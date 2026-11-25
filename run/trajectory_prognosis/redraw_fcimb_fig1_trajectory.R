#!/usr/bin/env Rscript
# 重画 Figure 1：对齐 fcimb-16-1871653（上下 a/b，各类均值曲线叠图 + 图例含 n）
#   Rscript run/trajectory_prognosis/redraw_fcimb_fig1_trajectory.R --index GPR

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
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

proj <- .get("--proj", "G:/02block_result/55_COPD/Prognosis_Trajectory_v2_42558177")
ix <- .get("--index", "GPR")
ix_root <- file.path(proj, paste0("by_index/\u3010success\u3011", ix))
if (!dir.exists(ix_root)) stop("缺少指标根: ", ix_root)
opt_ng <- file.path(ix_root, "mimic/step14_trajectory_jlcm/Tables/Summary", paste0("optimal_ng_", ix, ".txt"))
if (!file.exists(opt_ng))
  opt_ng <- file.path(ix_root, "mimic/Tables/Summary", paste0("optimal_ng_", ix, ".txt"))
ng <- if (file.exists(opt_ng)) {
  suppressWarnings(as.integer(trimws(readLines(opt_ng, warn = FALSE)[1L])))
} else 3L
if (!is.finite(ng) || ng < 2L) ng <- 3L
cycle <- 28L
id_col <- "subject_id"

cols <- c(
  "Class 1" = "#E69F00",
  "Class 2" = "#0072B2",
  "Class 3" = "#009E73",
  "Class 4" = "#D55E00",
  "Class 5" = "#CC79A7",
  "Class 6" = "#56B4E9"
)

# ── MIMIC：predictY 均值曲线 ────────────────────────────────────────────────
mod_path <- file.path(ix_root, "mimic/step14_trajectory_jlcm/Data", paste0("D01_jlcm_", ix, "_models.RData"))
long_path <- file.path(ix_root, "mimic/step14_trajectory_jlcm/Data", paste0("D01_long_", ix, "_D_", ng, ".RData"))
if (!file.exists(long_path)) {
  cands <- list.files(file.path(ix_root, "mimic/step14_trajectory_jlcm/Data"),
                      pattern = paste0("^D01_long_", ix, "_D_"), full.names = TRUE)
  if (length(cands)) long_path <- cands[1L]
}
e_m <- new.env(parent = emptyenv())
load(mod_path, envir = e_m)
m3 <- e_m$models_list_with_cov[[paste0("m", ng)]]
if (is.null(m3)) stop("找不到 m", ng, " 模型")

e_l <- new.env(parent = emptyenv())
load(long_path, envir = e_l)
long_m <- e_l$long
n_m <- long_m %>%
  distinct(.data[[id_col]], Class) %>%
  count(Class, name = "n") %>%
  mutate(
    class_num = as.integer(gsub("\\D", "", as.character(Class))),
    lab = sprintf("Class %d (n=%s)", class_num, format(n, big.mark = ","))
  )

# 协变量取各类均值（与 plot block 一致简化：全体均值）
need_cov <- setdiff(as.character(m3$Names$Xnames2 %||% character(0)), "time_day")
cov_mean <- long_m %>%
  summarise(across(any_of(need_cov), ~ suppressWarnings(mean(as.numeric(.x), na.rm = TRUE))))
nd <- data.frame(time_day = seq(1, cycle, by = 1))
if (ncol(cov_mean)) for (nm in names(cov_mean)) nd[[nm]] <- cov_mean[[nm]][1L]

if (!exists("ns", mode = "function")) ns <- splines::ns
suppressPackageStartupMessages(loadNamespace("splines"))
assign("ns", splines::ns, envir = .GlobalEnv)

pred <- tryCatch(
  lcmm::predictY(m3, newdata = nd, var.time = "time_day", draws = FALSE),
  error = function(e) stop("predictY 失败: ", conditionMessage(e))
)
# pred$pred 列 Ypred_class1.. 
pred_mat <- as.data.frame(pred$pred)
time_v <- if (is.data.frame(pred$times)) {
  as.numeric(pred$times[[1L]])
} else {
  as.numeric(pred$times %||% nd$time_day)
}
curve_m <- lapply(seq_len(ng), function(k) {
  cn <- names(pred_mat)
  if (!length(cn)) cn <- paste0("V", seq_len(ncol(pred_mat)))
  pick <- cn[k]
  hit <- grep(paste0("(class|_Y)", k, "$"), cn, ignore.case = TRUE, value = TRUE)
  if (length(hit)) pick <- hit[1L]
  data.frame(
    time = time_v,
    value = as.numeric(pred_mat[[pick]]),
    class_num = k,
    cohort = "a",
    stringsAsFactors = FALSE
  )
}) %>% bind_rows()
curve_m <- curve_m %>%
  left_join(n_m %>% select(class_num, lab, n), by = "class_num") %>%
  mutate(class_lab = lab)

# ── eICU：m3 predictClass + 观测日均值 ──────────────────────────────────────
wide_path <- file.path(proj, "data/eicu", paste0("12_", ix, ".RData"))
e_w <- new.env(parent = emptyenv())
load(wide_path, envir = e_w)
index_df <- e_w$index_df
if (is.null(index_df)) stop("eICU 宽表无 index_df")

day_cols <- paste0(ix, "_", seq_len(cycle))
day_cols <- day_cols[day_cols %in% names(index_df)]
long_e <- lapply(day_cols, function(dc) {
  day <- as.integer(sub(paste0("^", ix, "_"), "", dc))
  data.frame(
    subject_id = as.character(index_df[[id_col]]),
    time_day = day,
    Value = suppressWarnings(as.numeric(index_df[[dc]])),
    stringsAsFactors = FALSE
  )
}) %>% bind_rows() %>% filter(is.finite(Value))

# 准备 newdata（对齐 13block）
nm <- m3$Names
y_col <- as.character(nm$Yname %||% "scr_std")[1L]
subj_col <- as.character(nm$ID %||% "subject_id_num")[1L]
x_need <- as.character(nm$Xnames2 %||% character(0))
id_chr <- long_e$subject_id
id_levels <- unique(id_chr)
newdata <- data.frame(
  time_day = as.numeric(long_e$time_day),
  stringsAsFactors = FALSE
)
newdata[[y_col]] <- as.numeric(long_e$Value)
newdata[[subj_col]] <- as.integer(match(id_chr, id_levels))
newdata[[id_col]] <- id_chr

# 协变量：从 eICU dabiao 合并；缺则用发现集 model_data 中位数
base_path <- file.path(proj, "data/eicu/D02_COPD_EICU_surv28.RData")
e_b <- new.env(parent = emptyenv())
load(base_path, envir = e_b)
base <- e_b$data_imp %||% e_b$data %||% NULL
mdata <- e_m$model_data_final
cov_need <- setdiff(x_need, "time_day")
for (cv in cov_need) {
  if (!is.null(base) && cv %in% names(base) && id_col %in% names(base)) {
    b1 <- unique(base[, c(id_col, cv), drop = FALSE])
    b1[[id_col]] <- as.character(b1[[id_col]])
    newdata <- merge(newdata, b1, by = id_col, all.x = TRUE)
  }
  if (!cv %in% names(newdata)) {
    fill <- if (!is.null(mdata) && cv %in% names(mdata)) {
      suppressWarnings(median(as.numeric(mdata[[cv]]), na.rm = TRUE))
    } else 0
    newdata[[cv]] <- fill
  } else {
    miss <- !is.finite(as.numeric(newdata[[cv]]))
    if (any(miss)) {
      fill <- if (!is.null(mdata) && cv %in% names(mdata)) {
        suppressWarnings(median(as.numeric(mdata[[cv]]), na.rm = TRUE))
      } else suppressWarnings(median(as.numeric(newdata[[cv]]), na.rm = TRUE))
      newdata[[cv]][miss] <- fill
    }
  }
}

# 生存列若在 Names
for (tv in as.character(nm$Tnames %||% character(0))) {
  if (!tv %in% names(newdata)) {
    if (!is.null(base) && tv %in% names(base)) {
      b1 <- unique(base[, c(id_col, tv), drop = FALSE])
      b1[[id_col]] <- as.character(b1[[id_col]])
      newdata <- merge(newdata, b1, by = id_col, all.x = TRUE)
    }
    if (!tv %in% names(newdata) || anyNA(newdata[[tv]])) {
      fill <- if (!is.null(mdata) && tv %in% names(mdata)) {
        suppressWarnings(median(as.numeric(mdata[[tv]]), na.rm = TRUE))
      } else 28
      if (!tv %in% names(newdata)) newdata[[tv]] <- fill
      else newdata[[tv]][!is.finite(as.numeric(newdata[[tv]]))] <- fill
    }
  }
}

pc_args <- names(formals(lcmm::predictClass))
pc_call <- list(model = m3, newdata = newdata)
if ("subject" %in% pc_args) pc_call$subject <- subj_col
pred_c <- do.call(lcmm::predictClass, pc_call)
# class 列
cls_col <- intersect(c("class", "Class", "trajectory_class"), names(pred_c))[1L]
# subject 映射回 id
# pred_c 常有 subject = subject_id_num
sid <- pred_c[["subject_id_num"]] %||% pred_c[["subject"]] %||% pred_c[[subj_col]]
if (is.null(sid)) stop("predictClass 无 subject")
# 按行：newdata 与 pred 若按人折叠
if (length(sid) == length(id_levels) || length(unique(sid)) == length(id_levels)) {
  # 个体级
  assign_e <- data.frame(
    subject_id = id_levels[as.integer(sid)],
    trajectory_class = as.integer(pred_c[[cls_col]]),
    stringsAsFactors = FALSE
  )
} else if (nrow(pred_c) == nrow(newdata)) {
  assign_e <- data.frame(
    subject_id = as.character(newdata[[id_col]]),
    trajectory_class = as.integer(pred_c[[cls_col]]),
    stringsAsFactors = FALSE
  ) %>% distinct(subject_id, .keep_all = TRUE)
} else {
  # 尝试用 pred 的 subject 作为 id_levels 索引
  assign_e <- data.frame(
    subject_id = id_levels[as.integer(sid)],
    trajectory_class = as.integer(pred_c[[cls_col]]),
    stringsAsFactors = FALSE
  ) %>% filter(!is.na(subject_id)) %>% distinct(subject_id, .keep_all = TRUE)
}
assign_e <- assign_e %>% filter(is.finite(trajectory_class))
n_e <- assign_e %>% count(trajectory_class, name = "n") %>%
  mutate(
    class_num = as.integer(trajectory_class),
    lab = sprintf("Class %d (n=%s)", class_num, format(n, big.mark = ","))
  )
cli::cli_alert_info("eICU m3 分类: {paste(sprintf('C%d=%d', n_e$class_num, n_e$n), collapse=', ')}")

long_e2 <- long_e %>%
  inner_join(assign_e, by = "subject_id") %>%
  filter(trajectory_class %in% seq_len(ng))

# 观测日均值再 LOESS 平滑（对齐文献 Fig1b 光滑曲线，避免日均锯齿）
curve_e_raw <- long_e2 %>%
  group_by(class_num = as.integer(trajectory_class), time = time_day) %>%
  summarise(value = mean(Value, na.rm = TRUE), .groups = "drop")
curve_e <- curve_e_raw %>%
  group_by(class_num) %>%
  group_modify(function(.x, .y) {
    if (nrow(.x) < 4L) return(.x)
    fit <- tryCatch(
      stats::loess(value ~ time, data = .x, span = 0.55, degree = 2),
      error = function(e) NULL
    )
    if (is.null(fit)) return(.x)
    .x$value <- as.numeric(stats::predict(fit, newdata = .x))
    .x
  }) %>%
  ungroup() %>%
  left_join(n_e %>% select(class_num, lab, n), by = "class_num") %>%
  mutate(cohort = "b", class_lab = lab)

# 落盘外验 ng=3 分配（覆盖错误的 ng=6）
asg_dir <- file.path(ix_root, "eicu/step14_trajectory_lcmm_external_validate/Tables/LCMM")
dir.create(asg_dir, recursive = TRUE, showWarnings = FALSE)
utils::write.csv(
  assign_e %>% mutate(cohort = "eICU", ng = ng, discovery_model = basename(mod_path)),
  file.path(asg_dir, paste0("Table_LCMM_Assignment_External_", ix, ".csv")),
  row.names = FALSE
)

# ── 作图 ────────────────────────────────────────────────────────────────────
.font <- tryCatch(resolve_plot_font_family(), error = function(e) "sans")

.make_panel <- function(df, tag) {
  df <- df %>%
    mutate(
      class_lab = factor(class_lab, levels = unique(class_lab[order(class_num)])),
      col_key = paste("Class", class_num)
    )
  ggplot(df, aes(x = time, y = value, color = col_key)) +
    geom_line(linewidth = 1.15) +
    scale_color_manual(
      values = cols[unique(df$col_key)],
      breaks = paste("Class", sort(unique(df$class_num))),
      labels = df %>% distinct(class_num, class_lab) %>% arrange(class_num) %>% pull(class_lab),
      name = NULL
    ) +
    scale_x_continuous(breaks = c(0, 7, 14, 21, 28), limits = c(0, cycle)) +
    labs(x = "Days", y = ix) +
    theme_classic(base_size = 12, base_family = .font) +
    theme(
      legend.position = c(0.98, 0.98),
      legend.justification = c(1, 1),
      legend.background = element_rect(fill = "white", color = NA),
      legend.key.height = grid::unit(0.35, "cm"),
      legend.text = element_text(size = 9),
      axis.title = element_text(size = 11),
      axis.text = element_text(size = 10, color = "black"),
      plot.margin = margin(8, 10, 6, 8),
      plot.tag = element_text(face = "bold", size = 14),
      plot.tag.position = c(0.02, 0.98)
    ) +
    labs(tag = tag)
}

p_a <- .make_panel(curve_m, "a")
p_b <- .make_panel(curve_e, "b")

if (!requireNamespace("patchwork", quietly = TRUE)) {
  stop("需要 patchwork 包竖拼 a/b")
}
p <- p_a / p_b + patchwork::plot_layout(heights = c(1, 1))

out_pdf <- file.path(
  ix_root, "summary_results/Figures/pdf",
  sprintf("Figure 1. Trajectory of %s latent classes.pdf", ix)
)
dir.create(dirname(out_pdf), recursive = TRUE, showWarnings = FALSE)
grDevices::cairo_pdf(out_pdf, width = 7.2, height = 8.2, family = .font)
print(p)
grDevices::dev.off()

out_m <- file.path(ix_root, "mimic/Figures", sprintf("Figure Trajectory %s fcimb-style overlay.pdf", ix))
grDevices::cairo_pdf(out_m, width = 7.2, height = 4.0, family = .font)
print(p_a + labs(tag = NULL))
grDevices::dev.off()

md <- file.path(
  ix_root, "summary_results/Figures/image_information",
  sprintf("Figure 1. Trajectory of %s latent classes.md", ix)
)
dir.create(dirname(md), recursive = TRUE, showWarnings = FALSE)
writeLines(c(
  sprintf("# Figure 1. Trajectory of %s latent classes", ix),
  "",
  "## 图面说明",
  "对齐文献 Figure 1：上下两栏。",
  sprintf("- a：MIMIC-IV 发现集，JLCM ng=%d 的 predictY 类别均值曲线叠图；图例含各类 n。", ng),
  sprintf("- b：eICU 外验，发现集 m%d 固定参数 predictClass 后，按日观测 %s 均值曲线叠图；图例含各类 n。", ng, ix),
  "版式为单坐标系多类曲线（非分面灰线）。",
  "",
  "## 分析上下文",
  sprintf("暴露 %s；潜类数 %d；结局 28 天院内死亡；数据库 MIMIC（derivation）+ eICU（validation）。", ix, ng)
), md)

cli::cli_alert_success("已重画 Fig1 → {.file {out_pdf}}")
cli::cli_alert_info("MIMIC n: {paste(sprintf('C%d=%d', n_m$class_num, n_m$n), collapse=', ')}")
cli::cli_alert_info("eICU  n: {paste(sprintf('C%d=%d', n_e$class_num, n_e$n), collapse=', ')}")
