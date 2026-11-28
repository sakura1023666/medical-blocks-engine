suppressPackageStartupMessages(library(geepack))
ass <- read.csv(
  "G:/02block_result/60_abdominal_obesity/by_unit/【success】CHARLS_BMI/Tables/Trajectory/Table_Kml3D_Trajectory_Assignment.csv",
  stringsAsFactors = FALSE
)
names(ass)[1:2] <- c("ID", "trajectory_cluster")
ass$ID <- as.character(ass$ID)
load("E:/01block/01Block/Data/multimorbidity_04298/panels/D01_panel_CHARLS.RData")
d <- Multimorbidity
d$ID <- as.character(d$ID)
d <- merge(d, ass, by = "ID", all.x = TRUE)
d <- d[!is.na(d$trajectory_cluster), ]
d$trajectory_cluster <- stats::relevel(factor(d$trajectory_cluster), "Group1")
d$id_int <- as.integer(factor(d$ID))
d <- d[order(d$id_int), ]

cov_lists <- list(
  Model1 = c("trajectory_cluster", "Followup_wave"),
  Model2 = c("trajectory_cluster", "Followup_wave", "Age", "Gender"),
  Model3 = c("trajectory_cluster", "Followup_wave", "Age", "Gender",
             "Education", "Smoke", "Alcohol", "Hypertension", "Diabetes")
)

for (nm in names(cov_lists)) {
  covs <- cov_lists[[nm]]
  use <- unique(c("Cognition_z", "id_int", covs))
  use <- use[use %in% names(d)]
  ds <- d[, use, drop = FALSE]
  for (cc in setdiff(covs, c("trajectory_cluster", "Followup_wave"))) {
    if (is.character(ds[[cc]])) ds[[cc]] <- factor(ds[[cc]])
  }
  ds <- ds[stats::complete.cases(ds), , drop = FALSE]
  ds <- ds[order(ds$id_int), , drop = FALSE]
  cat(nm, " n=", nrow(ds), " ids=", length(unique(ds$id_int)), "\n")
  form <- stats::as.formula(paste("Cognition_z ~", paste(covs, collapse = " + ")))
  fit <- tryCatch(
    geeglm(form, data = ds, id = ds$id_int, family = gaussian(), corstr = "exchangeable"),
    error = function(e) {
      cat(" ERR ", conditionMessage(e), "\n")
      NULL
    }
  )
  if (!is.null(fit)) cat("  ok terms=", nrow(summary(fit)$coefficients), "\n")
}
