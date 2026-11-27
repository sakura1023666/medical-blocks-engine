#!/usr/bin/env Rscript
# Figure S4：敏感性 JLCM 轨迹（对齐 fcimb Supp Fig4）
#
# 默认 --mode allcause28：
#   主文 = 28 天「院内」死亡（death_within_hosp_28days）
#   敏感性 = MIMIC 完整随访 28 天死亡（icu_intime→dead_time ≤28，含出院后死亡）
#
# 可选 --mode landmark --landmark 14：缩短时间窗（备用）
#
#   Rscript run/trajectory_prognosis/redraw_wpr_fig_s4_sensitivity_landmark.R
#   Rscript run/trajectory_prognosis/redraw_wpr_fig_s4_sensitivity_landmark.R --mode landmark --landmark 14

suppressPackageStartupMessages({
  options(warn = 1)
  library(dplyr)
  library(ggplot2)
  library(data.table)
  library(splines)
  library(survival)
  library(lcmm)
})

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
source("R/utils.R")

.args <- commandArgs(trailingOnly = TRUE)
.get <- function(flag, default = NULL) {
  i <- match(flag, .args)
  if (is.na(i) || i >= length(.args)) return(default)
  .args[[i + 1L]]
}

proj <- .get("--proj", "/mnt/g/02block_result/55_COPD/Prognosis_Trajectory_v2_42558177")
if (!dir.exists(proj)) proj <- "G:/02block_result/55_COPD/Prognosis_Trajectory_v2_42558177"
ix <- .get("--index", "WPR")
ng <- as.integer(.get("--ng", "4"))
mode <- tolower(.get("--mode", "allcause28"))
lm_days <- as.integer(.get("--landmark", "14"))
cycle_plot <- 28L

ix_root <- file.path(proj, paste0("by_index/\u3010success\u3011", ix))
mod_path <- file.path(ix_root, "mimic/step14_trajectory_jlcm/Data", paste0("D01_jlcm_", ix, "_models.RData"))
stopifnot(file.exists(mod_path))

e_m <- new.env(parent = emptyenv())
load(mod_path, envir = e_m)
m_pri <- e_m$models_list_with_cov[[paste0("m", ng)]]
if (is.null(m_pri)) stop("缺主文 m", ng)
md0 <- e_m$model_data_final
stopifnot(is.data.frame(md0), nrow(md0) > 0)

cols <- c(
  "Class 1" = "#E69F00", "Class 2" = "#0072B2", "Class 3" = "#009E73",
  "Class 4" = "#D55E00", "Class 5" = "#CC79A7", "Class 6" = "#56B4E9"
)
cov_lock <- intersect(
  c("CHARLSON", "Age", "RDW", "NeutrophilCount"),
  names(md0)
)

# ── 构建敏感性生存结局 ──────────────────────────────────────────────────────
.build_allcause28 <- function(md) {
  copd_path <- file.path(proj, "data/mimic/COPD-预后(1).csv")
  if (!file.exists(copd_path)) stop("缺 ", copd_path)
  dt <- unique(data.table::fread(copd_path), by = "subject_id")
  fmt_dt <- "%d/%m/%Y %H:%M:%S"
  dt[, icu_in := as.POSIXct(icu_intime, format = fmt_dt, tz = "UTC")]
  dt[is.na(icu_in), icu_in := as.POSIXct(icu_intime, format = "%d/%m/%Y %H:%M", tz = "UTC")]
  dt[, dead := as.POSIXct(dead_time, format = fmt_dt, tz = "UTC")]
  dt[is.na(dead) & nzchar(as.character(dead_time)) & as.character(dead_time) != "NA",
     dead := as.POSIXct(dead_time, format = "%d/%m/%Y", tz = "UTC")]
  dt[, days_to_dead := as.numeric(difftime(dead, icu_in, units = "days"))]
  dt[, death_28d_ac := as.integer(
    !is.na(dead) & is.finite(days_to_dead) & days_to_dead >= 0 & days_to_dead <= 28
  )]
  dt[, t_ac := data.table::fifelse(
    death_28d_ac == 1L, pmax(0.01, pmin(28, days_to_dead)), 28
  )]
  map <- dt[, .(
    subject_id = as.character(subject_id),
    surv_event_ac = death_28d_ac,
    surv_time_ac = as.numeric(t_ac),
    death_hosp28 = as.integer(death_within_hosp_28days == 1L)
  )]

  out <- md
  id_chr <- if ("subject_id" %in% names(out)) as.character(out$subject_id) else NA_character_
  if (all(is.na(id_chr)) || !length(id_chr)) stop("model_data 无 subject_id")
  out$subject_id <- id_chr
  out <- merge(out, map, by = "subject_id", all.x = TRUE, sort = FALSE)
  # 分析集内若缺 dead_time：回退主文院内结局（不凭空造死亡）
  miss <- is.na(out$surv_event_ac)
  if (any(miss)) {
    cli::cli_alert_warning("allcause 映射缺失 {sum(miss)} 行 → 回退主文 surv_*")
    out$surv_event_ac[miss] <- as.integer(out$surv_event[miss])
    out$surv_time_ac[miss] <- as.numeric(out$surv_time[miss])
  }
  n_subj <- length(unique(out$subject_id_num))
  u <- out[!duplicated(out$subject_id_num), , drop = FALSE]
  n_hosp <- sum(u$death_hosp28 == 1L, na.rm = TRUE)
  n_ac <- sum(u$surv_event_ac == 1L, na.rm = TRUE)
  n_extra <- sum(u$surv_event_ac == 1L & u$death_hosp28 != 1L, na.rm = TRUE)
  cli::cli_alert_info(
    "MIMIC 完整随访 28d：院内事件={n_hosp}；全因28d={n_ac}；新增（出院后等）={n_extra}；n={n_subj}"
  )
  out$surv_event <- as.integer(out$surv_event_ac)
  out$surv_time <- as.numeric(out$surv_time_ac)
  if ("survival_28d" %in% names(out)) out$survival_28d <- out$surv_event
  if ("survival_time_28d" %in% names(out)) out$survival_time_28d <- out$surv_time
  attr(out, "sens_label") <- "28-day mortality (complete follow-up)"
  attr(out, "sens_tag") <- "allcause28"
  attr(out, "n_extra") <- n_extra
  out
}

.truncate_surv <- function(md, landmark) {
  out <- md
  t0 <- suppressWarnings(as.numeric(out$surv_time))
  e0 <- suppressWarnings(as.integer(out$surv_event))
  out$surv_time <- pmin(t0, as.numeric(landmark))
  out$surv_event <- as.integer(e0 == 1L & t0 <= as.numeric(landmark))
  if ("survival_time_28d" %in% names(out)) out$survival_time_28d <- out$surv_time
  if ("survival_28d" %in% names(out)) out$survival_28d <- out$surv_event
  attr(out, "sens_label") <- sprintf("%d-day mortality", landmark)
  attr(out, "sens_tag") <- paste0("L", landmark)
  out
}

.refit_ng <- function(md, tag) {
  cli::cli_h2("敏感性 JLCM ng={ng} · {tag}")
  u <- md[!duplicated(md$subject_id_num), , drop = FALSE]
  n_ev <- sum(u$surv_event == 1L, na.rm = TRUE)
  cli::cli_alert_info("个体 n={nrow(u)}；事件={n_ev} ({sprintf('%.1f', 100 * n_ev / nrow(u))}%)")
  if (n_ev < 30L) stop("事件过少")

  .__jlcm_sens_data__ <<- md
  on.exit(rm(list = ".__jlcm_sens_data__", envir = .GlobalEnv), add = TRUE)

  fml_surv <- stats::as.formula(
    paste0("Surv(surv_time, surv_event) ~ ", paste(cov_lock, collapse = " + "))
  )
  B0 <- tryCatch(as.numeric(m_pri$best), error = function(e) NULL)
  args <- list(
    fixed = scr_std ~ ns(time_day, df = 2),
    mixture = ~ ns(time_day, df = 2),
    random = ~ ns(time_day, df = 2),
    subject = "subject_id_num",
    ng = as.integer(ng),
    survival = fml_surv,
    hazard = "Weibull",
    hazardtype = "Specific",
    data = .__jlcm_sens_data__,
    verbose = FALSE,
    maxiter = 100L
  )
  if (!is.null(B0)) args$B <- B0

  m <- tryCatch(do.call(lcmm::Jointlcmm, args), error = function(e) {
    cli::cli_alert_warning("warm-start 失败: {e$message}")
    NULL
  })
  if (is.null(m) || !inherits(m, "Jointlcmm") || !isTRUE(m$conv %in% c(1, 2, 3))) {
    args$B <- NULL
    m <- tryCatch(do.call(lcmm::Jointlcmm, args), error = function(e) NULL)
  }
  if (is.null(m) || !inherits(m, "Jointlcmm")) stop("敏感性 JLCM 未收敛")
  cli::cli_alert_success("收敛 conv={m$conv} loglik={round(m$loglik, 2)}")
  pprob <- tryCatch(m$pprob, error = function(e) NULL)
  if (!is.null(pprob) && "class" %in% names(pprob)) {
    tab <- table(pprob$class)
    cli::cli_alert_info("类人数: {paste(sprintf('C%s=%s', names(tab), as.integer(tab)), collapse=', ')}")
  }
  m
}

.predict_curves <- function(m, md) {
  pprob <- m$pprob
  cls <- as.integer(pprob$class)
  n_tab <- as.data.frame(table(cls), stringsAsFactors = FALSE)
  names(n_tab) <- c("class_num", "n")
  n_tab$class_num <- as.integer(as.character(n_tab$class_num))
  n_tab$n <- as.integer(n_tab$n)
  n_tab$lab <- sprintf("Class %d (n=%s)", n_tab$class_num, format(n_tab$n, big.mark = ",", trim = TRUE))

  need_cov <- intersect(cov_lock, names(md))
  cov_mean <- md %>% summarise(across(all_of(need_cov), ~ mean(as.numeric(.x), na.rm = TRUE)))
  nd <- data.frame(time_day = seq(1, cycle_plot, by = 1))
  for (nm in names(cov_mean)) nd[[nm]] <- cov_mean[[nm]][1L]
  assign("ns", splines::ns, envir = .GlobalEnv)
  pred <- lcmm::predictY(m, newdata = nd, var.time = "time_day", draws = FALSE)
  pred_mat <- as.data.frame(pred$pred)
  time_v <- if (is.data.frame(pred$times)) as.numeric(pred$times[[1L]]) else
    as.numeric(pred$times %||% nd$time_day)
  cn <- names(pred_mat)
  if (!length(cn)) cn <- paste0("V", seq_len(ncol(pred_mat)))

  curve <- lapply(seq_len(ng), function(k) {
    hit <- grep(paste0("(class|_Y)", k, "$"), cn, ignore.case = TRUE, value = TRUE)
    pick <- if (length(hit)) hit[1L] else cn[min(k, length(cn))]
    data.frame(
      time = time_v, value = as.numeric(pred_mat[[pick]]),
      class_num = k, stringsAsFactors = FALSE
    )
  }) %>%
    bind_rows() %>%
    left_join(n_tab, by = "class_num") %>%
    mutate(class_lab = lab, col_key = paste("Class", class_num))
  # 类内 NA 插值，避免断线
  curve <- curve %>%
    group_by(class_num) %>%
    mutate(value = {
      v <- value
      ok <- is.finite(v)
      if (sum(ok) >= 2L && any(!ok)) approx(time[ok], v[ok], xout = time, rule = 2)$y else v
    }) %>%
    ungroup()
  list(curve = curve, n_tab = n_tab)
}

.make_panel <- function(df) {
  df <- df %>%
    mutate(class_lab = factor(class_lab, levels = unique(class_lab[order(class_num)])))
  .font <- tryCatch(resolve_plot_font_family(), error = function(e) "sans")
  ggplot(df, aes(x = time, y = value, color = col_key)) +
    geom_line(linewidth = 1.2) +
    scale_color_manual(
      values = cols[intersect(names(cols), unique(df$col_key))],
      breaks = paste("Class", sort(unique(df$class_num))),
      labels = df %>% distinct(class_num, class_lab) %>% arrange(class_num) %>% pull(class_lab),
      name = NULL
    ) +
    scale_x_continuous(breaks = c(0, 7, 14, 21, 28), limits = c(0, cycle_plot)) +
    labs(x = "Days", y = ix) +
    theme_classic(base_size = 12, base_family = .font) +
    theme(
      # 图例外置右侧，避免挡住右侧发散轨迹（文献图内嵌会挡）
      legend.position = "right",
      legend.justification = "center",
      legend.background = element_rect(fill = "white", color = NA),
      legend.key.height = grid::unit(0.42, "cm"),
      legend.text = element_text(size = 9),
      axis.title = element_text(face = "bold", size = 11),
      axis.text = element_text(size = 10, color = "black"),
      plot.margin = margin(8, 8, 6, 8)
    )
}

# ── 主流程 ──────────────────────────────────────────────────────────────────
if (identical(mode, "allcause28")) {
  md <- .build_allcause28(md0)
  tag <- "allcause28"
  sens_lab <- attr(md, "sens_label")
  file_stem <- "Figure S4. Sensitivity trajectory 28d complete follow-up"
} else if (identical(mode, "landmark")) {
  md <- .truncate_surv(md0, lm_days)
  tag <- paste0("L", lm_days)
  sens_lab <- attr(md, "sens_label")
  file_stem <- sprintf("Figure S4. Sensitivity trajectory %dd mortality", lm_days)
} else {
  stop("未知 --mode: ", mode, "（用 allcause28 或 landmark）")
}

m <- .refit_ng(md, tag)
pred <- .predict_curves(m, md)
curve <- pred$curve
n_tab <- pred$n_tab

sens_dir <- file.path(ix_root, "mimic/sensitivity_jlcm_landmark", tag)
dir.create(file.path(sens_dir, "Tables"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(sens_dir, "Data"), recursive = TRUE, showWarnings = FALSE)
saveRDS(m, file.path(sens_dir, "Data", paste0("JLCM_", ix, "_ng", ng, "_", tag, ".rds")))
utils::write.csv(n_tab, file.path(sens_dir, "Tables", paste0("Class_n_", ix, "_", tag, ".csv")), row.names = FALSE)
utils::write.csv(curve, file.path(sens_dir, "Tables", paste0("Trajectory_mean_", ix, "_", tag, ".csv")), row.names = FALSE)

p <- .make_panel(curve)
out_pdf <- file.path(ix_root, "summary_results/Figures/pdf", paste0(file_stem, ".pdf"))
dir.create(dirname(out_pdf), recursive = TRUE, showWarnings = FALSE)
.font <- tryCatch(resolve_plot_font_family(), error = function(e) "sans")
grDevices::cairo_pdf(out_pdf, width = 8.0, height = 4.6, family = .font)
print(p)
grDevices::dev.off()

# 清理旧 S4 文件名，只留本模式
old_s4 <- list.files(
  file.path(ix_root, "summary_results/Figures/pdf"),
  pattern = "^Figure S4\\.", full.names = TRUE
)
old_s4 <- old_s4[basename(old_s4) != basename(out_pdf)]
if (length(old_s4)) unlink(old_s4)
old_md <- list.files(
  file.path(ix_root, "summary_results/Figures/image_information"),
  pattern = "^Figure S4\\.", full.names = TRUE
)
md_path <- file.path(ix_root, "summary_results/Figures/image_information", paste0(file_stem, ".md"))
old_md <- old_md[basename(old_md) != basename(md_path)]
if (length(old_md)) unlink(old_md)

n_extra <- attr(md, "n_extra") %||% NA_integer_
writeLines(c(
  paste0("# ", file_stem),
  "",
  "## 图面说明",
  "",
  "单栏多类均值轨迹叠图（对齐 fcimb Supplementary Figure 4 / image 4.tif）。",
  paste0("敏感性：", sens_lab, "；主文为 28 天**院内**死亡。"),
  if (identical(mode, "allcause28"))
    paste0("MIMIC 用 icu_intime→dead_time≤28 天定义全因死亡（含出院后死亡）；相对院内终点新增事件约 ", n_extra, " 人。")
  else NULL,
  paste0("重估 JLCM ng=", ng, " 后 predictY；图例外置右侧以免挡曲线。横轴 Days 0–28，纵轴 ", ix, "。"),
  "",
  "### 图上标注",
  "",
  paste0("- 类人数：", paste(sprintf("C%d=%s", n_tab$class_num, n_tab$n), collapse = ", ")),
  "",
  "## 分析上下文",
  "",
  paste0("- 暴露：", ix, "；主文结局：28 天院内死亡；敏感性：", sens_lab),
  "- 数据库：MIMIC-IV derivation（文献 Supp Fig4 同）",
  "- 是否拼图：否（单面板）",
  ""
), md_path)

cli::cli_alert_success("S4 → {.file {out_pdf}}")
cli::cli_alert_info("敏感性模型目录: {.file {sens_dir}}")
