###############################################################################
#  trajectory_pamm — 连续复合指标时变非线性关联（PAMM；对齐 fcimb Fig5/6）
#
#  依据：piece-wise exponential additive mixed models（R 包 pammtools + mgcv）
#  公开作者脚本：未找到；实现走 pammtools 官方接口。
#
#  输出：
#    - 连续暴露 × 时间交互的平滑曲面/切片图（Fig5a–d 角色）
#    - 阈值异常（发现集锁定 lo/hi 分位）+ 暴露时间占比 + 累积负担 → Cox HR 表
#
#  config$trajectory_pamm = list(
#    index_vars = NULL,                 # NULL → 当前 Index / dual_safe 批跑 patch
#    discovery_db = "mimic",
#    threshold_probs = c(0.05, 0.95),    # 发现集锁定；过稀可降级 c(0.10,0.90)
#    threshold_fallback_probs = c(0.10, 0.90),
#    min_abnormal_person_days = 50L,
#    max_followup = 28L,
#    cut_points = seq(0, 28, by = 1),
#    survival_time_var = NULL,
#    survival_event_var = NULL,
#    covariate_vars = NULL,             # NULL → JLCM survival 协变量 / Model2
#    lock_thresholds_from_discovery = TRUE,
#    validation_apply_locked = TRUE,
#    export_figures = TRUE
#  )
#
#  register_block: "trajectory_pamm"
###############################################################################

.tpamm_is_discovery <- function(ctx, bl) {
  db <- tolower(as.character(ctx$config$project$database %||% ""))
  disc <- tolower(as.character(bl$discovery_db %||% "mimic"))
  grepl(disc, db, fixed = TRUE)
}

.tpamm_resolve_index <- function(ctx, bl) {
  ix <- bl$index_vars %||% ctx$config$trajectory_jlcm$index_vars %||%
    ctx$config$survival$index_var %||% character(0)
  as.character(ix)[1L]
}

.tpamm_covars <- function(ctx, bl, data) {
  covs <- bl$covariate_vars
  if (is.null(covs) || !length(covs)) {
    covs <- ctx$config$trajectory_jlcm$covariate_vars %||%
      ctx$results$Model2Factors %||%
      intersect(c("Age", "Gender"), names(data))
  }
  intersect(as.character(covs), names(data))
}

.tpamm_long_from_wide <- function(index_df, id_col, index_name, time_start = 1L, time_end = 28L) {
  day_cols <- paste0(index_name, "_", seq.int(time_start, time_end))
  day_cols <- day_cols[day_cols %in% names(index_df)]
  if (!length(day_cols)) stop("trajectory_pamm: 宽表缺少 ", index_name, "_day 列", call. = FALSE)
  rows <- lapply(day_cols, function(dc) {
    day <- as.integer(sub(paste0("^", index_name, "_"), "", dc))
    data.frame(
      id = as.character(index_df[[id_col]]),
      time_day = day,
      expo = suppressWarnings(as.numeric(index_df[[dc]])),
      stringsAsFactors = FALSE
    )
  })
  long <- do.call(rbind, rows)
  long <- long[is.finite(long$expo), , drop = FALSE]
  names(long)[1L] <- id_col
  long
}

.tpamm_lock_thresholds <- function(expo, probs = c(0.05, 0.95)) {
  q <- as.numeric(stats::quantile(expo, probs = probs, na.rm = TRUE, names = FALSE, type = 7))
  list(lo = q[1L], hi = q[2L], probs = probs)
}

.tpamm_event_01 <- function(x, cfg = NULL) {
  # 插补后结局常被 relabel 为 Survivor / Non-survivor；禁止 status == 1L
  if (exists("pipeline_outcome_as_01", mode = "function")) {
    return(as.integer(pipeline_outcome_as_01(x, cfg)))
  }
  if (is.numeric(x) || is.integer(x) || is.logical(x)) return(as.integer(as.numeric(x) == 1))
  xs <- trimws(as.character(x))
  as.integer(xs %in% c("1", "Non-survivor", "Dead", "dead", "Yes") |
               grepl("non.?surv|dead|expir|death", xs, ignore.case = TRUE))
}

.tpamm_burden_table <- function(long, base, id_col, thr, time_var, event_var, covs, max_followup,
                                cfg = NULL) {
  # person-level: prop time below lo / above hi; cumulative absolute deviation beyond thresholds
  agg <- stats::aggregate(
    expo ~ get(id_col), data = long,
    FUN = function(z) {
      n <- length(z)
      c(
        prop_lo = mean(z <= thr$lo),
        prop_hi = mean(z >= thr$hi),
        cum_lo = sum(pmax(0, thr$lo - z)),
        cum_hi = sum(pmax(0, z - thr$hi)),
        n_obs = n
      )
    }
  )
  # aggregate with cbind returns matrix columns oddly; rebuild
  idv <- as.character(agg[[1L]])
  mat <- as.matrix(agg[[2L]])
  bur <- data.frame(
    id = idv,
    prop_lo = as.numeric(mat[, "prop_lo"]),
    prop_hi = as.numeric(mat[, "prop_hi"]),
    cum_lo = as.numeric(mat[, "cum_lo"]),
    cum_hi = as.numeric(mat[, "cum_hi"]),
    n_obs = as.numeric(mat[, "n_obs"]),
    stringsAsFactors = FALSE
  )
  names(bur)[1L] <- id_col
  dd <- merge(base, bur, by = id_col, all.x = FALSE)
  dd$time <- pmin(as.numeric(dd[[time_var]]), max_followup)
  dd$event <- .tpamm_event_01(dd[[event_var]], cfg)
  dd <- dd[is.finite(dd$time) & dd$time > 0, , drop = FALSE]

  fit_one <- function(term, scale = 1) {
    dd$x <- as.numeric(dd[[term]]) * scale
    fml <- if (length(covs)) {
      stats::as.formula(paste("survival::Surv(time, event) ~ x +", paste(covs, collapse = " + ")))
    } else {
      survival::Surv(time, event) ~ x
    }
    m <- tryCatch(survival::coxph(fml, data = dd), error = function(e) NULL)
    if (is.null(m)) {
      return(data.frame(metric = term, HR = NA_real_, lo = NA_real_, hi = NA_real_,
                        p = NA_real_, n = nrow(dd), note = "fit_failed",
                        stringsAsFactors = FALSE))
    }
    sm <- summary(m)$coefficients
    ci <- tryCatch(exp(stats::confint(m)["x", ]), error = function(e) c(NA_real_, NA_real_))
    data.frame(
      metric = term,
      HR = unname(exp(sm["x", "coef"])),
      lo = unname(ci[1L]),
      hi = unname(ci[2L]),
      p = unname(sm["x", "Pr(>|z|)"]),
      n = nrow(dd),
      note = "",
      stringsAsFactors = FALSE
    )
  }

  rbind(
    fit_one("prop_lo", scale = 20),  # per 5% → scale 20 on proportion-in-[0,1]
    fit_one("prop_hi", scale = 20),
    fit_one("cum_lo", scale = 1),
    fit_one("cum_hi", scale = 1)
  )
}

.tpamm_fit_smooth <- function(ped, covs) {
  # s(tend) + s(expo) + ti(tend, expo) ; optional linear covariates
  rhs_cov <- if (length(covs)) paste("+", paste(covs, collapse = " + ")) else ""
  fml <- stats::as.formula(paste0(
    "ped_status ~ s(tend) + s(expo, k = 10) + ti(tend, expo, k = c(5, 5))",
    rhs_cov
  ))
  mgcv::gam(fml, data = ped, family = stats::poisson(), offset = log(ped$offset), method = "REML")
}

block_trajectory_pamm <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  bl <- ctx$config$trajectory_pamm %||% list()
  if (!requireNamespace("pammtools", quietly = TRUE))
    stop("trajectory_pamm: 请安装 pammtools", call. = FALSE)
  if (!requireNamespace("mgcv", quietly = TRUE))
    stop("trajectory_pamm: 请安装 mgcv", call. = FALSE)
  if (!requireNamespace("survival", quietly = TRUE))
    stop("trajectory_pamm: 请安装 survival", call. = FALSE)

  if (is.null(ctx$results$trajectory_pamm) || !is.list(ctx$results$trajectory_pamm))
    ctx$results$trajectory_pamm <- list()

  Index <- .tpamm_resolve_index(ctx, bl)
  if (!nzchar(Index)) stop("trajectory_pamm: 未解析到 Index", call. = FALSE)

  id_col <- ctx$config$data$id_column %||% "subject_id"
  time_var <- bl$survival_time_var %||% ctx$config$survival$time_var %||% "survival_time_28d"
  event_var <- bl$survival_event_var %||% ctx$config$survival$event_var %||% "survival_28d"
  max_fu <- as.integer(bl$max_followup %||% 28L)
  cuts <- as.numeric(bl$cut_points %||% seq(0, max_fu, by = 1))

  base <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(base) || !nrow(base)) stop("trajectory_pamm: 无基线/插补数据", call. = FALSE)
  if (!all(c(time_var, event_var) %in% names(base)))
    stop("trajectory_pamm: 缺少生存列 ", time_var, " / ", event_var, call. = FALSE)

  # wide index from JLCM rawdata or results
  wide_path <- NULL
  tpl <- ctx$config$trajectory_jlcm$rawdata_path_template %||% NULL
  if (!is.null(tpl)) {
    db_tag <- if (grepl("mimic", tolower(ctx$config$project$database %||% ""), fixed = TRUE)) "mimic" else "eicu"
    wide_path <- gsub("\\{Index\\}", Index, gsub("\\{db\\}", db_tag, tpl))
  }
  index_df <- NULL
  if (!is.null(wide_path) && file.exists(wide_path)) {
    e <- new.env(parent = emptyenv())
    load(wide_path, envir = e)
    obj <- ctx$config$trajectory_jlcm$rawdata_obj %||% "index_df"
    index_df <- e[[obj]]
  }
  if (is.null(index_df)) {
    stop("trajectory_pamm: 找不到纵向宽表 ", wide_path %||% "(no path)", call. = FALSE)
  }
  if (!id_col %in% names(index_df) && "subject_id" %in% names(index_df)) id_col <- "subject_id"
  if (!id_col %in% names(index_df) && "ID" %in% names(index_df)) {
    index_df[[id_col]] <- as.character(index_df$ID)
  }

  long <- .tpamm_long_from_wide(index_df, id_col, Index, 1L, max_fu)
  covs <- .tpamm_covars(ctx, bl, base)

  # thresholds: discovery locks; validation applies locked file
  out_tab <- file.path(ctx$output_dir_tables %||% file.path(ctx$config$project$output_dir, "Tables"), "PAMM")
  dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)
  thr_path <- file.path(out_tab, paste0("PAMM_thresholds_", Index, ".rds"))
  root_thr <- file.path(ctx$root_output_dir %||% ctx$config$project$output_dir, "Tables", "PAMM",
                        paste0("PAMM_thresholds_", Index, "_locked.rds"))

  is_disc <- .tpamm_is_discovery(ctx, bl)
  probs <- as.numeric(bl$threshold_probs %||% c(0.05, 0.95))
  fb_probs <- as.numeric(bl$threshold_fallback_probs %||% c(0.10, 0.90))
  min_abn <- as.integer(bl$min_abnormal_person_days %||% 50L)

  if (is_disc || !isTRUE(bl$validation_apply_locked %||% TRUE)) {
    thr <- .tpamm_lock_thresholds(long$expo, probs = probs)
    n_abn <- sum(long$expo <= thr$lo | long$expo >= thr$hi, na.rm = TRUE)
    if (is.finite(n_abn) && n_abn < min_abn) {
      cli::cli_alert_warning(
        "trajectory_pamm [{Index}]: P{100*probs[1]}/P{100*probs[2]} 异常人天={n_abn} < {min_abn}，降级 P{100*fb_probs[1]}/P{100*fb_probs[2]}"
      )
      thr <- .tpamm_lock_thresholds(long$expo, probs = fb_probs)
      thr$fallback <- TRUE
    } else thr$fallback <- FALSE
    saveRDS(thr, thr_path)
    dir.create(dirname(root_thr), recursive = TRUE, showWarnings = FALSE)
    saveRDS(thr, root_thr)
  } else {
    # 外验：config 注入路径优先；再扫同指标 mimic / 【failed】mimic 的 locked / 未加锁文件
    out_ix <- dirname(ctx$config$project$output_dir %||% ".")  # .../by_index/NLPR
    by_index <- dirname(out_ix)
    ix_nm <- basename(out_ix)
    disc_db <- as.character(bl$discovery_db %||% "mimic")[1L]
    thr_fns <- c(
      paste0("PAMM_thresholds_", Index, "_locked.rds"),
      paste0("PAMM_thresholds_", Index, ".rds")
    )
    sibling_roots <- unique(c(
      file.path(by_index, ix_nm, disc_db),
      file.path(by_index, paste0("\u3010success\u3011", ix_nm), disc_db),
      file.path(by_index, paste0("\u3010failed\u3011", ix_nm), disc_db),
      file.path(dirname(out_ix), disc_db)
    ))
    sibling_hits <- character(0)
    for (sr in sibling_roots) {
      for (fn in thr_fns) {
        sibling_hits <- c(
          sibling_hits,
          file.path(sr, "Tables", "PAMM", fn),
          file.path(sr, "step25_trajectory_pamm", "Tables", "PAMM", fn)
        )
      }
    }
    lock_candidates <- c(bl$locked_threshold_path %||% "", root_thr, sibling_hits)
    lock_candidates <- unique(lock_candidates[nzchar(lock_candidates) & file.exists(lock_candidates)])
    if (!length(lock_candidates))
      stop("trajectory_pamm: 外验缺少发现集锁定阈值文件 ", root_thr, call. = FALSE)
    thr <- readRDS(lock_candidates[[1L]])
    cli::cli_alert_info("trajectory_pamm [{Index}]: 使用发现集锁定阈值 lo={thr$lo}, hi={thr$hi}")
  }

  # ped data for PAMM
  surv_df <- base[, c(id_col, time_var, event_var, covs), drop = FALSE]
  names(surv_df)[names(surv_df) == time_var] <- "time"
  names(surv_df)[names(surv_df) == event_var] <- "status"
  surv_df$time <- pmin(as.numeric(surv_df$time), max_fu)
  n_ev_raw <- sum(.tpamm_event_01(base[[event_var]], ctx$config), na.rm = TRUE)
  surv_df$status <- .tpamm_event_01(surv_df$status, ctx$config)
  surv_df <- surv_df[is.finite(surv_df$time) & surv_df$time > 0, , drop = FALSE]
  n_ev <- sum(surv_df$status == 1L, na.rm = TRUE)
  cli::cli_alert_info(
    "trajectory_pamm [{Index}]: n={nrow(surv_df)}, events={n_ev} (raw_encode_check={n_ev_raw})"
  )
  if (!n_ev) {
    stop(
      "trajectory_pamm: 编码后仍无事件。event_var=", event_var,
      " levels=", paste(unique(as.character(base[[event_var]])), collapse = ","),
      call. = FALSE
    )
  }

  long2 <- merge(long, surv_df[, c(id_col, covs), drop = FALSE], by = id_col, all.x = TRUE)
  # as_ped with concurrent exposure: use ped toolkit
  ped <- tryCatch({
    pammtools::as_ped(
      data = list(surv_df, long2),
      formula = stats::as.formula(paste0(
        "Surv(time, status) ~ . + concurrent(expo, tz_var = \"time_day\")",
        if (length(covs)) paste0(" + ", paste(covs, collapse = " + ")) else ""
      )),
      cut = cuts,
      id = id_col
    )
  }, error = function(e) {
    cli::cli_alert_warning("as_ped concurrent 失败，回退静态基线暴露: {conditionMessage(e)}")
    NULL
  })

  if (is.null(ped)) {
    # fallback: use day-1 exposure as baseline covariate in PED
    d1 <- long[long$time_day == 1L, c(id_col, "expo"), drop = FALSE]
    sdf <- merge(surv_df, d1, by = id_col, all.x = TRUE)
    ped <- tryCatch(
      pammtools::as_ped(
        data = sdf,
        formula = stats::as.formula(paste0(
          "Surv(time, status) ~ expo",
          if (length(covs)) paste0(" + ", paste(covs, collapse = " + ")) else ""
        )),
        cut = cuts,
        id = id_col
      ),
      error = function(e) {
        stop("trajectory_pamm as_ped 静态回退仍失败: ", conditionMessage(e), call. = FALSE)
      }
    )
  }

  fit <- tryCatch(.tpamm_fit_smooth(ped, intersect(covs, names(ped))), error = function(e) {
    cli::cli_alert_danger("trajectory_pamm GAM 失败: {conditionMessage(e)}")
    NULL
  })

  bur <- .tpamm_burden_table(long, base, id_col, thr, time_var, event_var, covs, max_fu,
                            cfg = ctx$config)
  bur$Index <- Index
  bur$db <- ctx$config$project$database %||% ""
  utils::write.csv(bur, file.path(out_tab, paste0("Table_PAMM_burden_HR_", Index, ".csv")),
                   row.names = FALSE)

  # figure: predicted log-hazard vs expo at selected landmarks
  fig_dir <- file.path(ctx$output_dir_figures %||% file.path(ctx$config$project$output_dir, "Figures"))
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  if (!is.null(fit) && isTRUE(bl$export_figures %||% TRUE)) {
    landmarks <- as.numeric(bl$plot_landmarks %||% c(2, 4, 7, 14))
    expo_grid <- seq(
      as.numeric(stats::quantile(long$expo, 0.02, na.rm = TRUE)),
      as.numeric(stats::quantile(long$expo, 0.98, na.rm = TRUE)),
      length.out = 80L
    )
    pdf_path <- file.path(fig_dir, paste0("Figure_PAMM_", Index, ".pdf"))
    grDevices::pdf(pdf_path, width = 10, height = 8)
    graphics::par(mfrow = c(2, 2), family = "serif")
    for (lm in landmarks) {
      nd <- data.frame(tend = lm, expo = expo_grid, offset = 1)
      for (cv in intersect(covs, names(ped))) {
        if (is.numeric(ped[[cv]])) nd[[cv]] <- stats::median(ped[[cv]], na.rm = TRUE)
        else {
          tab <- sort(table(ped[[cv]]), decreasing = TRUE)
          nd[[cv]] <- names(tab)[1L]
        }
      }
      pr <- tryCatch(
        as.numeric(stats::predict(fit, newdata = nd, type = "link")),
        error = function(e) rep(NA_real_, nrow(nd))
      )
      graphics::plot(
        expo_grid, pr, type = "l", lwd = 2, xlab = Index,
        ylab = "log hazard (PAMM)", main = paste0("Landmark day ", lm)
      )
      graphics::abline(v = c(thr$lo, thr$hi), lty = 2, col = "gray40")
    }
    grDevices::dev.off()
    cli::cli_alert_success("trajectory_pamm 图已写: {.file {basename(pdf_path)}}")
  }

  ctx$results$trajectory_pamm[[Index]] <- list(
    thresholds = thr,
    burden_hr = bur,
    gam = fit,
    n_long = nrow(long),
    is_discovery = is_disc
  )
  cli::cli_alert_success("trajectory_pamm [{Index}] 完成（discovery={is_disc}）")
  ctx
}

register_block(
  "trajectory_pamm",
  block_trajectory_pamm,
  "PAMM 连续指标时变非线性 + P5/P95 占比/累积负担（Fig5/6）"
)
