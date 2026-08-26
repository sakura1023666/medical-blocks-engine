#!/usr/bin/env python3
"""汇总 TST 卒中文献级图表到 summary_results/（命名与 pub 交付清单对齐）。

用法:
  python build_summary_results.py --project-root "G:/.../two_stage_transformer_40041421"
  # 或由流水线 block tst_summary_results / mode tst_summary_results 调用
"""
from __future__ import annotations

import argparse
import csv
import shutil
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


def lit_fig(n: int | str, name: str, *, supp: bool = False) -> str:
    """主图 Figure N-DB-name；补充图 Figure SN-DB-name。"""
    if supp:
        return f"Figure S{n}-{DB_NAME}-{name}.pdf"
    return f"Figure {n}-{DB_NAME}-{name}.pdf"


def lit_tab(n: int | str, name: str, *, supp: bool = False, extra: bool = False) -> str:
    """主表/补充表/Extra → .xlsx（SCI 三线表，非 matplotlib 图片 PDF）。"""
    if extra:
        return f"Table Extra-{DB_NAME}-{name}.xlsx"
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
        cell = ws.cell(r0, j, _cell_str(col).replace("_", " "))
        cell.font = font_hdr
        cell.alignment = align_c
        cell.border = border_header

    # body
    for i, row in enumerate(show):
        excel_r = r0 + 1 + i
        is_last = i == len(show) - 1
        for j, col in enumerate(cols, start=1):
            cell = ws.cell(excel_r, j, _cell_str(row.get(col, "")))
            cell.font = font_body
            cell.alignment = align_l if j == 1 else align_c
            if is_last:
                cell.border = border_last

    if footnotes:
        feet = [str(f).strip() for f in footnotes if str(f).strip()]
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
        maxlen = len(_cell_str(col))
        for row in show:
            maxlen = max(maxlen, min(len(_cell_str(row.get(col, ""))), 48))
        ws.column_dimensions[get_column_letter(j)].width = min(max(maxlen + 2, 10), 42)
    if title:
        ws.row_dimensions[1].height = 22

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
            display = [str(x) for x in d["feature_display"]]
            fig, axes = _mpl().subplots(5, 1, figsize=(10.5, 14.0), dpi=160)
            fig.subplots_adjust(left=0.08, right=0.88, top=0.97, bottom=0.04, hspace=0.28)
            last_im = None
            for i, ax in enumerate(axes):
                day = i + 1
                key = f"day{day}"
                if key not in d:
                    ax.axis("off")
                    continue
                mat = np.asarray(d[key], dtype=np.float64)
                if mat.ndim != 2 or mat.shape[0] < 2:
                    ax.axis("off")
                    continue
                order = np.argsort(mat.mean(0))[::-1][:12]
                show = mat[:, order]
                show_n = show / np.maximum(show.max(axis=0, keepdims=True), 1e-12)
                labels = [display[j] for j in order]
                last_im = ax.imshow(show_n, aspect="auto", cmap="RdYlGn_r", vmin=0, vmax=1, interpolation="nearest")
                ax.set_title(f"Day-{day}", fontsize=10, loc="left", pad=2)
                ax.set_ylabel("Sample", fontsize=8)
                n_s = show_n.shape[0]
                ax.set_yticks([0, n_s // 2, n_s - 1])
                ax.set_yticklabels(["1", str(n_s // 2 + 1), str(n_s)], fontsize=7)
                ax.set_xticks(range(len(labels)))
                ax.set_xticklabels(labels, rotation=28, ha="right", fontsize=6.5)
            if last_im is not None:
                cax = fig.add_axes([0.90, 0.15, 0.02, 0.7])
                fig.colorbar(last_im, cax=cax, label="Relative |SHAP|")
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


def _build_yang_figure3(proj: Path, primary_lm: int, out_pdf: Path) -> bool:
    """L{lm}_B Day1–5 ROC+CM+柱图（Yang Fig3）；对照为 SAPSII【场景迁移】，图面无方法学大标题。"""
    import os
    import subprocess

    ud = unit_dir(proj, f"L{primary_lm}_B_twostage")
    if not ud or not find_file(ud, "model_b.pth"):
        return False
    repo = Path(__file__).resolve().parents[3]
    script = repo / "Blocks/71_two_stage_transformer_stroke/scripts/redraw_fig3_sapsii.py"
    torch_py = Path("/mnt/c/ProgramData/miniconda3/envs/torch/python.exe")
    if not script.exists() or not torch_py.exists():
        print("[fig3] redraw_fig3_sapsii.py or torch python missing")
        return False
    # 保证 stay→SAPSII 映射存在
    map_csv = proj / "_tmp_sapsii_by_stay.csv"
    if not map_csv.exists():
        baseline = list((proj / "data").glob("D01_baseline*.RData"))
        dabiao = proj / "data/dabiao.csv"
        if baseline and dabiao.exists():
            subprocess.run(
                [
                    "Rscript",
                    "-e",
                    (
                        "suppressPackageStartupMessages(library(data.table));"
                        f"load({str(baseline[0])!r});"
                        f"ids<-fread({str(dabiao)!r}); df<-as.data.table(baseline);"
                        "m<-merge(ids[,.(stay_id,subject_id)],df[,.(subject_id=ID,SAPSII)],by='subject_id',all.x=TRUE);"
                        f"fwrite(m[!is.na(SAPSII),.(stay_id,SAPSII)],{str(map_csv)!r})"
                    ),
                ],
                check=False,
            )
    env = os.environ.copy()
    env["KMP_DUPLICATE_LIB_OK"] = "TRUE"
    env["TST_FIG3_OUT"] = _to_win_path(out_pdf)
    env["TST_FIG3_LANDMARK"] = str(primary_lm)
    try:
        r = subprocess.run(
            [str(torch_py), _to_win_path(script)],
            env=env,
            capture_output=True,
            text=True,
            timeout=600,
        )
        if r.returncode != 0:
            print("[fig3] redraw failed:", (r.stderr or r.stdout)[-800:])
            return False
        print(r.stdout[-400:] if r.stdout else "")
        return out_pdf.exists()
    except Exception as e:
        print(f"[fig3] exception: {e}")
        return False


def build_summary_results(project_root: str | Path | None = None, primary_landmark: int = 72) -> Path:
    proj = find_proj(str(project_root) if project_root is not None else None)
    primary_lm = int(primary_landmark)
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

    # Table 1：复制已有 SCI 三线表 xlsx（Times New Roman）
    t1_src = (
        proj
        / "_shared/step06_baseline_binary/Tables"
        / "Table 1-MIMIC. Baseline characteristics of IschemicStroke TwoStageTransformer.xlsx"
    )
    t1_xlsx = tables / lit_tab(1, "Baseline_characteristics")
    if t1_src.exists():
        shutil.copy2(t1_src, t1_xlsx)
    else:
        blank_xlsx(t1_xlsx, "Main Table 1 — Baseline characteristics", "Source xlsx missing")
    lit(
        str(Path("Tables") / lit_tab(1, "Baseline_characteristics")),
        "Main Table 1",
        "Baseline characteristics and statistical comparisons (paper: ICU sepsis; here: MIMIC ischemic stroke).",
        "【场景迁移】队列为 MIMIC 缺血性卒中，非 eICU 脓毒症",
    )

    # S6 日级 Acc/F1（若有）用于填充 Table 2/3
    s6_by_day: dict[str, dict] = {}
    s6_csv = by_lm / f"L{primary_lm}" / "Tables" / "Table_S6_model_comparison_metrics.csv"
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

    # Table 2 — Yang 原文布局：行=AUC/Accuracy(%)/F1；列=Day1–5 + SAPSII
    t2_xlsx = tables / lit_tab(2, "Daily_performance_Transformer")
    t2_ok = False
    try:
        import subprocess

        script = Path(__file__).resolve().parent / "rebuild_table2_yang_layout.py"
        if script.exists():
            r = subprocess.run(
                [sys.executable, str(script)],
                capture_output=True,
                text=True,
                timeout=300,
            )
            t2_ok = r.returncode == 0 and t2_xlsx.exists()
            if r.returncode != 0:
                print("[Table2] rebuild failed:", (r.stderr or r.stdout)[-500:])
            else:
                print((r.stdout or "")[-300:])
    except Exception as e:
        print(f"[Table2] exception: {e}")
    if not t2_ok:
        blank_xlsx(
            t2_xlsx,
            "Table 2. Performance comparison (Yang layout)",
            "rebuild_table2_yang_layout.py failed",
        )
    lit(
        str(Path("Tables") / lit_tab(2, "Daily_performance_Transformer")),
        "Main Table 2",
        "Performance comparison of the two-stage Transformer across ICU days (paper vs APACHE II; here vs SAPSII).",
        "【场景迁移】对照为 MIMIC SAPSII，非原文 APACHE II；布局对齐原文 Table 2",
    )

    def _auc_for(model: str, day: str | int = 5) -> str:
        cands = [
            r
            for r in perf_rows
            if str(r.get("landmark_h")) == str(primary_lm)
            and str(r.get("model", "")).lower() == model.lower()
            and str(r.get("split", "test")).lower() == "test"
            and str(r.get("day")) == str(day)
        ]
        if cands:
            return str(cands[0].get("auc") or cands[0].get("auc_test") or "")
        cands = [
            r
            for r in perf_rows
            if str(r.get("landmark_h")) == str(primary_lm)
            and str(r.get("model", "")).lower() == model.lower()
            and str(r.get("split", "test")).lower() in ("test", "")
        ]
        if not cands:
            return ""
        vals = []
        for r in cands:
            try:
                vals.append(float(r.get("auc") or r.get("auc_test") or r.get("auc_val") or "nan"))
            except ValueError:
                pass
        vals = [v for v in vals if v == v]
        return f"{sum(vals)/len(vals):.4f}" if vals else ""

    t3_models = [
        ("decision_tree", "【证据不足】原文 DT 未跑"),
        ("xgboost", ""),
        ("mlp", ""),
        ("lstm", ""),
        ("two_stage_Transformer", ""),
        ("a1_repo", "【场景迁移】A1"),
        ("a2_single", "【场景迁移】A2"),
        ("logistic", "【场景迁移】额外基线"),
    ]
    model_key = {
        "decision_tree": None,
        "xgboost": "xgb",
        "mlp": "mlp",
        "lstm": "lstm",
        "two_stage_Transformer": "b",
        "a1_repo": "a1",
        "a2_single": "a2",
        "logistic": "logistic",
    }
    s6_name = {
        "decision_tree": "Decision Tree",
        "xgboost": "XGBoost",
        "mlp": "MLP",
        "lstm": "LSTM",
        "two_stage_Transformer": "Two-stage Transformer",
    }
    t3_rows = []
    for name, note in t3_models:
        mk = model_key[name]
        auc = _auc_for(mk, 5) if mk else ""
        s6n = s6_name.get(name, "")
        acc = _s6_metric(s6n, 5, "accuracy") if s6n else ""
        f1 = _s6_metric(s6n, 5, "f1") if s6n else ""
        if not auc and s6n:
            auc = _s6_metric(s6n, 5, "auc")
        t3_rows.append(
            {
                "Model": name.replace("_", " "),
                "Landmark (h)": primary_lm,
                "Day": 5,
                "AUC": auc,
                "Accuracy": acc,
                "F1 score": f1,
                "Note": note or ("" if auc else "缺失"),
            }
        )
    rows_to_xlsx(
        tables / lit_tab(3, "Comparative_model_performance"),
        t3_rows,
        f"Table 3. Comparative model performance (L{primary_lm}, Day 5)",
        footnotes=[
            "Paper models: Decision Tree / XGBoost / MLP / LSTM / Transformer.",
            "A1/A2/logistic are extra baselines 【场景迁移】.",
            "Decision Tree row filled from S6 surrogate when available; else 【证据不足】.",
        ],
    )
    lit(
        str(Path("Tables") / lit_tab(3, "Comparative_model_performance")),
        "Main Table 3",
        "Comparative performance metrics of predictive models (paper: DT/XGB/MLP/LSTM/Transformer).",
        f"主对照 L{primary_lm} Day5；DT 等见 S6 / 【证据不足】",
    )

    feat_src = proj / "_shared/step04_tst_timeseries/_tst_feature_coverage_audit.csv"
    if feat_src.exists():
        csv_file_to_xlsx(
            feat_src,
            tables / lit_tab(1, "Features", supp=True),
            "Table S1. Features / coverage audit (MIMIC ischemic stroke)",
            footnotes=[
                "【场景迁移】卒中日级特征审计，非原文 eICU 226 维小时特征表。",
            ],
        )
    else:
        blank_xlsx(
            tables / lit_tab(1, "Features", supp=True),
            "Table S1. Features",
            "Source missing",
        )
    lit(
        str(Path("Tables") / lit_tab(1, "Features", supp=True)),
        "Supplementary Table 1",
        "Features table (paper: eICU 226 features; here: MIMIC stroke retained features + coverage audit).",
        "【场景迁移】卒中日级特征审计，非原文 226 维小时特征表",
    )

    fc_src = proj / "_shared/step03_tst_cohort/_tst_cohort_flowchart.csv"
    if fc_src.exists():
        csv_file_to_pdf(
            fc_src,
            figures / lit_fig(1, "Cohort_flowchart"),
            "Main Figure 1 — Cohort screening workflow (counts table)",
        )
    else:
        blank_pdf(figures / lit_fig(1, "Cohort_flowchart"), "Main Figure 1 — Cohort flowchart")
    lit(
        str(Path("Figures") / lit_fig(1, "Cohort_flowchart")),
        "Main Figure 1",
        "Participants screening workflow (paper Fig. 1).",
        "本复现以纳排计数表 PDF 占位，无矢量流程图原件",
    )

    blank_pdf(
        figures / lit_fig(2, "Model_framework"),
        "Main Figure 2 — Two-stage Transformer framework",
        "【证据不足】未复现架构示意图（占位空白页）\n实现见 python/two_stage_transformer/model.py",
    )
    lit(
        str(Path("Figures") / lit_fig(2, "Model_framework")),
        "Main Figure 2",
        "Framework of the two-stage Transformer model for ICU patient time-series analysis.",
        "【证据不足】空白占位 PDF",
    )

    f3_pdf = figures / lit_fig(3, "ROC_confusion_model_comparison")
    fig3_ok = _build_yang_figure3(proj, primary_lm, f3_pdf)
    if not fig3_ok:
        if primary_roc_png and primary_roc_png.exists():
            png_to_pdf(primary_roc_png, f3_pdf)
        else:
            blank_pdf(f3_pdf, "Main Figure 3 — ROC + CM (Yang layout)")
    lit(
        str(Path("Figures") / lit_fig(3, "ROC_confusion_model_comparison")),
        "Main Figure 3",
        "ROC curves, confusion matrices, and model comparison (Yang Fig.3 layout; vs SAPSII).",
        f"L{primary_lm}_B Day1–5；对照 SAPSII【场景迁移】；图面无方法学大标题；"
        + ("regenerated" if fig3_ok else "fallback"),
    )

    if primary_shap_days:
        collage_shap_pdf(
            primary_shap_days,
            figures / lit_fig(4, "SHAP_daily_heatmap"),
            f"Main Figure 4 — SHAP L{primary_lm} B",
        )
    else:
        blank_pdf(figures / lit_fig(4, "SHAP_daily_heatmap"), "Main Figure 4 — SHAP heatmap")
    lit(
        str(Path("Figures") / lit_fig(4, "SHAP_daily_heatmap")),
        "Main Figure 4",
        "Daily feature visualization heatmaps (SHAP) for the two-stage Transformer.",
        f"L{primary_lm}_B Day1–5；列名为 mapping/字典标准名；日级广播【场景迁移】致小时维近似常数",
    )

    for d in range(1, 6):
        src = None
        if primary_shap_days and len(primary_shap_days) >= d:
            src = primary_shap_days[d - 1]
        else:
            ud = unit_dir(proj, f"L{primary_lm}_B_twostage")
            if ud:
                src = find_file(ud, f"shap_b_day{d}.png")
        dst = figures / lit_fig(d, f"SHAP_Day{d}", supp=True)
        if src and src.exists():
            png_to_pdf(src, dst)
        else:
            blank_pdf(dst, f"Supplementary Figure {d} — SHAP Day {d}")
        lit(
            str(Path("Figures") / lit_fig(d, f"SHAP_Day{d}", supp=True)),
            f"Supplementary Figure {d}",
            f"Day-{d} model visualization results (SHAP).",
            f"对应补充 Fig {d}；L{primary_lm}_B",
        )

    # Supplementary Figure S6 — Yang 风格五模型×三指标柱图
    s6_pdf = figures / lit_fig(6, "Model_comparison_bar", supp=True)
    s6_ok = False
    try:
        import os
        import subprocess

        script = Path(__file__).resolve().parent / "redraw_fig_s6_comparison.py"
        torch_py = Path("/mnt/c/ProgramData/miniconda3/envs/torch/python.exe")
        if script.exists() and torch_py.exists():
            env = os.environ.copy()
            env["KMP_DUPLICATE_LIB_OK"] = "TRUE"
            r = subprocess.run(
                [str(torch_py), _to_win_path(script)],
                env=env,
                capture_output=True,
                text=True,
                timeout=600,
            )
            s6_ok = r.returncode == 0 and s6_pdf.exists()
            if r.returncode != 0:
                print("[S6] redraw failed:", (r.stderr or r.stdout)[-500:])
            else:
                print((r.stdout or "")[-400:])
    except Exception as e:
        print(f"[S6] exception: {e}")
    if not s6_ok:
        blank_pdf(s6_pdf, "Supplementary Figure 6 — Comparison of Models", "regeneration failed")
    lit(
        str(Path("Figures") / lit_fig(6, "Model_comparison_bar", supp=True)),
        "Supplementary Figure 6",
        "Model performance comparison bar chart of AUC/Accuracy/F1 (paper P<0.001).",
        "Day1–5 mean±SD；含 DT/XGB/MLP/LSTM/Transformer；布局对齐补充 S6"
        + ("; regenerated" if s6_ok else "; blank"),
    )

    ext_unit = unit_dir(proj, "external_synthetic")
    ext_csv = find_file(ext_unit, "Table_External_Synthetic_Metrics.csv") if ext_unit else None
    if ext_csv and ext_csv.exists():
        rows = read_csv(ext_csv)
        for r in rows:
            r.setdefault("is_synthetic", "TRUE")
            r.setdefault(
                "synthetic_label",
                "SYNTHETIC — not for primary manuscript conclusions",
            )
        rows_to_pdf(
            figures / lit_fig("7-8", "External_validation", supp=True),
            rows,
            "Supplementary Figures 7–8 — External validation (SYNTHETIC)",
        )
    else:
        blank_pdf(
            figures / lit_fig("7-8", "External_validation", supp=True),
            "Supplementary Figures 7–8 — External validation",
            "SYNTHETIC placeholder",
        )
    lit(
        str(Path("Figures") / lit_fig("7-8", "External_validation", supp=True)),
        "Supplementary Figures 7–8",
        "External validation outcomes (paper Fig7 domestic / Fig8 MIMIC sepsis).",
        "【场景迁移】合成外推；禁止当真实外推主文结论",
    )

    blank_pdf(
        figures / lit_fig(9, "System_integration", supp=True),
        "Supplementary Figure 9 — Hospital system integration",
        "【证据不足】未复现（占位空白页）",
    )
    lit(
        str(Path("Figures") / lit_fig(9, "System_integration", supp=True)),
        "Supplementary Figure 9",
        "Framework of Hospital System Integration with Predictive Models.",
        "【证据不足】空白占位 PDF",
    )

    # Extras → xlsx 三线表（不生成 Extra_Calibration/DCA/ROC 图）
    if cal_rows:
        rows_to_xlsx(
            tables / lit_tab(0, "Calibration", extra=True),
            cal_rows,
            "Table Extra. Calibration",
        )
    if dca_rows:
        rows_to_xlsx(tables / lit_tab(0, "DCA", extra=True), dca_rows, "Table Extra. DCA")
    if abl_rows:
        rows_to_xlsx(
            tables / lit_tab(0, "Ablation", extra=True),
            abl_rows,
            "Table Extra. Ablation",
        )
    # Literature_Validation / Batch_summary / Indicator_availability：用户确认无用，不再导出

    for our, lid, cap, note in [
        (str(Path("Tables") / lit_tab(0, "Calibration", extra=True)), "Extra (not in paper)", "Calibration table", "原文无独立校准表"),
        (str(Path("Tables") / lit_tab(0, "DCA", extra=True)), "Extra (not in paper)", "DCA table", "原文无独立 DCA 表"),
        (str(Path("Tables") / lit_tab(0, "Ablation", extra=True)), "Extra (not in paper)", "Ablation metrics", "双轨复现消融"),
    ]:
        lit(our, lid, cap, note)

    rows_to_pdf(out / "00_Literature_ID_Map.pdf", lit_map, "Literature ID ↔ file map", max_rows=80)
    rows_to_pdf(scratch / "manifest_tmp.pdf", [{"k": m.get("dest"), "src": m.get("source")} for m in manifest], "manifest")

    checklist = [
        ("Main_Table1", str(Path("Tables") / lit_tab(1, "Baseline_characteristics"))),
        ("Main_Table2", str(Path("Tables") / lit_tab(2, "Daily_performance_Transformer"))),
        ("Main_Table3", str(Path("Tables") / lit_tab(3, "Comparative_model_performance"))),
        ("Main_Figure1", str(Path("Figures") / lit_fig(1, "Cohort_flowchart"))),
        ("Main_Figure2", str(Path("Figures") / lit_fig(2, "Model_framework"))),
        ("Main_Figure3", str(Path("Figures") / lit_fig(3, "ROC_confusion_model_comparison"))),
        ("Main_Figure4", str(Path("Figures") / lit_fig(4, "SHAP_daily_heatmap"))),
        ("Supp_Table1", str(Path("Tables") / lit_tab(1, "Features", supp=True))),
        ("Supp_Figure1", str(Path("Figures") / lit_fig(1, "SHAP_Day1", supp=True))),
        ("Supp_Figure2", str(Path("Figures") / lit_fig(2, "SHAP_Day2", supp=True))),
        ("Supp_Figure3", str(Path("Figures") / lit_fig(3, "SHAP_Day3", supp=True))),
        ("Supp_Figure4", str(Path("Figures") / lit_fig(4, "SHAP_Day4", supp=True))),
        ("Supp_Figure5", str(Path("Figures") / lit_fig(5, "SHAP_Day5", supp=True))),
        ("Supp_Figure6", str(Path("Figures") / lit_fig(6, "Model_comparison_bar", supp=True))),
        ("Supp_Figure7_8", str(Path("Figures") / lit_fig("7-8", "External_validation", supp=True))),
        ("Supp_Figure9", str(Path("Figures") / lit_fig(9, "System_integration", supp=True))),
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
        {"section": "Main Figure 1", "content": str(Path("Figures") / lit_fig(1, "Cohort_flowchart"))},
        {"section": "Main Figure 2", "content": str(Path("Figures") / lit_fig(2, "Model_framework")) + " (blank)"},
        {"section": "Main Table 1", "content": str(Path("Tables") / lit_tab(1, "Baseline_characteristics"))},
        {"section": "Main Table 2", "content": str(Path("Tables") / lit_tab(2, "Daily_performance_Transformer"))},
        {"section": "Main Figure 3", "content": str(Path("Figures") / lit_fig(3, "ROC_confusion_model_comparison"))},
        {"section": "Main Table 3", "content": str(Path("Tables") / lit_tab(3, "Comparative_model_performance"))},
        {"section": "Main Figure 4", "content": str(Path("Figures") / lit_fig(4, "SHAP_daily_heatmap"))},
        {"section": "Supp Table 1", "content": str(Path("Tables") / lit_tab(1, "Features", supp=True))},
        {"section": "Supp Fig 1-5", "content": "Figures/Figure S{1-5}-MIMIC-SHAP_Day*.pdf"},
        {"section": "Supp Fig 6", "content": str(Path("Figures") / lit_fig(6, "Model_comparison_bar", supp=True))},
        {"section": "Supp Fig 7-8", "content": str(Path("Figures") / lit_fig("7-8", "External_validation", supp=True))},
        {"section": "Supp Fig 9", "content": str(Path("Figures") / lit_fig(9, "System_integration", supp=True)) + " (blank)"},
        {
            "section": "Format",
            "content": "Tables/=xlsx SCI three-line (Times New Roman); Figures/=PDF",
        },
        {"section": "Primary landmark", "content": f"L{primary_lm}_B_twostage"},
    ]
    rows_to_pdf(out / "README.pdf", readme_lines, "summary_results — Yang pbaf003 ID alignment")

    # Tables 仅保留 xlsx；Figures / by_landmark 仍 PDF
    purge_keep_ext(tables, {".xlsx"})
    purge_non_pdf(figures)
    purge_non_pdf(by_lm)
    for p in out.iterdir():
        if p.is_file() and p.suffix.lower() != ".pdf":
            try:
                p.unlink()
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
    args = ap.parse_args(argv)
    return build_summary_results(
        project_root=args.project_root or None,
        primary_landmark=args.primary_landmark,
    )


if __name__ == "__main__":
    main()
