"""Metrics for corner regression, and a CLI to run them over a dataset.

Two numbers matter, and they answer different questions:

  corner error   how far off each corner is, as a percentage of the image
                 diagonal. Resolution-independent, so a 640x480 synthetic frame
                 and a 1920x1080 SmartDoc frame are directly comparable. This is
                 the number that tells you whether a user has to drag anything.

  quad IoU       overlap between the predicted and true quadrilaterals, the
                 SmartDoc competition's own metric (they call it Jaccard index).
                 Worth reporting because it is what published results use, so it
                 is the only way to know whether your model is any good relative
                 to the field.

They can disagree, and the disagreement is informative: one badly-placed corner
on an otherwise correct quad barely moves IoU but shows clearly in mean corner
error. IoU alone would hide exactly the failure a user notices.

Usage:
    python ml/eval.py --checkpoint runs/best.pt --data data/smartdoc/test
    python ml/eval.py --checkpoint runs/best.pt --data data/synth_val --by source
"""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path

import numpy as np
import torch
from torch.utils.data import DataLoader

from common import describe_device, get_device
from dataset import CornerDataset, from_rotated_cw
from postprocess import mask_to_quad


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------


def polygon_area(poly: np.ndarray) -> float:
    """Shoelace area of a polygon given as (N, 2)."""
    if len(poly) < 3:
        return 0.0
    x, y = poly[:, 0], poly[:, 1]
    return 0.5 * abs(float(np.sum(x * np.roll(y, -1) - np.roll(x, -1) * y)))


def clip_convex(subject: np.ndarray, clip: np.ndarray) -> np.ndarray:
    """Intersect two convex polygons (Sutherland-Hodgman).

    Twenty lines instead of a shapely dependency, and it is exact for the convex
    case, which is all we ever have -- a document quadrilateral that is not
    convex is a broken prediction, and `polygon_iou` reports 0 for those anyway.

    The algorithm: walk each edge of the clip polygon and cut the subject against
    the infinite line through it, keeping whatever lies on the inside. Repeating
    that for all edges leaves exactly the intersection.
    """
    def inside(p: np.ndarray, a: np.ndarray, b: np.ndarray) -> bool:
        return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]) >= 0

    def intersect(p: np.ndarray, q: np.ndarray, a: np.ndarray, b: np.ndarray) -> np.ndarray:
        d1, d2 = q - p, b - a
        denom = d1[0] * d2[1] - d1[1] * d2[0]
        if abs(denom) < 1e-12:
            return q
        t = ((a[0] - p[0]) * d2[1] - (a[1] - p[1]) * d2[0]) / denom
        return p + t * d1

    # Both polygons must wind the same way for the inside test to agree.
    if _signed_area(subject) < 0:
        subject = subject[::-1]
    if _signed_area(clip) < 0:
        clip = clip[::-1]

    output = list(subject)
    for i in range(len(clip)):
        a, b = clip[i], clip[(i + 1) % len(clip)]
        current, output = output, []
        if not current:
            break
        prev = current[-1]
        for point in current:
            if inside(point, a, b):
                if not inside(prev, a, b):
                    output.append(intersect(prev, point, a, b))
                output.append(point)
            elif inside(prev, a, b):
                output.append(intersect(prev, point, a, b))
            prev = point

    return np.array(output) if output else np.empty((0, 2))


def _signed_area(poly: np.ndarray) -> float:
    x, y = poly[:, 0], poly[:, 1]
    return 0.5 * float(np.sum(x * np.roll(y, -1) - np.roll(x, -1) * y))


def polygon_iou(pred: np.ndarray, true: np.ndarray) -> float:
    """Intersection over union of two quadrilaterals."""
    pred = np.asarray(pred, dtype=np.float64).reshape(4, 2)
    true = np.asarray(true, dtype=np.float64).reshape(4, 2)

    inter = polygon_area(clip_convex(pred, true))
    union = polygon_area(pred) + polygon_area(true) - inter
    return float(inter / union) if union > 1e-12 else 0.0


def corner_error(pred: np.ndarray, true: np.ndarray) -> float:
    """Mean distance between corresponding corners, as a fraction of the diagonal.

    Both inputs are in normalised [0, 1] coordinates, so the diagonal of the unit
    square (sqrt(2)) is the reference length. Multiply by 100 for a percentage.

    Taken as the best of the four cyclic shifts. Corner order is canonicalised
    by image position (corner 0 = nearest the frame's top-left), and now that
    roll is sampled across the full +/- 90 there are poses where two corners sit
    almost equidistant from that origin -- so prediction and ground truth can
    canonicalise to starts one apart on quadrilaterals that are otherwise on top
    of each other. Without the shift that scores as a large error, which is a
    labelling artefact rather than anything the user would see. Winding is
    already fixed by canonicalisation, so shifts alone are enough.
    """
    pred = np.asarray(pred, dtype=np.float64).reshape(4, 2)
    true = np.asarray(true, dtype=np.float64).reshape(4, 2)
    return min(
        float(np.mean(np.linalg.norm(np.roll(pred, shift, axis=0) - true, axis=1)) / np.sqrt(2.0))
        for shift in range(4)
    )


# ---------------------------------------------------------------------------
# Evaluation
# ---------------------------------------------------------------------------


@torch.no_grad()
def evaluate(
    model: torch.nn.Module,
    dataset: CornerDataset,
    device: torch.device,
    batch_size: int = 64,
    group_by: str | None = None,
    task: str = "corner",
    group_fn=None,
) -> dict:
    """Run the model over a dataset and summarise both metrics.

    `task="seg"` routes the model's mask through postprocess.mask_to_quad first,
    so both tasks are scored by the same corner_error / polygon_iou on the same
    corner labels -- which is the only way the two architectures' numbers mean
    the same thing.
    """
    model.eval().to(device)
    loader = DataLoader(dataset, batch_size=batch_size, shuffle=False, num_workers=2)

    errors: list[float] = []
    ious: list[float] = []
    misses = 0
    groups: dict[str, list[tuple[float, float]]] = defaultdict(list)

    index = 0
    for images, targets in loader:
        raw = model(images.to(device)).cpu().numpy()
        trues = targets.numpy()
        for output, true in zip(raw, trues):
            if task == "seg":
                mask = np.squeeze(output)
                quad = mask_to_quad(mask, logits=True)
                if quad is None:
                    # No plausible document. Counted as a miss and scored as
                    # zero overlap, which is what it is; left out of the corner
                    # error, where there is no value to average.
                    misses += 1
                    ious.append(0.0)
                    if group_by:
                        key = group_fn(dataset.records[index]) if group_fn else str(
                            dataset.records[index].get(group_by, "?")
                        )
                        groups[key].append((float("nan"), 0.0))
                    index += 1
                    continue
                # mask_to_quad works in mask pixels; targets are normalised.
                pred = quad / np.array([mask.shape[1], mask.shape[0]], dtype=np.float64)
            else:
                pred = output

            if getattr(dataset, "rotate_cw", False):
                # Score in the unrotated frame, so corner error is normalised
                # by the same axes whichever way the network was fed. (IoU is
                # unaffected either way: it is invariant under this map.)
                pred = from_rotated_cw(np.asarray(pred, dtype=np.float64).reshape(4, 2))
                true = from_rotated_cw(np.asarray(true, dtype=np.float64).reshape(4, 2))

            err = corner_error(pred, true)
            iou = polygon_iou(pred, true)
            errors.append(err)
            ious.append(iou)
            if group_by:
                key = group_fn(dataset.records[index]) if group_fn else str(
                    dataset.records[index].get(group_by, "?")
                )
                groups[key].append((err, iou))
            index += 1

    errors_arr, ious_arr = np.array(errors), np.array(ious)
    result = {
        "count": len(ious),
        "detected": len(errors),
        "misses": misses,
        "corner_error_pct_mean": 100 * float(errors_arr.mean()),
        "corner_error_pct_median": 100 * float(np.median(errors_arr)),
        "corner_error_pct_p90": 100 * float(np.percentile(errors_arr, 90)),
        "iou_mean": float(ious_arr.mean()),
        "iou_median": float(np.median(ious_arr)),
        # The competition threshold convention: fraction of frames above 0.9 IoU.
        "iou_over_0.90": float((ious_arr > 0.90).mean()),
        "iou_over_0.95": float((ious_arr > 0.95).mean()),
    }
    if group_by:
        result["groups"] = {
            key: {
                "count": len(values),
                # nanmean: a miss contributes its IoU of 0 but has no corner
                # error, and must not drag the group's error to nan.
                "corner_error_pct_mean": 100 * float(np.nanmean([v[0] for v in values])),
                "iou_mean": float(np.mean([v[1] for v in values])),
                "misses": int(sum(1 for v in values if np.isnan(v[0]))),
            }
            for key, values in sorted(groups.items())
        }
    return result


def print_report(result: dict) -> None:
    print(f"\n  frames evaluated       {result['count']}")
    if result.get("misses"):
        print(
            f"  no document found      {result['misses']} "
            f"({100 * result['misses'] / max(result['count'], 1):.1f}%)"
        )
        print("                         (scored as IoU 0; excluded from corner error)")
    print("\n  corner error (% of image diagonal, lower is better)")
    print(f"    mean                 {result['corner_error_pct_mean']:.2f}%")
    print(f"    median               {result['corner_error_pct_median']:.2f}%")
    print(f"    90th percentile      {result['corner_error_pct_p90']:.2f}%")
    print("\n  quad IoU (higher is better)")
    print(f"    mean                 {result['iou_mean']:.4f}")
    print(f"    median               {result['iou_median']:.4f}")
    print(f"    frames over 0.90     {100 * result['iou_over_0.90']:.1f}%")
    print(f"    frames over 0.95     {100 * result['iou_over_0.95']:.1f}%")

    if "groups" in result:
        print("\n  by group")
        width = max(len(k) for k in result["groups"])
        for key, stats in result["groups"].items():
            print(
                f"    {key:<{width}}  n={stats['count']:<6} "
                f"err={stats['corner_error_pct_mean']:.2f}%  IoU={stats['iou_mean']:.4f}"
            )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--data", type=Path, nargs="+", required=True)
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--device", default=None)
    parser.add_argument(
        "--by",
        default=None,
        metavar="FIELD",
        help="break results down by a label field, e.g. 'background' or 'modeltype'. "
        "'document' is computed from the video name; 'seen' needs --holdout-from",
    )
    parser.add_argument(
        "--task",
        choices=["corner", "seg"],
        default="corner",
        help="'seg' pipes the predicted mask through postprocess.mask_to_quad "
        "before scoring, so both tasks are judged on the same corner labels",
    )
    parser.add_argument(
        "--holdout-from",
        type=Path,
        default=None,
        metavar="TRAIN_DIR",
        help="a training dataset directory; reads its meta.json 'excluded_documents' "
        "so '--by seen' can separate pages the model trained on from pages it never "
        "saw. The SmartDoc test set reuses the same 30 documents this project warps "
        "for synthetic training, so without this the score silently mixes the two.",
    )
    parser.add_argument("--limit", type=int, default=None)
    # How the phone feeds the network, to measure what each choice costs.
    parser.add_argument(
        "--crop-aspect",
        default=None,
        metavar="W:H",
        help="crop frames to this aspect around the document (e.g. 4:3, the "
        "phone camera's), dropping frames whose document does not fit",
    )
    parser.add_argument(
        "--view",
        choices=["landscape", "portrait"],
        default="landscape",
        help="'portrait' rotates each frame 90 degrees first, as the live path "
        "does with an upright phone before squashing into the landscape input",
    )
    parser.add_argument(
        "--resample",
        choices=["area", "nearest"],
        default="area",
        help="downscale filter; 'nearest' is what yuv_to_tensor.cpp does",
    )
    args = parser.parse_args()

    device = get_device(args.device)
    print(f"device: {describe_device(device)}")

    # Checkpoints store the whole module so eval does not need to know the
    # architecture -- convenient while you are still changing model.py.
    model = torch.load(args.checkpoint, map_location=device, weights_only=False)
    if isinstance(model, dict):
        raise SystemExit(
            "checkpoint holds a state_dict, not a module; "
            "construct your model and load_state_dict into it, then re-save"
        )

    # Corner mode even for --task seg: the mask is what the model predicts, but
    # the corner labels are what both architectures are scored against.
    crop_aspect = None
    if args.crop_aspect:
        w, h = (float(v) for v in args.crop_aspect.split(":"))
        crop_aspect = w / h
    dataset = CornerDataset(
        list(args.data),
        augment=False,
        limit=args.limit,
        crop_aspect=crop_aspect,
        rotate_cw=args.view == "portrait",
        resample=args.resample,
    )
    print(f"dataset: {len(dataset)} frames from {', '.join(str(d) for d in args.data)}")
    if crop_aspect is not None:
        print(f"cropped to {args.crop_aspect}; {dataset.dropped_by_crop} frames dropped "
              "(document wider than the crop)")
    print(f"view: {args.view}, resample: {args.resample}")

    group_fn = None
    if args.by in ("document", "seen"):
        def document_of(row: dict) -> str:
            # smartdoc.py writes video as "background01/datasheet001"
            return Path(str(row.get("video", ""))).name or "?"

        if args.by == "document":
            group_fn = document_of
        else:
            if not args.holdout_from:
                raise SystemExit("--by seen needs --holdout-from pointing at the training set")
            meta = json.loads((args.holdout_from / "meta.json").read_text())
            held = set(meta.get("excluded_documents", []))
            if not held:
                raise SystemExit(
                    f"{args.holdout_from}/meta.json lists no excluded_documents, so every "
                    "test page was trained on and there is no unseen split to report"
                )
            print(f"held out of training: {', '.join(sorted(held))}")
            group_fn = lambda row: "unseen" if document_of(row) in held else "seen"

    print_report(
        evaluate(model, dataset, device, args.batch_size, args.by, args.task, group_fn)
    )


if __name__ == "__main__":
    main()
