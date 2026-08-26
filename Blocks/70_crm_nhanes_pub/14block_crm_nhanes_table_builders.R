###############################################################################
#  crm70 table builders — 原 run/crm_nhanes_mr/rerun_table*.R 并入 Blocks/70
#  由 crm_nhanes_pub_deliverables 在 lib_mode 下 source 后调用 crm70_build_*。
#  勿在 run/ 再放旁路重建脚本。
###############################################################################

.crm70_repo_root <- function() {
  env <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (nzchar(env) && dir.exists(env)) return(normalizePath(env, winslash = "/"))
  here <- tryCatch(
    normalizePath(file.path(dirname(sys.frame(1)$ofile), "../.."), winslash = "/"),
    error = function(e) NA_character_
  )
  # when sourced, ofile may be unavailable; fall back to known roots
  cands <- c(
    here,
    "E:/01block/01Block-new-Final",
    "/mnt/e/01block/01Block-new-Final"
  )
  hit <- cands[!is.na(cands) & nzchar(cands) & dir.exists(cands)]
  if (!length(hit)) stop("找不到 MEDICAL_BLOCKS_ROOT / 引擎根目录", call. = FALSE)
  normalizePath(hit[[1L]], winslash = "/")
}

.crm70_default_proj <- function() {
  opt <- getOption("crm70.proj", NULL)
  if (!is.null(opt) && nzchar(opt) && dir.exists(opt)) return(normalizePath(opt, winslash = "/"))
  cands <- c(
    "G:/02block_result/14_CRM/comorbid_Mendelia_randomization_40145269",
    "/mnt/g/02block_result/14_CRM/comorbid_Mendelia_randomization_40145269"
  )
  hit <- cands[dir.exists(cands)]
  if (!length(hit)) stop("找不到 CRM 产出根目录（设 options(crm70.proj=...)）", call. = FALSE)
  normalizePath(hit[[1L]], winslash = "/")
}

.crm70_obs_checkpoint <- function(proj, name = "crm_nhanes_ordinal_pub.rds") {
  cands <- c(
    file.path(proj, "by_unit", paste0("\u3010success\u3011", "obs_main"), "checkpoints", name),
    file.path(proj, "by_unit", "obs_main", "checkpoints", name)
  )
  hit <- cands[file.exists(cands)]
  if (!length(hit)) stop("缺 checkpoint: ", name, " under ", proj, call. = FALSE)
  hit[[1L]]
}

.crm70_ensure_utils <- function(repo) {
  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    source(file.path(repo, "R/utils.R"), local = FALSE)
  }
}


# ---- from rerun_table1_ordinal_wide.R ----
crm70_build_table1_ordinal <- function(...) {
  # 从 obs_main checkpoint 重跑 ordinal 宽表 Table 1，写入 NHANES_pub_deliverables

  suppressPackageStartupMessages({
    if (!requireNamespace("cli", quietly = TRUE)) stop("need cli")
  })

  repo <- .crm70_repo_root()
  options(pipeline.database_name = "NHANES")

  src <- function(rel) source(file.path(repo, rel), local = FALSE)
  .crm70_ensure_utils(repo)
  src("Blocks/70_crm_nhanes_pub/05block_crm_nhanes_ordinal_pub.R")

  proj <- .crm70_default_proj()
  cp <- .crm70_obs_checkpoint(proj)
  obj <- readRDS(cp)
  ctx <- obj$ctx
  if (is.null(ctx$data$cleaned) && is.null(ctx$data$raw)) {
    stop("checkpoint 中无 data$cleaned/raw")
  }

  deliver <- getOption("crm70.deliv", file.path(proj, "NHANES_pub_deliverables"))
  dir.create(deliver, recursive = TRUE, showWarnings = FALSE)
  ctx$output_dir <- file.path(deliver, "_tmp_ordinal_rerun")
  ctx$output_dir_tables <- file.path(deliver, "Tables")
  ctx$output_dir_figures <- file.path(deliver, "Figures")
  dir.create(ctx$output_dir_tables, recursive = TRUE, showWarnings = FALSE)

  ctx$config$crm_nhanes_ordinal_pub <- modifyList(
    ctx$config$crm_nhanes_ordinal_pub %||% list(),
    list(
      pause_enable = FALSE,
      pub_xlsx_filename = "Table 1-NHANES. Ordinal logistic OR SUA HU gout.xlsx",
      pub_title = "Table 1-NHANES. Association of serum uric acid and gout with CRM conditions"
    )
  )
  # 确保镜像到交付 Tables（若 utils 要求开关）
  ctx$config$project$mirror_pub_outputs_to_root <- FALSE

  ctx <- block_crm_nhanes_ordinal_pub(ctx)
  if (exists("render_queued_tables", mode = "function")) {
    ctx <- render_queued_tables(ctx)
  }

  # 清理 tex / 临时
  tex <- list.files(ctx$output_dir_tables, pattern = "\\.tex$", full.names = TRUE)
  unlink(tex)
  # 长表/宽表 csv 归档到 _archive，交付区只留正式 xlsx
  arch <- file.path(ctx$output_dir_tables, "_archive_internal")
  dir.create(arch, recursive = TRUE, showWarnings = FALSE)
  for (fn in c("Table_2_Ordinal_NHANES.csv", "Table_1_Ordinal_NHANES_wide.csv")) {
    p <- file.path(ctx$output_dir_tables, fn)
    if (file.exists(p)) {
      file.rename(p, file.path(arch, fn))
    }
  }
  unlink(ctx$output_dir, recursive = TRUE)

  wide <- ctx$results$crm_nhanes_ordinal_pub$table_wide
  cli::cli_h1("Table 1 wide preview")
  print(wide)
  xlsx <- file.path(ctx$output_dir_tables, "Table 1-NHANES. Ordinal logistic OR SUA HU gout.xlsx")
  # 若 inject 改过文件名，找最新 Table 1*.xlsx
  if (!file.exists(xlsx)) {
    cands <- list.files(ctx$output_dir_tables, pattern = "^Table 1-NHANES.*\\.xlsx$", full.names = TRUE)
    print(cands)
    xlsx <- cands[1L]
  }
  cli::cli_alert_success("Wrote: {xlsx}")

  invisible(TRUE)
}

# ---- from rerun_table2_cox_wide.R ----
crm70_build_table2_cox <- function(...) {
  # 重跑原文 Table 4 布局 → 正表 Table 2

  repo <- .crm70_repo_root()
  options(pipeline.database_name = "NHANES")
  .crm70_ensure_utils(repo)
  source(file.path(repo, "Blocks/70_crm_nhanes_pub/06block_crm_nhanes_cox_pub.R"), local = FALSE)

  proj <- .crm70_default_proj()
  cp <- .crm70_obs_checkpoint(proj)
  obj <- readRDS(cp)
  ctx <- obj$ctx
  deliver <- getOption("crm70.deliv", file.path(proj, "NHANES_pub_deliverables"))
  dir.create(deliver, recursive = TRUE, showWarnings = FALSE)
  ctx$output_dir <- file.path(deliver, "_tmp_cox_rerun")
  ctx$output_dir_tables <- file.path(deliver, "Tables")
  ctx$output_dir_figures <- file.path(deliver, "Figures")
  dir.create(ctx$output_dir_tables, recursive = TRUE, showWarnings = FALSE)
  ctx$config$project$mirror_pub_outputs_to_root <- FALSE
  ctx$config$crm_nhanes_cox_pub <- modifyList(
    ctx$config$crm_nhanes_cox_pub %||% list(),
    list(pause_enable = FALSE)
  )

  ctx <- block_crm_nhanes_cox_pub(ctx)
  if (exists("render_queued_tables", mode = "function")) ctx <- render_queued_tables(ctx)

  arch <- file.path(ctx$output_dir_tables, "_archive_internal")
  dir.create(arch, recursive = TRUE, showWarnings = FALSE)
  for (fn in c("Table_4_Cox_NHANES.csv", "Table_2_Cox_NHANES_wide.csv")) {
    p <- file.path(ctx$output_dir_tables, fn)
    if (file.exists(p)) file.rename(p, file.path(arch, basename(p)))
  }
  unlink(list.files(ctx$output_dir_tables, pattern = "\\.tex$", full.names = TRUE))
  unlink(ctx$output_dir, recursive = TRUE)

  print(ctx$results$crm_nhanes_cox_pub$table_wide)
  cli::cli_alert_success("Done Table 2")

  invisible(TRUE)
}

# ---- from rerun_table3_mr_wide.R ----
crm70_build_table3_mr <- function(...) {
  # 将 MR 长表重排为原文 Table 5 宽表 → 正表 Table 3

  repo <- .crm70_repo_root()
  options(pipeline.database_name = "NHANES")
  .crm70_ensure_utils(repo)

  `%||%` <- function(a, b) if (!is.null(a) && length(a)) a else b

  proj <- .crm70_default_proj()
  tab_dir <- getOption("crm70.tab_dir", file.path(proj, "NHANES_pub_deliverables", "Tables"))
  arch <- file.path(tab_dir, "_archive_internal")
  src_csv <- file.path(arch, "Table_5_MR_Estimates_pub.csv")
  if (!file.exists(src_csv)) src_csv <- file.path(arch, "Table_5_MR_Estimates.csv")
  if (!file.exists(src_csv)) stop("missing MR estimates csv in archive")

  d <- utils::read.csv(src_csv, stringsAsFactors = FALSE, check.names = FALSE)

  # 统一列名
  if (!"Outcome" %in% names(d) && "outcome_label" %in% names(d)) {
    d$Outcome <- d$outcome_label
  }
  if (!"Method" %in% names(d) && "method" %in% names(d)) {
    d$Method <- d$method
  }
  if (!"N_SNPs" %in% names(d) && "nsnp" %in% names(d)) {
    d$N_SNPs <- d$nsnp
  }
  if (!"P" %in% names(d) && "pval" %in% names(d)) {
    d$P <- d$pval
  }

  # 从 beta/se 补 OR 文本
  .fmt_or <- function(or_txt, beta, se) {
    if (!is.null(or_txt) && length(or_txt) && nzchar(as.character(or_txt)[1L]) &&
        !grepl("^\\s*$", as.character(or_txt)[1L]) &&
        grepl("\\(", as.character(or_txt)[1L])) {
      return(as.character(or_txt)[1L])
    }
    b <- suppressWarnings(as.numeric(beta))
    s <- suppressWarnings(as.numeric(se))
    if (!is.finite(b) || !is.finite(s)) return("")
    or <- exp(b); lo <- exp(b - 1.96 * s); hi <- exp(b + 1.96 * s)
    sprintf("%.3f (%.3f–%.3f)", or, lo, hi)
  }

  .fmt_p_paper <- function(p) {
    # 原文 Table 5：P<0.01 或最多约 3 位小数
    if (is.character(p)) {
      ps <- trimws(p)
      if (grepl("^<", ps)) {
        num <- suppressWarnings(as.numeric(sub("^<\\s*", "", ps)))
        if (is.finite(num) && num <= 0.01) return("<0.01")
      }
      p <- suppressWarnings(as.numeric(ps))
    } else {
      p <- suppressWarnings(as.numeric(p))
    }
    if (!is.finite(p)) return("")
    if (p < 0.01) return("<0.01")
    sprintf("%.2f", p)
  }

  .norm_method <- function(m) {
    m <- tolower(trimws(as.character(m)))
    if (grepl("inverse variance|\\bivw\\b", m)) return("IVW")
    if (grepl("egger", m)) return("MR-Egger")
    if (grepl("weighted median", m)) return("Weighted median")
    if (grepl("presso", m) && grepl("outlier|corrected", m)) return("MR-PRESSO")
    if (grepl("presso", m) && grepl("raw", m)) return("MR-PRESSO-raw")
    if (grepl("presso", m)) return("MR-PRESSO")
    m
  }

  .norm_outcome <- function(o) {
    o <- toupper(trimws(as.character(o)))
    if (o %in% c("DM", "DIABETES", "T2D", "T2DM")) return("diabetes")
    if (o == "CVD") return("CVD")
    if (o == "CKD") return("CKD")
    tolower(o)
  }

  d$Method_n <- vapply(d$Method, .norm_method, character(1))
  d$Outcome_n <- vapply(d$Outcome, .norm_outcome, character(1))
  d$OR_txt <- mapply(
    .fmt_or,
    if ("OR (95% CI)" %in% names(d)) d[["OR (95% CI)"]] else rep("", nrow(d)),
    if ("beta" %in% names(d)) d$beta else if ("b" %in% names(d)) d$b else rep(NA, nrow(d)),
    if ("se" %in% names(d)) d$se else rep(NA, nrow(d)),
    USE.NAMES = FALSE
  )
  d$P_txt <- vapply(d$P, .fmt_p_paper, character(1))

  # PRESSO：优先 outlier-corrected；若无则用 raw
  pick_row <- function(outc, method_keys) {
    for (mk in method_keys) {
      hit <- d[d$Outcome_n == outc & d$Method_n == mk, , drop = FALSE]
      if (nrow(hit)) return(hit[1L, , drop = FALSE])
    }
    NULL
  }

  outcomes <- c("CVD", "CKD", "diabetes")
  methods_wide <- list(
    IVW = c("IVW"),
    `MR-Egger` = c("MR-Egger"),
    `Weighted median` = c("Weighted median"),
    `MR-PRESSO` = c("MR-PRESSO", "MR-PRESSO-raw")
  )

  wide <- data.frame(
    `Exposure-outcome` = character(0),
    `No. of SNVs` = integer(0),
    `IVW_OR` = character(0), `IVW_P` = character(0),
    `Egger_OR` = character(0), `Egger_P` = character(0),
    `WM_OR` = character(0), `WM_P` = character(0),
    `PRESSO_OR` = character(0), `PRESSO_P` = character(0),
    check.names = FALSE, stringsAsFactors = FALSE
  )

  for (oc in outcomes) {
    label <- paste0("SUA on ", oc)
    n_snv <- NA_integer_
    cells <- list()
    for (mn in names(methods_wide)) {
      hit <- pick_row(oc, methods_wide[[mn]])
      if (is.null(hit)) {
        cells[[paste0(mn, "_OR")]] <- ""
        cells[[paste0(mn, "_P")]] <- ""
      } else {
        n_snv <- as.integer(hit$N_SNPs[1L])
        cells[[paste0(mn, "_OR")]] <- hit$OR_txt[1L]
        cells[[paste0(mn, "_P")]] <- hit$P_txt[1L]
      }
    }
    wide <- rbind(wide, data.frame(
      `Exposure-outcome` = label,
      `No. of SNVs` = n_snv,
      `IVW_OR` = cells[["IVW_OR"]], `IVW_P` = cells[["IVW_P"]],
      `Egger_OR` = cells[["MR-Egger_OR"]], `Egger_P` = cells[["MR-Egger_P"]],
      `WM_OR` = cells[["Weighted median_OR"]], `WM_P` = cells[["Weighted median_P"]],
      `PRESSO_OR` = cells[["MR-PRESSO_OR"]], `PRESSO_P` = cells[["MR-PRESSO_P"]],
      check.names = FALSE, stringsAsFactors = FALSE
    ))
  }

  # 发表列名（与双行表头配合：colnames 作第二行）
  body <- data.frame(
    V1 = wide[["Exposure-outcome"]],
    V2 = wide[["No. of SNVs"]],
    V3 = wide$IVW_OR, V4 = wide$IVW_P,
    V5 = wide$Egger_OR, V6 = wide$Egger_P,
    V7 = wide$WM_OR, V8 = wide$WM_P,
    V9 = wide$PRESSO_OR, V10 = wide$PRESSO_P,
    stringsAsFactors = FALSE
  )

  h1 <- c(
    "", "",
    "IVW", NA_character_,
    "MR-Egger", NA_character_,
    "Weighted median", NA_character_,
    "MR-PRESSO", NA_character_
  )
  h2 <- c(
    "Exposure-outcome", "No. of SNVs",
    "OR (95% CI)", "P value",
    "OR (95% CI)", "P value",
    "OR (95% CI)", "P value",
    "OR (95% CI)", "P value"
  )

  xlsx_path <- file.path(tab_dir, "Table 3-NHANES. MR causal estimates SUA.xlsx")
  title <- paste0(
    "Table 3-NHANES. MR estimates from different methods of assessing ",
    "the causal effect between SUA and each CRM condition"
  )
  footnotes <- c(
    paste0(
      "CKD indicates chronic kidney disease; CRM, cardiac, renal, and metabolic; ",
      "CVD, cardiovascular disease; IVW, inverse variance weighting; MR, Mendelian ",
      "randomization; MR-PRESSO, Mendelian Randomization Pleiotropy Residual Sum and ",
      "Outlier; OR, odds ratios; SNV, single-nucleotide variant; and SUA, serum uric acid."
    ),
    "MR-PRESSO column uses the outlier-corrected estimate when available; otherwise the raw estimate."
  )

  export_sci_table(
    body, xlsx_path, title = title,
    header_row1 = h1, header_row2 = h2,
    latex_include_colnames = FALSE,
    excel_use_prepared = FALSE,
    table_footnotes = footnotes
  )
  ctx <- list(output_dir = dirname(tab_dir), output_dir_tables = tab_dir)
  ctx <- render_queued_tables(ctx)
  unlink(list.files(tab_dir, pattern = "\\.tex$", full.names = TRUE))

  # 宽表 csv 存档
  utils::write.csv(wide, file.path(arch, "Table_3_MR_wide.csv"), row.names = FALSE)
  print(wide)
  cli::cli_alert_success("Wrote {xlsx_path}")

  invisible(TRUE)
}

# ---- from rerun_table_s3_baseline_hu.R ----
crm70_build_table_s3_baseline_hu <- function(...) {
  # =============================================================================
  #  重写交付物 Table S3：对齐原文补充 Table S4
  #  （NHANES，按高尿酸分层；Variables | Normal UA | Hyperuricemia | P）
  # =============================================================================

  repo <- .crm70_repo_root()
  options(pipeline.database_name = "NHANES")
  .crm70_ensure_utils(repo)

  `%||%` <- function(a, b) if (!is.null(a) && length(a)) a else b

  proj <- .crm70_default_proj()
  tab_dir <- getOption("crm70.tab_dir", file.path(proj, "NHANES_pub_deliverables", "Tables"))
  arch <- file.path(tab_dir, "_archive_internal")
  dir.create(arch, recursive = TRUE, showWarnings = FALSE)

  ck_path <- file.path(proj, "checkpoints/_shared/main/crm_nhanes_derive.rds")
  ck <- readRDS(ck_path)
  d0 <- ck$ctx$data$cleaned %||% ck$ctx$data$raw
  if (is.null(d0) || !nrow(d0)) stop("checkpoint 无 cleaned/raw 数据")

  suppressPackageStartupMessages(library(survey, warn.conflicts = FALSE))
  options(survey.lonely.psu = "adjust")

  # ---- 派生对齐原文 S4 的展示变量 ---------------------------------------------
  d <- d0
  d <- d[!is.na(d$hyperuricemia) & !is.na(d$new_Weight) & is.finite(d$new_Weight), , drop = FALSE]
  d$HU_grp <- factor(
    ifelse(d$hyperuricemia == 1L, "Hyperuricemia", "Normal uric acid"),
    levels = c("Normal uric acid", "Hyperuricemia")
  )

  # Sex
  g <- tolower(trimws(as.character(d$Gender)))
  d$Sex <- factor(
    ifelse(g %in% c("f", "female", "2", "女", "女性"), "Women", "Men"),
    levels = c("Men", "Women")
  )

  # Race（保留 NHANES 五分类；Other Race → Other race）
  race <- as.character(d$Race)
  race[race == "Other Race"] <- "Other race"
  d$Race_f <- factor(
    race,
    levels = c(
      "Mexican American", "Other Hispanic", "Non-Hispanic White",
      "Non-Hispanic Black", "Other race"
    )
  )

  # Education（数据仅二分；脚注说明与原文五档不同）
  edu <- as.character(d$Education)
  d$Education_f <- factor(edu, levels = c("Non-higher education", "Higher education"))

  # Marital（数据仅二分）
  ms <- as.character(d$Marital_Status)
  d$Marital_f <- factor(
    ifelse(ms == "Married", "Married/Living with partner", "Widowed/divorced/separated/Never married"),
    levels = c("Married/Living with partner", "Widowed/divorced/separated/Never married")
  )

  # Poverty：PIR < 1.3（数据已分箱；原文 Poverty 确切阈值【证据不足】，常用 PIR<1.3）
  pir <- as.character(d$PIR)
  d$Poverty <- factor(as.integer(pir == "< 1.3"), levels = c(0L, 1L), labels = c("No", "Yes"))

  # 血脂 mmol/L（原文单位）
  d$LDL_mmol <- suppressWarnings(as.numeric(d$LDL) / 38.67)
  d$TG_mmol <- suppressWarnings(as.numeric(d$TG) / 88.57)

  # BMI 分类
  bmi <- suppressWarnings(as.numeric(d$BMI))
  d$BMI_cat <- factor(
    ifelse(bmi < 25, "< 25.0",
           ifelse(bmi < 30, "25.0-29.9", "≥ 30.0")),
    levels = c("< 25.0", "25.0-29.9", "≥ 30.0")
  )

  # Smoking：ever（Former+Current），对齐原文单行 Smoking (%)
  sm <- as.character(d$Smoke)
  d$Smoking <- factor(
    as.integer(sm %in% c("Former", "Current")),
    levels = c(0L, 1L), labels = c("No", "Yes")
  )

  # 二值临床变量 → Yes/No
  .to_yn <- function(x) {
    xb <- suppressWarnings(as.integer(x))
    factor(ifelse(xb == 1L, "Yes", "No"), levels = c("No", "Yes"))
  }
  d$Hypertension_f <- .to_yn(d$Hypertension)
  d$Gout_f <- .to_yn(d$gout)
  d$CVD_f <- .to_yn(d$CVD)
  d$Diabetes_f <- .to_yn(d$Diabetes)
  d$CKD_f <- .to_yn(d$CKD)
  d$CRM_f <- factor(as.integer(d$CRM_count), levels = 0:3, labels = as.character(0:3))

  n0 <- sum(d$HU_grp == "Normal uric acid")
  n1 <- sum(d$HU_grp == "Hyperuricemia")

  design <- survey::svydesign(
    ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~new_Weight,
    data = d, nest = TRUE
  )
  des0 <- subset(design, HU_grp == "Normal uric acid")
  des1 <- subset(design, HU_grp == "Hyperuricemia")

  .fmt_p_paper <- function(p) {
    p <- suppressWarnings(as.numeric(p)[1L])
    if (!is.finite(p)) return("")
    if (p < 0.01) return("<0.01")
    if (p >= 0.995) return(sprintf("%.3f", p))
    if (p >= 0.1) return(sprintf("%.3f", p))
    sprintf("%.2f", p)
  }

  .mean_sd <- function(des, var) {
    form <- stats::as.formula(paste0("~", var))
    mu <- as.numeric(survey::svymean(form, des, na.rm = TRUE))
    vr <- as.numeric(survey::svyvar(form, des, na.rm = TRUE))
    sprintf("%.2f (%.2f)", mu, sqrt(max(vr, 0)))
  }

  .cat_cell <- function(des, var, level) {
    x <- des$variables[[var]]
    n_unw <- sum(as.character(x) == as.character(level), na.rm = TRUE)
    des2 <- stats::update(des, `.hit` = as.integer(as.character(des$variables[[var]]) == as.character(level)))
    pct <- as.numeric(survey::svymean(~`.hit`, des2, na.rm = TRUE)) * 100
    sprintf("%d (%.1f)", n_unw, pct)
  }

  .p_cont <- function(var) {
    fit <- tryCatch(
      survey::svyglm(stats::as.formula(paste0(var, " ~ HU_grp")), design = design),
      error = function(e) NULL
    )
    if (is.null(fit)) return(NA_real_)
    rt <- tryCatch(survey::regTermTest(fit, "HU_grp"), error = function(e) NULL)
    if (is.null(rt) || is.null(rt$p)) return(NA_real_)
    as.numeric(rt$p)[1L]
  }

  .p_cat <- function(var) {
    res <- tryCatch(
      survey::svychisq(stats::as.formula(paste0("~", var, "+ HU_grp")), design = design),
      error = function(e) NULL
    )
    if (is.null(res) || is.null(res$p.value)) return(NA_real_)
    as.numeric(res$p.value)[1L]
  }

  col0 <- sprintf("Normal uric acid (Unweighted n= %d)", n0)
  col1 <- sprintf("Hyperuricemia (Unweighted n = %d)", n1)

  rows <- list()
  add_row <- function(var_label, cell0, cell1, p = "", indent = FALSE) {
    lab <- if (isTRUE(indent)) paste0("  ", var_label) else var_label
    df <- data.frame(
      Variables = lab,
      V0 = as.character(cell0),
      V1 = as.character(cell1),
      `P value` = as.character(p),
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
    names(df)[2:3] <- c(col0, col1)
    rows[[length(rows) + 1L]] <<- df
  }

  # Weighted n (%)
  w0 <- sum(d$new_Weight[d$HU_grp == "Normal uric acid"], na.rm = TRUE)
  w1 <- sum(d$new_Weight[d$HU_grp == "Hyperuricemia"], na.rm = TRUE)
  wtot <- w0 + w1
  add_row(
    "Weighted n (%) *",
    sprintf("%.0f (%.1f)", w0, 100 * w0 / wtot),
    sprintf("%.0f (%.1f)", w1, 100 * w1 / wtot),
    ""
  )

  # Age
  add_row("Age (mean [SD])", .mean_sd(des0, "Age"), .mean_sd(des1, "Age"), .fmt_p_paper(.p_cont("Age")))

  # Sex
  add_row("Sex (%)", "", "", .fmt_p_paper(.p_cat("Sex")))
  add_row("Men", .cat_cell(des0, "Sex", "Men"), .cat_cell(des1, "Sex", "Men"), "", TRUE)
  add_row("Women", .cat_cell(des0, "Sex", "Women"), .cat_cell(des1, "Sex", "Women"), "", TRUE)

  # Race
  add_row("Race (%)", "", "", .fmt_p_paper(.p_cat("Race_f")))
  for (lv in levels(d$Race_f)) {
    add_row(lv, .cat_cell(des0, "Race_f", lv), .cat_cell(des1, "Race_f", lv), "", TRUE)
  }

  # Education
  add_row("Education level (%)", "", "", .fmt_p_paper(.p_cat("Education_f")))
  for (lv in levels(d$Education_f)) {
    if (all(is.na(d$Education_f)) || !(lv %in% levels(droplevels(d$Education_f)))) next
    add_row(lv, .cat_cell(des0, "Education_f", lv), .cat_cell(des1, "Education_f", lv), "", TRUE)
  }

  # Marital
  add_row("Marital status (%)", "", "", .fmt_p_paper(.p_cat("Marital_f")))
  for (lv in levels(d$Marital_f)) {
    add_row(lv, .cat_cell(des0, "Marital_f", lv), .cat_cell(des1, "Marital_f", lv), "", TRUE)
  }

  # Poverty (Yes)
  add_row(
    "Poverty (%)",
    .cat_cell(des0, "Poverty", "Yes"),
    .cat_cell(des1, "Poverty", "Yes"),
    .fmt_p_paper(.p_cat("Poverty"))
  )

  # lipids / SUA / eGFR
  add_row("LDL-C (mean [SD])", .mean_sd(des0, "LDL_mmol"), .mean_sd(des1, "LDL_mmol"), .fmt_p_paper(.p_cont("LDL_mmol")))
  add_row("Triglycerides (mean [SD])", .mean_sd(des0, "TG_mmol"), .mean_sd(des1, "TG_mmol"), .fmt_p_paper(.p_cont("TG_mmol")))
  add_row("Uric acid (mean [SD])", .mean_sd(des0, "SUA"), .mean_sd(des1, "SUA"), .fmt_p_paper(.p_cont("SUA")))
  add_row("eGFR (mean [SD])", .mean_sd(des0, "eGFR"), .mean_sd(des1, "eGFR"), .fmt_p_paper(.p_cont("eGFR")))

  # BMI
  add_row("BMI (%)", "", "", .fmt_p_paper(.p_cat("BMI_cat")))
  for (lv in levels(d$BMI_cat)) {
    add_row(lv, .cat_cell(des0, "BMI_cat", lv), .cat_cell(des1, "BMI_cat", lv), "", TRUE)
  }

  # binary clinical
  add_row("Smoking (%)", .cat_cell(des0, "Smoking", "Yes"), .cat_cell(des1, "Smoking", "Yes"), .fmt_p_paper(.p_cat("Smoking")))
  add_row("Hypertension (%)", .cat_cell(des0, "Hypertension_f", "Yes"), .cat_cell(des1, "Hypertension_f", "Yes"), .fmt_p_paper(.p_cat("Hypertension_f")))
  add_row("Gout (%)", .cat_cell(des0, "Gout_f", "Yes"), .cat_cell(des1, "Gout_f", "Yes"), .fmt_p_paper(.p_cat("Gout_f")))
  add_row("Cardiovascular disease (%)", .cat_cell(des0, "CVD_f", "Yes"), .cat_cell(des1, "CVD_f", "Yes"), .fmt_p_paper(.p_cat("CVD_f")))
  add_row("Diabetes (%)", .cat_cell(des0, "Diabetes_f", "Yes"), .cat_cell(des1, "Diabetes_f", "Yes"), .fmt_p_paper(.p_cat("Diabetes_f")))
  add_row("Chronic kidney disease (%)", .cat_cell(des0, "CKD_f", "Yes"), .cat_cell(des1, "CKD_f", "Yes"), .fmt_p_paper(.p_cat("CKD_f")))

  # CRM count
  add_row("No. of CRM conditions (%)", "", "", .fmt_p_paper(.p_cat("CRM_f")))
  for (lv in levels(d$CRM_f)) {
    add_row(lv, .cat_cell(des0, "CRM_f", lv), .cat_cell(des1, "CRM_f", lv), "", TRUE)
  }

  out <- do.call(rbind, rows)
  rownames(out) <- NULL

  # 归档旧 CRM 分层 S3
  old <- file.path(tab_dir, "Table S3-NHANES. Weighted baseline by CRM count.xlsx")
  if (file.exists(old)) {
    file.rename(old, file.path(arch, paste0("prev_", basename(old))))
  }

  xlsx <- file.path(tab_dir, "Table S3-NHANES. Weighted baseline by hyperuricemia.xlsx")
  title <- paste0(
    "Table S3-NHANES. Baseline and Demographic characteristics of participants ",
    "aged 45 and over with and without hyperuricemia in NHANES, 2007-2018"
  )
  footnotes <- c(
    paste0(
      "*Data are presented as unweighted n (weighted percentage) for categorical variables ",
      "and weighted means (SD) for continuous variables."
    ),
    paste0(
      "Aligned with Han et al. 2025 JAHA supplement Table S4 layout (Normal uric acid vs Hyperuricemia). ",
      "LDL-C and triglycerides converted to mmol/L (÷38.67 / ÷88.57). ",
      "Poverty defined as PIR < 1.3; Smoking = former or current. ",
      "Education/marital coding in this dataset is coarser than the paper’s NHANES categories ",
      "(【证据不足】无法还原原文五档教育/三档婚姻的精确映射)."
    ),
    sprintf(
      "Analytic N with non-missing hyperuricemia and survey weight: %d (Normal=%d; Hyperuricemia=%d). ",
      nrow(d), n0, n1
    )
  )

  export_sci_table(
    out, xlsx, title = title,
    excel_use_prepared = FALSE,
    table_footnotes = footnotes
  )
  ctx <- list(output_dir = dirname(tab_dir), output_dir_tables = tab_dir)
  ctx <- render_queued_tables(ctx)
  unlink(list.files(tab_dir, pattern = "\\.tex$", full.names = TRUE))

  utils::write.csv(out, file.path(arch, "Table_S3_Baseline_by_hyperuricemia.csv"), row.names = FALSE)
  print(utils::head(out, 20))
  cli::cli_alert_success("Wrote {xlsx} (n0={n0}, n1={n1})")

  invisible(TRUE)
}

# ---- from rerun_table_s4_baseline_crm1_hu.R ----
crm70_build_table_s4_baseline_crm1 <- function(...) {
  # =============================================================================
  #  重写交付物 Table S4：对齐原文补充 Table S6
  #  （NHANES，CRM≥1 人群，按高尿酸分层；版式同 Table S3 / 原文 S4）
  # =============================================================================

  repo <- .crm70_repo_root()
  options(pipeline.database_name = "NHANES")
  .crm70_ensure_utils(repo)

  `%||%` <- function(a, b) if (!is.null(a) && length(a)) a else b

  proj <- .crm70_default_proj()
  tab_dir <- getOption("crm70.tab_dir", file.path(proj, "NHANES_pub_deliverables", "Tables"))
  arch <- file.path(tab_dir, "_archive_internal")
  dir.create(arch, recursive = TRUE, showWarnings = FALSE)

  ck_path <- file.path(proj, "checkpoints/_shared/main/crm_nhanes_derive.rds")
  ck <- readRDS(ck_path)
  d0 <- ck$ctx$data$cleaned %||% ck$ctx$data$raw
  if (is.null(d0) || !nrow(d0)) stop("checkpoint 无 cleaned/raw 数据")

  suppressPackageStartupMessages(library(survey, warn.conflicts = FALSE))
  options(survey.lonely.psu = "adjust")

  # ---- 派生对齐原文 S6 的展示变量（先限 CRM≥1）--------------------------------
  d <- d0
  crm_n <- suppressWarnings(as.integer(d$CRM_count))
  d <- d[
    !is.na(d$hyperuricemia) &
      !is.na(d$new_Weight) & is.finite(d$new_Weight) &
      !is.na(crm_n) & crm_n >= 1L,
    , drop = FALSE
  ]
  d$HU_grp <- factor(
    ifelse(d$hyperuricemia == 1L, "Hyperuricemia", "Normal uric acid"),
    levels = c("Normal uric acid", "Hyperuricemia")
  )

  # Sex
  g <- tolower(trimws(as.character(d$Gender)))
  d$Sex <- factor(
    ifelse(g %in% c("f", "female", "2", "女", "女性"), "Women", "Men"),
    levels = c("Men", "Women")
  )

  # Race（保留 NHANES 五分类；Other Race → Other race）
  race <- as.character(d$Race)
  race[race == "Other Race"] <- "Other race"
  d$Race_f <- factor(
    race,
    levels = c(
      "Mexican American", "Other Hispanic", "Non-Hispanic White",
      "Non-Hispanic Black", "Other race"
    )
  )

  # Education（数据仅二分；脚注说明与原文五档不同）
  edu <- as.character(d$Education)
  d$Education_f <- factor(edu, levels = c("Non-higher education", "Higher education"))

  # Marital（数据仅二分）
  ms <- as.character(d$Marital_Status)
  d$Marital_f <- factor(
    ifelse(ms == "Married", "Married/Living with partner", "Widowed/divorced/separated/Never married"),
    levels = c("Married/Living with partner", "Widowed/divorced/separated/Never married")
  )

  # Poverty：PIR < 1.3（数据已分箱；原文 Poverty 确切阈值【证据不足】，常用 PIR<1.3）
  pir <- as.character(d$PIR)
  d$Poverty <- factor(as.integer(pir == "< 1.3"), levels = c(0L, 1L), labels = c("No", "Yes"))

  # 血脂 mmol/L（原文单位）
  d$LDL_mmol <- suppressWarnings(as.numeric(d$LDL) / 38.67)
  d$TG_mmol <- suppressWarnings(as.numeric(d$TG) / 88.57)

  # BMI 分类
  bmi <- suppressWarnings(as.numeric(d$BMI))
  d$BMI_cat <- factor(
    ifelse(bmi < 25, "< 25.0",
           ifelse(bmi < 30, "25.0-29.9", "≥ 30.0")),
    levels = c("< 25.0", "25.0-29.9", "≥ 30.0")
  )

  # Smoking：ever（Former+Current），对齐原文单行 Smoking (%)
  sm <- as.character(d$Smoke)
  d$Smoking <- factor(
    as.integer(sm %in% c("Former", "Current")),
    levels = c(0L, 1L), labels = c("No", "Yes")
  )

  # 二值临床变量 → Yes/No
  .to_yn <- function(x) {
    xb <- suppressWarnings(as.integer(x))
    factor(ifelse(xb == 1L, "Yes", "No"), levels = c("No", "Yes"))
  }
  d$Hypertension_f <- .to_yn(d$Hypertension)
  d$Gout_f <- .to_yn(d$gout)
  d$CVD_f <- .to_yn(d$CVD)
  d$Diabetes_f <- .to_yn(d$Diabetes)
  d$CKD_f <- .to_yn(d$CKD)
  d$CRM_f <- factor(as.integer(d$CRM_count), levels = 1:3, labels = as.character(1:3))

  n0 <- sum(d$HU_grp == "Normal uric acid")
  n1 <- sum(d$HU_grp == "Hyperuricemia")

  design <- survey::svydesign(
    ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~new_Weight,
    data = d, nest = TRUE
  )
  des0 <- subset(design, HU_grp == "Normal uric acid")
  des1 <- subset(design, HU_grp == "Hyperuricemia")

  .fmt_p_paper <- function(p) {
    p <- suppressWarnings(as.numeric(p)[1L])
    if (!is.finite(p)) return("")
    if (p < 0.01) return("<0.01")
    if (p >= 0.995) return(sprintf("%.3f", p))
    if (p >= 0.1) return(sprintf("%.3f", p))
    sprintf("%.2f", p)
  }

  .mean_sd <- function(des, var) {
    form <- stats::as.formula(paste0("~", var))
    mu <- as.numeric(survey::svymean(form, des, na.rm = TRUE))
    vr <- as.numeric(survey::svyvar(form, des, na.rm = TRUE))
    sprintf("%.2f (%.2f)", mu, sqrt(max(vr, 0)))
  }

  .cat_cell <- function(des, var, level) {
    x <- des$variables[[var]]
    n_unw <- sum(as.character(x) == as.character(level), na.rm = TRUE)
    des2 <- stats::update(des, `.hit` = as.integer(as.character(des$variables[[var]]) == as.character(level)))
    pct <- as.numeric(survey::svymean(~`.hit`, des2, na.rm = TRUE)) * 100
    sprintf("%d (%.1f)", n_unw, pct)
  }

  .p_cont <- function(var) {
    fit <- tryCatch(
      survey::svyglm(stats::as.formula(paste0(var, " ~ HU_grp")), design = design),
      error = function(e) NULL
    )
    if (is.null(fit)) return(NA_real_)
    rt <- tryCatch(survey::regTermTest(fit, "HU_grp"), error = function(e) NULL)
    if (is.null(rt) || is.null(rt$p)) return(NA_real_)
    as.numeric(rt$p)[1L]
  }

  .p_cat <- function(var) {
    res <- tryCatch(
      survey::svychisq(stats::as.formula(paste0("~", var, "+ HU_grp")), design = design),
      error = function(e) NULL
    )
    if (is.null(res) || is.null(res$p.value)) return(NA_real_)
    as.numeric(res$p.value)[1L]
  }

  col0 <- sprintf("Normal uric acid (Unweighted n= %d)", n0)
  col1 <- sprintf("Hyperuricemia (Unweighted n = %d)", n1)

  rows <- list()
  add_row <- function(var_label, cell0, cell1, p = "", indent = FALSE) {
    lab <- if (isTRUE(indent)) paste0("  ", var_label) else var_label
    df <- data.frame(
      Variables = lab,
      V0 = as.character(cell0),
      V1 = as.character(cell1),
      `P value` = as.character(p),
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
    names(df)[2:3] <- c(col0, col1)
    rows[[length(rows) + 1L]] <<- df
  }

  # Weighted n (%)
  w0 <- sum(d$new_Weight[d$HU_grp == "Normal uric acid"], na.rm = TRUE)
  w1 <- sum(d$new_Weight[d$HU_grp == "Hyperuricemia"], na.rm = TRUE)
  wtot <- w0 + w1
  add_row(
    "Weighted n (%) *",
    sprintf("%.0f (%.1f)", w0, 100 * w0 / wtot),
    sprintf("%.0f (%.1f)", w1, 100 * w1 / wtot),
    ""
  )

  # Age
  add_row("Age (mean [SD])", .mean_sd(des0, "Age"), .mean_sd(des1, "Age"), .fmt_p_paper(.p_cont("Age")))

  # Sex
  add_row("Sex (%)", "", "", .fmt_p_paper(.p_cat("Sex")))
  add_row("Men", .cat_cell(des0, "Sex", "Men"), .cat_cell(des1, "Sex", "Men"), "", TRUE)
  add_row("Women", .cat_cell(des0, "Sex", "Women"), .cat_cell(des1, "Sex", "Women"), "", TRUE)

  # Race
  add_row("Race (%)", "", "", .fmt_p_paper(.p_cat("Race_f")))
  for (lv in levels(d$Race_f)) {
    add_row(lv, .cat_cell(des0, "Race_f", lv), .cat_cell(des1, "Race_f", lv), "", TRUE)
  }

  # Education
  add_row("Education level (%)", "", "", .fmt_p_paper(.p_cat("Education_f")))
  for (lv in levels(d$Education_f)) {
    if (all(is.na(d$Education_f)) || !(lv %in% levels(droplevels(d$Education_f)))) next
    add_row(lv, .cat_cell(des0, "Education_f", lv), .cat_cell(des1, "Education_f", lv), "", TRUE)
  }

  # Marital
  add_row("Marital status (%)", "", "", .fmt_p_paper(.p_cat("Marital_f")))
  for (lv in levels(d$Marital_f)) {
    add_row(lv, .cat_cell(des0, "Marital_f", lv), .cat_cell(des1, "Marital_f", lv), "", TRUE)
  }

  # Poverty (Yes)
  add_row(
    "Poverty (%)",
    .cat_cell(des0, "Poverty", "Yes"),
    .cat_cell(des1, "Poverty", "Yes"),
    .fmt_p_paper(.p_cat("Poverty"))
  )

  # lipids / SUA / eGFR
  add_row("LDL-C (mean [SD])", .mean_sd(des0, "LDL_mmol"), .mean_sd(des1, "LDL_mmol"), .fmt_p_paper(.p_cont("LDL_mmol")))
  add_row("Triglycerides (mean [SD])", .mean_sd(des0, "TG_mmol"), .mean_sd(des1, "TG_mmol"), .fmt_p_paper(.p_cont("TG_mmol")))
  add_row("Uric acid (mean [SD])", .mean_sd(des0, "SUA"), .mean_sd(des1, "SUA"), .fmt_p_paper(.p_cont("SUA")))
  add_row("eGFR (mean [SD])", .mean_sd(des0, "eGFR"), .mean_sd(des1, "eGFR"), .fmt_p_paper(.p_cont("eGFR")))

  # BMI
  add_row("BMI (%)", "", "", .fmt_p_paper(.p_cat("BMI_cat")))
  for (lv in levels(d$BMI_cat)) {
    add_row(lv, .cat_cell(des0, "BMI_cat", lv), .cat_cell(des1, "BMI_cat", lv), "", TRUE)
  }

  # binary clinical
  add_row("Smoking (%)", .cat_cell(des0, "Smoking", "Yes"), .cat_cell(des1, "Smoking", "Yes"), .fmt_p_paper(.p_cat("Smoking")))
  add_row("Hypertension (%)", .cat_cell(des0, "Hypertension_f", "Yes"), .cat_cell(des1, "Hypertension_f", "Yes"), .fmt_p_paper(.p_cat("Hypertension_f")))
  add_row("Gout (%)", .cat_cell(des0, "Gout_f", "Yes"), .cat_cell(des1, "Gout_f", "Yes"), .fmt_p_paper(.p_cat("Gout_f")))
  add_row("Cardiovascular disease (%)", .cat_cell(des0, "CVD_f", "Yes"), .cat_cell(des1, "CVD_f", "Yes"), .fmt_p_paper(.p_cat("CVD_f")))
  add_row("Diabetes (%)", .cat_cell(des0, "Diabetes_f", "Yes"), .cat_cell(des1, "Diabetes_f", "Yes"), .fmt_p_paper(.p_cat("Diabetes_f")))
  add_row("Chronic kidney disease (%)", .cat_cell(des0, "CKD_f", "Yes"), .cat_cell(des1, "CKD_f", "Yes"), .fmt_p_paper(.p_cat("CKD_f")))

  # CRM count
  add_row("No. of CRM conditions (%)", "", "", .fmt_p_paper(.p_cat("CRM_f")))
  for (lv in levels(d$CRM_f)) {
    add_row(lv, .cat_cell(des0, "CRM_f", lv), .cat_cell(des1, "CRM_f", lv), "", TRUE)
  }

  out <- do.call(rbind, rows)
  rownames(out) <- NULL

  # 归档并替换旧亚组 Table S4
  old_names <- c(
    "Table S4-NHANES. Subgroup HU ordinal and Cox.xlsx",
    "Table S4-NHANES. Weighted baseline CRM ge1 by hyperuricemia.xlsx"
  )
  for (bn in old_names) {
    old <- file.path(tab_dir, bn)
    if (file.exists(old)) {
      file.rename(old, file.path(arch, paste0("prev_", basename(old))))
    }
  }

  xlsx <- file.path(
    tab_dir,
    "Table S4-NHANES. Weighted baseline CRM ge1 by hyperuricemia.xlsx"
  )
  title <- paste0(
    "Table S4-NHANES. Baseline and Demographic characteristics of patients with ",
    "at least 1 CRM conditions aged 45 and over with and without hyperuricemia ",
    "in NHANES, 2007-2018"
  )
  footnotes <- c(
    paste0(
      "*Data are presented as unweighted n (weighted percentage) for categorical variables ",
      "and weighted means (SD) for continuous variables."
    ),
    paste0(
      "Aligned with Han et al. 2025 JAHA supplement Table S6 ",
      "(CRM≥1 subsample; Normal uric acid vs Hyperuricemia; same layout as paper Table S4 / deliverable Table S3). ",
      "LDL-C and triglycerides converted to mmol/L (÷38.67 / ÷88.57). ",
      "Poverty defined as PIR < 1.3; Smoking = former or current. ",
      "Education/marital coding in this dataset is coarser than the paper’s NHANES categories ",
      "(【证据不足】无法还原原文五档教育/三档婚姻的精确映射)."
    ),
    sprintf(
      "Analytic N (CRM≥1, non-missing hyperuricemia and survey weight): %d (Normal=%d; Hyperuricemia=%d).",
      nrow(d), n0, n1
    )
  )

  export_sci_table(
    out, xlsx, title = title,
    excel_use_prepared = FALSE,
    table_footnotes = footnotes
  )
  ctx <- list(output_dir = dirname(tab_dir), output_dir_tables = tab_dir)
  ctx <- render_queued_tables(ctx)
  unlink(list.files(tab_dir, pattern = "\\.tex$", full.names = TRUE))

  utils::write.csv(
    out,
    file.path(arch, "Table_S4_Baseline_CRM_ge1_by_hyperuricemia.csv"),
    row.names = FALSE
  )
  print(utils::head(out, 20))
  cli::cli_alert_success("Wrote {xlsx} (CRM>=1; n0={n0}, n1={n1})")

  invisible(TRUE)
}

# ---- from rerun_table_s5_mortality_s7.R ----
crm70_build_table_s5_mortality <- function(...) {
  # =============================================================================
  #  重写交付物 Table S5：对齐原文补充 Table S7 的 NHANES 部分
  #  （不同 CRM 条件组合的全因死亡 Death/Cases 与死亡率）
  # =============================================================================

  repo <- .crm70_repo_root()
  options(pipeline.database_name = "NHANES")
  .crm70_ensure_utils(repo)

  `%||%` <- function(a, b) if (!is.null(a) && length(a)) a else b

  proj <- .crm70_default_proj()
  tab_dir <- getOption("crm70.tab_dir", file.path(proj, "NHANES_pub_deliverables", "Tables"))
  arch <- file.path(tab_dir, "_archive_internal")
  dir.create(arch, recursive = TRUE, showWarnings = FALSE)

  ck <- readRDS(file.path(proj, "checkpoints/_shared/main/crm_nhanes_derive.rds"))
  d0 <- ck$ctx$data$cleaned %||% ck$ctx$data$raw
  if (is.null(d0) || !nrow(d0)) stop("checkpoint 无 cleaned/raw")

  # 与 KM/flowchart 一致：SUA 非缺失 + 死亡随访合格 + CRM 分量完整
  d <- d0
  need <- c("SUA", "CVD", "CKD", "Diabetes", "CRM_count", "futime", "fustatus")
  miss <- setdiff(need, names(d))
  if (length(miss)) stop("缺列: ", paste(miss, collapse = ", "))

  ok <- !is.na(d$SUA) &
    !is.na(d$CVD) & !is.na(d$CKD) & !is.na(d$Diabetes) &
    !is.na(d$CRM_count) &
    !is.na(d$futime) & is.finite(d$futime) & d$futime > 0 &
    !is.na(d$fustatus)
  d <- d[ok, , drop = FALSE]
  d$CVD <- as.integer(d$CVD)
  d$CKD <- as.integer(d$CKD)
  d$Diabetes <- as.integer(d$Diabetes)
  d$dead <- as.integer(d$fustatus == 1L)

  .rate_row <- function(label, idx, indent = FALSE) {
    n <- sum(idx, na.rm = TRUE)
    deaths <- sum(d$dead[idx], na.rm = TRUE)
    rate <- if (n > 0L) 100 * deaths / n else NA_real_
    lab <- if (isTRUE(indent)) paste0("  ", label) else label
    data.frame(
      `CRM conditions` = lab,
      `Death/Cases` = sprintf("%d/%d", deaths, n),
      `Mortality rate` = if (is.finite(rate)) sprintf("%.1f%%", rate) else "",
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
  }

  cvd <- d$CVD == 1L
  ckd <- d$CKD == 1L
  dm  <- d$Diabetes == 1L

  rows <- list(
    .rate_row("CRM conditions = 1", d$CRM_count == 1L),
    .rate_row("CVD",  cvd & !ckd & !dm, TRUE),
    .rate_row("CKD",  !cvd & ckd & !dm, TRUE),
    .rate_row("DM",   !cvd & !ckd & dm, TRUE),
    .rate_row("CRM conditions = 2", d$CRM_count == 2L),
    .rate_row("CVD+CKD", cvd & ckd & !dm, TRUE),
    .rate_row("CVD+DM",  cvd & !ckd & dm, TRUE),
    .rate_row("CKD+DM",  !cvd & ckd & dm, TRUE),
    .rate_row("CRM conditions = 3", d$CRM_count == 3L),
    .rate_row("CVD+CKD+DM", cvd & ckd & dm, TRUE),
    .rate_row("CRM conditions ≥ 1", d$CRM_count >= 1L)
  )
  out <- do.call(rbind, rows)
  rownames(out) <- NULL

  # 归档旧痛风分层 S5
  old <- file.path(tab_dir, "Table S5-NHANES. Gout strata Cox HR.xlsx")
  if (file.exists(old)) {
    file.rename(old, file.path(arch, paste0("prev_", basename(old))))
  }
  # 若曾写出中间名也归档
  alt <- file.path(tab_dir, "Table S5-NHANES. Mortality rates by CRM conditions.xlsx")
  if (file.exists(alt)) {
    file.rename(alt, file.path(arch, paste0("prev_", basename(alt))))
  }

  xlsx <- file.path(tab_dir, "Table S5-NHANES. Mortality rates by CRM conditions.xlsx")
  title <- paste0(
    "Table S5-NHANES. Mortality rates of patients aged 45 and over with different ",
    "CRM conditions (NHANES portion of paper Table S7)"
  )
  footnotes <- c(
    "Death/Cases: number of all-cause deaths / number of participants in the stratum.",
    "Mortality rate: crude cumulative mortality (% deaths) during NHANES mortality follow-up.",
    paste0(
      "Aligned with Han et al. 2025 JAHA supplement Table S7 NHANES block ",
      "(CRM=1/2/3 and mutually exclusive disease combinations; CHARLS omitted). ",
      "Paper footnote “* 5-year mortality rate” applies to CHARLS; NHANES follow-up length ",
      "differs, so this table reports crude follow-up mortality (not a forced 5-year rate)."
    ),
    sprintf("Analytic N with complete CRM components and mortality follow-up: %d.", nrow(d))
  )

  export_sci_table(
    out, xlsx, title = title,
    excel_use_prepared = FALSE,
    table_footnotes = footnotes
  )
  ctx <- list(output_dir = dirname(tab_dir), output_dir_tables = tab_dir)
  ctx <- render_queued_tables(ctx)
  unlink(list.files(tab_dir, pattern = "\\.tex$", full.names = TRUE))

  utils::write.csv(out, file.path(arch, "Table_S5_Mortality_rates_CRM_NHANES.csv"), row.names = FALSE)
  print(out)
  cli::cli_alert_success("Wrote {xlsx}")

  invisible(TRUE)
}

# ---- from rerun_table_s6_paper_s9.R ----
crm70_build_table_s6_subgroup_or <- function(...) {
  # =============================================================================
  #  重写交付物 Table S6：对齐原文补充 Table S9
  #  （NHANES 年龄/性别/BMI 亚组加权有序 OR：SUA / Asymptomatic HUA / Gout）
  # =============================================================================

  repo <- .crm70_repo_root()
  options(pipeline.database_name = "NHANES")
  .crm70_ensure_utils(repo)

  `%||%` <- function(a, b) if (!is.null(a) && length(a)) a else b

  proj <- .crm70_default_proj()
  tab_dir <- getOption("crm70.tab_dir", file.path(proj, "NHANES_pub_deliverables", "Tables"))
  arch <- file.path(proj, "_archive_deliverables_internal_20260727")
  dir.create(arch, recursive = TRUE, showWarnings = FALSE)

  ck <- readRDS(file.path(proj, "checkpoints/_shared/main/crm_nhanes_derive.rds"))
  d0 <- ck$ctx$data$cleaned %||% ck$ctx$data$raw
  if (is.null(d0) || !nrow(d0)) stop("checkpoint 无 cleaned/raw")

  suppressPackageStartupMessages(library(survey, warn.conflicts = FALSE))
  options(survey.lonely.psu = "adjust")

  d <- d0
  d$gout <- suppressWarnings(as.integer(d$gout))
  d$hyperuricemia <- suppressWarnings(as.integer(d$hyperuricemia))
  d$SUA <- suppressWarnings(as.numeric(d$SUA))
  d$CRM_count <- factor(d$CRM_count, ordered = TRUE)

  # Asymptomatic HUA vs Normal control（限无痛风）
  d$asymp_HUA <- NA_integer_
  ok_ng <- !is.na(d$gout) & d$gout == 0L & !is.na(d$hyperuricemia)
  d$asymp_HUA[ok_ng] <- d$hyperuricemia[ok_ng]

  y <- "CRM_count"
  wt_col <- "new_Weight"
  psu_col <- "SDMVPSU"
  str_col <- "SDMVSTRA"
  model2_default <- c("Age", "Gender", "Race", "Education", "PIR", "BMI",
                      "Hypertension", "Smoke", "TG")
  m2_ctx <- character(0)
  cp_m2 <- file.path(proj, "by_unit/\u3010success\u3011obs_main/checkpoints/multicollinearity_final.rds")
  if (!file.exists(cp_m2)) {
    cp_m2 <- file.path(proj, "by_unit/obs_main/checkpoints/multicollinearity_final.rds")
  }
  if (file.exists(cp_m2)) {
    m2_ctx <- tryCatch({
      setdiff(
        as.character(readRDS(cp_m2)$ctx$results$Model2Factors %||% character(0)),
        c("SUA", "hyperuricemia", "gout", "CRM_count", "Group", "UricAcid")
      )
    }, error = function(e) character(0))
  }
  model2_all <- if (length(m2_ctx)) {
    intersect(m2_ctx, names(d))
  } else {
    intersect(model2_default, names(d))
  }

  .is_female <- function(g) {
    tolower(trimws(as.character(g))) %in% c("f", "female", "2", "女", "女性")
  }

  strata_list <- list(
    list(label = "Aged 45-64", idx = !is.na(d$Age) & d$Age < 65, drop = "Age"),
    list(label = "Aged 65 and above", idx = !is.na(d$Age) & d$Age >= 65, drop = "Age"),
    list(label = "Males", idx = !.is_female(d$Gender) & !is.na(d$Gender), drop = "Gender"),
    list(label = "Females", idx = .is_female(d$Gender) & !is.na(d$Gender), drop = "Gender"),
    list(label = "Normal", idx = !is.na(d$BMI) & d$BMI < 25, drop = "BMI"),
    list(label = "Overweight", idx = !is.na(d$BMI) & d$BMI >= 25 & d$BMI < 30, drop = "BMI"),
    list(label = "Obesity", idx = !is.na(d$BMI) & d$BMI >= 30, drop = "BMI")
  )

  .fmt_or <- function(or, lo, hi, p) {
    or <- suppressWarnings(as.numeric(or))
    lo <- suppressWarnings(as.numeric(lo))
    hi <- suppressWarnings(as.numeric(hi))
    p <- suppressWarnings(as.numeric(p))
    if (!is.finite(or) || !is.finite(lo) || !is.finite(hi)) return("")
    stars <- if (is.finite(p) && p < 0.01) "**" else if (is.finite(p) && p < 0.05) "*" else ""
    sprintf("%.3f (%.3f-%.3f)%s", or, lo, hi, stars)
  }

  .fit_or <- function(sub, x, covs) {
    need <- unique(c(y, x, covs, wt_col, psu_col, str_col))
    need <- intersect(need, names(sub))
    dd <- sub[, need, drop = FALSE]
    dd[[wt_col]] <- suppressWarnings(as.numeric(dd[[wt_col]]))
    dd[[x]] <- suppressWarnings(as.numeric(dd[[x]]))
    keep <- stats::complete.cases(dd[, intersect(c(y, x, covs, wt_col), names(dd)), drop = FALSE]) &
      is.finite(dd[[wt_col]])
    dd <- dd[keep, , drop = FALSE]
    dd[[y]] <- factor(dd[[y]], ordered = TRUE)
    if (nrow(dd) < 50L || nlevels(dd[[y]]) < 2L) return(NULL)
    # 暴露需有变异
    if (length(unique(dd[[x]][!is.na(dd[[x]])])) < 2L && x != "SUA") return(NULL)
    if (x == "SUA" && sd(dd[[x]], na.rm = TRUE) == 0) return(NULL)

    des <- tryCatch(
      survey::svydesign(
        ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~new_Weight,
        data = dd, nest = TRUE
      ),
      error = function(e) NULL
    )
    if (is.null(des)) return(NULL)
    fml <- stats::as.formula(paste0(
      y, " ~ ", x, if (length(covs)) paste0(" + ", paste(covs, collapse = " + ")) else ""
    ))
    fit <- tryCatch(survey::svyolr(fml, design = des), error = function(e) NULL)
    if (is.null(fit)) return(NULL)
    ct <- summary(fit)$coefficients
    if (!x %in% rownames(ct)) return(NULL)
    val <- ct[x, "Value"]; se <- ct[x, "Std. Error"]; tval <- ct[x, "t value"]
    pval <- 2 * stats::pnorm(-abs(tval))
    list(
      or = exp(val), lo = exp(val - 1.96 * se), hi = exp(val + 1.96 * se),
      p = pval, n = nrow(dd)
    )
  }

  rows <- list()
  add <- function(stratum, exposure, cell) {
    rows[[length(rows) + 1L]] <<- data.frame(
      Stratum = stratum,
      Exposure = exposure,
      `Model 2` = cell,
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
  }

  for (st in strata_list) {
    sub <- d[st$idx, , drop = FALSE]
    covs <- setdiff(model2_all, st$drop)
    add(st$label, "", "")  # stratum header row

    # SUA
    r <- .fit_or(sub, "SUA", covs)
    add(st$label, "SUA (mg/dL)", if (is.null(r)) "" else .fmt_or(r$or, r$lo, r$hi, r$p))

    # Asymptomatic HUA vs Normal control
    add(st$label, "Normal control", "1.0 (ref)")
    r <- .fit_or(sub, "asymp_HUA", covs)
    add(st$label, "Asymptomatic HUA", if (is.null(r)) "" else .fmt_or(r$or, r$lo, r$hi, r$p))

    # Gout vs Non-Gout
    add(st$label, "Non-Gout", "1.0 (ref)")
    r <- .fit_or(sub, "gout", covs)
    add(st$label, "Gout", if (is.null(r)) "" else .fmt_or(r$or, r$lo, r$hi, r$p))
  }

  out <- do.call(rbind, rows)
  rownames(out) <- NULL

  # 发表宽表：Stratum 仅在节首保留一次（其余留空，贴近原文）
  out$Stratum_disp <- out$Stratum
  keep_label <- !duplicated(out$Stratum) | out$Exposure == ""
  out$Stratum_disp[!keep_label] <- ""
  # 节首行：只显示 stratum，Exposure 空
  body <- data.frame(
    Stratum = out$Stratum_disp,
    Exposure = out$Exposure,
    `CRM conditions (Model 2)` = out[["Model 2"]],
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  # 去掉纯空节首的重复：节首 Exposure=="" 时把 Model2 也空着即可
  body <- body[!(body$Exposure == "" & body[["CRM conditions (Model 2)"]] == "" &
                   body$Stratum == ""), , drop = FALSE]
  # 重新：每个 stratum 第一行写 stratum 名到 Exposure 位置？原文是左侧缩进标题。
  # 简化为三列：Stratum | Exposure | OR

  body2 <- data.frame(
    Stratum = {
      s <- out$Stratum
      s[duplicated(s)] <- ""
      s
    },
    Exposure = out$Exposure,
    `Model 2` = out[["Model 2"]],
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  # 去掉 Exposure 与 Model2 都空且 Stratum 非空的“仅标题”行——改为保留标题行
  # 当前 out 已有标题行 Exposure=""; 保留它们但 Model2 空
  body2 <- body2[!(body2$Exposure == "" & body2$Stratum == ""), , drop = FALSE]

  old <- file.path(tab_dir, "Table S6-NHANES. MR pleiotropy heterogeneity.xlsx")
  if (file.exists(old)) {
    file.rename(old, file.path(arch, paste0("prev_", basename(old))))
  }
  alt <- file.path(tab_dir, "Table S6-NHANES. Subgroup ordinal OR SUA HUA gout.xlsx")
  if (file.exists(alt)) file.rename(alt, file.path(arch, paste0("prev_", basename(alt))))

  xlsx <- file.path(tab_dir, "Table S6-NHANES. Subgroup ordinal OR SUA HUA gout.xlsx")
  title <- paste0(
    "Table S6-NHANES. Stratified analysis of weighted odds ratios for the relationship ",
    "among different serum uric acid levels, gout and CRM conditions in NHANES, 2007-2018"
  )
  footnotes <- c(
    "* P < 0.05, ** P < 0.01.",
    "CRM conditions: Cardiac, Renal, and Metabolic conditions. SUA: Serum uric acid.",
    paste0(
      "Model 2: Adjusted for age, sex, race, education, BMI, hypertension, smoking status, ",
      "poverty (PIR) and triglyceride (stratification variable omitted within each stratum)."
    ),
    paste0(
      "Aligned with Han et al. 2025 JAHA supplement Table S9. ",
      "Asymptomatic HUA vs Normal control estimated among non-gout participants; ",
      "Gout vs Non-Gout among all participants with non-missing gout."
    )
  )

  export_sci_table(
    body2, xlsx, title = title,
    excel_use_prepared = FALSE,
    table_footnotes = footnotes
  )
  ctx <- list(output_dir = dirname(tab_dir), output_dir_tables = tab_dir)
  ctx <- render_queued_tables(ctx)
  unlink(list.files(tab_dir, pattern = "\\.tex$", full.names = TRUE))

  utils::write.csv(out, file.path(arch, "Table_S6_paperS9_subgroup_ordinal.csv"), row.names = FALSE)
  print(body2)
  cli::cli_alert_success("Wrote {xlsx}")

  invisible(TRUE)
}

# ---- from rerun_table_s7_paper_s11.R ----
crm70_build_table_s7_subgroup_hr <- function(...) {
  # =============================================================================
  #  新增交付物 Table S7：对齐原文补充 Table S11
  #  （CRM 0 / ≥1 分层 × 年龄/性别/BMI 亚组加权 Cox HR：SUA / HUA·gout 分类）
  # =============================================================================

  repo <- .crm70_repo_root()
  options(pipeline.database_name = "NHANES")
  .crm70_ensure_utils(repo)

  `%||%` <- function(a, b) if (!is.null(a) && length(a)) a else b

  proj <- .crm70_default_proj()
  tab_dir <- getOption("crm70.tab_dir", file.path(proj, "NHANES_pub_deliverables", "Tables"))
  arch <- file.path(proj, "_archive_deliverables_internal_20260727")
  dir.create(arch, recursive = TRUE, showWarnings = FALSE)

  ck <- readRDS(file.path(proj, "checkpoints/_shared/main/crm_nhanes_derive.rds"))
  d0 <- ck$ctx$data$cleaned %||% ck$ctx$data$raw
  if (is.null(d0) || !nrow(d0)) stop("checkpoint 无 cleaned/raw")

  suppressPackageStartupMessages({
    library(survey, warn.conflicts = FALSE)
    library(survival, warn.conflicts = FALSE)
  })
  options(survey.lonely.psu = "adjust")

  d <- d0
  d$gout <- suppressWarnings(as.integer(d$gout))
  d$hyperuricemia <- suppressWarnings(as.integer(d$hyperuricemia))
  d$SUA <- suppressWarnings(as.numeric(d$SUA))
  d$CRM_count <- suppressWarnings(as.integer(d$CRM_count))
  d$futime <- suppressWarnings(as.numeric(d$futime))
  d$fustatus <- suppressWarnings(as.numeric(d$fustatus))
  d$new_Weight <- suppressWarnings(as.numeric(d$new_Weight))

  # 死亡随访分析集
  ok <- !is.na(d$SUA) & !is.na(d$CRM_count) &
    !is.na(d$futime) & is.finite(d$futime) & d$futime > 0 &
    !is.na(d$fustatus) & !is.na(d$new_Weight) & is.finite(d$new_Weight)
  if ("eligstat" %in% names(d)) {
    ok <- ok & (d$eligstat %in% c(1, "1"))
  }
  d <- d[ok, , drop = FALSE]

  # ua×gout 四分类（对照：无 HU 且无痛风）
  hu <- d$hyperuricemia; gt <- d$gout
  grp <- rep(NA_character_, nrow(d))
  okg <- !is.na(hu) & !is.na(gt)
  grp[okg & hu == 0L & gt == 0L] <- "Ref_no_HU_gout"
  grp[okg & hu == 1L & gt == 0L] <- "Asymptomatic_HU"
  grp[okg & hu == 0L & gt == 1L] <- "Gout_normal_UA"
  grp[okg & hu == 1L & gt == 1L] <- "Gout_poor_HU"
  d$ua_gout_grp <- factor(
    grp,
    levels = c("Ref_no_HU_gout", "Asymptomatic_HU", "Gout_normal_UA", "Gout_poor_HU")
  )

  model2_default <- c("Age", "Gender", "Race", "Education", "PIR", "BMI",
                      "Hypertension", "Smoke", "eGFR", "TG")
  m2_ctx <- character(0)
  cp_m2 <- file.path(proj, "by_unit/\u3010success\u3011obs_main/checkpoints/multicollinearity_final.rds")
  if (!file.exists(cp_m2)) {
    cp_m2 <- file.path(proj, "by_unit/obs_main/checkpoints/multicollinearity_final.rds")
  }
  if (file.exists(cp_m2)) {
    m2_ctx <- tryCatch({
      setdiff(
        as.character(readRDS(cp_m2)$ctx$results$Model2Factors %||% character(0)),
        c("SUA", "hyperuricemia", "gout", "CRM_count", "Group", "UricAcid")
      )
    }, error = function(e) character(0))
  }
  model2_all <- if (length(m2_ctx)) {
    intersect(m2_ctx, names(d))
  } else {
    intersect(model2_default, names(d))
  }

  .is_female <- function(g) {
    tolower(trimws(as.character(g))) %in% c("f", "female", "2", "女", "女性")
  }

  demo_strata <- list(
    list(label = "Aged 45-64", idx = !is.na(d$Age) & d$Age < 65, drop = "Age"),
    list(label = "Aged 65 and above", idx = !is.na(d$Age) & d$Age >= 65, drop = "Age"),
    list(label = "Males", idx = !.is_female(d$Gender) & !is.na(d$Gender), drop = "Gender"),
    list(label = "Females", idx = .is_female(d$Gender) & !is.na(d$Gender), drop = "Gender"),
    list(label = "Normal", idx = !is.na(d$BMI) & d$BMI < 25, drop = "BMI"),
    list(label = "Overweight", idx = !is.na(d$BMI) & d$BMI >= 25 & d$BMI < 30, drop = "BMI"),
    list(label = "Obesity", idx = !is.na(d$BMI) & d$BMI >= 30, drop = "BMI")
  )

  crm_panels <- list(
    list(label = "0 CRM", idx = d$CRM_count == 0L),
    list(label = "≥1 CRM", idx = d$CRM_count >= 1L)
  )

  .fmt_hr <- function(hr, lo, hi, p) {
    hr <- suppressWarnings(as.numeric(hr))
    lo <- suppressWarnings(as.numeric(lo))
    hi <- suppressWarnings(as.numeric(hi))
    p <- suppressWarnings(as.numeric(p))
    if (!is.finite(hr) || !is.finite(lo) || !is.finite(hi)) return("")
    stars <- if (is.finite(p) && p < 0.01) "**" else if (is.finite(p) && p < 0.05) "*" else ""
    sprintf("%.3f (%.3f-%.3f)%s", hr, lo, hi, stars)
  }

  .fit_cox_term <- function(sub, x, covs, term = x) {
    need <- unique(c("futime", "fustatus", x, covs, "new_Weight", "SDMVPSU", "SDMVSTRA"))
    need <- intersect(need, names(sub))
    dd <- sub[, need, drop = FALSE]
    keep <- stats::complete.cases(dd[, intersect(c("futime", "fustatus", x, covs, "new_Weight"), names(dd)), drop = FALSE])
    dd <- dd[keep, , drop = FALSE]
    if (nrow(dd) < 40L) return(list(cell = "", note = "n_small"))

    # 分类暴露：暴露水平过少时按原文 ‡ 处理
    if (is.factor(dd[[x]]) || (!is.numeric(dd[[x]]) && x == "ua_gout_grp")) {
      # handled below for group models
    }

    des <- tryCatch(
      survey::svydesign(
        ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~new_Weight,
        data = dd, nest = TRUE
      ),
      error = function(e) NULL
    )
    if (is.null(des)) return(list(cell = "", note = "design_fail"))

    fml <- stats::as.formula(paste0(
      "Surv(futime, fustatus) ~ ", x,
      if (length(covs)) paste0(" + ", paste(covs, collapse = " + ")) else ""
    ))
    fit <- tryCatch(survey::svycoxph(fml, design = des), error = function(e) NULL)
    if (is.null(fit)) return(list(cell = "", note = "fit_fail"))
    s <- summary(fit)
    ci <- s$conf.int
    coefs <- s$coefficients
    rn <- rownames(ci)
    # term matching
    pick <- which(rn == term | grepl(paste0("^", term), rn) | endsWith(rn, term))
    if (!length(pick)) {
      # factor dummy names like ua_gout_grpAsymptomatic_HU
      pick <- which(grepl(term, rn, fixed = TRUE))
    }
    if (!length(pick)) return(list(cell = "", note = "no_term"))
    pick <- pick[1L]
    p_col <- if ("Pr(>|z|)" %in% colnames(coefs)) "Pr(>|z|)" else colnames(coefs)[ncol(coefs)]
    lo_col <- grep("lower", colnames(ci), ignore.case = TRUE)[1L]
    hi_col <- grep("upper", colnames(ci), ignore.case = TRUE)[1L]
    list(
      cell = .fmt_hr(ci[pick, "exp(coef)"], ci[pick, lo_col], ci[pick, hi_col], coefs[rn[pick], p_col]),
      note = "ok",
      n = nrow(dd),
      events = sum(dd$fustatus == 1, na.rm = TRUE)
    )
  }

  .level_ok <- function(sub, level, min_n = 10L, min_ev = 3L) {
    hit <- sub$ua_gout_grp == level
    n <- sum(hit, na.rm = TRUE)
    ev <- sum(sub$fustatus[hit] == 1, na.rm = TRUE)
    n >= min_n && ev >= min_ev
  }

  exp_rows <- c(
    "SUA (mg/dL)",
    "Asymptomatic HUA †",
    "Gout with normal UA †",
    "Gout with poorly-controlled HUA †"
  )
  term_map <- c(
    "SUA (mg/dL)" = "SUA",
    "Asymptomatic HUA †" = "Asymptomatic_HU",
    "Gout with normal UA †" = "Gout_normal_UA",
    "Gout with poorly-controlled HUA †" = "Gout_poor_HU"
  )

  out_rows <- list()
  for (st in demo_strata) {
    # header
    out_rows[[length(out_rows) + 1L]] <- data.frame(
      Stratum = st$label,
      Exposure = "",
      `0 CRM conditions` = "",
      `≥1 CRM conditions` = "",
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
    covs <- setdiff(model2_all, st$drop)

    for (ex in exp_rows) {
      cells <- c(`0 CRM` = "", `≥1 CRM` = "")
      for (cp in crm_panels) {
        sub <- d[st$idx & cp$idx, , drop = FALSE]
        key <- if (cp$label == "0 CRM") "0 CRM" else "≥1 CRM"
        if (ex == "SUA (mg/dL)") {
          r <- .fit_cox_term(sub, "SUA", covs, term = "SUA")
          cells[[key]] <- r$cell
        } else {
          lv <- unname(term_map[[ex]])
          if (!.level_ok(sub, lv)) {
            cells[[key]] <- "- ‡"
          } else {
            # 仅保留 ref + 当前水平，做成二分类；或用全因子模型
            # 全因子更贴原文（同一模型多对比）
            r <- .fit_cox_term(sub, "ua_gout_grp", covs, term = lv)
            if (identical(r$note, "no_term") || !nzchar(r$cell)) {
              # 回退：仅 ref vs 该水平
              sub2 <- sub[sub$ua_gout_grp %in% c("Ref_no_HU_gout", lv), , drop = FALSE]
              sub2$ua_gout_grp <- factor(
                as.character(sub2$ua_gout_grp),
                levels = c("Ref_no_HU_gout", lv)
              )
              r <- .fit_cox_term(sub2, "ua_gout_grp", covs, term = lv)
            }
            cells[[key]] <- if (nzchar(r$cell)) r$cell else "- ‡"
          }
        }
      }
      out_rows[[length(out_rows) + 1L]] <- data.frame(
        Stratum = "",
        Exposure = ex,
        `0 CRM conditions` = cells[["0 CRM"]],
        `≥1 CRM conditions` = cells[["≥1 CRM"]],
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
    }
  }

  out <- do.call(rbind, out_rows)
  rownames(out) <- NULL

  xlsx <- file.path(
    tab_dir,
    "Table S7-NHANES. Subgroup Cox HR by CRM0 vs ge1.xlsx"
  )
  if (file.exists(xlsx)) {
    file.rename(xlsx, file.path(arch, paste0("prev_", basename(xlsx))))
  }

  title <- paste0(
    "Table S7-NHANES. Stratified analysis of weighted hazard ratios (95% CIs) for ",
    "all-cause mortality according to serum uric acid, hyperuricemia and gout among ",
    "participants with different CRM conditions (NHANES, 2007-2018)"
  )
  footnotes <- c(
    "* P < 0.05, ** P < 0.01.",
    "SUA: Serum uric acid; HUA: Hyperuricemia; CRM conditions: Cardiac, Renal, and Metabolic conditions.",
    "†: Compared with participants without HUA and gout.",
    paste0(
      "‡: Due to the limited number of gout patients in these subgroups, estimates are omitted ",
      "(aligned with paper Table S11 footnote)."
    ),
    paste0(
      "Model 2: Adjusted for age, sex, race, education, poverty (PIR), BMI, hypertension, ",
      "smoking status, eGFR and triglyceride (stratification variable omitted within each stratum)."
    ),
    "Aligned with Han et al. 2025 JAHA supplement Table S11 (columns: 0 CRM vs ≥1 CRM)."
  )

  export_sci_table(
    out, xlsx, title = title,
    excel_use_prepared = FALSE,
    table_footnotes = footnotes
  )
  ctx <- list(output_dir = dirname(tab_dir), output_dir_tables = tab_dir)
  ctx <- render_queued_tables(ctx)
  unlink(list.files(tab_dir, pattern = "\\.tex$", full.names = TRUE))

  utils::write.csv(out, file.path(arch, "Table_S7_paperS11_subgroup_cox.csv"), row.names = FALSE)
  print(out)
  cli::cli_alert_success("Wrote {xlsx}")

  invisible(TRUE)
}
