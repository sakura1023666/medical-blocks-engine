#!/usr/bin/env Rscript
###############################################################################
# run/pub/rebuild_lit_publication_tables.R
# 通用「文献 wide 版式发表表」重导出 CLI（任意双库预后 ML 课题复用）
#
# 用引擎 R/pub_reference_lit_tables.R 内核，从 assoc checkpoint 重算并落盘：
#   Table2 联合分组 Cox（Panel A 主库 / Panel B 外验库）
#   S4  单指标三分位 Cox
#   S5  判别力 AUC/DeLong
#   S6-S8 各 SOFA 层 PH（cox.zph）
#   S9  敏感性：排除基线 Glucose<阈值（双库 Panel）
#   S10 complete-case 联合分组 Cox
#   S11 分层五模型性能宽表重塑（train / internal / external）
#   S2  单因素 Cox、S3 GVIF（别名保护）
#
# 用法（任意课题一条命令）：
#   Rscript run/pub/rebuild_lit_publication_tables.R \
#     --config <study/config.R> --index <A+B> \
#     --index-a <A> --index-b <B> [--cutoff 4,10] \
#     [--primary MIMIC_IV] [--secondary eICU] [--glucose-threshold 70] \
#     [--out <Tables目录>] [--tables joint,s9,s10,s11,s4,s5,s2,s3]
#
# 默认写到 by_index/【success】<INDEX>/Tables（先落本地 tmp 再拷，避 0 字节）。
# 与课题临时脚本的区别：所有口径参数化，不写死病种/列名/步号。
###############################################################################
options(warn = 1)
`%||%` <- function(a, b) if (!is.null(a)) a else b

.args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NULL) {
  i <- match(flag, .args)
  if (is.na(i) || i == length(.args)) default else .args[[i + 1L]]
}
config_path <- get_arg("--config")
index_label <- get_arg("--index")
index_a     <- get_arg("--index-a")
index_b     <- get_arg("--index-b")
cutoff_raw  <- get_arg("--cutoff", "4,10")
primary     <- get_arg("--primary", "MIMIC_IV")
secondary   <- get_arg("--secondary", "eICU")
glucose_thr <- as.numeric(get_arg("--glucose-threshold", "70"))
out_override <- get_arg("--out")
tables_sel  <- strsplit(get_arg("--tables",
  "t1,joint,s4,s5,ph,s9,s10,s2,s3,s11"), ",")[[1L]]
do_fig_s1   <- !is.na(match("--fig-s1", .args))

if (is.null(config_path) || is.null(index_label)) {
  stop("需 --config 与 --index。可选 --index-a/--index-b/--cutoff/--glucose-threshold/--out/--tables",
       call. = FALSE)
}
config_path <- normalizePath(config_path, winslash = "/", mustWork = TRUE)
cutoff <- suppressWarnings(as.integer(strsplit(cutoff_raw, ",")[[1L]]))

engine <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(engine)) {
  sp <- normalizePath(dirname(sub("^--file=", "",
        grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), winslash = "/")
  engine <- normalizePath(file.path(sp, "..", ".."), winslash = "/")
}
Sys.setenv(MEDICAL_BLOCKS_ROOT = engine)
suppressWarnings(suppressMessages({
  source(file.path(engine, "R/utils.R"))
  source(file.path(engine, "R/ml_assoc_covariate_rule.R"))
  source(file.path(engine, "R/ml_stratified_ctx.R"))
  source(file.path(engine, "R/prognosis_reference_assoc.R"))
  source(file.path(engine, "R/ml_reference_assoc_figures.R"))
  source(file.path(engine, "R/prognosis_landmark_ph.R"))
  source(file.path(engine, "R/pub_reference_lit_tables.R"))
}))
suppressPackageStartupMessages(library(survival))

# ---- config ----
sys.source(config_path, envir = .GlobalEnv)
cfg <- get("config", envir = .GlobalEnv)
pipeline_apply_pub_digits(cfg)

# ---- 端点名：优先 --index-a/-b，否则从 study.index_combos / ml_batch 反查 ----
if (is.null(index_a) || is.null(index_b)) {
  combos <- cfg$study.index_combos %||% cfg$ml_batch$index_combos %||%
    (if (!is.null(cfg$index_combos)) cfg$index_combos else NULL)
  hit <- NULL
  if (!is.null(combos)) {
    for (cb in combos) {
      if (length(cb) == 2L && paste0(cb[1], "+", cb[2]) == index_label) { hit <- cb; break }
    }
  }
  if (is.null(hit)) {
    parts <- strsplit(index_label, "+", fixed = TRUE)[[1L]]
    if (length(parts) >= 2L) hit <- parts[1:2]
  }
  if (is.null(hit)) stop("无法从 config 反查端点，请显式 --index-a/--index-b", call. = FALSE)
  index_a <- hit[1]; index_b <- hit[2]
}
.ref_assoc_set_indices(c(index_a, index_b))
message("indices: ", index_a, " / ", index_b, " | cutoff=", paste(cutoff, collapse = ","))

# ---- 定位课题根 / 结果目录 / checkpoints ----
study_root <- cfg$study_root %||%
  (if (!is.null(cfg$.batch_project_root)) cfg$.batch_project_root else NULL)
if (is.null(study_root)) {
  # config.R 里 .study_config_file 的目录的上一级（studies/<id>/config.R）
  cfg_dir <- dirname(config_path)
  study_root <- if (basename(cfg_dir) %in% c("config", "configs")) dirname(cfg_dir) else cfg_dir
}
index_root <- file.path(study_root, "by_index", paste0("【success】", index_label))
if (!dir.exists(index_root)) index_root <- file.path(study_root, "by_index", index_label)
ck_root <- file.path(study_root, "checkpoints", "by_index", index_label)
out_tables <- out_override %||% file.path(index_root, "Tables")
pub_tbl <- file.path(index_root, "publication_literature_final", "Tables")
local <- file.path(engine, "tmp", paste0("lit_pub_", gsub("[^A-Za-z0-9]", "_", index_label)))
dir.create(local, recursive = TRUE, showWarnings = FALSE)
dir.create(out_tables, recursive = TRUE, showWarnings = FALSE)

find_assoc_ckpt <- function(db) {
  d <- file.path(ck_root, db)
  if (!dir.exists(d)) return(NULL)
  hits <- list.files(d, pattern = "ml_assoc_bundle\\.rds$", full.names = TRUE)
  if (!length(hits)) return(NULL)
  steps <- suppressWarnings(as.integer(sub(".*(step[0-9]+).*", "\\1", hits)))
  hits[order(steps, decreasing = TRUE)][1]
}
fmi <- find_assoc_ckpt(primary); fei <- find_assoc_ckpt(secondary)
if (is.null(fmi)) stop("缺主库 ml_assoc_bundle.rds：", file.path(ck_root, primary), call. = FALSE)
mi <- pub_lit_inject_assoc(readRDS(fmi)$ctx, cfg)
message(mi$results$assoc_covariate_note)
dat <- pub_lit_prep(mi$data$imputed, cutoff = cutoff)
train <- pub_lit_prep(as.data.frame(mi$data$train %||% mi$data$imputed), cutoff = cutoff)
models <- .ref_assoc_models(mi, dat, c(index_a, index_b), "SOFA_layer")
cuts <- pub_lit_joint_cuts(train, index_a, index_b)
message("frozen upper-tertile cuts: ", index_a, "=", cuts$a, " ", index_b, "=", cuts$b)

# 外验库（同口径 M1/M2/M3）
dat_sec <- NULL
if (!is.null(fei)) {
  ei <- readRDS(fei)$ctx
  ei <- pub_lit_share_assoc_models(mi, ei)
  dat_sec <- pub_lit_prep(ei$data$imputed, cutoff = cutoff)
}

# ---- 落盘工具：本地写 + 拷 G ----
copy_one <- function(src, dest) {
  if (!file.exists(src)) return(invisible(FALSE))
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(dest, ".__tmp__")
  if (file.exists(tmp)) file.remove(tmp)
  ok <- tryCatch({ file.copy(src, tmp, overwrite = TRUE)
    if (file.exists(dest)) file.remove(dest); file.rename(tmp, dest) },
    error = function(e) { message("copy fail ", conditionMessage(e)); FALSE })
  message(if (isTRUE(ok)) "OK " else "FAIL ", basename(dest),
          " size=", if (file.exists(dest)) file.info(dest)$size else NA)
  invisible(ok)
}
DB_SHORT_PRI <- gsub("_", "-", primary)          # MIMIC_IV -> MIMIC-IV
DB_TAG_PRI   <- gsub("-", " ", DB_SHORT_PRI)      # for filenames "MIMIC IV"
lay_labels <- names(.ref_assoc_layer_masks(dat, cutoff))
strata_pub <- c("Overall", "SOFA 0\u20134", "SOFA 5\u201310", "SOFA \u226511")
PH_LAYERS  <- stats::setNames(strata_pub[-1], c("S6", "S7", "S8"))

# ---- 文献版式标题/脚注：可被 config$lit_tables 覆盖（本课题定稿措辞的单一来源）----
.lit <- cfg$lit_tables %||% list()
.toks <- list(
  IA = index_a, IB = index_b, ILAB = paste0(index_a, "+", index_b),
  PRI = DB_SHORT_PRI, SEC = secondary,
  OUT = cfg$pub_outcome_label %||% "28-day all-cause mortality",
  GTH = format(glucose_thr, scientific = FALSE)
)
.lit_sub <- function(s) {
  s <- as.character(s)
  for (k in names(.toks)) s <- gsub(paste0("{", k, "}"), .toks[[k]], s, fixed = TRUE)
  s
}
# title(key, default) / foot(key, default) —— 优先 config$lit_tables$<key>$title|footnotes
.lit_title <- function(key, default)
  .lit_sub(.lit[[key]]$title %||% default)
.lit_foot <- function(key, default)
  .lit_sub(.lit[[key]]$footnotes %||% default)

FOOT_COMMON <- .lit_foot("common", c(
  "Model 1: unadjusted; Model 2: age and sex; Model 3: clinical\u2229UV\u2229VIF covariates.",
  "Joint groups from {PRI} train frozen upper-tertile cuts; P for trend ordinal score.",
  "Strata: Overall and SOFA layers. Outcome: {OUT} only."))

# ==========================================================================
# Table1 文献版式（分库：Survivor/Non-survivor + Exposures 末节）——就地重排
# ==========================================================================
if ("t1" %in% tables_sel) {
  for (db_tag in list(c(DB_TAG_PRI, DB_SHORT_PRI), c(secondary, secondary))) {
    src_name <- paste0("Table 1-", db_tag[1],
      ". Baseline characteristics by 28-day survival.xlsx")
    src <- file.path(out_tables, src_name)
    if (!file.exists(src)) {
      # 兜底：任意 Table 1-<db> …xlsx（流水线原始命名如 "of AKI"；
      # pub_lit_style_table1 会把 No AKI/AKI 列头改写成 Survivor/Non-survivor）
      alt <- list.files(out_tables,
        pattern = paste0("^Table 1-", gsub(" ", ".", db_tag[1], fixed = TRUE),
                         ".*\\.xlsx$"),
        full.names = TRUE)
      alt <- setdiff(alt, file.path(out_tables, src_name))
      if (!length(alt)) { message("t1 缺分库表：", src_name); next }
      src <- alt[1]
      message("t1 使用源文件：", basename(src))
    }
    fn_styled <- file.path(local, src_name)
    pub_lit_style_table1(
      src, fn_styled, index_a, index_b,
      title = paste0("Table 1. Baseline characteristics by 28-day survival (",
                     db_tag[2], ")."),
      footnotes = .lit_foot("table1", c(
        "Continuous variables are presented as mean (SD) or median (IQR) depending on distribution; categorical as n (%).",
        "Comparisons between Survivor and Non-survivor used the Wilcoxon rank-sum or Pearson chi-squared test.",
        "Outcome: 28-day all-cause mortality (Survivor / Non-survivor).",
        paste0("Exposures: ", index_a, " and ", index_b, "."))))
    copy_one(fn_styled, file.path(out_tables, basename(fn_styled)))
    # 若用了旧命名源（如 "of AKI"），改名后删除旧文件
    if (basename(src) != basename(fn_styled)) {
      file.remove(src); message("removed legacy ", basename(src))
    }
    # 删双库合并表（定稿只留分库）
    combo <- file.path(out_tables,
      paste0("Table 1. Baseline characteristics by 28-day survival (",
             DB_SHORT_PRI, ", ", secondary, ").xlsx"))
    if (file.exists(combo)) { file.remove(combo); message("removed ", basename(combo)) }
  }
}

# ==========================================================================
# joint Table2（Panel A 主库 / Panel B 外验库；与 S9/S10 同布局）
# ==========================================================================
if ("joint" %in% tables_sel) {
  jt <- pub_lit_table_joint(dat, index_a, index_b, cuts$a, cuts$b, models,
                            cutoff, "28-day mortality")
  if (!is.null(dat_sec)) {
    jt_s <- pub_lit_table_joint(dat_sec, index_a, index_b, cuts$a, cuts$b, models,
                                cutoff, "28-day mortality")
    drop_hdr <- function(x) if (identical(x$Variables[[1]], "28-day mortality")) x[-1L, , drop = FALSE] else x
    blank_hdr <- function(x, lab) { z <- x[1, , drop = FALSE]; z[] <- ""; z$Variables <- lab; z }
    combo <- rbind(blank_hdr(jt, paste0("Panel A: ", DB_SHORT_PRI)), drop_hdr(jt),
                   blank_hdr(jt, paste0("Panel B: ", secondary)), drop_hdr(jt_s))
    rownames(combo) <- NULL
    jt <- combo
  }
  fn <- file.path(local, paste0("Table 2. Joint association of ", index_a, " and ",
              index_b, " with 28-day mortality (", DB_SHORT_PRI, ", ", secondary, ").xlsx"))
  sci_xlsx_single_header_booktabs(
    fn,
    title = .lit_title("table2", paste0("Table 2. The association of the combination of ",
      index_a, " and ", index_b, " with 28-day all-cause mortality (",
      DB_SHORT_PRI, ", ", secondary, ").")),
    df_body = jt, sheet = "Table 2", footnotes = .lit_foot("table2", FOOT_COMMON))
  copy_one(fn, file.path(out_tables, basename(fn)))
}

# ==========================================================================
# S9 glucose-excluded joint (dual DB panel)  |  S10 complete-case joint
# ==========================================================================
if ("s9" %in% tables_sel) {
  g9 <- pub_lit_exclude_glucose(dat, threshold = glucose_thr)
  b9 <- pub_lit_table_joint(g9, index_a, index_b, cuts$a, cuts$b, models,
                            cutoff, "28-day mortality")
  if (!is.null(dat_sec)) {
    b9s <- pub_lit_table_joint(pub_lit_exclude_glucose(dat_sec, threshold = glucose_thr),
      index_a, index_b, cuts$a, cuts$b, models, cutoff, "28-day mortality")
    drop_hdr <- function(x) if (identical(x$Variables[[1]], "28-day mortality")) x[-1L, , drop = FALSE] else x
    blank_hdr <- function(x, lab) { z <- x[1, , drop = FALSE]; z[] <- ""; z$Variables <- lab; z }
    b9 <- rbind(blank_hdr(b9, paste0("Panel A: ", DB_SHORT_PRI)), drop_hdr(b9),
                blank_hdr(b9, paste0("Panel B: ", secondary)), drop_hdr(b9s))
    rownames(b9) <- NULL
  }
  fn <- file.path(local, paste0("Table S9. Joint association of ", index_a, " and ",
              index_b, " after excluding baseline glucose <", format(glucose_thr, scientific = FALSE),
              " (", DB_SHORT_PRI, ", ", secondary, ").xlsx"))
  sci_xlsx_single_header_booktabs(fn,
    title = .lit_title("s9", paste0("Table S9. The association of the combination of ",
      index_a, " and ", index_b, " with 28-day all-cause mortality after excluding ",
      "individuals with baseline glucose <", format(glucose_thr, scientific = FALSE),
      " mg/dL (", DB_SHORT_PRI, " and ", secondary, ").")),
    df_body = b9, sheet = "Table S9",
    footnotes = .lit_foot("s9", c(
      paste0("Project-specific sensitivity: exclude baseline Glucose <",
             format(glucose_thr, scientific = FALSE), " mg/dL; missing retained."),
      paste0("Panel A ", DB_SHORT_PRI, "; Panel B ", secondary,
             ". Layout matches main Table 2."), FOOT_COMMON)))
  copy_one(fn, file.path(out_tables, basename(fn)))
}
if ("s10" %in% tables_sel) {
  cc <- pub_lit_complete_case(dat, unique(c(index_a, index_b, models$Model3, ".__tm", ".__ev")))
  b10 <- pub_lit_table_joint(cc, index_a, index_b, cuts$a, cuts$b, models,
                             cutoff, "28-day mortality")
  fn <- file.path(local, paste0("Table S10-", DB_TAG_PRI, ". Joint association of ",
              index_a, " and ", index_b, " complete-case analysis.xlsx"))
  sci_xlsx_single_header_booktabs(fn,
    title = .lit_title("s10", paste0("Table S10. The association of the combination of ",
      index_a, " and ", index_b, " with 28-day all-cause mortality after excluding ",
      "individuals with any missing value among analysis covariates (", DB_SHORT_PRI, ").")),
    df_body = b10, sheet = "Table S10",
    footnotes = .lit_foot("s10", c(
      paste0("Complete-case on ", index_a, ", ", index_b,
             ", Model 3 covariates, time and event."),
      "Model 1–3 and joint-group definitions as in Table 2 / Table S9.",
      "Strata: Overall and SOFA layers. {OUT} only.")))
  copy_one(fn, file.path(out_tables, basename(fn)))
}

# ==========================================================================
# S4 index tertile
# ==========================================================================
if ("s4" %in% tables_sel) {
  s4 <- pub_lit_table_index_tertile(dat, c(index_a, index_b), models, cutoff,
                                    "28-day mortality")
  fn <- file.path(local, paste0("Table S4-", DB_TAG_PRI, ". The association of ",
              index_a, " and ", index_b, " with 28-day mortality.xlsx"))
  sci_xlsx_single_header_booktabs(fn,
    title = .lit_title("s4", paste0("Table S4. The association of the ", index_a, " and ",
      index_b, " with 28-day all-cause mortality (", DB_SHORT_PRI, ").")),
    df_body = s4, sheet = "Table S4",
    footnotes = .lit_foot("s4", c(FOOT_COMMON[1],
      "T1\u2013T3: tertiles (type-7) within each stratum; P for trend treats tertile as ordinal 1\u20133.",
      "Strata: Overall and SOFA layers.",
      paste0("Outcome: {OUT} only."),
      paste0(DB_SHORT_PRI, " analysis set."))))
  copy_one(fn, file.path(out_tables, basename(fn)))
}

# ==========================================================================
# S5 discrimination
# ==========================================================================
if ("s5" %in% tables_sel) {
  # 默认对照评分：排除分层键 SOFA（铁律：分层键不得作预测因子）
  score_cols <- (cfg$pub_score_columns %||%
    intersect(c("GCS", "APSIII", "SAPSII", "OASIS", "APSII"), names(dat)))
  preds <- list()
  preds[[paste0(index_a, "+", index_b)]] <- function(d) {
    a <- as.numeric(d[[index_a]]); b <- as.numeric(d[[index_b]])
    as.numeric(scale(a)) + as.numeric(scale(b))
  }
  preds[[index_a]] <- function(d) as.numeric(d[[index_a]])
  preds[[index_b]] <- function(d) as.numeric(d[[index_b]])
  for (sc in score_cols) {
    # force() at outer-call time — else lazy arg promise re-reads loop var `sc`
    # after the loop, so every closure would return the last score column.
    preds[[sc]] <- (function(scf) { force(scf); function(d) as.numeric(d[[scf]]) })(sc)
  }
  lower <- cfg$pub_lower_risk_scores %||% "GCS"
  ref <- paste0(index_a, "+", index_b)
  s5 <- pub_lit_table_discrimination(dat, preds, ref, cutoff, lower_risk = lower)
  fn <- file.path(local, paste0("Table S5-", DB_TAG_PRI,
              ". Discrimination of each predictive model for outcomes.xlsx"))
  sci_xlsx_single_header_booktabs(fn,
    title = .lit_title("s5", paste0("Table S5. Discrimination of each predictive model ",
      "for outcomes (", DB_SHORT_PRI, ", 28-day mortality).")),
    df_body = s5, sheet = "Table S5",
    footnotes = .lit_foot("s5", c(
      "AUC (95% CI) from pROC; Sensitivity/Specificity at Youden threshold.",
      paste0("P: DeLong test versus {ILAB} (reference)."),
      paste0("Comparators: ", paste(names(preds), collapse = ", "), "."),
      paste0("Strata: Overall and SOFA layers. ", DB_SHORT_PRI, " only; 28-day mortality only."))))
  copy_one(fn, file.path(out_tables, basename(fn)))
}

# ==========================================================================
# S6-S8 PH per layer
# ==========================================================================
if ("ph" %in% tables_sel) {
  alias <- list(Heart_Failure = "Heart Failure",
                Ventilation = "Mechanical ventilation")
  for (i in seq_along(PH_LAYERS)) {
    tag <- names(PH_LAYERS)[i]; ly <- unname(PH_LAYERS[i])
    ph <- tryCatch(pub_lit_table_ph_layer(dat, index_a, index_b, models, ly, cutoff, alias),
                   error = function(e) { message("PH ", ly, " fail: ", conditionMessage(e)); NULL })
    if (is.null(ph)) next
    fn <- file.path(local, paste0("Table ", tag, "-", DB_TAG_PRI,
                  ". Results of the proportional hazards test (", ly, ").xlsx"))
    ph_key <- tolower(tag)  # s6/s7/s8
    sci_xlsx_single_header_booktabs(fn,
      title = .lit_title(ph_key, paste0("Table ", tag, ". Results of the proportional ",
        "hazards test (Cox model) in the ", ly, " population (", DB_SHORT_PRI, ").")),
      df_body = ph, sheet = tag,
      footnotes = .lit_foot(ph_key, c(
        paste0("Schoenfeld residual test (cox.zph) for Model 3 covariates plus ",
               index_a, " and ", index_b, "."),
        paste0("Stratum: ", ly, ". ", DB_SHORT_PRI, "; 28-day mortality."))))
    copy_one(fn, file.path(out_tables, basename(fn)))
  }
}

# ==========================================================================
# S2 univariate Cox + S3 GVIF (optional; need Table1 spec)
# ==========================================================================
if ("s2" %in% tables_sel && !is.null(cfg$pub_table1_spec)) {
  s2 <- pub_lit_table_uni_cox(dat, cfg$pub_table1_spec)
  fn <- file.path(local, paste0("Table S2-", DB_TAG_PRI, ". Univariate Cox regression results.xlsx"))
  sci_xlsx_single_header_booktabs(fn,
    title = .lit_title("s2", paste0("Table S2. Univariate Cox regression results (", DB_SHORT_PRI, ").")),
    df_body = s2, sheet = "Table S2",
    footnotes = .lit_foot("s2", c(
      "Number(%) for continuous variables: mean (SD); for categorical variables: n (%).",
      "Hazard ratios from univariate Cox models for 28-day all-cause mortality.",
      paste0("Variable order aligned with Table 1 (", DB_SHORT_PRI, ")."),
      paste0(DB_SHORT_PRI, " analysis set only."))))
  copy_one(fn, file.path(out_tables, basename(fn)))
}
if ("s3" %in% tables_sel) {
  vv <- mi$results$vif_screen_pass %||% setdiff(names(train), c("fustatus", "futime"))
  lab_map <- tryCatch({
    if (is.null(cfg$pub_table1_spec)) NULL else {
      resolve <- function(cands, nm) {
        cands <- as.character(cands); hit <- cands[cands %in% nm][1]
        if (!is.na(hit)) return(hit)
        for (c in cands) { h <- nm[tolower(gsub("[^A-Za-z0-9]", "", nm)) ==
                                    tolower(gsub("[^A-Za-z0-9]", "", c))]
                          if (length(h)) return(h[1]) }
        NA_character_
      }
      cols <- vapply(cfg$pub_table1_spec,
                     function(s) resolve(s$col, names(train)) %||% NA_character_, "")
      labs <- vapply(cfg$pub_table1_spec, function(s) s$label, "")
      keep <- !is.na(cols)
      stats::setNames(labs[keep], cols[keep])
    }
  }, error = function(e) NULL)
  s3 <- tryCatch(pub_lit_table_vif(train, vv,
              alias_groups = list(c("Diabetes", "T1DM", "T2DM")), label_map = lab_map),
              error = function(e) { message("S3 fail: ", conditionMessage(e)); NULL })
  if (!is.null(s3)) {
    fn <- file.path(local, paste0("Table S3-", DB_TAG_PRI,
        ". Variance inflation factor between variables.xlsx"))
    sci_xlsx_single_header_booktabs(fn,
      title = .lit_title("s3", paste0("Table S3. Variance inflation factor between variables (",
                   DB_SHORT_PRI, " training set).")),
      df_body = s3, sheet = "Table S3",
      footnotes = .lit_foot("s3", c(
        paste0("GVIF, Df and GVIF^(1/(2*Df)) from car::vif on the ", DB_SHORT_PRI,
               " training set."),
        "Collinear sub-levels dropped (e.g. Diabetes retained; T1DM/T2DM removed).",
        paste0("Variable order aligned with Table 1 where applicable. ",
               DB_SHORT_PRI, " only."))))
    copy_one(fn, file.path(out_tables, basename(fn)))
  }
}

# ==========================================================================
# S11 stratified five-model performance reshape
# ==========================================================================
if ("s11" %in% tables_sel) {
  s11_src <- NULL
  cand <- file.path(pub_tbl, "Table S11. Stratified five-model machine-learning performance.xlsx")
  if (file.exists(cand)) s11_src <- cand else {
    g <- list.files(pub_tbl, pattern = "Stratified five-model", full.names = TRUE)
    if (length(g)) s11_src <- g[1]
  }
  if (is.null(s11_src)) {
    message("S11: 未找到分层五模型性能源表（跳过；先跑 build_*_replication 生成）")
  } else {
    raw <- openxlsx::read.xlsx(s11_src, startRow = 2)
    s11 <- pub_lit_reshape_ml_perf(raw,
      strata = strata_pub,
      blocks = list(
        list(db = DB_SHORT_PRI, ds = "train", lab = paste0(DB_SHORT_PRI, " (training)")),
        list(db = DB_SHORT_PRI, ds = "internal validation", lab = paste0(DB_SHORT_PRI, " (internal validation)")),
        list(db = tolower(secondary), ds = "external validation", lab = paste0(secondary, " (external validation)"))
      ),
      model_map = c(logistic = "LR", dt = "DT", rf = "RF", xgboost = "XGBoost", lightgbm = "LGB"),
      metric_map = c(`roc auc` = "AUC", sens = "Sensitivity", spec = "Specificity",
                     accuracy = "Accuracy", `f meas` = "F1"))
    fn <- file.path(local, paste0("Table S11. Performance comparison of each ML model in predicting 28-day mortality (",
                DB_SHORT_PRI, ", ", secondary, ").xlsx"))
    sci_xlsx_single_header_booktabs(fn,
      title = .lit_title("s11", paste0("Table S11. The performance comparison of each ML ",
        "model in predicting 28-day mortality (", DB_SHORT_PRI, " training, ",
        DB_SHORT_PRI, " internal validation, and ", secondary, " external validation).")),
      df_body = s11, sheet = "Table S11",
      footnotes = .lit_foot("s11", c(
        paste0("Three sets per SOFA stratum, aligned with Figures: ", DB_SHORT_PRI,
               " training; ", DB_SHORT_PRI, " internal validation; ", secondary,
               " external validation."),
        "Metrics: AUC, Sensitivity, Specificity, Accuracy, F1. Models: LR, DT, RF, XGBoost, LGB.",
        paste0("{SEC} scored with frozen {PRI}-trained models (no refit)."),
        "Outcome: 28-day mortality only.")))
    copy_one(fn, file.path(out_tables, basename(fn)))
  }
}

# ==========================================================================
# 可选：Figure S1 原文样式 PH β(t) 趋势（--fig-s1）
# ==========================================================================
if (do_fig_s1) {
  if (!exists("pub_figure_ensure_formats", mode = "function"))
    suppressWarnings(suppressMessages(
      source(file.path(engine, "R/pub_figure_export.R"))))
  fig_root <- file.path(index_root, "publication_literature_final", "Figures")
  if (!dir.exists(fig_root)) fig_root <- file.path(index_root, "Figures")
  stem <- "Figure S1. Time-varying PH coefficient trends by SOFA strata"
  out_pdf <- file.path(local, paste0(stem, ".pdf"))
  ei_ctx <- if (!is.null(fei)) pub_lit_share_assoc_models(mi, readRDS(fei)$ctx) else NULL
  r <- pub_lit_fig_ph_beta_trends_original(
    mi, ei_ctx, index_a, index_b, out_pdf = out_pdf,
    train = mi$data$train, cutoff = cutoff)
  dir.create(file.path(fig_root, "pdf"), recursive = TRUE, showWarnings = FALSE)
  purge <- get("pub_figure_purge_format_subdirs", mode = "function")
  purge(fig_root, keep_md = FALSE, only_stems = stem)
  file.copy(out_pdf, file.path(fig_root, paste0(stem, ".pdf")), overwrite = TRUE)
  file.copy(out_pdf, file.path(fig_root, "pdf", paste0(stem, ".pdf")),
            overwrite = TRUE)
  assets <- file.path(dirname(fig_root), "_assets")
  dir.create(assets, recursive = TRUE, showWarnings = FALSE)
  file.copy(r$resid_csv, file.path(assets, "FigureS1_schoenfeld_points.csv"),
            overwrite = TRUE)
  file.copy(r$summary_csv, file.path(assets, "FigureS1_ph_summary.csv"),
            overwrite = TRUE)
  fmt <- function(p) if (is.finite(p)) format.pval(p, digits = 3, eps = 1e-3) else "NE"
  meta <- list(
    exposure = paste0(index_a, "+", index_b, " joint Group (tertile score)"),
    outcome = cfg$pub_outcome_label %||% "28 天全因死亡",
    grouping = "Overall（双库 A/B；分层 PH 见 Table S6-S8）",
    databases = unique(c(DB_SHORT_PRI, secondary)), combined = TRUE,
    figure_body_lines = c(
      "图面说明：对齐原文 Fig.S1（survival::plot.cox.zph）。A=主库，B=外验库。空心圆=标准化 Schoenfeld 残差；实线=样条平滑 β(t)（df=4）；虚线=±2SE；粉虚线=Beta(t)=0。",
      "X 轴为 cox.zph 默认 KM 时间变换刻度；Y 轴 Beta(t) for Group。",
      sprintf("图上标注：%s Schoenfeld P(Group)=%s (n=%d, events=%d)；%s P(Group)=%s (n=%d, events=%d)。",
              DB_SHORT_PRI, fmt(r$mimic$p_group), r$mimic$n, r$mimic$events,
              secondary, fmt(if (!is.null(r$eicu)) r$eicu$p_group else NA),
              if (!is.null(r$eicu)) r$eicu$n else NA,
              if (!is.null(r$eicu)) r$eicu$events else NA)
    ))
  res <- pub_figure_ensure_formats(fig_root, meta = meta, config = cfg, purge = FALSE)
  message("Fig S1: ", isTRUE(res$ok), " -> ", fig_root)
}

message("rebuild_lit_publication_tables DONE -> ", out_tables)
