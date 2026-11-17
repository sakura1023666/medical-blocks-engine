#!/usr/bin/env python3
"""Rebuild Fig2/S* from stay-level eICU+HiRID (Table3 Gen path); glucose unit audit/fix for S1."""
from __future__ import annotations
import importlib.util
import json
from pathlib import Path
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ci_mod = importlib.util.spec_from_file_location("eval_liver_paper_ci", "/tmp/eval_liver_paper_ci.py")
mod = importlib.util.module_from_spec(ci_mod)
ci_mod.loader.exec_module(mod)

INK = "#1f2937"
OUT_DIR = Path("/tmp/uln_pub_fix")
OUT_DIR.mkdir(parents=True, exist_ok=True)

COHORTS = {
    "all3": {
        "root": Path("/mnt/sda/BlendedICU/data/liver_dysfunction_uln_all3_42151996"),
        "fig": "Figure 2. Training size.pdf",
        "pin_expB": True,
    },
    "bili": {
        "root": Path("/mnt/sda/BlendedICU/data/liver_dysfunction_uln_bili_42151996"),
        "fig": "Figure S1. Training size (bilirubin ge1.3 only).pdf",
        "pin_expB": True,
    },
    "alt": {
        "root": Path("/mnt/sda/BlendedICU/data/liver_dysfunction_uln_alt_42151996"),
        "fig": "Figure S2. Training size (ALT ge41 only).pdf",
        "pin_expB": True,
    },
    "ast": {
        "root": Path("/mnt/sda/BlendedICU/data/liver_dysfunction_uln_ast_42151996"),
        "fig": "Figure S3. Training size (AST ge38 only).pdf",
        "pin_expB": True,
    },
}


def mcomposite(auc, mape, auc0, mape0):
    if not (np.isfinite(auc) and np.isfinite(mape) and np.isfinite(auc0) and np.isfinite(mape0)):
        return float("nan")
    if mape0 == 0 or (1 - auc0) == 0:
        return float("nan")
    return 0.5 * ((mape / mape0) + ((1 - auc) / (1 - auc0)))


def stay_metrics_from_preds(mort_p: Path, los_p: Path) -> dict:
    mort = pd.read_csv(mort_p)
    los = pd.read_csv(los_p) if los_p.exists() else None
    stay, _ = mod._stay_frame(mort, los)
    out = {}
    for db in ("eicu", "hirid"):
        sub = stay[stay["eval_on"] == db]
        if sub.empty:
            continue
        y = sub["y_mort"].to_numpy()
        p = sub["pred_mort"].to_numpy()
        auc = float(mod.roc_auc_score(y, p)) if np.unique(y).size >= 2 else float("nan")
        mape = float(sub["mape"].dropna().mean()) if "mape" in sub.columns and sub["mape"].notna().any() else float("nan")
        out[db] = {"auc": auc, "mape": mape, "n": len(sub)}
    return out


def series_for_cohort(root: Path, pin_expB: bool) -> pd.DataFrame:
    ud = root / "Output_paper_extras_physclip" / "liver_training_size_study"
    rows = []
    for mort_p in sorted(ud.glob("results/**/test_predictions_mort.csv")):
        pct = None
        for part in mort_p.parts:
            if part.startswith("mimic4_"):
                pct = int(part.split("_")[1])
                break
        if pct is None:
            continue
        los_p = mort_p.parent / "test_predictions_los.csv"
        met = stay_metrics_from_preds(mort_p, los_p)
        if "eicu" not in met or "hirid" not in met:
            continue
        # n_train from sibling metrics
        mcsv = mort_p.parent / "metrics_multitask.csv"
        n_train = int(pd.read_csv(mcsv)["n_train"].dropna().iloc[-1]) if mcsv.exists() else None
        rows.append({
            "pct": pct,
            "n_train": n_train,
            "auc": 0.5 * (met["eicu"]["auc"] + met["hirid"]["auc"]),
            "mape": 0.5 * (met["eicu"]["mape"] + met["hirid"]["mape"]),
            "auc_eicu": met["eicu"]["auc"],
            "auc_hirid": met["hirid"]["auc"],
            "mape_eicu": met["eicu"]["mape"],
            "mape_hirid": met["hirid"]["mape"],
        })
    tab = pd.DataFrame(rows).drop_duplicates("n_train").sort_values("n_train")
    if tab.empty:
        return tab
    # Pin 100% endpoint to Table3 Gen = mean eICU+HiRID from ci_main_four_arms expB
    ci_path = root / "Output_paper_extras_physclip" / "ci_main_four_arms" / "Table_CI_DeLong_bootstrap10k.csv"
    if pin_expB and ci_path.exists():
        ci = pd.read_csv(ci_path)
        b = ci[(ci["unit"].astype(str).str.contains("expB_mimic")) & (ci["eval_on"].isin(["eicu", "hirid"]))]
        if len(b) >= 2:
            auc = float(b["auroc_stay"].mean())
            mape = float(b["mape_stay_mean"].mean())
            tab.loc[tab["pct"] == 100, "auc"] = auc
            tab.loc[tab["pct"] == 100, "mape"] = mape
            tab.loc[tab["pct"] == 100, "pinned_table3_gen"] = True
    tab["pinned_table3_gen"] = tab.get("pinned_table3_gen", False)
    tab["pinned_table3_gen"] = tab["pinned_table3_gen"].fillna(False)
    base_mape = float(tab["mape"].iloc[-1])
    base_auc = float(tab["auc"].iloc[-1])
    tab["Mcomposite"] = [mcomposite(a, m, base_auc, base_mape) for a, m in zip(tab["auc"], tab["mape"])]
    return tab


def draw_fig2(tab: pd.DataFrame, out_pdf: Path, title: str = ""):
    c_comp, c_rlos, c_mort = "#6b7280", "#3b82f6", "#f59a2f"
    fig, ax = plt.subplots(figsize=(8.2, 4.8))
    fig.patch.set_facecolor("white")
    ax.set_facecolor("#eceff3")
    ax.yaxis.grid(False)
    ax.xaxis.grid(True, linestyle="-", linewidth=0.7, color="#d5dae2", zorder=0)
    ax.set_axisbelow(True)
    ax.plot(tab["n_train"], tab["Mcomposite"], "x", ms=7.5, mew=1.35, color=c_comp, zorder=3)
    ax.set_ylabel("Composite metric (arbitrary unit)", color=c_comp, fontsize=10)
    ax.tick_params(axis="y", colors=c_comp, labelsize=9)
    ax.spines["left"].set_color(c_comp)
    ax.spines["top"].set_visible(False)
    ax.set_xlabel("Number of patients for training", color=INK, fontsize=10)
    ax.tick_params(axis="x", colors=INK, labelsize=9)
    ax.spines["bottom"].set_color("#9aa3af")
    ax_r1 = ax.twinx()
    ax_r1.plot(tab["n_train"], tab["mape"], "x", ms=7.5, mew=1.35, color=c_rlos, zorder=3)
    ax_r1.set_ylabel("Remaining length of stay (MAPE)", color=c_rlos, fontsize=10)
    ax_r1.tick_params(axis="y", colors=c_rlos, labelsize=9)
    ax_r1.spines["right"].set_color(c_rlos)
    ax_r2 = ax.twinx()
    ax_r2.spines["right"].set_position(("axes", 1.12))
    ax_r2.plot(tab["n_train"], tab["auc"], "x", ms=7.5, mew=1.35, color=c_mort, zorder=3)
    ax_r2.set_ylabel("Mortality (AUROC)", color=c_mort, fontsize=10)
    ax_r2.tick_params(axis="y", colors=c_mort, labelsize=9)
    ax_r2.spines["right"].set_color(c_mort)
    # legend-ish labels
    ax.text(0.02, 0.98, "Composite", color=c_comp, transform=ax.transAxes, va="top", fontsize=9)
    ax.text(0.02, 0.92, "RLoS", color=c_rlos, transform=ax.transAxes, va="top", fontsize=9)
    ax.text(0.02, 0.86, "Mortality", color=c_mort, transform=ax.transAxes, va="top", fontsize=9)
    if title:
        ax.set_title(title, fontsize=10, color=INK)
    fig.tight_layout()
    out_pdf.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_pdf, format="pdf", bbox_inches="tight")
    plt.close(fig)


def glucose_unit_fix_stats():
    """Compute corrected glucose Before/After medians for S1 (MIMIC mg/dL → mmol/L)."""
    import duckdb
    files = [
        "/mnt/sda/BlendedICU/data/blended_data/long_timeseries/mimic4.parquet",
        "/mnt/sda/BlendedICU/data/blended_data/long_timeseries/hirid.parquet",
        "/mnt/sda/BlendedICU/data/blended_data/long_timeseries/amsterdam.parquet",
    ] + [f"/mnt/sda/BlendedICU/data/blended_data/long_timeseries/eicu_part{i}.parquet" for i in range(8)]
    elig = "/mnt/sda/BlendedICU/data/liver_dysfunction_uln_all3_42151996/eligible_stays.parquet"
    sql = ",".join(repr(f) for f in files)
    c = duckdb.connect()
    df = c.execute(f"""
    WITH el AS (SELECT patient FROM read_parquet('{elig}')),
    g AS (
      SELECT CASE
        WHEN filename LIKE '%amsterdam%' THEN 'amsterdam'
        WHEN filename LIKE '%mimic4%' THEN 'mimic4'
        WHEN filename LIKE '%hirid%' THEN 'hirid'
        WHEN filename LIKE '%eicu%' THEN 'eicu'
      END AS db,
      patient, value AS raw
      FROM read_parquet([{sql}], filename=true)
      WHERE variable='blood_glucose' AND time>=0 AND value>0
        AND patient IN (SELECT patient FROM el)
    )
    SELECT db, raw,
           CASE WHEN db='mimic4' AND raw>30 THEN raw/18.0 ELSE raw END AS mmol
    FROM g
    """).fetchdf()
    mmol = df["mmol"].to_numpy()
    lo, hi = 2.8, 12.4
    clipped = np.clip(mmol, lo, hi)
    def iq(x):
        q25,q50,q75=np.percentile(x,[25,50,75])
        def f(v):
            s=f"{v:.3f}".rstrip("0").rstrip(".")
            return s
        return f"{f(q50)} [{f(q25)} - {f(q75)}]"
    out = {
        "n": int(len(mmol)),
        "before": iq(mmol),
        "after": iq(clipped),
        "frac_mimic_converted": float(((df.db=="mimic4") & (df.raw>30)).mean()),
        "by_db_med_raw": df.groupby("db")["raw"].median().to_dict(),
        "by_db_med_mmol": df.groupby("db")["mmol"].median().to_dict(),
    }
    return out


def main():
    summary = {}
    for key, meta in COHORTS.items():
        root = meta["root"]
        if not (root / "Output_paper_extras_physclip" / "liver_training_size_study").exists():
            print("SKIP missing training_size", key)
            continue
        tab = series_for_cohort(root, meta["pin_expB"])
        if tab.empty:
            print("SKIP empty", key)
            continue
        csv_p = OUT_DIR / f"fig2_staylevel_{key}.csv"
        tab.to_csv(csv_p, index=False)
        pdf_p = OUT_DIR / meta["fig"]
        draw_fig2(tab, pdf_p)
        end = tab.iloc[-1]
        summary[key] = {
            "n_train": int(end["n_train"]),
            "auc": float(end["auc"]),
            "mape": float(end["mape"]),
            "Mcomposite": float(end["Mcomposite"]),
            "pinned": bool(end.get("pinned_table3_gen", False)),
            "pdf": str(pdf_p),
            "csv": str(csv_p),
            "points": [
                {"n": int(r.n_train), "auc": round(float(r.auc), 3), "mape": round(float(r.mape), 1), "Mcomp": round(float(r.Mcomposite), 3)}
                for r in tab.itertuples()
            ],
        }
        print("OK", key, summary[key]["n_train"], summary[key]["auc"], summary[key]["mape"], "pinned", summary[key]["pinned"])
    glu = glucose_unit_fix_stats()
    summary["glucose"] = glu
    print("GLUCOSE", glu)
    (OUT_DIR / "rebuild_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print("WROTE", OUT_DIR)


if __name__ == "__main__":
    main()
