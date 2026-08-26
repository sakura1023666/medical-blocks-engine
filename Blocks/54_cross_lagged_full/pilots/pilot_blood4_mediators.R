#!/usr/bin/env Rscript
# pilot_blood4_mediators.R
# 试验：三库共有四血检（HbA1c / HDL / Total_Cholesterol / CRP）作中介
# 与当前 Depression 中介对照（同一纵向分析人群 + Age+Alcohol_drinking）
#
# 用法：
#   Rscript Blocks/54_cross_lagged_full/pilots/pilot_blood4_mediators.R \
#     --study-root ".../16_Hip_fracture_cross-laged_40595747_allages" \
#     --sims 200
#
# 产出（不覆盖正式 S6/S7）：
#   summary_result/table/Pilot_blood4_mediation_vs_depression.csv|xlsx
#   phase3_long_*/Tables/Pilot_blood4_*.rds

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) return(normalizePath(dirname(sub("^--file=", "", f[1L])), winslash = "/"))
  normalizePath(getwd(), winslash = "/")
}
script_path <- .init_script_dir()
root <- {
  if (basename(script_path) == "pilots" &&
      grepl("54_cross_lagged", basename(dirname(script_path)), fixed = TRUE))
    normalizePath(file.path(script_path, "..", "..", ".."), winslash = "/")
  else if (basename(script_path) == "cross_lagged" && basename(dirname(script_path)) == "run")
    normalizePath(file.path(script_path, "..", ".."), winslash = "/")
  else if (nzchar(Sys.getenv("MEDICAL_BLOCKS_ROOT", "")))
    normalizePath(Sys.getenv("MEDICAL_BLOCKS_ROOT"), winslash = "/")
  else normalizePath(getwd(), winslash = "/")
}
setwd(root)

args <- commandArgs(trailingOnly = TRUE)
study_root <- Sys.getenv(
  "CROSS_LAGGED_STUDY_ROOT",
  unset = "/mnt/e/01block/01Block-new-Final/Output/16_Hip_fracture_cross-laged_40595747_allages"
)
sims <- 200L
i <- 1L
while (i <= length(args)) {
  if (args[[i]] == "--study-root" && i < length(args)) {
    study_root <- args[[i + 1L]]; i <- i + 2L
  } else if (args[[i]] == "--sims" && i < length(args)) {
    sims <- as.integer(args[[i + 1L]]); i <- i + 2L
  } else i <- i + 1L
}
study_root <- normalizePath(study_root, winslash = "/", mustWork = TRUE)
data_root <- file.path(study_root, "data")
out_tab <- file.path(study_root, "summary_result", "table")
dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/cross_lagged_fi_item_labels.R"))
source(file.path(root, "Blocks/54_cross_lagged_full/14block_cross_lagged_long_prepare.R"))
source(file.path(root, "Blocks/20_mediation/06block_mediation_longitudinal.R"))

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

options(warn = 1, cli.hyperlink = FALSE)

# 四共有血检（ELSA 用 HSCRP 映射为 CRP）
.BLOOD4 <- c("HbA1c", "HDL", "Total_Cholesterol", "CRP")
.BLOOD_LABEL <- c(
  HbA1c = "HbA1c",
  HDL = "HDL-C",
  Total_Cholesterol = "Total cholesterol",
  CRP = "CRP"
)

panel <- list(
  CHARLS = list(
    baseline_year = 2011L, country = "China",
    dep_file = "CHARLS_2013_抑郁.csv", dep_id = "ID", dep_score = "cesd10_total",
    years = list(
      list(year = 2011L, id_col = "ID",
           frailty_csv = file.path(data_root, "CHARLS/虚弱_charls_2011.csv"),
           outcome_rdata = file.path(data_root, "CHARLS/D03_result_CHARLS_2011.RData")),
      list(year = 2015L, id_col = "ID",
           frailty_csv = file.path(data_root, "CHARLS/虚弱_charls_2015.csv"),
           outcome_rdata = file.path(data_root, "CHARLS/D03_result_CHARLS_2015.RData"))
    )
  ),
  ELSA = list(
    baseline_year = 2004L, country = "UK",
    dep_file = "ELSA_wave3_抑郁.csv", dep_id = "idauniq", dep_score = "cesd8_total",
    years = list(
      list(year = 2004L, id_col = "idauniq",
           frailty_csv = file.path(data_root, "ELSA/虚弱_elsa_wave2.csv"),
           outcome_rdata = file.path(data_root, "ELSA/D03_result_ELSA2.RData")),
      list(year = 2008L, id_col = "idauniq",
           frailty_csv = file.path(data_root, "ELSA/虚弱_elsa_wave4.csv"),
           outcome_rdata = file.path(data_root, "ELSA/D03_result_ELSA4.RData")),
      list(year = 2012L, id_col = "idauniq",
           frailty_csv = file.path(data_root, "ELSA/虚弱_elsa_wave6.csv"),
           outcome_rdata = file.path(data_root, "ELSA/D03_result_ELSA6.RData")),
      list(year = 2016L, id_col = "idauniq",
           frailty_csv = file.path(data_root, "ELSA/虚弱_elsa_wave8.csv"),
           outcome_rdata = file.path(data_root, "ELSA/D03_result_ELSA8.RData"))
    )
  ),
  HRS = list(
    baseline_year = 2012L, country = "America",
    dep_file = "HRS_2014_抑郁.csv", dep_id = "HHID_PN", dep_score = "cesd8_total",
    years = list(
      list(year = 2012L, id_col = "hhidpn",
           frailty_csv = file.path(data_root, "HRS/虚弱_hrs_2012.csv"),
           outcome_rdata = file.path(data_root, "HRS/D03_result_HRS12.RData")),
      list(year = 2014L, id_col = "hhidpn",
           frailty_csv = file.path(data_root, "HRS/虚弱_hrs_2014.csv"),
           outcome_rdata = file.path(data_root, "HRS/D03_result_HRS14.RData")),
      list(year = 2016L, id_col = "hhidpn",
           frailty_csv = file.path(data_root, "HRS/虚弱_hrs_2016.csv"),
           outcome_rdata = file.path(data_root, "HRS/D03_result_HRS16.RData")),
      list(year = 2018L, id_col = "hhidpn",
           frailty_csv = file.path(data_root, "HRS/虚弱_hrs_2018.csv"),
           outcome_rdata = NULL),
      list(year = 2020L, id_col = "hhidpn",
           frailty_csv = file.path(data_root, "HRS/虚弱_hrs_2020.csv"),
           outcome_rdata = NULL)
    )
  )
)

load_ck <- function(db) {
  cdir <- file.path(study_root, paste0("phase1_", db, "_allages"), "checkpoints")
  cands <- c(
    file.path(cdir, "step08_multicollinearity_final.rds"),
    file.path(cdir, "multicollinearity_final.rds"),
    file.path(cdir, "step04_baseline_binary.rds"),
    file.path(cdir, "baseline_binary.rds")
  )
  hit <- cands[file.exists(cands)][1]
  if (is.na(hit)) stop("无检查点: ", db)
  ck <- readRDS(hit)
  if (!is.null(ck$ctx)) ck <- ck$ctx
  ck
}

.normalize_blood <- function(d) {
  # ELSA HSCRP → CRP；兼容 TC 别名
  if (!"CRP" %in% names(d) && "HSCRP" %in% names(d)) d$CRP <- as.numeric(d$HSCRP)
  if (!"Total_Cholesterol" %in% names(d) && "TC" %in% names(d)) {
    d$Total_Cholesterol <- as.numeric(d$TC)
  }
  d
}

.fmt_cell <- function(est, ci_lo, ci_hi, p) {
  p_str <- if (is.na(p) || !is.finite(p)) "" else if (p < 0.001) "<0.001" else sprintf("%.3f", round(p, 3))
  paste0(sprintf("%.4f", est), "[", sprintf("%.4f", ci_lo), ", ", sprintf("%.4f", ci_hi), "]", p_str)
}
.fmt_prop <- function(prop) {
  if (is.null(prop) || length(prop) == 0L || is.na(prop) || !is.finite(prop)) return("")
  paste0(sprintf("%.1f", abs(as.numeric(prop)) * 100), "%")
}

.score_med <- function(acme_p, a_p, b_p, prop, te_p, n_event) {
  # 越大越好：显著 ACME + 方向一致的 a/b + 中介比例 + 总效应
  sc <- 0
  if (is.finite(acme_p) && acme_p < 0.05) sc <- sc + 5
  else if (is.finite(acme_p) && acme_p < 0.10) sc <- sc + 2
  if (is.finite(a_p) && a_p < 0.05) sc <- sc + 2
  if (is.finite(b_p) && b_p < 0.05) sc <- sc + 2
  if (is.finite(te_p) && te_p < 0.05) sc <- sc + 1
  if (is.finite(prop)) sc <- sc + min(abs(prop), 1) * 3
  if (is.finite(n_event)) sc <- sc + min(n_event / 50, 2)
  # ACME p 越小加分
  if (is.finite(acme_p) && acme_p > 0) sc <- sc + max(0, -log10(acme_p)) * 0.5
  sc
}

covars_lock <- c("Age", "Alcohol_drinking")
rows <- list()

for (db in c("CHARLS", "ELSA", "HRS")) {
  cli::cli_h1("Pilot blood4: {db}")
  ck <- load_ck(db)
  out_dir <- file.path(study_root, paste0("phase3_long_", db))
  dir.create(file.path(out_dir, "Tables"), recursive = TRUE, showWarnings = FALSE)

  ctx0 <- list(
    data = ck$data,
    results = ck$results %||% list(),
    config = list(
      project = list(
        database = db,
        output_dir = out_dir,
        analysis_group = "Hip_Fracture",
        reference_group = "No_Fracture"
      ),
      data = list(outcome_column = "Disease_Group", id_column = "ID"),
      incidence = list(index_var = "FI"),
      cross_lagged_long_prepare = list(
        medition_dir = file.path(study_root, "data/medition"),
        require_baseline_free = TRUE,
        panel = panel
      )
    )
  )
  ctx0 <- block_cross_lagged_long_prepare(ctx0)
  med_base <- ctx0$data$longitudinal_mediation
  if (is.null(med_base) || !nrow(med_base)) {
    cli::cli_alert_warning("{db}: longitudinal_mediation 空，跳过")
    next
  }

  # 基线血检（插补后）→ 并入纵向中介表
  base <- ck$data$imputed %||% ck$data$cleaned
  base <- .normalize_blood(base)
  if (!"ID" %in% names(base)) {
    # 偶发 id 列
    idc <- intersect(c("ID", "idauniq", "HHIDPN", "hhidpn"), names(base))
    if (length(idc)) base$ID <- as.character(base[[idc[1]]])
  }
  base$ID <- as.character(base$ID)
  med_base$ID <- as.character(med_base$ID)

  blood_cols <- intersect(.BLOOD4, names(base))
  # HRS/CHARLS CRP 可能在 base 中；ELSA HSCRP 已映射
  if (!"CRP" %in% blood_cols && "HSCRP" %in% names(base)) {
    base$CRP <- as.numeric(base$HSCRP)
    blood_cols <- unique(c(blood_cols, "CRP"))
  }
  blood_cols <- intersect(.BLOOD4, names(base))
  cli::cli_alert_info("{db} blood available: {paste(blood_cols, collapse=', ')}")

  bkeep <- c("ID", blood_cols)
  base2 <- base[, bkeep, drop = FALSE]
  for (bc in blood_cols) base2[[bc]] <- suppressWarnings(as.numeric(base2[[bc]]))
  base2 <- base2[!duplicated(base2$ID), , drop = FALSE]

  med_b <- merge(med_base, base2, by = "ID", all.x = TRUE, sort = FALSE)
  # 协变量兜底：若 long_prepare 未带出 Alcohol，从 base 补
  for (cv in covars_lock) {
    if (!cv %in% names(med_b) && cv %in% names(base)) {
      tmp <- base[, c("ID", cv), drop = FALSE]
      tmp$ID <- as.character(tmp$ID)
      med_b <- merge(med_b, tmp, by = "ID", all.x = TRUE, sort = FALSE)
    }
  }

  mediators_try <- c("Depression_cont", blood_cols)
  for (med in mediators_try) {
    if (!med %in% names(med_b)) {
      rows[[length(rows) + 1L]] <- data.frame(
        Cohort = db, Mediator = med, Status = "missing_col",
        N = NA_integer_, Events = NA_integer_,
        ACME = NA_real_, ACME_lo = NA_real_, ACME_hi = NA_real_, ACME_p = NA_real_,
        ADE = NA_real_, ADE_p = NA_real_,
        TE = NA_real_, TE_p = NA_real_,
        path_a = NA_real_, path_a_p = NA_real_,
        path_b = NA_real_, path_b_p = NA_real_,
        prop_med = NA_real_, type = NA_character_, score = NA_real_,
        covars = paste(covars_lock, collapse = "+"),
        note = "column absent after merge",
        stringsAsFactors = FALSE
      )
      next
    }
    mlab <- if (identical(med, "Depression_cont")) "Depression" else (.BLOOD_LABEL[[med]] %||% med)
    dat <- med_b
    dat$M <- suppressWarnings(as.numeric(dat[[med]]))
    use_cols <- c("FI", "M", "Disease_Group", covars_lock)
    use_cols <- intersect(use_cols, names(dat))
    dat <- dat[stats::complete.cases(dat[, use_cols, drop = FALSE]), , drop = FALSE]
    n0 <- nrow(dat)
    ne <- sum(as.character(dat$Disease_Group) == "Hip_Fracture", na.rm = TRUE)
    if (n0 < 30L || ne < 5L) {
      rows[[length(rows) + 1L]] <- data.frame(
        Cohort = db, Mediator = mlab, Status = "n_too_small",
        N = n0, Events = ne,
        ACME = NA_real_, ACME_lo = NA_real_, ACME_hi = NA_real_, ACME_p = NA_real_,
        ADE = NA_real_, ADE_p = NA_real_,
        TE = NA_real_, TE_p = NA_real_,
        path_a = NA_real_, path_a_p = NA_real_,
        path_b = NA_real_, path_b_p = NA_real_,
        prop_med = NA_real_, type = NA_character_, score = NA_real_,
        covars = paste(covars_lock, collapse = "+"),
        note = sprintf("N=%d events=%d", n0, ne),
        stringsAsFactors = FALSE
      )
      next
    }

    # 仅保留分析列，媒介标准化名 M_std
    dat$Depression_cont <- NULL
    dat$M_std <- as.numeric(scale(dat$M)) # 可比系数尺度；bootstrap 用原尺度 col 名
    # mediation 用原尺度列名
    dat[[med]] <- dat$M
    # CRP/HbA1c 右偏：对 CRP 做 log1p
    if (identical(med, "CRP") || identical(med, "HSCRP")) {
      x <- dat[[med]]
      x[!is.finite(x) | x < 0] <- NA
      dat[[med]] <- log1p(x)
      dat <- dat[is.finite(dat[[med]]), , drop = FALSE]
    }

    ctx <- list(
      data = list(longitudinal_mediation = dat),
      results = list(Model2Factors = covars_lock),
      config = list(
        project = list(
          database = db, output_dir = out_dir,
          analysis_group = "Hip_Fracture"
        ),
        data = list(outcome_column = "Disease_Group"),
        incidence = list(index_var = "FI"),
        mediation_longitudinal = list(
          treat = "FI",
          mediator = med,
          outcome = "Disease_Group",
          outcome_event_level = "Hip_Fracture",
          treat_label = "Frailty Index",
          mediator_label = mlab,
          outcome_label = "Hip fracture",
          covariates = covars_lock,
          path_use_covariates = TRUE,
          sims = sims,
          seed = 1000L,
          diagram_enable = FALSE
        )
      )
    )
    ok <- TRUE
    err <- NULL
    ctx2 <- tryCatch(block_mediation_longitudinal(ctx), error = function(e) {
      ok <<- FALSE; err <<- conditionMessage(e); NULL
    })
    if (!ok || is.null(ctx2$results$mediation_longitudinal)) {
      # results key may vary - read rds pub
      pub <- file.path(out_dir, "Tables", "Table_Mediation_Longitudinal_pub.rds")
      res_obj <- if (file.exists(pub)) readRDS(pub) else NULL
      if (is.null(res_obj) || is.null(res_obj$results[[db]])) {
        rows[[length(rows) + 1L]] <- data.frame(
          Cohort = db, Mediator = mlab, Status = "fit_fail",
          N = n0, Events = ne,
          ACME = NA_real_, ACME_lo = NA_real_, ACME_hi = NA_real_, ACME_p = NA_real_,
          ADE = NA_real_, ADE_p = NA_real_,
          TE = NA_real_, TE_p = NA_real_,
          path_a = NA_real_, path_a_p = NA_real_,
          path_b = NA_real_, path_b_p = NA_real_,
          prop_med = NA_real_, type = NA_character_, score = NA_real_,
          covars = paste(covars_lock, collapse = "+"),
          note = err %||% "no results",
          stringsAsFactors = FALSE
        )
        next
      }
      r <- res_obj$results[[db]]
    } else {
      # parse from results if structured differently
      pub <- file.path(out_dir, "Tables", "Table_Mediation_Longitudinal_pub.rds")
      res_obj <- readRDS(pub)
      r <- res_obj$results[[db]]
    }

    # rename temp xlsx to pilot-specific to avoid stomping Depression table name
    src_x <- file.path(out_dir, "Tables", "Table_Mediation_Longitudinal_FI_Depression_Hip.xlsx")
    if (file.exists(src_x)) {
      file.copy(
        src_x,
        file.path(out_dir, "Tables", sprintf("Pilot_mediation_FI_%s.xlsx", mlab)),
        overwrite = TRUE
      )
    }
    file.copy(
      file.path(out_dir, "Tables", "Table_Mediation_Longitudinal_pub.rds"),
      file.path(out_dir, "Tables", sprintf("Pilot_mediation_FI_%s_pub.rds", gsub("[^A-Za-z0-9]+", "_", mlab))),
      overwrite = TRUE
    )

    acme_p <- r$d0_p; te_p <- r$tau_p
    sc <- .score_med(acme_p, r$a_p, r$b_p, r$prop, te_p, r$n_event)
    rows[[length(rows) + 1L]] <- data.frame(
      Cohort = db, Mediator = mlab, Status = "ok",
      N = r$N, Events = r$n_event,
      ACME = unname(r$d0), ACME_lo = unname(r$d0_ci[1]), ACME_hi = unname(r$d0_ci[2]),
      ACME_p = unname(acme_p),
      ADE = unname(r$z0), ADE_p = unname(r$z0_p),
      TE = unname(r$tau), TE_p = unname(te_p),
      path_a = unname(r$a_coef), path_a_p = unname(r$a_p),
      path_b = unname(r$b_coef), path_b_p = unname(r$b_p),
      prop_med = unname(r$prop),
      type = r$med_type,
      score = sc,
      covars = paste(r$covariates %||% covars_lock, collapse = "+"),
      note = sprintf(
        "ACME %s; prop=%s",
        .fmt_cell(r$d0, r$d0_ci[1], r$d0_ci[2], acme_p),
        .fmt_prop(r$prop)
      ),
      stringsAsFactors = FALSE
    )
    cli::cli_alert_success(
      "{db} · {mlab}: ACME_p={signif(acme_p,3)} prop={(.fmt_prop(r$prop))} score={round(sc,2)}"
    )
  }
}

tab <- do.call(rbind, rows)
rownames(tab) <- NULL
tab <- tab[order(tab$Cohort, -ifelse(is.finite(tab$score), tab$score, -Inf)), , drop = FALSE]

# 与 Depression 对照的简单判决
.judge <- function(sub) {
  dep <- sub[sub$Mediator == "Depression" & sub$Status == "ok", , drop = FALSE]
  blood <- sub[sub$Mediator != "Depression" & sub$Status == "ok", , drop = FALSE]
  if (!nrow(blood)) return("no_blood_ok")
  best_b <- blood[which.max(blood$score), , drop = FALSE]
  if (!nrow(dep)) return(paste0("best_blood=", best_b$Mediator[1], " (no dep baseline)"))
  if (isTRUE(best_b$score[1] > dep$score[1] + 0.5) &&
      is.finite(best_b$ACME_p[1]) && best_b$ACME_p[1] < 0.05) {
    paste0("BETTER: ", best_b$Mediator[1], " (score ",
           round(best_b$score[1], 2), " > Dep ", round(dep$score[1], 2), ")")
  } else if (isTRUE(best_b$score[1] > dep$score[1])) {
    paste0("slightly higher score: ", best_b$Mediator[1], " but ACME_p=",
           signif(best_b$ACME_p[1], 3), " vs Dep ACME_p=", signif(dep$ACME_p[1], 3))
  } else {
    paste0("Depression better or comparable (Dep score=", round(dep$score[1], 2),
           " ACME_p=", signif(dep$ACME_p[1], 3), "; best blood=", best_b$Mediator[1],
           " score=", round(best_b$score[1], 2), " ACME_p=", signif(best_b$ACME_p[1], 3), ")")
  }
}
verdict <- vapply(split(tab, tab$Cohort), .judge, character(1))
verdict_df <- data.frame(Cohort = names(verdict), Verdict = unname(verdict), stringsAsFactors = FALSE)

csv_path <- file.path(out_tab, "Pilot_blood4_mediation_vs_depression.csv")
utils::write.csv(tab, csv_path, row.names = FALSE)
utils::write.csv(verdict_df, file.path(out_tab, "Pilot_blood4_verdict_by_cohort.csv"), row.names = FALSE)

xlsx_path <- file.path(out_tab, "Pilot_blood4_mediation_vs_depression.xlsx")
if (requireNamespace("openxlsx", quietly = TRUE)) {
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "compare")
  openxlsx::writeData(wb, "compare", tab)
  openxlsx::addWorksheet(wb, "verdict")
  openxlsx::writeData(wb, "verdict", verdict_df)
  note <- paste(
    "Pilot: shared labs HbA1c/HDL/Total_Cholesterol/CRP (ELSA HSCRP→CRP).",
    "Mediator = baseline blood (same wave as FI; temporal order weaker than mid-wave Depression).",
    "Model: FI → M → Hip fracture; covariates Age+Alcohol_drinking; sims=", sims, ".",
    "CRP modeled as log1p(CRP). Score rewards significant ACME/path a/b and mediation proportion.",
    "Does NOT replace official Table S6/S7 (still Depression)."
  )
  openxlsx::addWorksheet(wb, "note")
  openxlsx::writeData(wb, "note", data.frame(note = note))
  openxlsx::saveWorkbook(wb, xlsx_path, overwrite = TRUE)
}

# 同步副本到课题盘（若可写）
g_dest <- "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747/summary_result/table"
if (dir.exists(dirname(g_dest))) {
  dir.create(g_dest, recursive = TRUE, showWarnings = FALSE)
  try(file.copy(csv_path, g_dest, overwrite = TRUE), silent = TRUE)
  try(file.copy(xlsx_path, g_dest, overwrite = TRUE), silent = TRUE)
  try(file.copy(file.path(out_tab, "Pilot_blood4_verdict_by_cohort.csv"), g_dest, overwrite = TRUE), silent = TRUE)
}

cli::cli_h1("Verdict by cohort")
print(verdict_df)
cli::cli_h1("Top rows")
print(tab[, c("Cohort", "Mediator", "Status", "N", "Events", "ACME_p", "prop_med", "score", "type")])
cli::cli_alert_success("Wrote {csv_path}")
cli::cli_alert_success("Wrote {xlsx_path}")
