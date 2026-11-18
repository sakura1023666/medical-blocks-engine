###############################################################################
#  sleep_dyslipid_cohort — 预后 2.0 三库纳排（血脂异常 + 睡眠 + 死亡时间）
#
#  register_block: "sleep_dyslipid_cohort"
#  典型流水线: 预后 2.0 第一步（不替换旧 survival dual-batch）
#
#  config$prognosis_v2 = list(
#    database = "SHHS",          # NHANES / CHARLS / SHHS，batch worker 按 unit 覆盖
#    data_root = "G:/.../data",
#    short_lt = 7, long_ge = 9,
#    shhs_death_code = 0         # 本库核对：CVD 死亡只出现在 vital==0
#  )
#
#  读: 各库原始表
#  写: ctx$data$cleaned；Tables/Cohort_attrition.csv；若缺睡眠或死亡则
#      prognosis_v2_ready=FALSE，并写 Cohort_gap.txt（后续块跳过建模）
###############################################################################

.sd_load_common <- function() {
  if (exists(".sd_cfg", mode = "function", inherits = TRUE)) return(invisible(TRUE))
  cands <- c(
    file.path(getwd(), "Blocks/79_sleep_dyslipid_prognosis_full/00_sleep_dyslipid_common.R")
  )
  if (exists("pipeline_engine_root", mode = "function")) {
    cands <- c(file.path(pipeline_engine_root(getwd()),
                         "Blocks/79_sleep_dyslipid_prognosis_full/00_sleep_dyslipid_common.R"), cands)
  }
  hit <- cands[file.exists(cands)]
  if (!length(hit)) stop("找不到 00_sleep_dyslipid_common.R", call. = FALSE)
  source(hit[[1L]], local = FALSE)
  invisible(TRUE)
}

.sd_load_nhanes <- function(root) {
  bl_path <- file.path(root, "NHANES", "D01_baseline_NHANES_0920.RData")
  sl_path <- file.path(root, "NHANES", "最终数据", "血脂异常-排除心血管疾病.csv")
  if (!file.exists(bl_path) || !file.exists(sl_path)) {
    stop("NHANES 基线或血脂异常表不存在", call. = FALSE)
  }
  e <- new.env()
  load(bl_path, envir = e)
  base <- e$baseline
  sl <- utils::read.csv(sl_path, stringsAsFactors = FALSE)
  base$ID <- as.character(base$ID)
  sl$ID <- as.character(sl$SEQN)
  m <- merge(base, sl[, c("ID", "SLD01", "DN", "LBDLDL_calc")], by = "ID", all = FALSE)
  m <- m[!is.na(m$DN) & m$DN == 1, , drop = FALSE]
  m$Sleep_hours <- .sd_num(m$SLD01)
  m$database <- "NHANES"
  m$survey_weight <- .sd_num(m$WTMEC2YR)
  m$survey_psu <- m$SDMVPSU
  m$survey_strata <- m$SDMVSTRA
  m$TG <- .sd_num(m$TG); m$TC <- .sd_num(m$TC)
  m$HDL <- .sd_num(m$HDL); m$LDL <- .sd_num(m$LDL)
  m$futime_years <- NA_real_
  m$fustatus <- NA_integer_
  m$cvd_status <- NA_integer_
  list(data = m, gap = "NHANES 基线已并入睡眠与血脂异常（DN=1），目录内没有 NDI 死亡链，不能算随访时间。")
}

.sd_load_charls <- function(root, cfg) {
  bl_path <- file.path(root, "CHARLS", "D01_baseline_2011_matched2013.RData")
  dth_path <- file.path(root, "CHARLS", "merged_baseline_death.csv")
  if (!file.exists(bl_path)) stop("CHARLS 2011 匹配表不存在", call. = FALSE)
  e <- new.env()
  load(bl_path, envir = e)
  base <- e$baseline
  base$ID <- as.character(base$ID)
  hyper <- trimws(as.character(base$Hyperlipidemia))
  base <- base[hyper %in% c("Yes", "1", "Y"), , drop = FALSE]
  if (file.exists(dth_path)) {
    dth <- utils::read.csv(dth_path, stringsAsFactors = FALSE)
    dth$ID <- as.character(dth$ID)
    keep <- intersect(c("ID", "death_status"), names(dth))
    base <- merge(base, dth[, keep, drop = FALSE], by = "ID", all.x = TRUE)
  }
  base$Sleep_hours <- NA_real_
  sleep_path <- cfg$charls_sleep_path %||% ""
  if (nzchar(sleep_path) && file.exists(sleep_path)) {
    sl <- utils::read.csv(sleep_path, stringsAsFactors = FALSE)
    idn <- intersect(c("ID", "id"), names(sl))[1]
    hn <- cfg$charls_sleep_col %||% "Sleep_hours"
    sl$ID <- as.character(sl[[idn]])
    base <- merge(base, sl[, c("ID", hn)], by = "ID", all.x = TRUE)
    base$Sleep_hours <- .sd_num(base[[hn]])
  }
  base$database <- "CHARLS"
  base$TG <- .sd_num(base$TG); base$TC <- .sd_num(base$TC)
  base$HDL <- .sd_num(base$HDL); base$LDL <- .sd_num(base$LDL)
  base$survey_weight <- NA_real_
  base$survey_psu <- NA
  base$survey_strata <- NA
  # 2011 基线到 2013 访视，行政随访按 2 年；死亡者若无精确日期，事件时间记 2 年
  if ("death_status" %in% names(base)) {
    base$fustatus <- .sd_event01(base$death_status, c("1", "Yes", "Y", "Dead", "dead", "死亡"))
    base$futime_years <- ifelse(is.na(base$fustatus), NA_real_, 2)
  } else {
    base$fustatus <- NA_integer_
    base$futime_years <- NA_real_
  }
  base$cvd_status <- NA_integer_
  gap <- NULL
  if (all(is.na(base$Sleep_hours))) {
    gap <- paste(
      "CHARLS 已保留 Hyperlipidemia=Yes，并接上 death_status。",
      "现成匹配表没有睡眠小时。请把睡眠问卷落到 prognosis_v2$charls_sleep_path 后再跑后续块。"
    )
  }
  list(data = base, gap = gap)
}

.sd_load_shhs <- function(root, cfg) {
  p1 <- file.path(root, "SHHS(1)", "EXCEL", "shhs1-dataset-0.18.0.csv")
  pc <- file.path(root, "SHHS(1)", "EXCEL", "shhs-cvd-summary-dataset-0.18.0.csv")
  if (!file.exists(p1) || !file.exists(pc)) stop("SHHS 数据表不存在", call. = FALSE)
  s1 <- utils::read.csv(p1, stringsAsFactors = FALSE)
  cv <- utils::read.csv(pc, stringsAsFactors = FALSE)
  need <- c("nsrrid", "hrswd02", "chol", "hdl", "trig", "age_s1", "gender", "bmi_s1")
  miss <- setdiff(need, names(s1))
  if (length(miss)) stop("SHHS1 缺列: ", paste(miss, collapse = ","), call. = FALSE)
  s1 <- s1[, need, drop = FALSE]
  cv <- cv[, intersect(c("nsrrid", "vital", "censdate", "cvd_death"), names(cv)), drop = FALSE]
  m <- merge(s1, cv, by = "nsrrid", all = FALSE)
  lip <- .sd_dyslipidemia_flag(m$trig, m$chol, m$hdl, NA_real_)
  m$dyslipidemia <- lip$flag
  m$LDL <- lip$ldl_calc
  m <- m[!is.na(m$dyslipidemia) & m$dyslipidemia == 1L, , drop = FALSE]
  death_code <- as.character(cfg$shhs_death_code %||% 0L)
  m$ID <- as.character(m$nsrrid)
  m$Age <- .sd_num(m$age_s1)
  m$Gender <- as.character(m$gender)
  m$BMI <- .sd_num(m$bmi_s1)
  m$Sleep_hours <- .sd_num(m$hrswd02)
  m$TG <- .sd_num(m$trig)
  m$TC <- .sd_num(m$chol)
  m$HDL <- .sd_num(m$hdl)
  m$futime_years <- .sd_num(m$censdate) / 365.25
  m$fustatus <- as.integer(as.character(m$vital) == death_code)
  m$cvd_status <- as.integer(.sd_num(m$cvd_death) == 1)
  m$database <- "SHHS"
  m$survey_weight <- NA_real_
  m$survey_psu <- NA
  m$survey_strata <- NA
  list(data = m, gap = NULL)
}

block_sleep_dyslipid_cohort <- function(ctx, ...) {
  .sd_load_common()
  cfg <- .sd_cfg(ctx)
  root <- cfg$data_root %||% ""
  db <- toupper(as.character(cfg$database %||% "SHHS")[1L])
  if (!nzchar(root) || !dir.exists(root)) {
    stop("prognosis_v2$data_root 不存在: ", root, call. = FALSE)
  }
  loaded <- switch(db,
    NHANES = .sd_load_nhanes(root),
    CHARLS = .sd_load_charls(root, cfg),
    SHHS = .sd_load_shhs(root, cfg),
    stop("未知数据库: ", db, call. = FALSE)
  )
  d <- loaded$data
  n0 <- nrow(d)
  d <- d[!is.na(d$Sleep_hours) & d$Sleep_hours > 0 & d$Sleep_hours < 24, , drop = FALSE]
  n_sleep <- nrow(d)
  ready <- is.null(loaded$gap) && any(!is.na(d$fustatus)) && any(!is.na(d$futime_years))
  if (ready) {
    d <- d[!is.na(d$fustatus) & !is.na(d$futime_years) & d$futime_years > 0, , drop = FALSE]
  }
  attr_df <- data.frame(
    database = db,
    step = c("dyslipidemia_cohort", "sleep_hours_known", "outcome_linked"),
    n = c(n0, n_sleep, if (ready) nrow(d) else NA_integer_),
    stringsAsFactors = FALSE
  )
  .sd_write_csv(attr_df, file.path(.sd_dir(ctx, "tables"), "Cohort_attrition.csv"))
  gap_path <- file.path(.sd_dir(ctx, "tables"), "Cohort_gap.txt")
  if (!is.null(loaded$gap)) {
    writeLines(loaded$gap, gap_path)
    cli::cli_alert_warning(loaded$gap)
  } else if (file.exists(gap_path)) {
    unlink(gap_path)
  }
  ctx <- .sd_put(ctx, d)
  ctx$results$prognosis_v2_ready <- isTRUE(ready) && nrow(d) > 0L
  ctx$results$prognosis_v2_database <- db
  ctx$results$sleep_dyslipid_cohort <- list(n = nrow(d), gap = loaded$gap, attrition = attr_df)
  cli::cli_alert_success("预后2.0 纳排 {db}: n={nrow(d)}，可建模={ctx$results$prognosis_v2_ready}")
  ctx
}

register_block("sleep_dyslipid_cohort", block_sleep_dyslipid_cohort,
               "预后2.0 三库血脂异常+睡眠+死亡纳排")
