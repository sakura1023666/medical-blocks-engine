#!/usr/bin/env python3
"""Cross-eval Amsterdam↔MIMIC for Allyn Table 3 specialization cells.

Solo extractions only put eICU/HiRID (not the peer train DB) into test.
Score each solo best_model on the peer DB test stays; append CIs to
ci_main_four_arms and merge predictions into the run folders.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import torch

ROOT = Path(
    os.environ.get(
        "LIVER_ROOT",
        "/mnt/sda/BlendedICU/data/liver_dysfunction_acg_42151996",
    )
)
MAIN = ROOT / "Output_physclip"
EXTRA = ROOT / "Output_paper_extras_physclip"
BLENDED = ROOT / "blendedlos_acg"
UPSTREAM = Path(
    os.environ.get(
        "DBPOOL_UPSTREAM",
        "/mnt/sda/liver_sofa2_train/Blocks/78_database_pooling_full/upstream/BlendedLoS",
    )
)
N_BOOT = int(os.environ.get("LIVER_TABLE2_N_BOOT", "10000"))

JOBS = [
    # model_unit, train_db, peer_db, peer_extraction, prefer_subdir
    ("liver_expA_amsterdam_solo", "amsterdam", "mimic4", "train_on_mimic4", "amsterdam_100"),
    ("liver_expB_mimic_solo", "mimic4", "amsterdam", "train_on_amsterdam", "mimic4_100"),
]


def _bootstrap_unit(unit_dir: Path) -> dict:
    """Exec patching header of unit _run_one.py (literature scaler / DataReader hooks)."""
    run_py = unit_dir / "_run_one.py"
    text = run_py.read_text(encoding="utf-8")
    cut = text.find("from models.config import MultiExperimentConfig")
    if cut < 0:
        raise RuntimeError(f"cannot trim {run_py}")
    # Ensure absolute paths in sys.path before exec
    sys.path.insert(0, str(unit_dir))
    sys.path.insert(0, str(UPSTREAM))
    ns: dict = {"__name__": "cross_eval_bootstrap", "__file__": str(run_py)}
    exec(compile(text[:cut], str(run_py), "exec"), ns)
    return ns


def _pick_best_model(unit_dir: Path, prefer: str) -> Path:
    hits = sorted(unit_dir.glob(f"results/**/{prefer}*/**/best_model.pth"))
    if not hits:
        hits = sorted(unit_dir.glob("results/**/best_model.pth"))
    if not hits:
        raise FileNotFoundError(f"no best_model in {unit_dir}")
    return sorted(hits, key=lambda p: p.stat().st_mtime)[-1]


def _peer_stay_ids(peer_extract: str, peer_db: str) -> pd.Index:
    lab = pd.read_parquet(BLENDED / "extraction" / peer_extract / "test" / "labels.parquet")
    if lab.index.name == "patient" or (lab.index.dtype == object and "source_dataset" in lab.columns):
        return lab.index[lab["source_dataset"] == peer_db].astype(str)
    lab = lab.reset_index()
    pid_col = "patient" if "patient" in lab.columns else lab.columns[0]
    return lab.loc[lab["source_dataset"] == peer_db, pid_col].astype(str)


def _score_one(unit: str, train_db: str, peer_db: str, peer_extract: str, prefer: str):
    unit_dir = MAIN / unit
    os.chdir(unit_dir)
    ns = _bootstrap_unit(unit_dir)
    _fit = ns["_fit_literature_scaler"]
    _LIT = ns["_LIT"]
    _remove_pad = ns.get("_remove_pad")
    from database.datareader import DataReader
    from models.config import MultiExperimentConfig

    config = MultiExperimentConfig(str(unit_dir / "config.json"), "tpc")
    runs = config["main_experiment"]
    run_config = runs[0]
    for rc in runs:
        ton = list(getattr(rc, "train_on", []) or [])
        if ton == [train_db]:
            run_config = rc
            break

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    _LIT["fitted"] = False
    train_dr = DataReader("train", run_config, device)
    _fit(train_dr)

    peer_ids = set(_peer_stay_ids(peer_extract, peer_db).astype(str))
    print(f"[cross] {train_db}-model → {peer_db}: peer_ids={len(peer_ids)}", flush=True)

    orig_pth = run_config.datareader_pth
    run_config.datareader_pth = f"extraction/{peer_extract}/"
    test_dr = DataReader("test", run_config, device)
    run_config.datareader_pth = orig_pth

    available = pd.Index(test_dr.patient_sample).astype(str).unique()
    keep = available[available.isin(peer_ids)]
    print(f"[cross] keep={len(keep)} / available={len(available)}", flush=True)
    if len(keep) == 0:
        raise RuntimeError(f"no peer stays for {unit} → {peer_db}")

    model_pth = _pick_best_model(unit_dir, prefer)
    print(f"[cross] model={model_pth}", flush=True)
    model = torch.load(model_pth, map_location=device, weights_only=False)
    model.eval()

    los = pd.to_numeric(test_dr.labels.loc[keep, test_dr.col_truelos], errors="coerce")
    thr = test_dr.time_before_pred / 24.0
    keep2 = keep[los.to_numpy() > thr]

    def pad_remove(y, mask):
        if _remove_pad is not None:
            return _remove_pad(y, mask)
        y = y.where(mask, torch.tensor(float("nan")).to(device=y.device)).flatten().detach().cpu().numpy()
        return y[~np.isnan(y)]

    mort_frames = []
    los_frames = []
    with torch.no_grad():
        for start in range(0, len(keep2), 32):
            patient_batch = keep2[start : start + 32].to_numpy()
            flat_batch = test_dr._gen_flats(patient_batch)
            ts_batch, seq_lengths, msk = test_dr._gen_ts_batch(patient_batch)
            nrep = msk.sum(1).detach().cpu().numpy()
            if np.any(nrep <= 0):
                ok = nrep > 0
                if not np.any(ok):
                    continue
                patient_batch = patient_batch[ok]
                flat_batch = test_dr._gen_flats(patient_batch)
                ts_batch, seq_lengths, msk = test_dr._gen_ts_batch(patient_batch)
            pred_los, pred_mort = model(
                ts_batch, flat_batch, time_before_pred=test_dr.time_before_pred
            )
            true_los = test_dr._gen_los_labels(patient_batch, seq_lengths)
            repeated = test_dr._repeat_patient_batch(patient_batch, msk)
            true_mort = test_dr._gen_mort_labels(repeated).detach().cpu().numpy()
            y_los = pad_remove(true_los, msk)
            y_hat_los = pad_remove(pred_los, msk)
            y_hat_mort = pad_remove(pred_mort, msk)
            n = min(len(repeated), len(true_mort), len(y_los), len(y_hat_los), len(y_hat_mort))
            mort_frames.append(
                pd.DataFrame(
                    {
                        "patientids": np.asarray(repeated)[:n],
                        "eval_on": peer_db,
                        "pred_mort": np.asarray(y_hat_mort, dtype=float)[:n],
                        "label": np.asarray(true_mort, dtype=float)[:n],
                    }
                )
            )
            los_frames.append(
                pd.DataFrame(
                    {
                        "patientids": np.asarray(repeated)[:n],
                        "eval_on": peer_db,
                        "pred_los": np.asarray(y_hat_los, dtype=float)[:n],
                        "label": np.asarray(y_los, dtype=float)[:n],
                    }
                )
            )

    mort = pd.concat(mort_frames, ignore_index=True)
    los_df = pd.concat(los_frames, ignore_index=True)
    del model
    if device.type == "cuda":
        torch.cuda.empty_cache()
    return mort, los_df


def _ci_row(unit: str, mort: pd.DataFrame, los: pd.DataFrame, eval_on: str) -> dict:
    sys.path.insert(0, "/tmp")
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import eval_liver_paper_ci as ci_mod
    from sklearn.metrics import average_precision_score, roc_auc_score

    stay, hourly = ci_mod._stay_frame(mort, los)
    st = stay[stay["eval_on"] == eval_on]
    hr = hourly[hourly["eval_on"] == eval_on]
    auc_s, lo_s, hi_s = ci_mod.delong_auc_ci(st["y_mort"].to_numpy(), st["pred_mort"].to_numpy())
    auc_h = (
        float(roc_auc_score(hr["label"], hr["pred_mort"]))
        if len(hr) and hr["label"].nunique() > 1
        else float("nan")
    )
    auprc = float(average_precision_score(st["y_mort"], st["pred_mort"]))
    a_lo, a_hi = ci_mod._boot_ci_auprc(st, n_boot=N_BOOT, seed=42)
    mape = float(st["mape"].mean()) if "mape" in st and st["mape"].notna().any() else float("nan")
    mdf = st.dropna(subset=["mape"]).copy() if "mape" in st.columns else pd.DataFrame()
    if len(mdf):
        m_lo, m_hi = ci_mod._boot_ci_person(mdf, "mape", n_boot=N_BOOT, seed=42)
    else:
        m_lo = m_hi = float("nan")
    return {
        "unit": unit,
        "model": "tpc",
        "run": f"cross_{eval_on}",
        "eval_on": eval_on,
        "n_stays": int(len(st)),
        "n_hours": int(len(hr)),
        "auroc_stay": round(auc_s, 4),
        "auroc_stay_lo_delong": round(lo_s, 4),
        "auroc_stay_hi_delong": round(hi_s, 4),
        "auroc_hourly_point": round(auc_h, 4) if auc_h == auc_h else None,
        "auprc_stay": round(auprc, 4),
        "auprc_lo_boot10k": round(a_lo, 4) if a_lo == a_lo else None,
        "auprc_hi_boot10k": round(a_hi, 4) if a_hi == a_hi else None,
        "mape_stay_mean": round(mape, 2) if mape == mape else None,
        "mape_lo_boot10k": round(m_lo, 2) if m_lo == m_lo else None,
        "mape_hi_boot10k": round(m_hi, 2) if m_hi == m_hi else None,
        "method_auroc": "DeLong_stay",
        "method_mape_auprc": f"bootstrap_{N_BOOT}_percentile_patient",
    }


def main():
    os.environ.setdefault("DBPOOL_PHYSIO_CLIP", "1")
    os.environ.setdefault(
        "DBPOOL_DROP_TS", "alanine_aminotransferase,aspartate_aminotransferase"
    )
    os.environ["DBPOOL_REEVAL"] = "0"
    out_dir = EXTRA / "cross_eval_ams_mimic"
    out_dir.mkdir(parents=True, exist_ok=True)
    ci_path = EXTRA / "ci_main_four_arms" / "Table_CI_DeLong_bootstrap10k.csv"
    ci = pd.read_csv(ci_path)
    ci = ci[~ci["run"].astype(str).str.startswith("cross_")].copy()

    new_rows = []
    for unit, train_db, peer_db, peer_extract, prefer in JOBS:
        mort, los = _score_one(unit, train_db, peer_db, peer_extract, prefer)
        mort.to_csv(out_dir / f"{unit}_on_{peer_db}_mort.csv", index=False)
        los.to_csv(out_dir / f"{unit}_on_{peer_db}_los.csv", index=False)
        row = _ci_row(unit, mort, los, peer_db)
        new_rows.append(row)
        print("CI", row, flush=True)

        pred_hits = sorted((MAIN / unit).glob(f"results/**/{prefer}*/**/test_predictions_mort.csv"))
        if pred_hits:
            dst = pred_hits[-1]
            old = pd.read_csv(dst)
            old = old[old["eval_on"].astype(str) != peer_db]
            pd.concat([old, mort], ignore_index=True).to_csv(dst, index=False)
            los_dst = dst.parent / "test_predictions_los.csv"
            if los_dst.exists():
                old_l = pd.read_csv(los_dst)
                if "eval_on" not in old_l.columns:
                    old_l["eval_on"] = old_l["patientids"].astype(str).str.split("-").str[0]
                old_l = old_l[old_l["eval_on"].astype(str) != peer_db]
                pd.concat([old_l, los], ignore_index=True).to_csv(los_dst, index=False)
            print("merged", dst, flush=True)

    ci2 = pd.concat([ci, pd.DataFrame(new_rows)], ignore_index=True)
    ci2.to_csv(ci_path, index=False)
    print("updated", ci_path, "n=", len(ci2), flush=True)


if __name__ == "__main__":
    main()
