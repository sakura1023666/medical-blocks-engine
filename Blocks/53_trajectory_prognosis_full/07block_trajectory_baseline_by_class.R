###############################################################################
#  trajectory_baseline_by_class — 潜类别（trajectory_class）基线特征对比表（Table S5）
#
#  迁移自 TableS5.R：按 JLCM 潜类别分组的基线特征对比表（Basic Characteristics /
#  Comorbidities / Laboratory / 28-day Outcomes 分节 + gtsummary 组间比较 + 分节
#  加粗表头的 Excel 导出）。相比原脚本的改动：
#    - 不再从外部 RData + class csv 重新拼接数据，直接读 ctx$data$imputed 里
#      trajectory_jlcm（assign_class_ng）已回写的 trajectory_class 列；
#    - 不再需要 swap_class 手工翻转（本 pipeline 全程共用同一份 class 赋值，
#      各 block 之间类别编号天然一致，无需像原脚本那样在每个独立脚本里各自反转）；
#    - vars_to_include 默认从 ctx$results$Model1Factors ∪ Model2Factors
#      （+ 生存时间/结局列）自动推断，而不是写死变量清单；仍可在 config 里显式指定。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_upstream = trajectory_jlcm（assign_class_ng 需已回写 trajectory_class）
#  require_pkg  = gtsummary, openxlsx, dplyr
#
#  trajectory_baseline_by_class = list(
#    index_vars          = NULL,     # NULL → 用裸列 trajectory_class；否则遍历 trajectory_class_{Index}
#    class_col           = NULL,     # 显式指定类别列名，优先级最高
#    vars_to_include     = NULL,     # NULL → Model1Factors ∪ Model2Factors ∪ 生存时间/结局列
#    extra_vars          = character(0),   # 额外追加变量（与自动推断的并集）
#    survival_time_var   = NULL,     # NULL → config$survival$time_var
#    survival_event_var  = NULL,     # NULL → config$survival$event_var
#    section_rules       = NULL,     # list(Section名 = "正则")，NULL → 内置默认规则
#    section_levels      = c("Basic Characteristics","Comorbidities","Laboratory",
#                             "28-day Outcomes","Other"),
#    title_template       = "Table S5. Baseline characteristics of patients in {ng} latent classes of {Index}",
#    filename_template     = "Table_S5_Baseline_By_Class_{Index}.xlsx",
#    pause_enable         = TRUE,
#    pause_on_no_output   = TRUE
#  ),
#
#  register_block: "trajectory_baseline_by_class"
#  写: ctx$results$trajectory_baseline_by_class[[Index]]
#  落盘: Tables/Table_S5_Baseline_By_Class_{Index}.xlsx
###############################################################################

.tbc07_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.tbc07_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else
    data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "trajectory_baseline_by_class", reason = reason,
    suggestion = suggestion, data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: See ctx$results$pause_point. / ",
    "发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.tbc07_pretty_var <- function(v) {
  if (exists("pipeline_var_display_name", mode = "function"))
    return(pipeline_var_display_name(v, cfg = NULL))
  v2 <- gsub("_", " ", v)
  v2 <- gsub("\\s+", " ", v2)
  trimws(v2)
}

.tbc07_default_section_rules <- function() {
  list(
    "28-day Outcomes"  = "survival|mortality|death|dead|event|vent",
    "Comorbidities"    = "copd|diabetes|stroke|hypertension|comorbid|pneumonia|cancer|charlson",
    "Laboratory Tests" = paste0(
      "hemoglobin|hematocrit|potassium|sodium|creatinine|urea|ureanitrogen|platelet|",
      "wbc|rbc|albumin|bilirubin|glucose|lactate|ast|alt|bicarbonate|anion|chloride|",
      "calcium|inr|pt|ptt|mcv|mch|rdw|hhr|gpr|hrr|aps|icp|sofa|apache|gcs|oasis|sirs"
    ),
    "Vital Signs"      = "hr|heart_rate|rr|spo2|temp|sbp|dbp|map|nbps|nbpd|nbpm|abps|abpd|abpm",
    "Basic Characteristics" = "age|gender|sex|race|weight|height|bmi"
  )
}

.tbc07_assign_section <- function(v, rules, section_levels) {
  vn <- tolower(v)
  for (sec in names(rules)) {
    pat <- rules[[sec]]
    if (nzchar(pat) && grepl(pat, vn)) return(sec)
  }
  if ("Other" %in% section_levels) "Other" else section_levels[length(section_levels)]
}

.tbc07_is_continuous_var <- function(x) {
  if (!(is.numeric(x) || is.integer(x))) return(FALSE)
  ux <- unique(x[is.finite(x) & !is.na(x)])
  length(ux) > 5
}

.tbc07_is_binary_01_num <- function(x) {
  if (!(is.numeric(x) || is.integer(x))) return(FALSE)
  ux <- sort(unique(x[is.finite(x) & !is.na(x)]))
  length(ux) <= 2 && all(ux %in% c(0, 1))
}

.tbc07_as_yesno_factor <- function(x) {
  if (is.factor(x)) x <- as.character(x)
  if (is.logical(x)) return(factor(ifelse(x, "Yes", "No"), levels = c("No", "Yes")))
  if (is.numeric(x) || is.integer(x)) {
    xx <- suppressWarnings(as.integer(as.character(x)))
    if (all(is.na(xx))) return(factor(x))
    if (all(stats::na.omit(unique(xx)) %in% c(0, 1))) {
      out <- ifelse(xx == 1, "Yes", ifelse(xx == 0, "No", NA))
      return(factor(out, levels = c("No", "Yes")))
    }
    return(factor(x))
  }
  if (is.character(x)) {
    xu <- toupper(trimws(x))
    if (all(stats::na.omit(unique(xu)) %in% c("0", "1", "NO", "YES", "N", "Y", "FALSE", "TRUE"))) {
      out <- ifelse(xu %in% c("1", "YES", "Y", "TRUE"), "Yes",
                    ifelse(xu %in% c("0", "NO", "N", "FALSE"), "No", NA))
      return(factor(out, levels = c("No", "Yes")))
    }
    return(factor(trimws(x)))
  }
  factor(x)
}

.tbc07_auto_cast_for_summary <- function(dat, vars) {
  for (v in vars) {
    x <- dat[[v]]
    if (is.factor(x)) {
      lv <- toupper(levels(x))
      if (length(lv) == 2 && all(lv %in% c("0", "1", "NO", "YES", "N", "Y", "FALSE", "TRUE", "FEMALE", "MALE"))) {
        dat[[v]] <- .tbc07_as_yesno_factor(x)
      } else {
        dat[[v]] <- factor(trimws(as.character(x)), exclude = NULL)
      }
      next
    }
    if (is.character(x) || is.logical(x)) { dat[[v]] <- .tbc07_as_yesno_factor(x); next }
    if (is.numeric(x) || is.integer(x)) {
      if (.tbc07_is_continuous_var(x)) {
        dat[[v]] <- suppressWarnings(as.numeric(x))
      } else if (.tbc07_is_binary_01_num(x)) {
        dat[[v]] <- .tbc07_as_yesno_factor(x)
      } else {
        dat[[v]] <- factor(as.character(x))
      }
      next
    }
    dat[[v]] <- factor(as.character(x))
  }
  dat
}

.tbc07_format_p <- function(p) {
  ifelse(is.na(p), "", ifelse(p < 0.001, "<0.001", sprintf("%.3f", p)))
}

.tbc07_make_block_table <- function(tb_body, vars_all, rules, section_levels,
                                     exposure_var = NULL) {
  var_section <- setNames(sapply(vars_all, .tbc07_assign_section, rules = rules, section_levels = section_levels), vars_all)
  if (!is.null(exposure_var) && nzchar(exposure_var) && exposure_var %in% names(var_section)) {
    var_section[[exposure_var]] <- "Exposure index"
    if (!"Exposure index" %in% section_levels) {
      section_levels <- c(section_levels, "Exposure index")
    }
  }
  var_order   <- setNames(seq_along(vars_all), vars_all)

  tb2 <- tb_body |>
    dplyr::mutate(
      Section = var_section[variable],
      Section = ifelse(is.na(Section) | Section == "", "Other", Section),
      Section = factor(Section, levels = section_levels),
      var_order = var_order[variable]
    ) |>
    dplyr::arrange(Section, var_order, row_type)

  stat_cols <- grep("^stat_", names(tb2), value = TRUE)
  rows_list <- list()
  section_row_index <- c()

  for (sec in section_levels) {
    sec_dat <- tb2[tb2$Section == sec & !is.na(tb2$Section), , drop = FALSE]
    if (nrow(sec_dat) == 0) next

    sec_row <- as.data.frame(as.list(stats::setNames(rep("", length(stat_cols) + 2), c("Variable", stat_cols, "P"))), stringsAsFactors = FALSE)
    sec_row$Variable <- as.character(sec)
    rows_list[[length(rows_list) + 1]] <- sec_row
    section_row_index <- c(section_row_index, length(rows_list))

    for (v in unique(sec_dat$variable)) {
      sub <- sec_dat[sec_dat$variable == v, , drop = FALSE]
      lab_row <- sub[sub$row_type == "label", , drop = FALSE][1, , drop = FALSE]
      v_row <- as.data.frame(as.list(stats::setNames(rep("", length(stat_cols) + 2), c("Variable", stat_cols, "P"))), stringsAsFactors = FALSE)
      v_row$Variable <- lab_row$label
      for (sc in stat_cols) v_row[[sc]] <- lab_row[[sc]]
      v_row$P <- .tbc07_format_p(lab_row$p.value)
      rows_list[[length(rows_list) + 1]] <- v_row

      levs <- sub[sub$row_type == "level", , drop = FALSE]
      if (nrow(levs) > 0) {
        for (i in seq_len(nrow(levs))) {
          l_row <- as.data.frame(as.list(stats::setNames(rep("", length(stat_cols) + 2), c("Variable", stat_cols, "P"))), stringsAsFactors = FALSE)
          l_row$Variable <- paste0("   ", levs$label[i])
          for (sc in stat_cols) l_row[[sc]] <- levs[[sc]][i]
          l_row$P <- ""
          rows_list[[length(rows_list) + 1]] <- l_row
        }
      }
    }
  }

  out_df <- dplyr::bind_rows(rows_list)
  out_df[is.na(out_df)] <- ""
  list(out_df = out_df, section_row_index = section_row_index)
}

.tbc07_export_xlsx <- function(dat, class_col, vars_all, title_txt, out_xlsx, rules, section_levels,
                               force_continuous_vars = character(0), exposure_var = NULL) {
  dat$.class_raw <- as.character(dat[[class_col]])
  dat$.class_num <- suppressWarnings(as.integer(dat$.class_raw))
  dat$class_factor <- if (all(!is.na(dat$.class_num))) {
    factor(dat$.class_num, levels = sort(unique(dat$.class_num)), labels = paste0("Class", sort(unique(dat$.class_num))))
  } else {
    factor(dat$.class_raw, levels = sort(unique(dat$.class_raw)), labels = paste0("Class", sort(unique(dat$.class_raw))))
  }

  vars_all <- vars_all[sapply(dat[vars_all], function(x) any(!is.na(x)))]
  if (!length(vars_all)) return(NULL)

  dat <- .tbc07_auto_cast_for_summary(dat, vars_all)
  force_cont <- as.character(force_continuous_vars %||% character(0))
  if (length(force_cont)) {
    for (v in intersect(force_cont, vars_all)) {
      dat[[v]] <- suppressWarnings(as.numeric(dat[[v]]))
    }
  }
  cont_vars <- vars_all[sapply(dat[vars_all], .tbc07_is_continuous_var)]
  if (length(force_cont)) cont_vars <- unique(c(cont_vars, intersect(force_cont, vars_all)))
  cat_vars  <- setdiff(vars_all, cont_vars)

  # 防止 gtsummary::add_p 在高基数类别变量上触发 fisher.test 组合爆炸（MIMIC 卡死根因）：
  # 基线表本就不该展示 >15 水平的类别变量，直接剔除。
  too_many <- cat_vars[vapply(cat_vars, function(v) nlevels(factor(dat[[v]])) > 15L, logical(1L))]
  if (length(too_many)) {
    cli::cli_alert_warning("trajectory_baseline_by_class: 剔除高基数类别变量 {paste(too_many, collapse=', ')}（>15 水平，避免 fisher.test 卡死）")
    vars_all <- setdiff(vars_all, too_many)
    cat_vars <- setdiff(cat_vars, too_many)
    if (!length(vars_all)) return(NULL)
  }

  label_text <- rep("", length(vars_all)); names(label_text) <- vars_all
  label_text[cont_vars] <- paste0(sapply(cont_vars, .tbc07_pretty_var), ", median (IQR)")
  label_text[cat_vars]  <- paste0(sapply(cat_vars,  .tbc07_pretty_var), ", n (%)")
  label_list <- as.list(label_text)

  tb <- dat |>
    gtsummary::tbl_summary(
      by = class_factor,
      include = dplyr::all_of(vars_all),
      type = list(
        gtsummary::all_continuous()  ~ "continuous",
        gtsummary::all_dichotomous() ~ "categorical"
      ),
      statistic = list(
        gtsummary::all_continuous()  ~ "{median} ({p25}, {p75})",
        gtsummary::all_categorical() ~ "{n} ({p}%)"
      ),
      digits = list(gtsummary::all_continuous() ~ 2),
      missing = "no",
      label = label_list
    ) |>
    gtsummary::add_p(
      test = list(
        gtsummary::all_continuous()  ~ "wilcox.test",
        gtsummary::all_categorical() ~ "chisq.test"
      ),
      pvalue_fun = ~ gtsummary::style_pvalue(.x, digits = 3)
    ) |>
    gtsummary::modify_header(
      gtsummary::all_stat_cols() ~ "{level}\n(N={n})",
      label ~ "Variable", p.value ~ "P"
    )

  tb_body <- tibble::as_tibble(tb$table_body)
  built <- .tbc07_make_block_table(tb_body, vars_all, rules, section_levels, exposure_var = exposure_var)
  out_df <- built$out_df
  section_row_index <- built$section_row_index

  n_per_class <- table(dat$class_factor)
  class_headers <- paste0(names(n_per_class), "\n(N=", as.integer(n_per_class), ")")
  colnames(out_df) <- c("Variable", class_headers, "P")

  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Sheet1")
  headerStyle <- openxlsx::createStyle(fontSize = 12, fontName = "Times New Roman", halign = "center", textDecoration = "bold", border = "bottom")
  bodyStyle   <- openxlsx::createStyle(fontSize = 12, fontName = "Times New Roman", halign = "center", valign = "center")
  boldLeftStyle <- openxlsx::createStyle(fontSize = 12, fontName = "Times New Roman", halign = "left", valign = "center", textDecoration = "bold")

  openxlsx::writeData(wb, 1, x = title_txt, startRow = 1, startCol = 1, colNames = FALSE)
  openxlsx::mergeCells(wb, 1, rows = 1, cols = 1:ncol(out_df))
  openxlsx::addStyle(wb, 1, style = headerStyle, rows = 1, cols = 1:ncol(out_df), gridExpand = TRUE)

  openxlsx::writeData(wb, 1, x = out_df, startRow = 3, startCol = 1, colNames = TRUE, rowNames = FALSE)
  openxlsx::addStyle(wb, 1, style = headerStyle, rows = 3, cols = 1:ncol(out_df), gridExpand = TRUE)
  openxlsx::addStyle(wb, 1, style = bodyStyle, rows = 4:(nrow(out_df) + 3), cols = 1:ncol(out_df), gridExpand = TRUE)
  openxlsx::addStyle(wb, 1, style = boldLeftStyle, rows = section_row_index + 3, cols = 1, gridExpand = TRUE)
  openxlsx::setColWidths(wb, 1, cols = 1:ncol(out_df), widths = "auto")
  openxlsx::saveWorkbook(wb, out_xlsx, overwrite = TRUE)

  list(out_df = out_df, n_per_class = n_per_class)
}

.tbc07_run_one <- function(ctx, data, bl, Index, class_col, rules, section_levels, out_tab) {
  if (!class_col %in% names(data)) {
    cli::cli_alert_warning("trajectory_baseline_by_class: 缺少类别列 {class_col}，跳过 {Index %||% ''}")
    return(NULL)
  }

  time_var  <- bl$survival_time_var  %||% ctx$config$survival$time_var  %||% NULL
  event_var <- bl$survival_event_var %||% ctx$config$survival$event_var %||% NULL
  if (!is.null(event_var) && event_var %in% names(data) && !"Mortality_28d" %in% names(data)) {
    xv <- data[[event_var]]
    if (is.numeric(xv) || is.integer(xv)) data$Mortality_28d <- as.integer(xv)
  }

  vars_cfg <- as.character(bl$vars_to_include %||% character(0))
  vars_from <- tolower(as.character(bl$vars_from %||% "table1")[1L])
  if (!length(vars_cfg)) {
    t1_vars <- as.character(ctx$results$table1_var_order %||% character(0))
    vif_vars <- union(ctx$results$Model1Factors %||% character(0), ctx$results$Model2Factors %||% character(0))
    vars_cfg <- if (identical(vars_from, "table1") && length(t1_vars)) {
      unique(c(t1_vars, vif_vars, time_var, event_var))
    } else {
      unique(c(vif_vars, time_var, event_var))
    }
  }
  vars_cfg <- unique(c(vars_cfg, as.character(bl$extra_vars %||% character(0))))
  vars_all <- intersect(vars_cfg, setdiff(names(data), class_col))
  # 潜类别列本身不作基线对比变量（已是 by=class）
  if (exists("trajectory_class_column_names", mode = "function")) {
    vars_all <- setdiff(vars_all, trajectory_class_column_names(vars_all))
  } else {
    vars_all <- vars_all[!grepl("^trajectory_class", vars_all, ignore.case = TRUE)]
  }
  t1_order <- as.character(ctx$results$table1_var_order %||% character(0))
  t1_order <- t1_order[nzchar(t1_order)]
  t1_order <- t1_order[!grepl("^trajectory_class", t1_order, ignore.case = TRUE)]
  if (length(t1_order)) {
    vars_all <- c(intersect(t1_order, vars_all), setdiff(vars_all, t1_order))
  }
  # 当前暴露指标单独成节并固定在表末（与 Table 1 暴露末位一致）
  ix_force <- as.character(Index %||% character(0))[1L]
  if (nzchar(ix_force) && ix_force %in% names(data)) {
    vars_all <- c(setdiff(vars_all, ix_force), ix_force)
  }

  if (!length(vars_all)) {
    cli::cli_alert_warning("trajectory_baseline_by_class: {Index %||% ''} 无可用变量（vars_to_include 为空且 Model1/2Factors 也为空），跳过")
    return(NULL)
  }

  class_num <- suppressWarnings(as.integer(gsub("\\D+", "", as.character(data[[class_col]]))))
  if (length(unique(stats::na.omit(class_num))) < 2) {
    cli::cli_alert_warning("trajectory_baseline_by_class: {Index %||% ''} 类别数<2，跳过")
    return(NULL)
  }
  ng <- length(unique(stats::na.omit(class_num)))

  dat_sub <- data[!is.na(class_num), c(class_col, vars_all), drop = FALSE]

  # 与 Table 1 一致：剔除批次内其它复合暴露指标（若仍残留在数据中）
  if (exists("trajectory_batch_other_index_vars", mode = "function")) {
    other_ix <- trajectory_batch_other_index_vars(ctx$config, Index)
    drop_ix <- intersect(other_ix, vars_all)
    if (length(drop_ix)) {
      vars_all <- setdiff(vars_all, drop_ix)
      dat_sub <- dat_sub[, c(class_col, vars_all), drop = FALSE]
      cli::cli_alert_info("trajectory_baseline_by_class: 剔除其它暴露指标列 {paste(drop_ix, collapse=', ')}")
    }
  }
  # 暴露指标勿进 Laboratory 中间节：追加末节 Exposure index
  rules_use <- rules
  sec_levels_use <- section_levels
  if (nzchar(ix_force) && ix_force %in% vars_all) {
    rules_use[["Exposure index"]] <- paste0("^", tolower(ix_force), "$")
    if (!"Exposure index" %in% sec_levels_use) {
      sec_levels_use <- c(setdiff(sec_levels_use, "Exposure index"), "Exposure index")
    }
  }
  title_txt <- gsub("\\{ng\\}", as.character(ng),
                     gsub("\\{Index\\}", Index %||% "", bl$title_template %||%
                            "Table S5. Baseline characteristics of patients in {ng} latent classes of {Index}"))
  fn <- gsub("\\{Index\\}", Index %||% "overall", bl$filename_template %||% "Table_S5_Baseline_By_Class_{Index}.xlsx")
  out_xlsx <- file.path(out_tab, fn)

  res <- tryCatch(
    .tbc07_export_xlsx(dat_sub, class_col, vars_all, title_txt, out_xlsx, rules_use, sec_levels_use,
                      force_continuous_vars = as.character(bl$force_continuous_vars %||% character(0)),
                      exposure_var = if (nzchar(ix_force)) ix_force else NULL),
    error = function(e) { cli::cli_alert_danger("trajectory_baseline_by_class {Index %||% ''}: {e$message}"); NULL }
  )
  if (is.null(res)) return(NULL)

  cli::cli_alert_success("{Index %||% ''}: 落盘 {.file {basename(out_xlsx)}}（{ng} 类，{nrow(dat_sub)} 例）")
  list(out_df = res$out_df, n_per_class = res$n_per_class, path = out_xlsx, vars_used = vars_all)
}

block_trajectory_baseline_by_class <- function(ctx, ...) {
  suppressPackageStartupMessages({ library(dplyr); library(cli) })
  bl <- ctx$config$trajectory_baseline_by_class %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("trajectory_baseline_by_class: 无数据", call. = FALSE)

  out_tab <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)

  rules <- bl$section_rules %||% .tbc07_default_section_rules()
  section_levels <- as.character(bl$section_levels %||%
    c("Basic Characteristics", "Vital Signs", "Laboratory Tests",
      "Comorbidities", "28-day Outcomes", "Other"))

  index_vars <- bl$index_vars %||% NULL
  explicit_col <- bl$class_col %||% NULL

  targets <- if (!is.null(explicit_col)) {
    list(list(Index = NULL, col = explicit_col))
  } else if (!is.null(index_vars) && length(index_vars)) {
    lapply(index_vars, function(ix) {
      col <- paste0("trajectory_class_", ix)
      if (!col %in% names(data)) col <- "trajectory_class"
      list(Index = ix, col = col)
    })
  } else {
    list(list(Index = NULL, col = "trajectory_class"))
  }

  results_all <- list()
  for (t in targets) {
    key <- t$Index %||% "_"
    res <- .tbc07_run_one(ctx, data, bl, t$Index, t$col, rules, section_levels, out_tab)
    if (!is.null(res)) results_all[[key]] <- res
  }

  if (!length(results_all)) {
    if (.tbc07_should_pause(bl, "pause_on_no_output", TRUE)) {
      .tbc07_pause(
        ctx, "trajectory_baseline_by_class: 未产出任何基线对比表。",
        "请确认 trajectory_jlcm 已配置 assign_class_ng 回写 trajectory_class，且 vars_to_include / Model1Factors ∪ Model2Factors 非空。",
        NULL
      )
    }
    cli::cli_alert_warning("trajectory_baseline_by_class: 无有效输出")
    return(ctx)
  }

  ctx$results$trajectory_baseline_by_class <- results_all
  cli::cli_alert_success("trajectory_baseline_by_class 完成：{length(results_all)} 组结果")
  ctx
}

register_block(
  "trajectory_baseline_by_class", block_trajectory_baseline_by_class,
  "潜类别基线特征对比表（Table S5：分节 + gtsummary 组间比较，协变量自动取自 VIF final）"
)
