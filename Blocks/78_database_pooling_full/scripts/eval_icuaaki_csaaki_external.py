#!/usr/bin/env python3
"""Frozen ICU-AKI (units) TPC → CSA-AKI domain-shift validation (supplementary).

Uses existing test_predictions_* from ICUAKI arms B/D; filters stays that appear in
the CSA-AKI cardiac perioperative DN=1 pack. Primary clean external slice = eICU
CSA-AKI (subset of ICUAKI eICU external). MIMIC-IV CSA-AKI uses only stays that
were in the ICUAKI MIMIC internal test (excludes training overlap). SICdb/INSPIRE
are documented as not scored (feature schema incompatible with frozen weights).

Writes into ICUAKI summary_results (顺延):
  Table S6  CSA-AKI external performance
  Table S7  Pooling vs MIMIC-IV DeLong on CSA-AKI eICU
  Figure S1  ROC (CSA-AKI eICU / MIMIC holdout)

Env:
  ICUAKI_ROOT, ICUAKI_MAIN_OUT, ICUAKI_PUB_OUT, ICUAKI_N_BOOT,
  CSAAKI_LABELS (default …/csaaki_gongqian_42151996/blendedlos_csaaki/preprocessed_labels.parquet)
"""
from __future__ import annotations

import importlib.util
import json
import os
import re
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, Side
from openpyxl.utils import get_column_letter
from sklearn.metrics import average_precision_score, roc_auc_score, roc_curve

ENGINE_SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(ENGINE_SCRIPTS))
from dbpool_pub_digits import DIGITS, fmt_ci, fmt_est, fmt_p  # noqa: E402

ROOT = Path(
    os.environ.get(
        "ICUAKI_ROOT",
        "/mnt/sda/BlendedICU/data/icuaaki_4db_20261106",
    )
)
MAIN_OUT = Path(
    os.environ.get("ICUAKI_MAIN_OUT", str(ROOT / "Output_database_pooling_units"))
)
PUB = Path(
    os.environ.get(
        "ICUAKI_PUB_OUT",
        str(ROOT / "summary_results_units"),
    )
)
BLENDED = ROOT / os.environ.get("ICUAKI_BLENDED_SUBDIR", "blendedlos_icuaaki_units")
CSA_LABELS = Path(
    os.environ.get(
        "CSAAKI_LABELS",
        "/mnt/sda/BlendedICU/data/csaaki_gongqian_42151996/blendedlos_csaaki/preprocessed_labels.parquet",
    )
)
N_BOOT = int(os.environ.get("ICUAKI_N_BOOT", "2000"))
EXTRA_OUT = Path(
    os.environ.get(
        "ICUAKI_CSA_EXTRA",
        str(ROOT / "Output_paper_extras_units" / "csaaki_external"),
    )
)

ARM = {
    "MIMIC-IV only": ("liver_expB_mimic_solo", "mimic4_100/"),
    "Pooling": ("liver_expD_pooled_mimic_amsterdam", "amsterdam_mimic4_100/"),
}
DB_LAB = {"eicu": "eICU", "mimic4": "MIMIC-IV"}

plt.rcParams.update(
    {
        "font.family": "serif",
        "font.serif": [
            "Times New Roman",
            "Times",
            "Nimbus Roman",
            "Liberation Serif",
            "DejaVu Serif",
        ],
        "font.size": 9,
        "axes.labelsize": 10,
        "axes.titlesize": 11,
        "axes.linewidth": 0.8,
        "legend.fontsize": 8,
        "pdf.fonttype": 42,
        "ps.fonttype": 42,
    }
)


def _disp(s: str) -> str:
    return re.sub(r"_+", " ", str(s)).strip()


def _scrub(s: str) -> str:
    return _disp(s).replace("_", " ")


def _norm_id(x: str) -> str:
    return str(x).replace(":", "-").strip()


def _load_ci_mod():
    p = ENGINE_SCRIPTS / "eval_liver_paper_ci.py"
    spec = importlib.util.spec_from_file_location("eval_liver_paper_ci", p)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


def _pick_pred(unit_dir: Path, prefer: str, kind: str) -> Path:
    hits = sorted(unit_dir.glob(f"results/**/{prefer}*/**/test_predictions_{kind}.csv"))
    if not hits:
        hits = sorted(unit_dir.glob(f"results/**/test_predictions_{kind}.csv"))
    if not hits:
        raise FileNotFoundError(f"no test_predictions_{kind} in {unit_dir}")
    return hits[-1]


def _save_table(df: pd.DataFrame, path: Path, *, title: str, footnote: str | None = None):
    path.parent.mkdir(parents=True, exist_ok=True)
    title = _scrub(title)
    if footnote:
        footnote = _scrub(footnote)
    out = df.copy()
    out.columns = [_scrub(c) for c in out.columns]
    for c in out.columns:
        if out[c].dtype == object:
            out[c] = out[c].map(lambda v: _scrub(v) if isinstance(v, str) else v)
    xlsx_p = Path(str(path) + ".xlsx")
    wb = Workbook()
    ws = wb.active
    ws.title = "Table"
    ws.sheet_view.showGridLines = False
    nc = max(1, len(out.columns))
    thick = Side(style="medium", color="000000")
    thin = Side(style="thin", color="000000")
    font_title = Font(name="Times New Roman", bold=True, size=12)
    font_h = Font(name="Times New Roman", bold=True, size=12)
    font_b = Font(name="Times New Roman", size=12)
    font_fn = Font(name="Times New Roman", size=10)
    align_c = Alignment(horizontal="center", vertical="center", wrap_text=True)
    align_l = Alignment(horizontal="left", vertical="center", wrap_text=True)
    r0 = 1
    cell = ws.cell(1, 1, title)
    cell.font = font_title
    cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
    if nc > 1:
        ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=nc)
    r0 = 2
    for j, col in enumerate(out.columns, 1):
        cell = ws.cell(r0, j, col)
        cell.font = font_h
        cell.alignment = align_c
        cell.border = Border(top=thick, bottom=thin)
    n = len(out)
    for i, row in enumerate(out.itertuples(index=False), r0 + 1):
        last = i == r0 + n
        for j, val in enumerate(row, 1):
            cell = ws.cell(i, j, "–" if val is None else val)
            cell.font = font_b
            cell.alignment = align_l if j == 1 else align_c
            if last:
                cell.border = Border(bottom=thick)
    if footnote:
        fr = r0 + n + 2
        cell = ws.cell(fr, 1, footnote)
        cell.font = font_fn
        cell.alignment = align_l
        if nc > 1:
            ws.merge_cells(start_row=fr, start_column=1, end_row=fr, end_column=nc)
        cell.border = Border(top=thin)
    for j in range(1, nc + 1):
        ws.column_dimensions[get_column_letter(j)].width = 22
    wb.save(xlsx_p)
    print("[csa] wrote", xlsx_p, flush=True)


def _write_fig(fig, name: str):
    pdf_d = PUB / "Figures" / "pdf"
    pdf_d.mkdir(parents=True, exist_ok=True)
    fig.savefig(pdf_d / f"{name}.pdf", bbox_inches="tight")
    plt.close(fig)
    print("[csa] wrote", pdf_d / f"{name}.pdf", flush=True)


def _write_md(name: str, body: str):
    d = PUB / "Figures" / "image_information"
    d.mkdir(parents=True, exist_ok=True)
    p = d / f"{name}.md"
    p.write_text(body.strip() + "\n", encoding="utf-8")
    print("[csa] wrote", p, flush=True)


def _csa_ids() -> dict[str, set[str]]:
    lab = pd.read_parquet(CSA_LABELS)
    idx = lab.index.astype(str).map(_norm_id)
    out: dict[str, set[str]] = {}
    for db, g in lab.assign(_id=idx).groupby(lab["source_dataset"].astype(str)):
        out[str(db)] = set(g["_id"].tolist())
    return out


def _icu_mimic_test_ids() -> set[str]:
    p = BLENDED / "extraction" / "train_on_amsterdam_mimic4" / "test" / "labels.parquet"
    lab = pd.read_parquet(p)
    m = lab[lab["source_dataset"].astype(str) == "mimic4"]
    return set(m.index.astype(str).map(_norm_id))


def _icu_mimic_train_ids() -> set[str]:
    p = BLENDED / "extraction" / "train_on_amsterdam_mimic4" / "train" / "labels.parquet"
    lab = pd.read_parquet(p)
    m = lab[lab["source_dataset"].astype(str) == "mimic4"]
    return set(m.index.astype(str).map(_norm_id))


def _filter_preds(mort: pd.DataFrame, los: pd.DataFrame, keep: set[str], eval_on: str):
    m = mort[mort["eval_on"].astype(str) == eval_on].copy()
    m["stay"] = m["patientids"].astype(str).map(_norm_id)
    m = m[m["stay"].isin(keep)]
    l = los[los["eval_on"].astype(str) == eval_on].copy()
    l["stay"] = l["patientids"].astype(str).map(_norm_id)
    l = l[l["stay"].isin(keep)]
    return m, l


def _metrics_row(ci_mod, arm: str, cohort: str, db: str, stay: pd.DataFrame) -> dict:
    y = stay["y_mort"].to_numpy()
    p = stay["pred_mort"].to_numpy()
    n = int(len(stay))
    n_d = int(stay["y_mort"].sum())
    if stay["y_mort"].nunique() < 2:
        auc = lo = hi = auprc = float("nan")
        a_lo = a_hi = float("nan")
    else:
        auc, lo, hi = ci_mod.delong_auc_ci(y, p)
        auprc = float(average_precision_score(y, p))
        a_lo, a_hi = ci_mod._boot_ci_auprc(stay, n_boot=N_BOOT, seed=42)
    mape = float(stay["mape"].mean()) if "mape" in stay and stay["mape"].notna().any() else float("nan")
    mdf = stay.dropna(subset=["mape"]).copy() if "mape" in stay.columns else pd.DataFrame()
    if len(mdf):
        m_lo, m_hi = ci_mod._boot_ci_person(mdf, "mape", n_boot=N_BOOT, seed=42)
    else:
        m_lo = m_hi = float("nan")
    return {
        "Training strategy": arm,
        "CSA-AKI cohort": cohort,
        "Evaluation database": DB_LAB.get(db, db),
        "N stays": f"{n:,}",
        "Deaths": f"{n_d:,}",
        "AUROC": fmt_ci(auc, lo, hi, digits=DIGITS["auroc_supp"]),
        "AUPRC": fmt_ci(auprc, a_lo, a_hi, digits=DIGITS["auprc"]),
        "MAPE %": fmt_ci(mape, m_lo, m_hi, digits=DIGITS["mape_supp"]),
        "_auc": auc,
        "_n": n,
        "_deaths": n_d,
        "_stay": stay,
    }


def main():
    EXTRA_OUT.mkdir(parents=True, exist_ok=True)
    ci_mod = _load_ci_mod()
    csa = _csa_ids()
    mimic_test = _icu_mimic_test_ids()
    mimic_train = _icu_mimic_train_ids()

    csa_eicu = csa.get("eicu", set())
    csa_mimic = csa.get("mimic4", set())
    csa_mimic_holdout = csa_mimic & mimic_test
    csa_mimic_train_ov = csa_mimic & mimic_train
    csa_inspire = csa.get("inspire", set())
    csa_sicdb = csa.get("sicdb", set())

    meta = {
        "csa_eicu_n": len(csa_eicu),
        "csa_mimic_n": len(csa_mimic),
        "csa_mimic_holdout_n": len(csa_mimic_holdout),
        "csa_mimic_train_overlap_n": len(csa_mimic_train_ov),
        "csa_inspire_n": len(csa_inspire),
        "csa_sicdb_n": len(csa_sicdb),
        "note_inspire_sicdb": (
            "INSPIRE/SICdb CSA-AKI tensors lack the feature channels required by the "
            "frozen ICU-AKI TPC; not scored."
        ),
        "n_boot": N_BOOT,
    }
    (EXTRA_OUT / "csaaki_overlap_meta.json").write_text(
        json.dumps(meta, indent=2), encoding="utf-8"
    )
    print("[csa] meta", meta, flush=True)

    cohorts = [
        ("eICU CSA-AKI (external subgroup)", "eicu", csa_eicu),
        ("MIMIC-IV CSA-AKI (internal-test holdout)", "mimic4", csa_mimic_holdout),
    ]

    rows = []
    stay_cache: dict[tuple[str, str], pd.DataFrame] = {}
    for arm, (unit, prefer) in ARM.items():
        unit_dir = MAIN_OUT / unit
        mort = pd.read_csv(_pick_pred(unit_dir, prefer, "mort"))
        los = pd.read_csv(_pick_pred(unit_dir, prefer, "los"))
        for cohort, db, keep in cohorts:
            if not keep:
                continue
            m, l = _filter_preds(mort, los, keep, db)
            stay, hourly = ci_mod._stay_frame(m, l)
            stay.to_csv(EXTRA_OUT / f"stay_{unit}_{db}.csv", index=False)
            row = _metrics_row(ci_mod, arm, cohort, db, stay)
            stay_cache[(arm, db)] = row.pop("_stay")
            row.pop("_auc", None)
            n = row.pop("_n")
            dth = row.pop("_deaths")
            rows.append(row)
            print(
                f"[csa] {arm} | {cohort}: n={n} deaths={dth} AUROC={row['AUROC']}",
                flush=True,
            )

    df_s6 = pd.DataFrame(rows)
    _save_table(
        df_s6,
        PUB / "Tables" / "Table S6. CSA-AKI external validation",
        title="Table S6. Frozen ICU-AKI TPC performance on cardiac surgery–associated AKI (CSA-AKI) cohorts",
        footnote=(
            f"Models were trained on units-harmonized general ICU-AKI (AmsterdamUMC + MIMIC-IV) and not "
            f"retrained on CSA-AKI. eICU CSA-AKI stays are the cardiac perioperative DN=1 subset of the "
            f"ICU-AKI eICU external set (n={len(csa_eicu):,}). MIMIC-IV CSA-AKI uses only stays present in "
            f"the ICU-AKI MIMIC internal test (n={len(csa_mimic_holdout):,}); "
            f"{len(csa_mimic_train_ov):,} CSA MIMIC stays overlapped the training set and were excluded. "
            f"SICdb (n={len(csa_sicdb):,}) and INSPIRE (n={len(csa_inspire):,}) were not scored because "
            f"their CSA tensors lack the feature channels required by the frozen ICU-AKI TPC. "
            f"AUROC 95% CI: DeLong (stay level). AUPRC/MAPE 95% CI: patient-level percentile bootstrap "
            f"({N_BOOT:,} resamples). MAPE among predicted survivors."
        ),
    )

    # Table S7: paired DeLong on shared CSA-AKI eICU stays
    st_b = stay_cache.get(("MIMIC-IV only", "eicu"))
    st_d = stay_cache.get(("Pooling", "eicu"))
    s7_rows = []
    if st_b is not None and st_d is not None:
        merged = st_b[["stay", "y_mort", "pred_mort"]].merge(
            st_d[["stay", "pred_mort"]],
            on="stay",
            suffixes=("_B", "_D"),
        )
        y = merged["y_mort"].to_numpy()
        p_b = merged["pred_mort_B"].to_numpy()
        p_d = merged["pred_mort_D"].to_numpy()
        auc_b, lo_b, hi_b = ci_mod.delong_auc_ci(y, p_b)
        auc_d, lo_d, hi_d = ci_mod.delong_auc_ci(y, p_d)
        p_del = ci_mod.delong_paired_pvalue(y, p_d, p_b)
        s7_rows.append(
            {
                "Cohort": "eICU CSA-AKI",
                "N shared stays": f"{len(merged):,}",
                "MIMIC-IV only AUROC": fmt_ci(auc_b, lo_b, hi_b, digits=DIGITS["auroc_supp"]),
                "Pooling AUROC": fmt_ci(auc_d, lo_d, hi_d, digits=DIGITS["auroc_supp"]),
                "Pooling minus MIMIC-IV": fmt_est(auc_d - auc_b, 3),
                "DeLong P": fmt_p(p_del),
            }
        )
        print("[csa] DeLong D-B", auc_d - auc_b, "p=", p_del, flush=True)
    if s7_rows:
        _save_table(
            pd.DataFrame(s7_rows),
            PUB / "Tables" / "Table S7. CSA-AKI DeLong pooling versus MIMIC-IV",
            title="Table S7. Paired DeLong comparison of pooling versus MIMIC-IV alone on CSA-AKI eICU stays",
            footnote=(
                "Same frozen ICU-AKI TPC weights as Table S6. Shared-stay paired DeLong test "
                "(Pooling − MIMIC-IV alone) on the eICU CSA-AKI subset."
            ),
        )

    # Figure S1 ROC
    fig, axes = plt.subplots(1, 2, figsize=(8.2, 3.6), sharey=True)
    panels = [
        (axes[0], "eicu", "eICU CSA-AKI (external subgroup)"),
        (axes[1], "mimic4", "MIMIC-IV CSA-AKI (test holdout)"),
    ]
    colors = {"MIMIC-IV only": "#c45c26", "Pooling": "#2f6f9f"}
    annot = []
    for ax, db, title in panels:
        ax.plot([0, 1], [0, 1], ls="--", color="#999999", lw=0.8)
        for arm in ("MIMIC-IV only", "Pooling"):
            st = stay_cache.get((arm, db))
            if st is None or st["y_mort"].nunique() < 2:
                continue
            y = st["y_mort"].to_numpy()
            p = st["pred_mort"].to_numpy()
            fpr, tpr, _ = roc_curve(y, p)
            auc = float(roc_auc_score(y, p))
            ax.plot(fpr, tpr, color=colors[arm], lw=1.4, label=f"{arm} AUROC {auc:.3f}")
            annot.append(f"{title} | {arm}: AUROC={auc:.3f}; N={len(st):,}; deaths={int(y.sum()):,}")
        ax.set_title(title, fontsize=10)
        ax.set_xlabel("1 − Specificity")
        ax.set_xlim(0, 1)
        ax.set_ylim(0, 1)
        ax.legend(loc="lower right", frameon=False)
    axes[0].set_ylabel("Sensitivity")
    fig.tight_layout()
    _write_fig(fig, "Figure S1. CSA-AKI ROC")
    _write_md(
        "Figure S1. CSA-AKI ROC",
        f"""# Figure S1. CSA-AKI ROC

## 图面说明
双面板 ROC：左为 eICU CSA-AKI（综合 ICU-AKI 外验 eICU 中的心脏围术期 DN=1 亚组）；右为 MIMIC-IV CSA-AKI 内部测试 holdout（已剔除与 ICU-AKI 训练集重叠 stay）。曲线比较冻权重 MIMIC-IV alone 与 Amsterdam+MIMIC 池化 TPC。对角虚线为无判别参考。

图上标注：
{chr(10).join('- ' + a for a in annot)}

## 分析上下文
暴露/模型：冻权重 ICU-AKI units-harmonized TPC（不在 CSA-AKI 上重训）。
结局：ICU 死亡（stay 级均值风险）。
数据库：eICU、MIMIC-IV（CSA-AKI 心脏围术期子集）。
Grouping：无分位；补充外验。
是否拼图：是（A/B 两面板）。
""",
    )

    # Drop any legacy CSA calibration fig from earlier drafts
    for legacy in (
        PUB / "Figures" / "pdf" / "Figure S2. CSA-AKI calibration.pdf",
        PUB / "Figures" / "image_information" / "Figure S2. CSA-AKI calibration.md",
    ):
        if legacy.exists():
            legacy.unlink()
            print("[csa] removed legacy", legacy, flush=True)

    _append_methods()
    print("[csa] done PUB=", PUB, flush=True)


def _append_methods():
    md = PUB / "Methods_statistical_analysis.md"
    if not md.exists():
        print("[csa] WARN no Methods md", flush=True)
        return
    text = md.read_text(encoding="utf-8")
    marker = "## CSA-AKI domain-shift validation"
    block = f"""{marker}

As a supplementary domain-shift check, the frozen units-harmonized ICU-AKI TPC weights (MIMIC-IV alone and AmsterdamUMC+MIMIC-IV pooling; no CSA-AKI retraining) were evaluated on cardiac surgery–associated AKI (CSA-AKI; perioperative DN=1) stays that already carried compatible BlendedICU tensors. The primary slice was the eICU CSA-AKI subset of the ICU-AKI eICU external set. A secondary MIMIC-IV CSA-AKI slice retained only stays in the ICU-AKI MIMIC internal test, excluding training-set overlap. SICdb and INSPIRE CSA-AKI extracts were not scored because their available feature channels are incompatible with the frozen ICU-AKI TPC feature inventory. Discrimination used stay-level AUROC (DeLong 95% CI) and AUPRC; RLoS used survivor MAPE (patient-level bootstrap, {N_BOOT:,} resamples). Pooling versus MIMIC-IV alone on shared CSA-AKI eICU stays used a paired DeLong test (Table S6–S7; Figure S1).
"""
    if marker in text:
        pre, _, rest = text.partition(marker)
        # drop old block until next ## or EOF
        nxt = rest.find("\n## ")
        if nxt >= 0:
            text = pre.rstrip() + "\n\n" + block + "\n" + rest[nxt + 1 :]
        else:
            text = pre.rstrip() + "\n\n" + block + "\n"
    else:
        # insert before Software if present
        if "\n## Software" in text:
            text = text.replace("\n## Software", "\n" + block + "\n## Software", 1)
        else:
            text = text.rstrip() + "\n\n" + block + "\n"
    md.write_text(text, encoding="utf-8")
    print("[csa] Methods updated", md, flush=True)


if __name__ == "__main__":
    main()
