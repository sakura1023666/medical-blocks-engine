###############################################################################
#  univariate_or_helpers.R — 单因素 OR/HR 表：二元 numeric 与系数名匹配
###############################################################################

#' 将 numeric 0/1（或两水平数值）转为 factor，使 glm 系数名为 VarLevel。
univar_coerce_binary_predictor <- function(x) {
  if (is.factor(x)) return(x)
  ux <- unique(stats::na.omit(x))
  if (length(ux) != 2L) return(x)
  if (is.numeric(x) && all(ux %in% c(0, 1))) {
    return(factor(x, levels = c(0, 1)))
  }
  if (is.numeric(x)) {
    return(factor(x, levels = sort(ux)))
  }
  x
}

#' 单因素发表表：按变量名与水平匹配系数行（兼容 numeric 0/1 的 Var 与 factor 的 VarLevel）。
univar_match_coef_row <- function(sub_u, bv, lev = NULL) {
  if (!is.data.frame(sub_u) || nrow(sub_u) == 0L) {
    return(sub_u[0, , drop = FALSE])
  }
  if (is.null(lev)) {
    mr <- sub_u[sub_u$Variable == bv, , drop = FALSE]
    if (nrow(mr)) return(mr[1L, , drop = FALSE])
    return(sub_u[0, , drop = FALSE])
  }
  lev <- as.character(lev)
  candidates <- unique(c(
    paste0(bv, lev),
    paste0(bv, trimws(lev)),
    bv
  ))
  for (cand in candidates) {
    mr <- sub_u[sub_u$Variable == cand, , drop = FALSE]
    if (nrow(mr)) return(mr[1L, , drop = FALSE])
  }
  if ("Group" %in% names(sub_u)) {
    mr <- sub_u[as.character(sub_u$Group) == lev, , drop = FALSE]
    if (nrow(mr)) return(mr[1L, , drop = FALSE])
  }
  mr <- sub_u[grepl(paste0("^", bv), sub_u$Variable, perl = TRUE), , drop = FALSE]
  if (nzchar(trimws(lev))) {
    mr <- mr[vapply(mr$Variable, function(vn) {
      grepl(trimws(lev), vn, fixed = TRUE)
    }, logical(1)), , drop = FALSE]
  }
  if (nrow(mr) > 1L) mr <- mr[1L, , drop = FALSE]
  mr
}
