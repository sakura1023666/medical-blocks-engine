#!/usr/bin/env python3
"""Pack ULN-all3 as main summary_results + bili/ALT/AST as sensitivity S tables/figs.

Main cohort: AST≥38 AND ALT≥41 AND TBil≥1.3 mg/dL (all above ULN).
Sensitivity (supplement only):
  - bili only  → Table S3/S4, Figure S1
  - ALT only   → Table S5/S6, Figure S2
  - AST only   → Table S7/S8, Figure S3

Does not overwrite ACG summary_results. Default out:
  /mnt/sda/liver_uln_pub/summary_results_uln_triple
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

from openpyxl import load_workbook

SCRIPT_DIR = Path(__file__).resolve().parent
FINALIZE = SCRIPT_DIR / "finalize_easl_paper_pub.py"
PY = sys.executable

ROOTS = {
    "all3": Path("/mnt/sda/BlendedICU/data/liver_dysfunction_uln_all3_42151996"),
    "bili": Path("/mnt/sda/BlendedICU/data/liver_dysfunction_uln_bili_42151996"),
    "alt": Path("/mnt/sda/BlendedICU/data/liver_dysfunction_uln_alt_42151996"),
    "ast": Path("/mnt/sda/BlendedICU/data/liver_dysfunction_uln_ast_42151996"),
}

# Feature-set wording (全包统一)：参考既往多数据库 ICU 预测文献；仅队列定义用实验室不进模。
_LIT_FEATURE = (
    "Model covariates followed prior multi-database ICU mortality/RLoS prediction literature; "
    "laboratories used only to define the cohort were not included as predictors"
)
COHORT_META = {
    "all3": {
        "title": "ULN-all3 lab-gate",
        "rule": "First AST≥38 and ALT≥41 and TBil≥1.3 mg/dL (all >ULN)",
        "note_zh": "三者均超 ULN 实验室门控（AST≥38 且 ALT≥41 且 TBil≥1.3 mg/dL）；特征集参考既往文献，纳入用 AST/ALT/胆红素不进模。",
        "subset_zh": "ULN-all3 子集",
        "drop_en": f"{_LIT_FEATURE} (AST, ALT and bilirubin).",
        "blended": "blendedlos_uln_all3",
        "drop_ts": "aspartate_aminotransferase,alanine_aminotransferase,bilirubine",
    },
    "bili": {
        "title": "ULN-bilirubin only",
        "rule": "First TBil≥1.3 mg/dL (22.23 µmol/L)",
        "note_zh": "仅胆红素≥1.3 mg/dL（ULN）敏感性分析；特征集参考既往文献，纳入用胆红素不进模。",
        "subset_zh": "ULN-bilirubin 子集",
        "drop_en": f"{_LIT_FEATURE} (bilirubin).",
        "blended": "blendedlos_uln_bili",
        "drop_ts": "bilirubine",
    },
    "alt": {
        "title": "ULN-ALT only",
        "rule": "First ALT≥41 U/L",
        "note_zh": "仅 ALT≥41 U/L（ULN）敏感性分析；特征集参考既往文献，纳入用 ALT 不进模。",
        "subset_zh": "ULN-ALT 子集",
        "drop_en": f"{_LIT_FEATURE} (ALT).",
        "blended": "blendedlos_uln_alt",
        "drop_ts": "alanine_aminotransferase",
    },
    "ast": {
        "title": "ULN-AST only",
        "rule": "First AST≥38 U/L",
        "note_zh": "仅 AST≥38 U/L（ULN）敏感性分析；特征集参考既往文献，纳入用 AST 不进模。",
        "subset_zh": "ULN-AST 子集",
        "drop_en": f"{_LIT_FEATURE} (AST).",
        "blended": "blendedlos_uln_ast",
        "drop_ts": "aspartate_aminotransferase",
    },
}

# sensitivity → (table2_s, table3_s, fig2_s, title_label, ascii_file_label)
# Filenames stay ASCII-safe (some SMB/NFS mounts choke on ≥).
SENS_MAP = {
    "bili": ("S3", "S4", "S1", "bilirubin ≥1.3 mg/dL only", "bilirubin ge1.3 only"),
    "alt": ("S5", "S6", "S2", "ALT ≥41 U/L only", "ALT ge41 only"),
    "ast": ("S7", "S8", "S3", "AST ≥38 U/L only", "AST ge38 only"),
}

PUB_OUT = Path(
    os.environ.get(
        "ULN_TRIPLE_PUB_OUT",
        "/mnt/sda/liver_uln_pub/summary_results_uln_triple",
    )
)
STAGING = Path(
    os.environ.get(
        "ULN_TRIPLE_STAGING",
        "/mnt/sda/liver_uln_pub/_staging_uln_sens",
    )
)
ACG_TABLE4 = Path(
    os.environ.get(
        "ACG_TABLE4",
        "/mnt/g/02block_result/50_Cirrhosis/database_pooled_42151996/"
        "summary_results/Tables/Table 4. Literature comparison.xlsx",
    )
)


def _run_finalize(key: str, out: Path, *, skip_table1: bool = False, skip_delivery: bool = False) -> None:
    meta = COHORT_META[key]
    root = ROOTS[key]
    env = os.environ.copy()
    env.update(
        {
            "LIVER_ROOT": str(root),
            "LIVER_PUB_OUT": str(out),
            "LIVER_BLENDED_SUBDIR": meta["blended"],
            "LIVER_COHORT_TITLE": meta["title"],
            "LIVER_COHORT_RULE_SHORT": meta["rule"],
            "LIVER_COHORT_NOTE_ZH": meta["note_zh"],
            "LIVER_COHORT_SUBSET_ZH": meta["subset_zh"],
            "LIVER_FEATURE_DROP_EN": meta["drop_en"],
            "DBPOOL_DROP_TS": meta["drop_ts"],
            "DBPOOL_COHORT": meta["title"],
            "DBPOOL_DROP_FEATURES": meta["drop_en"],
            "LIVER_TABLE1_FOOTNOTE": (
                f"{meta['title']} ({meta['rule']}). "
                "Continuous: mean [SD] (vitals/labs = stay-level hourly mean after physiological-range clip, "
                "then cohort mean [SD]). Drug exposure: any hourly dose >0 during the stay. "
                "Unit type from BlendedICU labels (HiRID often Unknown). "
                f"{meta['drop_en']} "
                "Vitals/labs clipped to a priori physiological ranges (same bounds as model preprocess)."
            ),
            "LIVER_SCALE_FEATURE_NOTE": meta["drop_en"],
            "MEDICAL_BLOCKS_ROOT": "/mnt/sda/r-platform-data/user02/home/medical-blocks/engine",
            "ACG_TABLE4": str(ACG_TABLE4) if ACG_TABLE4.exists() else str(
                Path("/mnt/sda/liver_uln_pub/_seed/Table 4. Literature comparison.xlsx")
            ),
        }
    )
    if skip_table1:
        env["LIVER_SKIP_TABLE1"] = "1"
    if skip_delivery:
        env["LIVER_SKIP_DELIVERY"] = "1"
    out.mkdir(parents=True, exist_ok=True)
    print(f"[pack] finalize {key} → {out} (skip_table1={skip_table1})", flush=True)
    subprocess.run([PY, str(FINALIZE)], check=True, env=env)


def _retitle_xlsx(src: Path, dst: Path, new_title: str, footnote_prefix: str | None = None) -> None:
    shutil.copy2(src, dst)
    wb = load_workbook(dst)
    ws = wb.active
    old = ws.cell(1, 1).value
    if isinstance(old, str) and old.strip():
        # Replace leading "Table N." / keep rest after first period if present
        if ". " in old:
            rest = old.split(". ", 1)[1]
            ws.cell(1, 1).value = f"{new_title}. {rest}"
        else:
            ws.cell(1, 1).value = new_title
    else:
        ws.cell(1, 1).value = new_title
    if footnote_prefix:
        # Footnote is typically 2 rows below last data; scan last 8 rows for long text
        for r in range(ws.max_row, max(1, ws.max_row - 12), -1):
            v = ws.cell(r, 1).value
            if isinstance(v, str) and len(v) > 40:
                if not v.startswith(footnote_prefix):
                    ws.cell(r, 1).value = footnote_prefix + v
                break
    wb.save(dst)


def _copy_fig(src_dir: Path, dst_dir: Path, src_name: str, dst_name: str) -> None:
    for kind, ext in (("pdf", "pdf"), ("png", "png"), ("tiff", "tiff")):
        s = src_dir / kind / f"{src_name}.{ext}"
        if not s.exists():
            continue
        d = dst_dir / kind
        d.mkdir(parents=True, exist_ok=True)
        shutil.copy2(s, d / f"{dst_name}.{ext}")
    info_s = src_dir / "image_information" / f"{src_name}.md"
    if info_s.exists():
        info_d = dst_dir / "image_information"
        info_d.mkdir(parents=True, exist_ok=True)
        text = info_s.read_text(encoding="utf-8")
        text = text.replace(f"# {src_name}", f"# {dst_name}", 1)
        text = text.replace(src_name, dst_name)
        (info_d / f"{dst_name}.md").write_text(text, encoding="utf-8")


def _merge_sensitivity(main: Path) -> None:
    tables = main / "Tables"
    figs = main / "Figures"
    tables.mkdir(parents=True, exist_ok=True)
    for key, (t2s, t3s, f2s, label, file_lab) in SENS_MAP.items():
        st = STAGING / key
        t2 = st / "Tables" / "Table 2. Internal and external.xlsx"
        t3 = st / "Tables" / "Table 3. Four training strategies.xlsx"
        if not t2.exists() or not t3.exists():
            raise SystemExit(f"missing sensitivity tables under {st}/Tables")
        pref = f"Sensitivity analysis ({label}). "
        _retitle_xlsx(
            t2,
            tables / f"Table {t2s}. Internal and external ({file_lab}).xlsx",
            f"Table {t2s}",
            footnote_prefix=pref,
        )
        # Prefer human ≥ in A1 title body
        p2 = tables / f"Table {t2s}. Internal and external ({file_lab}).xlsx"
        wb = load_workbook(p2)
        ws = wb.active
        v = ws.cell(1, 1).value
        if isinstance(v, str):
            ws.cell(1, 1).value = v.replace(file_lab, label)
        wb.save(p2)
        _retitle_xlsx(
            t3,
            tables / f"Table {t3s}. Four training strategies ({file_lab}).xlsx",
            f"Table {t3s}",
            footnote_prefix=pref,
        )
        p3 = tables / f"Table {t3s}. Four training strategies ({file_lab}).xlsx"
        wb = load_workbook(p3)
        ws = wb.active
        v = ws.cell(1, 1).value
        if isinstance(v, str):
            ws.cell(1, 1).value = v.replace(file_lab, label)
        wb.save(p3)
        _copy_fig(
            st / "Figures",
            figs,
            "Figure 2. Training size",
            f"Figure {f2s}. Training size ({file_lab})",
        )
        # patch fig md title to use human label
        md = figs / "image_information" / f"Figure {f2s}. Training size ({file_lab}).md"
        if md.exists():
            md.write_text(
                md.read_text(encoding="utf-8").replace(file_lab, label),
                encoding="utf-8",
            )
        print(f"[pack] merged sensitivity {key} → Table {t2s}/{t3s}, Figure {f2s}", flush=True)


def _copy_table4(main: Path) -> None:
    dst = main / "Tables" / "Table 4. Literature comparison.xlsx"
    if dst.exists():
        return
    # Prefer local ACG path; else optional env copy already on 34
    candidates = [
        ACG_TABLE4,
        Path("/mnt/sda/liver_uln_pub/_seed/Table 4. Literature comparison.xlsx"),
    ]
    for src in candidates:
        if src.exists():
            shutil.copy2(src, dst)
            print(f"[pack] copied Table 4 from {src}", flush=True)
            return
    print("[pack] WARN no Table 4 seed; skip", flush=True)


def _patch_methods(main: Path) -> None:
    md = main / "Methods_statistical_analysis.md"
    if not md.exists():
        print("[pack] WARN no Methods md yet; skip sensitivity patch", flush=True)
        return
    text = md.read_text(encoding="utf-8")
    block = (
        "\n## Sensitivity analyses (single-lab ULN gates)\n"
        "The primary cohort required AST, ALT and total bilirubin all above laboratory ULN "
        "(AST ≥38 U/L, ALT ≥41 U/L, total bilirubin ≥1.3 mg/dL). "
        "Three sensitivity cohorts used one lab gate only: bilirubin ≥1.3 mg/dL "
        "(Tables S3–S4, Figure S1); ALT ≥41 U/L (Tables S5–S6, Figure S2); "
        "AST ≥38 U/L (Tables S7–S8, Figure S3). "
        "Training strategies, TPC architecture, metrics and uncertainty methods matched the main analysis; "
        "only the cohort-defining laboratory (and its corresponding exclusion from predictors, "
        "consistent with the literature-referenced feature set) differed. "
        "In Table 3 / S4 / S6 / S8, Transfer Learning dashes for MIMIC-IV specialisation and "
        "eICU/HiRID generalisation are by design (Transfer reports AmsterdamUMC specialisation only).\n"
    )
    if "Sensitivity analyses (single-lab ULN gates)" in text:
        # replace existing block roughly
        import re

        text = re.sub(
            r"\n## Sensitivity analyses \(single-lab ULN gates\).*?(?=\n## |\Z)",
            block,
            text,
            flags=re.S,
        )
    else:
        # insert before ## Software if present
        if "\n## Software" in text:
            text = text.replace("\n## Software", block + "\n## Software", 1)
        else:
            text = text.rstrip() + "\n" + block
    # Fix cohort wording if delivery still says EASL/ACG remnant
    text = text.replace(
        "ACG-style enzyme elevation (ALT/AST ≥2×ULN)",
        "ULN-all3 laboratory gate (AST ≥38 U/L, ALT ≥41 U/L and total bilirubin ≥1.3 mg/dL)",
    )
    text = text.replace(
        "Inclusion enzymes used only for cohort definition were excluded from model features (ALT and AST).",
        "Inclusion laboratories used only for cohort definition were excluded from model features "
        "(AST, ALT and bilirubin in the main analysis).",
    )
    md.write_text(text, encoding="utf-8")
    print("[pack] Methods sensitivity section written", flush=True)


def _prune_delivery(main: Path) -> None:
    """Whitelist-ish prune: keep Figures/Tables/Methods*/中期; move rest to sibling workspace."""
    keep_names = {
        "Figures",
        "Tables",
        "Methods_statistical_analysis.md",
        "Methods_software_versions.txt",
    }
    workspace = main.parent / f"{main.name}_delivery_workspace"
    workspace.mkdir(parents=True, exist_ok=True)
    for p in list(main.iterdir()):
        if p.name in keep_names:
            continue
        if p.name.endswith("中期分析结果.pdf") or "中期" in p.name:
            continue
        dest = workspace / p.name
        if dest.exists():
            if dest.is_dir():
                shutil.rmtree(dest)
            else:
                dest.unlink()
        shutil.move(str(p), str(dest))
        print(f"[pack] pruned {p.name} → {workspace.name}/", flush=True)


def main() -> None:
    if not FINALIZE.exists():
        raise SystemExit(f"missing {FINALIZE}")
    for k, root in ROOTS.items():
        if not (root / "Output_physclip").is_dir():
            raise SystemExit(f"missing Output_physclip for {k}: {root}")
        if not (root / "Output_paper_extras_physclip").is_dir():
            raise SystemExit(f"missing extras for {k}: {root}")

    # 1) main all3 (reuse if already finalized)
    main_ready = (
        (PUB_OUT / "Tables" / "Table 2. Internal and external.xlsx").exists()
        and (PUB_OUT / "Tables" / "Table 3. Four training strategies.xlsx").exists()
        and (PUB_OUT / "Figures" / "pdf" / "Figure 2. Training size.pdf").exists()
    )
    force_main = os.environ.get("ULN_FORCE_MAIN", "").strip() in ("1", "true", "yes")
    if main_ready and not force_main:
        print(f"[pack] reuse existing main pack {PUB_OUT}", flush=True)
    else:
        if PUB_OUT.exists():
            shutil.rmtree(PUB_OUT)
        _run_finalize("all3", PUB_OUT)

    # 2) sensitivity staging (Table2/3/Fig2 only — skip slow Table1 + delivery)
    force_sens = os.environ.get("ULN_FORCE_SENS", "").strip().lower() in ("1", "true", "yes")
    sens_ready = all(
        (STAGING / k / "Tables" / "Table 2. Internal and external.xlsx").exists()
        and (STAGING / k / "Tables" / "Table 3. Four training strategies.xlsx").exists()
        for k in ("bili", "alt", "ast")
    )
    if sens_ready and not force_sens:
        print(f"[pack] reuse existing sensitivity staging {STAGING}", flush=True)
    else:
        if STAGING.exists():
            shutil.rmtree(STAGING)
        for key in ("bili", "alt", "ast"):
            _run_finalize(key, STAGING / key, skip_table1=True, skip_delivery=True)

    # 3) merge S tables/figs into main
    _merge_sensitivity(PUB_OUT)
    _copy_table4(PUB_OUT)

    # 4) Engine-level delivery: Times/underscore scrub + Methods/software + QC + whitelist
    engine = Path("/mnt/e/01block/01Block-new-Final")
    thin = engine / "run" / "dbpool" / "finalize_summary_delivery.R"
    if thin.exists():
        env = os.environ.copy()
        env["MEDICAL_BLOCKS_ROOT"] = str(engine)
        meta = COHORT_META["all3"]
        subprocess.run(
            [
                "Rscript",
                str(thin),
                "--dir",
                str(PUB_OUT),
                "--cohort",
                "ULN-all3 laboratory gate (AST ≥38 U/L, ALT ≥41 U/L and total bilirubin ≥1.3 mg/dL)",
                "--feature-set",
                meta["drop_en"],
            ],
            check=False,
            env=env,
        )
    # 5) ULN sensitivity Methods patch AFTER engine Methods write, then prune again
    _patch_methods(PUB_OUT)
    _prune_delivery(PUB_OUT)

    print("[pack] DONE", PUB_OUT, flush=True)
    print("tables:", sorted(p.name for p in (PUB_OUT / "Tables").glob("*.xlsx")))
    print(
        "figures:",
        sorted(p.name for p in (PUB_OUT / "Figures" / "pdf").glob("*.pdf"))
        if (PUB_OUT / "Figures" / "pdf").exists()
        else [],
    )


if __name__ == "__main__":
    main()
