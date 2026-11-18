## WPR Gate E：双库 LM 交集 + 两库均显著 → 统一 RDW → remirror Fig4
root_eng <- "/mnt/e/01block/01Block-new-Final"
proj <- "/mnt/g/02block_result/36_spesis/prediction_41194138"
setwd(proj)
Sys.setenv(MEDICAL_BLOCKS_ROOT = root_eng)
options(warn = 1)

source(file.path(root_eng, "R/utils.R"))
source(file.path(root_eng, "R/model3_required.R"))
source(file.path(root_eng, "R/dual_db_harmonize.R"))
source(file.path(root_eng, "R/cox_gate.R"))
source(file.path(root_eng, "R/pipeline_runner.R"))
source(file.path(root_eng, "configs/indices/composite_index_vars.R"))
source(file.path(root_eng, "R/survival_dual_batch_runner.R"))
source(file.path(root_eng, "R/incidence_dual_batch_runner.R"))
source(file.path(root_eng, "R/pub_figure_export.R"))
.med_common <- file.path(root_eng, "Blocks/20_mediation/00mediation_common.R")
if (file.exists(.med_common)) source(.med_common, local = FALSE)

source(file.path(proj, "config_survival.R"))
cfg <- config
cfg$project$root <- proj
cfg$project$output_dir <- proj

ix <- "WPR"
db_seq <- c("nhanes", "mimic")
cfg$dual_db$checkpoint_base <- file.path(proj, "checkpoints/by_index", ix)
cfg$dual_db$enable <- TRUE
cfg$dual_db$harmonization_dir <- file.path(proj, "checkpoints/_global_harmonization")
# 续跑需可读 ck；config 里可能关了
pipeline_regular_batch$checkpoint$enable <- TRUE
if (!is.null(pipeline)) pipeline$checkpoint$enable <- TRUE

# 强制 Gate E 行为
cfg$mediation_prognosis$dual_db_lock_shared_lm_mediators <- TRUE
cfg$mediation_prognosis$dual_db_lock_best_mediator <- TRUE
cfg$mediation_prognosis$dual_db_require_both_significant <- TRUE
cfg$mediation_prognosis$dual_db_force_rerun_mediation <- TRUE
# Jin Fig4 主文路径图
cfg$mediation_prognosis$figure_kind <- "main_figure"
cfg$mediation_prognosis$figure_number <- 4L
cfg$mediation_prognosis$bump_counter <- FALSE

pipe <- pipeline_regular_batch
stopifnot("mediation_prognosis" %in% pipe$blocks)

cli::cli_h1("WPR Gate E apply")
locked <- survival_batch_apply_gate_e_mediation(
  proj, cfg, ix, db_seq, pipe, result_ctx = NULL
)
if (is.null(locked)) {
  cli::cli_alert_danger("Gate E 锁定失败")
  quit(status = 1L)
}
cli::cli_alert_success(
  "locked best={locked$best_mediator}; n_med={length(locked$mediators)}"
)

# 收口拼图 + summary（不整链 finalize，只镜像中介图/表）
tryCatch({
  incidence_batch_finalize_index_outputs(proj, cfg, ix, db_seq)
}, error = function(e) {
  cli::cli_alert_warning("finalize: {conditionMessage(e)}")
})

# 保底：双库路径图拼成 Fig4
tryCatch({
  if (exists("dual_db_combine_paired_figures", mode = "function")) {
    pub <- file.path(proj, "by_index", paste0("【success】", ix))
    if (!dir.exists(pub)) pub <- file.path(proj, "by_index", ix)
    dual_db_combine_paired_figures(pub, cfg)
  }
}, error = function(e) {
  cli::cli_alert_warning("combine figures: {conditionMessage(e)}")
})

# summary_results Fig4：从指标根 Figures 同步
sr_fig <- file.path(proj, "by_index", paste0("【success】", ix), "summary_results", "Figures")
idx_fig <- file.path(proj, "by_index", paste0("【success】", ix), "Figures")
fig4_pat <- "Figure 4.*Mediation.*\\.pdf$"
if (dir.exists(idx_fig) && dir.exists(file.path(sr_fig, "pdf"))) {
  hits <- list.files(idx_fig, pattern = fig4_pat, full.names = TRUE, ignore.case = TRUE)
  if (!length(hits) && dir.exists(file.path(idx_fig, "pdf"))) {
    hits <- list.files(file.path(idx_fig, "pdf"), pattern = fig4_pat, full.names = TRUE, ignore.case = TRUE)
  }
  if (length(hits)) {
    dest <- file.path(sr_fig, "pdf", basename(hits[[1L]]))
    # 若拼图名不同，统一写到既有 Fig4 名
    dest_std <- file.path(
      sr_fig, "pdf",
      "Figure 4. Mediation path diagram of WPR and In-hospital all-cause mortality.pdf"
    )
    file.copy(hits[[1L]], dest_std, overwrite = TRUE)
    cli::cli_alert_success("synced Fig4 → summary_results: {dest_std}")
  }
}

cli::cli_alert_success("DONE Gate E WPR")
