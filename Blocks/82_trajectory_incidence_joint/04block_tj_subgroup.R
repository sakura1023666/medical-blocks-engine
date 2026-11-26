###############################################################################
# tj_subgroup — 轨迹类别 × 亚组分层 HR + LRT 交互 P（Rubin 合并 m 套）
#
# 口径（age_subgroup_binary + 层内剔除分层变量自身）：
#   - 暴露 = GBMTM 锁定类别（参照最低风险类），层内估计各类 vs 参照 HR
#   - 事件过少层（<min_events）→ NE
#   - 交互 P：各插补套 (grp + .li) vs (grp * .li) LRT chi2 平均 → chi2(df)
#   - 层内调整集 = 主分析 model（默认末段）剔除分层变量对应协变量
#
# joint_trajectory$subgroup = list(
#   vars = c("Age_Group","Sex_lbl","DM_lbl","HBP_lbl","Smoke_lbl"),
#   age_cutoff = 65L, model = NULL,     # NULL → 末段 model_sets
#   min_events = 15L, level_defs = list(), layer_dropv = list()
# )
#
# register_block: "tj_subgroup"
# 写: ctx$results$tj_subgroup, ctx$results$tj_p_interaction
# 落盘: results/subgroups/subgroup_forest.csv, p_interaction.csv
###############################################################################

block_tj_subgroup <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  suppressMessages({
    library(survival)
    source(file.path(root, "R/literature_trajectory_joint.R"), local = FALSE)
    source(file.path(root, "R/mi_rubin_pool.R"), local = FALSE)
  })
  bl <- ctx$config$joint_trajectory %||% stop("tj_subgroup: 缺 config", call. = FALSE)
  sg <- bl$subgroup
  if (!is.list(sg) || !length(sg)) {
    cli::cli_alert_info("tj_subgroup: 未配置 subgroup，跳过")
    ctx$results$tj_subgroup <- data.frame(); ctx$results$tj_p_interaction <- data.frame()
    return(ctx)
  }
  id_col <- bl$id_column %||% ctx$config$data$id_column %||% "id"
  prefix <- bl$group_col_prefix %||% "grp_"
  models <- tj_model_covariates(bl)
  mn <- sg$model %||% tail(names(models), 1L)
  m_covs <- models[[mn]]
  min_ev <- as.integer(sg$min_events %||% 15L)
  age_cut <- as.integer(sg$age_cutoff %||% 65L)

  df <- ctx$data$cleaned %||% ctx$data$raw
  oc_key <- grep("^tj_outcome_", names(ctx$results), value = TRUE)
  prim_key <- paste0("tj_outcome_", (bl$outcome %||% list())$primary$name %||% "primary")
  oc <- ctx$results[[prim_key]] %||% ctx$results[[oc_key[1]]]
  if (is.null(df) || is.null(oc)) stop("tj_subgroup: 缺数据或结局（先跑 ingest）", call. = FALSE)

  rubin_on <- isTRUE(mi_rubin_enabled(ctx))
  m_sets <- if (rubin_on) as.integer(ctx$results$mice_model$m %||% 5L) else 1L
  # 操作层代表集（Rubin 关闭时的单套 = ctx$data$cleaned 本身）
  get_set <- function(k) {
    if (!rubin_on) return(df)
    dk <- mi_complete_aligned(ctx, df, k, keep_vars = character(0))
    if (is.null(dk)) return(df)
    for (cn in setdiff(names(df), names(dk))) dk[[cn]] <- df[[cn]]
    dk
  }

  layers <- local({
    d <- df
    L <- list()
    if ("age" %in% names(d)) L$Age_Group <- factor(
      ifelse(d$age >= age_cut, paste0("\u2265 ", age_cut), paste0("< ", age_cut)),
      levels = c(paste0("< ", age_cut), paste0("\u2265 ", age_cut)))
    if ("sex" %in% names(d)) L$Sex_lbl <- factor(ifelse(d$sex == 1, "Male", "Female"), levels = c("Female","Male"))
    for (nm in names(sg$level_defs %||% list())) L[[nm]] <- eval(sg$level_defs[[nm]], envir = d)
    for (nm in c("DM_lbl","HBP_lbl")) {
      base <- switch(nm, DM_lbl = "dm_d", HBP_lbl = "hbp_d")
      if (base %in% names(d) && is.null(L[[nm]]))
        L[[nm]] <- factor(ifelse(d[[base]] == 1, "Yes", "No"), levels = c("No","Yes"))
    }
    if ("smoke" %in% names(d) && is.null(L$Smoke_lbl))
      L$Smoke_lbl <- factor(ifelse(d$smoke == 1, "Ever", "Never"), levels = c("Never","Ever"))
    L
  })
  use_vars <- intersect(sg$vars %||% names(layers), names(layers))

  layer_dropv <- list(Age_Group = "age", Sex_lbl = "sex", Edu_Group = "edu",
                      DM_lbl = c("dm_d","dmmed"), HBP_lbl = c("hbp_d","bpmed"),
                      Smoke_lbl = c("smoke","drink"))
  if (!is.null(sg$layer_dropv)) layer_dropv <- utils::modifyList(layer_dropv, sg$layer_dropv)

  # 对给定行集合跨 m 套拟合；return list(B,U[,setnames], chis, dfi)
  # gv / cls_lev / li_vec 显式传参，不用全局
  fit_set <- function(idx, covs, gv, cls_lev, li_vec = NULL) {
    covs <- covs[covs %in% names(df)]
    hits <- paste0(gv, cls_lev[-1])
    Bs <- NULL; Us <- NULL; chis <- c(); dfi <- 0L
    for (k in seq_len(m_sets)) {
      dd <- get_set(k)
      d <- dd[idx, , drop = FALSE]
      d$.tj_ev <- oc$event[idx]; d$.tj_tm <- oc$time[idx]
      keep_mask <- !is.na(d[[gv]]) & !is.na(d$.tj_tm) & d$.tj_tm > 0
      d <- d[keep_mask, , drop = FALSE]
      li_sub <- if (is.null(li_vec)) NULL else li_vec[idx][keep_mask]
      if (!nrow(d) || sum(d$.tj_ev, na.rm = TRUE) < min_ev) next
      d[[gv]] <- factor(d[[gv]], levels = cls_lev)
      rhs_cov <- paste(covs[covs %in% names(d)], collapse = " + ")
      if (is.null(li_vec)) {
        fml <- stats::as.formula(paste0("survival::Surv(.tj_tm,.tj_ev) ~ ", gv,
                                        if (nzchar(rhs_cov)) paste0(" + ", rhs_cov)))
        fit <- tryCatch(coxph(fml, data = d, ties = "efron"), error = function(e) NULL)
        if (is.null(fit)) next
        cf <- stats::coef(fit); vv <- diag(as.matrix(stats::vcov(fit)))
        hh <- hits[hits %in% names(cf)]
        if (length(hh) && all(is.finite(cf[hh])) && all(vv[hh] > 0)) {
          Bs <- rbind(Bs, cf[hh]); Us <- rbind(Us, vv[hh])
        }
      } else {
        d$.li <- li_sub
        f0f <- paste0("survival::Surv(.tj_tm,.tj_ev) ~ ", gv, " + .li",
                      if (nzchar(rhs_cov)) paste0(" + ", rhs_cov))
        f1f <- paste0("survival::Surv(.tj_tm,.tj_ev) ~ ", gv, " * .li",
                      if (nzchar(rhs_cov)) paste0(" + ", rhs_cov))
        f0 <- tryCatch(coxph(stats::as.formula(f0f), data = d, ties="efron"), error=function(e) NULL)
        f1 <- tryCatch(coxph(stats::as.formula(f1f), data = d, ties="efron"), error=function(e) NULL)
        if (!is.null(f0) && !is.null(f1)) {
          chis <- c(chis, 2*(f1$loglik[2]-f0$loglik[2])); dfi <- max(dfi, length(cls_lev)-1L)
        }
      }
    }
    list(B = Bs, U = Us, hits = hits, chis = chis, dfi = dfi)
  }

  rows <- list(); pirows <- list()
  for (sys in names(bl$index_pairs)) {
    gv <- paste0(prefix, sys)
    if (!gv %in% names(df)) next
    cls_lev <- sort(unique(as.character(df[[gv]])))
    disp <- cls_lev[-1]

    ov <- fit_set(seq_len(nrow(df)), m_covs, gv, cls_lev)
    if (!is.null(ov$B) && nrow(ov$B) >= 1) {
      for (dt in disp) {
        cn <- paste0(gv, dt)
        if (!cn %in% colnames(ov$B)) next
        R <- tj_rubin_vec(ov$B[, cn, drop = FALSE], ov$U[, cn, drop = FALSE])
        rows[[paste(sys, dt, sep="|")]] <- data.frame(
          system=sys, subgroup="Overall", level="Overall", class=dt,
          n=nrow(df), events=sum(oc$event, na.rm=TRUE),
          HR=round(exp(R$est),3), lo=round(exp(R$lo),3), hi=round(exp(R$hi),3),
          p=signif(R$p,4), status="OK", stringsAsFactors=FALSE)
      }
    }

    for (lname in use_vars) {
      covs <- setdiff(m_covs, layer_dropv[[lname]] %||% character(0))
      for (lev in levels(layers[[lname]])) {
        idx <- which(layers[[lname]] == lev)
        ev_n <- sum(oc$event[idx], na.rm = TRUE)
        fl <- if (ev_n >= min_ev) fit_set(idx, covs, gv, cls_lev) else list(B = NULL)
        for (dt in disp) {
          cn <- paste0(gv, dt); key <- paste(sys, lname, lev, dt, sep="|")
          if (is.null(fl$B) || !cn %in% colnames(fl$B)) {
            rows[[key]] <- data.frame(system=sys, subgroup=lname, level=lev, class=dt,
              n=length(idx), events=ev_n, HR=NA_real_, lo=NA_real_, hi=NA_real_, p=NA_real_,
              status="NE", stringsAsFactors=FALSE)
          } else {
            R <- tj_rubin_vec(fl$B[, cn, drop = FALSE], fl$U[, cn, drop = FALSE])
            rows[[key]] <- data.frame(system=sys, subgroup=lname, level=lev, class=dt,
              n=length(idx), events=ev_n, HR=round(exp(R$est),3), lo=round(exp(R$lo),3),
              hi=round(exp(R$hi),3), p=signif(R$p,4), status="OK", stringsAsFactors=FALSE)
          }
        }
      }
      li_vec <- as.integer(layers[[lname]] != levels(layers[[lname]])[1])
      pin <- fit_set(seq_len(nrow(df)), covs, gv, cls_lev, li_vec = li_vec)
      # 输出门控按「有效 LR 个数」而非 m_sets：非 Rubin（m=1）也要能报交互 P
      chis_ok <- pin$chis[is.finite(pin$chis) & pin$chis >= 0]
      if (length(chis_ok) >= 1 && pin$dfi > 0) {
        pirows[[paste(sys, lname, sep="|")]] <- data.frame(
          system=sys, subgroup=lname,
          p_interaction=signif(stats::pchisq(mean(chis_ok), df=pin$dfi, lower.tail=FALSE), 4),
          stringsAsFactors=FALSE)
      }
    }
  }

  res <- if (length(rows)) do.call(rbind, rows) else data.frame()
  pib <- if (length(pirows)) do.call(rbind, pirows) else data.frame()
  ctx$results$tj_subgroup <- res
  ctx$results$tj_p_interaction <- pib

  out_root <- file.path(ctx$config$project$output_dir %||% "Output")
  sg_dir <- file.path(out_root, "results", "subgroups"); dir.create(sg_dir, showWarnings = FALSE, recursive = TRUE)
  if (nrow(res)) utils::write.csv(res, file.path(sg_dir, "subgroup_forest.csv"), row.names=FALSE)
  if (nrow(pib)) utils::write.csv(pib, file.path(sg_dir, "p_interaction.csv"), row.names=FALSE)
  cli::cli_alert("tj_subgroup: {nrow(res)} 行, {nrow(pib)} 交互P, Rubin={rubin_on} (m={m_sets})")
  ctx
}

register_block("tj_subgroup", block_tj_subgroup, "轨迹类别 亚组分层HR+LRT交互P Rubin")
