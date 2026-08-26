###############################################################################
#  bkmr_fit — BKMR 贝叶斯核机器回归模型并行拟合（bkmrhat + future）
#
#  register_block: "bkmr_fit"
#  典型流水线: wqs_environment → bkmr_fit → bkmr_analysis
#
#  功能：
#    准备结局向量 y、标准化暴露矩阵 Z（z-score）、数值协变量矩阵 X；
#    用 bkmrhat::kmbayes_parallel 多链并行 MCMC 拟合；
#    总迭代次数 = nchains × iter（建议 10000+）。
#
#  包依赖：
#    bkmr（CRAN）、bkmrhat（GitHub: jpkeller/bkmrhat）、future
#    install.packages("bkmr")
#    remotes::install_github("jpkeller/bkmrhat")
#
#  # ── Bug 修复说明（相对原 C01_BKMR_Analysis.R / C02_BKMR_nohup.R）──────────
#  Bug 1: BKMR_dat[,-1] 按位置删 SEQN → 改为 BKMR_dat$SEQN <- NULL
#  Bug 2: mutate 中 if(col %in% colnames) case_when(...) 在条件 FALSE 时返回
#         NULL，dplyr 会删除已有列；且原代码含 'Yes '/'No ' 尾随空格数据问题；
#         修复: 改用通用 .bkmr38_encode_covariates()：
#              非数值列自动 as.numeric(as.factor(trimws(x)))，
#              并支持 covariate_encoding 自定义映射
#  Bug 3: C02 中 n <- 100 硬编码 100 workers → 改为 min(nchains, availableCores)
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data         = ctx$data$imputed %||% ctx$data$cleaned
#  require_ctx_results  = select_vocs_final（或 select_vocs）
#  可选 ctx_results     = final_features / Model2Factors
#
#  # ── 配置 config$bkmr_fit ─────────────────────────────────────────────────
#  bkmr_fit = list(
#    select_vocs         = NULL,   # VOC 列名；NULL = ctx$results$select_vocs_final
#    covariates          = NULL,   # 协变量；NULL = ctx$results$final_features
#    outcome_col         = NULL,   # 结局列名；NULL = config$data$outcome_column
#    analysis_group      = NULL,   # 病例组标签（编码为 1）
#    reference_group     = NULL,   # 对照组标签（编码为 0）
#    nchains             = NULL,   # NULL = floor(detectCores()/2)，最小 2
#    iter                = 1000L,  # 每链 MCMC 迭代次数（总 = nchains × iter）
#    family              = "binomial",
#    seed                = 123L,
#    varsel              = TRUE,   # 是否做变量选择（PIP）
#    est_h               = TRUE,   # 是否估计暴露-反应函数 h(z)
#    covariate_encoding  = NULL    # 自定义编码: list(Gender = c(Male=1, Female=2))
#  ),
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  写: ctx$results$fit_bkmr          — kmbayes_parallel 拟合结果列表
#      ctx$results$bkmr_y            — 结局向量 (0/1)
#      ctx$results$bkmr_Z            — 标准化暴露矩阵
#      ctx$results$bkmr_X            — 数值协变量 data.frame
#      ctx$results$bkmr_select_vocs  — 本次 BKMR 使用的 VOC 列名
###############################################################################

# ── 辅助：协变量数值编码（修复 Bug 2：通用 auto-encode + trimws 消除尾随空格）
.bkmr38_encode_covariates <- function(covar, encoding_map = NULL) {
  for (col in names(covar)) {
    x <- covar[[col]]

    if (!is.null(encoding_map) && col %in% names(encoding_map)) {
      # 用户自定义映射（命名向量：c("Male"=1, "Female"=2)）
      enc <- encoding_map[[col]]
      if (is.function(enc)) {
        covar[[col]] <- enc(x)
      } else {
        xc <- trimws(as.character(x))
        covar[[col]] <- suppressWarnings(as.numeric(enc[xc]))
      }
    } else if (!is.numeric(x)) {
      # 通用自动编码：trimws 消除尾随空格后 factor → numeric
      xc <- trimws(as.character(x))
      covar[[col]] <- as.numeric(as.factor(xc))
    }
  }

  # 最终确保全为数值，NA 设 0 并警告
  for (col in names(covar)) {
    if (!is.numeric(covar[[col]])) {
      covar[[col]] <- suppressWarnings(as.numeric(covar[[col]]))
    }
    n_na <- sum(is.na(covar[[col]]))
    if (n_na > 0L) {
      cli::cli_alert_warning("  协变量 [{col}] 含 {n_na} 个 NA，编码后将以 0 填充。")
      covar[[col]][is.na(covar[[col]])] <- 0
    }
  }
  covar
}

# ── Block 主函数 ──────────────────────────────────────────────────────────────
block_bkmr_fit <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(bkmr)
    library(bkmrhat)
    library(future)
    library(dplyr)
  })

  cfg    <- ctx$config
  bl_cfg <- cfg$bkmr_fit %||% list()

  # ── 读取数据 ─────────────────────────────────────────────────────────────
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    stop("bkmr_fit: 未找到数据，请先运行上游数据准备 block。")
  }

  outcome_col   <- as.character(bl_cfg$outcome_col    %||% cfg$data$outcome_column %||% "Group")
  analysis_grp  <- as.character(bl_cfg$analysis_group %||% cfg$project$analysis_group  %||% "Case")
  reference_grp <- as.character(bl_cfg$reference_group %||% cfg$project$reference_group %||% "Control")

  if (!outcome_col %in% names(data)) {
    stop("bkmr_fit: 结局列 '", outcome_col, "' 不在数据中。")
  }

  # ── 读取 VOC 和协变量（仅环境毒物）──────────────────────────────────────
  bl_select <- as.character(bl_cfg$select_vocs %||% character(0))
  if (exists("environment_resolve_mixture_vocs", mode = "function")) {
    resolved <- environment_resolve_mixture_vocs(
      ctx, data, cfg, "bkmr_fit", bl_select = bl_select
    )
    select_vocs <- resolved$vocs
    min_n <- resolved$min_n
    strict_glm <- isTRUE(resolved$strict_glm %||% TRUE)
  } else {
    select_vocs <- as.character(
      bl_select %||%
        ctx$results$select_vocs_final %||%
        ctx$results$select_vocs %||%
        character(0)
    )
    if (exists("environment_intersect_voc_only", mode = "function")) {
      select_vocs <- environment_intersect_voc_only(select_vocs, data, cfg)
    }
    select_vocs <- intersect(select_vocs, names(data))
    min_n <- if (exists("environment_min_mixture_n", mode = "function")) {
      environment_min_mixture_n(cfg, "bkmr_fit", 4L)
    } else {
      as.integer(bl_cfg$min_select_vocs %||% 4L)
    }
    strict_glm <- isTRUE(bl_cfg$strict_glm_vocs %||% TRUE)
  }
  if (!length(select_vocs)) {
    cli::cli_alert_warning("bkmr_fit: GLM 通过后无可用 VOC，跳过 BKMR。")
    ctx$results$bkmr_fit_skipped <- TRUE
    return(ctx)
  }
  min_bkmr <- as.integer(
    (cfg$environment_bkmr %||% list())$min_vocs_before_bkmr %||%
      bl_cfg$min_select_vocs %||% 3L
  )[1L]
  if (length(select_vocs) < min_bkmr) {
    cli::cli_alert_warning(
      "bkmr_fit: 到达 BKMR 前环境毒物仅 {length(select_vocs)} 个（需要 >= {min_bkmr}），跳过 BKMR。"
    )
    ctx$results$bkmr_fit_skipped <- TRUE
    return(ctx)
  }
  if (!strict_glm && length(select_vocs) < min_n) {
    stop(
      "bkmr_fit: 纯 VOC 候选仅 ", length(select_vocs),
      " 个，少于最少 ", min_n, " 个。", call. = FALSE
    )
  }
  if (exists("environment_assert_lasso_superset", mode = "function")) {
    environment_assert_lasso_superset(ctx, select_vocs, "BKMR")
  }

  covariates <- as.character(
    bl_cfg$covariates %||%
    ctx$results$vif_final_pass %||%
    ctx$results$final_features %||%
    ctx$results$Model2Factors %||%
    character(0)
  )
  covariates <- intersect(covariates, names(data))

  cli::cli_alert_info(
    "bkmr_fit: VOC {length(select_vocs)} \u4e2a, \u534f\u53d8\u91cf {length(covariates)} \u4e2a"
  )

  # ── 构建分析数据集 ────────────────────────────────────────────────────────
  keep_cols   <- unique(c(outcome_col, covariates, select_vocs))
  data_bkmr   <- data[, intersect(keep_cols, names(data)), drop = FALSE]
  data_bkmr   <- data_bkmr[stats::complete.cases(data_bkmr), , drop = FALSE]
  if (nrow(data_bkmr) < 30L) {
    stop("bkmr_fit: \u5b8c\u6574\u6837\u672c\u4e0d\u8db3 30 \u884c\uff0c\u8bf7\u68c0\u67e5\u6570\u636e\u3002")
  }
  cli::cli_alert_info("bkmr_fit: \u5206\u6790\u6837\u672c n = {nrow(data_bkmr)}")

  # ── 结局向量 y（0/1）────────────────────────────────────────────────────
  yraw <- data_bkmr[[outcome_col]]
  if (is.numeric(yraw) && all(stats::na.omit(unique(yraw)) %in% c(0, 1))) {
    y <- as.integer(yraw)
  } else {
    yc <- trimws(as.character(yraw))
    y  <- ifelse(yc == trimws(analysis_grp), 1L,
                 ifelse(yc == trimws(reference_grp), 0L, NA_integer_))
  }
  if (any(is.na(y))) {
    cli::cli_alert_warning("bkmr_fit: y \u542b {sum(is.na(y))} \u4e2a NA\uff0c\u5c06\u5220\u9664\u5bf9\u5e94\u884c\u3002")
    ok     <- !is.na(y)
    y      <- y[ok]
    data_bkmr <- data_bkmr[ok, , drop = FALSE]
  }

  # ── 标准化暴露矩阵 Z ──────────────────────────────────────────────────────
  expos      <- data_bkmr[, select_vocs, drop = FALSE]
  scale_expos <- as.matrix(scale(expos))
  if (any(is.nan(scale_expos))) {
    cli::cli_alert_warning("bkmr_fit: scale(Z) \u542b NaN\uff08\u67d0\u5217\u65b9\u5dee\u4e3a 0\uff0c\u7528 0 \u586b\u5145\uff09\u3002")
    scale_expos[is.nan(scale_expos)] <- 0
  }

  # ── 数值化协变量矩阵 X（修复 Bug 2）─────────────────────────────────────
  if (length(covariates)) {
    covar <- data.frame(data_bkmr[, covariates, drop = FALSE])
    covar <- .bkmr38_encode_covariates(covar, bl_cfg$covariate_encoding)
    cov_mat <- as.matrix(covar)
    storage.mode(cov_mat) <- "double"
    cov_mat[!is.finite(cov_mat)] <- 0
    covar <- as.data.frame(cov_mat, stringsAsFactors = FALSE)
    names(covar) <- colnames(cov_mat)
    cli::cli_alert_info("bkmr_fit: \u534f\u53d8\u91cf\u7f16\u7801\u5b8c\u6210: {paste(names(covar), collapse=', ')}")
  } else {
    covar <- NULL
    cli::cli_alert_warning("bkmr_fit: \u5c06\u4e0d\u4f7f\u7528\u534f\u53d8\u91cf\uff08X = NULL\uff09\u3002")
  }

  # ── 并行参数（修复 Bug 3: 避免 n > availableCores）─────────────────────
  n_available <- max(1L, parallel::detectCores(logical = FALSE))
  nchains_cfg  <- as.integer(bl_cfg$nchains %||% max(2L, floor(n_available / 2L)))
  nchains      <- max(2L, min(nchains_cfg, n_available))
  if (nchains < nchains_cfg) {
    cli::cli_alert_warning(
      "bkmr_fit: nchains \u964d\u81f3 {nchains}\uff08\u8bf7\u6c42 {nchains_cfg}\uff0c\u53ef\u7528\u6838 {n_available}\uff09"
    )
  }
  iter    <- as.integer(bl_cfg$iter    %||% 1000L)
  family  <- as.character(bl_cfg$family %||% "binomial")
  seed    <- as.integer(bl_cfg$seed    %||% 123L)
  varsel  <- isTRUE(bl_cfg$varsel      %||% TRUE)
  est_h   <- isTRUE(bl_cfg$est_h       %||% TRUE)

  fit_bkmr <- NULL
  iter_used <- iter
  if (exists("environment_auto_select_bkmr_iter", mode = "function") &&
      isTRUE(bl_cfg$auto_iter %||% TRUE)) {
    auto_res <- environment_auto_select_bkmr_iter(y, scale_expos, covar, bl_cfg)
    iter_used <- auto_res$iter
    if (!is.null(auto_res$fit)) {
      fit_bkmr <- auto_res$fit
      ctx$results$bkmr_iter_selected <- iter_used
      ctx$results$bkmr_overall_quality <- auto_res$quality
      if (!is.null(auto_res$risks)) ctx$results$risks_overall_search <- auto_res$risks
      cli::cli_h2(
        "bkmr_fit: 自动选择 iter={iter_used}（nchains={nchains}, total={nchains * iter_used}）"
      )
    }
  }

  if (is.null(fit_bkmr)) {
    cli::cli_h2(
      "bkmr_fit: 开始 MCMC（nchains={nchains}, iter={iter_used}, total={nchains * iter_used}）"
    )
    future::plan(strategy = future::multisession, workers = nchains)
    on.exit(future::plan(future::sequential), add = TRUE)
    set.seed(seed)
    fit_args <- list(
      nchains = nchains, y = y, Z = scale_expos, est.h = est_h,
      family = family, iter = iter_used, verbose = FALSE, varsel = varsel
    )
    if (!is.null(covar)) fit_args$X <- covar
    fit_bkmr <- tryCatch(
      do.call(bkmrhat::kmbayes_parallel, fit_args),
      error = function(e) {
        stop("bkmr_fit: kmbayes_parallel 失败: ", e$message, call. = FALSE)
      }
    )
  }

  ctx$results$fit_bkmr         <- fit_bkmr
  ctx$results$bkmr_y           <- y
  ctx$results$bkmr_Z           <- scale_expos
  ctx$results$bkmr_X           <- covar
  ctx$results$bkmr_select_vocs <- select_vocs

  if (isTRUE(bl_cfg$standardize_covariates_if_bad %||% FALSE) && !is.null(covar) &&
      requireNamespace("bkmr", quietly = TRUE)) {
    mix_util <- file.path(cfg$project$root %||% getwd(), "R", "environment_mixture_utils.R")
    if (file.exists(mix_util) && !exists("environment_bkmr_overall_quality", mode = "function")) {
      source(mix_util, local = FALSE)
    }
    comb0 <- tryCatch(bkmrhat::kmbayes_combine(fit_bkmr), error = function(e) NULL)
    risks0 <- if (!is.null(comb0)) {
      tryCatch(
        bkmr::OverallRiskSummaries(
          fit = comb0, X = covar, y = y, Z = scale_expos,
          qs = seq(0.25, 0.75, by = 0.05), method = "exact"
        ),
        error = function(e) NULL
      )
    } else NULL
    qual0 <- environment_bkmr_overall_quality(risks0)
    if (!isTRUE(qual0$ok)) {
      cli::cli_alert_warning(
        "bkmr_fit: 整体效应不理想（mono={qual0$mono}, right>0={qual0$right_no_cross}），协变量标准化后重拟合"
      )
      covar_sc <- as.data.frame(scale(covar))
      covar_sc[!is.finite(as.matrix(covar_sc))] <- 0
      set.seed(seed)
      fit_args2 <- list(
        nchains = nchains, y = y, Z = scale_expos, est.h = est_h,
        family = family, iter = iter_used, verbose = FALSE, varsel = varsel,
        X = covar_sc
      )
      fit_bkmr2 <- tryCatch(
        do.call(bkmrhat::kmbayes_parallel, fit_args2),
        error = function(e) NULL
      )
      if (!is.null(fit_bkmr2)) {
        fit_bkmr <- fit_bkmr2
        covar <- covar_sc
        ctx$results$bkmr_X <- covar
        ctx$results$bkmr_covariates_standardized <- TRUE
        cli::cli_alert_success("bkmr_fit: 协变量标准化后重拟合完成")
      }
    }
  }

  cli::cli_alert_success(
    "bkmr_fit 完成: {nchains} 链 × {iter_used} 迭代 = {nchains * iter_used} 次模拟。"
  )
  ctx
}

register_block(
  "bkmr_fit",
  block_bkmr_fit,
  "BKMR \u5e76\u884c MCMC \u62df\u5408\uff08bkmrhat\uff09\uff1a\u51c6\u5907 y/Z/X\u3001\u81ea\u52a8\u7f16\u7801\u534f\u53d8\u91cf\u3001future \u591a\u94fe\u62df\u5408"
)
