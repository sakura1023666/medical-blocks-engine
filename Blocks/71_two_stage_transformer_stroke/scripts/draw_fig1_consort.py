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
    """圆角框：pad=0（避免内缩吃高度），字号保守，居中不贴边。"""
    x, y = xy
    patch = FancyBboxPatch(
        (x, y), w, h,
        boxstyle="round,pad=0.0,rounding_size=0.06",
        linewidth=1.1, edgecolor=ec, facecolor=fc,
    )
    ax.add_patch(patch)
    ax.text(
        x + w / 2, y + h / 2, text,
        ha="center", va="center",
        fontsize=fontsize, fontweight=fw, family=family,
        linespacing=1.20, color="#111111",
        clip_on=False,
    )
    return patch


def _arrow(ax, x, y0, y1):
    ax.annotate("", xy=(x, y1), xytext=(x, y0),
                arrowprops=dict(arrowstyle="-|>", color="#222222", lw=1.2))


def _fmt(n: int) -> str:
    return f"{int(n):,}"


def _short_lines(text: str, max_chars: int = 28) -> str:
    """把过长标签收成短行，避免撑破圆角框。"""
    raw = str(text or "").replace("\n", " ").strip()
    if len(raw) <= max_chars:
        return raw
    # 优先在空格/逗号处断
    parts = []
    buf = ""
    for tok in raw.replace(",", ", ").split():
        cand = (buf + " " + tok).strip()
        if len(cand) <= max_chars:
            buf = cand
        else:
            if buf:
                parts.append(buf)
            buf = tok
    if buf:
        parts.append(buf)
    return "\n".join(parts[:3])


def draw_flowchart_steps(pdf: Path, counts: dict) -> None:
    """文献式多步 CONSORT：短标签、无脚注、统一行高、Exclude 对齐。"""
    family = _setup_times()
    pdf = Path(pdf)
    pdf.parent.mkdir(parents=True, exist_ok=True)
    steps = list(counts.get("steps") or [])
    if len(steps) < 2:
        raise ValueError("draw_flowchart_steps needs counts['steps'] with >=2 entries")

    if (
        len(steps) >= 2
        and int(steps[-1].get("n") or 0) == int(steps[-2].get("n") or -1)
        and steps[-1].get("exclude_label") is None
        and str(steps[-1].get("label") or "").strip().lower() in ("included", "include")
    ):
        steps = steps[:-1]
        steps[-1] = dict(steps[-1])
        steps[-1]["label"] = "Included"

    dead = int(counts.get("dead") or 0)
    alive = int(counts.get("alive") or 0)
    n_main = len(steps)

    # 固定几何：主列 / Exclude 同行同高；框加高给两行字留白
    bw, ex_w, bh = 4.50, 3.15, 1.32
    cx, ex_x = 3.25, 7.05
    row = 1.62
    fork_gap = 0.48
    oh = 1.18
    top_pad, bot_pad = 0.28, 0.22
    top = top_pad + (n_main - 1) * row + bh + fork_gap + oh + bot_pad
    fig, ax = plt.subplots(figsize=(8.6, max(9.2, top * 0.98)))
    ax.set_xlim(0.15, 10.5)
    ax.set_ylim(0, top)
    ax.axis("off")

    y = top - top_pad - bh
    y_incl = y
    for i, st in enumerate(steps):
        lab = str(st.get("label") or f"Step {i+1}").strip()
        if "\n" in lab:
            lab = lab.split("\n")[0].strip()
        n = int(st.get("n") or 0)
        is_last = i == n_main - 1
        _box(
            ax, (cx - bw / 2, y), bw, bh,
            f"{lab}\nn = {_fmt(n)}",
            fontsize=10.5 if (i == 0 or is_last) else 10,
            fw="bold",
            fc="#EEF5FB" if is_last else "#FFFFFF",
            family=family,
        )
        excl_lab = st.get("exclude_label")
        excl_n = st.get("exclude_n")
        if excl_lab is not None and excl_n is not None:
            reason = str(excl_lab).replace("\n", " ").strip()
            excl_txt = f"Exclude:\n{reason}\n(n = {_fmt(int(excl_n))})"
            _box(ax, (ex_x, y), ex_w, bh, excl_txt, fontsize=9, fw="normal", fc="#F5F5F5", family=family)
            ax.annotate(
                "",
                xy=(ex_x, y + bh / 2),
                xytext=(cx + bw / 2, y + bh / 2),
                arrowprops=dict(arrowstyle="-|>", color="#333333", lw=1.05, mutation_scale=10),
            )
        if not is_last:
            y_next = y - row
            _arrow(ax, cx, y, y_next + bh)
            y = y_next
        else:
            y_incl = y

    ow = 2.40
    gap_x = 0.45
    left_x = cx - gap_x / 2 - ow
    right_x = cx + gap_x / 2
    y_out = bot_pad
    stem_top = y_incl
    stem_bot = y_out + oh + 0.10
    ax.plot([cx, cx], [stem_top, stem_bot], color="#222222", lw=1.15)
    ax.plot([left_x + ow / 2, right_x + ow / 2], [stem_bot, stem_bot], color="#222222", lw=1.15)
    ax.annotate("", xy=(left_x + ow / 2, y_out + oh), xytext=(left_x + ow / 2, stem_bot),
                arrowprops=dict(arrowstyle="-|>", color="#222222", lw=1.15, mutation_scale=10))
    ax.annotate("", xy=(right_x + ow / 2, y_out + oh), xytext=(right_x + ow / 2, stem_bot),
                arrowprops=dict(arrowstyle="-|>", color="#222222", lw=1.15, mutation_scale=10))
    _box(ax, (left_x, y_out), ow, oh, f"Expired\n(n = {_fmt(dead)})", fontsize=10.5, fw="bold", fc="#FFF1F1", family=family)
    _box(ax, (right_x, y_out), ow, oh, f"Alive\n(n = {_fmt(alive)})", fontsize=10.5, fw="bold", fc="#F1FFF4", family=family)

    fig.savefig(pdf, dpi=300, bbox_inches="tight", pad_inches=0.10)
    dbg_png = pdf.with_suffix(".png")
    fig.savefig(dbg_png, dpi=220, bbox_inches="tight", pad_inches=0.10)
    plt.close(fig)
    print(f"font={family}")
    print(f"wrote {pdf}")
    print(f"wrote {dbg_png}")


def draw_flowchart(pdf: Path, counts: dict) -> None:
    """若 counts 含 steps（文献多步纳排）走 steps 版；否则走旧两框缺失模板。"""
    if counts.get("steps"):
        draw_flowchart_steps(pdf, counts)
        return

    family = _setup_times()
    pdf = Path(pdf)
    pdf.parent.mkdir(parents=True, exist_ok=True)

    disease = counts.get("disease_label", "AKI")
    db = counts.get("db_label", "MIMIC-IV")
    miss_pct = int(counts.get("patient_miss_pct", 50))
    # 禁止把 patient_missing_threshold=1.0 画成「>100%」(无意义且与文献 >30% 冲突)
    if miss_pct >= 100:
        miss_pct = 30
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

    # 无图底脚注（交付口径：细节进 Methods / image_information）
    fig.savefig(pdf, dpi=300, bbox_inches="tight", pad_inches=0.12)
    fig.savefig(pdf.with_suffix(".png"), dpi=220, bbox_inches="tight", pad_inches=0.12)
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
    """WSL /mnt/g/... → G:/... only when Windows path is readable (torch python).

    Linux python3 must keep /mnt/g/... — G:/ is not mounted in WSL userspace.
    """
    s = str(p).replace("\\", "/")
    raw = Path(s)
    if raw.exists():
        return raw
    if s.startswith("/mnt/") and len(s.split("/")) >= 4:
        drive = s.split("/")[2].upper()
        rest = "/".join(s.split("/")[3:])
        win = Path(f"{drive}:/{rest}")
        if win.exists():
            return win
    return raw


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

    miss_pct = 30  # 文献默认 >30% missing；禁止把 pipeline threshold=1.0 画成 >100%
    cfg = proj / "config_two_stage_transformer_stroke_task_parallel.R"
    cfg_txt = ""
    if cfg.is_file():
        import re

        cfg_txt = cfg.read_text(encoding="utf-8", errors="ignore")
        m = re.search(r"patient_missing_threshold\s*=\s*([0-9.]+)", cfg_txt)
        if m:
            thr = float(m.group(1))
            cand = int(round(thr * 100)) if thr <= 1 else int(thr)
            # threshold=1.0 表示「流水线不再剔人」(纳排已在提取完成)，图面仍按文献 30%
            if 0 < cand < 100:
                miss_pct = cand

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
    # 若 JSON 未给 steps，尝试从 config$attrition$steps 解析（R list 文本）
    if not out.get("steps") and cfg_txt:
        import re

        block = re.search(r"attrition\s*=\s*list\((.*?)\)\s*,\s*\n\s*methods", cfg_txt, re.S)
        if block:
            steps_raw = re.findall(
                r"list\(\s*label\s*=\s*\"([^\"]+)\"\s*,\s*n\s*=\s*([0-9]+)L?\s*\)",
                block.group(1),
            )
            if len(steps_raw) >= 2:
                parsed = []
                prev_n = None
                for lab, n_s in steps_raw:
                    n = int(n_s)
                    excl_n = None if prev_n is None else max(prev_n - n, 0)
                    excl_lab = None
                    low = lab.lower()
                    if prev_n is not None:
                        if "age" in low or "sex" in low:
                            excl_lab = "< 18 years or\nunknown sex"
                        elif "24" in low or "icu stay" in low:
                            excl_lab = "ICU stay < 24 h"
                        elif "missing" in low or "30%" in low:
                            excl_lab = f"Records with\n> {miss_pct}% missing\n(day 1-5 proxy)"
                        elif "first" in low:
                            excl_lab = "Not first\nICU stay"
                        else:
                            excl_lab = "Excluded"
                    item = {"label": lab, "n": n}
                    if excl_lab is not None:
                        item["exclude_label"] = excl_lab
                        item["exclude_n"] = excl_n
                    parsed.append(item)
                    prev_n = n
                # 首框不带 exclude；诊断框可带「非本病」差，若 pool→disease
                if parsed:
                    out["steps"] = parsed
                    out["included"] = parsed[-1]["n"]
                    out["patient_miss_pct"] = miss_pct
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
