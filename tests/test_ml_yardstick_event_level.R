#!/usr/bin/env Rscript
## ML yardstick：Group=Control,Case 时 sens/spec 必须以 Case(second) 为事件

suppressPackageStartupMessages(library(yardstick))

source("Blocks/22_ml_models/00block_ml_eval_common.R")

set.seed(1)
n <- 200
y <- factor(rep(c("Control", "Case"), c(170, 30)), levels = c("Control", "Case"))
p_control <- ifelse(y == "Control", runif(n, 0.55, 0.95), runif(n, 0.05, 0.45))
thr <- 0.5
pred_class <- factor(ifelse(p_control >= thr, "Control", "Case"), levels = levels(y))
df <- data.frame(Group = y, .pred_class = pred_class)

cm_first <- summary(yardstick::conf_mat(df, truth = Group, estimate = .pred_class),
                    event_level = "first")
cm_second <- summary(yardstick::conf_mat(df, truth = Group, estimate = .pred_class),
                     event_level = "second")

getm <- function(cm, nm) cm$.estimate[cm$.metric == nm]

p_case <- mean(y == "Case")
acc <- mean(pred_class == y)
acc_wrong <- getm(cm_first, "sens") * p_case + getm(cm_first, "spec") * (1 - p_case)
acc_right <- getm(cm_second, "sens") * p_case + getm(cm_second, "spec") * (1 - p_case)

stopifnot(abs(acc - acc_right) < 1e-6)
stopifnot(abs(acc - acc_wrong) > 0.05)
stopifnot(getm(cm_first, "ppv") > 0.8)
stopifnot(identical(.ml_yardstick_event_level(), "second"))

cat("OK: ml yardstick event_level second aligns sens/spec with Case event rate\n")
