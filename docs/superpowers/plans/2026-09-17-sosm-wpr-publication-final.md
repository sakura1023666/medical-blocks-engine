# SOSM+WPR Publication Final Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 从既有 SOSM+WPR 双库结果生成编号唯一、双库图已拼版、表格角色清晰的独立 SCI 终稿目录。

**Architecture:** 新增可复用的 ML dual literature-first 终稿构建模块。模块只读取成功指标目录及其分库 step 产物，先按语义角色解析来源，再生成 Figures 1–12、Tables 1–5/S1–S10、四格式图与来源清单；不修改模型、不覆盖原始结果。

**Tech Stack:** R 4.5、`pdftools`/公共 PDF A-B 拼图函数、`openxlsx`、`R/pub_figure_export.R`、`R/pub_xlsx_surgical.R`、基础 CSV manifest。

## Global Constraints

- 只处理 `by_index/【success】SOSM+WPR/`；不修改其余 9 个组合。
- 输出固定为 `publication_final/`，原 `Tables/`、`Figures/` 和 step 结果只读。
- MIMIC-IV 为 Panel A，eICU 为 Panel B。
- 双库图终稿只保留一个无数据库后缀的 A/B PDF。
- Boruta、SHAP 仅使用 MIMIC-IV；三集 ML 图直接复用，不额外拼图。
- 所有终稿图走 `pdf/png/tiff/image_information` 四目录。
- 已有 xlsx 不整表覆盖；新终稿工作簿从来源表读取后新建，并执行 `pub_xlsx_verify()`。
- 当前目录不是 Git 仓库；计划中的检查点以测试通过和 MANIFEST 落盘代替 commit。

---

### Task 1: 定义终稿角色映射与纯函数测试

**Files:**
- Create: `R/ml_dual_literature_final.R`
- Create: `tests/test_ml_dual_literature_final.R`

**Interfaces:**
- Consumes: 指标根路径、config、组合名。
- Produces: `ml_dual_literature_figure_spec()`、`ml_dual_literature_table_spec()`；均返回含 `order/role/title/db_mode/source_pattern` 的 data.frame。

- [ ] **Step 1: 写失败测试**

测试必须断言：

```r
fig <- ml_dual_literature_figure_spec()
stopifnot(identical(fig$order, 1:12))
stopifnot(fig$db_mode[fig$order == 2] == "paired")
stopifnot(fig$db_mode[fig$order == 7] == "primary")
stopifnot(fig$db_mode[fig$order == 8] == "three_set")

tab <- ml_dual_literature_table_spec()
stopifnot(identical(tab$main_no, 1:5))
stopifnot(identical(tab$supp_no, 1:10))
```

- [ ] **Step 2: 运行失败测试**

Run:

```bash
Rscript tests/test_ml_dual_literature_final.R
```

Expected: FAIL，提示终稿映射函数不存在。

- [ ] **Step 3: 实现固定映射**

Figure 角色严格为：

```r
c(
  "flowchart", "joint_km", "rcs", "comparator_roc", "landmark",
  "subgroup", "boruta", "three_set_roc", "three_set_calibration",
  "three_set_metrics", "three_set_dca", "shap"
)
```

Table 主文角色严格为：

```r
c("baseline_primary", "joint_cox_paired", "ml_train", "ml_internal", "ml_external")
```

补充角色严格为：

```r
c(
  "baseline_external", "train_internal_baseline", "univariate_cox",
  "vif", "comparator_roc_paired", "ph_paired", "hyperparameters",
  "logloss", "delong", "nri_idi"
)
```

- [ ] **Step 4: 运行测试并确认通过**

Expected: `ROLE_SPEC_OK figures=12 main_tables=5 supplementary=10`。

---

### Task 2: 实现语义来源解析与完整性闸门

**Files:**
- Modify: `R/ml_dual_literature_final.R`
- Modify: `tests/test_ml_dual_literature_final.R`

**Interfaces:**
- Produces: `ml_dual_literature_resolve_sources(index_root, config)`。
- Return: list(`figures`, `tables`, `missing`, `duplicates`)。

- [ ] **Step 1: 增加 fixture 模式测试**

对 SOSM+WPR 真实目录运行只读解析，断言：

```r
x <- ml_dual_literature_resolve_sources(index_root, config)
stopifnot(nrow(x$figures) == 12L)
stopifnot(!length(x$missing))
stopifnot(x$figures$n_source[x$figures$role == "joint_km"] == 2L)
stopifnot(x$figures$n_source[x$figures$role == "three_set_roc"] == 1L)
```

- [ ] **Step 2: 实现来源优先级**

解析必须使用内容角色，不依赖旧图号。关键来源：

```r
joint_km       = "*Kaplan-Meier curves of joint SOSM and WPR groups.pdf"
rcs            = "*RCS Analysis*SOSM*Mortality*AKI.pdf"
comparator_roc = "*ROC comparison of joint indices and APSIII.pdf"
landmark       = "*Day 7 landmark analysis by Diabetes.pdf"
subgroup       = "*Subgroup Forest analyses of SOSM.pdf"
boruta         = "*Boruta.pdf"
three_set_roc  = "*ML ROC training internal and external.pdf"
```

分库来源优先从 `MIMIC_IV/step*/` 与 `eICU/step*/` 取；聚合目录只用于三集图和 Flowchart，避免把已重编号图再次误配。

- [ ] **Step 3: 增加硬失败**

任一必需角色缺失、paired 角色不是恰好 MIMIC-IV+eICU、或单源角色多于一个时停止，错误列出 role 和候选路径，不静默选错。

- [ ] **Step 4: 运行测试**

Expected: `SOURCE_RESOLUTION_OK missing=0 duplicates=0`。

---

### Task 3: 构建 Figure 1–12 并统一四格式

**Files:**
- Modify: `R/ml_dual_literature_final.R`
- Modify: `tests/test_ml_dual_literature_final.R`

**Interfaces:**
- Produces: `ml_dual_literature_build_figures(index_root, final_root, config, dry_run=FALSE)`。
- Depends on: `pub_figure_combine_ab_pdfs()`、`pub_figure_ensure_formats()`、`pub_figure_refresh_image_information()`。

- [ ] **Step 1: 写 dry-run 测试**

断言 dry-run manifest 恰有 12 行、Figure 编号为 1–12、paired 角色标记 `MIMIC_IV|eICU`。

- [ ] **Step 2: 实现 paired 图**

Figure 1–6 中 paired 角色调用公共 A/B 合图：

```r
pub_figure_combine_ab_pdfs(
  left_pdf  = mimic_pdf,
  right_pdf = eicu_pdf,
  output_pdf = target,
  panel_labels = c("A", "B"),
  panel_titles = c("MIMIC-IV", "eICU")
)
```

Flowchart 若已是双栏成图则直接复制为 Figure 1，不再次嵌套。

- [ ] **Step 3: 实现单源/三集图**

- Figure 7：MIMIC-IV Boruta。
- Figure 8–11：现有三集 ROC/校准/指标/DCA。
- Figure 12：MIMIC-IV SHAP。

复制时统一改名，不改 PDF 内容。

- [ ] **Step 4: 导出四格式与 image information**

调用：

```r
pub_figure_ensure_formats(
  file.path(final_root, "Figures"),
  meta = list(
    exposure = "SOSM+WPR",
    outcome = "28-day all-cause mortality",
    databases = c("MIMIC-IV", "eICU"),
    combined = TRUE,
    grouping = "median × median (Group1-4)"
  ),
  config = config,
  purge = TRUE
)
```

每份 MD 只能含 `## 图面说明` 和 `## 分析上下文`，不得含 `## 标识`/`## 技术`。

- [ ] **Step 5: 验证**

Expected:

```text
FIGURES_OK pdf=12 png=12 tiff=12 md=12 flat_pdf=0
```

---

### Task 4: 构建 Table 1–5 与 S1–S10

**Files:**
- Modify: `R/ml_dual_literature_final.R`
- Modify: `tests/test_ml_dual_literature_final.R`

**Interfaces:**
- Produces: `ml_dual_literature_build_tables(index_root, final_root, config, dry_run=FALSE)`。

- [ ] **Step 1: 写表角色测试**

断言主表 5 个、补充表 10 个、文件名无重复编号。

- [ ] **Step 2: 实现单来源表复制**

Table 1、3、4、5 及 S1、S2、S3、S7–S10 从已导出的发表 xlsx 复制到新目录并按目标角色重命名；原表只读。

- [ ] **Step 3: 实现双库 Panel A/B 表**

Table 2、S5、S6 使用公共合并逻辑读取两库工作簿，生成一个新 xlsx：

```r
ml_dual_literature_merge_panel_xlsx(
  mimic_xlsx,
  eicu_xlsx,
  target_xlsx,
  panel_titles = c("Panel A. MIMIC-IV", "Panel B. eICU")
)
```

合并工作簿首行写统一题名；两个 Panel 保留原列名、脚注和三线表样式。禁止覆盖来源 xlsx。

- [ ] **Step 4: 校验所有终稿 xlsx**

逐个调用：

```r
v <- pub_xlsx_verify(path)
stopifnot(isTRUE(v$readable), v$corrupt_cells == 0L, v$styles > 0L)
```

- [ ] **Step 5: 验证**

Expected:

```text
TABLES_OK main=5 supplementary=10 duplicate_numbers=0 corrupt=0
```

---

### Task 5: 增加 CLI、MANIFEST 与可重复构建

**Files:**
- Create: `run/ml/build_ml_dual_literature_final.R`
- Modify: `R/ml_dual_literature_final.R`
- Modify: `tests/test_ml_dual_literature_final.R`

**Interfaces:**
- CLI:

```bash
Rscript run/ml/build_ml_dual_literature_final.R \
  --config "<study>/config.R" \
  --index "SOSM+WPR" \
  --out "<success>/publication_final"
```

- [ ] **Step 1: 实现参数解析与安全边界**

只接受 `【success】` 指标目录；目标位于该指标目录内；拒绝把 `--out` 指向原始 `Tables`/`Figures`。

- [ ] **Step 2: 实现 staging 后原子替换**

先构建 `publication_final.__staging__`；全部验收通过后替换 `publication_final`。失败时保留旧终稿并报告 staging 路径。

- [ ] **Step 3: 写 MANIFEST**

`MANIFEST.csv` 字段：

```text
kind,number,role,title,db_mode,source_files,target_file,verification
```

另写 `README.md`，明确主库、外验库、Figure/Table 映射和“模型未重训”。

- [ ] **Step 4: CLI dry-run**

Expected: 打印 12 图、15 表来源，且不写目录。

- [ ] **Step 5: CLI 实际构建**

Expected: `PUBLICATION_FINAL_OK figures=12 tables=15`。

---

### Task 6: SOSM+WPR 最终验收与文档同步

**Files:**
- Modify: `Decisiontree/decision_tree_ml_dual_prognosis_aki_dev_ext.md`
- Test: `tests/test_ml_dual_literature_final.R`

- [ ] **Step 1: 运行完整测试**

```bash
Rscript tests/test_ml_dual_literature_final.R
```

Expected: 所有 role/source/build/format/xlsx 检查为 PASS。

- [ ] **Step 2: 运行独立验收脚本**

检查：

```text
success combo = SOSM+WPR
Figures 1–12 = 12 unique
paired figures = 5 expected pairs
four formats = 12/12/12/12
main tables = 5
supplementary tables = 10
xlsx corrupt = 0
source files missing = 0
```

- [ ] **Step 3: 更新决策树**

将 SOSM+WPR 标记为最终入选组合，记录：

```text
External AUC (XGBoost)=0.7977
Internal AUC=0.8342
publication_final follows literature-first Figure 1–12
```

- [ ] **Step 4: 最终交付**

向用户报告 `publication_final` 路径、验收计数及任何无法从原始结果支持的项目；不得把缺失产物描述为已完成。

