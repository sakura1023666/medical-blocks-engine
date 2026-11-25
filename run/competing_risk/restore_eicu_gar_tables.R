#!/usr/bin/env Rscript
root <- "/mnt/e/01block/01Block-new-Final"
setwd(root)
source("R/pub_xlsx_surgical.R")

ws <- "/mnt/g/02block_result/33_AKI/Competing_risk_CRRT_28d/eICU/by_unit/\u3010success\u3011GAR_delivery_workspace/Tables_internal"
tab <- "/mnt/g/02block_result/33_AKI/Competing_risk_CRRT_28d/eICU/by_unit/\u3010success\u3011GAR/Tables"
fig <- "/mnt/g/02block_result/33_AKI/Competing_risk_CRRT_28d/eICU/by_unit/\u3010success\u3011GAR/Figures"
dir.create(tab, showWarnings = FALSE, recursive = TRUE)

pick_newest <- function(pattern) {
  fs <- list.files(ws, pattern = pattern, full.names = TRUE)
  fs <- fs[grepl("-eICU\\.", basename(fs))]
  if (!length(fs)) return(NULL)
  fs[order(file.info(fs)$mtime, decreasing = TRUE)][1]
}

moves <- list(
  list(pat = "^Table 1-eICU\\. Baseline characteristics by GAR quartile", dest = "Table 1-eICU. Baseline characteristics by GAR quartile.xlsx"),
  list(pat = "^Table 2-eICU\\. CIF of mortality by GAR quartile", dest = "Table 2-eICU. CIF of mortality by GAR quartile.xlsx"),
  list(pat = "^Table 3-eICU\\. Baseline characteristics by GAR trajectory", dest = "Table 3-eICU. Baseline characteristics by GAR trajectory.xlsx"),
  list(pat = "^Table 4-eICU\\. CIF of mortality by GAR trajectory", dest = "Table 4-eICU. CIF of mortality by GAR trajectory.xlsx"),
  list(pat = "Subgroup analysis by quartile", dest = "Table S1-eICU. Subgroup analysis by quartile.xlsx"),
  list(pat = "Standard Cox by quartile \\(sensitivity\\)", dest = "Table S2-eICU. Standard Cox by quartile (sensitivity).xlsx"),
  list(pat = "Competing-risk Cox sensitivity \\(extremes handled\\)", dest = "Table S3-eICU. Competing-risk Cox sensitivity (extremes handled).xlsx"),
  list(pat = "Standard Cox sensitivity \\(extremes handled\\)", dest = "Table S4-eICU. Standard Cox sensitivity (extremes handled).xlsx"),
  list(pat = "Subgroup analysis by trajectory", dest = "Table S5-eICU. Subgroup analysis by trajectory.xlsx"),
  list(pat = "Standard Cox by trajectory\\.xlsx$", dest = "Table S6-eICU. Standard Cox by trajectory.xlsx")
)

for (m in moves) {
  src <- pick_newest(m$pat)
  if (is.null(src)) { message("MISS: ", m$pat); next }
  dest <- file.path(tab, m$dest)
  file.copy(src, dest, overwrite = TRUE)
  message("OK ", basename(src), " -> ", m$dest)
}

for (dir in c(fig, file.path(fig, "pdf"), file.path(fig, "image_information"))) {
  if (!dir.exists(dir)) next
  fs <- list.files(dir, full.names = TRUE, recursive = FALSE)
  bn <- basename(fs)
  drop <- grepl("(?i)(^Figure\\s*S|Missing|Lasso|Random\\s*forest|S2[A-G]\\.|Fig1_Flowchart_raw)", bn, perl = TRUE)
  drop <- drop | (grepl("(?i)\\.pdf$", bn) & !grepl("^Figure [0-9]+-", bn) & !dir.exists(fs))
  if (any(drop)) unlink(fs[drop])
}

pdf_dir <- file.path(fig, "pdf")
dir.create(pdf_dir, showWarnings = FALSE)
for (f in list.files(fig, pattern = "^Figure [0-9]+-.*\\.pdf$", full.names = TRUE)) {
  file.copy(f, file.path(pdf_dir, basename(f)), overwrite = TRUE)
}

# 不用 pub_sync / strip：openpyxl 往返会弄坏部分 Supp 表的 openxlsx 可读性；
# 文件名已是 Lai S1–S6，A1 在下面用外科改。
if (exists("pub_xlsx_edit_cells", mode = "function")) {
  for (f in list.files(tab, pattern = "\\.xlsx$", full.names = TRUE)) {
    stem <- sub("\\.xlsx$", "", basename(f))
    try(pub_xlsx_edit_cells(f, data.frame(row = 1L, col = 1L, value = stem, stringsAsFactors = FALSE)), silent = TRUE)
  }
}

message("FINAL tables:")
print(list.files(tab, pattern = "\\.xlsx$"))
message("FINAL figs:")
print(list.files(pdf_dir, pattern = "\\.pdf$"))
library(openxlsx)
d <- read.xlsx(file.path(tab, "Table 1-eICU. Baseline characteristics by GAR quartile.xlsx"), colNames = FALSE)
print(d[1:3, 1:3])
print(tail(d, 3))
