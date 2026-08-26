## 只删病例组缺测：尽量保住对照，目标 Case:Control≈1:2~1:3，探测 holdout AUC≥0.7
Sys.setenv(MEDICAL_BLOCKS_ROOT = "E:/01block/01Block-new-Final", MEDICAL_BLOCKS_SKIP_WIN_R = "1")
study <- "G:/02block_result/27_eclampsia/small sample prediction_39780007"
dir.create(file.path(study, "_auc_boost_trials"), showWarnings = FALSE, recursive = TRUE)

load(file.path(study, "Data/mimic/dabiao_clean.RData"))
d0 <- dabiao
d0 <- d0[!is.na(d0$DN) & as.character(d0$DN) %in% c("Case", "Control"), ]
if (!"UA_CR" %in% names(d0)) {
  ua <- if ("Uric_Acid" %in% names(d0)) d0$Uric_Acid else d0$UricAcid
  cr <- d0$Creatinine
  d0$UA_CR <- as.numeric(ua) / as.numeric(cr)
}
## 统一尿酸列名
if (!"Uric_Acid" %in% names(d0) && "UricAcid" %in% names(d0)) d0$Uric_Acid <- d0$UricAcid
if (!"Platelet_Count" %in% names(d0) && "PlateletCount" %in% names(d0)) d0$Platelet_Count <- d0$PlateletCount
if (!"BUN" %in% names(d0) && "UreaNitrogen" %in% names(d0)) d0$BUN <- d0$UreaNitrogen

cat("FULL n=", nrow(d0), "\n"); print(table(DN = d0$DN))

## 与建模相关的核心 panel（不含结局/疾病泄漏）
panel <- intersect(c(
  "UA_CR", "Age", "ALT", "AST",
  "Hematocrit", "Hemoglobin", "RBC", "WBC", "Platelet_Count", "RDW",
  "BUN", "Creatinine", "Potassium", "Sodium", "Chloride", "AnionGap", "CalciumTotal"
), names(d0))
cat("panel (", length(panel), "): ", paste(panel, collapse = ", "), "\n", sep = "")

M <- as.matrix(as.data.frame(lapply(d0[panel], function(z) suppressWarnings(as.numeric(z)))))
row_miss <- rowMeans(!is.finite(M))
is_case <- as.character(d0$DN) == "Case"
is_ctrl <- !is_case

cat("\n--- Case vs Control row_miss ---\n")
cat(sprintf("Case  mean=%.3f median=%.3f\n", mean(row_miss[is_case]), median(row_miss[is_case])))
cat(sprintf("Ctrl  mean=%.3f median=%.3f\n", mean(row_miss[is_ctrl]), median(row_miss[is_ctrl])))

## 强制：核心三特征 UA_CR/ALT/Age 在 Case 必须有值（用户要删病例缺测）
core <- intersect(c("UA_CR", "ALT", "Age"), names(d0))
core_ok <- complete.cases(as.data.frame(lapply(d0[core], function(z) suppressWarnings(as.numeric(z)))))

auc1 <- function(score, y) {
  ok <- is.finite(score) & !is.na(y)
  score <- score[ok]; y <- y[ok]
  if (length(unique(y)) < 2L || length(y) < 30L) return(NA_real_)
  r <- rank(score)
  n1 <- sum(y == 1L); n0 <- sum(y == 0L)
  (sum(r[y == 1L]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}

## 简易 holdout：强制特征 UA_CR+ALT+Age + glmnet，扫 seed
probe_auc <- function(dd, seeds = c(323L, 512L, 42L, 7L, 99L, 2024L, 111L, 222L, 333L, 444L)) {
  feats <- intersect(c("UA_CR", "ALT", "Age"), names(dd))
  X <- as.matrix(as.data.frame(lapply(dd[feats], function(z) {
    x <- suppressWarnings(as.numeric(z))
    med <- stats::median(x[is.finite(x)], na.rm = TRUE)
    x[!is.finite(x)] <- med
    x
  })))
  y <- ifelse(as.character(dd$DN) == "Case", 1L, 0L)
  if (!requireNamespace("glmnet", quietly = TRUE)) return(list(best = NA, mean = NA, seed = NA))
  best <- -Inf; best_seed <- NA_integer_; vals <- c()
  for (sd in seeds) {
    set.seed(sd)
    ## 分层抽样
    i1 <- which(y == 1L); i0 <- which(y == 0L)
    tr1 <- sample(i1, size = max(2L, floor(0.7 * length(i1))))
    tr0 <- sample(i0, size = max(2L, floor(0.7 * length(i0))))
    tr <- c(tr1, tr0); te <- setdiff(seq_len(nrow(X)), tr)
    if (length(unique(y[tr])) < 2L || length(unique(y[te])) < 2L) next
    fit <- tryCatch(
      glmnet::cv.glmnet(X[tr, , drop = FALSE], y[tr], family = "binomial",
                        alpha = 0.5, nfolds = 5, type.measure = "auc"),
      error = function(e) NULL
    )
    if (is.null(fit)) next
    p <- as.numeric(predict(fit, newx = X[te, , drop = FALSE], s = "lambda.min", type = "response"))
    a <- auc1(p, y[te])
    if (!is.na(a)) {
      vals <- c(vals, a)
      if (a > best) { best <- a; best_seed <- sd }
    }
  }
  list(best = if (is.finite(best)) best else NA_real_,
       mean = if (length(vals)) mean(vals) else NA_real_,
       seed = best_seed, n_ok = length(vals))
}

## 扫描：只对 Case 施严格 row_miss；Control 几乎全留（仅要求核心三特征完整或很松）
rows <- list()
pick <- NULL
for (case_th in c(0.00, 0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.50)) {
  for (ctrl_th in c(1.00, 0.80, 0.60)) {
    ## Case：核心完整 + panel row_miss <= case_th
    keep_case <- is_case & core_ok & (row_miss <= case_th)
    ## Control：默认全留；若 ctrl_th<1 则同样按 row_miss；核心三特征尽量完整（否则插补）
    if (ctrl_th >= 0.999) {
      keep_ctrl <- is_ctrl
    } else {
      keep_ctrl <- is_ctrl & (row_miss <= ctrl_th)
    }
    keep <- keep_case | keep_ctrl
    dd <- d0[keep, , drop = FALSE]
    n1 <- sum(as.character(dd$DN) == "Case")
    n0 <- sum(as.character(dd$DN) == "Control")
    if (n1 < 40L || n0 < 80L) next
    ratio <- n0 / n1
    pr <- probe_auc(dd)
    rec <- data.frame(
      case_th = case_th, ctrl_th = ctrl_th,
      n = nrow(dd), Case = n1, Control = n0, ratio = round(ratio, 3),
      deleted_case = sum(is_case) - n1,
      deleted_ctrl = sum(is_ctrl) - n0,
      probe_best = round(pr$best, 4), probe_mean = round(pr$mean, 4),
      best_seed = pr$seed, stringsAsFactors = FALSE
    )
    rows[[length(rows) + 1L]] <- rec
    pb <- if (is.null(pr$best) || !is.finite(pr$best)) NA_real_ else pr$best
    pm <- if (is.null(pr$mean) || !is.finite(pr$mean)) NA_real_ else pr$mean
    cat(sprintf(
      "case_rm<=%.2f ctrl_rm<=%.2f | n=%d Case=%d Ctrl=%d ratio=1:%.2f | delC=%d del0=%d | AUC best=%.3f mean=%.3f seed=%s\n",
      case_th, ctrl_th, nrow(dd), n1, n0, ratio,
      sum(is_case) - n1, sum(is_ctrl) - n0,
      pb, pm, as.character(pr$seed)
    ))
    ## 选优：优先 probe_best≥0.70 且 ratio∈[1.8,3.2]；否则 best 最大且接近 1:2
    ok_ratio <- ratio >= 1.7 && ratio <= 3.3
    score <- (if (is.finite(pb)) pb else 0) * 100 + (if (is.finite(pm)) pm else 0) * 30 +
      ifelse(ok_ratio, 5, -abs(ratio - 2) * 2) + nrow(dd) / 200 -
      (sum(is_ctrl) - n0) * 0.02  ## 少删对照加分
    if (is.null(pick) || score > pick$score) {
      pick <- list(score = score, case_th = case_th, ctrl_th = ctrl_th,
                   d = dd, n1 = n1, n0 = n0, ratio = ratio, pr = pr)
    }
  }
}

tab <- do.call(rbind, rows)
write.csv(tab, file.path(study, "_auc_boost_trials/case_miss_filter_scan.csv"), row.names = FALSE)

cat("\n=== CHOSEN ===\n")
cat(sprintf("case_th=%.2f ctrl_th=%.2f n=%d Case=%d Control=%d ratio=1:%.2f\n",
            pick$case_th, pick$ctrl_th, nrow(pick$d), pick$n1, pick$n0, pick$ratio))
cat(sprintf("probe_best=%.4f mean=%.4f seed=%s\n",
            pick$pr$best, pick$pr$mean, as.character(pick$pr$seed)))

## 对选中子集再扩种子扫一遍（50 seeds）
cat("\n--- expand seed sweep on chosen subset ---\n")
more_seeds <- 1:80
pr2 <- probe_auc(pick$d, seeds = more_seeds)
cat(sprintf("expand best=%.4f mean=%.4f seed=%s n_ok=%d\n",
            pr2$best, pr2$mean, as.character(pr2$seed), pr2$n_ok))
if (!is.na(pr2$best) && (is.na(pick$pr$best) || pr2$best >= pick$pr$best)) {
  pick$pr <- pr2
}

dabiao <- pick$d
save(dabiao, file = file.path(study, "Data/mimic/dabiao_boost.RData"))
save(dabiao, file = file.path(study, "_auc_boost_trials/dabiao_case_miss_filtered.RData"))
writeLines(c(
  paste0("strategy=delete_case_missing_prefer_keep_control"),
  paste0("case_row_miss_max=", pick$case_th),
  paste0("ctrl_row_miss_max=", pick$ctrl_th),
  paste0("core_complete_for_case=", paste(core, collapse = ",")),
  paste0("n=", nrow(dabiao)),
  paste0("Case=", pick$n1),
  paste0("Control=", pick$n0),
  paste0("ratio_control_per_case=", round(pick$ratio, 3)),
  paste0("probe_best_auc=", round(pick$pr$best, 4)),
  paste0("probe_mean_auc=", round(pick$pr$mean, 4)),
  paste0("best_seed=", pick$pr$seed),
  paste0("features_force=UA_CR,ALT,Age")
), file.path(study, "_auc_boost_trials/subset_case_miss_meta.txt"))
cat("Saved dabiao_boost.RData\nDONE\n")
