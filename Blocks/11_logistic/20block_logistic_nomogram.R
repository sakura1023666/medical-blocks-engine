###############################################################################
#  logistic_nomogram — 多时点 logistic 列线图（Jin Fig2：院内 / 30d / 365d）
#
#  register_block: "logistic_nomogram"
#  典型流水线: derived_grouping / cox_multi_horizon 之后
#  依赖: rms
#
#  config$logistic_nomogram = list(
#    enable = TRUE,
#    selection = "backward",         # none | backward（α=0.05；对齐 Jin stepwise）
#    selection_alpha = 0.05,
#    candidate_mode = "shared_clinical",  # shared_clinical | explicit
#    candidate_features = NULL,      # 仅 explicit 时用手写名单
#    force_features = NULL,          # 额外强制（默认仍强制暴露+SOFA）
#    horizons = c("hosp", "d30", "d365"),
#    hosp = list(event = "fustatus", label = "In-hospital mortality", panel = "A"),
#    d30  = list(event = "event_d30", label = "30-day mortality", panel = "B"),
#    d365 = list(event = "event_d365", label = "365-day mortality", panel = "C"),
#    combine_panels = TRUE,          # 拼成一张 A|B|C（对齐 Jin Fig2）
#    bootstrap_B = 200L,             # 主时点（hosp）校准
#    seed = 42L
#  )
#  兼容: 缺 config$logistic_nomogram 时回读 config$jin_index_sofa$nomogram
#
#  候选池 shared_clinical：当前表可用临床列 − 结局/时间/ID/疾病泄漏/
#  暴露公式成分/其它复合指标/衍生分层；双库对齐后自然为交集。
#  各时点独立 backward（原文 A/B/C 变量可不一致）。
###############################################################################

.logistic_nomogram_cfg <- function(cfg) {
  top <- cfg$logistic_nomogram %||% list()
  if (length(top)) return(top)
  (cfg$jin_index_sofa %||% list())$nomogram %||% list()
}

.logistic_nomogram_all_index_names <- function() {
  if (exists(".idx_definitions", mode = "function")) {
    defs <- tryCatch(.idx_definitions(), error = function(e) NULL)
    if (is.list(defs) && length(defs)) {
      nm <- vapply(defs, function(x) as.character(x$name %||% "")[1L], character(1))
      return(unique(nm[nzchar(nm)]))
    }
  }
  character(0)
}

.logistic_nomogram_exposure_components <- function(cfg, expo) {
  comps <- character(0)
  if (exists("pipeline_ensure_index_formula_helpers", mode = "function")) {
    tryCatch(
      pipeline_ensure_index_formula_helpers(
        Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "") %||% getwd()
      ),
      error = function(e) NULL
    )
  }
  if (exists("index_get_formula_components", mode = "function") && nzchar(expo)) {
    comps <- tryCatch(
      as.character(index_get_formula_components(expo) %||% character(0)),
      error = function(e) character(0)
    )
  }
  if (exists("pipeline_index_component_vars_only", mode = "function")) {
    comps <- unique(c(
      comps,
      tryCatch(pipeline_index_component_vars_only(cfg), error = function(e) character(0))
    ))
  }
  ## 常见血小板别名
  if (any(c("Platelet_Count", "PLT") %in% comps)) {
    comps <- unique(c(comps, "Platelet_Count", "PLT", "Platelets"))
  }
  unique(comps[nzchar(comps)])
}

.logistic_nomogram_resolve_event <- function(data, preferred) {
  preferred <- as.character(preferred %||% "")[1L]
  if (nzchar(preferred) && preferred %in% names(data)) return(preferred)
  alts <- c(
    preferred,
    "fustatus", "event_d30", "event_30d", "event_d365", "event_365d",
    "is_hosp_dead", "hospital_expire_flag"
  )
  hit <- alts[alts %in% names(data)]
  if (!length(hit)) return(NA_character_)
  hit[[1L]]
}

.logistic_nomogram_y01 <- function(y, cfg) {
  if (exists("pipeline_outcome_as_01", mode = "function")) {
    y01 <- tryCatch(pipeline_outcome_as_01(y, cfg = cfg), error = function(e) NULL)
    if (!is.null(y01) && length(y01) == length(y)) return(as.integer(y01))
  }
  death_labs <- c(
    "1", "yes", "y", "true", "dead", "death", "died", "expire", "expired",
    "deceased", "non-survivor", "nonsurvivor", "non survivor", "死亡", "是"
  )
  yc <- tolower(trimws(as.character(y)))
  if (is.factor(y) || is.character(y)) {
    return(as.integer(yc %in% death_labs))
  }
  as.integer(suppressWarnings(as.numeric(y)) == 1L)
}

#' 双库对齐后的临床候选池（无手写短名单）
.logistic_nomogram_shared_clinical_pool <- function(data, cfg, expo, sofa_var, outcome_vars) {
  ae <- cfg$analysis_exclusion %||% list()
  disease <- as.character(ae$disease_vars %||% character(0))
  comps <- .logistic_nomogram_exposure_components(cfg, expo)
  other_idx <- .logistic_nomogram_all_index_names()
  id_col <- as.character((cfg$data %||% list())$id_column %||% "ID")[1L]

  drop_fixed <- unique(c(
    outcome_vars,
    "futime", "futime_30d", "futime_365d", "time_d30", "time_d365",
    "time_30d", "time_365d", "fu_day", "survival_day",
    "event_d30", "event_d365", "event_30d", "event_365d",
    "fustatus", "is_hosp_dead", "hospital_expire_flag",
    id_col, "ID", "subject_id", "hadm_id", "stay_id", "patientunitstayid",
    "icustay_id", "admissionid",
    "Index_SOFA_Q", "Index_HL", "SOFA_bin", "Group", "Index_tertile",
    paste0(expo, "_tertile"), paste0(expo, "_quartile"), paste0(expo, "_Group"),
    "Age_Group", "BMI_Group", "Disease_Group", "anchor_source",
    "Race", "race", "ethnicity", "Ethnicity",
    expo, sofa_var,
    disease, comps, other_idx,
    ## 与 SOFA 重叠的严重度评分（强制 SOFA 后不再进列线图）
    "APSIII", "OASIS", "SAPSII", "SAPS", "SIRS", "SOFA_score",
    "GCS", "gcs", "LODS", "Charlson", "CHARLSON",
    ## 住院/ICU 天数与随访时间（与死亡强共线）
    "hosp_day", "hosp_survival_day", "icu_day", "icu_day_num",
    "icu_to_disch_day", "icu_survival_day", "los_hospital", "los_icu",
    "Hosp_LOS", "ICU_LOS", "hospital_los", "icu_los",
    ## 工程/泄漏结局
    "death_within_icu_28days", "death_within_hosp_28days",
    "death_within_hosp_30days", "death_within_hosp_365days",
    "death_within_30days", "death_within_365days"
  ))
  drop_fixed <- drop_fixed[nzchar(drop_fixed)]

  cands <- setdiff(names(data), drop_fixed)
  ## 名称模式再剔：死亡标记、生存/住院天数、ID
  bad_pat <- paste0(
    "(?i)(death|dead|mortality|expire|fustatus|futime|survival_day|",
    "hosp_day|icu_day|los_|_los$|day_num|stay_id|subject_id|hadm|",
    "_tertile$|_quartile$|^Index_)"
  )
  cands <- cands[!grepl(bad_pat, cands, perl = TRUE)]

  ## 列线图池默认对齐 Jin：人口学+生命体征+实验室+通气；
  ## 共病/诊断大类默认不进（否则 backward 仍可留 20+ 个，图面过挤）
  dx_pat <- paste0(
    "(?i)^(Cancer|Hypertension|Hyperlipidemia|Diabetes|T1DM|T2DM|",
    "Heart_Failure|CHF|Myocardial_Infarction|MI|Stroke|COPD|Asthma|",
    "Pneumonia|Hepatitis|Liver_cirrhosis|Cirrhosis|CKD|AKI|Sepsis)$"
  )
  if (!isTRUE((cfg$logistic_nomogram %||% list())$include_comorbidities %||% FALSE)) {
    cands <- cands[!grepl(dx_pat, cands, perl = TRUE)]
  }

  keep <- character(0)
  for (vn in cands) {
    x <- data[[vn]]
    if (all(is.na(x))) next
    miss <- mean(is.na(x))
    if (isTRUE(miss > 0.4)) next
    if (is.numeric(x) || is.integer(x)) {
      ## 常数列跳过
      if (length(unique(stats::na.omit(x))) < 2L) next
      keep <- c(keep, vn)
      next
    }
    if (is.logical(x)) {
      keep <- c(keep, vn)
      next
    }
    if (is.factor(x) || is.character(x)) {
      xu <- unique(as.character(stats::na.omit(x)))
      nlev <- length(xu)
      if (nlev < 2L || nlev > 8L) next
      keep <- c(keep, vn)
    }
  }
  unique(keep)
}

.logistic_nomogram_term_p <- function(fit_or_glm, var) {
  s1 <- tryCatch(summary(fit_or_glm)$coefficients, error = function(e) NULL)
  if (is.null(s1)) return(NA_real_)
  rn <- rownames(s1)
  hits <- grep(paste0("^", gsub("([.\\(\\)])", "\\\\\\1", var)), rn)
  if (!length(hits)) return(NA_real_)
  pc <- intersect(c("Pr(>|z|)", "Pr(>|Z|)", "p"), colnames(s1))
  if (!length(pc)) return(NA_real_)
  max(as.numeric(s1[hits, pc[[1L]]]), na.rm = TRUE)
}

.logistic_nomogram_cap_features <- function(d, outcome, kept, force_keep, max_features) {
  max_features <- suppressWarnings(as.integer(max_features)[1L])
  if (!is.finite(max_features) || max_features < 2L) return(kept)
  force_in <- intersect(force_keep, kept)
  if (length(kept) <= max_features) return(kept)
  extras <- setdiff(kept, force_in)
  if (!length(extras)) return(kept)
  g1 <- tryCatch(
    stats::glm(
      stats::as.formula(paste(outcome, "~", paste(kept, collapse = " + "))),
      data = d, family = stats::binomial()
    ),
    error = function(e) NULL
  )
  if (is.null(g1)) return(kept[seq_len(min(length(kept), max_features))])
  pvals <- vapply(extras, function(v) .logistic_nomogram_term_p(g1, v), numeric(1))
  ## 保留 p 更小的额外变量，凑满 max_features
  n_extra <- max(0L, max_features - length(force_in))
  ord <- order(pvals, na.last = TRUE)
  take <- extras[ord][seq_len(min(n_extra, length(extras)))]
  unique(c(force_in, take))
}

.logistic_nomogram_backward <- function(
    fit, d, outcome, feats, force_keep, sel_alpha, max_features = NULL
) {
  force_in_model <- intersect(force_keep, feats)
  bw <- tryCatch(
    rms::fastbw(fit, rule = "p", type = "individual", sls = sel_alpha, force = force_in_model),
    error = function(e) NULL
  )
  kept <- NULL
  if (!is.null(bw)) {
    kept <- bw$names.kept %||% bw$kept %||% attr(bw, "names.kept")
    if (is.null(kept) && !is.null(bw$coefficients)) {
      kept <- setdiff(names(bw$coefficients), "(Intercept)")
    }
  }
  if (is.null(kept) || !length(kept)) {
    g0 <- tryCatch(
      stats::glm(
        stats::as.formula(paste(outcome, "~", paste(feats, collapse = " + "))),
        data = d, family = stats::binomial()
      ),
      error = function(e) NULL
    )
    if (!is.null(g0)) {
      kept <- feats
      repeat {
        dropable <- setdiff(kept, force_in_model)
        if (!length(dropable)) break
        g1 <- stats::glm(
          stats::as.formula(paste(outcome, "~", paste(kept, collapse = " + "))),
          data = d, family = stats::binomial()
        )
        s1 <- summary(g1)$coefficients
        rn <- rownames(s1)
        pvals <- vapply(dropable, function(v) {
          hits <- grep(paste0("^", gsub("([.\\(\\)])", "\\\\\\1", v)), rn)
          if (!length(hits)) return(0)
          max(as.numeric(s1[hits, 4L]), na.rm = TRUE)
        }, numeric(1))
        worst <- which.max(pvals)
        if (!length(worst) || !is.finite(pvals[[worst]]) || pvals[[worst]] < sel_alpha) break
        kept <- setdiff(kept, dropable[[worst]])
      }
    }
  }
  if (!length(kept)) return(feats)
  kept <- unique(c(force_in_model, intersect(as.character(kept), feats)))
  kept <- kept[kept %in% names(d)]
  .logistic_nomogram_cap_features(d, outcome, kept, force_keep, max_features)
}

.logistic_nomogram_fit_one <- function(
    data, outcome, feats, force_keep, sel_mode, sel_alpha, cfg,
    funlabel, pdf_path, width = 7.2, height = NULL, max_features = 12L
) {
  d <- data[, unique(c(outcome, feats)), drop = FALSE]
  d[[outcome]] <- .logistic_nomogram_y01(d[[outcome]], cfg)
  for (cc in feats) {
    if (is.character(d[[cc]])) d[[cc]] <- factor(d[[cc]])
  }
  d <- stats::na.omit(d)
  if (nrow(d) < 50L || length(unique(d[[outcome]])) < 2L) {
    return(list(ok = FALSE, reason = "complete-case too few / no event variation"))
  }

  feats_full <- feats
  fml <- stats::as.formula(paste(outcome, "~", paste(feats, collapse = " + ")))
  dd <- rms::datadist(d)
  options(datadist = "dd")
  assign("dd", dd, envir = .GlobalEnv)

  fit <- tryCatch(
    rms::lrm(fml, data = d, x = TRUE, y = TRUE),
    error = function(e) e
  )
  if (inherits(fit, "error")) {
    return(list(ok = FALSE, reason = conditionMessage(fit)))
  }

  max_feat <- suppressWarnings(as.integer(max_features %||% 12L)[1L])
  if (!is.finite(max_feat) || max_feat < 2L) max_feat <- 12L
  if (identical(sel_mode, "backward") && length(feats) > length(force_keep)) {
    kept <- .logistic_nomogram_backward(
      fit, d, outcome, feats, force_keep, sel_alpha, max_features = max_feat
    )
    if (length(kept) >= 2L && !identical(sort(kept), sort(feats))) {
      feats <- kept
      fml <- stats::as.formula(paste(outcome, "~", paste(feats, collapse = " + ")))
      dd <- rms::datadist(d[, c(outcome, feats), drop = FALSE])
      options(datadist = "dd")
      assign("dd", dd, envir = .GlobalEnv)
      fit2 <- tryCatch(rms::lrm(fml, data = d, x = TRUE, y = TRUE), error = function(e) NULL)
      if (!is.null(fit2)) fit <- fit2
    }
  }

  ## 宽图 + 稀疏概率/连续变量刻度，避免轴数字重叠
  w_use <- max(as.numeric(width %||% 9)[1L], 12)
  h <- height %||% max(6.5, 0.52 * length(feats) + 3.5)
  fun_at <- c(0.1, 0.2, 0.4, 0.6, 0.8, 0.9)
  ## 连续变量：P10–P90 上最多 4 个刻度；窄量程（如体温）只留 3 点
  axis_args <- list()
  for (vn in feats) {
    x <- suppressWarnings(as.numeric(d[[vn]]))
    if (!is.numeric(d[[vn]]) && !is.integer(d[[vn]])) next
    xu <- unique(stats::na.omit(x))
    if (length(xu) <= 6L) next
    qs <- stats::quantile(x, probs = c(0.10, 0.90), na.rm = TRUE, names = FALSE, type = 7)
    if (!all(is.finite(qs)) || qs[[1L]] >= qs[[2L]]) next
    span <- qs[[2L]] - qs[[1L]]
    ## 窄量程 / 暴露短轴：最多 3 点，避免 stub 上数字叠死
    n_tick <- if (is.finite(span) && span < 5) 3L else 4L
    if (grepl("^(WPR|wpr)$", vn) || span < 1) n_tick <- 3L
    ticks <- pretty(qs, n = max(2L, n_tick - 1L))
    ticks <- ticks[ticks >= qs[[1L]] & ticks <= qs[[2L]]]
    if (length(ticks) < 2L) {
      ticks <- c(qs[[1L]], qs[[2L]])
    } else if (length(ticks) < 3L && n_tick >= 3L) {
      ticks <- c(qs[[1L]], mean(qs), qs[[2L]])
    }
    if (length(ticks) > n_tick) {
      idx <- unique(round(seq(1L, length(ticks), length.out = n_tick)))
      ticks <- ticks[idx]
    }
    ## 圆整到合理位数，减少 36.5/37.5 挤成一团
    if (span >= 20) {
      ticks <- round(ticks)
    } else if (span >= 2) {
      ticks <- round(ticks, 1)
    } else {
      ticks <- round(ticks, 2)
    }
    ticks <- unique(as.numeric(ticks))
    if (length(ticks) < 2L) next
    axis_args[[vn]] <- ticks
  }
  grDevices::pdf(pdf_path, width = w_use, height = h, useDingbats = FALSE)
  nom <- tryCatch({
    args <- c(
      list(
        fit = fit,
        fun = stats::plogis,
        funlabel = funlabel,
        fun.at = fun_at
      ),
      axis_args
    )
    do.call(rms::nomogram, args)
  }, error = function(e) {
    tryCatch(
      rms::nomogram(fit, fun = stats::plogis, funlabel = funlabel, fun.at = fun_at),
      error = function(e2) NULL
    )
  })
  if (!is.null(nom)) {
    graphics::plot(
      nom,
      xfrac = 0.32,
      cex.axis = 0.48,
      cex.var = 0.82,
      lmgp = 0.28,
      tcl = 0.25,
      col.grid = c("#7EADCF", "#D0E4F4")
    )
  } else {
    graphics::plot.new()
    graphics::title("Nomogram failed")
  }
  grDevices::dev.off()

  list(
    ok = TRUE,
    features = feats,
    features_full = feats_full,
    force_features = force_keep,
    n = nrow(d),
    fit = fit,
    pdf = pdf_path,
    events = sum(d[[outcome]] == 1L, na.rm = TRUE)
  )
}

.logistic_nomogram_compose_abc <- function(paths, labels, out_path) {
  paths <- as.character(paths)
  labels <- as.character(labels)
  ## 竖排 A/B/C：每张全宽，避免横挤导致 Probability 刻度重叠
  ok <- FALSE
  if (exists(".dual_db_compose_n_pdf", mode = "function")) {
    ok <- tryCatch({
      .dual_db_compose_n_pdf(
        paths, labels, out_path,
        layout = "stack", dpi = 200L, label_cex = 1.05
      )
      file.exists(out_path) && isTRUE((file.info(out_path)$size %||% 0) > 1000)
    }, error = function(e) FALSE)
  }
  if (!isTRUE(ok)) {
    py <- NULL
    for (r in unique(c(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""), getwd()))) {
      cand <- file.path(r, "R", "dual_db_compose_n_panel.py")
      if (nzchar(r) && file.exists(cand)) { py <- cand; break }
    }
    if (!is.null(py) && nzchar(Sys.which("python3"))) {
      ok <- tryCatch({
        system2(
          "python3",
          c(py, "--out", out_path, "--layout", "stack",
            "--labels", paste(labels, collapse = "||"), paths),
          stdout = TRUE, stderr = TRUE
        )
        file.exists(out_path) && isTRUE((file.info(out_path)$size %||% 0) > 1000)
      }, error = function(e) FALSE)
    }
  }
  if (isTRUE(ok)) return(invisible(out_path))
  if (requireNamespace("pdftools", quietly = TRUE)) {
    tryCatch({
      pdftools::pdf_combine(paths, output = out_path)
      if (file.exists(out_path)) return(invisible(out_path))
    }, error = function(e) NULL)
  }
  if (file.exists(paths[[1L]])) {
    file.copy(paths[[1L]], out_path, overwrite = TRUE)
  }
  invisible(out_path)
}

block_logistic_nomogram <- function(ctx, ...) {
  .cands <- unique(c(
    Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""),
    as.character(ctx$config$project$root %||% "")[1L],
    getwd()
  ))
  .lit <- NULL
  for (.r in .cands[nzchar(as.character(.cands))]) {
    .p <- file.path(.r, "R", "literature_jin_index_sofa.R")
    if (file.exists(.p)) { .lit <- .p; break }
  }
  if (!is.null(.lit)) source(.lit, local = FALSE)
  ## 拼图助手
  for (.r in .cands[nzchar(as.character(.cands))]) {
    .p <- file.path(.r, "R", "dual_db_combine_figures.R")
    if (file.exists(.p)) {
      tryCatch(source(.p, local = FALSE), error = function(e) NULL)
      break
    }
  }
  if (!requireNamespace("rms", quietly = TRUE)) {
    stop("logistic_nomogram: 需要 rms 包", call. = FALSE)
  }

  ng <- .logistic_nomogram_cfg(ctx$config)
  if (!is.null(ng$enable) && !isTRUE(ng$enable)) {
    cli::cli_alert_info("logistic_nomogram: enable=FALSE，跳过")
    return(ctx)
  }

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data) || !nrow(data)) {
    stop("logistic_nomogram: 无数据", call. = FALSE)
  }

  ## 补齐 30d/365d 事件列（与 cox_multi_horizon 同源）
  .db_hz <- tolower(as.character(
    ctx$config$dual_db$current_db %||% ctx$config$project$database %||% "mimic"
  )[1L])
  if (grepl("eicu", .db_hz)) .db_hz <- "eicu" else .db_hz <- "mimic"
  if (exists("jin_ensure_horizon_columns", mode = "function")) {
    data <- jin_ensure_horizon_columns(data, db = .db_hz)
    if (!is.null(ctx$data$imputed) && is.data.frame(ctx$data$imputed)) {
      ctx$data$imputed <- jin_ensure_horizon_columns(ctx$data$imputed, db = .db_hz)
    }
  }

  strata <- ctx$results$derived_grouping %||%
    ctx$results$jin_index_sofa_strata %||% list()

  expo <- ng$exposure_var %||% strata$index_var %||%
    ctx$config$survival$index_var %||% ctx$config$project$index_var
  expo <- as.character(expo %||% "")[1L]
  if (!nzchar(expo) || !expo %in% names(data)) {
    if ("Index_HL" %in% names(data)) {
      expo <- "Index_HL"
    } else {
      stop("logistic_nomogram: 无暴露列", call. = FALSE)
    }
  }

  sofa_var <- as.character(ng$sofa_var %||% strata$sofa_var %||% "SOFA")[1L]
  if (!sofa_var %in% names(data)) {
    stop("logistic_nomogram: 无 SOFA 列", call. = FALSE)
  }

  extra_force <- as.character(ng$force_features %||% character(0))
  force_keep <- unique(c(expo, sofa_var, extra_force))
  force_keep <- force_keep[force_keep %in% names(data)]
  if (!all(c(expo, sofa_var) %in% force_keep)) {
    stop("logistic_nomogram: 强制特征暴露/SOFA 缺失", call. = FALSE)
  }

  horiz_ids <- as.character(ng$horizons %||% c("hosp", "d30", "d365"))
  horiz_ids <- horiz_ids[nzchar(horiz_ids)]
  if (!length(horiz_ids)) horiz_ids <- "hosp"

  default_hz <- list(
    hosp = list(
      event = "fustatus",
      label = "Probability of In-hospital Mortality",
      panel = "A",
      funlabel = "Probability of In-hospital Mortality"
    ),
    d30 = list(
      event = "event_d30",
      label = "Probability of 30-day Mortality",
      panel = "B",
      funlabel = "Probability of 30-day Mortality"
    ),
    d365 = list(
      event = "event_d365",
      label = "Probability of 365-day Mortality",
      panel = "C",
      funlabel = "Probability of 365-day Mortality"
    )
  )

  outcome_vars <- character(0)
  hz_specs <- list()
  for (hid in horiz_ids) {
    ov <- ng[[hid]] %||% list()
    base <- default_hz[[hid]] %||% list(
      event = "fustatus", label = hid, panel = toupper(substr(hid, 1, 1)),
      funlabel = hid
    )
    ev <- .logistic_nomogram_resolve_event(
      data, ov$event %||% base$event
    )
    if (is.na(ev) || !nzchar(ev)) {
      cli::cli_alert_warning("logistic_nomogram: 时点 {hid} 无事件列，跳过")
      next
    }
    outcome_vars <- c(outcome_vars, ev)
    hz_specs[[hid]] <- list(
      id = hid,
      event = ev,
      label = as.character(ov$label %||% base$label)[1L],
      panel = as.character(ov$panel %||% base$panel)[1L],
      funlabel = as.character(ov$funlabel %||% ov$label %||% base$funlabel)[1L]
    )
  }
  if (!length(hz_specs)) stop("logistic_nomogram: 无可用时点", call. = FALSE)

  cand_mode <- tolower(as.character(ng$candidate_mode %||% "shared_clinical")[1L])
  if (identical(cand_mode, "explicit") || identical(cand_mode, "manual")) {
    cands <- as.character(ng$candidate_features %||% character(0))
    cands <- cands[cands %in% names(data)]
  } else {
    cands <- .logistic_nomogram_shared_clinical_pool(
      data, ctx$config, expo, sofa_var, unique(outcome_vars)
    )
  }
  ## 别名补齐
  if ("NBPM" %in% names(data) && !"NBPM" %in% cands &&
      any(c("MBP", "MAP") %in% cands)) {
    cands <- unique(c(cands, "NBPM"))
  }
  if ("TotalCo2" %in% names(data)) {
    cands <- setdiff(cands, c("Bicarbonate", "bicarbonate"))
    if (!"TotalCo2" %in% cands) cands <- c(cands, "TotalCo2")
  }

  pool <- unique(c(force_keep, cands))
  pool <- pool[pool %in% names(data)]
  pool <- setdiff(pool, unique(outcome_vars))
  if (length(pool) < 2L) stop("logistic_nomogram: 特征过少", call. = FALSE)

  cli::cli_alert_info(
    "logistic_nomogram: candidate_mode={cand_mode}; pool n={length(pool)} (force={paste(force_keep, collapse=', ')})"
  )

  sel_mode <- tolower(as.character(ng$selection %||% "backward")[1L])
  sel_alpha <- suppressWarnings(as.numeric(ng$selection_alpha %||% 0.05)[1L])
  if (!is.finite(sel_alpha) || sel_alpha <= 0 || sel_alpha >= 1) sel_alpha <- 0.05
  max_feat <- suppressWarnings(as.integer(ng$max_features %||% 12L)[1L])
  if (!is.finite(max_feat) || max_feat < 2L) max_feat <- 12L
  cli::cli_alert_info(
    "logistic_nomogram: selection={sel_mode} α={sel_alpha}; max_features={max_feat}"
  )

  out_root <- as.character(
    ctx$output_dir %||% ctx$config$project$output_dir %||% getwd()
  )[1L]
  step_dir <- file.path(out_root, "step_logistic_nomogram")
  fig_dir <- file.path(out_root, "Figures")
  dir.create(step_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

  panel_pdfs <- character(0)
  panel_labels <- character(0)
  by_hz <- list()
  primary_fit <- NULL
  primary_feats <- NULL

  for (hid in names(hz_specs)) {
    sp <- hz_specs[[hid]]
    panel_path <- file.path(
      step_dir,
      sprintf("nomogram_panel_%s_%s.pdf", sp$panel, hid)
    )
    res <- .logistic_nomogram_fit_one(
      data = data,
      outcome = sp$event,
      feats = pool,
      force_keep = force_keep,
      sel_mode = sel_mode,
      sel_alpha = sel_alpha,
      cfg = ctx$config,
      funlabel = sp$funlabel,
      pdf_path = panel_path,
      max_features = max_feat
    )
    if (!isTRUE(res$ok)) {
      cli::cli_alert_warning(
        "logistic_nomogram: {hid} 失败 — {res$reason %||% 'unknown'}"
      )
      next
    }
    cli::cli_alert_info(
      "logistic_nomogram: {sp$panel}/{hid} backward α={sel_alpha} → {length(res$features_full)}→{length(res$features)} (n={res$n}, events={res$events}); keep={paste(res$features, collapse=', ')}"
    )
    utils::write.csv(
      data.frame(
        feature = res$features,
        forced = res$features %in% force_keep,
        horizon = hid,
        panel = sp$panel,
        stringsAsFactors = FALSE
      ),
      file.path(step_dir, sprintf("Table_nomogram_selected_features_%s.csv", hid)),
      row.names = FALSE
    )
    panel_pdfs <- c(panel_pdfs, res$pdf)
    panel_labels <- c(panel_labels, sprintf("%s. %s", sp$panel, sp$label))
    by_hz[[hid]] <- res
    if (identical(hid, "hosp") || is.null(primary_fit)) {
      primary_fit <- res$fit
      primary_feats <- res$features
    }
  }

  if (!length(panel_pdfs)) {
    stop("logistic_nomogram: 全部时点失败", call. = FALSE)
  }

  ## 兼容旧单图文件名 + Jin 三时点总图
  combined_bn <- "Figure. Nomogram for in-hospital, 30-day and 365-day mortality.pdf"
  if (length(panel_pdfs) == 1L) {
    combined_bn <- "Figure. Nomogram in-hospital mortality (logistic).pdf"
  }
  combined_path <- file.path(fig_dir, combined_bn)
  if (isTRUE(ng$combine_panels %||% TRUE) && length(panel_pdfs) >= 2L) {
    .logistic_nomogram_compose_abc(panel_pdfs, panel_labels, combined_path)
  } else {
    file.copy(panel_pdfs[[1L]], combined_path, overwrite = TRUE)
  }
  ## 多时点时禁止再写「仅院内」旧名，否则 curate 抢同一 fig2 角色把三时点图盖掉
  legacy <- file.path(fig_dir, "Figure. Nomogram in-hospital mortality (logistic).pdf")
  if (file.exists(legacy) && length(panel_pdfs) >= 2L) {
    unlink(legacy)
  }
  ## 限幅：多时点列线图保持多页，禁止 stack_pages 压成单页（双库交错依赖分页）
  if (exists("pub_figure_normalize_pdf", mode = "function") && file.exists(combined_path)) {
    tryCatch(
      pub_figure_normalize_pdf(
        combined_path,
        max_edge_in = as.numeric(
          (ctx$config$pub_figures %||% list())$max_edge_in %||% 11
        )[1L],
        stack_pages = length(panel_pdfs) < 2L
      ),
      error = function(e) NULL
    )
  }

  ## 主时点校准（S3）
  B <- as.integer(ng$bootstrap_B %||% 200L)[1L]
  seed <- as.integer(ng$seed %||% 42L)[1L]
  cal_path <- file.path(fig_dir, "Figure. Calibration bootstrap in-hospital mortality.pdf")
  if (!is.null(primary_fit)) {
    set.seed(seed)
    cal <- tryCatch(
      rms::calibrate(primary_fit, method = "boot", B = B),
      error = function(e) NULL
    )
    grDevices::pdf(cal_path, width = 6.5, height = 6.5)
    if (!is.null(cal)) {
      plot(cal, legend = FALSE, subtitles = FALSE,
           xlab = "Predicted probability", ylab = "Observed probability",
           main = sprintf("Bootstrap calibration (B=%d)", B))
    } else {
      graphics::plot.new()
      graphics::title("Calibration failed")
    }
    grDevices::dev.off()
  }

  ## 汇总所选特征
  sel_rows <- lapply(names(by_hz), function(hid) {
    data.frame(
      horizon = hid,
      panel = hz_specs[[hid]]$panel,
      feature = by_hz[[hid]]$features,
      forced = by_hz[[hid]]$features %in% force_keep,
      stringsAsFactors = FALSE
    )
  })
  utils::write.csv(
    do.call(rbind, sel_rows),
    file.path(step_dir, "Table_nomogram_selected_features.csv"),
    row.names = FALSE
  )

  primary_outcome <- tryCatch({
    as.character(hz_specs[["hosp"]]$event %||% hz_specs[[1L]]$event)[1L]
  }, error = function(e) NA_character_)
  if (!nzchar(primary_outcome %||% "")) primary_outcome <- "fustatus"

  res <- list(
    features = primary_feats,
    features_by_horizon = lapply(by_hz, function(x) x$features),
    features_full_pool = pool,
    force_features = force_keep,
    candidate_mode = cand_mode,
    selection = sel_mode,
    selection_alpha = sel_alpha,
    exposure = expo,
    sofa_var = sofa_var,
    outcome = primary_outcome,
    horizons = names(by_hz),
    n_by_horizon = lapply(by_hz, function(x) x$n),
    fit = primary_fit,
    nomogram_pdf = combined_path,
    panel_pdfs = panel_pdfs,
    calibration_pdf = cal_path,
    bootstrap_B = B,
    seed = seed,
    note = paste0(
      "Jin-style multi-horizon logistic nomogram: force exposure+SOFA; ",
      "shared_clinical candidate pool; per-horizon backward α=", sel_alpha, "."
    )
  )
  ctx$results$logistic_nomogram <- res
  ctx$results$jin_nomogram_cal <- res
  cli::cli_alert_success(
    "logistic_nomogram: panels={length(panel_pdfs)} → {basename(combined_path)}"
  )
  ctx
}

register_block(
  "logistic_nomogram",
  block_logistic_nomogram,
  "多时点logistic列线图（院内/30d/365d）与bootstrap校准"
)
