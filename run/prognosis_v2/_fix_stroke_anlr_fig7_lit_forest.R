#!/usr/bin/env Rscript
# Fig7：对齐用户原文 forestploter 版式
# Subgroup | 森林（绿方块）| HR (95% CI) | P for interaction
# 双库 A MIMIC / B eICU

suppressPackageStartupMessages({
  library(data.table)
  library(grid)
  library(forestploter)
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
dir.create(.fig, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(.out, "Figures", "image_information"), recursive = TRUE, showWarnings = FALSE)

sg <- as.data.frame(fread(file.path(.tab, "Subgroup_rows.csv")))
fmt_p <- function(p) {
  if (!is.finite(p)) return(" ")
  if (p < 0.001) "<0.001" else sprintf("%.3f", p)
}
hr_cell <- function(hr, lo, hi) {
  if (!all(is.finite(c(hr, lo, hi))) || hr < 0.01 || hi > 500 || !is.finite(hi)) {
    return("NE")
  }
  sprintf("%.3f (%.3f-%.3f)", hr, lo, hi)
}

# Subgroup_rows → 原文四列行结构
.to_lit_df <- function(dd) {
  rows <- list()
  est <- lo <- hi <- numeric(0)
  for (i in seq_len(nrow(dd))) {
    r <- dd[i, ]
    if (isTRUE(r$is_header)) {
      pint <- if (!is.null(r$pint_lab) && nzchar(as.character(r$pint_lab))) {
        gsub("^P-int\\s*=\\s*", "", as.character(r$pint_lab))
      } else if (is.finite(r$p_interaction)) {
        fmt_p(r$p_interaction)
      } else {
        " "
      }
      rows[[length(rows) + 1L]] <- data.frame(
        Subgroup = as.character(r$row_lab),
        ` ` = paste(rep(" ", 18L), collapse = ""),
        `HR (95% CI)` = " ",
        `P for interaction` = pint,
        check.names = FALSE, stringsAsFactors = FALSE
      )
      est <- c(est, NA_real_); lo <- c(lo, NA_real_); hi <- c(hi, NA_real_)
    } else {
      lab <- as.character(r$row_lab)
      if (identical(lab, "Overall")) {
        sub_lab <- "Overall"
      } else if (grepl(": ", lab, fixed = TRUE)) {
        parts <- strsplit(lab, ": ", fixed = TRUE)[[1]]
        sub_lab <- paste0("  ", parts[[length(parts)]])
      } else {
        sub_lab <- paste0("  ", lab)
      }
      pe <- as.numeric(r$HR); l <- as.numeric(r$lo); u <- as.numeric(r$hi)
      cell <- hr_cell(pe, l, u)
      if (identical(cell, "NE")) {
        pe <- l <- u <- NA_real_
      }
      rows[[length(rows) + 1L]] <- data.frame(
        Subgroup = sub_lab,
        ` ` = paste(rep(" ", 18L), collapse = ""),
        `HR (95% CI)` = cell,
        `P for interaction` = " ",
        check.names = FALSE, stringsAsFactors = FALSE
      )
      est <- c(est, pe); lo <- c(lo, l); hi <- c(hi, u)
    }
  }
  list(df = do.call(rbind, rows), est = est, lo = lo, hi = hi)
}

.draw_one <- function(dd, title) {
  lit <- .to_lit_df(dd)
  disp <- lit$df
  # 同宽空白列
  disp$` ` <- rep(disp$` `[1L], nrow(disp))

  tm <- forest_theme(
    base_size = 9,
    base_family = "Times",
    refline_gp = gpar(lty = "solid", col = "black", lwd = 1),
    ci_pch = 18,                 # 菱形，贴近原文绿菱/方块
    ci_col = "#2ca02c",
    ci_fill = "#2ca02c",
    ci_alpha = 0.95,
    ci_lty = 1,
    ci_lwd = 1.6,
    ci_Theight = 0.15,
    core = list(bg_params = list(fill = c("#ffffff", "#f7f7f7"), alpha = 0.35)),
    xlab_gp = gpar(fontsize = 8, fontfamily = "Times"),
    ticks_gp = gpar(fontsize = 7, fontfamily = "Times")
  )

  # log 轴；覆盖本库 HR 范围
  finite_lo <- lit$lo[is.finite(lit$lo) & lit$lo > 0]
  finite_hi <- lit$hi[is.finite(lit$hi) & lit$hi > 0]
  finite_est <- lit$est[is.finite(lit$est) & lit$est > 0]
  x_lo <- if (length(finite_lo)) max(0.05, min(finite_lo) * 0.7) else 0.05
  x_hi <- if (length(finite_hi)) min(8, max(c(finite_hi, finite_est), na.rm = TRUE) * 1.15) else 4
  if (!is.finite(x_hi) || x_hi <= x_lo) x_hi <- 4
  ticks <- c(0.2, 0.5, 1, 2, 4)
  ticks <- ticks[ticks >= x_lo & ticks <= x_hi]
  if (length(ticks) < 2L) ticks <- c(0.5, 1, 2)

  p <- forest(
    disp,
    est = lit$est,
    lower = lit$lo,
    upper = lit$hi,
    ci_column = 2L,
    sizes = 0.4,
    ref_line = 1,
    xlim = c(x_lo, x_hi),
    ticks_at = ticks,
    x_trans = "log",
    arrow_lab = c("Lower risk", "Higher risk"),
    theme = tm
  )
  p <- edit_plot(p, part = "header", gp = gpar(fontface = "bold"))
  # 分层标题行加粗
  hdr_i <- which(!grepl("^\\s+", disp$Subgroup) & disp$Subgroup != "Overall")
  if (length(hdr_i)) {
    p <- edit_plot(p, row = hdr_i, gp = gpar(fontface = "bold"))
    # 显著交互高亮（P<0.05）
    for (ri in hdr_i) {
      pv <- suppressWarnings(as.numeric(gsub("[^0-9.]", "", disp$`P for interaction`[ri])))
      lab <- trimws(as.character(disp$`P for interaction`[ri]))
      sig <- grepl("<0.001", lab, fixed = TRUE) || (is.finite(pv) && pv < 0.05)
      if (sig) {
        p <- edit_plot(
          p, row = ri,
          col = which(names(disp) == "P for interaction"),
          gp = gpar(col = "#c0392b", fontface = "bold")
        )
      }
    }
  }
  if (!is.null(p$layout) && "clip" %in% names(p$layout)) p$layout$clip[] <- "off"
  list(plot = p, title = title, n = nrow(disp))
}

db_order <- intersect(c("MIMIC", "eICU"), unique(as.character(sg$Database)))
panels <- list()
for (i in seq_along(db_order)) {
  nm <- db_order[[i]]
  panels[[nm]] <- .draw_one(sg[sg$Database == nm, , drop = FALSE], paste0(LETTERS[i], "  ", nm))
}

fig7 <- file.path(.fig, "Figure 7. Subgroup analyses of ANLR and all-cause mortality.pdf")
cairo_pdf(fig7, width = 10.8, height = 5.4, family = "Times")
grid.newpage()
grid.text(
  "Subgroup analyses of ANLR and all-cause mortality",
  x = 0.5, y = 0.985, gp = gpar(fontsize = 11, fontface = "bold", fontfamily = "Times")
)
n_p <- length(panels)
for (i in seq_along(panels)) {
  nm <- names(panels)[i]
  pushViewport(viewport(
    x = (i - 0.5) / n_p, y = 0.48, width = 0.985 / n_p, height = 0.92, just = "centre"
  ))
  grid.text(panels[[nm]]$title, x = 0.02, y = 0.99, just = c("left", "top"),
            gp = gpar(fontsize = 10, fontface = "bold", fontfamily = "Times"))
  pushViewport(viewport(y = 0.46, height = 0.90, just = "centre"))
  grid.draw(panels[[nm]]$plot)
  popViewport()
  popViewport()
}
dev.off()
message("Fig7 lit-style OK -> ", fig7)
pdfinfo <- tryCatch(system2("pdfinfo", shQuote(fig7), stdout = TRUE), error = function(e) character())
message(paste(pdfinfo[grepl("Pages|Page size", pdfinfo)], collapse = " | "))

.pint_line <- function(db) {
  dd <- sg[sg$Database == db & sg$is_header %in% TRUE, , drop = FALSE]
  if (!nrow(dd)) return("")
  paste(sprintf("%s %s", dd$row_lab, dd$pint_lab), collapse = "; ")
}
overall_m <- sg[sg$Database == "MIMIC" & sg$row_lab == "Overall", ][1, ]
overall_e <- sg[sg$Database == "eICU" & sg$row_lab == "Overall", ][1, ]
writeLines(c(
  "# Figure 7. Subgroup analyses of ANLR and all-cause mortality",
  "",
  "## 图面说明",
  "双库并列（A MIMIC / B eICU）forestploter 亚组森林图，版式对齐原文：",
  "Subgroup | 森林（绿菱形）| HR (95% CI) | P for interaction。",
  "对比为 Q4 vs Q1（中间分位并为 Middle，全样本估计）；层内未调整。",
  "分层：Overall、Age（<65 / ≥65）、Sex、Hypertension、Diabetes、SOFA（<6 / ≥6）。",
  "标题行仅显示 P for interaction；水平行显示 HR 点与 CI。不可估层显示 NE。",
  "",
  "### 图上标注",
  sprintf(
    "- A MIMIC Overall: HR=%.3f (%.3f-%.3f), P%s, N=%s",
    overall_m$HR, overall_m$lo, overall_m$hi,
    if (overall_m$p < 0.001) "<0.001" else sprintf("=%.3f", overall_m$p),
    format(overall_m$N, big.mark = ",")
  ),
  sprintf(
    "- B eICU Overall: HR=%.3f (%.3f-%.3f), P%s, N=%s",
    overall_e$HR, overall_e$lo, overall_e$hi,
    if (overall_e$p < 0.001) "<0.001" else sprintf("=%.3f", overall_e$p),
    format(overall_e$N, big.mark = ",")
  ),
  paste0("- MIMIC P for interaction: ", .pint_line("MIMIC")),
  paste0("- eICU P for interaction: ", .pint_line("eICU")),
  "- eICU Diabetes Yes 层不可估 → NE。",
  "",
  "## 分析上下文",
  "- 暴露: ANLR (Q4 vs Q1)",
  "- 结局: 28-day all-cause mortality",
  "- 样本量: MIMIC n=862; eICU n=1,860",
  "- 数据库: MIMIC + eICU",
  "- Grouping: quartile (Q4 vs Q1)",
  "- 是否拼图: 是（左右分库）"
), file.path(.out, "Figures", "image_information",
             "Figure 7. Subgroup analyses of ANLR and all-cause mortality.md"))

pub_figure_ensure_formats(
  file.path(.out, "Figures"),
  config = list(pub_figures = list(export_png = FALSE, export_tiff = FALSE, max_edge_in = 11))
)
st <- pub_figure_formats_status(
  file.path(.out, "Figures"),
  config = list(pub_figures = list(export_png = FALSE, export_tiff = FALSE, max_edge_in = 11))
)
message("formats ok=", isTRUE(st$ok),
        " bad_geom=", paste(st$bad_pdf_geometry %||% character(), collapse = ","))
message("done")
