#!/usr/bin/env Rscript
# 重修卒中 ANLR Fig2/Fig3：对齐 Hip Jin 风格；双库强制同一共享特征集

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(survival)
  library(grid)
  library(xgboost)
})

`%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a
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

dbs <- readRDS(file.path(.tab, "imputed_dbs.rds"))
.lock <- readRDS(file.path(.tab, "quantile_scheme_resolved.rds"))
.note <- file.path(.tab, "Covariate_selection_note.txt")
if (file.exists(.note)) {
  m3 <- trimws(unlist(strsplit(sub("^.*: ", "", readLines(.note)[1]), " \\+ ")))
} else if (file.exists(file.path(.tab, "Model3_by_database.rds"))) {
  m3 <- Reduce(intersect, readRDS(file.path(.tab, "Model3_by_database.rds")))
  writeLines(c(
    "Dual-DB Model3 intersection (for Methods / remirror preference):",
    paste(m3, collapse = " + ")
  ), .note)
} else {
  m3 <- c("Age", "Gender")
}
IDX <- "ANLR"

# ---- 强制共享特征池（两库列交集 ∩ 协变量候选；含 ANLR；不含 SOFA 成分）----
pool_json <- jsonlite::fromJSON(file.path(.proj, "data/shared_feature_pool.json"))
cov_cand <- intersect(pool_json$covariate_pool, Reduce(intersect, lapply(dbs, names)))
cov_cand <- setdiff(cov_cand, c(pool_json$exposure_components, "SOFA", pool_json$disease_vars))
# 双库均有变异
cov_cand <- cov_cand[vapply(cov_cand, function(v) {
  all(vapply(dbs, function(d) length(unique(na.omit(d[[v]]))) > 1L, logical(1)))
}, logical(1))]
shared_fs <- unique(c(IDX, "Age", "Gender", cov_cand))
shared_fs <- shared_fs[shared_fs %in% names(dbs$MIMIC) & shared_fs %in% names(dbs$eICU)]
message("共享特征集 n=", length(shared_fs), ": ", paste(shared_fs, collapse = ", "))
writeLines(shared_fs, file.path(.tab, "shared_feature_selection_vars.txt"))

.lab_disp <- function(x) {
  x <- as.character(x)
  x <- gsub("^Gender(Male|Female)$", "Gender: \\1", x)
  x <- gsub("^Race([A-Z].*)$", "Race: \\1", x)
  x <- gsub("^(Ventilation|Hypertension|Diabetes|Heart_Failure|Myocardial_Infarction|COPD|Pneumonia|Malignant_Tumor|CKD|Hyperlipidemia|Liver_cirrhosis|Hepatitis)(Yes|No)$",
            "\\1: \\2", x)
  pipeline_display_label(x)
}

# ---- 重跑 Boruta + SHAP（同一 shared_fs）----
bor_list <- list()
shap_long <- list()
shap_sum <- list()

for (nm in names(dbs)) {
  message("==== FS ", nm, " ====")
  d <- as.data.frame(dbs[[nm]])
  use <- shared_fs
  dd <- d[stats::complete.cases(d[, c("fustatus", "futime_years", use)]) & d$futime_years > 0, ]
  dd$fustatus_f <- factor(dd$fustatus, levels = c(0, 1))
  for (v in use) if (is.character(dd[[v]]) || is.logical(dd[[v]])) dd[[v]] <- factor(dd[[v]])
  set.seed(41904528)
  bor <- Boruta::Boruta(
    stats::as.formula(paste("fustatus_f ~", paste(use, collapse = "+"))),
    data = dd, doTrace = 0, maxRuns = 100, ntree = 400
  )
  bor <- Boruta::TentativeRoughFix(bor)
  bor_list[[nm]] <- bor
  st <- Boruta::attStats(bor)
  st$variable <- rownames(st)
  st$database <- nm
  fwrite(st, file.path(.tab, sprintf("Boruta_by_database_%s.csv", nm)))

  mm <- stats::model.matrix(stats::as.formula(paste("~", paste(use, collapse = "+"))), data = dd)
  mm <- mm[, colnames(mm) != "(Intercept)", drop = FALSE]
  lab <- ifelse(dd$fustatus == 1, dd$futime_years, -dd$futime_years)
  dtrain <- xgboost::xgb.DMatrix(mm, label = lab)
  fit <- xgboost::xgb.train(
    params = list(objective = "survival:cox", max_depth = 3, eta = 0.05),
    data = dtrain, nrounds = 80, verbose = 0
  )
  ex <- predict(fit, newdata = mm, predcontrib = TRUE)
  ex <- ex[, colnames(ex) != "BIAS", drop = FALSE]
  imp <- sort(colMeans(abs(ex)), decreasing = TRUE)
  shap_sum[[nm]] <- data.frame(database = nm, variable = names(imp), mean_abs_shap = as.numeric(imp))
  set.seed(41904528)
  idx_s <- sample(seq_len(nrow(ex)), min(1500L, nrow(ex)))
  sl <- as.data.frame(ex[idx_s, , drop = FALSE])
  sl$i <- seq_len(nrow(sl))
  sl <- data.table::melt(as.data.table(sl), id.vars = "i", variable.name = "variable", value.name = "shap")
  sl$database <- nm
  shap_long[[nm]] <- as.data.frame(sl)
}

saveRDS(bor_list, file.path(.tab, "Boruta_objects.rds"))
shap_df <- rbindlist(shap_long, fill = TRUE)
saveRDS(as.data.frame(shap_df), file.path(.tab, "SHAP_long.rds"))
mean_tab <- rbindlist(shap_sum, fill = TRUE)
fwrite(mean_tab, file.path(.tab, "SHAP_by_database.csv"))
fwrite(rbindlist(lapply(names(bor_list), function(nm) {
  st <- Boruta::attStats(bor_list[[nm]])
  data.frame(database = nm, variable = rownames(st), st, check.names = FALSE)
}), fill = TRUE), file.path(.tab, "Boruta_by_database.csv"))

# ---- Fig2：每库 A/B/C/D 四面板，上下 MIMIC / eICU ----
.fig2_one <- function(bor, shap_df_one, mean_tab_one, highlight = IDX) {
  h <- as.data.frame(bor$ImpHistory)
  h$iter <- seq_len(nrow(h))
  st <- Boruta::attStats(bor)
  dec <- setNames(as.character(st$decision), rownames(st))
  vars <- setdiff(colnames(h), "iter")
  box <- do.call(rbind, lapply(vars, function(v) data.frame(variable = v, z = h[[v]])))
  box$decision <- dec[box$variable]
  box$decision[is.na(box$decision)] <- "Shadow"
  med <- tapply(box$z, box$variable, median, na.rm = TRUE)
  box$variable <- factor(.lab_disp(box$variable), levels = .lab_disp(names(sort(med))))
  pal <- c(Confirmed = "#2ca02c", Rejected = "#d62728", Tentative = "#ffbf00", Shadow = "#1f77b4")
  th <- theme_classic(base_size = 8) +
    theme(axis.text.x = element_text(angle = 55, hjust = 1, size = 5.2),
          legend.position = "bottom", legend.key.size = unit(0.3, "cm"))
  pA <- ggplot(box, aes(variable, z, fill = decision)) +
    geom_boxplot(outlier.size = 0.25, linewidth = 0.25) +
    scale_fill_manual(values = pal, name = NULL) +
    labs(x = "Attributes", y = "Importance", title = "A") + th

  real <- intersect(rownames(st), colnames(h))
  lines <- do.call(rbind, lapply(real, function(v) data.frame(iter = h$iter, variable = v, z = h[[v]])))
  lines$group <- ifelse(lines$variable %in% highlight | grepl(paste0("^", highlight), lines$variable),
                        "Index", "Other")
  pB <- ggplot(lines, aes(iter, z, group = variable, color = group)) +
    geom_line(linewidth = 0.3) +
    scale_color_manual(values = c(Index = "#e74c3c", Other = "#4c78a8"), name = NULL) +
    labs(x = "Iteration", y = "Boruta Z-score", title = "B") +
    theme_classic(base_size = 8) + theme(legend.position = "bottom")

  sh <- as.data.frame(shap_df_one)
  sh$variable_raw <- as.character(sh$variable)
  sh$group <- ifelse(sh$variable_raw %in% highlight | grepl(paste0("^", highlight), sh$variable_raw),
                     "Index", "Other")
  ord_raw <- names(sort(tapply(abs(sh$shap), sh$variable_raw, mean)))
  sh$variable <- factor(.lab_disp(sh$variable_raw), levels = .lab_disp(ord_raw))
  pC <- ggplot(sh, aes(shap, variable, color = group)) +
    geom_jitter(height = 0.15, width = 0, size = 0.2, alpha = 0.4) +
    geom_vline(xintercept = 0, linewidth = 0.25) +
    scale_color_manual(values = c(Index = "#e74c3c", Other = "grey55"), name = NULL) +
    labs(x = "SHAP value (log-hazard)", y = "Feature", title = "C") +
    theme_classic(base_size = 8) + theme(legend.position = "bottom")

  md <- as.data.frame(mean_tab_one)
  md$group <- ifelse(md$variable %in% highlight | grepl(paste0("^", highlight), md$variable),
                     "Index", "Other")
  # 只展示与 Boruta 同池的列（去掉哑变量碎列过多时取 top）
  if (nrow(md) > 25L) md <- md[order(-md$mean_abs_shap), ][1:25, ]
  ord_md <- names(sort(setNames(md$mean_abs_shap, md$variable)))
  md$variable <- factor(.lab_disp(md$variable), levels = .lab_disp(ord_md))
  pD <- ggplot(md, aes(mean_abs_shap, variable, fill = group)) +
    geom_col(width = 0.72) +
    scale_fill_manual(values = c(Index = "#e74c3c", Other = "grey70"), name = NULL) +
    labs(x = "Mean |SHAP value|", y = NULL, title = "D") +
    theme_classic(base_size = 8) + theme(legend.position = "bottom")

  list(A = pA, B = pB, C = pC, D = pD)
}

blocks <- lapply(names(bor_list), function(nm) {
  list(
    title = nm,
    panels = .fig2_one(
      bor_list[[nm]],
      shap_df[shap_df$database == nm, ],
      mean_tab[mean_tab$database == nm, ]
    )
  )
})

fig2 <- file.path(.fig, "Figure 2. Boruta confirmation and SHAP values for all-cause mortality.pdf")
if (file.exists(fig2)) file.remove(fig2)
# 双库各一套 A–D：总高控制在 ≤11 in
cairo_pdf(fig2, width = 10.5, height = 10.8, family = "Times")
grid.newpage()
nblk <- length(blocks)
for (i in seq_len(nblk)) {
  y0 <- 1 - i / nblk
  pushViewport(viewport(y = y0, height = 1 / nblk, just = c("centre", "bottom")))
  grid.text(blocks[[i]]$title, x = 0.02, y = 0.98, just = c("left", "top"),
            gp = gpar(fontsize = 11, fontface = "bold", fontfamily = "Times"))
  panels <- blocks[[i]]$panels
  for (j in seq_along(panels)) {
    col <- if (j %% 2L == 1L) 0 else 1
    row <- if (j <= 2L) 1 else 0
    print(panels[[j]], vp = viewport(
      x = 0.02 + col * 0.49, y = 0.04 + row * 0.46,
      width = 0.47, height = 0.44, just = c("left", "bottom")
    ))
  }
  popViewport()
}
dev.off()
message("Fig2 OK -> ", fig2)

# ---- Fig3：累积发病率 1−KM + 风险表；双库并排/上下 ----
if (!requireNamespace("survminer", quietly = TRUE)) stop("need survminer")
.qsc_meta <- .lock$meta
.km_one <- function(d, qv, title) {
  d <- as.data.frame(d)
  # 28 天终点：横轴用天（futime），勿用 years
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
message("Fig3 OK -> ", fig3)

# 刷新四目录 / image_information
pub_figure_ensure_formats(
  file.path(.out, "Figures"),
  meta = list(
    databases = names(dbs),
    exposure = "ANLR",
    outcome = "28-day all-cause mortality",
    tables_dir = .tab,
    grouping = .lock$scheme
  ),
  config = list(pub_figures = list(export_png = FALSE, export_tiff = FALSE, max_edge_in = 11))
)

# 手工补 Fig2/3 image_information 要点
.write_md <- function(stem, body) {
  md <- file.path(.out, "Figures", "image_information", paste0(stem, ".md"))
  writeLines(body, md)
}
.write_md(
  "Figure 2. Boruta confirmation and SHAP values for all-cause mortality",
  c(
    "# Figure 2. Boruta confirmation and SHAP values for all-cause mortality",
    "",
    "## 图面说明",
    "双库各一套四面板（对齐 Jin/Hip 版式）：A Boruta 重要性箱线；B Boruta Z-score 轨迹；C SHAP 蜂群；D mean |SHAP|。",
    paste0("两库特征筛选强制同一共享变量集（n=", length(shared_fs), "）：", paste(shared_fs, collapse = ", "), "。"),
    "ANLR 在轨迹/SHAP 中标为 Index（红色）。展示名已去编程下划线。",
    "",
    "## 分析上下文",
    "- 暴露: ANLR",
    "- 结局: 28-day all-cause mortality",
    paste0("- 样本量: MIMIC N=", nrow(dbs$MIMIC), "；eICU N=", nrow(dbs$eICU)),
    "- 数据库: MIMIC + eICU（平权；共享特征）",
    "- 是否拼图: 是（上下分库，各 A–D）"
  )
)
.write_md(
  "Figure 3. Cumulative incidence of all-cause mortality by ANLR",
  c(
    "# Figure 3. Cumulative incidence of all-cause mortality by ANLR",
    "",
    "## 图面说明",
    paste0("双库累积发病率（1−KM），分组=", .lock$scheme, "（", paste(.qsc_meta$labels, collapse = "/"), "）。"),
    "含 Number at risk；图内标注 Log-rank P。横轴 Follow-up (days)（28 天终点），纵轴 Cumulative incidence of all-cause mortality。",
    "",
    "## 分析上下文",
    "- 暴露: ANLR",
    "- 结局: 28-day all-cause mortality",
    paste0("- Grouping: ", .lock$scheme, "（双库同 scheme；切点各库自算）"),
    paste0("- 样本量: MIMIC N=", nrow(dbs$MIMIC), "；eICU N=", nrow(dbs$eICU)),
    "- 数据库: MIMIC + eICU",
    "- 是否拼图: 是（上下分库）"
  )
)

st <- pub_figure_formats_status(
  file.path(.out, "Figures"),
  config = list(pub_figures = list(export_png = FALSE, export_tiff = FALSE, max_edge_in = 11))
)
message("bad_geo=", paste(st$bad_pdf_geometry %||% "", collapse = ";"))
message("done")
