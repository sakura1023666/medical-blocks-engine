#!/usr/bin/env Rscript
# Keep ONLY Table 1-6 / Figure 1-4 as main text.
# Remap Table 7-16 + old S* + Figure 5-7 + old Fig S1 → continuous Table S1+ / Figure S1+.

suppressPackageStartupMessages({ library(openxlsx) })
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/pub_xlsx_surgical.R"), local = FALSE)

proj <- file.path(
  Sys.getenv("BLOCK_RESULT_ROOT", "/mnt/g/02block_result"),
  "63_SSD", "LPA_Network_Mediaton_42214160", "by_index", "main_full_sample"
)
args <- commandArgs(trailingOnly = TRUE)
i <- match("--project", args)
if (!is.na(i) && i < length(args)) {
  proj <- normalizePath(args[[i + 1L]], winslash = "/", mustWork = TRUE)
}

sr <- file.path(proj, "summary_results")
sr_tab <- file.path(sr, "Tables")
sr_pdf <- file.path(sr, "Figures", "pdf")
sr_md <- file.path(sr, "Figures", "image_information")
stopifnot(dir.exists(sr_tab), dir.exists(sr_pdf))

# stem without extension → new stem (keep descriptive title after number)
tab_map <- c(
  "Table 7. Indirect effect contrast SSD-12 vs Whiteley-8" =
    "Table S1. Indirect effect contrast SSD-12 vs Whiteley-8",
  "Table 8. WHO-DAS domain scores by LCA class" =
    "Table S2. WHO-DAS domain scores by LCA class",
  "Table 9. CFA discriminant validity SSD-12 vs Whiteley" =
    "Table S3. CFA discriminant validity SSD-12 vs Whiteley",
  "Table 10. Mediation with SSS-8 as exposure" =
    "Table S4. Mediation with SSS-8 as exposure",
  "Table 11. Sensitivity mediation adjusting depression anxiety" =
    "Table S5. Sensitivity mediation adjusting depression anxiety",
  "Table 12. Stratified mediation by available moderators" =
    "Table S6. Stratified mediation by available moderators",
  "Table 13. Clinical ROC for WHO-DAS median split" =
    "Table S7. Clinical ROC for WHO-DAS median split",
  "Table 14. Objective visit burden N12AA by LCA class" =
    "Table S8. Objective visit burden N12AA by LCA class",
  "Table 15. Competing and reverse mediation models" =
    "Table S9. Competing and reverse mediation models",
  "Table 16. Spearman correlations with FDR adjustment" =
    "Table S10. Spearman correlations with FDR adjustment",
  "Table S1. Measurement invariance CFA SSD-12 Whiteley" =
    "Table S11. Measurement invariance CFA SSD-12 Whiteley",
  "Table S2. Multi-group path SEM indirect effects" =
    "Table S12. Multi-group path SEM indirect effects",
  "Table S3. Formal moderated mediation index" =
    "Table S13. Formal moderated mediation index",
  "Table S4. FIML and MI sensitivity for parallel mediation" =
    "Table S14. FIML and MI sensitivity for parallel mediation",
  "Table S5. Mediation with objective function outcomes" =
    "Table S15. Mediation with objective function outcomes",
  "Table S6. Qualitative functional subtypes from WHO-DAS domains" =
    "Table S16. Qualitative functional subtypes from WHO-DAS domains",
  "Table S7. Qualitative gloss for main-text severity LCA" =
    "Table S17. Qualitative gloss for main-text severity LCA"
)

fig_map <- c(
  "Figure 5. WHO-DAS domain profiles by LCA class" =
    "Figure S1. WHO-DAS domain profiles by LCA class",
  "Figure 6. Decision curve analysis" =
    "Figure S2. Decision curve analysis",
  "Figure 7. Stratified mediation ACME forest" =
    "Figure S3. Stratified mediation ACME forest",
  "Figure S1. Functional subtype domain profiles" =
    "Figure S4. Functional subtype domain profiles"
)

tmp_tag <- paste0("__remap_", format(Sys.time(), "%H%M%S"), "__")
phase1 <- function(dir, map, ext) {
  out <- list()
  for (nm in names(map)) {
    src <- file.path(dir, paste0(nm, ext))
    if (!file.exists(src)) {
      message("skip missing ", basename(src))
      next
    }
    tmp <- file.path(dir, paste0(tmp_tag, gsub("[^A-Za-z0-9]+", "_", nm), ext))
    if (file.exists(tmp)) unlink(tmp)
    ok <- file.rename(src, tmp)
    if (!isTRUE(ok)) {
      file.copy(src, tmp, overwrite = TRUE)
      unlink(src)
    }
    out[[length(out) + 1L]] <- list(tmp = tmp, dest_stem = unname(map[[nm]]))
    message("park ", basename(src))
  }
  out
}

phase2 <- function(parked, ext) {
  for (it in parked) {
    dest <- file.path(dirname(it$tmp), paste0(it$dest_stem, ext))
    if (file.exists(dest)) unlink(dest)
    ok <- file.rename(it$tmp, dest)
    if (!isTRUE(ok)) {
      file.copy(it$tmp, dest, overwrite = TRUE)
      unlink(it$tmp)
    }
    message("-> ", basename(dest))
  }
}

message("Remapping tables...")
park_tab <- phase1(sr_tab, tab_map, ".xlsx")
phase2(park_tab, ".xlsx")

message("Remapping figure PDFs...")
park_pdf <- phase1(sr_pdf, fig_map, ".pdf")
phase2(park_pdf, ".pdf")

message("Remapping figure markdown...")
park_md <- phase1(sr_md, fig_map, ".md")
phase2(park_md, ".md")

# Update A1 titles to match filenames
message("Sync A1 titles...")
tryCatch(pub_sync_xlsx_a1_titles_to_filenames(sr_tab), error = function(e) {
  message("pub_sync failed: ", conditionMessage(e))
})

# Patch first line / title mentions inside md
for (stem in unname(fig_map)) {
  md <- file.path(sr_md, paste0(stem, ".md"))
  if (!file.exists(md)) next
  lines <- readLines(md, warn = FALSE)
  if (!length(lines)) next
  lines[1] <- paste0("# ", stem)
  writeLines(lines, md)
  message("md title: ", basename(md))
}

# Methods: rewrite extension numbering to S*
methods_path <- file.path(sr, "Methods_statistical_analysis.md")
if (file.exists(methods_path)) {
  old <- readLines(methods_path, warn = FALSE)
  # drop previous extension + proposed framing blocks; rebuild clean
  cut1 <- grep("^## Extensions aligned with the 1021", old)
  cut2 <- grep("^## Proposed manuscript framing", old)
  cut <- min(c(cut1, cut2), na.rm = TRUE)
  if (is.finite(cut) && cut > 1L) old <- old[seq_len(cut - 1L)]

  # also scrub stray Table 7-16 / Figure 5-7 in retained body if any
  # (keep Figure 1-4 mentions)

  extra <- c(
    "",
    "## Supplementary materials numbering",
    "",
    "Main-text deliverables are **Tables 1–6** and **Figures 1–4** only. All other tables/figures below are supplementary.",
    "",
    "### Proposed title (Common-Sense Model framing)",
    "Predictors and mediating mechanisms of disability and social functioning impairment (WHO-DAS 12) among outpatients with somatic symptom disorder in a general hospital: a Common-Sense Model analysis of cognitive-path dominance and heterogeneity.",
    "",
    "中文拟定题目：综合医院门诊躯体症状障碍（SSD）患者残疾与社会功能损害（WHO-DAS 12）的预测因素及介导机制分析——基于症状感知/Common-Sense Model 的认知路径主导性与人群异质性。",
    "",
    "Innovation claim: which cognitive path dominates (SSD-12 vs Whiteley-8) and for whom (heterogeneity), not merely that mediation exists.",
    "",
    "### Supplementary tables",
    "- Table S1: parallel competing mediation indirect-effect contrast (H3).",
    "- Table S2: WHO-DAS domain scores by LCA class.",
    "- Table S3: CFA discriminant validity (SSD-12 vs Whiteley).",
    "- Table S4: mediation with SSS-8 as exposure.",
    "- Table S5: sensitivity mediation ± PHQ-9 / GAD-7.",
    "- Table S6: stratified mediation by available moderators.",
    "- Table S7: clinical ROC for WHO-DAS median split.",
    "- Table S8: objective visit burden (N12AA) by LCA class.",
    "- Table S9: competing and reverse mediation models.",
    "- Table S10: Spearman correlations with BH-FDR.",
    "- Table S11: measurement invariance CFA.",
    "- Table S12: multi-group path SEM.",
    "- Table S13: formal moderated mediation (index).",
    "- Table S14: FIML and MICE+Rubin sensitivity.",
    "- Table S15: mediation with objective outcomes (visits / employment).",
    "- Table S16: qualitative functional subtypes (domain k-means).",
    "- Table S17: qualitative gloss for main-text severity LCA.",
    "",
    "### Supplementary figures",
    "- Figure S1: WHO-DAS domain profiles by LCA class.",
    "- Figure S2: decision-curve analysis.",
    "- Figure S3: stratified mediation ACME forest.",
    "- Figure S4: qualitative functional subtype domain profiles.",
    "",
    "Alexithymia / catastrophizing / childhood trauma instruments and sick-leave/cost variables were unavailable; DAS8/DAS9 were absent from the analytic file.",
    ""
  )
  writeLines(c(old, extra), methods_path)
  message("Methods updated")
}

message("DONE. Main tables:")
print(list.files(sr_tab, pattern = "^Table [1-6]\\b"))
message("Supp tables:")
print(list.files(sr_tab, pattern = "^Table S"))
message("Main figs:")
print(list.files(sr_pdf, pattern = "^Figure [1-4]\\b"))
message("Supp figs:")
print(list.files(sr_pdf, pattern = "^Figure S"))
