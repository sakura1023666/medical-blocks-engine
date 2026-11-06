#!/usr/bin/env Rscript
# 卒中 ANLR：备选结局筛选（不覆盖 28d summary_results）
# A) MIMIC 真随访：90d / 365d 全因（is_dead + hosp_survival_day；无死亡记录行政删失至 landmark）
# B) 双库可比：院内全因死亡，窗口 28 / 90 / 365
#    规则：event = hospital-dead & los<=L；time = min(los, L)；Alive 提前出院 → 出院日删失

suppressPackageStartupMessages({
  library(data.table)
  library(survival)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.engine <- if (dir.exists("/mnt/e/01block/01Block-new-Final")) {
  "/mnt/e/01block/01Block-new-Final"
} else "E:/01block/01Block-new-Final"
setwd(.engine)

.proj <- {
  cands <- c(
    "/mnt/g/02block_result/11_ischemic stroke/prognosis_v2_41904528",
    "G:/02block_result/11_ischemic stroke/prognosis_v2_41904528"
  )
  cands[dir.exists(cands)][1L]
}
.data <- file.path(.proj, "data")
.out <- file.path(.proj, "outcome_screen")
dir.create(.out, recursive = TRUE, showWarnings = FALSE)

num <- function(x) suppressWarnings(as.numeric(x))
fmt_p <- function(p) {
  if (!is.finite(p)) return("NA")
  if (p < 0.001) "<0.001" else sprintf("%.3f", p)
}
hr_ci <- function(hr, lo, hi) {
  if (!all(is.finite(c(hr, lo, hi)))) return("NE")
  sprintf("%.3f (%.3f-%.3f)", hr, lo, hi)
}

load_d02 <- function(db) {
  e <- new.env(parent = emptyenv())
  load(file.path(.data, db, "D02_rt_Stroke_surv28.RData"), envir = e)
  as.data.table(e$rt)
}

prep_anlr <- function(db_folder, db_label) {
  d <- load_d02(db_folder)
  d[, Age := num(Age)]
  d[, Gender := ifelse(as.character(Gender) %in% c("Male", "M", "1"), "Male",
                       ifelse(as.character(Gender) %in% c("Female", "F", "2"), "Female", NA_character_))]
  d[, Neutrophil_Count := num(NeutrophilCount)]
  d[, Lymphocytes := num(Lymphocytes)]
  d[, Albumin := num(Albumin)]
  d[, ANLR := Albumin / (Neutrophil_Count / Lymphocytes)]
  d[, subject_id := as.character(subject_id %||% ID)]
  d[, ID := as.character(ID %||% subject_id)]
  d <- d[is.finite(Age) & Age >= 18 & is.finite(ANLR) & ANLR > 0]
  d[, database := db_label]
  d
}

fit_block <- function(dd, label, db, note = "") {
  dd <- dd[is.finite(futime) & futime > 0 & !is.na(fustatus)]
  n <- nrow(dd)
  ne <- sum(dd$fustatus == 1L)
  if (n < 40L || ne < 5L) {
    return(data.table(
      database = db, outcome = label, n = n, events = ne,
      event_pct = round(100 * ne / max(n, 1), 1),
      model = NA_character_, contrast = NA_character_,
      HR_CI = "NE", P = "NE", note = paste(note, "too few events")
    ))
  }
  dd[, ANLR_z := as.numeric(scale(ANLR))]
  qs <- unique(as.numeric(quantile(dd$ANLR, probs = c(0, 0.25, 0.5, 0.75, 1), na.rm = TRUE)))
  if (length(qs) >= 5L) {
    dd[, ANLR_Group := cut(ANLR, breaks = qs, include.lowest = TRUE,
                           labels = c("Q1", "Q2", "Q3", "Q4"))]
  } else {
    dd[, ANLR_Group := factor("Q1")]
  }
  .one <- function(form, model, contrast) {
    fit <- tryCatch(coxph(form, data = dd), error = function(e) NULL)
    if (is.null(fit)) {
      return(data.table(
        database = db, outcome = label, n = n, events = ne,
        event_pct = round(100 * ne / n, 1), model = model, contrast = contrast,
        HR_CI = "NE", P = "NE", note = paste(note, "cox failed")
      ))
    }
    s <- summary(fit)
    ci <- s$conf.int
    i <- nrow(ci)
    pv <- tryCatch(s$coefficients[i, "Pr(>|z|)"], error = function(e) NA_real_)
    data.table(
      database = db, outcome = label, n = n, events = ne,
      event_pct = round(100 * ne / n, 1), model = model, contrast = contrast,
      HR_CI = hr_ci(ci[i, 1], ci[i, 3], ci[i, 4]),
      P = fmt_p(pv), note = note
    )
  }
  rows <- list(
    .one(Surv(futime, fustatus) ~ ANLR_z, "crude", "per 1 SD"),
    .one(Surv(futime, fustatus) ~ ANLR_z + Age + Gender, "Age+Sex", "per 1 SD")
  )
  if ("Q4" %in% levels(dd$ANLR_Group) && sum(dd$ANLR_Group == "Q4", na.rm = TRUE) > 5) {
    rows <- c(rows, list(
      .one(Surv(futime, fustatus) ~ ANLR_Group, "crude", "Q4 vs Q1"),
      .one(Surv(futime, fustatus) ~ ANLR_Group + Age + Gender, "Age+Sex", "Q4 vs Q1")
    ))
  }
  rbindlist(rows, fill = TRUE)
}

# ---------- MIMIC ----------
message("==== MIMIC ====")
mm <- prep_anlr("mimic", "MIMIC")
hm <- fread(
  file.path(.data, "mimic", "mimic预后数据-all.csv"),
  select = c("subject_id", "is_dead", "hosp_survival_day", "is_hosp_dead", "hosp_day")
)
hm[, subject_id := as.character(subject_id)]
mm <- merge(mm, hm, by = "subject_id", all.x = TRUE)

res <- list()

# 真随访 landmark（与 D02 28d 对齐过）
make_fu <- function(is_dead, surv_day, L) {
  t <- rep(NA_real_, length(is_dead))
  ev <- rep(NA_integer_, length(is_dead))
  dead_ok <- !is.na(is_dead) & is_dead == 1L & is.finite(surv_day) & surv_day > 0
  t[dead_ok] <- pmin(surv_day[dead_ok], L)
  ev[dead_ok] <- as.integer(surv_day[dead_ok] <= L)
  alive <- is.na(is_dead)
  t[alive] <- as.numeric(L)
  ev[alive] <- 0L
  list(time = t, event = ev)
}

for (L in c(28L, 90L, 365L)) {
  lab <- sprintf("%dd all-cause mortality (post-discharge FU)", L)
  note <- "MIMIC is_dead+hosp_survival_day; no-death → admin censor at L"
  lk <- make_fu(mm$is_dead, mm$hosp_survival_day, L)
  dd <- copy(mm)
  dd[, futime := lk$time]
  dd[, fustatus := lk$event]
  # 28d 用 D02 字段作主对照更干净
  if (L == 28L) {
    dd[, futime := num(survival_time_28d)]
    dd[, fustatus := as.integer(Mortality_28d)]
    lab <- "28d all-cause mortality (D02 / primary ref)"
    note <- "D02 Mortality_28d + survival_time_28d"
  }
  res[[length(res) + 1L]] <- fit_block(dd, lab, "MIMIC", note)
  message(lab, " n=", sum(is.finite(dd$futime) & !is.na(dd$fustatus)),
          " ev=", sum(dd$fustatus == 1L, na.rm = TRUE))
}

# 院内窗口
for (L in c(28L, 90L, 365L)) {
  lab <- sprintf("In-hospital death within %dd", L)
  note <- "MIMIC is_hosp_dead + hosp_day; Alive early discharge censored at LOS"
  dd <- copy(mm)
  dd[, futime := pmin(pmax(num(hosp_day), 0.01), L)]
  dd[, fustatus := as.integer(is_hosp_dead == 1L & num(hosp_day) <= L)]
  # 院内死亡但 LOS>L → 在 L 处记存活（与 eICU 规则一致）
  dd[is_hosp_dead == 1L & num(hosp_day) > L, fustatus := 0L]
  dd[is_hosp_dead == 0L, fustatus := 0L]
  res[[length(res) + 1L]] <- fit_block(dd, lab, "MIMIC", note)
  message(lab, " n=", sum(is.finite(dd$futime) & !is.na(dd$fustatus)),
          " ev=", sum(dd$fustatus == 1L, na.rm = TRUE))
}

# ---------- eICU ----------
message("==== eICU ====")
ee <- prep_anlr("eicu", "eICU")
he <- fread(
  file.path(.data, "eicu", "EICU预后数据-all.csv"),
  select = c("patientunitstayid", "hospdischargestatus", "hosplosday")
)
he[, ID := as.character(patientunitstayid)]
ee <- merge(ee, he, by = "ID", all.x = TRUE)
ee[, hosp_dead := as.integer(tolower(as.character(hospdischargestatus)) == "expired")]
ee[, hosp_los := num(hosplosday)]

# D02 28d 对照
dd <- copy(ee)
dd[, futime := num(survival_time_28d)]
dd[, fustatus := as.integer(Mortality_28d)]
res[[length(res) + 1L]] <- fit_block(
  dd, "28d (D02; = in-hosp death ≤28d)", "eICU",
  "D02 identical to Expired & hosplos≤28"
)
message("eICU D02 28d ev=", sum(dd$fustatus == 1L, na.rm = TRUE))

for (L in c(28L, 90L, 365L)) {
  lab <- sprintf("In-hospital death within %dd", L)
  note <- "eICU Expired + hosplosday; Alive early discharge censored at LOS (no post-discharge FU)"
  dd <- copy(ee)
  dd[, futime := pmin(pmax(hosp_los, 0.01), L)]
  dd[, fustatus := as.integer(hosp_dead == 1L & hosp_los <= L)]
  dd[hosp_dead == 1L & hosp_los > L, fustatus := 0L]
  dd[hosp_dead == 0L, fustatus := 0L]
  res[[length(res) + 1L]] <- fit_block(dd, lab, "eICU", note)
  message(lab, " n=", sum(is.finite(dd$futime) & !is.na(dd$fustatus)),
          " ev=", sum(dd$fustatus == 1L, na.rm = TRUE))
}

tab <- rbindlist(res, fill = TRUE)
fwrite(tab, file.path(.out, "ANLR_alt_outcome_screen.csv"))

# 紧凑：Age+Sex + Q4vsQ1 / per1SD 各一行优先 Age+Sex Q4
compact <- tab[model == "Age+Sex"]
fwrite(compact, file.path(.out, "ANLR_alt_outcome_screen_AgeSex.csv"))

# 事件数对照表
ev_sum <- unique(tab[, .(database, outcome, n, events, event_pct, note)])
fwrite(ev_sum, file.path(.out, "ANLR_alt_outcome_N_events.csv"))

writeLines(c(
  "# Stroke ANLR alternate outcome screen",
  "",
  "## What was run",
  "1. MIMIC post-discharge FU: 28d (D02) / 90d / 365d all-cause",
  "2. Dual comparable: in-hospital death within 28 / 90 / 365 days",
  "   - MIMIC: is_hosp_dead + hosp_day",
  "   - eICU: hospdischargestatus==Expired + hosplosday",
  "3. eICU D02 28d confirmed identical to in-hosp ≤28d",
  "",
  "## Not overwritten",
  "summary_results/ remains the 28d primary delivery.",
  "",
  paste0("Output dir: ", .out)
), file.path(.out, "README_alt_outcomes.md"))

message("==== DONE ====")
print(compact[, .(database, outcome, n, events, event_pct, contrast, HR_CI, P)])
message("CSV -> ", .out)
