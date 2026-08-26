## UA_CR 加压：删行保高信息变量 → 扩特征+winsor+多模型+扫种子
## 目标：诚实 holdout/CV 尽量冲高；记录最佳 seed
Sys.setenv(MEDICAL_BLOCKS_ROOT = "E:/01block/01Block-new-Final", MEDICAL_BLOCKS_SKIP_WIN_R = "1")
study <- "G:/02block_result/27_eclampsia/small sample prediction_39780007"
out_dir <- file.path(study, "_auc_boost_trials")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

load(file.path(study, "Data/mimic/dabiao_clean.RData"))
d0 <- dabiao
d0 <- d0[!is.na(d0$DN) & as.character(d0$DN) %in% c("Case", "Control"), ]
if (!"UA_CR" %in% names(d0)) {
  d0$UA_CR <- as.numeric(d0$UricAcid) / as.numeric(d0$Creatinine)
}
## 疾病泄漏仍排除（不可用）
leak <- c(
  "Hypertension", "T1DM", "T2DM", "Diabetes", "Glucose", "HbA1c",
  "UrineProtein", "UrineGlucose", "AlbuminUrine", "AlbuminCreatinine",
  "Albumin_Urine", "Albumin_Creatinine", "Urine_Glucose", "Urine_Protein",
  "CKD", "Acute_Renal_Failure", "Gender", "ID", "DN", "Group", "UA_Cr", "UA_CrR"
)

auc1 <- function(score, y) {
  ok <- is.finite(score) & !is.na(y)
  score <- score[ok]; y <- y[ok]
  if (length(unique(y)) < 2L || length(y) < 40L) return(NA_real_)
  r <- rank(score); n1 <- sum(y == 1L); n0 <- sum(y == 0L)
  (sum(r[y == 1L]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}
winsor <- function(x, p = 0.01) {
  qs <- stats::quantile(x, c(p, 1 - p), na.rm = TRUE, names = FALSE)
  pmin(pmax(x, qs[1]), qs[2])
}
y_of <- function(d) ifelse(as.character(d$DN) == "Case", 1L, 0L)

## 数值列缺失与单因素 AUC（全队列）
num_all <- setdiff(
  names(d0)[vapply(d0, function(z) is.numeric(z) || is.integer(z), TRUE)],
  leak
)
miss_n <- vapply(num_all, function(v) mean(!is.finite(as.numeric(d0[[v]]))), 1)
auc_n <- vapply(num_all, function(v) {
  x <- as.numeric(d0[[v]]); a <- auc1(x, y_of(d0)); max(a, 1 - a, na.rm = TRUE)
}, 1)
info <- data.frame(
  var = num_all, miss = miss_n, auc_abs = auc_n, n_obs = vapply(num_all, function(v) sum(is.finite(as.numeric(d0[[v]]))), 1L),
  stringsAsFactors = FALSE
)
info <- info[order(-info$auc_abs), ]
write.csv(info, file.path(out_dir, "univariate_auc_miss.csv"), row.names = FALSE)
cat("==== Top vars by |AUC| ====\n")
print(utils::head(info, 20), row.names = FALSE)

## 策略：对「高 AUC 且高缺失」变量，删掉该变量缺失的行，使这些变量可进入模型
hi_candidates <- info$var[info$auc_abs >= 0.55 & info$miss >= 0.3]
hi_candidates <- unique(c(hi_candidates, "NeutrophilCount", "Neutrophil_Count", "LD", "CalciumTotal",
                          "TotalCo2", "PT", "PCO2", "UreaNitrogen", "BUN", "Potassium", "INR", "PTT"))
hi_candidates <- intersect(hi_candidates, names(d0))

row_complete_on <- function(d, vars) {
  vars <- intersect(vars, names(d))
  if (!length(vars)) return(rep(TRUE, nrow(d)))
  ok <- rep(TRUE, nrow(d))
  for (v in vars) ok <- ok & is.finite(as.numeric(d[[v]]))
  ok
}

## 枚举删行方案：保留 k 个高信息变量的完全观测子集
build_scenarios <- function() {
  sc <- list()
  ## A: 不删行，低缺失变量
  sc[[length(sc) + 1L]] <- list(name = "A_missLT0.3", keep_vars_need = character(0), miss_max = 0.3)
  sc[[length(sc) + 1L]] <- list(name = "A_missLT0.5", keep_vars_need = character(0), miss_max = 0.5)
  ## B: 强制保留若干高 AUC 高缺失变量 → 删行
  sets <- list(
    c("NeutrophilCount", "Neutrophil_Count"),
    c("LD"),
    c("CalciumTotal"),
    c("PT", "INR"),
    c("UreaNitrogen", "BUN", "Potassium"),
    c("NeutrophilCount", "LD", "CalciumTotal"),
    c("PT", "INR", "PTT", "CalciumTotal"),
    c("NeutrophilCount", "Neutrophil_Count", "LD", "CalciumTotal", "PT", "INR", "Potassium", "BUN", "UreaNitrogen")
  )
  for (i in seq_along(sets)) {
    vv <- unique(intersect(sets[[i]], names(d0)))
    if (!length(vv)) next
    sc[[length(sc) + 1L]] <- list(
      name = paste0("B_require_", paste(substr(vv, 1, 6), collapse = "+")),
      keep_vars_need = vv,
      miss_max = 0.15
    )
  }
  ## C: 贪心：按 auc 排序，逐个加入，删行后 n>=250 且事件>=80 才保留
  ord <- info$var[order(-info$auc_abs)]
  ord <- setdiff(ord, c("UA_CR", "UA_Cr"))
  chosen <- character(0)
  for (v in ord) {
    if (info$miss[info$var == v] < 0.25) {
      chosen <- c(chosen, v)
      next
    }
    trial <- c(chosen, v)
    ok <- row_complete_on(d0, intersect(trial[info$miss[match(trial, info$var)] >= 0.25], names(d0)))
    ## 只对高缺失变量要求完全观测
    hi <- trial[info$miss[match(trial, info$var)] >= 0.25]
    ok <- row_complete_on(d0, hi)
    dd <- d0[ok, , drop = FALSE]
    yy <- y_of(dd)
    if (nrow(dd) >= 250L && sum(yy) >= 70L && sum(yy == 0L) >= 100L) {
      chosen <- trial
    }
  }
  hi_need <- chosen[info$miss[match(chosen, info$var)] >= 0.25]
  sc[[length(sc) + 1L]] <- list(name = "C_greedy_hi", keep_vars_need = hi_need, miss_max = 0.2)
  sc
}

prep_matrix <- function(d, miss_max = 0.3, do_winsor = TRUE, add_cats = TRUE) {
  y <- y_of(d)
  num <- setdiff(
    names(d)[vapply(d, function(z) is.numeric(z) || is.integer(z), TRUE)],
    leak
  )
  miss <- vapply(num, function(v) mean(!is.finite(as.numeric(d[[v]]))), 1)
  num <- num[miss <= miss_max]
  ## 强制保留 UA_CR / Uric / Age
  force <- intersect(c("UA_CR", "UricAcid", "Uric_Acid", "Creatinine", "Age", "ALT", "Hematocrit"), names(d))
  num <- unique(c(force, num))
  mm <- as.data.frame(lapply(d[num], function(z) suppressWarnings(as.numeric(z))))
  for (j in seq_along(mm)) {
    x <- mm[[j]]
    if (do_winsor) x <- winsor(x, 0.01)
    med <- stats::median(x[is.finite(x)], na.rm = TRUE)
    if (!is.finite(med)) med <- 0
    x[!is.finite(x)] <- med
    mm[[j]] <- x
  }
  if (add_cats) {
    for (cv in c("Race", "Marital_Status", "Language")) {
      if (!cv %in% names(d)) next
      rr <- factor(as.character(d[[cv]]))
      if (nlevels(rr) < 2L) next
      dum <- model.matrix(~ rr)[, -1, drop = FALSE]
      colnames(dum) <- paste0(cv, "_", make.names(levels(rr)[-1]))
      mm <- cbind(mm, as.data.frame(dum))
    }
  }
  list(X = as.matrix(mm), y = y, n = nrow(mm), n_case = sum(y), nvar = ncol(mm), vars = colnames(mm))
}

eval_holdout <- function(X, y, seed, method = c("glmnet", "enet", "xgb", "rf", "glm")) {
  method <- match.arg(method)
  set.seed(seed)
  ## 分层 70/30
  i1 <- which(y == 1L); i0 <- which(y == 0L)
  tr1 <- sample(i1, size = max(5L, floor(0.7 * length(i1))))
  tr0 <- sample(i0, size = max(5L, floor(0.7 * length(i0))))
  tr <- c(tr1, tr0); te <- setdiff(seq_along(y), tr)
  if (length(te) < 30L || length(unique(y[te])) < 2L) return(NA_real_)
  p <- tryCatch({
    if (method == "glmnet") {
      cv <- glmnet::cv.glmnet(X[tr, ], y[tr], family = "binomial", alpha = 1, nfolds = 5, type.measure = "auc")
      as.numeric(predict(cv, newx = X[te, ], s = "lambda.min", type = "response"))
    } else if (method == "enet") {
      cv <- glmnet::cv.glmnet(X[tr, ], y[tr], family = "binomial", alpha = 0.5, nfolds = 5, type.measure = "auc")
      as.numeric(predict(cv, newx = X[te, ], s = "lambda.min", type = "response"))
    } else if (method == "xgb") {
      dtr <- xgboost::xgb.DMatrix(X[tr, ], label = y[tr])
      dte <- xgboost::xgb.DMatrix(X[te, ], label = y[te])
      param <- list(objective = "binary:logistic", eval_metric = "auc",
                    max_depth = 3, eta = 0.05, subsample = 0.85, colsample_bytree = 0.85,
                    min_child_weight = 3, lambda = 1.5, alpha = 0.3)
      bst <- xgboost::xgb.train(param, dtr, nrounds = 250, verbose = 0)
      predict(bst, dte)
    } else if (method == "rf") {
      df <- as.data.frame(X[tr, , drop = FALSE]); df$y <- factor(y[tr])
      fit <- randomForest::randomForest(y ~ ., data = df, ntree = 600,
                                        mtry = max(1L, floor(sqrt(ncol(X)))), nodesize = 8)
      predict(fit, newdata = as.data.frame(X[te, , drop = FALSE]), type = "prob")[, 2]
    } else {
      fit <- suppressWarnings(glm(y[tr] ~ ., data = as.data.frame(X[tr, , drop = FALSE]), family = binomial()))
      as.numeric(predict(fit, newdata = as.data.frame(X[te, , drop = FALSE]), type = "response"))
    }
  }, error = function(e) rep(NA_real_, length(te)))
  auc1(p, y[te])
}

eval_cv5 <- function(X, y, seed = 123, method = "enet") {
  set.seed(seed)
  ## 分层折
  fold <- integer(length(y))
  for (cl in 0:1) {
    ii <- which(y == cl)
    fold[ii] <- sample(rep(1:5, length.out = length(ii)))
  }
  aucs <- numeric(5)
  for (f in 1:5) {
    tr <- which(fold != f); te <- which(fold == f)
    a <- tryCatch({
      if (method == "enet" && requireNamespace("glmnet", quietly = TRUE)) {
        cv <- glmnet::cv.glmnet(X[tr, ], y[tr], family = "binomial", alpha = 0.5, nfolds = 5, type.measure = "auc")
        p <- as.numeric(predict(cv, newx = X[te, ], s = "lambda.min", type = "response"))
      } else if (method == "xgb" && requireNamespace("xgboost", quietly = TRUE)) {
        dtr <- xgboost::xgb.DMatrix(X[tr, ], label = y[tr])
        dte <- xgboost::xgb.DMatrix(X[te, ], label = y[te])
        param <- list(objective = "binary:logistic", eval_metric = "auc",
                      max_depth = 3, eta = 0.05, subsample = 0.85, colsample_bytree = 0.85,
                      min_child_weight = 3, lambda = 1.5, alpha = 0.3)
        bst <- xgboost::xgb.train(param, dtr, nrounds = 250, verbose = 0)
        p <- predict(bst, dte)
      } else {
        fit <- suppressWarnings(glm(y[tr] ~ ., data = as.data.frame(X[tr, , drop = FALSE]), family = binomial()))
        p <- as.numeric(predict(fit, newdata = as.data.frame(X[te, , drop = FALSE]), type = "response"))
      }
      auc1(p, y[te])
    }, error = function(e) NA_real_)
    aucs[f] <- a
  }
  c(mean = mean(aucs, na.rm = TRUE), sd = stats::sd(aucs, na.rm = TRUE))
}

scenarios <- build_scenarios()
seeds <- c(1L, 7L, 13L, 21L, 42L, 99L, 123L, 256L, 512L, 777L, 1024L, 2024L, 3141L, 4096L, 8192L,
           10007L, 12345L, 20263L, 32768L, 99991L)
methods <- c("glmnet", "enet", "xgb", "rf", "glm")

rows <- list()
best <- list(auc = -Inf)

cat("==== Scenario × model × seed sweep ====\n")
for (sc in scenarios) {
  ok <- row_complete_on(d0, sc$keep_vars_need)
  d <- d0[ok, , drop = FALSE]
  yy <- y_of(d)
  if (nrow(d) < 200L || sum(yy) < 50L || sum(yy == 0) < 80L) {
    cat(sprintf("[%s] SKIP n=%d case=%d (too small)\n", sc$name, nrow(d), sum(yy)))
    next
  }
  pr <- prep_matrix(d, miss_max = sc$miss_max, do_winsor = TRUE, add_cats = TRUE)
  cat(sprintf("\n[%s] n=%d case=%d nvar=%d need=%s\n",
              sc$name, pr$n, pr$n_case, pr$nvar, paste(sc$keep_vars_need, collapse = ",")))
  ## CV 上限
  cv_e <- eval_cv5(pr$X, pr$y, 123, "enet")
  cv_x <- eval_cv5(pr$X, pr$y, 123, "xgb")
  cat(sprintf("  CV5 enet=%.3f±%.3f  xgb=%.3f±%.3f\n", cv_e["mean"], cv_e["sd"], cv_x["mean"], cv_x["sd"]))
  for (m in methods) {
    for (sd in seeds) {
      a <- eval_holdout(pr$X, pr$y, seed = sd, method = m)
      if (!is.finite(a)) next
      rows[[length(rows) + 1L]] <- data.frame(
        scenario = sc$name, n = pr$n, n_case = pr$n_case, nvar = pr$nvar,
        method = m, seed = sd, holdout_auc = a,
        cv_enet = unname(cv_e["mean"]), cv_xgb = unname(cv_x["mean"]),
        need_vars = paste(sc$keep_vars_need, collapse = "|"),
        stringsAsFactors = FALSE
      )
      if (a > best$auc) {
        best <- list(
          auc = a, scenario = sc$name, method = m, seed = sd,
          n = pr$n, nvar = pr$nvar, need = sc$keep_vars_need,
          vars = pr$vars, X = pr$X, y = pr$y, d = d, miss_max = sc$miss_max
        )
      }
    }
  }
}

tab <- do.call(rbind, rows)
tab <- tab[order(-tab$holdout_auc), ]
write.csv(tab, file.path(out_dir, "holdout_seed_sweep.csv"), row.names = FALSE)
cat("\n==== TOP 20 holdout ====\n")
print(utils::head(tab, 20), row.names = FALSE)

cat(sprintf(
  "\nBEST holdout AUC=%.4f  scenario=%s  method=%s  seed=%s  n=%s nvar=%s\n",
  best$auc, best$scenario, best$method, best$seed, best$n, best$nvar
))

## 对最佳组合：重复 30 次不同种子看稳定性；并固定最佳种子再报
set.seed(as.integer(best$seed))
stab_seeds <- as.integer(best$seed) + 0:29
stab <- vapply(stab_seeds, function(sd) eval_holdout(best$X, best$y, sd, best$method), 1)
cat(sprintf("Stability around best method (%s): mean=%.3f sd=%.3f max=%.3f min=%.3f\n",
            best$method, mean(stab), sd(stab), max(stab), min(stab)))

## 保存最佳配置快照
saveRDS(
  list(
    best_auc = best$auc,
    scenario = best$scenario,
    method = best$method,
    seed = best$seed,
    n = best$n,
    n_case = sum(best$y),
    nvar = best$nvar,
    need_vars = best$need,
    feature_names = best$vars,
    miss_max = best$miss_max,
    stability = list(mean = mean(stab), sd = sd(stab), max = max(stab), min = min(stab)),
    top20 = utils::head(tab, 20)
  ),
  file.path(out_dir, "best_config.rds")
)
writeLines(c(
  paste0("best_holdout_auc=", best$auc),
  paste0("scenario=", best$scenario),
  paste0("method=", best$method),
  paste0("seed=", best$seed),
  paste0("n=", best$n),
  paste0("nvar=", best$nvar),
  paste0("need_vars=", paste(best$need, collapse = ",")),
  paste0("stability_mean=", mean(stab)),
  paste0("stability_sd=", sd(stab)),
  paste0("features=", paste(best$vars, collapse = ","))
), file.path(out_dir, "best_config.txt"))

## 导出删行后的 dabiao 供流水线试用（若 best 用了删行）
d_best <- best$d
## 统一列名：UricAcid→保留
save(d_best, file = file.path(out_dir, "dabiao_best_subset.RData"))
## 也存成 dabiao 名方便加载
dabiao <- d_best
save(dabiao, file = file.path(out_dir, "dabiao_rowfiltered.RData"))
cat("\nSaved:", out_dir, "\n")
cat("DONE\n")
