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
