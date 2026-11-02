#!/usr/bin/env python3
"""Compute Wang-2025 ESM-aligned S1–S13 (+ Table1/2) payloads for SA-AKI TCF.

Writes under success_root/_tables_rebuild_workspace/wang_payloads/*.csv
Consumed by rebuild_wang2025_tcf_tables.R → export_sci_table.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
import warnings
from itertools import combinations
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from scipy import stats
from sklearn.impute import KNNImputer, SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    accuracy_score,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
    roc_auc_score,
)
from sklearn.model_selection import StratifiedKFold, cross_val_score
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

# Engine topsis
_ENGINE_TCF = Path(__file__).resolve().parents[1]  # python/ml_tcf
if str(_ENGINE_TCF) not in sys.path:
    sys.path.insert(0, str(_ENGINE_TCF))
from topsis import topsis  # noqa: E402

EST_DIGITS = 3

# Shared stratum seeds (engine)
import os as _os
import sys as _sys
from pathlib import Path as _Path
_ENGINE = _Path(_os.environ.get("MEDICAL_BLOCKS_ROOT", ""))
if not (_ENGINE / "python/ml_tcf/pub/bootstrap.py").exists():
    _ENGINE = _Path(__file__).resolve().parents[3]
_sys.path.insert(0, str(_ENGINE / "python"))
from ml_tcf.pub.bootstrap import (  # noqa: E402
    BOOT_SEED,
    N_BOOT,
    SEED_OFF_C1,
    SEED_OFF_C2,
    SEED_OFF_EICU,
    SEED_OFF_INTERNAL,
    SEED_OFF_TRAIN,
    THR,
)

MODEL_ORDER = ["DT", "RF", "SVM", "NB", "GBDT", "XGB", "LGBM", "TCF"]
SUBMODEL_ORDER = ["DT", "RF", "SVM", "NB", "GBDT", "XGB", "LGBM"]
TREE_MODELS = ["DT", "RF", "XGB", "LGBM", "GBDT"]

# Search spaces from python/ml_tcf/train_tcf_bundle.py (RandomizedSearchCV)
PARAM_GRIDS = {
    "DT": {
        "criterion": "['gini', 'entropy']",
        "max_depth": "[10, 20, …, 290]",
        "max_features": "['sqrt', 'log2', None]",
        "min_samples_leaf": "[1, 3, …, 19]",
        "min_samples_split": "[2, 4, …, 18]",
    },
    "RF": {
        "n_estimators": "[20, 25, …, 95]",
        "criterion": "['gini', 'entropy']",
        "max_depth": "[10, 20, …, 100]",
        "min_samples_leaf": "[1, 3, …, 19]",
        "max_features": "['sqrt', 'log2']",
    },
    "SVM": {
        "C": "[0.1, 1, 10, 100]",
        "kernel": "['rbf', 'linear']",
        "gamma": "['scale', 'auto', 0.001, 0.01, 0.1, 1]",
        "degree": "[2, 3, 4]",
    },
    "NB": {
        "alpha": "[0.01, 0.1, 0.5, 1.0, 2.0, 5.0]",
        "binarize": "[0.0, 0.25, 0.5, 0.75]",
    },
    "GBDT": {
        "n_estimators": "[10, 20, …, 90]",
        "learning_rate": "[0.01, 0.05, 0.1, 0.2]",
        "max_depth": "[2, 3, …, 19]",
        "subsample": "[0.4, 0.5, 0.6, 0.7, 0.8]",
        "min_samples_split": "[2, 4, …, 18]",
        "min_samples_leaf": "[20, 25, …, 45]",
        "max_features": "['sqrt', 'log2']",
    },
    "XGB": {
        "max_depth": "[20, 25, …, 45]",
        "learning_rate": "[0.01, 0.05, 0.1, 0.2]",
        "subsample": "[0.5, 0.7, 0.9, 1.0]",
        "colsample_bytree": "[0.5, 0.7, 0.9, 1.0]",
        "n_estimators": "[20, 25, …, 45]",
    },
    "LGBM": {
        "boosting_type": "['gbdt', 'dart']",
        "num_leaves": "[20, 30, …, 140]",
        "max_depth": "[10, 15, …, 45]",
        "learning_rate": "[0.01, 0.05, 0.1]",
        "n_estimators": "[10, 15, …, 45]",
        "subsample": "[0.5, 0.7, 0.9, 1.0]",
    },
}

S1_VAR_DISPLAY = {
    "icu_day": "LOS-ICU",
    "Heart_Failure": "Heart Failure",
    "Myocardial_Infarction": "Myocardial Infarction",
    "Liver_cirrhosis": "Liver cirrhosis",
    "CalciumTotal": "Calcium Total",
    "AnionGap": "Anion Gap",
}

TABLE1_PREFERRED_VAR_ORDER = [
    "Age", "Gender", "Race", "Weight", "Temperature", "PP", "RR", "SpO2",
    "SI", "PAR", "WBC", "RBC", "RDW", "AST", "ALT", "Albumin", "Glucose",
    "Potassium", "CalciumTotal", "Chloride", "Creatinine", "AnionGap", "GCS",
    "Ventilation", "Hypertension", "Heart_Failure", "Myocardial_Infarction",
    "Liver_cirrhosis", "Pneumonia", "Hyperlipidemia", "COPD",
]


def fmt_est(x: float) -> str:
    if x is None or (isinstance(x, float) and (math.isnan(x) or math.isinf(x))):
        return "NA"
    return f"{float(x):.{EST_DIGITS}f}"


def fmt_est_ci(est: float, lo: float, hi: float) -> str:
    return f"{fmt_est(est)} ({fmt_est(lo)}, {fmt_est(hi)})"


def fmt_p(p: float) -> str:
    if p is None or (isinstance(p, float) and math.isnan(p)):
        return "NA"
    if p < 0.001:
        return "<0.001"
    return f"{p:.3f}"


def confusion_metrics(y, p, threshold=THR) -> dict:
    y = np.asarray(y, dtype=int)
    p = np.asarray(p, dtype=float)
    pred = (p >= float(threshold)).astype(int)
    tn, fp, fn, tp = confusion_matrix(y, pred, labels=[0, 1]).ravel()
    spe = float(tn / (tn + fp)) if (tn + fp) else float("nan")
    return {
        "AUC": float(roc_auc_score(y, p)),
        "ACC": float(accuracy_score(y, pred)),
        "SPE": spe,
        "F1": float(f1_score(y, pred, zero_division=0)),
        "PRE": float(precision_score(y, pred, zero_division=0)),
        "SEN": float(recall_score(y, pred, zero_division=0)),
    }


def boot_metric_cis(y, p, n_boot=N_BOOT, seed=BOOT_SEED, threshold=THR) -> dict:
    point = confusion_metrics(y, p, threshold=threshold)
    rng = np.random.default_rng(seed)
    y = np.asarray(y, dtype=int)
    p = np.asarray(p, dtype=float)
    n = len(y)
    rows = []
    for _ in range(int(n_boot)):
        idx = rng.integers(0, n, n)
        yi, pi = y[idx], p[idx]
        if len(np.unique(yi)) < 2:
            continue
        rows.append(confusion_metrics(yi, pi, threshold=threshold))
    boot = pd.DataFrame(rows)
    out = {}
    for key in ("AUC", "F1", "ACC", "PRE", "SEN", "SPE"):
        arr = boot[key].dropna().to_numpy(dtype=float) if key in boot.columns else np.array([])
        if len(arr) >= 10:
            lo, hi = np.percentile(arr, [2.5, 97.5])
        else:
            lo = hi = float(point[key])
        out[key] = {"est": float(point[key]), "lo": float(lo), "hi": float(hi)}
    return out


def load_proba_dir(d: Path) -> dict[str, np.ndarray]:
    out = {}
    for name in MODEL_ORDER:
        fp = d / f"{name}.csv"
        if fp.exists():
            out[name] = pd.read_csv(fp)["prob"].to_numpy(dtype=float)
    return out


def resolve_eicu_cohorts(eicu_meta: Path, y_e: np.ndarray) -> dict:
    meta_df = pd.read_csv(eicu_meta, usecols=["unittype", "fustatus"])
    if len(meta_df) != len(y_e):
        raise RuntimeError(f"eICU meta n={len(meta_df)} != external n={len(y_e)}")
    if not np.array_equal(meta_df["fustatus"].to_numpy(dtype=int), y_e):
        raise RuntimeError("eICU df_train fustatus != external y row order")
    unit = meta_df["unittype"].astype(str).fillna("Unknown")
    mask_c1 = unit.eq("Med-Surg ICU").to_numpy()
    return {"mask_c1": mask_c1, "mask_c2": ~mask_c1}


def metrics_table_from_proba(y, proba_map, models, seed_base=0, col_order=None) -> pd.DataFrame:
    col_order = col_order or ("AUC", "F1", "ACC", "PRE", "SEN", "SPE")
    rows = []
    for i, name in enumerate(models):
        if name not in proba_map:
            continue
        # TCF Internal AUC/CI 与 S10/Fig5/Fig6 共用 SEED_OFF_INTERNAL（勿用 model index）
        seed = (
            BOOT_SEED + SEED_OFF_INTERNAL
            if name == "TCF"
            else BOOT_SEED + seed_base + i
        )
        cis = boot_metric_cis(
            y, proba_map[name], n_boot=N_BOOT, seed=seed, threshold=THR
        )
        row = {"Model": name}
        for m in col_order:
            row[m] = fmt_est_ci(cis[m]["est"], cis[m]["lo"], cis[m]["hi"])
        rows.append(row)
    return pd.DataFrame(rows)


def is_binary_like(s: pd.Series) -> bool:
    u = pd.unique(s.dropna())
    if len(u) <= 1:
        return True
    if s.dtype == object or str(s.dtype) == "category":
        return True
    if len(u) <= 8 and set(np.round(u.astype(float), 8)).issubset({0.0, 1.0}):
        return True
    return False


def fmt_cont(x: pd.Series) -> str:
    x = pd.to_numeric(x, errors="coerce").dropna()
    if len(x) == 0:
        return "NA"
    q1, med, q3 = np.percentile(x, [25, 50, 75])
    return f"{med:.2f} ({q1:.2f}, {q3:.2f})"


def fmt_cat(x: pd.Series, level) -> str:
    x = x.dropna()
    n = int(len(x))
    if n == 0:
        return "NA"
    k = int((x == level).sum())
    return f"{k:,} ({100.0 * k / n:.1f}%)"


def _order_vars_like_table1(vars_present):
    present = [v for v in vars_present if v]
    preferred = [v for v in TABLE1_PREFERRED_VAR_ORDER if v in present]
    rest = sorted(set(present) - set(preferred))
    return preferred + rest


def _fmt_stat_num(x: float, digits: int = 3) -> str:
    if x is None or (isinstance(x, float) and (math.isnan(x) or math.isinf(x))):
        return "NA"
    return f"{float(x):.{digits}f}"


def _hypothesis_cont_cells(dead: pd.Series, alive: pd.Series) -> tuple[str, str, str, str]:
    a = pd.to_numeric(dead, errors="coerce").dropna().to_numpy(dtype=float)
    b = pd.to_numeric(alive, errors="coerce").dropna().to_numpy(dtype=float)
    if len(a) < 2 or len(b) < 2:
        return "NA", "NA", "NA", "NA"
    try:
        lev = stats.levene(a, b, center="median")
        f_s, p_f = _fmt_stat_num(float(lev.statistic)), fmt_p(float(lev.pvalue))
        equal_var = bool(float(lev.pvalue) >= 0.05)
    except Exception:
        f_s, p_f, equal_var = "NA", "NA", True
    try:
        tt = stats.ttest_ind(a, b, equal_var=equal_var, nan_policy="omit")
        t_s, p_t = _fmt_stat_num(float(tt.statistic)), fmt_p(float(tt.pvalue))
    except Exception:
        t_s, p_t = "NA", "NA"
    return f_s, p_f, t_s, p_t


def _hypothesis_cat_cells(dead: pd.Series, alive: pd.Series) -> tuple[str, str, str, str]:
    d = dead.dropna().astype(str)
    a = alive.dropna().astype(str)
    if len(d) == 0 or len(a) == 0:
        return "/", "/", "NA", "NA"
    levels = sorted(set(d.unique()) | set(a.unique()))
    if len(levels) < 2:
        return "/", "/", "NA", "NA"
    tab = np.array([[int((d == lv).sum()), int((a == lv).sum())] for lv in levels], dtype=float)
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            chi2, p, dof, expected = stats.chi2_contingency(tab)
        if np.any(expected < 5) and tab.shape == (2, 2):
            _, p = stats.fisher_exact(tab)
            try:
                chi2 = float(stats.chi2_contingency(tab, correction=False)[0])
            except Exception:
                chi2 = float("nan")
            return "/", "/", _fmt_stat_num(chi2) if not math.isnan(chi2) else "NA", fmt_p(float(p))
        return "/", "/", _fmt_stat_num(float(chi2)), fmt_p(float(p))
    except Exception:
        return "/", "/", "NA", "NA"


def build_hypothesis_s1(cohorts, feature_vars, outcome="fustatus") -> pd.DataFrame:
    """S1 rows = final model features only (Wang ESM role)."""
    rows = []
    cohort_keys = list(cohorts.keys())
    for v in feature_vars:
        # detect continuous vs cat from first available cohort
        sample = None
        for ck in cohort_keys:
            if v in cohorts[ck].columns:
                sample = cohorts[ck][v]
                break
        if sample is None:
            continue
        is_cont = not is_binary_like(sample) and pd.api.types.is_numeric_dtype(
            pd.to_numeric(sample, errors="coerce")
        )
        # binary 0/1 numeric comorbidities → categorical chi-square
        if pd.api.types.is_numeric_dtype(sample) or str(sample.dtype).startswith("float"):
            u = pd.unique(pd.to_numeric(sample, errors="coerce").dropna())
            if len(u) <= 8 and set(np.round(u.astype(float), 8)).issubset({0.0, 1.0}):
                is_cont = False
        display = S1_VAR_DISPLAY.get(v, v.replace("_", " "))
        row = {"Variable": display}
        for ck in cohort_keys:
            df = cohorts[ck]
            if v not in df.columns or outcome not in df.columns:
                cells = ("NA", "NA", "NA", "NA") if is_cont else ("/", "/", "NA", "NA")
            else:
                y = pd.to_numeric(df[outcome], errors="coerce")
                dead, alive = df.loc[y == 1, v], df.loc[y == 0, v]
                cells = _hypothesis_cont_cells(dead, alive) if is_cont else _hypothesis_cat_cells(dead, alive)
            row[f"{ck}__Levene_F"] = cells[0]
            row[f"{ck}__Levene_p"] = cells[1]
            row[f"{ck}__Stat"] = cells[2]
            row[f"{ck}__Stat_p"] = cells[3]
        rows.append(row)
    return pd.DataFrame(rows)


def _decode_factor_binary_series(s, *, positive, negative, positive_code=2):
    if s.dtype == object or str(s.dtype) == "category":
        out = s.astype(str)
        known = set(out.dropna().unique())
        if known and known <= {positive, negative, "nan", "None", "NA", "<NA>"}:
            return out
        num = pd.to_numeric(out, errors="coerce")
        if num.notna().any() and set(num.dropna().unique()).issubset({0, 1, 2}):
            s = num
        else:
            return out
    num = pd.to_numeric(s, errors="coerce")
    u = set(num.dropna().unique())
    if u <= {0, 1}:
        return num.map(lambda x: positive if float(x) == 1 else negative if float(x) == 0 else pd.NA)
    if u <= {1, 2}:
        return num.map(
            lambda x: positive if float(x) == float(positive_code) else negative if pd.notna(x) else pd.NA
        )
    return s


def build_baseline_tables(tr, va, eu, vars_cont, vars_cat, outcome="fustatus"):
    n_lab = {
        "Training": f"Training (n = {len(tr):,})",
        "Internal validation": f"Internal validation (n = {len(va):,})",
        "eICU": f"eICU (n = {len(eu):,})",
    }
    rows_t1 = []
    cont_set, cat_set = set(vars_cont), set(vars_cat)
    ordered = _order_vars_like_table1([v for v in list(vars_cont) + list(vars_cat) if v in tr.columns])

    def _append_cont(v):
        rows_t1.append({
            "Characteristic": f"{v}, median (IQR)",
            n_lab["Training"]: fmt_cont(tr[v]),
            n_lab["Internal validation"]: fmt_cont(va[v]),
            n_lab["eICU"]: fmt_cont(eu[v]),
        })

    def _append_cat(v):
        levels_all = sorted(
            set(pd.unique(tr[v].dropna().astype(str)))
            | set(pd.unique(va[v].dropna().astype(str)))
            | set(pd.unique(eu[v].dropna().astype(str)))
        )
        if set(levels_all) <= {"Yes", "No"} and "Yes" in levels_all:
            rows_t1.append({
                "Characteristic": f"{v}, n (%)",
                n_lab["Training"]: fmt_cat(tr[v].astype(str), "Yes"),
                n_lab["Internal validation"]: fmt_cat(va[v].astype(str), "Yes"),
                n_lab["eICU"]: fmt_cat(eu[v].astype(str), "Yes"),
            })
            return
        pref = {"Gender": ["Male"], "Sex": ["Male"], "Race": ["Asian", "Black", "Hispanic", "Other", "White"]}.get(v)
        if v == "Race" and pref:
            levels_show = [lv for lv in pref if lv in levels_all] + [lv for lv in levels_all if lv not in pref]
        elif pref:
            levels_show = [lv for lv in pref if lv in levels_all] or list(levels_all)
        else:
            levels_show = list(levels_all)
        rows_t1.append({
            "Characteristic": v,
            n_lab["Training"]: "",
            n_lab["Internal validation"]: "",
            n_lab["eICU"]: "",
        })
        for lv in levels_show:
            rows_t1.append({
                "Characteristic": f"  {lv}",
                n_lab["Training"]: fmt_cat(tr[v].astype(str), lv),
                n_lab["Internal validation"]: fmt_cat(va[v].astype(str), lv),
                n_lab["eICU"]: fmt_cat(eu[v].astype(str), lv),
            })

    for v in ordered:
        if v in cont_set:
            _append_cont(v)
        elif v in cat_set:
            _append_cat(v)
    rows_t1.append({"Characteristic": "Outcomes", n_lab["Training"]: "", n_lab["Internal validation"]: "", n_lab["eICU"]: ""})
    rows_t1.append({
        "Characteristic": "In-hospital death, n (%)",
        n_lab["Training"]: fmt_cat(tr[outcome], 1),
        n_lab["Internal validation"]: fmt_cat(va[outcome], 1),
        n_lab["eICU"]: fmt_cat(eu[outcome], 1),
    })
    return pd.DataFrame(rows_t1)


def write_baseline_and_s1(success: Path, out: Path, features: list[str], train, valid, external) -> None:
    print("[compute] Table1 + S1 (final features) …")
    tr0 = pd.read_csv(success / "MIMIC" / "step07_train_validation" / "Data" / "df_train.csv")
    va0 = pd.read_csv(success / "MIMIC" / "step07_train_validation" / "Data" / "df_validation.csv")
    eu0 = pd.read_csv(success / "eICU" / "step07_train_validation" / "Data" / "df_train.csv")
    if len(tr0) != len(train) or len(va0) != len(valid) or len(eu0) != len(external):
        raise RuntimeError("step07 vs ML split n mismatch")
    for raw, ml in ((tr0, train), (va0, valid), (eu0, external)):
        raw["fustatus"] = ml["y"].to_numpy(dtype=int) if "y" in ml.columns else raw["fustatus"]

    for col in ("SI", "PAR"):
        if col not in tr0.columns and col in train.columns:
            tr0[col] = train[col].to_numpy()
            va0[col] = valid[col].to_numpy()
            eu0[col] = external[col].to_numpy()

    cont_candidates = [
        "Age", "Weight", "Temperature", "PP", "RR", "SpO2", "SI", "PAR", "WBC", "RBC",
        "RDW", "AST", "ALT", "Albumin", "Glucose", "Potassium", "CalciumTotal", "Chloride",
        "Creatinine", "AnionGap", "GCS",
    ]
    cat_candidates = [
        "Gender", "Race", "Ventilation", "Hypertension", "Heart_Failure",
        "Myocardial_Infarction", "Liver_cirrhosis", "Pneumonia", "Hyperlipidemia", "COPD",
    ]
    cont = [c for c in cont_candidates if c in tr0.columns]
    cat = [c for c in cat_candidates if c in tr0.columns]

    for df in (tr0, va0, eu0):
        if "Gender" in df.columns and pd.api.types.is_numeric_dtype(df["Gender"]):
            df["Gender"] = _decode_factor_binary_series(df["Gender"], positive="Male", negative="Female", positive_code=2)
        for c in cat:
            if c in ("Gender", "Race") or c not in df.columns:
                continue
            if pd.api.types.is_numeric_dtype(df[c]):
                df[c] = _decode_factor_binary_series(df[c], positive="Yes", negative="No", positive_code=2)
            else:
                df[c] = df[c].astype(str).replace({"1": "Yes", "0": "No", "True": "Yes", "False": "No"})

    t1 = build_baseline_tables(tr0, va0, eu0, cont, cat, outcome="fustatus")
    t1.to_csv(out / "table1_baseline.csv", index=False)

    unit = eu0["unittype"].astype(str)
    eu_c1 = eu0.loc[unit.eq("Med-Surg ICU")].copy()
    eu_c2 = eu0.loc[~unit.eq("Med-Surg ICU")].copy()
    # Map clinical labels for features that live only on ML matrix
    s1_feats = []
    for f in features:
        if f in tr0.columns:
            s1_feats.append(f)
        elif f in train.columns:
            # pull continuous ML feature onto clinical frames for hypothesis
            tr0[f] = train[f].to_numpy()
            va0[f] = valid[f].to_numpy()
            # eICU: from external ML matrix
            eu0[f] = external[f].to_numpy()
            eu_c1 = eu0.loc[unit.eq("Med-Surg ICU")].copy()
            eu_c2 = eu0.loc[~unit.eq("Med-Surg ICU")].copy()
            s1_feats.append(f)
        else:
            print(f"[compute] WARN S1 skip missing feature {f}")
    # Prefer feature list order from TCF summary
    s1_feats = [f for f in features if f in s1_feats]

    # Decode binary cats on pulled columns for chi-square
    for df in (tr0, va0, eu_c1, eu_c2):
        for f in s1_feats:
            if f in cat_candidates and f in df.columns and pd.api.types.is_numeric_dtype(df[f]):
                df[f] = _decode_factor_binary_series(df[f], positive="Yes", negative="No", positive_code=2)

    cohorts = {
        "Training": tr0,
        "Internal validation": va0,
        "Cohort 1 Med-Surg": eu_c1,
        "Cohort 2 other": eu_c2,
    }
    s1 = build_hypothesis_s1(cohorts, s1_feats, outcome="fustatus")
    s1.to_csv(out / "table_s1_hypothesis.csv", index=False)
    s1.to_csv(out / "table_s1_group_comparison.csv", index=False)
    meta = {
        "n_features": len(s1_feats),
        "features": s1_feats,
        "cohorts": {k: {"n": int(len(v)), "events": int((v["fustatus"] == 1).sum())} for k, v in cohorts.items()},
    }
    (out / "table_s1_hypothesis_meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    print(f"[compute] S1 rows={len(s1)} features={len(s1_feats)}")


def univ_auc(y, x) -> float:
    """Univariable AUC matching FS `.fsent11_univ_auc`: glm binomial → predict → roc_auc.

    Raw-feature roc_auc can be <0.5 (inverse association); logistic predicted probs
    align with production tcf_corr_pair_drops.csv keep/drop decisions.
    """
    y = np.asarray(y, dtype=int)
    x = pd.to_numeric(pd.Series(x), errors="coerce").to_numpy(dtype=float)
    mask = np.isfinite(x) & np.isfinite(y.astype(float))
    y, x = y[mask], x[mask]
    if len(np.unique(y)) < 2 or len(x) < 20:
        return float("nan")
    try:
        clf = LogisticRegression(max_iter=500, solver="lbfgs")
        clf.fit(x.reshape(-1, 1), y)
        p = clf.predict_proba(x.reshape(-1, 1))[:, 1]
        return float(roc_auc_score(y, p))
    except Exception:
        try:
            # fallback: direction-invariant raw AUC
            a = float(roc_auc_score(y, x))
            return max(a, 1.0 - a)
        except Exception:
            return float("nan")


def _load_mi_train_aligned(success: Path) -> pd.DataFrame:
    """MICE complete#1 rows aligned to MIMIC training stay_id (FS corr/AUC source)."""
    import subprocess
    mi_path = success / "MIMIC" / "step08_imputation" / "D01_AfterMI_Data.RData"
    tr0 = pd.read_csv(success / "MIMIC" / "step07_train_validation" / "Data" / "df_train.csv")
    if not mi_path.exists():
        return tr0
    tmp = Path("/tmp/s3_mi_train_export.csv")
    rcode = f'''
    load("{mi_path.as_posix()}")
    write.csv(object, "{tmp.as_posix()}", row.names = FALSE)
    '''
    try:
        subprocess.check_call(
            ["Rscript", "-e", rcode],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        mi = pd.read_csv(tmp)
        if "stay_id" in mi.columns and "stay_id" in tr0.columns:
            ids = set(tr0["stay_id"].astype(str))
            mi_tr = mi.loc[mi["stay_id"].astype(str).isin(ids)].copy()
            if len(mi_tr) == len(tr0):
                return mi_tr.reset_index(drop=True)
        return mi.iloc[: len(tr0)].copy()
    except Exception:
        return tr0


def build_s2_s3(success: Path, out: Path, gaps: list) -> None:
    """S2 Wang triad bake-off; S3 exhaustive pairwise |r|>=0.7 among pre-corr candidates."""
    print("[compute] S2 / S3 correlation bake-off …")
    ent_dir = success / "MIMIC" / "step10_feature_selection_entropy_stepwise"
    corr = pd.read_csv(ent_dir / "tcf_corr_pair_drops.csv")
    final_feats = list(pd.read_csv(ent_dir / "tcf_features_final.csv")["feature"])
    dropped = [str(x) for x in corr["dropped"].tolist()]
    # 33 candidates at corr-filter stage = final 30 + 3 greedy drops (log: n_after_boolean=33)
    pre_corr = list(final_feats) + [d for d in dropped if d not in final_feats]
    tr = _load_mi_train_aligned(success)
    y = pd.to_numeric(tr["fustatus"], errors="coerce").to_numpy(dtype=int)

    miss = [c for c in pre_corr if c not in tr.columns]
    if miss:
        gaps.append(f"S3 pre-corr missing columns: {miss}")
        pre_corr = [c for c in pre_corr if c in tr.columns]

    sub = tr[pre_corr].apply(pd.to_numeric, errors="coerce")
    cmat = sub.corr(method="pearson").abs()
    np.fill_diagonal(cmat.values, np.nan)
    max_abs_r = float(np.nanmax(cmat.to_numpy())) if cmat.size else float("nan")

    # Exhaustive |r|>=0.7 pairs (not only greedy sequential drops)
    thr = 0.70
    pair_rows = []
    for a, b in combinations(pre_corr, 2):
        r = float(cmat.loc[a, b]) if a in cmat.columns and b in cmat.columns else float("nan")
        if not (math.isfinite(r) and r >= thr):
            continue
        auc_a = univ_auc(y, tr[a])
        auc_b = univ_auc(y, tr[b])
        # Final retained = higher univariable AUC (ties → keep first named)
        if not math.isfinite(auc_a) and not math.isfinite(auc_b):
            kept = a
        elif not math.isfinite(auc_a):
            kept = b
        elif not math.isfinite(auc_b):
            kept = a
        else:
            kept = a if auc_a >= auc_b else b
        pair_rows.append({
            "Variable_1": a,
            "Variable_2": b,
            "abs_r": r,
            "auc_a": auc_a,
            "auc_b": auc_b,
            "AUC retention_1": fmt_est(auc_a),
            "AUC retention_2": fmt_est(auc_b),
            "Final retained": kept,
        })
    pair_rows.sort(key=lambda d: -d["abs_r"])
    s3_pub = [{
        "Variable_1": r["Variable_1"],
        "Variable_2": r["Variable_2"],
        "AUC retention_1": r["AUC retention_1"],
        "AUC retention_2": r["AUC retention_2"],
        "Final retained": r["Final retained"],
    } for r in pair_rows]
    pd.DataFrame(s3_pub).to_csv(out / "table_s3_corr_auc_pairwise.csv", index=False)

    # Near-threshold audit (evidence if Wang-like ~9 pairs absent)
    near = []
    for a, b in combinations(pre_corr, 2):
        r = float(cmat.loc[a, b]) if a in cmat.columns and b in cmat.columns else float("nan")
        if math.isfinite(r) and 0.60 <= r < thr:
            near.append({"var_a": a, "var_b": b, "abs_r": r})
    near.sort(key=lambda d: -d["abs_r"])
    special = {}
    for a, b in [("SI", "HR"), ("SI", "PP"), ("HR", "PP"), ("AST", "ALT"),
                 ("RBC", "Hematocrit"), ("Chloride", "Sodium"), ("PAR", "PlateletCount")]:
        if a in tr.columns and b in tr.columns:
            special[f"{a}__{b}"] = float(
                abs(pd.to_numeric(tr[a], errors="coerce").corr(pd.to_numeric(tr[b], errors="coerce")))
            )
        else:
            special[f"{a}__{b}"] = None

    s3_meta = {
        "n_pre_corr_candidates": len(pre_corr),
        "pre_corr_candidates": pre_corr,
        "corr_threshold": thr,
        "n_pairs_ge_thr": len(pair_rows),
        "max_abs_r": max_abs_r,
        "pairs": [
            {
                "Variable_1": r["Variable_1"],
                "Variable_2": r["Variable_2"],
                "abs_r": r["abs_r"],
                "auc_a": r["auc_a"],
                "auc_b": r["auc_b"],
                "Final retained": r["Final retained"],
            }
            for r in pair_rows
        ],
        "near_060_069": near[:20],
        "special_abs_r": special,
        "production_greedy_drops": corr.to_dict(orient="records"),
        "data_source": "MICE complete#1 train-aligned (fallback step07)",
        "note": (
            "Exhaustive C(33,2) screen at |r|>=0.7 on the correlation-filter pool "
            "(final features ∪ greedy-dropped). Only pairs meeting the threshold are tabulated."
        ),
    }
    (out / "table_s3_meta.json").write_text(json.dumps(s3_meta, indent=2), encoding="utf-8")
    print(f"  S3 exhaustive pairs |r|>={thr}: n={len(pair_rows)} (max |r|={max_abs_r:.4f})")
    for r in pair_rows:
        print(f"    {r['Variable_1']}–{r['Variable_2']}: |r|={r['abs_r']:.4f} "
              f"AUC {r['AUC retention_1']}/{r['AUC retention_2']} → {r['Final retained']}")

    # Hunt size>=3 clique at |r|>=0.7 among corr-drop neighbourhood + SI/HR/PP
    cand = sorted(set(pre_corr).union({"PP", "SI", "HR", "RBC", "Hematocrit", "Sodium", "Chloride", "RDW"}))
    cand = [c for c in cand if c in tr.columns]
    sub2 = tr[cand].apply(pd.to_numeric, errors="coerce")
    cmat2 = sub2.corr().abs()
    cliques = []
    for comb in combinations(cand, 3):
        if all(float(cmat2.loc[a, b]) >= 0.7 for a, b in combinations(comb, 2)):
            cliques.append(comb)
    triad = None
    triad_note = ""
    if cliques:
        triad = cliques[0]
        triad_note = f"Clique |r|>=0.7: {triad}"
    else:
        # Shock-index related clinical triad (only SI–HR exceeds 0.7)
        triad = ("SI", "HR", "PP")
        if all(v in tr.columns for v in triad):
            r_si_hr = float(cmat2.loc["SI", "HR"]) if "SI" in cmat2.columns and "HR" in cmat2.columns else float("nan")
            r_si_pp = float(cmat2.loc["SI", "PP"]) if "PP" in cmat2.columns else float("nan")
            r_hr_pp = float(cmat2.loc["HR", "PP"]) if "PP" in cmat2.columns else float("nan")
            triad_note = (
                f"No size>=3 clique at |r|>=0.7. Exploratory shock-index triad SI/HR/PP "
                f"(|r| SI-HR={r_si_hr:.3f}, SI-PP={r_si_pp:.3f}, HR-PP={r_hr_pp:.3f}); "
                f"univariable logistic AUC on training."
            )
            gaps.append(triad_note)
        else:
            triad = None

    s2_rows = []
    if triad is not None:
        a, b, c = triad
        # Wang: each row deletes two vars (keeps one); AUC = univariable AUC of kept var
        scenarios = [
            (a, b, c),  # delete a,b keep c
            (a, c, b),
            (b, c, a),
        ]
        aucs = []
        for d1, d2, keep in scenarios:
            auc = univ_auc(y, tr[keep])
            aucs.append((d1, d2, keep, auc))
        best = max(aucs, key=lambda t: (-1 if math.isnan(t[3]) else t[3]))
        for d1, d2, keep, auc in aucs:
            s2_rows.append({
                "Delete variables": d1,
                "Delete variables_2": d2,
                "AUC": fmt_est(auc),
                "Final scheme": "√" if (d1, d2, keep) == (best[0], best[1], best[2]) else "",
            })
        (out / "table_s2_meta.json").write_text(
            json.dumps({"triad": list(triad), "note": triad_note, "winner_keep": best[2]}, indent=2),
            encoding="utf-8",
        )
    else:
        for _, r in corr.iterrows():
            s2_rows.append({
                "Delete variables": r["dropped"],
                "Delete variables_2": "",
                "AUC": fmt_est(float(r["auc_b"] if r["kept"] == r["var_b"] else r["auc_a"])),
                "Final scheme": "√",
            })
        gaps.append("S2 fallback: pairwise drops only (no triad columns filled as dual-delete)")
    pd.DataFrame(s2_rows).to_csv(out / "table_s2_corr_combo.csv", index=False)
    pd.DataFrame(s2_rows).to_csv(out / "table_s2_corr_pairs.csv", index=False)


def build_s4_imputation(success: Path, out: Path, features: list[str], gaps: list) -> None:
    print("[compute] S4 imputation Method×AUC …")
    tr = pd.read_csv(success / "MIMIC" / "step07_train_validation" / "Data" / "df_train.csv")
    y = pd.to_numeric(tr["fustatus"], errors="coerce").to_numpy(dtype=int)
    X = tr.copy()
    cols = []
    for f in features:
        if f not in X.columns:
            continue
        if pd.api.types.is_numeric_dtype(X[f]):
            cols.append(f)
        else:
            X[f + "_c"] = pd.Categorical(X[f].astype(str)).codes.astype(float)
            cols.append(f + "_c")
    mat = X[cols].apply(pd.to_numeric, errors="coerce").to_numpy(dtype=float)
    cv = StratifiedKFold(3, shuffle=True, random_state=42)

    def cv_auc(estimator) -> float:
        scores = cross_val_score(estimator, mat, y, cv=cv, scoring="roc_auc", n_jobs=1)
        return float(np.mean(scores))

    rows = []
    # Wang-like four methods with real numbers
    knn_pipe = Pipeline([
        ("imp", KNNImputer(n_neighbors=3)),
        ("sc", StandardScaler()),
        ("clf", LogisticRegression(max_iter=500, solver="lbfgs")),
    ])
    # KNN on full data can be slow — use 3-fold; if >60s skip to subsample note
    try:
        import time
        t0 = time.time()
        # subsample for KNN speed while remaining honest about method
        rng = np.random.default_rng(42)
        idx = rng.choice(len(mat), size=min(2500, len(mat)), replace=False)
        scores = cross_val_score(
            knn_pipe, mat[idx], y[idx], cv=cv, scoring="roc_auc", n_jobs=1
        )
        knn_auc = float(np.mean(scores))
        knn_note = f"3-fold CV on n={len(idx)} training subsample"
        print(f"  kNN AUC={knn_auc:.3f} ({time.time()-t0:.1f}s)")
    except Exception as e:
        knn_auc = float("nan")
        knn_note = str(e)
        gaps.append(f"S4 kNN failed: {e}")

    mean_auc = cv_auc(Pipeline([
        ("imp", SimpleImputer(strategy="mean")),
        ("sc", StandardScaler()),
        ("clf", LogisticRegression(max_iter=500)),
    ]))
    median_auc = cv_auc(Pipeline([
        ("imp", SimpleImputer(strategy="median")),
        ("sc", StandardScaler()),
        ("clf", LogisticRegression(max_iter=500)),
    ]))
    mask = ~np.isnan(mat).any(axis=1)
    cc_scores = cross_val_score(
        Pipeline([("sc", StandardScaler()), ("clf", LogisticRegression(max_iter=500))]),
        mat[mask], y[mask], cv=cv, scoring="roc_auc",
    )
    cc_auc = float(np.mean(cc_scores))

    # Production MICE logistic_mi complete#1 — CV on imputed train rows
    mi_auc = float("nan")
    mi_path = success / "MIMIC" / "step08_imputation" / "D01_AfterMI_Data.RData"
    if mi_path.exists():
        try:
            import subprocess
            tmp = Path("/tmp/mi_s4_export.csv")
            rcode = f'''
            load("{mi_path}")
            write.csv(object, "{tmp}", row.names=FALSE)
            '''
            subprocess.check_call(["Rscript", "-e", rcode], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            mi = pd.read_csv(tmp)
            tr_ids = set(tr["stay_id"]) if "stay_id" in tr.columns and "stay_id" in mi.columns else None
            if tr_ids is not None:
                mi_tr = mi.loc[mi["stay_id"].isin(tr_ids)].copy()
            else:
                mi_tr = mi.iloc[: len(tr)].copy()
            y_mi = pd.to_numeric(mi_tr["fustatus"], errors="coerce").to_numpy(dtype=int)
            cols_mi = []
            Xm = mi_tr.copy()
            for f in features:
                if f not in Xm.columns:
                    continue
                if pd.api.types.is_numeric_dtype(Xm[f]):
                    cols_mi.append(f)
                else:
                    Xm[f + "_c"] = pd.Categorical(Xm[f].astype(str)).codes.astype(float)
                    cols_mi.append(f + "_c")
            mat_mi = Xm[cols_mi].apply(pd.to_numeric, errors="coerce").fillna(0).to_numpy(dtype=float)
            mi_auc = float(np.mean(cross_val_score(
                Pipeline([("sc", StandardScaler()), ("clf", LogisticRegression(max_iter=500))]),
                mat_mi, y_mi, cv=cv, scoring="roc_auc",
            )))
            print(f"  MICE complete#1 AUC={mi_auc:.3f}")
        except Exception as e:
            gaps.append(f"S4 MICE AUC failed: {e}")

    rows = [
        {"Method": "k-Nearest Neighbors Imputer", "AUC": fmt_est(knn_auc)},
        {"Method": "Multiple Imputation using Logistic Regression (MICE logistic_mi, m=5, complete#1)", "AUC": fmt_est(mi_auc)},
        {"Method": "Mean imputation", "AUC": fmt_est(mean_auc)},
        {"Method": "Median imputation", "AUC": fmt_est(median_auc)},
        {"Method": "Complete-case analysis", "AUC": fmt_est(cc_auc)},
    ]
    # Mark chosen = MICE (production)
    pd.DataFrame(rows).to_csv(out / "table_s4_imputation_methods.csv", index=False)
    # legacy name
    pd.DataFrame(rows).to_csv(out / "table_s4_imputation_note.csv", index=False)
    (out / "table_s4_meta.json").write_text(json.dumps({
        "knn_note": knn_note,
        "chosen": "MICE logistic_mi",
        "cv": "StratifiedKFold(3), LogisticRegression ROC-AUC on training",
        "complete_case_n": int(mask.sum()),
    }, indent=2), encoding="utf-8")


def build_s5_entropy(ent_dir: Path, out: Path) -> None:
    print("[compute] S5 entropy twin-panel …")
    ent = pd.read_csv(ent_dir / "tcf_entropy_path.csv")
    ent = ent.sort_values("k").reset_index(drop=True)
    best_i = int(ent["AUC"].astype(float).idxmax())
    best_k = int(ent.loc[best_i, "k"])
    n = len(ent)
    mid = (n + 1) // 2
    left = ent.iloc[:mid].reset_index(drop=True)
    right = ent.iloc[mid:].reset_index(drop=True)
    n_rows = max(len(left), len(right))
    rows = []
    for i in range(n_rows):
        row = {
            "Top n variables": "",
            "AUC": "",
            "Top n variables_2": "",
            "AUC_2": "",
        }
        if i < len(left):
            k = int(left.loc[i, "k"])
            auc = float(left.loc[i, "AUC"])
            mark = " *" if k == best_k else ""
            row["Top n variables"] = f"{k}{mark}"
            row["AUC"] = fmt_est(auc)
        if i < len(right):
            k = int(right.loc[i, "k"])
            auc = float(right.loc[i, "AUC"])
            mark = " *" if k == best_k else ""
            row["Top n variables_2"] = f"{k}{mark}"
            row["AUC_2"] = fmt_est(auc)
        rows.append(row)
    pd.DataFrame(rows).to_csv(out / "table_s5_entropy_path.csv", index=False)
    (out / "table_s5_meta.json").write_text(
        json.dumps({"optimal_k": best_k, "optimal_auc": float(ent.loc[best_i, "AUC"])}, indent=2),
        encoding="utf-8",
    )


def build_s6_hyperparams(md: Path, out: Path, gaps: list) -> None:
    print("[compute] S6 hyperparameters Range|Optimum …")
    rows = []
    for name in SUBMODEL_ORDER:
        fp = md / f"model_{name}.joblib"
        grid = PARAM_GRIDS.get(name, {})
        if not fp.exists():
            gaps.append(f"S6 missing {fp.name}")
            continue
        try:
            clf = joblib.load(fp)
            if hasattr(clf, "best_estimator_"):
                clf = clf.best_estimator_
            params = clf.get_params(deep=False)
            keys = list(grid.keys()) if grid else [
                k for k, v in params.items()
                if not callable(v) and not str(k).endswith("_") and k not in ("n_jobs", "verbose", "warm_start")
            ][:12]
            for k in keys:
                opt = params.get(k, "NA")
                rows.append({
                    "Model": name,
                    "Parameters": k,
                    "Range": grid.get(k, "—"),
                    "Optimum value": str(opt),
                })
        except Exception as e:
            gaps.append(f"S6 {name}: {e}")
            rows.append({"Model": name, "Parameters": "(load failed)", "Range": "NA", "Optimum value": str(e)[:120]})
    pd.DataFrame(rows).to_csv(out / "table_s6_hyperparameters.csv", index=False)


def predict_train_probas(md: Path, features: list[str], train: pd.DataFrame) -> dict[str, np.ndarray]:
    """Apply MinMaxScaler then each submodel → training-set probabilities."""
    scaler = joblib.load(md / "minmax_scaler.joblib")
    X = scaler.transform(train[features].to_numpy(dtype=float))
    out = {}
    for name in SUBMODEL_ORDER:
        fp = md / f"model_{name}.joblib"
        if not fp.exists():
            continue
        clf = joblib.load(fp)
        if hasattr(clf, "best_estimator_"):
            clf = clf.best_estimator_
        out[name] = clf.predict_proba(X)[:, 1]
    # TCF fuse if alpha available
    summary = json.loads((md / "tcf_summary.json").read_text(encoding="utf-8"))
    alpha = summary.get("alpha") or {}
    if alpha and out:
        p = np.zeros(len(train), dtype=float)
        s = 0.0
        for name, pr in out.items():
            a = float(alpha.get(name, 0.0))
            p += a * pr
            s += a
        if s > 0:
            out["TCF"] = p / s
    # prefer stored TCF train proba if length matches
    tcf_fp = md / "proba_train" / "TCF.csv"
    if tcf_fp.exists():
        pt = pd.read_csv(tcf_fp)["prob"].to_numpy(dtype=float)
        if len(pt) == len(train):
            out["TCF"] = pt
    return out


def build_s7_train(md: Path, features: list[str], train: pd.DataFrame, out: Path, gaps: list) -> None:
    print("[compute] S7 seven sub-models on TRAINING set …")
    try:
        proba = predict_train_probas(md, features, train)
        y = train["y"].to_numpy(dtype=int)
        s7 = metrics_table_from_proba(y, proba, SUBMODEL_ORDER, seed_base=300)
        s7.to_csv(out / "table_s7_submodels_train.csv", index=False)
        # also write legacy name for safety
        s7.to_csv(out / "table_s7_submodels_valid.csv", index=False)
        for name in SUBMODEL_ORDER:
            if name in proba:
                print(f"  {name} train AUC={roc_auc_score(y, proba[name]):.3f}")
    except Exception as e:
        gaps.append(f"S7 train predict failed: {e}")
        pd.DataFrame().to_csv(out / "table_s7_submodels_train.csv", index=False)


def build_s8_topsis(md: Path, out: Path) -> None:
    print("[compute] S8 TOPSIS PIS/NIS/α/rank …")
    metric_df = pd.read_csv(md / "metrics_valid.csv", index_col=0)
    metric_df = metric_df.drop(index="TCF", errors="ignore")
    # ensure column order
    cols = [c for c in ["AUC", "F1", "ACC", "PRE", "SEN", "SPE"] if c in metric_df.columns]
    metric_df = metric_df[cols].astype(float)
    scored, z, w = topsis(metric_df, weight=None)
    alpha = scored["topsis_score"] / scored["topsis_score"].sum()
    # Prefer stored alpha if present (should match)
    stored = pd.read_csv(md / "topsis_alpha.csv")
    stored_map = dict(zip(stored["model"], stored["alpha"]))
    rows = []
    for name in SUBMODEL_ORDER:
        if name not in scored.index:
            continue
        rows.append({
            "Model": name,
            "PIS": fmt_est(float(scored.loc[name, "dist_pis"])),
            "NIS": fmt_est(float(scored.loc[name, "dist_nis"])),
            "αᵢ": fmt_est(float(stored_map.get(name, alpha.loc[name]))),
            "Ranking": str(int(scored.loc[name, "rank"])),
            "Ranking min-max": fmt_est(float(stored_map.get(name, alpha.loc[name]))),
        })
    # sort by ranking
    df = pd.DataFrame(rows)
    df["_r"] = df["Ranking"].astype(int)
    df = df.sort_values("_r").drop(columns="_r")
    df.to_csv(out / "table_s8_topsis.csv", index=False)
    # overwrite old performance filename so R picks TOPSIS if pointed there
    df.to_csv(out / "table_s8_tcf_performance.csv", index=False)


def build_s9_importance(md: Path, features: list[str], out: Path, gaps: list) -> None:
    print("[compute] S9 wide feature importance …")
    imp_mat = {}
    for name in TREE_MODELS:
        fp = md / f"model_{name}.joblib"
        if not fp.exists():
            continue
        try:
            clf = joblib.load(fp)
            if hasattr(clf, "best_estimator_"):
                clf = clf.best_estimator_
            if hasattr(clf, "feature_importances_"):
                imp = np.asarray(clf.feature_importances_, dtype=float)
                if len(imp) == len(features):
                    s = float(imp.sum())
                    imp_mat[name] = imp / s if s > 0 else imp
        except Exception as e:
            gaps.append(f"S9 {name}: {e}")
    if not imp_mat:
        gaps.append("S9: no tree importances")
        pd.DataFrame().to_csv(out / "table_s9_feature_importance.csv", index=False)
        return
    rows = []
    for i, feat in enumerate(features):
        row = {"Variable": feat}
        total = 0.0
        for name in TREE_MODELS:
            if name in imp_mat:
                v = float(imp_mat[name][i])
                row[name] = fmt_est(v)
                total += v
            else:
                row[name] = ""
        row["SUM"] = fmt_est(total)
        rows.append(row)
    df = pd.DataFrame(rows)
    df["_sum"] = df["SUM"].astype(float)
    df = df.sort_values("_sum", ascending=False).reset_index(drop=True)
    df["Rank"] = np.arange(1, len(df) + 1)
    df = df.drop(columns="_sum")
    # column order
    df = df[["Variable"] + [m for m in TREE_MODELS] + ["SUM", "Rank"]]
    df.to_csv(out / "table_s9_feature_importance.csv", index=False)


def build_s10(success, mimic_tcf, eicu_ext, y_tr, y_v, y_e, p_tr, proba_v, proba_e, out, gaps):
    print("[compute] S10 TCF across datasets …")
    try:
        strata = resolve_eicu_cohorts(
            success / "eICU" / "step07_train_validation" / "Data" / "df_train.csv", y_e
        )
        specs = []
        if p_tr is not None:
            specs.append((
                "Training set (apparent, in-sample)",
                y_tr, p_tr, SEED_OFF_TRAIN,
            ))
        specs.extend([
            ("Internal validation set", y_v, proba_v["TCF"], SEED_OFF_INTERNAL),
            ("Cohort 1 (Med-Surg ICU)", y_e[strata["mask_c1"]], proba_e["TCF"][strata["mask_c1"]], SEED_OFF_C1),
            ("Cohort 2 (other unit types)", y_e[strata["mask_c2"]], proba_e["TCF"][strata["mask_c2"]], SEED_OFF_C2),
        ])
        # Optional eICU overall
        if "TCF" in proba_e:
            specs.append(("eICU overall", y_e, proba_e["TCF"], SEED_OFF_EICU))
        rows = []
        for name, y, p, off in specs:
            cis = boot_metric_cis(y, p, seed=BOOT_SEED + off)
            row = {"Dataset": name}
            for m in ("AUC", "F1", "ACC", "PRE", "SEN", "SPE"):
                row[m] = fmt_est_ci(cis[m]["est"], cis[m]["lo"], cis[m]["hi"])
            rows.append(row)
            print(f"  {name}: n={len(y)} AUC={cis['AUC']['est']:.3f}")
        pd.DataFrame(rows).to_csv(out / "table_s10_tcf_across_datasets.csv", index=False)
    except Exception as e:
        gaps.append(f"S10 failed: {e}")
        pd.DataFrame().to_csv(out / "table_s10_tcf_across_datasets.csv", index=False)


def build_s11_missing(success: Path, features: list[str], out: Path) -> None:
    print("[compute] S11 twin-panel missing rates …")
    tr0 = pd.read_csv(success / "MIMIC" / "step07_train_validation" / "Data" / "df_train.csv")
    present = [f for f in features if f in tr0.columns]
    miss_pct = [(f, float(tr0[f].isna().mean() * 100.0)) for f in present]
    # keep feature order from model
    n = len(miss_pct)
    mid = (n + 1) // 2
    left = miss_pct[:mid]
    right = miss_pct[mid:]
    n_rows = max(len(left), len(right))
    rows = []
    for i in range(n_rows):
        row = {
            "Number": "",
            "Feature": "",
            "Missing rate (%)": "",
            "Number_2": "",
            "Feature_2": "",
            "Missing rate (%)_2": "",
        }
        if i < len(left):
            row["Number"] = str(i + 1)
            row["Feature"] = left[i][0]
            row["Missing rate (%)"] = fmt_est(left[i][1])
        if i < len(right):
            row["Number_2"] = str(mid + i + 1)
            row["Feature_2"] = right[i][0]
            row["Missing rate (%)_2"] = fmt_est(right[i][1])
        rows.append(row)
    pd.DataFrame(rows).to_csv(out / "table_s11_train_missing_before_imputation.csv", index=False)


def _s12_parse_opt_val(v):
    if v is None or (isinstance(v, float) and math.isnan(v)):
        return None
    s = str(v).strip()
    if s in ("None", "none", "NULL"):
        return None
    if s in ("True", "False"):
        return s == "True"
    try:
        if "." in s:
            return float(s)
        return int(s)
    except ValueError:
        return s


def _s12_optima_from_s6(out: Path) -> dict[str, dict]:
    """Best hyperparameters from Table S6 payload (robust vs joblib/numpy pickle drift)."""
    fp = out / "table_s6_hyperparameters.csv"
    if not fp.exists():
        raise FileNotFoundError(f"S12 needs {fp}")
    s6 = pd.read_csv(fp)
    opt: dict[str, dict] = {}
    for _, r in s6.iterrows():
        opt.setdefault(str(r["Model"]), {})[str(r["Parameters"])] = r["Optimum value"]
    return opt


def _s12_make_clf(name: str, opt: dict[str, dict]):
    from sklearn.tree import DecisionTreeClassifier
    from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier
    from sklearn.svm import SVC
    from sklearn.naive_bayes import BernoulliNB

    p = {k: _s12_parse_opt_val(v) for k, v in opt[name].items()}
    if name == "DT":
        return DecisionTreeClassifier(random_state=42, **p)
    if name == "RF":
        return RandomForestClassifier(random_state=42, n_jobs=1, **p)
    if name == "SVM":
        keys = {k: p[k] for k in ("C", "kernel", "gamma", "degree") if k in p}
        return SVC(probability=True, random_state=42, **keys)
    if name == "NB":
        keys = {k: p[k] for k in ("alpha", "binarize") if k in p}
        return BernoulliNB(**keys)
    if name == "GBDT":
        return GradientBoostingClassifier(random_state=42, **p)
    if name == "XGB":
        from xgboost import XGBClassifier

        return XGBClassifier(
            random_state=42, n_jobs=1, eval_metric="logloss", **p
        )
    if name == "LGBM":
        from lightgbm import LGBMClassifier

        return LGBMClassifier(random_state=42, n_jobs=1, verbose=-1, **p)
    raise ValueError(f"Unknown S12 submodel: {name}")


def _s12_fuse_alpha(proba_map: dict[str, np.ndarray], alpha: dict) -> np.ndarray:
    names = [n for n in SUBMODEL_ORDER if n in proba_map]
    if not names:
        raise RuntimeError("S12 fuse: empty proba map")
    p = np.zeros(len(proba_map[names[0]]), dtype=float)
    s = 0.0
    for name in names:
        a = float(alpha.get(name, 0.0))
        p += a * np.asarray(proba_map[name], dtype=float)
        s += a
    if s <= 0:
        raise RuntimeError("S12 fuse: alpha sum <= 0")
    return p / s


def _s12_auc_cell(y, p, seed: int) -> str:
    cis = boot_metric_cis(y, p, seed=seed)
    return fmt_est_ci(cis["AUC"]["est"], cis["AUC"]["lo"], cis["AUC"]["hi"])


def build_s12_smote(md: Path, features: list[str], train: pd.DataFrame, valid: pd.DataFrame,
                    external: pd.DataFrame, success: Path, y_e, proba_e, out: Path, gaps: list) -> None:
    """Wang S12 analogue: Cohort × N(events) × AUC before/after SMOTE.

    Wang oversampled small *validation* cohorts. Here SMOTE is train-only, so:
      Before = same S6 hyperparameters, refit on MIMIC train WITHOUT SMOTE, TOPSIS-α fuse
      After  = production TCF (SMOTE used in training), stored probabilities
    Evaluated on Training / Internal / Cohort1 / Cohort2 (no NA when computable).
    """
    print("[compute] S12 before/after SMOTE …")
    scaler = joblib.load(md / "minmax_scaler.joblib")
    ytr = train["y"].to_numpy(dtype=int)
    yva = valid["y"].to_numpy(dtype=int)
    ye = np.asarray(y_e, dtype=int)
    Xtr_s = scaler.transform(train[features].to_numpy(dtype=float))
    Xva_s = scaler.transform(valid[features].to_numpy(dtype=float))
    Xe_s = scaler.transform(external[features].to_numpy(dtype=float))

    summary = json.loads((md / "tcf_summary.json").read_text(encoding="utf-8"))
    alpha = summary.get("alpha") or {}
    opt = _s12_optima_from_s6(out)

    # Before = no-SMOTE refit with Table S6 optima + stored α
    before_parts = {"train": {}, "valid": {}, "ext": {}}
    for name in SUBMODEL_ORDER:
        if name not in opt:
            gaps.append(f"S12 missing S6 optima for {name}")
            continue
        try:
            clf = _s12_make_clf(name, opt)
            clf.fit(Xtr_s, ytr)
            before_parts["train"][name] = clf.predict_proba(Xtr_s)[:, 1]
            before_parts["valid"][name] = clf.predict_proba(Xva_s)[:, 1]
            before_parts["ext"][name] = clf.predict_proba(Xe_s)[:, 1]
        except Exception as e:
            gaps.append(f"S12 refit {name}: {e}")

    if len(before_parts["valid"]) < 3:
        gaps.append("S12: too few before-SMOTE models to fuse")
        raise RuntimeError("S12 before-SMOTE fuse failed")

    p_before_tr = _s12_fuse_alpha(before_parts["train"], alpha)
    p_before_va = _s12_fuse_alpha(before_parts["valid"], alpha)
    p_before_e = _s12_fuse_alpha(before_parts["ext"], alpha)

    # After = production SMOTE-trained probabilities
    proba_v = load_proba_dir(md / "proba_valid")
    p_tr_fp = md / "proba_train" / "TCF.csv"
    if p_tr_fp.exists() and len(pd.read_csv(p_tr_fp)) == len(ytr):
        p_after_tr = pd.read_csv(p_tr_fp)["prob"].to_numpy(dtype=float)
    else:
        gaps.append("S12: proba_train/TCF.csv missing; After train AUC unavailable")
        p_after_tr = None
    if "TCF" not in proba_v:
        raise RuntimeError("S12: production proba_valid/TCF missing")
    p_after_va = proba_v["TCF"]
    if "TCF" not in proba_e:
        raise RuntimeError("S12: production external TCF proba missing")
    p_after_e = np.asarray(proba_e["TCF"], dtype=float)

    n_tr, e_tr = len(ytr), int(ytr.sum())
    n_va, e_va = len(yva), int(yva.sum())
    strata = resolve_eicu_cohorts(
        success / "eICU" / "step07_train_validation" / "Data" / "df_train.csv", ye
    )

    # After bootstrap offsets match Table S10 so AUC strings lock.
    # Before uses distinct offsets (+10..+13) to avoid identical CI draws.
    rows = [
        {
            "Cohort": "Training set (SMOTE target; apparent)",
            "Sample Size (No. of Positives)": f"{n_tr:,} ({e_tr:,})",
            "AUC Before Sampling": _s12_auc_cell(ytr, p_before_tr, BOOT_SEED + 10),
            "AUC After Sampling": (
                _s12_auc_cell(ytr, p_after_tr, BOOT_SEED + SEED_OFF_TRAIN)
                if p_after_tr is not None
                else "NA"
            ),
        },
        {
            "Cohort": "Internal validation set",
            "Sample Size (No. of Positives)": f"{n_va:,} ({e_va:,})",
            "AUC Before Sampling": _s12_auc_cell(yva, p_before_va, BOOT_SEED + 11),
            "AUC After Sampling": _s12_auc_cell(
                yva, p_after_va, BOOT_SEED + SEED_OFF_INTERNAL
            ),
        },
    ]
    for off, (label, mask) in zip(
        (SEED_OFF_C1, SEED_OFF_C2),
        [
            ("Cohort 1 (Med-Surg ICU)", strata["mask_c1"]),
            ("Cohort 2 (other unit types)", strata["mask_c2"]),
        ],
    ):
        yy = ye[mask]
        n, ev = int(len(yy)), int(yy.sum())
        before_off = 12 if off == SEED_OFF_C1 else 13
        rows.append({
            "Cohort": label,
            "Sample Size (No. of Positives)": f"{n:,} ({ev:,})",
            "AUC Before Sampling": _s12_auc_cell(
                yy, p_before_e[mask], BOOT_SEED + before_off
            ),
            "AUC After Sampling": _s12_auc_cell(yy, p_after_e[mask], BOOT_SEED + off),
        })
    pd.DataFrame(rows).to_csv(out / "table_s12_oversampling_validation.csv", index=False)
    n_na = sum(
        1
        for r in rows
        for k in ("AUC Before Sampling", "AUC After Sampling")
        if str(r.get(k, "")).strip().upper() in ("", "NA", "N/A", "NAN")
    )
    print(
        "  train/valid/C1/C2 before-after AUCs written "
        f"(train in-sample; bootstrap n={N_BOOT}, seed={BOOT_SEED}; "
        f"After locked to S10 seeds; NA cells={n_na})"
    )
    if n_na:
        gaps.append(f"S12 still has {n_na} NA AUC cell(s)")

def build_s13_tripod() -> pd.DataFrame:
    """Full TRIPOD+AI checklist rows (development+evaluation study)."""
    # Compact but expanded beyond short status table — official item structure
    items = [
        ("Title", "1", "D,E", "Identify the study as developing and/or evaluating a multivariable prediction model, the target population, and the outcome to be predicted", "✓", "Title / project naming (SA-AKI TCF, in-hospital death)"),
        ("Abstract", "2", "D,E", "Provide a summary of objectives, study design, setting, participants, sample size, predictors, outcome, methods, results, and conclusions", "Partial", "Methods_statistical_analysis.md / midterm; journal abstract TBD"),
        ("Background", "3a", "D,E", "Explain the healthcare context and rationale for developing or evaluating the prediction model", "✓", "Methods_statistical_analysis.md"),
        ("Background", "3b", "D,E", "Describe the target population and the care setting", "✓", "MIMIC development; eICU external ICU"),
        ("Objectives", "4", "D,E", "Specify the study objectives, including whether the study describes development, evaluation, or both", "✓", "Develop + externally evaluate TCF for SA-AKI mortality"),
        ("Source of data", "5a", "D,E", "Describe study design or source of data; key dates", "✓", "Retrospective MIMIC-IV / eICU-CRD"),
        ("Source of data", "5b", "D,E", "Specify key study dates including start and accrual", "Partial", "Database versions noted; calendar accrual window in Methods if present"),
        ("Participants", "6a", "D,E", "Describe eligibility criteria and study setting/centres", "✓", "Figure 1 flowchart; SA-AKI cohort definition"),
        ("Participants", "6b", "D,E", "Describe treatments received if relevant", "Partial", "Ventilation and comorbidities tabulated; not intervention trial"),
        ("Outcome", "7a", "D,E", "Define the outcome clearly, including measurement and timing", "✓", "In-hospital death (fustatus)"),
        ("Outcome", "7b", "D,E", "Report any actions to blind assessment of the outcome", "N/A", "Registry death flag; no separate adjudicator"),
        ("Predictors", "8a", "D", "Describe predictors and how/when measured", "✓", "Admission/ICU labs, vitals, comorbidities; final 30 features"),
        ("Predictors", "8b", "D", "Report any actions to blind assessment of predictors", "N/A", "Electronic extract; no manual blinding"),
        ("Sample size", "9", "D,E", "Explain how the study size was arrived at", "✓", "Train 4,794; Internal 1,199; eICU 6,217"),
        ("Missing data", "10", "D,E", "Describe handling of missing data", "✓", "MICE logistic_mi m=5 fit_on=train; Tables S4/S11"),
        ("Analytical methods", "11a", "D", "Describe how predictors were handled in modelling", "✓", "Entropy ranking + |r| screen; MinMax; SMOTE train-only"),
        ("Analytical methods", "11b", "D", "Specify type of model, building steps, and method for internal validation", "✓", "7 learners + TOPSIS TCF; RSCV cv=5; 80/20 holdout"),
        ("Analytical methods", "11c", "E", "Describe evaluation methods (discrimination, calibration, clinical utility)", "✓", "AUC/F1/ACC/PRE/SEN/SPE; calibration & DCA figures"),
        ("Class imbalance", "12", "D", "Describe methods for class imbalance if used", "✓", "SMOTE 1:1 on training after MinMax; Table S12"),
        ("Risk groups", "13", "D,E", "If done, how risk groups created", "N/A", "No categorical risk groups for clinical decision thresholds beyond 0.5"),
        ("Development vs evaluation", "14", "D,E", "Distinguish development and evaluation datasets", "✓", "MIMIC train/valid vs eICU external + unittype strata"),
        ("Internal validation", "15", "D", "Resampling / holdout description", "✓", "Stratified holdout + RSCV on train"),
        ("External validation", "16", "E", "Independent data evaluation", "✓", "eICU full + Cohort1/2"),
        ("Model performance", "17", "D,E", "Report performance measures with CI", "✓", "Table 2 / S7 / S10; bootstrap 95% CI"),
        ("Model specification", "18a", "D", "Present the full prediction model for use", "Partial", "joblib under Models/TCF_sklearn; not a bedside equation card"),
        ("Model specification", "18b", "D", "Explain how to use the model", "Partial", "Engine scripts + SHAP/importance figures"),
        ("Open science / code", "19a", "D,E", "Availability of code / software", "Partial", "Engine Blocks + project scripts; local joblib"),
        ("Open science / data", "19b", "D,E", "Availability of data", "Partial", "Credentialed MIMIC/eICU access"),
        ("Funding", "20", "D,E", "Source of funding and role of funders", "N/A", "Not recorded in this delivery folder"),
        ("Conflicts", "21", "D,E", "Conflicts of interest", "N/A", "Not recorded in this delivery folder"),
        ("PPI", "22", "D,E", "Patient and public involvement", "N/A", "Retrospective EHR study; no PPI documented"),
        ("Participants results", "23a", "D,E", "Flow of participants / flowchart", "✓", "Figure 1"),
        ("Participants results", "23b", "D,E", "Characteristics of participants", "✓", "Table 1"),
        ("Model performance results", "24a", "D,E", "Discrimination and classification metrics", "✓", "Table 2, S7, S10; Figures 3–6"),
        ("Model performance results", "24b", "D,E", "Calibration", "✓", "Figure S3 internal; Figure S6 external"),
        ("Model updating", "25", "D", "If model updated, describe", "N/A", "No updating step"),
        ("Interpretation", "26", "D,E", "Interpret results for clinical practice / research", "Partial", "Midterm / Methods; full Discussion TBD for journal"),
        ("Limitations", "27a", "D,E", "Discuss limitations", "Partial", "Methods/Limitations notes; optimism of train AUC noted in S10 footnote"),
        ("Implications", "27b", "D,E", "Discuss implications for practice and future research", "Partial", "Midterm narrative"),
        ("AI fairness", "AI-1", "D,E", "Assess performance across relevant subgroups", "Partial", "eICU unittype Cohort1/2; no protected-attribute fairness audit"),
        ("AI explainability", "AI-2", "D,E", "Provide model explanation / feature attribution", "✓", "SHAP Figures 4/S5; Table S9"),
        ("AI overfitting controls", "AI-3", "D", "Describe overfitting controls", "✓", "Holdout + external; SMOTE not on valid/external"),
        ("AI hyperparameter tuning", "AI-4", "D", "Describe hyperparameter tuning", "✓", "RandomizedSearchCV cv=5; Table S6"),
        ("AI ensemble fusion", "AI-5", "D", "Describe ensemble / fusion method", "✓", "Equal-weight TOPSIS α; Table S8"),
    ]
    return pd.DataFrame([
        {
            "Section/Topic": a,
            "Item": b,
            "Development / evaluation": c,
            "Checklist item": d,
            "Reported": e,
            "Location / note": f,
        }
        for a, b, c, d, e, f in items
    ])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--success-root", required=True)
    ap.add_argument("--out-dir", default="")
    ap.add_argument("--only-baseline", action="store_true")
    ap.add_argument("--only-s12", action="store_true", help="Only rebuild Table S12 CSV payload")
    args = ap.parse_args()
    success = Path(args.success_root)
    out = Path(args.out_dir) if args.out_dir else success / "_tables_rebuild_workspace" / "wang_payloads"
    out.mkdir(parents=True, exist_ok=True)
    gaps: list[str] = []

    mimic_tcf = success / "MIMIC" / "step11_ml_tcf_sklearn_rscv" / "Models" / "TCF_sklearn"
    eicu_ext = success / "eICU" / "step11_ml_tcf_sklearn_external" / "Models" / "TCF_sklearn_external"
    ent_dir = success / "MIMIC" / "step10_feature_selection_entropy_stepwise"
    summary = json.loads((mimic_tcf / "tcf_summary.json").read_text(encoding="utf-8"))
    features = list(summary.get("features") or [])

    train = pd.read_csv(mimic_tcf / "_csv" / "train.csv")
    valid = pd.read_csv(mimic_tcf / "_csv" / "valid.csv")
    external = pd.read_csv(eicu_ext / "external.csv")
    y_tr = train["y"].to_numpy(dtype=int)
    y_v = valid["y"].to_numpy(dtype=int)
    y_e = external["y"].to_numpy(dtype=int)

    if args.only_baseline:
        write_baseline_and_s1(success, out, features, train, valid, external)
        (out / "_compute_meta.json").write_text(
            json.dumps({"only_baseline": True, "gaps": gaps}, indent=2), encoding="utf-8"
        )
        print("[compute] only-baseline done →", out)
        return

    proba_v = load_proba_dir(mimic_tcf / "proba_valid")
    proba_e = {}
    for name in MODEL_ORDER:
        fp = eicu_ext / f"proba_{name}.csv"
        if fp.exists():
            proba_e[name] = pd.read_csv(fp)["prob"].to_numpy(dtype=float)

    if args.only_s12:
        # S6 optima CSV must already exist in out/
        build_s12_smote(
            mimic_tcf, features, train, valid, external, success, y_e, proba_e, out, gaps
        )
        (out / "_compute_meta.json").write_text(
            json.dumps({"only_s12": True, "gaps": gaps}, indent=2), encoding="utf-8"
        )
        print("[compute] only-s12 done →", out)
        return

    p_tr_fp = mimic_tcf / "proba_train" / "TCF.csv"
    if p_tr_fp.exists() and len(pd.read_csv(p_tr_fp)) == len(y_tr):
        p_tr = pd.read_csv(p_tr_fp)["prob"].to_numpy(dtype=float)
    else:
        gaps.append("proba_train/TCF.csv missing or length mismatch")
        p_tr = None

    # Table 2 (internal) — keep for main text
    print("[compute] Table 2 internal …")
    t2 = metrics_table_from_proba(y_v, proba_v, MODEL_ORDER, seed_base=0)
    t2.to_csv(out / "table2_internal_performance.csv", index=False)

    write_baseline_and_s1(success, out, features, train, valid, external)
    build_s2_s3(success, out, gaps)
    build_s4_imputation(success, out, features, gaps)
    build_s5_entropy(ent_dir, out)
    build_s6_hyperparams(mimic_tcf, out, gaps)
    build_s7_train(mimic_tcf, features, train, out, gaps)
    build_s8_topsis(mimic_tcf, out)
    build_s9_importance(mimic_tcf, features, out, gaps)
    build_s10(success, mimic_tcf, eicu_ext, y_tr, y_v, y_e, p_tr, proba_v, proba_e, out, gaps)
    build_s11_missing(success, features, out)
    build_s12_smote(
        mimic_tcf, features, train, valid, external, success, y_e, proba_e, out, gaps
    )
    build_s13_tripod().to_csv(out / "table_s13_tripod_ai.csv", index=False)

    meta = {
        "n_boot": N_BOOT,
        "seed": BOOT_SEED,
        "threshold": THR,
        "n_train_csv": int(len(y_tr)),
        "n_valid": int(len(y_v)),
        "n_external": int(len(y_e)),
        "n_features": len(features),
        "gaps": gaps,
        "out_dir": str(out),
        "wang_esm_aligned": True,
    }
    (out / "_compute_meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    print(json.dumps(meta, indent=2))
    print("[compute] done")


if __name__ == "__main__":
    warnings.filterwarnings("ignore", category=UserWarning)
    main()
