#!/usr/bin/env Rscript
# pilot_blood4_mediators_long.R
# 用 medition 纵向血检（中间波，对齐抑郁中介时序）试 FI → 四血检 → 髋部骨折
#
# 时序规则（与 Depression 一致：X 基线 → M 中间 → Y 随访）：
#   CHARLS: 仅 2011/2015 血检 → 真·中间波不存在（2011=基线同期；2015=结局年同期）
#           本脚本对 CHARLS 额外给出「2015 同期参照」并标注 temporal=same_as_Y
#   ELSA  : wave4 2008-09 血检（基线 2004 之后；先于/不晚于晚波结局）
#   HRS   : 2014 wave12 血检（与抑郁 2014 同年；在 2012 基线之后）
#
# 产出（不覆盖正式 S6/S7）：
#   summary_result/table/Pilot_blood4_LONG_mediation_vs_depression.*

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
med_dir <- file.path(data_root, "medition")
out_tab <- file.path(study_root, "summary_result", "table")
dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/cross_lagged_fi_item_labels.R"))
source(file.path(root, "Blocks/54_cross_lagged_full/14block_cross_lagged_long_prepare.R"))
source(file.path(root, "Blocks/20_mediation/06block_mediation_longitudinal.R"))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
options(warn = 1, cli.hyperlink = FALSE)

.BLOOD4 <- c("HbA1c", "HDL", "Total_Cholesterol", "CRP")
.BLOOD_LABEL <- c(
  HbA1c = "HbA1c", HDL = "HDL-C",
  Total_Cholesterol = "Total cholesterol", CRP = "CRP"
)

# 纵向血检中间波规格
blood_wave <- list(
  CHARLS = list(
    # 无真中间波：记录并可选跑 2015 作为对照
    mid_file = NA_character_,
    mid_year = NA_integer_,
    mid_label = "none (only 2011 baseline & 2015 outcome-year blood)",
    ref_sameY_file = "CHARLS_2015_wave3_blood.csv",
    ref_sameY_year = 2015L,
    id_spec = "ID",
    colmap = list( # CHARLS 2015
      HbA1c = "bl_hbalc", HDL = "bl_hdl",
      Total_Cholesterol = "bl_cho", CRP = "bl_crp"
    ),
    colmap_2011 = list(
      HbA1c = "newhba1c", HDL = "newhdl",
      Total_Cholesterol = "newcho", CRP = "newcrp"
    )
  ),
  ELSA = list(
    mid_file = "ELSA_2008-2009_wave4_blood.csv",
    mid_year = 2008L,
    mid_label = "wave4 2008-09 (after 2004 baseline)",
    id_spec = "idauniq",
    colmap = list(
      HbA1c = "hba1c", HDL = "hdl",
      Total_Cholesterol = "chol", CRP = "hscrp"
    )
  ),
  HRS = list(
    # HRS 生物样本为交叉半年：本课题 2012 基线队列全部落在 2012 血检亚组，
    # 与 2014 血检 0 重叠；真·中间波可用 2016（在 2012 之后，事件须晚于 2016）
    mid_file = "HRS_2016_wave13_blood.csv",
    mid_year = 2016L,
    mid_label = "2016 wave13 (mid after 2012; 2014 blood has 0 overlap with this cohort half-sample)",
    id_spec = "HHID_PN",
    colmap = list(
      HbA1c = "PA1C_ADJ", HDL = "PHDL_ADJ",
      Total_Cholesterol = "PTC_ADJ", CRP = "PCRP_ADJ"
    ),
    # 也保留 2012 作为基线同期对照
    concurrent_file = "HRS_2012_wave11_blood.csv",
    concurrent_year = 2012L,
    concurrent_colmap = list(
      HbA1c = "NA1C_ADJ", HDL = "NHDL_ADJ",
      Total_Cholesterol = "NTC_ADJ", CRP = "NCRP_ADJ"
    )
  )
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
    file.path(cdir, "baseline_binary.rds")
  )
  hit <- cands[file.exists(cands)][1]
  if (is.na(hit)) stop("无检查点: ", db)
  ck <- readRDS(hit)
  if (!is.null(ck$ctx)) ck <- ck$ctx
  ck
}

.read_blood <- function(path, id_spec, colmap) {
  if (!file.exists(path)) stop("缺血检文件: ", path)
  d <- utils::read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
  if (identical(id_spec, "HHID_PN")) {
    if (!all(c("HHID", "PN") %in% names(d))) stop("HRS 血检缺 HHID/PN: ", path)
    d$ID <- paste0(d$HHID, sprintf("%03d", as.integer(d$PN)))
  } else if (id_spec %in% names(d)) {
    d$ID <- as.character(d[[id_spec]])
  } else if ("ID" %in% names(d)) {
    d$ID <- as.character(d$ID)
  } else stop("血检缺 ID: ", path)
  out <- data.frame(ID = d$ID, stringsAsFactors = FALSE)
  for (std in names(colmap)) {
    src <- colmap[[std]]
    if (!src %in% names(d)) {
      # soft alias try
      alt <- grep(paste0("^", src, "$"), names(d), ignore.case = TRUE, value = TRUE)
      if (length(alt)) src <- alt[[1]]
    }
    out[[std]] <- if (src %in% names(d)) suppressWarnings(as.numeric(d[[src]])) else NA_real_
  }
  out <- out[!is.na(out$ID) & !duplicated(out$ID), , drop = FALSE]
  out
}

.fmt_cell <- function(est, lo, hi, p) {
  p_str <- if (!is.finite(p)) "" else if (p < 0.001) "<0.001" else sprintf("%.3f", round(p, 3))
  paste0(sprintf("%.4f", est), "[", sprintf("%.4f", lo), ", ", sprintf("%.4f", hi), "]", p_str)
}
.fmt_prop <- function(prop) {
  if (!is.finite(prop)) return("")
  paste0(sprintf("%.1f", abs(as.numeric(prop)) * 100), "%")
}
.score_med <- function(acme_p, a_p, b_p, prop, te_p, n_event) {
  sc <- 0
  if (is.finite(acme_p) && acme_p < 0.05) sc <- sc + 5
  else if (is.finite(acme_p) && acme_p < 0.10) sc <- sc + 2
  if (is.finite(a_p) && a_p < 0.05) sc <- sc + 2
  if (is.finite(b_p) && b_p < 0.05) sc <- sc + 2
  if (is.finite(te_p) && te_p < 0.05) sc <- sc + 1
  if (is.finite(prop)) sc <- sc + min(abs(prop), 1) * 3
  if (is.finite(n_event)) sc <- sc + min(n_event / 50, 2)
  if (is.finite(acme_p) && acme_p > 0) sc <- sc + max(0, -log10(acme_p)) * 0.5
  sc
}

covars_lock <- c("Age", "Alcohol_drinking")
rows <- list()
inventory <- list()

for (db in c("CHARLS", "ELSA", "HRS")) {
  cli::cli_h1("LONG blood4 pilot: {db}")
  ck <- load_ck(db)
  out_dir <- file.path(study_root, paste0("phase3_long_", db))
  dir.create(file.path(out_dir, "Tables"), recursive = TRUE, showWarnings = FALSE)

  ctx0 <- list(
    data = ck$data,
    results = ck$results %||% list(),
    config = list(
      project = list(
        database = db, output_dir = out_dir,
        analysis_group = "Hip_Fracture", reference_group = "No_Fracture"
      ),
      data = list(outcome_column = "Disease_Group", id_column = "ID"),
      incidence = list(index_var = "FI"),
      cross_lagged_long_prepare = list(
        medition_dir = med_dir,
        require_baseline_free = TRUE,
        panel = panel
      )
    )
  )
  ctx0 <- block_cross_lagged_long_prepare(ctx0)
  med_base <- ctx0$data$longitudinal_mediation
  if (is.null(med_base) || !nrow(med_base)) {
    cli::cli_alert_warning("{db}: long mediation empty")
    next
  }
  med_base$ID <- as.character(med_base$ID)
  # 补协变量
  base <- ck$data$imputed %||% ck$data$cleaned
  if (!"ID" %in% names(base)) {
    idc <- intersect(c("ID", "idauniq", "hhidpn"), names(base))
    if (length(idc)) base$ID <- as.character(base[[idc[1]]])
  }
  base$ID <- as.character(base$ID)
  for (cv in covars_lock) {
    if (!cv %in% names(med_base) && cv %in% names(base)) {
      tmp <- base[, c("ID", cv), drop = FALSE]
      med_base <- merge(med_base, tmp[!duplicated(tmp$ID), ], by = "ID", all.x = TRUE)
    }
  }

  bw <- blood_wave[[db]]
  inventory[[db]] <- data.frame(
    Cohort = db,
    mid_blood_file = as.character(bw$mid_file %||% NA),
    mid_year = as.integer(bw$mid_year %||% NA),
    mid_label = bw$mid_label %||% "",
    n_long_med = nrow(med_base),
    stringsAsFactors = FALSE
  )

  # 任务集：Depression 基准 + 纵向中间波四血检（若可得）+ CHARLS 可选 sameY 参照
  jobs <- list(list(kind = "Depression", temporal = "mid_wave_depress", file = NULL))

  if (!is.null(bw$mid_file) && !is.na(bw$mid_file) && nzchar(bw$mid_file)) {
    jobs[[length(jobs) + 1L]] <- list(
      kind = "blood_mid", temporal = "mid_wave_blood",
      file = bw$mid_file, year = bw$mid_year, colmap = bw$colmap
    )
  } else {
    cli::cli_alert_warning(
      "{db}: 无真·中间波血检文件（{bw$mid_label}）。跳过 mid-wave 血检中介。"
    )
    # CHARLS 2015 作对照（标注 same_as_Y）
    if (!is.null(bw$ref_sameY_file) && file.exists(file.path(med_dir, bw$ref_sameY_file))) {
      jobs[[length(jobs) + 1L]] <- list(
        kind = "blood_sameY_ref", temporal = "same_year_as_outcome",
        file = bw$ref_sameY_file, year = bw$ref_sameY_year, colmap = bw$colmap
      )
    }
  }
  # HRS 等：基线同期血检对照
  if (!is.null(bw$concurrent_file) && file.exists(file.path(med_dir, bw$concurrent_file))) {
    jobs[[length(jobs) + 1L]] <- list(
      kind = "blood_concurrent", temporal = "same_wave_as_FI",
      file = bw$concurrent_file, year = bw$concurrent_year,
      colmap = bw$concurrent_colmap %||% bw$colmap
    )
  }

  for (job in jobs) {
    if (identical(job$kind, "Depression")) {
      med_vars <- "Depression_cont"
      dat0 <- med_base
      temporal <- "mid_wave_depress"
      wave_note <- as.character(panel[[db]]$dep_file)
    } else {
      bdf <- .read_blood(file.path(med_dir, job$file), bw$id_spec, job$colmap)
      n_hit <- sum(med_base$ID %in% bdf$ID)
      cli::cli_alert_info(
        "{db} blood merge {job$file}: long_N={nrow(med_base)} hit={n_hit} year={job$year}"
      )
      dat0 <- merge(med_base, bdf, by = "ID", all = FALSE)
      # 时序：中间波要求 outcome time 不早于血检年（可用才筛）
      if ("time" %in% names(dat0) && is.finite(job$year)) {
        tnum <- suppressWarnings(as.numeric(dat0$time))
        # time 在 long_prepare 可能是相对年或绝对年；若最大值>100 当绝对年
        if (isTRUE(max(tnum, na.rm = TRUE) > 100)) {
          if (identical(job$kind, "blood_mid")) {
            dat0 <- dat0[is.na(tnum) | tnum > job$year, , drop = FALSE]
          } # sameY: 允许 tnum >= year
        }
      }
      med_vars <- intersect(.BLOOD4, names(dat0))
      temporal <- job$temporal
      wave_note <- paste0(job$file, " y=", job$year)
    }

    for (med in med_vars) {
      mlab <- if (identical(med, "Depression_cont")) "Depression" else (.BLOOD_LABEL[[med]] %||% med)
      dat <- dat0
      if (!med %in% names(dat)) next
      dat[[med]] <- suppressWarnings(as.numeric(dat[[med]]))
      if (identical(med, "CRP")) {
        x <- dat[[med]]
        x[!is.finite(x) | x < 0] <- NA
        dat[[med]] <- log1p(x)
      }
      use_cols <- intersect(c("FI", med, "Disease_Group", covars_lock), names(dat))
      dat <- dat[stats::complete.cases(dat[, use_cols, drop = FALSE]), , drop = FALSE]
      n0 <- nrow(dat)
      ne <- sum(as.character(dat$Disease_Group) == "Hip_Fracture", na.rm = TRUE)
      if (n0 < 30L || ne < 5L) {
        rows[[length(rows) + 1L]] <- data.frame(
          Cohort = db, Mediator = mlab, Temporal = temporal, Wave = wave_note,
          Status = "n_too_small", N = n0, Events = ne,
          ACME = NA_real_, ACME_lo = NA_real_, ACME_hi = NA_real_, ACME_p = NA_real_,
          ADE_p = NA_real_, TE_p = NA_real_,
          path_a_p = NA_real_, path_b_p = NA_real_, prop_med = NA_real_,
          type = NA_character_, score = NA_real_,
          covars = paste(covars_lock, collapse = "+"),
          note = sprintf("N=%d events=%d", n0, ne),
          stringsAsFactors = FALSE
        )
        next
      }

      ctx <- list(
        data = list(longitudinal_mediation = dat),
        results = list(Model2Factors = covars_lock),
        config = list(
          project = list(database = db, output_dir = out_dir, analysis_group = "Hip_Fracture"),
          data = list(outcome_column = "Disease_Group"),
          incidence = list(index_var = "FI"),
          mediation_longitudinal = list(
            treat = "FI", mediator = med, outcome = "Disease_Group",
            outcome_event_level = "Hip_Fracture",
            treat_label = "Frailty Index",
            mediator_label = mlab,
            outcome_label = "Hip fracture",
            covariates = covars_lock,
            path_use_covariates = TRUE,
            sims = sims, seed = 1000L, diagram_enable = FALSE
          )
        )
      )
      err <- NULL
      tryCatch(block_mediation_longitudinal(ctx), error = function(e) {
        err <<- conditionMessage(e)
      })
      pub <- file.path(out_dir, "Tables", "Table_Mediation_Longitudinal_pub.rds")
      if (!is.null(err) || !file.exists(pub)) {
        rows[[length(rows) + 1L]] <- data.frame(
          Cohort = db, Mediator = mlab, Temporal = temporal, Wave = wave_note,
          Status = "fit_fail", N = n0, Events = ne,
          ACME = NA_real_, ACME_lo = NA_real_, ACME_hi = NA_real_, ACME_p = NA_real_,
          ADE_p = NA_real_, TE_p = NA_real_,
          path_a_p = NA_real_, path_b_p = NA_real_, prop_med = NA_real_,
          type = NA_character_, score = NA_real_,
          covars = paste(covars_lock, collapse = "+"),
          note = err %||% "no pub rds",
          stringsAsFactors = FALSE
        )
        next
      }
      res_obj <- readRDS(pub)
      r <- res_obj$results[[db]]
      sc <- .score_med(r$d0_p, r$a_p, r$b_p, r$prop, r$tau_p, r$n_event)
      rows[[length(rows) + 1L]] <- data.frame(
        Cohort = db, Mediator = mlab, Temporal = temporal, Wave = wave_note,
        Status = "ok", N = r$N, Events = r$n_event,
        ACME = unname(r$d0), ACME_lo = unname(r$d0_ci[1]), ACME_hi = unname(r$d0_ci[2]),
        ACME_p = unname(r$d0_p),
        ADE_p = unname(r$z0_p), TE_p = unname(r$tau_p),
        path_a_p = unname(r$a_p), path_b_p = unname(r$b_p),
        prop_med = unname(r$prop), type = r$med_type, score = sc,
        covars = paste(r$covariates %||% covars_lock, collapse = "+"),
        note = sprintf("ACME %s; prop=%s",
                       .fmt_cell(r$d0, r$d0_ci[1], r$d0_ci[2], r$d0_p),
                       .fmt_prop(r$prop)),
        stringsAsFactors = FALSE
      )
      # 保存单次结果
      file.copy(
        file.path(out_dir, "Tables", "Table_Mediation_Longitudinal_FI_Depression_Hip.xlsx"),
        file.path(out_dir, "Tables",
                  sprintf("Pilot_LONGmed_FI_%s_%s.xlsx", temporal, gsub("[^A-Za-z0-9]+", "_", mlab))),
        overwrite = TRUE
      )
      cli::cli_alert_success(
        "{db} · {mlab} [{temporal}]: ACME_p={signif(r$d0_p,3)} prop={(.fmt_prop(r$prop))} N={r$N}"
      )
    }
  }
}

tab <- do.call(rbind, rows)
rownames(tab) <- NULL
tab <- tab[order(tab$Cohort, tab$Temporal, -ifelse(is.finite(tab$score), tab$score, -Inf)), ]

inv <- do.call(rbind, inventory)
utils::write.csv(inv, file.path(out_tab, "Pilot_blood4_LONG_blood_wave_inventory.csv"), row.names = FALSE)
utils::write.csv(tab, file.path(out_tab, "Pilot_blood4_LONG_mediation_vs_depression.csv"), row.names = FALSE)

if (requireNamespace("openxlsx", quietly = TRUE)) {
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "compare")
  openxlsx::writeData(wb, "compare", tab)
  openxlsx::addWorksheet(wb, "inventory")
  openxlsx::writeData(wb, "inventory", inv)
  openxlsx::addWorksheet(wb, "note")
  openxlsx::writeData(wb, "note", data.frame(note = paste(
    "LONG blood pilot: mediators from medition intermediate-wave blood CSVs.",
    "ELSA=wave4 2008-09; HRS=2014; CHARLS has no true mid-wave blood (only 2011 & 2015).",
    "CHARLS optional row temporal=same_year_as_outcome uses 2015 blood (NOT valid mid mediation).",
    "CRP=log1p; covariates Age+Alcohol; Depression kept as reference mid-wave psych mediator.",
    "Official Table S6/S7 remain Depression."
  )))
  openxlsx::saveWorkbook(
    wb, file.path(out_tab, "Pilot_blood4_LONG_mediation_vs_depression.xlsx"), overwrite = TRUE
  )
}

g_dest <- "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747/summary_result/table"
if (dir.exists(dirname(g_dest))) {
  dir.create(g_dest, recursive = TRUE, showWarnings = FALSE)
  for (f in c(
    "Pilot_blood4_LONG_mediation_vs_depression.csv",
    "Pilot_blood4_LONG_mediation_vs_depression.xlsx",
    "Pilot_blood4_LONG_blood_wave_inventory.csv"
  )) {
    try(file.copy(file.path(out_tab, f), g_dest, overwrite = TRUE), silent = TRUE)
  }
}

cli::cli_h1("Inventory")
print(inv)
cli::cli_h1("Results (key cols)")
print(tab[, c("Cohort", "Mediator", "Temporal", "Status", "N", "Events", "ACME_p", "prop_med", "type", "score")])
cli::cli_alert_success("Done → {file.path(out_tab, 'Pilot_blood4_LONG_mediation_vs_depression.xlsx')}")
