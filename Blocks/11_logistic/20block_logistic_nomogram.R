###############################################################################
#  logistic_nomogram — 院内死亡 logistic + rms 列线图 + bootstrap 校准
#
#  register_block: "logistic_nomogram"
#  典型流水线: derived_grouping / cox_multi_horizon 之后
#  依赖: rms
#
#  config$logistic_nomogram = list(
#    enable = TRUE,
#    outcome = "fustatus",            # 院内死亡 0/1
#    exposure_var = NULL,            # NULL → 连续 index 或 Index_HL
#    sofa_var = NULL,                # NULL → SOFA（连续优先）
#    candidate_features = c("Age", "MBP", "WBC", "TotalCo2", "Hemoglobin",
#                           "Sodium", "Calcium"),  # 缺列自动跳过；供逐步筛选
#    force_features = NULL,          # 额外强制保留（默认仍强制暴露+SOFA）
#    selection = "backward",         # none | backward（对齐 Jin：α=0.05 后退）
#    selection_alpha = 0.05,
#    bootstrap_B = 200L,
#    seed = 42L
#  )
#  兼容: 缺 config$logistic_nomogram 时回读 config$jin_index_sofa$nomogram
#
#  中介代理名 TotalCo2（本块不做中介；中介走 mediation_prognosis）
#  写: Figures PDF + ctx$results$logistic_nomogram；CSV 到 step 目录
###############################################################################

.logistic_nomogram_cfg <- function(cfg) {
  top <- cfg$logistic_nomogram %||% list()
  if (length(top)) return(top)
  (cfg$jin_index_sofa %||% list())$nomogram %||% list()
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

  strata <- ctx$results$derived_grouping %||%
    ctx$results$jin_index_sofa_strata %||% list()
  outcome <- as.character(ng$outcome %||% "fustatus")[1L]
  if (!outcome %in% names(data)) {
    alt <- intersect(c("is_hosp_dead", "hospital_expire_flag", "fustatus"), names(data))
    if (!length(alt)) stop("logistic_nomogram: 无结局列", call. = FALSE)
    outcome <- alt[[1L]]
  }

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

  cands <- as.character(ng$candidate_features %||%
    c("Age", "MBP", "MAP", "WBC", "TotalCo2", "Hemoglobin", "Sodium", "Calcium",
      "Total_Calcium", "CalciumTotal", "Bicarbonate", "Gender", "HeartRate",
      "RespiratoryRate", "Potassium", "Creatinine", "Platelet_Count", "PLT"))
  extra_force <- as.character(ng$force_features %||% character(0))
  if ("MBP" %in% names(data) && "MAP" %in% cands && !"MBP" %in% cands) {
    cands <- c(cands, "MBP")
  }
  if ("NBPM" %in% names(data) && ("MBP" %in% cands || "MAP" %in% cands) &&
      !"NBPM" %in% cands) {
    cands <- c(cands, "NBPM")
  }
  if ("TotalCo2" %in% names(data)) {
    cands <- setdiff(cands, c("Bicarbonate", "bicarbonate"))
  }
  ## 强制：暴露 + SOFA（+ config 额外 force）；其余候选供后退筛选
  force_keep <- unique(c(expo, sofa_var, extra_force))
  force_keep <- force_keep[force_keep %in% names(data)]
  feats <- unique(c(force_keep, cands))
  feats <- feats[feats %in% names(data)]
  feats <- setdiff(feats, c(
    outcome, "futime", "Index_SOFA_Q", "SOFA_bin",
    as.character((ctx$config$data %||% list())$id_column %||% "ID")
  ))
  if (!all(c(expo, sofa_var) %in% feats)) {
    stop("logistic_nomogram: 强制特征暴露/SOFA 缺失", call. = FALSE)
  }
  if (length(feats) < 2L) stop("logistic_nomogram: 特征过少", call. = FALSE)

  d <- data[, unique(c(outcome, feats)), drop = FALSE]
  y <- d[[outcome]]
  ## 展示标签 Non-survivor / Expired 等；勿仅 as.numeric==1
  death_labs <- c(
    "1", "yes", "y", "true", "dead", "death", "died", "expire", "expired",
    "deceased", "non-survivor", "nonsurvivor", "non survivor", "死亡", "是"
  )
  yc <- tolower(trimws(as.character(y)))
  if (exists("pipeline_outcome_as_01", mode = "function")) {
    y01 <- tryCatch(
      pipeline_outcome_as_01(y, cfg = ctx$config),
      error = function(e) NULL
    )
  } else {
    y01 <- NULL
  }
  if (!is.null(y01) && length(y01) == length(y)) {
    d[[outcome]] <- as.integer(y01)
  } else if (is.factor(y) || is.character(y)) {
    d[[outcome]] <- as.integer(yc %in% death_labs)
  } else {
    d[[outcome]] <- as.integer(suppressWarnings(as.numeric(y)) == 1L)
  }
  for (cc in feats) {
    if (is.character(d[[cc]])) d[[cc]] <- factor(d[[cc]])
  }
  d <- stats::na.omit(d)
  if (nrow(d) < 50L || length(unique(d[[outcome]])) < 2L) {
    stop("logistic_nomogram: 完整病例过少或无事件变异", call. = FALSE)
  }

  fml <- stats::as.formula(paste(outcome, "~", paste(feats, collapse = " + ")))
  dd <- rms::datadist(d)
  options(datadist = "dd")
  assign("dd", dd, envir = .GlobalEnv)

  fit <- tryCatch(
    rms::lrm(fml, data = d, x = TRUE, y = TRUE),
    error = function(e) e
  )
  if (inherits(fit, "error")) {
    stop("logistic_nomogram: lrm 失败: ", conditionMessage(fit), call. = FALSE)
  }

  sel_mode <- tolower(as.character(ng$selection %||% "backward")[1L])
  sel_alpha <- suppressWarnings(as.numeric(ng$selection_alpha %||% 0.05)[1L])
  if (!is.finite(sel_alpha) || sel_alpha <= 0 || sel_alpha >= 1) sel_alpha <- 0.05
  feats_full <- feats
  if (identical(sel_mode, "backward") && length(feats) > length(force_keep)) {
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
      ## fallback：glm + 逐步删 p>=alpha（强制项不删）
      g0 <- tryCatch(
        stats::glm(fml, data = d, family = stats::binomial()),
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
    if (length(kept)) {
      kept <- unique(c(force_in_model, intersect(as.character(kept), feats)))
      kept <- kept[kept %in% names(d)]
      if (length(kept) >= 2L && !identical(sort(kept), sort(feats))) {
        feats <- kept
        fml <- stats::as.formula(paste(outcome, "~", paste(feats, collapse = " + ")))
        dd <- rms::datadist(d[, c(outcome, feats), drop = FALSE])
        options(datadist = "dd")
        assign("dd", dd, envir = .GlobalEnv)
        fit2 <- tryCatch(
          rms::lrm(fml, data = d, x = TRUE, y = TRUE),
          error = function(e) NULL
        )
        if (!is.null(fit2)) {
          fit <- fit2
          cli::cli_alert_info(
            "logistic_nomogram: backward α={sel_alpha} → {length(feats_full)}→{length(feats)} 特征（强制保留 {paste(force_in_model, collapse=', ')}）"
          )
        }
      }
    }
  }

  out_root <- as.character(
    ctx$output_dir %||% ctx$config$project$output_dir %||% getwd()
  )[1L]
  step_dir <- file.path(out_root, "step_logistic_nomogram")
  fig_dir <- file.path(out_root, "Figures")
  dir.create(step_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

  utils::write.csv(
    data.frame(
      feature = feats,
      forced = feats %in% force_keep,
      stringsAsFactors = FALSE
    ),
    file.path(step_dir, "Table_nomogram_selected_features.csv"),
    row.names = FALSE
  )

  nom_path <- file.path(fig_dir, "Figure. Nomogram in-hospital mortality (logistic).pdf")
  grDevices::pdf(nom_path, width = 11, height = max(5, 0.55 * length(feats) + 3))
  nom <- tryCatch(
    rms::nomogram(fit, fun = stats::plogis, funlabel = "Predicted in-hospital mortality"),
    error = function(e) NULL
  )
  if (!is.null(nom)) {
    graphics::plot(
      nom, xfrac = 0.28, cex.axis = 0.85, cex.var = 1.0,
      col.grid = c("#7EADCF", "#D0E4F4")
    )
  } else {
    graphics::plot.new()
    graphics::title("Nomogram failed")
  }
  grDevices::dev.off()

  B <- as.integer(ng$bootstrap_B %||% 200L)[1L]
  seed <- as.integer(ng$seed %||% 42L)[1L]
  set.seed(seed)
  cal <- tryCatch(
    rms::calibrate(fit, method = "boot", B = B),
    error = function(e) NULL
  )
  cal_path <- file.path(fig_dir, "Figure. Calibration bootstrap in-hospital mortality.pdf")
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

  ## rms::summary.rms 返回带 class 的 matrix，不能 sm$coef
  sm <- tryCatch(summary(fit), error = function(e) NULL)
  coef_path <- file.path(step_dir, "Table_nomogram_lrm_coef.csv")
  if (is.matrix(sm) || inherits(sm, "summary.rms")) {
    utils::write.csv(as.data.frame(sm), coef_path)
  } else if (is.list(sm) && !is.null(sm[["coef"]])) {
    utils::write.csv(as.data.frame(sm[["coef"]]), coef_path)
  } else {
    utils::write.csv(
      data.frame(term = names(stats::coef(fit)), coef = as.numeric(stats::coef(fit))),
      coef_path, row.names = FALSE
    )
  }

  res <- list(
    features = feats,
    features_full = feats_full,
    force_features = force_keep,
    selection = sel_mode,
    selection_alpha = sel_alpha,
    exposure = expo,
    sofa_var = sofa_var,
    outcome = outcome,
    n = nrow(d),
    fit = fit,
    nomogram_pdf = nom_path,
    calibration_pdf = cal_path,
    bootstrap_B = B,
    seed = seed,
    note = "Logistic nomogram: force exposure+SOFA; optional backward p-selection on candidates. Mediation separate."
  )
  ctx$results$logistic_nomogram <- res
  ctx$results$jin_nomogram_cal <- res
  cli::cli_alert_success(
    "logistic_nomogram: n={nrow(d)}, features={length(feats)} (selection={sel_mode}) → nomogram + calibration"
  )
  ctx
}

register_block(
  "logistic_nomogram",
  block_logistic_nomogram,
  "院内死亡logistic列线图与bootstrap校准"
)
