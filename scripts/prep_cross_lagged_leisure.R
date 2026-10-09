#!/usr/bin/env Rscript
# scripts/prep_cross_lagged_leisure.R
# Leisure_score × circadian DN: harmonize CHARLS / ELSA dabiao + D03 + wave CSV
#
# CHARLS ID：基线 D01 倒数第二位常为多余 0，匹配前 strip 该位 0 再与昼夜/休闲 CSV 对齐
# Usage:
#   Rscript scripts/prep_cross_lagged_leisure.R
#   Rscript scripts/prep_cross_lagged_leisure.R --study-root "/path/to/cross_laged_shehui"

suppressPackageStartupMessages({
  if (requireNamespace("dplyr", quietly = TRUE)) library(dplyr)
})

args <- commandArgs(trailingOnly = TRUE)
study_root <- "/mnt/g/02block_result/23_circadian rhythm/cross_laged_shehui"
if ("--study-root" %in% args) {
  i <- match("--study-root", args)
  study_root <- args[[i + 1L]]
}
if (!dir.exists(study_root)) {
  study_root <- "G:/02block_result/23_circadian rhythm/cross_laged_shehui"
}
raw <- file.path(study_root, "data")
out <- file.path(raw, "harmonized")
wave_dir <- file.path(out, "waves")
frailty_out <- file.path(out, "frailty")
dir.create(wave_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(frailty_out, recursive = TRUE, showWarnings = FALSE)

to_id <- function(x) as.character(as.vector(x))

#' CHARLS 基线 ID：若倒数第二位为 0 则删掉（与昼夜/休闲 CSV 对齐）
charls_strip_baseline_id <- function(x) {
  x <- to_id(x)
  vapply(x, function(s) {
    n <- nchar(s)
    if (n >= 2L && substr(s, n - 1L, n - 1L) == "0") {
      paste0(substr(s, 1L, n - 2L), substr(s, n, n))
    } else {
      s
    }
  }, character(1L), USE.NAMES = FALSE)
}

pad_charls_id <- function(x) {
  x <- to_id(trimws(x))
  ifelse(
    nchar(x) == 11L, paste0(substr(x, 1, 9), "0", substr(x, 10, 11)),
    ifelse(nchar(x) == 10L, paste0(substr(x, 1, 8), "0", substr(x, 9, 10)), x)
  )
}

recode_dn <- function(x) {
  ifelse(
    is.na(x), NA_character_,
    ifelse(
      as.character(x) %in% c("1"), "Circadian_Disorder",
      ifelse(as.character(x) %in% c("0"), "No_Disorder", NA_character_)
    )
  )
}

map_bp <- function(df) {
  if (!"SBP" %in% names(df) && "NBPS" %in% names(df)) df$SBP <- df$NBPS
  if (!"DBP" %in% names(df) && "NBPD" %in% names(df)) df$DBP <- df$NBPD
  df
}

load_df <- function(path, obj = NULL) {
  e <- new.env(parent = emptyenv())
  load(path, envir = e)
  if (is.null(obj)) {
    nms <- ls(e)
    if (length(nms) != 1L) {
      stop("期望单对象: ", path, " 有 ", paste(nms, collapse = ","))
    }
    obj <- nms[[1L]]
  }
  as.data.frame(e[[obj]])
}

circ_keep_cols <- c(
  "ID", paste0("condition", 1:7), "met_count", "DN"
)

leisure_charls_cols <- c("s1", "s2", "s4", "s5", "s6", "s8", "total_score")
leisure_elsa_cols <- c(
  "scorg01", "scorg02", "scorg03", "scorg04", "scorg05", "scorg06", "scorg07", "scorg08",
  "scacta", "scactb", "scactc", "scactd", "total_score"
)

prep_frailty_fi <- function(path, id_col = "ID") {
  fr <- utils::read.csv(path, check.names = FALSE)
  if (!id_col %in% names(fr)) {
    stop("虚弱文件缺少 ID 列: ", id_col, " in ", path)
  }
  fr$ID <- to_id(fr[[id_col]])
  if (!"FI" %in% names(fr)) stop("虚弱文件缺少 FI 列: ", path)
  fr[, c("ID", "FI"), drop = FALSE]
}

overlap_row <- function(cohort, strategy, left_ids, right_ids) {
  left_ids <- unique(to_id(left_ids))
  right_ids <- unique(to_id(right_ids))
  n_ov <- length(intersect(left_ids, right_ids))
  data.frame(
    cohort = cohort,
    strategy = strategy,
    n_left = length(left_ids),
    n_right = length(right_ids),
    n_overlap = n_ov,
    overlap_rate_vs_left = if (length(left_ids)) n_ov / length(left_ids) else NA_real_,
    stringsAsFactors = FALSE
  )
}

assert_analytic <- function(cohort, n, min_n = 3000L) {
  if (n < min_n) {
    stop(cohort, ": analytic n=", n, " < ", min_n, call. = FALSE)
  }
}

qc_row <- function(cohort, dabiao, circ_n, circ_merge_rate, fi_merge_rate, note = "") {
  data.frame(
    cohort = cohort,
    n = nrow(dabiao),
    n_event = sum(dabiao$Disease_Group == "Circadian_Disorder", na.rm = TRUE),
    circ_merge_rate = circ_merge_rate,
    fi_merge_rate = fi_merge_rate,
    leisure_non_na_rate = mean(!is.na(dabiao$Leisure_score)),
    note = note,
    stringsAsFactors = FALSE
  )
}

read_circ_charls <- function(path) {
  cc <- utils::read.csv(path, check.names = FALSE)
  cc$ID <- to_id(cc$ID)
  cc[, intersect(c(circ_keep_cols, names(cc)), names(cc)), drop = FALSE]
  cc <- cc[, unique(c("ID", intersect(circ_keep_cols, names(cc))), drop = FALSE)]
  cc[!duplicated(cc$ID), , drop = FALSE]
}

read_circ_elsa <- function(path) {
  cc <- utils::read.csv(path, check.names = FALSE)
  if (!"idauniq" %in% names(cc)) stop("ELSA circ 缺少 idauniq: ", path)
  cc$ID <- to_id(cc$idauniq)
  cc <- cc[, unique(c("ID", intersect(circ_keep_cols, names(cc)))), drop = FALSE]
  cc[!duplicated(cc$ID), , drop = FALSE]
}

read_leisure_charls <- function(path) {
  le <- utils::read.csv(path, check.names = FALSE)
  le$ID <- to_id(le$ID)
  keep <- intersect(c("ID", leisure_charls_cols), names(le))
  le <- le[, keep, drop = FALSE]
  if ("total_score" %in% names(le)) le$Leisure_score <- as.numeric(le$total_score)
  le[!duplicated(le$ID), , drop = FALSE]
}

read_leisure_elsa <- function(path) {
  le <- utils::read.csv(path, check.names = FALSE)
  if (!"idauniq" %in% names(le)) stop("ELSA leisure 缺少 idauniq: ", path)
  le$ID <- to_id(le$idauniq)
  keep <- intersect(c("ID", leisure_elsa_cols), names(le))
  le <- le[, keep, drop = FALSE]
  if ("total_score" %in% names(le)) le$Leisure_score <- as.numeric(le$total_score)
  le[!duplicated(le$ID), , drop = FALSE]
}

write_d03 <- function(df_ids, out_path) {
  d03 <- data.frame(
    ID = df_ids$ID,
    Disease_Group = recode_dn(df_ids$DN),
    stringsAsFactors = FALSE
  )
  dabiao <- d03
  save(dabiao, file = out_path)
}

write_wave_csv <- function(wave_df, out_path) {
  utils::write.csv(wave_df, out_path, row.names = FALSE)
}

write_frailty_harmonized <- function(src, dst, cohort = c("CHARLS", "ELSA")) {
  cohort <- match.arg(cohort)
  fr <- utils::read.csv(src, check.names = FALSE)
  id_col <- if (cohort == "CHARLS") "ID" else "idauniq"
  if (!id_col %in% names(fr)) stop("虚弱文件无 ID: ", src, call. = FALSE)
  fr$ID <- to_id(fr[[id_col]])
  if (cohort == "CHARLS") fr$ID <- charls_strip_baseline_id(fr$ID)
  utils::write.csv(fr, dst, row.names = FALSE)
  invisible(dst)
}

id_align_rows <- list()

# ── CHARLS baseline 2011 ─────────────────────────────────────────────────────
bl_charls_path <- file.path(raw, "charls/D01_baseline_CHARLS_2011_0813.RData")
circ_charls_2011 <- file.path(raw, "charls/昼夜节律CHARLS_2011.csv")
leisure_charls_2011 <- file.path(raw, "charls/休闲活动_charls_2011.csv")
fr_charls_2011 <- file.path(raw, "frailty/虚弱_charls_2011.csv")

bl <- load_df(bl_charls_path, "baseline")
bl$ID_raw <- to_id(bl$ID)
bl$ID <- charls_strip_baseline_id(bl$ID_raw)

circ <- read_circ_charls(circ_charls_2011)
circ_n_charls <- nrow(circ)
le <- read_leisure_charls(leisure_charls_2011)
fr <- prep_frailty_fi(fr_charls_2011, "ID")
fr$ID <- charls_strip_baseline_id(fr$ID)

id_align_rows[[length(id_align_rows) + 1L]] <- overlap_row(
  "CHARLS", "bl_strip_vs_circ", bl$ID, circ$ID
)
id_align_rows[[length(id_align_rows) + 1L]] <- overlap_row(
  "CHARLS", "bl_strip_vs_leisure", bl$ID, le$ID
)
id_align_rows[[length(id_align_rows) + 1L]] <- overlap_row(
  "CHARLS", "bl_raw_vs_circ", bl$ID_raw, circ$ID
)

dabiao_charls <- bl %>%
  inner_join(circ, by = "ID") %>%
  inner_join(le, by = "ID") %>%
  left_join(fr, by = "ID")
dabiao_charls$Disease_Group <- recode_dn(dabiao_charls$DN)
dabiao_charls$Frailty <- ifelse(
  !is.na(dabiao_charls$FI), as.integer(dabiao_charls$FI >= 0.25), NA_integer_
)
dabiao_charls <- map_bp(dabiao_charls)

circ_merge_charls <- nrow(dabiao_charls) / circ_n_charls
fi_merge_charls <- mean(!is.na(dabiao_charls$FI))
leisure_merge_charls <- 1
assert_analytic("CHARLS", nrow(dabiao_charls))
if (any(is.na(dabiao_charls$Leisure_score))) {
  stop("CHARLS: inner join 后仍有 Leisure_score 缺失", call. = FALSE)
}
note_charls <- paste0(
  "id=strip_baseline_zero; leisure_inner_join; n=", nrow(dabiao_charls)
)
if (fi_merge_charls < 0.70) {
  note_charls <- paste(note_charls, paste0("FI_MERGE_WARN=", round(fi_merge_charls, 4)), sep = ";")
}

dabiao <- dabiao_charls
save(dabiao, file = file.path(out, "D04_CHARLS_leisure_baseline.RData"))

# CHARLS wave 2011 merged
wave11 <- circ %>%
  left_join(le, by = "ID")
write_wave_csv(wave11, file.path(wave_dir, "CHARLS_2011_wave.csv"))
write_d03(circ, file.path(out, "D03_CHARLS_2011_DN.RData"))

# CHARLS 2015
circ15 <- read_circ_charls(file.path(raw, "charls/昼夜节律CHARLS_2015.csv"))
le15 <- read_leisure_charls(file.path(raw, "charls/休闲活动_charls_2015.csv"))
wave15 <- circ15 %>% left_join(le15, by = "ID")
write_wave_csv(wave15, file.path(wave_dir, "CHARLS_2015_wave.csv"))
write_d03(circ15, file.path(out, "D03_CHARLS_2015_DN.RData"))

# ── ELSA wave4 baseline ──────────────────────────────────────────────────────
bl_elsa_path <- file.path(raw, "elsa/D01_baseline_ELSA4_2008_0813.RData")
circ_elsa_path <- file.path(raw, "elsa/昼夜节律ELSA_wave4.csv")
leisure_elsa_path <- file.path(raw, "elsa/休闲活动_elsa_wave4.csv")
fr_elsa_path <- file.path(raw, "frailty/虚弱_elsa_wave4.csv")

bl <- load_df(bl_elsa_path, "baseline")
bl$ID <- to_id(bl$ID)

circ <- read_circ_elsa(circ_elsa_path)
circ_n_elsa <- nrow(circ)
le <- read_leisure_elsa(leisure_elsa_path)
fr <- prep_frailty_fi(fr_elsa_path, "idauniq")

id_align_rows[[length(id_align_rows) + 1L]] <- overlap_row("ELSA", "circ_vs_bl", circ$ID, bl$ID)
id_align_rows[[length(id_align_rows) + 1L]] <- overlap_row("ELSA", "leisure_vs_bl", le$ID, bl$ID)

dabiao_elsa <- bl %>%
  inner_join(circ, by = "ID") %>%
  inner_join(le, by = "ID") %>%
  left_join(fr, by = "ID")
dabiao_elsa$Disease_Group <- recode_dn(dabiao_elsa$DN)
dabiao_elsa$Frailty <- ifelse(
  !is.na(dabiao_elsa$FI), as.integer(dabiao_elsa$FI >= 0.25), NA_integer_
)
dabiao_elsa <- map_bp(dabiao_elsa)

circ_merge_elsa <- nrow(dabiao_elsa) / circ_n_elsa
fi_merge_elsa <- mean(!is.na(dabiao_elsa$FI))
leisure_merge_elsa <- 1
assert_analytic("ELSA", nrow(dabiao_elsa))
if (any(is.na(dabiao_elsa$Leisure_score))) {
  stop("ELSA: inner join 后仍有 Leisure_score 缺失", call. = FALSE)
}
note_elsa <- paste0("leisure_inner_join; n=", nrow(dabiao_elsa))
if (fi_merge_elsa < 0.70) {
  note_elsa <- paste(note_elsa, paste0("FI_MERGE_WARN=", round(fi_merge_elsa, 4)), sep = ";")
}

dabiao <- dabiao_elsa
save(dabiao, file = file.path(out, "D04_ELSA_leisure_baseline.RData"))

wave4 <- circ %>% left_join(le, by = "ID")
write_wave_csv(wave4, file.path(wave_dir, "ELSA_wave4_wave.csv"))
write_d03(circ, file.path(out, "D03_ELSA_wave4_DN.RData"))

circ6 <- read_circ_elsa(file.path(raw, "elsa/昼夜节律ELSA_wave6.csv"))
le6 <- read_leisure_elsa(file.path(raw, "elsa/休闲活动_elsa_wave6.csv"))
wave6 <- circ6 %>% left_join(le6, by = "ID")
write_wave_csv(wave6, file.path(wave_dir, "ELSA_wave6_wave.csv"))
write_d03(circ6, file.path(out, "D03_ELSA_wave6_DN.RData"))

# ── 虚弱 CSV（CHARLS ID strip，供 long_prepare 纵向合并）────────────────────
write_frailty_harmonized(
  file.path(raw, "frailty/虚弱_charls_2011.csv"),
  file.path(frailty_out, "虚弱_charls_2011.csv"), "CHARLS"
)
write_frailty_harmonized(
  file.path(raw, "frailty/虚弱_charls_2015.csv"),
  file.path(frailty_out, "虚弱_charls_2015.csv"), "CHARLS"
)
write_frailty_harmonized(
  file.path(raw, "frailty/虚弱_elsa_wave4.csv"),
  file.path(frailty_out, "虚弱_elsa_wave4.csv"), "ELSA"
)
write_frailty_harmonized(
  file.path(raw, "frailty/虚弱_elsa_wave6.csv"),
  file.path(frailty_out, "虚弱_elsa_wave6.csv"), "ELSA"
)

# ── QC ───────────────────────────────────────────────────────────────────────
qc <- rbind(
  qc_row("CHARLS", dabiao_charls, circ_n_charls, circ_merge_charls, fi_merge_charls, note_charls),
  qc_row("ELSA", dabiao_elsa, circ_n_elsa, circ_merge_elsa, fi_merge_elsa, note_elsa)
)
utils::write.csv(qc, file.path(out, "prep_qc.csv"), row.names = FALSE)

id_align_report <- do.call(rbind, id_align_rows)
utils::write.csv(id_align_report, file.path(out, "id_align_report.csv"), row.names = FALSE)

message("Wrote harmonized leisure dabiao + D03 + waves to ", out)
print(qc)
print(id_align_report)
message(
  "CHARLS n=", nrow(dabiao_charls),
  " events=", sum(dabiao_charls$Disease_Group == "Circadian_Disorder", na.rm = TRUE),
  " leisure_non_na=", sum(!is.na(dabiao_charls$Leisure_score))
)
