# Reference-paper association figures/tables (AKI SOSM+WPR x SOFA strata).
# Task 4: Figure 2-6 + Table 2 / S4 / S5 / S6-S8 / S9 / S10 (staging single PDFs).
#
# Trust model (Task 3 provenance): every lock (joint tertile cutpoints, RCS
# spline/reference, PH landmark stratum/day) is estimated ONLY on the trusted
# MIMIC development train frame. Because the PH lock requires the scan data to
# hash-match the authority train, Task 4 writes an auditable DERIVED authority
# snapshot = original train + frozen SOFA-layer / joint-group columns under
# out_dir/authority/checkpoints/by_index/SOSM+WPR_REF/MIMIC_IV/ (never the
# original study directory). eICU only applies the signed locks.

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}


# Dual-index pair for the current study (set by ref_assoc_run_all / CLI).
.ref_assoc_idx <- list(a = "SOSM", b = "WPR", label = "SOSM+WPR")
.ref_assoc_set_indices <- function(indices) {
  indices <- as.character(indices)
  if (length(indices) != 2L || any(!nzchar(indices))) {
    stop("ref_assoc indices must be length-2 character (e.g. c(\"ACAG\",\"RAR\")).",
         call. = FALSE)
  }
  .ref_assoc_idx <<- list(a = indices[[1]], b = indices[[2]],
                          label = paste0(indices[[1]], "+", indices[[2]]))
  invisible(.ref_assoc_idx)
}
.ref_ia <- function() .ref_assoc_idx$a
.ref_ib <- function() .ref_assoc_idx$b
.ref_ilab <- function() .ref_assoc_idx$label
## 图面/表题展示名（禁下划线）；路径/锁键仍用 .ref_ia/.ref_ib/.ref_ilab
.ref_disp <- function(x) {
  x <- as.character(x %||% "")
  if (!length(x)) return(x)
  if (exists("pipeline_display_label", mode = "function")) {
    return(pipeline_display_label(x))
  }
  gsub("_", " ", x, fixed = TRUE)
}
.ref_ia_lab <- function() .ref_disp(.ref_ia())
.ref_ib_lab <- function() .ref_disp(.ref_ib())
.ref_ilab_disp <- function() paste0(.ref_ia_lab(), "+", .ref_ib_lab())
# 图面显示名：联合四分组（各指标最高三分位 high × 其余 low）
.ref_joint_lab <- function() paste0(.ref_ilab_disp(), " joint")


.ref_assoc_require <- function(names) {
  missing <- names[!vapply(names, exists, logical(1), mode = "function",
                           inherits = TRUE)]
  if (length(missing)) {
    stop("Missing reference-association dependencies: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
  invisible(TRUE)
}

ref_assoc_dependencies_ok <- function() {
  ok <- tryCatch({
    .ref_assoc_require(c(
      "reference_trusted_development", "reference_lock_tertile_cutpoints",
      "reference_apply_joint_tertiles", "reference_joint_tertile_groups",
      "reference_grouped_rcs", "reference_lock_grouped_rcs",
      "reference_ph_landmark_lock", "reference_apply_landmark",
      "ml_stratum_spec_sofa", ".reference_event01", ".reference_numeric",
      ".reference_bt", ".reference_assoc_models", ".reference_cox_formula",
      ".reference_term_coefficients", ".reference_ph_p",
      "pub_format_est", "pub_format_p_cell", "pub_est_ci_not_estimable",
      "sci_xlsx_single_header_booktabs"
    ))
    TRUE
  }, error = function(e) FALSE)
  isTRUE(ok)
}

# --------------------------------------------------------------------------
# shared low-level helpers
# --------------------------------------------------------------------------

#' SOFA 分层标签（默认三层 0–4 / 5–10 / ≥11），与 ml_stratum_spec_sofa() 对齐。
#' 是否仅 Overall（不做 SOFA 分层）。cutoff=NULL / integer(0) / "overall"。
.ref_assoc_overall_only <- function(cutoff) {
  if (is.null(cutoff)) return(TRUE)
  if (is.character(cutoff)) {
    return(identical(tolower(trimws(as.character(cutoff)[1L])), "overall"))
  }
  br <- suppressWarnings(as.integer(as.numeric(cutoff)))
  br <- br[!is.na(br)]
  !length(br)
}

#' cutoff 参数现承载递增整数切点向量（breaks）；单值等价旧 2 层口径。
#' overall-only 时返回 integer(0)（调用方须先判 .ref_assoc_overall_only）。
.ref_assoc_breaks <- function(cutoff) {
  if (.ref_assoc_overall_only(cutoff)) return(integer(0))
  br <- suppressWarnings(as.integer(as.numeric(cutoff)))
  br <- br[!is.na(br)]
  if (!length(br)) c(4L, 10L) else unique(sort(br))
}

ref_assoc_sofa_layer <- function(data, cutoff = c(4L, 10L)) {
  n <- if (is.data.frame(data)) nrow(data) else length(data)
  if (.ref_assoc_overall_only(cutoff)) {
    return(factor(rep("Overall", n), levels = "Overall"))
  }
  spec <- ml_stratum_spec_sofa(breaks = .ref_assoc_breaks(cutoff))
  value <- suppressWarnings(as.numeric(as.character(data[[spec$variable]])))
  out <- rep(NA_character_, length(value))
  for (s in spec$strata) {
    out[ml_stratum_member(value, s)] <- s$label
  }
  factor(out, levels = vapply(spec$strata, function(s) s$label, character(1)))
}

#' Overall + 各 SOFA 层的标签顺序（图/表统一使用）。
#' overall-only 时仅返回 "Overall"。
ref_assoc_layer_labels <- function(cutoff = c(4L, 10L)) {
  if (.ref_assoc_overall_only(cutoff)) return("Overall")
  spec <- ml_stratum_spec_sofa(breaks = .ref_assoc_breaks(cutoff))
  c("Overall", vapply(spec$strata, function(s) s$label, character(1)))
}

# 主库（开发）永远排在外验库之前，避免 facet 按字母把 eICU 顶到第一行。
.ref_assoc_db_levels <- function(short = FALSE) {
  if (isTRUE(short)) c("MIMIC-IV", "eICU") else c("MIMIC_IV", "eICU")
}

.ref_assoc_order_db_frames <- function(db_frames) {
  if (!length(db_frames)) return(db_frames)
  nm <- vapply(db_frames, function(x) {
    as.character(x$name %||% x$short %||% "")[1L]
  }, character(1))
  prefer <- c(
    which(grepl("MIMIC", nm, ignore.case = TRUE)),
    which(grepl("eICU", nm, ignore.case = TRUE)),
    which(!grepl("MIMIC|eICU", nm, ignore.case = TRUE))
  )
  prefer <- unique(prefer)
  db_frames[prefer]
}

.ref_assoc_factor_db <- function(x, short = FALSE) {
  labs <- .ref_assoc_db_levels(short = short)
  x0 <- as.character(x)
  x0[x0 %in% c("MIMIC_IV", "MIMIC-IV", "MIMIC")] <- labs[[1]]
  x0[x0 %in% c("eICU", "EICU")] <- labs[[2]]
  factor(x0, levels = labs)
}


.ref_assoc_event01 <- function(d, event, cfg) {
  d[[event]] <- .reference_event01(d[[event]], cfg = cfg)
  d
}

.ref_assoc_layer_masks <- function(d, cutoff = c(4L, 10L)) {
  if (.ref_assoc_overall_only(cutoff)) {
    return(list(Overall = rep(TRUE, nrow(d))))
  }
  spec <- ml_stratum_spec_sofa(breaks = .ref_assoc_breaks(cutoff))
  value <- suppressWarnings(as.numeric(as.character(d[[spec$variable]])))
  masks <- list(Overall = rep(TRUE, nrow(d)))
  for (s in spec$strata) {
    masks[[s$label]] <- ml_stratum_member(value, s)
  }
  masks
}

#' Development-frozen upper-tertile cutpoint (from signed lock) for an index.
.ref_assoc_upper_cut <- function(lock) unname(lock$cutpoints[["a"]])

#' Development-frozen lower-tertile cut (quantile type 7 on trusted train).
.ref_assoc_lower_cut <- function(index, train_ref) {
  if (!is.data.frame(train_ref) || !index %in% names(train_ref)) {
    stop("Trusted development train frame is required for tertile cuts.",
         call. = FALSE)
  }
  unname(stats::quantile(
    .reference_numeric(train_ref[[index]], index), 1 / 3, type = 7
  ))
}

.ref_assoc_tertile3 <- function(d, index, lock, train_ref) {
  upper <- .ref_assoc_upper_cut(lock)
  lower <- .ref_assoc_lower_cut(index, train_ref)
  x <- suppressWarnings(as.numeric(as.character(d[[index]])))
  out <- rep(NA_character_, length(x))
  out[!is.na(x) & x <= lower] <- "T1"
  out[!is.na(x) & x > lower & x <= upper] <- "T2"
  out[!is.na(x) & x > upper] <- "T3"
  factor(out, levels = c("T1", "T2", "T3"))
}

.ref_assoc_models <- function(assoc_ctx, data, indices = c("SOSM", "WPR"),
                              stratum_vars = "SOFA_layer") {
  .reference_assoc_models(assoc_ctx, data, indices, stratum_vars)
}

#' Age+Sex adjust model key in models list (literature Model2 or legacy Model1 Age+Gender).
.ref_assoc_age_sex_model_name <- function(models) {
  nms <- names(models)
  if ("Model2" %in% nms && "Model1" %in% nms && !"Unadjusted" %in% nms) {
    return("Model2")
  }
  if ("Model1 Age+Gender" %in% nms) return("Model1 Age+Gender")
  if ("Model2" %in% nms) return("Model2")
  nms[[1L]]
}

#' Resolve literature Model1–3 covariate lists for a db_frame.
#' Prefer explicit `db$models`; else read locked factors from `db$assoc_ctx`.
.ref_assoc_resolve_db_models <- function(db, data = NULL) {
  if (!is.null(db$models) && length(db$models)) return(db$models)
  ctx <- db$assoc_ctx
  nm <- if (is.data.frame(data)) names(data) else character(0)
  pick <- function(x) {
    x <- unique(as.character(x %||% character(0)))
    x <- x[nzchar(x)]
    if (length(nm)) x <- intersect(x, nm)
    x
  }
  sex <- intersect(c("Gender", "Sex"), if (length(nm)) nm else c("Gender", "Sex"))
  m_agesex <- pick(c("Age", if (length(sex)) sex[[1L]] else "Gender"))
  if (!length(m_agesex)) m_agesex <- "Age"
  m3 <- pick(ctx$results$assoc_model3_factors %||% ctx$results$Model3Factors)
  if (!length(m3)) m3 <- pick(ctx$results$assoc_model2_factors)
  if (!length(m3)) m3 <- m_agesex
  m3 <- unique(c(m_agesex, setdiff(m3, m_agesex)))
  list(Model1 = character(0), Model2 = m_agesex, Model3 = m3)
}

#' Fully adjusted model key (literature Model3 or legacy Model2).
.ref_assoc_full_model_name <- function(models) {
  nms <- names(models)
  if ("Model3" %in% nms) return("Model3")
  if ("Model2" %in% nms && "Model1 Age+Gender" %in% nms) return("Model2")
  if ("Model2" %in% nms) return("Model2")
  nms[[length(nms)]]
}

.ref_assoc_table2_model_names <- function(models) {
  nms <- names(models)
  if (all(c("Model1", "Model2", "Model3") %in% nms)) {
    return(c("Model1", "Model2", "Model3"))
  }
  c("Unadjusted", "Model1 Age+Gender", "Model2")
}

.ref_assoc_hr_ci <- function(hr, lo, hi) {
  if (!is.finite(hr)) return("NE")
  if (isTRUE(pub_est_ci_not_estimable(hr, lo, hi))) return("NE")
  paste0(pub_format_est(hr), " (", pub_format_est(lo), ", ",
         pub_format_est(hi), ")")
}

.ref_assoc_fmt_long <- function(res) {
  ok <- grepl("^estimable", as.character(res$status))
  res$hr_ci <- ifelse(
    ok,
    vapply(seq_len(nrow(res)), function(i) {
      cell <- .ref_assoc_hr_ci(res$hr[i], res$conf_low[i], res$conf_high[i])
      if (identical(as.character(res$status[i]), "estimable_m1_fallback") &&
          !identical(cell, "NE")) {
        paste0(cell, "\u2021")
      } else {
        cell
      }
    }, character(1)),
    "NE"
  )
  res$p_cell <- pub_format_p_cell(res$p)
  res
}

# --------------------------------------------------------------------------
# Cox long-form engine (layers x indices x models)
# --------------------------------------------------------------------------

.ref_assoc_cox_long <- function(data, time, event, indices, models, layers,
                                outcome_cfg, index_terms) {
  rows <- list()
  k <- 0L
  for (layer_name in names(layers)) {
    d <- data[layers[[layer_name]], , drop = FALSE]
    for (index in indices) {
      d[[index]] <- index_terms[[index]](d)
      for (model_name in names(models)) {
        vars <- models[[model_name]]
        needed <- unique(c(time, event, index, vars))
        dd <- d[, needed, drop = FALSE]
        dd <- .ref_assoc_event01(dd, event, outcome_cfg)
        dd[[time]] <- .reference_numeric(dd[[time]], time, positive = TRUE)
        dd <- dd[stats::complete.cases(dd), , drop = FALSE]
        n <- nrow(dd)
        ne <- sum(dd[[event]] == 1L)
        mk_na <- function() {
          k <<- k + 1L
          rows[[k]] <<- data.frame(
            stratum = layer_name, index = index, model = model_name,
            term = NA_character_, hr = NA_real_, conf_low = NA_real_,
            conf_high = NA_real_, p = NA_real_, n = n, events = ne,
            status = "not_estimable", stringsAsFactors = FALSE
          )
        }
        if (n < 10L || ne < 1L ||
            length(unique(as.character(dd[[index]]))) < 2L) {
          mk_na()
          next
        }
        fit <- tryCatch(
          survival::coxph(
            .reference_cox_formula(time, event, index, vars),
            data = dd, x = TRUE, model = TRUE
          ),
          error = function(e) NULL
        )
        used_fallback <- FALSE
        # 全调整层（Model3 / legacy Model2）在小层/高维时常 aliased；
        # 回退 Age+Sex（Model2 / legacy Model1 Age+Gender），单元格加 ‡ 脚注。
        full_nm <- .ref_assoc_full_model_name(models)
        age_sex_nm <- .ref_assoc_age_sex_model_name(models)
        if ((is.null(fit) || anyNA(stats::coef(fit))) &&
            identical(model_name, full_nm) &&
            !identical(full_nm, age_sex_nm)) {
          m1 <- models[[age_sex_nm]]
          if (length(m1)) {
            needed1 <- unique(c(time, event, index, m1))
            dd1 <- d[, needed1, drop = FALSE]
            dd1 <- .ref_assoc_event01(dd1, event, outcome_cfg)
            dd1[[time]] <- .reference_numeric(dd1[[time]], time, positive = TRUE)
            dd1 <- dd1[stats::complete.cases(dd1), , drop = FALSE]
            fit <- tryCatch(
              survival::coxph(
                .reference_cox_formula(time, event, index, m1),
                data = dd1, x = TRUE, model = TRUE
              ),
              error = function(e) NULL
            )
            if (!is.null(fit) && !anyNA(stats::coef(fit))) {
              used_fallback <- TRUE
              n <- nrow(dd1)
              ne <- sum(dd1[[event]] == 1L)
            } else {
              fit <- NULL
            }
          }
        }
        if (is.null(fit) || anyNA(stats::coef(fit))) {
          mk_na()
          next
        }
        hits <- .reference_term_coefficients(fit, index)
        ci <- stats::confint(fit)
        sm <- summary(fit)
        for (term in hits) {
          k <- k + 1L
          z <- sm$coefficients[term, "z"]
          rows[[k]] <- data.frame(
            stratum = layer_name, index = index, model = model_name,
            term = term,
            hr = unname(exp(stats::coef(fit)[term])),
            conf_low = unname(exp(ci[term, 1L])),
            conf_high = unname(exp(ci[term, 2L])),
            p = unname(2 * stats::pnorm(-abs(z))),
            n = n, events = ne,
            status = if (used_fallback) "estimable_m1_fallback" else "estimable",
            stringsAsFactors = FALSE
          )
        }
      }
    }
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

# --------------------------------------------------------------------------
# Derived authority snapshot (MIMIC development train + frozen derived cols)
# --------------------------------------------------------------------------

.ref_assoc_write_derived_authority <- function(train_aug, out_dir, cfg) {
  path <- file.path(
    out_dir, "authority", "checkpoints", "by_index", paste0(.ref_ilab(), "_REF"),
    "MIMIC_IV", "step01_reference_derived.rds"
  )
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  proj <- cfg$project %||% list()
  payload <- list(
    ctx = list(
      config = list(
        project = list(
          database = "MIMIC_IV", study_type = "prognosis",
          analysis_group = proj$analysis_group,
          reference_group = proj$reference_group
        ),
        survival = cfg$survival, data = cfg$data, pub_digits = cfg$pub_digits
      ),
      data = list(train = train_aug)
    ),
    config = NULL, pipeline = NULL,
    step = "step01_reference_derived", block = "reference_derived",
    step_index = 1L, saved_at = format(Sys.time()), pub_counters = NULL,
    derived_from = paste0(
      "Task4 frozen derived snapshot of the authoritative MIMIC development ",
      "train plus SOFA-layer / joint-group columns"
    )
  )
  saveRDS(payload, path)
  path
}

# --------------------------------------------------------------------------
# Figure 2: 4 x 3 = 12 KM panels (Log-rank P per panel)
# --------------------------------------------------------------------------

.ref_assoc_km_panel <- function(d, group) {
  keep <- !is.na(as.character(group))
  dd <- data.frame(futime = d$futime[keep], event = d$event[keep],
                   group = droplevels(group[keep]))
  dd <- dd[is.finite(dd$futime) & dd$futime > 0, , drop = FALSE]
  ok <- nrow(dd) >= 4L && length(levels(dd$group)) >= 2L &&
    any(dd$event == 1L) && all(dd$event %in% c(0L, 1L))
  if (!ok) {
    return(list(status = "not_estimable", curve = NULL, p = NA_real_))
  }
  fit <- tryCatch(
    survival::survfit(survival::Surv(futime, event) ~ group, data = dd),
    error = function(e) NULL
  )
  if (is.null(fit)) {
    return(list(status = "not_estimable", curve = NULL, p = NA_real_))
  }
  # survival 以命名空间方式调用时 as.data.frame.survfit 可能不派发，手工构造
  fit_sum <- summary(fit)
  # n.risk 用于压制晚期风险集过小时 Greenwood CI 爆炸（观感异常但统计上常见）
  nr <- if (!is.null(fit_sum$n.risk)) as.integer(fit_sum$n.risk) else
    rep(NA_integer_, length(fit_sum$time))
  sdf <- data.frame(
    time = fit_sum$time, surv = fit_sum$surv,
    upper = fit_sum$upper, lower = fit_sum$lower,
    n.risk = nr,
    grp = sub("^group=", "", as.character(fit_sum$strata)),
    stringsAsFactors = FALSE
  )
  thin <- is.finite(sdf$n.risk) & sdf$n.risk < 20L
  sdf$upper[thin] <- NA_real_
  sdf$lower[thin] <- NA_real_
  p <- tryCatch(
    survival::survdiff(survival::Surv(futime, event) ~ group,
                       data = dd)$pvalue,
    error = function(e) NA_real_
  )
  list(status = "estimable", curve = sdf, p = p, fit = fit, data = dd)
}

# 参考期刊常见 KM：顶栏图例（指标名 + T1/T2/T3）、蓝/红/绿 + 实/点/虚线、
# 左下角 p、classic 白底；不做双库挤条带。
.ref_assoc_km_p_lab <- function(p) {
  if (is.na(p) || !is.finite(p)) return("p = NE")
  # 期刊常见口径：极小 p 写 p < 0.001（勿用科学计数挤在左下角）
  if (p < 0.001) return("p < 0.001")
  sprintf("p = %.3f", p)
}

# 28 天死亡等行政截尾窗：横轴必须画到结局窗，禁 pretty() 收成 0–25
.ref_assoc_km_time_horizon <- function(db_frames = NULL, default = 28) {
  hz <- NA_real_
  if (length(db_frames)) {
    for (db in db_frames) {
      cfg <- db$outcome_cfg %||% db$config %||% list()
      cand <- c(
        suppressWarnings(as.numeric(cfg$performance_ml$surv_horizon)[1L]),
        suppressWarnings(as.numeric(cfg$survival$landmark_days)[1L]),
        suppressWarnings(as.numeric(cfg$prognosis_outcome_landmark$landmark_days)[1L]),
        suppressWarnings(as.numeric(cfg$attrition$landmark_days)[1L])
      )
      cand <- cand[is.finite(cand) & cand > 0]
      if (length(cand)) {
        hz <- cand[[1L]]
        break
      }
    }
  }
  if (!is.finite(hz) || hz <= 0) hz <- as.numeric(default)[1L]
  if (!is.finite(hz) || hz <= 0) hz <- 28
  hz
}

.ref_assoc_km_x_breaks <- function(xmax) {
  xmax <- suppressWarnings(as.numeric(xmax)[1L])
  if (!is.finite(xmax) || xmax <= 0) return(pretty(c(0, 1), n = 4))
  if (abs(xmax - 28) < 1e-6) return(c(0, 7, 14, 21, 28))
  if (abs(xmax - 90) < 1e-6) return(c(0, 30, 60, 90))
  if (abs(xmax - 30) < 1e-6) return(c(0, 10, 20, 30))
  br <- pretty(c(0, xmax), n = 5)
  if (!any(abs(br - xmax) < 1e-6)) br <- sort(unique(c(br[br < xmax], xmax)))
  br
}

.ref_assoc_km_pretty_one <- function(curve, p, legend_title,
                                     xmax = NULL, y_floor = NULL,
                                     panel_letter = NULL) {
  if (is.null(curve) || !nrow(curve)) return(NULL)
  lv <- unique(as.character(curve$grp))
  nums <- suppressWarnings(as.numeric(sub(".*?([0-9]+)$", "\\1", lv)))
  ord <- if (!anyNA(nums)) lv[order(nums)] else sort(lv)
  # Joint Group1–4 → 原文式 Low/High 图例（禁 G1–G4）
  # Group1=双低, Group2=仅A高, Group3=仅B高, Group4=双高
  lab_map <- stats::setNames(ord, ord)
  g_hit <- grepl("^Group[0-9]+$", ord)
  if (any(g_hit)) {
    ia_lab <- .ref_ia_lab(); ib_lab <- .ref_ib_lab()
    g_labs <- c(
      Group1 = paste0("Low ", ia_lab, " + Low ", ib_lab),
      Group2 = paste0("High ", ia_lab, " + Low ", ib_lab),
      Group3 = paste0("Low ", ia_lab, " + High ", ib_lab),
      Group4 = paste0("High ", ia_lab, " + High ", ib_lab)
    )
    # 图例顺序对齐原文：双低 → 仅B高 → 仅A高 → 双高
    paper_ord <- c("Group1", "Group3", "Group2", "Group4")
    paper_ord <- paper_ord[paper_ord %in% ord]
    rest <- setdiff(ord, paper_ord)
    ord <- c(paper_ord, rest)
    lab_map <- stats::setNames(ord, ord)
    for (nm in names(g_labs)) {
      if (nm %in% names(lab_map)) lab_map[[nm]] <- g_labs[[nm]]
    }
  }
  curve$grp <- factor(as.character(curve$grp), levels = ord)
  # 每组补 t=0, S=1，阶梯从左上角起
  origin <- do.call(rbind, lapply(levels(curve$grp), function(g) {
    row0 <- curve[1, , drop = FALSE]
    row0$time <- 0
    row0$surv <- 1
    if ("upper" %in% names(row0)) row0$upper <- 1
    if ("lower" %in% names(row0)) row0$lower <- 1
    if ("n.risk" %in% names(row0)) row0$n.risk <- NA_integer_
    row0$grp <- g
    row0
  }))
  origin$grp <- factor(as.character(origin$grp), levels = levels(curve$grp))
  curve <- rbind(origin, curve)
  n_g <- nlevels(curve$grp)
  is_joint <- any(grepl("^Group[0-9]+$", levels(curve$grp)))
  # 联合组图例很长时不加总标题（对齐原文第三列）
  legend_name <- if (is_joint) NULL else legend_title
  leg_nrow <- if (is_joint) 2L else 1L
  pal <- if (n_g <= 3L) {
    c("#2F5F8A", "#C23B3B", "#3E9B4A")[seq_len(n_g)]
  } else if (n_g == 4L) {
    # 对齐原文：蓝 / 红 / 绿 / 浅蓝
    c("#2F5F8A", "#C23B3B", "#3E9B4A", "#5BA3D9")
  } else {
    grDevices::hcl.colors(n_g, "Dark 3")
  }
  lty <- if (n_g <= 3L) {
    c("solid", "dotted", "dashed")[seq_len(n_g)]
  } else if (n_g == 4L) {
    c("solid", "dotted", "dashed", "dotdash")
  } else {
    rep(c("solid", "dashed", "dotted", "dotdash"), length.out = n_g)
  }
  if (is.null(xmax) || !is.finite(xmax)) {
    xmax <- max(curve$time, na.rm = TRUE)
  }
  xmax <- max(as.numeric(xmax), max(curve$time, na.rm = TRUE), na.rm = TRUE)
  x_breaks <- .ref_assoc_km_x_breaks(xmax)
  ymin <- if (!is.null(y_floor) && is.finite(y_floor)) y_floor else {
    floor(min(curve$surv, na.rm = TRUE) * 10) / 10
  }
  ymin <- max(0, min(ymin, 0.5))
  p_lab <- .ref_assoc_km_p_lab(p)
  # 对齐原文 Fig.2：图例在上、p 在图内左下；禁 subtitle 与 legend 顶栏叠字
  letter <- trimws(as.character(panel_letter %||% "")[1L])
  title_lab <- if (nzchar(letter)) letter else NULL
  ggplot2::ggplot(
    curve,
    ggplot2::aes(x = time, y = surv, colour = grp, linetype = grp)
  ) +
    ggplot2::geom_step(linewidth = 0.85, lineend = "round") +
    ggplot2::annotate(
      "text", x = -Inf, y = -Inf, label = p_lab,
      hjust = -0.05, vjust = -0.4, size = 3.3, colour = "grey15"
    ) +
    ggplot2::scale_colour_manual(
      values = pal, breaks = levels(curve$grp),
      labels = unname(lab_map[levels(curve$grp)]),
      name = legend_name
    ) +
    ggplot2::scale_linetype_manual(
      values = lty, breaks = levels(curve$grp),
      labels = unname(lab_map[levels(curve$grp)]),
      name = legend_name
    ) +
    ggplot2::coord_cartesian(xlim = c(0, xmax), ylim = c(ymin, 1),
                             expand = TRUE, clip = "off") +
    ggplot2::scale_x_continuous(breaks = x_breaks) +
    ggplot2::scale_y_continuous(
      breaks = seq(ymin, 1, by = if ((1 - ymin) > 0.4) 0.25 else 0.1)
    ) +
    ggplot2::labs(
      x = "Time (days)", y = "Survival Probability",
      title = title_lab, subtitle = NULL
    ) +
    ggplot2::theme_classic(
      base_size = 11,
      base_family = if (exists("resolve_plot_font_family", mode = "function"))
        resolve_plot_font_family("Times New Roman") else "Times"
    ) +
    ggplot2::theme(
      legend.position = "top",
      legend.title = ggplot2::element_text(size = 10, face = "bold"),
      legend.text = ggplot2::element_text(size = if (is_joint) 7.2 else 8.5),
      legend.key.width = grid::unit(if (is_joint) 0.55 else 0.75, "cm"),
      legend.key.height = grid::unit(0.28, "cm"),
      legend.margin = ggplot2::margin(0, 0, 2, 0),
      legend.box.margin = ggplot2::margin(0, 0, 0, 0),
      plot.title = ggplot2::element_text(
        size = 12, face = "bold", hjust = 0,
        margin = ggplot2::margin(b = 0)
      ),
      plot.subtitle = ggplot2::element_blank(),
      axis.title = ggplot2::element_text(size = 10),
      axis.text = ggplot2::element_text(size = 9, colour = "grey20"),
      axis.line = ggplot2::element_line(linewidth = 0.45, colour = "grey20"),
      axis.ticks = ggplot2::element_line(linewidth = 0.35, colour = "grey20"),
      plot.margin = ggplot2::margin(6, 10, 8, 8)
    ) +
    ggplot2::guides(
      colour = ggplot2::guide_legend(
        title.position = "top", title.hjust = 0.5, nrow = leg_nrow,
        override.aes = list(linewidth = 0.9)
      ),
      linetype = ggplot2::guide_legend(
        title.position = "top", title.hjust = 0.5, nrow = leg_nrow
      )
    )
}

ref_assoc_fig2_km <- function(db_frames, cutoff = c(4L, 10L), out_pdf = NULL,
                              time_horizon = NULL) {
  ia <- .ref_ia(); ib <- .ref_ib(); ilab <- .ref_ilab()
  db_frames <- .ref_assoc_order_db_frames(db_frames)
  hz <- suppressWarnings(as.numeric(time_horizon)[1L])
  if (!is.finite(hz) || hz <= 0) {
    hz <- .ref_assoc_km_time_horizon(db_frames, default = 28)
  }
  panels <- list()
  curves <- list()
  k <- 0L
  cols <- list(
    list(column = ia, name = paste0(.ref_ia_lab(), " tertile"), legend = .ref_ia_lab()),
    list(column = ib, name = paste0(.ref_ib_lab(), " tertile"), legend = .ref_ib_lab()),
    list(column = "Joint", name = paste0(.ref_ilab_disp(), " joint"),
         legend = .ref_ilab_disp())
  )
  sofa_lv <- ref_assoc_layer_labels(cutoff)
  # overall-only：保留 Overall；有 SOFA 层时 KM 只画各 SOFA 层（不含 Overall 重复）
  if (!.ref_assoc_overall_only(cutoff)) {
    sofa_lv <- sofa_lv[sofa_lv != "Overall"]
  }
  overall_pretty <- isTRUE(.ref_assoc_overall_only(cutoff))
  for (db in db_frames) {
    d <- .ref_assoc_event01(data.frame(db$data), "fustatus", db$outcome_cfg)
    d$event <- d$fustatus
    d$SOFA_layer <- ref_assoc_sofa_layer(d, cutoff)
    joint <- reference_apply_joint_tertiles(d, db$joint_lock)
    d$Joint <- joint$group
    d[[paste0(ia, "_T")]] <- .ref_assoc_tertile3(d, ia, db$sosm_lock, db$train_ref)
    d[[paste0(ib, "_T")]] <- .ref_assoc_tertile3(d, ib, db$wpr_lock, db$train_ref)
    group_of <- stats::setNames(c(paste0(ia, "_T"), paste0(ib, "_T"), "Joint"),
                                c(ia, ib, "Joint"))
    for (ri in seq_along(sofa_lv)) {
      mask <- if (overall_pretty) {
        rep(TRUE, nrow(d))
      } else {
        !is.na(as.character(d$SOFA_layer)) &
          as.character(d$SOFA_layer) == sofa_lv[[ri]]
      }
      for (col in cols) {
        k <- k + 1L
        res <- .ref_assoc_km_panel(d[mask, , drop = FALSE],
                                   d[[group_of[[col$column]]]][mask])
        panels[[k]] <- data.frame(
          panel = k, row = ri, column = col$column, database = db$name,
          stratum = sofa_lv[[ri]],
          panel_title = if (overall_pretty) {
            col$legend
          } else {
            paste0(db$short, " ", sofa_lv[[ri]], " | ", col$name)
          },
          legend_title = col$legend,
          logrank_p = res$p, status = res$status, n = sum(mask),
          stringsAsFactors = FALSE
        )
        if (!is.null(res$curve)) {
          cv <- res$curve
          cv$panel <- k
          curves[[k]] <- cv
        }
      }
    }
  }
  panels <- do.call(rbind, panels)
  rownames(panels) <- NULL
  curve <- if (length(curves)) do.call(rbind, curves) else NULL
  path <- NULL
  if (!is.null(out_pdf) && !is.null(curve)) {
    path <- out_pdf
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    if (overall_pretty) {
      # 对齐原文 Fig.2 版式：每格图例在上、p 在左下；行=双库（替原文糖代谢层），列=三暴露。
      db_order <- unique(as.character(panels$database))
      db_lab <- function(dbn) {
        if (grepl("eicu", dbn, ignore.case = TRUE)) "eICU" else "MIMIC-IV"
      }
      # 行政截尾窗（默认 28 天）钉死横轴上限；数据 max 常 <28，pretty 会缩成 0–25
      xmax <- max(
        hz,
        max(curve$time[curve$panel %in% panels$panel], na.rm = TRUE),
        na.rm = TRUE
      )
      y_floor <- max(
        0,
        floor(min(curve$surv[curve$panel %in% panels$panel],
                  na.rm = TRUE) * 10) / 10 - 0.1
      )
      y_floor <- min(y_floor, 0.5)
      letter_i <- 0L
      row_plts <- list()
      for (dbn in db_order) {
        panels_use <- panels[as.character(panels$database) == dbn, , drop = FALSE]
        if (!nrow(panels_use)) next
        plts <- lapply(seq_len(nrow(panels_use)), function(i) {
          pr <- panels_use[i, , drop = FALSE]
          cv <- curve[curve$panel == pr$panel, , drop = FALSE]
          letter_i <<- letter_i + 1L
          # 首格标题带库名（可检索）；其余仅字母，避免与图例叠字
          lab_i <- if (i == 1L) {
            paste0(LETTERS[[letter_i]], "  ", db_lab(dbn))
          } else {
            LETTERS[[letter_i]]
          }
          .ref_assoc_km_pretty_one(
            cv, pr$logrank_p, legend_title = pr$legend_title,
            xmax = xmax, y_floor = y_floor,
            panel_letter = lab_i
          )
        })
        plts <- Filter(Negate(is.null), plts)
        if (!length(plts)) next
        if (requireNamespace("patchwork", quietly = TRUE)) {
          row_plts[[length(row_plts) + 1L]] <- patchwork::wrap_plots(plts, nrow = 1) +
            patchwork::plot_annotation(
              theme = ggplot2::theme(plot.margin = ggplot2::margin(2, 4, 2, 4))
            )
        } else {
          stop("Figure 2 dual-db overall needs package patchwork", call. = FALSE)
        }
      }
      if (!length(row_plts)) stop("Figure 2 overall: no KM panels", call. = FALSE)
      plt <- if (length(row_plts) == 1L) {
        row_plts[[1L]]
      } else {
        patchwork::wrap_plots(row_plts, ncol = 1)
      }
      n_db_draw <- length(row_plts)
      pipeline_ggsave_pdf(
        path, plt, width = 13.6,
        height = min(11, 4.8 * n_db_draw + 0.3)
      )
    } else {
      strip <- paste0(
        panels$panel_title, "\nLog-rank P = ",
        ifelse(is.na(panels$logrank_p), "NE",
               pub_format_p_cell(panels$logrank_p))
      )
      strip_df <- data.frame(panel = panels$panel, strip = strip,
                             stringsAsFactors = FALSE)
      # 按构建顺序固定 facet（主库在前、SOFA 0-4→≥11、A|B|Joint），禁字母重排
      strip_df <- strip_df[order(strip_df$panel), , drop = FALSE]
      curve <- merge(curve, strip_df, by = "panel", all.x = TRUE, sort = FALSE)
      curve$strip <- factor(curve$strip, levels = strip_df$strip)
      plt <- ggplot2::ggplot(
        curve,
        ggplot2::aes(x = time, y = surv, colour = grp, fill = grp)
      ) +
        ggplot2::geom_ribbon(
          ggplot2::aes(ymin = lower, ymax = upper),
          alpha = 0.15, linewidth = 0, na.rm = TRUE
        ) +
        ggplot2::geom_step(linewidth = 0.6) +
        ggplot2::facet_wrap(~strip, ncol = 3, scales = "free") +
        ggplot2::scale_y_continuous(limits = c(0, 1), expand = c(0.02, 0)) +
        ggplot2::scale_x_continuous(expand = c(0, 0)) +
        ggplot2::labs(x = "Days since ICU admission",
                      y = "Survival probability", colour = NULL, fill = NULL) +
        ggplot2::theme_bw(base_size = 8) +
        ggplot2::theme(legend.position = "bottom",
                       strip.text = ggplot2::element_text(size = 6),
                       panel.grid.minor = ggplot2::element_blank())
      n_rows <- ceiling(nrow(panels) / 3)
      pipeline_ggsave_pdf(path, plt, width = 10,
                          height = max(10, 2.1 * n_rows + 2))
    }
  }
  list(panels = panels, curve = curve, path = path)
}

# --------------------------------------------------------------------------
# Figure 3: grouped RCS, 2 x 2 panels (two adjusted SOFA curves per panel)
# --------------------------------------------------------------------------

ref_assoc_fig3_rcs <- function(db_frames, cutoff = c(4L, 10L), grid_n = 50L,
                               out_pdf = NULL) {
  ia <- .ref_ia(); ib <- .ref_ib(); ilab <- .ref_ilab()
  db_frames <- .ref_assoc_order_db_frames(db_frames)
  summaries <- list()
  curves <- list()
  for (db in db_frames) {
    d <- data.frame(db$data)
    d$SOFA_layer <- ref_assoc_sofa_layer(d, cutoff)
    models_db <- .ref_assoc_resolve_db_models(db, d)
    rcs_covs <- as.character(models_db$Model3 %||% c("Age", "Gender"))
    if (!length(rcs_covs)) rcs_covs <- intersect(c("Age", "Gender"), names(d))
    keep_cols <- intersect(
      c("futime", "fustatus", ia, ib, "SOFA_layer", rcs_covs),
      names(d)
    )
    d <- d[!is.na(d$SOFA_layer), keep_cols, drop = FALSE]
    rcs_covs <- intersect(rcs_covs, names(d))
    for (index in c(ia, ib)) {
      res <- reference_grouped_rcs(
        data = d, time = "futime", event = "fustatus", index = index,
        stratum = "SOFA_layer", covariates = rcs_covs,
        locked_spec = db$rcs_locks[[index]], outcome_cfg = db$outcome_cfg,
        grid_n = grid_n
      )
      s <- res$summary
      s$database <- db$name
      s$index <- index
      summaries[[length(summaries) + 1L]] <- s
      cv <- res$curve
      cv$database <- db$name
      cv$index <- index
      curves[[length(curves) + 1L]] <- cv
    }
  }
  summary <- do.call(rbind, summaries)
  rownames(summary) <- NULL
  curve <- do.call(rbind, curves)
  rownames(curve) <- NULL
  path <- NULL
  if (!is.null(out_pdf)) {
    # P 标注放在 facet strip（区外），避免图内 geom_text 与曲线/刻度碰撞
    ann <- summary
    ann$p_lab <- paste0(
      "P for overall = ", pub_format_p_cell(ann$p_overall),
      "; P for nonlinear = ", pub_format_p_cell(ann$p_nonlinear)
    )
    overall_only <- isTRUE(.ref_assoc_overall_only(cutoff))
    # 双库 Overall：2×2（行=库、列=A|B），每格自带库名+P；禁砍成单库
    db_short_of <- function(dbn) {
      if (grepl("eicu", dbn, ignore.case = TRUE)) "eICU" else "MIMIC-IV"
    }
    strip_df <- do.call(rbind, lapply(
      split(ann, list(ann$database, ann$index), drop = TRUE),
      function(a) {
        idx <- as.character(a$index[[1L]])
        dbn <- as.character(a$database[[1L]])
        db_s <- db_short_of(dbn)
        p_bit <- if (all(as.character(a$stratum) %in% c("Overall", "overall")) ||
                       nrow(a) == 1L) {
          a$p_lab[[1L]]
        } else {
          paste0(a$stratum, ": ", a$p_lab, collapse = "\n")
        }
        idx_lab <- .ref_disp(idx)
        lab <- if (isTRUE(overall_only) &&
                     length(unique(as.character(ann$database))) > 1L) {
          paste0(db_s, " | ", idx_lab, "\n", p_bit)
        } else {
          paste0(idx_lab, "\n", p_bit)
        }
        data.frame(
          database = dbn, index = idx, strip = lab,
          db_ord = db_s, stringsAsFactors = FALSE
        )
      }
    ))
    curve <- merge(curve, strip_df, by = c("database", "index"), all.x = TRUE,
                   sort = FALSE)
    curve$database <- .ref_assoc_factor_db(curve$database, short = FALSE)
    levels(curve$database) <- .ref_assoc_db_levels(short = TRUE)
    curve$index <- factor(as.character(curve$index), levels = c(ia, ib))
    n_db <- length(unique(as.character(curve$database)))
    single_db <- n_db <= 1L
    # 顺序：主库 A|B，再外验 A|B（2×2）
    strip_ord <- unique(as.character(
      strip_df$strip[order(
        match(strip_df$db_ord, c("MIMIC-IV", "eICU")),
        match(strip_df$index, c(ia, ib))
      )]
    ))
    curve$strip <- factor(as.character(curve$strip), levels = strip_ord)
    plt <- ggplot2::ggplot(
      curve,
      ggplot2::aes(x = value, y = hr, colour = stratum, fill = stratum)
    ) +
      ggplot2::geom_ribbon(
        ggplot2::aes(ymin = conf_low, ymax = conf_high),
        alpha = 0.15, linewidth = 0
      ) +
      ggplot2::geom_line(linewidth = 0.85) +
      ggplot2::geom_hline(yintercept = 1, linetype = 2, colour = "grey40",
                          linewidth = 0.35) +
      ggplot2::scale_x_continuous(
        labels = scales::label_comma(),
        breaks = scales::pretty_breaks(n = 4L)
      ) +
      ggplot2::coord_cartesian(ylim = c(0.4, NA), expand = TRUE, clip = "off") +
      ggplot2::labs(
        x = "Exposure", y = "Adjusted HR (95% CI)",
        colour = NULL, fill = NULL
      ) +
      ggplot2::theme_classic(base_family = if (exists("resolve_plot_font_family", mode = "function")) resolve_plot_font_family("Times New Roman") else "Times", base_size = if (single_db) 11 else 10) +
      ggplot2::theme(
        legend.position = if (overall_only) "none" else "bottom",
        panel.grid.minor = ggplot2::element_blank(),
        plot.margin = ggplot2::margin(8, 12, 8, 8),
        strip.background = ggplot2::element_blank(),
        strip.text = ggplot2::element_text(
          size = if (single_db) 9 else 8.2, face = "bold",
          margin = ggplot2::margin(b = 4)
        ),
        panel.spacing = grid::unit(1.0, "lines")
      ) +
      ggplot2::facet_wrap(~strip, ncol = 2L, scales = "free_x")
    path <- out_pdf
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    pipeline_ggsave_pdf(
      path, plt,
      width = if (single_db) 10.5 else 10.8,
      height = if (single_db) 5.2 else if (overall_only) 7.6 else 8.4
    )
  }
  list(summary = summary, curve = curve, path = path)
}

# --------------------------------------------------------------------------
# Figure 4 + Table S5: ROC (AUC/95%CI + DeLong vs SOSM within panel)
# --------------------------------------------------------------------------

ref_assoc_roc_predictors <- function() {
  c(.ref_ia(), .ref_ib(), "Joint", "APSIII", "OASIS", "GCS")
}

#' Fig4「联合」= 开发集冻结的连续两指标 logistic 线性预测值（非 Group1–4 序号）。
#' 系数仅在 MIMIC development/train 上估计，双库只套用（防外验重拟合泄漏）。
.ref_assoc_fig4_joint_lp_fit <- function(train_df, outcome_cfg, ia, ib) {
  if (!is.data.frame(train_df) || !nrow(train_df)) {
    stop("Fig4 joint LP: train_df 为空。", call. = FALSE)
  }
  need <- c(ia, ib, "fustatus")
  miss <- setdiff(need, names(train_df))
  if (length(miss)) {
    stop("Fig4 joint LP 缺列: ", paste(miss, collapse = ", "), call. = FALSE)
  }
  d <- .ref_assoc_event01(data.frame(train_df), "fustatus", outcome_cfg)
  d$event <- as.integer(d$fustatus)
  x1 <- suppressWarnings(as.numeric(as.character(d[[ia]])))
  x2 <- suppressWarnings(as.numeric(as.character(d[[ib]])))
  ok <- is.finite(x1) & is.finite(x2) & !is.na(d$event)
  if (sum(ok) < 30L || length(unique(d$event[ok])) < 2L) {
    stop("Fig4 joint LP: 开发集事件/样本量不足。", call. = FALSE)
  }
  fit_df <- data.frame(event = d$event[ok], x1 = x1[ok], x2 = x2[ok])
  fit <- stats::glm(event ~ x1 + x2, data = fit_df, family = stats::binomial())
  b <- stats::coef(fit)
  if (any(!is.finite(b)) || length(b) < 3L) {
    stop("Fig4 joint LP: glm 系数非有限。", call. = FALSE)
  }
  list(
    intercept = unname(b[["(Intercept)"]]),
    beta_a = unname(b[["x1"]]),
    beta_b = unname(b[["x2"]]),
    ia = ia,
    ib = ib,
    n_train = nrow(fit_df),
    n_events = sum(fit_df$event == 1L),
    mode = "continuous_logistic_lp"
  )
}

.ref_assoc_fig4_joint_lp_score <- function(df, lp_fit) {
  x1 <- suppressWarnings(as.numeric(as.character(df[[lp_fit$ia]])))
  x2 <- suppressWarnings(as.numeric(as.character(df[[lp_fit$ib]])))
  as.numeric(lp_fit$intercept + lp_fit$beta_a * x1 + lp_fit$beta_b * x2)
}

.ref_assoc_fig4_joint_lab <- function() {
  paste0(.ref_ia_lab(), " + ", .ref_ib_lab(), " (LP)")
}

ref_assoc_fig4_roc <- function(db_frames, cutoff = c(4L, 10L), out_pdf = NULL) {
  if (!requireNamespace("pROC", quietly = TRUE)) {
    stop("Package 'pROC' is required for Figure 4.", call. = FALSE)
  }
  ia <- .ref_ia(); ib <- .ref_ib()
  preds <- ref_assoc_roc_predictors()
  db_frames <- .ref_assoc_order_db_frames(db_frames)
  # 联合连续分：优先 MIMIC train_ref；缺则回退主库分析集（仍只拟合一次）
  train_src <- NULL
  train_cfg <- NULL
  for (db in db_frames) {
    if (!identical(as.character(db$name)[1L], "MIMIC_IV") &&
        !identical(as.character(db$short)[1L], "MIMIC-IV")) next
    if (is.data.frame(db$train_ref) && nrow(db$train_ref)) {
      train_src <- db$train_ref
      train_cfg <- db$outcome_cfg
      break
    }
  }
  if (is.null(train_src)) {
    db0 <- db_frames[[1L]]
    train_src <- db0$data
    train_cfg <- db0$outcome_cfg
    cli::cli_alert_warning(
      "Fig4 joint LP: 无 MIMIC train_ref，回退用 {db0$name} 分析集拟合系数。"
    )
  }
  lp_fit <- .ref_assoc_fig4_joint_lp_fit(train_src, train_cfg, ia, ib)
  cli::cli_alert_info(
    "Fig4 joint LP: {ia}+{ib} on train n={lp_fit$n_train} events={lp_fit$n_events}; coef a={round(lp_fit$beta_a, 4)} b={round(lp_fit$beta_b, 4)}"
  )
  auc_rows <- list()
  curve_rows <- list()
  k <- 0L
  # 原文 Fig.4 = 28天三层(A–C) + 90天三层(D–F) 共 6 面；本课题无 90 天，
  # 双库适配为 2 库 × (Overall + SOFA 三层) = 8 面板（对齐「结局×分层」骨架）。
  stratum_order <- ref_assoc_layer_labels(cutoff)
  for (db in db_frames) {
    d <- .ref_assoc_event01(data.frame(db$data), "fustatus", db$outcome_cfg)
    d$event <- d$fustatus
    d$SOFA_layer <- ref_assoc_sofa_layer(d, cutoff)
    d$Joint <- .ref_assoc_fig4_joint_lp_score(d, lp_fit)
    masks <- .ref_assoc_layer_masks(d, cutoff)
    for (layer_name in stratum_order) {
      if (is.null(masks[[layer_name]])) next
      dd <- d[masks[[layer_name]], , drop = FALSE]
      panel_rows <- list()
      ref_roc <- NULL
      for (pred in preds) {
        k <- k + 1L
        keep <- !is.na(dd[[pred]]) & is.finite(dd[[pred]])
        resp <- as.integer(dd$event[keep])
        value <- as.numeric(dd[[pred]][keep])
        mk <- function(auc_v = NA_real_, lo = NA_real_, hi = NA_real_,
                       p_dl = NA_real_, st = "estimable") {
          data.frame(
            database = db$name, stratum = layer_name, predictor = pred,
            auc = auc_v, ci_low = lo, ci_high = hi, delong_p = p_dl,
            n = sum(keep), events = sum(resp), status = st, panel = k,
            stringsAsFactors = FALSE
          )
        }
        res <- tryCatch({
          if (length(unique(resp)) < 2L || length(unique(value)) < 2L) {
            stop("single-level")
          }
          ro <- pROC::roc(resp, value, direction = "auto", quiet = TRUE)
          ci <- as.numeric(suppressWarnings(
            pROC::ci.auc(ro, conf.level = 0.95, method = "delong",
                         quiet = TRUE)
          ))
          list(ro = ro, auc = as.numeric(pROC::auc(ro)), ci = ci)
        }, error = function(e) NULL)
        if (is.null(res)) {
          panel_rows[[length(panel_rows) + 1L]] <- mk(st = "not_estimable")
          next
        }
        if (identical(pred, ia)) ref_roc <- res$ro
        cc <- pROC::coords(
          res$ro, x = "all", ret = c("specificity", "sensitivity"),
          transpose = FALSE
        )
        curve_rows[[length(curve_rows) + 1L]] <- data.frame(
          fpr = 1 - cc$specificity, tpr = cc$sensitivity,
          database = db$name, stratum = layer_name, predictor = pred,
          panel = k
        )
        panel_rows[[length(panel_rows) + 1L]] <- mk(
          auc_v = res$auc, lo = res$ci[1], hi = res$ci[3]
        )
      }
      pr <- do.call(rbind, panel_rows)
      if (!is.null(ref_roc)) {
        for (i in seq_len(nrow(pr))) {
          if (pr$status[i] != "estimable" || pr$predictor[i] == ia) next
          pr$delong_p[i] <- tryCatch({
            keep <- !is.na(dd[[pr$predictor[i]]]) &
              is.finite(dd[[pr$predictor[i]]])
            other <- pROC::roc(as.integer(dd$event[keep]),
                               as.numeric(dd[[pr$predictor[i]]][keep]),
                               direction = "auto", quiet = TRUE)
            as.numeric(suppressWarnings(
              pROC::roc.test(ref_roc, other, method = "delong",
                             paired = TRUE)$p.value
            ))
          }, error = function(e) NA_real_)
        }
      }
      auc_rows[[length(auc_rows) + 1L]] <- pr
    }
  }
  auc <- do.call(rbind, auc_rows)
  rownames(auc) <- NULL
  curve <- do.call(rbind, curve_rows)
  rownames(curve) <- NULL
  path <- NULL
  if (!is.null(out_pdf)) {
    # 原文 Fig.4：图例仅曲线名（AUC→Table S5）；无 90 天/糖代谢层时，
    # 双库 Overall 分析集 = A/B 两面（对齐 Fig2/3，禁 ML train/val 分面）
    pred_lv <- preds
    pred_labs <- .ref_disp(pred_lv)
    pred_labs[pred_lv == "Joint"] <- .ref_assoc_fig4_joint_lab()
    curve$database <- .ref_assoc_factor_db(curve$database, short = FALSE)
    levels(curve$database) <- .ref_assoc_db_levels(short = TRUE)
    curve$stratum <- factor(curve$stratum, levels = stratum_order)
    curve$predictor <- factor(curve$predictor, levels = pred_lv)
    overall_only <- length(stratum_order) == 1L &&
      identical(as.character(stratum_order), "Overall")
    n_db <- length(unique(as.character(curve$database)))
    single_db <- n_db <= 1L
    # 原文配色感：多条 ROC；Dark2 可读
    .roc_one <- function(cv, letter_lab) {
      ggplot2::ggplot(
        cv, ggplot2::aes(x = fpr, y = tpr, colour = predictor)
      ) +
        ggplot2::geom_abline(linetype = 2, colour = "grey55",
                             linewidth = 0.35) +
        ggplot2::geom_line(linewidth = 0.9) +
        ggplot2::scale_colour_brewer(
          palette = "Dark2", breaks = pred_lv, labels = pred_labs
        ) +
        ggplot2::coord_equal(xlim = c(0, 1), ylim = c(0, 1), expand = FALSE,
                             clip = "off") +
        ggplot2::labs(
          x = "1 - Specificity", y = "Sensitivity", colour = NULL,
          title = letter_lab
        ) +
        ggplot2::theme_classic(base_family = if (exists("resolve_plot_font_family", mode = "function")) resolve_plot_font_family("Times New Roman") else "Times", base_size = 11) +
        ggplot2::theme(
          legend.position = c(0.98, 0.02),
          legend.justification = c(1, 0),
          legend.background = ggplot2::element_rect(
            fill = scales::alpha("white", 0.75), colour = NA
          ),
          legend.key.width = grid::unit(0.7, "cm"),
          legend.key.height = grid::unit(0.28, "cm"),
          legend.text = ggplot2::element_text(size = 7.5),
          legend.margin = ggplot2::margin(2, 2, 2, 2),
          plot.title = ggplot2::element_text(
            size = 12, face = "bold", hjust = 0,
            margin = ggplot2::margin(b = 2)
          ),
          axis.title = ggplot2::element_text(size = 10),
          axis.text = ggplot2::element_text(size = 9),
          plot.margin = ggplot2::margin(6, 10, 6, 8)
        ) +
        ggplot2::guides(
          colour = ggplot2::guide_legend(ncol = 1L, override.aes = list(linewidth = 1))
        )
    }
    path <- out_pdf
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    if (isTRUE(overall_only) && !single_db &&
        requireNamespace("patchwork", quietly = TRUE)) {
      db_ord <- levels(curve$database)
      db_ord <- db_ord[db_ord %in% unique(as.character(curve$database))]
      plts <- lapply(seq_along(db_ord), function(i) {
        dbn <- db_ord[[i]]
        cv <- curve[as.character(curve$database) == dbn, , drop = FALSE]
        .roc_one(cv, paste0(LETTERS[[i]], "  ", dbn))
      })
      plt <- patchwork::wrap_plots(plts, nrow = 1)
      pipeline_ggsave_pdf(path, plt, width = 11.2, height = 5.4)
    } else {
      plt <- ggplot2::ggplot(
        curve, ggplot2::aes(x = fpr, y = tpr, colour = predictor)
      ) +
        ggplot2::geom_abline(linetype = 2, colour = "grey55",
                             linewidth = 0.35) +
        ggplot2::geom_line(linewidth = 0.85) +
        ggplot2::scale_colour_brewer(
          palette = "Dark2", breaks = pred_lv, labels = pred_labs
        ) +
        ggplot2::coord_equal(xlim = c(0, 1), ylim = c(0, 1), expand = TRUE,
                             clip = "off") +
        ggplot2::labs(
          x = "1 - Specificity", y = "Sensitivity", colour = NULL
        ) +
        ggplot2::theme_classic(base_family = if (exists("resolve_plot_font_family", mode = "function")) resolve_plot_font_family("Times New Roman") else "Times", base_size = if (single_db) 11 else 8) +
        ggplot2::theme(
          legend.position = "bottom",
          legend.direction = "horizontal",
          legend.key.width = grid::unit(1.05, "cm"),
          panel.grid.minor = ggplot2::element_blank(),
          strip.background = ggplot2::element_blank(),
          strip.text = ggplot2::element_text(face = "bold"),
          plot.margin = ggplot2::margin(10, 14, 12, 10)
        ) +
        ggplot2::guides(colour = ggplot2::guide_legend(nrow = 2L, byrow = TRUE))
      if (!single_db) {
        plt <- if (overall_only) {
          plt + ggplot2::facet_wrap(~database, ncol = 2)
        } else {
          plt + ggplot2::facet_grid(database ~ stratum)
        }
      } else if (!overall_only) {
        plt <- plt + ggplot2::facet_wrap(~stratum, ncol = 2)
      }
      pipeline_ggsave_pdf(
        path, plt,
        width = if (single_db && overall_only) 7.4 else if (overall_only) 8.4 else 12,
        height = if (single_db && overall_only) 7.0 else if (overall_only) 5.0 else 7.4
      )
    }
  }
  list(auc = auc, curve = curve, path = path, joint_lp = lp_fit)
}

# --------------------------------------------------------------------------
# Figure 5: landmark lock from MIMIC development; eICU only applies
# --------------------------------------------------------------------------

ref_assoc_fig5_landmark <- function(train_aug, mimic_analysis, eicu_analysis,
                                    provenance, outcome_cfg, covariates,
                                    cutoff = c(4L, 10L), alpha = 0.05,
                                    joint_lock = NULL,
                                    out_pdf = NULL,
                                    force_landmark_day = NULL,
                                    force_landmark_stratum = "Overall") {
  covs <- intersect(covariates, names(train_aug))
  covs <- setdiff(covs, c(.ref_ia(), .ref_ib(), "SOFA", "JointGroup",
                          "Joint_score", "Group", "ID"))
  locked_spec <- reference_ph_landmark_lock(list(
    data = train_aug,
    time = "futime", event = "fustatus",
    exposure = "Joint_score", stratum = "SOFA_layer",
    covariates = covs, outcome_cfg = outcome_cfg,
    provenance = provenance, max_day = 28
  ), alpha = alpha)
  ## 课题可硬锁 landmark 日（如 Methods 指定 day 3）；仍保留 scan 供脚注对照
  fd <- suppressWarnings(as.numeric(force_landmark_day)[1L])
  if (is.finite(fd) && fd > 0 && fd < 28) {
    layer <- as.character(force_landmark_stratum %||% "Overall")[1L]
    if (!nzchar(layer)) layer <- "Overall"
    locked_spec$landmark_times <- stats::setNames(fd, layer)
    locked_spec$strata <- layer
    locked_spec$forced_landmark <- TRUE
    locked_spec$forced_landmark_day <- fd
  } else if (!length(locked_spec$landmark_times)) {
    ## 无 PH 违反层：不静默 invent day；用 Overall 扫描候选日并标注 exploratory
    sc <- locked_spec$scan
    ov <- if (is.data.frame(sc) && nrow(sc)) {
      sc[sc$status == "estimable" & as.character(sc$stratum) == "Overall",
         , drop = FALSE]
    } else {
      sc[FALSE, , drop = FALSE]
    }
    if (!nrow(ov)) {
      ov <- if (is.data.frame(sc)) {
        sc[sc$status == "estimable" & is.finite(sc$landmark_time), , drop = FALSE]
      } else {
        data.frame()
      }
      if (nrow(ov)) {
        ov <- ov[which.min(ov$exposure_p), , drop = FALSE]
      }
    }
    if (nrow(ov) && is.finite(ov$landmark_time[[1L]])) {
      layer <- as.character(ov$stratum[[1L]])
      locked_spec$landmark_times <- stats::setNames(
        as.numeric(ov$landmark_time[[1L]]), layer
      )
      locked_spec$strata <- layer
      locked_spec$exploratory_no_ph_violation <- TRUE
      ## 避免 reference_apply_landmark 重扫（无违反层）判定为 tamper
      locked_spec$forced_landmark <- TRUE
      locked_spec$forced_landmark_day <- as.numeric(ov$landmark_time[[1L]])
      locked_spec$landmark_method_note <- as.character(
        ov$landmark_method[[1L]] %||% "scan_fallback"
      )
    }
  }

  fit_rows <- function(db_name, d) {
    d <- data.frame(d)
    d$row_id <- seq_len(nrow(d))
    # 分析帧若未携带冻结派生列，则按同一 cutoff / 冻结 joint lock 现场派生
    if (!"SOFA_layer" %in% names(d)) {
      d$SOFA_layer <- ref_assoc_sofa_layer(d, cutoff)
    }
    if (!"Joint_score" %in% names(d)) {
      if (is.null(joint_lock)) {
        stop("Figure 5: analysis frame lacks Joint_score and no joint lock was supplied.",
             call. = FALSE)
      }
      d$Joint_score <- as.numeric(
        reference_apply_joint_tertiles(d, joint_lock)$group
      )
    }
    minimal <- d[, c("row_id", "futime", "fustatus", "SOFA_layer"),
                 drop = FALSE]
    seg <- reference_apply_landmark(minimal, locked_spec)
    attr(seg, "locked_source") <- NULL
    attr(seg, "locked_spec") <- NULL
    ex <- d[, c("row_id", "Joint_score", covs), drop = FALSE]
    seg <- merge(seg, ex, by = "row_id", all.x = TRUE, sort = FALSE)
    rows <- list()
    k <- 0L
    strata <- unique(as.character(seg$SOFA_layer))
    strata <- strata[!is.na(strata)]
    for (stratum in strata) {
      for (segment in unique(as.character(
        seg$segment[as.character(seg$SOFA_layer) == stratum]
      ))) {
        k <- k + 1L
        dd <- seg[as.character(seg$SOFA_layer) == stratum &
                    as.character(seg$segment) == segment, , drop = FALSE]
        dd <- dd[stats::complete.cases(
          dd[, c("start", "stop", "event", "Joint_score", covs)]
        ), , drop = FALSE]
        lm_time <- unique(dd$landmark_time)
        lm_time <- if (length(lm_time)) lm_time[[1]] else NA_real_
        ok <- nrow(dd) >= 10L && sum(dd$event == 1L) >= 1L &&
          length(unique(dd$Joint_score)) >= 2L
        if (!ok) {
          rows[[k]] <- data.frame(
            database = db_name, stratum = stratum, segment = segment,
            hr = NA_real_, conf_low = NA_real_, conf_high = NA_real_,
            p = NA_real_, n = nrow(dd), events = sum(dd$event == 1L),
            landmark_time = lm_time, status = "not_estimable",
            stringsAsFactors = FALSE
          )
          next
        }
        form <- if (length(covs)) {
          stats::as.formula(sprintf(
            "survival::Surv(start, stop, event) ~ Joint_score + %s",
            paste(.reference_bt(covs), collapse = " + ")
          ))
        } else {
          stats::as.formula("survival::Surv(start, stop, event) ~ Joint_score")
        }
        fit <- tryCatch(survival::coxph(form, data = dd),
                        error = function(e) NULL)
        if (is.null(fit) || anyNA(stats::coef(fit))) {
          rows[[k]] <- data.frame(
            database = db_name, stratum = stratum, segment = segment,
            hr = NA_real_, conf_low = NA_real_, conf_high = NA_real_,
            p = NA_real_, n = nrow(dd), events = sum(dd$event == 1L),
            landmark_time = lm_time, status = "not_estimable",
            stringsAsFactors = FALSE
          )
          next
        }
        hits <- .reference_term_coefficients(fit, "Joint_score")
        ci <- stats::confint(fit)
        z <- summary(fit)$coefficients[hits[[1L]], "z"]
        rows[[k]] <- data.frame(
          database = db_name, stratum = stratum, segment = segment,
          hr = unname(exp(stats::coef(fit)[hits[[1L]]])),
          conf_low = unname(exp(ci[hits[[1L]], 1L])),
          conf_high = unname(exp(ci[hits[[1L]], 2L])),
          p = unname(2 * stats::pnorm(-abs(z))),
          n = nrow(dd), events = sum(dd$event == 1L),
          landmark_time = lm_time, status = "estimable",
          stringsAsFactors = FALSE
        )
      }
    }
    out <- do.call(rbind, rows)
    rownames(out) <- NULL
    out
  }

  res_parts <- list(
    fit_rows("MIMIC_IV", .ref_assoc_event01(mimic_analysis, "fustatus",
                                            outcome_cfg))
  )
  if (!is.null(eicu_analysis) && is.data.frame(eicu_analysis) &&
      nrow(eicu_analysis) > 0L) {
    res_parts[[length(res_parts) + 1L]] <- fit_rows(
      "eICU", .ref_assoc_event01(eicu_analysis, "fustatus", outcome_cfg)
    )
  }
  res <- do.call(rbind, res_parts)
  res$segment <- factor(res$segment, levels = c("before", "after", "all"))

  # ---- Figure 5 plot: 原文式单轴联合 landmark KM ----
  # 同一 Time 轴；竖线分界；左侧 0→L 删失，右侧 L 起条件存活重置到 1；
  # 图例 Low/High A × Low/High B（对齐原文 SHR/GV）；双库各一行。
  path <- NULL
  if (!is.null(out_pdf)) {
    ia <- .ref_ia(); ib <- .ref_ib()
    locked_layer <- names(locked_spec$landmark_times)[1L]
    locked_day <- suppressWarnings(as.numeric(locked_spec$landmark_times[[1L]]))
    if (is.null(locked_layer) || !nzchar(locked_layer) || !is.finite(locked_day)) {
      hit <- res[res$status == "estimable" &
                   is.finite(res$landmark_time), , drop = FALSE]
      if (nrow(hit)) {
        locked_layer <- as.character(hit$stratum[[1L]])
        locked_day <- as.numeric(hit$landmark_time[[1L]])
      } else {
        stop(
          "Figure 5: no PH-derived landmark day (scan empty). ",
          "Refuse silent day-3/day-4 fallback.",
          call. = FALSE
        )
      }
    }
    locked_day <- max(1, min(as.numeric(locked_day), 21))
    lock_subtitle_extra <- if (isTRUE(locked_spec$exploratory_no_ph_violation)) {
      " (no PH violation at α=0.05; day from Schoenfeld β scan)"
    } else if (isTRUE(locked_spec$forced_landmark)) {
      " (forced)"
    } else {
      ""
    }
    ia_lab <- .ref_ia_lab(); ib_lab <- .ref_ib_lab()
    grp_levels <- c(
      paste0("Low ", ia_lab, " + Low ", ib_lab),
      paste0("Low ", ia_lab, " + High ", ib_lab),
      paste0("High ", ia_lab, " + Low ", ib_lab),
      paste0("High ", ia_lab, " + High ", ib_lab)
    )
    # Group1=双低, Group2=仅A高, Group3=仅B高, Group4=双高 → 图例序同原文
    map_g <- c(
      "Group1" = grp_levels[[1]],
      "Group3" = grp_levels[[2]],
      "Group2" = grp_levels[[3]],
      "Group4" = grp_levels[[4]]
    )
    grp_cols <- c(
      "#E41A1C", "#377EB8", "#FF7F00", "#4DAF4A"
    )
    names(grp_cols) <- grp_levels

    build_km_src <- function(db_name, d) {
      d <- data.frame(d)
      if (!"SOFA_layer" %in% names(d)) {
        d$SOFA_layer <- ref_assoc_sofa_layer(d, cutoff)
      }
      if (!"JointGroup" %in% names(d)) {
        if (is.null(joint_lock)) {
          stop("Figure 5 KM needs JointGroup or joint_lock.", call. = FALSE)
        }
        jt <- reference_apply_joint_tertiles(d, joint_lock)
        d$JointGroup <- factor(paste0("Group", as.integer(jt$group)),
                               levels = paste0("Group", 1:4))
      }
      d <- .ref_assoc_event01(d, "fustatus", outcome_cfg)
      d$T <- suppressWarnings(as.numeric(d$futime))
      d$D <- as.integer(d$fustatus)
      if (!identical(locked_layer, "Overall")) {
        d <- d[as.character(d$SOFA_layer) == locked_layer, , drop = FALSE]
      }
      d <- d[is.finite(d$T) & !is.na(d$D) & !is.na(d$JointGroup), , drop = FALSE]
      d$group_lab <- factor(unname(map_g[as.character(d$JointGroup)]),
                            levels = grp_levels)
      d <- d[!is.na(d$group_lab), , drop = FALSE]
      list(db = db_name, data = d)
    }
    km_curve_one <- function(dd, segment, t_offset = 0) {
      if (!nrow(dd) || length(unique(dd$group_lab)) < 2L) {
        return(list(curve = NULL, p = NA_real_))
      }
      fit <- tryCatch(
        survival::survfit(survival::Surv(T, D) ~ group_lab, data = dd),
        error = function(e) NULL
      )
      if (is.null(fit)) return(list(curve = NULL, p = NA_real_))
      sdf <- tryCatch(broom::tidy(fit), error = function(e) NULL)
      if (is.null(sdf)) {
        strata_n <- if (is.null(fit$strata)) length(fit$time) else fit$strata
        labs <- sub("^group_lab=", "", names(strata_n))
        if (is.null(fit$strata)) labs <- levels(dd$group_lab)[1]
        cum_n <- 0L
        rows <- list()
        for (si in seq_along(strata_n)) {
          n_i <- as.integer(strata_n[[si]])
          ii <- (cum_n + 1L):(cum_n + n_i)
          cum_n <- cum_n + n_i
          rows[[si]] <- data.frame(
            time = fit$time[ii] + t_offset, surv = fit$surv[ii],
            group = labs[[si]], segment = segment,
            stringsAsFactors = FALSE
          )
        }
        curve <- do.call(rbind, rows)
      } else {
        curve <- data.frame(
          time = sdf$time + t_offset, surv = sdf$estimate,
          group = sub("^group_lab=", "", as.character(sdf$strata)),
          segment = segment, stringsAsFactors = FALSE
        )
      }
      # 原文 Fig5：before 从 (0,1) 起；after 在 landmark 处从 S=1 重置
      if (identical(segment, "before")) {
        starts <- data.frame(
          time = 0, surv = 1,
          group = unique(as.character(curve$group)),
          segment = segment, stringsAsFactors = FALSE
        )
        curve <- rbind(starts, curve)
        curve <- curve[order(curve$group, curve$time), , drop = FALSE]
      } else if (identical(segment, "after") && t_offset > 0) {
        starts <- data.frame(
          time = t_offset, surv = 1,
          group = unique(as.character(curve$group)),
          segment = segment, stringsAsFactors = FALSE
        )
        curve <- rbind(starts, curve)
        curve <- curve[order(curve$group, curve$time), , drop = FALSE]
      }
      lr <- tryCatch(
        survival::survdiff(survival::Surv(T, D) ~ group_lab, data = dd),
        error = function(e) NULL
      )
      p <- if (!is.null(lr)) {
        1 - stats::pchisq(lr$chisq, length(lr$n) - 1L)
      } else NA_real_
      list(curve = curve, p = p)
    }

    curve_rows <- list()
    p_ann <- list()
    src_list <- list(build_km_src("MIMIC-IV", mimic_analysis))
    if (!is.null(eicu_analysis) && is.data.frame(eicu_analysis) &&
        nrow(eicu_analysis) > 0L) {
      src_list[[length(src_list) + 1L]] <- build_km_src("eICU", eicu_analysis)
    }
    for (src in src_list) {
      d <- src$data
      if (!nrow(d)) next
      # Before：标准 landmark 左段——活过 L 者在 L 删失（只反映真实早死）
      # 禁止把存活者改成事件硬拽到 S=0：早死稀少时会出现「贴1再垂直掉0」假断崖。
      # （原文左段缓降至近0，是其 Pre-DM 队列前几天死亡密集，不是这种假编码。）
      bef <- d[, c("T", "D", "group_lab"), drop = FALSE]
      bef$D <- ifelse(bef$T > locked_day, 0L, bef$D)
      bef$T <- pmin(bef$T, locked_day)
      r0 <- km_curve_one(bef, "before", t_offset = 0)
      if (!is.null(r0$curve)) {
        r0$curve$database <- src$db
        curve_rows[[length(curve_rows) + 1L]] <- r0$curve
      }
      p_ann[[length(p_ann) + 1L]] <- data.frame(
        database = src$db, segment = "before", p_lr = r0$p,
        stringsAsFactors = FALSE
      )
      # After: 存活过 landmark；相对时间再平移回绝对轴
      aft <- d[d$T > locked_day, c("T", "D", "group_lab"), drop = FALSE]
      aft$T <- aft$T - locked_day
      r1 <- km_curve_one(aft, "after", t_offset = locked_day)
      if (!is.null(r1$curve)) {
        r1$curve$database <- src$db
        curve_rows[[length(curve_rows) + 1L]] <- r1$curve
      }
      p_ann[[length(p_ann) + 1L]] <- data.frame(
        database = src$db, segment = "after", p_lr = r1$p,
        stringsAsFactors = FALSE
      )
    }
    cdf <- if (length(curve_rows)) do.call(rbind, curve_rows) else NULL
    if (!is.null(cdf) && nrow(cdf)) {
      cdf$group <- factor(as.character(cdf$group), levels = grp_levels)
      db_lv <- intersect(c("MIMIC-IV", "eICU"), unique(as.character(cdf$database)))
      cdf$database <- factor(as.character(cdf$database), levels = db_lv)
      single_db <- length(db_lv) <= 1L
      ann <- do.call(rbind, p_ann)
      ann$lab <- paste0(
        "P = ", ifelse(is.na(ann$p_lr), "NE", pub_format_p_cell(ann$p_lr))
      )
      # 标注位置对齐原文：before 左下；after 右段中部
      xmax <- max(c(cdf$time, 28), na.rm = TRUE)
      ## 原文 Fig5 横轴：0–landmark 约占 30% 宽度（线性轴会把左段挤扁）
      w_left <- 0.32
      .fig5_xmap <- function(t, L = locked_day, X = xmax, w = w_left) {
        t <- as.numeric(t)
        ifelse(
          t <= L,
          (pmax(t, 0) / L) * w * X,
          w * X + ((t - L) / max(X - L, 1e-6)) * (1 - w) * X
        )
      }
      ann$x <- ifelse(
        ann$segment == "before",
        .fig5_xmap(locked_day * 0.12),
        .fig5_xmap(locked_day + (xmax - locked_day) * 0.35)
      )
      ann$y <- ifelse(ann$segment == "before", 0.10, 0.55)
      ann$database <- factor(as.character(ann$database),
                             levels = levels(cdf$database))
      ## 原文 Fig5：before / after 必须分两条 geom_step，禁止拼成一条
      ## （否则 before 终点 S=0 与 after 起点 S=1 被 step 直接接上，左段断崖消失）
      cdf_bef <- cdf[as.character(cdf$segment) == "before", , drop = FALSE]
      cdf_aft <- cdf[as.character(cdf$segment) == "after", , drop = FALSE]
      cdf_bef$xplot <- .fig5_xmap(cdf_bef$time)
      cdf_aft$xplot <- .fig5_xmap(cdf_aft$time)
      x_breaks <- sort(unique(c(0, locked_day, 10, 20, 28)))
      x_breaks <- x_breaks[x_breaks <= xmax + 1e-9]
      plt <- ggplot2::ggplot() +
        ggplot2::geom_step(
          data = cdf_bef,
          ggplot2::aes(x = xplot, y = surv, colour = group),
          linewidth = 0.85
        ) +
        ggplot2::geom_step(
          data = cdf_aft,
          ggplot2::aes(x = xplot, y = surv, colour = group),
          linewidth = 0.85
        ) +
        ggplot2::geom_vline(
          xintercept = .fig5_xmap(locked_day), linetype = 2, colour = "grey40",
          linewidth = 0.45
        ) +
        ggplot2::geom_text(
          data = ann, ggplot2::aes(x = x, y = y, label = lab),
          inherit.aes = FALSE, hjust = 0,
          size = if (single_db) 3.4 else 2.8, colour = "black"
        ) +
        ggplot2::coord_cartesian(ylim = c(0, 1), xlim = c(0, .fig5_xmap(xmax))) +
        ggplot2::scale_colour_manual(
          values = grp_cols, breaks = grp_levels, drop = FALSE,
          limits = grp_levels
        ) +
        ggplot2::scale_x_continuous(
          breaks = .fig5_xmap(x_breaks),
          labels = as.character(as.integer(x_breaks)),
          expand = ggplot2::expansion(mult = c(0.01, 0.02))
        ) +
        ggplot2::labs(
          x = "Time (day)", y = "Survival Probability", colour = NULL,
          title = paste0(
            "Figure 5. Landmark survival analysis of ", .ref_joint_lab(),
            " groups"
          ),
          subtitle = sprintf(
            "Landmark locked in MIMIC-IV: %s, day %s (dashed line)%s",
            locked_layer, as.integer(locked_day), lock_subtitle_extra
          )
        ) +
        ggplot2::theme_classic(base_family = if (exists("resolve_plot_font_family", mode = "function")) resolve_plot_font_family("Times New Roman") else "Times", base_size = if (single_db) 11 else 9) +
        ggplot2::theme(
          legend.position = "bottom",
          legend.direction = "horizontal",
          legend.key.height = grid::unit(0.45, "lines"),
          legend.key.width = grid::unit(1.2, "lines"),
          legend.text = ggplot2::element_text(size = if (single_db) 8.5 else 7),
          legend.margin = ggplot2::margin(0, 0, 0, 0),
          plot.title = ggplot2::element_text(
            size = if (single_db) 11 else 10, face = "bold"
          ),
          plot.subtitle = ggplot2::element_text(size = if (single_db) 9 else 7.5),
          panel.grid.minor = ggplot2::element_blank(),
          strip.text = ggplot2::element_text(face = "bold", size = 9),
          strip.background = ggplot2::element_blank()
        ) +
        ggplot2::guides(colour = ggplot2::guide_legend(nrow = 2L, byrow = TRUE))
      if (!single_db) {
        plt <- plt + ggplot2::facet_wrap(~database, ncol = 2L, scales = "fixed")
      }
      path <- out_pdf
      dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
      pipeline_ggsave_pdf(
        path, plt,
        width = if (single_db) 7.2 else 11,
        height = if (single_db) 5.4 else 4.6
      )
    }
  }
  list(
    results = res, path = path, locked_spec = locked_spec,
    scan = locked_spec$scan, covariates = covs,
    mimic = list(landmark_times = locked_spec$landmark_times,
                 database = "MIMIC_IV"),
    eicu = list(landmark_times = locked_spec$landmark_times,
                database = "eICU")
  )
}

# --------------------------------------------------------------------------
# Figure 6: clinical-subgroup forest (prefer Model3; fallback Age+Sex),
#   highest vs lowest tertile. Panels = databases x indices.
#   Rows = Overall + each clinical subgroup level; per-subgroup P-interaction
# --------------------------------------------------------------------------

#' 双库共有的临床亚组变量（Age 二分类 <65/>=65；其余为二值/因子水平）。
ref_assoc_fig6_subgroups <- c(
  "Age", "Gender", "Race", "Hypertension", "Diabetes", "CKD",
  "Ventilation", "Heart_Failure", "COPD", "Cancer", "Myocardial_Infarction"
)

#' 每层拟合 Cox（index 为 .ex 数值列）；调用方传入 Model3 或 Age+Sex covs。
.ref_assoc_fig6_stratum_hr <- function(dd, index, covs, time, event, cfg) {
  need <- unique(c(time, event, index, covs))
  dd <- dd[, intersect(need, names(dd)), drop = FALSE]
  dd <- .ref_assoc_event01(dd, event, cfg)
  dd[[time]] <- suppressWarnings(as.numeric(as.character(dd[[time]])))
  dd <- dd[stats::complete.cases(dd), , drop = FALSE]
  ok <- nrow(dd) >= 10L && sum(dd[[event]] == 1L) >= 2L &&
    length(unique(as.character(dd[[index]]))) >= 2L
  if (!ok) {
    return(list(hr = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_,
                n = nrow(dd), events = sum(dd[[event]] == 1L),
                status = "not_estimable"))
  }
  cv <- setdiff(intersect(covs, names(dd)), index)
  form <- stats::as.formula(sprintf(
    "survival::Surv(`%s`, `%s`) ~ `%s` + %s",
    time, event, index,
    if (length(cv)) paste(.reference_bt(cv), collapse = " + ") else "1"
  ))
  fit <- tryCatch(survival::coxph(form, data = dd), error = function(e) NULL)
  if (is.null(fit) || anyNA(stats::coef(fit))) {
    return(list(hr = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_,
                n = nrow(dd), events = sum(dd[[event]] == 1L),
                status = "not_estimable"))
  }
  hits <- .reference_term_coefficients(fit, index)
  if (!length(hits)) {
    return(list(hr = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_,
                n = nrow(dd), events = sum(dd[[event]] == 1L),
                status = "not_estimable"))
  }
  ci <- stats::confint(fit)
  z <- summary(fit)$coefficients[hits[[1L]], "z"]
  list(hr = unname(exp(stats::coef(fit)[hits[[1L]]])),
       lo = unname(exp(ci[hits[[1L]], 1L])),
       hi = unname(exp(ci[hits[[1L]], 2L])),
       p = unname(2 * stats::pnorm(-abs(z))),
       n = nrow(dd), events = sum(dd[[event]] == 1L), status = "estimable")
}

#' 亚组交互 P 值：exposure*subgroup 的 LRT（subgroup 为 .ex 之外的分层列）。
.ref_assoc_fig6_interaction_p <- function(dd, index, subgroup, covs, time, event, cfg) {
  dd <- dd[!is.na(dd[[subgroup]]) & nzchar(as.character(dd[[subgroup]])), , drop = FALSE]
  dd$.sg <- as.factor(as.character(dd[[subgroup]]))
  if (nlevels(dd$.sg) < 2L) return(NA_real_)
  cv <- setdiff(intersect(covs, names(dd)), c(index, subgroup))
  base <- stats::as.formula(sprintf(
    "survival::Surv(`%s`, `%s`) ~ `%s` + .sg + %s", time, event, index,
    if (length(cv)) paste(.reference_bt(cv), collapse = " + ") else "1"
  ))
  full <- stats::as.formula(sprintf(
    "survival::Surv(`%s`, `%s`) ~ `%s` * .sg + %s", time, event, index,
    if (length(cv)) paste(.reference_bt(cv), collapse = " + ") else "1"
  ))
  f0 <- tryCatch(survival::coxph(base, data = dd), error = function(e) NULL)
  f1 <- tryCatch(survival::coxph(full, data = dd), error = function(e) NULL)
  if (is.null(f0) || is.null(f1) || anyNA(stats::coef(f1))) return(NA_real_)
  tryCatch({
    a <- stats::anova(f0, f1, test = "LRT")
    # anova.coxph 的 p 值列名随版本/参数变化（p / P / Pr(>)）；取最后一行、
    # 首个可解析为数值的 p 列，保证恒返回长度 1（缺失记 NA，绝不返回长度 0）。
    pcol <- intersect(
      c("p", "P", "Pr(>)", "Pr(>Chisq)", "Pr(>|Chi|)", "P(>|Chi|)"),
      colnames(a)
    )
    if (!length(pcol)) return(NA_real_)
    pv <- suppressWarnings(as.numeric(a[nrow(a), pcol[[1L]]]))
    if (length(pv) != 1L || is.na(pv)) NA_real_ else pv
  }, error = function(e) NA_real_)
}

ref_assoc_fig6_forest <- function(db_frames, cutoff = c(4L, 10L), out_pdf = NULL) {
  ia <- .ref_ia(); ib <- .ref_ib(); ilab <- .ref_ilab()
  rows <- list()
  k <- 0L
  sub_vars <- ref_assoc_fig6_subgroups
  for (db in db_frames) {
    d <- .ref_assoc_event01(data.frame(db$data), "fustatus", db$outcome_cfg)
    d$event <- d$fustatus
    d$futime <- suppressWarnings(as.numeric(as.character(d$futime)))
    models <- .ref_assoc_resolve_db_models(db, d)
    age_sex_nm <- .ref_assoc_age_sex_model_name(models)
    full_nm <- .ref_assoc_full_model_name(models)
    m_agesex <- models[[age_sex_nm]]
    if (!length(m_agesex)) m_agesex <- intersect(c("Age", "Gender", "Sex"), names(d))
    m_full <- models[[full_nm]]
    if (!length(m_full)) m_full <- m_agesex
    for (index in c(ia, ib)) {
      lock <- if (identical(index, ia)) db$sosm_lock else db$wpr_lock
      tert <- .ref_assoc_tertile3(d, index, lock, db$train_ref)
      # 暴露列 .ex = T3(1) vs T1(0)，T2 丢弃
      d$.ex <- as.integer(as.character(tert) == "T3")
      d$.ex[is.na(tert) | as.character(tert) == "T2"] <- NA_integer_
      keep <- !is.na(d$.ex)
      # 与 Table 2/S4 统一：优先全调整 Model3；层内不可估时回退 Age+Sex
      covs_ov <- setdiff(m_full, c(index, "SOFA", "SOFA_layer"))
      ov <- .ref_assoc_fig6_stratum_hr(
        d[keep, , drop = FALSE], ".ex", covs_ov, "futime", "event", db$outcome_cfg
      )
      if (!identical(ov$status, "estimable") && length(m_agesex)) {
        covs_as <- setdiff(m_agesex, c(index, "SOFA", "SOFA_layer"))
        ov2 <- .ref_assoc_fig6_stratum_hr(
          d[keep, , drop = FALSE], ".ex", covs_as, "futime", "event", db$outcome_cfg
        )
        if (identical(ov2$status, "estimable")) ov <- ov2
      }
      k <- k + 1L
      rows[[k]] <- data.frame(
        database = db$name, index = index, subgroup = "Overall", level = "Overall",
        hr = ov$hr, conf_low = ov$lo, conf_high = ov$hi, p = ov$p,
        n = ov$n, events = ov$events, p_interaction = NA_real_,
        status = ov$status, stringsAsFactors = FALSE
      )
      for (sg in sub_vars) {
        if (!sg %in% names(d)) next
        covs <- setdiff(m_full, c(index, "SOFA", "SOFA_layer", sg))
        # Age 二分类 <65 / >=65；其余用原始因子/字符水平
        sg_disp <- d[[sg]]
        if (identical(sg, "Age")) {
          sg_disp <- factor(ifelse(is.na(sg_disp), NA_character_,
                                   ifelse(sg_disp < 65, "< 65", ">= 65")),
                            levels = c("< 65", ">= 65"))
        }
        d$.sgtmp <- sg_disp
        p_int <- .ref_assoc_fig6_interaction_p(
          d[keep, , drop = FALSE], ".ex", ".sgtmp", covs, "futime", "event",
          db$outcome_cfg
        )
        lv <- as.character(d$.sgtmp)
        lv[is.na(lv)] <- ""
        for (lev in unique(lv[nzchar(lv)])) {
          k <- k + 1L
          sel <- keep & nzchar(lv) & lv == lev
          r <- .ref_assoc_fig6_stratum_hr(
            d[sel, , drop = FALSE], ".ex", covs, "futime", "event",
            db$outcome_cfg
          )
          if (!identical(r$status, "estimable") && length(m_agesex)) {
            covs2 <- setdiff(m_agesex, c(index, "SOFA", "SOFA_layer", sg))
            r2 <- .ref_assoc_fig6_stratum_hr(
              d[sel, , drop = FALSE], ".ex", covs2, "futime", "event",
              db$outcome_cfg
            )
            if (identical(r2$status, "estimable")) r <- r2
          }
          rows[[k]] <- data.frame(
            database = db$name, index = index, subgroup = sg, level = lev,
            hr = r$hr, conf_low = r$lo, conf_high = r$hi, p = r$p,
            n = r$n, events = r$events, p_interaction = p_int,
            status = r$status, stringsAsFactors = FALSE
          )
        }
      }
    }
  }
  fr <- do.call(rbind, rows)
  rownames(fr) <- NULL
  note <- if (all(is.na(fr$p_interaction)))
    "P-interaction not estimable in any database/index/subgroup." else ""
  path <- NULL
  if (!is.null(out_pdf)) {
    if (!requireNamespace("forestploter", quietly = TRUE)) {
      warning("Figure 6 needs package forestploter for original-style layout.",
              call. = FALSE)
      return(list(rows = fr, path = NULL, p_interaction_note = note))
    }
    est <- fr[grepl("^estimable", fr$status), , drop = FALSE]
    if (!nrow(est)) {
      warning("Figure 6: no estimable forest rows", call. = FALSE)
      return(list(rows = fr, path = NULL,
                  p_interaction_note = if (nzchar(note)) note else
                    "Figure 6: no estimable subgroup model."))
    }
    # 亚组水平稳定排序（列名保持本课题：Age/Gender/...，非原文 Sex/BMI）
    .fig6_level_order <- function(sg, levs) {
      levs <- unique(as.character(levs))
      if (identical(sg, "Age")) {
        prefer <- c("< 65", ">= 65", "\u2265 65")
        return(unique(c(intersect(prefer, levs), setdiff(levs, prefer))))
      }
      if (sg %in% c("Gender", "Sex")) {
        prefer <- c("Male", "Female", "M", "F")
        return(unique(c(intersect(prefer, levs), setdiff(levs, prefer))))
      }
      yn <- c("No", "Yes", "0", "1", "FALSE", "TRUE")
      if (all(levs %in% yn) || any(levs %in% c("No", "Yes"))) {
        prefer <- c("No", "Yes")
        return(unique(c(intersect(prefer, levs), setdiff(levs, prefer))))
      }
      levs
    }
    # 建成原文样式表：Variable | HR(95% CI) |  | P | P for interaction
    .fig6_panel_df <- function(sub) {
      rows <- list()
      # Overall
      ov <- sub[sub$subgroup == "Overall", , drop = FALSE]
      if (nrow(ov)) {
        o <- ov[1, , drop = FALSE]
        rows[[length(rows) + 1L]] <- data.frame(
          Variable = "Overall",
          `HR (95% CI)` = sprintf(
            "%.2f(%.2f-%.2f)", o$hr, o$conf_low, o$conf_high
          ),
          ` ` = paste(rep(" ", 18L), collapse = ""),
          P = pub_format_p_cell(o$p),
          `P for interaction` = " ",
          `Point Estimate` = o$hr, Lower = o$conf_low, Upper = o$conf_high,
          is_header = FALSE, stringsAsFactors = FALSE,
          check.names = FALSE
        )
      }
      sgs <- unique(as.character(sub$subgroup[sub$subgroup != "Overall"]))
      sgs <- intersect(ref_assoc_fig6_subgroups, sgs)
      # 双库对齐：只保留本面板实际有水平的亚组（外层再交两库共有）
      for (sg in sgs) {
        ss <- sub[sub$subgroup == sg, , drop = FALSE]
        if (!nrow(ss)) next
        p_int <- ss$p_interaction[which(!is.na(ss$p_interaction))[1]]
        rows[[length(rows) + 1L]] <- data.frame(
          Variable = if (exists("pipeline_display_label", mode = "function"))
            pipeline_display_label(sg) else gsub("_", " ", sg, fixed = TRUE),
          `HR (95% CI)` = " ",
          ` ` = paste(rep(" ", 18L), collapse = ""),
          P = " ",
          `P for interaction` = if (is.na(p_int)) " " else
            pub_format_p_cell(p_int),
          `Point Estimate` = NA_real_, Lower = NA_real_, Upper = NA_real_,
          is_header = TRUE, stringsAsFactors = FALSE,
          check.names = FALSE
        )
        lev_ord <- .fig6_level_order(sg, ss$level)
        for (lev in lev_ord) {
          rr <- ss[as.character(ss$level) == lev, , drop = FALSE]
          if (!nrow(rr)) next
          r <- rr[1, , drop = FALSE]
          ok <- is.finite(r$hr) && is.finite(r$conf_low) && is.finite(r$conf_high) &&
            r$hr > 0 && r$conf_low > 0
          rows[[length(rows) + 1L]] <- data.frame(
            Variable = paste0("  ", lev),
            `HR (95% CI)` = if (ok) sprintf(
              "%.2f(%.2f-%.2f)", r$hr, r$conf_low, r$conf_high
            ) else "NE",
            ` ` = paste(rep(" ", 18L), collapse = ""),
            P = if (ok) pub_format_p_cell(r$p) else " ",
            `P for interaction` = " ",
            `Point Estimate` = if (ok) r$hr else NA_real_,
            Lower = if (ok) r$conf_low else NA_real_,
            Upper = if (ok) r$conf_high else NA_real_,
            is_header = FALSE, stringsAsFactors = FALSE,
            check.names = FALSE
          )
        }
      }
      do.call(rbind, rows)
    }
    .fig6_one_forest <- function(plot_df) {
      ci_lab <- "HR (95% CI)"
      disp <- plot_df[, c("Variable", ci_lab, " ", "P", "P for interaction"),
                      drop = FALSE]
      # 展示层禁下划线（Age_Group → Age Group 等）
      if (exists("pipeline_display_label", mode = "function")) {
        disp$Variable <- pipeline_display_label(as.character(disp$Variable))
      } else {
        disp$Variable <- gsub("_", " ", as.character(disp$Variable), fixed = TRUE)
      }
      .ff <- if (exists("resolve_plot_font_family", mode = "function")) {
        resolve_plot_font_family("Times New Roman")
      } else {
        "Times"
      }
      tm <- forestploter::forest_theme(
        base_size = 9,
        refline_gp = grid::gpar(col = "grey50", lty = 2, lwd = 1, fontfamily = .ff),
        ci_pch = 15, ci_col = "#2C7BB6", ci_fill = "#2C7BB6",
        ci_lty = 1, ci_lwd = 1.4, ci_Theight = 0.18,
        core = list(
          fg_params = list(hjust = 0, x = 0.01, fontfamily = .ff),
          bg_params = list(fill = c("#ffffff", "#f7f7f7"))
        ),
        xlab_gp = grid::gpar(fontsize = 9, fontfamily = .ff),
        ticks_gp = grid::gpar(fontsize = 8, fontfamily = .ff)
      )
      xlim <- c(0.2, 4)
      est <- plot_df$`Point Estimate`
      lo <- plot_df$Lower
      hi <- plot_df$Upper
      hi_clip <- pmin(hi, xlim[2] * 1.05)
      lo_clip <- pmax(lo, xlim[1] * 0.95)
      p <- forestploter::forest(
        disp,
        est = est, lower = lo_clip, upper = hi_clip,
        sizes = 0.35,
        ci_column = 3,
        ref_line = 1,
        xlim = xlim,
        ticks_at = c(0.5, 1, 2, 3),
        theme = tm
      )
      hdr <- which(plot_df$is_header %in% TRUE)
      if (length(hdr)) {
        p <- forestploter::edit_plot(
          p, row = hdr, gp = grid::gpar(fontface = "bold")
        )
      }
      p
    }
    # 双库共有亚组（禁一侧 COPD/Cancer 导致行高错位）
    # 注意：禁止把未出现的 eICU 空水平硬塞进 factor——否则
    # intersect(亚组, character(0)) 会把全部亚组裁掉，只剩 Overall。
    est$database_f <- .ref_assoc_factor_db(est$database, short = TRUE)
    est$database_f <- droplevels(est$database_f)
    db_lv <- levels(est$database_f)
    common_sgs <- ref_assoc_fig6_subgroups
    if (length(db_lv) >= 2L) {
      sg_by_db <- lapply(db_lv, function(dbn) {
        unique(as.character(est$subgroup[
          as.character(est$database_f) == dbn & est$subgroup != "Overall"
        ]))
      })
      # 任一库无亚组时不要与空集求交
      sg_by_db <- Filter(function(x) length(x) > 0L, sg_by_db)
      if (length(sg_by_db) >= 2L) {
        common_sgs <- Reduce(intersect, c(list(ref_assoc_fig6_subgroups), sg_by_db))
      } else if (length(sg_by_db) == 1L) {
        common_sgs <- intersect(ref_assoc_fig6_subgroups, sg_by_db[[1L]])
      }
    }
    est <- est[est$subgroup == "Overall" | est$subgroup %in% common_sgs, ,
               drop = FALSE]

    # overall-only：保留双库 × 双指标（2×2）；不做 SOFA/糖代谢分层拼图。
    # 禁止再静默丢掉外验库（审稿/交付要求 Fig6 必须两库可见）。
    # 主库在前；面板字母 A–B（单库双指标）或 A–D（双库双指标）
    panel_specs <- list()
    letter_i <- 0L
    for (dbn in db_lv) {
      for (idx in c(ia, ib)) {
        sub <- est[as.character(est$database_f) == dbn & est$index == idx, ,
                   drop = FALSE]
        if (!nrow(sub)) next
        letter_i <- letter_i + 1L
        panel_specs[[length(panel_specs) + 1L]] <- list(
          letter = LETTERS[[letter_i]],
          dbn = dbn, index = idx, sub = sub
        )
      }
    }
    if (!length(panel_specs)) {
      warning("Figure 6: no panels to draw", call. = FALSE)
      return(list(rows = fr, path = NULL, p_interaction_note = note))
    }

    # forestploter 禁止嵌套 viewport 硬拼——易叠画/表头错位。
    # 各面板单独落矢量 PDF，再用 PyMuPDF 2×N 矢量拼页（禁止 magick 整页栅格交付）。
    tmp_dir <- tempfile("fig6_panels_")
    dir.create(tmp_dir, recursive = TRUE)
    on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)
    panel_pdfs <- character(0)
    .ff <- if (exists("resolve_plot_font_family", mode = "function")) {
      resolve_plot_font_family("Times New Roman")
    } else {
      "Times"
    }
    for (ps in panel_specs) {
      pdf_df <- .fig6_panel_df(ps$sub)
      grob <- .fig6_one_forest(pdf_df)
      wh <- tryCatch(forestploter::get_wh(grob, unit = "in"),
                     error = function(e) NULL)
      if (is.null(wh)) {
        grDevices::pdf(NULL)
        wh <- tryCatch(forestploter::get_wh(grob, unit = "in"),
                       error = function(e) NULL)
        try(grDevices::dev.off(), silent = TRUE)
      }
      fig_w <- suppressWarnings(as.numeric(wh[["width"]] %||% wh[1L])[1L])
      fig_h <- suppressWarnings(as.numeric(wh[["height"]] %||% wh[2L])[1L])
      if (!is.finite(fig_w) || fig_w < 5) fig_w <- 7.2
      if (!is.finite(fig_h) || fig_h < 3) fig_h <- max(4.5, 0.28 * nrow(pdf_df) + 1.6)
      fig_w <- min(9.5, fig_w + 0.35)
      fig_h <- min(14, fig_h + 0.25)
      # 面板题：展示名禁下划线
      idx_lab <- if (exists("pipeline_display_label", mode = "function")) {
        pipeline_display_label(ps$index)
      } else {
        gsub("_", " ", ps$index, fixed = TRUE)
      }
      panel_lab <- if (length(db_lv) <= 1L) {
        sprintf("%s  %s", ps$letter, idx_lab)
      } else {
        sprintf("%s  %s | %s", ps$letter, ps$dbn, idx_lab)
      }
      title_grob <- grid::textGrob(
        panel_lab, x = 0.01, hjust = 0, gp = grid::gpar(
          fontsize = 11, fontface = "bold", fontfamily = .ff
        )
      )
      pdf_i <- file.path(tmp_dir, sprintf("panel_%s.pdf", ps$letter))
      if (exists("pipeline_pdf_device", mode = "function")) {
        pipeline_pdf_device(pdf_i, width = fig_w, height = fig_h + 0.35, family = .ff)
      } else if (isTRUE(capabilities("cairo"))) {
        grDevices::cairo_pdf(pdf_i, width = fig_w, height = fig_h + 0.35, family = .ff)
      } else {
        grDevices::pdf(pdf_i, width = fig_w, height = fig_h + 0.35, family = .ff)
      }
      grid::grid.newpage()
      grid::pushViewport(grid::viewport(layout = grid::grid.layout(
        2L, 1L, heights = grid::unit(c(0.35, fig_h), "in")
      )))
      grid::pushViewport(grid::viewport(layout.pos.row = 1L))
      grid::grid.draw(title_grob)
      grid::popViewport()
      grid::pushViewport(grid::viewport(layout.pos.row = 2L))
      grid::grid.draw(grob)
      grid::popViewport()
      grDevices::dev.off()
      panel_pdfs <- c(panel_pdfs, pdf_i)
    }

    path <- out_pdf
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    n_col <- 2L
    eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
    if (!nzchar(eng)) {
      eng <- as.character(getOption("medical_blocks.root", default = ""))[1L]
    }
    mosaic_py <- file.path(eng, "python", "pub_pdf_mosaic_vector.py")
    if (!nzchar(eng) || !file.exists(mosaic_py)) {
      # 回退：仓库相对路径
      mosaic_py <- file.path("python", "pub_pdf_mosaic_vector.py")
    }
    py <- Sys.which("python3")
    if (!nzchar(py)) py <- Sys.which("python")
    if (!nzchar(py) || !file.exists(mosaic_py)) {
      stop("Figure 6 vector mosaic needs python3 + python/pub_pdf_mosaic_vector.py",
           call. = FALSE)
    }
    ## stdout=TRUE 时 R 走 shell 拼接；路径含空格必须逐参 shQuote
    .mosaic_args <- c(
      mosaic_py, "--out", path, "--cols", as.character(n_col), panel_pdfs
    )
    st <- system2(
      py,
      vapply(.mosaic_args, shQuote, character(1L)),
      stdout = TRUE, stderr = TRUE
    )
    if (!is.null(attr(st, "status")) && !identical(as.integer(attr(st, "status")), 0L)) {
      stop("Figure 6 vector mosaic failed: ", paste(st, collapse = "\n"), call. = FALSE)
    }
    if (!file.exists(path) || file.info(path)$size < 1000) {
      stop("Figure 6 vector mosaic missing output: ", path, call. = FALSE)
    }
  }
  list(rows = fr, path = path, p_interaction_note = note)
}


# --------------------------------------------------------------------------
# Joint / index Cox tables
# --------------------------------------------------------------------------

.ref_assoc_joint_table_core <- function(database, data, joint_lock, models,
                                        cutoff, outcome_cfg) {
  d <- data.frame(data)
  joint <- reference_apply_joint_tertiles(d, joint_lock)
  d$JointGroup <- joint$group
  d$SOFA_layer <- ref_assoc_sofa_layer(d, cutoff)
  masks <- .ref_assoc_layer_masks(d, cutoff)
  res <- .ref_assoc_cox_long(
    d, "futime", "fustatus", "JointGroup", models, masks, outcome_cfg,
    index_terms = list(JointGroup = function(x) x$JointGroup)
  )
  res$database <- database
  res$group <- sub("^JointGroup", "", as.character(res$term))
  res$group[res$group == "" | is.na(res$group)] <- NA_character_
  .ref_assoc_fmt_long(res)
}

.ref_assoc_ref_rows <- function(tb, groups, database) {
  combos <- unique(tb[, c("stratum", "model")])
  do.call(rbind, lapply(seq_len(nrow(combos)), function(i) {
    st <- combos$stratum[[i]]
    mo <- combos$model[[i]]
    sub <- tb[tb$stratum == st & tb$model == mo, , drop = FALSE]
    data.frame(
      database = database, stratum = st, model = mo,
      group = groups,
      hr_ci = rep("1.000 (ref)", length(groups)),
      p_cell = rep("Ref", length(groups)),
      p = rep(NA_real_, length(groups)),
      n = if (nrow(sub)) rep(sub$n[[1]], length(groups)) else 0L,
      events = if (nrow(sub)) rep(sub$events[[1]], length(groups)) else 0L,
      status = "estimable",
      stringsAsFactors = FALSE
    )
  }))
}

ref_assoc_joint_cox_table <- function(database, data, joint_lock, assoc_ctx,
                                      cutoff = c(4L, 10L), outcome_cfg) {
  ia <- .ref_ia(); ib <- .ref_ib()
  models <- .ref_assoc_models(assoc_ctx, data, c(ia, ib),
                              "SOFA_layer")
  res <- .ref_assoc_joint_table_core(database, data, joint_lock, models,
                                     cutoff, outcome_cfg)
  refs <- .ref_assoc_ref_rows(res, "Group1", database)
  cols <- c("database", "stratum", "model", "group", "hr_ci", "p", "p_cell",
            "n", "events", "status")
  cols <- intersect(cols, intersect(names(res), names(refs)))
  out <- rbind(refs[, cols, drop = FALSE], res[, cols, drop = FALSE])
  out[order(out$database, out$stratum, out$model, out$group), , drop = FALSE]
}

ref_assoc_index_cox_table <- function(database, data, sosm_lock, wpr_lock,
                                      train_ref, assoc_ctx, cutoff = c(4L, 10L),
                                      outcome_cfg) {
  ia <- .ref_ia(); ib <- .ref_ib()
  d <- data.frame(data)
  d$SOFA_layer <- ref_assoc_sofa_layer(d, cutoff)
  models <- .ref_assoc_models(assoc_ctx, d, c(ia, ib), "SOFA_layer")
  masks <- .ref_assoc_layer_masks(d, cutoff)
  identity_terms <- stats::setNames(
    list(function(x) as.numeric(x[[ia]]), function(x) as.numeric(x[[ib]])),
    c(ia, ib))
  cont <- .ref_assoc_cox_long(
    d, "futime", "fustatus", c(ia, ib), models, masks, outcome_cfg,
    index_terms = identity_terms
  )
  cont$database <- database
  cont$coding <- "continuous"
  cont$group <- "per 1 unit"
  ta <- paste0(ia, "_T"); tb <- paste0(ib, "_T")
  ter <- .ref_assoc_cox_long(
    d, "futime", "fustatus", c(ta, tb), models, masks, outcome_cfg,
    index_terms = stats::setNames(list(
      function(x) .ref_assoc_tertile3(x, ia, sosm_lock, train_ref),
      function(x) .ref_assoc_tertile3(x, ib, wpr_lock, train_ref)
    ), c(ta, tb))
  )
  ter$database <- database
  ter$index <- sub("_T$", "", as.character(ter$index))
  ter$coding <- "tertile"
  ter$group <- sub(paste0("^(", ia, "|", ib, ")_T"), "", as.character(ter$term))
  cont <- .ref_assoc_fmt_long(cont)
  ter <- .ref_assoc_fmt_long(ter)
  ter <- ter[!is.na(ter$group) & nzchar(ter$group), , drop = FALSE]
  refs <- .ref_assoc_ref_rows(ter, "T1", database)
  refs$index <- rep(NA_character_, nrow(refs))
  refs$index <- vapply(seq_len(nrow(refs)), function(i) {
    hit <- unique(ter$index[ter$stratum == refs$stratum[i] &
                              ter$model == refs$model[i]])
    if (length(hit)) hit[[1]] else NA_character_
  }, character(1))
  # one reference row per database/stratum/index/model
  refs <- refs[!duplicated(refs[, c("stratum", "model", "index")]), ]
  refs$coding <- "tertile"
  refs$group <- "T1"
  keep_cols <- c("database", "stratum", "index", "coding", "model", "group",
                 "hr_ci", "p_cell", "p", "n", "events", "status")
  keep_cols <- intersect(keep_cols, Reduce(intersect, lapply(
    list(cont, refs, ter), names)))
  out <- rbind(cont[, keep_cols, drop = FALSE],
               refs[, keep_cols, drop = FALSE],
               ter[, keep_cols, drop = FALSE])
  out[order(out$database, out$stratum, out$index, out$coding, out$model,
            out$group), , drop = FALSE]
}

ref_assoc_ph_table <- function(database, data, sosm_lock, wpr_lock,
                               train_ref, cutoff = c(4L, 10L), outcome_cfg) {
  ia <- .ref_ia(); ib <- .ref_ib()
  d <- data.frame(data)
  d$SOFA_layer <- ref_assoc_sofa_layer(d, cutoff)
  masks <- .ref_assoc_layer_masks(d, cutoff)
  rows <- list()
  k <- 0L
  for (index in c(ia, ib)) {
    for (layer_name in names(masks)) {
      k <- k + 1L
      dd <- d[masks[[layer_name]], , drop = FALSE]
      dd <- .ref_assoc_event01(dd, "fustatus", outcome_cfg)
      dd$event <- dd$fustatus
      dd <- dd[stats::complete.cases(dd[, c("futime", "event", index)]), ,
               drop = FALSE]
      # model=TRUE（与 landmark PH 扫描一致）：cox.zph 复用已存 model.frame，
      # 不会去 formula 环境里重新求值 data=dd（否则报 object 'dd' not found）。
      fit <- tryCatch(
        survival::coxph(.ref_assoc_ph_formula(index), data = dd,
                        x = TRUE, y = TRUE, model = TRUE),
        error = function(e) NULL
      )
      if (is.null(fit) || anyNA(stats::coef(fit))) {
        rows[[k]] <- data.frame(
          database = database, index = index, stratum = layer_name,
          n = nrow(dd), events = sum(dd$event == 1L),
          exposure_p = NA_real_, global_p = NA_real_,
          status = "not_estimable", stringsAsFactors = FALSE
        )
        next
      }
      zph <- tryCatch(survival::cox.zph(fit, transform = "identity"),
                      error = function(e) NULL)
      pv <- if (is.null(zph)) {
        c(exposure = NA_real_, global = NA_real_)
      } else {
        .reference_ph_p(zph, index)
      }
      rows[[k]] <- data.frame(
        database = database, index = index, stratum = layer_name,
        n = fit$n, events = fit$nevent,
        exposure_p = unname(pv[["exposure"]]),
        global_p = unname(pv[["global"]]),
        status = "estimable", stringsAsFactors = FALSE
      )
    }
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

.data_or_bt <- NULL  # placeholder, replaced below

# build formula with backticked term
.ref_assoc_ph_formula <- function(index) {
  stats::as.formula(sprintf(
    "survival::Surv(futime, event) ~ %s", .reference_bt(index)
  ))
}

# --------------------------------------------------------------------------
# xlsx export (public SCI three-line single header)
# --------------------------------------------------------------------------

.ref_assoc_export_xlsx <- function(filepath, title, df, footnotes = NULL) {
  dir.create(dirname(filepath), recursive = TRUE, showWarnings = FALSE)
  sheet <- substr(gsub("[\\\\/:*?<>\\[\\]|\"]+", "-", basename(filepath)),
                  1, 28)
  sci_xlsx_single_header_booktabs(
    filepath, title = title, df_body = as.data.frame(df), sheet = sheet,
    footnotes = footnotes
  )
  filepath
}

# --------------------------------------------------------------------------
# Orchestration
# --------------------------------------------------------------------------

ref_assoc_run_all <- function(mimic, eicu, out_dir, cutoff = c(4L, 10L),
                              grid_n = 50L, quiet = FALSE,
                              indices = c("SOSM", "WPR"),
                              force_landmark_day = NULL,
                              force_landmark_stratum = "Overall") {
  .ref_assoc_set_indices(indices)
  ia <- .ref_ia(); ib <- .ref_ib(); ilab <- .ref_ilab()
  .ref_assoc_require(c(
    "reference_trusted_development", "reference_lock_tertile_cutpoints",
    "reference_apply_joint_tertiles", "reference_lock_grouped_rcs",
    "reference_grouped_rcs", "reference_ph_landmark_lock",
    "reference_apply_landmark", "sci_xlsx_single_header_booktabs"
  ))
  if (isTRUE(quiet)) {
    suppress <- TRUE
  } else {
    suppress <- FALSE
  }
  dir.create(file.path(out_dir, "Figures"), recursive = TRUE,
             showWarnings = FALSE)
  dir.create(file.path(out_dir, "Tables"), recursive = TRUE,
             showWarnings = FALSE)
  fig_dir <- file.path(out_dir, "Figures")
  tab_dir <- file.path(out_dir, "Tables")
  notes <- character(0)
  pipeline_apply_pub_digits(mimic$config)

  # -- trust root + frozen derived authority --------------------------------
  prov0 <- reference_trusted_development(
    mimic$train, checkpoint_path = mimic$authority_checkpoint
  )
  cuts0 <- reference_lock_tertile_cutpoints(
    mimic$train, ia, ib, prov0
  )
  train_aug <- mimic$train
  train_aug$SOFA_layer <- ref_assoc_sofa_layer(train_aug, cutoff)
  train_aug$JointGroup <- reference_joint_tertile_groups(
    train_aug[[ia]], train_aug[[ib]],
    cut_a = cuts0$cutpoints[["a"]], cut_b = cuts0$cutpoints[["b"]]
  )
  train_aug$Joint_score <- as.numeric(train_aug$JointGroup)
  derived_path <- .ref_assoc_write_derived_authority(
    train_aug, out_dir, mimic$config
  )
  provenance <- reference_trusted_development(train_aug,
                                              checkpoint_path = derived_path)
  joint_lock <- reference_lock_tertile_cutpoints(train_aug, ia, ib,
                                                 provenance)
  stopifnot(isTRUE(all.equal(unname(joint_lock$cutpoints),
                             unname(cuts0$cutpoints), tolerance = 0)))
  sosm_lock <- reference_lock_tertile_cutpoints(train_aug, ia, ia,
                                                provenance)
  wpr_lock <- reference_lock_tertile_cutpoints(train_aug, ib, ib,
                                               provenance)
  rcs_locks <- stats::setNames(list(
    reference_lock_grouped_rcs(train_aug, ia, provenance),
    reference_lock_grouped_rcs(train_aug, ib, provenance)), c(ia, ib))
  notes <- c(notes, paste0(
    "Derived authority: ", derived_path,
    " (source checkpoint md5 ", prov0$checkpoint_md5, ")"
  ))

  db_frames <- list(
    list(
      name = "MIMIC_IV", short = "MIMIC-IV", data = mimic$analysis,
      outcome_cfg = mimic$config, joint_lock = joint_lock,
      sosm_lock = sosm_lock, wpr_lock = wpr_lock, rcs_locks = rcs_locks,
      assoc_ctx = mimic$assoc_ctx, train_ref = train_aug
    ),
    list(
      name = "eICU", short = "eICU", data = eicu$analysis,
      outcome_cfg = eicu$config, joint_lock = joint_lock,
      sosm_lock = sosm_lock, wpr_lock = wpr_lock, rcs_locks = rcs_locks,
      assoc_ctx = eicu$assoc_ctx, train_ref = train_aug
    )
  )
  db_frames <- .ref_assoc_order_db_frames(db_frames)
  for (i in seq_along(db_frames)) {
    db_frames[[i]]$models <- .ref_assoc_models(
      db_frames[[i]]$assoc_ctx, db_frames[[i]]$data,
      c(ia, ib), "SOFA_layer"
    )
  }

  # -- Figure 2 --------------------------------------------------------------
  fig2_name <- if (.ref_assoc_overall_only(cutoff)) {
    paste0("Figure 2. KM ", ia, " ", ib, " joint groups.pdf")
  } else {
    paste0("Figure 2. KM ", ia, " ", ib, " joint by SOFA strata.pdf")
  }
  fig2 <- ref_assoc_fig2_km(
    db_frames, cutoff = cutoff,
    out_pdf = file.path(fig_dir, fig2_name)
  )
  notes <- c(notes, sprintf("Fig2 not_estimable panels: %d/%d",
                            sum(fig2$panels$status != "estimable"),
                            nrow(fig2$panels)))

  # -- Figure 3 --------------------------------------------------------------
  fig3_name <- if (.ref_assoc_overall_only(cutoff)) {
    paste0("Figure 3. Grouped RCS ", ia, " ", ib, ".pdf")
  } else {
    paste0("Figure 3. Grouped RCS ", ia, " ", ib, " by SOFA strata.pdf")
  }
  fig3 <- ref_assoc_fig3_rcs(
    db_frames, cutoff = cutoff, grid_n = grid_n,
    out_pdf = file.path(fig_dir, fig3_name)
  )

  # -- Figure 4 + S5 ----------------------------------------------------------
  fig4 <- ref_assoc_fig4_roc(
    db_frames, cutoff = cutoff,
    out_pdf = file.path(fig_dir, paste0("Figure 4. ROC ", ia, " ", ib, " joint scores.pdf"))
  )
  notes <- c(notes, sprintf("Fig4 not_estimable predictors: %d",
                            sum(fig4$auc$status != "estimable")))
  s5_title <- paste0(
    "Table S5. Discrimination (AUC with 95% CI) and DeLong tests versus ",
    ia, " for ", ia, ", ", ib, ", continuous joint linear predictor (", ia, "+", ib,
    " logistic LP locked on MIMIC train), APSIII, OASIS and GCS, by ",
    "database",
    if (identical(ref_assoc_layer_labels(cutoff), "Overall")) {
      " (overall cohort, 28-day all-cause mortality)."
    } else {
      " and SOFA stratum (28-day all-cause mortality)."
    }
  )
  s5_out <- fig4$auc
  s5_out$predictor[s5_out$predictor == "Joint"] <- .ref_assoc_fig4_joint_lab()
  s5_out$auc_fmt <- pub_format_est(s5_out$auc)
  s5_out$ci_fmt <- ifelse(
    is.finite(s5_out$ci_low),
    paste0("(", pub_format_est(s5_out$ci_low), ", ",
           pub_format_est(s5_out$ci_high), ")"),
    "NE"
  )
  s5_out$delong_fmt <- ifelse(
    s5_out$predictor == ia, "reference",
    pub_format_p_cell(s5_out$delong_p)
  )
  s5_export <- s5_out[, c("database", "stratum", "predictor", "n", "events",
                          "auc_fmt", "ci_fmt", "delong_fmt", "status")]
  names(s5_export) <- c("Database",
                        if (identical(ref_assoc_layer_labels(cutoff), "Overall")) {
                          "Stratum"
                        } else {
                          "SOFA stratum"
                        }, "Predictor", "N",
                        "Events", "AUC", "95% CI", paste0("DeLong P vs ", ia),
                        "Status")
  files <- list(
    S5 = .ref_assoc_export_xlsx(
      file.path(tab_dir, "Table S5 ROC discrimination DeLong.xlsx"),
      s5_title, s5_export,
      footnotes = c(
        paste0(
          "Joint = continuous logistic linear predictor of ", ia, " + ", ib,
          " with coefficients locked on MIMIC development/train ",
          "(applied to both databases; no refit on eICU)."
        ),
        "Not the four-level joint tertile group code used in Table 2 / KM.",
        "DeLong P compares each predictor with ", ia,
        " within the same database (and stratum if applicable).",
        "Outcome: 28-day all-cause mortality (Survivor / Non-survivor)."
      )
    )
  )

  # -- Figure 5 --------------------------------------------------------------
  # PH landmark 扫描必须用精简协变量（Age+Sex = literature Model2 / legacy Model1）。
  # 全调整 Model3 在部分指标组合上可达 30+ 列，coxph/cox.zph 全层 aliased → 误杀整条 Task4。
  age_sex_nm <- .ref_assoc_age_sex_model_name(db_frames[[1]]$models)
  fig5_covs <- intersect(db_frames[[1]]$models[[age_sex_nm]],
                         names(train_aug))
  if (!length(fig5_covs)) {
    fig5_covs <- intersect(c("Age", "Gender", "Sex"), names(train_aug))
  }
  ## landmark 硬锁：显式参数 > config$ml_literature_extras$force_landmark_day
  extras <- mimic$config$ml_literature_extras %||% list()
  fd_cfg <- suppressWarnings(as.numeric(
    force_landmark_day %||% extras$force_landmark_day %||% extras$fig5_landmark_day
  )[1L])
  fs_cfg <- as.character(
    force_landmark_stratum %||% extras$force_landmark_stratum %||%
      extras$fig5_landmark_stratum %||% "Overall"
  )[1L]
  fig5 <- ref_assoc_fig5_landmark(
    train_aug = train_aug, mimic_analysis = mimic$analysis,
    eicu_analysis = eicu$analysis, provenance = provenance,
    outcome_cfg = mimic$config, covariates = fig5_covs, cutoff = cutoff,
    joint_lock = joint_lock,
    out_pdf = file.path(fig_dir, "Figure 5. Landmark before after Cox.pdf"),
    force_landmark_day = if (is.finite(fd_cfg)) fd_cfg else NULL,
    force_landmark_stratum = fs_cfg
  )
  notes <- c(notes, sprintf("Fig5 not_estimable segments: %d",
                            sum(fig5$results$status != "estimable")))
  if (!length(fig5$locked_spec$landmark_times)) {
    notes <- c(notes, "Fig5: no PH-violating layer in development; no landmark selected.")
  }

  # -- Figure 6 --------------------------------------------------------------
  fig6 <- ref_assoc_fig6_forest(
    db_frames, cutoff = cutoff,
    out_pdf = file.path(fig_dir, "Figure 6. Forest tertile association.pdf")
  )
  if (nzchar(fig6$p_interaction_note)) {
    notes <- c(notes, fig6$p_interaction_note)
  }

  # -- Table 2 ----------------------------------------------------------------
  t2a <- ref_assoc_joint_cox_table(
    "MIMIC_IV", mimic$analysis, joint_lock, mimic$assoc_ctx, cutoff,
    mimic$config
  )
  t2b <- ref_assoc_joint_cox_table(
    "eICU", eicu$analysis, joint_lock, eicu$assoc_ctx, cutoff, eicu$config
  )
  t2 <- rbind(t2a, t2b)
  wide_table2 <- function(tb) {
    if (any(as.character(tb$model) == "Model3", na.rm = TRUE) ||
        any(as.character(t2$model) == "Model3", na.rm = TRUE)) {
      model_names <- c("Model1", "Model2", "Model3")
      full_nm <- "Model3"
    } else {
      model_names <- c("Unadjusted", "Model1 Age+Gender", "Model2")
      full_nm <- "Model2"
    }
    grp_order <- c("Group1", "Group2", "Group3", "Group4")
    do.call(rbind, lapply(ref_assoc_layer_labels(cutoff), function(st) {
      base <- data.frame(Stratum = st, Group = grp_order,
                         stringsAsFactors = FALSE)
      for (m in model_names) {
        sub <- tb[tb$stratum == st & tb$model == m, , drop = FALSE]
        cells <- paste0(sub$hr_ci, "  ", sub$p_cell)
        base[[paste0(m)]] <- vapply(grp_order, function(g) {
          hit <- cells[sub$group == g]
          if (length(hit) && nzchar(hit[[1]])) {
            hit[[1]]
          } else if (identical(g, "Group1")) {
            "1.000 (ref)  Ref"
          } else {
            "NE"
          }
        }, character(1))
      }
      n_row <- tb[tb$stratum == st & tb$model == full_nm, ]
      base[["N (events)"]] <- if (nrow(n_row)) {
        paste0(n_row$n[[1]], " (", n_row$events[[1]], ")")
      } else {
        ""
      }
      base
    }))
  }
  t2a_w <- wide_table2(t2a)
  t2b_w <- wide_table2(t2b)
  blank <- as.data.frame(
    matrix("", 1L, ncol(t2a_w)), stringsAsFactors = FALSE
  )
  names(blank) <- names(t2a_w)
  panel_a <- cbind(Panel = "Panel A: MIMIC-IV", t2a_w,
                   stringsAsFactors = FALSE)
  panel_b <- cbind(Panel = "Panel B: eICU", t2b_w,
                   stringsAsFactors = FALSE)
  blank2 <- blank
  blank2 <- cbind(Panel = "", blank2[, setdiff(names(panel_a), "Panel")],
                  row.names = NULL, stringsAsFactors = FALSE)
  names(blank2) <- names(panel_a)
  combo <- rbind(panel_a, blank2, panel_b)
  rownames(combo) <- NULL
  t2_title <- paste0(
    "Table 2. Association of ", .ref_ilab_disp(), " joint groups with 28-day all-cause ",
    "mortality (Cox regression; Group1 low/low = reference)."
  )
  lit_t2 <- any(as.character(t2$model) == "Model3", na.rm = TRUE)
  t2_footnotes <- if (isTRUE(lit_t2)) {
    c(
      paste0(
        "Model 1: unadjusted; Model 2: age and sex; Model 3: clinically meaningful ",
        "indicators that were significant in univariate analysis, with collinearity ",
        "controlled (VIF < 5). Disease-severity scores and organ-support variables ",
        "(e.g. APSIII, OASIS, SOFA, GCS, mechanical ventilation) are excluded from ",
        "Model 3 to avoid overadjustment of the total association."
      ),
      if (identical(ref_assoc_layer_labels(cutoff), "Overall")) {
        "Overall cohort only (no disease-severity split). Joint groups from MIMIC development-frozen upper-tertile cutpoints."
      } else {
        "SOFA strata 0-4 / 5-10 / >=11. Joint groups from MIMIC development-frozen upper-tertile cutpoints."
      },
      "Cells show HR (95% CI) and P; NE = not estimable; Group1 = 1.000 (ref).",
      paste0(
        "\u2021 Model3 not estimable (sparse events or collinearity); cell shows ",
        "Age+Sex-adjusted estimate (Model2 covariates) with the same joint-group contrast."
      ),
      "Outcome: Survivor / Non-survivor at 28 days (administrative censoring)."
    )
  } else {
    c(
      "Model 1: Age + Gender. Model 2: association-rule covariate set (per project covariate rule).",
      if (identical(ref_assoc_layer_labels(cutoff), "Overall")) {
        "Overall cohort only (no disease-severity split). Joint groups from MIMIC development-frozen upper-tertile cutpoints."
      } else {
        "SOFA strata 0-4 / 5-10 / >=11. Joint groups from MIMIC development-frozen upper-tertile cutpoints."
      },
      "Cells show HR (95% CI) and P; NE = not estimable; Group1 = 1.000 (ref).",
      paste0("\u2021 Model2 not estimable (sparse events or collinearity); cell shows Age+Gender-adjusted ",
             "estimate (Model1 covariates) with the same joint-group contrast."),
      "Outcome: Survivor / Non-survivor at 28 days (administrative censoring)."
    )
  }
  files$Table2 <- .ref_assoc_export_xlsx(
    file.path(tab_dir, "Table 2 Joint group Cox.xlsx"),
    t2_title, combo, footnotes = t2_footnotes
  )

  # -- S4 ---------------------------------------------------------------------
  s4 <- rbind(
    ref_assoc_index_cox_table(
      "MIMIC_IV", mimic$analysis, sosm_lock, wpr_lock, train_aug,
      mimic$assoc_ctx, cutoff, mimic$config
    ),
    ref_assoc_index_cox_table(
      "eICU", eicu$analysis, sosm_lock, wpr_lock, train_aug,
      eicu$assoc_ctx, cutoff, eicu$config
    )
  )
  s4_title <- paste0(
    paste0("Table S4. Cox associations of ", ia, " and ", ib, " (continuous and tertiles) "),
    "with 28-day all-cause mortality",
    if (identical(ref_assoc_layer_labels(cutoff), "Overall")) {
      ", overall cohort."
    } else {
      ", Overall and by SOFA stratum."
    }
  )
  s4_export <- s4
  names(s4_export) <- c("Database",
                        if (identical(ref_assoc_layer_labels(cutoff), "Overall")) {
                          "Stratum"
                        } else {
                          "SOFA stratum"
                        }, "Index", "Coding",
                        "Model", "Group", "HR (95% CI)", "P", "p raw",
                        "N", "Events", "Status")
  files$S4 <- .ref_assoc_export_xlsx(
    file.path(tab_dir, paste0("Table S4 ", ia, " ", ib, " Cox.xlsx")), s4_title, s4_export
  )

  # -- PH tables S6-S8 ----------------------------------------------------------
  ph <- rbind(
    ref_assoc_ph_table("MIMIC_IV", mimic$analysis, sosm_lock, wpr_lock,
                       train_aug, cutoff, mimic$config),
    ref_assoc_ph_table("eICU", eicu$analysis, sosm_lock, wpr_lock,
                       train_aug, cutoff, eicu$config)
  )
  ph$exposure_p_fmt <- pub_format_p_cell(ph$exposure_p)
  ph$global_p_fmt <- pub_format_p_cell(ph$global_p)
  # 原文 S6/S7/S8 = 三个糖代谢层的 PH 检验；本课题映射到三个 SOFA 层。
  # overall-only：仅导出 Overall 一张 Table S6（不做 SOFA 分层 PH）。
  layer_labs <- ref_assoc_layer_labels(cutoff)
  if (.ref_assoc_overall_only(cutoff)) {
    layer_labs <- "Overall"
    ph_keys <- "S6"
  } else {
    layer_labs <- layer_labs[layer_labs != "Overall"]
    ph_keys <- paste0("S", seq_along(layer_labs) + 5L)  # S6, S7, S8
  }
  if (length(layer_labs)) {
  ph_map <- stats::setNames(as.list(layer_labs), ph_keys)
  for (key in names(ph_map)) {
    lab <- ph_map[[key]]
    sub <- ph[ph$stratum == lab, , drop = FALSE]
    exp_df <- sub[, c("database", "index", "n", "events",
                      "exposure_p_fmt", "global_p_fmt", "status")]
    names(exp_df) <- c("Database", "Index", "N", "Events",
                       "PH P (exposure)", "PH P (global)", "Status")
    ph_title <- sprintf(
      "Table %s. Proportional-hazards (Schoenfeld) tests, %s.", key, lab
    )
    files[[key]] <- .ref_assoc_export_xlsx(
      file.path(tab_dir, paste0("Table ", key, " PH ", lab, ".xlsx")),
      ph_title, exp_df
    )
  }
  }

  # -- S9 baseline glucose sensitivity -------------------------------------------
  drop_low_glucose <- function(d, glucose) {
    # 按 ID 键对齐（match 取首个匹配），避免 merge 在重复键下行数爆炸/错位
    if (is.null(glucose) || !is.data.frame(glucose) ||
        !"ID" %in% names(glucose) || !"Glucose" %in% names(glucose)) {
      return(d)
    }
    gi <- match(as.character(d$ID), as.character(glucose$ID))
    g <- glucose$Glucose[gi]
    keep <- is.na(g) | g >= 70
    d[keep, , drop = FALSE]
  }
  if (is.null(mimic$baseline_glucose) || is.null(eicu$baseline_glucose)) {
    notes <- c(notes, "S9 skipped: baseline_glucose frame missing on mimic and/or eicu input.")
    files$S9 <- NA_character_
  } else {
  s9 <- rbind(
    ref_assoc_joint_cox_table(
      "MIMIC_IV", drop_low_glucose(mimic$analysis, mimic$baseline_glucose),
      joint_lock, mimic$assoc_ctx, cutoff, mimic$config
    ),
    ref_assoc_joint_cox_table(
      "eICU", drop_low_glucose(eicu$analysis, eicu$baseline_glucose),
      joint_lock, eicu$assoc_ctx, cutoff, eicu$config
    )
  )
  s9_title <- paste0(
    "Table S9. Sensitivity analysis: joint-group Cox after excluding ",
    "patients with baseline glucose <70 mg/dL (28-day all-cause mortality)."
  )
  s9_export <- s9
  names(s9_export) <- c("Database",
                        if (identical(ref_assoc_layer_labels(cutoff), "Overall")) {
                          "Stratum"
                        } else {
                          "SOFA stratum"
                        }, "Model", "Group",
                        "HR (95% CI)", "p raw", "P", "N", "Events", "Status")
  files$S9 <- .ref_assoc_export_xlsx(
    file.path(tab_dir, "Table S9 baseline glucose excluded joint Cox.xlsx"),
    s9_title, s9_export
  )
  files$S9_title <- s9_title
  }  # end baseline_glucose available

  # -- S10 complete-case sensitivity ------------------------------------------------
  if (is.null(mimic$complete_case) || is.null(eicu$complete_case) ||
      !is.data.frame(mimic$complete_case) || !is.data.frame(eicu$complete_case)) {
    notes <- c(notes, "S10 skipped: complete_case frame missing on mimic and/or eicu input.")
    files$S10 <- NA_character_
  } else {
  s10 <- rbind(
    ref_assoc_joint_cox_table(
      "MIMIC_IV", mimic$complete_case, joint_lock, mimic$assoc_ctx, cutoff,
      mimic$config
    ),
    ref_assoc_joint_cox_table(
      "eICU", eicu$complete_case, joint_lock, eicu$assoc_ctx, cutoff,
      eicu$config
    )
  )
  s10_title <- paste0(
    "Table S10. Sensitivity analysis: joint-group Cox restricted to ",
    "complete cases (28-day all-cause mortality)."
  )
  s10_export <- s10
  names(s10_export) <- c("Database",
                         if (identical(ref_assoc_layer_labels(cutoff), "Overall")) {
                           "Stratum"
                         } else {
                           "SOFA stratum"
                         }, "Model", "Group",
                         "HR (95% CI)", "p raw", "P", "N", "Events",
                         "Status")
  files$S10 <- .ref_assoc_export_xlsx(
    file.path(tab_dir, "Table S10 complete-case joint Cox.xlsx"),
    s10_title, s10_export
  )
  }  # end complete_case available

  if (!suppress) {
    message("ref_assoc_run_all complete: ", out_dir)
  }
  list(
    figures = list(Fig2 = fig2, Fig3 = fig3, Fig4 = fig4, Fig5 = fig5,
                   Fig6 = fig6),
    tables = list(
      Table2 = t2, S4 = s4, S5 = fig4$auc, PH = ph,
      S9 = if (exists("s9", inherits = FALSE)) {
        list(title = s9_title, table = s9)
      } else {
        NULL
      },
      S10 = if (exists("s10", inherits = FALSE)) {
        list(title = s10_title, table = s10)
      } else {
        NULL
      }
    ),
    files = files,
    locks = list(joint = joint_lock, sosm = sosm_lock, wpr = wpr_lock,
                 rcs = rcs_locks, derived_authority = derived_path),
    provenance = provenance,
    audit = list(notes = notes)
  )
}
