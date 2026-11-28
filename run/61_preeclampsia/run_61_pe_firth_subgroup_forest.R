#!/usr/bin/env Rscript
# 稀有事件结局：Firth 亚组森林图（不覆盖原 GLM 图，文件名加 _Firth）
# 结局：Preterm34, Apgar1_lt8, Apgar5_lt8, Newborn_lt1500, Newborn_lt2000
# 口径：与现有 subgroup_incidence 一致（Crude；Disease 保留三水平；Non-PE 参照）
#
# Rscript run/61_preeclampsia/run_61_pe_firth_subgroup_forest.R

`%||%` <- function(a, b) if (!is.null(a)) a else b

.root <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    sp <- normalizePath(dirname(sub("^--file=", "", f[1L])), winslash = "/")
    if (basename(sp) == "61_preeclampsia" && basename(dirname(sp)) == "run") {
      return(normalizePath(file.path(sp, "..", ".."), winslash = "/"))
    }
  }
  normalizePath(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd()), winslash = "/")
}

.root_dir <- .root()
setwd(.root_dir)
source(file.path(.root_dir, "R/utils.R"))
source(file.path(.root_dir, "R/subgroup_vars.R"))
source(file.path(.root_dir, "R/subgroup_forest_plot.R"))
source(file.path(.root_dir, "run/61_preeclampsia/pe_pre_bmi_group.R"))
source("/mnt/g/02block_result/61_Preeclampsia/configs/config_61_preeclampsia_batch.R")
suppressPackageStartupMessages({
  if (!requireNamespace("logistf", quietly = TRUE)) stop("需要 logistf", call. = FALSE)
  if (!requireNamespace("forestploter", quietly = TRUE)) stop("需要 forestploter", call. = FALSE)
  library(forestploter)
  library(grid)
})

out_base <- config$project$output_dir
ck_shared <- pipeline_shared$checkpoint$dir
ck <- file.path(ck_shared, "multicollinearity_screen.rds")
if (!file.exists(ck)) ck <- file.path(ck_shared, "step08_multicollinearity_screen.rds")
obj <- readRDS(ck)
ctx0 <- if (!is.null(obj$ctx)) obj$ctx else obj
imp0 <- as.data.frame(ctx0$data$imputed %||% ctx0$data$cleaned)

id <- as.character(config$data$id_column %||% "Admission_Num")[1L]
env <- new.env(parent = emptyenv())
load(config$data$rawdata_path, envir = env)
raw <- as.data.frame(env[[config$data$rawdata_obj]])
nw <- suppressWarnings(as.numeric(sub("/.*$", "", trimws(as.character(raw$Newborn_Weight)))))
nw[is.finite(nw) & nw <= 0] <- NA_real_
raw$Newborn_Weight_g <- nw
raw$Newborn_lt1500 <- as.integer(is.finite(nw) & nw < 1500)
raw$Newborn_lt2000 <- as.integer(is.finite(nw) & nw < 2000)
raw$APGAR_1min <- suppressWarnings(as.numeric(as.character(raw$APGAR_1min)))
raw$APGAR_5min <- suppressWarnings(as.numeric(as.character(raw$APGAR_5min)))
raw$Apgar1_lt8 <- as.integer(is.finite(raw$APGAR_1min) & raw$APGAR_1min < 8)
raw$Apgar5_lt8 <- as.integer(is.finite(raw$APGAR_5min) & raw$APGAR_5min < 8)
keep <- intersect(
  c(id, "Newborn_lt1500", "Newborn_lt2000", "Apgar1_lt8", "Apgar5_lt8"),
  names(raw)
)
map <- raw[, keep, drop = FALSE]
map[[id]] <- as.character(map[[id]])
imp0[[id]] <- as.character(imp0[[id]])
for (cn in setdiff(keep, id)) imp0[[cn]] <- NULL
imp0 <- merge(imp0, map, by = id, all.x = TRUE, sort = FALSE)

.get_imp_list <- function(ctx, imp0) {
  mm <- ctx$results$mice_model
  # mice 内 Age/Pre_BMI 等可能为标准化尺度；切组须用原始尺度
  protect <- c(
    "Age", "Age_Group", "Age_Years",
    "Pre_BMI", "Pre_BMI_subg", "Pre_BMI_Group",
    "GDM", "GDM01"
  )
  if (!is.null(mm) && inherits(mm, "mids") && nrow(mm$data) == nrow(imp0)) {
    m <- as.integer(mm$m)
    out <- vector("list", m)
    for (i in seq_len(m)) {
      comp <- as.data.frame(mice::complete(mm, i))
      di <- imp0
      for (cn in names(comp)) {
        if (cn %in% protect) next
        if (cn %in% names(di) && nrow(comp) == nrow(di)) di[[cn]] <- comp[[cn]]
      }
      out[[i]] <- di
    }
    return(out)
  }
  list(imp0)
}

# 先按原始 Age 建 Age_Group，再叠 mice（保护 Age）
age_cut0 <- as.numeric((config$subgroup %||% list())$age_cutoff %||% 35)[1L]
if (!is.finite(age_cut0)) age_cut0 <- 35
imp0 <- local({
  age_lo <- paste0("< ", age_cut0)
  age_hi <- paste0("\u2265 ", age_cut0)
  if ("Age" %in% names(imp0)) {
    imp0$Age_Group <- ifelse(
      suppressWarnings(as.numeric(imp0$Age)) < age_cut0, age_lo, age_hi
    )
    imp0$Age_Group <- factor(imp0$Age_Group, levels = c(age_lo, age_hi))
  }
  imp0
})
imp_list <- .get_imp_list(ctx0, imp0)
cli::cli_alert_info(
  "Firth 亚组使用 {length(imp_list)} 套插补；Age_Group: {paste(names(table(imp0$Age_Group)), '=', as.integer(table(imp0$Age_Group)), collapse = ', ')}"
)

.levels_dis <- c(
  "Non-preeclampsia",
  "Preeclampsia",
  "Chronic hypertension with preeclampsia"
)
.pe_key <- "DiseasePreeclampsia"
.ch_key <- "DiseaseChronic hypertension with preeclampsia"

.y01 <- function(d, oc) {
  y <- d[[oc]]
  if (identical(oc, "Preterm34")) {
    return(as.integer(as.character(y) == "Preterm34"))
  }
  as.integer(as.numeric(y) == 1)
}

.prep_frame <- function(d, oc) {
  y <- .y01(d, oc)
  dis <- factor(as.character(d$Disease), levels = .levels_dis)
  df <- data.frame(y = y, Disease = dis, stringsAsFactors = FALSE)
  # 透传亚组列
  for (cn in setdiff(names(d), c("y", "Disease"))) {
    df[[cn]] <- d[[cn]]
  }
  df <- df[is.finite(df$y) & !is.na(df$Disease), , drop = FALSE]
  df$Disease <- factor(as.character(df$Disease), levels = .levels_dis)
  df
}

.fmt_p <- function(p) {
  p <- suppressWarnings(as.numeric(p)[1L])
  if (!is.finite(p)) return("")
  if (p < 0.001) return("<0.001")
  formatC(round(p, 3), format = "f", digits = 3)
}

.pretty <- function(x) {
  if (exists("subgroup_pretty_label", mode = "function")) {
    return(subgroup_pretty_label(x))
  }
  gsub("_", " ", as.character(x), fixed = TRUE)
}

.extract_disease_terms <- function(fit) {
  rn <- names(fit$coefficients)
  out <- list()
  for (nm in c(.pe_key, .ch_key)) {
    if (identical(nm, .pe_key)) {
      hit <- which(
        grepl("preeclampsia", rn, ignore.case = TRUE) &
          !grepl("chronic", rn, ignore.case = TRUE) &
          grepl("^Disease", rn)
      )
    } else {
      hit <- which(
        grepl("chronic", rn, ignore.case = TRUE) &
          grepl("preeclampsia", rn, ignore.case = TRUE)
      )
    }
    if (!length(hit)) {
      out[[nm]] <- NULL
      next
    }
    i <- hit[[1L]]
    b <- unname(fit$coefficients[[i]])
    se <- NA_real_
    v <- fit$var
    if (!is.null(v) && is.matrix(v) && nrow(v) >= i) se <- sqrt(max(v[i, i], 0))
    if (!is.finite(se) || se <= 0) {
      lo <- unname(fit$ci.lower[[i]])
      hi <- unname(fit$ci.upper[[i]])
      if (is.finite(lo) && is.finite(hi) && hi > lo) se <- (hi - lo) / (2 * 1.96)
    }
    p <- unname(fit$prob[[i]])
    if (!is.finite(b) || !is.finite(se) || se <= 0) {
      out[[nm]] <- NULL
      next
    }
    out[[nm]] <- c(b = b, se = se, p = if (is.finite(p)) p else NA_real_)
  }
  out
}

.pool_terms <- function(term_list) {
  # term_list: list of named lists from .extract_disease_terms
  out <- list()
  for (nm in c(.pe_key, .ch_key)) {
    mats <- list()
    for (tl in term_list) {
      if (is.null(tl) || is.null(tl[[nm]])) next
      mats[[length(mats) + 1L]] <- tl[[nm]]
    }
    if (!length(mats)) {
      out[[nm]] <- list(or = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_)
      next
    }
    B <- vapply(mats, function(z) z[["b"]], numeric(1))
    SE <- vapply(mats, function(z) z[["se"]], numeric(1))
    m <- length(B)
    qbar <- mean(B)
    ubar <- mean(SE^2)
    bvar <- if (m > 1L) stats::var(B) else 0
    if (!is.finite(bvar)) bvar <- 0
    Tvar <- ubar + (1 + 1 / m) * bvar
    se_p <- sqrt(max(Tvar, 0))
    z <- if (se_p > 0) qbar / se_p else NA_real_
    p <- if (is.finite(z)) 2 * stats::pnorm(-abs(z)) else NA_real_
    out[[nm]] <- list(
      or = exp(qbar),
      lo = exp(qbar - 1.96 * se_p),
      hi = exp(qbar + 1.96 * se_p),
      p = p
    )
  }
  out
}

.fit_firth_disease <- function(df) {
  if (nrow(df) < 20L || length(unique(df$y)) < 2L) return(NULL)
  if (nlevels(droplevels(df$Disease)) < 2L) return(NULL)
  fit <- tryCatch(
    logistf::logistf(y ~ Disease, data = df, pl = TRUE),
    error = function(e) e
  )
  if (inherits(fit, "error")) return(NULL)
  fit
}

.interaction_p_firth <- function(df, sv) {
  if (!sv %in% names(df)) return("")
  d <- df[!is.na(df[[sv]]), , drop = FALSE]
  d[[sv]] <- droplevels(factor(as.character(d[[sv]])))
  if (nlevels(d[[sv]]) < 2L || nrow(d) < 30L || length(unique(d$y)) < 2L) {
    return("")
  }
  f0 <- tryCatch(
    logistf::logistf(
      stats::as.formula(paste0("y ~ Disease + `", sv, "`")),
      data = d, pl = FALSE
    ),
    error = function(e) e
  )
  f1 <- tryCatch(
    logistf::logistf(
      stats::as.formula(paste0("y ~ Disease * `", sv, "`")),
      data = d, pl = FALSE
    ),
    error = function(e) e
  )
  if (inherits(f0, "error") || inherits(f1, "error")) return("")

  # logistf::anova(full, reduced) → list(chisq, df, pval, ...)
  an <- tryCatch(stats::anova(f1, f0), error = function(e) NULL)
  if (!is.null(an)) {
    pv <- suppressWarnings(as.numeric(an$pval %||% an$P %||% an$`P-value`)[1L])
    if (is.finite(pv)) return(.fmt_p(pv))
  }

  # 回退：drop1 交互项行
  dr <- tryCatch(stats::drop1(f1, test = "Chisq"), error = function(e) NULL)
  if (!is.null(dr) && NROW(dr) > 0L) {
    rn <- rownames(dr)
    hit <- grep(paste0(":", sv, "$|:", gsub("`", "", sv), "$"), rn)
    if (!length(hit)) hit <- grep(":", rn)
    if (length(hit)) {
      pcol <- intersect(c("P-value", "Pr(>Chi)", "p.value"), names(dr))
      if (!length(pcol) && !is.null(colnames(dr))) {
        pcol <- grep("^P|Pr\\(", colnames(dr), value = TRUE)
      }
      if (length(pcol)) {
        pv <- suppressWarnings(as.numeric(dr[hit[[1L]], pcol[[1L]]])[1L])
        if (is.finite(pv)) return(.fmt_p(pv))
      }
    }
  }
  ""
}

.empty_row <- function(variable = "", count = NA_real_, percent = NA_real_,
                       levels = "", or = NA_real_, lo = NA_real_, hi = NA_real_,
                       pv = "", pint = "") {
  data.frame(
    Variable = variable,
    Count = count,
    Percent = percent,
    Levels = levels,
    `Point Estimate` = or,
    Lower = lo,
    Upper = hi,
    `P value` = pv,
    `P for interaction` = pint,
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
}

.term_to_row <- function(pooled, key, levels_lab) {
  r <- pooled[[key]]
  if (is.null(r)) {
    return(.empty_row(levels = levels_lab))
  }
  .empty_row(
    levels = levels_lab,
    or = r$or, lo = r$lo, hi = r$hi,
    pv = .fmt_p(r$p)
  )
}

.ensure_age_group <- function(d, age_cut = 35) {
  if ("Age" %in% names(d)) {
    age_lo <- paste0("< ", age_cut)
    age_hi <- paste0("\u2265 ", age_cut)
    d$Age_Group <- ifelse(
      suppressWarnings(as.numeric(d$Age)) < age_cut, age_lo, age_hi
    )
    d$Age_Group <- factor(d$Age_Group, levels = c(age_lo, age_hi))
  }
  d
}

.resolve_subgroup_vars <- function(oc, d, sub_cfg) {
  req <- as.character(sub_cfg$required_subgroup_vars %||% character(0))
  excl <- as.character(sub_cfg$exclude_vars %||% character(0))
  outcome_like <- c(
    "GDM01", "Preterm34", "Preterm_delivery",
    "Cesarean01", "Apgar1_lt8", "Apgar5_lt8", "Newborn_lt1500", "Newborn_lt2000",
    "PE01", "Delivery_Mode", "Newborn_Weight_g", "APGAR_1min", "APGAR_5min"
  )
  excl <- unique(c(excl, setdiff(outcome_like, "Preterm_delivery"), oc, "GDM01"))
  excl <- setdiff(excl, "GDM")
  # 早产结局本身不宜再用 Preterm_delivery 分层
  if (identical(oc, "Preterm34")) {
    excl <- unique(c(excl, "Preterm_delivery"))
    req <- setdiff(req, "Preterm_delivery")
  } else if (!"Preterm_delivery" %in% req) {
    req <- c(req, "Preterm_delivery")
  }
  # GDM 结局下不放 GDM 分层
  if (oc %in% c("GDM01", "GDM")) {
    excl <- unique(c(excl, "GDM", "GDM01"))
    req <- setdiff(req, c("GDM", "GDM01"))
  } else if (!"GDM" %in% req) {
    req <- c(req, "GDM")
  }
  # 统一用 Pre_BMI_Group（中国标准）
  req <- setdiff(req, c("Pre_BMI", "Pre_BMI_subg"))
  if (!"Pre_BMI_Group" %in% req) req <- c(req, "Pre_BMI_Group")
  req <- setdiff(req, c(excl, oc))
  # Age → Age_Group；若数据已建 Age_Group 则强制纳入
  req <- unique(ifelse(req %in% c("Age", "Age_Years"), "Age_Group", req))
  if ("Age_Group" %in% names(d) && !"Age_Group" %in% req) {
    req <- c("Age_Group", req)
  }
  req <- req[req %in% names(d)]
  ok <- vapply(req, function(v) {
    x <- d[[v]]
    nu <- length(unique(stats::na.omit(as.character(x))))
    nu >= 2L
  }, logical(1))
  out <- req[ok]
  if (!length(out) && "Age_Group" %in% names(d)) {
    cli::cli_alert_warning("亚组变量筛选后为空；Age_Group 水平数={length(unique(stats::na.omit(as.character(d$Age_Group))))}")
  }
  out
}

.bmi_stratum_estimable_rate <- function(res) {
  if (is.null(res) || !nrow(res)) return(NA_real_)
  # Pre_BMI_Group 段：水平行后的 Disease=PE/CH 对比
  v <- trimws(as.character(res$Variable %||% ""))
  lev <- trimws(as.character(res$Levels %||% ""))
  bmi_lv <- c("<18.5", "18.5-23.9", "24.0-27.9", "\u226528.0", "<24.0")
  # 找 Pre_BMI_Group 标题后直到下一标题
  hdr <- which(grepl("Pre.?BMI|Pre-pregnancy BMI", v, ignore.case = TRUE) & !nzchar(lev))
  if (!length(hdr)) {
    # 也可能 pretty 后叫 Pre BMI Group
    hdr <- which(v %in% c("Pre BMI Group", "Pre_BMI_Group", "Pre-pregnancy BMI") & !nzchar(lev))
  }
  # 退化：按 BMI 水平标签识别
  is_bmi_level <- v %in% bmi_lv | grepl("^<18\\.5|^18\\.5|^24\\.0|^<24|^≥28|^\\\\u226528", v)
  is_contrast <- grepl("Disease=.*[Pp]reeclampsia", lev) &
    !grepl("Non-preeclampsia", lev, ignore.case = TRUE)
  # 对比行 Variable 常为空，Levels 有 Disease=
  # 用：紧跟 BMI 水平行之后的空 Variable + Disease 对比
  pick <- integer(0)
  for (i in seq_len(nrow(res))) {
    if (is_bmi_level[[i]] || (nzchar(v[[i]]) && v[[i]] %in% bmi_lv)) {
      j <- i + 1L
      while (j <= nrow(res) && !nzchar(trimws(v[[j]])) && grepl("^Disease=", lev[[j]])) {
        if (!grepl("Non-preeclampsia", lev[[j]], ignore.case = TRUE)) {
          pick <- c(pick, j)
        }
        j <- j + 1L
      }
    }
  }
  if (!length(pick)) return(NA_real_)
  or <- suppressWarnings(as.numeric(res$`Point Estimate`[pick]))
  mean(is.finite(or) & or > 0)
}

.find_fig_dir <- function(oc) {
  base <- file.path(out_base, "by_outcome", oc)
  cands <- list.files(base, pattern = "step[0-9]+_subgroup_incidence$", full.names = TRUE)
  if (length(cands)) {
    step_n <- suppressWarnings(as.integer(sub(".*step([0-9]+)_.*", "\\1", basename(cands))))
    best <- cands[order(ifelse(is.na(step_n), -1L, step_n), decreasing = TRUE)][1]
    d <- file.path(best, "Figures")
    if (!dir.exists(d)) dir.create(d, recursive = TRUE)
    td <- file.path(best, "Tables")
    if (!dir.exists(td)) dir.create(td, recursive = TRUE)
    return(list(figures = d, tables = td, step = best))
  }
  d <- file.path(base, "step99_subgroup_incidence_Firth", "Figures")
  td <- file.path(base, "step99_subgroup_incidence_Firth", "Tables")
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  dir.create(td, recursive = TRUE, showWarnings = FALSE)
  list(figures = d, tables = td, step = dirname(d))
}

.build_firth_subgroup_table <- function(oc, frames, sg_vars, age_cut = 35) {
  frames <- lapply(frames, function(d) {
    d <- .ensure_age_group(d, age_cut)
    .prep_frame(d, oc)
  })
  total_n <- nrow(frames[[1]])

  # Overall
  overall_terms <- lapply(frames, function(df) {
    fit <- .fit_firth_disease(df)
    if (is.null(fit)) return(NULL)
    .extract_disease_terms(fit)
  })
  overall_pool <- .pool_terms(overall_terms)

  rows <- list(
    .term_to_row(overall_pool, .pe_key, "Disease=Preeclampsia"),
    .term_to_row(overall_pool, .ch_key, "Disease=Chronic hypertension with preeclampsia")
  )

  for (sv in sg_vars) {
    # interaction P：各套取中位数
    pints <- vapply(frames, function(df) {
      .interaction_p_firth(df, sv)
    }, character(1))
    pints_num <- suppressWarnings(as.numeric(gsub("^<", "", pints)))
    pint <- if (any(is.finite(pints_num))) {
      .fmt_p(stats::median(pints_num[is.finite(pints_num)]))
    } else {
      ""
    }
    rows[[length(rows) + 1L]] <- .empty_row(
      variable = .pretty(sv), pint = pint
    )

    lv <- levels(droplevels(factor(as.character(frames[[1]][[sv]]))))
    lv <- lv[lv %in% unique(as.character(stats::na.omit(frames[[1]][[sv]])))]
    for (l in lv) {
      n_l <- sum(as.character(frames[[1]][[sv]]) == l, na.rm = TRUE)
      pct <- round(100 * n_l / total_n, 1)
      rows[[length(rows) + 1L]] <- .empty_row(
        variable = as.character(l),
        count = n_l,
        percent = pct,
        levels = "Disease=Non-preeclampsia"
      )
      stratum_terms <- lapply(frames, function(df) {
        sub <- df[as.character(df[[sv]]) == l & !is.na(df[[sv]]), , drop = FALSE]
        fit <- .fit_firth_disease(sub)
        if (is.null(fit)) return(NULL)
        .extract_disease_terms(fit)
      })
      pooled <- .pool_terms(stratum_terms)
      rows[[length(rows) + 1L]] <- .term_to_row(
        pooled, .pe_key, "Disease=Preeclampsia"
      )
      rows[[length(rows) + 1L]] <- .term_to_row(
        pooled, .ch_key, "Disease=Chronic hypertension with preeclampsia"
      )
    }
  }
  do.call(rbind, rows)
}

outcomes <- list(
  Preterm34 = list(label = "Preterm delivery", col = "Preterm34"),
  Apgar1_lt8 = list(label = "Apgar 1 min < 8", col = "Apgar1_lt8"),
  Apgar5_lt8 = list(label = "Apgar 5 min < 8", col = "Apgar5_lt8"),
  Newborn_lt1500 = list(label = "Newborn weight < 1500 g", col = "Newborn_lt1500"),
  Newborn_lt2000 = list(label = "Newborn weight < 2000 g", col = "Newborn_lt2000")
)

sub_cfg <- config$subgroup %||% list()
age_cut <- as.numeric(sub_cfg$age_cutoff %||% 35)[1L]
if (!is.finite(age_cut)) age_cut <- 35

for (ou in names(outcomes)) {
  spec <- outcomes[[ou]]
  oc <- spec$col
  cli::cli_h1("Firth 亚组森林图: {oc}")

  # 检查结局列
  if (!oc %in% names(imp_list[[1]]) && !oc %in% names(imp0)) {
    cli::cli_alert_warning("{oc}: 数据中无该列，跳过")
    next
  }

  .prep_frames <- function(scheme) {
    lapply(imp_list, function(d) {
      if (!oc %in% names(d) && oc %in% names(imp0)) d[[oc]] <- imp0[[oc]]
      d <- .ensure_age_group(d, age_cut)
      .pe_add_pre_bmi_group(d, scheme)
    })
  }
  .resolve_sg <- function(frames_raw) {
    sg_vars <- .resolve_subgroup_vars(oc, frames_raw[[1]], sub_cfg)
    if ("Age_Group" %in% names(frames_raw[[1]]) &&
        length(unique(stats::na.omit(as.character(frames_raw[[1]]$Age_Group)))) >= 2L &&
        !"Age_Group" %in% sg_vars) {
      sg_vars <- c("Age_Group", sg_vars)
    }
    ord <- c(
      "Age_Group", "Is_Twin", "Assisted_Reproduction", "Tandem_Screening",
      "Preterm_delivery", "GDM", "Pre_BMI_Group"
    )
    c(intersect(ord, sg_vars), setdiff(sg_vars, ord))
  }

  bmi_scheme <- "china4"
  frames_raw <- .prep_frames(bmi_scheme)
  sg_vars <- .resolve_sg(frames_raw)
  if (!length(sg_vars)) {
    cli::cli_alert_warning("{oc}: 无可用亚组变量，跳过")
    next
  }
  cli::cli_alert_info(
    "亚组变量: {paste(sg_vars, collapse = ', ')} | Pre_BMI={bmi_scheme}"
  )

  res <- tryCatch(
    .build_firth_subgroup_table(oc, frames_raw, sg_vars, age_cut = age_cut),
    error = function(e) {
      cli::cli_alert_danger("{oc} 建表失败: {conditionMessage(e)}")
      NULL
    }
  )
  # 稀有结局：BMI 四分类层内可估率过低 → 退三分类（低体重并入正常）
  if (!is.null(res) && .pe_is_rare_outcome(oc) && "Pre_BMI_Group" %in% sg_vars) {
    rate4 <- .bmi_stratum_estimable_rate(res)
    cli::cli_alert_info(
      "{oc} Pre_BMI 四分类可估率: {if (is.finite(rate4)) sprintf('%.0f%%', 100*rate4) else 'NA'}"
    )
    if (is.finite(rate4) && rate4 < 0.5) {
      bmi_scheme <- "china3"
      frames_raw <- .prep_frames(bmi_scheme)
      sg_vars <- .resolve_sg(frames_raw)
      res <- tryCatch(
        .build_firth_subgroup_table(oc, frames_raw, sg_vars, age_cut = age_cut),
        error = function(e) NULL
      )
      cli::cli_alert_warning(
        "{oc}: Pre_BMI 四分类过稀，已合并为三分类（<24 / 24–27.9 / ≥28）"
      )
    }
  }
  if (is.null(res) || !nrow(res)) {
    cli::cli_alert_warning("{oc}: 亚组表为空")
    next
  }

  plot_df <- subgroup_prepare_forest_plot_df(res, "OR")
  if (is.null(plot_df)) {
    cli::cli_alert_warning("{oc}: forest 表格式化失败")
    next
  }

  dirs <- .find_fig_dir(oc)
  fig_name <- "Figure 2-Own. Subgroup Forest analyses of Disease_Firth.pdf"
  fig_path <- file.path(dirs$figures, fig_name)

  # 清理上次误写的 UnknownDB 中间文件（绝不删 Figure 2-Own....pdf 原图）
  junk <- list.files(
    dirs$figures,
    pattern = "UnknownDB.*Subgroup Forest.*\\.pdf$",
    full.names = TRUE
  )
  if (length(junk)) unlink(junk)

  sub_cfg_u <- utils::modifyList(
    sub_cfg,
    list(
      forest_xlim = c(0.2, 8),
      forest_xlim_max = 200,
      forest_force_single_page = TRUE
    )
  )
  arrow_lab <- c(
    paste0("Lower risk of ", spec$label),
    paste0("Higher risk of ", spec$label)
  )
  plot_ff <- if (exists("resolve_plot_font_family", mode = "function")) {
    resolve_plot_font_family("Times New Roman")
  } else {
    "Times"
  }

  ok <- tryCatch({
    p <- subgroup_build_one_forest(
      plot_df, sg_vars, sub_cfg_u,
      effect_sym = "OR", arrow_lab = arrow_lab, plot_ff = plot_ff
    )
    wh <- tryCatch(forestploter::get_wh(p, unit = "in"), error = function(e) NULL)
    fig_w <- suppressWarnings(as.numeric(wh[["width"]] %||% wh[1L])[1L])
    fig_h <- suppressWarnings(as.numeric(wh[["height"]] %||% wh[2L])[1L])
    if (!is.finite(fig_w) || fig_w < 4) fig_w <- 10
    if (!is.finite(fig_h) || fig_h < 3) fig_h <- max(8, nrow(plot_df) * 0.30 + 2.4)
    fig_w <- min(12, fig_w + 0.6)
    fig_h <- min(28, max(3.8, fig_h + 0.6))
    .draw_pdf <- function(path) {
      ok_c <- tryCatch({
        grDevices::cairo_pdf(path, width = fig_w, height = fig_h, family = plot_ff)
        grid::grid.newpage()
        grid::pushViewport(grid::viewport(clip = "off"))
        grid::grid.draw(p)
        grDevices::dev.off()
        TRUE
      }, error = function(e) {
        try(grDevices::dev.off(), silent = TRUE)
        FALSE
      })
      if (isTRUE(ok_c)) return(TRUE)
      grDevices::pdf(path, width = fig_w, height = fig_h, family = plot_ff,
                     useDingbats = FALSE, compress = TRUE)
      grid::grid.newpage()
      grid::pushViewport(grid::viewport(clip = "off"))
      grid::grid.draw(p)
      grDevices::dev.off()
      TRUE
    }
    .draw_pdf(fig_path)
    file.exists(fig_path) && isTRUE((file.info(fig_path)$size %||% 0) > 1000)
  }, error = function(e) {
    cli::cli_alert_danger("{oc} 出图失败: {conditionMessage(e)}")
    FALSE
  })

  if (isTRUE(ok)) {
    cli::cli_alert_success("Firth 森林图: {fig_path}")
  } else {
    cli::cli_alert_warning("{oc}: Firth PDF 未写出（原 GLM 图未改动）")
  }

  # 表：csv + 可选 xlsx，后缀 _Firth
  csv_fp <- file.path(
    dirs$tables,
    "Table_Subgroup_Analysis_Disease_Firth.csv"
  )
  utils::write.csv(res, csv_fp, row.names = FALSE)
  cli::cli_alert_success("Firth 亚组表: {csv_fp}")
}

cli::cli_alert_success("Firth 亚组森林图全部完成（未覆盖原 GLM 图）")
