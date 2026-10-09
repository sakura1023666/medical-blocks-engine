# tests/test_feature_selection_venn_single_method.R
.venn_list_single <- function(by_model, overlap_methods, final, U, composite_in_final) {
  composite_in_final <- intersect(composite_in_final, final)
  if (length(overlap_methods) >= 2L) {
    return(stats::setNames(
      lapply(overlap_methods, function(m) {
        unique(c(intersect(by_model[[m]] %||% character(0), U), composite_in_final))
      }),
      overlap_methods
    ))
  }
  if (length(overlap_methods) == 1L) {
    m1 <- overlap_methods[1L]
    return(stats::setNames(list(unique(final)), m1))
  }
  list()
}

lst <- .venn_list_single(
  by_model = list(lasso = c("A", "B")),
  overlap_methods = "lasso",
  final = c("A", "B"),
  U = c("A", "B"),
  composite_in_final = character(0)
)
stopifnot(length(lst) == 1L)
stopifnot(identical(names(lst), "lasso"))

cat("test_feature_selection_venn_single_method.R: OK\n")
