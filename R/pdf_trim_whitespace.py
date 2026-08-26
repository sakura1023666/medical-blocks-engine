#!/usr/bin/env python3
"""Crop PDF to content bbox and normalize MediaBox to (0,0). Keeps vector text."""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

from pypdf import PdfReader, PdfWriter, Transformation


def _gs_bbox(path: str) -> tuple[float, float, float, float]:
    r = subprocess.run(
        ["gs", "-dBATCH", "-dNOPAUSE", "-dSAFER", "-sDEVICE=bbox", path],
        capture_output=True,
        text=True,
        check=False,
    )
    text = (r.stdout or "") + "\n" + (r.stderr or "")
    m = re.search(
        r"%%HiResBoundingBox:\s*([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)",
        text,
    )
    if not m:
        m = re.search(
            r"%%BoundingBox:\s*([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)",
            text,
        )
    if not m:
        raise SystemExit(f"no bbox for {path}")
    return tuple(float(x) for x in m.groups())  # type: ignore[return-value]


def crop(path_in: str, path_out: str, pad_pt: float = 8.0) -> None:
    llx, lly, urx, ury = _gs_bbox(path_in)
    pad = max(0.0, float(pad_pt))
    llx = max(0.0, llx - pad)
    lly = max(0.0, lly - pad)
    urx = urx + pad
    ury = ury + pad
    if urx <= llx or ury <= lly:
        raise SystemExit(f"invalid bbox after pad: {llx} {lly} {urx} {ury}")

    w = urx - llx
    h = ury - lly
    reader = PdfReader(path_in)
    writer = PdfWriter()
    for page in reader.pages:
        # 平移内容使裁切后原点为 (0,0)，避免拼图时 mediabox 非零原点导致错位/重叠
        page.add_transformation(Transformation().translate(-llx, -lly))
        page.mediabox.lower_left = (0.0, 0.0)
        page.mediabox.upper_right = (w, h)
        page.cropbox.lower_left = (0.0, 0.0)
        page.cropbox.upper_right = (w, h)
        writer.add_page(page)
    Path(path_out).parent.mkdir(parents=True, exist_ok=True)
    with open(path_out, "wb") as f:
        writer.write(f)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("input")
    p.add_argument("-o", "--output", default="")
    p.add_argument("--pad-pt", type=float, default=8.0)
    args = p.parse_args()
    out = args.output or args.input
    tmp = out + ".trimtmp.pdf" if out == args.input else out
    crop(args.input, tmp, pad_pt=args.pad_pt)
    if tmp != out:
        Path(tmp).replace(out)


if __name__ == "__main__":
    main()
