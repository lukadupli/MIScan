"""SmartDoc 2015 Challenge 1 ingestion -- the real-photo half of the data.

Everything in synth.py is generated, which makes its labels exact and its
appearance a guess. This module brings in the opposite: 24,889 real smartphone
frames of real documents on real desks, hand-annotated by the ICDAR competition
organisers. It is the only honest answer to "does the synthetic training
actually transfer?", and that question cannot be answered by any amount of
held-out synthetic data.

Uses the pre-converted distribution at github.com/jchazalon/smartdoc15-ch1-dataset,
which has already turned the original competition's AVI videos plus per-frame XML
into JPEG frames plus one CSV. That saves us a video-decoding dependency.

Dataset: CC-BY 4.0, Chazalon et al., ICDAR 2015 SmartDoc Challenge 1.

Usage:
    python ml/smartdoc.py --download                 # ~1 GB, resumable
    python ml/smartdoc.py --prepare --stride 10      # every 10th frame
    python ml/smartdoc.py --prepare --stride 10 --visualize
"""

from __future__ import annotations

import argparse
import csv
import gzip
import hashlib
import json
import shutil
import sys
import tarfile
import urllib.request
from collections import defaultdict
from pathlib import Path

import numpy as np

from common import DATA_DIR, ensure_dirs

RELEASE = "https://github.com/jchazalon/smartdoc15-ch1-dataset/releases/download/v2.0.0"
FRAMES = ("frames.tar.gz", "3acb8be143fc86c507d90d298097cba762e91a3abf7e2d35ccd5303e13a79eae")
MODELS = ("models.tar.gz", "6f9068624073f76b20f88352b2bac60b9e5de5a59819fc9db37fba1ee07cce8a")

SMARTDOC_DIR = DATA_DIR / "smartdoc"
RAW_DIR = SMARTDOC_DIR / "raw"

# The CSV records corners as TL, BL, BR, TR -- counterclockwise on screen, which
# is the opposite winding to the TL, TR, BR, BL that frame.dart uses. We do not
# reorder by hand: canonicalize_corners already fixes winding and starting corner
# for any input order, and reusing it means both datasets are canonicalised by
# exactly the same code rather than by two rules that might drift apart.
CSV_CORNER_COLUMNS = [("tl_x", "tl_y"), ("bl_x", "bl_y"), ("br_x", "br_y"), ("tr_x", "tr_y")]


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download(name: str, expected_sha: str, dest_dir: Path) -> Path:
    """Fetch one release asset, resuming a partial download and verifying the hash.

    The resume matters more than it looks: this is a gigabyte over a link that
    may drop, and restarting from zero each time makes the whole stage tedious
    enough to skip. The checksum matters because a truncated tarball fails in
    confusing ways much later.
    """
    ensure_dirs(dest_dir)
    target = dest_dir / name

    if target.exists():
        print(f"{name}: already present, verifying...")
        if _sha256(target) == expected_sha:
            print(f"{name}: checksum OK")
            return target
        print(f"{name}: checksum MISMATCH, re-downloading")
        target.unlink()

    partial = target.with_suffix(target.suffix + ".part")
    have = partial.stat().st_size if partial.exists() else 0

    request = urllib.request.Request(f"{RELEASE}/{name}")
    if have:
        request.add_header("Range", f"bytes={have}-")
        print(f"{name}: resuming from {have / 1e6:.0f} MB")

    with urllib.request.urlopen(request) as response:
        total = int(response.headers.get("Content-Length", 0)) + have
        mode = "ab" if have else "wb"
        with partial.open(mode) as out:
            done = have
            while chunk := response.read(1 << 20):
                out.write(chunk)
                done += len(chunk)
                pct = f"{100 * done / total:5.1f}%" if total else "  ?  "
                print(f"\r{name}: {done / 1e6:7.0f} MB  {pct}", end="", flush=True)
    print()

    if _sha256(partial) != expected_sha:
        raise RuntimeError(f"{name}: checksum mismatch after download; delete {partial} and retry")
    partial.rename(target)
    print(f"{name}: checksum OK")
    return target


def extract(archive: Path, dest_dir: Path) -> None:
    marker = dest_dir / ".extracted"
    if marker.exists():
        print(f"{archive.name}: already extracted")
        return
    print(f"{archive.name}: extracting to {dest_dir} ...")
    ensure_dirs(dest_dir)
    with tarfile.open(archive) as tar:
        # filter="data" refuses absolute paths and parent-directory escapes.
        # This archive is trustworthy; the habit is worth keeping anyway.
        tar.extractall(dest_dir, filter="data")
    marker.touch()
    print(f"{archive.name}: done")


def _find_metadata(root: Path) -> Path:
    for candidate in root.rglob("metadata.csv.gz"):
        return candidate
    for candidate in root.rglob("metadata.csv"):
        return candidate
    raise FileNotFoundError(f"no metadata.csv[.gz] found under {root} -- did extraction finish?")


def _read_rows(metadata: Path) -> list[dict[str, str]]:
    opener = gzip.open if metadata.suffix == ".gz" else open
    with opener(metadata, "rt", newline="") as handle:
        return list(csv.DictReader(handle))


def prepare(stride: int, out_dir: Path, visualize: int) -> None:
    """Turn the CSV into the same labels.jsonl schema synth.py writes.

    One dataset format for both sources means dataset.py stays simple and there
    is exactly one place where a coordinate convention can be wrong.
    """
    from PIL import Image  # header-only reads; cheaper than decoding via cv2

    from synth import canonicalize_corners

    metadata = _find_metadata(RAW_DIR)
    frames_root = metadata.parent
    rows = _read_rows(metadata)
    print(f"metadata: {metadata} ({len(rows)} frames)")

    # Group by (background, model) -- that pair identifies one source video.
    #
    # This grouping is the whole reason to be careful here. Consecutive frames of
    # a video are near-identical, so splitting frames at random would put almost
    # the same picture in both train and test and report an accuracy that is
    # mostly memorisation. Splitting by video is the only split that measures
    # generalisation. Same reasoning as holding SmartDoc out from synthetic
    # training entirely: the test set has to be genuinely unseen.
    videos: dict[tuple[str, str], list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        videos[(row["bg_name"], row["model_name"])].append(row)
    for frames in videos.values():
        frames.sort(key=lambda r: int(r["frame_index"]))

    ensure_dirs(out_dir)
    kept = skipped = 0
    previews: list[tuple[Path, np.ndarray]] = []

    with (out_dir / "labels.jsonl").open("w") as labels:
        for (bg_name, model_name), frames in sorted(videos.items()):
            for row in frames[::stride]:
                image_path = frames_root / row["image_path"]
                if not image_path.exists():
                    skipped += 1
                    continue
                with Image.open(image_path) as img:
                    width, height = img.size

                corners = np.array(
                    [[float(row[cx]), float(row[cy])] for cx, cy in CSV_CORNER_COLUMNS],
                    dtype=np.float64,
                )
                corners = canonicalize_corners(corners)

                labels.write(
                    json.dumps(
                        {
                            "file": str(image_path.resolve()),
                            "width": width,
                            "height": height,
                            "corners": corners.tolist(),
                            "source": "smartdoc",
                            "video": f"{bg_name}/{model_name}",
                            "background": bg_name,
                            "modeltype": row["modeltype_name"],
                        }
                    )
                    + "\n"
                )
                kept += 1
                # One frame per video, so the preview spans backgrounds and
                # document types. Taking the first N in order would give N
                # near-identical frames of a single scene, which checks almost
                # nothing -- the point of looking is to catch a corner
                # convention that breaks on some subset.
                if len(previews) < visualize and row is frames[0]:
                    previews.append((image_path, corners))

    with (out_dir / "meta.json").open("w") as handle:
        json.dump(
            {
                "source": "smartdoc15-ch1",
                "images_root": "",  # 'file' fields are absolute
                "count": kept,
                "videos": len(videos),
                "stride": stride,
                "license": "CC-BY 4.0, Chazalon et al., ICDAR 2015 SmartDoc Challenge 1",
            },
            handle,
            indent=2,
        )

    print(f"wrote {kept} frames from {len(videos)} videos to {out_dir}")
    if skipped:
        print(f"  ({skipped} rows skipped -- image file missing)")

    if previews:
        _write_previews(previews, out_dir)


def _write_previews(previews: list[tuple[Path, np.ndarray]], out_dir: Path) -> None:
    """Contact sheet of real frames with their ground-truth quads.

    Worth doing once even though these labels are not ours: it confirms the
    corner columns were read in the order we think and that canonicalisation
    agrees between the two data sources.
    """
    import cv2

    from synth import contact_sheet

    samples = []
    for path, corners in previews:
        img = cv2.imread(str(path))
        if img is None:
            continue
        scale = 640 / img.shape[1]
        samples.append((cv2.resize(img, None, fx=scale, fy=scale), corners * scale))

    if samples:
        sheet_path = out_dir / "grid.jpg"
        cv2.imwrite(str(sheet_path), contact_sheet(samples))
        print(f"  contact sheet: {sheet_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--download", action="store_true", help="fetch and extract frames.tar.gz (~1 GB)")
    parser.add_argument(
        "--models",
        action="store_true",
        help="also fetch models.tar.gz (~409 MB): flat scans of the 30 documents, "
        "usable as real page images for synth.py",
    )
    parser.add_argument("--prepare", action="store_true", help="parse metadata into labels.jsonl")
    parser.add_argument(
        "--stride",
        type=int,
        default=10,
        help="keep every Nth frame per video; consecutive frames are near-duplicates (default 10)",
    )
    parser.add_argument("--out", type=Path, default=SMARTDOC_DIR / "test")
    parser.add_argument(
        "--visualize",
        type=int,
        nargs="?",
        const=16,
        default=0,
        metavar="N",
        help="write grid.jpg with N real frames and their ground-truth quads",
    )
    args = parser.parse_args()

    if not (args.download or args.prepare):
        parser.error("nothing to do: pass --download and/or --prepare")

    if args.download:
        free = shutil.disk_usage(DATA_DIR.parent).free
        needed = 3.5e9 if args.models else 2.5e9  # archive + extracted
        if free < needed:
            sys.exit(f"only {free / 1e9:.1f} GB free, need about {needed / 1e9:.1f} GB")
        extract(download(*FRAMES, RAW_DIR), RAW_DIR)
        if args.models:
            extract(download(*MODELS, RAW_DIR), RAW_DIR)

    if args.prepare:
        prepare(args.stride, args.out, args.visualize)


if __name__ == "__main__":
    main()
