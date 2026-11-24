###############################################################################
#  cftraj_subgroup_viz — 脆弱亚组 CATE 汇总（年轻、贫血、BMI）
#  文献: Ma 2026 Alzheimers Dement
###############################################################################

block_cftraj_subgroup_viz <- function(ctx, ...) {
  bl <- ctx$config$cftraj %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("cftraj_subgroup_viz: 无数据", call. = FALSE)

  id_col <- bl$id_column %||% ctx$config$data$id_column %||% "ID"
  cate_col <- bl$cate_col %||% "CATE"
  treat_col <- bl$treatment_col %||% bl$circs_binary_col %||% "CircS_high"

  if (!cate_col %in% names(data)) {
    out_prev <- (ctx$results$cftraj_causal_forest %||% list())$output_dir
    subj_path <- NULL
    if (!is.null(out_prev)) {
      for (cand in c(
        file.path(out_prev, "global", "Table_CfTraj_CATE_Subject.csv"),
        file.path(out_prev, "episodic", "Table_CfTraj_CATE_Subject.csv"),
        file.path(out_prev, "Table_CfTraj_CATE_Subject.csv")
      )) {
        if (file.exists(cand)) { subj_path <- cand; break }
      }
    }
    if (!is.null(subj_path) && file.exists(subj_path) && id_col %in% names(data)) {
      csub <- utils::read.csv(subj_path, stringsAsFactors = FALSE)
      if ("CATE" %in% names(csub) && id_col %in% names(csub)) {
        data <- merge(data, csub[, c(id_col, "CATE"), drop = FALSE], by = id_col, all.x = TRUE)
        names(data)[names(data) == "CATE"] <- cate_col
      }
    }
  }
  if (!cate_col %in% names(data)) stop("cftraj_subgroup_viz: 请先运行 cftraj_causal_forest", call. = FALSE)

  d <- data
  age_col <- bl$age_col %||% "Age"
  if (age_col %in% names(d)) {
    age_cut <- bl$younger_age_cut %||% 65L
    d$Age_young <- ifelse(suppressWarnings(as.numeric(d[[age_col]])) < age_cut, "Younger", "Older")
  }
  anemia_col <- bl$anemia_col %||% "Anemia"
  if (anemia_col %in% names(d)) {
    d$Anemia <- ifelse(suppressWarnings(as.numeric(d[[anemia_col]])) >= 1L, "Anemia", "No_anemia")
  } else if ("Hemoglobin" %in% names(d)) {
    d$Anemia <- ifelse(suppressWarnings(as.numeric(d$Hemoglobin)) < (bl$anemia_hb_cut %||% 12), "Anemia", "No_anemia")
  }
  bmi_col <- bl$bmi_col %||% "BMI"
  if (bmi_col %in% names(d)) {
    bmi_v <- suppressWarnings(as.numeric(d[[bmi_col]]))
    d$BMI_group <- ifelse(bmi_v < 18.5, "Underweight",
      ifelse(bmi_v < 24, "Normal",
        ifelse(bmi_v < 28, "Overweight", "Obese")))
  }

  subgroup_vars <- intersect(
    bl$subgroup_vars %||% c("Age_young", "Anemia", "BMI_group"),
    names(d)
  )
  if (!length(subgroup_vars)) stop("cftraj_subgroup_viz: 无可用亚组变量", call. = FALSE)

  rows <- list()
  for (sg in subgroup_vars) {
    for (lv in unique(d[[sg]])) {
      if (is.na(lv)) next
      idx <- !is.na(d[[cate_col]]) & d[[sg]] == lv
      if (sum(idx) < 5L) next
      sub <- d[idx, , drop = FALSE]
      rows[[length(rows) + 1L]] <- data.frame(
        subgroup_var = sg, subgroup_level = as.character(lv),
        n = sum(idx),
        mean_CATE = mean(sub[[cate_col]], na.rm = TRUE),
        median_CATE = stats::median(sub[[cate_col]], na.rm = TRUE),
        sd_CATE = stats::sd(sub[[cate_col]], na.rm = TRUE),
        pct_CircS_high = if (treat_col %in% names(sub)) mean(sub[[treat_col]], na.rm = TRUE) else NA_real_,
        stringsAsFactors = FALSE
      )
    }
  }

  tab <- if (length(rows)) do.call(rbind, rows) else data.frame(note = "no subgroups")
  tab <- tab[order(tab$subgroup_var, -abs(tab$mean_CATE)), , drop = FALSE]

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "CfTraj")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, file.path(out_dir, "Table_CfTraj_Vulnerable_Subgroups.csv"), row.names = FALSE)

  if (requireNamespace("ggplot2", quietly = TRUE) && nrow(tab) > 0L && "mean_CATE" %in% names(tab)) {
    fig_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Figures", "CfTraj")
    dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
    p <- ggplot2::ggplot(tab, ggplot2::aes(x = interaction(subgroup_var, subgroup_level), y = mean_CATE)) +
      ggplot2::geom_col(fill = "steelblue") +
      ggplot2::coord_flip() +
      ggplot2::labs(title = "CATE by vulnerable subgroups", x = NULL, y = "Mean CATE") +
      ggplot2::theme_bw()
    tryCatch(
      ggplot2::ggsave(file.path(fig_dir, "Fig_CfTraj_Subgroup_CATE.png"), p, width = 8, height = 5, dpi = 150),
      error = function(e) cli::cli_alert_warning("亚组图保存失败: {e$message}")
    )
  }

  ctx$results$cftraj_subgroup_viz <- tab
  cli::cli_alert_success("脆弱亚组 CATE 表完成")
  ctx
}

register_block("cftraj_subgroup_viz", block_cftraj_subgroup_viz, "脆弱亚组 CATE 汇总表")
