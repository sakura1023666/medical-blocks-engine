#!/usr/bin/env python3
"""Launch Aiya-NB004 midterm inspect/build with paths from env (UTF-8 safe).

R system2 argv can mangle 【success】 paths so parse_project_md returns {} and
the cover collapses to「与的 / 横断面相关性分析」plus a system date.
"""
from __future__ import annotations

import os
import runpy
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] not in ("inspect", "build"):
        print("usage: ckm_midterm_build.py inspect|build", file=sys.stderr)
        return 2
    mode = sys.argv[1]
    eng = Path(os.environ["CKM_MIDTERM_ENGINE"])
    proj = Path(os.environ["CKM_MIDTERM_PROJECT"])
    if not eng.is_file():
        print(f"engine missing: {eng}", file=sys.stderr)
        return 1
    if not proj.is_dir():
        print(f"project missing: {proj}", file=sys.stderr)
        return 1
    info = proj / "项目信息-中期.md"
    if mode == "build" and not info.is_file():
        print(f"项目信息 missing before build: {info}", file=sys.stderr)
        return 1
    argv = [str(eng)]
    if mode == "inspect":
        argv += ["--inspect", "--project", str(proj)]
    else:
        content = Path(os.environ["CKM_MIDTERM_CONTENT"])
        out = Path(os.environ["CKM_MIDTERM_OUT"])
        argv += [
            "--build",
            "--project", str(proj),
            "--content", str(content),
            "--out", str(out),
        ]
    sys.argv = argv
    runpy.run_path(str(eng), run_name="__main__")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
