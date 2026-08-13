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
from model import CornerNet


def build_loaders(args) -> tuple[DataLoader, DataLoader]:
    train_ds = CornerDataset(args.train, augment=True, limit=args.limit)
    val_ds = CornerDataset(args.val, augment=False, limit=args.limit)
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
    args = parser.parse_args()

    set_seed(args.seed)
    device = get_device(args.device)
    print(f"device: {describe_device(device)}")

    args.out.mkdir(parents=True, exist_ok=True)
    train_loader, val_loader = build_loaders(args)

    model = (
        torch.load(args.resume, map_location=device, weights_only=False)
        if args.resume
        else CornerNet()
    ).to(device)
    if args.resume:
        print(f"resumed from {args.resume}")

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
    best_err = float("inf")

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
        metrics = validate(model, val_loader, criterion, device)
        elapsed = time.time() - started

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
        if metrics["corner_err_pct"] < best_err:
            best_err = metrics["corner_err_pct"]
            torch.save(model, args.out / "best.pt")
            print(f"{'':>5} new best -> {args.out / 'best.pt'}")

    print(f"\nbest val corner error: {best_err:.2f}%")
    print(f"checkpoints in {args.out}")
    print(
        "\nNext, once you are happy with the val curve:\n"
        f"  python ml/eval.py --checkpoint {args.out / 'best.pt'} "
        "--data data/smartdoc/test --by background\n"
        "That is the real-photo number, and the first time the model meets it."
    )


if __name__ == "__main__":
    main()
