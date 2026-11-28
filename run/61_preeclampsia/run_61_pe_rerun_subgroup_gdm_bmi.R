#!/usr/bin/env Rscript
# 重跑全部结局亚组：GDM + 孕前 BMI 中国四分类
# 稀有结局 Firth：四分类可估率过低时自动退三分类（<24 / 24–27.9 / ≥28）
#
# Rscript run/61_preeclampsia/run_61_pe_rerun_subgroup_gdm_bmi.R

`%||%` <- function(a, b) if (!is.null(a)) a else b

.root <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    sp <- normalizePath(dirname(sub("^--file=", "", f[1L])), winslash = "/")
    if (basename(sp) == "61_preeclampsia" && basename(dirname(sp)) == "run") {
      return(normalizePath(file.path(sp, "..", ".."), winslash = "/"))
    }
  }
  normalizePath(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd()), winslash = "/")
}

root <- .root()
setwd(root)
Sys.setenv(MEDICAL_BLOCKS_ROOT = root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "run/61_preeclampsia/pe_pre_bmi_group.R"))
source("/mnt/g/02block_result/61_Preeclampsia/configs/config_61_preeclampsia_batch.R")

out_base <- config$project$output_dir
ck_shared <- pipeline_shared$checkpoint$dir
ck <- file.path(ck_shared, "multicollinearity_screen.rds")
if (!file.exists(ck)) ck <- file.path(ck_shared, "step08_multicollinearity_screen.rds")
obj <- readRDS(ck)
shared_ctx <- if (!is.null(obj$ctx)) obj$ctx else obj
m1 <- as.character(shared_ctx$results$Model1Factors %||% "Age")
m2 <- as.character(shared_ctx$results$Model2Factors %||% character(0))
if (!length(m2)) stop("Model2Factors 为空", call. = FALSE)

id <- as.character(config$data$id_column %||% "Admission_Num")[1L]
data0 <- as.data.frame(shared_ctx$data$imputed %||% shared_ctx$data$cleaned)
need <- c("Cesarean01", "Apgar1_lt8", "Apgar5_lt8", "Newborn_lt1500", "Newborn_lt2000")
if (!all(need %in% names(data0))) {
  env <- new.env(parent = emptyenv())
  load(config$data$rawdata_path, envir = env)
  raw <- as.data.frame(env[[config$data$rawdata_obj]])
  if (!"Cesarean01" %in% names(raw) && "Delivery_Mode" %in% names(raw)) {
    dm <- trimws(as.character(raw$Delivery_Mode))
    raw$Cesarean01 <- as.integer(grepl("剖|Cesarean|cesarean|CS", dm, ignore.case = TRUE))
  }
  nw <- suppressWarnings(as.numeric(sub("/.*$", "", trimws(as.character(raw$Newborn_Weight)))))
  nw[is.finite(nw) & nw <= 0] <- NA_real_
  raw$Newborn_lt1500 <- as.integer(is.finite(nw) & nw < 1500)
  raw$Newborn_lt2000 <- as.integer(is.finite(nw) & nw < 2000)
  raw$APGAR_1min <- suppressWarnings(as.numeric(as.character(raw$APGAR_1min)))
  raw$APGAR_5min <- suppressWarnings(as.numeric(as.character(raw$APGAR_5min)))
  raw$Apgar1_lt8 <- as.integer(is.finite(raw$APGAR_1min) & raw$APGAR_1min < 8)
  raw$Apgar5_lt8 <- as.integer(is.finite(raw$APGAR_5min) & raw$APGAR_5min < 8)
  keep <- intersect(c(id, need), names(raw))
  map <- raw[, keep, drop = FALSE]
  map[[id]] <- as.character(map[[id]])
  data0[[id]] <- as.character(data0[[id]])
  for (cn in setdiff(keep, id)) data0[[cn]] <- NULL
  data0 <- merge(data0, map, by = id, all.x = TRUE, sort = FALSE)
}

# 默认中国四分类；稀有结局 GLM 直接用三分类（避免森林图大片 NE）
# Firth 脚本仍先试四分类，可估率<50% 再退三分类
data0_china4 <- .pe_add_pre_bmi_group(data0, "china4")
data0_china3 <- .pe_add_pre_bmi_group(data0, "china3")
cli::cli_alert_info(
  "Pre_BMI 四分类: {paste(names(table(data0_china4$Pre_BMI_Group)), '=', as.integer(table(data0_china4$Pre_BMI_Group)), collapse=', ')}"
)
cli::cli_alert_info(
  "Pre_BMI 三分类: {paste(names(table(data0_china3$Pre_BMI_Group)), '=', as.integer(table(data0_china3$Pre_BMI_Group)), collapse=', ')}"
)

outcomes <- config$pe_outcomes %||% list()
cli::cli_alert_info("重跑亚组: {paste(names(outcomes), collapse=', ')}")

for (ou in names(outcomes)) {
  spec <- outcomes[[ou]]
  oc <- as.character(spec$outcome_column %||% ou)[1L]
  cli::cli_h1("subgroup_incidence: {oc}")

  cfg_u <- config
  cfg_u$data$outcome_column <- oc
  cfg_u$incidence$outcome_var <- oc
  cfg_u$project$analysis_group <- as.character(spec$analysis_group %||% oc)[1L]
  cfg_u$project$reference_group <- as.character(spec$reference_group %||% "")[1L]
  if (!is.null(spec$disease_label) && nzchar(spec$disease_label)) {
    cfg_u$project$disease <- as.character(spec$disease_label)[1L]
  }
  cfg_u$project$output_dir <- file.path(out_base, "by_outcome", oc)

  sg_excl <- as.character((cfg_u$subgroup %||% list())$exclude_vars %||% character(0))
  sg_req <- as.character((cfg_u$subgroup %||% list())$required_subgroup_vars %||% character(0))
  outcome_like <- c(
    "GDM01", "Preterm34", "Preterm_delivery",
    "Cesarean01", "Apgar1_lt8", "Apgar5_lt8", "Newborn_lt1500", "Newborn_lt2000",
    "PE01", "Delivery_Mode", "Newborn_Weight_g", "APGAR_1min", "APGAR_5min"
  )
  sg_excl <- unique(c(sg_excl, setdiff(outcome_like, "Preterm_delivery"), oc, "GDM01"))
  sg_excl <- setdiff(sg_excl, "GDM")
  if (oc %in% c("Preterm34", "Preterm_delivery")) {
    sg_excl <- unique(c(sg_excl, "Preterm_delivery", "Preterm34"))
    sg_req <- setdiff(sg_req, c("Preterm_delivery", "Preterm34"))
  } else if (!"Preterm_delivery" %in% sg_req) {
    sg_req <- c(sg_req, "Preterm_delivery")
  }
  if (oc %in% c("GDM01", "GDM")) {
    sg_excl <- unique(c(sg_excl, "GDM", "GDM01"))
    sg_req <- setdiff(sg_req, c("GDM", "GDM01"))
  } else if (!"GDM" %in% sg_req) {
    sg_req <- c(sg_req, "GDM")
  }
  sg_req <- setdiff(sg_req, c("Pre_BMI", "Pre_BMI_subg"))
  if (!"Pre_BMI_Group" %in% sg_req) sg_req <- c(sg_req, "Pre_BMI_Group")
  cfg_u$subgroup <- utils::modifyList(
    cfg_u$subgroup %||% list(),
    list(exclude_vars = sg_excl, required_subgroup_vars = sg_req)
  )

  # 稀有结局 GLM：已知四分类低体重组事件极少 → 直接三分类；其余用四分类
  use3 <- .pe_is_rare_outcome(oc)
  data_use <- if (use3) data0_china3 else data0_china4
  cli::cli_alert_info(
    "{oc} Pre_BMI={if (use3) 'china3 (稀有结局合并)' else 'china4'} | 亚组={paste(sg_req, collapse=', ')}"
  )

  pl_u <- pipeline_unit
  pl_u$checkpoint$enable <- TRUE
  pl_u$checkpoint$dir <- file.path(out_base, "by_outcome", oc, "checkpoints")

  ctx_u <- shared_ctx
  ctx_u$config <- cfg_u
  ctx_u$data$imputed <- data_use
  if (!is.null(ctx_u$data$cleaned)) ctx_u$data$cleaned <- data_use
  ctx_u$results$vif_final_pass <- m2
  ctx_u$results$Model1Factors <- m1
  ctx_u$results$Model2Factors <- m2

  ok <- tryCatch({
    run_pipeline(
      root,
      config = cfg_u,
      pipeline = pl_u,
      run_opts = list(
        initial_ctx = ctx_u,
        only = "subgroup_incidence"
      )
    )
    TRUE
  }, error = function(e) {
    cli::cli_alert_danger("{oc} 失败: {conditionMessage(e)}")
    FALSE
  })
  if (ok) cli::cli_alert_success("完成 GLM 亚组: {oc}")
}

cli::cli_alert_success("全部结局 GLM 亚组重跑完成；接着跑 Firth（四分类优先，过稀退三分类）…")
status <- system2(
  "Rscript",
  file.path(root, "run/61_preeclampsia/run_61_pe_firth_subgroup_forest.R"),
  stdout = "", stderr = ""
)
if (!identical(as.integer(status), 0L)) {
  cli::cli_alert_warning("Firth 亚组脚本退出码: {status}")
} else {
  cli::cli_alert_success("Firth 亚组亦已更新")
}
