#!/usr/bin/env Rscript
# Redraw AKI WPR(class=4) Figure 2:
#  - 2x2 facets (not 1x4)
#  - subsample spaghetti for large classes
#  - shared ylim across DBs; do not clip mean curves
#  - rematch eICU classes to MIMIC by predicted trajectory shape
#    then order display Class1=lowest mort on MIMIC (AP primary style)
#
#   Rscript run/trajectory_prognosis/redraw_aki_wpr4_fig2.R

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(cli)
  library(lcmm)
  library(splines)
})

`%||%` <- function(a, b) if (!is.null(a)) a else b

.root <- {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    d <- dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
    if (basename(d) == "trajectory_prognosis")
      normalizePath(file.path(d, "..", ".."), winslash = "/")
    else normalizePath(getwd(), winslash = "/")
  } else normalizePath(getwd(), winslash = "/")
}
setwd(.root)

source(file.path(.root, "R/utils.R"), local = FALSE)
source(file.path(.root, "R/trajectory_survival_utils.R"), local = FALSE)
source(file.path(.root, "R/dual_db_combine_figures.R"), local = FALSE)
source(file.path(.root, "R/pub_figure_export.R"), local = FALSE)

index_root <- "/mnt/g/02block_result/44_AKI_SPESIS_CKD/Prognosis_Trajectory_38882552/tr/by_index/WPR(class=4)"
fig_root <- file.path(index_root, "Figures")
tab_sum <- file.path(index_root, "Tables", "Summary")
dir.create(tab_sum, showWarnings = FALSE, recursive = TRUE)

.load_m4 <- function(db) {
  e <- new.env(parent = emptyenv())
  load(file.path(index_root, db, "step14_trajectory_jlcm/Data/D01_jlcm_WPR_models.RData"), envir = e)
  list(
    m = trajectory_unwrap_jointlcmm(e$models_list_with_cov$m4),
    md = as.data.frame(e$model_data_final)
  )
}
.load_long <- function(db) {
  e <- new.env(parent = emptyenv())
  load(file.path(index_root, db, "step14_trajectory_jlcm/Data/D01_long_WPR_D_1.RData"), envir = e)
  e$long
}

.pred_curves_by_raw <- function(m, md, cycle = 28L, n = 80L) {
  # returns matrix time x raw_class (1..ng) of predicted mean WPR
  cov_cols <- trajectory_jlcm_cov_cols(list(), m)
  if (!"time_day" %in% names(md) && "Time" %in% names(md)) md$time_day <- md$Time
  grid <- trajectory_jlcm_cov_grid(md, cov_cols, time_var = "time_day", cycle = cycle, n = n)
  pred <- tryCatch(
    lcmm::predictY(m, newdata = grid, var.time = "time_day", draws = FALSE),
    error = function(e) NULL
  )
  if (is.null(pred)) return(NULL)
  as.matrix(pred$pred) # columns Ypred_class1..
}

.patient_stats <- function(db, m) {
  x <- .load_m4(db)
  md <- x$md
  pp <- as.data.frame(m$pprob)
  id <- unique(md[, c("subject_id", "subject_id_num", "survival_28d", "survival_time_28d")])
  id$class_raw <- pp$class[match(id$subject_id_num, pp$subject_id_num)]
  long <- .load_long(db)
  pt_wpr <- aggregate(Value ~ subject_id, data = long, FUN = function(z) mean(z, na.rm = TRUE))
  names(pt_wpr)[2] <- "mean_wpr"
  id <- merge(id, pt_wpr, by = "subject_id", all.x = TRUE)
  id
}

# —— Build shape-based dual-db class map ——
xm <- .load_m4("mimic"); xe <- .load_m4("eicu")
pm <- .pred_curves_by_raw(xm$m, xm$md)
pe <- .pred_curves_by_raw(xe$m, xe$md)
stopifnot(!is.null(pm), !is.null(pe), ncol(pm) == 4L, ncol(pe) == 4L)

# distance: 1 - corr of curves (fallback MSE)
cost <- matrix(0, 4, 4)
for (i in 1:4) for (j in 1:4) {
  a <- as.numeric(pm[, i]); b <- as.numeric(pe[, j])
  ok <- is.finite(a) & is.finite(b)
  if (sum(ok) < 5L) {
    cost[i, j] <- 1e6
  } else {
    r <- suppressWarnings(stats::cor(a[ok], b[ok]))
    if (!is.finite(r)) {
      cost[i, j] <- mean((a[ok] - b[ok])^2)
    } else {
      cost[i, j] <- 1 - r
    }
  }
}
# rows = MIMIC raw class, cols = eICU raw class → assign each MIMIC raw a unique eICU raw
assign_e_for_m <- as.integer(clue::solve_LSAP(cost)) # length 4, position i -> eICU raw
cli_alert_info("Shape match MIMIC raw → eICU raw: {paste(1:4, assign_e_for_m, sep='→', collapse=', ')}")
cli_alert_info("corr distances:\n{paste(capture.output(print(round(cost,3))), collapse='\n')}")

# MIMIC display order: lowest mortality first (AP primary style)
ps_m <- .patient_stats("mimic", xm$m)
mort_m <- tapply(ps_m$survival_28d == 1L, ps_m$class_raw, mean)
# display: Class1 = lowest mort MIMIC raw
ord_m <- as.integer(names(sort(mort_m))) # raw classes low→high mort
# map MIMIC raw -> display
map_m <- stats::setNames(seq_along(ord_m), as.character(ord_m))
# eICU: matched raw to same display as its MIMIC partner
map_e_old_to_new <- integer(4)
names(map_e_old_to_new) <- as.character(1:4)
for (mi in 1:4) {
  ei <- assign_e_for_m[mi]
  disp <- as.integer(map_m[[as.character(mi)]])
  map_e_old_to_new[as.character(ei)] <- disp
}
map_e <- stats::setNames(as.integer(map_e_old_to_new), names(map_e_old_to_new))

align <- rbind(
  data.frame(db = "mimic", old_class = as.integer(names(map_m)), new_class = as.integer(unname(map_m)),
             note = "mortality-ordered on MIMIC; shape-matched to eICU", stringsAsFactors = FALSE),
  data.frame(db = "eicu", old_class = as.integer(names(map_e)), new_class = as.integer(unname(map_e)),
             note = "shape-matched to MIMIC display", stringsAsFactors = FALSE)
)
utils::write.csv(align, file.path(tab_sum, "class_align_WPR.csv"), row.names = FALSE)
cli_alert_success("Updated class_align_WPR.csv (shape+mort)")

# side-by-side check
ps_e <- .patient_stats("eicu", xe$m)
for (d in 1:4) {
  mr <- as.integer(names(map_m)[map_m == d])
  er <- as.integer(names(map_e)[map_e == d])
  cat(sprintf(
    "Display %d | MIMIC raw%d n=%d mort=%.1f%% meanWPR=%.3f | eICU raw%d n=%d mort=%.1f%% meanWPR=%.3f\n",
    d, mr,
    sum(ps_m$class_raw == mr), 100 * mean(ps_m$survival_28d[ps_m$class_raw == mr] == 1),
    mean(ps_m$mean_wpr[ps_m$class_raw == mr], na.rm = TRUE),
    er,
    sum(ps_e$class_raw == er), 100 * mean(ps_e$survival_28d[ps_e$class_raw == er] == 1),
    mean(ps_e$mean_wpr[ps_e$class_raw == er], na.rm = TRUE)
  ))
}

# —— Custom plot (2x2, thinned spaghetti, no clip) ——
.make_fig2 <- function(db, db_lab, m, cmap, ylim_shared) {
  long <- .load_long(db)
  md <- .load_m4(db)$md
  pp <- as.data.frame(m$pprob)
  id_map <- unique(md[, c("subject_id", "subject_id_num", "survival_28d", "survival_time_28d")])
  id_map$class_raw <- pp$class[match(id_map$subject_id_num, pp$subject_id_num)]
  id_map$class <- trajectory_apply_class_swap(id_map$class_raw, cmap)
  long$Class <- id_map$class_raw[match(as.character(long$subject_id), as.character(id_map$subject_id))]

  class_colors <- c(
    "Class 1" = "#D55E00", "Class 2" = "#E69F00",
    "Class 3" = "#56B4E9", "Class 4" = "#009E73"
  )
  class_levels <- paste0("Class ", 1:4)

  cov_cols <- trajectory_jlcm_cov_cols(list(), m)
  if (!"time_day" %in% names(md) && "Time" %in% names(md)) md$time_day <- md$Time
  # use long for cov means if needed
  cov_src <- long
  if (!"time_day" %in% names(cov_src) && "Time" %in% names(cov_src)) cov_src$time_day <- cov_src$Time
  grid <- trajectory_jlcm_cov_grid(cov_src, cov_cols, time_var = "time_day", cycle = 28L, n = 100L)
  pred <- lcmm::predictY(m, newdata = grid, var.time = "time_day", draws = FALSE)
  pred_tidy <- as.data.frame(pred$pred) |>
    mutate(time = grid$time_day) |>
    tidyr::pivot_longer(cols = starts_with("Ypred"), names_to = "class",
                        names_prefix = "Ypred_class", values_to = "Value") |>
    mutate(
      class_num = trajectory_apply_class_swap(class, cmap),
      class_label = factor(paste0("Class ", class_num), levels = class_levels)
    )

  # outcome labels
  outcome <- id_map |>
    group_by(class_num = class) |>
    summarise(
      n = n(),
      death_rate = 100 * mean(survival_28d == 1, na.rm = TRUE),
      .groups = "drop"
    )
  # KM median
  outcome$median_text <- NA_character_
  for (i in seq_len(nrow(outcome))) {
    cl <- outcome$class_num[i]
    sub <- id_map[id_map$class == cl, ]
    ev <- as.integer(sub$survival_28d == 1)
    tm <- pmin(as.numeric(sub$survival_time_28d), 28)
    tm <- ifelse(ev == 0, 28, tm)
    fit <- tryCatch(survival::survfit(survival::Surv(tm, ev) ~ 1), error = function(e) NULL)
    med <- if (!is.null(fit)) as.numeric(summary(fit)$table["median"]) else NA_real_
    outcome$median_text[i] <- if (is.finite(med)) sprintf("%.1f days", med) else "NR (>28 d)"
  }
  outcome <- outcome |>
    mutate(
      class_label = factor(paste0("Class ", class_num), levels = class_levels),
      label_text = sprintf("N = %d\nDeath: %.1f%%\nMedian Survival: %s", n, death_rate, median_text),
      x_pos = 27.5,
      y_pos = ylim_shared[2] - 0.02 * diff(ylim_shared)
    )

  # background: subsample per class (max 120 ids) to avoid grey blob
  bg <- long |>
    mutate(
      class_num = trajectory_apply_class_swap(Class, cmap),
      class_label = factor(paste0("Class ", class_num), levels = class_levels)
    ) |>
    filter(!is.na(class_num), is.finite(Value), is.finite(Time))
  set.seed(42)
  keep_ids <- bg |>
    distinct(subject_id, class_num) |>
    group_by(class_num) |>
    group_modify(~ {
      if (nrow(.x) <= 120L) .x else dplyr::slice_sample(.x, n = 120L)
    }) |>
    ungroup()
  bg <- bg |> semi_join(keep_ids, by = c("subject_id", "class_num"))

  p <- ggplot() +
    geom_line(
      data = bg,
      aes(x = Time, y = Value, group = subject_id),
      color = "grey70", alpha = 0.12, linewidth = 0.2
    ) +
    geom_line(
      data = pred_tidy,
      aes(x = time, y = Value, color = class_label),
      linewidth = 1.35
    ) +
    geom_text(
      data = outcome,
      aes(x = x_pos, y = y_pos, label = label_text),
      hjust = 1, vjust = 1, size = 3.1, lineheight = 0.95, color = "black"
    ) +
    facet_wrap(~ class_label, ncol = 2) +
    scale_color_manual(values = class_colors, guide = "none") +
    scale_x_continuous(breaks = seq(0, 28, by = 7)) +
    scale_y_continuous(breaks = pretty(ylim_shared, n = 5)) +
    labs(
      title = "WPR Trajectories by Latent Class (ng = 4)",
      x = "Day in ICU", y = "WPR"
    ) +
    coord_cartesian(xlim = c(0, 28), ylim = ylim_shared, expand = FALSE, clip = "on") +
    theme_classic(base_size = 11) +
    theme(
      legend.position = "none",
      plot.title = element_text(hjust = 0.5, size = 12, face = "bold"),
      axis.title = element_text(size = 11),
      axis.text = element_text(size = 9, color = "black"),
      strip.text = element_text(size = 10, face = "bold", margin = margin(5, 4, 5, 4)),
      strip.background = element_rect(fill = "grey96", color = "grey80", linewidth = 0.25),
      panel.border = element_rect(fill = NA, color = "grey45", linewidth = 0.35),
      panel.spacing = grid::unit(0.7, "lines"),
      plot.margin = margin(6, 8, 4, 8)
    )
  p
}

# shared ylim from both DBs' predictions (no clipping of means)
.all_pred <- c()
for (db in c("mimic", "eicu")) {
  x <- .load_m4(db)
  pr <- .pred_curves_by_raw(x$m, x$md, n = 100L)
  .all_pred <- c(.all_pred, as.numeric(pr))
}
hi <- as.numeric(stats::quantile(.all_pred[is.finite(.all_pred)], 0.995, na.rm = TRUE))
ylim_shared <- c(0, max(0.35, hi * 1.08))
cli_alert_info("shared ylim = [{ylim_shared[1]}, {round(ylim_shared[2],3)}]")

p_m <- .make_fig2("mimic", "MIMIC", xm$m, map_m, ylim_shared)
p_e <- .make_fig2("eicu", "eICU", xe$m, map_e, ylim_shared)

out_m <- file.path(index_root, "mimic", "Figures", "Figure 2-MIMIC. Trajectory of WPR latent classes.pdf")
out_e <- file.path(index_root, "eicu", "Figures", "Figure 2-eICU. Trajectory of WPR latent classes.pdf")
ggsave(out_m, p_m, width = 9.2, height = 7.2, device = grDevices::cairo_pdf)
ggsave(out_e, p_e, width = 9.2, height = 7.2, device = grDevices::cairo_pdf)
# also update _raw
file.copy(out_m, file.path(index_root, "mimic", "Figures", "_raw", "Figure Trajectory WPR latent classes.pdf"), overwrite = TRUE)
file.copy(out_e, file.path(index_root, "eicu", "Figures", "_raw", "Figure Trajectory WPR latent classes.pdf"), overwrite = TRUE)

# dual stack compose
out_dual <- file.path(fig_root, "Figure 2. Trajectory of WPR latent classes.pdf")
.dual_db_compose_pair_pdf(
  out_m, out_e, out_dual, layout = "stack",
  label_a = "A. MIMIC", label_b = "B. eICU",
  dpi = 220L, label_cex = 1.2
)

# refresh four-dir for Fig2 only: ensure_formats whole Figures
tryCatch(
  pub_figure_ensure_formats(fig_root, config = list()),
  error = function(e) cli_alert_warning("{e$message}")
)

# update image md
writeLines(c(
  "# Figure 2. Trajectory of WPR latent classes",
  "",
  "## 图面说明",
  "4 类 WPR 轨迹均值曲线双库拼图（A. MIMIC，B. eICU），每库 2×2 面板。",
  "灰线为各类随机抽样个体轨迹（每类最多 120 人），粗线为 JLCM 预测均值。",
  "双库类别按预测轨迹形态匹配后，再按 MIMIC 28 天死亡从低到高编号：",
  "Class 1 = 最低死亡（多数），Class 4 = 最高死亡。",
  "两库共用同一 Y 轴范围；预测均值不做裁切。",
  "",
  "## 分析上下文",
  "- 暴露: WPR 4-class latent trajectory (primary)",
  "- 结局: 28-day in-hospital death",
  "- Grouping: 4-class; shape-aligned across MIMIC/eICU",
  "- 数据库: MIMIC, eICU",
  "- 是否拼图: 是"
), file.path(fig_root, "image_information", "Figure 2. Trajectory of WPR latent classes.md"), useBytes = TRUE)

cli_alert_success("Figure 2 redrawn: {out_dual}")
