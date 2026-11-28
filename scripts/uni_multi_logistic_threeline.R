###############################################################################
#  uni_multi_logistic_threeline.R
#
#  独立总结脚本（不依赖 block 引擎）：
#    全样本 All 描述 → 单因素 Logistic → p<阈值入选多因素 → SCI 三线表 xlsx
#
#  用法:
#    1) 改「参数区」后:
#         Rscript scripts/uni_multi_logistic_threeline.R
#    2) 或 source 后调用:
#         source("scripts/uni_multi_logistic_threeline.R")
#         # 已在文件末尾按参数区自动跑；也可设 .RUN_ON_SOURCE <- FALSE 后手动调用
#
#  设计: docs/superpowers/specs/2026-11-04-uni-multi-logistic-threeline-design.md
###############################################################################

.RUN_ON_SOURCE <- TRUE

# ═══════════════════════════════════════════════════════════════════════════
#  参数区（真实数据只改这里）
# ═══════════════════════════════════════════════════════════════════════════

params <- list(
  ## TRUE = 内置模拟数据；FALSE = 读 data_path
  use_demo = TRUE,
  ## CSV 或 RDS；use_demo=FALSE 时必填
  data_path = "",
  ## 二分类结局列名（0/1 或两水平 factor）
  outcome = "outcome",
  ## 候选自变量；NULL / character(0) = 除结局外全部列
  predictors = c("age", "sex", "bmi", "smoke", "hypertension", "diabetes"),
  ## 分类变量参照水平：list(sex = "Female", smoke = "Never")；未指定取水平排序第一个
  ref_levels = list(sex = "Female", smoke = "Never"),
  ## 强制当连续处理的列
  force_continuous_vars = c("age", "bmi"),
  ## 唯一值 ≤ 该阈值视为分类（force_continuous_vars 除外）
  discrete_max_levels = 5L,
  ## TRUE: 连续变量用 Median [IQR]；FALSE: Mean ± SD
  skew_use_median = FALSE,
  ## 单因素入选多因素的 p 阈值
  uni_p_cutoff = 0.05,
  ## 输出目录（相对仓库根或绝对路径）
  out_dir = "Output/uni_multi_logistic_threeline",
  table_file = "Univariable_Multivariable_Logistic_Analysis.xlsx",
  table_title = "Univariable and Multivariable Logistic Regression Analysis",
  footnotes = c(
    "All: overall descriptive statistics (n (%) for categorical; Mean ± SD for continuous unless Median [IQR] enabled).",
    "OR: odds ratio from binomial logistic regression; 95% CI from Wald method.",
    "Variables with univariable P < cutoff entered the multivariable model.",
    "Reference: reference level of categorical predictors."
  )
)

# ═══════════════════════════════════════════════════════════════════════════
#  工具函数
# ═══════════════════════════════════════════════════════════════════════════

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x

.uml_repo_root <- function() {
  ## 优先脚本所在仓库根（.../01Block）
  cmd <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", cmd, value = TRUE)
  if (length(file_arg)) {
    script <- normalizePath(sub("^--file=", "", file_arg[1L]), winslash = "/", mustWork = FALSE)
    if (nzchar(script) && file.exists(script)) {
      return(normalizePath(file.path(dirname(script), ".."), winslash = "/", mustWork = FALSE))
    }
  }
  if (file.exists("scripts/uni_multi_logistic_threeline.R")) {
    return(normalizePath(".", winslash = "/", mustWork = FALSE))
  }
  if (file.exists("uni_multi_logistic_threeline.R")) {
    return(normalizePath("..", winslash = "/", mustWork = FALSE))
  }
  normalizePath(getwd(), winslash = "/", mustWork = FALSE)
}

.uml_fmt_num <- function(x, digits = 2L) {
  if (length(x) != 1L || is.na(x) || !is.finite(as.numeric(x))) return("")
  formatC(as.numeric(x), format = "f", digits = digits)
}

.uml_fmt_p <- function(p) {
  if (length(p) != 1L || is.na(p) || !is.finite(as.numeric(p))) return("")
  p <- as.numeric(p)
  if (p < 0.001) return("<0.001")
  formatC(p, format = "f", digits = 3)
}

.uml_fmt_or_ci <- function(or, lo, hi) {
  if (length(or) != 1L || is.na(or) || !is.finite(as.numeric(or))) return("")
  if (is.na(lo) || is.na(hi) || !is.finite(lo) || !is.finite(hi)) {
    return(.uml_fmt_num(or, 2L))
  }
  paste0(.uml_fmt_num(or, 2L), " (", .uml_fmt_num(lo, 2L), "-", .uml_fmt_num(hi, 2L), ")")
}

.uml_make_demo <- function(n = 400L, seed = 20261104L) {
  set.seed(seed)
  age <- round(rnorm(n, 62, 12), 1)
  sex <- factor(sample(c("Female", "Male"), n, TRUE, prob = c(0.48, 0.52)))
  bmi <- round(rnorm(n, 26, 4), 1)
  smoke <- factor(
    sample(c("Never", "Former", "Current"), n, TRUE, prob = c(0.5, 0.3, 0.2)),
    levels = c("Never", "Former", "Current")
  )
  hypertension <- factor(sample(c("No", "Yes"), n, TRUE, prob = c(0.55, 0.45)))
  diabetes <- factor(sample(c("No", "Yes"), n, TRUE, prob = c(0.7, 0.3)))
  lp <- -5.2 +
    0.035 * age +
    0.55 * (sex == "Male") +
    0.08 * bmi +
    0.45 * (smoke == "Former") +
    0.90 * (smoke == "Current") +
    0.85 * (hypertension == "Yes") +
    1.00 * (diabetes == "Yes")
  pr <- 1 / (1 + exp(-lp))
  outcome <- rbinom(n, 1L, pr)
  data.frame(
    age = age, sex = sex, bmi = bmi, smoke = smoke,
    hypertension = hypertension, diabetes = diabetes,
    outcome = outcome,
    stringsAsFactors = FALSE
  )
}

.uml_read_data <- function(path) {
  path <- as.character(path)[1L]
  if (!nzchar(path) || !file.exists(path)) {
    stop("data_path 无效或不存在: ", path, call. = FALSE)
  }
  ext <- tolower(tools::file_ext(path))
  if (ext == "rds") {
    obj <- readRDS(path)
    if (!is.data.frame(obj)) stop("RDS 内容不是 data.frame", call. = FALSE)
    return(obj)
  }
  if (ext %in% c("csv", "txt")) {
    return(utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE))
  }
  stop("仅支持 CSV/TXT/RDS: ", path, call. = FALSE)
}

.uml_prepare_outcome <- function(data, outcome) {
  if (!outcome %in% names(data)) stop("缺少结局列: ", outcome, call. = FALSE)
  y <- data[[outcome]]
  if (is.factor(y) || is.character(y)) {
    lev <- unique(as.character(y[!is.na(y)]))
    if (length(lev) != 2L) {
      stop("结局必须恰好 2 个水平，当前: ", paste(lev, collapse = ", "), call. = FALSE)
    }
    ## 默认后一水平为事件（与 factor 默认 contrasts 一致时可指定）
    y2 <- as.integer(factor(as.character(y), levels = sort(lev))) - 1L
    data[[outcome]] <- y2
    attr(data, "outcome_event_level") <- sort(lev)[2L]
  } else {
    y_num <- suppressWarnings(as.numeric(y))
    uniq <- sort(unique(y_num[!is.na(y_num)]))
    if (!all(uniq %in% c(0, 1)) || length(uniq) != 2L) {
      stop("数值结局须为 0/1 二分类", call. = FALSE)
    }
    data[[outcome]] <- as.integer(y_num)
    attr(data, "outcome_event_level") <- "1"
  }
  data
}

.uml_is_continuous <- function(x, force_cont, discrete_max_levels) {
  if (isTRUE(force_cont)) return(TRUE)
  if (is.factor(x) || is.character(x) || is.logical(x)) return(FALSE)
  nlev <- length(unique(x[!is.na(x)]))
  is.numeric(x) && nlev > as.integer(discrete_max_levels)
}

.uml_as_predictor <- function(x, v, continuous, ref_levels) {
  if (continuous) {
    return(as.numeric(x))
  }
  xc <- if (is.factor(x)) as.character(x) else as.character(x)
  lev <- unique(xc[!is.na(xc)])
  ref <- ref_levels[[v]]
  if (!is.null(ref) && ref %in% lev) {
    lev <- c(ref, setdiff(sort(lev), ref))
  } else {
    lev <- sort(lev)
  }
  factor(xc, levels = lev)
}

.uml_all_stat <- function(x, continuous, skew_use_median) {
  x <- x[!is.na(x)]
  if (!length(x)) return("")
  if (continuous) {
    x <- as.numeric(x)
    if (isTRUE(skew_use_median)) {
      qs <- stats::quantile(x, probs = c(0.25, 0.5, 0.75), na.rm = TRUE, names = FALSE)
      return(sprintf("%s [%s-%s]", .uml_fmt_num(qs[2], 2), .uml_fmt_num(qs[1], 2), .uml_fmt_num(qs[3], 2)))
    }
    return(sprintf("%s ± %s", .uml_fmt_num(mean(x), 2), .uml_fmt_num(stats::sd(x), 2)))
  }
  ## 分类：返回各水平 n (%) 的命名向量，由调用方拆行
  tab <- table(x)
  n <- sum(tab)
  pct <- if (n > 0) as.numeric(tab) / n * 100 else rep(0, length(tab))
  setNames(
    sprintf("%d (%.1f)", as.integer(tab), pct),
    names(tab)
  )
}

.uml_fit_glm_or <- function(data, outcome, rhs_vars) {
  rhs_vars <- unique(as.character(rhs_vars))
  rhs_vars <- rhs_vars[nzchar(rhs_vars) & rhs_vars %in% names(data)]
  if (!length(rhs_vars)) return(NULL)
  fml <- stats::as.formula(paste0(outcome, " ~ ", paste(rhs_vars, collapse = " + ")))
  fit <- tryCatch(
    stats::glm(fml, data = data, family = stats::binomial(link = "logit")),
    error = function(e) {
      warning("glm 失败 [", paste(rhs_vars, collapse = "+"), "]: ", e$message, call. = FALSE)
      NULL
    }
  )
  if (is.null(fit)) return(NULL)
  s <- summary(fit)
  co <- s$coefficients
  if (is.null(co) || !nrow(co)) return(NULL)
  nm <- rownames(co)
  keep <- nm != "(Intercept)"
  if (!any(keep)) {
    return(data.frame(
      term = character(0), OR = numeric(0), CI_lo = numeric(0),
      CI_hi = numeric(0), P = numeric(0), stringsAsFactors = FALSE
    ))
  }
  est <- co[keep, "Estimate", drop = TRUE]
  se  <- co[keep, "Std. Error", drop = TRUE]
  p   <- co[keep, "Pr(>|z|)", drop = TRUE]
  data.frame(
    term  = nm[keep],
    OR    = as.numeric(exp(est)),
    CI_lo = as.numeric(exp(est - 1.96 * se)),
    CI_hi = as.numeric(exp(est + 1.96 * se)),
    P     = as.numeric(p),
    stringsAsFactors = FALSE
  )
}

.uml_build_rows_for_var <- function(data, var, outcome, continuous, ref_levels,
                                   skew_use_median, uni_df, multi_df) {
  x <- data[[var]]
  x <- .uml_as_predictor(x, var, continuous, ref_levels)
  data[[var]] <- x

  if (continuous) {
    all_s <- .uml_all_stat(x, TRUE, skew_use_median)
    hit <- uni_df[uni_df$term == var, , drop = FALSE]
    mhit <- multi_df[multi_df$term == var, , drop = FALSE]
    return(data.frame(
      Variable = var,
      All = all_s,
      `Univariable OR (95%CI)` = if (nrow(hit)) .uml_fmt_or_ci(hit$OR[1], hit$CI_lo[1], hit$CI_hi[1]) else "",
      `P` = if (nrow(hit)) .uml_fmt_p(hit$P[1]) else "",
      `Multivariable OR (95%CI)` = if (nrow(mhit)) .uml_fmt_or_ci(mhit$OR[1], mhit$CI_lo[1], mhit$CI_hi[1]) else "",
      `P_multi` = if (nrow(mhit)) .uml_fmt_p(mhit$P[1]) else "",
      .var = var,
      .level = NA_character_,
      .uni_p = if (nrow(hit)) hit$P[1] else NA_real_,
      stringsAsFactors = FALSE,
      check.names = FALSE
    ))
  }

  lev <- levels(x)
  all_map <- .uml_all_stat(x, FALSE, skew_use_median)
  ref <- lev[1L]
  rows <- list()
  ## 变量标题行
  rows[[length(rows) + 1L]] <- data.frame(
    Variable = var,
    All = "",
    `Univariable OR (95%CI)` = "",
    `P` = "",
    `Multivariable OR (95%CI)` = "",
    `P_multi` = "",
    .var = var,
    .level = NA_character_,
    .uni_p = NA_real_,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  for (lv in lev) {
    term <- paste0(var, lv)
    hit <- uni_df[uni_df$term == term, , drop = FALSE]
    mhit <- multi_df[multi_df$term == term, , drop = FALSE]
    is_ref <- identical(lv, ref)
    uni_or <- if (is_ref) "Reference" else if (nrow(hit)) .uml_fmt_or_ci(hit$OR[1], hit$CI_lo[1], hit$CI_hi[1]) else ""
    uni_p  <- if (is_ref) "Reference" else if (nrow(hit)) .uml_fmt_p(hit$P[1]) else ""
    ## 多因素：仅当该变量入选时填 Reference / 数值
    var_in_multi <- any(startsWith(multi_df$term, var)) || var %in% multi_df$term
    if (!var_in_multi) {
      multi_or <- ""
      multi_p <- ""
    } else if (is_ref) {
      multi_or <- "Reference"
      multi_p <- "Reference"
    } else if (nrow(mhit)) {
      multi_or <- .uml_fmt_or_ci(mhit$OR[1], mhit$CI_lo[1], mhit$CI_hi[1])
      multi_p <- .uml_fmt_p(mhit$P[1])
    } else {
      multi_or <- ""
      multi_p <- ""
    }
    rows[[length(rows) + 1L]] <- data.frame(
      Variable = paste0("    ", lv),
      All = if (!is.null(all_map[[lv]])) all_map[[lv]] else "",
      `Univariable OR (95%CI)` = uni_or,
      `P` = uni_p,
      `Multivariable OR (95%CI)` = multi_or,
      `P_multi` = multi_p,
      .var = var,
      .level = lv,
      .uni_p = if (nrow(hit)) hit$P[1] else if (is_ref) 1 else NA_real_,
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
  }
  do.call(rbind, rows)
}

.uml_select_multi_vars <- function(predictors, is_cont, uni_df, cutoff) {
  keep <- character(0)
  for (i in seq_along(predictors)) {
    v <- predictors[i]
    if (is_cont[i]) {
      hit <- uni_df[uni_df$term == v, , drop = FALSE]
      if (nrow(hit) && any(hit$P < cutoff, na.rm = TRUE)) keep <- c(keep, v)
    } else {
      hit <- uni_df[startsWith(uni_df$term, v), , drop = FALSE]
      if (nrow(hit) && any(hit$P < cutoff, na.rm = TRUE)) keep <- c(keep, v)
    }
  }
  unique(keep)
}

.uml_write_three_line_sheet <- function(wb, sheet, title, df, footnotes = NULL) {
  openxlsx::addWorksheet(wb, sheet, gridLines = FALSE)
  nc <- ncol(df)
  header_title_style <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman",
    halign = "center", textDecoration = "bold"
  )
  header_three_line_style <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman",
    halign = "center", textDecoration = "bold",
    border = c("top", "bottom"),
    borderStyle = c("thick", "thin")
  )
  body_center <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman", halign = "center"
  )
  body_left <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman", halign = "left"
  )
  body_last_c <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman", halign = "center",
    border = "bottom", borderStyle = "thick"
  )
  body_last_l <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman",
    halign = "left",
    border = "bottom", borderStyle = "thick"
  )
  fn_style <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman",
    halign = "left", wrapText = TRUE
  )
  fn_top <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman",
    halign = "left", wrapText = TRUE,
    border = "top", borderStyle = "thin"
  )

  body <- as.data.frame(lapply(df, function(col) as.character(col)),
                        stringsAsFactors = FALSE, check.names = FALSE)
  names(body) <- names(df)
  hdr <- as.data.frame(
    matrix(names(df), nrow = 1L),
    stringsAsFactors = FALSE, check.names = FALSE
  )
  names(hdr) <- names(df)
  out <- rbind(hdr, body)

  if (nzchar(title %||% "")) {
    openxlsx::writeData(wb, sheet, title, startRow = 1L, startCol = 1L, colNames = FALSE)
    openxlsx::mergeCells(wb, sheet, rows = 1L, cols = seq_len(nc))
    openxlsx::addStyle(wb, sheet, header_title_style, rows = 1L, cols = seq_len(nc), gridExpand = TRUE)
    data_start <- 2L
  } else {
    data_start <- 1L
  }

  openxlsx::writeData(wb, sheet, out, startRow = data_start, startCol = 1L, colNames = FALSE)
  n_tbl <- nrow(out)
  last_row <- data_start + n_tbl - 1L
  openxlsx::addStyle(
    wb, sheet, header_three_line_style,
    rows = data_start, cols = seq_len(nc), gridExpand = TRUE
  )
  if (last_row > data_start) {
    body_rows <- seq.int(data_start + 1L, last_row)
    openxlsx::addStyle(wb, sheet, body_left, rows = body_rows, cols = 1L, gridExpand = TRUE)
    if (nc >= 2L) {
      openxlsx::addStyle(
        wb, sheet, body_center,
        rows = body_rows, cols = seq.int(2L, nc), gridExpand = TRUE
      )
    }
    openxlsx::addStyle(wb, sheet, body_last_l, rows = last_row, cols = 1L, gridExpand = TRUE)
    if (nc >= 2L) {
      openxlsx::addStyle(
        wb, sheet, body_last_c,
        rows = last_row, cols = seq.int(2L, nc), gridExpand = TRUE
      )
    }
  }

  if (length(footnotes)) {
    fn <- as.character(footnotes)
    fn <- fn[nzchar(fn)]
    if (length(fn)) {
      r0 <- last_row + 2L
      for (i in seq_along(fn)) {
        r <- r0 + i - 1L
        openxlsx::writeData(wb, sheet, fn[i], startRow = r, startCol = 1L, colNames = FALSE)
        openxlsx::mergeCells(wb, sheet, rows = r, cols = seq_len(nc))
        openxlsx::addStyle(
          wb, sheet, if (i == 1L) fn_top else fn_style,
          rows = r, cols = seq_len(nc), gridExpand = TRUE
        )
      }
    }
  }

  widths <- vapply(seq_len(nc), function(j) {
    mx <- max(nchar(as.character(out[[j]]), type = "chars"), na.rm = TRUE)
    as.numeric(min(max(mx + 2L, 10L), 42L))
  }, numeric(1))
  openxlsx::setColWidths(wb, sheet, cols = seq_len(nc), widths = widths)
}

.uml_export_xlsx <- function(path, title, combined, uni_detail, multi_detail, footnotes) {
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    stop("需要安装 openxlsx: install.packages('openxlsx')", call. = FALSE)
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  wb <- openxlsx::createWorkbook()
  .uml_write_three_line_sheet(wb, "Combined", title, combined, footnotes)
  .uml_write_three_line_sheet(
    wb, "Univariable",
    paste0(title, " — Univariable"),
    uni_detail,
    footnotes[seq_len(min(2L, length(footnotes)))]
  )
  .uml_write_three_line_sheet(
    wb, "Multivariable",
    paste0(title, " — Multivariable"),
    multi_detail,
    footnotes
  )
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  invisible(path)
}

# ═══════════════════════════════════════════════════════════════════════════
#  主流程
# ═══════════════════════════════════════════════════════════════════════════

run_uni_multi_logistic_threeline <- function(params) {
  root <- .uml_repo_root()
  if (isTRUE(params$use_demo)) {
    message("[demo] 使用内置模拟数据 n=400")
    data <- .uml_make_demo()
  } else {
    dp <- params$data_path
    if (!grepl("^(?:[A-Za-z]:|/)", dp)) dp <- file.path(root, dp)
    data <- .uml_read_data(dp)
  }
  data <- .uml_prepare_outcome(data, params$outcome)

  predictors <- params$predictors
  if (is.null(predictors) || !length(predictors)) {
    predictors <- setdiff(names(data), params$outcome)
  }
  predictors <- as.character(predictors)
  miss <- setdiff(predictors, names(data))
  if (length(miss)) stop("缺少自变量列: ", paste(miss, collapse = ", "), call. = FALSE)

  force_cont <- as.character(params$force_continuous_vars %||% character(0))
  disc_max <- as.integer(params$discrete_max_levels %||% 5L)[1L]
  skew <- isTRUE(params$skew_use_median)
  cutoff <- as.numeric(params$uni_p_cutoff %||% 0.05)[1L]
  ref_levels <- params$ref_levels %||% list()

  ## 预处理列类型
  is_cont <- logical(length(predictors))
  for (i in seq_along(predictors)) {
    v <- predictors[i]
    is_cont[i] <- .uml_is_continuous(
      data[[v]], v %in% force_cont, disc_max
    )
    data[[v]] <- .uml_as_predictor(data[[v]], v, is_cont[i], ref_levels)
  }

  ## 单因素
  uni_list <- list()
  for (i in seq_along(predictors)) {
    v <- predictors[i]
    one <- .uml_fit_glm_or(data, params$outcome, v)
    if (!is.null(one) && nrow(one)) {
      one$Variable <- v
      uni_list[[length(uni_list) + 1L]] <- one
    } else {
      warning("单因素拟合无有效系数: ", v, call. = FALSE)
    }
  }
  uni_df <- if (length(uni_list)) {
    do.call(rbind, uni_list)
  } else {
    data.frame(
      term = character(0), OR = numeric(0), CI_lo = numeric(0),
      CI_hi = numeric(0), P = numeric(0), Variable = character(0),
      stringsAsFactors = FALSE
    )
  }

  multi_vars <- .uml_select_multi_vars(predictors, is_cont, uni_df, cutoff)
  message(
    "单因素入选多因素 (p < ", cutoff, "): ",
    if (length(multi_vars)) paste(multi_vars, collapse = ", ") else "(无)"
  )

  multi_df <- if (length(multi_vars)) {
    .uml_fit_glm_or(data, params$outcome, multi_vars)
  } else {
    data.frame(
      term = character(0), OR = numeric(0), CI_lo = numeric(0),
      CI_hi = numeric(0), P = numeric(0),
      stringsAsFactors = FALSE
    )
  }
  if (is.null(multi_df)) {
    multi_df <- data.frame(
      term = character(0), OR = numeric(0), CI_lo = numeric(0),
      CI_hi = numeric(0), P = numeric(0),
      stringsAsFactors = FALSE
    )
  }

  ## Combined 表
  row_list <- list()
  for (i in seq_along(predictors)) {
    row_list[[i]] <- .uml_build_rows_for_var(
      data, predictors[i], params$outcome, is_cont[i], ref_levels,
      skew, uni_df, multi_df
    )
  }
  combined_raw <- do.call(rbind, row_list)
  ## 两个 P 同名列：用列表列避免 data.frame 自动改名
  combined_mat <- as.data.frame(
    matrix(NA_character_, nrow = nrow(combined_raw), ncol = 6L),
    stringsAsFactors = FALSE
  )
  names(combined_mat) <- c(
    "Variable", "All",
    "Univariable OR (95%CI)", "P",
    "Multivariable OR (95%CI)", "P"
  )
  combined_mat[[1]] <- as.character(combined_raw$Variable)
  combined_mat[[2]] <- as.character(combined_raw$All)
  combined_mat[[3]] <- as.character(combined_raw[["Univariable OR (95%CI)"]])
  combined_mat[[4]] <- as.character(combined_raw$P)
  combined_mat[[5]] <- as.character(combined_raw[["Multivariable OR (95%CI)"]])
  combined_mat[[6]] <- as.character(combined_raw$P_multi)

  ## 明细 sheet
  uni_detail <- uni_df
  if (nrow(uni_detail)) {
    uni_detail$`OR (95%CI)` <- mapply(
      .uml_fmt_or_ci, uni_detail$OR, uni_detail$CI_lo, uni_detail$CI_hi,
      USE.NAMES = FALSE
    )
    uni_detail$P_fmt <- vapply(uni_detail$P, .uml_fmt_p, character(1))
    uni_detail <- uni_detail[, c("Variable", "term", "OR", "CI_lo", "CI_hi", "OR (95%CI)", "P", "P_fmt")]
    names(uni_detail)[names(uni_detail) == "P_fmt"] <- "P_display"
  } else {
    uni_detail <- data.frame(
      note = "No univariable estimates",
      stringsAsFactors = FALSE
    )
  }

  if (nrow(multi_df)) {
    multi_detail <- multi_df
    multi_detail$`OR (95%CI)` <- mapply(
      .uml_fmt_or_ci, multi_detail$OR, multi_detail$CI_lo, multi_detail$CI_hi,
      USE.NAMES = FALSE
    )
    multi_detail$P_display <- vapply(multi_detail$P, .uml_fmt_p, character(1))
    multi_detail <- multi_detail[, c("term", "OR", "CI_lo", "CI_hi", "OR (95%CI)", "P", "P_display")]
  } else {
    multi_detail <- data.frame(
      note = paste0(
        "No variables entered multivariable model (univariable p < ",
        cutoff, ")."
      ),
      stringsAsFactors = FALSE
    )
  }

  out_dir <- params$out_dir %||% "Output/uni_multi_logistic_threeline"
  if (!grepl("^(?:[A-Za-z]:|/)", out_dir)) out_dir <- file.path(root, out_dir)
  out_path <- file.path(out_dir, params$table_file %||% "Univariable_Multivariable_Logistic_Analysis.xlsx")

  fn <- params$footnotes %||% character(0)
  fn <- c(
    fn,
    paste0("Univariable P cutoff for multivariable entry: ", cutoff, "."),
    paste0("N = ", nrow(data), "; event N = ", sum(data[[params$outcome]] == 1L, na.rm = TRUE), ".")
  )

  .uml_export_xlsx(
    out_path,
    params$table_title %||% "Univariable and Multivariable Logistic Regression Analysis",
    combined_mat,
    uni_detail,
    multi_detail,
    fn
  )
  message("已写出: ", out_path)
  invisible(list(
    path = out_path,
    combined = combined_mat,
    uni = uni_df,
    multi = multi_df,
    multi_vars = multi_vars,
    data = data
  ))
}

# ═══════════════════════════════════════════════════════════════════════════
#  入口
# ═══════════════════════════════════════════════════════════════════════════

if (isTRUE(.RUN_ON_SOURCE)) {
  .uml_result <- run_uni_multi_logistic_threeline(params)
}
