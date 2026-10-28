# 每个数据库一张 xlsx，三线表。Table 1 按死亡结局分层（Survivor / Non-survivor），睡眠是暴露行。

suppressPackageStartupMessages({
  library(data.table)
  library(survival)
  library(survey)
})
engine <- if (dir.exists("E:/01block/01Block-new-Final")) {
  "E:/01block/01Block-new-Final"
} else {
  "/mnt/e/01block/01Block-new-Final"
}
source(file.path(engine, "R/utils.R"))
source(file.path(engine, "R/pub_figure_export.R"))
source(file.path(engine, "R/pv2_pub_names.R"))
source(file.path(engine, "run/prognosis_v2/pv2_paths.R"), local = FALSE)
options(survey.lonely.psu = "adjust")

pv2_ensure_dirs()
out_root <- pv2_out_root
tab_dir <- pv2_tab_dir
ckpt <- pv2_ckpt_dir
dbs <- readRDS(if (exists("pv2_artifact", mode = "function")) pv2_artifact("imputed_dbs.rds") else file.path(tab_dir, "imputed_dbs.rds"))
if (!all(vapply(dbs, function(d) "DBP" %in% names(d), logical(1)))) {
  source(file.path(engine, "run/prognosis_v2/pv2_mediation.R"), local = FALSE)
  dbs <- pv2_attach_dbp(dbs)
}
dbs <- pv2_apply_sleep_group5(dbs)
dbs_nm <- intersect(pv2_all_dbs, names(dbs))
if (!length(dbs_nm)) dbs_nm <- names(dbs)
.pv2_single_db <- pv2_is_single_db(dbs_nm)
.pv2_read_m3 <- function() {
  note <- if (exists("pv2_artifact", mode = "function")) {
    pv2_artifact("Covariate_selection_note.txt")
  } else {
    n1 <- file.path(ckpt, "Covariate_selection_note.txt")
    if (file.exists(n1)) n1 else file.path(tab_dir, "Covariate_selection_note.txt")
  }
  if (!file.exists(note)) {
    return(c("Age", "Gender", "SBP", "Education", "Hypertension", "Alcohol", "Smoke", "BMI"))
  }
  lines <- readLines(note, warn = FALSE)
  hit <- grep("^Model 3 =", lines, value = TRUE)[1]
  if (!length(hit) || is.na(hit)) {
    return(c("Age", "Gender", "SBP", "Education", "Hypertension", "Alcohol", "Smoke", "BMI"))
  }
  trimws(strsplit(sub("^Model 3 =\\s*", "", hit), "\\s*\\+\\s*")[[1]])
}
m3_cov <- .pv2_read_m3()
message("Export Model 3: ", paste(m3_cov, collapse = ", "))

fmt_p <- function(p) {
  if (!is.finite(p)) return("")
  if (p < 0.001) "<0.001" else sprintf("%.3f", p)
}
mean_sd <- function(x) sprintf("%.2f (%.2f)", mean(x, na.rm = TRUE), stats::sd(x, na.rm = TRUE))
med_iqr <- function(x) {
  q <- stats::quantile(x, c(0.25, 0.5, 0.75), na.rm = TRUE)
  sprintf("%.2f (%.2f, %.2f)", q[2], q[1], q[3])
}
n_pct <- function(k, n) sprintf("%d (%.1f%%)", k, if (n > 0) 100 * k / n else NA_real_)
skewed <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) < 3 || length(x) > 5000) return(FALSE)
  tryCatch(stats::shapiro.test(x)$p.value < 0.05, error = function(e) TRUE)
}

write_one <- function(db, title, df, footnotes, level_rows = integer(0)) {
  stem <- sub("^Table (S?[0-9]+)\\. ", "", title)
  num <- sub("^Table (S?[0-9]+)\\. .*", "Table \\1", title)
  path <- file.path(
    tab_dir,
    pv2_table_xlsx_name(num, stem, db = db, single_db = .pv2_single_db)
  )
  sci_xlsx_single_header_booktabs(
    path, title = pv2_table_title(num, stem), df_body = df,
    footnotes = footnotes,
    level_row_idx = if (length(level_rows)) level_rows + 1L else NULL
  )
  message(basename(path))
  invisible(path)
}

# ---------- Table 1：结局分层，睡眠为暴露行 ----------
source(file.path(engine, "R/competing_supp_xlsx.R"))

is_normal_vec <- function(x) {
  x <- x[!is.na(x)]
  n <- length(x)
  if (n < 3L) return(FALSE)
  p <- tryCatch({
    if (n > 5000L) stats::ks.test(scale(x), "pnorm")$p.value else stats::shapiro.test(x)$p.value
  }, error = function(e) 0)
  is.finite(p) && p >= 0.05
}
q3 <- function(obj) {
  if (is.list(obj) && !is.null(obj$quantiles)) obj <- obj$quantiles
  if (is.list(obj) && !is.matrix(obj)) obj <- obj[[1L]]
  v <- suppressWarnings(as.numeric(obj))
  v <- v[is.finite(v)]
  if (length(v) < 3L && (is.matrix(obj) || is.data.frame(obj))) {
    v <- suppressWarnings(as.numeric(as.matrix(obj)[1L, ]))
    v <- v[is.finite(v)]
  }
  if (length(v) < 3L) stop("survey quantile could not be read")
  v[1:3]
}
svy_des <- function(dd) {
  survey::svydesign(ids = ~psu, strata = ~strata, weights = ~survey_weight, data = dd, nest = TRUE)
}
cont_cell <- function(dd, var, normal, weighted) {
  x <- dd[[var]]
  if (weighted) {
    desg <- svy_des(dd)
    if (normal) {
      m <- survey::svymean(stats::as.formula(paste0("~", var)), desg, na.rm = TRUE)
      sprintf("%.2f (%.2f)", as.numeric(m)[1], as.numeric(survey::SE(m))[1])
    } else {
      qs <- survey::svyquantile(stats::as.formula(paste0("~", var)), desg,
                                quantiles = c(0.25, 0.5, 0.75), na.rm = TRUE, ci = FALSE)
      q <- q3(qs)
      sprintf("%.2f (%.2f, %.2f)", q[2], q[1], q[3])
    }
  } else if (normal) {
    mean_sd(x)
  } else {
    med_iqr(x)
  }
}
cat_cell <- function(dd, var, lv, weighted) {
  k <- sum(dd[[var]] == lv, na.rm = TRUE)
  n <- sum(!is.na(dd[[var]]))
  if (!weighted) return(n_pct(k, n))
  dd$yy <- as.numeric(dd[[var]] == lv)
  pr <- as.numeric(survey::svymean(~yy, svy_des(dd), na.rm = TRUE))[1]
  sprintf("%d (%.1f%%)", k, 100 * pr)
}
p_cont <- function(d, var, normal, weighted, des) {
  if (weighted) {
    as.numeric(survey::svyranktest(
      stats::as.formula(paste(var, "~ status")), design = des, test = "wilcoxon"
    )$p.value)
  } else if (normal) {
    stats::t.test(d[[var]] ~ d$status)$p.value
  } else {
    stats::wilcox.test(d[[var]] ~ d$status)$p.value
  }
}
p_cat <- function(d, var, weighted, des) {
  if (weighted) {
    return(as.numeric(survey::svychisq(
      stats::as.formula(paste0("~", var, "+ status")), design = des
    )$p.value))
  }
  tab <- table(d[[var]], d$status)
  if (any(tab < 5)) {
    stats::fisher.test(tab, simulate.p.value = TRUE, B = 2000)$p.value
  } else {
    suppressWarnings(stats::chisq.test(tab)$p.value)
  }
}

# 暴露放在最后一节，与预后 Table 1 一致
layout <- list(
  Demographics = list(
    cont = c(Age = "Age, years", BMI = "BMI, kg/m2"),
    cats = list(Gender = c("Male", "Female"), Education = c("Higher", "Below"),
                Smoke = c("Yes", "No"), Alcohol = c("Yes", "No"))
  ),
  `Vital Signs` = list(cont = c(SBP = "SBP, mmHg", DBP = "DBP, mmHg"), cats = list()),
  Comorbidities = list(
    cont = c(),
    cats = list(Hypertension = c("Yes", "No"), Diabetes = c("Yes", "No"))
  ),
  Exposure = list(
    cont = c(Sleep_hours = "Sleep duration, hours"),
    cats = list(Sleep_Group = unname(pv2_sleep_labels[pv2_sleep_levels_display]))
  )
)
cat_lab <- c(Gender = "Sex", Education = "Education", Smoke = "Smoking", Alcohol = "Drinking",
             Sleep_Group = "Sleep duration", Hypertension = "Hypertension", Diabetes = "Diabetes")

if (!identical(Sys.getenv("PV2_SKIP_TABLE1"), "1")) {
old_t1 <- list.files(tab_dir, pattern = "^Table 1-.*\\.xlsx$", full.names = TRUE)
if (length(old_t1)) unlink(old_t1)

for (nm in dbs_nm) {
  d <- as.data.frame(dbs[[nm]])
  ev <- if ("fustatus" %in% names(d)) d$fustatus else d$event
  d <- d[!is.na(ev), ]
  ev <- ev[!is.na(ev)]
  d$status <- factor(ifelse(ev == 1, "Non-survivor", "Survivor"),
                     levels = c("Survivor", "Non-survivor"))
  d$Sleep_Group <- factor(
    unname(pv2_sleep_labels[as.character(pv2_sleep_group5(d$Sleep_hours, ref_first = FALSE))]),
    levels = unname(pv2_sleep_labels[pv2_sleep_levels_display])
  )
  weighted <- identical(nm, "NHANES")
  if (weighted) {
    d <- d[!is.na(d$survey_weight) & d$survey_weight > 0 & !is.na(d$psu) & !is.na(d$strata), ]
  }
  des <- if (weighted) svy_des(d) else NULL
  slices <- list(Overall = d, Survivor = d[d$status == "Survivor", ],
                 `Non-survivor` = d[d$status == "Non-survivor", ])
  headers <- c(
    sprintf("Overall, N = %d", nrow(slices$Overall)),
    sprintf("Survivor, N = %d", nrow(slices$Survivor)),
    sprintf("Non-survivor, N = %d", nrow(slices[["Non-survivor"]]))
  )
  rows <- list()
  level_rows <- integer(0)
  section_names <- character(0)
  add <- function(lab, vals, p = "") rows[[length(rows) + 1L]] <<- c(lab, vals, p)
  for (sec in names(layout)) {
    section_names <- c(section_names, sec)
    add(sec, rep("", 3), "")
    spec <- layout[[sec]]
    for (v in names(spec$cont)) {
      normal <- is_normal_vec(d[[v]])
      vals <- vapply(slices, function(dd) cont_cell(dd, v, normal, weighted), character(1))
      add(spec$cont[[v]], vals, fmt_p(p_cont(d, v, normal, weighted, des)))
    }
    for (v in names(spec$cats)) {
      add(cat_lab[[v]], rep("", 3), fmt_p(p_cat(d, v, weighted, des)))
      for (lv in spec$cats[[v]]) {
        level_rows <- c(level_rows, length(rows) + 1L)
        vals <- vapply(slices, function(dd) cat_cell(dd, v, lv, weighted), character(1))
        add(paste0("  ", lv), vals, "")
      }
    }
  }
  body <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
  names(body) <- c("Characteristic", headers, "p-value")
  hdr <- stats::setNames(as.data.frame(t(names(body)), stringsAsFactors = FALSE), names(body))
  show <- rbind(hdr, body)
  show[1, ] <- as.character(show[1, ])
  footnotes <- table1_baseline_xlsx_footnotes(n_groups = 2L, weighted = weighted)
  # tbl 行号含表头；write_one 的 level_row_idx 会再 +1，这里直接写工作簿
  stem <- "Baseline characteristics"
  path <- file.path(tab_dir, pv2_table_xlsx_name("Table 1", stem, db = nm, single_db = .pv2_single_db))
  .sci_xlsx_write_three_line_workbook(
    path, title = pv2_table_title("Table 1", stem), tbl_df_new = show,
    footnotes = footnotes,
    insert_map = stats::setNames(rep(1L, length(section_names)), section_names),
    level_row_idx = level_rows + 1L
  )
  message(basename(path))
}
}

if (identical(Sys.getenv("PV2_TABLE1_ONLY"), "1")) quit(save = "no")

# ---------- split a stacked csv into one xlsx per database ----------
split_write <- function(df, title, footnotes, drop_db = TRUE) {
  for (nm in intersect(dbs_nm, unique(df$database))) {
    sub <- df[df$database == nm, , drop = FALSE]
    if (drop_db) sub$database <- NULL
    write_one(nm, title, sub, footnotes)
  }
}

read_pub <- function(name) {
  p1 <- file.path(tab_dir, name)
  p2 <- file.path(ckpt, name)
  as.data.frame(fread(if (file.exists(p1)) p1 else p2))
}
model_fn <- c(
  "The Model 1 was non-adjusted.",
  "The Model 2 was adjusted by: Age, Gender.",
  paste0("The Model 3 was adjusted by: ", paste(m3_cov, collapse = ", "),
         ". Model 3 covariates were selected from the primary cohorts (NHANES, SHHS). CHARLS is the validation cohort."),
  "Primary cohorts: NHANES, SHHS. Validation cohort: CHARLS."
)

# Table 2：人数、死亡数、累积发病率、每万人年发病率（95% CI）。不做线性 P for trend（U 形关联）。
if (!identical(Sys.getenv("PV2_TABLE3_ONLY"), "1") &&
    !identical(Sys.getenv("PV2_TABLE4_ONLY"), "1")) {
for (nm in dbs_nm) {
  d <- as.data.frame(dbs[[nm]])
  d$Sleep_Group <- pv2_sleep_group5(d$Sleep_hours, ref_first = TRUE)
  d <- d[!is.na(d$Sleep_Group) & !is.na(d$futime_years) & d$futime_years > 0 & !is.na(d$fustatus), ]
  rows <- list(c("Sleep duration", "", "", "", ""))
  for (g in pv2_sleep_levels_display) {
    sub <- d[as.character(d$Sleep_Group) == g, ]
    n <- nrow(sub)
    ev <- sum(sub$fustatus == 1)
    pyrs <- sum(sub$futime_years)
    ci <- stats::poisson.test(ev, T = pyrs)$conf.int * 1e4
    lab <- paste0("  ", pv2_sleep_labels[[g]])
    rows[[length(rows) + 1L]] <- c(
      lab, as.character(n), as.character(ev), sprintf("%.2f", 100 * ev / max(n, 1L)),
      sprintf("%.2f\n(%.2f–%.2f)", 1e4 * ev / max(pyrs, .Machine$double.eps), ci[1], ci[2])
    )
  }
  body <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
  names(body) <- c(
    "Variable", "Participants", "All-cause mortality", "Cumulative incidence (%)",
    "Per 10,000\nperson-year\n(95% CI)"
  )
  write_one(
    nm, "Table 2. Incidence of all-cause mortality", body,
    c(
      "Per 10,000 person-year is events / person-years x 10,000. The interval is the exact Poisson 95% confidence interval.",
      "A linear P for trend across ordered sleep categories was not reported because sleep duration and mortality typically follow a U-shaped pattern; nonlinearity is assessed with restricted cubic splines (Figure 4)."
    ),
    level_rows = 2:(1 + length(pv2_sleep_levels_display))
  )
}
}
if (identical(Sys.getenv("PV2_TABLE2_ONLY"), "1")) quit(save = "no")

if (!identical(Sys.getenv("PV2_TABLE4_ONLY"), "1")) {
# Table 3：双行表头；m>1 时 Cox 走 Rubin（pv2_mi_cox.R），禁止只报 complete#1
source(file.path(engine, "run/prognosis_v2/pv2_mi_cox.R"), local = FALSE)
.mids_all <- {
  p <- if (exists("pv2_artifact", mode = "function")) {
    pv2_artifact("imputed_mids.rds", must_exist = FALSE)
  } else {
    file.path(tab_dir, "imputed_mids.rds")
  }
  if (is.na(p)) p <- file.path(tab_dir, "imputed_mids.rds")
  if (file.exists(p)) readRDS(p) else list()
}
cox_extract <- function(d, rhs, db_name = NULL) {
  weighted <- isTRUE((db_name %||% d$database[1]) == "NHANES") &&
    "survey_weight" %in% names(d) && any(!is.na(d$survey_weight))
  mids <- if (!is.null(db_name) && db_name %in% names(.mids_all)) .mids_all[[db_name]] else NULL
  expo_keep <- intersect(
    c("Sleep_hours", "Sleep_Group", "sleep_sd", "sleep_ord", "futime_years", "fustatus",
      "ID", "subject_id"),
    names(d)
  )
  out <- pv2_cox_extract(
    d, rhs, mids = mids, weighted = weighted, rubin = TRUE,
    exposure_keep = expo_keep
  )
  if (is.null(out)) {
    # 极端回退：无 mids 时单套
    out <- pv2_cox_extract(d, rhs, mids = NULL, weighted = weighted, rubin = FALSE)
  }
  out
}
one_term <- function(fit, key) {
  i <- grep(key, fit$term, fixed = TRUE)
  if (!length(i)) return(NULL)
  fit[i[1], , drop = FALSE]
}
hr_txt <- function(row) {
  if (is.null(row)) return("")
  sprintf("%.3f (%.3f–%.3f)", row$hr, row$lo, row$hi)
}
h1 <- c("", "", "Model 1", "Model 1", "Model 2", "Model 2", "Model 3", "Model 3")
h2 <- c("Variable", "N (%)", "HR (95% CI)", "P", "HR (95% CI)", "P", "HR (95% CI)", "P")

for (nm in dbs_nm) {
  d <- as.data.frame(dbs[[nm]])
  d$database <- nm
  d$Sleep_Group <- pv2_sleep_group5(d$Sleep_hours, ref_first = TRUE)
  need <- c("futime_years", "fustatus", "Sleep_hours", "Sleep_Group", m3_cov)
  d <- d[stats::complete.cases(d[, need]), ]
  d <- d[!is.na(d$futime_years) & d$futime_years > 0, ]
  n_all <- nrow(d)
  d$sleep_sd <- as.numeric(scale(d$Sleep_hours))
  specs <- list(
    Model1 = list(sd = "sleep_sd", grp = "Sleep_Group"),
    Model2 = list(sd = "sleep_sd + Age + Gender", grp = "Sleep_Group + Age + Gender"),
    Model3 = list(
      sd = paste(c("sleep_sd", m3_cov), collapse = " + "),
      grp = paste(c("Sleep_Group", m3_cov), collapse = " + ")
    )
  )
  fits <- lapply(specs, function(sp) {
    list(
      sd = cox_extract(d, sp$sd, db_name = nm),
      grp = cox_extract(d, sp$grp, db_name = nm)
    )
  })
  cell_grp <- function(md, key) {
    row <- one_term(fits[[md]]$grp, key)
    c(hr_txt(row), if (is.null(row)) "" else fmt_p(row$p))
  }
  cell_sd <- function(md) {
    row <- one_term(fits[[md]]$sd, "sleep_sd")
    c(hr_txt(row), if (is.null(row)) "" else fmt_p(row$p))
  }
  n_of <- function(g) sum(as.character(d$Sleep_Group) == g)
  row_of <- function(lab, ncell, pieces) c(lab, ncell, unlist(pieces))
  body_rows <- list(
    row_of("Sleep duration", "", lapply(c("Model1", "Model2", "Model3"), function(md) c("", ""))),
    row_of("  per 1 SD", as.character(n_all), lapply(c("Model1", "Model2", "Model3"), cell_sd)),
    row_of("  7-8 h", sprintf("%d (%.2f%%)", n_of("7-8"), 100 * n_of("7-8") / n_all),
           lapply(c("Model1", "Model2", "Model3"), function(md) c("Reference", "")))
  )
  for (g in c("<5", "5-6", "6-7", ">=9")) {
    key <- paste0("Sleep_Group", g)
    body_rows[[length(body_rows) + 1L]] <- row_of(
      paste0("  ", pv2_sleep_labels[[g]]),
      sprintf("%d (%.2f%%)", n_of(g), 100 * n_of(g) / n_all),
      lapply(c("Model1", "Model2", "Model3"), function(md) cell_grp(md, key))
    )
  }
  body <- as.data.frame(do.call(rbind, body_rows), stringsAsFactors = FALSE)
  names(body) <- paste0("c", seq_len(ncol(body)))
  path <- file.path(
    tab_dir,
    pv2_table_xlsx_name("Table 3", "Cox proportional hazards models", db = nm, single_db = .pv2_single_db)
  )
  .mi_note <- if (exists("pv2_artifact", mode = "function")) {
    pv2_artifact("Imputation_methods_note.txt", must_exist = FALSE)
  } else NA_character_
  if (is.na(.mi_note)) .mi_note <- file.path(tab_dir, "Imputation_methods_note.txt")
  mi_ft <- if (file.exists(.mi_note)) {
    readLines(.mi_note, warn = FALSE)
  } else {
    pv2_mi_methods_footnote()
  }
  ft <- c(
    model_fn,
    mi_ft,
    if (nm == "NHANES") {
      "NHANES models are survey-weighted (WTMEC2YR, PSU and strata)."
    } else {
      "Models are unweighted."
    },
    "per 1 SD is sleep duration standardized within the cohort.",
    "A linear P for trend across ordered sleep categories was not reported because sleep duration and mortality typically follow a U-shaped pattern; nonlinearity is assessed with restricted cubic splines (Figure 4)."
  )
  .sci_xlsx_double_header_booktabs(
    path, title = "Table 3. Cox proportional hazards models",
    df_body = body, h1 = h1, h2 = h2, footnotes = ft
  )
  message(basename(path))
}
}
if (identical(Sys.getenv("PV2_TABLE3_ONLY"), "1")) quit(save = "no")

# Table 4：Fine-Gray。CHARLS 心血管死亡 = Harmonized EOL ragcod 2；死因缺失的死亡不进入竞争风险。
eol_cause <- fread(file.path(pv2_data_root, "CHARLS/Exit_Interview/charls_eol_cause.csv"),
                   colClasses = c(ID = "character"))
eol_cause[, ID := as.character(ID)]
dbs$CHARLS <- merge(as.data.frame(dbs$CHARLS), as.data.frame(eol_cause[, .(ID, ragcod)]), by = "ID", all.x = TRUE)
dbs$CHARLS$cvd_status <- ifelse(dbs$CHARLS$fustatus == 1 & is.na(dbs$CHARLS$ragcod), NA_integer_,
                                as.integer(dbs$CHARLS$fustatus == 1 & dbs$CHARLS$ragcod == 2))
if (!exists("m3_cov")) {
  m3_cov <- c("Age", "Gender", "SBP", "Education", "Hypertension", "Alcohol", "Smoke", "BMI")
}
fg_one <- function(d, nm) {
  d <- d[!is.na(d$cvd_status), ]
  d$etime <- d$futime_years
  d$status <- factor(ifelse(d$cvd_status == 1, "cvd", ifelse(d$fustatus == 1, "other", "censor")),
                     levels = c("censor", "cvd", "other"))
  for (v in c("Gender", "Education", "Hypertension", "Alcohol", "Smoke")) d[[v]] <- factor(d[[v]])
  d$Sleep_Group <- pv2_sleep_group5(d$Sleep_hours, ref_first = TRUE)
  d <- d[stats::complete.cases(d[, c("etime", "status", "Sleep_hours", "Sleep_Group", m3_cov)]) & d$etime > 0, ]
  d$sleep_sd <- as.numeric(scale(d$Sleep_hours))
  fg_rhs <- paste(c("Sleep_Group", "sleep_sd", m3_cov), collapse = " + ")
  if (nm == "NHANES") fg_rhs <- paste(fg_rhs, "+ survey_weight")
  fg <- survival::finegray(stats::as.formula(paste("Surv(etime, status) ~", fg_rhs)),
                           data = d, etype = "cvd")
  w <- if (nm == "NHANES") fg$fgwt * fg$survey_weight else fg$fgwt
  fit_one <- function(rhs) {
    fit <- survival::coxph(stats::as.formula(paste("Surv(fgstart, fgstop, fgstatus) ~", rhs)),
                           data = fg, weights = w)
    s <- summary(fit)
    data.frame(term = rownames(s$conf.int), shr = s$conf.int[, 1], lo = s$conf.int[, 3],
               hi = s$conf.int[, 4], p = s$coefficients[, "Pr(>|z|)"], stringsAsFactors = FALSE)
  }
  specs <- list(
    Model1 = list(sd = "sleep_sd", grp = "Sleep_Group"),
    Model2 = list(sd = "sleep_sd + Age + Gender", grp = "Sleep_Group + Age + Gender"),
    Model3 = list(
      sd = paste(c("sleep_sd", m3_cov), collapse = " + "),
      grp = paste(c("Sleep_Group", m3_cov), collapse = " + ")
    )
  )
  fits <- lapply(specs, function(sp) lapply(sp, fit_one))
  pick <- function(fit, key) {
    i <- grep(key, fit$term, fixed = TRUE)
    if (!length(i)) return(NULL)
    fit[i[1], , drop = FALSE]
  }
  shr_txt <- function(row) if (is.null(row)) "" else sprintf("%.3f (%.3f–%.3f)", row$shr, row$lo, row$hi)
  cell <- function(md, kind, key) {
    row <- if (nzchar(key)) pick(fits[[md]][[kind]], key) else NULL
    c(shr_txt(row), if (is.null(row)) "" else fmt_p(row$p))
  }
  n_all <- nrow(d)
  n_of <- function(g) sum(as.character(d$Sleep_Group) == g)
  row_of <- function(lab, pieces) c(lab, unlist(pieces))
  mds <- c("Model1", "Model2", "Model3")
  body_rows <- list(
    row_of("Sleep duration", lapply(mds, function(md) c("", ""))),
    row_of("  per 1 SD", lapply(mds, function(md) cell(md, "sd", "sleep_sd"))),
    row_of("  7-8 h", lapply(mds, function(md) c("Reference", "")))
  )
  for (g in c("<5", "5-6", "6-7", ">=9")) {
    body_rows[[length(body_rows) + 1L]] <- row_of(
      paste0("  ", pv2_sleep_labels[[g]]),
      lapply(mds, function(md) cell(md, "grp", paste0("Sleep_Group", g)))
    )
  }
  body <- as.data.frame(do.call(rbind, body_rows), stringsAsFactors = FALSE)
  list(body = body, n = n_all, n_cvd = sum(d$cvd_status == 1, na.rm = TRUE),
       n_other = sum(d$fustatus == 1 & d$cvd_status != 1, na.rm = TRUE))
}
h1_fg <- c("", "Model 1", "Model 1", "Model 2", "Model 2", "Model 3", "Model 3")
h2_fg <- c("Variable", "sHR (95% CI)", "P", "sHR (95% CI)", "P", "sHR (95% CI)", "P")
for (nm in c("NHANES", "CHARLS", "SHHS")) {
  got <- fg_one(as.data.frame(dbs[[nm]]), nm)
  path <- file.path(
    tab_dir,
    pv2_table_xlsx_name("Table 4", "Competing risk analysis of cardiovascular death",
                        db = nm, single_db = .pv2_single_db)
  )
  ft <- c(
    "Fine-Gray subdistribution hazard for cardiovascular death. Other deaths are the competing event.",
    model_fn,
    if (nm == "NHANES") "NHANES models are survey-weighted (WTMEC2YR, PSU and strata)." else "Models are unweighted.",
    "per 1 SD is sleep duration standardized within the cohort.",
    "A linear P for trend across ordered sleep categories was not reported because sleep duration and mortality typically follow a U-shaped pattern; nonlinearity is assessed with restricted cubic splines (Figure 4).",
    if (nm == "CHARLS") "CHARLS cardiovascular death is Harmonized CHARLS End of Life ragcod = 2 (circulatory). Cancer and other coded causes are the competing event. Two deaths with a missing cause were excluded." else
      "CHARLS cardiovascular death uses Harmonized CHARLS End of Life ragcod = 2.",
    pub_competing_sparse_footnote(got$n_cvd)
  )
  .sci_xlsx_double_header_booktabs(
    path, title = "Table 4. Competing risk analysis of cardiovascular death",
    df_body = got$body, h1 = h1_fg, h2 = h2_fg, footnotes = ft
  )
  message(basename(path), " n=", got$n, " cvd=", got$n_cvd, " other=", got$n_other)
}
if (identical(Sys.getenv("PV2_TABLE4_ONLY"), "1")) quit(save = "no")

s1 <- read_pub("Table S1. Definitions.csv")
for (nm in dbs_nm) write_one(nm, "Table S1. Definitions", s1, character(0))

s2 <- read_pub("Table S2. Assessment of multicollinearity.csv")
split_write(s2, "Table S2. Assessment of multicollinearity",
            "Abbreviations: SBP, systolic blood pressure; DBP, diastolic blood pressure; BMI, body mass index; VIF, variance inflation factor.")

s4 <- read_pub("Table S4. Predictive performance for 2-year all-cause mortality.csv")
split_write(s4, "Table S4. Predictive performance for 2-year all-cause mortality",
            "Cutoff is the Youden threshold of the predicted 2-year mortality probability, not hours of sleep. NHANES AUC uses survey weights in the ROC only.")

# S6/S7/S8 已由 pv2_s6_s7_s8.R 定稿。本导出不再用缺失率、总胆固醇或 BMI 覆盖它们。
message("跳过 Table S6/S7/S8：用 pv2_s6_s7_s8.R")

old_csv <- list.files(tab_dir, pattern = "\\.csv$", full.names = TRUE)
if (length(old_csv)) {
  for (f in old_csv) file.rename(f, file.path(ckpt, basename(f)))
}
message("xlsx export done")
