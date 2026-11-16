# Times New Roman force for published xlsx — thin wrapper.
# Canonical path: python/pub_xlsx_scrub_display.py (also runs on every
# pub_delivery_scrub_display). Kept so older finalize hooks still source this file.

pub_xlsx_force_times_fonts <- function(path) {
  path <- path.expand(as.character(path)[[1L]])
  if (!file.exists(path)) return(invisible(FALSE))
  py <- Sys.which("python3")
  if (!nzchar(py)) py <- Sys.which("python")
  if (!nzchar(py)) {
    warning("python3 not found; skip Times force for ", path, call. = FALSE)
    return(invisible(FALSE))
  }
  root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(root) || !dir.exists(file.path(root, "R"))) {
    root <- "/mnt/e/01block/01Block-new-Final"
  }
  # Prefer canonical scrub --times-only (underscore/CJK path shares same file)
  scrub <- file.path(root, "python", "pub_xlsx_scrub_display.py")
  script <- if (file.exists(scrub)) scrub else {
    file.path(root, "R", "pub_xlsx_tools", "xlsx_force_times.py")
  }
  if (!file.exists(script)) {
    warning("Times force script not found; skip ", path, call. = FALSE)
    return(invisible(FALSE))
  }
  args <- if (identical(script, scrub)) c(script, "--times-only", path) else c(script, path)
  out <- tryCatch(
    system2(py, args, stdout = TRUE, stderr = TRUE),
    error = function(e) paste0("ERR:", conditionMessage(e))
  )
  invisible(list(path = path, log = out))
}

pub_delivery_force_tables_times <- function(delivery_root, ...) {
  tabs <- list.files(
    file.path(delivery_root, "Tables"),
    pattern = "\\.xlsx$",
    full.names = TRUE
  )
  if (!length(tabs)) return(invisible(list(n = 0L)))
  # One python call over the Tables dir when scrub is available
  root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
  scrub <- file.path(root, "python", "pub_xlsx_scrub_display.py")
  py <- Sys.which("python3")
  if (!nzchar(py)) py <- Sys.which("python")
  if (nzchar(py) && file.exists(scrub) && dir.exists(file.path(delivery_root, "Tables"))) {
    out <- tryCatch(
      system2(
        py,
        c(scrub, "--dir", file.path(delivery_root, "Tables"), "--times-only"),
        stdout = TRUE, stderr = TRUE
      ),
      error = function(e) paste0("ERR:", conditionMessage(e))
    )
    return(invisible(list(n = length(tabs), log = out)))
  }
  res <- lapply(tabs, pub_xlsx_force_times_fonts)
  invisible(list(n = length(tabs), details = res))
}
