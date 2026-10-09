###############################################################################
#  python_literature.R — 文献扩展 Python 子进程调用（网络毒理/GSEA/Kml3D/DL-SHAP）
###############################################################################

literature_python_bin <- function() {
  # Prefer explicit PYTHON (e.g. Miniconda envs/torch) even under WSL /mnt paths.
  env_py <- as.character(Sys.getenv("PYTHON", "") %||% "")[1L]
  if (nzchar(env_py) && file.exists(env_py)) return(env_py)

  if (grepl("^/mnt/", normalizePath(getwd(), winslash = "/", mustWork = FALSE))) {
    # Prefer Windows torch env used by prior TST / ML runs on this host
    for (cand in c(
      "/mnt/c/ProgramData/Miniconda3/envs/torch/python.exe",
      "C:/ProgramData/Miniconda3/envs/torch/python.exe",
      "/mnt/c/ProgramData/anaconda3/python.exe",
      Sys.which("python3"),
      Sys.which("python")
    )) {
      if (nzchar(cand) && file.exists(cand)) return(cand)
    }
  }
  cands <- c(
    "/mnt/c/ProgramData/Miniconda3/envs/torch/python.exe",
    "C:/ProgramData/Miniconda3/envs/torch/python.exe",
    "/mnt/c/ProgramData/anaconda3/python.exe",
    "C:/ProgramData/anaconda3/python.exe",
    Sys.which("python"),
    Sys.which("python3")
  )
  for (cand in cands) {
    if (nzchar(cand) && file.exists(cand)) return(cand)
  }
  stop("未找到 python3/python，请安装或设置 PYTHON 环境变量（如 C:/ProgramData/Miniconda3/envs/torch/python.exe）。", call. = FALSE)
}

# WSL R → Windows python.exe: MUST use forward-slash drive paths (E:/foo).
# Backslash form from wslpath -w (E:\01...) is mangled by WSL/.exe argv and
# becomes unreadable (e.g. E:\01block\...\python\x → ...\01block...pythonx).
#
# Native Windows R also hits this helper when PYTHON=*.exe. Do NOT pass CLI
# flags / scalars through normalizePath — on Windows that prepends getwd()
# (e.g. "--out-dir" → "E:/.../--out-dir") and breaks argparse.
.wsl_to_win_path <- function(p) {
  p <- as.character(p %||% "")[1L]
  if (!nzchar(p)) return(p)
  # Flags, bare tokens, numbers: leave untouched
  if (startsWith(p, "-")) return(p)
  if (grepl("^[0-9]+([.][0-9]+)?$", p)) return(p)
  if (!grepl("[/\\\\]", p) && !grepl("^[A-Za-z]:", p)) return(p)
  p <- normalizePath(p, winslash = "/", mustWork = FALSE)
  if (grepl("^/mnt/[a-zA-Z]/", p)) {
    return(paste0(toupper(substr(p, 6L, 6L)), ":", substr(p, 7L, nchar(p))))
  }
  # Already Windows with backslashes → forward slash
  if (grepl("^[A-Za-z]:\\\\", p) || grepl("\\\\", p, fixed = TRUE)) {
    return(gsub("\\\\", "/", p, fixed = TRUE))
  }
  p
}

literature_python_script <- function(root, name = "block_literature_extensions.py") {
  p <- file.path(root, "python", name)
  if (!file.exists(p)) stop("Python 脚本不存在: ", p, call. = FALSE)
  p <- normalizePath(p, winslash = "/", mustWork = TRUE)
  py <- literature_python_bin()
  if (grepl("python\\.exe$", py, ignore.case = TRUE) && grepl("^/mnt/", p)) {
    return(.wsl_to_win_path(p))
  }
  p
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
  # 长训练：勿把 tqdm 全量灌进 system2(stdout=TRUE)，易撑爆/被 timeout 掐断。
  # 重训练 mode 写日志文件；短任务仍捕获输出便于报错。
  long_train <- mode %in% c(
    "tst_train_a1", "tst_train_a2", "tst_train_b", "tst_ablation", "tst_baselines"
  )
  if (isTRUE(long_train) && is.finite(timeout_sec) && timeout_sec >= 3600) {
    log_file <- tempfile(pattern = paste0(mode, "_"), fileext = ".log")
    cli::cli_alert_info("Python 长任务日志: {log_file}")
    code <- system2(py, cmd_args, stdout = log_file, stderr = log_file, timeout = timeout_sec)
    if (!identical(as.integer(code %||% 0L), 0L)) {
      safe_tail <- tryCatch({
        lines <- readLines(log_file, warn = FALSE, encoding = "UTF-8")
        paste(utils::tail(lines, 40L), collapse = "\n")
      }, error = function(e) paste0("(无法读日志) ", log_file))
      stop("Python 模式 ", mode, " 失败 (exit=", code, "):\n", safe_tail, call. = FALSE)
    }
    return(invisible(log_file))
  }
  out <- system2(py, cmd_args, stdout = TRUE, stderr = TRUE, timeout = timeout_sec)
  code <- attr(out, "status") %||% 0L
  if (!identical(as.integer(code), 0L)) {
    raw_tail <- tail(out, 40L)
    # Windows Python 可能吐出非 UTF-8 字节；cli/stop 前先清洗，避免二次崩溃
    safe_tail <- vapply(raw_tail, function(line) {
      line <- as.character(line %||% "")
      enc <- tryCatch(iconv(line, from = "", to = "UTF-8", sub = "?"), error = function(e) NULL)
      if (is.null(enc) || !nzchar(enc)) enc <- tryCatch(
        iconv(line, from = "GBK", to = "UTF-8", sub = "?"),
        error = function(e) gsub("[^\x20-\x7E\n\r\t]", "?", line)
      )
      enc
    }, character(1L))
    tail_out <- paste(safe_tail, collapse = "\n")
    stop("Python 模式 ", mode, " 失败 (exit=", code, "):\n", tail_out, call. = FALSE)
  }
  invisible(out)
}
