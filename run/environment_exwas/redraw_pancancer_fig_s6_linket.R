#!/usr/bin/env Rscript
# Figure S6：对齐 Dong Supp Fig6 — 毒物三角相关热图 + Smoke→各毒物 Mantel/相关连线（linkET）
# 替换原条形图 Pearson-r 版。
#
#   Rscript run/environment_exwas/redraw_pancancer_fig_s6_linket.R
#
opt <- list(
  root = "/mnt/g/02block_result/58_cancer/environment_41380607",
  data_dir = "/mnt/g/02block_result/58_cancer/environment_41380607/data",
  min_age = 20L
)
ca <- commandArgs(trailingOnly = FALSE)
f <- grep("^--file=", ca, value = TRUE)
repo <- if (length(f)) {
  normalizePath(file.path(dirname(sub("^--file=", "", f[[1]])), "..", ".."), winslash = "/")
} else getwd()
setwd(repo)
source(file.path(repo, "R/environment_exwas_core.R"))
source(file.path(repo, "R/environment_exwas_aligned.R"))
source(file.path(repo, "R/environment_exwas_toxicant.R"))

if (!requireNamespace("linkET", quietly = TRUE)) stop("需要 linkET", call. = FALSE)
if (!requireNamespace("ggplot2", quietly = TRUE)) stop("需要 ggplot2", call. = FALSE)
if (!requireNamespace("dplyr", quietly = TRUE)) stop("需要 dplyr", call. = FALSE)

suppressPackageStartupMessages({
  library(linkET)
  library(ggplot2)
  library(dplyr)
})

root <- opt$root
sum_dir <- file.path(root, "summary_results")
fig_pdf <- file.path(sum_dir, "Figures", "pdf")
fig_md <- file.path(sum_dir, "Figures", "image_information")
tab_dir <- file.path(sum_dir, "Tables")
src_pub <- file.path(root, "Output_pancancer_paperflow_UCR_WTSA_full_pub")
dir.create(fig_pdf, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_md, recursive = TRUE, showWarnings = FALSE)
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

exwas_log("==== redraw Fig S6 linkET (Dong style) ====")

built <- exwas_tox_build_cancer_table("pancancer", opt$data_dir, min_age = opt$min_age)
d0 <- built$data
ucr0 <- exwas_to_num(d0$URXUCR)
d0 <- d0[is.finite(ucr0) & ucr0 > 0, , drop = FALSE]
ww0 <- exwas_to_num(d0$WTSA2YR)
d0 <- d0[is.finite(ww0) & ww0 > 0, , drop = FALSE]
tox <- intersect(built$tox_cols, names(d0))
d1 <- exwas_tox_creatinine_adjust(d0, tox, creat_col = "URXUCR")$data
scr <- exwas_tox_screen_transform(d1, tox)
person <- exwas_tox_drop_person_missing(
  scr$data, scr$keep, max_frac = 1 / 3, cycle_col = "cycle",
  raw_from_model = sub("_(ln|bin)$", "", scr$keep)
)
df <- person$data
if (!"Smoke" %in% names(df)) stop("分析表无 Smoke 列", call. = FALSE)

lab_map <- stats::setNames(built$code$Exposure, built$code$Labels)
fam_map <- stats::setNames(built$code$Family, built$code$Labels)
disp_of <- function(raw) {
  x <- unname(lab_map[raw])
  ifelse(is.na(x) | !nzchar(x), raw, x)
}

exps0 <- scr$keep
raws0 <- sub("_(ln|bin)$", "", exps0)
ord <- order(fam_map[raws0], disp_of(raws0), na.last = TRUE)
exps0 <- exps0[ord]
raws0 <- raws0[ord]

# Smoke 数值编码
sm <- df$Smoke
if (is.factor(sm) || is.character(sm)) {
  smc <- as.character(sm)
  lev <- c("Never", "Former", "Current", "never", "former", "current",
           "Never smoker", "Former smoker", "Current smoker",
           "从不", "既往", "现在", "0", "1", "2")
  smn0 <- suppressWarnings(as.numeric(factor(
    smc, levels = unique(c(lev[lev %in% smc], sort(unique(smc))))
  )))
  if (all(is.na(smn0))) smn0 <- as.numeric(factor(smc))
} else {
  smn0 <- exwas_to_num(sm)
}

# 毒物数值矩阵 + 展示名；剔稀疏列
Xraw <- df[, exps0, drop = FALSE]
for (j in seq_along(exps0)) Xraw[[j]] <- exwas_to_num(Xraw[[j]])
n_fin <- vapply(Xraw, function(z) sum(is.finite(z)), integer(1))
keep_idx <- which(n_fin >= 80L)
if (length(keep_idx) < 5L) stop("可用毒物列过少，无法画 S6", call. = FALSE)
exps <- exps0[keep_idx]
raws <- raws0[keep_idx]
labs <- make.unique(as.character(disp_of(raws)), sep = " ")
names(Xraw) <- labs
Xm <- Xraw[, labs, drop = FALSE]

ok_row <- is.finite(smn0) & rowSums(is.finite(as.matrix(Xm))) > 0
Xm <- Xm[ok_row, , drop = FALSE]
smn <- smn0[ok_row]
exwas_log("S6 n=", nrow(Xm), " p toxicants=", ncol(Xm))

# —— 1) 毒物相关矩阵（Pearson；stats::cor + as_correlate，避免稀疏 pairwise 报错）——
R <- suppressWarnings(stats::cor(as.matrix(Xm), use = "pairwise.complete.obs"))
nmat <- crossprod(is.finite(as.matrix(Xm)))
R[!is.finite(R) | nmat < 30] <- NA_real_
diag(R) <- 1
corr <- as_correlate(R, is_corr = TRUE)
exwas_log("相关矩阵维数=", nrow(R), "；有限相关对数=", sum(is.finite(R) & upper.tri(R)))

# —— 2) Smoke↔各毒物连线：Pearson r/P（图注「Correlation」；版式同 Dong/linkET Mantel 连线）——
# 不做 63×Mantel 置换（极慢且单列 Mantel≈相关）；图例仍用 p / |r| 分档着色线宽。
mantel_note <- "pearson_linkET_style"
rows <- lapply(names(Xm), function(nm) {
  xx <- Xm[[nm]]
  hit <- is.finite(xx) & is.finite(smn)
  if (sum(hit) < 50L) {
    return(data.frame(spec = nm, env = "Smoke", r = NA_real_, p = NA_real_,
                      stringsAsFactors = FALSE))
  }
  ct <- suppressWarnings(stats::cor.test(xx[hit], smn[hit], method = "pearson"))
  data.frame(
    spec = nm, env = "Smoke",
    r = unname(ct$estimate), p = ct$p.value,
    stringsAsFactors = FALSE
  )
})
mantel_df <- do.call(rbind, rows)
# linkET geom_couple 默认 data[[1]]=from（外侧节点）、data[[2]]=to（热图节点）
# Dong 图：外侧=Smoke，终点=各毒物 → 列顺序必须是 env, spec（或 aes(from=env, to=spec)）
md <- data.frame(
  env = "Smoke",
  spec = mantel_df$spec,
  r = mantel_df$r,
  p = mantel_df$p,
  stringsAsFactors = FALSE
)
md <- md[is.finite(md$r) & is.finite(md$p), , drop = FALSE]
md$pd.r <- abs(md$r)
md$p_bin <- cut(
  md$p,
  breaks = c(-Inf, 0.001, 0.01, 0.05, Inf),
  labels = c("< 0.001", "0.001 - 0.01", "0.01 - 0.05", ">= 0.05")
)
md$r_bin <- cut(
  md$pd.r,
  breaks = c(-Inf, 0.2, 0.4, Inf),
  labels = c("< 0.2", "0.2 - 0.4", ">= 0.4")
)
class(md) <- c("mantel_tbl", "data.frame")

# 落盘数值表（可复核）
out_tab <- data.frame(
  exposure = exps[match(md$spec, labs)],
  exposure_name = md$spec,
  family = unname(fam_map[raws[match(md$spec, labs)]]),
  r_smoke = md$r,
  p_smoke = md$p,
  abs_r = md$pd.r,
  p_bin = as.character(md$p_bin),
  method = mantel_note,
  n = nrow(Xm),
  stringsAsFactors = FALSE
)
utils::write.csv(out_tab, file.path(tab_dir, "Table_S_smoke_toxicant_correlation.csv"), row.names = FALSE)
if (dir.exists(file.path(src_pub, "Tables"))) {
  utils::write.csv(out_tab, file.path(src_pub, "Tables", "Table_S_smoke_toxicant_correlation.csv"), row.names = FALSE)
}

# —— 3) 画图 ——
.set_font <- function() {
  if (capabilities("cairo")) grDevices::cairo_pdf else grDevices::pdf
}
.font <- "serif"

# linkET 默认风格接近 Dong：上三角方块 + 左侧 Smoke 连线
p <- qcorrplot(corr, type = "upper", diag = FALSE) +
  geom_square() +
  scale_fill_gradientn(
    colours = c("#2166AC", "#67A9CF", "#D1E5F0", "#FDDBC7", "#EF8A62", "#B2182B"),
    limits = c(-1, 1),
    name = "Correlation\n(Pearson)"
  ) +
  geom_couple(
    data = md,
    # from=Smoke（外侧），to=毒物（热图对角线节点）
    aes(
      from = env,
      to = spec,
      colour = p_bin,
      size = r_bin
    ),
    curvature = nice_curvature(),
    label.size = 4.2,
    label.colour = "black",
    label.fontface = 2
  ) +
  scale_size_manual(
    values = c("< 0.2" = 0.45, "0.2 - 0.4" = 0.95, ">= 0.4" = 1.6),
    name = "|r|"
  ) +
  scale_colour_manual(
    values = c(
      "< 0.001" = "#B2182B",
      "0.001 - 0.01" = "#EF8A62",
      "0.01 - 0.05" = "#F4A582",
      ">= 0.05" = "grey70"
    ),
    name = "P"
  ) +
  guides(
    fill = guide_colorbar(order = 1),
    size = guide_legend(order = 2, override.aes = list(colour = "grey30")),
    colour = guide_legend(order = 3)
  ) +
  theme_hy() +
  theme(
    text = element_text(family = .font),
    axis.text = element_text(size = 5.5, family = .font),
    legend.text = element_text(size = 8, family = .font),
    legend.title = element_text(size = 9, family = .font),
    plot.title = element_text(size = 11, face = "bold", family = .font, hjust = 0.5)
  ) +
  labs(title = "Correlation between smoking status and environmental toxicants")

out_pdf <- file.path(fig_pdf, "Figure S6. Smoke toxicant correlation.pdf")
ggsave(out_pdf, p, width = 11.5, height = 9.5, device = .set_font(), limitsize = FALSE)
if (dir.exists(file.path(src_pub, "Figures", "pdf"))) {
  ggsave(file.path(src_pub, "Figures", "pdf", "Figure S6. Smoke toxicant correlation.pdf"),
         p, width = 11.5, height = 9.5, device = .set_font(), limitsize = FALSE)
}

n_sig <- sum(md$p < 0.05, na.rm = TRUE)
writeLines(c(
  "# Figure S6. Smoke toxicant correlation",
  "",
  "## 图面说明",
  paste0(
    "对齐 Dong Supp Fig6：毒物两两 Pearson 相关上三角热图（方块），",
    "左侧 Smoke 以连线接到各毒物（线色=P，线宽=|r|）。",
    sprintf("方法=%s；与 Smoke 名义显著（P<0.05）毒物数=%d / %d。", mantel_note, n_sig, nrow(md)),
    "主 ExWAS 不纳入 Smoke；本图说明吸烟与毒物共线，支撑 S8/S9 敏感性。"
  ),
  "",
  "## 分析上下文",
  paste0("泛癌；N=", nrow(Xm), "（Smoke 非缺失且至少一毒物可得）；尿肌酐调整后筛选暴露。")
), file.path(fig_md, "Figure S6. Smoke toxicant correlation.md"))

exwas_log("写完 ", out_pdf)
exwas_log("显著连线 P<0.05: ", n_sig, "/", nrow(md), " method=", mantel_note)
exwas_log("DONE")
