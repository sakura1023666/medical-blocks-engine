###############################################################################
#  incidence_pipeline_brief — 发病流水线步骤简要说明（txt）
#
#  每个指标跑完后，在 by_index/<ix>/ 下写 Pipeline_steps_brief.txt，
#  用中文简述：数据、暴露、协变量筛选路径、logistic 分支、RCS/亚组/中介等。
#  内容优先读实际产物（Model1/2、VIF、sig_vars、_batch_status），缺则写规则说明。
###############################################################################

.incidence_brief_read_lines <- function(path) {
  if (!file.exists(path)) return(character(0))
  x <- tryCatch(
    readLines(path, warn = FALSE, encoding = "UTF-8"),
    error = function(e) character(0)
  )
  trimws(x[nzchar(trimws(x)) & !startsWith(trimws(x), "#")])
}

.incidence_brief_find_file <- function(db_dir, patterns) {
  if (!dir.exists(db_dir)) return(NA_character_)
  for (pat in patterns) {
    hits <- list.files(db_dir, pattern = pat, recursive = TRUE, full.names = TRUE)
    if (length(hits)) return(hits[[1L]])
  }
  NA_character_
}

.incidence_brief_join <- function(x, empty = "（无/未写出）") {
  x <- unique(as.character(x))
  x <- x[nzchar(x)]
  if (!length(x)) return(empty)
  paste(x, collapse = ", ")
}

.incidence_brief_gate_b_source_label <- function(src) {
  src <- tolower(trimws(as.character(src %||% "")[1L]))
  if (identical(src, "vif_screen")) {
    return("单因素-VIF（vif_screen：两库单因素筛选后 VIF 初筛池的临床交集）")
  }
  if (identical(src, "vif_final")) {
    return("多因素-VIF（vif_final：两库多因素后 VIF 终筛池的临床交集）")
  }
  if (identical(src, "preset") || identical(src, "config")) {
    return("config 预设协变量（未走 VIF 闸门自动交集）")
  }
  if (!nzchar(src)) return("【证据不足】未能判定（gate_b 未记录来源）")
  paste0("其他来源: ", src)
}

#' 读取本指标 Gate B 最终协变量来源与统一 Model1/2
.incidence_brief_load_gate_b <- function(output_ix_dir, config = NULL, ix = NULL) {
  out <- list(
    source = NA_character_,
    source_label = NA_character_,
    config_mode = NA_character_,
    m1 = character(0),
    m2 = character(0),
    clinical = character(0),
    path = NA_character_
  )
  if (is.null(config)) return(out)

  dir_bn <- basename(normalizePath(output_ix_dir, winslash = "/", mustWork = FALSE))
  if (is.null(ix) || !nzchar(ix)) {
    ix <- sub("^【(success|failed)】", "", dir_bn)
    ix <- sub("^(success|failed)_?", "", ix)
  }

  root <- (config$project %||% list())$root %||%
    Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(as.character(root)[1L])) root <- getwd()

  # 优先从产物目录反推研究根（避免 config 里 output_base 误指向引擎根）
  ix_abs <- normalizePath(output_ix_dir, winslash = "/", mustWork = FALSE)
  by_index_dir <- dirname(ix_abs)
  study_root <- if (identical(basename(by_index_dir), "by_index")) {
    dirname(by_index_dir)
  } else {
    NA_character_
  }

  bc <- config$incidence_batch %||% list()
  out_base_cfg <- bc$output_base %||% (config$project %||% list())$output_dir
  ck_base_cfg <- bc$index_ck_base %||% {
    if (!is.null(out_base_cfg) && nzchar(as.character(out_base_cfg)[1L]))
      file.path(out_base_cfg, "checkpoints", "by_index")
    else NA_character_
  }

  gate_cands <- character(0)
  if (!is.na(study_root) && nzchar(study_root)) {
    gate_cands <- c(
      gate_cands,
      file.path(study_root, "checkpoints", "by_index", ix, "harmonization", "gate_b_covariates.rds")
    )
  }
  if (!is.na(ck_base_cfg) && nzchar(as.character(ck_base_cfg)[1L])) {
    gate_cands <- c(
      gate_cands,
      file.path(ck_base_cfg, ix, "harmonization", "gate_b_covariates.rds")
    )
  }
  gate_cands <- unique(gate_cands[nzchar(gate_cands)])
  gate_path <- gate_cands[file.exists(gate_cands)][1L]
  if (is.na(gate_path) || !nzchar(gate_path)) gate_path <- NA_character_
  out$path <- gate_path

  # 用实际找到的 gate_b 反推 ck_base，供 resolve 使用
  ck_base_eff <- if (!is.na(gate_path)) {
    # .../checkpoints/by_index/<ix>/harmonization/gate_b → by_index
    dirname(dirname(dirname(gate_path)))
  } else if (!is.na(study_root) && nzchar(study_root)) {
    file.path(study_root, "checkpoints", "by_index")
  } else {
    ck_base_cfg
  }

  cfg_ix <- config
  cfg_ix$dual_db <- cfg_ix$dual_db %||% list()
  if (!is.na(ck_base_eff) && nzchar(as.character(ck_base_eff)[1L])) {
    cfg_ix$dual_db$checkpoint_base <- file.path(ck_base_eff, ix)
    cfg_ix$dual_db$harmonization_dir <- file.path(ck_base_eff, ix, "harmonization")
    cfg_ix$incidence_batch <- cfg_ix$incidence_batch %||% list()
    cfg_ix$incidence_batch$index_ck_base <- ck_base_eff
    if (!is.na(study_root) && nzchar(study_root)) {
      cfg_ix$incidence_batch$output_base <- study_root
      cfg_ix$project <- cfg_ix$project %||% list()
      cfg_ix$project$output_dir <- study_root
    }
  }

  out$config_mode <- if (exists("dual_db_harmonization_covariate_source", mode = "function")) {
    dual_db_harmonization_covariate_source(cfg_ix)
  } else {
    as.character((cfg_ix$dual_db$harmonization %||% list())$covariate_source %||% "auto")[1L]
  }

  gate_b <- NULL
  if (!is.na(gate_path) && file.exists(gate_path)) {
    gate_b <- tryCatch(readRDS(gate_path), error = function(e) NULL)
  }
  if (!is.null(gate_b)) {
    out$m1 <- as.character(
      gate_b$harmonized_model1_nhanes %||% gate_b$harmonized_model1_mimic %||% character(0)
    )
    out$m2 <- as.character(
      gate_b$harmonized_model2_nhanes %||% gate_b$harmonized_model2_mimic %||% character(0)
    )
    out$clinical <- as.character(gate_b$common_model_factors %||% character(0))
    src0 <- gate_b$covariate_source_used
    if (!is.null(src0) && length(src0) && nzchar(as.character(src0)[1L]) &&
        !is.na(as.character(src0)[1L])) {
      out$source <- as.character(src0)[1L]
    }
  }

  # 旧缓存可能无 covariate_source_used：按 auto 规则重解析（不改盘）
  if (is.na(out$source) || !nzchar(as.character(out$source)[1L])) {
    if (exists("dual_db_resolve_gate_b_covariate_source", mode = "function")) {
      out$source <- tryCatch(
        dual_db_resolve_gate_b_covariate_source(root, cfg_ix),
        error = function(e) NA_character_
      )
    } else {
      out$source <- out$config_mode
    }
  }
  out$source_label <- .incidence_brief_gate_b_source_label(out$source)
  out
}

.incidence_brief_db_section <- function(db_dir, db_label, weighted = FALSE) {
  lines <- character(0)
  if (!dir.exists(db_dir)) {
    return(c(sprintf("【%s】目录不存在，跳过。", db_label), ""))
  }

  steps <- list.dirs(db_dir, full.names = FALSE, recursive = FALSE)
  steps <- steps[grepl("^step\\d+_", steps)]
  steps <- sort(steps)

  lines <- c(lines, sprintf("【%s】本库实际执行的 step 目录：", db_label))
  if (length(steps)) {
    lines <- c(lines, paste0("  - ", steps))
  } else {
    lines <- c(lines, "  （未发现 step* 目录）")
  }
  lines <- c(lines, "")

  # 协变量路径关键文件
  sig_path <- .incidence_brief_find_file(
    db_dir,
    if (weighted) c("step09_baseline_nhanes/sig_vars\\.txt$", "sig_vars\\.txt$")
    else c("step07_baseline_binary/sig_vars\\.txt$", "sig_vars\\.txt$")
  )
  vif_screen <- .incidence_brief_find_file(
    db_dir,
    if (weighted) c("VIF_screen_pass_weighted\\.txt$", "VIF_screen_pass\\.txt$")
    else c("VIF_screen_pass\\.txt$")
  )
  m1 <- .incidence_brief_find_file(db_dir, c("step1[35].*/Model1Factors\\.txt$", "Model1Factors\\.txt$"))
  m2 <- .incidence_brief_find_file(
    db_dir,
    if (weighted) c("step15_.*/Model2Factors\\.txt$", "Model2Factors\\.txt$")
    else c("step14_.*/Model2Factors\\.txt$", "Model2Factors\\.txt$")
  )
  # 优先 final VIF 目录下的 Model2
  m2_final <- .incidence_brief_find_file(
    db_dir,
    if (weighted) c("multicollinearity_nhanes_final.*/Model2Factors\\.txt$")
    else c("multicollinearity_final.*/Model2Factors\\.txt$")
  )
  if (!is.na(m2_final)) m2 <- m2_final

  final_cov <- .incidence_brief_find_file(
    db_dir, c("FinalCovariates_.*\\.txt$", "Tables/Summary/FinalCovariates")
  )

  lines <- c(
    lines,
    sprintf("【%s】协变量选择（按流水线顺序）", db_label),
    if (weighted) {
      c(
        "  1) 加权基线 Table1：病例/对照组间比较，显著变量记入 sig_vars。",
        "  2) 加权单因素 logistic：screening_cutoff 默认 p<0.1 进入候选。",
        "  3) VIF 初筛（screen）：剔除共线过高变量 → VIF_screen_pass。",
        "  4) 加权多因素：Model1≈人口学候选；Model2=VIF 通过后的临床+人口学集合。",
        "  5) VIF 终筛（final）+ multivariate_covariate_resolve：得到最终 Model1/Model2。",
        "  6) 双库时 Gate B（dual_db_covariate_harmonize）再对齐两库协变量。"
      )
    } else {
      c(
        "  1) 普通基线 Table1：组间比较 → sig_vars。",
        "  2) 单因素 logistic（GLM）：screening_cutoff 默认 p<0.1。",
        "  3) VIF 初筛 → VIF_screen_pass。",
        "  4) 多因素 GLM：写出 Model1 / Model2。",
        "  5) VIF 终筛 + covariate_resolve → 最终 Model1/Model2。",
        "  6) 双库时 Gate B 对齐协变量。"
      )
    },
    "",
    sprintf("  - 基线显著变量(sig_vars): %s",
            .incidence_brief_join(.incidence_brief_read_lines(sig_path))),
    sprintf("  - VIF 初筛通过(单因素后): %s",
            .incidence_brief_join(.incidence_brief_read_lines(vif_screen))),
    sprintf("  - 本库本地 Model1Factors（Gate B 对齐前）: %s",
            .incidence_brief_join(.incidence_brief_read_lines(m1))),
    sprintf("  - 本库本地 Model2Factors（Gate B 对齐前/或已被覆写）: %s",
            .incidence_brief_join(.incidence_brief_read_lines(m2))),
    "  - ★ 主分析最终名单见上文「三、协变量最终选择」（两库统一 Gate B）。",
    if (!is.na(final_cov)) {
      sprintf("  - FinalCovariates 摘要文件: %s", basename(final_cov))
    } else {
      "  - FinalCovariates 摘要文件: （未找到）"
    },
    "",
    sprintf("【%s】后续分析块（简述）", db_label),
    if (weighted) {
      c(
        "  - logistic 四分位/三分位/二分：Crude→Model1→Model2；按显著性门控升降级分支。",
        "  - 双库 logistic 方案对齐 + 主表 realign。",
        "  - RCS 剂量反应；再按 RCS 切点重跑分组 logistic。",
        "  - 加权亚组森林图；加权中介分析（实验室指标筛选）。",
        "  - 末尾附不加权 GLM 基线/logistic，作敏感性对照。"
      )
    } else {
      c(
        "  - simple_ROC 找截断；boxplot。",
        "  - logistic 四分位/三分位/二分（GLM）门控升降级。",
        "  - 双库方案对齐 + 主表 realign。",
        "  - RCS；RCS 切点分组 logistic；亚组；中介。"
      )
    },
    ""
  )
  lines
}

#' 为单个指标输出目录写 Pipeline_steps_brief.txt
#'
#' @param output_ix_dir by_index 下该指标目录（可为尚未重命名的 ix，或【success】ix）
#' @param config 研究 config list（可选；用于写规则阈值）
#' @param ix 指标名（可选；缺省从目录名推断）
#' @param overwrite 是否覆盖已有 brief
#' @return 写入路径（invisible）
incidence_write_pipeline_brief <- function(output_ix_dir,
                                           config = NULL,
                                           ix = NULL,
                                           overwrite = TRUE) {
  if (!dir.exists(output_ix_dir)) {
    warning("output_ix_dir 不存在: ", output_ix_dir)
    return(invisible(NA_character_))
  }
  out_path <- file.path(output_ix_dir, "Pipeline_steps_brief.txt")
  if (file.exists(out_path) && !isTRUE(overwrite)) {
    return(invisible(out_path))
  }

  dir_bn <- basename(normalizePath(output_ix_dir, winslash = "/", mustWork = FALSE))
  if (is.null(ix) || !nzchar(ix)) {
    ix <- sub("^【(success|failed)】", "", dir_bn)
    ix <- sub("^(success|failed)_?", "", ix)
  }

  st <- list()
  st_path <- file.path(output_ix_dir, "_batch_status.json")
  if (file.exists(st_path) && requireNamespace("jsonlite", quietly = TRUE)) {
    st <- tryCatch(jsonlite::fromJSON(st_path), error = function(e) list())
  }

  proj <- if (!is.null(config)) config$project %||% list() else list()
  bc   <- if (!is.null(config)) config$incidence_batch %||% list() else list()
  uni  <- if (!is.null(config)) config$univariate_nhanes %||% list() else list()
  vif  <- if (!is.null(config)) config$multicollinearity %||% list() else list()
  idx_formula <- NA_character_
  if (exists(".composite_index_defs", inherits = TRUE) ||
      exists("COMPOSITE_INDEX_DEFS", inherits = TRUE)) {
    # 尽量从 index block 公式旁注；此处用常见名兜底
  }

  disease <- st$disease %||% proj$disease %||% ""
  pmid    <- proj$literature_pmid %||% ""
  status  <- st$status %||% "unknown"

  gate_info <- .incidence_brief_load_gate_b(output_ix_dir, config = config, ix = ix)

  formula_note <- switch(
    as.character(ix),
    "TyG_WWI"  = "TyG_WWI = log(Glucose*Triglycerides/2) * (Waist_circumference/sqrt(Weight))",
    "TyG_ABSI" = "TyG_ABSI = log(Glucose*Triglycerides/2) * (WC / (BMI^(2/3)*Height^(1/2)))",
    "TyG"      = "TyG = log(Glucose*Triglycerides/2)",
    sprintf("暴露指标 = %s（具体公式见 Blocks/00_index/01block_index.R）", ix)
  )

  gate_section <- c(
    "════════════════════════════════════════════════════════════",
    "三、协变量最终选择（Gate B · 主分析 Table 2 实际使用）",
    "════════════════════════════════════════════════════════════",
    paste0("- config$dual_db$harmonization$covariate_source = ",
           gate_info$config_mode %||% "（未读到）",
           "（auto=先试多因素-VIF 交集，空则两边一起退回单因素-VIF；禁止混用）"),
    paste0("- ★ 本指标最终采用: ",
           gate_info$source_label %||% "【证据不足】"),
    paste0("- 代码标记: ",
           if (!is.na(gate_info$source) && nzchar(gate_info$source))
             gate_info$source else "（未记录）"),
    paste0("- 两库统一 Model1: ", .incidence_brief_join(gate_info$m1)),
    paste0("- 两库统一 Model2（Table 2 调整模型）: ",
           .incidence_brief_join(gate_info$m2)),
    paste0("- 临床交集（common_model_factors，不含纯人口学）: ",
           .incidence_brief_join(gate_info$clinical)),
    if (!is.na(gate_info$path)) {
      paste0("- Gate B 缓存: ", gate_info$path)
    } else {
      "- Gate B 缓存: （未找到 gate_b_covariates.rds；下列各库摘录可能仍为对齐前本地名单）"
    },
    "",
    "规则备忘（筛选阈值，非最终名单）：",
    paste0("  · 单因素进入多因素候选: screening_cutoff = ",
           uni$screening_cutoff %||% 0.1, "（通常 p<0.1）"),
    paste0("  · VIF 严格/宽松/硬删阈值: ",
           vif$vif_threshold_strict %||% 4, " / ",
           vif$vif_threshold_loose %||% 10, " / ",
           vif$vif_threshold_hard_drop %||% 50),
    "  · Model1: 优先人口学（Age/Gender/Race 等 demo_keywords）。",
    "  · Model2: Model1 + 上述来源池的临床交集；logistic 随机搜索可再精简。",
    "  · 指标组分变量及 ID/权重列默认排除出协变量池。",
    ""
  )

  hdr <- c(
    paste0("流水线步骤简要说明 — ", ix),
    paste0("生成时间: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    paste0("项目: ", disease,
           if (nzchar(as.character(pmid))) paste0(" (PMID ", pmid, ")") else ""),
    paste0("指标目录: ", normalizePath(output_ix_dir, winslash = "/", mustWork = FALSE)),
    paste0("运行状态: ", status,
           if (!is.null(st$db_mode)) paste0(" | db_mode=", st$db_mode) else "",
           if (!is.null(st$nhanes_branch)) paste0(" | NHANES分支=", st$nhanes_branch) else "",
           if (!is.null(st$mimic_branch)) paste0(" | CHARLS/副库分支=", st$mimic_branch) else ""),
    "",
    "════════════════════════════════════════════════════════════",
    "一、研究设定",
    "════════════════════════════════════════════════════════════",
    paste0("- 结局: Disease_Group（分析组=", proj$analysis_group %||% "1",
           "；参照组=", proj$reference_group %||% "0", "）"),
    paste0("- 暴露: ", formula_note),
    paste0("- 设计: NHANES 复杂抽样加权（svydesign + new_Weight）+ CHARLS 普通 GLM 双库"),
    paste0("- 样本量(过滤后): NHANES ",
           st$n_nhanes_before %||% "?", " → ", st$n_nhanes_after %||% "?",
           "；CHARLS ", st$n_mimic_before %||% "?", " → ", st$n_mimic_after %||% "?"),
    paste0("- 缺失插补: MICE method=",
           (if (!is.null(config)) config$imputation$method %||% "cart" else "cart"),
           "；列缺失阈值=",
           (if (!is.null(config)) config$imputation$missing_col_threshold %||% 0.4 else 0.4),
           "；指标极端值：不裁剪（pipeline 不挂 trim_index_extreme）"),
    "",
    "════════════════════════════════════════════════════════════",
    "二、共享层（每库只跑一次，checkpoint/_shared）",
    "════════════════════════════════════════════════════════════",
    "1. data_clean — 基础清洗、年龄/缺失阈值等。",
    "2. column_mapping — 列名标准化（如 PlateletCount→Platelet_Count）。",
    "3. dual_db_column_harmonize — Gate A：两库列名交集对齐。",
    "4. index — 批量计算复合指标；本指标仅保留当前暴露列进入后续分析。",
    "",
    gate_section,
    "════════════════════════════════════════════════════════════",
    "四、各库实际产物摘录（对齐前本地筛选轨迹）",
    "════════════════════════════════════════════════════════════",
    ""
  )

  nh_dir <- file.path(output_ix_dir, "NHANES")
  ch_dir <- file.path(output_ix_dir, "CHARLS")
  if (!dir.exists(ch_dir)) ch_dir <- file.path(output_ix_dir, "MIMIC")

  body <- c(
    .incidence_brief_db_section(nh_dir, "NHANES（加权）", weighted = TRUE),
    .incidence_brief_db_section(ch_dir, "CHARLS/副库（普通 GLM）", weighted = FALSE)
  )

  sens_dir <- file.path(output_ix_dir, "sensitivity")
  sens_lines <- character(0)
  if (dir.exists(sens_dir)) {
    scen <- list.dirs(sens_dir, full.names = FALSE, recursive = FALSE)
    scen <- scen[nzchar(scen)]
    sens_lines <- c(
      "════════════════════════════════════════════════════════════",
      "五、敏感性分析",
      "════════════════════════════════════════════════════════════",
      if (length(scen)) paste0("- 已跑场景: ", paste(scen, collapse = ", "))
      else "- sensitivity 目录存在但尚无子场景。",
      "- 规则通常为剔除高血压/糖尿病，或按 Age≥65 / Age<65 分层重跑主链路。",
      ""
    )
  } else {
    sens_lines <- c(
      "════════════════════════════════════════════════════════════",
      "五、敏感性分析",
      "════════════════════════════════════════════════════════════",
      "- 主分析成功后由 sensitivity_suite 自动触发（若 config 开启）。",
      "- 本目录尚未出现 sensitivity/ 子文件夹。",
      ""
    )
  }

  footer <- c(
    "════════════════════════════════════════════════════════════",
    "六、阅读产物时的建议顺序",
    "════════════════════════════════════════════════════════════",
    "1) Tables/ 或各 step*/Tables 中的 Table 1（基线）、Table 2（主 logistic）。",
    "2) 上文第三节 Gate B 最终来源（单因素-VIF / 多因素-VIF）与统一 Model1/2。",
    "3) Model1Factors.txt / Model2Factors.txt / FinalCovariates_*.txt（各库本地轨迹，可能已覆写）。",
    "4) VIF_check_*.csv（共线性诊断）。",
    "5) Figures：ROC/箱线图、RCS、亚组森林图、中介路径图。",
    "6) _batch_status.json / _index_summary.csv（本指标成败与分支）。",
    "",
    "（本文件由 incidence_write_pipeline_brief 自动生成，仅作步骤备忘，不替代正式表格。）"
  )

  txt <- c(hdr, body, sens_lines, footer)
  tryCatch(
    writeLines(txt, out_path, useBytes = FALSE),
    error = function(e) {
      # SMB 偶发编码问题：退回二进制写
      con <- file(out_path, open = "wb")
      on.exit(close(con), add = TRUE)
      writeBin(charToRaw(paste(txt, collapse = "\n")), con)
    }
  )
  if (requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_success("已写流水线说明: {.file {out_path}}")
  } else {
    message("已写流水线说明: ", out_path)
  }
  invisible(out_path)
}
