#!/usr/bin/env Rscript
# Sensitivity: polytomous LCA (poLCA) on WHO-DAS Likert items DAS1–12.
# Main-text profiles remain continuous LPA K=4.
# Note: poLCA is unrestricted polytomous LCA; category codes retain order but
# the measurement model is not cumulative-logit ordinal thresholds (needs Mplus).

suppressPackageStartupMessages({
  if (!requireNamespace("poLCA", quietly = TRUE)) {
    install.packages("poLCA", repos = "https://cloud.r-project.org")
  }
  library(poLCA)
})

rel_ent <- function(P) {
  if (is.null(P) || !is.matrix(P) || ncol(P) < 2L) return(NA_real_)
  P <- pmax(as.matrix(P), .Machine$double.eps)
  P <- P / rowSums(P)
  n <- nrow(P)
  k <- ncol(P)
  as.numeric(1 - sum(-P * log(P)) / (n * log(k)))
}

root <- "/mnt/g/02block_result/63_SSD/LPA_Network_Mediaton_42214160/by_index/main_full_sample"
ck <- file.path(root, "checkpoints/step04_latent_profile_tidylpa.rds")
obj <- readRDS(ck)
dat <- obj$ctx$data$cleaned
items <- paste0("DAS", 1:12)
X <- as.data.frame(lapply(dat[items], function(z) suppressWarnings(as.numeric(z))))
keep <- stats::complete.cases(X)
X <- X[keep, , drop = FALSE]
message("n complete = ", nrow(X))
message("item ranges (raw):")
print(sapply(X, function(z) range(z, na.rm = TRUE)))

# poLCA requires integers 1..R
for (nm in names(X)) {
  X[[nm]] <- as.integer(X[[nm]] - min(X[[nm]], na.rm = TRUE) + 1L)
}

fml <- as.formula(paste0("cbind(", paste(names(X), collapse = ","), ") ~ 1"))
set.seed(1234)
min_n <- 30L
min_prop <- 0.04
nrep <- 10L  # balance runtime vs stability

rows <- list()
for (k in 1:5) {
  message("Fitting K=", k, " (nrep=", nrep, ") ...")
  fit <- tryCatch(
    poLCA::poLCA(fml, data = X, nclass = k, nrep = nrep, maxiter = 4000, verbose = FALSE),
    error = function(e) {
      message("K=", k, " failed: ", conditionMessage(e))
      NULL
    }
  )
  if (is.null(fit)) next
  pred <- fit$predclass
  tab <- table(factor(pred, levels = seq_len(k)))
  n_unique <- sum(as.integer(tab) > 0L)
  prop <- as.numeric(tab) / sum(tab)
  pos <- as.integer(tab) > 0L
  rows[[length(rows) + 1L]] <- data.frame(
    K = k,
    AIC = as.numeric(fit$aic),
    BIC = as.numeric(fit$bic),
    loglik = as.numeric(fit$llik),
    npar = as.integer(fit$npar),
    min_class_n = min(as.integer(tab)[pos]),
    min_class_prop = min(prop[pos]),
    n_unique = n_unique,
    degenerate = (k > 1L && n_unique < k),
    entropy = rel_ent(fit$posterior),
    class_counts = paste(as.integer(tab), collapse = "|"),
    stringsAsFactors = FALSE
  )
}

fit_df <- do.call(rbind, rows)
print(fit_df)

elig <- fit_df[
  !fit_df$degenerate &
    fit_df$min_class_n >= min_n &
    fit_df$min_class_prop >= min_prop,
  ,
  drop = FALSE
]
if (nrow(elig)) {
  star <- elig[which.min(elig$BIC), , drop = FALSE]
} else {
  cand <- fit_df[!fit_df$degenerate & fit_df$K >= 2L, , drop = FALSE]
  star <- if (nrow(cand)) cand[which.min(cand$BIC), , drop = FALSE] else fit_df[1L, , drop = FALSE]
}
message(
  "Selected K*=", star$K[1],
  " BIC=", round(star$BIC[1], 2),
  " entropy=", round(star$entropy[1], 3),
  " counts=", star$class_counts[1]
)

dir.create(file.path(root, "Tables"), showWarnings = FALSE, recursive = TRUE)
step_tab <- file.path(root, "step04_latent_profile_tidylpa/Tables")
dir.create(step_tab, showWarnings = FALSE, recursive = TRUE)
write.csv(fit_df, file.path(root, "Tables/Table_ordinal_LCA_fit_indices.csv"), row.names = FALSE)
write.csv(fit_df, file.path(step_tab, "Table_ordinal_LCA_fit_indices.csv"), row.names = FALSE)

supp_dir <- file.path(root, "summary_results/Tables")
dir.create(supp_dir, showWarnings = FALSE, recursive = TRUE)
pub <- data.frame(
  K = fit_df$K,
  AIC = round(fit_df$AIC, 2),
  BIC = round(fit_df$BIC, 2),
  loglik = round(fit_df$loglik, 3),
  min_class_n = fit_df$min_class_n,
  min_class_prop = round(fit_df$min_class_prop, 4),
  n_unique = fit_df$n_unique,
  degenerate = fit_df$degenerate,
  Entropy = ifelse(is.na(fit_df$entropy), NA, round(fit_df$entropy, 3)),
  class_counts = fit_df$class_counts,
  stringsAsFactors = FALSE
)

xlsx <- file.path(supp_dir, "Table S3. Polytomous LCA fit indices.xlsx")
wb <- openxlsx::createWorkbook()
openxlsx::addWorksheet(wb, "Sheet1")
title <- "Table S3. Polytomous LCA fit indices on WHO-DAS items (sensitivity)"
openxlsx::writeData(wb, "Sheet1", title, startRow = 1, startCol = 1)
openxlsx::writeData(wb, "Sheet1", pub, startRow = 2, startCol = 1)
note <- paste0(
  "Sensitivity to continuous Gaussian LPA (Table 2). DAS1–DAS12 entered as categorical Likert levels via poLCA ",
  "(polytomous LCA: category codes retain order; measurement model is unrestricted polytomous, not cumulative-logit ",
  "ordinal thresholds as in Mplus). Gates aligned with main analysis: min class n≥30, prop≥0.04; reject degenerate ",
  "(n_unique<K). Under these gates K*=", star$K[1], " (counts ", star$class_counts[1], "; entropy=",
  round(star$entropy[1], 3), "). Main-text profiles remain continuous LPA K=4."
)
openxlsx::writeData(wb, "Sheet1", note, startRow = 2 + nrow(pub) + 2, startCol = 1)
st <- openxlsx::createStyle(fontName = "Times New Roman")
stb <- openxlsx::createStyle(fontName = "Times New Roman", textDecoration = "bold")
openxlsx::addStyle(wb, "Sheet1", stb, rows = 1:2, cols = seq_len(ncol(pub)), gridExpand = TRUE)
openxlsx::addStyle(
  wb, "Sheet1", st,
  rows = 3:(2 + nrow(pub) + 3), cols = seq_len(ncol(pub)), gridExpand = TRUE
)
openxlsx::saveWorkbook(wb, xlsx, overwrite = TRUE)
message("wrote ", xlsx)

saveRDS(
  list(fit = fit_df, star = star, n = nrow(X), seed = 1234L, nrep = nrep),
  file.path(root, "Tables/ordinal_LCA_summary.rds")
)

# Append Methods note if missing
methods <- file.path(root, "summary_results/Methods_statistical_analysis.md")
if (file.exists(methods)) {
  txt <- paste(readLines(methods, warn = FALSE), collapse = "\n")
  if (!grepl("Polytomous LCA|poLCA", txt, ignore.case = TRUE)) {
    add <- paste0(
      "\n\n## Sensitivity: polytomous LCA on DAS items\n\n",
      "As a scale-assumption sensitivity analysis, DAS1–DAS12 were also modelled as categorical Likert ",
      "indicators with polytomous latent class analysis (R package poLCA; ", nrep, " random starts). ",
      "This retains ordered category codes but does not impose cumulative-logit ordinal thresholds ",
      "(Mplus-style ordinal LCA was unavailable). The same class-size and non-degeneracy gates as the ",
      "main LPA were applied. Under these gates the polytomous LCA preferred K = ", star$K[1],
      " (see Table S3). Primary profile membership for all subsequent analyses remained the continuous ",
      "Gaussian LPA solution (K = 4).\n"
    )
    writeLines(paste0(txt, add), methods)
    message("Methods updated")
  }
}

message("DONE")
