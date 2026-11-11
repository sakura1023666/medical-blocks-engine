###############################################################################
#  ml_index_summary_results.R — 指标级 summary_results 收口（全项目复用）
#
#  落盘：by_index/【success】<INDEX>/summary_results/
#    交付白名单（与 pub_delivery_whitelist 一致）：
#      Figures/  Tables/
#      Methods_statistical_analysis.md
#      Methods_software_versions.txt
#      *中期*.pdf
#  用于单库 / 双库 ML 发病预测；config：
#    config$ml_batch$write_index_summary_results = TRUE
#    config$pub$index_summary_results_dir = "summary_results"  # 或 summary_result
###############################################################################

#' TCF / 多算法融合（sklearn RSCV + TOPSIS）Methods 正文
ml_index_methods_statistical_lines_tcf <- function(config = NULL) {
  cfg <- config %||% list()
  proj <- cfg$project %||% list()
  pmid <- as.character(proj$literature_pmid %||% "")[1L]
  mi <- cfg$imputation %||% list()
  m <- suppressWarnings(as.integer(mi$m %||% 5L)[1L])
  if (!is.finite(m) || m < 1L) m <- 5L
  mi_method <- as.character(mi$method %||% "mice")[1L]
  fit_on <- tolower(trimws(as.character(mi$fit_on %||% "train")[1L]))
  seed_split <- suppressWarnings(as.integer(
    (cfg$train_validation %||% list())$seed %||%
      (cfg$splitting %||% list())$seed %||% 42L
  )[1L])
  train_ratio <- suppressWarnings(as.numeric(
    (cfg$train_validation %||% list())$train_ratio %||%
      (cfg$splitting %||% list())$train_ratio %||% 0.8
  )[1L])
  rscv <- cfg$ml_tcf_sklearn_rscv %||% list()
  cv <- suppressWarnings(as.integer(rscv$cv %||% 5L)[1L])
  thr <- suppressWarnings(as.numeric(rscv$threshold %||% 0.5)[1L])
  smote <- !isFALSE(rscv$smote %||% TRUE)
  miss_thr <- suppressWarnings(as.numeric(mi$missing_col_threshold %||% 0.30)[1L])
  primary <- as.character((cfg$dual_db$primary %||% list())$name %||% "MIMIC")[1L]
  secondary <- as.character((cfg$dual_db$secondary %||% list())$name %||% "eICU")[1L]
  outcome_note <- as.character(
    (cfg$methods %||% list())$outcome_definition %||%
      "ICU admission–anchored 28-day all-cause death among sepsis-associated AKI (SA-AKI)"
  )[1L]
  pmid_note <- if (nzchar(pmid)) paste0(" (index PMID ", pmid, ")") else ""
  c(
    "# Statistical analysis",
    "",
    "## Study design and cohort",
    "",
    paste0(
      "This was a dual-database prognostic prediction study of SA-AKI", pmid_note, ". ",
      primary, " served as the development cohort (training + internal validation); ",
      secondary, " was used only for external validation without retraining. ",
      "Cohort construction and exclusions follow Figure 1."
    ),
    "",
    "## Exposure and outcome",
    "",
    paste0(
      "The clinical endpoint was ", outcome_note, ". ",
      "Candidate predictors were clinical and laboratory variables available after ",
      "analysis exclusions (disease-severity and severity scores removed from the covariate pool). ",
      "There was no single causal exposure index; the modelling target was multivariable risk prediction."
    ),
    "",
    "## Missing data and split",
    "",
    paste0(
      "Columns with missingness >", sprintf("%.0f", 100 * miss_thr),
      "% were dropped. Remaining missing values were handled by multiple imputation ",
      "(method = `", mi_method, "`, m = ", m, ", seed = ",
      as.integer(mi$seed %||% 42L), "). ",
      if (identical(fit_on, "train")) {
        "The imputation model was fit on the training set and applied to validation/external sets. "
      } else {
        "Imputation fit_on followed the study configuration. "
      },
      "Operational tables/figures used the first completed dataset (complete_action = 1). ",
      "Development patients were randomly split ",
      sprintf("%.0f/%.0f", 100 * train_ratio, 100 * (1 - train_ratio)),
      " into training/internal validation with stratification on the outcome (seed = ",
      seed_split, ")."
    ),
    "",
    "## Feature selection",
    "",
    paste0(
      "Entropy-based stepwise feature selection was run on the development data; ",
      "the final feature set was restricted to the dual-database computable intersection ",
      "so that external validation used the same predictors without silent column dropout."
    ),
    "",
    "## Machine learning (TCF)",
    "",
    paste0(
      "Seven base classifiers (decision tree, random forest, support-vector machine, ",
      "naive Bayes, gradient boosting, XGBoost, LightGBM) were tuned by RandomizedSearchCV ",
      "(", cv, "-fold CV", if (isTRUE(smote)) "; training MinMax scaling + SMOTE" else "",
      ") inside the Python TCF bundle. ",
      "TOPSIS fused the seven probability outputs into the TCF score using development-set ",
      "weights that were frozen for external scoring. ",
      "Classification used probability threshold ", thr,
      ". Discrimination metrics (AUC, ACC, PRE, SEN, SPE, F1) with bootstrap 95% CIs ",
      "(n_boot = 400, seed = 42) are reported for internal validation and external cohorts. ",
      "SHAP explanations used the best-performing base learner on the internal validation set."
    ),
    "",
    "## Limitations (apparent training performance)",
    "",
    paste0(
      "Because SMOTE and deep tree learners were fit on the development training set, ",
      "in-sample fused TCF predictions can yield an apparent training AUC near 1.000. ",
      "That row is disclosed in Table S10 as apparent/in-sample only and is omitted from ",
      "the main forest figure of cohort metrics. Primary discrimination claims use the ",
      "internal validation set and the external database (including planned strata). ",
      "Figure ROC legend AUC confidence intervals are bootstrap-locked to the TCF performance ",
      "tables (n_boot = 400; shared stratum seeds)."
    ),
    "",
    "## Software",
    "",
    "Package versions are listed in Methods_software_versions.txt and the Software subsection below.",
    ""
  )
}

#' ML 指标交付 Methods 正文（从 config 填疾病 / 库 / 暴露）
ml_index_methods_statistical_lines <- function(config = NULL) {
  cfg <- config %||% list()
  ## TCF / 多算法融合：禁止走默认 Cox/LASSO 预后模板
  is_tcf <- isTRUE((cfg$ml_tcf_sklearn_rscv %||% list())$enable) ||
    identical(tolower(as.character((cfg$methods %||% list())$kind %||% "")[1L]), "tcf") ||
    grepl("tcf|topsis|multi.?algorithm", tolower(paste(
      (cfg$project %||% list())$name %||% "",
      (cfg$project %||% list())$disease %||% ""
    )), perl = TRUE)
  if (isTRUE(is_tcf)) {
    return(ml_index_methods_statistical_lines_tcf(cfg))
  }
  proj <- cfg$project %||% list()
  mb <- cfg$ml_batch %||% cfg$incidence_batch %||% list()
  st <- tolower(trimws(as.character(proj$study_type %||% "")[1L]))
  is_prog <- identical(st, "prognosis")
  is_incidence <- identical(st, "incidence") || identical(st, "cross_sectional")
  ## analysis_group 常为 "1"/"0"；展示层用 disease 名，禁止 Methods 写 “analysis of 1”
  ag_raw <- as.character(proj$analysis_group %||% mb$analysis_group %||% "")[1L]
  disease_nm <- as.character(proj$disease %||% proj$disease_cn %||% "")[1L]
  disease <- if (nzchar(disease_nm) && (ag_raw %in% c("1", "0", "Yes", "No") || !nzchar(ag_raw))) {
    disease_nm
  } else if (nzchar(ag_raw) && !ag_raw %in% c("1", "0")) {
    ag_raw
  } else if (nzchar(disease_nm)) {
    disease_nm
  } else {
    "the study outcome"
  }
  exposure <- as.character(
    proj$exposure %||% mb$index_vars[[1L]] %||% cfg$index$vars[[1L]] %||%
      (cfg$index$only %||% character(0))[1L] %||%
      "the primary exposure index"
  )[1L]
  ## 流水线是否含 ML 训练块；纯发病/关联课题禁止写 Machine learning 节
  pipe_blocks_detect <- as.character((cfg$pipeline %||% list())$blocks %||% character(0))
  if (!length(pipe_blocks_detect)) {
    pipe_blocks_detect <- as.character(cfg$`_pipeline_blocks` %||% character(0))
  }
  has_ml_blocks <- any(grepl(
    "(?i)^(train_validation|ml_|performance_ml|shap|shiny_ml|feature_selection|lasso)",
    pipe_blocks_detect
  )) || isTRUE((cfg$capability %||% list())$ml_enable %||% FALSE) ||
    identical(tolower(as.character((cfg$methods %||% list())$kind %||% "")[1L]), "ml")
  include_ml_section <- isTRUE(has_ml_blocks) && !isTRUE(is_incidence && !has_ml_blocks)
  if (isTRUE(is_incidence) && !isTRUE(has_ml_blocks)) include_ml_section <- FALSE
  formula_txt <- trimws(as.character(
    (cfg$methods %||% list())$index_formula %||%
      (cfg$pub %||% list())$index_formula %||%
      (cfg$methods %||% list())$exposure_formula %||% ""
  )[1L])
  weight_formula <- trimws(as.character(
    (cfg$methods %||% list())$survey_weight_formula %||%
      (cfg$nhanes %||% list())$weight_formula %||% ""
  )[1L])
  fig1_bridge <- trimws(as.character(
    (cfg$methods %||% list())$fig1_bridge %||%
      (cfg$attrition %||% list())$methods_bridge %||% ""
  )[1L])
  mi_seed <- suppressWarnings(as.integer((cfg$imputation %||% list())$seed %||% NA_integer_)[1L])
  mi_maxit <- suppressWarnings(as.integer((cfg$imputation %||% list())$max_iter %||%
    (cfg$imputation %||% list())$maxit %||% NA_integer_)[1L])
  outcome_in_mice <- (cfg$imputation %||% list())$outcome_in_mice
  outcome_mice_note <- if (is.null(outcome_in_mice)) {
    "Whether the outcome entered the imputation predictor matrix followed the study imputation block defaults. "
  } else if (isTRUE(outcome_in_mice)) {
    "The binary outcome was included in the imputation predictor matrix. "
  } else {
    "The binary outcome was excluded from the imputation predictor matrix. "
  }
  db <- as.character(
    proj$database %||%
      (cfg$dual_db$primary %||% list())$name %||%
      mb$primary_name %||% proj$databases[[1L]] %||% "the study database"
  )[1L]
  age_f <- as.character((cfg$data_clean %||% list())$age_filter %||% "")[1L]
  age_note <- if (nzchar(age_f)) {
    paste0(" Age eligibility followed `", age_f, "`.")
  } else {
    ""
  }
  surv <- cfg$survival %||% list()
  time_var <- as.character(surv$time_var %||% "follow-up time")[1L]
  event_var <- as.character(surv$event_var %||% disease)[1L]
  horiz <- suppressWarnings(as.numeric((cfg$performance_ml %||% list())$surv_horizon %||% NA_real_)[1L])
  horiz_u <- as.character((cfg$performance_ml %||% list())$surv_horizon_unit %||% "month")[1L]
  best_metric_raw <- tolower(trimws(as.character(
    (cfg$methods %||% list())$primary_ml_metric %||%
      (cfg$ml_aggregate %||% list())$best_metric %||%
      (cfg$ml_best %||% list())$metric %||%
      if (is_prog) "td_auc_bootstrap" else "roc_auc"
  )[1L]))
  best_metric <- if (best_metric_raw %in% c("td_auc_bootstrap", "bootstrap_td_auc", "td-auc")) {
    paste0(
      if (is.finite(suppressWarnings(as.numeric((cfg$performance_ml %||% list())$surv_horizon %||% NA_real_)[1L]))) {
        paste0(
          as.integer((cfg$performance_ml %||% list())$surv_horizon), "-",
          as.character((cfg$performance_ml %||% list())$surv_horizon_unit %||% "month"), " "
        )
      } else {
        ""
      },
      "bootstrap time-dependent AUC / C-index on the validation set"
    )
  } else if (best_metric_raw %in% c("auc", "roc_auc")) {
    "validation single-cutpoint ROC AUC (overview only)"
  } else if (identical(best_metric_raw, "c_index")) {
    "validation C-index"
  } else {
    best_metric_raw
  }
  shap_rationale <- as.character(
    (cfg$methods %||% list())$shap_model_rationale %||%
      (cfg$shap %||% list())$selection_rationale %||% ""
  )[1L]
  wt <- as.character((cfg$nhanes %||% list())$survey_weight %||% "")[1L]
  db_type <- tolower(trimws(as.character(proj$database_type %||% "")[1L]))
  ## 模板常残留 nhanes$survey_weight；仅当库名/类型真是 NHANES 才写调查权重
  is_nhanes <- identical(toupper(db), "NHANES") ||
    identical(db_type, "nhanes") ||
    (nzchar(wt) && grepl("nhanes", tolower(paste(db, db_type)), fixed = TRUE))
  wt_disp <- if (nzchar(wt)) gsub("_", " ", wt, fixed = TRUE) else "the study survey weight"
  wt_note <- if (is_nhanes) {
    paste0(
      " For NHANES, descriptive tables and association models used the complex ",
      "survey design (strata SDMVSTRA, PSU SDMVPSU, and weight ", wt_disp, "). ",
      if (nzchar(weight_formula)) {
        paste0("Survey weights were constructed as: ", weight_formula, ". ")
      } else {
        ""
      },
      "Weighted percentages are paired with design-based tests as stated in table footnotes."
    )
  } else {
    ""
  }
  mi <- cfg$imputation %||% list()
  m <- suppressWarnings(as.integer(mi$m %||% 5L)[1L])
  if (!is.finite(m) || m < 1L) m <- 5L
  rubin <- isTRUE(mi$rubin_pool %||% TRUE)
  fit_on <- tolower(trimws(as.character(mi$fit_on %||% "all")[1L]))
  pipe_blocks <- as.character((cfg$pipeline %||% list())$blocks %||% character(0))
  ## 若调用方把 pipeline 放在外层，finalize 时也可从 config$`_pipeline_blocks` 传入
  if (!length(pipe_blocks)) {
    pipe_blocks <- as.character(cfg$`_pipeline_blocks` %||% character(0))
  }
  mi_before_split <- isTRUE((cfg$methods %||% list())$mi_before_split %||% FALSE) ||
    (identical(fit_on, "all") &&
       length(pipe_blocks) >= 2L &&
       any(pipe_blocks == "imputation") &&
       any(pipe_blocks == "train_validation") &&
       which(pipe_blocks == "imputation")[1L] < which(pipe_blocks == "train_validation")[1L])
  mi_order_note <- if (isTRUE(mi_before_split)) {
    paste0(
      "Multiple imputation was performed on the pooled analytic cohort before the random ",
      "training/validation split; therefore validation metrics may be mildly optimistic ",
      "(information leakage via the shared imputation model). "
    )
  } else if (identical(fit_on, "train")) {
    "The imputation model was fit on the training set and applied to the held-out validation set. "
  } else {
    ""
  }
  mi_note <- if (identical(as.character(mi$method %||% ""), "none")) {
    "Analyses used complete cases without multiple imputation."
  } else {
    paste0(
      "Missing covariates were handled with multiple imputation by chained equations ",
      "(method = ", as.character(mi$method %||% "cart")[1L],
      "; m = ", m,
      if (is.finite(mi_maxit)) paste0("; maxit = ", mi_maxit) else "",
      if (is.finite(mi_seed)) paste0("; seed = ", mi_seed) else "",
      "). ",
      outcome_mice_note,
      mi_order_note,
      if (isTRUE(rubin)) {
        if (is_prog) {
          "Cox regression estimates were pooled across imputations with Rubin's rules. "
        } else {
          "Logistic / survey-weighted regression estimates were pooled across imputations with Rubin's rules. "
        }
      } else {
        ""
      },
      if (isTRUE(include_ml_section)) {
        "Operational steps (feature selection, KM/RCS/SHAP plots, descriptive tables) used the first completed dataset."
      } else {
        "Operational steps (descriptive tables, RCS plots, subgroup forests) used the first completed dataset."
      }
    )
  }
  lim_lines <- character(0)
  if (isTRUE(mi_before_split)) {
    lim_lines <- c(
      "",
      "## Limitations (missing data / split)",
      "",
      paste0(
        "Because imputation preceded splitting, validation discrimination may be slightly ",
        "optimistic relative to a train-only imputation workflow; absolute differences are ",
        "typically small when missingness is modest, but PROBAST/TRIPOD reviewers should be ",
        "told this order explicitly."
      )
    )
  }
  pred_mode <- identical(
    tolower(as.character((cfg$capability %||% list())$exposure_mode %||% "")[1L]),
    "all_ml_features"
  )
  if (is_prog) {
    design_line <- paste0(
      "This was a prognostic survival analysis of ", disease,
      " in ", db, ".", age_note,
      " The analytic sample followed the study inclusion flowchart (Figure 1). ",
      "Follow-up time was recorded in `", time_var,
      "` with event indicator `", event_var, "`."
    )
    exposure_line <- if (isTRUE(pred_mode)) {
      paste0(
        "This study is a multivariable prediction model without a single causal exposure. ",
        "Candidate clinical variables entered feature selection. Continuous predictors retained ",
        "after selection were summarised with Cox models (continuous and quartile forms; ",
        "lowest quartile as reference), Kaplan–Meier curves, restricted cubic splines, and ",
        "subgroup forests as dose–response / robustness descriptions of associations captured ",
        "by the model (not causal exposure effects). ",
        if (is.finite(horiz)) {
          paste0(
            "Primary machine-learning discrimination used a ", horiz, "-", horiz_u,
            " horizon (bootstrap TD-AUC / C-index); single-cutpoint ROC AUC tables are overview only. "
          )
        } else {
          ""
        },
        "The clinical endpoint was ", disease, "."
      )
    } else {
      paste0(
        "Candidate clinical, imaging, and treatment variables entered feature selection. ",
        "Continuous features retained after selection were analysed with Cox proportional hazards models ",
        "(continuous and quartile forms; lowest quartile as reference) and Kaplan–Meier curves. ",
        "Restricted cubic splines and subgroup forests focused on Age when that exposure was significant. ",
        if (is.finite(horiz)) {
          paste0("Machine-learning discrimination was summarised at a ", horiz, "-", horiz_u, " horizon where applicable. ")
        } else {
          ""
        },
        "The clinical endpoint was ", disease, "."
      )
    }
    assoc_line <- if (isTRUE(pred_mode)) {
      paste0(
        "Cox models reported hazard ratios (HRs) with 95% confidence intervals as adjusted associations ",
        "among selected predictors. Model 1 and Model 2 covariates follow the regression table footnotes. ",
        "Restricted cubic splines and subgroup forests for representative continuous predictors ",
        "(for example Age or the leading continuous feature retained after selection) ",
        "are descriptive of model-captured structure."
      )
    } else {
      paste0(
        "Cox models reported hazard ratios (HRs) with 95% confidence intervals. ",
        "Model 1 and Model 2 covariates follow the regression table footnotes ",
        "(Age was not used as a covariate when Age was the exposure). ",
        "Restricted cubic splines described the Age–mortality dose–response. ",
        "Subgroup forests estimated the highest-versus-lowest Age quartile contrast ",
        "within strata on the full analytic sample."
      )
    }
    shap_note <- if (nzchar(shap_rationale)) {
      paste0(" SHAP / Shiny used ", shap_rationale, ".")
    } else {
      paste0(
        " The primary ranking metric for discrimination was ", best_metric,
        "; SHAP/Shiny may follow a separately declared calibration or auto-best rule ",
        "and must not be labelled simply as \"the best model\" without that rule."
      )
    }
    ml_line <- paste0(
      "Participants were randomly split into training and validation sets for supervised survival prediction of ",
      disease, ". ",
      "Feature selection used univariate Cox screening, VIF filtering, and LASSO-Cox. ",
      "Multiple survival learners were trained. Primary comparative performance used ",
      best_metric, ".",
      shap_note,
      " Discrimination (AUC, C-index), calibration, and decision-curve analyses are reported in the performance tables."
    )
  } else {
    design_line <- paste0(
      "This was a cross-sectional analysis of ", disease,
      " in ", db, ".", age_note,
      " The analytic sample followed the study inclusion flowchart (Figure 1). ",
      if (nzchar(fig1_bridge)) paste0(fig1_bridge, " ") else "",
      "Unweighted participant counts are reported alongside weighted percentages where labelled."
    )
    outcome_def <- trimws(as.character(
      (cfg$methods %||% list())$outcome_definition %||%
        (cfg$pub %||% list())$outcome_definition %||% ""
    )[1L])
    exposure_line <- paste0(
      "The primary exposure was ", exposure,
      if (nzchar(formula_txt)) {
        paste0(" with formula ", formula_txt, ". ")
      } else {
        " (composite index as defined in the study configuration). "
      },
      "The exposure entered models as a continuous variable and as quantiles with cut-points ",
      "aligned to the main regression table; the lowest quantile was the reference. ",
      "Tests for trend used the numeric quantile score. ",
      if (nzchar(outcome_def)) {
        outcome_def
      } else {
        paste0("The binary outcome was ", disease, ".")
      }
    )
    assoc_line <- paste0(
      if (is_nhanes) {
        "Survey-weighted logistic regression estimated odds ratios (ORs) with 95% confidence intervals. "
      } else {
        "Logistic regression estimated odds ratios (ORs) with 95% confidence intervals. "
      },
      "Model 1 and Model 2 covariates are those named in the main regression table footnote. ",
      "Restricted cubic splines (default 3 knots at the 10th/50th/90th percentiles) described dose–response; ",
      "figure panels report P for overall and P for nonlinear. ",
      "Subgroup forests estimated the highest-versus-lowest quantile contrast within strata ",
      "on the full analytic sample (forest N = stratum totals). ",
      "Mediation total effects need not equal Table 2 highest-quantile ORs when exposure coding differs ",
      "(continuous vs quantile); footnotes state the shared adjustment set when applicable."
    )
    ml_line <- if (isTRUE(include_ml_section)) {
      paste0(
        "Participants were split into training and validation sets for supervised prediction of ",
        disease, ". ",
        "Feature selection (LASSO) and candidate classifiers followed the study ML blocks. ",
        "The primary model for SHAP/Shiny used the highest ", best_metric, " on the validation set. ",
        "Discrimination, calibration, and related metrics are reported in the performance tables."
      )
    } else {
      ""
    }
  }
  out_lines <- c(
    "# Statistical analysis",
    "",
    "## Study design and cohort",
    "",
    design_line,
    wt_note,
    "",
    "## Exposure and outcome",
    "",
    exposure_line,
    "",
    "## Missing data",
    "",
    mi_note,
    "",
    "## Association analyses",
    "",
    assoc_line,
    ""
  )
  if (isTRUE(include_ml_section) && nzchar(ml_line)) {
    out_lines <- c(out_lines, "## Machine learning", "", ml_line, "")
  }
  c(
    out_lines,
    "## Software",
    "",
    "Package versions are listed in Methods_software_versions.txt and the Software subsection below.",
    "",
    lim_lines
  )
}

#' 单库发表名：去掉「Table/Figure …-库名.」中的库名（文件名 + 表 A1 标题）
#' @param root Tables 或 Figures 目录（或含二者的指标根 / summary_results）
#' @param db_tags 要剥掉的库标签；NULL 时用常见库名 + config 主库名
pub_strip_db_tags_from_delivery <- function(root, config = NULL, db_tags = NULL) {
  root <- as.character(root %||% "")[1L]
  if (!nzchar(root) || !dir.exists(root)) return(invisible(0L))
  tags <- unique(c(
    as.character(db_tags %||% character(0)),
    "CHARLS", "NHANES", "Nhance", "MIMIC", "MIMIC_IV", "MIMIC IV", "eICU", "ELSA", "Hosp",
    "NPC", "VitalDB", "BlendedICU"
  ))
  if (!is.null(config)) {
    dd <- config$dual_db %||% list()
    pr <- config$project %||% list()
    for (slot in c("primary", "secondary")) {
      nm <- as.character((dd[[slot]] %||% list())$name %||% "")[1L]
      if (nzchar(nm) && !identical(toupper(nm), "UNUSED")) tags <- c(tags, nm)
    }
    ## 单库常用 project$database（如 NPC）也会写进 Table 1-NPC. …
    for (nm in c(pr$database, pr$database_code, pr$disease_code)) {
      nm <- as.character(nm %||% "")[1L]
      if (!nzchar(nm) || identical(toupper(nm), "UNUSED")) next
      ## disease_code 形如 53_NPC → 也收 NPC
      tags <- c(tags, nm, sub("^.*_", "", nm))
    }
  }
  tags <- unique(tags[nzchar(tags) & !identical(toupper(tags), "UNUSED")])
  tags <- tags[order(-nchar(tags))]
  flex_one <- function(t) {
    t <- gsub("[ _]+", " ", t)
    parts <- strsplit(t, " ", fixed = TRUE)[[1L]]
    paste(vapply(parts, function(p) gsub("(\\\\|[][{}()+*^$?.|^-])", "\\\\\\1", p, perl = TRUE),
                 character(1L)), collapse = "[ _]+")
  }
  strip_bn <- function(bn) {
    out <- bn
    for (tg in tags) {
      flex <- flex_one(tg)
      # Table 1-CHARLS. / Figure S2A-CHARLS. / Figure S-CHARLS.
      out <- gsub(
        paste0("^((?:Table|Figure)\\s+(?:S?[0-9]+[A-Za-z]?|S)?)-(?:", flex, ")(\\.)"),
        "\\1\\2",
        out,
        ignore.case = TRUE,
        perl = TRUE
      )
      # 误套：Figure S1. S-CHARLS. caption → Figure S1. caption
      out <- gsub(
        paste0("\\.\\s*S-(?:", flex, ")\\.\\s*"),
        ". ",
        out,
        ignore.case = TRUE,
        perl = TRUE
      )
      out <- gsub(
        paste0("-(?:", flex, ")(?=\\.)"),
        "",
        out,
        ignore.case = TRUE,
        perl = TRUE
      )
    }
    out <- gsub("\\s{2,}", " ", out)
    out <- sub("^((?:Table|Figure)\\s+S)\\.\\s*", "\\1. ", out, perl = TRUE)
    out
  }
  n <- 0L
  # Tables xlsx
  tab_dirs <- unique(c(
    if (dir.exists(file.path(root, "Tables"))) file.path(root, "Tables") else character(0),
    if (grepl("/Tables$", root)) root else character(0)
  ))
  for (td in tab_dirs) {
    files <- list.files(td, pattern = "\\.xlsx$", full.names = TRUE, ignore.case = TRUE)
    for (f in files) {
      new_bn <- strip_bn(basename(f))
      dest <- file.path(td, new_bn)
      if (!identical(basename(f), new_bn)) {
        if (file.exists(dest) && !identical(normalizePath(f, winslash = "/"),
                                            normalizePath(dest, winslash = "/", mustWork = FALSE))) {
          unlink(dest)
        }
        if (isTRUE(file.rename(f, dest))) {
          n <- n + 1L
          f <- dest
        } else if (isTRUE(file.copy(f, dest, overwrite = TRUE))) {
          unlink(f)
          n <- n + 1L
          f <- dest
        }
      }
      # A1 标题去库名：字节级替换 sharedStrings（避免 openpyxl/ET 损坏 drawing）
      tryCatch(
        {
          py <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
          if (!nzchar(py)) py <- getwd()
          helper <- file.path(py, "python", "pub_strip_db_in_xlsx_title.py")
          if (file.exists(helper)) {
            system2("python3", c(helper, f), stdout = FALSE, stderr = FALSE)
          } else if (requireNamespace("openxlsx", quietly = TRUE)) {
            d <- tryCatch(openxlsx::read.xlsx(f, colNames = FALSE, rows = 1, cols = 1),
                          error = function(e) NULL)
            t1 <- if (!is.null(d) && nrow(d)) as.character(d[1, 1]) else ""
            t1b <- strip_bn(t1)
            if (nzchar(t1) && !identical(t1, t1b) &&
                exists("pub_xlsx_edit_cells", mode = "function")) {
              pub_xlsx_edit_cells(f, data.frame(row = 1L, col = 1L, value = t1b))
            }
          }
        },
        error = function(e) NULL
      )
    }
  }
  # Figures：pdf/png/tiff/image_information + 根平铺
  fig_root <- if (dir.exists(file.path(root, "Figures"))) {
    file.path(root, "Figures")
  } else if (grepl("/Figures$", root)) {
    root
  } else {
    character(0)
  }
  if (length(fig_root) && dir.exists(fig_root)) {
    subdirs <- c(
      fig_root,
      file.path(fig_root, c("pdf", "png", "tiff", "image_information"))
    )
    for (fd in subdirs) {
      if (!dir.exists(fd)) next
      files <- list.files(fd, full.names = TRUE, no.. = TRUE)
      files <- files[!dir.exists(files)]
      for (f in files) {
        new_bn <- strip_bn(basename(f))
        if (identical(basename(f), new_bn)) next
        dest <- file.path(fd, new_bn)
        if (file.exists(dest) && !identical(normalizePath(f, winslash = "/"),
                                            normalizePath(dest, winslash = "/", mustWork = FALSE))) {
          unlink(dest)
        }
        if (isTRUE(file.rename(f, dest)) || isTRUE(file.copy(f, dest, overwrite = TRUE))) {
          if (file.exists(dest) && file.exists(f) &&
              !identical(normalizePath(f, winslash = "/"), normalizePath(dest, winslash = "/"))) {
            unlink(f)
          }
          n <- n + 1L
          # md 标题同步
          if (grepl("\\.md$", dest, ignore.case = TRUE)) {
            lines <- tryCatch(readLines(dest, warn = FALSE, encoding = "UTF-8"), error = function(e) NULL)
            if (!is.null(lines) && length(lines) && grepl("^#\\s*Figure", lines[[1L]])) {
              lines[[1L]] <- paste0("# ", sub("\\.md$", "", new_bn, ignore.case = TRUE))
              writeLines(lines, dest, useBytes = TRUE)
            }
          }
        }
      }
    }
  }
  if (requireNamespace("cli", quietly = TRUE) && n > 0L) {
    cli::cli_alert_success("单库发表去库名: {n} 个文件 @ {root}")
  }
  invisible(n)
}

#' 指标级 summary_results 目录名
ml_index_summary_results_dirname <- function(config = NULL) {
  pub <- config$pub %||% list()
  bc <- config$ml_batch %||% config$incidence_batch %||% list()
  nm <- as.character(
    pub$index_summary_results_dir %||%
      bc$index_summary_results_dir %||%
      "summary_results"
  )[1L]
  if (!nzchar(nm)) nm <- "summary_results"
  nm
}

#' 是否在 finalize 后写指标级 summary_results
#'
#' 交付面：`by_index/【success】<INDEX>/summary_results/`（白名单五件套）。
#' 发病/预后 dual-batch、**双库/单库 ML** 均默认开（须在 by_index 下，勿只落课题根）。
#' 显式 `write_index_summary_results=FALSE` 可关。
ml_index_summary_results_enabled <- function(config = NULL) {
  bc <- config$ml_batch %||% config$incidence_batch %||% config$survival_batch %||% list()
  pub <- config$pub %||% list()
  if (!is.null(bc$write_index_summary_results)) {
    return(isTRUE(bc$write_index_summary_results))
  }
  if (!is.null(pub$write_index_summary_results)) {
    return(isTRUE(pub$write_index_summary_results))
  }
  ## 发病 / 预后 / ML dual-batch：默认写指标级 summary_results
  if (!is.null(config$incidence_batch) ||
      !is.null(config$survival_batch) ||
      !is.null(config$ml_batch)) {
    return(TRUE)
  }
  TRUE
}

#' 同步指标根 Tables/Figures → summary_results，并写 Methods / 软件版本后白名单修剪
#'
#' @param index_root by_index/【success】INDEX 或裸名 INDEX
#' @param config 可选；用于四目录 dpi、目录名与 Methods 字段
#' @param figures_tables_only TRUE 时仅留 Figures/Tables（旧行为）；
#'   默认 FALSE = 完整交付白名单（含 Methods / 软件版本 / 中期 PDF）
#' @param write_methods 是否写出 Methods_statistical_analysis.md + 软件版本（默认 TRUE）
#' @param methods_lines 可选课题自定义 Methods 行；NULL 时用 ml_index_methods_statistical_lines
#' @return summary_results 绝对路径
ml_finalize_index_summary_results <- function(index_root,
                                              config = NULL,
                                              figures_tables_only = FALSE,
                                              write_methods = TRUE,
                                              methods_lines = NULL) {
  index_root <- as.character(index_root %||% "")[1L]
  if (!nzchar(index_root) || !dir.exists(index_root)) {
    stop("ml_finalize_index_summary_results: index_root 无效: ", index_root)
  }
  index_root <- normalizePath(index_root, winslash = "/", mustWork = TRUE)
  eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(eng)) eng <- getwd()
  .ml_src <- function(rel) {
    p <- file.path(eng, rel)
    if (file.exists(p)) source(p, local = FALSE)
  }
  if (!exists("pub_prune_delivery_root", mode = "function")) {
    .ml_src("R/pub_delivery_prune.R")
  }
  if (!exists("pub_write_software_versions", mode = "function")) {
    .ml_src("R/pub_software_versions.R")
  }
  if (!exists("pub_figure_ensure_formats", mode = "function")) {
    .ml_src("R/pub_figure_export.R")
  }

  ## 单库：指标根先剥掉 -CHARLS/-NHANES/-NPC 等库名，再同步到 summary_results
  .do_strip <- exists("pub_config_is_single_db", mode = "function") &&
    isTRUE(pub_config_is_single_db(config))
  if (isTRUE(.do_strip)) {
    tryCatch(
      pub_strip_db_tags_from_delivery(index_root, config = config),
      error = function(e) {
        if (requireNamespace("cli", quietly = TRUE)) {
          cli::cli_alert_warning("summary_results: 去库名失败: {e$message}")
        }
      }
    )
  }
  ## 命名 options：单库禁止后续 block 再写 -库名
  if (exists("pub_apply_naming_options", mode = "function")) {
    tryCatch(pub_apply_naming_options(config), error = function(e) NULL)
  }
  sum_nm <- ml_index_summary_results_dirname(config)
  sum_root <- file.path(index_root, sum_nm)
  dir.create(sum_root, recursive = TRUE, showWarnings = FALSE)

  ## 确保指标根 Figures 四目录齐全
  fig_src <- file.path(index_root, "Figures")
  ## 若指标根已有 png/tiff，或发病单库默认，保持栅格导出（避免 ensure 把已有栅格清掉）
  if (!is.list(config)) config <- list()
  if (!is.list(config$pub_figures)) config$pub_figures <- list()
  has_png <- dir.exists(file.path(fig_src, "png")) &&
    length(list.files(file.path(fig_src, "png"), pattern = "\\.png$", ignore.case = TRUE)) > 0L
  has_tiff <- dir.exists(file.path(fig_src, "tiff")) &&
    length(list.files(file.path(fig_src, "tiff"), pattern = "\\.tiff?$", ignore.case = TRUE)) > 0L
  st0 <- tolower(as.character((config$project %||% list())$study_type %||% "")[1L])
  if (is.null(config$pub_figures$export_png) && (isTRUE(has_png) || identical(st0, "incidence"))) {
    config$pub_figures$export_png <- TRUE
  }
  if (is.null(config$pub_figures$export_tiff) && (isTRUE(has_tiff) || identical(st0, "incidence"))) {
    config$pub_figures$export_tiff <- TRUE
  }
  if (is.null(config$pub_figures$dpi)) config$pub_figures$dpi <- 600L
  if (dir.exists(fig_src) && exists("pub_figure_ensure_formats", mode = "function")) {
    tryCatch(
      pub_figure_ensure_formats(fig_src, config = config),
      error = function(e) {
        if (requireNamespace("cli", quietly = TRUE)) {
          cli::cli_alert_warning("summary_results: 四目录补齐失败: {e$message}")
        }
      }
    )
  }

  tab_src <- file.path(index_root, "Tables")
  tab_dst <- file.path(sum_root, "Tables")
  fig_dst <- file.path(sum_root, "Figures")
  dir.create(tab_dst, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig_dst, recursive = TRUE, showWarnings = FALSE)

  ## Tables：只同步发表 xlsx；先把指标根内题与文件名对齐（防 S* 错号）
  if (!exists("pub_sync_xlsx_a1_titles_to_filenames", mode = "function")) {
    .ml_src("R/pub_xlsx_surgical.R")
  }
  if (dir.exists(tab_src) &&
      exists("pub_sync_xlsx_a1_titles_to_filenames", mode = "function")) {
    tryCatch(
      pub_sync_xlsx_a1_titles_to_filenames(tab_src),
      error = function(e) {
        if (requireNamespace("cli", quietly = TRUE)) {
          cli::cli_alert_warning("summary_results: 表题同步失败: {e$message}")
        }
      }
    )
  }
  if (dir.exists(tab_src)) {
    if (!exists("pub_dedup_identical_tables", mode = "function")) {
      .ml_src("R/pub_dedup_identical_tables.R")
    }
    if (exists("pub_dedup_identical_tables", mode = "function")) {
      tryCatch(pub_dedup_identical_tables(tab_src, dry_run = FALSE), error = function(e) NULL)
    }
    xlsx <- list.files(tab_src, pattern = "\\.xlsx$", full.names = TRUE, ignore.case = TRUE)
    xlsx <- xlsx[!grepl("/_archive", xlsx)]
    for (f in xlsx) {
      file.copy(f, file.path(tab_dst, basename(f)), overwrite = TRUE)
    }
  }
  if (dir.exists(tab_dst) &&
      exists("pub_sync_xlsx_a1_titles_to_filenames", mode = "function")) {
    tryCatch(pub_sync_xlsx_a1_titles_to_filenames(tab_dst), error = function(e) NULL)
  }

  ## Figures：整树同步（含 pdf/png/tiff/image_information）
  if (dir.exists(fig_src)) {
    unlink(fig_dst, recursive = TRUE, force = TRUE)
    ## file.copy(src_dir, parent) → parent/basename(src_dir)
    file.copy(fig_src, sum_root, recursive = TRUE, overwrite = TRUE)
  }

  ## Shiny：指标根 Shiny/（或根级 ShinyApp/）→ summary_results（交付白名单保留）
  shiny_src <- file.path(index_root, "Shiny")
  shiny_app_src <- file.path(index_root, "ShinyApp")
  if (dir.exists(shiny_src)) {
    shiny_dst <- file.path(sum_root, "Shiny")
    if (dir.exists(shiny_dst)) unlink(shiny_dst, recursive = TRUE, force = TRUE)
    ok_sh <- isTRUE(file.copy(shiny_src, sum_root, recursive = TRUE, overwrite = TRUE))
    if (isTRUE(ok_sh) && requireNamespace("cli", quietly = TRUE)) {
      cli::cli_alert_success("summary_results: 已同步 Shiny/")
    }
  } else if (dir.exists(shiny_app_src)) {
    shiny_dst <- file.path(sum_root, "ShinyApp")
    if (dir.exists(shiny_dst)) unlink(shiny_dst, recursive = TRUE, force = TRUE)
    ok_sh <- isTRUE(file.copy(shiny_app_src, sum_root, recursive = TRUE, overwrite = TRUE))
    if (isTRUE(ok_sh) && requireNamespace("cli", quietly = TRUE)) {
      cli::cli_alert_success("summary_results: 已同步 ShinyApp/")
    }
  }

  ## 同步后再剥一次库名（防止 copy 带回旧 -NPC 名）
  if (isTRUE(.do_strip)) {
    tryCatch(
      pub_strip_db_tags_from_delivery(sum_root, config = config),
      error = function(e) NULL
    )
  }

  ## 汇总只留主文/必要补充：剔除 ML panel、Prognosis 校准/DCA、重复 LASSO、单层 KM
  if (dir.exists(fig_dst)) {
    if (!exists("incidence_batch_purge_non_delivery_figures", mode = "function")) {
      .ml_src("R/incidence_dual_batch_runner.R")
    }
    if (exists("incidence_batch_purge_non_delivery_figures", mode = "function")) {
      tryCatch(
        incidence_batch_purge_non_delivery_figures(fig_dst),
        error = function(e) {
          if (requireNamespace("cli", quietly = TRUE)) {
            cli::cli_alert_warning("summary_results 图清理跳过: {e$message}")
          }
        }
      )
    }
  }

  if (dir.exists(fig_dst) && exists("pub_figure_ensure_formats", mode = "function")) {
    tryCatch(
      pub_figure_ensure_formats(fig_dst, config = config),
      error = function(e) NULL
    )
  }
  ## ensure_formats 可能从旧根再生成冗余 panel → 再清一次
  if (dir.exists(fig_dst) &&
      exists("incidence_batch_purge_non_delivery_figures", mode = "function")) {
    tryCatch(incidence_batch_purge_non_delivery_figures(fig_dst), error = function(e) NULL)
  }

  ## 保留指标根已有中期 PDF
  mid_src <- list.files(index_root, pattern = "\u4e2d\u671f.*\\.pdf$", full.names = TRUE)
  mid_src <- c(mid_src, list.files(index_root, pattern = "(?i)midterm.*\\.pdf$", full.names = TRUE))
  for (f in unique(mid_src)) {
    if (file.exists(f)) {
      file.copy(f, file.path(sum_root, basename(f)), overwrite = TRUE)
    }
  }

  ## Methods + 软件版本（交付白名单）
  if (isTRUE(write_methods) && !isTRUE(figures_tables_only)) {
    if (is.null(methods_lines) || !length(methods_lines)) {
      methods_lines <- ml_index_methods_statistical_lines(config)
    }
    md_path <- file.path(sum_root, "Methods_statistical_analysis.md")
    writeLines(as.character(methods_lines), md_path, useBytes = TRUE)
    if (exists("pub_write_software_versions", mode = "function")) {
      tryCatch(
        pub_write_software_versions(sum_root, project_root = NULL, config = config),
        error = function(e) NULL
      )
    }
    if (exists("pub_write_methods_software_section", mode = "function")) {
      st <- tolower(trimws(as.character((config$project %||% list())$study_type %||% "")[1L]))
      is_tcf_soft <- isTRUE((config$ml_tcf_sklearn_rscv %||% list())$enable) ||
        identical(tolower(as.character((config$methods %||% list())$kind %||% "")[1L]), "tcf")
      roles <- if (isTRUE(is_tcf_soft)) {
        c(
          mice = "Multiple imputation (logistic_mi / MICE; train-fit)",
          ggplot2 = "Publication figures",
          patchwork = "Multi-panel layout",
          openxlsx = "SCI three-line tables",
          pROC = "ROC helpers (where used)",
          dplyr = "Data wrangling"
        )
      } else if (identical(st, "prognosis")) {
        c(
          mice = "Multiple imputation (m=5; Rubin pool for Cox)",
          survival = "Cox proportional hazards / Kaplan-Meier",
          glmnet = "LASSO-Cox / penalized Cox",
          xgboost = "XGBoost-Cox",
          randomForestSRC = "Random survival forest",
          rms = "Restricted cubic splines",
          pROC = "Time-dependent ROC / AUC",
          forestploter = "Subgroup forest plots",
          ggplot2 = "Publication figures",
          patchwork = "Multi-panel layout",
          openxlsx = "SCI three-line tables",
          car = "Variance inflation factors"
        )
      } else {
        c(
          mice = "Multiple imputation (m=5; Rubin pool for regression)",
          survey = "NHANES complex survey design",
          rms = "Restricted cubic splines",
          glmnet = "LASSO / elastic net",
          pROC = "ROC / AUC / DeLong",
          forestploter = "Subgroup forest plots",
          ggplot2 = "Publication figures",
          patchwork = "Multi-panel layout",
          openxlsx = "SCI three-line tables",
          car = "Variance inflation factors"
        )
      }
      ## 非 NHANES 课题去掉 survey 角色
      db <- toupper(as.character((config$project %||% list())$database %||% "")[1L])
      if (!identical(db, "NHANES")) roles <- roles[names(roles) != "survey"]
      soft_tmp <- tempfile(fileext = ".md")
      tryCatch(
        {
          pub_write_methods_software_section(
            out_path = soft_tmp,
            roles = roles,
            extra_pkgs = names(roles),
            append_to = md_path
          )
          if (file.exists(soft_tmp)) unlink(soft_tmp)
          sec <- file.path(sum_root, "Methods_software_section.md")
          if (file.exists(sec)) unlink(sec)
        },
        error = function(e) NULL
      )
    }
  }

  ## 白名单修剪
  if (!exists("pub_prune_delivery_root", mode = "function")) {
    .ml_src("R/pub_delivery_prune.R")
  }
  if (exists("pub_delivery_normalize_fig_tab_dirs", mode = "function")) {
    tryCatch(pub_delivery_normalize_fig_tab_dirs(sum_root), error = function(e) NULL)
  }
  if (exists("pub_delivery_clean_tables_xlsx_only", mode = "function")) {
    tryCatch(pub_delivery_clean_tables_xlsx_only(sum_root), error = function(e) NULL)
  }
  ## 展示禁下划线兜底（已导 xlsx 外科 scrub；引擎级，全指标）
  if (!exists("pub_delivery_scrub_tables_underscores", mode = "function")) {
    .ml_src("R/pub_delivery_prune.R")
  }
  if (!exists("pub_xlsx_scrub_underscores_dir", mode = "function")) {
    .ml_src("R/pub_xlsx_surgical.R")
  }
  if (exists("pub_delivery_scrub_tables_underscores", mode = "function")) {
    tryCatch(
      pub_delivery_scrub_tables_underscores(sum_root),
      error = function(e) {
        if (requireNamespace("cli", quietly = TRUE)) {
          cli::cli_alert_warning("summary_results underscore scrub: {e$message}")
        }
      }
    )
  }
  if (exists("pub_prune_delivery_root", mode = "function")) {
    tryCatch(
      pub_prune_delivery_root(
        sum_root,
        dry_run = FALSE,
        figures_tables_only = isTRUE(figures_tables_only)
      ),
      error = function(e) {
        if (requireNamespace("cli", quietly = TRUE)) {
          cli::cli_alert_warning("summary_results prune: {e$message}")
        }
      }
    )
  } else if (isTRUE(figures_tables_only)) {
    ents <- list.files(sum_root, all.files = TRUE, no.. = TRUE)
    for (nm in setdiff(ents, c("Figures", "Tables"))) {
      unlink(file.path(sum_root, nm), recursive = TRUE, force = TRUE)
    }
  }

  n_tab <- length(list.files(tab_dst, pattern = "\\.xlsx$", ignore.case = TRUE))
  n_pdf <- length(list.files(file.path(fig_dst, "pdf"), pattern = "\\.pdf$", ignore.case = TRUE))
  has_md <- file.exists(file.path(sum_root, "Methods_statistical_analysis.md"))
  has_soft <- file.exists(file.path(sum_root, "Methods_software_versions.txt"))
  if (requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_success(
      paste0(
        "指标 summary_results: ", sum_root,
        "（Tables xlsx=", n_tab, ", Figures pdf=", n_pdf,
        ", Methods=", has_md, ", software=", has_soft, "）"
      )
    )
  }
  if (n_tab < 1L || n_pdf < 1L) {
    warning(
      "ml_finalize_index_summary_results: 表或图为空 (xlsx=", n_tab, ", pdf=", n_pdf, ")",
      call. = FALSE
    )
  }
  invisible(sum_root)
}

#' finalize 挂点：从 config + ix 定位指标根并写 summary_results
ml_batch_finalize_index_summary_results <- function(root, config, ix) {
  if (!isTRUE(ml_index_summary_results_enabled(config))) {
    return(invisible(NULL))
  }
  index_root <- if (exists("incidence_batch_index_output_root", mode = "function")) {
    incidence_batch_index_output_root(config, ix)
  } else {
    file.path(root, "by_index", as.character(ix)[1L])
  }
  if (!is_absolute_path(index_root)) {
    index_root <- file.path(root, index_root)
  }
  if (!dir.exists(index_root)) {
    ## success 改名后
    alt <- file.path(
      dirname(index_root),
      paste0("\u3010success\u3011", as.character(ix)[1L])
    )
    if (dir.exists(alt)) index_root <- alt
  }
  if (!exists("export_pub_figures", mode = "function") &&
      !exists("pub_figure_ensure_formats", mode = "function")) {
    eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = root)
    pf <- file.path(eng, "R", "pub_figure_export.R")
    if (file.exists(pf)) source(pf, local = FALSE)
  }
  ml_finalize_index_summary_results(index_root, config = config)
}
