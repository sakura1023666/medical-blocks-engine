# Review package Task 6
453 Blocks/75_osteo_dxa_qct/03block_modality_discordance_profile.R
2:#  modality_discordance_profile — DXA/QCT 不一致四组基线表（Table S5）
4:#  register_block: "modality_discordance_profile"
8:#  # ── 配置 config$modality_discordance_profile ───────────────────────────────
10:#  group_var    = "discordance_group"   # Both_OP / QCT_only_OP / DXA_only_OP / Neither_OP
13:#  fracture     = "Vertebral_fracture"  # 脚注：QCT_only 骨折例数
14:#  add_p        = TRUE                  # gtsummary 可用时加组间 P
18:#  写: ctx$results$modality_discordance_profile
19:#  表: Table S5. Baseline by discordance group（xlsx 或 CSV fallback）
195:.mdp75_gtsummary_table <- function(data, group_var, vars, group_levels, add_p = TRUE) {
196:  if (!requireNamespace("gtsummary", quietly = TRUE)) return(NULL)
217:      gtsummary::all_continuous() ~ "continuous",
218:      gtsummary::all_dichotomous() ~ "categorical"
221:      gtsummary::all_continuous() ~ "{mean} \u00b1 {sd}",
222:      gtsummary::all_categorical() ~ "{n} ({p}%)"
224:    digits = list(gtsummary::all_continuous() ~ 2),
228:    suppressWarnings(do.call(gtsummary::tbl_summary, tbl_args)),
237:          gtsummary::add_p(
239:              gtsummary::all_continuous() ~ "kruskal.test",
240:              gtsummary::all_categorical() ~ "chisq.test"
242:            pvalue_fun = ~ gtsummary::style_pvalue(.x, digits = 3)
250:      gtsummary::modify_header(
251:        gtsummary::all_stat_cols() ~ "**{level}**\nN = {n}",
259:    as.data.frame(gtsummary::as_tibble(tb, col_labels = TRUE)),
269:  list(table = flat, gtsummary = tb)
272:#' 内部计算：按 discordance_group 的基线汇总 + QCT_only 骨折脚注
278:  group_var <- as.character(cfg$group_var %||% "discordance_group")[1L]
280:    stop("modality_discordance_profile: missing group_var '", group_var, "'", call. = FALSE)
283:  preferred_levels <- c("Both_OP", "QCT_only_OP", "DXA_only_OP", "Neither_OP")
287:    stop("modality_discordance_profile: no non-missing group levels", call. = FALSE)
296:  n_qct_only <- as.integer(n_by_group[["QCT_only_OP"]] %||% 0L)
###############################################################################
#  modality_discordance_profile — DXA/QCT 不一致四组基线表（Table S5）
#
#  register_block: "modality_discordance_profile"
#  典型流水线: diagnostic_vs_fracture 之后
#  公共 helper: Blocks/75_osteo_dxa_qct/00osteo_dxa_qct_common.R
#
#  # ── 配置 config$modality_discordance_profile ───────────────────────────────
#  enable       = TRUE
#  group_var    = "discordance_group"   # Both_OP / QCT_only_OP / DXA_only_OP / Neither_OP
#  exclude_vars = c("SampleID")         # 另自动排除 group_var 与高基数 ID 类
#  include_vars = NULL                  # 非空时仅保留所列协变量
#  fracture     = "Vertebral_fracture"  # 脚注：QCT_only 骨折例数
#  add_p        = TRUE                  # gtsummary 可用时加组间 P
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  读: ctx$data$imputed %||% cleaned
#  写: ctx$results$modality_discordance_profile
#  表: Table S5. Baseline by discordance group（xlsx 或 CSV fallback）
###############################################################################

.mdp75_source_common <- function(ctx = NULL) {
  if (exists(".osteo75_pick_col", mode = "function") &&
      exists("%||%", mode = "function")) {
    return(invisible(TRUE))
  }
  roots <- character(0)
  if (!is.null(ctx) && !is.null(ctx$config$project$root)) {
    roots <- c(roots, as.character(ctx$config$project$root)[1L])
  }
  env_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (nzchar(env_root)) roots <- c(roots, env_root)
  roots <- c(roots, getwd())
  roots <- unique(roots[nzchar(roots)])
  for (r in roots) {
    p <- file.path(r, "Blocks/75_osteo_dxa_qct/00osteo_dxa_qct_common.R")
    if (file.exists(p)) {
      source(p, local = FALSE)
      return(invisible(TRUE))
    }
  }
  stop("Cannot locate 00osteo_dxa_qct_common.R", call. = FALSE)
}

.mdp75_is_continuous <- function(x) {
  if (is.factor(x) || is.character(x) || is.logical(x)) return(FALSE)
  if (inherits(x, "Date") || inherits(x, "POSIXt")) return(FALSE)
  x <- suppressWarnings(as.numeric(x))
  x <- x[is.finite(x)]
  if (!length(x)) return(FALSE)
  nuniq <- length(unique(x))
  if (nuniq <= 5L) return(FALSE)
  TRUE
}

.mdp75_fmt_mean_sd <- function(x, digits = 2L) {
  x <- suppressWarnings(as.numeric(x))
  x <- x[is.finite(x)]
  if (!length(x)) return("NA")
  sprintf(
    paste0("%.", digits, "f \u00b1 %.", digits, "f"),
    mean(x),
    stats::sd(x)
  )
}

.mdp75_fmt_n_pct <- function(n, denom, digits = 1L) {
  if (!is.finite(denom) || denom <= 0) return("0 (NA)")
  sprintf(
    paste0("%d (%.", digits, "f%%)"),
    as.integer(n),
    100 * as.numeric(n) / as.numeric(denom)
  )
}

.mdp75_resolve_vars <- function(data, cfg, group_var) {
  excl <- unique(c(
    as.character(cfg$exclude_vars %||% c("SampleID")),
    group_var,
    "SampleID", "ID", "id", "subject_id"
  ))
  inc <- cfg$include_vars
  if (!is.null(inc) && length(inc)) {
    vars <- intersect(as.character(inc), names(data))
    vars <- setdiff(vars, excl)
    return(vars)
  }
  # 默认：排除分组定义列、影像诊断列与重复结局标签，保留临床协变量 + 骨折结局
  auto_excl <- c(
    excl,
    "QCT_OP", "DXA_OP", "need_QCT",
    "QCT_cat", "DXA_cat_min", "DXA_cat_lumbar",
    "QCT_vBMD", "DXA_T_min", "DXA_T_lumbar",
    "Disease", "Fracture_f"
  )
  vars <- setdiff(names(data), auto_excl)
  # 若有 Nathan_bin，去掉原始 Nathan（避免 4×4 稀疏 chisq 警告）
  if ("Nathan_bin" %in% vars && "Nathan" %in% vars) {
    vars <- setdiff(vars, "Nathan")
  }
  # 丢掉全缺失列
  vars <- vars[vapply(vars, function(v) any(!is.na(data[[v]])), logical(1L))]
  # 高基数字符/因子（>15）不进表
  keep <- vapply(vars, function(v) {
    x <- data[[v]]
    if (is.character(x) || is.factor(x)) {
      return(length(unique(as.character(x[!is.na(x)]))) <= 15L)
    }
    TRUE
  }, logical(1L))
  vars[keep]
}

.mdp75_hand_summary <- function(data, group_var, vars, group_levels) {
  n_by <- vapply(group_levels, function(lv) {
    as.integer(sum(as.character(data[[group_var]]) == lv, na.rm = TRUE))
  }, integer(1L))
  names(n_by) <- group_levels

  rows <- list()
  # N 行
  n_row <- data.frame(
    Variable = "N",
    stringsAsFactors = FALSE
  )
  for (lv in group_levels) n_row[[lv]] <- as.character(n_by[[lv]])
  n_row$P <- ""
  rows[[length(rows) + 1L]] <- n_row

  for (v in vars) {
    x <- data[[v]]
    if (.mdp75_is_continuous(x)) {
      r <- data.frame(Variable = paste0(v, ", mean \u00b1 SD"), stringsAsFactors = FALSE)
      for (lv in group_levels) {
        idx <- which(as.character(data[[group_var]]) == lv)
        r[[lv]] <- .mdp75_fmt_mean_sd(x[idx])
      }
      # Kruskal-Wallis if possible
      pval <- tryCatch({
        df_p <- data.frame(
          y = suppressWarnings(as.numeric(x)),
          g = factor(as.character(data[[group_var]]), levels = group_levels)
        )
        df_p <- df_p[is.finite(df_p$y) & !is.na(df_p$g), , drop = FALSE]
        if (nrow(df_p) < 3L || length(unique(df_p$g)) < 2L) {
          NA_real_
        } else {
          stats::kruskal.test(y ~ g, data = df_p)$p.value
        }
      }, error = function(e) NA_real_)
      r$P <- if (is.finite(pval)) format.pval(pval, digits = 3, eps = 0.001) else ""
      rows[[length(rows) + 1L]] <- r
    } else {
      # categorical
      lev_x <- if (is.factor(x)) {
        levels(x)
      } else {
        sort(unique(as.character(x[!is.na(x)])))
      }
      if (!length(lev_x)) next
      # label row
      lab <- data.frame(Variable = paste0(v, ", n (%)"), stringsAsFactors = FALSE)
      for (lv in group_levels) lab[[lv]] <- ""
      # overall chi-square / fisher
      pval <- tryCatch({
        tab <- table(
          factor(as.character(x), levels = lev_x),
          factor(as.character(data[[group_var]]), levels = group_levels)
        )
        if (any(dim(tab) < 2L)) {
          NA_real_
        } else {
          suppressWarnings(stats::chisq.test(tab)$p.value)
        }
      }, error = function(e) NA_real_)
      lab$P <- if (is.finite(pval)) format.pval(pval, digits = 3, eps = 0.001) else ""
      rows[[length(rows) + 1L]] <- lab
      for (lx in lev_x) {
        r <- data.frame(Variable = paste0("  ", lx), stringsAsFactors = FALSE)
        for (lv in group_levels) {
          idx <- which(as.character(data[[group_var]]) == lv)
          n_hit <- sum(as.character(x[idx]) == lx, na.rm = TRUE)
          r[[lv]] <- .mdp75_fmt_n_pct(n_hit, n_by[[lv]])
        }
        r$P <- ""
        rows[[length(rows) + 1L]] <- r
      }
    }
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

.mdp75_gtsummary_table <- function(data, group_var, vars, group_levels, add_p = TRUE) {
  if (!requireNamespace("gtsummary", quietly = TRUE)) return(NULL)
  if (!requireNamespace("dplyr", quietly = TRUE)) return(NULL)

  dat <- data
  dat[[group_var]] <- factor(as.character(dat[[group_var]]), levels = group_levels)
  dat <- dat[!is.na(dat[[group_var]]), , drop = FALSE]
  if (!nrow(dat) || !length(vars)) return(NULL)

  # cast obvious 0/1 ints with few levels as factor for n(%)
  for (v in vars) {
    x <- dat[[v]]
    if (is.numeric(x) && !.mdp75_is_continuous(x)) {
      dat[[v]] <- factor(x)
    }
  }

  tbl_args <- list(
    data = dat,
    by = group_var,
    include = vars,
    type = list(
      gtsummary::all_continuous() ~ "continuous",
      gtsummary::all_dichotomous() ~ "categorical"
    ),
    statistic = list(
      gtsummary::all_continuous() ~ "{mean} \u00b1 {sd}",
      gtsummary::all_categorical() ~ "{n} ({p}%)"
    ),
    digits = list(gtsummary::all_continuous() ~ 2),
    missing = "no"
  )
  tb <- tryCatch(
    suppressWarnings(do.call(gtsummary::tbl_summary, tbl_args)),
    error = function(e) NULL
  )
  if (is.null(tb)) return(NULL)

  if (isTRUE(add_p)) {
    tb <- tryCatch(
      suppressWarnings(
        tb |>
          gtsummary::add_p(
            test = list(
              gtsummary::all_continuous() ~ "kruskal.test",
              gtsummary::all_categorical() ~ "chisq.test"
            ),
            pvalue_fun = ~ gtsummary::style_pvalue(.x, digits = 3)
          )
      ),
      error = function(e) tb
    )
  }
  tb <- tryCatch(
    tb |>
      gtsummary::modify_header(
        gtsummary::all_stat_cols() ~ "**{level}**\nN = {n}",
        label ~ "**Variable**"
      ),
    error = function(e) tb
  )

  # Flatten to data.frame for export
  flat <- tryCatch(
    as.data.frame(gtsummary::as_tibble(tb, col_labels = TRUE)),
    error = function(e) NULL
  )
  if (is.null(flat) || !nrow(flat)) return(NULL)
  names(flat)[1L] <- "Variable"
  # Ensure P column name if present
  p_col <- grep("^p(\\.|_|$|value)|\\*\\*p", names(flat), ignore.case = TRUE, value = TRUE)
  if (length(p_col) == 1L && p_col != "P") {
    names(flat)[names(flat) == p_col] <- "P"
  }
  list(table = flat, gtsummary = tb)
}

#' 内部计算：按 discordance_group 的基线汇总 + QCT_only 骨折脚注
.mdp75_compute <- function(data, cfg = list()) {
  if (!is.data.frame(data)) stop("data must be a data.frame", call. = FALSE)
  cfg <- cfg %||% list()
  .mdp75_source_common(NULL)

  group_var <- as.character(cfg$group_var %||% "discordance_group")[1L]
  if (!group_var %in% names(data)) {
    stop("modality_discordance_profile: missing group_var '", group_var, "'", call. = FALSE)
  }

  preferred_levels <- c("Both_OP", "QCT_only_OP", "DXA_only_OP", "Neither_OP")
  present <- unique(as.character(data[[group_var]][!is.na(data[[group_var]])]))
  group_levels <- c(intersect(preferred_levels, present), setdiff(sort(present), preferred_levels))
  if (!length(group_levels)) {
    stop("modality_discordance_profile: no non-missing group levels", call. = FALSE)
  }

  ok <- !is.na(data[[group_var]])
  data_ok <- data[ok, , drop = FALSE]
  n <- as.integer(nrow(data_ok))
  n_by_group <- as.integer(table(factor(as.character(data_ok[[group_var]]), levels = group_levels)))
  names(n_by_group) <- group_levels

  n_qct_only <- as.integer(n_by_group[["QCT_only_OP"]] %||% 0L)

  frac_nm <- as.character(
    cfg$fracture %||%
      tryCatch(
        .osteo75_pick_col(data_ok, c("Vertebral_fracture", "vertebral_fracture", "Fracture")),
        error = function(e) NA_character_
      )
  )[1L]
  n_qct_only_fracture <- 0L
  if (!is.na(frac_nm) && nzchar(frac_nm) && frac_nm %in% names(data_ok)) {
    idx_q <- which(as.character(data_ok[[group_var]]) == "QCT_only_OP")
    fr <- suppressWarnings(as.integer(data_ok[[frac_nm]][idx_q]))
    n_qct_only_fracture <- as.integer(sum(is.finite(fr) & fr != 0L))
  }

  vars <- .mdp75_resolve_vars(data_ok, cfg, group_var)
  add_p <- isTRUE(cfg$add_p %||% TRUE)

  gt <- .mdp75_gtsummary_table(data_ok, group_var, vars, group_levels, add_p = add_p)
  if (!is.null(gt) && is.data.frame(gt$table)) {
    table_df <- gt$table
    engine <- "gtsummary"
  } else {
    table_df <- .mdp75_hand_summary(data_ok, group_var, vars, group_levels)
    engine <- "hand"
  }

  footnote <- sprintf(
    paste0(
      "Table S5. Baseline characteristics by DXA/QCT discordance group. ",
      "Groups: Both_OP, QCT_only_OP, DXA_only_OP, Neither_OP. ",
      "N (non-missing %s) = %d; sum of group n = %d. ",
      "QCT_only_OP n = %d; QCT_only fracture events = %d",
      if (!is.na(frac_nm) && nzchar(frac_nm)) paste0(" (from ", frac_nm, ")") else "",
      ". Continuous: mean \u00b1 SD; categorical: n (%%). Engine=%s."
    ),
    group_var, n, as.integer(sum(n_by_group)),
    n_qct_only, n_qct_only_fracture, engine
  )

  # Attach footnote as attribute + column for exporters that keep last col notes
  attr(table_df, "footnote") <- footnote
  if (!"footnote" %in% names(table_df)) {
    table_df$footnote <- c(footnote, rep("", max(0L, nrow(table_df) - 1L)))
  }

  list(
    n = n,
    n_by_group = n_by_group,
    n_qct_only = n_qct_only,
    n_qct_only_fracture = n_qct_only_fracture,
    group_var = group_var,
    group_levels = group_levels,
    vars = vars,
    engine = engine,
    footnote = footnote,
    fracture_col = frac_nm,
    table = table_df
  )
}

.mdp75_export_table <- function(table_df, out_dir, title, footnote = NULL) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  base <- title
  xlsx_path <- file.path(out_dir, paste0(base, ".xlsx"))
  csv_path <- file.path(out_dir, paste0(base, ".csv"))
  exported <- NULL

  # Drop footnote column from body if present (keep in title/notes)
  body <- table_df
  if ("footnote" %in% names(body)) {
    body$footnote <- NULL
  }

  if (exists("export_sci_table", mode = "function")) {
    tryCatch({
      args <- list(df = body, filepath = xlsx_path, title = base)
      if (!is.null(footnote) && nzchar(footnote)) {
        # export_sci_table may accept footnotes / note; ignore if unused
        args$footnotes <- footnote
      }
      do.call(export_sci_table, args)
      exported <- xlsx_path
    }, error = function(e) NULL)
  }
  if (is.null(exported) && requireNamespace("openxlsx", quietly = TRUE)) {
    tryCatch({
      wb <- openxlsx::createWorkbook()
      openxlsx::addWorksheet(wb, "Table S5")
      openxlsx::writeData(wb, "Table S5", base, startRow = 1, colNames = FALSE)
      openxlsx::writeData(wb, "Table S5", body, startRow = 3)
      if (!is.null(footnote) && nzchar(footnote)) {
        openxlsx::writeData(
          wb, "Table S5", footnote,
          startRow = 3L + nrow(body) + 2L, colNames = FALSE
        )
      }
      openxlsx::saveWorkbook(wb, xlsx_path, overwrite = TRUE)
      exported <- xlsx_path
    }, error = function(e) NULL)
  }

  # CSV: append footnote as last comment-like row via extra column write
  csv_body <- body
  if (!is.null(footnote) && nzchar(footnote)) {
    csv_body$footnote <- c(footnote, rep("", max(0L, nrow(csv_body) - 1L)))
  }
  utils::write.csv(csv_body, csv_path, row.names = FALSE)
  if (is.null(exported)) exported <- csv_path
  list(table_path = exported, csv_path = csv_path)
}

block_modality_discordance_profile <- function(ctx, ...) {
  .mdp75_source_common(ctx)
  cfg_all <- ctx$config %||% list()
  cfg <- cfg_all$modality_discordance_profile %||% list()
  if (!is.null(cfg$enable) && !isTRUE(cfg$enable)) {
    return(ctx)
  }

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    stop("modality_discordance_profile: need ctx$data$imputed or ctx$data$cleaned", call. = FALSE)
  }

  comp <- .mdp75_compute(data, cfg)

  out_dir <- as.character(
    cfg_all$project$output_dir %||%
      cfg_all$paths$output_dir %||%
      file.path(tempdir(), "modality_discordance_profile")
  )[1L]
  tables_dir <- file.path(out_dir, "Tables")
  dir.create(tables_dir, recursive = TRUE, showWarnings = FALSE)

  title <- "Table S5. Baseline by discordance group"
  exp <- .mdp75_export_table(comp$table, tables_dir, title, footnote = comp$footnote)

  ctx$results$modality_discordance_profile <- c(
    comp[c(
      "n", "n_by_group", "n_qct_only", "n_qct_only_fracture",
      "group_var", "group_levels", "vars", "engine", "footnote",
      "fracture_col", "table"
    )],
    list(
      table_path = exp$table_path,
      csv_path = exp$csv_path
    )
  )
  ctx
}

register_block(
  "modality_discordance_profile",
  block_modality_discordance_profile,
  "Table S5 baseline by DXA/QCT discordance_group; footnote QCT_only fracture n"
)
