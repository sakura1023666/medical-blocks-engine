###############################################################################
#  competing_io.R — 竞争风险中间结果 vs 发表表路径（全项目可复用）
#  中间 csv/txt 只进 step*/Data/，根目录 Tables/ 仅保留发表 xlsx
###############################################################################

.competing_unit_root <- function(ctx) {
  ctx$root_output_dir %||%
    (ctx$config$project$output_dir %||% "Output")
}

.competing_pub_tables_dir <- function(ctx) {
  # 发表表：优先当前 block 的 Tables（再由 mirror 汇总到根）
  d <- ctx$output_dir_tables %||% NULL
  if (!is.null(d) && nzchar(d)) {
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
    return(d)
  }
  d <- file.path(.competing_unit_root(ctx), "Tables")
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

.competing_data_dir <- function(ctx) {
  # 中间结果：step 子目录 Data/；无 step 上下文时落到 unit/_intermediate
  base <- ctx$output_dir %||% NULL
  if (is.null(base) || !nzchar(base)) {
    base <- file.path(.competing_unit_root(ctx), "_intermediate")
  }
  d <- file.path(base, "Data")
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

.competing_is_pub_table_name <- function(filename) {
  bn <- basename(as.character(filename)[1L])
  grepl(
    "^(Table [0-9]|Table S[0-9]|Supplementary Material|Figure [0-9])",
    bn,
    ignore.case = TRUE,
    perl = TRUE
  )
}

#' 中间表：只写 Data/，并可选存入 ctx$results
.competing_write_intermediate_csv <- function(ctx, tab, filename, result_key = NULL) {
  path <- file.path(.competing_data_dir(ctx), basename(filename))
  if (!is.null(tab)) {
    utils::write.csv(tab, path, row.names = FALSE)
  }
  if (!is.null(result_key) && nzchar(result_key) && is.list(ctx)) {
    ctx$results[[result_key]] <- tab
  }
  invisible(path)
}

#' 发表 xlsx：写到 block Tables/（mirror 到根 Tables）
.competing_pub_path <- function(ctx, filename) {
  file.path(.competing_pub_tables_dir(ctx), basename(filename))
}

#' 清理根目录 Tables 中的中间 csv/txt（非发表命名）
.competing_cleanup_root_tables <- function(ctx) {
  root_tab <- file.path(.competing_unit_root(ctx), "Tables")
  if (!dir.exists(root_tab)) return(invisible(0L))
  files <- list.files(root_tab, full.names = TRUE)
  n <- 0L
  for (f in files) {
    bn <- basename(f)
    ext <- tolower(tools::file_ext(bn))
    keep <- .competing_is_pub_table_name(bn) && ext %in% c("xlsx", "pdf", "png")
    # 允许 Table S*.xlsx / Supplementary / Table N.xlsx；其余 csv/txt/扁平 Table_*.csv 删除
    if (ext %in% c("csv", "txt") || (ext == "xlsx" && !keep && grepl("^Table[_]", bn))) {
      if (keep) next
      tryCatch(file.remove(f), error = function(e) FALSE)
      n <- n + 1L
    } else if (ext %in% c("csv", "txt")) {
      tryCatch(file.remove(f), error = function(e) FALSE)
      n <- n + 1L
    } else if (!keep && ext == "xlsx" && grepl("^(Table_|Analysis_|00_)", bn)) {
      tryCatch(file.remove(f), error = function(e) FALSE)
      n <- n + 1L
    }
  }
  # 再扫一遍：根 Tables 下所有 csv/txt 一律清除
  for (f in list.files(root_tab, pattern = "\\.(csv|txt)$", full.names = TRUE, ignore.case = TRUE)) {
    if (file.exists(f)) {
      tryCatch(file.remove(f), error = function(e) FALSE)
      n <- n + 1L
    }
  }
  invisible(n)
}
