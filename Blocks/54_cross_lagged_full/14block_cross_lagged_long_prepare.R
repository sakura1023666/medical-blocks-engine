###############################################################################
#  cross_lagged_long_prepare — 多年纵向：首年基线 + 其余随访；
#    任意随访年出现基线 ID → 有随访；无随访剔除；首发疾病年定 time；
#    产出 long / wide / mediation 表 + 纳排流程图
#
#  config$cross_lagged_long_prepare$panel[[cohort]] =
#    list(baseline_year, country, years = list(list(year, frailty_csv, id_col, outcome_rdata), ...),
#         dep_file, dep_id, dep_score, medition_dir 可继承顶层)
#  register_block: "cross_lagged_long_prepare"
###############################################################################

if (!exists("circadian_wave_enrich", mode = "function")) {
  .epwv_h <- c(
    file.path(getwd(), "R/cross_lagged_circadian_wave_epwv.R"),
    file.path("/mnt/e/01block/01Block-new-Final", "R/cross_lagged_circadian_wave_epwv.R")
  )
  .epwv_h <- .epwv_h[file.exists(.epwv_h)]
  if (length(.epwv_h)) source(.epwv_h[[1L]], local = FALSE)
}

block_cross_lagged_long_prepare <- function(ctx, ...) {
  bl <- ctx$config$cross_lagged_long_prepare %||% list()
  cohort <- as.character(ctx$config$project$database %||% "")[1L]
  if (!nzchar(cohort)) stop("cross_lagged_long_prepare: 需要 project$database", call. = FALSE)

  panel_all <- bl$panel %||% list()
  panel <- panel_all[[cohort]]
  if (is.null(panel))
    stop("cross_lagged_long_prepare: 未配置 panel$", cohort, call. = FALSE)

  base_imp <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(base_imp) || !is.data.frame(base_imp))
    stop("cross_lagged_long_prepare: 需要上游 imputed/cleaned", call. = FALSE)
  if (!"ID" %in% names(base_imp)) {
    idc <- ctx$config$data$id_column %||% "ID"
    if (idc %in% names(base_imp)) names(base_imp)[names(base_imp) == idc] <- "ID"
  }
  base_imp$ID <- as.character(base_imp$ID)
  id_keep <- unique(stats::na.omit(base_imp$ID))

  .recode01 <- function(x) {
    ifelse(is.na(x), NA_real_,
           ifelse(as.character(x) %in% c("1", "Hip_Fracture", "Patellar_Fracture", "Circadian_Disorder"), 1,
                  ifelse(as.character(x) %in% c("0", "No_Fracture", "No_Disorder"), 0, NA_real_)))
  }
  .recode_lab <- function(x) {
    xc <- as.character(x)
    ifelse(is.na(x), NA_character_,
           ifelse(xc %in% c("1", "Hip_Fracture", "Patellar_Fracture"), "Hip_Fracture",
           ifelse(xc %in% c("Circadian_Disorder"), "Circadian_Disorder",
           ifelse(xc %in% c("0", "No_Fracture"), "No_Fracture",
           ifelse(xc %in% c("No_Disorder"), "No_Disorder", xc)))))
  }
  .norm_id <- function(x) sub("^0+", "", as.character(x))
  .as_chr_id <- function(x) {
    if (inherits(x, "haven_labelled") || inherits(x, "vctrs_vctr")) {
      return(as.character(unclass(x)))
    }
    as.character(x)
  }

  .load_outcome <- function(path) {
    if (is.null(path) || !nzchar(path) || !file.exists(path)) return(NULL)
    e <- new.env(parent = emptyenv())
    load(path, envir = e)
    yo <- as.data.frame(e[[ls(e)[1]]], stringsAsFactors = FALSE)
    idy <- setdiff(names(yo), "Disease_Group")[1]
    names(yo)[names(yo) == idy] <- "ID"
    yo$ID <- .as_chr_id(yo$ID)
    yo$Disease01 <- .recode01(yo$Disease_Group)
    yo[!duplicated(yo$ID), c("ID", "Disease01"), drop = FALSE]
  }

  .read_frailty <- function(path, id_col, year_val) {
    if (is.null(path) || !nzchar(path) || !file.exists(path)) return(NULL)
    df <- utils::read.csv(path, check.names = FALSE)
    if (!id_col %in% names(df)) {
      # try common aliases
      alt <- intersect(c("ID", "idauniq", "hhidpn", "HHIDPN"), names(df))
      if (!length(alt)) stop("虚弱文件无 ID 列: ", path, call. = FALSE)
      id_col <- alt[[1]]
    }
    df$ID <- as.character(df[[id_col]])
    # 统一条目名：ELSA/HRS → CHARLS stem；跨波大小写合并
    if (exists("cross_lagged_fi_item_rename_to_canonical", mode = "function")) {
      new_nms <- cross_lagged_fi_item_rename_to_canonical(names(df))
      # 同名合并：优先非 NA；对 0/1 条目若两边都有则取 max（如 Alzheimer∪dementia→memrye）
      if (any(duplicated(new_nms))) {
        for (nm in unique(new_nms[duplicated(new_nms)])) {
          idx <- which(new_nms == nm)
          base <- suppressWarnings(as.numeric(df[[idx[[1L]]]]))
          for (j in idx[-1L]) {
            v <- suppressWarnings(as.numeric(df[[j]]))
            # HRS skip codes (3–9) 不当作缺陷，先规范到 0/1
            .to01 <- function(z) {
              z <- as.numeric(z)
              ifelse(is.na(z), NA_real_,
                     ifelse(z %in% c(0, 1), z,
                            ifelse(z == 1, 1, ifelse(z %in% c(4, 5), 0, NA_real_))))
            }
            # 简单：精确 1 = 缺陷，0 = 无；其它 skip → NA，再与另一列 OR
            b01 <- ifelse(is.na(base), NA_real_, ifelse(base == 1, 1, ifelse(base == 0, 0, NA_real_)))
            v01 <- ifelse(is.na(v), NA_real_, ifelse(v == 1, 1, ifelse(v == 0, 0, NA_real_)))
            base <- ifelse(is.na(b01) & is.na(v01), NA_real_,
                           pmax(ifelse(is.na(b01), 0, b01), ifelse(is.na(v01), 0, v01)))
            base[is.na(b01) & is.na(v01)] <- NA_real_
          }
          # 若 base 仍有 >1 的原始码
          if (any(base > 1, na.rm = TRUE))
            base <- ifelse(is.na(base), NA_real_, as.numeric(base == 1))
          df[[idx[[1L]]]] <- base
          df[idx[-1L]] <- NULL
          new_nms <- new_nms[-idx[-1L]]
        }
      }
      names(df) <- new_nms
      # HRS 遗留未合并的 skip 码：任何 >1 的条目列规范为 0/1（1=缺陷）
      for (nm in setdiff(names(df), c("ID", id_col, "FI", "Frailty", "score", "DN",
                                      "cognition_score", "AIP", "AIP_FI", "year"))) {
        if (!is.numeric(df[[nm]]) && !is.integer(df[[nm]])) next
        z <- suppressWarnings(as.numeric(df[[nm]]))
        if (any(z > 1, na.rm = TRUE) && max(z, na.rm = TRUE) <= 9) {
          df[[nm]] <- as.integer(z == 1L)
        }
      }
    }
    if (!"FI" %in% names(df)) {
      if ("frailty26_total" %in% names(df))
        df$FI <- as.numeric(df$frailty26_total) / 26
      else stop("虚弱文件无 FI: ", path, call. = FALSE)
    }
    df$FI <- as.numeric(df$FI)
    df$Frailty <- as.integer(df$FI >= 0.25)
    df$year <- as.integer(year_val)
    # keep frailty item columns (numeric 0/1 mostly)
    skip <- c(id_col, "idauniq", "hhidpn", "HHIDPN", "AIP", "AIP_FI",
              "bl_tg", "bl_hdl", "depression", "DN", "score", "cognition_score",
              "PScedA", "PScedB", "PScedC", "PScedD", "PScedE", "PScedF", "PScedG", "PScedH",
              "psceda", "pscedb", "pscedc", "pscedd", "pscede", "pscedf", "pscedg", "pscedh")
    keep_extra <- setdiff(names(df), c("ID", skip))
    keep_extra <- keep_extra[vapply(df[keep_extra], function(z) {
      is.numeric(z) || is.integer(z) || all(as.character(z) %in% c("0", "1", NA, "TRUE", "FALSE"))
    }, logical(1))]
    out <- df[, unique(c("ID", "year", "FI", "Frailty", keep_extra)), drop = FALSE]
    out <- out[!is.na(out$ID) & !duplicated(out$ID), , drop = FALSE]
    out
  }

  years_cfg <- panel$years %||% list()
  if (!length(years_cfg)) stop("panel$", cohort, "$years 为空", call. = FALSE)

  fr_list <- list()
  dis_list <- list()
  present_ids_by_year <- list()
  for (yc in years_cfg) {
    y <- as.integer(yc$year)
    id_col <- yc$id_col %||% "ID"
    fr <- .read_frailty(yc$frailty_csv, id_col, y)
    yo <- .load_outcome(yc$outcome_rdata %||% NULL)
    ids_y <- character(0)
    if (!is.null(fr)) {
      carry <- as.character(bl$carry_vars %||% character(0))
      carry <- carry[nzchar(carry)]
      circ_path <- yc$circadian_csv %||% NULL
      if (length(carry) && !is.null(circ_path) && nzchar(circ_path) && file.exists(circ_path)) {
        cc <- utils::read.csv(circ_path, check.names = FALSE)
        cid <- yc$circadian_id %||% id_col
        if (!cid %in% names(cc)) {
          alt <- intersect(c("ID", "idauniq", "SEQN", "idauniq"), names(cc))
          if (!length(alt)) stop("circadian_csv 无 ID 列: ", circ_path, call. = FALSE)
          cid <- alt[[1L]]
        }
        cc$ID <- as.character(cc[[cid]])
        if (identical(cohort, "CHARLS")) {
          cc$ID <- ifelse(
            nchar(cc$ID) == 11L, paste0(substr(cc$ID, 1, 9), "0", substr(cc$ID, 10, 11)),
            ifelse(nchar(cc$ID) == 10L, paste0(substr(cc$ID, 1, 8), "0", substr(cc$ID, 9, 10)), cc$ID)
          )
        }
        # 昼夜：该波血压+该波年龄算 ePWV；预编码 condition 药物 NA 会把 C2–C4 打成全 1，故从源列重建
        want_wave_epwv <- any(grepl("^condition[0-9]+$", carry)) ||
          "ePWV" %in% as.character(bl$node_stems %||% character(0))
        if (isTRUE(want_wave_epwv) && exists("circadian_wave_enrich", mode = "function")) {
          byear <- as.integer(panel$baseline_year %||% y)
          age_map <- NULL
          age_off <- 0
          age_src <- "none"
          if (!is.null(yc$age_rdata) && nzchar(as.character(yc$age_rdata)[1L]) &&
              file.exists(yc$age_rdata) && exists("circadian_load_age_map", mode = "function")) {
            age_map <- circadian_load_age_map(yc$age_rdata, cohort)
            age_off <- 0
            age_src <- "wave_D01"
          }
          if (is.null(age_map) || !length(age_map)) {
            if ("Age" %in% names(base_imp)) {
              age_map <- stats::setNames(as.numeric(base_imp$Age), as.character(base_imp$ID))
              age_map <- age_map[!is.na(names(age_map)) & !duplicated(names(age_map))]
              age_off <- as.integer(y) - byear
              age_src <- "imputed_Age_plus_delta"
            } else {
              sr <- ctx$config$project$study_root %||%
                Sys.getenv("CROSS_LAGGED_STUDY_ROOT", unset = "")
              p3 <- file.path(sr, paste0("phase1_", cohort), "checkpoints", "step03_index.rds")
              if (nzchar(sr) && file.exists(p3)) {
                ck3 <- readRDS(p3)
                if (!is.null(ck3$ctx)) ck3 <- ck3$ctx
                d3 <- ck3$data$imputed %||% ck3$data$cleaned
                if (is.data.frame(d3) && all(c("ID", "Age") %in% names(d3))) {
                  age_map <- stats::setNames(as.numeric(d3$Age), as.character(d3$ID))
                  age_map <- age_map[!is.na(names(age_map)) & !duplicated(names(age_map))]
                  age_off <- as.integer(y) - byear
                  age_src <- "step03_Age_plus_delta"
                }
              }
            }
          }
          cc <- circadian_wave_enrich(
            cc, cohort, y, byear, age_map,
            rebuild_conditions = isTRUE(bl$rebuild_circadian_conditions %||% TRUE),
            age_offset = age_off
          )
          cli::cli_alert_info(
            "{cohort} {y}: age_src={age_src}; wave ePWV finite={sum(is.finite(cc$ePWV))}/{nrow(cc)}; C2 pos={round(mean(cc$condition2 == 1, na.rm = TRUE), 3)}"
          )
        }
        keep_extra_cc <- intersect(c("ePWV", "SBP", "DBP", "Age_wave"), names(cc))
        keep_c <- unique(c(intersect(carry, names(cc)), keep_extra_cc))
        miss_c <- setdiff(carry, keep_c)
        if (length(miss_c))
          stop("circadian_csv 缺 carry_vars: ", paste(miss_c, collapse = ","), call. = FALSE)
        cc <- cc[, c("ID", keep_c), drop = FALSE]
        cc <- cc[!duplicated(cc$ID), , drop = FALSE]
        fr <- merge(fr, cc, by = "ID", all.x = TRUE)
      }
      fr_list[[as.character(y)]] <- fr
      ids_y <- union(ids_y, fr$ID)
    }
    if (!is.null(yo)) {
      yo$year <- y
      dis_list[[as.character(y)]] <- yo
      ids_y <- union(ids_y, yo$ID)
    }
    present_ids_by_year[[as.character(y)]] <- intersect(ids_y, id_keep)
  }

  baseline_year <- as.integer(panel$baseline_year %||% min(vapply(years_cfg, function(z) as.integer(z$year), 1L)))
  fu_years <- sort(setdiff(as.integer(names(present_ids_by_year)), baseline_year))
  if (!length(fu_years))
    stop("cross_lagged_long_prepare: 无随访年份（需配置 baseline 以外年份）", call. = FALSE)

  # disease long
  dis_long <- if (length(dis_list)) {
    d <- do.call(rbind, lapply(dis_list, function(z) z[, c("ID", "year", "Disease01"), drop = FALSE]))
    rownames(d) <- NULL
    d[d$ID %in% id_keep, , drop = FALSE]
  } else {
    data.frame(ID = character(), year = integer(), Disease01 = numeric())
  }

  # frailty long (align columns)
  fr_long <- NULL
  if (length(fr_list)) {
    all_cols <- Reduce(union, lapply(fr_list, names))
    fr_aligned <- lapply(fr_list, function(z) {
      miss <- setdiff(all_cols, names(z))
      for (m in miss) z[[m]] <- NA
      z[, all_cols, drop = FALSE]
    })
    fr_long <- do.call(rbind, fr_aligned)
    rownames(fr_long) <- NULL
    fr_long <- fr_long[fr_long$ID %in% id_keep, , drop = FALSE]
  }

  # ── 纳排 ──────────────────────────────────────────────────────────────────
  flow <- list()
  bl_ids <- present_ids_by_year[[as.character(baseline_year)]] %||% character(0)
  flow$n_baseline_present <- length(bl_ids)

  # baseline disease status
  bl_dis <- dis_long[dis_long$year == baseline_year & dis_long$ID %in% bl_ids, , drop = FALSE]
  bl_dis <- bl_dis[!duplicated(bl_dis$ID), , drop = FALSE]
  # require known disease-free at baseline when outcome available
  if (nrow(bl_dis)) {
    free_ids <- bl_dis$ID[!is.na(bl_dis$Disease01) & bl_dis$Disease01 == 0]
    prev_ids <- bl_dis$ID[!is.na(bl_dis$Disease01) & bl_dis$Disease01 == 1]
    unk_ids <- setdiff(bl_ids, bl_dis$ID[!is.na(bl_dis$Disease01)])
    # keep only known free
    wave1_ids <- free_ids
    flow$n_drop_prevalent <- length(prev_ids)
    flow$n_drop_baseline_outcome_missing <- length(unk_ids)
  } else {
    # no baseline outcome → keep all with baseline presence (warn)
    wave1_ids <- bl_ids
    flow$n_drop_prevalent <- 0L
    flow$n_drop_baseline_outcome_missing <- 0L
    cli::cli_alert_warning("{cohort}: 基线年无 D03 结局，跳过基线患病剔除")
  }
  flow$n_after_baseline_free <- length(wave1_ids)

  # 任意随访年出现基线 ID → 有随访
  fu_ids_any <- unique(unlist(present_ids_by_year[as.character(fu_years)], use.names = FALSE))
  has_fu <- intersect(wave1_ids, fu_ids_any)
  no_fu <- setdiff(wave1_ids, fu_ids_any)
  flow$n_drop_no_followup <- length(no_fu)
  flow$n_with_followup <- length(has_fu)
  eligible_ids <- has_fu

  # 要求基线有 FI
  if (!is.null(fr_long)) {
    bl_fi <- fr_long[fr_long$year == baseline_year & fr_long$ID %in% eligible_ids & !is.na(fr_long$FI), "ID", drop = TRUE]
    flow$n_drop_no_baseline_FI <- length(setdiff(eligible_ids, bl_fi))
    eligible_ids <- intersect(eligible_ids, bl_fi)
  } else {
    flow$n_drop_no_baseline_FI <- 0L
  }
  flow$n_analytic <- length(eligible_ids)

  # ── wave2：首发疾病年，否则末次随访年 ────────────────────────────────────
  fu_dis <- dis_long[dis_long$year %in% fu_years & dis_long$ID %in% eligible_ids, , drop = FALSE]
  fu_present <- data.frame(
    ID = rep(eligible_ids, each = length(fu_years)),
    year = rep(fu_years, times = length(eligible_ids)),
    stringsAsFactors = FALSE
  )
  # presence flag from any source
  present_fu <- do.call(rbind, lapply(fu_years, function(y) {
    data.frame(ID = present_ids_by_year[[as.character(y)]], year = y, present = 1L, stringsAsFactors = FALSE)
  }))
  present_fu <- present_fu[present_fu$ID %in% eligible_ids, , drop = FALSE]

  wave2_info <- lapply(eligible_ids, function(id) {
    d_sub <- fu_dis[fu_dis$ID == id & !is.na(fu_dis$Disease01), , drop = FALSE]
    p_sub <- present_fu[present_fu$ID == id, , drop = FALSE]
    any_event <- nrow(d_sub) > 0L && any(d_sub$Disease01 == 1)
    if (any_event) {
      event_year <- min(d_sub$year[d_sub$Disease01 == 1], na.rm = TRUE)
      wave2_year <- as.integer(event_year)
      event <- 1L
    } else {
      last_year <- if (nrow(p_sub)) max(p_sub$year, na.rm = TRUE) else NA_integer_
      # prefer last year with disease observed =0, else last present
      if (nrow(d_sub)) last_year <- max(d_sub$year, na.rm = TRUE)
      wave2_year <- as.integer(last_year)
      event <- 0L
    }
    data.frame(
      ID = id, wave2_year = wave2_year, event = event,
      time = as.integer(wave2_year - baseline_year),
      stringsAsFactors = FALSE
    )
  })
  wave2_info <- do.call(rbind, wave2_info)
  wave2_info <- wave2_info[!is.na(wave2_info$wave2_year), , drop = FALSE]
  eligible_ids <- intersect(eligible_ids, wave2_info$ID)
  flow$n_drop_no_wave2_year <- flow$n_analytic - length(eligible_ids)
  flow$n_analytic <- length(eligible_ids)
  wave2_info <- wave2_info[wave2_info$ID %in% eligible_ids, , drop = FALSE]

  # covariates from imputed (baseline)
  cov_skip <- c("ID", "Disease_Group", "FI", "Frailty", "SEQN", "Cohort", "Country")
  cov_cols <- setdiff(names(base_imp), cov_skip)
  cov_df <- base_imp[base_imp$ID %in% eligible_ids, c("ID", cov_cols), drop = FALSE]
  cov_df <- cov_df[!duplicated(cov_df$ID), , drop = FALSE]

  .join_fr_year <- function(ids, year_vec) {
    # year_vec aligned to ids
    if (is.null(fr_long)) {
      return(data.frame(ID = ids, year = year_vec, FI = NA_real_, Frailty = NA_integer_))
    }
    key <- paste(ids, year_vec, sep = "\r")
    fr_long$._k <- paste(fr_long$ID, fr_long$year, sep = "\r")
    hit <- fr_long[match(key, fr_long$._k), , drop = FALSE]
    fr_long$._k <- NULL
    hit$._k <- NULL
    hit$ID <- ids
    hit$year <- as.integer(year_vec)
    hit
  }

  # wave1 rows
  w1 <- data.frame(
    ID = eligible_ids, wave = 1L, year = baseline_year,
    time = wave2_info$time[match(eligible_ids, wave2_info$ID)],
    Disease01 = 0,
    stringsAsFactors = FALSE
  )
  fr1 <- .join_fr_year(w1$ID, w1$year)
  # drop duplicate ID/year cols before cbind
  fr1b <- fr1[, setdiff(names(fr1), c("ID", "year")), drop = FALSE]
  w1 <- cbind(w1, fr1b)
  w1 <- merge(w1, cov_df, by = "ID", all.x = TRUE, suffixes = c("", ".cov"))
  .drop_wave_cov_suffix <- function(d) {
    wave_keep <- intersect(
      c("ePWV", paste0("condition", 1:7), "SBP", "DBP", "Age_wave"),
      names(d)
    )
    drop <- intersect(paste0(wave_keep, ".cov"), names(d))
    if (length(drop)) d[drop] <- NULL
    d
  }
  w1 <- .drop_wave_cov_suffix(w1)

  # wave2 rows
  w2 <- data.frame(
    ID = wave2_info$ID, wave = 2L, year = wave2_info$wave2_year,
    time = wave2_info$time, Disease01 = wave2_info$event,
    stringsAsFactors = FALSE
  )
  fr2 <- .join_fr_year(w2$ID, w2$year)
  # if FI missing at event year, fall back to nearest prior FU frailty year
  miss_fi <- is.na(fr2$FI)
  if (any(miss_fi) && !is.null(fr_long)) {
    for (i in which(miss_fi)) {
      id <- w2$ID[i]; ty <- w2$year[i]
      cand <- fr_long[fr_long$ID == id & fr_long$year %in% fu_years & fr_long$year <= ty & !is.na(fr_long$FI), , drop = FALSE]
      if (!nrow(cand))
        cand <- fr_long[fr_long$ID == id & fr_long$year %in% fu_years & !is.na(fr_long$FI), , drop = FALSE]
      if (nrow(cand)) {
        cand <- cand[order(cand$year, decreasing = TRUE), , drop = FALSE][1, , drop = FALSE]
        for (nm in setdiff(names(cand), c("ID", "year"))) fr2[i, nm] <- cand[[nm]]
        # keep analytical year as event/censor year; FI may be from nearest
      }
    }
  }
  fr2b <- fr2[, setdiff(names(fr2), c("ID", "year")), drop = FALSE]
  w2 <- cbind(w2, fr2b)
  w2 <- merge(w2, cov_df, by = "ID", all.x = TRUE, suffixes = c("", ".cov"))
  w2 <- .drop_wave_cov_suffix(w2)

  # align columns and bind long (wave1+wave2 analysis panel)
  common <- intersect(names(w1), names(w2))
  long_pair <- rbind(w1[, common, drop = FALSE], w2[, common, drop = FALSE])
  long_pair <- long_pair[order(long_pair$ID, long_pair$wave), , drop = FALSE]
  ag <- as.character(ctx$config$project$analysis_group %||% "Hip_Fracture")[1L]
  rg <- as.character(ctx$config$project$reference_group %||% "No_Fracture")[1L]
  long_pair$Disease_Group <- ifelse(long_pair$Disease01 == 1, ag, rg)
  long_pair$Country <- panel$country %||% cohort
  long_pair$Cohort <- cohort
  long_pair$Year <- as.character(long_pair$year)

  # drop IDs with missing FI on either wave
  ok_fi <- tapply(long_pair$FI, long_pair$ID, function(z) all(!is.na(z)))
  keep_fi_ids <- names(ok_fi)[ok_fi]
  flow$n_drop_incomplete_FI_pair <- length(setdiff(unique(long_pair$ID), keep_fi_ids))
  long_pair <- long_pair[long_pair$ID %in% keep_fi_ids, , drop = FALSE]
  flow$n_final_pair <- length(unique(long_pair$ID))

  # full multi-year long for Fig1 / country-year（仅最终队列）
  long_all <- NULL
  if (!is.null(fr_long)) {
    long_all <- fr_long[fr_long$ID %in% keep_fi_ids, , drop = FALSE]
    # attach disease status that year if available
    if (nrow(dis_long)) {
      long_all <- merge(long_all, dis_long, by = c("ID", "year"), all.x = TRUE)
    } else long_all$Disease01 <- NA_real_
    # for descriptive plots: Disease_Group = eventual T2 event label (fixed per ID) OR year-specific
    # Fig1 uses year-specific when available; else map eventual outcome
    ev <- wave2_info[match(long_all$ID, wave2_info$ID), , drop = FALSE]
    long_all$Disease_Group <- ifelse(
      !is.na(long_all$Disease01),
      ifelse(long_all$Disease01 == 1, ag, rg),
      ifelse(ev$event == 1, ag, rg)
    )
    long_all$Country <- panel$country %||% cohort
    long_all$Cohort <- cohort
    long_all$Year <- as.character(long_all$year)
    long_all$wave <- ifelse(long_all$year == baseline_year, 1L, 2L)
    # 基线协变量挂到多年 long；ePWV / circadian 成分若已按波写入则不再用基线覆盖
    cov_attach <- setdiff(names(cov_df), names(long_all))
    cov_attach <- setdiff(cov_attach, c("ePWV", paste0("condition", 1:7), "SBP", "DBP", "Age_wave"))
    if (length(cov_attach)) {
      long_all <- merge(long_all, cov_df[, c("ID", cov_attach), drop = FALSE], by = "ID", all.x = TRUE)
    }
  } else {
    long_all <- long_pair
  }

  # wide T1/T2
  .to_wide <- function(dlong) {
    d1 <- dlong[dlong$wave == 1L, , drop = FALSE]
    d2 <- dlong[dlong$wave == 2L, , drop = FALSE]
    skip <- c("ID", "wave", "year", "Year", "Cohort", "Country", "time")
    v1 <- setdiff(names(d1), skip)
    v2 <- setdiff(names(d2), skip)
    names(d1)[names(d1) %in% v1] <- paste0("T1_", v1)
    names(d2)[names(d2) %in% v2] <- paste0("T2_", v2)
    # keep time on T2
    d2$T2_time <- d2$time
    out <- merge(
      d1[, c("ID", "Country", "Cohort", grep("^T1_", names(d1), value = TRUE)), drop = FALSE],
      d2[, c("ID", "T2_time", grep("^T2_", names(d2), value = TRUE)), drop = FALSE],
      by = "ID", all = FALSE
    )
    # change metrics
    if (all(c("T1_FI", "T2_FI") %in% names(out))) {
      out$mean_Index <- (as.numeric(out$T1_FI) + as.numeric(out$T2_FI)) / 2
      out$Index_change <- as.numeric(out$T2_FI) - as.numeric(out$T1_FI)
      out$FI_mean <- out$mean_Index
      out$FI_change <- out$Index_change
    }
    out
  }
  wide <- .to_wide(long_pair)

  # CLPN 用宽表：仅 FI/Frailty/Disease + 虚弱条目（去掉人口学协变量）
  demo_stems <- c("Age", "Gender", "Education", "Marital_Status", "Smoking", "Alcohol_drinking",
                  "BMI", "Weight", "Height", "Hypertension", "T2DM", "Cancer", "Psychiatric",
                  "HbA1c", "Residence", "Income", "Race", "Sex", "Country", "Cohort",
                  "Disease_Group", "Year", "time")
  stems_t1 <- sub("^T1_", "", grep("^T1_", names(wide), value = TRUE))
  stems_t2 <- sub("^T2_", "", grep("^T2_", names(wide), value = TRUE))
  stems <- intersect(stems_t1, stems_t2)
  stems <- setdiff(stems, c(demo_stems, "time"))
  # CLPN：FI 条目 + 疾病结局（文献网络含 CVD/疾病节点）+ 可选血脂
  item_pref <- c(
    "hibpe", "diabe", "cancre", "lunge", "psyche", "memrye", "arthre",
    "dressa", "batha", "eata", "beda", "toilta",
    "mealsa", "shopa", "medsa", "moneya",
    "srh", "armsa", "chaira", "climsa", "dimea", "lifta", "stoopa", "walk100a",
    "glass", "hear"
  )
  lipid_pref <- c("Triglycerides", "HDL_Cholesterol", "newtg", "newhdl")
  item_first <- intersect(item_pref, stems)
  out_first <- intersect(c("Disease01"), stems)
  lipid_first <- intersect(lipid_pref, stems)
  # 库特异 0/1 额外项（排除波次前缀垃圾列 *c069 / *d151 等）
  demo_drop <- c(
    demo_stems, "HR", "SBP", "DBP", "PP", "WBC", "Platelet", "Platelet_Count",
    "Waist_circumference", "Waist", "Hemoglobin", "LDL_Cholesterol", "Total_Cholesterol",
    "AIP", "AIP_FI", "FI", "Frailty", "frailty26_total", "Disease_Group"
  )
  extra_cand <- setdiff(stems, c(item_first, out_first, lipid_first, demo_drop, lipid_pref))
  extra_cand <- extra_cand[!grepl("^[a-z][cgd][0-9]+$", extra_cand)]
  stems_clpn <- unique(c(out_first, item_first, lipid_first, extra_cand))
  if (!length(stems_clpn)) {
    stems_clpn <- setdiff(stems, demo_drop)
  }
  if (length(stems_clpn) > 40L) stems_clpn <- stems_clpn[seq_len(40L)]
  wide_clpn <- wide[, c("ID", intersect(c("Country", "Cohort", "T2_time"), names(wide)),
                        paste0("T1_", stems_clpn), paste0("T2_", stems_clpn)), drop = FALSE]

  # ── mediation 表（基线暴露 + 中介 + 随访结局）────────────────────────────
  med_dir <- bl$medition_dir %||% panel$medition_dir
  dep_file <- panel$dep_file %||% NULL
  med_out <- NULL
  w1m <- long_pair[long_pair$wave == 1L, , drop = FALSE]
  w2m <- long_pair[long_pair$wave == 2L, , drop = FALSE]
  idx_var <- as.character(ctx$config$incidence$index_var %||% "FI")[1L]
  treat_var <- as.character(ctx$config$mediation_longitudinal$treat %||% idx_var)[1L]
  med_var <- as.character(ctx$config$mediation_longitudinal$mediator %||% "Depression_cont")[1L]
  m2_lock <- as.character(ctx$results$Model2Factors %||% character(0))
  med_cov_prefer <- unique(c(
    "ID", "FI", idx_var, treat_var, med_var,
    "Age", "Gender", "Education", "Marital_Status",
    "Smoking", "Alcohol_drinking", "BMI", "Weight", "Hemoglobin",
    "Hypertension", "Diabetes", "T2DM", "Country", "Cohort",
    m2_lock
  ))
  med_out <- w1m[, intersect(med_cov_prefer, names(w1m)), drop = FALSE]
  # 中介=FI 且暴露不是 FI：用随访波 FI（中间/同期波），保留基线为 FI_T1
  if (identical(med_var, "FI") && !identical(treat_var, "FI") && "FI" %in% names(w2m)) {
    med_out$FI_T1 <- med_out$FI
    med_out$FI <- w2m$FI[match(med_out$ID, w2m$ID)]
  }
  med_out <- merge(med_out, w2m[, c("ID", "Disease_Group", "time"), drop = FALSE], by = "ID", all = FALSE)

  dep_path <- if (!is.null(med_dir) && !is.null(dep_file)) file.path(med_dir, dep_file) else ""
  if (nzchar(dep_path) && file.exists(dep_path)) {
    dep <- utils::read.csv(dep_path, check.names = FALSE)
    id_spec <- panel$dep_id %||% "ID"
    if (identical(id_spec, "HHID_PN")) {
      dep$ID <- paste0(dep$HHID, sprintf("%03d", as.integer(dep$PN)))
    } else if (id_spec %in% names(dep)) {
      dep$ID <- as.character(dep[[id_spec]])
    } else if ("ID" %in% names(dep)) {
      dep$ID <- as.character(dep$ID)
    } else stop("抑郁缺 ID", call. = FALSE)
    if (identical(cohort, "CHARLS")) {
      dep$ID <- ifelse(
        nchar(dep$ID) == 11L, paste0(substr(dep$ID, 1, 9), "0", substr(dep$ID, 10, 11)),
        ifelse(nchar(dep$ID) == 10L, paste0(substr(dep$ID, 1, 8), "0", substr(dep$ID, 9, 10)), dep$ID)
      )
    }
    score <- panel$dep_score
    if (is.null(score) || !score %in% names(dep)) {
      hit <- grep("cesd|total|score|depress", names(dep), ignore.case = TRUE, value = TRUE)
      score <- hit[1]
    }
    dep2 <- data.frame(ID = dep$ID, Depression_cont = as.numeric(dep[[score]]), stringsAsFactors = FALSE)
    dep2 <- dep2[!is.na(dep2$ID) & !is.na(dep2$Depression_cont) & !duplicated(dep2$ID), , drop = FALSE]
    # 左连抑郁；中介是抑郁时再按 Depression_cont 完整病例筛
    med_out <- merge(med_out, dep2, by = "ID", all.x = TRUE)
  } else {
    cli::cli_alert_warning("{cohort}: 未合并抑郁（缺文件）")
  }

  need_cc <- intersect(c(treat_var, med_var, "Disease_Group"), names(med_out))
  if (length(need_cc) < 3L) {
    cli::cli_alert_warning("{cohort}: mediation 缺列 {paste(setdiff(c(treat_var, med_var, 'Disease_Group'), names(med_out)), collapse=', ')}")
    med_out <- NULL
  } else {
    med_out <- med_out[stats::complete.cases(med_out[, need_cc, drop = FALSE]), , drop = FALSE]
  }

  # ── 写出纳排表 + 流程图 ────────────────────────────────────────────────────
  out_root <- ctx$config$project$output_dir %||% "Output"
  tab_dir <- file.path(out_root, "Tables")
  fig_dir <- file.path(out_root, "Figures")
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

  flow_df <- data.frame(
    step = c(
      "Baseline year present (ID in baseline frailty/outcome)",
      "Exclude prevalent disease at baseline",
      "Exclude missing baseline outcome",
      "After baseline disease-free",
      "Exclude no follow-up in any FU year",
      "With any follow-up",
      "Exclude missing baseline FI",
      "Exclude incomplete FI at T1/T2 pair",
      "Final analytic (wave1+wave2 pair)"
    ),
    n = c(
      flow$n_baseline_present,
      flow$n_drop_prevalent,
      flow$n_drop_baseline_outcome_missing,
      flow$n_after_baseline_free,
      flow$n_drop_no_followup,
      flow$n_with_followup,
      flow$n_drop_no_baseline_FI %||% 0L,
      flow$n_drop_incomplete_FI_pair %||% 0L,
      flow$n_final_pair
    ),
    note = c("kept", "dropped", "dropped", "kept", "dropped", "kept", "dropped", "dropped", "kept"),
    stringsAsFactors = FALSE
  )
  utils::write.csv(flow_df, file.path(tab_dir, paste0("Flowchart_attrition_", cohort, ".csv")), row.names = FALSE)

  # simple PDF flowchart
  pdf_path <- file.path(fig_dir, paste0("Figure 1-", cohort, ". Longitudinal inclusion exclusion flowchart.pdf"))
  grDevices::pdf(pdf_path, width = 8.5, height = 10)
  op <- graphics::par(mar = c(1, 1, 2, 1))
  on.exit(graphics::par(op), add = TRUE)
  graphics::plot.new()
  graphics::title(main = paste0(cohort, " — Inclusion / Exclusion"), cex.main = 1.2)
  lines_txt <- c(
    sprintf("Baseline present (year %s): N = %s", baseline_year, flow$n_baseline_present),
    sprintf("− Prevalent disease at baseline: %s", flow$n_drop_prevalent),
    sprintf("− Missing baseline outcome: %s", flow$n_drop_baseline_outcome_missing),
    sprintf("= Disease-free at baseline: N = %s", flow$n_after_baseline_free),
    sprintf("− No follow-up in any FU year (%s): %s",
            paste(fu_years, collapse = "/"), flow$n_drop_no_followup),
    sprintf("= With any follow-up: N = %s", flow$n_with_followup),
    sprintf("− Missing baseline FI: %s", flow$n_drop_no_baseline_FI %||% 0L),
    sprintf("− Incomplete FI at T1/T2 pair: %s", flow$n_drop_incomplete_FI_pair %||% 0L),
    sprintf("Final analytic sample: N = %s (events at T2 = %s)",
            flow$n_final_pair,
            sum(long_pair$Disease01[long_pair$wave == 2L] == 1, na.rm = TRUE))
  )
  graphics::text(0.05, seq(0.92, 0.08, length.out = length(lines_txt)), labels = lines_txt,
                 adj = 0, cex = 1.05, family = "sans")
  grDevices::dev.off()

  # save RData
  save(long_pair, long_all, wide, wide_clpn, wave2_info, flow_df,
       file = file.path(out_root, paste0("D05_long_", cohort, ".RData")))

  ctx$data$longitudinal <- long_all
  ctx$data$longitudinal_pair <- long_pair
  ctx$data$longitudinal_wide <- wide
  ctx$data$longitudinal_wide_clpn <- wide_clpn
  if (!is.null(med_out)) ctx$data$longitudinal_mediation <- med_out
  # imputed stays for forest on baseline cross-section if needed; forest uses imputed by default —
  # also expose pair wave1 as optional
  ctx$results$long_prepare <- list(
    cohort = cohort,
    baseline_year = baseline_year,
    fu_years = fu_years,
    n_final = flow$n_final_pair,
    n_event = sum(long_pair$Disease01[long_pair$wave == 2L] == 1, na.rm = TRUE),
    n_drop_no_followup = flow$n_drop_no_followup,
    flowchart_pdf = pdf_path,
    flowchart_csv = file.path(tab_dir, paste0("Flowchart_attrition_", cohort, ".csv")),
    mediation_n = if (!is.null(med_out)) nrow(med_out) else 0L
  )
  cli::cli_alert_success(
    "{cohort} 纵向准备完成: final N={flow$n_final_pair}, drop_no_FU={flow$n_drop_no_followup}, events={ctx$results$long_prepare$n_event}"
  )
  cli::cli_alert_info("纳排图: {pdf_path}")
  ctx
}

register_block("cross_lagged_long_prepare", block_cross_lagged_long_prepare,
               "多年纵向准备+无随访剔除+纳排图")
