###############################################################################
#  model3_required.R — Model 3 = Model 2 + 课题学术必调协变量；不显著则回退 Model 2
#
#  Gate B / Cox 闸门仍只看 Crude / Model1 / Model2。
#  Model 3 在 M1/M2 锁定之后拟合；显著则下游全调整用 Model 3，否则用 Model 2。
#  必调名单只来自课题 config，禁止在引擎写死糖尿病或其他病种。
###############################################################################

pipeline_model3_required_raw <- function(cfg) {
  cfg <- cfg %||% list()
  am <- cfg$analysis_models %||% list()
  raw <- as.character(
    am$model3_required_factors %||%
      (cfg$logistic_nhanes_weighted %||% list())$model3_required_factors %||%
      (cfg$cox %||% list())$model3_required_factors %||%
      (cfg$survival %||% list())$model3_required_factors %||%
      character(0)
  )
  unique(raw[nzchar(raw)])
}

pipeline_model3_enabled <- function(cfg) {
  length(pipeline_model3_required_raw(cfg)) > 0L
}

pipeline_model3_show_insignificant <- function(cfg) {
  am <- (cfg %||% list())$analysis_models %||% list()
  isTRUE(am$model3_show_when_insignificant %||% TRUE)
}

pipeline_model3_alias_map <- function(cfg = NULL) {
  base <- list(
    Smoke = c("Smoke", "Smoking"),
    Smoking = c("Smoking", "Smoke"),
    Gender = c("Gender", "Sex"),
    Sex = c("Sex", "Gender"),
    Hypertension = c("Hypertension", "HTN")
  )
  aliases <- ((cfg %||% list())$dual_db %||% list())$harmonization$subgroup_var_aliases %||% list()
  if (length(aliases)) {
    for (nm in names(aliases)) {
      base[[nm]] <- unique(c(nm, as.character(aliases[[nm]])))
    }
  }
  base
}

pipeline_match_available_var <- function(name, data_cols, cfg = NULL) {
  name <- as.character(name %||% "")[1L]
  data_cols <- as.character(data_cols %||% character(0))
  if (!nzchar(name)) return(NA_character_)
  if (name %in% data_cols) return(name)
  amap <- pipeline_model3_alias_map(cfg)
  cands <- unique(c(name, as.character(amap[[name]] %||% character(0))))
  hit <- intersect(cands, data_cols)
  if (length(hit)) hit[1L] else NA_character_
}

pipeline_resolve_model3_factors <- function(M2, cfg, data_cols, index_var = NULL) {
  M2 <- unique(as.character(M2 %||% character(0)))
  M2 <- M2[nzchar(M2)]
  required_raw <- pipeline_model3_required_raw(cfg)
  if (!length(required_raw)) return(character(0))

  data_cols <- as.character(data_cols %||% character(0))
  index_var <- as.character(
    index_var %||%
      (cfg$incidence %||% list())$index_var %||%
      (cfg$survival %||% list())$index_var %||%
      (cfg$logistic %||% list())$index_var %||%
      ""
  )[1L]

  excl <- character(0)
  if (exists("pipeline_model_factor_exclude_vars", mode = "function")) {
    excl <- pipeline_model_factor_exclude_vars(cfg)
  }
  disease <- as.character((cfg$analysis_exclusion %||% list())$disease_vars %||% character(0))
  lcfg_excl <- as.character((cfg$logistic_nhanes_weighted %||% list())$exclude_from_models %||% character(0))
  excl <- unique(c(excl, disease, lcfg_excl, index_var[nzchar(index_var)]))

  resolved <- vapply(required_raw, function(v) {
    pipeline_match_available_var(v, data_cols, cfg)
  }, character(1L))
  resolved <- unique(resolved[!is.na(resolved) & nzchar(resolved)])
  resolved <- setdiff(resolved, excl)
  dropped <- setdiff(required_raw, resolved)
  if (length(dropped)) {
    cli::cli_alert_info(
      "Model3 必调未纳入（缺列 / 疾病排除 / 指标组分）: {paste(dropped, collapse = ', ')}"
    )
  }
  extra <- setdiff(resolved, M2)
  if (!length(extra)) return(character(0))
  M3 <- unique(c(M2, extra))
  M3 <- c(M2, setdiff(M3, M2))
  cli::cli_alert_info(
    "Model3 = Model2 + 学术必调: {paste(extra, collapse = ', ')}"
  )
  M3
}

pipeline_grouped_term_significant <- function(p_trend, p_groups,
                                             method = "trend_or_any_group",
                                             threshold = 0.05) {
  threshold <- as.numeric(threshold %||% 0.05)[1L]
  if (!is.finite(threshold) || threshold <= 0 || threshold >= 1) threshold <- 0.05
  p_groups <- suppressWarnings(as.numeric(p_groups))
  p_trend <- suppressWarnings(as.numeric(p_trend)[1L])
  method <- tolower(as.character(method %||% "trend_or_any_group")[1L])
  switch(
    method,
    trend = is.finite(p_trend) && p_trend < threshold,
    any_group = any(is.finite(p_groups) & p_groups < threshold, na.rm = TRUE),
    (is.finite(p_trend) && p_trend < threshold) ||
      any(is.finite(p_groups) & p_groups < threshold, na.rm = TRUE)
  )
}

pipeline_model3_sig_from_table <- function(tb, raw_levels,
                                           method = "trend_or_any_group",
                                           threshold = 0.05) {
  if (is.null(tb)) return(FALSE)
  if (is.matrix(tb)) tb <- as.data.frame(tb, stringsAsFactors = FALSE)
  if (ncol(tb) < 15L) return(FALSE)
  parse_p <- if (exists("logistic_gate_parse_pval", mode = "function")) {
    logistic_gate_parse_pval
  } else {
    function(x) {
      x <- trimws(as.character(x %||% ""))
      if (!nzchar(x) || identical(toupper(x), "NA") || identical(x, "Ref")) return(NA_real_)
      if (grepl("^\\s*<", x)) return(0.0001)
      suppressWarnings(as.numeric(x))
    }
  }
  glv <- as.character(raw_levels %||% character(0))
  non_ref <- if (length(glv) >= 2L) glv[-1L] else character(0)
  p_groups <- numeric(0)
  p_trend <- NA_real_
  for (i in seq_len(nrow(tb))) {
    lab <- trimws(as.character(tb[i, 1L]))
    if (identical(lab, "p for trend")) {
      p_trend <- parse_p(tb[i, 15L])
    } else if (lab %in% non_ref) {
      p_groups <- c(p_groups, parse_p(tb[i, 15L]))
    }
  }
  isTRUE(pipeline_grouped_term_significant(p_trend, p_groups, method, threshold))
}

pipeline_finalize_adjusted_factors <- function(M2, M3, m3_sig) {
  M2 <- unique(as.character(M2 %||% character(0)))
  M3 <- unique(as.character(M3 %||% character(0)))
  if (length(M3) && isTRUE(m3_sig)) M3 else M2
}

pipeline_store_model3 <- function(ctx, M3 = character(0), m3_sig = FALSE,
                                  final = NULL, announce = TRUE) {
  M3 <- as.character(M3 %||% character(0))
  final <- as.character(final %||% character(0))
  ctx$results$Model3Factors <- M3
  ctx$results$logistic_model3_factors <- M3
  ctx$results$cox_model3_factors <- M3
  ctx$results$model3_significant <- isTRUE(m3_sig)
  if (length(final)) {
    ctx$results$logistic_final_factors <- final
    ctx$results$cox_final_factors <- final
  }
  if (isTRUE(announce)) {
    if (isTRUE(m3_sig) && length(M3)) {
      cli::cli_alert_success("Model3 显著，下游全调整使用 Model3")
    } else if (length(M3)) {
      cli::cli_alert_info("Model3 不显著，下游全调整回退 Model2")
    }
  }
  ctx
}

#' Table S7/S8：在最终多因素协变量上并入课题 Model3 必调（不回写 Model2Factors）
pipeline_union_model3_required <- function(covs, cfg, data_cols, index_var = NULL) {
  covs <- unique(as.character(covs %||% character(0)))
  covs <- covs[nzchar(covs)]
  m3 <- pipeline_resolve_model3_factors(covs, cfg, data_cols, index_var)
  if (!length(m3)) return(covs)
  unique(c(covs, m3))
}

#' RCS 第四面板协变量：已锁定的 Model3Factors，否则从 config 解析
pipeline_rcs_model3_covs <- function(ctx, cfg, M2, data_cols, index_var = NULL) {
  data_cols <- as.character(data_cols %||% character(0))
  stored <- unique(as.character(
    ctx$results$Model3Factors %||%
      ctx$results$logistic_model3_factors %||%
      ctx$results$cox_model3_factors %||%
      character(0)
  ))
  stored <- intersect(stored[nzchar(stored)], data_cols)
  if (length(setdiff(stored, as.character(M2 %||% character(0))))) {
    return(stored)
  }
  pipeline_resolve_model3_factors(M2, cfg, data_cols, index_var)
}

#' RCS 拼图：4 面板 → 上2下2；否则横排
pipeline_rcs_layout <- function(n_panels) {
  n <- as.integer(n_panels)[1L]
  if (!is.finite(n) || n < 1L) n <- 1L
  if (n >= 4L) {
    return(list(
      nrow = 2L, ncol = 2L, width = 12, height = 10,
      base_matrix = matrix(seq_len(4L), nrow = 2L, ncol = 2L, byrow = TRUE)
    ))
  }
  list(
    nrow = 1L, ncol = n, width = 15, height = 5,
    base_matrix = matrix(seq_len(n), nrow = 1L)
  )
}

pipeline_rcs_patchwork <- function(panels) {
  panels <- Filter(Negate(is.null), as.list(panels))
  lay <- pipeline_rcs_layout(length(panels))
  comb <- Reduce(`+`, panels) + patchwork::plot_layout(nrow = lay$nrow, ncol = lay$ncol)
  list(plot = comb, width = lay$width, height = lay$height, n = length(panels))
}

#' 按 config$plot_models 筛选 RCS 面板（默认 crude+model1+model2）。
#' 例：plot_models = c("model2") 仅出 Model 2，避免与 Table 2 三列重复。
pipeline_rcs_select_plot_panels <- function(panels, cfg = list()) {
  panels <- as.list(panels)
  if (!length(panels)) return(panels)
  pm <- cfg$plot_models %||% NULL
  if (is.null(pm) && isTRUE(cfg$plot_model2_only)) pm <- "model2"
  if (is.null(pm)) return(Filter(Negate(is.null), panels))
  pm <- tolower(trimws(as.character(pm)))
  pm <- unique(pm[nzchar(pm)])
  wanted <- character(0)
  for (p in pm) {
    if (p %in% c("crude", "a")) wanted <- c(wanted, "crude")
    else if (p %in% c("model1", "m1", "b")) wanted <- c(wanted, "model1")
    else if (p %in% c("model2", "m2", "c")) wanted <- c(wanted, "model2")
    else if (p %in% c("model3", "m3", "d")) wanted <- c(wanted, "model3")
    else if (p %in% names(panels)) wanted <- c(wanted, p)
  }
  wanted <- unique(intersect(wanted, names(panels)))
  if (!length(wanted)) return(Filter(Negate(is.null), panels))
  Filter(Negate(is.null), panels[wanted])
}

#' 解析 Table 2 单元格 P 值（含 "<0.001"）。
pipeline_parse_table2_p <- function(x) {
  x <- trimws(as.character(x %||% ""))
  if (!nzchar(x) || identical(toupper(x), "NA")) return(NA_real_)
  if (grepl("^\\s*<", x)) return(0.0001)
  suppressWarnings(as.numeric(x))
}

#' 从 ctx 中已导出的 Table 2 读取 p for trend（与主文 logistic 一致）。
pipeline_logistic_table2_trend_p_from_tb <- function(tb, model = c("crude", "model1", "model2", "model3")) {
  model <- match.arg(model)
  col_map <- c(crude = 6L, model1 = 9L, model2 = 12L, model3 = 15L)
  col_i <- col_map[[model]]
  tb <- as.data.frame(tb, stringsAsFactors = FALSE)
  trend_rows <- which(grepl("p for trend", tb[[1L]], ignore.case = TRUE))
  if (!length(trend_rows)) {
    nr <- nrow(tb)
    trend_rows <- if (nr >= 2L) nr - 2L else return(NA_real_)
  }
  tr <- tb[trend_rows[1L], , drop = TRUE]
  if (length(tr) < col_i) return(NA_real_)
  pipeline_parse_table2_p(tr[[col_i]])
}

pipeline_logistic_table2_trend_p <- function(ctx, model = c("crude", "model1", "model2", "model3")) {
  model <- match.arg(model)
  tb_disk <- pipeline_logistic_table2_read_from_disk(ctx)
  if (!is.null(tb_disk)) {
    pt <- pipeline_logistic_table2_trend_p_from_tb(tb_disk, model)
    if (is.finite(pt)) return(pt)
  }
  tp <- ctx$results$logistic_table2_trend_p %||% list()
  if (is.list(tp) && length(tp[[model]])) {
    pt <- suppressWarnings(as.numeric(tp[[model]]))
    if (is.finite(pt)) return(pt)
  }
  tb <- ctx$results$logistic_table2_nhanes %||%
    ctx$results$nhanes_logistic_table2 %||%
    ctx$results$logistic_table2_weighted %||%
    ctx$results$logistic_table2 %||%
    ctx$results$logistic_table2_tertile_nhanes %||%
    ctx$results$logistic_table2_quartile_nhanes %||%
    ctx$results$logistic_table2_binary_nhanes
  if (is.null(tb) || !nrow(tb)) return(NA_real_)
  pipeline_logistic_table2_trend_p_from_tb(tb, model)
}

#' RCS 对齐专用：磁盘主表 → ctx 缓存 trend_p；不读内存中的临时 Table2（易与发表表不一致）。
pipeline_rcs_table2_trend_p <- function(ctx, model = c("crude", "model1", "model2", "model3")) {
  model <- match.arg(model)
  tb_disk <- tryCatch(pipeline_logistic_table2_read_from_disk(ctx), error = function(e) NULL)
  if (!is.null(tb_disk)) {
    pt <- tryCatch(pipeline_logistic_table2_trend_p_from_tb(tb_disk, model), error = function(e) NA_real_)
    if (is.finite(pt)) return(pt)
  }
  tp <- ctx$results$logistic_table2_trend_p %||% list()
  if (is.list(tp) && length(tp[[model]])) {
    pt <- suppressWarnings(as.numeric(tp[[model]]))
    if (is.finite(pt)) return(pt)
  }
  NA_real_
}

#' 续跑时 ctx$results 可能无 Table 2，从当前库 Tables/ 读主表。
pipeline_logistic_table2_read_from_disk <- function(ctx) {
  if (!requireNamespace("readxl", quietly = TRUE)) return(NULL)
  od <- ctx$output_dir %||% "."
  roots <- unique(c(
    ctx$output_dir_tables,
    file.path(od, "Tables"),
    file.path(dirname(od), "Tables"),
    file.path(dirname(dirname(od)), "Tables"),
    file.path(dirname(dirname(od)), "MIMIC", "Tables"),
    file.path(dirname(dirname(od)), "NHANES", "Tables")
  ))
  roots <- unique(tryCatch(normalizePath(roots, winslash = "/", mustWork = FALSE), error = function(e) as.character(roots)))
  roots <- roots[nzchar(roots) & !is.na(roots)]
  roots <- roots[dir.exists(roots)]
  hits <- character(0)
  for (td in roots) {
    hits <- c(
      hits,
      list.files(
        td,
        pattern = "^Table 2.*\\.xlsx$",
        full.names = TRUE,
        ignore.case = TRUE
      )
    )
  }
  hits <- unique(hits)
  if (!length(hits)) return(NULL)
  db_tag <- tolower(as.character(
    ctx$db_name %||% ctx$results$db_name %||%
      ((ctx$config %||% list())$dual_db %||% list())$current_db %||% ""
  ))[1L]
  if (!nzchar(db_tag)) {
    od <- as.character(ctx$output_dir %||% "")
    for (tag in c("NHANES", "MIMIC", "nhanes", "mimic")) {
      if (grepl(tag, od, ignore.case = TRUE)) { db_tag <- tolower(tag); break }
    }
  }
  if (nzchar(db_tag) && db_tag %in% c("nhanes", "mimic")) {
    tagged <- hits[grepl(db_tag, basename(hits), ignore.case = TRUE)]
    if (length(tagged)) hits <- tagged
  }
  ord <- order(file.info(hits)$mtime, decreasing = TRUE)
  hits <- hits[ord]
  for (fp in hits) {
    tb <- tryCatch(
      as.data.frame(
        readxl::read_excel(fp, col_names = FALSE),
        stringsAsFactors = FALSE
      ),
      error = function(e) NULL
    )
    if (!is.null(tb) && any(grepl("p for trend", tb[[1L]], ignore.case = TRUE))) {
      return(tb)
    }
  }
  NULL
}

#' NHANES 加权：与 logistic tertile Table 2 相同的 Num 线性 trend P。
pipeline_rcs_nhanes_weighted_tertile_num <- function(design, index_var) {
  if (is.null(design) || !index_var %in% names(design$variables)) return(NULL)
  xv <- suppressWarnings(as.numeric(design$variables[[index_var]]))
  qs <- tryCatch({
    qq <- survey::svyquantile(
      stats::as.formula(paste0("~", index_var)),
      design,
      quantiles = c(1 / 3, 2 / 3),
      na.rm = TRUE
    )
    if (index_var %in% names(qq)) {
      mat <- qq[[index_var]]
      if (is.matrix(mat) && "quantile" %in% colnames(mat)) {
        as.numeric(mat[, "quantile", drop = TRUE])
      } else {
        as.numeric(mat)
      }
    } else if (!is.null(qq$quantiles)) {
      as.numeric(qq$quantiles)
    } else {
      as.numeric(unlist(qq, use.names = FALSE))
    }
  }, error = function(e) {
    as.numeric(stats::quantile(xv, probs = c(1 / 3, 2 / 3), na.rm = TRUE))
  })
  if (length(qs) < 2L || any(!is.finite(qs))) return(NULL)
  if (qs[1L] >= qs[2L]) qs[2L] <- qs[1L] + .Machine$double.eps
  grp_chr <- rep("Q3", length(xv))
  grp_chr[is.na(xv)] <- NA_character_
  grp_chr[!is.na(xv) & xv < qs[1L]] <- "Q1"
  grp_chr[!is.na(xv) & xv >= qs[1L] & xv < qs[2L]] <- "Q2"
  as.numeric(factor(grp_chr, levels = c("Q1", "Q2", "Q3")))
}

pipeline_rcs_nhanes_trend_p <- function(design, covs, index_var, outcome_col, disease_lbl, cfg = NULL) {
  if (is.null(design) || !requireNamespace("survey", quietly = TRUE)) return(NA_real_)
  index_var <- as.character(index_var %||% "")[1L]
  if (!nzchar(index_var)) return(NA_real_)
  des <- design
  if (!"Num" %in% names(des$variables)) {
    num <- pipeline_rcs_nhanes_weighted_tertile_num(des, index_var)
    if (is.null(num)) return(NA_real_)
    des$variables$Num <- num
  }
  if (!"Disease_Group" %in% names(des$variables)) {
    oc <- outcome_col %||% "Disease"
    if (exists("pipeline_outcome_as_01", mode = "function")) {
      des <- survey::update(
        des,
        Disease_Group = pipeline_outcome_as_01(
          des$variables[[oc]], cfg = cfg, case_label = disease_lbl
        )
      )
    } else {
      return(NA_real_)
    }
  }
  covs <- intersect(as.character(covs %||% character(0)), names(des$variables))
  covs <- setdiff(covs, c(index_var, "Group", "Num", "Disease_Group", "Disease"))
  rhs <- paste(c("Num", covs), collapse = "+")
  fit <- tryCatch(
    survey::svyglm(
      stats::as.formula(paste("Disease_Group ~", rhs)),
      design = des,
      family = stats::quasibinomial()
    ),
    error = function(e) NULL
  )
  if (is.null(fit)) return(NA_real_)
  p <- tryCatch(
    survey::regTermTest(fit, ~Num)$p,
    error = function(e) NA_real_
  )
  if (is.finite(p)) return(p)
  sm <- tryCatch(summary(fit)$coefficients, error = function(e) NULL)
  if (is.null(sm) || !("Num" %in% rownames(sm))) return(NA_real_)
  pr_i <- grep("^Pr\\(", colnames(sm))
  if (!length(pr_i)) return(NA_real_)
  p <- suppressWarnings(as.numeric(sm["Num", pr_i[1L], drop = TRUE]))
  if (is.finite(p)) return(p)
  if (exists(".lnw00_wald_p_from_estimate", mode = "function")) {
    return(.lnw00_wald_p_from_estimate(sm["Num", "Estimate"], sm["Num", "Std. Error"]))
  }
  NA_real_
}

#' MIMIC/GLM：与 logistic tertile Table 2 相同的 Num trend P。
pipeline_rcs_incidence_trend_p <- function(data, covs, index_var, outcome_col = "Disease") {
  if (is.null(data) || !nrow(data)) return(NA_real_)
  index_var <- as.character(index_var %||% "")[1L]
  if (!index_var %in% names(data)) return(NA_real_)
  df <- as.data.frame(data)
  xv <- suppressWarnings(as.numeric(df[[index_var]]))
  if (!"Num" %in% names(df)) {
    qs <- stats::quantile(xv, probs = c(1 / 3, 2 / 3), na.rm = TRUE, names = FALSE)
    if (length(qs) < 2L || any(!is.finite(qs))) return(NA_real_)
    grp <- rep("Q3", length(xv))
    grp[!is.na(xv) & xv < qs[1L]] <- "Q1"
    grp[!is.na(xv) & xv >= qs[1L] & xv < qs[2L]] <- "Q2"
    df$Group <- factor(grp, levels = c("Q1", "Q2", "Q3"))
    df$Num <- as.numeric(df$Group)
  }
  oc <- outcome_col %||% "Disease"
  if (!oc %in% names(df) && "Disease_Group" %in% names(df)) oc <- "Disease_Group"
  if (oc %in% names(df) && !is.numeric(df[[oc]])) {
    df[[oc]] <- as.integer(df[[oc]] %in% c(1, "1", TRUE))
  }
  covs <- intersect(as.character(covs %||% character(0)), names(df))
  covs <- setdiff(covs, c(index_var, "Group", "Num", oc, "Disease_Group"))
  rhs <- paste(c("Num", covs), collapse = "+")
  fit <- tryCatch(
    stats::glm(
      stats::as.formula(paste(oc, "~", rhs)),
      data = df,
      family = stats::binomial()
    ),
    error = function(e) NULL
  )
  if (is.null(fit)) return(NA_real_)
  sm <- tryCatch(summary(fit)$coefficients, error = function(e) NULL)
  if (is.null(sm) || !("Num" %in% rownames(sm))) return(NA_real_)
  pr_i <- grep("^Pr\\(", colnames(sm))
  if (!length(pr_i)) return(NA_real_)
  suppressWarnings(as.numeric(sm["Num", pr_i[1L]]))
}

pipeline_rcs_p_overall_source <- function(cfg, block_cfg = list()) {
  if (!is.list(block_cfg)) block_cfg <- list()
  rcs_nh <- cfg$rcs_nhanes %||% list()
  if (!is.list(rcs_nh)) rcs_nh <- list()
  rcs_in <- cfg$rcs_incidence %||% list()
  if (!is.list(rcs_in)) rcs_in <- list()
  src <- block_cfg$p_overall_source %||%
    rcs_nh$p_overall_source %||%
    rcs_in$p_overall_source %||%
    cfg$p_overall_source %||%
    "spline_joint"
  tolower(as.character(src)[1L])
}

#' RCS 面板 P for overall：默认样条联合检验；table2_trend 与 Table 2 p for trend 对齐。
pipeline_rcs_override_p_overall <- function(res, ctx, cfg, panel,
                                             block_cfg = list(), ...) {
  if (is.null(res)) return(res)
  src <- pipeline_rcs_p_overall_source(cfg, block_cfg)
  if (!identical(src, "table2_trend")) return(res)

  pt <- NA_real_

  # 1) 优先从 ctx$results$logistic_table2_trend_p 读（最可靠）
  tp <- tryCatch(ctx[["results"]][["logistic_table2_trend_p"]], error = function(e) NULL)
  if (is.null(tp)) tp <- tryCatch(ctx$results$logistic_table2_trend_p, error = function(e) NULL)
  if (!is.null(tp) && is.list(tp)) {
    pv <- suppressWarnings(as.numeric(tp[[as.character(panel)[1L]]]))
    if (length(pv) > 0 && is.finite(pv[1])) pt <- pv[1]
  }

  # 2) 从磁盘读 Table 2
  if (!is.finite(pt)) {
    tb <- tryCatch(pipeline_logistic_table2_read_from_disk(ctx), error = function(e) NULL)
    if (!is.null(tb)) {
      pv <- tryCatch(pipeline_logistic_table2_trend_p_from_tb(tb, panel), error = function(e) NA_real_)
      if (is.finite(pv)) pt <- pv
    }
  }

  # 3) 从 survey design 算
  extra <- list(...)
  if (!is.finite(pt) && !is.null(extra$design) &&
      exists("pipeline_rcs_nhanes_trend_p", mode = "function")) {
    covs <- switch(panel,
      crude = character(0),
      model1 = extra$M1 %||% character(0),
      model2 = extra$M2 %||% character(0),
      model3 = extra$M3 %||% character(0),
      character(0)
    )
    pt <- tryCatch(
      pipeline_rcs_nhanes_trend_p(
        extra$design, covs,
        extra$index_var, extra$outcome_col, extra$disease_lbl, extra$cfg
      ),
      error = function(e) NA_real_
    )
  }

  if (is.finite(pt)) {
    res$p_overall <- pt
    attr(res, "p_overall_source") <- "table2_trend"
  }
  res
}

pipeline_fully_adjusted_factors <- function(ctx, fallback = character(0)) {
  out <- as.character(
    ctx$results$logistic_final_factors %||%
      ctx$results$cox_final_factors %||%
      fallback %||%
      ctx$results$nhanes_logistic_M2 %||%
      ctx$results$logistic_model2_factors %||%
      ctx$results$Model2Factors %||%
      character(0)
  )
  unique(out[nzchar(out)])
}

pipeline_apply_model3_after_m2 <- function(ctx, cfg, M2, data_cols, index_var = NULL,
                                           sig_fn = NULL, method = "trend_or_any_group",
                                           threshold = 0.05, M1 = NULL) {
  M2 <- unique(as.character(M2 %||% character(0)))
  M2 <- M2[nzchar(M2)]
  M1 <- unique(as.character(M1 %||% character(0)))
  M1 <- M1[nzchar(M1)]
  M3 <- pipeline_resolve_model3_factors(M2, cfg, data_cols, index_var)
  if (!length(M3) || !length(setdiff(M3, M2))) {
    ctx <- pipeline_store_model3(ctx, character(0), FALSE, M2)
    return(list(
      ctx = ctx, M2 = M2, M3 = character(0), m3_sig = FALSE,
      final = M2, include_m3 = FALSE
    ))
  }
  m3_sig <- FALSE
  if (is.function(sig_fn)) {
    m3_sig <- isTRUE(tryCatch(sig_fn(M3), error = function(e) FALSE))

    # ── Model3 降级链（config$model3_degrade$enable 默认 TRUE）────────────
    # 1) M3 不显著 → 在保留人口学 + Model1 的前提下，对 Model2 临床 extras
    #    做递减子集搜索，直到 Model3 显著
    # 2) 全删临床 extras 仍不显著 → 弃用 Model3（下游用原 Model2）
    # 双库：默认禁止按库改写 Model2（避免两库脚注分叉）；共用子集由 Gate C /
    # force_model2 锁定。若确需按库降级，设 model3_degrade$allow_per_db_m2_change=TRUE。
    deg <- (cfg$model3_degrade %||% list())
    deg_enable <- isTRUE(deg$enable %||% TRUE)
    dual_on <- isTRUE((cfg$dual_db %||% list())$enable)
    allow_per_db <- isTRUE(deg$allow_per_db_m2_change %||% FALSE)
    if (!m3_sig && deg_enable && dual_on && !allow_per_db) {
      if (isTRUE(pipeline_model3_show_insignificant(cfg))) {
        cli::cli_alert_info(
          "Model3 双库不显著：仍导出 Model3 列，下游全调整回退 Model2。"
        )
        final <- pipeline_finalize_adjusted_factors(M2, M3, FALSE)
        ctx <- pipeline_store_model3(ctx, M3, FALSE, final, announce = is.function(sig_fn))
        return(list(
          ctx = ctx, M2 = M2, M3 = M3, m3_sig = FALSE,
          final = final, include_m3 = TRUE, model3_insignificant_dual = TRUE
        ))
      }
      cli::cli_alert_warning(
        "Model3 不显著且双库已启用：跳过按库降级（避免两库 Model2 分叉）。请用 Gate C / force_model2 锁定两库共用子集。"
      )
      ctx <- pipeline_store_model3(ctx, character(0), FALSE, M2)
      return(list(
        ctx = ctx, M2 = M2, M3 = character(0), m3_sig = FALSE,
        final = M2, include_m3 = FALSE, model3_dropped = TRUE,
        dual_degrade_skipped = TRUE
      ))
    }
    if (!m3_sig && deg_enable) {
      demo_kw <- c("Age", "Gender", "Sex", "Race", "Education", "PIR",
                   "Marital_Status", "Income", "Ethnicity")
      m2_base <- M2
      protected <- unique(c(demo_kw, M1))
      clinical <- setdiff(m2_base, protected)
      found_sig <- FALSE
      dropped_trace <- character(0)

      try_cand <- function(cand_M2) {
        cand_M2 <- unique(as.character(cand_M2))
        cand_M2 <- cand_M2[nzchar(cand_M2)]
        # 保持原 Model2 顺序
        cand_M2 <- m2_base[m2_base %in% cand_M2]
        if (!length(cand_M2)) return(FALSE)
        cand_M3 <- pipeline_resolve_model3_factors(cand_M2, cfg, data_cols, index_var)
        if (!length(cand_M3) || !length(setdiff(cand_M3, cand_M2))) return(FALSE)
        isTRUE(tryCatch(sig_fn(cand_M3), error = function(e) FALSE))
      }

      # 递减保留临床 extras（先试少删，再试多删）；最后试仅 protected
      keep_sets <- list()
      if (length(clinical)) {
        if (exists("covariate_subsets_decreasing_from_full", mode = "function")) {
          keep_sets <- covariate_subsets_decreasing_from_full(clinical)
        } else {
          keep_sets <- c(
            list(clinical),
            lapply(clinical, function(v) setdiff(clinical, v)),
            list(character(0))
          )
        }
      }
      keep_sets <- c(keep_sets, list(character(0)))
      # 去重；跳过与全集相同的首次（已在上面测过全量 M3）
      seen <- character(0)
      for (keep_clin in keep_sets) {
        keep_clin <- unique(as.character(keep_clin))
        key <- paste(sort(keep_clin), collapse = "\x01")
        if (key %in% seen) next
        seen <- c(seen, key)
        if (length(clinical) && identical(sort(keep_clin), sort(clinical))) next
        cand_M2 <- unique(c(intersect(m2_base, protected), keep_clin))
        cand_M2 <- m2_base[m2_base %in% cand_M2]
        cand_M3 <- pipeline_resolve_model3_factors(cand_M2, cfg, data_cols, index_var)
        if (!length(cand_M3) || !length(setdiff(cand_M3, cand_M2))) next
        if (!isTRUE(tryCatch(sig_fn(cand_M3), error = function(e) FALSE))) next
        dropped_trace <- setdiff(clinical, keep_clin)
        M2 <- cand_M2
        M3 <- cand_M3
        m3_sig <- TRUE
        found_sig <- TRUE
        break
      }

      if (found_sig) {
        cli::cli_alert_info(
          "Model3 降级链：删除 {paste(dropped_trace, collapse = ', ')} 后 Model3 显著；新 Model2: {paste(M2, collapse = ', ')}"
        )
      } else {
        cli::cli_alert_warning(
          "Model3 降级链：临床协变量子集搜索后仍不显著 → 弃用 Model3，下游统一 Model2。"
        )
        ctx <- pipeline_store_model3(ctx, character(0), FALSE, m2_base)
        return(list(
          ctx = ctx, M2 = m2_base, M3 = character(0), m3_sig = FALSE,
          final = m2_base, include_m3 = FALSE, model3_dropped = TRUE
        ))
      }
    }
  }
  final <- pipeline_finalize_adjusted_factors(M2, M3, m3_sig)
  ctx <- pipeline_store_model3(ctx, M3, m3_sig, final, announce = is.function(sig_fn))
  list(ctx = ctx, M2 = M2, M3 = M3, m3_sig = m3_sig, final = final, include_m3 = TRUE)
}

pipeline_sci_with_model3_header <- function(line1, line2, include_m3, est = "OR") {
  if (!isTRUE(include_m3)) {
    return(list(line1 = line1, line2 = line2, n_pad = length(line1) - 1L))
  }
  list(
    line1 = c(as.character(line1), "", "Model3", ""),
    line2 = c(as.character(line2), est, "95%CI", "P-value"),
    n_pad = length(line1) + 2L
  )
}

pipeline_sci_model3_ref_cells <- function(include_m3) {
  if (isTRUE(include_m3)) c("Ref", "Ref", "") else character(0)
}

pipeline_model3_table_footnotes <- function(M1, M2, M3 = NULL, m3_significant = NULL, Crude = NULL) {
  pretty <- if (exists("logistic_glm_pretty_var", mode = "function")) {
    logistic_glm_pretty_var
  } else {
    function(v) gsub("_", " ", as.character(v), fixed = TRUE)
  }
  txt <- function(vars) {
    vars <- as.character(vars %||% character(0))
    if (!length(vars)) "none" else paste(vapply(vars, pretty, character(1L)), collapse = ", ")
  }
  Crude <- as.character(Crude %||% character(0))
  crude_line <- if (length(Crude)) {
    paste0("The Crude Model was adjusted by: ", txt(Crude), ".")
  } else {
    "The Crude Model was non-adjusted."
  }
  out <- c(
    crude_line,
    paste0("The Model 1 was adjusted by: ", txt(M1), "."),
    paste0("The Model 2 was adjusted by: ", txt(M2), ".")
  )
  M3 <- as.character(M3 %||% character(0))
  if (length(M3)) {
    out <- c(out, paste0("The Model 3 was adjusted by: ", txt(M3), "."))
    if (!isTRUE(m3_significant)) {
      out <- c(
        out,
        "Model 3 was not statistically significant; fully adjusted estimates use Model 2."
      )
    }
  }
  out
}

pipeline_cox_grouped_significant <- function(data, time_var, event_var,
                                             factor_name, trend_name, covs,
                                             threshold = 0.05) {
  if (!requireNamespace("survival", quietly = TRUE)) return(FALSE)
  covs <- as.character(covs %||% character(0))
  rhs_g <- paste(c(factor_name, covs), collapse = " + ")
  rhs_t <- paste(c(trend_name, covs), collapse = " + ")
  lhs <- paste0("Surv(", time_var, ", ", event_var, ")")
  mf <- tryCatch(
    survival::coxph(stats::as.formula(paste0(lhs, " ~ ", rhs_g)), data = data),
    error = function(e) NULL
  )
  mt <- tryCatch(
    survival::coxph(stats::as.formula(paste0(lhs, " ~ ", rhs_t)), data = data),
    error = function(e) NULL
  )
  p_groups <- numeric(0)
  if (!is.null(mf)) {
    sm <- tryCatch(summary(mf)$coefficients, error = function(e) NULL)
    if (!is.null(sm) && "Pr(>|z|)" %in% colnames(sm)) {
      rn <- rownames(sm)
      hit <- grepl(paste0("^", factor_name), rn)
      p_groups <- suppressWarnings(as.numeric(sm[hit, "Pr(>|z|)"]))
    }
  }
  p_trend <- NA_real_
  if (!is.null(mt)) {
    smt <- tryCatch(summary(mt)$coefficients, error = function(e) NULL)
    if (!is.null(smt) && nrow(smt) >= 1L && "Pr(>|z|)" %in% colnames(smt)) {
      p_trend <- suppressWarnings(as.numeric(smt[1L, "Pr(>|z|)"]))
    }
  }
  isTRUE(pipeline_grouped_term_significant(p_trend, p_groups, "trend_or_any_group", threshold))
}

pipeline_table_p_cols <- function(n_col, binary_layout = FALSE) {
  n_col <- as.integer(n_col)[1L]
  if (!is.finite(n_col) || n_col < 5L) return(integer(0))
  if (isTRUE(binary_layout)) {
    cols <- c(5L, 8L, 11L)
    if (n_col >= 14L) cols <- c(cols, 14L)
    return(cols)
  }
  cols <- c(6L, 9L, 12L)
  if (n_col >= 15L) cols <- c(cols, 15L)
  cols
}

pipeline_glm_or_ci_p <- function(model, row) {
  if (is.null(model)) return(c("", "", ""))
  sm <- tryCatch(summary(model)$coefficients, error = function(e) NULL)
  if (is.null(sm) || row > nrow(sm)) return(c("", "", ""))
  est <- tryCatch(stats::coef(model)[row], error = function(e) NA_real_)
  ci <- tryCatch(suppressMessages(stats::confint(model)), error = function(e) NULL)
  p <- if ("Pr(>|z|)" %in% colnames(sm)) sm[row, "Pr(>|z|)"] else sm[row, ncol(sm)]
  ci_str <- if (!is.null(ci) && nrow(ci) >= row) {
    paste0("(", round(exp(ci[row, 1L]), 3), ",", round(exp(ci[row, 2L]), 3), ")")
  } else {
    ""
  }
  c(
    if (is.finite(est)) round(exp(est), 3) else "",
    ci_str,
    if (is.finite(as.numeric(p))) round(as.numeric(p), 4) else ""
  )
}

#' 给已有 Crude/M1/M2 表追加 Model3 三列（GLM 发病敏感性表）
pipeline_glm_bind_model3_columns <- function(rt, data, outcome, factor_name, trend_name,
                                            cont_name, M3, group_labels) {
  M3 <- as.character(M3 %||% character(0))
  if (!length(M3) || is.null(rt)) return(rt)
  y <- as.character(outcome)[1L]
  rhs <- paste(c(factor_name, M3), collapse = "+")
  rhs_t <- paste(c(trend_name, M3), collapse = "+")
  mf <- tryCatch(stats::glm(stats::as.formula(paste0(y, "~", rhs)), data = data, family = binomial), error = function(e) NULL)
  mt <- tryCatch(stats::glm(stats::as.formula(paste0(y, "~", rhs_t)), data = data, family = binomial), error = function(e) NULL)
  mc <- NULL
  if (!is.null(cont_name) && nzchar(cont_name) && cont_name %in% names(data)) {
    rhs_c <- paste(c(cont_name, M3), collapse = "+")
    mc <- tryCatch(stats::glm(stats::as.formula(paste0(y, "~", rhs_c)), data = data, family = binomial), error = function(e) NULL)
  }
  if (is.matrix(rt)) rt <- as.data.frame(rt, stringsAsFactors = FALSE)
  n <- nrow(rt)
  extra <- vector("list", n)
  glv <- as.character(group_labels)
  non_ref <- if (length(glv) >= 2L) glv[-1L] else character(0)
  for (i in seq_len(n)) {
    lab <- trimws(as.character(rt[i, 1L]))
    if (i == 1L) {
      extra[[i]] <- c("", "Model3", "")
    } else if (i == 2L) {
      extra[[i]] <- c("OR", "95%CI", "P-value")
    } else if (grepl("\\(Ref\\)$", lab)) {
      extra[[i]] <- c("Ref", "Ref", "")
    } else if (identical(lab, "p for trend")) {
      extra[[i]] <- c("", "", pipeline_glm_or_ci_p(mt, 2L)[3L])
    } else if (lab %in% non_ref) {
      idx <- match(lab, non_ref) + 1L
      extra[[i]] <- pipeline_glm_or_ci_p(mf, idx)
    } else if (grepl("continuous", lab, ignore.case = TRUE)) {
      extra[[i]] <- pipeline_glm_or_ci_p(mc, 2L)
    } else {
      extra[[i]] <- c("", "", "")
    }
  }
  add <- do.call(rbind, extra)
  colnames(add) <- NULL
  out <- cbind(as.matrix(rt), add)
  rownames(out) <- NULL
  colnames(out) <- NULL
  out
}

pipeline_glm_apply_model3 <- function(ctx, cfg, data, outcome, index_var, factor_name, trend_name,
                                      M2, tb, group_labels) {
  pack <- pipeline_apply_model3_after_m2(ctx, cfg, M2, names(data), index_var)
  ctx <- pack$ctx
  if (!isTRUE(pack$include_m3)) {
    return(list(ctx = ctx, tb = tb, M3 = character(0), m3_sig = FALSE, final = M2))
  }
  tb2 <- tryCatch(
    pipeline_glm_bind_model3_columns(
      tb, data, outcome, factor_name, trend_name, index_var, pack$M3, group_labels
    ),
    error = function(e) {
      cli::cli_alert_warning("Model3 GLM 列追加失败，回退 Model2: {e$message}")
      NULL
    }
  )
  if (is.null(tb2)) {
    ctx <- pipeline_store_model3(ctx, pack$M3, FALSE, M2)
    return(list(ctx = ctx, tb = tb, M3 = pack$M3, m3_sig = FALSE, final = M2))
  }
  m3_sig <- pipeline_model3_sig_from_table(tb2, group_labels)
  final <- pipeline_finalize_adjusted_factors(M2, pack$M3, m3_sig)
  ctx <- pipeline_store_model3(ctx, pack$M3, m3_sig, final)
  list(ctx = ctx, tb = tb2, M3 = pack$M3, m3_sig = m3_sig, final = final)
}
