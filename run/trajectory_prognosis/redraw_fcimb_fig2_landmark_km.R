#!/usr/bin/env Rscript
# 重画 Figure 2：对齐 fcimb-16-1871653 landmark KM
#   Rscript run/trajectory_prognosis/redraw_fcimb_fig2_landmark_km.R --index GPR

suppressPackageStartupMessages({
  library(survival)
  library(dplyr)
  library(ggplot2)
})

.args <- commandArgs(trailingOnly = TRUE)
.get <- function(flag, default = NULL) {
  i <- match(flag, .args)
  if (is.na(i) || i >= length(.args)) return(default)
  .args[[i + 1L]]
}

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
source(file.path(.root, "R/utils.R"))

`%||%` <- function(a, b) if (is.null(a)) b else a

proj <- .get("--proj", "G:/02block_result/55_COPD/Prognosis_Trajectory_v2_42558177")
ix <- .get("--index", "GPR")
ix_root <- file.path(proj, paste0("by_index/\u3010success\u3011", ix))
ck_base <- file.path(proj, "checkpoints/by_index", ix)
max_fu <- 28L
landmark <- 5L
.font <- tryCatch(resolve_plot_font_family(), error = function(e) "sans")

cols <- c(
  "Class 1" = "#E69F00",
  "Class 2" = "#0072B2",
  "Class 3" = "#009E73",
  "Class 4" = "#D55E00",
  "Class 5" = "#CC79A7",
  "Class 6" = "#56B4E9"
)

.to_event01 <- function(x) {
  xs <- trimws(as.character(x))
  dplyr::case_when(
    xs %in% c("1", "Non-survivor", "Dead", "dead", "DEAD", "Yes", "TRUE", "T") ~ 1L,
    xs %in% c("0", "Survivor", "Alive", "alive", "ALIVE", "No", "FALSE", "F") ~ 0L,
    TRUE ~ suppressWarnings(as.integer(xs))
  )
}

.resolve_landmark <- function() {
  pc <- file.path(ck_base, "mimic/trajectory_piecewise_cox.rds")
  if (!file.exists(pc)) return(5L)
  cuts <- tryCatch(
    readRDS(pc)$ctx$results$trajectory_piecewise_cox$cuts[[ix]],
    error = function(e) NULL
  )
  ng <- suppressWarnings(as.integer(cuts)[1L])
  if (is.finite(ng) && ng >= 2L) ng else 5L
}

.load_km_df <- function(db) {
  p <- file.path(ck_base, db, "trajectory_km_class.rds")
  if (!file.exists(p)) p <- file.path(ck_base, db, "trajectory_jlcm.rds")
  if (!file.exists(p) && identical(db, "eicu"))
    p <- file.path(ck_base, db, "trajectory_lcmm_external_validate.rds")
  if (!file.exists(p)) stop("缺少 checkpoint: ", db)
  x <- readRDS(p)
  ctx <- x$ctx %||% x
  d <- ctx$data$imputed %||% ctx$data$cleaned
  if (!is.data.frame(d)) stop(db, ": 无 imputed/cleaned")
  cls <- if (paste0("trajectory_class_", ix) %in% names(d)) d[[paste0("trajectory_class_", ix)]] else d$trajectory_class
  # 外验优先 assignment CSV
  asg <- file.path(
    ix_root, "eicu/step14_trajectory_lcmm_external_validate/Tables/LCMM",
    paste0("Table_LCMM_Assignment_External_", ix, ".csv")
  )
  if (identical(db, "eicu") && file.exists(asg) && "subject_id" %in% names(d)) {
    a <- utils::read.csv(asg, stringsAsFactors = FALSE)
    if (all(c("subject_id", "trajectory_class") %in% names(a))) {
      d$subject_id <- as.character(d$subject_id)
      a$subject_id <- as.character(a$subject_id)
      d <- dplyr::left_join(
        d %>% select(-any_of(c("trajectory_class", paste0("trajectory_class_", ix)))),
        a %>% select(subject_id, trajectory_class),
        by = "subject_id"
      )
      cls <- d$trajectory_class
    }
  }
  raw_t <- suppressWarnings(as.numeric(as.character(d$survival_time_28d)))
  ev <- .to_event01(d$survival_28d)
  class_num <- suppressWarnings(as.integer(gsub("\\D+", "", as.character(cls))))
  out <- data.frame(
    class_num = class_num,
    time = ifelse(ev == 0L, max_fu, pmin(raw_t, max_fu)),
    event = ev,
    stringsAsFactors = FALSE
  )
  out <- out[is.finite(out$class_num) & is.finite(out$time) & out$time > 0 & !is.na(out$event), , drop = FALSE]
  out$class <- factor(
    out$class_num,
    levels = sort(unique(out$class_num)),
    labels = paste("Class", sort(unique(out$class_num)))
  )
  out
}

.surv_tidy <- function(fit) {
  s <- summary(fit, censored = TRUE)
  data.frame(
    time = s$time,
    surv = s$surv,
    strata = as.character(s$strata),
    stringsAsFactors = FALSE
  ) %>%
    mutate(
      class = sub("^class=", "", strata),
      class = sub("^Class\\.", "Class ", class),
      class = gsub("\\.", " ", class)
    )
}

# 补阶梯起点 (t=t0, S=1)
.add_start <- function(df, t0) {
  bind_rows(
    df %>%
      distinct(class) %>%
      mutate(time = t0, surv = 1),
    df
  ) %>%
    arrange(class, time)
}

.fmt_p <- function(p) {
  if (!is.finite(p)) return("P = NA")
  if (p < 0.001) "P < 0.001" else sprintf("P = %.3f", p)
}

.logrank_p <- function(df, time_col, event_col) {
  fml <- stats::as.formula(paste0("Surv(", time_col, ", ", event_col, ") ~ class"))
  sd <- tryCatch(survdiff(fml, data = df), error = function(e) NULL)
  if (is.null(sd)) return(NA_real_)
  stats::pchisq(sd$chisq, df = length(sd$n) - 1L, lower.tail = FALSE)
}

.risk_at <- function(df, times) {
  # 各时点仍在险：time > t 或 (time == t & event == 0) → time >= t 且非「死亡恰在 t 之前」
  # 标准：at risk at t = time >= t
  out <- lapply(times, function(t) {
    df %>%
      filter(time >= t) %>%
      count(class, name = "n") %>%
      mutate(t = t)
  })
  bind_rows(out)
}

.panel_km <- function(df, tag) {
  L <- as.numeric(landmark)
  # 左段：0–L
  d1 <- df %>%
    mutate(
      t1 = pmin(time, L),
      e1 = as.integer(event == 1L & time <= L)
    )
  p_left <- .logrank_p(d1, "t1", "e1")
  fit1 <- survfit(Surv(t1, e1) ~ class, data = d1)
  cur1 <- .add_start(.surv_tidy(fit1), 0) %>%
    filter(time <= L + 1e-8) %>%
    mutate(seg = "early")

  # 右段：landmark 条件生存（仍在险 = time > L）
  d2 <- df %>% filter(time > L) %>% mutate(start = L)
  p_right <- .logrank_p(d2, "time", "event")
  fit2 <- survfit(Surv(start, time, event) ~ class, data = d2)
  cur2 <- .surv_tidy(fit2) %>%
    mutate(seg = "late") %>%
    .add_start(L) %>%
    filter(time >= L - 1e-8)

  # 统一 class 标签
  lvl <- levels(df$class)
  cur1$class <- factor(as.character(cur1$class), levels = lvl)
  cur2$class <- factor(as.character(cur2$class), levels = lvl)

  pal <- unname(cols[lvl]); names(pal) <- lvl

  th <- theme_classic(base_size = 11, base_family = .font) +
    theme(
      legend.position = "top",
      legend.title = element_blank(),
      axis.title = element_text(size = 11),
      axis.text = element_text(size = 10, color = "black"),
      plot.tag = element_text(face = "bold", size = 14),
      plot.margin = margin(4, 2, 2, 6)
    )

  p_e <- ggplot(cur1, aes(time, surv, color = class)) +
    geom_step(linewidth = 0.9) +
    scale_color_manual(values = pal, drop = FALSE) +
    # 左段只标 0，cut 用右段红字，避免「55」叠字
    scale_x_continuous(limits = c(0, L), breaks = 0, expand = c(0.02, 0)) +
    scale_y_continuous(limits = c(0, 1.02), breaks = seq(0, 1, 0.25),
                       labels = function(x) sprintf("%.0f", x * 100)) +
    labs(x = NULL, y = "Survival probability", tag = tag) +
    annotate("text", x = L * 0.42, y = 0.12, label = .fmt_p(p_left),
             size = 3.2, family = .font) +
    th + theme(
      legend.position = "none",
      plot.tag.position = c(0.02, 0.98),
      plot.margin = margin(4, 1, 2, 6)
    )

  p_l <- ggplot(cur2, aes(time, surv, color = class)) +
    geom_step(linewidth = 0.9) +
    geom_vline(xintercept = L, linetype = "dashed", color = "grey55", linewidth = 0.35) +
    scale_color_manual(values = pal, drop = FALSE, name = NULL) +
    scale_x_continuous(
      limits = c(L, max_fu),
      breaks = c(7, 14, 21, 28),
      expand = c(0.02, 0)
    ) +
    scale_y_continuous(limits = c(0, 1.02), breaks = seq(0, 1, 0.25),
                       labels = NULL) +
    labs(x = NULL, y = NULL) +
    annotate("text", x = L + (max_fu - L) * 0.35, y = 0.12, label = .fmt_p(p_right),
             size = 3.2, family = .font) +
    th +
    theme(
      axis.line.y = element_blank(),
      axis.ticks.y = element_blank(),
      legend.position = c(0.98, 0.98),
      legend.justification = c(1, 1),
      legend.background = element_rect(fill = "white", color = NA),
      legend.key.height = grid::unit(0.32, "cm"),
      legend.text = element_text(size = 9),
      plot.margin = margin(4, 8, 2, 4)
    )

  # 风险表（0,7,14,21,28）
  risk <- .risk_at(df, c(0, 7, 14, 21, 28)) %>%
    mutate(class = factor(as.character(class), levels = lvl))
  p_risk <- ggplot(risk, aes(x = t, y = class, label = n)) +
    geom_text(size = 3.1, family = .font) +
    scale_x_continuous(breaks = c(0, 7, 14, 21, 28), limits = c(0, max_fu)) +
    scale_y_discrete(limits = rev(lvl)) +
    labs(x = "Days", y = "No. at risk") +
    theme_classic(base_size = 10, base_family = .font) +
    theme(
      axis.title.y = element_text(size = 10),
      axis.text.y = element_text(size = 9, color = unname(cols[rev(lvl)])),
      axis.text.x = element_text(size = 9),
      plot.margin = margin(2, 8, 4, 6)
    )

  # 中间窄条只写红色 landmark 日，模仿文献断轴
  p_gap <- ggplot() +
    annotate("text", x = 0.5, y = 0.02, label = as.character(as.integer(L)),
             color = "#D62728", fontface = "bold", size = 3.8, family = .font) +
    scale_x_continuous(limits = c(0, 1)) +
    scale_y_continuous(limits = c(0, 1.02)) +
    theme_void() +
    theme(plot.margin = margin(4, 0, 18, 0))

  # 右段不再重复红字，避免与 gap 叠字
  p_l <- p_l + theme(plot.margin = margin(4, 8, 2, 0))

  list(early = p_e, gap = p_gap, late = p_l, risk = p_risk,
       p_left = p_left, p_right = p_right)
}

.assemble_cohort <- function(parts) {
  (parts$early + parts$gap + parts$late +
     patchwork::plot_layout(widths = c(1.0, 0.12, 3.1))) /
    parts$risk +
    patchwork::plot_layout(heights = c(3.2, 1.0))
}

landmark <- .resolve_landmark()
df_m <- .load_km_df("mimic")
df_e <- .load_km_df("eicu")
cli::cli_alert_info("landmark cut = {landmark} 天（与 piecewise Cox 最优一致）")
cli::cli_alert_info("MIMIC n={nrow(df_m)} classes={paste(levels(df_m$class), collapse=',')}")
cli::cli_alert_info("eICU  n={nrow(df_e)} classes={paste(levels(df_e$class), collapse=',')}")

if (!requireNamespace("patchwork", quietly = TRUE)) stop("需要 patchwork")

parts_m <- .panel_km(df_m, "a")
parts_e <- .panel_km(df_e, "b")
# 用 wrap_elements 包一层，避免嵌套 patchwork nrow 冲突
p <- patchwork::wrap_elements(full = .assemble_cohort(parts_m)) /
  patchwork::wrap_elements(full = .assemble_cohort(parts_e)) +
  patchwork::plot_layout(heights = c(1, 1))

out_pdf <- file.path(
  ix_root, "summary_results/Figures/pdf",
  "Figure 2. Kaplan Meier survival by trajectory class.pdf"
)
dir.create(dirname(out_pdf), recursive = TRUE, showWarnings = FALSE)
grDevices::cairo_pdf(out_pdf, width = 8.2, height = 10.2, family = .font)
print(p)
grDevices::dev.off()

md <- file.path(
  ix_root, "summary_results/Figures/image_information",
  "Figure 2. Kaplan Meier survival by trajectory class.md"
)
writeLines(c(
  "# Figure 2. Kaplan Meier survival by trajectory class",
  "",
  "## 图面说明",
  "对齐文献 Figure 2：landmark Kaplan–Meier（分段横轴）。",
  paste0("- 分段点 = piecewise Cox 最优 cut = day ", landmark, "（红字标出）。"),
  "- 左段：ICU 入科后 0–cut 天，全分析集；右段：cut 时仍在险者，条件生存从 100% 重启至 day 28。",
  "- 两段各自标注 log-rank P。",
  "- a = MIMIC-IV 发现集；b = eICU 外验。",
  "- 下方 No. at risk：0 / 7 / 14 / 21 / 28 天。",
  "",
  "## 分析上下文",
  paste0("暴露 ", ix, "；结局 28 天院内死亡；landmark=", landmark, " 天。")
), md)

cli::cli_alert_success("已重画 Fig2 landmark KM → {.file {out_pdf}}")
