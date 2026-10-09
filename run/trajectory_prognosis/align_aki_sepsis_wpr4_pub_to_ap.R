#!/usr/bin/env Rscript
# Align AKI sepsis WPR(class=4) root Figures/Tables to AP WPR dual pub roles,
# keeping 4-class primary (no AP S7–S10 / Fig S9–S10 sensitivity extras).
#
# Target:
#   Figures: Fig1–4 + S1 KM, S2 cut(MIMIC-only), S3 subgroup, S4–S8 Weibull
#   Tables:  T1–T3 + S1–S6 (S5=by-class baseline, S6=posterior)
#   Labels:  AP primary style — Class1 = lowest-mortality (majority) … Class4 = highest
#            eICU remapped to MIMIC phenotypes (Hungarian on mean WPR + mortality)
#
#   Rscript run/trajectory_prognosis/align_aki_sepsis_wpr4_pub_to_ap.R

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(survival)
  library(openxlsx)
  library(cli)
})

`%||%` <- function(a, b) if (!is.null(a)) a else b

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

block_root <- {
  x <- Sys.getenv("BLOCK_RESULT_ROOT", "")
  if (nzchar(x) && dir.exists(x)) x
  else if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result"
  else "G:/02block_result"
}

index_root <- file.path(
  block_root,
  "44_AKI_SPESIS_CKD/Prognosis_Trajectory_38882552/tr/by_index/WPR(class=4)"
)
stopifnot(dir.exists(index_root))
cfg_path <- file.path(
  block_root, "44_AKI_SPESIS_CKD/Prognosis_Trajectory_38882552/tr/config.R"
)

source(file.path(.root, "R/utils.R"), local = FALSE)
source(file.path(.root, "R/trajectory_survival_utils.R"), local = FALSE)
source(file.path(.root, "R/trajectory_paper_tables.R"), local = FALSE)
source(file.path(.root, "R/pub_figure_export.R"), local = FALSE)
source(file.path(.root, "R/dual_db_combine_figures.R"), local = FALSE)
source(file.path(.root, "Blocks/26_trajectory/04block_trajectory_plot_jlcm.R"), local = FALSE)
if (file.exists(cfg_path)) source(cfg_path, local = FALSE)

fig_root <- file.path(index_root, "Figures")
tab_root <- file.path(index_root, "Tables")
arch_tab <- file.path(tab_root, "_archive_messy")
arch_fig <- file.path(fig_root, "_archive_pre_ap_align")
dir.create(fig_root, recursive = TRUE, showWarnings = FALSE)
dir.create(tab_root, recursive = TRUE, showWarnings = FALSE)
dir.create(arch_tab, recursive = TRUE, showWarnings = FALSE)
dir.create(arch_fig, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(tab_root, "Summary"), recursive = TRUE, showWarnings = FALSE)

# ── Class align (AP primary style: Class1 = lowest mortality) ───────────────
# MIMIC raw → display: 3→1, 1→2, 2→3, 4→4
# eICU matched to MIMIC phenotypes: 1→1, 3→2, 2→3, 4→4
align_df <- data.frame(
  db = c(rep("mimic", 4), rep("eicu", 4)),
  old_class = c(3L, 1L, 2L, 4L, 1L, 3L, 2L, 4L),
  new_class = c(1L, 2L, 3L, 4L, 1L, 2L, 3L, 4L),
  note = c(
    "majority low mort", "mid", "high WPR", "highest mort",
    "majority low mort", "mid-low WPR", "high WPR", "highest mort"
  ),
  stringsAsFactors = FALSE
)
align_fp <- file.path(tab_root, "Summary", "class_align_WPR.csv")
utils::write.csv(align_df, align_fp, row.names = FALSE)
cli_alert_success("Wrote {align_fp}")

.map_for <- function(db) {
  sub <- align_df[align_df$db == db, , drop = FALSE]
  stats::setNames(as.integer(sub$new_class), as.character(sub$old_class))
}

.load_m4 <- function(db) {
  f <- file.path(index_root, db, "step14_trajectory_jlcm/Data/D01_jlcm_WPR_models.RData")
  e <- new.env(parent = emptyenv())
  load(f, envir = e)
  list(
    m4 = trajectory_unwrap_jointlcmm(e$models_list_with_cov$m4),
    models = e$models_list_with_cov,
    md = as.data.frame(e$model_data_final)
  )
}

.load_long <- function(db) {
  f <- file.path(index_root, db, "step14_trajectory_jlcm/Data/D01_long_WPR_D_1.RData")
  e <- new.env(parent = emptyenv())
  load(f, envir = e)
  e$long
}

.patient_class <- function(db, cmap) {
  x <- .load_m4(db)
  md <- x$md
  id_map <- unique(md[, c("subject_id", "subject_id_num", "survival_28d", "survival_time_28d")])
  pp <- as.data.frame(x$m4$pprob)
  id_map$class_raw <- pp$class[match(id_map$subject_id_num, pp$subject_id_num)]
  id_map$class <- trajectory_apply_class_swap(id_map$class_raw, cmap)
  id_map
}

# ── 1) Regenerate Fig2 per DB with class_map ────────────────────────────────
.regen_fig2 <- function(db, db_lab, cmap) {
  x <- .load_m4(db)
  long <- .load_long(db)
  # long Class is often wrong/single; overwrite from pprob via subject_id
  pc <- .patient_class(db, cmap)
  # feed plot with Class = DISPLAY labels already applied in long for n/death annotation
  long2 <- long
  long2$Class <- pc$class[match(as.character(long2$subject_id), as.character(pc$subject_id))]
  # identity map for plot (already remapped in long$Class and need predictY remap from raw)
  # .tpj04_make_plot remaps pprob$class via class_map; long Class also remapped via same map
  # So pass RAW long Class from pprob for consistency:
  long3 <- long
  long3$Class <- pc$class_raw[match(as.character(long3$subject_id), as.character(pc$subject_id))]
  cov <- character(0)
  if (exists("trajectory_jlcm_cov_cols", mode = "function")) {
    cov <- trajectory_jlcm_cov_cols(list(), x$m4)
  }
  p <- .tpj04_make_plot(
    x$m4, long3, "WPR", 4L, 28L, "subject_id",
    font_family = "", cov_cols = cov, class_map = cmap, ylim = NULL
  )
  stopifnot(!is.null(p))
  out_db <- file.path(
    index_root, db, "Figures",
    sprintf("Figure 2-%s. Trajectory of WPR latent classes.pdf", db_lab)
  )
  ggplot2::ggsave(out_db, p, width = 7.2, height = 5.2, device = grDevices::cairo_pdf)
  # also _raw
  raw_dir <- file.path(index_root, db, "Figures", "_raw")
  dir.create(raw_dir, showWarnings = FALSE, recursive = TRUE)
  file.copy(out_db, file.path(raw_dir, "Figure Trajectory WPR latent classes.pdf"), overwrite = TRUE)
  cli_alert_success("Fig2 regenerated: {out_db}")
  invisible(out_db)
}

# ── 2) Remake KM ────────────────────────────────────────────────────────────
.regen_km <- function(db, db_lab, cmap) {
  pc <- .patient_class(db, cmap)
  dd <- pc
  dd$time <- pmin(as.numeric(dd$survival_time_28d), 28)
  dd$event <- as.integer(dd$survival_28d == 1L)
  dd$class_f <- factor(paste0("Class ", dd$class), levels = paste0("Class ", 1:4))
  dd <- dd[is.finite(dd$time) & dd$time > 0 & !is.na(dd$event) & !is.na(dd$class_f), ]
  fit <- survfit(Surv(time, event) ~ class_f, data = dd)
  # simple base R PDF to avoid survminer dependency issues
  cols <- c("#D55E00", "#E69F00", "#56B4E9", "#009E73")
  out_db <- file.path(
    index_root, db, "Figures",
    sprintf("Figure S1-%s. Kaplan Meier survival by trajectory class.pdf", db_lab)
  )
  grDevices::cairo_pdf(out_db, width = 7.2, height = 5.4)
  plot(
    fit, col = cols, lwd = 2, conf.int = FALSE, mark.time = TRUE,
    xlab = "Days since ICU admission", ylab = "Survival probability",
    main = sprintf("%s — KM by WPR trajectory class (4-class, aligned)", db_lab),
    xlim = c(0, 28), ylim = c(0, 1)
  )
  legend("bottomleft", legend = levels(dd$class_f), col = cols, lwd = 2, bty = "n")
  # log-rank
  sd <- survdiff(Surv(time, event) ~ class_f, data = dd)
  pval <- 1 - pchisq(sd$chisq, length(sd$n) - 1)
  mtext(sprintf("Log-rank P %s", ifelse(pval < 0.001, "< 0.001", sprintf("= %.3f", pval))), side = 3, line = 0.2)
  grDevices::dev.off()
  # events csv archive
  ev <- dd %>%
    group_by(class = as.integer(gsub("\\D", "", as.character(class_f)))) %>%
    summarise(
      n = n(), events = sum(event), censored = sum(event == 0L),
      event_rate = round(100 * mean(event), 2), .groups = "drop"
    ) %>%
    mutate(class = paste("Class", class))
  utils::write.csv(
    ev,
    file.path(index_root, db, "Tables", "_archive", "Table_KM_TrajectoryClass_WPR_Events.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    data.frame(chisq = unname(sd$chisq), df = length(sd$n) - 1, p_value = pval),
    file.path(index_root, db, "Tables", "_archive", "Table_KM_TrajectoryClass_WPR_LogRank.csv"),
    row.names = FALSE
  )
  cli_alert_success("KM regenerated: {out_db}")
  invisible(list(path = out_db, events = ev, p = pval))
}

# ── 3) Remake Table 3 piecewise Cox (shared cut=3, ref=Class1) ──────────────
.regen_table3 <- function(db, db_lab, cmap, cut = 3L) {
  pc <- .patient_class(db, cmap)
  dd <- pc
  dd$time <- pmin(as.numeric(dd$survival_time_28d), 28)
  dd$event <- as.integer(dd$survival_28d == 1L)
  dd$class <- factor(as.character(dd$class), levels = as.character(1:4))
  dd <- dd[is.finite(dd$time) & dd$time > 0 & !is.na(dd$event), ]
  dd$class <- stats::relevel(dd$class, ref = "1")

  fit_piece <- function(which_piece) {
    d <- dd
    if (which_piece == 1L) {
      # (0, cut]
      d$event2 <- ifelse(d$time <= cut, d$event, 0L)
      d$time2 <- pmin(d$time, cut)
    } else {
      # (cut, 28]
      keep <- d$time > cut
      d <- d[keep, , drop = FALSE]
      if (!nrow(d)) return(NULL)
      d$time2 <- d$time - cut
      d$event2 <- d$event
    }
    d <- d[d$time2 > 0, , drop = FALSE]
    if (nrow(d) < 10L || length(unique(d$class)) < 2L) return(NULL)
    fit <- tryCatch(
      coxph(Surv(time2, event2) ~ class, data = d),
      error = function(e) NULL
    )
    fit
  }
  fmt_hr <- function(fit) {
    if (is.null(fit)) return(rep("NE†", 3))
    s <- summary(fit)
    # coef rows class2, class3, class4
    rn <- rownames(s$coefficients)
    out <- setNames(rep("NE†", 3), c("2", "3", "4"))
    for (k in c("2", "3", "4")) {
      hit <- grep(paste0("class", k, "$|", k, "$"), rn)
      if (!length(hit)) next
      i <- hit[1]
      hr <- s$conf.int[i, 1]
      lo <- s$conf.int[i, 3]
      hi <- s$conf.int[i, 4]
      if (!is.finite(hr) || !is.finite(lo) || !is.finite(hi) || hr > 1e6) {
        out[[k]] <- "NE†"
      } else {
        out[[k]] <- sprintf("%.2f (%.2f, %.2f)", hr, lo, hi)
      }
    }
    out
  }
  h1 <- fmt_hr(fit_piece(1L))
  h2 <- fmt_hr(fit_piece(2L))
  body <- data.frame(
    Database = db_lab,
    `Trajectory class` = paste0("Class ", 2:4, " (ref = Class 1)"),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  body[[sprintf("(%s]", paste0("0,", cut))]] <- unname(h1)
  body[[sprintf("(%s]", paste0(cut, ",28"))]] <- unname(h2)

  title <- sprintf("Table 3-%s. Time-dependent HR for trajectory classes", db_lab)
  fp <- file.path(tab_root, paste0(title, ".xlsx"))
  # also db Tables
  fp_db <- file.path(index_root, db, "Tables", paste0(title, ".xlsx"))
  export_sci_table(
    body, fp, title = title, sheet = "Table3",
    table_footnotes = list(
      "4-class WPR labels aligned to AP primary style: Class 1 = lowest 28-day mortality (majority); Class 4 = highest.",
      "Dual-db class labels remapped so display Class k matches MIMIC phenotype (see Tables/Summary/class_align_WPR.csv).",
      sprintf("Shared piecewise cut = day %s (from dual-db shared_cut).", cut),
      "†NE = not estimable (quasi-complete separation)."
    )
  )
  if (!dir.exists(dirname(fp_db))) dir.create(dirname(fp_db), recursive = TRUE)
  file.copy(fp, fp_db, overwrite = TRUE)
  # archive csv
  arch <- file.path(index_root, db, "Tables", "_archive")
  dir.create(arch, showWarnings = FALSE, recursive = TRUE)
  utils::write.csv(
    data.frame(
      Index = "WPR", class = 2:4,
      class_label = paste0("Class ", 2:4, " (ref = Class 1)"),
      dataset = db_lab, cut = cut, ref_class = "1",
      early = unname(h1), late = unname(h2)
    ),
    file.path(arch, "Table_Piecewise_Cox_By_Class.csv"),
    row.names = FALSE
  )
  cli_alert_success("Table3 regenerated: {fp}")
  invisible(fp)
}

# ── 4) Table2 + S6 from JLCM with class_map ─────────────────────────────────
.regen_t2_s6 <- function(db, db_lab, cmap) {
  x <- .load_m4(db)
  # fake ctx for export helpers
  ctx <- list(config = if (exists("config")) config else list())
  t2_title <- sprintf("Table 2-%s. Metrics for determining the optimal number of classes", db_lab)
  t2_fp <- file.path(tab_root, paste0(t2_title, ".xlsx"))
  trajectory_export_table2_sci(
    ctx, x$models, t2_fp, t2_title, class_map = cmap
  )
  if (exists("render_queued_tables", mode = "function")) {
    try(render_queued_tables(ctx), silent = TRUE)
  }
  if (file.exists(t2_fp)) {
    file.copy(t2_fp, file.path(index_root, db, "Tables", basename(t2_fp)), overwrite = TRUE)
  }

  s6_title <- sprintf("Table S6-%s. Posterior classification table", db_lab)
  s6_fp <- file.path(tab_root, paste0(s6_title, ".xlsx"))
  trajectory_export_posterior_classification_sci(
    ctx, x$m4, s6_fp, s6_title, class_map = cmap
  )
  if (exists("render_queued_tables", mode = "function")) {
    try(render_queued_tables(ctx), silent = TRUE)
  }
  if (file.exists(s6_fp)) {
    file.copy(s6_fp, file.path(index_root, db, "Tables", basename(s6_fp)), overwrite = TRUE)
  }
  cli_alert_success("Table2 + S6 regenerated for {db_lab}")
}

# ── 5) Reorder S5 by-class columns according to class_align ─────────────────
.reorder_s5_columns <- function(src, dest, title, cmap) {
  if (!file.exists(src)) {
    cli_alert_warning("S5 source missing: {src}")
    return(invisible(FALSE))
  }
  old_for_new <- integer(4)
  for (old in names(cmap)) {
    old_for_new[as.integer(cmap[[old]])] <- as.integer(old)
  }
  # Python: strip drawings, permute Class1–4 columns, rewrite title/headers
  py <- paste(
    "import zipfile,re,shutil,tempfile,os,sys",
    "from pathlib import Path",
    "import openpyxl",
    sprintf("src=%s", shQuote(src, type = "cmd")),
    sprintf("dest=%s", shQuote(dest, type = "cmd")),
    sprintf("title=%s", shQuote(title, type = "cmd")),
    sprintf("old_for_new=%s", paste0("[", paste(old_for_new, collapse = ","), "]")),
    "td=tempfile.mkdtemp()",
    "zipfile.ZipFile(src).extractall(td)",
    "rels=Path(td)/'xl/worksheets/_rels'",
    "if rels.exists():",
    "  for f in rels.glob('*.rels'):",
    "    t=re.sub(r'<Relationship[^>]*drawings/drawing[^/]*/>','',f.read_text(errors=\"ignore\"))",
    "    f.write_text(t)",
    "shutil.rmtree(Path(td)/'xl/drawings', ignore_errors=True)",
    "clean=str(Path(td)/'clean.xlsx')",
    "shutil.make_archive(str(Path(td)/'c'), 'zip', td)",
    "os.replace(str(Path(td)/'c.zip'), clean)",
    "wb=openpyxl.load_workbook(clean)",
    "ws=wb.active",
    "hdr_i=None",
    "for i,row in enumerate(ws.iter_rows(min_row=1,max_row=min(12,ws.max_row or 1), values_only=True),1):",
    "  vals=[str(c) if c is not None else '' for c in row]",
    "  if any(re.search(r'^Class\\s*1|^Class1', v) for v in vals):",
    "    hdr_i=i; break",
    "if hdr_i is None:",
    "  shutil.copy2(src, dest); sys.exit(0)",
    "hdr=[ws.cell(hdr_i,c).value for c in range(1,(ws.max_column or 1)+1)]",
    "raw_cols={}",
    "for k in range(1,5):",
    "  for c,v in enumerate(hdr,1):",
    "    if v is None: continue",
    "    if re.search(rf'^Class\\s*{k}\\b|^Class{k}\\b', str(v)):",
    "      raw_cols[k]=c; break",
    "if len(raw_cols)<4:",
    "  shutil.copy2(src, dest); sys.exit(0)",
    "dest_slots=[raw_cols[j] for j in range(1,5)]",
    "src_slots=[raw_cols[old_for_new[j-1]] for j in range(1,5)]",
    "body_rows=list(range(1,(ws.max_row or 1)+1)); body_rows.remove(hdr_i)",
    "# snapshot source cells",
    "snap={c:[ws.cell(r,c).value for r in body_rows] for c in src_slots}",
    "for j,dc in enumerate(dest_slots):",
    "  sc=src_slots[j]",
    "  for bi,r in enumerate(body_rows):",
    "    ws.cell(r,dc).value=snap[sc][bi]",
    "  old=old_for_new[j]",
    "  old_h=str(hdr[raw_cols[old]-1] or '')",
    "  m=re.search(r'N\\s*=\\s*([0-9]+)', old_h, re.I)",
    "  ntxt=f'N={m.group(1)}' if m else ''",
    "  ws.cell(hdr_i,dc).value=(f'Class{j+1}\\n({ntxt})' if ntxt else f'Class{j+1}')",
    "ws.cell(1,1).value=title",
    "wb.save(dest)",
    "print('S5_OK')",
    sep = "\n"
  )
  # shQuote type cmd may be wrong on linux — use cat to tempfile
  pyf <- tempfile(fileext = ".py")
  writeLines(c(
    "import zipfile,re,shutil,tempfile,os,sys",
    "from pathlib import Path",
    "import openpyxl",
    sprintf("src = %s", deparse(src)),
    sprintf("dest = %s", deparse(dest)),
    sprintf("title = %s", deparse(title)),
    sprintf("old_for_new = [%s]", paste(old_for_new, collapse = ", ")),
    "td = tempfile.mkdtemp()",
    "zipfile.ZipFile(src).extractall(td)",
    "rels = Path(td) / 'xl' / 'worksheets' / '_rels'",
    "if rels.exists():",
    "    for f in rels.glob('*.rels'):",
    "        t = re.sub(r'<Relationship[^>]*drawings/drawing[^/]*/>', '', f.read_text(errors='ignore'))",
    "        f.write_text(t)",
    "shutil.rmtree(Path(td) / 'xl' / 'drawings', ignore_errors=True)",
    "clean = str(Path(td) / 'clean.xlsx')",
    "shutil.make_archive(str(Path(td) / 'c'), 'zip', td)",
    "os.replace(str(Path(td) / 'c.zip'), clean)",
    "wb = openpyxl.load_workbook(clean)",
    "ws = wb.active",
    "hdr_i = None",
    "for i, row in enumerate(ws.iter_rows(min_row=1, max_row=min(12, ws.max_row or 1), values_only=True), 1):",
    "    vals = [str(c) if c is not None else '' for c in row]",
    "    if any(re.search(r'^Class\\s*1|^Class1', v) for v in vals):",
    "        hdr_i = i",
    "        break",
    "if hdr_i is None:",
    "    shutil.copy2(src, dest); print('S5_COPY'); sys.exit(0)",
    "hdr = [ws.cell(hdr_i, c).value for c in range(1, (ws.max_column or 1) + 1)]",
    "raw_cols = {}",
    "for k in range(1, 5):",
    "    for c, v in enumerate(hdr, 1):",
    "        if v is None: continue",
    "        if re.search(rf'^Class\\s*{k}\\b|^Class{k}\\b', str(v)):",
    "            raw_cols[k] = c; break",
    "if len(raw_cols) < 4:",
    "    shutil.copy2(src, dest); print('S5_COPY'); sys.exit(0)",
    "dest_slots = [raw_cols[j] for j in range(1, 5)]",
    "src_slots = [raw_cols[old_for_new[j - 1]] for j in range(1, 5)]",
    "body_rows = list(range(1, (ws.max_row or 1) + 1)); body_rows.remove(hdr_i)",
    "snap = {c: [ws.cell(r, c).value for r in body_rows] for c in src_slots}",
    "for j, dc in enumerate(dest_slots):",
    "    sc = src_slots[j]",
    "    for bi, r in enumerate(body_rows):",
    "        ws.cell(r, dc).value = snap[sc][bi]",
    "    old = old_for_new[j]",
    "    old_h = str(hdr[raw_cols[old] - 1] or '')",
    "    m = re.search(r'N\\s*=\\s*([0-9]+)', old_h, re.I)",
    "    ntxt = f'N={m.group(1)}' if m else ''",
    "    ws.cell(hdr_i, dc).value = (f'Class{j + 1}\\n({ntxt})' if ntxt else f'Class{j + 1}')",
    "ws.cell(1, 1).value = title",
    "wb.save(dest)",
    "print('S5_OK')"
  ), pyf)
  rc <- system2("python3", pyf, stdout = TRUE, stderr = TRUE)
  if (!any(grepl("S5_OK|S5_COPY", paste(rc, collapse = " ")))) {
    cli_alert_warning("S5 reorder failed; copying source. {paste(rc, collapse=' | ')}")
    file.copy(src, dest, overwrite = TRUE)
    return(invisible(FALSE))
  }
  # strip xml:space after openpyxl
  if (exists("pub_xlsx_strip", mode = "function")) {
    try(pub_xlsx_strip(dest), silent = TRUE)
  } else if (file.exists(file.path(.root, "R/pub_xlsx_surgical.R"))) {
    try({
      source(file.path(.root, "R/pub_xlsx_surgical.R"), local = TRUE)
      if (exists("pub_xlsx_strip", mode = "function")) pub_xlsx_strip(dest)
    }, silent = TRUE)
  }
  cli_alert_success("S5 reordered: {basename(dest)}")
  invisible(TRUE)
}

# ── Run per-DB regenerations ────────────────────────────────────────────────
km_notes <- list()
for (db in c("mimic", "eicu")) {
  db_lab <- if (db == "mimic") "MIMIC" else "eICU"
  cmap <- .map_for(db)
  cli_h2("{db_lab}: class_map = {paste(names(cmap), cmap, sep='→', collapse=', ')}")
  .regen_fig2(db, db_lab, cmap)
  km_notes[[db]] <- .regen_km(db, db_lab, cmap)
  .regen_table3(db, db_lab, cmap, cut = 3L)
  .regen_t2_s6(db, db_lab, cmap)

  # S5 from existing by-class baseline (prefer S7, else S10)
  cands <- c(
    file.path(tab_root, sprintf("Table S7-%s. Baseline characteristics by trajectory class (WPR).xlsx", db_lab)),
    file.path(tab_root, sprintf("Table S10-%s. Baseline characteristics by trajectory class (WPR).xlsx", db_lab)),
    file.path(index_root, db, "Tables", sprintf("Table S7-%s. Baseline characteristics by trajectory class (WPR).xlsx", db_lab))
  )
  src <- cands[file.exists(cands)][1]
  s5_title <- sprintf("Table S5-%s. Baseline characteristics by trajectory class (WPR)", db_lab)
  s5_fp <- file.path(tab_root, paste0(s5_title, ".xlsx"))
  .reorder_s5_columns(src, s5_fp, s5_title, cmap)
  file.copy(s5_fp, file.path(index_root, db, "Tables", basename(s5_fp)), overwrite = TRUE)
}

# ── 6) Figure renumber at db level + restage root + compose ──────────────────
# Archive current root PDFs
old_root_pdfs <- list.files(fig_root, pattern = "\\.pdf$", full.names = TRUE)
if (length(old_root_pdfs)) {
  file.copy(old_root_pdfs, file.path(arch_fig, basename(old_root_pdfs)), overwrite = TRUE)
  unlink(old_root_pdfs)
}
# Also clear four-dir stale
for (sub in c("pdf", "png", "tiff", "image_information")) {
  d <- file.path(fig_root, sub)
  if (dir.exists(d) && sub != "image_information") {
    # will regenerate
  }
}

# Rename db-level figures to AP numbering (except Fig2/S1 already written with new names)
.renumber_db_figs <- function(db, db_lab) {
  fdir <- file.path(index_root, db, "Figures")
  # Map old stem → new stem (without DB tag)
  pairs <- list(
    c("Figure S2-", "Figure S1-"), # KM — may already be S1 from regen
    c("Figure S3-", "Figure S2-"), # cut
    c("Figure S4-", "Figure S3-"), # subgroup
    c("Figure S5-", "Figure S4-"), # weibull auc
    c("Figure S6-", "Figure S5-"),
    c("Figure S7-", "Figure S6-"),
    c("Figure S8-", "Figure S7-"),
    c("Figure S9-", "Figure S8-")
  )
  # Delete Missing overview
  unlink(list.files(fdir, pattern = "Missing value overview", full.names = TRUE))
  # If old S2 KM still exists and new S1 exists, drop old S2 KM
  unlink(list.files(fdir, pattern = sprintf("^Figure S2-%s\\. Kaplan", db_lab), full.names = TRUE))
  # Rename S3→S2 ... S9→S8 carefully from high to low to avoid clobber
  for (i in rev(seq_along(pairs))) {
    old_pref <- pairs[[i]][1]
    new_pref <- pairs[[i]][2]
    # skip KM pair (already handled)
    if (grepl("S2-", old_pref) && grepl("S1-", new_pref)) next
    files <- list.files(fdir, pattern = paste0("^", gsub("-", "\\\\-", old_pref), db_lab), full.names = TRUE)
    for (fp in files) {
      bn <- basename(fp)
      nb <- sub(old_pref, new_pref, bn, fixed = TRUE)
      # avoid overwriting if target exists from previous run
      target <- file.path(fdir, nb)
      if (file.exists(target) && !identical(fp, target)) unlink(target)
      file.rename(fp, target)
      cli_alert_info("{db}: {bn} → {nb}")
    }
  }
}

for (db in c("mimic", "eicu")) {
  db_lab <- if (db == "mimic") "MIMIC" else "eICU"
  .renumber_db_figs(db, db_lab)
}

# Stage tagged PDFs into root (flat), then compose
unlink(list.files(fig_root, pattern = "\\.pdf$", full.names = TRUE))
# keep dual Fig1 if present in arch or db — prefer existing dual Fig1 from archive if any
fig1_arch <- file.path(arch_fig, "Figure 1. Flowchart of patient selection.pdf")
fig1_db_m <- file.path(index_root, "mimic", "Figures", "Figure 1-MIMIC. Flowchart of patient selection.pdf")
fig1_db_e <- file.path(index_root, "eicu", "Figures", "Figure 1-eICU. Flowchart of patient selection.pdf")
if (file.exists(fig1_arch)) {
  file.copy(fig1_arch, file.path(fig_root, "Figure 1. Flowchart of patient selection.pdf"), overwrite = TRUE)
}

for (db in c("eicu", "mimic")) {
  db_lab <- if (db == "eicu") "eICU" else "MIMIC"
  srcs <- list.files(
    file.path(index_root, db, "Figures"),
    pattern = sprintf("^Figure .+-%s\\. .+\\.pdf$", db_lab),
    full.names = TRUE
  )
  srcs <- srcs[!grepl("^Figure 1-", basename(srcs))]
  srcs <- srcs[!grepl("Missing value overview", basename(srcs), ignore.case = TRUE)]
  # S2 cut: keep only MIMIC at root compose step
  if (identical(db, "eicu")) {
    srcs <- srcs[!grepl("^Figure S2-eICU\\. Piecewise", basename(srcs))]
  }
  for (fp in srcs) file.copy(fp, file.path(fig_root, basename(fp)), overwrite = TRUE)
}

cfg <- if (exists("config")) config else list()
cfg$dual_db <- cfg$dual_db %||% list()
cfg$dual_db$combine_figures <- list(
  enable = TRUE,
  remove_singles = TRUE,
  drop_missing_overview = TRUE,
  panel_order = "secondary_first",
  layout_by_role = list(
    Trajectory = "stack",
    Dynpred = "stack",
    "Dynamic prediction" = "stack",
    "Kaplan Meier" = "stack",
    "latent classes" = "stack",
    Subgroup = "stack",
    Weibull = "stack"
  )
)
comb <- tryCatch(
  dual_db_combine_paired_figures(index_root, cfg, figures_dir = fig_root),
  error = function(e) {
    cli_alert_warning("combine failed: {e$message}")
    NULL
  }
)

# Force MIMIC-only S2 cut into root
cut_src <- file.path(index_root, "mimic", "Figures", "Figure S2-MIMIC. Piecewise Cox cut point search.pdf")
if (file.exists(cut_src)) {
  file.copy(cut_src, file.path(fig_root, "Figure S2. Piecewise Cox cut point search.pdf"), overwrite = TRUE)
  unlink(list.files(fig_root, pattern = "Figure S2-eICU", full.names = TRUE))
  unlink(list.files(fig_root, pattern = "Figure S2-MIMIC", full.names = TRUE))
}

# Ensure Fig1 dual exists
if (!file.exists(file.path(fig_root, "Figure 1. Flowchart of patient selection.pdf"))) {
  if (file.exists(fig1_db_m) && file.exists(fig1_db_e)) {
    .dual_db_compose_pair_pdf(
      fig1_db_m, fig1_db_e,
      file.path(fig_root, "Figure 1. Flowchart of patient selection.pdf"),
      layout = "side", label_a = "A. MIMIC", label_b = "B. eICU"
    )
  }
}

# Drop any leftover singles / old S9 / missing
unlink(list.files(fig_root, pattern = "Figure S9", full.names = TRUE))
unlink(list.files(fig_root, pattern = "Missing", full.names = TRUE))
unlink(list.files(fig_root, pattern = "-MIMIC\\.|-eICU\\.", full.names = TRUE))

# ── 7) Tables cleanup to T1–T3 + S1–S6 only ─────────────────────────────────
wanted_patterns <- c(
  "^Table 1-",
  "^Table 2-",
  "^Table 3-",
  "^Table S1-.*after multiple imputation",
  "^Table S2-.*Normality",
  "^Table S3-.*Univariate",
  "^Table S4-.*univariate screen",
  "^Table S5-.*by trajectory class",
  "^Table S6-.*Posterior"
)

all_tabs <- list.files(tab_root, pattern = "\\.xlsx$", full.names = TRUE)
keep <- logical(length(all_tabs))
for (i in seq_along(all_tabs)) {
  bn <- basename(all_tabs[i])
  keep[i] <- any(vapply(wanted_patterns, function(p) grepl(p, bn, ignore.case = TRUE), logical(1)))
}
# Prefer canonical S1 name; archive duplicates
for (fp in all_tabs[!keep]) {
  file.copy(fp, file.path(arch_tab, basename(fp)), overwrite = TRUE)
  unlink(fp)
}
# Archive non-canonical S1 "before and after imputation" short name if both exist
s1_long <- list.files(tab_root, pattern = "^Table S1-.*after multiple imputation\\.xlsx$", full.names = TRUE)
s1_short <- list.files(tab_root, pattern = "^Table S1-.*before and after imputation\\.xlsx$", full.names = TRUE)
s1_short <- setdiff(s1_short, s1_long)
if (length(s1_long) && length(s1_short)) {
  for (fp in s1_short) {
    file.copy(fp, file.path(arch_tab, basename(fp)), overwrite = TRUE)
    unlink(fp)
  }
}
# Remove multivariate / VIF final if somehow still matching — already excluded by patterns

# Ensure T1 and S2–S4 exist: copy from db folders if missing at root
.copy_if_absent <- function(pattern) {
  hits <- list.files(tab_root, pattern = pattern, full.names = TRUE)
  if (length(hits)) return(invisible(NULL))
  for (db in c("mimic", "eicu")) {
    srcs <- list.files(file.path(index_root, db, "Tables"), pattern = pattern, full.names = TRUE)
    for (s in srcs) file.copy(s, file.path(tab_root, basename(s)), overwrite = TRUE)
  }
}
.copy_if_absent("^Table 1-")
.copy_if_absent("^Table S2-.*Normality")
.copy_if_absent("^Table S3-.*Univariate")
.copy_if_absent("^Table S4-.*univariate screen")
.copy_if_absent("^Table S1-.*after multiple imputation")

# ── 8) Four-dir export + image_information ──────────────────────────────────
cfg2 <- if (exists("config")) config else list()
tryCatch(
  pub_figure_ensure_formats(fig_root, config = cfg2),
  error = function(e) cli_alert_warning("pub_figure_ensure_formats: {e$message}")
)

# Write concise image_information for key class figures
.imdir <- file.path(fig_root, "image_information")
dir.create(.imdir, showWarnings = FALSE, recursive = TRUE)
.km_m <- km_notes$mimic$events
.km_e <- km_notes$eicu$events
.write_md <- function(name, body) {
  writeLines(body, file.path(.imdir, name), useBytes = TRUE)
}
.write_md("Figure 2. Trajectory of WPR latent classes.md", c(
  "# Figure 2. Trajectory of WPR latent classes",
  "",
  "## 图面说明",
  "本图为 4 类 WPR 轨迹均值曲线双库拼图（A. MIMIC，B. eICU）。",
  "类别标签对齐 AP 主文口径：Class 1 = 最低 28 天死亡（多数类），Class 4 = 最高死亡；",
  "eICU 已按 MIMIC 表型重标（见 Tables/Summary/class_align_WPR.csv）。",
  "配色：Class1 橙、Class2 黄、Class3 蓝、Class4 绿。",
  "",
  "## 分析上下文",
  "- 暴露: WPR 4-class latent trajectory (primary for this folder)",
  "- 结局: 28-day in-hospital death",
  "- Grouping: 4-class; labels aligned across MIMIC/eICU",
  "- 数据库: MIMIC, eICU",
  "- 是否拼图: 是"
))
.write_md("Figure S1. Kaplan Meier survival by trajectory class.md", c(
  "# Figure S1. Kaplan Meier survival by trajectory class",
  "",
  "## 图面说明",
  "4 类 WPR 轨迹 KM 双库拼图；类标签与 Figure 2 / Table 3 / Table S5–S6 一致。",
  sprintf(
    "MIMIC 事件率：%s",
    paste(sprintf("%s %.1f%% (n=%s)", .km_m$class, .km_m$event_rate, .km_m$n), collapse = "; ")
  ),
  sprintf(
    "eICU 事件率：%s",
    paste(sprintf("%s %.1f%% (n=%s)", .km_e$class, .km_e$event_rate, .km_e$n), collapse = "; ")
  ),
  "",
  "## 分析上下文",
  "- 暴露: WPR 4-class",
  "- 结局: 28-day death",
  "- Grouping: 4-class aligned",
  "- 数据库: MIMIC, eICU",
  "- 是否拼图: 是"
))

# README
readme <- c(
  "# Tables / Figures（WPR 4-class，对齐 AP 角色）",
  "",
  "角色对齐 `41_AP/.../by_index/WPR`，但本文件夹主分析为 **4 类**；",
  "**不含** AP 的 S7–S9 / Fig S9–S10 等敏感性补充。",
  "",
  "## Figures（至 S8）",
  "| 编号 | 内容 | 口径 |",
  "|---|---|---|",
  "| Figure 1 | 纳排流程图 | 双库拼图 |",
  "| Figure 2 | 4 类 WPR 轨迹 | 双库；类标签已对齐 |",
  "| Figure 3 | 动态预测 | 双库 |",
  "| Figure 4 | 个体动态预测 | 双库 |",
  "| Figure S1 | KM by class | 双库 |",
  "| Figure S2 | 分段 Cox 切点搜索 | **仅 MIMIC** |",
  "| Figure S3 | 亚组 | 双库 |",
  "| Figure S4–S8 | Weibull AUC/C-index/Acc/Sens/Spec | 双库 |",
  "",
  "## Tables（至 S6）",
  "| 编号 | 内容 | 口径 |",
  "|---|---|---|",
  "| Table 1 | 基线特征 | 双库 |",
  "| Table 2 | 选类指标；Class 占比按 class_align | 双库 |",
  "| Table 3 | 分段/时变 HR（ref=Class1） | 双库 |",
  "| Table S1 | 插补前后基线 | 双库 |",
  "| Table S2 | 正态性 | 双库 |",
  "| Table S3 | 单因素 | 双库 |",
  "| Table S4 | VIF（单因素筛） | 双库 |",
  "| Table S5 | 按轨迹类基线 | 双库；列已按 align 重排 |",
  "| Table S6 | 后验分类表 | 双库 |",
  "",
  "## 类标签规则",
  "Class 1 = 最低 28 天死亡（多数低危，对齐 AP 主文 Fig2 口径）；Class 4 = 最高死亡。",
  "映射见 `Tables/Summary/class_align_WPR.csv`。",
  "",
  sprintf("整理时间: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
)
writeLines(readme, file.path(tab_root, "README.md"), useBytes = TRUE)
writeLines(readme, file.path(fig_root, "image_information", "README.md"), useBytes = TRUE)

cli_alert_success("AP-role alignment done (4-class, Fig≤S8, Table≤S6): {index_root}")
cli_alert_info("Root figures: {paste(list.files(fig_root, pattern='\\\\.pdf$'), collapse='; ')}")
cli_alert_info("Root tables: {paste(list.files(tab_root, pattern='\\\\.xlsx$'), collapse='; ')}")
