#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
中期分析报告 PDF 生成引擎(step06-Aiya-midterm-report-pdf)

两种模式:
  inspect: dump 项目信息(项目信息-中期.md) + 全部 xlsx 单元格 + 图清单,给 Claude 读数据写内容用
  build:   把 content.json(Claude 撰写的叙述)+ xlsx 表 + PDF 图合成一份 PDF 报告

依赖:pandas 不需要;openpyxl + PyMuPDF(fitz) + Chrome/Edge 无头打印。零额外安装。

用法:
  python build_report.py --inspect --project <项目目录> [--out dump路径]
  python build_report.py --build --project <项目目录> --content <content.json> [--out 输出.pdf]
"""

import argparse
import glob
import html
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import date
from pathlib import Path

import fitz  # PyMuPDF
import openpyxl

# 部分交付 xlsx 引用了包内不存在的 drawing,openpyxl 解析嵌入图片时 KeyError。
# 报告不需要嵌入图片,直接禁用图片/图表解析(须补丁 excel 模块的直接绑定名)。
import openpyxl.reader.excel as _ap_excel
_ap_excel.find_images = lambda *a, **k: ([], [])

BROWSER_CANDIDATES = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
]
# Linux 兼容(2026-09-07):apt/snap Chrome 与 playwright 缓存的 Chromium;
# playwright 无 root 运行须 --no-sandbox(见 print_pdf)。
if sys.platform.startswith("linux"):
    BROWSER_CANDIDATES += [
        "/usr/bin/google-chrome",
        "/usr/bin/google-chrome-stable",
        "/usr/bin/chromium",
        "/usr/bin/chromium-browser",
        "/snap/bin/chromium",
        # 2026-09-09(aiya-ai):playwright 完整版 chrome --headless=new 打印后不退出(挂死),
        # 优先用 chrome-headless-shell(打印完即退);完整版留作回退。
        *sorted(glob.glob(os.path.expanduser(
            "~/.cache/ms-playwright/chromium_headless_shell-*/chrome-headless-shell-linux*/chrome-headless-shell"))),
        *sorted(glob.glob(os.path.expanduser(
            "~/.cache/ms-playwright/chromium-*/chrome-linux*/chrome"))),
        # WSL 无 Linux Chrome 时用 Windows 浏览器；print_pdf 会把路径换成盘符。
        "/mnt/c/Program Files/Google/Chrome/Application/chrome.exe",
        "/mnt/c/Program Files (x86)/Google/Chrome/Application/chrome.exe",
        "/mnt/c/Program Files/Microsoft/Edge/Application/msedge.exe",
        "/mnt/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
    ]

LABEL_RE = re.compile(r"(Table|Figure)\s*(S?\d+)", re.IGNORECASE)
SUPP_RE = re.compile(r"(Table|Figure)\s*S\d+", re.IGNORECASE)
TITLE_RE = re.compile(r"^(Table|Figure)\b", re.IGNORECASE)


# ---------------------------------------------------------------- 项目信息

def parse_project_md(proj_dir: Path) -> dict:
    """解析 项目信息-中期.md(缺省,回退 项目信息.md)的 `key: value` 行。返回 dict;表格/图片目录名缺省 Tables/Figures。"""
    info = {}
    md = proj_dir / "项目信息-中期.md"
    if not md.exists():
        md = proj_dir / "项目信息.md"
    if not md.exists():
        md = proj_dir / "Project Information.md"  # 2026-09-17 英文名回退(全局英文文件名规则)
    if not md.exists():
        return info
    for line in md.read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(r"^([^:：]+)[：:]\s*(.+)$", line.strip())
        if m:
            info[m.group(1).strip()] = m.group(2).strip()
    return info


def customer_label(info: dict) -> str:
    """客户名称后补"老师"(已以"老师"结尾则保持原样)。"""
    c = info.get("客户", "")
    if c and not c.endswith("老师"):
        c += "老师"
    return c


def asset_dirs(proj_dir: Path, info: dict):
    tname = info.get("表格路径", "Tables")
    fname = info.get("图片路径", "Figures")
    tdir = proj_dir / tname
    fdir = proj_dir / fname
    return (tdir if tdir.exists() else proj_dir), (fdir if fdir.exists() else proj_dir)


def discover(tdir: Path, fdir: Path):
    """返回 (tables, figures):主表、主图、附表、附图 各自按编号自然排序。"""
    def key_of(p: Path):
        m = LABEL_RE.search(p.stem)
        if not m:
            return (9, 0)
        supp = 1 if m.group(2).upper().startswith("S") else 0
        digits = re.sub(r"\D", "", m.group(2)) or "0"
        return (supp, int(digits))

    # 递归收集:支持资产分装在子文件夹(如按时间点的 28天/3个月/6个月);~$ 临时文件跳过
    tables = sorted((p for p in tdir.rglob("*.xlsx") if not p.name.startswith("~$")), key=key_of)
    figures = sorted((p for p in fdir.rglob("*.pdf") if not p.name.startswith("~$")), key=key_of)
    main_t = [p for p in tables if not SUPP_RE.search(p.stem)]
    supp_t = [p for p in tables if SUPP_RE.search(p.stem)]
    main_f = [p for p in figures if not SUPP_RE.search(p.stem)]
    supp_f = [p for p in figures if SUPP_RE.search(p.stem)]
    for p in tables + figures:
        if not LABEL_RE.search(p.stem):
            print(f"[警告] 文件名无法解析编号,排到末尾: {p.name}", file=sys.stderr)
    return main_t, main_f, supp_t, supp_f


# ---------------------------------------------------------------- xlsx 读取

def read_sheet(path: Path):
    """读第一个 sheet 为 (grid, merges)。grid 是二维 list;merges 是合并区域 set{(r,c,r2,c2)}。
    不用 read_only 模式——实测部分文件其 max_row/max_column 失真。"""
    wb = openpyxl.load_workbook(path, data_only=True)
    if len(wb.sheetnames) > 1:
        print(f"[提示] {path.name} 有 {len(wb.sheetnames)} 个 sheet,仅使用第一个: {wb.sheetnames[0]}", file=sys.stderr)
    ws = wb[wb.sheetnames[0]]
    grid = [[("" if c is None else str(c).strip()) for c in row] for row in ws.iter_rows(values_only=True)]
    merges = {(r.min_row - 1, r.min_col - 1, r.max_row - 1, r.max_col - 1) for r in ws.merged_cells.ranges}
    wb.close()
    # 去掉全空行尾 / 全空列尾
    while grid and all(v == "" for v in grid[-1]):
        grid.pop()
    if grid:
        maxc = max((len(r) for r in grid), default=0)
        grid = [r + [""] * (maxc - len(r)) for r in grid]
        while maxc and all(row[maxc - 1] == "" for row in grid):
            for row in grid:
                row.pop()
            maxc -= 1
    return grid, merges


def split_caption(grid, merges):
    """剥离开头只有单一非空单元格的标题行。返回 (caption_lines, body)。
    横向合并(跨≥2列)的单值行通常是内容行(如通栏的 'Overall (N=2,003)'),不是标题,
    遇到即停止剥离——除非其文本以 Table/Figure 开头(视为表格标题,仍算 caption)。
    merges 坐标是 grid 空间。"""
    caps, i = [], 0
    while i < len(grid):
        nonempty = [v for v in grid[i] if v != ""]
        if len(nonempty) != 1:
            break
        v = nonempty[0]
        is_hmerge = any(r0 == i and c2 > c0 and r2 == r0 for (r0, c0, r2, c2) in merges)
        if is_hmerge and not TITLE_RE.match(v):
            break
        caps.append(v)
        i += 1
    return caps, grid[i:]


def header_rows(body, merges, off=0):
    """判断表头行数:首行必为表头;若其下方紧邻行与首行共同构成合并表头(如 Crude Model/Model1 双层),扩展。
    merges 行坐标是 grid 空间,body 已剥掉标题行,须按偏移 off 对齐。"""
    if not body:
        return 1
    n = 1
    # 首行存在横向合并(跨≥2列)→ 视为分组表头,再吃下一行
    has_hmerge = any(r0 - off == 0 and c2 - c0 >= 1 and r2 == r0 for (r0, c0, r2, c2) in merges)
    # 首行有多个空单元格而次行在这些位置有值 → 双层表头
    first, second = body[0], (body[1] if len(body) > 1 else [])
    gap_fill = any(v == "" and ci < len(second) and second[ci] != "" for ci, v in enumerate(first))
    if (has_hmerge or gap_fill) and len(body) > 1:
        n = 2
        # 若第 2 行还有向下合并到第 3 行的(三层表头,罕见),继续吃
        while any(r0 - off == n and r2 > r0 for (r0, c0, r2, c2) in merges) and len(body) > n:
            n += 1
    return n


def grid_to_html_table(path: Path, table_id: str, suppress_caption: bool = False) -> str:
    """xlsx → HTML 表,保留合并单元格(colspan/rowspan),标题行转 caption。
    suppress_caption=True 时不渲染内嵌 caption(标题已由外部'表N:'行承担,避免重复)。"""
    grid, merges = read_sheet(path)
    caps, body = split_caption(grid, merges)
    if not body:
        return f'<p class="warn">[空表] {html.escape(path.name)}</p>'
    off = len(caps)
    nhead = header_rows(body, merges, off)
    ncols = max(len(r) for r in body)

    span_map = {}  # (r,c) -> (rs, cs)
    covered = set()
    for (r0, c0, r2, c2) in merges:
        r0 -= off
        r2 -= off
        if r0 < 0 or r0 >= len(body) or c0 >= ncols:
            continue
        rs, cs = r2 - r0 + 1, c2 - c0 + 1
        span_map[(r0, c0)] = (rs, cs)
        for rr in range(r0, r2 + 1):
            for cc in range(c0, c2 + 1):
                if (rr, cc) != (r0, c0):
                    covered.add((rr, cc))

    def cell_tag(r, c, in_head):
        v = body[r][c] if c < len(body[r]) else ""
        tag = "th" if in_head else "td"
        span = span_map.get((r, c))
        attrs = ""
        if span:
            rs, cs = span
            if cs > 1:
                attrs += f' colspan="{cs}"'
            if rs > 1:
                attrs += f' rowspan="{rs}"'
        cls = ' class="rowhead"' if (not in_head and c == 0 and v != "") else ""
        return f"<{tag}{attrs}{cls}>{html.escape(v)}</{tag}>"

    parts = []
    if not suppress_caption:
        for ci, cap in enumerate(caps):
            if ci == 0:
                parts.append(f"<caption>{html.escape(cap)}</caption>")
            else:
                parts.append(f'<caption class="sub">{html.escape(cap)}</caption>')

    parts.append("<thead>")
    for r in range(nhead):
        parts.append("<tr>" + "".join(cell_tag(r, c, True) for c in range(ncols) if (r, c) not in covered) + "</tr>")
    parts.append("</thead><tbody>")

    # 表格尾部脚注:仅第0列有内容(未合并,或合并恰好占满整行)的行 → 按通栏渲染,避免只显示在第一列
    note_start = len(body)
    for r in range(len(body) - 1, nhead - 1, -1):
        nz = [c for c, v in enumerate(body[r]) if v != ""]
        if len(nz) != 1 or nz[0] != 0:
            break
        sp = span_map.get((r, 0))
        if sp is not None and sp != (1, ncols):
            break
        if sp is None and (r, 0) in covered:
            break
        note_start = r

    for r in range(nhead, len(body)):
        if r >= note_start:
            parts.append(f'<tr><td class="fullnote" colspan="{ncols}">{html.escape(body[r][0])}</td></tr>')
        else:
            parts.append("<tr>" + "".join(cell_tag(r, c, False) for c in range(ncols) if (r, c) not in covered) + "</tr>")
    parts.append("</tbody>")

    size_cls = "tw" if ncols <= 8 else ("tm" if ncols <= 12 else "twide")
    return f'<table id="{table_id}" class="data {size_cls}">' + "".join(parts) + "</table>"


def relkey(p: Path, proj: Path) -> str:
    """资产相对项目目录的 posix 路径键;不在项目目录下时退化为文件名。"""
    try:
        return p.resolve().relative_to(proj).as_posix()
    except ValueError:
        return p.name


def resolve_ref(ref: str, pool: list, proj: Path, what: str = "引用") -> Path:
    """解析 content.json 中 table/figure 引用为资产路径。
    含 / 或 \\ 的引用按相对项目目录解析(子文件夹模式);裸文件名须在全集中唯一。"""
    if "/" in ref or "\\" in ref:
        target = ref.replace("\\", "/").lstrip("./")
        matches = [q for q in pool if relkey(q, proj) == target]
        if matches:
            return matches[0]
        sys.exit(f"{what} 引用了资产目录树中不存在的文件: {ref}")
    cands = [q for q in pool if q.name == ref]
    if len(cands) == 1:
        return cands[0]
    if len(cands) > 1:
        sys.exit(f"{what} 引用 {ref} 在多个子文件夹中同名,存在歧义;请改用带子目录的相对路径,如: "
                 + " | ".join(relkey(q, proj) for q in cands))
    sys.exit(f"{what} 引用了不存在的文件: {ref}")


def analyze_table(p: Path, suppress_caption: bool = False):
    """一次读取,返回 (html_table, ncols, nrows, caption, title_for_heading)。"""
    grid, merges = read_sheet(p)
    caps, body = split_caption(grid, merges)
    ncols = max(len(r) for r in body) if body else 0
    nrows = len(body)
    tbl = grid_to_html_table(p, p.stem[:30], suppress_caption)
    return tbl, ncols, nrows, caps, (caps[0] if caps else p.stem)


# ---------------------------------------------------------------- inspect

def cmd_inspect(args):
    if not args.project:
        sys.exit("inspect 模式需要 --project <项目目录>")
    proj = Path(args.project).resolve()
    info = parse_project_md(proj)
    tdir, fdir = asset_dirs(proj, info)
    main_t, main_f, supp_t, supp_f = discover(tdir, fdir)

    lines = [f"# Inspect dump — {proj.name}", ""]
    lines.append("## 项目信息(项目信息-中期.md)")
    lines.append("| 字段 | 值 |")
    lines.append("|---|---|")
    for k, v in info.items():
        lines.append(f"| {k} | {v} |")
    lines.append("")

    def dump_table(p: Path):
        lines.append(f"### 表格: {relkey(p, proj)}")
        grid, merges = read_sheet(p)
        caps, body = split_caption(grid, merges)
        for cap in caps:
            lines.append(f"> 标题行: {cap}")
        if body:
            lines.append(f"({len(body)} 行 × {max(len(r) for r in body)} 列;合并区域 {len(merges)} 处)")
            lines.append("")
            for row in body:
                lines.append("| " + " | ".join(v if v else " " for v in row) + " |")
        lines.append("")

    lines.append(f"## 表格目录({tdir.name}/,共 {len(main_t)+len(supp_t)} 个)")
    lines.append("")
    for p in main_t + supp_t:
        dump_table(p)

    lines.append(f"## 图目录({fdir.name}/,共 {len(main_f)+len(supp_f)} 个)")
    lines.append("")
    for p in main_f + supp_f:
        d = fitz.open(p)
        pg_note = "单页" if len(d) == 1 else f"⚠️ {len(d)} 页,报告只嵌首页"
        page0 = d[0]
        w, h = page0.rect.width, page0.rect.height
        ratio = w / h if h else 0
        # 判断是否拼接图:宽幅(横向多面板)或高幅(纵向多面板)
        if ratio > 1.3:
            merge = "🔗 已拼接(宽幅多面板,建议合写注释)"
        elif ratio < 0.6:
            merge = "🔗 已拼接(纵幅多面板,建议合写注释)"
        else:
            merge = "单图(建议分数据集描述)"
        lines.append(f"- **{relkey(p, proj)}** ({pg_note}, {w:.0f}×{h:.0f}pt, ratio={ratio:.2f}) → {merge}")
        d.close()
    lines.append("")

    out = Path(args.out) if args.out else proj / "_report_dump.md"
    out.write_text("\n".join(lines), encoding="utf-8")
    print(f"inspect 完成: {out}")
    print(f"  表 {len(main_t)+len(supp_t)} 个(主 {len(main_t)} / 补 {len(supp_t)});图 {len(main_f)+len(supp_f)} 个(主 {len(main_f)} / 补 {len(supp_f)})")


# ---------------------------------------------------------------- HTML / PDF

CSS = """
@page { size: A4 portrait; margin: 2.4cm 2.5cm 2.2cm; }
* { box-sizing: border-box; }
body { font-family: "SimSun", "Songti SC", "Microsoft YaHei", serif; font-size: 12pt; line-height: 1.6; color: #1a1a1a; }
h1 { font-size: 19pt; text-align: center; margin: 0 0 4pt; }
.sub-title { text-align: center; font-size: 12pt; color: #444; margin: 0 0 16pt; }
h2 { font-size: 14pt; border-left: 4pt solid #2c5f8a; padding-left: 8pt; margin: 18pt 0 8pt; page-break-after: avoid; }
h3 { font-size: 14pt; font-family: "Liberation Sans", "SimHei", "Microsoft YaHei", sans-serif; margin: 16pt 0 6pt; page-break-after: avoid; }
p { margin: 4pt 0; text-align: justify; text-indent: 2em; }
.meta-table { width: 100%; border-collapse: collapse; margin: 10pt 0; }
.meta-table td { border: 0.75pt solid #999; padding: 5pt 8pt; font-size: 10.5pt; }
.meta-table td.k { background: #eef3f7; width: 22%; font-weight: bold; }
table.data { width: 100%; border-collapse: collapse; margin: 6pt 0; table-layout: auto; }
table.data caption { caption-side: top; text-align: center; font-weight: normal; font-size: 11pt; padding: 4pt 0; }
table.data caption.sub { font-weight: normal; font-size: 9pt; color: #333; }
table.data th, table.data td { border: 0.5pt solid #8aa; padding: 3pt 5pt; overflow-wrap: anywhere; text-align: center; }
table.data th { background: #e8eef3; }
table.data td.rowhead, table.data th:first-child { text-align: left; }
table.data td.fullnote { text-align: left; color: #444; }
table.data thead { display: table-header-group; }
table.tw  { font-size: 8pt; }
table.tm  { font-size: 6.5pt; }
table.twide { font-size: 5.5pt; }
figure { margin: 8pt 0 2pt; page-break-inside: avoid; text-align: center; }
figure img { max-width: 100%; max-height: 14.5cm; object-fit: contain; }
.figblock { page-break-inside: avoid; text-align: center; }
.block { page-break-inside: avoid; }
.block.breakable { page-break-inside: auto; }
.fig-title { text-align: left; font-weight: bold; font-size: 11pt; margin: 10pt 0 2pt; text-indent: 0; }
.summary { background: #f7f9fb; border-left: 3pt solid #2c5f8a; padding: 6pt 10pt; margin: 4pt 0 14pt; }
.summary p { margin: 0; font-size: 10.5pt; text-indent: 0; }
.cover { text-align: center; margin-top: 44pt; display: flex; flex-direction: column; min-height: 23cm; }
.cover h1 { font-family: "Liberation Sans", "SimHei", "Microsoft YaHei", sans-serif; font-size: 21pt; margin-bottom: 6pt; font-weight: bold; }
.cover .cover-subtitle { font-size: 17pt; margin: 20pt 0 0; text-indent: 0; text-align: center; letter-spacing: 2pt; }
.cover .datasrc { font-size: 14pt; color: #222; margin: 12pt 0 0; text-indent: 0; text-align: center; }
.cover .info-list { text-align: left; width: 70%; margin: 40pt auto 0; }
.cover .info-list p { margin: 7pt 0; font-size: 12pt; text-indent: 0; }
.cover .info-list .lbl { font-family: "SimHei", "Microsoft YaHei", sans-serif; font-weight: bold; display: inline-block; min-width: 6.5em; }
.cover .bottom-note { margin-top: auto; padding-bottom: 1cm; }
.cover .bottom-note .date { color: #555; font-size: 11pt; }
.cover .bottom-note .disclaimer { color: #888; font-size: 9.5pt; margin-top: 8pt; text-align: center; text-indent: 0; }
.toc-page { page-break-after: always; }
.toc-page h2 { font-family: "Liberation Sans", "SimHei", "Microsoft YaHei", sans-serif; font-size: 16pt; text-align: center; border: none; padding: 0; margin: 6pt 0 22pt; }
.toc-page table { width: 100%; border-collapse: collapse; }
.toc-page td { padding: 4pt 0; font-size: 12pt; vertical-align: bottom; }
.toc-page td.td-num { width: 58pt; }  /* 2026-09-17: 44pt 在两位数小节(9.10+)时编号溢出错位 */
.toc-page td.td-dots { width: auto; }
.toc-page td.td-pg { width: 34pt; text-align: right; border-bottom: none; }
.toc-page tr.toc-chapter td { font-weight: bold; font-family: "Liberation Sans", "SimHei", "Microsoft YaHei", sans-serif; padding-top: 10pt; }
.toc-page tr.toc-section td.td-num { padding-left: 26pt; }
.toc-page tr.toc-section td { font-weight: normal; }
.chapter { font-size: 17pt; font-weight: bold; font-family: "Liberation Sans", "SimHei", "Microsoft YaHei", sans-serif; text-align: center; margin: 22pt 0 10pt; page-break-after: avoid; }
.section-wrap { margin-left: 0; }
.section-wrap > h3 { font-size: 14pt; font-weight: bold; font-family: "Liberation Sans", "SimHei", "Microsoft YaHei", sans-serif; margin: 16pt 0 6pt; margin-left: 24pt; page-break-after: avoid; color: #1a1a1a; }
.section-intro { margin: 4pt 0 6pt; }
.formula { text-align: center; text-indent: 0; font-family: "Times New Roman", "SimSun", "Noto Serif CJK SC", serif; font-size: 12pt; margin: 8pt 0 10pt; page-break-inside: avoid; }
.annotation { font-family: "KaiTi", "楷体", "SimSun", serif; font-size: 11pt; color: #222; line-height: 1.55; text-align: justify; text-indent: 0; margin: 6pt 0 14pt; }
p.tbl-caption { text-align: center; font-size: 12pt; text-indent: 0; margin: 8pt 0 4pt; }
p.fig-caption { text-align: center; font-size: 12pt; text-indent: 0; margin: 4pt 0 10pt; page-break-before: avoid; }
.keep-with-next { page-break-after: avoid; }
.end-note { margin-top: 4pt; }
.end-note p { text-indent: 0; color: #333; margin: 2pt 0; }
.pgmark { position: absolute; font-size: 1pt; color: #ffffff; }
body.final .pgmark { display: none; }
table.idx th, table.idx td:nth-child(1), table.idx td:nth-child(2) { white-space: nowrap; }
table.idx td:nth-child(2) { width: 8%; }
.abbrev-wrap { page-break-before: always; }
.abbrev-head { font-size: 17pt; font-weight: bold; font-family: "Liberation Sans", "SimHei", "Microsoft YaHei", sans-serif; text-align: center; margin: 0 0 10pt; page-break-after: avoid; }
table.abbrev { width: 90%; margin: 0 auto; }
table.abbrev th, table.abbrev td { font-size: 10pt; padding: 2.5pt 5pt; }
"""

LANDSCAPE_CSS = CSS.replace("A4 portrait", "A4 landscape").replace(
    "figure img { max-width: 100%; max-height: 14.5cm;",
    "figure img { max-width: 100%; max-height: 12.5cm;")


def html_doc(body: str, landscape: bool, final: bool = False) -> str:
    cls = ' class="final"' if final else ""
    return f"""<!DOCTYPE html><html><head><meta charset="utf-8">
<style>{LANDSCAPE_CSS if landscape else CSS}</style></head><body{cls}>{body}</body></html>"""


# ---------------------------------------------------------------- Alice-style helpers

def check_formula(obj: dict, where: str):
    fs = obj.get("formula", [])
    if isinstance(fs, str) or (isinstance(fs, list) and all(isinstance(x, str) and x.strip() for x in fs)):
        return
    sys.exit(f'{where}.formula 须为非空字符串或字符串数组(居中渲染于该处 intro 之后,如暴露指标计算公式)')


def validate_chapters(content: dict, all_tables: list, all_figures: list, proj: Path):
    """校验 chapters 中引用是否存在于已发现资产(支持子文件夹相对路径);并强制所有图全部插入正文。"""
    referenced_figs = set()  # relkey 集合
    for ci, ch in enumerate(content.get("chapters", [])):
        if "title" not in ch:
            sys.exit(f"chapters[{ci}] 缺少 title")
        check_formula(ch, f"chapters[{ci}]")
        for si, sec in enumerate(ch.get("sections", [])):
            if "title" not in sec:
                sys.exit(f"chapters[{ci}].sections[{si}] 缺少 title")
            check_formula(sec, f"chapters[{ci}].sections[{si}]")
            for key in ("table", "figure"):
                ref = sec.get(key)
                if not ref:
                    continue
                pool = all_tables if key == "table" else all_figures
                q = resolve_ref(ref, pool, proj, f"chapters[{ci}].sections[{si}].{key}")
                if key == "figure":
                    referenced_figs.add(relkey(q, proj))
    # 排除清单:仅限用户明确要求不进报告的图(如重复文件;2026-10-10 起纳排流程图默认纳入报告)
    excluded = content.get("exclude_figures", [])
    if not isinstance(excluded, list):
        sys.exit("exclude_figures 必须是文件名数组")
    excluded_keys = set()
    for name in excluded:
        q = resolve_ref(name, all_figures, proj, "exclude_figures")
        k = relkey(q, proj)
        if k in referenced_figs:
            sys.exit(f"{name} 同时出现在 exclude_figures 与正文 figure 引用中,二者矛盾")
        excluded_keys.add(k)
    # 强制规则:图目录下的每一张图(含 Figure S 系列)都必须插入报告正文,不允许只列索引
    unreferenced = [relkey(p, proj) for p in all_figures
                    if relkey(p, proj) not in referenced_figs and relkey(p, proj) not in excluded_keys]
    if unreferenced:
        sys.exit(
            "以下图文件未被 content.json 任何 section 的 figure 字段引用——"
            "规则要求所有图(含 Figure S 系列)全部插入报告正文,请补齐后重跑:\n  "
            + "\n  ".join(unreferenced)
        )
    # 缩略词对照表(可选附录):数组,每项 4 键 dict 或 ≥3 元素数组,缩写词不得为空
    for i, it in enumerate(content.get("abbreviations", [])):
        if isinstance(it, dict):
            if not str(it.get("缩写词", "")).strip():
                sys.exit(f"abbreviations[{i}] 缺少 缩写词")
        elif isinstance(it, (list, tuple)):
            if len(it) < 3 or not str(it[0]).strip():
                sys.exit(f"abbreviations[{i}] 数组形式至少 3 项(缩写词/对应英文/对应中文)且缩写词非空")
        else:
            sys.exit(f"abbreviations[{i}] 须为 dict 或数组")


def build_cover_alice(info: dict, ym: str) -> str:
    """Alice 样式封面:居中大标题 + 副标题(类型) + 数据来源行 + 信息清单 + 页底免责声明。"""
    customer = customer_label(info)
    exposure = info.get("暴露指标", "")
    outcome = info.get("结局", "")
    pairs = [
        ("研究指标：", exposure), ("研究人群：", info.get("研究人群", "")),
        ("数据来源：", info.get("数据集", "")), ("研究结局：", outcome),
    ]
    info_items = "".join(
        f'<p><span class="lbl">{html.escape(k)}</span>{html.escape(v)}</p>'
        for k, v in pairs if v
    )
    # 数据来源行:"MIMIC 数据库、eICU 数据库" → "基于MIMIC与eICU公共数据库"
    datasrc = ""
    src = info.get("数据集", "")
    if src:
        if "自有数据" in src:
            datasrc = "基于自有数据"
        else:
            parts = [s.strip() for s in re.split(r"[、,，]", re.sub(r"\s*数据库\s*", "", src)) if s.strip()]
            if parts:
                datasrc = "基于" + "与".join(parts) + "公共数据库"
    typ = info.get("类型", "中期分析结果") or "中期分析结果"
    # 2026-09-09:类型填"无"(或 - / —)时封面不渲染副标题行(标题副题已含"中期分析结果"等字样,避免重复)
    sub_p = "" if typ in ("无", "-", "—") else f'<p class="cover-subtitle">{html.escape(typ)}</p>'
    # 封面标题可用 项目信息-中期.md 的 报告标题/标题副题 覆盖(横断面之外设计,如队列研究)
    title1 = info.get("报告标题") or f"{exposure}与{outcome}的"
    phrase = info.get("标题副题") or "横断面相关性分析"
    cust_suffix = "–" + html.escape(customer) if customer else ""
    # 2026-09-09(326):标题副题填"无/-/—"= 取消主标题第二行,客户名缀主标题末行,
    # 类型值并入数据来源行尾(如"基于MIMIC-IV v3.1公共数据库–中期分析结果"),独立副标题行不再渲染。
    phrase_sup = phrase in ("无", "-", "—")
    if phrase_sup:
        title_html = f'<h1>{html.escape(title1)}{cust_suffix}</h1>'
        sub_p = ""
        if datasrc and typ not in ("无", "-", "—"):
            datasrc = f"{datasrc}–{typ}"
    else:
        title_html = f'<h1>{html.escape(title1)}</h1><h1>{html.escape(phrase)}{cust_suffix}</h1>'
    return (
        f'<div class="cover">'
        f'{title_html}'
        f'{sub_p}'
        f'<p class="datasrc">{html.escape(datasrc)}</p>'
        f'<div class="info-list">{info_items}'
        f'<p><span class="lbl">分析日期：</span>{html.escape(ym)}</p>'
        f'</div>'
        f'<div class="bottom-note">'
        f'<p class="disclaimer">本报告为中期分析结果，包含主要统计分析内容及图表。</p>'
        f'</div>'
        f'</div>'
    )


def build_toc(chapters: list, ch_pages: dict = None, sec_pages: dict = None) -> str:
    """生成目录页 HTML(table 布局)。章、小节均带页码(ch_pages={章号:页},
    sec_pages={(章号,节号):页},页码来自探针渲染的隐藏标记)。"""
    rows = []
    for ci, ch in enumerate(chapters):
        chap_num = ci + 1
        title = html.escape(ch["title"])
        pg = ch_pages.get(chap_num, "") if ch_pages else ""
        rows.append(
            f'<tr class="toc-chapter">'
            f'<td class="td-num">{chap_num}</td>'
            f'<td class="td-dots">{title}</td>'
            f'<td class="td-pg">{pg}</td></tr>'
        )
        for si, sec in enumerate(ch.get("sections", [])):
            sec_title = html.escape(sec.get("title", ""))
            spg = (sec_pages or {}).get((chap_num, si + 1), "")
            rows.append(
                f'<tr class="toc-section">'
                f'<td class="td-num">{chap_num}.{si+1}</td>'
                f'<td class="td-dots">{sec_title}</td>'
                f'<td class="td-pg">{spg}</td></tr>'
            )
    rows_html = "".join(rows)
    return f'<div class="toc-page"><h2>目录</h2><table>{rows_html}</table></div>'


def index_items_html(items: list, tbl_no: int, caption: str) -> str:
    """补充材料清单表:index_items 元素为 {编号,类型,内容说明} dict 或 3 元数组。"""
    head = ("编号", "类型", "内容说明")
    rows = []
    for it in items:
        if isinstance(it, dict):
            vals = [str(it.get(k, "")) for k in head]
        else:
            vals = ([str(v) for v in it] + ["", "", ""])[:3]
        tds = "".join(
            (f'<td class="rowhead">{html.escape(v)}</td>' if i == 0 else f"<td>{html.escape(v)}</td>")
            for i, v in enumerate(vals)
        )
        rows.append(f"<tr>{tds}</tr>")
    thead = "<thead><tr>" + "".join(f"<th>{h}</th>" for h in head) + "</tr></thead>"
    return (
        f'<div class="block">'
        f'<p class="tbl-caption">表{tbl_no}: {html.escape(caption)}</p>'
        f'<table class="data tw idx">{thead}<tbody>{"".join(rows)}</tbody></table>'
        f'</div>'
    )


ABBREV_KEYS = ("缩写词", "对应英文", "对应中文", "单位")

def build_abbreviations_block(abbrevs: list) -> str:
    """缩略词对照表(Alice 样式附录):不编号、不占"表N"、从新页开始,四列
    (缩写词/对应英文/对应中文/单位)。条目为 4 键 dict 或 ≥3 元素数组(缺单位留空)。"""
    rows = []
    for it in abbrevs:
        if isinstance(it, dict):
            vals = [str(it.get(k, "")) for k in ABBREV_KEYS]
        else:
            vals = ([str(v) for v in it] + ["", "", "", ""])[:4]
        rows.append("<tr>" + "".join(f"<td>{html.escape(v)}</td>" for v in vals) + "</tr>")
    thead = "<thead><tr>" + "".join(f"<th>{h}</th>" for h in ABBREV_KEYS) + "</tr></thead>"
    cols = ('<colgroup><col style="width:13%"><col style="width:42%">'
            '<col style="width:29%"><col style="width:16%"></colgroup>')
    return (
        f'<div class="abbrev-wrap"><div class="abbrev-head">缩略词对照表</div>'
        f'<table class="data abbrev">{cols}{thead}<tbody>{"".join(rows)}</tbody></table></div>'
    )


def formula_paras(obj: dict) -> list:
    """formula 字段(str 或 str 数组)→ 居中式行 HTML,渲染在其所属 intro 段落之后。"""
    fs = obj.get("formula", [])
    if isinstance(fs, str):
        fs = [fs]
    return [f'<p class="formula">{html.escape(x)}</p>' for x in fs]


def intro_paras(raw) -> list:
    """intro 字段规范化为段落列表。

    content.json 里 intro 常写成单个字符串；若直接 for p in intro 会按字符迭代，
    每个字变成独立 <p>，打印后呈现一字一行的「竖排」假象（2026-10 ACG 中期踩坑）。
    **禁止**在章/节渲染处写 `for p in ch.get("intro", [])`，必须经本函数。
    """
    if raw is None:
        return []
    if isinstance(raw, str):
        s = raw.strip()
        return [s] if s else []
    if isinstance(raw, (list, tuple)):
        out = []
        for x in raw:
            if x is None:
                continue
            # 列表元素若误再套一层字符迭代，仍须整段保留
            if isinstance(x, str):
                s = x.strip()
            else:
                s = str(x).strip()
            if s:
                out.append(s)
        # 守卫：≥8 个长度均为 1 的「段」→ 几乎一定是把字符串当 list 拆开了
        if len(out) >= 8 and all(len(p) == 1 for p in out):
            sys.exit(
                "intro 疑似被按字符拆成多段（一字一行竖排假象）。"
                "请传字符串或段落数组，且渲染必须走 intro_paras()。"
            )
        return out
    s = str(raw).strip()
    return [s] if s else []


def _selftest_intro_paras() -> None:
    """build 启动时跑：字符串 intro 必须整段保留，不得拆成单字。"""
    sample = "四库ICU住院人数：eICU 20,201"
    got = intro_paras(sample)
    if got != [sample]:
        sys.exit(f"intro_paras 自检失败: 字符串应保持 1 段，实际 {got!r}")
    got2 = intro_paras([sample, "第二段"])
    if got2 != [sample, "第二段"]:
        sys.exit(f"intro_paras 自检失败: 列表段落异常 {got2!r}")
    if intro_paras(None) or intro_paras("") or intro_paras("   "):
        sys.exit("intro_paras 自检失败: 空值应返回 []")


def build_chapter_blocks(content: dict, pngs: dict, proj: Path, all_tables: list, all_figures: list):
    """按 chapters 结构生成 (orientation, html) 块列表(Alice 样式)。
    表/图按全文出现顺序连续编号(表1.../图1...);每个标题内嵌隐藏 [chN]/[scN.M]
    标记(绝对定位 1pt 白字,不占版面),探针渲染用于定位页码,终稿 body.final 隐藏。"""
    blocks = []
    tbl_no = fig_no = 0

    for ci, ch in enumerate(content["chapters"]):
        chap_num = ci + 1
        html_parts = []
        html_parts.append(
            f'<div class="chapter keep-with-next"><span class="pgmark">[ch{chap_num}]</span>'
            f'{chap_num}&ensp;{html.escape(ch["title"])}</div>'
        )

        for p in intro_paras(ch.get("intro")):
            html_parts.append(f"<p>{html.escape(p)}</p>")
        html_parts.extend(formula_paras(ch))
        # 章内按节切块:宽表节(ncols>8)与其前后窄节分属横/竖版,避免混合章里宽表被挤进竖版页
        # (章标题/引言并入首节的朝向;无节的章单独成 portrait 块)
        orient = "portrait"
        has_section = False

        for si, sec in enumerate(ch.get("sections", [])):
            tbl_html = None
            if sec.get("table"):
                p = resolve_ref(sec["table"], all_tables, proj, f"第{ci+1}章第{si+1}节 table")
                cap = sec.get("caption", "")
                tbl, ncols, nrows, caps, _ = analyze_table(p, suppress_caption=True)
                tbl_no += 1
                disp = cap or (caps[0] if caps else p.stem)
                sec_orient = "landscape" if ncols > 8 else "portrait"
                if has_section and sec_orient != orient:
                    blocks.append((orient, "".join(html_parts)))
                    html_parts = []
                orient = sec_orient
                tbl_html = table_block(tbl, "", f"表{tbl_no}: {disp}", breakable=(nrows > 25))
            has_section = True
            sec_title = sec.get("title", "")
            html_parts.append('<div class="section-wrap">')
            if sec_title:
                html_parts.append(
                    f'<h3 class="keep-with-next"><span class="pgmark">[sc{chap_num}.{si+1}]</span>'
                    f'{chap_num}.{si+1}&ensp;{html.escape(sec_title)}</h3>'
                )

            for p in intro_paras(sec.get("intro")):
                html_parts.append(f'<p class="section-intro">{html.escape(p)}</p>')
            html_parts.extend(formula_paras(sec))

            if tbl_html:
                html_parts.append(tbl_html)

            if sec.get("index_items"):
                tbl_no += 1
                cap = sec.get("caption") or "补充材料清单"
                html_parts.append(index_items_html(sec["index_items"], tbl_no, cap))

            fig_open = False
            if sec.get("figure"):
                fp = resolve_ref(sec["figure"], all_figures, proj, f"第{ci+1}章第{si+1}节 figure")
                png = pngs.get(relkey(fp, proj)) or pngs.get(fp.name)
                if png:
                    fig_no += 1
                    cap = sec.get("caption") or fp.stem
                    # 图+图题+注释包成不可分块,防止 Chrome 把图题/注释甩到下页
                    html_parts.append('<div class="figblock">')
                    html_parts.append(f'<figure><img src="{_img_src(png)}"></figure>')
                    html_parts.append(f'<p class="fig-caption">图{fig_no}: {html.escape(cap)}</p>')
                    fig_open = True

            annotation = sec.get("annotation", "")
            if isinstance(annotation, list):
                annotation = "".join(annotation)
            if annotation:
                html_parts.append(f'<p class="annotation">注释：{html.escape(annotation)}</p>')

            if fig_open:
                html_parts.append("</div>")
            html_parts.append("</div>")

        blocks.append((orient, "".join(html_parts)))

    return blocks


def figure_block(fig_path: Path, png_path: Path, summary_html: str) -> str:
    return (
        f'<p class="fig-title">{html.escape(fig_path.stem)}</p>'
        f'<figure><img src="{_img_src(png_path)}"></figure>'
        f'<div class="summary">{summary_html}</div>'
    )


def table_block(html_table: str, summary_html: str, title: str, breakable: bool) -> str:
    # 表自带 caption(标题行)时不再额外显示标题/文件名,避免重复;无 caption 才用文件名兜底
    cls = "block breakable" if breakable else "block"
    head = f'<p class="tbl-caption">{html.escape(title)}</p>' if title else ""
    return (
        f'<div class="{cls}">{head}{html_table}'
        f'<div class="summary">{summary_html}</div></div>'
    )


def _img_src(png: Path) -> str:
    """Windows 浏览器读不了 file:///tmp 或 file:///mnt。打印走 .exe 时改成盘符 URI。"""
    browser = find_browser()
    if _is_windows_browser(browser):
        return _browser_html_arg(browser, png)
    return png.as_uri()


def find_browser() -> str:
    for c in BROWSER_CANDIDATES:
        if Path(c).exists():
            return c
    sys.exit("找不到 Chrome/Edge,无法打印 PDF")


def _is_windows_browser(browser: str) -> bool:
    return Path(browser).name.lower().endswith(".exe")


def _wsl_win_path(path: Path) -> str:
    r = subprocess.run(["wslpath", "-w", str(path)], capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        sys.exit(f"wslpath 失败,无法交给 Windows 浏览器: {path}")
    return r.stdout.strip()


def _browser_html_arg(browser: str, html_path: Path) -> str:
    if not _is_windows_browser(browser):
        return html_path.as_uri()
    win = _wsl_win_path(html_path).replace("\\", "/")
    return "file:///" + win.replace(" ", "%20")


def _browser_pdf_arg(browser: str, pdf_path: Path) -> str:
    if not _is_windows_browser(browser):
        return str(pdf_path)
    return _wsl_win_path(pdf_path)


def print_pdf(browser: str, html_path: Path, pdf_path: Path):
    is_hs = Path(browser).name.startswith("chrome-headless-shell")  # 本身即 headless,无需也不应传 --headless*
    is_win = _is_windows_browser(browser)
    cmd = [browser, "--disable-gpu", "--no-pdf-header-footer",
           f"--print-to-pdf={_browser_pdf_arg(browser, pdf_path)}",
           "--virtual-time-budget=20000", _browser_html_arg(browser, html_path)]
    if not is_hs:
        cmd.insert(1, "--headless=new")
    if sys.platform.startswith("linux") and not is_win:
        cmd.insert(1, "--no-sandbox")  # playwright 缓存的 Chromium 非 root 必需
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if not pdf_path.exists() and not is_hs:
        cmd[1] = "--headless"  # 旧版 Chrome/Edge 回退
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if not pdf_path.exists():
        sys.exit(f"浏览器打印失败: {r.stderr[:500]}")


def split_blocks_by_orient(blocks: list) -> list:
    """按方向连续块切分成打印作业,返回 [(html_path, landscape), ...]。"""
    jobs, buf, buf_land = [], [], False
    def flush():
        if buf:
            h = buf[0][0]  # reuse tmp ref; see caller
            jobs.append(("".join(f for _, f in buf), buf_land))
            buf.clear()
    for orient, frag in blocks:
        if orient == "portrait":
            if buf_land:
                flush()
            buf.append((orient, frag)); buf_land = False
        else:
            if not buf_land and buf:
                flush()
            buf.append((orient, frag)); buf_land = True
    flush()
    return jobs


def render_blocks(tmp: Path, blocks: list, final: bool = False) -> Path:
    """渲染 blocks 到单个 PDF,返回 PDF 路径。final=True 时 body 带 final 类(隐藏探针标记)。"""
    browser = find_browser()
    orient_jobs = split_blocks_by_orient(blocks)
    pdfs = []
    for idx, (html_str, landscape) in enumerate(orient_jobs):
        h = tmp / f"pass_{idx}.html"
        h.write_text(html_doc(html_str, landscape, final=final), encoding="utf-8")
        pdf = tmp / f"pass_{idx}.pdf"
        print_pdf(browser, h, pdf)
        pdfs.append(pdf)
    final = fitz.open()
    for p in pdfs:
        final.insert_pdf(fitz.open(p))
    out = tmp / "combined.pdf"
    final.save(str(out), garbage=4, deflate=True)
    final.close()
    return out


def analyze_figure_merge(figures: list) -> dict:
    """分析图片拼接情况,返回 {filename: {"merged": bool, "ratio": float}}。"""
    result = {}
    for p in figures:
        try:
            d = fitz.open(p)
            w, h = d[0].rect.width, d[0].rect.height
            ratio = w / h if h else 1
            merged = ratio > 1.3 or ratio < 0.6
            result[p.name] = {"merged": merged, "ratio": round(ratio, 2),
                              "note": "已拼接" if merged else "单图"}
            d.close()
        except Exception:
            result[p.name] = {"merged": False, "ratio": 1.0, "note": "未知"}
    return result


def extract_marker_pages(pdf_path: Path, markers: list) -> dict:
    """从探针 PDF 中定位各隐藏标记([chN]/[scN.M])所在页,返回 {marker: page_number}。
    单次顺序扫描,已命中的标记不再查找。"""
    doc = fitz.open(pdf_path)
    pages = {}
    remaining = set(markers)
    for page_idx in range(len(doc)):
        if not remaining:
            break
        page = doc[page_idx]
        for m in list(remaining):
            if page.search_for(m):
                pages[m] = page_idx + 1
                remaining.discard(m)
    doc.close()
    return pages


def bottom_end_note(browser: str, h: Path, pdf: Path, body_str: str, landscape: bool):
    """结尾声明贴底:作业打印后实测"分析日期"行底部与内容区底(页高−底边距2.2cm)的差距,
    把 end-spacer 占位 div 垫到该高度后重印,使声明紧贴最后一页页底(与正文同页,不另起一页)。
    目标留 7pt 余量(声明段落的底边距+排版取整),垫高若把声明整个段落盒挤出内容区(页数+1)
    则将垫高减半重试;找不到声明或已贴近页底(delta<3pt)时保持原样。"""
    doc = fitz.open(pdf)
    npages, ph = doc.page_count, doc[-1].rect.height
    bottom = 0.0
    for blk in doc[-1].get_text("dict")["blocks"]:
        for ln in blk.get("lines", []):
            # Chrome Type3 子集字体逐字成 span,"分析日期"不会完整出现在单 span 内;
            # 须按行拼接后匹配,否则 bottom=0 直接返回、声明不贴底
            if "分析日期" in "".join(sp["text"] for sp in ln["spans"]):
                bottom = max(bottom, max(sp["bbox"][3] for sp in ln["spans"]))
    doc.close()
    delta_pt = (ph - 62.4 - 7.0) - bottom
    if bottom == 0.0 or delta_pt < 3:
        return

    def pad_pdf(pt):
        padded = body_str.replace('style="height:0px"',
                                  f'style="height:{int(pt / 0.75)}px"', 1)
        h.write_text(html_doc(padded, landscape, final=True), encoding="utf-8")
        print_pdf(browser, h, pdf)
        d = fitz.open(pdf)
        same = d.page_count == npages
        d.close()
        return same

    # 全量垫高会把声明段落盒(含底边距)挤出内容区,Chrome 整段推到新页(页数+1)。
    # 此时二分搜索"不换页"的最大垫高,最大化贴底幅度(全量可容纳则 pad_pdf 已是最优)。
    if not pad_pdf(delta_pt):
        lo, hi = 0.0, delta_pt
        for _ in range(12):
            mid = (lo + hi) / 2
            if pad_pdf(mid):
                lo = mid
            else:
                hi = mid
        if lo > 0.05:
            pad_pdf(lo)


def stamp_page_headers(doc: fitz.Document, header_text: str):
    """合并后给除封面外的每页盖页眉与页码(目录页计为第 1 页;横版页按各自版面右对齐)。
    CJK 字体缺失时警告并跳过,不中断构建。"""
    try:
        font = fitz.Font("cjk")
    except Exception as e:
        print(f"[警告] 无可用 CJK 字体,跳过页眉页码: {e}", file=sys.stderr)
        return
    for i in range(1, doc.page_count):
        page = doc[i]
        r = page.rect
        # Chrome 打印的内容流末尾残留未复位的缩放矩阵(约0.24),直接追加文字会被缩小并移位
        # (10.5pt→2.5pt、(71,48)→(17,190))。先归一化内容流再盖章。
        page.clean_contents()
        tw = fitz.TextWriter(page.rect)
        tw.append(fitz.Point(71, 48), header_text, font=font, fontsize=10.5)
        num = str(i)
        w = font.text_length(num, fontsize=10.5)
        tw.append(fitz.Point(r.width - 71 - w, 48), num, font=font, fontsize=10.5)
        tw.write_text(page, color=(0.25, 0.25, 0.25))
        # 页眉下横线:与页眉同色 0.5pt,横贯正文宽(基线 48 + 字降 ≈50.2,线放 53.5 留出间隙)
        page.draw_line(fitz.Point(71, 53.5), fitz.Point(r.width - 71, 53.5),
                       color=(0.25, 0.25, 0.25), width=0.5)


# ---------------------------------------------------------------- build

def cmd_build(args):
    _selftest_intro_paras()
    if not args.project:
        sys.exit("build 模式需要 --project <项目目录>")
    proj = Path(args.project).resolve()
    info = parse_project_md(proj)

    def safe_name(s):
        return re.sub(r'[/\\:*?"<>|]', ' ', s)

    # 输出路径提前确定:重跑时上一版报告 PDF 若落在资产扫描范围内,须从图池剔除,
    # 否则会被"全图入正文"校验当成未嵌入的图而报错
    # 2026-10-10 用户定(398 起因):缺省文件名=<客户老师>中期分析结果.pdf,客户名按项目信息照录;
    # 客户为空时回退旧拼接(去客户括号段),此时仍建议 --out 显式给名
    _cust = customer_label(info)
    if _cust:
        _default_pdf = f"{safe_name(_cust)}中期分析结果.pdf"
    else:
        _default_pdf = (
            f"{safe_name(info.get('暴露指标', ''))}_{safe_name(info.get('结局', ''))}_"
            f"{safe_name(info.get('分析方法', ''))}_中期分析结果.pdf"
        )
    out = Path(args.out) if args.out else proj / _default_pdf
    out_resolved = out.resolve()
    tdir, fdir = asset_dirs(proj, info)
    main_t, main_f, supp_t, supp_f = discover(tdir, fdir)
    main_f = [p for p in main_f if p.resolve() != out_resolved]
    supp_f = [p for p in supp_f if p.resolve() != out_resolved]
    content = json.loads(Path(args.content).read_text(encoding="utf-8"))
    has_chapters = "chapters" in content
    if has_chapters:
        validate_chapters(content, main_t + supp_t, main_f + supp_f, proj)

    summaries = content.get("summaries", {})
    if not has_chapters:
        # 旧格式:每个资产都要有简介
        missing = [p.name for p in main_t + main_f + supp_t + supp_f if p.name not in summaries]
        if missing:
            sys.exit("content.json 缺少以下文件的简介,补齐后重跑:\n  " + "\n  ".join(missing))

    if _is_windows_browser(find_browser()):
        tmp = proj / "_report_build_tmp"
        if tmp.exists():
            shutil.rmtree(tmp, ignore_errors=True)
        tmp.mkdir()
    else:
        tmp = Path(tempfile.mkdtemp(prefix="report_"))
    try:
        # 图 → PNG(键为相对项目目录的 posix 路径;文件名唯一时另设裸名别名)
        pngs = {}
        for p in main_f + supp_f:
            d = fitz.open(p)
            pix = d[0].get_pixmap(matrix=fitz.Matrix(2.5, 2.5))
            png = tmp / (p.stem[:40].replace(" ", "_") + f"_{len(pngs)}.png")
            pix.save(png)
            if len(d) > 1:
                print(f"[警告] {p.name} 有 {len(d)} 页,仅嵌入首页", file=sys.stderr)
            d.close()
            pngs[relkey(p, proj)] = png
        name_ct = {}
        for p in main_f + supp_f:
            name_ct[p.name] = name_ct.get(p.name, 0) + 1
        for p in main_f + supp_f:
            if name_ct[p.name] == 1:
                pngs[p.name] = pngs[relkey(p, proj)]

        def para_html(key):
            vals = content.get(key) or []
            if isinstance(vals, str):
                vals = [vals]
            return "".join(f"<p>{html.escape(v)}</p>" for v in vals)

        def summ_html(name):
            return "".join(f"<p>{html.escape(v)}</p>" for v in ([summaries[name]] if isinstance(summaries[name], str) else summaries[name]))

        customer = customer_label(info)
        today = date.today().strftime("%Y-%m-%d")

        # ---------- 组块序列 ----------
        if has_chapters:
            # Alice 样式:探针渲染(定位页码) → 终稿渲染(目录带页码) → 合并后盖页眉页码
            chapter_blocks = build_chapter_blocks(content, pngs, proj, main_t + supp_t, main_f + supp_f)
            now = date.today()
            ymd = f"{now.year}年{now.month}月{now.day}日"
            # 结尾声明并入最后一个竖版作业紧跟正文;先以 0 高占位渲染,
            # 打印后按实测差距垫高占位(bottom_end_note)把声明推到当页页底
            end_note = ('portrait',
                        '<div class="end-spacer" style="height:0px"></div>'
                        '<div class="end-note">'
                        '<p>本报告为中期分析结果，最终结论以正式交付为准。</p>'
                        f'<p>分析日期：{ymd}</p></div>')

            # 探针渲染:封面 + 目录(页码留空) + 章节一起打印,前置分页与终稿完全一致
            # (目录超过一页也不会导致页码错位);标记 [chN]/[scN.M] 落在各自标题所在页
            probe_pdf = render_blocks(
                tmp,
                [("portrait", build_cover_alice(info, ymd)),
                 ("portrait", build_toc(content["chapters"]))] + chapter_blocks,
                final=False)
            markers = [f"[ch{ci+1}]" for ci in range(len(content["chapters"]))]
            markers += [f"[sc{ci+1}.{si+1}]"
                        for ci, ch in enumerate(content["chapters"])
                        for si in range(len(ch.get("sections", [])))]
            mp = extract_marker_pages(probe_pdf, markers)
            # 显示页码 = 物理页 - 1(封面不编号,目录物理页2=显示页1)
            ch_pages, sec_pages = {}, {}
            for ci, ch in enumerate(content["chapters"]):
                m = f"[ch{ci+1}]"
                if m in mp:
                    ch_pages[ci + 1] = mp[m] - 1
                for si in range(len(ch.get("sections", []))):
                    m2 = f"[sc{ci+1}.{si+1}]"
                    if m2 in mp:
                        sec_pages[(ci + 1, si + 1)] = mp[m2] - 1

            # 终稿渲染:封面 + 目录(带页码) + 章节 + 结尾声明(标记隐藏)
            blocks = [("portrait", build_cover_alice(info, ymd))]
            blocks.append(("portrait", build_toc(content["chapters"], ch_pages, sec_pages)))
            blocks.extend(chapter_blocks)
            # 缩略词对照表:全部章节之后、结尾声明之前(不进目录、不占章节/表编号)
            if content.get("abbreviations"):
                blocks.append(("portrait", build_abbreviations_block(content["abbreviations"])))
            blocks.append(end_note)
        else:
            # 旧样式:封面 + 4 大板块
            meta_rows = "".join(
                f'<tr><td class="k">{html.escape(k)}</td><td>{html.escape(v)}</td></tr>'
                for k, v in [
                    ("客户", customer), ("暴露指标", info.get("暴露指标", "")),
                    ("结局", info.get("结局", "")), ("分析方法", info.get("分析方法", "")),
                    ("数据集", info.get("数据集", "")), ("报告类型", info.get("类型", "中期分析结果")),
                ])
            cover = (
                f'<div class="cover"><h1>中期分析结果报告</h1>'
                f'<p class="sub-title">{html.escape(info.get("暴露指标", ""))} 与 {html.escape(info.get("结局", ""))} 的关联性分析</p>'
                f'<table class="meta-table">{meta_rows}</table>'
                f'<p class="date">报告日期:{today}</p></div>'
                f'<h2>一、项目信息与解读</h2>{para_html("project_intro")}'
                f'<h2>二、分析结论总结</h2>{para_html("conclusion")}'
            )

            blocks = [("portrait", cover)]
            blocks.append(("portrait", '<h2>三、主要结果</h2>'))

            for p in main_t:
                tbl, ncols, nrows, caps, _ = analyze_table(p)
                blk = table_block(tbl, summ_html(p.name), "" if caps else p.stem, breakable=(nrows > 25))
                blocks.append(("landscape" if ncols > 8 else "portrait", blk))

            for p in main_f:
                blocks.append(("portrait", figure_block(p, pngs[p.name], summ_html(p.name))))

            supp_head = '<h2>四、补充材料</h2>' + (f'<p>{html.escape(content["supplement_intro"])}</p>' if content.get("supplement_intro") else "")
            first_supp = True
            for p in supp_t:
                tbl, ncols, nrows, caps, _ = analyze_table(p)
                head = supp_head if first_supp else ""
                first_supp = False
                blk = table_block(tbl, summ_html(p.name), "" if caps else p.stem, breakable=(nrows > 25))
                blocks.append(("landscape" if ncols > 8 else "portrait", head + blk))

            for p in supp_f:
                head = supp_head if first_supp else ""
                first_supp = False
                blocks.append(("portrait", head + figure_block(p, pngs[p.name], summ_html(p.name))))

        # ---------- 按方向切分成打印作业(暂存 HTML 字符串,打印时再落盘) ----------
        jobs = []  # (body_str, landscape)
        buf, buf_land = [], False

        def flush():
            if buf:
                jobs.append(("".join(buf), buf_land))
                buf.clear()

        for orient, frag in blocks:
            if orient == "landscape":
                if not buf_land and buf:
                    flush()
                buf.append(frag); buf_land = True
            else:  # portrait
                if buf_land:
                    flush()
                buf.append(frag); buf_land = False
        flush()

        # ---------- 打印 + 合并(封装可重跑,供出厂闸门自动重试)----------
        browser = find_browser()

        def render_all():
            pdfs = []
            for i, (body_str, land) in enumerate(jobs):
                h = tmp / f"doc_{i}.html"
                h.write_text(html_doc(body_str, land, final=has_chapters), encoding="utf-8")
                pdf = tmp / f"part_{i}.pdf"
                print_pdf(browser, h, pdf)
                # 含结尾声明的作业:测量后垫高占位把声明推到当页页底,重印该作业
                if has_chapters and "end-spacer" in body_str:
                    bottom_end_note(browser, h, pdf, body_str, land)
                pdfs.append(pdf)
            merged = fitz.open()
            for p in pdfs:
                merged.insert_pdf(fitz.open(p))
            if has_chapters:
                header = ((info.get("报告标题") or
                           (info.get("暴露指标", "").strip() + "与" + info.get("结局", "").strip()))
                          + "——中期分析结果")
                stamp_page_headers(merged, header)
            return merged

        expected_figures = sum(frag.count("<figure><img") for _, frag in blocks)
        final = render_all()
        final.save(str(out), garbage=4, deflate=True)
        n = final.page_count
        final.close()

        # ---------- 结果检查清单(出厂闸门):FAIL 先自动重打一次,仍 FAIL 拦下 ----------
        results, n_fail, retryable = run_checklist(out, content=content, expected_figures=expected_figures)
        if n_fail and retryable:
            print("[出厂闸门] 命中打印类缺陷(C02/C03),自动重打一次…", flush=True)
            final = render_all()
            final.save(str(out), garbage=4, deflate=True)
            final.close()
            results, n_fail, _ = run_checklist(out, content=content, expected_figures=expected_figures)
        print_checklist(results)
        if n_fail:
            rej = out.with_name(out.stem + ".REJECTED.pdf")
            out.rename(rej)
            sys.exit(f"[出厂闸门] {n_fail} 项 FAIL:检查未通过,成品已改名 {rej.name}(不得交付);"
                     f"按上方明细修复后重 build")
        print(f"报告已生成: {out}  (共 {n} 页,{len(jobs)} 个打印作业,出厂闸门 {len(results)} 项检查通过)")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ======================= 结果检查清单(出厂闸门,2026-10-10 起)=======================
# 起因:398 标题编号 ⊠ 乱码(Chrome Type3 合成粗体子集 Encoding 损坏)出厂未被拦截。
# 清单持续新增:每项一个 check,新增须同步 SKILL.md「结果检查清单」表 + 技能 changelog。

AI_TRACE_WORDS = ["彰显", "至关重要", "体现了", "展现了"]          # C07;与 step05 痕迹表对齐,持续新增
PLACEHOLDER_WORDS = ["AUTHOR_INPUT_NEEDED", "TODO:", "FIXME", "lorem", "待插入", "待填入", "待补:", "待填:"]
PATH_LEAK_WORDS = ["/tmp/", "file://", "/home/", "C:\\Users", "report_"]
RETRYABLE_IDS = {"C02", "C03"}  # 打印/字体类缺陷:自动重打一次可能自愈


def _walk_strs(obj):
    if isinstance(obj, str):
        yield obj
    elif isinstance(obj, dict):
        for v in obj.values():
            yield from _walk_strs(v)
    elif isinstance(obj, list):
        for v in obj:
            yield from _walk_strs(v)


def _squash(s: str) -> str:
    return re.sub(r"\s+", "", s)


def run_checklist(pdf_path, content=None, expected_figures=None):
    """对成品 PDF 跑检查清单。返回 (results, n_fail, retryable_fail)。
    results = [(cid, title, status, detail)];status ∈ PASS/WARN/FAIL/SKIP。
    C02/C03 为 398 乱码坑主探针;C01–C10 为首批,后续按项目教训持续新增。"""
    content = content or {}
    doc = fitz.open(pdf_path)
    results = []

    def add(cid, title, ok, detail="", skip=False, warn=False):
        status = "SKIP" if skip else ("WARN" if warn else ("PASS" if ok else "FAIL"))
        results.append((cid, title, status, detail))

    try:
        page_texts = [doc[i].get_text() for i in range(len(doc))]
        full = "\n".join(page_texts)
        squash = _squash(full)
        ctrl_hits, img_xrefs = [], set()
        for i in range(len(doc)):
            for x in doc[i].get_images(full=True):
                img_xrefs.add(x[0])
            for b in doc[i].get_text("dict")["blocks"]:
                for l in b.get("lines", []):
                    for s in l["spans"]:
                        if any(ord(c) < 32 and c not in "\t\n\r" for c in s["text"]):
                            ctrl_hits.append((i + 1, repr(s["text"][:24])))
        chapters = content.get("chapters") or []

        add("C01", "页数完整", doc.page_count >= 1, f"共 {doc.page_count} 页")
        add("C02", "文本层零控制字符(乱码探针)", not ctrl_hits,
            ("; ".join(f"p{p}:{t}" for p, t in ctrl_hits[:5])) or "无")
        miss_no = [ch.get("title", "") for ch in chapters
                   if re.sub(r"\s+", "", ch.get("title", ""))
                   and not re.search(r"\d" + re.escape(re.sub(r"\s+", "", ch["title"])), squash)]
        add("C03", "章标题带数字编号", not miss_no,
            ("缺编号: " + "; ".join(miss_no[:4])) if miss_no else "全部命中", skip=not chapters)
        if expected_figures is None:
            add("C04", "图嵌入数=应嵌数", True, "无 expected 值(--verify 传 --figures 可启用)", skip=True)
        else:
            add("C04", "图嵌入数=应嵌数", len(img_xrefs) == expected_figures,
                f"应嵌 {expected_figures} / 实嵌 {len(img_xrefs)}")
        tokens = set(re.findall(r"\d+(?:[.,]\d+)*", "".join(_walk_strs(content))))
        miss_t = sorted(t for t in tokens if _squash(t) not in squash)
        add("C05", "数字 token 全入 PDF", len(miss_t) <= 2,
            (f"未命中 {len(miss_t)}: " + ", ".join(miss_t[:10])) if miss_t else f"{len(tokens)} 个全命中",
            warn=0 < len(miss_t) <= 2)
        if not chapters:
            add("C06", "目录条目带页码", True, "旧样式无目录", skip=True)
        else:
            # 目录溢出到第 2 页时，只读含“目录”的那一页会把后半章判成缺页码。
            toc_chunks = []
            started = False
            first_title = _squash(chapters[0].get("title", "")) if chapters else ""
            for t in page_texts[:8]:
                sq = _squash(t)
                if not started:
                    if "目录" in sq:
                        started = True
                        toc_chunks.append(sq)
                    continue
                if first_title and first_title in sq and ("注释" in sq or len(sq) > 500):
                    break
                toc_chunks.append(sq)
            toc_txt = "".join(toc_chunks)
            miss_p = [ch.get("title", "") for ch in chapters
                      if not re.search(re.escape(re.sub(r"\s+", "", ch.get("title", ""))) + r"[.\s]*\d", toc_txt)]
            add("C06", "目录条目带页码", not miss_p,
                ("缺页码: " + "; ".join(miss_p[:4])) if miss_p else "全部带页码")
        hits_w = [w for w in AI_TRACE_WORDS if w in full]
        add("C07", "AI 痕迹词零残留", not hits_w, ("; ".join(hits_w)) or "无")
        hits_p = [w for w in PATH_LEAK_WORDS if w in full]
        add("C08", "路径泄漏零", not hits_p, ("; ".join(hits_p)) or "无")
        hits_h = [w for w in PLACEHOLDER_WORDS if w in full]
        add("C09", "占位符零残留", not hits_h, ("; ".join(hits_h)) or "无")
        if content.get("abbreviations"):
            add("C10", "缩略词表在版", "缩略词" in full, "" if "缩略词" in full else "未找到缩略词表头")
        else:
            add("C10", "缩略词表在版", True, "无缩略词配置", skip=True)
    finally:
        doc.close()
    n_fail = sum(1 for r in results if r[2] == "FAIL")
    retryable = any(r[0] in RETRYABLE_IDS and r[2] == "FAIL" for r in results)
    return results, n_fail, retryable


def print_checklist(results, only_issues=True):
    print("—— 结果检查清单(出厂闸门)——")
    for cid, title, status, detail in results:
        mark = {"PASS": "✅", "FAIL": "❌", "WARN": "⚠️ ", "SKIP": "—"}[status]
        if status == "PASS" and only_issues:
            print(f"  {mark} {cid} {title}")
        else:
            print(f"  {mark} {cid} {title}: {detail} [{status}]")


def cmd_verify(args):
    content = json.loads(Path(args.content).read_text(encoding="utf-8")) if args.content else {}
    results, n_fail, _ = run_checklist(Path(args.pdf), content=content,
                                       expected_figures=getattr(args, "figures", None))
    print_checklist(results, only_issues=False)
    if n_fail:
        sys.exit(f"verify: {n_fail} 项 FAIL,不得交付")


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass
    ap = argparse.ArgumentParser(description="中期分析报告 PDF 引擎")
    ap.add_argument("--inspect", dest="mode", action="store_const", const="inspect")
    ap.add_argument("--build", dest="mode", action="store_const", const="build")
    ap.add_argument("--verify", dest="mode", action="store_const", const="verify")
    ap.add_argument("--project", help="项目目录(含 项目信息-中期.md,回退 项目信息.md)")
    ap.add_argument("--content", help="build/verify 模式:content.json 路径")
    ap.add_argument("--out", help="输出路径(inspect 的 dump / build 的 pdf)")
    ap.add_argument("--pdf", help="verify 模式:待检 PDF 路径")
    ap.add_argument("--figures", type=int, help="verify 模式:应嵌图数(可选,启用 C04)")
    args = ap.parse_args()
    if args.mode == "inspect":
        cmd_inspect(args)
    elif args.mode == "build":
        if not args.content:
            sys.exit("build 模式需要 --content content.json")
        cmd_build(args)
    elif args.mode == "verify":
        if not args.pdf:
            sys.exit("verify 模式需要 --pdf 待检 PDF 路径")
        cmd_verify(args)
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
