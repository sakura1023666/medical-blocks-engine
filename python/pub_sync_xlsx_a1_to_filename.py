#!/usr/bin/env python3
"""Sync worksheet A1 / sharedStrings table title to the xlsx filename stem.

Surgical: only replaces an exact sharedStrings entry equal to the current A1
title (or any sharedStrings item that looks like a Table title mismatch).
Does not rewrite values, styles, or drawings.
"""
from __future__ import annotations

import argparse
import os
import re
import sys
import zipfile
from xml.etree import ElementTree as ET


SS_NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}


def _local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _si_text(si: ET.Element) -> str:
    parts: list[str] = []
    t = si.find("m:t", SS_NS)
    if t is not None and t.text:
        parts.append(t.text)
    for r in si.findall("m:r", SS_NS):
        rt = r.find("m:t", SS_NS)
        if rt is not None and rt.text:
            parts.append(rt.text)
    return "".join(parts)


def _set_si_text(si: ET.Element, text: str) -> None:
    for child in list(si):
        si.remove(child)
    t = ET.SubElement(si, "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}t")
    t.text = text
    if text.startswith(" ") or text.endswith(" ") or "\n" in text or "\t" in text:
        t.set("{http://www.w3.org/XML/1998/namespace}space", "preserve")


def _a1_shared_index(sheet_xml: bytes) -> int | None:
    root = ET.fromstring(sheet_xml)
    for c in root.iter():
        if _local(c.tag) != "c":
            continue
        if c.get("r") != "A1":
            continue
        if c.get("t") != "s":
            return None
        v = None
        for ch in c:
            if _local(ch.tag) == "v" and ch.text is not None:
                v = ch.text
                break
        if v is None:
            return None
        try:
            return int(v)
        except ValueError:
            return None
    return None


def sync_one(path: str, dry_run: bool = False) -> tuple[bool, str]:
    new_title = os.path.splitext(os.path.basename(path))[0]
    if not path.lower().endswith(".xlsx") or not os.path.isfile(path):
        return False, "skip"
    with zipfile.ZipFile(path, "r") as zin:
        names = zin.namelist()
        if "xl/sharedStrings.xml" not in names:
            return False, "no sharedStrings"
        ss_xml = zin.read("xl/sharedStrings.xml")
        sheet_name = "xl/worksheets/sheet1.xml"
        if sheet_name not in names:
            sheets = [n for n in names if n.startswith("xl/worksheets/sheet") and n.endswith(".xml")]
            if not sheets:
                return False, "no sheet"
            sheet_name = sorted(sheets)[0]
        sheet_xml = zin.read(sheet_name)
        other = {n: zin.read(n) for n in names if n not in (sheet_name, "xl/sharedStrings.xml")}

    idx = _a1_shared_index(sheet_xml)
    root = ET.fromstring(ss_xml)
    sis = [el for el in list(root) if _local(el.tag) == "si"]
    if idx is None or idx < 0 or idx >= len(sis):
        # fallback: replace first Table* shared string that differs from filename
        changed = False
        for si in sis:
            cur = _si_text(si)
            if re.match(r"(?i)^Table(\s+S)?\.?\s*", cur or "") and cur != new_title:
                if not dry_run:
                    _set_si_text(si, new_title)
                changed = True
                break
        if not changed:
            return False, "no A1 index"
    else:
        cur = _si_text(sis[idx])
        if cur == new_title:
            return True, "already"
        if not dry_run:
            _set_si_text(sis[idx], new_title)

    if dry_run:
        return True, f"would set -> {new_title}"

    # serialize sharedStrings (keep default namespace)
    for el in root.iter():
        if el.tag.startswith("{"):
            pass
    new_ss = ET.tostring(root, encoding="utf-8", xml_declaration=True)

    tmp = path + ".tmp_title_sync"
    with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED) as zout:
        for n, data in other.items():
            zout.writestr(n, data)
        zout.writestr(sheet_name, sheet_xml)
        zout.writestr("xl/sharedStrings.xml", new_ss)
    os.replace(tmp, path)
    return True, f"set -> {new_title}"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    n_ok = 0
    for p in args.paths:
        ok, msg = sync_one(p, dry_run=args.dry_run)
        print(f"{os.path.basename(p)}: {msg}")
        if ok:
            n_ok += 1
    return 0 if n_ok else 1


if __name__ == "__main__":
    sys.exit(main())
