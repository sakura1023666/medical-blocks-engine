# Task 3 Review Package
## Files
total 12
drwxrwxrwx 1 root root 4096 Aug 26 11:32 .
drwxrwxrwx 1 root root 4096 Aug 26 11:32 ..
-rwxrwxrwx 1 root root 8453 Aug 26 11:34 01block_ip_cohort_sle_aki.R
-rwxrwxrwx 1 root root 6427 Aug 26 11:33 /mnt/e/01block/01Block-new-Final/tests/test_ip_cohort_sle_aki.R

## pipeline_runner registration
416:    ip_cohort_sle_aki             = b("72_incidence_prognosis_two_stage/01block_ip_cohort_sle_aki.R"),

## data_clean gate (if any)
46:  } else if (isTRUE(ctx$results$ip_cohort_prepared %||% FALSE) && !is.null(ctx$data$raw)) {
49:      "Using SLE∩baseline cohort from ip_cohort_sle_aki ({nrow(data)} rows x {ncol(data)} cols)"

## Block file
# ip_cohort_sle_aki — SLE 背景 ∩ MIMIC ICU baseline 纳排分析集
###############################################################################
#
#  register_block: "ip_cohort_sle_aki"
#  典型流水线: ip_cohort_sle_aki → attrition_flowchart → data_clean → column_mapping → index → analysis_exclusion → imputation
#
#  依据: docs/superpowers/specs/2026-08-26-sle-aki-incidence-prognosis-two-stage-design.md §4.1
#  主并键: baseline$ID == SLE.csv$subject_id == ARF.csv$subject_id（Task 1 审计）
#  dabiao 仅交叉核对人数，主分析以本块现场筛入为准。
#
#  require_config = config$ip_two_stage$baseline_path / sle_path / arf_path
#
#  # ── 配置 config$ip_two_stage ──────────────────────────────────────────────
#  ip_two_stage = list(
#    baseline_path     = ".../data/mimic/D01_baseline_MIMIC_ICU_frist_0626 (1).RData",
#    baseline_obj      = "baseline",
#    sle_path          = ".../data/mimic/SLE.csv",
#    arf_path          = ".../data/mimic/ARF.csv",
#    baseline_id_col   = "ID",          # 无 subject_id 列名
#    sle_id_col        = "subject_id",
#    arf_id_col        = "subject_id",
#    min_age           = 18,
#    dabiao_path       = NULL,          # 可选；仅日志交叉核对
#    aki_window_note   = "ICU stay ARF/AKI (Acute_Renal_Failure or ARF.csv membership)"
#  ),
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  写: ctx$data$raw（分析集；并抄一份 ctx$data$cleaned）
#      ctx$results$ip_attrition_steps（step, n_in, n_out, n_excluded, reason）
#      ctx$results$ip_aki_window_note、ctx$results$ip_cohort_prepared
#      结局列 Disease（0/1）、Acute_Renal_Failure（Yes/No 或缺列时由 ARF.csv 派生）
###############################################################################

.ip72_id_chr <- function(x) {
  x <- trimws(as.character(x))
  x[is.na(x) | !nzchar(x) | x %in% c("NA", "NaN", "<NA>")] <- NA_character_
  sub("\\.0+$", "", x)
}

.ip72_is_yes <- function(x) {
  if (is.null(x)) return(integer(0))
  if (is.logical(x)) return(as.integer(x %in% TRUE))
  if (is.numeric(x)) return(as.integer(!is.na(x) & x == 1))
  xc <- tolower(trimws(as.character(x)))
  as.integer(xc %in% c("yes", "y", "1", "true"))
}

.ip72_step <- function(step, n_in, n_out, reason) {
  n_in <- as.integer(n_in)[1L]
  n_out <- as.integer(n_out)[1L]
  if (!is.finite(n_in)) n_in <- 0L
  if (!is.finite(n_out)) n_out <- 0L
  data.frame(
    step = as.character(step)[1L],
    n_in = n_in,
    n_out = n_out,
    n_excluded = as.integer(max(0L, n_in - n_out)),
    reason = as.character(reason)[1L],
    stringsAsFactors = FALSE
  )
}

.ip72_require_file <- function(path, label) {
  path <- as.character(path %||% "")[1L]
  if (!nzchar(path) || !file.exists(path)) {
    stop("ip_cohort_sle_aki: ", label, " 无效或不存在: ", path, call. = FALSE)
  }
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

.ip72_load_baseline <- function(path, obj) {
  e <- new.env(parent = emptyenv())
  load(path, envir = e)
  obj <- as.character(obj %||% "baseline")[1L]
  if (exists(obj, envir = e, inherits = FALSE) && is.data.frame(e[[obj]])) {
    return(e[[obj]])
  }
  nms <- ls(e)
  dfs <- nms[vapply(nms, function(nm) is.data.frame(e[[nm]]), logical(1))]
  stop(
    "ip_cohort_sle_aki: RData 中找不到 data.frame 对象 '", obj, "'",
    if (length(dfs)) paste0("（候选: ", paste(dfs, collapse = ", "), "）") else "",
    call. = FALSE
  )
}

.ip72_unique_warn <- function(ids, label) {
  ids <- ids[!is.na(ids)]
  n <- length(ids)
  n_u <- length(unique(ids))
  if (n != n_u) {
    cli::cli_alert_warning(
      "ip_cohort_sle_aki: {label} ID 不唯一 ({n} 行 / {n_u} 唯一)；交集按 baseline 行保留"
    )
  }
  invisible(n_u)
}

block_ip_cohort_sle_aki <- function(ctx, ...) {
  cfg <- ctx$config$ip_two_stage
  if (is.null(cfg) || !is.list(cfg)) {
    stop("ip_cohort_sle_aki: 缺少 config$ip_two_stage", call. = FALSE)
  }

  bl_path  <- .ip72_require_file(cfg$baseline_path, "baseline_path")
  sle_path <- .ip72_require_file(cfg$sle_path, "sle_path")
  arf_path <- .ip72_require_file(cfg$arf_path, "arf_path")

  bl  <- .ip72_load_baseline(bl_path, cfg$baseline_obj %||% "baseline")
  sle <- utils::read.csv(sle_path, stringsAsFactors = FALSE)
  arf <- utils::read.csv(arf_path, stringsAsFactors = FALSE)

  id_bl  <- as.character(cfg$baseline_id_col %||% "ID")[1L]
  id_sle <- as.character(cfg$sle_id_col %||% "subject_id")[1L]
  id_arf <- as.character(cfg$arf_id_col %||% "subject_id")[1L]
  if (!id_bl %in% names(bl)) {
    stop("ip_cohort_sle_aki: baseline 无列 ", id_bl, call. = FALSE)
  }
  if (!id_sle %in% names(sle)) {
    stop("ip_cohort_sle_aki: SLE.csv 无列 ", id_sle, call. = FALSE)
  }
  if (!id_arf %in% names(arf)) {
    stop("ip_cohort_sle_aki: ARF.csv 无列 ", id_arf, call. = FALSE)
  }

  bl_ids  <- .ip72_id_chr(bl[[id_bl]])
  sle_ids <- .ip72_id_chr(sle[[id_sle]])
  arf_ids <- .ip72_id_chr(arf[[id_arf]])
  .ip72_unique_warn(bl_ids, "baseline")
  .ip72_unique_warn(sle_ids, "SLE.csv")

  steps <- list()
  n_bl <- nrow(bl)
  steps[[length(steps) + 1L]] <- .ip72_step(
    "baseline_icu", n_bl, n_bl,
    "MIMIC ICU first-stay baseline"
  )

  sle_keep <- unique(sle_ids[!is.na(sle_ids)])
  d <- bl[bl_ids %in% sle_keep, , drop = FALSE]
  n_sle <- nrow(d)
  steps[[length(steps) + 1L]] <- .ip72_step(
    "intersect_SLE", n_bl, n_sle,
    "Restrict to SLE.csv subject_id ∩ baseline ID"
  )
  if (n_sle < 1L) {
    stop("ip_cohort_sle_aki: SLE ∩ baseline 为空；检查 ID 映射（baseline$ID vs SLE$subject_id）",
         call. = FALSE)
  }

  min_age <- suppressWarnings(as.numeric(cfg$min_age %||% 18)[1L])
  if (!is.finite(min_age)) min_age <- 18
  if ("Age" %in% names(d)) {
    n_pre_age <- nrow(d)
    age <- suppressWarnings(as.numeric(as.character(d$Age)))
    d <- d[!is.na(age) & age >= min_age, , drop = FALSE]
    steps[[length(steps) + 1L]] <- .ip72_step(
      "age_ge_18", n_pre_age, nrow(d),
      paste0("Age >= ", min_age)
    )
  }

  d_ids <- .ip72_id_chr(d[[id_bl]])
  arf_keep <- unique(arf_ids[!is.na(arf_ids)])
  arf_derived <- FALSE
  if (!"Acute_Renal_Failure" %in% names(d)) {
    d$Acute_Renal_Failure <- ifelse(d_ids %in% arf_keep, "Yes", "No")
    arf_derived <- TRUE
  }
  d$Disease <- .ip72_is_yes(d$Acute_Renal_Failure)

  note <- as.character(cfg$aki_window_note %||% "")[1L]
  if (!nzchar(note)) {
    note <- paste0(
      "ICU stay ARF/AKI (Acute_Renal_Failure or ARF.csv membership); ",
      "exact AKI onset time not in baseline"
    )
    ctx$config$ip_two_stage$aki_window_note <- note
  }

  att <- do.call(rbind, steps)
  rownames(att) <- NULL

  n_aki <- as.integer(sum(d$Disease == 1L, na.rm = TRUE))
  dabiao_n <- NA_integer_
  dabiao_note <- NA_character_
  dabiao_path <- as.character(cfg$dabiao_path %||% "")[1L]
  if (nzchar(dabiao_path) && file.exists(dabiao_path)) {
    de <- new.env(parent = emptyenv())
    ok <- tryCatch({
      load(dabiao_path, envir = de)
      TRUE
    }, error = function(e) FALSE)
    if (isTRUE(ok)) {
      dnms <- ls(de)
      ddfs <- dnms[vapply(dnms, function(nm) is.data.frame(de[[nm]]), logical(1))]
      if (length(ddfs)) {
        dabiao_n <- nrow(de[[ddfs[[1L]]]])
        dabiao_note <- sprintf(
          "dabiao n=%d vs live SLE∩baseline n=%d (main analysis uses live filter)",
          dabiao_n, nrow(d)
        )
        if (!identical(as.integer(dabiao_n), as.integer(nrow(d)))) {
          cli::cli_alert_warning("ip_cohort_sle_aki: {dabiao_note}")
        }
      }
    }
  }

  ctx$data$raw <- d
  ctx$data$cleaned <- d
  ctx$results$ip_attrition_steps <- att
  ctx$results$ip_aki_window_note <- note
  ctx$results$ip_cohort_prepared <- TRUE
  ctx$results$ip_cohort_sle_aki <- list(
    n_baseline = n_bl,
    n_sle = n_sle,
    n_analytic = nrow(d),
    n_aki = n_aki,
    arf_derived = arf_derived,
    dabiao_n = dabiao_n,
    dabiao_note = dabiao_note,
    aki_window_note = note
  )

  cli::cli_alert_success(
    "ip_cohort_sle_aki: baseline={n_bl} → SLE={n_sle} → analytic={nrow(d)} (AKI={n_aki})"
  )
  ctx
}

register_block("ip_cohort_sle_aki", block_ip_cohort_sle_aki,
               "SLE背景∩baseline 纳排分析集")

## Test
#!/usr/bin/env Rscript
# TDD: ip_cohort_sle_aki — 10 baseline ∩ 5 SLE → nrow==5；纳排表列；ARF 结局
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(root)) root <- normalizePath(".", winslash = "/")
source(file.path(root, "R/utils.R"), local = FALSE)

block_src <- file.path(root, "Blocks/72_incidence_prognosis_two_stage/01block_ip_cohort_sle_aki.R")
if (file.exists(block_src)) source(block_src, local = FALSE)
stopifnot(exists("block_ip_cohort_sle_aki"))

.ip_write_fake <- function(td, bl, sle, arf) {
  e <- new.env(parent = emptyenv())
  e$baseline <- bl
  bl_path <- file.path(td, "baseline.RData")
  save(list = "baseline", file = bl_path, envir = e)
  sle_path <- file.path(td, "SLE.csv")
  arf_path <- file.path(td, "ARF.csv")
  utils::write.csv(sle, sle_path, row.names = FALSE)
  utils::write.csv(arf, arf_path, row.names = FALSE)
  list(baseline_path = bl_path, sle_path = sle_path, arf_path = arf_path)
}

.ip_make_ctx <- function(paths, extra = list()) {
  cfg <- c(
    list(
      baseline_path = paths$baseline_path,
      baseline_obj = "baseline",
      sle_path = paths$sle_path,
      arf_path = paths$arf_path,
      baseline_id_col = "ID",
      aki_window_note = "ICU stay ARF/AKI (Acute_Renal_Failure or ARF.csv)"
    ),
    extra
  )
  list(
    config = list(ip_two_stage = cfg),
    data = list(),
    results = list()
  )
}

# --- 最小：10 人 baseline ∩ 5 SLE → nrow==5 ---
td <- tempfile("ip_cohort_")
dir.create(td)
bl <- data.frame(
  ID = 1:10,
  Age = c(40, 50, 60, 70, 45, 30, 22, 80, 33, 41),
  stringsAsFactors = FALSE
)
sle <- data.frame(subject_id = 1:5, stringsAsFactors = FALSE)
arf <- data.frame(subject_id = c(1L, 2L, 3L), stringsAsFactors = FALSE)
paths <- .ip_write_fake(td, bl, sle, arf)
ctx <- block_ip_cohort_sle_aki(.ip_make_ctx(paths))
stopifnot(nrow(ctx$data$raw) == 5L)
stopifnot(identical(sort(as.integer(ctx$data$raw$ID)), 1:5))
stopifnot("Disease" %in% names(ctx$data$raw))
stopifnot("Acute_Renal_Failure" %in% names(ctx$data$raw))
stopifnot(identical(as.integer(sum(ctx$data$raw$Disease == 1L, na.rm = TRUE)), 3L))

att <- ctx$results$ip_attrition_steps
stopifnot(is.data.frame(att))
need_cols <- c("step", "n_in", "n_out", "n_excluded", "reason")
stopifnot(all(need_cols %in% names(att)))
stopifnot("baseline_icu" %in% att$step)
stopifnot("intersect_SLE" %in% att$step)
sle_row <- att[att$step == "intersect_SLE", , drop = FALSE]
stopifnot(nrow(sle_row) == 1L)
stopifnot(identical(as.integer(sle_row$n_out[[1L]]), 5L))
stopifnot(identical(as.integer(sle_row$n_in[[1L]]), 10L))
stopifnot(identical(as.integer(sle_row$n_excluded[[1L]]), 5L))
stopifnot(identical(as.character(ctx$results$ip_aki_window_note),
                    "ICU stay ARF/AKI (Acute_Renal_Failure or ARF.csv)"))

# --- Age < 18 从 SLE 交集中剔除 ---
td2 <- tempfile("ip_cohort_age_")
dir.create(td2)
bl2 <- bl
bl2$Age[bl2$ID == 5L] <- 16
paths2 <- .ip_write_fake(td2, bl2, sle, arf)
ctx2 <- block_ip_cohort_sle_aki(.ip_make_ctx(paths2))
stopifnot(nrow(ctx2$data$raw) == 4L)
stopifnot(!5L %in% as.integer(ctx2$data$raw$ID))
age_row <- ctx2$results$ip_attrition_steps
age_row <- age_row[age_row$step == "age_ge_18", , drop = FALSE]
stopifnot(nrow(age_row) == 1L)
stopifnot(identical(as.integer(age_row$n_out[[1L]]), 4L))

# --- 已有 Acute_Renal_Failure 时不覆盖，仅派生 Disease ---
td3 <- tempfile("ip_cohort_arfcol_")
dir.create(td3)
bl3 <- bl
bl3$Acute_Renal_Failure <- c("Yes", "No", "Yes", "No", "No",
                             "No", "No", "No", "No", "No")
paths3 <- .ip_write_fake(td3, bl3, sle, arf)
ctx3 <- block_ip_cohort_sle_aki(.ip_make_ctx(paths3))
stopifnot(nrow(ctx3$data$raw) == 5L)
stopifnot(identical(as.character(ctx3$data$raw$Acute_Renal_Failure[ctx3$data$raw$ID == 1L]), "Yes"))
stopifnot(identical(as.integer(ctx3$data$raw$Disease[ctx3$data$raw$ID == 1L]), 1L))
stopifnot(identical(as.integer(ctx3$data$raw$Disease[ctx3$data$raw$ID == 2L]), 0L))

# --- ID 类型不一致（character subject_id vs numeric ID）仍能交集 ---
td4 <- tempfile("ip_cohort_idtype_")
dir.create(td4)
sle4 <- data.frame(subject_id = as.character(1:5), stringsAsFactors = FALSE)
paths4 <- .ip_write_fake(td4, bl, sle4, arf)
ctx4 <- block_ip_cohort_sle_aki(.ip_make_ctx(paths4))
stopifnot(nrow(ctx4$data$raw) == 5L)

# --- pipeline_block_sources 注册 ---
source(file.path(root, "R/pipeline_runner.R"), local = FALSE)
src_map <- pipeline_block_sources(root)
stopifnot("ip_cohort_sle_aki" %in% names(src_map))
stopifnot(grepl("01block_ip_cohort_sle_aki\\.R$", src_map$ip_cohort_sle_aki))
stopifnot(file.exists(src_map$ip_cohort_sle_aki))

# --- 真数据冒烟（路径存在才跑；Windows G: 与 WSL /mnt/g） ---
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
  if (file.exists(bl_real) && file.exists(sle_real) && file.exists(arf_real)) {
    ctx_r <- list(
      config = list(ip_two_stage = list(
        baseline_path = bl_real,
        baseline_obj = "baseline",
        sle_path = sle_real,
        arf_path = arf_real,
        baseline_id_col = "ID",
        aki_window_note = "ICU stay ARF/AKI"
      )),
      data = list(),
      results = list()
    )
    ctx_r <- block_ip_cohort_sle_aki(ctx_r)
    att_r <- ctx_r$results$ip_attrition_steps
    n_intersect <- as.integer(att_r$n_out[att_r$step == "intersect_SLE"][[1L]])
    n_analytic <- nrow(ctx_r$data$raw)
    n_aki <- as.integer(sum(ctx_r$data$raw$Disease == 1L, na.rm = TRUE))
    # Task 1: SLE ∩ baseline = 271；1 例 Age=NA 按 brief `!is.na(Age) & Age>=18` 剔除 → 270
    stopifnot(identical(n_intersect, 271L))
    stopifnot(identical(as.integer(n_analytic), 270L))
    stopifnot(identical(n_aki, 110L))
    message("real-data smoke: intersect_SLE=", n_intersect,
            " analytic=", n_analytic, " n_AKI=", n_aki)
  } else {
    message("real-data smoke skipped: missing baseline/SLE/ARF under ", mim)
  }
} else {
  message("real-data smoke skipped: mimic dir not found")
}

unlink(c(td, td2, td3, td4), recursive = TRUE)
cat("OK test_ip_cohort_sle_aki\n")

## Report
# Task 3 Report: `ip_cohort_sle_aki` glue block + register

**Status**: DONE  
**Date**: 2026-08-26  
**Worker**: Task 3 subagent  
**Commits**: none（global constraints / 用户明确禁止）

---

## 1. 执行摘要

已按 TDD 实现 SLE∩baseline 纳排胶水块 `ip_cohort_sle_aki`：假数据 10∩5→5 与真数据冒烟均通过。`pipeline_block_sources` 已注册；`docs/Blocks_catalog.md` AUTO 已同步。未 git commit。

TDD：先写 `tests/test_ip_cohort_sle_aki.R`，Windows Rscript 首次失败为 `exists("block_ip_cohort_sle_aki") is not TRUE`（函数未定义）；实现后 PASS。

---

## 2. 交付物

| 项 | 路径 | 说明 |
|----|------|------|
| Block | `Blocks/72_incidence_prognosis_two_stage/01block_ip_cohort_sle_aki.R` | 新建 |
| 注册 | `R/pipeline_runner.R` → `pipeline_block_sources` | `ip_cohort_sle_aki = b("72_.../01block_ip_cohort_sle_aki.R")` |
| 测试 | `tests/test_ip_cohort_sle_aki.R` | 假数据 + 注册 + 真数据冒烟 |
| data_clean 闸门 | `Blocks/02_data_clean/01block_data_clean.R` | `ip_cohort_prepared` 时用已筛 `ctx$data$raw`，不改旧课题默认 |
| Catalog | `docs/Blocks_catalog.md` | `python3 scripts/update_blocks_catalog.py` exit 0；MANUAL §1–§3 未改 |

---

## 3. Block 行为

消费 `config$ip_two_stage`：`baseline_path` / `baseline_obj`（默认 `baseline`）/ `sle_path` / `arf_path`；并键 `baseline_id_col` 默认 `ID` ↔ SLE/ARF `subject_id`。

产出：

- `ctx$data$raw`（并抄 `ctx$data$cleaned`）
- `ctx$results$ip_attrition_steps`：`step, n_in, n_out, n_excluded, reason`
- 结局列 `Acute_Renal_Failure`（已有则保留；否则按 ARF.csv 成员派生 Yes/No）、`Disease`（0/1）
- `ctx$results$ip_aki_window_note`（读 `config$ip_two_stage$aki_window_note`；空则写入默认 ICU 期 ARF/AKI 脚注）
- `ctx$results$ip_cohort_prepared = TRUE`（供 data_clean 吃现场筛入集，避免再 load 全库 65366）

纳排步：`baseline_icu` → `intersect_SLE` →（若有 Age 列）`age_ge_18`。ID 一律转字符再交集，避免 numeric/character 漏并。

---

## 4. 测试摘要

命令：

```bash
cd /mnt/e/01block/01Block-new-Final
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" tests/test_ip_cohort_sle_aki.R
```

| 阶段 | 结果 |
|------|------|
| RED | `Error: exists("block_ip_cohort_sle_aki") is not TRUE` |
| GREEN | `OK test_ip_cohort_sle_aki` + `real-data smoke: intersect_SLE=271 analytic=270 n_AKI=110` |

假数据：10∩5→5；Age&lt;18 剔除；已有 `Acute_Renal_Failure` 不覆盖；character `subject_id` 仍能并；`pipeline_block_sources` 含本块且文件存在。

真数据（`G:/02block_result/29_SLE/.../data/mimic/`）：baseline 65366 → SLE 271 → analytic **270**（1 例 `Age=NA`，ID `12370999`）→ AKI **110**。

---

## 5. Catalog

- 脚本 exit OK；新 `register_block` id：`ip_cohort_sle_aki`
- AUTO 卡片用途行已是 purpose（非哈希横幅）
- MANUAL §1/§2/§3 未改（套路 template 属 Task 7）

---

## 6. Concerns / 待后续确认

1. **Age=NA 剔除 1 人**：brief 伪代码为 `!is.na(Age) & Age>=18`，故 271→270。若临床要保留 Age 缺失的 SLE 例，需改过滤规则（仅踢明确 &lt;18）。
2. **data_clean 闸门**：spec 顺序是本块在 `data_clean` 之前；无 `ip_cohort_prepared` 时 data_clean 会重新 load 全库。已加 gated 分支，旧课题不走该旗。
3. **AKI 时间窗**：baseline 仅 ICU 期二分类，无精确 `aki_time`；脚注走 `aki_window_note`。Stage2 规则 C 回退 `icu_intime` 仍待 Task 4。
4. **dabiao 交叉核对**：`dabiao_path` 可选；未配则只日志现场筛入。Task 1 显示 dabiao=271（含 Age=NA 那例），与 analytic 270 会差 1——Task 7 若配 dabiao_path 会打 warning。
5. **未改旧课题 config**；未 git commit。

---

## 7. 自检清单

- [x] 失败测试先跑（函数未定义）
- [x] `register_block("ip_cohort_sle_aki", ...)` + `pipeline_block_sources` 一行
- [x] 测试 PASS（假数据 + 真数据冒烟）
- [x] catalog 脚本 OK
- [x] 无 git commit
- [x] 本 report 已写入 `.superpowers/sdd/task-3-report.md`
