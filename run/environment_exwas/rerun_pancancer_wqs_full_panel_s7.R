#!/usr/bin/env Rscript
# 对齐 Dong Fig7/S7：筛后大面板进 gWQS（非仅 FDR 命中）→ 重画 Figure S7 长名单权重图
#
#   Rscript run/environment_exwas/rerun_pancancer_wqs_full_panel_s7.R [--wqs-boot 1000]
#
args <- commandArgs(trailingOnly = TRUE)
opt <- list(
  root = "/mnt/g/02block_result/58_cancer/environment_41380607",
  data_dir = "/mnt/g/02block_result/58_cancer/environment_41380607/data",
  min_age = 20L, wqs_boot = 1000L
)
i <- 1L
while (i <= length(args)) {
  a <- args[[i]]
  if (a == "--wqs-boot" && i < length(args)) {
    opt$wqs_boot <- as.integer(args[[i + 1L]]); i <- i + 2L
  } else if (a == "--root" && i < length(args)) {
    opt$root <- args[[i + 1L]]; i <- i + 2L
  } else stop("未知参数: ", a, call. = FALSE)
}

ca <- commandArgs(trailingOnly = FALSE)
f <- grep("^--file=", ca, value = TRUE)
repo <- if (length(f)) {
  normalizePath(file.path(dirname(sub("^--file=", "", f[[1]])), "..", ".."), winslash = "/")
} else getwd()
setwd(repo)
source(file.path(repo, "R/environment_exwas_core.R"))
source(file.path(repo, "R/environment_exwas_aligned.R"))
source(file.path(repo, "R/environment_exwas_toxicant.R"))
source(file.path(repo, "R/environment_exwas_toxicant_downstream.R"))

if (!requireNamespace("gWQS", quietly = TRUE)) stop("需要 gWQS", call. = FALSE)
if (!requireNamespace("ggplot2", quietly = TRUE)) stop("需要 ggplot2", call. = FALSE)

root <- opt$root
sum_dir <- file.path(root, "summary_results")
src_pub <- file.path(root, "Output_pancancer_paperflow_UCR_WTSA_full_pub")
down <- file.path(src_pub, "_downstream")
fig_pdf <- file.path(sum_dir, "Figures", "pdf")
fig_md <- file.path(sum_dir, "Figures", "image_information")
tab_dir <- file.path(sum_dir, "Tables")
dir.create(fig_pdf, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_md, recursive = TRUE, showWarnings = FALSE)
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(down, recursive = TRUE, showWarnings = FALSE)

exwas_log("==== WQS full screened panel → Fig S7 ====")

built <- exwas_tox_build_cancer_table("pancancer", opt$data_dir, min_age = opt$min_age)
d0 <- built$data
d0 <- d0[is.finite(exwas_to_num(d0$URXUCR)) & exwas_to_num(d0$URXUCR) > 0, , drop = FALSE]
d0 <- d0[is.finite(exwas_to_num(d0$WTSA2YR)) & exwas_to_num(d0$WTSA2YR) > 0, , drop = FALSE]
tox <- intersect(built$tox_cols, names(d0))
d1 <- exwas_tox_creatinine_adjust(d0, tox, creat_col = "URXUCR")$data
scr <- exwas_tox_screen_transform(d1, tox)
person <- exwas_tox_drop_person_missing(
  scr$data, scr$keep, max_frac = 1 / 3, cycle_col = "cycle",
  raw_from_model = sub("_(ln|bin)$", "", scr$keep)
)
df <- person$data
df$SDMVSTRA_cyc <- as.integer(
  interaction(as.character(df$cycle), exwas_to_num(df$SDMVSTRA), drop = TRUE, lex.order = TRUE)
)
covars_m2 <- intersect(
  c("Age", "Gender", "Race", "Education", "Marital_Status", "PIR_cat", "BMI_cat",
    "Alcohol_drinking", "eGFR"),
  names(df)
)
df <- exwas_aligned_as_model_frame(df, covars_m2)

lab_map <- stats::setNames(built$code$Exposure, built$code$Labels)
disp_of <- function(raw) {
  x <- unname(lab_map[raw])
  ifelse(is.na(x) | !nzchar(as.character(x)), raw, x)
}

wqs_pool <- intersect(scr$keep, names(df))
miss_w <- vapply(wqs_pool, function(nm) mean(!is.finite(exwas_to_num(df[[nm]]))), numeric(1))
mix_cols <- names(miss_w)[is.finite(miss_w) & miss_w <= 0.55]
if (length(mix_cols) < 5L) stop("可用混合列过少: ", length(mix_cols), call. = FALSE)

cols_w <- unique(c("DN", mix_cols, covars_m2))
dw <- df[, cols_w, drop = FALSE]
for (nm in mix_cols) {
  v <- exwas_to_num(dw[[nm]])
  med <- stats::median(v[is.finite(v)], na.rm = TRUE)
  if (!is.finite(med)) med <- 0
  v[!is.finite(v)] <- med
  dw[[nm]] <- v
}
dw <- dw[stats::complete.cases(dw), , drop = FALSE]
exwas_log("WQS n=", nrow(dw), " mix=", length(mix_cols), " b=", opt$wqs_boot)

fml <- stats::as.formula(
  paste("DN ~ wqs +", paste(intersect(covars_m2, names(dw)), collapse = "+"))
)
suppressPackageStartupMessages(library(gWQS))
options(future.globals.maxSize = Inf)
fit_w <- NULL
for (bp in c(TRUE, FALSE)) {
  exwas_log("gwqs b1_pos=", bp, " …")
  fit_w <- tryCatch(
    gwqs(
      formula = fml, data = dw, mix_name = mix_cols,
      q = 4L, b = as.integer(opt$wqs_boot), b1_pos = bp,
      validation = 0.6, family = "binomial", seed = 123456L
    ),
    error = function(e) e
  )
  if (!inherits(fit_w, "error")) {
    exwas_log("收敛 b1_pos=", bp)
    break
  }
  exwas_log("失败 b1_pos=", bp, ": ", conditionMessage(fit_w))
}
if (inherits(fit_w, "error")) stop("WQS 未收敛: ", conditionMessage(fit_w), call. = FALSE)

wt <- as.data.frame(fit_w$final_weights, stringsAsFactors = FALSE)
# gWQS 列名常见 mix_name / mean_weight
nm_col <- if ("mix_name" %in% names(wt)) "mix_name" else names(wt)[1]
w_col <- if ("mean_weight" %in% names(wt)) "mean_weight" else {
  numc <- names(wt)[vapply(wt, is.numeric, logical(1))]
  numc[1]
}
wt$mix_name <- as.character(wt[[nm_col]])
wt$mean_weight <- as.numeric(wt[[w_col]])
wt$exposure_raw <- sub("_(ln|bin)$", "", wt$mix_name)
wt$exposure_name <- disp_of(wt$exposure_raw)
wt <- wt[order(-wt$mean_weight), , drop = FALSE]
wt$rank <- seq_len(nrow(wt))

# 落盘
utils::write.csv(wt, file.path(down, "Table_WQS_weights.csv"), row.names = FALSE)
utils::write.csv(wt, file.path(tab_dir, "Table S14. WQS mixture weights.csv"), row.names = FALSE)
# 兼容旧 xlsx 角色：写一份简易 xlsx
if (requireNamespace("openxlsx", quietly = TRUE)) {
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Weights")
  openxlsx::writeData(wb, "Weights", "Table S14. WQS mixture weights and coefficients", startRow = 1, startCol = 1)
  openxlsx::writeData(wb, "Weights", wt, startRow = 2)
  ct <- tryCatch(as.data.frame(summary(fit_w)$coefficients), error = function(e) NULL)
  if (!is.null(ct)) {
    openxlsx::addWorksheet(wb, "Coefficients")
    openxlsx::writeData(wb, "Coefficients", ct)
    utils::write.csv(ct, file.path(down, "Table_WQS_coefficients.csv"))
  }
  openxlsx::saveWorkbook(
    wb, file.path(tab_dir, "Table S14. WQS mixture weights and coefficients.xlsx"), overwrite = TRUE
  )
}
writeLines(
  c(
    "gWQS complementary mixture; aligned with Dong Fig7/S7 full screened panel.",
    paste0("q=4; b=", opt$wqs_boot, "; mix=full screened toxicants n=", length(mix_cols), "; seed=123456"),
    paste0("analytic n=", nrow(dw), "; sum(weights)=", signif(sum(wt$mean_weight), 6))
  ),
  file.path(down, "WQS_weight_note.txt")
)
if (dir.exists(file.path(src_pub, "Tables"))) {
  utils::write.csv(wt, file.path(src_pub, "Tables", "Table. WQS mixture weights.csv"), row.names = FALSE)
}

# —— Figure S7：Dong 风格长条（展示名、蓝渐变）——
.font <- "serif"
n_show <- nrow(wt)
h_in <- max(8.5, 0.14 * n_show + 1.5)
wt$lab <- factor(wt$exposure_name, levels = rev(wt$exposure_name))
# 颜色：权重越高越深
pal <- grDevices::colorRampPalette(c("#DEEBF7", "#9ECAE1", "#4292C6", "#08519C", "#08306B"))(100)
wt$fill <- pal[pmax(1L, pmin(100L, as.integer(round(wt$mean_weight / max(wt$mean_weight) * 99) + 1)))]

p <- ggplot2::ggplot(wt, ggplot2::aes(x = mean_weight, y = lab, fill = mean_weight)) +
  ggplot2::geom_col(width = 0.85) +
  ggplot2::scale_fill_gradientn(
    colours = c("#DEEBF7", "#9ECAE1", "#4292C6", "#2171B5", "#08306B"),
    name = NULL, guide = "none"
  ) +
  ggplot2::scale_x_continuous(expand = ggplot2::expansion(mult = c(0, 0.05))) +
  ggplot2::labs(
    title = "Relative contribution weights of individual environmental toxicants",
    subtitle = sprintf(
      "gWQS; q=4; bootstrap=%d; mixture = full screened panel (n=%d)",
      opt$wqs_boot, n_show
    ),
    x = "Weight", y = NULL
  ) +
  ggplot2::theme_bw(base_size = 9, base_family = .font) +
  ggplot2::theme(
    panel.grid.major.y = ggplot2::element_blank(),
    axis.text.y = ggplot2::element_text(size = 6.5),
    plot.title = ggplot2::element_text(face = "bold", hjust = 0.5, size = 11),
    plot.subtitle = ggplot2::element_text(hjust = 0.5, size = 8)
  )

out_pdf <- file.path(fig_pdf, "Figure S7. WQS weights.pdf")
ggplot2::ggsave(
  out_pdf, p, width = 7.2, height = h_in,
  device = if (capabilities("cairo")) grDevices::cairo_pdf else grDevices::pdf,
  limitsize = FALSE
)
if (dir.exists(file.path(src_pub, "Figures", "pdf"))) {
  ggplot2::ggsave(
    file.path(src_pub, "Figures", "pdf", "Figure S7. WQS weights.pdf"),
    p, width = 7.2, height = h_in,
    device = if (capabilities("cairo")) grDevices::cairo_pdf else grDevices::pdf,
    limitsize = FALSE
  )
}

top5 <- head(wt, 5)
writeLines(c(
  "# Figure S7. WQS weights",
  "",
  "## 图面说明",
  paste0(
    "对齐 Dong Fig7/S7：筛后大面板进 gWQS（非仅 FDR 命中）。",
    sprintf("混合组分 n=%d；bootstrap=%d；q=4。", n_show, opt$wqs_boot),
    "条长=相对权重（和≈1）。顶权：",
    paste(sprintf("%s=%.3f", top5$exposure_name, top5$mean_weight), collapse = "; "),
    "。"
  ),
  "",
  "## 分析上下文",
  paste0("泛癌；分析 n=", nrow(dw), "；协变量同 Model2；正方向优先。")
), file.path(fig_md, "Figure S7. WQS weights.md"))

# Methods 一句
md_path <- file.path(sum_dir, "Methods_statistical_analysis.md")
if (file.exists(md_path)) {
  md <- readLines(md_path, warn = FALSE)
  md <- gsub(
    "WQS: gWQS q=4",
    "WQS: gWQS q=4 on full screened toxicant panel (Dong Fig7/S7; not FDR-hits-only)",
    md, fixed = TRUE
  )
  if (!any(grepl("full screened toxicant panel", md))) {
    md <- c(md, "WQS Fig S7: full screened panel (Dong-aligned), not FDR-hit subset.")
  }
  writeLines(md, md_path)
}

exwas_log("顶5: ", paste(sprintf("%s=%.3f", top5$exposure_name, top5$mean_weight), collapse = "; "))
exwas_log("写完 ", out_pdf)
exwas_log("DONE")
