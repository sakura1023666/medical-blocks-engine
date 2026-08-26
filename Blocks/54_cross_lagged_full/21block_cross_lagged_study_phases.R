###############################################################################
# 21block_cross_lagged_study_phases.R
# 交叉滞后多阶段编排（原 run/cross_lagged 下零散 phase 脚本已迁入 phases/）
# 仅由 run/cross_lagged/run_cross_lagged_frailty.R 调用。
###############################################################################

cross_lagged_phases_dir <- function(root) {
  file.path(root, "Blocks/54_cross_lagged_full/phases")
}

cross_lagged_default_study_root <- function() {
  "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747"
}

#' 课题盘同步目标（结果镜像路径）
#'
#' 优先级：
#' 1. 环境变量 CROSS_LAGGED_SYNC_ROOT
#' 2. study_root 下 CROSS_LAGGED_SYNC_ROOT / sync_to.txt
#' 3. 若 study 已在 02block_result / block_result 则自身
#' 4. 已知引擎镜像目录名 → 课题盘映射
#' 5. 默认 cross_lagged_default_study_root()（髋部课题）
cross_lagged_resolve_sync_root <- function(study_root) {
  env <- Sys.getenv("CROSS_LAGGED_SYNC_ROOT", unset = "")
  if (nzchar(env)) {
    return(normalizePath(path.expand(env), winslash = "/", mustWork = FALSE))
  }
  study_root <- as.character(study_root %||% "")[1L]
  if (!nzchar(study_root)) return(cross_lagged_default_study_root())

  for (nm in c("CROSS_LAGGED_SYNC_ROOT", "sync_to.txt", ".sync_to")) {
    f <- file.path(study_root, nm)
    if (file.exists(f)) {
      ln <- tryCatch(
        trimws(readLines(f, n = 1L, warn = FALSE, encoding = "UTF-8")[1L]),
        error = function(e) ""
      )
      if (nzchar(ln %||% "")) {
        return(normalizePath(path.expand(ln), winslash = "/", mustWork = FALSE))
      }
    }
  }

  sr_norm <- tryCatch(
    normalizePath(study_root, winslash = "/", mustWork = FALSE),
    error = function(e) study_root
  )
  if (grepl("02block_result|/block_result/", sr_norm, ignore.case = TRUE)) {
    return(sr_norm)
  }

  # 引擎 Output 镜像 → 课题盘（可扩展）
  known <- c(
    "16_Hip_fracture_cross-laged_40595747_allages" =
      "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747",
    "16_Hip_fracture_cross-laged_40595747" =
      "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747",
    "16_Patellar_fracture_cross-laged_40595747_allages" =
      "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747",
    "16_Patellar_fracture_cross-laged_40595747" =
      "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747"
  )
  bn <- basename(sr_norm)
  if (bn %in% names(known)) return(unname(known[[bn]]))

  # 默认仍回落到主课题盘（避免“跑完找不到 summary”）
  cross_lagged_default_study_root()
}

#' 将 study 产出同步到课题盘（exclude data/ 与默认 checkpoints）
#' @param no_sync TRUE 时跳过（CLI --no-sync）
cross_lagged_sync_to_project_disk <- function(root, study_root, no_sync = FALSE) {
  if (isTRUE(no_sync) ||
      identical(Sys.getenv("CROSS_LAGGED_NO_SYNC", ""), "1")) {
    cli::cli_alert_info("课题盘同步已跳过 (--no-sync / CROSS_LAGGED_NO_SYNC=1)")
    return(invisible(NULL))
  }
  if (is.null(study_root) || !nzchar(as.character(study_root)[1L])) {
    return(invisible(NULL))
  }
  study_root <- tryCatch(
    normalizePath(study_root, winslash = "/", mustWork = TRUE),
    error = function(e) {
      cli::cli_alert_warning("同步跳过：study_root 无效 ({conditionMessage(e)})")
      return(NULL)
    }
  )
  if (is.null(study_root)) return(invisible(NULL))

  dest <- cross_lagged_resolve_sync_root(study_root)
  dest_n <- tryCatch(
    normalizePath(dest, winslash = "/", mustWork = FALSE),
    error = function(e) dest
  )
  src_n <- normalizePath(study_root, winslash = "/", mustWork = FALSE)
  if (identical(src_n, dest_n) || identical(src_n, path.expand(dest))) {
    cli::cli_alert_info("工作目录已在课题盘，无需镜像: {.path {src_n}}")
    return(invisible(src_n))
  }

  # 确保指针文件存在，便于 shell 与后续人工查找
  ptr <- file.path(study_root, "CROSS_LAGGED_SYNC_ROOT")
  tryCatch(
    writeLines(dest_n, ptr),
    error = function(e) invisible(NULL)
  )

  cli::cli_h2("同步到课题盘")
  cli::cli_alert_info("SRC  {.path {src_n}}")
  cli::cli_alert_info("DEST {.path {dest_n}}")
  # 课题盘路径常含空格：DEST 只走 env，避免 argv 拆分
  Sys.setenv(CROSS_LAGGED_SYNC_ROOT = dest_n)
  ok <- tryCatch(
    {
      cross_lagged_run_phase_bash(
        root, "sync_to_project_disk.sh", src_n
      )
      TRUE
    },
    error = function(e) {
      cli::cli_alert_warning("课题盘同步失败（不中断流水线）: {conditionMessage(e)}")
      FALSE
    }
  )
  if (isTRUE(ok)) {
    cli::cli_alert_success("已同步 → {.path {dest_n}}/summary_result")
  }
  invisible(dest_n)
}

#' 从单库 config 的 output_dir 推断 study_root（phase1_* 的上一级）
cross_lagged_infer_study_root_from_config <- function(config) {
  od <- config$project$output_dir %||% ""
  if (!nzchar(od)) return(NULL)
  od <- normalizePath(od, winslash = "/", mustWork = FALSE)
  bn <- basename(od)
  if (grepl("^phase1_", bn) || grepl("^phase3_", bn) || grepl("^phase2_", bn)) {
    return(dirname(od))
  }
  # 已是 study 根
  if (dir.exists(file.path(od, "summary_result")) ||
      file.exists(file.path(od, "CROSS_LAGGED_SYNC_ROOT")) ||
      length(list.files(od, pattern = "^config_phase1_")) > 0L) {
    return(od)
  }
  dirname(od)
}

#' 引擎根：兼容 run/cross_lagged、Blocks/54/.../phases 及 MEDICAL_BLOCKS_ROOT
cross_lagged_resolve_engine_root <- function(script_path = NULL) {
  if (is.null(script_path) || !nzchar(script_path)) {
    ca <- commandArgs(trailingOnly = FALSE)
    f <- grep("^--file=", ca, value = TRUE)
    if (length(f)) {
      script_path <- normalizePath(dirname(sub("^--file=", "", f[[1L]])), winslash = "/")
    } else {
      script_path <- normalizePath(getwd(), winslash = "/")
    }
  }
  script_path <- normalizePath(script_path, winslash = "/", mustWork = FALSE)
  # run/cross_lagged
  if (basename(script_path) == "cross_lagged" &&
      basename(dirname(script_path)) == "run") {
    return(normalizePath(file.path(script_path, "..", ".."), winslash = "/"))
  }
  # Blocks/54_cross_lagged_full/phases
  if (basename(script_path) == "phases" &&
      grepl("54_cross_lagged", basename(dirname(script_path)), fixed = TRUE)) {
    return(normalizePath(file.path(script_path, "..", "..", ".."), winslash = "/"))
  }
  # Blocks/54_cross_lagged_full/pilots
  if (basename(script_path) == "pilots" &&
      grepl("54_cross_lagged", basename(dirname(script_path)), fixed = TRUE)) {
    return(normalizePath(file.path(script_path, "..", "..", ".."), winslash = "/"))
  }
  # Blocks/54_cross_lagged_full
  if (grepl("54_cross_lagged", basename(script_path), fixed = TRUE)) {
    return(normalizePath(file.path(script_path, "..", ".."), winslash = "/"))
  }
  # 模板 configs/templates
  if (basename(script_path) == "templates" &&
      basename(dirname(script_path)) == "configs") {
    return(normalizePath(file.path(script_path, "..", ".."), winslash = "/"))
  }
  env <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (nzchar(env) && dir.exists(env)) {
    return(normalizePath(env, winslash = "/"))
  }
  normalizePath(getwd(), winslash = "/")
}

.cl_rscript_bin <- function() {
  file.path(R.home("bin"), "Rscript")
}

#' 运行 phases/ 下 R 脚本（子进程，保留原 CLI 语义）
cross_lagged_run_phase_rscript <- function(root, phase_file, args = character()) {
  sc <- file.path(cross_lagged_phases_dir(root), phase_file)
  if (!file.exists(sc)) stop("缺少 phase 脚本: ", sc, call. = FALSE)
  # 路径中有空格时，额外用环境变量传 study_root（phase 脚本优先读）
  sr_i <- match("--study-root", args)
  if (!is.na(sr_i) && sr_i < length(args)) {
    Sys.setenv(CROSS_LAGGED_STUDY_ROOT = as.character(args[[sr_i + 1L]]))
  }
  status <- system2(.cl_rscript_bin(), args = c(sc, as.character(args)), wait = TRUE)
  if (!is.null(status) && !identical(as.integer(status), 0L)) {
    stop(sprintf("phase 失败 (%s) exit=%s", phase_file, as.character(status)), call. = FALSE)
  }
  invisible(TRUE)
}

#' 运行 phases/ 下 bash 脚本
cross_lagged_run_phase_bash <- function(root, sh_file, args = character()) {
  sc <- file.path(cross_lagged_phases_dir(root), sh_file)
  if (!file.exists(sc)) stop("缺少 phase shell: ", sc, call. = FALSE)
  if (length(args) >= 1L && nzchar(args[[1L]])) {
    Sys.setenv(CROSS_LAGGED_STUDY_ROOT = as.character(args[[1L]]))
  }
  status <- system2("bash", args = c(sc, as.character(args)), wait = TRUE)
  if (!is.null(status) && !identical(as.integer(status), 0L)) {
    stop(sprintf("phase shell 失败 (%s) exit=%s", sh_file, as.character(status)), call. = FALSE)
  }
  invisible(TRUE)
}

# ── 各阶段薄封装 ────────────────────────────────────────────────────────────

cross_lagged_phase_vif_pooled <- function(root, study_root, skip_vif = FALSE) {
  args <- c("--study-root", study_root)
  if (isTRUE(skip_vif)) args <- c(args, "--pooled-only")
  cross_lagged_run_phase_rscript(root, "phase_vif_pooled.R", args)
}

cross_lagged_phase_post_vif <- function(root, study_root, only = NULL) {
  args <- c("--study-root", study_root)
  if (!is.null(only) && length(only)) args <- c(args, "--only", paste(only, collapse = ","))
  cross_lagged_run_phase_rscript(root, "phase_post_vif.R", args)
}

cross_lagged_phase_relock_logistic <- function(root, study_root, only = NULL, rcs_only = FALSE) {
  args <- c("--study-root", study_root)
  if (!is.null(only) && length(only)) args <- c(args, "--only", paste(only, collapse = ","))
  if (isTRUE(rcs_only)) args <- c(args, "--rcs-only")
  cross_lagged_run_phase_rscript(root, "phase_relock_logistic.R", args)
}

cross_lagged_phase_long_figs <- function(root, study_root,
                                        sims = 200L,
                                        only = NULL,
                                        change_only = FALSE,
                                        rescreen_med_covars = FALSE,
                                        with_pooled = FALSE) {
  args <- c("--study-root", study_root, "--sims", as.character(sims))
  if (!is.null(only) && length(only)) args <- c(args, "--only", paste(only, collapse = ","))
  if (isTRUE(change_only)) args <- c(args, "--change-only")
  if (isTRUE(rescreen_med_covars)) args <- c(args, "--rescreen-mediation-covars")
  if (isTRUE(with_pooled)) args <- c(args, "--with-pooled") else args <- c(args, "--no-pooled")
  cross_lagged_run_phase_rscript(root, "phase_long_figs.R", args)
}

cross_lagged_phase_long_mediation <- function(root, study_root, sims = 200L) {
  args <- c("--study-root", study_root, "--sims", as.character(sims))
  cross_lagged_run_phase_rscript(root, "phase_long_mediation.R", args)
}

cross_lagged_phase_subgroup_harmonize <- function(root, study_root, only = NULL) {
  args <- c("--study-root", study_root)
  if (!is.null(only) && length(only)) args <- c(args, "--only", paste(only, collapse = ","))
  cross_lagged_run_phase_rscript(root, "phase_subgroup_harmonize.R", args)
}

cross_lagged_study_is_hip <- function(study_root) {
  study_root <- as.character(study_root %||% "")[1L]
  if (!nzchar(study_root) || !dir.exists(study_root)) return(FALSE)
  allages <- dir.exists(file.path(study_root, "phase1_CHARLS_allages"))
  hrs <- dir.exists(file.path(study_root, "phase1_HRS_allages")) ||
    dir.exists(file.path(study_root, "phase1_HRS"))
  circ <- file.exists(file.path(study_root, "config_long_panel.R")) &&
    any(grepl("circadian_index_var",
              readLines(file.path(study_root, "config_long_panel.R"), warn = FALSE),
              fixed = TRUE))
  isTRUE(allages && hrs && !circ)
}

cross_lagged_phase_summary_collect <- function(root, study_root, no_sync = FALSE) {
  cross_lagged_run_phase_bash(root, "collect_summary_result.sh", study_root)
  # 髋部 reorder 白名单会丢掉 ePWV/昼夜图名；仅髋部布局才跑
  if (isTRUE(cross_lagged_study_is_hip(study_root))) {
    cross_lagged_run_phase_bash(root, "reorder_summary_result.sh", study_root)
  } else {
    cli::cli_alert_info("非髋部布局：跳过 reorder，保留本课题图/表原名")
  }
  # summary 必刷课题盘
  cross_lagged_sync_to_project_disk(root, study_root, no_sync = no_sync)
  invisible(TRUE)
}

cross_lagged_phase_summary_prune_logistic <- function(root, study_root) {
  cross_lagged_run_phase_bash(root, "prune_summary_nonsummary_logistic.sh", study_root)
  # prune 脚本末尾原指引 re-run reorder
  cross_lagged_run_phase_bash(root, "reorder_summary_result.sh", study_root)
  invisible(TRUE)
}

cross_lagged_phase_study_batch <- function(root, config_path = NULL,
                                          workers = NULL,
                                          shared_only = FALSE,
                                          only_unit = NULL,
                                          skip_existing = TRUE) {
  args <- character(0)
  if (!is.null(config_path) && nzchar(config_path))
    args <- c(args, "--config", config_path)
  if (!is.null(workers)) args <- c(args, "--workers", as.character(workers))
  if (isTRUE(shared_only)) args <- c(args, "--shared-only")
  if (!is.null(only_unit) && length(only_unit))
    args <- c(args, "--only-unit", paste(only_unit, collapse = ","))
  if (!isTRUE(skip_existing)) args <- c(args, "--no-skip")
  cross_lagged_run_phase_rscript(root, "phase_study_batch.R", args)
}

cross_lagged_phase_pub_figs <- function(root, study_root, no_sync = FALSE) {
  args <- c("--study-root", study_root)
  if (isTRUE(no_sync)) args <- c(args, "--no-sync")
  cross_lagged_run_phase_rscript(root, "phase_pub_figs_s4s5_f4.R", args)
}

cross_lagged_phase_sensitivity <- function(root, study_root, only = NULL,
                                           scenario = NULL, no_sync = FALSE) {
  args <- c("--study-root", study_root)
  if (!is.null(only) && length(only) && nzchar(as.character(only)[1L])) {
    args <- c(args, "--only", paste(only, collapse = ","))
  }
  if (!is.null(scenario) && length(scenario) && nzchar(as.character(scenario)[1L])) {
    args <- c(args, "--scenario", paste(scenario, collapse = ","))
  }
  if (isTRUE(no_sync)) args <- c(args, "--no-sync")
  cross_lagged_run_phase_rscript(root, "phase_sensitivity.R", args)
}

cross_lagged_phase_midterm <- function(root, study_root, engine = c("xelatex", "rmd")) {
  engine <- match.arg(engine)
  args <- c("--study-root", study_root)
  sc <- if (identical(engine, "xelatex")) {
    "phase_render_midterm_xelatex.R"
  } else {
    "phase_render_midterm_rmd.R"
  }
  cross_lagged_run_phase_rscript(root, sc, args)
}

#' 按名称调度（供入口 CLI）
cross_lagged_dispatch_phase <- function(root, phase, opts = list()) {
  study_root <- opts$study_root %||% cross_lagged_default_study_root()
  only <- opts$only
  no_sync <- isTRUE(opts$no_sync)
  # CLI / env 注入同步目标
  if (!is.null(opts$sync_root) && nzchar(as.character(opts$sync_root)[1L])) {
    Sys.setenv(CROSS_LAGGED_SYNC_ROOT = as.character(opts$sync_root)[1L])
  }
  phase <- tolower(trimws(as.character(phase)[[1L]]))
  cli::cli_h1("Cross-lagged phase: {phase}")
  switch(
    phase,
    "vif_pooled" = ,
    "phase2" = ,
    "phase2_vif" = cross_lagged_phase_vif_pooled(
      root, study_root, skip_vif = isTRUE(opts$pooled_only)
    ),
    "post_vif" = ,
    "phase3_post" = ,
    "phase3_post_vif" = cross_lagged_phase_post_vif(root, study_root, only = only),
    "relock" = ,
    "relock_logistic" = ,
    "phase3_relock" = cross_lagged_phase_relock_logistic(
      root, study_root, only = only, rcs_only = isTRUE(opts$rcs_only)
    ),
    "long" = ,
    "long_figs" = ,
    "phase3_long" = ,
    "cross_lagged_figs" = cross_lagged_phase_long_figs(
      root, study_root,
      sims = opts$sims %||% 200L,
      only = only,
      change_only = isTRUE(opts$change_only),
      rescreen_med_covars = isTRUE(opts$rescreen_med_covars),
      with_pooled = isTRUE(opts$with_pooled)
    ),
    "long_mediation" = ,
    "mediation" = cross_lagged_phase_long_mediation(
      root, study_root, sims = opts$sims %||% 200L
    ),
    "subgroup" = ,
    "fig3" = ,
    "subgroup_harmonize" = cross_lagged_phase_subgroup_harmonize(
      root, study_root, only = only
    ),
    "summary" = ,
    "collect" = {
      return(cross_lagged_phase_summary_collect(
        root, study_root, no_sync = no_sync
      ))
    },
    "prune" = ,
    "prune_logistic" = cross_lagged_phase_summary_prune_logistic(root, study_root),
    "pub_figs" = ,
    "pub" = ,
    "s4s5_f4" = cross_lagged_phase_pub_figs(
      root, study_root, no_sync = no_sync
    ),
    "sensitivity" = ,
    "sens" = cross_lagged_phase_sensitivity(
      root, study_root, only = only,
      scenario = opts$scenario, no_sync = no_sync
    ),
    "midterm" = ,
    "midterm_pdf" = ,
    "report" = cross_lagged_phase_midterm(root, study_root, engine = "xelatex"),
    "midterm_rmd" = ,
    "midterm_rmarkdown" = cross_lagged_phase_midterm(root, study_root, engine = "rmd"),
    "batch" = cross_lagged_phase_study_batch(
      root,
      config_path = opts$config,
      workers = opts$workers,
      shared_only = isTRUE(opts$shared_only),
      only_unit = opts$only_unit,
      skip_existing = if (is.null(opts$skip_existing)) TRUE else isTRUE(opts$skip_existing)
    ),
    "sync" = {
      # 仅同步：不重跑分析
      return(cross_lagged_sync_to_project_disk(root, study_root, no_sync = no_sync))
    },
    stop(
      "未知 --phase: ", phase, "\n",
      "可用: vif_pooled | post_vif | relock | long_figs | long_mediation | ",
      "subgroup | summary | prune | pub_figs | sensitivity | midterm | midterm_rmd | batch | sync",
      call. = FALSE
    )
  )
  # 产出阶段：自动收图+表进 summary_result，再镜像课题盘
  if (!phase %in% c(
    "summary", "collect", "sync", "prune", "prune_logistic",
    "midterm", "midterm_pdf", "report", "midterm_rmd", "midterm_rmarkdown"
  )) {
    tryCatch(
      cross_lagged_run_phase_bash(root, "collect_summary_result.sh", study_root),
      error = function(e)
        cli::cli_alert_warning("自动汇总失败（分析已完成）: {conditionMessage(e)}")
    )
  }
  if (!phase %in% c("summary", "collect", "sync")) {
    cross_lagged_sync_to_project_disk(root, study_root, no_sync = no_sync)
  }
  invisible(TRUE)
}
