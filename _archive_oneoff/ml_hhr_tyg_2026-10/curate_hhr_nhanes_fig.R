Sys.setenv(MEDICAL_BLOCKS_ROOT = "E:/01block/01Block-new-Final")
eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT")
source(file.path(eng, "R/attrition_log.R"), local = FALSE)
source(file.path(eng, "R/pub_figure_export.R"), local = FALSE)
`%||%` <- function(a, b) if (!is.null(a)) a else b

index_root <- "G:/02block_result/15_hearing_loss/ml_hhr_charls_single/by_index/\u3010success\u3011HHR"
csv <- file.path(index_root, "NHANES/step44_attrition_flowchart/Tables/Flowchart_attrition_nhanes.csv")
rows <- utils::read.csv(csv, stringsAsFactors = FALSE)
rows$database <- "NHANES"
cohort <- list(
  database = "NHANES",
  years = "1999-2018 cycles with hearing outcome",
  n_source = 22377L,
  age_exclude_label = "Age < 45 or > 69 years or missing age",
  age_exclude_n = 15961L,
  age_keep_label = "Aged 45\u201369 years",
  age_keep_n = 6416L,
  side_line_width = 54L,
  figure_width = 5.6
)
tmp <- file.path(tempdir(), "fig1_nhanes.pdf")
ok <- attrition_draw_pv2_pdf(list(NHANES = rows), tmp, cohort = cohort, width = 5.6)
stopifnot(isTRUE(ok), file.exists(tmp), file.size(tmp) > 5000)
message("fig1 size ", file.size(tmp))

fig_pdf <- file.path(index_root, "Figures/pdf")
sum_pdf <- file.path(index_root, "summary_results/Figures/pdf")
nhanes_fig <- file.path(index_root, "NHANES/Figures")
dir.create(fig_pdf, TRUE, FALSE)
dir.create(sum_pdf, TRUE, FALSE)

for (d in c(
  file.path(fig_pdf, "Figure 1. Flowchart.pdf"),
  file.path(sum_pdf, "Figure 1. Flowchart.pdf"),
  file.path(index_root, "Figures/Figure 1. Flowchart.pdf"),
  file.path(nhanes_fig, "Figure 1. Flowchart.pdf")
)) {
  dir.create(dirname(d), TRUE, FALSE)
  file.copy(tmp, d, TRUE)
}

sg <- file.path(fig_pdf, "Figure 3. Subgroup Forest analyses of HHR.pdf")
if (file.exists(sg)) {
  file.copy(sg, file.path(fig_pdf, "Figure 5. Subgroup Forest analyses of HHR.pdf"), TRUE)
}

shap_dst <- file.path(fig_pdf, "Figure 4. SHAP.pdf")
if (!file.exists(shap_dst)) {
  shap <- list.files(fig_pdf, pattern = "^Figure 4\\. SHAP", full.names = TRUE)
  shap <- shap[!grepl("Figure 4\\. SHAP\\.pdf$", basename(shap))]
  if (length(shap)) file.copy(shap[[1]], shap_dst, TRUE)
}

A <- list.files(c(fig_pdf, nhanes_fig), pattern = "S2A.*Lasso", full.names = TRUE)[1]
B <- list.files(c(fig_pdf, nhanes_fig), pattern = "S2B.*Lasso", full.names = TRUE)[1]
s1 <- file.path(fig_pdf, "Figure S1. Lasso.pdf")
if (!is.na(A) && !is.na(B) && file.exists(A) && file.exists(B)) {
  combined <- FALSE
  if (exists("pub_figure_combine_ab_pdfs", mode = "function")) {
    combined <- isTRUE(tryCatch(pub_figure_combine_ab_pdfs(A, B, s1), error = function(e) FALSE))
  }
  if (!combined && requireNamespace("pdftools", quietly = TRUE)) {
    tryCatch({
      pdftools::pdf_combine(c(A, B), output = s1)
      combined <- TRUE
    }, error = function(e) NULL)
  }
  if (!combined) file.copy(B, s1, TRUE)
  message("S1 size ", file.size(s1))
}

f3 <- file.path(fig_pdf, "Figure 3. ML performance combined 2x4.pdf")
message("Fig3 size ", if (file.exists(f3)) file.size(f3) else NA)

keep <- c(
  "Figure 1. Flowchart.pdf",
  "Figure 2. RCS of HHR and Hearing loss.pdf",
  "Figure 3. ML performance combined 2x4.pdf",
  "Figure 4. SHAP.pdf",
  "Figure 5. Subgroup Forest analyses of HHR.pdf",
  "Figure S1. Lasso.pdf"
)
for (dir in c(fig_pdf, sum_pdf)) {
  if (!dir.exists(dir)) next
  for (p in list.files(dir, "\\.pdf$", full.names = TRUE)) {
    if (!basename(p) %in% keep) unlink(p)
  }
}
for (bn in keep) {
  src <- file.path(fig_pdf, bn)
  dst <- file.path(sum_pdf, bn)
  if (file.exists(src) && !identical(
    normalizePath(src, winslash = "/", mustWork = FALSE),
    normalizePath(dst, winslash = "/", mustWork = FALSE)
  )) {
    file.copy(src, dst, TRUE)
  }
}

# drop attrition csv from delivery tables
for (td in c(file.path(index_root, "Tables"), file.path(index_root, "summary_results/Tables"))) {
  csvs <- list.files(td, pattern = "^Flowchart_attrition", full.names = TRUE)
  if (length(csvs)) unlink(csvs)
}

cfg <- list(pub_figures = list(
  formats_dir = TRUE, dpi = 600L, tiff_compression = "lzw",
  write_image_information = TRUE
))
for (fd in c(
  file.path(index_root, "Figures"),
  file.path(index_root, "summary_results/Figures")
)) {
  if (!dir.exists(fd)) next
  message("ensure_formats ", fd)
  print(pub_figure_ensure_formats(fd, config = cfg))
}

message("FINAL pdf:")
print(list.files(sum_pdf))
