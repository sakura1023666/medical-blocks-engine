###############################################################################
#  latent_profile_tidylpa — 潜剖面 / 潜类别（主分析可切换）
#
#  register_block: "latent_profile_tidylpa"
#  方法目录: Blocks/83_latent_profile/
#
#  config$latent_profile = list(
#    engine = "poLCA",          # "poLCA"（等级题主分析）| "mclust"（连续 LPA）
#    items = paste0("DAS", 1:12),
#    n_profiles_max = 5L,
#    min_class_n = 30L,
#    min_class_prop = 0.04,
#    nrep = 10L,                # poLCA 随机起始
#    seed = 1234L,
#    class_col = "LCA_class",
#    also_write_lpa_alias = TRUE # 同步写 LPA_class 兼容旧下游
#  )
###############################################################################

block_latent_profile_tidylpa <- function(ctx, ...) {
  cfg <- ctx$config
  bl <- cfg$latent_profile %||% cfg$latent_profile_tidylpa %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("latent_profile_tidylpa: 无数据", call. = FALSE)

  items <- as.character(bl$items %||% character(0))
  items <- items[items %in% names(data)]
  if (length(items) < 2L) stop("latent_profile_tidylpa: items < 2", call. = FALSE)

  max_k <- as.integer(bl$n_profiles_max %||% 5L)
  min_n <- as.integer(bl$min_class_n %||% 30L)
  min_prop <- as.numeric(bl$min_class_prop %||% 0.04)
  seed <- as.integer(bl$seed %||% cfg$seed %||% 1234L)
  class_col <- as.character(bl$class_col %||% "LCA_class")[1L]
  engine <- tolower(as.character(bl$engine %||% "poLCA")[1L])
  nrep <- as.integer(bl$nrep %||% 10L)
  also_alias <- isTRUE(bl$also_write_lpa_alias %||% TRUE)
  set.seed(seed)

  X <- as.data.frame(lapply(data[items], function(z) suppressWarnings(as.numeric(z))))
  keep <- stats::complete.cases(X)
  Xc <- X[keep, , drop = FALSE]
  if (nrow(Xc) < max(30L, min_n)) {
    stop("latent_profile_tidylpa: 完整病例过少 n=", nrow(Xc), call. = FALSE)
  }

  .rel_ent <- function(z) {
    if (is.null(z) || !is.matrix(z) || ncol(z) < 2L) return(NA_real_)
    z <- pmax(as.matrix(z), .Machine$double.eps)
    z <- z / rowSums(z)
    n <- nrow(z)
    k <- ncol(z)
    denom <- n * log(k)
    if (!is.finite(denom) || denom <= 0) return(NA_real_)
    as.numeric(1 - sum(-z * log(z)) / denom)
  }

  .pick_best <- function(fit_df, assigns, bic_smaller_better = TRUE) {
    if (!nrow(fit_df)) stop("latent_profile_tidylpa: 无拟合表", call. = FALSE)
    score_bic <- if (isTRUE(bic_smaller_better)) fit_df$BIC else -fit_df$BIC
    tiny <- (fit_df$min_class_n < min_n) | (fit_df$min_class_prop < min_prop)
    deg <- as.logical(fit_df$degenerate %||% FALSE)
    score <- score_bic + ifelse(tiny | deg, 1e6, 0)
    best_i <- which.min(score)
    best_k <- as.integer(fit_df$K[best_i])

    if (best_k <= 1L && nrow(fit_df) > 1L) {
      cand <- fit_df[!deg & fit_df$K >= 2L & fit_df$min_class_prop >= min_prop, , drop = FALSE]
      if (!nrow(cand)) {
        cand <- fit_df[!deg & fit_df$K >= 2L & fit_df$min_class_n >= min_n, , drop = FALSE]
      }
      if (!nrow(cand)) cand <- fit_df[!deg & fit_df$K >= 2L, , drop = FALSE]
      if (nrow(cand)) {
        pick <- if (isTRUE(bic_smaller_better)) {
          cand[which.min(cand$BIC), , drop = FALSE]
        } else {
          cand[which.max(cand$BIC), , drop = FALSE]
        }
        best_k <- as.integer(pick$K[1L])
        cli::cli_alert_warning(
          "LPA/LCA: 原门槛下 K*=1；放宽后改选 K*={best_k}"
        )
      }
    }
    cls <- assigns[[as.character(best_k)]]
    list(best_k = best_k, cls = cls)
  }

  fit_tab <- list()
  assigns <- list()
  method_used <- engine
  bic_smaller_better <- TRUE

  if (identical(engine, "polca") || identical(engine, "poLCA") || identical(engine, "lca")) {
    if (!requireNamespace("poLCA", quietly = TRUE)) {
      stop("engine=poLCA 需要安装 poLCA 包", call. = FALSE)
    }
    method_used <- "poLCA"
    bic_smaller_better <- TRUE
    Xp <- Xc
    for (nm in names(Xp)) {
      Xp[[nm]] <- as.integer(Xp[[nm]] - min(Xp[[nm]], na.rm = TRUE) + 1L)
    }
    fml <- stats::as.formula(paste0("cbind(", paste(names(Xp), collapse = ","), ") ~ 1"))
    for (k in seq_len(max_k)) {
      fit <- tryCatch(
        poLCA::poLCA(fml, data = Xp, nclass = k, nrep = nrep, maxiter = 4000, verbose = FALSE),
        error = function(e) NULL
      )
      if (is.null(fit)) next
      cls_k <- as.integer(fit$predclass)
      tab <- table(factor(cls_k, levels = seq_len(k)))
      n_unique <- sum(as.integer(tab) > 0L)
      prop <- as.numeric(tab) / sum(tab)
      pos <- as.integer(tab) > 0L
      fit_tab[[length(fit_tab) + 1L]] <- data.frame(
        K = k,
        AIC = as.numeric(fit$aic),
        BIC = as.numeric(fit$bic),
        loglik = as.numeric(fit$llik),
        model = "poLCA",
        min_class_n = min(as.integer(tab)[pos]),
        min_class_prop = min(prop[pos]),
        n_unique = n_unique,
        degenerate = (k > 1L && n_unique < k),
        entropy = .rel_ent(fit$posterior),
        class_counts = paste(as.integer(tab), collapse = "|"),
        stringsAsFactors = FALSE
      )
      assigns[[as.character(k)]] <- cls_k
    }
  } else {
    # continuous Gaussian LPA (mclust)
    if (!requireNamespace("mclust", quietly = TRUE)) {
      stop("engine=mclust 需要 mclust 包", call. = FALSE)
    }
    method_used <- "mclust"
    bic_smaller_better <- FALSE # mclust BIC 越大越好
    for (k in seq_len(max_k)) {
      mod <- tryCatch(
        mclust::Mclust(
          as.matrix(Xc), G = k,
          modelNames = c("EEI", "VVI", "EEE", "VVV"), verbose = FALSE
        ),
        error = function(e) NULL
      )
      if (is.null(mod)) next
      cls_k <- as.integer(mod$classification)
      n_unique <- length(unique(cls_k))
      tab <- table(cls_k)
      prop <- as.numeric(tab) / length(cls_k)
      fit_tab[[length(fit_tab) + 1L]] <- data.frame(
        K = k,
        AIC = NA_real_,
        BIC = as.numeric(mod$bic),
        loglik = as.numeric(mod$loglik),
        model = as.character(mod$modelName),
        min_class_n = min(as.integer(tab)),
        min_class_prop = min(prop),
        n_unique = n_unique,
        degenerate = (k > 1L && n_unique < k),
        entropy = .rel_ent(mod$z),
        class_counts = paste(as.integer(tab), collapse = "|"),
        stringsAsFactors = FALSE
      )
      assigns[[as.character(k)]] <- cls_k
    }
  }

  fit_df <- if (length(fit_tab)) do.call(rbind, fit_tab) else {
    stop("latent_profile_tidylpa: 全部 K 拟合失败", call. = FALSE)
  }
  picked <- .pick_best(fit_df, assigns, bic_smaller_better = bic_smaller_better)
  best_k <- picked$best_k
  cls <- picked$cls
  if (is.null(cls)) stop("latent_profile_tidylpa: 无分类结果", call. = FALSE)

  data[[class_col]] <- NA_integer_
  data[[class_col]][which(keep)] <- cls
  data[[paste0(class_col, "_label")]] <- ifelse(
    is.na(data[[class_col]]), NA_character_,
    paste0("C", data[[class_col]])
  )
  if (isTRUE(also_alias) && !identical(class_col, "LPA_class")) {
    data[["LPA_class"]] <- data[[class_col]]
    data[["LPA_class_label"]] <- data[[paste0(class_col, "_label")]]
  }

  ctx$data$cleaned <- data
  if (!is.null(ctx$data$imputed) && nrow(ctx$data$imputed) == nrow(data)) {
    ctx$data$imputed[[class_col]] <- data[[class_col]]
    ctx$data$imputed[[paste0(class_col, "_label")]] <- data[[paste0(class_col, "_label")]]
    if (isTRUE(also_alias) && !identical(class_col, "LPA_class")) {
      ctx$data$imputed[["LPA_class"]] <- data[["LPA_class"]]
      ctx$data$imputed[["LPA_class_label"]] <- data[["LPA_class_label"]]
    }
  }

  out_dir <- file.path(ctx$output_dir %||% ".", "Tables")
  fig_dir <- file.path(ctx$output_dir %||% ".", "Figures")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(fit_df, file.path(out_dir, "Table_LPA_fit_indices.csv"), row.names = FALSE)
  utils::write.csv(fit_df, file.path(out_dir, "Table_LCA_fit_indices.csv"), row.names = FALSE)

  if (requireNamespace("ggplot2", quietly = TRUE)) {
    uk <- sort(unique(cls))
    means <- lapply(uk, function(kk) colMeans(Xc[cls == kk, , drop = FALSE], na.rm = TRUE))
    plot_df <- do.call(rbind, lapply(seq_along(means), function(i) {
      data.frame(
        class = paste0("C", uk[i]),
        item = names(means[[i]]),
        mean = as.numeric(means[[i]])
      )
    }))
    ttl <- if (identical(method_used, "poLCA")) {
      paste0("LCA class profiles (K=", best_k, "; item means)")
    } else {
      paste0("LPA profiles (K=", best_k, ")")
    }
    p <- ggplot2::ggplot(plot_df, ggplot2::aes(item, mean, group = class, colour = class)) +
      ggplot2::geom_line() + ggplot2::geom_point() +
      ggplot2::theme_bw() +
      ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1)) +
      ggplot2::labs(title = ttl, y = "Item mean", x = NULL)
    ggplot2::ggsave(file.path(fig_dir, "Figure_LPA_profiles.pdf"), p, width = 9, height = 5)
    ggplot2::ggsave(file.path(fig_dir, "Figure_LCA_profiles.pdf"), p, width = 9, height = 5)
  }

  ctx$results$latent_profile <- list(
    fit = fit_df, best_k = best_k, class_col = class_col,
    method = method_used, n_complete = nrow(Xc), items = items,
    engine = engine
  )
  ent_star <- fit_df$entropy[match(best_k, fit_df$K)]
  cli::cli_alert_success(
    "latent_profile_tidylpa: K*={best_k} (method={method_used}, n={nrow(Xc)}, entropy={round(ent_star, 3)})"
  )
  ctx
}

register_block(
  "latent_profile_tidylpa",
  block_latent_profile_tidylpa,
  "潜剖面/潜类别（poLCA 等级 LCA 或 mclust 连续 LPA）"
)
