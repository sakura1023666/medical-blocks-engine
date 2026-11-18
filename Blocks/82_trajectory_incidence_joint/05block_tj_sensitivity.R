###############################################################################
# tj_sensitivity — 轨迹类别 × 新发结局 敏感性分析（文献 9 项口径）
#
# 每项对末段模型（默认最后一个 model_set）重估各类 vs 参照 HR；
# MICE 变量走 m 套 coxph + Rubin（tj_rubin_vec）；⑤完整病例 = 未插补单套（m=1 如实标注）。
#
# 项目（config$joint_trajectory$sensitivity$items，缺列/缺文件自动跳过并记日志）：
#   S0_main                        主分析复算（同 cohort 同模型）
#   S1_exclude_first2y             排除随访前 N 年内事件（exclude_first_years，默认 2）
#   S3_exclude_DM / S4_exclude_HBP 排除基线糖尿病 / 高血压
#   S5_complete_case               协变量完整病例（未插补）
#   S6_exclude_glucose_lipid_med   排除降糖/降脂药使用者
#   S7_PP_weighted                 后验概率加权 Cox（类别不确定性；weights>=0.1 截断）
#   S9a_linear_time / S9b_cubic_time  随访时间线性/三次主效应
#
# register_block: "tj_sensitivity"
# 写: ctx$results$tj_sensitivity
# 落盘: results/sensitivity/sens_table.csv
###############################################################################

block_tj_sensitivity <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  suppressMessages({
    library(survival)
    source(file.path(root, "R/literature_trajectory_joint.R"), local = FALSE)
    source(file.path(root, "R/mi_rubin_pool.R"), local = FALSE)
  })
  bl <- ctx$config$joint_trajectory %||% stop("tj_sensitivity: 缺 config", call. = FALSE)
  sens_cfg <- bl$sensitivity
  if (!is.list(sens_cfg) || !length(sens_cfg)) {
    cli::cli_alert_info("tj_sensitivity: 未配置 sensitivity，跳过")
    ctx$results$tj_sensitivity <- data.frame(); return(ctx)
  }
  id_col <- bl$id_column %||% ctx$config$data$id_column %||% "id"
  prefix <- bl$group_col_prefix %||% "grp_"
  models <- tj_model_covariates(bl)
  mn <- sens_cfg$model %||% tail(names(models), 1L)
  covs_all <- models[[mn]]

  df <- ctx$data$cleaned %||% ctx$data$raw
  prim_key <- paste0("tj_outcome_", (bl$outcome %||% list())$primary$name %||% "primary")
  oc <- ctx$results[[prim_key]] %||% ctx$results$tj_outcome_primary
  if (is.null(df) || is.null(oc)) stop("tj_sensitivity: 缺数据或结局", call. = FALSE)
  oc_e <- oc$event; oc_t <- oc$time

  rubin_on <- isTRUE(mi_rubin_enabled(ctx))
  m_sets <- if (rubin_on) as.integer(ctx$results$mice_model$m %||% 5L) else 1L

  # 单体系行集拟合：gv 显式传参；use_cc=TRUE 只用 master（未插补）
  fit_hr <- function(idx, gv, covs, extra_terms = "", wfun = NULL, use_cc = FALSE) {
    covs <- covs[covs %in% names(df)]
    Bs <- NULL; Us <- NULL
    nSet <- if (use_cc || !rubin_on) 1L else m_sets
    tpl <- df[idx, unique(c(id_col, gv, covs)), drop = FALSE]
    for (k in seq_len(nSet)) {
      if (use_cc || !rubin_on) {
        d <- tpl
      } else {
        dk <- mi_complete_aligned(ctx, tpl, k, keep_vars = c(id_col, gv))
        if (is.null(dk)) next
        d <- dk[, names(tpl), drop = FALSE]   # 插补列覆盖，gv 经 extra 带回
      }
      d$.tj_ev <- oc_e[idx]; d$.tj_tm <- oc_t[idx]
      keep <- !is.na(d[[gv]]) & !is.na(d$.tj_tm) & d$.tj_tm > 0
      d <- d[keep, , drop = FALSE]
      w <- if (is.null(wfun)) NULL else wfun(d)   # d 已过滤 → 长度自然对齐
      if (!nrow(d)) next
      cls_lev <- sort(unique(as.character(d[[gv]])))
      if (length(cls_lev) < 2) next
      d[[gv]] <- factor(d[[gv]], levels = cls_lev)
      rhs <- paste0(gv, " + ", paste(covs[covs %in% names(d)], collapse = " + "), extra_terms)
      fml <- stats::as.formula(paste0("survival::Surv(.tj_tm,.tj_ev) ~ ", rhs))
      fit <- tryCatch(suppressWarnings(coxph(fml, data = d, ties = "efron", weights = w)),
                      error = function(e) NULL)
      if (is.null(fit)) next
      cf <- stats::coef(fit); vv <- diag(as.matrix(stats::vcov(fit)))
      hit <- paste0(gv, cls_lev[-1]); hit <- hit[hit %in% names(cf)]
      if (length(hit) && all(is.finite(cf[hit])) && all(vv[hit] > 0)) {
        Bs <- rbind(Bs, cf[hit]); Us <- rbind(Us, vv[hit])
      }
    }
    if (is.null(Bs) || !nrow(Bs)) return(NULL)
    R <- tj_rubin_vec(Bs, Us)
    data.frame(term = rownames(R), class = sub(paste0("^", gv), "", rownames(R)),
               HR = round(exp(R$est), 3), lo = round(exp(R$lo), 3), hi = round(exp(R$hi), 3),
               p = signif(R$p, 4), m = nrow(Bs), stringsAsFactors = FALSE)
  }

  items <- sens_cfg$items %||% c("S0_main","S1_exclude_first2y","S3_exclude_DM","S4_exclude_HBP",
                                 "S5_complete_case","S6_exclude_glucose_lipid_med","S7_PP_weighted",
                                 "S9a_linear_time","S9b_cubic_time")
  tw <- as.numeric(bl$exclude_first_years %||% 2) * 12
  cc_cols <- intersect(unlist(models, use.names = FALSE), names(df))
  cc_cols <- setdiff(cc_cols, c(id_col))
  cc <- if (length(cc_cols)) which(stats::complete.cases(df[, cc_cols, drop = FALSE])) else integer(0)
  out_root <- file.path(ctx$config$project$output_dir %||% "Output")

  rows <- list()
  for (sys in names(bl$index_pairs)) {
    gv <- paste0(prefix, sys)
    if (!gv %in% names(df)) next
    add <- function(tag, r) {
      if (is.null(r) || !nrow(r)) { cli::cli_alert_info("敏感性 {tag}/{sys}: 不可估，跳过"); return(invisible()) }
      r$analysis <- tag; r$system <- sys
      rows[[paste0(sys, "_", tag)]] <<- r
    }
    all_idx <- seq_len(nrow(df))
    pp_path <- file.path(out_root, "results", "trajectories", paste0("posterior_", sys, ".csv"))
    pp <- NULL
    if (file.exists(pp_path)) {
      p <- utils::read.csv(pp_path, stringsAsFactors = FALSE)
      pp <- list(w = as.matrix(p[, setdiff(names(p), "id"), drop = FALSE]), id = as.character(p$id))
    }

    for (item in items) {
      tryCatch(switch(item,
        S0_main = add(item, fit_hr(all_idx, gv, covs_all)),
        S1_exclude_first2y = add(item, fit_hr(which(oc_e == 0 | oc_t >= tw), gv, covs_all)),
        S3_exclude_DM = add(item, fit_hr(which(is.na(df$dm_d) | df$dm_d == 0), gv, covs_all)),
        S4_exclude_HBP = add(item, fit_hr(which(is.na(df$hbp_d) | df$hbp_d == 0), gv, covs_all)),
        S5_complete_case = if (length(cc) > 30) add(item, fit_hr(cc, gv, covs_all, use_cc = TRUE)) else NULL,
        S6_exclude_glucose_lipid_med = add(item, fit_hr(which(
          (is.na(df$chol_med_w3) | df$chol_med_w3 == 0) &
          (is.na(df$dmmed) | df$dmmed == 0) &
          (is.na(df$insulin) | df$insulin == 0)), gv, covs_all)),
        S7_PP_weighted = if (!is.null(pp)) add(item, fit_hr(
          all_idx, gv, covs_all, wfun = function(d) {
            lv <- as.integer(sub("^T", "", d[[gv]]))
            ri <- match(as.character(d[[id_col]]), pp$id)
            pmax(pp$w[cbind(ri, lv)], 0.1)
          })) else cli::cli_alert_info("S7/{sys}: 无后验文件，跳过"),
        S9a_linear_time = add(item, fit_hr(all_idx, gv, covs_all, extra_terms = " + .tj_tm")),
        S9b_cubic_time = add(item, fit_hr(all_idx, gv, covs_all, extra_terms = " + .tj_tm + I(.tj_tm^3)")),
        cli::cli_alert_info("敏感性项 '{item}' 未实现，跳过")
      ), error = function(e) cli::cli_alert_warning("敏感性 {item}/{sys} 失败: {conditionMessage(e)}"))
    }
  }

  res <- if (length(rows)) do.call(rbind, rows) else data.frame()
  ctx$results$tj_sensitivity <- res
  sd <- file.path(out_root, "results", "sensitivity"); dir.create(sd, showWarnings = FALSE, recursive = TRUE)
  if (nrow(res)) utils::write.csv(res, file.path(sd, "sens_table.csv"), row.names = FALSE)
  cli::cli_alert("tj_sensitivity: {nrow(res)} 行, 项数={if (nrow(res)) length(unique(res$analysis)) else 0}, Rubin={rubin_on}")
  ctx
}

register_block("tj_sensitivity", block_tj_sensitivity, "轨迹类别 敏感性 9 项 Rubin/完整病例")
