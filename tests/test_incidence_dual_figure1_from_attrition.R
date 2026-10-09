# test: dual-db incidence Figure 1 must not keep single-db flowchart
`%||%` <- function(a, b) if (is.null(a)) b else a

root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = normalizePath("."))
source(file.path(root, "R", "utils.R"), local = FALSE)
source(file.path(root, "R", "attrition_log.R"), local = FALSE)
source(file.path(root, "R", "dual_db_harmonize.R"), local = FALSE)
source(file.path(root, "R", "incidence_dual_batch_runner.R"), local = FALSE)

td <- tempfile("fig1_dual_")
dir.create(td)
on.exit(unlink(td, recursive = TRUE), add = TRUE)

# 模拟 by_index/<ix>/{NHANES,CHARLS}/step_attrition/Tables
ix_root <- file.path(td, "by_index", "TESTIX")
for (db in c("NHANES", "CHARLS")) {
  tab <- file.path(ix_root, db, "step99_attrition_flowchart", "Tables")
  dir.create(tab, recursive = TRUE)
  utils::write.csv(
    data.frame(
      step = c("After data cleaning", "After imputation"),
      n = if (identical(db, "NHANES")) c(2000L, 1000L) else c(5000L, 3000L),
      source = "log",
      kind = "include"
    ),
    file.path(tab, sprintf("Flowchart_attrition_%s.csv", tolower(db))),
    row.names = FALSE
  )
  fig_db <- file.path(ix_root, db, "Figures")
  dir.create(fig_db, recursive = TRUE)
}
# 汇总目录先放一张「单库」假 Figure 1（非占位体积）
fig_agg <- file.path(ix_root, "Figures")
dir.create(fig_agg, recursive = TRUE)
grDevices::pdf(file.path(fig_agg, "Figure 1. Flowchart.pdf"), width = 6, height = 5)
plot.new()
title("Single NHANES only")
text(0.5, 0.5, "N = 1000")
grDevices::dev.off()

config <- list(
  project = list(kind = "incidence", exposure_var = "TESTIX"),
  dual_db = list(
    enable = TRUE,
    primary = list(name = "NHANES", db_type = "nhanes"),
    secondary = list(name = "CHARLS", db_type = "regular")
  ),
  plot = list(font_family = "sans")
)

ok <- incidence_batch_ensure_real_figure1(
  index_root = ix_root,
  config = config,
  ix = "TESTIX",
  db_seq = c("nhanes", "mimic"),
  project_root = td
)
stopifnot(isTRUE(ok))
dest <- file.path(fig_agg, "Figure 1. Flowchart.pdf")
stopifnot(file.exists(dest))
stopifnot(file.info(dest)$size > 2000)

txt <- ""
if (nzchar(Sys.which("pdftotext"))) {
  txt <- paste(system2("pdftotext", c("-layout", dest, "-"), stdout = TRUE, stderr = FALSE), collapse = " ")
}
if (!nzchar(txt)) {
  # 至少应写出 dual csv
  dual_csv <- file.path(ix_root, "Tables", "Flowchart_attrition_TESTIX_dual.csv")
  stopifnot(file.exists(dual_csv))
  dt <- utils::read.csv(dual_csv)
  stopifnot(length(unique(dt$database)) >= 2L)
  message("OK (csv dual; pdftotext unavailable for text check)")
} else {
  stopifnot(grepl("NHANES", txt, ignore.case = TRUE))
  stopifnot(grepl("CHARLS", txt, ignore.case = TRUE))
  stopifnot(!grepl("Single NHANES only", txt, fixed = TRUE))
  message("OK: dual Figure 1 contains NHANES + CHARLS")
}
