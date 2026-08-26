Sys.setenv(MEDICAL_BLOCKS_ROOT="E:/01block/01Block-new-Final", MEDICAL_BLOCKS_SKIP_WIN_R="1")
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT")
study <- "G:/02block_result/27_eclampsia/small sample prediction_39780007"
# 读清洗后数据
load(file.path(study, "Data/mimic/dabiao_clean.RData"))
d <- dabiao
cat("raw dim:", nrow(d), ncol(d), "\n")
# DN
dn <- d$DN
cat("DN:\n"); print(table(dn, useNA="ifany"))
# drop missing DN
d <- d[!is.na(d$DN) & d$DN %in% c("Case","Control",0,1,"0","1"), ]
y <- ifelse(as.character(d$DN) %in% c("Case","1"), 1L, 0L)
cat("n after DN filter:", nrow(d), " events:", sum(y), "\n")

# compute UA_CR if needed
if (!"UA_CR" %in% names(d)) {
  ua <- d$UricAcid %||% d$Uric_Acid
  cr <- d$Creatinine
  if (!is.null(ua) && !is.null(cr)) d$UA_CR <- as.numeric(ua)/as.numeric(cr)
}
num <- names(d)[vapply(d, function(x) is.numeric(x) || is.integer(x), TRUE)]
drop <- c("ID","SEQN")
num <- setdiff(num, drop)
# AUC vs y for each numeric
auc1 <- function(x, y) {
  ok <- is.finite(x) & !is.na(y)
  if (sum(ok) < 50 || length(unique(y[ok]))<2) return(NA_real_)
  x <- x[ok]; y <- y[ok]
  # Mann-Whitney AUC
  r <- rank(x)
  n1 <- sum(y==1); n0 <- sum(y==0)
  if (n1<5 || n0<5) return(NA_real_)
  (sum(r[y==1]) - n1*(n1+1)/2) / (n1*n0)
}
res <- data.frame(var=num, n=NA_integer_, miss=NA_real_, auc=NA_real_, auc_abs=NA_real_, stringsAsFactors=FALSE)
for (i in seq_along(num)) {
  x <- suppressWarnings(as.numeric(d[[num[i]]]))
  res$n[i] <- sum(is.finite(x))
  res$miss[i] <- mean(!is.finite(x))
  a <- auc1(x, y)
  res$auc[i] <- a
  res$auc_abs[i] <- max(a, 1-a, na.rm=FALSE)
}
res <- res[order(-res$auc_abs, res$miss), ]
cat("\n==== Top univariate AUC (abs) ====\n")
print(utils::head(res, 25), row.names=FALSE)

# extreme values on top vars + UA_CR
vars_chk <- unique(c("UA_CR","ALT","Hematocrit","Age", head(res$var[res$auc_abs>=0.58], 10)))
vars_chk <- intersect(vars_chk, names(d))
cat("\n==== Extreme check (1%/99%) ====\n")
for (v in vars_chk) {
  x <- suppressWarnings(as.numeric(d[[v]]))
  qs <- stats::quantile(x, c(0.01,0.05,0.5,0.95,0.99), na.rm=TRUE)
  cat(sprintf("%s n=%d  p01=%.3g p99=%.3g\n", v, sum(is.finite(x)), qs[1], qs[5]))
}

# quick glmnet CV on more features (top 15 by auc + UA_CR)
cand <- unique(c("UA_CR", head(res$var[is.finite(res$auc_abs) & res$miss < 0.4], 20)))
cand <- intersect(cand, names(d))
cat("\n==== Quick CV probe candidates (", length(cand), ") ====\n")
print(cand)
mm <- as.data.frame(lapply(d[cand], function(z) suppressWarnings(as.numeric(z))))
# simple median impute
for (j in seq_along(mm)) mm[[j]][!is.finite(mm[[j]])] <- stats::median(mm[[j]], na.rm=TRUE)
ok <- complete.cases(mm) & !is.na(y)
X <- as.matrix(mm[ok, , drop=FALSE]); yy <- y[ok]
set.seed(123)
# 5-fold CV logistic
k <- 5
fold <- sample(rep(1:k, length.out=nrow(X)))
aucs <- numeric(k)
for (f in 1:k) {
  tr <- fold!=f; te <- fold==f
  fit <- suppressWarnings(glm(yy[tr] ~ ., data=as.data.frame(X[tr,,drop=FALSE]), family=binomial()))
  p <- as.numeric(predict(fit, newdata=as.data.frame(X[te,,drop=FALSE]), type="response"))
  aucs[f] <- auc1(p, yy[te])
}
cat("logistic CV AUC mean=", mean(aucs), " sd=", sd(aucs), " folds=", paste(round(aucs,3), collapse=","), "\n")

if (requireNamespace("glmnet", quietly=TRUE)) {
  set.seed(123)
  cv <- glmnet::cv.glmnet(X, yy, family="binomial", alpha=1, nfolds=5, type.measure="auc")
  cat("glmnet CV max AUC=", max(cv$cvm), " at lambda.min\n")
  # holdout 70/30 once
  set.seed(42)
  idx <- sample(seq_len(nrow(X)), size=floor(0.7*nrow(X)))
  cv2 <- glmnet::cv.glmnet(X[idx,], yy[idx], family="binomial", alpha=1, nfolds=5, type.measure="auc")
  p <- as.numeric(predict(cv2, newx=X[-idx,], s="lambda.min", type="response"))
  cat("glmnet holdout AUC=", auc1(p, yy[-idx]), " ntrain=", length(idx), " ntest=", nrow(X)-length(idx), "\n")
}
