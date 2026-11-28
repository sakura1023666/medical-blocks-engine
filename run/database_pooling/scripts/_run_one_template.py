import sys
import os
os.environ.setdefault("MPLBACKEND", "Agg")
import matplotlib
matplotlib.use("Agg")
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, "__CWD__")
sys.path.insert(0, "__UPSTREAM__")

# RealExtraction adapter writes flat parquet (no patient index). BlendedLoS
# pad_sequences expects index level 'patient' when reading a path list.
import database.BlendedICU as _bicu

_orig_load = _bicu.BlendedICU.load


def _load_with_patient_index(self, pth, verbose=True, **kwargs):
    if isinstance(pth, (list, tuple)):
        frames = []
        cols = kwargs.get("columns")
        for p in pth:
            # Wide hourly files only store variables observed in that stay.
            # Reindex to the requested columns so q5/q95 fitting matches the
            # paper feature list (missing stays stay NaN, then ffill + mask).
            if cols is None:
                df = pd.read_parquet(p)
            else:
                try:
                    df = pd.read_parquet(p, columns=cols)
                except Exception:
                    df = pd.read_parquet(p)
                    for c in cols:
                        if c not in df.columns:
                            df[c] = np.nan
                    df = df.loc[:, list(cols)]
            pid = Path(p).stem
            df = df.copy()
            df.index = pd.Index([pid] * len(df), name="patient")
            frames.append(df)
        if verbose:
            print(f"Loading {len(pth)} timeseries files (patient-indexed)")
        return pd.concat(frames, axis=0)
    return _orig_load(self, pth, verbose=verbose, **kwargs)


_bicu.BlendedICU.load = _load_with_patient_index

# ---------------------------------------------------------------------------
# Literature preprocess (Allyn 2026 Methods + MOESM1):
#   1) clip raw continuous values to MOESM1 physiological ranges
#   2) q5/q95 fit on TRAIN only (vitals/lab/resp) *after* physio clip
#   3) x_norm = 2 * (x - q5) / (q95 - q5) - 1
#   4) then clip to [-4, 4]
#   5) then forward-fill + observation masks (TPC layout: values + masks)
# ---------------------------------------------------------------------------
# MOESM1 "Normal physiological range" (blended column → (lo, hi)).
# Variables absent here are left unclipped before q5/q95.
_PHYSIO_CLIP = {
    "heart_rate": (46.74, 122.7),
    "invasive_systolic_blood_pressure": (67.78, 175.8),
    "invasive_diastolic_blood_pressure": (33.34, 84.24),
    "invasive_mean_blood_pressure": (46.95, 113.2),
    "noninvasive_systolic_blood_pressure": (70.5, 169.5),
    "noninvasive_diastolic_blood_pressure": (32.87, 97.12),
    "noninvasive_mean_blood_pressure": (44.37, 115.6),
    "O2_arterial_saturation": (88.7, 103.7),
    "temperature": (35.61, 38.23),
    "lactate": (0.70, 2.2),
    "blood_glucose": (2.800, 12.4),
    "magnesium": (0.533, 1.193),
    "sodium": (130.0, 148.0),
    "creatinine": (46.6, 110.0),
    "calcium": (1.675, 2.425),
    "chloride": (92.5, 119.5),
    "potassium": (2.9, 5.299),
    "PTT": (1.449, 72.55),
    "bilirubine": (23.6, 51.47),
    "alanine_aminotransferase": (10.0, 40.0),
    "aspartate_aminotransferase": (10.0, 40.0),
    "alkaline_phosphatase": (28.5, 202.5),
    "albumin": (10.0, 40.0),
    "phosphate": (0.315, 1.816),
    "bicarbonate": (15.7, 32.5),
    "blood_urea_nitrogen": (-5.14, 22.15),
    "pH": (7.235, 7.564),
    "paO2": (25.90, 163.9),
    "paCO2": (22.59, 55.6),
    "hemoglobin": (6.021, 13.97),
    "white_blood_cells": (0.500, 22.09),
    "platelets": (150.0, 370.5),
    "urine_output": (100.0, 368.8),
    "glasgow_coma_score": (-1.0, 23.0),
    "glasgow_coma_score_eye": (2.5, 5.5),
    "glasgow_coma_score_motor": (0.5, 9.5),
    "glasgow_coma_score_verbal": (3.5, 6.5),
}


def _physio_clip_enabled() -> bool:
    # Default ON (Allyn MOESM1). Set DBPOOL_PHYSIO_CLIP=0 to disable.
    raw = os.environ.get("DBPOOL_PHYSIO_CLIP", "1").strip().lower()
    return raw not in ("0", "false", "no", "off")


def _clip_physio_df(df):
    """Clip continuous columns; no-op when DBPOOL_PHYSIO_CLIP=0."""
    if not _physio_clip_enabled():
        return df
    out = df
    touched = False
    for c, (lo, hi) in _PHYSIO_CLIP.items():
        if c not in out.columns:
            continue
        if not touched:
            out = df.copy()
            touched = True
        out[c] = pd.to_numeric(out[c], errors="coerce").clip(lower=lo, upper=hi)
    return out


from database.datareader import DataReader as _DR

# Sensitivity only. Empty by default, so the main liver run keeps Allyn's list.
# DBPOOL_DROP_TS=bilirubine,alanine_aminotransferase,...
_DROP_TS = {
    x.strip()
    for x in os.environ.get("DBPOOL_DROP_TS", "").split(",")
    if x.strip()
}
_orig_get_loadcols = _DR._get_loadcols


def _get_loadcols_drop(self):
    cols = list(_orig_get_loadcols(self))
    if not _DROP_TS:
        return cols
    kept = [c for c in cols if c not in _DROP_TS]
    removed = [c for c in cols if c in _DROP_TS]
    missing = sorted(_DROP_TS.difference(cols))
    print(
        f"[drop-ts] removed={removed} absent_from_loadcols={missing} n_loadcols={len(kept)}",
        flush=True,
    )
    return kept


_DR._get_loadcols = _get_loadcols_drop

# Deadline subsample: cap each database inside the split folder before the
# paper's percentage_trainval is applied, so 10/25/50/75/100% still scale.
# Val/test use the same cap (batch size 32 cannot survive 25% of a tiny val).
_orig_included = _DR._get_included_patients


def _capped_included(self):
    inc = _orig_included(self)
    raw = os.environ.get("DBPOOL_TRAIN_STAYS_PER_DB", "").strip()
    cap = int(raw) if raw else 0
    if cap <= 0 or inc is None or len(inc) == 0:
        return inc
    parts = []
    rng = np.random.RandomState(974)
    for ds, df in inc.groupby("source_dataset"):
        df = df.sort_index()
        if len(df) > cap:
            take = rng.choice(df.index.to_numpy(), size=cap, replace=False)
            parts.append(df.loc[take])
        else:
            parts.append(df)
    out = pd.concat(parts).sort_index()
    print(
        f"[reduced-n] split={getattr(self, 'trainvaltest', '?')} "
        f"cap_per_db={cap} kept={len(out)} (seed 974)"
    )
    return out


_DR._get_included_patients = _capped_included

_LIT = {
    "fitted": False,
    "cont_cols": [],
    "q5": None,
    "q95": None,
    "flat_median": None,
    "flat_mean": None,
    "flat_std": None,
    "flat_cols": ["age", "sex", "height", "weight"],
}


def _continuous_ts_cols(loadcols, ts_variables):
    cats = ts_variables.set_index("variable")["category"]
    out = []
    for c in loadcols:
        if c == "time":
            continue
        cat = cats.get(c, None)
        if cat in ("vitals", "laboratory", "respiratory"):
            out.append(c)
    return out


def _fit_literature_scaler(train_dr, max_patients=2000, seed=974):
    """Fit train-only q5/q95 (Allyn 2026). Val/test reuse the same quantiles."""
    rng = np.random.default_rng(seed)
    patients = np.asarray(train_dr.patient_sample)
    if len(patients) == 0:
        raise ValueError("train patient_sample empty; cannot fit literature scaler")
    n = min(int(max_patients), len(patients))
    sample = patients if n == len(patients) else rng.choice(patients, size=n, replace=False)
    cont = _continuous_ts_cols(train_dr.loadcols, train_dr.ts_variables)
    paths = [
        p
        for p in train_dr._ts_pths.loc[sample, "ts_pth"].tolist()
        if Path(p).exists()
    ]
    if len(paths) < max(10, int(0.2 * n)):
        raise FileNotFoundError(
            f"literature scaler: only {len(paths)}/{n} train parquet paths exist; "
            "re-run adapter/shared before training"
        )
    # load in chunks to bound memory
    chunks = []
    step = 200
    for i in range(0, len(paths), step):
        part = train_dr.load(paths[i : i + step], columns=["time"] + cont, verbose=False)
        chunks.append(part[cont])
    raw = pd.concat(chunks, axis=0) if chunks else pd.DataFrame(columns=cont)
    raw = _clip_physio_df(raw)
    q5, q95 = {}, {}
    for c in cont:
        s = pd.to_numeric(raw[c], errors="coerce").dropna()
        if len(s) < 10:
            q5[c] = 0.0
            q95[c] = 1.0
            continue
        lo, hi = np.nanpercentile(s, [5, 95])
        lo, hi = float(lo), float(hi)
        if not np.isfinite(lo) or not np.isfinite(hi) or hi <= lo:
            mu = float(np.nanmean(s))
            lo, hi = mu - 1.0, mu + 1.0
        q5[c] = lo
        q95[c] = hi

    flat = train_dr.flat.loc[sample, _LIT["flat_cols"]].apply(pd.to_numeric, errors="coerce")
    flat_median = flat.median(numeric_only=True).fillna(0.0)
    flat_q5 = {}
    flat_q95 = {}
    for c in _LIT["flat_cols"]:
        if c == "sex":
            continue
        s = pd.to_numeric(flat[c], errors="coerce").dropna()
        if len(s) < 10:
            flat_q5[c] = 0.0
            flat_q95[c] = 1.0
            continue
        lo, hi = np.nanpercentile(s, [5, 95])
        lo, hi = float(lo), float(hi)
        if not np.isfinite(hi) or hi <= lo:
            lo, hi = float(s.mean()) - 1.0, float(s.mean()) + 1.0
        flat_q5[c] = lo
        flat_q95[c] = hi

    _LIT.update(
        {
            "fitted": True,
            "cont_cols": cont,
            "q5": q5,
            "q95": q95,
            "flat_median": flat_median,
            "flat_q5": flat_q5,
            "flat_q95": flat_q95,
        }
    )
    _pc_on = _physio_clip_enabled()
    print(
        f"[lit-preprocess] physio_clip={'MOESM1 n_vars='+str(len(_PHYSIO_CLIP)) if _pc_on else 'OFF'}; "
        f"fitted train q5-q95: n_sample={n} "
        f"cont_cols={len(cont)} formula=2*(x-q5)/(q95-q5)-1 clip=[-4,4]"
    )
    try:
        import json as _json
        _payload = {
            "n_sample": int(n),
            "physio_clip_enabled": _pc_on,
            "physio_clip": {k: list(v) for k, v in _PHYSIO_CLIP.items()} if _pc_on else {},
            "q5": q5,
            "q95": q95,
            "flat_q5": flat_q5,
            "flat_q95": flat_q95,
            "clip": [-4, 4],
            "formula": (
                "physio_clip -> 2*(x-q5)/(q95-q5)-1 -> clip[-4,4]"
                if _pc_on
                else "2*(x-q5)/(q95-q5)-1 -> clip[-4,4]"
            ),
        }
        Path("train_q5q95.json").write_text(
            _json.dumps(_payload, indent=2), encoding="utf-8"
        )
    except Exception as _exc:
        print(f"[lit-preprocess] could not write train_q5q95.json: {_exc}")


def _q5q95_scale(series, lo, hi):
    """Allyn 2026: x_norm = 2*(x-q5)/(q95-q5)-1, then clip to [-4, 4]."""
    x = pd.to_numeric(series, errors="coerce")
    denom = float(hi) - float(lo)
    if not np.isfinite(denom) or abs(denom) < 1e-8:
        denom = 1.0
    return (2.0 * (x - float(lo)) / denom - 1.0).clip(lower=-4.0, upper=4.0)


def _apply_ts_scale(df, val_cols):
    out = _clip_physio_df(df)
    for c in _LIT["cont_cols"]:
        if c not in out.columns:
            continue
        out[c] = _q5q95_scale(out[c], _LIT["q5"][c], _LIT["q95"][c])
    # meds / other non-cont: leave raw (binary 0/1 after fill)
    return out


def _gen_ts_batch_lit(self, patient_batch):
    if not _LIT["fitted"]:
        raise RuntimeError("literature scaler not fitted; Template.run must fit first")
    self.patient_ts_path = self._ts_pths.loc[patient_batch, "ts_pth"].to_list()
    ts = self.load(self.patient_ts_path, columns=self.loadcols, verbose=False)
    if ts.index.name != "patient" and "patient" not in (ts.index.names or []):
        raise ValueError("timeseries missing patient index after load patch")
    # Paper max_los (days) clamps LoS labels; hourly files can still be thousands of
    # rows (eICU outliers). Cap sequence length to max_los*24 so batch pad matches
    # the modelling horizon — does NOT change batch_size.
    # Use time relative to each stay's first timestamp: a few eICU stays start at
    # t>>0 (e.g. min=317h); absolute t<=max_hours would drop the whole stay and
    # shrink the batch (np.repeat 32 vs 31).
    _ml = getattr(self.config, "max_los", 10)
    if _ml is None:
        _ml = 10
    max_hours = int(float(_ml) * 24)
    if "time" in ts.columns and max_hours > 0:
        t_h = pd.to_numeric(ts["time"], errors="coerce")
        t0 = t_h.groupby(level="patient", sort=False).transform("min")
        t_rel = t_h - t0
        ts = ts.loc[t_h.isna() | t_rel.isna() | (t_rel <= float(max_hours))]
        # also hard-cap row count per stay (unsorted / bad clocks)
        ts = ts.groupby(level="patient", sort=False, group_keys=False).head(max_hours)
    # Keep batch cardinality = len(patient_batch) even if a stay is empty after cap.
    present = set(ts.index.get_level_values("patient").unique()) if len(ts) else set()
    val_cols = [c for c in self.loadcols if c != "time"]
    missing = [pid for pid in patient_batch if pid not in present]
    if missing:
        stub = pd.DataFrame(
            {c: np.nan for c in self.loadcols},
            index=pd.Index(missing, name="patient"),
        )
        stub["time"] = 0.0
        ts = pd.concat([ts, stub], axis=0)
    # pad_sequences groupby order must match patient_batch for np.repeat(msk).
    ts = pd.concat([ts.loc[[pid]] for pid in patient_batch], axis=0)
    masks = ts[val_cols].notna().astype(np.float32)
    masks.columns = [f"{c}__mask" for c in val_cols]
    filled = _apply_ts_scale(ts, val_cols)
    filled[val_cols] = (
        filled.groupby(level="patient", sort=False)[val_cols].ffill().fillna(0.0)
    )
    filled["time"] = filled["time"].div(24)
    out = pd.concat([filled[["time"] + val_cols], masks], axis=1)
    padded_seq, seq_lengths = self.pad_sequences(out)
    msk = self._build_msk(padded_seq, seq_lengths)
    return padded_seq, seq_lengths, msk[..., self.time_before_pred :]


def _gen_flats_lit(self, patient_batch):
    if not _LIT["fitted"]:
        raise RuntimeError("literature scaler not fitted")
    batch_flat = self.flat.loc[patient_batch, _LIT["flat_cols"]].copy()
    for c in _LIT["flat_cols"]:
        batch_flat[c] = pd.to_numeric(batch_flat[c], errors="coerce")
        batch_flat[c] = batch_flat[c].fillna(_LIT["flat_median"].get(c, 0.0))
        if c == "sex":
            continue
        batch_flat[c] = _q5q95_scale(
            batch_flat[c], _LIT["flat_q5"].get(c, 0.0), _LIT["flat_q95"].get(c, 1.0)
        )
    return self._tensorize(batch_flat.fillna(0.0))


_DR._gen_ts_batch = _gen_ts_batch_lit
_DR._gen_flats = _gen_flats_lit

# Public batch_gen draws a fresh random 32 each batch, so the test set is neither
# complete nor the same people across arms. Test scoring walks every stay once.
_orig_batch_gen = _DR.batch_gen


def _batch_gen_cover_test(self):
    if self.trainvaltest != "test":
        yield from _orig_batch_gen(self)
        return
    self._check_init()
    patients = pd.Index(self.patient_sample).unique()
    los = pd.to_numeric(self.labels.loc[patients, self.col_truelos], errors="coerce")
    keep = patients[los.to_numpy() > (self.time_before_pred / 24.0)]
    for start in range(0, len(keep), int(self.batch_size)):
        patient_batch = keep[start : start + int(self.batch_size)].to_numpy()
        flat_batch = self._gen_flats(patient_batch)
        ts_batch, seq_lengths, msk = self._gen_ts_batch(patient_batch)
        nrep = msk.sum(1).detach().cpu().numpy()
        if np.any(nrep <= 0):
            ok = nrep > 0
            if not np.any(ok):
                continue
            patient_batch = patient_batch[ok]
            flat_batch = self._gen_flats(patient_batch)
            ts_batch, seq_lengths, msk = self._gen_ts_batch(patient_batch)
        los_labels = self._gen_los_labels(patient_batch, seq_lengths)
        repeated = self._repeat_patient_batch(patient_batch, msk)
        mort_labels = self._gen_mort_labels(patient_batch)
        repeated_mort = self._gen_mort_labels(repeated)
        yield (
            patient_batch,
            repeated,
            los_labels,
            mort_labels,
            repeated_mort,
            flat_batch,
            ts_batch,
            msk,
            seq_lengths,
        )


_DR.batch_gen = _batch_gen_cover_test

# MSLE: log(0) → -inf when remaining LoS hits 0; clamp before log (numeric guard)
import models.loss as _loss_mod

_orig_msle = _loss_mod.MSLELoss.forward


def _msle_forward_safe(self, pred_los, true_los, mask, seq_length):
    eps = 1e-7
    return self.mseloss(
        pred_los.clamp(min=eps).log(),
        true_los.clamp(min=eps).log(),
        mask,
        seq_length,
    )


_loss_mod.MSLELoss.forward = _msle_forward_safe

# Early-stop: init best_epoch; never call plt.show() (hangs on WSL/headless)
# Public BlendedLoS Template hardcodes patience=5 — keep that literature-code default.
import models.template as _tmpl
import matplotlib.pyplot as plt

plt.show = lambda *a, **k: None
_orig_validate = _tmpl.Template.validate_one_epoch
_orig_run = _tmpl.Template.run


def _validate_one_epoch_safe(self):
    if not hasattr(self, "best_epoch"):
        self.best_epoch = 0
    if not np.isfinite(getattr(self, "min_loss", np.inf)):
        self.min_loss = np.inf
    return _orig_validate(self)


def _run_fit_scaler_then_train(self):
    if not _LIT["fitted"]:
        _fit_literature_scaler(self.datareaders["train"])
    return _orig_run(self)


_tmpl.Template.validate_one_epoch = _validate_one_epoch_safe
_tmpl.Template.run = _run_fit_scaler_then_train
for _alias in ("TPCTemplate", "LSTMTemplate", "TransformerTemplate"):
    setattr(_tmpl, _alias, getattr(_tmpl, _alias))
    getattr(_tmpl, _alias).validate_one_epoch = _validate_one_epoch_safe
    getattr(_tmpl, _alias).run = _run_fit_scaler_then_train

# LSTM/Transformer public code sets input_size=F+1 (values only).
# Our batch is time + values + masks = 2F+1. TPC already splits masks.
import torch.nn as nn
import models.lstm_model as _lstm
import models.transformer_model as _tfm

_orig_lstm_init = _lstm.BaseLSTM.__init__
_orig_tf_init = _tfm.Transformer.__init__


def _lstm_init_with_masks(self, config, device, F, D, n_flat_features):
    _orig_lstm_init(self, config, device, F, D, n_flat_features)
    if not getattr(self, "channelwise", False):
        self.lstm = nn.LSTM(
            input_size=2 * int(F) + 1,
            hidden_size=self.n_units,
            num_layers=self.n_layers,
            bidirectional=self.bidirectional,
            dropout=self.lstm_dropout_rate,
        )


def _tf_init_with_masks(self, config, device, F, D, n_flat_features):
    _orig_tf_init(self, config, device, F, D, n_flat_features)
    self.transformer = _tfm.TransformerEncoder(
        input_size=2 * int(F) + 1,
        d_model=self.d_model,
        num_layers=self.n_layers,
        num_heads=config.n_heads,
        feedforward_size=config.feedforward_size,
        dropout=self.tf_dropout_rate,
        pe=config.positional_encoding,
        device=device,
    )


_lstm.BaseLSTM.__init__ = _lstm_init_with_masks
_tfm.Transformer.__init__ = _tf_init_with_masks

from models.config import MultiExperimentConfig
from models.template import LSTMTemplate, TransformerTemplate, TPCTemplate

config_fname = "__CONFIG__"
experiments = __EXPERIMENTS__
models = {"lstm", "transformer", "tpc"}
templateconstructors = {
    "tpc": TPCTemplate,
    "transformer": TransformerTemplate,
    "lstm": LSTMTemplate,
}
configs = {m: MultiExperimentConfig(config_fname, m) for m in models}

def _remove_pad(y, mask):
    import torch

    y = (
        y.where(mask, torch.tensor(float("nan")).to(device=y.device))
        .flatten()
        .detach()
        .cpu()
        .numpy()
    )
    return y[~np.isnan(y)]


def _boot_ci(values_by_person, stat_fn, n_boot=1000, seed=974):
    persons = np.array(list(values_by_person))
    if len(persons) < 2:
        return np.nan, np.nan
    rng = np.random.default_rng(seed)
    stats = []
    for _ in range(n_boot):
        draw = rng.choice(persons, size=len(persons), replace=True)
        try:
            stats.append(float(stat_fn(draw)))
        except ValueError:
            continue
    if len(stats) < 50:
        return np.nan, np.nan
    lo, hi = np.percentile(stats, [2.5, 97.5])
    return float(lo), float(hi)


def _metrics_block(df, arm, eval_on):
    from sklearn.metrics import roc_auc_score

    g = df[df["eval_on"] == eval_on].copy()
    if g.empty:
        return None
    hourly_auc = float(roc_auc_score(g["y_mort"], g["y_hat_mort"]))
    alive = g[g["y_mort"] == 0]
    denom = alive["y_los"].clip(lower=4 / 24)
    mape = float(((alive["y_los"] - alive["y_hat_los"]).abs() / denom).mean() * 100)
    stay = g.groupby("stay").agg(
        y_mort=("y_mort", "max"),
        y_hat_mort=("y_hat_mort", "mean"),
        person=("person", "first"),
    )
    stay_auc = float(roc_auc_score(stay["y_mort"], stay["y_hat_mort"]))

    def person_frame(draw):
        parts = [values_by_person[p] for p in draw]
        return pd.concat(parts, axis=0)

    values_by_person = {p: sub for p, sub in g.groupby("person")}

    def stat_hour(draw):
        part = person_frame(draw)
        if part["y_mort"].nunique() < 2:
            raise ValueError("one class")
        return roc_auc_score(part["y_mort"], part["y_hat_mort"])

    def stat_stay(draw):
        part = person_frame(draw)
        st = part.groupby("stay").agg(y=("y_mort", "max"), p=("y_hat_mort", "mean"))
        if st["y"].nunique() < 2:
            raise ValueError("one class")
        return roc_auc_score(st["y"], st["p"])

    h_lo, h_hi = _boot_ci(values_by_person, stat_hour)
    s_lo, s_hi = _boot_ci(values_by_person, stat_stay)
    return {
        "arm": arm,
        "eval_on": eval_on,
        "n_hours": int(len(g)),
        "n_stays": int(g["stay"].nunique()),
        "n_persons": int(g["person"].nunique()),
        "mort_rate": float(g.groupby("stay")["y_mort"].max().mean()),
        "auc_hourly": hourly_auc,
        "auc_hourly_lo": h_lo,
        "auc_hourly_hi": h_hi,
        "auc_stay": stay_auc,
        "auc_stay_lo": s_lo,
        "auc_stay_hi": s_hi,
        "mape_hourly": mape,
    }


def _reeval_saved_models(configs, experiments):
    import torch
    from database.datareader import DataReader

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    out_dir = Path(os.environ.get("DBPOOL_REEVAL_OUT", "reeval_full_test"))
    out_dir.mkdir(parents=True, exist_ok=True)
    rows = []
    coverage = []
    for exp_name in experiments:
        config = configs["tpc"]
        if not config.run_experiment.get(exp_name, False):
            continue
        for run_config in config[exp_name]:
            _LIT["fitted"] = False
            train_dr = DataReader("train", run_config, device)
            _fit_literature_scaler(train_dr)
            job = "_".join(sorted(run_config.train_on)) + f"_{run_config.percentage_trainval}"
            if run_config.from_pretrained:
                job += "_retrain" + (
                    "_last_layer" if run_config.retrain_last_layer_only else "_all_layers"
                )
            hits = sorted(Path("results").glob(f"**/{job}/multitask/TPC/*/best_model.pth"))
            if not hits:
                raise FileNotFoundError(f"no best_model for {job}")
            model_pth = hits[-1]
            print(f"[reeval] {job} <- {model_pth}")
            model = torch.load(model_pth, map_location=device, weights_only=False)
            model.eval()
            dr = DataReader("test", run_config, device)
            patients = pd.Index(dr.patient_sample).unique()
            los = pd.to_numeric(dr.labels.loc[patients, dr.col_truelos], errors="coerce")
            thr = dr.time_before_pred / 24.0
            keep = patients[los.to_numpy() > thr]
            short = int((~(los.to_numpy() > thr)).sum())
            frames = []
            dropped_empty = 0
            with torch.no_grad():
                for start in range(0, len(keep), 32):
                    patient_batch = keep[start : start + 32].to_numpy()
                    flat_batch = dr._gen_flats(patient_batch)
                    ts_batch, seq_lengths, msk = dr._gen_ts_batch(patient_batch)
                    nrep = msk.sum(1).detach().cpu().numpy()
                    if np.any(nrep <= 0):
                        ok = nrep > 0
                        dropped_empty += int((~ok).sum())
                        if not np.any(ok):
                            continue
                        patient_batch = patient_batch[ok]
                        flat_batch = dr._gen_flats(patient_batch)
                        ts_batch, seq_lengths, msk = dr._gen_ts_batch(patient_batch)
                    pred_los, pred_mort = model(
                        ts_batch, flat_batch, time_before_pred=dr.time_before_pred
                    )
                    true_los = dr._gen_los_labels(patient_batch, seq_lengths)
                    repeated = dr._repeat_patient_batch(patient_batch, msk)
                    true_mort = dr._gen_mort_labels(repeated).detach().cpu().numpy()
                    y_los = _remove_pad(true_los, msk)
                    y_hat_los = _remove_pad(pred_los, msk)
                    y_hat_mort = _remove_pad(pred_mort, msk)
                    if not (len(repeated) == len(true_mort) == len(y_los) == len(y_hat_los) == len(y_hat_mort)):
                        raise RuntimeError(
                            f"prediction length mismatch stays={len(patient_batch)} "
                            f"ids={len(repeated)} mort={len(true_mort)} los={len(y_los)} "
                            f"hat_los={len(y_hat_los)} hat_mort={len(y_hat_mort)}"
                        )
                    batch = pd.DataFrame(
                        {
                            "stay": repeated,
                            "y_los": y_los,
                            "y_hat_los": y_hat_los,
                            "y_mort": true_mort,
                            "y_hat_mort": y_hat_mort,
                        }
                    )
                    frames.append(batch)
            pred = pd.concat(frames, ignore_index=True)
            pred["eval_on"] = pred["stay"].str.split("-").str[0]
            pred["person"] = dr.labels.loc[pred["stay"], "uniquepid"].to_numpy()
            pred_path = out_dir / f"{job}_predictions.parquet"
            pred.to_parquet(pred_path, index=False)
            coverage.append(
                {
                    "job": job,
                    "model": str(model_pth),
                    "test_stays_in_split": int(len(patients)),
                    "shorter_than_5h": short,
                    "empty_after_hour5": dropped_empty,
                    "scored_stays": int(pred["stay"].nunique()),
                    "scored_persons": int(pred["person"].nunique()),
                }
            )
            for db in sorted(pred["eval_on"].unique()):
                block = _metrics_block(pred, job, db)
                if block:
                    rows.append(block)
            del model
            if device.type == "cuda":
                torch.cuda.empty_cache()
    pd.DataFrame(rows).to_csv(out_dir / "metrics_own_test.csv", index=False)
    pd.DataFrame(coverage).to_csv(out_dir / "coverage.csv", index=False)
    print(pd.DataFrame(rows).to_string(index=False))


if os.environ.get("DBPOOL_REEVAL") == "1":
    _reeval_saved_models(configs, experiments)
    print("[dbpool] reeval finished OK")
    sys.exit(0)

for exp_name in experiments:
    for model in models:
        config = configs[model]
        if not config.run_experiment.get(exp_name, False):
            print(f"Skipping {model} - {exp_name}")
            continue
        print(f"{model} - {exp_name}")
        for run_config in config[exp_name]:
            # reset scaler per run (different train_on → different train patients)
            _LIT["fitted"] = False
            templateconstructors[model](run_config).run()

print("[dbpool] unit finished OK")
sys.exit(0)
