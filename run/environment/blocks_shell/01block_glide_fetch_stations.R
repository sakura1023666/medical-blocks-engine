# glide_fetch_stations — GLIDE-SOL: fetch stations
# register_block: "glide_fetch_stations"
# Implementation lives in python/block_glide_sol.py (Final 源库同样无独立 R 算法文件).

block_glide_fetch_stations <- function(ctx, config) {
  if (!exists("python_run_glide_sol_step", mode = "function")) {
    py_helper <- file.path(ctx$root %||% getwd(), "R", "python_literature.R")
    if (file.exists(py_helper)) source(py_helper, local = FALSE)
  }
  if (exists("python_run_glide_sol_step", mode = "function")) {
    return(python_run_glide_sol_step(ctx, config, step = "glide_fetch_stations"))
  }
  stop(
    "GLIDE-SOL step 'glide_fetch_stations' has no R body; implement via python/block_glide_sol.py ",
    "or add python_run_glide_sol_step() helper. Source Final also lacked Blocks/74_glide_sol_full/."
  )
}

register_block("glide_fetch_stations", block_glide_fetch_stations, "GLIDE-SOL: fetch stations")
