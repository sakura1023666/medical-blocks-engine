# Task 4 Review Package
# Task 4 Report: `ip_stage2_cohort_28d` + 单测

**Status**: DONE  
**Date**: 2026-08-26  
**Worker**: Task 4 subagent  
**Commits**: none（global constraints / 用户明确禁止）

---

## 1. 执行摘要

已按 TDD 实现 Stage2 胶水块 `ip_stage2_cohort_28d`：28 天行政截尾纯函数、AKI 阳性筛入、预后 CSV 合并、规则 C 时间零点、`study_type` 切到 prognosis。假数据与真数据冒烟均通过。`pipeline_block_sources` 已注册；`docs/Blocks_catalog.md` AUTO 已同步。未 git commit。

TDD：先写 `tests/test_ip_stage2_28d.R`，Windows Rscript 首次失败为 `exists("ip_admin_censor_28", mode = "function") is not TRUE`；实现 `00ip_common.R` + block + 注册后 PASS。

---

## 2. 交付物

| 项 | 路径 | 说明 |
|----|------|------|
| 公共函数 | `Blocks/72_incidence_prognosis_two_stage/00ip_common.R` | `ip_admin_censor_28`：futime=min(t,28)；fustatus=1 iff dead & t≤28 |
| Block | `Blocks/72_incidence_prognosis_two_stage/02block_ip_stage2_cohort_28d.R` | 新建；加载时 source 同目录 `00ip_common.R` |
| 注册 | `R/pipeline_runner.R` → `pipeline_block_sources` | `ip_stage2_cohort_28d = b("72_.../02block_ip_stage2_cohort_28d.R")`（仅追加一行，未改旧映射） |
| 测试 | `tests/test_ip_stage2_28d.R` | 截尾向量 + 假队列 + 规则 C + locked 回退 + d/m/yyyy + 注册 + 真数据冒烟 |
| Catalog | `docs/Blocks_catalog.md` | `python3 scripts/update_blocks_catalog.py` exit 0；MANUAL §1–§3 未改 |

---

## 3. Block 行为

消费：`ctx$data$imputed`（空则 `locked` / `cleaned`）；`config$ip_two_stage$prognosis_path`；并键默认 `ID` ↔ `subject_id`。

产出：

- 筛 `Disease==1`（否则 `Acute_Renal_Failure`）后并预后 CSV
- 规则 C：`aki_time` 有非缺失 → t0=aki_time（行内缺失回退 icu_intime），`ctx$results$ip_stage2_timezero_source = "aki_onset"`；否则 `"icu_intime"`
- `t` = `dead_time`（存活则 `disch_time`/`icu_outtime`）− t0（天）；`ip_admin_censor_28`
- `ctx$data$stage2` 并覆写 `imputed`（供后续 Cox/KM 读同一分析集）
- `project$study_type = "prognosis"`；`data$outcome_column` / `survival$time_var`/`event_var` → `fustatus` / `futime`

---

## 4. 测试摘要

命令：

```bash
cd /mnt/e/01block/01Block-new-Final
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" tests/test_ip_stage2_28d.R
```

| 阶段 | 结果 |
|------|------|
| RED | `Error: exists("ip_admin_censor_28", mode = "function") is not TRUE` |
| GREEN | `OK censor logic` + `OK test_ip_stage2_28d` + `real-data smoke: n_AKI=110 stage2=110 events=24 timezero=icu_intime` |

回归：`tests/test_ip_cohort_sle_aki.R` 仍 `OK`（analytic=270, n_AKI=110）。

假数据：截尾向量 (10,40,28,5)×(1,1,0,0)→fustatus (1,0,0,0) / futime (10,28,28,5)；5 人 Stage1 → 3 AKI；无 `aki_time` → `icu_intime`；有 `aki_time` → `aki_onset` 且随访相对 AKI 起算；`locked` 回退；MIMIC `d/m/yyyy` 解析。

---

## 5. Catalog

- 脚本 exit OK；新 `register_block` id：`ip_stage2_cohort_28d`（415 blocks）
- AUTO 卡片用途行已是 purpose
- MANUAL §1/§2/§3 未改（套路 template 属 Task 7）
- `00ip_common.R` 无 `register_block`；`index_code_bundle` 会按同目录 `00*common` 一并拷贝

---

## 6. Concerns / 待后续确认

1. **真数据无 `aki_time`**：冒烟 t0=`icu_intime`（Task 1 已预期）；规则 C 的 `aki_onset` 分支仅假数据覆盖。
2. **`is_dead` 为 1 或 NA**（不是 0）：`ip_admin_censor_28` 把 NA dead 视为 0。
3. **存活者截在出院**：无死亡时用 `disch_time`/`icu_outtime`，属院内随访；spec §4.4 要求脚注偏倚（Task 7 config / image_information）。
4. **28d 事件偏少**：110 AKI 中 24 例 28 天死亡，后续 Cox/亚组可能不稳。
5. **覆写 `imputed`**：Stage2 之后分析集变为 AKI 子集；worker 须先完成 Stage1 导出再切阶段。
6. **未改旧课题 config**；未 git commit。

---

## 7. 自检清单

- [x] 失败测试先跑（`ip_admin_censor_28` 未定义）
- [x] `ip_admin_censor_28` 在 `00ip_common.R`；block 与测试共用
- [x] `register_block("ip_stage2_cohort_28d", ...)` + `pipeline_block_sources` 一行
- [x] 测试 PASS（假数据 + 真数据冒烟）；Task 3 回归 PASS
- [x] catalog 脚本 OK
- [x] 无 git commit
- [x] 本 report 已写入 `.superpowers/sdd/task-4-report.md`

## 00ip_common.R
###############################################################################
#  00ip_common — 发病/预后两阶段共用（72_incidence_prognosis_two_stage）
#
#  ip_admin_censor_28: 28 天行政截尾
#    futime   = min(t, 28)
#    fustatus = 1 iff 死亡且 t ≤ 28（t 缺失或 dead 非 1 → 0）
###############################################################################

ip_admin_censor_28 <- function(t_days, dead) {
  dead <- as.integer(dead)
  dead[is.na(dead)] <- 0L
  t_days <- as.numeric(t_days)
  fustatus <- as.integer(!is.na(t_days) & dead == 1L & t_days <= 28)
  futime <- pmin(t_days, 28)
  data.frame(futime = futime, fustatus = fustatus, stringsAsFactors = FALSE)
}
## 02block
320 /mnt/e/01block/01Block-new-Final/Blocks/72_incidence_prognosis_two_stage/02block_ip_stage2_cohort_28d.R
# ip_stage2_cohort_28d — AKI 阳性亚队列 + 预后 CSV + 规则 C 时间零点 + 28 天行政截尾
###############################################################################
#
#  register_block: "ip_stage2_cohort_28d"
#  典型流水线: Stage1 发病链 → ip_stage2_cohort_28d → Stage2 预后链（cox/KM/rcs…）
#
#  依据: docs/superpowers/specs/2026-08-26-sle-aki-incidence-prognosis-two-stage-design.md §4.4
#  时间零点规则 C: aki_time（若有非缺失）否则 icu_intime
#  28d: futime=min(t,28); fustatus=1 iff 死亡且 t≤28
#
#  require_config = config$ip_two_stage$prognosis_path
#  require_data   = ctx$data$imputed %||% ctx$data$locked %||% ctx$data$cleaned
#
#  # ── 配置 config$ip_two_stage ──────────────────────────────────────────────
#  ip_two_stage = list(
#    prognosis_path     = ".../data/mimic/mimic预后数据-all.csv",
#    baseline_id_col    = "ID",
#    prognosis_id_col   = "subject_id",
#    aki_time_col       = "aki_time",
#    icu_intime_col     = "icu_intime",
#    dead_time_col      = "dead_time",
#    dead_col           = "is_dead",
#    last_followup_cols = c("disch_time", "icu_outtime")
#  ),
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  读: Stage1 分析集（含 Disease / AKI 阳性）
#  写: ctx$data$stage2（并覆写 imputed 子集）列 futime / fustatus
#      ctx$results$ip_stage2_timezero_source ∈ aki_onset|icu_intime
#      ctx$config$project$study_type = "prognosis"
#      ctx$config$data$outcome_column / survival$time_var / event_var
###############################################################################

local({
  if (exists("ip_admin_censor_28", mode = "function")) return(invisible())
  of <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
  cands <- character(0)
  if (!is.null(of) && nzchar(of)) {
    cands <- c(cands, file.path(
      dirname(normalizePath(of, winslash = "/", mustWork = FALSE)),
      "00ip_common.R"
    ))
  }
  cands <- c(
    cands,
    file.path(getwd(), "Blocks/72_incidence_prognosis_two_stage/00ip_common.R")
  )
  p <- cands[file.exists(cands)][1L]
  if (length(p) && !is.na(p) && nzchar(p)) source(p, local = FALSE)
})

.ip72_s2_id_chr <- function(x) {
  x <- trimws(as.character(x))
  x[is.na(x) | !nzchar(x) | x %in% c("NA", "NaN", "<NA>")] <- NA_character_
  sub("\\.0+$", "", x)
}

.ip72_s2_yes01 <- function(x) {
  if (is.null(x)) return(integer(0))
  if (is.logical(x)) return(as.integer(x %in% TRUE))
  if (is.numeric(x)) return(as.integer(!is.na(x) & x == 1))
  xc <- tolower(trimws(as.character(x)))
  as.integer(xc %in% c("yes", "y", "1", "true"))
}

.ip72_s2_parse_dt <- function(x) {
  n <- if (is.null(x)) 0L else length(x)
  na_out <- function(n) {
    as.POSIXct(rep(NA_real_, n), origin = "1970-01-01", tz = "UTC")
  }
  if (n == 0L) return(na_out(0L))
  if (inherits(x, "POSIXt")) return(as.POSIXct(x))
  if (inherits(x, "Date")) return(as.POSIXct(as.character(x), tz = "UTC"))
  xc <- trimws(as.character(x))
  xc[is.na(x) | !nzchar(xc) | xc %in% c("NA", "NaN", "<NA>", "NULL")] <- NA_character_
  if (all(is.na(xc))) return(na_out(n))
  fmt <- c(
    "%Y-%m-%d %H:%M:%S",
    "%Y-%m-%d %H:%M",
    "%Y-%m-%d",
    "%d/%m/%Y %H:%M:%S",
    "%d/%m/%Y %H:%M",
    "%d/%m/%Y"
  )
  suppressWarnings(as.POSIXct(xc, tz = "UTC", tryFormats = fmt))
}

.ip72_s2_coalesce_dt <- function(...) {
  args <- list(...)
  args <- args[!vapply(args, is.null, logical(1))]
  if (!length(args)) return(.ip72_s2_parse_dt(character(0)))
  out <- args[[1L]]
  if (length(args) == 1L) return(out)
  for (i in seq_along(args)[-1L]) {
    miss <- is.na(out)
    if (!any(miss)) break
    nxt <- args[[i]]
    if (length(nxt) != length(out)) next
    out[miss] <- nxt[miss]
  }
## test
#!/usr/bin/env Rscript
# TDD: ip_stage2_cohort_28d — 28 天行政截尾；AKI 亚队列；规则 C 时间零点
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(root)) root <- normalizePath(".", winslash = "/")
source(file.path(root, "R/utils.R"), local = FALSE)

common_src <- file.path(root, "Blocks/72_incidence_prognosis_two_stage/00ip_common.R")
block_src <- file.path(root, "Blocks/72_incidence_prognosis_two_stage/02block_ip_stage2_cohort_28d.R")
if (file.exists(common_src)) source(common_src, local = FALSE)
if (file.exists(block_src)) source(block_src, local = FALSE)

stopifnot(exists("ip_admin_censor_28", mode = "function"))
stopifnot(exists("block_ip_stage2_cohort_28d", mode = "function"))

# --- 行政截尾：futime=min(t,28); fustatus=1 iff dead & t<=28 ---
x <- ip_admin_censor_28(c(10, 40, 28, 5), c(1, 1, 0, 0))
stopifnot(identical(x$fustatus, c(1L, 0L, 0L, 0L)))
stopifnot(identical(as.numeric(x$futime), c(10, 28, 28, 5)))

# 恰 28 天死亡算事件；dead=NA 视为未死亡
x28 <- ip_admin_censor_28(c(28, 10), c(1, NA))
stopifnot(identical(x28$fustatus, c(1L, 0L)))
stopifnot(identical(as.numeric(x28$futime), c(28, 10)))

# t 缺失：fustatus=0，futime=NA
xna <- ip_admin_censor_28(c(10, NA_real_), c(1, 1))
stopifnot(identical(xna$fustatus, c(1L, 0L)))
stopifnot(is.na(xna$futime[[2L]]))

cat("OK censor logic\n")

.ip_s2_write_prog <- function(td, prog) {
  path <- file.path(td, "mimic_prog.csv")
  utils::write.csv(prog, path, row.names = FALSE, na = "")
  path
}

.ip_s2_ctx <- function(imputed, prog_path, extra_cfg = list(), locked = NULL) {
  cfg <- c(
    list(
      prognosis_path = prog_path,
      baseline_id_col = "ID",
      prognosis_id_col = "subject_id"
    ),
    extra_cfg
  )
  list(
    config = list(
      ip_two_stage = cfg,
      project = list(study_type = "incidence"),
      data = list(outcome_column = "Disease"),
      survival = list()
    ),
    data = list(imputed = imputed, locked = locked),
    results = list()
  )
}

# --- 假数据：5 人 Stage1，3 例 AKI；死亡 10d / 40d / 存活出院 5d ---
td <- tempfile("ip_stage2_")
dir.create(td)
t0 <- as.POSIXct("2180-07-23 14:00:00", tz = "UTC")
imputed <- data.frame(
  ID = 1:5,
  Disease = c(1L, 1L, 1L, 0L, 0L),
  Age = c(40, 50, 60, 70, 45),
  stringsAsFactors = FALSE
)
prog <- data.frame(
  subject_id = 1:5,
  icu_intime = format(t0, "%Y-%m-%d %H:%M:%S"),
  dead_time = c(
    format(t0 + 10 * 86400, "%Y-%m-%d %H:%M:%S"),
    format(t0 + 40 * 86400, "%Y-%m-%d %H:%M:%S"),
    "",
    format(t0 + 3 * 86400, "%Y-%m-%d %H:%M:%S"),
    ""
  ),
  is_dead = c(1L, 1L, NA_integer_, 1L, NA_integer_),
  disch_time = c(
    format(t0 + 8 * 86400, "%Y-%m-%d %H:%M:%S"),
    format(t0 + 12 * 86400, "%Y-%m-%d %H:%M:%S"),
    format(t0 + 5 * 86400, "%Y-%m-%d %H:%M:%S"),
    format(t0 + 3 * 86400, "%Y-%m-%d %H:%M:%S"),
    format(t0 + 2 * 86400, "%Y-%m-%d %H:%M:%S")
  ),
  icu_outtime = format(t0 + 1 * 86400, "%Y-%m-%d %H:%M:%S"),
  stringsAsFactors = FALSE
)
prog_path <- .ip_s2_write_prog(td, prog)
ctx <- block_ip_stage2_cohort_28d(.ip_s2_ctx(imputed, prog_path))

stopifnot(is.data.frame(ctx$data$stage2))
stopifnot(identical(nrow(ctx$data$stage2), 3L))
stopifnot(identical(sort(as.integer(ctx$data$stage2$ID)), 1:3))
stopifnot(all(c("futime", "fustatus") %in% names(ctx$data$stage2)))
stopifnot(identical(ctx$results$ip_stage2_timezero_source, "icu_intime"))

ord <- order(as.integer(ctx$data$stage2$ID))
s2 <- ctx$data$stage2[ord, , drop = FALSE]
stopifnot(identical(as.integer(s2$fustatus), c(1L, 0L, 0L)))
stopifnot(isTRUE(all.equal(as.numeric(s2$futime), c(10, 28, 5), tolerance = 1e-6)))

stopifnot(identical(ctx$config$project$study_type, "prognosis"))
stopifnot(identical(ctx$config$data$outcome_column, "fustatus"))
stopifnot(identical(ctx$config$survival$time_var, "futime"))
stopifnot(identical(ctx$config$survival$event_var, "fustatus"))
stopifnot(identical(nrow(ctx$data$imputed), 3L))
stopifnot(all(as.numeric(ctx$data$imputed$futime) <= 28))

# --- 规则 C：有 aki_time 则时间零点 = aki_onset ---
td_aki <- tempfile("ip_stage2_aki_")
dir.create(td_aki)
imputed_aki <- imputed
imputed_aki$aki_time <- format(t0 + 2 * 86400, "%Y-%m-%d %H:%M:%S")
prog_aki_path <- .ip_s2_write_prog(td_aki, prog)
ctx_aki <- block_ip_stage2_cohort_28d(.ip_s2_ctx(imputed_aki, prog_aki_path))
stopifnot(identical(ctx_aki$results$ip_stage2_timezero_source, "aki_onset"))
s2a <- ctx_aki$data$stage2[order(as.integer(ctx_aki$data$stage2$ID)), , drop = FALSE]
# ID1: 死亡相对 aki_time = 8d → 事件；ID2: 38d → 截在 28；ID3: 出院相对 aki = 3d
stopifnot(identical(as.integer(s2a$fustatus), c(1L, 0L, 0L)))
stopifnot(isTRUE(all.equal(as.numeric(s2a$futime), c(8, 28, 3), tolerance = 1e-6)))

# --- locked 回退（无 imputed）---
td_lock <- tempfile("ip_stage2_lock_")
dir.create(td_lock)
prog_lock <- .ip_s2_write_prog(td_lock, prog)
ctx_lock <- .ip_s2_ctx(NULL, prog_lock, locked = imputed)
ctx_lock$data$imputed <- NULL
ctx_lock <- block_ip_stage2_cohort_28d(ctx_lock)
stopifnot(identical(nrow(ctx_lock$data$stage2), 3L))
stopifnot(identical(ctx_lock$results$ip_stage2_timezero_source, "icu_intime"))

# --- d/m/yyyy 预后 CSV（与 MIMIC 真数据格式一致）---
td_dm <- tempfile("ip_stage2_dm_")
dir.create(td_dm)
prog_dm <- data.frame(
  subject_id = 1:5,
  icu_intime = "23/7/2180 14:00:00",
  dead_time = c("2/8/2180 14:00:00", "1/9/2180 14:00:00", "", "26/7/2180 14:00:00", ""),
  is_dead = c(1L, 1L, NA_integer_, 1L, NA_integer_),
  disch_time = c(
    "31/7/2180 14:00:00", "4/8/2180 14:00:00", "28/7/2180 14:00:00",
    "26/7/2180 14:00:00", "25/7/2180 14:00:00"
  ),
  stringsAsFactors = FALSE
)
ctx_dm <- block_ip_stage2_cohort_28d(
  .ip_s2_ctx(imputed, .ip_s2_write_prog(td_dm, prog_dm))
)
s2d <- ctx_dm$data$stage2[order(as.integer(ctx_dm$data$stage2$ID)), , drop = FALSE]
# 23/7 → 2/8 = 10d 事件；23/7 → 1/9 ≈ 40d 截 28；存活 23/7→28/7 = 5d
stopifnot(identical(as.integer(s2d$fustatus), c(1L, 0L, 0L)))
stopifnot(isTRUE(all.equal(round(as.numeric(s2d$futime), 6), c(10, 28, 5), tolerance = 1e-4)))

# --- pipeline_block_sources 注册 ---
source(file.path(root, "R/pipeline_runner.R"), local = FALSE)
src_map <- pipeline_block_sources(root)
stopifnot("ip_stage2_cohort_28d" %in% names(src_map))
stopifnot(grepl("02block_ip_stage2_cohort_28d\\.R$", src_map$ip_stage2_cohort_28d))
stopifnot(file.exists(src_map$ip_stage2_cohort_28d))
# 旧课题映射仍在
stopifnot("ip_cohort_sle_aki" %in% names(src_map))
stopifnot("data_clean" %in% names(src_map))

# --- 真数据冒烟（路径存在才跑）---
mim_cands <- c(
  "G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/data/mimic",
  "/mnt/g/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/data/mimic"
)
mim <- NULL
for (p in mim_cands) {
  if (dir.exists(p)) {
    mim <- p
    break
  }
}
if (!is.null(mim)) {
  bl_real <- file.path(mim, "D01_baseline_MIMIC_ICU_frist_0626 (1).RData")
  sle_real <- file.path(mim, "SLE.csv")
  arf_real <- file.path(mim, "ARF.csv")
  prog_real <- file.path(mim, "mimic预后数据-all.csv")
  cohort_src <- file.path(root, "Blocks/72_incidence_prognosis_two_stage/01block_ip_cohort_sle_aki.R")
  if (file.exists(bl_real) && file.exists(sle_real) && file.exists(arf_real) &&
      file.exists(prog_real) && file.exists(cohort_src)) {
    source(cohort_src, local = FALSE)
    ctx_r <- list(
      config = list(ip_two_stage = list(
        baseline_path = bl_real,
        baseline_obj = "baseline",
        sle_path = sle_real,
        arf_path = arf_real,
        baseline_id_col = "ID",
        prognosis_path = prog_real,
        aki_window_note = "ICU stay ARF/AKI"
      )),
      data = list(),
      results = list()
    )
    ctx_r <- block_ip_cohort_sle_aki(ctx_r)
    ctx_r$data$imputed <- ctx_r$data$raw
    n_aki <- as.integer(sum(ctx_r$data$imputed$Disease == 1L, na.rm = TRUE))
    ctx_r <- block_ip_stage2_cohort_28d(ctx_r)
    n_s2 <- nrow(ctx_r$data$stage2)
    stopifnot(identical(n_aki, 110L))
    stopifnot(n_s2 <= n_aki)
    stopifnot(n_s2 >= 1L)
    stopifnot(identical(ctx_r$results$ip_stage2_timezero_source, "icu_intime"))
    stopifnot(all(as.numeric(ctx_r$data$stage2$futime) <= 28, na.rm = TRUE))
    stopifnot(all(ctx_r$data$stage2$fustatus %in% c(0L, 1L)))
    stopifnot(identical(ctx_r$config$project$study_type, "prognosis"))
    message("real-data smoke: n_AKI=", n_aki, " stage2=", n_s2,
            " events=", sum(ctx_r$data$stage2$fustatus == 1L, na.rm = TRUE),
            " timezero=", ctx_r$results$ip_stage2_timezero_source)
  } else {
    message("real-data smoke skipped: missing cohort/prognosis files under ", mim)
  }
} else {
  message("real-data smoke skipped: mimic dir not found")
}

unlink(c(td, td_aki, td_lock, td_dm), recursive = TRUE)
cat("OK test_ip_stage2_28d\n")
## register
417:    ip_stage2_cohort_28d          = b("72_incidence_prognosis_two_stage/02block_ip_stage2_cohort_28d.R"),
