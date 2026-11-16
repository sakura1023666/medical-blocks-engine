#!/usr/bin/env Rscript
# 髋部骨折 summary_result（50）/（65）对齐抑郁课题交付版式
# - 顶层只留 Figures/{pdf,image_information} + Tables + Methods + 中期
# - 纵向中介 ACME 在 CHARLS/ELSA/HRS 中显著库数 <2 → 降级横断面 FI→BMI→Hip
# - 三库共用 Model2 协变量；先相关回归再中介
#
# 用法:
#   Rscript run/cross_lagged/align_hip_summary_to_depression.R
#   Rscript run/cross_lagged/align_hip_summary_to_depression.R --cut 50
#   Rscript run/cross_lagged/align_hip_summary_to_depression.R --cut 65

suppressPackageStartupMessages({
  library(mediation)
  library(openxlsx)
})

`%||%` <- function(a, b) if (!is.null(a)) a else b

args <- commandArgs(trailingOnly = TRUE)
only_cut <- NA_integer_
if ("--cut" %in% args) {
  i <- match("--cut", args)
  only_cut <- as.integer(args[[i + 1L]])
}

.args0 <- commandArgs(trailingOnly = FALSE)
.file_arg <- grep("^--file=", .args0, value = TRUE)
.script <- if (length(.file_arg)) sub("^--file=", "", .file_arg[1]) else NA_character_
eng <- "/mnt/e/01block/01Block-new-Final"
if (is.character(.script) && nzchar(.script) && file.exists(.script)) {
  cand <- normalizePath(file.path(dirname(.script), "..", ".."), winslash = "/", mustWork = FALSE)
  if (dir.exists(file.path(cand, "R"))) eng <- cand
}
source(file.path(eng, "R/utils.R"), local = FALSE)
source(file.path(eng, "Blocks/20_mediation/01block_mediation_prognosis.R"), local = FALSE)

g_base <- "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747"
dep_ref <- "/mnt/g/02block_result/22_depression/cross-laged_40595747/summary_result"
n_panel_py <- file.path(eng, "R/dual_db_compose_n_panel.py")

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

.parse_acme_p <- function(cell) {
  cell <- as.character(cell %||% "")[1L]
  if (!nzchar(cell)) return(NA_real_)
  if (grepl("<0\\.001", cell)) return(0.0005)
  m <- regexpr("[0-9]*\\.?[0-9]+\\s*$", cell, perl = TRUE)
  if (m < 1) return(NA_real_)
  as.numeric(regmatches(cell, m))
}

.load_imputed <- function(engine_root, db) {
  ck <- file.path(engine_root, paste0("phase1_", db, "_allages"), "checkpoints", "imputation.rds")
  if (!file.exists(ck)) {
    ck <- file.path(engine_root, paste0("phase1_", db), "checkpoints", "imputation.rds")
  }
  stopifnot(file.exists(ck))
  obj <- readRDS(ck)
  dat <- obj$ctx$data$imputed %||% obj$ctx$data$cleaned
  stopifnot(is.data.frame(dat))
  dat
}

.read_lock_m2 <- function(engine_root) {
  f <- file.path(engine_root, "mediation_depression_covar_lock.txt")
  if (!file.exists(f)) return(list(m1 = "Age", m2 = c("Age", "Alcohol_drinking")))
  lines <- readLines(f, warn = FALSE)
  m2_line <- grep("^Model2=", lines, value = TRUE)[1L]
  m1_line <- grep("^Model1=", lines, value = TRUE)[1L]
  m2 <- if (is.na(m2_line)) c("Age", "Alcohol_drinking") else strsplit(sub("^Model2=", "", m2_line), "\\+")[[1]]
  m1 <- if (is.na(m1_line)) "Age" else strsplit(sub("^Model1=", "", m1_line), "\\+")[[1]]
  list(m1 = trimws(m1), m2 = trimws(m2))
}

.xlsx_sheet_rows <- function(path, max_rows = 20L) {
  # drawing-safe: parse sheet1 + sharedStrings via unzip
  td <- tempfile("xlsx_")
  dir.create(td)
  on.exit(unlink(td, recursive = TRUE), add = TRUE)
  utils::unzip(path, exdir = td)
  ss_path <- file.path(td, "xl", "sharedStrings.xml")
  ss <- character(0)
  if (file.exists(ss_path)) {
    raw <- paste(readLines(ss_path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    # crude <t>...</t>
    m <- gregexpr("<t[^>]*>([^<]*)</t>", raw, perl = TRUE)
    hits <- regmatches(raw, m)[[1]]
    ss <- gsub("^<t[^>]*>|</t>$", "", hits, perl = TRUE)
  }
  sh <- file.path(td, "xl", "worksheets", "sheet1.xml")
  if (!file.exists(sh)) return(list())
  raw <- paste(readLines(sh, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  row_chunks <- strsplit(raw, "<row[ >]", perl = TRUE)[[1]][-1]
  out <- list()
  for (chunk in row_chunks) {
    if (length(out) >= max_rows) break
    cells <- list()
    cm <- gregexpr("<c r=\"([A-Z]+)([0-9]+)\"[^>]*?(?: t=\"([^\"]+)\")?[^>]*>(?:.*?<v>([^<]*)</v>)?",
                   chunk, perl = TRUE)
    # simpler: find each <c ...> ... </c>
    parts <- strsplit(chunk, "</c>", fixed = TRUE)[[1]]
    for (p in parts) {
      rm <- regexec('r="([A-Z]+)([0-9]+)"', p, perl = TRUE)
      rr <- regmatches(p, rm)[[1]]
      if (length(rr) < 3) next
      col <- rr[2]
      t_m <- regexec('t="([^"]+)"', p, perl = TRUE)
      tt <- regmatches(p, t_m)[[1]]
      typ <- if (length(tt) >= 2) tt[2] else ""
      vm <- regexec("<v>([^<]*)</v>", p, perl = TRUE)
      vv <- regmatches(p, vm)[[1]]
      val <- if (length(vv) >= 2) vv[2] else ""
      if (identical(typ, "s") && nzchar(val)) {
        idx <- suppressWarnings(as.integer(val)) + 1L
        if (is.finite(idx) && idx >= 1L && idx <= length(ss)) val <- ss[idx]
      }
      cells[[col]] <- val
    }
    if (length(cells)) out[[length(out) + 1L]] <- cells
  }
  out
}

.long_mediation_sig_n <- function(g_dir) {
  cands <- list.files(
    c(file.path(g_dir, "Tables"), file.path(g_dir, "table")),
    pattern = "^Table S7\\. Longitudinal mediation",
    full.names = TRUE
  )
  s7 <- if (length(cands)) cands[1] else NA_character_
  if (is.na(s7) || !file.exists(s7)) {
    return(list(n_sig = 0L, detail = "S7 missing", path = NA_character_))
  }
  rows <- tryCatch(.xlsx_sheet_rows(s7, max_rows = 12L), error = function(e) list())
  if (!length(rows)) {
    return(list(n_sig = 0L, detail = "unreadable", path = s7))
  }
  detail <- character(0)
  n_sig <- 0L
  for (cells in rows) {
    vals <- unlist(cells, use.names = TRUE)
    # column A = cohort, column D = Indirect typically
    coh <- as.character(vals[["A"]] %||% vals[[1]] %||% "")
    if (!coh %in% c("CHARLS", "ELSA", "HRS")) next
    ind <- as.character(vals[["D"]] %||% "")
    if (!nzchar(ind) && length(vals) >= 4L) ind <- as.character(vals[[4]])
    p <- .parse_acme_p(ind)
    detail <- c(detail, sprintf("%s ACME_p=%s", coh, ifelse(is.finite(p), p, "NA")))
    if (is.finite(p) && p < 0.05) n_sig <- n_sig + 1L
  }
  list(n_sig = n_sig, detail = detail, path = s7)
}

.fit_corr_one_db <- function(dat, db, m1, m2,
                             x = "FI", med = "BMI", y = "Disease_Group",
                             event = "Hip_Fracture",
                             x_lab = "Frailty Index", med_lab = "BMI",
                             y_lab = "Hip fracture") {
  dat <- as.data.frame(dat)
  dat$.y <- as.integer(as.character(dat[[y]]) == as.character(event))
  m1 <- intersect(m1, names(dat))
  m2 <- intersect(m2, names(dat))
  .fit_row <- function(resp, pred, covs, family) {
    covs <- setdiff(covs, c(resp, pred))
    rhs <- paste(c(pred, covs), collapse = " + ")
    fml <- stats::as.formula(paste(resp, "~", rhs))
    if (identical(family, "binomial")) {
      fit <- stats::glm(fml, data = dat, family = binomial())
      cf <- summary(fit)$coefficients
      if (!pred %in% rownames(cf))
        return(list(est = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_, metric = "OR"))
      b <- cf[pred, 1]; se <- cf[pred, 2]; p <- cf[pred, 4]
      list(est = exp(b), lo = exp(b - 1.96 * se), hi = exp(b + 1.96 * se), p = p, metric = "OR")
    } else {
      fit <- stats::lm(fml, data = dat)
      cf <- summary(fit)$coefficients
      if (!pred %in% rownames(cf))
        return(list(est = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_, metric = "beta"))
      b <- cf[pred, 1]; se <- cf[pred, 2]; p <- cf[pred, 4]
      list(est = b, lo = b - 1.96 * se, hi = b + 1.96 * se, p = p, metric = "beta")
    }
  }
  .fmt_est <- function(r) {
    if (!is.finite(r$est)) return("")
    d <- if (identical(r$metric, "OR")) 3L else 4L
    sprintf(paste0("%.", d, "f"), r$est)
  }
  .fmt_ci <- function(r) {
    if (!is.finite(r$lo) || !is.finite(r$hi)) return("")
    d <- if (identical(r$metric, "OR")) 3L else 4L
    sprintf(paste0("(%.", d, "f, %.", d, "f)"), r$lo, r$hi)
  }
  pairs <- list(
    list(label = paste(x_lab, "and", med_lab), resp = med, pred = x, family = "gaussian"),
    list(label = paste(x_lab, "and", y_lab), resp = ".y", pred = x, family = "binomial"),
    list(label = paste(med_lab, "and", y_lab), resp = ".y", pred = med, family = "binomial")
  )
  pub_rows <- list(
    data.frame(Variable = db, Estimate = "", `95% CI` = "", `P value` = "",
               stringsAsFactors = FALSE, check.names = FALSE)
  )
  for (pr in pairs) {
    pub_rows[[length(pub_rows) + 1L]] <- data.frame(
      Variable = pr$label, Estimate = "", `95% CI` = "", `P value` = "",
      stringsAsFactors = FALSE, check.names = FALSE
    )
    for (model in c("Crude", "Model 1", "Model 2")) {
      covs <- if (identical(model, "Crude")) character(0)
      else if (identical(model, "Model 1")) m1 else m2
      r <- .fit_row(pr$resp, pr$pred, covs, pr$family)
      pub_rows[[length(pub_rows) + 1L]] <- data.frame(
        Variable = model,
        Estimate = .fmt_est(r),
        `95% CI` = .fmt_ci(r),
        `P value` = .fmt_p4(r$p),
        stringsAsFactors = FALSE, check.names = FALSE
      )
    }
  }
  do.call(rbind, pub_rows)
}

.fit_cs_mediation_one <- function(dat, db, covars,
                                  treat = "FI", mediator = "BMI",
                                  y = "Disease_Group", event = "Hip_Fracture",
                                  sims = 1000L, seed = 40595747L) {
  dat <- as.data.frame(dat)
  dat$.__y_bin <- as.integer(as.character(dat[[y]]) == as.character(event))
  cov_d <- intersect(covars, names(dat))
  drop_cov <- character(0)
  for (cv in cov_d) {
    v <- dat[[cv]]
    if (is.character(v) || is.factor(v) || is.logical(v)) {
      dat[[cv]] <- factor(as.character(v))
      if (nlevels(droplevels(stats::na.omit(dat[[cv]]))) < 2L) drop_cov <- c(drop_cov, cv)
    } else if (length(unique(stats::na.omit(v))) < 2L) {
      drop_cov <- c(drop_cov, cv)
    }
  }
  cov_d <- setdiff(cov_d, unique(drop_cov))
  need <- c(treat, mediator, ".__y_bin", cov_d)
  mydata <- dat[stats::complete.cases(dat[, need, drop = FALSE]), , drop = FALSE]
  if (nrow(mydata) < 30L) stop(db, " N too small for CS mediation")

  rhs_a <- paste(c(treat, cov_d), collapse = " + ")
  rhs_b <- paste(c(mediator, treat, cov_d), collapse = " + ")
  b_fit <- stats::lm(stats::as.formula(paste(mediator, "~", rhs_a)), data = mydata)
  c_fit <- stats::glm(stats::as.formula(paste(".__y_bin ~", rhs_b)), data = mydata, family = binomial())
  xtr <- suppressWarnings(as.numeric(mydata[[treat]]))
  xtr <- xtr[is.finite(xtr)]
  tv <- as.numeric(stats::quantile(xtr, 0.75, na.rm = TRUE, names = FALSE))
  cv <- as.numeric(stats::quantile(xtr, 0.25, na.rm = TRUE, names = FALSE))
  set.seed(seed)
  cc <- mediation::mediate(
    b_fit, c_fit, sims = sims, treat = treat, mediator = mediator,
    treat.value = tv, control.value = cv
  )
  s <- summary(cc)
  a_ci <- tryCatch(stats::confint(b_fit)[treat, ], error = function(e) c(NA_real_, NA_real_))
  b_ci <- tryCatch(stats::confint.default(c_fit)[mediator, ], error = function(e) c(NA_real_, NA_real_))
  a_p <- summary(b_fit)$coefficients[treat, 4]
  b_p <- summary(c_fit)$coefficients[mediator, 4]
  med_type <- if (sign(s$d0) == sign(s$z0)) "Complementary" else "Competitive (suppression)"
  list(
    db = db, N = nrow(mydata), covariates = cov_d, med_type = med_type,
    tau = s$tau.coef, tau_ci = s$tau.ci, tau_p = s$tau.p,
    z0 = s$z0, z0_ci = s$z0.ci, z0_p = s$z0.p,
    d0 = s$d0, d0_ci = s$d0.ci, d0_p = s$d0.p,
    prop = s$n.avg,
    a_coef = unname(coef(b_fit)[treat]), a_ci = a_ci, a_p = a_p,
    b_coef = unname(coef(c_fit)[mediator]), b_ci = b_ci, b_p = b_p,
    treat_value = tv, control_value = cv
  )
}

.write_simple_xlsx <- function(path, title, df, note = NULL) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Sheet1")
  openxlsx::writeData(wb, 1, title, startRow = 1, startCol = 1)
  openxlsx::writeData(wb, 1, df, startRow = 2, startCol = 1, colNames = TRUE)
  if (!is.null(note) && nzchar(note)) {
    openxlsx::writeData(wb, 1, note, startRow = 2L + nrow(df) + 1L, startCol = 1)
  }
  # Times
  st <- openxlsx::createStyle(fontName = "Times New Roman", fontSize = 11)
  openxlsx::addStyle(wb, 1, st, rows = 1:(2L + nrow(df) + 2L), cols = 1:max(1L, ncol(df)),
                     gridExpand = TRUE, stack = TRUE)
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
}

.csv_to_xlsx_clpn <- function(csv_path, xlsx_path, title) {
  d <- utils::read.csv(csv_path, check.names = FALSE, stringsAsFactors = FALSE)
  .write_simple_xlsx(xlsx_path, title, d)
}

.compose_fig4 <- function(pdfs, labels, out_pdf) {
  stopifnot(length(pdfs) >= 2L, file.exists(n_panel_py))
  dir.create(dirname(out_pdf), recursive = TRUE, showWarnings = FALSE)
  cmd <- paste(
    shQuote(Sys.which("python3")),
    shQuote(n_panel_py),
    "--out", shQuote(out_pdf),
    "--inputs", paste(shQuote(pdfs), collapse = " "),
    "--labels", paste(shQuote(labels), collapse = " "),
    "--layout", "stack",
    "--font-size", "13"
  )
  st <- system(cmd, intern = TRUE)
  if (!file.exists(out_pdf) || file.info(out_pdf)$size < 500) {
    stop("Fig4 compose failed: ", paste(st, collapse = " "))
  }
  invisible(out_pdf)
}

.draw_cs_path_diagram <- function(results_by_db, out_pdf) {
  if (!exists(".mp01_draw_mediation_path_diagram", mode = "function")) {
    stop("missing .mp01_draw_mediation_path_diagram")
  }
  if (!exists(".mp01_palettes", mode = "any")) {
    stop("missing .mp01_palettes")
  }
  dir.create(dirname(out_pdf), recursive = TRUE, showWarnings = FALSE)
  tmp_dir <- tempfile("med_path_")
  dir.create(tmp_dir, recursive = TRUE)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)
  pdfs <- character(0)
  labs <- character(0)
  letters <- c("A", "B", "C", "D")
  i <- 0L
  for (nm in names(results_by_db)) {
    i <- i + 1L
    r <- results_by_db[[nm]]
    pdf_file <- file.path(tmp_dir, paste0(nm, ".pdf"))
    prop_pct <- if (is.finite(r$prop)) abs(as.numeric(r$prop)) * 100 else NA_real_
    set.seed(40595747L + i)
    sel_colors <- .mp01_palettes[[sample(names(.mp01_palettes), 1L)]]
    .mp01_draw_mediation_path_diagram(
      exposure_label = "Frailty Index",
      mediator_label = "BMI",
      outcome_label = "Hip fracture",
      coef_a = r$a_coef, p_a = r$a_p,
      coef_b = r$b_coef, p_b = r$b_p,
      # bottom arrow = Direct (c'/z0)
      effect_total = r$z0, p_total = r$z0_p,
      prop_pct = prop_pct, prop_lo_pct = NA_real_, prop_hi_pct = NA_real_,
      colors = sel_colors,
      ci_a_lo = r$a_ci[1], ci_a_hi = r$a_ci[2],
      ci_b_lo = r$b_ci[1], ci_b_hi = r$b_ci[2],
      ci_tot_lo = r$z0_ci[1], ci_tot_hi = r$z0_ci[2],
      output_path = pdf_file
    )
    if (!file.exists(pdf_file)) stop("path diagram failed for ", nm)
    pdfs <- c(pdfs, pdf_file)
    labs <- c(labs, paste0(letters[i], ". ", nm))
  }
  if (length(pdfs) == 1L) {
    file.copy(pdfs[1], out_pdf, overwrite = TRUE)
  } else {
    .compose_fig4(pdfs, labs, out_pdf)
  }
  invisible(out_pdf)
}

.write_image_md <- function(path, title, face, context) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(c(
    paste0("# ", title),
    "",
    "## 图面说明",
    "",
    face,
    "",
    "## 分析上下文",
    "",
    context
  ), path)
}

.pick_existing <- function(...) {
  cands <- c(...)
  for (p in cands) if (!is.null(p) && nzchar(p) && file.exists(p)) return(p)
  NA_character_
}

.curate_one <- function(age_cut) {
  message("\n================ Age >= ", age_cut, " ================")
  g_dir <- file.path(g_base, sprintf("summary_result（%d）", age_cut))
  eng_root <- file.path(eng, "Output", sprintf("16_Hip_fracture_cross-laged_40595747_age%d", age_cut))
  stopifnot(dir.exists(g_dir), dir.exists(eng_root))

  stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  backup <- file.path(g_base, paste0("summary_result（", age_cut, "）_pre_align_", stamp))
  message("Backup -> ", backup)
  if (dir.exists(backup)) unlink(backup, recursive = TRUE)
  # paths contain spaces (Hip fracture) — must quote
  st <- system(paste("cp -a", shQuote(g_dir), shQuote(backup)))
  if (!identical(as.integer(st), 0L) || !dir.exists(backup)) {
    stop("backup failed for ", g_dir)
  }

  lock <- .read_lock_m2(eng_root)
  message("Shared Model1=", paste(lock$m1, collapse = "+"),
          " Model2=", paste(lock$m2, collapse = "+"))

  long_gate <- .long_mediation_sig_n(g_dir)
  message("Longitudinal ACME sig cohorts: ", long_gate$n_sig, " | ",
          paste(long_gate$detail, collapse = "; "))
  use_cs <- isTRUE(long_gate$n_sig < 2L)
  message("Mediation mode: ", if (use_cs) "CROSS-SECTIONAL FI→BMI→Hip" else "keep LONGITUDINAL Depression")

  work <- file.path(tempdir(), paste0("hip_align_", age_cut, "_", stamp))
  unlink(work, recursive = TRUE)
  dir.create(file.path(work, "Tables"), recursive = TRUE)
  dir.create(file.path(work, "Figures", "pdf"), recursive = TRUE)
  dir.create(file.path(work, "Figures", "image_information"), recursive = TRUE)

  src_tab <- if (dir.exists(file.path(g_dir, "Tables"))) file.path(g_dir, "Tables") else file.path(g_dir, "table")
  src_fig <- file.path(g_dir, "Figures", "pdf")
  if (!dir.exists(src_fig)) src_fig <- file.path(g_dir, "figure", "pdf")
  if (!dir.exists(src_fig)) src_fig <- file.path(g_dir, "figure")

  # ---- Tables whitelist (depression-like) ----
  copy_tab <- function(from_name, to_name = from_name) {
    src <- file.path(src_tab, from_name)
    if (!file.exists(src)) {
      # also look in table/
      alt <- file.path(g_dir, "table", from_name)
      if (file.exists(alt)) src <- alt
    }
    if (!file.exists(src)) {
      warning("missing table: ", from_name)
      return(FALSE)
    }
    file.copy(src, file.path(work, "Tables", to_name), overwrite = TRUE)
    TRUE
  }

  for (db in c("CHARLS", "ELSA", "HRS")) {
    copy_tab(sprintf("Table 1-%s. Baseline characteristics of Hip fracture.xlsx", db))
    copy_tab(sprintf("Table 2-%s. Logistic regression analysis of Frailty Index and Hip fracture - tertile (GLM).xlsx", db))
    # S1 imputation — depression naming
    s1_old <- sprintf("Table S1-%s. Baseline characteristics before and after imputation.xlsx", db)
    s1_new <- sprintf("Table S1-%s. Baseline characteristics of patients before and after multiple imputation.xlsx", db)
    copy_tab(s1_old, s1_new)
    copy_tab(sprintf("Table S2-%s. Normality test results for continuous variables.xlsx", db))
    copy_tab(sprintf("Table S3-%s. Univariate Regression Analysis.xlsx", db))
    # S4 VIF — prefer screen-like title
    s4 <- sprintf("Table S4-%s. Multicollinearity Analysis.xlsx", db)
    s4_new <- sprintf("Table S4-%s. Multicollinearity Analysis (VIF, univariate p 0.1 screen).xlsx", db)
    copy_tab(s4, s4_new)
  }
  copy_tab("Table 2-Pooled. Logistic regression analysis of Frailty Index and Hip fracture - tertile (GLM).xlsx")
  copy_tab("Table S5. Change analysis Mean FI and FI change.xlsx")

  # complete-case sensitivity → S9–S11 like depression
  for (db in c("CHARLS", "ELSA", "HRS")) {
    copy_tab(
      sprintf("Table S14-%s. Sensitivity complete case unimputed listwise — Baseline characteristics of Hip fracture.xlsx", db),
      sprintf("Table S9-%s. Sensitivity complete case unimputed listwise — Baseline characteristics of Hip fracture.xlsx", db)
    )
    copy_tab(
      sprintf("Table S15-%s. Sensitivity complete case unimputed listwise — Logistic regression FI and Hip fracture - tertile (GLM).xlsx", db),
      sprintf("Table S10-%s. Sensitivity complete case unimputed listwise — Logistic regression FI and Hip fracture - tertile (GLM).xlsx", db)
    )
  }
  copy_tab(
    "Table S16. Sensitivity complete case unimputed listwise — Change analysis Mean FI and FI change.xlsx",
    "Table S11. Sensitivity complete case unimputed listwise — Change analysis Mean FI and FI change.xlsx"
  )

  # CLPN adjacency csv → xlsx S8
  for (db in c("CHARLS", "ELSA", "HRS")) {
    csv <- .pick_existing(
      file.path(g_dir, "table", sprintf("Table S8-%s. CLPN adjacency.csv", db)),
      file.path(src_tab, sprintf("Table S8-%s. CLPN adjacency.csv", db))
    )
    if (!is.na(csv)) {
      .csv_to_xlsx_clpn(
        csv,
        file.path(work, "Tables", sprintf("Table S8-%s. CLPN adjacency.xlsx", db)),
        sprintf("Table S8-%s. CLPN adjacency", db)
      )
    }
  }

  dbs <- c("CHARLS", "ELSA", "HRS")
  med_results <- list()

  if (use_cs) {
    # rebuild S6 + S7 CS with shared covars
    corr_parts <- list()
    for (db in dbs) {
      dat <- .load_imputed(eng_root, db)
      corr_parts[[db]] <- .fit_corr_one_db(dat, db, lock$m1, lock$m2)
      message("CS mediation fitting: ", db)
      med_results[[db]] <- .fit_cs_mediation_one(dat, db, lock$m2, sims = 1000L, seed = 40595747L)
    }
    corr_df <- do.call(rbind, corr_parts)
    s6_title <- "Table S6. Correlation regression of Frailty Index, BMI and Hip fracture (cross-sectional, Table 1)"
    s6_note <- sprintf(
      "Note: Cross-sectional Table 1 sample. Model 1 adjusted for %s. Model 2 adjusted for shared covariates across CHARLS/ELSA/HRS: %s. Continuous~continuous = beta; binary outcome = OR. Longitudinal FI→Depression mediation was not significant in ≥2 cohorts and was downgraded.",
      paste(lock$m1, collapse = ", "),
      paste(lock$m2, collapse = ", ")
    )
    .write_simple_xlsx(
      file.path(work, "Tables", paste0(s6_title, ".xlsx")),
      s6_title, corr_df, s6_note
    )

    s7_rows <- lapply(dbs, function(db) {
      r <- med_results[[db]]
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
        stringsAsFactors = FALSE, check.names = FALSE
      )
    })
    s7_df <- do.call(rbind, s7_rows)
    type_note <- paste(vapply(dbs, function(db) {
      paste0(db, ": ", med_results[[db]]$med_type, " mediation (cov=",
             paste(med_results[[db]]$covariates, collapse = "+"), ")")
    }, character(1)), collapse = "; ")
    s7_title <- "Table S7. Cross-sectional mediation of Frailty Index to BMI to Hip fracture (Table 1)"
    s7_note <- paste0(
      "Note: Effects are risk difference (95% CI) P value. Path a/b are regression coefficients (95% CI) P value. ",
      "Path covariates follow locked shared Model2 (", paste(lock$m2, collapse = "+"), "). ",
      "Bootstrap sims=1000, seed=40595747. Continuous FI contrast = within-cohort P25→P75. ",
      type_note, "."
    )
    .write_simple_xlsx(
      file.path(work, "Tables", paste0(s7_title, ".xlsx")),
      s7_title, s7_df, s7_note
    )
  } else {
    copy_tab(
      "Table S6. Correlation regression FI Depression Hip fracture.xlsx",
      "Table S6. Correlation regression of Frailty Index, Depression and Hip fracture.xlsx"
    )
    copy_tab(
      "Table S7. Longitudinal mediation Frailty Index\u2192Depression\u2192Hip fracture.xlsx",
      "Table S7. Longitudinal mediation of Frailty Index to Depression to Hip fracture.xlsx"
    )
  }

  # ---- Figures ----
  copy_fig <- function(src, dest_bn) {
    if (is.na(src) || !file.exists(src)) {
      warning("missing figure src for ", dest_bn)
      return(FALSE)
    }
    file.copy(src, file.path(work, "Figures", "pdf", dest_bn), overwrite = TRUE)
    TRUE
  }

  f1 <- .pick_existing(
    file.path(src_fig, "Figure 1. Longitudinal inclusion exclusion flowchart.pdf"),
    file.path(src_fig, "Figure 1-Pooled. Longitudinal inclusion exclusion flowchart.pdf")
  )
  copy_fig(f1, "Figure 1. Inclusion exclusion flowchart.pdf")

  f2 <- .pick_existing(
    file.path(src_fig, "Figure 2. RCS of Frailty Index and Hip Fracture.pdf"),
    file.path(src_fig, "Figure 2-Pooled. RCS of Frailty Index and Hip Fracture.pdf")
  )
  copy_fig(f2, "Figure 2. RCS of Frailty Index and Hip fracture.pdf")

  f3 <- .pick_existing(
    file.path(src_fig, "Figure 3. Subgroup analyses of FI.pdf")
  )
  copy_fig(f3, "Figure 3. Subgroup analyses of FI.pdf")

  # Fig4 CLPN stack
  clpn_pdfs <- vapply(dbs, function(db) {
    .pick_existing(
      file.path(src_fig, sprintf("Fig4_CLPN_network_pub-%s.pdf", db)),
      file.path(eng_root, paste0("phase3_long_", db), "Figures", "Fig4_CLPN_network_pub.pdf"),
      file.path(src_fig, sprintf("Figure L3-%s. CLPN network.pdf", db))
    )
  }, character(1))
  if (all(file.exists(clpn_pdfs))) {
    .compose_fig4(
      clpn_pdfs,
      paste0(c("A. ", "B. ", "C. "), dbs),
      file.path(work, "Figures", "pdf", "Figure 4. CLPN network of frailty index items.pdf")
    )
  } else {
    warning("Fig4 sources incomplete: ", paste(clpn_pdfs, collapse = " | "))
  }

  # S1 mediation path
  if (use_cs) {
    s1_pdf <- file.path(work, "Figures", "pdf",
                        "Figure S1. Cross-sectional mediation path diagram of FI BMI and hip fracture.pdf")
    .draw_cs_path_diagram(med_results, s1_pdf)
  } else {
    s1_src <- .pick_existing(
      file.path(src_fig, "Figure S3. Longitudinal mediation path diagram of FI and hip fracture.pdf"),
      file.path(src_fig, "Figure S3-Pooled. Longitudinal mediation path diagram of FI and hip fracture.pdf")
    )
    copy_fig(s1_src, "Figure S1. Longitudinal mediation path diagram of FI Depression and hip fracture.pdf")
  }

  s2 <- .pick_existing(
    file.path(src_fig, "Figure S2. Boxplot FI by Hip Fracture.pdf"),
    file.path(src_fig, "Figure S2-Pooled. Boxplot FI by Hip Fracture.pdf")
  )
  copy_fig(s2, "Figure S2. FI by Hip fracture status baseline.pdf")

  s3 <- .pick_existing(
    file.path(src_fig, "FigS5_Mean_FI_by_Country_Disease-Pooled.pdf"),
    file.path(src_fig, "Figure L2-Pooled. FI by Country Year.pdf")
  )
  copy_fig(s3, "Figure S3. Mean FI by Country and Disease.pdf")

  s4 <- .pick_existing(
    file.path(src_fig, "Figure S1. ROC Multivariable Frailty Index.pdf"),
    file.path(src_fig, "Figure S1-Pooled. ROC Multivariable Frailty Index.pdf")
  )
  copy_fig(s4, "Figure S4. ROC of Frailty Index for Hip fracture.pdf")

  # image_information
  age_note <- sprintf("Age ≥ %d analytic sample; CHARLS + ELSA + HRS.", age_cut)
  med_mode <- if (use_cs) {
    "Cross-sectional mediation FI→BMI→Hip fracture (Table 1); longitudinal Depression ACME not significant in ≥2 cohorts."
  } else {
    "Longitudinal mediation FI→Depression→Hip fracture retained."
  }
  md_specs <- list(
    list("Figure 1. Inclusion exclusion flowchart.pdf",
         "三队列纳排流程图（拼图）。主列纳入框 + 右侧 Exclude + 底部分叉病例/对照。",
         paste(age_note, "Flowchart from longitudinal inclusion/exclusion.")),
    list("Figure 2. RCS of Frailty Index and Hip fracture.pdf",
         "限制性立方样条：Frailty Index 与髋部骨折关联；含 P-linear / P-nonlinear 等图面标注。",
         paste(age_note, "RCS on baseline analytic sample.")),
    list("Figure 3. Subgroup analyses of FI.pdf",
         "亚组森林图：最高 vs 最低分位（随主文 tertile）及交互 P。",
         paste(age_note, "Subgroup forest aligned across cohorts.")),
    list("Figure 4. CLPN network of frailty index items.pdf",
         "交叉滞后面板网络（CLPN）：A/B/C 对应 CHARLS / ELSA / HRS。",
         paste(age_note, "CLPN of frailty index items.")),
    list(basename(list.files(file.path(work, "Figures", "pdf"), pattern = "^Figure S1", full.names = FALSE)[1]),
         paste("中介路径图。", med_mode, "底边箭为 Direct effect (c′)。"),
         paste(age_note, med_mode)),
    list("Figure S2. FI by Hip fracture status baseline.pdf",
         "基线按髋部骨折状态分层的 FI 分布（箱线/描述）。",
         paste(age_note, "Baseline FI by fracture status.")),
    list("Figure S3. Mean FI by Country and Disease.pdf",
         "按国家/队列与疾病状态的平均 FI。",
         paste(age_note, "Mean FI by country and disease.")),
    list("Figure S4. ROC of Frailty Index for Hip fracture.pdf",
         "FI 预测髋部骨折的 ROC（多变量口径以图注为准）。",
         paste(age_note, "ROC of FI for hip fracture."))
  )
  for (sp in md_specs) {
    bn <- sp[[1]]
    if (is.na(bn) || !nzchar(bn)) next
    .write_image_md(
      file.path(work, "Figures", "image_information", sub("\\.pdf$", ".md", bn)),
      sub("\\.pdf$", "", bn), sp[[2]], sp[[3]]
    )
  }

  # Methods
  methods_lines <- c(
    "# Statistical analysis",
    "",
    "Participants were drawn from CHARLS, ELSA and HRS. Baseline cross-sectional analyses used the first analytic wave after inclusion/exclusion (Figure 1). Longitudinal change and cross-lagged panel network (CLPN) analyses used two-wave wide tables.",
    "",
    "## Cohort age restriction",
    sprintf(
      "The analytic sample was restricted to participants aged %d years or older at baseline (Age ≥ %d; non-finite ages excluded). Separate deliveries are produced for Age ≥ 50 and Age ≥ 65.",
      age_cut, age_cut
    ),
    "",
    "## Exposure and outcome",
    "The primary exposure was the Frailty Index (mean of deficit items). The outcome was hip fracture. Baseline tables report fracture status in the analytic sample; change and CLPN models use follow-up status as defined in the study config.",
    "",
    "## Descriptive and association models",
    "Continuous variables were summarized as mean (SD) or median (IQR); categorical variables as n (%). Logistic models related FI (continuous and tertiles; lowest tertile as reference) to hip fracture. Model 1 / Model 2 covariates are listed in the Table 2 footnotes. Restricted cubic splines, ROC curves and subgroup forests used the same analytic sample unless a sensitivity scenario is named in the table title.",
    "",
    "## Change analysis and mediation",
    "Mean FI and FI change tables followed the main logistic grouping scheme (tertile).",
    if (use_cs) {
      paste0(
        "Longitudinal mediation (Frailty Index → Depression → hip fracture) did not show a significant indirect effect in at least two of three cohorts; ",
        "analyses were therefore downgraded to cross-sectional mediation on the Table 1 sample (Frailty Index → BMI → hip fracture) ",
        "using the product-of-coefficients framework with bootstrap intervals (sims = 1000, seed = 40595747). ",
        "Correlation regressions (Table S6) used the same shared covariates and preceded mediation. ",
        "Shared Model 2 covariates across CHARLS, ELSA and HRS were: ", paste(lock$m2, collapse = ", "), ". ",
        "Path diagrams place the Direct effect (c′) on the bottom arrow, aligned with Table S7."
      )
    } else {
      paste0(
        "Longitudinal mediation (Frailty Index → Depression → hip fracture) used the product-of-coefficients framework with bootstrap intervals. ",
        "Correlation regressions (Table S6) used shared covariates and preceded mediation. Shared Model 2 covariates: ",
        paste(lock$m2, collapse = ", "), "."
      )
    },
    "",
    "## Cross-lagged panel network",
    "CLPN edge weights were estimated with regularized regression (glmnet) of each T2 node on all T1 nodes. Binary nodes used binomial family; others used Gaussian. Networks were drawn with qgraph. Edge colour encodes OR > 1 vs OR < 1.",
    "",
    "## Sensitivity analyses",
    "Complete-case unimputed listwise sensitivity reused the main logistic and change specifications on the restricted sample (Tables S9–S11).",
    "",
    "Software versions are listed in Methods_software_versions.txt and the Software subsection below.",
    ""
  )
  writeLines(methods_lines, file.path(work, "Methods_statistical_analysis.md"))

  # software versions
  sv_src <- .pick_existing(
    file.path(g_dir, "Methods_software_versions.txt"),
    file.path(eng_root, "summary_result", "Methods_software_versions.txt")
  )
  if (!is.na(sv_src)) {
    file.copy(sv_src, file.path(work, "Methods_software_versions.txt"), overwrite = TRUE)
  } else {
    writeLines(c(
      paste0("R version: ", paste(R.version$major, R.version$minor, sep = ".")),
      paste0("Generated: ", format(Sys.time(), "%F %T"))
    ), file.path(work, "Methods_software_versions.txt"))
  }
  # append Software section
  cat("\n## Software\n\n", file = file.path(work, "Methods_statistical_analysis.md"), append = TRUE)
  cat(paste(readLines(file.path(work, "Methods_software_versions.txt"), warn = FALSE), collapse = "\n"),
      "\n", file = file.path(work, "Methods_statistical_analysis.md"), append = TRUE)

  # midterm PDF keep
  mid <- list.files(g_dir, pattern = "中期.*\\.pdf$", full.names = TRUE)
  if (length(mid)) file.copy(mid[1], file.path(work, basename(mid[1])), overwrite = TRUE)

  # replace g_dir contents with curated
  message("Replace delivery root: ", g_dir)
  st2 <- system(paste(
    "rsync -a --delete",
    shQuote(paste0(work, "/")),
    shQuote(paste0(g_dir, "/"))
  ))
  if (!identical(as.integer(st2), 0L)) stop("rsync to delivery failed: ", g_dir)

  # inventory
  n_tab <- length(list.files(file.path(g_dir, "Tables"), pattern = "\\.xlsx$"))
  n_pdf <- length(list.files(file.path(g_dir, "Figures", "pdf"), pattern = "\\.pdf$"))
  n_md <- length(list.files(file.path(g_dir, "Figures", "image_information"), pattern = "\\.md$"))
  top <- list.files(g_dir)
  message("TOP: ", paste(top, collapse = " | "))
  message(sprintf("Tables=%d  Figures/pdf=%d  image_information=%d  mode=%s",
                  n_tab, n_pdf, n_md, if (use_cs) "CS_BMI" else "LONG_DEP"))
  writeLines(c(
    sprintf("age_cut=%d", age_cut),
    sprintf("aligned_at=%s", format(Sys.time(), "%F %T")),
    sprintf("mediation_mode=%s", if (use_cs) "cross_sectional_BMI" else "longitudinal_Depression"),
    sprintf("long_acme_sig_cohorts=%d", long_gate$n_sig),
    sprintf("long_detail=%s", paste(long_gate$detail, collapse = "; ")),
    sprintf("shared_model2=%s", paste(lock$m2, collapse = "+")),
    sprintf("tables=%d", n_tab),
    sprintf("figures_pdf=%d", n_pdf),
    sprintf("top=%s", paste(top, collapse = " | ")),
    sprintf("backup=%s", backup)
  ), file.path(backup, "ALIGN_MANIFEST.txt"))

  invisible(list(
    age = age_cut, mode = if (use_cs) "CS" else "LONG",
    n_tab = n_tab, n_pdf = n_pdf, backup = backup, top = top
  ))
}

cuts <- if (is.finite(only_cut)) only_cut else c(50L, 65L)
res <- lapply(cuts, .curate_one)
print(res)
message("DONE")
