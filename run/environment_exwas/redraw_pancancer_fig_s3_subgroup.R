#!/usr/bin/env Rscript
# Figure S3：对齐 Dong Supp Fig3 版式（forestploter 表列 + 绿方点 + 蓝 CI + p for interaction）
# 癌症适应：保留人口学/生活方式亚组；不含漱口水/牙线/牙医（牙周病特异）
#
#   Rscript redraw_pancancer_fig_s3_subgroup.R
#
ROOT <- "/mnt/e/01block/01Block-new-Final"
BASE <- "/mnt/g/02block_result/58_cancer/environment_41380607"
source(file.path(ROOT, "R/environment_exwas_core.R"))
source(file.path(ROOT, "R/environment_exwas_aligned.R"))
source(file.path(ROOT, "R/environment_exwas_toxicant.R"))
source(file.path(ROOT, "R/environment_exwas_toxicant_downstream.R"))

suppressPackageStartupMessages({
  library(grid)
  library(forestploter)
})
if (!requireNamespace("survey", quietly = TRUE)) stop("need survey", call. = FALSE)

fig_pdf <- file.path(BASE, "summary_results/Figures/pdf")
fig_md <- file.path(BASE, "summary_results/Figures/image_information")
tab_dir <- file.path(BASE, "summary_results/Tables")
out_ds <- file.path(BASE, "Output_pancancer_paperflow_UCR_WTSA_full_pub/_downstream")
dir.create(fig_pdf, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_md, recursive = TRUE, showWarnings = FALSE)

fmt_p <- function(p) {
  if (!is.finite(p)) return("")
  if (p < 0.001) return("<0.001")
  sprintf("%.3f", p)
}
fmt_or <- function(or, lo, hi) {
  if (!all(is.finite(c(or, lo, hi)))) return("")
  sprintf("%.3f (%.3f, %.3f)", or, lo, hi)
}

message("[S3] build analytic + reuse ERS")
built <- exwas_tox_build_cancer_table("pancancer", file.path(BASE, "data"), 20L)
d0 <- built$data
d0 <- d0[is.finite(exwas_to_num(d0$URXUCR)) & exwas_to_num(d0$URXUCR) > 0, ]
d0 <- d0[is.finite(exwas_to_num(d0$WTSA2YR)) & exwas_to_num(d0$WTSA2YR) > 0, ]
tox <- intersect(built$tox_cols, names(d0))
d1 <- exwas_tox_creatinine_adjust(d0, tox)$data
scr <- exwas_tox_screen_transform(d1, tox)
person <- exwas_tox_drop_person_missing(
  scr$data, scr$keep, 1 / 3, "cycle", sub("_(ln|bin)$", "", scr$keep)
)
df <- person$data
dag_m2 <- intersect(
  c("Gender", "Race", "Education", "Marital_Status",
    "PIR_cat", "BMI_cat", "Alcohol_drinking", "eGFR"),
  names(df)
)
df <- exwas_aligned_as_model_frame(df, dag_m2)
if (!"SDMVSTRA_cyc" %in% names(df) && "SDMVSTRA" %in% names(df)) {
  df$SDMVSTRA_cyc <- df$SDMVSTRA
}
# 与 Fig4 定稿 Model2 一致（已落盘路径）；若文件缺失则重筛
m2_path <- file.path(out_ds, "Model2_selection_path.txt")
covars_m2 <- c("Gender", "Race", "PIR_cat", "Alcohol_drinking", "eGFR")
if (file.exists(m2_path)) {
  lines <- readLines(m2_path, warn = FALSE)
  sw_line <- lines[grepl("^stepwise=", lines)]
  if (length(sw_line)) {
    covars_m2 <- intersect(strsplit(sub("^stepwise=", "", sw_line[[1]]), ",")[[1]], names(df))
  }
}
covars_m2 <- intersect(covars_m2, names(df))
message("[S3] Model2=", paste(covars_m2, collapse = "+"))

ers_rds <- file.path(out_ds, "ERS_adaptive_enet_fit.rds")
if (!file.exists(ers_rds)) stop("缺少 ERS rds: ", ers_rds, call. = FALSE)
ers_fit <- readRDS(ers_rds)
df$ERS <- exwas_tox_score_ers(
  df, ers_fit$beta,
  center = ers_fit$center, scale = ers_fit$scale, is_binary = ers_fit$is_binary
)
assoc <- exwas_tox_ers_assoc_table(df, covars_m2, weight_col = "WTSA2YR")
use <- assoc$data
if (!"SDMVSTRA_cyc" %in% names(use) && "SDMVSTRA" %in% names(use)) {
  use$SDMVSTRA_cyc <- use$SDMVSTRA
}
sw <- list(survey_weight = "WTSA2YR", survey_psu = "SDMVPSU", survey_strata = "SDMVSTRA_cyc")

# ---- 亚组定义（展示名对齐原文；水平按本队列可得分类）----
.mk_chr <- function(x) {
  x <- as.character(x)
  x[is.na(x) | !nzchar(x)] <- NA_character_
  x
}
use$sg_sex <- .mk_chr(use$Gender)
age_cut <- 65L
use$sg_age <- ifelse(
  exwas_to_num(use$Age) >= age_cut,
  paste0("\u2265", age_cut),
  paste0("<", age_cut)
)
if ("Race" %in% names(use)) {
  rr <- .mk_chr(use$Race)
  use$sg_race <- ifelse(
    rr %in% c("Other Race", "Other Hispanic"), "Other", rr
  )
  use$sg_race <- factor(
    use$sg_race,
    levels = c("Non-Hispanic White", "Non-Hispanic Black", "Mexican American", "Other")
  )
}
if ("Education" %in% names(use)) {
  ed <- .mk_chr(use$Education)
  use$sg_edu <- ifelse(
    grepl("Higher|college|College", ed, ignore.case = TRUE),
    "Higher education",
    "Non-higher education"
  )
}
if ("Marital_Status" %in% names(use)) {
  ms <- .mk_chr(use$Marital_Status)
  use$sg_marital <- ifelse(grepl("Married", ms, ignore.case = TRUE), "Married", "Unmarried")
}
if ("PIR_cat" %in% names(use)) {
  pr <- .mk_chr(use$PIR_cat)
  pr <- gsub("\u2013", "-", pr)
  pr <- gsub("^1\\.3-3\\.5$", "1.3\u20133.5", pr)
  pr <- gsub("^<\\s*1\\.3$", "<1.3", pr)
  pr <- gsub("^>\\s*3\\.5$", ">3.5", pr)
  use$sg_pir <- factor(pr, levels = c(">3.5", "1.3\u20133.5", "<1.3"))
}
if ("BMI_cat" %in% names(use)) {
  bm <- .mk_chr(use$BMI_cat)
  use$sg_bmi <- ifelse(
    grepl("Overweight|Obese", bm, ignore.case = TRUE),
    "Overweight/Obese",
    "Normal"
  )
}
if ("Alcohol_drinking" %in% names(use)) {
  al <- .mk_chr(use$Alcohol_drinking)
  use$sg_alc <- ifelse(grepl("^Yes", al, ignore.case = TRUE), "Yes", "No")
}

sg_defs <- list(
  list(title = "Sex", col = "sg_sex",
       levels = c("Female", "Male"), drop = "Gender"),
  list(title = "Age (years)", col = "sg_age",
       levels = c(paste0("\u2265", age_cut), paste0("<", age_cut)), drop = "Age"),
  list(title = "Ethnicity", col = "sg_race",
       levels = c("Non-Hispanic White", "Non-Hispanic Black", "Mexican American", "Other"),
       drop = "Race"),
  list(title = "Education", col = "sg_edu",
       levels = c("Higher education", "Non-higher education"), drop = "Education"),
  list(title = "Marital", col = "sg_marital",
       levels = c("Married", "Unmarried"), drop = "Marital_Status"),
  list(title = "Poverty", col = "sg_pir",
       levels = c(">3.5", "1.3\u20133.5", "<1.3"), drop = "PIR_cat"),
  list(title = "BMI (kg/m\u00b2)", col = "sg_bmi",
       levels = c("Overweight/Obese", "Normal"), drop = "BMI_cat"),
  list(title = "Alcohol use", col = "sg_alc",
       levels = c("Yes", "No"), drop = "Alcohol_drinking")
)
sg_defs <- Filter(function(z) z$col %in% names(use), sg_defs)

.sg_fit <- function(sub, drop_vars = character(0)) {
  cv <- setdiff(covars_m2, drop_vars)
  cv_ok <- character(0)
  for (v in cv) {
    if (!v %in% names(sub)) next
    nlev <- length(unique(as.character(sub[[v]][!is.na(sub[[v]])])))
    if (nlev >= 2L) cv_ok <- c(cv_ok, v)
  }
  if (exwas_has_survey(sub, sw)) {
    est <- tryCatch(
      .exwas_tox_svy_or_row(sub, "DN", "ERS_IQR", cv_ok, sw),
      error = function(e) NULL
    )
    if (!is.null(est)) {
      return(list(OR = est$OR, lo = est$lo, hi = est$hi, p = est$p, n = nrow(sub)))
    }
  }
  one <- exwas_fit_one(sub, "DN", "ERS_IQR", cv_ok)
  list(OR = one$OR, lo = one$lo, hi = one$hi, p = one$p, n = nrow(sub))
}

.sg_pint <- function(col, drop_vars = character(0)) {
  # Wald / LRT for ERS_IQR × subgroup interaction on full sample
  d <- use[!is.na(use[[col]]) & is.finite(use$ERS_IQR) & !is.na(use$DN), , drop = FALSE]
  if (nrow(d) < 200L) return(NA_real_)
  d$sg <- factor(as.character(d[[col]]))
  if (nlevels(d$sg) < 2L) return(NA_real_)
  cv <- setdiff(covars_m2, c(drop_vars, col))
  cv_ok <- character(0)
  for (v in cv) {
    if (!v %in% names(d)) next
    nlev <- length(unique(as.character(d[[v]][!is.na(d[[v]])])))
    if (nlev >= 2L) cv_ok <- c(cv_ok, v)
  }
  rhs0 <- paste(c("ERS_IQR", "sg", cv_ok), collapse = " + ")
  rhs1 <- paste(c("ERS_IQR * sg", cv_ok), collapse = " + ")
  f0 <- stats::as.formula(paste("DN ~", rhs0))
  f1 <- stats::as.formula(paste("DN ~", rhs1))
  if (exwas_has_survey(d, sw)) {
    des <- tryCatch(exwas_design(d, sw), error = function(e) NULL)
    if (!is.null(des)) {
      m0 <- tryCatch(
        survey::svyglm(f0, design = des, family = quasibinomial()),
        error = function(e) NULL
      )
      m1 <- tryCatch(
        survey::svyglm(f1, design = des, family = quasibinomial()),
        error = function(e) NULL
      )
      if (!is.null(m0) && !is.null(m1)) {
        a <- tryCatch(anova(m0, m1, method = "LRT"), error = function(e) NULL)
        if (!is.null(a)) {
          pn <- names(a)
          pk <- pn[grepl("p|Pr", pn, ignore.case = TRUE)][1]
          if (!is.na(pk)) return(as.numeric(a[[pk]][2]))
          # survey anova often returns p in last column
          return(as.numeric(a[nrow(a), ncol(a)]))
        }
      }
    }
  }
  m0 <- tryCatch(stats::glm(f0, data = d, family = binomial()), error = function(e) NULL)
  m1 <- tryCatch(stats::glm(f1, data = d, family = binomial()), error = function(e) NULL)
  if (is.null(m0) || is.null(m1)) return(NA_real_)
  a <- tryCatch(anova(m0, m1, test = "Chisq"), error = function(e) NULL)
  if (is.null(a)) return(NA_real_)
  as.numeric(a$`Pr(>Chi)`[2])
}

message("[S3] fit strata + interactions")
rows <- list()
raw_rows <- list()
for (sg in sg_defs) {
  pint <- .sg_pint(sg$col, sg$drop)
  rows[[length(rows) + 1L]] <- data.frame(
    Character = sg$title,
    `OR (95% CI)` = "",
    p = "",
    `p for interaction` = fmt_p(pint),
    est = NA_real_, lo = NA_real_, hi = NA_real_,
    is_header = TRUE,
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  raw_rows[[length(raw_rows) + 1L]] <- data.frame(
    character = sg$title, level = NA_character_,
    OR = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_,
    p_interaction = pint, n = NA_integer_, is_header = TRUE,
    stringsAsFactors = FALSE
  )
  for (lv in sg$levels) {
    idx <- which(as.character(use[[sg$col]]) == lv)
    if (length(idx) < 80L) next
    est <- .sg_fit(use[idx, , drop = FALSE], sg$drop)
    rows[[length(rows) + 1L]] <- data.frame(
      Character = paste0("  ", lv),
      `OR (95% CI)` = fmt_or(est$OR, est$lo, est$hi),
      p = fmt_p(est$p),
      `p for interaction` = "",
      est = est$OR, lo = est$lo, hi = est$hi,
      is_header = FALSE,
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
    raw_rows[[length(raw_rows) + 1L]] <- data.frame(
      character = sg$title, level = lv,
      OR = est$OR, lo = est$lo, hi = est$hi, p = est$p,
      p_interaction = pint, n = est$n, is_header = FALSE,
      stringsAsFactors = FALSE
    )
  }
}
dt <- do.call(rbind, rows)
raw <- do.call(rbind, raw_rows)
utils::write.csv(raw, file.path(out_ds, "Table_ERS_subgroup_adjusted.csv"), row.names = FALSE)
utils::write.csv(
  raw,
  file.path(tab_dir, "Table. ERS subgroup associations.csv"),
  row.names = FALSE
)

# ---- forestploter（原文：绿方块 + 蓝 CI；列 Character / OR / p / p for interaction）----
disp <- dt[, c("Character", "OR (95% CI)", "p", "p for interaction")]
disp$` ` <- paste(rep(" ", 24), collapse = "")
est <- dt$est
lo <- dt$lo
hi <- dt$hi
# 轴：对齐原文约 0.5–5
xlim <- c(0.5, 5)
ticks <- c(0.5, 1, 2, 3, 4, 5)
lo_draw <- pmax(lo, xlim[1] * 0.999)
hi_draw <- pmin(hi, xlim[2] * 1.001)
lo_draw[!is.finite(lo)] <- NA_real_
hi_draw[!is.finite(hi)] <- NA_real_
est[!is.finite(est)] <- NA_real_

tm <- forestploter::forest_theme(
  base_size = 10,
  refline_gp = grid::gpar(lty = "dashed", col = "grey40", lwd = 1),
  ci_pch = 15,
  ci_col = "#2E75B6",
  ci_fill = "#70AD47",
  ci_alpha = 1,
  ci_lty = 1,
  ci_lwd = 1.8,
  ci_Theight = 0.18,
  xaxis_gp = grid::gpar(fontsize = 9, fontfamily = "serif"),
  core = list(
    fg_params = list(hjust = 0, x = 0.01, fontfamily = "serif", fontsize = 9),
    bg_params = list(fill = c("#FFFFFF", "#F2F2F2"))
  ),
  colhead = list(
    fg_params = list(hjust = 0, x = 0.01, fontface = "bold", fontfamily = "serif", fontsize = 10)
  )
)

p <- forestploter::forest(
  disp,
  est = est,
  lower = lo_draw,
  upper = hi_draw,
  sizes = 0.35,
  ci_column = which(names(disp) == " ")[1L],
  ref_line = 1,
  xlim = xlim,
  ticks_at = ticks,
  x_trans = "log",
  theme = tm
)
p <- forestploter::edit_plot(p, part = "header", gp = grid::gpar(fontface = "bold"))
hdr <- which(dt$is_header)
if (length(hdr)) {
  p <- forestploter::edit_plot(p, row = hdr, gp = grid::gpar(fontface = "bold"))
}

out <- file.path(fig_pdf, "Figure S3. ERS subgroup forest.pdf")
# 高度随行数
n_row <- nrow(disp)
h_in <- max(7.5, 1.2 + n_row * 0.28)
wh <- tryCatch(forestploter::get_wh(p, unit = "in"), error = function(e) c(10.5, h_in))
w_in <- max(10.2, as.numeric(wh[1]))
h_in <- max(h_in, as.numeric(wh[2]))
grDevices::cairo_pdf(out, width = w_in, height = h_in, family = "serif")
grid::grid.newpage()
grid::grid.draw(p)
grDevices::dev.off()
message("wrote ", out, " rows=", n_row)

# 同步归档面板（不改 Fig4 拼图里的紧凑 4F；S3 独立交付）
arch <- file.path(out_ds, "fig4_panels")
if (dir.exists(arch)) {
  file.copy(out, file.path(arch, basename(out)), overwrite = TRUE)
}

writeLines(c(
  "# Figure S3. ERS subgroup forest",
  "",
  "## 图面说明",
  "对齐 Dong Supplementary Figure 3：左侧 Character（变量标题 + 缩进水平），",
  "OR (95% CI)、p、p for interaction；右侧 log 轴森林图（绿方点、蓝 CI，参照线 OR=1）。",
  paste0("亚组：", paste(vapply(sg_defs, `[[`, "", "title"), collapse = "; "), "。"),
  "牙周病特异亚组（漱口水/牙线/牙医就诊）未纳入（癌症队列无对应口径）。",
  "Education / Marital / BMI 为本队列可得二分水平（非原文三分）。",
  "层内 Model2 调整（剔除分层变量本身）；交互 P 为 ERS×亚组 LRT。",
  "",
  "## 分析上下文",
  paste0("暴露=ERS per IQR；结局=泛癌；N=", nrow(use),
         "；Model2=", paste(covars_m2, collapse = "+"), "；权重=WTSA2YR。")
), file.path(fig_md, "Figure S3. ERS subgroup forest.md"))

message("DONE Fig S3 Dong-style forestploter")
