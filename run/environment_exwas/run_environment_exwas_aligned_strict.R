#!/usr/bin/env Rscript
# 严格纳排对齐试跑：
#   1) 对照仅 MCQ220=2（从未患癌），去掉其他癌症对照
#   2) 同时要求 WTDRD1>0 与 WTMEC2YR>0（膳食 ∩ MEC）
#   3) 实验室按原文 LOD 规则；膳食 log1p
#   4) Dong：分析物缺失>40% → 人缺失>1/3 → mice → 不加权 ExWAS/FDR
# 用法:
#   Rscript run_environment_exwas_aligned_strict.R --nutrition <csv> --out <dir> [--label name]
#
args <- commandArgs(trailingOnly = TRUE)
opt <- list(nutrition = NULL, out = NULL, label = "strict", workers = "4")
i <- 1L
while (i <= length(args)) {
  a <- args[[i]]
  if (a == "--nutrition" && i < length(args)) { opt$nutrition <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--out" && i < length(args)) { opt$out <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--label" && i < length(args)) { opt$label <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--workers" && i < length(args)) { opt$workers <- args[[i + 1L]]; i <- i + 2L
  } else stop("未知参数: ", a, call. = FALSE)
}
if (is.null(opt$nutrition) || is.null(opt$out)) stop("需要 --nutrition 与 --out", call. = FALSE)

ca <- commandArgs(trailingOnly = FALSE)
f <- grep("^--file=", ca, value = TRUE)
root <- if (length(f)) {
  normalizePath(file.path(dirname(sub("^--file=", "", f[[1]])), "..", ".."), winslash = "/")
} else getwd()
setwd(root)
Sys.setenv(EXWAS_WORKERS = opt$workers)
source(file.path(root, "R/environment_exwas_core.R"))
source(file.path(root, "R/environment_exwas_aligned.R"))

to_host_path <- function(p) {
  if (.Platform$OS.type != "windows") return(p)
  p <- chartr("\\", "/", p)
  if (grepl("^/mnt/[A-Za-z]/", p)) paste0(toupper(substr(p, 6, 6)), ":/", substring(p, 8)) else p
}
base <- to_host_path("/mnt/g/02block_result/51_gastric cancer/environment_41380607")
out <- to_host_path(opt$out)
exwas_ensure_dir(out)

nut_csv <- to_host_path(opt$nutrition)
base_r <- file.path(base, "data/D01_baseline_NHANES_0920.RData")

exwas_log("[", opt$label, "] 读取 142+53 营养/实验室宽表 + baseline")
raw0 <- exwas_aligned_load(nut_csv, base_r)
raw0 <- exwas_aligned_mediators(raw0)
n_age <- nrow(raw0)
dn_age <- sum(raw0$DN == 1, na.rm = TRUE)

# 1) 从未患癌对照
nc <- exwas_aligned_never_cancer_controls(raw0)
raw1 <- nc$data
exwas_log("从未患癌对照：去掉其他癌症对照 ", nc$n_dropped_other_cancer,
          " → n=", nrow(raw1), " 病例 ", sum(raw1$DN == 1, na.rm = TRUE))

# 2) 膳食 ∩ MEC
dm <- exwas_aligned_require_diet_mec(raw1)
raw <- dm$data
exwas_log("膳食∩MEC：剔除 ", dm$n_dropped, " → n=", nrow(raw),
          " 病例 ", sum(raw$DN == 1, na.rm = TRUE),
          " 权重对上 ", sum(is.finite(raw$WTMEC2YR_7) & is.finite(raw$WTDRD1_7)))

id_cols <- c("cycle", "SEQN", "RIDAGEYR", "RIAGENDR", "c1", "DN", "k", "pool", "MCQ220")
exposures_raw <- setdiff(names(raw), c(id_cols, exwas_aligned_dag_pool(),
  "WBC", "NeutrophilCount", "Lymphocytes", "Mononuclear_cell_count", "PlateletCount",
  "NEUT", "MONO", "NLR", "SII", "SIRI",
  "SDMVPSU", "SDMVSTRA",
  "WTINT2YR", "WTMEC2YR", "WTDRD1", "WTDR2D", "WTSA2YR", "WTSB2YR", "WTSC2YR", "WTSVOC2Y",
  "WTINT2YR_7", "WTMEC2YR_7", "WTDRD1_7", "WTDR2D_7", "WTSA2YR_7", "WTSB2YR_7", "WTSC2YR_7", "WTSVOC2Y_7"))
exposures_raw <- exposures_raw[vapply(exposures_raw, function(nm) is.numeric(exwas_to_num(raw[[nm]])), logical(1))]
exposures <- exwas_aligned_dedup(exposures_raw)
exwas_log("暴露列 ", length(exposures_raw), " → 去重(去DR2/SI/LA/DR1I)后 ", length(exposures))
utils::write.csv(
  data.frame(dropped = setdiff(exposures_raw, exposures)),
  file.path(out, "exposure_duplicates_dropped.csv"),
  row.names = FALSE
)

analyte <- exwas_aligned_analyte_keep(raw, exposures, max_missing = 0.40)
utils::write.csv(analyte$notes, file.path(out, "Table_S1a_analyte_keep.csv"), row.names = FALSE)
exwas_log("分析物保留 ", length(analyte$keep), " / ", length(exposures),
          "（缺失>40% 或零值过多已剔除）")

person <- exwas_aligned_drop_person_missing(raw, analyte$keep, max_frac = 1 / 3)
df <- person$data
exwas_log("人级缺失>1/3 剔除 ", person$n_excluded,
          " → 保留 ", nrow(df), " 例，病例 ", sum(df$DN == 1, na.rm = TRUE))

utils::write.csv(
  data.frame(
    step = c(
      "age>=20_assessable",
      "never_cancer_controls_MCQ220eq2",
      "diet_and_MEC_weights",
      "after_analyte_filter_pool",
      "after_person_missing_le_1_3"
    ),
    n = c(n_age, nrow(raw1), nrow(raw), nrow(raw), nrow(df)),
    cases = c(
      dn_age,
      sum(raw1$DN == 1, na.rm = TRUE),
      sum(raw$DN == 1, na.rm = TRUE),
      sum(raw$DN == 1, na.rm = TRUE),
      sum(df$DN == 1, na.rm = TRUE)
    ),
    n_exposures = c(length(exposures_raw), length(exposures_raw), length(exposures),
                    length(analyte$keep), length(analyte$keep)),
    note = c(
      "已排除2017-2018与2017-2020；暴露=原142并集DR1TOT53",
      paste0("对照仅MCQ220=2；去掉其他癌症对照", nc$n_dropped_other_cancer, "人"),
      paste0("WTDRD1>0 且 WTMEC2YR>0；剔除", dm$n_dropped, "人"),
      paste0("分析物缺失>40%后保留", length(analyte$keep), "列"),
      paste0("人对这", length(analyte$keep), "列缺失超过1/3则剔除；剔除", person$n_excluded, "人")
    ),
    stringsAsFactors = FALSE
  ),
  file.path(out, "Table_attrition_strict.csv"),
  row.names = FALSE
)

screened <- exwas_aligned_screen_by_family(df, analyte$keep)
df <- screened$data
keep <- screened$keep
fam <- exwas_aligned_family(sub("_(ln|bin)$", "", keep))
names(fam) <- keep
utils::write.csv(screened$notes, file.path(out, "Table_S1_exposure_screen.csv"), row.names = FALSE)
exwas_log("transform 后暴露 ", length(keep), "（膳食log1p / 实验室LOD）；分析 n=", nrow(df),
          " 病例 ", sum(df$DN == 1, na.rm = TRUE))

dag <- intersect(exwas_aligned_dag_pool(), names(df))
df <- exwas_aligned_as_model_frame(df, dag)
uni <- exwas_aligned_univariate(df, "DN", dag, 0.05)
vif <- exwas_aligned_vif_screen(df, "DN", uni$keep, 4)
covars <- vif$keep
exwas_log("协变量 DAG ", paste(dag, collapse = ","))
exwas_log("单因素通过 ", paste(uni$keep, collapse = ","))
exwas_log("VIF 后 ", paste(covars, collapse = ","))
utils::write.csv(uni$table, file.path(out, "covariate_univariate.csv"), row.names = FALSE)
utils::write.csv(vif$dropped, file.path(out, "covariate_vif_dropped.csv"), row.names = FALSE)
writeLines(c(covars, "",
             "单因素 p<0.05 才进入，Age 强制保留。",
             "严格纳排：MCQ220=2 对照；膳食∩MEC；实验室 LOD；142∪DR1TOT53。"),
           file.path(out, "covariate_final.txt"))

exwas_log("未插补 ExWAS")
tab_cc <- exwas_run_unweighted(df, "DN", keep, covars, fam)
utils::write.csv(tab_cc, file.path(out, "Table_S7_ExWAS_unimputed.csv"), row.names = FALSE)

exwas_log("mice m=5（严格纳排后队列）")
imp_cols <- unique(c("DN", keep, covars))
use <- df[, imp_cols, drop = FALSE]
use$DN <- exwas_to_num(use$DN)
for (nm in keep) use[[nm]] <- exwas_to_num(use[[nm]])
for (nm in covars) {
  if (is.character(use[[nm]]) || is.factor(use[[nm]])) use[[nm]] <- factor(use[[nm]])
}
set.seed(123456)
imp <- mice::mice(use, m = 5L, maxit = 5L, printFlag = FALSE, seed = 123456L)
completed <- mice::complete(imp, action = 1L)
for (nm in names(completed)) df[[nm]] <- completed[[nm]]
df <- exwas_aligned_as_model_frame(df, covars)

exwas_log("插补后 ExWAS")
tab <- exwas_run_unweighted(df, "DN", keep, covars, fam)
utils::write.csv(tab, file.path(out, "Table_2_ExWAS_imputed.csv"), row.names = FALSE)
exwas_log("FDR<0.05 ", sum(tab$q < 0.05, na.rm = TRUE), " / ", nrow(tab),
          " 最小q ", suppressWarnings(min(tab$q, na.rm = TRUE)))

if (requireNamespace("ggplot2", quietly = TRUE)) {
  plot_df <- tab[is.finite(tab$p), , drop = FALSE]
  plot_df$logp <- -log10(pmax(plot_df$p, 1e-300))
  plot_df$hit <- ifelse(!is.na(plot_df$q) & plot_df$q < 0.05, "FDR<0.05", "other")
  p <- ggplot2::ggplot(plot_df, ggplot2::aes(x = log(OR), y = logp, color = hit)) +
    ggplot2::geom_point() + ggplot2::theme_bw() +
    ggplot2::labs(title = "ExWAS after mice (strict)", x = "log(OR per IQR)", y = "-log10(p)")
  ggplot2::ggsave(file.path(out, "Figure_2_ExWAS_volcano.pdf"), p, width = 7, height = 5)
}

exwas_log("分层 ExWAS")
df$age60 <- ifelse(exwas_to_num(df$Age) < 60, "<60", ">=60")
strata <- list(
  age_lt60 = df$age60 == "<60",
  age_ge60 = df$age60 == ">=60"
)
glev <- levels(df$Gender)
if (length(glev) >= 1L) {
  for (g in glev) strata[[paste0("sex_", g)]] <- df$Gender == g
}
stab <- list()
for (nm in names(strata)) {
  sub <- df[which(strata[[nm]]), , drop = FALSE]
  cv <- setdiff(covars, if (grepl("^sex_", nm)) "Gender" else if (grepl("^age_", nm)) "Age" else character(0))
  one <- exwas_run_unweighted(sub, "DN", keep, cv, fam)
  one$stratum <- nm
  one$events <- sum(sub$DN == 1, na.rm = TRUE)
  stab[[nm]] <- one
}
utils::write.csv(do.call(rbind, stab), file.path(out, "Table_S3_S4_stratified_ExWAS.csv"), row.names = FALSE)

survey_int <- list(survey_weight = "WTINT2YR_7", survey_psu = "SDMVPSU", survey_strata = "SDMVSTRA")
if (requireNamespace("survey", quietly = TRUE) && exwas_has_survey(df, survey_int)) {
  des <- exwas_design(df, survey_int)
  sm <- survey::svyby(~Age, ~DN, des, survey::svymean, na.rm = TRUE)
  utils::write.csv(sm, file.path(out, "Table_1_age_survey.csv"), row.names = FALSE)
}

dr1 <- keep[grepl("^DR1", keep)]
exwas_log("ERS 第1日膳食 ", length(dr1))
if (length(dr1) >= 2L && requireNamespace("glmnet", quietly = TRUE)) {
  dd <- df[, c("DN", dr1), drop = FALSE]
  dd <- dd[stats::complete.cases(dd), , drop = FALSE]
  X <- as.matrix(dd[, dr1, drop = FALSE])
  yy <- dd$DN
  set.seed(2024)
  alphas <- seq(0, 1, length.out = 11)
  best <- NULL
  for (a in alphas) {
    cv <- tryCatch(glmnet::cv.glmnet(X, yy, family = "binomial", alpha = a, nfolds = 5L),
                   error = function(e) NULL)
    if (is.null(cv)) next
    dev <- min(cv$cvm)
    if (is.null(best) || dev < best$dev) best <- list(alpha = a, cv = cv, dev = dev)
  }
  if (!is.null(best)) {
    coefs <- as.matrix(stats::coef(best$cv, s = "lambda.min"))
    sel <- setdiff(rownames(coefs)[abs(coefs[, 1]) > 0], "(Intercept)")
    ok <- stats::complete.cases(df[, sel, drop = FALSE])
    df$ERS <- NA_real_
    df$ERS[ok] <- as.numeric(as.matrix(df[ok, sel, drop = FALSE]) %*% coefs[sel, 1])
    use <- df[is.finite(df$ERS), , drop = FALSE]
    iqr <- stats::IQR(use$ERS)
    if (!is.finite(iqr) || iqr == 0) iqr <- 1
    use$ERS_IQR <- use$ERS / iqr
    sw <- list(survey_weight = "WTDRD1_7", survey_psu = "SDMVPSU", survey_strata = "SDMVSTRA")
    rows <- list()
    for (spec in list(list(model = "Model1", covars = character(0)),
                      list(model = "Model2", covars = covars))) {
      if (exwas_has_survey(use, sw)) {
        est <- exwas_weighted_logit(use, "DN", "ERS_IQR", spec$covars, sw)
        weighted <- TRUE
      } else {
        est <- exwas_fit_one(use, "DN", "ERS_IQR", spec$covars)
        est <- est[, c("OR", "lo", "hi", "p")]
        weighted <- FALSE
      }
      rows[[length(rows) + 1L]] <- data.frame(model = spec$model, weighted = weighted, est,
                                              alpha = best$alpha, n_selected = length(sel))
    }
    ers_tab <- do.call(rbind, rows)
    utils::write.csv(ers_tab, file.path(out, "Table_ERS_logistic_weighted.csv"), row.names = FALSE)
    utils::write.csv(data.frame(exposure = sel), file.path(out, "Table_S5_ERS_selected.csv"), row.names = FALSE)
    ev <- exwas_aligned_evalue_or(ers_tab$OR[ers_tab$model == "Model2"], ers_tab$lo[ers_tab$model == "Model2"])
    utils::write.csv(data.frame(t(ev)), file.path(out, "Table_S11_Evalue_ERS.csv"), row.names = FALSE)
    exwas_log("ERS 入选 ", length(sel), " 加权=", ers_tab$weighted[1])

    if (exwas_has_survey(use, sw) && requireNamespace("splines", quietly = TRUE)) {
      des <- exwas_design(use, sw)
      f_lin <- stats::as.formula(paste("DN ~ ERS_IQR", if (length(covars)) paste("+", paste(covars, collapse = "+")) else ""))
      f_rcs <- stats::as.formula(paste(
        "DN ~ splines::ns(ERS_IQR, df = 2)",
        if (length(covars)) paste("+", paste(covars, collapse = "+")) else ""
      ))
      fit_l <- survey::svyglm(f_lin, design = des, family = stats::quasibinomial())
      fit_s <- tryCatch(survey::svyglm(f_rcs, design = des, family = stats::quasibinomial()), error = function(e) NULL)
      p_nl <- NA_real_
      if (!is.null(fit_s)) {
        p_nl <- tryCatch(stats::pchisq(max(0, fit_l$deviance - fit_s$deviance), df = 1, lower.tail = FALSE),
                         error = function(e) NA_real_)
      }
      writeLines(
        c("RCS knots=3 (ns df=2), weight=WTDRD1/7",
          paste0("p_nonlinear_approx=", p_nl)),
        file.path(out, "Figure_4_RCS_note.txt")
      )
    }
  }
}

# WQS：仅第1日膳食（混合物补充，不加权）
if (length(dr1) >= 2L && requireNamespace("gWQS", quietly = TRUE)) {
  options(future.globals.maxSize = Inf)
  dd <- df[, unique(c("DN", dr1, covars)), drop = FALSE]
  dd <- dd[stats::complete.cases(dd), , drop = FALSE]
  fml <- stats::as.formula(paste("DN ~ wqs", if (length(covars)) paste("+", paste(covars, collapse = "+")) else ""))
  suppressPackageStartupMessages(library(gWQS))
  fit <- tryCatch(
    gwqs(formula = fml, data = dd, mix_name = dr1, q = 4L, b = 100L,
         b1_pos = FALSE, validation = 0.6, family = "binomial", seed = 2024L),
    error = function(e) e
  )
  if (inherits(fit, "error")) {
    writeLines(conditionMessage(fit), file.path(out, "WQS_not_fit.txt"))
    exwas_log("WQS 未收敛")
  } else {
    utils::write.csv(fit$final_weights, file.path(out, "Table_WQS_weights.csv"), row.names = FALSE)
    writeLines("gWQS 无调查设计参数；主 ExWAS 不加权；ERS logistic 已用 WTDRD1/7。",
               file.path(out, "WQS_weight_note.txt"))
    exwas_log("WQS 完成")
  }
}

if ("ERS" %in% names(df) && any(is.finite(df$ERS))) {
  swm <- list(survey_weight = "WTMEC2YR_7", survey_psu = "SDMVPSU", survey_strata = "SDMVSTRA")
  med_rows <- list()
  for (med in c("WBC", "NEUT", "MONO", "SII", "NLR", "SIRI")) {
    use <- df[is.finite(df$ERS) & is.finite(df[[med]]), , drop = FALSE]
    if (!exwas_has_survey(use, swm) || nrow(use) < 50L) next
    des <- exwas_design(use, swm)
    a_f <- stats::as.formula(paste(med, "~ ERS", if (length(covars)) paste("+", paste(covars, collapse = "+")) else ""))
    b_f <- stats::as.formula(paste("DN ~ ERS +", med, if (length(covars)) paste("+", paste(covars, collapse = "+")) else ""))
    fa <- tryCatch(survey::svyglm(a_f, design = des), error = function(e) NULL)
    fb <- tryCatch(survey::svyglm(b_f, design = des, family = stats::quasibinomial()), error = function(e) NULL)
    if (is.null(fa) || is.null(fb)) next
    a <- coef(fa)["ERS"]; b <- coef(fb)[med]
    med_rows[[med]] <- data.frame(
      mediator = med, a = a, b = b, indirect = unname(a * b),
      direct = unname(coef(fb)["ERS"]), n = nrow(use), weighted = TRUE
    )
  }
  if (length(med_rows)) {
    utils::write.csv(do.call(rbind, med_rows), file.path(out, "Table_S6_mediation_product.csv"), row.names = FALSE)
    exwas_log("中介 ", length(med_rows), " 个")
  }
}

exwas_log("严格纳排试跑写完 ", out)
