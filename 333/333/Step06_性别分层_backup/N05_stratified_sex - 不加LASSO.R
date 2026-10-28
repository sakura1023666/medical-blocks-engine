rm(list = ls()); gc()
################################################################################
# N05_stratified_sex.R —— Step06 性别分层分析 (仅保留非正则化全偏相关网络图)
# 按 Gender (Female / Male) 分层, 对每个 队列 × 性别 子集:
#   1) 构建 13 节点 (8 抑郁 + 5 MetS) 全偏相关网络 (PCOR, 无 LASSO/EBIC 正则化);
#   2) 保存网络图 (groups/spring, 蓝=正/红=负; 风格同 Fig1).
# 输入: ../Step01_基线/D01_AfterMI_Data_<cohort>.RData  (含 Gender)
# 输出: Network_<cohort>_<sex>.pdf
################################################################################
args <- commandArgs(trailingOnly = FALSE)
fa <- grep("^--file=", args, value = TRUE)
if (length(fa) > 0) setwd(normalizePath(dirname(sub("^--file=", "", fa[1])), mustWork = FALSE))
cat("工作目录:", getwd(), "\n"); options(width = 220)
suppressPackageStartupMessages({ library(bootnet); library(qgraph) })

DATA_DIR <- normalizePath(file.path(dirname(getwd()), "Step01_基线"), mustWork = FALSE)
COHORTS  <- c("CHARLS","ELSA"); SEXES <- c("Female","Male")

# ---- 节点定义 (与 Step02 完全一致) ----
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

# build_nodes: 读 MI 数据 → 按性别分层 → 选 13 节点列 → 完整病例 → 正向条目校正 + MetS log
build_nodes <- function(coh, sex) {
  e <- new.env(); load(file.path(DATA_DIR, paste0("D01_AfterMI_Data_", coh, ".RData")), envir = e)
  df <- e$data_imp
  df <- df[which(as.character(df$Gender) == sex), , drop = FALSE]             # ★ 性别分层
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

# ★ 非正则化的全偏相关估计器 (PCOR)
est_pcor <- local({ function(data, verbose=TRUE, ...) {
  S <- cor(data)
  evmin <- min(eigen(S, symmetric=TRUE, only.values=TRUE)$values)
  if (!is.na(evmin) && evmin <= 1e-8) S <- as.matrix(Matrix::nearPD(S, corr=TRUE, keepDiag=TRUE)$mat)
  K <- solve(S)
  P <- -cov2cor(K)
  diag(P) <- 0
  list(graph=P, intercepts=rep(0, ncol(data)), results=list())
}})

save_plot <- function(stem, plotfun, width=11, height=8, res=300) {
  cairo_pdf(paste0(stem,".pdf"), width=width, height=height, family="sans"); plotfun(); dev.off()
  # svg(paste0(stem,".svg"),       width=width, height=height); plotfun(); dev.off()
  # png(paste0(stem,".png"),       width=width, height=height, units="in", res=res); plotfun(); dev.off()
  cat("  [图]", stem, "\n")
}

for (coh in COHORTS) for (sx in SEXES) {
  cat("\n==================== ", coh, " / ", sx, " ====================\n")
  L <- build_nodes(coh, sx); dat <- L$dat; P <- ncol(dat)
  
  # ★ 估计网络 (不带正则化)
  net <- estimateNetwork(dat, fun=est_pcor)
  
  W <- net$graph; items <- L$Items
  groups <- list(Depression = 1:L$ndep, MetS = (L$ndep+1):P)
  short  <- c(paste0("D", 1:L$ndep), paste0("M", 1:L$nmets))
  
  # ★ 仅输出保存网络图
  save_plot(paste0("Network_", coh, "_", sx), function() {
    qgraph::qgraph(W, layout="spring", groups=groups, palette="colorblind",
                   posCol="#0B6ECC", negCol="#CC2A2A", negDashed=TRUE, vsize=7,
                   labels=short, nodeNames=items, legend=TRUE, legend.cex=0.5, label.cex=0.95,
                   title=paste0(coh, " ", sx, " (pcor) N=", L$N), mar=c(2,2,4,2))
  })
  
  cat("  ", coh, sx, "N=", L$N, "| 边数:", sum(W!=0)/2, "/78\n")
}
cat("\n==================== Step06 分层网络图绘制完成 ====================\n")