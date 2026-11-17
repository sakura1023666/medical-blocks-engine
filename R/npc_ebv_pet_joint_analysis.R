# =============================================================================
# NPC EBV DNA × PET/CT 联合预测（真实重算，不搬运报告表图）
# 输入：DATA/鼻咽癌EBV_PETCT数据表(1).xlsx 病例级核查表
# 输出：summary_results 中 Table 5+ / Figure 7+（不覆盖 OS-ML 1–4 / 1–6）
# =============================================================================

npc_ebv_pet_read_analysis_df <- function(workbook) {
  if (!requireNamespace("readxl", quietly = TRUE) && !requireNamespace("openxlsx", quietly = TRUE)) {
    stop("需要 readxl 或 openxlsx 读 xlsx")
  }
  read_sheet <- function(sheet, skip = 2L) {
    if (requireNamespace("readxl", quietly = TRUE)) {
      as.data.frame(readxl::read_excel(workbook, sheet = sheet, skip = skip), stringsAsFactors = FALSE)
    } else {
      openxlsx::read.xlsx(workbook, sheet = sheet, startRow = skip + 1L)
    }
  }
  b <- read_sheet("核查后分析病例_391例", 2L)
  a <- tryCatch(read_sheet("更新后数据表_全队列412例", 2L), error = function(e) NULL)
  idx <- tryCatch(read_sheet("逐例对照索引", 2L), error = function(e) NULL)

  # 标准化列名（核查表）
  ren <- c(
    "原表行" = "row_src", "纳入" = "include", "性别" = "sex", "年龄" = "age",
    "T" = "T", "N" = "N", "M" = "M", "AJCC8" = "ajcc8", "诊断日期" = "dx_date",
    "诊断年" = "dx_year", "HBsAg" = "hbsag", "IC原编码" = "ic_code",
    "EBV阈值" = "lod", "T0达阈" = "t0_pos", "T0归一分数" = "t0_score",
    "T1达阈" = "t1_pos", "T1归一分数" = "t1_score",
    "T2达阈" = "t2_pos", "T2归一分数" = "t2_score",
    "T0记录类型" = "t0_kind", "T1记录类型" = "t1_kind", "T2记录类型" = "t2_kind",
    "原发SUVmax" = "suv_p", "原发SUVmean" = "suvmean_p", "原TLG" = "tlg",
    "原发MTV" = "mtv", "淋巴结SUVmax" = "suv_n", "分析NTR" = "ntr",
    "分析OS事件" = "os_event", "分析OS月" = "os_time",
    "分析PFS事件" = "pfs_event", "分析PFS月" = "pfs_time",
    "分析DM状态" = "dm_status", "分析DM月" = "dm_time",
    "远转或死亡事件" = "dmd_event", "远转或死亡月" = "dmd_time",
    "局部区域状态" = "lr_status", "首次局部区域月" = "lr_time",
    "6月界标" = "lm6", "9月界标" = "lm9", "12月界标" = "lm12",
    "两时点组" = "two_point", "IC三位码" = "ic_code3"
  )
  for (nm in names(ren)) {
    if (nm %in% names(b) && !ren[[nm]] %in% names(b)) names(b)[names(b) == nm] <- ren[[nm]]
  }

  # 合并轨迹 / 四象限 / 风险评分（来自对照索引或全队列表）
  if (!is.null(idx)) {
    if ("原表行" %in% names(idx)) names(idx)[names(idx) == "原表行"] <- "row_src"
    keep <- intersect(c("row_src", "PID", "重定义轨迹", "三层风险", "联合四象限", "风险评分", "风险三分位"), names(idx))
    if ("row_src" %in% keep) {
      b <- merge(b, idx[, keep, drop = FALSE], by = "row_src", all.x = TRUE, sort = FALSE)
    }
  }
  if (!is.null(a) && "PID" %in% names(a)) {
    # 若索引无轨迹，从全队列表补
    if (!"重定义轨迹" %in% names(b) && "TRAJ_NEW" %in% names(a) && "PID" %in% names(b)) {
      b <- merge(b, a[, intersect(c("PID", "TRAJ_NEW", "TRAJ_RISK", "Joint_Group", "risk_score"), names(a)), drop = FALSE],
                 by = "PID", all.x = TRUE, sort = FALSE)
    }
  }
  if ("重定义轨迹" %in% names(b) && !"traj" %in% names(b)) b$traj <- b[["重定义轨迹"]]
  if ("三层风险" %in% names(b) && !"traj_risk" %in% names(b)) b$traj_risk <- b[["三层风险"]]
  if ("联合四象限" %in% names(b) && !"quadrant" %in% names(b)) b$quadrant <- b[["联合四象限"]]
  if ("风险评分" %in% names(b) && !"risk_score" %in% names(b)) b$risk_score <- b[["风险评分"]]
  if ("风险三分位" %in% names(b) && !"risk_tert" %in% names(b)) b$risk_tert <- b[["风险三分位"]]

  # 派生建模变量
  num <- function(x) suppressWarnings(as.numeric(x))
  b$include <- as.integer(num(b$include))
  b$age <- num(b$age)
  b$male <- as.integer(b$sex %in% c("男", "Male", "M", 1, "1"))
  b$t_ord <- as.integer(gsub("^T", "", as.character(b$T)))
  b$n_ord <- as.integer(gsub("^N", "", as.character(b$N)))
  b$dx_year <- num(b$dx_year)
  b$lod <- num(b$lod)
  b$lod_cat <- factor(b$lod)
  b$t0_pos <- as.integer(num(b$t0_pos) == 1)
  b$t0_score <- num(b$t0_score)
  b$t1_pos <- as.integer(num(b$t1_pos) == 1)
  b$t1_score <- num(b$t1_score)
  b$t2_pos <- as.integer(num(b$t2_pos) == 1)
  b$t2_score <- num(b$t2_score)
  b$mtv <- num(b$mtv)
  b$suv_n <- num(b$suv_n)
  b$suv_p <- num(b$suv_p)
  b$tlg <- num(b$tlg)
  b$ntr <- num(b$ntr)
  b$Lmtv <- log2(1 + pmax(b$mtv, 0, na.rm = FALSE))
  b$Lnode <- log2(1 + pmax(b$suv_n, 0, na.rm = FALSE))
  b$Ltlg <- log2(1 + pmax(b$tlg, 0, na.rm = FALSE))
  b$Lntr <- log2(1 + pmax(b$ntr, 0, na.rm = FALSE))
  b$tlg_high <- as.integer(b$tlg > 65)
  b$ntr_high <- as.integer(b$ntr > 0.64)
  b$pet_high <- as.integer(b$tlg_high == 1 | b$ntr_high == 1)
  b$ebv_high <- as.integer(b$t0_pos == 1 | b$t2_pos == 1)
  # 若无四象限则现场算
  if (!"quadrant" %in% names(b) || all(is.na(b$quadrant))) {
    b$quadrant <- ifelse(b$ebv_high == 0 & b$pet_high == 0, "双低",
                  ifelse(b$ebv_high == 1 & b$pet_high == 0, "仅EBV高",
                  ifelse(b$ebv_high == 0 & b$pet_high == 1, "仅PET高", "双高")))
  }

  # 终点
  b$os_event <- as.integer(num(b$os_event) == 1)
  b$os_time <- num(b$os_time)
  b$pfs_event <- as.integer(num(b$pfs_event) == 1)
  b$pfs_time <- num(b$pfs_time)
  b$dm_status <- as.integer(num(b$dm_status)) # 0/1/2
  b$dm_time <- num(b$dm_time)
  b$dmd_event <- as.integer(num(b$dmd_event) == 1)
  b$dmd_time <- num(b$dmd_time)
  b$lr_status <- as.integer(num(b$lr_status))
  b$lr_time <- num(b$lr_time)
  b$lm6 <- as.integer(num(b$lm6) == 1)
  b$lm9 <- as.integer(num(b$lm9) == 1)
  b$lm12 <- as.integer(num(b$lm12) == 1)

  # 轨迹三层哑变量
  if ("traj_risk" %in% names(b)) {
    tr <- as.character(b$traj_risk)
    b$traj_mid <- as.integer(tr %in% c("中危", "中"))
    b$traj_high <- as.integer(tr %in% c("高危", "高"))
  }

  b
}

.npc_model_vars <- function(spec = c("C", "E", "P2", "EP2")) {
  spec <- match.arg(spec)
  base <- c("age", "male", "t_ord", "n_ord", "dx_year")
  # LOD 作因子：在矩阵里展开
  e <- c("t0_pos", "t0_score")
  p2 <- c("Lmtv", "Lnode")
  switch(spec,
    C = base,
    E = c(base, e),
    P2 = c(base, p2),
    EP2 = c(base, e, p2)
  )
}

.npc_design_matrix <- function(df, vars) {
  # LOD 类别并入临床模型
  d <- df
  if (!"lod_cat" %in% names(d)) d$lod_cat <- factor(d$lod)
  form_vars <- vars
  # 始终加 lod 哑变量到所有规格（报告 C 含阈值类别）
  if (!"lod_cat" %in% form_vars) form_vars <- c(form_vars, "lod_cat")
  fml <- as.formula(paste("~", paste(form_vars, collapse = " + "), "- 1"))
  mm <- model.matrix(fml, data = d)
  # 去常数列
  keep <- apply(mm, 2L, function(z) sd(z, na.rm = TRUE) > 1e-8)
  mm[, keep, drop = FALSE]
}

.npc_endpoint_df <- function(df, endpoint = c("OS", "PFS", "DM", "DM+D", "LR")) {
  endpoint <- match.arg(endpoint)
  out <- df
  if (endpoint == "OS") {
    out$time <- out$os_time
    out$status <- out$os_event # 0/1
    out$cause <- out$status
  } else if (endpoint == "PFS") {
    out$time <- out$pfs_time
    out$status <- out$pfs_event
    out$cause <- out$status
  } else if (endpoint == "DM") {
    out$time <- out$dm_time
    out$status <- as.integer(out$dm_status > 0) # any event for stratification
    out$cause <- out$dm_status # 1=DM, 2=competing death
  } else if (endpoint == "DM+D") {
    out$time <- out$dmd_time
    out$status <- out$dmd_event
    out$cause <- out$status
  } else if (endpoint == "LR") {
    out$time <- out$lr_time
    out$status <- as.integer(out$lr_status > 0)
    out$cause <- out$lr_status # 1=LR, 2=competing
  }
  out <- out[is.finite(out$time) & out$time > 0 & !is.na(out$cause), , drop = FALSE]
  rownames(out) <- NULL
  out
}

.npc_fit_ridge_cox <- function(x, y_surv, alpha = 0) {
  # y_surv: Surv object; for competing risk cause-specific, treat cause!=1 as censored
  fit <- glmnet::cv.glmnet(
    x = x, y = y_surv, family = "cox", alpha = alpha,
    nfolds = min(5L, max(3L, nrow(x) %/% 10L)),
    type.measure = "deviance", standardize = TRUE
  )
  fit
}

.npc_predict_lp <- function(cvfit, xnew) {
  as.numeric(predict(cvfit, newx = xnew, s = "lambda.min", type = "link"))
}

.npc_ipcw_auc <- function(time, cause, marker, horizon = 36, primary_cause = 1L) {
  # timeROC; competing risk if any cause==2 → slot AUC_1; else slot AUC
  ok <- is.finite(time) & is.finite(marker) & !is.na(cause)
  time <- time[ok]; cause <- as.integer(cause[ok]); marker <- marker[ok]
  if (length(time) < 30L) {
    return(list(auc = NA_real_, brier = NA_real_, n = length(time), n_event = 0L))
  }
  has_comp <- any(cause == 2L, na.rm = TRUE)
  # timeROC status: 0 censor, 1 event, 2 competing
  if (has_comp) {
    st <- cause
    st[!st %in% c(0L, 1L, 2L)] <- 0L
  } else {
    st <- as.integer(cause > 0L)
  }
  tr <- tryCatch(
    timeROC::timeROC(
      T = time, delta = st, marker = marker, cause = as.integer(primary_cause),
      times = horizon, iid = FALSE
    ),
    error = function(e) NULL
  )
  auc <- NA_real_
  if (!is.null(tr)) {
    raw <- if (has_comp && !is.null(tr$AUC_1)) tr$AUC_1 else tr$AUC
    raw <- as.numeric(raw)
    fin <- raw[is.finite(raw)]
    if (length(fin)) auc <- as.numeric(utils::tail(fin, 1L))
  }
  list(
    auc = if (length(auc) == 1L && is.finite(auc)) auc else NA_real_,
    brier = NA_real_,
    n = length(time),
    n_event = sum(st == as.integer(primary_cause), na.rm = TRUE)
  )
}

npc_ebv_pet_oof_cv <- function(df, endpoint = "DM", model = "EP2",
                               n_repeats = 8L, n_folds = 5L, seed = 20261117L,
                               horizon = 36) {
  d0 <- .npc_endpoint_df(df, endpoint)
  rownames(d0) <- as.character(seq_len(nrow(d0)))
  vars <- .npc_model_vars(model)
  # 完整病例
  mm_all <- tryCatch(.npc_design_matrix(d0, vars), error = function(e) NULL)
  if (is.null(mm_all)) return(NULL)
  keep_rows <- as.integer(rownames(mm_all))
  d <- d0[keep_rows, , drop = FALSE]
  rownames(d) <- NULL
  x <- mm_all
  rownames(x) <- NULL
  # 分层：主事件
  strata <- as.integer(d$cause == 1L)
  if (endpoint == "DM") strata <- as.integer(d$cause) # 0/1/2
  set.seed(seed)
  oof_sum <- rep(0, nrow(d))
  oof_n <- rep(0, nrow(d))
  for (r in seq_len(n_repeats)) {
    # create folds
    fold <- rep(NA_integer_, nrow(d))
    for (s in sort(unique(strata))) {
      ii <- which(strata == s)
      fold[ii] <- sample(rep(seq_len(n_folds), length.out = length(ii)))
    }
    for (k in seq_len(n_folds)) {
      te <- which(fold == k)
      tr <- which(fold != k)
      if (length(te) < 5L || length(tr) < 20L) next
      # cause-specific: for DM/LR, censor competing (cause==2 -> 0)
      ev <- d$cause
      if (endpoint %in% c("DM", "LR")) {
        ev_tr <- as.integer(ev[tr] == 1L)
      } else {
        ev_tr <- as.integer(ev[tr] > 0)
      }
      ytr <- survival::Surv(d$time[tr], ev_tr)
      xtr <- x[tr, , drop = FALSE]
      xte <- x[te, , drop = FALSE]
      # drop NA rows
      oktr <- complete.cases(xtr) & is.finite(d$time[tr])
      if (sum(oktr) < 20L) next
      cvfit <- tryCatch(.npc_fit_ridge_cox(xtr[oktr, , drop = FALSE], ytr[oktr]), error = function(e) NULL)
      if (is.null(cvfit)) next
      lp <- tryCatch(.npc_predict_lp(cvfit, xte), error = function(e) rep(NA_real_, length(te)))
      oof_sum[te] <- oof_sum[te] + lp
      oof_n[te] <- oof_n[te] + 1L
    }
  }
  lp_mean <- ifelse(oof_n > 0, oof_sum / oof_n, NA_real_)
  met <- .npc_ipcw_auc(d$time, d$cause, lp_mean, horizon = horizon)
  n_ev <- sum(d$cause == 1L, na.rm = TRUE)
  list(
    endpoint = endpoint, model = model, horizon = horizon,
    lp = lp_mean, time = d$time, cause = d$cause, row_id = keep_rows,
    auc = if (length(met$auc) == 1L) met$auc else NA_real_,
    n = nrow(d), n_event = as.integer(n_ev),
    n_repeats = n_repeats, n_folds = n_folds
  )
}

npc_ebv_pet_paired_delta <- function(oof_a, oof_b, n_boot = 800L, seed = 42L) {
  # 固定折外预测上配对重采样
  ok <- is.finite(oof_a$lp) & is.finite(oof_b$lp)
  time <- oof_a$time[ok]; cause <- oof_a$cause[ok]
  ma <- oof_a$lp[ok]; mb <- oof_b$lp[ok]
  base <- .npc_ipcw_auc(time, cause, ma, oof_a$horizon)
  alt <- .npc_ipcw_auc(time, cause, mb, oof_b$horizon)
  d0 <- alt$auc - base$auc
  set.seed(seed)
  boots <- replicate(n_boot, {
    ii <- sample.int(length(time), replace = TRUE)
    a1 <- .npc_ipcw_auc(time[ii], cause[ii], ma[ii], oof_a$horizon)$auc
    a2 <- .npc_ipcw_auc(time[ii], cause[ii], mb[ii], oof_b$horizon)$auc
    a2 - a1
  })
  boots <- boots[is.finite(boots)]
  list(
    auc_ref = base$auc, auc_new = alt$auc, delta = d0,
    lo = as.numeric(quantile(boots, 0.025, na.rm = TRUE)),
    hi = as.numeric(quantile(boots, 0.975, na.rm = TRUE)),
    n_boot = length(boots)
  )
}

npc_ebv_pet_cause_specific_hr <- function(df, endpoint = "DM", vars = c("Lnode", "Lmtv", "t0_pos", "t0_score")) {
  d <- .npc_endpoint_df(df, endpoint)
  # 调整：age male t_ord n_ord dx_year + vars
  adj <- c("age", "male", "t_ord", "n_ord", "dx_year", vars)
  d2 <- d[, c("time", "cause", adj), drop = FALSE]
  d2 <- d2[complete.cases(d2), , drop = FALSE]
  if (endpoint %in% c("DM", "LR")) {
    d2$ev <- as.integer(d2$cause == 1L)
  } else {
    d2$ev <- as.integer(d2$cause > 0)
  }
  fml <- as.formula(paste("survival::Surv(time, ev) ~", paste(adj, collapse = " + ")))
  fit <- tryCatch(survival::coxph(fml, data = d2), error = function(e) NULL)
  if (is.null(fit)) return(NULL)
  s <- summary(fit)$coefficients
  ci <- suppressMessages(exp(confint(fit)))
  out <- data.frame(
    endpoint = endpoint,
    variable = rownames(s),
    HR = exp(s[, "coef"]),
    lo = ci[, 1],
    hi = ci[, 2],
    p = s[, "Pr(>|z|)"],
    stringsAsFactors = FALSE
  )
  rownames(out) <- NULL
  out
}

npc_ebv_pet_fmt <- function(x, digits = 3) {
  ifelse(!is.finite(x), "NE", sprintf(paste0("%.", digits, "f"), x))
}
