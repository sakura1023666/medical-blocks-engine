#!/usr/bin/env python3
"""Byte-safe strip of -DB. tags inside xlsx sharedStrings / sheet XML (title cells)."""
from __future__ import annotations

import io
import re
import sys
import zipfile
from pathlib import Path

_TAG = rb"(?:CHARLS|NHANES|Nhance|MIMIC(?: IV)?|eICU|ELSA|Hosp)"
_PATS = [
    (re.compile(rb"((?:Table|Figure) (?:S?\d+[A-Za-z]?))-" + _TAG + rb"\."), rb"\1."),
]


def strip_xlsx_titles(path: Path) -> bool:
    path = Path(path)
    if not path.is_file():
        return False
    changed = False
    with zipfile.ZipFile(path, "r") as zin:
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED) as zout:
            for item in zin.infolist():
                data = zin.read(item.filename)
                if item.filename.endswith(".xml") and (
                    "sharedStrings" in item.filename or "worksheets/sheet" in item.filename
                ):
                    new = data
                    for cre, repl in _PATS:
                        new2 = cre.sub(repl, new)
                        if new2 != new:
                            changed = True
                            new = new2
                    data = new
                zout.writestr(item, data)
        if changed:
            path.write_bytes(buf.getvalue())
    return changed


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: pub_strip_db_in_xlsx_title.py <xlsx> [...]", file=sys.stderr)
        return 2
    n = 0
    for a in argv[1:]:
        if strip_xlsx_titles(Path(a)):
            n += 1
            print("stripped", a)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
