# =============================================================================
#  成功指标目录下生成可改协变量 / 可单步重跑的 code 包（全项目）
#  落盘：by_index/【success】<INDEX>/code/
# =============================================================================

#' 从 checkpoint 读取锁定协变量（优先 cox_final / Model2 / Model1）
.index_code_bundle_locked_covs <- function(project_root, ix, config, db_seq) {
  out <- list(model1 = character(0), model2 = character(0),
              cox_final = character(0), mediation_covs = character(0),
              best_mediator = NA_character_,
              path_use_covariates = NA)
  # 课题 config：中介路径是否加协变量（FALSE = crude）
  for (nm in c("mediation_nhanes_weighted", "mediation_incidence",
               "mediation_prognosis")) {
    blk <- (config %||% list())[[nm]]
    if (!is.null(blk) && !is.null(blk$path_use_covariates)) {
      out$path_use_covariates <- isTRUE(blk$path_use_covariates)
      break
    }
  }
  if (is.na(out$path_use_covariates)) {
    pol <- (config %||% list())$mediation_policy %||% list()
    if (!is.null(pol$path_use_covariates)) {
      out$path_use_covariates <- isTRUE(pol$path_use_covariates)
    }
  }
  for (db in db_seq) {
    dbn <- if (exists("dual_db_slot_path_name", mode = "function")) {
      tryCatch(dual_db_slot_path_name(config, db), error = function(e) db)
    } else db
    ck_dir <- file.path(project_root, "checkpoints", "by_index", ix, dbn)
    if (!dir.exists(ck_dir)) next
    for (bn in c("cox_quartile.rds", "cox_tertile.rds", "cox_binary.rds",
                 "dual_db_covariate_harmonize.rds",
                 "multivariate_prognosis_harmonized.rds",
                 "multivariate_incidence_harmonized.rds",
                 "multicollinearity_final.rds")) {
      p <- file.path(ck_dir, bn)
      if (!file.exists(p)) next
      obj <- tryCatch(readRDS(p), error = function(e) NULL)
      res <- obj$ctx$results %||% list()
      if (!length(out$model1)) {
        out$model1 <- as.character(res$Model1Factors %||% character(0))
      }
      if (!length(out$model2)) {
        out$model2 <- as.character(res$Model2Factors %||% character(0))
      }
      if (!length(out$cox_final)) {
        out$cox_final <- as.character(res$cox_final_factors %||% character(0))
      }
    }
    med_p <- file.path(ck_dir, "mediation_prognosis.rds")
    if (!file.exists(med_p)) med_p <- file.path(ck_dir, "mediation_incidence.rds")
    if (!file.exists(med_p)) med_p <- file.path(ck_dir, "mediation_nhanes_weighted.rds")
    if (file.exists(med_p)) {
      obj <- tryCatch(readRDS(med_p), error = function(e) NULL)
      res <- obj$ctx$results %||% list()
      if (!length(out$mediation_covs)) {
        # 路径协变量通常等于锁定多因素（已剔除中介候选）
        out$mediation_covs <- as.character(
          res$mediation_prognosis_auto_covariates %||%
            res$mediation_path_covariates %||%
            res$Model2Factors %||% out$model2
        )
      }
      if (!nzchar(as.character(out$best_mediator %||% "")[1L])) {
        out$best_mediator <- as.character(
          res$mediation_best_mediator %||%
            res$best_mediator %||% NA_character_
        )[1L]
      }
    }
  }
  pref <- file.path(project_root, "checkpoints", "by_index", ix,
                    "harmonization", "preferred_mediator.rds")
  if (file.exists(pref)) {
    pr <- tryCatch(readRDS(pref), error = function(e) NULL)
    out$best_mediator <- as.character(pr$mediator %||% NA_character_)[1L]
  }
  # 未在 config 显式声明时：有路径协变量则视为开启（兼容旧课题）
  if (is.na(out$path_use_covariates)) {
    out$path_use_covariates <- length(out$mediation_covs) > 0L ||
      length(out$model2) > 0L
  }
  out$model1 <- unique(out$model1[nzchar(out$model1)])
  out$model2 <- unique(out$model2[nzchar(out$model2)])
  out$cox_final <- unique(out$cox_final[nzchar(out$cox_final)])
  out$mediation_covs <- unique(out$mediation_covs[nzchar(out$mediation_covs)])
  out
}

.index_code_bundle_quote_chr <- function(x) {
  x <- as.character(x %||% character(0))
  x <- x[nzchar(x)]
  if (!length(x)) return("character(0)")
  paste0("c(", paste(sprintf('"%s"', gsub('"', '\\"', x, fixed = TRUE)), collapse = ", "), ")")
}

.index_code_bundle_quote_num <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  x <- x[is.finite(x)]
  if (!length(x)) return("NULL")
  paste0("c(", paste(format(x, scientific = FALSE, trim = TRUE), collapse = ", "), ")")
}

.index_code_bundle_quote_scalar <- function(x, default = "NULL") {
  x <- suppressWarnings(as.numeric(x)[1L])
  if (!is.finite(x)) return(default)
  format(x, scientific = FALSE, trim = TRUE)
}

#' 从 checkpoint / 指标 step 目录推断本指标实际跑过的 block（发病/预后共用）
.index_code_bundle_used_blocks <- function(project_root, index_root, ix, config,
                                           db_seq, pipeline_blks = character(0)) {
  used <- character(0)
  .add_names <- function(x) {
    x <- as.character(x %||% character(0))
    x <- gsub("\\.rds$", "", x)
    x <- gsub("^step\\d+_", "", x)
    x <- x[nzchar(x)]
    x <- x[!grepl("^(harmonization|preferred_mediator)$", x, ignore.case = TRUE)]
    used <<- c(used, x)
  }
  for (db in db_seq) {
    dbn <- if (exists("dual_db_slot_path_name", mode = "function")) {
      tryCatch(dual_db_slot_path_name(config, db), error = function(e) db)
    } else db
    ck_dir <- file.path(project_root, "checkpoints", "by_index", ix, dbn)
    if (dir.exists(ck_dir)) {
      .add_names(list.files(ck_dir, pattern = "\\.rds$", full.names = FALSE))
    }
    # 指标输出 stepNN_<block>/ 目录（无 ck 时的兜底）
    step_root <- file.path(index_root, dbn)
    if (dir.exists(step_root)) {
      dirs <- list.dirs(step_root, full.names = FALSE, recursive = FALSE)
      .add_names(dirs[grepl("^step\\d+_", dirs)])
    }
  }
  used <- unique(used)
  pipe <- as.character(pipeline_blks %||% character(0))
  pipe <- pipe[nzchar(pipe)]
  if (length(used)) {
    ordered <- intersect(pipe, used)
    extra <- setdiff(used, ordered)
    return(c(ordered, sort(extra)))
  }
  # 无证据时退回整条 pipeline（仍会拷贝，避免空包）
  pipe
}

#' 把使用过的 block 源码（及同目录 00*common）拷进 code/blocks/
.index_code_bundle_copy_block_sources <- function(code_dir, engine_root, used_blocks) {
  engine_root <- normalizePath(as.character(engine_root)[1L], winslash = "/", mustWork = FALSE)
  used_blocks <- unique(as.character(used_blocks %||% character(0)))
  used_blocks <- used_blocks[nzchar(used_blocks)]
  blocks_out <- file.path(code_dir, "blocks")
  if (dir.exists(blocks_out)) {
    # 只清 Blocks 镜像，保留 MANIFEST
    old <- list.files(blocks_out, recursive = TRUE, full.names = TRUE)
    unlink(old[grepl("/Blocks/|/MANIFEST|/00_common", old)], recursive = TRUE)
  }
  dir.create(blocks_out, recursive = TRUE, showWarnings = FALSE)

  if (!exists("pipeline_block_sources", mode = "function")) {
    pr <- file.path(engine_root, "R", "pipeline_runner.R")
    if (file.exists(pr)) {
      tryCatch(source(pr, local = FALSE), error = function(e) NULL)
    }
  }
  if (!exists("pipeline_block_sources", mode = "function")) {
    writeLines(
      c("# 无法加载 pipeline_block_sources，未拷贝 block 源码",
        paste0("# used: ", paste(used_blocks, collapse = ", "))),
      file.path(blocks_out, "MANIFEST.md")
    )
    return(invisible(character(0)))
  }

  src_map <- tryCatch(pipeline_block_sources(engine_root), error = function(e) list())
  rows <- list()
  copied_files <- character(0)

  .copy_one <- function(src_path, reason) {
    src_path <- normalizePath(src_path, winslash = "/", mustWork = FALSE)
    if (!file.exists(src_path)) return(NA_character_)
    # 相对 engine 的 Blocks/... 路径
    rel <- sub(
      paste0("^", gsub("([.\\])", "\\\\\\1", engine_root), "/?"),
      "",
      src_path
    )
    rel <- gsub("^/+", "", rel)
    if (!grepl("^Blocks/", rel)) {
      rel <- file.path("Blocks", basename(src_path))
    }
    dest <- file.path(blocks_out, rel)
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    ok <- tryCatch(file.copy(src_path, dest, overwrite = TRUE), error = function(e) FALSE)
    if (!isTRUE(ok)) return(NA_character_)
    copied_files <<- c(copied_files, dest)
    rel
  }

  for (bn in used_blocks) {
    if (!bn %in% names(src_map)) {
      rows[[length(rows) + 1L]] <- data.frame(
        block = bn, source_rel = NA_character_, status = "MISSING_MAP",
        stringsAsFactors = FALSE
      )
      next
    }
    src <- src_map[[bn]]
    rel <- .copy_one(src, bn)
    st <- if (is.na(rel)) "COPY_FAIL" else "OK"
    rows[[length(rows) + 1L]] <- data.frame(
      block = bn, source_rel = if (is.na(rel)) as.character(src) else rel, status = st,
      stringsAsFactors = FALSE
    )
    # 同目录公共文件（mediation / logistic common 等）+ 本课题辅助脚本
    # （如 07*_mr.R、09nafld_ext_*.R 被 06* source 引用；非 register_block 文件）
    if (!is.na(rel) && file.exists(src)) {
      sibs <- list.files(dirname(src), pattern = "^[0-9]{2}[a-zA-Z_]*.*\\.[Rr]$|^00", full.names = TRUE)
      sibs <- sibs[
        grepl("\\.[Rr]$", sibs) &
          (grepl("common|shared|logistic|mediation", basename(sibs), ignore.case = TRUE) |
           grepl("^0[6-9][a-zA-Z_0-9]*\\.R$", basename(sibs), ignore.case = TRUE) &
           !grepl("^0[6-9]block_", basename(sibs), ignore.case = TRUE))
      ]
      for (sp in sibs) {
        sp_n <- normalizePath(sp, winslash = "/", mustWork = FALSE)
        already <- normalizePath(copied_files, winslash = "/", mustWork = FALSE)
        if (sp_n %in% already) next
        .copy_one(sp, paste0(bn, "+aux"))
      }
    }
  }

  man <- if (length(rows)) do.call(rbind, rows) else {
    data.frame(block = character(0), source_rel = character(0), status = character(0))
  }
  utils::write.table(
    man, file.path(blocks_out, "MANIFEST.tsv"),
    sep = "\t", row.names = FALSE, quote = FALSE
  )
  md <- c(
    "# 本指标实际使用过的 Block 源码",
    "",
    "本目录从引擎 `Blocks/` 拷贝，便于离线对照四分位/三分位/二分位、Cox/logistic 等实现。",
    "**重跑仍走引擎**（`run.R` → worker），勿直接改这里的副本当生产源。",
    "",
    "| block | 源文件 | 状态 |",
    "|---|---|---|"
  )
  if (nrow(man)) {
    for (i in seq_len(nrow(man))) {
      md <- c(md, sprintf(
        "| `%s` | `%s` | %s |",
        man$block[i],
        ifelse(is.na(man$source_rel[i]), "", man$source_rel[i]),
        man$status[i]
      ))
    }
  } else {
    md <- c(md, "| （空） | | |")
  }
  writeLines(md, file.path(blocks_out, "MANIFEST.md"))
  invisible(man$block[man$status == "OK"])
}

#' 校验指标 code 包是否满足全项目铁律（含 blocks/ 源码镜像）
index_code_bundle_validate <- function(code_dir, min_block_files = 1L) {
  code_dir <- as.character(code_dir)[1L]
  issues <- character(0)
  if (!nzchar(code_dir) || !dir.exists(code_dir)) {
    return(list(ok = FALSE, issues = "code 目录不存在"))
  }
  required_files <- c(
    "README.md", "run.R", "paths.R", "00_config_overrides.R",
    "blocks_menu.txt", "blocks_used.txt"
  )
  for (f in required_files) {
    if (!file.exists(file.path(code_dir, f))) {
      issues <- c(issues, paste0("缺少文件: ", f))
    }
  }
  blocks_dir <- file.path(code_dir, "blocks")
  if (!dir.exists(blocks_dir)) {
    issues <- c(issues, "缺少目录: blocks/")
  } else {
    for (mf in c("MANIFEST.md", "MANIFEST.tsv")) {
      if (!file.exists(file.path(blocks_dir, mf))) {
        issues <- c(issues, paste0("缺少: blocks/", mf))
      }
    }
    r_files <- list.files(blocks_dir, pattern = "\\.[Rr]$", recursive = TRUE, full.names = FALSE)
    n_r <- length(r_files)
    if (n_r < as.integer(min_block_files)[1L]) {
      issues <- c(issues, sprintf("blocks/ 内 .R 文件数 %d < %d", n_r, min_block_files))
    }
    used_path <- file.path(code_dir, "blocks_used.txt")
    if (file.exists(used_path)) {
      bl <- trimws(readLines(used_path, warn = FALSE))
      bl <- bl[nzchar(bl) & !startsWith(bl, "#")]
      ## 多 block 常映射同一 .R（如 multicollinearity_screen/final），
      ## 禁止用「名单长度 > 文件数」误报；只要求有镜像且 used 非空时有文件。
      if (length(bl) && n_r < 1L) {
        issues <- c(issues, "blocks_used.txt 非空但 blocks/ 无 .R 镜像")
      }
    }
  }
  list(ok = !length(issues), issues = issues)
}

#' 指标收尾写 code 包（发病 / 预后 / ML dual-batch 共用；全项目铁律入口）
index_code_bundle_finalize <- function(root, config, ix, db_seq, index_root = NULL) {
  ix <- as.character(ix %||% "")[1L]
  db_seq <- unique(as.character(db_seq[nzchar(as.character(db_seq))]))
  if (!length(db_seq) || !nzchar(ix)) return(invisible(FALSE))

  if (is.null(index_root) || !nzchar(as.character(index_root)[1L])) {
    if (!exists("incidence_batch_index_output_root", mode = "function")) {
      return(invisible(FALSE))
    }
    index_root <- incidence_batch_index_output_root(config, ix)
    if (!exists("is_absolute_path", mode = "function") ||
        !is_absolute_path(index_root)) {
      index_root <- file.path(root, index_root)
    }
  }
  index_root <- normalizePath(as.character(index_root)[1L], winslash = "/", mustWork = FALSE)
  if (grepl("sensitivity|\\.sensitivity_staging", index_root, ignore.case = TRUE)) {
    return(invisible(FALSE))
  }
  if (!dir.exists(index_root)) return(invisible(FALSE))

  tryCatch({
    eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
    if (!nzchar(eng)) eng <- root
    cb_src <- file.path(eng, "R", "index_code_bundle.R")
    if (!file.exists(cb_src)) cb_src <- file.path(root, "R", "index_code_bundle.R")
    if (file.exists(cb_src) && !exists("index_code_bundle_write", mode = "function")) {
      source(cb_src, local = FALSE)
    }
    if (!exists("index_code_bundle_write", mode = "function")) {
      if (requireNamespace("cli", quietly = TRUE)) {
        cli::cli_alert_warning("指标 code 包: 找不到 index_code_bundle_write")
      }
      return(invisible(FALSE))
    }
    proj_root <- as.character(
      (config$survival_batch %||% config$incidence_batch %||% list())$output_base %||%
        config$project$output_dir %||% root
    )[1L]
    ok <- index_code_bundle_write(
      index_root = index_root,
      project_root = proj_root,
      ix = ix,
      config = config,
      engine_root = eng,
      db_seq = db_seq
    )
    if (!isTRUE(ok)) {
      if (requireNamespace("cli", quietly = TRUE)) {
        cli::cli_alert_warning("指标 code 包生成失败")
      }
      return(invisible(FALSE))
    }
    val <- index_code_bundle_validate(file.path(index_root, "code"))
    if (!isTRUE(val$ok)) {
      if (requireNamespace("cli", quietly = TRUE)) {
        cli::cli_alert_warning(
          "指标 code 包校验未通过（全项目铁律）: {paste(val$issues, collapse = '; ')}"
        )
      }
      return(invisible(FALSE))
    }
    if (requireNamespace("cli", quietly = TRUE)) {
      cli::cli_alert_success("指标 code 包校验通过（含 blocks/ 源码镜像）")
    }
    invisible(TRUE)
  }, error = function(e) {
    if (requireNamespace("cli", quietly = TRUE)) {
      cli::cli_alert_warning("指标 code 包生成异常: {e$message}")
    }
    invisible(FALSE)
  })
}

#' 森林图 / 亚组可改设置（config + checkpoint）
.index_code_bundle_forest_settings <- function(project_root, ix, config, db_seq) {
  sg <- utils::modifyList(
    config$subgroup %||% list(),
    config$subgroup_prognosis %||% config$subgroup_incidence %||%
      config$subgroup_nhanes_weighted %||% list()
  )
  out <- list(
    vars = as.character(
      sg$locked_subgroup_vars %||% sg$required_subgroup_vars %||% sg$vars %||% character(0)
    ),
    forbid = as.character(sg$forbid_subgroup_vars %||% sg$exclude_subgroup_vars %||% character(0)),
    age_cutoff = suppressWarnings(as.numeric(sg$age_cutoff %||% 65)[1L]),
    min_n = suppressWarnings(as.numeric(sg$min_n %||% 20)[1L]),
    forest_xlim = suppressWarnings(as.numeric(sg$forest_xlim %||% c(0.2, 4))),
    forest_ticks_at = suppressWarnings(as.numeric(sg$forest_ticks_at %||% numeric(0))),
    forest_xlim_max = suppressWarnings(as.numeric(sg$forest_xlim_max %||% 80)[1L]),
    forest_base_size = suppressWarnings(as.numeric(sg$forest_base_size %||% 9)[1L]),
    forest_x_trans = as.character(sg$forest_x_trans %||% "log")[1L],
    forest_n_source = as.character(sg$forest_n_source %||% "full_stratum")[1L],
    continuous_index_mode = as.character(sg$continuous_index_mode %||% "highest_vs_lowest")[1L],
    adjust_covariates = as.character(sg$adjust_covariates %||% character(0))
  )
  # checkpoint 实际用过的亚组优先
  for (db in db_seq) {
    dbn <- if (exists("dual_db_slot_path_name", mode = "function")) {
      tryCatch(dual_db_slot_path_name(config, db), error = function(e) db)
    } else db
    for (bn in c("subgroup_prognosis.rds", "subgroup_incidence.rds",
                 "subgroup_nhanes_weighted.rds")) {
      p <- file.path(project_root, "checkpoints", "by_index", ix, dbn, bn)
      if (!file.exists(p)) next
      obj <- tryCatch(readRDS(p), error = function(e) NULL)
      res <- obj$ctx$results %||% list()
      used <- as.character(res$subgroup_vars_used %||% character(0))
      used <- unique(used[nzchar(used)])
      cfg_req <- unique(as.character(
        sg$required_subgroup_vars %||% sg$locked_subgroup_vars %||% character(0)
      ))
      cfg_req <- cfg_req[nzchar(cfg_req)]
      # 勿把 min_n 过滤后的短名单写进 overrides（否则下次重跑永久丢失 Age 等）
      if (length(cfg_req) && length(used) &&
          all(used %in% cfg_req) && length(used) < length(cfg_req)) {
        out$vars <- cfg_req
        break
      }
      if (length(used)) {
        out$vars <- used
        break
      }
      ck_sg <- obj$ctx$config$subgroup %||% list()
      lock <- as.character(
        ck_sg$locked_subgroup_vars %||% ck_sg$required_subgroup_vars %||% character(0)
      )
      if (length(lock)) {
        out$vars <- lock
        if (is.finite(suppressWarnings(as.numeric(ck_sg$age_cutoff)[1L])))
          out$age_cutoff <- as.numeric(ck_sg$age_cutoff)[1L]
        if (is.finite(suppressWarnings(as.numeric(ck_sg$min_n)[1L])))
          out$min_n <- as.numeric(ck_sg$min_n)[1L]
        break
      }
    }
    if (length(out$vars)) break
  }
  out$vars <- unique(out$vars[nzchar(out$vars)])
  out$forbid <- unique(out$forbid[nzchar(out$forbid)])
  if (!length(out$forest_xlim) || !all(is.finite(out$forest_xlim))) {
    out$forest_xlim <- c(0.2, 4)
  }
  out
}

#' 写出指标 code 包
#' @param index_root 指标输出根（可为 by_index/ALBI 或 【success】ALBI）
#' @param project_root 课题根（含 config.R / checkpoints）
#' @param engine_root MEDICAL_BLOCKS_ROOT
index_code_bundle_write <- function(index_root, project_root, ix, config,
                                    engine_root = NULL, db_seq = NULL) {
  index_root <- normalizePath(as.character(index_root)[1L], winslash = "/", mustWork = FALSE)
  project_root <- normalizePath(as.character(project_root)[1L], winslash = "/", mustWork = FALSE)
  ix <- as.character(ix %||% "")[1L]
  if (!nzchar(index_root) || !dir.exists(index_root) || !nzchar(ix)) {
    return(invisible(FALSE))
  }
  # 敏感性 / staging 不写
  if (grepl("sensitivity|\\.sensitivity_staging", index_root, ignore.case = TRUE)) {
    return(invisible(FALSE))
  }
  engine_root <- as.character(
    engine_root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "") %||% ""
  )[1L]
  if (!nzchar(engine_root)) engine_root <- project_root

  if (is.null(db_seq) || !length(db_seq)) {
    db_seq <- c("nhanes", "mimic")
  }
  db_seq <- unique(as.character(db_seq))

  code_dir <- file.path(index_root, "code")
  dir.create(code_dir, recursive = TRUE, showWarnings = FALSE)

  covs <- .index_code_bundle_locked_covs(project_root, ix, config, db_seq)
  forest <- .index_code_bundle_forest_settings(project_root, ix, config, db_seq)
  is_prog <- exists("incidence_batch_is_prognosis_config", mode = "function") &&
    isTRUE(incidence_batch_is_prognosis_config(config))
  is_ml <- !is.null(config$ml_batch) ||
    isTRUE((config$shiny_ml_app %||% list())$enable) ||
    grepl("ml_", as.character(config$project$name %||% "")[1L], ignore.case = TRUE)
  worker_rel <- if (isTRUE(is_ml)) {
    "run/ml/run_ml_dual_batch_worker.R"
  } else if (is_prog) {
    "run/survival/run_survival_dual_batch_worker.R"
  } else {
    "run/incidence/run_incidence_dual_batch_worker.R"
  }

  # blocks menu
  pipe <- if (is_prog) {
    config$pipeline_regular_batch %||% config$pipelines$pipeline_regular_batch %||% list()
  } else {
    config$pipeline_regular_batch %||% config$pipelines$pipeline_regular_batch %||%
      config$pipeline_nhanes_batch %||% list()
  }
  # survival template often puts blocks on config via bind
  blks <- as.character(
    (config$survival_batch %||% list())$.pipeline_blocks %||%
      pipe$blocks %||%
      (config$pipeline %||% list())$blocks %||%
      character(0)
  )
  # fallback: read from last worker log pattern — use common prognosis chain
  if (!length(blks) && is_prog) {
    blks <- c(
      "data_clean", "column_mapping", "dual_db_column_harmonize", "index",
      "imputation", "trim_index_extreme", "baseline_binary",
      "univariate_prognosis", "multicollinearity_screen", "multivariate_prognosis",
      "multivariate_covariate_resolve", "multicollinearity_final",
      "dual_db_covariate_harmonize", "multivariate_prognosis_harmonized",
      "cox_quartile", "cox_tertile", "cox_binary", "rcs_prognosis",
      "km_strata", "segmented_cox_quartile", "segmented_cox_tertile",
      "km_binary", "segmented_cox_binary", "subgroup_prognosis",
      "simple_ROC", "boxplot", "mediation_prognosis"
    )
  }
  writeLines(blks, file.path(code_dir, "blocks_menu.txt"))

  # 实际用过的 block 名 + 源码镜像（发病 / 预后铁律）
  used_blks <- .index_code_bundle_used_blocks(
    project_root = project_root,
    index_root = index_root,
    ix = ix,
    config = config,
    db_seq = db_seq,
    pipeline_blks = blks
  )
  writeLines(used_blks, file.path(code_dir, "blocks_used.txt"))
  .index_code_bundle_copy_block_sources(code_dir, engine_root, used_blks)

  # paths.R — 课题 config 优先 survival / incidence / dual_batch，再回落 config.R
  study_cfg_candidates <- c(
    "config_survival_dual_batch.R",
    "config_incidence_dual_batch.R",
    "config_survival.R",
    "config_incidence.R",
    "config.R"
  )
  study_cfg <- NA_character_
  for (bn in study_cfg_candidates) {
    p <- file.path(project_root, bn)
    if (file.exists(p)) {
      study_cfg <- normalizePath(p, winslash = "/", mustWork = FALSE)
      break
    }
  }
  if (!nzchar(as.character(study_cfg %||% "")[1L]) ||
      identical(as.character(study_cfg)[1L], "NA")) {
    study_cfg <- file.path(project_root, if (is_prog) "config_survival.R" else "config_incidence_dual_batch.R")
    if (!file.exists(study_cfg)) {
      study_cfg <- file.path(project_root, if (is_prog) "config_survival.R" else "config.R")
    }
    if (file.exists(study_cfg)) {
      study_cfg <- normalizePath(study_cfg, winslash = "/", mustWork = FALSE)
    }
  }
  writeLines(c(
    "# 自动生成：路径常量（一般不必改）",
    sprintf("CODE_BUNDLE_INDEX <- %s", .index_code_bundle_quote_chr(ix)),
    sprintf("CODE_BUNDLE_PROJECT_ROOT <- %s", .index_code_bundle_quote_chr(project_root)),
    sprintf("CODE_BUNDLE_ENGINE_ROOT <- %s", .index_code_bundle_quote_chr(engine_root)),
    sprintf("CODE_BUNDLE_INDEX_ROOT <- %s", .index_code_bundle_quote_chr(index_root)),
    sprintf(
      "CODE_BUNDLE_STUDY_CONFIG <- %s",
      .index_code_bundle_quote_chr(study_cfg)
    ),
    sprintf("CODE_BUNDLE_WORKER <- %s", .index_code_bundle_quote_chr(file.path(engine_root, worker_rel))),
    sprintf("CODE_BUNDLE_IS_PROGNOSIS <- %s", if (is_prog) "TRUE" else "FALSE")
  ), file.path(code_dir, "paths.R"))

  # force_model2 = Table 2 的 Model2（不含 Model3 学术必调）；
  # 终模（Model3 显著时含 Gender/SOFA）写在注释里供对照，勿塞进 force_model2。
  m2_use <- if (length(covs$model2)) covs$model2 else covs$cox_final
  final_note <- if (length(covs$cox_final) &&
                    !identical(sort(covs$cox_final), sort(m2_use))) {
    sprintf(
      "# Table 2 全调整终模（Model3）= %s",
      paste(covs$cox_final, collapse = ", ")
    )
  } else {
    NULL
  }
  path_use_cov <- isTRUE(covs$path_use_covariates)
  med_use <- if (!isTRUE(path_use_cov)) {
    character(0)
  } else if (length(covs$mediation_covs)) {
    covs$mediation_covs
  } else {
    m2_use
  }
  bm0 <- as.character(covs$best_mediator %||% "")[1L]
  if (nzchar(bm0)) med_use <- setdiff(med_use, bm0)
  ov <- c(
    "# =============================================================================",
    sprintf("#  %s — 协变量 / 中介 / 森林图覆盖（只改本文件）", ix),
    "#  改完后用 run.R 单步重跑。默认从 checkpoint 续跑，勿轻易 --from imputation。",
    "# =============================================================================",
    "",
    "apply_overrides_to_config <- TRUE",
    "patch_checkpoint_covariates <- TRUE  # 重跑前把 Model1/2 写入相关 checkpoint",
    "",
    "# --- 用户可改区：协变量 / 中介 ---------------------------------------------",
    sprintf("force_model1_factors <- %s", .index_code_bundle_quote_chr(covs$model1)),
    sprintf("force_model2_factors <- %s", .index_code_bundle_quote_chr(m2_use)),
    final_note,
    sprintf(
      "force_best_mediator <- %s",
      if (nzchar(as.character(covs$best_mediator %||% "")[1L])) {
        .index_code_bundle_quote_chr(covs$best_mediator)
      } else {
        '""'
      }
    ),
    sprintf("force_mediation_covariates <- %s", .index_code_bundle_quote_chr(med_use)),
    sprintf("force_mediation_path_use_covariates <- %s", if (path_use_cov) "TRUE" else "FALSE"),
    "",
    "# --- 用户可改区：森林图（Figure 亚组）--------------------------------------",
    sprintf("force_subgroup_vars <- %s", .index_code_bundle_quote_chr(forest$vars)),
    sprintf("force_forbid_subgroup_vars <- %s", .index_code_bundle_quote_chr(forest$forbid)),
    sprintf("force_age_cutoff <- %s", .index_code_bundle_quote_scalar(forest$age_cutoff, "65")),
    sprintf("force_subgroup_min_n <- %s", .index_code_bundle_quote_scalar(forest$min_n, "20")),
    sprintf("force_forest_xlim <- %s", .index_code_bundle_quote_num(forest$forest_xlim)),
    sprintf(
      "force_forest_ticks_at <- %s",
      if (length(forest$forest_ticks_at)) {
        .index_code_bundle_quote_num(forest$forest_ticks_at)
      } else {
        "NULL  # 自动刻度；可改成 c(0.5, 1, 2, 4)"
      }
    ),
    sprintf("force_forest_xlim_max <- %s", .index_code_bundle_quote_scalar(forest$forest_xlim_max, "80")),
    sprintf("force_forest_base_size <- %s", .index_code_bundle_quote_scalar(forest$forest_base_size, "9")),
    sprintf(
      "force_forest_x_trans <- %s",
      if (nzchar(as.character(forest$forest_x_trans %||% "")[1L])) {
        .index_code_bundle_quote_chr(forest$forest_x_trans)
      } else {
        '"log"'
      }
    ),
    sprintf("force_forest_n_source <- %s", .index_code_bundle_quote_chr(forest$forest_n_source %||% "full_stratum")),
    sprintf("force_continuous_index_mode <- %s", .index_code_bundle_quote_chr(forest$continuous_index_mode %||% "highest_vs_lowest")),
    sprintf("force_subgroup_adjust_covariates <- %s", .index_code_bundle_quote_chr(forest$adjust_covariates %||% character(0))),
    "# 重跑森林图: Rscript run.R --blocks subgroup_prognosis",
    "# -------------------------------------------------------------------------",
    "",
    "if (!exists('%||%', mode = 'function')) {",
    "  `%||%` <- function(x, y) if (is.null(x)) y else x",
    "}",
    "",
    "code_bundle_apply <- function(config) {",
    "  if (!isTRUE(apply_overrides_to_config)) return(config)",
    "  m1 <- as.character(force_model1_factors %||% character(0))",
    "  m2 <- as.character(force_model2_factors %||% character(0))",
    "  m1 <- m1[nzchar(m1)]; m2 <- m2[nzchar(m2)]",
    "  if (!length(m2) && length(m1)) m2 <- m1",
    "  # analysis_models / cox_* / logistic_*",
    "  if (is.null(config$analysis_models)) config$analysis_models <- list()",
    "  if (length(m1)) config$analysis_models$model1_factors <- m1",
    "  if (length(m2)) config$analysis_models$model2_factors <- m2",
    "  for (nm in c('rcs_prognosis','rcs_incidence','cox_quartile','cox_tertile','cox_binary',",
    "               'logistic_quartile_glm','logistic_tertile_glm','logistic_binary_glm',",
    "               'logistic_quartile_nhanes_weighted','logistic_tertile_nhanes_weighted',",
    "               'logistic_binary_nhanes_weighted')) {",
    "    if (is.null(config[[nm]])) next",
    "    if (length(m1)) config[[nm]]$model1_factors <- m1",
    "    if (length(m2)) config[[nm]]$model2_factors <- m2",
    "  }",
    "  if (is.null(config$dual_db)) config$dual_db <- list()",
    "  if (is.null(config$dual_db$harmonization)) config$dual_db$harmonization <- list()",
    "  hz <- config$dual_db$harmonization",
    "  if (length(m1)) {",
    "    hz$harmonized_model1_nhanes <- m1",
    "    hz$harmonized_model1_mimic <- m1",
    "  }",
    "  if (length(m2)) {",
    "    hz$harmonized_model2_nhanes <- m2",
    "    hz$harmonized_model2_mimic <- m2",
    "  }",
    "  config$dual_db$harmonization <- hz",
    "  # mediation（force_mediation_path_use_covariates=FALSE → crude；空协变量勿回退为 TRUE）",
    "  med_cov <- as.character(force_mediation_covariates %||% character(0))",
    "  med_cov <- med_cov[nzchar(med_cov)]",
    "  bm <- as.character(force_best_mediator %||% '')[1L]",
    "  med_use_cov <- if (exists('force_mediation_path_use_covariates')) {",
    "    isTRUE(force_mediation_path_use_covariates)",
    "  } else {",
    "    length(med_cov) > 0L",
    "  }",
    "  for (nm in c('mediation_prognosis','mediation_incidence','mediation_nhanes_weighted')) {",
    "    if (is.null(config[[nm]])) config[[nm]] <- list()",
    "    config[[nm]]$path_use_covariates <- med_use_cov",
    "    if (isTRUE(med_use_cov) && length(med_cov)) {",
    "      config[[nm]]$covariate_source <- 'config'",
    "      config[[nm]]$covariates <- med_cov",
    "    } else {",
    "      config[[nm]]$covariate_source <- 'none'",
    "      config[[nm]]$covariates <- character(0)",
    "    }",
    "    if (nzchar(bm) && !identical(bm, 'NA')) config[[nm]]$best_mediator <- bm",
    "  }",
    "  if (is.null(config$mediation_policy)) config$mediation_policy <- list()",
    "  config$mediation_policy$path_use_covariates <- med_use_cov",
    "  config$mediation_policy$covariate_source <- if (isTRUE(med_use_cov)) 'config' else 'none'",
    "  # forest / subgroup",
    "  sg_vars <- as.character(force_subgroup_vars %||% character(0))",
    "  sg_vars <- sg_vars[nzchar(sg_vars)]",
    "  forbid <- as.character(force_forbid_subgroup_vars %||% character(0))",
    "  forbid <- forbid[nzchar(forbid)]",
    "  fx <- suppressWarnings(as.numeric(force_forest_xlim %||% numeric(0)))",
    "  fx <- fx[is.finite(fx)]",
    "  ft <- if (exists('force_forest_ticks_at')) {",
    "    suppressWarnings(as.numeric(force_forest_ticks_at))",
    "  } else numeric(0)",
    "  ft <- ft[is.finite(ft)]",
    "  for (nm in c('subgroup','subgroup_prognosis','subgroup_incidence',",
    "               'subgroup_nhanes_weighted','subgroup_iptw_weighted')) {",
    "    if (is.null(config[[nm]])) config[[nm]] <- list()",
    "    if (length(sg_vars)) {",
    "      config[[nm]]$required_subgroup_vars <- sg_vars",
    "      config[[nm]]$locked_subgroup_vars <- sg_vars",
    "      config[[nm]]$vars <- sg_vars",
    "    }",
    "    if (length(forbid)) config[[nm]]$forbid_subgroup_vars <- forbid",
    "    if (exists('force_age_cutoff') && is.finite(suppressWarnings(as.numeric(force_age_cutoff)[1L])))",
    "      config[[nm]]$age_cutoff <- as.numeric(force_age_cutoff)[1L]",
    "    if (exists('force_subgroup_min_n') && is.finite(suppressWarnings(as.numeric(force_subgroup_min_n)[1L])))",
    "      config[[nm]]$min_n <- as.numeric(force_subgroup_min_n)[1L]",
    "    if (length(fx) >= 2L) config[[nm]]$forest_xlim <- fx[1:2]",
    "    if (length(ft) >= 2L) config[[nm]]$forest_ticks_at <- ft",
    "    if (exists('force_forest_xlim_max') && is.finite(suppressWarnings(as.numeric(force_forest_xlim_max)[1L])))",
    "      config[[nm]]$forest_xlim_max <- as.numeric(force_forest_xlim_max)[1L]",
    "    if (exists('force_forest_base_size') && is.finite(suppressWarnings(as.numeric(force_forest_base_size)[1L])))",
    "      config[[nm]]$forest_base_size <- as.numeric(force_forest_base_size)[1L]",
    "    xt <- as.character(force_forest_x_trans %||% '')[1L]",
    "    if (nzchar(xt)) config[[nm]]$forest_x_trans <- xt",
    "    ns <- as.character(force_forest_n_source %||% '')[1L]",
    "    if (nzchar(ns)) config[[nm]]$forest_n_source <- ns",
    "    cim <- as.character(force_continuous_index_mode %||% '')[1L]",
    "    if (nzchar(cim)) config[[nm]]$continuous_index_mode <- cim",
    "    adj <- as.character(force_subgroup_adjust_covariates %||% character(0))",
    "    adj <- adj[nzchar(trimws(adj))]",
    "    if (length(adj)) config[[nm]]$adjust_covariates <- adj",
    "  }",
    "  invisible(config)",
    "}"
  )
  writeLines(ov, file.path(code_dir, "00_config_overrides.R"))

  # run.R
  run_r <- c(
    "#!/usr/bin/env Rscript",
    "# 单指标可改协变量 / 单步重跑入口",
    "# 用法:",
    "#   Rscript run.R --from cox_quartile --to mediation_prognosis",
    "#   Rscript run.R --blocks mediation_prognosis",
    "#   Rscript run.R --blocks subgroup_prognosis   # 只重画森林图",
    "#   Rscript run.R --blocks subgroup_prognosis --out D:/rerun_forest_v1  # 不覆盖主结果",
    "#   Rscript run.R --from multivariate_prognosis_harmonized --to cox_quartile --db both",
    "# 警告: 不要轻易 --from imputation / trim_index_extreme（会改分析人数）",
    "",
    "args <- commandArgs(trailingOnly = TRUE)",
    "opts <- list(from = NULL, to = NULL, blocks = NULL, db = 'both',",
    "             out = NULL, patch_ck = TRUE, dry_run = FALSE)",
    "i <- 1L",
    "while (i <= length(args)) {",
    "  a <- args[[i]]",
    "  if (a == '--from' && i < length(args)) { opts$from <- args[[i+1L]]; i <- i+2L",
    "  } else if (a == '--to' && i < length(args)) { opts$to <- args[[i+1L]]; i <- i+2L",
    "  } else if (a == '--blocks' && i < length(args)) {",
    "    opts$blocks <- trimws(strsplit(args[[i+1L]], ',', fixed = TRUE)[[1L]]); i <- i+2L",
    "  } else if (a == '--db' && i < length(args)) { opts$db <- tolower(args[[i+1L]]); i <- i+2L",
    "  } else if ((a == '--out' || a == '--outdir') && i < length(args)) {",
    "    opts$out <- args[[i+1L]]; i <- i+2L",
    "  } else if (a == '--no-patch-ck') { opts$patch_ck <- FALSE; i <- i+1L",
    "  } else if (a == '--dry-run') { opts$dry_run <- TRUE; i <- i+1L",
    "  } else { i <- i+1L }",
    "}",
    "",
    "code_dir <- tryCatch({",
    "  ca <- commandArgs(trailingOnly = FALSE)",
    "  f <- grep('^--file=', ca, value = TRUE)",
    "  if (length(f)) dirname(normalizePath(sub('^--file=', '', f[1L]), winslash = '/'))",
    "  else normalizePath(getwd(), winslash = '/')",
    "}, error = function(e) normalizePath(getwd(), winslash = '/'))",
    "",
    "source(file.path(code_dir, 'paths.R'), local = FALSE)",
    "source(file.path(code_dir, '00_config_overrides.R'), local = FALSE)",
    "",
    "# Linux/WSL：若 paths.R 写成盘符（G:/...），映射回 /mnt/<drv>",
    "if (.Platform$OS.type != 'windows') {",
    "  .cb_nix <- function(p) {",
    "    p <- gsub('\\\\\\\\', '/', as.character(p)[1L])",
    "    if (grepl('^[A-Za-z]:/', p)) {",
    "      drv <- tolower(substr(p, 1L, 1L))",
    "      rest <- substring(p, 4L)",
    "      return(paste0('/mnt/', drv, '/', rest))",
    "    }",
    "    p",
    "  }",
    "  CODE_BUNDLE_PROJECT_ROOT <<- .cb_nix(CODE_BUNDLE_PROJECT_ROOT)",
    "  CODE_BUNDLE_ENGINE_ROOT <<- .cb_nix(CODE_BUNDLE_ENGINE_ROOT)",
    "  CODE_BUNDLE_INDEX_ROOT <<- .cb_nix(CODE_BUNDLE_INDEX_ROOT)",
    "  CODE_BUNDLE_STUDY_CONFIG <<- .cb_nix(CODE_BUNDLE_STUDY_CONFIG)",
    "  CODE_BUNDLE_WORKER <<- .cb_nix(CODE_BUNDLE_WORKER)",
    "}",
    "",
    "# Windows 本机：把 WSL 路径映射成可访问路径（优先盘符，避免 //UNC 被当成相对路径）",
    "if (.Platform$OS.type == 'windows') {",
    "  .cb_win <- function(p) {",
    "    p <- gsub('\\\\\\\\', '/', as.character(p)[1L])",
    "    # /mnt/g/DockerHome/... → G:/DockerHome/... 或 \\\\192.168.68.133\\DockerHome\\...",
    "    if (grepl('^/mnt/g/DockerHome/', p, ignore.case = TRUE)) {",
    "      rest <- sub('^/mnt/g/DockerHome/', '', p, ignore.case = TRUE)",
    "      cands <- c(",
    "        paste0('G:/DockerHome/', rest),",
    "        paste0('\\\\\\\\192.168.68.133\\\\DockerHome\\\\', gsub('/', '\\\\\\\\', rest))",
    "      )",
    "      for (.c in cands) {",
    "        if (dir.exists(.c) || file.exists(.c)) return(gsub('\\\\\\\\', '/', .c))",
    "      }",
    "      return(gsub('\\\\\\\\', '/', cands[[1L]]))",
    "    }",
    "    if (grepl('^//192\\\\.168\\\\.68\\\\.133/DockerHome/', p) ||",
    "        grepl('^//192.168.68.133/DockerHome/', p)) {",
    "      rest <- sub('^//192.168.68.133/DockerHome/', '', p)",
    "      g <- paste0('G:/DockerHome/', rest)",
    "      if (dir.exists(g) || file.exists(g)) return(g)",
    "      return(p)",
    "    }",
    "    if (grepl('^/mnt/[A-Za-z]/', p)) {",
    "      drv <- toupper(substr(p, 6L, 6L))",
    "      rest <- substring(p, 8L)",
    "      return(paste0(drv, ':/', rest))",
    "    }",
    "    p",
    "  }",
    "  CODE_BUNDLE_PROJECT_ROOT <<- .cb_win(CODE_BUNDLE_PROJECT_ROOT)",
    "  CODE_BUNDLE_ENGINE_ROOT <<- .cb_win(CODE_BUNDLE_ENGINE_ROOT)",
    "  CODE_BUNDLE_INDEX_ROOT <<- .cb_win(CODE_BUNDLE_INDEX_ROOT)",
    "  CODE_BUNDLE_STUDY_CONFIG <<- .cb_win(CODE_BUNDLE_STUDY_CONFIG)",
    "  CODE_BUNDLE_WORKER <<- .cb_win(CODE_BUNDLE_WORKER)",
    "  # 本机无 E:/01block 时，依次尝试常见引擎位置",
    "  .eng_cands <- unique(c(",
    "    CODE_BUNDLE_ENGINE_ROOT,",
    "    'E:/01block/01Block-new-Final',",
    "    'G:/01block-G/01Block-new-Final'",
    "  ))",
    "  .eng_hit <- NA_character_",
    "  for (.e in .eng_cands) {",
    "    if (dir.exists(.e) && file.exists(file.path(.e, 'run/survival/run_survival_dual_batch_worker.R'))) {",
    "      .eng_hit <- .e; break",
    "    }",
    "  }",
    "  if (is.na(.eng_hit)) {",
    "    stop(",
    "      '本机找不到引擎目录。已尝试:\\n  - ', paste(.eng_cands, collapse = '\\n  - '),",
    "      '\\n请编辑 paths.R 把 CODE_BUNDLE_ENGINE_ROOT 改成你的引擎路径。'",
    "    )",
    "  }",
    "  CODE_BUNDLE_ENGINE_ROOT <<- .eng_hit",
    "  CODE_BUNDLE_WORKER <<- file.path(",
    "    CODE_BUNDLE_ENGINE_ROOT, 'run/survival/run_survival_dual_batch_worker.R'",
    "  )",
    "  CODE_BUNDLE_WORKER <<- gsub('\\\\\\\\', '/', CODE_BUNDLE_WORKER)",
    "  # 课题根必须存在且含 checkpoints（防止 UNC 拼到引擎下）",
    "  if (!dir.exists(CODE_BUNDLE_PROJECT_ROOT) ||",
    "      !dir.exists(file.path(CODE_BUNDLE_PROJECT_ROOT, 'checkpoints'))) {",
    "    stop(",
    "      '课题根无效: ', CODE_BUNDLE_PROJECT_ROOT,",
    "      '\\n请在 paths.R 改为盘符路径，例如 G:/DockerHome/5001/medical-blocks-studies/studies/...')",
    "  }",
    "  message('Windows 路径映射:')",
    "  message('  ENGINE  = ', CODE_BUNDLE_ENGINE_ROOT)",
    "  message('  PROJECT = ', CODE_BUNDLE_PROJECT_ROOT)",
    "  message('  WORKER  = ', CODE_BUNDLE_WORKER)",
    "  if (!file.exists(CODE_BUNDLE_STUDY_CONFIG))",
    "    stop('本机找不到课题 config: ', CODE_BUNDLE_STUDY_CONFIG)",
    "}",
    "Sys.setenv(MEDICAL_BLOCKS_ROOT = CODE_BUNDLE_ENGINE_ROOT)",
    "Sys.setenv(INCIDENCE_BATCH_ROOT = CODE_BUNDLE_PROJECT_ROOT)",
    "",
    "# --blocks 无 --from 时：自动从前一 block 加载 checkpoint（避免 No data）",
    "if (length(opts$blocks) && (is.null(opts$from) || !nzchar(as.character(opts$from)[1L]))) {",
    "  menu_p <- file.path(code_dir, 'blocks_menu.txt')",
    "  if (file.exists(menu_p)) {",
    "    menu <- trimws(readLines(menu_p, warn = FALSE))",
    "    menu <- menu[nzchar(menu) & !startsWith(menu, '#')]",
    "    first <- as.character(opts$blocks[[1L]])[1L]",
    "    idx <- match(first, menu)",
    "    if (!is.na(idx) && idx > 1L) {",
    "      opts$from <- menu[[idx - 1L]]",
    "      message('自动 --from ', opts$from, '（加载 ck 后再跑 ', first, '）')",
    "    }",
    "  }",
    "}",
    "",
    "# 组装临时 config = 课题 config + overrides",
    "# 必须写在课题根下：config.R 用 --config 的 dirname 当 project root；",
    "# 若写到 Temp，会找不到 Data/ 与 checkpoints。",
    "tmp_cfg <- file.path(",
    "  CODE_BUNDLE_PROJECT_ROOT,",
    "  paste0('._code_bundle_', CODE_BUNDLE_INDEX, '_cfg.R')",
    ")",
    "writeLines(c(",
    "  sprintf('source(%s, local = FALSE)', deparse(CODE_BUNDLE_STUDY_CONFIG)),",
    "  sprintf('source(%s, local = FALSE)', deparse(file.path(code_dir, '00_config_overrides.R'))),",
    "  'if (exists(\"code_bundle_apply\", mode = \"function\")) config <- code_bundle_apply(config)'",
    "), tmp_cfg)",
    "on.exit(unlink(tmp_cfg), add = TRUE)",
    "",
    "# --out：结果写到独立目录，不覆盖【success】主结果；默认也不 patch 主 ck",
    "if (!is.null(opts$out) && nzchar(as.character(opts$out)[1L])) {",
    "  out_dir <- as.character(opts$out)[1L]",
    "  if (!grepl('^[A-Za-z]:|^\\\\\\\\|^/', out_dir) && !grepl('^//', out_dir)) {",
    "    out_dir <- file.path(code_dir, out_dir)",
    "  }",
    "  out_dir <- gsub('\\\\\\\\', '/', out_dir)",
    "  if (.Platform$OS.type != 'windows' && grepl('^[A-Za-z]:/', out_dir)) {",
    "    out_dir <- paste0('/mnt/', tolower(substr(out_dir, 1L, 1L)), '/', substring(out_dir, 4L))",
    "  }",
    "  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)",
    "  out_dir <- normalizePath(out_dir, winslash = '/', mustWork = FALSE)",
    "  Sys.setenv(MEDICAL_BLOCKS_RERUN_OUT = out_dir)",
    "  opts$patch_ck <- FALSE",
    "  message('输出目录(--out): ', out_dir, '（不覆盖主结果；已关闭 patch ck）')",
    "} else {",
    "  Sys.unsetenv('MEDICAL_BLOCKS_RERUN_OUT')",
    "}",
    "",
    "cmd <- c(",
    "  CODE_BUNDLE_WORKER,",
    "  '--config', tmp_cfg,",
    "  '--index', CODE_BUNDLE_INDEX,",
    "  '--db', opts$db",
    ")",
    "if (!is.null(opts$from) && nzchar(opts$from)) cmd <- c(cmd, '--from', opts$from)",
    "if (!is.null(opts$to) && nzchar(opts$to)) cmd <- c(cmd, '--to', opts$to)",
    "if (!is.null(opts$blocks) && length(opts$blocks)) {",
    "  cmd <- c(cmd, '--blocks', paste(opts$blocks, collapse = ','))",
    "}",
    "message('Rscript ', paste(shQuote(cmd), collapse = ' '))",
    "if (isTRUE(opts$dry_run)) quit(save = 'no', status = 0)",
    "",
    "# 可选：把 Model1/2 写进 checkpoint（有 --out 时默认关闭，避免改主分析 ck）",
    "if (isTRUE(opts$patch_ck) && isTRUE(patch_checkpoint_covariates) &&",
    "    exists('force_model1_factors') && exists('force_model2_factors')) {",
    "  m1 <- as.character(force_model1_factors); m2 <- as.character(force_model2_factors)",
    "  m1 <- m1[nzchar(m1)]; m2 <- m2[nzchar(m2)]",
    "  ck_base <- file.path(CODE_BUNDLE_PROJECT_ROOT, 'checkpoints', 'by_index', CODE_BUNDLE_INDEX)",
    "  if (dir.exists(ck_base) && (length(m1) || length(m2))) {",
    "    for (dbn in list.dirs(ck_base, full.names = TRUE, recursive = FALSE)) {",
    "      if (identical(basename(dbn), 'harmonization')) next",
    "      for (fn in list.files(dbn, pattern = '\\\\.rds$', full.names = TRUE)) {",
    "        bn <- basename(fn)",
    "        if (!grepl('covariate|multivariate|cox_|multicollinearity_final|mediation_', bn)) next",
    "        obj <- tryCatch(readRDS(fn), error = function(e) NULL)",
    "        if (is.null(obj) || is.null(obj$ctx) || is.null(obj$ctx$results)) next",
    "        if (length(m1)) obj$ctx$results$Model1Factors <- m1",
    "        if (length(m2)) {",
    "          obj$ctx$results$Model2Factors <- m2",
    "          # 不覆盖 cox_final_factors：终模可能是 Model3（Model2+学术必调）",
    "        }",
    "        tryCatch(saveRDS(obj, fn), error = function(e) NULL)",
    "      }",
    "    }",
    "    message('已 patch checkpoint Model1/Model2（可用 --no-patch-ck 关闭）')",
    "  }",
    "}",
    "",
    "# WSL/部分 Unix 上 system2(向量) 会对含空格参数二次拆分；用 shQuote + system 保路径完整",
    "status <- system(paste(shQuote(c('Rscript', cmd)), collapse = ' '))",
    "quit(save = 'no', status = if (is.na(status)) 1L else as.integer(status))"
  )
  run_path <- file.path(code_dir, "run.R")
  writeLines(run_r, run_path)
  tryCatch(Sys.chmod(run_path, mode = "0755"), error = function(e) NULL)

  # README + 操作说明（用户模板风格）
  op_doc <- c(
    sprintf("# %s — 单步重跑操作说明", ix),
    "",
    "## 模板",
    "",
    "```powershell",
    "cd \"<课题>/by_index/【success】<指标>/code\"",
    "$env:MEDICAL_BLOCKS_ROOT = \"E:/01block/01Block-new-Final\"",
    "Rscript ./run.R --blocks <要跑的块>",
    "```",
    "",
    "指定输出目录（**不覆盖**【success】主结果）：",
    "",
    "```powershell",
    "Rscript ./run.R --blocks <要跑的块> --out \"<你的目录>\"",
    "```",
    "",
    "## 例子",
    "",
    "```powershell",
    sprintf(
      "cd \"G:/DockerHome/5001/medical-blocks-studies/studies/01_ARDS/prognosis_38902748/by_index/【success】%s/code\"",
      ix
    ),
    "$env:MEDICAL_BLOCKS_ROOT = \"E:/01block/01Block-new-Final\"",
    "Rscript ./run.R --blocks subgroup_prognosis",
    "```",
    "",
    "不覆盖主图，另存一版：",
    "",
    "```powershell",
    sprintf(
      "cd \"G:/DockerHome/5001/medical-blocks-studies/studies/01_ARDS/prognosis_38902748/by_index/【success】%s/code\"",
      ix
    ),
    "$env:MEDICAL_BLOCKS_ROOT = \"E:/01block/01Block-new-Final\"",
    "Rscript ./run.R --blocks subgroup_prognosis --out \"G:/DockerHome/5001/reruns/ALBI_forest_v1\"",
    "```",
    "",
    "## 参数说明",
    "",
    "| 参数 | 含义 |",
    "|---|---|",
    "| `--blocks <名>` | 只跑列出的 block（逗号分隔多个） |",
    "| `--from A --to B` | 从 A 之后跑到 B（含） |",
    "| `--out <目录>` | 结果写到该目录，**不覆盖**【success】主结果；并默认不 patch 主 ck |",
    "| `--db both\\|nhanes\\|mimic` | 默认 both |",
    "| `--no-patch-ck` | 禁止改主分析 checkpoint 里的 Model1/2 |",
    "| `--dry-run` | 只打印命令不执行 |",
    "",
    "## 结果在哪",
    "",
    "- **不加 `--out`**：写入 `【success】<指标>/Figures` / `Tables`（及 eICU、MIMIC 子目录），并自动双库拼图。",
    "- **加了 `--out`**：全部新表/新图写到你指定的目录（含 eICU/MIMIC 与拼图），主结果不动。",
    "",
    "## 改什么文件",
    "",
    "- 只改 `00_config_overrides.R`（协变量 / 森林图 / 中介）",
    "- 一般不改 `paths.R`（133 上用 G:/DockerHome + E:/01block）",
    "- **本指标用过的 Block 源码**在 `blocks/`（见 `blocks/MANIFEST.md`、`blocks_used.txt`）；对照用，重跑仍走引擎",
    "",
    "## 本指标实际用过的 block",
    "",
    paste(used_blks, collapse = "\n"),
    "",
    "## pipeline 全名单（可 `--blocks` 重跑）",
    "",
    paste(blks, collapse = "\n"),
    "",
    "## 常用对照",
    "",
    "| 想做的事 | block |",
    "|---|---|",
    "| 四分位 Cox（Table 2） | `cox_quartile` |",
    "| 三分位 / 二分位 Cox | `cox_tertile` / `cox_binary` |",
    "| 四分位 / 三分位 / 二分位 logistic | `logistic_quartile_glm` / `logistic_tertile_glm` / `logistic_binary_glm` |",
    "| 亚组森林图 | `subgroup_prognosis` / `subgroup_incidence` |",
    "| 中介 + 路径图 | `mediation_prognosis` / `mediation_incidence` |",
    "| RCS | `rcs_prognosis` / `rcs_incidence` |",
    "| KM | `km_strata` / `km_binary` |",
    "| ROC / 箱线 | `simple_ROC` / `boxplot` |",
    "",
    "## 不要随便跑（会改人数 N）",
    "",
    "- `imputation`",
    "- `trim_index_extreme`",
    "",
    sprintf("生成时间: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))
  )
  writeLines(op_doc, file.path(code_dir, "操作说明.md"))
  writeLines(op_doc, file.path(code_dir, "README.md"))

  cheat <- c(
    "# Block 速查",
    "",
    "完整操作见 `操作说明.md`。",
    "",
    "## 本指标实际用过的 block 源码",
    "",
    "见目录 `blocks/`（`MANIFEST.md` + 镜像的 `Blocks/...`）。名单：`blocks_used.txt`。",
    "",
    paste(paste0("- `", used_blks, "`"), collapse = "\n"),
    "",
    "## 模板",
    "```powershell",
    "cd \"<课题>/by_index/【success】<指标>/code\"",
    "$env:MEDICAL_BLOCKS_ROOT = \"E:/01block/01Block-new-Final\"",
    "Rscript ./run.R --blocks <要跑的块>",
    "Rscript ./run.R --blocks <要跑的块> --out \"<不覆盖主结果的目录>\"",
    "```",
    "",
    "## pipeline 全名单",
    "",
    paste(blks, collapse = "\n")
  )
  writeLines(cheat, file.path(code_dir, "blocks_cheatsheet.md"))

  val <- index_code_bundle_validate(code_dir)
  if (!isTRUE(val$ok)) {
    if (requireNamespace("cli", quietly = TRUE)) {
      cli::cli_alert_warning(
        "code 包写入后校验未通过: {paste(val$issues, collapse = '; ')}"
      )
    }
    return(invisible(FALSE))
  }

  if (requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_success("已生成指标 code 包: {.file {code_dir}}")
  }
  invisible(TRUE)
}

# =============================================================================
#  单库平链（all-vars ML / 单流水线）code 包
#  落盘：<study_root>/code/（无 by_index）
# =============================================================================

.index_code_bundle_should_write_single <- function(config, pipeline = NULL) {
  cb <- (config %||% list())$code_bundle %||% list()
  if (identical(cb$enable, FALSE)) return(FALSE)
  dual <- (config %||% list())$dual_db %||% list()
  if (isTRUE(dual$enable)) return(FALSE)
  cur <- as.character(dual$current_db %||% "")[1L]
  if (nzchar(cur)) return(FALSE)
  # dual-batch worker 注入的指标批处理：交给 index_code_bundle_finalize
  if (!is.null((config$survival_batch %||% list())$index) ||
      !is.null((config$incidence_batch %||% list())$index) ||
      !is.null((config$ml_batch %||% list())$index)) {
    return(FALSE)
  }
  if (isTRUE(cb$enable)) return(TRUE)
  blks <- as.character((pipeline %||% list())$blocks %||% character(0))
  if (!length(blks)) {
    blks <- as.character((config$pipeline %||% list())$blocks %||% character(0))
  }
  has_ml <- any(grepl(
    "^(ml_|feature_selection|shap$|performance_ml|shiny_ml|train_validation|cox_ml_)",
    blks
  ))
  isTRUE((config$project %||% list())$use_step_prefixed_block_dirs) || has_ml
}

.index_code_bundle_used_blocks_flat <- function(study_root, pipeline_blks = character(0)) {
  used <- character(0)
  .add <- function(x) {
    x <- as.character(x %||% character(0))
    x <- gsub("\\.rds$", "", x)
    x <- gsub("^step\\d+_", "", x)
    x <- x[nzchar(x)]
    x <- x[!grepl("^(harmonization|preferred_mediator|obj)$", x, ignore.case = TRUE)]
    used <<- c(used, x)
  }
  study_root <- normalizePath(as.character(study_root)[1L], winslash = "/", mustWork = FALSE)
  if (dir.exists(study_root)) {
    dirs <- list.dirs(study_root, full.names = FALSE, recursive = FALSE)
    .add(dirs[grepl("^step\\d+_", dirs)])
  }
  ck <- file.path(study_root, "checkpoints")
  if (dir.exists(ck)) {
    .add(list.files(ck, pattern = "\\.rds$", full.names = FALSE))
  }
  used <- unique(used)
  pipe <- as.character(pipeline_blks %||% character(0))
  pipe <- pipe[nzchar(pipe)]
  if (length(used)) {
    ordered <- intersect(pipe, used)
    extra <- setdiff(used, ordered)
    # 子模型 step（ml_xgbsurv 等）可能不在 pipeline 名单但实际有目录
    return(c(ordered, sort(extra)))
  }
  pipe
}

.index_code_bundle_locked_covs_flat <- function(study_root, config) {
  out <- list(
    model1 = character(0), model2 = character(0),
    cox_final = character(0), mediation_covs = character(0),
    best_mediator = NA_character_,
    path_use_covariates = FALSE,
    ml_features = character(0)
  )
  # 课题 config 优先（RCS / Cox 连续特征关联表）
  rcs <- (config %||% list())$rcs_prognosis %||% list()
  if (length(as.character(rcs$model1_factors %||% character(0)))) {
    out$model1 <- as.character(rcs$model1_factors)
  }
  if (length(as.character(rcs$model2_factors %||% character(0)))) {
    out$model2 <- as.character(rcs$model2_factors)
  }
  ck <- file.path(study_root, "checkpoints")
  for (bn in c(
    "cox_ml_continuous_batch.rds", "rcs_prognosis.rds",
    "subgroup_prognosis.rds", "ml_feature_selection_bundle.rds",
    "multicollinearity_screen.rds"
  )) {
    p <- file.path(ck, bn)
    if (!file.exists(p)) next
    obj <- tryCatch(readRDS(p), error = function(e) NULL)
    res <- obj$ctx$results %||% list()
    if (!length(out$ml_features)) {
      out$ml_features <- as.character(
        res$feature_selection_final %||%
          res$ml_feature_names %||%
          res$cox_ml_continuous_batch_features %||%
          character(0)
      )
    }
    # 仅当 config 未钉死 Model1/2 时，用 checkpoint
    if (!length(out$model1)) {
      out$model1 <- as.character(
        res$cox_ml_continuous_model1 %||% res$Model1Factors %||% character(0)
      )
    }
    if (!length(out$model2)) {
      out$model2 <- as.character(
        res$Model2Factors %||% character(0)
      )
    }
  }
  out$model1 <- unique(out$model1[nzchar(out$model1)])
  out$model2 <- unique(out$model2[nzchar(out$model2)])
  out$ml_features <- unique(out$ml_features[nzchar(out$ml_features)])
  out
}

.index_code_bundle_forest_settings_flat <- function(study_root, config) {
  out <- .index_code_bundle_forest_settings(study_root, "NA", config, db_seq = character(0))
  # 平链 subgroup ck
  for (bn in c("subgroup_prognosis.rds", "subgroup_incidence.rds")) {
    p <- file.path(study_root, "checkpoints", bn)
    if (!file.exists(p)) next
    obj <- tryCatch(readRDS(p), error = function(e) NULL)
    res <- obj$ctx$results %||% list()
    used <- as.character(res$subgroup_vars_used %||% character(0))
    if (length(used)) {
      out$vars <- unique(used[nzchar(used)])
      break
    }
  }
  # config 锁定优先于「跑过的全部分类」膨胀名单（all-vars 亚组常很宽）
  sg <- utils::modifyList(
    config$subgroup %||% list(),
    config$subgroup_prognosis %||% list()
  )
  lock <- as.character(
    sg$locked_subgroup_vars %||% sg$required_subgroup_vars %||% character(0)
  )
  lock <- lock[nzchar(lock)]
  if (length(lock) && isTRUE(sg$restrict_to_required %||% FALSE)) {
    out$vars <- lock
  } else if (length(lock) && !length(out$vars)) {
    out$vars <- lock
  } else if (length(lock)) {
    # 预填 required；用户可在 overrides 扩成全跑过名单
    out$vars <- lock
  }
  if (is.finite(suppressWarnings(as.numeric(sg$age_cutoff)[1L]))) {
    out$age_cutoff <- as.numeric(sg$age_cutoff)[1L]
  }
  if (is.finite(suppressWarnings(as.numeric(sg$min_n)[1L]))) {
    out$min_n <- as.numeric(sg$min_n)[1L]
  }
  fx <- suppressWarnings(as.numeric(sg$forest_xlim %||% numeric(0)))
  if (length(fx) >= 2L && all(is.finite(fx))) out$forest_xlim <- fx[1:2]
  if (is.finite(suppressWarnings(as.numeric(sg$forest_xlim_max)[1L]))) {
    out$forest_xlim_max <- as.numeric(sg$forest_xlim_max)[1L]
  }
  out$forbid <- unique(as.character(
    sg$forbid_subgroup_vars %||% sg$exclude_subgroup_vars %||% out$forbid
  ))
  out$forbid <- out$forbid[nzchar(out$forbid)]
  out
}

#' 单库平链 code 包写出（all-vars ML / 单流水线）
#' @param study_root 课题根（含 config.R / checkpoints / stepNN_*）
index_code_bundle_write_single_pipeline <- function(study_root, config,
                                                   engine_root = NULL,
                                                   pipeline = NULL,
                                                   ix = NULL) {
  study_root <- normalizePath(as.character(study_root)[1L], winslash = "/", mustWork = FALSE)
  if (!nzchar(study_root) || !dir.exists(study_root)) return(invisible(FALSE))
  if (grepl("sensitivity|\\.sensitivity_staging", study_root, ignore.case = TRUE)) {
    return(invisible(FALSE))
  }
  engine_root <- as.character(
    engine_root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "") %||% ""
  )[1L]
  if (!nzchar(engine_root)) engine_root <- study_root
  engine_root <- normalizePath(engine_root, winslash = "/", mustWork = FALSE)

  ix <- as.character(
    ix %||%
      (config$code_bundle %||% list())$index_label %||%
      (config$project %||% list())$disease_code %||%
      (config$project %||% list())$name %||%
      "all_vars"
  )[1L]
  if (!nzchar(ix)) ix <- "all_vars"

  blks <- as.character(
    (pipeline %||% list())$blocks %||%
      (config$pipeline %||% list())$blocks %||%
      character(0)
  )
  if (!length(blks)) {
    # 从 step 目录反推
    dirs <- list.dirs(study_root, full.names = FALSE, recursive = FALSE)
    blks <- gsub("^step\\d+_", "", dirs[grepl("^step\\d+_", dirs)])
    blks <- unique(blks[nzchar(blks)])
  }

  code_dir <- file.path(study_root, "code")
  dir.create(code_dir, recursive = TRUE, showWarnings = FALSE)

  covs <- .index_code_bundle_locked_covs_flat(study_root, config)
  forest <- .index_code_bundle_forest_settings_flat(study_root, config)
  used_blks <- .index_code_bundle_used_blocks_flat(study_root, blks)

  writeLines(blks, file.path(code_dir, "blocks_menu.txt"))
  writeLines(used_blks, file.path(code_dir, "blocks_used.txt"))
  .index_code_bundle_copy_block_sources(code_dir, engine_root, used_blks)

  study_cfg <- file.path(study_root, "config.R")
  if (!file.exists(study_cfg)) {
    for (bn in c("config_ml.R", "config_survival.R", "config_incidence.R")) {
      p <- file.path(study_root, bn)
      if (file.exists(p)) { study_cfg <- p; break }
    }
  }
  if (file.exists(study_cfg)) {
    study_cfg <- normalizePath(study_cfg, winslash = "/", mustWork = FALSE)
  }
  entry <- file.path(study_root, "run_ml.R")
  if (!file.exists(entry)) entry <- file.path(study_root, "run.R")
  if (file.exists(entry)) {
    entry <- normalizePath(entry, winslash = "/", mustWork = FALSE)
  } else {
    entry <- file.path(engine_root, "R", "pipeline_runner.R")
  }

  writeLines(c(
    "# 自动生成：路径常量（一般不必改）",
    sprintf("CODE_BUNDLE_INDEX <- %s", .index_code_bundle_quote_chr(ix)),
    sprintf("CODE_BUNDLE_PROJECT_ROOT <- %s", .index_code_bundle_quote_chr(study_root)),
    sprintf("CODE_BUNDLE_ENGINE_ROOT <- %s", .index_code_bundle_quote_chr(engine_root)),
    sprintf("CODE_BUNDLE_INDEX_ROOT <- %s", .index_code_bundle_quote_chr(study_root)),
    sprintf("CODE_BUNDLE_STUDY_CONFIG <- %s", .index_code_bundle_quote_chr(study_cfg)),
    sprintf("CODE_BUNDLE_ENTRY <- %s", .index_code_bundle_quote_chr(entry)),
    "CODE_BUNDLE_IS_PROGNOSIS <- TRUE",
    "CODE_BUNDLE_SINGLE_PIPELINE <- TRUE"
  ), file.path(code_dir, "paths.R"))

  m2_use <- if (length(covs$model2)) covs$model2 else covs$model1
  ov <- c(
    "# =============================================================================",
    sprintf("#  %s — 协变量 / 森林图 / ML 特征覆盖（只改本文件）", ix),
    "#  改完后用 run.R 单步重跑。默认从 checkpoint 续跑，勿轻易 --from imputation。",
    "# =============================================================================",
    "",
    "apply_overrides_to_config <- TRUE",
    "patch_checkpoint_covariates <- TRUE",
    "",
    "# --- 用户可改区：关联表 / RCS 协变量 ---------------------------------------",
    sprintf("force_model1_factors <- %s", .index_code_bundle_quote_chr(covs$model1)),
    sprintf("force_model2_factors <- %s", .index_code_bundle_quote_chr(m2_use)),
    sprintf("force_ml_features <- %s", .index_code_bundle_quote_chr(covs$ml_features)),
    'force_best_mediator <- ""',
    "force_mediation_covariates <- character(0)",
    "force_mediation_path_use_covariates <- FALSE",
    "",
    "# --- 用户可改区：森林图（Figure 亚组）--------------------------------------",
    sprintf("force_subgroup_vars <- %s", .index_code_bundle_quote_chr(forest$vars)),
    sprintf("force_forbid_subgroup_vars <- %s", .index_code_bundle_quote_chr(forest$forbid)),
    sprintf("force_age_cutoff <- %s", .index_code_bundle_quote_scalar(forest$age_cutoff, "45")),
    sprintf("force_subgroup_min_n <- %s", .index_code_bundle_quote_scalar(forest$min_n, "10")),
    sprintf("force_forest_xlim <- %s", .index_code_bundle_quote_num(forest$forest_xlim)),
    "force_forest_ticks_at <- NULL  # 自动刻度；可改成 c(0.5, 1, 2, 4)",
    sprintf("force_forest_xlim_max <- %s", .index_code_bundle_quote_scalar(forest$forest_xlim_max, "10")),
    sprintf("force_forest_base_size <- %s", .index_code_bundle_quote_scalar(forest$forest_base_size, "9")),
    sprintf(
      "force_forest_x_trans <- %s",
      if (nzchar(as.character(forest$forest_x_trans %||% "")[1L])) {
        .index_code_bundle_quote_chr(forest$forest_x_trans)
      } else {
        '"log"'
      }
    ),
    sprintf("force_forest_n_source <- %s", .index_code_bundle_quote_chr(forest$forest_n_source %||% "full_stratum")),
    sprintf("force_continuous_index_mode <- %s", .index_code_bundle_quote_chr(forest$continuous_index_mode %||% "highest_vs_lowest")),
    sprintf("force_subgroup_adjust_covariates <- %s", .index_code_bundle_quote_chr(forest$adjust_covariates %||% character(0))),
    "# 重跑森林图: Rscript run.R --blocks subgroup_prognosis",
    "# -------------------------------------------------------------------------",
    "",
    "if (!exists('%||%', mode = 'function')) {",
    "  `%||%` <- function(x, y) if (is.null(x)) y else x",
    "}",
    "",
    "code_bundle_apply <- function(config) {",
    "  if (!isTRUE(apply_overrides_to_config)) return(config)",
    "  m1 <- as.character(force_model1_factors %||% character(0))",
    "  m2 <- as.character(force_model2_factors %||% character(0))",
    "  m1 <- m1[nzchar(m1)]; m2 <- m2[nzchar(m2)]",
    "  if (!length(m2) && length(m1)) m2 <- m1",
    "  if (is.null(config$analysis_models)) config$analysis_models <- list()",
    "  if (length(m1)) config$analysis_models$model1_factors <- m1",
    "  if (length(m2)) config$analysis_models$model2_factors <- m2",
    "  for (nm in c('rcs_prognosis','rcs_incidence','cox_ml_continuous_batch',",
    "               'cox_quartile','cox_tertile','cox_binary')) {",
    "    if (is.null(config[[nm]])) next",
    "    if (length(m1)) config[[nm]]$model1_factors <- m1",
    "    if (length(m2)) config[[nm]]$model2_factors <- m2",
    "  }",
    "  mf <- as.character(force_ml_features %||% character(0))",
    "  mf <- mf[nzchar(mf)]",
    "  if (length(mf)) {",
    "    if (is.null(config$feature_selection)) config$feature_selection <- list()",
    "    config$feature_selection$force_final_features <- mf",
    "  }",
    "  sg_vars <- as.character(force_subgroup_vars %||% character(0))",
    "  sg_vars <- sg_vars[nzchar(sg_vars)]",
    "  forbid <- as.character(force_forbid_subgroup_vars %||% character(0))",
    "  forbid <- forbid[nzchar(forbid)]",
    "  fx <- suppressWarnings(as.numeric(force_forest_xlim %||% numeric(0)))",
    "  fx <- fx[is.finite(fx)]",
    "  ft <- if (exists('force_forest_ticks_at')) {",
    "    suppressWarnings(as.numeric(force_forest_ticks_at))",
    "  } else numeric(0)",
    "  ft <- ft[is.finite(ft)]",
    "  for (nm in c('subgroup','subgroup_prognosis','subgroup_incidence')) {",
    "    if (is.null(config[[nm]])) config[[nm]] <- list()",
    "    if (length(sg_vars)) {",
    "      config[[nm]]$required_subgroup_vars <- sg_vars",
    "      config[[nm]]$locked_subgroup_vars <- sg_vars",
    "      config[[nm]]$vars <- sg_vars",
    "    }",
    "    if (length(forbid)) config[[nm]]$forbid_subgroup_vars <- forbid",
    "    if (exists('force_age_cutoff') && is.finite(suppressWarnings(as.numeric(force_age_cutoff)[1L])))",
    "      config[[nm]]$age_cutoff <- as.numeric(force_age_cutoff)[1L]",
    "    if (exists('force_subgroup_min_n') && is.finite(suppressWarnings(as.numeric(force_subgroup_min_n)[1L])))",
    "      config[[nm]]$min_n <- as.numeric(force_subgroup_min_n)[1L]",
    "    if (length(fx) >= 2L) config[[nm]]$forest_xlim <- fx[1:2]",
    "    if (length(ft) >= 2L) config[[nm]]$forest_ticks_at <- ft",
    "    if (exists('force_forest_xlim_max') && is.finite(suppressWarnings(as.numeric(force_forest_xlim_max)[1L])))",
    "      config[[nm]]$forest_xlim_max <- as.numeric(force_forest_xlim_max)[1L]",
    "    if (exists('force_forest_base_size') && is.finite(suppressWarnings(as.numeric(force_forest_base_size)[1L])))",
    "      config[[nm]]$forest_base_size <- as.numeric(force_forest_base_size)[1L]",
    "    xt <- as.character(force_forest_x_trans %||% '')[1L]",
    "    if (nzchar(xt)) config[[nm]]$forest_x_trans <- xt",
    "    ns <- as.character(force_forest_n_source %||% '')[1L]",
    "    if (nzchar(ns)) config[[nm]]$forest_n_source <- ns",
    "    cim <- as.character(force_continuous_index_mode %||% '')[1L]",
    "    if (nzchar(cim)) config[[nm]]$continuous_index_mode <- cim",
    "    adj <- as.character(force_subgroup_adjust_covariates %||% character(0))",
    "    adj <- adj[nzchar(trimws(adj))]",
    "    if (length(adj)) config[[nm]]$adjust_covariates <- adj",
    "  }",
    "  invisible(config)",
    "}"
  )
  writeLines(ov, file.path(code_dir, "00_config_overrides.R"))

  run_r <- c(
    "#!/usr/bin/env Rscript",
    "# 单库平链（all-vars ML）可改协变量 / 单步重跑入口",
    "# 用法:",
    "#   Rscript run.R --blocks subgroup_prognosis",
    "#   Rscript run.R --blocks rcs_prognosis,subgroup_prognosis",
    "#   Rscript run.R --from ml_feature_selection_bundle --to performance_ml",
    "#   Rscript run.R --blocks subgroup_prognosis --out D:/rerun_forest_v1",
    "#   Rscript run.R --dry-run --blocks shap",
    "# 警告: 不要轻易 --from imputation（会改分析人数）",
    "",
    "args <- commandArgs(trailingOnly = TRUE)",
    "opts <- list(from = NULL, to = NULL, blocks = NULL, out = NULL,",
    "             patch_ck = TRUE, dry_run = FALSE)",
    "i <- 1L",
    "while (i <= length(args)) {",
    "  a <- args[[i]]",
    "  if (a == '--from' && i < length(args)) { opts$from <- args[[i+1L]]; i <- i+2L",
    "  } else if (a == '--to' && i < length(args)) { opts$to <- args[[i+1L]]; i <- i+2L",
    "  } else if ((a == '--blocks' || a == '--only') && i < length(args)) {",
    "    opts$blocks <- trimws(strsplit(args[[i+1L]], ',', fixed = TRUE)[[1L]]); i <- i+2L",
    "  } else if ((a == '--out' || a == '--outdir') && i < length(args)) {",
    "    opts$out <- args[[i+1L]]; i <- i+2L",
    "  } else if (a == '--no-patch-ck') { opts$patch_ck <- FALSE; i <- i+1L",
    "  } else if (a == '--dry-run') { opts$dry_run <- TRUE; i <- i+1L",
    "  } else { i <- i+1L }",
    "}",
    "",
    "code_dir <- tryCatch({",
    "  ca <- commandArgs(trailingOnly = FALSE)",
    "  f <- grep('^--file=', ca, value = TRUE)",
    "  if (length(f)) dirname(normalizePath(sub('^--file=', '', f[1L]), winslash = '/'))",
    "  else normalizePath(getwd(), winslash = '/')",
    "}, error = function(e) normalizePath(getwd(), winslash = '/'))",
    "",
    "source(file.path(code_dir, 'paths.R'), local = FALSE)",
    "source(file.path(code_dir, '00_config_overrides.R'), local = FALSE)",
    "",
    "if (.Platform$OS.type != 'windows') {",
    "  .cb_nix <- function(p) {",
    "    p <- gsub('\\\\\\\\', '/', as.character(p)[1L])",
    "    if (grepl('^[A-Za-z]:/', p)) {",
    "      drv <- tolower(substr(p, 1L, 1L))",
    "      rest <- substring(p, 4L)",
    "      return(paste0('/mnt/', drv, '/', rest))",
    "    }",
    "    p",
    "  }",
    "  CODE_BUNDLE_PROJECT_ROOT <<- .cb_nix(CODE_BUNDLE_PROJECT_ROOT)",
    "  CODE_BUNDLE_ENGINE_ROOT <<- .cb_nix(CODE_BUNDLE_ENGINE_ROOT)",
    "  CODE_BUNDLE_INDEX_ROOT <<- .cb_nix(CODE_BUNDLE_INDEX_ROOT)",
    "  CODE_BUNDLE_STUDY_CONFIG <<- .cb_nix(CODE_BUNDLE_STUDY_CONFIG)",
    "  CODE_BUNDLE_ENTRY <<- .cb_nix(CODE_BUNDLE_ENTRY)",
    "}",
    "if (.Platform$OS.type == 'windows') {",
    "  .cb_win <- function(p) {",
    "    p <- gsub('\\\\\\\\', '/', as.character(p)[1L])",
    "    if (grepl('^/mnt/[A-Za-z]/', p)) {",
    "      drv <- toupper(substr(p, 6L, 6L))",
    "      rest <- substring(p, 8L)",
    "      return(paste0(drv, ':/', rest))",
    "    }",
    "    p",
    "  }",
    "  CODE_BUNDLE_PROJECT_ROOT <<- .cb_win(CODE_BUNDLE_PROJECT_ROOT)",
    "  CODE_BUNDLE_ENGINE_ROOT <<- .cb_win(CODE_BUNDLE_ENGINE_ROOT)",
    "  CODE_BUNDLE_INDEX_ROOT <<- .cb_win(CODE_BUNDLE_INDEX_ROOT)",
    "  CODE_BUNDLE_STUDY_CONFIG <<- .cb_win(CODE_BUNDLE_STUDY_CONFIG)",
    "  CODE_BUNDLE_ENTRY <<- .cb_win(CODE_BUNDLE_ENTRY)",
    "}",
    "Sys.setenv(MEDICAL_BLOCKS_ROOT = CODE_BUNDLE_ENGINE_ROOT)",
    "",
    "# --blocks 无 --from：自动从前一 block 加载 checkpoint",
    "if (length(opts$blocks) && (is.null(opts$from) || !nzchar(as.character(opts$from)[1L]))) {",
    "  menu_p <- file.path(code_dir, 'blocks_menu.txt')",
    "  if (file.exists(menu_p)) {",
    "    menu <- trimws(readLines(menu_p, warn = FALSE))",
    "    menu <- menu[nzchar(menu) & !startsWith(menu, '#')]",
    "    first <- as.character(opts$blocks[[1L]])[1L]",
    "    idx <- match(first, menu)",
    "    if (!is.na(idx) && idx > 1L) {",
    "      opts$from <- menu[[idx - 1L]]",
    "      message('自动 --from ', opts$from, '（加载 ck 后再跑 ', first, '）')",
    "    }",
    "  }",
    "}",
    "",
    "tmp_cfg <- file.path(",
    "  CODE_BUNDLE_PROJECT_ROOT,",
    "  paste0('._code_bundle_', CODE_BUNDLE_INDEX, '_cfg.R')",
    ")",
    "writeLines(c(",
    "  sprintf('source(%s, local = FALSE)', deparse(CODE_BUNDLE_STUDY_CONFIG)),",
    "  sprintf('source(%s, local = FALSE)', deparse(file.path(code_dir, '00_config_overrides.R'))),",
    "  'if (exists(\"code_bundle_apply\", mode = \"function\")) config <- code_bundle_apply(config)',",
    "  '.out <- Sys.getenv(\"MEDICAL_BLOCKS_RERUN_OUT\", unset = \"\")',",
    "  'if (nzchar(.out)) {',",
    "  '  config$project$output_dir <- .out',",
    "  '  if (exists(\"pipeline\") && is.list(pipeline)) {',",
    "  '    if (is.null(pipeline$checkpoint)) pipeline$checkpoint <- list()',",
    "  '    pipeline$checkpoint$enable <- FALSE',",
    "  '  }',",
    "  '}'",
    "), tmp_cfg)",
    "on.exit(unlink(tmp_cfg), add = TRUE)",
    "",
    "if (!is.null(opts$out) && nzchar(as.character(opts$out)[1L])) {",
    "  out_dir <- as.character(opts$out)[1L]",
    "  if (!grepl('^[A-Za-z]:|^\\\\\\\\|^/', out_dir) && !grepl('^//', out_dir)) {",
    "    out_dir <- file.path(code_dir, out_dir)",
    "  }",
    "  out_dir <- gsub('\\\\\\\\', '/', out_dir)",
    "  if (.Platform$OS.type != 'windows' && grepl('^[A-Za-z]:/', out_dir)) {",
    "    out_dir <- paste0('/mnt/', tolower(substr(out_dir, 1L, 1L)), '/', substring(out_dir, 4L))",
    "  }",
    "  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)",
    "  out_dir <- normalizePath(out_dir, winslash = '/', mustWork = FALSE)",
    "  Sys.setenv(MEDICAL_BLOCKS_RERUN_OUT = out_dir)",
    "  opts$patch_ck <- FALSE",
    "  message('输出目录(--out): ', out_dir, '（不覆盖主结果；已关闭 patch ck）')",
    "} else {",
    "  Sys.unsetenv('MEDICAL_BLOCKS_RERUN_OUT')",
    "}",
    "",
    "cmd <- c(CODE_BUNDLE_ENTRY, '--config', tmp_cfg)",
    "if (!is.null(opts$from) && nzchar(opts$from)) cmd <- c(cmd, '--from', opts$from)",
    "if (!is.null(opts$to) && nzchar(opts$to)) cmd <- c(cmd, '--to', opts$to)",
    "if (!is.null(opts$blocks) && length(opts$blocks)) {",
    "  cmd <- c(cmd, '--only', paste(opts$blocks, collapse = ','))",
    "}",
    "message('Rscript ', paste(shQuote(cmd), collapse = ' '))",
    "if (isTRUE(opts$dry_run)) quit(save = 'no', status = 0)",
    "",
    "if (isTRUE(opts$patch_ck) && isTRUE(patch_checkpoint_covariates) &&",
    "    exists('force_model1_factors') && exists('force_model2_factors')) {",
    "  m1 <- as.character(force_model1_factors); m2 <- as.character(force_model2_factors)",
    "  m1 <- m1[nzchar(m1)]; m2 <- m2[nzchar(m2)]",
    "  ck_dir <- file.path(CODE_BUNDLE_PROJECT_ROOT, 'checkpoints')",
    "  if (dir.exists(ck_dir) && (length(m1) || length(m2))) {",
    "    for (fn in list.files(ck_dir, pattern = '\\\\.rds$', full.names = TRUE)) {",
    "      bn <- basename(fn)",
    "      if (!grepl('cox_ml|rcs_|subgroup_|multicollinearity|covariate', bn, ignore.case = TRUE)) next",
    "      obj <- tryCatch(readRDS(fn), error = function(e) NULL)",
    "      if (is.null(obj) || is.null(obj$ctx) || is.null(obj$ctx$results)) next",
    "      if (length(m1)) obj$ctx$results$Model1Factors <- m1",
    "      if (length(m2)) obj$ctx$results$Model2Factors <- m2",
    "      tryCatch(saveRDS(obj, fn), error = function(e) NULL)",
    "    }",
    "    message('已 patch checkpoint Model1/Model2（可用 --no-patch-ck 关闭）')",
    "  }",
    "}",
    "",
    "status <- system(paste(shQuote(c('Rscript', cmd)), collapse = ' '))",
    "quit(save = 'no', status = if (is.na(status)) 1L else as.integer(status))"
  )
  run_path <- file.path(code_dir, "run.R")
  writeLines(run_r, run_path)
  tryCatch(Sys.chmod(run_path, mode = "0755"), error = function(e) NULL)

  study_disp <- gsub("/", "\\\\", study_root)
  op_doc <- c(
    sprintf("# %s — 单步重跑操作说明（单库平链 / all-vars ML）", ix),
    "",
    "## 模板",
    "",
    "```powershell",
    sprintf("cd \"%s\\\\code\"", study_disp),
    "$env:MEDICAL_BLOCKS_ROOT = \"E:/01block/01Block-new-Final\"",
    "Rscript ./run.R --blocks <要跑的块>",
    "```",
    "",
    "指定输出目录（**不覆盖**主结果）：",
    "",
    "```powershell",
    "Rscript ./run.R --blocks <要跑的块> --out \"<你的目录>\"",
    "```",
    "",
    "## 例子",
    "",
    "```powershell",
    sprintf("cd \"G:/02block_result/35_EMs/ml_40395549/code\""),
    "$env:MEDICAL_BLOCKS_ROOT = \"E:/01block/01Block-new-Final\"",
    "Rscript ./run.R --blocks subgroup_prognosis",
    "Rscript ./run.R --blocks subgroup_prognosis --out \"G:/02block_result/35_EMs/reruns/forest_v1\"",
    "Rscript ./run.R --dry-run --blocks shap",
    "```",
    "",
    "## 参数说明",
    "",
    "| 参数 | 含义 |",
    "|---|---|",
    "| `--blocks <名>` | 只跑列出的 block（逗号分隔；内部映射为 `--only`） |",
    "| `--from A --to B` | 从 A 之后跑到 B（含） |",
    "| `--out <目录>` | 结果写到该目录，**不覆盖**主结果；并默认不 patch 主 ck |",
    "| `--no-patch-ck` | 禁止改主分析 checkpoint 里的 Model1/2 |",
    "| `--dry-run` | 只打印命令不执行 |",
    "",
    "## 结果在哪",
    "",
    "- **不加 `--out`**：写入课题根 `Figures` / `Tables` / `stepNN_*`",
    "- **加了 `--out`**：新表/新图写到指定目录，主结果不动；本次不写 checkpoint",
    "",
    "## 改什么文件",
    "",
    "- 只改 `00_config_overrides.R`（协变量 / 森林图 / ML 特征）",
    "- 一般不改 `paths.R`",
    "- **本课题用过的 Block 源码**在 `blocks/`（见 `blocks/MANIFEST.md`、`blocks_used.txt`）；对照用，重跑仍走引擎",
    "",
    "## 本课题实际用过的 block",
    "",
    paste(used_blks, collapse = "\n"),
    "",
    "## pipeline 全名单（可 `--blocks` 重跑）",
    "",
    paste(blks, collapse = "\n"),
    "",
    "## 常用对照",
    "",
    "| 想做的事 |命令 |",
    "|---|---|",
    "| 亚组森林图 | `subgroup_prognosis` |",
    "| RCS | `rcs_prognosis` |",
    "| KM | `km_continuous_router` |",
    "| Cox 连续特征关联 | `cox_ml_continuous_batch` |",
    "| ML 训练 / 性能 / SHAP | `ml_models_bundle` / `performance_ml` / `shap` |",
    "| Shiny | `shiny_ml_app` |",
    "",
    "## 不要随便跑（会改人数 N）",
    "",
    "- `imputation`",
    "- `train_validation`（会重划训练/验证）",
    "",
    sprintf("生成时间: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))
  )
  writeLines(op_doc, file.path(code_dir, "操作说明.md"))
  writeLines(op_doc, file.path(code_dir, "README.md"))
  writeLines(c(
    "# Block 速查",
    "",
    "完整操作见 `操作说明.md` / `README.md`。",
    "",
    paste(paste0("- `", used_blks, "`"), collapse = "\n")
  ), file.path(code_dir, "blocks_cheatsheet.md"))

  val <- index_code_bundle_validate(code_dir)
  if (!isTRUE(val$ok)) {
    if (requireNamespace("cli", quietly = TRUE)) {
      cli::cli_alert_warning(
        "单库 code 包校验未通过: {paste(val$issues, collapse = '; ')}"
      )
    }
    return(invisible(FALSE))
  }
  if (requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_success("已生成单库平链 code 包: {.file {code_dir}}")
  }
  invisible(TRUE)
}

#' 单库平链收尾写 code 包（run_pipeline 挂点）
index_code_bundle_finalize_single_pipeline <- function(study_root, config,
                                                      pipeline = NULL,
                                                      engine_root = NULL) {
  if (!.index_code_bundle_should_write_single(config, pipeline)) {
    return(invisible(FALSE))
  }
  study_root <- normalizePath(as.character(study_root)[1L], winslash = "/", mustWork = FALSE)
  if (grepl("sensitivity|\\.sensitivity_staging", study_root, ignore.case = TRUE)) {
    return(invisible(FALSE))
  }
  tryCatch({
    eng <- as.character(
      engine_root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "") %||% study_root
    )[1L]
    cb_src <- file.path(eng, "R", "index_code_bundle.R")
    if (!file.exists(cb_src)) cb_src <- file.path(study_root, "R", "index_code_bundle.R")
    if (file.exists(cb_src) && !exists("index_code_bundle_write_single_pipeline", mode = "function")) {
      source(cb_src, local = FALSE)
    }
    ok <- index_code_bundle_write_single_pipeline(
      study_root = study_root,
      config = config,
      engine_root = eng,
      pipeline = pipeline
    )
    if (!isTRUE(ok)) {
      if (requireNamespace("cli", quietly = TRUE)) {
        cli::cli_alert_warning("单库 code 包生成失败")
      }
      return(invisible(FALSE))
    }
    invisible(TRUE)
  }, error = function(e) {
    if (requireNamespace("cli", quietly = TRUE)) {
      cli::cli_alert_warning("单库 code 包生成异常: {e$message}")
    }
    invisible(FALSE)
  })
}
