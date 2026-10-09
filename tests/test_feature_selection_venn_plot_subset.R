# 韦恩图截前 4 个方法时，图心 ≠ 定稿不得失败、不得覆盖 ML
.fsc07_is_plot_method_subset <- function(overlap_methods, selected_methods) {
  om <- unique(as.character(overlap_methods[nzchar(as.character(overlap_methods))]))
  sm <- unique(as.character(selected_methods[nzchar(as.character(selected_methods))]))
  length(sm) >= 2L && length(om) >= 1L && !setequal(om, sm)
}

.venn_list <- function(by_model, methods, final, composite_in_final) {
  stats::setNames(
    lapply(methods, function(m) {
      unique(c(by_model[[m]] %||% character(0), intersect(composite_in_final, final)))
    }),
    methods
  )
}

`%||%` <- function(a, b) if (!is.null(a)) a else b

by_model <- list(
  random_forest = c(
    "APSIII", "PTT", "PH", "SAPSII", "WPR", "INR", "RR", "Heart_Failure",
    "Potassium", "TotalCo2", "PaO2", "HR", "OASIS", "RBC", "Lactate", "LD",
    "Pneumonia", "AnionGap", "Bilirubin_Total", "Glucose", "Hypertension",
    "CalciumTotal", "Ventilation", "Age"
  ),
  bayesian = c(
    "APSIII", "SAPSII", "TotalCo2", "PTT", "PH", "OASIS", "INR", "RR",
    "AnionGap", "PaO2", "WPR", "Heart_Failure", "Potassium", "HR", "Pneumonia",
    "LD", "CalciumTotal", "RBC", "Hypertension", "Bilirubin_Total",
    "Ventilation", "Glucose", "Lactate", "Age"
  ),
  lvq = c(
    "HR", "RR", "RBC", "LD", "Bilirubin_Total", "Potassium", "CalciumTotal",
    "AnionGap", "Glucose", "PaO2", "PH", "TotalCo2", "INR", "PTT", "APSIII",
    "SAPSII", "OASIS", "Ventilation", "Hypertension", "Heart_Failure",
    "Pneumonia", "WPR"
  ),
  boruta = c(
    "HR", "RR", "Potassium", "PaO2", "PH", "TotalCo2", "INR", "PTT",
    "APSIII", "SAPSII", "OASIS", "Heart_Failure", "WPR"
  ),
  bagged_trees = c("APSIII", "PTT", "TotalCo2", "PH", "SAPSII", "INR", "RR")
)
selected <- c("random_forest", "bayesian", "lvq", "boruta", "bagged_trees")
plot4 <- selected[seq_len(4L)]
raw5 <- Reduce(intersect, by_model[selected])
final <- unique(c(raw5, "WPR"))
stopifnot(identical(
  sort(final),
  sort(c("APSIII", "PH", "RR", "SAPSII", "TotalCo2", "INR", "PTT", "WPR"))
))
stopifnot("WPR" %in% final)

list_plot <- .venn_list(by_model, plot4, final, "WPR")
list_canon <- .venn_list(by_model, selected, final, "WPR")
plot_center <- Reduce(intersect, list_plot)
canon_center <- Reduce(intersect, list_canon)

stopifnot(.fsc07_is_plot_method_subset(plot4, selected))
stopifnot(!.fsc07_is_plot_method_subset(selected, selected))
stopifnot(length(plot_center) > length(final))
stopifnot(setequal(canon_center, final))
## 旧闸门会因 length(plot_center)!=length(final) 误杀；新闸门只比全集
stopifnot(setequal(canon_center, final))

cat("test_feature_selection_venn_plot_subset.R: OK\n")
