# Task 1 Report: `export_pub_figures` 核心（TDD）

## Status

**DONE_WITH_CONCERNS**

## TDD Evidence

### RED (Step 2 — `R/pub_figure_export.R` 不存在)

```bash
cd /mnt/e/01block/01Block-new-Final && Rscript tests/test_pub_figure_export.R
```

```
Error: file.exists(file.path(root, "R/pub_figure_export.R")) is not TRUE
Execution halted
```

Exit code: **1**（符合预期）

### GREEN (Step 5 — 全部断言通过)

```bash
cd /mnt/e/01block/01Block-new-Final && Rscript tests/test_pub_figure_export.R
```

```
null device 
          1 
null device 
          1 
[1] TRUE
test_pub_figure_export: OK
```

Exit code: **0**（符合预期）

## Files Created

| Action | Path |
|--------|------|
| Create | `tests/test_pub_figure_export.R` |
| Create | `python/pub_figure_rasterize.py` |
| Create | `R/pub_figure_export.R` |

## Implementation Summary

### `python/pub_figure_rasterize.py`

- 与 brief 逐字一致。
- 渲染优先级：`pypdfium2` → `pdftoppm`（Poppler）+ Pillow。
- TIFF 输出使用 `compression="tiff_lzw"`，PNG 为 RGB。

### `R/pub_figure_export.R`

- 与 brief 一致，导出三个公开函数：
  - `export_pub_figures(figures_dir, meta, config)`
  - `pub_figure_write_image_md(md_path, stem, meta, tech)`
  - `pub_figure_ensure_format_dirs(figures_dir)`
- 行为要点：
  - 顶层 `Figure*.pdf|png` → 四子目录（`pdf/`、`png/`、`tiff/`、`image_information/`），顶层无散落图。
  - `Missing Value Overview` 文件删除，不进四目录。
  - 每图写 `.md` + 汇总 `README.md`；meta 中 `grouping` 由调用方注入（测试用 `quartile`）。
  - 返回 `invisible(list(exported=, missing_raster=, md=))`。

### 偏离 brief 的最小修复（WSL / 含空格路径）

**`.pub_figure_rasterize_one`**：brief 使用 `system2("python3", args, stdout=TRUE, stderr=TRUE)`。在本机 WSL2 上，当 `stdout/stderr` 非 `FALSE` 时 R 走 shell，路径如 `Figure 1. Flowchart.pdf` 在空格处被拆分，栅格化失败。改为：

```r
cmd <- paste("python3", shQuote(script), "--pdf", shQuote(pdf_path), ...)
status <- system(paste(cmd, "2>", shQuote(err)))
```

**测试 LZW 校验块**：brief 的 `system2(..., stdout=TRUE)` 对 `-c` 脚本同样因 shell 未加引号失败。改为 `system(paste("python3 -c", shQuote(...)), intern=TRUE)`。

## Dependencies

| 组件 | 状态 |
|------|------|
| `python3` | `/usr/bin/python3` |
| Pillow (`PIL`) | 已安装 |
| `pdftoppm` (poppler-utils) | 已安装 |
| `pypdfium2` | 未安装；走 pdftoppm 回退，测试通过 |

无需额外 pip/apt 安装。

## Self-Review

| 检查项 | 结果 |
|--------|------|
| TDD：先写测试、RED 后实现、GREEN 通过 | ✓ |
| 四子目录创建 | ✓ |
| PDF 复制 + PNG/TIFF 栅格化 | ✓ |
| TIFF LZW（PIL 读得 `tiff_lzw`） | ✓ |
| `image_information/*.md` 含 BAR / Death / quartile / LZW | ✓ |
| Missing Value Overview 不进 `pdf/` | ✓ |
| 顶层无散落 `.pdf/.png/.tiff` | ✓ |
| Python 脚本与 brief 逐字一致 | ✓ |
| R 主体与 brief 一致（栅格调用处最小偏离） | ✓（见 Concerns） |
| 未执行 git commit | ✓ |

## Concerns

1. **路径含空格 + `system2(stdout=TRUE)`**：brief 中 R 栅格调用与测试末尾 PIL 检查在 WSL2 上不通过；已用 `shQuote` + `system()` 最小修复。上游 Linux/macOS CI 若同样走 shell，可能需相同处理；若 `system2` 无 shell 则原 brief 代码亦可。
2. **`pypdfium2` 未装**：当前依赖 Poppler 回退；生产环境建议两者至少其一可用。
3. **`tech$width/height`**：暂写「未记录」；后续任务可从 PDF 页盒读取。
4. **测试 LZW 块非 brief 逐字**：仅为通过本机 shell 引号问题；其余测试与 brief 一致。

## Commits

none（workspace 无 `.git`，按 global constraints 跳过）
