###############################################################################
#  pe_plan_supplement — 方案补跑：3.2 个人变化指标 + S1 单胎 Logistic + S2 PE vs SPE 轨迹
#  课题壳（run/61_preeclampsia/blocks_shell/），不进 Blocks 方法族。
###############################################################################

.pe_sup_ensure_pe_vs_spe <- function(data, cleaned = NULL) {
  if ("PE_vs_SPE" %in% names(data) && !all(is.na(data$PE_vs_SPE))) {
    return(data)
  }
  if (is.null(cleaned) || !is.data.frame(cleaned)) {
    stop("pe_plan_supplement: 缺少 PE_vs_SPE，且无 cleaned 可回补", call. = FALSE)
  }
  id <- intersect(c("Admission_Num"), names(data))
  if (!length(id) || !id[[1L]] %in% names(cleaned) || !"PE_vs_SPE" %in% names(cleaned)) {
    stop("pe_plan_supplement: 无法按 Admission_Num 回补 PE_vs_SPE", call. = FALSE)
  }
  id <- id[[1L]]
  map <- cleaned[, c(id, "PE_vs_SPE"), drop = FALSE]
  names(map)[1L] <- ".pe_id"
  data$.pe_id <- data[[id]]
  data$PE_vs_SPE <- NULL
  data <- merge(data, map, by = ".pe_id", all.x = TRUE, sort = FALSE)
  data$.pe_id <- NULL
  if (!is.factor(data$PE_vs_SPE)) {
    data$PE_vs_SPE <- factor(as.character(data$PE_vs_SPE), levels = c("PE", "SPE"))
  }
  cli::cli_alert_success(
    "已回补 PE_vs_SPE：PE={sum(data$PE_vs_SPE=='PE', na.rm=TRUE)}, SPE={sum(data$PE_vs_SPE=='SPE', na.rm=TRUE)}, NA={sum(is.na(data$PE_vs_SPE))}"
  )
  data
}

.pe_sup_marker_specs <- function() {
  list(
    list(stem = "Weight", times = c("Pre", "Early", "Mid", "Late")),
    list(stem = "BMI", times = c("Pre", "Early", "Mid", "Late")),
    list(stem = "Total_Cholesterol", times = c("Early", "Mid", "Late")),
    list(stem = "Triglycerides", times = c("Early", "Mid", "Late")),
    list(stem = "HDL_Cholesterol", times = c("Early", "Mid", "Late")),
    list(stem = "LDL_Cholesterol", times = c("Early", "Mid", "Late")),
    list(stem = "FFA_Cholesterol", times = c("Early", "Mid", "Late"))
  )
}

.pe_sup_compute_features <- function(data, specs = .pe_sup_marker_specs()) {
  out <- data.frame(row.names = rownames(data))
  if ("Admission_Num" %in% names(data)) out$Admission_Num <- data$Admission_Num
  for (sp in specs) {
    stem <- sp$stem
    times <- sp$times
    cols <- paste0(times, "_", stem)
    if (!any(cols %in% names(data))) next
    mat <- sapply(cols, function(cn) {
      if (!cn %in% names(data)) return(rep(NA_real_, nrow(data)))
      suppressWarnings(as.numeric(data[[cn]]))
    })
    if (!is.matrix(mat)) mat <- cbind(mat)
    colnames(mat) <- cols
    t_idx <- seq_along(times)
    start <- apply(mat, 1L, function(v) {
      ok <- which(is.finite(v))
      if (!length(ok)) return(NA_real_)
      v[[ok[[1L]]]]
    })
    mid_col <- paste0("Mid_", stem)
    mid <- if (mid_col %in% colnames(mat)) mat[, mid_col] else rep(NA_real_, nrow(mat))
    delta <- apply(mat, 1L, function(v) {
      ok <- which(is.finite(v))
      if (length(ok) < 2L) return(NA_real_)
      v[[ok[[length(ok)]]]] - v[[ok[[1L]]]]
    })
    slope <- apply(mat, 1L, function(v) {
      ok <- which(is.finite(v))
      if (length(ok) < 2L) return(NA_real_)
      unname(stats::coef(stats::lm(v[ok] ~ t_idx[ok]))[2L])
    })
    out[[paste0(stem, "_start")]] <- as.numeric(start)
    out[[paste0(stem, "_mid")]] <- as.numeric(mid)
    out[[paste0(stem, "_delta")]] <- as.numeric(delta)
    out[[paste0(stem, "_slope")]] <- as.numeric(slope)
  }
  out
}

.pe_sup_fit_or <- function(y, x, covs_df = NULL, use_firth = FALSE) {
  d <- data.frame(y = as.integer(y), x = as.numeric(x))
  if (!is.null(covs_df) && ncol(covs_df)) {
    for (cn in names(covs_df)) d[[cn]] <- covs_df[[cn]]
  }
  d <- d[stats::complete.cases(d), , drop = FALSE]
  if (nrow(d) < 30L || length(unique(d$y)) < 2L || length(unique(d$x)) < 2L) {
    return(list(n = nrow(d), or = NA_real_, lo = NA_real_, hi = NA_real_,
                p = NA_real_, note = "insufficient"))
  }
  rhs <- c("x", setdiff(names(d), c("y", "x")))
  fml <- stats::as.formula(paste("y ~", paste(rhs, collapse = " + ")))
  if (isTRUE(use_firth) && requireNamespace("logistf", quietly = TRUE)) {
    fit <- tryCatch(logistf::logistf(fml, data = d, pl = TRUE), error = function(e) e)
    if (inherits(fit, "error")) {
      return(list(n = nrow(d), or = NA_real_, lo = NA_real_, hi = NA_real_,
                  p = NA_real_, note = conditionMessage(fit)))
    }
    rn <- names(fit$coefficients)
    hit <- which(rn == "x")
    if (!length(hit)) hit <- grep("^x$", rn)
    if (!length(hit)) {
      return(list(n = nrow(d), or = NA_real_, lo = NA_real_, hi = NA_real_,
                  p = NA_real_, note = "no coef x"))
    }
    i <- hit[[1L]]
    return(list(
      n = nrow(d),
      or = unname(exp(fit$coefficients[[i]])),
      lo = unname(exp(fit$ci.lower[[i]])),
      hi = unname(exp(fit$ci.upper[[i]])),
      p = unname(fit$prob[[i]]),
      note = "firth"
    ))
  }
  fit <- tryCatch(stats::glm(fml, data = d, family = stats::binomial()), error = function(e) e)
  if (inherits(fit, "error")) {
    return(list(n = nrow(d), or = NA_real_, lo = NA_real_, hi = NA_real_,
                p = NA_real_, note = conditionMessage(fit)))
  }
  sm <- summary(fit)$coefficients
  if (!"x" %in% rownames(sm)) {
    return(list(n = nrow(d), or = NA_real_, lo = NA_real_, hi = NA_real_,
                p = NA_real_, note = "no coef x"))
  }
  est <- sm["x", "Estimate"]
  se <- sm["x", "Std. Error"]
  p <- sm["x", "Pr(>|z|)"]
  list(
    n = nrow(d),
    or = unname(exp(est)),
    lo = unname(exp(est - 1.96 * se)),
    hi = unname(exp(est + 1.96 * se)),
    p = unname(p),
    note = "glm"
  )
}

.pe_sup_outcome01 <- function(data, outcome) {
  if (!outcome %in% names(data)) {
    stop("outcome column missing: ", outcome, call. = FALSE)
  }
  if (identical(outcome, "Preterm34")) {
    return(as.integer(as.character(data$Preterm34) == "Preterm34"))
  }
  # 其余二分类结局：1 / "1" / Yes 视为事件
  y <- data[[outcome]]
  if (is.factor(y) || is.character(y)) {
    ys <- trimws(as.character(y))
    return(as.integer(ys %in% c("1", "Yes", "yes", "TRUE", "True")))
  }
  as.integer(as.numeric(y) == 1)
}

.pe_sup_use_firth <- function(outcome) {
  outcome %in% c(
    "Preterm34", "Apgar1_lt8", "Apgar5_lt8",
    "Newborn_lt1500", "Newborn_lt2000"
  )
}

.pe_sup_run_feature_models <- function(data, feat, m2, outcomes = c("Preterm34", "GDM01")) {
  feat_cols <- setdiff(names(feat), "Admission_Num")
  rows <- list()
  cov_base <- data[, intersect(m2, names(data)), drop = FALSE]
  for (oc in outcomes) {
    y <- .pe_sup_outcome01(data, oc)
    use_firth <- .pe_sup_use_firth(oc)
    for (fc in feat_cols) {
      for (model in c("Crude", "Model2")) {
        covs <- if (identical(model, "Model2")) cov_base else NULL
        # BMI 特征时 Model2 去掉 Pre_BMI，避免同源共线
        if (!is.null(covs) && grepl("^BMI_", fc) && "Pre_BMI" %in% names(covs)) {
          covs$Pre_BMI <- NULL
        }
        if (!is.null(covs) && grepl("^Weight_", fc) && "Pre_Weight" %in% names(covs)) {
          covs$Pre_Weight <- NULL
        }
        res <- .pe_sup_fit_or(y, feat[[fc]], covs_df = covs, use_firth = use_firth)
        rows[[length(rows) + 1L]] <- data.frame(
          outcome = oc,
          feature = fc,
          model = model,
          n = res$n,
          OR = round(res$or, 3),
          CI_low = round(res$lo, 3),
          CI_high = round(res$hi, 3),
          P = ifelse(is.finite(res$p), signif(res$p, 3), NA_real_),
          method = res$note,
          stringsAsFactors = FALSE
        )
      }
    }
  }
  do.call(rbind, rows)
}

.pe_sup_run_disease_logistic <- function(data, m2, outcome, label) {
  y <- .pe_sup_outcome01(data, outcome)
  d <- data.frame(
    y = y,
    Disease = factor(
      as.character(data$Disease),
      levels = c(
        "Non-preeclampsia",
        "Preeclampsia",
        "Chronic hypertension with preeclampsia"
      )
    ),
    stringsAsFactors = FALSE
  )
  for (cn in intersect(m2, names(data))) d[[cn]] <- data[[cn]]
  d <- d[stats::complete.cases(d), , drop = FALSE]
  use_firth <- .pe_sup_use_firth(outcome)
  rhs <- c("Disease", intersect(m2, names(d)))
  fml <- stats::as.formula(paste("y ~", paste(rhs, collapse = " + ")))
  out <- list()
  if (isTRUE(use_firth) && requireNamespace("logistf", quietly = TRUE)) {
    fit <- tryCatch(logistf::logistf(fml, data = d, pl = TRUE), error = function(e) e)
    if (!inherits(fit, "error")) {
      rn <- names(fit$coefficients)
      # 忽略大小写匹配 Disease 水平（含 with preeclampsia）
      keep <- which(
        grepl("^Disease", rn) &
          grepl("preeclampsia", rn, ignore.case = TRUE)
      )
      for (i in keep) {
        out[[length(out) + 1L]] <- data.frame(
          label = label, outcome = outcome, term = rn[[i]],
          n = nrow(d), events = sum(d$y == 1L),
          OR = round(exp(fit$coefficients[[i]]), 3),
          CI_low = round(exp(fit$ci.lower[[i]]), 3),
          CI_high = round(exp(fit$ci.upper[[i]]), 3),
          P = signif(fit$prob[[i]], 3),
          method = "firth",
          stringsAsFactors = FALSE
        )
      }
      if (length(out)) return(do.call(rbind, out))
    }
  }
  fit <- stats::glm(fml, data = d, family = stats::binomial())
  sm <- summary(fit)$coefficients
  keep <- grep("^Disease", rownames(sm))
  for (i in keep) {
    est <- sm[i, "Estimate"]; se <- sm[i, "Std. Error"]
    out[[length(out) + 1L]] <- data.frame(
      label = label, outcome = outcome, term = rownames(sm)[[i]],
      n = nrow(d), events = sum(d$y == 1L),
      OR = round(exp(est), 3),
      CI_low = round(exp(est - 1.96 * se), 3),
      CI_high = round(exp(est + 1.96 * se), 3),
      P = signif(sm[i, "Pr(>|z|)"], 3),
      method = "glm",
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, out)
}

block_pe_plan_supplement <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(cli)
  })
  cfg <- ctx$config
  root_out <- cfg$project$output_dir %||% ctx$output_dir
  # shared 根：…/Full_pipeline/_shared 或 …/Full_pipeline
  out_base <- if (basename(as.character(root_out)[1L]) == "_shared") {
    dirname(as.character(root_out)[1L])
  } else {
    as.character(root_out)[1L]
  }
  sup_root <- file.path(out_base, "_shared", "supplement_plan")
  dir.create(sup_root, recursive = TRUE, showWarnings = FALSE)

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    stop("pe_plan_supplement: 无 imputed/cleaned 数据", call. = FALSE)
  }
  cleaned <- ctx$data$cleaned
  data <- .pe_sup_ensure_pe_vs_spe(data, cleaned)
  ctx$data$imputed <- data

  m2 <- as.character(ctx$results$Model2Factors %||% character(0))
  if (!length(m2)) {
    m2 <- c("Age", "Height_cm", "Assisted_Reproduction", "Is_Twin",
            "Parity", "Pre_BMI", "Pregnancy_Delivery", "Tandem_Screening")
  }

  # ── S2：PE vs SPE 轨迹图 ───────────────────────────────────────────────
  cli::cli_h2("S2: PE vs SPE 轨迹图")
  s2_dir <- file.path(out_base, "_shared", "sensitivity", "S2_PE_vs_SPE_trajectory")
  dir.create(file.path(s2_dir, "Figures"), recursive = TRUE, showWarnings = FALSE)
  data_s2 <- data[!is.na(data$PE_vs_SPE), , drop = FALSE]
  cli::cli_alert_info("S2 样本: n={nrow(data_s2)} (PE/SPE only)")
  if (nrow(data_s2) >= 50L && exists("block_trajectory_plot_gbmt_priori_mean_ci", mode = "function")) {
    ctx_s2 <- ctx
    ctx_s2$data$imputed <- data_s2
    ctx_s2$config$trajectory_plot_gbmt_priori_mean_ci$strata_var <- "PE_vs_SPE"
    ctx_s2$config$trajectory_plot_gbmt_priori$strata_var <- "PE_vs_SPE"
    ctx_s2$config$project$output_dir <- s2_dir
    # 临时改写输出目录字段供 save_figure 使用
    ctx_s2$output_dir <- s2_dir
    ctx_s2$output_dir_figures <- file.path(s2_dir, "Figures")
    ctx_s2$output_dir_tables <- file.path(s2_dir, "Tables")
    dir.create(ctx_s2$output_dir_tables, recursive = TRUE, showWarnings = FALSE)
    ctx_s2$results$figure_queue <- list()
    ctx_s2 <- tryCatch(
      block_trajectory_plot_gbmt_priori_mean_ci(ctx_s2),
      error = function(e) {
        cli::cli_alert_warning("S2 mean_ci 失败: {conditionMessage(e)}")
        ctx_s2
      }
    )
    if (exists("render_queued_figures", mode = "function")) {
      ctx_s2 <- tryCatch(render_queued_figures(ctx_s2), error = function(e) ctx_s2)
    }
    if (exists("block_trajectory_plot_gbmt_priori", mode = "function")) {
      ctx_s2$results$figure_queue <- list()
      ctx_s2 <- tryCatch(
        block_trajectory_plot_gbmt_priori(ctx_s2),
        error = function(e) {
          cli::cli_alert_warning("S2 loess 失败: {conditionMessage(e)}")
          ctx_s2
        }
      )
      if (exists("render_queued_figures", mode = "function")) {
        ctx_s2 <- tryCatch(render_queued_figures(ctx_s2), error = function(e) ctx_s2)
      }
    }
    n_fig <- length(list.files(file.path(s2_dir, "Figures"), pattern = "\\.pdf$"))
    cli::cli_alert_success("S2 轨迹输出 → {s2_dir}（{n_fig} 张 PDF）")
  } else {
    cli::cli_alert_warning("S2 跳过：样本不足或轨迹块未加载")
  }

  # ── S1：仅单胎 Logistic（全 pe_outcomes；稀有结局 Firth）────────────────
  cli::cli_h2("S1: 仅单胎 Logistic")
  s1_dir <- file.path(out_base, "_shared", "sensitivity", "S1_singleton_logistic")
  dir.create(s1_dir, recursive = TRUE, showWarnings = FALSE)
  data_s1 <- data[as.character(data$Is_Twin) == "No", , drop = FALSE]
  m2_s1 <- setdiff(m2, "Is_Twin")
  # 兼容旧表：仅 Preterm + GDM（不改名覆盖历史口径时可对照）
  s1_legacy <- rbind(
    .pe_sup_run_disease_logistic(data_s1, m2_s1, "Preterm34", "SA_singleton_only"),
    .pe_sup_run_disease_logistic(data_s1, m2_s1, "GDM01", "SA_singleton_only")
  )
  utils::write.csv(s1_legacy, file.path(s1_dir, "Table_S1_singleton_Disease_logistic.csv"),
                   row.names = FALSE, fileEncoding = "UTF-8")
  if (requireNamespace("openxlsx", quietly = TRUE)) {
    openxlsx::write.xlsx(s1_legacy, file.path(s1_dir, "Table_S1_singleton_Disease_logistic.xlsx"))
  }
  # 全结局扩展表（_all_outcomes；稀有结局 Firth）
  pe_oc <- names(ctx$config$pe_outcomes %||% list())
  if (!length(pe_oc)) {
    pe_oc <- c(
      "Preterm34", "GDM01", "Cesarean01",
      "Apgar1_lt8", "Apgar5_lt8", "Newborn_lt1500", "Newborn_lt2000"
    )
  }
  pe_oc <- pe_oc[pe_oc %in% names(data_s1)]
  s1_all <- do.call(
    rbind,
    lapply(pe_oc, function(oc) {
      tryCatch(
        .pe_sup_run_disease_logistic(data_s1, m2_s1, oc, "SA_singleton_only"),
        error = function(e) {
          cli::cli_alert_warning("S1 {oc} 失败: {conditionMessage(e)}")
          NULL
        }
      )
    })
  )
  if (!is.null(s1_all) && nrow(s1_all)) {
    utils::write.csv(
      s1_all,
      file.path(s1_dir, "Table_S1_singleton_Disease_logistic_all_outcomes.csv"),
      row.names = FALSE, fileEncoding = "UTF-8"
    )
    if (requireNamespace("openxlsx", quietly = TRUE)) {
      openxlsx::write.xlsx(
        s1_all,
        file.path(s1_dir, "Table_S1_singleton_Disease_logistic_all_outcomes.xlsx")
      )
    }
  }
  cli::cli_alert_success(
    "S1 单胎 Logistic n={nrow(data_s1)}；legacy={nrow(s1_legacy)} 行；all_outcomes={nrow(s1_all %||% data.frame())} 行 → {s1_dir}"
  )

  # ── 3.2 个人变化指标 ───────────────────────────────────────────────────
  cli::cli_h2("3.2: 个人变化指标 → Preterm34 / GDM01")
  feat <- .pe_sup_compute_features(data)
  feat_path <- file.path(sup_root, "Data")
  dir.create(feat_path, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(feat, file.path(feat_path, "individual_traj_features.csv"),
                   row.names = FALSE, fileEncoding = "UTF-8")
  # 合并进分析表
  if ("Admission_Num" %in% names(data) && "Admission_Num" %in% names(feat)) {
    data_f <- merge(data, feat, by = "Admission_Num", all.x = TRUE, sort = FALSE)
  } else {
    data_f <- cbind(data, feat[, setdiff(names(feat), "Admission_Num"), drop = FALSE])
  }
  tab32 <- .pe_sup_run_feature_models(data_f, feat, m2)
  tab_dir <- file.path(sup_root, "Tables")
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab32, file.path(tab_dir, "Table_3_2_traj_features_logistic.csv"),
                   row.names = FALSE, fileEncoding = "UTF-8")
  if (requireNamespace("openxlsx", quietly = TRUE)) {
    openxlsx::write.xlsx(tab32, file.path(tab_dir, "Table_3_2_traj_features_logistic.xlsx"))
  }
  cli::cli_alert_success(
    "3.2 完成: {length(setdiff(names(feat),'Admission_Num'))} 个特征 × 2 结局；Firth 用于 Preterm34"
  )

  ctx$results$pe_plan_supplement <- list(
    s1_n = nrow(data_s1),
    s2_n = nrow(data_s2),
    n_features = length(setdiff(names(feat), "Admission_Num")),
    out_dirs = c(s1_dir, s2_dir, sup_root)
  )
  ctx
}

register_block(
  "pe_plan_supplement",
  block_pe_plan_supplement,
  "子痫方案补跑：3.2变化指标 + S1单胎Logistic + S2 PE/SPE轨迹"
)
