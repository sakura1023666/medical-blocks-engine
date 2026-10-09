###############################################################################
#  train_validation — 分层划分训练/验证集 + 组间基线可比性表（Table 1 风格）。
#
#  register_block: "train_validation"
#  典型流水线: imputation 之后、ml_models 之前；enable=FALSE 时需自行赋值 ctx$data$train/test
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed %||% ctx$data$cleaned
#  结局列用于 stratify（默认 Group 0/1）
#
#  # ── 配置 config$train_validation ──────────────────────────────────────────
#  train_validation = list(
#    enable             = TRUE,
#    passthrough        = FALSE,   # TRUE 或 mode="passthrough"：不重切，沿用 ctx$data$train/test
#    mode               = NULL,    # "passthrough" | "external_all"（次库整库外验，不划分）
#    train_ratio        = 0.7,     # 训练占比；(0,1)
#    stratify           = TRUE,    # 按结局分层 initial_split
#    base_seed          = NULL,  # NULL → splitting$seed 或 imputation$seed
#    max_resplit_iter   = 2000L, # 组间比较 P 不达标时重划分上限
#    p_strict           = 0.05,  # 全部比较 P 须严格大于该值（不可等于）
#    comparison_vars    = NULL,  # NULL → baseline 候选或自动
#    variable_labels    = NULL,  # 列名 → 表头显示名
#    table_title        = NULL,
#    continuous_preprocess = list(enable=FALSE, default_method="none", by_var=list(), ...)
#  ),
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  写: ctx$data$train、ctx$data$test、ctx$results$table_train_val_baseline
#  文件: Tables/Table_1_Baseline_*；源: Blocks/block_train_validation.R
###############################################################################

.tv_coerce_numeric_col <- function(x) {
  if (is.factor(x)) x <- as.character(x)
  suppressWarnings(as.numeric(x))
}

.tv_normalize_method <- function(m) {
  m <- tolower(trimws(as.character(m)[1L]))
  if (!nzchar(m)) return("none")
  if (m %in% c("standardize", "zscore", "z-score")) return("scale")
  if (m %in% c("normalize", "min_max", "min-max", "minmax0", "range01")) return("minmax")
  m
}

.tv_preprocess_vectors <- function(x_tr, x_va, method_raw, opts) {
  method <- .tv_normalize_method(method_raw)
  if (method %in% c("none", "identity")) {
    return(list(train = x_tr, val = x_va, applied = FALSE, detail = "none", used = NA_character_))
  }
  xt <- .tv_coerce_numeric_col(x_tr)
  xv <- .tv_coerce_numeric_col(x_va)
  fin_tr <- is.finite(xt)
  if (!any(fin_tr)) {
    return(list(train = xt, val = xv, applied = FALSE, detail = "no finite training values", used = NA_character_))
  }

  used <- method
  if (method == "log") {
    if (any(fin_tr & xt <= 0, na.rm = TRUE)) {
      if (isTRUE(opts$log_use_log1p_if_nonpositive %||% TRUE)) {
        used <- "log1p (auto: training had non-positive)"
        xt2 <- xt
        xv2 <- xv
        ok_tr <- is.finite(xt2) & xt2 > -1 + .Machine$double.eps
        ok_va <- is.finite(xv2) & xv2 > -1 + .Machine$double.eps
        xt2[ok_tr] <- log1p(xt2[ok_tr])
        xv2[ok_va] <- log1p(xv2[ok_va])
        return(list(train = xt2, val = xv2, applied = TRUE, detail = NA_character_, used = used))
      }
      return(list(train = xt, val = xv, applied = FALSE, detail = "log requires all training values > 0", used = NA_character_))
    }
    xt2 <- xt
    xv2 <- xv
    xt2[is.finite(xt2) & xt2 > 0] <- log(xt2[is.finite(xt2) & xt2 > 0])
    xv2[is.finite(xv2) & xv2 > 0] <- log(xv2[is.finite(xv2) & xv2 > 0])
    return(list(train = xt2, val = xv2, applied = TRUE, detail = NA_character_, used = used))
  }

  if (method == "log1p") {
    xt2 <- xt
    xv2 <- xv
    ok_tr <- is.finite(xt2) & xt2 > -1 + .Machine$double.eps
    ok_va <- is.finite(xv2) & xv2 > -1 + .Machine$double.eps
    xt2[ok_tr] <- log1p(xt2[ok_tr])
    xv2[ok_va] <- log1p(xv2[ok_va])
    return(list(train = xt2, val = xv2, applied = TRUE, detail = NA_character_, used = used))
  }

  if (method == "sqrt") {
    xt2 <- xt
    xv2 <- xv
    ok_tr <- is.finite(xt2) & xt2 >= 0
    ok_va <- is.finite(xv2) & xv2 >= 0
    xt2[ok_tr] <- sqrt(xt2[ok_tr])
    xv2[ok_va] <- sqrt(xv2[ok_va])
    return(list(train = xt2, val = xv2, applied = TRUE, detail = NA_character_, used = used))
  }

  if (method == "scale") {
    mu <- mean(xt[fin_tr], na.rm = TRUE)
    sdv <- stats::sd(xt[fin_tr], na.rm = TRUE)
    if (!is.finite(sdv) || sdv < 1e-12) {
      return(list(train = xt, val = xv, applied = FALSE, detail = "sd_train ~ 0", used = NA_character_))
    }
    xt2 <- xt
    xv2 <- xv
    xt2[is.finite(xt2)] <- (xt2[is.finite(xt2)] - mu) / sdv
    xv2[is.finite(xv2)] <- (xv2[is.finite(xv2)] - mu) / sdv
    return(list(train = xt2, val = xv2, applied = TRUE, detail = NA_character_, used = paste0("mean=", mu, ", sd=", sdv)))
  }

  if (method == "minmax") {
    rng <- range(xt[fin_tr], na.rm = TRUE, finite = TRUE)
    mn <- rng[1L]
    mx <- rng[2L]
    den <- mx - mn
    if (!is.finite(den) || den < 1e-12) {
      return(list(train = xt, val = xv, applied = FALSE, detail = "minmax degenerate range", used = NA_character_))
    }
    xt2 <- xt
    xv2 <- xv
    scale01 <- function(z) (z - mn) / den
    xt2[is.finite(xt2)] <- scale01(xt2[is.finite(xt2)])
    xv2[is.finite(xv2)] <- scale01(xv2[is.finite(xv2)])
    if (isTRUE(opts$minmax_clip_validation %||% TRUE)) {
      xv2[is.finite(xv2)] <- pmax(0, pmin(1, xv2[is.finite(xv2)]))
    }
    return(list(train = xt2, val = xv2, applied = TRUE, detail = NA_character_, used = paste0("min=", mn, ", max=", mx)))
  }

  list(train = xt, val = xv, applied = FALSE, detail = paste0("unknown method: ", method_raw), used = NA_character_)
}

.tv_col_is_numeric_like <- function(x) {
  if (is.numeric(x) || is.integer(x) || is.logical(x)) return(TRUE)
  if (is.factor(x)) x <- as.character(x)
  if (!is.character(x)) return(FALSE)
  xc <- trimws(x)
  suppressWarnings(all(is.na(x) | grepl("^[0-9eE.+-]+$", xc)))
}

.tv_apply_continuous_preprocess <- function(df_train, df_val, tv_cfg) {
  pp <- tv_cfg$continuous_preprocess %||% list()
  if (!isTRUE(pp$enable %||% FALSE)) {
    return(list(train = df_train, val = df_val, log = NULL))
  }
  def <- .tv_normalize_method(pp$default_method %||% "none")
  byv <- pp$by_var %||% list()
  if (length(byv) && !is.list(byv)) {
    byv <- as.list(byv)
  }
  opts <- list(
    log_use_log1p_if_nonpositive = pp$log_use_log1p_if_nonpositive,
    minmax_clip_validation       = pp$minmax_clip_validation
  )
  tr <- df_train
  va <- df_val
  log_rows <- list()

  for (cn in names(tr)) {
    if (cn == "Group") next
    if (!cn %in% names(va)) next
    if (!.tv_col_is_numeric_like(tr[[cn]])) next

    meth <- if (!is.null(byv[[cn]])) byv[[cn]] else def
    meth <- .tv_normalize_method(meth)
    if (meth %in% c("none", "identity")) next

    res <- .tv_preprocess_vectors(tr[[cn]], va[[cn]], meth, opts)
    if (isTRUE(res$applied)) {
      tr[[cn]] <- res$train
      va[[cn]] <- res$val
      log_rows[[length(log_rows) + 1L]] <- data.frame(
        variable     = cn,
        method_input = as.character(byv[[cn]] %||% def),
        method_used  = as.character(res$used %||% meth),
        detail       = res$detail %||% NA_character_,
        stringsAsFactors = FALSE
      )
    } else if (isFALSE(res$applied)) {
      dtl <- res$detail
      if (length(dtl) == 1L && !is.na(dtl) && nzchar(as.character(dtl)) &&
          !identical(as.character(dtl), "none")) {
        log_rows[[length(log_rows) + 1L]] <- data.frame(
          variable     = cn,
          method_input = as.character(byv[[cn]] %||% def),
          method_used  = "skipped",
          detail       = dtl,
          stringsAsFactors = FALSE
        )
      }
    }
  }

  log_df <- if (length(log_rows)) do.call(rbind, log_rows) else NULL
  list(train = tr, val = va, log = log_df)
}

.tv_test_normality <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  x <- x[is.finite(x)]
  n <- length(x)
  if (n < 3L) return(FALSE)
  p <- tryCatch(
    if (n > 5000L) {
      stats::ks.test(scale(x), "pnorm")$p.value
    } else {
      stats::shapiro.test(x)$p.value
    },
    error = function(e) 0
  )
  isTRUE(p >= 0.05)
}

.tv_fmt_num2 <- function(x) sprintf("%.2f", x)

.tv_fmt_p <- function(p) {
  if (is.null(p) || length(p) != 1L || is.na(p)) return("")
  if (p < 0.001) return("<0.001")
  s <- format(round(p, 3), nsmall = 3, scientific = FALSE, trim = TRUE)
  sub("^0\\.", ".", s)
}

.tv_p_two_sample_numeric <- function(x_tr, x_va, normal) {
  x_tr <- suppressWarnings(as.numeric(x_tr))
  x_va <- suppressWarnings(as.numeric(x_va))
  x_tr <- x_tr[is.finite(x_tr)]
  x_va <- x_va[is.finite(x_va)]
  if (length(x_tr) < 2L || length(x_va) < 2L) return(NA_real_)
  if (length(unique(c(x_tr, x_va))) < 2L) return(NA_real_)
  tryCatch(
    if (isTRUE(normal)) {
      stats::t.test(x_tr, x_va)$p.value
    } else {
      stats::wilcox.test(x_tr, x_va, exact = FALSE)$p.value
    },
    error = function(e) NA_real_
  )
}

.tv_summarize_numeric <- function(x, normal) {
  x <- suppressWarnings(as.numeric(x))
  x <- x[is.finite(x)]
  if (length(x) == 0L) return("")
  if (isTRUE(normal)) {
    paste0(.tv_fmt_num2(mean(x)), " ± ", .tv_fmt_num2(stats::sd(x)))
  } else {
    q <- stats::quantile(x, probs = c(0.25, 0.5, 0.75), na.rm = TRUE, type = 7)
    paste0(
      .tv_fmt_num2(q[2L]), " (",
      .tv_fmt_num2(q[1L]), ", ",
      .tv_fmt_num2(q[3L]), ")"
    )
  }
}

.tv_p_cat <- function(tr, va, v) {
  a <- tr[[v]]
  b <- va[[v]]
  if (is.factor(a)) a <- as.character(a)
  if (is.factor(b)) b <- as.character(b)
  tab <- rbind(
    table(factor(a, exclude = NULL)),
    table(factor(b, exclude = NULL))
  )
  if (nrow(tab) < 2L || ncol(tab) < 1L) return(NA_real_)
  tab[is.na(tab)] <- 0
  tryCatch(
    {
      exp <- sum(tab) * (rowSums(tab) / sum(tab)) %o% (colSums(tab) / sum(tab))
      if (nrow(tab) == 2L && ncol(tab) == 2L) {
        as.numeric(stats::fisher.test(tab)$p.value)
      } else if (any(exp < 5, na.rm = TRUE)) {
        as.numeric(stats::chisq.test(tab, simulate.p.value = TRUE, B = 10000L)$p.value)
      } else {
        as.numeric(stats::chisq.test(tab)$p.value)
      }
    },
    error = function(e) NA_real_
  )
}

.tv_row_categorical <- function(tr, va, v, lbl) {
  a <- tr[[v]]
  b <- va[[v]]
  if (is.factor(a)) a <- as.character(a)
  if (is.factor(b)) b <- as.character(b)
  levs <- sort(unique(c(a, b)))
  levs <- levs[!is.na(levs) & nzchar(as.character(levs))]
  p <- .tv_p_cat(tr, va, v)
  rows <- list()
  rows[[1L]] <- data.frame(
    Variables = lbl,
    Training = "",
    Validation = "",
    P = .tv_fmt_p(p),
    .p_raw = p,
    stringsAsFactors = FALSE
  )
  for (lv in levs) {
    n1 <- sum(a == lv, na.rm = TRUE)
    n2 <- sum(b == lv, na.rm = TRUE)
    d1 <- if (nrow(tr) > 0L) round(100 * n1 / nrow(tr), 1) else NA_real_
    d2 <- if (nrow(va) > 0L) round(100 * n2 / nrow(va), 1) else NA_real_
    s1 <- paste0(n1, " (", d1, "%)")
    s2 <- paste0(n2, " (", d2, "%)")
    rows[[length(rows) + 1L]] <- data.frame(
      Variables = paste0("  ", lv),
      Training = s1,
      Validation = s2,
      P = "",
      .p_raw = NA_real_,
      stringsAsFactors = FALSE
    )
  }
  dplyr::bind_rows(rows)
}

.tv_build_table <- function(tr, va, vars, lbl_map) {
  out <- list()
  for (v in vars) {
    lbl <- lbl_map[[v]] %||% v
    if (!v %in% names(tr)) next
    xv <- tr[[v]]
    xv_chr <- trimws(as.character(xv))
    looks_numeric <- suppressWarnings(all(is.na(xv) | grepl("^[0-9.-]+$", xv_chr)))
    is_num <- is.numeric(xv) || (is.character(xv) && looks_numeric)
    if (is_num) {
      xv <- suppressWarnings(as.numeric(tr[[v]]))
      pool <- c(suppressWarnings(as.numeric(tr[[v]])), suppressWarnings(as.numeric(va[[v]])))
      pool <- pool[is.finite(pool)]
      normal <- .tv_test_normality(pool)
      lab <- if (normal) paste0(lbl, ", mean ± SD") else paste0(lbl, ", M (Q1, Q3)")
      p <- .tv_p_two_sample_numeric(tr[[v]], va[[v]], normal)
      out[[length(out) + 1L]] <- data.frame(
        Variables = lab,
        Training = .tv_summarize_numeric(tr[[v]], normal),
        Validation = .tv_summarize_numeric(va[[v]], normal),
        P = .tv_fmt_p(p),
        .p_raw = p,
        stringsAsFactors = FALSE
      )
    } else {
      out[[length(out) + 1L]] <- .tv_row_categorical(tr, va, v, lbl)
    }
  }
  dplyr::bind_rows(out)
}

block_train_validation <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(dplyr)
  })

  cfg <- ctx$config
  tv  <- cfg$train_validation %||% list()
  if (isFALSE(tv$enable %||% TRUE)) {
    cli::cli_alert_info("config$train_validation$enable=FALSE，跳过 train_validation。")
    return(ctx)
  }

  ## 外验库整库不划分：train/test 均为全集（MICE 拟合用 train；ML 只评 test）
  if (identical(tv$mode, "external_all") || isTRUE(tv$external_all)) {
    data <- ctx$data$imputed %||% ctx$data$cleaned
    if (is.null(data) || !is.data.frame(data) || nrow(data) < 1L) {
      stop("train_validation external_all: 需要非空 cleaned/imputed。", call. = FALSE)
    }
    ctx$data$train <- data
    ctx$data$test <- data
    ctx$results$train_validation_external_all <- TRUE
    tv$passthrough <- TRUE
    tv$mode <- "passthrough"
    ctx$config$train_validation <- tv
    cli::cli_alert_info(
      "train_validation external_all: 不划分，整库 n={nrow(data)} 作为外验集。"
    )
  }

  passthrough <- isTRUE(tv$passthrough) || identical(tv$mode, "passthrough")
  if (passthrough) {
    df_train <- ctx$data$train
    df_val   <- ctx$data$test
    if (is.null(df_train) || !is.data.frame(df_train) || nrow(df_train) < 1L) {
      stop("train_validation passthrough: 需要非空 ctx$data$train。", call. = FALSE)
    }
    if (is.null(df_val) || !is.data.frame(df_val)) {
      stop("train_validation passthrough: 需要 ctx$data$test。", call. = FALSE)
    }

    cli::cli_alert_info("train_validation passthrough: 保留已有 train/test，跳过重划分。")

    # ML 块要求 ctx$data$train/test 含 Group（正常路径在划分前写入；passthrough 须补）
    id_col      <- cfg$data$id_column %||% NULL
    outcome_col <- cfg$data$outcome_column %||% "Disease"
    ana_group   <- cfg$project$analysis_group %||% cfg$project$disease %||% "Case"
    ref_group   <- cfg$project$reference_group %||% "Control"
    .tv_add_group <- function(d) {
      if (!is.data.frame(d)) return(d)
      if ("Group" %in% names(d) && !outcome_col %in% names(d)) return(d)
      if (!outcome_col %in% names(d)) {
        stop("train_validation passthrough: 结局列 ", outcome_col, " 不在数据中。", call. = FALSE)
      }
      y_chr <- trimws(as.character(d[[outcome_col]]))
      d$Group <- factor(
        dplyr::case_when(
          y_chr == trimws(ana_group) ~ ana_group,
          y_chr == trimws(ref_group) ~ ref_group,
          TRUE ~ NA_character_
        ),
        levels = c(ref_group, ana_group)
      )
      d <- d[!is.na(d$Group), , drop = FALSE]
      # Keep original outcome (e.g. DN) for association blocks; ML uses Group.
      d
    }
    df_train <- .tv_add_group(df_train)
    df_val   <- .tv_add_group(df_val)
    if (nrow(df_train) < 1L || nrow(df_val) < 1L) {
      stop("train_validation passthrough: Group 映射后 train/test 为空。", call. = FALSE)
    }
    ctx$data$train <- df_train
    ctx$data$test  <- df_val

    bl        <- cfg$baseline %||% list()
    non_vars  <- unique(c(
      "Group",
      id_col %||% character(0),
      cfg$survival$time_var %||% character(0),
      cfg$survival$event_var %||% character(0)
    ))
    non_vars <- non_vars[nzchar(as.character(non_vars))]
    pool <- df_train
    candidates <- setdiff(names(pool), non_vars)
    excl <- as.character(bl$exclude_vars %||% character(0))
    candidates <- setdiff(candidates, excl[excl %in% candidates])
    tv_cmp <- tv$comparison_vars
    inc <- bl$include_vars
    if (!is.null(tv_cmp) && length(as.character(tv_cmp)) > 0L) {
      vars <- as.character(tv_cmp)
      vars <- vars[vars %in% names(pool)]
    } else if (!is.null(inc) && length(as.character(inc)) > 0L) {
      inc <- as.character(inc)
      vars <- inc[inc %in% candidates]
    } else {
      vars <- candidates
    }

    vl <- tv$variable_labels
    lbl_map <- if (is.null(vl) || !length(vl)) list() else as.list(vl)

    if (isTRUE(tv$export_baseline_table %||% FALSE) && length(vars)) {
      tab <- .tv_build_table(df_train, df_val, vars, lbl_map)
      tab_export <- tab[, setdiff(names(tab), ".p_raw"), drop = FALSE]
      names_tr <- paste0("Training (n = ", nrow(df_train), ")")
      names_va <- paste0("Validation (n = ", nrow(df_val), ")")
      names(tab_export)[names(tab_export) == "Training"] <- names_tr
      names(tab_export)[names(tab_export) == "Validation"] <- names_va
      title_tbl <- tv$table_title %||% pub_title(ctx, "main_table",
        "Baseline characteristics stratified by training and validation sets")
      fp <- file.path(
        ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables"),
        "Table_1_Baseline_characteristics_train_val_split.xlsx"
      )
      export_sci_table(tab_export, fp, title = title_tbl, sheet = "Table1")
      ctx <- render_queued_tables(ctx)
      tryCatch(
        {
          if (requireNamespace("openxlsx", quietly = TRUE) && file.exists(fp)) {
            wb <- openxlsx::loadWorkbook(fp)
            openxlsx::modifyBaseFont(wb, fontSize = 11L, fontName = "Times New Roman")
            openxlsx::saveWorkbook(wb, fp, overwrite = TRUE)
          }
        },
        error = function(e) invisible(NULL)
      )
      ctx$results$table_train_val_baseline <- tab_export
    }

    ctx$results$train_validation_mode <- "passthrough"
    ctx$results$train_validation_attempts <- 0L

    data_dir <- file.path(ctx$output_dir, "Data")
    if (!dir.exists(data_dir)) dir.create(data_dir, recursive = TRUE)
    save(df_train, file = file.path(data_dir, "df_train_RData.RData"))
    save(df_val, file = file.path(data_dir, "df_validation_RData.RData"))
    saveRDS(df_train, file.path(data_dir, "df_train.rds"))
    saveRDS(df_val, file.path(data_dir, "df_validation.rds"))
    utils::write.csv(df_train, file.path(data_dir, "df_train.csv"), row.names = FALSE, fileEncoding = "UTF-8")
    utils::write.csv(df_val, file.path(data_dir, "df_validation.csv"), row.names = FALSE, fileEncoding = "UTF-8")

    ctx <- save_result(
      ctx, "train_validation_meta",
      data.frame(
        mode = "passthrough",
        seed_used = NA_integer_,
        attempts = 0L,
        train_n = nrow(df_train),
        val_n = nrow(df_val),
        train_ratio = NA_real_,
        stratify = NA
      ),
      "train_validation_split_meta.csv"
    )
    cli::cli_alert_success(
      "train_validation passthrough: train n={nrow(df_train)}, test n={nrow(df_val)}（已写 Group + Data 导出）"
    )
    return(ctx)
  }

  suppressPackageStartupMessages(library(rsample))

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("train_validation: 请先运行 imputation / data_clean。", call. = FALSE)

  outcome_col <- cfg$data$outcome_column %||% "Disease"
  id_col      <- cfg$data$id_column %||% NULL
  ana_group   <- cfg$project$analysis_group %||% cfg$project$disease %||% "Case"
  ref_group   <- cfg$project$reference_group %||% "Control"
  sp_cfg      <- cfg$splitting %||% list()

  train_ratio <- as.numeric(tv$train_ratio %||% sp_cfg$train_ratio %||% 0.7)[1L]
  stratify    <- isTRUE(tv$stratify %||% sp_cfg$stratify %||% TRUE)
  p_strict    <- as.numeric(tv$p_strict %||% 0.05)[1L]
  max_iter    <- as.integer(tv$max_resplit_iter %||% 2000L)[1L]
  base_seed   <- as.integer(tv$base_seed %||% sp_cfg$seed %||% cfg$imputation$seed %||% cfg$ml_models$seed %||% 42L)[1L]

  if (train_ratio <= 0 || train_ratio >= 1) {
    stop("train_validation: train_ratio 须在 (0,1) 内。", call. = FALSE)
  }

  if (!outcome_col %in% names(data)) {
    stop("train_validation: 结局列 ", outcome_col, " 不在数据中。", call. = FALSE)
  }

  d <- data
  y_chr <- trimws(as.character(d[[outcome_col]]))
  d$Group <- factor(
    dplyr::case_when(
      y_chr == trimws(ana_group) ~ ana_group,
      y_chr == trimws(ref_group) ~ ref_group,
      TRUE ~ NA_character_
    ),
    levels = c(ref_group, ana_group)
  )
  d <- d[!is.na(d$Group), , drop = FALSE]
  if (nrow(d) < 30L) stop("train_validation: 有效样本过少。", call. = FALSE)

  # 保留原结局列（如 DN）供关联块 / fit_on=train 使用；ML 仍以 Group 为主

  bl <- cfg$baseline %||% list()
  non_vars <- unique(c(
    "Group",
    id_col %||% character(0),
    cfg$survival$time_var %||% character(0),
    cfg$survival$event_var %||% character(0)
  ))
  non_vars <- non_vars[nzchar(as.character(non_vars))]
  candidates <- setdiff(names(d), non_vars)
  excl <- as.character(bl$exclude_vars %||% character(0))
  candidates <- setdiff(candidates, excl[excl %in% candidates])
  tv_cmp <- tv$comparison_vars
  inc <- bl$include_vars
  if (!is.null(tv_cmp) && length(as.character(tv_cmp)) > 0L) {
    vars <- as.character(tv_cmp)
    vars <- vars[vars %in% names(d)]
  } else if (!is.null(inc) && length(as.character(inc)) > 0L) {
    inc <- as.character(inc)
    vars <- inc[inc %in% candidates]
  } else {
    vars <- candidates
  }
  if (!length(vars)) stop("train_validation: 无可用比较变量，请设置 baseline$include_vars 或 train_validation$comparison_vars。", call. = FALSE)

  vl <- tv$variable_labels
  lbl_map <- if (is.null(vl) || !length(vl)) {
    list()
  } else {
    as.list(vl)
  }

  attempt <- 0L
  ok <- FALSE
  df_train <- NULL
  df_val <- NULL
  tab_export <- NULL
  last_tr <- NULL; last_va <- NULL; last_tab <- NULL

  while (attempt < max_iter && !ok) {
    attempt <- attempt + 1L
    s <- as.integer(base_seed + (attempt - 1L) * 7919L)
    set.seed(s)
    spl <- if (stratify) {
      rsample::initial_split(d, prop = train_ratio, strata = "Group")
    } else {
      rsample::initial_split(d, prop = train_ratio)
    }
    tr <- rsample::training(spl)
    va <- rsample::testing(spl)
    tab <- .tv_build_table(tr, va, vars, lbl_map)
    pr <- tab$.p_raw
    pr <- pr[is.finite(pr)]
    if (length(pr) == 0L) {
      ok <- TRUE
    } else {
      ok <- min(pr, na.rm = TRUE) > p_strict
    }
    last_tr <- tr; last_va <- va; last_tab <- tab
    if (ok) {
      df_train <- tr
      df_val   <- va
      tab_export <- tab[, setdiff(names(tab), ".p_raw"), drop = FALSE]
    }
  }

  if (!ok) {
    ctx$results$pause_point <- list(
      block = "train_validation",
      reason = paste0(
        "在 ", max_iter, " 次重新划分内，仍存在 P ≤ ", p_strict,
        " 的变量（训练/验证基线不可比）。"
      ),
      suggestion = paste0(
        "可尝试：增大 max_resplit_iter、调整 train_ratio、减少 comparison_vars、",
        "或放宽 p_strict（不推荐发表场景）。"
      ),
      last_attempt = attempt
    )
    cli::cli_alert_warning(paste0(
      "train_validation: 在 ", max_iter, " 次重划分内仍存在 P ≤ ", p_strict,
      " 的变量，将使用最后一次划分继续（发表时请注意说明）。"
    ))
    df_train   <- last_tr
    df_val     <- last_va
    tab_export <- last_tab[, setdiff(names(last_tab), ".p_raw"), drop = FALSE]
  }

  ppres <- .tv_apply_continuous_preprocess(df_train, df_val, tv)
  df_train <- ppres$train
  df_val   <- ppres$val

  names_tr <- paste0("Training (n = ", nrow(df_train), ")")
  names_va <- paste0("Validation (n = ", nrow(df_val), ")")
  names(tab_export)[names(tab_export) == "Training"] <- names_tr
  names(tab_export)[names(tab_export) == "Validation"] <- names_va

  data_dir <- file.path(ctx$output_dir, "Data")
  if (!dir.exists(data_dir)) dir.create(data_dir, recursive = TRUE)
  if (!is.null(ppres$log) && nrow(ppres$log) > 0L) {
    ctx$results$train_validation_continuous_preprocess <- ppres$log
    utils::write.csv(
      ppres$log,
      file.path(data_dir, "train_validation_continuous_preprocess.csv"),
      row.names = FALSE,
      fileEncoding = "UTF-8"
    )
    cli::cli_alert_info(
      "continuous_preprocess: 已按 config 变换数值列，记录见 Data/train_validation_continuous_preprocess.csv"
    )
  }

  save(df_train, file = file.path(data_dir, "df_train_RData.RData"))
  save(df_val, file = file.path(data_dir, "df_validation_RData.RData"))
  saveRDS(df_train, file.path(data_dir, "df_train.rds"))
  saveRDS(df_val, file.path(data_dir, "df_validation.rds"))
  utils::write.csv(df_train, file.path(data_dir, "df_train.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  utils::write.csv(df_val, file.path(data_dir, "df_validation.csv"), row.names = FALSE, fileEncoding = "UTF-8")

  ctx$data$train <- df_train
  ctx$data$test  <- df_val

  if (isTRUE(tv$export_baseline_table %||% FALSE)) {
    title_tbl <- tv$table_title %||% pub_title(ctx, "main_table",
      "Baseline characteristics stratified by training and validation sets")
    fp <- file.path(
      ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables"),
      "Table_1_Baseline_characteristics_train_val_split.xlsx"
    )
    export_sci_table(tab_export, fp, title = title_tbl, sheet = "Table1")
    ctx <- render_queued_tables(ctx)
    tryCatch(
      {
        if (requireNamespace("openxlsx", quietly = TRUE) && file.exists(fp)) {
          wb <- openxlsx::loadWorkbook(fp)
          openxlsx::modifyBaseFont(wb, fontSize = 11L, fontName = "Times New Roman")
          openxlsx::saveWorkbook(wb, fp, overwrite = TRUE)
        }
      },
      error = function(e) invisible(NULL)
    )
    ctx$results$table_train_val_baseline <- tab_export
  }
  ctx$results$train_validation_seed_used <- as.integer(base_seed + (attempt - 1L) * 7919L)
  ctx$results$train_validation_attempts  <- attempt
  ctx <- save_result(
    ctx, "train_validation_meta",
    data.frame(
      seed_used = ctx$results$train_validation_seed_used,
      attempts = attempt,
      train_n = nrow(df_train),
      val_n = nrow(df_val),
      train_ratio = train_ratio,
      stratify = stratify
    ),
    "train_validation_split_meta.csv"
  )

  cli::cli_alert_success(
    "train_validation: 划分完成（尝试 {attempt} 次，种子={ctx$results$train_validation_seed_used}）；全部检验 P > {p_strict}"
  )
  ctx
}

register_block(
  "train_validation",
  block_train_validation,
  "训练/验证集划分及基线可比性表（P 全部 > 阈值后定稿）"
)
