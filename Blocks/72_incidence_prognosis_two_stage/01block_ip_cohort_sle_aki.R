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
#    keep_age_na       = TRUE,          # TRUE=Age 缺失留队，交 imputation 补齐
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
    # 保留 Age 缺失：仅剔除已知 Age < min_age（本队列 1 例 Age=NA 否则会掉到 270）
    keep_age_na <- isTRUE(cfg$keep_age_na %||% TRUE)
    if (isTRUE(keep_age_na)) {
      d <- d[is.na(age) | age >= min_age, , drop = FALSE]
      steps[[length(steps) + 1L]] <- .ip72_step(
        "age_ge_18", n_pre_age, nrow(d),
        paste0("Age >= ", min_age, " (keep Age NA)")
      )
    } else {
      d <- d[!is.na(age) & age >= min_age, , drop = FALSE]
      steps[[length(steps) + 1L]] <- .ip72_step(
        "age_ge_18", n_pre_age, nrow(d),
        paste0("Age >= ", min_age)
      )
    }
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
