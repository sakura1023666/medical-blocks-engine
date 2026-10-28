# Display / analysis names for suicide CLPM indicators.
# Ordinary words: first letter uppercase, remaining words separated by spaces.
# Fixed abbreviations stay as written (HAMD, HAMA, CSSRS, C-SSRS, CGI, EI, BMI, ECT, BZDs, MASS, ID, DIA).
# year_education is the explicit exception: "Years of education".
# Idempotent: names that are already in the target form are returned unchanged.

.suicide_indicator_acronym <- c(
  "HAMD", "HAMA", "CSSRS", "CGI", "EI", "BMI", "ECT", "BZDs",
  "MASS", "ID", "DIA", "Psy"
)

suicide_indicator_name <- function(x) {
  x <- as.character(x)
  vapply(x, .suicide_indicator_name_one, character(1L), USE.NAMES = FALSE)
}

# Exact names (old underscore form and the spaced form already on disk).
.suicide_indicator_alias <- c(
  year_education = "Years of education",
  "Years of education" = "Years of education",
  Smoke_1 = "Smoke",
  "Smoke 1" = "Smoke",
  Smoke = "Smoke",
  Alcohol_1 = "Alcohol",
  "Alcohol 1" = "Alcohol",
  Alcohol = "Alcohol",
  form = "Mode of onset",
  Form = "Mode of onset",
  "Mode of onset" = "Mode of onset",
  medicine = "Current medication",
  Medicine = "Current medication",
  "Current medication" = "Current medication",
  MASS_1 = "Forgets medication",
  "MASS 1" = "Forgets medication",
  "Forgets medication" = "Forgets medication",
  MASS_2 = "Missed doses in 2 weeks",
  "MASS 2" = "Missed doses in 2 weeks",
  "Missed doses in 2 weeks" = "Missed doses in 2 weeks",
  MASS_3 = "Reduced dose alone",
  "MASS 3" = "Reduced dose alone",
  "Reduced dose alone" = "Reduced dose alone",
  MASS_4 = "Forgets medication away",
  "MASS 4" = "Forgets medication away",
  "Forgets medication away" = "Forgets medication away",
  MASS_5 = "Took medication yesterday",
  "MASS 5" = "Took medication yesterday",
  "Took medication yesterday" = "Took medication yesterday",
  MASS_6 = "Stopped when better",
  "MASS 6" = "Stopped when better",
  "Stopped when better" = "Stopped when better",
  MASS_7 = "Hard to adhere",
  "MASS 7" = "Hard to adhere",
  "Hard to adhere" = "Hard to adhere",
  age_onset = "Age at onset",
  "Age Onset" = "Age at onset",
  "Age at onset" = "Age at onset",
  "No. Hopitalization" = "Ever hospitalized",
  "是否住院" = "Ever hospitalized",
  "Ever hospitalized" = "Ever hospitalized",
  "No. Manic Episode" = "Manic episode",
  "是否躁狂发作" = "Manic episode",
  "Manic episode" = "Manic episode",
  "HAMD Index" = "HAMD-17 total, Index",
  "HAMD-17 total, Index" = "HAMD-17 total, Index",
  "HAMA Index" = "HAMA-14 total, Index",
  "HAMA-14 total, Index" = "HAMA-14 total, Index",
  "HAMD 1st" = "HAMD-17 total, 1st",
  "HAMD-17 total, 1st" = "HAMD-17 total, 1st",
  "HAMA 1st" = "HAMA-14 total, 1st",
  "HAMA-14 total, 1st" = "HAMA-14 total, 1st",
  "CSSRS Index" = "C-SSRS ideation, Index",
  "C-SSRS ideation, Index" = "C-SSRS ideation, Index",
  "CSSRS 1st" = "C-SSRS ideation, 1st",
  "C-SSRS ideation, 1st" = "C-SSRS ideation, 1st"
)

.suicide_indicator_name_one <- function(nm) {
  if (length(nm) != 1L || is.na(nm) || !nzchar(nm)) return(nm)
  if (nm %in% names(.suicide_indicator_alias)) return(unname(.suicide_indicator_alias[[nm]]))
  if (grepl("[^\x01-\x7F]", nm, perl = TRUE)) return(nm)
  if (!grepl("_", nm, fixed = TRUE)) {
    return(.suicide_indicator_title_token(nm))
  }
  parts <- strsplit(nm, "_", fixed = TRUE)[[1L]]
  out <- character(0)
  i <- 1L
  while (i <= length(parts)) {
    tok <- parts[[i]]
    if (identical(tok, "C") && i < length(parts) && identical(parts[[i + 1L]], "SSRS")) {
      out <- c(out, "C-SSRS")
      i <- i + 2L
      next
    }
    out <- c(out, .suicide_indicator_title_token(tok))
    i <- i + 1L
  }
  paste(out, collapse = " ")
}

.suicide_indicator_title_token <- function(tok) {
  if (!nzchar(tok)) return(tok)
  if (tok %in% .suicide_indicator_acronym) return(tok)
  if (identical(tok, "1st") || grepl("^[0-9]+$", tok)) return(tok)
  if (identical(tok, "No.")) return("No.")
  # DrugNaive / Duringcourse / Moodstaberlizers: already capitalized compounds, do not restyle.
  if (grepl("[a-z]", tok) && grepl("[A-Z]", tok)) return(tok)
  paste0(toupper(substring(tok, 1L, 1L)), substring(tok, 2L))
}

# Table 1 / imputation table row order. Section headers are inserted by the table writers.
suicide_table1_sections <- function() {
  list(
    Demographics = c(
      "Age", "Sex", "Years of education", "Education", "Marriage",
      "Height", "Weight", "BMI", "Smoke", "Alcohol"
    ),
    "Clinical history" = c(
      "Family history", "First Episode", "Age at onset", "Duringcourse",
      "Mode of onset", "Attack",
      "Ever hospitalized", "Manic episode", "No. Depressive Episode",
      "住院时间"
    ),
    Treatment = c(
      "DrugNaive", "Age Medication Intake", "Current medication",
      "Antipsychotics", "Antidepressants", "Moodstaberlizers", "BZDs", "ECT",
      "Medication adherence"
    ),
    "Index assessment" = c("HAMD-17 total, Index", "HAMA-14 total, Index")
  )
}

suicide_order_table_vars <- function(vars) {
  sec <- unlist(suicide_table1_sections(), use.names = FALSE)
  vars <- unique(as.character(vars))
  c(intersect(sec, vars), setdiff(vars, sec))
}

# Level recodes that belong with the column-name pass.
# Marriage: married n is too small to stand alone; pool with in_relationship.
suicide_recode_indicator_levels <- function(df) {
  recode_one <- function(x, map, levels) {
    y <- trimws(as.character(x))
    hit <- !is.na(y) & y %in% names(map)
    y[hit] <- unname(map[y[hit]])
    factor(y, levels = levels)
  }
  if ("Marriage" %in% names(df)) {
    df[["Marriage"]] <- recode_one(df[["Marriage"]], c(
      single = "Single",
      Single = "Single",
      in_relationship = "Partnered",
      married = "Partnered",
      Partnered = "Partnered"
    ), c("Single", "Partnered"))
  }
  # Education: primary school n=1 (illiterate n=0 in the outpatient cohort).
  # Before high school = illiterate + primary + junior high.
  # High school or above = senior high + college or above.
  if ("Education" %in% names(df)) {
    df[["Education"]] <- recode_one(df[["Education"]], c(
      illiterate = "Before high school",
      primary_school = "Before high school",
      junior_high = "Before high school",
      "Before high school" = "Before high school",
      senior_high = "High school or above",
      college_or_above = "High school or above",
      "High school or above" = "High school or above"
    ), c("Before high school", "High school or above"))
  }
  onset <- intersect(c("Mode of onset", "Form", "form"), names(df))
  if (length(onset)) {
    v <- onset[[1L]]
    df[[v]] <- recode_one(df[[v]], c(
      acute_onset = "Acute onset",
      slow_onset = "Slow onset",
      "Acute onset" = "Acute onset",
      "Slow onset" = "Slow onset"
    ), c("Acute onset", "Slow onset"))
  }
  # Counts > 0 = Yes. Depressive episode count stays numeric.
  any_event <- function(x) {
    y <- trimws(as.character(x))
    num <- suppressWarnings(as.numeric(y))
    out <- rep(NA_character_, length(y))
    out[!is.na(num) & num == 0] <- "No"
    out[!is.na(num) & num > 0] <- "Yes"
    out[y %in% c("No", "Yes")] <- y[y %in% c("No", "Yes")]
    factor(out, levels = c("No", "Yes"))
  }
  bin_map <- c(
    "No. Hopitalization" = "Ever hospitalized",
    "是否住院" = "Ever hospitalized",
    "No. Manic Episode" = "Manic episode",
    "是否躁狂发作" = "Manic episode"
  )
  for (old in names(bin_map)) {
    new <- unname(bin_map[[old]])
    src <- if (old %in% names(df)) old else if (new %in% names(df)) new else NA_character_
    if (is.na(src)) next
    df[[new]] <- any_event(df[[src]])
    if (!identical(src, new)) df[[src]] <- NULL
  }
  med <- intersect(c("Current medication", "Medicine", "medicine"), names(df))
  if (length(med)) {
    v <- med[[1L]]
    df[[v]] <- recode_one(df[[v]], c(
      on_medication = "Yes",
      no_medication = "No",
      Yes = "Yes",
      No = "No"
    ), c("No", "Yes"))
  }
  df
}

# Family history 1-6 are six relative slots with the same diagnosis codes.
# Any code other than none = family history present.
# MASS items 1-7 are MMAS yes/no items (item 8 was not in the source file).
# Score 0-7, higher = better adherence. Items 1-4, 6, 7: No = 1 point.
# Item 5 (took medication yesterday): Yes = 1 point.
suicide_add_composite_indicators <- function(df) {
  fh_cols <- paste("Familyhistory", 1:6)
  fh_cols <- intersect(fh_cols, names(df))
  if (length(fh_cols)) {
    mat <- as.data.frame(df[, fh_cols, drop = FALSE], stringsAsFactors = FALSE)
    pos <- matrix(FALSE, nrow(df), length(fh_cols))
    known <- matrix(FALSE, nrow(df), length(fh_cols))
    for (j in seq_along(fh_cols)) {
      y <- trimws(as.character(mat[[j]]))
      known[, j] <- !is.na(y) & nzchar(y) & !tolower(y) %in% c("na", "null")
      pos[, j] <- known[, j] & tolower(y) != "none"
    }
    lab <- rep(NA_character_, nrow(df))
    any_pos <- rowSums(pos) > 0
    any_known <- rowSums(known) > 0
    lab[any_known & !any_pos] <- "No"
    lab[any_pos] <- "Yes"
    df[["Family history"]] <- factor(lab, levels = c("No", "Yes"))
  }
  mass_pts <- c(
    "Forgets medication" = 0,
    "Missed doses in 2 weeks" = 0,
    "Reduced dose alone" = 0,
    "Forgets medication away" = 0,
    "Took medication yesterday" = 1,
    "Stopped when better" = 0,
    "Hard to adhere" = 0
  )
  mass_cols <- intersect(names(mass_pts), names(df))
  m8_name <- intersect(c("MASS 8", "MASS_8"), names(df))
  if (length(mass_cols) == length(mass_pts) && length(m8_name)) {
    score <- rep(0, nrow(df))
    miss <- rep(FALSE, nrow(df))
    for (v in names(mass_pts)) {
      y <- tolower(trimws(as.character(df[[v]])))
      pt <- rep(NA_real_, length(y))
      yes_point <- unname(mass_pts[[v]])
      pt[y %in% c("yes", "1")] <- yes_point
      pt[y %in% c("no", "0")] <- 1 - yes_point
      miss <- miss | is.na(pt)
      pt[is.na(pt)] <- 0
      score <- score + pt
    }
    y8 <- toupper(trimws(as.character(df[[m8_name[[1L]]]])))
    pt8 <- rep(NA_real_, length(y8))
    pt8[y8 == "A"] <- 1
    pt8[y8 == "B"] <- 0.75
    pt8[y8 == "C"] <- 0.5
    pt8[y8 == "D"] <- 0.25
    pt8[y8 == "E"] <- 0
    miss <- miss | is.na(pt8)
    pt8[is.na(pt8)] <- 0
    score <- score + pt8
    score[miss] <- NA_real_
    df[["Medication adherence"]] <- score
  }
  df
}

suicide_indicator_rename_df <- function(df) {
  if (!is.data.frame(df)) stop("suicide_indicator_rename_df expects a data.frame", call. = FALSE)
  names(df) <- suicide_indicator_name(names(df))
  df <- suicide_recode_indicator_levels(df)
  df <- suicide_add_composite_indicators(df)
  if (anyDuplicated(names(df))) {
    stop("Indicator rename produced duplicate names: ",
         paste(unique(names(df)[duplicated(names(df))]), collapse = ", "),
         call. = FALSE)
  }
  df
}
