#!/usr/bin/env Rscript
# Fig3：Follow-up (days)；Fig4：Hip 样式 RCS（HR 锚定 mean/0 SD）

suppressPackageStartupMessages({
  library(data.table)
  library(survival)
  library(ggplot2)
  library(splines)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.engine <- if (dir.exists("/mnt/e/01block/01Block-new-Final")) {
  "/mnt/e/01block/01Block-new-Final"
} else "E:/01block/01Block-new-Final"
setwd(.engine)
source(file.path(.engine, "run/prognosis_v2/stroke_anlr_env.R"), local = FALSE)
source(file.path(.engine, "R/utils.R"), local = FALSE)
source(file.path(.engine, "R/pub_figure_export.R"), local = FALSE)

.proj <- {
  cands <- c(
    "/mnt/g/02block_result/11_ischemic stroke/prognosis_v2_41904528",
    "G:/02block_result/11_ischemic stroke/prognosis_v2_41904528"
  )
  cands[dir.exists(cands)][1L]
}
.out <- stroke_anlr_out(.proj)
.days <- stroke_anlr_days()
.day_lab <- stroke_anlr_day_lab()
.endpoint <- stroke_anlr_endpoint_phrase()
.tab <- file.path(.out, "Tables")
.fig <- file.path(.out, "Figures", "pdf")
IDX <- "ANLR"

dbs <- readRDS(file.path(.tab, "imputed_dbs.rds"))
.lock <- readRDS(file.path(.tab, "quantile_scheme_resolved.rds"))
m3_by <- readRDS(file.path(.tab, "Model3_by_database.rds"))
m3_shared <- Reduce(intersect, m3_by)
fmt_p <- function(p) {
  if (!is.finite(p)) return("NA")
  if (p < 0.001) "<0.001" else sprintf("%.3f", p)
}

# ---- Fig3：天数横轴 ----
if (!requireNamespace("survminer", quietly = TRUE)) stop("need survminer")
.qsc_meta <- .lock$meta
.km_one <- function(d, qv, title) {
  d <- as.data.frame(d)
  # 28 天终点：用 futime（天），禁止 years 轴
  d$time <- if ("futime" %in% names(d)) as.numeric(d$futime) else as.numeric(d$futime_years) * 365.25
  d$event <- as.integer(d$fustatus)
  d <- d[!is.na(d[[qv]]) & is.finite(d$time) & d$time > 0 & !is.na(d$event), ]
  labs <- .qsc_meta$labels
  d$sg <- factor(as.character(d[[qv]]), levels = labs)
  d <- d[!is.na(d$sg), ]
  fit <- survfit(Surv(time, event) ~ sg, data = d)
  sd <- survdiff(Surv(time, event) ~ sg, data = d)
  p <- pchisq(sd$chisq, length(sd$n) - 1, lower.tail = FALSE)
  plab <- if (p < 0.001) "Log-rank P < 0.001" else sprintf("Log-rank P = %.3f", p)
  pal <- c("#2ca02c", "#ff7f0e", "#9467bd", "#d62728", "#1f77b4")[seq_along(labs)]
  tmax <- max(28, ceiling(max(d$time, na.rm = TRUE)))
  g <- survminer::ggsurvplot(
    fit, data = d, fun = "event", conf.int = FALSE, censor = TRUE, censor.size = 1.6,
    risk.table = TRUE, risk.table.height = 0.28, risk.table.title = "Number at risk",
    pval = FALSE, palette = pal,
    legend = "top", legend.title = .qsc_meta$legend_title %||% .lock$scheme,
    legend.labs = labs,
    xlab = "Follow-up (days)", ylab = "Cumulative incidence of all-cause mortality",
    title = title, break.time.by = 7,
    xlim = c(0, tmax),
    ggtheme = theme_classic(base_size = 11), fontsize = 3.0
  )
  g$plot <- g$plot + annotate("text", x = 0, y = Inf, label = plab, hjust = 0, vjust = 1.4, size = 3.4)
  g
}

km_plots <- lapply(names(dbs), function(nm) {
  .km_one(dbs[[nm]], paste0(IDX, "_Group"), paste0(nm, " — ANLR"))
})
names(km_plots) <- names(dbs)

fig3 <- file.path(.fig, "Figure 3. Cumulative incidence of all-cause mortality by ANLR.pdf")
if (file.exists(fig3)) file.remove(fig3)
km_page <- survminer::arrange_ggsurvplots(km_plots, print = FALSE, ncol = 1, nrow = 2, title = NA)
cairo_pdf(fig3, width = 7.4, height = 10.5, family = "Times")
print(km_page)
dev.off()
message("Fig3 OK (days) -> ", fig3)

# Fig3 image_information；Fig4–7 由专用 Hip 对齐脚本统一重画
.write_md <- function(stem, body) {
  writeLines(body, file.path(.out, "Figures", "image_information", paste0(stem, ".md")))
}
.write_md(
  "Figure 3. Cumulative incidence of all-cause mortality by ANLR",
  c(
    "# Figure 3. Cumulative incidence of all-cause mortality by ANLR",
    "",
    "## 图面说明",
    paste0("双库累积发病率（1−KM），分组=", .lock$scheme, "（", paste(.qsc_meta$labels, collapse = "/"), "）。"),
    "含 Number at risk；图内标注 Log-rank P。横轴 Follow-up (days)（28 天终点）；纵轴 Cumulative incidence of all-cause mortality。",
    "",
    "## 分析上下文",
    "- 暴露: ANLR",
    "- 结局: 28-day all-cause mortality",
    paste0("- Grouping: ", .lock$scheme),
    paste0("- 样本量: MIMIC N=", nrow(dbs$MIMIC), "；eICU N=", nrow(dbs$eICU)),
    "- 数据库: MIMIC + eICU",
    "- 是否拼图: 是（上下分库）"
  )
)

cfg <- list(pub_figures = list(export_png = FALSE, export_tiff = FALSE, max_edge_in = 11))
pub_figure_ensure_formats(file.path(.out, "Figures"), config = cfg)
message("Fig3 done; Fig4-7 via _fix_stroke_anlr_fig4_7_hip.R")
sys.source(
  file.path(.engine, "run/prognosis_v2/_fix_stroke_anlr_fig4_7_hip.R"),
  envir = new.env(parent = globalenv())
)
message("done")
