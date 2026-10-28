#!/usr/bin/env Rscript
# 重画 Fig2：仅 MIMIC-IV、期刊风 KM（对齐顶栏图例 + 蓝/红/绿线型 + 左下角 p）
# 用法：
#   Rscript run/ml/redraw_fig2_km_pretty.R \
#     --index-root "/mnt/g/.../【success】SAR+CrCV" \
#     --indices SAR,CrCV

args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(a, b) if (!is.null(a) && length(a) && !is.na(a[[1]]) &&
                             !(is.character(a) && !nzchar(a[[1]]))) a else b

get_arg <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i >= length(args)) return(default)
  args[[i + 1L]]
}

index_root <- get_arg(
  "--index-root",
  "/mnt/g/02block_result/33_AKI/prognosis_ml_40346649/by_index/\u3010success\u3011SAR+CrCV"
)
idx_csv <- get_arg("--indices", "SAR,CrCV")
indices <- strsplit(idx_csv, ",", fixed = TRUE)[[1]]
indices <- trimws(indices)

engine <- Sys.getenv("MEDICAL_BLOCKS_ENGINE", unset = "/mnt/e/01block/01Block-new-Final")
setwd(engine)
source("R/utils.R")
source("R/prognosis_reference_assoc.R")
source("R/ml_reference_assoc_figures.R")
source("R/ml_reference_paper_profile.R")
source("R/pub_figure_export.R")

.ref_assoc_set_indices(indices)
ia <- indices[[1]]; ib <- indices[[2]]

# 分析帧：assoc bundle 的 imputed（全分析集）
study_guess <- c(
  "/mnt/g/DockerHome/5003/medical-blocks-studies/studies/33_AKI_SAR_CrCV_28\u5929\u6b7b\u4ea1",
  file.path(dirname(dirname(index_root)), "..")
)
mi_ckpt <- NULL
for (sg in study_guess) {
  cand <- file.path(sg, "checkpoints/by_index/SAR+CrCV/MIMIC_IV/ml_assoc_bundle.rds")
  if (file.exists(cand)) { mi_ckpt <- cand; break }
}
if (is.null(mi_ckpt)) {
  cand2 <- list.files(file.path(index_root, "MIMIC_IV"),
                      pattern = "ml_assoc_bundle", recursive = TRUE,
                      full.names = TRUE)
  if (length(cand2)) mi_ckpt <- cand2[[1]]
}
stopifnot(!is.null(mi_ckpt), file.exists(mi_ckpt))

mi <- readRDS(mi_ckpt)
ctx <- mi$ctx %||% mi
config <- ctx$config %||% mi$config
analysis <- ctx$data$imputed
stopifnot(is.data.frame(analysis))
stopifnot(all(c(ia, ib, "futime", "fustatus") %in% names(analysis)))

# 锁定链：必须用 lit final 的 derived authority（hash 与 Joint 列一致）
derived_path <- file.path(
  index_root, "publication_literature_final", "authority", "checkpoints",
  "by_index", "SAR+CrCV_REF", "MIMIC_IV", "step01_reference_derived.rds"
)
if (!file.exists(derived_path)) {
  derived_path <- file.path(
    "/mnt/g/DockerHome/5003/medical-blocks-studies/studies/33_AKI_SAR_CrCV_28\u5929\u6b7b\u4ea1",
    "by_index/\u3010success\u3011SAR+CrCV/publication_literature_final/authority/checkpoints/by_index/SAR+CrCV_REF/MIMIC_IV/step01_reference_derived.rds"
  )
}
stopifnot(file.exists(derived_path))
der <- readRDS(derived_path)
train_aug <- der$ctx$data$train
stopifnot(is.data.frame(train_aug))

cutoff <- NULL
provenance <- reference_trusted_development(
  train_aug, checkpoint_path = derived_path
)
joint_lock <- reference_lock_tertile_cutpoints(train_aug, ia, ib, provenance)
sosm_lock <- reference_lock_tertile_cutpoints(train_aug, ia, ia, provenance)
wpr_lock <- reference_lock_tertile_cutpoints(train_aug, ib, ib, provenance)

db_frames <- list(list(
  name = "MIMIC_IV", short = "MIMIC-IV", data = analysis,
  outcome_cfg = config, joint_lock = joint_lock,
  sosm_lock = sosm_lock, wpr_lock = wpr_lock,
  rcs_locks = NULL, assoc_ctx = ctx, train_ref = train_aug
))

out_dirs <- unique(c(
  file.path(index_root, "publication_literature_final", "Figures", "pdf"),
  file.path(index_root, "summary_result", "Figures", "pdf"),
  # DockerHome mirror if present
  "/mnt/g/DockerHome/5003/medical-blocks-studies/studies/33_AKI_SAR_CrCV_28\u5929\u6b7b\u4ea1/by_index/\u3010success\u3011SAR+CrCV/publication_literature_final/Figures/pdf",
  "/mnt/g/DockerHome/5003/medical-blocks-studies/studies/33_AKI_SAR_CrCV_28\u5929\u6b7b\u4ea1/by_index/\u3010success\u3011SAR+CrCV/summary_result/Figures/pdf"
))

fig_name <- sprintf("Figure 2. KM %s %s joint groups.pdf", ia, ib)
res <- ref_assoc_fig2_km(db_frames, cutoff = cutoff,
                         out_pdf = file.path(tempdir(), fig_name))
stopifnot(!is.null(res$path), file.exists(res$path))
message("built: ", res$path)
message("panels:\n", paste(utils::capture.output(print(res$panels[,
  c("panel", "column", "legend_title", "logrank_p", "n")])), collapse = "\n"))

for (od in out_dirs) {
  if (!dir.exists(dirname(dirname(od)))) next
  dir.create(od, recursive = TRUE, showWarnings = FALSE)
  dest <- file.path(od, fig_name)
  ok <- file.copy(res$path, dest, overwrite = TRUE)
  message(if (isTRUE(ok)) "wrote " else "FAIL ", dest)
}

# refresh four formats for lit + summary（out_dirs 指向 .../Figures/pdf）
fig_roots <- unique(dirname(out_dirs))
for (fr in fig_roots) {
  if (!dir.exists(fr) || !dir.exists(file.path(fr, "pdf"))) next
  message("ensure formats: ", fr)
  tryCatch(
    pub_figure_ensure_formats(fr, config = list(pub_figures = list(dpi = 600L))),
    error = function(e) message("ensure failed: ", conditionMessage(e))
  )
}

# image_information
md_txt <- paste0(
  "# Figure 2. KM ", ia, " ", ib, " joint groups\n\n",
  "## \u56fe\u9762\u8bf4\u660e\n\n",
  "MIMIC-IV \u603b\u4f53\u961f\u5217 Kaplan\u2013Meier \u4e09\u9762\u677f\uff1a",
  ia, " \u4e09\u5206\u4f4d\u3001", ib, " \u4e09\u5206\u4f4d\u3001",
  ia, "+", ib, " \u8054\u5408\u7ec4\u3002",
  "\u6bcf\u9762\u677f\u9876\u680f\u56fe\u4f8b\u4e3a\u6307\u6807\u540d + \u7ec4\u522b\uff08\u84dd/\u7ea2/\u7eff\uff0c\u5b9e/\u70b9/\u865a\u7ebf\uff09\uff1b",
  "\u5de6\u4e0b\u89d2\u4e3a Log-rank p\u3002\u4e0d\u542b eICU \u5173\u8054\u9762\u677f\u3002\n\n",
  "### \u56fe\u4e0a\u6807\u6ce8\n\n",
  paste(sprintf(
    "- %s: n=%s, %s",
    res$panels$legend_title,
    format(res$panels$n, big.mark = ","),
    vapply(res$panels$logrank_p, .ref_assoc_km_p_lab, character(1))
  ), collapse = "\n"),
  "\n\n## \u5206\u6790\u4e0a\u4e0b\u6587\n\n",
  "- \u66b4\u9732: ", ia, " / ", ib, " / \u8054\u5408\u7ec4\n",
  "- \u7ed3\u5c40: 28 \u5929\u5168\u56e0\u6b7b\u4ea1\n",
  "- \u6837\u672c\u91cf: MIMIC-IV \u5206\u6790\u96c6 n=",
  format(res$panels$n[[1]], big.mark = ","), "\n",
  "- Grouping: tertile (\u4e0e\u4e3b\u6587\u95f8\u95e8\u4e00\u81f4)\n",
  "- \u6570\u636e\u5e93: MIMIC-IV\uff08\u5355\u5e93\uff09\n"
)
for (fr in fig_roots) {
  md_dir <- file.path(fr, "image_information")
  if (!dir.exists(fr)) next
  dir.create(md_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(md_txt, file.path(md_dir, sub("\\.pdf$", ".md", fig_name)),
             useBytes = TRUE)
}

message("DONE")
