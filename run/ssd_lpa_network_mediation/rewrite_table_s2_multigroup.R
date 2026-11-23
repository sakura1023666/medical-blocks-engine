#!/usr/bin/env Rscript
# Rewrite supplementary Table S2 only (multi-group path SEM with free group labels).
suppressPackageStartupMessages({ library(lavaan); library(openxlsx) })
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
source(file.path(root, "R/utils.R"), local = FALSE)
.fmt_est <- function(x, d = 3L) if (!is.finite(x)) "-" else formatC(x, format = "f", digits = d)
.fmt_p <- function(p) if (!is.finite(p)) "-" else if (p < 0.001) "<0.001" else formatC(p, format = "f", digits = 3)

proj <- file.path(
  Sys.getenv("BLOCK_RESULT_ROOT", "/mnt/g/02block_result"),
  "63_SSD", "LPA_Network_Mediaton_42214160", "by_index", "main_full_sample"
)
sr_tab <- file.path(proj, "summary_results/Tables")
ck <- readRDS(file.path(proj, "checkpoints/step05_baseline_multiclass.rds"))
d0 <- ck$ctx$data$cleaned
d0 <- d0[!is.na(d0$LCA_class), ]
for (v in c("PHQ15", "SSD12", "Whiteley8", "WHODAS", "age")) d0[[v]] <- as.numeric(d0[[v]])
d0$sex_g <- factor(tolower(as.character(d0$sex)), levels = c("female", "male"))
d0$SSD_g <- factor(tolower(trimws(as.character(d0$SSD))))
d0$SSD_g[!d0$SSD_g %in% c("yes", "no")] <- NA
d0$SSD_g <- droplevels(d0$SSD_g)
d0$sex_f <- as.integer(d0$sex_g == "female")

.path_by_group <- function(dd, group_var, group_lab, covars) {
  dd <- dd[stats::complete.cases(dd[, c("PHQ15", "SSD12", "Whiteley8", "WHODAS", group_var, covars), drop = FALSE]), ]
  dd[[group_var]] <- droplevels(dd[[group_var]])
  tabg <- table(dd[[group_var]])
  if (nlevels(dd[[group_var]]) < 2L || any(tabg < 100L)) return(NULL)
  cov_txt <- if (length(covars)) paste0(" + ", paste(covars, collapse = " + ")) else ""
  model <- paste0(
    "SSD12 ~ c(a1g1, a1g2)*PHQ15", cov_txt, "\n",
    "Whiteley8 ~ c(a2g1, a2g2)*PHQ15", cov_txt, "\n",
    "WHODAS ~ c(b1g1, b1g2)*SSD12 + c(b2g1, b2g2)*Whiteley8 + c(cp1, cp2)*PHQ15", cov_txt, "\n",
    "ind_ssd1 := a1g1*b1g1\n ind_w1 := a2g1*b2g1\n diff1 := ind_ssd1 - ind_w1\n",
    "ind_ssd2 := a1g2*b1g2\n ind_w2 := a2g2*b2g2\n diff2 := ind_ssd2 - ind_w2\n"
  )
  fit <- lavaan::sem(model, data = dd, group = group_var, estimator = "MLR")
  pe <- lavaan::parameterEstimates(fit, ci = TRUE)
  pe <- pe[pe$op == ":=" & grepl("^(ind_|diff)", pe$lhs), ]
  glab <- levels(dd[[group_var]])
  data.frame(
    Grouping = group_lab,
    Group = ifelse(grepl("1$", pe$lhs), glab[1], glab[2]),
    Path = sub("[12]$", "", pe$lhs),
    Estimate = vapply(pe$est, .fmt_est, character(1)),
    SE = vapply(pe$se, .fmt_est, character(1)),
    LLCI = vapply(pe$ci.lower, .fmt_est, character(1)),
    ULCI = vapply(pe$ci.upper, .fmt_est, character(1)),
    P = vapply(pe$pvalue, .fmt_p, character(1)),
    `Group n` = paste(paste0(names(tabg), "=", as.integer(tabg)), collapse = "; "),
    check.names = FALSE, stringsAsFactors = FALSE
  )
}

tS2 <- rbind(
  .path_by_group(d0, "sex_g", "Sex", "age"),
  .path_by_group(d0, "SSD_g", "SSD diagnosis", c("age", "sex_f"))
)
path <- file.path(sr_tab, "Table S2. Multi-group path SEM indirect effects.xlsx")
if (file.exists(path)) unlink(path)
sci_xlsx_single_header_booktabs(
  filepath = path,
  title = "Table S2. Multi-group path SEM: PHQ-15 to WHO-DAS via SSD-12 and Whiteley-8.",
  df_body = tS2, sheet = "Sheet1",
  footnotes = c(
    "Supplementary. Path model on scale totals; covariates = age (+ sex when grouping by SSD).",
    "ind_ssd / ind_w / diff are group-specific defined effects (free across groups).",
    "Pain-predominant / persistent multi-group SEM omitted (sparse cells)."
  ),
  blank_na_cells = TRUE
)
py <- Sys.which("python3")
script <- file.path(root, "python/pub_xlsx_enforce_three_line.py")
if (nzchar(py) && file.exists(script)) {
  invisible(system2(py, shQuote(c(script, path)), stdout = TRUE, stderr = TRUE))
}
print(tS2)
message("OK ", basename(path))
