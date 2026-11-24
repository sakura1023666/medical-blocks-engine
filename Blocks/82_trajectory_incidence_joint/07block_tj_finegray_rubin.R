###############################################################################
# tj_finegray_rubin — 轨迹类别 × 新发结局 Fine-Gray 竞争风险（Rubin 合并 m 套）
#
# 套路「轨迹发病」竞争风险版：暴露 = GBMTM 锁定类别（grp_<system>，参照 = T1），
# 结局 = 主事件（cause=failcode），死亡（或配置的死因编码）= 竞争事件；
# 每套 MICE complete 拟合 cmprsk::crr → mi_rubin_pool_estimates 合并（mi_m5 铁律）。
# cmprsk 缺失时回退 cause-specific Cox（coxph，事件=主因），表注/日志写明口径。
#
# joint_trajectory = list(
#   competing_risk = list(
#     enable = TRUE,
#     cause = 1L,                      # fstatus 中主事件编码（crr failcode）
#     cencode = 0L,                    # 删失编码
#     death_cause = 2L,                # 竞争事件编码（默认 2=死亡；多死因用向量）
#     event_col_overrides = list()     # 可选：结局名 -> c(event,cause编码) 覆盖
#   ),
#   ...同 tj_cox_rubin（model_sets / group_col_prefix / id_column）
# )
# 结局列约定：ingest 产出 .tj_ev(0/1 主事件) + .tj_tm；竞争风险另需 fstatus：
#   fstatus = ifelse(.tj_ev==1, cause, ifelse(death_event==1, death_cause, cencode))
#   death 事件列 = bl$competing_risk$death_event_col %||% "death_event"（0/1 列，
#   由课题数据或 ingest 预生成；无该列且 master 无死亡字段 → 块跳过并警告，
#   禁止静默把死亡当删失再冒充竞争风险）。
#
# register_block: "tj_finegray_rubin"
# 写: ctx$results$tj_fg = data.frame(system,outcome,model,term,sHR,lo,hi,p,method,n_events)
# 落盘: results/finegray/finegray_all_models.csv
###############################################################################

block_tj_finegray_rubin <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  suppressMessages({
    library(survival)
    source(file.path(root, "R/literature_trajectory_joint.R"), local = FALSE)
    source(file.path(root, "R/mi_rubin_pool.R"), local = FALSE)
  })
  bl <- ctx$config$joint_trajectory %||% stop("tj_finegray_rubin: 缺 config$joint_trajectory", call. = FALSE)
  cr <- bl$competing_risk %||% list(enable = TRUE)
  if (identical(cr$enable, FALSE)) {
    cli::cli_alert_info("tj_finegray_rubin: competing_risk$enable=FALSE，跳过")
    return(invisible(ctx))
  }
  id_col <- bl$id_column %||% ctx$config$data$id_column %||% "id"
  prefix <- bl$group_col_prefix %||% "grp_"
  cause  <- as.integer(cr$cause %||% 1L)
  cencode <- as.integer(cr$cencode %||% 0L)
  death_cause <- as.integer(cr$death_cause %||% 2L)
  death_col <- cr$death_event_col %||% "death_event"
  death_tcol <- cr$death_time_col %||% NULL   # 死亡者的 ftime 列（月）；NULL 则沿用结局 time
  use_cmprsk <- requireNamespace("cmprsk", quietly = TRUE)
  if (!use_cmprsk) cli::cli_alert_warning(
    "tj_finegray_rubin: cmprsk 不可用 -> 回退 cause-specific Cox（主事件 vs 其余，死亡按删失以外的竞争事件仍计 fstatus）")

  df <- ctx$data$cleaned %||% ctx$data$raw
  if (is.null(df)) stop("tj_finegray_rubin: 无数据", call. = FALSE)
  if (!death_col %in% names(df)) {
    cli::cli_alert_danger(paste0(
      "tj_finegray_rubin: 缺死亡/竞争事件列 '", death_col, "'。",
      "竞争风险须显式死因编码：请在 Data/master 预生成 ", death_col,
      " (0/1) 或在 config$joint_trajectory$competing_risk$death_event_col 指定。跳过。"))
    return(invisible(ctx))
  }

  models <- tj_model_covariates(bl)
  systems <- names(bl$index_pairs)
  outcomes <- sub("^tj_outcome_", "", grep("^tj_outcome_", names(ctx$results), value = TRUE))
  if (!length(outcomes)) outcomes <- (bl$outcome %||% list())$primary$name %||% "primary"

  # 竞争事件语义自证（文献敏感性② = non-CVD death）：
  #  - 死亡者中若无人带主结局事件 → 竞争事件即 "死亡且无主结局（非主结局死亡近似）"
  #  - 有死因列 death_cause_icd + non_cause_pattern → 按 ICD 判非主结局死（严格口径）
  # 语义写入 attr，Table 4 脚注与 Methods 必须如实引用，禁止把全因死亡冒充 non-CVD 死亡。
  cr_note <- cr$death_semantics_note %||% NULL
  icd_col <- cr$death_cause_icd_col %||% NULL
  d_comp_lgl <- NULL   # 竞争事件（死亡）逻辑向量；NULL=沿用 death_col==1
  if (!is.null(icd_col) && icd_col %in% names(df) && !is.null(cr$main_cause_regex)) {
    # main_cause_regex = 死因归属主结局的 ICD 模式；匹配 → 非竞争（缺事件记录的保守删失）
    main_death <- grepl(cr$main_cause_regex, as.character(df[[icd_col]]), perl = TRUE)
    main_death[is.na(main_death)] <- FALSE
    d_comp_lgl <- as.integer(df[[death_col]]) == 1L & !main_death
    prim0 <- ctx$results[[paste0("tj_outcome_", outcomes[1])]]
    n_amb <- if (!is.null(prim0)) sum(as.integer(df[[death_col]]) == 1L & main_death &
                 as.integer(prim0$event) != 1L, na.rm = TRUE) else 0L
    cr_note <- sprintf("non-%s death by underlying cause: %s NOT matching /%s/ (%d %s-cause deaths without recorded event censored conservatively)",
                       toupper(outcomes[1]), icd_col, cr$main_cause_regex, n_amb, outcomes[1])
    cli::cli_alert_info("tj_finegray_rubin: ICD 死因口径启用 -> {cr_note}")
  } else if (is.null(cr_note)) {
    prim_oc <- ctx$results[[paste0("tj_outcome_", outcomes[1])]]
    mixed <- if (!is.null(prim_oc)) sum(as.integer(df[[death_col]]) == 1L &
                       as.integer(prim_oc$event) == 1L, na.rm = TRUE) else NA_integer_
    cr_note <- if (identical(cr$competing_is_all_cause, TRUE)) {
      "all-cause death (explicit config declaration)"
    } else {
      sprintf("death without reported incident %s (non-%s death approximation; %d deaths co-occurring with the event are coded as the event, not as competing)",
              outcomes[1], outcomes[1], if (is.na(mixed)) 0L else mixed)
    }
  }
  ctx$results$tj_fg_note <- cr_note

  out_root <- file.path(ctx$config$project$output_dir %||% "Output")
  fg_dir <- file.path(out_root, "results", "finegray")
  dir.create(fg_dir, showWarnings = FALSE, recursive = TRUE)

  rows <- list()
  for (sys in systems) {
    gv <- paste0(prefix, sys)
    if (!gv %in% names(df)) { cli::cli_alert_danger("tj_finegray_rubin: 缺类别列 {gv}（先跑 tj_gbmtm_fit）"); next }
    cls_lev <- sort(unique(as.character(df[[gv]])))

    for (oc in outcomes) {
      ov <- ctx$results[[paste0("tj_outcome_", oc)]]
      if (is.null(ov)) { cli::cli_alert_info("tj_finegray_rubin: 无结局 {oc}，跳过"); next }

      for (mn in names(models)) {
        covs_present <- models[[mn]][models[[mn]] %in% names(df)]
        tpl_cols <- unique(c(id_col, ".tj_row_id", gv, covs_present))
        base <- df[, tpl_cols, drop = FALSE]
        d_ev  <- as.integer(df[[death_col]])
        # 竞争事件判定：ICD 口径优先（死亡且死因非主结局），否则死亡即竞争
        dec   <- if (!is.null(d_comp_lgl)) d_comp_lgl else (d_ev == 1L)
        d_tm  <- if (!is.null(death_tcol) && death_tcol %in% names(df))
                    as.numeric(df[[death_tcol]]) else NULL
        base$.tj_ev <- ov$event
        base$.tj_tm <- ov$time
        base$.tj_fs <- ifelse(as.integer(ov$event) == 1L, cause,
                        ifelse(dec, death_cause[1], cencode))
        # 竞争事件者 ftime = 死亡时间（有列时），Fine-Gray 要求事件时间与状态一致
        if (!is.null(d_tm)) {
          is_comp <- base$.tj_fs == death_cause[1]
          bad_na  <- is_comp & (is.na(d_tm) | d_tm <= 0)
          if (any(bad_na)) {
            cli::cli_alert_warning("tj_finegray_rubin {sys}/{oc}: {sum(bad_na)} 例竞争事件缺死亡时间 -> 记为删失")
            base$.tj_fs[bad_na] <- cencode
            is_comp <- base$.tj_fs == death_cause[1]
          }
          base$.tj_tm[is_comp] <- d_tm[is_comp]
        }
        base[[gv]] <- factor(base[[gv]], levels = cls_lev)
        base <- base[!is.na(base[[gv]]) & !is.na(base$.tj_tm) & base$.tj_tm > 0, , drop = FALSE]
        if (!nrow(base)) next

        cov_df <- function(d) {
          mm <- stats::model.matrix(~ ., data = d[, c(gv, covs_present), drop = FALSE])
          mm[, setdiff(colnames(mm), "(Intercept)"), drop = FALSE]
        }
        fit_one <- function(d1) {
          mm <- cov_df(d1)
          if (use_cmprsk) {
            f <- tryCatch(cmprsk::crr(ftime = d1$.tj_tm, fstatus = d1$.tj_fs, cov1 = mm,
                                      failcode = cause, cencode = cencode),
                          error = function(e) NULL)
            if (is.null(f) || is.null(f$coef) || !length(f$coef)) return(NULL)
            v <- as.matrix(f$var)
            if (is.null(dimnames(v)) && length(f$coef) == nrow(v))
              dimnames(v) <- list(names(f$coef), names(f$coef))
            list(coef = f$coef, var = v)
          } else {
            dd <- d1; dd$.evt <- as.integer(dd$.tj_ev == 1L)
            rhs <- paste0("survival::Surv(.tj_tm, .evt) ~ ", gv,
                          if (length(covs_present)) paste0(" + ", paste(covs_present, collapse = " + ")))
            f <- tryCatch(survival::coxph(stats::as.formula(rhs), data = dd, ties = bl$ties %||% "efron"),
                          error = function(e) NULL)
            if (is.null(f)) return(NULL)
            list(coef = stats::coef(f), var = as.matrix(stats::vcov(f)))
          }
        }

        # Rubin：每套 complete 拟合 -> 合并（与 mi_coxph 同构，直接走通用池）
        rubin_on <- isTRUE(mi_rubin_enabled(ctx)) && !is.null(ctx$results$mice_model)
        fit_list <- list()
        if (rubin_on) {
          m <- as.integer(ctx$config$imputation$m %||% 5L)
          for (k in seq_len(m)) {
            d1 <- mi_complete_aligned(ctx, base, k, keep_vars = c(".tj_ev", ".tj_tm", ".tj_fs", gv))
            if (is.null(d1)) next
            r <- fit_one(d1)
            if (!is.null(r)) fit_list[[length(fit_list) + 1L]] <- r
          }
        }
        method_lab <- if (use_cmprsk) "Fine-Gray (crr)" else "cause-specific Cox"
        if (length(fit_list) < 2L) {
          # 无 MICE 或池失败：操作层单套（写明，不冒充 Rubin）
          r <- fit_one(base)
          if (is.null(r)) { cli::cli_alert_danger("tj_finegray_rubin 拟合失败 {sys}/{oc}/{mn}"); next }
          cm <- r$coef
          se <- sqrt(diag(as.matrix(r$var)))
          names(se) <- names(cm)
          rubin_n <- 1L
        } else {
          pooled <- mi_rubin_pool_estimates(fit_list)
          if (is.null(pooled)) { cli::cli_alert_danger("tj_finegray_rubin: Rubin 池失败 {sys}/{oc}/{mn}"); next }
          cm <- pooled$coef
          se <- pooled$se
          rubin_n <- length(fit_list)
        }
        z <- cm / se
        pvec <- 2 * stats::pnorm(-abs(z))
        lo_v <- exp(cm - 1.96 * se); hi_v <- exp(cm + 1.96 * se)

        for (tn in names(cm)) {
          if (!grepl(paste0("^", gv), tn)) next
          lvl <- sub(paste0("^", gv), "", tn)
          rows[[paste(sys, oc, mn, tn, sep = "|")]] <- data.frame(
            system = sys, outcome = oc, model = mn, class = lvl, term = tn,
            sHR = round(exp(cm[[tn]]), 3),
            lo = round(as.numeric(lo_v[tn]), 3), hi = round(as.numeric(hi_v[tn]), 3),
            p = signif(as.numeric(pvec[tn]), 4),
            method = paste0(method_lab, if (rubin_n > 1L) sprintf(", Rubin m-pooled (%d/%d)", rubin_n, rubin_n) else " (complete#1)"),
            n_events = sum(base$.tj_fs == cause, na.rm = TRUE),
            n_competing = sum(base$.tj_fs %in% death_cause, na.rm = TRUE),
            stringsAsFactors = FALSE)
        }
        cli::cli_alert_success("FG {sys}/{oc}/{mn} done (method={method_lab}, rubin_n={rubin_n})")
      }
    }
  }

  res <- if (length(rows)) do.call(rbind, rows) else data.frame()
  ctx$results$tj_fg <- res
  if (nrow(res)) {
    utils::write.csv(res, file.path(fg_dir, "finegray_all_models.csv"), row.names = FALSE)
    if (!use_cmprsk) attr(res, "note") <- "cmprsk unavailable; cause-specific Cox fallback"
  }
  invisible(ctx)
}

register_block("tj_finegray_rubin", block_tj_finegray_rubin,
               "轨迹类别 × 新发结局 Fine-Gray 竞争风险（Rubin m 套合并）")
