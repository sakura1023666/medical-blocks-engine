###############################################################################
#  cross_lagged_circadian_wave_epwv.R
#  按波次计算 ePWV，并用原始成分重建 circadian condition1–7
#  （预编码 condition 常把药物 NA 当成阳性，导致整列全 1）
###############################################################################

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (is.null(a)) b else a
}

circadian_num <- function(x) {
  suppressWarnings(as.numeric(as.character(x)))
}

circadian_yes1 <- function(x) {
  z <- circadian_num(x)
  !is.na(z) & z == 1
}

circadian_row_mean <- function(...) {
  m <- cbind(...)
  storage.mode(m) <- "double"
  z <- rowMeans(m, na.rm = TRUE)
  z[is.nan(z)] <- NA_real_
  z
}

#' Greer / 文献 ePWV（Age + MBP）
circadian_epwv_from_age_bp <- function(age, sbp, dbp) {
  age <- circadian_num(age)
  sbp <- circadian_num(sbp)
  dbp <- circadian_num(dbp)
  mbp <- dbp + 0.4 * (sbp - dbp)
  9.587 - 0.402 * age + 0.00456 * age^2 -
    0.00002621 * age^2 * mbp + 0.003176 * age * mbp - 0.01832
}

.circadian_pick <- function(df, cands) {
  nms <- names(df)
  hit <- cands[tolower(cands) %in% tolower(nms)]
  if (!length(hit)) return(NULL)
  nms[match(tolower(hit[[1L]]), tolower(nms))]
}

.circadian_col <- function(df, cands) {
  nm <- .circadian_pick(df, cands)
  if (is.null(nm)) return(rep(NA_real_, nrow(df)))
  df[[nm]]
}

.circadian_pick_all <- function(df, cands) {
  nms <- names(df)
  nms[tolower(nms) %in% tolower(cands)]
}

#' 用腰围/血压/血脂/血糖/睡眠/抑郁重建 7 成分（药物 NA = 未服药）
circadian_rebuild_conditions <- function(df, cohort) {
  df <- as.data.frame(df)
  male <- circadian_num(.circadian_col(df, c("rgender", "ba000_w2_3", "dhsex.x", "DhSex", "Gender"))) == 1
  waist <- circadian_num(.circadian_col(df, c("qm002", "wstval", "WSTVAL", "Waist_circumference")))
  sbp_cols <- .circadian_pick_all(df, c("qa003", "qa007", "qa011", "sysval", "SYSVAL", "SBP", "NBPS"))
  dbp_cols <- .circadian_pick_all(df, c("qa004", "qa008", "qa012", "diaval", "DIAVAL", "DBP", "NBPD"))
  sbp <- if (length(sbp_cols)) {
    do.call(circadian_row_mean, lapply(sbp_cols, function(nm) circadian_num(df[[nm]])))
  } else rep(NA_real_, nrow(df))
  dbp <- if (length(dbp_cols)) {
    do.call(circadian_row_mean, lapply(dbp_cols, function(nm) circadian_num(df[[nm]])))
  } else rep(NA_real_, nrow(df))

  tg <- circadian_num(.circadian_col(df, c("newtg", "bl_tg", "trig", "TG", "Triglycerides")))
  hdl <- circadian_num(.circadian_col(df, c("newhdl", "bl_hdl", "hdl", "HDL", "HDL_Cholesterol")))
  glu <- circadian_num(.circadian_col(df, c("newglu", "bl_glu", "fglu", "Glucose")))
  hba <- circadian_num(.circadian_col(df, c("hba1c", "HbA1c")))
  sleep <- circadian_num(.circadian_col(df, c("da049", "heslpe", "SLD01")))
  ces_nm <- .circadian_pick(df, c("CES_D10", "CES_D8"))
  ces <- if (is.null(ces_nm)) rep(NA_real_, nrow(df)) else circadian_num(df[[ces_nm]])
  if (sum(is.finite(hba)) >= 20L && stats::median(hba, na.rm = TRUE) > 20)
    hba <- hba / 10.929 + 2.152

  bpmed <- circadian_yes1(.circadian_col(df, c("da010_2_s1", "hemda", "HeMDa")))
  lipmed <- circadian_yes1(.circadian_col(df, c("da014s1", "hechmd", "HeChMd")))
  diamed <- circadian_yes1(.circadian_col(df, c("da011s1", "hedimdi")))

  asia <- grepl("CHARLS", as.character(cohort)[1L], ignore.case = TRUE)
  w_m <- if (isTRUE(asia)) 90 else 94
  w_f <- 80
  tg_cut <- if (isTRUE(asia) || stats::median(tg, na.rm = TRUE) > 20) 150 else 1.7
  hdl_m <- if (isTRUE(asia) || stats::median(hdl, na.rm = TRUE) > 5) 40 else 1.0
  hdl_f <- if (isTRUE(asia) || stats::median(hdl, na.rm = TRUE) > 5) 50 else 1.3
  glu_cut <- if (isTRUE(asia) || stats::median(glu, na.rm = TRUE) > 20) 100 else 5.6
  ces_cut <- if (!is.null(ces_nm) && grepl("10", ces_nm)) 10 else 4

  c1 <- ifelse(is.na(waist) | is.na(male), NA_integer_,
               as.integer(ifelse(male, waist >= w_m, waist >= w_f)))
  c2 <- ifelse(is.na(tg) & !lipmed, NA_integer_,
               as.integer((!is.na(tg) & tg >= tg_cut) | lipmed))
  c3 <- ifelse(is.na(hdl) & !lipmed, NA_integer_,
               as.integer((!is.na(hdl) & ifelse(male, hdl < hdl_m, hdl < hdl_f)) | lipmed))
  c4 <- ifelse(is.na(sbp) & is.na(dbp) & !bpmed, NA_integer_,
               as.integer((!is.na(sbp) & sbp >= 130) | (!is.na(dbp) & dbp >= 85) | bpmed))
  c5 <- ifelse(is.na(glu) & is.na(hba) & !diamed, NA_integer_,
               as.integer((!is.na(glu) & glu >= glu_cut) |
                            (!is.na(hba) & hba >= 6) | diamed))
  c6 <- ifelse(is.na(sleep), NA_integer_, as.integer(sleep < 6))
  c7 <- ifelse(is.na(ces), NA_integer_, as.integer(ces >= ces_cut))

  df$condition1 <- c1
  df$condition2 <- c2
  df$condition3 <- c3
  df$condition4 <- c4
  df$condition5 <- c5
  df$condition6 <- c6
  df$condition7 <- c7
  df$SBP <- sbp
  df$DBP <- dbp
  df
}

#' 从该波 D01/基线表读 Age（CHARLS ID 补 0）
circadian_load_age_map <- function(path, cohort) {
  if (is.null(path) || !nzchar(as.character(path)[1L]) || !file.exists(path))
    return(NULL)
  e <- new.env(parent = emptyenv())
  load(path, envir = e)
  d <- as.data.frame(e[[ls(e)[1L]]], stringsAsFactors = FALSE)
  idc <- names(d)[tolower(names(d)) %in% c("id", "idauniq", "seqn")][1L]
  if (is.na(idc) || !"Age" %in% names(d)) return(NULL)
  ids <- as.character(d[[idc]])
  if (grepl("CHARLS", as.character(cohort)[1L], ignore.case = TRUE)) {
    ids <- ifelse(
      nchar(ids) == 11L, paste0(substr(ids, 1, 9), "0", substr(ids, 10, 11)),
      ifelse(nchar(ids) == 10L, paste0(substr(ids, 1, 8), "0", substr(ids, 9, 10)), ids)
    )
  }
  mp <- stats::setNames(circadian_num(d$Age), ids)
  mp[!is.na(names(mp)) & !duplicated(names(mp))]
}

#' 给单波 circadian 表：重建 7 成分 + 按该波 Age/血压算 ePWV
#'
#' @param age_map named numeric，该波年龄（不要再加间隔年）
#' @param age_offset 仅当 age_map 是基线年龄时传入（随访年-基线年）
circadian_wave_enrich <- function(df, cohort, year, baseline_year, age_map,
                                  rebuild_conditions = TRUE, age_offset = 0) {
  df <- as.data.frame(df)
  if (isTRUE(rebuild_conditions)) {
    df <- circadian_rebuild_conditions(df, cohort)
  } else {
    sbp_cols <- .circadian_pick_all(df, c("qa003", "qa007", "qa011", "sysval", "SYSVAL", "SBP", "NBPS"))
    dbp_cols <- .circadian_pick_all(df, c("qa004", "qa008", "qa012", "diaval", "DIAVAL", "DBP", "NBPD"))
    if (length(sbp_cols))
      df$SBP <- do.call(circadian_row_mean, lapply(sbp_cols, function(nm) circadian_num(df[[nm]])))
    if (length(dbp_cols))
      df$DBP <- do.call(circadian_row_mean, lapply(dbp_cols, function(nm) circadian_num(df[[nm]])))
  }
  ids <- as.character(df$ID)
  age0 <- if (is.null(age_map) || !length(age_map)) {
    rep(NA_real_, length(ids))
  } else {
    unname(age_map[ids])
  }
  off <- suppressWarnings(as.numeric(age_offset)[1L])
  if (!is.finite(off)) off <- 0
  age_w <- age0 + off
  df$Age_wave <- age_w
  df$ePWV <- circadian_epwv_from_age_bp(age_w, df$SBP, df$DBP)
  df
}
