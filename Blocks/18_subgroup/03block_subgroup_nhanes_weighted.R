###############################################################################
#  subgroup_nhanes_weighted — NHANES 加权亚组森林图（svyglm OR + forestploter，Figure 6 风格）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_ctx_results = nhanes_logistic_selected_scheme 或 nhanes_design_*
#  读 config$subgroup（排序等）、config$nhanes、config$logistic$index_var
###############################################################################

.sgn03_canonical_subgroup_order_vec <- function() {
  c(
    "Age_Group",
    "Gender",
    "BMI",
    "Education",
    "Marital_Status",
    "Income",
    "Smoking",
    "Alcohol_drinking",
    "Race",
    "Weight",
    "Height",
    "Language",
    "Micu_Code",
    "Insurance",
    "Ventilation",
    "Hypertension",
    "Diabetes",
    "T1DM",
    "T2DM",
    "Heart_Failure",
    "Myocardial_Infarction",
    "Atrial_Fibrillation",
    "Stroke",
    "COPD",
    "CKD",
    "Acute_Renal_Failure",
    "Liver_cirrhosis",
    "Hepatitis",
    "Cancer",
    "Hyperlipidemia",
    "Pneumonia",
    "Tuberculosis",
    "Dementia"

  )
}

.sgn03_order_subgroup_vars_clinical <- function(v, req_ord = character(0)) {
  if (exists("subgroup_order_vars", mode = "function")) {
    return(subgroup_order_vars(v, req_ord))
  }
  v <- unique(as.character(v))
  canon <- .sgn03_canonical_subgroup_order_vec()
  c(intersect(canon, v), sort(setdiff(v, canon)))
}

.sgn03_pretty_subgroup_label <- function(x) {
  x <- as.character(x %||% "")
  # 仅下划线→空格；勿把区间连字符「30-44」抹成「30 44」（Fig 6 等森林图标签）
  x <- gsub("_", " ", x, fixed = TRUE)
  x <- gsub("\\s+", " ", x)
  x <- gsub("([0-9]{2})\\s+([0-9]{2})", "\\1-\\2", x, perl = TRUE)
  trimws(x)
}

block_subgroup_nhanes_weighted <- function(ctx) {
  options(survey.lonely.psu = "adjust")
  if (!exists("subgroup_render_forest_figure", mode = "function")) {
    root_sf <- (ctx$config$project$root %||% getwd())
    suppressWarnings(source(file.path(root_sf, "R", "subgroup_forest_plot.R"), local = FALSE))
  }

  cfg        <- ctx$config
  nhanes_cfg <- cfg$nhanes %||% list()
  proj_cfg   <- cfg$project %||% list()
  outcome_col <- cfg$data$outcome_column %||% "Disease"
  disease_lbl <- if (exists("pipeline_outcome_case_label", mode = "function")) {
    pipeline_outcome_case_label(cfg)
  } else {
    as.character(proj_cfg$disease %||% proj_cfg$analysis_group %||% "Case")[1L]
  }
  # analysis_group 占位 "0"/"1" 时改用疾病名，避免 pipeline_outcome_as_01 全 0
  if (identical(trimws(as.character(disease_lbl)[1L]), "0") ||
      identical(trimws(as.character(disease_lbl)[1L]), "1") ||
      !nzchar(trimws(as.character(disease_lbl)[1L]))) {
    disease_lbl <- as.character(proj_cfg$disease %||% "Case")[1L]
  }
  index_var   <- as.character(
    (cfg$logistic %||% list())$index_var %||%
    (cfg$incidence %||% list())$index_var %||% "Index")[1L]

  # 获取选定分组 design（须用 [[ ]] 避免 $ 部分匹配 nhanes_logistic_selected_scheme）
  scheme <- as.character(ctx$results[["nhanes_logistic_selected_scheme"]] %||% "")
  nhanes_sel <- NULL
  if (nzchar(scheme)) {
    scheme_map <- list(
      quartile = list(slot = "nhanes_design_quart",  group_col = "Index_Group_Quartile", label = "Quartile"),
      tertile  = list(slot = "nhanes_design_tert",   group_col = "Index_Group_Tertile",  label = "Tertile"),
      binary   = list(slot = "nhanes_design_binary", group_col = "Index_Group",         label = "Binary")
    )
    sm <- scheme_map[[scheme]]
    if (!is.null(sm)) {
      d_try <- ctx$results[[sm$slot]]
      if (!is.null(d_try)) {
        nhanes_sel <- list(design = d_try, group_col = sm$group_col, label = sm$label)
      }
    }
  }
  if (is.null(nhanes_sel)) {
    for (d_nm in c("nhanes_design_quart", "nhanes_design_tert", "nhanes_design_binary")) {
      d_try <- ctx$results[[d_nm]]
      if (!is.null(d_try)) {
        gc_try <- switch(d_nm,
          nhanes_design_quart  = "Index_Group_Quartile",
          nhanes_design_tert   = "Index_Group_Tertile",
          "Index_Group")
        nhanes_sel <- list(design = d_try, group_col = gc_try, label = d_nm)
        break
      }
    }
  }
  if (is.null(nhanes_sel)) {
    cli::cli_alert_warning("block_subgroup(NHANES): 无可用分组 design，跳过。")
    return(ctx)
  }

  for (pkg in c("survey","forestploter","grid")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      cli::cli_alert_warning("block_subgroup(NHANES): 需要 {pkg}，跳过。"); return(ctx)
    }
  }
  suppressPackageStartupMessages({
    library(survey, warn.conflicts = FALSE)
    library(forestploter); library(grid)
  })

  design_grp <- nhanes_sel$design
  grp_col    <- nhanes_sel$group_col
  grp_lbl    <- nhanes_sel$label %||% "Selected"
  # 连续暴露：亚组内 OR 为每升高 1 单位 index（避免最高分位 0 事件时 OR≈0 导致森林图“空白”）
  use_continuous <- isTRUE((cfg$subgroup %||% list())$exposure_continuous %||% FALSE) ||
    identical(tolower(as.character((cfg$subgroup %||% list())$exposure_type %||% "")[1L]), "continuous")
  if (!use_continuous && nzchar(index_var) && index_var %in% names(design_grp$variables) &&
      grp_col %in% names(design_grp$variables)) {
    # 自动：最高组事件数为 0 → 改连续
    .tmp_y <- tryCatch(
      pipeline_outcome_as_01(
        design_grp$variables[[outcome_col]],
        case_label = {
          if (exists("pipeline_outcome_case_label", mode = "function"))
            pipeline_outcome_case_label(cfg)
          else disease_lbl
        }
      ),
      error = function(e) NULL
    )
    if (!is.null(.tmp_y)) {
      hi <- tail(levels(factor(design_grp$variables[[grp_col]])), 1L)
      n_hi_ev <- sum(
        as.character(design_grp$variables[[grp_col]]) == hi & as.numeric(.tmp_y) == 1,
        na.rm = TRUE
      )
      if (is.finite(n_hi_ev) && n_hi_ev <= 0L) {
        use_continuous <- TRUE
        cli::cli_alert_warning(
          "block_subgroup(NHANES): 最高组 [{hi}] 事件数=0，改用连续暴露 {index_var} 估计亚组 OR（避免森林图 OR≈0）"
        )
      }
    }
  }
  if (use_continuous) {
    if (!index_var %in% names(design_grp$variables)) {
      cli::cli_alert_warning("block_subgroup(NHANES): 连续暴露缺列 {index_var}，跳过。")
      return(ctx)
    }
    grp_col <- index_var
    grp_lbl <- paste0(index_var, " continuous")
  }

  # ── 若当前 index_var 与上次 block_cutoff 的指标不同，用基础 design + ROC cutoff 重建分组 ──
  stored_cutoff_idx <- ctx$results$nhanes_cutoff_index %||% ""
  base_design_ok <- !is.null(ctx$results$nhanes_design) &&
                    index_var %in% names(ctx$results$nhanes_design$variables)
  if (!identical(stored_cutoff_idx, index_var) && base_design_ok) {
    # 在 step*_cutoff 目录里查找当前指标的 ROC cutoff
    .find_cutoff <- function(ix) {
      out_base <- ctx$output_dir %||% ""
      if (!nzchar(out_base)) return(NULL)
      parent_dir <- dirname(normalizePath(out_base, winslash = "/", mustWork = FALSE))
      tryCatch({
        all_dirs <- list.dirs(parent_dir, recursive = FALSE, full.names = TRUE)
        cut_dirs <- all_dirs[grepl("cutoff", basename(all_dirs), ignore.case = TRUE)]
        for (d in cut_dirs) {
          fp <- file.path(d, paste0("cutoff_", ix, ".csv"))
          if (file.exists(fp)) {
            df <- read.csv(fp, stringsAsFactors = FALSE)
            if ("cutoff" %in% names(df)) {
              val <- suppressWarnings(as.numeric(df$cutoff[1L]))
              if (is.finite(val)) return(val)
            }
          }
        }
        NULL
      }, error = function(e) NULL)
    }
    cv <- .find_cutoff(index_var)
    if (!is.null(cv)) {
      bd <- ctx$results$nhanes_design
      vals <- bd$variables[[index_var]]
      vmin <- min(vals, na.rm=TRUE); vmax <- max(vals, na.rm=TRUE)
      if (cv > vmin && cv < vmax) {
        lbl_lo <- paste0("<", round(cv, 4))
        lbl_hi <- paste0(">=",  round(cv, 4))
        bd <- stats::update(bd,
          Index_Group = factor(
            ifelse(bd$variables[[index_var]] < cv, lbl_lo, lbl_hi),
            levels = c(lbl_lo, lbl_hi)))
        design_grp <- bd
        grp_col    <- "Index_Group"
        grp_lbl    <- "Binary"
        cli::cli_alert_info(
          "block_subgroup(NHANES): {index_var} 与上次 cutoff 指标（{stored_cutoff_idx}）不同，已用 ROC cutoff={round(cv,4)} 重建 Index_Group。"
        )
      }
    } else {
      cli::cli_alert_warning(
        "block_subgroup(NHANES): 未找到 {index_var} 的 ROC cutoff 文件，使用现有 design（可能来自 {stored_cutoff_idx}）。"
      )
    }
  }

  # Update Disease_Group（stats::update → survey.design 方法；勿用未导出的 survey::update.svydesign）
  design_grp <- stats::update(design_grp,
    Disease_Group = pipeline_outcome_as_01(design_grp$variables[[outcome_col]], case_label = disease_lbl))

  sub_cfg <- cfg$subgroup %||% list()
  forbid_extra <- c(grp_col, "Disease_Group", outcome_col)
  if (!exists("subgroup_build_variable_pool", mode = "function")) {
    suppressWarnings(source(file.path(getwd(), "R", "subgroup_vars.R"), local = FALSE))
  }

  skip_age <- subgroup_age_forbidden(cfg, forbid_extra)
  if (!skip_age && !"Age_Group" %in% names(design_grp$variables) &&
      "Age" %in% names(design_grp$variables)) {
    # 与 subgroup_incidence / CHARLS 对齐：默认 Age <65 / ≥65；
    # 仅当显式配置 age_group_cutoffs 时才用多档切点。
    sub_age_cut <- sub_cfg$age_cutoff %||% nhanes_cfg$age_cutoff %||% 65L
    if (!is.null(nhanes_cfg$age_group_cutoffs) || !is.null(sub_cfg$age_group_cutoffs)) {
      age_cuts   <- nhanes_cfg$age_group_cutoffs %||% sub_cfg$age_group_cutoffs
      age_labels <- nhanes_cfg$age_group_labels %||% sub_cfg$age_group_labels %||%
        c("<30", "30-44", "45-59", "\u226560")
      design_grp$variables$Age_Group <- cut(
        design_grp$variables$Age,
        breaks = c(-Inf, age_cuts, Inf),
        labels = age_labels, right = FALSE)
    } else {
      age_lo <- paste0("< ", sub_age_cut)
      age_hi <- paste0("\u2265 ", sub_age_cut)
      design_grp$variables$Age_Group <- factor(
        ifelse(design_grp$variables$Age < sub_age_cut, age_lo, age_hi),
        levels = c(age_lo, age_hi)
      )
      cli::cli_alert_info(
        "NHANES Age_Group 与 CHARLS 对齐: {age_lo} / {age_hi}"
      )
    }
  }

  if (isTRUE(sub_cfg$merge_borderline_levels %||% FALSE)) {
    .merge_borderline_levels <- function(dg) {
      for (col in names(dg$variables)) {
        x <- dg$variables[[col]]
        if (!is.factor(x)) next
        lvs <- levels(x)
        bl_idx <- which(grepl("borderline", lvs, ignore.case = TRUE))
        if (!length(bl_idx)) next
        target_idx <- which(grepl("^(no|none|normal|neg|0|false)", lvs, ignore.case = TRUE))
        if (!length(target_idx)) target_idx <- setdiff(seq_along(lvs), bl_idx)[1L]
        if (!length(target_idx)) next
        target_lv <- lvs[target_idx[1L]]
        new_x <- as.character(x)
        new_x[new_x %in% lvs[bl_idx]] <- target_lv
        keep_lvs <- lvs[!lvs %in% lvs[bl_idx]]
        dg$variables[[col]] <- factor(new_x, levels = keep_lvs)
        cli::cli_alert_info(
          "block_subgroup(NHANES): {col} 中 [{paste(lvs[bl_idx], collapse='/')}] 已合并到 [{target_lv}]（borderline → 低风险组）。"
        )
      }
      dg
    }
    design_grp <- .merge_borderline_levels(design_grp)
  }

  if (use_continuous) {
    # 连续：每层 Disease_Group ~ index；系数行 = index_var
    high_grp <- index_var
    grp_levels <- index_var
  } else {
    grp_levels <- levels(factor(design_grp$variables[[grp_col]]))
    high_grp   <- tail(grp_levels, 1)   # highest category = comparison group
  }

  min_group_size <- subgroup_resolve_min_n(sub_cfg, nrow(design_grp$variables))
  req <- as.character(sub_cfg$required_subgroup_vars %||% sub_cfg$vars %||% character(0))
  if (identical(sub_cfg$var_source %||% "table1_categorical", "required") && length(req)) {
    forbid <- subgroup_default_forbid(cfg, forbid_extra)
    var_subgroups <- intersect(req, names(design_grp$variables))
    var_subgroups <- setdiff(var_subgroups, forbid)
    cli::cli_alert_info("NHANES required subgroup vars: {paste(var_subgroups, collapse=', ')}")
  } else {
    pool_built <- subgroup_build_variable_pool(
      ctx, design_grp$variables, cfg, db_name = "nhanes"
    )
    var_subgroups <- setdiff(pool_built$vars, forbid_extra)
  }
  var_subgroups <- subgroup_vars_pass_min_n(
    design_grp$variables, var_subgroups, min_group_size
  )
  # 与 CHARLS 一致：始终走 clinical canon（Age_Group 优先），避免 req 打乱两库顺序
  var_subgroups <- .sgn03_order_subgroup_vars_clinical(var_subgroups, character(0))
  if (!length(var_subgroups)) {
    cli::cli_alert_warning("block_subgroup(NHANES): 无可用亚组变量（Table 1 / min_n），跳过。")
    return(ctx)
  }
  cli::cli_alert_info("NHANES 亚组变量: {paste(var_subgroups, collapse=', ')}")

  design_grp$variables <- subgroup_apply_level_order(
    design_grp$variables, var_subgroups, cfg
  )

  # Per-subgroup svyglm
  .one_subgroup <- function(sub_var, des, min_n) {
    levs <- levels(factor(des$variables[[sub_var]]))
    sub_list <- lapply(levs, function(l) {
      sub_d <- tryCatch(
        subset(des, des$variables[[sub_var]] == l),
        error = function(e) NULL)
      if (is.null(sub_d) || nrow(sub_d$variables) < min_n) return(NULL)
      fit <- tryCatch(
        survey::svyglm(
          stats::as.formula(paste0("Disease_Group ~ ", grp_col)),
          design = sub_d, family = quasibinomial()),
        error = function(e) NULL)
      if (is.null(fit)) return(NULL)
      co <- summary(fit)$coefficients
      if (isTRUE(use_continuous)) {
        tgt <- grep(paste0("^", grp_col, "$"), rownames(co))
        if (!length(tgt)) tgt <- 2L
      } else {
        tgt <- tail(grep(high_grp, rownames(co), fixed = FALSE), 1)
      }
      if (!length(tgt) || !is.finite(tgt[1L]) || tgt[1L] > nrow(co)) return(NULL)
      tgt <- tgt[1L]
      est <- co[tgt,"Estimate"]; se <- co[tgt,"Std. Error"]; pv <- co[tgt,4]
      n_ev  <- sum(sub_d$variables$Disease_Group == 1, na.rm=TRUE)
      n_tot <- nrow(sub_d$variables)
      data.frame(
        Subgroup = sub_var, Levels = l,
        Events   = paste0(n_ev, "/", n_tot),
        OR = exp(est), Lower = exp(est - 1.96*se), Upper = exp(est + 1.96*se),
        P.value  = pv, stringsAsFactors = FALSE)
    })
    res_df <- do.call(rbind, Filter(Negate(is.null), sub_list))
    if (is.null(res_df) || !nrow(res_df)) return(NULL)
    # Interaction P
    fml_i <- stats::as.formula(
      paste0("Disease_Group ~ ", grp_col, " * ", sub_var))
    fit_i <- tryCatch(
      survey::svyglm(fml_i, design = des, family = quasibinomial()),
      error = function(e) NULL)
    if (!is.null(fit_i)) {
      ci <- summary(fit_i)$coefficients
      ir <- grep(paste0(high_grp,"|",sub_var), rownames(ci))
      ir <- ir[grepl(":", rownames(ci)[ir])]
      res_df$P.inter <- if (length(ir)) ci[ir[1], 4] else NA_real_
    } else {
      res_df$P.inter <- NA_real_
    }
    res_df
  }

  all_res <- list()
  for (v in var_subgroups) {
    r <- tryCatch(
      .one_subgroup(v, design_grp, min_group_size),
      error = function(e) {
        cli::cli_alert_warning("NHANES subgroup '{v}' 失败: {e$message}"); NULL })
    if (!is.null(r) && nrow(r) > 0) all_res[[v]] <- r
  }
  if (!length(all_res)) {
    cli::cli_alert_warning("NHANES 亚组：所有变量均无有效结果，跳过。"); return(ctx)
  }

  dt_raw <- do.call(rbind, all_res)
  total_n <- nrow(design_grp$variables)
  res_glm <- subgroup_nhanes_results_to_glm_table(dt_raw, total_n, .sgn03_pretty_subgroup_label)
  plot_df <- subgroup_prepare_forest_plot_df(res_glm, "OR")
  if (is.null(plot_df)) {
    cli::cli_alert_warning("NHANES 亚组：森林图数据构建失败，跳过。")
    return(ctx)
  }

  ref_grp <- cfg$project$reference_group %||% "Control"
  arrow_lab <- subgroup_forest_arrow_lab(ref_grp, disease_lbl)
  subgroup_render_forest_figure(
    ctx, plot_df, var_subgroups, sub_cfg,
    fig_caption = paste0("Weighted Subgroup of ", index_var, " (", grp_lbl, ")"),
    effect_sym = "OR",
    arrow_lab = arrow_lab
  )

  # 亚组已有森林图，默认不再导出 Table 4（可用 subgroup$export_table=TRUE 打开）
  if (isTRUE(sub_cfg$export_table %||% FALSE)) {
    tbl_export <- res_glm
    if ("Variable" %in% names(tbl_export)) {
      tbl_export$Variable <- gsub("_", " ", as.character(tbl_export$Variable), fixed = TRUE)
    }
    if (all(c("Point Estimate", "Lower", "Upper") %in% names(tbl_export))) {
      tbl_export[["OR (95% CI)"]] <- ifelse(
        is.na(suppressWarnings(as.numeric(tbl_export$"Point Estimate"))), "",
        sprintf(
          "%s (%s\u2013%s)",
          formatC(as.numeric(tbl_export$"Point Estimate"), format = "f", digits = 2),
          formatC(as.numeric(tbl_export$Lower), format = "f", digits = 2),
          formatC(as.numeric(tbl_export$Upper), format = "f", digits = 2)
        )
      )
    }
    disease_lbl <- cfg$project$disease %||% "Psoriasis"
    tbl_caption <- sub_cfg$table_caption %||% paste0(
      "Weighted subgroup analysis of ", index_var, " and ", disease_lbl,
      " (NHANES, ", grp_lbl, ", OR)"
    )
    pub <- pub_paths(
      ctx, ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables"),
      "supp_table", tbl_caption, "xlsx"
    )
    tryCatch(
      export_sci_table(tbl_export, pub$filepath, title = pub$title),
      error = function(e) cli::cli_alert_warning("NHANES 亚组表导出失败: {e$message}")
    )
  }

  ctx$results$nhanes_subgroup       <- dt_raw
  ctx$results$nhanes_subgroup_label <- grp_lbl
  ctx$results$subgroup_vars_used    <- var_subgroups
  cli::cli_alert_success("block_subgroup(NHANES 加权亚组) 完成。")
  ctx
}

register_block(
  "subgroup_nhanes_weighted",
  block_subgroup_nhanes_weighted,
  "NHANES 加权亚组森林图（svyglm OR + forestploter）"
)
