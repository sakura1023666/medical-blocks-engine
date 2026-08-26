# SLE→AKI 发病+预后两阶段套路 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在单库 MIMIC 上为 SLE 背景人群搭建「AKI 发病 → AKI 后 28 天死亡预后」一套两阶段可并行 batch 套路，表图对齐文献深度且覆盖流程图 15 步全绿。

**Architecture:** `Blocks/72_incidence_prognosis_two_stage/` 仅含队列/Stage2/阈值三块胶水；Stage1/2 统计主链全部复用现有 incidence/survival Blocks。单 worker 内顺序跑 Stage1→胶水→Stage2；按指标并行。现有绘图 Block 增加 `pub_figure$profile == "mimic_inc_prog_sle_aki"` 门控分支，默认路径不变。

**Tech Stack:** R 4.5.1 (`Rscript.exe`)、Medical Blocks (`pipeline_runner` / batch worker 模式)、MICE、rms/segmented、飞书 bitable API

## Global Constraints

- 引擎根：`/mnt/e/01block/01Block-new-Final`
- 结果根：`G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/`（WSL：`/mnt/g/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/`）
- 数据：`.../data/mimic/` 下 `D01_baseline_MIMIC_ICU_frist_0626 (1).RData`、`SLE.csv`、`ARF.csv`、`mimic预后数据-all.csv`（`D04_dabiao` 仅核对）
- R：`"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"`（Windows 路径读 `G:/...`；缺包装该 R）
- **禁止**改旧课题 config/产出；**禁止**把 Tables/Figures 写到引擎仓库根
- `pub_figure$profile` 仅本套路设为 `"mimic_inc_prog_sle_aki"`；缺省=旧图
- Git：**仅在用户明确要求时 commit**（下列 Commit 步骤默认跳过）
- Spec：`docs/superpowers/specs/2026-08-26-sle-aki-incidence-prognosis-two-stage-design.md`
- 列审阅：必须先有 `_column_review.md` 再定稿 `disease_vars`

## File Structure

| 路径 | 职责 |
|------|------|
| `.../29_SLE/.../data/_column_review.md` + `_column_review_raw.txt` | 逐列审阅 |
| `Blocks/72_incidence_prognosis_two_stage/01block_ip_cohort_sle_aki.R` | SLE 纳排分析集 |
| `Blocks/72_incidence_prognosis_two_stage/02block_ip_stage2_cohort_28d.R` | Stage2 + 28 天截尾 |
| `Blocks/72_incidence_prognosis_two_stage/03block_threshold_logistic.R` | 发病 threshold 表图 |
| `R/pipeline_runner.R` | 注册 3 个新 block 源路径 |
| `Blocks/00_index/01block_index.R` | 仅追加缺失指标公式 |
| `Blocks/00_attrition/...`、`13_roc/...`、`15_rcs/...`、`18_subgroup/...`、`27_KM/...`、`28_plot/...` | 图 profile 门控分支 |
| `R/ip_two_stage_batch_runner.R` | shared + by_index worker 编排 |
| `run/sle_aki_inc_prog/run_sle_aki_inc_prog_batch.R` | 入口 |
| `run/sle_aki_inc_prog/run_sle_aki_inc_prog_batch_worker.R` | 指标 worker |
| `configs/templates/config_sle_aki_inc_prog_batch.template.R` | 模板 |
| `configs/config_sle_aki_inc_prog_batch.R` 或结果根下研究 config | 本课题 config |
| `Decisiontree/decision_tree_sle_aki_inc_prog.md` | 决策树（含 DAG） |
| `tests/test_ip_stage2_28d.R` | 28 天行政截尾单测 |
| `tests/test_pub_figure_profile_gate.R` | profile 缺省不改行为 |
| `run/feishu/` 扩展脚本或字段 | 挂 `29_SLE` / 工作计划 Bxx |

---

### Task 1: 列审阅 + 键与结局核对

**Files:**
- Create: `G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/data/_column_review_raw.txt`
- Create: `G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/data/_column_review.md`
- Create: `G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/data/_key_audit.txt`

**Interfaces:**
- Consumes: baseline / SLE.csv / ARF.csv / 预后 CSV / dabiao
- Produces: `disease_vars` 候选名单；键字段结论（`subject_id`/`stay_id`/`hadm_id`/`ID`）

- [ ] **Step 1: 用 Windows R 导出 baseline 列名与键重叠**

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" -e '
root <- "G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/data"
mim <- file.path(root, "mimic")
e <- new.env(); load(file.path(mim, "D01_baseline_MIMIC_ICU_frist_0626 (1).RData"), envir=e)
writeLines(names(e$baseline), file.path(root, "_column_review_raw.txt"))
sle <- read.csv(file.path(mim, "SLE.csv"), stringsAsFactors=FALSE)
arf <- read.csv(file.path(mim, "ARF.csv"), stringsAsFactors=FALSE)
prog <- read.csv(file.path(mim, "mimic预后数据-all.csv"), nrows=2, stringsAsFactors=FALSE)
keys <- c("subject_id","stay_id","hadm_id","ID")
sink(file.path(root, "_key_audit.txt"))
cat("baseline nrow=", nrow(e$baseline), "\n")
cat("SLE nrow=", nrow(sle), " ARF nrow=", nrow(arf), "\n")
cat("baseline has ID=", "ID" %in% names(e$baseline), "\n")
cat("SLE cols=", paste(names(sle), collapse=","), "\n")
cat("prog cols=", paste(names(prog), collapse=","), "\n")
# overlap by subject_id if baseline$ID == subject_id
if ("ID" %in% names(e$baseline)) {
  cat("SLE in baseline by ID=", sum(sle$subject_id %in% e$baseline$ID), "\n")
  cat("ARF in baseline by ID=", sum(arf$subject_id %in% e$baseline$ID), "\n")
}
sink()
cat("wrote audits\n")
'
```

Expected: 生成两个审计文件；打印 `wrote audits`

- [ ] **Step 2: 写 `_column_review.md`**

按 `.cursor/skills/review-raw-covariate-columns/SKILL.md` 逐列 `保留|排除`。SLE/AKI 课题至少排除进 `disease_vars` 的示例：`Acute_Renal_Failure`（结局）、`CKD`（若作排除准则则纳排用、不作协变量）、`CRRT`/`CRRT_Day`（结局相关干预）、明显肾结局泄漏列；SLE 诊断相关列若存在亦排除。人口学/生命体征/通用血脂肝酶可保留候选。

- [ ] **Step 3: 跳过 commit**（除非用户要求）

---

### Task 2: 指标库审计与补缺

**Files:**
- Modify: `Blocks/00_index/01block_index.R`（仅追加缺失 `list(name=...)`）
- Create: `G:/02block_result/29_SLE/.../data/_index_coverage.md`

**Interfaces:**
- Consumes: `01block_index.R` 内公式列表
- Produces: 本课题 `index$only` 推荐向量（覆盖文献+库内可算）

- [ ] **Step 1: 列出已有 vs 文献目标**

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" -e '
f <- "/mnt/e/01block/01Block-new-Final/Blocks/00_index/01block_index.R"
tx <- readLines(f)
nms <- unique(sub(".*name\\s*=\\s*\"([^\"]+)\".*", "\\1", grep("name\\s*=\\s*\"", tx, value=TRUE)))
# crude; prefer parsing list(name=
want <- c("CONUT_score","PNI","GNRI","NLR","SII","SIRI","SIS","LMR","BMI","PLR","MLR","CAR","PIV","AGR","SIIR")
cat("have:\n"); print(intersect(want, nms))
cat("missing:\n"); print(setdiff(want, nms))
writeLines(c("## have", intersect(want, nms), "", "## missing", setdiff(want, nms), "", "## all_in_block", sort(nms)),
  "G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/data/_index_coverage.md")
'
```

- [ ] **Step 2: 对 missing 追加公式**

在 `01block_index.R` 公式列表末尾按现有风格追加（示例 SIS / LMR，若 Step1 显示缺失）：

```r
list(name = "SIS",
     expr = quote( /* 按文献: 低白蛋白/淋巴细胞/肿瘤等计分；若成分不足则 skip */ ),
     digits = 4L),
list(name = "LMR",
     expr = quote(Lymphocytes / Monocyte),
     digits = 4L)
```

实现时：每个 missing 指标查文献定义；成分列不存在则依赖 index 块「自动跳过」行为，不改跳过逻辑。

- [ ] **Step 3: 冒烟——对 dabiao 子集跑 index 公式可用性**

用临时 R 加载 dabiao，source index 内部公式函数（或跑最小 pipeline `--only index`），确认 `computed_indices` 非空。

---

### Task 3: `ip_cohort_sle_aki` 胶水块 + 注册

**Files:**
- Create: `Blocks/72_incidence_prognosis_two_stage/01block_ip_cohort_sle_aki.R`
- Modify: `R/pipeline_runner.R`（`pipeline_block_sources` 增加一行）

**Interfaces:**
- Consumes: `config$ip_two_stage` 路径；baseline / SLE / ARF
- Produces: `ctx$data$raw` 或 `ctx$data$cleaned` 分析集；`ctx$results$ip_attrition_steps`（data.frame: step, n_in, n_out, n_excluded, reason）；结局列 `Disease`/`Acute_Renal_Failure`

- [ ] **Step 1: 写失败测试（队列人数）**

Create `tests/test_ip_cohort_sle_aki.R`：

```r
source("R/utils.R") # 若测试框架已有 helper 则沿用
# 最小：source 新 block 后，用假数据 10 人 baseline ∩ 5 SLE → nrow==5
stopifnot(exists("block_ip_cohort_sle_aki"))
```

先跑应 FAIL（函数未定义）。

- [ ] **Step 2: 实现 block**

核心逻辑：

```r
block_ip_cohort_sle_aki <- function(ctx) {
  cfg <- ctx$config$ip_two_stage
  e <- new.env(); load(cfg$baseline_path, envir = e)
  bl <- e[[cfg$baseline_obj %||% "baseline"]]
  sle <- utils::read.csv(cfg$sle_path, stringsAsFactors = FALSE)
  arf <- utils::read.csv(cfg$arf_path, stringsAsFactors = FALSE)
  id_bl <- cfg$baseline_id_col %||% "ID"
  steps <- list()
  steps[[1]] <- list(step = "baseline_icu", n = nrow(bl))
  d <- bl[bl[[id_bl]] %in% sle$subject_id, , drop = FALSE]
  steps[[2]] <- list(step = "intersect_SLE", n = nrow(d))
  # age>=18 if Age present
  if ("Age" %in% names(d)) {
    d <- d[!is.na(d$Age) & d$Age >= 18, , drop = FALSE]
    steps[[3]] <- list(step = "age_ge_18", n = nrow(d))
  }
  # AKI flag: prefer Acute_Renal_Failure; else membership in ARF.csv
  if (!"Acute_Renal_Failure" %in% names(d)) {
    d$Acute_Renal_Failure <- ifelse(d[[id_bl]] %in% arf$subject_id, "Yes", "No")
  }
  d$Disease <- as.integer(d$Acute_Renal_Failure %in% c("Yes", "YES", 1L, "1"))
  # write attrition table for attrition_flowchart
  ctx$results$ip_attrition_steps <- do.call(rbind, lapply(steps, as.data.frame))
  ctx$data$raw <- d
  ctx
}
register_block("ip_cohort_sle_aki", block_ip_cohort_sle_aki, "SLE背景∩baseline 纳排分析集")
```

疾病窗写入 `config$ip_two_stage$aki_window_note`（字符串，脚注用）。

- [ ] **Step 3: `pipeline_block_sources` 注册**

```r
ip_cohort_sle_aki = b("72_incidence_prognosis_two_stage/01block_ip_cohort_sle_aki.R"),
```

- [ ] **Step 4: 重跑测试 PASS**

---

### Task 4: `ip_stage2_cohort_28d` + 单测

**Files:**
- Create: `Blocks/72_incidence_prognosis_two_stage/02block_ip_stage2_cohort_28d.R`
- Create: `tests/test_ip_stage2_28d.R`
- Modify: `R/pipeline_runner.R`

**Interfaces:**
- Consumes: Stage1 分析 `ctx$data$imputed`（或 locked）；`config$ip_two_stage$prognosis_path`；时间零点规则 C
- Produces: `ctx$data$stage2`（或覆写 imputed 子集）；列 `futime`,`fustatus`；`ctx$results$ip_stage2_timezero_source` ∈ `aki_onset|icu_intime`

- [ ] **Step 1: 写失败测试（行政截尾）**

```r
# tests/test_ip_stage2_28d.R
ip_admin_censor_28 <- function(t_days, dead) {
  dead <- as.integer(dead)
  t_days <- as.numeric(t_days)
  fustatus <- as.integer(dead == 1L & t_days <= 28)
  futime <- pmin(t_days, 28)
  futime[dead != 1L | t_days > 28] <- pmin(t_days[dead != 1L | t_days > 28], 28)
  # clarify: always futime = min(t,28); fustatus = 1 iff dead & t<=28
  fustatus <- as.integer(!is.na(t_days) & dead == 1L & t_days <= 28)
  futime <- pmin(t_days, 28)
  data.frame(futime = futime, fustatus = fustatus)
}
x <- ip_admin_censor_28(c(10, 40, 28, 5), c(1, 1, 0, 0))
stopifnot(identical(x$fustatus, c(1L, 0L, 0L, 0L)))
stopifnot(identical(as.numeric(x$futime), c(10, 28, 28, 5)))
cat("OK censor logic\n")
```

Run:  
`"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" tests/test_ip_stage2_28d.R`  
Expected: `OK censor logic`（纯函数可先内嵌测试文件；block 实现后改为 source 公共函数）

- [ ] **Step 2: 实现 block**

```r
# 伪代码要点
# 1) d <- ctx$data$imputed; d2 <- d[d$Disease == 1L, ]
# 2) merge prognosis on subject_id/ID
# 3) t0 <- if (has aki_time) aki_time else icu_intime
# 4) t_days <- as.numeric(difftime(dead_time_or_last, t0, units="days"))
# 5) apply ip_admin_censor_28; study_type 切到 prognosis 字段供后续块
# 6) ctx$config$data$outcome_column / survival$time_var/event_var 指向 fustatus/futime
```

把 `ip_admin_censor_28` 放到同目录 `00ip_common.R` 供测试与 block 共用。

- [ ] **Step 3: 注册 `ip_stage2_cohort_28d`**

- [ ] **Step 4: 测试 PASS**

---

### Task 5: `threshold_logistic` 块

**Files:**
- Create: `Blocks/72_incidence_prognosis_two_stage/03block_threshold_logistic.R`
- Modify: `R/pipeline_runner.R`

**Interfaces:**
- Consumes: 锁定协变量 + 连续暴露；`rcs` 或分段搜索
- Produces: `Tables/Table_Threshold_logistic_*.csv`；`Figures/Figure_Threshold_*.pdf`（profile 文献版）

- [ ] **Step 1: 实现最小可用版本**

对连续 index：在分位数网格上拟合两段 logistic（或 `segmented`/`chngpt` 若已装），输出阈值点、阈值下/上 OR、P；图为平滑曲线+竖线阈值（对标论文 1 Figure 3 / Table 4）。

```r
register_block("threshold_logistic", block_threshold_logistic,
               "发病侧 threshold/piecewise logistic 表图")
```

缺包则 `install.packages` 到 R-4.5.1 library。

- [ ] **Step 2: 单指标冒烟**（在 Task 8 通跑时验收）

---

### Task 6: 现有 Block 图 profile 门控

**Files:**
- Modify（各加只读门控，禁止改默认）:
  - `Blocks/00_attrition/01block_attrition_flowchart.R`
  - `Blocks/13_roc/02block_simple_ROC.R`（及必要时 `01block_ROC.R`）
  - `Blocks/15_rcs/02block_rcs_incidence.R`、`01block_rcs_prognosis.R`
  - `Blocks/18_subgroup/` 发病/预后 subgroup
  - `Blocks/27_KM/*`、`Blocks/28_plot/01block_plot_cutoff.R`
- Create: `tests/test_pub_figure_profile_gate.R`
- Create: `R/pub_figure_profile.R`（`pub_figure_profile(ctx)` → 字符串或 NULL）

**Interfaces:**
- Consumes: `ctx$config$pub_figure$profile`
- Produces: 仅当 profile 匹配时改 theme/面板/标注；否则原函数路径

- [ ] **Step 1: 公共 getter**

```r
# R/pub_figure_profile.R
pub_figure_profile <- function(config) {
  p <- tryCatch(config$pub_figure$profile, error = function(e) NULL)
  if (is.null(p) || !nzchar(as.character(p)[1L])) return(NULL)
  as.character(p)[1L]
}
is_pub_profile <- function(config, name) {
  identical(pub_figure_profile(config), name)
}
```

- [ ] **Step 2: 每个目标 Block 在绑图前**

```r
if (is_pub_profile(ctx$config, "mimic_inc_prog_sle_aki")) {
  # 文献版：例如 ROC 多曲线同面板、RCS 带 knot 标注、森林图交互 P 高亮
} else {
  # 原有代码不动
}
```

优先抽取「只改 ggplot theme / ggsave 尺寸 / 标题」的最小 diff；大改版式放 profile 分支内。

- [ ] **Step 3: 门控测试**

```r
source("R/pub_figure_profile.R")
stopifnot(is.null(pub_figure_profile(list())))
stopifnot(is_pub_profile(list(pub_figure = list(profile = "mimic_inc_prog_sle_aki")),
                         "mimic_inc_prog_sle_aki"))
stopifnot(!is_pub_profile(list(pub_figure = list(profile = "other")),
                          "mimic_inc_prog_sle_aki"))
cat("OK profile gate\n")
```

---

### Task 7: Config + 决策树 + Template

**Files:**
- Create: `configs/templates/config_sle_aki_inc_prog_batch.template.R`
- Create: `G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/config_sle_aki_inc_prog_batch.R`（研究 config，可从 template 复制）
- Create: `Decisiontree/decision_tree_sle_aki_inc_prog.md`

**Interfaces:**
- `project$output_dir` → 结果根  
- `project$study_type` Stage1 为 `incidence`；Stage2 块前由胶水切换 survival 字段  
- `pub_figure$profile = "mimic_inc_prog_sle_aki"`  
- `mirror_pub_outputs_to_root = TRUE`（相对于 **output_dir**）  
- `analysis_exclusion$disease_vars` ← Task 1  
- `subgroup$age_cutoff`：SLE 常用 65（注释写依据；二分类 `Age_Group`）  
- `ip_two_stage` 路径全部指向 `G:/02block_result/.../data/mimic/`

Pipeline 列表按 spec §6 完整写入 `pipeline$blocks` / `pipeline_regular_batch`。

决策树必须含：15 步对照表、DAG 文字版、时间零点规则 C、28 天定义、飞书编号占位。

- [ ] **Step 1: 从 `config_incidence_dual_batch.template.R` + survival 模板拼单库两阶段 template**（`dual_db$enable=FALSE`）
- [ ] **Step 2: 写决策树 md（结构对齐 `decision_tree_incidence_single.md`）**
- [ ] **Step 3: 结果根落研究 config**

---

### Task 8: Runner + Worker（并行 batch）

**Files:**
- Create: `R/ip_two_stage_batch_runner.R`
- Create: `run/sle_aki_inc_prog/run_sle_aki_inc_prog_batch.R`
- Create: `run/sle_aki_inc_prog/run_sle_aki_inc_prog_batch_worker.R`

**Interfaces:**
- CLI：`--config` `--workers` `--only-index` `--shared-only` `--from` `--to` `--no-skip`
- Shared：跑到 `imputation`（含纳排/index/exclusion）
- Worker：每指标 Stage1 全链 → `ip_stage2_cohort_28d` → Stage2 全链 → finalize（Tables/Figures 镜像到结果根；成功则 `index_code_bundle_finalize`）

- [ ] **Step 1: 入口脚本头仿 `run_incidence_dual_batch.R`**，但调用 `ip_two_stage_batch_run()`
- [ ] **Step 2: Worker 内两阶段**

```r
# 伪代码
run_pipeline(ctx, blocks = stage0_or_stage1_blocks)
run_pipeline(ctx, blocks = "ip_stage2_cohort_28d")
# 切换 config$project$study_type <- "prognosis"；outcome/time/event
run_pipeline(ctx, blocks = stage2_blocks)
incidence_batch_finalize_index_outputs(ctx)  # 若可复用；否则写 ip_finalize
```

协变量综合：Stage2 开始前

```r
m1 <- unique(c(ctx$results$model1_incidence, ctx$config$ip_two_stage$force_covariates))
# Stage2 UV/MV 后再 union 写回 Model factors
```

- [ ] **Step 3: 试跑 1 个指标**

```bash
cd /mnt/e/01block/01Block-new-Final
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
  run/sle_aki_inc_prog/run_sle_aki_inc_prog_batch.R \
  --config "G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/config_sle_aki_inc_prog_batch.R" \
  --only-index NLR --workers 1
```

Expected: 结果根出现 `by_index/` 与 `Tables/`/`Figures/`（含 flowchart、Table1×2、ROC、RCS、threshold、KM）

---

### Task 9: 飞书挂接

**Files:**
- Create or modify: `run/feishu/run_feishu_setup_sle_aki_tables.R`（可复用 `run_feishu_setup_routine_table.R` 模式）
- 工作计划行：模块名含 `SLE` / `发病预后两阶段`；编号取当前最大 B + 1（查飞书或本地 xlsx）

**Interfaces:**
- `BLOCK_RESULT_ROOT` 含 `G:/02block_result`；扫描 `29_SLE`
- `.env.feishu` 已有 `FEISHU_APP_ID/SECRET/BITABLE_APP_TOKEN`

- [ ] **Step 1: dry-run `run_feishu_resync_block_result.R --dry-run`**
- [ ] **Step 2: 写入工作计划「进行中」**
- [ ] **Step 3: 全批成功后 mark done**

---

### Task 10: 全量并行 + 验收清单

**Files:** 无新代码；产出在结果根

- [ ] **Step 1: 全指标 batch**

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
  run/sle_aki_inc_prog/run_sle_aki_inc_prog_batch.R \
  --config "G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/config_sle_aki_inc_prog_batch.R" \
  --workers auto
```

- [ ] **Step 2: 勾选验收**

| 检查项 | 通过标准 |
|--------|----------|
| 15 步 | 决策树与产出一一对应 |
| Fig1 | 逐步 n + 排除人数 |
| Table1 ×2 | 发病/预后各一 |
| ROC ×2 | 有 AUC 表 |
| RCS + threshold + segmented | 文件存在 |
| KM + Cox | 28 天截尾脚注 |
| 旧课题 | 抽一旧 incidence config，`profile` 空，图逻辑无回归 |
| 落盘 | 引擎根无本课题 Tables/Figures |

- [ ] **Step 3: `update-blocks-catalog` skill** 更新 `docs/Blocks_catalog.md`（新 72 块）

---

## Spec Coverage Self-Review

| Spec 要求 | Task |
|-----------|------|
| 两阶段一套套路 | 8 |
| 现场 SLE 纳排 + flowchart | 3, 7 |
| 28 天行政截尾规则 C | 4 |
| 指标补库 | 2 |
| threshold_logistic | 5 |
| 图 profile 门控 | 6 |
| disease_vars 审列 | 1 |
| config/决策树/run | 7–8 |
| 飞书 | 9 |
| 结果只落 G: 结果根 | Global + 7–8 |
| 不改旧课题 | Global + 6 测试 |
| 并行 batch | 8, 10 |
| code 包 finalize | 8 |
| 15 步全绿 | 10 验收表 |

**Placeholder scan:** 无 TBD；SIS 公式在 Task 2 按文献填写（执行时查原文，不留空实现）。

**命名一致性:** `ip_cohort_sle_aki` / `ip_stage2_cohort_28d` / `threshold_logistic` / `mimic_inc_prog_sle_aki` / `ip_admin_censor_28` 全文统一。

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-26-sle-aki-incidence-prognosis-two-stage.md`.

**Two execution options:**

1. **Subagent-Driven（推荐）** — 每任务新开 subagent，任务间审查  
2. **Inline Execution** — 本会话按 executing-plans 连续执行并设检查点  

Which approach?
