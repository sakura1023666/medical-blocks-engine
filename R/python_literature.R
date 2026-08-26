###############################################################################
#  python_literature.R — 文献扩展 Python 子进程调用（网络毒理/GSEA/Kml3D/DL-SHAP）
###############################################################################

literature_python_bin <- function() {
  if (grepl("^/mnt/", normalizePath(getwd(), winslash = "/", mustWork = FALSE))) {
    for (cand in c(Sys.which("python3"), Sys.which("python"))) {
      if (nzchar(cand) && file.exists(cand)) return(cand)
    }
  }
  cands <- c(
    Sys.getenv("PYTHON", ""),
    "/mnt/c/ProgramData/anaconda3/python.exe",
    "C:/ProgramData/anaconda3/python.exe",
    Sys.which("python"),
    Sys.which("python3")
  )
  for (cand in cands) {
    if (nzchar(cand) && file.exists(cand)) return(cand)
  }
  stop("未找到 python3/python，请安装或设置 PYTHON 环境变量（如 C:/ProgramData/anaconda3/python.exe）。", call. = FALSE)
}

literature_python_script <- function(root, name = "block_literature_extensions.py") {
  p <- file.path(root, "python", name)
  if (!file.exists(p)) stop("Python 脚本不存在: ", p, call. = FALSE)
  p <- normalizePath(p, winslash = "/", mustWork = TRUE)
  py <- literature_python_bin()
  if (grepl("python\\.exe$", py, ignore.case = TRUE) && grepl("^/mnt/", p)) {
    wsl <- Sys.which("wslpath")
    if (nzchar(wsl)) {
      wp <- tryCatch(
        system2(wsl, c("-w", p), stdout = TRUE, stderr = FALSE),
        error = function(e) character(0)
      )
      if (length(wp) && nzchar(trimws(wp[[1L]]))) {
        return(trimws(wp[[1L]]))
      }
    }
  }
  p
}

.wsl_to_win_path <- function(p) {
  if (!nzchar(p) || !grepl("^/mnt/", p)) return(p)
  wsl <- Sys.which("wslpath")
  if (!nzchar(wsl)) return(p)
  wp <- tryCatch(system2(wsl, c("-w", p), stdout = TRUE, stderr = FALSE), error = function(e) character(0))
  if (length(wp) && nzchar(trimws(wp[[1L]]))) trimws(wp[[1L]]) else p
}

# Windows system2 不会自动给含空格参数加引号；路径如 `11_ischemic stroke` 会被拆开
.system2_quote_args <- function(args) {
  args <- as.character(args)
  vapply(args, function(a) {
    if (!nzchar(a)) return('""')
    if (grepl("[[:space:]]", a, perl = TRUE) && !grepl('^["\'].*["\']$', a)) {
      paste0('"', gsub('"', '""', a, fixed = TRUE), '"')
    } else {
      a
    }
  }, character(1L), USE.NAMES = FALSE)
}

run_literature_python <- function(root, mode, args = character(), timeout_sec = 600L,
                                  script = "block_literature_extensions.py") {
  py  <- literature_python_bin()
  scr <- literature_python_script(root, name = script)
  # WSL 调用 Windows Python 时，数据/输出路径也需转为 Windows 路径
  if (grepl("python\\.exe$", py, ignore.case = TRUE)) {
    args <- vapply(args, .wsl_to_win_path, character(1L))
  }
  cmd_args <- c(scr, "--mode", mode, args)
  if (grepl("python\\.exe$", py, ignore.case = TRUE) || identical(.Platform$OS.type, "windows")) {
    cmd_args <- .system2_quote_args(cmd_args)
  }
  cli::cli_alert_info("Python [{mode}]: {basename(scr)}")
  out <- system2(py, cmd_args, stdout = TRUE, stderr = TRUE, timeout = timeout_sec)
  code <- attr(out, "status") %||% 0L
  if (!identical(as.integer(code), 0L)) {
    tail_out <- paste(tail(out, 20L), collapse = "\n")
    stop("Python 模式 ", mode, " 失败 (exit=", code, "):\n", tail_out, call. = FALSE)
  }
  invisible(out)
}
