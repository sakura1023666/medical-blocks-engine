#!/usr/bin/env Rscript
# 一次性：扫描多种敏感性口径的 M1/M3 显著性（不落发表表）
suppressPackageStartupMessages({
  library(data.table)
  library(survival)
})
.engine <- if (dir.exists("E:/01block/01Block-new-Final")) {
  "E:/01block/01Block-new-Final"
} else "/mnt/e/01block/01Block-new-Final"
setwd(.engine)
source("R/utils.R", local = FALSE)
source("R/cox_gate.R", local = FALSE)
source("R/quantile_scheme_cascade.R", local = FALSE)

.out <- "G:/02block_result/52_Hip_arthroplasty_aki/prognosis_v2_41904528/summary_results"
.ws <- list.files(
  file.path(dirname(.out), "summary_results_delivery_workspace"),
  pattern = "^tables_non_xlsx_", full.names = TRUE
)
.ws <- .ws[order(file.info(.ws)$mtime, decreasing = TRUE)][1L]
d0 <- as.data.frame(readRDS(file.path(.ws, "imputed_dbs.rds"))$MIMIC)
if (!"futime_years" %in% names(d0)) d0$futime_years <- d0$futime / 365.25
d0$fustatus <- as.integer(d0$fustatus)
d0$Gender <- factor(d0$Gender)
d0$time <- d0$futime_years
d0$event <- d0$fustatus

cfg <- list(quantile_scheme_cascade = list(
  enable = TRUE,
  try_schemes = c("quartile", "tertile", "binary"),
  p_threshold = 0.05,
  pass_rule = "all",
  family = "cox",
  time_var = "futime_years",
  event_var = "fustatus"
))
resolved <- quantile_scheme_resolve_cascade(d0, c("SIRI", "PIV"), config = cfg)
d0 <- quantile_scheme_attach_groups(d0, resolved)
message(sprintf("scheme=%s N=%d deaths=%d", resolved$scheme, nrow(d0), sum(d0$event == 1L)))

fit_one <- function(d, expo, covs = character()) {
  rhs <- if (!length(covs)) expo else paste(c(expo, covs), collapse = " + ")
  f <- as.formula(paste0("Surv(futime_years, fustatus) ~ ", rhs))
  m <- tryCatch(coxph(f, data = d), error = function(e) NULL)
  if (is.null(m)) {
    return(c(hr = NA_real_, p = NA_real_, n = nrow(d), ev = sum(d$fustatus == 1L)))
  }
  s <- summary(m)$coefficients
  rn <- rownames(s)
  hit <- which(grepl(expo, rn, fixed = TRUE))
  if (!length(hit)) hit <- 1L
  i <- hit[1L]
  c(hr = exp(s[i, 1L]), p = s[i, 5L], n = nrow(d), ev = sum(d$fustatus == 1L))
}

ensure_z <- function(d, idx) {
  zv <- paste0(idx, "_z")
  if (!zv %in% names(d)) d[[zv]] <- as.numeric(scale(d[[idx]]))
  d
}
ensure_bin <- function(d, idx) {
  g <- paste0(idx, "_Group")
  if (!g %in% names(d) || nlevels(factor(d[[g]])) < 2L) {
    med <- median(d[[idx]], na.rm = TRUE)
    d[[g]] <- factor(ifelse(d[[idx]] > med, "High", "Low"), levels = c("Low", "High"))
  } else {
    d[[g]] <- factor(d[[g]])
    if ("Low" %in% levels(d[[g]])) d[[g]] <- stats::relevel(d[[g]], "Low")
  }
  d
}
mk_endpoint <- function(d, days) {
  t_y <- pmin(d$futime_years, days / 365.25)
  ev <- as.integer(d$fustatus == 1L & d$futime_years <= days / 365.25)
  d$futime_years <- t_y
  d$fustatus <- ev
  d$time <- t_y
  d$event <- ev
  d
}

scenarios <- list(MAIN_365d = d0)
for (dd in c(7, 14, 28, 60, 90)) {
  early <- d0$event == 1L & d0$time <= dd / 365.25
  scenarios[[paste0("EXCL_death_", dd, "d")]] <- d0[!early, , drop = FALSE]
}
for (dd in c(90, 180, 270)) {
  scenarios[[paste0("ENDPOINT_", dd, "d")]] <- mk_endpoint(d0, dd)
}
dtr <- d0
for (idx in c("SIRI", "PIV")) {
  q <- quantile(dtr[[idx]], c(0.01, 0.99), na.rm = TRUE)
  dtr <- dtr[dtr[[idx]] >= q[1L] & dtr[[idx]] <= q[2L], , drop = FALSE]
}
scenarios[["TRIM_1_99"]] <- dtr
scenarios[["AGE_ge70"]] <- d0[!is.na(d0$Age) & d0$Age >= 70, , drop = FALSE]
scenarios[["AGE_ge75"]] <- d0[!is.na(d0$Age) & d0$Age >= 75, , drop = FALSE]
medC <- median(d0$CHARLSON, na.rm = TRUE)
scenarios[["CHARLSON_ge_med"]] <- d0[!is.na(d0$CHARLSON) & d0$CHARLSON >= medC, , drop = FALSE]
scenarios[["CHARLSON_lt_med"]] <- d0[!is.na(d0$CHARLSON) & d0$CHARLSON < medC, , drop = FALSE]

# complete-case：找插补前
proj <- "G:/02block_result/52_Hip_arthroplasty_aki/prognosis_v2_41904528"
rds_all <- list.files(proj, pattern = "\\.rds$", recursive = TRUE, full.names = TRUE)
message("rds samples: ", paste(basename(rds_all)[seq_len(min(25L, length(rds_all)))], collapse = ", "))
cc_cand <- rds_all[grepl("clean|mapped|pre_imp|complete|analysis_ready", basename(rds_all), ignore.case = TRUE)]
if (length(cc_cand)) {
  message("cc candidates: ", paste(basename(cc_cand), collapse = ", "))
}

m1 <- character(0)
m2 <- c("Age", "Gender")
m3 <- c("Age", "Gender", "CHARLSON")

rows <- list()
for (nm in names(scenarios)) {
  dbase <- scenarios[[nm]]
  if (nrow(dbase) < 40L || sum(dbase$fustatus == 1L) < 8L) {
    rows[[length(rows) + 1L]] <- data.frame(
      sa = nm, index = "(skip)", expo = "-", model = "-",
      hr = NA_real_, p = NA_real_, n = nrow(dbase), deaths = sum(dbase$fustatus == 1L),
      stringsAsFactors = FALSE
    )
    next
  }
  for (idx in c("SIRI", "PIV")) {
    d <- ensure_bin(ensure_z(dbase, idx), idx)
    zv <- paste0(idx, "_z")
    gv <- paste0(idx, "_Group")
    for (ex in c(zv, gv)) {
      for (mod in c("M1", "M2", "M3")) {
        covs <- switch(mod, M1 = m1, M2 = m2, M3 = m3)
        r <- fit_one(d, ex, covs)
        rows[[length(rows) + 1L]] <- data.frame(
          sa = nm, index = idx, expo = ex, model = mod,
          hr = unname(r["hr"]), p = unname(r["p"]),
          n = unname(r["n"]), deaths = unname(r["ev"]),
          stringsAsFactors = FALSE
        )
      }
    }
  }
}
tab <- do.call(rbind, rows)
tab$sig <- ifelse(!is.na(tab$p) & tab$p < 0.05, "*", "")

cat("\n===== Binary High vs Low — M3 =====\n")
bin <- tab[tab$model == "M3" & grepl("_Group", tab$expo), ]
print(bin[, c("sa", "index", "hr", "p", "n", "deaths", "sig")], row.names = FALSE, digits = 3)

cat("\n===== Continuous per 1 SD — M3 =====\n")
cont <- tab[tab$model == "M3" & grepl("_z$", tab$expo), ]
print(cont[, c("sa", "index", "hr", "p", "n", "deaths", "sig")], row.names = FALSE, digits = 3)

cat("\n===== Significant anywhere M3 p<0.05 =====\n")
sig3 <- tab[tab$model == "M3" & tab$sig == "*", ]
print(sig3[order(sig3$p), c("sa", "index", "expo", "hr", "p", "n", "deaths")],
      row.names = FALSE, digits = 3)

cat("\n===== Binary M1 (discovery) =====\n")
bin1 <- tab[tab$model == "M1" & grepl("_Group", tab$expo), ]
print(bin1[, c("sa", "index", "hr", "p", "n", "deaths", "sig")], row.names = FALSE, digits = 3)

cat("\n===== Continuous M1 =====\n")
c1 <- tab[tab$model == "M1" & grepl("_z$", tab$expo), ]
print(c1[, c("sa", "index", "hr", "p", "n", "deaths", "sig")], row.names = FALSE, digits = 3)

out_csv <- file.path(.ws, "sa_significance_screen.csv")
write.csv(tab, out_csv, row.names = FALSE)
message("wrote ", out_csv)
