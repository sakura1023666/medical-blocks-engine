#!/usr/bin/env Rscript
root <- normalizePath(Sys.getenv("MEDICAL_BLOCKS_ROOT", "/mnt/e/01block/01Block-new-Final"), winslash = "/")
source(file.path(root, "R/prognosis_outcome_landmark.R"))

x <- prognosis_admin_censor_outcome(c(10, 40, 28, 5), c(1, 1, 0, 0), 28L)
stopifnot(x$futime[2] == 28, x$fustatus[2] == 0L, x$fustatus[1] == 1L)

df <- data.frame(futime = c(3, 50), fustatus = c(1L, 1L))
cfg <- list(
  project = list(study_type = "prognosis"),
  survival = list(time_var = "futime", event_var = "fustatus"),
  prognosis_outcome = list(enable = TRUE, landmark_days = 28L)
)
y <- prognosis_apply_outcome_landmark(df, cfg)
stopifnot(y$futime[2] == 28, y$fustatus[2] == 0L)
cat("OK prognosis_outcome_landmark\n")
