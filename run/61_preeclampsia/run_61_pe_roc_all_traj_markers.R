#!/usr/bin/env Rscript
# 轨迹全指标 ROC（波次合图）：Disease 三对照 + Preterm34/GDM01
# Rscript run/61_preeclampsia/run_61_pe_roc_all_traj_markers.R

`%||%` <- function(a, b) if (!is.null(a)) a else b

.root_from_file <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    sp <- normalizePath(dirname(sub("^--file=", "", f[1L])), winslash = "/")
    if (basename(sp) == "61_preeclampsia" && basename(dirname(sp)) == "run") {
      return(normalizePath(file.path(sp, "..", ".."), winslash = "/"))
    }
  }
  normalizePath(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd()), winslash = "/")
}
root <- .root_from_file()
setwd(root)
source("/mnt/g/02block_result/61_Preeclampsia/configs/config_61_preeclampsia_batch.R")
suppressPackageStartupMessages({
  library(pROC)
  library(ggplot2)
  library(openxlsx)
})

ck <- file.path(
  "/mnt/g/02block_result/61_Preeclampsia/checkpoints/Full_pipeline/_shared",
  "imputed_with_neonatal_outcomes.rds"
)
if (!file.exists(ck)) {
  ck <- file.path(
    "/mnt/g/02block_result/61_Preeclampsia/checkpoints/Full_pipeline/_shared",
    "multicollinearity_screen.rds"
  )
}
obj <- readRDS(ck)
ctx <- if (!is.null(obj$ctx)) obj$ctx else obj
imp <- as.data.frame(ctx$data$imputed)
dis <- as.character(imp$Disease)

# ROC 时点：血脂/肾功仅 Early+Mid；BMI/Weight 另加 Pre（不用 Late）
specs <- list(
  list(stem = "Weight", times = c("Pre", "Early", "Mid"), label = "Weight"),
  list(stem = "BMI", times = c("Pre", "Early", "Mid"), label = "BMI"),
  list(stem = "Total_Cholesterol", times = c("Early", "Mid"), label = "Total cholesterol"),
  list(stem = "Triglycerides", times = c("Early", "Mid"), label = "Triglycerides"),
  list(stem = "HDL_Cholesterol", times = c("Early", "Mid"), label = "HDL cholesterol"),
  list(stem = "LDL_Cholesterol", times = c("Early", "Mid"), label = "LDL cholesterol"),
  list(stem = "FFA_Cholesterol", times = c("Early", "Mid"), label = "FFA cholesterol"),
  list(stem = "Uric_Acid", times = c("Early", "Mid"), label = "Uric acid"),
  list(stem = "Creatinine", times = c("Early", "Mid"), label = "Creatinine"),
  list(stem = "Urea", times = c("Early", "Mid"), label = "Urea"),
  list(stem = "Urine_Protein", times = c("Early", "Mid"), label = "Urine protein")
)
wave_cols <- c(Pre = "#4C78A8", Early = "#F58518", Mid = "#54A24B", Late = "#E45756")

.draw_roc_set <- function(imp, contrasts, specs, out_fig, out_tab_prefix) {
  if (!dir.exists(out_fig)) dir.create(out_fig, recursive = TRUE)
  rows <- list()
  for (ct in contrasts) {
    y_all <- ct$y
    keep0 <- ct$keep
    for (sp in specs) {
      curves <- list()
      stem_rows <- list()
      for (tm in sp$times) {
        mk <- paste0(tm, "_", sp$stem)
        if (!mk %in% names(imp)) next
        x <- suppressWarnings(as.numeric(imp[[mk]]))
        ok <- keep0 & is.finite(x) & !is.na(y_all)
        if (sum(ok) < 20L || length(unique(y_all[ok])) < 2L) next
        roc_obj <- tryCatch(
          pROC::roc(
            response = y_all[ok], predictor = x[ok],
            quiet = TRUE, direction = "auto"
          ),
          error = function(e) NULL
        )
        if (is.null(roc_obj)) next
        auc_v <- as.numeric(pROC::auc(roc_obj))
        ci <- as.numeric(pROC::ci.auc(roc_obj, quiet = TRUE))
        coords <- pROC::coords(
          roc_obj, "best", best.method = "youden",
          ret = c("threshold", "sensitivity", "specificity")
        )
        r <- data.frame(
          contrast = ct$name,
          contrast_label = ct$title,
          marker = mk,
          label = paste(tm, sp$label),
          wave = tm,
          biomarker = sp$label,
          n = sum(ok),
          events = sum(y_all[ok] == 1L),
          AUC = round(auc_v, 3),
          CI_low = round(ci[[1]], 3),
          CI_high = round(ci[[3]], 3),
          Youden_cutoff = as.numeric(coords[["threshold"]][1L]),
          Sensitivity = round(as.numeric(coords[["sensitivity"]][1L]), 3),
          Specificity = round(as.numeric(coords[["specificity"]][1L]), 3),
          direction = as.character(roc_obj$direction),
          stringsAsFactors = FALSE
        )
        rows[[length(rows) + 1L]] <- r
        stem_rows[[tm]] <- r
        curves[[tm]] <- data.frame(
          wave = tm,
          fpr = 1 - roc_obj$specificities,
          tpr = roc_obj$sensitivities
        )
      }
      if (!length(curves)) next
      df <- do.call(rbind, curves)
      df$wave <- factor(
        df$wave,
        levels = intersect(c("Pre", "Early", "Mid"), unique(df$wave))
      )
      lab_map <- c()
      for (tm in levels(df$wave)) {
        hit <- stem_rows[[tm]]
        lab_map[tm] <- sprintf(
          "%s  AUC=%.3f (%.3f-%.3f)", tm, hit$AUC, hit$CI_low, hit$CI_high
        )
      }
      df$wave_lab <- factor(
        lab_map[as.character(df$wave)],
        levels = unname(lab_map[levels(df$wave)])
      )
      cols_use <- wave_cols[levels(df$wave)]
      g <- ggplot2::ggplot(
        df, ggplot2::aes(x = .data$fpr, y = .data$tpr, color = .data$wave_lab)
      ) +
        ggplot2::geom_path(linewidth = 1.05) +
        ggplot2::geom_abline(
          slope = 1, intercept = 0, linetype = "longdash", color = "gray55"
        ) +
        ggplot2::scale_color_manual(
          values = stats::setNames(
            unname(cols_use), unname(lab_map[levels(df$wave)])
          )
        ) +
        ggplot2::scale_x_continuous(
          "1 - Specificity", limits = c(0, 1), breaks = seq(0, 1, 0.2)
        ) +
        ggplot2::scale_y_continuous(
          "Sensitivity", limits = c(0, 1), breaks = seq(0, 1, 0.2)
        ) +
        ggplot2::labs(
          title = paste0("ROC: ", sp$label, "\n", ct$title), color = NULL
        ) +
        ggplot2::theme_bw(base_size = 12) +
        ggplot2::theme(
          plot.title = ggplot2::element_text(hjust = 0.5, face = "bold", size = 12),
          panel.grid = ggplot2::element_blank(),
          legend.position = c(0.97, 0.03),
          legend.justification = c(1, 0),
          legend.background = ggplot2::element_rect(
            fill = grDevices::adjustcolor("white", alpha.f = 0.85),
            color = "gray80"
          ),
          legend.text = ggplot2::element_text(size = 8.5)
        )
      fig <- file.path(
        out_fig, paste0("ROC_", ct$file_tag, "_", sp$stem, "_by_wave.pdf")
      )
      grDevices::pdf(fig, width = 7.2, height = 6.8)
      print(g)
      grDevices::dev.off()
    }
  }
  tab <- do.call(rbind, rows)
  rownames(tab) <- NULL
  tab <- tab[order(
    tab$contrast, tab$biomarker,
    match(tab$wave, c("Pre", "Early", "Mid"))
  ), ]
  utils::write.csv(tab, paste0(out_tab_prefix, ".csv"), row.names = FALSE)
  openxlsx::write.xlsx(tab, paste0(out_tab_prefix, ".xlsx"), overwrite = TRUE)
  tab
}

# ── Disease 三对照 ──────────────────────────────────────────────────────────
contrasts_dis <- list(
  list(
    name = "AnyPE_vs_NonPE",
    title = "Any PE (PE + CH+PE) vs Non-PE",
    file_tag = "AnyPE",
    y = as.integer(dis != "Non-preeclampsia"),
    keep = rep(TRUE, length(dis))
  ),
  list(
    name = "PE_only_vs_NonPE",
    title = "Preeclampsia only vs Non-PE",
    file_tag = "PEonly",
    y = as.integer(dis == "Preeclampsia"),
    keep = dis %in% c("Non-preeclampsia", "Preeclampsia")
  ),
  list(
    name = "CHwithPE_vs_NonPE",
    title = "CH with PE vs Non-PE",
    file_tag = "CHwithPE",
    y = as.integer(dis == "Chronic hypertension with preeclampsia"),
    keep = dis %in% c("Non-preeclampsia", "Chronic hypertension with preeclampsia")
  )
)

roc_dir <- file.path(
  config$project$output_dir, "_shared/supplement_plan/ROC_bmi_lipid_Disease"
)
roc_fig <- file.path(roc_dir, "Figures")
roc_tab <- file.path(roc_dir, "Tables")
dir.create(roc_fig, recursive = TRUE, showWarnings = FALSE)
dir.create(roc_tab, recursive = TRUE, showWarnings = FALSE)
old <- list.files(roc_fig, pattern = "^ROC_.*\\.pdf$", full.names = TRUE)
if (length(old)) unlink(old)

cli::cli_h1("Disease ROC: full trajectory markers")
tab_dis <- .draw_roc_set(
  imp, contrasts_dis, specs, roc_fig,
  file.path(roc_tab, "Table_ROC_traj_markers_Disease_contrasts")
)
openxlsx::write.xlsx(
  tab_dis, file.path(roc_tab, "Table_ROC_BMI_lipid_Disease_contrasts.xlsx"),
  overwrite = TRUE
)
openxlsx::write.xlsx(
  tab_dis[tab_dis$contrast == "AnyPE_vs_NonPE", ],
  file.path(roc_tab, "Table_ROC_BMI_lipid_Disease_PE01.xlsx"),
  overwrite = TRUE
)
cli::cli_alert_success(
  "Disease: {length(list.files(roc_fig, pattern='\\\\.pdf$'))} figs, {nrow(tab_dis)} rows"
)

# ── Preterm / GDM ───────────────────────────────────────────────────────────
y_pt <- if (is.factor(imp$Preterm34) || is.character(imp$Preterm34)) {
  as.integer(as.character(imp$Preterm34) == "Preterm34")
} else {
  as.integer(as.numeric(imp$Preterm34) == 1)
}
contrasts_out <- list(
  list(
    name = "Preterm34", title = "Preterm <34 weeks", file_tag = "Preterm34",
    y = y_pt, keep = rep(TRUE, nrow(imp))
  ),
  list(
    name = "GDM01", title = "GDM", file_tag = "GDM01",
    y = as.integer(as.numeric(imp$GDM01) == 1),
    keep = rep(TRUE, nrow(imp))
  )
)
roc_dir2 <- file.path(
  config$project$output_dir, "_shared/supplement_plan/ROC_bmi_lipid"
)
roc_fig2 <- file.path(roc_dir2, "Figures")
roc_tab2 <- file.path(roc_dir2, "Tables")
dir.create(roc_fig2, recursive = TRUE, showWarnings = FALSE)
dir.create(roc_tab2, recursive = TRUE, showWarnings = FALSE)
old2 <- list.files(roc_fig2, pattern = "^ROC_.*\\.pdf$", full.names = TRUE)
if (length(old2)) unlink(old2)

cli::cli_h1("Preterm/GDM ROC: full trajectory markers")
tab_out <- .draw_roc_set(
  imp, contrasts_out, specs, roc_fig2,
  file.path(roc_tab2, "Table_ROC_traj_markers_Preterm_GDM")
)
openxlsx::write.xlsx(
  tab_out, file.path(roc_tab2, "Table_ROC_BMI_lipid_univariate.xlsx"),
  overwrite = TRUE
)
cli::cli_alert_success(
  "Preterm/GDM: {length(list.files(roc_fig2, pattern='\\\\.pdf$'))} figs, {nrow(tab_out)} rows"
)

new_bio <- c("Weight", "Uric acid", "Creatinine", "Urea", "Urine protein")
sub <- tab_dis[tab_dis$contrast == "AnyPE_vs_NonPE" & tab_dis$biomarker %in% new_bio, ]
cli::cli_h2("AnyPE newly added (top)")
print(utils::head(
  sub[order(-sub$AUC), c("label", "n", "events", "AUC", "CI_low", "CI_high")],
  15
), row.names = FALSE)
cli::cli_alert_success("完成")
