#!/usr/bin/env Rscript
# 预后套路：S7 相关筛中介 → 双库锁定 best → S8/Fig6；中介不进 Model3

suppressPackageStartupMessages({
  library(data.table)
  library(survival)
  library(ggplot2)
  library(grid)
  library(openxlsx)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.engine <- if (dir.exists("/mnt/e/01block/01Block-new-Final")) {
  "/mnt/e/01block/01Block-new-Final"
} else "E:/01block/01Block-new-Final"
setwd(.engine)
source(file.path(.engine, "run/prognosis_v2/stroke_anlr_env.R"), local = FALSE)
source(file.path(.engine, "R/utils.R"), local = FALSE)
source(file.path(.engine, "R/pv2_pub_names.R"), local = FALSE)
source(file.path(.engine, "R/quantile_scheme_cascade.R"), local = FALSE)
source(file.path(.engine, "R/pv2_literature_pub_tables.R"), local = FALSE)
source(file.path(.engine, "run/prognosis_v2/pv2_mi_cox.R"), local = FALSE)
source(file.path(.engine, "R/pub_figure_export.R"), local = FALSE)
source(file.path(.engine, "Blocks/20_mediation/01block_mediation_prognosis.R"), local = FALSE)

.proj <- stroke_anlr_proj()
.out <- stroke_anlr_out(.proj)
.days <- stroke_anlr_days()
.day_lab <- stroke_anlr_day_lab()
.endpoint <- stroke_anlr_endpoint_phrase()
.tab <- file.path(.out, "Tables")
.fig <- file.path(.out, "Figures", "pdf")
IDX <- "ANLR"
m2_covs <- c("Age", "Gender")

dbs <- readRDS(file.path(.tab, "imputed_dbs.rds"))
mids_list <- readRDS(file.path(.tab, "imputed_mids.rds"))
.lock <- readRDS(file.path(.tab, "quantile_scheme_resolved.rds"))
m3_by <- readRDS(file.path(.tab, "Model3_by_database.rds"))
m3_old <- Reduce(intersect, m3_by)

lab_pool <- c(
  "SOFA", "APSIII", "OASIS", "GCS", "WBC", "Hemoglobin", "PlateletCount",
  "RDW", "Sodium", "Potassium", "Glucose", "Creatinine", "UreaNitrogen"
)
lab_pool <- Reduce(intersect, lapply(dbs, function(d) intersect(lab_pool, names(d))))
# 排除 ANLR 成分（若有）
lab_pool <- setdiff(lab_pool, c("Albumin", "NeutrophilCount", "Lymphocytes", IDX))
message("S7 pool: ", paste(lab_pool, collapse = ", "))

# ---- 1) S7 全池相关性（先于中介）----
s7_store <- list()
for (nm in names(dbs)) {
  d <- as.data.frame(dbs[[nm]])
  # 临时 Model3 = 旧交集（筛选用）；稍后按中介剔除再重写 Table3
  s7_store[[nm]] <- pv2_s7_exposure_mediator_body(
    d, exposures = IDX, mediators = lab_pool,
    m1_covs = character(0), m2_covs = m2_covs, m3_covs = setdiff(m3_old, lab_pool)
  )
}

.parse_p <- function(x) {
  x <- trimws(as.character(x))
  ifelse(x == "<0.001", 5e-4, suppressWarnings(as.numeric(x)))
}
.extract_beta <- function(s) {
  s <- gsub(",", "", as.character(s))
  suppressWarnings(as.numeric(sub("^\\s*([-+0-9.eE]+).*", "\\1", s)))
}

# Model2 双库均 P<0.05 → 候选
# 默认优先实验室（非严重度评分），再按 mean|β|；可用 STROKE_ANLR_MEDIATOR 强制点名
.sev_rank <- c("OASIS", "APSIII", "SOFA", "GCS")
pick_from <- function(s7_list) {
  tabs <- lapply(names(s7_list), function(nm) {
    x <- as.data.frame(s7_list[[nm]])
    x <- x[x$Model == "Model2", , drop = FALSE]
    x$pnum <- .parse_p(x$P)
    x$bnum <- .extract_beta(x[["Beta (95% CI)"]])
    x$db <- nm
    x
  })
  both <- Reduce(function(a, b) merge(a, b, by = "Mediator", suffixes = c("_1", "_2")), tabs)
  both <- both[is.finite(both$pnum_1) & is.finite(both$pnum_2) &
                 both$pnum_1 < 0.05 & both$pnum_2 < 0.05, , drop = FALSE]
  if (!nrow(both)) return(NULL)
  both$mean_abs <- rowMeans(cbind(abs(both$bnum_1), abs(both$bnum_2)), na.rm = TRUE)
  both$is_sev <- both$Mediator %in% .sev_rank
  # lab first (is_sev=FALSE), then larger |beta|
  both <- both[order(both$is_sev, -both$mean_abs), , drop = FALSE]
  both
}

cand <- pick_from(s7_store)
if (is.null(cand) || !nrow(cand)) {
  stop("No shared Model2-significant mediator in S7 — omit S7/S8/Fig6 (prognosis gate).")
}
force_med <- trimws(Sys.getenv("STROKE_ANLR_MEDIATOR", unset = ""))
if (nzchar(force_med)) {
  if (!force_med %in% cand$Mediator) {
    stop("STROKE_ANLR_MEDIATOR=", force_med, " not in dual-DB Model2-significant set: ",
         paste(cand$Mediator, collapse = ", "))
  }
  best_med <- force_med
  pick_rule <- paste0("forced STROKE_ANLR_MEDIATOR=", force_med,
                      "; dual_DB Model2 P<0.05 candidates=", paste(cand$Mediator, collapse = ","))
} else {
  best_med <- as.character(cand$Mediator[1L])
  pick_rule <- "dual_DB Model2 P<0.05 intersection; prefer laboratory over severity, then max mean|beta|"
}
message("==== correlation-first pick ====")
message("Shared Model2-significant: ", paste(cand$Mediator, collapse = ", "))
message("Locked best mediator: ", best_med)
writeLines(c(
  paste0("best_mediator=", best_med),
  paste0("rule=", pick_rule),
  paste0("candidates=", paste(cand$Mediator, collapse = ",")),
  "pipeline=S7 correlation then S8 mediation (prognosis routine)"
), file.path(.tab, "preferred_mediator.txt"))

# ---- 2) Model3 剔除中介后重写 Table 3 / S3 ----
m3_shared <- setdiff(m3_old, best_med)
message("Model3 after dropping mediator: ", paste(m3_shared, collapse = " + "))
m3_by2 <- lapply(m3_by, function(x) setdiff(as.character(x), best_med))
saveRDS(m3_by2, file.path(.tab, "Model3_by_database.rds"))
fwrite(rbindlist(lapply(names(m3_by2), function(nm) {
  data.frame(database = nm, model3 = paste(m3_by2[[nm]], collapse = "+"), stringsAsFactors = FALSE)
})), file.path(.tab, "Model3_by_database.csv"))

cox_notes <- function(m3) {
  c(
    "The Model 1 was non-adjusted.",
    paste0("The Model 2 was adjusted by: ", paste(m2_covs, collapse = ", "), "."),
    paste0("The Model 3 was adjusted by: ", paste(m3, collapse = ", "), "."),
    paste0(
      best_med,
      " was reserved as the mediator (selected after Table S7 correlation screening) and was not included in Model 3."
    ),
    "Multiple imputation (cart, m = 5); hazard ratios pooled by Rubin's rules.",
    "Continuous exposure standardized to 1 SD within the analytic sample.",
    quantile_scheme_footnote_lines(.lock)
  )
}

for (nm in names(dbs)) {
  d <- as.data.frame(dbs[[nm]])
  body3 <- pv2_cox_wide_m123_body(
    d, IDX, .lock, mids = mids_list[[nm]],
    m2_covs = m2_covs, m3_covs = m3_shared,
    time_var = "futime_years", event_var = "fustatus", rubin = TRUE
  )
  body3$Variable <- sub(paste0("^\\s*", IDX, " \\(per 1 SD\\)$"), "  per 1 SD", body3$Variable)
  # 清旧短/长 Table3 文件名
  unlink(list.files(.tab, pattern = paste0("^Table 3-", nm, "\\."), full.names = TRUE))
  pv2_write_cox_wide_xlsx(
    file.path(.tab, pv2_table_xlsx_name(
      "Table 3", sprintf("Cox proportional hazards models for %s", .endpoint), db = nm)),
    pv2_table_title("Table 3", sprintf("Cox proportional hazards models for %s", .endpoint)),
    body3,
    footnotes = cox_notes(m3_shared)
  )

  # S3 Model4 = Model3 + HTN + DM（仍不含中介）
  m4 <- unique(c(m3_shared, "Hypertension", "Diabetes"))
  m4 <- m4[m4 %in% names(d)]
  body_m4 <- pv2_cox_wide_m123_body(
    d, IDX, .lock, mids = mids_list[[nm]],
    m2_covs = m2_covs, m3_covs = m4,
    time_var = "futime_years", event_var = "fustatus", rubin = TRUE
  )
  body_m4$Variable <- sub(paste0("^\\s*", IDX, " \\(per 1 SD\\)$"), "  per 1 SD", body_m4$Variable)
  body_s3 <- data.frame(
    Variable = body_m4$Variable,
    `HR (95% CI)` = body_m4[[6]],
    P = body_m4[[7]],
    check.names = FALSE, stringsAsFactors = FALSE
  )
  unlink(list.files(.tab, pattern = paste0("^Table S3-", nm, "\\."), full.names = TRUE))
  sci_xlsx_single_header_booktabs(
    file.path(.tab, pv2_table_xlsx_name(
      "Table S3", "Cox model including additional comorbidity (Model 4)", db = nm)),
    title = pv2_table_title("Table S3", "Cox model including additional comorbidity (Model 4)"),
    df_body = body_s3,
    footnotes = c(
      paste0("The Model 4 was adjusted by: ", paste(m4, collapse = ", "), "."),
      paste0("Mediator ", best_med, " excluded from Model 4 (same as Model 3)."),
      quantile_scheme_footnote_lines(.lock)
    ),
    level_row_idx = which(startsWith(body_s3$Variable, "  ")) + 1L
  )
}

# ---- 3) 重写 S7（脚注写清筛选→中介）并写 S8 ----
for (nm in names(dbs)) {
  d <- as.data.frame(dbs[[nm]])
  s7 <- pv2_s7_exposure_mediator_body(
    d, exposures = IDX, mediators = lab_pool,
    m1_covs = character(0), m2_covs = m2_covs, m3_covs = m3_shared
  )
  unlink(list.files(.tab, pattern = paste0("^Table S7-", nm, "\\."), full.names = TRUE))
  sci_xlsx_single_header_booktabs(
    file.path(.tab, pv2_table_xlsx_name(
      "Table S7", "Correlation between ANLR and other indicators", db = nm)),
    title = pv2_table_title("Table S7", "Correlation between ANLR and other indicators"),
    df_body = s7,
    footnotes = c(
      pv2_table3_covariate_footnotes(m2_covs = m2_covs, m3_covs = m3_shared),
      "Each linear model regresses the standardized indicator on ANLR (per 1 SD), matching Table S8 path a direction.",
      paste0(
        "Mediator for Table S8 / Figure 6 was selected after this correlation screen: dual-database Model 2 P<0.05 intersection; locked to ",
        best_med, "."
      ),
      paste0(
        "Table S8 / Figure 6 use the Model 2 adjustment (",
        paste(m2_covs, collapse = ", "),
        "); Model 2 beta for ", best_med, " aligns with Table S8 Path a."
      )
    )
  )

  s8 <- pv2_s8_mediation_body(
    d, exposures = IDX, mediators = best_med,
    covs = m2_covs, time_var = "futime_years", event_var = "fustatus",
    bootstrap_B = 400L, seed = 41904528L
  )
  unlink(list.files(.tab, pattern = paste0("^Table S8-", nm, "\\."), full.names = TRUE))
  sci_xlsx_single_header_booktabs(
    file.path(.tab, pv2_table_xlsx_name("Table S8", "Mediation analysis", db = nm)),
    title = pv2_table_title("Table S8", "Mediation analysis"),
    df_body = s8,
    footnotes = c(
      paste0("Mediator = ", best_med, " (selected after Table S7 correlation screening)."),
      paste0("Path models adjusted for ", paste(m2_covs, collapse = ", "), " (Table 3 Model 2)."),
      paste0(best_med, " omitted from its own adjustment set."),
      "Direct effect HR matches Figure 6 bottom arrow.",
      "Proportion mediated = (a\times b)/total on the log-hazard scale; bootstrap 95% CI (B=400)."
    )
  )
}

# ---- 4) Fig6 路径图（Hip 马卡龙；中介 = best_med）----
.macaron <- list(
  exposure = "#A8D5E5", mediator = "#F6C6C6", outcome = "#C8E6C9",
  path_a = "#5B9BD5", path_b = "#ED7D31", path_c = "#70AD47", prop = "#7F7F7F"
)
.med_fit_z <- function(d, expo, med, covs = m2_covs) {
  d <- as.data.frame(d)
  d$time <- as.numeric(d$futime_years)
  d$event <- as.integer(d$fustatus)
  if ("Gender" %in% covs) d$Gender <- factor(d$Gender)
  need <- c(expo, med, "time", "event", covs)
  dd <- d[stats::complete.cases(d[, need]) & d$time > 0, ]
  dd$.E <- as.numeric(scale(dd[[expo]]))
  dd$.M <- as.numeric(scale(dd[[med]]))
  ma <- lm(as.formula(paste(".M ~", paste(c(".E", covs), collapse = "+"))), dd)
  mf <- coxph(as.formula(paste("Surv(time, event) ~", paste(c(".E", ".M", covs), collapse = "+"))), dd)
  mt <- coxph(as.formula(paste("Surv(time, event) ~", paste(c(".E", covs), collapse = "+"))), dd)
  sa <- summary(ma)$coefficients
  sf <- summary(mf)$coefficients
  st <- summary(mt)$coefficients
  ca <- sa[".E", 1]; sea <- sa[".E", 2]; pa <- sa[".E", 4]
  cb <- sf[".M", 1]; seb <- sf[".M", 3]; pb <- sf[".M", 5]
  cp <- sf[".E", 1]; sep <- sf[".E", 3]; p_de <- sf[".E", 5]
  cc <- st[".E", 1]; ab <- ca * cb
  list(
    a = ca, pa = pa, a_lo = ca - 1.96 * sea, a_hi = ca + 1.96 * sea,
    b = cb, pb = pb, b_lo = cb - 1.96 * seb, b_hi = cb + 1.96 * seb,
    de_hr = exp(cp), p_de = p_de, de_lo = exp(cp - 1.96 * sep), de_hi = exp(cp + 1.96 * sep),
    prop = 100 * ab / cc
  )
}
db_order <- intersect(c("MIMIC", "eICU"), names(dbs))
p6_list <- lapply(seq_along(db_order), function(i) {
  nm <- db_order[[i]]
  res <- .med_fit_z(dbs[[nm]], IDX, best_med)
  message(sprintf(
    "Fig6 %s: a=%.3f (P=%s); Direct HR=%.3f; prop=%.1f%%",
    nm, res$a, ifelse(res$pa < 0.001, "<0.001", sprintf("%.3f", res$pa)),
    res$de_hr, res$prop
  ))
  .mp01_draw_mediation_path_diagram(
    exposure_label = paste0(IDX, " (per 1 SD)"),
    mediator_label = best_med,
    outcome_label = paste0(.day_lab, " mortality"),
    coef_a = res$a, p_a = res$pa, coef_b = res$b, p_b = res$pb,
    effect_total = res$de_hr, p_total = res$p_de,
    prop_pct = res$prop, prop_lo_pct = NA_real_, prop_hi_pct = NA_real_,
    colors = .macaron,
    ci_a_lo = res$a_lo, ci_a_hi = res$a_hi,
    ci_b_lo = res$b_lo, ci_b_hi = res$b_hi,
    ci_tot_lo = res$de_lo, ci_tot_hi = res$de_hi,
    font_family = "Times", output_path = NULL, width = 6.2, height = 4.0
  ) +
    ggplot2::ggtitle(paste0(if (i == 1L) "A  " else "B  ", nm)) +
    ggplot2::theme(plot.title = ggplot2::element_text(family = "Times", face = "bold", size = 12, hjust = 0))
})
.fig6_title <- paste0("Mediation path diagram of ANLR and ", .endpoint)
.fig6_stem <- paste0("Figure 6. ", .fig6_title)
unlink(list.files(.fig, pattern = "^Figure 6\\. Mediation path diagram.*\\.pdf$", full.names = TRUE))
fig6 <- file.path(.fig, paste0(.fig6_stem, ".pdf"))
if (requireNamespace("patchwork", quietly = TRUE)) {
  ggsave(
    fig6,
    (p6_list[[1]] / p6_list[[2]]) + patchwork::plot_annotation(title = .fig6_title),
    width = 6.8, height = 8.6, device = cairo_pdf, family = "Times"
  )
}
unlink(list.files(file.path(.out, "Figures", "image_information"),
                   pattern = "^Figure 6\\. Mediation path diagram.*\\.md$", full.names = TRUE))
writeLines(c(
  paste0("# ", .fig6_stem),
  "",
  "## 图面说明",
  paste0("上下两面板（A MIMIC / B eICU）；ANLR (per 1 SD) → ", best_med, " → ", .endpoint, "。"),
  "底边箭 = Direct effect HR（与 Table S8 同源）；调整 Age + Gender（Table 3 Model 2）。",
  paste0("中介 ", best_med, " 由 Table S7 相关性筛选后按预后套路选出（非预锁 SOFA）。"),
  "",
  "## 分析上下文",
  paste0("- 暴露: ANLR"),
  paste0("- 中介: ", best_med, "（S7→S8 预后套路）"),
  paste0("- 结局: ", .endpoint),
  "- 数据库: MIMIC + eICU",
  "- 是否拼图: 是（上下分库）"
), file.path(.out, "Figures", "image_information", paste0(.fig6_stem, ".md")))

# ---- 5) Methods：按行整句替换，禁止叠残 ----
methods <- readLines(file.path(.out, "Methods_statistical_analysis.md"), warn = FALSE)
.med_pick_phrase <- if (nzchar(force_med)) {
  paste0(best_med, " among dual-database Model 2 P<0.05 candidates (",
         paste(cand$Mediator, collapse = ", "), ")")
} else if (best_med %in% .sev_rank) {
  paste0(best_med, " (severity preferred among dual-database Model 2 P<0.05 candidates: ",
         paste(cand$Mediator, collapse = ", "), ")")
} else {
  paste0(best_med, " (laboratory preferred among dual-database Model 2 P<0.05 candidates: ",
         paste(cand$Mediator, collapse = ", "), ")")
}
cov_i <- which(grepl("Model 3 used a dual-DB harmonized set", methods))[1]
if (is.finite(cov_i)) {
  methods[[cov_i]] <- paste0(
    "Covariates were restricted to columns available in both databases. Model 1 was unadjusted. ",
    "Model 2 was adjusted for Age and Gender. Model 3 used a dual-DB harmonized set: Age, Gender, ",
    "and variables retained after Boruta/SHAP screening and VIF within the shared pool (intersection across databases). ",
    best_med, " was selected as the mediator after Table S7 correlation screening (",
    .med_pick_phrase, ") and was not entered in Model 3. ANLR component variables were excluded from regression covariates."
  )
}
methods[grepl("^Mediation followed|^Subgroup analyses", methods)] <- NA_character_
methods <- methods[!is.na(methods)]
ins <- c(
  paste0(
    "Subgroup analyses estimated Q4 versus Q1 contrasts for ", .endpoint,
    " on the full analytic sample after collapsing middle quartiles (unadjusted within strata), with likelihood-ratio P values for exposure×stratum interactions (Figure 7)."
  ),
  paste0(
    "Mediation followed the prognosis routine (correlation first, then mediation): Table S7 first reported associations of ANLR with shared laboratory/severity indicators; ",
    "the mediator was then selected as ", .med_pick_phrase, "; ",
    "Table S8 and Figure 6 evaluated path models adjusted as in Table 3 Model 2 (Age, Gender). ",
    "Path a was the linear coefficient of ANLR (per 1 SD) on standardized ", best_med,
    "; path b and the Direct effect were Cox log-hazard coefficients. Proportion mediated used bootstrap confidence intervals. Association tables and path diagrams were co-gated."
  )
)
ix <- which(grepl("^Sensitivity analysis", methods))[1]
if (is.finite(ix)) {
  methods <- c(methods[seq_len(ix - 1L)], ins, methods[ix:length(methods)])
} else {
  methods <- c(methods, ins)
}
writeLines(methods, file.path(.out, "Methods_statistical_analysis.md"))

writeLines(c(
  paste0("Dual-DB harmonized Model3 (mediator excluded): ", paste(m3_shared, collapse = " + ")),
  paste0("best_mediator=", best_med, " via S7 correlation-first (prognosis routine)."),
  "SOFA is no longer pre-locked as mediator."
), file.path(.tab, "Covariate_selection_note.txt"))

pub_figure_ensure_formats(
  file.path(.out, "Figures"),
  config = list(pub_figures = list(export_png = FALSE, export_tiff = FALSE, max_edge_in = 11))
)
message("done: mediator=", best_med)
