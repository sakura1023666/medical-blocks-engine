###############################################################################
#  subgroup_forest_plot.R — 发病/预后亚组森林图（HRS / NHANES 统一版式）
###############################################################################

subgroup_pretty_label <- function(x) {
  x <- as.character(x %||% "")
  x <- gsub("_", " ", x, fixed = TRUE)
  x <- gsub("\\s+", " ", x)
  x <- gsub("([0-9]{2})\\s+([0-9]{2})", "\\1-\\2", x, perl = TRUE)
  # BMI 最高组统一为 ≥30（兼容历史 "> 30" / ">30"）
  x <- gsub("^(\\s*)>\\s*30\\s*$", "\\1\u2265 30", x, perl = TRUE)
  trimws(x)
}

subgroup_format_p <- function(p) {
  p <- suppressWarnings(as.numeric(p)[1L])
  if (length(p) != 1L || is.na(p)) return(" ")
  if (p < 0.001) "<0.001" else sprintf("%.3f", p)
}

#' Benjamini–Hochberg FDR for subgroup forest P columns
#'
#' config$subgroup$p_adjust：FALSE/NULL/"none" 关闭；"BH"/"fdr"/TRUE 开启（默认方法 BH）。
#' 层内效应 P（有点估计的行）与 interaction P（标题行）分别校正。
#' 开启后列名改为 "P FDR (BH)" / "P-int FDR (BH)"，便于图注与方法段引用。
subgroup_apply_fdr_p <- function(res, sub_cfg = list()) {
  if (is.null(res) || !is.data.frame(res) || !nrow(res)) return(res)
  adj <- sub_cfg$p_adjust %||% sub_cfg$fdr %||% FALSE
  if (isFALSE(adj) || is.null(adj)) return(res)
  if (is.character(adj) && tolower(adj) %in% c("", "none", "no", "false", "off")) return(res)
  method <- if (isTRUE(adj) || (is.character(adj) && tolower(adj) %in% c("bh", "fdr", "true", "yes", "on"))) {
    "BH"
  } else if (is.character(adj) && nzchar(adj)) {
    adj
  } else {
    "BH"
  }

  p_col <- names(res)[tolower(names(res)) %in% c("p value", "p.value", "pvalue", "p")]
  p_col <- if (length(p_col)) p_col[[1L]] else {
    hit <- grep("^p(\\s|_|$|value)", names(res), ignore.case = TRUE, value = TRUE)
    hit <- hit[!grepl("interaction|fdr", hit, ignore.case = TRUE)]
    if (length(hit)) hit[[1L]] else NA_character_
  }
  pint_col <- names(res)[grepl("interaction", names(res), ignore.case = TRUE)]
  pint_col <- if (length(pint_col)) pint_col[[1L]] else NA_character_

  # 有点估计 → 层内比较；标题行用 interaction
  pe <- if ("Point Estimate" %in% names(res)) {
    suppressWarnings(as.numeric(as.character(res[["Point Estimate"]])))
  } else if ("OR" %in% names(res)) {
    suppressWarnings(as.numeric(as.character(res[["OR"]])))
  } else if ("HR" %in% names(res)) {
    suppressWarnings(as.numeric(as.character(res[["HR"]])))
  } else {
    rep(NA_real_, nrow(res))
  }
  is_level <- is.finite(pe)

  parse_p <- function(x) {
    x <- trimws(as.character(x))
    x[x %in% c("", " ", "NA", "N/A", "<NA>")] <- NA_character_
    x <- gsub("^<\\s*", "", x)
    suppressWarnings(as.numeric(x))
  }

  if (!is.na(p_col) && p_col %in% names(res)) {
    raw <- parse_p(res[[p_col]])
    out <- rep(NA_real_, length(raw))
    ok <- is_level & is.finite(raw)
    if (any(ok)) out[ok] <- stats::p.adjust(raw[ok], method = method)
    res[[p_col]] <- ifelse(
      is.na(out),
      ifelse(is_level, " ", as.character(res[[p_col]])),
      vapply(out, subgroup_format_p, character(1L))
    )
    # 层内行：空白掉未校正残留；标题行本就无层内 P
    res[[p_col]][!is_level] <- " "
    names(res)[names(res) == p_col] <- paste0("P FDR (", method, ")")
    cli::cli_alert_info(
      "Subgroup FDR: adjusted {sum(ok)} stratum P-values (method={method})"
    )
  }
  if (!is.na(pint_col) && pint_col %in% names(res)) {
    raw <- parse_p(res[[pint_col]])
    out <- rep(NA_real_, length(raw))
    ok <- !is_level & is.finite(raw)
    if (any(ok)) out[ok] <- stats::p.adjust(raw[ok], method = method)
    res[[pint_col]] <- ifelse(
      is.na(out),
      ifelse(!is_level, " ", as.character(res[[pint_col]])),
      vapply(out, subgroup_format_p, character(1L))
    )
    res[[pint_col]][is_level] <- " "
    names(res)[names(res) == pint_col] <- paste0("P-int FDR (", method, ")")
    cli::cli_alert_info(
      "Subgroup FDR: adjusted {sum(ok)} interaction P-values (method={method})"
    )
  }
  attr(res, "subgroup_p_adjust") <- method
  res
}

subgroup_forest_arrow_lab <- function(ref_grp, disease_lbl) {
  ref_pretty <- subgroup_pretty_label(ref_grp)
  disease_pretty <- subgroup_pretty_label(disease_lbl)
  c(
    paste0("Lower odds (OR<1) - toward ", ref_pretty),
    paste0("Higher odds (OR>1) - toward ", disease_pretty)
  )
}

subgroup_forest_ticks_at <- function(xlim, sub_cfg = list()) {
  fx <- suppressWarnings(as.numeric(xlim))
  if (length(fx) != 2L || any(!is.finite(fx)) || fx[2] <= fx[1]) fx <- c(0, 4)
  ft <- sub_cfg$forest_ticks_at
  if (!is.null(ft) && length(ft)) {
    ft <- suppressWarnings(as.numeric(ft))
    ft <- ft[is.finite(ft) & ft >= fx[1] & ft <= fx[2]]
    if (length(ft)) return(ft)
  }
  if (fx[2] - fx[1] > 10) {
    pretty(c(fx[1], fx[2]), n = 5)
  } else {
    seq(fx[1], fx[2], length.out = 3L)
  }
}

subgroup_age_forbidden <- function(cfg, extra_forbid = character(0)) {
  forbid <- subgroup_default_forbid(cfg, extra_forbid)
  any(c("Age", "Age_Years", "Age_Group") %in% forbid)
}

subgroup_order_vars <- function(v, req_ord = character(0)) {
  v <- unique(as.character(v[nzchar(as.character(v))]))
  # 发病双库：强制 clinical canon，保证 NHANES/CHARLS 森林图变量顺序一致
  # （req_ord 仅用于补齐映射，不再覆盖 canon）
  req_ord <- unique(as.character(req_ord[nzchar(as.character(req_ord))]))
  req_ord <- vapply(req_ord, function(x) {
    if (x %in% c("Age", "Age_Years")) "Age_Group" else x
  }, character(1L), USE.NAMES = FALSE)
  if (exists("subgroup_order_vars_clinical", mode = "function")) {
    ordered <- subgroup_order_vars_clinical(v)
    # 把 req 中存在但未进 ordered 的补到末尾
    return(unique(c(ordered, intersect(req_ord, v))))
  }
  req_hit <- req_ord[req_ord %in% v]
  if (length(req_hit)) return(unique(c(req_hit, setdiff(v, req_hit))))
  v
}

#' 各亚组水平在指定数据上的人数（森林图 N 列：展示分层全样本量）
#'
#' 必须按「变量 × 水平」嵌套，禁止只用 Yes/No 当键：Alcohol / Hypertension /
#' Diabetes 等共病都是 No/Yes，扁平键会后写覆盖先写，图上人数变得一模一样。
#'
#' @return named list；`out[[varname]][[level]]` 为整数 n。varname 同时登记
#'   原始名与 pretty 名；level 同时登记裸标签、pretty 标签及带缩进「  x」。
subgroup_stratum_n_map <- function(data, vars, pretty_fn = NULL) {
  if (is.null(data) || !is.data.frame(data) || !length(vars)) return(list())
  if (is.null(pretty_fn) || !is.function(pretty_fn)) {
    pretty_fn <- if (exists("subgroup_pretty_label", mode = "function")) {
      subgroup_pretty_label
    } else {
      function(x) gsub("_", " ", as.character(x), fixed = TRUE)
    }
  }
  out <- list()
  for (v in unique(as.character(vars))) {
    if (!nzchar(v) || !v %in% names(data)) next
    x <- data[[v]]
    if (!(is.factor(x) || is.character(x))) next
    tab <- table(as.character(x), useNA = "no")
    inner <- list()
    for (lv in names(tab)) {
      n <- as.integer(tab[[lv]])
      lab <- pretty_fn(lv)
      inner[[paste0("  ", lab)]] <- n
      inner[[lab]] <- n
      inner[[lv]] <- n
      inner[[paste0("  ", lv)]] <- n
    }
    if (!length(inner)) next
    out[[v]] <- inner
    v_pretty <- pretty_fn(v)
    if (nzchar(v_pretty) && !identical(v_pretty, v)) out[[v_pretty]] <- inner
  }
  out
}

#' 按当前标题行的亚组变量查找分层 n（兼容旧扁平 n_map）
.subgroup_n_map_lookup <- function(n_map, var_name, level_label) {
  if (is.null(n_map) || !length(n_map)) return(NULL)
  var_name <- trimws(as.character(var_name %||% ""))
  level_label <- as.character(level_label %||% "")
  inner <- NULL
  if (nzchar(var_name)) {
    keys_var <- unique(c(
      var_name,
      gsub(" ", "_", var_name, fixed = TRUE),
      gsub("_", " ", var_name, fixed = TRUE)
    ))
    keys_var <- keys_var[nzchar(keys_var)]
    for (k in keys_var) {
      cand <- n_map[[k]]
      if (is.list(cand) && !is.null(cand) && length(cand) &&
          !is.numeric(cand)) {
        inner <- cand
        break
      }
    }
  }
  pick <- function(mp) {
    if (is.null(mp)) return(NULL)
    n <- mp[[level_label]]
    if (is.null(n)) n <- mp[[trimws(level_label)]]
    if (is.null(n)) n <- mp[[paste0("  ", trimws(level_label))]]
    n
  }
  n <- pick(inner)
  if (!is.null(n)) return(n)
  # 旧扁平 map：仅当该键不是「变量名 → 子 list」时才用（避免误取另一变量）
  pick(n_map)
}

#' 将森林图表的 Count/N 覆盖为全分层样本量（OR 仍可为 Q4 vs Q1）
#' @param n_source "full_stratum"（默认）| "model_sample"（保持模型样本）
subgroup_overlay_forest_count <- function(df, n_map, total_n = NULL,
                                          n_source = "full_stratum") {
  n_source <- as.character(n_source %||% "full_stratum")[1L]
  if (!identical(n_source, "full_stratum")) return(df)
  if (is.null(df) || !is.data.frame(df) || !nrow(df) || !"Count" %in% names(df)) {
    return(df)
  }
  if (is.null(n_map) || !length(n_map)) return(df)
  var <- as.character(df$Variable %||% "")
  n_changed <- 0L
  current_var <- NA_character_
  for (i in seq_len(nrow(df))) {
    v <- var[i]
    is_level <- grepl("^\\s+", v) && nzchar(trimws(v))
    if (!is_level) {
      current_var <- trimws(v)
      next
    }
    n <- .subgroup_n_map_lookup(n_map, current_var, v)
    if (is.null(n) || !is.finite(as.numeric(n)[1L])) next
    n <- as.integer(n)[1L]
    df$Count[i] <- n
    n_changed <- n_changed + 1L
    if ("Percent" %in% names(df) && is.finite(total_n) && as.numeric(total_n)[1L] > 0) {
      df$Percent[i] <- sprintf("%.1f", 100 * n / as.numeric(total_n)[1L])
    }
  }
  if (n_changed > 0L) {
    cli::cli_alert_info(
      "森林图 N 列：已用全分层样本量覆盖 {n_changed} 行（OR 仍为最高 vs 最低分位）"
    )
  }
  df
}

subgroup_nhanes_results_to_glm_table <- function(dt_raw, total_n,
                                                pretty_fn = subgroup_pretty_label) {
  rows <- list()
  for (sub in unique(dt_raw$Subgroup)) {
    sub_rows <- dt_raw[dt_raw$Subgroup == sub, , drop = FALSE]
    rows[[length(rows) + 1L]] <- data.frame(
      Variable = pretty_fn(sub),
      Count = " ",
      Percent = " ",
      `Point Estimate` = NA_real_,
      Lower = NA_real_,
      Upper = NA_real_,
      `P value` = " ",
      `P for interaction` = subgroup_format_p(sub_rows$P.inter[1]),
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
    for (i in seq_len(nrow(sub_rows))) {
      parts <- strsplit(as.character(sub_rows$Events[i]), "/", fixed = TRUE)[[1L]]
      n_tot <- suppressWarnings(as.numeric(parts[2L]))
      pct <- if (is.finite(n_tot) && total_n > 0) {
        sprintf("%.1f", 100 * n_tot / total_n)
      } else {
        " "
      }
      rows[[length(rows) + 1L]] <- data.frame(
        Variable = paste0("  ", pretty_fn(sub_rows$Levels[i])),
        Count = if (is.finite(n_tot)) as.integer(n_tot) else " ",
        Percent = pct,
        `Point Estimate` = sub_rows$OR[i],
        Lower = sub_rows$Lower[i],
        Upper = sub_rows$Upper[i],
        `P value` = subgroup_format_p(sub_rows$P.value[i]),
        `P for interaction` = " ",
        stringsAsFactors = FALSE,
        check.names = FALSE
      )
    }
  }
  do.call(rbind, rows)
}

#' 将多水平暴露结果的 Levels 并入 Variable，避免森林图左侧空白
subgroup_merge_levels_into_variable <- function(plot_df) {
  if (!is.data.frame(plot_df) || !"Variable" %in% names(plot_df)) return(plot_df)
  if (!"Levels" %in% names(plot_df)) return(plot_df)
  var_raw <- as.character(plot_df$Variable)
  var_raw[is.na(var_raw)] <- ""
  was_indented <- grepl("^\\s+", var_raw)
  var <- trimws(var_raw)
  lev <- trimws(as.character(plot_df$Levels))
  lev[is.na(lev)] <- ""
  # 行标签空但 Levels 有内容 → 缩进显示 Levels（多水平暴露对比）
  fill <- !nzchar(var) & nzchar(lev)
  var[fill] <- paste0("  ", subgroup_pretty_label(lev[fill]))
  # 保留原缩进：trimws 后若不补回，层行会被误判为标题行 → OR 文本列空白
  keep_indent <- was_indented & !fill & nzchar(var)
  var[keep_indent] <- paste0("  ", var[keep_indent])
  plot_df$Variable <- var
  plot_df
}

#' 亚组森林分位解析：跟随主文锁定方案（tertile/quartile/binary）
#'
#' 双库 harmonize / scheme_harmonize / main_table_realign 会把最终方案写入
#' ctx$results；旧版亚组块硬编码 "quartile" 导致主文 tertile、亚组却按 Q4 vs Q1
#' 且只用两端子集（与主文分母脱节）。新铁律：亚组 = 全人群 + 主文同分位。
subgroup_resolve_main_scheme <- function(ctx, cfg, default = "quartile") {
  r <- ctx$results %||% list()
  for (k in c("logistic_grouping_scheme", "nhanes_logistic_selected_scheme",
              "nhanes_logistic_grouping_scheme", "dual_db_logistic_unified_scheme",
              "dual_db_cox_unified_scheme", "cox_grouping_scheme",
              "cox_selected_scheme")) {
    v <- tolower(trimws(as.character(r[[k]] %||% "")[1L]))
    if (v %in% c("quartile", "tertile", "binary")) return(v)
  }
  for (nm in c("logistic_tertile_glm", "cox_tertile")) {
    blk <- cfg[[nm]]
    if (!is.null(blk) && isTRUE(blk$enable %||% FALSE)) return("tertile")
  }
  for (nm in c("logistic_quartile_glm", "cox_quartile")) {
    blk <- cfg[[nm]]
    if (!is.null(blk) && isTRUE(blk$enable %||% FALSE)) return("quartile")
  }
  default
}

#' 将多水平分位因子折叠为「最低 | Middle | 最高」三水平（全人群，不删任何行）
#'
#' Q4 vs Q1（或 T3 vs T1）对比系数与四/三分位全模型完全一致：把中间分位并为
#' 一个协变量类别不改变最高层的系数估计；且保留全部人群，与主文 Table 2 同分母。
subgroup_collapse_middle_levels <- function(x, levels = NULL) {
  lv <- levels %||% levels(factor(x))
  lv <- as.character(lv)
  if (length(lv) <= 2L) return(x)
  mid <- lv[-c(1L, length(lv))]
  xc <- trimws(as.character(x))
  xc[xc %in% mid] <- "Middle"
  factor(xc, levels = c(lv[1L], "Middle", lv[length(lv)]))
}

#' 从 jstable 多水平分位输出中提取「最高 vs 最低」对比行（每层一行）
#'
#' 输入为 TableSubgroupMultiGLM / MultiCox 在「最低|Middle|最高」三水平暴露上
#' 的返回：每层 = 标题/参照行（Levels=index=Q1）+ Middle 行 + 最高行。
#' 输出与二水平暴露的 jstable 表同构（标题行 + 缩进对比行），下游
#' subgroup_prepare_forest_plot_df / N 覆盖 / 去 Overall 块全部原样可用。
#' jstable 在「最低|Middle|最高」三水平暴露上的原始结构：
#'   变量标题行（Variable=ageg, Levels=NA, P for interaction）
#'   层行（Variable=< 45, Levels=x=Q1, Count=全层 n, OR=Reference）
#'   对比行（Variable 空, Levels=x=Middle / x=Q4, OR/P 数值）
#' 本函数把每个层块折叠成与「二水平暴露」输出同构的一行：
#'   Variable 缩进「   层名」+ 层全量 Count/Percent + Levels 清空 +
#'   Point Estimate / Lower / Upper / P value 取最高对比行（Q4 vs Q1）。
#' 变量标题行原样保留；Overall 行由下游 res[-1,] / drop_exposure 去掉。
#' 全人群估计下 Middle 不改变最高层系数（哑变量嵌套性质），故与
#' 「仅 Q1+Q4 子集」旧口径相比，对比估计同值但分母为全分析集。
subgroup_fold_quantile_contrast_rows <- function(res, index_var, end_level) {
  if (is.null(res) || !is.data.frame(res) || !nrow(res)) return(res)
  end_level <- trimws(as.character(end_level %||% "")[1L])
  if (!nzchar(end_level)) return(res)
  lev_raw <- if ("Levels" %in% names(res)) {
    trimws(as.character(res$Levels))
  } else {
    rep("", nrow(res))
  }
  lev_raw[is.na(lev_raw)] <- ""
  ix <- as.character(index_var %||% "")[1L]
  ix_esc <- gsub("([][{}()*+?.^$|\\\\])", "\\\\\\1", ix, perl = TRUE)
  ix_pfx <- paste0(ix_esc, "=")
  is_exp_lev <- grepl(paste0("^", ix_pfx), lev_raw, perl = TRUE)
  var_raw <- as.character(res$Variable %||% "")
  var_raw[is.na(var_raw)] <- ""
  # 块起点 = Variable 非空（含缩进的层行，如「 < 45」与非空标题行如「ageg」/「Overall」）
  blk_i <- which(nzchar(trimws(var_raw)))
  if (!length(blk_i)) return(res)
  ends <- c(blk_i[-1L] - 1L, nrow(res))
  num_cols <- intersect(
    c("Point Estimate", "OR", "HR", "Lower", "Upper", "P value", "P.value"),
    names(res)
  )
  end_set <- c(end_level, paste0(ix, "=", end_level))
  rows <- list()
  for (b in seq_along(blk_i)) {
    s <- blk_i[[b]]; e <- ends[[b]]
    block <- if (e >= s) seq(s, e) else s
    block_exp <- block[is_exp_lev[block]]
    cand <- block_exp[lev_raw[block_exp] %in% end_set]
    if (!length(cand)) {
      # 无暴露对比行 = 变量标题行（仅 P for interaction）→ 原样保留；
      # 有对比行但缺最高层（极端情形）→ 整块丢弃
      if (!length(block_exp)) rows[[length(rows) + 1L]] <- res[s, , drop = FALSE]
      next
    }
    cmp_i <- cand[[length(cand)]]
    base <- res[s, , drop = FALSE]
    for (cn in num_cols) base[[cn]] <- res[[cn]][cmp_i]
    base_var <- trimws(var_raw[s])
    if (!base_var %in% c("Overall", "Total", "All")) {
      base$Variable <- paste0("   ", base_var)
    }
    if ("Levels" %in% names(base)) base$Levels <- ""
    rows[[length(rows) + 1L]] <- base
  }
  if (!length(rows)) return(res)
  out <- do.call(rbind, rows)
  # 折叠后 Levels 全空 → 删除该列，使下游 merge_levels_into_variable 提前返回、
  # 保留 Variable 缩进（与二水平 jstable 输出同构；否则缩进被 trimws 抹掉，
  # 层行会被误判为标题行而清空点估计）。
  if ("Levels" %in% names(out)) {
    lv_left <- trimws(as.character(out$Levels))
    filled <- !is.na(lv_left) & nzchar(lv_left) & !lv_left %in% c("NA", " ")
    if (!any(filled)) out$Levels <- NULL
  }
  rownames(out) <- NULL
  out
}

#' 按亚组标题行切块，保证分页不拆开同一亚组
subgroup_forest_split_chunks <- function(plot_df, header_labels, max_rows = 45L) {
  n <- nrow(plot_df)
  if (n <= max_rows) return(list(plot_df))
  var <- trimws(as.character(plot_df$Variable))
  is_hdr <- var %in% subgroup_pretty_label(header_labels)
  # 无标题行时按固定行数切
  if (!any(is_hdr)) {
    idx <- seq_len(n)
    splits <- split(idx, ceiling(idx / max_rows))
    return(lapply(splits, function(ii) plot_df[ii, , drop = FALSE]))
  }
  # 每个标题行开启新块；块满则换页（标题跟随本块）
  hdr_pos <- which(is_hdr)
  starts <- unique(c(1L, hdr_pos))
  starts <- starts[starts <= n]
  ends <- c(starts[-1L] - 1L, n)
  blocks <- Map(function(a, b) plot_df[a:b, , drop = FALSE], starts, ends)

  chunks <- list()
  cur <- NULL
  for (b in blocks) {
    if (is.null(cur)) {
      cur <- b
    } else if (nrow(cur) + nrow(b) <= max_rows) {
      cur <- rbind(cur, b)
    } else {
      chunks[[length(chunks) + 1L]] <- cur
      cur <- b
    }
    # 单块自身已超限：再硬切
    if (nrow(cur) > max_rows) {
      idx <- seq_len(nrow(cur))
      for (part in split(idx, ceiling(idx / max_rows))) {
        chunks[[length(chunks) + 1L]] <- cur[part, , drop = FALSE]
      }
      cur <- NULL
    }
  }
  if (!is.null(cur) && nrow(cur)) chunks[[length(chunks) + 1L]] <- cur
  chunks
}

#' 亚组森林：去掉 Overall / 暴露分位块，只保留真正分层变量
subgroup_drop_exposure_overall_block <- function(res, index_var, subgroup_vars) {
  if (is.null(res) || !is.data.frame(res) || !nrow(res) || !"Variable" %in% names(res)) {
    return(res)
  }
  var <- trimws(as.character(res$Variable))
  is_hdr <- !grepl("^\\s+", as.character(res$Variable))
  sg_ok <- unique(c(
    as.character(subgroup_vars %||% character(0)),
    gsub("_", " ", as.character(subgroup_vars %||% character(0)), fixed = TRUE)
  ))
  sg_ok <- sg_ok[nzchar(sg_ok)]
  ix <- as.character(index_var %||% "")[1L]
  ix_lab <- gsub("_", " ", ix, fixed = TRUE)
  drop_hdr <- function(v) {
    if (!nzchar(v)) return(TRUE)
    if (v %in% c("Overall", "Total", "All")) return(TRUE)
    if (nzchar(ix) && identical(v, ix)) return(TRUE)
    if (nzchar(ix_lab) && identical(v, ix_lab)) return(TRUE)
    # ANLR / ANLR_quartile / ANLR quartile / ANLR group …
    # 指标名几乎都是 [A-Za-z0-9_]+；避免 TRE 字符类转义炸掉
    if (nzchar(ix) && grepl("^[A-Za-z0-9_]+$", ix)) {
      if (grepl(
        paste0("^", ix, "([_[:space:]]+(quartile|tertile|binary|group|cut))?$"),
        v, ignore.case = TRUE
      )) {
        return(TRUE)
      }
    }
    if (nzchar(ix_lab) && !identical(ix_lab, ix) && grepl("^[A-Za-z0-9_ ]+$", ix_lab)) {
      lab_pat <- gsub("[[:space:]]+", "[[:space:]]+", ix_lab)
      if (grepl(
        paste0("^", lab_pat, "([_[:space:]]+(quartile|tertile|binary|group|cut))?$"),
        v, ignore.case = TRUE
      )) {
        return(TRUE)
      }
    }
    # 非亚组名单中的标题块一律丢掉（防暴露别名漏网）
    if (length(sg_ok) && !(v %in% sg_ok)) return(TRUE)
    FALSE
  }
  keep <- rep(TRUE, nrow(res))
  i <- 1L
  while (i <= nrow(res)) {
    if (is_hdr[i] && drop_hdr(var[i])) {
      keep[i] <- FALSE
      j <- i + 1L
      while (j <= nrow(res) && !is_hdr[j]) {
        keep[j] <- FALSE
        j <- j + 1L
      }
      i <- j
      next
    }
    i <- i + 1L
  }
  res[keep, , drop = FALSE]
}

subgroup_prepare_forest_plot_df <- function(res, effect_sym = "OR") {
  need_cols <- c("Lower", "Upper", "Variable", "Point Estimate")
  if (is.null(res) || !is.data.frame(res) || nrow(res) < 1L || !all(need_cols %in% names(res))) {
    return(NULL)
  }
  plot_df <- res
  plot_df <- subgroup_merge_levels_into_variable(plot_df)

  txt_idx <- setdiff(
    seq_len(ncol(plot_df)),
    which(names(plot_df) %in% c("Point Estimate", "Lower", "Upper"))
  )
  for (ci in txt_idx) {
    plot_df[[ci]] <- ifelse(is.na(plot_df[[ci]]), " ", as.character(plot_df[[ci]]))
  }
  # 固定宽度空白列：绝不能用 nrow 个空格，否则 CI 列撑满整页、Variable 被挤没
  plot_df$` ` <- paste(rep(" ", 20L), collapse = "")

  for (cn in c("Point Estimate", "Lower", "Upper")) {
    plot_df[[cn]] <- suppressWarnings(as.numeric(as.character(plot_df[[cn]])))
  }
  # 仅隐藏非有限 / ≤0 / 完全分离量级的荒谬值；大但有限的 OR/HR 必须保留可画
  # （旧阈值 Point>50 / Upper>100 会把 TyG_* 等强关联亚组点全部抹掉，图看起来“空”）
  hide_est_gt <- suppressWarnings(as.numeric(getOption("subgroup.forest_hide_est_gt", 500))[1L])
  hide_upper_gt <- suppressWarnings(as.numeric(getOption("subgroup.forest_hide_upper_gt", 1000))[1L])
  if (!is.finite(hide_est_gt) || hide_est_gt < 50) hide_est_gt <- 500
  if (!is.finite(hide_upper_gt) || hide_upper_gt < 100) hide_upper_gt <- 1000
  bad_est <- !is.finite(plot_df$"Point Estimate") |
    !is.finite(plot_df$Lower) |
    !is.finite(plot_df$Upper) |
    plot_df$"Point Estimate" <= 0 |
    plot_df$Lower <= 0 |
    plot_df$Upper <= 0 |
    plot_df$"Point Estimate" > hide_est_gt |
    plot_df$Upper > hide_upper_gt
  # 标题行本身无点估计，不计入「隐藏」告警
  is_header0 <- !grepl("^\\s+", as.character(plot_df$Variable %||% ""))
  bad_est[is_header0] <- FALSE
  ci_lab <- paste0(effect_sym, " (95% CI)")
  is_header <- !grepl("^\\s+", as.character(plot_df$Variable %||% ""))
  # 先写 CI 文本：可估用数值；分离/荒谬用 NE（不再留空列）
  plot_df[[ci_lab]] <- ifelse(
    is_header,
    "",
    ifelse(
      bad_est,
      "NE",
      sprintf("%.2f (%.2f-%.2f)", plot_df$"Point Estimate", plot_df$Lower, plot_df$Upper)
    )
  )
  if (any(bad_est, na.rm = TRUE)) {
    n_bad <- sum(bad_est, na.rm = TRUE)
    cli::cli_alert_info(
      "Subgroup forest: {n_bad} 行效应量不可估/荒谬（est>{hide_est_gt} 或 Upper>{hide_upper_gt}/Inf）→ 表列显示 NE，不画点"
    )
    plot_df$"Point Estimate"[bad_est] <- NA_real_
    plot_df$Lower[bad_est] <- NA_real_
    plot_df$Upper[bad_est] <- NA_real_
  }
  # 标题行不应显示效应量（经典森林图仅保留 P for interaction）
  if (any(is_header)) {
    plot_df$"Point Estimate"[is_header] <- NA_real_
    plot_df$Lower[is_header] <- NA_real_
    plot_df$Upper[is_header] <- NA_real_
  }
  for (ci in txt_idx) {
    if (identical(names(plot_df)[ci], "Levels")) next
    plot_df[[ci]] <- subgroup_pretty_label(plot_df[[ci]])
  }
  # pretty_label 会吃掉缩进；对原缩进行补回两空格
  raw_var <- as.character(res$Variable)
  if ("Levels" %in% names(res)) {
    lev0 <- trimws(as.character(res$Levels))
    raw_var <- ifelse(
      !nzchar(trimws(as.character(res$Variable))) & nzchar(lev0),
      paste0("  ", lev0),
      as.character(res$Variable)
    )
  }
  was_indented <- grepl("^\\s+", raw_var)
  plot_df$Variable <- ifelse(
    was_indented,
    paste0("  ", trimws(as.character(plot_df$Variable))),
    trimws(as.character(plot_df$Variable))
  )
  plot_df
}

subgroup_build_one_forest <- function(plot_df, final_subgroup_vars, sub_cfg,
                                      effect_sym = "OR", arrow_lab = NULL,
                                      plot_ff = "") {
  ci_lab <- paste0(effect_sym, " (95% CI)")
  # 兼容旧版带下划线的列名
  for (old in c(paste0(effect_sym, "_CI"), paste0(effect_sym, " (95% CI)"))) {
    if (!identical(old, ci_lab) && old %in% names(plot_df) && !ci_lab %in% names(plot_df)) {
      names(plot_df)[names(plot_df) == old] <- ci_lab
    }
  }
  tm <- forestploter::forest_theme(
    base_size = as.numeric(sub_cfg$forest_base_size %||% 9)[1L],
    base_family = plot_ff,
    refline_gp = grid::gpar(lty = "dashed", col = "black"),
    ci_pch = c(15),
    ci_col = as.character(sub_cfg$forest_ci_col %||% "black")[1L],
    ci_alpha = 0.8,
    ci_lty = 1,
    ci_lwd = 1.5,
    ci_Theight = 0,
    vertline_lty = c("dashed", "dotted"),
    vertline_col = c("#d6604d", "#bababa")
  )

  fx <- sub_cfg$forest_xlim %||% c(0.2, 4)
  fx <- suppressWarnings(as.numeric(fx))
  if (length(fx) != 2L || any(!is.finite(fx)) || fx[2] <= fx[1]) fx <- c(0.2, 4)
  # 上限：config$subgroup$forest_xlim_max；默认 80（旧默认 10 会把 OR>10 的点全部裁出画布）
  max_xlim <- suppressWarnings(as.numeric(sub_cfg$forest_xlim_max %||% 80)[1L])
  if (!is.finite(max_xlim) || max_xlim < 2) max_xlim <- 80
  finite_est <- plot_df$"Point Estimate"[
    is.finite(plot_df$"Point Estimate") & plot_df$"Point Estimate" > 0
  ]
  finite_upper <- plot_df$Upper[is.finite(plot_df$Upper) & plot_df$Upper > 0]
  finite_lower <- plot_df$Lower[
    is.finite(plot_df$Lower) & plot_df$Lower > 0
  ]
  if (length(finite_est) || length(finite_upper)) {
    # 优先盖住 ≥90% 的点估计与上界，避免“表有 OR、图上空”
    p90_est <- if (length(finite_est))
      as.numeric(stats::quantile(finite_est, 0.90, na.rm = TRUE)) else 0
    p90_up <- if (length(finite_upper))
      as.numeric(stats::quantile(finite_upper, 0.90, na.rm = TRUE)) else 0
    need_raw <- max(p90_est * 1.15, p90_up * 1.05, max(finite_est, na.rm = TRUE) * 1.05, 2)
    need <- max(fx[2], min(max_xlim, max(ceiling(need_raw), 2)))
    if (need > fx[2]) {
      fx[2] <- need
      cli::cli_alert_info("Subgroup forest xlim auto-expanded to c({fx[1]}, {fx[2]})")
    }
  }
  # 下界：保护性 OR（如 0.04）时 CI 常低于 config 默认 0.2，导致“图空白/CI 全在 xlim 外”
  if (length(finite_lower) || length(finite_est)) {
    min_pos_cfg <- suppressWarnings(as.numeric(sub_cfg$forest_xlim_log_min %||% 0.01)[1L])
    if (!is.finite(min_pos_cfg) || min_pos_cfg <= 0) min_pos_cfg <- 0.01
    min_raw <- min(c(finite_lower, finite_est[finite_est > 0]), na.rm = TRUE)
    if (is.finite(min_raw) && min_raw < fx[1]) {
      new_lo <- max(min_pos_cfg, min_raw * 0.75)
      if (new_lo < fx[1]) {
        fx[1] <- new_lo
        cli::cli_alert_info(
          "Subgroup forest xlim lower expanded to {signif(fx[1], 3)}（min OR/CI={signif(min_raw, 3)}）"
        )
      }
    }
  }
  if (fx[2] > max_xlim) fx[2] <- max_xlim
  # 若仍有大量点估计落在 xlim 外，再尽量抬到 max_xlim（仍保留箭头提示超界 CI）
  if (length(finite_est)) {
    n_out <- sum(finite_est > fx[2], na.rm = TRUE)
    if (n_out > 0L && fx[2] < max_xlim) {
      fx[2] <- min(max_xlim, max(fx[2], ceiling(max(finite_est[finite_est <= max_xlim], na.rm = TRUE) * 1.05)))
      cli::cli_alert_info(
        "Subgroup forest xlim raised to cover estimates: c({fx[1]}, {fx[2]})（{n_out} 点曾超界）"
      )
    }
  }
  # HR/OR 默认对数轴，压缩右侧长 CI，减少箭头压到 HR 文本
  x_trans <- as.character(sub_cfg$forest_x_trans %||% NA_character_)[1L]
  if (!nzchar(x_trans) || is.na(x_trans)) {
    x_trans <- if (toupper(effect_sym) %in% c("HR", "OR", "RR")) "log" else "none"
  }
  if (!x_trans %in% c("none", "log", "log2", "log10")) x_trans <- "none"
  # log 轴下界必须 >0；config 常写 forest_xlim=c(0,4) 会触发 invalid 'xscale' in viewport
  if (x_trans %in% c("log", "log2", "log10")) {
    min_pos <- suppressWarnings(as.numeric(sub_cfg$forest_xlim_log_min %||% 0.2)[1L])
    if (!is.finite(min_pos) || min_pos <= 0) min_pos <- 0.2
    if (fx[1] < min_pos) {
      fx[1] <- min_pos
      cli::cli_alert_info(
        "Subgroup forest: log 轴下界抬至 {fx[1]}（config forest_xlim 含 0 无效）"
      )
    }
  }
  if (x_trans %in% c("log", "log2", "log10")) {
    ft <- c(0.2, 0.5, 1, 2, 5, 10, 20, 50, 80)
    ft <- ft[ft >= fx[1] & ft <= fx[2]]
    if (length(ft) < 2L) ft <- subgroup_forest_ticks_at(fx, sub_cfg)
  } else {
    ft <- subgroup_forest_ticks_at(fx, sub_cfg)
    ft <- ft[ft >= fx[1] & ft <= fx[2]]
  }
  if (!length(ft)) ft <- seq(fx[1], fx[2], length.out = 3L)
  # 轴端留白：首尾刻度不要贴死 xlim，否则 0.2 的「0」和右侧末刻度会被 clip
  tick_pad <- suppressWarnings(as.numeric(sub_cfg$forest_tick_pad_mult %||% 2.2)[1L])
  if (!is.finite(tick_pad) || tick_pad < 1.05) tick_pad <- 2.2
  if (x_trans %in% c("log", "log2", "log10")) {
    fx[1] <- max(fx[1] / tick_pad, .Machine$double.eps * 10)
    fx[2] <- fx[2] * tick_pad
  } else {
    span <- max(fx[2] - fx[1], 1e-6)
    fx[1] <- fx[1] - span * (tick_pad - 1)
    fx[2] <- fx[2] + span * (tick_pad - 1)
  }
  f_arrow <- sub_cfg$forest_arrow_length
  if (is.null(f_arrow) || !is.finite(suppressWarnings(as.numeric(f_arrow)))) {
    f_arrow <- fx[2]
  } else {
    f_arrow <- as.numeric(f_arrow)
  }

  # 表头无下划线：Subgroup | N | forest | HR (95% CI) | P value | P for interaction
  hide_pct <- isTRUE(sub_cfg$forest_hide_percent %||% TRUE)
  disp <- plot_df
  rename_map <- c(
    "Variable" = "Subgroup",
    "Count" = "N",
    "P_val" = "P value",
    "P_inter" = "P for interaction"
  )
  for (from in names(rename_map)) {
    to <- unname(rename_map[[from]])
    if (from %in% names(disp) && !to %in% names(disp)) {
      names(disp)[names(disp) == from] <- to
    }
  }
  if (!" " %in% names(disp)) {
    disp$` ` <- NA_character_
  }
  # CI 列占位宽度由空格数决定；过短则森林箭头易压到右侧 HR 文本
  n_sp <- suppressWarnings(as.integer(sub_cfg$forest_ci_spacer_chars %||% 12L)[1L])
  if (!is.finite(n_sp) || n_sp < 4L) n_sp <- 12L
  if (n_sp > 28L) n_sp <- 28L
  disp$` ` <- paste(rep(" ", n_sp), collapse = "")
  # 保证每行同宽
  if (nrow(disp) > 1L) disp$` ` <- rep(disp$` `[1L], nrow(disp))
  if (!ci_lab %in% names(disp)) {
    old_ci <- paste0(effect_sym, "_CI")
    if (old_ci %in% names(disp)) names(disp)[names(disp) == old_ci] <- ci_lab
  }
  .col_or_blank <- function(nm) if (nm %in% names(disp)) nm else " "
  # 森林列后插一窄空列，给 CI 箭头留缓冲，避免压到 HR 文本
  gap_nm <- "  "
  if (!gap_nm %in% names(disp) || identical(gap_nm, " ")) {
    # 用不会与 CI 占位列混淆的列名
    gap_nm <- "\u00a0"
    disp[[gap_nm]] <- "  "
  } else {
    disp[[gap_nm]] <- "  "
  }
  if (nrow(disp) > 1L) disp[[gap_nm]] <- rep(disp[[gap_nm]][1L], nrow(disp))
  forest_col_names <- unique(c(
    .col_or_blank("Subgroup"),
    .col_or_blank("N"),
    if (!hide_pct) .col_or_blank("Percent") else character(0),
    " ",
    gap_nm,
    ci_lab,
    .col_or_blank("P value"),
    .col_or_blank("P for interaction")
  ))
  ci_col_idx <- which(forest_col_names == " ")[[1L]]

  if (x_trans %in% c("log", "log2", "log10")) {
    for (nm in c("Point Estimate", "Lower", "Upper")) {
      v <- plot_df[[nm]]
      v[is.finite(v) & v <= 0] <- NA_real_
      plot_df[[nm]] <- v
    }
  }
  p <- forestploter::forest(
    disp[, forest_col_names, drop = FALSE],
    est = list(plot_df$"Point Estimate"),
    lower = list(plot_df$Lower),
    upper = list(plot_df$Upper),
    ci_column = c(ci_col_idx),
    sizes = 0.55,
    ref_line = 1,
    arrow_lab = arrow_lab,
    xlim = fx,
    ticks_at = ft,
    arrow_length = f_arrow,
    x_trans = x_trans,
    theme = tm
  )
  p <- forestploter::edit_plot(p, part = "header", gp = grid::gpar(fontface = "bold"))
  # 强制加宽 CI 图形列，避免箭头侵入左右文本列
  ci_extra <- suppressWarnings(as.numeric(sub_cfg$forest_ci_extra_in %||% 1.6)[1L])
  if (is.finite(ci_extra) && ci_extra > 0 && !is.null(p$widths)) {
    g_ci <- as.integer(ci_col_idx) + 1L
    if (g_ci >= 1L && g_ci <= length(p$widths)) {
      cur <- tryCatch(
        as.numeric(grid::convertWidth(p$widths[[g_ci]], "in", valueOnly = TRUE)),
        error = function(e) NA_real_
      )
      if (!is.finite(cur) || cur < 0.5) cur <- 1.4
      p$widths[[g_ci]] <- grid::unit(cur + ci_extra, "in")
    }
  }
  # 禁止 gtable/viewport clip：xaxis 默认 clip=on 会切掉端点刻度「0.2」的「0」
  if (!is.null(p$layout) && "clip" %in% names(p$layout)) {
    p$layout$clip[] <- "off"
  }
  .forest_vp_clip_off <- function(g) {
    if (is.null(g)) return(g)
    if (inherits(g, "viewport")) {
      g$clip <- "off"
      return(g)
    }
    if (!is.null(g$vp)) {
      if (inherits(g$vp, "vpTree")) {
        g$vp$parent$clip <- "off"
        if (!is.null(g$vp$children)) {
          for (i in seq_along(g$vp$children)) {
            if (inherits(g$vp$children[[i]], "viewport")) {
              g$vp$children[[i]]$clip <- "off"
            }
          }
        }
      } else if (inherits(g$vp, "viewport")) {
        g$vp$clip <- "off"
      }
    }
    if (inherits(g, "gTree") && !is.null(g$children) && length(g$children)) {
      for (nm in names(g$children)) {
        g$children[[nm]] <- .forest_vp_clip_off(g$children[[nm]])
      }
    }
    g
  }
  p <- .forest_vp_clip_off(p)
  # 左右/上下加空白，避免轴端 0.2 与右侧 P 画出页外（gtable 从原点起画，溢出即裁）
  lab_pad <- suppressWarnings(as.numeric(sub_cfg$forest_axis_col_pad_in %||% 0.32)[1L])
  if (!is.finite(lab_pad) || lab_pad < 0.08) lab_pad <- 0.32
  if (requireNamespace("gtable", quietly = TRUE) && !is.null(p$widths)) {
    p <- gtable::gtable_add_cols(p, grid::unit(lab_pad, "in"), pos = 0)
    p <- gtable::gtable_add_cols(p, grid::unit(max(0.18, lab_pad * 0.65), "in"), pos = -1)
    p <- gtable::gtable_add_rows(p, grid::unit(0.10, "in"), pos = 0)
    p <- gtable::gtable_add_rows(p, grid::unit(0.18, "in"), pos = -1)
  }

  var_labels_for_bold <- subgroup_pretty_label(final_subgroup_vars)
  subgroup_row_indices <- which(trimws(as.character(plot_df$Variable)) %in% var_labels_for_bold)
  if (length(subgroup_row_indices) > 0) {
    p <- forestploter::edit_plot(p, row = subgroup_row_indices, gp = grid::gpar(fontface = "bold"))
    p_col <- which(forest_col_names == "P for interaction")
    if (length(p_col)) {
      p <- forestploter::edit_plot(
        p, row = subgroup_row_indices, col = p_col,
        gp = grid::gpar(fontface = "bold")
      )
    }
  }
  if (isTRUE(sub_cfg$forest_highlight_interaction_sig) &&
      "P for interaction" %in% names(plot_df)) {
    p_col_hi <- which(forest_col_names == "P for interaction")
    pv_raw <- plot_df[["P for interaction"]]
    pv_num <- suppressWarnings(as.numeric(gsub("[^0-9.eE+-]", "", as.character(pv_raw))))
    sig_rows <- which(is.finite(pv_num) & pv_num < 0.05)
    if (length(p_col_hi) && length(sig_rows)) {
      p <- forestploter::edit_plot(
        p, row = sig_rows, col = p_col_hi,
        gp = grid::gpar(fontface = "bold", col = "#C0392B")
      )
    }
  }
  p
}

subgroup_render_forest_figure <- function(ctx, plot_df, final_subgroup_vars, sub_cfg,
                                         fig_caption, effect_sym = "OR",
                                         arrow_lab = NULL) {
  if (is.null(plot_df) || !nrow(plot_df)) return(invisible(FALSE))

  if (!requireNamespace("forestploter", quietly = TRUE)) {
    cli::cli_alert_warning("subgroup_render_forest_figure: 需要 forestploter 包")
    return(invisible(FALSE))
  }
  suppressPackageStartupMessages({
    library(forestploter, warn.conflicts = FALSE)
    library(grid, warn.conflicts = FALSE)
  })

  plot_ff <- if (exists("plot_font_from_config", mode = "function")) {
    plot_font_from_config(ctx$config)
  } else if (exists("resolve_plot_font_family", mode = "function")) {
    resolve_plot_font_family("Times New Roman")
  } else {
    "Times"
  }
  max_rows <- as.integer(sub_cfg$forest_max_rows_per_page %||% 45L)[1L]
  if (!is.finite(max_rows) || max_rows < 15L) max_rows <- 45L
  max_h <- as.numeric(sub_cfg$forest_max_height_in %||% 22)[1L]
  if (!is.finite(max_h) || max_h < 8) max_h <- 22
  # 默认尽量一张图：不分页，按行数加高画布（对齐经典单页亚组森林图）
  force_one <- isTRUE(sub_cfg$forest_force_single_page %||% TRUE)

  if (force_one) {
    chunks <- list(plot_df)
    need_h <- nrow(plot_df) * 0.30 + 2.4
    if (need_h > max_h) {
      max_h <- min(36, need_h)
      cli::cli_alert_info(
        "Subgroup forest: 单页输出 {nrow(plot_df)} 行，画布高度 {round(max_h, 1)} in"
      )
    }
  } else {
    chunks <- subgroup_forest_split_chunks(plot_df, final_subgroup_vars, max_rows = max_rows)
  }
  n_page <- length(chunks)
  if (n_page > 1L) {
    cli::cli_alert_info(
      "Subgroup forest: {nrow(plot_df)} 行 → 分页 {n_page} 页（每页≤{max_rows} 行）"
    )
  }

  fig_kind <- as.character(sub_cfg$figure_kind %||% "main_figure")[1L]
  if (!nzchar(fig_kind)) fig_kind <- "main_figure"
  fig_no <- suppressWarnings(as.integer(sub_cfg$figure_number %||% NA_integer_)[1L])
  fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir, "Figures")
  if (!dir.exists(fig_dir)) dir.create(fig_dir, recursive = TRUE)
  fig_path <- if (is.finite(fig_no) && fig_no >= 1L &&
                  exists("pub_figure_filepath_at", mode = "function")) {
    pub_figure_filepath_at(
      fig_dir, fig_no, fig_caption, ext = "pdf",
      bump_counter = isTRUE(sub_cfg$bump_counter %||% TRUE),
      kind = fig_kind
    )
  } else {
    file.path(fig_dir, pub_figure_file(ctx, fig_kind, fig_caption))
  }
  fig_name <- basename(fig_path)

  .save_one_page <- function(p, path, height_in = NULL) {
    # forestploter::get_wh → 按 gtable 真实占位自适应画布，消除四周大白边
    wh <- tryCatch(
      forestploter::get_wh(p, unit = "in"),
      error = function(e) NULL
    )
    if (is.null(wh) || any(!is.finite(as.numeric(wh)))) {
      # 需有打开的 graphics device 才能 convertHeight；先开 null
      grDevices::pdf(NULL)
      wh <- tryCatch(
        forestploter::get_wh(p, unit = "in"),
        error = function(e) NULL
      )
      try(grDevices::dev.off(), silent = TRUE)
    }
    fig_w <- suppressWarnings(as.numeric(wh[["width"]] %||% wh[1L])[1L])
    fig_h <- suppressWarnings(as.numeric(wh[["height"]] %||% wh[2L])[1L])
    if (!is.finite(fig_w) || fig_w < 4) {
      fig_w <- as.numeric(sub_cfg$forest_width_in %||% 10)[1L]
      if (!is.finite(fig_w) || fig_w < 4) fig_w <- 10
    }
    if (!is.finite(fig_h) || fig_h < 3) {
      fig_h <- if (is.finite(as.numeric(height_in)[1L])) as.numeric(height_in)[1L] else 8
    }
    # 边距：贴合内容，避免四周大白边（可被 config 覆盖）
    pad <- as.numeric(sub_cfg$forest_margin_in %||% 0.22)[1L]
    if (!is.finite(pad) || pad < 0) pad <- 0.22
    arrow_pad <- 0
    if (!is.null(arrow_lab) && length(arrow_lab) && any(nzchar(as.character(arrow_lab)))) {
      arrow_pad <- as.numeric(sub_cfg$forest_arrow_lab_pad_in %||% 0.32)[1L]
      if (!is.finite(arrow_pad) || arrow_pad < 0) arrow_pad <- 0.32
    }
    side_pad <- as.numeric(sub_cfg$forest_side_pad_in %||% 0.20)[1L]
    if (!is.finite(side_pad) || side_pad < 0) side_pad <- 0.20
    max_w <- as.numeric(sub_cfg$forest_max_width_in %||% 12)[1L]
    if (!is.finite(max_w) || max_w < 6) max_w <- 12
    max_h_soft <- as.numeric(sub_cfg$forest_max_height_in %||% max_h)[1L]
    if (!is.finite(max_h_soft) || max_h_soft < 8) max_h_soft <- max_h
    min_w <- as.numeric(sub_cfg$forest_min_width_in %||% 3.8)[1L]
    if (!is.finite(min_w) || min_w < 3) min_w <- 3.8
    # 以 get_wh 为准；过大下限会撑出空白（最终仍会 bbox 裁切）
    fig_w <- min(max_w, max(min_w, fig_w + 2 * pad + 2 * side_pad))
    fig_h <- min(max(max_h_soft, 28), max(3.8, fig_h + 2 * pad + arrow_pad))
    n_row_est <- tryCatch(nrow(plot_df), error = function(e) NA_integer_)
    if (is.finite(n_row_est) && n_row_est > 0L) {
      cap_h <- n_row_est * 0.28 + 1.35 + arrow_pad
      if (is.finite(cap_h) && fig_h > cap_h + 0.25) {
        fig_h <- min(fig_h, max(3.8, cap_h))
      }
    }
    cli::cli_alert_info(
      "Subgroup forest 自适应画布: {round(fig_w, 2)} × {round(fig_h, 2)} in（arrow_pad={round(arrow_pad, 2)}）"
    )

    .draw <- function(device_fun, target) {
      device_fun(target, width = fig_w, height = fig_h, family = plot_ff)
      opened <- TRUE
      tryCatch(
        {
          # 整页关闭 clip，避免轴端刻度被 device/viewport 裁切
          grid::grid.newpage()
          grid::pushViewport(grid::viewport(clip = "off"))
          grid::grid.draw(p)
          grDevices::dev.off()
          opened <- FALSE
          TRUE
        },
        error = function(e) {
          if (isTRUE(opened)) try(grDevices::dev.off(), silent = TRUE)
          stop(e)
        }
      )
    }
    # Prefer cairo_pdf first so Unicode ≥ (U+2265) renders; base pdf()+Times often shows "= 65"
    ok <- tryCatch(
      .draw(grDevices::cairo_pdf, path),
      error = function(e) {
        cli::cli_alert_warning("cairo_pdf: {conditionMessage(e)}")
        tryCatch(
          .draw(function(path, width, height, family) {
            grDevices::pdf(path, width = width, height = height, family = family,
                           useDingbats = FALSE, compress = TRUE)
          }, path),
          error = function(e2) {
            cli::cli_alert_warning("pdf: {conditionMessage(e2)}")
            FALSE
          }
        )
      }
    )
    pdf_ok <- isTRUE(ok) && file.exists(path) && isTRUE((file.info(path)$size %||% 0) > 1000)
    if (!pdf_ok) return(FALSE)
    # 默认不按 GS bbox 裁切：bbox 常切掉轴端 0.2 的「0」（serif 左缘不被计入）
    if (isTRUE(sub_cfg$forest_trim_whitespace %||% FALSE)) {
      pad_pt <- as.numeric(sub_cfg$forest_trim_pad_pt %||% 36)[1L]
      if (!is.finite(pad_pt) || pad_pt < 0) pad_pt <- 36
      if (exists("pdf_trim_whitespace", mode = "function")) {
        trim_ok <- tryCatch(
          pdf_trim_whitespace(path, pad_pt = pad_pt),
          error = function(e) {
            cli::cli_alert_warning("forest PDF 去白边失败: {e$message}")
            FALSE
          }
        )
        if (isTRUE(trim_ok)) {
          cli::cli_alert_info("Subgroup forest 已按内容裁切白边（pad={pad_pt}pt）")
        }
      }
    }
    # SVG 旁路：默认关闭（config$project$export_figure_svg=TRUE 才写）
    if (!isTRUE(pub_export_figure_svg(ctx))) return(TRUE)
    if (!requireNamespace("svglite", quietly = TRUE)) {
      cli::cli_alert_warning("export_figure_svg=TRUE 但未安装 svglite，跳过 SVG")
      return(TRUE)
    }
    svg_path <- sub("\\.pdf$", ".svg", path, ignore.case = TRUE)
    svg_ok <- tryCatch(
      .draw(function(target, width, height, family) {
        svglite::svglite(target, width = width, height = height)
      }, svg_path),
      error = function(e) {
        cli::cli_alert_warning("svg: {conditionMessage(e)}")
        FALSE
      }
    )
    # PDF 已成功即视为成功；SVG 失败不拖垮整图
    TRUE
  }

  .combine_pdfs <- function(files, dest) {
    files <- files[file.exists(files)]
    if (!length(files)) return(FALSE)
    if (length(files) == 1L) {
      return(isTRUE(file.copy(files[[1L]], dest, overwrite = TRUE)))
    }
    if (requireNamespace("pdftools", quietly = TRUE)) {
      ok <- tryCatch({
        pdftools::pdf_combine(files, output = dest)
        TRUE
      }, error = function(e) FALSE)
      if (isTRUE(ok)) return(TRUE)
    }
    gs <- Sys.which(c("gswin64c", "gswin32c", "gs"))
    gs <- gs[nzchar(gs)]
    if (length(gs)) {
      status <- system2(
        gs[[1L]],
        c("-dBATCH", "-dNOPAUSE", "-q", "-sDEVICE=pdfwrite",
          paste0("-sOutputFile=", dest), files),
        stdout = FALSE, stderr = FALSE
      )
      if (identical(as.integer(status), 0L) && file.exists(dest)) return(TRUE)
    }
    # 回退：主文件=第1页，续页另存
    file.copy(files[[1L]], dest, overwrite = TRUE)
    for (i in seq_along(files)[-1L]) {
      alt <- sub("\\.pdf$", paste0("_p", i, ".pdf"), dest, ignore.case = TRUE)
      file.copy(files[[i]], alt, overwrite = TRUE)
      cli::cli_alert_info("Subgroup forest continued page: {.file {basename(alt)}}")
    }
    TRUE
  }

  tmp_dir <- file.path(
    tempdir(),
    paste0("sg_forest_", format(Sys.time(), "%Y%m%d%H%M%S"), "_", sample.int(1e6, 1L))
  )
  dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
  page_files <- character(0)
  page_svg_files <- character(0)
  for (i in seq_along(chunks)) {
    h_i <- max(8, min(max_h, nrow(chunks[[i]]) * 0.32 + 2.2))
    tp <- file.path(tmp_dir, sprintf("page_%02d.pdf", i))
    p <- subgroup_build_one_forest(
      chunks[[i]], final_subgroup_vars, sub_cfg,
      effect_sym = effect_sym, arrow_lab = arrow_lab, plot_ff = plot_ff
    )
    if (!.save_one_page(p, tp, h_i)) {
      cli::cli_alert_warning("Subgroup forest page {i} failed to save")
      next
    }
    page_files <- c(page_files, tp)
    tsvg <- sub("\\.pdf$", ".svg", tp, ignore.case = TRUE)
    if (file.exists(tsvg)) page_svg_files <- c(page_svg_files, tsvg)
  }

  ok <- length(page_files) > 0L && isTRUE(.combine_pdfs(page_files, fig_path))
  if (isTRUE(ok) && length(page_svg_files)) {
    if (length(page_svg_files) == 1L) {
      dest_svg <- sub("\\.pdf$", ".svg", fig_path, ignore.case = TRUE)
      file.copy(page_svg_files[[1L]], dest_svg, overwrite = TRUE)
      # SVG 仅留在 step Figures，不镜像汇总根目录
    } else {
      for (i in seq_along(page_svg_files)) {
        dest_svg <- sub(
          "\\.pdf$", paste0("_p", sprintf("%02d", i), ".svg"),
          fig_path, ignore.case = TRUE
        )
        file.copy(page_svg_files[[i]], dest_svg, overwrite = TRUE)
      }
    }
  }
  unlink(tmp_dir, recursive = TRUE)

  if (isTRUE(ok)) {
    sz <- tryCatch(file.info(fig_path)$size, error = function(e) NA_real_)
    np <- tryCatch({
      if (requireNamespace("pdftools", quietly = TRUE)) {
        pdftools::pdf_info(fig_path)$pages
      } else {
        length(page_files)
      }
    }, error = function(e) length(page_files))
    cli::cli_alert_success(
      "Figure saved: {.file {fig_path}} ({np} page(s), {sz} bytes)"
    )
    mirrored <- mirror_pub_output_to_root(ctx, fig_path)
    if (isTRUE(mirrored)) {
      root <- ctx$root_output_dir
      dest <- file.path(root, "Figures", basename(fig_path))
      dsz <- tryCatch(file.info(dest)$size, error = function(e) 0)
      src_sz <- tryCatch(file.info(fig_path)$size, error = function(e) 0)
      if (!is.finite(dsz) || dsz < 1000 || (is.finite(src_sz) && dsz < src_sz * 0.5)) {
        tryCatch(file.copy(fig_path, dest, overwrite = TRUE), error = function(e) NULL)
      }
    }
  } else {
    cli::cli_alert_warning("Subgroup forest figure not saved")
  }
  invisible(isTRUE(ok))
}
