#!/usr/bin/env python3
"""PDF -> Markdown 分块转换脚本（医学文献对抗式阅读用）。

来源：操作手册第 11.2 章「可选 PDF 切分脚本思路」的强化版。

功能
----
- 扫描 ``papers/*.pdf``，按文件名排序后依次赋予稳定 paper_id（paper_001, paper_002 ...）。
- 用 PyMuPDF (fitz) 抽取每页文本，每页加 ``# Page N`` 标题，合并为单个 Markdown。
- 输出到 ``chunks/paper_NNN_<slug>.md``（slug 由文件名清洗而来，纯 ASCII、无空格括号）。
- 同时写/更新 ``papers/index.md``：paper_id ↔ 完整标题 ↔ 作者/年份。

依赖
----
- PyMuPDF::  pip install pymupdf

用法
----
    python3 scripts/pdf_to_chunks.py            # 处理 papers/ 下全部 PDF
    python3 scripts/pdf_to_chunks.py paper_002  # 只处理指定 paper_id
    python3 scripts/pdf_to_chunks.py --root /path/to/adversarial_lit_reading
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

try:
    import fitz  # PyMuPDF
except ImportError:  # pragma: no cover
    sys.exit(
        "[pdf_to_chunks] 未安装 PyMuPDF。请先运行： pip install pymupdf"
    )


def slugify(text: str) -> str:
    """把含中文/空格/特殊字符的文件名清洗成 ASCII slug。"""
    # 取文件名主体（去扩展名）
    text = Path(text).stem
    # 抽出 4 位年份（若有）
    year = re.search(r"(19|20)\d{2}", text)
    # 去掉 "Xu 等 - 2024 - " 之类前缀里的中文与「等」
    # 提取所有 ASCII 字母/数字词
    ascii_words = re.findall(r"[A-Za-z0-9]+", text)
    slug = "_".join(w.lower() for w in ascii_words if len(w) > 1 or w.isdigit())
    if year:
        slug = f"{year.group(0)}_{slug}" if slug else year.group(0)
    slug = re.sub(r"[^a-z0-9_]+", "_", slug).strip("_")
    # 压缩多重下划线
    slug = re.sub(r"_+", "_", slug).strip("_")
    return slug or "untitled"


def extract_pages(pdf_path: Path) -> tuple[str, int, str]:
    """返回 (全文 markdown, 页数, 元数据里的标题)。"""
    doc = fitz.open(pdf_path)
    parts: list[str] = []
    title = ""
    for i, page in enumerate(doc, start=1):
        text = page.get_text("text") or ""
        parts.append(f"\n\n# Page {i}\n\n{text.strip()}")
        if i == 1 and not title:
            # 取首页最长的一行当作粗略标题
            lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
            title = max(lines, key=len) if lines else pdf_path.stem
    meta = doc.metadata or {}
    if meta.get("title"):
        title = meta["title"]
    full = "".join(parts).strip() + "\n"
    doc.close()
    return full, len(parts), title


def parse_author_year(filename: str, meta: dict) -> tuple[str, str]:
    """从文件名 'Xu 等 - 2024 - ...' 解析作者姓与年份。"""
    stem = Path(filename).stem
    year = ""
    m_year = re.search(r"(19|20)\d{2}", stem)
    if m_year:
        year = m_year.group(0)
    author = ""
    m_author = re.match(r"\s*([A-Za-z]+)", stem)
    if m_author:
        author = m_author.group(1)
    if meta.get("author"):
        author = author or meta["author"].split(",")[0].strip()
    return author, year


def title_from_filename(filename: str) -> str:
    """从 'Author 等 - Year - <Title>.pdf' 解析真实标题。

    Zotero/Zotero 风格命名：'Xu 等 - 2024 - Is systemic inflammation ... Evidence from.pdf'
    取作者+年份之后的部分作为标题，去掉常见尾缀碎片。
    """
    stem = Path(filename).stem
    parts = [p.strip() for p in re.split(r"\s*-\s*", stem)]
    # 跳过开头的「作者」与「年份」两段
    title_parts = [p for p in parts if p and not re.fullmatch(r"[A-Za-z]+ 等?", p)
                   and not re.fullmatch(r"(19|20)\d{2}", p)]
    title = " - ".join(title_parts) if title_parts else stem
    # 折叠成单行并规整空白
    title = re.sub(r"\s+", " ", title).strip()
    return title


def main() -> int:
    ap = argparse.ArgumentParser(description="把 papers/*.pdf 转成 chunks/*.md")
    ap.add_argument(
        "--root",
        default=str(Path(__file__).resolve().parents[1]),
        help="adversarial_lit_reading 根目录（默认：脚本上一级目录）",
    )
    ap.add_argument("only", nargs="?", help="只处理指定 paper_id，如 paper_002",
                    default=None)
    args = ap.parse_args()

    root = Path(args.root)
    papers_dir = root / "papers"
    chunks_dir = root / "chunks"
    chunks_dir.mkdir(parents=True, exist_ok=True)

    pdfs = sorted(papers_dir.glob("*.pdf"))
    if not pdfs:
        print(f"[pdf_to_chunks] 未在 {papers_dir} 找到 PDF。")
        return 0

    index_rows: list[str] = ["| paper_id | 标题 | 作者 | 年份 | chunk 文件 |",
                             "|---|---|---|---|---|"]
    count = 0
    for idx, pdf in enumerate(pdfs, start=1):
        paper_id = f"paper_{idx:03d}"
        if args.only and args.only != paper_id:
            continue
        full, npages, title = extract_pages(pdf)
        author, year = parse_author_year(pdf.name, fitz.open(pdf).metadata or {})
        # 优先用文件名里的真实标题（页面「最长行」常误取到版权声明等噪音）
        fn_title = title_from_filename(pdf.name)
        title = fn_title or title
        slug = slugify(pdf.name)
        out_name = f"{paper_id}_{slug}.md" if slug else f"{paper_id}.md"
        out_path = chunks_dir / out_name
        out_path.write_text(full, encoding="utf-8")
        index_rows.append(
            f"| {paper_id} | {title.strip()[:120]} | {author} | {year} | chunks/{out_name} |"
        )
        print(f"[pdf_to_chunks] {paper_id}  {pdf.name}  ->  {out_path.relative_to(root)}  ({npages} 页, {len(full)} 字符)")
        count += 1

    (papers_dir / "index.md").write_text(
        "# papers/index.md\n\n论文 paper_id 清单（由 pdf_to_chunks.py 自动生成）。\n\n"
        + "\n".join(index_rows) + "\n",
        encoding="utf-8",
    )
    print(f"[pdf_to_chunks] 完成，共处理 {count} 篇；索引已写入 papers/index.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
