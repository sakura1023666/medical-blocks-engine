# Review package Task 3
## 00osteo_dxa_qct_common.R
###############################################################################
# 00osteo_dxa_qct_common.R — Blocks/75 骨质疏松 DXA/QCT 公共 helper
###############################################################################

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
}

#' 从 data 中按候选顺序选取第一个存在的列名
.osteo75_pick_col <- function(data, candidates) {
  if (!is.data.frame(data)) stop("data must be a data.frame", call. = FALSE)
  hit <- intersect(as.character(candidates), names(data))
  if (!length(hit)) {
    stop(
      "No column found among candidates: ",
      paste(candidates, collapse = ", "),
      call. = FALSE
    )
  }
  hit[1L]
}

#' Cohen's kappa（二分类；混淆矩阵公式，不依赖 irr）
.osteo75_cohen_kappa <- function(x, y) {
  x <- as.integer(x)
  y <- as.integer(y)
  ok <- is.finite(x) & is.finite(y)
  x <- x[ok]
  y <- y[ok]
  n <- length(x)
  if (n == 0L) {
    return(list(kappa = NA_real_, n = 0L))
  }
  x01 <- ifelse(x != 0L, 1L, 0L)
  y01 <- ifelse(y != 0L, 1L, 0L)
  tab <- table(factor(x01, levels = c(0L, 1L)), factor(y01, levels = c(0L, 1L)))
  po <- sum(diag(tab)) / n
  px1 <- sum(tab[, 2L]) / n
  px0 <- sum(tab[, 1L]) / n
  py1 <- sum(tab[2L, ]) / n
  py0 <- sum(tab[1L, ]) / n
  pe <- px1 * py1 + px0 * py0
  kappa <- if (abs(1 - pe) < 1e-12) {
    if (abs(po - pe) < 1e-12) 1 else 0
  } else {
    (po - pe) / (1 - pe)
  }
  list(kappa = as.numeric(kappa), n = as.integer(n))
}

#' 临床分层向量：Nathan / AAC / BMI / Age（名称为短标签，值为 factor 或数值）
.osteo75_make_strata <- function(data, cfg) {
  if (!is.data.frame(data)) stop("data must be a data.frame", call. = FALSE)
  cfg <- cfg %||% list()

  nathan_col <- as.character(cfg$nathan_col %||% "Nathan_bin")[1L]
  aac_col <- as.character(cfg$aac_col %||% "AAC")[1L]
  bmi_col <- as.character(cfg$bmi_col %||% "BMI_bin")[1L]
  age_col <- as.character(cfg$age_col %||% "Age_bin")[1L]

  nathan_vec <- if (nathan_col %in% names(data)) {
    data[[nathan_col]]
  } else if ("Nathan" %in% names(data)) {
    n <- as.integer(data$Nathan)
    factor(ifelse(n %in% c(3L, 4L), "3-4", "1-2"), levels = c("1-2", "3-4"))
  } else {
    stop("Cannot resolve Nathan stratum column", call. = FALSE)
  }

  aac_vec <- if (aac_col %in% names(data)) {
    data[[aac_col]]
  } else if ("AAC" %in% names(data)) {
    as.integer(data$AAC)
  } else {
    stop("Cannot resolve AAC stratum column", call. = FALSE)
  }

  bmi_vec <- if (bmi_col %in% names(data)) {
    data[[bmi_col]]
  } else if ("BMI" %in% names(data)) {
    b <- suppressWarnings(as.numeric(data$BMI))
    factor(ifelse(b >= 24, ">=24", "<24"), levels = c("<24", ">=24"))
  } else {
    stop("Cannot resolve BMI stratum column", call. = FALSE)
  }

  age_vec <- if (age_col %in% names(data)) {
    data[[age_col]]
  } else if ("Age" %in% names(data)) {
    a <- suppressWarnings(as.numeric(data$Age))
    factor(ifelse(a >= 65, ">=65", "<65"), levels = c("<65", ">=65"))
  } else {
    stop("Cannot resolve Age stratum column", call. = FALSE)
  }

  list(
    Nathan = nathan_vec,
    AAC = aac_vec,
    BMI = bmi_vec,
    Age = age_vec
  )
}

#' 二分类金标准 vs 预测的 Sens/Spec/PPV/NPV
.osteo75_diag_metrics <- function(truth01, pred01) {
  t <- as.integer(truth01)
  p <- as.integer(pred01)
  ok <- is.finite(t) & is.finite(p)
  t <- ifelse(t[ok] != 0L, 1L, 0L)
  p <- ifelse(p[ok] != 0L, 1L, 0L)
  n <- length(t)
  n_pos <- sum(t == 1L)
  tp <- sum(t == 1L & p == 1L)
  tn <- sum(t == 0L & p == 0L)
  fp <- sum(t == 0L & p == 1L)
  fn <- sum(t == 1L & p == 0L)
  sens <- if ((tp + fn) > 0L) tp / (tp + fn) else NA_real_
  spec <- if ((tn + fp) > 0L) tn / (tn + fp) else NA_real_
  ppv <- if ((tp + fp) > 0L) tp / (tp + fp) else NA_real_
  npv <- if ((tn + fn) > 0L) tn / (tn + fn) else NA_real_
  data.frame(
    sens = sens,
    spec = spec,
    ppv = ppv,
    npv = npv,
    n = as.integer(n),
    n_pos = as.integer(n_pos),
    stringsAsFactors = FALSE
  )
}

#' 连续分数 ROC-AUC（默认 direction="<"，骨密度/T 越低越病）
.osteo75_auc_continuous <- function(truth01, score, direction = "<") {
  if (!requireNamespace("pROC", quietly = TRUE)) {
    stop("Package 'pROC' is required for .osteo75_auc_continuous", call. = FALSE)
  }
  y <- as.integer(truth01)
  s <- suppressWarnings(as.numeric(score))
  ok <- is.finite(y) & is.finite(s)
  y <- ifelse(y[ok] != 0L, 1L, 0L)
  s <- s[ok]
  if (length(y) < 2L || length(unique(y)) < 2L) {
    return(list(auc = NA_real_, ci_lo = NA_real_, ci_hi = NA_real_))
  }
  roc <- suppressWarnings(
    pROC::roc(y, s, quiet = TRUE, direction = direction)
  )
  auc <- as.numeric(pROC::auc(roc))
  ci <- tryCatch(
    as.numeric(pROC::ci.auc(roc)),
    error = function(e) c(NA_real_, NA_real_, NA_real_)
  )
  list(
    auc = auc,
    ci_lo = ci[1L],
    ci_hi = ci[3L]
  )
}

## tests/test_osteo_dxa_qct_blocks.R
#!/usr/bin/env Rscript
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(root)) root <- normalizePath(".", winslash = "/")
if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
}

common_path <- file.path(root, "Blocks/75_osteo_dxa_qct/00osteo_dxa_qct_common.R")
stopifnot(file.exists(common_path))
source(common_path, local = FALSE)

# Cohen kappa (known 2x2)
x <- c(1, 1, 1, 0, 0, 0)
y <- c(1, 1, 0, 0, 0, 1)
k <- .osteo75_cohen_kappa(x, y)
stopifnot(is.finite(k$kappa), k$n == 6L)

# Diagnostic metrics
m <- .osteo75_diag_metrics(c(1, 1, 1, 0, 0), c(1, 1, 0, 0, 0))
stopifnot(abs(m$sens - 2 / 3) < 1e-8, abs(m$spec - 1) < 1e-8)

# pick_col
df <- data.frame(QCT_vBMD = 1:3, DXA_T_min = 4:6)
stopifnot(identical(.osteo75_pick_col(df, c("missing", "QCT_vBMD")), "QCT_vBMD"))

# make_strata
mini <- data.frame(
  Nathan = c(1L, 2L, 3L, 4L),
  AAC = c(0L, 1L, 0L, 1L),
  BMI = c(22, 25, 30, 23),
  Age = c(60, 70, 55, 66),
  stringsAsFactors = FALSE
)
st <- .osteo75_make_strata(mini, list())
stopifnot(all(c("Nathan", "AAC", "BMI", "Age") %in% names(st)))
stopifnot(length(st$Nathan) == 4L)

if (requireNamespace("pROC", quietly = TRUE)) {
  set.seed(42)
  truth <- c(rep(1L, 10), rep(0L, 10))
  score_good <- c(rnorm(10, 2), rnorm(10, 0))
  auc <- .osteo75_auc_continuous(truth, score_good)
  stopifnot(is.finite(auc$auc), auc$auc > 0.5)
} else {
  message("note: pROC not installed; AUC helper not exercised in test")
}

cat("helper OK\n")
