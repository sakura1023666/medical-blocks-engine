#!/usr/bin/env python3
"""AKI/eICU — repeated 7:2:1 splits → Table 3 mean(SD) @ Day5 (Yang pbaf003 layout).

模型：Decision Tree / XGBoost / MLP / LSTM / Two-stage Transformer / APSIII
口径：L120 (D=5), expand_hours → 24×F×5, Day5 AUC/Accuracy/F1, mean(SD) over seeds.
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
import time
from pathlib import Path

import numpy as np
import torch
from torch.utils.data import DataLoader

REPO_CANDS = [
    Path(r"E:/01block/01Block-new-Final"),
    Path("/mnt/e/01block/01Block-new-Final"),
]


def find_path(cands: list[Path]) -> Path:
    for p in cands:
        if p.exists():
            return p
    raise SystemExit(f"path not found among {[str(c) for c in cands]}")


def roc_curve_np(y_true, y_score):
    y_true = np.asarray(y_true).astype(int)
    y_score = np.asarray(y_score, dtype=float)
    order = np.argsort(-y_score)
    y_true = y_true[order]
    y_score = y_score[order]
    tps = np.cumsum(y_true == 1)
    fps = np.cumsum(y_true == 0)
    P = max(int((y_true == 1).sum()), 1)
    N = max(int((y_true == 0).sum()), 1)
    return fps / N, tps / P, y_score


def roc_auc_score(y_true, y_score):
    if len(np.unique(y_true)) < 2:
        return float("nan")
    fpr, tpr, _ = roc_curve_np(y_true, y_score)
    fpr = np.concatenate([[0.0], np.asarray(fpr, float), [1.0]])
    tpr = np.concatenate([[0.0], np.asarray(tpr, float), [1.0]])
    order = np.argsort(fpr)
    fpr, tpr = fpr[order], tpr[order]
    return float(np.trapezoid(tpr, fpr)) if hasattr(np, "trapezoid") else float(np.trapz(tpr, fpr))


def youden_pred(y, scores):
    fpr, tpr, thr = roc_curve_np(y, scores)
    opt = float(thr[np.argmax(tpr - fpr)]) if len(thr) else 0.5
    return (scores > opt).astype(int)


def f1_score_binary(y_true, y_pred):
    y_true = np.asarray(y_true).astype(int)
    y_pred = np.asarray(y_pred).astype(int)
    tp = int(((y_true == 1) & (y_pred == 1)).sum())
    fp = int(((y_true == 0) & (y_pred == 1)).sum())
    fn = int(((y_true == 1) & (y_pred == 0)).sum())
    prec = tp / (tp + fp) if (tp + fp) else 0.0
    rec = tp / (tp + fn) if (tp + fn) else 0.0
    return 0.0 if prec + rec == 0 else 2 * prec * rec / (prec + rec)


def load_score_map(proj: Path, score_name: str = "APSIII") -> dict[int, float]:
    path = proj / f"_tmp_{score_name.lower()}_by_stay.csv"
    out: dict[int, float] = {}
    if not path.is_file():
        return out
    with path.open(encoding="utf-8") as f:
        for row in csv.DictReader(f):
            keys = {k.lower(): k for k in row.keys()}
            id_k = keys.get("stay_id") or keys.get("patient") or list(row.keys())[0]
            sc_k = keys.get(score_name.lower()) or list(row.keys())[-1]
            try:
                out[int(float(row[id_k]))] = float(row[sc_k])
            except (TypeError, ValueError, KeyError):
                continue
    return out


def day5_metrics(y, los, scores) -> dict:
    sel = los >= 5
    yy = y[sel]
    ss = scores[sel] if scores.ndim == 1 else scores[sel]
    if len(yy) < 5 or len(np.unique(yy)) < 2:
        return {"auc": float("nan"), "acc": float("nan"), "f1": float("nan"), "n": int(len(yy))}
    pred = youden_pred(yy, ss)
    return {
        "auc": float(roc_auc_score(yy, ss)),
        "acc": float((pred == yy).mean()) * 100.0,
        "f1": float(f1_score_binary(yy, pred)),
        "n": int(len(yy)),
    }


def eval_transformer_day5(data_dir: Path, model_path: Path, arch: str = "b") -> dict:
    from python.two_stage_transformer.dataloader import TSTDataset
    from python.two_stage_transformer.eval import load_model_for_eval, score_all_cutoffs

    ds = TSTDataset("test", str(data_dir))
    D, H, F = ds.n_days, ds.n_hours, ds.n_features
    dl = DataLoader(ds, batch_size=64, shuffle=False)
    model = load_model_for_eval(str(model_path), arch, D, H, F)
    scores_by_day = score_all_cutoffs(model, dl, D)
    los = ds.day_mask.sum(1).astype(int)
    c = min(5, D)
    return day5_metrics(ds.y, los, scores_by_day[c])


def eval_clinical_day5(data_dir: Path, score_map: dict[int, float]) -> dict:
    d = np.load(data_dir / "test.npz", allow_pickle=False)
    y = d["y"].astype(int)
    los = d["day_mask"].sum(1).astype(int)
    pids = d["patient_id"]
    s = np.array([score_map.get(int(float(p)), np.nan) for p in pids], dtype=np.float64)
    los_eff = los.copy()
    los_eff[np.isnan(s)] = 0
    return day5_metrics(y, los_eff, s)


def eval_baselines_day5(data_dir: Path, seed: int, baseline_epochs: int) -> dict[str, dict]:
    from python.two_stage_transformer import baselines as baselines_mod

    out = Path(data_dir).parent / "baseline_cv"
    rows = baselines_mod.run_baselines(
        data_dir=str(data_dir),
        out_dir=str(out),
        models="logistic,xgboost,mlp,lstm",
        seed=seed,
        epochs=baseline_epochs,
    )
    # baselines only report pooled test auc — re-eval day5 from saved preds would need extend;
    # use test auc/acc proxy from table + decision tree separate
    out_map: dict[str, dict] = {}
    name_map = {"logistic": "Logistic", "xgboost": "XGBoost", "mlp": "MLP", "lstm": "LSTM"}
    for r in rows:
        m = r.get("model", "")
        auc = float(r.get("auc_test") or float("nan"))
        # acc/f1 not in baseline csv — approximate from auc ranking for table shell; day5 refit below
        out_map[name_map.get(m, m)] = {
            "auc": auc,
            "acc": float("nan"),
            "f1": float("nan"),
            "n": int(r.get("n_test") or 0),
        }

    # Decision tree + day5 metrics for all tabular models
    from python.two_stage_transformer.dataloader import TSTDataset
    from sklearn.tree import DecisionTreeClassifier

    te = TSTDataset("test", str(data_dir))
    tr = TSTDataset("train", str(data_dir))
    n, D, H, F = tr.X.shape[0], tr.n_days, tr.n_hours, tr.n_features

    def tabular_x(ds):
        day_valid = ds.day_mask[:, :, None, None]
        day_mean = (ds.X * day_valid).sum(axis=2) / np.clip(day_valid.sum(axis=2) * H, 1e-6, None)
        return day_mean.reshape(len(ds), D * F)

    def day5_from_proba(clf, X_te, y_te, los_te):
        proba = clf.predict_proba(X_te)[:, 1]
        return day5_metrics(y_te, los_te, proba)

    X_tr, y_tr = tabular_x(tr), tr.y
    X_te, y_te = tabular_x(te), te.y
    los_te = te.day_mask.sum(1).astype(int)
    mu, sd = X_tr.mean(0), X_tr.std(0)
    sd[sd < 1e-8] = 1.0
    X_tr = (X_tr - mu) / sd
    X_te = (X_te - mu) / sd

    dt = DecisionTreeClassifier(max_depth=8, random_state=seed, class_weight="balanced")
    dt.fit(X_tr, y_tr)
    out_map["Decision tree"] = day5_metrics(y_te, los_te, dt.predict_proba(X_te)[:, 1])

    try:
        from sklearn.linear_model import LogisticRegression
        from sklearn.neural_network import MLPClassifier
        from sklearn.ensemble import GradientBoostingClassifier

        lg = LogisticRegression(max_iter=1000, class_weight="balanced", random_state=seed)
        lg.fit(X_tr, y_tr)
        out_map["Logistic"] = day5_metrics(y_te, los_te, lg.predict_proba(X_te)[:, 1])

        mlp = MLPClassifier(hidden_layer_sizes=(64, 32), max_iter=300, random_state=seed)
        mlp.fit(X_tr, y_tr)
        out_map["MLP"] = day5_metrics(y_te, los_te, mlp.predict_proba(X_te)[:, 1])

        try:
            from xgboost import XGBClassifier
            xgb = XGBClassifier(n_estimators=200, max_depth=4, random_state=seed, eval_metric="logloss")
        except Exception:
            xgb = GradientBoostingClassifier(n_estimators=150, random_state=seed)
        xgb.fit(X_tr, y_tr)
        out_map["XGBoost"] = day5_metrics(y_te, los_te, xgb.predict_proba(X_te)[:, 1])
    except Exception as e:
        print(f"[table3cv] sklearn baselines warn: {e}")

    # LSTM day5
    try:
        import torch.nn as nn

        Xd_tr = tr.X.mean(axis=2)
        Xd_te = te.X.mean(axis=2)
        mu2 = Xd_tr.reshape(-1, F).mean(0)
        sd2 = Xd_tr.reshape(-1, F).std(0)
        sd2[sd2 < 1e-8] = 1.0
        Xd_tr = (Xd_tr - mu2) / sd2
        Xd_te = (Xd_te - mu2) / sd2

        class TinyLSTM(nn.Module):
            def __init__(self, n_feat, hidden=32):
                super().__init__()
                self.lstm = nn.LSTM(n_feat, hidden, batch_first=True)
                self.fc = nn.Linear(hidden, 1)

            def forward(self, x):
                out, _ = self.lstm(x)
                return torch.sigmoid(self.fc(out[:, -1, :])).squeeze(-1)

        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        net = TinyLSTM(F).to(device)
        opt = torch.optim.Adam(net.parameters(), lr=1e-3)
        xt = torch.tensor(Xd_tr, dtype=torch.float32, device=device)
        yt = torch.tensor(y_tr, dtype=torch.float32, device=device)
        for _ in range(baseline_epochs):
            opt.zero_grad()
            nn.functional.binary_cross_entropy(net(xt), yt).backward()
            opt.step()
        with torch.no_grad():
            p = net(torch.tensor(Xd_te, dtype=torch.float32, device=device)).cpu().numpy()
        out_map["LSTM"] = day5_metrics(y_te, los_te, p)
    except Exception as e:
        print(f"[table3cv] LSTM warn: {e}")

    return out_map


def write_csv(path: Path, rows: list[dict], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(rows)


def aggregate_table3(all_rows: list[dict], day: int = 5) -> list[dict]:
    models = [
        "Decision tree",
        "XGBoost",
        "MLP",
        "LSTM",
        "Two-stage Transformer",
        "APSIII",
    ]
    sub = [r for r in all_rows if int(r.get("day", 0)) == day]
    out = []
    for m in models:
        rs = [r for r in sub if r.get("model") == m]
        for metric, col in [("AUC", "auc"), ("Accuracy (%)", "acc"), ("F1 score", "f1")]:
            vals = [float(r[col]) for r in rs if r.get(col) not in (None, "", "nan") and r[col] == r[col]]
            if not vals:
                out.append({"Model": m, "Metric": metric, "Mean": "", "SD": "", "N_seeds": 0})
            else:
                out.append({
                    "Model": m,
                    "Metric": metric,
                    "Mean": float(np.mean(vals)),
                    "SD": float(np.std(vals, ddof=1) if len(vals) > 1 else 0.0),
                    "N_seeds": len(vals),
                })
    return out


def run_one_seed(
    *,
    full_npz: Path,
    work_root: Path,
    seed: int,
    score_map: dict[int, float],
    tf_epochs: int,
    baseline_epochs: int,
    patience: int,
    arch: str,
    train_seed: int,
) -> list[dict]:
    from python.two_stage_transformer.prepare import split_npz
    from python.two_stage_transformer.train import train

    fold_dir = work_root / f"seed_{seed}"
    data_dir = fold_dir / "npz"
    out_dir = fold_dir / "Tables"
    out_dir.mkdir(parents=True, exist_ok=True)
    print(f"\n===== Table3 CV seed={seed} =====", flush=True)
    t0 = time.time()
    split_npz(str(full_npz), str(data_dir), seed=seed)
    summary = train(
        data_dir=str(data_dir),
        out_dir=str(out_dir),
        arch=arch,
        epochs=tf_epochs,
        patience=patience,
        seed=train_seed,
    )
    tr = eval_transformer_day5(data_dir, Path(summary["model_path"]), arch=arch)
    base = eval_baselines_day5(data_dir, seed=seed, baseline_epochs=baseline_epochs)
    clin = eval_clinical_day5(data_dir, score_map)

    rows = []
    for label, met in [("Two-stage Transformer", tr), ("APSIII", clin)]:
        rows.append({"seed": seed, "model": label, "day": 5, **met, "elapsed_sec": round(time.time() - t0, 1)})
    for label, met in base.items():
        rows.append({"seed": seed, "model": label, "day": 5, **met, "elapsed_sec": round(time.time() - t0, 1)})
    write_csv(fold_dir / "fold_table3_day5.csv", rows, ["seed", "model", "day", "auc", "acc", "f1", "n", "elapsed_sec"])
    print(f"[table3cv] seed={seed} Transformer AUC={tr.get('auc')} APSIII={clin.get('auc')}", flush=True)
    return rows


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project-root", required=True)
    ap.add_argument("--landmark", type=int, default=120)
    ap.add_argument("--seeds", default="41,42,43,44,45")
    ap.add_argument("--tf-epochs", type=int, default=100)
    ap.add_argument("--baseline-epochs", type=int, default=20)
    ap.add_argument("--patience", type=int, default=15)
    ap.add_argument("--score-name", default="APSIII")
    ap.add_argument("--full-npz", default="")
    ap.add_argument("--work-dir", default="")
    args = ap.parse_args()

    repo = find_path(REPO_CANDS)
    sys.path.insert(0, str(repo))
    proj = Path(args.project_root)
    lm = int(args.landmark)
    seeds = [int(x) for x in args.seeds.split(",") if x.strip()]

    full_npz = Path(args.full_npz) if args.full_npz else (
        proj / f"by_unit/【success】L{lm}_B_twostage/step09_tst_train_eval/Tables/npz/full.npz"
    )
    if not full_npz.is_file():
        alt = proj / f"by_unit/L{lm}_B_twostage/step09_tst_train_eval/Tables/npz/full.npz"
        full_npz = alt if alt.is_file() else full_npz
    if not full_npz.is_file():
        raise SystemExit(f"full.npz not found: {full_npz}")

    work_root = Path(args.work_dir) if args.work_dir else proj / "summary_results" / "cv_table3_repeated_split"
    work_root.mkdir(parents=True, exist_ok=True)
    score_map = load_score_map(proj, args.score_name)

    meta = {
        "protocol": "repeated_patient_level_7_2_1_table3_day5",
        "landmark_h": lm,
        "seeds": seeds,
        "tf_epochs": args.tf_epochs,
        "baseline_epochs": args.baseline_epochs,
        "comparator_score": args.score_name,
        "full_npz": str(full_npz),
    }
    (work_root / "cv_meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")

    all_rows: list[dict] = []
    for seed in seeds:
        fold_csv = work_root / f"seed_{seed}" / "fold_table3_day5.csv"
        if fold_csv.is_file():
            with fold_csv.open(encoding="utf-8-sig") as f:
                all_rows.extend(list(csv.DictReader(f)))
            continue
        all_rows.extend(
            run_one_seed(
                full_npz=full_npz,
                work_root=work_root,
                seed=seed,
                score_map=score_map,
                tf_epochs=args.tf_epochs,
                baseline_epochs=args.baseline_epochs,
                patience=args.patience,
                arch="b",
                train_seed=42,
            )
        )

    write_csv(work_root / "Table_CV_Table3_fold_metrics.csv", all_rows,
              ["seed", "model", "day", "auc", "acc", "f1", "n", "elapsed_sec"])

    agg = aggregate_table3(all_rows, day=5)
    # Yang layout strings
    yang_rows = []
    order = ["Decision tree", "XGBoost", "MLP", "LSTM", "Two-stage Transformer", "APSIII"]
    for m in order:
        parts = {r["Metric"]: r for r in agg if r["Model"] == m}
        yang_rows.append({
            "Model": m,
            "AUC": f"{parts['AUC']['Mean']:.3f} ({parts['AUC']['SD']:.3f})" if parts.get("AUC", {}).get("Mean") != "" else "",
            "Accuracy (%)": f"{parts['Accuracy (%)']['Mean']:.2f} ({parts['Accuracy (%)']['SD']:.2f})" if parts.get("Accuracy (%)", {}).get("Mean") != "" else "",
            "F1 score": f"{parts['F1 score']['Mean']:.3f} ({parts['F1 score']['SD']:.3f})" if parts.get("F1 score", {}).get("Mean") != "" else "",
        })
    write_csv(work_root / "Table_3_mean_SD_Yang_layout.csv", yang_rows, ["Model", "AUC", "Accuracy (%)", "F1 score"])

    # rank check
    auc_vals = {}
    for r in agg:
        if r["Metric"] == "AUC" and r.get("Mean") != "":
            auc_vals[r["Model"]] = float(r["Mean"])
    best = max(auc_vals, key=auc_vals.get) if auc_vals else "?"
    print("\n=== Table 3 Day5 mean AUC ===")
    for k, v in sorted(auc_vals.items(), key=lambda x: -x[1]):
        print(f"  {k:24s} {v:.3f}")
    print(f"Best AUC: {best}")
    if auc_vals.get("Two-stage Transformer", 0) >= 0.75:
        print("PASS: Transformer AUC mean >= 0.75")
    else:
        print("WARN: Transformer AUC mean < 0.75 — check seeds / features / N")
    if best == "Two-stage Transformer":
        print("PASS: Transformer ranks #1 on mean AUC")
    clin_key = args.score_name if args.score_name in auc_vals else "APSIII"
    if auc_vals.get("Two-stage Transformer", 0) > auc_vals.get(clin_key, 0):
        print(f"PASS: Transformer > {clin_key}")
    print(f"[table3cv] wrote {work_root}")


if __name__ == "__main__":
    main()
