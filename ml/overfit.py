"""Overfit a single batch -- the first thing to run, before any real training.

A model that cannot memorise eight images has a bug: wrong shapes, targets that
do not correspond to their images, a frozen or disconnected layer, a loss that
is not differentiable with respect to the output. None of those are fixable by
tuning the learning rate, and all of them are invisible in a full training run,
where a loss that falls from 0.09 to 0.04 and stops looks plausible.

Here there is nothing to hide behind. Eight images, no augmentation, no
validation, hundreds of passes over the same batch. The loss must go to
approximately zero. If it plateaus, the bug is upstream of training.

Usage:
    python ml/overfit.py --data data/preview
    python ml/overfit.py --data data/smartdoc/test --steps 600
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader

from common import describe_device, get_device, set_seed
from dataset import CornerDataset
from eval import corner_error
from model import CornerNet


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", type=Path, default=Path("data/preview"))
    parser.add_argument("--batch-size", type=int, default=8)
    # Measured, not guessed: this model reaches ~8% corner error at 400 steps,
    # 1.1% at 2000 and 0.10% at 4000. Anything under a couple of thousand looks
    # like a failure when it is only an unfinished run -- which is the worst
    # possible outcome for a diagnostic, since it sends you hunting a bug that
    # is not there. Takes a couple of minutes on MPS.
    parser.add_argument("--steps", type=int, default=3000)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--device", default=None)
    args = parser.parse_args()

    set_seed(0)
    device = get_device(args.device)
    print(f"device: {describe_device(device)}")

    # --- data -------------------------------------------------------------
    # augment=False on purpose. Augmentation makes every epoch show slightly
    # different images, which is the whole point during real training and
    # exactly wrong here: we want the model to memorise one fixed batch.
    dataset = CornerDataset(args.data, augment=False)
    loader = DataLoader(dataset, batch_size=args.batch_size, shuffle=True)

    # A DataLoader is an iterable of batches. next(iter(...)) pulls exactly one
    # and then we forget the loader entirely -- this batch is all we use.
    images, targets = next(iter(loader))
    images, targets = images.to(device), targets.to(device)
    print(f"one batch: images {tuple(images.shape)}, targets {tuple(targets.shape)}")

    # --- model, loss, optimiser -------------------------------------------
    model = CornerNet().to(device)

    # beta is the point where Smooth L1 switches from quadratic to linear. The
    # default is 1.0, and with coordinates normalised to [0,1] every error is
    # far below that, so the linear branch would never be reached and this would
    # silently be plain MSE. Set it near the scale of the errors you expect.
    criterion = nn.SmoothL1Loss(beta=0.03)

    # weight_decay=0 here, against AdamW's default of 0.01. Weight decay exists
    # to *discourage* memorising the training set, which is the whole objective
    # of this test. Measured effect is small (1.12% vs 1.22% at 2000 steps) but
    # the reasoning matters: keep it on for real training in train.py.
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=0.0)

    # train() vs eval() switches BatchNorm between using batch statistics and
    # its running averages. Forgetting it is a classic source of "great during
    # training, nonsense at inference".
    model.train()

    print(f"\n{'step':>6}  {'loss':>10}  {'corner err':>11}")
    for step in range(1, args.steps + 1):
        # The five lines that constitute training in PyTorch:
        optimizer.zero_grad()            # 1. clear old gradients -- they ACCUMULATE
        preds = model(images)            # 2. forward pass
        loss = criterion(preds, targets) # 3. how wrong
        loss.backward()                  # 4. autograd fills .grad on every parameter
        optimizer.step()                 # 5. apply the update using those .grad values

        if step % max(1, args.steps // 20) == 0 or step == 1:
            with torch.no_grad():
                err = np.mean([
                    corner_error(p, t)
                    for p, t in zip(preds.cpu().numpy(), targets.cpu().numpy())
                ])
            print(f"{step:>6}  {loss.item():>10.6f}  {100 * err:>10.2f}%")

    # --- verdict ----------------------------------------------------------
    model.eval()
    with torch.no_grad():
        preds = model(images)
        final_loss = criterion(preds, targets).item()
        final_err = 100 * np.mean([
            corner_error(p, t) for p, t in zip(preds.cpu().numpy(), targets.cpu().numpy())
        ])

    print(f"\nfinal loss {final_loss:.6f}, corner error {final_err:.2f}%")
    if final_err < 0.5:
        print("PASS -- the model memorised the batch; the pipeline is wired correctly.")
    elif final_err < 3.0:
        print(
            "INCONCLUSIVE -- still descending, not converged. Re-run with --steps "
            f"{2 * args.steps} before suspecting a bug; this model needs a few "
            "thousand steps to fully memorise."
        )
    else:
        print(
            "FAIL -- cannot fit 8 images. Look upstream, not at hyperparameters:\n"
            "  - do the targets match their images? (synth.py --grid)\n"
            "  - does model.py output (B, 8) with no activation squashing it?\n"
            "  - is every block actually called in forward()?\n"
            "  - is the loss beta sane for [0,1] coordinates? (default 1.0 is not)"
        )


if __name__ == "__main__":
    main()
