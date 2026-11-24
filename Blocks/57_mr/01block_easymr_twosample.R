###############################################################################
#  easymr_twosample — 调用本机 easyMR 做两样本孟德尔随机化
#
#  register_block: "easymr_twosample"
#  典型位置: 数据已下载之后单独跑，不插入发病/预后主链
#  运行环境: Windows R 4.2.2（C:/Program Files/R/R-4.2.2）+ D:/easyMR
#            当前流水线的 Linux R 只负责把脚本交给这个 Rscript.exe
#
#  config$easymr = list(
#    rscript = "C:/Program Files/R/R-4.2.2/bin/Rscript.exe",
#    mr_database = "D:/easyMR/MRmyy_refer_file",
#    exposure_dir = "E:/孟德尔/1暴露数据",
#    exposure_out_dir = "E:/孟德尔/复合指标",
#    outcome_raw = "E:/孟德尔/1结局数据/finngen_R12_NAFLD.gz",
#    outcome_dir = "E:/孟德尔/结局",
#    outcome_rds = NULL,          # 已有 rds 时填路径，则不再 trans_finn_data
#    outcome_kind = "finn",       # finn | rds
#    outcome_label = "NAFLD",
#    save_root = "E:/孟德尔/MR/study_id",
#    full_mr = TRUE,              # FALSE 只做初步 IVW，不进入删点/RadialMR
#    force_reformat = FALSE,
#    dry_run = FALSE,
#    clump_kb = 10000, clump_r2 = 0.001, pval_threshold = 5e-8,
#    proxies = TRUE, pop = "EUR", action = 2L, run_steiger = TRUE,
#    exposures = list(
#      list(file = "GCST90309892.h.tsv.gz", id = "AST_GCST90309892",
#           label = "AST", N = 174488L)
#    )
#  )
#  写出: save_root/<id>/ 下 easyMR 原生产物，以及 save_root/easymr_status.txt
#  ctx$results$easymr_twosample: status_file, save_root, runner
###############################################################################

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x
}

.easymr_slash <- function(p) gsub("\\\\", "/", p)

.easymr_to_win <- function(p) {
  p <- .easymr_slash(p)
  if (grepl("^/mnt/[a-zA-Z]/", p)) {
    paste0(toupper(substr(p, 6, 6)), ":", substring(p, 7))
  } else {
    p
  }
}

.easymr_to_host <- function(p) {
  p <- .easymr_slash(p)
  if (grepl("^[A-Za-z]:/", p)) {
    alt <- paste0("/mnt/", tolower(substr(p, 1, 1)), substring(p, 3))
    if (file.exists(alt)) return(alt)
  }
  p
}

.easymr_r_quote <- function(x) {
  x <- enc2utf8(as.character(x))
  cps <- utf8ToInt(x)
  parts <- vapply(cps, function(cp) {
    if (cp == 34L) return("\\\"")
    if (cp == 92L) return("\\\\")
    if (cp >= 32L && cp < 127L) return(intToUtf8(cp))
    sprintf("\\u%04x", cp)
  }, character(1))
  paste0("\"", paste(parts, collapse = ""), "\"")
}

.easymr_col_aliases <- function() {
  list(
    SNP = c("rsid", "rs_id", "SNP", "snp", "hm_rsid", "markername", "Name", "name", "variant_id", "rs_id_all"),
    chr = c("chromosome", "chrom", "chr", "hm_chrom"),
    pos = c("base_pair_location", "pos", "bp", "position", "hm_pos"),
    beta = c("beta", "hm_beta"),
    se = c("standard_error", "se", "stderr"),
    effect_allele = c("effect_allele", "ea", "hm_effect_allele"),
    other_allele = c("other_allele", "nea", "hm_other_allele"),
    pval = c("p_value", "pval", "p", "pvalue"),
    eaf = c("effect_allele_frequency", "eaf", "freq", "hm_effect_allele_frequency")
  )
}

.easymr_peek_table <- function(path, n = 40L) {
  con <- if (grepl("\\.gz$", path, ignore.case = TRUE)) gzfile(path, "rt") else file(path, "rt")
  on.exit(close(con), add = TRUE)
  header <- readLines(con, n = 1L, warn = FALSE)
  if (!length(header) || !nzchar(header)) stop("暴露文件没有表头: ", path)
  sep <- if (grepl("\t", header, fixed = TRUE)) "\t" else ","
  cols <- gsub("^\"|\"$", "", trimws(strsplit(header, sep, fixed = TRUE)[[1]]))
  rows <- readLines(con, n = n, warn = FALSE)
  samples <- setNames(vector("list", length(cols)), cols)
  for (line in rows) {
    parts <- strsplit(line, sep, fixed = TRUE)[[1]]
    parts <- gsub("^\"|\"$", "", parts)
    if (length(parts) < length(cols)) parts <- c(parts, rep("", length(cols) - length(parts)))
    for (i in seq_along(cols)) samples[[i]] <- c(samples[[i]], parts[[i]])
  }
  list(cols = cols, samples = samples)
}

.easymr_rs_fraction <- function(v) {
  v <- as.character(v)
  v <- v[!is.na(v) & nzchar(v) & !tolower(v) %in% c("na", "nan", ".")]
  if (!length(v)) return(0)
  mean(grepl("^rs[0-9]+$", v, ignore.case = TRUE))
}

.easymr_match_name <- function(header, aliases) {
  hit <- aliases[tolower(aliases) %in% tolower(header)]
  if (!length(hit)) return(NA_character_)
  header[match(tolower(hit[[1]]), tolower(header))]
}

.easymr_resolve_cols <- function(path, user_cols) {
  peek <- .easymr_peek_table(path)
  header <- peek$cols
  user_cols <- user_cols %||% list()
  aliases <- .easymr_col_aliases()
  cols <- list()
  notes <- character()
  for (role in names(aliases)) {
    if (!is.null(user_cols[[role]]) && nzchar(user_cols[[role]])) {
      chosen <- .easymr_match_name(header, user_cols[[role]])
      if (is.na(chosen)) {
        stop(path, " 里没有指定列 ", role, "=", user_cols[[role]],
             "。表头: ", paste(header, collapse = ", "))
      }
      cols[[role]] <- chosen
      next
    }
    if (role == "SNP") {
      named <- .easymr_match_name(header, aliases$SNP)
      fracs <- vapply(header, function(nm) .easymr_rs_fraction(peek$samples[[nm]]), numeric(1))
      rs_cols <- header[fracs >= 0.8]
      if (length(rs_cols)) {
        prefer <- aliases$SNP[tolower(aliases$SNP) %in% tolower(rs_cols)]
        pick <- if (length(prefer)) {
          rs_cols[match(tolower(prefer[[1]]), tolower(rs_cols))]
        } else {
          rs_cols[[which.max(fracs[rs_cols])]]
        }
        cols$SNP <- pick
        notes <- c(notes, sprintf("SNP 列 %s（抽样 rs 比例 %.2f）", pick, fracs[[pick]]))
      } else if (!is.na(named)) {
        stop(path, " 的 ID 列 ", named, " 抽样后不是 rs 号。表头: ",
             paste(header, collapse = ", "),
             "。请在 exposure$cols$SNP 指定真正的 rs 列，或先换成带 rsid 的 harmonised 文件。")
      } else {
        stop(path, " 没有可用的 rs 号列。表头: ", paste(header, collapse = ", "))
      }
      next
    }
    chosen <- .easymr_match_name(header, aliases[[role]])
    if (is.na(chosen)) {
      stop(path, " 缺少 ", role, " 列。表头: ", paste(header, collapse = ", "))
    }
    cols[[role]] <- chosen
  }
  list(cols = cols, note = paste(notes, collapse = "; "))
}

.easymr_one_exposure <- function(x, exposure_dir, force_reformat) {
  if (is.null(x$file) || !nzchar(x$file)) stop("easymr exposure 缺少 file")
  if (is.null(x$id) || !nzchar(x$id)) stop("easymr exposure 缺少 id")
  if (is.null(x$N) || !is.finite(as.numeric(x$N))) stop("easymr exposure 缺少样本量 N: ", x$id)
  host <- .easymr_to_host(file.path(.easymr_slash(exposure_dir), x$file))
  if (!file.exists(host)) {
    if (isTRUE(force_reformat)) stop("找不到暴露文件: ", host)
    message("easymr ", x$id, ": 原始文件不在，跳过表头识别，只在已有 txt 上做 MR")
  }
  cols <- list()
  note <- "未读表头（沿用已有 txt）"
  if (file.exists(host)) {
    resolved <- .easymr_resolve_cols(host, x$cols)
    cols <- resolved$cols
    note <- resolved$note
    message("easymr ", x$id, ": ", note, " | ",
            paste(names(cols), unlist(cols), sep = "=", collapse = ", "))
  } else if (!is.null(x$cols)) {
    cols <- x$cols
    note <- "使用 exposure$cols，未找到原始文件"
  }
  list(
    file = x$file,
    id = x$id,
    label = x$label %||% x$id,
    N = as.numeric(x$N),
    type_binary = isTRUE(x$type_binary),
    ncase = x$ncase %||% NA_real_,
    cols = cols,
    col_note = note
  )
}

.easymr_write_runner <- function(path, cfg, jobs) {
  cols_lines <- function(cols) {
    paste(sprintf("%s = %s", names(cols), vapply(cols, .easymr_r_quote, "")), collapse = ", ")
  }
  job_lines <- vapply(jobs, function(j) {
    sprintf(
      "list(file = %s, id = %s, label = %s, N = %s, type_binary = %s, ncase = %s, cols = list(%s))",
      .easymr_r_quote(j$file), .easymr_r_quote(j$id), .easymr_r_quote(j$label),
      format(j$N, scientific = FALSE, trim = TRUE),
      if (isTRUE(j$type_binary)) "TRUE" else "FALSE",
      if (is.finite(j$ncase)) format(j$ncase, scientific = FALSE, trim = TRUE) else "NA",
      cols_lines(j$cols)
    )
  }, character(1))
  body <- c(
    "# Generated by block easymr_twosample. ASCII only.",
    "args_ok <- TRUE",
    "suppressPackageStartupMessages(library(easyMR))",
    "suppressPackageStartupMessages(library(data.table))",
    sprintf("config_MRdatabase(path = %s)", .easymr_r_quote(cfg$mr_database)),
    sprintf("exposure_dir <- %s", .easymr_r_quote(.easymr_to_win(cfg$exposure_dir))),
    sprintf("exposure_out <- %s", .easymr_r_quote(.easymr_to_win(cfg$exposure_out_dir))),
    sprintf("outcome_dir <- %s", .easymr_r_quote(.easymr_to_win(cfg$outcome_dir))),
    sprintf("save_root <- %s", .easymr_r_quote(.easymr_to_win(cfg$save_root))),
    sprintf("outcome_raw <- %s", .easymr_r_quote(.easymr_to_win(cfg$outcome_raw %||% ""))),
    sprintf("outcome_rds <- %s", .easymr_r_quote(.easymr_to_win(cfg$outcome_rds %||% ""))),
    sprintf("outcome_kind <- %s", .easymr_r_quote(cfg$outcome_kind %||% "finn")),
    sprintf("outcome_label <- %s", .easymr_r_quote(cfg$outcome_label %||% "outcome")),
    sprintf("full_mr <- %s", if (isFALSE(cfg$full_mr)) "FALSE" else "TRUE"),
    sprintf("force_reformat <- %s", if (isTRUE(cfg$force_reformat)) "TRUE" else "FALSE"),
    sprintf("clump_kb <- %s", as.integer(cfg$clump_kb %||% 10000L)),
    sprintf("clump_r2 <- %s", cfg$clump_r2 %||% 0.001),
    sprintf("pval_threshold <- %s", format(cfg$pval_threshold %||% 5e-8, scientific = TRUE)),
    sprintf("proxies <- %s", if (isFALSE(cfg$proxies)) "FALSE" else "TRUE"),
    sprintf("pop <- %s", .easymr_r_quote(cfg$pop %||% "EUR")),
    sprintf("action <- %sL", as.integer(cfg$action %||% 2L)),
    sprintf("run_steiger <- %s", if (isFALSE(cfg$run_steiger)) "FALSE" else "TRUE"),
    "dir.create(exposure_out, recursive = TRUE, showWarnings = FALSE)",
    "dir.create(outcome_dir, recursive = TRUE, showWarnings = FALSE)",
    "dir.create(save_root, recursive = TRUE, showWarnings = FALSE)",
    "status_path <- file.path(save_root, \"easymr_status.txt\")",
    "cat(\"QUEUE_START\", format(Sys.time()), \"\\n\", file = status_path)",
    "if (!nzchar(outcome_rds) || !file.exists(outcome_rds)) {",
    "  if (!identical(outcome_kind, \"finn\")) stop(\"outcome_rds missing and outcome_kind is not finn\")",
    "  if (!file.exists(outcome_raw)) stop(\"Missing FinnGen file: \", outcome_raw)",
    "  before <- list.files(outcome_dir, pattern = \"[.]rds$\")",
    "  easyMR:::trans_finn_data(filename = outcome_raw, type = \"outcome\", save_path = outcome_dir)",
    "  after <- list.files(outcome_dir, pattern = \"[.]rds$\")",
    "  newf <- setdiff(after, before)",
    "  if (length(newf) != 1L) stop(\"trans_finn_data did not yield exactly one new rds: \", paste(newf, collapse = \",\"))",
    "  outcome_rds <- file.path(outcome_dir, newf)",
    "}",
    "cat(\"OUTCOME\", outcome_rds, \"\\n\", file = status_path, append = TRUE)",
    "jobs <- list(",
    paste0("  ", job_lines, collapse = ",\n"),
    ")",
    "for (job in jobs) {",
    "  id <- job$id",
    "  txt <- file.path(exposure_out, paste0(id, \".txt\"))",
    "  save_path <- file.path(save_root, id)",
    "  dir.create(save_path, recursive = TRUE, showWarnings = FALSE)",
    "  cat(\"START\", id, format(Sys.time()), \"\\n\", file = status_path, append = TRUE)",
    "  ok <- tryCatch({",
    "    if ((force_reformat || !file.exists(txt)) && length(job$cols)) {",
    "      dat <- data.table::fread(file.path(exposure_dir, job$file))",
    "      fmt_args <- list(",
    "        dat = dat, type_name = id, type = \"exposure\", type_binary = job$type_binary,",
    "        SNP = job$cols$SNP, chr = job$cols$chr, pos = job$cols$pos,",
    "        beta = job$cols$beta, se = job$cols$se,",
    "        effect_allele = job$cols$effect_allele, other_allele = job$cols$other_allele,",
    "        pval = job$cols$pval, eaf = job$cols$eaf, N = job$N,",
    "        clump_kb = clump_kb, clump_r2 = clump_r2, pval_threshold = pval_threshold,",
    "        clump_local = TRUE, save_path = exposure_out)",
    "      if (is.finite(job$ncase)) fmt_args$ncase <- job$ncase",
    "      do.call(format_MR_data, fmt_args)",
    "    }",
    "    if (!file.exists(txt)) stop(\"format_MR_data did not write \", txt)",
    "    mr_modified(",
    "      exp_file_sig = txt, out_filenames = outcome_rds,",
    "      exp = job$label, out = outcome_label,",
    "      clump = FALSE, clump_r2 = clump_r2, clump_kb = clump_kb, clump_local = TRUE,",
    "      proxies = proxies, pop = pop, pval = pval_threshold, pval_out = pval_threshold,",
    "      r2 = 0.8, action = action, remove_HLA = FALSE, palindromic = FALSE,",
    "      full_MR = full_mr, remove_SNP = NULL, run_steiger_filtering = run_steiger,",
    "      save_path = save_path)",
    "    TRUE",
    "  }, error = function(e) {",
    "    cat(\"FAIL\", id, conditionMessage(e), \"\\n\", file = status_path, append = TRUE)",
    "    FALSE",
    "  })",
    "  cat(\"EXIT\", id, if (isTRUE(ok)) \"code=0\" else \"code=1\", format(Sys.time()), \"\\n\",",
    "      file = status_path, append = TRUE)",
    "}",
    "cat(\"QUEUE_DONE\", format(Sys.time()), \"\\n\", file = status_path, append = TRUE)"
  )
  writeLines(body, path, useBytes = TRUE)
  invisible(path)
}

block_easymr_twosample <- function(ctx, ...) {
  cfg <- (ctx$config$easymr) %||% list()
  if (!length(cfg$exposures)) stop("config$easymr$exposures 为空")
  need <- c("exposure_dir", "exposure_out_dir", "outcome_dir", "save_root", "mr_database")
  miss <- need[!vapply(need, function(k) !is.null(cfg[[k]]) && nzchar(cfg[[k]]), logical(1))]
  if (length(miss)) stop("config$easymr 缺少: ", paste(miss, collapse = ", "))
  if ((cfg$outcome_kind %||% "finn") == "finn" &&
      !nzchar(cfg$outcome_rds %||% "") && !nzchar(cfg$outcome_raw %||% "")) {
    stop("FinnGen 结局需要 outcome_raw，或直接给 outcome_rds")
  }
  jobs <- lapply(cfg$exposures, .easymr_one_exposure,
                 exposure_dir = cfg$exposure_dir,
                 force_reformat = isTRUE(cfg$force_reformat))
  root <- ctx$config$project$root %||% getwd()
  out_dir <- ctx$output_dir %||% file.path(root, "Output", "easymr")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  runner_host <- file.path(out_dir, "easymr_runner.R")
  .easymr_write_runner(runner_host, cfg, jobs)
  rscript <- cfg$rscript %||% "C:/Program Files/R/R-4.2.2/bin/Rscript.exe"
  ctx$results$easymr_twosample <- list(
    runner = runner_host,
    save_root = cfg$save_root,
    status_file = file.path(.easymr_to_win(cfg$save_root), "easymr_status.txt"),
    n_exposures = length(jobs),
    dry_run = isTRUE(cfg$dry_run)
  )
  if (isTRUE(cfg$dry_run)) {
    message("easymr dry_run: wrote ", runner_host)
    return(ctx)
  }
  exe <- .easymr_to_host(rscript)
  if (!file.exists(exe)) stop("找不到 Rscript: ", rscript)
  runner_arg <- .easymr_to_win(runner_host)
  message("easymr: ", exe, " --vanilla ", runner_arg)
  status <- system2(exe, c("--vanilla", runner_arg))
  ctx$results$easymr_twosample$exit_status <- status
  if (!identical(as.integer(status), 0L)) {
    warning("easyMR Rscript 退出码 ", status, "。查看 ", ctx$results$easymr_twosample$status_file)
  }
  ctx
}

if (exists("register_block", mode = "function")) {
  register_block("easymr_twosample", block_easymr_twosample, "easyMR 两样本孟德尔")
}
