#!/usr/bin/env Rscript
# 毒物 ExWAS 下游（对齐 Dong 2026 EWAS-new）
# 默认：前列腺 Age>=45 · 肌酐校正 · 要尿肌酐 · ExWAS 粗模型 FDR 命中
# → adaptive elastic-net ERS → WTSA2YR 加权 logistic → RCS → WQS → 炎症中介(探索)
#
# 用法:
#   Rscript run_environment_exwas_toxicant_downstream.R \
#     --disease prostate --min-age 45 --covars-set none --require-urine-creat \
#     --hits-csv <Table_2b...> --out <dir> [--bootstrap 200]
#
args <- commandArgs(trailingOnly = TRUE)
opt <- list(
  disease = "prostate", out = NULL, min_age = 45L,
  require_urine_creat = TRUE, creat_adjust = TRUE,
  require_weight = NULL,
  covars_set = "none", include_smoke = FALSE,
  hits_csv = NULL, bootstrap = 200L, wqs_boot = 200L,
  weight_col = "WTSA2YR"
)
i <- 1L
while (i <= length(args)) {
  a <- args[[i]]
  if (a == "--disease" && i < length(args)) { opt$disease <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--out" && i < length(args)) { opt$out <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--min-age" && i < length(args)) { opt$min_age <- as.integer(args[[i + 1L]]); i <- i + 2L
  } else if (a == "--hits-csv" && i < length(args)) { opt$hits_csv <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--bootstrap" && i < length(args)) { opt$bootstrap <- as.integer(args[[i + 1L]]); i <- i + 2L
  } else if (a == "--wqs-boot" && i < length(args)) { opt$wqs_boot <- as.integer(args[[i + 1L]]); i <- i + 2L
  } else if (a == "--covars-set" && i < length(args)) { opt$covars_set <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--require-urine-creat") { opt$require_urine_creat <- TRUE; i <- i + 1L
  } else if (a == "--no-creat-adjust") { opt$creat_adjust <- FALSE; i <- i + 1L
  } else if (a == "--require-weight" && i < length(args)) {
    opt$require_weight <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--require-weight") {
    opt$require_weight <- "WTSA2YR"; i <- i + 1L
  } else if (a == "--include-smoke") { opt$include_smoke <- TRUE; i <- i + 1L
  } else if (a == "--no-smoke") { opt$include_smoke <- FALSE; i <- i + 1L
  } else stop("未知参数: ", a, call. = FALSE)
}
if (is.null(opt$out)) stop("需要 --out", call. = FALSE)
opt$disease <- match.arg(opt$disease, c("prostate", "breast", "pancancer"))
opt$covars_set <- match.arg(opt$covars_set, c("none", "age", "demo", "full"))

ca <- commandArgs(trailingOnly = FALSE)
f <- grep("^--file=", ca, value = TRUE)
root <- if (length(f)) {
  normalizePath(file.path(dirname(sub("^--file=", "", f[[1]])), "..", ".."), winslash = "/")
} else getwd()
setwd(root)
source(file.path(root, "R/environment_exwas_core.R"))
source(file.path(root, "R/environment_exwas_aligned.R"))
source(file.path(root, "R/environment_exwas_toxicant.R"))
source(file.path(root, "R/environment_exwas_toxicant_downstream.R"))

to_host_path <- function(p) {
  if (.Platform$OS.type != "windows") return(p)
  p <- chartr("\\", "/", p)
  if (grepl("^/mnt/[A-Za-z]/", p)) paste0(toupper(substr(p, 6, 6)), ":/", substring(p, 8)) else p
}
data_dir <- to_host_path("/mnt/g/02block_result/51_gastric cancer/environment_41380607/data")
out <- to_host_path(opt$out)
exwas_ensure_dir(out)

exwas_log("==== toxicant downstream ", opt$disease, " Age>=", opt$min_age,
          " ExWAS-covars=", opt$covars_set, " ====")

# 1) 重建与筛查一致的分析表
built <- exwas_tox_build_cancer_table(opt$disease, data_dir, min_age = opt$min_age)
d0 <- built$data
if (isTRUE(opt$require_urine_creat)) {
  ucr0 <- exwas_to_num(d0$URXUCR)
  d0 <- d0[is.finite(ucr0) & ucr0 > 0, , drop = FALSE]
}
if (!is.null(opt$require_weight) && nzchar(opt$require_weight)) {
  wcol0 <- opt$require_weight
  if (!wcol0 %in% names(d0)) stop("缺少权重列 ", wcol0, call. = FALSE)
  ww0 <- exwas_to_num(d0[[wcol0]])
  d0 <- d0[is.finite(ww0) & ww0 > 0, , drop = FALSE]
  exwas_log("下游要求 ", wcol0, ">0 → n=", nrow(d0),
            " 病例=", sum(d0$DN == 1, na.rm = TRUE))
}
tox <- intersect(built$tox_cols, names(d0))
if (isTRUE(opt$creat_adjust)) {
  d1 <- exwas_tox_creatinine_adjust(d0, tox, creat_col = "URXUCR")$data
} else {
  d1 <- d0
}
scr <- exwas_tox_screen_transform(d1, tox)
person <- exwas_tox_drop_person_missing(
  scr$data, scr$keep, max_frac = 1 / 3, cycle_col = "cycle",
  raw_from_model = sub("_(ln|bin)$", "", scr$keep)
)
df <- person$data
df <- exwas_tox_merge_inflam(df, data_dir)
df$SDMVSTRA_cyc <- as.integer(
  interaction(as.character(df$cycle), exwas_to_num(df$SDMVSTRA), drop = TRUE, lex.order = TRUE)
)

# ERS/RCS/中介 Model2：原文前述协变量；泛癌含 Gender；默认无 Smoke
sex_strat <- opt$disease != "pancancer"
want_m2 <- exwas_tox_cancer_covars(
  sex_stratified = sex_strat, include_smoke = isTRUE(opt$include_smoke)
)
covars_m2 <- character(0)
for (v in want_m2) {
  if (v == "PIR" && "PIR_cat" %in% names(df)) covars_m2 <- c(covars_m2, "PIR_cat")
  else if (v == "BMI" && "BMI_cat" %in% names(df)) covars_m2 <- c(covars_m2, "BMI_cat")
  else if (v %in% names(df)) covars_m2 <- c(covars_m2, v)
}
covars_m2 <- unique(covars_m2)
if (length(covars_m2)) {
  mr <- vapply(covars_m2, function(v) mean(is.na(df[[v]])), numeric(1))
  covars_m2 <- setdiff(covars_m2, names(mr)[mr > 0.40])
}
df <- exwas_aligned_as_model_frame(df, covars_m2)
exwas_log("Model2 covars: ", paste(covars_m2, collapse = ", "))

# 2) FDR 命中池
hits_path <- if (!is.null(opt$hits_csv) && nzchar(opt$hits_csv)) {
  to_host_path(opt$hits_csv)
} else {
  file.path(
    dirname(out),
    paste0("Output_", opt$disease, "_toxicant_exwas_age", opt$min_age,
           "_requireUCR_cov", opt$covars_set),
    "Table_2b_ExWAS_FDR_hits.csv"
  )
}
if (!file.exists(hits_path)) {
  # 回退默认粗模型命中
  hits_path <- file.path(
    "G:/02block_result/51_gastric cancer/environment_41380607",
    "Output_prostate_toxicant_exwas_age45_requireUCR_covnone",
    "Table_2b_ExWAS_FDR_hits.csv"
  )
  hits_path <- to_host_path(hits_path)
}
hits <- utils::read.csv(hits_path, stringsAsFactors = FALSE)
hit_cols <- if ("exposure" %in% names(hits)) hits$exposure else character(0)
hit_cols <- intersect(hit_cols, scr$keep)
# Dong 2026：ERS 在全暴露框架下做 adaptive elastic-net（非仅 FDR 命中）
ers_pool <- intersect(scr$keep, names(df))
if (length(ers_pool) < 2L) stop("ERS 全暴露池 <2", call. = FALSE)
exwas_log("ERS 全暴露池 n=", length(ers_pool),
          "；FDR 命中(供 WQS/对照)=", length(hit_cols), " from ", basename(hits_path))
utils::write.csv(
  data.frame(
    exposure = ers_pool,
    in_fdr_hits = ers_pool %in% hit_cols,
    source = "scr$keep_full_exposure_pool",
    stringsAsFactors = FALSE
  ),
  file.path(out, "Table_S0_hit_pool.csv"), row.names = FALSE
)

# 3) Adaptive elastic-net ERS（gcdnet；11α×50λ；Z-score）
ers_fit <- exwas_tox_fit_adaptive_enet(
  df, "DN", ers_pool,
  n_boot = as.integer(opt$bootstrap),
  seed = 123456L,
  use_gcdnet = TRUE,
  nlambda = 50L,
  lambda_min = 1e-3,
  lambda_max = 1e2
)
utils::write.csv(ers_fit$freq, file.path(out, "Table_S5_ERS_bootstrap_inclusion.csv"), row.names = FALSE)
utils::write.csv(
  data.frame(
    exposure = ers_fit$selected,
    coef = as.numeric(ers_fit$beta[ers_fit$selected]),
    stringsAsFactors = FALSE
  ),
  file.path(out, "Table_S5_ERS_selected.csv"), row.names = FALSE
)
utils::write.csv(
  data.frame(
    alpha = ers_fit$alpha, lambda = ers_fit$lambda, lambda2 = ers_fit$lambda2,
    n_selected = length(ers_fit$selected),
    n_model = ers_fit$n_model, n_events = ers_fit$n_events,
    n_boot = ers_fit$n_boot, gcdnet_used = ers_fit$gcdnet_used,
    n_pool = length(ers_pool)
  ),
  file.path(out, "Table_S5_ERS_tuning.csv"), row.names = FALSE
)
if (!is.null(ers_fit$alpha_path)) {
  utils::write.csv(ers_fit$alpha_path, file.path(out, "Table_S5_ERS_alpha_path.csv"), row.names = FALSE)
}
# 标准化参数（评分必须同源）
utils::write.csv(
  data.frame(
    exposure = names(ers_fit$center),
    center = unname(ers_fit$center),
    scale = unname(ers_fit$scale),
    is_binary = unname(ers_fit$is_binary[names(ers_fit$center)]),
    stringsAsFactors = FALSE
  ),
  file.path(out, "Table_S5_ERS_standardize.csv"), row.names = FALSE
)
exwas_log("ERS 入选 ", length(ers_fit$selected), " / ", length(ers_pool),
          " alpha=", signif(ers_fit$alpha, 3),
          " lambda=", signif(ers_fit$lambda, 3),
          " gcdnet=", ers_fit$gcdnet_used)

df$ERS <- exwas_tox_score_ers(
  df, ers_fit$beta,
  center = ers_fit$center, scale = ers_fit$scale, is_binary = ers_fit$is_binary
)
# 持久化 fit 供 Fig4 B/C 重绘
saveRDS(ers_fit, file.path(out, "ERS_adaptive_enet_fit.rds"))

# 4) 加权 ERS 关联（原文 Model1 未调整 / Model2 全协变量）
# 无正权重者在加权模型内自然剔除
wcol <- opt$weight_col
if (!wcol %in% names(df)) stop("缺少权重列 ", wcol, call. = FALSE)
assoc <- exwas_tox_ers_assoc_table(df, covars_m2, weight_col = wcol)
utils::write.csv(assoc$table, file.path(out, "Table_ERS_logistic_weighted.csv"), row.names = FALSE)
ev <- tryCatch(
  exwas_aligned_evalue_or(
    assoc$table$OR[assoc$table$model == "Model2_continuous"][1],
    assoc$table$lo[assoc$table$model == "Model2_continuous"][1]
  ),
  error = function(e) c(evalue = NA_real_, evalue_ci = NA_real_)
)
utils::write.csv(data.frame(t(ev)), file.path(out, "Table_S11_Evalue_ERS.csv"), row.names = FALSE)

# 5) RCS
sw <- list(survey_weight = wcol, survey_psu = "SDMVPSU", survey_strata = "SDMVSTRA_cyc")
p_nl <- exwas_tox_ers_rcs_note(assoc$data, covars_m2, sw, file.path(out, "Figure_4_RCS_note.txt"))
exwas_log("RCS p_nonlinear≈", signif(p_nl, 4))

# 6) WQS（对齐 Dong Fig7/S7：筛后大面板进混合，非仅 FDR 命中；q=4；b 可用 --wqs-boot）
wqs_pool <- unique(c(ers_pool, hit_cols))
wqs_pool <- intersect(wqs_pool, names(assoc$data))
if (length(wqs_pool) >= 2L && requireNamespace("gWQS", quietly = TRUE)) {
  options(future.globals.maxSize = Inf)
  dd <- assoc$data
  # 多周期跨面板：剔缺失率过高者后中位数填补（与 ERS 操作层同精神）
  miss_w <- vapply(wqs_pool, function(nm) mean(!is.finite(exwas_to_num(dd[[nm]]))), numeric(1))
  mix_cols <- names(miss_w)[is.finite(miss_w) & miss_w <= 0.55]
  if (length(mix_cols) < 2L) mix_cols <- intersect(ers_fit$selected, names(dd))
  cols_w <- unique(c("DN", mix_cols, covars_m2))
  cols_w <- cols_w[cols_w %in% names(dd)]
  dw <- dd[, cols_w, drop = FALSE]
  for (nm in mix_cols) {
    if (!nm %in% names(dw)) next
    v <- exwas_to_num(dw[[nm]])
    med <- stats::median(v[is.finite(v)], na.rm = TRUE)
    if (!is.finite(med)) med <- 0
    v[!is.finite(v)] <- med
    dw[[nm]] <- v
  }
  dw <- dw[stats::complete.cases(dw), , drop = FALSE]
  hit_cols_wqs <- mix_cols
  exwas_log("WQS mix 列=", length(hit_cols_wqs), " (full screened panel) n=", nrow(dw))
  fml <- stats::as.formula(
    paste("DN ~ wqs", if (length(intersect(covars_m2, names(dw)))) {
      paste("+", paste(intersect(covars_m2, names(dw)), collapse = "+"))
    } else "")
  )
  suppressPackageStartupMessages(library(gWQS))
  try_pos_first <- isTRUE(opt$disease %in% c("pancancer", "breast"))
  pos_order <- if (try_pos_first) c(TRUE, FALSE) else c(FALSE, TRUE)
  fit_w <- NULL
  for (bp in pos_order) {
    fit_w <- tryCatch(
      gwqs(
        formula = fml, data = dw, mix_name = intersect(hit_cols_wqs, names(dw)),
        q = 4L, b = as.integer(opt$wqs_boot), b1_pos = bp,
        validation = 0.6, family = "binomial", seed = 123456L
      ),
      error = function(e) e
    )
    if (!inherits(fit_w, "error")) {
      exwas_log("WQS b1_pos=", bp, " 收敛")
      break
    }
  }
  if (inherits(fit_w, "error")) {
    writeLines(conditionMessage(fit_w), file.path(out, "WQS_not_fit.txt"))
    exwas_log("WQS 未收敛: ", conditionMessage(fit_w))
  } else {
    utils::write.csv(fit_w$final_weights, file.path(out, "Table_WQS_weights.csv"), row.names = FALSE)
    ct <- tryCatch(as.data.frame(summary(fit_w)$coefficients), error = function(e) NULL)
    if (!is.null(ct)) utils::write.csv(ct, file.path(out, "Table_WQS_coefficients.csv"))
    writeLines(
      c(
        "gWQS complementary mixture; no native survey design (paper same package).",
        paste0("q=4; b=", opt$wqs_boot, "; mix=full screened toxicant panel (Dong Fig7/S7); seed=123456"),
        paste0("n_mix=", length(hit_cols_wqs), "; FDR-hit subset size=", length(hit_cols)),
        "ERS logistic uses WTSA2YR survey weights."
      ),
      file.path(out, "WQS_weight_note.txt")
    )
    exwas_log("WQS 完成")
  }
} else {
  writeLines("gWQS unavailable or <2 mix columns", file.path(out, "WQS_not_fit.txt"))
}

# 7) 探索性中介：对齐 Dong — mediation::mediate B=1000（风险差）；癌症 6 中介非牙周照搬
# 正式 Fig5/S4 重建入口：run/environment_exwas/rebuild_pancancer_fig5_mediation.R
meds <- if (isTRUE(opt$disease %in% c("pancancer", "breast", "prostate", "gastric"))) {
  exwas_tox_cancer_mediators_default()
} else {
  c("WBC", "NEUT", "MONO", "NLR", "SII", "SIRI")
}
meds <- meds[meds %in% names(df)]
med_rows <- list()
use0 <- df[is.finite(exwas_to_num(df$ERS)), , drop = FALSE]
iqr_ers <- stats::IQR(use0$ERS, na.rm = TRUE)
if (is.finite(iqr_ers) && iqr_ers > 0) use0$ERS_IQR <- use0$ERS / iqr_ers else use0$ERS_IQR <- use0$ERS
for (med in meds) {
  if (sum(is.finite(exwas_to_num(use0[[med]]))) < 200L) next
  exwas_log("mediate ", med)
  res <- tryCatch(
    exwas_tox_mediate_one(
      use0, treat = "ERS_IQR", mediator = med, outcome = "DN",
      covars = intersect(covars_m2, names(use0)),
      weight_col = if ("WTSA2YR" %in% names(use0)) "WTSA2YR" else sw,
      sims = 1000L, seed = 123456L + match(med, meds)
    ),
    error = function(e) NULL
  )
  if (!is.null(res)) med_rows[[med]] <- res$table
}
if (length(med_rows)) {
  utils::write.csv(do.call(rbind, med_rows),
                   file.path(out, "Table_S6_mediation_exploratory.csv"), row.names = FALSE)
  exwas_log("中介行数=", length(med_rows), " (mediation_boot)")
} else {
  writeLines(
    "Exploratory mediation: mediate() failed or insufficient inflam biomarkers.",
    file.path(out, "Figure_5_mediation_unavailable.txt")
  )
  exwas_log("中介未产出可用行")
}

# 8) 分层 ExWAS（原文 Fig3：Age<60 / >=60；粗模型命中池上重估）
exwas_log("分层 ExWAS（Age / 命中池）")
df$age60 <- ifelse(exwas_to_num(df$Age) < 60, "<60", ">=60")
strata <- list(
  age_lt60 = which(df$age60 == "<60"),
  age_ge60 = which(df$age60 == ">=60")
)
if ("Smoke" %in% names(df)) {
  sm <- as.character(df$Smoke)
  never <- grepl("Never|never|从不|No", sm) | sm %in% c("0", "Never smoker", "Never Smoker")
  strata$never_smoker <- which(never)
}
stab <- list()
for (nm in names(strata)) {
  idx <- strata[[nm]]
  if (!length(idx) || length(idx) < 80L) next
  sub <- df[idx, , drop = FALSE]
  one <- exwas_run_unweighted(sub, "DN", hit_cols, character(0))
  one$stratum <- nm
  one$n_stratum <- nrow(sub)
  one$n_events <- sum(sub$DN == 1, na.rm = TRUE)
  stab[[nm]] <- one
}
if (length(stab)) {
  stab_df <- do.call(rbind, stab)
  utils::write.csv(stab_df, file.path(out, "Table_S3_S4_stratified_ExWAS_crudeHits.csv"),
                   row.names = FALSE)
  exwas_log("分层 ExWAS 行数=", nrow(stab_df))
}

# 9) 命中毒物相关矩阵（原文 Fig4A 风格）
if (requireNamespace("ggplot2", quietly = TRUE) && length(hit_cols) >= 2L) {
  Xm <- df[, hit_cols, drop = FALSE]
  for (nm in names(Xm)) Xm[[nm]] <- exwas_to_num(Xm[[nm]])
  ok <- stats::complete.cases(Xm)
  if (sum(ok) >= 50L) {
    R <- stats::cor(Xm[ok, , drop = FALSE], use = "pairwise.complete.obs")
    utils::write.csv(R, file.path(out, "Table_S_toxicant_correlation.csv"))
    lab <- built$code
    rn <- rownames(R)
    disp <- if (!is.null(lab) && all(c("Labels", "Exposure") %in% names(lab))) {
      mp <- stats::setNames(lab$Exposure, lab$Labels)
      raw <- sub("_(ln|bin)$", "", rn)
      ifelse(is.na(mp[raw]), rn, mp[raw])
    } else rn
    rownames(R) <- disp; colnames(R) <- disp
    rdf <- as.data.frame(as.table(R), stringsAsFactors = FALSE)
    names(rdf) <- c("x", "y", "r")
    p <- ggplot2::ggplot(rdf, ggplot2::aes(x = x, y = y, fill = r)) +
      ggplot2::geom_tile() +
      ggplot2::scale_fill_gradient2(limits = c(-1, 1), midpoint = 0) +
      ggplot2::theme_bw(base_size = 8) +
      ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 90, hjust = 1, vjust = 0.5)) +
      ggplot2::labs(title = "Correlation among ExWAS FDR-hit toxicants", x = NULL, y = NULL)
    ggplot2::ggsave(file.path(out, "Figure_4A_toxicant_correlation.pdf"), p, width = 9, height = 8)
  }
}

# 10) ERS 火山/森林式简表已有；补 ExWAS 命中 volcano（粗）
if (requireNamespace("ggplot2", quietly = TRUE) && file.exists(hits_path)) {
  ht <- utils::read.csv(hits_path, stringsAsFactors = FALSE)
  if (all(c("OR", "p") %in% names(ht))) {
    ht$logOR <- log(pmax(ht$OR, 1e-12))
    ht$logp <- -log10(pmax(ht$p, 1e-300))
    ht$lab <- if ("exposure_name" %in% names(ht)) ht$exposure_name else ht$exposure
    p2 <- ggplot2::ggplot(ht, ggplot2::aes(x = logOR, y = logp, label = lab)) +
      ggplot2::geom_point(color = "#B2182B") +
      ggplot2::geom_text(size = 2.5, vjust = -0.4, check_overlap = TRUE) +
      ggplot2::theme_bw() +
      ggplot2::labs(
        title = paste0(opt$disease, " ExWAS crude FDR hits (Age>=", opt$min_age, ")"),
        x = "log(OR per IQR)", y = "-log10(p)"
      )
    ggplot2::ggsave(file.path(out, "Figure_2_ExWAS_crude_hits_volcano.pdf"), p2, width = 7, height = 5)
  }
}

# README
writeLines(c(
  paste0("# Toxicant ExWAS downstream — ", opt$disease),
  "Aligned to Dong 2026 EWAS-new (methods):",
  paste0("- Analytic: Age>=", opt$min_age, "; creat_adjust=", opt$creat_adjust,
         "; require_URXUCR=", opt$require_urine_creat),
  paste0("- ExWAS hit pool: ", basename(hits_path), " (covars_set=", opt$covars_set, ")"),
  "  NOTE: paper ExWAS was fully adjusted; this run continues from USER-chosen crude hits.",
  "- ERS: adaptive elastic-net (glmnet alpha grid 11 + adaptive penalty; gcdnet optional)",
  paste0("  bootstrap inclusion B=", opt$bootstrap, " (paper 1000; raise --bootstrap 1000 if needed)"),
  "- ERS association: survey-weighted logistic WTSA2YR; Model1 crude / Model2 full covars (no Smoke default)",
  "- RCS: ns(df=2) ≈ 3 knots; p_nonlinear from deviance difference",
  paste0("- WQS: gWQS q=4 b=", opt$wqs_boot, " on FDR-hit mix (paper b=1000)"),
  "- Mediation: exploratory product-method on available WBC/NEUT/MONO/NLR/SII/SIRI/CRP",
  paste0("- ERS selected n=", length(ers_fit$selected), ": ", paste(ers_fit$selected, collapse = ", "))
), file.path(out, "README_toxicant_downstream.txt"))

exwas_log("写完 ", out)
print(assoc$table)
print(utils::head(ers_fit$freq, 15))
