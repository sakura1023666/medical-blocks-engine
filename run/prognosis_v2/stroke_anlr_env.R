# 卒中 ANLR：输出目录 / 结局窗口（由环境变量驱动；默认保持 28d summary_results）
# STROKE_ANLR_OUT  = summary_results | summary_results_7d|14d|90d|365d
# STROKE_ANLR_DAYS = 7 | 14 | 28 | 90 | 365

stroke_anlr_proj <- function() {
  cands <- c(
    "/mnt/g/02block_result/11_ischemic stroke/prognosis_v2_41904528",
    "G:/02block_result/11_ischemic stroke/prognosis_v2_41904528"
  )
  hit <- cands[dir.exists(cands)]
  if (!length(hit)) stop("stroke ANLR project root not found")
  hit[[1L]]
}

stroke_anlr_out_name <- function() {
  nm <- Sys.getenv("STROKE_ANLR_OUT", unset = "summary_results")
  if (!nzchar(nm)) nm <- "summary_results"
  nm
}

stroke_anlr_out <- function(proj = stroke_anlr_proj()) {
  file.path(proj, stroke_anlr_out_name())
}

stroke_anlr_days <- function() {
  d <- suppressWarnings(as.integer(Sys.getenv("STROKE_ANLR_DAYS", unset = "28")))
  if (!is.finite(d) || d < 1L) 28L else as.integer(d)
}

stroke_anlr_day_lab <- function() sprintf("%d-day", stroke_anlr_days())

stroke_anlr_endpoint_phrase <- function() {
  sprintf("%s all-cause mortality", stroke_anlr_day_lab())
}
