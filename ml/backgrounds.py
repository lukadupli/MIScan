"""Fetch the Describable Textures Dataset for use as synthetic backgrounds.

synth.py needs something to paste documents onto. Smooth colour gradients make
the page boundary a perfect high-contrast edge, which is the easiest possible
version of the problem and nothing like a real photo -- real captures put paper
on wood, cloth or carpet, with competing straight lines from table edges and
other objects nearby.

DTD is 5,640 photographs of real surfaces across 47 categories (banded, woven,
marbled, cracked, ...). It is the usual choice for this because the textures are
genuinely photographed rather than rendered, so they carry real lighting, noise
and scale variation.

Deliberately NOT used: SmartDoc's own five backgrounds. Those belong to the test
set, and training on them would quietly turn the one honest measurement in this
project into a number about memorisation.

Dataset: Cimpoi et al., "Describing Textures in the Wild", CVPR 2014.

Usage:
    python ml/backgrounds.py --download
"""

from __future__ import annotations

import argparse
import tarfile
import urllib.request
from pathlib import Path

from common import DATA_DIR, ensure_dirs

DTD_URL = "https://thor.robots.ox.ac.uk/~vgg/data/dtd/dtd-r1.0.1.tar.gz"
DTD_DIR = DATA_DIR / "backgrounds"
ARCHIVE = DTD_DIR / "dtd-r1.0.1.tar.gz"


def download() -> Path:
    ensure_dirs(DTD_DIR)

    if not ARCHIVE.exists():
        partial = ARCHIVE.with_suffix(ARCHIVE.suffix + ".part")
        have = partial.stat().st_size if partial.exists() else 0

        request = urllib.request.Request(DTD_URL)
        if have:
            request.add_header("Range", f"bytes={have}-")
            print(f"resuming from {have / 1e6:.0f} MB")

        with urllib.request.urlopen(request) as response:
            total = int(response.headers.get("Content-Length", 0)) + have
            with partial.open("ab" if have else "wb") as out:
                done = have
                while chunk := response.read(1 << 20):
                    out.write(chunk)
                    done += len(chunk)
                    pct = f"{100 * done / total:5.1f}%" if total else "  ?  "
                    print(f"\rdtd: {done / 1e6:6.0f} MB  {pct}", end="", flush=True)
        print()
        partial.rename(ARCHIVE)

    marker = DTD_DIR / ".extracted"
    if not marker.exists():
        print("extracting ...")
        with tarfile.open(ARCHIVE) as tar:
            tar.extractall(DTD_DIR, filter="data")
        marker.touch()

    images = list(DTD_DIR.rglob("*.jpg"))
    print(f"{len(images)} background images under {DTD_DIR}")
    return DTD_DIR


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--download", action="store_true")
    args = parser.parse_args()

    if not args.download:
        parser.error("pass --download")
    download()


if __name__ == "__main__":
    main()
