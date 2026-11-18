#!/usr/bin/env Rscript
# 横断面中介：FI → BMI → Hip fracture（BMI 作中介；不用血检）
# 更新 summary_result（50）/（65） Table S6 / S7 / Figure S1 + Methods

suppressPackageStartupMessages({
  library(mediation)
  library(openxlsx)
  library(ggplot2)
})

`%||%` <- function(a, b) if (!is.null(a)) a else b

eng <- "/mnt/e/01block/01Block-new-Final"
source(file.path(eng, "R/utils.R"), local = FALSE)
source(file.path(eng, "Blocks/20_mediation/01block_mediation_prognosis.R"), local = FALSE)
n_panel_py <- file.path(eng, "R/dual_db_compose_n_panel.py")
g_base <- "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747"

.fmt_p <- function(p) {
  if (!is.finite(p)) return("")
  if (p < 0.001) "<0.001" else sprintf("%.3f", round(p, 3))
}
.fmt_p4 <- function(p) {
  if (!is.finite(p)) return("")
  if (p < 0.001) "<0.001" else sprintf("%.4f", p)
}
.fmt_cell <- function(est, lo, hi, p) {
  paste0(sprintf("%.4f", est), "[", sprintf("%.4f", lo), ", ", sprintf("%.4f", hi), "]", .fmt_p(p))
}
.fmt_prop <- function(prop) {
  if (!is.finite(prop)) return("")
  paste0(sprintf("%.1f", abs(as.numeric(prop)) * 100), "%")
}

.load_imputed <- function(engine_root, db) {
  ck <- file.path(engine_root, paste0("phase1_", db, "_allages"), "checkpoints", "imputation.rds")
  if (!file.exists(ck)) ck <- file.path(engine_root, paste0("phase1_", db), "checkpoints", "imputation.rds")
  obj <- readRDS(ck)
  obj$ctx$data$imputed %||% obj$ctx$data$cleaned
}

.read_lock <- function(engine_root) {
  f <- file.path(engine_root, "mediation_depression_covar_lock.txt")
  lines <- readLines(f, warn = FALSE)
  m2 <- trimws(strsplit(sub("^Model2=", "", grep("^Model2=", lines, value = TRUE)[1]), "\\+")[[1]])
  m1 <- trimws(strsplit(sub("^Model1=", "", grep("^Model1=", lines, value = TRUE)[1]), "\\+")[[1]])
  list(m1 = m1, m2 = m2)
}

.write_xlsx <- function(path, title, df, note = NULL) {
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Sheet1")
  openxlsx::writeData(wb, 1, title, startRow = 1, startCol = 1)
  openxlsx::writeData(wb, 1, df, startRow = 2, startCol = 1, colNames = TRUE)
  if (!is.null(note)) openxlsx::writeData(wb, 1, note, startRow = 2L + nrow(df) + 1L, startCol = 1)
  st <- openxlsx::createStyle(fontName = "Times New Roman", fontSize = 11)
  openxlsx::addStyle(wb, 1, st, rows = 1:(3L + nrow(df)), cols = 1:max(1L, ncol(df)),
                     gridExpand = TRUE, stack = TRUE)
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
}

.compose <- function(pdfs, labels, out) {
  cmd <- paste(
    shQuote(Sys.which("python3")), shQuote(n_panel_py),
    "--out", shQuote(out),
    "--inputs", paste(shQuote(pdfs), collapse = " "),
    "--labels", paste(shQuote(labels), collapse = " "),
    "--layout", "stack", "--font-size", "13"
  )
  system(cmd)
  stopifnot(file.exists(out))
}

.fit_corr <- function(dat, db, m1, m2) {
  dat$.y <- as.integer(as.character(dat$Disease_Group) == "Hip_Fracture")
  m1 <- intersect(m1, names(dat)); m2 <- intersect(m2, names(dat))
  .row <- function(resp, pred, covs, family) {
    covs <- setdiff(covs, c(resp, pred))
    fml <- stats::as.formula(paste(resp, "~", paste(c(pred, covs), collapse = "+")))
    if (identical(family, "binomial")) {
      fit <- stats::glm(fml, data = dat, family = binomial())
      cf <- summary(fit)$coefficients
      if (!pred %in% rownames(cf)) return(list(est = NA, lo = NA, hi = NA, p = NA, metric = "OR"))
      b <- cf[pred, 1]; se <- cf[pred, 2]; p <- cf[pred, 4]
      list(est = exp(b), lo = exp(b - 1.96 * se), hi = exp(b + 1.96 * se), p = p, metric = "OR")
    } else {
      fit <- stats::lm(fml, data = dat)
      cf <- summary(fit)$coefficients
      if (!pred %in% rownames(cf)) return(list(est = NA, lo = NA, hi = NA, p = NA, metric = "beta"))
      b <- cf[pred, 1]; se <- cf[pred, 2]; p <- cf[pred, 4]
      list(est = b, lo = b - 1.96 * se, hi = b + 1.96 * se, p = p, metric = "beta")
    }
  }
  .fe <- function(r) {
    if (!is.finite(r$est)) return("")
    d <- if (identical(r$metric, "OR")) 3 else 4
    sprintf(paste0("%.", d, "f"), r$est)
  }
  .fc <- function(r) {
    if (!is.finite(r$lo)) return("")
    d <- if (identical(r$metric, "OR")) 3 else 4
    sprintf(paste0("(%.", d, "f, %.", d, "f)"), r$lo, r$hi)
  }
  pairs <- list(
    list(lab = "Frailty Index and BMI", resp = "BMI", pred = "FI", fam = "gaussian"),
    list(lab = "Frailty Index and Hip fracture", resp = ".y", pred = "FI", fam = "binomial"),
    list(lab = "BMI and Hip fracture", resp = ".y", pred = "BMI", fam = "binomial")
  )
  rows <- list(data.frame(
    Variable = db, Estimate = "", `95% CI` = "", `P value` = "",
    check.names = FALSE, stringsAsFactors = FALSE
  ))
  for (pr in pairs) {
    rows[[length(rows) + 1]] <- data.frame(
      Variable = pr$lab, Estimate = "", `95% CI` = "", `P value` = "",
      check.names = FALSE, stringsAsFactors = FALSE
    )
    for (model in c("Crude", "Model 1", "Model 2")) {
      covs <- if (model == "Crude") character(0) else if (model == "Model 1") m1 else m2
      r <- .row(pr$resp, pr$pred, covs, pr$fam)
      rows[[length(rows) + 1]] <- data.frame(
        Variable = model, Estimate = .fe(r), `95% CI` = .fc(r), `P value` = .fmt_p4(r$p),
        check.names = FALSE, stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, rows)
}

.fit_med <- function(dat, db, covars, sims = 1000L, seed = 40595747L) {
  dat$.__y_bin <- as.integer(as.character(dat$Disease_Group) == "Hip_Fracture")
  cov_d <- intersect(covars, names(dat))
  drop <- character(0)
  for (cv in cov_d) {
    v <- dat[[cv]]
    if (is.character(v) || is.factor(v) || is.logical(v)) {
      dat[[cv]] <- factor(as.character(v))
      if (nlevels(droplevels(stats::na.omit(dat[[cv]]))) < 2) drop <- c(drop, cv)
    } else if (length(unique(stats::na.omit(v))) < 2) drop <- c(drop, cv)
  }
  cov_d <- setdiff(cov_d, unique(drop))
  need <- c("FI", "BMI", ".__y_bin", cov_d)
  my <- dat[stats::complete.cases(dat[, need, drop = FALSE]), , drop = FALSE]
  stopifnot(nrow(my) >= 30)
  rhs_a <- paste(c("FI", cov_d), collapse = "+")
  rhs_b <- paste(c("BMI", "FI", cov_d), collapse = "+")
  b_fit <- stats::lm(stats::as.formula(paste("BMI ~", rhs_a)), data = my)
  c_fit <- stats::glm(stats::as.formula(paste(".__y_bin ~", rhs_b)), data = my, family = binomial())
  xtr <- as.numeric(my$FI); xtr <- xtr[is.finite(xtr)]
  tv <- as.numeric(stats::quantile(xtr, 0.75, na.rm = TRUE, names = FALSE))
  cv <- as.numeric(stats::quantile(xtr, 0.25, na.rm = TRUE, names = FALSE))
  set.seed(seed)
  cc <- mediation::mediate(
    b_fit, c_fit, sims = sims, treat = "FI", mediator = "BMI",
    treat.value = tv, control.value = cv
  )
  s <- summary(cc)
  a_ci <- tryCatch(stats::confint(b_fit)["FI", ], error = function(e) c(NA, NA))
  b_ci <- tryCatch(stats::confint.default(c_fit)["BMI", ], error = function(e) c(NA, NA))
  list(
    db = db, N = nrow(my), covariates = cov_d,
    med_type = if (sign(s$d0) == sign(s$z0)) "Complementary" else "Competitive (suppression)",
    tau = s$tau.coef, tau_ci = s$tau.ci, tau_p = s$tau.p,
    z0 = s$z0, z0_ci = s$z0.ci, z0_p = s$z0.p,
    d0 = s$d0, d0_ci = s$d0.ci, d0_p = s$d0.p, prop = s$n.avg,
    a_coef = unname(coef(b_fit)["FI"]), a_ci = a_ci, a_p = summary(b_fit)$coefficients["FI", 4],
    b_coef = unname(coef(c_fit)["BMI"]), b_ci = b_ci, b_p = summary(c_fit)$coefficients["BMI", 4]
  )
}

.run_cut <- function(age_cut) {
  message("\n==== Age>=", age_cut, " FI→BMI→Hip ====")
  g_dir <- file.path(g_base, sprintf("summary_result（%d）", age_cut))
  eng_root <- file.path(eng, "Output", sprintf("16_Hip_fracture_cross-laged_40595747_age%d", age_cut))
  lock <- .read_lock(eng_root)
  dbs <- c("CHARLS", "ELSA", "HRS")
  corr_parts <- list(); meds <- list()
  for (db in dbs) {
    dat <- .load_imputed(eng_root, db)
    stopifnot(all(c("BMI", "FI", "Disease_Group") %in% names(dat)))
    corr_parts[[db]] <- .fit_corr(dat, db, lock$m1, lock$m2)
    message("mediate ", db, " ...")
    meds[[db]] <- .fit_med(dat, db, lock$m2)
    message(sprintf(
      "  %s a_p=%.4g b_p=%.4g ACME_p=%.4g prop=%s type=%s",
      db, meds[[db]]$a_p, meds[[db]]$b_p, meds[[db]]$d0_p,
      .fmt_prop(meds[[db]]$prop), meds[[db]]$med_type
    ))
  }
  corr_df <- do.call(rbind, corr_parts)
  s6_title <- "Table S6. Correlation regression of Frailty Index, BMI and Hip fracture (cross-sectional, Table 1)"
  s6_note <- sprintf(
    paste0(
      "Note: Cross-sectional Table 1 sample. Exposure=Frailty Index, mediator=BMI, outcome=Hip fracture. ",
      "Model 1: %s. Model 2 (shared across cohorts): %s. Continuous~continuous=beta; binary outcome=OR."
    ),
    paste(lock$m1, collapse = ", "), paste(lock$m2, collapse = ", ")
  )
  unlink(list.files(file.path(g_dir, "Tables"), pattern = "^Table S6\\.", full.names = TRUE))
  .write_xlsx(file.path(g_dir, "Tables", paste0(s6_title, ".xlsx")), s6_title, corr_df, s6_note)

  s7_rows <- lapply(dbs, function(db) {
    r <- meds[[db]]
    data.frame(
      Cohort = db,
      `Total effect (c)` = .fmt_cell(r$tau, r$tau_ci[1], r$tau_ci[2], r$tau_p),
      `Direct effect (c')` = .fmt_cell(r$z0, r$z0_ci[1], r$z0_ci[2], r$z0_p),
      `Indirect effect (a*b)` = .fmt_cell(r$d0, r$d0_ci[1], r$d0_ci[2], r$d0_p),
      `Path a (FI -> BMI)` = paste0(
        sprintf("%.4f", r$a_coef), "[", sprintf("%.4f", r$a_ci[1]), ", ",
        sprintf("%.4f", r$a_ci[2]), "]", .fmt_p(r$a_p)
      ),
      `Path b (BMI -> Hip fracture)` = paste0(
        sprintf("%.4f", r$b_coef), "[", sprintf("%.4f", r$b_ci[1]), ", ",
        sprintf("%.4f", r$b_ci[2]), "]", .fmt_p(r$b_p)
      ),
      `Proportion mediated` = .fmt_prop(r$prop),
      check.names = FALSE, stringsAsFactors = FALSE
    )
  })
  s7_df <- do.call(rbind, s7_rows)
  type_note <- paste(vapply(dbs, function(db) {
    paste0(db, ": ", meds[[db]]$med_type, " (cov=", paste(meds[[db]]$covariates, collapse = "+"), ")")
  }, character(1)), collapse = "; ")
  s7_title <- "Table S7. Cross-sectional mediation of Frailty Index to BMI to Hip fracture (Table 1)"
  s7_note <- paste0(
    "Note: Effects are risk difference (95% CI) P value. Path a/b are regression coefficients (95% CI) P value. ",
    "Shared Model2 covariates: ", paste(lock$m2, collapse = "+"),
    ". Bootstrap sims=1000, seed=40595747. Continuous FI contrast = within-cohort P25→P75. ",
    type_note, "."
  )
  unlink(list.files(file.path(g_dir, "Tables"), pattern = "^Table S7\\.", full.names = TRUE))
  .write_xlsx(file.path(g_dir, "Tables", paste0(s7_title, ".xlsx")), s7_title, s7_df, s7_note)

  tmp <- tempfile("medbmi_"); dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  pdfs <- character(0); labs <- character(0); letters <- c("A", "B", "C")
  for (i in seq_along(dbs)) {
    db <- dbs[i]; r <- meds[[db]]
    pdf_file <- file.path(tmp, paste0(db, ".pdf"))
    set.seed(40595747L + i)
    cols <- .mp01_palettes[[sample(names(.mp01_palettes), 1)]]
    prop_pct <- if (is.finite(r$prop)) abs(as.numeric(r$prop)) * 100 else NA_real_
    .mp01_draw_mediation_path_diagram(
      exposure_label = "Frailty Index",
      mediator_label = "BMI",
      outcome_label = "Hip fracture",
      coef_a = r$a_coef, p_a = r$a_p,
      coef_b = r$b_coef, p_b = r$b_p,
      effect_total = r$z0, p_total = r$z0_p,
      prop_pct = prop_pct, prop_lo_pct = NA_real_, prop_hi_pct = NA_real_,
      colors = cols,
      ci_a_lo = r$a_ci[1], ci_a_hi = r$a_ci[2],
      ci_b_lo = r$b_ci[1], ci_b_hi = r$b_ci[2],
      ci_tot_lo = r$z0_ci[1], ci_tot_hi = r$z0_ci[2],
      output_path = pdf_file
    )
    pdfs <- c(pdfs, pdf_file)
    labs <- c(labs, paste0(letters[i], ". ", db))
  }
  unlink(list.files(file.path(g_dir, "Figures", "pdf"), pattern = "^Figure S1\\.", full.names = TRUE))
  unlink(list.files(file.path(g_dir, "Figures", "image_information"), pattern = "^Figure S1\\.", full.names = TRUE))
  out_s1 <- file.path(
    g_dir, "Figures", "pdf",
    "Figure S1. Cross-sectional mediation path diagram of FI BMI and hip fracture.pdf"
  )
  .compose(pdfs, labs, out_s1)
  writeLines(c(
    "# Figure S1. Cross-sectional mediation path diagram of FI BMI and hip fracture",
    "", "## 图面说明", "",
    "横断面中介路径图：Frailty Index → BMI → Hip fracture。A/B/C 对应 CHARLS / ELSA / HRS。底边箭为 Direct effect (c′)，与 Table S7 一致。",
    "", "## 分析上下文", "",
    sprintf("Age ≥ %d；Table 1 分析集；共用 Model2=%s；先 Table S6 相关再 Table S7 中介。",
            age_cut, paste(lock$m2, collapse = "+"))
  ), file.path(
    g_dir, "Figures", "image_information",
    "Figure S1. Cross-sectional mediation path diagram of FI BMI and hip fracture.md"
  ))

  md <- file.path(g_dir, "Methods_statistical_analysis.md")
  lines <- readLines(md, warn = FALSE)
  i0 <- match("## Change analysis and mediation", lines)
  i1 <- which(grepl("^## ", lines)); i1 <- i1[i1 > i0][1]
  if (is.finite(i0) && is.finite(i1)) {
    new_body <- c(
      "## Change analysis and mediation",
      "Mean FI and FI change tables followed the main logistic grouping scheme (tertile).",
      paste0(
        "Cross-sectional mediation used Frailty Index as the exposure and BMI as the mediator ",
        "(Frailty Index → BMI → hip fracture) on the Table 1 analytic sample, with the ",
        "product-of-coefficients framework and bootstrap intervals (sims = 1000, seed = 40595747). ",
        "Correlation regressions (Table S6) used the same shared covariates and preceded mediation. ",
        "Shared Model 2 covariates across CHARLS, ELSA and HRS were: ",
        paste(lock$m2, collapse = ", "),
        ". Path diagrams place the Direct effect (c′) on the bottom arrow, aligned with Table S7."
      ),
      ""
    )
    lines <- c(lines[seq_len(i0 - 1L)], new_body, lines[i1:length(lines)])
    writeLines(lines, md)
  }
  s7_df
}

res50 <- .run_cut(50L)
res65 <- .run_cut(65L)
cat("\n==== Age50 ====\n"); print(res50)
cat("\n==== Age65 ====\n"); print(res65)
message("DONE FI→BMI→Hip")
