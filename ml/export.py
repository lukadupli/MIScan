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
import torch

from common import INPUT_SIZE
from model import CornerNet

# opset 17 is widely supported by ONNX Runtime Mobile and covers everything a
# plain conv net needs. Raising it gains nothing here and risks the mobile build
# not implementing a newer operator.
OPSET = 17

DEFAULT_OUT = Path(__file__).resolve().parents[1] / "assets" / "models" / "corners.onnx"


def export(model: torch.nn.Module, out_path: Path) -> None:
    """Write the model to ONNX with a fixed 1x3x224x224 input.

    Static shapes on purpose. Dynamic batch would be one line more, but the app
    only ever runs a single frame, and fixed shapes let the runtime plan memory
    once at session creation -- which matters for the live-preview path, where
    the session is created once and reused across frames.
    """
    out_path.parent.mkdir(parents=True, exist_ok=True)
    model.eval().cpu()
    dummy = torch.zeros(1, 3, INPUT_SIZE, INPUT_SIZE)

    torch.onnx.export(
        model,
        dummy,
        str(out_path),
        input_names=["image"],
        output_names=["corners"],
        opset_version=OPSET,
        do_constant_folding=True,
        # Critical for how the app loads this. torch's exporter defaults to
        # external_data=True, which writes the graph to model.onnx and the
        # weights to a sibling model.onnx.data -- 4 KB and 4.3 MB respectively.
        # The app reads the model out of a Flutter asset as one byte buffer and
        # hands it to ORT's CreateSessionFromArray, so there is no filesystem
        # for a sibling file to live on, and a Flutter asset is not a real path
        # anyway. Weights must be inline in the single file we ship.
        external_data=False,
    )

    size_mb = out_path.stat().st_size / 1e6
    print(f"wrote {out_path}  ({size_mb:.2f} MB)")

    # A graph-only file is a few KB. Catch it here rather than on the phone.
    sidecar = out_path.with_suffix(out_path.suffix + ".data")
    if sidecar.exists():
        raise SystemExit(f"weights landed in {sidecar}; external_data did not take effect")
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

    worst = 0.0
    for _ in range(trials):
        x = np.random.randn(1, 3, INPUT_SIZE, INPUT_SIZE).astype(np.float32)
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
        help="export a freshly initialised CornerNet to a temp path; validates the "
        "export and parity machinery without needing a trained checkpoint",
    )
    parser.add_argument("--tolerance", type=float, default=1e-4)
    args = parser.parse_args()

    if args.self_test:
        model = CornerNet()
        out_path = Path("/tmp/corners_selftest.onnx")
    elif args.checkpoint:
        model = torch.load(args.checkpoint, map_location="cpu", weights_only=False)
        if isinstance(model, dict):
            raise SystemExit("checkpoint holds a state_dict; save the whole module instead")
        out_path = args.out
    else:
        parser.error("pass --checkpoint, or --self-test")

    export(model, out_path)

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
