#!/usr/bin/env Rscript
# 关联图正经重画（MIMIC-only）：Fig3/4/5/6 + Fig S1，禁止裁切双库面板。
#   Rscript run/ml/redraw_assoc_figs_mimic_only.R \
#     --index-root ".../【success】SAR+CrCV" --indices SAR,CrCV

args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(a, b) if (!is.null(a) && length(a) && !(is.character(a) &&
  !nzchar(a[[1]]))) a else b
get_arg <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i >= length(args)) return(default)
  args[[i + 1L]]
}

index_root <- get_arg(
  "--index-root",
  "/mnt/g/02block_result/33_AKI/prognosis_ml_40346649/by_index/\u3010success\u3011SAR+CrCV"
)
indices <- trimws(strsplit(get_arg("--indices", "SAR,CrCV"), ",", fixed = TRUE)[[1]])

engine <- Sys.getenv("MEDICAL_BLOCKS_ENGINE", unset = "/mnt/e/01block/01Block-new-Final")
setwd(engine)
source("R/utils.R")
source("R/prognosis_reference_assoc.R")
source("R/prognosis_landmark_ph.R")
source("R/ml_reference_assoc_figures.R")
source("R/ml_reference_paper_profile.R")
source("R/pub_figure_export.R")

.ref_assoc_set_indices(indices)
ia <- indices[[1]]; ib <- indices[[2]]
cutoff <- NULL  # overall-only

mi_ckpt <- "/mnt/g/DockerHome/5003/medical-blocks-studies/studies/33_AKI_SAR_CrCV_28\u5929\u6b7b\u4ea1/checkpoints/by_index/SAR+CrCV/MIMIC_IV/ml_assoc_bundle.rds"
if (!file.exists(mi_ckpt)) {
  cands <- list.files(file.path(index_root, "MIMIC_IV"), pattern = "ml_assoc",
                      recursive = TRUE, full.names = TRUE)
  stopifnot(length(cands) > 0)
  mi_ckpt <- cands[[1]]
}
mi <- readRDS(mi_ckpt)
ctx <- mi$ctx %||% mi
config <- ctx$config %||% mi$config
analysis <- ctx$data$imputed
stopifnot(is.data.frame(analysis))

derived_path <- file.path(
  index_root, "publication_literature_final/authority/checkpoints/by_index",
  "SAR+CrCV_REF/MIMIC_IV/step01_reference_derived.rds"
)
if (!file.exists(derived_path)) {
  derived_path <- file.path(
    "/mnt/g/DockerHome/5003/medical-blocks-studies/studies/33_AKI_SAR_CrCV_28\u5929\u6b7b\u4ea1",
    "by_index/\u3010success\u3011SAR+CrCV/publication_literature_final/authority/checkpoints/by_index/SAR+CrCV_REF/MIMIC_IV/step01_reference_derived.rds"
  )
}
stopifnot(file.exists(derived_path))
train_aug <- readRDS(derived_path)$ctx$data$train
provenance <- reference_trusted_development(train_aug, checkpoint_path = derived_path)
joint_lock <- reference_lock_tertile_cutpoints(train_aug, ia, ib, provenance)
sosm_lock <- reference_lock_tertile_cutpoints(train_aug, ia, ia, provenance)
wpr_lock <- reference_lock_tertile_cutpoints(train_aug, ib, ib, provenance)
rcs_locks <- stats::setNames(list(
  reference_lock_grouped_rcs(train_aug, ia, provenance),
  reference_lock_grouped_rcs(train_aug, ib, provenance)
), c(ia, ib))

db_frames <- list(list(
  name = "MIMIC_IV", short = "MIMIC-IV", data = analysis,
  outcome_cfg = config, joint_lock = joint_lock,
  sosm_lock = sosm_lock, wpr_lock = wpr_lock,
  rcs_locks = rcs_locks, assoc_ctx = ctx, train_ref = train_aug
))

tmp <- tempfile("assoc_redraw_")
dir.create(tmp)
message("staging ", tmp)

# ---- Fig3 RCS ----
f3 <- file.path(tmp, sprintf("Figure 3. Grouped RCS %s %s.pdf", ia, ib))
r3 <- ref_assoc_fig3_rcs(db_frames, cutoff = cutoff, grid_n = 40L, out_pdf = f3)
message("Fig3 OK ", r3$path)

# ---- Fig4 ROC ----
f4 <- file.path(tmp, sprintf("Figure 4. ROC %s %s joint scores.pdf", ia, ib))
r4 <- ref_assoc_fig4_roc(db_frames, cutoff = cutoff, out_pdf = f4)
message("Fig4 OK ", r4$path)

# ---- Fig5 landmark（eICU=NULL）----
f5 <- file.path(tmp, "Figure 5. Landmark before after Cox.pdf")
covs <- intersect(c("Age", "Gender"), names(train_aug))
r5 <- ref_assoc_fig5_landmark(
  train_aug = train_aug,
  mimic_analysis = analysis,
  eicu_analysis = NULL,
  provenance = provenance,
  outcome_cfg = config,
  covariates = covs,
  cutoff = cutoff,
  joint_lock = joint_lock,
  out_pdf = f5
)
message("Fig5 OK ", r5$path)

# ---- Fig6 forest（仅 MIMIC → 两面板）----
f6 <- file.path(tmp, "Figure 6. Forest tertile association.pdf")
r6 <- tryCatch(
  ref_assoc_fig6_forest(db_frames, cutoff = cutoff, out_pdf = f6),
  error = function(e) {
    message("Fig6 skip: ", conditionMessage(e)); NULL
  }
)
if (!is.null(r6$path)) message("Fig6 OK ", r6$path)

# ---- Fig S1 PH（仅 MIMIC 单面板）----
f_s1 <- file.path(tmp, "Figure S1. Time-varying PH coefficient trends (Overall).pdf")
d <- data.frame(analysis)
d$Group <- as.numeric(reference_apply_joint_tertiles(d, joint_lock)$group)
d <- .ref_assoc_event01(d, "fustatus", config)
d$T <- suppressWarnings(as.numeric(d$futime))
d$D <- as.integer(d$fustatus)
covs0 <- intersect(c("Age", "Gender"), names(d))
need <- c("T", "D", "Group", covs0)
dd <- d[stats::complete.cases(d[, need, drop = FALSE]), , drop = FALSE]
dd <- dd[is.finite(dd$T) & dd$T > 0 & dd$T <= 28, , drop = FALSE]
form <- if (length(covs0)) {
  stats::as.formula(sprintf("survival::Surv(T, D) ~ Group + %s",
                            paste(covs0, collapse = " + ")))
} else {
  stats::as.formula("survival::Surv(T, D) ~ Group")
}
fit <- survival::coxph(form, data = dd, x = TRUE, y = TRUE, model = TRUE)
zph <- survival::cox.zph(fit)
p_g <- as.numeric(as.data.frame(zph$table)[
  match("Group", rownames(zph$table)), "p"])
grDevices::pdf(f_s1, width = 6.4, height = 5.2, onefile = TRUE)
graphics::par(mar = c(5.4, 4.4, 3.6, 1.4))
idx <- match("Group", colnames(zph$y)); if (is.na(idx)) idx <- 1L
survival:::plot.cox.zph(
  zph, resid = TRUE, se = TRUE, df = 4, nsmo = 40, var = idx,
  xlab = "Time (days)", ylab = "Beta(t) for Group",
  main = "MIMIC-IV\nCOX Regression PH Test Trend Plot_Group",
  col = 1, lwd = 1.2, lty = 1:2, pch = 1, cex = 0.55
)
graphics::abline(h = 0, col = "pink", lty = 2, lwd = 1.5)
graphics::mtext(
  sprintf("Schoenfeld P (Group) = %s",
          format.pval(p_g, digits = 3, eps = 1e-3)),
  side = 1, line = 3.8, cex = 0.85, adj = 0
)
graphics::mtext(
  paste0(
    "Fig. S1  PH assumption trends (MIMIC-IV overall). Group = ",
    ia, "+", ib, " joint tertile score; Age+Gender adjusted."
  ),
  side = 1, line = 5.0, cex = 0.72, adj = 0
)
grDevices::dev.off()
message("FigS1 OK ", f_s1)

# ---- 分发到 lit final + summary_result（两面镜子）----
dest_roots <- unique(c(
  file.path(index_root, "publication_literature_final", "Figures"),
  file.path(index_root, "summary_result", "Figures"),
  "/mnt/g/DockerHome/5003/medical-blocks-studies/studies/33_AKI_SAR_CrCV_28\u5929\u6b7b\u4ea1/by_index/\u3010success\u3011SAR+CrCV/publication_literature_final/Figures",
  "/mnt/g/DockerHome/5003/medical-blocks-studies/studies/33_AKI_SAR_CrCV_28\u5929\u6b7b\u4ea1/by_index/\u3010success\u3011SAR+CrCV/summary_result/Figures"
))
built <- c(f3, f4, f5, f_s1)
if (!is.null(r6$path) && file.exists(r6$path)) built <- c(built, r6$path)

for (fr in dest_roots) {
  if (!dir.exists(dirname(fr))) next
  pdf_dir <- file.path(fr, "pdf")
  dir.create(pdf_dir, recursive = TRUE, showWarnings = FALSE)
  for (src in built) {
    if (!file.exists(src)) next
    ok <- file.copy(src, file.path(pdf_dir, basename(src)), overwrite = TRUE)
    message(if (isTRUE(ok)) "wrote " else "FAIL ", file.path(pdf_dir, basename(src)))
  }
  tryCatch(
    pub_figure_ensure_formats(fr, config = list(pub_figures = list(dpi = 600L))),
    error = function(e) message("ensure failed: ", conditionMessage(e))
  )
}

message("DONE redraw assoc figs (no crop)")
