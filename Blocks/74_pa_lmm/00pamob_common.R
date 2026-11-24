###############################################################################
# 00pamob_common.R — source utils once for 74 blocks
###############################################################################

.pamob_source_utils <- function(ctx) {
  root <- ctx$config$project$root %||% getwd()
  path <- file.path(root, "R/pamob_utils.R")
  if (!file.exists(path)) stop("缺少 R/pamob_utils.R", call. = FALSE)
  source(path, local = FALSE)
}
