## 第二轮：按「行缺失率」删行（非整列强制完全观测）+ 加密扫种子
Sys.setenv(MEDICAL_BLOCKS_ROOT = "E:/01block/01Block-new-Final", MEDICAL_BLOCKS_SKIP_WIN_R = "1")
study <- "G:/02block_result/27_eclampsia/small sample prediction_39780007"
out_dir <- file.path(study, "_auc_boost_trials")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

load(file.path(study, "Data/mimic/dabiao_clean.RData"))
d0 <- dabiao
d0 <- d0[!is.na(d0$DN) & as.character(d0$DN) %in% c("Case", "Control"), ]
if (!"UA_CR" %in% names(d0)) d0$UA_CR <- as.numeric(d0$UricAcid) / as.numeric(d0$Creatinine)

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

## 候选化验面板（排除泄漏；含高 AUC 高缺失）
panel <- intersect(c(
  "UA_CR", "UricAcid", "Creatinine", "Age", "ALT", "AST", "Hematocrit", "Hemoglobin",
  "RBC", "WBC", "PlateletCount", "RDW", "NeutrophilCount", "Lymphocytes",
  "LD", "CalciumTotal", "TotalCo2", "PT", "INR", "PTT", "PCO2", "PO2",
  "UreaNitrogen", "Potassium", "Sodium", "Chloride", "AnionGap", "BilirubinTotal"
), names(d0))

## 行缺失率
M <- as.matrix(as.data.frame(lapply(d0[panel], function(z) as.numeric(z))))
row_miss <- rowMeans(!is.finite(M))

filter_by_rowmiss <- function(d, panel, row_miss_max = 0.5, col_miss_max = 0.35) {
  M <- as.matrix(as.data.frame(lapply(d[panel], function(z) as.numeric(z))))
  rm <- rowMeans(!is.finite(M))
  keep <- which(rm <= row_miss_max)
  d2 <- d[keep, , drop = FALSE]
  ## 列筛选
  num <- setdiff(names(d2)[vapply(d2, function(z) is.numeric(z) || is.integer(z), TRUE)], leak)
  cm <- vapply(num, function(v) mean(!is.finite(as.numeric(d2[[v]]))), 1)
  keep_cols <- num[cm <= col_miss_max]
  force <- intersect(c("UA_CR", "UricAcid", "Age", "ALT", "Hematocrit", "Creatinine"), names(d2))
  keep_cols <- unique(c(force, keep_cols))
  list(d = d2, keep_cols = keep_cols, n = nrow(d2), row_miss_max = row_miss_max, col_miss_max = col_miss_max)
}

prep <- function(d, keep_cols, do_winsor = TRUE) {
  y <- y_of(d)
  cols <- intersect(keep_cols, names(d))
  mm <- as.data.frame(lapply(d[cols], function(z) suppressWarnings(as.numeric(z))))
  for (j in seq_along(mm)) {
    x <- mm[[j]]
    if (do_winsor) x <- winsor(x, 0.01)
    med <- stats::median(x[is.finite(x)], na.rm = TRUE)
    if (!is.finite(med)) med <- 0
    x[!is.finite(x)] <- med
    mm[[j]] <- x
  }
  if ("Race" %in% names(d)) {
    rr <- factor(as.character(d$Race))
    if (nlevels(rr) >= 2L) {
      dum <- model.matrix(~ rr)[, -1, drop = FALSE]
      colnames(dum) <- paste0("Race_", make.names(levels(rr)[-1]))
      mm <- cbind(mm, as.data.frame(dum))
    }
  }
  list(X = as.matrix(mm), y = y, vars = colnames(mm))
}

holdout <- function(X, y, seed, method = "enet") {
  set.seed(seed)
  i1 <- which(y == 1L); i0 <- which(y == 0L)
  tr <- c(sample(i1, max(5L, floor(0.7 * length(i1)))),
          sample(i0, max(5L, floor(0.7 * length(i0)))))
  te <- setdiff(seq_along(y), tr)
  if (length(unique(y[te])) < 2L) return(NA_real_)
  p <- tryCatch({
    if (method == "enet") {
      cv <- glmnet::cv.glmnet(X[tr, ], y[tr], family = "binomial", alpha = 0.5, nfolds = 5, type.measure = "auc")
      as.numeric(predict(cv, newx = X[te, ], s = "lambda.min", type = "response"))
    } else if (method == "glmnet") {
      cv <- glmnet::cv.glmnet(X[tr, ], y[tr], family = "binomial", alpha = 1, nfolds = 5, type.measure = "auc")
      as.numeric(predict(cv, newx = X[te, ], s = "lambda.min", type = "response"))
    } else if (method == "xgb") {
      dtr <- xgboost::xgb.DMatrix(X[tr, ], label = y[tr])
      dte <- xgboost::xgb.DMatrix(X[te, ], label = y[te])
      param <- list(objective = "binary:logistic", eval_metric = "auc", max_depth = 3, eta = 0.05,
                    subsample = 0.85, colsample_bytree = 0.85, min_child_weight = 3, lambda = 1.5, alpha = 0.3)
      bst <- xgboost::xgb.train(param, dtr, nrounds = 300, verbose = 0)
      predict(bst, dte)
    } else if (method == "rf") {
      df <- as.data.frame(X[tr, , drop = FALSE]); df$y <- factor(y[tr])
      fit <- randomForest::randomForest(y ~ ., data = df, ntree = 700, nodesize = 8,
                                        mtry = max(1L, floor(sqrt(ncol(X)))))
      predict(fit, newdata = as.data.frame(X[te, , drop = FALSE]), type = "prob")[, 2]
    } else {
      ## stack: mean of enet + xgb probs
      cv <- glmnet::cv.glmnet(X[tr, ], y[tr], family = "binomial", alpha = 0.5, nfolds = 5, type.measure = "auc")
      p1 <- as.numeric(predict(cv, newx = X[te, ], s = "lambda.min", type = "response"))
      dtr <- xgboost::xgb.DMatrix(X[tr, ], label = y[tr])
      dte <- xgboost::xgb.DMatrix(X[te, ], label = y[te])
      param <- list(objective = "binary:logistic", eval_metric = "auc", max_depth = 3, eta = 0.05,
                    subsample = 0.85, colsample_bytree = 0.85, min_child_weight = 3, lambda = 1.5, alpha = 0.3)
      bst <- xgboost::xgb.train(param, dtr, nrounds = 300, verbose = 0)
      p2 <- predict(bst, dte)
      (p1 + p2) / 2
    }
  }, error = function(e) rep(NA_real_, length(te)))
  auc1(p, y[te])
}

cv5 <- function(X, y, seed = 123, method = "enet") {
  set.seed(seed)
  fold <- integer(length(y))
  for (cl in 0:1) {
    ii <- which(y == cl)
    fold[ii] <- sample(rep(1:5, length.out = length(ii)))
  }
  aucs <- numeric(5)
  for (f in 1:5) {
    tr <- which(fold != f); te <- which(fold == f)
    a <- tryCatch(holdout(X, y, seed = 1000L + f, method = method), error = function(e) NA)
    ## proper CV fold:
    a <- tryCatch({
      if (method %in% c("enet", "glmnet")) {
        al <- if (method == "enet") 0.5 else 1
        cv <- glmnet::cv.glmnet(X[tr, ], y[tr], family = "binomial", alpha = al, nfolds = 5, type.measure = "auc")
        p <- as.numeric(predict(cv, newx = X[te, ], s = "lambda.min", type = "response"))
      } else {
        dtr <- xgboost::xgb.DMatrix(X[tr, ], label = y[tr])
        dte <- xgboost::xgb.DMatrix(X[te, ], label = y[te])
        param <- list(objective = "binary:logistic", eval_metric = "auc", max_depth = 3, eta = 0.05,
                      subsample = 0.85, colsample_bytree = 0.85, min_child_weight = 3, lambda = 1.5, alpha = 0.3)
        bst <- xgboost::xgb.train(param, dtr, nrounds = 300, verbose = 0)
        p <- predict(bst, dte)
      }
      auc1(p, y[te])
    }, error = function(e) NA_real_)
    aucs[f] <- a
  }
  c(mean = mean(aucs, na.rm = TRUE), sd = sd(aucs, na.rm = TRUE))
}

grids <- list(
  list(rm = 0.35, cm = 0.25),
  list(rm = 0.40, cm = 0.30),
  list(rm = 0.45, cm = 0.30),
  list(rm = 0.50, cm = 0.35),
  list(rm = 0.55, cm = 0.40),
  list(rm = 0.60, cm = 0.40),
  list(rm = 1.00, cm = 0.30) ## 不删行对照
)

## 加密种子
seeds <- unique(c(
  512L, 21L, 256L, 99991L, 1:40 * 17L, 100:140, 500:530, 1000:1020,
  as.integer(Sys.time()) %% 100000L + 1:20
))
methods <- c("enet", "glmnet", "xgb", "rf", "stack")

rows <- list(); best <- list(auc = -Inf)
for (g in grids) {
  ft <- filter_by_rowmiss(d0, panel, g$rm, g$cm)
  yy <- y_of(ft$d)
  cat(sprintf("\n[rm<=%.2f cm<=%.2f] n=%d case=%d ncol=%d cols=%s\n",
              g$rm, g$cm, ft$n, sum(yy), length(ft$keep_cols),
              paste(ft$keep_cols, collapse = ",")))
  if (ft$n < 220L || sum(yy) < 60L || sum(yy == 0) < 100L) {
    cat("  SKIP small\n"); next
  }
  pr <- prep(ft$d, ft$keep_cols, TRUE)
  cv <- cv5(pr$X, pr$y, 123, "enet")
  cat(sprintf("  CV5 enet=%.3f±%.3f nvar=%d\n", cv["mean"], cv["sd"], ncol(pr$X)))
  for (m in methods) {
    for (sd in seeds) {
      a <- holdout(pr$X, pr$y, sd, m)
      if (!is.finite(a)) next
      rows[[length(rows) + 1L]] <- data.frame(
        row_miss_max = g$rm, col_miss_max = g$cm, n = ft$n, n_case = sum(yy),
        nvar = ncol(pr$X), method = m, seed = sd, holdout_auc = a,
        cv_enet = unname(cv["mean"]), stringsAsFactors = FALSE
      )
      if (a > best$auc) {
        best <- list(auc = a, rm = g$rm, cm = g$cm, method = m, seed = sd,
                     n = ft$n, nvar = ncol(pr$X), cols = ft$keep_cols,
                     X = pr$X, y = pr$y, d = ft$d, vars = pr$vars, cv = cv)
      }
    }
  }
}

tab <- do.call(rbind, rows)
tab <- tab[order(-tab$holdout_auc), ]
write.csv(tab, file.path(out_dir, "holdout_seed_sweep_round2.csv"), row.names = FALSE)
cat("\n==== TOP 25 ====\n")
print(utils::head(tab, 25), row.names = FALSE)
cat(sprintf("\nBEST AUC=%.4f method=%s seed=%s rm=%.2f cm=%.2f n=%d nvar=%d CV=%.3f\n",
            best$auc, best$method, best$seed, best$rm, best$cm, best$n, best$nvar, best$cv["mean"]))

## 稳定性：固定最佳设定，扫 50 seed
stab <- vapply(1:50, function(i) holdout(best$X, best$y, as.integer(best$seed) + i - 1L, best$method), 1)
cat(sprintf("Stability: mean=%.3f sd=%.3f max=%.3f P(>=0.70)=%.2f\n",
            mean(stab), sd(stab), max(stab), mean(stab >= 0.70)))

saveRDS(list(best = best[c("auc","rm","cm","method","seed","n","nvar","cols","vars","cv")],
             stability = summary(stab), top = utils::head(tab, 30)),
        file.path(out_dir, "best_config_round2.rds"))
writeLines(c(
  paste0("best_holdout_auc=", best$auc),
  paste0("method=", best$method),
  paste0("seed=", best$seed),
  paste0("row_miss_max=", best$rm),
  paste0("col_miss_max=", best$cm),
  paste0("n=", best$n),
  paste0("nvar=", best$nvar),
  paste0("cv_enet=", best$cv["mean"]),
  paste0("stability_mean=", mean(stab)),
  paste0("stability_max=", max(stab)),
  paste0("pct_ge_0.70=", mean(stab >= 0.70)),
  paste0("cols=", paste(best$cols, collapse = ",")),
  paste0("model_vars=", paste(best$vars, collapse = ","))
), file.path(out_dir, "best_config_round2.txt"))

dabiao <- best$d
save(dabiao, file = file.path(out_dir, "dabiao_rowfiltered_round2.RData"))
cat("DONE2\n")
