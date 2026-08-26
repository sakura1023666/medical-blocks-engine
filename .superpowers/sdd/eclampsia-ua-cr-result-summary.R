`%||%` <- function(a,b) if(!is.null(a)) a else b
root <- "G:/02block_result/27_eclampsia/small sample prediction_39780007"
ua <- file.path(root, "by_index", "【success】UA_CR")
# ML wide validation
val <- list.files(ua, pattern = "ML performance wide validation\\.xlsx$", recursive = TRUE, full.names = TRUE)
val <- val[grepl("MIMIC_IV/Tables|Tables/", val)][1]
train <- list.files(ua, pattern = "ML performance wide training\\.xlsx$", recursive = TRUE, full.names = TRUE)
train <- train[grepl("MIMIC_IV/Tables|Tables/", train)][1]
cat("VAL:", val, "\nTRAIN:", train, "\n")
if (requireNamespace("openxlsx", quietly = TRUE) && !is.na(val) && file.exists(val)) {
  d <- openxlsx::read.xlsx(val, sheet = 1)
  cat("\n==== Validation table (head) ====\n")
  print(utils::head(d, 20))
  # try find AUC-like cols
  cn <- names(d)
  cat("\nCOLS:", paste(cn, collapse=" | "), "\n")
}
if (requireNamespace("openxlsx", quietly = TRUE) && !is.na(train) && file.exists(train)) {
  d2 <- openxlsx::read.xlsx(train, sheet = 1)
  cat("\n==== Training table (head) ====\n")
  print(utils::head(d2, 20))
}
# quartile logistic
q <- list.files(ua, pattern = "quartile\\.xlsx$", recursive = TRUE, full.names = TRUE)
q <- q[grepl("MIMIC_IV/Tables", q)][1]
cat("\nQUARTILE:", q, "\n")
if (requireNamespace("openxlsx", quietly = TRUE) && !is.na(q) && file.exists(q)) {
  dq <- openxlsx::read.xlsx(q, sheet = 1)
  print(utils::head(dq, 30))
}
# status json
st <- file.path(ua, "_batch_status.json")
if (file.exists(st)) {
  cat("\nSTATUS:\n")
  cat(paste(readLines(st, warn=FALSE), collapse="\n"), "\n")
}
