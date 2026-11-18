#!/usr/bin/env python3
"""Summarize ICUAKI Allyn 4-arm mortality AUROC (test)."""
from __future__ import annotations

from pathlib import Path

import pandas as pd

ROOT = Path("/mnt/sda/BlendedICU/data/icuaaki_4db_20261106/Output_database_pooling")
OUT = Path("/mnt/sda/BlendedICU/data/icuaaki_4db_20261106/reports")
UNITS = {
    "A_amsterdam": "liver_expA_amsterdam_solo",
    "B_mimic": "liver_expB_mimic_solo",
    "C_transfer": "liver_expC_mimic2amsterdam_transfer",
    "D_pool": "liver_expD_pooled_mimic_amsterdam",
}


def last_test(unit_dir: Path):
    mets = list(unit_dir.rglob("metrics_multitask.csv"))
    cands = []
    for p in mets:
        df = pd.read_csv(p)
        if "set" not in df.columns:
            continue
        te = df[df["set"] == "test"]
        if te.empty:
            continue
        ep = te["epoch"].max()
        te = te[te["epoch"] == ep]
        cands.append((p.stat().st_mtime, p, te))
    if not cands:
        return None
    cands.sort(key=lambda x: x[0])
    prefer = [c for c in cands if "retrain" in str(c[1])]
    return prefer[-1] if prefer else cands[-1]


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    rows = []
    for name, folder in UNITS.items():
        got = last_test(ROOT / folder)
        print("===", name, "===")
        if not got:
            print("NO TEST")
            continue
        _mtime, path, te = got
        print("file", path)
        mort = te[te["task"] == "mortality"] if "task" in te.columns else te
        for _, r in mort.iterrows():
            db = str(r.get("source_dataset", "?"))
            auc = r.get("auc", None)
            auc_f = float(auc) if pd.notna(auc) else None
            rows.append({"arm": name, "db": db, "auc": auc_f})
            print(f"  mortality {db}: AUROC={auc_f}")

    df = pd.DataFrame(rows)
    wide = df.pivot_table(index="arm", columns="db", values="auc")
    print("\n=== wide ===")
    print(wide.round(3).to_string())

    print("\n=== D - B external ===")
    verdict_bits = []
    for db in ("eicu", "hirid"):
        bb = float(df[(df.arm == "B_mimic") & (df.db == db)]["auc"].iloc[0])
        dd = float(df[(df.arm == "D_pool") & (df.db == db)]["auc"].iloc[0])
        delta = dd - bb
        flag = dd > bb
        tag = "POS" if flag else "NOT_POS"
        print(f"{db}: B={bb:.3f} D={dd:.3f} D-B={delta:+.3f} {tag}")
        verdict_bits.append((db, bb, dd, delta, flag))

    wide.round(4).to_csv(OUT / "allyn_mortality_auroc_wide.csv")
    df.to_csv(OUT / "allyn_mortality_auroc_long.csv", index=False)

    lines = [
        "# ICUAKI Allyn 四臂结果（死亡 AUROC，test）",
        "",
        "| 臂 | amsterdam | eicu | hirid | mimic4 |",
        "|---|---:|---:|---:|---:|",
    ]
    for arm in ("A_amsterdam", "B_mimic", "C_transfer", "D_pool"):
        if arm not in wide.index:
            continue
        r = wide.loc[arm]

        def g(c: str) -> str:
            return f"{r[c]:.3f}" if c in r.index and pd.notna(r[c]) else "-"

        lines.append(
            f"| {arm} | {g('amsterdam')} | {g('eicu')} | {g('hirid')} | {g('mimic4')} |"
        )
    lines += ["", "## 阳性判定（外验 D > B）", ""]
    pos_any = False
    for db, bb, dd, delta, flag in verdict_bits:
        pos_any = pos_any or flag
        lines.append(
            f"- **{db}**: B={bb:.3f}, D={dd:.3f}, Δ={delta:+.3f} → {'阳性' if flag else '非阳性'}"
        )
    if pos_any:
        overall = "至少一侧外验池化优于 MIMIC 单库"
    else:
        overall = "双侧外验均未显示池化优于 MIMIC 单库（非阳性）"
    lines += [
        "",
        f"**总判读**: {overall}。",
        "",
        "口径: Allyn TPC；eICU/HiRID 训练未见；DN=1 ICU-AKI；DROP creatinine/urine_output。",
    ]
    (OUT / "allyn_results_summary.md").write_text("\n".join(lines), encoding="utf-8")
    print("\nverdict:", overall)
    print("wrote", OUT / "allyn_results_summary.md")


if __name__ == "__main__":
    main()
