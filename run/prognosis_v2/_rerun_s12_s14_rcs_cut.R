#!/usr/bin/env Rscript
# 仅重跑扩展：用本课题各库 RCS Model3 切点替换旧 465 min 包，并刷新 Methods。
engine <- if (dir.exists("/mnt/e/01block/01Block-new-Final")) {
  "/mnt/e/01block/01Block-new-Final"
} else {
  "E:/01block/01Block-new-Final"
}
Sys.setenv(MEDICAL_BLOCKS_ROOT = engine, PV2_PROFILE = "sleep_dyslipidemia")
source(file.path(engine, "run/prognosis_v2/pv2_paths.R"), local = FALSE)
source(file.path(engine, "run/prognosis_v2/pv2_mainval_extension.R"), local = FALSE)
# Methods
Sys.setenv(
  PV2_PROFILE = "sleep_dyslipidemia",
  PV2_COHORT = "adults aged 45 years or older with dyslipidemia",
  PV2_EXPOSURE = "sleep duration",
  PV2_MEDIATOR = "diastolic blood pressure (DBP)"
)
cmd <- sprintf(
  "Rscript %s --dir %s --study-type prognosis_v2 --outcome %s --exposure %s --databases %s",
  shQuote(file.path(engine, "run/pub/finalize_delivery_root.R")),
  shQuote(pv2_out_root),
  shQuote("all-cause mortality"),
  shQuote("sleep duration"),
  shQuote("NHANES,SHHS,CHARLS")
)
status <- system(cmd)
message("rerun done status=", status)
