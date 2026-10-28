# 预后 2.0 发表表/图文件名：单库不加数据库前缀；多库保留 "Table 1-NHANES. …"

pv2_is_single_db <- function(dbs_or_units) {
  nms <- if (is.list(dbs_or_units) && !is.data.frame(dbs_or_units)) {
    names(dbs_or_units)
  } else {
    unique(as.character(dbs_or_units))
  }
  nms <- nms[!is.na(nms) & nzchar(nms)]
  length(nms) <= 1L
}

# num_stem 例: "Table 1", "Table S6"；stem 例: "Baseline characteristics"
# db 在单库时忽略；多库时写入文件名。
pv2_table_xlsx_name <- function(num_stem, stem, db = NULL, single_db = FALSE) {
  num_stem <- trimws(as.character(num_stem)[1L])
  stem <- trimws(as.character(stem)[1L])
  stem <- sub("^\\.\\s*", "", stem)
  if (isTRUE(single_db) || is.null(db) || !nzchar(as.character(db)[1L])) {
    sprintf("%s. %s.xlsx", num_stem, stem)
  } else {
    sprintf("%s-%s. %s.xlsx", num_stem, as.character(db)[1L], stem)
  }
}

pv2_table_title <- function(num_stem, stem, db = NULL, single_db = FALSE) {
  # 表内标题一律不带库名；库别只体现在多库文件名。
  sprintf("%s. %s", trimws(num_stem), trimws(stem))
}
