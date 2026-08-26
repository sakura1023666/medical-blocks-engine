#!/usr/bin/env Rscript
# =============================================================================
#  汇总发病 by_index/【success】* 下关键发表表 → 一张 CSV（全课题可复用）
#
#  用法（引擎根目录）:
#    Rscript run/incidence/summarize_index_tables.R \
#      --root "/mnt/g/02block_result/19_Rheumatoid Arthritis/incidence_38341157" \
#      --out  "/mnt/g/.../incidence_38341157/Tables/index_key_extract.csv"
#
#  说明:
#    - 按文件名/表题角色匹配（Table 1 / Table 2 / Final multivariable /
#      Mediation / laboratory associations / ROC），不依赖可变的 S 编号。
#    - 仅扫描 【success】 指标目录；缺表则对应列为 NA。
# =============================================================================

`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0L || (is.atomic(a) && all(is.na(a)))) b else a
}

.parse_args <- function(args) {
  opts <- list(root = NULL, out = NULL, success_only = TRUE)
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--root" && i < length(args)) {
      opts$root <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--out" && i < length(args)) {
      opts$out <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--include-failed") {
      opts$success_only <- FALSE; i <- i + 1L
    } else if (!startsWith(a, "--") && is.null(opts$root)) {
      opts$root <- a; i <- i + 1L
    } else {
      i <- i + 1L
    }
  }
  opts
}

numish <- function(x) {
  if (is.null(x) || length(x) == 0L || is.na(x[[1L]])) return(NA_real_)
  x <- gsub("[^0-9eE.+-]", "", as.character(x[[1L]]))
  suppressWarnings(as.numeric(x))
}

parse_or_p <- function(s) {
  if (is.null(s) || is.na(s) || !nzchar(as.character(s))) {
    return(list(or = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_, raw = NA_character_))
  }
  s <- as.character(s)
  m <- regexec(
    "([0-9.]+)\\s*\\(([0-9.]+)\\s*[-–]\\s*([0-9.]+)\\s*,\\s*p\\s*[=<]\\s*([0-9.]+)",
    s, perl = TRUE
  )
  h <- regmatches(s, m)[[1]]
  if (length(h) >= 5L) {
    return(list(
      or = as.numeric(h[2]), lo = as.numeric(h[3]), hi = as.numeric(h[4]),
      p = as.numeric(h[5]), raw = s
    ))
  }
  list(or = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_, raw = s)
}

read_xlsx_safe <- function(path) {
  path <- as.character(path %||% "")[1L]
  if (!nzchar(path) || !file.exists(path)) return(NULL)
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    stop("需要 openxlsx 包")
  }
  tryCatch(openxlsx::read.xlsx(path, colNames = FALSE), error = function(e) NULL)
}

find_table <- function(tables_dir, pattern) {
  if (!dir.exists(tables_dir)) return(character(0))
  list.files(tables_dir, pattern = pattern, full.names = TRUE, ignore.case = TRUE)
}

find_pub_xlsx_any <- function(index_dir, pattern) {
  # 优先汇总 Tables，再递归找 xlsx（ROC 可能只在 step）
  root_hit <- find_table(file.path(index_dir, "Tables"), pattern)
  if (length(root_hit)) return(root_hit)
  list.files(
    index_dir, pattern = paste0(pattern, ".*\\.xlsx$"),
    full.names = TRUE, recursive = TRUE, ignore.case = TRUE
  )
}

extract_t1_n <- function(d) {
  f <- find_table(file.path(d, "Tables"), "^Table 1")
  tab <- read_xlsx_safe(f)
  if (is.null(tab) || nrow(tab) < 2L) return(list())
  hdr <- paste(as.character(unlist(tab[min(2L, nrow(tab)), ])), collapse = " | ")
  n_all <- suppressWarnings(as.integer(sub(".*Overall N = ([0-9]+).*", "\\1", hdr)))
  n_ctrl <- suppressWarnings(as.integer(sub(".*Non[_ ]?ASCVD N = ([0-9]+).*", "\\1", hdr, ignore.case = TRUE)))
  n_case <- suppressWarnings(as.integer(sub(".*ASCVD N = ([0-9]+).*", "\\1", hdr)))
  if (is.na(n_all)) {
    n_all <- suppressWarnings(as.integer(sub(".*N = ([0-9]+).*", "\\1", hdr)))
  }
  list(n = n_all, n_ctrl = n_ctrl, n_case = n_case, t1_hdr = hdr)
}

extract_t2 <- function(d) {
  f <- find_table(file.path(d, "Tables"), "^Table 2")
  tab <- read_xlsx_safe(f)
  if (is.null(tab) || nrow(tab) < 3L) return(list(t2_file = NA_character_))
  chars <- as.character(tab[[1]])
  out <- list(t2_file = basename(f[1L]))
  ci <- which(grepl("continuous", chars, ignore.case = TRUE))
  if (length(ci)) {
    r <- tab[ci[1L], ]
    out$t2_cont_or_crude <- numish(r[[4]])
    out$t2_cont_p_crude <- numish(r[[6]])
    out$t2_cont_or_m2 <- numish(r[[10]])
    out$t2_cont_ci_m2 <- as.character(r[[11]])
    out$t2_cont_p_m2 <- numish(r[[12]])
  }
  q <- which(grepl("^Q[2-4]", chars))
  if (length(q)) {
    r <- tab[max(q), ]
    out$t2_q_label <- as.character(r[[1]])
    out$t2_q_or_crude <- numish(r[[4]])
    out$t2_q_p_crude <- numish(r[[6]])
    out$t2_q_or_m2 <- numish(r[[10]])
    out$t2_q_ci_m2 <- as.character(r[[11]])
    out$t2_q_p_m2 <- numish(r[[12]])
  }
  pt <- which(grepl("p for trend", chars, ignore.case = TRUE))
  if (length(pt)) {
    r <- tab[pt[1L], ]
    out$t2_ptrend_m2 <- numish(r[[12]])
    if (is.na(out$t2_ptrend_m2)) out$t2_ptrend_m2 <- numish(r[[6]])
  }
  out
}

extract_final_mv_index <- function(d, idx) {
  # Final multivariable model（锁定）优先；否则 Multivariable Regression
  f <- find_table(file.path(d, "Tables"), "Final multivariable model")
  if (!length(f)) {
    f <- find_table(file.path(d, "Tables"), "Multivariable Regression")
  }
  tab <- read_xlsx_safe(f)
  if (is.null(tab)) return(NULL)
  idx_pat <- gsub("_", "[ _]", idx)
  hit <- grepl(paste0("^", idx_pat, "$"), tab[[1]], ignore.case = TRUE)
  if (!any(hit)) hit <- grepl(idx_pat, tab[[1]], ignore.case = TRUE)
  if (!any(hit)) return(NULL)
  row <- tab[max(which(hit)), , drop = FALSE]
  parsed <- parse_or_p(row[[ncol(tab)]])
  list(
    mv_or = parsed$or, mv_lo = parsed$lo, mv_hi = parsed$hi, mv_p = parsed$p,
    mv_raw = parsed$raw, mv_file = basename(f[1L])
  )
}

extract_lab_assoc_hi <- function(d) {
  f <- find_table(
    file.path(d, "Tables"),
    "Associations of .+ with laboratory|laboratory indicators"
  )
  if (!length(f)) {
    f <- find_table(file.path(d, "Tables"), "laboratory")
  }
  tab <- read_xlsx_safe(f)
  if (is.null(tab) || nrow(tab) < 4L) return(NULL)
  chars <- as.character(tab[[1]])
  hi <- which(grepl("^>=|^≥|^High", chars))
  if (!length(hi)) return(NULL)
  r <- tab[hi[1L], , drop = FALSE]
  n <- ncol(tab)
  list(
    lab_hi_label = as.character(r[[1]]),
    lab_or_m2 = if (n >= 10L) numish(r[[10]]) else NA_real_,
    lab_ci_m2 = if (n >= 11L) as.character(r[[11]]) else NA_character_,
    lab_p_m2 = if (n >= 12L) numish(r[[12]]) else NA_real_,
    lab_file = basename(f[1L])
  )
}

extract_mediation_any <- function(d) {
  f <- find_table(file.path(d, "Tables"), "Mediation analysis")
  tab <- read_xlsx_safe(f)
  if (is.null(tab)) return(list(mediation_file = NA_character_, mediation_nrow = NA_integer_))
  list(
    mediation_file = basename(f[1L]),
    mediation_nrow = nrow(tab),
    mediation_ncol = ncol(tab)
  )
}

extract_auc <- function(d) {
  f <- find_pub_xlsx_any(d, "ROC|AUC")
  # 优先含 ROC 字样的表
  if (!length(f)) return(list(auc = NA_real_))
  f <- f[grepl("ROC|AUC", basename(f), ignore.case = TRUE)]
  if (!length(f)) return(list(auc = NA_real_))
  tab <- read_xlsx_safe(f[1L])
  if (is.null(tab)) return(list(auc = NA_real_, auc_file = basename(f[1L])))
  auc <- NA_real_
  chars <- as.character(tab[[1]])
  ar <- which(grepl("AUC|auc", chars))
  if (length(ar)) {
    r <- tab[ar[1L], ]
    for (j in seq_len(ncol(tab))) {
      v <- suppressWarnings(as.numeric(r[[j]]))
      if (!is.na(v) && v >= 0.5 && v <= 1) auc <- v
    }
  }
  if (is.na(auc)) {
    for (j in seq_len(ncol(tab))) {
      v <- suppressWarnings(as.numeric(tab[[j]]))
      cand <- v[!is.na(v) & v >= 0.5 & v <= 1]
      if (length(cand)) auc <- cand[length(cand)]
    }
  }
  list(auc = auc, auc_file = basename(f[1L]))
}

flatten_rows <- function(rows) {
  all_keys <- unique(unlist(lapply(rows, names)))
  do.call(rbind, lapply(rows, function(r) {
    r2 <- lapply(all_keys, function(k) {
      v <- r[[k]]
      if (is.null(v) || length(v) == 0L) return(NA)
      if (length(v) > 1L) return(paste(v, collapse = "|"))
      v
    })
    names(r2) <- all_keys
    as.data.frame(r2, stringsAsFactors = FALSE)
  }))
}

main <- function() {
  opts <- .parse_args(commandArgs(trailingOnly = TRUE))
  root <- opts$root
  if (is.null(root) || !nzchar(root) || !dir.exists(root)) {
    stop("请提供有效 --root <study_root>（含 by_index/）")
  }
  by <- file.path(root, "by_index")
  if (!dir.exists(by)) stop("未找到: ", by)

  dirs <- list.dirs(by, recursive = FALSE, full.names = TRUE)
  if (isTRUE(opts$success_only)) {
    dirs <- dirs[grepl("【success】", basename(dirs))]
  } else {
    dirs <- dirs[grepl("【success】|【failed】", basename(dirs))]
  }
  if (!length(dirs)) stop("by_index 下无匹配指标目录")

  rows <- list()
  for (d in dirs) {
    bn <- basename(d)
    idx <- sub("^【(success|failed)】", "", bn)
    st <- tryCatch({
      if (requireNamespace("jsonlite", quietly = TRUE) &&
          file.exists(file.path(d, "_batch_status.json"))) {
        jsonlite::fromJSON(file.path(d, "_batch_status.json"))
      } else {
        list()
      }
    }, error = function(e) list())

    rec <- list(
      index = idx,
      status_dir = bn,
      branch = st$mimic_branch %||% st$branch %||% NA,
      n_before = st$n_mimic_before %||% NA,
      n_after_status = st$n_mimic_after %||% NA
    )
    rec <- c(rec, extract_t1_n(d))
    rec <- c(rec, extract_t2(d))
    rec <- c(rec, extract_final_mv_index(d, idx))
    rec <- c(rec, extract_lab_assoc_hi(d))
    rec <- c(rec, extract_mediation_any(d))
    rec <- c(rec, extract_auc(d))
    rows[[idx]] <- rec
  }

  df <- flatten_rows(rows)
  rownames(df) <- NULL

  out <- opts$out
  if (is.null(out) || !nzchar(out)) {
    out_dir <- file.path(root, "Tables")
    if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
    out <- file.path(out_dir, "index_key_extract.csv")
  } else {
    od <- dirname(out)
    if (nzchar(od) && !dir.exists(od)) dir.create(od, recursive = TRUE)
  }

  utils::write.csv(df, out, row.names = FALSE, fileEncoding = "UTF-8")
  message("wrote ", out, "  nrow=", nrow(df), " ncol=", ncol(df))

  keep <- intersect(c(
    "index", "n", "n_case", "n_ctrl", "branch", "auc",
    "t2_cont_or_m2", "t2_cont_p_m2", "t2_q_label", "t2_q_or_m2", "t2_q_p_m2",
    "mv_or", "mv_p", "mv_raw",
    "lab_or_m2", "lab_p_m2",
    "mediation_nrow", "mediation_file"
  ), names(df))
  if (length(keep)) {
    print(df[, keep, drop = FALSE], row.names = FALSE)
  }
  invisible(df)
}

main()
