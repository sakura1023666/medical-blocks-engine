###############################################################################
#  crm_multivariate_prognosis — 包装 multivariate_prognosis（全因死亡多因素 Cox）
#  原因：01block_multivariate_prognosis 对 NHANES 硬停转 multivariate_nhanes（加权 logistic），
#  与本套路「按死亡筛协变量」不符。本块临时去 NHANES 标记后调用原预后多因素块，
#  不修改 Blocks/01–69。
###############################################################################

block_crm_multivariate_prognosis <- function(ctx, ...) {
  if (!exists("block_multivariate_prognosis", mode = "function", envir = .GlobalEnv)) {
    root <- ctx$config$project$root %||% getwd()
    fp <- file.path(root, "Blocks/07_multivariate/01block_multivariate_prognosis.R")
    if (!file.exists(fp)) {
      stop("crm_multivariate_prognosis: 找不到 multivariate_prognosis 源文件: ", fp, call. = FALSE)
    }
    sys.source(fp, envir = .GlobalEnv)
  }
  if (!exists("block_multivariate_prognosis", mode = "function", envir = .GlobalEnv)) {
    stop("crm_multivariate_prognosis: 未加载 block_multivariate_prognosis", call. = FALSE)
  }
  old_db <- ctx$config$project$database
  old_dt <- ctx$config$project$database_type
  # 避开 .is_nhanes_db() 的 nhanes|nhance 匹配
  ctx$config$project$database <- "CRM_survey"
  ctx$config$project$database_type <- "CRM_survey"
  # 复用 multivariate_prognosis 配置段（若仅写了 multivariate_prognosis）
  if (is.null(ctx$config$multivariate_prognosis)) {
    ctx$config$multivariate_prognosis <- list(sig_cutoff = 0.05, pause_enable = FALSE)
  }
  ctx <- block_multivariate_prognosis(ctx, ...)
  ctx$config$project$database <- old_db
  ctx$config$project$database_type <- old_dt
  ctx$results$crm_multivariate_prognosis <- list(
    wrapped = "multivariate_prognosis",
    note = "NHANES 库绕过 multivariate_nhanes 硬停，按全因死亡筛 Model2"
  )
  ctx
}

register_block(
  "crm_multivariate_prognosis",
  block_crm_multivariate_prognosis,
  "CRM：全因死亡多因素 Cox 筛选（包装 multivariate_prognosis）"
)
