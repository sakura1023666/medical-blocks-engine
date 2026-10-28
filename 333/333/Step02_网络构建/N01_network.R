rm(list = ls()); gc()
################################################################################
# N01_network.R —— Step02 网络构建(两版):
#   pcor       = 全偏相关(不稀疏, Fig1 用, 跨社区边全显示)
#   EBICglasso = LASSO+EBIC 稀疏(分析用, 拓扑指标 Betweenness/Closeness/Barrat/Onnela 有效)
# 节点: 统一 13(8 抑郁 + 5 MetS); MetS_3/4/5(TG/SBP/Glu) log.  估计: Pearson → nearPD → (pcor|EBICglasso γ=0.5).
# 输出: core_<method>_<cohort>.RData + edgeweight_<method>_<cohort>.csv + Fig1_<method>_<cohort>_network.{pdf/svg/png}
################################################################################
args <- commandArgs(trailingOnly = FALSE)
fa <- grep("^--file=", args, value = TRUE)
if (length(fa) > 0) setwd(normalizePath(dirname(sub("^--file=", "", fa[1])), mustWork = FALSE))
cat("工作目录:", getwd(), "\n"); options(width = 220)
suppressPackageStartupMessages({ library(bootnet); library(qgraph); library(mgm) })

DATA_DIR <- normalizePath(file.path(dirname(getwd()), "Step01"), mustWork = FALSE)  # ../Step01
FIG_DIR <- TAB_DIR <- getwd()   # 结果直接输出到 Step02/ 下
cat("数据目录:", DATA_DIR, "\n")

COHORTS <- c("CHARLS","ELSA"); EBIC_GAMMA <- 0.5
UNIFIED <- list(
  list(name="Felt Depressed",           CHARLS=c(dc011="Felt Depressed"),             ELSA=c(PScedA="Felt Depressed")),
  list(name="Everything Was an Effort", CHARLS=c(dc012="Everything Was an Effort"),   ELSA=c(PScedB="Everything Was an Effort")),
  list(name="Restless Sleep",           CHARLS=c(dc015="Restless Sleep"),             ELSA=c(PScedC="Restless Sleep")),
  list(name="Happy [POS]",              CHARLS=c(dc016="Happy [POS]"),                ELSA=c(PScedD="Happy [POS]")),
  list(name="Positive Mindset [POS]",   CHARLS=c(dc013="Hopeful About Future [POS]"), ELSA=c(PScedF="Enjoyed Life [POS]")),
  list(name="Negative Mindset",         CHARLS=c(dc014="Felt Fearful"),               ELSA=c(PScedG="Felt Sad")),
  list(name="Felt Lonely",              CHARLS=c(dc017="Felt Lonely"),                ELSA=c(PScedE="Felt Lonely")),
  list(name="Could Not Get Going",      CHARLS=c(dc018="Could Not Get Going"),        ELSA=c(PScedH="Could Not Get Going")))
METS_RAW <- c(waist_cm="Waist Circumference (cm)", hdl_mgdl="HDL-Cholesterol (mg/dL)",
              tg_mgdl="Triglycerides (mg/dL)", meanSBP="Systolic Blood Pressure (mmHg)",
              glu_mgdl="Fasting Glucose (mg/dL)")
LOG_METS <- c("tg_mgdl","meanSBP","glu_mgdl")

build_nodes <- function(coh) {
  e <- new.env(); load(file.path(DATA_DIR, paste0("D01_AfterMI_Data_", coh, ".RData")), envir = e)
  df <- e$data_imp
  dep_map  <- setNames(lapply(UNIFIED, `[[`, coh), sapply(UNIFIED, `[[`, "name"))
  dep_cols <- unname(sapply(dep_map, names)); mets_cols <- names(METS_RAW)
  cols <- c(dep_cols, mets_cols)
  dat <- df[complete.cases(df[, cols]), cols, drop = FALSE]
  for (i in seq_along(dep_cols)) {
    cn <- dep_cols[i]; others <- rowSums(dat[, dep_cols[-i], drop=FALSE], na.rm=TRUE)
    r <- cor(dat[[cn]], others, use="pairwise.complete.obs")
    if (!is.na(r) && r < 0) dat[[cn]] <- max(dat[[cn]], na.rm=TRUE) - dat[[cn]]
  }
  for (cn in intersect(LOG_METS, mets_cols))
    dat[[cn]] <- if (any(dat[[cn]] <= 0, na.rm=TRUE)) log1p(dat[[cn]]) else log(dat[[cn]])
  list(dat=dat, ndep=length(dep_cols), nmets=length(mets_cols),
       Label=c(paste0("Depression_",seq_along(dep_cols)), paste0("MetS_",seq_along(mets_cols))),
       Items=c(names(dep_map), unname(METS_RAW)), N=nrow(dat))
}

# 两版估计器(Pearson → nearPD → pcor 或 EBICglasso), 自包含闭包
est_pcor <- local({ function(data, verbose=TRUE, ...) {
  S <- cor(data)
  evmin <- min(eigen(S, symmetric=TRUE, only.values=TRUE)$values)
  if (!is.na(evmin) && evmin <= 1e-8) S <- as.matrix(Matrix::nearPD(S, corr=TRUE, keepDiag=TRUE)$mat)
  K <- solve(S); P <- -cov2cor(K); diag(P) <- 0
  list(graph=P, intercepts=rep(0, ncol(data)), results=list())
}})
est_ebic <- local({ .g <- EBIC_GAMMA; function(data, verbose=TRUE, ...) {
  S <- cor(data)
  evmin <- min(eigen(S, symmetric=TRUE, only.values=TRUE)$values)
  if (!is.na(evmin) && evmin <= 1e-8) S <- as.matrix(Matrix::nearPD(S, corr=TRUE, keepDiag=TRUE)$mat)
  list(graph=qgraph::EBICglasso(S, nrow(data), gamma=.g, threshold=FALSE), intercepts=rep(0, ncol(data)), results=list())
}})
pred_r2 <- function(dat) {
  P <- ncol(dat); M <- data.matrix(dat)
  tryCatch({
    fit <- mgm::mgm(M, type=rep("g",P), levels=rep(1,P), k=2, lambdaSel="EBIC", ruleReg="AND", verb=FALSE)
    setNames(predict(fit, M, errorCon=c("RMSE","R2"))$errors$R2, colnames(dat))
  }, error=function(e) rep(NA_real_, P))
}
save_plot <- function(stem, plotfun, width=11, height=8, res=300) {
  cairo_pdf(file.path(FIG_DIR, paste0(stem,".pdf")), width=width, height=height, family="sans"); plotfun(); dev.off()
  svg(file.path(FIG_DIR, paste0(stem,".svg")), width=width, height=height); plotfun(); dev.off()
  png(file.path(FIG_DIR, paste0(stem,".png")), width=width, height=height, units="in", res=res); plotfun(); dev.off()
  cat("  [图]", stem, "\n")
}

for (m in c("pcor", "EBIC")) {
  est <- if (m == "pcor") est_pcor else est_ebic
  cat("\n########## 方法:", m, " ##########\n")
  for (coh in COHORTS) {
    L <- build_nodes(coh); dat <- L$dat; P <- ncol(dat)
    net <- estimateNetwork(dat, fun=est)
    r2  <- pred_r2(dat)
    save(L, net, r2, file=file.path(FIG_DIR, paste0("core_", m, "_", coh, ".RData")))
    ew <- net$graph; rownames(ew) <- colnames(ew) <- L$Label
    write.csv(round(ew,3), file.path(TAB_DIR, paste0("edgeweight_", m, "_", coh, ".csv")), row.names=TRUE)
    groups <- list(Depression = 1:L$ndep, MetS = (L$ndep+1):P)
    short  <- c(paste0("D", 1:L$ndep), paste0("M", 1:L$nmets))
    save_plot(paste0("Fig1_", m, "_", coh, "_network"), function() {
      qgraph::qgraph(net$graph, layout="spring", groups=groups, palette="colorblind",
        posCol="#0B6ECC", negCol="#CC2A2A", negDashed=TRUE, pie=r2, vsize=7,
        labels=short, nodeNames=L$Items, legend=TRUE, legend.cex=0.5, label.cex=0.95,
        title=paste0(coh, " (", m, ") N=", L$N), mar=c(2,2,4,2))
    })
    cat("  ", coh, "[", m, "] 非零边:", sum(net$graph != 0)/2, "/78 | R²均:", round(mean(r2, na.rm=TRUE),3), "\n")
  }
}
cat("\n==================== Step02 完成(两版网络) ====================\n")
