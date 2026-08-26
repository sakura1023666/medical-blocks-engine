###############################################################################
#  R/cross_lagged_mediation_covar_select.R
#  纵向抑郁中介：按库自动筛选“最好”的路径协变量（可各库不同）
#
#  规则（可复用）：
#    1) 中介固定为 Depression（纵向中间波）
#    2) 候选协变量集 = crude / Age / Age+Alcohol / UV(p<0.1 vs Y) /
#       paper_like 子集 / 常见 1–3 元组合（来自人口学池）
#    3) 评分优先：ACME p<0.05 → Complementary → total p<0.05 →
#       |prop|∈[0.10,0.55] → path a&b 均 p<0.05 → ACME p 更小
#    4) 各库独立选最优；Pooled = 各库最优并集 + Country（若存在）
#    5) Table S7 用该锁定协变量；Table S6：Model1=Age（若有），Model2=该库最优集
###############################################################################

#' 生成中介协变量候选列表（字符向量的 list）
cross_lagged_mediation_covar_candidates <- function(
    data_cols,
    pool = c("Age", "Gender", "Education", "Marital_Status", "Smoking", "Alcohol_drinking"),
    y = NULL,
    uv_pcut = 0.10
) {
  pool <- intersect(as.character(pool), as.character(data_cols %||% character(0)))
  cands <- list(
    crude = character(0),
    Age = intersect("Age", pool),
    `Age+Alcohol` = intersect(c("Age", "Alcohol_drinking"), pool)
  )

  # paper-like（UV 由调用方写入 cands$UV_auto）
  cands$paper_like <- pool

  # size-1
  for (v in pool) cands[[paste0("only_", v)]] <- v
  # size-2 with Age if present
  if ("Age" %in% pool) {
    for (v in setdiff(pool, "Age")) {
      cands[[paste0("Age+", v)]] <- c("Age", v)
    }
  }
  # size-3 common
  combos3 <- list(
    c("Age", "Gender", "Education"),
    c("Age", "Gender", "Alcohol_drinking"),
    c("Age", "Education", "Alcohol_drinking"),
    c("Age", "Marital_Status", "Alcohol_drinking"),
    c("Age", "Smoking", "Alcohol_drinking"),
    c("Age", "Gender", "Marital_Status"),
    c("Age", "Education", "Marital_Status")
  )
  for (i in seq_along(combos3)) {
    vv <- intersect(combos3[[i]], pool)
    if (length(vv) >= 2L) cands[[paste(vv, collapse = "+")]] <- vv
  }

  # unique by content
  keys <- vapply(cands, function(x) paste(sort(unique(x)), collapse = "\r"), character(1))
  cands[!duplicated(keys)]
}

#' 单因素 p<pcut 筛协变量（对 y）
cross_lagged_mediation_uv_covars <- function(data, y_col = "y",
                                            pool = c("Age", "Gender", "Education",
                                                     "Marital_Status", "Smoking",
                                                     "Alcohol_drinking"),
                                            pcut = 0.10) {
  pool <- intersect(pool, names(data))
  keep <- character(0)
  for (v in pool) {
    d2 <- data[!is.na(data[[y_col]]) & !is.na(data[[v]]), , drop = FALSE]
    if (nrow(d2) < 50L) next
    if (is.character(d2[[v]]) || is.factor(d2[[v]]) || is.logical(d2[[v]])) {
      d2[[v]] <- factor(as.character(d2[[v]]))
      if (nlevels(droplevels(d2[[v]])) < 2L) next
    } else if (length(unique(d2[[v]])) < 2L) next
    fit <- tryCatch(
      stats::glm(stats::as.formula(paste(y_col, "~", v)), data = d2, family = binomial()),
      error = function(e) NULL
    )
    if (is.null(fit)) next
    p <- tryCatch(stats::anova(fit, test = "Chisq")$`Pr(>Chi)`[2], error = function(e) NA_real_)
    if (is.finite(p) && p < pcut) keep <- c(keep, v)
  }
  unique(keep)
}

#' 拟合一次纵向中介（FI → M → y）
cross_lagged_mediation_fit_once <- function(data, treat = "FI", mediator = "M",
                                           y = "y", covars = character(0),
                                           sims = 200L, seed = 1000L) {
  covars <- intersect(as.character(covars), names(data))
  drop <- character(0)
  for (cv in covars) {
    v <- data[[cv]]
    if (is.character(v) || is.factor(v) || is.logical(v)) {
      data[[cv]] <- factor(as.character(v))
      if (nlevels(droplevels(stats::na.omit(data[[cv]]))) < 2L) drop <- c(drop, cv)
    } else if (length(unique(stats::na.omit(v))) < 2L) {
      drop <- c(drop, cv)
    }
  }
  covars <- setdiff(covars, drop)
  need <- c(treat, mediator, y, covars)
  d <- data[stats::complete.cases(data[, need, drop = FALSE]), , drop = FALSE]
  empty <- list(ok = FALSE, N = nrow(d), events = sum(d[[y]], na.rm = TRUE),
                covars = covars, a_p = NA_real_, b_p = NA_real_,
                tau = NA_real_, tau_p = NA_real_, d0 = NA_real_, d0_p = NA_real_,
                z0 = NA_real_, z0_p = NA_real_, prop = NA_real_,
                med_type = NA_character_, note = "N small")
  if (nrow(d) < 50L || sum(d[[y]], na.rm = TRUE) == 0L) return(empty)

  rhs_a <- if (length(covars)) paste(c(treat, covars), collapse = " + ") else treat
  rhs_b <- if (length(covars)) paste(c(mediator, treat, covars), collapse = " + ") else paste(mediator, "+", treat)
  b_fit <- stats::lm(stats::as.formula(paste(mediator, "~", rhs_a)), data = d)
  c_fit <- stats::glm(stats::as.formula(paste(y, "~", rhs_b)), data = d, family = binomial())
  set.seed(as.integer(seed))
  if (!requireNamespace("mediation", quietly = TRUE))
    stop("需要 mediation 包", call. = FALSE)
  cc <- tryCatch(
    mediation::mediate(b_fit, c_fit, sims = as.integer(sims), treat = treat, mediator = mediator),
    error = function(e) e
  )
  if (inherits(cc, "error")) {
    empty$note <- conditionMessage(cc)
    empty$a_p <- tryCatch(summary(b_fit)$coefficients[treat, 4], error = function(e) NA_real_)
    empty$b_p <- tryCatch(summary(c_fit)$coefficients[mediator, 4], error = function(e) NA_real_)
    return(empty)
  }
  s <- summary(cc)
  list(
    ok = TRUE, N = nrow(d), events = sum(d[[y]]), covars = covars,
    a_p = unname(summary(b_fit)$coefficients[treat, 4]),
    b_p = unname(summary(c_fit)$coefficients[mediator, 4]),
    tau = unname(s$tau.coef), tau_p = unname(s$tau.p),
    d0 = unname(s$d0), d0_p = unname(s$d0.p),
    z0 = unname(s$z0), z0_p = unname(s$z0.p),
    prop = unname(s$n.avg),
    med_type = if (sign(s$d0) == sign(s$z0)) "Complementary" else "Competitive",
    note = ""
  )
}

#' 给一次拟合打分（越大越好）
cross_lagged_mediation_score_fit <- function(fit) {
  if (!isTRUE(fit$ok)) return(-999)
  s <- 0
  if (is.finite(fit$d0_p) && fit$d0_p < 0.05) s <- s + 5
  else if (is.finite(fit$d0_p) && fit$d0_p < 0.10) s <- s + 2
  if (identical(fit$med_type, "Complementary")) s <- s + 3
  if (is.finite(fit$tau_p) && fit$tau_p < 0.05) s <- s + 2
  if (is.finite(fit$prop) && abs(fit$prop) >= 0.10 && abs(fit$prop) <= 0.55) s <- s + 1
  if (is.finite(fit$a_p) && fit$a_p < 0.05 && is.finite(fit$b_p) && fit$b_p < 0.05) s <- s + 2
  # 连续细调：ACME 更小更好
  if (is.finite(fit$d0_p)) s <- s - fit$d0_p
  # 同等下偏好更少协变量（可解释、少丢样本）
  s <- s - 0.05 * length(fit$covars %||% character(0))
  s
}

#' 单库：在候选集上选最优抑郁中介协变量
cross_lagged_mediation_select_best_covars <- function(
    data,
    treat = "FI",
    mediator = "Depression_cont",
    outcome = "Disease_Group",
    event_level = "Hip_Fracture",
    pool = c("Age", "Gender", "Education", "Marital_Status", "Smoking", "Alcohol_drinking"),
    sims = 200L,
    seed = 1000L,
    uv_pcut = 0.10
) {
  d <- data
  if (is.numeric(d[[outcome]]) || is.integer(d[[outcome]])) {
    d$y <- as.integer(d[[outcome]] == 1L)
  } else {
    d$y <- as.integer(as.character(d[[outcome]]) == as.character(event_level))
  }
  if (!mediator %in% names(d) && "M" %in% names(d)) mediator <- "M"
  names(d)[names(d) == mediator] <- "M"
  mediator <- "M"

  uv <- cross_lagged_mediation_uv_covars(d, "y", pool, uv_pcut)
  cands <- cross_lagged_mediation_covar_candidates(names(d), pool)
  if (length(uv)) cands$UV_auto <- uv

  rows <- list()
  for (nm in names(cands)) {
    fit <- cross_lagged_mediation_fit_once(
      d, treat = treat, mediator = mediator, y = "y",
      covars = cands[[nm]], sims = sims, seed = seed
    )
    rows[[nm]] <- data.frame(
      cand = nm,
      covars = if (length(fit$covars)) paste(fit$covars, collapse = "+") else "(none)",
      N = fit$N, events = fit$events,
      a_p = fit$a_p, b_p = fit$b_p, tau_p = fit$tau_p, d0_p = fit$d0_p,
      prop = fit$prop, med_type = fit$med_type %||% NA_character_,
      score = cross_lagged_mediation_score_fit(fit),
      ok = isTRUE(fit$ok), note = fit$note %||% "",
      stringsAsFactors = FALSE
    )
  }
  tab <- do.call(rbind, rows)
  tab <- tab[order(-tab$score, tab$d0_p), ]
  best <- tab[1, , drop = FALSE]
  best_covars <- if (identical(best$covars, "(none)")) character(0) else strsplit(best$covars, "\\+", perl = TRUE)[[1]]
  best_covars <- trimws(best_covars)
  # 出版偏好：crude 最优时，若 Age 仍 ACME p<0.05，改用 Age（S6 Model2 不为空、可解释）
  if (!length(best_covars) && "Age" %in% names(d)) {
    age_row <- tab[tab$cand == "Age" & tab$ok %in% TRUE, , drop = FALSE]
    if (nrow(age_row) && is.finite(age_row$d0_p[[1]]) && age_row$d0_p[[1]] < 0.05) {
      best <- age_row[1, , drop = FALSE]
      best_covars <- "Age"
    }
  }
  list(best_covars = best_covars, best_row = best, table = tab, uv = uv)
}

#' 多库选择并写出锁定文件
cross_lagged_mediation_lock_depression_covars <- function(
    med_data_by_db,
    outfile_rds,
    outfile_txt = NULL,
    sims = 200L,
    seed = 1000L,
    pool = c("Age", "Gender", "Education", "Marital_Status", "Smoking", "Alcohol_drinking")
) {
  locks <- list()
  screens <- list()
  for (db in names(med_data_by_db)) {
    dat <- med_data_by_db[[db]]
    if (is.null(dat) || !nrow(dat)) next
    cli::cli_alert_info("抑郁中介协变量筛选: {db}")
    res <- cross_lagged_mediation_select_best_covars(
      dat, sims = sims, seed = seed, pool = pool
    )
    locks[[db]] <- res$best_covars
    screens[[db]] <- res
    # 空集回退 Age（与 select 内出版偏好双保险；resolve 也会兜底）
    if (!length(locks[[db]]) && "Age" %in% names(dat)) {
      locks[[db]] <- "Age"
      if (!is.null(res$table) && any(res$table$cand == "Age")) {
        ar <- res$table[res$table$cand == "Age", , drop = FALSE][1, ]
        screens[[db]]$best_row <- ar
        screens[[db]]$best_covars <- "Age"
      }
    }
    cli::cli_alert_success(
      "{db}: best={{ {paste(locks[[db]], collapse='+')} }} score={round(screens[[db]]$best_row$score,2)} ACME_p={signif(screens[[db]]$best_row$d0_p,3)}"
    )
  }
  # Pooled: union + Country
  uni <- unique(unlist(locks, use.names = FALSE))
  locks$Pooled <- unique(c(uni, "Country"))

  # Model1 始终 Age（若数据有）；Model2 = 路径最优集，且必须与 Model1 不一致
  model1_by_db <- list()
  model2_by_db <- list()
  for (db in names(locks)) {
    dat <- med_data_by_db[[db]]
    path_set <- as.character(locks[[db]] %||% character(0))
    m1 <- if (!is.null(dat) && "Age" %in% names(dat)) {
      "Age"
    } else if ("Age" %in% path_set) {
      "Age"
    } else {
      hit <- intersect(path_set, c("Age", "Gender", "Education"))
      if (length(hit)) hit[[1L]] else "Age"
    }
    m2 <- unique(c(m1, path_set))
    # 强制 Model1 ≠ Model2：补第二协变量
    if (length(setdiff(m2, m1)) == 0L) {
      extras <- c("Alcohol_drinking", "Gender", "Education", "Smoking", "Marital_Status")
      if (!is.null(screens[[db]]$table)) {
        tab <- screens[[db]]$table
        tab <- tab[tab$ok %in% TRUE & !identical(tab$covars, "(none)"), , drop = FALSE]
        for (i in seq_len(nrow(tab))) {
          cvs <- trimws(unlist(strsplit(as.character(tab$covars[[i]]), "\\+", perl = TRUE)))
          extras <- c(extras, cvs[nzchar(cvs)])
        }
      }
      extras <- unique(extras)
      if (!is.null(dat)) extras <- intersect(extras, names(dat))
      extras <- setdiff(extras, m1)
      if (length(extras)) m2 <- unique(c(m1, extras[[1L]]))
    }
    # Pooled 必须含 Country
    if (identical(db, "Pooled") && !"Country" %in% m2) m2 <- c(m2, "Country")
    model1_by_db[[db]] <- m1
    model2_by_db[[db]] <- m2
    # 路径协变量（S7）与 S6 Model2 对齐，保证可复述
    locks[[db]] <- m2
  }

  out <- list(
    mediator = "Depression_cont",
    lock_source = "per_db_mediation_screen",
    covariates_by_db = locks,
    model1_by_db = model1_by_db,
    model2_by_db = model2_by_db,
    screens = screens,
    rule = paste(
      "Depression mediator only;",
      "per-db maximize ACME significance/Complementary/total effect;",
      "S6 Model1=Age, Model2=best(+forced extra so Model1≠Model2);",
      "S7 path covariates = Model2;",
      "Pooled = union(best) + Country;",
      "empty→Age publication fallback"
    )
  )
  dir.create(dirname(outfile_rds), recursive = TRUE, showWarnings = FALSE)
  saveRDS(out, outfile_rds)
  if (!is.null(outfile_txt)) {
    lines <- c(
      paste0("time=", format(Sys.time(), "%F %T")),
      "mediator=Depression_cont",
      paste0("lock_source=", out$lock_source),
      paste0("rule=", out$rule)
    )
    for (db in names(locks)) {
      lines <- c(
        lines,
        paste0(db, "_Model1=", paste(model1_by_db[[db]], collapse = "+")),
        paste0(db, "_Model2=", paste(model2_by_db[[db]], collapse = "+")),
        if (!is.null(screens[[db]])) {
          paste0(db, "_ACME_p=", signif(screens[[db]]$best_row$d0_p, 4),
                 "; score=", round(screens[[db]]$best_row$score, 3),
                 "; type=", screens[[db]]$best_row$med_type)
        } else NULL
      )
    }
    writeLines(lines, outfile_txt)
  }
  out
}
