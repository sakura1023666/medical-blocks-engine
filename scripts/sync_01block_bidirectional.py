#!/usr/bin/env python3
"""Additive bidirectional sync: 01Block ↔ 01Block-new-Final.

Principles (do not change):
  - Only ADD missing files / missing pipeline map keys
  - Never overwrite existing same-path files
  - Never delete anything
  - Same-path content diffs stay as-is (both sides keep their copy)

Default roots:
  A = /mnt/e/01block/01Block
  B = /mnt/e/01block/01Block-new-Final
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path

DEFAULT_A = Path("/mnt/e/01block/01Block")
DEFAULT_B = Path("/mnt/e/01block/01Block-new-Final")

# Relative trees to sync additively (file-level; never overwrite).
SYNC_TREES = (
    "Blocks",
    "R",
    "scripts",
    "configs/templates",
    "configs/indices",
    "configs/study_interface",
    "python",
    "run",
    ".cursor/skills",
    "tests",
)

SKIP_DIR_NAMES = {
    "__pycache__",
    ".git",
    ".venv",
    "venv",
    "node_modules",
    "checkpoints",
    "by_index",
    "by_unit",
    "summary_result",
    "summary_results",
    "_delivery_workspace",
    ".Rproj.user",
}

SKIP_SUFFIXES = {".pyc", ".pyo", ".rds", ".RData", ".rda", ".xlsx", ".csv", ".pdf", ".png", ".tiff"}

# Keep small text/code only under run/; skip bulky result dumps.
RUN_ALLOW_SUFFIXES = {".R", ".r", ".py", ".sh", ".md", ".txt", ".json", ".yml", ".yaml", ".toml"}


def log(msg: str) -> None:
    print(f"{datetime.now():%F %T} {msg}", flush=True)


def should_skip_path(rel: Path, tree: str) -> bool:
    parts = rel.parts
    if any(p in SKIP_DIR_NAMES for p in parts):
        return True
    if tree == ".cursor/skills":
        # skills: text/code only; skip heavy asset galleries
        if any(p in {"assets", "gallery", "figures", "node_modules"} for p in parts):
            return True
        if rel.suffix.lower() in {".png", ".jpg", ".jpeg", ".gif", ".webp", ".pdf", ".zip"}:
            return True
        if rel.suffix and rel.suffix.lower() not in {".md", ".py", ".r", ".sh", ".json", ".txt", ".yaml", ".yml"}:
            if rel.name != "SKILL.md":
                return True
        return False
    if rel.name.startswith(".") and rel.suffix not in {".R", ".py", ".md", ".sh", ".json"}:
        return True
    if tree == "run":
        if rel.suffix and rel.suffix not in RUN_ALLOW_SUFFIXES:
            return True
        if any(p in {"Tables", "Figures", "logs", "Data", "data"} for p in parts):
            return True
    if tree in {
        "python",
        "R",
        "Blocks",
        "tests",
        "scripts",
        "configs/templates",
        "configs/indices",
        "configs/study_interface",
    }:
        if rel.suffix and rel.suffix.lower() not in {
            ".r",
            ".py",
            ".sh",
            ".md",
            ".txt",
            ".json",
            ".yml",
            ".yaml",
            ".toml",
        }:
            return True
    return False


def iter_files(root: Path, tree: str):
    base = root / tree
    if not base.exists():
        return
    for dirpath, dirnames, filenames in os.walk(base, followlinks=False):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIR_NAMES]
        for fn in filenames:
            src = Path(dirpath) / fn
            if src.is_symlink():
                # copy symlink as symlink if dest missing
                rel = src.relative_to(root)
                yield rel, src, True
                continue
            if not src.is_file():
                continue
            rel = src.relative_to(root)
            if should_skip_path(rel, tree):
                continue
            yield rel, src, False


def copy_missing(src_root: Path, dst_root: Path, tree: str, dry_run: bool) -> tuple[int, int]:
    added = skipped = 0
    for rel, src, is_link in iter_files(src_root, tree):
        dst = dst_root / rel
        if dst.exists() or dst.is_symlink():
            skipped += 1
            continue
        if dst.parent.exists() and dst.parent.is_symlink():
            skipped += 1
            continue
        if dry_run:
            log(f"DRY {src_root.name}->{dst_root.name} ADD {rel}")
            added += 1
            continue
        dst.parent.mkdir(parents=True, exist_ok=True)
        if is_link:
            target = os.readlink(src)
            dst.symlink_to(target)
        else:
            shutil.copy2(src, dst)
        added += 1
    return added, skipped


def extract_pipeline_entries(text: str) -> dict[str, str]:
    entries: dict[str, str] = {}
    for m in re.finditer(
        r'^(\s+)([A-Za-z0-9_]+)\s*=\s*(?:b\("[^"]+"\)|file\.path\([^\n]+\))\s*,?\s*(?:#.*)?$',
        text,
        re.M,
    ):
        key = m.group(2)
        if key not in entries:
            entries[key] = m.group(0)
    return entries


def find_map_insert_point(text: str) -> int | None:
    m = re.search(r"\n(\s*render_tables\s*=\s*b\(\"[^\"]+\"\)\s*)\n", text)
    if m:
        return m.start(1)
    idxs = [m.start() for m in re.finditer(r"\n  \)\n", text)]
    return idxs[-1] if idxs else None


def ensure_comma_line(line: str) -> str:
    line = line.rstrip()
    if line.endswith(","):
        return line
    if "#" in line:
        code, comment = line.split("#", 1)
        return code.rstrip().rstrip(",") + ",  #" + comment
    return line.rstrip(",") + ","


def merge_pipeline_keys(target: Path, donor: Path, label: str, dry_run: bool) -> int:
    if not target.exists() or not donor.exists():
        log(f"skip pipeline merge {label}: missing file")
        return 0
    t = target.read_text(encoding="utf-8", errors="replace")
    d = donor.read_text(encoding="utf-8", errors="replace")
    te, de = extract_pipeline_entries(t), extract_pipeline_entries(d)
    missing = sorted(set(de) - set(te))
    if not missing:
        log(f"pipeline {label}: nothing to add")
        return 0
    insert_at = find_map_insert_point(t)
    if insert_at is None:
        log(f"ERROR pipeline {label}: cannot find insertion point")
        return 0
    if dry_run:
        log(f"DRY pipeline {label}: would add {len(missing)} keys")
        return len(missing)
    bak = target.with_suffix(target.suffix + ".bak_weekly_sync")
    if not bak.exists():
        bak.write_text(t, encoding="utf-8")
    stamp = datetime.now().strftime("%F")
    lines = [f"    ## --- weekly sync {stamp} from peer ({label}); additive only ---"]
    for k in missing:
        lines.append(ensure_comma_line(de[k]))
    block = "\n".join(lines) + "\n"
    target.write_text(t[:insert_at] + block + t[insert_at:], encoding="utf-8")
    log(f"pipeline {label}: added {len(missing)} keys")
    return len(missing)


def index_basenames(blocks: Path) -> dict[str, list[Path]]:
    by_bn: dict[str, list[Path]] = defaultdict(list)
    if not blocks.exists():
        return by_bn
    for p in blocks.rglob("*.R"):
        by_bn[p.name].append(p)
    return by_bn


def repair_map_symlinks(root: Path, dry_run: bool) -> tuple[int, int]:
    """Create per-file symlinks for pipeline b() paths that miss on disk."""
    runner = root / "R" / "pipeline_runner.R"
    blocks = root / "Blocks"
    if not runner.exists():
        return 0, 0
    text = runner.read_text(encoding="utf-8", errors="replace")
    mapped = re.findall(r'=\s*b\("([^"]+\.R)"\)', text)
    by_bn = index_basenames(blocks)
    created = unresolved = 0
    for rel in mapped:
        dest = blocks / rel
        if dest.exists():
            continue
        cands = by_bn.get(Path(rel).name, [])
        if not cands:
            unresolved += 1
            continue
        pick = sorted(cands, key=lambda c: (0 if "_full" in str(c) else 1, len(str(c))))[0]
        if dry_run:
            created += 1
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        if dest.exists() or dest.is_symlink():
            continue
        target = os.path.relpath(pick, start=dest.parent)
        dest.symlink_to(target)
        created += 1
    return created, unresolved


def ensure_glide_pack(root: Path, dry_run: bool) -> int:
    """Ensure Blocks/74_glide_sol → run/environment/blocks_shell glide files."""
    shell = root / "run" / "environment" / "blocks_shell"
    dest_dir = root / "Blocks" / "74_glide_sol"
    if not shell.exists():
        return 0
    files = sorted(shell.glob("0*block_glide_*.R"))
    n = 0
    for src in files:
        dest = dest_dir / src.name
        if dest.exists() or dest.is_symlink():
            continue
        if dry_run:
            n += 1
            continue
        dest_dir.mkdir(parents=True, exist_ok=True)
        dest.symlink_to(os.path.relpath(src, start=dest_dir))
        n += 1
    return n


def register_ids(root: Path) -> set[str]:
    blocks = root / "Blocks"
    if not blocks.exists():
        return set()
    try:
        out = subprocess.check_output(
            [
                "rg",
                "-oN",
                r"""register_block\s*\(\s*["']([^"']+)["']""",
                "-r",
                "$1",
                str(blocks),
                "--no-filename",
                "--follow",
            ],
            text=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return set()
    return {x.strip() for x in out.splitlines() if x.strip()}


def run_catalog(root: Path, dry_run: bool) -> None:
    script = root / "scripts" / "update_blocks_catalog.py"
    if not script.exists():
        log(f"catalog skip: no script in {root}")
        return
    if dry_run:
        log(f"DRY catalog: {script}")
        return
    r = subprocess.run(
        [sys.executable, str(script)],
        cwd=str(root),
        capture_output=True,
        text=True,
    )
    tail = (r.stdout or r.stderr or "").strip().splitlines()[-3:]
    for line in tail:
        log(f"catalog[{root.name}]: {line}")
    if r.returncode != 0:
        log(f"WARNING catalog exit={r.returncode} in {root}")


def sync_skill_md(a: Path, b: Path, dry_run: bool) -> None:
    """Keep update-blocks-catalog skill identical (prefer newer mtime)."""
    rel = Path(".cursor/skills/update-blocks-catalog/SKILL.md")
    pa, pb = a / rel, b / rel
    if not pa.exists() and not pb.exists():
        return
    if pa.exists() and pb.exists():
        if pa.read_bytes() == pb.read_bytes():
            return
        src = pa if pa.stat().st_mtime >= pb.stat().st_mtime else pb
        dst = pb if src is pa else pa
    elif pa.exists():
        src, dst = pa, pb
    else:
        src, dst = pb, pa
    if dry_run:
        log(f"DRY skill sync {src} -> {dst}")
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    # personal skill library
    personal = Path.home() / ".cursor/skills/update-blocks-catalog/SKILL.md"
    personal.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, personal)
    log(f"skill synced from {src.parent.parent.parent.name}")


def write_report(out: Path, stats: dict) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        f"# 01Block 双向同步报告 ({stats['stamp']})",
        "",
        f"- A: `{stats['a']}`",
        f"- B: `{stats['b']}`",
        f"- dry_run: {stats['dry_run']}",
        "",
        "## 结果",
        f"- A→B files added: {stats['a2b_added']} (skipped existing {stats['a2b_skipped']})",
        f"- B→A files added: {stats['b2a_added']} (skipped existing {stats['b2a_skipped']})",
        f"- pipeline keys A→B: {stats['pipe_a2b']}",
        f"- pipeline keys B→A: {stats['pipe_b2a']}",
        f"- map symlinks created A/B: {stats['link_a']}/{stats['link_b']}",
        f"- glide links created A/B: {stats['glide_a']}/{stats['glide_b']}",
        f"- register_block ids A/B: {stats['ids_a']}/{stats['ids_b']}",
        f"- ids only A: {stats['only_a']}",
        f"- ids only B: {stats['only_b']}",
        "",
        "原则：只增不删、不覆盖同路径已有文件。",
        "",
    ]
    out.write_text("\n".join(lines), encoding="utf-8")
    log(f"report: {out}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--a", type=Path, default=DEFAULT_A, help="01Block root")
    ap.add_argument("--b", type=Path, default=DEFAULT_B, help="01Block-new-Final root")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--skip-catalog", action="store_true")
    ap.add_argument(
        "--report",
        type=Path,
        default=None,
        help="Write markdown report (default: B/reports/blocks_weekly_sync_YYYY-MM-DD.md)",
    )
    args = ap.parse_args()
    a, b = args.a.resolve(), args.b.resolve()
    if not a.is_dir() or not b.is_dir():
        log(f"ERROR: roots must exist: a={a} b={b}")
        return 2

    log(f"START sync A={a} B={b} dry_run={args.dry_run}")
    a2b_added = a2b_skipped = b2a_added = b2a_skipped = 0
    for tree in SYNC_TREES:
        x1, y1 = copy_missing(a, b, tree, args.dry_run)
        a2b_added += x1
        a2b_skipped += y1
        x2, y2 = copy_missing(b, a, tree, args.dry_run)
        b2a_added += x2
        b2a_skipped += y2
        log(f"tree {tree}: A→B +{x1} B→A +{x2}")

    log(f"files A→B added={a2b_added} skipped={a2b_skipped}")
    log(f"files B→A added={b2a_added} skipped={b2a_skipped}")

    pipe_a2b = merge_pipeline_keys(b / "R/pipeline_runner.R", a / "R/pipeline_runner.R", "A→B", args.dry_run)
    pipe_b2a = merge_pipeline_keys(a / "R/pipeline_runner.R", b / "R/pipeline_runner.R", "B→A", args.dry_run)

    link_a, un_a = repair_map_symlinks(a, args.dry_run)
    link_b, un_b = repair_map_symlinks(b, args.dry_run)
    log(f"map symlinks A created={link_a} unresolved={un_a}")
    log(f"map symlinks B created={link_b} unresolved={un_b}")

    glide_a = ensure_glide_pack(a, args.dry_run)
    glide_b = ensure_glide_pack(b, args.dry_run)
    log(f"glide pack links A={glide_a} B={glide_b}")

    sync_skill_md(a, b, args.dry_run)

    if not args.skip_catalog:
        run_catalog(a, args.dry_run)
        run_catalog(b, args.dry_run)

    ids_a, ids_b = register_ids(a), register_ids(b)
    only_a = sorted(ids_a - ids_b)
    only_b = sorted(ids_b - ids_a)
    log(f"register_block A={len(ids_a)} B={len(ids_b)} only_A={len(only_a)} only_B={len(only_b)}")
    if only_a[:10]:
        log(f"only_A sample: {only_a[:10]}")
    if only_b[:10]:
        log(f"only_B sample: {only_b[:10]}")

    stamp = datetime.now().strftime("%F")
    report = args.report or (b / "reports" / f"blocks_weekly_sync_{stamp}.md")
    write_report(
        report,
        {
            "stamp": stamp,
            "a": str(a),
            "b": str(b),
            "dry_run": args.dry_run,
            "a2b_added": a2b_added,
            "a2b_skipped": a2b_skipped,
            "b2a_added": b2a_added,
            "b2a_skipped": b2a_skipped,
            "pipe_a2b": pipe_a2b,
            "pipe_b2a": pipe_b2a,
            "link_a": link_a,
            "link_b": link_b,
            "glide_a": glide_a,
            "glide_b": glide_b,
            "ids_a": len(ids_a),
            "ids_b": len(ids_b),
            "only_a": only_a,
            "only_b": only_b,
        },
    )
    log("DONE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
