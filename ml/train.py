"""Training loop for the corner regressor.

Usage:
    # smoke test: a few hundred samples, two epochs, proves the wiring
    python ml/train.py --limit 512 --epochs 2

    # the real run
    python ml/train.py --epochs 40

    # resume from where a run stopped
    python ml/train.py --epochs 60 --resume runs/corners/last.pt

Watch `val corner err`, not the loss. The loss exists for the optimiser; the
corner error is in units you can reason about -- percent of image diagonal --
and is what decides whether the user has to drag anything.
"""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader

from common import RUNS_DIR, describe_device, get_device, set_seed
from dataset import CornerDataset
from eval import corner_error, polygon_iou
from model import CornerNet, DocSegNet


class SegLoss(nn.Module):
    """BCE plus soft Dice.

    BCE alone under-segments here: page pixels are the minority class, so
    predicting "background everywhere" is already a decent BCE score and the
    optimiser is happy to sit near it. Dice is computed on the overlap itself,
    which is scale-free with respect to class balance, so it keeps pushing once
    BCE has flattened out. Summing the two is the standard pairing -- BCE gives
    well-behaved per-pixel gradients early, Dice shapes the region later.
    """

    def __init__(self, dice_weight: float = 1.0) -> None:
        super().__init__()
        self.bce = nn.BCEWithLogitsLoss()
        self.dice_weight = dice_weight

    def forward(self, logits: torch.Tensor, target: torch.Tensor) -> torch.Tensor:
        probs = torch.sigmoid(logits)
        dims = (1, 2, 3)
        intersection = (probs * target).sum(dims)
        # +1 on both sides: keeps an all-empty prediction on an all-empty target
        # from being 0/0, and softens the gradient on tiny regions.
        dice = 1.0 - ((2.0 * intersection + 1.0) / (probs.sum(dims) + target.sum(dims) + 1.0))
        return self.bce(logits, target) + self.dice_weight * dice.mean()


def build_loaders(args) -> tuple[DataLoader, DataLoader]:
    masks = args.task == "seg"
    train_ds = CornerDataset(args.train, augment=True, limit=args.limit, masks=masks)
    val_ds = CornerDataset(args.val, augment=False, limit=args.limit, masks=masks)
    print(f"train: {len(train_ds)} samples from {args.train}")
    print(f"val:   {len(val_ds)} samples from {args.val}")

    # shuffle on train only -- sample order must not be a learnable signal.
    # persistent_workers keeps the worker processes alive between epochs;
    # without it they are torn down and respawned every epoch, which on 20k
    # small files costs more than the loading itself.
    common = dict(num_workers=args.workers, pin_memory=False)
    if args.workers > 0:
        common["persistent_workers"] = True

    return (
        DataLoader(train_ds, batch_size=args.batch_size, shuffle=True, drop_last=True, **common),
        DataLoader(val_ds, batch_size=2 * args.batch_size, shuffle=False, **common),
    )


@torch.no_grad()
def validate(model, loader, criterion, device) -> dict[str, float]:
    """One pass over validation: loss plus the two metrics that mean something."""
    model.eval()  # BatchNorm switches to running averages; forgetting this is a classic bug
    losses, errors, ious = [], [], []

    for images, targets in loader:
        images, targets = images.to(device), targets.to(device)
        preds = model(images)
        losses.append(criterion(preds, targets).item())

        preds_np, targets_np = preds.cpu().numpy(), targets.cpu().numpy()
        for pred, true in zip(preds_np, targets_np):
            errors.append(corner_error(pred, true))
            ious.append(polygon_iou(pred, true))

    return {
        "loss": float(np.mean(losses)),
        "corner_err_pct": 100 * float(np.mean(errors)),
        "iou": float(np.mean(ious)),
    }


@torch.no_grad()
def validate_seg(model, loader, criterion, device) -> dict[str, float]:
    """Validation for the mask task: loss plus mask IoU.

    Mask IoU, not quad IoU: this runs every epoch, and pushing every validation
    sample through postprocess.py to recover a quadrilateral would dominate the
    epoch time. Mask IoU tracks it closely enough to choose a checkpoint by.
    The quad numbers -- and the comparison against the old model -- come from
    eval.py, once, at the end.
    """
    model.eval()
    losses, intersections, unions = [], 0.0, 0.0

    for images, targets in loader:
        images, targets = images.to(device), targets.to(device)
        logits = model(images)
        losses.append(criterion(logits, targets).item())

        predicted = (torch.sigmoid(logits) >= 0.5).float()
        intersections += float((predicted * targets).sum())
        unions += float(((predicted + targets) >= 1).float().sum())

    return {
        "loss": float(np.mean(losses)),
        # Aggregated over all pixels rather than averaged per image: a frame
        # whose page is mostly out of shot has few page pixels and a noisy
        # per-image IoU, which a per-image mean would weight equally with a
        # full-frame page.
        "mask_iou": intersections / max(unions, 1.0),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--train", type=Path, default=Path("data/synth_train"))
    parser.add_argument("--val", type=Path, default=Path("data/synth_val"))
    parser.add_argument("--out", type=Path, default=RUNS_DIR / "corners")
    parser.add_argument("--epochs", type=int, default=40)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--weight-decay", type=float, default=0.01)
    parser.add_argument("--beta", type=float, default=0.03, help="Smooth L1 changeover point")
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--device", default=None)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--limit", type=int, default=None, help="cap samples per split (smoke test)")
    parser.add_argument("--resume", type=Path, default=None)
    parser.add_argument(
        "--task",
        choices=["corner", "seg"],
        default="corner",
        help="'corner' regresses 8 coordinates (CornerNet); 'seg' predicts a "
        "document mask (DocSegNet) and needs a dataset generated with masks",
    )
    args = parser.parse_args()

    set_seed(args.seed)
    device = get_device(args.device)
    print(f"device: {describe_device(device)}")

    args.out.mkdir(parents=True, exist_ok=True)
    train_loader, val_loader = build_loaders(args)

    fresh = DocSegNet if args.task == "seg" else CornerNet
    model = (
        torch.load(args.resume, map_location=device, weights_only=False)
        if args.resume
        else fresh()
    ).to(device)
    if args.resume:
        print(f"resumed from {args.resume}")

    if args.task == "seg":
        criterion = SegLoss()
    else:
        # beta must sit near the scale of the errors. Coordinates are normalised to
        # [0,1], so typical errors are ~0.01-0.05; the PyTorch default of 1.0 would
        # keep every sample in the quadratic branch and silently make this MSE.
        criterion = nn.SmoothL1Loss(beta=args.beta)

    # weight_decay stays on here, unlike overfit.py, where the goal was to
    # memorise. Here it is one of the things keeping the model from doing that.
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=args.weight_decay)

    # Cosine decay to near zero over the run. Large steps early to cover ground,
    # small ones late to settle -- with a fixed LR the model bounces around the
    # minimum instead of converging into it.
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=args.epochs)

    history: list[dict] = []
    best_score = float("inf")  # lower is better for both tasks; see `score` below
    is_seg = args.task == "seg"

    if is_seg:
        print(f"\n{'epoch':>5} {'lr':>9} {'train':>10} {'val':>10} {'mask IoU':>9} {'time':>7}")
    else:
        print(f"\n{'epoch':>5} {'lr':>9} {'train':>10} {'val':>10} {'corner err':>11} {'IoU':>7} {'time':>7}")
    for epoch in range(1, args.epochs + 1):
        model.train()
        started = time.time()
        running = []

        for images, targets in train_loader:
            images, targets = images.to(device), targets.to(device)

            optimizer.zero_grad()               # gradients accumulate; clear them
            preds = model(images)
            loss = criterion(preds, targets)
            loss.backward()
            optimizer.step()

            running.append(loss.item())

        scheduler.step()  # once per epoch, not per batch, to match T_max
        train_loss = float(np.mean(running))
        validator = validate_seg if is_seg else validate
        metrics = validator(model, val_loader, criterion, device)
        elapsed = time.time() - started

        if is_seg:
            print(
                f"{epoch:>5} {scheduler.get_last_lr()[0]:>9.2e} {train_loss:>10.5f} "
                f"{metrics['loss']:>10.5f} {metrics['mask_iou']:>9.4f} {elapsed:>6.0f}s"
            )
        else:
            print(
                f"{epoch:>5} {scheduler.get_last_lr()[0]:>9.2e} {train_loss:>10.5f} "
                f"{metrics['loss']:>10.5f} {metrics['corner_err_pct']:>10.2f}% "
                f"{metrics['iou']:>7.4f} {elapsed:>6.0f}s"
            )

        history.append({"epoch": epoch, "train_loss": train_loss, **metrics, "seconds": elapsed})
        (args.out / "history.json").write_text(json.dumps(history, indent=2))

        # Save the whole module, not a state_dict: eval.py and export.py can then
        # load it without needing to know the architecture, which matters while
        # model.py is still changing.
        torch.save(model, args.out / "last.pt")
        # One number, lower-is-better, whichever task this is: corner error
        # directly, and 1 - IoU for masks.
        score = 1.0 - metrics["mask_iou"] if is_seg else metrics["corner_err_pct"]
        if score < best_score:
            best_score = score
            torch.save(model, args.out / "best.pt")
            print(f"{'':>5} new best -> {args.out / 'best.pt'}")

    if is_seg:
        print(f"\nbest val mask IoU: {1.0 - best_score:.4f}")
    else:
        print(f"\nbest val corner error: {best_score:.2f}%")
    print(f"checkpoints in {args.out}")
    print(
        "\nNext, once you are happy with the val curve:\n"
        f"  python ml/eval.py --checkpoint {args.out / 'best.pt'} "
        f"{'--task seg ' if is_seg else ''}--data data/smartdoc/test --by background\n"
        "That is the real-photo number, and the first time the model meets it."
    )


if __name__ == "__main__":
    main()
