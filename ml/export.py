"""Export a trained model to ONNX, and prove the export did not change it.

The parity check is the point of this file. Almost every "the model works in
Python but returns nonsense on the phone" bug is introduced between training and
inference -- a wrong channel order, normalisation applied twice, an operator the
converter silently approximated. Comparing PyTorch against onnxruntime on
identical input localises that to one of two sides before any C++ exists.

If parity passes and the phone still misbehaves, the fault is in the C++
preprocessing, not the model. That is worth a great deal when debugging.

Usage:
    python ml/export.py --checkpoint runs/best.pt
    python ml/export.py --checkpoint runs/best.pt --out ../assets/models/corners.onnx
    python ml/export.py --self-test          # exports an untrained net, checks the path works
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import onnx
import torch

from common import INPUT_SIZE
from model import CornerNet, DocSegNet

# opset 17 is widely supported by ONNX Runtime Mobile and covers everything a
# plain conv net needs. Raising it gains nothing here and risks the mobile build
# not implementing a newer operator.
OPSET = 17

# The onnxruntime Flutter plugin bundles a mobile ORT build that has been
# observed to reject IR version 10 ("Unsupported model IR version: 10, max
# supported IR version: 9") even though desktop onnxruntime -- what
# check_parity() below uses -- reads it fine. That gap is exactly why this
# constant exists: parity passing is not proof the phone can load the file.
MAX_MOBILE_IR_VERSION = 9

DEFAULT_OUT = Path(__file__).resolve().parents[1] / "assets" / "models" / "corners.onnx"


def export(
    model: torch.nn.Module,
    out_path: Path,
    size: tuple[int, int] = INPUT_SIZE,
    output_name: str = "corners",
    dynamic: bool = False,
) -> None:
    """Write the model to ONNX with a fixed 1x3xHxW input.

    Static shapes on purpose. Dynamic batch would be one line more, but the app
    only ever runs a single frame, and fixed shapes let the runtime plan memory
    once at session creation -- which matters for the live-preview path, where
    the session is created once and reused across frames.

    `dynamic=True` frees the two spatial axes, and exists for one job: the
    Phase 0 resolution sweep, where one session is fed several input sizes to
    time them against each other. Do not ship it. ORT optimises a dynamic graph
    less aggressively and re-plans memory whenever the shape changes, so its
    numbers are only good for comparing sizes -- once a size is chosen, re-export
    statically at that size and re-measure.
    """
    out_path.parent.mkdir(parents=True, exist_ok=True)
    model.eval().cpu()
    height, width = size
    dummy = torch.zeros(1, 3, height, width)

    torch.onnx.export(
        model,
        dummy,
        str(out_path),
        input_names=["image"],
        output_names=[output_name],
        opset_version=OPSET,
        do_constant_folding=True,
        dynamic_axes=(
            {"image": {2: "height", 3: "width"}, output_name: {2: "height", 3: "width"}}
            if dynamic
            else None
        ),
        # Critical for how the app loads this. torch's exporter defaults to
        # external_data=True, which writes the graph to model.onnx and the
        # weights to a sibling model.onnx.data -- 4 KB and 4.3 MB respectively.
        # The app reads the model out of a Flutter asset as one byte buffer and
        # hands it to ORT's CreateSessionFromArray, so there is no filesystem
        # for a sibling file to live on, and a Flutter asset is not a real path
        # anyway. Weights must be inline in the single file we ship.
        external_data=False,
        # torch's default (dynamo=True) exporter writes ONNX IR version 10.
        # The desktop onnxruntime used by check_parity() below happily reads
        # that, so it says nothing about whether the phone can -- and the
        # onnxruntime Flutter plugin bundles a mobile ORT build that maxes out
        # at IR version 9 and fails to load the file at all. The legacy
        # TorchScript-based exporter (dynamo=False) writes IR version 8 for
        # the same opset and graph, which both runtimes accept.
        dynamo=False,
    )

    size_mb = out_path.stat().st_size / 1e6
    print(f"wrote {out_path}  ({size_mb:.2f} MB)")

    # A graph-only file is a few KB. Catch it here rather than on the phone.
    sidecar = out_path.with_suffix(out_path.suffix + ".data")
    if sidecar.exists():
        raise SystemExit(f"weights landed in {sidecar}; external_data did not take effect")
    ir_version = onnx.load(out_path).ir_version
    if ir_version > MAX_MOBILE_IR_VERSION:
        raise SystemExit(
            f"IR version {ir_version} exceeds the mobile runtime's max of "
            f"{MAX_MOBILE_IR_VERSION}; the phone will fail to load this file "
            "even though it is valid ONNX. Re-export with dynamo=False."
        )

    expected_mb = sum(p.numel() for p in model.parameters()) * 4 / 1e6
    if size_mb < 0.5 * expected_mb:
        raise SystemExit(
            f"{size_mb:.2f} MB is far below the ~{expected_mb:.2f} MB the weights "
            "alone need; the file does not contain them"
        )


def check_parity(model: torch.nn.Module, onnx_path: Path, trials: int = 8) -> float:
    """Run the same inputs through PyTorch and onnxruntime; return the worst gap.

    Random inputs rather than real images on purpose: random values exercise the
    whole numeric range, where a real photo occupies a narrow band and can hide a
    discrepancy that only shows on unusual input.
    """
    import onnxruntime as ort

    model.eval().cpu()
    session = ort.InferenceSession(str(onnx_path), providers=["CPUExecutionProvider"])
    input_name = session.get_inputs()[0].name

    # Take the shape from the file rather than from INPUT_SIZE, so this checks
    # the graph that was actually written even when export() was told a
    # different size. A dynamic export reports its free axes as strings, and
    # there is no single right answer for those -- fall back to the contract.
    shape = session.get_inputs()[0].shape
    height, width = (d if isinstance(d, int) else s for d, s in zip(shape[2:], INPUT_SIZE))

    worst = 0.0
    for _ in range(trials):
        x = np.random.randn(1, 3, height, width).astype(np.float32)
        with torch.no_grad():
            torch_out = model(torch.from_numpy(x)).numpy()
        onnx_out = session.run(None, {input_name: x})[0]
        worst = max(worst, float(np.abs(torch_out - onnx_out).max()))

    return worst


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path, default=None)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="export a freshly initialised model to a temp path; validates the "
        "export and parity machinery without needing a trained checkpoint",
    )
    parser.add_argument(
        "--arch",
        choices=["corner", "seg"],
        default="corner",
        help="which architecture --self-test should instantiate",
    )
    parser.add_argument(
        "--size",
        type=int,
        nargs=2,
        metavar=("H", "W"),
        default=None,
        help=f"input height and width (default: {INPUT_SIZE[0]} {INPUT_SIZE[1]})",
    )
    parser.add_argument(
        "--dynamic",
        action="store_true",
        help="free the spatial axes. For the resolution sweep only -- see export(). "
        "Never ship a graph exported this way.",
    )
    parser.add_argument("--tolerance", type=float, default=1e-4)
    args = parser.parse_args()

    size = tuple(args.size) if args.size else INPUT_SIZE

    if args.self_test:
        model = DocSegNet() if args.arch == "seg" else CornerNet()
        out_path = Path(f"/tmp/{args.arch}_selftest.onnx")
    elif args.checkpoint:
        model = torch.load(args.checkpoint, map_location="cpu", weights_only=False)
        if isinstance(model, dict):
            raise SystemExit("checkpoint holds a state_dict; save the whole module instead")
        out_path = args.out
    else:
        parser.error("pass --checkpoint, or --self-test")

    is_seg = isinstance(model, DocSegNet)
    export(
        model,
        out_path,
        size=size,
        output_name="mask" if is_seg else "corners",
        dynamic=args.dynamic,
    )

    worst = check_parity(model, out_path)
    print(f"parity: worst absolute difference over 8 random inputs = {worst:.3e}")
    if worst < args.tolerance:
        print(f"PASS -- ONNX matches PyTorch within {args.tolerance:g}")
    else:
        raise SystemExit(
            f"FAIL -- difference {worst:.3e} exceeds {args.tolerance:g}.\n"
            "The exported graph is not the model you trained. Do not ship it."
        )


if __name__ == "__main__":
    main()
