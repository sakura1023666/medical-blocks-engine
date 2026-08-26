## 加压探测：能否在诚实 CV/holdout 下摸到 0.70
Sys.setenv(MEDICAL_BLOCKS_ROOT = "E:/01block/01Block-new-Final", MEDICAL_BLOCKS_SKIP_WIN_R = "1")
study <- "G:/02block_result/27_eclampsia/small sample prediction_39780007"
load(file.path(study, "Data/mimic/dabiao_clean.RData"))
d <- dabiao
d <- d[!is.na(d$DN) & as.character(d$DN) %in% c("Case", "Control"), ]
y <- ifelse(as.character(d$DN) == "Case", 1L, 0L)
if (!"UA_CR" %in% names(d)) {
  d$UA_CR <- as.numeric(d$UricAcid) / as.numeric(d$Creatinine)
}

## 疾病泄漏列（与 config 一致，探测时也排除）
disease <- c(
  "Hypertension", "T1DM", "T2DM", "Diabetes", "Glucose", "HbA1c",
  "UrineProtein", "UrineGlucose", "AlbuminUrine", "AlbuminCreatinine",
  "CKD", "Acute_Renal_Failure", "Gender"
)
## 但 UricAcid 可保留作特征（暴露相关）

auc1 <- function(score, y) {
  ok <- is.finite(score) & !is.na(y)
  score <- score[ok]; y <- y[ok]
  if (length(unique(y)) < 2L || length(y) < 40L) return(NA_real_)
  r <- rank(score)
  n1 <- sum(y == 1L); n0 <- sum(y == 0L)
  (sum(r[y == 1L]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}

winsor <- function(x, p = 0.01) {
  qs <- stats::quantile(x, c(p, 1 - p), na.rm = TRUE, names = FALSE)
  pmin(pmax(x, qs[1]), qs[2])
}

prep_X <- function(d, y, miss_max = 0.5, do_winsor = TRUE, keep_uric = TRUE) {
  drop <- unique(c(disease, "ID", "DN", "Group", "UA_Cr"))
  if (!keep_uric) drop <- c(drop, "UricAcid", "Uric_Acid")
  # numeric + simple factor Race
  num <- names(d)[vapply(d, function(z) is.numeric(z) || is.integer(z), TRUE)]
  num <- setdiff(num, drop)
  miss <- vapply(num, function(v) mean(!is.finite(as.numeric(d[[v]]))), numeric(1))
  num <- num[miss <= miss_max]
  mm <- as.data.frame(lapply(d[num], function(z) suppressWarnings(as.numeric(z))))
  for (j in seq_along(mm)) {
    x <- mm[[j]]
    if (do_winsor) x <- winsor(x, 0.01)
    med <- stats::median(x[is.finite(x)], na.rm = TRUE)
    x[!is.finite(x)] <- med
    mm[[j]] <- x
  }
  if ("Race" %in% names(d) && !"Race" %in% names(mm)) {
    rr <- factor(as.character(d$Race))
    dum <- model.matrix(~ rr)[, -1, drop = FALSE]
    colnames(dum) <- paste0("Race_", make.names(levels(rr)[-1]))
    mm <- cbind(mm, as.data.frame(dum))
  }
  if ("Marital_Status" %in% names(d)) {
    rr <- factor(as.character(d$Marital_Status))
    if (nlevels(rr) >= 2L) {
      dum <- model.matrix(~ rr)[, -1, drop = FALSE]
      colnames(dum) <- paste0("Marital_", make.names(levels(rr)[-1]))
      mm <- cbind(mm, as.data.frame(dum))
    }
  }
  list(X = as.matrix(mm), y = y, vars = colnames(mm), nvar = ncol(mm))
}

eval_holdout <- function(X, y, seed = 42, method = c("glmnet", "xgb", "rf")) {
  method <- match.arg(method)
  set.seed(seed)
  idx <- sample(seq_len(nrow(X)), size = floor(0.7 * nrow(X)))
  tr <- idx; te <- setdiff(seq_len(nrow(X)), idx)
  if (method == "glmnet") {
    if (!requireNamespace("glmnet", quietly = TRUE)) return(NA)
    cv <- glmnet::cv.glmnet(X[tr, ], y[tr], family = "binomial", alpha = 1, nfolds = 5, type.measure = "auc")
    p <- as.numeric(predict(cv, newx = X[te, ], s = "lambda.min", type = "response"))
  } else if (method == "xgb") {
    if (!requireNamespace("xgboost", quietly = TRUE)) return(NA)
    dtr <- xgboost::xgb.DMatrix(X[tr, ], label = y[tr])
    dte <- xgboost::xgb.DMatrix(X[te, ], label = y[te])
    param <- list(
      objective = "binary:logistic", eval_metric = "auc",
      max_depth = 3, eta = 0.05, subsample = 0.8, colsample_bytree = 0.8,
      min_child_weight = 5, lambda = 2, alpha = 0.5
    )
    bst <- xgboost::xgb.train(param, dtr, nrounds = 200, verbose = 0)
    p <- predict(bst, dte)
  } else {
    if (!requireNamespace("randomForest", quietly = TRUE)) return(NA)
    df <- as.data.frame(X[tr, , drop = FALSE])
    df$y <- factor(y[tr])
    fit <- randomForest::randomForest(y ~ ., data = df, ntree = 500, mtry = max(1, floor(sqrt(ncol(X)))), nodesize = 10)
    p <- predict(fit, newdata = as.data.frame(X[te, , drop = FALSE]), type = "prob")[, 2]
  }
  auc1(p, y[te])
}

eval_cv5 <- function(X, y, seed = 123, method = "xgb") {
  set.seed(seed)
  fold <- sample(rep(1:5, length.out = nrow(X)))
  aucs <- numeric(5)
  for (f in 1:5) {
    tr <- which(fold != f); te <- which(fold == f)
    if (method == "xgb" && requireNamespace("xgboost", quietly = TRUE)) {
      dtr <- xgboost::xgb.DMatrix(X[tr, ], label = y[tr])
      dte <- xgboost::xgb.DMatrix(X[te, ], label = y[te])
      param <- list(
        objective = "binary:logistic", eval_metric = "auc",
        max_depth = 3, eta = 0.05, subsample = 0.8, colsample_bytree = 0.8,
        min_child_weight = 5, lambda = 2, alpha = 0.5
      )
      bst <- xgboost::xgb.train(param, dtr, nrounds = 200, verbose = 0)
      p <- predict(bst, dte)
    } else if (requireNamespace("glmnet", quietly = TRUE)) {
      cv <- glmnet::cv.glmnet(X[tr, ], y[tr], family = "binomial", alpha = 0.5, nfolds = 5)
      p <- as.numeric(predict(cv, newx = X[te, ], s = "lambda.min", type = "response"))
    } else next
    aucs[f] <- auc1(p, y[te])
  }
  c(mean = mean(aucs), sd = sd(aucs), folds = paste(round(aucs, 3), collapse = ","))
}

scenarios <- list(
  list(name = "miss0.3_winsor", miss = 0.3, winsor = TRUE, uric = TRUE),
  list(name = "miss0.5_winsor", miss = 0.5, winsor = TRUE, uric = TRUE),
  list(name = "miss0.7_winsor", miss = 0.7, winsor = TRUE, uric = TRUE),
  list(name = "miss0.5_nowinsor", miss = 0.5, winsor = FALSE, uric = TRUE),
  list(name = "miss0.5_noUric", miss = 0.5, winsor = TRUE, uric = FALSE),
  list(name = "miss0.85_winsor", miss = 0.85, winsor = TRUE, uric = TRUE)
)

cat("==== Scenario probe (holdout 70/30, seed=42) ====\n")
for (sc in scenarios) {
  pr <- prep_X(d, y, miss_max = sc$miss, do_winsor = sc$winsor, keep_uric = sc$uric)
  cat(sprintf("\n[%s] nvar=%d\n", sc$name, pr$nvar))
  for (m in c("glmnet", "xgb", "rf")) {
    a <- tryCatch(eval_holdout(pr$X, pr$y, seed = 42, method = m), error = function(e) NA)
    cat(sprintf("  holdout %-6s AUC=%.3f\n", m, a))
  }
  cv <- tryCatch(eval_cv5(pr$X, pr$y, method = "xgb"), error = function(e) c(mean = NA))
  cat(sprintf("  xgb 5fold CV mean=%s sd=%s folds=%s\n", cv["mean"], cv["sd"], cv["folds"]))
}

## 专门：只用高信息低缺失 + Age/Race，强正则 XGB
pr <- prep_X(d, y, 0.05, TRUE, TRUE)
keep <- intersect(c("UA_CR", "UricAcid", "ALT", "Hematocrit", "RBC", "Hemoglobin", "Age", "Creatinine", "WBC", "PlateletCount", "AST", "RDW",
                    grep("^Race_", colnames(pr$X), value = TRUE)), colnames(pr$X))
X2 <- pr$X[, keep, drop = FALSE]
cat("\n==== Compact feature set (", ncol(X2), ") ====\n")
print(colnames(X2))
for (seed in c(1, 7, 42, 99, 123)) {
  cat(sprintf("seed=%3d  glmnet=%.3f  xgb=%.3f  rf=%.3f\n", seed,
              eval_holdout(X2, y, seed, "glmnet"),
              eval_holdout(X2, y, seed, "xgb"),
              eval_holdout(X2, y, seed, "rf")))
}
cv <- eval_cv5(X2, y, method = "xgb")
cat("compact xgb CV:", paste(names(cv), cv, sep = "=", collapse = " "), "\n")

## 乐观上限：把高缺失但单因素好的变量也硬插补进来
hi <- c("NeutrophilCount", "LD", "CalciumTotal", "TotalCo2", "PT", "PCO2", "UreaNitrogen", "Potassium", "INR")
hi <- intersect(hi, names(d))
pr3 <- prep_X(d, y, 0.95, TRUE, TRUE)
cat("\n==== Wide miss0.95 nvar=", pr3$nvar, " ====\n")
cat(sprintf("holdout glmnet=%.3f xgb=%.3f rf=%.3f\n",
            eval_holdout(pr3$X, y, 42, "glmnet"),
            eval_holdout(pr3$X, y, 42, "xgb"),
            eval_holdout(pr3$X, y, 42, "rf")))
cv <- eval_cv5(pr3$X, y, method = "xgb")
cat("wide xgb CV:", paste(names(cv), cv, sep = "=", collapse = " "), "\n")
