# Regression: prognosis_v2 S4/Fig5 must stay continuous-index unadjusted (no Cox LP)
# Run: Rscript tests/test_pv2_index_roc_unadjusted.R

.root <- {
  if (dir.exists("/mnt/e/01block/01Block-new-Final")) "/mnt/e/01block/01Block-new-Final"
  else if (dir.exists("E:/01block/01Block-new-Final")) "E:/01block/01Block-new-Final"
  else getwd()
}
setwd(.root)

src <- file.path(.root, "R/pv2_index_roc.R")
stopifnot(file.exists(src))
sys.source(src, envir = environment())

# ---- API smoke ----
set.seed(42)
n <- 400L
score <- rnorm(n)
event <- rbinom(n, 1L, plogis(0.8 * score))
fit <- pv2_index_roc_fit(event = event, score = score, index_lab = "DEMO")
stopifnot(!is.null(fit), grepl("continuous, unadjusted", fit$table_row$Index, fixed = TRUE))
stopifnot(nrow(fit$curve_df) > 5L, is.finite(fit$auc))

fn <- pv2_index_roc_footnotes("DEMO", "28-day all-cause mortality")
stopifnot(any(grepl("unadjusted", fn, ignore.case = TRUE)))
stopifnot(!any(grepl("Cox LP|linear predictor", fn, ignore.case = TRUE)))

# ---- audit catches Cox LP wording ----
bad <- pv2_index_roc_audit_delivery_text(
  "Discrimination using the Cox linear predictor of ALBI + Age, Sodium, GCS"
)
stopifnot(length(bad) >= 1L)

good <- pv2_index_roc_audit_delivery_text(paste(
  "ALBI (continuous, unadjusted)",
  "Discrimination for 28-day all-cause mortality using continuous ALBI alone (unadjusted).",
  "Youden index; AUC with DeLong 95% CI."
))
stopifnot(length(good) == 0L)

# ---- callers must source engine + must not keep roc_lp_covs / Cox LP builders ----
callers <- c(
  "run/prognosis_v2/rebuild_copd_tables_hip.R",
  "run/prognosis_v2/rebuild_copd_figs_hip.R",
  "run/prognosis_v2/_rebuild_stroke_anlr_tables_hip_layout.R",
  "run/prognosis_v2/_fix_stroke_anlr_fig4_7_hip.R",
  "run/prognosis_v2/remirror_hip_aki_pub.R"
)
forbid <- c(
  ".roc_lp_covs",
  "roc_covs_prefer",
  "predict(fit, type = \"lp\")",
  "predict(fit, type=\"lp\")",
  "Cox LP",
  "linear predictor of"
)
for (rel in callers) {
  p <- file.path(.root, rel)
  stopifnot(file.exists(p))
  txt <- paste(readLines(p, warn = FALSE), collapse = "\n")
  if (!grepl("pv2_index_roc", txt, fixed = TRUE)) {
    stop(rel, " must source/use pv2_index_roc")
  }
  hit <- forbid[vapply(forbid, function(f) grepl(f, txt, fixed = TRUE), logical(1))]
  # allow comments that say 禁 Cox LP
  hit <- setdiff(hit, character(0))
  bad_hit <- hit[hit != "Cox LP" | grepl("Index = paste0\\(.*Cox LP", txt)]
  # stricter: any of the LP construction tokens
  lp_tokens <- c(".roc_lp_covs", "roc_covs_prefer", "predict(fit, type = \"lp\")", "predict(fit, type=\"lp\")")
  bad_lp <- lp_tokens[vapply(lp_tokens, function(f) grepl(f, txt, fixed = TRUE), logical(1))]
  if (length(bad_lp)) {
    stop(rel, " still contains forbidden Cox-LP ROC tokens: ", paste(bad_lp, collapse = ", "))
  }
  if (grepl("Index = paste0\\(.*Cox LP", txt) || grepl('paste0\\(IDX, " Cox LP"\\)', txt)) {
    stop(rel, " still labels Index as Cox LP")
  }
}

# ---- gate file must audit S4/Fig5 ----
gate <- paste(readLines(file.path(.root, "R/pv2_pub_p0_gate.R"), warn = FALSE), collapse = "\n")
need_gate <- c("s4_fig5_roc_audit", "Table S4", "Figure 5", "continuous-index ROC")
miss_g <- need_gate[!vapply(need_gate, function(p) grepl(p, gate, fixed = TRUE), logical(1))]
if (length(miss_g)) stop("pv2_pub_p0_gate.R missing S4/Fig5 hooks: ", paste(miss_g, collapse = ", "))

message("OK: pv2_index_roc unadjusted path + caller/gate guards")
