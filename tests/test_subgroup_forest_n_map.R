# tests/test_subgroup_forest_n_map.R
# Yes/No 共病亚组（饮酒 / 高血压 / 糖尿病）N 覆盖不得互相踩键
root <- normalizePath(".")
if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}
source(file.path(root, "R/subgroup_forest_plot.R"), local = FALSE)

set.seed(1)
n <- 200L
dat <- data.frame(
  Alcohol_drinking = c(rep("Yes", 40L), rep("No", 160L)),
  Hypertension     = c(rep("Yes", 90L), rep("No", 110L)),
  Diabetes         = c(rep("Yes", 25L), rep("No", 175L)),
  Gender           = c(rep("Female", 120L), rep("Male", 80L)),
  stringsAsFactors = FALSE
)

n_map <- subgroup_stratum_n_map(
  dat,
  c("Alcohol_drinking", "Hypertension", "Diabetes", "Gender")
)
stopifnot(is.list(n_map$Alcohol_drinking), is.list(n_map$Hypertension))
stopifnot(identical(n_map$Alcohol_drinking[["Yes"]], 40L))
stopifnot(identical(n_map$Hypertension[["Yes"]], 90L))
stopifnot(identical(n_map$Diabetes[["Yes"]], 25L))
# pretty 变量名也要能查到
stopifnot(identical(n_map[["Alcohol drinking"]][["Yes"]], 40L))

df <- data.frame(
  Variable = c(
    "Alcohol drinking", "  Yes", "  No",
    "Hypertension", "  Yes", "  No",
    "Diabetes", "  Yes", "  No",
    "Gender", "  Female", "  Male"
  ),
  Count = 1L,
  Percent = "0.5",
  stringsAsFactors = FALSE
)
out <- subgroup_overlay_forest_count(df, n_map, total_n = n, n_source = "full_stratum")
stopifnot(identical(as.integer(out$Count[out$Variable == "  Yes"][1L]), 40L))
stopifnot(identical(as.integer(out$Count[out$Variable == "  Yes"][2L]), 90L))
stopifnot(identical(as.integer(out$Count[out$Variable == "  Yes"][3L]), 25L))
stopifnot(identical(as.integer(out$Count[out$Variable == "  No"][1L]), 160L))
stopifnot(identical(as.integer(out$Count[out$Variable == "  No"][2L]), 110L))
stopifnot(identical(as.integer(out$Count[out$Variable == "  No"][3L]), 175L))
stopifnot(identical(as.integer(out$Count[out$Variable == "  Female"]), 120L))
stopifnot(!identical(
  as.integer(out$Count[out$Variable == "  Yes"][1L]),
  as.integer(out$Count[out$Variable == "  Yes"][2L])
))

cat("test_subgroup_forest_n_map.R: OK\n")
