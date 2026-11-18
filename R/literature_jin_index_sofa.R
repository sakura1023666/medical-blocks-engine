###############################################################################
# literature_jin_index_sofa.R — Jin 2025 指标×SOFA 预后方法助手
#
# 文献: Jin et al. Cardiovasc Diabetol 2025;24:422 (DOI 10.1186/s12933-025-02969-1)
# 迁移: 方法菜谱 → 脓毒症双库（MIMIC 开发 + eICU 外验）；暴露=复合指标（非仅 SHR）
#
# 四组: Q1 Low×Low SOFA | Q2 High×Low SOFA | Q3 Low×High SOFA | Q4 High×High SOFA
# SOFA 默认切点 5（Methods）；暴露 High/Low 默认 T3/T1，T2=Middle 不入四组
###############################################################################

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x
}

#' SOFA 二分：< cutoff → Low；≥ cutoff → High
jin_sofa_binary <- function(sofa, cutoff = 5) {
  v <- suppressWarnings(as.numeric(sofa))
  cut <- suppressWarnings(as.numeric(cutoff)[1L])
  if (!is.finite(cut)) cut <- 5
  out <- ifelse(is.na(v), NA_character_,
                ifelse(v >= cut, "High", "Low"))
  factor(out, levels = c("Low", "High"))
}

#' 暴露三分位 → High / Low / Middle
#' mode="t3_vs_t1"：T3/最高=High，T1/最低=Low，中间=Middle
jin_exposure_high_low <- function(index_tert, mode = "t3_vs_t1") {
  mode <- tolower(trimws(as.character(mode)[1L] %||% "t3_vs_t1"))
  x <- as.character(index_tert)
  x <- trimws(x)
  # 归一常见标签
  x_u <- toupper(gsub("\\s+", "", x))
  out <- rep(NA_character_, length(x))

  if (!identical(mode, "t3_vs_t1")) {
    warning("jin_exposure_high_low: 未知 mode='", mode, "'，回退 t3_vs_t1", call. = FALSE)
  }

  is_t1 <- x_u %in% c("T1", "Q1", "LOW", "T1_LOW", "TERTILE1", "1") |
    grepl("^T1", x_u) |
    (grepl("LOW", x_u) & !grepl("HIGH|MIDDLE|MID|MEDIUM", x_u))
  is_t3 <- x_u %in% c("T3", "Q3", "HIGH", "T3_HIGH", "TERTILE3", "3") |
    grepl("^T3", x_u) |
    (grepl("HIGH", x_u) & !grepl("LOW|MIDDLE|MID", x_u))
  is_t2 <- x_u %in% c("T2", "Q2", "MIDDLE", "MID", "MEDIUM", "T2_MID", "TERTILE2", "2") |
    grepl("^T2", x_u) |
    grepl("MIDDLE|MEDIUM|^MID$", x_u)

  # 若为有序因子/数字 1:3，优先按水平序
  if (is.factor(index_tert) || is.ordered(index_tert)) {
    lev <- levels(factor(index_tert))
    if (length(lev) >= 3L) {
      out[as.character(index_tert) == lev[[1L]]] <- "Low"
      out[as.character(index_tert) == lev[[length(lev)]]] <- "High"
      if (length(lev) >= 3L) {
        mid <- lev[seq(2L, length(lev) - 1L)]
        out[as.character(index_tert) %in% mid] <- "Middle"
      }
      return(factor(out, levels = c("Low", "Middle", "High")))
    }
  }

  out[is_t1] <- "Low"
  out[is_t3] <- "High"
  out[is_t2 & is.na(out)] <- "Middle"
  # 未匹配的非 NA 原值：尝试数值
  num <- suppressWarnings(as.numeric(x))
  miss <- is.na(out) & !is.na(x) & x != ""
  if (any(miss) && any(is.finite(num[miss]))) {
    # 若整体像 1/2/3
    u <- sort(unique(num[is.finite(num)]))
    if (length(u) >= 3L) {
      out[miss & num == min(u)] <- "Low"
      out[miss & num == max(u)] <- "High"
      out[miss & is.finite(num) & num > min(u) & num < max(u)] <- "Middle"
    }
  }
  factor(out, levels = c("Low", "Middle", "High"))
}

#' High/Low × SOFA_bin → Q1–Q4；Middle 或不完整 → NA
#' Q1 Low+Low | Q2 High+Low | Q3 Low+High | Q4 High+High
jin_index_sofa_q4 <- function(high_low, sofa_bin) {
  hl <- as.character(high_low)
  sb <- as.character(sofa_bin)
  hl <- ifelse(toupper(trimws(hl)) %in% c("HIGH", "H"), "High",
               ifelse(toupper(trimws(hl)) %in% c("LOW", "L"), "Low",
                      ifelse(grepl("middle|mid|medium", hl, ignore.case = TRUE), "Middle", hl)))
  sb <- ifelse(toupper(trimws(sb)) %in% c("HIGH", "H"), "High",
               ifelse(toupper(trimws(sb)) %in% c("LOW", "L"), "Low", sb))
  out <- rep(NA_character_, length(hl))
  ok <- !is.na(hl) & !is.na(sb) & hl %in% c("Low", "High") & sb %in% c("Low", "High")
  out[ok & hl == "Low"  & sb == "Low"]  <- "Q1"
  out[ok & hl == "High" & sb == "Low"]  <- "Q2"
  out[ok & hl == "Low"  & sb == "High"] <- "Q3"
  out[ok & hl == "High" & sb == "High"] <- "Q4"
  factor(out, levels = c("Q1", "Q2", "Q3", "Q4"))
}

#' 从命名向量/1 行表里取首个存在的列
.jin_pick_col <- function(df, candidates) {
  nm <- names(df)
  if (is.null(nm)) return(NULL)
  for (c in candidates) {
    hit <- which(tolower(nm) == tolower(c))
    if (length(hit)) return(nm[[hit[[1L]]]])
  }
  # 宽松：子串
  for (c in candidates) {
    hit <- grep(paste0("^", gsub("_", "[._]?", c), "$"), nm, ignore.case = TRUE, value = TRUE)
    if (length(hit)) return(hit[[1L]])
  }
  NULL
}

.jin_as01 <- function(x) {
  if (is.logical(x)) return(as.integer(x))
  if (is.factor(x)) {
    lv <- levels(x)
    return(as.integer(x == lv[[length(lv)]] | tolower(as.character(x)) %in% c("1", "yes", "dead", "expired", "true")))
  }
  xc <- tolower(trimws(as.character(x)))
  out <- rep(NA_integer_, length(xc))
  out[xc %in% c("1", "yes", "dead", "expired", "true", "y")] <- 1L
  out[xc %in% c("0", "no", "alive", "false", "n", "survived")] <- 0L
  num <- suppressWarnings(as.numeric(x))
  out[is.na(out) & is.finite(num)] <- as.integer(num[is.na(out) & is.finite(num)] == 1)
  out
}

.jin_horizon_core <- function(df, db = c("mimic", "eicu")) {
  db <- match.arg(tolower(as.character(db)[1L]), c("mimic", "eicu"))
  if (is.null(df)) stop("jin_horizon: df/surv_row 为空", call. = FALSE)
  if (is.atomic(df) && !is.null(names(df))) {
    df <- as.data.frame(as.list(df), stringsAsFactors = FALSE)
  }
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  n <- nrow(df)

  time_hosp_nm <- .jin_pick_col(df, c(
    "hosp_survival_day", "hosp_day", "hospital_los", "los_hospital",
    "Hosp_LOS", "survival_time_hosp", "futime_hosp", "fu_hosp_day"
  ))
  dead_hosp_nm <- .jin_pick_col(df, c(
    "is_hosp_dead", "hospital_expire_flag", "hospdischargestatus",
    "is_dead", "hospitalmortality", "inhospitalmortality", "fustatus"
  ))
  time_30_nm <- .jin_pick_col(df, c(
    "survival_time_30d", "surv_time_30d", "fu_day_30", "time_d30", "day30_time",
    "futime_30d", "fu_time_30d", "time_30d"
  ))
  event_30_nm <- .jin_pick_col(df, c(
    "death_within_hosp_30days", "death_within_30days", "death_30d",
    "mortality_30d", "event_d30", "event_30d", "surv_event_30d", "is_dead_30d"
  ))
  time_365_nm <- .jin_pick_col(df, c(
    "survival_time_365d", "surv_time_365d", "fu_day_365", "time_d365",
    "day365_time", "survival_time_1y", "futime_365d", "fu_time_365d", "time_365d"
  ))
  event_365_nm <- .jin_pick_col(df, c(
    "death_within_hosp_365days", "death_within_365days", "death_365d",
    "death_within_1year", "mortality_365d", "mortality_1y",
    "event_d365", "event_365d", "surv_event_365d", "is_dead_365d"
  ))
  # 长随访日历天（用于封顶 30/365）
  time_long_nm <- .jin_pick_col(df, c(
    "survival_day", "fu_day", "followup_days", "dod_ssn_day",
    "dead_time", "los_followup", time_hosp_nm
  ))

  t_hosp <- if (!is.null(time_hosp_nm)) suppressWarnings(as.numeric(df[[time_hosp_nm]])) else rep(NA_real_, n)
  e_hosp <- if (!is.null(dead_hosp_nm)) .jin_as01(df[[dead_hosp_nm]]) else rep(NA_integer_, n)
  # hospdischargestatus 文本
  if (!is.null(dead_hosp_nm) && all(is.na(e_hosp))) {
    xc <- tolower(as.character(df[[dead_hosp_nm]]))
    e_hosp <- as.integer(grepl("expir|dead|death", xc))
    e_hosp[!grepl("expir|dead|death|alive|surviv|home|discharg", xc)] <- NA_integer_
  }

  t_long <- if (!is.null(time_long_nm)) suppressWarnings(as.numeric(df[[time_long_nm]])) else t_hosp

  # 30d
  if (!is.null(event_30_nm)) {
    e30 <- .jin_as01(df[[event_30_nm]])
  } else if (!all(is.na(e_hosp)) && !all(is.na(t_long))) {
    e30 <- as.integer(!is.na(e_hosp) & e_hosp == 1L & is.finite(t_long) & t_long <= 30)
  } else {
    e30 <- rep(NA_integer_, n)
  }
  if (!is.null(time_30_nm)) {
    t30 <- suppressWarnings(as.numeric(df[[time_30_nm]]))
  } else {
    t30 <- pmin(t_long, 30)
    # 院内死亡早于出院：用院内时间与长随访较小者封顶
    if (!all(is.na(t_hosp))) t30 <- pmin(t30, pmin(t_hosp, 30), na.rm = FALSE)
  }

  # 365d
  if (!is.null(event_365_nm)) {
    e365 <- .jin_as01(df[[event_365_nm]])
  } else if (!all(is.na(e_hosp)) && !all(is.na(t_long))) {
    # 无显式 365 事件列时：仅当长随访可知才衍生；否则留 NA（勿用院内死亡冒充 1 年）
    if (!identical(time_long_nm, time_hosp_nm) || any(is.finite(t_long) & t_long > 30, na.rm = TRUE)) {
      e365 <- as.integer(!is.na(e_hosp) & e_hosp == 1L & is.finite(t_long) & t_long <= 365)
    } else {
      e365 <- rep(NA_integer_, n)
    }
  } else {
    e365 <- rep(NA_integer_, n)
  }
  if (!is.null(time_365_nm)) {
    t365 <- suppressWarnings(as.numeric(df[[time_365_nm]]))
  } else if (any(is.finite(t_long))) {
    t365 <- pmin(t_long, 365)
  } else {
    t365 <- rep(NA_real_, n)
  }

  # 主终点：院内死亡；时间至少 0.01
  futime <- t_hosp
  futime[!is.finite(futime) | futime <= 0] <- NA_real_
  futime[is.finite(futime) & futime < 0.01] <- 0.01
  fustatus <- e_hosp

  out <- data.frame(
    futime = futime,
    fustatus = as.integer(fustatus),
    event_d30 = as.integer(e30),
    time_d30 = as.numeric(t30),
    event_d365 = as.integer(e365),
    time_d365 = as.numeric(t365),
    stringsAsFactors = FALSE
  )
  out$time_d30[is.finite(out$time_d30) & out$time_d30 < 0.01] <- 0.01
  out$time_d365[is.finite(out$time_d365) & out$time_d365 < 0.01] <- 0.01
  attr(out, "jin_horizon_db") <- db
  attr(out, "jin_horizon_src") <- list(
    time_hosp = time_hosp_nm, event_hosp = dead_hosp_nm,
    time_30 = time_30_nm, event_30 = event_30_nm,
    time_365 = time_365_nm, event_365 = event_365_nm,
    time_long = time_long_nm
  )
  out
}

#' MIMIC survival 行/表 → 院内主终点 + 30d/365d 附列
jin_horizon_from_survival_mimic <- function(surv_row) {
  .jin_horizon_core(surv_row, db = "mimic")
}

#' eICU survival 行/表 → 同结构（列别名兼容 MIMIC 命名）
jin_horizon_from_survival_eicu <- function(surv_row) {
  .jin_horizon_core(surv_row, db = "eicu")
}

#' 在已有分析表上补齐 cox_multi_horizon 默认列名（time_d30/event_d30/…）
#'
#' 优先复制 dabiao 常见别名 futime_30d/event_30d；若仍缺则尝试 .jin_horizon_core 衍生。
#' 不覆盖已有非全 NA 的标准列。
jin_ensure_horizon_columns <- function(data, db = c("mimic", "eicu")) {
  if (is.null(data) || !is.data.frame(data) || !nrow(data)) return(data)
  db <- tryCatch(
    match.arg(tolower(as.character(db)[1L]), c("mimic", "eicu")),
    error = function(e) "mimic"
  )
  .copy_if_missing <- function(df, dest, srcs) {
    if (dest %in% names(df) && any(is.finite(suppressWarnings(as.numeric(df[[dest]]))))) {
      return(df)
    }
    for (s in srcs) {
      if (!s %in% names(df)) next
      df[[dest]] <- df[[s]]
      return(df)
    }
    df
  }
  data <- .copy_if_missing(
    data, "time_d30",
    c("futime_30d", "fu_time_30d", "time_30d", "survival_time_30d")
  )
  data <- .copy_if_missing(
    data, "event_d30",
    c("event_30d", "death_30d", "mortality_30d", "death_within_30days")
  )
  data <- .copy_if_missing(
    data, "time_d365",
    c("futime_365d", "fu_time_365d", "time_365d", "survival_time_365d")
  )
  data <- .copy_if_missing(
    data, "event_d365",
    c("event_365d", "death_365d", "mortality_365d", "death_within_365days")
  )
  need <- c("time_d30", "event_d30", "time_d365", "event_d365")
  if (!all(need %in% names(data)) ||
      any(vapply(need, function(nm) {
        !nm %in% names(data) || !any(is.finite(suppressWarnings(as.numeric(data[[nm]]))))
      }, logical(1L)))) {
    hz <- tryCatch(.jin_horizon_core(data, db = db), error = function(e) NULL)
    if (!is.null(hz) && is.data.frame(hz) && nrow(hz) == nrow(data)) {
      for (nm in need) {
        if ((!nm %in% names(data) ||
             !any(is.finite(suppressWarnings(as.numeric(data[[nm]]))))) &&
            nm %in% names(hz)) {
          data[[nm]] <- hz[[nm]]
        }
      }
    }
  }
  data
}

#' 课题目录助手
jin_project_dirs <- function(project_root) {
  root <- as.character(project_root %||% getwd())[1L]
  list(
    root = root,
    tables = file.path(root, "Tables"),
    figures = file.path(root, "Figures"),
    figures_pdf = file.path(root, "Figures", "pdf"),
    image_information = file.path(root, "Figures", "image_information"),
    reports = file.path(root, "reports"),
    checkpoints = file.path(root, "checkpoints"),
    by_index = file.path(root, "by_index"),
    summary_results = file.path(root, "summary_results")
  )
}

jin_ensure_dirs <- function(dirs) {
  paths <- unlist(dirs, use.names = FALSE)
  for (p in unique(as.character(paths))) {
    if (nzchar(p) && !dir.exists(p)) dir.create(p, recursive = TRUE, showWarnings = FALSE)
  }
  invisible(dirs)
}
