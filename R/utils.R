###############################################################################
#  utils.R — 底层工具函数
#  所有 Block 模块共用的辅助函数，在 main.R 中统一 source
###############################################################################

# ── 空值回退运算符 ────────────────────────────────────────────────────────────
`%||%` <- function(a, b) if (!is.null(a)) a else b

# AI 临床 batch：worker 输出目录与 shared 层 cases 路径不一致时的回退解析
ai_clinical_cases_path <- function(ctx) {
  root <- ctx$config$project$root %||% getwd()
  candidates <- character(0)
  out <- ctx$config$project$output_dir %||% "Output"
  candidates <- c(candidates, file.path(out, "Tables", "AI_Cases", "cases_prepared.csv"))
  sb <- (ctx$config$study_batch %||% list())$output_base
  if (!is.null(sb) && nzchar(sb))
    candidates <- c(candidates, file.path(sb, "_shared", "Tables", "AI_Cases", "cases_prepared.csv"))
  bl <- ctx$config$ai_clinical %||% list()
  raw <- bl$cases_path %||% "Data/smoke/D01_ai_clinical_cases.csv"
  if (!is_absolute_path(raw)) raw <- file.path(root, raw)
  candidates <- c(candidates, raw)
  for (p in candidates) if (file.exists(p)) return(normalizePath(p, winslash = "/"))
  normalizePath(candidates[1L], winslash = "/")
}

# ctx$results 含 ml_models_models_dir 时，$ml_models 会部分匹配到该字符路径；须用 [[
ensure_ctx_results_list <- function(ctx, key) {
  val <- ctx$results[[key]]
  if (is.null(val) || !is.list(val)) {
    ctx$results[[key]] <- list()
  }
  ctx
}

# 各 ml_* 子块各自写入 Models/；按 tag 解析 evalresult_<tag>.RData 所在目录
resolve_ml_models_dir_for_tag <- function(ctx, tag) {
  tag <- as.character(tag)[1L]
  .remap_success_index_path <- function(p) {
    p <- as.character(p %||% "")[1L]
    if (!nzchar(p)) return("")
    if (dir.exists(p) || file.exists(p)) return(p)
    ## by_index/<IX>/… → by_index/【success】<IX>/…（finalize 改名后 ck 内绝对路径会失效）
    p2 <- sub(
      "/by_index/([^/【]+)/",
      "/by_index/\u3010success\u3011\\1/",
      p,
      perl = TRUE
    )
    if (!identical(p2, p) && (dir.exists(p2) || file.exists(p2))) return(p2)
    p3 <- sub(
      "/by_index/\u3010success\u3011([^/]+)/",
      "/by_index/\\1/",
      p,
      perl = TRUE
    )
    if (!identical(p3, p) && (dir.exists(p3) || file.exists(p3))) return(p3)
    p
  }
  dirs <- character(0)
  stored <- as.character(ctx$results[["ml_models_models_dir"]] %||% "")[1L]
  if (nzchar(stored)) dirs <- c(dirs, .remap_success_index_path(stored))
  bd <- ctx$log$block_output_dirs[[paste0("ml_", tag)]] %||% ""
  if (nzchar(bd)) dirs <- c(dirs, file.path(.remap_success_index_path(bd), "Models"))
  bundle <- ctx$log$block_output_dirs[["ml_models_bundle"]] %||% ""
  if (nzchar(bundle)) dirs <- c(dirs, file.path(.remap_success_index_path(bundle), "Models"))
  out_dir <- as.character(ctx$output_dir %||% "")[1L]
  if (nzchar(out_dir) && dir.exists(out_dir) && nzchar(tag)) {
    hits <- list.files(
      out_dir,
      pattern = paste0("^step[0-9]+_ml_", tag, "$"),
      full.names = TRUE
    )
    if (length(hits)) dirs <- c(dirs, file.path(hits, "Models"))
    hit2 <- file.path(out_dir, paste0("ml_", tag), "Models")
    if (dir.exists(hit2)) dirs <- c(dirs, hit2)
  }
  dirs <- unique(dirs[nzchar(dirs)])
  for (d in dirs) {
    d <- .remap_success_index_path(d)
    path <- file.path(d, paste0("evalresult_", tag, ".RData"))
    if (file.exists(path)) return(d)
  }
  if (length(dirs)) {
    d0 <- .remap_success_index_path(dirs[1L])
    if (dir.exists(d0)) return(d0)
  }
  file.path(ctx$output_dir, "Models")
}

# 指标极端值裁剪：有效样本 > large_n 时前后各裁 large_trim，否则用 base_trim
trim_index_quantile_for_n <- function(n, base_trim = 0.01, large_n = 10000L,
                                      large_trim = 0.05) {
  n <- as.integer(n)[1L]
  if (!is.finite(n) || n <= 0L) return(base_trim)
  if (base_trim <= 0) return(0)
  if (n > large_n) large_trim else base_trim
}

# 发表级小数位（全项目统一入口；config$pub_digits / options 可覆盖）
# 默认：效应量/描述/P/切点一律 3 位（避免中介 path β 等两位变成 0.00）
# desc_trim：描述统计去尾随 0（90 不写 90.000）；est/p 仍固定位数
.pipeline_pub_digits <- function() {
  list(
    est = as.integer(getOption("medical_blocks.pub_digits.est", 3L))[1L],
    p = as.integer(getOption("medical_blocks.pub_digits.p", 3L))[1L],
    desc = as.integer(getOption("medical_blocks.pub_digits.desc", 3L))[1L],
    cutoff = as.integer(getOption("medical_blocks.pub_digits.cutoff", 3L))[1L],
    # 整数（人数 / 事件数 / 计数）千分位：TRUE=1,234；FALSE=1234（全项目单一口径）
    int_big_mark = isTRUE(getOption("medical_blocks.pub_digits.int_big_mark", TRUE)),
    # 描述统计：最多 desc 位，默认去掉尾随 0（整数不写 .000）
    desc_trim = isTRUE(getOption("medical_blocks.pub_digits.desc_trim", TRUE))
  )
}

#' 从 config$pub_digits 注入全局 options（pipeline 启动时调用一次）
pipeline_apply_pub_digits <- function(cfg = NULL) {
  d <- if (is.list(cfg)) (cfg$pub_digits %||% list()) else list()
  if (!is.null(d$est) && is.finite(suppressWarnings(as.integer(d$est)[1L]))) {
    options(medical_blocks.pub_digits.est = as.integer(d$est)[1L])
  }
  if (!is.null(d$p) && is.finite(suppressWarnings(as.integer(d$p)[1L]))) {
    options(medical_blocks.pub_digits.p = as.integer(d$p)[1L])
  }
  if (!is.null(d$desc) && is.finite(suppressWarnings(as.integer(d$desc)[1L]))) {
    options(medical_blocks.pub_digits.desc = as.integer(d$desc)[1L])
  }
  if (!is.null(d$cutoff) && is.finite(suppressWarnings(as.integer(d$cutoff)[1L]))) {
    options(medical_blocks.pub_digits.cutoff = as.integer(d$cutoff)[1L])
  }
  if (!is.null(d$int_big_mark)) {
    options(medical_blocks.pub_digits.int_big_mark = isTRUE(d$int_big_mark))
  }
  if (!is.null(d$desc_trim)) {
    options(medical_blocks.pub_digits.desc_trim = isTRUE(d$desc_trim))
  }
  invisible(.pipeline_pub_digits())
}

# 发表级 P 值格式：极小值统一显示 < 0.001，其余按 pub_digits$p（默认 3 位）
# 用于 SCI 三线表与森林图，避免出现 7.3e-24 这类过长字符串。
pub_format_p <- function(p, small_cut = 0.001, digits = NULL) {
  dig <- as.integer(digits %||% .pipeline_pub_digits()$p)[1L]
  if (!is.finite(dig) || dig < 0L) dig <- 3L
  pn <- suppressWarnings(as.numeric(p))
  out <- character(length(pn))
  for (i in seq_along(pn)) {
    v <- pn[i]
    if (!is.finite(v)) { out[i] <- ""; next }
    if (v < small_cut) { out[i] <- paste0("< ", format(small_cut, scientific = FALSE)); next }
    if (v > 0.999) { out[i] <- ">0.999"; next }
    out[i] <- formatC(round(v, dig), format = "f", digits = dig)
  }
  out
}

# Cox/logistic 表单元格 P：与 pub_format_p 同口径（默认 3 位）；禁止 3/4 位混用
pub_format_p_cell <- function(p, digits = NULL) {
  if (length(p) != 1L) {
    return(vapply(p, function(x) pub_format_p_cell(x, digits = digits), character(1L), USE.NAMES = FALSE))
  }
  if (is.null(p) || length(p) == 0L) return("")
  s <- trimws(as.character(p)[1L])
  if (!nzchar(s) || s %in% c("Ref", "ref", "NA", "NaN")) {
    return(if (s %in% c("NA", "NaN")) "" else s)
  }
  pn <- suppressWarnings(as.numeric(s))
  if (!is.finite(pn)) return(s)
  dig <- as.integer(digits %||% .pipeline_pub_digits()$p)[1L]
  if (!is.finite(dig) || dig < 0L) dig <- 3L
  if (pn < 0.001) return("<0.001")
  formatC(pn, format = "f", digits = dig)
}

pub_fix_p_cells <- function(rt, cols = NULL) {
  rt <- as.data.frame(rt, stringsAsFactors = FALSE)
  if (is.null(cols)) {
    cols <- if (exists("pipeline_table_p_cols", mode = "function")) {
      pipeline_table_p_cols(ncol(rt), binary_layout = ncol(rt) %in% c(11L, 14L))
    } else {
      c(6L, 9L, 12L)
    }
  }
  for (j in cols) {
    if (ncol(rt) < j) next
    rt[[j]] <- pub_format_p_cell(as.character(rt[[j]]))
  }
  rt
}

pub_format_est <- function(x, digits = NULL) {
  dig <- as.integer(digits %||% .pipeline_pub_digits()$est)[1L]
  if (!is.finite(dig) || dig < 0L) dig <- 2L
  # 向量必须逐元素格式化：若只处理首元并返回长度 1，赋值进 data.frame
  # 列时会整列回收成同一个数（Table S5 AUC 曾全表塌成 0.592）。
  if (length(x) != 1L) {
    return(vapply(x, function(xi) pub_format_est(xi, digits = dig),
                  character(1L), USE.NAMES = FALSE))
  }
  xn <- suppressWarnings(as.numeric(x))
  if (length(xn) != 1L || !is.finite(xn)) return(as.character(x)[1L])
  formatC(xn, format = "f", digits = dig)
}

pub_format_ci <- function(lo, hi, digits = NULL) {
  dig <- as.integer(digits %||% .pipeline_pub_digits()$est)[1L]
  paste0("(", pub_format_est(lo, dig), ", ", pub_format_est(hi, dig), ")")
}

# ── 发表级整数格式（人数 / 事件数 / 计数）：全项目唯一入口 ─────────────────────
#   口径由 config$pub_digits$int_big_mark 决定（默认 TRUE = 千分位逗号 "1,234"）。
#   禁止在课题 / Block 里再手写 format(..., big.mark=",") 或 sprintf("%d") 出发表表，
#   否则同表出现 "4,000" 与 "4000" 分叉（审稿必抓）。
pub_format_int <- function(x, big_mark = NULL) {
  use_bm <- isTRUE(big_mark %||% .pipeline_pub_digits()$int_big_mark)
  v <- suppressWarnings(as.numeric(x))
  out <- character(length(v))
  for (i in seq_along(v)) {
    if (!is.finite(v[i])) { out[i] <- ""; next }
    iv <- as.integer(round(v[i]))
    out[i] <- if (use_bm) format(iv, big.mark = ",", scientific = FALSE, trim = TRUE)
              else format(iv, scientific = FALSE, trim = TRUE)
  }
  out
}

# 纯数字串补千分位（"1234" -> "1,234"；<=3 位原样）
.pub_int_comma <- function(d) {
  n <- nchar(d)
  if (n <= 3L) return(d)
  first_len <- ((n - 1) %% 3) + 1
  pieces <- substring(d, 1, first_len)
  pos <- first_len + 1
  while (pos <= n) {
    pieces <- c(pieces, substring(d, pos, pos + 2))
    pos <- pos + 3
  }
  paste(pieces, collapse = ",")
}

# 渲染层千分位守卫：只对「计数上下文」单元格（含 %、/、或 N=/n= 标记）中的
# 独立整数段（≥4 位、前后不挨 数字/. , -）补千分位；已带逗号的幂等跳过。
# 避免误伤年份/年段（2006-2010）、小数（0.1234）、P 值等。
# 用于 .prepare_df_for_tex，统一发表表 xlsx/tex 最终呈现；不改动数据层 CSV。
.pub_group_count_ints <- function(x) {
  x <- as.character(x)
  ok <- !is.na(x) & nzchar(x)
  if (!any(ok)) return(x)
  ctx <- grepl("%", x, fixed = TRUE) |
    grepl("/", x, fixed = TRUE) |
    grepl("(?i)(^|[^A-Za-z])[Nn]\\s*=", x, perl = TRUE)
  for (i in which(ok & ctx)) {
    repeat {
      m <- regexpr("(?<![-\\d.,])\\d{4,}(?![-\\d.,])", x[i], perl = TRUE)
      if (m < 0L) break
      d <- regmatches(x[i], m)
      x[i] <- sub(d, .pub_int_comma(d), x[i], fixed = TRUE)
    }
  }
  x
}

pub_hr_ci_p <- function(model, row = 1L) {
  sm <- summary(model)
  ci <- suppressMessages(stats::confint(model))
  hr <- exp(stats::coef(model))[row]
  list(
    hr = pub_format_est(hr),
    ci = pub_format_ci(exp(ci[row, 1L]), exp(ci[row, 2L])),
    p = pub_format_p_cell(sm$coefficients[row, "Pr(>|z|)"])
  )
}

pub_cox_group_n_header <- function() "N (%)"

# 发病 GLM 分组列：事件数 / 组内 n（组内发病率），禁止再用 Case (%) 填组人数
pub_glm_group_n_header <- function() "Events / N (%)"

pub_glm_group_n_cell <- function(n_event, n_group) {
  n_event <- suppressWarnings(as.integer(n_event)[1L])
  n_group <- suppressWarnings(as.integer(n_group)[1L])
  if (!is.finite(n_event) || n_event < 0L) n_event <- 0L
  if (!is.finite(n_group) || n_group <= 0L) return("")
  paste0(
    pub_format_int(n_event), "/", pub_format_int(n_group),
    " (", fmt_num(100 * n_event / n_group), "%)"
  )
}

pub_glm_group_n_cell_from_data <- function(data, outcome_col, group_col, level) {
  hit <- as.character(data[[group_col]]) == as.character(level)[1L]
  n <- sum(hit, na.rm = TRUE)
  ev <- sum(hit & suppressWarnings(as.numeric(data[[outcome_col]])) == 1, na.rm = TRUE)
  pub_glm_group_n_cell(ev, n)
}

# NHANES/IPTW 加权 logistic：组内事件数 / n（事件率）；禁止填「组占全样本 %」
pub_svy_group_events_n_header <- function() "Events / N (%)"

pub_svy_group_events_n_cell <- function(design, level, outcome_col = "Disease_Group",
                                        group_col = "Group") {
  lvl <- as.character(level)[1L]
  hit <- as.character(design$variables[[group_col]]) == lvl
  n <- sum(hit, na.rm = TRUE)
  y <- suppressWarnings(as.numeric(design$variables[[outcome_col]]))
  # 已是 0/1 则直接用；否则走统一编码
  if (!all(y[!is.na(y)] %in% c(0, 1))) {
    y <- pipeline_outcome_as_01(design$variables[[outcome_col]])
  }
  ev <- sum(hit & y == 1, na.rm = TRUE)
  pub_glm_group_n_cell(ev, n)
}

pipeline_mediation_table_footnotes <- function(standardize = TRUE) {
  out <- character(0)
  if (isTRUE(standardize)) {
    out <- c(out, "Path coefficients and mediator-outcome effects are per 1-SD of the mediator.")
  }
  c(
    out,
    "A negative proportion mediated indicates a suppression (masking) effect, not a mediated fraction."
  )
}

# 中介 LM 调整集 = Cox Model1 / Model2（禁止写死下标 1,15:18）
pipeline_mediation_lm_adjustors <- function(ctx, data_names = NULL) {
  res <- ctx$results %||% list()
  m1 <- unique(as.character(
    res$cox_model1_covariates %||% res$Model1Factors %||% character(0)
  ))
  m1 <- m1[nzchar(m1)]
  m2_extra <- unique(as.character(res$cox_model2_covariates %||% character(0)))
  m2_full <- unique(as.character(res$Model2Factors %||% character(0)))
  m2 <- unique(c(m1, m2_extra[nzchar(m2_extra)], m2_full[nzchar(m2_full)]))
  if (!is.null(data_names)) {
    m1 <- intersect(m1, data_names)
    m2 <- intersect(m2, data_names)
  }
  if (!length(m1) && length(m2)) m1 <- m2[1L]
  list(m1 = m1, m2 = unique(c(m1, m2)))
}

pipeline_s1_missing_pct_row <- function(x_before, x_after, n_before, n_after) {
  n_miss_b <- sum(is.na(x_before))
  n_miss_a <- sum(is.na(x_after))
  pct_b <- if (isTRUE(n_before > 0L)) n_miss_b / n_before * 100 else 0
  pct_a <- if (isTRUE(n_after > 0L)) n_miss_a / n_after * 100 else 0
  data.frame(
    Variable = "  Missing (%)",
    Statistic = "",
    Before_MI = paste0(fmt_num(pct_b), "%"),
    After_MI  = paste0(fmt_num(pct_a), "%"),
    P_value = "",
    .is_cat_row = TRUE,
    .is_section_row = FALSE,
    stringsAsFactors = FALSE
  )
}

pipeline_subgroup_forest_caption <- function(index_var, mode = "highest_vs_lowest") {
  ix <- as.character(index_var)[1L]
  # 文件名/图题保持短名；Q4 vs Q1 / High vs Low 写进 image_information，不塞进括号
  paste0("Subgroup Forest analyses of ", ix)
}

# 机械通气：二分类 ever 与连续小时不得共用一名
pipeline_split_ventilation_mapping <- function(data) {
  if (is.null(data) || !is.data.frame(data)) return(data)
  nm <- names(data)
  hour_aliases <- c("vent_hour", "Ventilation_Hour", "vent_hours", "VentilationHour")
  ever_aliases <- c("Ventilation", "ventilation", "mechvent", "mechanical_ventilation")
  hour_hit <- intersect(nm, hour_aliases)
  ever_hit <- intersect(nm, ever_aliases)
  if (length(hour_hit) && !"Ventilation_Hour" %in% nm) {
    names(data)[names(data) == hour_hit[1L]] <- "Ventilation_Hour"
    for (a in setdiff(hour_hit, hour_hit[1L])) data[[a]] <- NULL
  }
  if (length(ever_hit) && !"Ventilation" %in% names(data)) {
    src <- ever_hit[ever_hit != "Ventilation_Hour"]
    if (length(src)) {
      names(data)[names(data) == src[1L]] <- "Ventilation"
    }
  }
  if ("Ventilation_Hour" %in% names(data)) {
    vh <- suppressWarnings(as.numeric(as.character(data[["Ventilation_Hour"]])))
    nuniq <- length(unique(stats::na.omit(vh)))
    if (nuniq <= 2L && !"Ventilation" %in% names(data)) {
      names(data)[names(data) == "Ventilation_Hour"] <- "Ventilation"
    } else if (!"Ventilation" %in% names(data)) {
      data[["Ventilation"]] <- as.integer(is.finite(vh) & vh > 0)
    }
  }
  if ("Ventilation" %in% names(data)) {
    data[["Ventilation"]] <- pipeline_ventilation_as_ever_factor(data[["Ventilation"]])
  }
  data
}

# 双库通气统一为 No/Yes 因子（ever），禁止 0/1 与小时混用
pipeline_ventilation_as_ever_factor <- function(x) {
  if (is.null(x)) return(x)
  if (is.factor(x)) {
    xs <- trimws(as.character(x))
  } else if (is.logical(x)) {
    xs <- ifelse(is.na(x), NA_character_, ifelse(x, "Yes", "No"))
  } else if (is.numeric(x) || is.integer(x)) {
    xn <- suppressWarnings(as.numeric(x))
    if (!all(stats::na.omit(xn) %in% c(0, 1))) return(x)
    xs <- ifelse(is.na(xn), NA_character_, ifelse(xn > 0, "Yes", "No"))
  } else {
    xs <- trimws(as.character(x))
  }
  xs[xs %in% c("1", "true", "TRUE", "yes", "Y", "y")] <- "Yes"
  xs[xs %in% c("0", "false", "FALSE", "no", "N", "n")] <- "No"
  factor(xs, levels = c("No", "Yes"))
}

# 清洗 No/Yes 二分类列尾随空格（如 "Yes "/"No "），避免敏感性/亚组过滤永远为真
pipeline_normalize_yes_no_factors <- function(data) {
  if (is.null(data) || !is.data.frame(data) || !ncol(data)) return(data)
  for (nm in names(data)) {
    x <- data[[nm]]
    if (is.factor(x)) {
      lv <- trimws(as.character(levels(x)))
      if (length(lv) && all(lv %in% c("No", "Yes", ""))) {
        data[[nm]] <- pipeline_ventilation_as_ever_factor(x)
      }
    } else if (is.character(x)) {
      xu <- unique(stats::na.omit(trimws(x)))
      if (length(xu) && all(xu %in% c("No", "Yes"))) {
        data[[nm]] <- pipeline_ventilation_as_ever_factor(x)
      }
    }
  }
  data
}

# 闸门 A keep 列表：Ventilation_Hour 与 Ventilation(ever) 互为别名，避免拆名后整列被删
# 空 keep = 不过滤；不得把 Ventilation 填进空名单，否则 105 列会被削成 1 列
pipeline_ventilation_keep_alias <- function(keep, data_names) {
  keep <- unique(as.character(keep[nzchar(as.character(keep))]))
  if (!length(keep)) return(keep)
  nms <- as.character(data_names)
  if ("Ventilation_Hour" %in% keep && !"Ventilation_Hour" %in% nms && "Ventilation" %in% nms) {
    keep <- unique(c(setdiff(keep, "Ventilation_Hour"), "Ventilation"))
  }
  if ("Ventilation" %in% nms) keep <- unique(c(keep, "Ventilation"))
  if ("Ventilation_Hour" %in% nms && "Ventilation_Hour" %in% keep) {
    keep <- unique(c(keep, "Ventilation_Hour"))
  }
  keep
}

# 映射后立刻拆 ever/小时，供 Gate A 与 dual_db_load_mapped_frame 共用
pipeline_apply_ventilation_after_map <- function(data) {
  if (is.null(data) || !is.data.frame(data)) return(data)
  if (exists("pipeline_split_ventilation_mapping", mode = "function")) {
    data <- pipeline_split_ventilation_mapping(data)
  }
  data
}

# 两库列名：通气统一为 Ventilation(ever)；小时不得进共有列
pipeline_gate_a_align_ventilation_cols <- function(cols_a, cols_b, common) {
  cols_a <- as.character(cols_a)
  cols_b <- as.character(cols_b)
  common <- unique(as.character(common[nzchar(as.character(common))]))
  a_has <- any(c("Ventilation", "Ventilation_Hour") %in% cols_a)
  b_has <- any(c("Ventilation", "Ventilation_Hour") %in% cols_b)
  if (a_has && b_has && !"Ventilation" %in% common) {
    common <- unique(c(common, "Ventilation"))
  }
  if ("Ventilation" %in% common) {
    common <- setdiff(common, "Ventilation_Hour")
  }
  common
}

# --no-skip 覆盖已有【success】目录前先删目标
pipeline_remove_dir <- function(path) {
  path <- as.character(path)[1L]
  if (!nzchar(path) || !dir.exists(path)) return(TRUE)
  unlink(path, recursive = TRUE, force = TRUE)
  if (dir.exists(path)) {
    system2("rm", c("-rf", path), stdout = TRUE, stderr = TRUE)
  }
  !dir.exists(path)
}

# *_Hour 连续变量：单因素 Cox 按每 24h 报告，避免 HR=1.00 (1.00-1.00)
pipeline_cox_unit_scale <- function(var, x) {
  v <- as.character(var)[1L]
  if (grepl("Hour$|_Hour$|_Hours$|hour$", v, ignore.case = TRUE) &&
      is.numeric(x) && length(unique(stats::na.omit(x))) > 2L) {
    return(list(x = as.numeric(x) / 24, label = "per 24 h", scale = 24))
  }
  list(x = x, label = "per unit", scale = 1)
}

#' 连续变量极端值置 NA（不删行）
#'
#' config$extreme_to_na（亦可写在 univariate_*$extreme_to_na）:
#'   enable, method=("percentile"|"iqr"), probs=c(0.01,0.99), iqr_factor=1.5,
#'   min_unique=20, protect_vars, protect_demo=TRUE, vars=NULL（默认全体数值列）
#' @return list(data, n_set, per_var)
pipeline_extreme_values_to_na <- function(data, cfg = list(), uv_cfg = list()) {
  if (is.null(data) || !is.data.frame(data) || !nrow(data)) {
    return(list(data = data, n_set = 0L, per_var = integer(0)))
  }
  ex <- cfg$extreme_to_na %||% list()
  if (!length(ex) && is.list(uv_cfg)) {
    ex <- uv_cfg$extreme_to_na %||% list()
  }
  if (!isTRUE(ex$enable %||% FALSE)) {
    return(list(data = data, n_set = 0L, per_var = integer(0)))
  }
  method <- tolower(trimws(as.character(ex$method %||% "percentile")[1L]))
  if (!method %in% c("percentile", "iqr")) method <- "percentile"
  probs <- suppressWarnings(as.numeric(ex$probs %||% c(0.01, 0.99)))
  if (length(probs) < 2L || any(!is.finite(probs))) probs <- c(0.01, 0.99)
  probs <- sort(probs[seq_len(2L)])
  if (probs[1L] < 0) probs[1L] <- 0
  if (probs[2L] > 1) probs[2L] <- 1
  iqr_f <- suppressWarnings(as.numeric(ex$iqr_factor %||% 1.5)[1L])
  if (!is.finite(iqr_f) || iqr_f <= 0) iqr_f <- 1.5
  min_u <- suppressWarnings(as.integer(ex$min_unique %||% 20L)[1L])
  if (!is.finite(min_u) || min_u < 5L) min_u <- 20L

  protect <- unique(c(
    as.character(ex$protect_vars %||% character(0)),
    as.character((cfg$data %||% list())$id_column %||% character(0)),
    "ID", "subject_id", "SEQN",
    as.character((cfg$data %||% list())$outcome_column %||% character(0)),
    as.character((cfg$incidence %||% list())$outcome_var %||% character(0)),
    as.character((cfg$survival %||% list())$event_var %||% character(0)),
    as.character((cfg$survival %||% list())$time_var %||% character(0)),
    as.character((cfg$incidence %||% list())$index_var %||% character(0)),
    as.character((cfg$survival %||% list())$index_var %||% character(0)),
    as.character((cfg$competing_risk %||% list())$index_var %||% character(0))
  ))
  protect <- protect[nzchar(protect)]
  if (!isFALSE(ex$protect_demo %||% TRUE)) {
    demo_kw <- c(
      "Age", "Gender", "Sex", "Race", "Ethnicity", "Education",
      "Height", "Weight", "BMI"
    )
    protect <- unique(c(protect, intersect(demo_kw, names(data))))
  }

  cand <- as.character(ex$vars %||% character(0))
  if (!length(cand) || !any(nzchar(cand))) {
    cand <- names(data)
  }
  cand <- setdiff(unique(cand[nzchar(cand)]), protect)
  cand <- cand[cand %in% names(data)]

  n_set <- 0L
  per_var <- integer(0)
  for (v in cand) {
    x <- data[[v]]
    if (!(is.numeric(x) || is.integer(x))) next
    x <- as.numeric(x)
    ok <- is.finite(x)
    if (sum(ok) < min_u) next
    n_u <- length(unique(x[ok]))
    if (n_u < min_u) next
    # 近似二分类 / 低基数：不裁
    if (n_u <= 5L) next
    if (identical(method, "iqr")) {
      q <- stats::quantile(x[ok], probs = c(0.25, 0.75), names = FALSE, na.rm = TRUE, type = 7)
      iqr <- q[2L] - q[1L]
      if (!is.finite(iqr) || iqr <= 0) next
      lo <- q[1L] - iqr_f * iqr
      hi <- q[2L] + iqr_f * iqr
    } else {
      q <- stats::quantile(x[ok], probs = probs, names = FALSE, na.rm = TRUE, type = 7)
      lo <- q[1L]
      hi <- q[2L]
    }
    if (!is.finite(lo) || !is.finite(hi) || hi < lo) next
    bad <- ok & (x < lo | x > hi)
    n_bad <- sum(bad, na.rm = TRUE)
    if (!n_bad) next
    x[bad] <- NA_real_
    data[[v]] <- x
    n_set <- n_set + as.integer(n_bad)
    per_var[[v]] <- as.integer(n_bad)
  }
  list(data = data, n_set = n_set, per_var = per_var)
}

#' 对 ctx$data 各分析槽应用极端值置空；返回更新后的 ctx 与当前分析用 data
pipeline_apply_extreme_to_na <- function(ctx, data = NULL, label = "extreme_to_na") {
  cfg <- ctx$config %||% list()
  uv_cfg <- cfg$univariate_prognosis %||% cfg$univariate_incidence_binary %||% list()
  ex <- cfg$extreme_to_na %||% uv_cfg$extreme_to_na %||% list()
  if (!isTRUE(ex$enable %||% FALSE)) {
    return(list(ctx = ctx, data = data, n_set = 0L))
  }
  persist <- !isFALSE(ex$persist_to_imputed %||% TRUE)
  total <- 0L
  merged_pv <- integer(0)
  if (isTRUE(persist)) {
    for (slot in c("imputed", "cleaned", "train", "validation", "val", "test")) {
      df <- ctx$data[[slot]]
      if (is.null(df) || !is.data.frame(df) || !nrow(df)) next
      res <- pipeline_extreme_values_to_na(df, cfg, uv_cfg)
      if ((res$n_set %||% 0L) <= 0L) next
      ctx$data[[slot]] <- res$data
      total <- total + as.integer(res$n_set)
      for (nm in names(res$per_var)) {
        prev <- if (nm %in% names(merged_pv)) as.integer(merged_pv[[nm]]) else 0L
        merged_pv[nm] <- prev + as.integer(res$per_var[[nm]])
      }
    }
  }
  if (!is.null(data) && is.data.frame(data)) {
    res_d <- pipeline_extreme_values_to_na(data, cfg, uv_cfg)
    data <- res_d$data
    if (!isTRUE(persist)) {
      total <- total + as.integer(res_d$n_set %||% 0L)
      for (nm in names(res_d$per_var)) {
        prev <- if (nm %in% names(merged_pv)) as.integer(merged_pv[[nm]]) else 0L
        merged_pv[nm] <- prev + as.integer(res_d$per_var[[nm]])
      }
    }
  } else if (isTRUE(persist)) {
    data <- ctx$data$imputed %||% ctx$data$cleaned %||% data
  }
  if (total > 0L && requireNamespace("cli", quietly = TRUE)) {
    top <- utils::head(sort(merged_pv, decreasing = TRUE), 8L)
    cli::cli_alert_info(
      "{label}: 极端值置 NA {total} 个单元格（不删行）; 例: {paste(sprintf('%s=%d', names(top), as.integer(top)), collapse=', ')}"
    )
  }
  ctx$results$extreme_to_na <- list(n_set = total, per_var = merged_pv, persist = persist)
  list(ctx = ctx, data = data, n_set = total)
}

# 批量发病 by_index 目录名：【success】<ix> / 【failed】<ix>
incidence_batch_status_label <- function(status) {
  if (identical(as.character(status), "success")) "success" else "failed"
}

incidence_batch_output_dir_name <- function(ix, status = NULL) {
  ix <- as.character(ix)[1L]
  if (is.null(status)) return(ix)
  paste0("\u3010", incidence_batch_status_label(status), "\u3011", ix)
}

#' by_index 目录名（可与指标名 ix 不同，如 Preop_Cr【更改协变量版】）
incidence_batch_index_dir_label <- function(ix, config = list()) {
  ix <- as.character(ix)[1L]
  bc <- config$incidence_batch %||% config$ml_batch %||% config$survival_batch %||% list()
  lab_map <- bc$index_output_label_map %||% list()
  if (!is.null(lab_map[[ix]]) && nzchar(as.character(lab_map[[ix]])[1L])) {
    return(as.character(lab_map[[ix]])[1L])
  }
  suf <- as.character(bc$index_output_label_suffix %||% "")[1L]
  if (nzchar(suf)) return(paste0(ix, suf))
  ix
}

# Unix / Windows 绝对路径（G:/、C:/、/mnt/...）
is_absolute_path <- function(p) {
  p <- as.character(p)[1L]
  if (!nzchar(p)) return(FALSE)
  grepl("^/", p) || grepl("^[A-Za-z]:[/\\\\]", p)
}

# ── 亚型参照组：按各亚型粗事件率（0/1 结局）选最低风险类 ─────────────────────
pipeline_pick_lowest_risk_subphenotype_ref <- function(data, subphenotype_col,
                                                       class_levels, event01) {
  event01 <- as.numeric(event01)
  class_levels <- as.character(class_levels)
  rates <- vapply(class_levels, function(cls) {
    m <- !is.na(data[[subphenotype_col]]) &
      as.character(data[[subphenotype_col]]) == cls
    y <- event01[m]
    y <- y[!is.na(y)]
    if (!length(y)) return(NA_real_)
    mean(y == 1, na.rm = TRUE)
  }, numeric(1))
  names(rates) <- class_levels
  ok <- is.finite(rates)
  if (!any(ok)) {
    return(list(ref = class_levels[1L], rates = rates))
  }
  ref <- class_levels[which.min(rates)]
  list(ref = as.character(ref), rates = rates)
}

pipeline_resolve_subphenotype_ref_class <- function(bl_cfg, data, subphenotype_col,
                                                    class_levels, event01,
                                                    block_label = "subphenotype") {
  ref_cfg <- bl_cfg$ref_class
  use_auto <- isTRUE(bl_cfg$ref_class_lowest_risk) ||
    is.null(ref_cfg) ||
    (length(ref_cfg) == 1L && is.na(ref_cfg)) ||
    (length(ref_cfg) >= 1L &&
       tolower(trimws(as.character(ref_cfg[1L]))) %in%
         c("auto", "lowest_risk", "lowest-risk"))

  if (!use_auto && length(ref_cfg) >= 1L) {
    ref <- as.character(ref_cfg[1L])
    if (ref %in% class_levels) {
      cli::cli_alert_info("{block_label}: 使用配置指定参照组 Class {ref}")
      return(ref)
    }
    cli::cli_alert_warning(
      "{block_label}: ref_class={ref} 不在亚型水平中，改为自动选最低风险类"
    )
    use_auto <- TRUE
  }

  pick <- pipeline_pick_lowest_risk_subphenotype_ref(
    data, subphenotype_col, class_levels, event01
  )
  for (cls in names(pick$rates)) {
    r <- pick$rates[[cls]]
    if (is.finite(r)) {
      n_cls <- sum(
        !is.na(data[[subphenotype_col]]) &
          as.character(data[[subphenotype_col]]) == cls,
        na.rm = TRUE
      )
      cli::cli_alert_info(
        "  Class {cls}: 粗事件率 = {round(100 * r, 2)}% (n={n_cls})"
      )
    }
  }
  cli::cli_alert_info(
    "{block_label}: 参照组 = Class {pick$ref}（各亚型中最低风险）"
  )
  pick$ref
}

# 按粗事件率重排亚型编号：最低风险 → Class 1，次低 → Class 2，…（双库 align_subtype_semantics）
pipeline_remap_subphenotype_by_risk <- function(results, df_final, event01, align = TRUE) {
  if (!isTRUE(align) || is.null(results) || is.null(df_final)) {
    return(list(results = results, df_final = df_final, mapping = NULL))
  }
  if (!"Subphenotype" %in% names(df_final)) {
    return(list(results = results, df_final = df_final, mapping = NULL))
  }
  event01 <- suppressWarnings(as.numeric(event01))
  cls_chr <- as.character(df_final$Subphenotype)
  ok <- !is.na(cls_chr) & !is.na(event01)
  if (!any(ok)) {
    cli::cli_alert_warning("align_subtype_semantics: 无可用事件数据，跳过标签重排")
    return(list(results = results, df_final = df_final, mapping = NULL))
  }
  levels <- sort(unique(as.integer(cls_chr[ok])))
  if (length(levels) < 2L) {
    return(list(results = results, df_final = df_final, mapping = NULL))
  }
  rates <- vapply(levels, function(l) {
    y <- event01[ok & cls_chr == as.character(l)]
    if (!length(y)) return(NA_real_)
    mean(y == 1, na.rm = TRUE)
  }, numeric(1))
  names(rates) <- as.character(levels)
  if (!any(is.finite(rates))) {
    cli::cli_alert_warning("align_subtype_semantics: 无法计算各亚型事件率，跳过标签重排")
    return(list(results = results, df_final = df_final, mapping = NULL))
  }
  ord <- order(rates, na.last = NA)
  new_levels <- seq_along(levels)
  mapping <- setNames(as.character(new_levels), as.character(levels[ord]))
  for (cls in names(rates)) {
    if (is.finite(rates[[cls]])) {
      cli::cli_alert_info(
        "  align: Class {cls} 粗事件率 = {round(100 * rates[[cls]], 2)}% → 新 Class {mapping[[cls]]}"
      )
    }
  }
  .remap_vec <- function(v) {
    out <- mapping[as.character(v)]
    as.integer(out)
  }
  for (k in 2:length(results)) {
    if (is.null(results[[k]])) next
    cls <- results[[k]]$consensusClass
    if (is.null(cls)) next
    results[[k]]$consensusClass <- .remap_vec(cls)
  }
  df_final$Subphenotype <- factor(.remap_vec(df_final$Subphenotype), levels = new_levels)
  list(results = results, df_final = df_final, mapping = mapping)
}

# ── 建模/特征选择：永不应作为预测变量的列名（仅读 config，不在各 block 内硬编码）────
pipeline_never_predictor_names <- function(cfg) {
  cfg <- cfg %||% list()
  dc  <- cfg$data %||% list()
  uv_excl <- if (exists("pipeline_uv_excluded_predictors", mode = "function")) {
    pipeline_uv_excluded_predictors(cfg)
  } else {
    unique(c(
      as.character((cfg$univariate_prognosis %||% list())$excluded_predictors %||% character(0)),
      as.character((cfg$univariate_incidence_binary %||% list())$excluded_predictors %||% character(0)),
      as.character((cfg$univariate_incidence_multiclass %||% list())$excluded_predictors %||% character(0))
    ))
  }
  mc  <- cfg$multicollinearity %||% list()
  pr  <- cfg$prediction %||% list()
  fs  <- cfg$feature_selection %||% list()
  unique(c(
    as.character(dc$id_column %||% character(0)),
    as.character(dc$strip_id_columns_after_imputation %||% character(0)),
    if (exists("pipeline_outcome_leak_columns", mode = "function")) {
      pipeline_outcome_leak_columns(cfg)
    } else {
      c("Disease", "Disease_Group")
    },
    uv_excl,
    as.character(mc$exclude_vars %||% character(0)),
    as.character(pr$forbidden_model_predictors %||% character(0)),
    as.character(fs$exclude_vars %||% character(0))
  ))
}

# 0/1 占位标签：发病解析为疾病/非疾病，预后解析为死亡/存活展示名
.pipeline_is_binary_code_label <- function(x) {
  x <- trimws(as.character(x)[1L])
  identical(x, "0") || identical(x, "1") || !nzchar(x)
}

pipeline_resolve_outcome_display_labels <- function(cfg) {
  prj <- cfg$project %||% list()
  study_type <- tolower(trimws(as.character(prj$study_type %||% "")[1L]))
  is_prognosis <- identical(study_type, "prognosis")
  disease <- trimws(as.character(prj$disease %||% prj$disease_label %||% character(0))[1L])
  if (is.na(disease) || !nzchar(disease)) disease <- "Case"

  ana_raw <- prj$analysis_group %||% ""
  ref_raw <- prj$reference_group %||% ""
  ana_cfg <- trimws(as.character(ana_raw)[1L])
  ref_cfg <- trimws(as.character(ref_raw)[1L])
  if (is.na(ana_cfg)) ana_cfg <- ""
  if (is.na(ref_cfg)) ref_cfg <- ""

  ref_alt <- ""
  for (candidate in list(prj$reference_group_label, prj$control_group, prj$noncase_label)) {
    if (is.null(candidate) || !length(candidate)) next
    candidate <- trimws(as.character(candidate)[1L])
    if (!is.na(candidate) && nzchar(candidate) && !.pipeline_is_binary_code_label(candidate)) {
      ref_alt <- candidate
      break
    }
  }

  analysis_lbl <- if (.pipeline_is_binary_code_label(ana_cfg)) {
    if (is_prognosis) "Non-survivor" else disease
  } else ana_cfg

  reference_lbl <- if (.pipeline_is_binary_code_label(ref_cfg)) {
    if (nzchar(ref_alt)) ref_alt
    else if (is_prognosis) "Survivor"
    else paste0("No ", disease)
  } else ref_cfg

  list(analysis = analysis_lbl, reference = reference_lbl)
}

pipeline_outcome_case_label <- function(cfg) {
  pipeline_resolve_outcome_display_labels(cfg)$analysis
}

pipeline_outcome_reference_label <- function(cfg) {
  pipeline_resolve_outcome_display_labels(cfg)$reference
}

#' 将结局向量编码为 0/1。
#'
#' 已是 0/1 数值（如 rcs_nhanes 写入的 nhanes_design_rcs$Disease_Group）则原样返回，
#' 避免再与疾病名比较导致全 0（Table S-XX 连续 OR 被错写成 ~1.0）。
#'
#' 铁律：单因素 / logistic GLM·clogit 等在 `analysis_group="1"` 但列已是
#' 疾病显示名（Diabetes / No Diabetes）时，**必须**调用本函数（或
#' `pipeline_outcome_case_label` 取阳性名），禁止 `x == cfg$project$analysis_group`。
pipeline_outcome_as_01 <- function(x, cfg = NULL, case_label = NULL) {
  if (is.null(x)) return(x)
  if (is.numeric(x) || is.integer(x) || is.logical(x)) {
    ux <- unique(as.numeric(x)[is.finite(as.numeric(x))])
    if (length(ux) && all(ux %in% c(0, 1))) {
      return(as.numeric(x))
    }
  }
  xc <- trimws(as.character(x))
  ux_c <- unique(xc[!is.na(xc) & nzchar(xc)])
  if (length(ux_c) && all(ux_c %in% c("0", "1"))) {
    return(as.numeric(xc == "1"))
  }
  if (length(ux_c) && all(ux_c %in% c("Yes", "No"))) {
    return(as.numeric(xc == "Yes"))
  }
  lbl <- case_label
  if (is.null(lbl) || !nzchar(as.character(lbl)[1L])) {
    lbl <- if (!is.null(cfg) && exists("pipeline_outcome_case_label", mode = "function")) {
      pipeline_outcome_case_label(cfg)
    } else {
      "1"
    }
  }
  lbl <- as.character(lbl)[1L]
  as.numeric(xc == lbl | xc == "1")
}

pipeline_normalize_project_outcome_labels <- function(cfg) {
  if (is.null(cfg) || !is.list(cfg)) return(cfg)
  lbl <- pipeline_resolve_outcome_display_labels(cfg)
  if (is.null(cfg$project)) cfg$project <- list()
  cfg$project$analysis_group <- lbl$analysis
  cfg$project$reference_group <- lbl$reference
  cfg
}

# 将结局列 0/1（数值或字符）替换为 reference/analysis 展示名
pipeline_relabel_binary_outcome_column <- function(data, cfg, col = NULL, extra_cols = NULL) {
  if (is.null(data) || !is.data.frame(data)) return(data)
  lbl <- pipeline_resolve_outcome_display_labels(cfg)
  prj <- cfg$project %||% list()
  raw_ana <- trimws(as.character(prj$analysis_group %||% character(0))[1L])
  raw_ref <- trimws(as.character(prj$reference_group %||% character(0))[1L])
  code_labels <- unique(c("0", "1", raw_ana, raw_ref))
  code_labels <- code_labels[.pipeline_is_binary_code_label(code_labels)]

  cols <- unique(c(
    as.character(col %||% (cfg$data %||% list())$outcome_column %||% "Disease")[1L],
    as.character(extra_cols %||% character(0))
  ))
  cols <- intersect(cols[nzchar(cols)], names(data))
  if (!length(cols)) return(data)

  .to_case_lbl <- function(v) {
    if (is.na(v)) return(NA_character_)
    if (is.numeric(v) || is.integer(v)) {
      return(if (v == 1L) lbl$analysis else lbl$reference)
    }
    xc <- trimws(as.character(v))
    if (xc %in% c("1", lbl$analysis) || (length(code_labels) && xc %in% code_labels && xc == "1")) {
      return(lbl$analysis)
    }
    if (xc %in% c("0", lbl$reference) || (length(code_labels) && xc %in% code_labels && xc == "0")) {
      return(lbl$reference)
    }
    if (xc %in% c("Yes", "yes", "Y", "y")) return(lbl$analysis)
    if (xc %in% c("No", "no", "N", "n")) return(lbl$reference)
    xc
  }

  for (cn in cols) {
    x <- data[[cn]]
    vals <- stats::na.omit(unique(x))
    if (!length(vals)) next
    char_vals <- trimws(as.character(vals))
    needs <- (is.numeric(x) || is.integer(x)) && all(vals %in% c(0, 1))
    needs <- needs || all(char_vals %in% c("0", "1"))
    needs <- needs || all(char_vals %in% c("Yes", "No"))
    needs <- needs || (length(code_labels) && all(char_vals %in% code_labels))
    if (!needs) next
    new_x <- vapply(x, .to_case_lbl, character(1L))
    data[[cn]] <- factor(new_x, levels = c(lbl$reference, lbl$analysis))
  }
  data
}

# ── data_clean 扩展：列重命名 / dabiao 队列过滤 / 预后补充表合并 / MIMIC 28天生存衍生 ──

pipeline_data_clean_rename_columns <- function(data, cfg) {
  if (is.null(data) || !is.data.frame(data)) return(data)
  dc <- cfg$data_clean %||% list()
  renames <- dc$rename_columns %||% NULL
  if (is.null(renames) || !length(renames)) return(data)
  if (is.character(renames) && !is.null(names(renames))) {
    for (old_nm in names(renames)) {
      new_nm <- as.character(renames[[old_nm]])[1L]
      if (!nzchar(old_nm) || !nzchar(new_nm) || !old_nm %in% names(data)) next
      if (new_nm %in% names(data) && !identical(old_nm, new_nm)) next
      names(data)[names(data) == old_nm] <- new_nm
      cli::cli_alert_info("data_clean: 列重命名 {old_nm} → {new_nm}")
    }
    return(data)
  }
  data
}

#' 生理不可能值置 NA（插补前）。不删人。
#'
#' config$data_clean$implausible_ranges 示例:
#'   list(
#'     Height = list(min = 100, max = 250),
#'     Weight = list(min = 20, max = 250),
#'     BMI = list(min = 12, max = 60),
#'     Total_Cholesterol = list(max = 20, only_if_median_below = 30)  # 仅 mmol/L
#'   )
pipeline_data_clean_apply_implausible_ranges <- function(data, cfg) {
  if (is.null(data) || !is.data.frame(data)) return(data)
  ranges <- (cfg$data_clean %||% list())$implausible_ranges
  if (is.null(ranges) || !length(ranges)) return(data)
  n_flag <- 0L
  for (vn in names(ranges)) {
    if (!vn %in% names(data)) next
    spec <- ranges[[vn]]
    if (!is.list(spec)) next
    x <- suppressWarnings(as.numeric(data[[vn]]))
    if (!any(is.finite(x))) next
    med <- stats::median(x, na.rm = TRUE)
    med_gate <- suppressWarnings(as.numeric(spec$only_if_median_below %||% NA_real_)[1L])
    if (is.finite(med_gate) && is.finite(med) && med >= med_gate) next
    lo <- suppressWarnings(as.numeric(spec$min %||% NA_real_)[1L])
    hi <- suppressWarnings(as.numeric(spec$max %||% NA_real_)[1L])
    bad <- is.finite(x) & (
      (is.finite(lo) & x < lo) | (is.finite(hi) & x > hi)
    )
    n_bad <- sum(bad, na.rm = TRUE)
    if (!n_bad) next
    data[[vn]][bad] <- NA_real_
    n_flag <- n_flag + n_bad
    if (requireNamespace("cli", quietly = TRUE)) {
      cli::cli_alert_info(
        "data_clean: {vn} 生理不可能值置 NA n={n_bad} (min={lo}, max={hi})"
      )
    }
  }
  if (n_flag > 0L && requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_info("data_clean: implausible_ranges 共置 NA {n_flag} 个单元格，不删人")
  }
  data
}

pipeline_data_clean_apply_cohort_filter <- function(data, cfg) {
  if (is.null(data) || !is.data.frame(data)) return(data)
  dc <- cfg$data_clean %||% list()
  cohort_path <- dc$cohort_id_path %||% dc$cohort_filter_path %||% NULL
  if (is.null(cohort_path) || !nzchar(cohort_path)) return(data)
  id_col <- as.character((cfg$data %||% list())$id_column %||% "subject_id")[1L]
  cohort_id_col <- as.character(dc$cohort_id_column %||% id_col)[1L]
  if (!file.exists(cohort_path)) {
    stop("data_clean: cohort_id_path 不存在: ", cohort_path, call. = FALSE)
  }
  cohort_df <- load_rawdata(cohort_path)
  if (!cohort_id_col %in% names(cohort_df)) {
    stop("data_clean: cohort 文件缺少 ID 列 ", cohort_id_col, ": ", cohort_path, call. = FALSE)
  }
  if (!id_col %in% names(data)) {
    stop("data_clean: 主表缺少 ID 列 ", id_col, "，无法按 dabiao/队列过滤", call. = FALSE)
  }
  keep_ids <- unique(as.character(cohort_df[[cohort_id_col]]))
  keep_ids <- keep_ids[nzchar(keep_ids)]
  if (!length(keep_ids)) stop("data_clean: cohort_id_path 中 ID 为空", call. = FALSE)
  n_before <- nrow(data)
  data[[id_col]] <- as.character(data[[id_col]])
  data <- data[data[[id_col]] %in% keep_ids, , drop = FALSE]
  cli::cli_alert_info(
    "data_clean: cohort 过滤 ({basename(cohort_path)}): {n_before} → {nrow(data)} 行（{length(keep_ids)} 个 {cohort_id_col}）"
  )
  data
}

pipeline_data_clean_merge_supplement <- function(data, cfg) {
  if (is.null(data) || !is.data.frame(data)) return(data)
  dc <- cfg$data_clean %||% list()
  sup_path <- dc$supplement_merge_path %||% dc$aux_merge_path %||% NULL
  if (is.null(sup_path) || !nzchar(sup_path)) return(data)
  id_col <- as.character((cfg$data %||% list())$id_column %||% "subject_id")[1L]
  sup_id_col <- as.character(dc$supplement_merge_id_column %||% id_col)[1L]
  if (!file.exists(sup_path)) {
    stop("data_clean: supplement_merge_path 不存在: ", sup_path, call. = FALSE)
  }
  sup_df <- load_rawdata(sup_path)
  if (!sup_id_col %in% names(sup_df)) {
    stop("data_clean: 补充表缺少 ID 列 ", sup_id_col, ": ", sup_path, call. = FALSE)
  }
  if (!id_col %in% names(data)) {
    stop("data_clean: 主表缺少 ID 列 ", id_col, "，无法合并补充表", call. = FALSE)
  }
  sup_cols <- as.character(dc$supplement_merge_columns %||% character(0))
  sup_cols <- unique(sup_cols[nzchar(sup_cols)])
  if (length(sup_cols)) {
    sup_cols <- intersect(sup_cols, names(sup_df))
    sup_df <- sup_df[, c(sup_id_col, sup_cols), drop = FALSE]
  } else {
    dup_cols <- intersect(setdiff(names(sup_df), sup_id_col), names(data))
    if (length(dup_cols)) {
      sup_df <- sup_df[, !names(sup_df) %in% dup_cols, drop = FALSE]
    }
  }
  data[[id_col]] <- as.character(data[[id_col]])
  sup_df[[sup_id_col]] <- as.character(sup_df[[sup_id_col]])
  n_before <- nrow(data)
  by_cols <- if (identical(sup_id_col, id_col)) id_col else c(id_col, sup_id_col)
  if (!identical(sup_id_col, id_col)) {
    names(sup_df)[names(sup_df) == sup_id_col] <- id_col
  }
  data <- merge(data, sup_df, by = id_col, all.x = TRUE, sort = FALSE)
  cli::cli_alert_info(
    "data_clean: 合并补充表 {basename(sup_path)}: {n_before} → {nrow(data)} 行 × {ncol(data)} 列"
  )
  data
}

pipeline_derive_mimic_survival_28d <- function(data, cfg) {
  if (is.null(data) || !is.data.frame(data)) return(data)
  dc <- cfg$data_clean %||% list()
  if (!isTRUE(dc$derive_mimic_survival_28d %||% FALSE)) return(data)
  need <- c("hosp_day", "is_hosp_dead")
  miss <- setdiff(need, names(data))
  if (length(miss)) {
    stop(
      "data_clean: derive_mimic_survival_28d 需要列 ",
      paste(need, collapse = ", "),
      "；缺失: ", paste(miss, collapse = ", "),
      call. = FALSE
    )
  }
  hosp_day <- suppressWarnings(as.numeric(data$hosp_day))
  is_dead <- suppressWarnings(as.numeric(data$is_hosp_dead))
  data$survival_time_28d <- ifelse(hosp_day > 28, 28, hosp_day)
  data$survival_28d <- ifelse(hosp_day > 28 & is_dead == 1, 0, is_dead)
  if (!"Mortality_28d" %in% names(data)) {
    data$Mortality_28d <- data$survival_28d
  }
  cli::cli_alert_success(
    "data_clean: 已衍生 survival_time_28d / survival_28d（MIMIC 28天截尾规则）"
  )
  data
}

#' 28天糖尿病竞争风险结局衍生（缺血性脑卒中 × HbA1c 竞争风险模型）
#'
#' status = 0  28天内未达标且仍观测（右删失，含窗口外才死亡/出院的情形）
#' status = 1  首次 HbA1c ≥ hba1c_threshold（主事件：糖尿病）
#' status = 2  达标前死亡（窗口内死亡）
#' status = 3  达标前出院（窗口内出院、未死亡）
#'
#' time = min(首次达标日, 死亡/出院日, followup_days) - 入院日（day 计数，与 hosp_day 同基准）
#'
#' 需要 config$data_clean$derive_competing_diabetes_28d = TRUE，以及：
#'   config$competing_risk$hba1c_lab_csv_path   — 逐日 HbA1c 宽表 CSV（lab{d}_laba1c 列）
#'   config$competing_risk$hba1c_threshold      — 默认 6.5
#'   config$competing_risk$followup_days        — 默认 28
#'   主表需已合并 hosp_day / is_hosp_dead（供 pipeline_data_clean_merge_supplement 完成）
pipeline_competing_primary_event <- function(status, primary_cause = 1L) {
  status_num <- suppressWarnings(as.integer(status))
  primary <- suppressWarnings(as.integer(primary_cause)[1L])
  out <- as.integer(status_num == primary)
  out[is.na(status_num)] <- NA_integer_
  out
}

pipeline_derive_competing_diabetes_28d <- function(data, cfg) {
  if (is.null(data) || !is.data.frame(data)) return(data)
  dc <- cfg$data_clean %||% list()
  if (!isTRUE(dc$derive_competing_diabetes_28d %||% FALSE)) return(data)

  cr <- cfg$competing_risk %||% list()
  id_col <- as.character((cfg$data %||% list())$id_column %||% "subject_id")[1L]
  need <- c(id_col, "hosp_day", "is_hosp_dead")
  miss <- setdiff(need, names(data))
  if (length(miss)) {
    stop(
      "data_clean: derive_competing_diabetes_28d 需要列 ", paste(need, collapse = ", "),
      "；缺失: ", paste(miss, collapse = ", "), call. = FALSE
    )
  }
  lab_path <- cr$hba1c_lab_csv_path %||% NULL
  if (is.null(lab_path) || !nzchar(lab_path) || !file.exists(lab_path)) {
    stop(
      "data_clean: derive_competing_diabetes_28d 需要 config$competing_risk$hba1c_lab_csv_path（存在的 CSV 路径）",
      call. = FALSE
    )
  }
  if (!requireNamespace("data.table", quietly = TRUE)) {
    stop("derive_competing_diabetes_28d 需要 data.table 包", call. = FALSE)
  }

  threshold  <- as.numeric(cr$hba1c_threshold %||% 6.5)[1L]
  followup   <- as.integer(cr$followup_days %||% 28L)[1L]
  lab_id_col <- as.character(cr$hba1c_lab_id_column %||% id_col)[1L]
  lab_prefix <- as.character(cr$hba1c_lab_prefix %||% "laba1c")[1L]

  header    <- names(data.table::fread(lab_path, nrows = 0L))
  want_cols <- paste0("lab", seq_len(followup), "_", lab_prefix)
  a1c_cols  <- intersect(want_cols, header)
  if (!length(a1c_cols)) {
    stop("derive_competing_diabetes_28d: CSV 中找不到任何 lab{d}_", lab_prefix, " 列: ", lab_path, call. = FALSE)
  }
  select_cols <- unique(c(lab_id_col, a1c_cols))
  lab <- data.table::fread(lab_path, select = select_cols)
  lab[[lab_id_col]] <- as.character(lab[[lab_id_col]])

  keep_ids <- unique(as.character(data[[id_col]]))
  lab <- lab[lab[[lab_id_col]] %in% keep_ids]
  if (anyDuplicated(lab[[lab_id_col]])) lab <- lab[!duplicated(lab[[lab_id_col]])]

  day_mat <- suppressWarnings(apply(as.matrix(lab[, a1c_cols, with = FALSE]), 2, as.numeric))
  day_mat <- matrix(as.numeric(day_mat), nrow = nrow(lab), ncol = length(a1c_cols))
  day_num <- as.integer(sub(paste0("^lab(\\d+)_", lab_prefix, "$"), "\\1", a1c_cols))
  hit <- day_mat >= threshold
  hba1c_day <- vapply(seq_len(nrow(hit)), function(i) {
    w <- which(hit[i, ])
    if (length(w)) min(day_num[w]) else NA_integer_
  }, integer(1))

  outcome_df <- data.frame(
    id_tmp = as.character(lab[[lab_id_col]]),
    hba1c_day = hba1c_day,
    stringsAsFactors = FALSE
  )
  names(outcome_df)[1] <- id_col

  data[[id_col]] <- as.character(data[[id_col]])
  n_before <- nrow(data)
  data <- merge(data, outcome_df, by = id_col, all.x = TRUE, sort = FALSE)
  if (nrow(data) != n_before) {
    stop("derive_competing_diabetes_28d: 合并后行数变化（存在重复 ID），请检查数据", call. = FALSE)
  }

  hosp_day <- suppressWarnings(as.numeric(data$hosp_day))
  is_dead  <- suppressWarnings(as.numeric(data$is_hosp_dead))
  terminal_in_window <- is.finite(hosp_day) & hosp_day <= followup
  terminal_status <- ifelse(is_dead == 1, 2L, 3L)

  hba1c_day_v <- data$hba1c_day
  hba1c_ok <- is.finite(hba1c_day_v) & hba1c_day_v <= followup

  status <- ifelse(
    hba1c_ok & (!terminal_in_window | hba1c_day_v <= hosp_day), 1L,
    ifelse(terminal_in_window, terminal_status, 0L)
  )
  time <- ifelse(
    status == 1L, hba1c_day_v,
    ifelse(status %in% c(2L, 3L), hosp_day, followup)
  )

  data$competing_time_28d   <- as.numeric(time)
  data$competing_status_28d <- as.integer(status)
  data$competing_primary_event <- pipeline_competing_primary_event(
    data$competing_status_28d,
    cr$primary_cause %||% 1L
  )
  data$hba1c_day <- NULL

  cli::cli_alert_success(sprintf(
    "data_clean: 已衍生 competing_time_28d / competing_status_28d（HbA1c\u2265%.1f%%，%d天窗口；status 0/1/2/3 = %d/%d/%d/%d）",
    threshold, followup,
    sum(status == 0L, na.rm = TRUE), sum(status == 1L, na.rm = TRUE),
    sum(status == 2L, na.rm = TRUE), sum(status == 3L, na.rm = TRUE)
  ))
  data
}

#' 28天 AKI 竞争风险结局衍生（缺血性脑卒中 × 肌酐 KDIGO 简化）
#'
#' status = 0  右删失；1 = 首次 AKI；2 = 达标前死亡；3 = 达标前出院
#' AKI：相对 day1 基线 Cr，在 d=2..followup 首次满足
#'   Cr >= baseline + delta_abs  或  Cr >= baseline * ratio
#' 默认 delta_abs=0.3 mg/dL，ratio=1.5（KDIGO stage1 简化）
pipeline_derive_competing_aki_28d <- function(data, cfg) {
  if (is.null(data) || !is.data.frame(data)) return(data)
  dc <- cfg$data_clean %||% list()
  if (!isTRUE(dc$derive_competing_aki_28d %||% FALSE)) return(data)

  cr <- cfg$competing_risk %||% list()
  id_col <- as.character((cfg$data %||% list())$id_column %||% "subject_id")[1L]
  need <- c(id_col, "hosp_day", "is_hosp_dead")
  miss <- setdiff(need, names(data))
  if (length(miss)) {
    stop(
      "data_clean: derive_competing_aki_28d 需要列 ", paste(need, collapse = ", "),
      "；缺失: ", paste(miss, collapse = ", "), call. = FALSE
    )
  }
  lab_path <- cr$aki_lab_csv_path %||% cr$hba1c_lab_csv_path %||% NULL
  if (is.null(lab_path) || !nzchar(lab_path) || !file.exists(lab_path)) {
    stop(
      "data_clean: derive_competing_aki_28d 需要 config$competing_risk$aki_lab_csv_path（存在的 CSV 路径）",
      call. = FALSE
    )
  }
  if (!requireNamespace("data.table", quietly = TRUE)) {
    stop("derive_competing_aki_28d 需要 data.table 包", call. = FALSE)
  }

  followup   <- as.integer(cr$followup_days %||% 28L)[1L]
  delta_abs  <- as.numeric(cr$aki_delta_abs %||% 0.3)[1L]
  ratio      <- as.numeric(cr$aki_ratio %||% 1.5)[1L]
  lab_id_col <- as.character(cr$aki_lab_id_column %||% cr$hba1c_lab_id_column %||% id_col)[1L]
  lab_prefix <- as.character(cr$aki_lab_prefix %||% "labcreatinine")[1L]
  baseline_day <- as.integer(cr$aki_baseline_day %||% 1L)[1L]

  header    <- names(data.table::fread(lab_path, nrows = 0L))
  want_cols <- paste0("lab", seq_len(followup), "_", lab_prefix)
  cre_cols  <- intersect(want_cols, header)
  if (!length(cre_cols)) {
    stop("derive_competing_aki_28d: CSV 中找不到任何 lab{d}_", lab_prefix, " 列: ", lab_path, call. = FALSE)
  }
  select_cols <- unique(c(lab_id_col, cre_cols))
  lab <- data.table::fread(lab_path, select = select_cols)
  lab[[lab_id_col]] <- as.character(lab[[lab_id_col]])

  keep_ids <- unique(as.character(data[[id_col]]))
  lab <- lab[lab[[lab_id_col]] %in% keep_ids]
  if (anyDuplicated(lab[[lab_id_col]])) lab <- lab[!duplicated(lab[[lab_id_col]])]

  day_mat <- suppressWarnings(as.matrix(lab[, cre_cols, with = FALSE]))
  storage.mode(day_mat) <- "double"
  day_num <- as.integer(sub(paste0("^lab(\\d+)_", lab_prefix, "$"), "\\1", cre_cols))
  base_idx <- match(baseline_day, day_num)
  if (is.na(base_idx)) {
    stop("derive_competing_aki_28d: 找不到基线日 lab", baseline_day, "_", lab_prefix, call. = FALSE)
  }
  baseline <- as.numeric(day_mat[, base_idx])

  aki_day <- vapply(seq_len(nrow(day_mat)), function(i) {
    b <- baseline[i]
    if (!is.finite(b) || b <= 0) return(NA_integer_)
    for (j in seq_along(day_num)) {
      d <- day_num[j]
      if (d <= baseline_day) next
      v <- day_mat[i, j]
      if (!is.finite(v)) next
      if (v >= b + delta_abs || v >= b * ratio) return(as.integer(d))
    }
    NA_integer_
  }, integer(1))

  outcome_df <- data.frame(
    id_tmp = as.character(lab[[lab_id_col]]),
    aki_day = aki_day,
    stringsAsFactors = FALSE
  )
  names(outcome_df)[1] <- id_col

  data[[id_col]] <- as.character(data[[id_col]])
  n_before <- nrow(data)
  data <- merge(data, outcome_df, by = id_col, all.x = TRUE, sort = FALSE)
  if (nrow(data) != n_before) {
    stop("derive_competing_aki_28d: 合并后行数变化（存在重复 ID），请检查数据", call. = FALSE)
  }

  hosp_day <- suppressWarnings(as.numeric(data$hosp_day))
  is_dead  <- suppressWarnings(as.numeric(data$is_hosp_dead))
  terminal_in_window <- is.finite(hosp_day) & hosp_day <= followup
  # discharge_as_censor=TRUE：出院为删失(0)，仅死亡为竞争(2)；默认仍写出院=3（兼容旧课题）
  if (isTRUE(cr$discharge_as_censor %||% FALSE)) {
    terminal_status <- ifelse(is_dead == 1, 2L, 0L)
  } else {
    terminal_status <- ifelse(is_dead == 1, 2L, 3L)
  }

  aki_day_v <- data$aki_day
  aki_ok <- is.finite(aki_day_v) & aki_day_v <= followup

  status <- ifelse(
    aki_ok & (!terminal_in_window | aki_day_v <= hosp_day), 1L,
    ifelse(terminal_in_window, terminal_status, 0L)
  )
  if (isTRUE(cr$discharge_as_censor %||% FALSE)) {
    time <- ifelse(
      status == 1L, aki_day_v,
      ifelse(
        status == 2L, hosp_day,
        ifelse(terminal_in_window & !(is_dead == 1), hosp_day, followup)
      )
    )
  } else {
    time <- ifelse(
      status == 1L, aki_day_v,
      ifelse(status %in% c(2L, 3L), hosp_day, followup)
    )
  }

  data$competing_time_28d   <- as.numeric(time)
  data$competing_status_28d <- as.integer(status)
  data$competing_primary_event <- pipeline_competing_primary_event(
    data$competing_status_28d,
    cr$primary_cause %||% 1L
  )
  data$aki_day <- NULL

  cli::cli_alert_success(sprintf(
    "data_clean: 已衍生 competing_time_28d / competing_status_28d（AKI: Cr\u2265基线+%.2f \u6216 \u00d7%.2f，%d\u5929\u7a97\u53e3\uff1bstatus 0/1/2/3 = %d/%d/%d/%d）",
    delta_abs, ratio, followup,
    sum(status == 0L, na.rm = TRUE), sum(status == 1L, na.rm = TRUE),
    sum(status == 2L, na.rm = TRUE), sum(status == 3L, na.rm = TRUE)
  ))
  data
}

pipeline_data_clean_enforce_min_n <- function(data, cfg, stage = "cohort") {
  if (is.null(data) || !is.data.frame(data)) return(invisible(NULL))
  dc <- cfg$data_clean %||% list()
  min_n <- suppressWarnings(as.integer(dc$min_n_after_cohort %||% dc$min_n %||% 0L)[1L])
  if (!is.finite(min_n) || min_n <= 0L) return(invisible(NULL))
  n <- nrow(data)
  if (n <= min_n) {
    stop(
      "COHORT_MIN_N_STOP: ", stage, " 后样本量 ", n,
      " ≤ 阈值 ", min_n, "，按 config$data_clean$min_n_after_cohort 终止 pipeline。",
      call. = FALSE
    )
  }
  invisible(NULL)
}

pipeline_resolve_index_var <- function(cfg) {
  as.character(
    (cfg$survival %||% list())$index_var %||%
      (cfg$incidence %||% list())$index_var %||%
      (cfg$logistic %||% list())$index_var %||%
      (cfg$project %||% list())$index_var %||% NA_character_
  )[1L]
}

pipeline_check_index_regression_significant <- function(ctx, cfg, coef_df, tb_sig,
                                                        block_name, p_threshold) {
  bl_key <- switch(block_name,
    univariate_prognosis = "univariate_prognosis",
    multivariate_prognosis = "multivariate_prognosis",
    block_name
  )
  bl_cfg <- (cfg[[bl_key]] %||% list())
  fail_on <- isTRUE(bl_cfg$fail_on_index_ns %||% FALSE)
  if (!fail_on && !isTRUE(bl_cfg$pause_enable %||% FALSE)) return(invisible(NULL))
  index_var <- pipeline_resolve_index_var(cfg)
  if (is.na(index_var) || !nzchar(index_var)) return(invisible(NULL))
  in_tb <- index_var %in% as.character(tb_sig)
  idx_p <- NA_real_
  if (!is.null(coef_df) && is.data.frame(coef_df) && nrow(coef_df) > 0L &&
      all(c("Variable", "P") %in% names(coef_df))) {
    hit <- coef_df$Variable == index_var |
      grepl(paste0("^", index_var, "($|[0-9])"), coef_df$Variable)
    if (any(hit, na.rm = TRUE)) {
      idx_p <- suppressWarnings(min(as.numeric(coef_df$P[hit]), na.rm = TRUE))
    }
  }
  if (in_tb && (is.na(idx_p) || idx_p < p_threshold)) return(invisible(NULL))
  msg <- paste0(
    "INDEX_REGRESSION_NS_STOP: 暴露指标 ", index_var,
    if (is.finite(idx_p)) paste0(" P = ", format(round(idx_p, 4), scientific = FALSE)) else " 未进入显著变量集",
    " >= ", p_threshold, "（", block_name, "），终止 pipeline。"
  )
  if (isTRUE(bl_cfg$pause_enable %||% FALSE) && !fail_on) {
    ctx$results$pause_point <- list(
      block = block_name, reason = msg, suggestion = "检查暴露分布或放宽 sig_cutoff"
    )
    stop("PAUSE_FOR_USER_DECISION: ", msg, call. = FALSE)
  }
  stop(msg, call. = FALSE)
}

# 发病 batch 常用 outcome_column=Disease_Group；原始 dabiao 仅含 Disease 时复制并移除 Disease
pipeline_ensure_outcome_group_column <- function(data, cfg) {
  if (is.null(data) || !is.data.frame(data)) return(data)
  outcome_col <- as.character((cfg$data %||% list())$outcome_column %||% "Disease")[1L]
  if (!nzchar(outcome_col)) return(data)
  if (identical(outcome_col, "Disease_Group") && "Disease" %in% names(data)) {
    if (!"Disease_Group" %in% names(data)) {
      data[["Disease_Group"]] <- data[["Disease"]]
    }
    data[["Disease"]] <- NULL
    return(data)
  }
  if (!outcome_col %in% names(data) && identical(outcome_col, "Disease_Group") &&
      "Disease" %in% names(data)) {
    data[[outcome_col]] <- data[["Disease"]]
    data[["Disease"]] <- NULL
  }
  data
}

#' 插补前数值清洗：Inf/NaN → NA；SBP/DBP/PP 合理性检查与 PP 回填
pipeline_sanitize_numeric_for_mice <- function(data, cfg = list()) {
  if (is.null(data) || !is.data.frame(data)) {
    return(list(data = data, n_nonfinite = 0L, n_pp_filled = 0L))
  }
  dc <- cfg$data_clean %||% list()
  bp_cfg <- dc$bp_columns %||% list(
    sbp = c("SBP", "NBPS"),
    dbp = c("DBP", "NBPD"),
    pp  = c("PP")
  )
  sbp_col <- intersect(as.character(bp_cfg$sbp), names(data))[1L]
  dbp_col <- intersect(as.character(bp_cfg$dbp), names(data))[1L]
  pp_col  <- intersect(as.character(bp_cfg$pp), names(data))[1L]

  .has_bp_col <- function(col) {
    is.character(col) && length(col) == 1L && !is.na(col) && nzchar(col)
  }

  num_cols <- names(data)[vapply(data, is.numeric, logical(1L))]
  n_nonfinite <- 0L
  for (col in num_cols) {
    x <- data[[col]]
    bad <- is.nan(x) | is.infinite(x)
    if (any(bad, na.rm = TRUE)) {
      n_nonfinite <- n_nonfinite + sum(bad, na.rm = TRUE)
      x[bad] <- NA_real_
      data[[col]] <- x
    }
  }

  n_pp_filled <- 0L
  if (.has_bp_col(sbp_col) && .has_bp_col(dbp_col)) {
    sbp <- as.numeric(data[[sbp_col]])
    dbp <- as.numeric(data[[dbp_col]])
    sbp_min <- as.numeric(dc$bp_sbp_min %||% 50)
    sbp_max <- as.numeric(dc$bp_sbp_max %||% 280)
    dbp_min <- as.numeric(dc$bp_dbp_min %||% 30)
    dbp_max <- as.numeric(dc$bp_dbp_max %||% 180)
    bad_bp <- (is.finite(sbp) & (sbp < sbp_min | sbp > sbp_max)) |
      (is.finite(dbp) & (dbp < dbp_min | dbp > dbp_max)) |
      (is.finite(sbp) & is.finite(dbp) & dbp > sbp)
    if (any(bad_bp, na.rm = TRUE)) {
      n_nonfinite <- n_nonfinite + sum(bad_bp, na.rm = TRUE)
      sbp[bad_bp] <- NA_real_
      dbp[bad_bp] <- NA_real_
      data[[sbp_col]] <- sbp
      data[[dbp_col]] <- dbp
    }
    if (.has_bp_col(pp_col)) {
      pp <- as.numeric(data[[pp_col]])
      need_pp <- !is.finite(pp) & is.finite(sbp) & is.finite(dbp)
      if (any(need_pp, na.rm = TRUE)) {
        pp[need_pp] <- sbp[need_pp] - dbp[need_pp]
        n_pp_filled <- sum(need_pp, na.rm = TRUE)
      }
      bad_pp <- is.finite(pp) & (pp < 0 | pp > 200)
      if (any(bad_pp, na.rm = TRUE)) {
        n_nonfinite <- n_nonfinite + sum(bad_pp, na.rm = TRUE)
        pp[bad_pp] <- NA_real_
      }
      data[[pp_col]] <- pp
    }
  }

  list(data = data, n_nonfinite = n_nonfinite, n_pp_filled = n_pp_filled)
}

# 上游统计（单因素/VIF/多因素）：restrict_to_train=TRUE 且已划分 train_validation 时用训练集
pipeline_upstream_modeling_data <- function(ctx) {
  cfg <- ctx$config
  up <- cfg$upstream %||% list()
  fs <- cfg$feature_selection %||% list()
  restrict <- isTRUE(up$restrict_to_train %||% fs$restrict_to_train %||% FALSE)
  source_tag <- "imputed"

  data <- if (restrict && !is.null(ctx$data$train) && is.data.frame(ctx$data$train) &&
              nrow(ctx$data$train) > 0L) {
    source_tag <- "train"
    ctx$data$train
  } else {
    ctx$data$imputed %||% ctx$data$cleaned
  }

  if (is.null(data) || !is.data.frame(data)) {
    return(list(data = NULL, outcome_col = NA_character_, source = source_tag))
  }

  if (exists("pipeline_ensure_outcome_group_column", mode = "function")) {
    data <- pipeline_ensure_outcome_group_column(data, cfg)
  }
  if (exists("pipeline_relabel_binary_outcome_column", mode = "function")) {
    data <- pipeline_relabel_binary_outcome_column(data, cfg)
  }

  outcome_col <- as.character((cfg$data %||% list())$outcome_column %||% "Disease")[1L]
  study_type <- tolower(trimws(cfg$project$study_type %||% "incidence"))
  if (identical(study_type, "incidence")) {
    outcome_col <- as.character((cfg$incidence %||% list())$outcome_var %||% outcome_col)[1L]
  } else {
    outcome_col <- as.character((cfg$survival %||% list())$event_var %||% outcome_col)[1L]
  }

  if (restrict && identical(source_tag, "train") &&
      "Group" %in% names(data) && !outcome_col %in% names(data)) {
    data[[outcome_col]] <- data[["Group"]]
  }

  if (exists("pipeline_drop_mi_quality_cols", mode = "function")) {
    data <- pipeline_drop_mi_quality_cols(data, ctx)
  }

  if (restrict && identical(source_tag, "train")) {
    cli::cli_alert_info("upstream: 使用训练集 (n={nrow(data)})")
  }

  list(data = data, outcome_col = outcome_col, source = source_tag)
}

# 图/表展示：去掉下划线（空格替代）
pipeline_display_no_underscore <- function(x) {
  if (is.null(x)) return(x)
  if (is.data.frame(x)) {
    chr_cols <- vapply(x, function(col) is.character(col) || is.factor(col), logical(1L))
    if (any(chr_cols)) {
      for (cn in names(x)[chr_cols]) {
        x[[cn]] <- gsub("_", " ", as.character(x[[cn]]), fixed = TRUE)
      }
    }
    return(x)
  }
  gsub("_", " ", as.character(x), fixed = TRUE)
}

# 发表展示名：优先 label_map，否则去下划线（数据列名不变）
# label_map 例：c(diameter_cm = "Diameter, cm", energy_j = "Energy, J")
pipeline_display_label <- function(x, label_map = NULL) {
  x <- as.character(x)
  if (!length(x)) return(x)
  out <- x
  if (!is.null(label_map) && length(label_map)) {
    lab <- as.character(label_map)
    names(lab) <- names(label_map)
    hit <- x %in% names(lab)
    if (any(hit)) out[hit] <- unname(lab[x[hit]])
  }
  pipeline_display_no_underscore(out)
}

# 发表表 data.frame 清洗：Variable/feature 走字典；字符列与列名禁下划线
pipeline_scrub_pub_df <- function(df, label_map = NULL) {
  if (is.null(df) || !is.data.frame(df)) return(df)
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  for (cn in intersect(c("Variable", "feature", "Characteristic", "covariate", "term"), names(df))) {
    df[[cn]] <- pipeline_display_label(df[[cn]], label_map = label_map)
  }
  df <- pipeline_display_no_underscore(df)
  names(df) <- pipeline_display_no_underscore(names(df))
  df
}

# 脚注/说明文字禁下划线
pipeline_scrub_pub_text <- function(x) {
  if (is.null(x)) return(x)
  pipeline_display_no_underscore(as.character(x))
}

# SHAP waterfall：优先阳性且概率>阈值；否则阳性中最高概率（由 capability layer 覆盖增强）
pipeline_pick_shap_waterfall_row <- function(ctx, pred_prob, outcome01,
                                             prob_threshold = 0.75) {
  n <- length(outcome01)
  if (!length(pred_prob) || length(pred_prob) != n) {
    return(list(row_id = 1L, incidence = NA_real_, pred_prob = NA_real_,
                outcome01 = NA_integer_, met_threshold = FALSE, rule = "fallback_row1"))
  }
  ok <- !is.na(outcome01) & !is.na(pred_prob)
  incidence <- if (any(ok)) mean(outcome01[ok] == 1L) else NA_real_
  thr <- as.numeric(prob_threshold)[1L]
  if (!is.finite(thr)) thr <- 0.75
  hit <- which(ok & outcome01 == 1L & pred_prob > thr)
  if (length(hit)) {
    rid <- as.integer(hit[1L])
    return(list(row_id = rid, incidence = incidence, pred_prob = as.numeric(pred_prob[rid]),
                outcome01 = as.integer(outcome01[rid]), met_threshold = TRUE,
                rule = "case_and_prob_gt_threshold"))
  }
  hit2 <- which(ok & outcome01 == 1L)
  if (length(hit2)) {
    rid <- as.integer(hit2[which.max(pred_prob[hit2])])
    return(list(row_id = rid, incidence = incidence, pred_prob = as.numeric(pred_prob[rid]),
                outcome01 = as.integer(outcome01[rid]),
                met_threshold = isTRUE(pred_prob[rid] > thr),
                rule = "case_highest_prob"))
  }
  list(row_id = 1L, incidence = incidence,
       pred_prob = as.numeric(pred_prob[1L]), outcome01 = as.integer(outcome01[1L]),
       met_threshold = FALSE, rule = "fallback_row1")
}

# 特征选择建模数据：restrict_to_train=TRUE 且已划分 train_validation 时用训练集
feature_selection_modeling_data <- function(ctx) {
  cfg <- ctx$config
  fs <- cfg$feature_selection %||% list()
  restrict <- isTRUE(fs$restrict_to_train %||% FALSE)
  source_tag <- "imputed"

  data <- if (restrict && !is.null(ctx$data$train) && is.data.frame(ctx$data$train) &&
              nrow(ctx$data$train) > 0L) {
    source_tag <- "train"
    ctx$data$train
  } else {
    ctx$data$imputed %||% ctx$data$cleaned
  }

  if (is.null(data) || !is.data.frame(data)) {
    return(list(data = NULL, outcome_col = NA_character_, source = source_tag))
  }

  if (exists("pipeline_ensure_outcome_group_column", mode = "function")) {
    data <- pipeline_ensure_outcome_group_column(data, cfg)
  }
  if (exists("pipeline_relabel_binary_outcome_column", mode = "function")) {
    data <- pipeline_relabel_binary_outcome_column(data, cfg)
  }

  outcome_col <- as.character((cfg$data %||% list())$outcome_column %||% "Disease")[1L]
  study_type <- tolower(trimws(cfg$project$study_type %||% "incidence"))
  if (identical(study_type, "incidence")) {
    outcome_col <- as.character((cfg$incidence %||% list())$outcome_var %||% outcome_col)[1L]
  }

  if (restrict && identical(source_tag, "train") &&
      "Group" %in% names(data) && !outcome_col %in% names(data)) {
    data[[outcome_col]] <- data[["Group"]]
  }

  if (exists("pipeline_drop_mi_quality_cols", mode = "function")) {
    data <- pipeline_drop_mi_quality_cols(data, ctx)
  }

  if (restrict && identical(source_tag, "train")) {
    cli::cli_alert_info("feature_selection: 使用训练集 (n={nrow(data)})")
  }

  list(data = data, outcome_col = outcome_col, source = source_tag)
}

# 特征选择方法块内部子采样：已用 train_validation 划分时不再二次抽样
feature_selection_row_index_for_fit <- function(d0, y01, cfg, resolved) {
  fs <- cfg$feature_selection %||% list()
  if (isTRUE(fs$restrict_to_train %||% FALSE) && identical(resolved$source %||% "", "train")) {
    return(seq_len(nrow(d0)))
  }
  sp <- cfg$splitting %||% list()
  train_ratio <- as.numeric(sp$train_ratio %||% 0.7)[1L]
  stratify <- isTRUE(sp$stratify %||% TRUE)
  ok <- !is.na(y01)
  n <- sum(ok)
  if (n < 20L) {
    stop("feature_selection: 非缺失结局样本过少。", call. = FALSE)
  }
  idx <- which(ok)
  if (stratify) {
    yv <- y01[idx]
    i1 <- idx[yv == 1L]
    i0 <- idx[yv == 0L]
    n1 <- max(1L, floor(length(i1) * train_ratio))
    n0 <- max(1L, floor(length(i0) * train_ratio))
    c(sample(i1, n1), sample(i0, n0))
  } else {
    sample(idx, max(1L, floor(n * train_ratio)))
  }
}

pipeline_outcome_leak_columns <- function(cfg) {
  oc <- as.character((cfg$data %||% list())$outcome_column %||% "Disease")[1L]
  unique(c("Disease", "Disease_Group", oc)[nzchar(c("Disease", "Disease_Group", oc))])
}

pipeline_ensure_outcome_group_on_ctx <- function(ctx) {
  if (is.null(ctx) || !is.list(ctx) || is.null(ctx$config)) return(ctx)
  if (is.null(ctx$data)) ctx$data <- list()
  outcome_col <- as.character((ctx$config$data %||% list())$outcome_column %||% "Disease")[1L]
  ref_vec <- NULL
  ref_id <- NULL
  id_col <- as.character((ctx$config$data %||% list())$id_column %||% character(0))[1L]
  for (slot in c("raw", "cleaned", "mapped", "imputed")) {
    df <- ctx$data[[slot]]
    if (is.null(df) || !is.data.frame(df)) next
    if (outcome_col %in% names(df)) {
      ref_vec <- df[[outcome_col]]
      if (nzchar(id_col) && id_col %in% names(df)) ref_id <- df[[id_col]]
      break
    }
    if ("Disease" %in% names(df)) {
      ref_vec <- df[["Disease"]]
      if (nzchar(id_col) && id_col %in% names(df)) ref_id <- df[[id_col]]
      break
    }
  }
  for (slot in c("raw", "cleaned", "mapped", "imputed")) {
    df <- ctx$data[[slot]]
    if (!is.null(df) && is.data.frame(df)) {
      df <- pipeline_ensure_outcome_group_column(df, ctx$config)
      if (!outcome_col %in% names(df) && !is.null(ref_vec)) {
        if (!is.null(ref_id) && nzchar(id_col) && id_col %in% names(df)) {
          idx <- match(df[[id_col]], ref_id)
          df[[outcome_col]] <- ref_vec[idx]
        } else if (length(ref_vec) == nrow(df)) {
          df[[outcome_col]] <- ref_vec
        }
      }
      if (exists("pipeline_relabel_binary_outcome_column", mode = "function")) {
        df <- pipeline_relabel_binary_outcome_column(df, ctx$config, col = outcome_col)
      }
      ctx$data[[slot]] <- df
    }
  }
  ctx
}

pipeline_patch_checkpoint_outcome_group <- function(ck_path, cfg) {
  if (is.null(ck_path) || !nzchar(ck_path) || !file.exists(ck_path)) {
    return(invisible(FALSE))
  }
  obj <- tryCatch(readRDS(ck_path), error = function(e) NULL)
  if (is.null(obj) || is.null(obj$ctx)) return(invisible(FALSE))
  obj$ctx <- pipeline_ensure_outcome_group_on_ctx(obj$ctx)
  if (!is.null(cfg)) obj$config <- cfg
  saveRDS(obj, ck_path)
  invisible(TRUE)
}

# ── 发病/双库：暴露指标 vs 协变量排除（单因素/多因素/VIF 可纳入 index；Model1/2 不含）──
pipeline_index_var_names <- function(cfg) {
  cfg <- cfg %||% list()
  # 无复合指标主链（用药 IPW unit=main）：不解析公式组分
  if (isTRUE((cfg$analysis_exclusion %||% list())$allow_no_index %||% FALSE)) {
    return(character(0))
  }
  inc <- cfg$incidence %||% list()
  harm <- (cfg$dual_db %||% list())$harmonization %||% list()
  idx <- as.character(
    (cfg$survival %||% list())$index_var %||%
      inc$index_var %||%
      (cfg$logistic %||% list())$index_var %||%
      character(0)
  )
  # 空向量 [1L] → NA；nzchar(NA)=TRUE（keepNA=FALSE）会误进公式解析
  idx <- idx[!is.na(idx) & nzchar(idx)]
  idx <- if (length(idx)) idx[[1L]] else ""
  comp <- as.character(
    inc$index_component_vars %||% harm$index_component_vars %||% character(0)
  )
  if (nzchar(idx)) comp <- unique(c(idx, comp))
  if (nzchar(idx) && exists("index_get_formula_components", mode = "function")) {
    comp <- unique(c(comp, index_get_formula_components(idx)))
  }
  unique(comp[!is.na(comp) & nzchar(comp)])
}

#' 批量/双库启动前加载指标公式解析（01block_index.R），供组分自动排除
pipeline_ensure_index_formula_helpers <- function(root) {
  root <- as.character(root %||% getwd())[1L]
  if (exists("index_get_formula_components", mode = "function") &&
      exists(".idx_definitions", mode = "function")) {
    return(invisible(TRUE))
  }
  idx_file <- file.path(root, "Blocks/00_index/01block_index.R")
  if (!file.exists(idx_file)) return(invisible(FALSE))
  source(idx_file, local = FALSE)
  invisible(exists("index_get_formula_components", mode = "function"))
}

#' 当前暴露指标的公式组分（不含暴露本身）
pipeline_index_component_vars_only <- function(cfg) {
  exposure <- pipeline_index_exposure_var(cfg)
  setdiff(pipeline_index_var_names(cfg), exposure)
}

# 当前暴露指标（单变量，如 SII / MCV）
pipeline_index_exposure_var <- function(cfg) {
  cfg <- cfg %||% list()
  active <- unique(c(
    as.character((cfg$survival %||% list())$index_var %||% character(0)),
    as.character((cfg$incidence %||% list())$index_var %||% character(0)),
    as.character((cfg$logistic %||% list())$index_var %||% character(0)),
    as.character((cfg$prediction %||% list())$index_vars %||% character(0))
  ))
  active <- active[nzchar(active)]
  if (length(active)) return(active[[1L]])
  character(0)
}

#' ML 建模是否纳入当前复合暴露指标（默认 TRUE；仍排除指标组分/foreign index）
pipeline_ml_include_composite_index <- function(cfg) {
  if (isTRUE((cfg$ml %||% list())$use_venn_center_features %||% FALSE)) return(FALSE)
  isTRUE((cfg$ml %||% list())$include_composite_index %||%
    (cfg$feature_selection %||% list())$include_composite_in_ml %||% TRUE)
}

#' ML 特征池：当前复合指标 + composite_features / prediction$index_vars
pipeline_ml_composite_feature_tags <- function(cfg) {
  fs <- cfg$feature_selection %||% list()
  pred <- cfg$prediction %||% list()
  tags <- unique(c(
    as.character(fs$composite_features %||% character(0)),
    as.character(pred$index_vars %||% character(0)),
    pipeline_index_exposure_var(cfg)
  ))
  tags[nzchar(tags)]
}

#' 将复合指标并入 ML 特征清单（feature_selection_final / ml_feature_names 等）
ensure_composite_in_ml_features <- function(ctx, db_tag = NULL) {
  cfg <- ctx$config
  if (!pipeline_ml_include_composite_index(cfg)) return(ctx)
  dat <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$train
  if (is.null(dat)) return(ctx)
  forced <- pipeline_ml_composite_feature_tags(cfg)
  present <- intersect(forced, names(dat))
  if (!length(present)) return(ctx)
  db_tag <- db_tag %||% cfg$project$database %||% "DB"
  added_any <- character(0)
  for (key in c("feature_selection_final", "Model2Factors", "ml_feature_names", "univar_features")) {
    old <- as.character(ctx$results[[key]] %||% character(0))
    new <- unique(c(old, present))
    added <- setdiff(present, old)
    if (length(added)) {
      ctx$results[[key]] <- new
      added_any <- unique(c(added_any, added))
    }
  }
  if (length(added_any)) {
    cli::cli_alert_info(
      "{db_tag}: ML 特征已并入复合指标: {paste(added_any, collapse = ', ')}"
    )
  }
  ctx
}

# VIF 设计矩阵排除：暴露组分（Age/HbA1c/Total_Cholesterol 等），保留暴露指标本身进 VIF 表
pipeline_index_vif_exclude_vars <- function(cfg) {
  idx <- pipeline_index_exposure_var(cfg)
  all <- pipeline_index_var_names(cfg)
  setdiff(unique(all[nzchar(all)]), as.character(idx))
}

# 单因素/多因素/VIF 分析池：排除 index_exclude_vars 中非当前 index 的列（index 本身仍参与分析）
pipeline_covariate_analysis_exclude_vars <- function(cfg) {
  cfg <- cfg %||% list()
  eb  <- cfg$environment_batch %||% list()
  if (isTRUE(eb$include_vocs_in_clinical_screen)) {
    return(character(0))
  }
  inc <- cfg$incidence %||% list()
  declared <- as.character(inc$index_exclude_vars %||% character(0))
  declared <- unique(declared[nzchar(declared)])
  if (!length(declared)) {
    return(pipeline_index_component_vars_only(cfg))
  }
  exposure <- pipeline_index_exposure_var(cfg)
  # 排除：当前指标组分 + 其它 batch 指标名；当前暴露本身仍可进单因素池
  unique(c(
    pipeline_index_component_vars_only(cfg),
    setdiff(declared, c(exposure, pipeline_index_component_vars_only(cfg)))
  ))
}

#' 调查周期/权重元数据列：保留在数据中供权重计算与周期对齐，但不得作为协变量或出现在发表表/图中
pipeline_survey_weight_metadata_cols <- function() {
  c("cycle", "Source_File", "SDDSRVYR")
}

pipeline_meta_exclude_cols <- function() {
  c(
    "ID", "SEQN", "subject_id", "stay_id", "hadm_id", "tst_patient_id",
    "icustay_id", "patientunitstayid", "Pt_ID", "Patient_ID",
    "admit_time", "disch_time", "icu_intime", "icu_outtime",
    "hosp_intime", "hosp_outtime", "charttime",
    "new_Weight", "new_weight",
    "WTINT2YR", "WTMEC2YR", "WTMEC4YR", "WTSA2YR", "WTSAF2YR", "WTSAF4YR",
    "WTINT4YR",
    "WTDRD1", "WTDR2D", "WTSOG2YR", "WTSB2YR", "WTSC2YR", "WTSVOC2YR", "WTSVOC2Y",
    "SDMVPSU", "SDMVSTRA", "Source_File", "SDDSRVYR"
  )
}

#' NHANES 调查设计/权重列：不得出现在 Table1/S3/VIF 等展示表（保留 wt_col 供 svyglm）
pipeline_nhanes_survey_design_exclude_cols <- function(var_names, cfg = NULL) {
  var_names <- as.character(var_names)
  nhanes_cfg <- if (!is.null(cfg)) (cfg$nhanes %||% list()) else list()
  wt_col  <- as.character(nhanes_cfg$survey_weight  %||% "new_Weight")[1L]
  psu_col <- as.character(nhanes_cfg$survey_cluster %||% "SDMVPSU")[1L]
  str_col <- as.character(nhanes_cfg$survey_strata  %||% "SDMVSTRA")[1L]
  extra_excl <- as.character(nhanes_cfg$exclude_cols %||% c(
    "WTINT2YR", "WTMEC2YR", "WTINT4YR", "WTMEC4YR", "WTSAF2YR", "WTSAF4YR",
    "WTDRD1", "WTDR2D", "WTSOG2YR", "WTSA2YR", "WTSB2YR", "WTSC2YR", "WTSVOC2YR"
  ))
  excl <- unique(c(
    wt_col, psu_col, str_col, extra_excl,
    if (exists("pipeline_meta_exclude_cols", mode = "function")) {
      pipeline_meta_exclude_cols()
    } else {
      character(0)
    }
  ))
  auto_wt <- grep("^(WT[A-Z]|SDMV|Source_File)", var_names, value = TRUE, ignore.case = TRUE)
  auto_wt <- setdiff(auto_wt, wt_col)
  unique(c(intersect(var_names, excl), auto_wt))
}

#' 强制纳入协变量（默认仅 Age；Gender 须显式 force_sex=TRUE）
#' 关闭年龄：force_age=FALSE；打开性别：force_sex=TRUE
pipeline_force_include_covariates <- function(cfg) {
  cfg <- cfg %||% list()
  pol <- cfg$covariate_policy %||% list()
  out <- as.character(pol$force_include %||% character(0))
  out <- out[nzchar(out)]
  if (!isFALSE(pol$force_age %||% TRUE)) {
    out <- unique(c("Age", "Age_Years", out))
  }
  # 默认不强制性别（与 UV→VIF→S7 链路一致）；显式开启后再消歧 Gender/Sex
  if (isTRUE(pol$force_sex)) {
    out <- unique(c(out, "Gender", "Sex", "gender", "sex"))
  }
  # 暴露公式成分不得强制进协变量（如 FIB4 含 Age：可 Table1/亚组，不可 Model1/2）
  if (exists("pipeline_covariate_analysis_exclude_vars", mode = "function")) {
    out <- setdiff(out, pipeline_covariate_analysis_exclude_vars(cfg))
  }
  out
}

#' 插补后：对指标做协变量残差化（如 FIB4 ~ Age → FIB4_AgeResid）
#'
#' config$index$residualize = list(
#'   enable = TRUE,
#'   source = "FIB4",
#'   adjust = "Age",          # 字符或字符向量
#'   name   = "FIB4_AgeResid",
#'   drop_source = FALSE      # TRUE 则删掉原始 source 列
#' )
pipeline_apply_index_residualize <- function(ctx, cfg = NULL) {
  cfg <- cfg %||% ctx$config %||% list()
  rs <- (cfg$index %||% list())$residualize %||% list()
  if (isFALSE(rs$enable %||% FALSE)) return(ctx)
  src <- as.character(rs$source %||% "")[1L]
  adj <- unique(as.character(rs$adjust %||% "Age"))
  adj <- adj[nzchar(adj)]
  out_nm <- as.character(rs$name %||% paste0(src, "_AgeResid"))[1L]
  if (!nzchar(src) || !nzchar(out_nm) || !length(adj)) {
    cli::cli_alert_warning("index$residualize 配置不完整，跳过残差化")
    return(ctx)
  }
  df <- ctx$data$imputed
  if (!is.data.frame(df) || !nrow(df)) {
    cli::cli_alert_warning("index$residualize: 无 imputed 数据，跳过")
    return(ctx)
  }
  need <- c(src, adj)
  miss <- setdiff(need, names(df))
  if (length(miss)) {
    stop(
      "index$residualize 缺列: ", paste(miss, collapse = ", "),
      "（须先算 source 指标且保留 adjust 列）",
      call. = FALSE
    )
  }
  y <- suppressWarnings(as.numeric(df[[src]]))
  X <- df[, adj, drop = FALSE]
  for (a in adj) X[[a]] <- suppressWarnings(as.numeric(X[[a]]))
  ok <- is.finite(y) & complete.cases(X)
  if (sum(ok) < 30L) {
    stop(
      "index$residualize: 可用于拟合的行太少 (n=", sum(ok), ")",
      call. = FALSE
    )
  }
  fit <- stats::lm(y ~ ., data = data.frame(y = y[ok], X[ok, , drop = FALSE]))
  resid_all <- rep(NA_real_, nrow(df))
  resid_all[ok] <- as.numeric(stats::residuals(fit))
  digits <- as.integer((cfg$index %||% list())$digits %||% 4L)[1L]
  if (is.finite(digits) && digits >= 0L) {
    resid_all <- round(resid_all, digits)
  }
  df[[out_nm]] <- resid_all
  if (isTRUE(rs$drop_source) && !identical(src, out_nm)) {
    df[[src]] <- NULL
  }
  ctx$data$imputed <- df
  # 同步其它常用槽，避免下游仍读旧 FIB4
  for (slot in c("mapped", "cleaned")) {
    if (!is.null(ctx$data[[slot]]) && is.data.frame(ctx$data[[slot]]) &&
        nrow(ctx$data[[slot]]) == nrow(df)) {
      ctx$data[[slot]][[out_nm]] <- resid_all
      if (isTRUE(rs$drop_source) && !identical(src, out_nm) &&
          src %in% names(ctx$data[[slot]])) {
        ctx$data[[slot]][[src]] <- NULL
      }
    }
  }
  ctx$results$index_residualize <- list(
    source = src, adjust = adj, name = out_nm,
    n_fit = as.integer(sum(ok)),
    r_squared = unname(summary(fit)$r.squared)
  )
  cli::cli_alert_success(
    "指标残差化: {out_nm} = resid({src} ~ {paste(adj, collapse=' + ')})；拟合 n={sum(ok)}, R2={round(summary(fit)$r.squared, 3)}"
  )
  ctx
}

#' 年龄/性别候选消歧：各只保留 1 列（优先 Age / Gender）
pipeline_dedupe_force_demo_vars <- function(force, data_cols = NULL) {
  force <- unique(as.character(force %||% character(0)))
  force <- force[nzchar(force)]
  if (!is.null(data_cols)) {
    force <- intersect(force, as.character(data_cols))
  }
  age_hits <- intersect(c("Age", "Age_Years"), force)
  if (length(age_hits) > 1L) {
    keep <- if ("Age" %in% age_hits) "Age" else age_hits[[1L]]
    force <- unique(c(setdiff(force, age_hits), keep))
  }
  sex_hits <- intersect(c("Gender", "Sex", "gender", "sex"), force)
  if (length(sex_hits) > 1L) {
    keep <- if ("Gender" %in% sex_hits) "Gender" else if ("Sex" %in% sex_hits) "Sex" else sex_hits[[1L]]
    force <- unique(c(setdiff(force, sex_hits), keep))
  }
  force
}

#' 数据列名（插补/清洗后主表）
pipeline_ctx_data_cols <- function(ctx) {
  if (is.null(ctx) || !is.list(ctx)) return(character(0))
  for (slot in c("imputed", "cleaned", "mapped", "raw")) {
    df <- ctx$data[[slot]]
    if (is.data.frame(df) && ncol(df) > 0L) return(names(df))
  }
  character(0)
}

#' 若数据有年龄且 Model1 尚未包含，则补进 Model1（并入 Model2）
#' 关闭：config$covariate_policy$force_age = FALSE
pipeline_ensure_age_in_model1 <- function(M1, M2, data_cols, cfg = NULL) {
  M1 <- unique(as.character(M1 %||% character(0)))
  M2 <- unique(as.character(M2 %||% character(0)))
  M1 <- M1[nzchar(M1)]
  M2 <- M2[nzchar(M2)]
  pol <- (cfg %||% list())$covariate_policy %||% list()
  if (isFALSE(pol$force_age %||% TRUE)) {
    return(list(M1 = M1, M2 = unique(c(M1, M2))))
  }
  data_cols <- as.character(data_cols %||% character(0))
  age_hits <- intersect(c("Age", "Age_Years"), data_cols)
  if (!length(age_hits)) {
    return(list(M1 = M1, M2 = unique(c(M1, M2))))
  }
  age_col <- if ("Age" %in% age_hits) "Age" else age_hits[[1L]]
  already <- any(tolower(c(M1, M2)) == tolower(age_col))
  in_m1 <- any(tolower(M1) == tolower(age_col))
  if (!in_m1) {
    M1 <- unique(c(age_col, M1))
  }
  if (!already || !in_m1) {
    M2 <- unique(c(M1, M2))
  } else {
    M2 <- unique(c(M1, M2))
  }
  list(M1 = M1, M2 = M2)
}

#' 多因素 VIF 无人口学、回退单因素人口学时：已有（或可补）Age 则不再强加 Marital 等
#'
#' UV 回退只保留 Age（默认）；仅 force_sex=TRUE 时再保留 Gender/Sex。
#' force_age=FALSE：不把单因素人口学全集塞进 Model1，只保留强制性别（若开启）。
#' 例外：强加 Age 在 Model1（暴露+Age）中不显著时，恢复全部单因素人口学。
#' 无 Age 列且 force_age 开启时保持原 UV 人口学全集（兜底 Model1 非空）。
pipeline_uv_demo_fallback_model1 <- function(uv_demos, data_cols, cfg = NULL,
                                            age_significant = NULL) {
  uv_demos <- unique(as.character(uv_demos %||% character(0)))
  uv_demos <- uv_demos[nzchar(uv_demos)]
  data_cols <- as.character(data_cols %||% character(0))
  pol <- (cfg %||% list())$covariate_policy %||% list()
  .keep_forced_sex <- function(pool) {
    if (!isTRUE(pol$force_sex)) return(character(0))
    sex <- intersect(c("Gender", "Sex", "gender", "sex"), pool)
    if (!length(sex)) return(character(0))
    if ("Gender" %in% sex) "Gender" else sex[[1L]]
  }
  # 关闭年龄强制：Model1 不强塞 UV 人口学全集；性别仅当 force_sex=TRUE
  if (isFALSE(pol$force_age %||% TRUE)) {
    keep <- .keep_forced_sex(uv_demos)
    return(list(M1 = keep, dropped = setdiff(uv_demos, keep)))
  }
  age_pool <- unique(c(uv_demos, data_cols))
  age_cols <- intersect(c("Age", "Age_Years"), age_pool)
  if ("Age" %in% age_cols) age_cols <- "Age"
  if (!length(age_cols)) {
    return(list(M1 = uv_demos, dropped = character(0)))
  }
  if (isFALSE(age_significant)) {
    return(list(M1 = uv_demos, dropped = character(0)))
  }
  keep <- age_cols
  sex_keep <- .keep_forced_sex(uv_demos)
  if (length(sex_keep)) keep <- unique(c(keep, sex_keep))
  dropped <- setdiff(uv_demos, keep)
  list(M1 = keep, dropped = dropped)
}

#' 强加进 Model1 的 Age 是否显著（y ~ 暴露 + Age；无暴露则 y ~ Age）
pipeline_forced_age_is_significant <- function(data, cfg = NULL, index_var = NULL,
                                              p_cutoff = NULL) {
  p_cutoff <- as.numeric(
    p_cutoff %||%
      (cfg$multivariate_incidence_binary %||% list())$sig_cutoff %||%
      (cfg$logistic %||% list())$p_threshold %||% 0.05
  )[1L]
  if (!is.finite(p_cutoff)) p_cutoff <- 0.05
  if (!is.data.frame(data) || !nrow(data)) return(NA)
  age_col <- if ("Age" %in% names(data)) "Age" else if ("Age_Years" %in% names(data)) {
    "Age_Years"
  } else {
    return(NA)
  }
  ycol <- as.character((cfg$data %||% list())$outcome_column %||% "Disease_Group")[1L]
  if (!nzchar(ycol) || !ycol %in% names(data)) {
    ycol <- if ("Disease_Group" %in% names(data)) "Disease_Group" else if ("Disease" %in% names(data)) {
      "Disease"
    } else {
      return(NA)
    }
  }
  y <- if (exists("pipeline_outcome_as_01", mode = "function")) {
    pipeline_outcome_as_01(data[[ycol]], cfg)
  } else {
    yy <- data[[ycol]]
    if (is.numeric(yy)) as.integer(yy > 0) else as.integer(as.factor(yy)) - 1L
  }
  age <- suppressWarnings(as.numeric(data[[age_col]]))
  ok <- !is.na(y) & is.finite(age)
  df <- data.frame(y = as.numeric(y), stringsAsFactors = FALSE)
  df[[age_col]] <- age
  rhs <- age_col
  idx <- as.character(
    index_var %||%
      (if (exists("pipeline_index_exposure_var", mode = "function")) {
        pipeline_index_exposure_var(cfg)
      } else {
        character(0)
      }) %||% ""
  )[1L]
  if (nzchar(idx) && idx %in% names(data) && !identical(idx, age_col)) {
    xv <- suppressWarnings(as.numeric(data[[idx]]))
    if (any(is.finite(xv))) {
      df[[idx]] <- xv
      ok <- ok & is.finite(xv)
      rhs <- paste(idx, age_col, sep = " + ")
    }
  }
  df <- df[ok, , drop = FALSE]
  if (nrow(df) < 20L || length(unique(df$y)) < 2L) return(NA)
  fit <- tryCatch(
    stats::glm(
      stats::as.formula(paste("y ~", rhs)),
      data = df,
      family = stats::binomial()
    ),
    error = function(e) NULL
  )
  if (is.null(fit)) return(NA)
  s <- tryCatch(summary(fit)$coefficients, error = function(e) NULL)
  if (is.null(s) || !nrow(s)) return(NA)
  rn <- rownames(s)
  hit <- intersect(c(age_col, paste0(age_col, "1")), rn)
  if (!length(hit)) {
    hit <- rn[grepl(paste0("^", age_col), rn)]
  }
  if (!length(hit)) return(NA)
  pcol <- intersect(c("Pr(>|z|)", "Pr(>|t|)"), colnames(s))
  if (!length(pcol)) return(NA)
  p <- suppressWarnings(as.numeric(s[hit[[1L]], pcol[[1L]]]))
  if (!is.finite(p)) return(NA)
  isTRUE(p < p_cutoff)
}

#' 把强制协变量并入 Model1/Model2（仅保留数据中存在的列）
pipeline_merge_force_covariates <- function(M1, M2, data_cols, cfg) {
  data_cols <- as.character(data_cols %||% character(0))
  force <- pipeline_dedupe_force_demo_vars(
    pipeline_force_include_covariates(cfg), data_cols
  )
  if (!length(force)) {
    return(list(M1 = as.character(M1 %||% character(0)), M2 = as.character(M2 %||% character(0))))
  }
  M2 <- unique(c(as.character(M2 %||% character(0)), force))
  # 强制集进 Model1：
  # - 默认 force 仅含 Age → Model1=Age
  # - 若 force_sex=TRUE 且 force_sex_to_model1=TRUE，Gender 也可进 Model1
  # - force_sex_to_model1=FALSE：仅 Age 进 Model1，Gender 只留 Model2
  pol <- cfg$covariate_policy %||% list()
  if (isFALSE(pol$force_sex_to_model1 %||% TRUE)) {
    force_m1 <- force[vapply(force, function(v) {
      grepl("Age", v, ignore.case = TRUE)
    }, logical(1L))]
  } else {
    demo_kw <- c("Age", "Gender", "Sex", "Race", "Ethnic")
    force_m1 <- force[vapply(force, function(v) {
      any(grepl(paste(demo_kw, collapse = "|"), v, ignore.case = TRUE))
    }, logical(1L))]
  }
  M1 <- unique(c(as.character(M1 %||% character(0)), force_m1))
  # Model1 必须 ⊆ Model2
  M2 <- unique(c(M1, M2))
  if (exists("pipeline_ensure_age_in_model1", mode = "function")) {
    return(pipeline_ensure_age_in_model1(M1, M2, data_cols, cfg))
  }
  list(M1 = M1, M2 = M2)
}

#' 中介路径是否使用协变量（默认 FALSE = crude，全项目生效）
#' 显式开启：config$mediation_policy$path_use_covariates = TRUE
#' 或单块 config$mediation_*$path_use_covariates = TRUE
pipeline_mediation_path_use_covariates <- function(cfg, block_cfg = NULL) {
  blk <- block_cfg %||% list()
  if (!is.null(blk$path_use_covariates)) return(isTRUE(blk$path_use_covariates))
  if (!is.null(blk$use_path_covariates)) return(isTRUE(blk$use_path_covariates))
  pol <- (cfg %||% list())$mediation_policy %||% list()
  isTRUE(pol$path_use_covariates %||% FALSE)
}

#' 中介路径协变量来源（默认 table2 = 与主文 Table 2 / 锁定多因素同套）
pipeline_mediation_covariate_source <- function(cfg, block_cfg = NULL) {
  blk <- block_cfg %||% list()
  src <- as.character(blk$covariate_source %||% "")[1L]
  if (!nzchar(src)) {
    pol <- (cfg %||% list())$mediation_policy %||% list()
    src <- as.character(pol$covariate_source %||% "table2")[1L]
  }
  src
}

#' 从 ctx 解析 Table 2 锁定协变量（logistic_final / cox_final / locked 链）
.pipeline_mediation_table2_covariates <- function(ctx, cfg, data_cols) {
  if (!is.null(ctx) && exists("locked_multivariable_covariates", mode = "function")) {
    lk <- tryCatch(
      locked_multivariable_covariates(ctx, cfg %||% ctx$config),
      error = function(e) NULL
    )
    if (!is.null(lk) && length(lk$covariates)) {
      return(as.character(lk$covariates))
    }
  }
  if (!is.null(ctx)) {
    res <- ctx$results %||% list()
    covs <- unique(c(
      as.character(res$logistic_final_factors %||% character(0)),
      as.character(res$cox_final_factors %||% character(0)),
      as.character(res$nhanes_logistic_M2 %||% character(0)),
      as.character(res$Model2Factors %||% character(0)),
      as.character(res$vif_final_pass %||% character(0))
    ))
    covs <- covs[nzchar(covs)]
    if (length(covs)) return(covs)
  }
  character(0)
}

#' 解析中介路径协变量：path_use_covariates=TRUE 时启用。
#' 默认 covariate_source=table2（与 Table 2 锁定集同套）；仅显式 config 才用 block$covariates。
pipeline_mediation_resolve_path_covariates <- function(cfg, block_cfg, data_cols,
                                                       ctx = NULL) {
  if (!pipeline_mediation_path_use_covariates(cfg, block_cfg)) {
    return(character(0))
  }
  src <- tolower(trimws(pipeline_mediation_covariate_source(cfg, block_cfg)))
  if (src %in% c("none", "crude", "null")) {
    return(character(0))
  }
  covs <- if (identical(src, "config")) {
    as.character((block_cfg %||% list())$covariates %||% character(0))
  } else if (identical(src, "model1")) {
  # 中介路径仅调 Model1（人口学/基线），避免 ICU 严重度等阻断间接效应
    if (!is.null(ctx)) {
      unique(as.character(
        ctx$results$Model1Factors %||%
          ctx$results$model1_incidence %||%
          ctx$results$cox_model1_covariates %||%
          character(0)
      ))
    } else {
      character(0)
    }
  } else {
    # table2（默认）：与主文 Table 2 / S7 锁定多因素同套
    .pipeline_mediation_table2_covariates(ctx, cfg, data_cols)
  }
  covs <- covs[nzchar(covs)]
  # 勿把暴露本身留在协变量里
  ix <- as.character(
    (cfg %||% list())$incidence$index_var %||%
      (cfg %||% list())$logistic$index_var %||%
      (cfg %||% list())$survival$index_var %||%
      ""
  )[1L]
  if (!nzchar(ix) && !is.null(ctx) && exists("pipeline_index_exposure_var", mode = "function")) {
    ix <- as.character(pipeline_index_exposure_var(cfg %||% ctx$config) %||% "")[1L]
  }
  if (nzchar(ix)) covs <- setdiff(covs, ix)
  intersect(unique(covs), as.character(data_cols %||% character(0)))
}

#' 路径协变量不得含候选中介（否则如 Lactate 既调又中介 → Proportion mediated≈0）
pipeline_mediation_drop_mediators_from_covariates <- function(covariates, mediators,
                                                             label = NULL) {
  covariates <- unique(as.character(covariates %||% character(0)))
  covariates <- covariates[nzchar(covariates)]
  mediators <- unique(as.character(mediators %||% character(0)))
  mediators <- mediators[nzchar(mediators)]
  hit <- intersect(covariates, mediators)
  if (length(hit) && requireNamespace("cli", quietly = TRUE)) {
    lbl <- as.character(label %||% "")[1L]
    prefix <- if (nzchar(lbl)) paste0(lbl, ": ") else ""
    cli::cli_alert_info(
      "{prefix}路径协变量已剔除候选中介: {paste(hit, collapse = ', ')}"
    )
  }
  setdiff(covariates, mediators)
}

#' 是否允许为刷显著而搜索协变量（默认关；且须先开启 path_use_covariates）
pipeline_mediation_auto_covariate_search <- function(cfg, block_cfg = NULL) {
  if (!pipeline_mediation_path_use_covariates(cfg, block_cfg)) return(FALSE)
  isTRUE((block_cfg %||% list())$auto_covariate_search %||% FALSE)
}

#' 解析中介自动协变量搜索的候选池
#'
#' - 显式 `covariate_search_pool` 优先
#' - `covariate_search_pool_source = "vif_screen"|"all"`：单因素 VIF screen 通过变量（更广）
#' - 默认：`Model2Factors`（与 Table 2 锁定池一致）
pipeline_mediation_covariate_search_pool <- function(ctx, cfg, block_cfg = NULL,
                                                     default_pool = character(0)) {
  bl <- block_cfg %||% list()
  explicit <- as.character(bl$covariate_search_pool %||% character(0))
  explicit <- explicit[nzchar(explicit)]
  if (length(explicit)) return(unique(explicit))

  src <- tolower(trimws(as.character(
    bl$covariate_search_pool_source %||% "model2"
  )[1L]))
  if (src %in% c("vif_screen", "screen", "all", "all_screen")) {
    pool <- as.character(
      ctx$results$vif_screen_pass %||%
        ctx$results$vif_screen_pass_weighted %||%
        ctx$results$tb_screen %||%
        ctx$results$tb1 %||%
        character(0)
    )
    pool <- unique(pool[nzchar(pool)])
    # 续跑时 ctx 可能丢 screen pass：从产出目录 VIF_check_screen*.csv 回填
    if (!length(pool)) {
      od <- as.character(ctx$output_dir %||% "")[1L]
      roots <- unique(c(
        od,
        dirname(od),
        file.path(dirname(dirname(od %||% ".")), "NHANES"),
        file.path(dirname(dirname(od %||% ".")), "MIMIC")
      ))
      csvs <- unlist(lapply(roots, function(r) {
        if (!nzchar(r) || !dir.exists(r)) return(character(0))
        list.files(
          r, pattern = "^VIF_check_screen.*\\.csv$",
          recursive = TRUE, full.names = TRUE, ignore.case = TRUE
        )
      }), use.names = FALSE)
      for (f in csvs) {
        d <- tryCatch(utils::read.csv(f, stringsAsFactors = FALSE), error = function(e) NULL)
        if (is.null(d) || !nrow(d)) next
        col <- if ("Variable" %in% names(d)) "Variable" else if ("Variable_display" %in% names(d)) {
          "Variable_display"
        } else {
          names(d)[1L]
        }
        vv <- as.character(d[[col]])
        vv <- gsub(" ", "_", vv, fixed = TRUE)
        pool <- unique(c(pool, vv[nzchar(vv)]))
      }
    }
    if (length(pool)) return(pool)
  }
  pool <- as.character(default_pool %||% character(0))
  if (!length(pool)) {
    pool <- as.character(ctx$results$Model2Factors %||% character(0))
  }
  unique(pool[nzchar(pool)])
}

#' 中介血检候选须排除：暴露本身 + 公式组分 + 其它复合指标名 + 暴露衍生列
#' （全项目通用：暴露=BAR 时不得以 BUN/Albumin 等组分作中介；其它指标同理）
pipeline_mediation_lab_exclude_vars <- function(cfg, data_cols = NULL) {
  cfg <- cfg %||% list()
  eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  roots <- unique(c(
    eng,
    as.character((cfg$project %||% list())$root %||% ""),
    getwd()
  ))
  roots <- roots[nzchar(roots)]
  if (exists("pipeline_ensure_index_formula_helpers", mode = "function")) {
    for (r in roots) {
      if (pipeline_ensure_index_formula_helpers(r)) break
    }
  }
  exposure <- pipeline_index_exposure_var(cfg)
  # 暴露 + 公式组分（如 BAR → BUN, Albumin）
  idx_names <- tryCatch(pipeline_index_var_names(cfg), error = function(e) character(0))
  comps <- tryCatch(pipeline_index_component_vars_only(cfg), error = function(e) character(0))
  extra_comp <- character(0)
  if (nzchar(as.character(exposure %||% "")[1L]) &&
      exists("index_get_formula_components", mode = "function")) {
    extra_comp <- tryCatch(
      as.character(index_get_formula_components(exposure) %||% character(0)),
      error = function(e) character(0)
    )
  }
  # 其它已加载的复合指标名（不可把 SII 等当作 BAR 的中介）
  all_ix <- character(0)
  if (exists(".composite_index_vars", mode = "function")) {
    all_ix <- tryCatch(as.character(.composite_index_vars() %||% character(0)),
                       error = function(e) character(0))
  }
  if (exists(".composite_index_vars_all", inherits = TRUE)) {
    all_ix <- unique(c(all_ix, as.character(.composite_index_vars_all %||% character(0))))
  }
  # composite_index_vars.R 全局向量兜底
  for (nm in c(".composite_index_vars_all", ".composite_index_vars_dual_safe",
               "composite_index_vars")) {
    if (exists(nm, inherits = TRUE)) {
      all_ix <- unique(c(all_ix, as.character(get(nm, inherits = TRUE) %||% character(0))))
    }
  }

  excl <- unique(c(
    as.character(exposure %||% character(0)),
    idx_names,
    comps,
    extra_comp,
    all_ix,
    as.character((cfg$incidence %||% list())$index_exclude_vars %||% character(0)),
    as.character((cfg$mediation_policy %||% list())$exclude_mediators %||% character(0)),
    as.character((cfg$mediation_prognosis %||% list())$exclude_mediators %||% character(0)),
    as.character((cfg$mediation_incidence %||% list())$exclude_mediators %||% character(0)),
    pipeline_meta_exclude_cols(),
    pipeline_survey_weight_metadata_cols()
  ))
  excl <- excl[!is.na(excl) & nzchar(excl)]

  # 暴露衍生列：BAR_quartile / BAR_tertile / BAR_Group 等
  if (nzchar(as.character(exposure %||% "")[1L]) && !is.null(data_cols)) {
    data_cols <- as.character(data_cols)
    exp0 <- as.character(exposure)[1L]
    der <- data_cols[
      data_cols == exp0 |
        startsWith(data_cols, paste0(exp0, "_")) |
        grepl(paste0("^", exp0, "($|[_\\.]|Q|Group|cut)"), data_cols, ignore.case = TRUE)
    ]
    excl <- unique(c(excl, der))
  }

  excl
}

#' 从中介候选中剔除暴露/组分/复合指标；返回清洗后向量
pipeline_mediation_filter_mediators <- function(mediators, cfg, data_cols = NULL, label = "中介") {
  mediators <- unique(as.character(mediators %||% character(0)))
  mediators <- mediators[nzchar(mediators)]
  if (!length(mediators)) return(character(0))
  excl <- pipeline_mediation_lab_exclude_vars(cfg, data_cols = data_cols %||% mediators)
  drop <- intersect(mediators, excl)
  # 不区分大小写再打一轮
  if (length(mediators) && length(excl)) {
    drop_ci <- mediators[tolower(mediators) %in% tolower(excl)]
    drop <- unique(c(drop, drop_ci))
  }
  if (length(drop)) {
    cli::cli_alert_info(
      "{label}候选已剔除暴露组分/复合指标: {paste(drop, collapse = ', ')}"
    )
  }
  setdiff(mediators, drop)
}

# 批量/双库：根据当前 index_var 写回 index_exclude_vars；Model 排除 index+extra，UV/MV/VIF 仅排除 extra
pipeline_apply_index_exclude_patch <- function(cfg, extra_covariate_vars = character(0)) {
  cfg <- cfg %||% list()
  idx_names <- pipeline_index_var_names(cfg)
  extra_src <- unique(as.character(extra_covariate_vars %||% character(0)))
  extra_src <- extra_src[nzchar(extra_src)]
  exposure <- pipeline_index_exposure_var(cfg)
  components <- pipeline_index_component_vars_only(cfg)
  extra <- setdiff(extra_src, idx_names)
  meta_excl <- pipeline_meta_exclude_cols()
  force_cov <- pipeline_force_include_covariates(cfg)

  cfg$incidence <- cfg$incidence %||% list()
  cfg$incidence$index_exclude_vars <- unique(c(idx_names, extra))

  cov_excl <- unique(c(
    components,
    extra,
    intersect(extra_src, meta_excl)
  ))
  cov_excl <- setdiff(cov_excl, c(exposure, force_cov))
  model_excl <- unique(c(idx_names, extra))

  mc <- cfg$multicollinearity %||% list()
  cfg$multicollinearity <- mc
  cfg$multicollinearity$exclude_vars <- setdiff(unique(c(
    as.character(mc$exclude_vars %||% character(0)),
    intersect(extra_src, meta_excl),
    extra
  )), idx_names)

  for (blk in c(
    "univariate_nhanes", "univariate_incidence_binary",
    "multivariate_nhanes", "multivariate_incidence_binary",
    "multivariate_incidence_harmonized"
  )) {
    if (!is.null(cfg[[blk]])) {
      prev <- setdiff(
        as.character(cfg[[blk]]$excluded_predictors %||% character(0)),
        idx_names
      )
      cfg[[blk]]$excluded_predictors <- unique(c(prev, cov_excl))
      # 强制 Age 等进入 required_predictors（不显著也保留）
      req <- as.character(cfg[[blk]]$required_predictors %||% character(0))
      cfg[[blk]]$required_predictors <- unique(c(req, force_cov))
    }
  }
  if (!is.null(cfg$logistic_nhanes_weighted)) {
    cfg$logistic_nhanes_weighted$exclude_from_models <- unique(c(
      as.character(cfg$logistic_nhanes_weighted$exclude_from_models %||% character(0)),
      model_excl
    ))
  }
  cfg
}

pipeline_uv_excluded_predictors <- function(cfg) {
  pipeline_covariate_analysis_exclude_vars(cfg)
}

# Model1/Model2 / logistic 协变量池：暴露及其组分 + 额外排除列
pipeline_model_factor_exclude_vars <- function(cfg) {
  unique(c(
    pipeline_index_var_names(cfg),
    pipeline_covariate_analysis_exclude_vars(cfg),
    pipeline_survey_weight_metadata_cols()
  )[nzchar(c(
    pipeline_index_var_names(cfg),
    pipeline_covariate_analysis_exclude_vars(cfg),
    pipeline_survey_weight_metadata_cols()
  ))])
}

pipeline_strip_index_from_model_factors <- function(M1, M2, cfg) {
  excl <- pipeline_model_factor_exclude_vars(cfg)
  # 强制协变量（Age）不得被指标组分排除逻辑误删
  force <- pipeline_force_include_covariates(cfg)
  excl <- setdiff(excl, force)
  list(
    M1 = setdiff(as.character(M1 %||% character(0)), excl),
    M2 = setdiff(as.character(M2 %||% character(0)), excl)
  )
}

# 兼容旧名：logistic / 随机搜索等仍调用此函数 → 仅用于 Model 协变量排除
pipeline_index_exclude_vars <- function(cfg) {
  pipeline_model_factor_exclude_vars(cfg)
}

# ── Model2：排除指标相关协变量，并限制总协变量数（含 Model1 人口学）──────────
logistic_constrain_model_factors <- function(M1, M2, cfg, index_var = NULL) {
  cfg <- cfg %||% list()
  M1 <- unique(as.character(M1)[nzchar(as.character(M1))])
  M2 <- unique(as.character(M2)[nzchar(as.character(M2))])
  index_var <- as.character(index_var %||% (cfg$incidence %||% list())$index_var %||% character(0))[1L]

  excl <- if (exists("pipeline_index_exclude_vars", mode = "function")) {
    pipeline_index_exclude_vars(cfg)
  } else {
    unique(c(index_var))
  }
  if (nzchar(index_var)) excl <- unique(c(excl, index_var))
  # 强制人口学（Gender 等）可进 Model；但暴露组分（Age∈FIB4 等）永远不可进协变量
  force <- if (exists("pipeline_force_include_covariates", mode = "function")) {
    pipeline_force_include_covariates(cfg)
  } else {
    character(0)
  }
  if (exists("pipeline_dedupe_force_demo_vars", mode = "function")) {
    force <- pipeline_dedupe_force_demo_vars(force)
  }
  comp_block <- if (exists("pipeline_covariate_analysis_exclude_vars", mode = "function")) {
    pipeline_covariate_analysis_exclude_vars(cfg)
  } else {
    character(0)
  }
  force <- setdiff(force, comp_block)
  excl <- setdiff(excl, force)

  max_m2 <- as.integer(
    (cfg$logistic %||% list())$model2_max_covariates %||%
      (cfg$incidence %||% list())$model2_max_covariates %||% 10L
  )[1L]
  if (!is.finite(max_m2) || max_m2 < 1L) max_m2 <- 10L

  M1_orig <- M1
  M2_orig <- M2
  M1 <- setdiff(M1, excl)
  clinical <- setdiff(M2, c(M1, excl))
  M2 <- unique(c(M1, clinical))

  dropped_clinical <- character(0)
  if (length(M2) > max_m2) {
    keep_clinical <- head(clinical, max(0L, max_m2 - length(M1)))
    dropped_clinical <- setdiff(clinical, keep_clinical)
    M2 <- unique(c(M1, keep_clinical))
    if (length(dropped_clinical)) {
      cli::cli_alert_info(
        "Model2 协变量截断至 {max_m2} 个（移除 {length(dropped_clinical)} 个临床变量）: {paste(dropped_clinical, collapse = ', ')}"
      )
    }
  }

  removed_idx <- unique(intersect(c(M1_orig, M2_orig), excl))
  if (length(removed_idx)) {
    cli::cli_alert_info(
      "Model2 排除指标相关协变量: {paste(removed_idx, collapse = ', ')}"
    )
  }

  list(
    M1 = M1,
    M2 = M2,
    excluded = excl,
    dropped_clinical = dropped_clinical,
    model2_max_covariates = max_m2
  )
}

# 暴露必须按【取值】做分位 / 连续回归。Table 1 可能把 0/1/2/3 转成 factor；
# as.numeric(factor) 会变成 1/2/3/4，加权中位数切到 3，且新 R 里 factor < 数值全是 NA → Table 2 空壳。
pipeline_index_as_numeric <- function(x) {
  if (is.null(x)) return(x)
  if (is.numeric(x) && !is.factor(x)) return(as.numeric(x))
  xn <- suppressWarnings(as.numeric(as.character(x)))
  n <- length(x)
  n_ok <- if (n) sum(is.finite(xn) | is.na(x)) else 0L
  if (n > 0L && (n_ok / n) >= 0.5) return(xn)
  if (is.factor(x)) return(suppressWarnings(as.numeric(x)))
  xn
}

# 分类暴露（Yes/No、factor 标签、0/1 码）：回归变量本身，禁止再当连续 / 再切分位。
pipeline_index_is_categorical <- function(x, max_numeric_levels = 2L) {
  if (is.null(x)) return(FALSE)
  max_n <- as.integer(max_numeric_levels)[1L]
  if (!is.finite(max_n) || max_n < 1L) max_n <- 2L
  if (is.logical(x)) return(TRUE)
  if (is.factor(x) || is.character(x)) {
    xn <- suppressWarnings(as.numeric(as.character(x)))
    n <- length(x)
    n_ok <- if (n) sum(is.finite(xn) | is.na(x)) else 0L
    if (n > 0L && (n_ok / n) >= 0.5) {
      u <- unique(stats::na.omit(xn))
      return(length(u) <= max_n)
    }
    return(TRUE)
  }
  if (is.numeric(x) && !is.factor(x)) {
    u <- unique(stats::na.omit(as.numeric(x)))
    if (!length(u)) return(FALSE)
    return(length(u) <= max_n && all(abs(u - round(u)) < 1e-8))
  }
  FALSE
}

pipeline_ctx_index_is_categorical <- function(ctx, index_var = NULL) {
  cfg <- (ctx$config %||% list())
  ix <- as.character(
    index_var %||%
      (if (exists("pipeline_index_exposure_var", mode = "function")) {
        pipeline_index_exposure_var(cfg)
      } else {
        character(0)
      }) %||%
      (cfg$logistic %||% list())$index_var %||%
      (cfg$survival %||% list())$index_var %||%
      ""
  )[1L]
  data <- ctx$data$imputed %||% ctx$data$train %||%
    ctx$data$cleaned %||% ctx$data$mapped
  if (!nzchar(ix) || is.null(data) || !is.data.frame(data) || !ix %in% names(data)) {
    return(FALSE)
  }
  pipeline_index_is_categorical(data[[ix]])
}

# 分类暴露：group_var = 变量本身，关掉 continuous 行
pipeline_apply_categorical_exposure <- function(bl_cfg, data, index_var) {
  bl_cfg <- bl_cfg %||% list()
  ix <- as.character(index_var %||% bl_cfg$index_var %||% "")[1L]
  if (!nzchar(ix) || is.null(data) || !is.data.frame(data) || !ix %in% names(data)) {
    return(bl_cfg)
  }
  if (!isTRUE(pipeline_index_is_categorical(data[[ix]]))) return(bl_cfg)
  bl_cfg$include_continuous_row <- FALSE
  gv <- as.character(bl_cfg$group_var %||% "")[1L]
  if (!nzchar(gv)) bl_cfg$group_var <- ix
  bl_cfg$categorical_exposure <- TRUE
  bl_cfg
}

# 分类暴露不得再跑分位 / RCS（只留 binary / 原生水平）
pipeline_categorical_exposure_should_skip_block <- function(block_name, ctx) {
  if (!isTRUE(pipeline_ctx_index_is_categorical(ctx))) return(FALSE)
  bn <- as.character(block_name %||% "")[1L]
  grepl(
    "quartile|tertile|quintile|sextile|_rcs$|rcs_incidence|rcs_prognosis|rcs_nhanes",
    bn
  )
}

# ── Table 1：离散数值（牙周炎 0–3、Yes/No 编码等）转 factor，避免 gtsummary ────────────────
# 把 unique≤threshold 的 numeric 当分类；否则 tbl_svysummary 会当分类却套 median/IQR 整表失败。
pipeline_coerce_discrete_numeric <- function(data, vars = NULL, threshold = 5L,
                                            force_continuous = character(0),
                                            outcome_col = NULL) {
  if (is.null(data) || !is.data.frame(data)) {
    return(list(
      data = data, discrete = character(0), continuous = character(0)
    ))
  }
  vars <- as.character(vars %||% names(data))
  vars <- intersect(vars[nzchar(vars)], names(data))
  force_continuous <- as.character(force_continuous %||% character(0))
  outcome_col <- as.character(outcome_col %||% "")[1L]
  if (nzchar(outcome_col)) vars <- setdiff(vars, outcome_col)
  vars <- setdiff(vars, force_continuous)
  is_num <- vapply(vars, function(v) is.numeric(data[[v]]) && !is.factor(data[[v]]), logical(1L))
  num_vars <- vars[is_num]
  n_uniq <- vapply(num_vars, function(v) {
    length(unique(stats::na.omit(data[[v]])))
  }, integer(1L))
  discrete <- num_vars[n_uniq <= as.integer(threshold)[1L]]
  continuous <- setdiff(num_vars, discrete)
  if (length(discrete)) {
    for (v in discrete) {
      data[[v]] <- as.factor(data[[v]])
    }
  }
  list(data = data, discrete = discrete, continuous = continuous)
}

# 仅对真正连续数值列套 median/IQR（已转 factor 的离散列排除）
pipeline_median_stat_vars <- function(data, skewed_vars) {
  skewed_vars <- unique(as.character(skewed_vars %||% character(0)))
  skewed_vars <- skewed_vars[nzchar(skewed_vars)]
  if (!is.data.frame(data) || !length(skewed_vars)) return(character(0))
  skewed_vars <- intersect(skewed_vars, names(data))
  keep <- vapply(skewed_vars, function(v) {
    x <- data[[v]]
    is.numeric(x) && !is.factor(x) && length(unique(stats::na.omit(x))) > 5L
  }, logical(1L))
  skewed_vars[keep]
}

# 加权 Table 1 是否真的写出（勿用 baseline_nhanes_done：块跑过 ≠ 表落盘）
pipeline_has_weighted_table1 <- function(results) {
  results <- results %||% list()
  isTRUE(results$nhanes_baseline_table) ||
    !is.null(results$table_1_nhanes_weighted) ||
    !is.null(results$baseline_table_weighted) ||
    (!is.null(results$table_1) && isTRUE(results$baseline_mode == "nhanes"))
}

# ── 分析候选变量池：与 baseline Table 1 include_vars 对齐 ─────────────────────
# 优先级：dual_db 显式池 → UV include_predictors → baseline_binary$include_vars
# 交叉滞后 / 发病：若 Table 1 限定了 include_vars，单因素与 VIF screen 只做这些特征
pipeline_baseline_table1_include_predictors <- function(cfg) {
  cfg <- cfg %||% list()
  harm <- (cfg$dual_db %||% list())$harmonization %||% list()
  inc <- as.character(harm$prognosis_include_vars %||% character(0))
  if (!length(inc)) {
    inc <- as.character((cfg$univariate_incidence_binary %||% list())$include_predictors %||% character(0))
  }
  if (!length(inc)) {
    inc <- as.character((cfg$univariate_prognosis %||% list())$include_predictors %||% character(0))
  }
  if (!length(inc)) {
    inc <- as.character((cfg$univariate_nhanes %||% list())$include_predictors %||% character(0))
  }
  if (!length(inc)) {
    inc <- as.character((cfg$baseline_binary %||% list())$include_vars %||% character(0))
  }
  # 显式关闭：univariate_from_baseline_table1 = FALSE 时不限制
  uv_flag <- (cfg$univariate_incidence_binary %||% list())$univariate_from_baseline_table1
  if (is.null(uv_flag)) uv_flag <- (cfg$cross_lagged %||% list())$univariate_from_baseline_table1
  if (is.null(uv_flag)) uv_flag <- (cfg$baseline_binary %||% list())$univariate_from_baseline_table1
  if (isFALSE(uv_flag)) return(character(0))
  # 有 include_vars 则默认启用；或显式 TRUE
  if (!isTRUE(uv_flag) && !length(inc)) return(character(0))
  if (!length(inc) && isTRUE(uv_flag)) {
    inc <- as.character((cfg$baseline_binary %||% list())$include_vars %||% character(0))
  }
  unique(inc[nzchar(inc)])
}

# ── 双库 HF：与 baseline$include_vars 相同的预后分析候选变量池 ─────────────────
pipeline_dual_db_include_predictors <- function(cfg) {
  # 兼容旧名：优先 Table1 / UV 统一池
  inc <- pipeline_baseline_table1_include_predictors(cfg)
  if (length(inc)) return(inc)
  cfg <- cfg %||% list()
  harm <- (cfg$dual_db %||% list())$harmonization %||% list()
  inc <- as.character(harm$prognosis_include_vars %||% character(0))
  if (!length(inc)) {
    inc <- as.character((cfg$baseline_binary %||% list())$include_vars %||% character(0))
  }
  if (!length(inc)) {
    inc <- as.character((cfg$univariate_prognosis %||% list())$include_predictors %||% character(0))
  }
  inc[nzchar(inc)]
}

pipeline_apply_include_predictors <- function(cfg, predictor_vars, data_names,
                                              label = "与 Table 1 同一变量池") {
  inc <- pipeline_dual_db_include_predictors(cfg)
  if (!length(inc)) return(predictor_vars)
  pool <- inc[inc %in% data_names & inc %in% predictor_vars]
  miss <- setdiff(inc, pool)
  # 仅提示「在数据中但不在当前候选」；数据中根本没有的不算 miss 噪声
  miss_in_data <- setdiff(intersect(inc, data_names), pool)
  if (length(miss_in_data)) {
    cli::cli_alert_warning(
      "{label}: {length(miss_in_data)} 个被先前排除（已忽略）: {paste(miss_in_data, collapse = ', ')}"
    )
  }
  if (!length(pool)) {
    stop(
      label, ": 统一变量与当前分析数据无交集。",
      "请检查 baseline_binary$include_vars / imputation 列，或设 univariate_from_baseline_table1=FALSE。",
      call. = FALSE
    )
  }
  # 保持 Table 1 顺序
  pool <- inc[inc %in% pool]
  cli::cli_alert_info("{label}: {length(pool)} 个（仅基线表特征）")
  pool
}

# ── 亚组变量池（Table 1 / 双库人口学 vs 临床）────────────────────────────────
suppressWarnings({
  .sg_util_path <- file.path(getwd(), "R", "subgroup_vars.R")
  if (file.exists(.sg_util_path)) source(.sg_util_path, local = FALSE)
})

# ── 判断是否 KNHANES（韩国；须精确匹配，避免与 US NHANES 权重公式混淆）──────
.is_knhanes_db <- function(cfg) {
  proj <- cfg$project %||% list()
  dt <- tolower(trimws(as.character(proj$database_type %||% "")))
  db <- tolower(trimws(as.character(proj$database %||% "")))
  identical(dt, "knhanes") || identical(db, "knhanes")
}

# ── 判断是否走复杂抽样加权块（US NHANES / NHANCE / KNHANES）────────────────
# 注意：KNHANES 名字含 "nhanes"，但权重算法 ≠ CDC ÷K，须用 weight_builder 分派。
.is_nhanes_db <- function(cfg) {
  if (.is_knhanes_db(cfg)) return(TRUE)
  proj <- cfg$project %||% list()
  dt <- tolower(trimws(as.character(proj$database_type %||% "")))
  db <- tolower(trimws(as.character(proj$database %||% "")))
  # 精确/前缀：nhanes、nhance；排除仅子串误伤已由 .is_knhanes_db 先行处理
  grepl("^(nhanes|nhance)", dt) || grepl("^(nhanes|nhance)", db) ||
    identical(dt, "nhanes") || identical(db, "nhanes") ||
    grepl("nhanes|nhance", dt) || grepl("nhanes|nhance", db)
}

# ── 判断是否自有数据（own）：发表表保留原始数据列序 ───────────────────────────
.is_own_db <- function(cfg) {
  proj <- cfg$project %||% list()
  cm   <- cfg$column_mapping %||% list()
  dt <- tolower(trimws(as.character(proj$database_type %||% "")))
  db <- tolower(trimws(as.character(proj$database %||% "")))
  cm_dt <- tolower(trimws(as.character(cm$database_type %||% "")))
  identical(dt, "own") || identical(db, "own") || identical(cm_dt, "own")
}

# ── NHANES cutoff 衍生的 index 分组列：单因素/VIF 中至多保留一种（避免三分位+四分位同时入模）──
.nhanes_index_group_column_names <- function() {
  c("Index_Group", "Index_Group_Tertile", "Index_Group_Quartile")
}

infer_nhanes_index_grouping_keep_kind <- function(cfg) {
  cfg <- cfg %||% list()
  mc <- cfg$multicollinearity %||% list()
  ovr <- mc$index_grouping_covariate_keep %||% NULL
  if (!is.null(ovr)) {
    k <- tolower(trimws(as.character(ovr)[1L]))
    if (k %in% c("binary", "tertile", "quartile")) return(k)
  }
  pred <- cfg$prediction %||% list()
  ui <- pred$unified_index_logistic %||% list()
  if (isTRUE(ui$enabled %||% FALSE)) {
    md <- tolower(trimws(as.character(ui$mode %||% "")[1L]))
    if (identical(md, "tertile")) return("tertile")
    if (identical(md, "quartile")) return("quartile")
    if (md %in% c("median", "binary")) return("binary")
  }
  lg <- cfg$logistic %||% list()
  gm <- tolower(trimws(as.character(lg$grouping_mode %||% "auto")))
  mn <- suppressWarnings(as.integer(lg$manual_n_groups %||% 0L)[1L])
  if (identical(gm, "manual") && mn %in% c(2L, 3L, 4L)) {
    if (mn == 4L) return("quartile")
    if (mn == 3L) return("tertile")
    return("binary")
  }
  if (identical(gm, "predefined")) {
    gv <- trimws(as.character(lg$group_var %||% "")[1L])
    std <- .nhanes_index_group_column_names()
    if (gv %in% std) {
      if (identical(gv, "Index_Group_Quartile")) return("quartile")
      if (identical(gv, "Index_Group_Tertile")) return("tertile")
      return("binary")
    }
    return(NULL)
  }
  mi <- pred$logistic_multi_index %||% list()
  try_ng <- suppressWarnings(as.integer(mi$try_n_groups %||% c(4L, 3L, 2L)))
  try_ng <- try_ng[is.finite(try_ng) & try_ng %in% c(2L, 3L, 4L)]
  if (length(try_ng)) {
    top <- try_ng[[1L]]
    if (top == 4L) return("quartile")
    if (top == 3L) return("tertile")
    return("binary")
  }
  "tertile"
}

.nhanes_keep_col_for_group_kind <- function(kind) {
  kind <- tolower(trimws(as.character(kind %||% "tertile")[1L]))
  if (identical(kind, "quartile")) return("Index_Group_Quartile")
  if (identical(kind, "binary")) return("Index_Group")
  "Index_Group_Tertile"
}

filter_redundant_nhanes_index_group_columns <- function(vars, cfg, data_column_names = NULL) {
  vars <- unique(as.character(vars %||% character(0)))
  dnames <- if (is.null(data_column_names)) vars else unique(as.character(data_column_names))
  std <- .nhanes_index_group_column_names()
  present <- intersect(std, dnames)
  if (length(present) <= 1L) return(vars)
  keep_kind <- infer_nhanes_index_grouping_keep_kind(cfg)
  if (is.null(keep_kind)) return(vars)
  keep_col <- .nhanes_keep_col_for_group_kind(keep_kind)
  drop <- setdiff(present, keep_col)
  if (length(drop) == 0L) return(vars)
  dropped <- intersect(vars, drop)
  if (length(dropped) > 0L) {
    cli::cli_alert_info(
      "NHANES index 分组列按配置仅保留 [{keep_col}]，从变量集移除: {paste(dropped, collapse = ', ')}"
    )
  }
  setdiff(vars, drop)
}

# ── 发表图表命名：「Figure|Table …-数据库名. 描述」（库名在编号后，不在最前）────────
.get_db_name_for_naming <- function(sanitize_for_file = FALSE) {
  opt <- getOption("pipeline.database_name")
  if (!is.null(opt)) {
    nm <- trimws(as.character(opt)[1L])
    if (!nzchar(nm)) return("")
  } else {
    nm <- "UnknownDB"
  }
  # 项目里常用拼写 Nhance → 发表/文件名统一为 NHANES
  if (tolower(nm) %in% c("nhance", "nhanes")) nm <- "NHANES"
  if (isTRUE(sanitize_for_file)) {
    nm <- gsub("[^A-Za-z0-9._-]+", "_", nm)
    if (!nzchar(nm)) nm <- "UnknownDB"
  }
  nm
}

.regex_escape_pcre <- function(s) {
  s <- as.character(s %||% "")[1L]
  gsub("(\\\\|[][{}()+*^$?.|^-])", "\\\\\\1", s, perl = TRUE)
}

# MIMIC_IV / MIMIC IV 视为同一库名
.pub_db_name_flex_re <- function(db) {
  db <- trimws(as.character(db %||% "")[1L])
  if (!nzchar(db)) return("")
  parts <- strsplit(gsub("[ _]+", " ", db), " ", fixed = TRUE)[[1L]]
  parts <- vapply(parts, .regex_escape_pcre, character(1L), USE.NAMES = FALSE)
  paste(parts, collapse = "[ _]+")
}

# 去掉标题/文件名中与「Figure x-DB.」重复的库名（如正文里再写 " in NHANES"）
.pub_strip_redundant_db_in_pub_string <- function(txt, db) {
  txt <- as.character(txt %||% "")[1L]
  db <- trimws(as.character(db %||% "")[1L])
  if (!nzchar(txt) || !nzchar(db)) return(txt)
  db_re <- .regex_escape_pcre(db)
  txt <- gsub(paste0(" in ", db_re, "\\b"), "", txt, ignore.case = TRUE, perl = TRUE)
  txt <- gsub(paste0("\\s*,\\s*", db_re, "\\b"), "", txt, ignore.case = TRUE, perl = TRUE)
  gsub("\\s{2,}", " ", trimws(txt))
}

.inject_db_into_pub_label <- function(x, sanitize_for_file = FALSE) {
  s <- as.character(x %||% "")
  if (!nzchar(s)) return(s)

  lead <- ""
  tail <- ""
  core <- s
  if (startsWith(core, "**")) {
    lead <- "**"
    core <- sub("^\\*\\*", "", core)
  }
  if (grepl("\\*\\*$", core)) {
    tail <- "**"
    core <- sub("\\*\\*$", "", core)
  }

  db_nm <- .get_db_name_for_naming(sanitize_for_file = sanitize_for_file)
  db_re <- .regex_escape_pcre(db_nm)
  db_flex <- .pub_db_name_flex_re(db_nm)

  # 误用旧规则时可能出现「库名. Figure …」，去掉前缀以便重新插入 -库名
  core <- sub(paste0("^", db_re, "\\.\\s*"), "", core, ignore.case = TRUE)

  is_pub <- grepl("^Fig([ _]|\\b)", core, ignore.case = TRUE) ||
    grepl("^Figure([ _]|\\b)", core, ignore.case = TRUE) ||
    grepl("^Table([ _]|\\b)", core, ignore.case = TRUE)
  if (!is_pub) {
    return(paste0(lead, core, tail))
  }

  core <- .pub_strip_redundant_db_in_pub_string(core, db_nm)

  # 扩展名（pdf/xlsx/tex 等）与主体分离，-库名 插在主体第一个「.」之前，或无点时接在主体末尾
  ext <- ""
  stem <- core
  em <- regexpr("\\.[A-Za-z][A-Za-z0-9]{0,7}$", stem, perl = TRUE)
  if (!is.na(em[1L]) && em[1L] > 1L) {
    ext <- substr(stem, em[1L], nchar(stem))
    stem <- substr(stem, 1L, em[1L] - 1L)
  }

  # 折叠 Table 1-MIMIC IV-MIMIC IV. → Table 1-MIMIC IV.
  if (nzchar(db_flex)) {
    stem <- gsub(
      paste0("-((?:", db_flex, "))(?:-\\1)+(?=\\.)"),
      "-\\1",
      stem,
      ignore.case = TRUE,
      perl = TRUE
    )
  }

  already <- nzchar(stem) && (
    grepl("Train\\s*\\(", stem, ignore.case = TRUE) ||
    grepl(
      paste0("^(Figure|Fig|Table)\\s+.+?-", db_flex, "\\."),
      stem,
      ignore.case = TRUE,
      perl = TRUE
    ) ||
      # 文件名已含任意 -库名. 时不再二次注入（库名可含空格：MIMIC IV）
      grepl(
        "^(Figure|Fig|Table)\\s+.+?-[A-Za-z][A-Za-z0-9_]*(?:[ _][A-Za-z0-9_]+)*\\.",
        stem,
        ignore.case = TRUE,
        perl = TRUE
      ) ||
      # 已是「Figure N. DB. caption」curate 形态（第二段库名后再接 caption，勿把 “Table 1. Baseline…” 当已注入）
      grepl(
        "^(Figure|Fig|Table)\\s+[0-9S]+\\.\\s*[A-Za-z][A-Za-z0-9_ \\-]*\\.\\s+\\S",
        stem,
        ignore.case = TRUE,
        perl = TRUE
      ) ||
      (identical(toupper(db_nm), "NHANES") &&
        grepl(
          "^(Figure|Fig|Table)\\s+.+?-(?:NHANES|Nhance|nhance)\\.",
          stem,
          ignore.case = TRUE,
          perl = TRUE
        ))
  )

  if (!already && nzchar(db_nm) && grepl("^(Figure|Fig|Table)\\s+", stem, ignore.case = TRUE)) {
    # 修正旧版误加在整段末尾的 -DB（fixed=TRUE 下 "\\." 无法匹配句号导致）
    stem <- sub(paste0("-", db_re, "$"), "", stem, ignore.case = TRUE, perl = TRUE)
    dot_pos <- regexpr(".", stem, fixed = TRUE)[1L]
    if (!is.na(dot_pos) && dot_pos > 0L) {
      left <- trimws(substr(stem, 1L, dot_pos - 1L))
      right <- trimws(substr(stem, dot_pos + 1L, nchar(stem)))
      if (!grepl(paste0("-", db_re, "$"), left, ignore.case = TRUE)) {
        stem <- paste0(left, "-", db_nm, ". ", right)
      }
    } else {
      if (!grepl(paste0("-", db_re, "$"), stem, ignore.case = TRUE)) {
        stem <- paste0(stem, "-", db_nm)
      }
    }
  }

  core <- paste0(stem, ext)
  paste0(lead, core, tail)
}

.needs_windows_path_limits <- function(filepath) {
  fp <- as.character(filepath %||% "")[1L]
  if (!nzchar(fp)) return(FALSE)
  if (.Platform$OS.type == "windows") return(TRUE)
  abs_fp <- tryCatch(
    normalizePath(fp, winslash = "/", mustWork = FALSE),
    error = function(e) fp
  )
  grepl("^/mnt/[a-zA-Z]/", abs_fp, perl = TRUE)
}

.sanitize_path_component_for_os <- function(s, for_windows_mount = FALSE) {
  s <- as.character(s %||% "")[1L]
  if (!nzchar(s)) return(s)
  apply <- isTRUE(for_windows_mount) || .Platform$OS.type == "windows"
  if (!apply) return(s)
  # Windows / NTFS：禁止字符 + 方括号（batch 长路径下易触发 MAX_PATH）
  s <- gsub("[\\[\\]]", "", s, perl = TRUE)
  s <- gsub("[<>:\"/\\\\|?*]", "_", s, perl = TRUE)
  gsub("\\s{2,}", " ", trimws(s))
}

.truncate_filepath_for_max_path <- function(filepath, max_len = 250L) {
  fp <- as.character(filepath %||% "")[1L]
  if (!nzchar(fp) || nchar(fp) <= max_len) return(fp)
  ext <- tools::file_ext(fp)
  stem <- if (nzchar(ext)) {
    sub(paste0("\\.", ext, "$"), "", basename(fp), ignore.case = TRUE)
  } else {
    basename(fp)
  }
  dn <- dirname(fp)
  reserve <- nchar(dn) + if (nzchar(ext)) nchar(ext) + 2L else 1L
  max_stem <- as.integer(max_len - reserve)
  if (max_stem < 24L) max_stem <- 24L
  if (nchar(stem) > max_stem) {
    stem <- paste0(substr(stem, 1L, max_stem - 3L), "...")
  }
  if (nzchar(ext)) file.path(dn, paste0(stem, ".", ext)) else file.path(dn, stem)
}

.inject_db_into_pub_filepath <- function(filepath) {
  fp <- as.character(filepath %||% "")
  if (!nzchar(fp)) return(fp)
  bn <- basename(fp)
  dn <- dirname(fp)
  win_lim <- .needs_windows_path_limits(fp)
  bn2 <- .sanitize_path_component_for_os(
    .inject_db_into_pub_label(bn, sanitize_for_file = TRUE),
    for_windows_mount = win_lim
  )
  # 表文件名与图一致：下划线 → 空格（Disease_Group → Disease Group）
  bn2 <- gsub("_", " ", bn2, fixed = TRUE)
  fp2 <- file.path(dn, bn2)
  if (win_lim) .truncate_filepath_for_max_path(fp2) else fp2
}

# 发表表：字符向量 / 因子单元格内下划线 → 空格（默认不改列名，避免破坏程序性列名）
.pub_charvec_underscores <- function(x) {
  if (is.null(x)) return(x)
  gsub("_", " ", as.character(x), fixed = TRUE)
}

.pub_df_cells_underscores_to_spaces <- function(df) {
  if (is.null(df) || !is.data.frame(df)) return(df)
  out <- df
  for (j in seq_along(out)) {
    if (is.character(out[[j]])) {
      out[[j]] <- gsub("_", " ", out[[j]], fixed = TRUE)
    } else if (is.factor(out[[j]])) {
      lev <- levels(out[[j]])
      if (!is.null(lev)) levels(out[[j]]) <- gsub("_", " ", lev, fixed = TRUE)
      else out[[j]] <- factor(gsub("_", " ", as.character(out[[j]]), fixed = TRUE))
    }
  }
  out
}

# ── Logistic 分位分组（与 Blocks/block_logistic.R 中 cut 规则一致）────────────
logistic_quantile_group_factor <- function(values, n_groups) {
  values <- as.numeric(values)
  n_groups <- as.integer(n_groups)[1L]
  if (!n_groups %in% c(2L, 3L, 4L)) return(NULL)
  if (n_groups == 4L) {
    probs <- c(0, 0.25, 0.5, 0.75, 1)
    labels <- c("Q1", "Q2", "Q3", "Q4")
  } else if (n_groups == 3L) {
    probs <- c(0, 1 / 3, 2 / 3, 1)
    labels <- c("T1", "T2", "T3")
  } else {
    probs <- c(0, 0.5, 1)
    labels <- c("low", "high")
  }
  cuts <- unique(as.numeric(stats::quantile(values, probs = probs, na.rm = TRUE)))
  if (length(cuts) < 2L) return(NULL)
  ng <- n_groups
  if ((length(cuts) - 1L) < ng) {
    ng <- length(cuts) - 1L
    if (ng <= 1L) return(NULL)
    labels <- labels[seq_len(ng)]
  }
  out <- tryCatch(
    cut(values, breaks = cuts, labels = labels, include.lowest = TRUE),
    error = function(e) NULL
  )
  if (is.null(out)) return(NULL)
  factor(out)
}

# 多指标 Logistic 统一分组：与 block_logistic 一致以「最后一组」为 crude 目标组。
# mode:
#   coarsest_all_crude — 依次 n=2,3,4，取第一个使 index_vars 中每个指标 crude 目标组均 P<p_threshold 的分组数；
#                        若均不满足则 patch=FALSE（不统一改 logistic），避免强行 manual 导致某指标无 Table 2/4。
#   tertile / quartile / median — 固定 3/4/2 组。
#   none — 不修改 config（返回 patch=FALSE）。
unified_prediction_logistic_choice <- function(
    data,
    outcome_col,
    disease_label,
    index_vars,
    p_threshold = 0.05,
    mode = "coarsest_all_crude",
    fallback_n_groups = 3L) {
  mode <- tolower(trimws(mode))
  index_vars <- intersect(as.character(index_vars), names(data))
  fallback_n_groups <- as.integer(fallback_n_groups)[1L]
  if (!fallback_n_groups %in% c(2L, 3L, 4L)) fallback_n_groups <- 3L

  if (identical(mode, "none")) {
    return(list(n_groups = NULL, reason = "unified_index_logistic.mode=none", patch = FALSE))
  }
  if (identical(mode, "tertile")) {
    return(list(n_groups = 3L, reason = "mode=tertile（三指标同一三分位）", patch = TRUE))
  }
  if (identical(mode, "quartile")) {
    return(list(n_groups = 4L, reason = "mode=quartile", patch = TRUE))
  }
  if (mode %in% c("median", "binary", "dichotomy")) {
    return(list(n_groups = 2L, reason = "mode=median", patch = TRUE))
  }

  if (!outcome_col %in% names(data) || length(index_vars) < 1L) {
    return(list(
      n_groups = NULL,
      reason = "coarsest_all_crude：缺结局或指标列，不统一覆盖 logistic",
      patch = FALSE
    ))
  }

  yraw <- data[[outcome_col]]
  if (is.character(yraw) || is.factor(yraw)) {
    y01 <- ifelse(as.character(yraw) == as.character(disease_label), 1, 0)
  } else {
    y01 <- as.numeric(yraw)
  }

  .crude_ok_one <- function(ix, n_g) {
    s <- !is.na(y01) & !is.na(data[[ix]])
    if (sum(s) < 10L) return(FALSE)
    gf <- logistic_quantile_group_factor(data[[ix]][s], n_g)
    if (is.null(gf)) return(FALSE)
    d2 <- data.frame(
      yy = y01[s],
      Group = droplevels(factor(gf)),
      stringsAsFactors = FALSE
    )
    if (nlevels(d2$Group) < 2L) return(FALSE)
    fit <- tryCatch(
      stats::glm(yy ~ Group, data = d2, family = stats::binomial()),
      error = function(e) NULL
    )
    if (is.null(fit)) return(FALSE)
    tgt <- tail(levels(d2$Group), 1L)
    cm <- stats::summary.glm(fit)$coefficients
    rn <- rownames(cm)
    tr <- paste0("Group", tgt)
    if (!tr %in% rn) return(FALSE)
    cm[tr, "Pr(>|z|)"] < p_threshold
  }

  .crude_ok_all <- function(n_g) {
    for (ix in index_vars) {
      if (!.crude_ok_one(ix, n_g)) return(FALSE)
    }
    TRUE
  }

  for (n_g in c(2L, 3L, 4L)) {
    ok <- tryCatch(.crude_ok_all(n_g), error = function(e) FALSE)
    if (isTRUE(ok)) {
      return(list(
        n_groups = n_g,
        reason = paste0(
          "coarsest_all_crude：取最粗分位 n=", n_g,
          "（median/tertile/quartile 对应 2/3/4 组），三指标 crude 目标组均 P<", p_threshold
        ),
        patch = TRUE
      ))
    }
  }
  # 此处已确认 n=2,3,4 均无「三指标同时 crude 显著」；不再强行 fallback 为 manual（否则易触发 MANUAL_GROUPING_STOP）
  list(
    n_groups = NULL,
    reason = paste0(
      "coarsest_all_crude：无 2/3/4 组分位使三指标 crude 目标组均 P<", p_threshold,
      "；不统一覆盖各指标 logistic（请改 mode=tertile/quartile 或 config$logistic$grouping_mode=auto 等）。"
    ),
    patch = FALSE
  )
}

# 供 run_prediction / run_logistic_only：若启用则返回并入 logistic 的 list，否则 NULL。
prediction_unified_logistic_merge <- function(data, cfg) {
  pred <- cfg$prediction %||% list()
  u <- pred$unified_index_logistic %||% list()
  if (!isTRUE(u$enabled %||% FALSE)) return(NULL)
  logistic_cfg <- cfg$logistic %||% list()
  outcome_col <- cfg$data$outcome_column %||% "Disease"
  disease_label <- cfg$project$analysis_group %||% cfg$project$disease
  ix_all <- as.character(pred$index_vars %||% character(0))
  ix_all <- ix_all[nzchar(ix_all)]
  p_threshold <- logistic_cfg$p_threshold %||% 0.05
  mode <- u$mode %||% "coarsest_all_crude"
  fb <- as.integer(u$fallback_n_groups %||% 3L)
  ch <- unified_prediction_logistic_choice(
    data, outcome_col, disease_label, ix_all,
    p_threshold = p_threshold,
    mode = mode,
    fallback_n_groups = fb
  )
  if (!isTRUE(ch$patch) || is.null(ch$n_groups)) return(NULL)
  out <- list(grouping_mode = "manual", manual_n_groups = ch$n_groups)
  attr(out, "unified_reason") <- ch$reason
  out
}

# ── 多指标 Logistic： crude 筛选保留指标 + 统一分位（manual_n_groups）──────────
# 在 try_n_groups（默认 2/3/4）上对每个 index 做与 unified_prediction_logistic_choice
# 相同的 crude 目标组检验；选取「在该 n_g 下全体通过 crude 的指标数」最大的分位档；
# 并列时取更粗分位（组数更少）。任一 n_g 下均 crude 不显著的指标不会进入 index_vars，
# 后续 run_block(logistic) 不会为这些指标出表。
prediction_plan_multi_index_logistic <- function(data, cfg, roc_cutoffs = list()) {
  pred <- cfg$prediction %||% list()
  lmi <- pred$logistic_multi_index %||% list()
  if (!isTRUE(lmi$enabled %||% FALSE)) return(NULL)

  ix_all <- as.character(pred$index_vars %||% character(0))
  ix_all <- unique(ix_all[nzchar(ix_all)])
  if (!length(ix_all)) {
    lv <- (cfg$logistic %||% list())$index_var
    if (length(lv)) ix_all <- unique(as.character(lv)[nzchar(as.character(lv))])
  }
  ix_all <- intersect(ix_all, names(data))
  logistic_cfg <- cfg$logistic %||% list()
  p_threshold <- as.numeric(logistic_cfg$p_threshold %||% 0.05)[1L]
  if (!is.finite(p_threshold)) p_threshold <- 0.05

  try_order <- as.integer(unlist(lmi$try_n_groups %||% c(2L, 3L, 4L), use.names = FALSE))
  try_order <- try_order[try_order %in% c(2L, 3L, 4L)]
  if (!length(try_order)) try_order <- c(2L, 3L, 4L)

  outcome_col <- cfg$data$outcome_column %||% "Disease"
  disease_label <- cfg$project$analysis_group %||% cfg$project$disease
  if (!outcome_col %in% names(data) || !length(ix_all)) {
    return(NULL)
  }

  yraw <- data[[outcome_col]]
  if (is.character(yraw) || is.factor(yraw)) {
    y01 <- ifelse(as.character(yraw) == as.character(disease_label), 1L, 0L)
  } else {
    y01 <- as.integer(yraw)
  }

  # n_g=2 时：若提供了 ROC cutoff 则用它分组，否则用中位数
  .crude_p_one <- function(ix, n_g) {
    s <- !is.na(y01) & !is.na(data[[ix]])
    if (sum(s) < 10L) return(NA_real_)
    vals <- data[[ix]][s]
    if (n_g == 2L && !is.null(roc_cutoffs[[ix]]) && is.finite(roc_cutoffs[[ix]])) {
      cv <- roc_cutoffs[[ix]]
      vmin <- min(vals, na.rm = TRUE); vmax <- max(vals, na.rm = TRUE)
      if (cv <= vmin || cv >= vmax) {
        gf <- logistic_quantile_group_factor(vals, 2L)
      } else {
        # Convention A: equals cutoff → high (right = FALSE → [vmin, cv) / [cv, vmax])
        gf <- cut(vals, breaks = c(vmin, cv, vmax),
                  labels = c("low", "high"), include.lowest = TRUE, right = FALSE)
      }
    } else {
      gf <- logistic_quantile_group_factor(vals, n_g)
    }
    if (is.null(gf)) return(NA_real_)
    d2 <- data.frame(
      yy = y01[s],
      Group = droplevels(factor(gf)),
      stringsAsFactors = FALSE
    )
    if (nlevels(d2$Group) < 2L) return(NA_real_)
    fit <- tryCatch(
      stats::glm(yy ~ Group, data = d2, family = stats::binomial()),
      error = function(e) NULL
    )
    if (is.null(fit)) return(NA_real_)
    tgt <- tail(levels(d2$Group), 1L)
    cm <- stats::summary.glm(fit)$coefficients
    rn <- rownames(cm)
    tr <- paste0("Group", tgt)
    if (!tr %in% rn) return(NA_real_)
    as.numeric(cm[tr, "Pr(>|z|)"])
  }

  pval_mat <- matrix(NA_real_, nrow = length(ix_all), ncol = length(try_order))
  rownames(pval_mat) <- ix_all
  colnames(pval_mat) <- as.character(try_order)
  for (n_g in try_order) {
    pval_mat[, as.character(n_g)] <- vapply(ix_all, function(ix) .crude_p_one(ix, n_g), numeric(1))
  }
  pass_mat <- pval_mat < p_threshold
  pass_mat[is.na(pass_mat)] <- FALSE

  common_ng <- try_order[vapply(try_order, function(n_g) {
    all(pass_mat[, as.character(n_g), drop = TRUE])
  }, logical(1))]

  if (length(common_ng)) {
    best_n <- common_ng[[1L]]
    best_set <- ix_all
    selected_mode <- "common_significant_quantile"
  } else {
    n_pass <- vapply(try_order, function(n_g) {
      sum(pass_mat[, as.character(n_g), drop = TRUE])
    }, integer(1))
    best_n <- try_order[which.max(n_pass)][1L]
    best_set <- ix_all[pass_mat[, as.character(best_n), drop = TRUE]]
    selected_mode <- "max_pass_quantile_fallback"
  }

  if (best_n == 2L) {
    cuts_used <- vapply(ix_all, function(ix) {
      cv <- roc_cutoffs[[ix]]
      if (!is.null(cv) && is.finite(cv)) paste0("ROC(", round(cv, 4), ")") else "median"
    }, character(1))
    unique_cuts <- unique(cuts_used)
    grp_lab <- if (length(unique_cuts) == 1L) paste0("binary (", unique_cuts, ")")
               else "binary (ROC cutoff per index)"
  } else {
    grp_lab <- switch(as.character(best_n),
      "3" = "tertile (T1-T3)", "4" = "quartile (Q1-Q4)", "unknown")
  }

  list(
    index_vars = best_set,
    manual_n_groups = best_n,
    grouping_label = grp_lab,
    dropped = setdiff(ix_all, best_set),
    try_n_groups_evaluated = try_order,
    p_threshold = p_threshold,
    original_index_vars = ix_all,
    selected_mode = selected_mode,
    pval_matrix = pval_mat,
    pass_matrix = pass_mat,
    roc_cutoffs_used = roc_cutoffs
  )
}

prediction_apply_multi_index_logistic_plan <- function(cx) {
  pred <- cx$config$prediction %||% list()
  lmi <- pred$logistic_multi_index %||% list()
  if (!isTRUE(lmi$enabled %||% FALSE)) return(cx)

  data <- cx$data$imputed %||% cx$data$cleaned
  if (is.null(data) || !is.data.frame(data) || !nrow(data)) {
    cli::cli_alert_warning("prediction logistic_multi_index: 无插补/清洗数据，跳过指标筛选。")
    return(cx)
  }

  # 从 step*_cutoff 目录读取各指标的 ROC cutoff 值，用于二分位粗筛
  .collect_roc_cutoffs <- function() {
    out_base <- cx$output_dir %||% ""
    if (!nzchar(out_base)) return(list())
    parent_dir <- dirname(normalizePath(out_base, winslash = "/", mustWork = FALSE))
    cuts <- list()
    tryCatch({
      all_dirs <- list.dirs(parent_dir, recursive = FALSE, full.names = TRUE)
      cutoff_dirs <- all_dirs[grepl("cutoff", basename(all_dirs), ignore.case = TRUE)]
      ix_cands <- as.character(pred$index_vars %||% character(0))
      for (d in cutoff_dirs) {
        for (ix in ix_cands) {
          fp <- file.path(d, paste0("cutoff_", ix, ".csv"))
          if (file.exists(fp) && is.null(cuts[[ix]])) {
            df <- tryCatch(read.csv(fp, stringsAsFactors = FALSE), error = function(e) NULL)
            if (!is.null(df) && "cutoff" %in% names(df)) {
              val <- suppressWarnings(as.numeric(df$cutoff[1L]))
              if (is.finite(val)) cuts[[ix]] <- val
            }
          }
        }
      }
    }, error = function(e) NULL)
    cuts
  }
  roc_cutoffs <- .collect_roc_cutoffs()
  if (length(roc_cutoffs)) {
    cli::cli_alert_info(
      "粗筛：已找到 ROC cutoff，二分位使用 cutoff 替代中位数：{paste(paste0(names(roc_cutoffs), '=', round(unlist(roc_cutoffs), 4)), collapse = ', ')}"
    )
  }

  plan <- prediction_plan_multi_index_logistic(data, cx$config, roc_cutoffs = roc_cutoffs)
  if (is.null(plan)) return(cx)

  # 打印每个指标在各分位（2/3/4）的 crude 目标组 P
  try_order <- plan$try_n_groups_evaluated %||% integer(0)
  pmat <- plan$pval_matrix
  if (length(try_order) && !is.null(pmat)) {
    for (ix in rownames(pmat)) {
      seg <- vapply(try_order, function(n_g) {
        pv <- pmat[ix, as.character(n_g)]
        lb <- switch(as.character(n_g),
          "2" = if (!is.null(roc_cutoffs[[ix]])) paste0("ROC(", round(roc_cutoffs[[ix]], 4), ")")
                else "median",
          "3" = "tertile", "4" = "quartile", as.character(n_g))
        paste0(lb, "=", ifelse(is.na(pv), "NA", fmt_pval(pv)))
      }, character(1))
      cli::cli_alert_info("Logistic 粗筛 P [{ix}]: {paste(seg, collapse = '; ')}")
    }
  }

  dropped <- plan$dropped %||% character(0)
  if (length(dropped)) {
    cli::cli_alert_warning(
      "Logistic 多指标（粗筛过滤）：以下指标不显著，已排除，不出表：{paste(dropped, collapse = ', ')}"
    )
  }
  if (!length(plan$index_vars) || is.na(plan$manual_n_groups)) {
    stop(
      "logistic_multi_index：筛选后无可用指标（请放宽 p_threshold、检查数据或关闭 logistic_multi_index）。",
      call. = FALSE
    )
  }

  if (identical(plan$selected_mode, "common_significant_quantile")) {
    cli::cli_alert_success(
      "Logistic 多指标：共同显著分位 manual_n_groups={plan$manual_n_groups}（{plan$grouping_label}）；保留指标：{paste(plan$index_vars, collapse = ', ')}。"
    )
  } else {
    cli::cli_alert_warning(
      "Logistic 多指标：无共同显著分位；取通过数最多分位 manual_n_groups={plan$manual_n_groups}（{plan$grouping_label}），保留显著指标：{paste(plan$index_vars, collapse = ', ')}。"
    )
  }

  cx$config$prediction$index_vars <- plan$index_vars
  cx$config$logistic$grouping_mode <- "manual"
  cx$config$logistic$manual_n_groups <- as.integer(plan$manual_n_groups)[1L]
  cx$results$logistic_multi_index_plan <- plan
  cx
}


.table_queue_env <- new.env(parent = emptyenv())
.table_queue_env$items <- list()


# ── 加载原始数据（支持 .RData / .rds / .csv / .xlsx）────────────────────────
load_rawdata <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext == "rdata" || ext == "rda") {
    env <- new.env()
    load(path, envir = env)
    objs <- ls(env)
    df_objs <- objs[sapply(objs, function(o) is.data.frame(get(o, envir = env)))]
    if (length(df_objs) == 0) stop("No data.frame found in: ", path)
    if (length(df_objs) > 1)
      cli::cli_alert_warning("Multiple data.frames found, using first: {df_objs[1]}")
    return(get(df_objs[1], envir = env))
  } else if (ext == "rds") {
    return(readRDS(path))
  } else if (ext == "csv") {
    return(read.csv(path, stringsAsFactors = FALSE))
  } else if (ext %in% c("xlsx", "xls")) {
    if (!requireNamespace("readxl", quietly = TRUE)) stop("Package 'readxl' required")
    return(as.data.frame(readxl::read_excel(path)))
  } else {
    stop("Unsupported file format: ", ext)
  }
}


# ── 保存结果到 ctx 并写出文件 ─────────────────────────────────────────────────
save_result <- function(ctx, name, object, filename) {
  ctx$results[[name]] <- object
  # 若 filename 已是绝对路径则直接使用，否则拼接 output_dir
  out_path <- if (
    !is.null(filename) && nzchar(filename) &&
    (startsWith(filename, "/") || grepl("^[A-Za-z]:[/\\\\]", filename))
  ) filename else file.path(ctx$output_dir, filename)
  ext <- tolower(tools::file_ext(filename))
  tryCatch({
    if (ext %in% c("rdata", "rda")) {
      save(list = "object", file = out_path, envir = environment())
    } else if (ext == "rds") {
      saveRDS(object, out_path)
    } else if (ext == "csv") {
      write.csv(object, out_path, row.names = FALSE)
    }
    cli::cli_alert_success("Saved: {.file {filename}}")
  }, error = function(e) {
    cli::cli_alert_warning("Save failed ({filename}): {e$message}")
  })
  ctx
}

#' 从 block_feature_selection 写出的清单读入特征（及可选的分模型列表），写入 ctx$results。
#' RDS 结构：list(features=..., feature_selection_by_model=..., ...)，见 block_feature_selection 持久化。
#' @param path 若非 NULL，仅尝试该文件；否则按 config$ml_models$feature_selection_rds、输出根、checkpoints 顺序探测。
load_feature_selection_final_into_ctx <- function(ctx, path = NULL) {
  ml <- ctx$config$ml_models %||% list()
  cands <- character(0)
  if (!is.null(path) && nzchar(trimws(as.character(path)[1L]))) {
    cands <- c(trimws(as.character(path)[1L]), cands)
  }
  mp <- ml$feature_selection_rds %||% NULL
  if (!is.null(mp) && nzchar(trimws(as.character(mp)[1L]))) {
    cands <- c(trimws(as.character(mp)[1L]), cands)
  }
  ro <- ctx$root_output_dir %||% ""
  od <- ctx$config$project$output_dir %||% ""
  ck <- (ctx$config$checkpoint %||% list())$dir %||% "checkpoints"
  ck <- trimws(as.character(ck)[1L])
  ck_dir <- if (grepl("^(/|[A-Za-z]:[/\\\\])", ck)) ck else file.path(getwd(), ck)
  fn <- "feature_selection_final.rds"
  cands <- c(
    cands,
    file.path(ro, fn),
    file.path(od, fn),
    file.path(ck_dir, fn),
    file.path(getwd(), "checkpoints", fn)
  )
  cands <- unique(cands[nzchar(trimws(cands))])
  for (p0 in cands) {
    p <- tryCatch(normalizePath(p0, winslash = "/", mustWork = FALSE), error = function(e) p0)
    if (!isTRUE(file.exists(p))) next
    obj <- tryCatch(readRDS(p), error = function(e) NULL)
    if (is.null(obj)) next
    feats <- obj$features %||% obj$feature_selection_final %||% character(0)
    feats <- as.character(feats)
    feats <- feats[nzchar(feats)]
    if (!length(feats)) next
    ctx$results$feature_selection_final <- feats
    if (!is.null(obj$feature_selection_by_model)) {
      ctx$results$feature_selection_by_model <- obj$feature_selection_by_model
    }
    if (!is.null(obj$feature_selection_methods_used)) {
      ctx$results$feature_selection_methods_used <- obj$feature_selection_methods_used
    }
    if (!is.null(obj$feature_selection_methods_selected)) {
      ctx$results$feature_selection_methods_selected <- obj$feature_selection_methods_selected
    }
    if (!is.null(obj$selection_source)) {
      ctx$results$feature_selection_selection_source <- obj$selection_source
    }
    if (!is.null(obj$feature_selection_venn_input)) {
      ctx$results$feature_selection_venn_input <- obj$feature_selection_venn_input
    }
    if (!is.null(obj$feature_selection_vote_df)) {
      ctx$results$feature_selection_vote_df <- obj$feature_selection_vote_df
    }
    if (!is.null(obj$feature_selection_method_summary)) {
      ctx$results$feature_selection_method_summary <- obj$feature_selection_method_summary
    }
    ctx$results$Model2Factors <- feats
    ctx$results$ml_feature_names <- feats
    cli::cli_alert_info("已从 {.file {p}} 载入最终特征（n={length(feats)}）。")
    return(ctx)
  }
  ctx
}


# ── 发表表/图自动编号（仅 Table n / Figure n / Table Sn / Figure Sn）────────────
# main_table:  Table 1, 2, 3…（按流水线产出顺序）
# main_figure: Figure 2, 3, 4…（Figure 1 预留给流程图；计数器初值 1，首次 +1 得 2）
# supp_table:  Table S1, S2, S3…
# supp_figure: Figure S1, S2, S3…
# 非标准名（Table_xxx、Figure S2A、VIF_check.csv 等）勿调用下列函数。

# 使用全局 environment 存计数（R 对 list 形 ctx$log 的嵌套赋值会 copy-on-write，函数内无法写回）
.pub_state <- new.env(parent = emptyenv())

.pub_counters_default <- function() {
  list(main_table = 0L, main_figure = 1L, supp_table = 0L, supp_figure = 0L)
}

.pub_counters_snapshot <- function() {
  list(
    main_table  = as.integer(.pub_state$main_table  %||% 0L),
    main_figure = as.integer(.pub_state$main_figure %||% 1L),
    supp_table  = as.integer(.pub_state$supp_table  %||% 0L),
    supp_figure = as.integer(.pub_state$supp_figure %||% 0L)
  )
}

.pub_counters_restore <- function(snap) {
  d <- .pub_counters_default()
  if (!is.null(snap) && is.list(snap)) d <- utils::modifyList(d, snap)
  .pub_state$main_table  <- as.integer(d$main_table)
  .pub_state$main_figure <- as.integer(d$main_figure)
  .pub_state$supp_table  <- as.integer(d$supp_table)
  .pub_state$supp_figure <- as.integer(d$supp_figure)
  invisible(d)
}

pub_reset_counters <- function(ctx = NULL) {
  .pub_counters_restore(.pub_counters_default())
  if (!is.null(ctx)) {
    ctx$log$pub_counters <- .pub_counters_snapshot()
    ctx
  } else {
    invisible(.pub_counters_snapshot())
  }
}

pub_next_id <- function(ctx = NULL, kind) {
  kind <- match.arg(kind, c("main_table", "main_figure", "supp_table", "supp_figure"))
  if (!exists("main_table", envir = .pub_state, inherits = FALSE)) {
    .pub_counters_restore(.pub_counters_default())
  }
  id <- switch(kind,
    main_table = {
      .pub_state$main_table <- as.integer(.pub_state$main_table %||% 0L) + 1L
      .pub_state$main_table
    },
    main_figure = {
      .pub_state$main_figure <- as.integer(.pub_state$main_figure %||% 1L) + 1L
      .pub_state$main_figure
    },
    supp_table = {
      .pub_state$supp_table <- as.integer(.pub_state$supp_table %||% 0L) + 1L
      .pub_state$supp_table
    },
    supp_figure = {
      .pub_state$supp_figure <- as.integer(.pub_state$supp_figure %||% 0L) + 1L
      .pub_state$supp_figure
    }
  )
  if (!is.null(ctx)) {
    ctx$log$pub_counters <- .pub_counters_snapshot()
  }
  id
}

pub_prefix <- function(kind, id) {
  switch(match.arg(kind, c("main_table", "main_figure", "supp_table", "supp_figure")),
    main_table = paste0("Table ", id, "."),
    main_figure = paste0("Figure ", id, "."),
    supp_table = paste0("Table S", id, "."),
    supp_figure = paste0("Figure S", id, ".")
  )
}

#' 文件名追加 Train/Validation 槽标签（表/图 caption 内文不改，仅 filepath）
.pub_path_with_slot_label <- function(ctx, path_or_name) {
  label <- tryCatch(
    as.character((ctx$config$pub %||% list())$slot_label %||% "")[1L],
    error = function(e) ""
  )
  if (!nzchar(label)) return(path_or_name)
  if (grepl("\\(Train\\)|\\(Validation\\)", path_or_name)) return(path_or_name)
  has_dir <- grepl("[/\\\\]", path_or_name)
  bn <- if (has_dir) basename(path_or_name) else path_or_name
  dn <- if (has_dir) dirname(path_or_name) else ""
  ext <- tools::file_ext(bn)
  base <- if (nzchar(ext)) sub(paste0("\\.", ext, "$"), "", bn, ignore.case = TRUE) else bn
  new_bn <- if (nzchar(ext)) paste0(base, " (", label, ").", ext) else paste0(base, " (", label, ")")
  if (has_dir && nzchar(dn) && dn != ".") file.path(dn, new_bn) else new_bn
}

# 发表 xlsx 文件名上限（含 .xlsx）。
# 上限提高以保住疾病名等关键信息（"…and Diabetic retinopathy" 不再被截成 "…and Diabetic"）。
# 完整路径另有 .truncate_filepath_for_max_path（250）兜底 Windows MAX_PATH。
pub_table_max_filename_n <- function() 150L

# 去掉括号段（半角/全角）；保留末尾 Train/Validation / training|validation set 槽标签
pub_caption_strip_parentheses <- function(s, keep_slot = TRUE) {
  s <- as.character(s %||% "")[1L]
  if (!nzchar(s)) return(s)
  slot <- ""
  if (isTRUE(keep_slot)) {
    ## 优先保留 training / (internal|external) validation set（含可选 n=）
    .slot_re <- paste0(
      "\\(((?:internal|external)\\s+)?(training|validation)\\s+set",
      "(?:,\\s*n\\s*=\\s*[0-9]+)?\\)\\s*$"
    )
    if (grepl(.slot_re, s, ignore.case = TRUE, perl = TRUE)) {
      m <- regmatches(s, regexpr(.slot_re, s, ignore.case = TRUE, perl = TRUE))
      slot <- paste0(" ", trimws(m))
      s <- sub(paste0("\\s*", .slot_re), "", s, ignore.case = TRUE, perl = TRUE)
    } else if (grepl("\\((Train|Validation)\\)\\s*$", s, ignore.case = TRUE, perl = TRUE)) {
      m <- regmatches(
        s,
        regexpr("\\((Train|Validation)\\)\\s*$", s, ignore.case = TRUE, perl = TRUE)
      )
      slot <- paste0(" ", trimws(m))
      s <- sub("\\s*\\((Train|Validation)\\)\\s*$", "", s, ignore.case = TRUE, perl = TRUE)
    }
  }
  s <- gsub("\\([^)]*\\)", "", s)
  s <- gsub("（[^）]*）", "", s)
  s <- gsub("\\s+", " ", s)
  paste0(trimws(s), slot)
}

# 将表文件 stem 压到 max_n（含 .ext）；超长时优先保住疾病名（截断中段、保留结尾）
pub_fit_table_stem <- function(stem, ext = "xlsx", max_n = NULL,
                               disease = NULL) {
  stem <- pub_caption_strip_parentheses(as.character(stem %||% "")[1L])
  ext <- sub("^\\.", "", as.character(ext %||% "xlsx")[1L])
  max_n <- as.integer(max_n %||% pub_table_max_filename_n())[1L]
  if (!is.finite(max_n) || max_n < 24L) max_n <- 76L
  budget <- max_n - nchar(ext, type = "chars") - 1L
  if (nchar(stem, type = "chars") <= budget) return(stem)
  cut <- substr(stem, 1L, budget)
  sp <- gregexpr(" ", cut, fixed = TRUE)[[1L]]
  if (length(sp) && sp[[1L]] > 0L && max(sp) >= 24L) {
    cut <- substr(cut, 1L, max(sp) - 1L)
  }
  trimmed <- sub("[ .,-]+$", "", trimws(cut))
  # 疾病名保护：结尾的疾病名被截掉时，压缩中段、保留 "and <disease>" 结尾
  dis <- trimws(as.character(disease %||% "")[1L])
  if (nzchar(dis) && grepl(dis, stem, fixed = TRUE)) {
    tail_txt <- paste0(" and ", dis)
    if (grepl(tail_txt, stem, fixed = TRUE)) {
      head_room <- budget - nchar(tail_txt, type = "chars")
      if (head_room >= 24L) {
        head_txt <- substr(stem, 1L, head_room)
        sp2 <- gregexpr(" ", head_txt, fixed = TRUE)[[1L]]
        if (length(sp2) && sp2[[1L]] > 0L && max(sp2) >= 20L) {
          head_txt <- substr(head_txt, 1L, max(sp2) - 1L)
        }
        cand <- paste0(sub("[ .,-]+$", "", trimws(head_txt)), tail_txt)
        if (nchar(cand, type = "chars") <= budget) return(cand)
      }
    }
  }
  trimmed
}

# 发病/预后 GLM 主表与 RCS 附表短标题（无括号）
logistic_glm_pub_caption <- function(ix_disp, disease_disp = NULL,
                                     scheme = "quartile",
                                     is_rcs = FALSE,
                                     unweighted = FALSE,
                                     native_levels = FALSE) {
  ix_disp <- gsub("_", " ", trimws(as.character(ix_disp %||% "")[1L]))
  if (!nzchar(ix_disp)) ix_disp <- "index"
  scheme <- tolower(trimws(as.character(scheme %||% "quartile")[1L]))
  if (isTRUE(is_rcs)) {
    return(sprintf("Logistic regression of %s RCS cutoff", ix_disp))
  }
  if (isTRUE(native_levels) || identical(scheme, "categorical")) {
    scheme <- ""
  }
  if (isTRUE(unweighted) && nzchar(scheme)) {
    return(sprintf(
      "Sensitivity analysis: Logistic regression of %s %s (GLM, unweighted)",
      ix_disp, scheme
    ))
  }
  if (nzchar(scheme)) {
    return(sprintf("Logistic regression of %s %s", ix_disp, scheme))
  }
  sprintf("Logistic regression of %s", ix_disp)
}

pub_title <- function(ctx, kind, caption = "") {
  id <- pub_next_id(ctx, kind)
  pref <- pub_prefix(kind, id)
  cap <- pub_caption_strip_parentheses(trimws(as.character(caption %||% "")))
  if (nzchar(cap)) paste(pref, cap) else pref
}

pub_filepath <- function(ctx, dir, kind, caption, ext) {
  title <- pub_title(ctx, kind, caption)
  fp <- .inject_db_into_pub_filepath(file.path(dir, paste0(title, ".", ext)))
  .pub_path_with_slot_label(ctx, fp)
}

pub_paths <- function(ctx, dir, kind, caption, ext) {
  title <- pub_title(ctx, kind, caption)
  fp <- .inject_db_into_pub_filepath(file.path(dir, paste0(title, ".", ext)))
  fp <- .pub_path_with_slot_label(ctx, fp)
  list(title = title, filepath = fp)
}

# 同一编号，表头与文件名使用不同描述（如 S2 表头=Cox…，文件名=Univariate…）
pub_pair <- function(ctx, dir, kind, title_caption, file_caption, ext) {
  id <- pub_next_id(ctx, kind)
  pref <- pub_prefix(kind, id)
  cap_t <- trimws(as.character(title_caption %||% ""))
  cap_f <- trimws(as.character(file_caption %||% ""))
  title <- if (nzchar(cap_t)) paste(pref, cap_t) else pref
  stem_f <- if (nzchar(cap_f)) paste(pref, cap_f) else pref
  filepath <- .inject_db_into_pub_filepath(file.path(dir, paste0(stem_f, ".", ext)))
  filepath <- .pub_path_with_slot_label(ctx, filepath)
  list(title = title, filepath = filepath, id = id)
}

pub_figure_file <- function(ctx, kind, caption, ext = "pdf") {
  title <- pub_title(ctx, kind, caption)
  fn <- .pub_figure_filename(.inject_db_into_pub_label(paste0(title, ".", ext), sanitize_for_file = TRUE))
  .pub_path_with_slot_label(ctx, fn)
}

#' 是否旁路导出 SVG（Illustrator）。默认 FALSE：只保留 PDF。
#' 打开：config$project$export_figure_svg = TRUE
pub_export_figure_svg <- function(ctx = NULL) {
  prj <- if (is.null(ctx)) list() else (ctx$config$project %||% list())
  isTRUE(prj$export_figure_svg %||% FALSE)
}

#' 将 main_figure 计数器至少推进到指定编号（固定 Figure 4 等场景）
pub_bump_main_figure_min <- function(min_id) {
  min_id <- as.integer(min_id)[1L]
  if (!is.finite(min_id) || min_id < 1L) return(invisible(NULL))
  cur <- as.integer(.pub_state$main_figure %||% 1L)
  if (cur < min_id) .pub_state$main_figure <- min_id
  invisible(.pub_state$main_figure)
}

#' 将 supp_table 计数器至少推进到指定编号（固定 Table S7 等场景）
pub_bump_supp_table_min <- function(min_id) {
  min_id <- as.integer(min_id)[1L]
  if (!is.finite(min_id) || min_id < 1L) return(invisible(NULL))
  cur <- as.integer(.pub_state$supp_table %||% 0L)
  if (cur < min_id) .pub_state$supp_table <- min_id
  invisible(.pub_state$supp_table)
}

#' 将 supp_figure 计数器至少推进到指定编号（固定 Figure S1 等场景）
pub_bump_supp_figure_min <- function(min_id) {
  min_id <- as.integer(min_id)[1L]
  if (!is.finite(min_id) || min_id < 1L) return(invisible(NULL))
  cur <- as.integer(.pub_state$supp_figure %||% 0L)
  if (cur < min_id) .pub_state$supp_figure <- min_id
  invisible(.pub_state$supp_figure)
}

#' 固定 Figure / Figure S 编号出图（默认同步计数器，避免后续图号倒退）
#' @param kind "main_figure" → Figure N；"supp_figure" → Figure SN
pub_figure_filepath_at <- function(fig_dir, figure_id, caption, ext = "pdf",
                                   bump_counter = TRUE,
                                   kind = c("main_figure", "supp_figure")) {
  kind <- match.arg(kind)
  figure_id <- as.integer(figure_id)[1L]
  if (!is.finite(figure_id) || figure_id < 1L) {
    stop("pub_figure_filepath_at: figure_id 须为正整数。")
  }
  if (isTRUE(bump_counter)) {
    if (identical(kind, "supp_figure")) pub_bump_supp_figure_min(figure_id)
    else pub_bump_main_figure_min(figure_id)
  }
  pref <- pub_prefix(kind, figure_id)
  cap <- trimws(as.character(caption %||% ""))
  stem <- if (nzchar(cap)) paste(pref, cap) else pref
  fn <- .pub_figure_filename(
    .inject_db_into_pub_label(paste0(stem, ".", ext), sanitize_for_file = TRUE)
  )
  file.path(fig_dir, fn)
}

# 固定编号出图但带 slot 标签时调用（ctx 可选；无 ctx 则原样）
pub_figure_filepath_at_slot <- function(ctx, fig_dir, figure_id, caption, ext = "pdf",
                                        bump_counter = TRUE,
                                        kind = c("main_figure", "supp_figure")) {
  fp <- pub_figure_filepath_at(
    fig_dir, figure_id, caption, ext = ext,
    bump_counter = bump_counter, kind = kind
  )
  if (is.null(ctx)) return(fp)
  .pub_path_with_slot_label(ctx, fp)
}

# 发表用图文件名：Fig → Figure；文件名中下划线改为空格（与表格展示一致）
.pub_figure_filename <- function(filename) {
  fn <- as.character(filename %||% "")
  if (!nzchar(fn)) return(fn)
  bn <- basename(fn)
  dn <- dirname(fn)
  bn <- gsub("_", " ", bn, fixed = TRUE)
  bn <- sub("^Fig(?=[ _\\.0-9S])", "Figure", bn, perl = TRUE)
  if (nzchar(dn) && dn != ".") file.path(dn, bn) else bn
}

# 解析可在当前 PDF 设备上使用的 Times 系字体（WSL/Linux 常无 "Times New Roman"）
# 有 cairo 时优先返回系统 "Times New Roman"（cairo_pdf 可嵌 TrueType）；
# 仅标准 pdf() 时再探测 pdfFonts / Nimbus / serif 回退。
resolve_plot_font_family <- function(preferred = "Times New Roman") {
  pref0 <- as.character(preferred %||% "Times New Roman")[1L]
  if (!nzchar(pref0)) pref0 <- "Times New Roman"
  times_like <- tolower(pref0) %in% c("times new roman", "times", "serif", "nimbus roman")
  # cairo 必须实测：仅 capabilities("cairo") 不够；缺字时会 PostScript/invalid font 写出空壳 PDF
  if (isTRUE(capabilities("cairo"))) {
    cairo_cands <- if (times_like) {
      c(
        "Times New Roman", "Liberation Serif", "DejaVu Serif", "FreeSerif",
        "Nimbus Roman", "serif"
      )
    } else {
      c(pref0, "serif", "sans")
    }
    cairo_cands <- unique(cairo_cands[nzchar(cairo_cands)])
    for (ff in cairo_cands) {
      ok <- tryCatch({
        tmp <- tempfile(fileext = ".pdf")
        on.exit(unlink(tmp), add = TRUE)
        suppressWarnings({
          grDevices::cairo_pdf(tmp, width = 2, height = 2, family = ff)
          grid::grid.text("Mg", gp = grid::gpar(fontfamily = ff, fontsize = 12))
          grDevices::dev.off()
        })
        isTRUE(file.info(tmp)$size > 1500)
      }, error = function(e) FALSE)
      if (isTRUE(ok)) return(ff)
    }
  }
  prefs <- unique(c(
    if (times_like) "Times" else pref0,
    pref0,
    "Times New Roman", "Times", "Nimbus Roman", "serif"
  ))
  prefs <- prefs[nzchar(prefs)]
  pdf_fonts <- tryCatch(names(grDevices::pdfFonts()), error = function(e) character(0))
  if (length(pdf_fonts)) {
    mapped <- character(0)
    for (ff in prefs) {
      if (ff %in% pdf_fonts) {
        mapped <- c(mapped, ff)
      } else if (ff %in% c("Times New Roman", "Times New RomanPSMT") && "Times" %in% pdf_fonts) {
        mapped <- c(mapped, "Times")
      } else if (ff %in% c("serif", "sans", "mono", "Times", "Helvetica", "Courier")) {
        mapped <- c(mapped, ff)
      }
    }
    prefs <- unique(c(mapped, "serif"))
  }
  for (ff in prefs) {
    ok <- tryCatch({
      tmp <- tempfile(fileext = ".pdf")
      on.exit(unlink(tmp), add = TRUE)
      suppressWarnings({
        # 标准 pdf() 不认 "Times New Roman"（PostScript DB）→ 一律落到 Times/serif
        ff_dev <- if (identical(ff, "Times New Roman")) "Times" else ff
        grDevices::pdf(tmp, family = ff_dev, width = 2, height = 2)
        grid::grid.text("Mg", gp = grid::gpar(fontfamily = ff_dev, fontsize = 12))
        grDevices::dev.off()
      })
      TRUE
    }, error = function(e) FALSE)
    if (isTRUE(ok)) {
      return(if (identical(ff, "Times New Roman")) "Times" else ff)
    }
  }
  "serif"
}

# 从 config$plot$font_family 读取并解析为当前设备可用字体
plot_font_from_config <- function(cfg) {
  resolve_plot_font_family((cfg$plot %||% list())$font_family %||% "Times New Roman")
}

# 图轴/图注展示名：字典名 + 去下划线（数据列名仍用 De_Ritis）
pipeline_plot_axis_label <- function(var, cfg = NULL) {
  lab <- if (exists("pipeline_var_display_name", mode = "function")) {
    pipeline_var_display_name(var, cfg)
  } else {
    as.character(var %||% "")[1L]
  }
  if (exists("pipeline_display_no_underscore", mode = "function")) {
    return(pipeline_display_no_underscore(lab)[1L])
  }
  gsub("_", " ", as.character(lab)[1L], fixed = TRUE)
}

# 分类轴刻度：因子水平去下划线（Non_ASCVD → Non ASCVD）；数据水平名不变
pipeline_factor_tick_labels <- function(levels) {
  lv <- as.character(levels %||% character(0))
  if (!length(lv)) return(character(0))
  if (exists("pipeline_display_no_underscore", mode = "function")) {
    return(as.character(pipeline_display_no_underscore(lv)))
  }
  gsub("_", " ", lv, fixed = TRUE)
}

# ggplot 发表 PDF：cairo 嵌入 Times New Roman（勿用无 family 的 cairo_pdf，否则像默认衬线而非新罗马）
pipeline_ggsave_pdf <- function(filename, plot, width, height, family = NULL, cfg = NULL) {
  ff <- as.character(family %||% "")[1L]
  if (!nzchar(ff)) {
    ff <- if (exists("plot_font_from_config", mode = "function")) {
      plot_font_from_config(cfg %||% list())
    } else {
      "Times New Roman"
    }
  }
  ggplot2::ggsave(
    filename = filename,
    plot = plot,
    width = width,
    height = height,
    device = function(filename, width, height, ...) {
      if (exists("pipeline_pdf_device", mode = "function")) {
        pipeline_pdf_device(filename, width = width, height = height, family = ff)
      } else if (isTRUE(capabilities("cairo"))) {
        grDevices::cairo_pdf(filename, width = width, height = height, family = ff)
      } else {
        grDevices::pdf(filename, width = width, height = height, family = "Times")
      }
    }
  )
  invisible(filename)
}

# 打开发表 PDF：有 cairo 用 cairo_pdf 嵌 Times New Roman；
# 否则用 pdf() + Times/serif。禁止对 pdf() 传 "Times New Roman"（Linux 报 unknown family）。
pipeline_pdf_device <- function(path, width, height, family = "Times New Roman") {
  path <- as.character(path)[1L]
  family <- as.character(family %||% "Times New Roman")[1L]
  if (!nzchar(family)) family <- "Times New Roman"
  # 优先用已探测可用的 family（resolve_plot_font_family）；勿再强行改回 Times New Roman
  ff <- if (exists("resolve_plot_font_family", mode = "function")) {
    resolve_plot_font_family(family)
  } else {
    family
  }
  if (isTRUE(capabilities("cairo"))) {
    grDevices::cairo_pdf(path, width = width, height = height, family = ff)
    return(invisible(ff))
  }
  if (identical(ff, "Times New Roman")) ff <- "Times"
  grDevices::pdf(path, width = width, height = height, family = ff)
  invisible(ff)
}

#' 按 Ghostscript 内容 bbox 裁切 PDF 白边（保留矢量/可编辑文字）
#' @param path PDF 路径（原地覆盖）
#' @param pad_pt 内容外额外留白（pt）
#' @return TRUE/FALSE
pdf_trim_whitespace <- function(path, pad_pt = 6) {
  path <- as.character(path)[1L]
  if (!nzchar(path) || !file.exists(path)) return(FALSE)
  py <- Sys.which("python3")
  if (!nzchar(py)) py <- Sys.which("python")
  if (!nzchar(py)) return(FALSE)
  if (!nzchar(Sys.which("gs"))) return(FALSE)
  script <- NULL
  cand <- c(
    file.path(dirname(path), "pdf_trim_whitespace.py"),
    file.path(getwd(), "R", "pdf_trim_whitespace.py"),
    file.path(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""), "R", "pdf_trim_whitespace.py"),
    "/mnt/e/01block/01Block-new-Final/R/pdf_trim_whitespace.py"
  )
  for (p in unique(cand[nzchar(as.character(cand))])) {
    if (file.exists(p)) {
      script <- p
      break
    }
  }
  if (is.null(script)) return(FALSE)
  pad_pt <- as.numeric(pad_pt)[1L]
  if (!is.finite(pad_pt) || pad_pt < 0) pad_pt <- 6
  cmd <- paste(
    shQuote(c(py, script, path, "-o", path, "--pad-pt", as.character(pad_pt)), type = "sh"),
    collapse = " "
  )
  st <- tryCatch(system(cmd, intern = TRUE), error = function(e) e)
  status <- attr(st, "status")
  is.null(status) || identical(as.integer(status), 0L)
}

# ── 保存图形到 output_dir/Figures ─────────────────────────────────────────────
# 所有图统一使用 Times New Roman 字体（PDF 内嵌；不可用时 resolve_plot_font_family 回退 Times）
save_figure <- function(ctx, filename, plot_fn, width = 10, height = 7) {
  filename <- .pub_figure_filename(.inject_db_into_pub_label(filename, sanitize_for_file = TRUE))
  q <- ctx$results$figure_queue %||% list()
  q[[length(q) + 1L]] <- list(
    filename = filename,
    plot_fn  = plot_fn,
    width    = width,
    height   = height
  )
  ctx$results$figure_queue <- q
  cli::cli_alert_info("Queued figure task: {.file {filename}}")
  ctx
}

# 根目录 / 库级 Tables 为发表汇总：不写 .tex（LaTeX 仅留在 step*/Tables）
pipeline_is_aggregate_pub_tables_path <- function(path) {
  path <- as.character(path %||% "")[1L]
  if (!nzchar(path)) return(FALSE)
  # .../step12_xxx/Tables/... → 非汇总
  if (grepl("(^|[/\\\\])step\\d+_", path, ignore.case = TRUE, perl = TRUE)) {
    return(FALSE)
  }
  grepl("(^|[/\\\\])Tables([/\\\\]|$)", path, ignore.case = TRUE, perl = TRUE)
}

pipeline_purge_aggregate_tex <- function(tables_dir, label = "汇总 Tables") {
  tables_dir <- as.character(tables_dir %||% "")[1L]
  if (!nzchar(tables_dir) || !dir.exists(tables_dir)) return(invisible(0L))
  # 只清直接位于该 Tables 目录的 .tex，不递归进 step
  stale <- list.files(tables_dir, pattern = "\\.tex$", full.names = TRUE, ignore.case = TRUE)
  if (!length(stale)) return(invisible(0L))
  unlink(stale)
  cli::cli_alert_info("已清理{label}中 {length(stale)} 个 .tex")
  invisible(length(stale))
}

# 将 step 子目录下已落盘的表/图复制到 <output_dir>/Tables 或 /Figures（config$project$mirror_pub_outputs_to_root）
# 根目录 Tables 仅镜像 xlsx；tex 仍保留在各 step 子目录 Tables 中
mirror_pub_output_to_root <- function(ctx, src_path) {
  if (is.null(ctx) || !is.list(ctx)) return(invisible(FALSE))
  prj <- ctx$config$project %||% list()
  if (!isTRUE(prj$mirror_pub_outputs_to_root %||% FALSE)) return(invisible(FALSE))
  src_path <- as.character(src_path)[1L]
  if (!nzchar(src_path) || !file.exists(src_path)) return(invisible(FALSE))
  root <- ctx$root_output_dir %||% NULL
  if (is.null(root) || !nzchar(root)) return(invisible(FALSE))

  ext <- tolower(tools::file_ext(src_path))
  if (identical(ext, "tex")) return(invisible(FALSE))
  # 根目录 Tables 只收发表 xlsx（Table N / Table S / Supplementary）；中间 csv 不镜像
  if (identical(ext, "csv")) return(invisible(FALSE))
  if (identical(ext, "xlsx")) {
    bn <- basename(src_path)
    # ROC 数值表留在 step 子目录，不进发表 Tables
    if (grepl("ROC", bn, ignore.case = TRUE)) return(invisible(FALSE))
    pub_xlsx <- grepl(
      "^(Table [0-9]|Table S[0-9]|Supplementary Material)",
      bn, ignore.case = TRUE, perl = TRUE
    )
    if (!pub_xlsx) return(invisible(FALSE))
  }
  dest_sub <- switch(ext,
    xlsx = "Tables",
    pdf = "Figures", png = "Figures", jpg = "Figures", jpeg = "Figures",
    # SVG 仅留在 step 子目录，不进汇总 Figures/
    svg = NULL,
    NULL
  )
  if (is.null(dest_sub)) return(invisible(FALSE))

  dest_dir <- file.path(root, dest_sub)
  if (!dir.exists(dest_dir)) dir.create(dest_dir, recursive = TRUE)
  dest_path <- file.path(dest_dir, basename(src_path))
  src_norm <- tryCatch(normalizePath(src_path, winslash = "/", mustWork = TRUE), error = function(e) src_path)
  dest_norm <- tryCatch(
    normalizePath(dest_path, winslash = "/", mustWork = FALSE),
    error = function(e) dest_path
  )
  if (identical(src_norm, dest_norm)) return(invisible(FALSE))

  ok <- tryCatch(file.copy(src_path, dest_path, overwrite = TRUE), error = function(e) FALSE)
  if (isTRUE(ok)) {
    cli::cli_alert_info("Mirrored to root: {.file {file.path(dest_sub, basename(src_path))}}")
  }
  invisible(isTRUE(ok))
}

# 渲染当前尚未落盘的发表表/图队列（export_sci_table / save_figure 入队项）
flush_pub_output_queues <- function(ctx) {
  if (is.null(ctx) || !is.list(ctx)) return(invisible(ctx))
  if (length(.table_queue_env$items %||% list()) > 0L &&
      exists("render_queued_tables", mode = "function")) {
    ctx <- render_queued_tables(ctx)
  }
  if (length(ctx$results$figure_queue %||% list()) > 0L &&
      exists("render_queued_figures", mode = "function")) {
    ctx <- render_queued_figures(ctx)
  }
  invisible(ctx)
}

# 将当前 block 子目录 Tables/Figures 下已落盘发表文件镜像到 <root>/Tables|Figures
mirror_block_pub_outputs <- function(ctx) {
  if (is.null(ctx) || !is.list(ctx)) return(invisible(ctx))
  prj <- ctx$config$project %||% list()
  if (!isTRUE(prj$mirror_pub_outputs_to_root %||% FALSE)) return(invisible(ctx))
  block_dir <- ctx$output_dir %||% NULL
  if (is.null(block_dir) || !nzchar(block_dir) || !dir.exists(block_dir)) {
    return(invisible(ctx))
  }
  pub_pat_tables <- "\\.(xlsx|csv)$"
  # 汇总根目录不收 SVG（Illustrator 源文件留在各 step/Figures）
  pub_pat_figures <- "\\.(pdf|png|jpg|jpeg)$"
  for (sub in c("Tables", "Figures")) {
    src_dir <- file.path(block_dir, sub)
    if (!dir.exists(src_dir)) next
    pat <- if (identical(sub, "Tables")) pub_pat_tables else pub_pat_figures
    files <- list.files(src_dir, full.names = TRUE, pattern = pat, ignore.case = TRUE)
    for (f in files) mirror_pub_output_to_root(ctx, f)
  }
  invisible(ctx)
}

# 多个 step 子目录可能含同名发表文件；取修改时间最新的一份
pub_pick_latest_file <- function(paths) {
  paths <- unique(as.character(paths[nzchar(as.character(paths))]))
  paths <- paths[file.exists(paths)]
  if (!length(paths)) return(NA_character_)
  if (length(paths) == 1L) return(paths[[1L]])
  paths[which.max(file.info(paths)$mtime)]
}

# 按 step 目录名顺序，将各 block 子目录 Tables/Figures 汇总镜像到根目录（同名文件取 mtime 最新）
sync_all_block_pub_outputs_to_root <- function(ctx) {
  if (is.null(ctx) || !is.list(ctx)) return(invisible(ctx))
  prj <- ctx$config$project %||% list()
  if (!isTRUE(prj$mirror_pub_outputs_to_root %||% FALSE)) return(invisible(ctx))
  root <- ctx$root_output_dir %||% NULL
  if (is.null(root) || !nzchar(root) || !dir.exists(root)) return(invisible(ctx))

  step_dirs <- list.dirs(root, recursive = FALSE, full.names = TRUE)
  bn <- basename(step_dirs)
  step_dirs <- step_dirs[grepl("^step\\d+_", bn, ignore.case = TRUE)]
  if (!length(step_dirs)) return(invisible(ctx))
  step_dirs <- step_dirs[order(basename(step_dirs))]

  pub_pat_tables <- "\\.(xlsx|csv)$"
  # 汇总根目录不收 SVG
  pub_pat_figures <- "\\.(pdf|png|jpg|jpeg)$"
  n <- 0L
  latest_by_name <- list()
  root_tables <- file.path(root, "Tables")
  if (dir.exists(root_tables)) {
    stale_tex <- list.files(root_tables, pattern = "\\.tex$", full.names = TRUE, ignore.case = TRUE)
    if (length(stale_tex)) {
      unlink(stale_tex)
      cli::cli_alert_info("已清理根目录 Tables 中 {length(stale_tex)} 个 .tex 文件")
    }
  }
  root_figs <- file.path(root, "Figures")
  if (dir.exists(root_figs)) {
    stale_svg <- list.files(root_figs, pattern = "\\.svg$", full.names = TRUE, ignore.case = TRUE)
    if (length(stale_svg)) {
      unlink(stale_svg)
      cli::cli_alert_info("已清理根目录 Figures 中 {length(stale_svg)} 个 .svg 文件")
    }
  }
  for (block_dir in step_dirs) {
    for (sub in c("Tables", "Figures")) {
      src_dir <- file.path(block_dir, sub)
      if (!dir.exists(src_dir)) next
      pat <- if (identical(sub, "Tables")) pub_pat_tables else pub_pat_figures
      files <- list.files(src_dir, full.names = TRUE, pattern = pat, ignore.case = TRUE)
      for (f in files) {
        bn <- basename(f)
        prev <- latest_by_name[[bn]]
        if (is.null(prev) || file.info(f)$mtime > file.info(prev)$mtime) {
          latest_by_name[[bn]] <- f
        }
      }
    }
  }
  for (f in latest_by_name) {
    if (isTRUE(mirror_pub_output_to_root(ctx, f))) n <- n + 1L
  }
  if (n > 0L) {
    cli::cli_alert_info("已汇总镜像 {n} 个发表表/图到根目录 Tables/Figures")
  }
  invisible(ctx)
}

# ── 发表表/图自动重排序号（删表后下游顺延；文件名 + xlsx 内标题 + tex 标题）──
#' 解析发表文件名编号："Table S3-NHANES. xxx.xlsx" → list(kind="supp_table", id=3)
pub_parse_pub_number <- function(basename_str) {
  bn <- trimws(as.character(basename_str %||% "")[1L])
  m <- regmatches(
    bn,
    regexpr("^(Table|Figure)\\s+(S?)(\\d+)(\\s*-|\\s*\\.)", bn, perl = TRUE)
  )
  if (!length(m) || !nzchar(m)) return(NULL)
  kind_str <- sub("^(Table|Figure).*$", "\\1", m)
  is_s <- grepl("^(Table|Figure)\\s+S", m)
  id <- suppressWarnings(as.integer(sub("^.*?(\\d+)(\\s*-|\\s*\\.)$", "\\1", m)))
  if (!is.finite(id)) return(NULL)
  kind <- paste0(
    tolower(kind_str),
    if (is_s) "_supp" else "_main"
  )
  kind <- switch(
    kind,
    table_main = "main_table", table_supp = "supp_table",
    figure_main = "main_figure", figure_supp = "supp_figure",
    NULL
  )
  if (is.null(kind)) return(NULL)
  list(kind = kind, id = id)
}

#' 重排一个目录下发表文件的编号（缺号顺延）。
#' xlsx 标题首行同步更新；同名 .tex 同步重命名并更新 \\caption 标题。
#' 返回 list(moved = n_renamed, details = df)
pub_renumber_pub_dir <- function(dir, verbose = TRUE) {
  if (is.null(dir) || !nzchar(dir) || !dir.exists(dir)) {
    return(invisible(list(moved = 0L, details = NULL)))
  }
  exts <- "\\.(xlsx|pdf|png|jpg|jpeg)$"
  files <- list.files(dir, full.names = TRUE, pattern = exts, ignore.case = TRUE)
  files <- files[!dir.exists(files)]
  if (!length(files)) return(invisible(list(moved = 0L, details = NULL)))

  parsed <- lapply(basename(files), pub_parse_pub_number)
  ok <- !vapply(parsed, is.null, logical(1L))
  if (!any(ok)) return(invisible(list(moved = 0L, details = NULL)))

  items <- data.frame(
    path = files[ok],
    bn   = basename(files)[ok],
    kind = vapply(parsed[ok], `[[`, character(1L), "kind"),
    id   = vapply(parsed[ok], `[[`, integer(1L), "id"),
    stringsAsFactors = FALSE
  )
  # 每类内按原编号排序，缺号顺延压缩（同编号冲突时也强制重新分配）
  moved <- 0L
  details <- list()
  for (k in unique(items$kind)) {
    sub <- items[items$kind == k, , drop = FALSE]
    sub <- sub[order(sub$id, sub$bn), , drop = FALSE]
    if (!nrow(sub)) next
    new_ids <- seq_len(nrow(sub))
    # 如果同号有多个文件（冲突），或有编号间隔，都需要重排
    has_dup  <- any(duplicated(sub$id))
    needs    <- has_dup | (new_ids != sub$id)
    if (!any(needs)) next
    # 有冲突时全量重排，避免 rename 时目标已存在；需先用临时名
    for (i in seq_len(nrow(sub))) {
      if (!has_dup && !needs[i]) next
      old_bn <- sub$bn[i]
      new_id <- new_ids[i]
      pref_old <- regmatches(
        old_bn,
        regexpr("^(Table|Figure)\\s+(S?)(\\d+)(\\s*-|\\s*\\.)", old_bn, perl = TRUE)
      )
      pref_new <- .replace_first_num(pref_old, new_id)
      new_bn <- if (length(pref_old) && nzchar(pref_old)) {
        sub(pref_old, pref_new, old_bn, fixed = TRUE)
      } else next
      old_path <- sub$path[i]
      new_path <- file.path(dir, new_bn)
      if (!identical(old_path, new_path) && file.exists(old_path) &&
          !file.exists(new_path)) {
        ok_move <- tryCatch(file.rename(old_path, new_path), error = function(e) FALSE)
        if (isTRUE(ok_move)) {
          moved <- moved + 1L
          .pub_update_xlsx_title(new_path, pref_new)
          tex_old <- sub("\\.xlsx$", ".tex", old_path, ignore.case = TRUE)
          if (file.exists(tex_old)) {
            tex_new <- sub("\\.xlsx$", ".tex", new_path, ignore.case = TRUE)
            tryCatch(file.rename(tex_old, tex_new), error = function(e) NULL)
            .pub_update_tex_title(tex_new, pref_new)
          }
          details[[length(details) + 1L]] <-
            data.frame(from = old_bn, to = new_bn, stringsAsFactors = FALSE)
        }
      }
    }
  }
  if (moved > 0L && verbose && requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_info("发表编号重排：{moved} 个文件已顺延（{basename(dir)}）")
  }
  list(moved = moved, details = if (length(details)) do.call(rbind, details) else NULL)
}

.replace_first_num <- function(prefix, new_id) {
  sub(
    "(\\d+)",
    as.character(as.integer(new_id)),
    prefix,
    perl = TRUE
  )
}

#' 更新 xlsx 首行标题中的编号前缀（如 "Table S3." → "Table S5."）
.pub_update_xlsx_title <- function(xlsx_path, new_prefix) {
  if (!requireNamespace("openxlsx", quietly = TRUE)) return(invisible(FALSE))
  ok <- tryCatch({
    cell_val <- as.character(
      openxlsx::read.xlsx(xlsx_path, sheet = 1L, colNames = FALSE,
                          rows = 1L, cols = 1L)[1L, 1L]
    )
    if (!is.na(cell_val) && nzchar(cell_val)) {
      cell_new <- sub(
        "^(Table|Figure)\\s+S?\\d+(\\s*-|\\s*\\.)",
        new_prefix,
        cell_val,
        perl = TRUE
      )
      if (!identical(cell_new, cell_val)) {
        wb <- openxlsx::loadWorkbook(xlsx_path)
        sh <- names(wb)[1L]
        openxlsx::writeData(wb, sheet = sh, x = cell_new,
                            startCol = 1L, startRow = 1L, colNames = FALSE)
        openxlsx::saveWorkbook(wb, xlsx_path, overwrite = TRUE)
      }
    }
    TRUE
  }, error = function(e) FALSE)
  invisible(ok)
}

#' 更新 tex 文件 \\caption{} / 首个注释标题中的编号前缀
.pub_update_tex_title <- function(tex_path, new_prefix) {
  if (!file.exists(tex_path)) return(invisible(FALSE))
  lines <- readLines(tex_path, warn = FALSE, encoding = "UTF-8")
  hit <- grepl("^(Table|Figure)\\s+S?\\d+\\s*\\.", lines, perl = TRUE) |
    grepl("\\\\caption\\{\\s*(Table|Figure)\\s+S?\\d+\\s*\\.", lines, perl = TRUE)
  if (!any(hit)) return(invisible(FALSE))
  lines[hit] <- sub(
    "(Table|Figure)(\\s+)S?\\d+(\\s*\\.)",
    paste0("\\1\\2", sub("^.*?([0-9]+)\\s*\\.$", "S\\1.", new_prefix)),
    lines[hit],
    perl = TRUE
  )
  # 规范化：新前缀本身已含点
  lines[hit] <- sub(
    "(Table|Figure)\\s+S?\\d+\\s*\\.",
    new_prefix,
    lines[hit],
    perl = TRUE
  )
  tryCatch(writeLines(lines, tex_path, useBytes = TRUE), error = function(e) NULL)
  invisible(TRUE)
}



# ── 多因素发表表：是否保留单因素列（默认不保留，全流水线复用）──────────────
#' 多因素 Table S* 是否包含 OR/HR (univariable) 列
#'
#' 默认 FALSE。可在 config$multivariate_*$include_univariable_column 或
#' config$publication$multivariate_include_univariable_column = TRUE 打开。
multivariate_pub_include_univariable_column <- function(cfg) {
  cfg <- cfg %||% list()
  keys <- c(
    "multivariate_nhanes",
    "multivariate_nhanes_harmonized",
    "multivariate_incidence_binary",
    "multivariate_incidence_harmonized",
    "multivariate_prognosis",
    "multivariate_prognosis_harmonized",
    "multivariate_incidence_multiclass",
    "multivariate"
  )
  for (k in keys) {
    v <- (cfg[[k]] %||% list())$include_univariable_column
    if (!is.null(v)) return(isTRUE(v))
  }
  v2 <- (cfg$publication %||% list())$multivariate_include_univariable_column
  if (!is.null(v2)) return(isTRUE(v2))
  FALSE
}

#' 本跑是否单库（primary/secondary 同名或同路径，或 dual_db 未开）
locked_mv_n_databases <- function(cfg) {
  dual <- (cfg %||% list())$dual_db %||% list()
  if (!isTRUE(dual$enable)) return(1L)
  p <- as.character(dual$primary$name %||% "")[1L]
  s <- as.character(dual$secondary$name %||% "")[1L]
  if (!nzchar(s)) return(1L)
  if (nzchar(p) && identical(tolower(p), tolower(s))) return(1L)
  pp <- as.character(dual$primary$rawdata_path %||% "")[1L]
  sp <- as.character(dual$secondary$rawdata_path %||% "")[1L]
  if (nzchar(pp) && nzchar(sp)) {
    np <- tryCatch(normalizePath(pp, winslash = "/", mustWork = FALSE), error = function(e) pp)
    ns <- tryCatch(normalizePath(sp, winslash = "/", mustWork = FALSE), error = function(e) sp)
    if (identical(tolower(np), tolower(ns))) return(1L)
  }
  2L
}

#' 锁定多因素表文件名/标题（与全池多因素区分，避免缩短后撞名）
locked_multivariable_table_caption <- function(cfg = NULL, n_db = NULL) {
  if (is.null(n_db)) n_db <- locked_mv_n_databases(cfg)
  n_db <- suppressWarnings(as.integer(n_db)[1L])
  if (is.finite(n_db) && n_db >= 2L) {
    "Final multivariable model harmonized"
  } else {
    "Final multivariable model"
  }
}

#' config 手动锁定的 logistic Model1/Model2（logistic 块 use_manual 同源）
#' M1/M2 均非空才视为手动锁定；否则返回空（走 Gate B / vif_final_pass 链）
logistic_locked_model_factors <- function(cfg) {
  lcfg <- cfg$logistic_nhanes_weighted %||% cfg$logistic_covariates %||% list()
  m1 <- unique(as.character(lcfg$model1_factors %||% character(0)))
  m2 <- unique(as.character(lcfg$model2_factors %||% character(0)))
  m1 <- m1[nzchar(m1)]
  m2 <- m2[nzchar(m2)]
  if (!(length(m1) > 0L && length(m2) > 0L)) {
    return(list(model1 = character(0), model2 = character(0)))
  }
  list(model1 = m1, model2 = unique(c(m1, setdiff(m2, m1))))
}

#' 锁定多因素协变量（发表 Model2 / 多变量 ROC / 中介 LM 共用）
#' 双库 Gate B / Cox 统一锁定后优先 Model2Factors（与 Table 2 一致）；
#' config 手动锁定 logistic Model1/Model2（Table 2 实际使用）优先于 Gate B / vif_final_pass；
#' 否则用 vif_final_pass；再回退 Model2Factors。
locked_multivariable_covariates <- function(ctx, cfg) {
  ix <- character(0)
  if (exists("pipeline_index_exposure_var", mode = "function")) {
    ix <- as.character(pipeline_index_exposure_var(cfg) %||% "")[1L]
  }
  if (!length(ix) || !nzchar(ix)) {
    ix <- as.character(
      (cfg$incidence %||% list())$index_var %||%
        (cfg$survival %||% list())$index_var %||%
        (cfg$study_batch %||% list())$active_unit %||%
        ""
    )[1L]
  }
  gate_locked <- isTRUE(ctx$results$dual_db_cox_unified_locked) ||
    isTRUE(ctx$results$dual_db_covariate_harmonized)
  m2 <- unique(as.character(ctx$results$Model2Factors %||% character(0)))
  m2 <- m2[nzchar(m2)]
  # config 手动锁定的 logistic Model1/Model2（Table 2 实际使用）：S7/S8 与 Table 2 同套
  manual <- character(0)
  if (exists("logistic_locked_model_factors", mode = "function")) {
    manual <- logistic_locked_model_factors(cfg)[["model2"]]
  }
  final <- unique(as.character(
    ctx$results$logistic_final_factors %||%
      ctx$results$cox_final_factors %||%
      character(0)
  ))
  final <- final[nzchar(final)]
  vif <- unique(as.character(ctx$results$vif_final_pass %||% character(0)))
  vif <- vif[nzchar(vif)]
  pool <- if (length(final)) {
    final
  } else if (length(manual)) {
    manual
  } else if (gate_locked && length(m2)) {
    m2
  } else if (length(vif)) {
    vif
  } else {
    m2
  }
  covs <- setdiff(pool, ix[nzchar(ix)])
  data_cols <- pipeline_ctx_data_cols(ctx)
  # 已有 cox/logistic_final_factors 时以终模为准（与 Table 2 全调整一致，含 Model3 显著性回退）。
  # 仅在尚无终模时再并入学术必调；Model3 已判定不显著则不再强行并入。
  if (!length(final) && exists("pipeline_resolve_model3_factors", mode = "function")) {
    m3_sig <- ctx$results$model3_significant
    if (is.null(m3_sig) || isTRUE(m3_sig)) {
      m3 <- tryCatch(
        pipeline_resolve_model3_factors(covs, cfg, data_cols, ix),
        error = function(e) character(0)
      )
      if (length(m3)) covs <- unique(c(covs, m3))
    }
  }
  ens <- pipeline_ensure_age_in_model1(character(0), covs, data_cols, cfg)
  covs <- ens$M2
  all_vars <- unique(c(ix[nzchar(ix)], ens$M1, covs))
  list(index = ix, covariates = covs, model1 = ens$M1, all = all_vars)
}

#' 按配置剔除多因素表中的单因素列（列名含 (univariable)）
multivariate_pub_drop_univariable_if_needed <- function(out_table, cfg) {
  if (is.null(out_table) || !is.data.frame(out_table) || !ncol(out_table)) {
    return(out_table)
  }
  if (multivariate_pub_include_univariable_column(cfg)) return(out_table)
  drop <- grepl("\\(univariable\\)", names(out_table), ignore.case = TRUE)
  if (!any(drop)) return(out_table)
  out_table[, !drop, drop = FALSE]
}

# ── 内置指标展示名（全套路通用；数据列名不变，仅表/图展示）────────────────
# FI / Frailty → Frailty Index；可在此继续追加其它缩写
pipeline_builtin_var_display_names <- function() {
  c(
    FI             = "Frailty Index",
    Frailty_Index  = "Frailty Index",
    frailty_index  = "Frailty Index",
    FrailtyIndex   = "Frailty Index",
    Ventilation    = "Mechanical ventilation (ever)",
    Ventilation_Hour = "Mechanical ventilation duration, hours"
  )
}

pipeline_var_display_name <- function(var, cfg = NULL) {
  v <- as.character(var %||% "")[1L]
  if (!nzchar(v)) return("Index")
  # config 显式覆盖（仅对当前 index）
  if (!is.null(cfg)) {
    ix <- as.character((cfg$incidence %||% list())$index_var %||% "")[1L]
    disp <- (cfg$incidence %||% list())$index_var_display_name
    if (nzchar(ix) && identical(v, ix) && !is.null(disp) && nzchar(as.character(disp)[1L])) {
      return(as.character(disp)[1L])
    }
  }
  builtins <- pipeline_builtin_var_display_names()
  if (v %in% names(builtins)) return(unname(builtins[[v]]))
  hit <- names(builtins)[tolower(names(builtins)) == tolower(v)]
  if (length(hit)) return(unname(builtins[[hit[[1]]]]))
  gsub("_", " ", v, fixed = TRUE)
}

# ── Logistic Table 2 脚注（Crude / Model 1 / Model 2 协变量说明）────────────────
pipeline_index_display_name <- function(cfg, index_var = NULL) {
  v <- index_var %||% (cfg$incidence %||% list())$index_var
  pipeline_var_display_name(v, cfg)
}

logistic_glm_pretty_var <- function(v) {
  pipeline_var_display_name(v, cfg = NULL)
}

logistic_glm_table_footnotes <- function(M1, M2, M3 = NULL, m3_significant = NULL, Crude = NULL) {
  if (exists("pipeline_model3_table_footnotes", mode = "function")) {
    return(pipeline_model3_table_footnotes(M1, M2, M3, m3_significant, Crude = Crude))
  }
  m1_txt <- if (length(M1)) {
    paste(vapply(M1, logistic_glm_pretty_var, character(1L)), collapse = ", ")
  } else {
    "none"
  }
  m2_txt <- if (length(M2)) {
    paste(vapply(M2, logistic_glm_pretty_var, character(1L)), collapse = ", ")
  } else {
    "none"
  }
  Crude <- as.character(Crude %||% character(0))
  crude_line <- if (length(Crude)) {
    paste0(
      "The Crude Model was adjusted by: ",
      paste(vapply(Crude, logistic_glm_pretty_var, character(1L)), collapse = ", "),
      "."
    )
  } else {
    "The Crude Model was non-adjusted."
  }
  c(
    crude_line,
    paste0("The Model 1 was adjusted by: ", m1_txt, "."),
    paste0("The Model 2 was adjusted by: ", m2_txt, ".")
  )
}

# ── 导出 SCI 标准三线表到 Excel ───────────────────────────────────────────────
#
#  三线表规范：
#    - 顶线（表格最上方）：粗实线，厚度 2pt
#    - 标题行下方分隔线：细实线，厚度 1pt
#    - 底线（表格最下方）：粗实线，厚度 2pt
#    - 无竖线、无内部横线
#    - 标题行：加粗，居中，浅灰底色
#    - 数据行：交替白/极浅灰，左对齐
#    - p-value 列：< 0.05 的单元格文字加粗标红
#    - 字体：Times New Roman 11pt（正文），12pt（标题）
#    - 列宽自适应
#    - .tex：latex_use_longtable=TRUE（默认）时用 longtable，编译时可自动跨页；
#            但若设置了 table_footnotes，则自动切换为 table+resizebox+tabular（整表不跨页，脚注不分页）
#
format_vif_pub_column <- function(vif_vals) {
  vapply(vif_vals, function(v) {
    if (length(v) != 1L || is.na(v)) return("")
    x <- suppressWarnings(as.numeric(v))
    if (!is.finite(x)) {
      if (is.infinite(x) && x > 0) return("Inf")
      if (is.infinite(x) && x < 0) return("-Inf")
      return("")
    }
    formatC(x, format = "f", digits = 3)
  }, character(1L), USE.NAMES = FALSE)
}

export_sci_table <- function(df, filepath, title = "", sheet = "Table",
                             latex_include_colnames = TRUE,
                             overwrite_tex = TRUE,
                             row_top_borders_idx = NULL,
                             header_row1 = NULL,
                             header_row2 = NULL,
                             latex_align = NULL,
                             latex_use_longtable = TRUE,
                             excel_use_prepared = TRUE,
                             skip_excel = FALSE,
                             table1_render_spec = NULL,
                             table_footnotes = NULL,
                             excel_level_row_idx = NULL,
                             blank_na_cells = TRUE) {
  title <- pub_caption_strip_parentheses(as.character(title %||% "")[1L])
  filepath <- .inject_db_into_pub_filepath(filepath)
  title <- .inject_db_into_pub_label(title, sanitize_for_file = FALSE)
  title <- pub_caption_strip_parentheses(title)
  if (identical(tolower(tools::file_ext(filepath)), "xlsx") &&
      exists("pub_fit_table_stem", mode = "function")) {
    bn <- basename(filepath)
    ext <- tools::file_ext(bn)
    stem <- pub_caption_strip_parentheses(
      sub(paste0("\\.", ext, "$"), "", bn, ignore.case = TRUE)
    )
    # 从标题中提取结尾 " and <Disease>" 作为疾病名保护（无需 config）
    dis_guess <- sub("^.* and ([A-Za-z][A-Za-z -]+)$", "\\1", stem, perl = TRUE)
    if (identical(dis_guess, stem)) dis_guess <- NULL
    fitted <- pub_fit_table_stem(stem, ext, disease = dis_guess)
    filepath <- file.path(dirname(filepath), paste0(fitted, ".", ext))
    title <- fitted
  }
  q <- .table_queue_env$items %||% list()
  q[[length(q) + 1L]] <- list(
    df = df,
    filepath = filepath,
    title = title,
    sheet = sheet,
    latex_include_colnames = latex_include_colnames,
    overwrite_tex = overwrite_tex,
    row_top_borders_idx = row_top_borders_idx,
    header_row1 = header_row1,
    header_row2 = header_row2,
    latex_align = latex_align,
    latex_use_longtable = latex_use_longtable %||% TRUE,
    excel_use_prepared = excel_use_prepared,
    skip_excel = skip_excel %||% FALSE,
    table1_render_spec = table1_render_spec,
    table_footnotes = table_footnotes,
    excel_level_row_idx = excel_level_row_idx,
    blank_na_cells = isTRUE(blank_na_cells)
  )
  .table_queue_env$items <- q
  cli::cli_alert_info("Queued table task: {.file {basename(filepath)}}")
}

# ── Table 1：按变量名在 gtsummary 表中定位，得到「子标题插入行」（含表头行后的 1-based 行号）──
# sections: 命名 list，元素为变量名字符向量；每个分组在表中第一个命中变量的 label 行上方插入子标题
table1_section_insert_rows_from_gtsummary <- function(tbl, sections) {
  if (is.null(tbl) || is.null(sections) || length(sections) == 0L) return(NULL)
  if (!inherits(tbl, "gtsummary")) return(NULL)
  body <- tbl$table_body
  if (is.null(body$variable) || is.null(body$row_type)) return(NULL)
  rows <- integer(0)
  titles <- character(0)
  for (ti in names(sections)) {
    vars <- sections[[ti]]
    if (is.null(vars)) next
    vars <- as.character(unlist(vars, use.names = FALSE))
    vars <- unique(vars[nzchar(vars)])
    rid <- NA_integer_
    for (v in vars) {
      hit <- which(body$variable == v & body$row_type == "label")[1L]
      if (is.na(hit)) {
        hit <- which(
          tolower(as.character(body$variable)) == tolower(v) &
            body$row_type == "label"
        )[1L]
      }
      if (is.na(hit)) {
        .nk <- function(x) gsub("[^a-z0-9]+", "", tolower(as.character(x)))
        hit <- which(
          .nk(body$variable) == .nk(v) & body$row_type == "label"
        )[1L]
      }
      if (!is.na(hit)) {
        rid <- as.integer(hit) + 1L
        break
      }
    }
    if (!is.na(rid)) {
      rows <- c(rows, rid)
      titles <- c(titles, ti)
    }
  }
  if (length(rows) == 0L) return(NULL)
  out <- stats::setNames(rows, titles)
  out <- out[!duplicated(as.integer(out))]
  out[order(as.integer(out))]
}

# Table 1「Laboratory Tests」小节变量名（用于 NHANES 加权中介：限定血检指标池）
.default_laboratory_test_vars <- function() {
  secs <- .default_table1_sections()
  unique(as.character(secs[["Laboratory Tests"]] %||% character(0)))
}

.default_table1_sections <- function() {
  list(
    # 1. 人口统计学
    "Demographics" = c(
      "Age", "Gender", "Race",
      "Education", "Marital_Status", "Income", "PIR", "Language",
      "Smoking", "Smoke", "Alcohol_drinking", "Drinking",
      "Weight", "Height", "Waist_circumference", "Waist",
      # CHARLS / Single 人口学 / 社会经济
      "Residence", "Residence_type", "Hukou",
      "Familysize", "Household_size", "Household size", "Family_size",
      "Incometotal", "Family_per_capita_consumption",
      # CHARLS 认知评分
      "Totalcognition", "Executive", "Memeory",
      "Micu_Code",
      # BMI 置于 Vital Signs 小节之上（Demographics 末行）
      "BMI"
    ),

    # 2. 生命体征（不含 BMI）
    "Vital Signs" = c(
      # ELSA8 体格测量
      "Hip", "WaistHipRatio", "SittingHeight",
      "HR", "Pulse", "PP", "RR", "SpO2", "Temperature",
      "SBP", "DBP", "MAP",
      "Systolic pressure", "Systolic_pressure",
      "Diastolic pressure", "Diastolic_pressure",
      "NBPS", "NBPD", "NBPM",
      "ABPS", "ABPD", "ABPM"
    ),

    # 3. 实验室检查（CBC → 生化 → 血气 → 凝血/心肌 → 铁代谢/甲状腺 → 尿液）
    "Laboratory Tests" = c(
      # CBC
      "WBC", "RBC", "Hemoglobin", "Hematocrit", "PlateletCount", "Platelet_Count",
      "Neutrophil_Count", "NeutrophilCount", "Percentage_of_neutrophils",
      "Lymphocytes", "Monocyte", "Mononuclear_cell_count",
      "mononuclear_cell_count", "Eosinophil_Count", "Basophil_Count",
      "RDW", "MCV", "MCH", "MCHC", "Mean_platelet_volume",
      # 肝酶 & 蛋白
      "ALT", "AST", "LD", "CK", "CKMb", "GGT",
      "Albumin", "TotalProtein", "Globulin", "AG_ratio",
      "BilirubinTotal", "Bilirubin_Total", "BilirubinDirect", "Bilirubin_Direct",
      "BilirubinIndirect", "Bilirubin_Indirect",
      "ALP", "TBA",
      # 肾功能 / eICU-MIMIC 别名
      "BUN", "Creatinine", "eGFR", "Uric_Acid", "UreaNitrogen",
      # 电解质
      "Sodium", "Potassium", "Chloride", "Bicarbonate",
      "Calcium", "CalciumTotal", "Magnesium", "Phosphate", "AnionGap",
      # 血糖 & 胰岛素
      "Glucose", "SerumGlucose", "HbA1c", "Insulin",
      "Fasting Glucose mg dL", "Fasting_Glucose",
      # 血脂
      "Total_Cholesterol", "Triglycerides", "LDL", "HDL",
      "LpA", "ApoA", "ApoA1", "ApoB",
      # CHARLS 衍生指标
      "TyG", "TyG_BMI",
      # ELSA8
      "VitD", "IGF1",
      # 炎症
      "CRP", "HSCRP", "Procalcitonin", "Lactate",
      "C reactive protein mg dL", "C_reactive_protein_mg_dL", "C-reactive protein",
      # 血气
      "PaO2", "FiO2", "PH", "PCO2", "PO2", "TotalCo2", "Free_Calcium",
      # 凝血 & 心肌标志物
      "INR", "PT", "PTT", "TT", "Fibrinogen", "Ddimer",
      "Troponint", "NTproBNP", "BNP",
      # 铁代谢
      "Serumiron", "Ferritin", "TotalIronBindingCapacity", "Transferrin",
      # 甲状腺
      "Thyroid_stimulating_hormone",
      "Thyroxine_free_T4", "Thyroxine_total_T4",
      "Triiodothyronine_T3_free", "Thyroxine_total_T3",
      # 尿液
      "Urine_Creatinine", "UrineCreatinine", "Urine_Protein", "Albumin_Urine",
      "AlbuminUrine", "Albumin_Creatinine",
      "Urine_Glucose", "Urine_Osmolality", "Urine_Volume", "Urine_specific_gravity",
      "Urine_Ketones", "Urine_Occult_Blood", "Urine_pH", "Urine_Sodium",
      "Urine_Potassium", "Urine_Bilirubin", "Urine_Urobilinogen", "Urine_Iodine",
      # 维生素 / 膳食营养（勿落入 Clinical Scores）
      "Vitamin_A_dietary", "Vitamin_A_blood", "Vitamin_B1", "Vitamin_B2",
      "Vitamin_C", "Vitamin_D", "Vitamin_D2", "Vitamin_D3", "Vitamin_D3_3epi",
      "Vitamin_E", "Folate", "Beta_Carotene",
      "Iron_dietary", "Calcium_dietary", "Phosphorus_dietary",
      "Potassium_dietary", "Sodium_dietary", "Dietary_Fiber", "Total_Fat_dietary",
      # 血脂别名（KNHANES 等）
      "TG", "Cholesterol", "UreaNitrogen", "UricAcid",
      # NHANES 总钙（置于 Laboratory Tests 末行）
      "Total_Calcium", "TotalCalcium"
    ),

    # 4. 临床评分（ICU 严重度 / 器官衰竭 / 共病指数；复合暴露指标勿放此处）
    "Clinical Scores" = c(
      "APS", "APSIII", "SAPSII", "OASIS", "SIRS", "HHR", "ICP",
      "GCS", "SOFA", "APACHE",
      "CHARLSON", "Charlson", "CCI"
      # 注：FIB4/APRI/NFS/HSI/FLI 等作课题暴露时由 table1_resolve_sections()
      # 归入 Exposure，不再挂 Clinical Scores
    ),

    # 4b. 暴露指标（当前 index；由 table1_resolve_sections 动态填入）
    "Exposure" = character(0),

    # 5. 干预与住院过程
    "Interventions and Hospital Course" = c(
      "Ventilation", "Ventilation_Hour",
      "hosp_day", "icu_day", "ICU_LOS", "Hospital_LOS", "ICU_Days", "Hospital_Days",
      # 用药
      "Antihypertensive_agents", "Lipid_lowering_agents",
      "Antidiabetic_agents"
    ),

    # 6. 合并症与相关治疗
    "Comorbidities" = c(
      # 合并症
      "Hypertension", "Diabetes", "T1DM", "T2DM",
      "Heart_Failure", "Myocardial_Infarction", "Atrial_Fibrillation",
      "Stroke", "PVD",
      "COPD", "CKD", "Acute_Renal_Failure",
      "Cancer", "Malignant_Tumor", "Dementia",
      "Hyperlipidemia", "Liver_cirrhosis", "Hepatitis",
      "Tuberculosis", "Pneumonia",
      # NHANES 自报合并症（无下划线列名）
      "Anginapectoris", "Heartattack", "Heartfailure",
      "Coronaryheartdisease", "Chronicbronchitis", "Emphysema",
      "Livercondition", "Arthritis",
      # 肾脏替代治疗（Table 1 归入共病相关）
      "CRRT", "CRRT_Day",
      # CHARLS 问卷合并症
      "Pulmonary_Disease", "Liver_Disease", "Cardiopathy", "Kidney_Disease",
      "Stomach_Disease", "Psychiatric", "Amnesia", "Rheumatic_Diseases", "Asthma"
    )
  )
}

#' Table1 小节：默认 sections + 当前暴露归入 Exposure（勿挂 Clinical Scores）
table1_resolve_sections <- function(cfg, bl_cfg = NULL) {
  bl <- bl_cfg %||% cfg$baseline_binary %||% cfg$baseline_nhanes %||%
    cfg$baseline_multiclass %||% cfg$baseline %||% list()
  if (isTRUE(bl$table1_sections_disable_default) &&
      length(bl$table1_sections %||% list()) > 0L) {
    sec <- as.list(bl$table1_sections)
  } else {
    sec <- utils::modifyList(
      as.list(.default_table1_sections()),
      as.list(bl$table1_sections %||% list())
    )
  }
  if (!length(sec)) sec <- .default_table1_sections()

  ix <- character(0)
  if (exists("pipeline_index_exposure_var", mode = "function")) {
    ix <- as.character(pipeline_index_exposure_var(cfg) %||% character(0))
  }
  ix <- unique(c(
    ix,
    as.character((cfg$incidence %||% list())$index_var %||% character(0)),
    as.character((cfg$logistic %||% list())$index_var %||% character(0)),
    as.character((cfg$survival %||% list())$index_var %||% character(0))
  ))
  ix <- ix[nzchar(ix)]
  if (exists("index_alias_names", mode = "function") && length(ix)) {
    ix <- unique(c(ix, unlist(lapply(ix, index_alias_names), use.names = FALSE)))
  }
  if (length(ix)) {
    for (nm in names(sec)) {
      sec[[nm]] <- setdiff(as.character(sec[[nm]] %||% character(0)), ix)
    }
    # Exposure 放在 Clinical Scores 之前（若存在），否则追加
    sec$Exposure <- unique(c(as.character(sec$Exposure %||% character(0)), ix))
    nms <- names(sec)
    if ("Clinical Scores" %in% nms && "Exposure" %in% nms) {
      rest <- setdiff(nms, c("Clinical Scores", "Exposure"))
      cs_idx <- match("Clinical Scores", nms)
      before <- nms[seq_len(cs_idx - 1L)]
      after <- setdiff(nms[seq(cs_idx, length(nms))], "Exposure")
      ord <- unique(c(before, "Exposure", after))
      sec <- sec[ord]
    }
  }
  # 去掉空小节（Exposure 有内容则保留）
  keep <- vapply(sec, function(v) {
    length(as.character(v %||% character(0))[nzchar(as.character(v %||% character(0)))]) > 0L
  }, logical(1L))
  if ("Exposure" %in% names(sec) && length(sec$Exposure)) keep[["Exposure"]] <- TRUE
  sec[keep]
}

# 单因素/发表表行序：先连续变量、再分类变量；组内按 table1_sections 统一排序（双库一致）。
order_vars_like_baseline <- function(vars, ctx, cfg) {
  vars <- unique(as.character(vars))
  vars <- vars[nzchar(vars)]
  cont <- intersect(as.character(ctx$results$continuous_vars %||% character(0)), vars)
  catv <- intersect(as.character(ctx$results$categorical_vars %||% character(0)), vars)
  rest <- setdiff(vars, c(cont, catv))
  c(
    sort_vars_by_table1_sections(cont, cfg),
    sort_vars_by_table1_sections(catv, cfg),
    sort_vars_by_table1_sections(rest, cfg)
  )
}

# 按 .default_table1_sections（可被 config$baseline$table1_sections 覆盖）对变量名排序。
# 不在任何 section 中的变量排在末尾（字母序）；当前暴露指标（survival/incidence/prediction）排在最末。
# 供所有 baseline / univariate / multivariate / vif block 统一调用，不再在各 block 内重复实现。
sort_vars_by_table1_sections <- function(vars, cfg) {
  vars <- unique(as.character(vars))
  if (length(vars) <= 1L) return(vars)

  # 优先从各 baseline 块的专属 config key 读取 table1_sections 配置，兜底用 cfg$baseline
  bl <- cfg$baseline_binary %||% cfg$baseline_nhanes %||% cfg$baseline_multiclass %||%
        cfg$baseline %||% list()
  pred <- cfg$prediction %||% list()
  # 仅暴露指标本身置末；Albumin / Bilirubin 等组分留在 Laboratory，勿随 index 挂尾
  index_last <- unique(c(
    if (exists("pipeline_index_exposure_var", mode = "function")) {
      as.character(pipeline_index_exposure_var(cfg) %||% character(0))
    } else {
      character(0)
    },
    as.character((cfg$survival %||% list())$index_var %||% character(0)),
    as.character((cfg$logistic %||% list())$index_var %||% character(0)),
    as.character((pred$index_vars %||% character(0))[1L])
  ))
  index_last <- index_last[nzchar(index_last)]
  if (exists("index_alias_names", mode = "function")) {
    index_last <- unique(c(
      index_last,
      unlist(lapply(index_last, index_alias_names), use.names = FALSE)
    ))
  }
  index_last <- intersect(index_last, vars)

  if (isTRUE(bl$table1_sections_disable_default) &&
      length(bl$table1_sections %||% list()) > 0L) {
    sec <- bl$table1_sections
  } else if (!isTRUE(bl$table1_sections_disable_default)) {
    if (exists("table1_resolve_sections", mode = "function")) {
      sec <- table1_resolve_sections(cfg, bl)
    } else {
      sec <- utils::modifyList(
        as.list(.default_table1_sections()),
        as.list(bl$table1_sections %||% list())
      )
    }
  } else {
    sec <- bl$table1_sections %||% .default_table1_sections()
  }
  if (length(sec) == 0L) {
    sec <- if (exists("table1_resolve_sections", mode = "function")) {
      table1_resolve_sections(cfg, bl)
    } else {
      .default_table1_sections()
    }
  }

  others <- sort(setdiff(vars, index_last))
  # 随访时间：放在暴露指标正上方（末段）
  follow_vars <- intersect(
    c("futime", "Follow_up_time", "Follow-up time", "RFS_Months"),
    setdiff(vars, index_last)
  )

  # 下划线 / 空格 / 连字符视为同一分隔，避免 CHARLS「C_reactive_protein_mg_dL」落在小节外
  .norm_key <- function(x) {
    x <- tolower(as.character(x))
    gsub("[^a-z0-9]+", "", x)
  }
  .exact_key <- function(v) {
    vl <- tolower(v)
    vn <- .norm_key(v)
    for (si in seq_along(sec)) {
      sv <- unique(as.character(unlist(sec[[si]], use.names = FALSE)))
      sv <- sv[nzchar(sv)]
      pos <- match(vl, tolower(sv), nomatch = NA_integer_)
      if (is.na(pos)) {
        pos <- match(vn, .norm_key(sv), nomatch = NA_integer_)
      }
      if (!is.na(pos)) return(si * 100000L + pos)
    }
    NA_real_
  }
  .prefix_key <- function(v) {
    vl <- tolower(v)
    vn <- .norm_key(v)
    for (si in seq_along(sec)) {
      sv <- unique(as.character(unlist(sec[[si]], use.names = FALSE)))
      sv <- sv[nzchar(sv)]
      for (pref in sv[order(-nchar(sv))]) {
        # 仅允许 pref 本身或 pref_xxx，避免 CK 误匹配 CKD
        if (!nzchar(pref)) next
        pl <- tolower(pref)
        pn <- .norm_key(pref)
        if (identical(vl, pl) || startsWith(vl, paste0(pl, "_")) ||
            identical(vn, pn) || (nzchar(pn) && startsWith(vn, pn))) {
          pos2 <- match(pl, tolower(sv), nomatch = NA_integer_)
          if (is.na(pos2)) pos2 <- match(pn, .norm_key(sv), nomatch = NA_integer_)
          if (!is.na(pos2)) return(si * 100000L + pos2)
        }
      }
    }
    NA_real_
  }

  .sort_key <- function(v) {
    if (v %in% index_last) return(9000000L + match(v, index_last, nomatch = 9999L))
    if (v %in% follow_vars) return(8500000L + match(v, follow_vars, nomatch = 9999L))
    ek <- .exact_key(v)
    if (is.finite(ek)) return(ek)
    pk <- .prefix_key(v)
    if (is.finite(pk)) return(pk)
    8000000L + match(v, others, nomatch = 9999L)
  }

  vars[order(vapply(vars, .sort_key, numeric(1L)))]
}

# 单因素发表表变量排序：own 库按原始数据列序，否则按 table1_sections。
sort_univariate_table_vars <- function(vars, cfg, col_order = character(0)) {
  vars <- unique(as.character(vars))
  vars <- vars[nzchar(vars)]
  if (length(vars) <= 1L) return(vars)
  if (.is_own_db(cfg)) {
    col_order <- unique(as.character(col_order))
    col_order <- col_order[nzchar(col_order)]
    in_order <- intersect(col_order, vars)
    rest <- vars[vars %in% setdiff(vars, in_order)]
    return(c(in_order, rest))
  }
  sort_vars_by_table1_sections(vars, cfg)
}

# 单因素/多因素/VIF 发表表行序：与 baseline Table 1 的 table1_var_order 完全一致（双库相同规则）。
order_vars_like_table1 <- function(vars, ctx, cfg, data = NULL) {
  vars <- unique(as.character(vars))
  vars <- vars[nzchar(vars)]
  if (length(vars) <= 1L) return(vars)
  t1 <- as.character(ctx$results$table1_var_order %||% character(0))
  t1 <- t1[nzchar(t1)]
  ordered <- if (length(t1)) {
    o <- intersect(t1, vars)
    rest <- setdiff(vars, o)
    if (length(rest) && exists("sort_vars_by_table1_sections", mode = "function")) {
      o <- c(o, sort_vars_by_table1_sections(rest, cfg))
    } else {
      o <- c(o, rest)
    }
    o
  } else if (exists("sort_vars_by_table1_sections", mode = "function")) {
    sort_vars_by_table1_sections(vars, cfg)
  } else {
    vars
  }
  # 暴露指标强制最末（即使旧 table1_var_order 未更新）
  ix <- if (exists("pipeline_index_exposure_var", mode = "function")) {
    pipeline_index_exposure_var(cfg)
  } else {
    as.character((cfg$survival %||% list())$index_var %||% character(0))[1L]
  }
  ix <- as.character(ix %||% character(0))[1L]
  if (nzchar(ix) && ix %in% ordered) {
    ordered <- c(setdiff(ordered, ix), ix)
  }
  ordered
}

# 兼容旧名
order_vars_like_univariate_table <- function(vars, cfg, data = NULL) {
  order_vars_like_table1(vars, list(results = list()), cfg, data)
}

.reorder_vif_table_like_univariate <- function(vif_tbl, cfg, data, ctx = NULL) {
  if (is.null(vif_tbl) || !nrow(vif_tbl) || !"Variable" %in% names(vif_tbl)) {
    return(vif_tbl)
  }
  ord <- order_vars_like_table1(vif_tbl$Variable, ctx %||% list(results = list()), cfg, data)
  vif_tbl[match(ord, vif_tbl$Variable), , drop = FALSE]
}

# 与 insert_section_titles 相同的行号偏移，用于 level 行映射到插入子标题后的行号
.table1_shift_row_indices_for_inserts <- function(rows, insert_map_named) {
  rows <- unique(as.integer(rows))
  if (is.null(insert_map_named) || length(insert_map_named) == 0L) return(rows)
  twr <- insert_map_named[order(as.integer(insert_map_named))]
  offset <- 0L
  for (nm in names(twr)) {
    row_num <- as.integer(twr[[nm]]) + offset
    rows <- rows + as.integer(rows >= row_num)
    offset <- offset + 1L
  }
  rows
}

# 去掉单元格与列名中的下划线（及多余空格）；仅处理字符列，避免改动数值列
.table1_strip_underscores_display <- function(df) {
  fix_chr <- function(x) {
    x <- as.character(x)
    x <- gsub("_", " ", x, fixed = TRUE)
    x <- gsub("\\s+", " ", x)
    trimws(x)
  }
  cn <- colnames(df)
  cn <- gsub("\\*\\*", "", cn)
  cn <- fix_chr(cn)
  colnames(df) <- cn
  for (j in seq_len(ncol(df))) {
    if (is.character(df[[j]])) df[[j]] <- fix_chr(df[[j]])
  }
  df
}

# 将 gtsummary 导出的 NA / N/A 等占位符转为空字符串（TeX 与 Excel 均不显示 “NA”）
.table1_blank_na_cells <- function(df) {
  blank_if_missing <- function(x) {
    s <- as.character(x)
    t <- trimws(s)
    bad <- is.na(x)
    if (is.numeric(x)) {
      xd <- suppressWarnings(as.double(x))
      bad <- bad | is.nan(xd)
    }
    bad <- bad | toupper(t) %in% c("NA", "<NA>", "N/A", "NAN", "NULL") |
      t %in% c("Inf", "-Inf", "NaN")
    s[bad] <- ""
    s
  }
  for (j in seq_len(ncol(df))) {
    df[[j]] <- blank_if_missing(df[[j]])
  }
  df
}

# ── Table 1 Excel / LaTeX 脚注（block_baseline 默认；可被 config$baseline$table1_xlsx_footnotes 覆盖）──
table1_baseline_xlsx_footnotes <- function(
    n_obs = NA_integer_,
    n_groups = 2L,
    has_normal_continuous = TRUE,
    has_skewed_continuous = TRUE,
    has_categorical = TRUE,
    use_fisher_any = FALSE,
    weighted = FALSE
) {
  # 保留形参以兼容 block_baseline 调用；脚注文案固定为发表用两句
  # weighted=TRUE（tbl_svysummary + add_p）：连续=survey 加权 Wilcoxon 秩和
  # （svy.wilcox.test），分类=survey 调整卡方（svy.chisq.test）——gtsummary 默认；
  # 百分比亦为加权估计。禁止加权表写非加权 Wilcoxon/Pearson 脚注。
  # weighted=FALSE（baseline_binary / 不加权敏感性基线）：禁止写 weighted mean/count。
  desc <- if (isTRUE(weighted)) {
    paste0(
      "Continuous variables are presented as weighted mean (standard error) or weighted ",
      "median (interquartile range) depending on their distribution. ",
      "Categorical variables are presented as weighted count (weighted percentage)."
    )
  } else {
    paste0(
      "Continuous variables are presented as mean (standard deviation) or ",
      "median (interquartile range) depending on their distribution. ",
      "Categorical variables are presented as count (percentage)."
    )
  }
  test <- if (isTRUE(weighted)) {
    paste0(
      "Statistical comparisons were performed using survey-weighted Wilcoxon rank-sum tests ",
      "and survey-adjusted chi-squared tests, accounting for the complex survey design ",
      "(stratification, clustering, and sampling weights)."
    )
  } else {
    paste0(
      "Statistical comparisons were performed using the Wilcoxon rank-sum test ",
      "or Pearson's chi-squared test."
    )
  }
  c(desc, test)
}

# 与 Excel 完全相同的展示用 data.frame（列名首行 + 子标题插入 + 去下划线）
table1_build_display_df <- function(
    tbl_df,
    section_insert_rows = NULL,
    section_anchors = NULL,
    gtsummary_tbl = NULL,
    center_first_col_values = character(0),
    strip_underscores = TRUE
) {
  tbl_df <- as.data.frame(tbl_df, stringsAsFactors = FALSE)
  tbl_with_header_row <- rbind(
    stats::setNames(
      as.data.frame(t(colnames(tbl_df)), stringsAsFactors = FALSE),
      colnames(tbl_df)
    ),
    tbl_df
  )

  insert_section_titles <- function(df, titles_with_rows) {
    if (is.null(titles_with_rows) || length(titles_with_rows) == 0L) return(df)
    twr <- titles_with_rows[order(as.integer(titles_with_rows))]
    offset <- 0L
    for (nm in names(twr)) {
      row_num <- as.integer(twr[[nm]]) + offset
      if (length(row_num) != 1L || row_num < 1L || row_num > nrow(df)) next
      new_row <- as.data.frame(
        matrix(c(nm, rep("", ncol(df) - 1L)), nrow = 1L, ncol = ncol(df)),
        stringsAsFactors = FALSE
      )
      names(new_row) <- names(df)
      df <- rbind(df[seq_len(row_num - 1L), , drop = FALSE],
                  new_row,
                  df[row_num:nrow(df), , drop = FALSE])
      offset <- offset + 1L
    }
    df
  }

  insert_map <- NULL
  if (!is.null(section_insert_rows) && length(section_insert_rows) > 0L) {
    sir <- section_insert_rows
    if (is.list(sir) && !is.null(names(sir))) sir <- unlist(sir, use.names = TRUE)
    insert_map <- stats::setNames(as.integer(sir), names(sir))
    insert_map <- insert_map[is.finite(insert_map) & insert_map >= 1L &
      insert_map <= nrow(tbl_with_header_row)]
    insert_map <- insert_map[!duplicated(as.integer(insert_map))]
    insert_map <- insert_map[order(as.integer(insert_map))]
    if (length(insert_map) == 0L) insert_map <- NULL
  } else if (!is.null(section_anchors) && length(section_anchors) > 0L) {
    anchors <- section_anchors
    if (is.list(anchors) && !is.null(names(anchors))) {
      anchors <- unlist(anchors, use.names = TRUE)
    }
    anchors <- anchors[nzchar(as.character(anchors))]
    v1 <- tbl_with_header_row[[1L]]
    for (nm in names(anchors)) {
      anch <- anchors[[nm]]
      idx <- which(v1 == anch)
      if (length(idx) == 1L) insert_map <- c(insert_map, stats::setNames(idx, nm))
    }
    if (!is.null(insert_map) && length(insert_map) > 0L) {
      insert_map <- insert_map[!duplicated(as.integer(insert_map))]
      insert_map <- insert_map[order(as.integer(insert_map))]
    }
  }

  tbl_df_new <- insert_section_titles(tbl_with_header_row, insert_map)
  tbl_df_new[1L, ] <- gsub("\\*", "", as.character(tbl_df_new[1L, ]))
  colnames(tbl_df_new) <- gsub("\\*\\*", "", colnames(tbl_df_new))
  if (isTRUE(strip_underscores)) {
    tbl_df_new <- .table1_strip_underscores_display(tbl_df_new)
  }
  tbl_df_new <- .table1_blank_na_cells(tbl_df_new)

  level_row_idx <- integer(0)
  if (!is.null(gtsummary_tbl) && inherits(gtsummary_tbl, "gtsummary")) {
    bdy <- gtsummary_tbl$table_body
    if (!is.null(bdy$row_type)) {
      lev <- which(bdy$row_type == "level")
      if (length(lev) > 0L) {
        aug <- as.integer(lev) + 1L
        aug <- .table1_shift_row_indices_for_inserts(aug, insert_map)
        level_row_idx <- as.integer(aug)
      }
    }
  }
  if (length(center_first_col_values) > 0L) {
    extra_r <- which(tbl_df_new[[1L]] %in% center_first_col_values)
    level_row_idx <- unique(c(level_row_idx, extra_r))
  }
  level_row_idx <- level_row_idx[
    level_row_idx >= 2L & level_row_idx <= nrow(tbl_df_new)
  ]

  section_row_idx <- integer(0)
  if (!is.null(insert_map) && length(insert_map) > 0L) {
    section_row_idx <- which(tbl_df_new[[1L]] %in% names(insert_map))
  }

  list(
    df = tbl_df_new,
    insert_map = insert_map,
    level_row_idx = level_row_idx,
    section_row_idx = section_row_idx,
    ncol = ncol(tbl_df_new)
  )
}

# 独立 .tex 中可跨页的三线表：longtable + booktabs（勿与 \\resizebox 同用，否则无法分页）
# longtable 默认 \\LTleft/\\LTright 常为 0：表窄于版心时整表贴左，易显得「偏右/不对称」；两侧加等量 fil 可在版心内水平居中。
.latex_longtable_booktabs_core <- function(align, caption_star_line, header_lines, body_lines) {
  cap <- if (nzchar(caption_star_line %||% "")) caption_star_line else character(0)
  hdr <- header_lines
  if (length(hdr) == 0L) hdr <- "\\toprule"
  c(
    "% longtable: center table block when narrower than \\textwidth",
    "\\setlength{\\LTleft}{0pt plus 1fil}",
    "\\setlength{\\LTright}{0pt plus 1fil}",
    paste0("\\begin{longtable}{", align, "}"),
    cap,
    hdr,
    "\\endfirsthead",
    hdr,
    "\\endhead",
    "\\midrule",
    "\\endfoot",
    "\\bottomrule",
    "\\endlastfoot",
    body_lines,
    "\\end{longtable}"
  )
}

# 与 Excel 同结构的 booktabs 三线表 + 表下脚注（独立 .tex 文档）
table1_booktabs_latex_document <- function(
    display_df,
    title = "",
    footnotes = character(0),
    insert_map = NULL,
    level_row_idx = integer(0),
    latex_align = NULL,
    use_longtable = TRUE
) {
  df <- as.data.frame(display_df, stringsAsFactors = FALSE)
  nc <- ncol(df)
  nr <- nrow(df)
  if (nc < 1L || nr < 1L) {
    stop("table1_booktabs_latex_document: empty display_df")
  }
  align <- if (!is.null(latex_align) && nzchar(latex_align)) {
    latex_align
  } else {
    paste0("l", paste(rep("c", max(0L, nc - 1L)), collapse = ""))
  }

  sec_names <- if (!is.null(insert_map) && length(insert_map) > 0L) {
    names(insert_map)
  } else {
    character(0)
  }
  lvl_set <- as.integer(level_row_idx)

  .fmt_cell <- function(t, j, is_header_row, is_section_row, is_level_row) {
    empty <- !nzchar(trimws(t))
    if (empty) {
      return("{}")
    }
    ev <- .escape_latex(trimws(t))
    if (isTRUE(is_header_row)) {
      return(sprintf("\\multicolumn{1}{c}{\\textbf{%s}}", ev))
    }
    if (isTRUE(is_section_row)) {
      if (j == 1L) return(sprintf("\\textbf{%s}", ev))
      return("{}")
    }
    if (j == 1L && isTRUE(is_level_row)) {
      return(sprintf("\\multicolumn{1}{c}{%s}", ev))
    }
    ev
  }

  row_lines <- character(0)
  for (i in seq_len(nr)) {
    is_h <- (i == 1L)
    v1 <- as.character(df[[1L]][i])
    is_sec <- !is_h && v1 %in% sec_names
    is_lvl <- !is_h && !is_sec && (i %in% lvl_set)
    vals <- vapply(seq_len(nc), function(j) as.character(df[[j]][i]), character(1))
    cells <- vapply(seq_len(nc), function(j) {
      .fmt_cell(vals[j], j, is_h, is_sec, is_lvl)
    }, character(1))
    row_lines <- c(row_lines, paste(paste(cells, collapse = " & "), "\\\\"))
  }

  header_lines <- c("\\toprule", row_lines[1L], "\\midrule")
  body_lines <- if (nr >= 2L) row_lines[seq.int(2L, nr)] else character(0)

  foot_blk <- character(0)
  if (length(footnotes) > 0L) {
    esc_f <- vapply(footnotes, function(f) .escape_latex(as.character(f)), character(1))
    foot_blk <- c(
      "\\vspace{0.6em}",
      "{\\footnotesize",
      "\\raggedright",
      paste(esc_f, collapse = "\\par\\noindent "),
      "}"
    )
  }

  cap <- if (nzchar(title)) paste0("\\caption*{", .escape_latex(title), "}\\\\") else ""

  use_lt <- isTRUE(use_longtable)
  if (use_lt) {
    inner <- .latex_longtable_booktabs_core(align, cap, header_lines, body_lines)
    latex <- c(
      "% \\documentclass{article}",
      "% \\usepackage[utf8]{inputenc}",
      "% \\usepackage[T1]{fontenc}",
      "% \\usepackage{times}",
      "% \\usepackage{booktabs}",
      "% \\usepackage{longtable}",
      "% \\usepackage{caption}",
      "",
      "% \\begin{document}",
      "",
      "\\renewcommand{\\arraystretch}{1.1}",
      "\\setlength{\\tabcolsep}{6pt}",
      "{\\small",
      inner,
      "}",
      foot_blk,
      "",
      "% \\end{document}"
    )
  } else {
    mid_block <- c(header_lines, body_lines, "\\bottomrule")
    latex <- c(
      "% \\documentclass{article}",
      "% \\usepackage[utf8]{inputenc}",
      "% \\usepackage[T1]{fontenc}",
      "% \\usepackage{times}",
      "% \\usepackage{booktabs}",
      "% \\usepackage{graphicx}",
      "% \\usepackage{caption}",
      "",
      "% \\begin{document}",
      "",
      "\\begin{table}[htbp]",
      "\\centering",
      "\\renewcommand{\\arraystretch}{1.1}",
      "\\setlength{\\tabcolsep}{6pt}",
      "\\small",
      if (nzchar(title)) paste0("\\caption*{", .escape_latex(title), "}\n") else "",
      "\\resizebox{\\textwidth}{!}{%",
      paste0("\\begin{tabular}{", align, "}"),
      mid_block,
      "\\end{tabular}",
      "}",
      foot_blk,
      "\\end{table}",
      "",
      "% \\end{document}"
    )
  }
  latex <- gsub("\u00b1", "$\\\\pm$", latex)
  latex <- gsub("\u2265", "$\\\\geq$", latex)
  latex
}

# ── 通用 SCI 三线表 xlsx：tbl_df_new 第 1 行为表头（列名作为单元格），其后为表体 ──
# openxlsx 在 CIFS/SMB 挂载上直接 overwrite=TRUE 可能无报错却保留旧工作簿。
# 始终先写同目录临时文件，再替换目标，确保重跑真正覆盖旧表。
.pub_xlsx_save_workbook_replace <- function(wb, filepath) {
  fd <- dirname(filepath)
  if (nzchar(fd) && !dir.exists(fd)) dir.create(fd, recursive = TRUE, showWarnings = FALSE)
  tmp <- tempfile(pattern = ".xlsx_write_", tmpdir = fd, fileext = ".xlsx")
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  openxlsx::saveWorkbook(wb, file = tmp, overwrite = TRUE)
  if (file.exists(filepath) && !isTRUE(unlink(filepath) == 0L)) {
    stop("Cannot replace existing xlsx: ", filepath, call. = FALSE)
  }
  ok <- file.rename(tmp, filepath)
  if (!isTRUE(ok)) {
    ok <- file.copy(tmp, filepath, overwrite = TRUE)
    if (isTRUE(ok)) unlink(tmp)
  }
  if (!isTRUE(ok) || !file.exists(filepath)) {
    stop("Failed to save xlsx: ", filepath, call. = FALSE)
  }
  invisible(filepath)
}

.sci_xlsx_write_three_line_workbook <- function(
    filepath,
    title,
    tbl_df_new,
    sheet = "Table",
    footnotes = NULL,
    insert_map = NULL,
    level_row_idx = integer(0)
) {
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    stop("Package 'openxlsx' is required.")
  }
  nc <- ncol(tbl_df_new)
  sh <- sheet
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, sh, gridLines = FALSE)

  header_title_style <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman", halign = "center",
    textDecoration = "bold"
  )
  header_three_line_style <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman", halign = "center",
    textDecoration = "bold",
    border = c("top", "bottom"),
    borderStyle = c("thick", "thin")
  )
  body_center_plain <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman", halign = "center"
  )
  body_left_plain <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman", halign = "left"
  )
  body_bold_left_plain <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman", halign = "left",
    textDecoration = "bold"
  )
  body_last_row_bottom_c <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman", halign = "center",
    border = "bottom", borderStyle = "thick"
  )
  body_last_row_bottom_l <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman", halign = "left",
    border = "bottom", borderStyle = "thick"
  )
  header_single_row_three_line <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman", halign = "center",
    textDecoration = "bold",
    border = c("top", "bottom"),
    borderStyle = c("thick", "thick")
  )
  footnote_merged_left <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman", halign = "left", valign = "center",
    wrapText = TRUE
  )
  footnote_first_row_top <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman", halign = "left", valign = "center",
    wrapText = TRUE, border = "top", borderStyle = "thin"
  )

  out_dir <- dirname(filepath)
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

  if (nzchar(title %||% "")) {
    openxlsx::writeData(
      wb, sheet = sh, x = title, startRow = 1L, startCol = 1L,
      colNames = FALSE, rowNames = FALSE
    )
    openxlsx::mergeCells(wb, sheet = sh, rows = 1L, cols = seq_len(nc))
    openxlsx::addStyle(
      wb, sheet = sh, style = header_title_style,
      rows = 1L, cols = seq_len(nc), gridExpand = TRUE
    )
    data_start_row <- 2L
  } else {
    data_start_row <- 1L
  }

  openxlsx::writeData(
    wb, sheet = sh, x = tbl_df_new, startRow = data_start_row, startCol = 1L,
    colNames = FALSE, rowNames = FALSE
  )
  hdr_row <- data_start_row
  openxlsx::addStyle(
    wb, sheet = sh,
    style = if (nrow(tbl_df_new) >= 2L) header_three_line_style else header_single_row_three_line,
    rows = hdr_row, cols = seq_len(nc), gridExpand = TRUE
  )

  n_tbl <- nrow(tbl_df_new)
  last_data_row <- data_start_row + n_tbl - 1L
  # writeData 将 tbl 第 i 行写在 Excel 行 (data_start_row + i - 1)；勿与「+ data_start_row」混淆
  level_excel_rows <- as.integer(level_row_idx) + as.integer(data_start_row) - 1L
  level_excel_rows <- level_excel_rows[
    level_excel_rows >= (data_start_row + 1L) & level_excel_rows <= last_data_row
  ]

  if (last_data_row >= (data_start_row + 1L)) {
    openxlsx::addStyle(
      wb, sheet = sh, style = body_center_plain,
      rows = (data_start_row + 1L):last_data_row, cols = 2L:nc, gridExpand = TRUE
    )
    openxlsx::addStyle(
      wb, sheet = sh, style = body_left_plain,
      rows = (data_start_row + 1L):last_data_row, cols = 1L, gridExpand = TRUE
    )
  }

  if (length(level_excel_rows) > 0L) {
    openxlsx::addStyle(
      wb, sheet = sh, style = body_center_plain,
      rows = level_excel_rows, cols = 1L, gridExpand = TRUE
    )
  }

  if (!is.null(insert_map) && length(insert_map) > 0L) {
    section_titles <- names(insert_map)
    section_title_rows <- which(tbl_df_new[[1L]] %in% section_titles)
    section_title_rows_excel <- section_title_rows + data_start_row - 1L
    section_title_rows_excel <- section_title_rows_excel[
      section_title_rows_excel >= data_start_row & section_title_rows_excel <= last_data_row
    ]
    if (length(section_title_rows_excel) > 0L) {
      openxlsx::addStyle(
        wb, sheet = sh, style = body_bold_left_plain,
        rows = section_title_rows_excel, cols = 1L, gridExpand = TRUE
      )
    }
  }

  if (last_data_row >= (data_start_row + 1L)) {
    if (nc >= 2L) {
      openxlsx::addStyle(
        wb, sheet = sh, style = body_last_row_bottom_c,
        rows = last_data_row, cols = 2L:nc, gridExpand = TRUE
      )
    }
    lr_c1 <- if (last_data_row %in% level_excel_rows) {
      body_last_row_bottom_c
    } else {
      body_last_row_bottom_l
    }
    openxlsx::addStyle(
      wb, sheet = sh, style = lr_c1,
      rows = last_data_row, cols = 1L, gridExpand = TRUE
    )
  }

  n_foot <- length(footnotes)
  if (n_foot > 0L) {
    first_foot_row <- last_data_row + 1L
    last_foot_row <- last_data_row + n_foot
    for (i in seq_len(n_foot)) {
      r <- last_data_row + i
      openxlsx::mergeCells(wb, sheet = sh, rows = r, cols = seq_len(nc))
      openxlsx::writeData(
        wb, sheet = sh, x = footnotes[[i]], startRow = r, startCol = 1L,
        colNames = FALSE, rowNames = FALSE
      )
    }
    openxlsx::addStyle(
      wb, sheet = sh, style = footnote_first_row_top,
      rows = first_foot_row, cols = seq_len(nc), gridExpand = TRUE
    )
    if (last_foot_row > first_foot_row) {
      openxlsx::addStyle(
        wb, sheet = sh, style = footnote_merged_left,
        rows = (first_foot_row + 1L):last_foot_row, cols = seq_len(nc),
        gridExpand = TRUE
      )
    }
  }

  openxlsx::setColWidths(wb, sheet = sh, cols = seq_len(nc), widths = "auto")
  fd <- dirname(filepath)
  if (nzchar(fd) && !dir.exists(fd)) dir.create(fd, recursive = TRUE, showWarnings = FALSE)
  save_fp <- filepath
  if (.Platform$OS.type == "windows") {
    abs_fp <- normalizePath(filepath, winslash = "\\", mustWork = FALSE)
    if (nchar(abs_fp) >= 260) save_fp <- paste0("\\\\?\\", abs_fp)
  }
  .pub_xlsx_save_workbook_replace(wb, save_fp)
  if (exists(".competing_xlsx_fix_drawings", mode = "function")) {
    try(.competing_xlsx_fix_drawings(filepath), silent = TRUE)
  }
  invisible(filepath)
}

# 单行表头：df 为表体（列名在 names(df)），与 Table 1 同式三线表 xlsx
# level_row_idx：tbl_df_new 中行号（含第 1 行表头），首列用居中；Table S1 分类水平行由 block_imputation 传入
sci_xlsx_single_header_booktabs <- function(filepath, title, df_body, sheet = "Table",
                                            footnotes = NULL, level_row_idx = NULL,
                                            blank_na_cells = TRUE) {
  df_body <- as.data.frame(df_body, stringsAsFactors = FALSE)
  if (isTRUE(blank_na_cells)) {
    df_body <- .table1_blank_na_cells(df_body)
  }
  hdr <- stats::setNames(
    as.data.frame(t(colnames(df_body)), stringsAsFactors = FALSE),
    colnames(df_body)
  )
  tbl_df_new <- rbind(hdr, df_body)
  tbl_df_new[1L, ] <- gsub("\\*", "", as.character(tbl_df_new[1L, ]))
  colnames(tbl_df_new) <- gsub("\\*\\*", "", colnames(tbl_df_new))
  tbl_df_new <- .table1_strip_underscores_display(tbl_df_new)
  if (!is.null(footnotes)) {
    footnotes <- as.character(unlist(footnotes, use.names = FALSE))
    footnotes <- footnotes[nzchar(trimws(footnotes))]
    if (exists("pipeline_scrub_pub_text", mode = "function")) {
      footnotes <- pipeline_scrub_pub_text(footnotes)
    } else {
      footnotes <- gsub("_", " ", footnotes, fixed = TRUE)
    }
  }
  lr <- if (is.null(level_row_idx) || !length(level_row_idx)) {
    integer(0)
  } else {
    as.integer(level_row_idx)
  }
  .sci_xlsx_write_three_line_workbook(
    filepath, title %||% "", tbl_df_new, sheet = sheet,
    footnotes = footnotes, insert_map = NULL, level_row_idx = lr
  )
}

# 双行表头 xlsx：与队列中 flatten/merge 逻辑一致；footnotes 在表体底线下方、跨列左对齐（同 Table 1）
.sci_xlsx_double_header_booktabs <- function(filepath, title, df_body, h1, h2, sheet = "Table",
                                              footnotes = NULL) {
  df_body <- as.data.frame(df_body, stringsAsFactors = FALSE)
  df_body <- .table1_blank_na_cells(df_body)
  df_body <- .table1_strip_underscores_display(df_body)
  nc <- ncol(df_body)
  if (length(h1) != nc || length(h2) != nc) {
    stop("header_row1/header_row2 length must match ncol(df).")
  }
  sh <- sheet
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, sh, gridLines = FALSE)

  header_title_style <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman", halign = "center",
    textDecoration = "bold"
  )
  h1_line_style <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman", halign = "center",
    textDecoration = "bold",
    border = c("top", "bottom"), borderStyle = c("thick", "thin")
  )
  h2_line_style <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman", halign = "center",
    textDecoration = "bold",
    border = "bottom", borderStyle = "thin"
  )
  body_center_plain <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman", halign = "center"
  )
  body_left_plain <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman", halign = "left"
  )
  body_last_row_bottom_c <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman", halign = "center",
    border = "bottom", borderStyle = "thick"
  )
  body_last_row_bottom_l <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman", halign = "left",
    border = "bottom", borderStyle = "thick"
  )

  out_dir <- dirname(filepath)
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

  r_h1 <- 1L
  if (nzchar(title %||% "")) {
    openxlsx::writeData(wb, sheet = sh, x = title, startRow = 1L, startCol = 1L,
                        colNames = FALSE, rowNames = FALSE)
    openxlsx::mergeCells(wb, sheet = sh, rows = 1L, cols = seq_len(nc))
    openxlsx::addStyle(
      wb, sheet = sh, style = header_title_style,
      rows = 1L, cols = seq_len(nc), gridExpand = TRUE
    )
    # 表头紧贴标题下一行（勿用 r_h1=3，否则第 2 行为全表空白行）
    r_h1 <- 2L
  }

  h1_flat <- .flatten_header_row_for_xlsx(h1)
  h2_flat <- vapply(h2, function(x) if (is.na(x)) "" else as.character(x), character(1))
  openxlsx::writeData(wb, sheet = sh, matrix(h1_flat, nrow = 1L), startRow = r_h1, colNames = FALSE)
  openxlsx::writeData(wb, sheet = sh, matrix(h2_flat, nrow = 1L), startRow = r_h1 + 1L, colNames = FALSE)
  for (ab in .header_merge_col_ranges(h1)) {
    openxlsx::mergeCells(wb, sheet = sh, rows = r_h1, cols = ab[1]:ab[2])
  }
  openxlsx::writeData(
    wb, sheet = sh, x = df_body, startRow = r_h1 + 2L, startCol = 1L,
    colNames = FALSE, rowNames = FALSE
  )

  openxlsx::addStyle(
    wb, sheet = sh, style = h1_line_style,
    rows = r_h1, cols = seq_len(nc), gridExpand = TRUE
  )
  openxlsx::addStyle(
    wb, sheet = sh, style = h2_line_style,
    rows = r_h1 + 1L, cols = seq_len(nc), gridExpand = TRUE
  )

  n_body <- nrow(df_body)
  last_data_row <- r_h1 + 1L + n_body
  if (n_body > 0L) {
    openxlsx::addStyle(
      wb, sheet = sh, style = body_center_plain,
      rows = (r_h1 + 2L):last_data_row, cols = 2L:nc, gridExpand = TRUE
    )
    openxlsx::addStyle(
      wb, sheet = sh, style = body_left_plain,
      rows = (r_h1 + 2L):last_data_row, cols = 1L, gridExpand = TRUE
    )
    openxlsx::addStyle(
      wb, sheet = sh, style = body_last_row_bottom_c,
      rows = last_data_row, cols = 2L:nc, gridExpand = TRUE
    )
    openxlsx::addStyle(
      wb, sheet = sh, style = body_last_row_bottom_l,
      rows = last_data_row, cols = 1L, gridExpand = TRUE
    )
  }

  if (!is.null(footnotes)) {
    footnotes <- as.character(unlist(footnotes, use.names = FALSE))
    footnotes <- footnotes[nzchar(trimws(footnotes))]
  }
  n_foot <- length(footnotes)
  if (n_foot > 0L) {
    footnote_merged_left <- openxlsx::createStyle(
      fontSize = 12, fontName = "Times New Roman", halign = "left", valign = "center",
      wrapText = TRUE
    )
    footnote_first_row_top <- openxlsx::createStyle(
      fontSize = 12, fontName = "Times New Roman", halign = "left", valign = "center",
      wrapText = TRUE, border = "top", borderStyle = "thin"
    )
    first_foot_row <- last_data_row + 1L
    last_foot_row <- last_data_row + n_foot
    for (i in seq_len(n_foot)) {
      r <- last_data_row + i
      openxlsx::mergeCells(wb, sheet = sh, rows = r, cols = seq_len(nc))
      openxlsx::writeData(
        wb, sheet = sh, x = footnotes[[i]], startRow = r, startCol = 1L,
        colNames = FALSE, rowNames = FALSE
      )
    }
    openxlsx::addStyle(
      wb, sheet = sh, style = footnote_first_row_top,
      rows = first_foot_row, cols = seq_len(nc), gridExpand = TRUE
    )
    if (last_foot_row > first_foot_row) {
      openxlsx::addStyle(
        wb, sheet = sh, style = footnote_merged_left,
        rows = (first_foot_row + 1L):last_foot_row, cols = seq_len(nc),
        gridExpand = TRUE
      )
    }
  }

  openxlsx::setColWidths(wb, sheet = sh, cols = seq_len(nc), widths = "auto")
  fd <- dirname(filepath)
  if (nzchar(fd) && !dir.exists(fd)) dir.create(fd, recursive = TRUE, showWarnings = FALSE)
  save_fp <- filepath
  if (.Platform$OS.type == "windows") {
    abs_fp <- normalizePath(filepath, winslash = "\\", mustWork = FALSE)
    if (nchar(abs_fp) >= 260) save_fp <- paste0("\\\\?\\", abs_fp)
  }
  .pub_xlsx_save_workbook_replace(wb, save_fp)
  if (exists(".competing_xlsx_fix_drawings", mode = "function")) {
    try(.competing_xlsx_fix_drawings(filepath), silent = TRUE)
  }
  invisible(filepath)
}

# ── Table 1 xlsx：SCI 三线表（顶线粗、表头下细线、底线粗；无竖线、表体无内横线）；脚注在表外、合并左对齐
# section_insert_rows / section_anchors 同上
# center_first_col_values: 额外指定首列居中的文本（可选）；若提供 gtsummary_tbl 则自动将分类 level 行首列居中
# gtsummary_tbl: 用于识别 row_type=="level" 的行以居中分类水平
write_table1_xlsx_guan_style <- function(
    tbl_df,
    filepath,
    title,
    section_insert_rows = NULL,
    section_anchors = NULL,
    center_first_col_values = character(0),
    gtsummary_tbl = NULL,
    footnotes = NULL,
    prebuilt = NULL,
    sheet = "Sheet1"
) {
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    stop("Package 'openxlsx' is required for write_table1_xlsx_guan_style().")
  }
  if (is.null(footnotes) || length(footnotes) == 0L) {
    footnotes <- table1_baseline_xlsx_footnotes()
  } else {
    footnotes <- as.character(unlist(footnotes, use.names = FALSE))
    footnotes <- footnotes[nzchar(trimws(footnotes))]
  }
  if (!is.null(prebuilt) && is.list(prebuilt) && !is.null(prebuilt$df)) {
    tbl_df_new <- prebuilt$df
    insert_map <- prebuilt$insert_map
    level_row_idx <- prebuilt$level_row_idx
    nc <- prebuilt$ncol
  } else {
    built <- table1_build_display_df(
      tbl_df,
      section_insert_rows = section_insert_rows,
      section_anchors = section_anchors,
      gtsummary_tbl = gtsummary_tbl,
      center_first_col_values = center_first_col_values
    )
    tbl_df_new <- built$df
    insert_map <- built$insert_map
    level_row_idx <- built$level_row_idx
    nc <- built$ncol
  }

  .sci_xlsx_write_three_line_workbook(
    filepath,
    title,
    tbl_df_new,
    sheet = sheet,
    footnotes = footnotes,
    insert_map = insert_map,
    level_row_idx = level_row_idx
  )
}

.as_latex_path <- function(filepath) {
  if (grepl("\\.[A-Za-z0-9]+$", filepath)) {
    return(sub("\\.[A-Za-z0-9]+$", ".tex", filepath))
  }
  paste0(filepath, ".tex")
}

# 双行表头 LaTeX：h1 中 NA 表示与左侧合并；或与左侧单元格文本相同且非空时合并（与 multiclass 表一致）
.latex_multicolumn_header_row <- function(h1) {
  n <- length(h1)
  parts <- character(0)
  i <- 1L
  while (i <= n) {
    if (is.na(h1[i])) {
      i <- i + 1L
      next
    }
    j <- i
    vi <- as.character(h1[i])
    tvi <- trimws(vi)
    while (j < n) {
      vnext <- h1[j + 1L]
      if (is.na(vnext)) {
        j <- j + 1L
      } else if (nzchar(tvi) && identical(trimws(as.character(vnext)), tvi)) {
        j <- j + 1L
      } else {
        break
      }
    }
    span <- j - i + 1L
    txt <- .escape_latex(vi)
    tvi_cell <- trimws(as.character(vi))
    is_empty <- (length(tvi_cell) == 1L && is.na(tvi_cell)) || !nzchar(tvi_cell)
    parts <- c(parts, if (is_empty) {
      if (span > 1L) sprintf("\\multicolumn{%d}{c}{}", span) else "{}"
    } else if (span > 1L) {
      sprintf("\\multicolumn{%d}{c}{\\textbf{%s}}", span, txt)
    } else {
      sprintf("\\textbf{%s}", txt)
    })
    i <- j + 1L
  }
  paste(parts, collapse = " & ")
}

# Excel 双行表头：合并区仅保留首格文本，其余置空
.flatten_header_row_for_xlsx <- function(h1) {
  n <- length(h1)
  out <- rep("", n)
  i <- 1L
  while (i <= n) {
    if (is.na(h1[i])) {
      i <- i + 1L
      next
    }
    j <- i
    vi <- as.character(h1[i])
    tvi <- trimws(vi)
    while (j < n) {
      vnext <- h1[j + 1L]
      if (is.na(vnext)) {
        j <- j + 1L
      } else if (nzchar(tvi) && identical(trimws(as.character(vnext)), tvi)) {
        j <- j + 1L
      } else {
        break
      }
    }
    out[i] <- vi
    i <- j + 1L
  }
  out
}

.header_merge_col_ranges <- function(h1) {
  n <- length(h1)
  rng <- list()
  i <- 1L
  while (i <= n) {
    if (is.na(h1[i])) {
      i <- i + 1L
      next
    }
    j <- i
    vi <- as.character(h1[i])
    tvi <- trimws(vi)
    while (j < n) {
      vnext <- h1[j + 1L]
      if (is.na(vnext)) {
        j <- j + 1L
      } else if (nzchar(tvi) && identical(trimws(as.character(vnext)), tvi)) {
        j <- j + 1L
      } else {
        break
      }
    }
    if (j > i) rng[[length(rng) + 1L]] <- c(i, j)
    i <- j + 1L
  }
  rng
}

.escape_latex <- function(x) {
  x <- as.character(x)
  x <- gsub("\\\\", "\\\\textbackslash{}", x)
  x <- gsub("#", "\\#", x, fixed = TRUE)
  x <- gsub("%", "\\%", x, fixed = TRUE)
  x <- gsub("&", "\\&", x, fixed = TRUE)
  x <- gsub("_", "\\_", x, fixed = TRUE)
  x <- gsub("{", "\\{", x, fixed = TRUE)
  x <- gsub("}", "\\}", x, fixed = TRUE)
  x <- gsub("~", "\\\\textasciitilde{}", x, fixed = TRUE)
  x <- gsub("\\^", "\\\\textasciicircum{}", x)
  x <- gsub("\\\\\\\\%", "\\\\%", x)
  x <- gsub("<", "\\textless{}", x, fixed = TRUE)
  x <- gsub(">", "\\textgreater{}", x, fixed = TRUE)
  x
}

# booktabs 单元格：空 / NA -> {}，否则转义（与 Table 1 同源 TeX 一致）
.escape_latex_cell <- function(raw) {
  if (length(raw) != 1L) return("{}")
  if (is.na(raw)) return("{}")
  t <- trimws(as.character(raw))
  if (identical(t, NA_character_) || !nzchar(t)) return("{}")
  .escape_latex(t)
}

.prepare_df_for_tex <- function(df, filepath = "") {
  if (!is.data.frame(df) || ncol(df) == 0) return(df)
  
  # 统一清理 markdown 标记与无效文本
  names(df) <- gsub("\\*\\*|__", "", names(df))
  names(df) <- gsub("\r|\n", " ", names(df))
  names(df) <- gsub("\\s+", " ", names(df))
  names(df) <- trimws(names(df))
  
  is_baseline <- grepl("^Table 1", basename(filepath %||% ""), ignore.case = TRUE)

  for (cn in names(df)) {
    if (!nzchar(cn)) next
    raw_col <- df[[cn]]
    if (is.null(raw_col)) next
    x <- as.character(raw_col)
    if (!length(x)) next
    x <- gsub("\\*\\*|__", "", x)
    x <- gsub("\r|\n", " ", x)
    x <- gsub("\\s+", " ", x)
    x <- trimws(x)
    x[is.na(raw_col)] <- ""
    x[toupper(x) %in% c("NA", "N/A", "<NA>", "NAN", "NULL")] <- ""
    if (length(x) == nrow(df)) df[[cn]] <- x
  }

  # 下划线转空格：列名 + 所有字符列（发表表统一）
  names(df) <- gsub("_", " ", names(df), fixed = TRUE)
  for (cn in names(df)) {
    if (is.character(df[[cn]])) df[[cn]] <- gsub("_", " ", df[[cn]], fixed = TRUE)
  }
  # 常见年龄分组展示：「30 44」规范为「30-44」
  for (cn in names(df)) {
    if (is.character(df[[cn]])) {
      df[[cn]] <- gsub("([0-9]{2})\\s+([0-9]{2})", "\\1-\\2", df[[cn]], perl = TRUE)
    }
  }
  # 发表级整数千分位守卫：把计数类整数（人数 / 事件数 / n(%) 中的 n）统一成 "1,234"。
  # 只在「计数上下文」触发（同格含 %、/ 或 N=/n= 标记），避免误伤年份 / 年段（2006-2010）。
  # 口径由 config$pub_digits$int_big_mark 决定（FALSE 时跳过，保持 1234）。
  if (isTRUE(.pipeline_pub_digits()$int_big_mark)) {
    for (cn in names(df)) {
      if (is.character(df[[cn]])) df[[cn]] <- .pub_group_count_ints(df[[cn]])
    }
    names(df) <- .pub_group_count_ints(names(df))
  }
  first_col <- names(df)[1L]
  last_col <- names(df)[ncol(df)]

  # Table 1：分类水平行首列缩进（与 xlsx level_row_idx 一致）
  if (isTRUE(is_baseline) && ncol(df) >= 3L) {
    middle_cols <- names(df)[2:(ncol(df) - 1)]
    header_rows <- apply(df[, middle_cols, drop = FALSE], 1, function(r) {
      vals <- trimws(as.character(r))
      all(vals == "")
    })
    level_rows <- (!header_rows) &
      trimws(df[[last_col]]) == "" &
      apply(df[, middle_cols, drop = FALSE], 1, function(r) {
        vals <- trimws(as.character(r))
        any(vals != "")
      })
    level_rows[is.na(level_rows)] <- FALSE
    df[[first_col]][level_rows] <- paste0("  ", trimws(df[[first_col]][level_rows]))
  }

  df
}

.write_lines_safe <- function(text, path, useBytes = TRUE) {
  if (.Platform$OS.type == "windows") {
    abs_p <- normalizePath(path, winslash = "\\", mustWork = FALSE)
    if (nchar(abs_p) >= 260) {
      tmp <- tempfile(fileext = tools::file_ext(path))
      on.exit(unlink(tmp), add = TRUE)
      writeLines(text, tmp, useBytes = useBytes)
      long_dest <- paste0("\\\\?\\", abs_p)
      file.copy(tmp, long_dest, overwrite = TRUE)
      return(invisible(path))
    }
  }
  writeLines(text, path, useBytes = useBytes)
  invisible(path)
}

render_queued_tables <- function(ctx) {
  q <- .table_queue_env$items %||% list()
  if (length(q) == 0) {
    cli::cli_alert_info("No queued tables to render.")
    return(ctx)
  }
  for (it in q) {
    df_raw <- as.data.frame(it$df, stringsAsFactors = FALSE)
    if (!isTRUE(it$excel_use_prepared %||% TRUE)) {
      df_raw <- .pub_df_cells_underscores_to_spaces(df_raw)
    }
    title_render <- .pub_charvec_underscores(it$title %||% "")
    df_tex <- .prepare_df_for_tex(df_raw, it$filepath %||% "")
    df_xlsx <- if (isTRUE(it$excel_use_prepared %||% TRUE)) df_tex else df_raw
    tex_path <- .as_latex_path(it$filepath)
    latex_include_colnames <- it$latex_include_colnames %||% TRUE
    overwrite_tex <- it$overwrite_tex %||% TRUE
    row_top_borders_idx <- it$row_top_borders_idx %||% integer(0)
    if (length(row_top_borders_idx) > 0) {
      row_top_borders_idx <- as.integer(row_top_borders_idx)
      row_top_borders_idx <- row_top_borders_idx[is.finite(row_top_borders_idx)]
    }
    tf <- it$table_footnotes
    if (!is.null(tf)) {
      tf <- as.character(unlist(tf, use.names = FALSE))
      tf <- tf[nzchar(trimws(tf))]
      tf <- .pub_charvec_underscores(tf)
    } else {
      tf <- character(0)
    }

    # 1) 导出 xlsx：与 Table 1 同式 SCI 三线表（Times、顶/底粗线、无竖线、关网格）
    #    默认与 .tex 共用 .prepare_df_for_tex；若需保留原始单元格：excel_use_prepared = FALSE
    if (!is.null(it$filepath) && nzchar(it$filepath) && !isTRUE(it$skip_excel)) {
      tryCatch({
        if (!requireNamespace("openxlsx", quietly = TRUE)) {
          stop("Package 'openxlsx' is required to export xlsx tables.")
        }
        df_x <- as.data.frame(df_xlsx, stringsAsFactors = FALSE)
        if (isTRUE(it$blank_na_cells %||% TRUE)) {
          df_x <- .table1_blank_na_cells(df_x)
        }
        h1_x <- it$header_row1
        h2_x <- it$header_row2
        if (!is.null(h1_x)) h1_x <- .pub_charvec_underscores(h1_x)
        if (!is.null(h2_x)) h2_x <- .pub_charvec_underscores(h2_x)
        nc_x <- ncol(df_x)
        use_dbl_xlsx <- !is.null(h1_x) && !is.null(h2_x) &&
          length(h1_x) == nc_x && length(h2_x) == nc_x
        sh <- it$sheet %||% "Table"
        if (isTRUE(use_dbl_xlsx)) {
          .sci_xlsx_double_header_booktabs(
            it$filepath, title_render, df_x, h1_x, h2_x, sheet = sh,
            footnotes = if (length(tf) > 0L) tf else NULL
          )
        } else {
          lr_x <- it$excel_level_row_idx %||% NULL
          if (!is.null(lr_x) && length(lr_x)) lr_x <- as.integer(lr_x)
          sci_xlsx_single_header_booktabs(
            it$filepath, title_render, df_x, sheet = sh,
            footnotes = if (length(tf) > 0L) tf else NULL,
            level_row_idx = lr_x,
            blank_na_cells = isTRUE(it$blank_na_cells %||% TRUE)
          )
        }
        cli::cli_alert_success("Excel table saved (SCI 三线表): {.file {basename(it$filepath)}}")
        mirror_pub_output_to_root(ctx, it$filepath)
      }, error = function(e) {
        cli::cli_alert_warning("Excel export failed ({basename(it$filepath)}): {e$message}")
      })
    }
    
    # 2) 再导出 tex（仅 step 子目录；汇总 Tables 不写 .tex）
    write_tex_here <- nzchar(tex_path) &&
      !pipeline_is_aggregate_pub_tables_path(tex_path)
    if (!write_tex_here) {
      if (nzchar(tex_path) && file.exists(tex_path) &&
          pipeline_is_aggregate_pub_tables_path(tex_path)) {
        unlink(tex_path)
      }
    } else if (!overwrite_tex && file.exists(tex_path)) {
      cli::cli_alert_info("LaTeX 已存在且 overwrite_tex=FALSE，跳过: {.file {basename(tex_path)}}")
    } else {
      if (nzchar(tex_path)) {
        td <- dirname(tex_path)
        if (nzchar(td) && !dir.exists(td)) {
          dir.create(td, recursive = TRUE, showWarnings = FALSE)
        }
      }
      use_lt <- isTRUE(it$latex_use_longtable %||% TRUE)
      spec <- it$table1_render_spec
      if (!is.null(spec) && is.list(spec) && is.data.frame(spec$df) &&
          nrow(spec$df) >= 1L && ncol(spec$df) >= 1L) {
        ft <- spec$footnotes
        if (is.null(ft)) ft <- character(0)
        ft <- as.character(unlist(ft, use.names = FALSE))
        ft <- ft[nzchar(trimws(ft))]
        ft <- .pub_charvec_underscores(ft)
        use_lt_eff <- use_lt && length(ft) == 0L
        if (use_lt && !use_lt_eff) {
          cli::cli_alert_info("检测到表格脚注，LaTeX 自动改为非 longtable（脚注不分页）。")
        }
        spec_df <- .pub_df_cells_underscores_to_spaces(as.data.frame(spec$df, stringsAsFactors = FALSE))
        latex_doc <- table1_booktabs_latex_document(
          spec_df,
          title = title_render,
          footnotes = ft,
          insert_map = spec$insert_map %||% NULL,
          level_row_idx = as.integer(spec$level_row_idx %||% integer(0)),
          latex_align = it$latex_align,
          use_longtable = use_lt_eff
        )
        tryCatch({
          .write_lines_safe(latex_doc, tex_path, useBytes = TRUE)
          cli::cli_alert_success(
            "LaTeX table saved (booktabs{if (use_lt_eff) ' + longtable' else ''}, matches xlsx): {.file {basename(tex_path)}}"
          )
          mirror_pub_output_to_root(ctx, tex_path)
        }, error = function(e) {
          cli::cli_alert_warning("LaTeX export failed ({basename(tex_path)}): {e$message}")
        })
      } else {
      df <- .table1_blank_na_cells(as.data.frame(df_tex, stringsAsFactors = FALSE))
      cols <- names(df)
      align <- if (!is.null(it$latex_align) && nzchar(it$latex_align)) {
        it$latex_align
      } else {
        paste0("l", paste(rep("c", max(0, length(cols) - 1)), collapse = ""))
      }
      h1_tex <- it$header_row1
      h2_tex <- it$header_row2
      if (!is.null(h1_tex)) h1_tex <- .pub_charvec_underscores(h1_tex)
      if (!is.null(h2_tex)) h2_tex <- .pub_charvec_underscores(h2_tex)
      use_dbl_tex <- !is.null(h1_tex) && !is.null(h2_tex) &&
        length(h1_tex) == ncol(df) && length(h2_tex) == ncol(df)
      header_line <- if (isTRUE(use_dbl_tex)) {
        NULL
      } else if (isTRUE(latex_include_colnames)) {
        paste(
          vapply(cols, function(cn) {
            sprintf("\\multicolumn{1}{c}{\\textbf{%s}}", .escape_latex(cn))
          }, character(1)),
          collapse = " & "
        )
      } else {
        NULL
      }
      # 单列表头：excel_level_row_idx = 含表头时的 Excel 行号；TeX 表体第 i 行对应 idx - 1。
      # Table S1：.prepare_df_for_tex 对首列 trimws，无法用「前导空格」识别分类水平，须与 xlsx 共用 excel_level_row_idx。
      lx_lv <- it$excel_level_row_idx %||% integer(0)
      if (length(lx_lv) > 0L) {
        lx_lv <- as.integer(lx_lv) - 1L
        lx_lv <- lx_lv[is.finite(lx_lv) & lx_lv >= 1L & lx_lv <= nrow(df)]
      } else {
        lx_lv <- integer(0)
      }
      body <- vapply(seq_len(nrow(df)), function(i) {
        row_vals <- as.character(df[i, , drop = TRUE])
        first_raw <- row_vals[1]
        first_trim <- trimws(first_raw)
        center_first <- (i %in% lx_lv) ||
          (grepl("^\\s{2,}", first_raw) && nzchar(first_trim))
        first_cell <- if (center_first && nzchar(first_trim)) {
          paste0("\\multicolumn{1}{c}{", .escape_latex(first_trim), "}")
        } else {
          .escape_latex_cell(first_raw)
        }
        if (length(row_vals) == 1) {
          line <- first_cell
        } else {
          other_cells <- vapply(row_vals[-1], .escape_latex_cell, character(1))
          line <- paste(c(first_cell, other_cells), collapse = " & ")
        }
        if (i %in% row_top_borders_idx) paste0("\\midrule\n", line) else line
      }, character(1))
      
      cap_float <- if (nzchar(title_render %||% "")) {
        paste0("\\caption*{", .escape_latex(title_render), "}\n")
      } else {
        ""
      }
      cap_lt <- if (nzchar(title_render %||% "")) {
        paste0("\\caption*{", .escape_latex(title_render), "}\\\\")
      } else {
        ""
      }

      body_lines <- paste0(body, " \\\\")
      header_lines <- if (isTRUE(use_dbl_tex)) {
        line_h1 <- .latex_multicolumn_header_row(h1_tex)
        line_h2 <- paste(vapply(h2_tex, function(x) {
          tx <- if (is.na(x)) "" else trimws(as.character(x))
          if (!nzchar(tx)) {
            "{}"
          } else {
            sprintf("\\multicolumn{1}{c}{\\textbf{%s}}", .escape_latex(tx))
          }
        }, character(1)), collapse = " & ")
        c(
          "\\toprule",
          paste0(line_h1, " \\\\"),
          "\\midrule",
          paste0(line_h2, " \\\\"),
          "\\midrule"
        )
      } else if (is.null(header_line)) {
        "\\toprule"
      } else {
        c("\\toprule", paste0(header_line, " \\\\"), "\\midrule")
      }

      foot_blk <- character(0)
      if (length(tf) > 0L) {
        esc_f <- vapply(tf, function(f) .escape_latex(as.character(f)), character(1))
        foot_blk <- c(
          "\\vspace{0.6em}",
          "{\\footnotesize",
          "\\raggedright",
          paste(esc_f, collapse = "\\par\\noindent "),
          "}"
        )
      }

      use_lt_eff <- use_lt

      if (use_lt_eff) {
        inner <- .latex_longtable_booktabs_core(align, cap_lt, header_lines, body_lines)
        latex <- c(
          "% \\documentclass{article}",
          "% \\usepackage[utf8]{inputenc}",
          "% \\usepackage[T1]{fontenc}",
          "% \\usepackage{times}",
          "% \\usepackage{booktabs}",
          "% \\usepackage{longtable}",
          "% \\usepackage{caption}",
          "",
          "% \\begin{document}",
          "",
          "\\renewcommand{\\arraystretch}{1.1}",
          "\\setlength{\\tabcolsep}{6pt}",
          "{\\small",
          inner,
          "}",
          foot_blk,
          "",
          "% \\end{document}"
        )
      } else {
        mid_block <- c(header_lines, body_lines, "\\bottomrule")
        latex <- c(
          "% \\documentclass{article}",
          "% \\usepackage[utf8]{inputenc}",
          "% \\usepackage[T1]{fontenc}",
          "% \\usepackage{times}",
          "% \\usepackage{booktabs}",
          "% \\usepackage{graphicx}",
          "% \\usepackage{caption}",
          "",
          "% \\begin{document}",
          "",
          "\\begin{table}[htbp]",
          "\\centering",
          "\\renewcommand{\\arraystretch}{1.1}",
          "\\setlength{\\tabcolsep}{6pt}",
          "\\small",
          cap_float,
          "\\resizebox{\\textwidth}{!}{%",
          paste0("\\begin{tabular}{", align, "}"),
          mid_block,
          "\\end{tabular}",
          "}",
          foot_blk,
          "\\end{table}",
          "",
          "% \\end{document}"
        )
      }

      latex <- gsub("\u00b1", "$\\\\pm$", latex)
      latex <- gsub("\u2265", "$\\\\geq$", latex)

      tryCatch({
        .write_lines_safe(latex, tex_path, useBytes = TRUE)
        cli::cli_alert_success(
          "LaTeX table saved (booktabs{if (use_lt_eff) ' + longtable' else ''}): {.file {basename(tex_path)}}"
        )
        mirror_pub_output_to_root(ctx, tex_path)
      }, error = function(e) {
        cli::cli_alert_warning("LaTeX export failed ({basename(tex_path)}): {e$message}")
      })
      }
    }
  }
  .table_queue_env$items <- list()
  ctx
}

# plot_fn 只应 return 对象。ggsurvplot 默认 print(newpage=TRUE) 会先空一页。
.print_queued_plot_object <- function(out) {
  if (is.null(out)) return(invisible(NULL))
  if (inherits(out, "ggsurvplot")) {
    print(out, newpage = FALSE)
    return(invisible(out))
  }
  if (inherits(out, c("ggplot", "patchwork", "gg", "gtable", "grob", "HeatmapList", "Heatmap"))) {
    print(out)
  }
  invisible(out)
}

render_queued_figures <- function(ctx) {
  q <- ctx$results$figure_queue %||% list()
  if (length(q) == 0) {
    cli::cli_alert_info("No queued figures to render.")
    return(ctx)
  }
  pref <- ctx$config$plot$font_family %||% "Times New Roman"
  font_family <- plot_font_from_config(ctx$config)
  if (!identical(font_family, pref)) {
    cli::cli_alert_info(
      "字体 '{pref}' 在当前 PDF 设备不可用，已使用 '{font_family}'（Times 系，接近新罗马）。"
    )
  }
  # 有 cairo 时走 pipeline_pdf_device（cairo_pdf + 已探测可用字体）。
  # 禁止对标准 pdf() 传 "Times New Roman"：Windows/Linux 都会 unknown family，图全部入队失败。
  pdf_dev <- tolower(trimws(ctx$config$plot$pdf_device %||% "auto"))
  # 强制标准 pdf() 时，主题/par 必须用 PostScript 名（Times），不能留 Times New Roman
  if (identical(pdf_dev, "pdf") && identical(font_family, "Times New Roman")) {
    font_family <- "Times"
    cli::cli_alert_info("plot$pdf_device=pdf：主题字体改用 Times（避免 PostScript DB 找不到 Times New Roman）。")
  }

  .with_plot_theme <- function(plot_fn, ff = font_family) {
    old_theme <- ggplot2::theme_get()
    old_par <- graphics::par(no.readonly = TRUE)
    on.exit({
      ggplot2::theme_set(old_theme)
      # 仅在无活动作图设备或 null device 时恢复 par，避免 PDF 多出一页
      if (grDevices::dev.cur() <= 1L) {
        try(graphics::par(old_par), silent = TRUE)
      }
    }, add = FALSE)
    # 标准 pdf 设备：par/theme 用 Times；cairo 可用系统字体名
    ff_par <- if (!isTRUE(capabilities("cairo")) || identical(pdf_dev, "pdf")) {
      if (identical(ff, "Times New Roman")) "Times" else ff
    } else {
      ff
    }
    graphics::par(family = ff_par)
    ggplot2::theme_set(
      ggplot2::theme_get() +
        ggplot2::theme(
          text = ggplot2::element_text(family = ff_par),
          axis.text = ggplot2::element_text(family = ff_par),
          axis.title = ggplot2::element_text(family = ff_par),
          plot.title = ggplot2::element_text(family = ff_par),
          legend.text = ggplot2::element_text(family = ff_par),
          strip.text = ggplot2::element_text(family = ff_par)
        )
    )
    out <- plot_fn()
    # ggplot / patchwork 等需显式 print 才写入设备；否则会出现空 PDF（仅壳）。
    # 约定：plot_fn 只 return 对象，不要内部 print()——否则会打成两页。
    # 禁止在此处调用 grid::grid.ls()：它会初始化 grid，导致随后 print(ggplot) 变成 2 页。
    .print_queued_plot_object(out)
    invisible(out)
  }

  .open_pdf <- function(path, width, height, ff = font_family) {
    if (identical(pdf_dev, "pdf")) {
      ff_dev <- if (identical(ff, "Times New Roman")) "Times" else ff
      grDevices::pdf(
        path, width = width, height = height, family = ff_dev,
        useDingbats = FALSE, compress = TRUE
      )
    } else if (exists("pipeline_pdf_device", mode = "function")) {
      pipeline_pdf_device(path, width = width, height = height, family = ff)
    } else if (identical(pdf_dev, "cairo_pdf") || isTRUE(capabilities("cairo"))) {
      if (isTRUE(capabilities("cairo"))) {
        grDevices::cairo_pdf(path, width = width, height = height, family = ff)
      } else {
        ff_dev <- if (identical(ff, "Times New Roman")) "Times" else ff
        grDevices::pdf(
          path, width = width, height = height, family = ff_dev,
          useDingbats = FALSE, compress = TRUE
        )
      }
    } else {
      ff_dev <- if (identical(ff, "Times New Roman")) "Times" else ff
      grDevices::pdf(
        path, width = width, height = height, family = ff_dev,
        useDingbats = FALSE, compress = TRUE
      )
    }
  }

  for (it in q) {
    filename <- it$filename
    # 若 filename 已是绝对路径（Unix / Windows 盘符），直接使用，不再拼接 output_dir
    out_path <- if (
      !is.null(filename) && nzchar(filename) &&
      (startsWith(filename, "/") || grepl("^[A-Za-z]:[/\\\\]", filename))
    ) {
      filename
    } else {
      file.path(ctx$output_dir_figures %||% ctx$output_dir, filename)
    }
    out_path_dir <- dirname(out_path)
    if (nzchar(out_path_dir) && !dir.exists(out_path_dir)) {
      dir.create(out_path_dir, recursive = TRUE, showWarnings = FALSE)
    }
    ext <- tolower(tools::file_ext(filename))

    .patch_plot_font <- function(obj, ff) {
      if (inherits(obj, c("ggplot", "gg"))) {
        return(
          obj + ggplot2::theme(
            text = ggplot2::element_text(family = ff),
            axis.text = ggplot2::element_text(family = ff),
            axis.title = ggplot2::element_text(family = ff),
            plot.title = ggplot2::element_text(family = ff),
            legend.text = ggplot2::element_text(family = ff),
            strip.text = ggplot2::element_text(family = ff)
          )
        )
      }
      obj
    }

    .render_once <- function(ff) {
      if (ext == "pdf") {
        .open_pdf(out_path, it$width, it$height, ff)
      } else {
        grDevices::png(
          out_path, width = it$width * 100, height = it$height * 100, res = 100,
          type = "cairo", family = ff
        )
      }
      opened <- TRUE
      tryCatch({
        old_theme <- ggplot2::theme_get()
        old_par <- graphics::par(no.readonly = TRUE)
        on.exit({
          ggplot2::theme_set(old_theme)
          if (grDevices::dev.cur() <= 1L) {
            try(graphics::par(old_par), silent = TRUE)
          }
        }, add = FALSE)
        ff_par <- if (!isTRUE(capabilities("cairo")) || identical(pdf_dev, "pdf")) {
          if (identical(ff, "Times New Roman")) "Times" else ff
        } else {
          ff
        }
        graphics::par(family = ff_par)
        ggplot2::theme_set(
          ggplot2::theme_get() +
            ggplot2::theme(
              text = ggplot2::element_text(family = ff_par),
              axis.text = ggplot2::element_text(family = ff_par),
              axis.title = ggplot2::element_text(family = ff_par),
              plot.title = ggplot2::element_text(family = ff_par),
              legend.text = ggplot2::element_text(family = ff_par),
              strip.text = ggplot2::element_text(family = ff_par)
            )
        )
        out <- it$plot_fn()
        out <- .patch_plot_font(out, ff_par)
        .print_queued_plot_object(out)
        grDevices::dev.off()
        opened <- FALSE
        invisible(TRUE)
      }, error = function(e) {
        if (isTRUE(opened)) try(grDevices::dev.off(), silent = TRUE)
        stop(e)
      })
    }

    tryCatch({
      .render_once(font_family)
      cli::cli_alert_success("Figure saved: {.file {filename}}")
      mirror_pub_output_to_root(ctx, out_path)

      # PDF 旁路写 SVG（需显式打开 config$project$export_figure_svg=TRUE）
      if (ext == "pdf" && isTRUE(pub_export_figure_svg(ctx))) {
        if (!requireNamespace("svglite", quietly = TRUE)) {
          cli::cli_alert_warning("export_figure_svg=TRUE 但未安装 svglite，跳过 SVG: {basename(out_path)}")
        } else {
          svg_path <- sub("\\.pdf$", ".svg", out_path, ignore.case = TRUE)
          svglite::svglite(svg_path, width = it$width, height = it$height)
          opened_svg <- TRUE
          tryCatch({
            .with_plot_theme(it$plot_fn, font_family)
            grDevices::dev.off()
            opened_svg <- FALSE
          }, error = function(e) {
            if (isTRUE(opened_svg)) try(grDevices::dev.off(), silent = TRUE)
            stop(e)
          })
          cli::cli_alert_success("Figure SVG saved: {.file {basename(svg_path)}}")
        }
      }
    }, error = function(e) {
      try(grDevices::dev.off(), silent = TRUE)
      msg <- conditionMessage(e)
      font_err <- grepl("invalid font|font family|font type|PostScript", msg, ignore.case = TRUE)
      recovered <- FALSE
      if (isTRUE(font_err) && identical(ext, "pdf")) {
        for (fb in c("Liberation Serif", "DejaVu Serif", "serif", "Times", "sans")) {
          if (identical(fb, font_family)) next
          ok <- tryCatch({
            .render_once(fb)
            TRUE
          }, error = function(e2) FALSE)
          if (isTRUE(ok)) {
            cli::cli_alert_warning(
              "Figure saved with font fallback '{fb}' (was '{font_family}'): {.file {filename}}"
            )
            mirror_pub_output_to_root(ctx, out_path)
            recovered <- TRUE
            break
          }
        }
      }
      if (!isTRUE(recovered)) {
        cli::cli_alert_warning("Figure failed ({filename}): {msg}")
      }
    })
  }
  ctx$results$figure_queue <- list()
  ctx
}


# ── 初始化 ctx 上下文对象 ─────────────────────────────────────────────────────
# 输出目录结构: output_dir / Tables（所有 .xlsx）, output_dir / Figures（所有 .pdf/.png）
init_ctx <- function(config) {
  if (exists("pipeline_normalize_project_outcome_labels", mode = "function")) {
    config <- pipeline_normalize_project_outcome_labels(config)
  }
  output_dir <- config$project$output_dir %||% "Output"
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
    cli::cli_alert_info("Created output directory: {.file {output_dir}}")
  }
  output_dir_tables  <- file.path(output_dir, "Tables")
  output_dir_figures <- file.path(output_dir, "Figures")
  if (!dir.exists(output_dir_tables))  dir.create(output_dir_tables,  recursive = TRUE)
  if (!dir.exists(output_dir_figures)) dir.create(output_dir_figures, recursive = TRUE)
  pub_reset_counters()
  list(
    config              = config,
    data                = list(),
    results             = list(),
    log                 = list(
      block_output_dirs   = list(),
      block_step_counter  = 0L,
      pub_counters        = .pub_counters_snapshot()
    ),
    root_output_dir     = output_dir,
    current_block       = NULL,
    output_dir          = output_dir,
    output_dir_tables   = output_dir_tables,
    output_dir_figures  = output_dir_figures
  )
}


# ── Block 注册表 ──────────────────────────────────────────────────────────────
.block_registry <- new.env(parent = emptyenv())

register_block <- function(name, fn, description = "") {
  .block_registry[[name]] <- list(fn = fn, description = description)
}

run_block <- function(ctx, block_name, ...) {
  if (!exists(block_name, envir = .block_registry)) {
    stop("Block not found: '", block_name, "'. Did you source the block file?")
  }
  root_output_dir <- ctx$root_output_dir %||% ctx$output_dir %||% "Output"
  prj <- ctx$config$project %||% list()
  use_step_prefix <- prj$use_step_prefixed_block_dirs %||% TRUE
  steps_prefix <- prj$block_steps_prefix %||% "step"
  dir_leaf <- if (isTRUE(use_step_prefix)) {
    ctx$log$block_step_counter <- as.integer(ctx$log$block_step_counter %||% 0L) + 1L
    sprintf("%s%02d_%s", steps_prefix, ctx$log$block_step_counter, block_name)
  } else {
    block_name
  }
  block_output_dir <- file.path(root_output_dir, dir_leaf)
  block_tables_dir <- file.path(block_output_dir, "Tables")
  block_figures_dir <- file.path(block_output_dir, "Figures")
  block_data_dir <- file.path(block_output_dir, "Data")
  if (!dir.exists(block_output_dir)) dir.create(block_output_dir, recursive = TRUE)
  if (!dir.exists(block_tables_dir)) dir.create(block_tables_dir, recursive = TRUE)
  if (!dir.exists(block_figures_dir)) dir.create(block_figures_dir, recursive = TRUE)
  if (!dir.exists(block_data_dir)) dir.create(block_data_dir, recursive = TRUE)
  
  ctx$current_block <- block_name
  ctx$output_dir <- block_output_dir
  ctx$output_dir_tables <- block_tables_dir
  ctx$output_dir_figures <- block_figures_dir
  ctx$log$block_output_dirs[[block_name]] <- block_output_dir
  
  proj_cfg <- ctx$config$project %||% list()
  db_name_for_naming <- proj_cfg$database %||% proj_cfg$database_type %||% "UnknownDB"
  options(pipeline.database_name = db_name_for_naming)
  entry <- .block_registry[[block_name]]
  cli::cli_rule(left = paste0("Block: ", block_name))
  cli::cli_alert_info("Block output directory: {.file {block_output_dir}}")
  t0 <- proc.time()
  ctx <- entry$fn(ctx, ...)
  ctx <- flush_pub_output_queues(ctx)
  ctx <- mirror_block_pub_outputs(ctx)
  elapsed <- round((proc.time() - t0)[["elapsed"]], 1)
  cli::cli_alert_success("Block '{block_name}' done in {elapsed}s")
  cli::cli_rule()
  ctx
}


# ── run_prediction / run_logistic_only：多指标协变量交集 ─────────────────────
# 依赖本文件已 source 且 block_logistic 已 register_block("logistic", …)。

prediction_intersect_probed_covariates <- function(by_index_named_list) {
  ok <- by_index_named_list[!vapply(by_index_named_list, is.null, logical(1))]
  if (!length(ok)) {
    return(list(m1 = character(0), m2 = character(0), n_ok = 0L))
  }
  m1s <- lapply(ok, function(z) as.character(z$m1 %||% character(0)))
  m2s <- lapply(ok, function(z) as.character(z$m2 %||% character(0)))
  list(
    m1 = if (length(m1s) >= 1L) Reduce(intersect, m1s) else character(0),
    m2 = if (length(m2s) >= 1L) Reduce(intersect, m2s) else character(0),
    n_ok = length(ok)
  )
}

prediction_build_logistic_cov_unify_patch <- function(m1, m2) {
  list(
    use_fixed_covariate_sets = TRUE,
    fixed_model1_covariates = as.character(m1 %||% character(0)),
    fixed_model2_covariates = as.character(m2 %||% character(0))
  )
}

# 交集为空时不应启用固定集，否则 Table 4 脚注全为 None 且模型等同 Crude。
prediction_cov_unify_patch_if_nonempty <- function(m1, m2) {
  m1 <- as.character(m1 %||% character(0))
  m2 <- as.character(m2 %||% character(0))
  if (!length(m1) && !length(m2)) return(NULL)
  prediction_build_logistic_cov_unify_patch(m1, m2)
}

# 各指标探测结果的并集（Model2-only 会与 Model1 去重），用于交集为空时的回退。
prediction_union_probed_covariates <- function(by_index_named_list) {
  ok <- by_index_named_list[!vapply(by_index_named_list, is.null, logical(1))]
  if (!length(ok)) {
    return(list(m1 = character(0), m2 = character(0), n_ok = 0L))
  }
  m1s <- lapply(ok, function(z) as.character(z$m1 %||% character(0)))
  m2s <- lapply(ok, function(z) as.character(z$m2 %||% character(0)))
  fuse <- function(lst) {
    if (!length(lst)) return(character(0))
    if (length(lst) == 1L) return(lst[[1L]])
    Reduce(union, lst)
  }
  m1u <- fuse(m1s)
  m2u <- setdiff(fuse(m2s), m1u)
  list(m1 = m1u, m2 = m2u, n_ok = length(ok))
}

# 取消固定协变量（避免检查点或上次运行残留 use_fixed 导致全表 None）。
prediction_logistic_strip_fixed_covariates <- function(logistic_cfg) {
  utils::modifyList(
    as.list(logistic_cfg %||% list()),
    list(
      use_fixed_covariate_sets = FALSE,
      fixed_model1_covariates = character(0),
      fixed_model2_covariates = character(0)
    )
  )
}

prediction_probe_logistic_covariates_per_index <- function(
  ctx_template,
  ix_all,
  unified_log_patch,
  output_base,
  probe_tag = "_probe_logistic_cov"
) {
  ix_all <- as.character(ix_all)
  ix_all <- ix_all[nzchar(ix_all)]
  if (!length(ix_all)) {
    return(list(by_index = stats::setNames(list(), character(0)), failed = character(0)))
  }
  ob <- normalizePath(as.character(output_base)[1L], winslash = "/", mustWork = FALSE)
  out <- vector("list", length(ix_all))
  names(out) <- ix_all
  failed <- character(0)
  for (ix in ix_all) {
    cx <- unserialize(serialize(ctx_template, connection = NULL, xdr = FALSE))
    la <- as.list(cx$config$logistic %||% list())
    la$use_fixed_covariate_sets <- FALSE
    la$fixed_model1_covariates <- character(0)
    la$fixed_model2_covariates <- character(0)
    cx$config$logistic <- la
    if (!is.null(unified_log_patch)) {
      cx$config$logistic <- utils::modifyList(as.list(cx$config$logistic %||% list()), unified_log_patch)
      cx$config$logistic$use_fixed_covariate_sets <- FALSE
      cx$config$logistic$fixed_model1_covariates <- character(0)
      cx$config$logistic$fixed_model2_covariates <- character(0)
    }
    cx$config$logistic$index_var <- ix
    if (!is.null(cx$config$incidence)) cx$config$incidence$index_var <- ix
    if (!is.null(cx$config$survival)) cx$config$survival$index_var <- ix
    if (!is.null(cx$config$quartile)) cx$config$quartile$index_var <- ix
    if (!is.null(cx$config$rcs)) cx$config$rcs$vars <- c(ix)

    pr <- file.path("prediction_by_index", probe_tag, ix)
    new_root <- normalizePath(file.path(ob, pr), winslash = "/", mustWork = FALSE)
    if (!dir.exists(new_root)) dir.create(new_root, recursive = TRUE)
    cx$root_output_dir <- new_root
    cx$output_dir <- new_root
    cx$output_dir_tables <- file.path(new_root, "Tables")
    cx$output_dir_figures <- file.path(new_root, "Figures")
    if (!dir.exists(cx$output_dir_tables)) dir.create(cx$output_dir_tables, recursive = TRUE)
    if (!dir.exists(cx$output_dir_figures)) dir.create(cx$output_dir_figures, recursive = TRUE)
    cx$config$project$output_dir <- new_root
    cx$log$block_step_counter <- 0L

    cx <- tryCatch(
      run_block(cx, "logistic"),
      error = function(e) {
        failed <<- c(failed, ix)
        cli::cli_alert_warning("协变量探测 Logistic 失败 [{ix}]: {conditionMessage(e)}")
        NULL
      }
    )
    if (!is.null(cx)) {
      out[[ix]] <- list(
        m1 = as.character(cx$results$logistic_model1_covariates %||% character(0)),
        m2 = as.character(cx$results$logistic_model2_covariates %||% character(0))
      )
    } else {
      out[[ix]] <- NULL
    }
  }
  list(by_index = out, failed = failed)
}

prediction_cleanup_cov_probe_dirs <- function(output_base, probe_tag = "_probe_logistic_cov") {
  ob <- normalizePath(as.character(output_base)[1L], winslash = "/", mustWork = FALSE)
  p <- normalizePath(file.path(ob, "prediction_by_index", probe_tag), winslash = "/", mustWork = FALSE)
  if (nzchar(p) && dir.exists(p)) {
    unlink(p, recursive = TRUE)
    cli::cli_alert_info("已删除协变量探测临时目录: {.file {p}}")
  }
}


# ── 全局数据展示规范（位数见 .pipeline_pub_digits / config$pub_digits）──────────
#   描述统计: 最多 desc 位（默认 3），默认去尾随 0（90 不写 90.000）
#   效应量(OR/HR/RR+CI): 固定 est 位（用 pub_format_est，不去尾随 0）
#   P: 固定 p 位；切点: cutoff 位

#' 去掉小数尾随 0；整数不保留小数点（仅用于描述统计 fmt_num）
.fmt_num_trim_trailing <- function(s) {
  s <- as.character(s)
  ok <- !is.na(s) & nzchar(s) & grepl("\\.", s, fixed = FALSE)
  if (!any(ok)) return(s)
  s[ok] <- sub("(\\.[0-9]*?)0+$", "\\1", s[ok])
  s[ok] <- sub("\\.$", "", s[ok])
  s
}

fmt_num <- function(x, digits = NULL, trim = NULL) {
  if (length(x) == 0L) return(NA_character_)
  dig <- as.integer(digits %||% .pipeline_pub_digits()$desc)[1L]
  if (!is.finite(dig) || dig < 0L) dig <- 2L
  do_trim <- isTRUE(trim %||% .pipeline_pub_digits()$desc_trim)
  s <- formatC(round(as.numeric(x), dig), format = "f", digits = dig)
  if (do_trim) s <- .fmt_num_trim_trailing(s)
  s
}

# 分位/切点标签：小量级指标（如 WPR≈0.03）自动加位数，避免「0.03 -< 0.03」
fmt_num_cutoff <- function(x, digits = NULL) {
  if (length(x) == 0L) return(NA_character_)
  x1 <- suppressWarnings(as.numeric(x)[1L])
  if (!is.finite(x1)) return(NA_character_)
  if (is.null(digits)) {
    ax <- abs(x1)
    digits <- if (ax >= 1) 2L else if (ax >= 0.1) 3L else .pipeline_pub_digits()$cutoff
  }
  formatC(round(x1, as.integer(digits)[1L]), format = "f", digits = as.integer(digits)[1L])
}

fmt_pval <- function(p, digits = NULL) {
  dig <- as.integer(digits %||% .pipeline_pub_digits()$p)[1L]
  if (!is.finite(dig) || dig < 0L) dig <- 3L
  ifelse(is.na(p), NA_character_,
         ifelse(p < 0.001, "<0.001", formatC(round(p, dig), format = "f", digits = dig)))
}

# 单因素 / 附表：OR|HR (lo-hi, p=…)；效应量走 est 位数，描述统计仍用 fmt_num
# 完全分离 / Inf CI / 爆炸效应量与亚组森林一致，写成 NE，避免 1e22 或 0.000-Inf
pub_est_ci_not_estimable <- function(est, lo = NA_real_, hi = NA_real_,
                                     ne_est_gt = 500, ne_hi_gt = 1000) {
  e <- suppressWarnings(as.numeric(est)[1L])
  l <- suppressWarnings(as.numeric(lo)[1L])
  h <- suppressWarnings(as.numeric(hi)[1L])
  if (!is.finite(e) || e <= 0) return(TRUE)
  if (e > ne_est_gt) return(TRUE)
  if (!is.na(h) && (!is.finite(h) || h > ne_hi_gt)) return(TRUE)
  if (!is.na(l) && !is.finite(l)) return(TRUE)
  FALSE
}

pub_fmt_est_ci_p <- function(est, lo, hi, p) {
  if (length(est) != 1L || is.na(est)) return("")
  .fmt_p_inline <- function(p) {
    if (length(p) != 1L || is.na(p)) return("")
    if (p < 0.001) return("p<0.001")
    paste0("p=", fmt_pval(p))
  }
  pt <- .fmt_p_inline(p)
  if (isTRUE(pub_est_ci_not_estimable(est, lo, hi))) {
    if (!nzchar(pt)) return("NE")
    return(paste0("NE (", pt, ")"))
  }
  if (is.na(lo) || is.na(hi)) {
    if (!nzchar(pt)) return(pub_format_est(est))
    return(paste0(pub_format_est(est), " (", pt, ")"))
  }
  if (!nzchar(pt)) {
    return(paste0(pub_format_est(est), " (", pub_format_est(lo), "-", pub_format_est(hi), ")"))
  }
  paste0(pub_format_est(est), " (", pub_format_est(lo), "-", pub_format_est(hi), ", ", pt, ")")
}

# ── RCS 曲线切点（OR=1 / slope=0），与 02block_rcs_incidence.R 逻辑一致 ─────────
rcs_format_cutoff <- function(x, digits = NULL) {
  dig <- as.integer(digits %||% .pipeline_pub_digits()$cutoff)[1L]
  if (!is.finite(dig) || dig < 0L) dig <- 4L
  formatC(as.numeric(x), digits = dig, format = "f")
}

rcs_find_roots_on_grid <- function(x, y, target = 0, tol = 1e-5) {
  if (length(x) < 2L) return(numeric(0))
  x <- as.numeric(x)
  y <- as.numeric(y)
  ok <- is.finite(x) & is.finite(y)
  x <- x[ok]
  y <- y[ok]
  if (length(x) < 2L) return(numeric(0))
  o <- order(x)
  x <- x[o]
  y <- y[o]
  f <- stats::approxfun(x, y, rule = 2)
  roots <- numeric(0)
  y_adj <- y - target
  for (i in seq_len(length(x) - 1L)) {
    if (abs(y_adj[i]) < tol) roots <- c(roots, x[i])
    if (y_adj[i] * y_adj[i + 1L] < 0) {
      r <- tryCatch(
        stats::uniroot(function(xi) f(xi) - target, c(x[i], x[i + 1L]))$root,
        error = function(e) NA_real_
      )
      if (is.finite(r)) roots <- c(roots, r)
    }
  }
  roots <- sort(unique(round(roots, 6)))
  if (length(roots) <= 1L) return(roots)
  tol_x <- max(diff(range(x)) * 1e-4, 1e-6)
  kept <- roots[1L]
  for (r in roots[-1L]) {
    if (r - tail(kept, 1L) > tol_x) kept <- c(kept, r)
  }
  kept
}

rcs_find_slope_zero <- function(x, log_or, tol = 1e-4) {
  if (length(x) < 3L) return(numeric(0))
  x <- as.numeric(x)
  log_or <- as.numeric(log_or)
  ok <- is.finite(x) & is.finite(log_or)
  x <- x[ok]
  log_or <- log_or[ok]
  if (length(x) < 3L) return(numeric(0))
  o <- order(x)
  x <- x[o]
  log_or <- log_or[o]
  f <- stats::approxfun(x, log_or, rule = 2)
  span <- diff(range(x))
  eps <- max(span * 1e-6, 1e-6)
  deriv <- function(xi) (f(xi + eps) - f(xi - eps)) / (2 * eps)
  x_fine <- seq(min(x), max(x), length.out = max(500L, length(x) * 10L))
  d <- vapply(x_fine, deriv, numeric(1))
  roots <- numeric(0)
  for (i in seq_len(length(x_fine) - 1L)) {
    if (!is.finite(d[i]) || !is.finite(d[i + 1L])) next
    if (abs(d[i]) < tol) {
      roots <- c(roots, x_fine[i])
    } else if (d[i] * d[i + 1L] < 0) {
      r <- tryCatch(
        stats::uniroot(deriv, c(x_fine[i], x_fine[i + 1L]))$root,
        error = function(e) NA_real_
      )
      if (is.finite(r)) roots <- c(roots, r)
    }
  }
  roots <- sort(unique(round(roots, 6)))
  if (length(roots) <= 1L) return(roots)
  tol_x <- max(span * 1e-4, 1e-6)
  kept <- roots[1L]
  for (r in roots[-1L]) {
    if (r - tail(kept, 1L) > tol_x) kept <- c(kept, r)
  }
  kept
}

rcs_find_cutoffs_from_or_curve <- function(x, or) {
  x <- as.numeric(x)
  or <- as.numeric(or)
  ok <- is.finite(x) & is.finite(or) & or > 0
  x <- x[ok]
  or <- or[ok]
  if (length(x) < 2L) {
    return(list(or1 = numeric(0), slope_zero = numeric(0), peak = numeric(0), all = numeric(0)))
  }
  log_or <- log(or)
  or1 <- rcs_find_roots_on_grid(x, log_or, target = 0)
  slope_zero_raw <- rcs_find_slope_zero(x, log_or)
  rcs_refined_cutoffs(x, log_or, or1, slope_zero_raw)
}

rcs_slope_zero_peak <- function(x, log_or, slope_zero) {
  slope_zero <- unique(as.numeric(slope_zero[is.finite(slope_zero)]))
  if (!length(slope_zero) || length(x) < 2L) return(NA_real_)
  f <- stats::approxfun(as.numeric(x), as.numeric(log_or), rule = 2)
  hr_at <- exp(f(slope_zero))
  slope_zero[which.max(hr_at)]
}

rcs_is_between_or1_roots <- function(x, or1) {
  or1 <- sort(unique(as.numeric(or1[is.finite(or1)])))
  if (length(or1) < 2L || !is.finite(x)) return(FALSE)
  any(vapply(
    seq_len(length(or1) - 1L),
    function(i) x > or1[i] && x < or1[i + 1L],
    logical(1L)
  ))
}

rcs_refined_cutoffs <- function(x, log_or, or1, slope_zero) {
  or1 <- sort(unique(as.numeric(or1[is.finite(or1)])))
  peak_x <- rcs_slope_zero_peak(x, log_or, slope_zero)

  kept_peak <- NA_real_
  if (length(or1) == 1L) {
    all_cutoffs <- or1
  } else if (length(or1) >= 2L) {
    if (is.finite(peak_x) && rcs_is_between_or1_roots(peak_x, or1)) {
      kept_peak <- peak_x
    }
    all_cutoffs <- sort(unique(c(or1, kept_peak[is.finite(kept_peak)])))
  } else {
    kept_peak <- if (is.finite(peak_x)) {
      peak_x
    } else if (length(x) >= 1L) {
      as.numeric(x)[which.max(as.numeric(log_or))]
    } else {
      NA_real_
    }
    all_cutoffs <- sort(unique(as.numeric(kept_peak[is.finite(kept_peak)])))
  }

  kept_peak_vec <- as.numeric(kept_peak[is.finite(kept_peak)])
  list(or1 = or1, slope_zero = kept_peak_vec, peak = kept_peak_vec, all = all_cutoffs)
}

rcs_find_cutoffs_from_lnhr_curve <- function(x, lnhr) {
  x <- as.numeric(x)
  lnhr <- as.numeric(lnhr)
  ok <- is.finite(x) & is.finite(lnhr)
  x <- x[ok]
  lnhr <- lnhr[ok]
  if (length(x) < 2L) {
    return(list(or1 = numeric(0), slope_zero = numeric(0), peak = numeric(0), all = numeric(0)))
  }
  or1 <- rcs_find_roots_on_grid(x, lnhr, target = 0)
  slope_zero_raw <- rcs_find_slope_zero(x, lnhr)
  rcs_refined_cutoffs(x, lnhr, or1, slope_zero_raw)
}

rcs_primary_cutoff <- function(cutoffs) {
  if (is.list(cutoffs)) {
    if (length(cutoffs$or1) == 1L) return(cutoffs$or1[1L])
    if (length(cutoffs$peak)) return(cutoffs$peak[1L])
    if (length(cutoffs$or1)) return(cutoffs$or1[1L])
    if (length(cutoffs$all)) return(cutoffs$all[1L])
  }
  NA_real_
}

# Table S-XX / logistic_*_rcs：默认只用 primary cutoff 二分（< cut vs >= cut）
rcs_table_group_cutoffs <- function(cutoffs, primary = NULL, mode = c("primary", "all")) {
  mode <- tolower(as.character(mode)[1L])
  if (!mode %in% c("primary", "all")) mode <- "primary"
  all_cuts <- if (is.list(cutoffs)) {
    as.numeric(cutoffs$all %||% numeric(0))
  } else {
    as.numeric(cutoffs %||% numeric(0))
  }
  all_cuts <- sort(unique(all_cuts[is.finite(all_cuts)]))
  if (identical(mode, "all")) return(all_cuts)
  pc <- suppressWarnings(as.numeric(primary)[1L])
  if (!is.finite(pc)) {
    pc <- if (is.list(cutoffs)) rcs_primary_cutoff(cutoffs) else NA_real_
  }
  if (is.finite(pc)) return(pc)
  all_cuts
}

rcs_primary_from_ctx <- function(ctx) {
  .as_num1 <- function(x) {
    if (is.null(x)) return(NA_real_)
    # save_result("rcs_cutoff", cutoff_detail) 曾把 data.frame 盖掉标量；兼容旧检查点
    if (is.data.frame(x)) {
      if ("cutoff" %in% names(x)) {
        if ("type" %in% names(x) && any(x$type == "peak_or", na.rm = TRUE)) {
          return(suppressWarnings(as.numeric(x$cutoff[x$type == "peak_or"][1L])))
        }
        return(suppressWarnings(as.numeric(x$cutoff[1L])))
      }
      return(NA_real_)
    }
    if (is.list(x) && !is.atomic(x)) {
      return(suppressWarnings(as.numeric(unlist(x, use.names = FALSE)[1L])))
    }
    suppressWarnings(as.numeric(x)[1L])
  }
  pc <- .as_num1(ctx$results$rcs_cutoff)
  if (!is.finite(pc)) pc <- .as_num1(ctx$results$rcs_group_cutoffs_used)
  if (!is.finite(pc)) pc <- .as_num1(ctx$results$cutoff_value)
  if (!is.finite(pc)) pc <- .as_num1(ctx$results$nhanes_rcs_primary_cutoff)
  pc
}

rcs_table_exposure_cutoff_labels <- function(raw_levels, primary_cutoff) {
  cutoffs <- stats::setNames(rep("", length(raw_levels)), raw_levels)
  pc <- suppressWarnings(as.numeric(primary_cutoff)[1L])
  if (!is.finite(pc) || length(raw_levels) < 2L) return(cutoffs)
  cutoffs[[raw_levels[[1L]]]] <- paste0("< ", fmt_num_cutoff(pc))
  cutoffs[[raw_levels[[length(raw_levels)]]]] <- paste0("\u2265 ", fmt_num_cutoff(pc))
  cutoffs
}

logistic_rcs_prepare_cutoffs <- function(raw_levels, ctx) {
  out <- rcs_table_exposure_cutoff_labels(raw_levels, rcs_primary_from_ctx(ctx))
  attr(out, "is_rcs_group") <- TRUE
  out
}

logistic_glm_format_p <- function(p, is_rcs_group = FALSE) {
  # 与 pub_format_p_cell / fmt_pval 同口径（默认 3 位）；禁止再写 round(p, 4)
  if (exists("pub_format_p_cell", mode = "function")) pub_format_p_cell(p) else fmt_pval(p)
}

rcs_ggrcs_strip_histogram_layers <- function(plot_obj) {
  if (is.null(plot_obj$layers) || !length(plot_obj$layers)) return(plot_obj)
  is_hist <- vapply(plot_obj$layers, function(ly) {
    grepl("GeomBar|GeomHistogram", class(ly$geom)[1])
  }, logical(1))
  if (any(is_hist)) plot_obj$layers <- plot_obj$layers[!is_hist]
  plot_obj
}

rcs_ggrcs_y_limits <- function(plot_obj, ann_frac = 0.18, x_range = NULL) {
  bd <- ggplot2::ggplot_build(plot_obj)
  ymaxs <- numeric(0)
  ymins <- numeric(0)
  xr <- if (!is.null(x_range) && length(x_range) >= 2L &&
            all(is.finite(as.numeric(x_range[1:2])))) {
    as.numeric(x_range[1:2])
  } else {
    NULL
  }
  for (i in seq_along(bd$data)) {
    ly <- bd$data[[i]]
    if ("count" %in% names(ly) && "xmin" %in% names(ly)) next
    if (!is.null(xr) && "x" %in% names(ly)) {
      in_x <- is.finite(ly$x) & ly$x >= xr[1] & ly$x <= xr[2]
      ly <- ly[in_x, , drop = FALSE]
      if (!nrow(ly)) next
    }
    if ("y" %in% names(ly)) {
      ymaxs <- c(ymaxs, ly$y)
      ymins <- c(ymins, ly$y)
    }
    if ("ymax" %in% names(ly)) ymaxs <- c(ymaxs, ly$ymax)
    if ("ymin" %in% names(ly)) ymins <- c(ymins, ly$ymin)
  }
  ymax_data <- max(ymaxs, na.rm = TRUE)
  if (!is.finite(ymax_data) || ymax_data <= 0) ymax_data <- 1
  ymin <- min(ymins, na.rm = TRUE)
  if (!is.finite(ymin) || ymin > 0) ymin <- 0
  y_span <- max(ymax_data - ymin, ymax_data * 0.05, 1e-6)
  ymax_plot <- ymax_data + y_span * ann_frac
  y_step <- y_span * ann_frac / 2.5
  list(ymin = ymin, ymax_data = ymax_data, ymax_plot = ymax_plot, y_step = y_step)
}

rcs_ggrcs_add_cutoff_vlines <- function(plot_obj, cutoffs, y_lim, plot_ff, label_digits = 2L,
                                        x_range = NULL, fit = NULL, Index = NULL) {
  xs <- sort(unique(as.numeric(cutoffs$all[is.finite(cutoffs$all)])))
  if (!length(xs)) return(plot_obj)

  plot_obj <- plot_obj + ggplot2::geom_vline(
    xintercept = xs,
    linetype   = "dashed",
    linewidth  = 0.45,
    color      = "gray35"
  )

  if (is.null(x_range)) x_range <- xs
  x_rng <- range(x_range, na.rm = TRUE)
  x_span <- diff(x_rng)
  if (!is.finite(x_span) || x_span <= 0) x_span <- max(abs(xs), 1)
  x_off <- x_span * 0.015

  ys <- rep(y_lim$ymax_data * 0.88, length(xs))
  if (!is.null(fit) && !is.null(Index) && nzchar(as.character(Index)[1L])) {
    pred <- tryCatch(
      do.call(rms::Predict, list(fit, as.name(Index), ref.zero = TRUE)),
      error = function(e) NULL
    )
    if (!is.null(pred)) {
      px <- as.numeric(pred[[Index]])
      por <- exp(as.numeric(pred$yhat))
      ok <- is.finite(px) & is.finite(por)
      if (sum(ok) >= 2L) {
        f_or <- stats::approxfun(px[ok], por[ok], rule = 2)
        ys <- pmax(f_or(xs), y_lim$ymin + 0.02 * diff(c(y_lim$ymin, y_lim$ymax_data)))
      }
    }
  }

  y_drop <- max(y_lim$y_step * 0.45, y_lim$ymax_data * 0.03, 0.04)
  for (i in seq_along(xs)) {
    plot_obj <- plot_obj + ggplot2::annotate(
      "text",
      x      = xs[i] + x_off,
      y      = ys[i] - (i - 1L) %% 3L * y_drop,
      label  = rcs_format_cutoff(xs[i], digits = label_digits),
      angle  = 0,
      hjust  = 0,
      vjust  = 0.5,
      size   = 3.2,
      family = plot_ff,
      color  = "gray20"
    )
  }
  plot_obj
}

rcs_cutoff_factor <- function(x, cutoffs, index_name = "Index") {
  col_name <- paste0(index_name, "_RCS_Group")
  x_num <- suppressWarnings(as.numeric(x))
  cutoffs <- sort(unique(as.numeric(cutoffs[is.finite(cutoffs)])))
  if (!length(cutoffs)) {
    lbl <- "All (no cutoff)"
    return(list(
      factor = factor(rep(lbl, length(x_num)), levels = lbl),
      col_name = col_name,
      labels = lbl,
      n_groups = 1L,
      cutoffs = numeric(0)
    ))
  }
  breaks <- c(-Inf, cutoffs, Inf)
  n_grp <- length(breaks) - 1L
  labels <- character(n_grp)
  # Convention A: x < cut → lower group; x >= cut → higher group (equals → high)
  for (i in seq_len(n_grp)) {
    if (i == 1L) {
      labels[i] <- paste0("<", rcs_format_cutoff(cutoffs[1L]))
    } else if (i == n_grp) {
      labels[i] <- paste0(">=", rcs_format_cutoff(cutoffs[length(cutoffs)]))
    } else {
      labels[i] <- paste0(
        ">=", rcs_format_cutoff(cutoffs[i - 1L]),
        " & <", rcs_format_cutoff(cutoffs[i])
      )
    }
  }
  cutoffs_named <- stats::setNames(labels, labels)
  f <- cut(
    x_num,
    breaks = breaks,
    labels = labels,
    include.lowest = TRUE,
    right = FALSE
  )
  list(
    factor = f,
    col_name = col_name,
    labels = labels,
    n_groups = n_grp,
    cutoffs = cutoffs,
    cutoffs_named = cutoffs_named
  )
}

# Logistic Table 2（12 列 OR/CI/P）：rbind 后矩阵列名可能被暴露变量名污染，按列位替换 rounded 0
format_logistic_table2_pvalues <- function(x, p_cols = NULL) {
  df <- if (is.data.frame(x)) x else data.frame(x, stringsAsFactors = FALSE)
  if (is.null(p_cols)) {
    p_cols <- if (exists("pipeline_table_p_cols", mode = "function")) {
      pipeline_table_p_cols(ncol(df), binary_layout = FALSE)
    } else {
      cols <- c(6L, 9L, 12L)
      if (ncol(df) >= 15L) cols <- c(cols, 15L)
      cols
    }
  }
  for (j in p_cols) {
    if (ncol(df) >= j) {
      v <- df[[j]]
      hit <- !is.na(v) & (v == "0" | v == 0)
      if (any(hit)) df[[j]][hit] <- "P < 0.001"
    }
  }
  df
}

# 连续变量描述：正态 → "Mean ± SD"，非正态 → "Median (Q1, Q3)"
fmt_continuous <- function(x, is_normal = TRUE) {
  x <- x[!is.na(x)]
  if (length(x) == 0) return(NA_character_)
  if (is_normal) {
    paste0(fmt_num(mean(x)), " \u00b1 ", fmt_num(sd(x)))
  } else {
    q <- quantile(x, probs = c(0.25, 0.5, 0.75))
    paste0(fmt_num(q[2]), " (", fmt_num(q[1]), ", ", fmt_num(q[3]), ")")
  }
}

# 分类变量描述："n (xx.xx%)"（计数走 pub_format_int 千分位统一口径）
fmt_categorical <- function(x) {
  n   <- sum(!is.na(x))
  tbl <- table(x)
  paste0(names(tbl), ": ", pub_format_int(as.integer(tbl)), " (", fmt_num(tbl / n * 100), "%)", collapse = "; ")
}

# 连续变量正态性（与 baseline_nhanes / baseline_binary 一致）
test_variable_normality <- function(x) {
  x <- x[!is.na(x)]
  n <- length(x)
  if (n < 3) return(FALSE)
  pv <- tryCatch({
    if (n > 5000) {
      stats::ks.test(scale(x), "pnorm")$p.value
    } else {
      stats::shapiro.test(x)$p.value
    }
  }, error = function(e) 0)
  pv >= 0.05
}

resolve_normality_vars <- function(data, continuous_vars = NULL) {
  if (is.null(continuous_vars)) {
    continuous_vars <- names(Filter(is.numeric, data))
  }
  continuous_vars <- as.character(continuous_vars)
  continuous_vars <- continuous_vars[continuous_vars %in% names(data)]
  if (!length(continuous_vars)) {
    return(list(normal = character(0), skewed = character(0)))
  }
  is_norm <- vapply(
    continuous_vars,
    function(v) test_variable_normality(data[[v]]),
    logical(1)
  )
  list(normal = continuous_vars[is_norm], skewed = continuous_vars[!is_norm])
}

is_var_normal_for_table <- function(var, normal_vars, skewed_vars) {
  if (length(normal_vars) && var %in% normal_vars) return(TRUE)
  if (length(skewed_vars) && var %in% skewed_vars) return(FALSE)
  TRUE
}

continuous_statistic_label <- function(is_normal = TRUE) {
  if (isTRUE(is_normal)) "Mean \u00b1 SD" else "Median (Q1, Q3)"
}

# 从 survey::svyquantile 结果提取分位数值（兼容 newsvyquantile 与旧格式）
svy_extract_quantiles <- function(qq, var = NULL) {
  if (is.null(qq)) return(numeric(0))
  if (!is.null(var) && nzchar(var) && var %in% names(qq)) {
    mat <- qq[[var]]
    if (is.matrix(mat) && "quantile" %in% colnames(mat)) {
      return(as.numeric(mat[, "quantile", drop = TRUE]))
    }
    return(as.numeric(mat))
  }
  if (!is.null(qq$quantiles)) return(as.numeric(qq$quantiles))
  as.numeric(unlist(qq, use.names = FALSE))
}

# NHANES 加权连续变量描述（对齐 baseline_nhanes tbl_svysummary）
fmt_continuous_svy <- function(design, var, is_normal = TRUE) {
  if (!requireNamespace("survey", quietly = TRUE)) {
    return(fmt_continuous(design$variables[[var]], is_normal))
  }
  form <- stats::as.formula(paste0("~", var))
  if (isTRUE(is_normal)) {
    mu <- as.numeric(survey::svymean(form, design, na.rm = TRUE))
    vr <- as.numeric(survey::svyvar(form, design, na.rm = TRUE))
    sd_w <- sqrt(max(vr, 0))
    paste0(fmt_num(mu), " \u00b1 ", fmt_num(sd_w))
  } else {
    qq <- survey::svyquantile(
      form, design, quantiles = c(0.25, 0.5, 0.75), na.rm = TRUE
    )
    qv <- svy_extract_quantiles(qq, var)
    if (length(qv) >= 3L && all(is.finite(qv))) {
      paste0(fmt_num(qv[2]), " (", fmt_num(qv[1]), ", ", fmt_num(qv[3]), ")")
    } else {
      fmt_continuous(design$variables[[var]], FALSE)
    }
  }
}

# NHANES 加权分类水平描述：n_unweighted (weighted %)，对齐 baseline_nhanes
fmt_categorical_level_svy <- function(design, var, level) {
  if (!requireNamespace("survey", quietly = TRUE)) {
    x <- design$variables[[var]]
    n <- sum(as.character(x) == as.character(level), na.rm = TRUE)
    n_tot <- sum(!is.na(x))
    pct <- if (n_tot > 0) n / n_tot * 100 else 0
    return(paste0(pub_format_int(n), " (", fmt_num(pct), "%)"))
  }
  x <- design$variables[[var]]
  level <- as.character(level)
  n_unw <- sum(as.character(x) == level, na.rm = TRUE)
  design2 <- stats::update(
    design,
    `.cat_hit` = as.integer(as.character(design$variables[[var]]) == level)
  )
  pct <- as.numeric(survey::svymean(~`.cat_hit`, design2, na.rm = TRUE)) * 100
  paste0(pub_format_int(n_unw), " (", fmt_num(pct), "%)")
}

# ── 协变量子集枚举：按子集大小递增，供 Logistic/Cox 自动组合搜索 ─────────────
#   vars 去重后；长度 <= max_exhaustive 时枚举全部非空子集 + 空集（空集在首位）；
#   更长时仅枚举空集、所有 1～3 元子集及全集，避免组合爆炸。
covariate_subsets_increasing_order <- function(vars, max_exhaustive = 10L) {
  vars <- unique(as.character(vars))
  vars <- vars[nzchar(vars)]
  out <- list(character(0))
  if (length(vars) == 0L) return(out)
  if (length(vars) <= max_exhaustive) {
    for (sz in seq_len(length(vars))) {
      out <- c(out, combn(vars, sz, simplify = FALSE))
    }
    return(out)
  }
  n <- length(vars)
  for (sz in seq_len(min(3L, n))) {
    out <- c(out, combn(vars, sz, simplify = FALSE))
  }
  if (n > 3L) out <- c(out, list(vars))
  out
}

# ── 协变量子集枚举：先全集再规模递减（n, n-1, …, 1），供 Logistic「先全加再减」──
#   n <= max_exhaustive：枚举所有非空子集，顺序为从大到小（首个命中 = 变量最多的显著模型）。
#   n > max_exhaustive：先试全集，再试 n-1、n-2… 共最多 max_drop_layers 层；单层组合数 >
#   max_choose_per_layer 时跳过该层（避免组合爆炸），后续由 block_logistic 的递增阶段补搜。
covariate_subsets_decreasing_from_full <- function(
    vars,
    max_exhaustive = 12L,
    max_drop_layers = 6L,
    max_choose_per_layer = 400L) {
  vars <- unique(as.character(vars))
  vars <- vars[nzchar(vars)]
  if (length(vars) == 0L) return(list(character(0)))
  n <- length(vars)
  out <- list()
  if (n <= max_exhaustive) {
    for (sz in seq(n, 1L)) {
      out <- c(out, combn(vars, sz, simplify = FALSE))
    }
    return(out)
  }
  out <- c(out, list(vars))
  n_drop_max <- as.integer(max_drop_layers)[1L]
  if (!is.finite(n_drop_max) || n_drop_max < 1L) n_drop_max <- 1L
  n_drop_max <- min(n_drop_max, n - 1L)
  for (k in seq_len(n_drop_max)) {
    sz <- n - k
    if (sz < 1L) break
    nc <- tryCatch(as.numeric(choose(n, sz)), error = function(e) Inf)
    if (length(nc) != 1L || !is.finite(nc) || nc > max_choose_per_layer) {
      nc_show <- if (is.finite(nc)) as.character(round(nc, 0)) else "NA"
      cli::cli_alert_warning(
        "covariate_subsets_decreasing_from_full: n={n}，跳过 size={sz}（组合数 {nc_show} > {max_choose_per_layer}）"
      )
      next
    }
    out <- c(out, combn(vars, sz, simplify = FALSE))
  }
  out
}

# ── Table 2 式：按分组列描述基线特征（Overall + 各组 + p），与 block_baseline 检验逻辑对齐 ──
#   若缺少 gtsummary / dplyr 则静默跳过并返回 NULL。
export_table2_characteristics_by_strata <- function(
    data,
    strata_col,
    index_var = NULL,
    selected_grouping = "quartile",
    exclude_cols = character(0),
    filepath,
    title,
    p_threshold = 0.05,
    discrete_threshold = 10L,
    force_continuous = character(0)) {
  if (!requireNamespace("gtsummary", quietly = TRUE) ||
      !requireNamespace("dplyr", quietly = TRUE)) {
    cli::cli_alert_warning("export_table2_characteristics_by_strata: 需要 gtsummary 与 dplyr，已跳过导出。")
    return(NULL)
  }
  if (!strata_col %in% names(data)) {
    cli::cli_alert_warning("export_table2_characteristics_by_strata: 分层列不在数据中。")
    return(NULL)
  }
  dd <- data
  dd[[strata_col]] <- droplevels(factor(dd[[strata_col]]))
  if (nlevels(dd[[strata_col]]) < 2L) {
    cli::cli_alert_warning("export_table2_characteristics_by_strata: 分层水平不足 2。")
    return(NULL)
  }

  # 参照论文表头：Q1 [lo - hi]
  if (!is.null(index_var) && index_var %in% names(dd) &&
      selected_grouping %in% c("quartile", "tertile", "median")) {
    xv <- dd[[index_var]]
    probs <- switch(selected_grouping,
      "quartile" = c(0, 0.25, 0.5, 0.75, 1),
      "tertile" = c(0, 1 / 3, 2 / 3, 1),
      c(0, 0.5, 1)
    )
    cuts <- unique(as.numeric(quantile(xv, probs = probs, na.rm = TRUE)))
    lv <- levels(dd[[strata_col]])
    if (length(cuts) >= 2L && length(lv) == length(cuts) - 1L) {
      new_lv <- character(length(lv))
      for (i in seq_along(lv)) {
        lo <- cuts[i]
        hi <- cuts[i + 1L]
        bracket <- if (i == length(lv)) {
          paste0("[", fmt_num(lo), " - ", fmt_num(hi), "]")
        } else {
          paste0("[", fmt_num(lo), " - ", fmt_num(hi), "]")
        }
        new_lv[i] <- paste0(lv[i], " ", bracket)
      }
      levels(dd[[strata_col]]) <- new_lv
    }
  }

  excl <- unique(c(strata_col, exclude_cols))
  analysis_vars <- setdiff(names(dd), excl)
  if (length(analysis_vars) == 0L) {
    cli::cli_alert_warning("export_table2_characteristics_by_strata: 无可描述变量。")
    return(NULL)
  }

  .test_normality_tbl2 <- function(x) {
    x <- x[!is.na(x)]
    n <- length(x)
    if (n < 3) return(FALSE)
    p <- tryCatch(
      if (n > 5000) stats::ks.test(scale(x), "pnorm")$p.value else stats::shapiro.test(x)$p.value,
      error = function(e) 0
    )
    p >= 0.05
  }

  all_numeric <- analysis_vars[vapply(dd[, analysis_vars, drop = FALSE], is.numeric, logical(1))]
  fc <- intersect(as.character(force_continuous), all_numeric)
  is_disc <- vapply(all_numeric, function(v) {
    if (v %in% fc) return(FALSE)
    length(unique(stats::na.omit(dd[[v]]))) <= discrete_threshold
  }, logical(1))
  discrete_numeric <- all_numeric[is_disc]
  continuous_vars <- all_numeric[!is_disc]
  for (v in discrete_numeric) dd[[v]] <- as.factor(dd[[v]])
  categorical_vars <- c(setdiff(analysis_vars, all_numeric), discrete_numeric)

  normality_result <- vapply(continuous_vars, function(v) .test_normality_tbl2(dd[[v]]), logical(1))
  normal_vars <- continuous_vars[normality_result]
  skewed_vars <- continuous_vars[!normality_result]

  n_groups <- nlevels(dd[[strata_col]])
  fisher_vars <- categorical_vars[vapply(categorical_vars, function(v) {
    tv <- table(dd[[v]], dd[[strata_col]])
    any(tv < 5)
  }, logical(1))]

  stat_list <- c(
    setNames(rep(list("{mean} \u00b1 {sd}"), length(normal_vars)), normal_vars),
    setNames(rep(list("{median} ({p25}, {p75})"), length(skewed_vars)), skewed_vars),
    setNames(rep(list("{n} ({p}%)"), length(categorical_vars)), categorical_vars)
  )
  type_list <- if (length(fc) > 0L) {
    setNames(rep(list("continuous"), length(fc)), fc)
  } else NULL

  test_list <- c(
    setNames(lapply(normal_vars, function(v) if (n_groups == 2) "t.test" else "aov"), normal_vars),
    setNames(lapply(skewed_vars, function(v) if (n_groups == 2) "wilcox.test" else "kruskal.test"), skewed_vars),
    setNames(lapply(categorical_vars, function(v) {
      if (v %in% fisher_vars) "fisher.test" else "chisq.test"
    }), categorical_vars)
  )

  tbl <- tryCatch({
    tbl_args <- list(
      data = dplyr::select(dd, dplyr::all_of(c(strata_col, analysis_vars))),
      by = strata_col,
      statistic = stat_list,
      digits = list(gtsummary::all_continuous() ~ 2, gtsummary::all_categorical() ~ c(0, 2)),
      missing = "no"
    )
    if (!is.null(type_list)) tbl_args$type <- type_list
    t0 <- do.call(gtsummary::tbl_summary, tbl_args)
    if (length(fisher_vars) > 0L) {
      t0 <- gtsummary::add_p(
        t0,
        test = test_list,
        pvalue_fun = function(p) fmt_pval(p),
        test.args = stats::setNames(
          rep(list(list(workspace = 2e8, simulate.p.value = TRUE, B = 2000)), length(fisher_vars)),
          fisher_vars
        )
      )
    } else {
      t0 <- gtsummary::add_p(t0, test = test_list, pvalue_fun = function(p) fmt_pval(p))
    }
    t0 <- gtsummary::add_overall(t0)
    gtsummary::bold_p(t0, t = p_threshold)
  }, error = function(e) {
    cli::cli_alert_warning("Table 2 (characteristics) gtsummary 失败: {e$message}")
    NULL
  })
  if (is.null(tbl)) return(NULL)
  tbl_df <- as.data.frame(tbl)
  ft <- c(
    "Continuous variables: normal distribution shown as Mean \u00b1 SD (t-test or ANOVA); non-normal as Median (Q1, Q3) (Wilcoxon or Kruskal-Wallis).",
    "Categorical variables: n (%) (\u03c7\u00b2 or Fisher's exact test).",
    paste0("P-value threshold for bold: ", p_threshold, ".")
  )
  tryCatch({
    export_sci_table(
      tbl_df,
      filepath,
      title = title,
      latex_include_colnames = FALSE,
      table_footnotes = ft
    )
    cli::cli_alert_success("Table 2 (characteristics) 已入队导出: {.file {basename(filepath)}}")
  }, error = function(e) {
    cli::cli_alert_warning("Table 2 (characteristics) export_sci_table 失败: {e$message}")
  })
  invisible(list(tbl = tbl, tbl_df = tbl_df))
}

# ── 递归复制目录（仅 base R）──────────────────────────────────────────────────
.copy_tree <- function(from_dir, to_dir, overwrite = TRUE) {
  if (!dir.exists(from_dir)) return(invisible(FALSE))
  if (!dir.exists(to_dir)) dir.create(to_dir, recursive = TRUE)
  for (nm in list.files(from_dir, full.names = FALSE, all.files = TRUE, no.. = TRUE)) {
    src <- file.path(from_dir, nm)
    dst <- file.path(to_dir, nm)
    if (dir.exists(src)) {
      .copy_tree(src, dst, overwrite = overwrite)
    } else {
      file.copy(src, dst, overwrite = overwrite)
    }
  }
  invisible(TRUE)
}

# ── 按 step 序号 + block 名汇总各 block 产出 ───────────────────────────────────
#
#  在跑完一套 pipeline 后调用，将各 block 目录整棵复制到目标文件夹下，
#  子目录名为 step01_<block>、step02_<block> …（顺序与本次 run_block 调用一致）。
#
#  用法:
#    collect_pipeline_results(ctx)
#    collect_pipeline_results(ctx, dest_dir = "D:/我的汇总结果")
#    collect_pipeline_results(config = config)   # 无 ctx 时按磁盘扫描（顺序为目录名字母序）
#
#  默认目标目录: <project$output_dir>/Results_by_step
#
collect_pipeline_results <- function(ctx = NULL,
                                     config = NULL,
                                     dest_dir = NULL,
                                     steps_prefix = "Step",
                                     overwrite = TRUE) {
  root <- NULL
  block_map <- NULL

  if (!is.null(ctx)) {
    root <- ctx$root_output_dir %||% dirname(ctx$output_dir %||% ".")
    block_map <- ctx$log$block_output_dirs
  } else if (!is.null(config)) {
    root <- config$project$output_dir %||% "Output"
  } else {
    stop("请提供 ctx 或 config。")
  }

  root <- normalizePath(root, winslash = "/", mustWork = FALSE)
  if (!nzchar(root) || !dir.exists(root)) {
    stop("输出根目录不存在: ", root)
  }

  if (is.null(block_map) || length(block_map) == 0) {
    skip <- c("Tables", "Figures", "Data", "Results_by_step")
    cand <- list.dirs(root, full.names = FALSE, recursive = FALSE)
    cand <- cand[!cand %in% skip & nzchar(cand)]
    cand <- cand[vapply(cand, function(nm) {
      p <- file.path(root, nm)
      any(dir.exists(file.path(p, c("Tables", "Figures", "Data")))) ||
        length(list.files(p, all.files = FALSE, no.. = TRUE)) > 0
    }, logical(1))]
    if (length(cand) == 0) {
      cli::cli_alert_warning("未在 {.file {root}} 下发现 block 子目录，且 log 为空。")
      return(invisible(NULL))
    }
    cand <- sort(cand)
    block_map <- stats::setNames(as.list(file.path(root, cand)), cand)
    cli::cli_alert_info("无 ctx$log，已按子目录名排序复制 {length(block_map)} 个文件夹。")
  }

  if (is.null(dest_dir)) {
    dest_dir <- file.path(root, "Results_by_step")
  } else {
    dest_dir <- normalizePath(dest_dir, winslash = "/", mustWork = FALSE)
  }
  if (!dir.exists(dest_dir)) dir.create(dest_dir, recursive = TRUE)
  dest_dir <- normalizePath(dest_dir, winslash = "/", mustWork = TRUE)

  n <- length(block_map)
  for (i in seq_len(n)) {
    bn <- names(block_map)[i]
    from <- block_map[[i]]
    if (!is.null(from)) from <- normalizePath(from, winslash = "/", mustWork = FALSE)
    step_dir <- file.path(dest_dir, sprintf("%s%02d_%s", steps_prefix, i, bn))
    if (overwrite && dir.exists(step_dir)) unlink(step_dir, recursive = TRUE)
    dir.create(step_dir, recursive = TRUE)
    if (nzchar(from %||% "") && dir.exists(from)) {
      .copy_tree(from, step_dir, overwrite = overwrite)
      cli::cli_alert_success("已汇总 {.strong {bn}} -> {.file {basename(step_dir)}}")
    } else {
      cli::cli_alert_warning("跳过（目录不存在）: {bn} -> {from %||% ''}")
    }
  }
  cli::cli_alert_info("汇总完成: {.file {dest_dir}}")
  invisible(dest_dir)
}


# ── 生成运行报告摘要 ──────────────────────────────────────────────────────────
print_run_summary <- function(ctx) {
  cli::cli_h1("Run Summary")
  root_output_dir <- ctx$root_output_dir %||% ctx$output_dir
  cli::cli_alert_info("Output directory: {.file {root_output_dir}}")
  if (!is.null(ctx$output_dir_tables))
    cli::cli_alert_info("Tables: {.file {ctx$output_dir_tables}}")
  if (!is.null(ctx$output_dir_figures))
    cli::cli_alert_info("Figures: {.file {ctx$output_dir_figures}}")
  if (!is.null(ctx$data$raw))
    cli::cli_alert_info("Raw data: {nrow(ctx$data$raw)} rows x {ncol(ctx$data$raw)} cols")
  if (!is.null(ctx$data$cleaned))
    cli::cli_alert_info("Cleaned data: {nrow(ctx$data$cleaned)} rows x {ncol(ctx$data$cleaned)} cols")
  if (!is.null(ctx$data$imputed))
    cli::cli_alert_info("Imputed data: {nrow(ctx$data$imputed)} rows x {ncol(ctx$data$imputed)} cols")
  if (!is.null(ctx$results$selected_features))
    cli::cli_alert_info("Selected features ({length(ctx$results$selected_features)}): {paste(ctx$results$selected_features, collapse = ', ')}")
  out_files <- list.files(root_output_dir, full.names = FALSE)
  tbl_dir <- ctx$output_dir_tables %||% file.path(root_output_dir, "Tables")
  fig_dir <- ctx$output_dir_figures %||% file.path(root_output_dir, "Figures")
  tbl_files <- if (dir.exists(tbl_dir)) list.files(tbl_dir, full.names = FALSE) else character(0)
  fig_files <- if (dir.exists(fig_dir)) list.files(fig_dir, full.names = FALSE) else character(0)
  if (length(out_files) > 0 || length(tbl_files) > 0 || length(fig_files) > 0) {
    cli::cli_h2("Output files")
    if (length(out_files) > 0) { cli::cli_alert_info("Root ({length(out_files)}): data/csv/rds"); for (f in head(out_files, 15)) cli::cli_li("{f}"); if (length(out_files) > 15) cli::cli_li("...") }
    if (length(tbl_files) > 0) { cli::cli_alert_info("Tables ({length(tbl_files)}):"); for (f in tbl_files) cli::cli_li("{f}") }
    if (length(fig_files) > 0) { cli::cli_alert_info("Figures ({length(fig_files)}):"); for (f in fig_files) cli::cli_li("{f}") }
  }
  if (!is.null(ctx$log$block_output_dirs) && length(ctx$log$block_output_dirs) > 0) {
    cli::cli_h2("Block output folders")
    for (bn in names(ctx$log$block_output_dirs)) {
      cli::cli_alert_info("{bn}: {.file {ctx$log$block_output_dirs[[bn]]}}")
    }
  }
}

# ── 通用能力层（MI 质量门控 / 审计 / 中介亚组路由 / 敏感性默认）─────────────
local({
  rdir <- NULL
  ofile <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
  if (!is.null(ofile) && nzchar(ofile)) {
    rdir <- dirname(normalizePath(ofile, winslash = "/", mustWork = FALSE))
  }
  cand_cap <- c(
    if (!is.null(rdir)) file.path(rdir, "pipeline_capability_layer.R"),
    file.path(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""), "R", "pipeline_capability_layer.R"),
    file.path("R", "pipeline_capability_layer.R")
  )
  path_cap <- cand_cap[file.exists(cand_cap)][1L]
  if (!is.na(path_cap) && nzchar(path_cap)) source(path_cap, local = FALSE)

  cand_sens <- c(
    if (!is.null(rdir)) file.path(rdir, "sensitivity_scenario_runner.R"),
    file.path(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""), "R", "sensitivity_scenario_runner.R"),
    file.path("R", "sensitivity_scenario_runner.R")
  )
  path_sens <- cand_sens[file.exists(cand_sens)][1L]
  if (!is.na(path_sens) && nzchar(path_sens)) source(path_sens, local = FALSE)

  # 血小板 / 血细胞 K/uL 全局规则（APRI/FIB4/SII 等依赖；禁止 Platelet med>50 误 ÷1000）
  cand_hema <- c(
    if (!is.null(rdir)) file.path(rdir, "hematology_units.R"),
    file.path(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""), "R", "hematology_units.R"),
    file.path("R", "hematology_units.R")
  )
  path_hema <- cand_hema[file.exists(cand_hema)][1L]
  if (!is.na(path_hema) && nzchar(path_hema)) source(path_hema, local = FALSE)

  # 统一分类配色库（KM / boxplot / cutoff / 森林图等）
  cand_pal <- c(
    if (!is.null(rdir)) file.path(rdir, "color_palettes.R"),
    file.path(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""), "R", "color_palettes.R"),
    file.path("R", "color_palettes.R")
  )
  path_pal <- cand_pal[file.exists(cand_pal)][1L]
  if (!is.na(path_pal) && nzchar(path_pal)) source(path_pal, local = FALSE)

  # 发表图 profile 门控（缺省 NULL=旧图；仅 mimic_inc_prog_sle_aki 改 theme）
  cand_pfp <- c(
    if (!is.null(rdir)) file.path(rdir, "pub_figure_profile.R"),
    file.path(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""), "R", "pub_figure_profile.R"),
    file.path("R", "pub_figure_profile.R")
  )
  path_pfp <- cand_pfp[file.exists(cand_pfp)][1L]
  if (!is.na(path_pfp) && nzchar(path_pfp)) source(path_pfp, local = FALSE)

  cand_uv <- c(
    if (!is.null(rdir)) file.path(rdir, "univariate_or_helpers.R"),
    file.path(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""), "R", "univariate_or_helpers.R"),
    file.path("R", "univariate_or_helpers.R")
  )
  path_uv <- cand_uv[file.exists(cand_uv)][1L]
  if (!is.na(path_uv) && nzchar(path_uv)) source(path_uv, local = FALSE)
})
