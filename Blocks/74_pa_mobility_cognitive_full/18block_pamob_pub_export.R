###############################################################################
# pamob_pub_export — 汇总 Fig1–4 四目录 + Methods/Results 初稿
###############################################################################

block_pamob_pub_export <- function(ctx, ...) {
  source(file.path(ctx$config$project$root %||% getwd(),
                   "Blocks/74_pa_mobility_cognitive_full/00pamob_common.R"), local = FALSE)
  .pamob_source_utils(ctx)
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/pub_figure_export.R"), local = FALSE)

  batch_root <- pamob_out_root(ctx)
  coll <- pamob_collect_main_figures(batch_root)
  fig <- coll$figures_dir

  # 若 NHANES 单元把 Fig4 顺延成 Figure 1，再从 png/pdf 搜一次并复制为 Figure 4
  if (!("Figure 4. NHANES DSST and NfL panel.pdf" %in% coll$copied)) {
    hits <- list.files(file.path(batch_root, "by_unit"), pattern = "NfL|DSST.*panel",
                       recursive = TRUE, full.names = TRUE)
    hits <- hits[grepl("\\.pdf$", hits, ignore.case = TRUE)]
    if (length(hits)) {
      file.copy(hits[[1L]], file.path(fig, "Figure 4. NHANES DSST and NfL panel.pdf"), overwrite = TRUE)
      coll$copied <- c(coll$copied, "Figure 4. NHANES DSST and NfL panel.pdf")
    }
  }

  res <- tryCatch(
    export_pub_figures(fig, config = ctx$config),
    error = function(e) {
      tryCatch(pub_figure_ensure_formats(fig, config = ctx$config), error = function(e2) e2)
    }
  )

  # Methods / Results 初稿（方案 §10.1 / §11）
  ms_dir <- file.path(batch_root, "Manuscript")
  dir.create(ms_dir, recursive = TRUE, showWarnings = FALSE)
  feas <- file.path(batch_root, "_shared", "Tables", "Feasibility", "Feasibility_Report.md")
  t1 <- file.path(batch_root, "by_unit", "【success】CHARLS", "Tables",
                  "Table 1. CHARLS baseline by phenotype.csv")
  t2 <- file.path(batch_root, "by_unit", "【success】CHARLS", "Tables",
                  "Table 2. CHARLS LMM Global cognition.csv")
  t3 <- file.path(batch_root, "by_unit", "【success】NHANES", "Tables",
                  "Table 3. NHANES baseline by phenotype.csv")
  t4 <- file.path(batch_root, "by_unit", "【success】NHANES", "Tables",
                  "Table 4. NHANES DSST and NfL regressions.csv")

  draft <- c(
    "# Methods and Results Draft — PA–Mobility Phenotypes and Cognitive Aging",
    "",
    "## Methods (draft)",
    "",
    "### Study design",
    "We constructed four physical activity–mobility capacity phenotypes and examined:",
    "(i) CHARLS longitudinal change in global cognition (0–21) using linear mixed-effects models",
    "with phenotype × time interactions (random intercept); and (ii) NHANES 2013–2014",
    "cross-sectional associations with DSST and log(serum NfL) under the complex survey design.",
    "Databases were analyzed separately (cross-database triangulation); individual-level pooling was not performed.",
    "NfL was not treated as a formal mediator of CHARLS associations.",
    "",
    "### Phenotype definition",
    "PA sufficient: ≥600 MET-min/week. Mobility limited: any difficulty on four harmonized tasks",
    "(~1 km walk, stairs, chair rise, stoop/kneel). Reference: Active–preserved.",
    "Two pre-specified contrasts: Inactive–preserved vs Active–preserved;",
    "Active–limited vs Inactive–limited.",
    "ADL/IADL were not included in the main mobility score. CES-D-10/PHQ-9 were covariates, not cognitive outcomes.",
    "",
    "### CHARLS",
    "Baseline wave locked to 2011 (Scheme A) after feasibility comparison with 2015 (Scheme B).",
    "Adults aged ≥45 years with baseline phenotype and repeated cognition contributed to LMM.",
    "Models 1–3 nested covariates (demographics → SES → lifestyle/comorbidity/CES-D-10).",
    "Primary outcome: global cognition; secondary: episodic memory.",
    "",
    "### NHANES",
    "Cycle H (2013–2014), age 60–75 for the integrated PA/mobility/DSST/NfL sample.",
    "NfL models used WTSSNH2Y with SDMVSTRA/SDMVPSU. Model 3 covariates followed the proposal;",
    "NfL extensions added eGFR (±CRP in sensitivity). PFQ answer 5 coded as limited in main analyses",
    "and excluded in sensitivity analyses.",
    "",
    "### Sensitivities (pre-specified)",
    "CHARLS: exclude baseline stroke; mobility limited redefined as ≥2 items; ≥2 cognition waves.",
    "NHANES: exclude PFQ answer 5; exclude stroke; NfL Model3+eGFR+CRP.",
    "PA alternative duration remapping requires raw CHARLS PA bins (not in delivered D03-ok) and is noted as not run.",
    "",
    "## Results (draft placeholders — numbers from pipeline tables)",
    "",
    paste0("- Feasibility report: ", if (file.exists(feas)) feas else "pending"),
    paste0("- Table 1 present: ", file.exists(t1)),
    paste0("- Table 2 present: ", file.exists(t2)),
    paste0("- Table 3 present: ", file.exists(t3)),
    paste0("- Table 4 present: ", file.exists(t4)),
    paste0("- Main figures copied to Figures/: ", paste(coll$copied, collapse = "; ")),
    "",
    "### Interpretation guardrails",
    "CHARLS estimates refer to longitudinal cognitive change; NHANES DSST/NfL estimates are cross-sectional",
    "and must not be described as cognitive decline. Serum NfL is a neurodegeneration-related marker,",
    "not AD-specific. Associations should not be framed as causal effects.",
    "",
    "### Key references (proposal Appendix B)",
    "Ylitalo 2021; Tian & Shi 2022; Chai 2024; Thibeau 2019; Taaffe 2008; Desai 2022; Luo 2022;",
    "WHO GPAQ analysis guide; NHANES 2013–2014 PAQ/PFQ/CFQ/SSSNFL documentation."
  )
  writeLines(draft, file.path(ms_dir, "Methods_Results_Draft.md"))

  # 根目录 Tables：仅发表三线表 xlsx（由 rebuild 脚本生成）
  tab_root <- file.path(batch_root, "Tables")
  rebuild <- file.path(root, "run/pa_mobility_cognitive/rebuild_pamob_pub_tables.R")
  if (file.exists(rebuild)) {
    tryCatch(
      source(rebuild, local = new.env(parent = globalenv())),
      error = function(e) cli::cli_alert_warning("pub tables rebuild: {conditionMessage(e)}")
    )
  } else {
    dir.create(tab_root, recursive = TRUE, showWarnings = FALSE)
    for (p in c(t1, t2, t3, t4)) {
      if (file.exists(p)) file.copy(p, file.path(tab_root, basename(p)), overwrite = TRUE)
    }
  }

  ctx$results$pamob_pub_export <- list(
    figures_dir = fig, result = res, copied = coll$copied,
    manuscript = file.path(ms_dir, "Methods_Results_Draft.md")
  )
  cli::cli_alert_success("pamob_pub_export: Figs={length(coll$copied)}; draft={ms_dir}")
  ctx
}

register_block("pamob_pub_export", block_pamob_pub_export, "发表图四目录导出")
