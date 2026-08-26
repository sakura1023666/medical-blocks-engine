###############################################################################
#  literature_data_utils.R — 插补后 ID 行名恢复等
###############################################################################

literature_ensure_id_column <- function(data, id_col = "ID") {
  if (is.null(data) || !is.data.frame(data) || !nrow(data)) return(data)
  if (id_col %in% names(data) && any(nzchar(as.character(data[[id_col]])))) return(data)
  rn <- rownames(data)
  if (!is.null(rn) && length(rn) == nrow(data)) {
    data[[id_col]] <- rn
  }
  data
}
