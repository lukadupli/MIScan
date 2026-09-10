"""Turn a predicted document mask into four corners.

This is the half of the segmentation approach that is not a network. The model
says which pixels are page; this file decides where the quadrilateral is, and
in which order its corners come out.

Written in plain numpy on purpose -- no cv2. The same algorithm has to run on
the phone, where there is no OpenCV and the native layer is hand-written
(ml/requirements.txt: "The on-device code stays dependency-free"). Keeping this
to loops and arithmetic that map one-to-one onto Dart makes that port a
transcription rather than a reimplementation, which is the difference between
the two staying in agreement and quietly drifting apart.

The pipeline, and why each step is there:

    threshold          the model emits logits; pick the page pixels
    largest component  a stray blob elsewhere in the frame would drag the hull
                       out to meet it, so keep only the biggest connected one
    boundary pixels    the hull only depends on the outline, and this is ~1000
                       points instead of ~50000
    convex hull        a document is convex; this discards ragged edge noise
    simplify           a hull of a quad has many collinear-ish vertices along
                       each side; reduce to the four that matter
    canonicalise       fix winding and starting corner

Returning None rather than a guess is deliberate: a mask that does not reduce
to a sane quadrilateral is the model telling us it did not find a document,
which is a signal the old 8-number regression could not express -- it always
emitted four corners whether or not it had seen anything.
"""

from __future__ import annotations

import numpy as np

from synth import canonicalize_corners


def largest_component(binary: np.ndarray) -> np.ndarray:
    """Keep only the biggest 4-connected blob of True pixels.

    Flood fill over flat indices with an explicit stack: no recursion (masks are
    big enough to blow the stack) and no scipy, so the Dart side can mirror it.
    """
    h, w = binary.shape
    flat = binary.reshape(-1)
    seen = np.zeros(flat.size, dtype=bool)

    best_label: list[int] = []
    best_size = 0

    for start in np.flatnonzero(flat):
        if seen[start]:
            continue
        stack = [int(start)]
        seen[start] = True
        component = []
        while stack:
            idx = stack.pop()
            component.append(idx)
            y, x = divmod(idx, w)
            if x > 0 and flat[idx - 1] and not seen[idx - 1]:
                seen[idx - 1] = True
                stack.append(idx - 1)
            if x < w - 1 and flat[idx + 1] and not seen[idx + 1]:
                seen[idx + 1] = True
                stack.append(idx + 1)
            if y > 0 and flat[idx - w] and not seen[idx - w]:
                seen[idx - w] = True
                stack.append(idx - w)
            if y < h - 1 and flat[idx + w] and not seen[idx + w]:
                seen[idx + w] = True
                stack.append(idx + w)
        if len(component) > best_size:
            best_size = len(component)
            best_label = component

    out = np.zeros(flat.size, dtype=bool)
    if best_label:
        out[np.asarray(best_label)] = True
    return out.reshape(h, w)


def boundary_points(binary: np.ndarray) -> np.ndarray:
    """(N, 2) array of (x, y) for pixels on the blob's edge.

    A pixel is on the edge if it is set and at least one 4-neighbour is not --
    counting the outside of the frame as not set, so a page running off the
    frame still contributes its clipped edge.
    """
    padded = np.zeros((binary.shape[0] + 2, binary.shape[1] + 2), dtype=bool)
    padded[1:-1, 1:-1] = binary
    interior = (
        padded[1:-1, 1:-1]
        & padded[:-2, 1:-1]
        & padded[2:, 1:-1]
        & padded[1:-1, :-2]
        & padded[1:-1, 2:]
    )
    ys, xs = np.nonzero(binary & ~interior)
    return np.stack([xs, ys], axis=1).astype(np.float64)


def convex_hull(points: np.ndarray) -> np.ndarray:
    """Andrew's monotone chain. Returns hull vertices counter-clockwise in
    screen coordinates (y down), without the closing repeat."""
    if len(points) < 3:
        return points
    order = np.lexsort((points[:, 1], points[:, 0]))
    pts = points[order]

    def half(seq):
        out: list[np.ndarray] = []
        for p in seq:
            while len(out) >= 2 and _cross(out[-2], out[-1], p) <= 0:
                out.pop()
            out.append(p)
        return out[:-1]

    hull = half(pts) + half(pts[::-1])
    return np.asarray(hull, dtype=np.float64)


def _cross(o: np.ndarray, a: np.ndarray, b: np.ndarray) -> float:
    """Z of (a-o) x (b-o). Same orientation primitive as lib/frame.dart's ccw()."""
    return float((a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]))


def _point_line_distance(p: np.ndarray, a: np.ndarray, b: np.ndarray) -> float:
    ab = b - a
    length = float(np.hypot(ab[0], ab[1]))
    if length < 1e-9:
        return float(np.hypot(*(p - a)))
    ap = p - a
    return abs(float(ab[0] * ap[1] - ab[1] * ap[0])) / length


def _douglas_peucker(points: np.ndarray, epsilon: float) -> np.ndarray:
    """Simplify an open polyline, keeping both endpoints."""
    if len(points) < 3:
        return points
    dists = [_point_line_distance(points[i], points[0], points[-1]) for i in range(1, len(points) - 1)]
    worst = int(np.argmax(dists)) + 1
    if dists[worst - 1] <= epsilon:
        return np.stack([points[0], points[-1]])
    left = _douglas_peucker(points[: worst + 1], epsilon)
    right = _douglas_peucker(points[worst:], epsilon)
    return np.concatenate([left[:-1], right])


def simplify_closed(hull: np.ndarray, epsilon: float) -> np.ndarray:
    """Douglas-Peucker around a closed polygon.

    Split at the two furthest-apart vertices first: on a closed ring there is no
    natural pair of endpoints to anchor the recursion, and anchoring at an
    arbitrary vertex can delete a real corner that happens to sit next to it.
    """
    if len(hull) <= 4:
        return hull
    diffs = hull[:, None, :] - hull[None, :, :]
    far = np.unravel_index(int(np.argmax((diffs ** 2).sum(-1))), (len(hull), len(hull)))
    i, j = sorted(far)
    first = _douglas_peucker(hull[i : j + 1], epsilon)
    second = _douglas_peucker(np.concatenate([hull[j:], hull[: i + 1]]), epsilon)
    return np.concatenate([first[:-1], second[:-1]])


def _quad_area(quad: np.ndarray) -> float:
    x, y = quad[:, 0], quad[:, 1]
    return 0.5 * abs(float(np.sum(x * np.roll(y, -1) - np.roll(x, -1) * y)))


def largest_quadrilateral(hull: np.ndarray) -> np.ndarray | None:
    """Pick the 4 hull vertices enclosing the most area.

    Used when simplification does not land on exactly four. Brute force over
    combinations, which is only affordable because it runs on an already
    simplified hull of a few dozen points at most.
    """
    n = len(hull)
    if n < 4:
        return None
    best, best_area = None, -1.0
    for a in range(n - 3):
        for b in range(a + 1, n - 2):
            for c in range(b + 1, n - 1):
                for d in range(c + 1, n):
                    quad = hull[[a, b, c, d]]
                    area = _quad_area(quad)
                    if area > best_area:
                        best_area, best = area, quad
    return best


def mask_to_quad(
    mask: np.ndarray,
    threshold: float = 0.5,
    min_area_fraction: float = 0.01,
    logits: bool = False,
    stats: dict | None = None,
) -> np.ndarray | None:
    """Mask (H, W) -> (4, 2) corners in pixel coordinates, or None.

    Pass `logits=True` for raw model output. This is an explicit flag rather
    than a guess from the value range: a uint8 mask read off disk spans 0-255,
    which any "looks unbounded, must be logits" heuristic would silently
    sigmoid into nonsense.

    Pass a dict as `stats` to have the path taken recorded into it -- the same
    fields lib/debug/mask_to_quad.dart's MaskToQuadStats records, so offline
    and on-device diagnostics mean the same thing. It observes only; the
    result is identical either way.
    """
    if stats is None:
        stats = {}
    stats.update(path="", hull_size=0, fallback_ran=False, fallback_n=0)

    if mask.ndim != 2:
        mask = np.squeeze(mask)
    mask = mask.astype(np.float64)
    if logits:
        mask = 1.0 / (1.0 + np.exp(-mask))
    elif mask.max() > 1.0:
        mask = mask / 255.0  # uint8 mask straight off disk

    binary = mask >= threshold
    if binary.sum() < min_area_fraction * binary.size:
        stats["path"] = "reject:empty"
        return None

    blob = largest_component(binary)
    points = boundary_points(blob)
    if len(points) < 4:
        stats["path"] = "reject:few-points"
        return None

    hull = convex_hull(points)
    stats["hull_size"] = len(hull)
    if len(hull) < 4:
        stats["path"] = "reject:small-hull"
        return None

    # Epsilon relative to the blob's own scale, so it behaves the same on a
    # page filling the frame and one occupying a corner of it.
    scale = float(np.sqrt(_quad_area(hull) if len(hull) >= 3 else 0.0)) or 1.0
    quad = None
    for factor in (0.02, 0.04, 0.01, 0.08, 0.005):
        simplified = simplify_closed(hull, factor * scale)
        if len(simplified) == 4:
            quad = simplified
            stats["path"] = f"eps{factor}"
            break
    if quad is None:
        candidates = simplify_closed(hull, 0.02 * scale)
        stats["fallback_ran"] = True
        stats["fallback_n"] = len(candidates)
        quad = largest_quadrilateral(candidates)
        stats["path"] = "fallback"
    if quad is None or _quad_area(quad) < min_area_fraction * mask.size:
        stats["path"] = "reject:tiny-quad"
        return None

    # Same ordering rule the labels use, so predictions and ground truth are
    # directly comparable without a second convention to keep in sync.
    return canonicalize_corners(quad)
