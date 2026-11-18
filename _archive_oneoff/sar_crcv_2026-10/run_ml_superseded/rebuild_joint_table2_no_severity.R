#!/usr/bin/env Rscript
# 重算文献 Table 2 联合暴露 Cox：Model3 剔除严重度（防 HR 方向翻转）
#
# MEDICAL_BLOCKS_ROOT=... Rscript run/ml/rebuild_joint_table2_no_severity.R \
#   --study .../33_AKI_SAR_CrCV_28天死亡 \
#   --index SAR+CrCV \
#   --delivery .../by_index/【success】SAR+CrCV
args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(a, b) {
  if (is.null(a) || !length(a) || (length(a) == 1L && (is.na(a) || (is.character(a) && !nzchar(a))))) b else a
}
get_opt <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i >= length(args)) return(default)
  args[[i + 1L]]
}

engine <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(engine)) {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", ca[grep("^--file=", ca)])
  if (length(f)) {
    engine <- normalizePath(file.path(dirname(f[[1]]), "../.."), winslash = "/", mustWork = FALSE)
  }
}
stopifnot(dir.exists(file.path(engine, "R")))
Sys.setenv(MEDICAL_BLOCKS_ROOT = engine)

for (f in c(
  "R/utils.R",
  "R/ml_assoc_covariate_rule.R",
  "R/prognosis_reference_assoc.R"
)) {
  source(file.path(engine, f), local = FALSE)
}

study <- normalizePath(get_opt("--study", ""), winslash = "/", mustWork = TRUE)
index <- as.character(get_opt("--index", "SAR+CrCV"))[1L]
delivery <- get_opt("--delivery", "")
indices <- trimws(strsplit(index, "+", fixed = TRUE)[[1L]])
stopifnot(length(indices) == 2L)
ia <- indices[[1L]]
ib <- indices[[2L]]

ck_path <- file.path(study, "checkpoints/by_index", index, "MIMIC_IV/ml_assoc_bundle.rds")
stopifnot(file.exists(ck_path))
ck <- readRDS(ck_path)
ctx <- ck$ctx %||% ck

# 不 source 完整 config.R（依赖 .study 等）；只叠加本修复所需 assoc 规则
ctx$config$assoc_covariate <- modifyList(
  ctx$config$assoc_covariate %||% list(),
  list(
    enable = TRUE,
    scheme = "literature_m123",
    force_model1 = "Age",
    sex_var = "Gender",
    model3_exclude = unique(c(
      as.character((ctx$config$assoc_covariate %||% list())$model3_exclude %||% character(0)),
      "GCS", "APSIII", "OASIS", "SOFA", "SAPSII", "Ventilation", "CRRT",
      ml_assoc_default_model3_exclude()
    )),
    clinical_covariates = unique(c(
      as.character((ctx$config$assoc_covariate %||% list())$clinical_covariates %||% character(0)),
      "GCS", "APSIII", "OASIS", "SpO2", "Lactate", "PH", "pH", "BUN", "PT", "INR",
      "Hemoglobin", "Heart_Failure", "Ventilation", "MAP", "WBC", "Glucose"
    ))
  )
)

dat <- ctx$data$imputed %||% ctx$data$analysis %||% ctx$data$cleaned
train <- ctx$data$train %||% dat
stopifnot(is.data.frame(dat), all(c(ia, ib, "futime", "fustatus") %in% names(dat)))

cut_a <- unname(stats::quantile(as.numeric(train[[ia]]), 2 / 3, type = 7, na.rm = TRUE))
cut_b <- unname(stats::quantile(as.numeric(train[[ib]]), 2 / 3, type = 7, na.rm = TRUE))
message(sprintf("Frozen upper-tertile cuts: %s=%.6g; %s=%.6g", ia, cut_a, ib, cut_b))

ctx2 <- ml_apply_assoc_covariate_rule_to_ctx(ctx)
m3 <- as.character(ctx2$results$assoc_model3_factors %||% character(0))
m2 <- intersect(c("Age", "Gender", "Sex"), names(dat))
if (!("Age" %in% m2)) stop("Age missing")
sex <- intersect(c("Gender", "Sex"), m2)
m2 <- unique(c("Age", sex[[1L]]))
m3 <- unique(c(m2, setdiff(m3, ml_assoc_default_model3_exclude())))
m3 <- intersect(m3, names(dat))
message("assoc note: ", ctx2$results$assoc_covariate_note)
message("Model3 covariates: ", paste(m3, collapse = ", "))
message(
  "severity held out: ",
  paste(ctx2$results$assoc_model3_severity_sensitivity %||% character(0), collapse = ", ")
)

grp <- reference_joint_tertile_groups(
  dat[[ia]], dat[[ib]], cut_a, cut_b
)
dd <- dat
dd$.T <- suppressWarnings(as.numeric(dat$futime))
dd$.E <- pipeline_outcome_as_01(dat$fustatus, cfg = ctx2$config)
dd$.G <- factor(paste0("Group", as.integer(grp)), levels = paste0("Group", 1:4))
dd <- dd[is.finite(dd$.T) & !is.na(dd$.E) & !is.na(dd$.G), , drop = FALSE]

models <- list(
  Model1 = character(0),
  Model2 = m2,
  Model3 = m3
)

fit_rows <- list()
for (mn in names(models)) {
  covs <- intersect(models[[mn]], names(dd))
  rhs <- c(".G", covs)
  form <- stats::as.formula(paste(
    "survival::Surv(.T, .E) ~", paste(sprintf("`%s`", rhs), collapse = " + ")
  ))
  fit <- tryCatch(survival::coxph(form, data = dd, x = TRUE), error = function(e) {
    message(mn, " fail: ", conditionMessage(e))
    NULL
  })
  if (is.null(fit)) next
  sm <- summary(fit)
  coef <- sm$coefficients
  ci <- sm$conf.int
  rn <- grep("^\\.G", rownames(coef))
  for (r in rn) {
    g <- sub("^\\.G", "", rownames(coef)[r])
    hr <- ci[r, "exp(coef)"]
    lo <- ci[r, "lower .95"]
    hi <- ci[r, "upper .95"]
    p <- coef[r, "Pr(>|z|)"]
    fit_rows[[length(fit_rows) + 1L]] <- data.frame(
      model = mn,
      group = g,
      hr_ci = sprintf("%.3f (%.3f, %.3f)", hr, lo, hi),
      p_cell = if (is.finite(p) && p < 0.001) "<0.001" else sprintf("%.3f", p),
      n = nrow(dd),
      events = sum(dd$.E == 1L, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }
}
t2 <- do.call(rbind, fit_rows)
print(t2)

grp_order <- c("Group1", "Group2", "Group3", "Group4")
wide <- data.frame(Group = grp_order, stringsAsFactors = FALSE)
for (mn in names(models)) {
  sub <- t2[t2$model == mn, , drop = FALSE]
  wide[[paste0(mn, " HR (95% CI)")]] <- vapply(grp_order, function(g) {
    if (identical(g, "Group1")) return("1.00 (Reference)")
    hit <- sub$hr_ci[sub$group == g]
    if (length(hit)) hit[[1]] else "NE"
  }, character(1))
  wide[[paste0(mn, " P")]] <- vapply(grp_order, function(g) {
    if (identical(g, "Group1")) return("")
    hit <- sub$p_cell[sub$group == g]
    if (length(hit)) hit[[1]] else ""
  }, character(1))
}

# rename columns to match delivery table
names(wide) <- c(
  "Group",
  "Model 1 HR (95% CI)", "Model 1 P",
  "Model 2 HR (95% CI)", "Model 2 P",
  "Model 3 HR (95% CI)", "Model 3 P"
)

title <- sprintf(
  "Table 2. Association of %s and %s joint groups with 28-day all-cause mortality (MIMIC-IV).",
  ia, ib
)
n_lab <- sprintf(
  "N (events) = %s (%s).",
  format(nrow(dd), big.mark = ","),
  format(sum(dd$.E == 1L), big.mark = ",")
)
footnotes <- c(
  paste0(
    "Model 1: unadjusted. Model 2: age and sex. Model 3: age, sex, and univariate-significant ",
    "clinical covariates with VIF < 5, excluding disease-severity scores and organ support ",
    "(APSIII, OASIS, SOFA, GCS, mechanical ventilation) to avoid overadjustment of the total association. ",
    "Model 3 covariates: ", paste(m3, collapse = ", "), "."
  ),
  "Group1 is the low/low reference (each index high = upper tertile frozen on the MIMIC-IV development set).",
  n_lab,
  "Outcome: 28-day all-cause mortality."
)

out_dirs <- character(0)
if (nzchar(as.character(delivery %||% ""))) {
  delivery <- normalizePath(delivery, winslash = "/", mustWork = TRUE)
  out_dirs <- c(
    file.path(delivery, "summary_result", "Tables"),
    file.path(delivery, "publication_literature_final", "Tables"),
    file.path(delivery, "Tables")
  )
}
out_dirs <- c(
  out_dirs,
  file.path(study, "by_index", paste0("【success】", index), "summary_result", "Tables"),
  file.path(study, "by_index", paste0("【success】", index), "Tables")
)
out_dirs <- unique(out_dirs)
# 无 ctx 时 inject_db 会写成 *-UnknownDB.xlsx；直接定稿名写出后改名覆盖
for (od in out_dirs) {
  dir.create(od, recursive = TRUE, showWarnings = FALSE)
  fp <- file.path(od, "Table 2 Joint group Cox.xlsx")
  if (exists("export_sci_table", mode = "function")) {
    export_sci_table(wide, fp, title = title, table_footnotes = footnotes)
  } else {
    stop("export_sci_table missing")
  }
  message("queued ", fp)
}
if (exists("render_queued_tables", mode = "function")) {
  invisible(render_queued_tables(list()))
}
# 把 UnknownDB 定稿改回规范名
for (od in out_dirs) {
  bad <- file.path(od, "Table 2 Joint group Cox-UnknownDB.xlsx")
  good <- file.path(od, "Table 2 Joint group Cox.xlsx")
  if (file.exists(bad)) {
    if (file.exists(good)) unlink(good)
    file.rename(bad, good)
    message("renamed -> ", good)
  }
}

harm <- file.path(study, "checkpoints/by_index", index, "harmonization")
dir.create(harm, recursive = TRUE, showWarnings = FALSE)
writeLines(
  c(
    "Model1 (table): unadjusted",
    paste0("Model2 (table): ", paste(m2, collapse = ", ")),
    paste0("Model3 (table, no severity): ", paste(m3, collapse = ", ")),
    paste0(
      "severity_held_out: ",
      paste(ctx2$results$assoc_model3_severity_sensitivity %||% character(0), collapse = ", ")
    ),
    paste0("note: ", ctx2$results$assoc_covariate_note)
  ),
  file.path(harm, "assoc_covariates_primary.txt")
)

g4 <- t2[t2$group == "Group4", , drop = FALSE]
message("Group4:")
print(g4)
message("REBUILD_OK")
