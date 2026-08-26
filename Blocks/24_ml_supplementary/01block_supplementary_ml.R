###############################################################################
#  supplementary_ml — ML 补充表（S2 超参数、S3 Log-Loss、S4/S5 DeLong、S6/S7 NRI/IDI）
#
#  register_block: "supplementary_ml"
#  典型流水线: ml_models → supplementary_ml（勿与父块重复 source）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_results = ctx$results$ml_models；Data/Hpbest.RData、Models/evalresult_<tag>.RData
#  require_data = ctx$data$train / test（logloss / delong / nri_idi）；超参数表仅需 Hpbest
#
#  # ── 配置 config$supplementary_ml ─────────────────────────────────────────
#  supplementary_ml = list(
#    enable = TRUE,
#    methods = c("hyperparameters", "logloss", "delong", "nri_idi"),
#    delong_method = "delong", logloss_epsilon = 1e-15, nri_cutoff = c(0, 0.5, 1)
#  ),
#
#  发病: Group 二分类；预后: survival$event_var 与 imputed 对齐
#  源: Blocks/24_ml_supplementary/01block_supplementary_ml.R
###############################################################################

.sm_display_from_tag <- function(tag) {
  m <- c(
    dt = "DT", rf = "RF", xgboost = "XGBoost", enet = "ENet", rsvm = "RSVM",
    mlp = "MLP", logistic = "Logistic", lightgbm = "LightGBM", knn = "KNN",
    tabpfn = "TabPFN", adaboost = "AdaBoost", catboost = "CatBoost",
    tabpfnv2 = "TabPFNv2", realtabpfn_2_5 = "RealTabPFN-2.5",
    tablcl_v2 = "TablCL_v2"
  )
  tg <- tolower(as.character(tag)[1L])
  v <- unname(m[tg])
  if (is.na(v)) toupper(tg) else v
}

.sm_round_df_numeric <- function(df, digits = 3L) {
  if (is.null(df) || !nrow(df)) return(df)
  out <- as.data.frame(df, stringsAsFactors = FALSE)
  digs <- as.integer(digits)[1L]
  for (cn in names(out)) {
    if (is.numeric(out[[cn]])) out[[cn]] <- round(out[[cn]], digs)
  }
  out
}

.sm_collect_hpbest_all <- function(ctx, tags, display_names) {
  parts <- list()
  for (tg in tags) {
    models_dir <- resolve_ml_models_dir_for_tag(ctx, tg)
    step_dir <- dirname(models_dir)
    hp_path <- file.path(step_dir, "Data", "Hpbest.RData")
    if (!file.exists(hp_path)) next
    e <- new.env(parent = emptyenv())
    tryCatch(load(hp_path, envir = e), error = function(er) NULL)
    hpl <- e$hpbest_list %||% list()
    key <- paste0("hpbest_", tg)
    x <- hpl[[key]]
    if (is.null(x)) next
    if (!is.data.frame(x) && !inherits(x, "tbl_df")) next
    df <- as.data.frame(x, stringsAsFactors = FALSE)
    df$Model <- display_names[[tg]] %||% .sm_display_from_tag(tg)
    parts[[tg]] <- df
  }
  if (!length(parts)) return(NULL)
  dplyr::bind_rows(parts)
}

.sm_load_evalresult <- function(models_dir, tag) {
  path <- file.path(models_dir, paste0("evalresult_", tag, ".RData"))
  if (!file.exists(path)) return(NULL)
  env <- new.env(parent = emptyenv())
  tryCatch(load(path, envir = env), error = function(e) NULL)
  pt <- paste0("predtrain_", tag)
  pv <- paste0("predtest_", tag)
  if (!all(c(pt, pv) %in% names(env))) return(NULL)
  list(predtrain = get(pt, envir = env), predtest = get(pv, envir = env))
}

.sm_match_rows <- function(d_tv, part) {
  cols <- names(part)
  if (!length(cols)) return(integer(0))
  if (!all(cols %in% names(d_tv))) {
    stop("block_Supplementary_ml: train/test 无法与 imputed 对齐。", call. = FALSE)
  }
  pc <- function(df, cn) {
    do.call(paste, c(lapply(cn, function(v) as.character(df[[v]])), list(sep = "\1")))
  }
  match(pc(part, cols), pc(d_tv, cols), nomatch = NA_integer_)
}

.sm_build_d_tv <- function(data, outcome_col, ref_group, ana_group) {
  d0 <- data
  y_chr <- trimws(as.character(d0[[outcome_col]]))
  d0$Group <- factor(
    dplyr::case_when(
      y_chr == trimws(ana_group) ~ ana_group,
      y_chr == trimws(ref_group) ~ ref_group,
      TRUE ~ NA_character_
    ),
    levels = c(ref_group, ana_group)
  )
  d0[!is.na(d0$Group), , drop = FALSE]
}

.sm_outcome_binary <- function(ctx, part_df, prognosis, outcome_ml, ev_var, ref_group, ana_group) {
  n <- nrow(part_df)
  if (!prognosis) {
    g <- as.character(part_df$Group)
    y <- as.integer(g != ref_group)
    return(list(y = y, ok = rep(TRUE, n)))
  }
  if (is.null(ev_var) || !nzchar(ev_var)) {
    stop("block_Supplementary_ml（预后）: 需要 config$survival$event_var。", call. = FALSE)
  }
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("block_Supplementary_ml: 无 imputed 数据。", call. = FALSE)
  d_tv <- .sm_build_d_tv(data, outcome_ml, ref_group, ana_group)
  if (!ev_var %in% names(d_tv)) {
    stop("block_Supplementary_ml: event 列 ", ev_var, " 不存在。", call. = FALSE)
  }
  idx <- .sm_match_rows(d_tv, part_df)
  if (anyNA(idx) || length(idx) != n) {
    stop("block_Supplementary_ml（预后）: 无法对齐 event。", call. = FALSE)
  }
  y <- suppressWarnings(as.numeric(d_tv[[ev_var]][idx]))
  list(y = y, ok = is.finite(y))
}

.sm_clip_prob <- function(p, eps) {
  pmax(pmin(as.numeric(p), 1 - eps), eps)
}

.sm_logloss_one <- function(actual01, pred, eps) {
  if (!requireNamespace("Metrics", quietly = TRUE)) {
    stop("block_Supplementary_ml: 需要 Metrics 包计算 logLoss。", call. = FALSE)
  }
  ok <- is.finite(actual01) & is.finite(pred)
  actual01 <- actual01[ok]
  pred <- pred[ok]
  if (!length(actual01)) return(NA_real_)
  pred <- .sm_clip_prob(pred, eps)
  Metrics::logLoss(actual = actual01, predicted = pred)
}

.sm_delong_pair_fixed_names <- function(y01, s1, s2, name_new, name_base, method) {
  if (!requireNamespace("pROC", quietly = TRUE)) {
    stop("block_Supplementary_ml: 需要 pROC 包。", call. = FALSE)
  }
  ok <- is.finite(y01) & is.finite(s1) & is.finite(s2)
  y01 <- y01[ok]
  s1 <- s1[ok]
  s2 <- s2[ok]
  if (length(unique(y01)) < 2L || length(y01) < 10L) return(NULL)
  r1 <- pROC::roc(response = y01, predictor = s1, quiet = TRUE)
  r2 <- pROC::roc(response = y01, predictor = s2, quiet = TRUE)
  rt <- tryCatch(pROC::roc.test(r1, r2, method = method), error = function(e) NULL)
  if (is.null(rt)) return(NULL)
  a1 <- as.numeric(pROC::auc(r1))
  a2 <- as.numeric(pROC::auc(r2))
  dauc <- a1 - a2
  ci_chr <- NA_character_
  ci <- suppressWarnings(as.numeric(rt$conf.int))
  if (length(ci) >= 2L && all(is.finite(ci))) {
    ci_chr <- sprintf("%.3f ~ %.3f", ci[1L], ci[2L])
  }
  zv <- suppressWarnings(as.numeric(rt$statistic))
  if (length(zv) != 1L) zv <- NA_real_
  pv <- suppressWarnings(as.numeric(rt$p.value))
  if (length(pv) != 1L) pv <- NA_real_
  data.frame(
    `New model-Baseline model` = paste(name_new, "-", name_base),
    `New model` = a1,
    `Baseline model` = a2,
    `Difference of AUC` = dauc,
    `95% CI` = ci_chr,
    `Z statistic` = zv,
    `P value` = pv,
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
}

.sm_parse_reclass_lines <- function(output_lines) {
  txt <- paste(output_lines, collapse = "\n")
  pick <- function(pattern) {
    m <- regmatches(txt, regexpr(pattern, txt, perl = TRUE))
    if (length(m) != 1L || !nzchar(m)) return(list(val = NA_character_, p = NA_character_))
    parts <- strsplit(m, ";", fixed = TRUE)[[1L]]
    if (length(parts) < 2L) return(list(val = trimws(parts[1L]), p = NA_character_))
    list(val = trimws(parts[1L]), p = trimws(gsub("^.*p-value:\\s*", "", parts[2L], ignore.case = TRUE)))
  }
  nri <- pick("NRI\\(Categorical\\)\\s*\\[95% CI\\]:[^;]+;[^\\n]+")
  idi <- pick("IDI\\s*\\[95% CI\\]:[^;]+;[^\\n]+")
  if (is.na(nri$val)) {
    li <- grep("NRI", output_lines, value = TRUE, ignore.case = TRUE)
    if (length(li)) {
      s <- li[length(li)]
      parts <- strsplit(s, ";", fixed = TRUE)[[1L]]
      if (length(parts) >= 2L) {
        nri$val <- trimws(gsub("^.*?NRI[^:]*:\\s*", "", parts[1L], ignore.case = TRUE))
        nri$p <- trimws(gsub("^.*p-value:\\s*", "", parts[2L], ignore.case = TRUE))
      }
    }
  }
  if (is.na(idi$val)) {
    li <- grep("^\\s*IDI", output_lines, value = TRUE, ignore.case = TRUE)
    if (length(li)) {
      s <- li[length(li)]
      parts <- strsplit(s, ";", fixed = TRUE)[[1L]]
      if (length(parts) >= 2L) {
        idi$val <- trimws(parts[1L])
        idi$p <- trimws(gsub("^.*p-value:\\s*", "", parts[2L], ignore.case = TRUE))
      }
    }
  }
  list(nri = nri, idi = idi)
}

.sm_nri_idi_one <- function(df_rc, predrisk1, predrisk2, cutoffs) {
  if (!requireNamespace("PredictABEL", quietly = TRUE)) {
    stop("block_Supplementary_ml: 需要 PredictABEL 包计算 NRI/IDI。", call. = FALSE)
  }
  out <- tryCatch(
    utils::capture.output(
      PredictABEL::reclassification(
        data = df_rc,
        cOutcome = "Group",
        predrisk1 = as.numeric(predrisk1),
        predrisk2 = as.numeric(predrisk2),
        cutoff = cutoffs
      )
    ),
    error = function(e) {
      cli::cli_alert_danger("PredictABEL::reclassification: {e$message}")
      character()
    }
  )
  if (!length(out)) return(NULL)
  .sm_parse_reclass_lines(out)
}

.sm_run_delong_grid <- function(y01, preds_named, method) {
  nm <- names(preds_named)
  n <- length(nm)
  if (n < 2L) return(NULL)
  rows <- list()
  for (i in seq_len(n - 1L)) {
    for (j in (i + 1L):n) {
      r <- .sm_delong_pair_fixed_names(
        y01, preds_named[[nm[i]]], preds_named[[nm[j]]], nm[i], nm[j], method
      )
      if (!is.null(r)) rows[[length(rows) + 1L]] <- r
    }
  }
  if (!length(rows)) return(NULL)
  dplyr::bind_rows(rows)
}

.sm_run_nri_grid <- function(df_rc, preds_named, cutoffs) {
  nm <- names(preds_named)
  n <- length(nm)
  if (n < 2L) return(NULL)
  rows <- list()
  for (i in seq_len(n - 1L)) {
    for (j in (i + 1L):n) {
      pr <- .sm_nri_idi_one(
        df_rc,
        preds_named[[nm[j]]],
        preds_named[[nm[i]]],
        cutoffs
      )
      if (is.null(pr)) next
      nri <- pr$nri
      idi <- pr$idi
      rows[[length(rows) + 1L]] <- data.frame(
        `New model-Baseline model` = paste(nm[i], "-", nm[j]),
        NRI = nri$val %||% NA_character_,
        `P value_NRI` = nri$p %||% NA_character_,
        IDI = idi$val %||% NA_character_,
        `P value_IDI` = idi$p %||% NA_character_,
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
    }
  }
  if (!length(rows)) return(NULL)
  dplyr::bind_rows(rows)
}

block_Supplementary_ml <- function(ctx, ...) {
  cfg <- ctx$config
  sm <- cfg$supplementary_ml %||% list()
  if (isFALSE(sm$enable %||% TRUE)) {
    cli::cli_alert_info("config$supplementary_ml$enable=FALSE，跳过 supplementary_ml。")
    return(ctx)
  }

  methods <- tolower(as.character(sm$methods %||% c(
    "hyperparameters", "logloss", "delong", "nri_idi"
  )))
  if (!length(methods)) {
    cli::cli_alert_info("supplementary_ml$methods 为空，跳过。")
    return(ctx)
  }

  models <- ctx$results[["ml_models"]] %||% list()
  tags <- names(models)
  if (!length(tags)) {
    stop("block_Supplementary_ml: 请先运行 ml_models。", call. = FALSE)
  }

  study_type <- tolower(trimws(cfg$project$study_type %||% "incidence"))
  prognosis <- identical(study_type, "prognosis")
  ref_group <- cfg$project$reference_group %||% "Control"
  ana_group <- cfg$project$analysis_group %||% cfg$project$disease %||% "Case"
  outcome_ml <- cfg$data$outcome_column %||% "Disease"
  ev_var <- cfg$survival$event_var %||% NULL
  pred_ana <- ctx$results$ml_pred_ana_col %||% paste0(".pred_", ana_group)

  ml_block_dir <- ctx$log$block_output_dirs[["ml_dt"]] %||%
    ctx$log$block_output_dirs[["ml_models_bundle"]] %||% ""
  data_dir <- file.path(ml_block_dir, "Data")
  if (!nzchar(ml_block_dir) || !dir.exists(data_dir)) {
    data_dir <- file.path(ctx$output_dir, "Data")
  }
  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables")
  if (!dir.exists(tbl_dir)) dir.create(tbl_dir, recursive = TRUE)

  eps <- as.numeric(sm$logloss_epsilon %||% 1e-15)[1L]
  tbl_digits <- as.integer(sm$table_digits %||% cfg$performance_ml$table_digits %||% 3L)[1L]
  delong_m <- tolower(trimws(as.character(sm$delong_method %||% "delong")[1L]))
  nri_cut <- sm$nri_cutoff %||% c(0, 0.5, 1)

  display_names <- vapply(tags, .sm_display_from_tag, character(1L))
  names(display_names) <- tags

  loaded <- list()
  for (tg in tags) {
    L <- .sm_load_evalresult(resolve_ml_models_dir_for_tag(ctx, tg), tg)
    if (!is.null(L)) loaded[[tg]] <- L
  }
  tags_ok <- names(loaded)
  if (!length(tags_ok)) {
    stop("block_Supplementary_ml: 未找到 Models/evalresult_*.RData。", call. = FALSE)
  }

  ## ── Table S2: 超参数（汇总全部模型）────────────────────────────────────────
  if ("hyperparameters" %in% methods || "s2" %in% methods || "hpbest" %in% methods) {
    hp_df <- .sm_collect_hpbest_all(ctx, tags_ok, display_names)
    if (is.null(hp_df) || !nrow(hp_df)) {
      cli::cli_alert_warning("block_Supplementary_ml: 未找到任何模型的 Hpbest 超参数，跳过超参数表。")
    } else {
      if ("Model" %in% names(hp_df)) {
        hp_df <- hp_df[, c("Model", setdiff(names(hp_df), "Model")), drop = FALSE]
      }
      hp_pub <- pub_paths(
        ctx, tbl_dir, "supp_table",
        "Hyperparameters for machine learning models",
        "xlsx"
      )
      export_sci_table(hp_df, hp_pub$filepath, title = hp_pub$title)
      ctx <- save_result(ctx, "supplementary_ml_s2", hp_df, "Table_S2_hyperparameters.csv")
      cli::cli_alert_success("block_Supplementary_ml: 超参数表已汇总 {length(unique(hp_df$Model))} 个模型。")
    }
  }

  ## ── 准备预测与真值（Log-loss / DeLong / NRI 共用）────────────────────────
  need_preds <- any(c("logloss", "s3", "delong", "s4", "s5", "nri_idi", "s6", "s7") %in% methods)
  if (need_preds) {
    tr <- ctx$data$train
    te <- ctx$data$test
    if (is.null(tr) || is.null(te)) {
      stop("block_Supplementary_ml: 需要 ctx$data$train / test。", call. = FALSE)
    }

    tv_tr <- .sm_outcome_binary(ctx, tr, prognosis, outcome_ml, ev_var, ref_group, ana_group)
    tv_te <- .sm_outcome_binary(ctx, te, prognosis, outcome_ml, ev_var, ref_group, ana_group)
    y_tr <- tv_tr$y
    y_te <- tv_te$y
    if (prognosis) {
      y_tr[!tv_tr$ok] <- NA_real_
      y_te[!tv_te$ok] <- NA_real_
    }

    pred_tr_list <- list()
    pred_te_list <- list()
    for (tg in tags_ok) {
      pr <- loaded[[tg]]$predtrain
      pe <- loaded[[tg]]$predtest
      if (!pred_ana %in% names(pr) || !pred_ana %in% names(pe)) next
      nm <- display_names[tg]
      pred_tr_list[[nm]] <- as.numeric(pr[[pred_ana]])
      pred_te_list[[nm]] <- as.numeric(pe[[pred_ana]])
    }
    if (!length(pred_tr_list)) {
      stop("block_Supplementary_ml: 无法读取任何模型的预测概率列。", call. = FALSE)
    }

    ## ── Table S3: Log-Loss ────────────────────────────────────────────────
    if ("logloss" %in% methods || "s3" %in% methods) {
      nm_ll <- intersect(names(pred_tr_list), names(pred_te_list))
      if (!length(nm_ll)) {
        cli::cli_alert_warning("Log-Loss: 训练/验证预测列名无交集，跳过 S3。")
      } else {
      ll_tr <- vapply(nm_ll, function(nm) {
        .sm_logloss_one(y_tr, pred_tr_list[[nm]], eps)
      }, numeric(1L))
      ll_te <- vapply(nm_ll, function(nm) {
        .sm_logloss_one(y_te, pred_te_list[[nm]], eps)
      }, numeric(1L))
      df_ll <- data.frame(
        Model = nm_ll,
        Log_Loss_Train = unname(ll_tr),
        Log_Loss_Validation = unname(ll_te),
        stringsAsFactors = FALSE
      )
      df_ll <- .sm_round_df_numeric(df_ll, tbl_digits)
      ll_pub <- pub_paths(
        ctx, tbl_dir, "supp_table",
        "Log-Loss (training and validation sets)",
        "xlsx"
      )
      export_sci_table(df_ll, ll_pub$filepath, title = ll_pub$title)
      ctx <- save_result(ctx, "supplementary_ml_s3", df_ll, "Table_S3_logloss.csv")
      }
    }

    ## ── Table S4 / S5: DeLong ─────────────────────────────────────────────
    if ("delong" %in% methods || "s4" %in% methods || "s5" %in% methods) {
      d_tr <- .sm_run_delong_grid(y_tr, pred_tr_list, delong_m)
      d_te <- .sm_run_delong_grid(y_te, pred_te_list, delong_m)
      if (!is.null(d_tr) && ("delong" %in% methods || "s4" %in% methods)) {
        d_tr <- .sm_round_df_numeric(d_tr, tbl_digits)
        del_tr_pub <- pub_paths(
          ctx, tbl_dir, "supp_table",
          "DeLong tests (training set)",
          "xlsx"
        )
        export_sci_table(d_tr, del_tr_pub$filepath, title = del_tr_pub$title)
        ctx <- save_result(ctx, "supplementary_ml_s4", d_tr, "Table_S4_delong_train.csv")
      }
      if (!is.null(d_te) && ("delong" %in% methods || "s5" %in% methods)) {
        d_te <- .sm_round_df_numeric(d_te, tbl_digits)
        del_va_pub <- pub_paths(
          ctx, tbl_dir, "supp_table",
          "DeLong tests (validation set)",
          "xlsx"
        )
        export_sci_table(d_te, del_va_pub$filepath, title = del_va_pub$title)
        ctx <- save_result(ctx, "supplementary_ml_s5", d_te, "Table_S5_delong_validation.csv")
      }
    }

    ## ── Table S6 / S7: NRI & IDI（PredictABEL）────────────────────────────
    if ("nri_idi" %in% methods || "s6" %in% methods || "s7" %in% methods) {
      df_tr <- data.frame(Group = y_tr, stringsAsFactors = FALSE)
      df_te <- data.frame(Group = y_te, stringsAsFactors = FALSE)
      ok_tr <- is.finite(df_tr$Group)
      ok_te <- is.finite(df_te$Group)
      df_tr <- df_tr[ok_tr, , drop = FALSE]
      df_te <- df_te[ok_te, , drop = FALSE]
      ptr <- lapply(pred_tr_list, function(z) z[ok_tr])
      pte <- lapply(pred_te_list, function(z) z[ok_te])

      nri_tr <- .sm_run_nri_grid(df_tr, ptr, nri_cut)
      nri_te <- .sm_run_nri_grid(df_te, pte, nri_cut)

      .sm_fill_nri_na_p <- function(df) {
        if (is.null(df) || !nrow(df)) return(df)
        for (cn in c("P value_NRI", "P value_IDI", "P value (NRI)", "P value (IDI)")) {
          if (!cn %in% names(df)) next
          x <- as.character(df[[cn]])
          bad <- is.na(x) | !nzchar(trimws(x)) | toupper(trimws(x)) %in% c("NA", "NAN")
          x[bad] <- "\u2014"
          df[[cn]] <- x
        }
        df
      }
      if (!is.null(nri_tr) && ("nri_idi" %in% methods || "s6" %in% methods)) {
        nri_tr <- .sm_fill_nri_na_p(nri_tr)
        names(nri_tr)[names(nri_tr) == "P value_NRI"] <- "P value (NRI)"
        names(nri_tr)[names(nri_tr) == "P value_IDI"] <- "P value (IDI)"
        nri_tr_pub <- pub_paths(
          ctx, tbl_dir, "supp_table",
          "NRI and IDI (training set)",
          "xlsx"
        )
        export_sci_table(nri_tr, nri_tr_pub$filepath, title = nri_tr_pub$title)
        ctx <- save_result(ctx, "supplementary_ml_s6", nri_tr, "Table_S6_nri_idi_train.csv")
      }
      if (!is.null(nri_te) && ("nri_idi" %in% methods || "s7" %in% methods)) {
        nri_te <- .sm_fill_nri_na_p(nri_te)
        names(nri_te)[names(nri_te) == "P value_NRI"] <- "P value (NRI)"
        names(nri_te)[names(nri_te) == "P value_IDI"] <- "P value (IDI)"
        nri_va_pub <- pub_paths(
          ctx, tbl_dir, "supp_table",
          "NRI and IDI (validation set)",
          "xlsx"
        )
        export_sci_table(nri_te, nri_va_pub$filepath, title = nri_va_pub$title)
        ctx <- save_result(ctx, "supplementary_ml_s7", nri_te, "Table_S7_nri_idi_validation.csv")
      }
    }
  }

  ctx <- render_queued_tables(ctx)
  ctx$results$supplementary_ml_done <- TRUE
  cli::cli_alert_success("block_Supplementary_ml 完成（methods: {paste(methods, collapse = ', ')})。")
  ctx
}

register_block(
  "supplementary_ml",
  block_Supplementary_ml,
  "ML 补充表：S2 超参数、S3 Log-Loss、S4/S5 DeLong、S6/S7 NRI/IDI（发病/预后）"
)
