###############################################################################
#  exwas_gastric_assemble — 读入胃癌营养宽表（142 个营养指标已含结局）
#
#  register_block: "exwas_gastric_assemble"
#  典型流水线: exwas_gastric_assemble → exwas_unweighted → ers_elastic_net
#
#  config$exwas_gastric_assemble = list(
#    nutrition_csv = "NHANES_nutrition_142_sample_39149.csv",
#    outcome_col   = "DN",
#    id_cols       = c("cycle", "SEQN", "RIDAGEYR", "RIAGENDR", "c1", "k", "pool")
#  )
###############################################################################

block_exwas_gastric_assemble <- function(ctx, ...) {
  root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
  source(file.path(root, "R/environment_exwas_core.R"), local = FALSE)
  cfg <- ctx$config$exwas_gastric_assemble %||% list()
  path <- cfg$nutrition_csv
  if (is.null(path) || !nzchar(path)) {
    stop("请设置 exwas_gastric_assemble$nutrition_csv 为营养宽表", call. = FALSE)
  }
  raw <- exwas_read_csv(path)
  names(raw) <- sub("^\ufeff", "", names(raw))
  y <- cfg$outcome_col %||% "DN"
  raw[[y]] <- exwas_to_num(raw[[y]])
  id_cols <- cfg$id_cols %||% c(
    "cycle", "SEQN", "RIDAGEYR", "RIAGENDR", "c1", "k", "pool", "DN"
  )
  exposures <- setdiff(names(raw), c(id_cols, y))
  ctx$data$cleaned <- raw
  ctx$results$exwas_outcome <- y
  ctx$results$exwas_exposure_cols <- exposures
  ctx$results$exwas_mode <- "nutrition"
  ctx$results$exwas_n <- nrow(raw)
  ctx$results$exwas_events <- sum(raw[[y]] == 1, na.rm = TRUE)
  exwas_log("营养宽表 n=", nrow(raw), " 事件=", ctx$results$exwas_events,
            " 营养列=", length(exposures))
  ctx
}

register_block(
  "exwas_gastric_assemble",
  block_exwas_gastric_assemble,
  "胃癌结局与 142 个营养指标宽表"
)
