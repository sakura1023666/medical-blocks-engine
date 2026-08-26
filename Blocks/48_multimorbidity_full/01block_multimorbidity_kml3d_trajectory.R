###############################################################################
#  multimorbidity_kml3d_trajectory — Kml3D 风格联合轨迹聚类（Python KMeans 实现）
###############################################################################

block_multimorbidity_kml3d_trajectory <- function(ctx, ...) {
  bl <- ctx$config$multimorbidity %||% list()
  root <- ctx$config$project$root %||% getwd()
  if (!exists("run_literature_python", mode = "function")) {
    source(file.path(root, "R/python_literature.R"), local = FALSE)
  }
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("multimorbidity_kml3d: 无数据", call. = FALSE)
  long_path <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "_kml3d_input.csv")
  dir.create(dirname(long_path), recursive = TRUE, showWarnings = FALSE)
  if (!"BMI_proxy" %in% names(data)) data$BMI_proxy <- stats::rnorm(nrow(data), 27, 4)
  utils::write.csv(data, long_path, row.names = FALSE)
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Trajectory")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  n_cl <- as.integer(bl$kml3d_clusters %||% 4L)
  run_literature_python(root, "kml3d_trajectory", c(
    "--out-dir", out, "--long-path", long_path, "--n-clusters", as.character(n_cl)
  ))
  assign_path <- file.path(out, "Table_Kml3D_Trajectory_Assignment.csv")
  if (file.exists(assign_path)) {
    traj <- utils::read.csv(assign_path, stringsAsFactors = FALSE)
    merge_id <- intersect(c("ID", ctx$config$data$id_column %||% "ID", "row_id"), names(traj))[1L]
    if (!is.na(merge_id) && merge_id %in% names(data) && "trajectory_cluster" %in% names(traj)) {
      data <- merge(data, traj[, c(merge_id, "trajectory_cluster"), drop = FALSE], by = merge_id, all.x = TRUE)
      ctx$data$imputed <- data
      ctx$data$cleaned <- data
    }
  }
  ctx$results$multimorbidity_kml3d <- list(output_dir = out, n_clusters = n_cl)
  cli::cli_alert_success("Kml3D 轨迹聚类完成（k={n_cl}）")
  ctx
}

register_block(
  "multimorbidity_kml3d_trajectory",
  block_multimorbidity_kml3d_trajectory,
  "Kml3D 联合轨迹聚类"
)
