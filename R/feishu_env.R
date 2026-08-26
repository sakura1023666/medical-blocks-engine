###############################################################################
#  feishu_env.R — 从项目根 .env.feishu 加载飞书凭证到 Sys.getenv
###############################################################################

feishu_env_keys <- function() {
  c(
    "FEISHU_APP_ID",
    "FEISHU_APP_SECRET",
    "FEISHU_BITABLE_APP_TOKEN",
    "FEISHU_BITABLE_TABLE_ID",
    "FEISHU_BITABLE_TABLE_SUCCESS_ID",
    "FEISHU_BITABLE_TABLE_FAILURE_ID",
    "FEISHU_BITABLE_TABLE_ROUTINE_ID",
    "FEISHU_OWNER"
  )
}

.feishu_parse_dotenv_line <- function(line) {
  line <- trimws(as.character(if (is.null(line)) "" else line))
  if (!nzchar(line) || startsWith(line, "#")) return(NULL)
  if (!grepl("=", line, fixed = TRUE)) return(NULL)
  parts <- strsplit(line, "=", fixed = TRUE)[[1L]]
  key <- trimws(parts[1L])
  val <- trimws(paste(parts[-1L], collapse = "="))
  val <- sub("^['\"]|['\"]$", "", val)
  if (!nzchar(key)) return(NULL)
  list(key = key, value = val)
}

.feishu_dotenv_candidates <- function(root = getwd()) {
  root <- normalizePath(root, winslash = "/", mustWork = FALSE)
  c(
    file.path(root, "run/feishu/.env.feishu"),
    file.path(root, ".env.feishu")
  )
}

#' 读取 run/feishu/.env.feishu 与 <root>/.env.feishu（先 run/feishu，后根目录；不覆盖已有环境变量）
feishu_load_dotenv <- function(root = getwd()) {
  paths <- .feishu_dotenv_candidates(root)
  paths <- paths[file.exists(paths)]
  if (!length(paths)) return(invisible(FALSE))
  loaded <- FALSE
  for (path in paths) {
    lines <- tryCatch(
      readLines(path, warn = FALSE, encoding = "UTF-8"),
      error = function(e) character(0)
    )
    for (line in lines) {
      kv <- .feishu_parse_dotenv_line(line)
      if (is.null(kv)) next
      if (!nzchar(Sys.getenv(kv$key, unset = ""))) {
        args <- list()
        args[[kv$key]] <- kv$value
        do.call(Sys.setenv, args)
        loaded <- TRUE
      }
    }
  }
  invisible(loaded)
}

#' 返回各飞书环境变量是否已配置（供 run_feishu_test.R 自检）
feishu_env_status <- function() {
  keys <- feishu_env_keys()
  stats::setNames(
    vapply(keys, function(k) nzchar(Sys.getenv(k, unset = "")), logical(1L)),
    keys
  )
}
