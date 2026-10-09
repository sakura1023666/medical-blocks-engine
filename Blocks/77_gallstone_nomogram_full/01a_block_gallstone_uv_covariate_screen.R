###############################################################################
# gallstone_uv_covariate_screen — 关联段协变量：单因素显著筛选
# 死规则：Model1 强制 Age；Model2=Age∪(人口学∩UV显著)；Model3=Age∪(候选∩UV显著)
###############################################################################

block_gallstone_uv_covariate_screen <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_gallstone_nomogram.R"), local = FALSE)
  bl <- ctx$config$gallstone_nomogram %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$raw
  outcome <- ctx$config$data$outcome_column %||% "Success"
  if (is.null(data)) stop("uv_covariate_screen: 无数据", call. = FALSE)

  alpha <- as.numeric(bl$uv_alpha %||% 0.05)[1L]
  demo_pool <- unique(as.character(bl$uv_demo_pool %||% c("Age", "Sex")))
  # 候选混杂：人口学 + 分类临床（不含「当前连续暴露」互校池，避免小样本分离）
  cand <- unique(as.character(bl$uv_candidate_pool %||% c(
    demo_pool, gallstone_nomogram_cat_features(ctx$config)
  )))
  cand <- cand[cand %in% names(data)]
  cand <- setdiff(cand, c(outcome, "success", "id", "ID"))

  y <- data[[outcome]]
  if (is.factor(y)) {
    y01 <- as.integer(y == levels(y)[length(levels(y))] | y == "Yes")
  } else {
    y01 <- as.integer(as.numeric(y) == 1L)
  }
  d0 <- data
  d0$.y <- y01

  rows <- list()
  for (v in cand) {
    dv <- d0[, c(".y", v), drop = FALSE]
    dv <- dv[stats::complete.cases(dv), , drop = FALSE]
    if (nrow(dv) < 10L || length(unique(dv$.y)) < 2L) {
      rows[[length(rows) + 1L]] <- data.frame(
        variable = v, n = nrow(dv), OR = NA_real_, CI_low = NA_real_,
        CI_high = NA_real_, P = NA_real_, significant = FALSE,
        pool = if (v %in% demo_pool) "demo" else "clinical",
        stringsAsFactors = FALSE
      )
      next
    }
    # 连续：按 1 SD；分类：原样因子
    if (is.numeric(dv[[v]]) && !is.factor(dv[[v]])) {
      dv$.x <- as.numeric(scale(as.numeric(dv[[v]])))
      fml <- .y ~ .x
      lab_or <- "per_1SD"
    } else {
      dv[[v]] <- factor(dv[[v]])
      if (nlevels(dv[[v]]) < 2L) {
        rows[[length(rows) + 1L]] <- data.frame(
          variable = v, n = nrow(dv), OR = NA_real_, CI_low = NA_real_,
          CI_high = NA_real_, P = NA_real_, significant = FALSE,
          pool = if (v %in% demo_pool) "demo" else "clinical",
          stringsAsFactors = FALSE
        )
        next
      }
      fml <- stats::as.formula(paste(".y ~", v))
      lab_or <- "factor"
    }
    fit <- tryCatch(stats::glm(fml, data = dv, family = stats::binomial()),
                    error = function(e) NULL)
    if (is.null(fit)) {
      rows[[length(rows) + 1L]] <- data.frame(
        variable = v, n = nrow(dv), OR = NA_real_, CI_low = NA_real_,
        CI_high = NA_real_, P = NA_real_, significant = FALSE,
        pool = if (v %in% demo_pool) "demo" else "clinical",
        stringsAsFactors = FALSE
      )
      next
    }
    sm <- summary(fit)$coefficients
    # 取第一个非截距项的总体似然比 / 或最小 P（分类多水平）
    rn <- setdiff(rownames(sm), "(Intercept)")
    if (!length(rn)) {
      p_v <- NA_real_; or_v <- NA_real_; lo_v <- NA_real_; hi_v <- NA_real_
    } else if (identical(lab_or, "per_1SD")) {
      est <- sm[rn[[1L]], "Estimate"]
      se <- sm[rn[[1L]], "Std. Error"]
      p_v <- sm[rn[[1L]], grepl("^Pr", colnames(sm))][1]
      or_v <- exp(est); lo_v <- exp(est - 1.96 * se); hi_v <- exp(est + 1.96 * se)
    } else {
      # 分类：用 drop1 LRT 总检验
      p_v <- tryCatch({
        d1 <- drop1(fit, test = "Chisq")
        as.numeric(d1[v, "Pr(>Chi)"])
      }, error = function(e) {
        min(sm[rn, grepl("^Pr", colnames(sm))], na.rm = TRUE)
      })
      or_v <- NA_real_; lo_v <- NA_real_; hi_v <- NA_real_
    }
    p_v <- as.numeric(p_v)[1L]
    rows[[length(rows) + 1L]] <- data.frame(
      variable = v, n = nrow(dv),
      OR = as.numeric(or_v)[1L], CI_low = as.numeric(lo_v)[1L],
      CI_high = as.numeric(hi_v)[1L], P = p_v,
      significant = is.finite(p_v) && p_v < alpha,
      pool = if (v %in% demo_pool) "demo" else "clinical",
      stringsAsFactors = FALSE
    )
  }
  tab <- do.call(rbind, rows)
  sig_all <- as.character(tab$variable[which(as.logical(tab$significant) %in% TRUE)])
  sig_demo <- intersect(sig_all, demo_pool)
  sig_clinical <- setdiff(sig_all, demo_pool)

  dirs <- gallstone_nomogram_out_dirs(ctx, "ALL")
  gallstone_nomogram_ensure_dirs(list(dirs$shared_tables, file.path(dirs$project, "Tables")))
  # Model1 死规则：Age 强制（不论 UV 是否显著）；Model2/3 = Age ∪ UV显著（嵌套）
  ctx$config$gallstone_nomogram$force_model1 <- "Age"
  ctx$config$gallstone_nomogram$model2 <- unique(c("Age", sig_demo))
  ctx$config$gallstone_nomogram$model3 <- unique(c("Age", sig_all))
  ctx$config$gallstone_nomogram$assoc_covariate_source <- "uv_significant"

  methods_txt <- c(
    "assoc_covariate_source=uv_significant",
    sprintf("uv_alpha=%.3f", alpha),
    "force_model1=Age  # 死规则：不论 UV 是否显著",
    sprintf("sig_demo_uv=%s", paste(sig_demo, collapse = ",")),
    sprintf("sig_all_uv=%s", paste(sig_all, collapse = ",")),
    sprintf("Model1=Age(forced); Model2=Age+%s; Model3=Age+%s",
            paste(setdiff(sig_demo, "Age"), collapse = "+"),
            paste(setdiff(sig_all, "Age"), collapse = "+"))
  )
  for (td in unique(c(dirs$shared_tables, file.path(dirs$project, "Tables")))) {
    utils::write.csv(tab, file.path(td, "Table_UV_covariate_screen.csv"), row.names = FALSE)
    writeLines(methods_txt, file.path(td, "Methods_assoc_covariate_uv.txt"))
  }

  ctx$results$gallstone_uv_covariate_screen <- list(
    table = tab, alpha = alpha,
    sig_demo = sig_demo, sig_all = sig_all, sig_clinical = sig_clinical,
    candidate_pool = cand, demo_pool = demo_pool
  )

  cli::cli_alert_success(
    "UV 协变量筛选: alpha={alpha}; Model1=Age(forced); Model2={paste(unique(c('Age', sig_demo)), collapse=',')}; Model3={paste(unique(c('Age', sig_all)), collapse=',')}"
  )
  ctx
}

register_block("gallstone_uv_covariate_screen", block_gallstone_uv_covariate_screen,
               "胆结石关联协变量单因素显著筛选")
