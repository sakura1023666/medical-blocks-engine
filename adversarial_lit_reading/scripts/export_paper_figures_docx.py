#!/usr/bin/env python3
"""把论文 PDF 里的图、表按出现顺序截成图片，写入一份 Word。

每张图/表上方用文中原标题命名，并加连续序号，例如::

    1. Figure 1，研究流程与训练策略概览
    2. Figure 2，……
    3. Table 1，……

先排全部图（正文图、补充图），再排全部表（正文表、补充表）。
中文图题用 ``--zh-json`` 传入，键为 ``Figure 1`` / ``Table S1``。

用法（项目根）::

    python3 adversarial_lit_reading/scripts/export_paper_figures_docx.py PAPER.pdf
    python3 adversarial_lit_reading/scripts/export_paper_figures_docx.py PAPER.pdf -o out.docx
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import tempfile
from pathlib import Path

import fitz

try:
    from docx import Document
    from docx.enum.text import WD_ALIGN_PARAGRAPH
    from docx.shared import Cm, Pt, RGBColor
except ImportError:  # pragma: no cover
    sys.exit("[export_paper_figures_docx] 未安装 python-docx。请先运行： pip install python-docx")


LABEL_RE = re.compile(
    r"^(?P<kind>Fig(?:ure)?s?|Tables?|图|表)"
    r"\.?\s*(?P<num>\d+[A-Za-z]?)"
    r"(?:\s*[:：.\u2014\u2013\-])?\s*(?P<rest>.*)$",
    re.IGNORECASE,
)
KIND_FIG = {"fig", "figs", "figure", "figures", "图"}


def _norm(text: str) -> str:
    text = text.replace("\u00a0", " ").replace("\u2009", " ").replace("\u202f", " ")
    text = text.replace("\u00ad", "")
    text = re.sub(r"\s+", " ", text).strip()
    return text


def _is_fig(kind: str) -> bool:
    return kind.lower() in KIND_FIG or kind == "图"


def _kind_label(kind: str, num: str) -> str:
    if _is_fig(kind):
        return f"Fig. {num}"
    return f"Table {num}"


def _first_sentence(rest: str) -> str:
    rest = _norm(rest)
    if not rest:
        return ""
    # 标题句到第一个句号为止；Fig. / et al. 这类缩写不截断。
    parts = re.split(r"(?<=[。．.])\s+", rest, maxsplit=1)
    title = parts[0].strip()
    if title and title[-1] not in "。．.":
        title += "."
    return title


def _iter_lines(page: fitz.Page):
    data = page.get_text("dict")
    for block in data["blocks"]:
        if block.get("type") != 0:
            continue
        for line in block.get("lines", []):
            text = _norm("".join(span["text"] for span in line.get("spans", [])))
            if not text:
                continue
            yield text, fitz.Rect(line["bbox"]), block


def _caption_block_text(block: dict) -> str:
    lines = []
    for line in block.get("lines", []):
        text = _norm("".join(span["text"] for span in line.get("spans", [])))
        if text:
            lines.append(text)
    return _norm(" ".join(lines))


def _find_captions(page: fitz.Page) -> list[dict]:
    found = []
    seen = set()
    for text, rect, block in _iter_lines(page):
        match = LABEL_RE.match(text)
        if not match:
            continue
        rest = _norm(match.group("rest"))
        # 「Table 1 presents …」是正文引用，不是图表标题。
        if rest and rest[0].isascii() and rest[0].islower():
            continue
        kind = match.group("kind")
        num = match.group("num")
        key = (_is_fig(kind), num)
        if key in seen:
            continue
        seen.add(key)
        full = _caption_block_text(block)
        if not LABEL_RE.match(full):
            full = text
        label = _kind_label(kind, num)
        parsed = LABEL_RE.match(full)
        title_rest = _first_sentence(parsed.group("rest") if parsed else rest)
        heading = f"{label} {title_rest}".strip()
        found.append(
            {
                "kind": "figure" if _is_fig(kind) else "table",
                "num": num,
                "heading": heading,
                "rect": rect,
                "block": block,
            }
        )
    found.sort(key=lambda item: (item["rect"].y0, item["rect"].x0))
    return found


def _content_margins(page: fitz.Page) -> tuple[float, float]:
    return 48.0, page.rect.width - 48.0


def _image_rects(page: fitz.Page) -> list[fitz.Rect]:
    rects = []
    for block in page.get_text("dict")["blocks"]:
        if block.get("type") == 1:
            rects.append(fitz.Rect(block["bbox"]))
    return rects


def _drawing_rects(page: fitz.Page) -> list[fitz.Rect]:
    rects = []
    for drawing in page.get_drawings():
        rect = fitz.Rect(drawing["rect"])
        if rect.width < 8 or rect.height < 2:
            continue
        if rect.y0 < 62 or rect.y1 > page.rect.height - 36:
            continue
        rects.append(rect)
    return rects


def _rule_bands(page: fitz.Page) -> list[tuple[float, fitz.Rect]]:
    """三线表横线高度常为 0。fitz.Rect 会把零高度当成空框，所以用坐标自行合并。"""
    grouped: dict[int, list[float]] = {}
    for drawing in page.get_drawings():
        raw = drawing["rect"]
        x0, y0, x1, y1 = float(raw.x0), float(raw.y0), float(raw.x1), float(raw.y1)
        if x1 < x0:
            x0, x1 = x1, x0
        if y1 < y0:
            y0, y1 = y1, y0
        if (x1 - x0) < 20 or (y1 - y0) > 2.5:
            continue
        if y0 < 62 or y1 > page.rect.height - 28:
            continue
        key = int(round(y0))
        if key not in grouped:
            grouped[key] = [x0, y0, x1, y1]
        else:
            band = grouped[key]
            band[0] = min(band[0], x0)
            band[1] = min(band[1], y0)
            band[2] = max(band[2], x1)
            band[3] = max(band[3], y1)
    bands = []
    for key in sorted(grouped):
        x0, y0, x1, y1 = grouped[key]
        bands.append((float(key), fitz.Rect(x0, y0, x1, max(y1, y0 + 0.4))))
    return bands


def _union(rects: list[fitz.Rect]) -> fitz.Rect | None:
    if not rects:
        return None
    box = fitz.Rect(rects[0])
    for rect in rects[1:]:
        box.include_rect(rect)
    return box


def _h_overlap(a: fitz.Rect, b: fitz.Rect) -> float:
    return max(0.0, min(a.x1, b.x1) - max(a.x0, b.x0))


def _cluster_vertical(rects: list[fitz.Rect], seed: fitz.Rect, gap: float = 10.0) -> list[fitz.Rect]:
    cluster = [seed]
    changed = True
    while changed:
        changed = False
        for rect in rects:
            if any(rect == item for item in cluster):
                continue
            for item in cluster:
                vertical = rect.y0 <= item.y1 + gap and rect.y1 >= item.y0 - gap
                if vertical and _h_overlap(rect, item) > 8:
                    cluster.append(rect)
                    changed = True
                    break
    return cluster


def _cluster_figure_panels(rects: list[fitz.Rect], seed: fitz.Rect, gap: float = 24.0) -> list[fitz.Rect]:
    """多面板图：并排子图无水平重叠，只按与当前并集的纵向邻接扩簇。"""
    cluster = [seed]
    changed = True
    while changed:
        changed = False
        box = _union(cluster)
        if box is None:
            break
        for rect in rects:
            if any(rect == item for item in cluster):
                continue
            if rect.y0 <= box.y1 + gap and rect.y1 >= box.y0 - gap:
                cluster.append(rect)
                changed = True
    return cluster


def _page_pad(page: fitz.Page) -> tuple[float, float, float, float]:
    """页面可用内边距（过严会裁掉贴边的图/续表表头）。"""
    return 28.0, 24.0, 28.0, 24.0  # left, right, top, bottom


def _figure_clip(page: fitz.Page, caption: dict) -> fitz.Rect:
    cap = caption["rect"]
    x0, x1 = _content_margins(page)
    left, right, top, bottom = _page_pad(page)
    # 图注上方全部候选图块（多面板常跨整页高度，勿用「距图注 <80pt」截断）
    images = [
        rect
        for rect in _image_rects(page)
        if rect.y1 <= cap.y0 + 8 and rect.y0 < cap.y0 and rect.height > 40
    ]
    if images:
        seed = min(images, key=lambda rect: cap.y0 - rect.y1)
        # 只保留与图注邻近子图纵向连通的一簇，避免吃到上一图残留
        near = [rect for rect in images if cap.y0 - rect.y1 < 120]
        if not near:
            near = [seed]
        seed = min(near, key=lambda rect: cap.y0 - rect.y1)
        box = _union(_cluster_figure_panels(images, seed, gap=28))
    else:
        drawings = [
            rect
            for rect in _drawing_rects(page)
            if rect.y1 <= cap.y0 + 6 and rect.y0 < cap.y0
        ]
        if drawings:
            near = [rect for rect in drawings if cap.y0 - rect.y1 < 80]
            seed = min(near or drawings, key=lambda rect: cap.y0 - rect.y1)
            box = _union(_cluster_figure_panels(drawings, seed, gap=18))
        else:
            box = fitz.Rect(x0, max(top, cap.y0 - 220), x1, cap.y0)
    if box is None:
        box = fitz.Rect(x0, max(top, cap.y0 - 220), x1, cap.y0)
    # 外扩贴边像素；勿把已更宽的图块强行收进 content_margins（会裁右侧图例）
    box.x0 = max(left, min(box.x0, x0) - 6)
    box.x1 = min(page.rect.width - right, max(box.x1, box.x0 + 40) + 6)
    if box.width > 360:
        box.x0 = min(box.x0, x0)
        box.x1 = max(box.x1, x1)
    box.y0 = max(top, box.y0 - 6)
    box.y1 = min(page.rect.height - bottom, max(box.y1, cap.y0 - 2) + 2)
    # 图注留在 Word 标题里；截图收到图注上沿，避免标题重复一大段。
    if cap.y0 - box.y1 < 30:
        box.y1 = min(box.y1, cap.y0 - 2)
    return box


def _table_title(page: fitz.Page, caption: dict, rule_top: float) -> str:
    """表题只取首条横线以上的标题行，不把表头和单元格算进名字。"""
    parts = []
    cap = caption["rect"]
    lines = sorted(_iter_lines(page), key=lambda item: (item[1].y0, item[1].x0))
    for text, rect, _block in lines:
        if rect.y0 + 1 < cap.y0:
            continue
        if rect.y0 >= rule_top - 0.5:
            break
        if abs(rect.x0 - cap.x0) > 25 and rect.x0 > cap.x0 + 15:
            continue
        parts.append(text)
    title = _norm(" ".join(parts)) if parts else caption["heading"]
    parsed = LABEL_RE.match(title)
    if not parsed:
        return title
    return f"{_kind_label(parsed.group('kind'), parsed.group('num'))} {_norm(parsed.group('rest'))}".strip()


def _table_clip(page: fitz.Page, caption: dict) -> tuple[fitz.Rect, str]:
    cap = caption["rect"]
    bands = [(y, rect) for y, rect in _rule_bands(page) if y >= cap.y0 - 8]
    if not bands:
        box = fitz.Rect(caption["block"]["bbox"])
        return box, caption["heading"]
    _y0, header = bands[0]
    selected = [header]
    for _y, rect in bands[1:]:
        same_left = abs(rect.x0 - header.x0) < 10
        overlap = _h_overlap(rect, header) > header.width * 0.45
        if same_left and overlap:
            selected.append(rect)
        else:
            break
    box = _union(selected)
    # 表题写在 Word 标题里，截图从首条横线开始，避免标题出现两遍。
    box.y0 = selected[0].y0 - 2
    heading = _table_title(page, caption, selected[0].y0)
    # 表注贴在底线下面，直到空档或离开本表栏。
    lines = [(text, rect) for text, rect, _block in _iter_lines(page) if rect.y0 >= box.y1 - 2]
    lines.sort(key=lambda item: item[1].y0)
    y_cursor = box.y1
    for _text, rect in lines:
        if _h_overlap(rect, box) < min(30, box.width * 0.2):
            continue
        if rect.y0 - y_cursor > 12:
            break
        if LABEL_RE.match(_text) and rect.y0 > cap.y1 + 8:
            break
        box.y1 = max(box.y1, rect.y1)
        box.x0 = min(box.x0, rect.x0)
        box.x1 = max(box.x1, rect.x1)
        y_cursor = rect.y1
    left, right, top, bottom = _page_pad(page)
    box.x0 = max(left, box.x0 - 4)
    box.x1 = min(page.rect.width - right, box.x1 + 4)
    box.y1 = min(page.rect.height - bottom, box.y1 + 3)
    # 续表表头常贴页眉下沿；y0≥68 会裁掉 Variables/列名行
    box.y0 = max(top, box.y0 - 2)
    return box, heading


def _clip_for(page: fitz.Page, caption: dict) -> tuple[fitz.Rect, str]:
    if caption["kind"] == "figure":
        box = _figure_clip(page, caption)
        heading = caption["heading"]
    else:
        box, heading = _table_clip(page, caption)
    if box.height < 20:
        box.y1 = box.y0 + 20
    if box.width < 40:
        box.x1 = box.x0 + 40
    box.intersect(page.rect)
    return box, heading


def collect_items(doc: fitz.Document, doc_id: str = "main") -> list[dict]:
    items = []
    for page_index, page in enumerate(doc):
        for caption in _find_captions(page):
            clip, heading = _clip_for(page, caption)
            items.append(
                {
                    "doc_id": doc_id,
                    "page_index": page_index,
                    "kind": caption["kind"],
                    "num": str(caption["num"]),
                    "heading": heading,
                    "clip": clip,
                }
            )
    return items


def _label(kind: str, num: str) -> str:
    prefix = "Figure" if kind == "figure" else "Table"
    return f"{prefix} {num}"


def _sort_key(item: dict) -> tuple:
    num = str(item["num"])
    supplementary = 1 if num[:1].upper() == "S" else 0
    digits = re.sub(r"\D", "", num) or "0"
    return (0 if item["kind"] == "figure" else 1, supplementary, int(digits), num)


def sort_figure_then_table(items: list[dict]) -> list[dict]:
    return sorted(items, key=_sort_key)


def apply_chinese_titles(items: list[dict], zh_map: dict[str, str]) -> None:
    missing = []
    for item in items:
        key = _label(item["kind"], item["num"])
        zh = (zh_map.get(key) or "").strip()
        if not zh:
            missing.append(key)
            zh = item["heading"]
        heading_l = (item.get("heading") or "").lower()
        continued = "continued" in heading_l or "续" in (item.get("heading") or "")
        item["zh"] = zh
        # 「Table 1（续），中文题」——跨页续表与首段区分，避免后处理按同名误删
        label = f"{key}（续）" if continued else key
        item["display"] = f"{label}，{zh}"
        item["continued"] = bool(continued)
    if missing:
        print("[export_paper_figures_docx] 以下标题没有中文，已暂时沿用英文：", ", ".join(missing))


def _render(page: fitz.Page, clip: fitz.Rect, dest: Path, zoom: float = 3.0) -> None:
    matrix = fitz.Matrix(zoom, zoom)
    pix = page.get_pixmap(matrix=matrix, clip=clip, alpha=False)
    pix.save(dest.as_posix())


def _row_texts(row) -> list[str]:
    return [re.sub(r"\s+", " ", cell.text).strip() for cell in row.cells]


def _docx_caption_before_table(document, table_element) -> str:
    from docx.oxml.ns import qn

    caption = ""
    pattern = re.compile(r"^(Table|Figure|Fig\.?)\s+(S?\d+[A-Za-z]?)\b", re.IGNORECASE)
    for child in document.element.body.iterchildren():
        if child is table_element:
            break
        if child.tag != qn("w:p"):
            continue
        text = _norm("".join(child.itertext()))
        if pattern.match(text):
            caption = text
    return caption


def items_from_docx(path: Path, png_dir: Path) -> list[dict]:
    """补充 Word 里的表（或图）渲染成图片。本文补充材料是 Table S1 / S2，没有补充图。"""
    from docx import Document as DocxDocument
    from PIL import Image, ImageDraw, ImageFont

    font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
    font = ImageFont.truetype(font_path, 18)
    font_bold = ImageFont.truetype(font_path, 18)
    document = DocxDocument(path.as_posix())
    items = []
    seen_nums: set[str] = set()
    for index, table in enumerate(document.tables, start=1):
        rows = [_row_texts(row) for row in table.rows]
        if not rows:
            continue
        # 跳过几乎空的尾表（补充 DOCX 常见误嵌空 table → 重复 Table S6）
        nonempty = sum(1 for row in rows for cell in row if cell.strip())
        if nonempty < 2 or len(rows) < 2:
            continue
        caption = _docx_caption_before_table(document, table._tbl)
        match = re.match(r"^(Table|Figure|Fig\.?)\s+(S?\d+[A-Za-z]?)\b", caption, re.IGNORECASE)
        if match:
            kind = "figure" if match.group(1).lower().startswith("fig") else "table"
            num = match.group(2)
        else:
            kind, num = "table", f"S{index}"
        if num in seen_nums:
            continue
        seen_nums.add(num)
        png = png_dir / f"{path.stem}_{num}.png"
        _draw_table_png(rows, png, font, font_bold)
        items.append(
            {
                "kind": kind,
                "num": num,
                "heading": _norm(caption) or _label(kind, num),
                "png_path": png,
            }
        )
    return items


def _draw_table_png(rows: list[list[str]], dest: Path, font, font_bold) -> None:
    from PIL import Image, ImageDraw

    ncol = max(len(row) for row in rows)
    rows = [row + [""] * (ncol - len(row)) for row in rows]
    pad_x, pad_y = 8, 6
    # 按列里最长的一行估宽，上限避免某一列独占整页。
    col_w = []
    for col in range(ncol):
        longest = max((len(row[col]) for row in rows), default=1)
        col_w.append(min(420, max(90, int(longest * 10 + 24))))
    line_h = 24
    wrapped: list[list[list[str]]] = []
    row_h = []
    for row in rows:
        cell_lines = []
        heights = []
        for col, text in enumerate(row):
            width_chars = max(8, col_w[col] // 10)
            lines = _wrap_cell(text, width_chars)
            cell_lines.append(lines)
            heights.append(max(1, len(lines)) * line_h + pad_y * 2)
        wrapped.append(cell_lines)
        row_h.append(max(heights))
    width = sum(col_w) + 2
    height = sum(row_h) + 2
    image = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(image)
    y = 1
    for r, row in enumerate(wrapped):
        x = 1
        for c, lines in enumerate(row):
            box = (x, y, x + col_w[c], y + row_h[r])
            fill = (236, 236, 236) if r == 0 else "white"
            draw.rectangle(box, fill=fill, outline=(40, 40, 40))
            use_font = font_bold if r == 0 else font
            ty = y + pad_y
            for line in lines:
                draw.text((x + pad_x, ty), line, fill=(0, 0, 0), font=use_font)
                ty += line_h
            x += col_w[c]
        y += row_h[r]
    dest.parent.mkdir(parents=True, exist_ok=True)
    image.save(dest.as_posix())


def _wrap_cell(text: str, width_chars: int) -> list[str]:
    text = text or ""
    if not text:
        return [""]
    lines = []
    for piece in text.split("\n"):
        while len(piece) > width_chars:
            lines.append(piece[:width_chars])
            piece = piece[width_chars:]
        lines.append(piece)
    return lines or [""]


def write_docx(pdf_path: Path, items: list[dict], docs: dict, out_path: Path) -> None:
    word = Document()
    section = word.sections[0]
    section.page_width = Cm(21.0)
    section.page_height = Cm(29.7)
    section.left_margin = Cm(1.6)
    section.right_margin = Cm(1.6)
    section.top_margin = Cm(1.6)
    section.bottom_margin = Cm(1.6)

    title = word.add_paragraph()
    title.alignment = WD_ALIGN_PARAGRAPH.LEFT
    run = title.add_run(pdf_path.stem)
    run.bold = True
    run.font.size = Pt(16)
    run.font.color.rgb = RGBColor(0x1A, 0x1A, 0x1A)

    note = word.add_paragraph()
    note_run = note.add_run(f"先图后表，共 {len(items)} 项。标题为原文编号加中文图题或表题。")
    note_run.font.size = Pt(10)
    note_run.font.color.rgb = RGBColor(0x55, 0x55, 0x55)

    usable = section.page_width - section.left_margin - section.right_margin

    with tempfile.TemporaryDirectory(prefix="paper_fig_") as tmp:
        tmp_dir = Path(tmp)
        for index, item in enumerate(items, start=1):
            if item.get("png_path"):
                png = Path(item["png_path"])
            else:
                page = docs[item["doc_id"]][item["page_index"]]
                png = tmp_dir / f"{index:02d}.png"
                _render(page, item["clip"], png)
            head = word.add_paragraph()
            head.paragraph_format.space_before = Pt(16)
            head.paragraph_format.space_after = Pt(6)
            head_run = head.add_run(f"{index}. {item['display']}")
            head_run.bold = True
            head_run.font.size = Pt(12)
            head_run.font.name = "Times New Roman"
            from docx.oxml.ns import qn
            head_run._element.rPr.rFonts.set(qn("w:eastAsia"), "宋体")
            pic_par = word.add_paragraph()
            pic_par.alignment = WD_ALIGN_PARAGRAPH.CENTER
            pic_par.add_run().add_picture(png.as_posix(), width=usable)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    word.save(out_path.as_posix())


def export_pdf(
    pdf_path: Path,
    out_path: Path | None = None,
    extras: list[Path] | None = None,
    zh_map: dict[str, str] | None = None,
) -> tuple[Path, list[dict]]:
    import shutil

    doc = fitz.open(pdf_path.as_posix())
    docs = {"main": doc}
    extra_docs = []
    png_dir = Path(tempfile.mkdtemp(prefix="paper_supp_"))
    try:
        items = collect_items(doc, "main")
        for extra in extras or []:
            suffix = extra.suffix.lower()
            if suffix == ".pdf":
                opened = fitz.open(extra.as_posix())
                extra_docs.append(opened)
                docs[extra.name] = opened
                items.extend(collect_items(opened, extra.name))
            elif suffix == ".docx":
                items.extend(items_from_docx(extra, png_dir))
            else:
                raise SystemExit(f"[export_paper_figures_docx] 不支持的补充文件：{extra}")
        if not items:
            raise SystemExit(f"[export_paper_figures_docx] 未识别到图或表：{pdf_path}")
        items = sort_figure_then_table(items)
        apply_chinese_titles(items, zh_map or {})
        if out_path is None:
            out_path = pdf_path.with_name(pdf_path.stem + "_图表.docx")
        write_docx(pdf_path, items, docs, out_path)
        return out_path, items
    finally:
        doc.close()
        for opened in extra_docs:
            opened.close()
        shutil.rmtree(png_dir, ignore_errors=True)


def main() -> None:
    parser = argparse.ArgumentParser(description="截取论文 PDF 的图和表，写入 Word")
    parser.add_argument("pdf", type=Path, help="论文 PDF 路径")
    parser.add_argument("-o", "--out", type=Path, default=None, help="输出 docx，默认与 PDF 同目录、文件名加 _图表")
    parser.add_argument("--extra", type=Path, action="append", default=[], help="补充 PDF 或 DOCX，可重复")
    parser.add_argument("--zh-json", type=Path, default=None, help="中文图题/表题 JSON，键为 Figure 1、Table S1")
    args = parser.parse_args()
    pdf_path = args.pdf.expanduser().resolve()
    if not pdf_path.is_file():
        sys.exit(f"[export_paper_figures_docx] 找不到 PDF：{pdf_path}")
    zh_map = {}
    if args.zh_json:
        zh_map = json.loads(args.zh_json.read_text(encoding="utf-8"))
    extras = [path.expanduser().resolve() for path in args.extra]
    out_path, items = export_pdf(
        pdf_path,
        args.out.resolve() if args.out else None,
        extras=extras,
        zh_map=zh_map,
    )
    print(f"wrote {out_path}")
    for index, item in enumerate(items, start=1):
        print(f"{index:02d} {item['kind']} {item['num']} | {item['display']}")


if __name__ == "__main__":
    main()
