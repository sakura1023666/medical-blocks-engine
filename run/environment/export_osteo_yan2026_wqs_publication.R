###############################################################################
#  export_osteo_yan2026_wqs_publication.R
#  WQS 发表级表/图：对齐 Yan2026 Table3/4/Fig5/Fig6 版式；12 个中介全覆盖
#
#  "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
#    run/environment/export_osteo_yan2026_wqs_publication.R
###############################################################################

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}
script_path <- .init_script_dir()
root <- if (basename(script_path) == "environment" && basename(dirname(script_path)) == "run") {
  normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else script_path
setwd(root)
Sys.setenv(MEDICAL_BLOCKS_ROOT = root)

source(file.path(root, "R/moderated_mediation_process.R"))
modmed_ensure_pkgs(c("ggplot2", "openxlsx"))
suppressPackageStartupMessages(library(ggplot2))

`%||%` <- function(a, b) if (!is.null(a)) a else b

.resolve_g <- function(p) {
  if (.Platform$OS.type != "windows" && grepl("^[A-Za-z]:/", p)) {
    wsl <- paste0("/mnt/", tolower(substr(p, 1L, 1L)), substr(p, 3L, nchar(p)))
    if (dir.exists(wsl) || file.exists(wsl)) return(wsl)
  }
  p
}

base <- .resolve_g("G:/02block_result/04_Osteoarthritis/medition/yan2026_modmed_reproduce")
raw_base <- file.path(dirname(base), "data")
pub <- file.path(base, "WQS_only", "Publication")
tbl_dir <- file.path(pub, "Tables")
fig_dir <- file.path(pub, "Figures")
dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

mediators_12 <- c(
  "Creatinine_mol", "Red_blood_cells", "Mean_cell_hemoglobin", "TBIL_mol",
  "Total_Protein_gdL", "BUN_mol", "Potassium", "Sodium",
  "White_blood_cells", "Neutrophil_count", "Mononuclear_cell_count", "lymphocyte_count"
)

.pretty <- function(x) {
  map <- c(
    Creatinine_mol = "Creatinine",
    Red_blood_cells = "Red blood cell count",
    Mean_cell_hemoglobin = "Mean cell hemoglobin",
    TBIL_mol = "Total bilirubin",
    Total_Protein_gdL = "Total protein",
    BUN_mol = "Blood urea nitrogen",
    Potassium = "Potassium",
    Sodium = "Sodium",
    White_blood_cells = "WBC count",
    Neutrophil_count = "Neutrophil count",
    Mononuclear_cell_count = "Monocyte count",
    lymphocyte_count = "Lymphocyte count",
    WQS = "WQS index",
    Group_bin = "Osteoarthritis",
    Age = "Age", BMI = "BMI", Gender_num = "Gender", Gender = "Gender"
  )
  x <- as.character(x)
  ifelse(x %in% names(map), unname(map[x]), gsub("_", " ", x))
}

.fmt <- function(x, d = 3) {
  x <- as.numeric(x)
  vapply(x, function(z) {
    if (!is.finite(z)) return("—")
    formatC(round(z, d), format = "f", digits = d)
  }, character(1))
}
.fmt_p <- function(p) {
  p <- as.numeric(p)
  vapply(p, function(z) {
    if (!is.finite(z)) return("—")
    if (z < 0.001) "<0.001" else formatC(round(z, 3), format = "f", digits = 3)
  }, character(1))
}

# ── 美化 Excel（文献表风格：标题行 + 分组缩进 + 边框）──────────────────────
.save_lit_xlsx <- function(blocks, filepath, title, note = NULL) {
  # blocks: list of list(header=..., df=data.frame) or plain data.frame rows with .section
  dir.create(dirname(filepath), recursive = TRUE, showWarnings = FALSE)
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Table")
  style_title <- openxlsx::createStyle(fontSize = 12, textDecoration = "bold", wrapText = TRUE)
  style_header <- openxlsx::createStyle(
    fontSize = 10, textDecoration = "bold", halign = "center", valign = "center",
    border = "TopBottom", borderStyle = "thin", wrapText = TRUE
  )
  style_section <- openxlsx::createStyle(fontSize = 10, textDecoration = "bold")
  style_indent <- openxlsx::createStyle(fontSize = 10, indent = 1)
  style_body <- openxlsx::createStyle(fontSize = 10, halign = "center")
  style_note <- openxlsx::createStyle(fontSize = 9, textDecoration = "italic", wrapText = TRUE)

  openxlsx::writeData(wb, "Table", title, startRow = 1, startCol = 1)
  openxlsx::addStyle(wb, "Table", style_title, rows = 1, cols = 1)
  openxlsx::setRowHeights(wb, "Table", rows = 1, heights = 30)
  openxlsx::mergeCells(wb, "Table", cols = 1:8, rows = 1)

  r <- 3L
  for (blk in blocks) {
    if (!is.null(blk$section)) {
      openxlsx::writeData(wb, "Table", blk$section, startRow = r, startCol = 1)
      openxlsx::addStyle(wb, "Table", style_section, rows = r, cols = 1)
      r <- r + 1L
    }
    df <- blk$df
    if (is.null(df) || !nrow(df)) next
    if (isTRUE(blk$write_header %||% TRUE)) {
      openxlsx::writeData(wb, "Table", df, startRow = r, colNames = TRUE)
      openxlsx::addStyle(wb, "Table", style_header, rows = r, cols = seq_len(ncol(df)), gridExpand = TRUE)
      body_rows <- (r + 1L):(r + nrow(df))
      openxlsx::addStyle(wb, "Table", style_body, rows = body_rows, cols = seq_len(ncol(df)), gridExpand = TRUE)
      # first col left-indent look
      openxlsx::addStyle(wb, "Table", style_indent, rows = body_rows, cols = 1, gridExpand = TRUE, stack = TRUE)
      r <- r + nrow(df) + 2L
    } else {
      openxlsx::writeData(wb, "Table", df, startRow = r, colNames = FALSE)
      openxlsx::addStyle(wb, "Table", style_indent, rows = r:(r + nrow(df) - 1L), cols = 1, gridExpand = TRUE)
      openxlsx::addStyle(wb, "Table", style_body, rows = r:(r + nrow(df) - 1L), cols = 2:ncol(df), gridExpand = TRUE)
      r <- r + nrow(df) + 1L
    }
  }
  if (!is.null(note) && nzchar(note)) {
    openxlsx::writeData(wb, "Table", paste0("Note: ", note), startRow = r + 1L, startCol = 1)
    openxlsx::addStyle(wb, "Table", style_note, rows = r + 1L, cols = 1)
    openxlsx::mergeCells(wb, "Table", cols = 1:8, rows = r + 1L)
  }
  openxlsx::setColWidths(wb, "Table", cols = 1:10, widths = c(36, 12, 12, 12, 12, 14, 14, 12, 12, 12))
  openxlsx::saveWorkbook(wb, filepath, overwrite = TRUE)
  cli::cli_alert_success("Wrote {.file {basename(filepath)}}")
}

`%||%` <- function(a, b) if (!is.null(a)) a else b

# ── 数据 ────────────────────────────────────────────────────────────────────
med_all <- read.csv(file.path(base, "WQS_only/Tables/Table_WQS_Mediation_All.csv"), stringsAsFactors = FALSE)
med_sig <- read.csv(file.path(base, "WQS_only/Tables/Table_WQS_Mediation_Significant.csv"), stringsAsFactors = FALSE)
sp <- read.csv(file.path(base, "WQS_only/Tables/Table_WQS_Spearman_with_others.csv"), stringsAsFactors = FALSE)

e <- new.env(parent = emptyenv())
load(file.path(raw_base, "结局_8环境毒物_基线全指标.RData"), envir = e)
load(file.path(raw_base, "D01_WQS_Result.RData"), envir = e)
dat <- modmed_merge_wqs(e$merged, e$wqs_fit, "WQS")
dat$Group_bin <- modmed_encode_outcome(dat$Group, "Osteoarthritis", "Normal")
dat$Gender_num <- modmed_encode_gender_num(dat$Gender, "Male")

.path_ab <- function(d, x, m, y) {
  dd <- d[, c(x, m, y)]
  dd <- dd[stats::complete.cases(dd), ]
  fit_m <- stats::lm(stats::as.formula(paste(m, "~", x)), data = dd)
  fit_y <- stats::glm(stats::as.formula(paste(y, "~", x, "+", m)), data = dd, family = binomial())
  sm_m <- summary(fit_m)$coefficients
  sm_y <- summary(fit_y)$coefficients
  list(a = unname(sm_m[x, 1]), p_a = unname(sm_m[x, 4]),
       b = unname(sm_y[m, 1]), p_b = unname(sm_y[m, 4]), n = nrow(dd))
}

# ── 对 12 个中介 × Age/BMI/Gender 全量调节（文献 Table4 用）────────────────
cli::cli_h2("Computing moderation for all 12 mediators")
mod_rows <- list()
for (m in mediators_12) {
  for (w in c("Age", "BMI", "Gender_num")) {
    one <- tryCatch(
      modmed_moderation_tests(dat, "WQS", m, "Group_bin", w),
      error = function(e) NULL
    )
    if (!is.null(one)) mod_rows[[length(mod_rows) + 1L]] <- one
  }
}
mod_all12 <- do.call(rbind, mod_rows)
write.csv(mod_all12, file.path(base, "WQS_only/Tables/Table_WQS_Moderation_All12.csv"), row.names = FALSE)

# 总效应调节（文献 Table3：Y ~ X*W）—— OA 为 logit，报告交互系数
.fit_total_moderation <- function(d, y, x, w) {
  dd <- d[, c(y, x, w)]
  dd <- dd[stats::complete.cases(dd), ]
  if (w %in% c("Age", "BMI")) dd$Wc <- as.numeric(scale(dd[[w]], scale = FALSE)) else {
    dd$Wc <- as.numeric(dd[[w]])
  }
  # linear probability / or logit: paper used GLM; for continuous Y they used linear.
  # OA binary -> logit; also report linear for comparability of β scale notes
  fml <- stats::as.formula(paste0(y, " ~ ", x, " * Wc"))
  fit <- stats::glm(fml, data = dd, family = binomial())
  sm <- summary(fit)
  cf <- sm$coefficients
  rn <- rownames(cf)
  int <- rn[grepl(":", rn)][1]
  xrow <- rn[rn == x | startsWith(rn, paste0(x))][1]
  wrow <- rn[rn == "Wc" | grepl("^Wc", rn)][1]
  .row <- function(nm) {
    if (is.na(nm) || !nm %in% rn) return(c(NA, NA, NA, NA, NA))
    beta <- cf[nm, 1]; se <- cf[nm, 2]; z <- cf[nm, 3]; p <- cf[nm, 4]
    c(beta, se, z, p, beta - 1.96 * se, beta + 1.96 * se)
  }
  # F/R2 not natural for logit; report null deviance based pseudo
  list(
    n = nrow(dd),
    x = .row(xrow),
    w = .row(wrow),
    xw = .row(int),
    # LRT for interaction
    p_int = {
      f0 <- stats::glm(stats::as.formula(paste0(y, " ~ ", x, " + Wc")), data = dd, family = binomial())
      an <- tryCatch(anova(f0, fit, test = "Chisq"), error = function(e) NULL)
      if (is.null(an)) NA_real_ else as.numeric(an$`Pr(>Chi)`[2])
    }
  )
}

# ── Table 1 Spearman ────────────────────────────────────────────────────────
t1_df <- data.frame(
  Variable = vapply(sp$variable, .pretty, character(1)),
  `Spearman ρ` = .fmt(sp$spearman_r, 3),
  `P value` = .fmt_p(sp$p),
  check.names = FALSE
)
.save_lit_xlsx(
  list(list(df = t1_df)),
  file.path(tbl_dir, "Table 1. Spearman correlations of WQS index with biomarkers and osteoarthritis.xlsx"),
  "Table 1. Spearman correlations of WQS index with blood biomarkers and osteoarthritis",
  "Crude correlations; pairwise complete observations."
)

# ── Table 2 Mediation（12 个全列）──────────────────────────────────────────
t2_rows <- lapply(mediators_12, function(m) {
  r <- med_all[med_all$mediator == m, , drop = FALSE][1, ]
  ab <- .path_ab(dat, "WQS", m, "Group_bin")
  data.frame(
    Mediator = .pretty(m),
    N = r$n,
    `Path a β` = .fmt(ab$a),
    `Path a P` = .fmt_p(ab$p_a),
    `Path b β` = .fmt(ab$b),
    `Path b P` = .fmt_p(ab$p_b),
    `Indirect effect β` = .fmt(r$ACME),
    `Indirect 95%CI lower` = .fmt(r$ACME_lo),
    `Indirect 95%CI upper` = .fmt(r$ACME_hi),
    `Direct effect β` = .fmt(r$ADE),
    `Direct 95%CI lower` = .fmt(r$ADE_lo),
    `Direct 95%CI upper` = .fmt(r$ADE_hi),
    `Proportion mediated (%)` = .fmt(100 * r$prop_mediated, 2),
    Significant = ifelse(isTRUE(r$significant), "Yes", "No"),
    check.names = FALSE
  )
})
t2 <- do.call(rbind, t2_rows)
.save_lit_xlsx(
  list(list(df = t2)),
  file.path(tbl_dir, "Table 2. Mediation of WQS index on osteoarthritis via 12 blood biomarkers.xlsx"),
  "Table 2. Mediation analysis of WQS index and osteoarthritis via 12 blood biomarkers",
  "Bootstrap n=5000, bias-corrected CI, Crude Model. Significant = indirect-effect 95%CI excludes 0."
)

# ── Table 3（文献风格：Age 对结局的调节）───────────────────────────────────
# 对 OA：WQS*Age；并对每个中介作为 outcome 的线性模型 WQS*Age（类似文献 ALT/AST 两块）
make_table3_block <- function(outcome_label, fit_obj, is_binary = FALSE) {
  xw <- fit_obj$xw
  data.frame(
    Term = c(
      "X: WQS index",
      "W: Age",
      "X×W",
      if (is_binary) "P for interaction" else "P for X×W"
    ),
    β = c(.fmt(fit_obj$x[1]), .fmt(fit_obj$w[1]), .fmt(xw[1]), .fmt_p(fit_obj$p_int)),
    `β (95%CI) Lower` = c(.fmt(fit_obj$x[5]), .fmt(fit_obj$w[5]), .fmt(xw[5]), "—"),
    `β (95%CI) Upper` = c(.fmt(fit_obj$x[6]), .fmt(fit_obj$w[6]), .fmt(xw[6]), "—"),
    check.names = FALSE
  )
}

# Age moderation on each mediator (continuous) — paper Table3 style blocks
t3_blocks <- list()
# first: OA binary
fit_oa_age <- .fit_total_moderation(dat, "Group_bin", "WQS", "Age")
t3_blocks[[1]] <- list(
  section = "Osteoarthritis (binary outcome, logit)",
  df = make_table3_block("OA", fit_oa_age, TRUE),
  write_header = TRUE
)
# then each of 12 mediators as Y ~ WQS * Age (linear), matching paper ALT/AST layout
for (m in mediators_12) {
  dd <- dat[, c(m, "WQS", "Age")]
  dd <- dd[stats::complete.cases(dd), ]
  dd$Wc <- as.numeric(scale(dd$Age, scale = FALSE))
  fit <- stats::lm(stats::as.formula(paste0(m, " ~ WQS * Wc")), data = dd)
  sm <- summary(fit)
  cf <- sm$coefficients
  getc <- function(nm) {
    if (!nm %in% rownames(cf)) return(rep(NA_real_, 6))
    b <- cf[nm, 1]; se <- cf[nm, 2]; t <- cf[nm, 3]; p <- cf[nm, 4]
    c(b, se, t, p, b - 1.96 * se, b + 1.96 * se)
  }
  int_nm <- rownames(cf)[grepl(":", rownames(cf))][1]
  xrow <- getc("WQS"); wrow <- getc("Wc"); xw <- getc(int_nm)
  p_int <- if (!is.null(int_nm)) cf[int_nm, 4] else NA_real_
  df <- data.frame(
    Term = c("X: WQS index", "W: Age", "X×W", "F", "R²", "P for X×W"),
    β = c(.fmt(xrow[1]), .fmt(wrow[1]), .fmt(xw[1]), .fmt(sm$fstatistic[1], 3), .fmt(sm$r.squared, 3), .fmt_p(p_int)),
    `β (95%CI) Lower` = c(.fmt(xrow[5]), .fmt(wrow[5]), .fmt(xw[5]), "—", "—", "—"),
    `β (95%CI) Upper` = c(.fmt(xrow[6]), .fmt(wrow[6]), .fmt(xw[6]), "—", "—", "—"),
    check.names = FALSE
  )
  t3_blocks[[length(t3_blocks) + 1L]] <- list(
    section = .pretty(m),
    df = df,
    write_header = TRUE
  )
}
.save_lit_xlsx(
  t3_blocks,
  file.path(tbl_dir, "Table 3. Effect of age on WQS associations with osteoarthritis and 12 biomarkers.xlsx"),
  "Table 3. Effect of age on the associations of WQS index with osteoarthritis and blood biomarkers",
  "Aligned with Yan et al. Table 3 layout. For continuous biomarkers, linear models were used (X, W, X×W, F, R², P). For osteoarthritis, logistic models were used."
)

# BMI / Gender as supplementary Table S3
for (mod_nm in c("BMI", "Gender_num")) {
  blocks <- list()
  for (m in mediators_12) {
    dd <- dat[, c(m, "WQS", mod_nm)]
    dd <- dd[stats::complete.cases(dd), ]
    if (mod_nm == "BMI") dd$Wc <- as.numeric(scale(dd$BMI, scale = FALSE)) else dd$Wc <- as.numeric(dd$Gender_num)
    fit <- stats::lm(stats::as.formula(paste0(m, " ~ WQS * Wc")), data = dd)
    sm <- summary(fit); cf <- sm$coefficients
    int_nm <- rownames(cf)[grepl(":", rownames(cf))][1]
    getc <- function(nm) {
      if (is.na(nm) || !nm %in% rownames(cf)) return(rep(NA_real_, 6))
      b <- cf[nm, 1]; se <- cf[nm, 2]; c(b, se, cf[nm, 3], cf[nm, 4], b - 1.96 * se, b + 1.96 * se)
    }
    xw <- getc(int_nm)
    df <- data.frame(
      Term = c("X: WQS index", paste0("W: ", .pretty(mod_nm)), "X×W", "P for X×W"),
      β = c(.fmt(getc("WQS")[1]), .fmt(getc("Wc")[1]), .fmt(xw[1]), .fmt_p(xw[4])),
      `β (95%CI) Lower` = c(.fmt(getc("WQS")[5]), .fmt(getc("Wc")[5]), .fmt(xw[5]), "—"),
      `β (95%CI) Upper` = c(.fmt(getc("WQS")[6]), .fmt(getc("Wc")[6]), .fmt(xw[6]), "—"),
      check.names = FALSE
    )
    blocks[[length(blocks) + 1L]] <- list(section = .pretty(m), df = df, write_header = TRUE)
  }
  .save_lit_xlsx(
    blocks,
    file.path(tbl_dir, sprintf(
      "Table S3%s. Effect of %s on WQS associations with 12 biomarkers.xlsx",
      if (mod_nm == "BMI") "a" else "b", .pretty(mod_nm)
    )),
    sprintf("Table S3. Effect of %s on WQS–biomarker associations (12 mediators)", .pretty(mod_nm)),
    "Same layout as Table 3."
  )
}

# ── Table 4（文献风格：路径交互，12 个中介 × Age）──────────────────────────
# Paper labels: Outcome Variable | β SE t/Z P | CI
# For each mediator: section Mediator name with rows:
#   WQS × Age  (path a / literature path b)
#   Mediator × Age on OA (path b / literature path c)
#   WQS × Age on OA (path c' / literature path a)
t4_blocks <- list()
for (m in mediators_12) {
  sub <- mod_all12[mod_all12$mediator == m & mod_all12$moderator == "Age", ]
  if (!nrow(sub)) next
  # map path names to paper row labels
  lab_map <- c(
    a = paste0("WQS index × Age  (path b: WQS → ", .pretty(m), ")"),
    b = paste0(.pretty(m), " × Age  (path c: mediator → OA)"),
    c_prime = "WQS index × Age  (path a: WQS → OA | mediator)"
  )
  rows <- lapply(c("a", "b", "c_prime"), function(ph) {
    rr <- sub[sub$path == ph, ][1, ]
    data.frame(
      `Outcome / interaction` = lab_map[[ph]],
      β = .fmt(rr$beta),
      SE = .fmt(rr$se),
      `t/Z` = .fmt(rr$beta / rr$se),
      P = .fmt_p(rr$p),
      `β (95%CI) Lower` = .fmt(rr$ci_lo),
      `β (95%CI) Upper` = .fmt(rr$ci_hi),
      check.names = FALSE
    )
  })
  t4_blocks[[length(t4_blocks) + 1L]] <- list(
    section = .pretty(m),
    df = do.call(rbind, rows),
    write_header = TRUE
  )
}
.save_lit_xlsx(
  t4_blocks,
  file.path(tbl_dir, "Table 4. Effects of age on pathways in WQS mediation models for 12 biomarkers.xlsx"),
  "Table 4. Effects of age on the pathways in the process of WQS index affecting osteoarthritis (12 mediators)",
  "Layout aligned with Yan et al. Table 4. Path letters follow the paper Fig.5 convention: a = direct WQS→OA, b = WQS→mediator, c = mediator→OA. Red-arrow candidates are interactions with P<0.05."
)

# BMI / Gender path tables as Table S4
for (mod_nm in c("BMI", "Gender_num")) {
  blocks <- list()
  for (m in mediators_12) {
    sub <- mod_all12[mod_all12$mediator == m & mod_all12$moderator == mod_nm, ]
    if (!nrow(sub)) next
    lab_map <- c(
      a = paste0("WQS × ", .pretty(mod_nm), " (path b)"),
      b = paste0(.pretty(m), " × ", .pretty(mod_nm), " (path c)"),
      c_prime = paste0("WQS × ", .pretty(mod_nm), " (path a)")
    )
    rows <- lapply(c("a", "b", "c_prime"), function(ph) {
      rr <- sub[sub$path == ph, ][1, ]
      data.frame(
        Interaction = lab_map[[ph]],
        β = .fmt(rr$beta), SE = .fmt(rr$se), P = .fmt_p(rr$p),
        `β (95%CI) Lower` = .fmt(rr$ci_lo), `β (95%CI) Upper` = .fmt(rr$ci_hi),
        check.names = FALSE
      )
    })
    blocks[[length(blocks) + 1L]] <- list(section = .pretty(m), df = do.call(rbind, rows), write_header = TRUE)
  }
  .save_lit_xlsx(
    blocks,
    file.path(tbl_dir, sprintf(
      "Table S4%s. Effects of %s on WQS mediation pathways for 12 biomarkers.xlsx",
      if (mod_nm == "BMI") "a" else "b", .pretty(mod_nm)
    )),
    sprintf("Table S4. Effects of %s on WQS mediation pathways (12 mediators)", .pretty(mod_nm)),
    "Same path-letter convention as Table 4."
  )
}

# ── Table 5 Simple slopes（12 个中介 × Age）────────────────────────────────
ss_rows <- list()
for (m in mediators_12) {
  one <- tryCatch(modmed_simple_slopes_table(dat, "WQS", m, "Age"), error = function(e) NULL)
  if (is.null(one)) next
  one$Mediator <- .pretty(m)
  ss_rows[[length(ss_rows) + 1L]] <- one
}
ss_all <- do.call(rbind, ss_rows)
t5 <- data.frame(
  Mediator = ss_all$Mediator,
  Level = ss_all$w_level,
  `Age value` = .fmt(ss_all$w_value, 2),
  `Simple slope β` = .fmt(ss_all$slope),
  SE = .fmt(ss_all$se),
  P = .fmt_p(ss_all$p),
  `95%CI Lower` = .fmt(ss_all$ci_lo),
  `95%CI Upper` = .fmt(ss_all$ci_hi),
  check.names = FALSE
)
.save_lit_xlsx(
  list(list(df = t5)),
  file.path(tbl_dir, "Table 5. Simple slopes of WQS on 12 biomarkers at Age Mean plus minus 1SD.xlsx"),
  "Table 5. Simple slopes of WQS index on 12 blood biomarkers at low/mean/high Age (Mean±1SD)",
  "Levels are Mean−1SD, Mean, and Mean+1SD of Age. Corresponds to Figure 3 / Figure S3."
)

# ── Figure drawing: literature Fig.5 style ─────────────────────────────────────
draw_fig5 <- function(mediator, outfile, panel = NULL,
                      red_b = FALSE, red_c = FALSE, red_a = FALSE) {
  cols <- list(
    exposure = "#5B9BD5", mediator = "#7FBF3F", outcome = "#F4A460", moderator = "#F2C14E"
  )
  # layout matching reference image closely
  ex <- 1.15; ey <- 2.05
  mx <- 3.55; my <- 3.35
  ox <- 5.95; oy <- 2.05
  wx <- 3.55; wy <- 0.55

  # path segments (a direct, b up-left, c up-right)
  seg <- data.frame(
    x = c(ex + 0.72, mx + 0.05, ex + 0.78),
    y = c(ey + 0.28, my - 0.32, ey),
    xend = c(mx - 0.55, ox - 0.72, ox - 0.78),
    yend = c(my - 0.28, oy + 0.28, oy),
    lab = c("b", "c", "a"),
    stringsAsFactors = FALSE
  )

  # Age arrows to midpoints of paths; red if significant
  mid_b <- c(2.15, 2.75)
  mid_c <- c(4.95, 2.75)
  mid_a <- c(3.55, 2.05)
  arr <- data.frame(
    x = c(wx - 0.15, wx + 0.15, wx),
    y = c(wy + 0.28, wy + 0.28, wy + 0.32),
    xend = c(mid_b[1], mid_c[1], mid_a[1]),
    yend = c(mid_b[2] - 0.15, mid_c[2] - 0.15, mid_a[2] - 0.12),
    sig = c(red_b, red_c, red_a)
  )

  plt <- ggplot() +
    { if (!is.null(panel)) annotate("text", x = 0.25, y = 3.85, label = panel, fontface = "bold", size = 6.5, hjust = 0) else NULL } +
    # main path arrows
    geom_segment(
      data = seg, aes(x = x, y = y, xend = xend, yend = yend),
      arrow = grid::arrow(length = unit(0.22, "cm"), type = "closed"),
      linewidth = 1.05, color = "grey20", lineend = "round"
    ) +
    annotate("text", x = 2.05, y = 2.95, label = "b", size = 5, fontface = "bold") +
    annotate("text", x = 5.05, y = 2.95, label = "c", size = 5, fontface = "bold") +
    annotate("text", x = 3.55, y = 1.78, label = "a", size = 5, fontface = "bold") +
    # moderation arrows
    geom_segment(
      data = arr, aes(x = x, y = y, xend = xend, yend = yend, color = sig),
      arrow = grid::arrow(length = unit(0.20, "cm"), type = "closed"),
      linewidth = 1.15, show.legend = FALSE, lineend = "round"
    ) +
    scale_color_manual(values = c(`TRUE` = "#E31A1C", `FALSE` = "grey25")) +
    # nodes
    annotate("label", x = ex, y = ey, label = "WQS index",
             fill = cols$exposure, color = "white", fontface = "bold", size = 4.6,
             label.r = unit(0.55, "lines"), label.padding = unit(0.62, "lines"), linewidth = 0.4,
             label.size = 0.3) +
    annotate("label", x = mx, y = my, label = .pretty(mediator),
             fill = cols$mediator, color = "white", fontface = "bold", size = 4.2,
             label.r = unit(0.55, "lines"), label.padding = unit(0.55, "lines"), linewidth = 0.4) +
    annotate("label", x = ox, y = oy, label = "Osteoarthritis",
             fill = cols$outcome, color = "white", fontface = "bold", size = 4.6,
             label.r = unit(0.55, "lines"), label.padding = unit(0.62, "lines"), linewidth = 0.4) +
    annotate("label", x = wx, y = wy, label = "Age",
             fill = cols$moderator, color = "black", fontface = "bold", size = 4.6,
             label.r = unit(0.55, "lines"), label.padding = unit(0.55, "lines"), linewidth = 0.4) +
    coord_cartesian(xlim = c(0.15, 7.0), ylim = c(0.15, 4.05), expand = FALSE) +
    theme_void() +
    theme(plot.background = element_rect(fill = "white", color = NA),
          plot.margin = margin(6, 6, 6, 6))

  ggsave(outfile, plt, width = 7.6, height = 5.0, device = pdf, bg = "white")
}

draw_lit_mediation <- function(row, outfile, panel = "A") {
  ab <- .path_ab(dat, "WQS", row$mediator, "Group_bin")
  ind <- as.numeric(row$ACME); ind_lo <- as.numeric(row$ACME_lo); ind_hi <- as.numeric(row$ACME_hi)
  dir <- as.numeric(row$ADE); dir_lo <- as.numeric(row$ADE_lo); dir_hi <- as.numeric(row$ADE_hi)
  prop <- 100 * as.numeric(row$prop_mediated)
  cols <- list(exposure = "#5B9BD5", mediator = "#7FBF3F", outcome = "#F4A460")
  ex <- 1.2; ey <- 1.05; mx <- 3.5; my <- 2.65; ox <- 5.8; oy <- 1.05
  lab_top <- paste0("Indirect Effect = ", .fmt(ind), "\n95% CI: ", .fmt(ind_lo), " to ", .fmt(ind_hi))
  lab_bot <- paste0("Direct Effect = ", .fmt(dir), "\n95% CI: ", .fmt(dir_lo), " to ", .fmt(dir_hi))
  lab_prop <- paste0("Proportion of Mediation: ", .fmt(prop, 2), "%")
  seg <- data.frame(
    x = c(ex + 0.55, mx, ex + 0.7), y = c(ey + 0.35, my - 0.35, ey),
    xend = c(mx - 0.2, ox - 0.55, ox - 0.7), yend = c(my - 0.35, oy + 0.35, oy)
  )
  plt <- ggplot() +
    annotate("text", x = 0.3, y = 3.25, label = panel, fontface = "bold", size = 6, hjust = 0) +
    annotate("text", x = 3.5, y = 3.25, label = lab_top, size = 3.4, lineheight = 1.15) +
    annotate("text", x = 3.5, y = 0.32, label = lab_bot, size = 3.4, lineheight = 1.15) +
    annotate("text", x = 3.5, y = 1.55, label = lab_prop, size = 3.5, fontface = "bold") +
    annotate("label", x = ex, y = ey, label = "WQS index", fill = cols$exposure, color = "white",
             fontface = "bold", size = 4.3, label.r = unit(0.5, "lines"), label.padding = unit(0.55, "lines"), linewidth = 0.3) +
    annotate("label", x = mx, y = my, label = .pretty(row$mediator), fill = cols$mediator, color = "white",
             fontface = "bold", size = 4.0, label.r = unit(0.5, "lines"), label.padding = unit(0.5, "lines"), linewidth = 0.3) +
    annotate("label", x = ox, y = oy, label = "Osteoarthritis", fill = cols$outcome, color = "white",
             fontface = "bold", size = 4.3, label.r = unit(0.5, "lines"), label.padding = unit(0.55, "lines"), linewidth = 0.3) +
    geom_segment(data = seg, aes(x = x, y = y, xend = xend, yend = yend),
                 arrow = grid::arrow(length = unit(0.18, "cm"), type = "closed"),
                 linewidth = 0.95, color = "grey25") +
    coord_cartesian(xlim = c(0.2, 6.8), ylim = c(0.05, 3.45), expand = FALSE) +
    theme_void() + theme(plot.background = element_rect(fill = "white", color = NA))
  ggsave(outfile, plt, width = 7.2, height = 4.3, device = pdf, bg = "white")
}

draw_fig6 <- function(mediator, outfile) {
  d <- dat[, c("WQS", mediator, "Age")]
  names(d)[2] <- "M"
  d <- d[stats::complete.cases(d), ]
  fit <- stats::lm(M ~ WQS * Age, data = d)
  w_lo <- mean(d$WQS) - sd(d$WQS); w_hi <- mean(d$WQS) + sd(d$WQS)
  a_lo <- mean(d$Age) - sd(d$Age); a_hi <- mean(d$Age) + sd(d$Age)
  nd <- expand.grid(
    WQS_level = factor(c("Low WQS", "High WQS"), levels = c("Low WQS", "High WQS")),
    Age_level = factor(c("Low Age", "High Age"), levels = c("Low Age", "High Age"))
  )
  nd$WQS <- ifelse(nd$WQS_level == "Low WQS", w_lo, w_hi)
  nd$Age <- ifelse(nd$Age_level == "Low Age", a_lo, a_hi)
  nd$pred <- predict(fit, nd)
  plt <- ggplot(nd, aes(x = WQS_level, y = pred, group = Age_level, shape = Age_level)) +
    geom_line(linewidth = 0.85, color = "black") +
    geom_point(size = 3.2, fill = "white", color = "black") +
    scale_shape_manual(values = c(`Low Age` = 17, `High Age` = 22)) +
    labs(x = NULL, y = .pretty(mediator), shape = NULL) +
    theme_classic(base_size = 13) +
    theme(
      legend.position = c(0.80, 0.88),
      legend.background = element_blank(),
      axis.line = element_line(color = "black", linewidth = 0.6),
      panel.grid = element_blank()
    )
  ggsave(outfile, plt, width = 5.4, height = 4.3, device = pdf, bg = "white")
}

# ── Figures: mediation path (significant = Fig1; all 12 = Fig S1) ───────────
cli::cli_h2("Drawing figures")
sig_order <- med_sig[order(-med_sig$prop_mediated), ]
panels <- LETTERS[seq_len(nrow(sig_order))]
fig1_names <- c(
  BUN_mol = "Figure 1A. Mediation path diagram of WQS via blood urea nitrogen on osteoarthritis.pdf",
  TBIL_mol = "Figure 1B. Mediation path diagram of WQS via total bilirubin on osteoarthritis.pdf",
  Neutrophil_count = "Figure 1C. Mediation path diagram of WQS via neutrophil count on osteoarthritis.pdf",
  White_blood_cells = "Figure 1D. Mediation path diagram of WQS via WBC count on osteoarthritis.pdf"
)
for (i in seq_len(nrow(sig_order))) {
  m <- sig_order$mediator[i]
  fn <- fig1_names[[m]] %||% sprintf("Figure 1%s. Mediation path diagram of WQS via %s.pdf", panels[i], m)
  draw_lit_mediation(sig_order[i, ], file.path(fig_dir, fn), panel = panels[i])
  cli::cli_alert_success(basename(fn))
}

# Supplement: all 12 mediation diagrams
for (i in seq_along(mediators_12)) {
  m <- mediators_12[i]
  row <- med_all[med_all$mediator == m, ][1, ]
  fn <- sprintf("Figure S1%s. Mediation path diagram of WQS via %s on osteoarthritis.pdf",
                LETTERS[i], gsub(" ", "_", .pretty(m)))
  draw_lit_mediation(row, file.path(fig_dir, fn), panel = LETTERS[i])
}
cli::cli_alert_success("Figure S1A–L: all 12 mediation path diagrams")

# Fig 2 / S2: moderated mediation schematics for all 12 (Age)
for (i in seq_along(mediators_12)) {
  m <- mediators_12[i]
  sub <- mod_all12[mod_all12$mediator == m & mod_all12$moderator == "Age", ]
  red_b <- isTRUE(sub$significant[sub$path == "a"][1])
  red_c <- isTRUE(sub$significant[sub$path == "b"][1])
  red_a <- isTRUE(sub$significant[sub$path == "c_prime"][1])
  # main figures for those with any Age path significant
  any_sig <- red_b || red_c || red_a
  if (any_sig) {
    # keep BUN / Neu as Figure 2A/2B if they match
    main_fn <- if (m == "BUN_mol") {
      "Figure 2A. Moderated mediation model of WQS via BUN by Age.pdf"
    } else if (m == "Neutrophil_count") {
      "Figure 2B. Moderated mediation model of WQS via neutrophil by Age.pdf"
    } else {
      NULL
    }
    if (!is.null(main_fn)) {
      draw_fig5(m, file.path(fig_dir, main_fn), panel = if (m == "BUN_mol") "A" else "B",
                red_b = red_b, red_c = red_c, red_a = red_a)
      cli::cli_alert_success(main_fn)
    }
  }
  fn <- sprintf("Figure S2%s. Moderated mediation model of WQS via %s by Age.pdf",
                LETTERS[i], gsub(" ", "_", .pretty(m)))
  draw_fig5(m, file.path(fig_dir, fn), panel = LETTERS[i],
            red_b = red_b, red_c = red_c, red_a = red_a)
}
cli::cli_alert_success("Figure S2A–L: Age moderated-mediation schematics for 12 mediators")

# Fig 3 / S3: simple slopes for all 12
# Main: BUN + Neutrophil (Age a-path significant)
draw_fig6("BUN_mol", file.path(fig_dir, "Figure 3A. Simple slopes of Age moderation on WQS to BUN.pdf"))
draw_fig6("Neutrophil_count", file.path(fig_dir, "Figure 3B. Simple slopes of Age moderation on WQS to neutrophil.pdf"))
for (i in seq_along(mediators_12)) {
  m <- mediators_12[i]
  fn <- sprintf("Figure S3%s. Simple slopes of Age moderation on WQS to %s.pdf",
                LETTERS[i], gsub(" ", "_", .pretty(m)))
  draw_fig6(m, file.path(fig_dir, fn))
}
cli::cli_alert_success("Figure 3A/B + Figure S3A–L simple-slope plots")

# Manifest
manifest <- c(
  "WQS Publication deliverables (Yan2026-aligned)",
  "================================================",
  "",
  "[Main Tables]",
  "  Table 1. Spearman correlations ...",
  "  Table 2. Mediation ... via 12 blood biomarkers",
  "  Table 3. Effect of age ... (paper Table3 layout; OA + 12 biomarkers)",
  "  Table 4. Effects of age on pathways ... (paper Table4 layout; 12 mediators)",
  "  Table 5. Simple slopes ... 12 biomarkers at Age Mean+/-1SD",
  "",
  "[Supplementary Tables]",
  "  Table S3a/S3b. Effect of BMI / Gender (Table3 layout)",
  "  Table S4a/S4b. Effects of BMI / Gender on pathways (Table4 layout)",
  "",
  "[Main Figures]",
  "  Figure 1A–1D. Mediation path diagrams (4 significant mediators)",
  "  Figure 2A–2B. Moderated mediation schematics (Age; red = significant path)",
  "  Figure 3A–3B. Simple-slope interaction plots (Age)",
  "",
  "[Supplementary Figures]",
  "  Figure S1A–L. Mediation path diagrams for all 12 mediators",
  "  Figure S2A–L. Moderated mediation schematics (Age) for all 12 mediators",
  "  Figure S3A–L. Simple-slope plots (Age) for all 12 mediators",
  "",
  "Path-letter convention (paper Fig.5): a=direct WQS→OA, b=WQS→M, c=M→OA."
)
writeLines(manifest, file.path(pub, "00_清单_Table_Figure顺序.txt"), useBytes = TRUE)

cli::cli_h1("Done")
cli::cli_alert_info("{.file {pub}}")
