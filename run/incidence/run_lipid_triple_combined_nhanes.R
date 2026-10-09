#!/usr/bin/env Rscript
# =============================================================================
#  run_lipid_triple_combined_nhanes.R
#  HDL + LDL + VLDL：完整病例、统一协变量、强制 quartile 加权 logistic + RCS
#  产出：一张合并 Table 2 + 一张 1×3 RCS 图（四目录）
#
#  用法（引擎根）:
#    MEDICAL_BLOCKS_ROOT=/mnt/e/01block/01Block-new-Final \
#      Rscript run/incidence/run_lipid_triple_combined_nhanes.R --dataset both
#    Rscript ... --dataset Data
#    Rscript ... --dataset cindychen
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
opts <- list(dataset = "both")
i <- 1L
while (i <= length(args)) {
  a <- args[[i]]
  if (a == "--dataset" && i < length(args)) {
    opts$dataset <- tolower(trimws(args[[i + 1L]]))
    i <- i + 2L
  } else {
    i <- i + 1L
  }
}

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || (length(x) == 1L && is.na(x))) y else x

.root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(.root) || !dir.exists(.root)) {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    .root <- normalizePath(file.path(dirname(sub("^--file=", "", f[1L])), "../.."), winslash = "/")
  } else {
    .root <- normalizePath(getwd(), winslash = "/")
  }
}
Sys.setenv(MEDICAL_BLOCKS_ROOT = .root)

.source_engine <- function() {
  for (rel in c(
    "R/utils.R",
    "R/nhanes_survey_weight.R",
    "R/pub_figure_export.R",
    "Blocks/12_obj/01block_obj.R",
    "Blocks/11_logistic/00logistic_nhanes_weighted_common.R",
    "Blocks/11_logistic/13block_logistic_quartile_nhanes_weighted.R",
    "Blocks/15_rcs/03block_rcs_nhanes.R"
  )) {
    p <- file.path(.root, rel)
    if (file.exists(p)) source(p, local = FALSE)
  }
}
.source_engine()

.study_root <- normalizePath(
  "/mnt/g/02block_result/07_Diabetic retinopathy/incidence_38341157",
  winslash = "/", mustWork = TRUE
)

.disease_vars <- c(
  "T1DM", "T2DM", "Diabetes", "HbA1c", "Glucose", "Insulin",
  "Antidiabetic_agents", "Albumin_Urine", "AlbuminUrine", "UACR"
)
.lipid_ban <- c("HDL", "LDL", "VLDL", "TG", "Triglycerides", "TC", "Total_Cholesterol")

.datasets <- list(
  Data = list(
    label = "Data",
    raw_path = file.path(.study_root, "Data/nhanes/D04_dabiao_DR.RData"),
    raw_obj = "dabiao",
    out_subdir = "by_index",
    prep_dir = file.path(.study_root, "Data/nhanes"),
    id_col = "ID"
  ),
  cindychen = list(
    label = "cindychen",
    raw_path = file.path(.study_root, "data(cindychen)/D04_dabiao_0904.RData"),
    raw_obj = "dabiao_new",
    out_subdir = "by_index(cindychen)",
    prep_dir = file.path(.study_root, "data(cindychen)"),
    id_col = "SEQN"
  )
)

.prep_complete_case <- function(ds) {
  e <- new.env(parent = emptyenv())
  load(ds$raw_path, envir = e)
  d <- e[[ds$raw_obj]]
  stopifnot(is.data.frame(d))
  n0 <- nrow(d)

  if (!"Triglycerides" %in% names(d) && "TG" %in% names(d)) d$Triglycerides <- d$TG
  if (!"Total_Cholesterol" %in% names(d) && "TC" %in% names(d)) d$Total_Cholesterol <- d$TC
  if (!"Monocyte" %in% names(d) && "Mononuclear_cell_count" %in% names(d)) {
    d$Monocyte <- d$Mononuclear_cell_count
  }
  if (!"Smoking" %in% names(d) && "Smoke" %in% names(d)) d$Smoking <- d$Smoke
  if (!"TG" %in% names(d) && "Triglycerides" %in% names(d)) d$TG <- d$Triglycerides

  d$HDL <- suppressWarnings(as.numeric(d$HDL))
  d$LDL <- suppressWarnings(as.numeric(d$LDL))
  d$TG <- suppressWarnings(as.numeric(d$TG))
  d$VLDL <- round(d$TG / 5, 2)

  ok <- stats::complete.cases(d[, c("HDL", "LDL", "VLDL", "Disease_Group")])
  d2 <- d[ok, , drop = FALSE]
  n1 <- nrow(d2)

  # new_Weight via engine helper (HDL non-fasting → WTMEC)
  cfg_stub <- list(
    project = list(root = .root, database_type = "NHANES"),
    nhanes = list(
      survey_weight = "new_Weight", auto_new_weight = TRUE,
      cutoff_index_var = "HDL", recompute_new_weight = TRUE
    ),
    incidence = list(index_var = "HDL")
  )
  if (exists("compute_nhanes_new_weight", mode = "function")) {
    d2 <- compute_nhanes_new_weight(
      d2, target_var = "HDL", wt_col = "new_Weight", recompute = TRUE
    )
  } else if (exists(".block_obj_apply_new_weight", mode = "function")) {
    d2 <- .block_obj_apply_new_weight(d2, cfg_stub, .root)
  } else {
    # fallback: WTMEC4YR preferred then × cycle count
    w <- if ("WTMEC4YR" %in% names(d2)) d2$WTMEC4YR else d2$WTMEC2YR
    n_cyc <- if ("Source_File" %in% names(d2)) length(unique(stats::na.omit(d2$Source_File))) else 1L
    d2$new_Weight <- suppressWarnings(as.numeric(w)) / max(1L, n_cyc)
  }
  w_ok <- is.finite(d2$new_Weight) & d2$new_Weight > 0
  d2 <- d2[w_ok, , drop = FALSE]
  n2 <- nrow(d2)

  # binary outcome 0/1
  dg <- d2$Disease_Group
  if (is.factor(dg)) dg <- as.character(dg)
  d2$Disease_Group <- as.integer(as.character(dg) %in% c("1", "Yes", "DR", "Diabetic retinopathy"))

  out_path <- file.path(ds$prep_dir, "D04_dabiao_lipid_triple_cc.RData")
  dabiao_lipid_triple_cc <- d2
  save(dabiao_lipid_triple_cc, file = out_path)

  attrition <- data.frame(
    step = c("raw", "complete_HDL_LDL_VLDL_outcome", "positive_new_Weight"),
    n = c(n0, n1, n2),
    stringsAsFactors = FALSE
  )
  write.csv(
    attrition,
    file.path(ds$prep_dir, "lipid_triple_complete_case_attrition.csv"),
    row.names = FALSE
  )
  list(data = d2, attrition = attrition, path = out_path, n = n2)
}

.lock_covariates <- function(d) {
  # Force Age; add common demos if present; labs from prior HDL Data/cindychen runs
  # Exclude lipids / disease
  ban <- unique(c(.lipid_ban, .disease_vars, "Disease_Group", "Disease",
                  "SEQN", "ID", "new_Weight", "Source_File",
                  "SDMVPSU", "SDMVSTRA",
                  grep("^WT", names(d), value = TRUE)))
  demos <- intersect(c("Age", "Gender", "PIR", "Education", "Race", "Marital_Status"), names(d))
  labs <- intersect(
    c("LD", "Monocyte", "BUN", "Creatinine", "AST", "ALT", "Albumin",
      "BilirubinTotal", "Bilirubin_Total", "UricAcid", "Uric_Acid",
      "Mean_platelet_volume", "WBC", "RBC", "Hemoglobin"),
    names(d)
  )
  # Prefer prior successful HDL locks when columns exist
  m1 <- intersect(c("Age", "PIR", "Education"), names(d))
  if (!"Age" %in% m1 && "Age" %in% names(d)) m1 <- c("Age", m1)
  m2_extra <- intersect(c("LD", "Monocyte"), names(d))
  m2 <- unique(c(m1, m2_extra))
  m1 <- setdiff(m1, ban)
  m2 <- setdiff(m2, ban)
  # Drop covars with >30% missing in CC sample
  miss_ok <- function(v) mean(is.na(d[[v]])) <= 0.30
  m1 <- m1[vapply(m1, miss_ok, logical(1))]
  m2 <- m2[vapply(m2, miss_ok, logical(1))]
  if (!length(m1)) m1 <- intersect("Age", names(d))
  if (!length(m2)) m2 <- m1
  list(model1 = m1, model2 = m2, demos = demos, labs = labs)
}

.make_design <- function(d) {
  need <- c("new_Weight", "SDMVPSU", "SDMVSTRA", "Disease_Group")
  stopifnot(all(need %in% names(d)))
  survey::svydesign(
    ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~new_Weight,
    nest = TRUE, data = d
  )
}

.fit_row <- function(design, fml) {
  fit <- tryCatch(
    survey::svyglm(stats::as.formula(fml), design = design, family = quasibinomial()),
    error = function(e) NULL
  )
  if (is.null(fit)) return(list(OR = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_))
  cf <- summary(fit)$coefficients
  # last exposure coef (skip intercept)
  rn <- rownames(cf)
  hit <- rn[rn != "(Intercept)"][1L]
  if (is.na(hit) || is.null(hit)) {
    return(list(OR = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_))
  }
  b <- cf[hit, "Estimate"]
  se <- cf[hit, "Std. Error"]
  p <- cf[hit, grep("Pr", colnames(cf))[1L]]
  list(
    OR = exp(b), lo = exp(b - 1.96 * se), hi = exp(b + 1.96 * se),
    p = as.numeric(p)
  )
}

.fmt_or <- function(x) {
  if (is.null(x) || !is.finite(x$OR)) return(list(or = "NA", ci = "NA", p = "NA"))
  list(
    or = sprintf("%.2f", x$OR),
    ci = sprintf("(%.2f,%.2f)", x$lo, x$hi),
    p = if (!is.finite(x$p)) "NA" else if (x$p < 0.001) "<0.001" else sprintf("%.3f", x$p)
  )
}

.build_quartile_design <- function(design, index_var) {
  if (exists(".lqq09_apply_quartile", mode = "function")) {
    return(.lqq09_apply_quartile(design, index_var))
  }
  xv <- design$variables[[index_var]]
  qs <- as.numeric(stats::quantile(xv, c(0.25, 0.5, 0.75), na.rm = TRUE))
  grp <- cut(xv, breaks = c(-Inf, qs[1], qs[2], qs[3], Inf),
             labels = c("Q1", "Q2", "Q3", "Q4"), right = FALSE, include.lowest = TRUE)
  levels(grp) <- c("Q1", "Q2", "Q3", "Q4")
  cutoffs <- c(
    Q1 = paste0("< ", round(qs[1], 2)),
    Q2 = paste0(round(qs[1], 2), " -< ", round(qs[2], 2)),
    Q3 = paste0(round(qs[2], 2), " -< ", round(qs[3], 2)),
    Q4 = paste0("\u2265 ", round(qs[3], 2))
  )
  list(
    design = stats::update(design, Group = factor(grp, levels = c("Q1", "Q2", "Q3", "Q4"))),
    raw_levels = c("Q1", "Q2", "Q3", "Q4"),
    cutoffs = cutoffs
  )
}

.events_cell <- function(des, level) {
  vv <- des$variables
  sub <- vv$Group == level & !is.na(vv$Group)
  n <- sum(sub, na.rm = TRUE)
  ev <- sum(sub & vv$Disease_Group == 1L, na.rm = TRUE)
  sprintf("%d/%d (%.2f%%)", ev, n, if (n > 0) 100 * ev / n else NA_real_)
}

.logistic_block_for_index <- function(design, index_var, M1, M2) {
  # continuous
  .subset_design <- function(des, vars) {
    vv <- des$variables
    keep <- rep(TRUE, nrow(vv))
    for (v in unique(vars)) {
      if (!v %in% names(vv)) next
      if (is.numeric(vv[[v]])) keep <- keep & is.finite(vv[[v]])
      else keep <- keep & !is.na(vv[[v]])
    }
    survey::svydesign(
      ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~new_Weight,
      nest = TRUE, data = vv[keep, , drop = FALSE]
    )
  }
  cont_rows <- list()
  for (tag in c("crude", "m1", "m2")) {
    cov <- switch(tag, crude = character(0), m1 = M1, m2 = M2)
    des_i <- .subset_design(design, c(index_var, cov, "Disease_Group", "SDMVPSU", "SDMVSTRA", "new_Weight"))
    rhs <- if (length(cov)) paste(c(index_var, cov), collapse = "+") else index_var
    cont_rows[[tag]] <- .fit_row(des_i, paste0("Disease_Group ~ ", rhs))
  }

  grp <- .build_quartile_design(design, index_var)
  des_g <- grp$design
  # complete cases for group + covars m2
  vv <- des_g$variables
  keep <- !is.na(vv$Group) & is.finite(vv[[index_var]])
  for (v in unique(c(M1, M2))) {
    if (!v %in% names(vv)) next
    if (is.numeric(vv[[v]])) keep <- keep & is.finite(vv[[v]]) else keep <- keep & !is.na(vv[[v]])
  }
  des_g$variables <- vv[keep, , drop = FALSE]
  des_g <- survey::svydesign(
    ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~new_Weight,
    nest = TRUE, data = des_g$variables
  )

  q_rows <- list()
  for (lv in c("Q2", "Q3", "Q4")) {
    q_rows[[lv]] <- list()
    for (tag in c("crude", "m1", "m2")) {
      cov <- switch(tag, crude = character(0), m1 = M1, m2 = M2)
      # contrast vs Q1: use relevel
      dd <- des_g$variables
      dd$Group <- stats::relevel(dd$Group, ref = "Q1")
      des_q <- survey::svydesign(
        ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~new_Weight,
        nest = TRUE, data = dd
      )
      rhs <- if (length(cov)) paste(c("Group", cov), collapse = "+") else "Group"
      fit <- tryCatch(
        survey::svyglm(stats::as.formula(paste0("Disease_Group ~ ", rhs)),
                       design = des_q, family = quasibinomial()),
        error = function(e) NULL
      )
      if (is.null(fit)) {
        q_rows[[lv]][[tag]] <- list(OR = NA, lo = NA, hi = NA, p = NA)
      } else {
        cf <- summary(fit)$coefficients
        nm <- paste0("Group", lv)
        if (!nm %in% rownames(cf)) nm <- grep(paste0("Group.*", lv), rownames(cf), value = TRUE)[1L]
        if (is.na(nm) || !nzchar(nm)) {
          q_rows[[lv]][[tag]] <- list(OR = NA, lo = NA, hi = NA, p = NA)
        } else {
          b <- cf[nm, "Estimate"]; se <- cf[nm, "Std. Error"]
          p <- cf[nm, grep("Pr", colnames(cf))[1L]]
          q_rows[[lv]][[tag]] <- list(OR = exp(b), lo = exp(b - 1.96 * se), hi = exp(b + 1.96 * se), p = as.numeric(p))
        }
      }
    }
  }

  # p for trend via Num
  trend <- list()
  dd <- des_g$variables
  dd$Num <- as.numeric(dd$Group)
  des_t <- survey::svydesign(
    ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~new_Weight,
    nest = TRUE, data = dd
  )
  for (tag in c("crude", "m1", "m2")) {
    cov <- switch(tag, crude = character(0), m1 = M1, m2 = M2)
    rhs <- if (length(cov)) paste(c("Num", cov), collapse = "+") else "Num"
    fit <- tryCatch(
      survey::svyglm(stats::as.formula(paste0("Disease_Group ~ ", rhs)),
                     design = des_t, family = quasibinomial()),
      error = function(e) NULL
    )
    if (is.null(fit)) {
      trend[[tag]] <- NA_real_
    } else {
      cf <- summary(fit)$coefficients
      trend[[tag]] <- if ("Num" %in% rownames(cf)) cf["Num", grep("Pr", colnames(cf))[1L]] else NA_real_
    }
  }

  list(
    index = index_var,
    cutoffs = grp$cutoffs,
    continuous = cont_rows,
    groups = q_rows,
    trend = trend,
    design_g = des_g,
    events = sapply(c("Q1", "Q2", "Q3", "Q4"), function(lv) .events_cell(des_g, lv), USE.NAMES = TRUE)
  )
}

.rcs_curve <- function(design, index_var, covs) {
  if (!requireNamespace("Hmisc", quietly = TRUE)) return(NULL)
  xv <- design$variables[[index_var]]
  knots <- as.numeric(stats::quantile(xv, c(0.1, 0.5, 0.9), na.rm = TRUE))
  if (length(unique(knots)) < 3L) return(NULL)
  basis <- Hmisc::rcspline.eval(xv, knots = knots, inclx = TRUE)
  bn <- paste0("rcs_b", seq_len(ncol(basis)))
  colnames(basis) <- bn
  tmp <- design$variables
  for (j in seq_len(ncol(basis))) tmp[[bn[j]]] <- basis[, j]
  # complete
  keep <- rep(TRUE, nrow(tmp))
  for (v in c(bn, covs)) {
    if (!v %in% names(tmp)) next
    if (is.numeric(tmp[[v]])) keep <- keep & is.finite(tmp[[v]]) else keep <- keep & !is.na(tmp[[v]])
  }
  tmp <- tmp[keep, , drop = FALSE]
  des <- survey::svydesign(
    ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~new_Weight,
    nest = TRUE, data = tmp
  )
  fml <- paste0("Disease_Group ~ ", paste(bn, collapse = "+"),
                if (length(covs)) paste0(" + ", paste(covs, collapse = "+")) else "")
  fit <- tryCatch(
    survey::svyglm(stats::as.formula(fml), design = des, family = quasibinomial()),
    error = function(e) NULL
  )
  if (is.null(fit)) return(NULL)
  p_ov <- tryCatch(survey::regTermTest(fit, bn)$p, error = function(e) NA_real_)
  p_nl <- tryCatch(
    if (length(bn) > 1) survey::regTermTest(fit, bn[-1])$p else NA_real_,
    error = function(e) NA_real_
  )
  x_rng <- seq(min(xv, na.rm = TRUE), max(xv, na.rm = TRUE), length.out = 200)
  pb <- Hmisc::rcspline.eval(x_rng, knots = knots, inclx = TRUE)
  colnames(pb) <- bn
  pred_df <- data.frame(setNames(list(x_rng), index_var))
  pred_df <- cbind(pred_df, as.data.frame(pb))
  for (v in covs) {
    vd <- des$variables[[v]]
    if (is.numeric(vd)) pred_df[[v]] <- mean(vd, na.rm = TRUE)
    else {
      xf <- if (is.factor(vd)) vd else factor(vd)
      pred_df[[v]] <- factor(rep(levels(xf)[1L], nrow(pred_df)), levels = levels(xf))
    }
  }
  ref_x <- stats::median(xv, na.rm = TRUE)
  ref_b <- Hmisc::rcspline.eval(ref_x, knots = knots, inclx = TRUE)
  ref_row <- pred_df[1, , drop = FALSE]
  ref_row[[index_var]] <- ref_x
  ref_row[, bn] <- as.numeric(ref_b)
  for (v in covs) ref_row[[v]] <- pred_df[[v]][1]
  newdat <- rbind(ref_row, pred_df)
  pr <- tryCatch(predict(fit, newdata = newdat, type = "link", se.fit = TRUE), error = function(e) NULL)
  if (is.null(pr)) return(NULL)
  lv <- as.numeric(pr)
  sv <- as.numeric(survey::SE(pr))
  rl <- lv[-1] - lv[1]
  list(
    df = data.frame(
      x = x_rng,
      yhat = exp(rl),
      lower = exp(rl - 1.96 * sv[-1]),
      upper = exp(rl + 1.96 * sv[-1])
    ),
    p_overall = as.numeric(p_ov),
    p_nonlin = as.numeric(p_nl),
    knots = knots,
    cutoff = ref_x
  )
}

.plot_rcs_panel <- function(rcs, title, letter) {
  stopifnot(requireNamespace("ggplot2", quietly = TRUE))
  df <- rcs$df
  p_ov <- if (is.finite(rcs$p_overall)) {
    if (rcs$p_overall < 0.001) "P-overall < 0.001" else sprintf("P-overall = %.3f", rcs$p_overall)
  } else "P-overall = NA"
  p_nl <- if (is.finite(rcs$p_nonlin)) {
    if (rcs$p_nonlin < 0.001) "P-non-linear < 0.001" else sprintf("P-non-linear = %.3f", rcs$p_nonlin)
  } else "P-non-linear = NA"
  ann <- paste(p_ov, p_nl, sep = "\n")
  ggplot2::ggplot(df, ggplot2::aes(x = x, y = yhat)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = lower, ymax = upper), fill = "#b0d5df", alpha = 0.5) +
    ggplot2::geom_line(color = "#FF9999", linewidth = 0.9) +
    ggplot2::geom_hline(yintercept = 1, linetype = 2, color = "grey40") +
    ggplot2::geom_vline(xintercept = rcs$cutoff, linetype = 3, color = "grey30") +
    ggplot2::annotate("text", x = Inf, y = Inf, label = ann, hjust = 1.05, vjust = 1.2, size = 3) +
    ggplot2::labs(title = paste0(letter, ". ", title), x = title, y = "OR") +
    ggplot2::theme_classic(base_size = 11) +
    ggplot2::theme(plot.title = ggplot2::element_text(face = "bold"))
}

.write_combined_table <- function(blocks, M1, M2, n, out_xlsx, title) {
  header1 <- c("", "", "", "Crude", "", "", "Model1", "", "", "Model2", "", "")
  header2 <- c("Characteristic", "Exposure cutoff", "Events / N (%)",
               "OR", "95%CI", "P-value", "OR", "95%CI", "P-value", "OR", "95%CI", "P-value")
  body <- list()
  for (bl in blocks) {
    body[[length(body) + 1L]] <- c(bl$index, "", "", "", "", "", "", "", "", "", "", "")
    fc <- .fmt_or(bl$continuous$crude)
    f1 <- .fmt_or(bl$continuous$m1)
    f2 <- .fmt_or(bl$continuous$m2)
    body[[length(body) + 1L]] <- c(
      paste(bl$index, "continuous"), "", "",
      fc$or, fc$ci, fc$p, f1$or, f1$ci, f1$p, f2$or, f2$ci, f2$p
    )
    body[[length(body) + 1L]] <- c(paste(bl$index, "groups"), "", "", "", "", "", "", "", "", "", "", "")
    body[[length(body) + 1L]] <- c(
      "Q1 (Ref)", unname(bl$cutoffs["Q1"]), bl$events[["Q1"]],
      "Ref", "Ref", "", "Ref", "Ref", "", "Ref", "Ref", ""
    )
    for (lv in c("Q2", "Q3", "Q4")) {
      fc <- .fmt_or(bl$groups[[lv]]$crude)
      f1 <- .fmt_or(bl$groups[[lv]]$m1)
      f2 <- .fmt_or(bl$groups[[lv]]$m2)
      body[[length(body) + 1L]] <- c(
        lv, unname(bl$cutoffs[lv]), bl$events[[lv]],
        fc$or, fc$ci, fc$p, f1$or, f1$ci, f1$p, f2$or, f2$ci, f2$p
      )
    }
    tp <- function(p) if (!is.finite(p)) "NA" else if (p < 0.001) "<0.001" else sprintf("%.3f", p)
    body[[length(body) + 1L]] <- c(
      "p for trend", "", "",
      "", "", tp(bl$trend$crude),
      "", "", tp(bl$trend$m1),
      "", "", tp(bl$trend$m2)
    )
  }
  mat <- do.call(rbind, body)
  colnames(mat) <- paste0("V", seq_len(ncol(mat)))
  footnotes <- c(
    sprintf("Complete-case on HDL+LDL+VLDL+outcome; N=%d. VLDL=TG/5 (Friedewald, mg/dL).", n),
    "Grouping=quartile (forced), aligned across three exposures.",
    sprintf("Model1 adjusted for: %s.", paste(M1, collapse = ", ")),
    sprintf("Model2 adjusted for: %s.", paste(M2, collapse = ", ")),
    "Covariates identical for HDL, LDL, and VLDL; lipid exposures/TG excluded from covariate pool."
  )
  if (exists("export_sci_table", mode = "function")) {
    export_sci_table(
      as.data.frame(mat, stringsAsFactors = FALSE),
      out_xlsx,
      title = title,
      header_row1 = header1,
      header_row2 = header2,
      latex_include_colnames = FALSE,
      table_footnotes = footnotes
    )
    if (exists("render_queued_tables", mode = "function")) {
      tryCatch(
        render_queued_tables(list(results = list(), config = list())),
        error = function(e) cli::cli_alert_warning("render_queued_tables: {e$message}")
      )
    }
  }
  # 兜底：若队列未落盘则写 CSV + 简易 xlsx
  if (!file.exists(out_xlsx)) {
    csv <- sub("\\.xlsx$", ".csv", out_xlsx)
    utils::write.csv(
      rbind(header1, header2, mat),
      csv, row.names = FALSE
    )
    if (requireNamespace("openxlsx", quietly = TRUE)) {
      wb <- openxlsx::createWorkbook()
      openxlsx::addWorksheet(wb, "Table")
      openxlsx::writeData(wb, "Table", rbind(header1, header2, mat), colNames = FALSE)
      openxlsx::saveWorkbook(wb, out_xlsx, overwrite = TRUE)
    } else {
      cli::cli_alert_warning("无 openxlsx，已写 CSV: {csv}")
    }
  }
  invisible(out_xlsx)
}

.run_one_dataset <- function(key) {
  ds <- .datasets[[key]]
  cli::cli_h1("lipid triple: {ds$label}")
  prep <- .prep_complete_case(ds)
  d <- prep$data
  cov <- .lock_covariates(d)
  M1 <- cov$model1
  M2 <- cov$model2
  cli::cli_alert_info("N={prep$n}; M1={paste(M1, collapse='+')}; M2={paste(M2, collapse='+')}")

  # save covar lock
  cov_path <- file.path(ds$prep_dir, "lipid_triple_covariates.json")
  jsonlite::write_json(
    list(model1 = M1, model2 = M2, n = prep$n, attrition = prep$attrition),
    cov_path, auto_unbox = TRUE, pretty = TRUE
  )

  out_root <- file.path(.study_root, ds$out_subdir, "【lipid_triple】HDL_LDL_VLDL")
  dir.create(file.path(out_root, "Tables"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(out_root, "Figures"), recursive = TRUE, showWarnings = FALSE)

  design <- .make_design(d)
  indices <- c("HDL", "LDL", "VLDL")
  blocks <- lapply(indices, function(ix) {
    cli::cli_h2("logistic quartile: {ix}")
    .logistic_block_for_index(design, ix, M1, M2)
  })

  title <- sprintf(
    "Table 2-NHANES. Combined weighted logistic of HDL, LDL, VLDL and Diabetic retinopathy (%s)",
    ds$label
  )
  xlsx <- file.path(
    out_root, "Tables",
    "Table 2-NHANES. Combined weighted logistic of HDL LDL VLDL and Diabetic retinopathy.xlsx"
  )
  .write_combined_table(blocks, M1, M2, prep$n, xlsx, title)

  # RCS Model2 panels
  cli::cli_h2("RCS 1x3")
  rcs_list <- lapply(indices, function(ix) {
    cli::cli_alert_info("RCS {ix}")
    .rcs_curve(design, ix, M2)
  })
  panels <- list()
  letters <- c("A", "B", "C")
  for (i in seq_along(indices)) {
    if (is.null(rcs_list[[i]])) {
      panels[[i]] <- ggplot2::ggplot() +
        ggplot2::annotate("text", x = 0.5, y = 0.5, label = paste(indices[i], "RCS failed")) +
        ggplot2::theme_void() +
        ggplot2::labs(title = paste0(letters[i], ". ", indices[i]))
    } else {
      panels[[i]] <- .plot_rcs_panel(rcs_list[[i]], indices[i], letters[i])
    }
  }
  if (requireNamespace("patchwork", quietly = TRUE)) {
    fig <- panels[[1]] + panels[[2]] + panels[[3]] + patchwork::plot_layout(ncol = 3)
  } else {
    fig <- panels[[1]]
  }
  fig_pdf <- file.path(
    out_root, "Figures",
    "Figure 2. RCS of HDL LDL VLDL and Diabetic retinopathy.pdf"
  )
  ggplot2::ggsave(fig_pdf, fig, width = 12, height = 4, device = grDevices::cairo_pdf)

  # four formats
  if (exists("export_pub_figures", mode = "function")) {
    meta <- list(
      exposure = "HDL, LDL, VLDL",
      outcome = "Diabetic retinopathy",
      n = prep$n,
      grouping = "quartile (logistic); RCS continuous",
      databases = ds$label,
      model2 = paste(M2, collapse = "+"),
      note = "Complete-case HDL+LDL+VLDL; VLDL=TG/5"
    )
    # write image_information enrichment via pub helper if available
    tryCatch(
      export_pub_figures(file.path(out_root, "Figures"), meta = meta, purge = TRUE),
      error = function(e) cli::cli_alert_warning("export_pub_figures: {e$message}")
    )
  } else if (exists("pub_figure_ensure_formats", mode = "function")) {
    pub_figure_ensure_formats(file.path(out_root, "Figures"))
  }

  # custom image_information md
  md_dir <- file.path(out_root, "Figures", "image_information")
  dir.create(md_dir, recursive = TRUE, showWarnings = FALSE)
  md <- file.path(md_dir, "Figure 2. RCS of HDL LDL VLDL and Diabetic retinopathy.md")
  lines <- c(
    "# Figure 2. RCS of HDL LDL VLDL and Diabetic retinopathy",
    "",
    "## 图面说明",
    "三面板限制性立方样条（RCS）加权 logistic：A=HDL，B=LDL，C=VLDL。",
    "曲线为 OR（相对暴露中位数），阴影为 95%CI；虚线 OR=1；点线为参照中位数。",
    "各面板标注 P-overall / P-non-linear（来自 svyglm + regTermTest）。",
    "",
    "### 图上标注",
    sprintf("- A HDL: P-overall=%s; P-non-linear=%s; cutoff(median)=%s",
            ifelse(is.null(rcs_list[[1]]), "未收获", format(rcs_list[[1]]$p_overall, digits = 3)),
            ifelse(is.null(rcs_list[[1]]), "未收获", format(rcs_list[[1]]$p_nonlin, digits = 3)),
            ifelse(is.null(rcs_list[[1]]), "未收获", format(rcs_list[[1]]$cutoff, digits = 4))),
    sprintf("- B LDL: P-overall=%s; P-non-linear=%s; cutoff(median)=%s",
            ifelse(is.null(rcs_list[[2]]), "未收获", format(rcs_list[[2]]$p_overall, digits = 3)),
            ifelse(is.null(rcs_list[[2]]), "未收获", format(rcs_list[[2]]$p_nonlin, digits = 3)),
            ifelse(is.null(rcs_list[[2]]), "未收获", format(rcs_list[[2]]$cutoff, digits = 4))),
    sprintf("- C VLDL: P-overall=%s; P-non-linear=%s; cutoff(median)=%s",
            ifelse(is.null(rcs_list[[3]]), "未收获", format(rcs_list[[3]]$p_overall, digits = 3)),
            ifelse(is.null(rcs_list[[3]]), "未收获", format(rcs_list[[3]]$p_nonlin, digits = 3)),
            ifelse(is.null(rcs_list[[3]]), "未收获", format(rcs_list[[3]]$cutoff, digits = 4))),
    "",
    "## 分析上下文",
    sprintf("- 暴露: HDL, LDL, VLDL(=TG/5)"),
    sprintf("- 结局: Diabetic retinopathy (Disease_Group)"),
    sprintf("- 样本量: 完整病例 N=%d（%s）", prep$n, ds$label),
    sprintf("- Grouping: logistic 强制 quartile；RCS 连续"),
    sprintf("- Model2 协变量（三暴露共用）: %s", paste(M2, collapse = ", ")),
    sprintf("- 数据库: NHANES / %s", ds$label),
    "- 拼图: 1×3 三面板"
  )
  writeLines(lines, md)

  # status
  jsonlite::write_json(
    list(
      status = "success",
      dataset = ds$label,
      n = prep$n,
      model1 = M1,
      model2 = M2,
      table = xlsx,
      figure = fig_pdf
    ),
    file.path(out_root, "_lipid_triple_status.json"),
    auto_unbox = TRUE, pretty = TRUE
  )
  cli::cli_alert_success("done {ds$label}: {out_root}")
  invisible(out_root)
}

# ---- main ----
if (!requireNamespace("survey", quietly = TRUE)) stop("需要 survey")
if (!requireNamespace("ggplot2", quietly = TRUE)) stop("需要 ggplot2")
if (!requireNamespace("jsonlite", quietly = TRUE)) stop("需要 jsonlite")
options(survey.lonely.psu = "adjust")

keys <- if (identical(opts$dataset, "both")) c("Data", "cindychen") else {
  if (opts$dataset %in% c("data")) "Data" else opts$dataset
}
keys <- intersect(keys, names(.datasets))
if (!length(keys)) stop("未知 --dataset: ", opts$dataset)

for (k in keys) .run_one_dataset(k)
cli::cli_alert_success("lipid triple combined finished: {paste(keys, collapse=', ')}")
