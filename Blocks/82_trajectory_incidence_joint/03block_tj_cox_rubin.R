###############################################################################
# tj_cox_rubin — 轨迹类别 × 新发结局 序贯 Cox Model1-4（Rubin 合并 m 套）
#
# 暴露 = GBMTM 锁定类别（操作层固定列 grp_<system>，参照组 = 最低风险 T1）
# 推断走 mi_m5_rubin_pool 铁律：每套 complete 拟合 coxph → Rubin 合并
#   （类别列非插补，经 mi_complete_aligned extra 每套自动带回）
#
# joint_trajectory = list(
#   group_col_prefix = "grp_", model_sets = list(model1=…, model2=…, model3=…, model4=…),
#   ties = "efron"
# )
# ctx$results$tj_outcome_<name> = list(event=, time=)   # 来自 tj_data_ingest
#
# register_block: "tj_cox_rubin"
# 写: ctx$results$tj_cox = data.frame(system,outcome,model,term,HR,lo,hi,p,n_events)
#     ctx$results$tj_ph  = PH Schoenfeld（complete#1 代表集，Methods 注明）
# 落盘: results/cox/cox_all_models.csv, results/cox/PH_schoenfeld.csv
###############################################################################

block_tj_cox_rubin <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  suppressMessages({
    library(survival)
    source(file.path(root, "R/literature_trajectory_joint.R"), local = FALSE)
    source(file.path(root, "R/mi_rubin_pool.R"), local = FALSE)
  })
  bl <- ctx$config$joint_trajectory %||% stop("tj_cox_rubin: 缺 config", call. = FALSE)
  id_col <- bl$id_column %||% ctx$config$data$id_column %||% "id"
  prefix <- bl$group_col_prefix %||% "grp_"
  ties <- bl$ties %||% "efron"
  models <- tj_model_covariates(bl)

  df <- ctx$data$cleaned %||% ctx$data$raw
  if (is.null(df)) stop("tj_cox_rubin: 无数据", call. = FALSE)

  systems <- names(bl$index_pairs)
  outcomes <- sub("^tj_outcome_", "", grep("^tj_outcome_", names(ctx$results), value = TRUE))
  if (!length(outcomes)) outcomes <- (bl$outcome %||% list())$primary$name %||% "primary"

  out_root <- file.path(ctx$config$project$output_dir %||% "Output")
  cox_dir <- file.path(out_root, "results", "cox")
  dir.create(cox_dir, showWarnings = FALSE, recursive = TRUE)

  rubin_on <- isTRUE(mi_rubin_enabled(ctx))
  rows <- list(); phrows <- list()

  for (sys in systems) {
    gv <- paste0(prefix, sys)
    if (!gv %in% names(df)) { cli::cli_alert_danger("tj_cox_rubin: 缺类别列 {gv}（先跑 tj_gbmtm_fit）"); next }
    cls_lev <- sort(unique(as.character(df[[gv]])))
    ref <- cls_lev[1]   # coxph 因子系数名 = <col><level>（无分隔），下文按 gv 前缀匹配

    for (oc in outcomes) {
      ov <- ctx$results[[paste0("tj_outcome_", oc)]]
      if (is.null(ov)) { cli::cli_alert_info("tj_cox_rubin: 无结局 {oc}，跳过"); next }

      for (mn in names(models)) {
        covs <- models[[mn]]
        covs_present <- covs[covs %in% names(df)]
        # 组装 data_template：ID + 类别 + 结局 + 协变量（缺失由 mice 覆盖，类别/结局经 extra 带回）
        tpl_cols <- unique(c(id_col, ".tj_row_id", gv, covs_present))
        base <- df[, tpl_cols, drop = FALSE]
        base$.tj_ev <- ov$event
        base$.tj_tm <- ov$time
        base[[gv]] <- factor(base[[gv]], levels = cls_lev)
        base <- base[!is.na(base[[gv]]) & !is.na(base$.tj_tm) & base$.tj_tm > 0, , drop = FALSE]
        if (!nrow(base)) next
        fml <- stats::as.formula(paste0("survival::Surv(.tj_tm, .tj_ev) ~ ", gv,
                                        if (length(covs_present)) paste0(" + ", paste(covs_present, collapse = " + "))))

        fit <- tryCatch(mi_coxph(ctx, fml, base, keep_vars = c(".tj_ev", ".tj_tm", gv)),
                        error = function(e) NULL)
        if (is.null(fit)) { cli::cli_alert_danger("tj_cox_rubin 拟合失败 {sys}/{oc}/{mn}"); next }
        cm <- stats::coef(fit)
        ci <- tryCatch(stats::confint(fit), error = function(e) NULL)
        V <- tryCatch(as.matrix(stats::vcov(fit)), error = function(e) NULL)
        if (is.null(V) && !is.null(fit$var)) V <- as.matrix(fit$var)   # mi_pooled_cox
        if (is.null(V)) { cli::cli_alert_danger("tj_cox_rubin: {sys}/{oc}/{mn} vcov 不可得，跳过"); next }
        se <- sqrt(diag(V))
        pvec <- if (!is.null(summary(fit)$coefficients)) {
          sc <- summary(fit)$coefficients
          if ("Pr(>|z|)" %in% colnames(sc)) sc[, "Pr(>|z|)"] else sc[, ncol(sc)]
        } else 2 * stats::pnorm(-abs(cm / se))
        # ci 为 log 尺度（coxph/confint.mi_pooled_cox 均返回 log 尺度）→ 一次性取指数
        ci_exp <- if (!is.null(ci)) exp(ci) else
          matrix(exp(cbind(cm - 1.96 * se, cm + 1.96 * se)), nrow = length(cm),
                 dimnames = list(names(cm), c("2.5 %", "97.5 %")))
        lo_v <- ci_exp[, 1]; hi_v <- ci_exp[, 2]

        for (tn in names(cm)) {
          if (!grepl(paste0("^", gv), tn)) next
          lvl <- sub(paste0("^", gv), "", tn)
          rows[[paste(sys, oc, mn, tn, sep = "|")]] <- data.frame(
            system = sys, outcome = oc, model = mn, class = lvl, term = tn,
            HR = round(exp(cm[[tn]]), 3),
            lo = round(as.numeric(lo_v[tn]), 3),
            hi = round(as.numeric(hi_v[tn]), 3),
            p = signif(as.numeric(pvec[[tn]]), 4),
            n_events = sum(base$.tj_ev, na.rm = TRUE), stringsAsFactors = FALSE)
        }

        # PH（complete#1 代表集；mi_m5 允许诊断用操作层单套，Methods 注明）
        if (rubin_on && !is.null(ctx$results$mice_model)) {
          d1 <- mi_complete_aligned(ctx, base, 1L, keep_vars = c(".tj_ev", ".tj_tm", gv))
          if (!is.null(d1)) {
            z <- tryCatch(survival::cox.zph(survival::coxph(fml, data = d1, ties = ties)),
                          error = function(e) NULL)
            if (!is.null(z)) {
              tb <- as.data.frame(as.matrix(z$table))
              for (j in seq_len(nrow(tb))) phrows[[paste(sys, oc, mn, rownames(tb)[j], sep = "|")]] <-
                data.frame(system = sys, outcome = oc, model = mn, term = rownames(tb)[j],
                           chisq = round(tb$chisq[j], 2), df = tb$df[j], p = signif(tb$p[j], 4),
                           stringsAsFactors = FALSE)
            }
          }
        }
        cli::cli_alert_success("Cox {sys}/{oc}/{mn} done (rubin={rubin_on})")
      }
    }
  }

  res <- if (length(rows)) do.call(rbind, rows) else data.frame()
  ph  <- if (length(phrows)) do.call(rbind, phrows) else data.frame()
  ctx$results$tj_cox <- res
  ctx$results$tj_ph  <- ph
  if (nrow(res)) utils::write.csv(res, file.path(cox_dir, "cox_all_models.csv"), row.names = FALSE)
  if (nrow(ph))  utils::write.csv(ph,  file.path(cox_dir, "PH_schoenfeld.csv"), row.names = FALSE)
  cli::cli_alert("tj_cox_rubin: {nrow(res)} 行估计, {nrow(ph)} PH 检验, Rubin={rubin_on}")
  ctx
}

register_block("tj_cox_rubin", block_tj_cox_rubin, "轨迹类别 序贯Cox Model1-4 Rubin合并+PH")
