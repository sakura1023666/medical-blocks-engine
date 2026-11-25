#!/usr/bin/env Rscript
# 审 Fig2（前后段 log-rank）+ Fig5/6 PAMM s(expo)
# 门控：MIMIC Fig2 左&右均 P<α；MIMIC+eICU s(expo) 均 P<α → 否则 【success】→【failed】
#
#   Rscript run/trajectory_prognosis/audit_fcimb_fig2_pamm_gate.R
#   Rscript run/trajectory_prognosis/audit_fcimb_fig2_pamm_gate.R --dry-run
#   Rscript run/trajectory_prognosis/audit_fcimb_fig2_pamm_gate.R --alpha 0.05

suppressPackageStartupMessages({
  options(warn = 1)
  library(survival)
  library(mgcv)
})

.args <- commandArgs(trailingOnly = TRUE)
.get <- function(flag, default = NULL) {
  i <- match(flag, .args)
  if (is.na(i) || i >= length(.args)) return(default)
  .args[[i + 1L]]
}
.has <- function(flag) !is.na(match(flag, .args))

.root <- {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    d <- dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
    if (basename(d) == "trajectory_prognosis")
      normalizePath(file.path(d, "..", ".."), winslash = "/")
    else normalizePath(getwd(), winslash = "/")
  } else normalizePath(getwd(), winslash = "/")
}
setwd(.root)

proj <- .get("--proj", "G:/02block_result/55_COPD/Prognosis_Trajectory_v2_42558177")
alpha <- as.numeric(.get("--alpha", "0.05"))
dry <- .has("--dry-run")
max_fu <- 28

`%||%` <- function(a, b) if (!is.null(a)) a else b

.to_event01 <- function(x) {
  if (is.numeric(x)) return(as.integer(x > 0))
  xs <- trimws(as.character(x))
  out <- rep(NA_integer_, length(xs))
  out[xs %in% c("1", "Yes", "YES", "true", "TRUE", "Non-survivor", "Dead", "Death")] <- 1L
  out[xs %in% c("0", "No", "NO", "false", "FALSE", "Survivor", "Alive")] <- 0L
  miss <- is.na(out)
  if (any(miss)) out[miss] <- suppressWarnings(as.integer(xs[miss]))
  out
}

.logrank_p <- function(df, time_col, event_col) {
  if (nrow(df) < 2L || length(unique(df$class)) < 2L) return(NA_real_)
  fml <- stats::as.formula(paste0("Surv(", time_col, ", ", event_col, ") ~ class"))
  sd <- tryCatch(survdiff(fml, data = df), error = function(e) NULL)
  if (is.null(sd)) return(NA_real_)
  stats::pchisq(sd$chisq, df = length(sd$n) - 1L, lower.tail = FALSE)
}

.seg_ps <- function(df, L) {
  d1 <- df
  d1$t1 <- pmin(d1$time, L)
  d1$e1 <- as.integer(d1$event == 1L & d1$time <= L)
  p_left <- .logrank_p(d1, "t1", "e1")
  d2 <- df[df$time > L, , drop = FALSE]
  p_right <- .logrank_p(d2, "time", "event")
  list(p_left = p_left, p_right = p_right, n_class = length(unique(df$class)), n = nrow(df))
}

.load_km <- function(ix, db) {
  ck <- file.path(proj, "checkpoints/by_index", ix, db)
  p <- file.path(ck, "trajectory_km_class.rds")
  if (!file.exists(p)) p <- file.path(ck, "trajectory_jlcm.rds")
  if (!file.exists(p) && identical(db, "eicu"))
    p <- file.path(ck, "trajectory_lcmm_external_validate.rds")
  if (!file.exists(p)) return(NULL)
  x <- tryCatch(readRDS(p), error = function(e) NULL)
  if (is.null(x)) return(NULL)
  ctx <- x$ctx %||% x
  d <- ctx$data$imputed %||% ctx$data$cleaned
  if (!is.data.frame(d)) return(NULL)
  cls <- if (paste0("trajectory_class_", ix) %in% names(d))
    d[[paste0("trajectory_class_", ix)]] else d$trajectory_class
  ix_root <- file.path(proj, paste0("by_index/\u3010success\u3011", ix))
  asg <- file.path(
    ix_root, "eicu/step14_trajectory_lcmm_external_validate/Tables/LCMM",
    paste0("Table_LCMM_Assignment_External_", ix, ".csv")
  )
  if (identical(db, "eicu") && file.exists(asg) && "subject_id" %in% names(d)) {
    a <- utils::read.csv(asg, stringsAsFactors = FALSE)
    if (all(c("subject_id", "trajectory_class") %in% names(a))) {
      d$subject_id <- as.character(d$subject_id)
      a$subject_id <- as.character(a$subject_id)
      drop <- intersect(c("trajectory_class", paste0("trajectory_class_", ix)), names(d))
      if (length(drop)) d <- d[, setdiff(names(d), drop), drop = FALSE]
      d <- merge(d, a[, c("subject_id", "trajectory_class")], by = "subject_id", all.x = TRUE)
      cls <- d$trajectory_class
    }
  }
  raw_t <- suppressWarnings(as.numeric(as.character(d$survival_time_28d)))
  ev <- .to_event01(d$survival_28d)
  class_num <- suppressWarnings(as.integer(gsub("\\D+", "", as.character(cls))))
  out <- data.frame(
    class = factor(class_num),
    time = ifelse(ev == 0L, max_fu, pmin(raw_t, max_fu)),
    event = ev,
    stringsAsFactors = FALSE
  )
  out <- out[is.finite(as.numeric(as.character(out$class))) &
               is.finite(out$time) & out$time > 0 & !is.na(out$event), , drop = FALSE]
  out
}

.resolve_cut <- function(ix) {
  pc <- file.path(proj, "checkpoints/by_index", ix, "mimic/trajectory_piecewise_cox.rds")
  if (!file.exists(pc)) return(5L)
  cuts <- tryCatch(
    readRDS(pc)$ctx$results$trajectory_piecewise_cox$cuts[[ix]],
    error = function(e) NULL
  )
  ng <- suppressWarnings(as.integer(cuts)[1L])
  if (is.finite(ng) && ng >= 2L) as.integer(ng) else 5L
}

.sexp_p <- function(ix, db) {
  f <- file.path(
    proj, paste0("by_index/\u3010success\u3011", ix), db,
    "step25_trajectory_pamm/Tables/PAMM", paste0("PAMM_gam_", ix, ".rds")
  )
  if (!file.exists(f)) {
    alt <- list.files(
      file.path(proj, paste0("by_index/\u3010success\u3011", ix), db),
      pattern = paste0("PAMM_gam_", ix, "\\.rds$"), recursive = TRUE, full.names = TRUE
    )
    f <- alt[1]
  }
  if (is.null(f) || !nzchar(f) || !file.exists(f)) return(NA_real_)
  obj <- tryCatch(readRDS(f), error = function(e) NULL)
  if (is.null(obj)) return(NA_real_)
  fit <- if (inherits(obj, "gam")) obj else obj$gam %||% obj$fit
  if (is.null(fit) || !inherits(fit, "gam")) return(NA_real_)
  st <- tryCatch(summary(fit)$s.table, error = function(e) NULL)
  if (is.null(st) || !nrow(st)) return(NA_real_)
  rn <- rownames(st)
  hit <- grep("^s\\(expo\\)$", rn)
  if (!length(hit)) hit <- grep("expo", rn)
  if (!length(hit)) return(NA_real_)
  as.numeric(st[hit[1], "p-value"])
}

.sig <- function(p, a = alpha) is.finite(p) && p < a

success_dirs <- list.dirs(file.path(proj, "by_index"), recursive = FALSE, full.names = TRUE)
success_dirs <- success_dirs[grepl("\u3010success\u3011", basename(success_dirs))]
indices <- sort(sub("^\u3010success\u3011", "", basename(success_dirs)))

rows <- list()
for (ix in indices) {
  L <- .resolve_cut(ix)
  km_m <- .load_km(ix, "mimic")
  km_e <- .load_km(ix, "eicu")
  ps_m <- if (!is.null(km_m)) .seg_ps(km_m, L) else list(p_left = NA, p_right = NA, n_class = NA, n = NA)
  ps_e <- if (!is.null(km_e)) .seg_ps(km_e, L) else list(p_left = NA, p_right = NA, n_class = NA, n = NA)
  p_sexp_m <- .sexp_p(ix, "mimic")
  p_sexp_e <- .sexp_p(ix, "eicu")

  fig2_ok <- .sig(ps_m$p_left) && .sig(ps_m$p_right)
  # Fig5/6：发现 + 外验 s(expo) 都要显著
  pamm_ok <- .sig(p_sexp_m) && .sig(p_sexp_e)
  pass <- isTRUE(fig2_ok) && isTRUE(pamm_ok)

  reason <- character(0)
  if (!isTRUE(fig2_ok)) {
    reason <- c(reason, sprintf(
      "Fig2 MIMIC 前后未双显著 (L=%.4g / R=%.4g, cut=%s)",
      ps_m$p_left, ps_m$p_right, L
    ))
  }
  if (!isTRUE(pamm_ok)) {
    reason <- c(reason, sprintf(
      "PAMM s(expo) 未双库显著 (MIMIC=%.4g / eICU=%.4g)",
      p_sexp_m, p_sexp_e
    ))
  }

  rows[[length(rows) + 1L]] <- data.frame(
    index = ix,
    cut = L,
    mimic_n = ps_m$n %||% NA,
    mimic_nclass = ps_m$n_class %||% NA,
    fig2_p_left = ps_m$p_left,
    fig2_p_right = ps_m$p_right,
    fig2_ok = fig2_ok,
    eicu_fig2_p_left = ps_e$p_left,
    eicu_fig2_p_right = ps_e$p_right,
    eicu_nclass = ps_e$n_class %||% NA,
    pamm_sexp_mimic = p_sexp_m,
    pamm_sexp_eicu = p_sexp_e,
    pamm_ok = pamm_ok,
    pass = pass,
    fail_reason = if (length(reason)) paste(reason, collapse = "; ") else "",
    stringsAsFactors = FALSE
  )
}

tab <- do.call(rbind, rows)
out_dir <- file.path(proj, "reports/fcimb_rebuild_batch")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
csv <- file.path(out_dir, "audit_fig2_pamm_gate.csv")
utils::write.csv(tab, csv, row.names = FALSE)

cli::cli_h1("Fig2 + PAMM s(expo) 门控（α={alpha}）")
print(tab[, c("index", "cut", "fig2_p_left", "fig2_p_right", "fig2_ok",
              "pamm_sexp_mimic", "pamm_sexp_eicu", "pamm_ok", "pass")])

pass_ix <- tab$index[tab$pass]
fail_ix <- tab$index[!tab$pass]
cli::cli_alert_success("通过 {length(pass_ix)}/{nrow(tab)}: {paste(pass_ix, collapse=', ')}")
cli::cli_alert_warning("失败 {length(fail_ix)}/{nrow(tab)}: {paste(fail_ix, collapse=', ')}")

renamed <- character(0)
if (!dry && length(fail_ix)) {
  for (ix in fail_ix) {
    src <- file.path(proj, "by_index", paste0("\u3010success\u3011", ix))
    dest <- file.path(proj, "by_index", paste0("\u3010failed\u3011", ix))
    if (!dir.exists(src)) next
    if (dir.exists(dest)) {
      stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
      dest <- paste0(dest, "_gate_", stamp)
    }
    ok <- tryCatch({
      file.rename(src, dest)
      TRUE
    }, error = function(e) {
      cli::cli_alert_danger("{ix}: rename 失败 {conditionMessage(e)}")
      FALSE
    })
    if (isTRUE(ok)) {
      renamed <- c(renamed, ix)
      cli::cli_alert_info("【success】{ix} → {basename(dest)}")
    }
  }
} else if (dry) {
  cli::cli_alert_info("dry-run：未改目录名")
}

manifest <- c(
  "# fcimb Fig2 + PAMM s(expo) 门控",
  "",
  paste0("- α = ", alpha),
  "- Fig2：MIMIC landmark 左段(0–cut) 与右段(cut–28) log-rank **均** P<α",
  "- Fig5/6：MIMIC 与 eICU PAMM `s(expo)` **均** P<α",
  paste0("- 生成: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  paste0("- dry_run: ", dry),
  "",
  "## 通过",
  paste(pass_ix, collapse = ", "),
  "",
  "## 失败（已改名 failed）",
  paste(if (dry) fail_ix else renamed, collapse = ", "),
  "",
  paste0("CSV: ", csv)
)
writeLines(manifest, file.path(out_dir, "audit_fig2_pamm_gate.md"))
cli::cli_alert_success("报告 → {.file {csv}}")
