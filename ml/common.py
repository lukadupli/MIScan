"""Shared helpers for the corner-detection training pipeline.

Deliberately thin: paths, reproducibility, device selection. Anything that
knows what a document or a corner is lives in the stage-specific modules.
"""

from __future__ import annotations

import os
import random
from pathlib import Path

import numpy as np
import torch

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
# Both of these are gitignored. Scripts accept overrides so the same code runs
# unchanged on Colab, where the filesystem looks nothing like this.

ML_ROOT = Path(__file__).resolve().parent
DATA_DIR = ML_ROOT / "data"
RUNS_DIR = ML_ROOT / "runs"

# ---------------------------------------------------------------------------
# Preprocessing contract
# ---------------------------------------------------------------------------
# These three values define what the network expects to be fed, and they have to
# hold in three places at once: here in training, in ml/export.py's parity check,
# and in the C++ preprocessing that runs on the phone. A mismatch in any of them
# produces a model that scores well in Python and returns nonsense on-device --
# the single most common way this kind of project fails. Change them here and
# nowhere else, then re-run the parity check.
#
# INPUT_SIZE is (height, width) and does not have to be square. It used to be a
# bare 224 because CornerNet ended in Linear(7*7*576, 8) -- a fixed-size flatten
# that structurally admits exactly one input size. The segmentation nets are
# fully convolutional and accept any spatial size (verified: square or not,
# multiple of 32 or not), returning a mask at exactly the input dims. So this is
# now a latency/precision dial rather than an architectural constant:
#   - bigger costs compute roughly in proportion to area,
#   - bigger preserves the edge detail the network localises against, which a
#     squash from 1920 wide destroys,
#   - matching the camera's 4:3 removes the aspect distortion a square input
#     forces the network to learn around.
INPUT_SIZE = (240, 320)  # (H, W) -- 4:3, matching the camera, so no aspect squash
IMAGENET_MEAN = (0.485, 0.456, 0.406)
IMAGENET_STD = (0.229, 0.224, 0.225)


def ensure_dirs(*paths: Path) -> None:
    for path in paths:
        path.mkdir(parents=True, exist_ok=True)


# ---------------------------------------------------------------------------
# Reproducibility
# ---------------------------------------------------------------------------


def set_seed(seed: int = 0) -> None:
    """Seed every RNG this project might touch.

    Worth being pedantic about, because the three stages use three different
    generators: the synthetic scene sampler uses numpy, the augmentation uses
    python's `random`, and the training loop uses torch. Seeding one of them
    gives you runs that look reproducible right up until they aren't.
    """
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)
    os.environ["PYTHONHASHSEED"] = str(seed)


# ---------------------------------------------------------------------------
# Device
# ---------------------------------------------------------------------------


def get_device(prefer: str | None = None) -> torch.device:
    """CUDA (Colab) -> MPS (Apple Silicon) -> CPU, unless overridden.

    `prefer` exists mainly for debugging: MPS occasionally lacks a kernel that
    CPU has, and forcing `--device cpu` is the fastest way to find out whether
    a strange result is your maths or the backend.
    """
    if prefer:
        return torch.device(prefer)
    if torch.cuda.is_available():
        return torch.device("cuda")
    if torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")


def describe_device(device: torch.device) -> str:
    if device.type == "cuda":
        return f"cuda ({torch.cuda.get_device_name(device)})"
    if device.type == "mps":
        return "mps (Apple Silicon GPU)"
    return "cpu"
