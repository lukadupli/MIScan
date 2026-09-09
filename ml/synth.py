"""Synthetic training data for the corner detector.

Generates (image, 4 corners) pairs by taking a flat document image, projecting it
through a pinhole camera onto a random background, and recording where its corners
landed. Labels are exact and free, which is the whole point -- hand-labelling tens
of thousands of photos is not a project, it's a job.

The camera model is a deliberate port of native/test/synthetic_scene.h. That file
projects a known 3D rectangle through a pinhole camera to test that QuadTransform
can invert it. Here we use the *same forward model* to build training data, so the
network learns to invert exactly the projection the C++ assumes. If the two ever
disagree, the network will be systematically wrong in a way no amount of training
fixes.

Usage:
    python ml/synth.py --out data/synth_train --count 20000
    python ml/synth.py --out data/synth_val   --count 2000 --seed 1
    python ml/synth.py --out /tmp/peek --count 12 --visualize
"""

from __future__ import annotations

import argparse
import json
import math
import random
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np

from common import ensure_dirs, set_seed

# Output frame the synthetic photo is rendered into. Kept a bit larger than the
# model's 224x224 input so downstream resizing has something to work with and we
# are not baking the network's input size into the dataset.
FRAME_W, FRAME_H = 640, 480

# Pose sampling limits. These are the knobs that shape the dataset -- run with
# --stats after changing any of them to see what actually came out.
MAX_ROLL_DEG = 90.0  # in-plane rotation cap; see sample_scene for why 90 covers everything
MIN_AREA_FRACTION = 0.04  # below this the page is too small to localise reliably
MAX_AREA_FRACTION = 1.30  # above this the page is mostly outside the frame
MIN_CORNERS_IN_FRAME = 2  # some corners off-frame is wanted; all four is not
MAX_POSE_ATTEMPTS = 400  # rejection-sampling budget per sample
CROP_SLACK = 0.015  # how far past the frame edge a page may drift, as a frame fraction


# ===========================================================================
# The projection maths
# ===========================================================================
# The first two functions are near-direct ports of native/test/synthetic_scene.h
# (lines 33-65); the third is the design decision that actually determines
# whether this dataset is any good.


@dataclass
class Scene:
    """A document rectangle in 3D plus where its corners land in the picture.

    Mirrors `SyntheticScene` in native/test/synthetic_scene.h.
    """

    height: float  # camera height h; camera sits at (0, 0, h)
    normal: np.ndarray  # unit normal of the document plane
    center: np.ndarray  # document centre in 3D (its z is negative)
    axis_u: np.ndarray  # unit vectors spanning the document plane
    axis_v: np.ndarray
    half_width: float
    half_height: float
    principal_point: np.ndarray  # where picture (0,0) sits relative to the camera axis
    corners: np.ndarray  # shape (4, 2) -- projected corners in pixel coords
    roll: float = 0.0  # in-plane rotation applied, radians (kept for --stats)
    corners_z: np.ndarray | None = None  # 3D z of each corner, for validity checks

    @property
    def true_aspect(self) -> float:
        return self.half_width / self.half_height


def project_through_camera(point: np.ndarray, height: float) -> np.ndarray:
    """Project a 3D point through a pinhole camera at (0, 0, height) onto z = 0.

    Port of `projectThroughCamera`, synthetic_scene.h:33-37.

    The ray runs from the camera through `point`; we want where it crosses the
    picture plane z = 0. Solving `height + t * dir.z == 0` gives the step t.

    The sign is the whole subtlety. With `t = height / (height - point.z)` and a
    document at negative z, the picture plane sits *between* camera and document
    and the image comes out upright. Flip that sign and you get the physically
    literal pinhole camera -- film behind the aperture, image inverted through a
    180-degree point reflection. This codebase uses the upright convention (the
    standard computer-vision "virtual image plane"), and QuadTransform assumes it.
    """
    t = height / (height - point[2])
    return np.array([t * point[0], t * point[1], 0.0])


def make_scene(
    camera_height: float,
    tilt_x: float,
    tilt_y: float,
    roll: float,
    document_center: np.ndarray,
    half_width: float,
    half_height: float,
    principal_point: np.ndarray,
) -> Scene:
    """Build a document rectangle in 3D and project its four corners.

    Port of `makeScene`, synthetic_scene.h:42-65.

    Steps, all of them one-liners:
      1. normal  = unit vector of (tilt_x, tilt_y, 1)
      2. axis_u  = unit(cross(normal, (0, 1, 0)))    -- an in-plane direction
         axis_v  = unit(cross(normal, axis_u))       -- perpendicular to both
      3. roll that frame about the normal by `roll` radians (see below)
      4. the four corners in 3D are
             center -/+ half_width * axis_u -/+ half_height * axis_v
         in the sign order  (-,-), (+,-), (+,+), (-,+)
      5. project each through the camera and add `principal_point`

    Why cross products give you the in-plane axes is worth a minute's thought:
    `cross(normal, anything)` is perpendicular to `normal`, so it necessarily
    lies *in* the plane. The second cross then gives you the in-plane direction
    perpendicular to the first. Two perpendicular in-plane unit vectors is
    exactly a coordinate frame for the document.

    Step 3 is the one the C++ does not have, and it exists because step 2 alone
    is not general. `cross(normal, (0,1,0))` has a structurally zero y-component
    -- crossing with the y axis annihilates it -- so it always lands on the one
    frame whose u-axis is horizontal in the world. That is a *gauge choice*: the
    plane admits a whole one-parameter family of valid frames related by rotation
    about the normal, and the C++ only ever needed one member of it because every
    property its tests check (height, normal, aspect) is rotation-invariant. We
    need the family, or the model never sees a page held even slightly askew.

    Since u, v and n are orthonormal, rotating about n is just a plain 2D rotation
    within the (u, v) basis -- no Rodrigues formula required:

        u_rolled =  cos(roll) * u + sin(roll) * v
        v_rolled = -sin(roll) * u + cos(roll) * v

    Store the projected corners into `Scene.corners` as a (4, 2) float array,
    dropping the z (which is 0 by construction). Do not worry about which corner
    ends up first -- keep the sign order above so opposite corners stay opposite,
    and `canonicalize_corners` settles the ordering downstream.
    """
    def unit(v: np.ndarray) -> np.ndarray:
        return v / np.linalg.norm(v)

    normal = unit(np.array([tilt_x, tilt_y, 1.0]))

    # An arbitrary-but-consistent in-plane frame, then rolled to the angle we want.
    axis_u = unit(np.cross(normal, np.array([0.0, 1.0, 0.0])))
    axis_v = unit(np.cross(normal, axis_u))
    cos_r, sin_r = math.cos(roll), math.sin(roll)
    axis_u, axis_v = (
        cos_r * axis_u + sin_r * axis_v,
        -sin_r * axis_u + cos_r * axis_v,
    )

    signs = ((-1, -1), (+1, -1), (+1, +1), (-1, +1))
    corners_3d = [
        document_center + su * half_width * axis_u + sv * half_height * axis_v
        for su, sv in signs
    ]
    projected = [project_through_camera(c, camera_height) + principal_point for c in corners_3d]

    return Scene(
        height=camera_height,
        normal=normal,
        center=document_center,
        axis_u=axis_u,
        axis_v=axis_v,
        half_width=half_width,
        half_height=half_height,
        principal_point=principal_point,
        corners=np.array([[p[0], p[1]] for p in projected], dtype=np.float64),
        roll=roll,
        corners_z=np.array([c[2] for c in corners_3d], dtype=np.float64),
    )


def sample_scene(rng: random.Random, frame_w: int, frame_h: int) -> Scene:
    """Randomly draw one plausible camera pose and document.

    This is the real design work in stage 1, and it is not a port -- the C++ only
    ever needed a handful of hand-picked poses for tests, whereas you need a
    *distribution* that covers how people actually photograph pages.

    Things to sample, and the questions to ask yourself for each:
      - camera_height: this is the focal length in pixels. What field of view does
        a phone camera have? (Hint: for a frame `frame_w` wide, height ~= 0.9 to
        1.4 * frame_w lands in the right ballpark.)
      - tilt_x, tilt_y: how far off-perpendicular do people hold a phone? Small
        values mean near-square-on. Note that BOTH near zero is the case the
        native QuadTransform can't recover height from (see CLAUDE.md), so it is
        worth over-sampling mild tilts rather than centring on zero.
      - document_center: negative z (in front of the picture plane), with x/y
        offsets so the page is not always dead centre.
      - roll: in-plane rotation, in radians, sampled across the full +/- 90.
        This used to be capped at +/- 25, and the reason was never realism: the
        old corner-regression target was canonicalised by image position
        (corner 0 = nearest the frame's top-left), so near 45 degrees two
        corners sit almost equidistant from it and a tiny pose change flips the
        label. That is a discontinuity in the target function, and networks
        cannot fit those -- they average across the jump and get both sides
        wrong. The segmentation target has no corner ordering to flip, so the
        discontinuity is gone and the cap with it; corner ordering is now
        decided in postprocessing, where it is plain geometry.
        +/- 90 is the *complete* range, not a partial one: a rectangle rolled
        by 180 degrees produces an identical mask, so [-90, 90] already covers
        every distinct appearance exactly once.
      - half_width / half_height: pick an aspect ratio. A4 is 1:1.414, US Letter
        1:1.294, but people scan receipts and book pages too. Sample both
        portrait and landscape.

    Constraint to enforce before returning: all four projected corners must land
    somewhere sane relative to the frame. Reject and redraw if the page is
    entirely off-screen or fills less than, say, 15% of it. A page that fills
    2% of the frame teaches the network nothing except to predict the mean.

    Deliberately allow *some* corners off-frame -- users do crop pages at the
    edge, and a model that has never seen it will fail badly there.
    """
    principal_point = np.array([frame_w / 2.0, frame_h / 2.0, 0.0])
    last = None

    for _ in range(MAX_POSE_ATTEMPTS):
        # Focal length in pixels. ~1.0 * frame_w is a typical phone field of view;
        # the spread covers wide-angle through slight telephoto.
        camera_height = rng.uniform(0.85, 1.45) * frame_w

        # Tilt away from square-on. Sampled from a half-normal so mild tilts are
        # common and extreme ones rare, but deliberately floored away from zero:
        # a perfectly square-on page is the degenerate case where QuadTransform
        # cannot recover camera height at all (CLAUDE.md), so it is not a case
        # worth over-representing.
        tilt_mag = min(abs(rng.gauss(0.0, 0.26)) + 0.02, 0.85)
        tilt_dir = rng.uniform(0.0, 2.0 * math.pi)
        tilt_x = tilt_mag * math.cos(tilt_dir)
        tilt_y = tilt_mag * math.sin(tilt_dir)

        roll = math.radians(rng.uniform(-MAX_ROLL_DEG, MAX_ROLL_DEG))
        cos_r_px, sin_r_px = math.cos(roll), math.sin(roll)

        # Depth of the page below the picture plane. Together with camera_height
        # this fixes the magnification m = h / (h + d): a world length L at depth
        # d covers L * m pixels. We invert that below to size the page in pixels
        # rather than in meaningless world units.
        depth = rng.uniform(0.7, 2.2) * camera_height
        magnification = camera_height / (camera_height + depth)

        # Aspect ratios people actually photograph: A4 and Letter dominate, with
        # a broad band covering receipts, book pages, cards and notebooks. The
        # jitter on the standard sizes keeps the histogram from spiking into two
        # delta functions the model could latch onto.
        if rng.random() < 0.5:
            aspect = rng.choice([1.414, 1.294]) * rng.uniform(0.97, 1.03)
        else:
            aspect = rng.uniform(1.05, 2.4)
        portrait = rng.random() < 0.65

        # Size the page relative to the largest one that would actually fit at
        # this aspect and roll, rather than to a flat share of the frame. Those
        # are very different: a portrait A4 in a 640x480 landscape frame tops out
        # near 0.53 of the frame area before its long side runs off the top and
        # bottom, so asking for 0.8 just guarantees a crop every time. Scaling by
        # the feasible maximum makes `fill` mean the same thing for every page
        # shape, and lets fill > 1 deliberately produce the cropped captures we
        # do want a minority of.
        half_w_unit, half_h_unit = (1.0, aspect) if portrait else (aspect, 1.0)
        rot_w_unit = abs(half_w_unit * cos_r_px) + abs(half_h_unit * sin_r_px)
        rot_h_unit = abs(half_w_unit * sin_r_px) + abs(half_h_unit * cos_r_px)
        scale_to_fit = min(0.5 * frame_w / rot_w_unit, 0.5 * frame_h / rot_h_unit)

        # Deliberately wide, and the width is the point.
        #
        # This was first tuned to a 0.39 median area fraction on the assumption
        # that real captures fill most of the frame. Measuring SmartDoc showed
        # its pages occupy 0.08 / 0.12 / 0.16 at p10 / p50 / p90 -- about three
        # times smaller. SmartDoc is video preview frames rather than composed
        # photographs, so the app's own inputs likely sit between the two, and
        # matching either one exactly would leave the model blind at the other
        # scale. This range spans roughly 0.07 to 0.50, covering both.
        #
        # Re-check with --stats after touching this, and compare against the
        # real distribution rather than against intuition.
        fill = rng.uniform(0.30, 1.10)
        half_w_px = half_w_unit * scale_to_fit * fill
        half_h_px = half_h_unit * scale_to_fit * fill

        half_width = half_w_px / magnification
        half_height = half_h_px / magnification

        # Off-centre the page. A fixed fraction of the frame does not work here:
        # once the page covers half the frame, a 15% shove puts two corners
        # outside every time. Scale the offset by the room actually left instead,
        # measured on the roll-rotated bounding box, plus a small slack so that
        # partially-cropped pages still occur -- they do in real captures, and a
        # model that has never seen one fails badly at the frame edge.
        rot_half_w = abs(half_w_px * cos_r_px) + abs(half_h_px * sin_r_px)
        rot_half_h = abs(half_w_px * sin_r_px) + abs(half_h_px * cos_r_px)
        room_x = max(0.0, frame_w / 2.0 - rot_half_w)
        room_y = max(0.0, frame_h / 2.0 - rot_half_h)
        offset_x_px = rng.uniform(-1.0, 1.0) * (0.85 * room_x + CROP_SLACK * frame_w)
        offset_y_px = rng.uniform(-1.0, 1.0) * (0.85 * room_y + CROP_SLACK * frame_h)

        offset_x = offset_x_px / magnification
        offset_y = offset_y_px / magnification
        document_center = np.array([offset_x, offset_y, -depth])

        scene = make_scene(
            camera_height=camera_height,
            tilt_x=tilt_x,
            tilt_y=tilt_y,
            roll=roll,
            document_center=document_center,
            half_width=half_width,
            half_height=half_height,
            principal_point=principal_point,
        )
        last = scene
        if _pose_is_usable(scene, frame_w, frame_h):
            return scene

    # Rejection sampling should essentially always succeed; falling through means
    # the ranges above drifted out of step with the acceptance test. Surface it
    # rather than silently poisoning the dataset with degenerate samples.
    raise RuntimeError(
        f"sample_scene: no usable pose in {MAX_POSE_ATTEMPTS} attempts; "
        f"last quad area fraction was {_area_fraction(last.corners, frame_w, frame_h):.3f}"
    )


def _area_fraction(corners: np.ndarray, frame_w: int, frame_h: int) -> float:
    """Quad area as a fraction of the frame, via the shoelace formula."""
    x, y = corners[:, 0], corners[:, 1]
    area = 0.5 * abs(float(np.sum(x * np.roll(y, -1) - np.roll(x, -1) * y)))
    return area / (frame_w * frame_h)


def _pose_is_usable(scene: Scene, frame_w: int, frame_h: int) -> bool:
    """Reject poses that are degenerate, off-screen, or teach nothing."""
    corners = scene.corners
    if not np.all(np.isfinite(corners)):
        return False

    # Every corner must sit in front of the picture plane. A corner that creeps
    # above z = 0 is past the plane's horizon: the projection's denominator
    # changes sign and the corner is flung to the far side of the image. This is
    # the failure CLAUDE.md warns shows up as an absurd allocation rather than an
    # error, so it is worth catching at the source.
    if scene.corners_z is None or np.any(scene.corners_z >= -1e-9):
        return False

    fraction = _area_fraction(corners, frame_w, frame_h)
    if not MIN_AREA_FRACTION <= fraction <= MAX_AREA_FRACTION:
        return False

    # Some corners off-frame is wanted -- users do crop pages at the edge -- but
    # a quad defined almost entirely by extrapolated corners is not a useful
    # training signal.
    inside = int(
        np.sum(
            (corners[:, 0] >= 0)
            & (corners[:, 0] < frame_w)
            & (corners[:, 1] >= 0)
            & (corners[:, 1] < frame_h)
        )
    )
    if inside < MIN_CORNERS_IN_FRAME:
        return False

    centroid = corners.mean(axis=0)
    return 0 <= centroid[0] < frame_w and 0 <= centroid[1] < frame_h


# ===========================================================================
# MY PART -- ordering, rendering, augmentation, I/O
# ===========================================================================


def canonicalize_corners(corners: np.ndarray) -> np.ndarray:
    """Put four corners into the order the app expects, without moving them.

    The app needs two things from a corner list, and neither is 'corner 0 is the
    page's own top-left':
      - a consistent *winding*, which is what FrameController.isConvex() checks
        and what QuadTransform's loadCoordinates assumes, and
      - a stable rule for which corner comes first, so the network has a single
        well-defined target.

    So we fix both here rather than asking the network to learn them. Corner 0
    becomes whichever corner is nearest the frame's top-left, then the rest
    follow the winding -- reproducing the TL, TR, BR, BL order that frame.dart
    lays down by default (frame.dart:122-129).

    Which corner ends up first only determines the *rotation* of the final scan,
    and EditPage already has a rotate control, so there is nothing to gain from
    making the network infer true page orientation from its content.

    Note this cannot be made continuous: rotate a page through a full 360 and
    the set of corners returns to itself while each individual corner advances
    one position, so no continuous assignment rule exists. Every rule has a cut
    somewhere. Capping `roll` in sample_scene keeps the cut out of the data.
    """
    pts = np.asarray(corners, dtype=np.float64).reshape(4, 2)

    # Shoelace signed area. In image coordinates (y pointing down) a positive
    # value means clockwise on screen, which is the order frame.dart uses.
    area = 0.5 * float(
        np.sum(pts[:, 0] * np.roll(pts[:, 1], -1) - np.roll(pts[:, 0], -1) * pts[:, 1])
    )
    if area < 0:
        pts = pts[::-1]

    start = int(np.argmin(np.hypot(pts[:, 0], pts[:, 1])))
    return np.roll(pts, -start, axis=0)


class ImageBank:
    """A pool of source images, either preloaded or decoded on demand.

    The right strategy depends on the pool, and the two we use sit at opposite
    extremes:

      documents    ~150 files, 3507x2481 PNGs, each reused ~130 times in a 20k
                   run. Decoding costs over a tenth of a second, so decoding per
                   sample would add hours. Preload, downscaled -- at full size
                   they would need ~3.9 GB, against ~320 MB at a 1000px side.

      backgrounds  ~5,640 DTD files, roughly 640x480, each reused only about
                   three times. Preloading them all would take ~5 GB to save a
                   few milliseconds per sample. Decode on demand instead.

    Hence `eager`: preload when files are few, large and heavily reused; stream
    when they are many, small and barely reused.
    """

    def __init__(
        self,
        directory: Path,
        max_side: int = 1000,
        limit: int | None = None,
        eager: bool = True,
        exclude: set[str] | None = None,
    ) -> None:
        patterns = ("*.png", "*.jpg", "*.jpeg", "*.JPG", "*.PNG", "*.JPEG")
        paths = sorted({p for pattern in patterns for p in Path(directory).rglob(pattern)})
        if not paths:
            raise FileNotFoundError(f"no images found under {directory}")
        if exclude:
            kept = [p for p in paths if p.stem not in exclude]
            missing = exclude - {p.stem for p in paths}
            if missing:
                raise SystemExit(f"--exclude-docs names nothing under {directory}: {sorted(missing)}")
            paths = kept
        if limit:
            paths = paths[:limit]

        self.paths = paths
        self.max_side = max_side
        self.images: list[np.ndarray] | None = None

        if eager:
            self.images = [img for img in (self._load(p) for p in paths) if img is not None]
            if not self.images:
                raise RuntimeError(f"every image under {directory} failed to decode")

    def _load(self, path: Path) -> np.ndarray | None:
        img = cv2.imread(str(path), cv2.IMREAD_COLOR)
        if img is None:
            return None
        scale = self.max_side / max(img.shape[:2])
        if scale < 1.0:
            img = cv2.resize(img, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
        return img

    def __len__(self) -> int:
        return len(self.images) if self.images is not None else len(self.paths)

    def pick(self, rng: random.Random) -> np.ndarray:
        if self.images is not None:
            return self.images[rng.randrange(len(self.images))]
        # Streaming: retry past the occasional unreadable file rather than
        # failing a whole generation run for one bad JPEG.
        for _ in range(8):
            img = self._load(self.paths[rng.randrange(len(self.paths))])
            if img is not None:
                return img
        raise RuntimeError("could not decode any image from the bank")


def crop_to_frame(img: np.ndarray, rng: random.Random, w: int, h: int) -> np.ndarray:
    """Random crop/scale a background image to exactly (h, w).

    Scaling to cover and then cropping at a random offset gives many distinct
    backgrounds from one photo, and keeps the aspect ratio intact -- stretching
    would introduce a directional distortion the model could learn to key on.
    """
    scale = max(w / img.shape[1], h / img.shape[0]) * rng.uniform(1.0, 1.6)
    resized = cv2.resize(img, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
    max_x, max_y = resized.shape[1] - w, resized.shape[0] - h
    x0 = rng.randint(0, max(0, max_x))
    y0 = rng.randint(0, max(0, max_y))
    out = resized[y0 : y0 + h, x0 : x0 + w]
    if out.shape[0] != h or out.shape[1] != w:
        out = cv2.resize(out, (w, h), interpolation=cv2.INTER_AREA)
    return out


def make_placeholder_document(rng: random.Random, w: int = 850, h: int = 1100) -> np.ndarray:
    """A procedurally drawn 'page' so the pipeline runs before we source real data.

    Not good enough to train a shippable model on -- real scanned pages have
    photographs, tables, varied typography and paper tint. It is good enough to
    prove the geometry is right, which is all stage 1 needs.
    """
    tint = rng.randint(235, 255)
    page = np.full((h, w, 3), (tint, tint, rng.randint(tint - 5, 255)), dtype=np.uint8)

    margin = rng.randint(60, 110)
    y = margin
    while y < h - margin:
        if rng.random() < 0.12:  # paragraph break
            y += rng.randint(20, 45)
            continue
        line_w = int((w - 2 * margin) * rng.uniform(0.35, 1.0))
        thickness = rng.randint(6, 11)
        grey = rng.randint(40, 110)
        cv2.rectangle(page, (margin, y), (margin + line_w, y + thickness), (grey,) * 3, -1)
        y += thickness + rng.randint(8, 16)

    return page


def make_placeholder_background(rng: random.Random, w: int, h: int) -> np.ndarray:
    """A vaguely desk-like background: base colour, gradient, a little noise."""
    base = np.array([rng.randint(30, 160) for _ in range(3)], dtype=np.float32)
    bg = np.tile(base, (h, w, 1))

    gx = np.linspace(rng.uniform(0.6, 1.0), rng.uniform(0.6, 1.0), w, dtype=np.float32)
    gy = np.linspace(rng.uniform(0.6, 1.0), rng.uniform(0.6, 1.0), h, dtype=np.float32)
    bg *= (gy[:, None] * gx[None, :])[:, :, None]
    bg += np.random.normal(0, 6, bg.shape).astype(np.float32)

    return np.clip(bg, 0, 255).astype(np.uint8)


def render(
    document: np.ndarray, background: np.ndarray, corners: np.ndarray
) -> tuple[np.ndarray, np.ndarray]:
    """Warp `document` onto `corners` over `background`; return (composite, mask).

    The key fact making this cheap: projecting a *planar* rectangle through a
    pinhole camera is exactly a homography. So once `sample_scene` has told us
    where the four corners go, a single 3x3 matrix reproduces the whole page --
    we do not have to ray-trace anything. The pinhole model's job is only to
    constrain *which* quadrilaterals are physically possible; cv2 does the pixels.

    The mask is the page's alpha, which compositing needs anyway -- it is also
    exactly the segmentation label, so it is returned rather than thrown away.
    It comes back antialiased (0-255, soft only on the boundary) rather than
    hard 0/255; that keeps the sub-pixel edge coverage, and dataset.py can
    threshold it at load time if a strictly binary target is wanted.
    """
    h, w = document.shape[:2]
    src = np.array([[0, 0], [w - 1, 0], [w - 1, h - 1], [0, h - 1]], dtype=np.float32)
    matrix = cv2.getPerspectiveTransform(src, corners.astype(np.float32))

    frame_h, frame_w = background.shape[:2]
    warped = cv2.warpPerspective(document, matrix, (frame_w, frame_h), flags=cv2.INTER_LINEAR)

    # Warp a white page-shaped mask the same way to know which pixels are page.
    mask = cv2.warpPerspective(
        np.full((h, w), 255, np.uint8), matrix, (frame_w, frame_h), flags=cv2.INTER_LINEAR
    )
    alpha = (mask.astype(np.float32) / 255.0)[:, :, None]

    composite = (warped * alpha + background * (1 - alpha)).astype(np.uint8)
    return composite, mask


def augment(img: np.ndarray, rng: random.Random) -> np.ndarray:
    """Everything that varies between real phone photos but not between renders.

    Without this the network learns to detect 'crisp synthetic edge' rather than
    'document', and falls over on the first real photo. This is usually the
    difference between a synthetic model that transfers and one that doesn't.
    """
    out = img.astype(np.float32)

    # Soft directional shadow across the frame.
    if rng.random() < 0.7:
        h, w = out.shape[:2]
        yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
        angle = rng.uniform(0, 2 * math.pi)
        ramp = math.cos(angle) * xx / w + math.sin(angle) * yy / h
        ramp = (ramp - ramp.min()) / max(float(np.ptp(ramp)), 1e-6)
        out *= (1.0 - rng.uniform(0.0, 0.45) * ramp)[:, :, None]

    # Global brightness / contrast.
    out = out * rng.uniform(0.7, 1.25) + rng.uniform(-25, 25)

    # Slight white-balance drift -- indoor light is rarely neutral.
    out *= np.array([rng.uniform(0.92, 1.08) for _ in range(3)], dtype=np.float32)

    out = np.clip(out, 0, 255).astype(np.uint8)

    if rng.random() < 0.5:
        k = rng.choice([3, 5])
        out = cv2.GaussianBlur(out, (k, k), 0)

    if rng.random() < 0.6:
        out = out.astype(np.float32) + np.random.normal(0, rng.uniform(2, 9), out.shape)
        out = np.clip(out, 0, 255).astype(np.uint8)

    # Round-trip through JPEG so the network sees the same block artefacts the
    # app's own images carry.
    if rng.random() < 0.8:
        quality = rng.randint(45, 95)
        ok, buf = cv2.imencode(".jpg", out, [cv2.IMWRITE_JPEG_QUALITY, quality])
        if ok:
            out = cv2.imdecode(buf, cv2.IMREAD_COLOR)

    return out


def draw_quad(img: np.ndarray, corners: np.ndarray) -> np.ndarray:
    """Overlay the ground-truth quad, with corner 0 labelled, for --visualize.

    Corner *order* is the most common silent bug in this kind of pipeline -- an
    image can look perfectly warped while the labels are rotated one step, and
    the network will happily train to a plausible-looking loss on garbage. So
    the markers are numbered rather than just drawn.
    """
    out = img.copy()
    pts = corners.astype(np.int32)
    cv2.polylines(out, [pts], isClosed=True, color=(0, 255, 0), thickness=2)
    for i, (x, y) in enumerate(pts):
        cv2.circle(out, (int(x), int(y)), 6, (0, 0, 255), -1)
        cv2.putText(out, str(i), (int(x) + 8, int(y) - 8), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 255), 2)
    return out


def contact_sheet(samples: list[tuple[np.ndarray, np.ndarray]], cols: int = 4) -> np.ndarray:
    """Tile annotated samples into one image.

    Far more useful than flipping through files: problems in a *distribution* --
    pages always centred, tilts always the same way, quads clustering in one
    region -- are invisible one sample at a time and obvious in a grid.
    """
    cell_w, cell_h = 320, 240
    rows = (len(samples) + cols - 1) // cols
    sheet = np.full((rows * cell_h, cols * cell_w, 3), 24, np.uint8)

    for i, (img, corners) in enumerate(samples):
        scale = min(cell_w / img.shape[1], cell_h / img.shape[0])
        annotated = draw_quad(img, corners)
        resized = cv2.resize(annotated, (int(img.shape[1] * scale), int(img.shape[0] * scale)))
        r, c = divmod(i, cols)
        y0, x0 = r * cell_h, c * cell_w
        sheet[y0 : y0 + resized.shape[0], x0 : x0 + resized.shape[1]] = resized

    return sheet


def write_stats(scenes: list[Scene], corners: list[np.ndarray], out_path: Path) -> None:
    """Plot what the pose sampler actually produced.

    The sampling ranges in `sample_scene` are guesses about how people hold
    phones. These histograms are how you check the guesses turned into the
    distribution you meant -- and they are cheap insurance against a typo in a
    range quietly collapsing all the variety out of the dataset.
    """
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fracs = [_area_fraction(c, FRAME_W, FRAME_H) for c in corners]
    rolls = [math.degrees(s.roll) for s in scenes]
    tilts = [float(np.hypot(s.normal[0], s.normal[1]) / s.normal[2]) for s in scenes]
    aspects = [s.true_aspect for s in scenes]
    inside = [
        int(np.sum((c[:, 0] >= 0) & (c[:, 0] < FRAME_W) & (c[:, 1] >= 0) & (c[:, 1] < FRAME_H)))
        for c in corners
    ]

    fig, axes = plt.subplots(2, 3, figsize=(15, 8))
    for ax, (data, title, xlabel) in zip(
        axes.ravel(),
        [
            (fracs, "Page area / frame area", "fraction"),
            (rolls, "In-plane roll", "degrees"),
            (tilts, "Tilt magnitude (off square-on)", "|tilt| / 1"),
            (aspects, "Page aspect (width / height)", "w/h"),
            (inside, "Corners inside the frame", "count"),
        ],
    ):
        ax.hist(data, bins=30 if title != "Corners inside the frame" else [1, 2, 3, 4, 5], color="#4C78A8")
        ax.set_title(title)
        ax.set_xlabel(xlabel)

    # Where corners land, all samples overlaid -- shows dead zones the model
    # would never learn to predict into.
    ax = axes.ravel()[5]
    allc = np.concatenate(corners)
    ax.scatter(allc[:, 0], allc[:, 1], s=1, alpha=0.15, color="#E45756")
    ax.add_patch(plt.Rectangle((0, 0), FRAME_W, FRAME_H, fill=False, color="black", lw=1.5))
    ax.set_title("Corner positions (frame outlined)")
    ax.set_aspect("equal")
    ax.invert_yaxis()

    fig.tight_layout()
    fig.savefig(out_path, dpi=110)
    plt.close(fig)


def generate(
    out_dir: Path,
    count: int,
    seed: int,
    visualize: bool = False,
    grid: int = 0,
    stats: bool = False,
    documents: Path | None = None,
    exclude_docs: set[str] | None = None,
    backgrounds: Path | None = None,
) -> None:
    rng = random.Random(seed)
    set_seed(seed)

    doc_bank = (
        ImageBank(documents, max_side=1000, eager=True, exclude=exclude_docs)
        if documents
        else None
    )
    # max_side 800: backgrounds are cropped down to the 640x480 frame anyway, so
    # holding more resolution than that only slows the decode.
    bg_bank = ImageBank(backgrounds, max_side=800, eager=False) if backgrounds else None
    print(
        f"documents:   {len(doc_bank) if doc_bank else 'PLACEHOLDER (fake text)'}\n"
        f"backgrounds: {len(bg_bank) if bg_bank else 'PLACEHOLDER (gradients)'}"
    )
    if not (doc_bank and bg_bank):
        print(
            "  warning: placeholder sources train a model to find a bright rectangle\n"
            "  on a smooth gradient, which is not the same as finding a document."
        )

    images_dir = out_dir / "images"
    masks_dir = out_dir / "masks"
    ensure_dirs(out_dir, images_dir, masks_dir)

    sheet_samples: list[tuple[np.ndarray, np.ndarray]] = []
    stat_scenes: list[Scene] = []
    stat_corners: list[np.ndarray] = []

    labels_path = out_dir / "labels.jsonl"
    with labels_path.open("w") as labels:
        for i in range(count):
            scene = sample_scene(rng, FRAME_W, FRAME_H)
            corners = canonicalize_corners(scene.corners)
            document = doc_bank.pick(rng) if doc_bank else make_placeholder_document(rng)
            background = (
                crop_to_frame(bg_bank.pick(rng), rng, FRAME_W, FRAME_H)
                if bg_bank
                else make_placeholder_background(rng, FRAME_W, FRAME_H)
            )

            img, mask = render(document, background, corners)
            # augment() is photometric only -- no geometry -- so the mask stays
            # aligned with the image and must not be put through it.
            img = augment(img, rng)

            name = f"{i:06d}.jpg"
            mask_name = f"{i:06d}.png"  # lossless; JPEG would blur the boundary
            cv2.imwrite(str(images_dir / name), img)
            cv2.imwrite(str(masks_dir / mask_name), mask)
            labels.write(
                json.dumps(
                    {
                        "file": name,
                        "mask": mask_name,
                        "width": FRAME_W,
                        "height": FRAME_H,
                        # pixel coordinates, canonical order: corner 0 nearest
                        # the frame's top-left, then following the winding.
                        # Kept alongside the mask: eval.py still scores corner
                        # error, and it is what the old model is compared against.
                        "corners": corners.tolist(),
                        "aspect": scene.true_aspect,
                    }
                )
                + "\n"
            )

            if visualize:
                cv2.imwrite(str(out_dir / f"vis_{name}"), draw_quad(img, corners))
            if grid and len(sheet_samples) < grid:
                sheet_samples.append((img, corners))
            if stats:
                stat_scenes.append(scene)
                stat_corners.append(corners)

    # Same shape as the one smartdoc.py writes, so dataset.py can load either
    # source without caring which produced it.
    with (out_dir / "meta.json").open("w") as handle:
        json.dump(
            {
                "source": "synthetic",
                "images_root": "images",
                "masks_root": "masks",
                "count": count,
                "seed": seed,
                # Recorded so eval.py can split the SmartDoc score by whether the
                # page was in training, rather than being told the list twice and
                # risking the two drifting apart.
                "excluded_documents": sorted(exclude_docs) if exclude_docs else [],
            },
            handle,
            indent=2,
        )

    print(f"wrote {count} samples to {out_dir}")
    if visualize:
        print(f"  annotated previews: {out_dir}/vis_*.jpg")
    if grid and sheet_samples:
        path = out_dir / "grid.jpg"
        cv2.imwrite(str(path), contact_sheet(sheet_samples))
        print(f"  contact sheet:      {path}")
    if stats and stat_scenes:
        path = out_dir / "stats.png"
        write_stats(stat_scenes, stat_corners, path)
        print(f"  distributions:      {path}")

    if visualize or grid:
        print(
            "\nCheck, in order: quads sit on the page edges; corner 0 is the one\n"
            "nearest the frame's top-left; numbering runs 0->1->2->3 around the\n"
            "quad without crossing; page content is not mirrored."
        )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True, help="output dataset directory")
    parser.add_argument("--count", type=int, default=1000)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument(
        "--visualize",
        action="store_true",
        help="write one vis_*.jpg per sample with the ground-truth quad drawn on",
    )
    parser.add_argument(
        "--grid",
        type=int,
        nargs="?",
        const=16,
        default=0,
        metavar="N",
        help="write grid.jpg tiling N annotated samples (default 16)",
    )
    parser.add_argument(
        "--stats",
        action="store_true",
        help="write stats.png showing the pose/area/roll distributions actually generated",
    )
    parser.add_argument(
        "--documents",
        type=Path,
        default=None,
        metavar="DIR",
        help="directory of real page images to warp (recursive). Without it, "
        "procedurally drawn fake-text pages are used instead.",
    )
    parser.add_argument(
        "--backgrounds",
        type=Path,
        default=None,
        metavar="DIR",
        help="directory of real background photos (recursive). Without it, "
        "smooth colour gradients are used instead.",
    )
    parser.add_argument(
        "--exclude-docs",
        nargs="+",
        default=None,
        metavar="STEM",
        help="document filename stems to leave out (e.g. letter005 tax005). The "
        "SmartDoc test set is shot with the same 30 pages this generator warps, "
        "so a page used here is not unseen at eval time. Holding a few out lets "
        "eval.py report seen-vs-unseen separately and measure what that is worth.",
    )
    args = parser.parse_args()

    generate(
        args.out,
        args.count,
        args.seed,
        visualize=args.visualize,
        grid=args.grid,
        stats=args.stats,
        documents=args.documents,
        exclude_docs=set(args.exclude_docs) if args.exclude_docs else None,
        backgrounds=args.backgrounds,
    )


if __name__ == "__main__":
    main()
