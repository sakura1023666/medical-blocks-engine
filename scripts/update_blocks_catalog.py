#!/usr/bin/env python3
"""Generate / sync docs/Blocks_catalog.md from Blocks/**/*.R headers.

Usage (from repo root):
  python3 scripts/update_blocks_catalog.py
  python3 scripts/update_blocks_catalog.py --check   # exit 1 if stale
  python3 scripts/update_blocks_catalog.py --only-new # print register names not yet in catalog

AUTO sections are regenerated. MANUAL sections (between markers) are preserved
when the catalog already exists.
"""
from __future__ import annotations

import argparse
import datetime as dt
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BLOCKS = ROOT / "Blocks"
TEMPLATES = ROOT / "configs" / "templates"
OUT = ROOT / "docs" / "Blocks_catalog.md"
MANUAL_SIDE = ROOT / "docs" / "Blocks_catalog.manual.md"

REG_PAT = re.compile(
    r'register_block\s*\(\s*[\n\r\s]*["\']([^"\']+)["\']',
    re.MULTILINE,
)
SKIP_DIR_NAMES = {"scripts", "Figures_Blocks", "Tables_Blocks"}


def _is_block_file(path: Path) -> bool:
    if path.suffix.lower() != ".r":
        return False
    if any(p in SKIP_DIR_NAMES for p in path.parts):
        return False
    # skip pure helper commons that may still register; keep them if they register
    return True


def extract_header(text: str, max_lines: int = 80) -> str:
    lines = text.splitlines()
    out: list[str] = []
    started = False
    for line in lines[:160]:
        s = line.strip()
        if s.startswith("#"):
            started = True
            out.append(line)
            if len(out) >= max_lines:
                break
        elif started:
            break
        elif not s:
            continue
        else:
            break
    return "\n".join(out)


def parse_header_fields(header: str, block_id: str) -> dict:
    """Best-effort parse of block file comment header."""
    # strip leading "# " / "#"
    raw_lines = []
    for line in header.splitlines():
        s = line.lstrip()
        if s.startswith("#"):
            s = s[1:]
            if s.startswith(" "):
                s = s[1:]
        raw_lines.append(s.rstrip())
    blob = "\n".join(raw_lines)

    purpose = ""
    for line in raw_lines:
        if not line or set(line) <= {"-", "="}:
            continue
        if line.startswith("---") or line.startswith("==="):
            continue
        # first substantial line often "name — purpose"
        if "—" in line or " - " in line or line.startswith(block_id):
            purpose = line
            break
        if purpose == "" and len(line) > 8 and not line.startswith("register_block"):
            purpose = line
            break

    def grab(patterns: list[str]) -> str:
        for pat in patterns:
            m = re.search(pat, blob, re.I | re.M | re.S)
            if m:
                return re.sub(r"\s+", " ", m.group(1).strip())
        return ""

    pipeline = grab(
        [
            r"典型流水线[:：]\s*(.+?)(?:\n\n|\n#|\n写:|\n块内|\nregister_block|$)",
            r"典型位置[:：]\s*(.+?)(?:\n\n|\n#|\n写:|\n块内|$)",
        ]
    )
    # shorten pipeline to one line
    if pipeline:
        pipeline = pipeline.split("\n")[0].strip()

    writes = grab(
        [
            r"写[:：]\s*(.+?)(?:\n文件:|\n依赖:|\n块内|\n# ──|\n$)",
        ]
    )
    if writes:
        writes = writes.split("\n")[0].strip()[:220]

    requires = []
    for m in re.finditer(
        r"require_[a-zA-Z0-9_]+\s*=\s*[^\n]+", blob
    ):
        requires.append(re.sub(r"\s+", " ", m.group(0).strip()))

    # config section name: config$foo or "config$foo = list("
    cfg_keys = sorted(
        set(re.findall(r"config\$([A-Za-z0-9_]+)", blob))
    )
    # also "foo_binary = list(" near top as config section
    m_cfg_block = re.search(
        rf"(?:^|\n)({re.escape(block_id)})\s*=\s*list\s*\(", blob, re.M
    )
    if m_cfg_block and block_id not in cfg_keys:
        cfg_keys.insert(0, block_id)

    # pull indented config snippet (first list(...) after block_id = list)
    config_snip = ""
    m = re.search(
        rf"(?:^|\n)((?:{re.escape(block_id)}|[A-Za-z0-9_]+)\s*=\s*list\s*\([\s\S]{{0,1200}}?\n\s*\),)",
        blob,
        re.M,
    )
    if m:
        config_snip = m.group(1).strip()
        if len(config_snip) > 900:
            config_snip = config_snip[:900] + "\n  # ... truncated ..."

    return {
        "purpose": purpose[:240],
        "pipeline": pipeline[:200],
        "writes": writes,
        "requires": requires[:6],
        "config_keys": cfg_keys[:12],
        "config_snip": config_snip,
    }


def collect_blocks() -> list[dict]:
    items: list[dict] = []
    for path in sorted(BLOCKS.rglob("*.R")):
        if not _is_block_file(path):
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        names = REG_PAT.findall(text)
        if not names:
            continue
        rel = path.relative_to(ROOT).as_posix()
        dir_name = path.parent.name
        header = extract_header(text)
        for name in names:
            meta = parse_header_fields(header, name)
            items.append(
                {
                    "id": name,
                    "path": rel,
                    "dir": dir_name,
                    **meta,
                }
            )
    # stable unique by id (first wins)
    seen = set()
    uniq = []
    for it in items:
        if it["id"] in seen:
            continue
        seen.add(it["id"])
        uniq.append(it)
    return uniq


def family_key(block_id: str) -> str:
    parts = block_id.split("_")
    if len(parts) >= 2:
        # logistic_quartile_glm → logistic; cox_binary → cox; baseline_nhanes → baseline
        if parts[0] in {
            "dual",
            "logistic",
            "cox",
            "baseline",
            "univariate",
            "multivariate",
            "subgroup",
            "mediation",
            "rcs",
            "ml",
            "environment",
            "competing",
            "ipw",
            "crm",
            "tst",
            "trajectory",
        }:
            return parts[0]
        if parts[0] == "dual" and parts[1] == "db":
            return "dual_db"
    return parts[0]


def variant_tables(blocks: list[dict]) -> str:
    families = defaultdict(list)
    for b in blocks:
        fam = family_key(b["id"])
        families[fam].append(b["id"])

    # only show families with useful fan-out
    interesting = {
        "baseline",
        "cox",
        "logistic",
        "univariate",
        "multivariate",
        "subgroup",
        "mediation",
        "rcs",
        "dual_db",
        "weightcox",
        "ml",
        "competing",
        "ipw",
        "crm",
        "tst",
        "trajectory",
        "environment",
    }
    lines = [
        "按家族对照选型（pipeline 写 **register_block 名**，不是文件名）。",
        "",
    ]
    for fam in sorted(interesting):
        ids = sorted(families.get(fam, []))
        if len(ids) < 2:
            continue
        lines.append(f"### `{fam}_*`（{len(ids)}）")
        lines.append("")
        lines.append("| register_block |")
        lines.append("|---|")
        for i in ids:
            lines.append(f"| `{i}` |")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def render_block_cards(blocks: list[dict]) -> str:
    by_dir: dict[str, list[dict]] = defaultdict(list)
    for b in blocks:
        by_dir[b["dir"]].append(b)

    lines: list[str] = []
    lines.append(
        f"共 **{len(blocks)}** 个 `register_block`。"
        " 细节以各文件头部注释为准；本表只做选型索引。"
    )
    lines.append("")

    for dir_name in sorted(by_dir.keys()):
        lines.append(f"### `{dir_name}/`")
        lines.append("")
        for b in sorted(by_dir[dir_name], key=lambda x: x["id"]):
            lines.append(f"#### `{b['id']}`")
            lines.append(f"- 路径: `{b['path']}`")
            if b["purpose"]:
                lines.append(f"- 用途: {b['purpose']}")
            if b["pipeline"]:
                lines.append(f"- 典型位置: {b['pipeline']}")
            if b["requires"]:
                lines.append("- 前置: " + "; ".join(f"`{r}`" for r in b["requires"]))
            if b["writes"]:
                lines.append(f"- 写出: {b['writes']}")
            if b["config_keys"]:
                keys = ", ".join(f"`config${k}`" for k in b["config_keys"])
                lines.append(f"- config 节: {keys}")
            if b["config_snip"]:
                lines.append("- 头部配置摘录:")
                lines.append("")
                lines.append("```r")
                lines.append(b["config_snip"])
                lines.append("```")
            lines.append(f"- 回读: `{b['path']}` 文件头注释")
            lines.append("")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def render_dir_index(blocks: list[dict]) -> str:
    by_dir: dict[str, list[str]] = defaultdict(list)
    for b in blocks:
        by_dir[b["dir"]].append(b["id"])
    lines = [
        "| 目录 | 块数 | register_block（节选） |",
        "|---|---:|---|",
    ]
    for d in sorted(by_dir.keys()):
        ids = sorted(by_dir[d])
        preview = ", ".join(f"`{i}`" for i in ids[:8])
        if len(ids) > 8:
            preview += f", …(+{len(ids)-8})"
        lines.append(f"| `{d}` | {len(ids)} | {preview} |")
    return "\n".join(lines) + "\n"


def collect_templates() -> list[tuple[str, str]]:
    rows = []
    if not TEMPLATES.is_dir():
        return rows
    for p in sorted(TEMPLATES.glob("*.template.R")):
        text = p.read_text(encoding="utf-8", errors="replace")[:2500]
        # first non-empty comment line after banner
        purpose = p.stem
        for line in text.splitlines()[:40]:
            s = line.strip()
            if s.startswith("#") and "——" in s:
                purpose = s.lstrip("# ").strip()
                break
            if s.startswith("#") and "template" in s.lower() and len(s) > 20:
                purpose = s.lstrip("# ").strip()
                break
        # extract 【必改】 if present
        must = ""
        m = re.search(r"【必改键一览】[：:]?\s*([\s\S]{0,400}?)(?:【不要改】|# ──|config\s*<-)", text)
        if m:
            must = re.sub(r"\s+", " ", m.group(1)).strip()[:240]
        rows.append((p.relative_to(ROOT).as_posix(), purpose[:160], must))
    return rows


def render_templates(rows: list[tuple[str, str, str]]) -> str:
    lines = [
        "写新 config：**先复制最近 template**，再改【必改】键。",
        "",
        "| template | 说明 | 【必改】摘要 |",
        "|---|---|---|",
    ]
    for path, purpose, must in rows:
        must_cell = must.replace("|", "\\|") if must else "见文件头"
        purpose_cell = purpose.replace("|", "\\|")
        lines.append(f"| `{path}` | {purpose_cell} | {must_cell} |")
    return "\n".join(lines) + "\n"


def extract_pipeline_snippets() -> str:
    """Pull blocks=c(...) from a few key templates for copy-paste orientation."""
    keys = [
        "config_incidence_dual_batch.template.R",
        "config_survival_dual_batch.template.R",
        "config_competing_risk_stroke_batch.template.R",
        "config_ml_dual_batch.template.R",
        "config_ipw_diabetes_stroke_batch.template.R",
        "config_crm_nhanes_mr_batch.template.R",
        "config_two_stage_transformer_stroke.template.R",
    ]
    lines = [
        "以下从母版 template 抽取 `blocks = c(...)`（只读参考；研究区默认勿手改 pipeline，用 `add_block`）。",
        "",
    ]
    for name in keys:
        path = TEMPLATES / name
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        lines.append(f"### `{path.relative_to(ROOT).as_posix()}`")
        lines.append("")
        # find all pipeline_* <- list( ... blocks = c( ... ) )
        for m in re.finditer(
            r"(pipeline[_a-zA-Z0-9]*)\s*<-\s*list\s*\([\s\S]*?blocks\s*=\s*(c\([\s\S]*?\))",
            text,
        ):
            pname = m.group(1)
            vec = m.group(2)
            # compress whitespace
            vec_one = re.sub(r"\s+", " ", vec).strip()
            if len(vec_one) > 500:
                vec_one = vec_one[:500] + " ...)"
            lines.append(f"- `{pname}$blocks`: `{vec_one}`")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


DEFAULT_MANUAL = """\
<!-- MANUAL:HOW_TO_USE -->
## 0. 怎么用这份文档

1. 先看 **§1 研究类型 → 默认套路**，选定 template。
2. 再看 **§5 变体对照**，避免选错 `*_nhanes` / `*_incidence` / `*_prognosis`。
3. 打开对应 template，改【必改】键；**默认不要改** `pipeline$blocks`。
4. 需要核对键名/前置条件时，用 **§8 Block 卡片** 定位，再回读 `Blocks/...` 文件头。
5. 程序员隔离跑批流程见 `docs/block操作手册.md`；本文件只做 **block / config 选型字典**。

约定：
- pipeline 里的名字 = **`register_block` 名**，不是 `.R` 文件名。
- AUTO 段由 `python3 scripts/update_blocks_catalog.py` 重生成；`<!-- MANUAL:... -->` 段可手改并会被保留。
<!-- /MANUAL:HOW_TO_USE -->

<!-- MANUAL:ROUTINES -->
## 1. 研究类型 → 默认套路

| 场景 | 推荐 template | study_type / 备注 | 心智模型 |
|---|---|---|---|
| 双库发病（NHANES+临床库等） | `configs/templates/config_incidence_dual_batch.template.R` | `incidence` | 共享洗数 → 每库/每指标分析 |
| 双库预后 / 生存 | `configs/templates/config_survival_dual_batch.template.R` | `prognosis` | Cox / KM / 亚组 |
| 单库 NHANES 发病 | `configs/templates/config_incidence_nhanes_batch.template.R` | `incidence` + 权重 | survey design |
| 竞争风险（卒中等） | `configs/templates/config_competing_risk_stroke_batch.template.R` | competing | `55_competing_risk_full` |
| IPW 糖尿病-卒中 | `configs/templates/config_ipw_diabetes_stroke_batch.template.R` | IPW | `69_ipw_*` |
| CRM NHANES + MR | `configs/templates/config_crm_nhanes_mr_batch.template.R` | NHANES pub | `70_crm_nhanes_pub` |
| 两阶段 Transformer | `configs/templates/config_two_stage_transformer_stroke.template.R` | TST | `71_two_stage_transformer_stroke` |
| ML 双库 | `configs/templates/config_ml_dual_batch.template.R` | ml | `22_ml_models` 等 |
| 环境暴露 / VOC | `configs/templates/config_environment_dkd_batch.template.R` | environment | `35–46` + environment full |
| 轨迹预后 | `configs/templates/config_trajectory_prognosis_batch.template.R` | trajectory | `53_trajectory_*` |

专题设计说明（非选型字典）：`docs/superpowers/specs/`。
<!-- /MANUAL:ROUTINES -->

<!-- MANUAL:GLOBAL_KEYS -->
## 2. 全局 config 地图（跨 block 共用）

| 节 | 常见键 | 谁在用（典型） |
|---|---|---|
| `project` | `study_type`, `classification_mode`, `disease*`, `analysis_group`, `reference_group`, `output_dir`, `use_step_prefixed_block_dirs` | 几乎所有 block |
| `data` | `rawdata_path`, `rawdata_obj`, `id_column`, `outcome_*` | 洗数 / 插补 / 基线 |
| `incidence` | `outcome_var`, `index_var`, `index_*` | 发病 logistic / 单多因素 |
| `survival` | `time_var`, `event_var`, `index_var` | Cox / KM / 预后亚组 |
| `nhanes` | `survey_weight`, `survey_cluster`, `survey_strata`, `exclude_cols` | `*_nhanes*` / weighted |
| `dual_db` | `primary` / `secondary` 路径与映射 | `00_dual_db/*` |
| `index` | `enable`, `only`, `skip`, `digits` | `00_index` |
| `column_mapping` | `enable`, `database_type` | `01_column_mappings` |
| `imputation` | `method`, `m`, thresholds | `03_imputation` |
| `data_clean` | `missing_threshold`, `drop_columns` | `02_data_clean` |
| `plot` | `font_family` | 出图块 |

单块专有键见 §8 卡片的 `config$<block_id>`。
<!-- /MANUAL:GLOBAL_KEYS -->

<!-- MANUAL:PITFALLS -->
## 3. 常见坑（手维）

- `baseline_binary`：分层列必须恰好 2 水平，否则 pause/stop。
- 选 `*_nhanes_weighted` 前确认 `nhanes$survey_*` 列名与 `exclude_cols`。
- 双库：引擎内部槽位仍常称 nhanes(主)/mimic(副)；子目录名跟 `dual_db$*$name`。
- 竞争风险 / IPW / TST：优先整包 template，不要从零拼 `55/69/70/71`。
- 研究区勿手改母版 `pipeline$blocks` 绕过 `add_block`（见操作手册）。
<!-- /MANUAL:PITFALLS -->
"""


def extract_manual_sections(existing: str | None) -> dict[str, str]:
    """Return mapping name -> full block including markers."""
    if not existing:
        return {}
    out = {}
    for m in re.finditer(
        r"(<!-- MANUAL:([A-Z0-9_]+) -->\n)([\s\S]*?)(\n<!-- /MANUAL:\2 -->)",
        existing,
    ):
        out[m.group(2)] = m.group(0)
    return out


def manual_block(name: str, preserved: dict[str, str], defaults: dict[str, str]) -> str:
    if name in preserved:
        return preserved[name]
    # from DEFAULT_MANUAL parse
    if name in defaults:
        return defaults[name]
    return f"<!-- MANUAL:{name} -->\n\n<!-- /MANUAL:{name} -->"


def parse_default_manuals() -> dict[str, str]:
    return extract_manual_sections(DEFAULT_MANUAL)


def build_catalog(blocks: list[dict], existing: str | None) -> str:
    preserved = extract_manual_sections(existing or "")
    defaults = parse_default_manuals()
    # optional sidecar overrides whole manual file sections
    if MANUAL_SIDE.is_file():
        side = extract_manual_sections(MANUAL_SIDE.read_text(encoding="utf-8"))
        preserved = {**defaults, **preserved, **side}

    today = dt.date.today().isoformat()
    tmpl_rows = collect_templates()

    parts = [
        "# Blocks 选型目录（写 config 用）",
        "",
        f"> 生成/同步：`python3 scripts/update_blocks_catalog.py`  ·  日期：{today}  ·  "
        f"register_block 数：{len(blocks)}",
        "",
        "分工：`docs/block操作手册.md` = 怎么跑研究；本文件 = **选哪个 block / 改哪些 config 键**；"
        "`docs/block_catalog/` = 程序员 search_blocks 只读导出（另一套）。",
        "",
        manual_block("HOW_TO_USE", preserved, defaults),
        "",
        manual_block("ROUTINES", preserved, defaults),
        "",
        manual_block("GLOBAL_KEYS", preserved, defaults),
        "",
        manual_block("PITFALLS", preserved, defaults),
        "",
        "<!-- BEGIN AUTO:dir_index -->",
        "## 4. 目录速览（AUTO）",
        "",
        render_dir_index(blocks),
        "<!-- END AUTO:dir_index -->",
        "",
        "<!-- BEGIN AUTO:variants -->",
        "## 5. 变体对照（AUTO）",
        "",
        variant_tables(blocks),
        "<!-- END AUTO:variants -->",
        "",
        "<!-- BEGIN AUTO:templates -->",
        "## 6. Template 索引（AUTO）",
        "",
        render_templates(tmpl_rows),
        "<!-- END AUTO:templates -->",
        "",
        "<!-- BEGIN AUTO:pipelines -->",
        "## 7. 已验证 pipeline 片段（AUTO）",
        "",
        extract_pipeline_snippets(),
        "<!-- END AUTO:pipelines -->",
        "",
        "<!-- BEGIN AUTO:block_cards -->",
        "## 8. Block 卡片（AUTO）",
        "",
        render_block_cards(blocks),
        "<!-- END AUTO:block_cards -->",
        "",
        "<!-- BEGIN AUTO:id_list -->",
        "## 9. 全量 register_block 列表（AUTO）",
        "",
        ", ".join(f"`{b['id']}`" for b in sorted(blocks, key=lambda x: x["id"])),
        "",
        "<!-- END AUTO:id_list -->",
        "",
    ]
    return "\n".join(parts).rstrip() + "\n"


def ids_in_catalog(text: str) -> set[str]:
    # from section 9 or cards
    return set(re.findall(r"#### `([^`]+)`", text)) | set(
        re.findall(r"## 9[\s\S]*?\n(`[^`]+`(,\s*`[^`]+`)*)", text)
    )  # weak


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="exit 1 if catalog would change")
    ap.add_argument(
        "--only-new",
        action="store_true",
        help="print register_block ids missing from catalog cards",
    )
    ap.add_argument("--out", type=Path, default=OUT)
    args = ap.parse_args()

    blocks = collect_blocks()
    existing = args.out.read_text(encoding="utf-8") if args.out.is_file() else None
    new_text = build_catalog(blocks, existing)

    if args.only_new:
        have = set(re.findall(r"#### `([^`]+)`", existing or ""))
        missing = [b["id"] for b in blocks if b["id"] not in have]
        for m in missing:
            print(m)
        print(f"# missing={len(missing)} total={len(blocks)}", file=sys.stderr)
        return 0

    if args.check:
        if existing is None or existing != new_text:
            print("STALE: docs/Blocks_catalog.md needs update", file=sys.stderr)
            return 1
        print("OK: catalog up to date")
        return 0

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(new_text, encoding="utf-8")
    print(f"Wrote {args.out.relative_to(ROOT)} ({len(blocks)} blocks, {len(new_text)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
