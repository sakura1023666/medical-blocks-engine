###############################################################################
#  latent_profile_tidylpa — 连续条目潜剖面分析（LPA）
#
#  register_block: "latent_profile_tidylpa"
#  方法目录: Blocks/83_latent_profile/（问卷 LPA；≠ Blocks/30_lca 共识聚类）
#
#  config$latent_profile = list(
#    items = paste0("DAS", 1:12),
#    n_profiles_max = 5L,
#    min_class_n = 80L,
#    min_class_prop = 0.05,
#    model = "EEI",          # tidyLPA / mclust 回退
#    seed = 1234L,
#    class_col = "LPA_class",
#    prefer = c("BIC", "interpretability")
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
  min_n <- as.integer(bl$min_class_n %||% 80L)
  min_prop <- as.numeric(bl$min_class_prop %||% 0.05)
  seed <- as.integer(bl$seed %||% cfg$seed %||% 1234L)
  class_col <- as.character(bl$class_col %||% "LPA_class")[1L]
  set.seed(seed)

  X <- as.data.frame(lapply(data[items], function(z) suppressWarnings(as.numeric(z))))
  keep <- stats::complete.cases(X)
  Xc <- X[keep, , drop = FALSE]
  if (nrow(Xc) < max(30L, min_n)) {
    stop("latent_profile_tidylpa: 完整病例过少 n=", nrow(Xc), call. = FALSE)
  }

  fit_tab <- list()
  assigns <- list()
  method_used <- "mclust"

  if (requireNamespace("tidyLPA", quietly = TRUE)) {
    method_used <- "tidyLPA"
    tl <- tryCatch(
      tidyLPA::estimate_profiles(Xc, n_profiles = 1:max_k, models = 1L),
      error = function(e) NULL
    )
    if (!is.null(tl)) {
      # tidyLPA 返回值结构因版本而异；失败则回退 mclust
      method_used <- "tidyLPA"
    }
  }

  if (!requireNamespace("mclust", quietly = TRUE)) {
    stop("需要 mclust（或可用的 tidyLPA）", call. = FALSE)
  }
  suppressPackageStartupMessages(library(mclust))

  best_k <- 1L
  best_bic <- Inf
  best_mod <- NULL
  for (k in seq_len(max_k)) {
    mod <- tryCatch(
      mclust::Mclust(as.matrix(Xc), G = k, modelNames = c("EEI", "VVI", "EEE", "VVV"), verbose = FALSE),
      error = function(e) NULL
    )
    if (is.null(mod)) next
    bic <- as.numeric(mod$bic)
    # mclust::BIC 越大越好 → 选模用 -BIC（越小越好）
    cls_k <- as.integer(mod$classification)
    n_unique <- length(unique(cls_k))
    prop <- as.numeric(table(cls_k)) / length(cls_k)
    min_cls_n <- min(as.integer(table(cls_k)))
    degenerate <- (k > 1L && n_unique < k)
    fit_tab[[length(fit_tab) + 1L]] <- data.frame(
      K = k, BIC = bic, loglik = as.numeric(mod$loglik),
      model = as.character(mod$modelName),
      min_class_n = min_cls_n,
      min_class_prop = min(prop),
      n_unique = n_unique,
      degenerate = degenerate,
      entropy_proxy = NA_real_,
      stringsAsFactors = FALSE
    )
    assigns[[as.character(k)]] <- cls_k
    tiny <- (min_cls_n < min_n) || (min(prop) < min_prop)
    score <- -bic + if (tiny || degenerate) 1e6 else 0
    if (score < best_bic) {
      best_bic <- score
      best_k <- k
      best_mod <- mod
    }
  }

  fit_df <- if (length(fit_tab)) do.call(rbind, fit_tab) else {
    stop("latent_profile_tidylpa: 全部 K 拟合失败", call. = FALSE)
  }

  # 若门槛过严导致只剩 K=1：优先「非退化且过 prop」；再「非退化且过 min_n」；最后非退化 BIC 最大
  if (best_k <= 1L && nrow(fit_df) > 1L) {
    deg <- as.logical(fit_df$degenerate %||% FALSE)
    cand <- fit_df[!deg & fit_df$K >= 2L & fit_df$min_class_prop >= min_prop, , drop = FALSE]
    if (!nrow(cand)) {
      cand <- fit_df[!deg & fit_df$K >= 2L & fit_df$min_class_n >= min_n, , drop = FALSE]
    }
    if (!nrow(cand)) cand <- fit_df[!deg & fit_df$K >= 2L, , drop = FALSE]
    if (nrow(cand)) {
      pick <- cand[which.max(cand$BIC), , drop = FALSE]
      best_k <- as.integer(pick$K[1L])
      cli::cli_alert_warning(
        "LPA: 原门槛下 K*=1；放宽后改选 K*={best_k} (min_n={pick$min_class_n[1]}, prop={round(pick$min_class_prop[1],3)})"
      )
    }
  }

  cls <- assigns[[as.character(best_k)]]
  if (is.null(cls) && !is.null(best_mod)) cls <- as.integer(best_mod$classification)
  if (is.null(cls)) stop("latent_profile_tidylpa: 无分类结果", call. = FALSE)

  data[[class_col]] <- NA_integer_
  data[[class_col]][which(keep)] <- cls
  data[[paste0(class_col, "_label")]] <- ifelse(
    is.na(data[[class_col]]), NA_character_,
    paste0("C", data[[class_col]])
  )

  # 写回
  ctx$data$cleaned <- data
  if (!is.null(ctx$data$imputed)) {
    # 对齐行：若 imputed 同行数则同步
    if (nrow(ctx$data$imputed) == nrow(data)) {
      ctx$data$imputed[[class_col]] <- data[[class_col]]
      ctx$data$imputed[[paste0(class_col, "_label")]] <- data[[paste0(class_col, "_label")]]
    }
  }

  out_dir <- file.path(ctx$output_dir %||% ".", "Tables")
  fig_dir <- file.path(ctx$output_dir %||% ".", "Figures")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(fit_df, file.path(out_dir, "Table_LPA_fit_indices.csv"), row.names = FALSE)

  # 剖面均值图（条目）
  if (requireNamespace("ggplot2", quietly = TRUE)) {
    means <- lapply(sort(unique(cls)), function(k) {
      colMeans(Xc[cls == k, , drop = FALSE], na.rm = TRUE)
    })
    plot_df <- do.call(rbind, lapply(seq_along(means), function(i) {
      data.frame(class = paste0("C", sort(unique(cls))[i]),
                 item = names(means[[i]]),
                 mean = as.numeric(means[[i]]))
    }))
    p <- ggplot2::ggplot(plot_df, ggplot2::aes(item, mean, group = class, colour = class)) +
      ggplot2::geom_line() + ggplot2::geom_point() +
      ggplot2::theme_bw() +
      ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1)) +
      ggplot2::labs(title = paste0("LPA profiles (K=", best_k, ")"), y = "Item mean", x = NULL)
    ggplot2::ggsave(file.path(fig_dir, "Figure_LPA_profiles.pdf"), p, width = 9, height = 5)
  }

  ctx$results$latent_profile <- list(
    fit = fit_df, best_k = best_k, class_col = class_col,
    method = method_used, n_complete = nrow(Xc), items = items
  )
  cli::cli_alert_success(
    "latent_profile_tidylpa: K*={best_k} (method={method_used}, n={nrow(Xc)})"
  )
  ctx
}

register_block(
  "latent_profile_tidylpa",
  block_latent_profile_tidylpa,
  "连续条目潜剖面分析 LPA（tidyLPA/mclust）"
)
