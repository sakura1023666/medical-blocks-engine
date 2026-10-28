#!/usr/bin/env python3
"""Publication tables and figures for the database-pooling block.

Called by Blocks/78 dbpool_pub_tables. Reads each unit's metrics_multitask.csv.
MAPE uses the BlendedLoS definition (absolute error over true LoS clipped at 4 hours).
Tables are xlsx only. Point estimates; not the paper's DeLong or 10,000 bootstrap.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import pyarrow.parquet as pq
from sklearn.metrics import average_precision_score, roc_auc_score

PAPER = {
    "equal_n": 19573,
    "fig2_range": "1,000 to 55,000",
    "table2_mape_internal": {
        "AmsterdamUMC": 80.3,
        "eICU": 87.4,
        "HiRID": 83.2,
        "MIMIC-IV": 87.2,
    },
    "table2_mape_external": {
        "AmsterdamUMC": 121.9,
        "eICU": 100.1,
        "HiRID": 83.0,
        "MIMIC-IV": 109.5,
    },
    "table3_pool_better_amsterdam": "pooling Mcomposite 1.07 and transfer 1.08 vs Amsterdam solo 1.41",
    "table3_pool_mape": "Amsterdam specialization MAPE pooling 84.49 vs transfer 89.24",
    "table3_generalization": "pooling Mcomposite 1.15 best on unseen eICU+HiRID",
    "table3_mimic_solo_better": "MIMIC specialization: solo Mcomposite 0.89 better than pooling 0.97",
}

DB_LABEL = {
    "amsterdam": "AmsterdamUMC",
    "eicu": "eICU",
    "hirid": "HiRID",
    "mimic4": "MIMIC-IV",
}


def _latest_metric_files(unit_dir: Path) -> list[Path]:
    files = list(unit_dir.rglob("metrics_multitask.csv"))
    # keep the newest timestamp folder when several runs share a parent
    best = {}
    for f in files:
        parent = f.parent
        key = str(parent.parent)
        if key not in best or parent.name > best[key].parent.name:
            best[key] = f
    return list(best.values())


def _test_metrics(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path)
    df = df[df["set"] == "test"].copy()
    if df.empty:
        return df
    last = df["epoch"].max()
    df = df[df["epoch"] == last]
    df["run_dir"] = str(path.parent)
    return df


def _mape(y, p):
    y = np.asarray(y, dtype=float)
    p = np.asarray(p, dtype=float)
    denom = np.clip(y, 4 / 24, None)
    return float(np.mean(np.abs(y - p) / denom) * 100)


def _safe_auc(y, p):
    y = np.asarray(y, dtype=float)
    if len(np.unique(y)) < 2:
        return float("nan")
    return float(roc_auc_score(y, p))


def _safe_auprc(y, p):
    y = np.asarray(y, dtype=float)
    if len(np.unique(y)) < 2:
        return float("nan")
    return float(average_precision_score(y, p))


def _boot_ci(values_fn, n=200, seed=42):
    rng = np.random.default_rng(seed)
    stats = []
    for _ in range(n):
        stats.append(values_fn(rng))
    arr = np.asarray(stats, dtype=float)
    arr = arr[np.isfinite(arr)]
    if len(arr) < 20:
        return float("nan"), float("nan")
    return float(np.percentile(arr, 2.5)), float(np.percentile(arr, 97.5))


def _load_preds(run_dir: Path):
    mort_p = run_dir / "test_predictions_mort.csv"
    los_p = run_dir / "test_predictions_los.csv"
    mort = los = None
    if mort_p.exists() and mort_p.stat().st_size < 80_000_000:
        mort = pd.read_csv(mort_p)
    if los_p.exists() and los_p.stat().st_size < 80_000_000:
        los = pd.read_csv(los_p)
    return mort, los


def _fmt(x, nd=2):
    if x is None or not np.isfinite(x):
        return ""
    return f"{x:.{nd}f}"


def _fmt_ci(x, lo, hi, nd=2):
    if not np.isfinite(x):
        return ""
    if not (np.isfinite(lo) and np.isfinite(hi)):
        return _fmt(x, nd)
    return f"{x:.{nd}f} ({lo:.{nd}f} to {hi:.{nd}f})"


def build_table1(blended: Path) -> pd.DataFrame:
    """One row per database: train + val + test stays of that database."""
    root = blended / "extraction"
    rows = []
    for key, label in DB_LABEL.items():
        frames = []
        base = root / f"train_on_{key}"
        for split in ("train", "val", "test"):
            path = base / split / "labels.parquet"
            if not path.exists():
                continue
            df = pd.read_parquet(path)
            if "source_dataset" in df.columns:
                df = df[df["source_dataset"].astype(str) == key]
            frames.append(df)
        if not frames:
            continue
        g = pd.concat(frames)
        g = g[~g.index.duplicated(keep="first")]
        rec = {"Database": label, "N stays": int(len(g))}
        if "age" in g.columns:
            rec["Age, median"] = round(float(pd.to_numeric(g["age"], errors="coerce").median()), 1)
        if "sex" in g.columns:
            s = pd.to_numeric(g["sex"], errors="coerce")
            rec["Sex code 1, proportion"] = round(float((s == 1).mean()), 3) if s.notna().any() else float("nan")
        if "lengthofstay" in g.columns:
            rec["LOS days, median"] = round(float(pd.to_numeric(g["lengthofstay"], errors="coerce").median()), 2)
        if "mortality" in g.columns:
            rec["ICU mortality"] = round(float(pd.to_numeric(g["mortality"], errors="coerce").mean()), 3)
        rows.append(rec)
    return pd.DataFrame(rows)


def _collect(work: Path) -> dict[str, pd.DataFrame]:
    out = {}
    for unit in work.iterdir():
        if not unit.is_dir():
            continue
        frames = []
        for f in _latest_metric_files(unit):
            t = _test_metrics(f)
            if not t.empty:
                frames.append(t)
        if frames:
            out[unit.name] = pd.concat(frames, ignore_index=True)
    return out


def _save_table(df: pd.DataFrame, path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    df.to_excel(path.parent / f"{path.name}.xlsx", index=False)


def _write_fig(fig, out_root: Path, name: str):
    for kind, ext in (("pdf", "pdf"), ("png", "png"), ("tiff", "tiff")):
        d = out_root / "Figures" / kind
        d.mkdir(parents=True, exist_ok=True)
        target = d / f"{name}.{ext}"
        if ext == "pdf":
            fig.savefig(target, bbox_inches="tight")
        else:
            fig.savefig(target, dpi=600, bbox_inches="tight")
    plt.close(fig)


def _flow_box(ax, x, y, w, h, title, subtitle, face):
    from matplotlib.patches import FancyBboxPatch
    ax.add_patch(
        FancyBboxPatch(
            (x, y), w, h,
            boxstyle="round,pad=0.012,rounding_size=0.08",
            facecolor=face, edgecolor="#243040", linewidth=0.7,
            mutation_aspect=0.6,
        )
    )
    ax.text(x + w / 2, y + h * 0.62, title, ha="center", va="center", fontsize=8.2, color="#1b2430")
    if subtitle:
        ax.text(x + w / 2, y + h * 0.28, subtitle, ha="center", va="center", fontsize=6.6, color="#3d4a5c")


def _arrow(ax, x, y0, y1):
    ax.annotate(
        "", xy=(x, y1), xytext=(x, y0),
        arrowprops=dict(arrowstyle="-|>", color="#243040", lw=0.8, mutation_scale=8),
    )


def _chip(ax, x, y, w, h, text, face):
    from matplotlib.patches import FancyBboxPatch
    ax.add_patch(
        FancyBboxPatch(
            (x, y), w, h,
            boxstyle="round,pad=0.01,rounding_size=0.06",
            facecolor=face, edgecolor="#243040", linewidth=0.6,
        )
    )
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center", fontsize=7, color="#1b2430")


def make_fig1(out: Path):
    """Seven-step pipeline plus the four training strategies from Allyn 2026 Fig. 1."""
    fig, axes = plt.subplots(1, 2, figsize=(11.4, 6.4), gridspec_kw={"width_ratios": [1.05, 1.15]})
    ink = "#1b2430"
    db = {"AmsterdamUMC": "#d7e6f5", "MIMIC-IV": "#f6dfd4", "eICU": "#dceee4", "HiRID": "#efe6c9"}

    ax = axes[0]
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis("off")
    ax.text(0.15, 9.65, "A", fontsize=13, fontweight="bold", color=ink, ha="left", va="center")
    ax.text(0.7, 9.65, "Study pipeline", fontsize=11, color=ink, ha="left", va="center")
    steps = [
        ("1  Four ICU databases", "MIMIC-IV, eICU, HiRID, AmsterdamUMC", "#d7e6f5"),
        ("2  Preprocess", "Clip, forward-fill, missingness mask, scale", "#dceee4"),
        ("3  Patient-level split", "Train 70%   validation 15%   test 15%", "#efe6c9"),
        ("4  TPC model", "Mortality and remaining stay, trained together", "#f6dfd4"),
        ("5  Internal test", "Same database, held-out patients", "#e6e4f4"),
        ("6  External test", "Four training strategies, panel B", "#e6e4f4"),
        ("7  Hourly outputs", "Death risk, and remaining stay if alive", "#f7f3ea"),
    ]
    box_w, box_h = 8.6, 0.95
    x0 = 0.7
    top = 8.85
    gap = 0.22
    for i, (title, sub, face) in enumerate(steps):
        y = top - i * (box_h + gap)
        _flow_box(ax, x0, y, box_w, box_h, title, sub, face)
        if i < len(steps) - 1:
            _arrow(ax, x0 + box_w / 2, y, y - gap + 0.02)

    ax = axes[1]
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.axis("off")
    ax.text(0.15, 9.65, "B", fontsize=13, fontweight="bold", color=ink, ha="left", va="center")
    ax.text(0.7, 9.65, "Four training strategies", fontsize=11, color=ink, ha="left", va="center")

    rows = [
        (7.35, "1", "AmsterdamUMC alone", [("AmsterdamUMC", 1.15, 2.15)], "Evaluated on AmsterdamUMC", "160 patients"),
        (5.35, "2", "MIMIC-IV alone", [("MIMIC-IV", 1.15, 1.7)], "Evaluated on MIMIC-IV", "472 patients"),
        (3.35, "3", "Transfer: MIMIC-IV, then AmsterdamUMC", [("MIMIC-IV", 1.15, 1.7), ("AmsterdamUMC", 3.55, 2.15)], "Evaluated only after fine-tuning", "632 patients"),
        (1.05, "4", "Pooling in one training run", [("AmsterdamUMC", 1.15, 2.15), ("MIMIC-IV", 3.5, 1.7)], "Also tested on eICU and HiRID", "635 patients"),
    ]
    for y, num, name, chips, outcome, nlab in rows:
        ax.add_patch(plt.Circle((0.48, y + 0.78), 0.26, facecolor="#243040", edgecolor="none"))
        ax.text(0.48, y + 0.78, num, ha="center", va="center", fontsize=8, color="white")
        ax.text(1.05, y + 1.28, name, ha="left", va="center", fontsize=8.5, color=ink)
        for src, cx, cw in chips:
            _chip(ax, cx, y + 0.48, cw, 0.4, src, db[src])
        if num == "3":
            ax.annotate(
                "", xy=(3.48, y + 0.68), xytext=(2.95, y + 0.68),
                arrowprops=dict(arrowstyle="-|>", color="#243040", lw=0.7, mutation_scale=7),
            )
        ax.text(1.05, y + 0.16, outcome, ha="left", va="center", fontsize=7, color="#3d4a5c")
        ax.text(9.7, y + 0.78, nlab, ha="right", va="center", fontsize=7.2, color="#3d4a5c")

    fig.tight_layout(pad=0.4)
    _write_fig(fig, out, "Figure 1. Study pipeline")


def make_fig2(size_df: pd.DataFrame, out: Path) -> pd.DataFrame:
    """size_df: rows with n_train, task, source or total, mape, auc."""
    los = size_df[size_df["task"] == "LoS"].groupby("n_train", as_index=False)["mape"].mean()
    mort = size_df[size_df["task"] == "mortality"].groupby("n_train", as_index=False)["auc"].mean()
    tab = los.merge(mort, on="n_train", how="outer").sort_values("n_train")
    if tab.empty:
        return tab
    base_mape = float(tab["mape"].iloc[-1])
    base_auc = float(tab["auc"].iloc[-1])
    tab["Mcomposite"] = 0.5 * (
        (tab["mape"] / base_mape) + ((1 - tab["auc"]) / (1 - base_auc))
    )
    fig, ax = plt.subplots(figsize=(7.2, 4.4))
    ax.plot(tab["n_train"], tab["mape"], "o", color="tab:blue", label="MAPE")
    ax.set_xlabel("Patients used for training")
    ax.set_ylabel("MAPE")
    ax2 = ax.twinx()
    ax2.plot(tab["n_train"], tab["auc"], "s", color="tab:orange", label="AUROC")
    ax2.set_ylabel("AUROC")
    ax.set_title("Training size and test performance")
    # markers only: no smoothed curve
    h1, l1 = ax.get_legend_handles_labels()
    h2, l2 = ax2.get_legend_handles_labels()
    ax.legend(h1 + h2, l1 + l2, frameon=False, loc="best")
    fig.tight_layout()
    _write_fig(fig, out, "Figure 2. Training size")
    return tab


def write_md(out: Path, name: str, body: str):
    d = out / "Figures" / "image_information"
    d.mkdir(parents=True, exist_ok=True)
    (d / f"{name}.md").write_text(body, encoding="utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--work-root", required=True)
    ap.add_argument("--blended-out", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    work = Path(args.work_root)
    out = Path(args.out)
    (out / "Tables").mkdir(parents=True, exist_ok=True)
    (out / "Figures" / "pdf").mkdir(parents=True, exist_ok=True)

    t1 = build_table1(Path(args.blended_out))
    if not t1.empty:
        _save_table(t1, out / "Tables" / "Table 1. Cohort characteristics")

    collected = _collect(work)
    rows_metrics = []
    for unit, df in collected.items():
        df = df.copy()
        df.insert(0, "unit", unit)
        rows_metrics.append(df)
    if rows_metrics:
        allm = pd.concat(rows_metrics, ignore_index=True)
        allm.to_csv(out / "Tables" / "_internal_test_metrics.csv", index=False)
    else:
        allm = pd.DataFrame()

    make_fig1(out)
    size = collected.get("training_size_study", pd.DataFrame())
    fig2_tab = make_fig2(size, out) if not size.empty else pd.DataFrame()
    if not fig2_tab.empty:
        _save_table(fig2_tab, out / "Tables" / "Figure 2 data")

    # Table 2 from dataset_benchmark test rows
    ds = collected.get("dataset_benchmark", pd.DataFrame())
    t2_rows = []
    if not ds.empty:
        for ntr, g in ds.groupby("n_train"):
            # one training database is the one with a LoS row that we treat as internal
            # heuristic: the trained DB is recorded only as the source that matches the run folder name
            pass
        # Use run_dir parent names
        for run_dir, g in ds.groupby("run_dir"):
            train_db = None
            # folder .../amsterdam_100/ or similar
            parts = Path(run_dir).parts
            for p in parts:
                for key in DB_LABEL:
                    if p.startswith(key):
                        train_db = key
            if train_db is None:
                continue
            for task, metric, label in [
                ("LoS", "mape", "MAPE"),
                ("mortality", "auc", "AUROC"),
            ]:
                sub = g[g["task"] == task]
                internal = sub[sub["source_dataset"] == train_db]
                external = sub[sub["source_dataset"] != train_db]
                if internal.empty or external.empty:
                    continue
                iv = float(internal[metric].mean())
                ev = float(external[metric].mean())
                if metric == "mape":
                    var = (ev - iv) / iv * 100 if iv else float("nan")
                else:
                    var = (ev - iv) / iv * 100 if iv else float("nan")
                t2_rows.append(
                    {
                        "Training database": DB_LABEL.get(train_db, train_db),
                        "Task": label,
                        "Internal": round(iv, 3),
                        "External mean of other sites": round(ev, 3),
                        "Relative change percent": round(var, 1),
                        "N train": int(ntr) if False else int(internal["n_train"].iloc[0]),
                    }
                )
    t2 = pd.DataFrame(t2_rows)
    if not t2.empty:
        _save_table(t2, out / "Tables" / "Table 2. Internal and external")

    # Table 3 from the four strategy units, Amsterdam and MIMIC rows + unseen
    strategy = {
        "expA_amumc_solo": "Amsterdam only",
        "expB_mimic_solo": "MIMIC-IV only",
        "expC_mimic2amumc_transfer": "Transfer",
        "expD_pooled_mimic_amumc": "Pooling",
    }
    # baseline = dataset_benchmark internal
    baseline = {}
    if not ds.empty:
        for _, r in ds.iterrows():
            if r["task"] not in ("LoS", "mortality"):
                continue
            # internal if this run was trained on that source: detect later
            baseline.setdefault(r["source_dataset"], {})[r["task"]] = float(
                r["mape"] if r["task"] == "LoS" else r["auc"]
            )
    # The loop above overwrites with every source in every run. Rebuild properly.
    baseline = {}
    if not ds.empty:
        for run_dir, g in ds.groupby("run_dir"):
            train_db = None
            for p in Path(run_dir).parts:
                for key in DB_LABEL:
                    if p.startswith(key):
                        train_db = key
            if train_db is None:
                continue
            sub = g[g["source_dataset"] == train_db]
            for _, r in sub.iterrows():
                baseline.setdefault(train_db, {})[r["task"]] = float(
                    r["mape"] if r["task"] == "LoS" else r["auc"]
                )

    def composite(mape, auc, b_mape, b_auc):
        if not all(np.isfinite(v) for v in [mape, auc, b_mape, b_auc]):
            return float("nan")
        if b_mape == 0 or b_auc == 1:
            return float("nan")
        return 0.5 * ((mape / b_mape) + ((1 - auc) / (1 - b_auc)))

    t3_rows = []
    for unit, label in strategy.items():
        g = collected.get(unit, pd.DataFrame())
        if g.empty:
            continue
        # transfer unit has two runs; keep the fine-tune (pretrained True / last)
        if "pretrained" in g.columns and unit.startswith("expC"):
            finetune = g["pretrained"].astype(str).str.lower().isin(["all", "true", "1"])
            if finetune.any():
                g = g[finetune]
        n_train = int(g["n_train"].max())

        def grab(db, task, col):
            sub = g[(g["source_dataset"] == db) & (g["task"] == task)]
            if sub.empty:
                return float("nan")
            return float(sub[col].mean())

        evals = [("amsterdam", "Specialization AmsterdamUMC")]
        if unit != "expC_mimic2amumc_transfer":
            evals.append(("mimic4", "Specialization MIMIC-IV"))
        for db, title in evals:
            mape = grab(db, "LoS", "mape")
            auc = grab(db, "mortality", "auc")
            b = baseline.get(db, {})
            t3_rows.append(
                {
                    "Evaluation": title,
                    "Training": label,
                    "N train": n_train,
                    "AUROC": round(auc, 3) if np.isfinite(auc) else "",
                    "MAPE": round(mape, 2) if np.isfinite(mape) else "",
                    "Mcomposite": round(composite(mape, auc, b.get("LoS", np.nan), b.get("mortality", np.nan)), 3)
                    if np.isfinite(mape)
                    else "",
                }
            )
        # generalization: eicu + hirid mean
        mape_g = np.nanmean([grab("eicu", "LoS", "mape"), grab("hirid", "LoS", "mape")])
        auc_g = np.nanmean([grab("eicu", "mortality", "auc"), grab("hirid", "mortality", "auc")])
        # baseline for generalization: mean of eicu and hirid internal
        b_mape = np.nanmean([baseline.get("eicu", {}).get("LoS", np.nan), baseline.get("hirid", {}).get("LoS", np.nan)])
        b_auc = np.nanmean([baseline.get("eicu", {}).get("mortality", np.nan), baseline.get("hirid", {}).get("mortality", np.nan)])
        if unit != "expC_mimic2amumc_transfer":
            t3_rows.append(
                {
                    "Evaluation": "Generalization eICU and HiRID",
                    "Training": label,
                    "N train": n_train,
                    "AUROC": round(float(auc_g), 3) if np.isfinite(auc_g) else "",
                    "MAPE": round(float(mape_g), 2) if np.isfinite(mape_g) else "",
                    "Mcomposite": round(composite(mape_g, auc_g, b_mape, b_auc), 3) if np.isfinite(mape_g) else "",
                }
            )
    t3 = pd.DataFrame(t3_rows)
    if not t3.empty:
        _save_table(t3, out / "Tables" / "Table 3. Four training strategies")

    # Table S2 model benchmark
    mb = collected.get("model_benchmark", pd.DataFrame())
    if not mb.empty:
        s2 = (
            mb.groupby(["task", "source_dataset"], as_index=False)
            .agg(MAPE=("mape", "mean"), AUROC=("auc", "mean"), N=("n_train", "max"))
        )
        # model name is not a column; recover from run_dir
        models = []
        for _, r in mb.iterrows():
            model = "TPC"
            for part in Path(r["run_dir"]).parts:
                if part.lower() in ("lstm", "transformer", "tpc"):
                    model = part.upper() if part.lower() != "tpc" else "TPC"
            models.append(model)
        mb = mb.copy()
        mb["Model"] = models
        s2 = (
            mb.groupby(["Model", "task", "source_dataset"], as_index=False)
            .agg(value_mape=("mape", "mean"), value_auc=("auc", "mean"), N_train=("n_train", "max"))
        )
        s2["Database"] = s2["source_dataset"].map(lambda x: DB_LABEL.get(x, x))
        s2["Metric"] = np.where(s2["task"] == "LoS", s2["value_mape"], s2["value_auc"])
        s2["Task"] = s2["task"].map({"LoS": "RLoS MAPE", "mortality": "Mortality AUROC"}).fillna(s2["task"])
        s2 = s2[["Model", "Database", "Task", "Metric", "N_train"]]
        _save_table(s2, out / "Tables" / "Table S2. LSTM Transformer TPC")

    # Table S1 quantiles
    qfiles = list(work.rglob("train_q5q95.json"))
    if qfiles:
        payload = json.loads(sorted(qfiles)[-1].read_text())
        rows = []
        for c, lo in payload.get("q5", {}).items():
            hi = payload.get("q95", {}).get(c)
            rows.append({"Variable": c.replace("_", " "), "Train q5": lo, "Train q95": hi, "Clip": "-4 to 4"})
        for c, lo in payload.get("flat_q5", {}).items():
            hi = payload.get("flat_q95", {}).get(c)
            rows.append({"Variable": c, "Train q5": lo, "Train q95": hi, "Clip": "-4 to 4"})
        _save_table(pd.DataFrame(rows), out / "Tables" / "Table S1. Scaling")

    # Table 4 comparison scaffold with paper numbers from the chunk and our summary
    t4 = pd.DataFrame(
        [
            {
                "Study": "Allyn 2026 Critical Care",
                "Equal stays per database": PAPER["equal_n"],
                "Model": "TPC, LSTM, Transformer",
                "Epoch ceiling": 200,
                "Noted pattern": "Internal MAPE often worse externally; pooling helps Amsterdam specialization and unseen-site generalization; MIMIC solo beats pooling on MIMIC",
            },
            {
                "Study": "This reduced run",
                "Equal stays per database": "see difference note",
                "Model": "Same three architectures",
                "Epoch ceiling": "30 for the four strategies and per-database runs; 12 for model comparison and training size",
                "Noted pattern": "See difference note after the tables",
            },
        ]
    )
    _save_table(t4, out / "Tables" / "Table 4. Comparison with the paper")

    note = out / "与原文的差别.md"
    note.write_text(_difference_note(t1, t2, t3, fig2_tab), encoding="utf-8")

    write_md(
        out,
        "Figure 1. Study pipeline",
        "# Figure 1\n\n## 图面说明\n\n左图是七步流程：四库协调、小时序列与两个结局、患者级划分、训练集分位数缩放、前向填充和缺失掩码、时间点卷积、验证集早停。右图是四种训练：只训 Amsterdam、只训 MIMIC-IV、先 MIMIC-IV 再微调 Amsterdam、两库合并训练。\n\n## 分析上下文\n\n结局是 ICU 死亡和剩余住院时间。这张图是方法示意图，上面没有性能数字。样本量见差异说明。\n",
    )
    n_txt = ""
    if not fig2_tab.empty:
        n_txt = "、".join(str(int(x)) for x in fig2_tab["n_train"])
        mape_txt = "、".join(f"{v:.1f}" for v in fig2_tab["mape"])
        auc_txt = "、".join(f"{v:.3f}" for v in fig2_tab["auc"])
    else:
        mape_txt = auc_txt = "未收获"
    write_md(
        out,
        "Figure 2. Training size",
        "# Figure 2\n\n## 图面说明\n\n横轴是本次实际用于训练的人数，点是各规模在测试集上的 MAPE 和 AUROC，没有做平滑。\n\n图上标注：训练人数 "
        + (n_txt or "未收获")
        + "；MAPE "
        + mape_txt
        + "；AUROC "
        + auc_txt
        + "。\n\n## 分析上下文\n\n模型是时间点卷积，结局是 ICU 死亡和剩余住院时间。原文横轴大约从 1,000 到 55,000，并描述 15,000 以后平台。本次人数被压到每个库最多 640 次住院，画不出那个平台。\n",
    )
    print(f"wrote {out}")


def _difference_note(t1, t2, t3, fig2) -> str:
    lines = [
        "# 和原文的差别",
        "",
        "原文是 Allyn 等，Critical Care 2026，BlendedLoS。下面只写已经核对过的差异。性能数字来自本次缩小样本的测试集，不是原文表里的数字。",
        "",
        "## 人数",
        "",
        "- 原文 Table 1 每个库等量抽样 19,573 次住院。我们按 Amsterdam 小时文件对齐后，每个库大约 21,311 次，多出来是因为提取队列和原文不是同一批住院。",
        "- 原文四种策略的训练人数：只训 Amsterdam 3,574；只训 MIMIC-IV 10,915；迁移和合并都是 14,489。",
        "- 本次每个库在训练、验证、测试文件夹里各自最多抽 640 次住院（随机种子 974），再套原文的 25% 或 75%。所以策略 A 的训练人数大约是 160，策略 B 大约 480，合并大约 640。验证集用了同样的上限，因此验证人数相对训练集比原文的 15% 更大。",
        "- 每个 epoch 最多 24 个 batch（每批 32 人）。训练规模实验的最大档如果超过这个上限，会被截断。",
        "- Figure 2 原文从大约 1,000 画到 55,000，并写少于 5,000 变差、15,000 以后平台。我们的横轴只有几百人，平台那一段复现不了。",
        "",
        "## 模型",
        "",
        "- 结构相同：主分析是时间点卷积（TPC）；补充比较还有 LSTM 和 Transformer。损失仍是死亡的二元交叉熵加上 20 倍的剩余住院时间 MSLE。",
        "- 标准化相同：只用训练集的第 5 和第 95 百分位，缩放到大约 -1 到 1，再截断到 -4 到 4，然后前向填充，并保留填充前的观测掩码。",
        "- 划分相同：患者级 70/15/15，种子 974。",
        "- 早停仍是验证集上连续 5 轮不提升就停。原文最多 200 轮。四种策略和按库比较的上限是 30 轮；模型比较和训练规模实验的上限是 12 轮。",
        "- 测试比例本次用满缩小后的测试文件夹。原文公开代码默认是测试集的 100%，我们之前的全量任务用过 50%。",
        "- 置信区间不是原文的 DeLong，也不是 10,000 次 bootstrap。表里如果只有一个数，就是测试集的点估计。",
        "",
        "## 数据和软件版本",
        "",
        "- 协调步骤用的是服务器上的 BlendedICU 0.5.2 提取结果，配置开关与作者引用的 0.3.2 一致（住院时长上下限、药物暴露 2 小时、前向填充）。没有为了版本号重抽 0.3.2。",
        "- 磁盘上的 MIMIC 是 3.1，原文路径写的是 2.2。",
        "- 呼吸机变量这版配置没有打开（use resp 关闭）。原文主模型用了呼吸相关变量。",
        "",
        "## 原文里比较稳的趋势，用来对照本次",
        "",
        "- Table 2：内部验证往往比外部乐观。剩余住院 MAPE 在 Amsterdam 外部升高最多（原文 +51.8%），HiRID 几乎不变（-0.3%）。AUROC 在 Amsterdam 外部略升，在 MIMIC 外部下降最多（-13.8%）。AUPRC 外部都下降，MIMIC 最陡（-40.8%）。",
        "- Table 3：在 Amsterdam 上，合并和迁移都好于只训 Amsterdam（Mcomposite 大约 1.07 和 1.08，对 1.41）。合并和迁移的 AUROC 接近，合并的 MAPE 更好（84.49 对 89.24）。对没见过的 eICU 和 HiRID，合并最好（Mcomposite 1.15）。在 MIMIC 上，只训 MIMIC（0.89）好于合并（0.97）。",
        "",
        "## 本次算出来的数",
        "",
    ]
    if t2 is not None and not t2.empty:
        lines.append("Table 2（内部对外部，外部是其他库测试指标的平均）：")
        lines.append("")
        lines.append(t2.to_csv(index=False))
    else:
        lines.append("Table 2 还没有测试结果。")
    if t3 is not None and not t3.empty:
        lines.append("")
        lines.append("Table 3（Mcomposite 以各库单独训练的内部测试为基准，低于 1 表示好于该基准）：")
        lines.append("")
        lines.append(t3.to_csv(index=False))
    else:
        lines.append("Table 3 还没有四种策略的测试结果。")
    if fig2 is not None and not fig2.empty:
        lines.append("")
        lines.append("Figure 2 各训练人数上的 MAPE、AUROC、Mcomposite（基准取最大训练人数那一档）：")
        lines.append("")
        lines.append(fig2.to_csv(index=False))
    lines.append("")
    lines.append("Table 1 是每个库单独划分后的训练、验证、测试住院合在一起，用来和原文 19,573 人对照。模型实际每次最多从中抽 640 次住院。")
    lines.append("")
    return "\n".join(lines)


if __name__ == "__main__":
    main()
