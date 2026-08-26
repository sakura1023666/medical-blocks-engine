# Task 1 Gate Review: `export_pub_figures` 核心

**Reviewer:** task-scoped gate (read-only)  
**Package:** `.superpowers/sdd/pubfig-task-1-review-pkg.md`  
**Date:** 2026-08-20

---

## 1. Spec compliance

**Verdict: PASS**

### Required deliverables (present)

| Item | Status |
|------|--------|
| `tests/test_pub_figure_export.R` | ✓ |
| `python/pub_figure_rasterize.py` | ✓ |
| `R/pub_figure_export.R` | ✓ |

### Public interfaces (match brief)

| Function | Contract | Verified |
|----------|----------|----------|
| `export_pub_figures(figures_dir, meta, config)` | → `invisible(list(exported=, missing_raster=, md=))` | ✓ |
| `pub_figure_write_image_md(md_path, stem, meta, tech)` | writes one `.md` | ✓ |
| `pub_figure_ensure_format_dirs(figures_dir)` | returns four named paths | ✓ |

### Behavioral requirements (from brief test + global constraints)

| Requirement | Verified in package |
|-------------|---------------------|
| 四子目录 `pdf/` / `png/` / `tiff/` / `image_information/` | ✓ |
| 顶层 `Figure*.pdf` → 复制 + 栅格化 + 写 md，顶层无散落图 | ✓ |
| `Missing Value Overview` 删除，不进 `pdf/` | ✓ |
| TIFF LZW + RGB（Python `compression="tiff_lzw"`，PIL 校验块） | ✓ |
| md 含调用方注入的 `exposure` / `outcome` / `grouping`（非写死 tertile） | ✓ |
| md 技术段含 LZW | ✓ |
| `image_information/README.md` 索引 | ✓ |
| 栅格失败记 `missing_raster` + cli 告警，PDF 仍保留 | ✓（代码路径） |
| 未执行 git commit | ✓（符合 global constraints） |

### Deviations from brief literal code (not missing scope)

- **`.pub_figure_rasterize_one`**：brief 用 `system2("python3", args, stdout=TRUE, stderr=TRUE)`；实现改为 `system(paste(..., shQuote(...)))` 以处理含空格路径（报告已说明）。
- **测试 LZW 块**：brief 用 `system2(..., stdout=TRUE)`；实现改为 `system(paste("python3 -c", shQuote(...)), intern=TRUE)`（同上原因）。
- **Step 6 commit + design doc**：global constraints 禁止 commit；design doc 已存在于 repo，非 Task 1 新建项。

### Out of scope (correctly not implemented in Task 1)

- 多库拼图 / `remove_singles` / 分库底稿隔离（后续任务）
- step 级中间图改造
- 默认 DPI=300 的独立断言（测试显式传 `dpi=72`，配置默认仍为 300）

**Missing:** 无  
**Extra (documented):** shell 化 `system()` 调用两处

---

## 2. Task quality

**Verdict: Approved**

实现与 brief/设计 spec 对齐，TDD 证据链（RED→GREEN）在报告中可信且与包内容一致；Python 脚本与 brief 逐字一致；R 主体除栅格调用外与 brief 一致。Task 1 范围内质量可接受。

---

## 3. Findings

### Important

1. **栅格调用走 shell `system()`**（`R/pub_figure_export.R` L132–145）：对含空格 stem 必要，但比 brief 的 `system2` 更依赖 shell 引号行为；建议在后续 CI/README 注明，或评估 `system2(..., stdout=FALSE, stderr=FALSE)` + 向量 args（无 shell）是否可跨平台统一。
2. **`pypdfium2` 未安装时仅依赖 Poppler 回退**：测试环境可过，生产需保证 Poppler 或 pypdfium2 至少其一可用（报告已披露）。

### Minor

3. **测试与 brief Step 1 非逐字**：仅 LZW 校验块改用 `system()`；功能等价，但与 TDD「先写指定测试」字面略有偏离。
4. **`tech$width` / `tech$height` 固定「未记录」**：符合 brief 占位，后续任务可读 PDF 页盒补全。
5. **`.pub_figure_cfg()` 用 `formats_dir` 键控制 `enable`**：命名易混淆，但来自 brief 原文，非本任务引入。
6. **非 `Figure*` 顶层文件不会被清理**：仅处理/删除 `Figure*` 与 Missing Overview；与测试范围一致，全量「仅四子目录」清理由上游拼图任务保证。

### Critical

无。

---

## 4. Verification notes

- 对照来源：`pubfig-task-1-brief.md`、`pubfig-global-constraints.md`、`pubfig-task-1-report.md`、`pubfig-task-1-review-pkg.md`。
- 未重跑测试套件（审查指令要求）。
- 包内三文件与 workspace 路径 `R/`、`python/`、`tests/` 一致。

---

## 5. Summary

| Dimension | Verdict |
|-----------|---------|
| Spec compliance | **PASS** |
| Task quality | **Approved** |

Task 1 核心导出能力、三格式目录、image_information 与全局约束（Missing Overview 排除、grouping 注入、无 git commit）均已满足；两处 shell 引号修复为合理最小偏离，应在后续集成/CI 中关注。
