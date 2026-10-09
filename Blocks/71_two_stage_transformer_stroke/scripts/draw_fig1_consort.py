#!/usr/bin/env python3
r"""Draw Yang-style CONSORT Figure 1 for TST cohorts (Times New Roman).

正式入口（勿再用 run/.../_tmp_*）:
  python Blocks/71_two_stage_transformer_stroke/scripts/draw_fig1_consort.py \
    --project-root /path/to/study_output \
    [--out summary_results/Figures/Figure\ 1-MIMIC-Cohort_flowchart.pdf]

有 --project-root 时从本课题 flowchart 读人数；仅无 project-root 时才用 AKI 默认兜底。
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
from matplotlib import font_manager, pyplot as plt
from matplotlib.patches import FancyBboxPatch

FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/msttcorefonts/Times_New_Roman.ttf",
    "/usr/share/fonts/truetype/msttcorefonts/Times_New_Roman_Bold.ttf",
    r"C:\Windows\Fonts\times.ttf",
    r"C:\Windows\Fonts\timesbd.ttf",
    "/mnt/c/Windows/Fonts/times.ttf",
    "/mnt/c/Windows/Fonts/timesbd.ttf",
]


def _setup_times() -> str:
    regular = None
    bold = None
    for p in FONT_CANDIDATES:
        fp = Path(p)
        if not fp.exists():
            continue
        font_manager.fontManager.addfont(str(fp))
        name = font_manager.FontProperties(fname=str(fp)).get_name()
        low = fp.name.lower()
        if "bd" in low or "bold" in low:
            bold = name
        else:
            regular = name
    family = regular or bold or "Times New Roman"
    plt.rcParams["font.family"] = "serif"
    plt.rcParams["font.serif"] = [family, "Times New Roman", "DejaVu Serif"]
    plt.rcParams["axes.unicode_minus"] = False
    return family


def _box(ax, xy, w, h, text, *, fontsize=10, fw="normal", fc="#ffffff", ec="#222222", family="Times New Roman"):
    x, y = xy
    patch = FancyBboxPatch(
        (x, y), w, h,
        boxstyle="round,pad=0.012,rounding_size=0.02",
        linewidth=1.2, edgecolor=ec, facecolor=fc, mutation_aspect=0.3,
    )
    ax.add_patch(patch)
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center",
            fontsize=fontsize, fontweight=fw, family=family, linespacing=1.25)
    return patch


def _arrow(ax, x, y0, y1):
    ax.annotate("", xy=(x, y1), xytext=(x, y0),
                arrowprops=dict(arrowstyle="-|>", color="#222222", lw=1.2))


def _fmt(n: int) -> str:
    return f"{int(n):,}"


def draw_flowchart(pdf: Path, counts: dict) -> None:
    family = _setup_times()
    pdf = Path(pdf)
    pdf.parent.mkdir(parents=True, exist_ok=True)

    disease = counts.get("disease_label", "AKI")
    db = counts.get("db_label", "MIMIC-IV")
    miss_pct = int(counts.get("patient_miss_pct", 50))
    pool = int(counts["pool"])
    disease_n = int(counts["disease"])
    confirmed = int(counts.get("confirmed") or 0)
    n_excl_idlist = int(counts.get("n_excl_idlist") or max(disease_n - confirmed, 0))
    show_confirmed = confirmed > 0 and confirmed < disease_n
    age18 = int(counts["age18"])
    n_excl_age = int(counts.get("n_excl_age", (confirmed or disease_n) - age18))
    after_miss = int(counts["after_miss"])
    n_excl_miss = int(counts.get("n_excl_miss", age18 - after_miss))
    included = int(counts.get("included", after_miss))
    dead = int(counts["dead"])
    alive = int(counts["alive"])
    n_model = int(counts.get("n_model_l120", 0))

    fig_h = 11.2 if show_confirmed else 9.4
    ylim = 16.2 if show_confirmed else 14.0
    fig, ax = plt.subplots(figsize=(7.4, fig_h))
    ax.set_xlim(0, 10)
    ax.set_ylim(0, ylim)
    ax.axis("off")

    cx, bw, bh, ex_x, ex_w = 3.35, 4.5, 0.95, 7.45, 2.35
    if show_confirmed:
        y_adm, y_aki, y_conf, y_age, y_miss, y_incl, y_out = 14.6, 12.85, 11.1, 9.35, 7.5, 5.7, 3.5
    else:
        y_adm, y_aki, y_conf, y_age, y_miss, y_incl, y_out = 12.6, 10.9, 0.0, 9.2, 7.45, 5.7, 3.5

    _box(ax, (cx - bw / 2, y_adm), bw, bh, f"Admission records in {db}\nn = {_fmt(pool)}", fontsize=11, fw="bold", family=family)
    _arrow(ax, cx, y_adm, y_aki + bh)
    _box(ax, (cx - bw / 2, y_aki), bw, bh, f"The diagnosis includes {disease}\nn = {_fmt(disease_n)}", fontsize=11, fw="bold", family=family)
    if show_confirmed:
        _arrow(ax, cx, y_aki, y_conf + bh)
        _box(
            ax, (ex_x, y_aki - 0.2), ex_w, 1.15,
            f"Exclude:\nnot on confirmed\nstay list\n(n = {_fmt(n_excl_idlist)})",
            fontsize=8.5, fc="#f7f7f7", family=family,
        )
        ax.annotate("", xy=(ex_x, y_aki + 0.4), xytext=(cx + bw / 2, y_aki + 0.4),
                    arrowprops=dict(arrowstyle="-|>", color="#444444", lw=1.0))
        _box(ax, (cx - bw / 2, y_conf), bw, bh, f"Confirmed {disease} stays\nn = {_fmt(confirmed)}", fontsize=11, fw="bold", family=family)
        _arrow(ax, cx, y_conf, y_age + bh)
        _box(ax, (ex_x, y_conf - 0.15), ex_w, 1.05, f"Exclude:\n< 18 years\n(n = {_fmt(n_excl_age)})", fontsize=9, fc="#f7f7f7", family=family)
        ax.annotate("", xy=(ex_x, y_conf + 0.4), xytext=(cx + bw / 2, y_conf + 0.4),
                    arrowprops=dict(arrowstyle="-|>", color="#444444", lw=1.0))
    else:
        _arrow(ax, cx, y_aki, y_age + bh)
        _box(ax, (ex_x, y_aki - 0.15), ex_w, 1.05, f"Exclude:\n< 18 years\n(n = {_fmt(n_excl_age)})", fontsize=9, fc="#f7f7f7", family=family)
        ax.annotate("", xy=(ex_x, y_aki + 0.4), xytext=(cx + bw / 2, y_aki + 0.4),
                    arrowprops=dict(arrowstyle="-|>", color="#444444", lw=1.0))
    _box(ax, (cx - bw / 2, y_age), bw, bh, f"Age >= 18 years\nn = {_fmt(age18)}", fontsize=11, fw="bold", family=family)
    _arrow(ax, cx, y_age, y_miss + bh)
    _box(ax, (ex_x, y_age - 0.35), ex_w, 1.35,
         f"Exclude:\nPatient missing\n> {miss_pct}% (day 1-5)\n(n = {_fmt(n_excl_miss)})",
         fontsize=8.5, fc="#f7f7f7", family=family)
    ax.annotate("", xy=(ex_x, y_age + 0.35), xytext=(cx + bw / 2, y_age + 0.35),
                arrowprops=dict(arrowstyle="-|>", color="#444444", lw=1.0))
    _box(ax, (cx - bw / 2, y_miss), bw, bh, f"After patient missing filter\nn = {_fmt(after_miss)}", fontsize=11, fw="bold", family=family)
    _arrow(ax, cx, y_miss, y_incl + bh)
    _box(ax, (cx - bw / 2, y_incl), bw, bh, f"Included\nn = {_fmt(included)}", fontsize=12, fw="bold", fc="#eef6ff", family=family)

    ow, oh, gap = 2.55, 1.05, 0.35
    left_x = cx - gap / 2 - ow
    right_x = cx + gap / 2
    mid_y = y_incl - 0.05
    ax.plot([cx, cx], [mid_y, y_out + oh + 0.12], color="#222222", lw=1.2)
    ax.plot([left_x + ow / 2, right_x + ow / 2], [y_out + oh + 0.12, y_out + oh + 0.12], color="#222222", lw=1.2)
    ax.annotate("", xy=(left_x + ow / 2, y_out + oh), xytext=(left_x + ow / 2, y_out + oh + 0.12),
                arrowprops=dict(arrowstyle="-|>", color="#222222", lw=1.2))
    ax.annotate("", xy=(right_x + ow / 2, y_out + oh), xytext=(right_x + ow / 2, y_out + oh + 0.12),
                arrowprops=dict(arrowstyle="-|>", color="#222222", lw=1.2))
    _box(ax, (left_x, y_out), ow, oh, f"Expired group\n(n = {_fmt(dead)})", fontsize=11, fw="bold", fc="#fff5f5", family=family)
    _box(ax, (right_x, y_out), ow, oh, f"Alive group\n(n = {_fmt(alive)})", fontsize=11, fw="bold", fc="#f3fff5", family=family)

    foot = (
        f"Table 1 / primary analysis pool: N = {_fmt(included)}.\n"
        "Feature columns use a separate day-1 missing gate (> 30%); not used to drop patients."
    )
    if n_model:
        foot += f"\nL120 Day-5 modeling further requires ICU stay >= 5 days (n = {_fmt(n_model)})."
    ax.text(5.0, 0.85, foot, ha="center", va="center", fontsize=8, color="#333333", family=family)

    fig.tight_layout()
    fig.savefig(pdf, dpi=300, bbox_inches="tight")
    fig.savefig(pdf.with_suffix(".png"), dpi=220, bbox_inches="tight")
    plt.close(fig)
    print(f"font={family}")
    print(f"wrote {pdf}")
    print(f"wrote {pdf.with_suffix('.png')}")


DEFAULT_AKI_MIMIC = {
    "pool": 65366, "disease": 15533, "disease_label": "AKI", "db_label": "MIMIC-IV",
    "n_excl_age": 14, "age18": 15519, "n_excl_miss": 1069, "after_miss": 14450,
    "included": 14450, "dead": 3323, "alive": 11127, "n_model_l120": 5105, "patient_miss_pct": 50,
}


def _norm_proj_path(p: Path | str) -> Path:
    """WSL /mnt/g/... → G:/... so Windows torch python can open SMB paths."""
    s = str(p).replace("\\", "/")
    if s.startswith("/mnt/") and len(s.split("/")) >= 4:
        drive = s.split("/")[2].upper()
        rest = "/".join(s.split("/")[3:])
        return Path(f"{drive}:/{rest}")
    return Path(p)


def _read_flowchart_csv(proj: Path) -> dict[str, dict]:
    proj = _norm_proj_path(proj)
    cands = [
        proj / "_shared/step06_tst_timeseries/Tables/_tst_cohort_flowchart.csv",
        proj / "_shared/step06_tst_timeseries/_tst_cohort_flowchart.csv",
        proj / "_shared/step05_tst_timeseries/Tables/_tst_cohort_flowchart.csv",
        proj / "_shared/step05_tst_timeseries/_tst_cohort_flowchart.csv",
        proj / "_shared/step04_tst_timeseries/Tables/_tst_cohort_flowchart.csv",
        proj / "_shared/step03_tst_cohort/Tables/_tst_cohort_flowchart.csv",
        proj / "_shared/step03_tst_cohort/_tst_cohort_flowchart.csv",
    ]
    path = next((p for p in cands if p.is_file()), None)
    if path is None:
        return {}
    import csv

    out: dict[str, dict] = {}
    with path.open(encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f):
            st = str(row.get("stage") or "").strip()
            if not st:
                continue
            out[st] = row
    return out


def _disease_label_from_project(proj: Path) -> str:
    p = str(proj).replace("\\", "/")
    cfg = proj / "config_two_stage_transformer_stroke_task_parallel.R"
    txt = cfg.read_text(encoding="utf-8", errors="ignore") if cfg.is_file() else ""
    # 路径优先：禁止用 config 注释里的「对齐 TBI」把本病标成 TBI
    if "42_AKI_spesis" in p or "SepsisAKI" in txt or "sepsis-AKI" in txt.lower() or "sepsisAKI" in txt:
        return "sepsis-associated AKI"
    if "37_TBI" in p:
        return "TBI"
    if "33_AKI" in p:
        return "AKI"
    if "osteoporosis" in p.lower() or "Osteoporosis" in txt:
        return "osteoporosis"
    if "ischemic" in p.lower() or "IschemicStroke" in txt:
        return "ischemic stroke"
    return "index disease"


def counts_from_project(proj: Path, *, db_name: str = "MIMIC") -> dict:
    """从本项目 flowchart / landmark 汇总人数；禁止默认套用 AKI。"""
    proj = _norm_proj_path(proj)
    rows = _read_flowchart_csv(proj)
    if not rows:
        raise FileNotFoundError(f"flowchart CSV missing under {proj}/_shared")

    def _n(stage: str, default: int = 0) -> int:
        r = rows.get(stage) or {}
        v = r.get("n")
        try:
            return int(float(v)) if v not in (None, "") else default
        except (TypeError, ValueError):
            return default

    def _alive_dead() -> tuple[int, int]:
        for key in ("final_analysis_cohort_n_out", "final_cohort_n_out"):
            r = rows.get(key) or {}
            try:
                a = int(float(r.get("n_alive") or 0))
                d = int(float(r.get("n_dead") or 0))
                if a or d:
                    return a, d
            except (TypeError, ValueError):
                pass
        return 0, 0

    extract_n = _n("baseline_n_in")
    dabiao_n = _n("dabiao_stroke_inner_join") or _n("dabiao_inner_join")
    pool = _n("mimic_icu_pool") or _n("icu_pool_n_in")
    # 本库 stay 提取当「疾病新数据」；全库 ICU 人数单独作第一框
    if pool <= 0:
        fig1_json = proj / "_shared/_tst_fig1_counts.json"
        if fig1_json.is_file():
            try:
                extra = json.loads(fig1_json.read_text(encoding="utf-8"))
                pool = int(extra.get("mimic_icu_pool") or extra.get("pool") or 0)
            except (TypeError, ValueError, json.JSONDecodeError):
                pool = 0
    if pool <= 0:
        pool = extract_n
    disease_n = extract_n if extract_n > dabiao_n > 0 else (dabiao_n or extract_n)
    confirmed = dabiao_n if extract_n > dabiao_n > 0 else 0
    age18 = _n("age_ge_min_age") or _n("outcome_valid_0_1") or (confirmed or disease_n)
    after_miss = _n("final_analysis_cohort_n_out")
    if after_miss <= 0:
        # 无患者缺失删人时终点=队列出数
        after_miss = _n("final_cohort_n_out") or age18
    alive, dead = _alive_dead()
    n_excl_age = max((confirmed or disease_n) - age18, 0)
    n_excl_miss = max(age18 - after_miss, 0)
    n_excl_idlist = max(disease_n - confirmed, 0) if confirmed else 0

    miss_pct = 50
    cfg = proj / "config_two_stage_transformer_stroke_task_parallel.R"
    if cfg.is_file():
        import re

        txt = cfg.read_text(encoding="utf-8", errors="ignore")
        m = re.search(r"patient_missing_threshold\s*=\s*([0-9.]+)", txt)
        if m:
            miss_pct = int(round(float(m.group(1)) * 100)) if float(m.group(1)) <= 1 else int(float(m.group(1)))

    n_model = 0
    for lp in (
        proj / "_shared/step08_tst_landmark/Tables/_tst_landmark_summary.csv",
        proj / "_shared/step08_tst_landmark/_tst_landmark_summary.csv",
        proj / "_shared/step07_tst_landmark/Tables/_tst_landmark_summary.csv",
        proj / "_shared/step07_tst_landmark/_tst_landmark_summary.csv",
    ):
        if not lp.is_file():
            continue
        import csv

        with lp.open(encoding="utf-8-sig", newline="") as f:
            for row in csv.DictReader(f):
                try:
                    lm = int(float(
                        row.get("landmark_hours")
                        or row.get("landmark_h")
                        or row.get("landmark")
                        or 0
                    ))
                    elig = int(float(row.get("n_eligible") or row.get("n") or 0))
                except (TypeError, ValueError):
                    continue
                if lm == 120 and elig > 0:
                    n_model = elig
                    break
        break

    db_label = "MIMIC-IV" if str(db_name).upper().startswith("MIMIC") else str(db_name)
    out = {
        "pool": pool,
        "disease": disease_n,
        "confirmed": confirmed,
        "n_excl_idlist": n_excl_idlist,
        "disease_label": _disease_label_from_project(proj),
        "db_label": db_label,
        "n_excl_age": n_excl_age,
        "age18": age18,
        "n_excl_miss": n_excl_miss,
        "after_miss": after_miss,
        "included": after_miss,
        "dead": dead,
        "alive": alive,
        "n_model_l120": n_model,
        "patient_miss_pct": miss_pct,
    }
    fig1_json = proj / "_shared/_tst_fig1_counts.json"
    if fig1_json.is_file():
        try:
            extra = json.loads(fig1_json.read_text(encoding="utf-8"))
            for k, v in extra.items():
                if k in ("note",) or v in (None, ""):
                    continue
                out[k] = v
        except (TypeError, ValueError, json.JSONDecodeError):
            pass
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description="TST CONSORT Figure 1 (Times New Roman)")
    ap.add_argument("--project-root", default="")
    ap.add_argument("--out", default="")
    ap.add_argument("--counts-json", default="")
    ap.add_argument("--db-name", default="MIMIC")
    args = ap.parse_args()
    # 有 project-root 时必须读本课题 flowchart；禁止静默套用 AKI 默认人数
    if args.counts_json:
        counts = dict(DEFAULT_AKI_MIMIC)
        counts.update(json.loads(Path(args.counts_json).read_text(encoding="utf-8")))
    elif args.project_root:
        counts = counts_from_project(Path(args.project_root), db_name=args.db_name)
    else:
        counts = dict(DEFAULT_AKI_MIMIC)
    if args.out:
        out = _norm_proj_path(args.out) if str(args.out).startswith("/mnt/") else Path(args.out)
    elif args.project_root:
        out = _norm_proj_path(args.project_root) / f"summary_results/Figures/Figure 1-{args.db_name}-Cohort_flowchart.pdf"
    else:
        raise SystemExit("Need --out or --project-root")
    draw_flowchart(out, counts)


if __name__ == "__main__":
    main()
