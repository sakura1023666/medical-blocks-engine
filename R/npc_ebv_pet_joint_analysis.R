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
    # 生物学复发等口径 A 字段并入（按 PID；无 PID 则按行序谨慎跳过）
    if ("PID" %in% names(b)) {
      a_extra <- intersect(
        c("PID", "生物学复发", "BioRelapse", "BioRelapse_time", "BioRelapse_date_known",
          "轨迹_Robust", "TRAJ_NEW", "TRAJ_RISK", "Joint_Group", "RiskScore", "RiskTertile",
          "联合免疫", "IC", "HBsAg_pos", "Stage_num", "Stage_grp", "分期", "EBV_high",
          "EBV_AUC_log", "EBV_T2_residual", "EBV_LogDrop", "EBV_ClearPct",
          "ClinicalRelapse", "PFS_event", "PFS_time"),
        names(a)
      )
      if (length(a_extra) > 1L) {
        ae <- a[, a_extra, drop = FALSE]
        # 避免重复列名覆盖：只补 b 缺失列
        add_cols <- setdiff(names(ae), c("PID", names(b)))
        if (length(add_cols)) {
          b <- merge(b, ae[, c("PID", add_cols), drop = FALSE], by = "PID", all.x = TRUE, sort = FALSE)
        }
        if (!"生物学复发" %in% names(b) && "生物学复发" %in% names(ae)) {
          b <- merge(b, ae[, c("PID", "生物学复发"), drop = FALSE], by = "PID", all.x = TRUE, sort = FALSE)
        }
        if (!"BioRelapse" %in% names(b) && "BioRelapse" %in% names(ae)) {
          b <- merge(b, ae[, c("PID", "BioRelapse", intersect("BioRelapse_time", names(ae))), drop = FALSE],
                     by = "PID", all.x = TRUE, sort = FALSE)
        }
      }
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
  b$Lsuv_p <- log2(1 + pmax(b$suv_p, 0, na.rm = FALSE))
  if ("suvmean_p" %in% names(b)) {
    b$Lsuvmean_p <- log2(1 + pmax(num(b$suvmean_p), 0, na.rm = FALSE))
  } else {
    b$Lsuvmean_p <- b$Lsuv_p
  }
  # 原始定量 / 左删失上界
  if ("T0定量" %in% names(b)) b$t0_raw <- num(b[["T0定量"]])
  if ("T1定量" %in% names(b)) b$t1_raw <- num(b[["T1定量"]])
  if ("T2定量" %in% names(b)) b$t2_raw <- num(b[["T2定量"]])
  if ("T0左删失上界" %in% names(b)) b$t0_ub <- num(b[["T0左删失上界"]])
  if ("T1左删失上界" %in% names(b)) b$t1_ub <- num(b[["T1左删失上界"]])
  if ("T2左删失上界" %in% names(b)) b$t2_ub <- num(b[["T2左删失上界"]])
  if ("T0定量>0" %in% names(b)) b$t0_anypos <- as.integer(num(b[["T0定量>0"]]) == 1)
  if ("TLG公式核查值" %in% names(b)) b$tlg_formula <- num(b[["TLG公式核查值"]])
  if ("TLG差>5%" %in% names(b)) b$tlg_flag <- as.integer(num(b[["TLG差>5%"]]) == 1)
  # IC 标记
  if ("ic_code" %in% names(b)) {
    b$ic <- as.integer(!(is.na(b$ic_code) | as.character(b$ic_code) %in% c("0", "无", "否", "")))
  }
  if ("IC 9月界标" %in% names(b)) b$ic_lm9 <- as.integer(num(b[["IC 9月界标"]]) == 1)

  # 累积负荷 / 时点差（若表内已有则保留数值化）
  if ("T1−T0分数" %in% names(b)) b$t1_minus_t0 <- num(b[["T1−T0分数"]])
  if ("T2−T0分数" %in% names(b)) b$t2_minus_t0 <- num(b[["T2−T0分数"]])
  # 梯形积分：假定 T0=0、T1=2、T2=4 月（报告口径 A 代理）
  b$cum_trap <- ifelse(
    is.finite(b$t1_score),
    b$t0_score + 2 * b$t1_score + b$t2_score,
    2 * (b$t0_score + b$t2_score)
  )
  b$cum_ebv <- b$cum_trap
  b$t2_resid <- b$t2_score
  b$log_drop <- b$t0_score - b$t2_score
  # BLQ=LOD/2 分数（敏感性）
  b$t0_score_half <- ifelse(
    !is.na(b$t0_kind) & grepl("左删失|BLQ", as.character(b$t0_kind)),
    log10(1 + 0.5),  # rel=0.5 → log10(1.5)≈0.176；报告写 log_half=0.176
    b$t0_score
  )
  # 左删失上界进入相对编码（保留上界信息）
  b$t0_ub_score <- ifelse(
    is.finite(b$t0_ub) & is.finite(b$lod) & b$lod > 0,
    log10(1 + pmax(b$t0_ub, 0) / b$lod),
    NA_real_
  )
  b$t0_score_with_ub <- ifelse(
    !is.na(b$t0_kind) & grepl("左删失|BLQ", as.character(b$t0_kind)) & is.finite(b$t0_ub_score),
    b$t0_ub_score,
    b$t0_score
  )
  # 报告四象限：PET 高危 = TLG>65 g 或 NTR>0.64（与工作簿 Joint_Group 一致）
  b$tlg_high <- as.integer(is.finite(b$tlg) & b$tlg > 65)
  b$ntr_high <- as.integer(is.finite(b$ntr) & b$ntr > 0.64)
  b$pet_high <- as.integer(b$tlg_high == 1L | b$ntr_high == 1L)
  # EBV 高危：优先用工作簿 EBV_high（与 Joint_Group 同源）；否则 = 达阈/T2/持续|反弹
  if ("EBV_high" %in% names(b)) {
    b$ebv_high <- as.integer(num(b$EBV_high) == 1L)
  } else {
    traj_chr <- as.character(if ("traj" %in% names(b)) b$traj else NA)
    persist_rebound <- grepl("Persistent|Rebound|持续|反弹", traj_chr, ignore.case = TRUE)
    b$ebv_high <- as.integer(b$t0_pos == 1L | b$t2_pos == 1L | persist_rebound)
  }
  # 分期序数（口径 A M0 用 Stage，不用拆开的 T/N）
  if ("Stage_num" %in% names(b)) {
    b$stage_num <- num(b$Stage_num)
  } else if ("ajcc8" %in% names(b)) {
    b$stage_num <- as.integer(factor(as.character(b$ajcc8), levels = c("I", "II", "III", "IVA", "IVB")))
  }
  if (!"stage_num" %in% names(b) || all(is.na(b$stage_num))) {
    b$stage_num <- b$t_ord # 兜底
  }
  # 生物学复发（口径 A 合并后可能已有）
  if ("生物学复发" %in% names(b)) b$bio_relapse <- as.integer(num(b[["生物学复发"]]) == 1)
  if ("BioRelapse" %in% names(b) && !"bio_relapse" %in% names(b)) {
    b$bio_relapse <- as.integer(num(b$BioRelapse) == 1)
  }
  if ("BioRelapse_time" %in% names(b)) b$bio_time <- num(b$BioRelapse_time)
  # 联合免疫 / IC（口径 A：诱导化疗 + 免疫）
  if ("联合免疫" %in% names(b)) {
    b$immuno <- as.integer(num(b[["联合免疫"]]) == 1L | as.character(b[["联合免疫"]]) %in% c("1", "是", "Yes", "Y"))
  } else {
    b$immuno <- NA_integer_
  }
  if ("IC" %in% names(b) && !"ic_a" %in% names(b)) {
    b$ic_a <- as.integer(num(b$IC) == 1L)
  }
  if (!"ic_a" %in% names(b)) b$ic_a <- as.integer(num(b$ic) == 1L | num(b$ic_code) == 1L)
  if ("HBsAg_pos" %in% names(b) && !"hbsag_pos" %in% names(b)) {
    b$hbsag_pos <- as.integer(num(b$HBsAg_pos) == 1L)
  }
  if (!"hbsag_pos" %in% names(b)) {
    b$hbsag_pos <- as.integer(grepl("阳|pos|1", as.character(b$hbsag), ignore.case = TRUE))
  }
  if ("原稳健轨迹" %in% names(b) && !"traj_robust" %in% names(b)) {
    b$traj_robust <- as.character(b[["原稳健轨迹"]])
  }
  # 四象限一律按报告阈值重算（覆盖工作簿旧分层，保证 TLG/NTR 定义一致）
  b$quadrant <- ifelse(b$ebv_high == 0 & b$pet_high == 0, "双低",
                ifelse(b$ebv_high == 1 & b$pet_high == 0, "仅EBV高",
                ifelse(b$ebv_high == 0 & b$pet_high == 1, "仅PET高", "双高")))

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

.npc_model_vars <- function(spec = c("C", "E", "P2", "P6", "EP2", "EP6", "EP2X")) {
  spec <- match.arg(spec)
  base <- c("age", "male", "t_ord", "n_ord", "dx_year")
  # LOD 作因子：在矩阵里展开
  e <- c("t0_pos", "t0_score")
  p2 <- c("Lmtv", "Lnode")
  # P6：原发 MTV/TLG/SUVmax + 淋巴结 SUVmax + NTR（与工作簿参数个数对齐）
  p6 <- c("Lmtv", "Lnode", "Ltlg", "Lntr", "Lsuv_p", "Lsuvmean_p")
  # EP2X：联合 + EBV×PET 交互（t0_score × Lnode）
  switch(spec,
    C = base,
    E = c(base, e),
    P2 = c(base, p2),
    P6 = c(base, p6),
    EP2 = c(base, e, p2),
    EP6 = c(base, e, p6),
    EP2X = c(base, e, p2, "ebv_pet_x")
  )
}

.npc_design_matrix <- function(df, vars) {
  # LOD 类别并入临床模型
  d <- df
  if (!"lod_cat" %in% names(d)) d$lod_cat <- factor(d$lod)
  if ("ebv_pet_x" %in% vars && !"ebv_pet_x" %in% names(d)) {
    d$ebv_pet_x <- as.numeric(d$t0_score) * as.numeric(d$Lnode)
  }
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

# 报告惩罚：口径 A λ=0.03；口径 B 为 (5/2)·Σβ_std² ≡ glmnet ridge standardize 下 λ=5
npc_ebv_pet_penalty_lambda <- function(cohort = c("B", "A")) {
  cohort <- match.arg(cohort)
  if (identical(cohort, "A")) 0.03 else 5
}

.npc_fit_ridge_cox <- function(x, y_surv, alpha = 0, lambda = NULL) {
  # y_surv: Surv object; for competing risk cause-specific, treat cause!=1 as censored
  # 报告规格：Breslow 结点；固定 lambda 时不做 CV
  if (!is.null(lambda) && is.finite(lambda)) {
    fit <- glmnet::glmnet(
      x = x, y = y_surv, family = "cox", alpha = alpha,
      lambda = lambda, standardize = TRUE, cox.ties = "breslow"
    )
    attr(fit, "fixed_lambda") <- lambda
    return(fit)
  }
  fit <- glmnet::cv.glmnet(
    x = x, y = y_surv, family = "cox", alpha = alpha,
    nfolds = min(5L, max(3L, nrow(x) %/% 10L)),
    type.measure = "deviance", standardize = TRUE, cox.ties = "breslow"
  )
  fit
}

.npc_predict_lp <- function(cvfit, xnew) {
  if (!is.null(attr(cvfit, "fixed_lambda"))) {
    return(as.numeric(predict(cvfit, newx = xnew, s = attr(cvfit, "fixed_lambda"), type = "link")))
  }
  as.numeric(predict(cvfit, newx = xnew, s = "lambda.min", type = "link"))
}

# Harrell C-index（原因特异：竞争事件作删失）
# survival::concordance 默认「标记越高 → 生存越长」；Cox LP/风险分越高 → 风险越高，故对标记取负
.npc_harrell_c <- function(time, cause, marker, primary_cause = 1L, risk_score = TRUE) {
  ok <- is.finite(time) & is.finite(marker) & !is.na(cause)
  time <- time[ok]; cause <- as.integer(cause[ok]); marker <- marker[ok]
  ev <- as.integer(cause == primary_cause)
  if (sum(ev) < 5L) return(NA_real_)
  s <- survival::Surv(time, ev)
  x <- if (isTRUE(risk_score)) -marker else marker
  as.numeric(survival::concordance(s ~ x)$concordance)
}

# Bootstrap 乐观校正 C-index（全流程：重抽样拟合 → 表观 − 乐观）
npc_ebv_pet_boot_cindex <- function(df, endpoint = "DM", model = "EP2",
                                    n_boot = 200L, seed = 2026L, lambda = NULL) {
  d0 <- .npc_endpoint_df(df, endpoint)
  rownames(d0) <- as.character(seq_len(nrow(d0)))
  vars <- .npc_model_vars(model)
  mm <- tryCatch(.npc_design_matrix(d0, vars), error = function(e) NULL)
  if (is.null(mm)) return(NULL)
  keep <- as.integer(rownames(mm))
  d <- d0[keep, , drop = FALSE]
  x <- mm; rownames(x) <- NULL
  if (endpoint %in% c("DM", "LR")) {
    ev <- as.integer(d$cause == 1L)
  } else {
    ev <- as.integer(d$cause > 0)
  }
  y <- survival::Surv(d$time, ev)
  fit0 <- tryCatch(.npc_fit_ridge_cox(x, y, lambda = lambda), error = function(e) NULL)
  if (is.null(fit0)) return(NULL)
  lp0 <- .npc_predict_lp(fit0, x)
  c_app <- .npc_harrell_c(d$time, d$cause, lp0)
  set.seed(seed)
  opt <- replicate(n_boot, {
    ii <- sample.int(nrow(d), replace = TRUE)
    xb <- x[ii, , drop = FALSE]
    yb <- y[ii]
    fitb <- tryCatch(.npc_fit_ridge_cox(xb, yb, lambda = lambda), error = function(e) NULL)
    if (is.null(fitb)) return(c(NA_real_, NA_real_))
    lp_b <- .npc_predict_lp(fitb, xb)
    lp_o <- .npc_predict_lp(fitb, x)
    c_b <- .npc_harrell_c(d$time[ii], d$cause[ii], lp_b)
    c_o <- .npc_harrell_c(d$time, d$cause, lp_o)
    c(c_b, c_o)
  })
  if (is.null(dim(opt))) opt <- matrix(opt, nrow = 2L)
  c_boot <- opt[1, ]; c_orig <- opt[2, ]
  ok <- is.finite(c_boot) & is.finite(c_orig)
  optimism <- mean(c_boot[ok] - c_orig[ok], na.rm = TRUE)
  data.frame(
    endpoint = endpoint, model = model,
    C_apparent = c_app,
    optimism = optimism,
    C_corrected = c_app - optimism,
    n_boot = sum(ok),
    stringsAsFactors = FALSE
  )
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
  br <- tryCatch(
    .npc_ipcw_brier(time, cause, marker, horizon, primary_cause),
    error = function(e) NA_real_
  )
  list(
    auc = if (length(auc) == 1L && is.finite(auc)) auc else NA_real_,
    brier = br,
    n = length(time),
    n_event = sum(st == as.integer(primary_cause), na.rm = TRUE)
  )
}

npc_ebv_pet_oof_cv <- function(df, endpoint = "DM", model = "EP2",
                               n_repeats = 8L, n_folds = 5L, seed = 20261117L,
                               horizon = 36, lambda = NULL, vars = NULL) {
  d0 <- .npc_endpoint_df(df, endpoint)
  rownames(d0) <- as.character(seq_len(nrow(d0)))
  if (is.null(vars)) vars <- .npc_model_vars(model)
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
      cvfit <- tryCatch(
        .npc_fit_ridge_cox(xtr[oktr, , drop = FALSE], ytr[oktr], lambda = lambda),
        error = function(e) NULL
      )
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
    brier = if (length(met$brier) == 1L) met$brier else NA_real_,
    n = nrow(d), n_event = as.integer(n_ev),
    lambda = if (is.null(lambda)) NA_real_ else as.numeric(lambda),
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

# ---- IPCW Brier（简化：按 horizon 二元结局 + 逆概率删失权重近似）----
.npc_ipcw_brier <- function(time, cause, marker, horizon = 36, primary_cause = 1L) {
  ok <- is.finite(time) & is.finite(marker) & !is.na(cause)
  time <- time[ok]; cause <- as.integer(cause[ok]); marker <- marker[ok]
  if (length(time) < 30L) return(NA_real_)
  r <- rank(marker) / length(marker)
  inc <- mean(cause == primary_cause & time <= horizon, na.rm = TRUE)
  risk <- pmin(pmax(r * (2 * inc), 1e-4), 0.99)
  known <- (cause == primary_cause & time <= horizon) | (time >= horizon) |
    (cause != primary_cause & cause != 0L & time <= horizon)
  if (sum(known, na.rm = TRUE) < 20L) return(NA_real_)
  y <- as.integer(cause == primary_cause & time <= horizon)
  ev_censor <- as.integer(cause == 0L)
  sf <- tryCatch(survival::survfit(survival::Surv(time, ev_censor) ~ 1), error = function(e) NULL)
  w <- rep(1, length(time))
  if (!is.null(sf)) {
    gt <- approx(sf$time, sf$surv, xout = pmin(time, horizon), rule = 2, yleft = 1, yright = min(sf$surv))$y
    w <- 1 / pmax(gt, 0.05)
  }
  w[!known] <- 0
  w <- w / mean(w[known])
  mean(w * (y - risk)^2, na.rm = TRUE)
}

npc_ebv_pet_paired_delta_full <- function(oof_a, oof_b, n_boot = 400L, seed = 42L) {
  ok <- is.finite(oof_a$lp) & is.finite(oof_b$lp)
  time <- oof_a$time[ok]; cause <- oof_a$cause[ok]
  ma <- oof_a$lp[ok]; mb <- oof_b$lp[ok]
  hor <- oof_a$horizon %||% 36
  base_a <- .npc_ipcw_auc(time, cause, ma, hor)
  alt_a <- .npc_ipcw_auc(time, cause, mb, hor)
  set.seed(seed)
  boots <- replicate(n_boot, {
    ii <- sample.int(length(time), replace = TRUE)
    a1 <- .npc_ipcw_auc(time[ii], cause[ii], ma[ii], hor)
    a2 <- .npc_ipcw_auc(time[ii], cause[ii], mb[ii], hor)
    c(a2$auc - a1$auc, a2$brier - a1$brier)
  })
  if (is.null(dim(boots))) boots <- matrix(boots, nrow = 2L)
  da <- boots[1, ]; db <- boots[2, ]
  da <- da[is.finite(da)]; db <- db[is.finite(db)]
  list(
    auc_ref = base_a$auc, auc_new = alt_a$auc,
    delta_auc = alt_a$auc - base_a$auc,
    auc_lo = as.numeric(quantile(da, 0.025, na.rm = TRUE)),
    auc_hi = as.numeric(quantile(da, 0.975, na.rm = TRUE)),
    brier_ref = base_a$brier, brier_new = alt_a$brier,
    delta_brier = alt_a$brier - base_a$brier,
    brier_lo = as.numeric(quantile(db, 0.025, na.rm = TRUE)),
    brier_hi = as.numeric(quantile(db, 0.975, na.rm = TRUE))
  )
}

# 嵌套似然比：全样本 ridge 不可直接 LR；用未惩罚 Cox 同变量集
npc_ebv_pet_nested_lr <- function(df, endpoint = "DM",
                                  vars_small, vars_large) {
  d <- .npc_endpoint_df(df, endpoint)
  if (endpoint %in% c("DM", "LR")) d$ev <- as.integer(d$cause == 1L) else d$ev <- as.integer(d$cause > 0)
  vs <- unique(c("age", "male", "t_ord", "n_ord", "dx_year", vars_small))
  vl <- unique(c(vs, vars_large))
  cols <- unique(c("time", "ev", vs, vl))
  d2 <- d[, intersect(cols, names(d)), drop = FALSE]
  d2 <- d2[complete.cases(d2), , drop = FALSE]
  if (nrow(d2) < 50L) return(NULL)
  f0 <- as.formula(paste("Surv(time, ev) ~", paste(vs, collapse = "+")))
  f1 <- as.formula(paste("Surv(time, ev) ~", paste(vl, collapse = "+")))
  m0 <- tryCatch(survival::coxph(f0, data = d2), error = function(e) NULL)
  m1 <- tryCatch(survival::coxph(f1, data = d2), error = function(e) NULL)
  if (is.null(m0) || is.null(m1)) return(NULL)
  an <- tryCatch(anova(m0, m1, test = "Chisq"), error = function(e) NULL)
  if (is.null(an)) return(NULL)
  data.frame(
    endpoint = endpoint,
    model_small = paste(vars_small, collapse = "+"),
    model_large = paste(setdiff(vl, vs), collapse = "+"),
    n = nrow(d2),
    LR_chisq = as.numeric(an$Chisq[2]),
    df = as.numeric(an$Df[2]),
    p = as.numeric(an$`Pr(>|Chi|)`[2]),
    stringsAsFactors = FALSE
  )
}

# Fine–Gray / 原因特异 + CIF 绝对风险表
npc_ebv_pet_cif_table <- function(df, endpoint = "DM", times = c(12, 24, 36, 48, 60)) {
  d <- .npc_endpoint_df(df, endpoint)
  if (!requireNamespace("cmprsk", quietly = TRUE)) return(NULL)
  cif <- tryCatch(cmprsk::cuminc(ftime = d$time, fstatus = d$cause, cencode = 0), error = function(e) NULL)
  if (is.null(cif)) return(NULL)
  # names like "1 1" / "1 2"
  nm <- names(cif)
  nm <- nm[nm != "Tests"]
  rows <- list()
  for (n1 in nm) {
    tr <- cif[[n1]]
    cause_lab <- if (grepl("1$", n1) || grepl(" 1$", n1)) "primary" else "competing"
    for (tt in times) {
      # last estimate at or before tt
      idx <- which(tr$time <= tt)
      est <- if (length(idx)) tr$est[max(idx)] else NA_real_
      var <- if (length(idx) && !is.null(tr$var)) tr$var[max(idx)] else NA_real_
      se <- if (is.finite(var)) sqrt(var) else NA_real_
      rows[[length(rows) + 1L]] <- data.frame(
        Endpoint = endpoint, Cause = cause_lab, Time_mo = tt,
        CIF = est, SE = se,
        CI_low = if (is.finite(est) && is.finite(se)) pmax(0, est - 1.96 * se) else NA_real_,
        CI_high = if (is.finite(est) && is.finite(se)) pmin(1, est + 1.96 * se) else NA_real_,
        stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, rows)
}

npc_ebv_pet_finegray_hr <- function(df, endpoint = "DM",
                                    vars = c("Lnode", "Lmtv", "t0_pos", "t0_score")) {
  if (!requireNamespace("cmprsk", quietly = TRUE)) return(NULL)
  d <- .npc_endpoint_df(df, endpoint)
  adj <- c("age", "male", "t_ord", "n_ord", "dx_year", vars)
  d2 <- d[, c("time", "cause", adj), drop = FALSE]
  d2 <- d2[complete.cases(d2), , drop = FALSE]
  if (nrow(d2) < 50L) return(NULL)
  # crr cov1 matrix
  x <- as.matrix(d2[, adj, drop = FALSE])
  fit <- tryCatch(
    cmprsk::crr(ftime = d2$time, fstatus = d2$cause, cov1 = x, failcode = 1, cencode = 0),
    error = function(e) NULL
  )
  if (is.null(fit)) return(NULL)
  co <- fit$coef; se <- sqrt(diag(fit$var))
  data.frame(
    endpoint = endpoint,
    variable = names(co),
    HR = exp(co),
    lo = exp(co - 1.96 * se),
    hi = exp(co + 1.96 * se),
    p = 2 * pnorm(-abs(co / se)),
    stringsAsFactors = FALSE
  )
}

# 偏 Spearman：先对协变量残差化再相关
npc_ebv_pet_partial_spearman <- function(df, xvars, yvars, adjust = c("age", "male", "t_ord", "n_ord", "lod")) {
  adj <- intersect(adjust, names(df))
  resids <- function(v) {
    d <- df[, c(v, adj), drop = FALSE]
    d <- d[complete.cases(d), , drop = FALSE]
    if (nrow(d) < 30L) return(NULL)
    # rank then residualize
    d[[v]] <- rank(d[[v]])
    for (a in adj) d[[a]] <- rank(d[[a]])
    fml <- as.formula(paste(v, "~", paste(adj, collapse = "+")))
    fit <- lm(fml, data = d)
    data.frame(row = as.integer(rownames(d)), r = residuals(fit))
  }
  rows <- list()
  for (xv in xvars) {
    rx <- resids(xv); if (is.null(rx)) next
    for (yv in yvars) {
      ry <- resids(yv); if (is.null(ry)) next
      m <- merge(rx, ry, by = "row", suffixes = c(".x", ".y"))
      if (nrow(m) < 30L) next
      ct <- suppressWarnings(cor.test(m$r.x, m$r.y, method = "spearman", exact = FALSE))
      rows[[length(rows) + 1L]] <- data.frame(
        X = xv, Y = yv, rho = unname(ct$estimate), p = ct$p.value, n = nrow(m),
        stringsAsFactors = FALSE
      )
    }
  }
  out <- do.call(rbind, rows)
  if (is.null(out) || !nrow(out)) return(out)
  out$q <- p.adjust(out$p, method = "BH")
  out
}

# 口径 A：M0–M4 表观 AUC（Cox + IPCW）
npc_ebv_pet_m01234_apparent <- function(dfA, endpoint = "DM", horizon = 36) {
  d0 <- .npc_endpoint_df(dfA, endpoint)
  rownames(d0) <- as.character(seq_len(nrow(d0)))
  if (!"traj_mid" %in% names(d0) && "traj_risk" %in% names(d0)) {
    tr <- as.character(d0$traj_risk)
    d0$traj_mid <- as.integer(tr %in% c("中危", "中"))
    d0$traj_high <- as.integer(tr %in% c("高危", "高"))
  }
  if (!"cum_trap" %in% names(d0)) d0$cum_trap <- d0$cum_ebv
  if (!"t2_resid" %in% names(d0)) d0$t2_resid <- d0$t2_score
  # M0：Age+Sex+Stage + 诱导化疗 + 联合免疫（报告口径 A；Stage 用 stage_num）
  if (!"ic_a" %in% names(d0)) d0$ic_a <- as.integer(d0$ic %in% 1L | d0$ic_code %in% 1L)
  if (!"immuno" %in% names(d0)) d0$immuno <- 0L
  if (!"stage_num" %in% names(d0)) {
    d0$stage_num <- if ("ajcc8" %in% names(d0)) {
      as.integer(factor(as.character(d0$ajcc8), levels = c("I", "II", "III", "IVA", "IVB")))
    } else d0$t_ord
  }
  d0$ic_a <- as.integer(d0$ic_a %in% 1L)
  d0$immuno <- as.integer(d0$immuno %in% 1L)
  specs <- list(
    M0 = c("age", "male", "stage_num", "ic_a", "immuno"),
    M1 = c("age", "male", "stage_num", "ic_a", "immuno", "cum_trap", "t2_resid", "traj_mid", "traj_high"),
    M2 = c("age", "male", "stage_num", "ic_a", "immuno", "Lnode", "Ltlg", "Lntr"),
    M3 = c("age", "male", "stage_num", "ic_a", "immuno", "cum_trap", "t2_resid", "traj_mid", "traj_high", "Lnode", "Ltlg", "Lntr"),
    M4 = c("age", "male", "stage_num", "ic_a", "immuno", "cum_trap", "t2_resid", "traj_mid", "traj_high", "Lnode", "Ltlg", "Lntr", "ebv_high", "pet_high")
  )
  # M4 interaction: add product column
  d0$ebv_pet <- as.numeric(d0$ebv_high) * as.numeric(d0$pet_high)
  specs$M4 <- c(specs$M4, "ebv_pet")
  rows <- list()
  for (nm in names(specs)) {
    vars <- intersect(specs[[nm]], names(d0))
    mm <- tryCatch({
      fml <- as.formula(paste("~", paste(vars, collapse = "+"), "-1"))
      model.matrix(fml, data = d0)
    }, error = function(e) NULL)
    if (is.null(mm) || nrow(mm) < 50) next
    keep <- as.integer(rownames(mm))
    ev <- if (endpoint %in% c("DM", "LR")) as.integer(d0$cause[keep] == 1L) else as.integer(d0$cause[keep] > 0)
    fit <- tryCatch(.npc_fit_ridge_cox(mm, survival::Surv(d0$time[keep], ev)), error = function(e) NULL)
    if (is.null(fit)) next
    lp <- .npc_predict_lp(fit, mm)
    met <- .npc_ipcw_auc(d0$time[keep], d0$cause[keep], lp, horizon)
    rows[[length(rows) + 1L]] <- data.frame(
      Cohort = "A", Endpoint = endpoint, Model = nm, N = length(keep),
      AUC = round(met$auc, 3), Brier = round(met$brier, 4),
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

`%||%` <- function(a, b) if (!is.null(a) && length(a) && !is.na(a)[1]) a else b
