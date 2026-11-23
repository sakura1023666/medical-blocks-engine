#!/usr/bin/env Rscript
# 发表交付根收口（全项目唯一入口）：方法 md + 软件版本 txt + 图四目录 +
# figure/table 规范化 + Tables 仅 xlsx + 白名单修剪
#
#   Rscript run/pub/finalize_delivery_root.R \
#     --dir ".../summary_result" \
#     --study-type cross_lagged|tst|generic|ml \
#     --outcome Hypertension \
#     --exposure "Frailty Index" \
#     --databases "CHARLS,ELSA,HRS"
#
# 仅修剪（不重写 Methods；兼容旧 CLI prune_delivery_root.R）：
#   Rscript run/pub/finalize_delivery_root.R --dir ".../summary_result" --prune-only
#   Rscript run/pub/finalize_delivery_root.R --project ".../课题根" --prune-only
#
# 交付根只保留：Figures/ Tables/ Methods_statistical_analysis.md
# Methods_software_versions.txt / *中期*.pdf（见 R/pub_delivery_prune.R）

args <- commandArgs(trailingOnly = TRUE)
# 路径/文案含空格时，若上游未 shQuote，argv 会被拆成多段；拼到下一个 --flag 为止
get_opt <- function(flag, default = NULL) {
  hit <- which(args == flag)
  if (!length(hit) || hit[[1]] >= length(args)) return(default)
  i <- hit[[1]] + 1L
  parts <- character(0)
  while (i <= length(args) && !grepl("^--", args[[i]])) {
    parts <- c(parts, args[[i]])
    i <- i + 1L
  }
  if (!length(parts)) return(default)
  paste(parts, collapse = " ")
}
has_flag <- function(flag) flag %in% args

engine <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(engine) || !dir.exists(file.path(engine, "R"))) {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", ca[grep("^--file=", ca)])
  if (length(f)) {
    engine <- normalizePath(file.path(dirname(f[[1]]), "..", ".."),
                            winslash = "/", mustWork = FALSE)
  }
}
if (!dir.exists(file.path(engine, "R"))) {
  engine <- "/mnt/e/01block/01Block-new-Final"
}
Sys.setenv(MEDICAL_BLOCKS_ROOT = engine)
source(file.path(engine, "R/utils.R"), local = FALSE)
source(file.path(engine, "R/pub_software_versions.R"), local = FALSE)
source(file.path(engine, "R/pub_delivery_prune.R"), local = FALSE)
source(file.path(engine, "R/pub_xlsx_surgical.R"), local = FALSE)
source(file.path(engine, "R/pub_figure_export.R"), local = FALSE)
cl_methods <- file.path(engine, "R/cross_lagged_methods_pub.R")
if (file.exists(cl_methods)) source(cl_methods, local = FALSE)
tst_methods <- file.path(engine, "R/pub_tst_methods.R")
if (file.exists(tst_methods)) source(tst_methods, local = FALSE)
pv2_methods <- file.path(engine, "R/pub_prognosis_v2_methods.R")
if (file.exists(pv2_methods)) source(pv2_methods, local = FALSE)
ml_sum <- file.path(engine, "R/ml_index_summary_results.R")
if (file.exists(ml_sum)) source(ml_sum, local = FALSE)
ckm_pub <- file.path(engine, "R/cum_egdr_kmeans_pub.R")
if (file.exists(ckm_pub)) source(ckm_pub, local = FALSE)
gs_methods <- file.path(engine, "R/pub_gallstone_methods.R")
if (file.exists(gs_methods)) source(gs_methods, local = FALSE)
npc_pub <- file.path(engine, "R/npc_ebv_pet_pub.R")
if (file.exists(npc_pub)) source(npc_pub, local = FALSE)

dir <- get_opt("--dir", "")
proj <- get_opt("--project", "")
prune_only <- has_flag("--prune-only")

# --prune-only：只做白名单修剪（可 --dir 或 --project）
if (isTRUE(prune_only)) {
  if (nzchar(dir)) {
    if (!dir.exists(dir)) stop("目录不存在: ", dir, call. = FALSE)
    pub_delivery_normalize_fig_tab_dirs(dir)
    pub_delivery_clean_tables_xlsx_only(dir)
    if (exists("pub_delivery_scrub_display", mode = "function")) {
      tryCatch(
        pub_delivery_scrub_display(dir, root = engine),
        error = function(e) warning("display scrub: ", conditionMessage(e), call. = FALSE)
      )
    } else if (exists("pub_delivery_scrub_tables_underscores", mode = "function")) {
      tryCatch(
        pub_delivery_scrub_tables_underscores(dir, root = engine),
        error = function(e) warning("underscore scrub: ", conditionMessage(e), call. = FALSE)
      )
    }
    times_src <- file.path(engine, "R/pub_xlsx_force_times.R")
    if (file.exists(times_src)) {
      tryCatch(source(times_src, local = FALSE), error = function(e) NULL)
    }
    if (exists("pub_delivery_force_tables_times", mode = "function")) {
      tryCatch(
        pub_delivery_force_tables_times(dir),
        error = function(e) warning("Times font force: ", conditionMessage(e), call. = FALSE)
      )
    }
    res <- pub_prune_delivery_root(dir, dry_run = has_flag("--dry-run"))
    cat("PRUNE_OK dir=", normalizePath(dir), " moved=", length(res$moved %||% character(0)), "\n", sep = "")
  } else if (nzchar(proj)) {
    res <- pub_prune_project_delivery_roots(proj)
    cat("PRUNE_OK project roots=", length(res), "\n", sep = "")
  } else {
    stop("需要 --dir <summary_result> 或 --project <课题根>", call. = FALSE)
  }
  quit(save = "no", status = 0L)
}

if (!nzchar(dir) || !dir.exists(dir)) {
  stop("需要 --dir <summary_result>", call. = FALSE)
}
study_type <- tolower(get_opt("--study-type", "generic"))
outcome <- get_opt("--outcome", "the study outcome")
exposure <- get_opt("--exposure", "Frailty Index")
dbs <- strsplit(get_opt("--databases", "CHARLS,ELSA,HRS"), ",")[[1]]
dbs <- trimws(dbs)

pub_delivery_normalize_fig_tab_dirs(dir)
pub_delivery_clean_tables_xlsx_only(dir)
if (exists("pub_delivery_scrub_display", mode = "function")) {
  tryCatch(
    pub_delivery_scrub_display(dir, root = engine),
    error = function(e) warning("display scrub: ", conditionMessage(e), call. = FALSE)
  )
} else if (exists("pub_delivery_scrub_tables_underscores", mode = "function")) {
  tryCatch(
    pub_delivery_scrub_tables_underscores(dir, root = engine),
    error = function(e) warning("underscore scrub: ", conditionMessage(e), call. = FALSE)
  )
}
# Engine-level Times New Roman force on all Tables/*.xlsx (drop Calibri/Arial leftovers)
times_src <- file.path(engine, "R/pub_xlsx_force_times.R")
if (file.exists(times_src)) {
  tryCatch(source(times_src, local = FALSE), error = function(e) NULL)
}
if (exists("pub_delivery_force_tables_times", mode = "function")) {
  tryCatch(
    pub_delivery_force_tables_times(dir),
    error = function(e) warning("Times font force: ", conditionMessage(e), call. = FALSE)
  )
}

fig_dir <- file.path(dir, "Figures")
if (!dir.exists(fig_dir)) fig_dir <- file.path(dir, "figure")
if (dir.exists(fig_dir) && exists("pub_figure_ensure_formats", mode = "function")) {
  pub_figure_ensure_formats(
    fig_dir,
    config = list(pub_figures = list(
      dpi = 600L, formats_dir = TRUE,
      export_png = FALSE, export_tiff = FALSE,
      max_edge_in = 16, require_vector_pdf = TRUE
    ))
  )
  # ensure_formats 会重写 image_information/README；必须再 scrub 一次展示下划线
  if (exists("pub_delivery_scrub_image_information", mode = "function")) {
    tryCatch(
      pub_delivery_scrub_image_information(dir),
      error = function(e) warning("image_information scrub: ", conditionMessage(e), call. = FALSE)
    )
  }
}

is_tst <- grepl("tst|two.?stage|transformer", study_type, ignore.case = TRUE)
is_dbpool <- grepl("dbpool|database.?pool|blendedlos|blended.?los|cirrhosis.?pool", study_type, ignore.case = TRUE)
dbpool_methods <- file.path(engine, "R/pub_dbpool_methods.R")
if (isTRUE(is_dbpool) && file.exists(dbpool_methods)) source(dbpool_methods, local = FALSE)
.env_int <- function(key, default) {
  v <- Sys.getenv(key, unset = "")
  if (!nzchar(v)) return(as.integer(default))
  suppressWarnings(as.integer(v)[1L])
}
.env_chr <- function(key, default) {
  v <- Sys.getenv(key, unset = "")
  if (!nzchar(v)) return(as.character(default)[1L])
  as.character(v)[1L]
}
config <- list(
  project = list(
    study_type = study_type,
    analysis_group = outcome,
    disease = if (is_tst) {
      .env_chr("TST_DISEASE_LABEL", outcome)
    } else {
      outcome
    },
    disease_label = if (is_tst) .env_chr("TST_DISEASE_LABEL", "") else "",
    outcome_label = if (is_tst) {
      .env_chr("TST_OUTCOME_LABEL", "in-hospital mortality")
    } else {
      outcome
    },
    exposure = exposure,
    databases = dbs
  ),
  imputation = list(fit_on = "train"),
  tst_stroke = list(
    min_age = .env_int("TST_MIN_AGE", 18L),
    summary_primary_landmark = .env_int("TST_LANDMARK_H", 120L),
    comparator_score = .env_chr("TST_COMPARATOR", "APSIII")
  ),
  software_versions = list(
    extra_pkgs = if (is_tst) {
      c("mice", "openxlsx", "ggplot2", "pROC", "tableone", "dplyr", "data.table")
    } else if (isTRUE(is_dbpool)) {
      c("openxlsx", "ggplot2", "data.table")
    } else if (isTRUE(grepl("prognosis_v2|prognosis.?v2", study_type, ignore.case = TRUE))) {
      c("mice", "survival", "rms", "car", "pROC", "Boruta", "fastshap",
        "ggplot2", "patchwork", "openxlsx", "data.table", "tableone")
    } else {
      c("qgraph", "glmnet", "bootnet", "survey", "mice", "rms",
        "mediation", "pROC", "forestploter", "igraph")
    },
    include_python = isTRUE(is_dbpool) || isTRUE(is_tst),
    python_modules = if (is_tst) {
      c(
        "torch", "numpy", "pandas", "sklearn", "xgboost", "shap",
        "imblearn", "joblib", "openpyxl", "matplotlib"
      )
    } else if (isTRUE(is_dbpool)) {
      c("torch", "numpy", "pandas", "scipy", "sklearn", "matplotlib", "openpyxl")
    } else {
      character(0)
    },
    # TST / dbpool：只列本分析用到的 Python 模块（勿灌 lightgbm 等未用基线）
    python_modules_only = isTRUE(is_dbpool) || isTRUE(is_tst),
    # 全因死亡预后 v2：未做 Fine–Gray / 竞争风险，勿在 Methods 软件清单挂 cmprsk
    # dbpool / TST：剔除未用的 Cox/中介/LASSO 模板包
    exclude_pkgs = if (isTRUE(grepl("prognosis_v2|prognosis.?v2", study_type, ignore.case = TRUE))) {
      c("cmprsk")
    } else if (isTRUE(is_tst)) {
      c(
        "survival", "survminer", "cmprsk", "mediation", "rms", "Boruta",
        "glmnet", "Hmisc", "car", "jstable", "patchwork"
      )
    } else if (isTRUE(is_dbpool)) {
      c(
        "survival", "survminer", "cmprsk", "mediation", "rms", "Boruta",
        "glmnet", "Hmisc", "car", "tableone", "pROC", "patchwork", "dplyr",
        # TPC path does not use MICE / jstable (Cox template core — must not appear)
        "mice", "jstable"
      )
    } else {
      character(0)
    }
  )
)
if (isTRUE(is_dbpool)) {
  config$project$cohort <- .env_chr(
    "DBPOOL_COHORT",
    "ULN-all3 enzyme elevation (AST≥38 U/L, ALT≥41 U/L, and total bilirubin≥1.3 mg/dL)"
  )
  config$project$feature_set <- .env_chr(
    "DBPOOL_FEATURE_SET",
    paste0(
      "Model inputs followed prior published multi-database ICU modelling inventories ",
      "(hourly vitals + laboratories + selected medications; respiratory channels off unless ",
      "enabled; static age/sex/height/weight). Laboratories used only to define the cohort ",
      "were dropped from predictors. Variable-level inventory is Table S9 (written by ",
      "dbpool_feature_inventory.py at pack/finalize). No additional data-driven feature ",
      "hunting was performed beyond this literature-aligned inventory and the leakage exclusions."
    )
  )
  config$project$model <- .env_chr(
    "DBPOOL_MODEL",
    "Temporal Pointwise Convolution (TPC) multitask network"
  )
}
# prognosis_v2 课题字段（可用环境变量覆盖）
if (grepl("prognosis_v2|prognosis.?v2", study_type, ignore.case = TRUE)) {
  config$project$pv2_profile <- .env_chr("PV2_PROFILE", "hip_aki")
  if (grepl("sleep|dyslipid", config$project$pv2_profile, ignore.case = TRUE)) {
    config$project$cohort <- .env_chr(
      "PV2_COHORT",
      "adults aged 45 years or older with dyslipidemia"
    )
    config$project$model3_covs <- .env_chr(
      "PV2_MODEL3",
      "Age, Gender, SBP, Education, Diabetes, Hypertension, Alcohol, Smoke, BMI"
    )
    config$project$grouping <- .env_chr(
      "PV2_GROUPING",
      "five mutually exclusive categories (<5 h, 5-6 h, 6-7 h, 7-<9 h [7 to <9 hours], >=9 h; reference 7-<9 h)"
    )
    config$project$sensitivity <- .env_chr(
      "PV2_SENSITIVITY",
      "exclusion of deaths within the first year (Table S5) and a 5-year administrative horizon (Table S3)"
    )
    config$project$mediator <- .env_chr("PV2_MEDIATOR", "diastolic blood pressure (DBP)")
    config$project$primary_dbs <- .env_chr("PV2_PRIMARY_DBS", "NHANES and SHHS")
    config$project$validation_dbs <- .env_chr("PV2_VALIDATION_DBS", "CHARLS")
    config$project$exposure <- .env_chr("PV2_EXPOSURE", "sleep duration")
  } else {
    config$project$cohort <- .env_chr(
      "PV2_COHORT",
      "adults aged 65 years or older with hip arthroplasty and AKI"
    )
    config$project$model3_covs <- .env_chr("PV2_MODEL3", "Age, Gender, CHARLSON")
    config$project$grouping <- .env_chr("PV2_GROUPING", "binary (High vs Low)")
    config$project$sensitivity <- .env_chr(
      "PV2_SENSITIVITY", "90-day all-cause mortality (Table S5)"
    )
    config$project$mediator <- .env_chr("PV2_MEDIATOR", "OASIS")
  }
}

is_pv2 <- grepl("prognosis_v2|prognosis.?v2", study_type, ignore.case = TRUE)
is_ml <- grepl("^ml$|machine.?learn|ml_single|ml_dual", study_type, ignore.case = TRUE)
is_ckm <- grepl(
  "cum.?egdr|elsa.?osteo|ckm.?stroke|kmeans.?ckm|cum_egdr_kmeans",
  study_type,
  ignore.case = TRUE
)
is_gallstone <- grepl(
  "gallstone|nomogram_418|lithotripsy.?nomogram",
  study_type,
  ignore.case = TRUE
)
is_npc_ebv <- grepl(
  "npc.?ebv|ebv.?pet|npc_ebv_pet",
  study_type,
  ignore.case = TRUE
)
# NPC EBV×PET：专用 Methods + sync draft→summary_results + 白名单
if (isTRUE(is_npc_ebv) && exists("npc_ebv_pet_finalize_summary_delivery", mode = "function")) {
  draft_guess <- get_opt("--draft", "")
  if (!nzchar(draft_guess)) {
    sib <- file.path(dirname(dir), "summary（new）")
    draft_guess <- if (dir.exists(sib)) sib else dir
  }
  res <- npc_ebv_pet_finalize_summary_delivery(
    draft_root = draft_guess,
    summary_root = dir,
    project_root = if (nzchar(proj)) proj else dirname(dir),
    rewrite_methods = TRUE,
    prune = TRUE,
    sync_draft = !identical(normalizePath(draft_guess, mustWork = FALSE),
                            normalizePath(dir, mustWork = FALSE))
  )
  cat(
    "FINALIZE_OK study=npc_ebv_pet dir=", normalizePath(dir),
    " methods=", isTRUE(res$methods),
    " software=", isTRUE(res$software),
    "\n", sep = ""
  )
  quit(save = "no", status = 0L)
}
# gallstone：走专用收口（方法 + 软件版本 + PDF-only + 白名单），然后退出
if (isTRUE(is_gallstone) && exists("gallstone_finalize_summary_delivery", mode = "function")) {
  res <- gallstone_finalize_summary_delivery(
    summary_root = dir,
    project_root = if (nzchar(proj)) proj else dirname(dir),
    config = list(
      project = list(study_type = "gallstone_nomogram"),
      software_versions = list(
        extra_pkgs = c(
          "gtsummary", "car", "glmnet", "brglm2", "rms", "forestploter",
          "ggplot2", "patchwork", "pROC", "openxlsx"
        )
      ),
      pub_figures = list(export_png = FALSE, export_tiff = FALSE, dpi = 600L)
    ),
    rewrite_methods = TRUE,
    prune = TRUE
  )
  st <- if (dir.exists(fig_dir)) pub_figure_formats_status(fig_dir, config = list(
    pub_figures = list(
      export_png = FALSE, export_tiff = FALSE,
      max_edge_in = 16, require_vector_pdf = TRUE
    )
  )) else list(ok = NA)
  cat(
    "FINALIZE_OK study=gallstone dir=", normalizePath(dir),
    " fig_ok=", isTRUE(st$ok),
    " methods=", isTRUE(res$methods),
    " software=", isTRUE(res$software),
    "\n", sep = ""
  )
  quit(save = "no", status = 0L)
}
methods_lines <- if (grepl("cross.?lag|clpn", study_type) &&
                     exists("cross_lagged_methods_statistical_lines", mode = "function")) {
  cross_lagged_methods_statistical_lines(config)
} else if (is_tst && exists("pub_tst_methods_statistical_lines", mode = "function")) {
  pub_tst_methods_statistical_lines(config)
} else if (isTRUE(is_dbpool) && exists("pub_dbpool_methods_statistical_lines", mode = "function")) {
  pub_dbpool_methods_statistical_lines(config)
} else if (is_pv2 && exists("pub_prognosis_v2_methods_lines", mode = "function")) {
  pub_prognosis_v2_methods_lines(config)
} else if (is_ml && exists("ml_index_methods_statistical_lines", mode = "function")) {
  ml_index_methods_statistical_lines(config)
} else if (isTRUE(is_ckm) && exists("ckm_stroke_elsa_methods_statistical_lines", mode = "function")) {
  ckm_stroke_elsa_methods_statistical_lines(
    index_lab = exposure,
    n_analytic = suppressWarnings(as.integer(.env_int("CKM_N_ANALYTIC", NA_integer_))),
    model3_covars = strsplit(
      .env_chr("CKM_MODEL3", "Age, Gender, Marital, Dyslipidemia, Hypertension"),
      ",\\s*"
    )[[1]],
    unit_delta = {
      ud <- Sys.getenv("CKM_UNIT_DELTA", unset = "")
      if (nzchar(ud)) suppressWarnings(as.numeric(ud)[1L]) else NULL
    },
    min_age = .env_int("CKM_MIN_AGE", 50L),
    database = if (length(dbs)) dbs[[1]] else "ELSA",
    outcome_lab = outcome
  )
} else if (exists("pub_default_methods_lines", mode = "function")) {
  pub_default_methods_lines(config)
} else {
  c("# Statistical analysis", "", "See study protocol.", "")
}
methods_path <- file.path(dir, "Methods_statistical_analysis.md")
writeLines(methods_lines, methods_path, useBytes = TRUE)

# 旧名 Software_versions_for_submission.txt → 白名单标准名
legacy_soft <- file.path(dir, "Software_versions_for_submission.txt")
std_soft <- file.path(dir, "Methods_software_versions.txt")
# 始终按当前 study_type 重写（保证 exclude_pkgs 踢 mice/jstable/cmprsk 等生效）
# legacy 仅作附录素材；不得覆盖已按 study_type 清洗的 Methods_software_versions.txt
pub_write_software_versions(index_root = dir, project_root = NULL, config = config)
if (isTRUE(is_dbpool)) {
  # 训练机 PyTorch 口径（finalize 主机未必有 CUDA torch）；可用环境变量覆盖
  th <- Sys.getenv("DBPOOL_TRAINING_HOST", unset = "192.168.68.34")
  tv <- Sys.getenv("DBPOOL_TORCH_VERSION", unset = "2.6.0+cu124")
  tenv <- Sys.getenv("DBPOOL_TORCH_ENV", unset = "conda env blendedlos; TPC multitask training")
  torch_lines <- c(
    "",
    paste0("Training host (", th, ") Python packages:"),
    paste0("  torch ", tv),
    paste0("  (", tenv, ")")
  )
  if (file.exists(std_soft)) {
    writeLines(c(readLines(std_soft, warn = FALSE), torch_lines), std_soft, useBytes = TRUE)
  }
}
if (file.exists(legacy_soft) && !file.exists(std_soft)) {
  file.copy(legacy_soft, std_soft, overwrite = FALSE)
}

if (exists("pub_write_methods_software_section", mode = "function")) {
  soft_tmp <- tempfile(fileext = ".md")
  roles <- if (is_tst) {
    c(
      mice = "Multiple imputation (train-fit)",
      openxlsx = "SCI three-line xlsx",
      ggplot2 = "Publication figures",
      pROC = "ROC utilities (R side)"
    )
  } else if (isTRUE(is_dbpool)) {
    c(
      openxlsx = "SCI three-line xlsx",
      ggplot2 = "Publication figures",
      data.table = "Tabular utilities (R side)"
    )
  } else if (isTRUE(is_pv2)) {
    c(
      mice = "Multiple imputation (m = 5; Rubin pool for Cox)",
      survival = "Cox / Kaplan-Meier",
      rms = "Restricted cubic splines",
      car = "Variance inflation factors",
      Boruta = "Feature confirmation",
      pROC = "ROC / AUC / Youden",
      ggplot2 = "Publication figures",
      patchwork = "Multi-panel figures",
      openxlsx = "SCI three-line xlsx"
    )
  } else {
    c(
      mice = "Multiple imputation",
      rms = "Restricted cubic splines",
      car = "Variance inflation factors",
      glmnet = "CLPN / penalized regression",
      qgraph = "Network visualization",
      mediation = "Mediation analysis",
      pROC = "ROC / AUC",
      forestploter = "Subgroup forest",
      ggplot2 = "Publication figures",
      openxlsx = "SCI three-line xlsx"
    )
  }
  tryCatch(
    pub_write_methods_software_section(
      out_path = soft_tmp, roles = roles,
      extra_pkgs = config$software_versions$extra_pkgs,
      exclude_pkgs = config$software_versions$exclude_pkgs %||% character(0),
      append_to = methods_path
    ),
    error = function(e) NULL
  )
  if (file.exists(soft_tmp)) unlink(soft_tmp)
  sec <- file.path(dir, "Methods_software_section.md")
  if (file.exists(sec)) unlink(sec)
}

# dbpool / TST：禁止用 legacy 整文件覆盖（会把 mice/jstable/TCF 注句冲回交付）
# 非 dbpool/TST 且仍有 legacy 时，仅在 std 缺失时已于上方 copy；此处不再 overwrite

# image_information README 不进白名单：随 prune 移走；先删幽灵 S1/S2 行可选
readme <- file.path(fig_dir, "image_information", "README.md")
if (file.exists(readme)) {
  # 留在 fig 内即可；prune 只动交付根一级
}

# 单库：剥掉 Table/Figure …-库名.（--databases 仅 1 个，或 config 判定单库）
if (exists("pub_strip_db_tags_from_delivery", mode = "function") &&
    exists("pub_config_is_single_db", mode = "function")) {
  dbs_n <- length(unique(dbs[nzchar(dbs)]))
  if (dbs_n == 1L || isTRUE(pub_config_is_single_db(config))) {
    tryCatch(
      {
        n_strip <- pub_strip_db_tags_from_delivery(dir, config = config, db_tags = dbs)
        if (requireNamespace("cli", quietly = TRUE)) {
          cli::cli_alert_info("单库交付去库名: moved/edited ~{n_strip}")
        }
      },
      error = function(e) {
        message("单库去库名跳过: ", conditionMessage(e))
      }
    )
  }
}

pub_prune_delivery_root(dir)
st <- if (dir.exists(fig_dir)) {
  pub_figure_formats_status(
    fig_dir,
    config = list(pub_figures = list(
      export_png = FALSE, export_tiff = FALSE,
      max_edge_in = 16, require_vector_pdf = TRUE
    ))
  )
} else {
  list(ok = NA)
}
cat(
  "FINALIZE_OK dir=", normalizePath(dir),
  " fig_ok=", isTRUE(st$ok),
  " methods=", file.exists(methods_path),
  " software=", file.exists(file.path(dir, "Methods_software_versions.txt")),
  "\n", sep = ""
)
