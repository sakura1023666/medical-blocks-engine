#!/usr/bin/env python3
"""Validate midterm 项目信息-中期.md before Aiya-NB004 build.

Empty exposure/outcome → cover degenerates to「与的」+ default「横断面」+ system date.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def parse(md: Path) -> dict[str, str]:
    d: dict[str, str] = {}
    for line in md.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^([^:：]+)[：:]\s*(.+)$", line.strip())
        if m:
            d[m.group(1).strip()] = m.group(2).strip()
    return d


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("path", type=Path)
    ap.add_argument("--no-date", action="store_true")
    ns = ap.parse_args()
    if not ns.path.is_file():
        print(f"FAIL missing: {ns.path}", file=sys.stderr)
        return 1
    d = parse(ns.path)
    need = ["暴露指标", "结局", "报告标题"]
    miss = [k for k in need if not str(d.get(k, "")).strip()]
    if miss:
        print(f"FAIL missing fields: {miss}", file=sys.stderr)
        return 1
    if ns.no_date:
        date_v = str(d.get("分析日期", "")).strip()
        if date_v not in ("无", "-", "—", "无日期"):
            print(f"FAIL 分析日期 must be 无, got={date_v!r}", file=sys.stderr)
            return 1
    print(
        "OK",
        d.get("客户", ""),
        d.get("暴露指标", ""),
        d.get("结局", ""),
        f"date={d.get('分析日期', '')}",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
