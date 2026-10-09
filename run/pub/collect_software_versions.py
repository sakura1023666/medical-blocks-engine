#!/usr/bin/env python3
"""Collect Python (+ optional R) versions for manuscript Software_versions_*.txt.

Usage (engine root):
  python run/pub/collect_software_versions.py \\
    --out /path/to/summary_results/Software_versions_for_submission.txt \\
    --project "SA-AKI TST MIMIC" \\
    --python /mnt/c/ProgramData/Miniconda3/envs/torch/python.exe

If --python omitted, uses current interpreter. R versions via Rscript if on PATH.
"""
from __future__ import annotations

import argparse
import datetime as dt
import platform
import subprocess
import sys
from pathlib import Path


PY_PKGS = [
    ("torch", "torch"),
    ("numpy", "numpy"),
    ("scipy", "scipy"),
    ("pandas", "pandas"),
    ("scikit-learn", "sklearn"),
    ("xgboost", "xgboost"),
    ("lightgbm", "lightgbm"),
    ("shap", "shap"),
    ("matplotlib", "matplotlib"),
    ("seaborn", "seaborn"),
    ("Pillow", "PIL"),
    ("openpyxl", "openpyxl"),
    ("einops", "einops"),
    ("joblib", "joblib"),
    ("tqdm", "tqdm"),
    ("PyYAML", "yaml"),
]

R_PKGS = [
    "openxlsx",
    "data.table",
    "dplyr",
    "tidyr",
    "ggplot2",
    "survival",
    "mice",
    "jsonlite",
]


def _run(cmd: list[str], timeout: int = 60) -> str:
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return (p.stdout or "") + (p.stderr or "")
    except Exception as e:
        return f"ERROR: {e}"


def collect_py(py: str) -> dict[str, str]:
    code = r"""
import sys, platform
print("Python", sys.version.split()[0])
print("Platform", platform.platform())
print("System", platform.system(), platform.release())
pkgs = %r
for label, mod in pkgs:
    try:
        m = __import__(mod)
        ver = getattr(m, "__version__", getattr(m, "VERSION", "?"))
        print(f"PKG {label}={ver}")
    except Exception:
        print(f"PKG {label}=NOT_INSTALLED")
try:
    import torch
    print("CUDA", torch.cuda.is_available())
    if torch.cuda.is_available():
        print("CUDA_VER", torch.version.cuda)
        print("GPU", torch.cuda.get_device_name(0))
except Exception:
    print("CUDA", "NA")
""" % PY_PKGS
    out = _run([py, "-c", code], timeout=120)
    info: dict[str, str] = {"raw": out}
    for line in out.splitlines():
        if line.startswith("Python "):
            info["Python"] = line.split(None, 1)[1]
        elif line.startswith("Platform "):
            info["Platform"] = line.split(None, 1)[1]
        elif line.startswith("System "):
            info["System"] = line.split(None, 1)[1]
        elif line.startswith("PKG "):
            k, v = line[4:].split("=", 1)
            info[k] = v
        elif line.startswith("CUDA "):
            info["CUDA"] = line.split(None, 1)[1]
        elif line.startswith("CUDA_VER "):
            info["CUDA_VER"] = line.split(None, 1)[1]
        elif line.startswith("GPU "):
            info["GPU"] = line.split(None, 1)[1]
    return info


def collect_r() -> dict[str, str]:
    rscript = "Rscript"
    info: dict[str, str] = {}
    ver = _run([rscript, "-e", "cat(R.version.string)"])
    if ver.startswith("ERROR") or "R version" not in ver:
        info["R"] = "Rscript not available"
        return info
    info["R"] = ver.strip().splitlines()[-1]
    pkgs = ",".join(f'"{p}"' for p in R_PKGS)
    code = f"""
pkgs <- c({pkgs})
for (p in pkgs) {{
  if (requireNamespace(p, quietly=TRUE))
    cat(p, as.character(packageVersion(p)), "\\n")
  else
    cat(p, "NOT_INSTALLED\\n")
}}
"""
    out = _run([rscript, "-e", code])
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0] in R_PKGS:
            info[parts[0]] = parts[1]
    return info


def render(project: str, out_path: str, py_info: dict, r_info: dict, py_exe: str) -> str:
    today = dt.date.today().isoformat()
    lines = [
        "Software versions for manuscript submission",
        f"Project: {project}",
        f"Path: {out_path}",
        f"Recorded: {today}",
        f"Python executable: {py_exe}",
        "",
        "=" * 80,
        "1. Operating system / environment",
        "=" * 80,
        f"System                        {py_info.get('System', platform.platform())}",
        f"Platform                      {py_info.get('Platform', '')}",
        "",
        "=" * 80,
        "2. Python",
        "=" * 80,
        f"Python                        {py_info.get('Python', '')}",
    ]
    for label, _ in PY_PKGS:
        if label in py_info:
            lines.append(f"{label:<28} {py_info[label]}")
    lines.append(f"CUDA available                {py_info.get('CUDA', 'NA')}")
    if "CUDA_VER" in py_info:
        lines.append(f"CUDA version                  {py_info['CUDA_VER']}")
    if "GPU" in py_info:
        lines.append(f"GPU                           {py_info['GPU']}")
    lines += [
        "",
        "=" * 80,
        "3. R",
        "=" * 80,
        f"R                             {r_info.get('R', '')}",
    ]
    for p in R_PKGS:
        if p in r_info:
            lines.append(f"{p:<28} {r_info[p]}")
    lines += [
        "",
        "=" * 80,
        "4. Notes",
        "=" * 80,
        "- Generated by run/pub/collect_software_versions.py",
        "- Template: configs/templates/Software_versions_for_submission.template.txt",
        "- Edit Methods wording after review; drop unused packages from the list.",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, help="Output txt path")
    ap.add_argument("--project", default="(unnamed study)")
    ap.add_argument("--python", default=sys.executable, help="Python executable to probe")
    ap.add_argument("--skip-r", action="store_true")
    args = ap.parse_args()

    py_info = collect_py(args.python)
    r_info = {} if args.skip_r else collect_r()
    text = render(args.project, args.out, py_info, r_info, args.python)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text, encoding="utf-8")
    print(f"Wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
