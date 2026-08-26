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
    # 同目录公共文件（mediation / logistic common 等）
    if (!is.na(rel) && file.exists(src)) {
      sibs <- list.files(dirname(src), pattern = "^00", full.names = TRUE)
      sibs <- sibs[
        grepl("\\.[Rr]$", sibs) &
          grepl("common|shared|logistic|mediation", basename(sibs), ignore.case = TRUE)
      ]
      for (sp in sibs) {
        sp_n <- normalizePath(sp, winslash = "/", mustWork = FALSE)
        already <- normalizePath(copied_files, winslash = "/", mustWork = FALSE)
        if (sp_n %in% already) next
        .copy_one(sp, paste0(bn, "+common"))
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
      if (length(bl) && n_r < length(bl)) {
        issues <- c(
          issues,
          sprintf(
            "blocks_used.txt 列 %d 个 block，但仅镜像 %d 个 .R 文件",
            length(bl), n_r
          )
        )
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
    forest_x_trans = as.character(sg$forest_x_trans %||% "log")[1L]
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
  worker_rel <- if (is_prog) {
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

  # paths.R — 课题 config 优先 survival / incidence，再回落 config.R
  study_cfg_candidates <- c(
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
  if (!nzchar(study_cfg %||% "")) {
    study_cfg <- file.path(project_root, if (is_prog) "config_survival.R" else "config.R")
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
    "  for (nm in c('cox_quartile','cox_tertile','cox_binary',",
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
