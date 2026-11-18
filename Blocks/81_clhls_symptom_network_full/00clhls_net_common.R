###############################################################################
#  CLHLS 症状网络公共函数
#  算法对齐既往网络脚本 Step02–Step07：Pearson → nearPD → pcor / EBICglasso(γ=0.5)
#  节点、条目名、社区来自 config$clhls_network，不在本文件写死某一课题的列名。
###############################################################################

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x
}

clhls_net_spec <- function(bl) {
  items <- bl$node_items
  if (is.null(items) || !length(items)) {
    stop("config$clhls_network$node_items 未设置（命名向量：列名 = 条目说明）", call. = FALSE)
  }
  if (is.list(items)) items <- unlist(items, use.names = TRUE)
  nm <- names(items)
  if (is.null(nm) || any(!nzchar(nm))) {
    stop("node_items 的名字必须是数据列名", call. = FALSE)
  }
  if (anyDuplicated(nm)) stop("node_items 列名重复", call. = FALSE)
  comm <- bl$communities
  if (is.null(comm) || !length(comm) || is.null(names(comm)) || any(!nzchar(names(comm)))) {
    stop("config$clhls_network$communities 未设置（命名列表：社区名 = 列名向量）", call. = FALSE)
  }
  groups <- lapply(comm, function(cols) {
    cols <- as.character(unlist(cols, use.names = FALSE))
    idx <- match(cols, nm)
    if (anyNA(idx)) {
      stop("communities 中有列不在 node_items: ",
           paste(cols[is.na(idx)], collapse = ", "), call. = FALSE)
    }
    idx
  })
  covered <- unlist(groups, use.names = FALSE)
  if (length(covered) != length(nm) || anyDuplicated(covered)) {
    stop("communities 必须不重不漏地覆盖全部 node_items", call. = FALSE)
  }
  short <- bl$short_labels
  if (is.null(short) || !length(short)) {
    short <- nm
  } else {
    short <- as.character(unlist(short, use.names = FALSE))
    if (length(short) != length(nm)) {
      stop("short_labels 长度须等于节点数", call. = FALSE)
    }
  }
  # 展示层统一：节点直接以短标签（如 I1/C7）为分析名，避免 Fig2/3/S* 与表里
  # 残留 dev1/circ7 这类编程列名（pub_no_underscore_display 铁律）。
  # 数据列名保留在 nodes_raw，读入后由 clhls_net_rename_nodes 改名。
  list(nodes = short, nodes_raw = nm,
       items = stats::setNames(as.character(items), short),
       groups = groups, short = short)
}

clhls_net_rename_nodes <- function(df, cfg) {
  raw <- cfg$nodes_raw %||% cfg$nodes
  if (identical(raw, cfg$nodes)) return(df)
  # 定向重跑时数据里可能已有旧短标签列，先删掉避免命名冲突
  stale <- intersect(cfg$nodes, names(df))
  if (length(stale)) df[, stale, drop = FALSE] <- NULL
  idx <- match(raw, names(df))
  if (anyNA(idx)) {
    stop("数据缺少节点列: ", paste(raw[is.na(idx)], collapse = ", "), call. = FALSE)
  }
  names(df)[idx] <- cfg$nodes
  df
}

clhls_net_cfg <- function(ctx) {
  bl <- ctx$config$clhls_network %||% list()
  spec <- clhls_net_spec(bl)
  n_env <- suppressWarnings(as.integer(Sys.getenv("CLHLS_NBOOTS", "")))
  nct_env <- suppressWarnings(as.integer(Sys.getenv("CLHLS_NCT_IT", "")))
  spec$cohort_csv <- as.character(bl$cohort_csv %||% "")[1L]
  spec$ebic_gamma <- as.numeric(bl$ebic_gamma %||% 0.5)
  spec$n_boots <- if (!is.na(n_env) && n_env > 0L) n_env else as.integer(bl$n_boots %||% 1000L)
  spec$n_cores <- as.integer(bl$n_cores %||% max(1L, parallel::detectCores() - 1L))
  spec$nct_it <- if (!is.na(nct_env) && nct_env > 0L) nct_env else as.integer(bl$nct_it %||% 1000L)
  spec$sex_col <- as.character(bl$sex_col %||% "sex")[1L]
  spec$male_code <- as.character(bl$male_code %||% "1")[1L]
  spec$female_code <- as.character(bl$female_code %||% "2")[1L]
  spec$figure1_stem <- as.character(bl$figure1_stem %||% "Figure 1. Symptom network of depression and anxiety")[1L]
  spec$table1_stem <- as.character(bl$table1_stem %||% "Table 1. Basic information of depression-anxiety symptoms")[1L]
  spec$covariates <- as.character(unlist(bl$covariates %||% character(0), use.names = FALSE))
  # 相关矩阵：pearson（默认，兼容旧课题）| spearman（案例原码常见）
  cm <- tolower(as.character(bl$cor_method %||% "pearson")[1L])
  if (!cm %in% c("pearson", "spearman")) {
    stop("clhls_network$cor_method 仅支持 pearson / spearman，收到: ", cm, call. = FALSE)
  }
  spec$cor_method <- cm
  # pairwise.complete.obs 对齐文献 pairwise；完整病例时与 complete 等价
  cu <- as.character(bl$cor_use %||% "pairwise.complete.obs")[1L]
  spec$cor_use <- cu
  spec
}

clhls_net_out_dirs <- function(ctx) {
  root_out <- ctx$config$project$output_dir %||% "Output/CLHLS_Symptom_Network"
  if (!grepl("^(/|[A-Za-z]:)", root_out)) {
    root_out <- file.path(ctx$config$project$root %||% getwd(), root_out)
  }
  # /mnt/g/... → G:/...，避免 Windows R 写成 E:/mnt/g/...
  root_out <- clhls_net_win_path(root_out)
  fig <- file.path(root_out, "Figures")
  tab <- file.path(root_out, "Tables")
  rdata <- file.path(root_out, "rdata")
  dir.create(fig, recursive = TRUE, showWarnings = FALSE)
  dir.create(tab, recursive = TRUE, showWarnings = FALSE)
  dir.create(rdata, recursive = TRUE, showWarnings = FALSE)
  options(clhls_net_root = ctx$config$project$root %||% getwd())
  list(root = root_out, fig = fig, tab = tab, rdata = rdata)
}

clhls_net_win_path <- function(p) {
  p <- gsub("\\\\", "/", as.character(p)[1L])
  if (grepl("^/mnt/[a-zA-Z]/", p)) {
    paste0(toupper(substr(p, 6, 6)), ":", substring(p, 7))
  } else p
}

clhls_net_read_cohort <- function(path, nodes) {
  path <- clhls_net_win_path(path)
  if (!file.exists(path)) stop("找不到队列文件: ", path, call. = FALSE)
  df <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  miss <- setdiff(nodes, names(df))
  if (length(miss)) stop("队列缺少节点列: ", paste(miss, collapse = ", "), call. = FALSE)
  df
}

clhls_net_node_matrix <- function(df, nodes) {
  mat <- as.data.frame(lapply(df[nodes], function(x) {
    if (is.factor(x)) x <- as.character(x)
    as.numeric(x)
  }), check.names = FALSE)
  names(mat) <- nodes
  mat <- mat[stats::complete.cases(mat), , drop = FALSE]
  if (nrow(mat) < 30L) stop("完整节点样本 < 30", call. = FALSE)
  mat
}

#' 协变量残差化节点矩阵：每个节点对协变量做 OLS，取残差，再进 EBICglasso。
#' covs 为数据列名（数值/0-1）；完整病例 = 节点 ∪ 协变量 同时非缺失。
#' 返回仅含 nodes 列的 data.frame（残差），供 estimateNetwork / NCT 使用。
clhls_net_cov_mat <- function(df, nodes, covs) {
  if (!length(covs)) return(clhls_net_node_matrix(df, nodes))
  cols <- c(nodes, covs)
  miss <- setdiff(cols, names(df))
  if (length(miss)) stop("clhls_net_cov_mat: 数据缺协变量列 ", paste(miss, collapse = ", "), call. = FALSE)
  sub <- df[, cols, drop = FALSE]
  sub <- sub[stats::complete.cases(sub), , drop = FALSE]
  if (nrow(sub) < 30L) stop("协变量完整样本 < 30", call. = FALSE)
  Y <- data.matrix(sub[, nodes, drop = FALSE])
  X <- cbind(`.int` = 1, data.matrix(sub[, covs, drop = FALSE]))
  R <- Y
  for (j in seq_len(ncol(Y))) {
    co <- tryCatch(qr.coef(qr(X), Y[, j]), error = function(e) rep(NA_real_, ncol(X)))
    if (all(is.finite(co))) R[, j] <- Y[, j] - as.vector(X %*% co)
  }
  colnames(R) <- nodes
  attr(R, "n_cov") <- ncol(X) - 1L
  as.data.frame(R, check.names = FALSE)
}

clhls_net_cor_matrix <- function(data, method = "pearson", use = "pairwise.complete.obs") {
  method <- tolower(as.character(method %||% "pearson")[1L])
  use <- as.character(use %||% "pairwise.complete.obs")[1L]
  S <- stats::cor(as.matrix(data), method = method, use = use)
  # 非正定或缺失相关时兜底 nearPD（Spearman 秩相关偶发）
  if (any(!is.finite(S))) {
    S[!is.finite(S)] <- 0
    diag(S) <- 1
  }
  evmin <- tryCatch(
    min(eigen(S, symmetric = TRUE, only.values = TRUE)$values),
    error = function(e) NA_real_
  )
  if (is.na(evmin) || evmin <= 1e-8) {
    if (!requireNamespace("Matrix", quietly = TRUE)) {
      stop("需要 Matrix::nearPD 修正非正定相关矩阵", call. = FALSE)
    }
    S <- as.matrix(Matrix::nearPD(S, corr = TRUE, keepDiag = TRUE)$mat)
  }
  S
}

# 估计器闭包内联相关矩阵：bootnet 并行 worker 序列化后找不到全局辅助函数
clhls_net_est_pcor <- function(method = "pearson", use = "pairwise.complete.obs") {
  force(method); force(use)
  function(data, verbose = TRUE, ...) {
    S <- stats::cor(as.matrix(data), method = method, use = use)
    if (any(!is.finite(S))) {
      S[!is.finite(S)] <- 0
      diag(S) <- 1
    }
    evmin <- tryCatch(
      min(eigen(S, symmetric = TRUE, only.values = TRUE)$values),
      error = function(e) NA_real_
    )
    if (is.na(evmin) || evmin <= 1e-8) {
      if (!requireNamespace("Matrix", quietly = TRUE)) {
        stop("需要 Matrix::nearPD 修正非正定相关矩阵", call. = FALSE)
      }
      S <- as.matrix(Matrix::nearPD(S, corr = TRUE, keepDiag = TRUE)$mat)
    }
    K <- solve(S)
    P <- -stats::cov2cor(K)
    diag(P) <- 0
    list(graph = P, intercepts = rep(0, ncol(data)), results = list())
  }
}

clhls_net_est_ebic <- function(gamma, method = "pearson", use = "pairwise.complete.obs") {
  force(gamma); force(method); force(use)
  function(data, verbose = TRUE, ...) {
    S <- stats::cor(as.matrix(data), method = method, use = use)
    if (any(!is.finite(S))) {
      S[!is.finite(S)] <- 0
      diag(S) <- 1
    }
    evmin <- tryCatch(
      min(eigen(S, symmetric = TRUE, only.values = TRUE)$values),
      error = function(e) NA_real_
    )
    if (is.na(evmin) || evmin <= 1e-8) {
      if (!requireNamespace("Matrix", quietly = TRUE)) {
        stop("需要 Matrix::nearPD 修正非正定相关矩阵", call. = FALSE)
      }
      S <- as.matrix(Matrix::nearPD(S, corr = TRUE, keepDiag = TRUE)$mat)
    }
    list(
      graph = qgraph::EBICglasso(S, nrow(data), gamma = gamma, threshold = FALSE),
      intercepts = rep(0, ncol(data)),
      results = list()
    )
  }
}

clhls_net_pred_r2 <- function(dat) {
  P <- ncol(dat)
  M <- data.matrix(dat)
  tryCatch({
    fit <- mgm::mgm(M, type = rep("g", P), levels = rep(1, P), k = 2,
                    lambdaSel = "EBIC", ruleReg = "AND", verb = FALSE)
    setNames(predict(fit, M, errorCon = c("RMSE", "R2"))$errors$R2, colnames(dat))
  }, error = function(e) {
    warning("mgm R2 失败: ", conditionMessage(e))
    setNames(rep(NA_real_, P), colnames(dat))
  })
}

clhls_net_fit_ebic <- function(dat, gamma, method = "pearson", use = "pairwise.complete.obs") {
  bootnet::estimateNetwork(
    dat, fun = clhls_net_est_ebic(gamma, method = method, use = use)
  )
}

clhls_net_fit_pcor <- function(dat, method = "pearson", use = "pairwise.complete.obs") {
  bootnet::estimateNetwork(
    dat, fun = clhls_net_est_pcor(method = method, use = use)
  )
}

clhls_net_save_pdf <- function(path, plotfun, width = 11, height = 8) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  grDevices::cairo_pdf(path, width = width, height = height, family = "sans")
  on.exit(try(grDevices::dev.off(), silent = TRUE), add = TRUE)
  plotfun()
  invisible(path)
}

clhls_net_write_table <- function(df, path_stem) {
  xlsx <- paste0(path_stem, ".xlsx")
  dir.create(dirname(xlsx), recursive = TRUE, showWarnings = FALSE)
  csv <- paste0(path_stem, ".csv")
  if (file.exists(csv)) unlink(csv)
  root <- getOption("clhls_net_root", "")
  if (!nzchar(root)) root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", "")
  if (!exists("sci_xlsx_single_header_booktabs", mode = "function")) {
    if (!nzchar(root)) stop("clhls_net_write_table: 找不到项目根目录", call. = FALSE)
    source(file.path(root, "R/utils.R"), local = FALSE)
  }
  sci_xlsx_single_header_booktabs(
    filepath = xlsx,
    title = basename(path_stem),
    df_body = df,
    sheet = "Table"
  )
  invisible(xlsx)
}

clhls_net_z <- function(x) {
  x <- as.numeric(x)
  s <- stats::sd(x, na.rm = TRUE)
  if (is.na(s) || s == 0) return(rep(0, length(x)))
  z <- (x - mean(x, na.rm = TRUE)) / s
  z[!is.finite(z)] <- NA_real_
  z
}

clhls_net_sex_code <- function(x) sub("\\.0$", "", as.character(x))

clhls_net_sex_split <- function(df, cfg) {
  sx <- clhls_net_sex_code(df[[cfg$sex_col]])
  list(
    Male = df[sx == clhls_net_sex_code(cfg$male_code), , drop = FALSE],
    Female = df[sx == clhls_net_sex_code(cfg$female_code), , drop = FALSE]
  )
}

clhls_net_load_core <- function(dirs, method = "EBIC") {
  f <- file.path(dirs$rdata, sprintf("core_%s_CLHLS.RData", method))
  if (!file.exists(f)) stop("缺少 ", f, "，请先跑 clhls_network", call. = FALSE)
  e <- new.env(parent = emptyenv())
  load(f, envir = e)
  e
}

clhls_net_source_common <- function(ctx) {
  root <- ctx$config$project$root %||% getwd()
  common <- file.path(root, "Blocks/81_clhls_symptom_network_full/00clhls_net_common.R")
  if (!file.exists(common)) stop("缺少公共文件: ", common, call. = FALSE)
  source(common, local = FALSE)
}

clhls_net_require_pkgs <- function() {
  need <- c("bootnet", "qgraph", "mgm", "igraph", "networktools",
            "NetworkComparisonTest", "ggplot2", "Matrix", "openxlsx")
  miss <- need[!vapply(need, requireNamespace, logical(1), quietly = TRUE)]
  if (length(miss)) {
    stop("缺少 R 包: ", paste(miss, collapse = ", "),
         "。请在 R-4.5.1 中安装。", call. = FALSE)
  }
}
