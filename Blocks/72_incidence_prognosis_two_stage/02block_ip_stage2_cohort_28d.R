# ip_stage2_cohort_28d — AKI 阳性亚队列 + 预后 CSV + 规则 C 时间零点 + 28 天行政截尾
###############################################################################
#
#  register_block: "ip_stage2_cohort_28d"
#  典型流水线: Stage1 发病链 → ip_stage2_cohort_28d → Stage2 预后链（cox/KM/rcs…）
#
#  依据: docs/superpowers/specs/2026-08-26-sle-aki-incidence-prognosis-two-stage-design.md §4.4
#  时间零点规则 C: aki_time（若有非缺失）否则 icu_intime
#  28d: futime=min(t,28); fustatus=1 iff 死亡且 t≤28
#
#  require_config = config$ip_two_stage$prognosis_path
#  require_data   = ctx$data$imputed %||% ctx$data$locked %||% ctx$data$cleaned
#
#  # ── 配置 config$ip_two_stage ──────────────────────────────────────────────
#  ip_two_stage = list(
#    prognosis_path     = ".../data/mimic/mimic预后数据-all.csv",
#    baseline_id_col    = "ID",
#    prognosis_id_col   = "subject_id",
#    aki_time_col       = "aki_time",
#    icu_intime_col     = "icu_intime",
#    dead_time_col      = "dead_time",
#    dead_col           = "is_dead",
#    last_followup_cols = c("disch_time", "icu_outtime")
#  ),
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  读: Stage1 分析集（含 Disease / AKI 阳性）
#  写: ctx$data$stage2（并覆写 imputed 子集）列 futime / fustatus
#      ctx$results$ip_stage2_timezero_source ∈ aki_onset|icu_intime
#      ctx$config$project$study_type = "prognosis"
#      ctx$config$data$outcome_column / survival$time_var / event_var
###############################################################################

local({
  if (exists("ip_admin_censor_28", mode = "function")) return(invisible())
  of <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
  cands <- character(0)
  if (!is.null(of) && nzchar(of)) {
    cands <- c(cands, file.path(
      dirname(normalizePath(of, winslash = "/", mustWork = FALSE)),
      "00ip_common.R"
    ))
  }
  cands <- c(
    cands,
    file.path(getwd(), "Blocks/72_incidence_prognosis_two_stage/00ip_common.R")
  )
  p <- cands[file.exists(cands)][1L]
  if (length(p) && !is.na(p) && nzchar(p)) source(p, local = FALSE)
})

.ip72_s2_id_chr <- function(x) {
  x <- trimws(as.character(x))
  x[is.na(x) | !nzchar(x) | x %in% c("NA", "NaN", "<NA>")] <- NA_character_
  sub("\\.0+$", "", x)
}

.ip72_s2_yes01 <- function(x) {
  if (is.null(x)) return(integer(0))
  if (is.logical(x)) return(as.integer(x %in% TRUE))
  if (is.numeric(x) && !is.factor(x)) return(as.integer(!is.na(x) & x == 1))
  xc <- tolower(trimws(as.character(x)))
  yes <- xc %in% c("yes", "y", "1", "true", "sle", "aki", "arf")
  yes[grepl("^no(\\s|$|_)", xc)] <- FALSE
  as.integer(yes)
}

.ip72_s2_parse_dt <- function(x) {
  n <- if (is.null(x)) 0L else length(x)
  na_out <- function(n) {
    as.POSIXct(rep(NA_real_, n), origin = "1970-01-01", tz = "UTC")
  }
  if (n == 0L) return(na_out(0L))
  if (inherits(x, "POSIXt")) return(as.POSIXct(x))
  if (inherits(x, "Date")) return(as.POSIXct(as.character(x), tz = "UTC"))
  xc <- trimws(as.character(x))
  xc[is.na(x) | !nzchar(xc) | xc %in% c("NA", "NaN", "<NA>", "NULL")] <- NA_character_
  if (all(is.na(xc))) return(na_out(n))
  fmt <- c(
    "%Y-%m-%d %H:%M:%S",
    "%Y-%m-%d %H:%M",
    "%Y-%m-%d",
    "%d/%m/%Y %H:%M:%S",
    "%d/%m/%Y %H:%M",
    "%d/%m/%Y"
  )
  suppressWarnings(as.POSIXct(xc, tz = "UTC", tryFormats = fmt))
}

.ip72_s2_coalesce_dt <- function(...) {
  args <- list(...)
  args <- args[!vapply(args, is.null, logical(1))]
  if (!length(args)) return(.ip72_s2_parse_dt(character(0)))
  out <- args[[1L]]
  if (length(args) == 1L) return(out)
  for (i in seq_along(args)[-1L]) {
    miss <- is.na(out)
    if (!any(miss)) break
    nxt <- args[[i]]
    if (length(nxt) != length(out)) next
    out[miss] <- nxt[miss]
  }
  out
}

.ip72_s2_require_file <- function(path, label) {
  path <- as.character(path %||% "")[1L]
  if (!nzchar(path) || !file.exists(path)) {
    stop("ip_stage2_cohort_28d: ", label, " 无效或不存在: ", path, call. = FALSE)
  }
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

.ip72_s2_pick_data <- function(ctx) {
  for (nm in c("imputed", "locked", "cleaned")) {
    d <- ctx$data[[nm]]
    if (is.data.frame(d) && nrow(d) >= 1L) return(d)
  }
  stop("ip_stage2_cohort_28d: 需要 ctx$data$imputed（或 locked / cleaned）", call. = FALSE)
}

.ip72_s2_aki_keep <- function(d, cfg = NULL) {
  if ("Disease" %in% names(d)) {
    if (!is.null(cfg) && exists("pipeline_outcome_as_01", mode = "function")) {
      return(pipeline_outcome_as_01(d$Disease, cfg) == 1)
    }
    return(.ip72_s2_yes01(d$Disease) == 1L)
  }
  if ("Acute_Renal_Failure" %in% names(d)) {
    return(.ip72_s2_yes01(d$Acute_Renal_Failure) == 1L)
  }
  stop("ip_stage2_cohort_28d: 分析集无 Disease / Acute_Renal_Failure，无法筛 AKI 阳性",
       call. = FALSE)
}

block_ip_stage2_cohort_28d <- function(ctx, ...) {
  if (!exists("ip_admin_censor_28", mode = "function")) {
    stop("ip_stage2_cohort_28d: 缺少 ip_admin_censor_28（00ip_common.R）", call. = FALSE)
  }
  cfg <- ctx$config$ip_two_stage
  if (is.null(cfg) || !is.list(cfg)) {
    stop("ip_stage2_cohort_28d: 缺少 config$ip_two_stage", call. = FALSE)
  }

  d <- .ip72_s2_pick_data(ctx)
  if (all(c("futime", "fustatus") %in% names(d)) &&
      any(is.finite(suppressWarnings(as.numeric(d$futime)))) &&
      nrow(d) >= 1L) {
    cli::cli_alert_info(
      "ip_stage2_cohort_28d: 已有 futime/fustatus（n={nrow(d)}），跳过重复筛队"
    )
    ctx$data$stage2 <- d
    ctx$config$project$study_type <- "prognosis"
    ctx$config$data$outcome_column <- "fustatus"
    ctx$config$survival$time_var <- "futime"
    ctx$config$survival$event_var <- "fustatus"
    return(ctx)
  }
  n_in <- nrow(d)
  keep <- .ip72_s2_aki_keep(d, ctx$config)
  d2 <- d[keep, , drop = FALSE]
  n_aki <- nrow(d2)
  if (n_aki < 1L) {
    stop("ip_stage2_cohort_28d: Disease==1 / AKI 阳性亚队列为空", call. = FALSE)
  }

  prog_path <- .ip72_s2_require_file(cfg$prognosis_path, "prognosis_path")
  prog <- utils::read.csv(prog_path, stringsAsFactors = FALSE, check.names = FALSE)

  id_bl <- as.character(cfg$baseline_id_col %||% "ID")[1L]
  id_pg <- as.character(cfg$prognosis_id_col %||% "subject_id")[1L]
  if (!id_bl %in% names(d2)) {
    alt <- intersect(c("ID", "subject_id"), names(d2))[1L]
    if (is.na(alt) || !nzchar(alt)) {
      stop("ip_stage2_cohort_28d: 分析集无并键列 ", id_bl, call. = FALSE)
    }
    id_bl <- alt
  }
  if (!id_pg %in% names(prog)) {
    stop("ip_stage2_cohort_28d: 预后 CSV 无列 ", id_pg, call. = FALSE)
  }

  d2$.ip72_join <- .ip72_s2_id_chr(d2[[id_bl]])
  prog$.ip72_join <- .ip72_s2_id_chr(prog[[id_pg]])
  if (anyDuplicated(prog$.ip72_join[!is.na(prog$.ip72_join)])) {
    cli::cli_alert_warning("ip_stage2_cohort_28d: 预后 CSV 并键不唯一，保留首行")
    prog <- prog[!is.na(prog$.ip72_join) & !duplicated(prog$.ip72_join), , drop = FALSE]
  }

  aki_col  <- as.character(cfg$aki_time_col %||% "aki_time")[1L]
  icu_col  <- as.character(cfg$icu_intime_col %||% "icu_intime")[1L]
  dead_t_col <- as.character(cfg$dead_time_col %||% "dead_time")[1L]
  dead_col <- as.character(cfg$dead_col %||% "is_dead")[1L]
  last_cols <- cfg$last_followup_cols %||% c("disch_time", "icu_outtime")
  last_cols <- as.character(last_cols)
  bring <- unique(c(
    ".ip72_join", icu_col, dead_t_col, dead_col, aki_col, last_cols,
    "hosp_survival_day", "is_hosp_dead", "death_within_hosp_28days"
  ))
  bring <- intersect(bring, names(prog))
  # 分析集已有的同名时间列保留；预后侧用后缀补缺失
  already <- setdiff(intersect(names(d2), setdiff(bring, ".ip72_join")), character(0))
  prog_small <- prog[, bring, drop = FALSE]
  if (length(already)) {
    ren <- already
    names(prog_small)[match(ren, names(prog_small), nomatch = 0L)] <-
      paste0(ren[ren %in% names(prog_small)], "_prog")
  }

  merged <- merge(d2, prog_small, by = ".ip72_join", all.x = TRUE, sort = FALSE)
  .col <- function(primary, fallback = NULL) {
    if (primary %in% names(merged)) return(merged[[primary]])
    fb <- fallback %||% paste0(primary, "_prog")
    if (fb %in% names(merged)) return(merged[[fb]])
    NULL
  }
  .col_prefer <- function(nm) {
    a <- .col(nm)
    b <- .col(paste0(nm, "_prog"))
    if (is.null(a) && is.null(b)) return(NULL)
    if (is.null(b)) return(a)
    if (is.null(a)) return(b)
    miss <- is.na(a) | (is.character(a) & !nzchar(trimws(as.character(a))))
    a[miss] <- b[miss]
    a
  }

  aki_raw <- .col_prefer(aki_col)
  icu_raw <- .col_prefer(icu_col)
  dead_t_raw <- .col_prefer(dead_t_col)
  dead_raw <- .col_prefer(dead_col)
  last_list <- lapply(last_cols, function(nm) {
    raw <- .col_prefer(nm)
    if (is.null(raw)) return(NULL)
    .ip72_s2_parse_dt(raw)
  })

  aki_dt <- if (is.null(aki_raw)) NULL else .ip72_s2_parse_dt(aki_raw)
  icu_dt <- if (is.null(icu_raw)) NULL else .ip72_s2_parse_dt(icu_raw)
  if (is.null(icu_dt)) {
    stop("ip_stage2_cohort_28d: 合并后无 ", icu_col, "，无法确定时间零点", call. = FALSE)
  }

  used_aki <- !is.null(aki_dt) && any(!is.na(aki_dt))
  if (isTRUE(used_aki)) {
    t0 <- .ip72_s2_coalesce_dt(aki_dt, icu_dt)
    tz_src <- "aki_onset"
  } else {
    t0 <- icu_dt
    tz_src <- "icu_intime"
  }

  dead01 <- if (is.null(dead_raw)) {
    rep(0L, nrow(merged))
  } else {
    .ip72_s2_yes01(dead_raw)
  }
  dead_dt <- if (is.null(dead_t_raw)) {
    .ip72_s2_parse_dt(rep(NA_character_, nrow(merged)))
  } else {
    .ip72_s2_parse_dt(dead_t_raw)
  }
  last_dt <- do.call(.ip72_s2_coalesce_dt, c(last_list, list(dead_dt)))
  alive <- is.na(dead01) | dead01 != 1L
  end_dt <- dead_dt
  end_dt[alive] <- last_dt[alive]
  still_na <- is.na(end_dt)
  if (any(still_na)) end_dt[still_na] <- last_dt[still_na]

  t_days <- as.numeric(difftime(end_dt, t0, units = "days"))
  hs <- if ("hosp_survival_day" %in% names(merged)) {
    suppressWarnings(as.numeric(merged$hosp_survival_day))
  } else {
    rep(NA_real_, nrow(merged))
  }
  fb <- is.na(t_days) & is.finite(hs) & hs >= 0
  if (any(fb)) t_days[fb] <- hs[fb]

  cen <- ip_admin_censor_28(t_days, dead01)
  merged$futime <- as.numeric(cen$futime)
  merged$fustatus <- as.integer(cen$fustatus)

  ok <- is.finite(merged$futime) & merged$futime >= 0
  n_drop <- as.integer(sum(!ok))
  if (n_drop > 0L) {
    cli::cli_alert_warning(
      "ip_stage2_cohort_28d: 剔除 futime 缺失/非法 {n_drop} 人（原 AKI={n_aki}）"
    )
    merged <- merged[ok, , drop = FALSE]
  }
  if (nrow(merged) < 1L) {
    stop("ip_stage2_cohort_28d: 28 天随访可算样本为空", call. = FALSE)
  }

  merged$.ip72_join <- NULL
  drop_prog_sfx <- grep("_prog$", names(merged), value = TRUE)
  if (length(drop_prog_sfx)) {
    merged[drop_prog_sfx] <- NULL
  }

  if (is.null(ctx$config$project) || !is.list(ctx$config$project)) {
    ctx$config$project <- list()
  }
  ctx$config$project$study_type <- "prognosis"
  if (is.null(ctx$config$data) || !is.list(ctx$config$data)) {
    ctx$config$data <- list()
  }
  ctx$config$data$outcome_column <- "fustatus"
  if (is.null(ctx$config$survival) || !is.list(ctx$config$survival)) {
    ctx$config$survival <- list()
  }
  ctx$config$survival$time_var <- "futime"
  ctx$config$survival$event_var <- "fustatus"

  ctx$data$stage2 <- merged
  ctx$data$imputed <- merged
  if (is.data.frame(ctx$data$locked)) ctx$data$locked <- merged
  if (is.data.frame(ctx$data$cleaned)) ctx$data$cleaned <- merged

  ctx$results$ip_stage2_timezero_source <- tz_src
  n_event <- as.integer(sum(merged$fustatus == 1L, na.rm = TRUE))
  ctx$results$ip_stage2 <- list(
    n_stage1 = n_in,
    n_aki = n_aki,
    n_stage2 = nrow(merged),
    n_event = n_event,
    n_dropped_time = n_drop,
    timezero_source = tz_src
  )

  cli::cli_alert_success(
    "ip_stage2_cohort_28d: Stage1={n_in} → AKI={n_aki} → stage2={nrow(merged)} (28d events={n_event}; t0={tz_src})"
  )
  ctx
}

register_block("ip_stage2_cohort_28d", block_ip_stage2_cohort_28d,
               "AKI亚队列 28天行政截尾预后分析集")
