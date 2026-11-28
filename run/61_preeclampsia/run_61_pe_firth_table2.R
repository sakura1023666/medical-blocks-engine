#!/usr/bin/env Rscript
# 稀有事件结局：Firth Logistic Table2（不覆盖原 GLM 表，文件名加 _Firth）
# 结局：Preterm34, Apgar1_lt8, Apgar5_lt8, Newborn_lt1500, Newborn_lt2000
#
# Rscript run/61_preeclampsia/run_61_pe_firth_table2.R

`%||%` <- function(a, b) if (!is.null(a)) a else b

.root <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    sp <- normalizePath(dirname(sub("^--file=", "", f[1L])), winslash = "/")
    if (basename(sp) == "61_preeclampsia" && basename(dirname(sp)) == "run") {
      return(normalizePath(file.path(sp, "..", ".."), winslash = "/"))
    }
  }
  normalizePath(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd()), winslash = "/")
}
.root_dir <- .root()
setwd(.root_dir)
source(file.path(.root_dir, "R/utils.R"))
source("/mnt/g/02block_result/61_Preeclampsia/configs/config_61_preeclampsia_batch.R")
suppressPackageStartupMessages({
  library(openxlsx)
  if (!requireNamespace("logistf", quietly = TRUE)) stop("需要 logistf", call. = FALSE)
})

out_base <- config$project$output_dir
ck_shared <- pipeline_shared$checkpoint$dir
ck <- file.path(ck_shared, "multicollinearity_screen.rds")
if (!file.exists(ck)) ck <- file.path(ck_shared, "step08_multicollinearity_screen.rds")
obj <- readRDS(ck)
ctx <- if (!is.null(obj$ctx)) obj$ctx else obj
imp0 <- as.data.frame(ctx$data$imputed %||% ctx$data$cleaned)
m1 <- as.character(ctx$results$Model1Factors %||% "Age")
m2 <- as.character(ctx$results$Model2Factors %||% character(0))
if (!length(m2)) stop("Model2Factors 为空", call. = FALSE)
cli::cli_alert_info("Model2: {paste(m2, collapse = ', ')}")

# 回补新生儿结局
id <- as.character(config$data$id_column %||% "Admission_Num")[1L]
env <- new.env(parent = emptyenv())
load(config$data$rawdata_path, envir = env)
raw <- as.data.frame(env[[config$data$rawdata_obj]])
nw <- suppressWarnings(as.numeric(sub("/.*$", "", trimws(as.character(raw$Newborn_Weight)))))
nw[is.finite(nw) & nw <= 0] <- NA_real_
raw$Newborn_Weight_g <- nw
raw$Newborn_lt1500 <- as.integer(is.finite(nw) & nw < 1500)
raw$Newborn_lt2000 <- as.integer(is.finite(nw) & nw < 2000)
raw$APGAR_1min <- suppressWarnings(as.numeric(as.character(raw$APGAR_1min)))
raw$APGAR_5min <- suppressWarnings(as.numeric(as.character(raw$APGAR_5min)))
raw$Apgar1_lt8 <- as.integer(is.finite(raw$APGAR_1min) & raw$APGAR_1min < 8)
raw$Apgar5_lt8 <- as.integer(is.finite(raw$APGAR_5min) & raw$APGAR_5min < 8)
keep <- intersect(
  c(id, "Newborn_lt1500", "Newborn_lt2000", "Apgar1_lt8", "Apgar5_lt8"),
  names(raw)
)
map <- raw[, keep, drop = FALSE]
map[[id]] <- as.character(map[[id]])
imp0[[id]] <- as.character(imp0[[id]])
for (cn in setdiff(keep, id)) imp0[[cn]] <- NULL
imp0 <- merge(imp0, map, by = id, all.x = TRUE, sort = FALSE)

# 若有 mice，用 m 套完整数据做 Rubin 合并；否则单表
.get_imp_list <- function(ctx, imp0, id_col = "Admission_Num") {
  # mice 对象只有 A 类协变量、无 ID；按行序把各套插补协变量写回完整分析框
  mm <- ctx$results$mice_model
  if (!is.null(mm) && inherits(mm, "mids") && nrow(mm$data) == nrow(imp0)) {
    m <- as.integer(mm$m)
    out <- vector("list", m)
    for (i in seq_len(m)) {
      comp <- as.data.frame(mice::complete(mm, i))
      di <- imp0
      for (cn in names(comp)) {
        if (cn %in% names(di) && nrow(comp) == nrow(di)) di[[cn]] <- comp[[cn]]
      }
      out[[i]] <- di
    }
    return(out)
  }
  list(imp0)
}

imp_list <- .get_imp_list(ctx, imp0, id_col = id)
cli::cli_alert_info("Firth 使用 {length(imp_list)} 套插补数据")

.y01 <- function(d, oc) {
  y <- d[[oc]]
  if (identical(oc, "Preterm34")) {
    return(as.integer(as.character(y) == "Preterm34"))
  }
  as.integer(as.numeric(y) == 1)
}

.prep_disease <- function(d) {
  dis <- factor(
    as.character(d$Disease),
    levels = c(
      "Non-preeclampsia",
      "Preeclampsia",
      "Chronic hypertension with preeclampsia"
    )
  )
  dis
}

.fit_firth_one <- function(d, oc, covs) {
  y <- .y01(d, oc)
  dis <- .prep_disease(d)
  df <- data.frame(y = y, Disease = dis, stringsAsFactors = FALSE)
  for (cv in covs) {
    if (!cv %in% names(d)) next
    df[[cv]] <- d[[cv]]
  }
  df <- df[stats::complete.cases(df), , drop = FALSE]
  if (nrow(df) < 30L || length(unique(df$y)) < 2L) {
    return(NULL)
  }
  # 保证因子水平
  df$Disease <- factor(df$Disease, levels = levels(dis))
  rhs <- if (length(covs)) {
    paste(c("Disease", intersect(covs, names(df))), collapse = " + ")
  } else {
    "Disease"
  }
  fml <- stats::as.formula(paste("y ~", rhs))
  fit <- tryCatch(logistf::logistf(fml, data = df, pl = TRUE), error = function(e) e)
  if (inherits(fit, "error")) return(NULL)
  list(fit = fit, n = nrow(df), events = sum(df$y == 1L), data = df)
}

.extract_disease_or <- function(fit_obj) {
  # DiseasePreeclampsia / DiseaseChronic...
  rn <- names(fit_obj$fit$coefficients)
  want <- c(
    "DiseasePreeclampsia",
    "DiseaseChronic hypertension with preeclampsia"
  )
  # also try with backticks stripped patterns
  out <- list()
  for (w in want) {
    hit <- which(rn == w)
    if (!length(hit)) {
      hit <- grep(paste0("^", gsub("([\\(\\)])", "\\\\\\1", w), "$"), rn)
    }
    if (!length(hit)) {
      # fuzzy
      if (grepl("Preeclampsia", w) && !grepl("Chronic", w)) {
        hit <- which(grepl("Disease.*Preeclampsia$", rn) & !grepl("Chronic", rn))
      } else {
        hit <- which(grepl("Chronic", rn) & grepl("Preeclampsia", rn))
      }
    }
    if (!length(hit)) {
      out[[w]] <- list(or = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_)
      next
    }
    i <- hit[[1L]]
    out[[w]] <- list(
      or = unname(exp(fit_obj$fit$coefficients[[i]])),
      lo = unname(exp(fit_obj$fit$ci.lower[[i]])),
      hi = unname(exp(fit_obj$fit$ci.upper[[i]])),
      p = unname(fit_obj$fit$prob[[i]])
    )
  }
  out
}

.pool_firth <- function(fits) {
  # Rubin pool on logOR / SE approx from CI width if available; else average coef + var
  # logistf has var object sometimes
  if (!length(fits)) return(NULL)
  if (length(fits) == 1L) return(.extract_disease_or(fits[[1]]))

  # collect coef names intersection for Disease terms
  get_coef <- function(fo, term_regex) {
    rn <- names(fo$fit$coefficients)
    hit <- grep(term_regex, rn)
    if (!length(hit)) return(NULL)
    i <- hit[[1L]]
    b <- unname(fo$fit$coefficients[[i]])
    # SE from var diagonal if present
    se <- NA_real_
    v <- tryCatch(fo$fit$var, error = function(e) NULL)
    if (!is.null(v)) {
      if (is.matrix(v) && nrow(v) >= i && ncol(v) >= i) {
        se <- sqrt(max(v[i, i], 0))
      } else if (length(v) >= i) {
        se <- sqrt(max(as.numeric(v)[[i]], 0))
      }
    }
    if (!is.finite(se) || se <= 0) {
      # approx from profile CI
      lo <- unname(fo$fit$ci.lower[[i]])
      hi <- unname(fo$fit$ci.upper[[i]])
      if (is.finite(lo) && is.finite(hi) && hi > lo) se <- (hi - lo) / (2 * 1.96)
    }
    c(b = b, se = se)
  }

  terms <- list(
    pe = "Disease.*Preeclampsia$|^DiseasePreeclampsia$",
    ch = "Chronic"
  )
  # refine pe to exclude Chronic
  out <- list()
  # 水平名含小写 preeclampsia；匹配忽略大小写
  for (nm in c("DiseasePreeclampsia", "DiseaseChronic hypertension with preeclampsia")) {
    mats <- list()
    for (fo in fits) {
      rn <- names(fo$fit$coefficients)
      if (identical(nm, "DiseasePreeclampsia")) {
        hit <- which(
          grepl("preeclampsia", rn, ignore.case = TRUE) &
            !grepl("chronic", rn, ignore.case = TRUE) &
            grepl("^Disease", rn)
        )
      } else {
        hit <- which(
          grepl("chronic", rn, ignore.case = TRUE) &
            grepl("preeclampsia", rn, ignore.case = TRUE)
        )
      }
      if (!length(hit)) next
      i <- hit[[1L]]
      b <- unname(fo$fit$coefficients[[i]])
      se <- NA_real_
      v <- fo$fit$var
      if (!is.null(v) && is.matrix(v) && nrow(v) >= i) se <- sqrt(max(v[i, i], 0))
      if (!is.finite(se) || se <= 0) {
        lo <- unname(fo$fit$ci.lower[[i]])
        hi <- unname(fo$fit$ci.upper[[i]])
        if (is.finite(lo) && is.finite(hi) && hi > lo) se <- (hi - lo) / (2 * 1.96)
      }
      # 优先用 profile CI 直接合并（每套取 logCI），下面仍用 Wald 合并
      if (!is.finite(b) || !is.finite(se) || se <= 0) next
      mats[[length(mats) + 1L]] <- c(b = b, se = se)
    }
    if (!length(mats)) {
      out[[nm]] <- list(or = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_)
      next
    }
    B <- vapply(mats, function(z) z[["b"]], numeric(1))
    SE <- vapply(mats, function(z) z[["se"]], numeric(1))
    m <- length(B)
    qbar <- mean(B)
    ubar <- mean(SE^2)
    bvar <- if (m > 1L) stats::var(B) else 0
    if (!is.finite(bvar)) bvar <- 0
    Tvar <- ubar + (1 + 1 / m) * bvar
    se_p <- sqrt(max(Tvar, 0))
    z <- if (se_p > 0) qbar / se_p else NA_real_
    p <- if (is.finite(z)) 2 * stats::pnorm(-abs(z)) else NA_real_
    out[[nm]] <- list(
      or = exp(qbar),
      lo = exp(qbar - 1.96 * se_p),
      hi = exp(qbar + 1.96 * se_p),
      p = p
    )
  }
  out
}

.fmt_or <- function(x) {
  if (!is.finite(x)) return("NA")
  sprintf("%.3f", x)
}
.fmt_ci <- function(lo, hi) {
  if (!is.finite(lo) || !is.finite(hi)) return("NA")
  sprintf("(%.3f,%.3f)", lo, hi)
}
.fmt_p <- function(p) {
  if (!is.finite(p)) return("NA")
  if (p < 0.001) return("<0.001")
  sprintf("%.3f", p)
}

.event_str <- function(df, level) {
  sub <- df[as.character(df$Disease) == level, , drop = FALSE]
  ev <- sum(sub$y == 1L, na.rm = TRUE)
  n <- nrow(sub)
  sprintf("%d/%d (%.3f%%)", ev, n, if (n > 0) 100 * ev / n else NA_real_)
}

.find_tables_dir <- function(oc) {
  base <- file.path(out_base, "by_outcome", oc)
  cands <- list.files(base, pattern = "step[0-9]+_logistic_binary_glm$", full.names = TRUE)
  if (!length(cands)) {
    d <- file.path(base, "step99_logistic_binary_glm_Firth", "Tables")
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
    return(d)
  }
  step_n <- suppressWarnings(as.integer(sub(".*step([0-9]+)_.*", "\\1", basename(cands))))
  best <- cands[order(ifelse(is.na(step_n), -1L, step_n), decreasing = TRUE)][1]
  d <- file.path(best, "Tables")
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  d
}

outcomes <- list(
  Preterm34 = list(label = "Preterm delivery", col = "Preterm34"),
  Apgar1_lt8 = list(label = "Apgar 1 min < 8", col = "Apgar1_lt8"),
  Apgar5_lt8 = list(label = "Apgar 5 min < 8", col = "Apgar5_lt8"),
  Newborn_lt1500 = list(label = "Newborn weight < 1500 g", col = "Newborn_lt1500"),
  Newborn_lt2000 = list(label = "Newborn weight < 2000 g", col = "Newborn_lt2000")
)

levels_dis <- c(
  "Non-preeclampsia",
  "Preeclampsia",
  "Chronic hypertension with preeclampsia"
)

for (ou in names(outcomes)) {
  spec <- outcomes[[ou]]
  oc <- spec$col
  cli::cli_h1("Firth Table2: {oc}")

  models <- list(
    Crude = character(0),
    Model1 = intersect(m1, names(imp0)),
    Model2 = intersect(m2, names(imp0))
  )

  res_by_model <- list()
  n_events_ref <- NULL
  for (mn in names(models)) {
    covs <- models[[mn]]
    fits <- list()
    for (di in imp_list) {
      if (!oc %in% names(di)) next
      fo <- .fit_firth_one(di, oc, covs)
      if (!is.null(fo)) fits[[length(fits) + 1L]] <- fo
    }
    if (!length(fits)) {
      cli::cli_alert_warning("{oc} {mn}: 拟合失败")
      res_by_model[[mn]] <- NULL
      next
    }
    pooled <- .pool_firth(fits)
    res_by_model[[mn]] <- list(pooled = pooled, example = fits[[1]])
    if (is.null(n_events_ref)) n_events_ref <- fits[[1]]$data
    cli::cli_alert_success("{oc} {mn}: OK (m_fit={length(fits)})")
  }

  # Build Table 2 body + SCI 双行表头三线表（与 logistic_binary_glm / export_sci_table 同口径）
  title <- paste0("Table 2-Own. Logistic regression of Disease ", spec$label, " (Firth)")
  pe_key <- "DiseasePreeclampsia"
  ch_key <- "DiseaseChronic hypertension with preeclampsia"

  get_cell <- function(mn, key, what) {
    r <- res_by_model[[mn]]
    if (is.null(r) || is.null(r$pooled) || is.null(r$pooled[[key]])) return(NA_real_)
    r$pooled[[key]][[what]]
  }

  df0 <- n_events_ref
  if (is.null(df0)) {
    cli::cli_alert_danger("{oc}: 无可用分析框，跳过写表")
    next
  }

  ev_ref <- .event_str(df0, levels_dis[[1]])
  ev_pe <- .event_str(df0, levels_dis[[2]])
  ev_ch <- .event_str(df0, levels_dis[[3]])

  # 与 04block_logistic_binary_glm Line1/Line2 一致
  h1 <- c("", "", "", "", "Crude Model", "", "", "Model1", "", "", "Model2", "")
  h2 <- c(
    "Characteristic", "Exposure cutoff", "Events / N (%)",
    "OR", "95%CI", "P-value",
    "OR", "95%CI", "P-value",
    "OR", "95%CI", "P-value"
  )

  .or_ci_p <- function(mn, key) {
    c(
      .fmt_or(get_cell(mn, key, "or")),
      .fmt_ci(get_cell(mn, key, "lo"), get_cell(mn, key, "hi")),
      .fmt_p(get_cell(mn, key, "p"))
    )
  }

  body <- rbind(
    c("Disease groups", rep("", 11)),
    c(
      "Non-preeclampsia (Ref)", "", ev_ref,
      "Ref", "Ref", "", "Ref", "Ref", "", "Ref", "Ref", ""
    ),
    c(
      "Preeclampsia", "", ev_pe,
      .or_ci_p("Crude", pe_key),
      .or_ci_p("Model1", pe_key),
      .or_ci_p("Model2", pe_key)
    ),
    c(
      "Chronic hypertension with preeclampsia", "", ev_ch,
      .or_ci_p("Crude", ch_key),
      .or_ci_p("Model1", ch_key),
      .or_ci_p("Model2", ch_key)
    ),
    c("p for trend", rep("", 11))
  )
  body <- as.data.frame(body, stringsAsFactors = FALSE)
  colnames(body) <- paste0("V", seq_len(ncol(body)))
  rownames(body) <- NULL

  footnotes <- c(
    "The Crude Model was non-adjusted.",
    paste0("The Model 1 was adjusted by: ", paste(gsub("_", " ", m1), collapse = ", "), "."),
    paste0("The Model 2 was adjusted by: ", paste(gsub("_", " ", m2), collapse = ", "), "."),
    paste0(
      "Firth's penalized logistic regression (logistf). ",
      "Estimates pooled across m=", length(imp_list),
      " imputations using Rubin's rules on the log-OR scale (Wald CI)."
    ),
    "Filename suffix _Firth: does not overwrite the original GLM Table 2."
  )

  tab_dir <- .find_tables_dir(oc)
  fname <- paste0(
    "Table 2-Own. Logistic regression of Disease ", spec$label, "_Firth.xlsx"
  )
  fpath <- file.path(tab_dir, fname)

  if (!exists(".sci_xlsx_double_header_booktabs", mode = "function")) {
    stop("缺少 .sci_xlsx_double_header_booktabs；请确认已 source R/utils.R", call. = FALSE)
  }
  .sci_xlsx_double_header_booktabs(
    filepath = fpath,
    title = title,
    df_body = body,
    h1 = h1,
    h2 = h2,
    sheet = "Table",
    footnotes = footnotes
  )

  # 附 csv（扁平：表头两行 + 表体），便于核对
  flat <- rbind(h1, h2, as.matrix(body))
  utils::write.csv(
    as.data.frame(flat, stringsAsFactors = FALSE),
    sub("\\.xlsx$", ".csv", fpath),
    row.names = FALSE
  )
  cli::cli_alert_success("写入 SCI 三线表: {fpath}")
}

cli::cli_alert_success("Firth Table2 全部完成（未覆盖原 GLM 表）")
