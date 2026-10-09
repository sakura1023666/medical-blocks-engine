#!/usr/bin/env python3
"""汇总 TST 卒中文献级图表到 summary_results/（命名与 pub 交付清单对齐）。

用法:
  python build_summary_results.py --project-root "G:/.../two_stage_transformer_40041421"
  # 或由流水线 block tst_summary_results / mode tst_summary_results 调用
"""
from __future__ import annotations

import argparse
import csv
import json
import shutil
import subprocess
import sys
from pathlib import Path

# matplotlib / PIL 延迟导入：Tables 三线表 xlsx 不依赖绘图栈
_plt = None
_Image = None


def _mpl():
    global _plt
    if _plt is None:
        import matplotlib

        matplotlib.use("Agg")
        from matplotlib import pyplot as plt

        _plt = plt
    return _plt


def _pil():
    global _Image
    if _Image is None:
        from PIL import Image

        _Image = Image
    return _Image

PROJ_CANDS = [
    Path(r"G:/02block_result/33_AKI/two_stage_transformer_40041421"),
    Path("/mnt/g/02block_result/33_AKI/two_stage_transformer_40041421"),
    Path(r"G:/02block_result/11_ischemic stroke/two_stage_transformer_40041421"),
    Path("/mnt/g/02block_result/11_ischemic stroke/two_stage_transformer_40041421"),
]
LANDMARKS = (24, 48, 72, 96, 120)
ARCH_MAP = {
    "A1_repo": "a1",
    "A2_single": "a2",
    "B_twostage": "b",
}
BASELINES = ("logistic", "xgb", "mlp", "lstm")
# 交付命名：Figure → PDF；Table → xlsx 三线表（Yang pbaf003 对齐）
DB_NAME = "MIMIC"
FONT_TNR = "Times New Roman"


def pub_strip_underscores(s: object) -> str:
    """发表图/表可见文字禁止下划线（对齐 R .pub_charvec_underscores）。"""
    t = "" if s is None else str(s)
    if "_" not in t:
        return t
    # static_Age → Age；其余 _ → 空格
    if t.lower().startswith("static_"):
        t = t[7:]
    return t.replace("_", " ").replace("  ", " ").strip()


def lit_fig(n: int | str, name: str, *, supp: bool = False) -> str:
    """主图 Figure N-DB-name；补充图 Figure SN-DB-name。"""
    if supp:
        return f"Figure S{n}-{DB_NAME}-{name}.pdf"
    return f"Figure {n}-{DB_NAME}-{name}.pdf"


def lit_tab(n: int | str, name: str, *, supp: bool = False, extra: bool = False, sci: bool = False) -> str:
    """主表/补充表/Extra → .xlsx。

    sci=True：对齐引擎 export_sci_table 命名
    ``Table N-DB. Human readable title.xlsx``（depression / AKI GPR 同款）。
    默认仍用 Yang 短横线 slug（历史 summary 脚本兼容）。
    """
    if extra:
        return f"Table Extra-{DB_NAME}-{name}.xlsx"
    if sci:
        prefix = f"Table S{n}" if supp else f"Table {n}"
        return f"{prefix}-{DB_NAME}. {name}.xlsx"
    if supp:
        return f"Table S{n}-{DB_NAME}-{name}.xlsx"
    return f"Table {n}-{DB_NAME}-{name}.xlsx"


def find_proj(explicit: str | None = None) -> Path:
    if explicit and str(explicit).strip():
        p = Path(str(explicit).strip())
        if not p.exists():
            raise SystemExit(f"project-root 不存在: {p}")
        return p
    for p in PROJ_CANDS:
        if p.exists():
            return p
    raise SystemExit(
        "未找到项目产出根；请传 --project-root（流水线应传入 config$project$output_dir）"
    )


def unit_dir(proj: Path, unit: str) -> Path | None:
    for name in (f"【success】{unit}", unit):
        d = proj / "by_unit" / name
        if d.is_dir():
            return d
    return None


def find_file(unit_path: Path, filename: str) -> Path | None:
    """优先固定相对路径，避免 G: 盘 rglob 极慢。"""
    cands = [
        unit_path / "step09_tst_train_eval" / "Tables" / filename,
        unit_path / "step11_tst_shap" / "Tables" / filename,
        unit_path / "Tables" / filename,
        unit_path / filename,
    ]
    for p in cands:
        if p.is_file():
            return p
    # 最后才浅层扫描（限深）
    try:
        for p in unit_path.glob(f"*/Tables/{filename}"):
            if p.is_file():
                return p
        for p in unit_path.glob(f"*/*/Tables/{filename}"):
            if p.is_file():
                return p
    except OSError:
        pass
    return None


def read_csv(path: Path) -> list[dict]:
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def write_csv(path: Path, rows: list[dict], fieldnames: list[str] | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    cols = fieldnames or list(dict.fromkeys(k for r in rows for k in r.keys()))
    with path.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)


def blank_pdf(path: Path, title: str, subtitle: str = "") -> None:
    """空白/占位 PDF（Fig2 / Fig9 等未复现项）。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    fig = _mpl().figure(figsize=(8.5, 11.0), dpi=150)
    fig.patch.set_facecolor("white")
    fig.text(0.5, 0.55, title, ha="center", va="center", fontsize=14, fontweight="bold")
    if subtitle:
        fig.text(0.5, 0.48, subtitle, ha="center", va="center", fontsize=10, wrap=True)
    fig.text(0.5, 0.12, "(blank placeholder)", ha="center", va="center", fontsize=9, color="#888888")
    fig.savefig(path, format="pdf")
    _mpl().close(fig)


def rows_to_pdf(path: Path, rows: list[dict], title: str, max_rows: int = 40) -> None:
    """将表格行渲染为 PDF（仅用于清单/README 等非 Tables 交付物）。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        blank_pdf(path, title, "No rows")
        return
    cols = list(dict.fromkeys(k for r in rows for k in r.keys()))
    show = rows[:max_rows]
    cell = [[str(r.get(c, ""))[:48] for c in cols] for r in show]
    n_cols = max(len(cols), 1)
    fig_w = min(18.0, max(8.5, 1.35 * n_cols))
    fig_h = min(14.0, max(4.0, 0.38 * (len(show) + 4)))
    fig, ax = _mpl().subplots(figsize=(fig_w, fig_h), dpi=150)
    ax.axis("off")
    ax.set_title(title, fontsize=11, pad=12)
    tbl = ax.table(cellText=cell, colLabels=cols, loc="center", cellLoc="left")
    tbl.auto_set_font_size(False)
    tbl.set_fontsize(7)
    tbl.scale(1.0, 1.25)
    if len(rows) > max_rows:
        fig.text(0.5, 0.02, f"... truncated {max_rows}/{len(rows)} rows", ha="center", fontsize=8)
    fig.tight_layout()
    fig.savefig(path, format="pdf")
    _mpl().close(fig)


def _cell_str(v) -> str:
    if v is None:
        return ""
    s = str(v).strip()
    if s.lower() in ("nan", "none", "na"):
        return ""
    return s


def rows_to_xlsx(
    path: Path,
    rows: list[dict],
    title: str,
    *,
    footnotes: list[str] | None = None,
    max_rows: int | None = None,
) -> None:
    """SCI 三线表 xlsx：Times New Roman；顶粗/表头下细/底粗；无竖线、无表体内横线。

    规范对齐 R/utils.R::.sci_xlsx_write_three_line_workbook。
    """
    from openpyxl import Workbook  # type: ignore
    from openpyxl.styles import Alignment, Border, Font, Side  # type: ignore
    from openpyxl.utils import get_column_letter  # type: ignore

    path = Path(path)
    if path.suffix.lower() != ".xlsx":
        path = path.with_suffix(".xlsx")
    path.parent.mkdir(parents=True, exist_ok=True)

    cols = list(dict.fromkeys(k for r in rows for k in r.keys())) if rows else ["Note"]
    show = rows if max_rows is None else rows[:max_rows]
    if not show:
        show = [{"Note": "No rows"}]
        cols = ["Note"]

    thick = Side(style="medium", color="000000")
    thin = Side(style="thin", color="000000")
    border_header = Border(top=thick, bottom=thin)
    border_last = Border(bottom=thick)
    border_foot_top = Border(top=thin)

    font_title = Font(name=FONT_TNR, size=12, bold=True)
    font_hdr = Font(name=FONT_TNR, size=12, bold=True)
    font_body = Font(name=FONT_TNR, size=12)
    align_c = Alignment(horizontal="center", vertical="center", wrap_text=True)
    align_l = Alignment(horizontal="left", vertical="center", wrap_text=True)

    wb = Workbook()
    ws = wb.active
    ws.title = "Table"
    ws.sheet_view.showGridLines = False

    nc = len(cols)
    r0 = 1
    if title and str(title).strip():
        ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=nc)
        c = ws.cell(1, 1, str(title).strip())
        c.font = font_title
        c.alignment = align_c
        r0 = 2

    # header row (col names as cells)
    for j, col in enumerate(cols, start=1):
        cell = ws.cell(r0, j, pub_strip_underscores(_cell_str(col)))
        cell.font = font_hdr
        cell.alignment = align_c
        cell.border = border_header

    # body
    for i, row in enumerate(show):
        excel_r = r0 + 1 + i
        is_last = i == len(show) - 1
        for j, col in enumerate(cols, start=1):
            cell = ws.cell(excel_r, j, pub_strip_underscores(_cell_str(row.get(col, ""))))
            cell.font = font_body
            cell.alignment = align_l if j == 1 else align_c
            if is_last:
                cell.border = border_last

    if footnotes:
        feet = [pub_strip_underscores(f).strip() for f in footnotes if str(f).strip()]
        last_data = r0 + len(show)
        for k, note in enumerate(feet):
            fr = last_data + 1 + k
            ws.merge_cells(start_row=fr, start_column=1, end_row=fr, end_column=nc)
            cell = ws.cell(fr, 1, note)
            cell.font = font_body
            cell.alignment = align_l
            if k == 0:
                cell.border = border_foot_top

    # auto width (cap)
    for j, col in enumerate(cols, start=1):
        maxlen = len(pub_strip_underscores(_cell_str(col)))
        for row in show:
            maxlen = max(maxlen, min(len(pub_strip_underscores(_cell_str(row.get(col, "")))), 48))
        ws.column_dimensions[get_column_letter(j)].width = min(max(maxlen + 2, 10), 42)
    if title:
        ws.row_dimensions[1].height = 22

    # title also strip
    if title and str(title).strip():
        ws.cell(1, 1).value = pub_strip_underscores(str(title).strip())

    wb.save(path)


def blank_xlsx(path: Path, title: str, note: str = "") -> None:
    rows = [{"Note": note or "Placeholder"}]
    rows_to_xlsx(path, rows, title)


def csv_file_to_xlsx(
    csv_path: Path,
    xlsx: Path,
    title: str,
    *,
    footnotes: list[str] | None = None,
    max_rows: int | None = None,
) -> None:
    rows = read_csv(csv_path) if csv_path.exists() else []
    rows_to_xlsx(xlsx, rows, title, footnotes=footnotes, max_rows=max_rows)


def csv_file_to_pdf(csv_path: Path, pdf: Path, title: str, max_rows: int = 40) -> None:
    """by_landmark 等中间产物仍可写 PDF；主交付 Tables/ 请用 csv_file_to_xlsx。"""
    rows = read_csv(csv_path) if csv_path.exists() else []
    rows_to_pdf(pdf, rows, title, max_rows=max_rows)


def png_to_pdf(png: Path, pdf: Path) -> None:
    pdf.parent.mkdir(parents=True, exist_ok=True)
    img = _pil().open(png).convert("RGB")
    img.save(pdf, "PDF", resolution=150.0)


# 与 python/two_stage_transformer/shap_plot.py SHAP_HEATMAP_LABELS 保持一致
_SHAP_LBL = {
    "y_hour": "Hour (0–23)",
    "x_features": "Daily activated features",
    "cbar": "Relative strength (Green → Yellow → Red)",
    "interpret": (
        "Which features the model considers more important at which hours on that day "
        "(mean |SHAP| over explained patients; global color scale)."
    ),
    "title_day": "Day-{c} visualization results",
    "title_fig2": "Daily feature visualization heatmaps (SHAP)",
}


def _shap_hour_yticks(H: int) -> tuple[list[float], list[str]]:
    step = 2 if H >= 24 else 1
    ticks = list(range(0, H, step))
    if ticks[-1] != H - 1:
        ticks.append(H - 1)
    return [t + 0.5 for t in ticks], [str(t) for t in ticks]


def _render_shap_panel_from_npz(
    d,
    display: list[str],
    *,
    day: int,
    layout: str,
    n_hours: int,
    ax,
    n_top: int = 24,
):
    """在 ax 上绘制单日 SHAP Hour×Feature 热图。"""
    import numpy as np

    key = f"day{day}"
    if key not in d:
        ax.axis("off")
        return None
    mat = np.asarray(d[key], dtype=np.float64)
    if mat.ndim != 2 or mat.shape[1] < 2:
        ax.axis("off")
        return None
    is_hour = layout == "hour_feature" or (n_hours > 1 and mat.shape[0] == n_hours)
    order = np.argsort(mat.mean(0))[::-1][: (n_top if is_hour else 12)]
    show = mat[:, order]
    vmax = float(np.percentile(show, 99)) if show.size else 1.0
    show_n = np.clip(show / max(vmax, 1e-12), 0.0, 1.0)
    labels = [display[j] for j in order]
    im = ax.imshow(
        show_n,
        aspect="auto",
        cmap="RdYlGn_r",
        vmin=0,
        vmax=1,
        interpolation="nearest",
    )
    ax.set_title(_SHAP_LBL["title_day"].format(c=day), fontsize=10, loc="center", pad=4)
    if is_hour:
        H = show_n.shape[0]
        yticks, ylabels = _shap_hour_yticks(H)
        ax.set_yticks(yticks)
        ax.set_yticklabels(ylabels, fontsize=7)
        ax.set_ylabel(_SHAP_LBL["y_hour"], fontsize=8)
    else:
        ax.set_ylabel("Sample", fontsize=8)
        n_s = show_n.shape[0]
        ax.set_yticks([0, n_s // 2, n_s - 1])
        ax.set_yticklabels(["1", str(n_s // 2 + 1), str(n_s)], fontsize=7)
    ax.set_xticks(range(len(labels)))
    ax.set_xticklabels(labels, rotation=28, ha="right", fontsize=6.5)
    return im, labels


def render_shap_day_pdf(npz: Path, day: int, out_pdf: Path) -> bool:
    """由 npz 重绘 Supplementary Figure S{day}（含完整轴/色标/脚注）。"""
    import numpy as np

    if not npz.exists():
        return False
    d = np.load(npz, allow_pickle=True)
    display = [pub_strip_underscores(x) for x in d["feature_display"]]
    layout = str(d["heatmap_layout"]) if "heatmap_layout" in d else "sample_feature"
    n_hours = int(d["n_hours"]) if "n_hours" in d else 0
    fig, ax = _mpl().subplots(figsize=(14.0, 6.0), dpi=160)
    res = _render_shap_panel_from_npz(d, display, day=day, layout=layout, n_hours=n_hours, ax=ax)
    if res is None:
        _mpl().close(fig)
        return False
    im, labels = res
    is_hour = layout == "hour_feature" or (n_hours > 1 and int(d[f"day{day}"].shape[0]) == n_hours)
    cbar = fig.colorbar(im, ax=ax, fraction=0.025, pad=0.02)
    cbar.set_label(_SHAP_LBL["cbar"], fontsize=8)
    top_names = ", ".join(labels[:6])
    # 加大底边：斜向 tick + xlabel + 脚注分层，禁止叠字
    fig.subplots_adjust(left=0.08, right=0.92, top=0.92, bottom=0.22)
    if is_hour:
        ax.set_xlabel(_SHAP_LBL["x_features"], fontsize=9, labelpad=6)
    fig.text(
        0.5,
        0.02,
        f"Prominently activated features: {top_names}\n{_SHAP_LBL['interpret']}",
        ha="center",
        va="bottom",
        fontsize=7.5,
        style="italic",
        color="#1a237e",
    )
    out_pdf.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_pdf, format="pdf")
    _mpl().close(fig)
    return True


def collage_shap_pdf(day_pngs: list[Path], out_pdf: Path, title: str) -> None:
    """优先用 npz 紧凑排版；否则退回 5 行直排 PNG（避免 2×3 大空白）。"""
    # 尝试同目录 / 上级 step11 的 heatmaps
    npz_cands: list[Path] = []
    for p in day_pngs:
        if not p:
            continue
        npz_cands.append(p.parent / "shap_b_heatmaps.npz")
        npz_cands.append(p.parent / "shap_a1_heatmaps.npz")
    npz = next((p for p in npz_cands if p.exists()), None)
    if npz is not None:
        try:
            import numpy as np

            d = np.load(npz, allow_pickle=True)
            display = [pub_strip_underscores(x) for x in d["feature_display"]]
            layout = str(d["heatmap_layout"]) if "heatmap_layout" in d else "sample_feature"
            n_hours = int(d["n_hours"]) if "n_hours" in d else 0
            # 加高画布 + 加大 bottom：斜向 tick 占约 0.10 图高，脚注单独落在更下方
            fig, axes = _mpl().subplots(5, 1, figsize=(11.0, 18.5), dpi=160)
            fig.subplots_adjust(left=0.11, right=0.84, top=0.958, bottom=0.22, hspace=0.42)
            fig.suptitle(_SHAP_LBL["title_fig2"], fontsize=12, y=0.988)
            last_im = None
            last_labels: list[str] = []
            for i, ax in enumerate(axes):
                day = i + 1
                res = _render_shap_panel_from_npz(
                    d, display, day=day, layout=layout, n_hours=n_hours, ax=ax
                )
                if res is None:
                    continue
                last_im, last_labels = res
                is_hour = layout == "hour_feature" or (n_hours > 1)
                # 末行不写 xlabel；斜标签下方空白留给蓝色脚注
                if is_hour:
                    ax.set_xlabel("")
                if i == 4:
                    ax.tick_params(axis="x", pad=1)
            if last_im is not None:
                cax = fig.add_axes([0.86, 0.26, 0.02, 0.62])
                cb = fig.colorbar(last_im, cax=cax)
                cb.set_label(_SHAP_LBL["cbar"], fontsize=8)
            if last_labels:
                fig.text(
                    0.5,
                    0.018,
                    f"Daily activated features — prominently (Day 5): {', '.join(last_labels[:6])}\n"
                    f"{_SHAP_LBL['interpret']}",
                    ha="center",
                    va="bottom",
                    fontsize=7.5,
                    style="italic",
                    color="#1a237e",
                )
            out_pdf.parent.mkdir(parents=True, exist_ok=True)
            fig.savefig(out_pdf, format="pdf")
            _mpl().close(fig)
            return
        except Exception as e:
            print(f"[collage_shap] npz layout failed: {e}; fallback PNG stack")

    imgs = [_pil().open(p).convert("RGB") for p in day_pngs if p and p.exists()]
    if not imgs:
        blank_pdf(out_pdf, title, "No SHAP panels")
        return
    # 竖向紧凑拼接，去掉 2×3 右下空白
    w = max(im.width for im in imgs)
    gap = 8
    h = sum(im.height for im in imgs) + gap * (len(imgs) - 1)
    canvas = _pil().new("RGB", (w, h), (255, 255, 255))
    y = 0
    for im in imgs:
        if im.width != w:
            im = im.resize((w, int(im.height * w / im.width)))
        canvas.paste(im, (0, y))
        y += im.height + gap
    out_pdf.parent.mkdir(parents=True, exist_ok=True)
    tmp = out_pdf.with_suffix(".tmp.png")
    canvas.save(tmp, dpi=(160, 160))
    png_to_pdf(tmp, out_pdf)
    try:
        tmp.unlink()
    except OSError:
        pass


def purge_non_pdf(folder: Path) -> None:
    purge_keep_ext(folder, {".pdf"})


def purge_keep_ext(folder: Path, keep: set[str]) -> None:
    if not folder.is_dir():
        return
    keep_l = {e.lower() if e.startswith(".") else f".{e.lower()}" for e in keep}
    for p in folder.rglob("*"):
        if p.is_file() and p.suffix.lower() not in keep_l:
            try:
                p.unlink()
            except OSError:
                pass


def purge_to_whitelist(folder: Path, allowed_names: set[str]) -> list[str]:
    """Delete any file in folder (non-recursive) not in allowed basename set."""
    removed: list[str] = []
    if not folder.is_dir():
        return removed
    for p in folder.iterdir():
        if not p.is_file():
            continue
        if p.name not in allowed_names:
            try:
                p.unlink()
                removed.append(p.name)
            except OSError:
                pass
    return removed


# 汇总 Figures/Tables 白名单由 lit_fig / lit_tab 在 purge 时动态生成（见 build() 末尾）


def plot_calibration(csv_path: Path, pdf: Path, title: str) -> None:
    rows = read_csv(csv_path)
    if not rows:
        return
    pred = [float(r["predicted"]) for r in rows]
    obs = [float(r["observed"]) for r in rows]
    fig, ax = _mpl().subplots(figsize=(5.2, 5.0), dpi=150)
    ax.plot([0, 1], [0, 1], "k:", lw=1, label="Ideal")
    ax.plot(pred, obs, "o-", color="#1f4e79", lw=1.8, markersize=5, label="Model")
    ax.set_xlabel("Predicted probability")
    ax.set_ylabel("Observed frequency")
    ax.set_title(title)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.legend(frameon=False, loc="upper left")
    ax.set_aspect("equal", adjustable="box")
    fig.tight_layout()
    pdf.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(pdf)
    _mpl().close(fig)


def plot_dca(csv_path: Path, pdf: Path, title: str) -> None:
    rows = read_csv(csv_path)
    if not rows:
        return
    thr = [float(r["threshold"]) for r in rows]
    nb_m = [float(r["net_benefit_model"]) for r in rows]
    nb_a = [float(r["net_benefit_treat_all"]) for r in rows]
    nb_n = [float(r.get("net_benefit_treat_none", 0) or 0) for r in rows]
    fig, ax = _mpl().subplots(figsize=(6.0, 4.5), dpi=150)
    ax.plot(thr, nb_m, color="#1f4e79", lw=2.0, label="Model")
    ax.plot(thr, nb_a, color="#c45911", lw=1.5, ls="--", label="Treat all")
    ax.plot(thr, nb_n, color="#595959", lw=1.2, ls=":", label="Treat none")
    ax.set_xlabel("Threshold probability")
    ax.set_ylabel("Net benefit")
    ax.set_title(title)
    ax.legend(frameon=False)
    fig.tight_layout()
    pdf.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(pdf)
    _mpl().close(fig)


def collage_shap(day_pngs: list[Path], out_png: Path, title: str) -> None:
    collage_shap_pdf(day_pngs, out_png.with_suffix(".pdf") if out_png.suffix.lower() != ".pdf" else out_png, title)


def _clear_dir(path: Path) -> None:
    if not path.exists():
        return
    try:
        shutil.rmtree(path)
        return
    except OSError:
        pass
    # Windows 偶发文件占用：逐文件删，删不掉则跳过（后续 overwrite）
    for p in sorted(path.rglob("*"), reverse=True):
        try:
            if p.is_file() or p.is_symlink():
                p.unlink()
            elif p.is_dir():
                p.rmdir()
        except OSError:
            continue



def _to_win_path(path: Path) -> str:
    s = str(path)
    if s.startswith("/mnt/"):
        parts = s.split("/")
        if len(parts) >= 3:
            return parts[2].upper() + ":/" + "/".join(parts[3:])
    return s


def _build_score_map_csv(proj: Path, score_name: str) -> Path:
    """写出 stay_id,<score> 映射，供 Fig3 / Table2 对照。"""
    map_csv = proj / f"_tmp_{score_name.lower()}_by_stay.csv"
    if map_csv.exists() and map_csv.stat().st_size > 20:
        return map_csv

    # 1) shared cohort checkpoint（已含 APSIII/SOFA/OASIS 等）
    ck = proj / "checkpoints/_shared/main/tst_split.rds"
    if not ck.exists():
        ck = proj / "checkpoints/_shared/main/tst_cohort.rds"
    if ck.exists():
        r = subprocess.run(
            [
                "Rscript",
                "-e",
                (
                    "suppressPackageStartupMessages(library(data.table));"
                    f"x<-readRDS({str(ck)!r});"
                    "co<-if (!is.null(x$ctx$data$tst_cohort)) x$ctx$data$tst_cohort else x$data$tst_cohort;"
                    f"sc<-{score_name!r};"
                    "if (!sc %in% names(co)) quit(save='no', status=2);"
                    "id<-if ('tst_patient_id' %in% names(co)) 'tst_patient_id' else names(co)[1];"
                    f"fwrite(as.data.table(co)[!is.na(get(sc)),.(stay_id=get(id), {score_name}=get(sc))], "
                    f"{str(map_csv)!r})"
                ),
            ],
            capture_output=True,
            text=True,
        )
        if r.returncode == 0 and map_csv.exists():
            return map_csv

    # 2) baseline RData + dabiao（卒中 SAPSII 路径）
    data_dirs = [proj / "data", proj / "Data", proj / "data/eicu", proj / "Data/eicu"]
    baseline = []
    dabiao = None
    for d in data_dirs:
        baseline.extend(list(d.glob("D01_baseline*.RData")))
        if (d / "dabiao.csv").exists():
            dabiao = d / "dabiao.csv"
    if baseline and dabiao is not None:
        subprocess.run(
            [
                "Rscript",
                "-e",
                (
                    "suppressPackageStartupMessages(library(data.table));"
                    f"load({str(baseline[0])!r});"
                    f"ids<-fread({str(dabiao)!r}); df<-as.data.table(baseline);"
                    f"sc<-{score_name!r};"
                    "if (!sc %in% names(df)) quit(save='no', status=2);"
                    "id_col<-if ('stay_id' %in% names(ids)) 'stay_id' else if ('patientunitstayid' %in% names(ids)) "
                    "'patientunitstayid' else names(ids)[1];"
                    "subj<-if ('subject_id' %in% names(ids)) 'subject_id' else if ('ID' %in% names(ids)) 'ID' else NA;"
                    "if (is.na(subj) || !'ID' %in% names(df)) quit(save='no', status=3);"
                    "m<-merge(ids[,.(stay_id=get(id_col), subject_id=get(subj))], "
                    f"df[,.(subject_id=ID, {score_name}=get(sc))], by='subject_id', all.x=TRUE);"
                    f"fwrite(m[!is.na(get(sc)),.(stay_id, {score_name}=get(sc))], {str(map_csv)!r})"
                ),
            ],
            check=False,
        )
    return map_csv


def _resolve_fig3_landmark(proj: Path, preferred: int) -> int:
    """Fig3 需要 Day1–5 面板时优先选 D>=5 的成功 B unit。"""
    for lm in (preferred, 120, 96, 72, 48, 24):
        ud = unit_dir(proj, f"L{lm}_B_twostage")
        if not ud:
            continue
        meta = ud / "step09_tst_train_eval/Tables/npz/prepare_meta.json"
        model = ud / "step09_tst_train_eval/Tables/model_b.pth"
        if not model.exists():
            # try alternate nesting
            for p in ud.rglob("model_b.pth"):
                model = p
                break
        if not model.exists():
            continue
        d = None
        if meta.exists():
            try:
                import json

                d = int(json.loads(meta.read_text(encoding="utf-8"))["prepare"]["D"])
            except Exception:
                d = None
        if d is None or d >= min(5, max(1, lm // 24)):
            # prefer D>=5 when asking for Yang layout
            if preferred >= 120 or (d is not None and d >= 5) or lm == preferred:
                if d is not None and d >= 5:
                    return lm
    # fallback: any successful B with largest D
    best_lm, best_d = preferred, 0
    for lm in (120, 96, 72, 48, 24):
        ud = unit_dir(proj, f"L{lm}_B_twostage")
        if not ud:
            continue
        meta = next(ud.rglob("prepare_meta.json"), None)
        if meta and meta.exists():
            try:
                import json

                d = int(json.loads(meta.read_text(encoding="utf-8"))["prepare"]["D"])
                if d > best_d:
                    best_lm, best_d = lm, d
            except Exception:
                pass
    return int(best_lm)


def _resolve_torch_python() -> str | None:
    import os
    import sys as _sys

    if str(_sys.executable).lower().endswith("python.exe") and "torch" in str(
        _sys.executable
    ).lower().replace("\\", "/"):
        return str(_sys.executable)
    for p in (
        Path("/mnt/c/ProgramData/Miniconda3/envs/torch/python.exe"),
        Path("/mnt/c/ProgramData/miniconda3/envs/torch/python.exe"),
        Path(r"C:/ProgramData/Miniconda3/envs/torch/python.exe"),
        Path(os.environ.get("PYTHON", "")),
    ):
        if not p or not str(p):
            continue
        win = _to_win_path(p) if str(p).startswith("/mnt/") else str(p)
        if Path(win).exists() or p.exists():
            return win
    return None


def _run_torch_script(script: Path, args: list[str], *, timeout: int = 600) -> subprocess.CompletedProcess | None:
    import os

    torch_py = _resolve_torch_python()
    if torch_py is None or not script.exists():
        return None
    cmd = [torch_py, _to_win_path(script), *args]
    env = os.environ.copy()
    env["KMP_DUPLICATE_LIB_OK"] = "TRUE"
    env["PYTHONUTF8"] = "1"
    env["PYTHONIOENCODING"] = "utf-8"
    return subprocess.run(
        cmd,
        env=env,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
    )


def _find_table1_src(proj: Path) -> Path | None:
    tab_dir = proj / "_shared/step06_baseline_binary/Tables"
    if not tab_dir.is_dir():
        return None
    hits = sorted(tab_dir.glob("Table 1-MIMIC*.xlsx"))
    return hits[0] if hits else None


def _read_xlsx_rows_via_zip(src: Path) -> list[list[str]]:
    """Read sheet cells without openpyxl drawings (broken openxlsx often misses drawing1.xml)."""
    import zipfile
    from xml.etree import ElementTree as ET

    ns = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
    with zipfile.ZipFile(src) as z:
        texts: list[str] = []
        if "xl/sharedStrings.xml" in z.namelist():
            ss = ET.fromstring(z.read("xl/sharedStrings.xml"))
            for si in ss.findall(f"{ns}si"):
                texts.append("".join(n.text or "" for n in si.iter(f"{ns}t")))
        sheet = ET.fromstring(z.read("xl/worksheets/sheet1.xml"))
        # column letters A..Z enough for Table1
        def col_idx(ref: str) -> int:
            letters = "".join(ch for ch in ref if ch.isalpha())
            n = 0
            for ch in letters:
                n = n * 26 + (ord(ch.upper()) - 64)
            return n - 1

        rows_map: dict[int, dict[int, str]] = {}
        max_c = 0
        for row in sheet.findall(f"{ns}sheetData/{ns}row"):
            r_i = int(row.get("r", "0"))
            cells: dict[int, str] = {}
            for c in row.findall(f"{ns}c"):
                ref = c.get("r", "A1")
                j = col_idx(ref)
                max_c = max(max_c, j)
                t = c.get("t")
                v = c.find(f"{ns}v")
                if v is None or v.text is None:
                    val = ""
                elif t == "s":
                    val = texts[int(v.text)]
                else:
                    val = v.text
                cells[j] = val
            rows_map[r_i] = cells
        if not rows_map:
            return []
        out: list[list[str]] = []
        for r_i in range(1, max(rows_map) + 1):
            cells = rows_map.get(r_i, {})
            out.append([cells.get(j, "") for j in range(max_c + 1)])
        return out


def _fix_table1_copy(src: Path, dst: Path) -> None:
    """Preserve export_sci_table xlsx; only patch outcome labels in sharedStrings.

    Do NOT rebuild with openpyxl — that drops the engine SCI 三线表 styles
    (depression / incidence Table 1 naming & formatting).
    """
    import zipfile

    replacements = {
        b"No AKI TwoStageTransformer": b"Survived (discharge alive)",
        b"No IschemicStroke TwoStageTransformer": b"Survived (discharge alive)",
        b"No TBI TwoStageTransformer": b"Survived (discharge alive)",
        b"No Osteoporosis TwoStageTransformer": b"Survived (discharge alive)",
        b"AKI TwoStageTransformer": b"In-hospital death",
        b"IschemicStroke TwoStageTransformer": b"In-hospital death",
        b"TBI TwoStageTransformer": b"In-hospital death",
        b"Osteoporosis TwoStageTransformer": b"In-hospital death",
        b"Baseline characteristics of AKI TwoStageTransformer": b"Baseline characteristics of AKI in-hospital mortality",
        b"Baseline characteristics of IschemicStroke TwoStageTransformer": b"Baseline characteristics of ischemic stroke in-hospital mortality",
        b"Baseline characteristics of TBI TwoStageTransformer": b"Baseline characteristics of TBI in-hospital mortality",
        b"Baseline characteristics of Osteoporosis TwoStageTransformer": b"Baseline characteristics of osteoporosis in-hospital mortality",
    }
    dst.parent.mkdir(parents=True, exist_ok=True)
    # Order matters: replace longer/more-specific keys first
    keys = sorted(replacements.keys(), key=len, reverse=True)
    with zipfile.ZipFile(src, "r") as zin, zipfile.ZipFile(dst, "w") as zout:
        for item in zin.infolist():
            blob = zin.read(item.filename)
            if item.filename.endswith(".xml"):
                for old in keys:
                    blob = blob.replace(old, replacements[old])
            zout.writestr(item, blob)
    print(f"[Table1] sci-copy {src.name} -> {dst.name}")


def _table1_rows_from_tex(tex: Path) -> list[list[str]]:
    import re

    txt = tex.read_text(encoding="utf-8", errors="replace")
    rows: list[list[str]] = []
    title_m = re.search(r"caption\*\{([^}]+)\}", txt)
    if title_m:
        rows.append([title_m.group(1).strip(), "", "", "", ""])
    for line in txt.splitlines():
        line = line.strip()
        if not line.endswith("\\\\") and "&" not in line:
            continue
        if line.startswith("\\") and "multicolumn" not in line and "&" not in line:
            continue
        line = line.replace("\\\\", "").strip()
        if not line or line.startswith("\\toprule") or line.startswith("\\midrule") or line.startswith("\\bottomrule"):
            continue
        # strip latex
        line = re.sub(r"\\multicolumn\{1\}\{[lc]\}\{([^}]*)\}", r"\1", line)
        line = re.sub(r"\\textbf\{([^}]*)\}", r"\1", line)
        line = line.replace("\\textless{}", "<").replace("{}", "")
        parts = [p.strip() for p in line.split("&")]
        if len(parts) >= 2:
            rows.append(parts[:5] if len(parts) >= 5 else parts + [""] * (5 - len(parts)))
    return rows


def write_yang_table3_xlsx(
    path: Path,
    *,
    model_stats: dict[str, dict[str, tuple[float, float]]],
    p_values: dict[str, float],
    title: str,
    footnotes: list[str] | None = None,
) -> None:
    """Yang Table 3 layout: rows=AUC/Accuracy/F1; cols=5 models + P-value; mean (SD)."""
    from openpyxl import Workbook
    from openpyxl.styles import Alignment, Border, Font, Side
    from openpyxl.utils import get_column_letter

    models = [
        ("Decision Tree", "Decision Tree"),
        ("XGBoost", "XGBoost"),
        ("MLP", "MLP"),
        ("LSTM", "LSTM"),
        ("Two-stage Transformer", "Two-stage Transformer"),
    ]
    metrics = [
        ("auc", "AUC", False),
        ("acc", "Accuracy (%)", True),
        ("f1", "F1-scoreᵃ", False),
    ]

    def fmt_metric(key: str, mean: float, sd: float, pct: bool) -> str:
        if mean != mean:
            return "—"
        s = 0.0 if (sd != sd or sd < 0) else float(sd)
        if pct:
            return f"{100.0 * mean:.2f} ({100.0 * s:.2f})"
        if key == "f1":
            return f"{mean:.3f} ({s:.3f})"
        # AUC 三位：0.802 vs 0.799 不能都显示成 0.80
        return f"{mean:.3f} ({s:.3f})"

    def fmt_p(p: float) -> str:
        if p != p:
            return "—"
        return "<0.001" if p < 0.001 else f"{p:.3f}"

    headers = ["Metric"] + [h for h, _ in models] + ["P-value"]
    body = []
    for key, label, pct in metrics:
        row = [label]
        for _, mk in models:
            m, s = model_stats.get(mk, {}).get(key, (float("nan"), float("nan")))
            row.append(fmt_metric(key, m, s, pct))
        row.append(fmt_p(p_values.get(key, float("nan"))))
        body.append(row)

    thick = Side(style="medium", color="000000")
    thin = Side(style="thin", color="000000")
    wb = Workbook()
    ws = wb.active
    ws.title = "Table"
    ws.sheet_view.showGridLines = False
    font_title = Font(name=FONT_TNR, size=12, bold=True)
    font_hdr = Font(name=FONT_TNR, size=11, bold=True)
    font_body = Font(name=FONT_TNR, size=11)
    align_c = Alignment(horizontal="center", vertical="center", wrap_text=True)
    align_l = Alignment(horizontal="left", vertical="center", wrap_text=True)
    nc = len(headers)
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=nc)
    c = ws.cell(1, 1, title)
    c.font = font_title
    c.alignment = align_c
    for j, h in enumerate(headers, 1):
        cell = ws.cell(2, j, h)
        cell.font = font_hdr
        cell.alignment = align_c
        cell.border = Border(top=thick, bottom=thin)
    for i, row in enumerate(body):
        er = 3 + i
        for j, val in enumerate(row, 1):
            cell = ws.cell(er, j, val)
            cell.font = font_body
            cell.alignment = align_l if j == 1 else align_c
            if i == len(body) - 1:
                cell.border = Border(bottom=thick)
    if footnotes is None:
        footnotes = [
            "ᵃ F1-score, harmonic mean of precision and recall.",
        ]
    fr0 = 3 + len(body)
    for k, note in enumerate(footnotes):
        fr = fr0 + k
        ws.merge_cells(start_row=fr, start_column=1, end_row=fr, end_column=nc)
        cell = ws.cell(fr, 1, note)
        cell.font = font_body
        cell.alignment = align_l
        if k == 0:
            cell.border = Border(top=thin)
    widths = [14, 14, 14, 12, 12, 18, 10]
    for j, w in enumerate(widths, 1):
        ws.column_dimensions[get_column_letter(j)].width = w
    ws.row_dimensions[1].height = 40
    path.parent.mkdir(parents=True, exist_ok=True)
    wb.save(path)
    print(f"[Table3] wrote {path}")


def _build_table3_from_s6(proj: Path, primary_lm: int, tables: Path) -> bool:
    """Yang Table 3：优先用 Day5 bootstrap mean(SD)+Mann–Whitney P（与 Fig S6 同口径）。

    旧口径「Day1–5 五点 Kruskal」仅 5 个观测/模型，功效极低，常出现 NS，
    不能解释为模型无差异；与文献 mean(SD) 也不一致。
    """
    import numpy as np

    tab_dir = proj / f"summary_results/by_landmark/L{primary_lm}/Tables"
    summary = tab_dir / "Table_S6_model_comparison_summary.csv"
    pfile = tab_dir / "Table_S6_model_comparison_pvalues.csv"
    s6 = tab_dir / "Table_S6_model_comparison_metrics.csv"

    order = ["Decision Tree", "XGBoost", "MLP", "LSTM", "Two-stage Transformer"]
    stats: dict[str, dict[str, tuple[float, float]]] = {}
    p_values: dict[str, float] = {"auc": float("nan"), "acc": float("nan"), "f1": float("nan")}
    source_note = ""

    if summary.exists():
        with summary.open(encoding="utf-8-sig", newline="") as f:
            for r in csv.DictReader(f):
                m = str(r.get("model", "")).strip()
                if m not in order:
                    continue
                try:
                    stats[m] = {
                        "auc": (float(r["auc_mean"]), float(r["auc_sd"])),
                        "acc": (float(r["acc_mean"]), float(r["acc_sd"])),
                        "f1": (float(r["f1_mean"]), float(r["f1_sd"])),
                    }
                except (TypeError, ValueError, KeyError):
                    continue
        source_note = "Day5 test bootstrap mean(SD); P from Mann–Whitney vs Transformer (Fig S6)"
        if pfile.exists():
            with pfile.open(encoding="utf-8-sig", newline="") as f:
                for r in csv.DictReader(f):
                    k = str(r.get("metric", "")).strip().lower()
                    try:
                        p_values[k] = float(r["pvalue"])
                    except (TypeError, ValueError, KeyError):
                        continue

    # fallback: Day1–5 across-day mean (underpowered; only if summary missing)
    if len(stats) < 3 and s6.exists():
        by_model: dict[str, dict[str, list[float]]] = {}
        with s6.open(encoding="utf-8-sig", newline="") as f:
            for r in csv.DictReader(f):
                m = str(r.get("model", "")).strip()
                if not m:
                    continue
                by_model.setdefault(m, {"auc": [], "acc": [], "f1": []})
                try:
                    by_model[m]["auc"].append(float(r["auc"]))
                    by_model[m]["acc"].append(float(r["accuracy"]))
                    by_model[m]["f1"].append(float(r["f1"]))
                except (TypeError, ValueError, KeyError):
                    continue
        for m in order:
            d = by_model.get(m, {})
            stats[m] = {}
            for k in ("auc", "acc", "f1"):
                a = np.asarray(d.get(k, []), dtype=float)
                a = a[np.isfinite(a)]
                if a.size == 0:
                    stats[m][k] = (float("nan"), float("nan"))
                elif a.size == 1:
                    stats[m][k] = (float(a[0]), 0.0)
                else:
                    stats[m][k] = (float(a.mean()), float(a.std(ddof=1)))
        source_note = "FALLBACK Day1–5 across-day mean (n=5/model; Kruskal underpowered)"
        try:
            from scipy.stats import kruskal

            for k in ("auc", "acc", "f1"):
                groups = [by_model[m][k] for m in order if m in by_model and by_model[m].get(k)]
                p_values[k] = float(kruskal(*groups).pvalue) if len(groups) >= 3 else float("nan")
        except Exception:
            pass

    if len(stats) < 3:
        return False

    title = (
        f"Table 3-{DB_NAME}. Comparative performance metrics [mean (SD)] of predictive models for "
        "in-hospital mortality: decision tree, XGBoost, Multilayer Perceptron (MLP), "
        "LSTM, and two-stage Transformer"
    )
    out = tables / lit_tab(
        3,
        "Comparative performance metrics [mean (SD)] of predictive models for in-hospital mortality",
        sci=True,
    )
    n_day5 = None
    if s6.exists():
        with s6.open(encoding="utf-8-sig", newline="") as f:
            for r in csv.DictReader(f):
                if "trans" in str(r.get("model", "")).lower() and str(r.get("day", "")).strip() in ("5", "5.0"):
                    try:
                        n_day5 = int(float(r.get("n") or 0))
                    except (TypeError, ValueError):
                        n_day5 = None
                    break
    n_txt = f"n={n_day5}" if n_day5 else "L120 test set"
    t3_feet = [
        "* F1-score, harmonic mean of precision and recall.",
        (
            "P-value is the smallest Mann–Whitney U P of Transformer versus each baseline "
            "on bootstrap distributions (not Transformer versus XGBoost alone)."
        ),
    ]
    # 内外标题一致：A1 用完整 stem（与文件名一致）
    write_yang_table3_xlsx(
        out, model_stats=stats, p_values=p_values, title=out.stem, footnotes=t3_feet
    )
    print(f"[Table3] source={source_note}")
    # 清理旧 slug 文件名
    old = tables / lit_tab(3, "Comparative_model_performance")
    if old.is_file() and old.resolve() != out.resolve():
        old.unlink(missing_ok=True)
        print(f"[Table3] removed stale {old.name}")
    return out.exists()


def _primary_database(proj: Path) -> str:
    """EICU | MIMIC from project config (default MIMIC)."""
    cfg = proj / "config_two_stage_transformer_stroke_task_parallel.R"
    if cfg.is_file():
        txt = cfg.read_text(encoding="utf-8", errors="ignore")
        if 'database = "EICU"' in txt or "database = 'EICU'" in txt:
            return "EICU"
        if "database_type = \"EICU\"" in txt or "database_type = 'EICU'" in txt:
            return "EICU"
        if 'database = "MIMIC"' in txt or "database = 'MIMIC'" in txt:
            return "MIMIC"
        if "database_type = \"MIMIC\"" in txt or "database_type = 'MIMIC'" in txt:
            return "MIMIC"
    p = str(proj).replace("\\", "/")
    if "mimic_main" in p.lower():
        return "MIMIC"
    if "eicu" in p.lower() and "mimic_main" not in p.lower():
        return "EICU"
    return "MIMIC"


def _build_eicu_external_fig(proj: Path, primary_lm: int, out_pdf: Path, *, day: int = 5) -> bool:
    repo = Path(__file__).resolve().parents[3]
    script = repo / "Blocks/71_two_stage_transformer_stroke/scripts/prepare_eicu_external_and_eval.py"
    r = _run_torch_script(
        script,
        [
            "--project-root",
            _to_win_path(proj),
            "--landmark",
            str(primary_lm),
            "--day",
            str(day),
            "--out",
            _to_win_path(out_pdf),
            "--repo",
            _to_win_path(repo),
            "--min-age",
            "18",
        ],
        timeout=1800,
    )
    if r is None:
        print("[S7 eICU] script or torch missing")
        return False
    ok = r.returncode == 0 and out_pdf.exists()
    if not ok:
        print("[S7 eICU] failed:", (r.stderr or r.stdout)[-1200:])
    else:
        print((r.stdout or "")[-500:])
    return ok


def _build_mimic_external_fig(proj: Path, primary_lm: int, out_pdf: Path, *, day: int = 5) -> bool:
    """eICU 主库 → MIMIC 外验（Fig S7）。"""
    repo = Path(__file__).resolve().parents[3]
    script = repo / "Blocks/71_two_stage_transformer_stroke/scripts/prepare_mimic_external_and_eval.py"
    r = _run_torch_script(
        script,
        [
            "--project-root",
            _to_win_path(proj),
            "--landmark",
            str(primary_lm),
            "--day",
            str(day),
            "--out",
            _to_win_path(out_pdf),
            "--repo",
            _to_win_path(repo),
            "--min-age",
            "18",
        ],
        timeout=1800,
    )
    if r is None:
        print("[S7 MIMIC] script or torch missing")
        return False
    ok = r.returncode == 0 and out_pdf.exists()
    if not ok:
        print("[S7 MIMIC] failed:", (r.stderr or r.stdout)[-1200:])
    else:
        print((r.stdout or "")[-500:])
    return ok


def _disease_label(proj: Path) -> str:
    name = ""
    cfg = proj / "config_two_stage_transformer_stroke_task_parallel.R"
    if cfg.is_file():
        name = cfg.read_text(encoding="utf-8", errors="ignore")
    p = str(proj).replace("\\", "/")
    if "42_AKI_spesis" in p or "SepsisAKI" in name:
        host = "eICU" if _primary_database(proj) == "EICU" else "MIMIC"
        return f"{host} sepsis-associated AKI ICU cohort (in-hospital mortality)"
    if "37_TBI" in p or "TBI" in name:
        return "MIMIC TBI ICU cohort (in-hospital mortality)"
    if "33_AKI" in p or ("AKI" in name and "Osteoporosis" not in name):
        return "MIMIC AKI ICU cohort (in-hospital mortality)"
    if "osteoporosis" in p.lower() or "Osteoporosis" in name:
        return "MIMIC osteoporosis ICU cohort (in-hospital mortality)"
    return "MIMIC ischemic stroke ICU cohort"


def _disease_short(proj: Path) -> str:
    lbl = _disease_label(proj)
    p = str(proj).replace("\\", "/")
    if "42_AKI_spesis" in p or "sepsis-associated AKI" in lbl.lower() or "SepsisAKI" in lbl:
        return "sepsis-associated AKI"
    if "TBI" in lbl:
        return "TBI"
    if "AKI" in lbl:
        return "AKI"
    if "osteoporosis" in lbl.lower():
        return "osteoporosis"
    return "ischemic stroke"


def _table1_title(proj: Path) -> str:
    return f"Baseline characteristics of {_disease_short(proj)} in-hospital mortality"


def _analysis_cohort_n(proj: Path) -> tuple[int, int, int]:
    """Return (n_total, n_alive, n_dead) from flowchart if available."""
    fig1_json = proj / "_shared/_tst_fig1_counts.json"
    if fig1_json.is_file():
        try:
            data = json.loads(fig1_json.read_text(encoding="utf-8"))
            n = int(data.get("included") or data.get("after_miss") or 0)
            a = int(data.get("alive") or 0)
            d = int(data.get("dead") or 0)
            if n > 0:
                return n, a, d
        except (OSError, TypeError, ValueError, json.JSONDecodeError):
            pass
    cands = [
        proj / "_shared/step06_tst_timeseries/Tables/_tst_cohort_flowchart.csv",
        proj / "_shared/step06_tst_timeseries/_tst_cohort_flowchart.csv",
        proj / "_shared/step05_tst_timeseries/Tables/_tst_cohort_flowchart.csv",
        proj / "_shared/step05_tst_timeseries/_tst_cohort_flowchart.csv",
        proj / "_shared/step03_tst_cohort/Tables/_tst_cohort_flowchart.csv",
    ]
    for path in cands:
        if not path.is_file():
            continue
        rows = read_csv(path)
        for r in reversed(rows):
            st = str(r.get("stage") or "")
            if st not in ("final_analysis_cohort_n_out", "final_cohort_n_out"):
                continue
            try:
                n = int(float(r.get("n") or 0))
                a = int(float(r.get("n_alive") or 0))
                d = int(float(r.get("n_dead") or 0))
            except (TypeError, ValueError):
                continue
            if n > 0:
                return n, a, d
    return 0, 0, 0


def _build_model_comparison_bar(proj: Path, primary_lm: int, out_pdf: Path) -> bool:
    repo = Path(__file__).resolve().parents[3]
    script = repo / "Blocks/71_two_stage_transformer_stroke/scripts/redraw_fig_s6_comparison.py"
    r = _run_torch_script(
        script,
        [
            "--project-root",
            _to_win_path(proj),
            "--landmark",
            str(primary_lm),
            "--out",
            _to_win_path(out_pdf),
        ],
        timeout=900,
    )
    if r is None:
        print("[Fig2] redraw_fig_s6_comparison.py or torch python missing")
        return False
    ok = r.returncode == 0 and out_pdf.exists()
    if not ok:
        print("[Fig2] redraw failed:", (r.stderr or r.stdout)[-800:])
    else:
        print((r.stdout or "")[-400:])
    return ok


def _build_external_validation_fig(
    proj: Path, primary_lm: int, panel: str, out_pdf: Path, *, day: int = 5
) -> bool:
    repo = Path(__file__).resolve().parents[3]
    script = repo / "Blocks/71_two_stage_transformer_stroke/scripts/redraw_fig_external_validation.py"
    r = _run_torch_script(
        script,
        [
            "--project-root",
            _to_win_path(proj),
            "--landmark",
            str(primary_lm),
            "--panel",
            panel,
            "--day",
            str(day),
            "--out",
            _to_win_path(out_pdf),
            "--repo",
            _to_win_path(repo),
        ],
        timeout=600,
    )
    if r is None:
        print(f"[Fig ext {panel}] script or torch missing")
        return False
    ok = r.returncode == 0 and out_pdf.exists()
    if not ok:
        print(f"[Fig ext {panel}] failed:", (r.stderr or r.stdout)[-800:])
    else:
        print((r.stdout or "")[-400:])
    return ok


def _build_yang_figure3(
    proj: Path,
    primary_lm: int,
    out_pdf: Path,
    score_name: str = "SAPSII",
    fig3_landmark: int | None = None,
) -> bool:
    """L{lm}_B Day1–5 ROC+CM+柱图（主文 Figure 2；Yang 原文 Fig3 布局）；对照为临床严重度分数。"""
    import os
    import subprocess

    lm = _resolve_fig3_landmark(proj, int(fig3_landmark or primary_lm))
    ud = unit_dir(proj, f"L{lm}_B_twostage")
    if not ud or not find_file(ud, "model_b.pth"):
        print(f"[fig3] missing L{lm}_B model")
        return False
    repo = Path(__file__).resolve().parents[3]
    script = repo / "Blocks/71_two_stage_transformer_stroke/scripts/redraw_fig3_sapsii.py"
    # 嵌套调用：若当前已是 torch 的 Windows python，直接用 sys.executable
    # （从 Windows python 再 spawn /mnt/c/... 会 WinError 5）
    import sys as _sys

    torch_py: str | None = None
    if str(_sys.executable).lower().endswith("python.exe") and "torch" in str(_sys.executable).lower().replace("\\", "/"):
        torch_py = str(_sys.executable)
    else:
        torch_cands = [
            Path("/mnt/c/ProgramData/Miniconda3/envs/torch/python.exe"),
            Path("/mnt/c/ProgramData/miniconda3/envs/torch/python.exe"),
            Path(r"C:/ProgramData/Miniconda3/envs/torch/python.exe"),
            Path(os.environ.get("PYTHON", "")),
        ]
        for p in torch_cands:
            if not p or not str(p):
                continue
            if p.exists() or Path(_to_win_path(p) if str(p).startswith("/mnt/") else p).exists():
                torch_py = _to_win_path(p) if str(p).startswith("/mnt/") else str(p)
                break
    if not script.exists() or torch_py is None:
        print("[fig3] redraw_fig3_sapsii.py or torch python missing")
        return False

    map_csv = _build_score_map_csv(proj, score_name)
    if not map_csv.exists():
        print(f"[fig3] score map missing for {score_name}: {map_csv}")
        return False

    # CLI 必传：WSL→Windows python.exe 时常丢 env
    cmd = [
        torch_py,
        _to_win_path(script),
        "--project-root",
        _to_win_path(proj),
        "--landmark",
        str(lm),
        "--score-name",
        score_name,
        "--score-map",
        _to_win_path(map_csv),
        "--out",
        _to_win_path(out_pdf),
        "--repo",
        _to_win_path(repo),
    ]
    env = os.environ.copy()
    env["KMP_DUPLICATE_LIB_OK"] = "TRUE"
    env["MEDICAL_BLOCKS_ROOT"] = _to_win_path(repo)
    try:
        r = subprocess.run(
            cmd,
            env=env,
            capture_output=True,
            text=True,
            timeout=600,
            cwd=_to_win_path(repo) if str(repo).startswith("/mnt/") else str(repo),
        )
        if r.returncode != 0:
            print("[fig3] redraw failed:", (r.stderr or r.stdout)[-1200:])
            return False
        print(r.stdout[-600:] if r.stdout else "")
        return out_pdf.exists() and out_pdf.stat().st_size > 20_000
    except Exception as e:
        print(f"[fig3] exception: {e}")
        return False


def build_summary_results(
    project_root: str | Path | None = None,
    primary_landmark: int = 72,
    comparator_score: str = "SAPSII",
    fig3_landmark: int | None = None,
) -> Path:
    proj = find_proj(str(project_root) if project_root is not None else None)
    primary_lm = int(primary_landmark)
    score_name = (comparator_score or "").strip()
    # 显式 comparator_score 优先；仅空串时按路径兜底（勿把 SAPSII 强改成 APSIII 除非 AKI）
    if not score_name:
        pth = str(proj).replace("\\", "/")
        if "33_AKI" in pth or "37_TBI" in pth:
            score_name = "APSIII"
        else:
            score_name = "SAPSII"
    disease_short = _disease_short(proj)
    disease_note = _disease_label(proj)
    n_cohort, n_alive, n_dead = _analysis_cohort_n(proj)
    t1_title = _table1_title(proj)
    out = proj / "summary_results"
    _clear_dir(out)
    tables = out / "Tables"
    figures = out / "Figures"
    by_lm = out / "by_landmark"
    tables.mkdir(parents=True, exist_ok=True)
    figures.mkdir(parents=True, exist_ok=True)

    manifest: list[dict] = []

    def record(kind: str, dest: Path, src: str = "") -> None:
        manifest.append(
            {
                "type": kind,
                "dest": str(dest.relative_to(out)).replace("\\", "/"),
                "source": src,
                "exists": dest.exists(),
            }
        )

    # ---- static sources handled in literature-numbered section below ----
    # (baseline / flowchart / features / external / validation)

    perf_rows: list[dict] = []
    cal_rows: list[dict] = []
    dca_rows: list[dict] = []
    shap_rows: list[dict] = []
    abl_rows: list[dict] = []

    primary_roc_png = None
    primary_shap_days: list[Path] = []

    for lm in LANDMARKS:
        lm_tab = by_lm / f"L{lm}" / "Tables"
        lm_fig = by_lm / f"L{lm}" / "Figures"
        lm_tab.mkdir(parents=True, exist_ok=True)
        lm_fig.mkdir(parents=True, exist_ok=True)

        # A1 / A2 / B
        for suffix, arch in ARCH_MAP.items():
            unit = f"L{lm}_{suffix}"
            ud = unit_dir(proj, unit)
            if not ud:
                continue
            metrics = find_file(ud, f"Table_TST_Metrics_{arch}.csv")
            if metrics:
                for r in read_csv(metrics):
                    r = dict(r)
                    r["landmark_h"] = str(lm)
                    r["unit"] = unit
                    r["model"] = arch
                    perf_rows.append(r)
                csv_file_to_pdf(metrics, lm_tab / f"Table_TST_Metrics_{arch}.pdf", f"L{lm} Metrics {arch}")

            roc = find_file(ud, f"roc_{arch}_test.png")
            if roc:
                png_to_pdf(roc, lm_fig / f"Figure_TST_ROC_{arch}.pdf")
                if lm == primary_lm and arch == "b":
                    primary_roc_png = roc

            cal = find_file(ud, "Table_TST_Calibration.csv")
            if cal:
                for r in read_csv(cal):
                    r = dict(r)
                    r["landmark_h"] = str(lm)
                    r["unit"] = unit
                    r["model"] = arch
                    cal_rows.append(r)
                csv_file_to_pdf(cal, lm_tab / f"Table_TST_Calibration_{arch}.pdf", f"L{lm} Calibration {arch}")
                plot_calibration(
                    cal,
                    lm_fig / f"Figure_TST_Calibration_{arch}.pdf",
                    f"Calibration — L{lm} {arch.upper()}",
                )

            dca = find_file(ud, "Table_TST_DCA.csv")
            if dca:
                for r in read_csv(dca):
                    r = dict(r)
                    r["landmark_h"] = str(lm)
                    r["unit"] = unit
                    r["model"] = arch
                    dca_rows.append(r)
                csv_file_to_pdf(dca, lm_tab / f"Table_TST_DCA_{arch}.pdf", f"L{lm} DCA {arch}")
                plot_dca(
                    dca,
                    lm_fig / f"Figure_TST_DCA_{arch}.pdf",
                    f"DCA — L{lm} {arch.upper()}",
                )

            shap = find_file(ud, "Table_TST_SHAP_Importance.csv")
            if shap:
                for r in read_csv(shap):
                    r = dict(r)
                    r["landmark_h"] = str(lm)
                    r["unit"] = unit
                    r["model"] = arch
                    shap_rows.append(r)
                csv_file_to_pdf(shap, lm_tab / f"Table_TST_SHAP_Importance_{arch}.pdf", f"L{lm} SHAP {arch}")

            day_pngs = []
            for d in range(1, 6):
                cand = find_file(ud, f"shap_{arch}_day{d}.png")
                if cand is None and arch in ("a1", "b"):
                    cand = find_file(ud, f"shap_b_day{d}.png")
                if cand:
                    png_to_pdf(cand, lm_fig / f"Figure_TST_SHAP_{arch}_day{d}.pdf")
                    day_pngs.append(cand)
            if day_pngs:
                collage_shap_pdf(
                    day_pngs,
                    lm_fig / f"Figure_TST_SHAP_heatmap_{arch}.pdf",
                    f"SHAP L{lm} {arch}",
                )
                if lm == primary_lm and arch == "b":
                    primary_shap_days = day_pngs

        # baselines
        for bl in BASELINES:
            unit = f"L{lm}_{bl}"
            ud = unit_dir(proj, unit)
            if not ud:
                continue
            base = find_file(ud, "Table_TST_Baselines.csv")
            if not base:
                continue
            for r in read_csv(base):
                r = dict(r)
                r["landmark_h"] = str(lm)
                r["unit"] = unit
                r["model"] = bl
                perf_rows.append(r)
            csv_file_to_pdf(base, lm_tab / f"Table_TST_Baselines_{bl}.pdf", f"L{lm} Baseline {bl}")

        # ablation
        for abl in ("mask", "structure"):
            unit = f"L{lm}_ablation_{abl}"
            ud = unit_dir(proj, unit)
            if not ud:
                continue
            abl_f = find_file(ud, "Table_TST_Ablation.csv")
            if not abl_f:
                continue
            for r in read_csv(abl_f):
                r = dict(r)
                r["landmark_h"] = str(lm)
                r["unit"] = unit
                r["ablation"] = abl
                abl_rows.append(r)
            csv_file_to_pdf(abl_f, lm_tab / f"Table_TST_Ablation_{abl}.pdf", f"L{lm} Ablation {abl}")

    # ---- Yang pbaf003：Tables/ = xlsx 三线表；Figures/ = PDF ----
    scratch = out / "_scratch"
    scratch.mkdir(parents=True, exist_ok=True)

    lit_map: list[dict] = []

    def lit(our: str, lit_id: str, caption: str, note: str = "") -> None:
        lit_map.append(
            {
                "literature_id": lit_id,
                "literature_caption": caption,
                "our_file": our,
                "exists": (out / our).exists() if our else False,
                "scene_migration_note": note,
            }
        )

    # Table 1：直接拷贝引擎 SCI 三线表（命名对齐 depression：Table 1-DB. Title.xlsx）
    t1_src = _find_table1_src(proj)
    t1_xlsx = tables / lit_tab(1, t1_title, sci=True)
    if t1_src and t1_src.exists():
        _fix_table1_copy(t1_src, t1_xlsx)
        # 去掉旧短横线命名，避免与标准 SCI 文件并存
        old_t1 = tables / lit_tab(1, "Baseline_characteristics")
        if old_t1.exists() and old_t1.resolve() != t1_xlsx.resolve():
            old_t1.unlink()
        # 清掉他病残留文件名
        for stale in tables.glob("Table 1-*.xlsx"):
            if stale.resolve() != t1_xlsx.resolve() and "Baseline characteristics" in stale.name:
                try:
                    stale.unlink()
                except OSError:
                    pass
    else:
        blank_xlsx(t1_xlsx, "Main Table 1 — Baseline characteristics", "Source xlsx missing")
    cohort_note = (
        f"终点队列 n={n_cohort:,}（时序删人后；存活 {n_alive:,} / 院内死亡 {n_dead:,}），与 Figure 1 / Table 1 一致"
        if n_cohort
        else "终点队列与 Figure 1 / Table 1 对齐"
    )
    lit(
        str(Path("Tables") / t1_xlsx.name),
        "Main Table 1",
        f"Baseline characteristics and statistical comparisons (paper: ICU sepsis; here: {disease_note}).",
        cohort_note,
    )

    # 对照分数 map 必须先于 Table2 / Fig2（否则分数列会空、列名误成 SAPSII）
    _build_score_map_csv(proj, score_name)

    # S6 日级明细（Fig S6 柱图脚本同时写出 CSV，供 Table 3 填充）
    s6_by_day: dict[str, dict] = {}
    s6_csv = by_lm / f"L{primary_lm}" / "Tables" / "Table_S6_model_comparison_metrics.csv"
    _pre_s6 = figures / lit_fig(6, "Model_comparison_bar", supp=True)
    if not s6_csv.exists():
        _build_model_comparison_bar(proj, primary_lm, _pre_s6)
    if s6_csv.exists():
        for r in read_csv(s6_csv):
            m = str(r.get("model", "")).strip().lower()
            d = str(r.get("day", "")).strip()
            s6_by_day[f"{m}|{d}"] = r

    def _s6_metric(model_label: str, day, key: str) -> str:
        r = s6_by_day.get(f"{model_label.lower()}|{day}")
        if not r:
            return ""
        v = r.get(key, "")
        try:
            return f"{float(v):.4f}"
        except (TypeError, ValueError):
            return _cell_str(v)

    # Table 2 — Yang 原文布局：行=AUC/Accuracy(%)/F1；列=Day1–5 + 对照分数；单元格 mean (SD)
    t2_title_body = (
        f"Performance comparison [mean (SD)] of the two-stage Transformer model and {score_name} "
        "in predicting in-hospital mortality across ICU days"
    )
    t2_xlsx = tables / lit_tab(2, t2_title_body, sci=True)
    t2_ok = False
    try:
        import subprocess

        script = Path(__file__).resolve().parent / "rebuild_table2_yang_layout.py"
        if script.exists():
            r = subprocess.run(
                [
                    sys.executable,
                    str(script),
                    "--project-root",
                    str(proj),
                    "--landmark",
                    str(primary_lm),
                    "--comparator-score",
                    score_name,
                    "--from-bootstrap",
                ],
                capture_output=True,
                text=True,
                timeout=900,
            )
            # rebuild 可能改写 SCI 文件名；再 glob 一次
            t2_ok = r.returncode == 0 and (
                t2_xlsx.exists()
                or any(tables.glob("Table 2-*.Performance comparison*.xlsx"))
            )
            if r.returncode != 0:
                print("[Table2] rebuild failed:", (r.stderr or r.stdout)[-500:])
            else:
                print((r.stdout or "")[-300:])
    except Exception as e:
        print(f"[Table2] exception: {e}")
    if not t2_ok:
        blank_xlsx(
            t2_xlsx,
            f"Table 2-{DB_NAME}. {t2_title_body}",
            "rebuild_table2_yang_layout.py failed",
        )
    # 清理旧 slug
    old_t2 = tables / lit_tab(2, "Daily_performance_Transformer")
    if old_t2.is_file():
        old_t2.unlink(missing_ok=True)
    lit(
        str(Path("Tables") / t2_xlsx.name),
        "Main Table 2",
        "Performance comparison of the two-stage Transformer across ICU days (paper vs APACHE II; here vs "
        + score_name
        + ").",
        f"【场景迁移】对照为 MIMIC {score_name}；布局对齐原文 Table 2；单元格 mean (SD)",
    )

    t3_ok = _build_table3_from_s6(proj, primary_lm, tables)
    t3_xlsx = tables / lit_tab(
        3,
        "Comparative performance metrics [mean (SD)] of predictive models for in-hospital mortality",
        sci=True,
    )
    if not t3_ok:
        blank_xlsx(
            t3_xlsx,
            f"Table 3-{DB_NAME}. Comparative performance metrics [mean (SD)] of predictive models for in-hospital mortality",
            "Need Table_S6_model_comparison_metrics.csv (run S6 bar first)",
        )
    lit(
        str(Path("Tables") / t3_xlsx.name),
        "Main Table 3",
        "Comparative performance metrics [mean (SD)] of DT/XGB/MLP/LSTM/Transformer (Yang Table 3 layout).",
        f"L{primary_lm} Day5 bootstrap mean(SD) + Mann–Whitney P；对齐文献 Table 3",
    )

    feat_src = proj / "_shared/step06_tst_timeseries/_tst_feature_coverage_audit.csv"
    if not feat_src.exists():
        feat_src = proj / "_shared/step06_tst_timeseries/Tables/_tst_feature_coverage_audit.csv"
    if not feat_src.exists():
        feat_src = proj / "_shared/step05_tst_timeseries/_tst_feature_coverage_audit.csv"
    if not feat_src.exists():
        feat_src = proj / "_shared/step05_tst_timeseries/Tables/_tst_feature_coverage_audit.csv"
    if not feat_src.exists():
        feat_src = proj / "_shared/step04_tst_timeseries/_tst_feature_coverage_audit.csv"
    if not feat_src.exists():
        feat_src = proj / "_shared/step04_tst_timeseries/Tables/_tst_feature_coverage_audit.csv"
    if feat_src.exists():
        feat_rows = read_csv(feat_src)
        # 对齐 AKI 定稿 Table S2：仅 Section + Feature（最终入模）
        cleaned = []
        for r in feat_rows:
            feat = str(r.get("feature") or r.get("Feature") or "").strip()
            act = str(r.get("action") or r.get("Action") or "").strip()
            if not feat or act not in ("KEPT", "KEPT_FORCE"):
                continue
            cleaned.append(
                {
                    "Section": "Dynamic (hourly)",
                    "Feature": pub_strip_underscores(feat.replace("_", " ")),
                }
            )
        n_static = 0
        for ud in (
            proj / f"by_unit/【success】L{primary_lm}_B_twostage/step09_tst_train_eval/Tables/npz/test.npz",
            proj / f"by_unit/L{primary_lm}_B_twostage/step09_tst_train_eval/Tables/npz/test.npz",
        ):
            if not ud.exists():
                continue
            try:
                import numpy as _np

                fn = [str(x) for x in _np.load(ud, allow_pickle=True)["feature_names"]]
                for name in fn:
                    if not name.lower().startswith("static_"):
                        continue
                    disp = name[len("static_"):] if name.lower().startswith("static_") else name
                    cleaned.append(
                        {
                            "Section": "Static (baseline broadcast)",
                            "Feature": pub_strip_underscores(disp.replace("_", " ")),
                        }
                    )
                    n_static += 1
                break
            except Exception:
                continue
        feat_xlsx = tables / lit_tab(2, "Features used in Transformer", supp=True, sci=True)
        # 内外标题一致；定稿：Table S2 不要脚注
        s2_title = feat_xlsx.stem
        rows_to_xlsx(
            feat_xlsx,
            cleaned,
            s2_title,
            footnotes=None,
        )
        old_feat = tables / lit_tab(1, "Features", supp=True)
        if old_feat.exists() and old_feat.resolve() != feat_xlsx.resolve():
            old_feat.unlink()
    else:
        feat_xlsx = tables / lit_tab(2, "Features used in Transformer", supp=True, sci=True)
        blank_xlsx(
            feat_xlsx,
            "Table S2. Features",
            "Source missing",
        )
    lit(
        str(Path("Tables") / feat_xlsx.name),
        "Supplementary Table 2",
        f"Features table (paper: eICU 226 features; here: MIMIC {disease_short} retained features).",
        (
            f"【场景迁移】MIMIC {disease_short} 特征清单；队列 N={n_cohort:,} 与 Table 1 一致；插补前后对照见 Table S1"
            if n_cohort
            else f"【场景迁移】MIMIC {disease_short} 特征清单；插补前后对照见 Table S1"
        ),
    )

    # Table S1：插补前后对照 —— 优先用分析队列对齐重算（正式脚本），再拷入汇总
    s1_imp_name = lit_tab(
        1,
        "Baseline characteristics before and after imputation (analysis cohort)",
        supp=True,
        sci=True,
    )
    s1_imp_dst = tables / s1_imp_name
    s1_script = Path(__file__).resolve().parent / "rebuild_imputation_table_s1.R"
    if s1_script.exists():
        import os
        import subprocess

        rscript = shutil.which("Rscript") or "Rscript"
        try:
            r = subprocess.run(
                [
                    rscript,
                    str(s1_script),
                    "--project-root",
                    str(proj),
                    "--repo",
                    str(Path(__file__).resolve().parents[3]),
                    "--copy-summary",
                    "TRUE",
                ],
                capture_output=True,
                text=True,
                timeout=600,
                env={**os.environ, "MEDICAL_BLOCKS_ROOT": str(Path(__file__).resolve().parents[3])},
            )
            if r.returncode != 0:
                print("[TableS1] rebuild failed:", (r.stderr or r.stdout)[-600:])
            else:
                print((r.stdout or "")[-300:])
        except Exception as e:
            print(f"[TableS1] rebuild exception: {e}")
    if not s1_imp_dst.exists() or s1_imp_dst.stat().st_size < 1000:
        s1_imp_cands = []
        for step in ("step04_imputation", "step05_imputation"):
            tdir = proj / "_shared" / step / "Tables"
            s1_imp_cands.extend(
                [
                    tdir / s1_imp_name,
                    tdir
                    / "Table S1-MIMIC. Baseline characteristics before and after imputation (analysis cohort).xlsx",
                    tdir
                    / "Table S1-MIMIC. Baseline characteristics before and after imputation.xlsx",
                ]
            )
        for cand in s1_imp_cands:
            if (
                cand.exists()
                and cand.stat().st_size > 1000
                and "validation set" not in cand.name.lower()
            ):
                shutil.copy2(cand, s1_imp_dst)
                break
    lit(
        str(Path("Tables") / s1_imp_name),
        "Supplementary Table 1",
        "Baseline characteristics before and after imputation (analysis cohort).",
        "分析队列对齐后的 SCI 三线表（rebuild_imputation_table_s1.R）",
    )

    fc_src = proj / "_shared/step05_tst_timeseries/_tst_cohort_flowchart.csv"
    if not fc_src.exists():
        fc_src = proj / "_shared/step05_tst_timeseries/Tables/_tst_cohort_flowchart.csv"
    if not fc_src.exists():
        fc_src = proj / "_shared/step04_tst_timeseries/Tables/_tst_cohort_flowchart.csv"
    if not fc_src.exists():
        fc_src = proj / "_shared/step03_tst_cohort/_tst_cohort_flowchart.csv"
    fig1 = figures / lit_fig(1, "Cohort_flowchart")
    # 优先论文式 CONSORT；强制按本课题 flowchart 重绘（禁止复用他病默认人数 PNG）
    consort_script = Path(__file__).resolve().parent / "draw_fig1_consort.py"
    consort_png = fig1.with_suffix(".png")
    for stale in (fig1, consort_png):
        if stale.exists():
            try:
                stale.unlink()
            except OSError:
                pass
    if consort_script.exists():
        _run_torch_script(
            consort_script,
            ["--project-root", _to_win_path(proj), "--out", _to_win_path(fig1), "--db-name", DB_NAME],
            timeout=120,
        )
    if consort_png.exists() and consort_png.stat().st_size > 1000:
        png_to_pdf(consort_png, fig1)
    elif fig1.exists() and fig1.stat().st_size > 1000:
        pass
    elif fc_src.exists():
        csv_file_to_pdf(
            fc_src,
            fig1,
            "Main Figure 1 — Cohort screening workflow (counts table)",
        )
    else:
        blank_pdf(fig1, "Main Figure 1 — Cohort flowchart")
    fig1_note = (
        f"终点为时序删人后最终分析队列 n={n_cohort:,}（存活 {n_alive:,} / 院内死亡 {n_dead:,}），与 Table 1 一致"
        if n_cohort
        else "终点队列与 Table 1 一致"
    )
    lit(
        str(Path("Figures") / lit_fig(1, "Cohort_flowchart")),
        "Main Figure 1",
        "Participants screening workflow (paper Fig. 1).",
        fig1_note,
    )

    # Main Figure 2 — Day1–5 ROC + CM + vs severity score 柱图（Yang 主文性能总图）
    fig2_pdf = figures / lit_fig(2, "ROC_confusion_model_comparison")
    fig2_ok = _build_yang_figure3(
        proj,
        primary_lm,
        fig2_pdf,
        score_name=score_name,
        fig3_landmark=fig3_landmark,
    )
    if not fig2_ok:
        blank_pdf(
            fig2_pdf,
            "Main Figure 2 — Daily ROC / confusion matrix / Comparison of Models",
            f"need L*_B model + {score_name} map",
        )
    lit(
        str(Path("Figures") / lit_fig(2, "ROC_confusion_model_comparison")),
        "Main Figure 2",
        f"Daily ROC + confusion matrices (Day1–5) and Comparison of Models vs {score_name} (paper-style Fig. 2).",
        f"L{primary_lm}_B；对照={score_name}（原文 APACHE II）",
    )

    # Main Figure 3 — SHAP 日级热图汇总（原主文 Fig 4 / 曾误标为 Fig2）
    if primary_shap_days:
        collage_shap_pdf(
            primary_shap_days,
            figures / lit_fig(3, "SHAP_daily_heatmap"),
            f"Main Figure 3 — SHAP L{primary_lm} B",
        )
    else:
        blank_pdf(figures / lit_fig(3, "SHAP_daily_heatmap"), "Main Figure 3 — SHAP heatmap")
    lit(
        str(Path("Figures") / lit_fig(3, "SHAP_daily_heatmap")),
        "Main Figure 3",
        "Daily feature visualization heatmaps (SHAP): Hour (0–23) × activated features.",
        _SHAP_LBL["interpret"],
    )

    shap_npz: Path | None = None
    ud_primary = unit_dir(proj, f"L{primary_lm}_B_twostage")
    if ud_primary:
        shap_npz = find_file(ud_primary, "shap_b_heatmaps.npz")
        if shap_npz is None:
            cand = ud_primary / "step11_tst_shap/Tables/shap_b_heatmaps.npz"
            if cand.exists():
                shap_npz = cand

    for d in range(1, 6):
        dst = figures / lit_fig(d, f"SHAP_Day{d}", supp=True)
        ok = bool(shap_npz and shap_npz.exists() and render_shap_day_pdf(shap_npz, d, dst))
        if not ok:
            src = None
            if primary_shap_days and len(primary_shap_days) >= d:
                src = primary_shap_days[d - 1]
            elif ud_primary:
                src = find_file(ud_primary, f"shap_b_day{d}.png")
            if src and src.exists():
                png_to_pdf(src, dst)
            else:
                blank_pdf(dst, f"Supplementary Figure {d} — SHAP Day {d}")
        lit(
            str(Path("Figures") / lit_fig(d, f"SHAP_Day{d}", supp=True)),
            f"Supplementary Figure {d}",
            f"Day-{d} SHAP heatmap: Hour (0–23) × daily activated features.",
            f"L{primary_lm}_B; {_SHAP_LBL['interpret']}",
        )

    # Supplementary Figure S6 — 五模型 Day5 柱图（Transformer 应为最高）
    s6_pdf = figures / lit_fig(6, "Model_comparison_bar", supp=True)
    s6_ok = _build_model_comparison_bar(proj, primary_lm, s6_pdf)
    if not s6_ok:
        blank_pdf(s6_pdf, "Supplementary Figure 6 — Comparison of Models", "regeneration failed")
    lit(
        str(Path("Figures") / lit_fig(6, "Model_comparison_bar", supp=True)),
        "Supplementary Figure 6",
        "Model performance comparison bar chart of AUC/Accuracy/F1 at Day 5 (paper Supp. Fig. 6).",
        f"L{primary_lm}_B test 集 Day5；基线用截至 Day5 特征"
        + ("; regenerated" if s6_ok else "; blank"),
    )

    # Supplementary Figure S7 — 外验（默认 MIMIC→eICU；eICU 主库课题则 eICU→MIMIC）
    primary_db = _primary_database(proj)
    if primary_db == "EICU":
        s7_pdf = figures / lit_fig(7, "MIMIC_validation", supp=True)
        s7_ok = _build_mimic_external_fig(proj, primary_lm, s7_pdf, day=5)
        if not s7_ok:
            blank_pdf(s7_pdf, "Supplementary Figure 7 — MIMIC external validation (ROC + CM)")
        lit(
            str(Path("Figures") / lit_fig(7, "MIMIC_validation", supp=True)),
            "Supplementary Figure 7",
            "MIMIC external validation: ROC and confusion matrix (eICU-trained model).",
            f"主分析=eICU；外验=MIMIC；病种={disease_short}",
        )
    else:
        s7_pdf = figures / lit_fig(7, "eICU_validation", supp=True)
        s7_ok = _build_eicu_external_fig(proj, primary_lm, s7_pdf, day=5)
        if not s7_ok:
            blank_pdf(s7_pdf, "Supplementary Figure 7 — eICU external validation (ROC + CM)")
        lit(
            str(Path("Figures") / lit_fig(7, "eICU_validation", supp=True)),
            "Supplementary Figure 7",
            "eICU external validation: ROC and confusion matrix (MIMIC-trained model).",
            f"主分析=MIMIC；外验=eICU（若有）；病种={disease_short}",
        )

    # 清理旧版图号 / Extra 表残留
    for stale in (
        figures / lit_fig(2, "SHAP_daily_heatmap"),  # SHAP 已改到 Fig3
        figures / lit_fig(2, "Model_comparison_bar"),
        figures / lit_fig(3, "External_validation"),
        figures / lit_fig(3, "ROC_confusion_model_comparison"),  # ROC 总图已改到 Fig2
        figures / lit_fig(4, "MIMIC_validation"),
        figures / lit_fig(4, "SHAP_daily_heatmap"),
        figures / lit_fig(2, "Model_framework"),
        figures / lit_fig(6, "ROC_confusion_model_comparison", supp=True),
        figures / lit_fig("7-8", "External_validation", supp=True),
        figures / lit_fig(7, "MIMIC_validation", supp=True),
        figures / lit_fig(9, "System_integration", supp=True),
        tables / lit_tab(0, "Calibration", extra=True),
        tables / lit_tab(0, "DCA", extra=True),
        tables / lit_tab(0, "Ablation", extra=True),
    ):
        if stale.exists():
            try:
                stale.unlink()
            except OSError:
                pass

    # Extra Calibration/DCA/Ablation：用户要求不出现在汇总 Tables/
    # （by_landmark 仍保留中间产物 PDF）

    rows_to_pdf(out / "00_Literature_ID_Map.pdf", lit_map, "Literature ID ↔ file map", max_rows=80)
    rows_to_pdf(scratch / "manifest_tmp.pdf", [{"k": m.get("dest"), "src": m.get("source")} for m in manifest], "manifest")

    checklist = [
        ("Main_Figure1", str(Path("Figures") / lit_fig(1, "Cohort_flowchart"))),
        ("Main_Figure2", str(Path("Figures") / lit_fig(2, "ROC_confusion_model_comparison"))),
        ("Main_Figure3", str(Path("Figures") / lit_fig(3, "SHAP_daily_heatmap"))),
        ("Main_Table1", str(Path("Tables") / lit_tab(1, t1_title, sci=True))),
        ("Main_Table2", str(Path("Tables") / lit_tab(2, t2_title_body, sci=True))),
        (
            "Main_Table3",
            str(
                Path("Tables")
                / lit_tab(
                    3,
                    "Comparative performance metrics [mean (SD)] of predictive models for in-hospital mortality",
                    sci=True,
                )
            ),
        ),
        ("Supp_Table1", str(Path("Tables") / lit_tab(1, "Baseline characteristics before and after imputation (analysis cohort)", supp=True, sci=True))),
        ("Supp_Table2", str(Path("Tables") / lit_tab(2, "Features used in Transformer", supp=True, sci=True))),
        ("Supp_Figure1", str(Path("Figures") / lit_fig(1, "SHAP_Day1", supp=True))),
        ("Supp_Figure2", str(Path("Figures") / lit_fig(2, "SHAP_Day2", supp=True))),
        ("Supp_Figure3", str(Path("Figures") / lit_fig(3, "SHAP_Day3", supp=True))),
        ("Supp_Figure4", str(Path("Figures") / lit_fig(4, "SHAP_Day4", supp=True))),
        ("Supp_Figure5", str(Path("Figures") / lit_fig(5, "SHAP_Day5", supp=True))),
        ("Supp_Figure6", str(Path("Figures") / lit_fig(6, "Model_comparison_bar", supp=True))),
        ("Supp_Figure7", str(Path("Figures") / lit_fig(7, "eICU_validation", supp=True))),
        ("Literature_ID_Map", "00_Literature_ID_Map.pdf"),
    ]
    ck_rows = []
    for key, rel in checklist:
        p = out / rel
        ck_rows.append(
            {
                "key": key,
                "expected": rel,
                "found": p.exists(),
                "status": "PASS" if p.exists() else "MISSING",
            }
        )
    rows_to_pdf(out / "Pub_deliverables_checklist.pdf", ck_rows, "Deliverables checklist")

    # README as PDF
    readme_lines = [
        {"section": "How to use", "content": "Open 00_Literature_ID_Map.pdf for literature_id ↔ file mapping"},
        {"section": "Main Figure 1", "content": str(Path("Figures") / lit_fig(1, "Cohort_flowchart")) + (f" (n={n_cohort:,})" if n_cohort else "")},
        {"section": "Main Figure 2", "content": str(Path("Figures") / lit_fig(2, "ROC_confusion_model_comparison")) + f" (vs {score_name})"},
        {"section": "Main Figure 3", "content": str(Path("Figures") / lit_fig(3, "SHAP_daily_heatmap"))},
        {"section": "Main Table 1", "content": str(Path("Tables") / lit_tab(1, t1_title, sci=True))},
        {"section": "Main Table 2", "content": str(Path("Tables") / lit_tab(2, t2_title_body, sci=True))},
        {
            "section": "Main Table 3",
            "content": str(
                Path("Tables")
                / lit_tab(
                    3,
                    "Comparative performance metrics [mean (SD)] of predictive models for in-hospital mortality",
                    sci=True,
                )
            ),
        },
        {"section": "Supp Table 1", "content": str(Path("Tables") / lit_tab(1, "Baseline characteristics before and after imputation (analysis cohort)", supp=True, sci=True))},
        {"section": "Supp Table 2", "content": str(Path("Tables") / lit_tab(2, "Features used in Transformer", supp=True, sci=True))},
        {"section": "Supp Fig 1-5", "content": "Figures/Figure S{1-5}-MIMIC-SHAP_Day*.pdf"},
        {"section": "Supp Fig 6", "content": str(Path("Figures") / lit_fig(6, "Model_comparison_bar", supp=True)) + " (Day5 five-model bar)"},
        {"section": "Supp Fig 7", "content": str(Path("Figures") / lit_fig(7, "eICU_validation", supp=True)) + " (eICU external)"},
        {
            "section": "Locked deliverables",
            "content": "Fig1 flowchart; Fig2 ROC+CM+vs-score; Fig3 SHAP; S1–S5 SHAP days; S6 five-model bar; S7 eICU; Table1–3; Table S1 imputation; Table S2 Features (no Extra)",
        },
        {
            "section": "Format",
            "content": "Tables/=xlsx SCI three-line (Times New Roman; Table1/S1 use export_sci_table naming Table N-DB. Title.xlsx); Figures/=PDF",
        },
        {"section": "Primary landmark", "content": f"L{primary_lm}_B_twostage"},
    ]
    rows_to_pdf(
        out / "README.pdf",
        readme_lines,
        f"summary_results — {disease_short} ({primary_db} primary)",
    )

    # Tables / Figures 白名单清扫：只留锁定交付物（去掉 _tmp、png、Extra、旧图号）
    locked_figs = {
        lit_fig(1, "Cohort_flowchart"),
        lit_fig(2, "ROC_confusion_model_comparison"),
        lit_fig(3, "SHAP_daily_heatmap"),
        *[lit_fig(d, f"SHAP_Day{d}", supp=True) for d in range(1, 6)],
        lit_fig(6, "Model_comparison_bar", supp=True),
        lit_fig(7, "eICU_validation", supp=True),
    }
    locked_tabs = {
        lit_tab(1, t1_title, sci=True),
        lit_tab(2, t2_title_body, sci=True),
        lit_tab(
            3,
            "Comparative performance metrics [mean (SD)] of predictive models for in-hospital mortality",
            sci=True,
        ),
        lit_tab(1, "Baseline characteristics before and after imputation (analysis cohort)", supp=True, sci=True),
        lit_tab(2, "Features used in Transformer", supp=True, sci=True),
    }
    removed_f = purge_to_whitelist(figures, locked_figs)
    removed_t = purge_to_whitelist(tables, locked_tabs)
    if removed_f or removed_t:
        print(f"[summary_results] purged extras: figures={removed_f} tables={removed_t}")
    # by_landmark 保留中间产物 PDF + CSV（供 Table3/S6 复用），删 png 等
    purge_keep_ext(by_lm, {".pdf", ".csv", ".json", ".npz"})
    for p in out.iterdir():
        if p.is_file() and p.suffix.lower() != ".pdf":
            try:
                p.unlink()
            except OSError:
                pass
    # eICU / MIMIC 外验中间 npz 挪到 by_landmark
    for ext_name in ("eicu_external", "mimic_external"):
        ext_dir = out / ext_name
        if ext_dir.is_dir():
            dest = by_lm / f"L{primary_lm}" / ext_name
            dest.parent.mkdir(parents=True, exist_ok=True)
            if dest.exists() and dest.resolve() != ext_dir.resolve():
                try:
                    shutil.rmtree(dest)
                except OSError:
                    pass
            try:
                shutil.move(str(ext_dir), str(dest))
            except OSError:
                pass
    # remove scratch
    try:
        shutil.rmtree(scratch)
    except OSError:
        pass

    n_pass = sum(1 for r in ck_rows if r["status"] == "PASS")
    print(f"[summary_results] OK -> {out}")
    print(f"[summary_results] checklist PASS {n_pass}/{len(ck_rows)} (Tables=xlsx, Figures=PDF)")
    for r in ck_rows:
        print(f"  {r['status']}: {r['expected']}")
    return out


def refresh_summary_index_docs(
    project_root: str | Path,
    *,
    primary_landmark: int = 120,
    comparator_score: str = "APSIII",
) -> Path:
    """只重写 README.pdf / 00_Literature_ID_Map.pdf / checklist，不动已定稿表图。"""
    proj = Path(project_root)
    out = proj / "summary_results"
    tables = out / "Tables"
    figures = out / "Figures" / "pdf"
    if not figures.is_dir():
        figures = out / "Figures"
    n_cohort, n_alive, n_dead = _analysis_cohort_n(proj)
    t1_title = _table1_title(proj)
    disease_short = _disease_short(proj)
    disease_note = _disease_label(proj)
    primary_db = _primary_database(proj)
    score_name = (comparator_score or "APSIII").strip()
    primary_lm = int(primary_landmark)

    def _pick(folder: Path, prefix: str, fallback: str) -> str:
        hits = sorted(folder.glob(prefix)) if folder.is_dir() else []
        if hits:
            return hits[0].name
        return fallback

    t1_name = _pick(tables, "Table 1-*.xlsx", f"Table 1-MIMIC. {t1_title}.xlsx")
    t2_name = _pick(tables, "Table 2-*.xlsx", "Table 2-MIMIC.xlsx")
    t3_name = _pick(tables, "Table 3-*.xlsx", "Table 3-MIMIC.xlsx")
    s1_name = _pick(tables, "Table S1-*.xlsx", "Table S1-MIMIC.xlsx")
    s2_name = _pick(tables, "Table S2-*.xlsx", "Table S2-MIMIC.xlsx")
    fig1 = _pick(figures, "Figure 1-*.pdf", "Figure 1-MIMIC-Cohort_flowchart.pdf")
    fig2 = _pick(figures, "Figure 2-*.pdf", "Figure 2-MIMIC-ROC_confusion_model_comparison.pdf")
    fig3 = _pick(figures, "Figure 3-*.pdf", "Figure 3-MIMIC-SHAP_daily_heatmap.pdf")
    s7 = _pick(figures, "Figure S7-*.pdf", "Figure S7-MIMIC-eICU_validation.pdf")

    if primary_db == "EICU":
        s7_note = f"主分析=eICU；外验=MIMIC；病种={disease_short}"
        s7_cap = "MIMIC external validation: ROC and confusion matrix (eICU-trained model)."
    else:
        s7_note = f"主分析=MIMIC；外验=eICU；病种={disease_short}"
        s7_cap = "eICU external validation: ROC and confusion matrix (MIMIC-trained model)."
    cohort_note = (
        f"终点队列 n={n_cohort:,}（时序删人后；存活 {n_alive:,} / 院内死亡 {n_dead:,}），与 Figure 1 / Table 1 一致"
        if n_cohort
        else "终点队列与 Figure 1 / Table 1 对齐"
    )

    lit_map = [
        {
            "literature_id": "Main Table 1",
            "literature_caption": f"Baseline characteristics ({disease_note}).",
            "our_file": str(Path("Tables") / t1_name),
            "exists": (out / "Tables" / t1_name).exists(),
            "scene_migration_note": cohort_note,
        },
        {
            "literature_id": "Main Table 2",
            "literature_caption": f"Transformer vs {score_name} across ICU days.",
            "our_file": str(Path("Tables") / t2_name),
            "exists": (out / "Tables" / t2_name).exists(),
            "scene_migration_note": f"对照为 MIMIC {score_name}；单元格 mean (SD)",
        },
        {
            "literature_id": "Main Table 3",
            "literature_caption": "DT/XGB/MLP/LSTM/Transformer Day5 mean (SD).",
            "our_file": str(Path("Tables") / t3_name),
            "exists": (out / "Tables" / t3_name).exists(),
            "scene_migration_note": f"L{primary_lm} Day5 bootstrap；P=最小基线对照（非单独 vs XGBoost）",
        },
        {
            "literature_id": "Supplementary Table 1",
            "literature_caption": "Baseline characteristics before and after imputation (analysis cohort).",
            "our_file": str(Path("Tables") / s1_name),
            "exists": (out / "Tables" / s1_name).exists(),
            "scene_migration_note": "分析队列对齐后的 SCI 三线表",
        },
        {
            "literature_id": "Supplementary Table 2",
            "literature_caption": f"Features used in Transformer ({disease_short}).",
            "our_file": str(Path("Tables") / s2_name),
            "exists": (out / "Tables" / s2_name).exists(),
            "scene_migration_note": f"MIMIC {disease_short} 入模特征；队列 N={n_cohort:,}" if n_cohort else "",
        },
        {
            "literature_id": "Main Figure 1",
            "literature_caption": "Participants screening workflow.",
            "our_file": str(Path("Figures") / fig1),
            "exists": (figures / fig1).exists(),
            "scene_migration_note": cohort_note,
        },
        {
            "literature_id": "Main Figure 2",
            "literature_caption": f"Daily ROC + CM and vs {score_name}.",
            "our_file": str(Path("Figures") / fig2),
            "exists": (figures / fig2).exists(),
            "scene_migration_note": f"L{primary_lm}_B；对照={score_name}",
        },
        {
            "literature_id": "Main Figure 3",
            "literature_caption": "Daily SHAP heatmaps.",
            "our_file": str(Path("Figures") / fig3),
            "exists": (figures / fig3).exists(),
            "scene_migration_note": "Hour × activated features",
        },
        {
            "literature_id": "Supplementary Figure 7",
            "literature_caption": s7_cap,
            "our_file": str(Path("Figures") / s7),
            "exists": (figures / s7).exists(),
            "scene_migration_note": s7_note,
        },
    ]
    rows_to_pdf(out / "00_Literature_ID_Map.pdf", lit_map, "Literature ID ↔ file map", max_rows=80)
    readme_lines = [
        {"section": "How to use", "content": "Open 00_Literature_ID_Map.pdf for literature_id ↔ file mapping"},
        {"section": "Main Figure 1", "content": str(Path("Figures") / fig1) + (f" (n={n_cohort:,})" if n_cohort else "")},
        {"section": "Main Figure 2", "content": str(Path("Figures") / fig2) + f" (vs {score_name})"},
        {"section": "Main Figure 3", "content": str(Path("Figures") / fig3)},
        {"section": "Main Table 1", "content": str(Path("Tables") / t1_name)},
        {"section": "Main Table 2", "content": str(Path("Tables") / t2_name)},
        {"section": "Main Table 3", "content": str(Path("Tables") / t3_name)},
        {"section": "Supp Table 1", "content": str(Path("Tables") / s1_name)},
        {"section": "Supp Table 2", "content": str(Path("Tables") / s2_name)},
        {"section": "Supp Fig 1-5", "content": "Figures/Figure S{1-5}-MIMIC-SHAP_Day*.pdf"},
        {"section": "Supp Fig 6", "content": "Figures/Figure S6-MIMIC-Model_comparison_bar.pdf (Day5 five-model bar)"},
        {"section": "Supp Fig 7", "content": str(Path("Figures") / s7) + " (eICU external)" if primary_db != "EICU" else str(Path("Figures") / s7) + " (MIMIC external)"},
        {
            "section": "Locked deliverables",
            "content": "Fig1–3; S1–S5 SHAP; S6 five-model; S7 external; Table1–3; Table S1–S2 (no Table S3)",
        },
        {"section": "Primary landmark", "content": f"L{primary_lm}_B_twostage"},
        {"section": "Primary database", "content": f"{primary_db}; disease={disease_short}"},
    ]
    rows_to_pdf(
        out / "README.pdf",
        readme_lines,
        f"summary_results — {disease_short} ({primary_db} primary)",
    )
    print(f"[index-docs] n={n_cohort} db={primary_db} disease={disease_short}")
    return out


def main(argv: list[str] | None = None) -> Path:
    ap = argparse.ArgumentParser(
        description="TST summary_results 文献级汇总（Tables=xlsx 三线表；Figures=PDF）"
    )
    ap.add_argument(
        "--project-root",
        default="",
        help="研究产出根（含 by_unit/）；默认尝试常见 G:/.../two_stage_transformer_* 路径",
    )
    ap.add_argument(
        "--primary-landmark",
        type=int,
        default=72,
        help="主文 ROC/校准/DCA/SHAP 所用 landmark（小时）",
    )
    ap.add_argument(
        "--comparator-score",
        default="SAPSII",
        help="Fig2/Table2 对照分数列名（卒中 SAPSII；AKI 自动 APSIII）",
    )
    ap.add_argument(
        "--fig3-landmark",
        type=int,
        default=0,
        help="Fig2 ROC 总图所用 B unit landmark（0=自动选 D>=5；AKI 建议 120）",
    )
    ap.add_argument(
        "--index-docs-only",
        action="store_true",
        help="只刷新 README / Literature ID Map，不重跑表图",
    )
    args = ap.parse_args(argv)
    if args.index_docs_only:
        return refresh_summary_index_docs(
            args.project_root or "",
            primary_landmark=args.primary_landmark,
            comparator_score=args.comparator_score,
        )
    return build_summary_results(
        project_root=args.project_root or None,
        primary_landmark=args.primary_landmark,
        comparator_score=args.comparator_score,
        fig3_landmark=(args.fig3_landmark or None),
    )


if __name__ == "__main__":
    main()
