# Table S6：插补前后对照（课题表）。Table S7/S8：调用引擎多库中介（BMI/SBP，不用血脂）。

suppressPackageStartupMessages({
  library(data.table)
  library(survival)
})
engine <- if (dir.exists("E:/01block/01Block-new-Final")) {
  "E:/01block/01Block-new-Final"
} else {
  "/mnt/e/01block/01Block-new-Final"
}
source(file.path(engine, "R/utils.R"))
source(file.path(engine, "R/pv2_pub_names.R"))
source(file.path(engine, "run/prognosis_v2/pv2_paths.R"), local = FALSE)
pv2_ensure_dirs()

tab_dir <- pv2_tab_dir
ckpt <- pv2_ckpt_dir
data_root <- pv2_data_root
before <- readRDS(pv2_artifact("before_imputation_dbs.rds"))
after <- readRDS(pv2_artifact("imputed_dbs.rds"))
# 确保生命体征含 DBP（中介变量，观察值挂入，不另插补）
if (exists("pv2_attach_dbp", mode = "function") ||
    { source(file.path(engine, "run/prognosis_v2/pv2_mediation.R"), local = FALSE); TRUE }) {
  before <- pv2_attach_dbp(before)
  after <- pv2_attach_dbp(after)
}

fmt_p <- function(p) {
  if (!is.finite(p)) return("")
  if (p < 0.001) "<0.001" else sprintf("%.3f", p)
}
is_normal_vec <- function(x) {
  x <- x[!is.na(x)]
  n <- length(x)
  if (n < 3L) return(FALSE)
  p <- tryCatch({
    if (n > 5000L) stats::ks.test(scale(x), "pnorm")$p.value else stats::shapiro.test(x)$p.value
  }, error = function(e) 0)
  is.finite(p) && p >= 0.05
}
same_num <- function(a, b) {
  isTRUE(all.equal(as.numeric(a), as.numeric(b), tolerance = 1e-8, check.attributes = FALSE))
}

cont_spec <- c(Age = "Age, years", BMI = "BMI, kg/m2", SBP = "SBP, mmHg", DBP = "DBP, mmHg")
cat_spec <- list(
  Gender = c("Male", "Female"),
  Education = c("Higher", "Below"),
  Smoke = c("Yes", "No"),
  Alcohol = c("Yes", "No"),
  Hypertension = c("Yes", "No"),
  Diabetes = c("Yes", "No")
)
cat_lab <- c(Gender = "Sex", Education = "Education", Smoke = "Smoking", Alcohol = "Drinking",
             Hypertension = "Hypertension", Diabetes = "Diabetes")
sections <- list(
  Demographics = c("Age", "BMI", "Gender", "Education", "Smoke", "Alcohol"),
  `Vital Signs` = c("SBP", "DBP"),
  Comorbidities = c("Hypertension", "Diabetes")
)

for (nm in c("NHANES", "CHARLS", "SHHS")) {
  b <- as.data.frame(before[[nm]])
  a <- as.data.frame(after[[nm]])
  b$ID <- as.character(b$ID)
  a$ID <- as.character(a$ID)
  a <- a[match(b$ID, a$ID), ]
  stopifnot(identical(b$ID, a$ID))
  rows <- list()
  level_rows <- integer(0)
  add <- function(v, stat, before_cell, after_cell, p) {
    rows[[length(rows) + 1L]] <<- data.frame(
      Variable = v, Statistic = stat,
      `Before imputation` = before_cell, `After imputation` = after_cell, `P value` = p,
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }
  for (sec in names(sections)) {
    add(sec, "", "", "", "")
    for (v in sections[[sec]]) {
      xb <- b[[v]]
      xa <- a[[v]]
      if (v %in% names(cont_spec)) {
        normal <- is_normal_vec(xa)
        p <- if (same_num(xb, xa)) 1 else tryCatch(
          if (normal) stats::t.test(xa, xb)$p.value else stats::wilcox.test(xa, xb)$p.value,
          error = function(e) NA_real_
        )
        add(cont_spec[[v]], if (normal) "Mean \u00b1 SD" else "Median (Q1, Q3)",
            fmt_continuous(xb, normal), fmt_continuous(xa, normal), fmt_p(p))
      } else {
        p <- if (identical(as.character(xb), as.character(xa))) 1 else tryCatch({
          tbl <- table(
            c(as.character(xb), as.character(xa)),
            c(rep("Before", length(xb)), rep("After", length(xa)))
          )
          if (any(tbl < 5)) stats::fisher.test(tbl, simulate.p.value = TRUE, B = 2000)$p.value
          else stats::chisq.test(tbl)$p.value
        }, error = function(e) NA_real_)
        add(unname(cat_lab[[v]]), "n (%)", "", "", fmt_p(p))
        for (lv in cat_spec[[v]]) {
          level_rows <- c(level_rows, length(rows) + 1L)
          nb <- sum(as.character(xb) == lv, na.rm = TRUE)
          na_ <- sum(as.character(xa) == lv, na.rm = TRUE)
          add(paste0("  ", lv), "",
              sprintf("%d (%s%%)", nb, fmt_num(100 * nb / nrow(b))),
              sprintf("%d (%s%%)", na_, fmt_num(100 * na_ / nrow(a))), "")
        }
      }
      level_rows <- c(level_rows, length(rows) + 1L)
      add("  Missing (%)", "",
          paste0(fmt_num(100 * mean(is.na(xb))), "%"),
          paste0(fmt_num(100 * mean(is.na(xa))), "%"), "")
    }
  }
  body <- do.call(rbind, rows)
  if (!exists("pv2_table_xlsx_name", mode = "function")) {
    source(file.path(engine, "R/pv2_pub_names.R"), local = FALSE)
  }
  .single <- pv2_is_single_db(names(before))
  note_path <- pv2_artifact("Imputation_methods_note.txt", must_exist = FALSE)
  if (is.na(note_path)) note_path <- file.path(pv2_ckpt_dir, "Imputation_methods_note.txt")
  mi_note <- if (file.exists(note_path)) {
    paste(readLines(note_path, warn = FALSE), collapse = " ")
  } else {
    "MICE (cart, m = 1, maxit = 5, seed = 1234). Single completed dataset used for all analyses."
  }
  path <- file.path(
    tab_dir,
    pv2_table_xlsx_name(
      "Table S6", "Baseline characteristics before and after imputation",
      db = nm, single_db = .single
    )
  )
  sci_xlsx_single_header_booktabs(
    path, title = "Table S6. Baseline characteristics before and after imputation",
    df_body = body, footnotes = c(
      mi_note,
      "Exposure, follow-up time, death and survey weights were not imputed.",
      "P values compare the distribution before and after imputation."
    ),
    level_row_idx = level_rows + 1L
  )
  message(basename(path))
}
old_s6 <- list.files(tab_dir, pattern = "^Table S6-.*Missingness.*\\.xlsx$", full.names = TRUE)
if (length(old_s6)) unlink(old_s6)

# ---- S7 / S8：舒张压（DBP）中介；图仅主库 ----
if (!identical(Sys.getenv("PV2_S6_ONLY"), "1")) {
  source(file.path(engine, "run/prognosis_v2/pv2_s7_s8_nonlipid.R"), local = FALSE)
  old_s7 <- list.files(tab_dir, pattern = "^Table S7-.*blood lipids.*\\.xlsx$", full.names = TRUE)
  if (length(old_s7)) unlink(old_s7)
}
message("done")
