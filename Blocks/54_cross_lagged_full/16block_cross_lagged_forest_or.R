###############################################################################
#  cross_lagged_forest_or — 暴露中位数二分 + 亚组 OR 森林图
#
#  require_data = ctx$data$imputed %||% ctx$data$cleaned
#  来源: C01_ForestPlot - nolevel-OR.R
#  修正: 原脚本 xlim=c(0,1)+ref_line=1 对 OR 不合理；改为自动范围且 ref=1
#        删除重复的 Events/OR 列构造
#  register_block: "cross_lagged_forest_or"
###############################################################################

block_cross_lagged_forest_or <- function(ctx, ...) {
  if (!requireNamespace("jstable", quietly = TRUE))
    stop("cross_lagged_forest_or: 需要 jstable", call. = FALSE)
  if (!requireNamespace("forestploter", quietly = TRUE))
    stop("cross_lagged_forest_or: 需要 forestploter", call. = FALSE)

  cfg <- ctx$config
  bl <- cfg$cross_lagged_forest_or %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data))
    stop("cross_lagged_forest_or: 无数据", call. = FALSE)

  index <- bl$index_var %||% cfg$incidence$index_var %||% "FI"
  outcome <- bl$outcome %||% cfg$data$outcome_column %||% "Disease_Group"
  event <- bl$outcome_event_level %||% cfg$project$analysis_group %||% "Hip_Fracture"
  if (!index %in% names(data)) stop("cross_lagged_forest_or: 缺暴露列 ", index, call. = FALSE)
  if (!outcome %in% names(data)) stop("cross_lagged_forest_or: 缺结局列 ", outcome, call. = FALSE)

  data2 <- data
  if (is.numeric(data2[[outcome]]) || is.integer(data2[[outcome]])) {
    data2$Disease <- as.integer(data2[[outcome]] == 1L)
  } else {
    data2$Disease <- as.integer(as.character(data2[[outcome]]) == as.character(event))
  }
  if ("Age" %in% names(data2) && !"Age_Group" %in% names(data2)) {
    data2$Age_Group <- factor(ifelse(data2$Age < 75, "< 75", "≥ 75"), levels = c("< 75", "≥ 75"))
  }

  cut_median <- as.numeric(stats::quantile(data2[[index]], probs = 0.5, na.rm = TRUE))
  data2$Group <- factor(ifelse(data2[[index]] < cut_median, "Q1", "Q2"), levels = c("Q1", "Q2"))

  continuous_vars <- names(data2)[vapply(data2, is.numeric, logical(1))]
  categorical_vars <- setdiff(names(data2), continuous_vars)
  var_subgroups <- setdiff(categorical_vars, c("Group", "ID", "Disease", outcome, "Cohort"))
  var_subgroups <- var_subgroups[var_subgroups %in% names(data2)]
  if (!length(var_subgroups)) {
    cli::cli_alert_warning("cross_lagged_forest_or: 无亚组分类变量，仅总体")
    var_subgroups <- character(0)
  }
  if (length(var_subgroups))
    data2[var_subgroups] <- lapply(data2[var_subgroups], function(z) factor(trimws(as.character(z))))

  res <- jstable::TableSubgroupMultiGLM(
    formula = Disease ~ Group,
    var_subgroups = if (length(var_subgroups)) var_subgroups else NULL,
    var_cov = NULL,
    family = "binomial",
    data = data2
  )
  res[is.na(res)] <- ""
  rt <- as.data.frame(print(res))
  rt[is.na(rt)] <- ""

  get_first_existing <- function(df, candidates) {
    hit <- intersect(candidates, colnames(df))
    if (!length(hit)) return(NA_character_)
    hit[[1]]
  }

  if ("Variable" %in% names(rt)) rt$Subgroup <- rt[["Variable"]] else rt$Subgroup <- rt[[1]]
  if (all(c("Count", "Percent") %in% names(rt))) {
    rt$Events <- ""
    idxc <- which(rt$Count != "")
    rt$Events[idxc] <- paste0(rt$Count[idxc], "(", rt$Percent[idxc], "%)")
  } else if ("Count" %in% names(rt)) {
    rt$Events <- rt$Count
  } else rt$Events <- ""

  if (!"Levels" %in% names(rt)) rt$Levels <- ""
  rt$P.value <- if ("P value" %in% names(rt)) rt[["P value"]] else if ("P.value" %in% names(rt)) rt[["P.value"]] else ""
  rt$P.for.interaction <- if ("P for interaction" %in% names(rt)) rt[["P for interaction"]] else ""

  or_col <- get_first_existing(rt, c("OR", "HR", "RR", "Estimate"))
  low_col <- get_first_existing(rt, c("Lower", "LCL", "CI_low", "Lower.95"))
  up_col <- get_first_existing(rt, c("Upper", "UCL", "CI_up", "Upper.95"))
  if (!"OR" %in% names(rt)) rt$OR <- ""
  if (!"Lower" %in% names(rt)) rt$Lower <- ""
  if (!"Upper" %in% names(rt)) rt$Upper <- ""
  if (!is.na(or_col)) rt$OR <- rt[[or_col]]
  if (!is.na(low_col)) rt$Lower <- rt[[low_col]]
  if (!is.na(up_col)) rt$Upper <- rt[[up_col]]

  rt$`OR.(95%CI)` <- ""
  idx <- which(rt$OR != "" & rt$OR != "Reference")
  if (length(idx))
    rt$`OR.(95%CI)`[idx] <- paste0(rt$OR[idx], "(", rt$Lower[idx], "-", rt$Upper[idx], ")")

  need_cols <- c("Subgroup", "Events", "OR", "Lower", "Upper", "Levels", "OR.(95%CI)", "P.value", "P.for.interaction")
  dt <- rt[, need_cols, drop = FALSE]
  dt$Subgroup1 <- paste(rep(" ", max(1L, max(nchar(dt$Subgroup)))), collapse = " ")
  dt$Subgroup <- ifelse(rt$OR == "" | is.na(rt$OR), dt$Subgroup, paste0("   ", dt$Subgroup))
  dt$OR <- suppressWarnings(as.numeric(gsub("[^0-9.-]", "", as.character(dt$OR))))
  dt$Lower <- suppressWarnings(as.numeric(gsub("[^0-9.-]", "", as.character(dt$Lower))))
  dt$Upper <- suppressWarnings(as.numeric(gsub("[^0-9.-]", "", as.character(dt$Upper))))

  # FIX: OR 图不应强制 xlim 到 [0,1]
  finite_or <- dt$OR[is.finite(dt$OR) & dt$OR > 0]
  finite_hi <- dt$Upper[is.finite(dt$Upper) & dt$Upper > 0]
  xmax <- if (length(finite_hi)) max(finite_hi, na.rm = TRUE) else 3
  xmax <- max(2, min(10, xmax * 1.1))
  xlim_use <- c(0, xmax)
  ticks_at <- pretty(xlim_use, n = 5)

  tm <- forestploter::forest_theme(
    base_size = 12,
    refline_gp = grid::gpar(lty = "dashed", col = "black"),
    ci_pch = 15, ci_col = "black", ci_lwd = 1.5
  )
  p <- forestploter::forest(
    dt[, c("Subgroup", "Events", "Subgroup1", "Levels", "OR.(95%CI)", "P.value", "P.for.interaction")],
    est = list(dt$OR),
    lower = list(dt$Lower),
    upper = list(dt$Upper),
    ci_column = 3,
    sizes = 0.6,
    ref_line = 1,
    arrow_lab = c(paste("Decreased risk for", event), paste("Increased risk for", event)),
    xlim = xlim_use,
    ticks_at = ticks_at,
    theme = tm
  )
  bold_rows <- unique(c(which(is.na(dt$OR)), 1L))
  p <- forestploter::edit_plot(p, row = bold_rows, gp = grid::gpar(fontface = "bold"))

  fig_dir <- file.path(cfg$project$output_dir %||% "Output", "Figures")
  tab_dir <- file.path(cfg$project$output_dir %||% "Output", "Tables")
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
  db <- cfg$project$database %||% "cohort"
  pdf_path <- file.path(fig_dir, paste0("Fig_Subgroup_", db, "_", index, "_Binary.pdf"))
  grDevices::pdf(pdf_path, height = 14, width = 10)
  print(p)
  grDevices::dev.off()
  utils::write.csv(dt, file.path(tab_dir, paste0("Subgroup_OR_", db, "_", index, ".csv")), row.names = FALSE)

  ctx$results$cross_lagged_forest_or <- list(
    cut_median = cut_median, path = pdf_path, table = dt
  )
  cli::cli_alert_success("森林图已写: {pdf_path} (median cut={round(cut_median, 4)})")
  ctx
}

register_block("cross_lagged_forest_or", block_cross_lagged_forest_or, "亚组 OR 森林图")
