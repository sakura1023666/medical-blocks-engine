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
# 图面显示名：联合四分组（各指标最高三分位 high × 其余 low）
.ref_joint_lab <- function() paste0(.ref_ilab(), " joint")


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
#' cutoff 参数现承载递增整数切点向量（breaks）；单值等价旧 2 层口径。
.ref_assoc_breaks <- function(cutoff) {
  br <- suppressWarnings(as.integer(as.numeric(cutoff)))
  br <- br[!is.na(br)]
  if (!length(br)) c(4L, 10L) else unique(sort(br))
}

ref_assoc_sofa_layer <- function(data, cutoff = c(4L, 10L)) {
  spec <- ml_stratum_spec_sofa(breaks = .ref_assoc_breaks(cutoff))
  value <- suppressWarnings(as.numeric(as.character(data[[spec$variable]])))
  out <- rep(NA_character_, length(value))
  for (s in spec$strata) {
    out[ml_stratum_member(value, s)] <- s$label
  }
  factor(out, levels = vapply(spec$strata, function(s) s$label, character(1)))
}

#' Overall + 各 SOFA 层的标签顺序（图/表统一使用）。
ref_assoc_layer_labels <- function(cutoff = c(4L, 10L)) {
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
  list(status = "estimable", curve = sdf, p = p)
}

ref_assoc_fig2_km <- function(db_frames, cutoff = c(4L, 10L), out_pdf = NULL) {
  ia <- .ref_ia(); ib <- .ref_ib(); ilab <- .ref_ilab()
  db_frames <- .ref_assoc_order_db_frames(db_frames)
  panels <- list()
  curves <- list()
  k <- 0L
  cols <- list(
    list(column = ia, name = paste0(ia, " tertile")),
    list(column = ib, name = paste0(ib, " tertile")),
    list(column = "Joint", name = paste0(ilab, " joint"))
  )
  sofa_lv <- ref_assoc_layer_labels(cutoff)
  sofa_lv <- sofa_lv[sofa_lv != "Overall"]
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
      mask <- !is.na(as.character(d$SOFA_layer)) &
        as.character(d$SOFA_layer) == sofa_lv[[ri]]
      for (col in cols) {
        k <- k + 1L
        res <- .ref_assoc_km_panel(d[mask, , drop = FALSE],
                                   d[[group_of[[col$column]]]][mask])
        panels[[k]] <- data.frame(
          panel = k, row = ri, column = col$column, database = db$name,
          stratum = sofa_lv[[ri]],
          panel_title = paste0(db$short, " ", sofa_lv[[ri]], " | ",
                               col$name),
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
    path <- out_pdf
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    n_rows <- ceiling(nrow(panels) / 3)
    pipeline_ggsave_pdf(path, plt, width = 10,
                        height = max(10, 2.1 * n_rows + 2))
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
    keep_cols <- intersect(c("futime", "fustatus", ia, ib, "SOFA_layer",
                             "Age", "Gender"), names(d))
    d <- d[!is.na(d$SOFA_layer), keep_cols, drop = FALSE]
    for (index in c(ia, ib)) {
      res <- reference_grouped_rcs(
        data = d, time = "futime", event = "fustatus", index = index,
        stratum = "SOFA_layer", covariates = c("Age", "Gender"),
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
    ann <- summary
    ann$lab <- paste0(
      ann$stratum, ": P for overall = ", pub_format_p_cell(ann$p_overall),
      ", P for nonlinear = ", pub_format_p_cell(ann$p_nonlinear)
    )
    lab_df <- do.call(rbind, lapply(
      split(ann, list(ann$database, ann$index), drop = TRUE),
      function(a) {
        idx <- a$index[[1L]]; dbn <- a$database[[1L]]
        cv <- curve[curve$database == dbn & curve$index == idx, , drop = FALSE]
        xv <- if (nrow(cv)) min(cv$value, na.rm = TRUE) else 0
        yh <- if (nrow(cv)) {
          max(c(cv$conf_high, cv$hr), na.rm = TRUE)
        } else {
          2
        }
        data.frame(
          database = dbn, index = idx,
          lab = paste0(a$lab, collapse = "\n"),
          value = xv, hr = yh,
          stringsAsFactors = FALSE
        )
      }
    ))
    curve$database <- .ref_assoc_factor_db(curve$database, short = FALSE)
    lab_df$database <- .ref_assoc_factor_db(lab_df$database, short = FALSE)
    # 列顺序：指标 A | B（与原文 SHR | GV 一致）
    curve$index <- factor(curve$index, levels = c(ia, ib))
    lab_df$index <- factor(lab_df$index, levels = c(ia, ib))
    # 图面显示名用短名
    levels(curve$database) <- .ref_assoc_db_levels(short = TRUE)
    levels(lab_df$database) <- .ref_assoc_db_levels(short = TRUE)
    plt <- ggplot2::ggplot(
      curve,
      ggplot2::aes(x = value, y = hr, colour = stratum, fill = stratum)
    ) +
      ggplot2::geom_ribbon(
        ggplot2::aes(ymin = conf_low, ymax = conf_high),
        alpha = 0.15, linewidth = 0
      ) +
      ggplot2::geom_line(linewidth = 0.7) +
      ggplot2::geom_hline(yintercept = 1, linetype = 2, colour = "grey40",
                          linewidth = 0.3) +
      ggplot2::facet_grid(database ~ index, scales = "free_x") +
      ggplot2::geom_text(
        data = lab_df,
        ggplot2::aes(x = value, y = hr, label = lab),
        hjust = 0, vjust = 1.05, size = 1.9, inherit.aes = FALSE,
        show.legend = FALSE
      ) +
      ggplot2::scale_x_continuous(labels = scales::label_comma()) +
      ggplot2::coord_cartesian(ylim = c(0.4, NA)) +
      ggplot2::labs(x = "Exposure", y = "Adjusted HR (95% CI)",
                    colour = NULL, fill = NULL,
                    title = paste0("Figure 3. Restricted cubic splines for ", ia, " and ", ib)) +
      ggplot2::theme_bw(base_size = 8) +
      ggplot2::theme(legend.position = "bottom",
                     panel.grid.minor = ggplot2::element_blank(),
                     plot.title = ggplot2::element_text(size = 9, face = "bold"))
    path <- out_pdf
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    pipeline_ggsave_pdf(path, plt, width = 9, height = 8)
  }
  list(summary = summary, curve = curve, path = path)
}

# --------------------------------------------------------------------------
# Figure 4 + Table S5: ROC (AUC/95%CI + DeLong vs SOSM within panel)
# --------------------------------------------------------------------------

ref_assoc_roc_predictors <- function() {
  c(.ref_ia(), .ref_ib(), "Joint", "APSIII", "OASIS", "GCS")
}

ref_assoc_fig4_roc <- function(db_frames, cutoff = c(4L, 10L), out_pdf = NULL) {
  if (!requireNamespace("pROC", quietly = TRUE)) {
    stop("Package 'pROC' is required for Figure 4.", call. = FALSE)
  }
  ia <- .ref_ia(); ib <- .ref_ib()
  preds <- ref_assoc_roc_predictors()
  db_frames <- .ref_assoc_order_db_frames(db_frames)
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
    joint <- reference_apply_joint_tertiles(d, db$joint_lock)
    d$Joint <- as.numeric(joint$group)
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
    # 原文 Fig.4 图例仅曲线名（AUC 数字在 Table S5）；Joint 写成「ACAG+RAR joint」
    pred_lv <- preds
    pred_labs <- pred_lv
    pred_labs[pred_labs == "Joint"] <- .ref_joint_lab()
    curve$database <- .ref_assoc_factor_db(curve$database, short = FALSE)
    levels(curve$database) <- .ref_assoc_db_levels(short = TRUE)
    curve$stratum <- factor(curve$stratum, levels = stratum_order)
    curve$predictor <- factor(curve$predictor, levels = pred_lv)
    plt <- ggplot2::ggplot(
      curve, ggplot2::aes(x = fpr, y = tpr, colour = predictor)
    ) +
      ggplot2::geom_abline(linetype = 2, colour = "grey50",
                           linewidth = 0.3) +
      ggplot2::geom_line(linewidth = 0.6) +
      ggplot2::facet_grid(database ~ stratum) +
      ggplot2::scale_colour_discrete(breaks = pred_lv, labels = pred_labs) +
      ggplot2::scale_x_continuous(limits = c(0, 1), expand = c(0, 0)) +
      ggplot2::scale_y_continuous(limits = c(0, 1), expand = c(0, 0)) +
      ggplot2::labs(x = "1 - Specificity", y = "Sensitivity", colour = NULL,
                    title = paste0(
                      "Figure 4. ROC of ", ia, ", ", ib, ", ",
                      .ref_joint_lab(),
                      " and clinical scores (Overall and SOFA strata)"
                    )) +
      ggplot2::theme_bw(base_size = 8) +
      ggplot2::theme(legend.position = "bottom",
                     panel.grid.minor = ggplot2::element_blank(),
                     plot.title = ggplot2::element_text(size = 8, face = "bold"))
    path <- out_pdf
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    # 2 行(库) × 4 列(Overall+三层) = 8 面板
    pipeline_ggsave_pdf(path, plt, width = 12, height = 7)
  }
  list(auc = auc, curve = curve, path = path)
}

# --------------------------------------------------------------------------
# Figure 5: landmark lock from MIMIC development; eICU only applies
# --------------------------------------------------------------------------

ref_assoc_fig5_landmark <- function(train_aug, mimic_analysis, eicu_analysis,
                                    provenance, outcome_cfg, covariates,
                                    cutoff = c(4L, 10L), alpha = 0.05,
                                    joint_lock = NULL,
                                    out_pdf = NULL) {
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

  res <- rbind(
    fit_rows("MIMIC_IV", .ref_assoc_event01(mimic_analysis, "fustatus",
                                            outcome_cfg)),
    fit_rows("eICU", .ref_assoc_event01(eicu_analysis, "fustatus",
                                        outcome_cfg))
  )
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
      hit <- res[res$status == "estimable" & res$segment == "after", , drop = FALSE]
      if (nrow(hit)) {
        locked_layer <- as.character(hit$stratum[[1L]])
        locked_day <- as.numeric(hit$landmark_time[[1L]])
      } else {
        locked_layer <- "Overall"
        locked_day <- 4
      }
    }
    locked_day <- max(1, min(as.numeric(locked_day), 21))
    grp_levels <- c(
      paste0("Low ", ia, " + Low ", ib),
      paste0("Low ", ia, " + High ", ib),
      paste0("High ", ia, " + Low ", ib),
      paste0("High ", ia, " + High ", ib)
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
      # After 段在 landmark 处从 S=1 起步（原文右段重置）
      if (identical(segment, "after") && t_offset > 0) {
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
    for (src in list(
      build_km_src("MIMIC-IV", mimic_analysis),
      build_km_src("eICU", eicu_analysis)
    )) {
      d <- src$data
      if (!nrow(d)) next
      # Before: 超过 landmark 删失
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
      cdf$database <- factor(as.character(cdf$database),
                             levels = c("MIMIC-IV", "eICU"))
      ann <- do.call(rbind, p_ann)
      ann$lab <- paste0(
        "P = ", ifelse(is.na(ann$p_lr), "NE", pub_format_p_cell(ann$p_lr))
      )
      # 标注位置：before 左下；after 右上（按库分行）
      xmax <- max(c(cdf$time, 28), na.rm = TRUE)
      ann$x <- ifelse(ann$segment == "before", locked_day * 0.08, xmax * 0.72)
      ann$y <- ifelse(ann$segment == "before", 0.08, 0.92)
      ann$database <- factor(as.character(ann$database),
                             levels = levels(cdf$database))
      plt <- ggplot2::ggplot(
        cdf, ggplot2::aes(x = time, y = surv, colour = group)
      ) +
        ggplot2::geom_step(linewidth = 0.75) +
        ggplot2::geom_vline(
          xintercept = locked_day, linetype = 2, colour = "grey40",
          linewidth = 0.45
        ) +
        ggplot2::geom_text(
          data = ann, ggplot2::aes(x = x, y = y, label = lab),
          inherit.aes = FALSE, hjust = 0, size = 2.8, colour = "black"
        ) +
        # 原文单队列一张图；双库改为左右并排（非上下叠），更接近「一张联合图」观感
        ggplot2::facet_wrap(~database, ncol = 2L, scales = "fixed") +
        ggplot2::coord_cartesian(ylim = c(0, 1), xlim = c(0, max(28, xmax))) +
        ggplot2::scale_colour_manual(
          values = grp_cols, breaks = grp_levels, drop = FALSE
        ) +
        ggplot2::scale_x_continuous(
          breaks = sort(unique(c(0, locked_day, 10, 20, 28)))
        ) +
        ggplot2::labs(
          x = "Time (day)", y = "Survival Probability", colour = NULL,
          title = paste0(
            "Figure 5. Landmark survival analysis of ", .ref_joint_lab(),
            " groups"
          ),
          subtitle = sprintf(
            "Locked in MIMIC: %s, day %s (dashed line); eICU applies the same lock",
            locked_layer, as.integer(locked_day)
          )
        ) +
        ggplot2::theme_bw(base_size = 9) +
        ggplot2::theme(
          # 双库并排：图例横排置于图底（避免压住 landmark 后塌缩曲线）
          legend.position = "bottom",
          legend.direction = "horizontal",
          legend.key.height = grid::unit(0.4, "lines"),
          legend.key.width = grid::unit(1.1, "lines"),
          legend.text = ggplot2::element_text(size = 7),
          legend.margin = ggplot2::margin(0, 0, 0, 0),
          plot.title = ggplot2::element_text(size = 10, face = "bold"),
          plot.subtitle = ggplot2::element_text(size = 7.5),
          panel.grid.minor = ggplot2::element_blank(),
          strip.text = ggplot2::element_text(face = "bold", size = 9),
          strip.background = ggplot2::element_rect(fill = "grey92")
        ) +
        ggplot2::guides(colour = ggplot2::guide_legend(nrow = 1L, byrow = TRUE))
      path <- out_pdf
      dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
      pipeline_ggsave_pdf(path, plt, width = 11, height = 4.6)
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
# Figure 6: clinical-subgroup forest (Model 2), highest vs lowest tertile
#   Panels = 2 databases x 2 indices (SOSM / WPR), matching original Fig.6A/B
#   Rows = Overall + each clinical subgroup level; per-subgroup P-interaction
# --------------------------------------------------------------------------

#' 双库共有的临床亚组变量（Age 二分类 <65/>=65；其余为二值/因子水平）。
ref_assoc_fig6_subgroups <- c(
  "Age", "Gender", "Race", "Hypertension", "Diabetes", "CKD",
  "Ventilation", "Heart_Failure", "COPD", "Cancer", "Myocardial_Infarction"
)

#' 每层拟合 Model2 Cox（index 传入的是 .ex 数值列），返回该层 HR。
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
    models <- db$models
    age_sex_nm <- .ref_assoc_age_sex_model_name(models)
    full_nm <- .ref_assoc_full_model_name(models)
    m1 <- models[[age_sex_nm]]
    if (!length(m1)) m1 <- intersect(c("Age", "Gender", "Sex"), names(d))
    m2 <- models[[full_nm]]
    if (!length(m2)) m2 <- m1
    for (index in c(ia, ib)) {
      lock <- if (identical(index, ia)) db$sosm_lock else db$wpr_lock
      tert <- .ref_assoc_tertile3(d, index, lock, db$train_ref)
      # 暴露列 .ex = T3(1) vs T1(0)，T2 丢弃
      d$.ex <- as.integer(as.character(tert) == "T3")
      d$.ex[is.na(tert) | as.character(tert) == "T2"] <- NA_integer_
      keep <- !is.na(d$.ex)
      # 亚组森林默认 Age+Sex（Model2）；全调整 Model3 高维层内容易准分离 → 空面。
      covs_ov <- setdiff(m1, c(index, "SOFA", "SOFA_layer"))
      ov <- .ref_assoc_fig6_stratum_hr(
        d[keep, , drop = FALSE], ".ex", covs_ov, "futime", "event", db$outcome_cfg
      )
      if (!identical(ov$status, "estimable") && length(m2)) {
        covs2 <- setdiff(m2, c(index, "SOFA", "SOFA_layer"))
        ov2 <- .ref_assoc_fig6_stratum_hr(
          d[keep, , drop = FALSE], ".ex", covs2, "futime", "event", db$outcome_cfg
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
        covs <- setdiff(m1, c(index, "SOFA", "SOFA_layer", sg))
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
          if (!identical(r$status, "estimable") && length(m2)) {
            covs2 <- setdiff(m2, c(index, "SOFA", "SOFA_layer", sg))
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
          Variable = sg,
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
      tm <- forestploter::forest_theme(
        base_size = 9,
        refline_gp = grid::gpar(col = "grey50", lty = 2, lwd = 1),
        ci_pch = 15, ci_col = "#2C7BB6", ci_fill = "#2C7BB6",
        ci_lty = 1, ci_lwd = 1.4, ci_Theight = 0.18,
        core = list(fg_params = list(hjust = 0, x = 0.01),
                    bg_params = list(fill = c("#ffffff", "#f7f7f7")))
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
    est$database_f <- .ref_assoc_factor_db(est$database, short = FALSE)
    levels(est$database_f) <- .ref_assoc_db_levels(short = TRUE)
    db_lv <- levels(est$database_f)
    common_sgs <- ref_assoc_fig6_subgroups
    if (length(db_lv) >= 2L) {
      sg_by_db <- lapply(db_lv, function(dbn) {
        unique(as.character(est$subgroup[
          as.character(est$database_f) == dbn & est$subgroup != "Overall"
        ]))
      })
      common_sgs <- Reduce(intersect, c(list(ref_assoc_fig6_subgroups), sg_by_db))
    }
    est <- est[est$subgroup == "Overall" | est$subgroup %in% common_sgs, ,
               drop = FALSE]

    # 主库在前；面板字母 A–D（勿重复 A/B）
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
    # 各面板单独按 get_wh 落临时 PDF，再用 magick 2×2 合成。
    tmp_dir <- tempfile("fig6_panels_")
    dir.create(tmp_dir, recursive = TRUE)
    on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)
    panel_pngs <- character(0)
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
      pdf_i <- file.path(tmp_dir, sprintf("panel_%s.pdf", ps$letter))
      png_i <- file.path(tmp_dir, sprintf("panel_%s.png", ps$letter))
      # 整页只画 forest（禁止再套 viewport，否则表头/行会叠画）
      grDevices::pdf(pdf_i, width = fig_w, height = fig_h, onefile = TRUE)
      grid::grid.newpage()
      grid::grid.draw(grob)
      grDevices::dev.off()
      # ImageMagick 常禁 PDF coder → 一律 pdftools 栅格化，再用 magick 拼图
      if (!requireNamespace("pdftools", quietly = TRUE) ||
          !requireNamespace("magick", quietly = TRUE)) {
        stop("Figure 6 compose needs pdftools + magick.", call. = FALSE)
      }
      pdftools::pdf_convert(pdf_i, format = "png", dpi = 200,
                            filenames = png_i, verbose = FALSE)
      im <- magick::image_read(png_i)
      title_h <- 48L
      title_bar <- magick::image_blank(
        magick::image_info(im)$width, title_h, "white"
      )
      title_bar <- magick::image_annotate(
        title_bar,
        text = sprintf("%s  %s | %s", ps$letter, ps$dbn, ps$index),
        size = 22, gravity = "west", location = "+12+0", weight = 700
      )
      im <- magick::image_append(c(title_bar, im), stack = TRUE)
      magick::image_write(im, path = png_i, format = "png")
      panel_pngs <- c(panel_pngs, png_i)
    }

    path <- out_pdf
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    n_col <- 2L
    n_row <- as.integer(ceiling(length(panel_pngs) / n_col))
    imgs <- lapply(panel_pngs, magick::image_read)
    # 统一各面板画布高度（取最大）再拼，避免行高错位
    target_h <- max(vapply(imgs, function(im) magick::image_info(im)$height, numeric(1)))
    imgs <- lapply(imgs, function(im) {
      info <- magick::image_info(im)
      if (info$height < target_h) {
        magick::image_extent(
          im, geometry = sprintf("%dx%d", info$width, as.integer(target_h)),
          gravity = "north", color = "white"
        )
      } else im
    })
    rows_im <- list()
    for (r in seq_len(n_row)) {
      ii <- ((r - 1L) * n_col + 1L):min(r * n_col, length(imgs))
      row_imgs <- imgs[ii]
      while (length(row_imgs) < n_col) {
        blank <- magick::image_blank(
          magick::image_info(row_imgs[[1]])$width,
          magick::image_info(row_imgs[[1]])$height, "white"
        )
        row_imgs[[length(row_imgs) + 1L]] <- blank
      }
      rows_im[[r]] <- magick::image_append(do.call(c, row_imgs), stack = FALSE)
    }
    body <- if (length(rows_im) == 1L) rows_im[[1]] else
      magick::image_append(do.call(c, rows_im), stack = TRUE)
    # 总标题 + 脚注条
    bw <- magick::image_info(body)$width
    title_bar <- magick::image_blank(bw, 70, "white")
    title_bar <- magick::image_annotate(
      title_bar,
      text = paste0("Figure 6. Subgroup analyses of ", ia, " and ", ib,
                    " for 28-day mortality"),
      size = 28, gravity = "west", location = "+20+0", weight = 700
    )
    foot_bar <- magick::image_blank(bw, 55, "white")
    foot_bar <- magick::image_annotate(
      foot_bar,
      text = paste0(
        "Exposure contrast = highest vs lowest tertile of ", ia, " / ", ib,
        ". Subgroups aligned across databases: ",
        paste(common_sgs, collapse = ", "), "."
      ),
      size = 16, gravity = "west", location = "+20+0", color = "#555555"
    )
    final_im <- magick::image_append(c(title_bar, body, foot_bar), stack = TRUE)
    tmp_png <- file.path(tmp_dir, "fig6_compose.png")
    magick::image_write(final_im, path = tmp_png, format = "png")
    # 勿用 magick 写 PDF（ImageMagick PDF policy 常拦截）；改 raster → cairo/pdf
    info <- magick::image_info(final_im)
    fig_w_in <- info$width / 200
    fig_h_in <- info$height / 200
    raster <- as.raster(final_im)
    if (requireNamespace("grDevices", quietly = TRUE) &&
        is.function(grDevices::cairo_pdf)) {
      grDevices::cairo_pdf(path, width = fig_w_in, height = fig_h_in)
    } else {
      grDevices::pdf(path, width = fig_w_in, height = fig_h_in, onefile = TRUE)
    }
    grid::grid.newpage()
    grid::grid.raster(raster, interpolate = TRUE)
    grDevices::dev.off()
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
                              indices = c("SOSM", "WPR")) {
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
  fig2 <- ref_assoc_fig2_km(
    db_frames, cutoff = cutoff,
    out_pdf = file.path(
      fig_dir, paste0("Figure 2. KM ", ia, " ", ib, " joint by SOFA strata.pdf")
    )
  )
  notes <- c(notes, sprintf("Fig2 not_estimable panels: %d/12",
                            sum(fig2$panels$status != "estimable")))

  # -- Figure 3 --------------------------------------------------------------
  fig3 <- ref_assoc_fig3_rcs(
    db_frames, cutoff = cutoff, grid_n = grid_n,
    out_pdf = file.path(
      fig_dir, paste0("Figure 3. Grouped RCS ", ia, " ", ib, " by SOFA strata.pdf")
    )
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
    ia, " for ", ia, ", ", ib, ", joint group score, APSIII, OASIS and GCS, by ",
    "database and SOFA stratum (28-day all-cause mortality)."
  )
  s5_out <- fig4$auc
  s5_out$predictor[s5_out$predictor == "Joint"] <- .ref_joint_lab()
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
  names(s5_export) <- c("Database", "SOFA stratum", "Predictor", "N",
                        "Events", "AUC", "95% CI", paste0("DeLong P vs ", ia),
                        "Status")
  files <- list(
    S5 = .ref_assoc_export_xlsx(
      file.path(tab_dir, "Table S5 ROC discrimination DeLong.xlsx"),
      s5_title, s5_export
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
  fig5 <- ref_assoc_fig5_landmark(
    train_aug = train_aug, mimic_analysis = mimic$analysis,
    eicu_analysis = eicu$analysis, provenance = provenance,
    outcome_cfg = mimic$config, covariates = fig5_covs, cutoff = cutoff,
    joint_lock = joint_lock,
    out_pdf = file.path(fig_dir, "Figure 5. Landmark before after Cox.pdf")
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
    "Table 2. Association of ", ilab, " joint groups with 28-day all-cause ",
    "mortality (Cox regression; Group1 low/low = reference)."
  )
  lit_t2 <- any(as.character(t2$model) == "Model3", na.rm = TRUE)
  t2_footnotes <- if (isTRUE(lit_t2)) {
    c(
      paste0(
        "Model 1: unadjusted; Model 2: age and sex; Model 3: clinically meaningful ",
        "indicators that were significant in univariate analysis, with collinearity ",
        "controlled (VIF < 5)."
      ),
      "SOFA strata 0-4 / 5-10 / >=11. Joint groups from MIMIC development-frozen upper-tertile cutpoints.",
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
      "SOFA strata 0-4 / 5-10 / >=11. Joint groups from MIMIC development-frozen upper-tertile cutpoints.",
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
    "with 28-day all-cause mortality, Overall and by SOFA stratum."
  )
  s4_export <- s4
  names(s4_export) <- c("Database", "SOFA stratum", "Index", "Coding",
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
  layer_labs <- ref_assoc_layer_labels(cutoff)
  layer_labs <- layer_labs[layer_labs != "Overall"]
  ph_keys <- paste0("S", seq_along(layer_labs) + 5L)  # S6, S7, S8
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
  names(s9_export) <- c("Database", "SOFA stratum", "Model", "Group",
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
  names(s10_export) <- c("Database", "SOFA stratum", "Model", "Group",
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
