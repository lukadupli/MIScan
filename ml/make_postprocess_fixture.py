"""Write the fixture that pins lib/debug/mask_to_quad.dart to postprocess.py.

The mask->quad algorithm exists twice: here in numpy, so eval.py can score a
model, and in Dart, so the phone can act on one. Two implementations of the
same geometry drift, and when they do the SmartDoc number quietly stops
predicting what the app does -- which is the one thing that number is for.

So this generates masks, runs the Python side over them, and records what it
produced. test/mask_to_quad_test.dart replays the same masks through the Dart
side and requires the same answers.

Run after changing either implementation:
    python ml/make_postprocess_fixture.py
    flutter test test/mask_to_quad_test.dart
"""

from __future__ import annotations

import json
from pathlib import Path

import cv2
import numpy as np

from common import INPUT_SIZE
from postprocess import mask_to_quad

OUT = Path(__file__).resolve().parents[1] / "test" / "mask_to_quad_fixture.json"


def rle(binary: np.ndarray) -> list[int]:
    """Run lengths, alternating, starting with a run of zeros.

    Flat masks are mostly two big constant regions, so this turns ~77k values
    into a few hundred and keeps the fixture readable.
    """
    flat = binary.reshape(-1).astype(np.uint8)
    runs: list[int] = []
    current = 0
    count = 0
    for value in flat:
        if value == current:
            count += 1
        else:
            runs.append(count)
            current = value
            count = 1
    runs.append(count)
    return runs


def filled_quad(corners: np.ndarray, height: int, width: int) -> np.ndarray:
    mask = np.zeros((height, width), dtype=np.uint8)
    cv2.fillConvexPoly(mask, corners.astype(np.int32), 255)
    return mask


def main() -> None:
    height, width = INPUT_SIZE
    cases: list[dict] = []

    # Hand-built quads: an upright page, a steeply rolled one (the case the old
    # corner regressor could not be trained for), a small one, a perspective
    # trapezoid, and one running off the frame edge.
    named = {
        "upright": np.array([[60, 40], [260, 40], [260, 200], [60, 200]]),
        "rolled_40deg": np.array([[150, 20], [290, 130], [175, 225], [35, 115]]),
        "small": np.array([[190, 150], [250, 145], [255, 200], [195, 205]]),
        "trapezoid": np.array([[90, 45], [235, 55], [285, 195], [40, 190]]),
        "clipped_edge": np.array([[-30, 40], [240, 30], [250, 210], [-20, 220]]),
    }
    for name, corners in named.items():
        mask = filled_quad(corners, height, width)
        quad = mask_to_quad(mask)
        cases.append(
            {
                "name": name,
                "runs": rle(mask >= 128),
                "expected": None if quad is None else quad.tolist(),
            }
        )

    # A blank frame must come back as "no document" rather than a guess.
    cases.append(
        {
            "name": "empty",
            "runs": rle(np.zeros((height, width), dtype=bool)),
            "expected": None,
        }
    )

    # Two blobs: the small decoy must not drag the hull away from the page.
    both = filled_quad(named["upright"], height, width)
    cv2.rectangle(both, (295, 215), (315, 235), 255, -1)
    quad = mask_to_quad(both)
    cases.append(
        {
            "name": "decoy_blob",
            "runs": rle(both >= 128),
            "expected": None if quad is None else quad.tolist(),
        }
    )

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(
        json.dumps({"height": height, "width": width, "cases": cases}, indent=1)
    )
    print(f"wrote {OUT} ({OUT.stat().st_size / 1000:.0f} KB, {len(cases)} cases)")
    for case in cases:
        got = case["expected"]
        summary = "None" if got is None else ", ".join(f"({p[0]:.0f},{p[1]:.0f})" for p in got)
        print(f"  {case['name']:<14} -> {summary}")


if __name__ == "__main__":
    main()
