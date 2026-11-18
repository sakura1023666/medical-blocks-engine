###############################################################################
#  incidence_summary_result — 发病/预后 dual-batch → summary_result 收口
#
#  全项目铁律：
#    1) 成功指标 Tables/Figures → project/summary_result/（或 config$pub$summary_dirname）
#    2) 敏感性附表晋升：优先【success】SA_complete_case（可要求 Model2 双库显著）；
#       完整病例失败/不显著时，回退任选一个其它【success】SA_* 进汇总补充表
#    3) Methods_software_versions.txt + Methods_statistical_analysis.md
#    4) Figures 四目录 @ ≥600 dpi
#    5) 交付白名单修剪（R/pub_delivery_prune.R）：根下仅 Figures/Tables/方法md/软件版本txt/中期PDF
###############################################################################

#' 指标根下全部成功敏感性场景目录（【success】SA_*）
incidence_summary_sa_success_dirs <- function(index_root) {
  index_root <- as.character(index_root %||% "")[1L]
  if (!nzchar(index_root) || !dir.exists(index_root)) return(character(0))
  sens <- file.path(index_root, "sensitivity")
  if (!dir.exists(sens)) return(character(0))
  hits <- list.files(
    sens,
    pattern = "^\u3010success\u3011SA_",
    full.names = TRUE
  )
  hits[dir.exists(hits)]
}

#' 解析指标根下成功完整病例敏感性目录
#' @return 目录路径向量（可能为空）
incidence_summary_sa_complete_case_dirs <- function(index_root) {
  hits <- incidence_summary_sa_success_dirs(index_root)
  keep <- grepl(
    "SA_complete_case$|SA_unimputed_cc$",
    basename(hits),
    ignore.case = TRUE
  )
  hits[keep]
}

#' 从场景目录名解析短标签，如 SA_no_Alcohol_drinking
incidence_summary_sa_scenario_label <- function(sa_dir) {
  bn <- basename(as.character(sa_dir %||% "")[1L])
  bn <- sub("^\u3010success\u3011", "", bn)
  bn <- sub("^\u3010failed\u3011", "", bn)
  if (!nzchar(bn)) bn <- "SA_unknown"
  bn
}

#' 展示名：SA_no_Alcohol_drinking → no-Alcohol-drinking
incidence_summary_sa_pretty_label <- function(scenario) {
  sc <- as.character(scenario %||% "")[1L]
  sc <- sub("^SA_", "", sc)
  gsub("_", "-", sc, fixed = TRUE)
}

#' 挑选写入汇总的敏感性目录：完整病例优先，否则任选一个其它成功场景
#'
#' @param require_complete_case_sig TRUE 时完整病例还须 Model2 双库 P&lt;cutoff
#' @return list(dir=, scenario=, role=) 或 NULL
incidence_summary_pick_sa_for_pub <- function(index_root,
                                              require_complete_case_sig = TRUE,
                                              cutoff = 0.05) {
  ok_dirs <- incidence_summary_sa_success_dirs(index_root)
  if (!length(ok_dirs)) return(NULL)

  is_cc <- grepl("SA_complete_case$|SA_unimputed_cc$", basename(ok_dirs), ignore.case = TRUE)
  cc_dirs <- ok_dirs[is_cc]
  other_dirs <- ok_dirs[!is_cc]

  # 1) 完整病例成功目录 +（可选）显著性
  if (length(cc_dirs)) {
    gate <- incidence_complete_case_read_gate(cc_dirs[[1L]])
    ok_sig <- if (isTRUE(require_complete_case_sig)) {
      incidence_complete_case_is_significant(
        gate$p_primary, gate$p_secondary, cutoff
      )
    } else {
      TRUE
    }
    if (isTRUE(ok_sig)) {
      return(list(
        dir = cc_dirs[[1L]],
        scenario = incidence_summary_sa_scenario_label(cc_dirs[[1L]]),
        role = "complete_case",
        p_primary = gate$p_primary,
        p_secondary = gate$p_secondary
      ))
    }
    if (requireNamespace("cli", quietly = TRUE)) {
      cli::cli_alert_info(
        "完整病例未达汇总门槛 (P1={gate$p_primary}; P2={gate$p_secondary})，改选其它成功敏感性"
      )
    }
  } else if (isTRUE(require_complete_case_sig) &&
             requireNamespace("cli", quietly = TRUE)) {
    # 完整病例目录为【failed】时也尝试读 gate 打日志
    fail_cc <- list.files(
      file.path(index_root, "sensitivity"),
      pattern = "^\u3010failed\u3011SA_complete_case$",
      full.names = TRUE
    )
    if (length(fail_cc)) {
      gate <- incidence_complete_case_read_gate(fail_cc[[1L]])
      cli::cli_alert_info(
        "完整病例敏感性失败 (P1={gate$p_primary}; P2={gate$p_secondary})，改选其它成功敏感性"
      )
    }
  }

  if (!length(other_dirs)) return(NULL)

  # 2) 稳定优先序：排除合并症 → 年龄分层 → 其余按名
  pref <- c(
    "SA_no_Alcohol_drinking", "SA_no_Diabetes", "SA_no_Hypertension",
    "SA_no_Smoke", "SA_no_Smoking", "SA_age_lt_65", "SA_age_ge_65"
  )
  labs <- vapply(other_dirs, incidence_summary_sa_scenario_label, character(1L))
  ord <- order(
    match(labs, pref, nomatch = 999L),
    labs
  )
  pick <- other_dirs[[ord[[1L]]]]
  list(
    dir = pick,
    scenario = incidence_summary_sa_scenario_label(pick),
    role = "fallback_success_sa",
    p_primary = NA_real_,
    p_secondary = NA_real_
  )
}

#' 完整病例是否达到附表门槛：Model 2 主比较 P < cutoff（双库则两侧都要）
#' 仅有敏感性目录【success】不够：complete case 的 success 不强制 Model 2。
incidence_complete_case_is_significant <- function(p_primary,
                                                   p_secondary = NULL,
                                                   cutoff = 0.05) {
  cutoff <- suppressWarnings(as.numeric(cutoff)[1L])
  if (!is.finite(cutoff)) cutoff <- 0.05
  p1 <- suppressWarnings(as.numeric(p_primary)[1L])
  if (!is.finite(p1) || p1 >= cutoff) return(FALSE)
  p2 <- suppressWarnings(as.numeric(p_secondary)[1L])
  if (is.finite(p2) && p2 >= cutoff) return(FALSE)
  TRUE
}

incidence_complete_case_read_gate <- function(sens_dir) {
  path <- file.path(sens_dir, "complete_case_gate.txt")
  if (!file.exists(path)) return(list(p_primary = NA_real_, p_secondary = NA_real_, status = ""))
  ln <- readLines(path, warn = FALSE)
  grab <- function(key) {
    hit <- grep(paste0("^", key, "="), ln, value = TRUE)
    if (!length(hit)) return(NA_real_)
    suppressWarnings(as.numeric(sub(paste0("^", key, "="), "", hit[[1L]])))
  }
  st <- grep("^status=", ln, value = TRUE)
  list(
    p_primary = grab("p_primary"),
    p_secondary = grab("p_secondary"),
    status = if (length(st)) sub("^status=", "", st[[1L]]) else ""
  )
}

#' 收集某一敏感性成功目录下的发表 xlsx（基线 / 关联优先）
incidence_summary_collect_sa_dir_tables <- function(sa_dir) {
  sa_dir <- as.character(sa_dir %||% "")[1L]
  if (!nzchar(sa_dir) || !dir.exists(sa_dir)) return(character(0))
  cands <- c(
    list.files(file.path(sa_dir, "Tables"), pattern = "\\.xlsx$", full.names = TRUE),
    list.files(file.path(sa_dir, "NHANES", "Tables"), pattern = "\\.xlsx$", full.names = TRUE),
    list.files(file.path(sa_dir, "MIMIC", "Tables"), pattern = "\\.xlsx$", full.names = TRUE),
    list.files(file.path(sa_dir, "CHARLS", "Tables"), pattern = "\\.xlsx$", full.names = TRUE)
  )
  cands <- unique(cands[file.exists(cands)])
  prefer <- cands[grepl(
    "Baseline|Association|complete.?case|SA-|Logistic|Cox",
    basename(cands),
    ignore.case = TRUE
  )]
  if (length(prefer)) prefer else cands
}

#' 收集完整病例成功补充表（xlsx）
incidence_summary_collect_sa_complete_case_tables <- function(index_root) {
  dirs <- incidence_summary_sa_complete_case_dirs(index_root)
  unique(unlist(lapply(dirs, incidence_summary_collect_sa_dir_tables), use.names = FALSE))
}

#' 把指定敏感性目录的基线+关联表晋升到指标 Tables（双库同 S 号）
incidence_promote_sa_dir_tables <- function(index_root, sa_dir, scenario = NULL) {
  index_root <- as.character(index_root %||% "")[1L]
  sa_dir <- as.character(sa_dir %||% "")[1L]
  if (!nzchar(index_root) || !dir.exists(index_root)) return(invisible(FALSE))
  if (!nzchar(sa_dir) || !dir.exists(sa_dir)) return(invisible(FALSE))
  scenario <- scenario %||% incidence_summary_sa_scenario_label(sa_dir)
  pretty <- incidence_summary_sa_pretty_label(scenario)
  is_cc <- grepl("complete_case|unimputed_cc", scenario, ignore.case = TRUE)

  tab_dir <- file.path(index_root, "Tables")
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
  # 仅匹配本入口写出的命名，勿命中主分析「Sensitivity analysis Unweighted…」
  already <- list.files(
    tab_dir,
    pattern = "Complete-case (baseline|logistic)|Sensitivity [A-Za-z0-9-]+ (baseline|association)",
    ignore.case = TRUE
  )
  if (length(already) >= 2L) return(invisible(TRUE))

  srcs <- incidence_summary_collect_sa_dir_tables(sa_dir)
  if (!length(srcs)) return(invisible(FALSE))
  .db_tag <- function(bn) {
    m <- regmatches(bn, regexec("^Table\\s+S?[A-Za-z0-9.-]*-([A-Za-z0-9]+)\\.", bn, perl = TRUE))[[1L]]
    if (length(m) >= 2L) return(toupper(m[[2L]]))
    if (grepl("NHANES", bn, ignore.case = TRUE)) return("NHANES")
    if (grepl("CHARLS", bn, ignore.case = TRUE)) return("CHARLS")
    if (grepl("MIMIC", bn, ignore.case = TRUE)) return("MIMIC")
    "NHANES"
  }
  base_src <- srcs[grepl("Baseline|baseline", basename(srcs))]
  assoc_src <- srcs[grepl(
    "Association|association|Logistic|Cox",
    basename(srcs),
    ignore.case = TRUE
  )]
  if (!length(base_src) || !length(assoc_src)) return(invisible(FALSE))

  nums <- as.integer(unlist(regmatches(
    list.files(tab_dir, pattern = "Table S[0-9]+"),
    gregexpr("(?<=Table S)\\d+", list.files(tab_dir, pattern = "Table S[0-9]+"), perl = TRUE)
  )))
  n_base <- if (length(nums) && any(is.finite(nums))) max(nums, na.rm = TRUE) + 1L else 12L
  n_assoc <- n_base + 1L
  db_order <- unique(c(
    vapply(basename(base_src), .db_tag, character(1L)),
    vapply(basename(assoc_src), .db_tag, character(1L))
  ))
  pairs <- list()
  for (db in db_order) {
    b <- base_src[toupper(vapply(basename(base_src), .db_tag, character(1L))) == db]
    a <- assoc_src[toupper(vapply(basename(assoc_src), .db_tag, character(1L))) == db]
    if (length(b)) {
      stem <- if (isTRUE(is_cc)) {
        sprintf("Table S%d-%s. Complete-case baseline characteristics", n_base, db)
      } else {
        sprintf("Table S%d-%s. Sensitivity %s baseline", n_base, db, pretty)
      }
      pairs[[length(pairs) + 1L]] <- list(src = b[[1L]], stem = stem)
    }
    if (length(a)) {
      stem <- if (isTRUE(is_cc)) {
        sprintf("Table S%d-%s. Complete-case logistic regression", n_assoc, db)
      } else {
        sprintf("Table S%d-%s. Sensitivity %s association", n_assoc, db, pretty)
      }
      pairs[[length(pairs) + 1L]] <- list(src = a[[1L]], stem = stem)
    }
  }
  if (!length(pairs)) return(invisible(FALSE))
  for (pr in pairs) {
    dst <- file.path(tab_dir, paste0(pr$stem, ".xlsx"))
    file.copy(pr$src, dst, overwrite = TRUE)
    a1 <- tryCatch(
      as.character(openxlsx::read.xlsx(dst, colNames = FALSE)[1, 1]),
      error = function(e) ""
    )
    if (nzchar(a1) && exists("pub_xlsx_edit_cells", mode = "function")) {
      a1n <- sub("^Table S[0-9]+-[A-Za-z0-9]+", sub("\\..*$", "", pr$stem), a1)
      if (!identical(a1n, a1)) {
        tryCatch(
          pub_xlsx_edit_cells(dst, data.frame(row = 1L, col = 1L, value = a1n)),
          error = function(e) NULL
        )
      }
    }
  }
  if (requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_success(
      "敏感性附表已晋升 ({scenario}) → {basename(index_root)}/Tables S{n_base}/S{n_assoc} × {length(db_order)} 库"
    )
  }
  invisible(TRUE)
}

#' 汇总用敏感性附表晋升：完整病例优先，否则回退任一成功 SA
#'
#' @param require_model2_sig 仅约束完整病例是否须 Model2 双库显著；
#'   回退成功场景不再次卡显著性（场景本身已过 sensitivity suite 闸门）。
#' @return TRUE 表示已有或刚写入敏感性附表
incidence_promote_sensitivity_for_summary <- function(index_root,
                                                      require_model2_sig = TRUE,
                                                      cutoff = 0.05) {
  index_root <- as.character(index_root %||% "")[1L]
  if (!nzchar(index_root) || !dir.exists(index_root)) return(invisible(FALSE))
  tab_dir <- file.path(index_root, "Tables")
  already <- list.files(
    tab_dir,
    pattern = "Complete-case (baseline|logistic)|Sensitivity [A-Za-z0-9-]+ (baseline|association)",
    ignore.case = TRUE
  )
  if (length(already) >= 2L) return(invisible(TRUE))

  pick <- incidence_summary_pick_sa_for_pub(
    index_root,
    require_complete_case_sig = isTRUE(require_model2_sig),
    cutoff = cutoff
  )
  if (is.null(pick)) {
    if (requireNamespace("cli", quietly = TRUE)) {
      cli::cli_alert_info(
        "无可用成功敏感性场景，跳过附表晋升: {basename(index_root)}"
      )
    }
    return(invisible(FALSE))
  }
  incidence_promote_sa_dir_tables(index_root, pick$dir, scenario = pick$scenario)
}

#' 完整病例表拷入指标 Tables（兼容旧入口；内部走敏感性晋升）
#'
#' @param require_model2_sig TRUE 时完整病例须 Model2 双库显著；失败则回退其它成功 SA
#' @return TRUE 表示指标 Tables 里已有（或刚写入）敏感性附表
incidence_promote_sig_complete_case <- function(index_root,
                                                p_primary = NULL,
                                                p_secondary = NULL,
                                                cutoff = 0.05,
                                                require_model2_sig = FALSE) {
  # p_primary/p_secondary 保留兼容；挑选逻辑统一走 pick_sa_for_pub
  invisible(incidence_promote_sensitivity_for_summary(
    index_root,
    require_model2_sig = isTRUE(require_model2_sig),
    cutoff = cutoff
  ))
}

#' 定位 success 指标发表 Tables/Figures 源
incidence_summary_resolve_pub_sources <- function(index_root, db_seq = character(0)) {
  index_root <- as.character(index_root)[1L]
  tab_src <- character(0)
  fig_src <- NULL
  root_tab <- file.path(index_root, "Tables")
  root_fig <- file.path(index_root, "Figures")
  if (dir.exists(root_tab) &&
      length(list.files(root_tab, pattern = "\\.(xlsx|csv)$"))) {
    tab_src <- list.files(root_tab, pattern = "\\.(xlsx|csv)$", full.names = TRUE)
  }
  if (dir.exists(root_fig) &&
      dir.exists(file.path(root_fig, "pdf")) &&
      length(list.files(file.path(root_fig, "pdf"), pattern = "^Figure"))) {
    fig_src <- root_fig
  }
  # 单库未镜像到指标根：回退 NHANES/MIMIC/CHARLS 槽
  if (!length(tab_src) || is.null(fig_src)) {
    slots <- unique(c(
      as.character(db_seq),
      "NHANES", "MIMIC", "CHARLS", "eICU", "ELSA"
    ))
    for (sl in slots) {
      if (!nzchar(sl)) next
      td <- file.path(index_root, sl, "Tables")
      fd <- file.path(index_root, sl, "Figures")
      if (!length(tab_src) && dir.exists(td)) {
        fs <- list.files(td, pattern = "\\.(xlsx|csv)$", full.names = TRUE)
        if (length(fs)) tab_src <- fs
      }
      if (is.null(fig_src) && dir.exists(fd) &&
          dir.exists(file.path(fd, "pdf"))) {
        if (length(list.files(file.path(fd, "pdf"), pattern = "^Figure"))) {
          fig_src <- fd
        }
      }
    }
  }
  list(tables = unique(tab_src), figures = fig_src)
}

#' 发病/预后课题 summary_result 收口
#'
#' @param project_root 课题产出根
#' @param config 可选
#' @param index 可选指标名；NULL=全部【success】
#' @param methods_lines 可选 Methods_statistical_analysis.md 正文
#' @param include_sa_complete_case 默认 TRUE
incidence_finalize_summary_result <- function(project_root,
                                              config = NULL,
                                              index = NULL,
                                              methods_lines = NULL,
                                              readme_lines = NULL,
                                              include_sa_complete_case = TRUE,
                                              extra_pkgs = c(
                                                "survey", "forestploter", "rms",
                                                "pROC", "mediation", "tableone"
                                              ),
                                              software_roles = NULL,
                                              summary_dirname = NULL,
                                              tables_figures_only = FALSE) {
  project_root <- as.character(project_root)[1L]
  stopifnot(dir.exists(project_root))
  if (!requireNamespace("cli", quietly = TRUE)) stop("need cli", call. = FALSE)

  by_ix <- file.path(project_root, "by_index")
  success_dirs <- character(0)
  if (dir.exists(by_ix)) {
    all_ok <- list.files(by_ix, pattern = "^\u3010success\u3011", full.names = TRUE)
    if (!is.null(index) && nzchar(as.character(index)[1L])) {
      ix <- as.character(index)[1L]
      want <- file.path(by_ix, paste0("\u3010success\u3011", ix))
      success_dirs <- all_ok[basename(all_ok) == paste0("\u3010success\u3011", ix) |
                               grepl(paste0("\u3010success\u3011", ix, "$"), all_ok)]
      if (!length(success_dirs) && dir.exists(want)) success_dirs <- want
    } else {
      success_dirs <- all_ok
    }
  }
  if (!length(success_dirs)) {
    cli::cli_alert_warning("incidence_finalize_summary_result: 无【success】指标，跳过")
    return(invisible(list(ok = FALSE, summary_root = NA_character_)))
  }

  sum_name <- as.character(
    summary_dirname %||%
      (config$pub %||% list())$summary_dirname %||%
      "summary_result"
  )[1L]
  if (!nzchar(sum_name)) sum_name <- "summary_result"
  sum_root <- file.path(project_root, sum_name)
  tab_dir <- file.path(sum_root, "Tables")
  fig_dir <- file.path(sum_root, "Figures")
  for (d in c(sum_root, tab_dir, fig_dir)) {
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
  }

  # 多指标时后写覆盖同名；单指标课题为主场景
  all_tabs <- character(0)
  fig_src_use <- NULL
  sa_n <- 0L
  # 完整病例默认要求显著才优先；不显著则引擎回退其它【success】SA_*
  require_sig <- isTRUE(
    (config$pub %||% list())$sa_complete_case_require_sig %||% TRUE
  )
  for (ix_root in success_dirs) {
    if (isTRUE(include_sa_complete_case)) {
      tryCatch(
        incidence_promote_sensitivity_for_summary(
          ix_root, require_model2_sig = require_sig
        ),
        error = function(e) cli::cli_alert_warning("敏感性附表晋升跳过: {e$message}")
      )
      promoted <- list.files(
        file.path(ix_root, "Tables"),
        pattern = "Complete-case (baseline|logistic)|Sensitivity [A-Za-z0-9-]+ (baseline|association)",
        ignore.case = TRUE,
        full.names = TRUE
      )
      if (length(promoted)) {
        sa_n <- sa_n + length(promoted)
        cli::cli_alert_success(
          "敏感性附表已在指标 Tables（{length(promoted)}）: {basename(ix_root)}"
        )
      }
    }
    # 晋升后再收集，确保 Complete-case 表进入 summary_result/Tables
    src <- incidence_summary_resolve_pub_sources(ix_root)
    all_tabs <- c(all_tabs, src$tables)
    if (!is.null(src$figures)) fig_src_use <- src$figures
  }
  all_tabs <- unique(all_tabs[file.exists(all_tabs)])

  # 清空后按 basename 去重（新者优先）
  old_tabs <- list.files(tab_dir, full.names = TRUE)
  if (length(old_tabs)) unlink(old_tabs)
  by_bn <- split(all_tabs, basename(all_tabs))
  for (bn in names(by_bn)) {
    paths <- by_bn[[bn]]
    paths <- paths[order(file.info(paths)$mtime, decreasing = TRUE)]
    file.copy(paths[[1L]], file.path(tab_dir, bn), overwrite = TRUE)
  }
  cli::cli_alert_success(
    "Tables -> {tab_dir} ({length(list.files(tab_dir))} files; SA_complete_case={sa_n})"
  )

  # 交付前 strip：清悬空 drawing / 未声明 ns1 前缀，保证 openpyxl/中期 inspect 可读
  if (!exists("pub_xlsx_strip", mode = "function")) {
    sx <- c(
      file.path(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""), "R", "pub_xlsx_surgical.R"),
      file.path(getwd(), "R", "pub_xlsx_surgical.R")
    )
    sx <- sx[nzchar(sx) & file.exists(sx)]
    if (length(sx)) source(sx[[1L]], local = FALSE)
  }
  if (exists("pub_xlsx_strip", mode = "function")) {
    for (xp in list.files(tab_dir, pattern = "\\.xlsx$", full.names = TRUE)) {
      tryCatch(pub_xlsx_strip(xp), error = function(e) {
        cli::cli_alert_warning("xlsx strip 跳过 {basename(xp)}: {e$message}")
      })
    }
  }

  if (is.null(fig_src_use) || !dir.exists(fig_src_use)) {
    cli::cli_alert_warning("summary_result: 未找到 Figures 源目录")
  } else {
    for (sub in c("pdf", "png", "tiff", "image_information")) {
      d <- file.path(fig_dir, sub)
      if (dir.exists(d)) unlink(list.files(d, full.names = TRUE), recursive = TRUE)
      dir.create(d, recursive = TRUE, showWarnings = FALSE)
      src_sub <- file.path(fig_src_use, sub)
      if (!dir.exists(src_sub)) next
      fs <- list.files(src_sub, full.names = TRUE)
      if (length(fs)) file.copy(fs, d, overwrite = TRUE)
    }
    # 去掉 Figures 根平铺残留
    flat <- list.files(fig_dir, pattern = "^Figure.*\\.(pdf|png|tiff)$", full.names = TRUE)
    if (length(flat)) unlink(flat)
    if (exists("pub_figure_ensure_formats", mode = "function")) {
      pub_figure_ensure_formats(fig_dir, config = config %||% list())
    }
  }

  st <- if (exists("pub_figure_formats_status", mode = "function") &&
            dir.exists(file.path(fig_dir, "pdf"))) {
    pub_figure_formats_status(fig_dir)
  } else {
    list(ok = NA)
  }
  cli::cli_alert_info(
    "Figures four-format ok={isTRUE(st$ok)}; n_pdf={length(list.files(file.path(fig_dir,'pdf')))}"
  )

  # tables_figures_only：交付根只留 Figures/ + Tables/（不写 Methods / 软件版本）
  if (!isTRUE(tables_figures_only)) {
    if (exists("pub_write_software_versions", mode = "function")) {
      pub_write_software_versions(
        index_root = sum_root,
        project_root = project_root,
        config = config %||% list(software_versions = list(extra_pkgs = extra_pkgs))
      )
    }
    if (is.null(methods_lines) || !length(methods_lines)) {
      if (!exists("pub_default_methods_lines", mode = "function")) {
        sv <- c(
          if (nzchar(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""))) {
            file.path(Sys.getenv("MEDICAL_BLOCKS_ROOT"), "R", "pub_software_versions.R")
          } else character(0),
          file.path(getwd(), "R", "pub_software_versions.R")
        )
        sv <- sv[file.exists(sv)]
        if (length(sv)) source(sv[[1L]], local = FALSE)
      }
      if (exists("pub_default_methods_lines", mode = "function")) {
        methods_lines <- pub_default_methods_lines(config)
      }
    }
    methods_path <- file.path(sum_root, "Methods_statistical_analysis.md")
    if (!is.null(methods_lines) && length(methods_lines)) {
      writeLines(methods_lines, methods_path, useBytes = TRUE)
    }
    if (exists("pub_write_methods_software_section", mode = "function") &&
        file.exists(methods_path)) {
      roles <- software_roles %||% c(
        survey = "NHANES complex survey / weighted logistic",
        mice = "Multiple imputation",
        rms = "Restricted cubic splines",
        car = "Variance inflation factors",
        forestploter = "Subgroup forest",
        pROC = "ROC / AUC",
        mediation = "Mediation analysis",
        ggplot2 = "Publication figures",
        openxlsx = "SCI three-line xlsx"
      )
      soft_tmp <- tempfile(fileext = ".md")
      tryCatch(
        pub_write_methods_software_section(
          out_path = soft_tmp, roles = roles, extra_pkgs = extra_pkgs,
          append_to = methods_path
        ),
        error = function(e) NULL
      )
      if (file.exists(soft_tmp)) unlink(soft_tmp)
      sec <- file.path(sum_root, "Methods_software_section.md")
      if (file.exists(sec)) unlink(sec)
    }

    if (!exists("pub_prune_delivery_root", mode = "function")) {
      pr <- c(
        file.path(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""), "R", "pub_delivery_prune.R"),
        file.path(getwd(), "R", "pub_delivery_prune.R")
      )
      pr <- pr[nzchar(pr) & file.exists(pr)]
      if (length(pr)) source(pr[[1L]], local = FALSE)
    }
    if (exists("pub_prune_delivery_root", mode = "function")) {
      pub_prune_delivery_root(sum_root)
    }
  } else {
    # 清掉非 Figures/Tables 残留
    keep <- c("Figures", "Tables")
    for (nm in list.files(sum_root)) {
      if (!nm %in% keep) {
        unlink(file.path(sum_root, nm), recursive = TRUE)
      }
    }
    cli::cli_alert_info("summary_results 仅保留 Figures/ + Tables/")
  }

  invisible(list(
    ok = isTRUE(st$ok),
    summary_root = sum_root,
    n_tables = length(list.files(tab_dir)),
    n_sa_complete_case = sa_n,
    status = st
  ))
}
