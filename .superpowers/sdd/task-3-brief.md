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
