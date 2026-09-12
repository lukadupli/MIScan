"""Dataset loading for corner regression.

Reads the labels.jsonl + meta.json format that both synth.py and smartdoc.py
write, and turns it into (image tensor, 8-value target) pairs for PyTorch.

The one idea worth understanding here is the coordinate normalisation, because
it is what makes resizing safe.
"""

from __future__ import annotations

import json
import random
from pathlib import Path

import cv2
import numpy as np
import torch
from torch.utils.data import Dataset

from common import IMAGENET_MEAN, IMAGENET_STD, INPUT_SIZE

_RESAMPLE = {
    "area": cv2.INTER_AREA,
    # _EXACT maps output pixel centres onto the source, as the phone does;
    # plain INTER_NEAREST uses corners and lands half a pixel off.
    "nearest": cv2.INTER_NEAREST_EXACT,
}


def to_rotated_cw(points: np.ndarray) -> np.ndarray:
    """Normalised (x, y) in a frame -> the same points once the frame is
    rotated 90 degrees clockwise: the left edge becomes the top."""
    return np.stack([1.0 - points[:, 1], points[:, 0]], axis=1).astype(points.dtype)


def from_rotated_cw(points: np.ndarray) -> np.ndarray:
    """Inverse of to_rotated_cw."""
    return np.stack([points[:, 1], 1.0 - points[:, 0]], axis=1).astype(points.dtype)


def _crop_origin(row: dict, aspect: float) -> int | None:
    """Left edge of a full-height crop of width/height `aspect` that contains
    the whole document, centred on it; None if the document is too wide.
    Frames already narrower than `aspect` are not cropped (origin 0)."""
    width, height = row["width"], row["height"]
    crop_w = round(height * aspect)
    if crop_w >= width:
        return 0
    xs = np.asarray(row["corners"], dtype=np.float64).reshape(4, 2)[:, 0]
    if xs.max() - xs.min() > crop_w:
        return None
    x0 = round((xs.min() + xs.max()) / 2 - crop_w / 2)
    x0 = min(max(x0, 0), width - crop_w)
    # Rounding can shave a corner by a pixel; that still counts as inside.
    if xs.min() < x0 - 1 or xs.max() > x0 + crop_w + 1:
        return None
    return x0


class CornerDataset(Dataset):
    """Images plus their four corners, normalised to [0, 1] of the source frame.

    Why normalised coordinates rather than pixels:

    The network sees a 224x224 image, but the source frames are 640x480 (synth)
    or 1920x1080 (SmartDoc). If targets were in pixels, the same physical corner
    would carry a different number depending on which dataset it came from, and
    the network would have to infer the source resolution to make sense of it.

    Dividing by the source width and height removes that entirely -- and, more
    usefully, makes the target *invariant to the resize*. Squash a whole frame to
    224x224 and a corner that sat 30% across the frame still sits 30% across the
    resized image. The label needs no adjustment at all. That only holds because
    we resize the entire frame rather than cropping; crop-based augmentation
    would require transforming the labels to match, which is exactly the class of
    bug that trains to a plausible loss on wrong data.

    The resize does distort aspect ratio (640x480 and 1920x1080 both become
    square). That is fine and deliberate: the distortion is deterministic, the
    network sees it consistently, and the app undoes it by mapping the predicted
    normalised coordinates back onto the original image's own dimensions.
    """

    def __init__(
        self,
        dirs: list[Path] | Path,
        input_size: tuple[int, int] = INPUT_SIZE,  # (H, W)
        augment: bool = False,
        limit: int | None = None,
        masks: bool = False,
        crop_aspect: float | None = None,
        rotate_cw: bool = False,
        resample: str = "area",
    ) -> None:
        """The last three reproduce how the phone feeds the network, for eval:

        crop_aspect  crop each frame horizontally to this width/height ratio,
                     centred on the document, and drop frames whose document is
                     wider than the crop. 4/3 turns SmartDoc's 16:9 into what
                     the phone's camera delivers.
        rotate_cw    rotate the frame 90 degrees clockwise before resizing --
                     an upright portrait phone frame squashed into the
                     landscape input, which is what the live path does today.
                     Targets are rotated to match, so they stay in the frame
                     the network saw.
        resample     'area' (training's filter) or 'nearest' (pixel-centre
                     nearest neighbour, what yuv_to_tensor.cpp does).
        """
        if resample not in _RESAMPLE:
            raise ValueError(f"resample must be one of {sorted(_RESAMPLE)}")
        self.input_size = input_size
        self.augment = augment
        self.masks = masks
        self.crop_aspect = crop_aspect
        self.rotate_cw = rotate_cw
        self.resample = resample
        self.records: list[dict] = []

        for directory in [dirs] if isinstance(dirs, Path) else dirs:
            directory = Path(directory)
            meta_path = directory / "meta.json"
            meta = json.loads(meta_path.read_text()) if meta_path.exists() else {}
            images_root = directory / meta.get("images_root", "")
            masks_root = directory / meta.get("masks_root", "")

            labels_path = directory / "labels.jsonl"
            if not labels_path.exists():
                raise FileNotFoundError(f"{labels_path} not found -- generate the dataset first")

            with labels_path.open() as handle:
                for line in handle:
                    row = json.loads(line)
                    path = Path(row["file"])
                    row["_path"] = path if path.is_absolute() else images_root / path
                    row.setdefault("source", meta.get("source", "unknown"))
                    if masks:
                        if "mask" not in row:
                            raise ValueError(
                                f"{labels_path} has no 'mask' field -- it predates mask "
                                "output; regenerate with the current synth.py"
                            )
                        mask_path = Path(row["mask"])
                        row["_mask_path"] = (
                            mask_path if mask_path.is_absolute() else masks_root / mask_path
                        )
                    self.records.append(row)

        if crop_aspect is not None:
            self.dropped_by_crop = 0
            kept = []
            for row in self.records:
                x0 = _crop_origin(row, crop_aspect)
                if x0 is None:
                    self.dropped_by_crop += 1
                else:
                    row["_crop_x0"] = x0
                    kept.append(row)
            self.records = kept

        if limit is not None:
            self.records = self.records[:limit]
        if not self.records:
            raise ValueError(f"no records loaded from {dirs}")

    def __len__(self) -> int:
        return len(self.records)

    def __getitem__(self, index: int) -> tuple[torch.Tensor, torch.Tensor]:
        row = self.records[index]

        img = cv2.imread(str(row["_path"]), cv2.IMREAD_COLOR)
        if img is None:
            raise RuntimeError(f"could not read {row['_path']}")
        img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

        corners = np.asarray(row["corners"], dtype=np.float32).reshape(4, 2)
        corners[:, 0] /= row["width"]
        corners[:, 1] /= row["height"]

        mask = None
        if self.masks:
            mask = cv2.imread(str(row["_mask_path"]), cv2.IMREAD_GRAYSCALE)
            if mask is None:
                raise RuntimeError(f"could not read {row['_mask_path']}")

        if "_crop_x0" in row:
            x0 = row["_crop_x0"]
            crop_w = min(round(row["height"] * self.crop_aspect), row["width"])
            if img.shape[:2] != (row["height"], row["width"]):
                raise RuntimeError(f"{row['_path']} is not the size its label says")
            img = img[:, x0 : x0 + crop_w]
            if mask is not None:
                mask = mask[:, x0 : x0 + crop_w]
            corners[:, 0] = (corners[:, 0] * row["width"] - x0) / crop_w
        if self.rotate_cw:
            img = np.ascontiguousarray(np.rot90(img, k=-1))
            if mask is not None:
                mask = np.ascontiguousarray(np.rot90(mask, k=-1))
            corners = to_rotated_cw(corners)

        # cv2.resize takes (width, height); input_size is (height, width).
        img = cv2.resize(img, self.input_size[::-1], interpolation=_RESAMPLE[self.resample])
        if mask is not None:
            # INTER_NEAREST, then threshold: the label should stay a hard
            # decision per pixel. INTER_AREA would blur the boundary into
            # intermediate values that the loss then treats as genuine
            # uncertainty rather than as a resampling artefact.
            mask = cv2.resize(mask, self.input_size[::-1], interpolation=cv2.INTER_NEAREST)
            mask = (mask >= 128).astype(np.float32)

        if self.augment:
            img = _photometric_augment(img)
            if mask is not None:
                img, mask = _geometric_augment(img, mask)

        # HWC uint8 -> CHW float, normalised. The channel order (RGB), the
        # normalisation constants and the layout all have to match what the C++
        # does on device; see common.py.
        tensor = torch.from_numpy(img).float().div_(255.0).permute(2, 0, 1)
        mean = torch.tensor(IMAGENET_MEAN).view(3, 1, 1)
        std = torch.tensor(IMAGENET_STD).view(3, 1, 1)
        tensor = (tensor - mean) / std

        if mask is not None:
            return tensor, torch.from_numpy(mask).unsqueeze(0)
        return tensor, torch.from_numpy(corners.reshape(8))


def _geometric_augment(img: np.ndarray, mask: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Flips, applied to image and mask together. Mask targets only.

    This is the augmentation the corner-regression path could not have (see
    _photometric_augment below). A mask transforms by exactly the same operation
    as its image, so there is no separate label transform to get subtly wrong --
    the class of bug that docstring warns about cannot occur here.

    Flips rather than arbitrary rotation, for two reasons: synth.py now samples
    roll across the full +/- 90, so document orientation is already covered
    physically correctly, with the perspective that a real rolled camera would
    produce; and a k*90 rotation would transpose a non-square input, which does
    not survive batching. Horizontal and vertical flips compose to give 180
    degrees, cost nothing, and preserve the shape.

    A mirrored page is not physically realistic -- the text reads backwards --
    but nothing here is asked to read text, only to find where the paper stops.
    """
    if random.random() < 0.5:
        img, mask = np.fliplr(img), np.fliplr(mask)
    if random.random() < 0.5:
        img, mask = np.flipud(img), np.flipud(mask)
    # flips return views with negative strides; torch.from_numpy rejects those.
    return np.ascontiguousarray(img), np.ascontiguousarray(mask)


def _photometric_augment(img: np.ndarray) -> np.ndarray:
    """Appearance-only augmentation: brightness, contrast, blur, noise.

    Deliberately nothing geometric *for the corner path*. Flips, crops and
    rotations would all move the corners, so every one of them would need a
    matching label transform -- and a geometric augmentation whose label
    transform is subtly wrong is invisible in the loss curve and fatal to the
    result. synth.py already supplies geometric variety by construction, at the
    point where the labels come for free. See _geometric_augment above for what
    a mask target makes safe.
    """
    out = img.astype(np.float32)
    out = out * random.uniform(0.8, 1.2) + random.uniform(-20, 20)

    if random.random() < 0.3:
        out = np.clip(out, 0, 255).astype(np.uint8)
        k = random.choice([3, 5])
        out = cv2.GaussianBlur(out, (k, k), 0).astype(np.float32)

    if random.random() < 0.4:
        out += np.random.normal(0, random.uniform(2, 8), out.shape)

    return np.clip(out, 0, 255).astype(np.uint8)


def denormalize(corners: np.ndarray, width: int, height: int) -> np.ndarray:
    """[0,1] model output -> pixel coordinates in an image of this size.

    The inverse of the normalisation above, and the exact operation the Dart side
    performs before writing into FrameController.corners.
    """
    out = np.asarray(corners, dtype=np.float64).reshape(4, 2).copy()
    out[:, 0] *= width
    out[:, 1] *= height
    return out
