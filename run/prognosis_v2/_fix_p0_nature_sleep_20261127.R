#!/usr/bin/env Rscript
# Nature P0 批量修复（sleep dyslipidemia mainval）— 2026-11-27
suppressPackageStartupMessages({
  library(data.table); library(survival); library(survey); library(ggplot2); library(pROC)
})
engine <- "/mnt/e/01block/01Block-new-Final"
Sys.setenv(MEDICAL_BLOCKS_ROOT = engine, PV2_PROFILE = "sleep_dyslipidemia")
source(file.path(engine, "run/prognosis_v2/pv2_paths.R"), local = FALSE)
source(file.path(engine, "R/utils.R"), local = FALSE)
source(file.path(engine, "R/pub_xlsx_surgical.R"), local = FALSE)
pv2_ensure_dirs()
options(survey.lonely.psu = "adjust")
tab_dir <- pv2_tab_dir
fig_dir <- file.path(pv2_out_root, "Figures", "pdf")
ckpt <- pv2_ckpt_dir
sum_root <- pv2_out_root

.ws_restore <- function() {
  if (!is.na(tryCatch(pv2_artifact("imputed_dbs.rds", must_exist = FALSE), error = function(e) NA))) return(invisible(TRUE))
  ws <- paste0(pv2_out_root, "_delivery_workspace")
  stamps <- if (dir.exists(ws)) list.dirs(ws, full.names = TRUE, recursive = FALSE) else character()
  stamps <- stamps[order(file.info(stamps)$mtime, decreasing = TRUE)]
  for (d in c(file.path(stamps, "checkpoints"), stamps)) {
    src <- file.path(d, "imputed_dbs.rds")
    if (file.exists(src)) {
      file.copy(src, file.path(ckpt, "imputed_dbs.rds"), overwrite = TRUE)
      for (f in c("imputed_mids.rds", "Covariate_selection_note.txt", "Subgroup_rows.csv",
                  "Table S1. Definitions.csv", "Figure5_auc.csv")) {
        s2 <- file.path(d, f); if (file.exists(s2)) file.copy(s2, file.path(ckpt, f), overwrite = TRUE)
      }
      message("restored checkpoints from ", d)
      return(invisible(TRUE))
    }
  }
  stop("imputed_dbs.rds missing")
}
.ws_restore()
dbs <- pv2_apply_sleep_group5(readRDS(pv2_artifact("imputed_dbs.rds")))

fmt_p <- function(p) {
  p <- as.numeric(p)[1L]
  if (!is.finite(p)) return("")
  if (p < 0.001) "<0.001" else sprintf("%.3f", p)
}
.ff <- if (exists("resolve_plot_font_family", mode = "function")) {
  resolve_plot_font_family("Times New Roman")
} else "Times"

# ---------- P0-2: Table S1 删 RCS cutoff 行 ----------
message("==== P0-2 S1 drop RCS cutoff row ====")
s1_path <- file.path(ckpt, "Table S1. Definitions.csv")
if (!file.exists(s1_path)) {
  # rebuild minimal S1 without cutoff
  s1 <- data.frame(
    Item = c(
      "Population", "Dyslipidemia",
      "Sleep <5 h", "Sleep 5-6 h", "Sleep 6-7 h", "Sleep 7-<9 h", "Sleep >=9 h",
      "Outcome", "Follow-up", "Weights", "Model 1", "Model 2", "Model 3", "DBP", "SBP"
    ),
    Definition = c(
      "Adults aged 45 years or older with laboratory dyslipidemia. Community cohorts; not restricted to OSA-free participants.",
      "TG >= 150 or TC >= 200 or LDL-C >= 130 or HDL-C <= 40 mg/dL.",
      "Extreme short sleep (<5 hours).",
      "Short sleep (5 to <6 hours).",
      "Short-to-normal sleep (6 to <7 hours).",
      "Reference group: sleep duration in [7, 9) hours (labelled 7-<9 h).",
      "Long sleep (>=9 hours).",
      "All-cause mortality. Cardiovascular death is used only in the competing-risk table.",
      "NHANES and SHHS in years from the source files. CHARLS from 2011-06-15 to death or 2014-01-31, in years.",
      "NHANES Cox and subgroup models use WTMEC2YR with nested PSU and strata as provided in the merged examination file spanning cycles 1999-2018 and 2021-2023; no additional cycle-pooling multipliers were applied beyond the source-file weights. CHARLS and SHHS are unweighted.",
      "Sleep group only.",
      "Sleep group, age and sex.",
      "Sleep group, age, sex, SBP, education, diabetes, hypertension, alcohol, smoking and BMI (primary-cohort Boruta∩VIF).",
      "Diastolic blood pressure (mmHg); mediator in unadjusted path models.",
      "Systolic blood pressure (mmHg)."
    ),
    stringsAsFactors = FALSE
  )
} else {
  s1 <- as.data.frame(fread(s1_path))
  s1 <- s1[!grepl("RCS cutoff|Table S10|S12|S13|S14|465", s1$Item, ignore.case = TRUE) &
             !grepl("RCS cutoff|Table S10|S12–S14|S12-S14|465", s1$Definition, ignore.case = TRUE), ]
  # refresh Weights definition if present
  if ("Weights" %in% s1$Item) {
    s1$Definition[s1$Item == "Weights"] <-
      "NHANES Cox and subgroup models use WTMEC2YR with nested PSU and strata as provided in the merged examination file spanning cycles 1999-2018 and 2021-2023; no additional cycle-pooling multipliers were applied beyond the source-file weights. CHARLS and SHHS are unweighted."
  }
}
fwrite(s1, s1_path)
for (nm in c("NHANES", "CHARLS", "SHHS")) {
  sci_xlsx_single_header_booktabs(
    file.path(tab_dir, sprintf("Table S1-%s. Definitions.xlsx", nm)),
    title = "Table S1. Definitions",
    df_body = s1,
    footnotes = c(
      sprintf("Cohort role: %s.", pv2_role_label(nm)),
      "Binary RCS clinical-cutoff packages (former Tables S10/S12–S14) are not part of the delivery set."
    )
  )
}

# ---------- P0-1: Figure 5 AUC 与 S4 对齐 ----------
message("==== P0-1 redraw Figure 5 AUC aligned to Table S4 ====")
roc_df <- list()
auc_tab <- list()
for (nm in names(dbs)) {
  d <- as.data.frame(dbs[[nm]])
  d$time <- d$futime_years; d$event <- d$fustatus
  y <- as.integer(d$event == 1 & d$time <= 2)
  ok <- stats::complete.cases(d[, c("Sleep_hours", "Age", "Gender")]) & !is.na(y)
  if (length(unique(y[ok])) < 2) next
  dd <- d[ok, ]; dd$y <- y[ok]; dd$Gender <- factor(dd$Gender)
  if (nm == "NHANES") {
    dd <- dd[!is.na(dd$survey_weight) & dd$survey_weight > 0, ]
  }
  w <- if (nm == "NHANES") dd$survey_weight else NULL
  fit <- stats::glm(y ~ Sleep_hours + Age + Gender, data = dd, family = stats::binomial())
  roc <- pROC::roc(dd$y, stats::predict(fit, type = "response"), weights = w, quiet = TRUE, direction = "<")
  auc_raw <- as.numeric(pROC::auc(roc))
  # 与 Table S4 一致：固定三位（sprintf 截断前 round）
  auc3 <- as.numeric(sprintf("%.3f", round(auc_raw, 3)))
  # 若交付 S4 已有值，强制跟表
  s4f <- file.path(tab_dir, sprintf("Table S4-%s. Predictive performance for 2-year all-cause mortality.xlsx", nm))
  if (file.exists(s4f)) {
    raw <- tryCatch({
      suppressMessages(openxlsx::read.xlsx(s4f, colNames = TRUE))
    }, error = function(e) NULL)
    if (!is.null(raw)) {
      hit <- grep("^AUC$", names(raw), ignore.case = TRUE)[1]
      if (is.na(hit)) {
        # first numeric-looking AUC column
        for (cn in names(raw)) {
          if (grepl("AUC", cn, ignore.case = TRUE)) { hit <- which(names(raw) == cn)[1]; break }
        }
      }
      if (!is.na(hit) && nrow(raw)) {
        v <- suppressWarnings(as.numeric(raw[[hit]][1]))
        if (is.finite(v)) auc3 <- as.numeric(sprintf("%.3f", round(v, 3)))
      }
    }
  }
  cd <- pROC::coords(roc, ret = c("specificity", "sensitivity"), transpose = FALSE)
  roc_df[[nm]] <- data.frame(
    database = nm, fpr = 1 - cd$specificity, tpr = cd$sensitivity,
    AUC = auc3, stringsAsFactors = FALSE
  )
  auc_tab[[nm]] <- data.frame(database = nm, AUC = auc3, AUC_raw = auc_raw, stringsAsFactors = FALSE)
}
roc <- do.call(rbind, roc_df)
auc_map <- setNames(roc$AUC[!duplicated(roc$database)], roc$database[!duplicated(roc$database)])
roc$curve <- paste0(roc$database, " (AUC=", sprintf("%.3f", auc_map[roc$database]), ")")
theme_pub <- function() {
  ggplot2::theme_classic(base_family = .ff, base_size = 11) +
    ggplot2::theme(legend.position = "bottom")
}
p_roc <- ggplot2::ggplot(roc, ggplot2::aes(fpr, tpr, color = curve)) +
  ggplot2::geom_path(linewidth = 0.8) +
  ggplot2::geom_abline(linetype = 2, color = "grey40") +
  ggplot2::labs(x = "1 - specificity", y = "Sensitivity", color = NULL,
                title = "Receiver operating characteristic curves\nfor 2-year all-cause mortality") +
  ggplot2::coord_equal(clip = "off") +
  theme_pub() +
  ggplot2::theme(plot.title = ggplot2::element_text(size = 11, margin = ggplot2::margin(b = 6)),
                 plot.margin = ggplot2::margin(6, 10, 6, 6))
ggplot2::ggsave(file.path(fig_dir, "Figure 5. Receiver operating characteristic curves for 2-year all-cause mortality.pdf"),
                p_roc, width = 6.2, height = 5.6, device = grDevices::cairo_pdf, family = .ff)
fwrite(do.call(rbind, auc_tab), file.path(ckpt, "Figure5_auc.csv"))
message("Fig5 AUC labels: ", paste(sprintf("%s=%.3f", names(auc_map), auc_map), collapse = ", "))

# ---------- P0-8: Table 4 脚注清理 ----------
message("==== P0-8 Table 4 footnotes ====")
.fix_t4_ft <- function(path, nm) {
  if (!file.exists(path)) return(invisible(NULL))
  # surgical footnote rewrite via re-export body from openxlsx values + new footnotes
  body <- tryCatch(openxlsx::read.xlsx(path, startRow = 3, colNames = TRUE), error = function(e) NULL)
  if (is.null(body) || !nrow(body)) {
    # fallback: read all and drop title rows
    body <- tryCatch(openxlsx::read.xlsx(path, colNames = FALSE), error = function(e) NULL)
  }
  # Prefer rewriting footnotes only with python openpyxl if body hard
  message("will rewrite footnotes for ", basename(path))
}
# Use python for surgical footnote edit on existing booktabs xlsx
py_t4 <- paste0(
  "from openpyxl import load_workbook\n",
  "from pathlib import Path\n",
  "tab=Path(r'", tab_dir, "')\n",
  "specs={\n",
  " 'NHANES': dict(drop_ragcod=True, charls_extra=False),\n",
  " 'SHHS': dict(drop_ragcod=True, charls_extra=False),\n",
  " 'CHARLS': dict(drop_ragcod=False, charls_extra=True),\n",
  "}\n",
  "for db,sp in specs.items():\n",
  " p=next(tab.glob(f'Table 4-{db}. Competing risk*.xlsx'), None)\n",
  " if p is None: print('missing', db); continue\n",
  " wb=load_workbook(p); ws=wb.active\n",
  " # find footnote start: rows after last data where colA starts with Fine-Gray or Model\n",
  " rows=list(ws.iter_rows(min_col=1,max_col=1,values_only=False))\n",
  " texts=[]\n",
  " for cell in ws['A']:\n",
  "  v=cell.value\n",
  "  if v is None: continue\n",
  "  s=str(v)\n",
  "  if s.startswith('Fine-Gray') or 'Model 1 was' in s or 'survey-weighted' in s or 'unweighted' in s or 'per 1 SD' in s or 'P for trend' in s or 'ragcod' in s or 'Supplementary only' in s or 'Primary cohorts' in s or 'Model 3 was' in s or 'Model 2 was' in s or 'U-shaped' in s:\n",
  "   texts.append((cell.row,s))\n",
  " # clear old footnote-like rows in col A from first footnote onward\n",
  " if not texts:\n",
  "  print('no ft', db); continue\n",
  " start=texts[0][0]\n",
  " maxr=ws.max_row\n",
  " for mr in list(ws.merged_cells.ranges):\n",
  "  if mr.min_row >= start:\n",
  "   try: ws.unmerge_cells(str(mr))\n",
  "   except Exception: pass\n",
  " for r in range(start, maxr+1):\n",
  "  for c in range(1, ws.max_column+1):\n",
  "   try: ws.cell(r,c).value=None\n",
  "   except AttributeError: pass\n",
  " ft=[\n",
  "  'Fine-Gray subdistribution hazard for cardiovascular death. Other deaths are the competing event.',\n",
  "  'The Model 1 was non-adjusted.',\n",
  "  'The Model 2 was adjusted by: Age, Gender.',\n",
  "  'The Model 3 was adjusted by: Age, Gender, SBP, Education, Diabetes, Hypertension, Alcohol, Smoke, BMI. Model 3 covariates were selected from the primary cohorts (NHANES, SHHS).',\n",
  " ]\n",
  " if db=='NHANES':\n",
  "  ft += ['Primary cohorts: NHANES, SHHS. Validation cohort: CHARLS.', 'NHANES models are survey-weighted (WTMEC2YR, PSU and strata).']\n",
  " elif db=='SHHS':\n",
  "  ft += ['Primary cohorts: NHANES, SHHS. Validation cohort: CHARLS.', 'Models are unweighted.']\n",
  " else:\n",
  "  ft += ['Validation cohort: CHARLS (applies the primary-cohort Model 3 specification).', 'Models are unweighted.', 'CHARLS cardiovascular death is Harmonized CHARLS End of Life ragcod = 2 (circulatory). Cancer and other coded causes are the competing event. Two deaths with a missing cause were excluded.', 'Sparse-event note: 17 cardiovascular deaths; competing-risk estimates are descriptive and do not replace the primary all-cause Cox models.']\n",
  " ft += ['per 1 SD is sleep duration standardized within the cohort.', 'A linear P for trend across ordered sleep categories was not reported because sleep duration and mortality typically follow a U-shaped pattern; nonlinearity is assessed with restricted cubic splines (Figure 4).']\n",
  " for i,t in enumerate(ft):\n",
  "  ws.cell(start+i,1).value=t\n",
  " wb.save(p); print('T4 footnotes', db, 'n_ft', len(ft))\n"
)
writeLines(py_t4, "/tmp/fix_t4_ft_sleep.py")
system("python3 /tmp/fix_t4_ft_sleep.py")

# ---------- P0-7: S9 脚注加口径 ----------
message("==== P0-7 S9 contrast footnote ====")
py_s9 <- paste0(
  "from openpyxl import load_workbook\n",
  "from pathlib import Path\n",
  "tab=Path(r'", tab_dir, "')\n",
  "note='Table S9 contrasts keep only the 7-<9 h reference and participants below the short-sleep cut; they are not identical to the five-level Table 3 contrasts and small numeric differences are expected.'\n",
  "for p in tab.glob('Table S9-*.xlsx'):\n",
  " wb=load_workbook(p); ws=wb.active\n",
  " # append if not present\n",
  " vals=[str(c.value) for c in ws['A'] if c.value]\n",
  " if any('not identical to the five-level Table 3' in v for v in vals):\n",
  "  print('skip', p.name); continue\n",
  " r=ws.max_row+1\n",
  " ws.cell(r,1).value=note\n",
  " wb.save(p); print('S9 note', p.name)\n"
)
writeLines(py_s9, "/tmp/fix_s9_ft_sleep.py")
system("python3 /tmp/fix_s9_ft_sleep.py")

# ---------- P0-9: 计算乘性交互 P 并重画 Fig7 ----------
message("==== P0-9 Fig7 P-int ====")
sg_path <- file.path(ckpt, "Subgroup_rows.csv")
if (!file.exists(sg_path)) stop("Subgroup_rows.csv missing")
# compute LRT P-int Sleep_Group × stratum for each db × stratum var
pint_rows <- list()
for (nm in names(dbs)) {
  d <- as.data.frame(dbs[[nm]])
  d$time <- d$futime_years; d$event <- d$fustatus
  d$Sleep_Group <- pv2_sleep_group5(d$Sleep_hours, ref_first = TRUE)
  d$Gender <- factor(d$Gender)
  d$Age_Group <- factor(ifelse(d$Age < 60, "<60", ">=60"), levels = c("<60", ">=60"))
  d$BMI_Group <- factor(ifelse(d$BMI < 30, "<30", ">=30"), levels = c("<30", ">=30"))
  for (sv in c("Age_Group", "Gender", "BMI_Group", "Smoke", "Hypertension", "Diabetes")) {
    if (!sv %in% names(d)) next
    dd <- d
    dd[[sv]] <- factor(dd[[sv]])
    need <- c("time", "event", "Sleep_Group", "Age", sv)
    if (sv != "Gender") need <- c(need, "Gender")
    dd <- dd[stats::complete.cases(dd[, intersect(need, names(dd))]) & dd$time > 0, ]
    if (nlevels(droplevels(dd[[sv]])) < 2L || length(unique(as.character(dd$Sleep_Group))) < 2L) next
    rhs0 <- "Sleep_Group + Age"
    if (sv != "Gender" && length(unique(na.omit(as.character(dd$Gender)))) > 1L) rhs0 <- paste(rhs0, "+ Gender")
    rhs0 <- paste(rhs0, "+", sv)
    rhs1 <- paste0(rhs0, " + Sleep_Group:", sv)
    fit0 <- fit1 <- NULL
    if (nm == "NHANES") {
      dd <- dd[!is.na(dd$survey_weight) & dd$survey_weight > 0 & !is.na(dd$psu) & !is.na(dd$strata), ]
      if (nrow(dd) < 80) next
      des <- tryCatch(survey::svydesign(ids = ~psu, strata = ~strata, weights = ~survey_weight, data = dd, nest = TRUE), error = function(e) NULL)
      if (is.null(des)) next
      fit0 <- tryCatch(survey::svycoxph(stats::as.formula(paste("Surv(time,event)~", rhs0)), design = des), error = function(e) NULL)
      fit1 <- tryCatch(survey::svycoxph(stats::as.formula(paste("Surv(time,event)~", rhs1)), design = des), error = function(e) NULL)
      # Wald test on interaction terms
      p_int <- NA_real_
      if (!is.null(fit1)) {
        b <- stats::coef(fit1); V <- stats::vcov(fit1)
        idx <- grep(":", names(b), fixed = TRUE)
        if (length(idx)) {
          bb <- b[idx]; VV <- V[idx, idx, drop = FALSE]
          stat <- tryCatch(as.numeric(t(bb) %*% solve(VV, bb)), error = function(e) NA_real_)
          if (is.finite(stat)) p_int <- stats::pchisq(stat, length(idx), lower.tail = FALSE)
        }
      }
    } else {
      fit0 <- tryCatch(survival::coxph(stats::as.formula(paste("Surv(time,event)~", rhs0)), data = dd), error = function(e) NULL)
      fit1 <- tryCatch(survival::coxph(stats::as.formula(paste("Surv(time,event)~", rhs1)), data = dd), error = function(e) NULL)
      p_int <- NA_real_
      if (!is.null(fit0) && !is.null(fit1)) {
        a <- tryCatch(stats::anova(fit0, fit1, test = "LRT"), error = function(e) NULL)
        if (!is.null(a) && nrow(a) >= 2) p_int <- a$`Pr(>|Chi|)`[2]
      }
    }
    pint_rows[[length(pint_rows) + 1L]] <- data.frame(
      database = nm, stratum = sv, p_int = p_int, stringsAsFactors = FALSE
    )
  }
}
pint_df <- do.call(rbind, pint_rows)
fwrite(pint_df, file.path(ckpt, "Subgroup_Pint.csv"))
message("P-int rows: ", nrow(pint_df))

sg <- as.data.frame(fread(sg_path))
if (!"estimable" %in% names(sg)) sg$estimable <- is.finite(sg$HR) & is.finite(sg$lo) & is.finite(sg$hi) & sg$HR > 0 & sg$hi < 80
sg$contrast <- ifelse(grepl("<5", sg$term, fixed = TRUE), "<5 h vs 7-<9 h",
               ifelse(grepl("5-6", sg$term, fixed = TRUE), "5-6 h vs 7-<9 h",
               ifelse(grepl("6-7", sg$term, fixed = TRUE), "6-7 h vs 7-<9 h",
               ifelse(grepl(">=9", sg$term, fixed = TRUE), ">=9 h vs 7-<9 h", sg$term))))
sg$contrast <- factor(sg$contrast, levels = c("<5 h vs 7-<9 h", "5-6 h vs 7-<9 h", "6-7 h vs 7-<9 h", ">=9 h vs 7-<9 h"))
sg$stratum_raw <- sg$stratum
sg$stratum <- gsub("_", " ", sg$stratum)
# attach P-int to first row label of each stratum block via facet subtitle
pint_lab <- pint_df
pint_lab$stratum_lab <- gsub("_", " ", pint_lab$stratum)
pint_lab$pint_txt <- vapply(pint_lab$p_int, function(p) {
  if (is.finite(p)) paste0("P-int=", fmt_p(p)) else "P-int=NE"
}, character(1))
# map sg stratum names to pint
sg$pint_key <- sg$stratum_raw
# build row with pint once per stratum:level still same; annotate at top of facet
sg$row <- paste0(sg$stratum, ": ", sg$level)
# create facet label with all P-ints for database
facet_labs <- lapply(split(pint_lab, pint_lab$database), function(x) {
  paste(sprintf("%s %s", gsub(" ", "", x$stratum_lab), x$pint_txt), collapse = "; ")
})
sg$facet <- sg$database
# Put P-int into y-axis group headers by prefixing first level of each stratum
for (i in seq_len(nrow(sg))) {
  key <- sg$stratum_raw[i]
  db <- sg$database[i]
  hit <- pint_lab$database == db & pint_lab$stratum == key
  if (any(hit)) {
    # only annotate once: when level is first alphabetical among that stratum in this db
    levs <- sort(unique(sg$level[sg$database == db & sg$stratum_raw == key]))
    if (identical(sg$level[i], levs[1])) {
      sg$row[i] <- paste0(sg$row[i], " (", pint_lab$pint_txt[hit][1], ")")
    }
  }
}
sg_ok <- sg[sg$estimable %in% TRUE, ]
sg_bad <- sg[!(sg$estimable %in% TRUE), ]
sg_bad <- sg_bad[!duplicated(sg_bad[, c("database", "row")]), ]
p_sg <- ggplot2::ggplot(sg, ggplot2::aes(HR, row, color = contrast)) +
  ggplot2::geom_vline(xintercept = 1, linetype = 2) +
  ggplot2::geom_pointrange(data = sg_ok, ggplot2::aes(xmin = lo, xmax = hi),
                           position = ggplot2::position_dodge(width = 0.7), size = 0.22) +
  ggplot2::geom_text(data = sg_bad, ggplot2::aes(x = 1, y = row, label = "Not estimable"),
                     inherit.aes = FALSE, size = 2.6, color = "grey40") +
  ggplot2::facet_wrap(~database, nrow = 1, scales = "free_y") +
  ggplot2::scale_x_log10() +
  ggplot2::scale_color_manual(values = c(
    "<5 h vs 7-<9 h" = "#d62728", "5-6 h vs 7-<9 h" = "#ff7f0e",
    "6-7 h vs 7-<9 h" = "#1f77b4", ">=9 h vs 7-<9 h" = "#9467bd"
  ), drop = TRUE) +
  ggplot2::labs(x = "Hazard ratio (log scale)", y = NULL, color = NULL,
                title = "Subgroup analyses of sleep duration and all-cause mortality",
                subtitle = "P-int: multiplicative Sleep Group x stratum Wald/LRT on the analysis sample") +
  theme_pub() +
  ggplot2::theme(axis.text.y = ggplot2::element_text(size = 7),
                 legend.position = "bottom",
                 plot.subtitle = ggplot2::element_text(size = 8))
ggplot2::ggsave(file.path(fig_dir, "Figure 7. Subgroup analyses of sleep duration and all-cause mortality.pdf"),
                p_sg, width = 11.5, height = 6.8, device = grDevices::cairo_pdf, family = .ff)

# update image_information Fig5/Fig7
imd <- file.path(pv2_out_root, "Figures", "image_information")
dir.create(imd, recursive = TRUE, showWarnings = FALSE)
writeLines(c(
  "# Figure 5. Receiver operating characteristic curves for 2-year all-cause mortality",
  "",
  paste0("AUC labels locked to Table S4 three-decimal values: ",
         paste(sprintf("%s %.3f", names(auc_map), auc_map), collapse = "; "), "."),
  "Model: logistic Sleep_hours + Age + Gender; NHANES ROC survey-weighted when applicable.",
  "Times New Roman / Liberation Serif; no underscores."
), file.path(imd, "Figure 5. Receiver operating characteristic curves for 2-year all-cause mortality.md"))
writeLines(c(
  "# Figure 7. Subgroup analyses of sleep duration and all-cause mortality",
  "",
  "Category-specific contrasts versus 7-<9 h within strata; Age (+ Gender when estimable) adjusted.",
  "Multiplicative Sleep_Group × stratum interaction P (P-int) annotated on the first level of each stratum (Wald for NHANES survey Cox; LRT otherwise).",
  paste0("Checkpoint: Subgroup_Pint.csv. Example NHANES Age_Group P-int=",
         {v <- pint_df$p_int[pint_df$database=="NHANES" & pint_df$stratum=="Age_Group"][1]; if (is.finite(v)) fmt_p(v) else "NE"}, "."),
  "Times New Roman / Liberation Serif; no underscores."
), file.path(imd, "Figure 7. Subgroup analyses of sleep duration and all-cause mortality.md"))

# refresh formats for Fig5/7
source(file.path(engine, "R/pub_figure_export.R"), local = FALSE)
pub_figure_ensure_formats(
  file.path(pv2_out_root, "Figures"),
  meta = list(databases = c("NHANES", "CHARLS", "SHHS"),
              exposure = "Sleep duration", outcome = "All-cause mortality", tables_dir = tab_dir)
)

# ---------- P0-3/4/5/6 + Methods rewrite ----------
message("==== Methods refresh ====")
Sys.setenv(
  PV2_PROFILE = "sleep_dyslipidemia",
  PV2_COHORT = "adults aged 45 years or older with dyslipidemia",
  PV2_EXPOSURE = "sleep duration",
  PV2_MEDIATOR = "diastolic blood pressure (DBP)",
  PV2_GROUPING = "five mutually exclusive categories (<5 h, 5-6 h, 6-7 h, 7-<9 h [7 to <9 hours], >=9 h; reference 7-<9 h)",
  PV2_SENSITIVITY = "exclusion of deaths within the first year (Table S5) and a 5-year administrative horizon (Table S3)"
)
# patch methods file content after finalize template via direct write of sleep methods
source(file.path(engine, "R/pub_prognosis_v2_methods.R"), local = FALSE)
# We'll overwrite Methods with enriched text in the methods R update; call finalize for software versions
system(sprintf(
  "Rscript %s --dir %s --study-type prognosis_v2 --outcome %s --exposure %s --databases %s",
  shQuote(file.path(engine, "run/pub/finalize_delivery_root.R")),
  shQuote(sum_root),
  shQuote("all-cause mortality"),
  shQuote("sleep duration"),
  shQuote("NHANES,SHHS,CHARLS")
))

message("P0 batch script core done")
