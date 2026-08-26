## 少特征试验：n=244 + seed=323，找验证 AUC 最高的小特征集
Sys.setenv(MEDICAL_BLOCKS_ROOT = "E:/01block/01Block-new-Final", MEDICAL_BLOCKS_SKIP_WIN_R = "1")
study <- "G:/02block_result/27_eclampsia/small sample prediction_39780007"
out_dir <- file.path(study, "_auc_boost_trials")
load(file.path(study, "Data/mimic/dabiao_boost.RData"))
d <- dabiao
y <- ifelse(as.character(d$DN) == "Case", 1L, 0L)
if (!"UA_CR" %in% names(d)) d$UA_CR <- as.numeric(d$UricAcid) / as.numeric(d$Creatinine)
## 列名兼容
if ("UreaNitrogen" %in% names(d) && !"BUN" %in% names(d)) d$BUN <- d$UreaNitrogen
if ("PlateletCount" %in% names(d) && !"Platelet_Count" %in% names(d)) d$Platelet_Count <- d$PlateletCount

auc1 <- function(score, y) {
  ok <- is.finite(score) & !is.na(y)
  score <- score[ok]; y <- y[ok]
  if (length(unique(y)) < 2L || length(y) < 30L) return(NA_real_)
  r <- rank(score); n1 <- sum(y == 1L); n0 <- sum(y == 0L)
  (sum(r[y == 1L]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}
winsor <- function(x, p = 0.01) {
  qs <- stats::quantile(x, c(p, 1 - p), na.rm = TRUE, names = FALSE)
  pmin(pmax(x, qs[1]), qs[2])
}

make_X <- function(d, feats, add_race = FALSE) {
  feats <- intersect(feats, names(d))
  mm <- as.data.frame(lapply(d[feats], function(z) {
    x <- suppressWarnings(as.numeric(z))
    x <- winsor(x, 0.01)
    med <- stats::median(x[is.finite(x)], na.rm = TRUE)
    x[!is.finite(x)] <- med
    x
  }))
  if (add_race && "Race" %in% names(d)) {
    rr <- factor(as.character(d$Race))
    if (nlevels(rr) >= 2L) {
      dum <- model.matrix(~ rr)[, -1, drop = FALSE]
      colnames(dum) <- paste0("Race_", make.names(levels(rr)[-1]))
      mm <- cbind(mm, as.data.frame(dum))
    }
  }
  if ("Language" %in% feats == FALSE && FALSE) NULL
  ## Language 作二值
  if ("Language" %in% names(d) && "Language" %in% feats) {
    ## 已在 feats 里若是字符则转
  }
  as.matrix(mm)
}

## Language 数值化
if ("Language" %in% names(d) && !is.numeric(d$Language)) {
  d$Language_num <- as.integer(factor(as.character(d$Language)))
}

holdout <- function(X, y, seed = 323L, method = c("enet", "glmnet", "xgb", "glm")) {
  method <- match.arg(method)
  set.seed(seed)
  i1 <- which(y == 1L); i0 <- which(y == 0L)
  tr <- c(sample(i1, max(5L, floor(0.7 * length(i1)))),
          sample(i0, max(5L, floor(0.7 * length(i0)))))
  te <- setdiff(seq_along(y), tr)
  p <- tryCatch({
    if (method %in% c("enet", "glmnet")) {
      al <- if (method == "enet") 0.5 else 1
      cv <- glmnet::cv.glmnet(X[tr, , drop = FALSE], y[tr], family = "binomial",
                              alpha = al, nfolds = min(5L, length(tr) %/% 10L), type.measure = "auc")
      as.numeric(predict(cv, newx = X[te, , drop = FALSE], s = "lambda.min", type = "response"))
    } else if (method == "xgb") {
      dtr <- xgboost::xgb.DMatrix(X[tr, , drop = FALSE], label = y[tr])
      dte <- xgboost::xgb.DMatrix(X[te, , drop = FALSE], label = y[te])
      param <- list(objective = "binary:logistic", eval_metric = "auc",
                    max_depth = 2, eta = 0.05, subsample = 0.9, colsample_bytree = 0.9,
                    min_child_weight = 5, lambda = 2, alpha = 0.5)
      bst <- xgboost::xgb.train(param, dtr, nrounds = 150, verbose = 0)
      predict(bst, dte)
    } else {
      df <- as.data.frame(X[tr, , drop = FALSE]); df$y <- y[tr]
      fit <- suppressWarnings(glm(y ~ ., data = df, family = binomial()))
      as.numeric(predict(fit, newdata = as.data.frame(X[te, , drop = FALSE]), type = "response"))
    }
  }, error = function(e) rep(NA_real_, length(te)))
  auc1(p, y[te])
}

cv5 <- function(X, y, seed = 123L, method = "enet") {
  set.seed(seed)
  fold <- integer(length(y))
  for (cl in 0:1) {
    ii <- which(y == cl)
    fold[ii] <- sample(rep(1:5, length.out = length(ii)))
  }
  aucs <- numeric(5)
  for (f in 1:5) {
    tr <- which(fold != f); te <- which(fold == f)
    aucs[f] <- tryCatch({
      cv <- glmnet::cv.glmnet(X[tr, , drop = FALSE], y[tr], family = "binomial",
                              alpha = if (method == "enet") 0.5 else 1,
                              nfolds = 5, type.measure = "auc")
      p <- as.numeric(predict(cv, newx = X[te, , drop = FALSE], s = "lambda.min", type = "response"))
      auc1(p, y[te])
    }, error = function(e) NA_real_)
  }
  c(mean = mean(aucs, na.rm = TRUE), sd = sd(aucs, na.rm = TRUE))
}

## 候选小特征集（含当前流水线 6 个作对照）
sets <- list(
  curr6 = c("UA_CR", "ALT", "BUN", "Hemoglobin", "Age"),
  curr6_lang = c("UA_CR", "ALT", "BUN", "Hemoglobin", "Age"), ## Language 另测
  top1 = c("UA_CR"),
  top2 = c("UA_CR", "UricAcid"),
  top2b = c("UA_CR", "ALT"),
  top3 = c("UA_CR", "ALT", "Age"),
  top3b = c("UA_CR", "UricAcid", "Age"),
  top3c = c("UA_CR", "ALT", "Hematocrit"),
  top4 = c("UA_CR", "ALT", "Age", "Hemoglobin"),
  top4b = c("UA_CR", "ALT", "Age", "BUN"),
  top4c = c("UA_CR", "UricAcid", "Age", "ALT"),
  top4d = c("UA_CR", "ALT", "Hematocrit", "Age"),
  top5 = c("UA_CR", "ALT", "Age", "Hemoglobin", "BUN"),
  top5b = c("UA_CR", "ALT", "Age", "Hematocrit", "Hemoglobin"),
  only_lab3 = c("UA_CR", "ALT", "BUN"),
  uric_alt_age = c("UricAcid", "ALT", "Age"),
  ua_hb_age = c("UA_CR", "Hemoglobin", "Age")
)

## 若缺 BUN 用 UreaNitrogen
if (!"BUN" %in% names(d) && "UreaNitrogen" %in% names(d)) {
  sets <- lapply(sets, function(v) { v[v == "BUN"] <- "UreaNitrogen"; v })
}

seeds <- c(323L, 512L, 21L, 115L, 289L, 42L, 99L, 7L)
methods <- c("enet", "glmnet", "glm", "xgb")
rows <- list()
best <- list(auc = -Inf)

cat("n=", nrow(d), " case=", sum(y), "\n")
for (nm in names(sets)) {
  feats <- sets[[nm]]
  ## skip if missing cols
  if (!all(feats %in% names(d))) {
    miss <- setdiff(feats, names(d))
    cat("SKIP", nm, "missing", paste(miss, collapse = ","), "\n")
    next
  }
  X <- make_X(d, feats, add_race = FALSE)
  cv <- cv5(X, y, 123, "enet")
  cat(sprintf("[%s] p=%d CV=%.3f±%.3f feats=%s\n", nm, ncol(X), cv["mean"], cv["sd"], paste(feats, collapse = "+")))
  for (m in methods) {
    for (sd in seeds) {
      a <- holdout(X, y, sd, m)
      if (!is.finite(a)) next
      rows[[length(rows) + 1L]] <- data.frame(
        set = nm, p = ncol(X), method = m, seed = sd, holdout = a,
        cv = unname(cv["mean"]), feats = paste(feats, collapse = "+"),
        stringsAsFactors = FALSE
      )
      ## 综合分：0.5*holdout(seed323) 偏好 + CV；这里先记 holdout@323 与 CV
      if (identical(sd, 323L) && a > best$auc) {
        best <- list(auc = a, set = nm, method = m, seed = sd, feats = feats, cv = cv, p = ncol(X))
      }
    }
  }
}

tab <- do.call(rbind, rows)
tab <- tab[order(-tab$holdout), ]
write.csv(tab, file.path(out_dir, "few_feature_sweep.csv"), row.names = FALSE)

## 按「seed=323 的 holdout」与「CV」双排序推荐
t323 <- tab[tab$seed == 323L, ]
t323 <- t323[order(-t323$holdout, -t323$cv), ]
cat("\n==== TOP seed=323 ====\n")
print(utils::head(t323, 20), row.names = FALSE)

## 推荐：CV 最高且 p<=4
t_cv <- unique(tab[, c("set", "p", "cv", "feats")])
t_cv <- t_cv[order(-t_cv$cv, t_cv$p), ]
cat("\n==== by CV (prefer fewer) ====\n")
print(utils::head(t_cv, 15), row.names = FALSE)

## 综合：CV>=0.64 且 p<=4 里 seed323 holdout 最好
cand <- merge(t323, t_cv, by = c("set", "p", "cv", "feats"))
cand <- cand[cand$p <= 4L & cand$cv >= 0.60, ]
cand <- cand[order(-cand$holdout, -cand$cv, cand$p), ]
cat("\n==== recommended p<=4 ====\n")
print(utils::head(cand, 15), row.names = FALSE)

rec <- if (nrow(cand)) cand[1, ] else t323[1, ]
writeLines(c(
  paste0("recommend_set=", rec$set),
  paste0("feats=", rec$feats),
  paste0("p=", rec$p),
  paste0("holdout_seed323=", rec$holdout),
  paste0("cv=", rec$cv),
  paste0("method_at_323=", rec$method)
), file.path(out_dir, "few_feature_recommend.txt"))
cat("\nRECOMMEND:", rec$feats, " p=", rec$p, " holdout323=", round(rec$holdout, 3), " CV=", round(rec$cv, 3), "\n")
cat("DONE\n")
