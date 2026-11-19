###############################################################################
# cum_egdr_kmeans_pub.R — 两波 k-means 累积暴露发表层 helpers（跨课题复用）
#
# 依赖：R/literature_ckm_cum_egdr.R（数据/索引/kmeans/OR-HR）
# 入口：run/cum_egdr_kmeans_ckm/rebuild_publication.R
# 下一课题（CHARLS 两波 × 任意 index）：用 cfg 覆盖 class_map / 暴露列 / 标签即可。
###############################################################################

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || (length(x) == 1L && is.na(x))) y else x
}

.ckm_pub_ensure_literature <- function(root = NULL) {
  root <- root %||% Sys.getenv("BLOCK_REPO_ROOT", unset = "")
  if (!nzchar(root)) root <- getwd()
  lit <- file.path(root, "R", "literature_ckm_cum_egdr.R")
  if (file.exists(lit) && !exists("ckm_stroke_fit_or_row", mode = "function")) {
    source(lit, local = FALSE)
  }
  invisible(TRUE)
}

# -----------------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------------
ckm_stroke_resolve_engine_paths <- function(
    engine_win = "E:/01block/01Block-new-Final",
    engine_wsl = "/mnt/e/01block/01Block-new-Final",
    result_win = "G:/02block_result",
    result_wsl = "/mnt/g/02block_result") {
  is_linux <- identical(.Platform$OS.type, "unix")
  root <- if (is_linux && dir.exists(engine_wsl)) engine_wsl else if (dir.exists(engine_win)) engine_win else engine_wsl
  res_root <- if (is_linux && dir.exists(result_wsl)) result_wsl else if (dir.exists(result_win)) result_win else result_wsl
  list(root = root, res_root = res_root, is_linux = is_linux)
}

ckm_stroke_default_project_paths <- function(
    res_root,
    study_rel = file.path("46_CKM", "\u7d2f\u8ba1\u66b4\u9732\u805a\u7c7b_41654871"),
    index = "eGDR") {
  proj <- file.path(res_root, study_rel)
  list(
    proj = proj,
    checkpoint = file.path(proj, "by_unit", paste0("\u3010success\u3011", index),
                           "checkpoints", "table1_by_class_ckm.rds"),
    elbow_csv = file.path(proj, "by_unit", paste0("\u3010success\u3011", index),
                          "by_index", index, "Tables", "Kmeans_elbow_WCSS.csv"),
    summary = file.path(proj, "by_index", paste0("\u3010success\u3011", index), "summary_results"),
    tables = file.path(proj, "by_index", paste0("\u3010success\u3011", index), "summary_results", "Tables"),
    figures = file.path(proj, "by_index", paste0("\u3010success\u3011", index), "summary_results", "Figures")
  )
}

# -----------------------------------------------------------------------------
# Class map (paper Class 1–4) — disease-agnostic via overrides
# 编号仍固定：Persistent_low→Class2 等；参照类按指标方向重挑，不再写死 Class 2
# -----------------------------------------------------------------------------

# 指标方向：higher_better（如 eGDR）vs higher_worse（ABSI/WWI/ePWV 等）
ckm_stroke_index_risk_direction <- function(index_name) {
  idx <- as.character(index_name %||% "")[1L]
  if (!nzchar(idx)) return("higher_worse")
  if (grepl("^eGDR$", idx, ignore.case = TRUE)) return("higher_better")
  "higher_worse"
}

# 按本指标数据挑参照 Class（返回 paper Class 名 + 语义名 + 理由）
ckm_stroke_pick_ref_class <- function(
    data,
    index_name,
    class_col = "Class_paper",
    t1_col = "eGDR_t1",
    outcome = NULL,
    policy = c("direction_mean", "lowest_event_rate", "force"),
    force_ref_class = NULL,
    cmap_base = NULL,
    t1_wave_lab = "Wave 4") {
  policy <- match.arg(policy)
  cmap_base <- cmap_base %||% ckm_stroke_class_map_paper()
  classes <- as.character(cmap_base$order_paper)
  .t1_lab <- as.character(t1_wave_lab %||% "Wave 4")[1L]
  if (!nzchar(.t1_lab)) .t1_lab <- "Wave 4"
  if (!class_col %in% names(data)) {
    stop("ckm_stroke_pick_ref_class: missing ", class_col, call. = FALSE)
  }
  if (identical(policy, "force") && !is.null(force_ref_class) &&
      as.character(force_ref_class)[1L] %in% classes) {
    ref_cl <- as.character(force_ref_class)[1L]
    reason <- sprintf("forced reference %s", ref_cl)
  } else if (identical(policy, "lowest_event_rate") &&
             !is.null(outcome) && outcome %in% names(data)) {
    y <- as.integer(as.numeric(data[[outcome]]) == 1L)
    rates <- vapply(classes, function(cl) {
      keep <- as.character(data[[class_col]]) == cl
      if (!any(keep)) return(Inf)
      mean(y[keep], na.rm = TRUE)
    }, numeric(1))
    ref_cl <- names(which.min(rates))[1L]
    reason <- sprintf(
      "lowest crude event rate (%.1f%%) among Class 1–4",
      100 * as.numeric(rates[[ref_cl]])
    )
  } else {
    # direction_mean（默认）：higher_worse → 最低 t1 均值类；higher_better → 最高
    if (!t1_col %in% names(data)) {
      stop("ckm_stroke_pick_ref_class: missing ", t1_col, call. = FALSE)
    }
    means <- vapply(classes, function(cl) {
      keep <- as.character(data[[class_col]]) == cl
      mean(as.numeric(data[[t1_col]][keep]), na.rm = TRUE)
    }, numeric(1))
    direction <- ckm_stroke_index_risk_direction(index_name)
    if (identical(direction, "higher_better")) {
      ref_cl <- names(which.max(means))[1L]
      reason <- sprintf(
        "%s is higher-better; reference = highest %s mean class (%s, mean=%.3f)",
        index_name, .t1_lab, ref_cl, as.numeric(means[[ref_cl]])
      )
    } else {
      ref_cl <- names(which.min(means))[1L]
      reason <- sprintf(
        "%s is higher-worse; reference = lowest %s mean class (%s, mean=%.3f)",
        index_name, .t1_lab, ref_cl, as.numeric(means[[ref_cl]])
      )
    }
  }
  ref_sem <- as.character(cmap_base$semantic_of[[ref_cl]] %||% NA_character_)[1L]
  if (!nzchar(ref_sem) || is.na(ref_sem)) {
    # semantic_of 是 Class→语义；map 是语义→Class
    hit <- names(cmap_base$map)[cmap_base$map == ref_cl]
    ref_sem <- if (length(hit)) hit[[1L]] else NA_character_
  }
  list(
    ref_class = ref_cl,
    ref_semantic = ref_sem,
    reason = reason,
    policy = policy,
    order_table_ref_first = c(ref_cl, setdiff(classes, ref_cl))
  )
}

ckm_stroke_class_map_paper <- function(
    map = c(
      Moderate_high_stable = "Class 1",
      Persistent_low = "Class 2",
      Stable_high = "Class 3",
      Rapid_decrease = "Class 4"
    ),
    order_paper = c("Class 1", "Class 2", "Class 3", "Class 4"),
    order_table_ref_first = NULL,
    colors = c(`Class 1` = "#E41A1C", `Class 2` = "#4DAF4A",
               `Class 3` = "#377EB8", `Class 4` = "#984EA3"),
    shapes = c(`Class 1` = 16, `Class 2` = 17, `Class 3` = 15, `Class 4` = 8),
    semantic_of = NULL,
    ref_class = NULL,
    ref_semantic = NULL,
    ref_reason = NULL) {
  if (is.null(semantic_of)) {
    semantic_of <- setNames(names(map), unname(map))
  }
  # 默认仍可用 Persistent_low/Class2，但正式发表须经 ckm_stroke_class_map_for_index 重挑
  if (is.null(ref_class)) ref_class <- "Class 2"
  if (is.null(ref_semantic)) {
    ref_semantic <- names(map)[map == ref_class]
    ref_semantic <- if (length(ref_semantic)) ref_semantic[[1L]] else "Persistent_low"
  }
  if (is.null(order_table_ref_first)) {
    order_table_ref_first <- c(ref_class, setdiff(order_paper, ref_class))
  }
  list(
    map = map,
    order_paper = order_paper,
    order_table_ref_first = order_table_ref_first,
    colors = colors,
    shapes = shapes,
    semantic_of = semantic_of,
    ref_class = as.character(ref_class)[1L],
    ref_semantic = as.character(ref_semantic)[1L],
    ref_reason = as.character(ref_reason %||% "")[1L]
  )
}

# 按数据中实际出现的语义类建 map（k=3 时无 Rapid_decrease / Class 4）
ckm_stroke_class_map_from_present <- function(semantic) {
  sem <- unique(as.character(stats::na.omit(semantic)))
  # 固定文献编号：中高稳→1，持续低→2，稳定高→3，快速降→4；缺谁丢谁
  full_map <- c(
    Moderate_high_stable = "Class 1",
    Persistent_low = "Class 2",
    Stable_high = "Class 3",
    Rapid_decrease = "Class 4"
  )
  keep <- names(full_map)[names(full_map) %in% sem]
  if (!length(keep)) keep <- names(full_map)
  map <- full_map[keep]
  order_paper <- unname(map)
  ckm_stroke_class_map_paper(
    map = map,
    order_paper = order_paper,
    ref_class = if ("Persistent_low" %in% names(map)) map[["Persistent_low"]] else order_paper[1L],
    ref_semantic = if ("Persistent_low" %in% names(map)) "Persistent_low" else names(map)[1L]
  )
}

# 编号随实际类数 + 按指标数据重挑参照
ckm_stroke_class_map_for_index <- function(
    data,
    index_name,
    class_col = "Class_paper",
    t1_col = "eGDR_t1",
    outcome = NULL,
    policy = "direction_mean",
    force_ref_class = NULL,
    semantic_col = "eGDR_Class",
    t1_wave_lab = "Wave 4") {
  # 优先用语义列推断实际类数
  if (semantic_col %in% names(data)) {
    base <- ckm_stroke_class_map_from_present(data[[semantic_col]])
  } else {
    base <- ckm_stroke_class_map_paper()
  }
  # 若尚未挂 Class_paper，先按语义编号挂一次
  if (!class_col %in% names(data) && semantic_col %in% names(data)) {
    data <- ckm_stroke_attach_class_paper(data, semantic_col, base)
    class_col <- "Class_paper"
  }
  picked <- ckm_stroke_pick_ref_class(
    data,
    index_name = index_name,
    class_col = class_col,
    t1_col = t1_col,
    outcome = outcome,
    policy = policy,
    force_ref_class = force_ref_class,
    cmap_base = base,
    t1_wave_lab = t1_wave_lab
  )
  ckm_stroke_class_map_paper(
    map = base$map,
    order_paper = base$order_paper,
    ref_class = picked$ref_class,
    ref_semantic = picked$ref_semantic,
    order_table_ref_first = picked$order_table_ref_first,
    ref_reason = picked$reason
  )
}

ckm_stroke_attach_class_paper <- function(data, class_col = "eGDR_Class",
                                          cmap = ckm_stroke_class_map_paper()) {
  stopifnot(class_col %in% names(data))
  data$Class_paper <- factor(
    unname(cmap$map[as.character(data[[class_col]])]),
    levels = cmap$order_paper
  )
  ref_sem <- as.character(cmap$ref_semantic %||% "Persistent_low")[1L]
  data[[class_col]] <- .ckm_relevel_class_safe(
    factor(data[[class_col]]),
    ref_sem
  )
  data
}

# 类别展示名只看本数据的波次均值变化。文献四类名（尤其 Rapid decrease）
# 不得在 |mean Δ| 小于类间极差 25% 时沿用。
ckm_stroke_class_display_labels <- function(
    data,
    class_col = "Class_paper",
    t1_col = "eGDR_t1",
    t2_col = "eGDR_t2",
    cmap = ckm_stroke_class_map_paper(),
    rapid_frac = 0.25,
    t1_wave_lab = "Wave 4",
    t2_wave_lab = "Wave 6") {
  present <- intersect(
    as.character(cmap$order_paper),
    unique(as.character(stats::na.omit(data[[class_col]])))
  )
  if (!length(present)) {
    present <- unique(as.character(stats::na.omit(data[[class_col]])))
  }
  rows <- lapply(present, function(cl) {
    keep <- as.character(data[[class_col]]) == cl
    t1 <- as.numeric(data[[t1_col]][keep])
    t2 <- as.numeric(data[[t2_col]][keep])
    dlt <- t2 - t1
    data.frame(
      class = cl, n = sum(keep),
      mean_t1 = mean(t1, na.rm = TRUE),
      mean_t2 = mean(t2, na.rm = TRUE),
      mean_delta = mean(dlt, na.rm = TRUE),
      median_delta = stats::median(dlt, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  })
  sm <- do.call(rbind, rows)
  rng <- max(sm$mean_t1, na.rm = TRUE) - min(sm$mean_t1, na.rm = TRUE)
  thr <- rapid_frac * rng
  if (!is.finite(thr) || thr <= 0) thr <- Inf
  mid_cut <- stats::median(sm$mean_t1, na.rm = TRUE)
  sm$rapid <- is.finite(sm$mean_delta) & sm$mean_delta < 0 & abs(sm$mean_delta) >= thr
  sm$display <- vapply(seq_len(nrow(sm)), function(i) {
    if (isTRUE(sm$rapid[i])) return("Rapid decrease")
    mt <- sm$mean_t1[i]
    if (!is.finite(mt)) return(as.character(sm$class[i]))
    if (mt <= min(sm$mean_t1, na.rm = TRUE) + 1e-8) return("Persistent low")
    if (mt >= max(sm$mean_t1, na.rm = TRUE) - 1e-8) return("Stable high")
    if (is.finite(mid_cut) && mt >= mid_cut) return("Moderate-high stable")
    "Intermediate stable"
  }, character(1))
  # 重名时加上类号，避免两行脚注无法区分
  dup <- sm$display[duplicated(sm$display) | duplicated(sm$display, fromLast = TRUE)]
  if (length(dup)) {
    hit <- sm$display %in% unique(dup)
    sm$display[hit] <- paste0(sm$display[hit], " (", sm$class[hit], ")")
  }
  .w1 <- as.character(t1_wave_lab %||% "Wave 4")[1L]
  .w2 <- as.character(t2_wave_lab %||% "Wave 6")[1L]
  if (!nzchar(.w1)) .w1 <- "Wave 4"
  if (!nzchar(.w2)) .w2 <- "Wave 6"
  # Krakauer ABSI 等小量纲：%.2f 会把 0.077/0.084/0.090 全收成 0.08，脚注不可辨
  .mag <- max(abs(c(sm$mean_t1, sm$mean_t2, sm$median_delta, thr)), na.rm = TRUE)
  .nd <- if (!is.finite(.mag) || .mag >= 1) 2L else if (.mag >= 0.1) 3L else 4L
  .fmt <- function(x) sprintf(paste0("%.", .nd, "f"), x)
  phrase <- function(i) {
    sprintf(
      "%s = %s (%s mean %s, %s mean %s, median within-person change %s)",
      sm$class[i], sm$display[i], .w1, .fmt(sm$mean_t1[i]), .w2, .fmt(sm$mean_t2[i]),
      .fmt(sm$median_delta[i])
    )
  }
  footnote <- paste(vapply(seq_len(nrow(sm)), phrase, character(1)), collapse = "; ")
  footnote <- paste0(
    "Class labels follow the observed trajectory. A decline is named rapid only when the absolute mean change is at least ",
    sprintf("%.0f%%", 100 * rapid_frac),
    " of the between-class range of ", .w1, " means (threshold ",
    .fmt(thr),
    "). ",
    footnote, "."
  )
  labels <- setNames(
    paste0(sm$class, ": ", sm$display),
    sm$class
  )
  list(summary = sm, labels = labels, footnote = footnote, rapid_threshold = thr)
}

# Safe relevel: if reference level absent in a stratum, keep factor as-is (fit returns NE)
.ckm_relevel_class_safe <- function(x, ref) {
  x <- factor(x)
  if (as.character(ref)[1L] %in% levels(x)) {
    stats::relevel(x, ref = as.character(ref)[1L])
  } else {
    x
  }
}

# -----------------------------------------------------------------------------
# Formatting（对标 Wang 2026 CVD 25:78；OR 三位为引擎铁律）
# -----------------------------------------------------------------------------
# Wang 原文：OR/CI 多为 2 位；P 为 3 位或 <0.001；Table1 mean(SD) 多为 2 位；% 多为 1 位。
# 本引擎 OR/HR/CI **固定 3 位**（含尾随 0），避免两位把相近模型收成同一字符串。
ckm_stroke_pub_digits <- function() {
  list(est = 3L, p = 3L, desc = 2L, pct = 1L, cutoff = 3L)
}
ckm_stroke_fmt_p <- function(p) {
  if (length(p) != 1L || is.na(p)) return("")
  dig <- as.integer(ckm_stroke_pub_digits()$p %||% 3L)[1L]
  if (p < 0.001) "<0.001" else sprintf(paste0("%.", dig, "f"), p)
}
ckm_stroke_fmt_orci <- function(or, lo, hi) {
  if (!is.finite(or) || !is.finite(lo) || !is.finite(hi)) return("NE")
  dig <- as.integer(ckm_stroke_pub_digits()$est %||% 3L)[1L]
  sprintf(paste0("%.", dig, "f (%.", dig, "f\u2013%.", dig, "f)"), or, lo, hi)
}
ckm_stroke_fmt_or_tilde <- function(est, lo, hi, digits = 3L) {
  # 与表内 OR/HR 一致：en-dash（–），不用波浪号 ~
  if (!is.finite(est) || !is.finite(lo) || !is.finite(hi)) return("")
  sprintf(
    paste0("%.", digits, "f (%.", digits, "f\u2013%.", digits, "f)"),
    est, lo, hi
  )
}
ckm_stroke_mean_sd <- function(x) {
  x <- as.numeric(x); x <- x[is.finite(x)]
  if (!length(x)) return("")
  sprintf("%.2f (%.2f)", mean(x), stats::sd(x))
}
ckm_stroke_n_pct <- function(n, den) {
  if (!is.finite(den) || den <= 0) return("")
  sprintf("%d (%.1f)", as.integer(n), 100 * n / den)
}
ckm_stroke_events_cell <- function(y) {
  y <- as.integer(y == 1L)
  ckm_stroke_n_pct(sum(y, na.rm = TRUE), sum(!is.na(y)))
}

# -----------------------------------------------------------------------------
# Forest / subgroup groups
# -----------------------------------------------------------------------------
ckm_stroke_prepare_forest_groups <- function(
    df,
    age_cutoff = 60L,
    bmi_cut = 30,
    age_labels_compact = TRUE,
    drop_extreme_bmi = FALSE,
    ckm_col = "CKM_stage") {
  .ckm_pub_ensure_literature()
  df <- ckm_stroke_prepare_age_group(df, age_cutoff)
  cut <- as.numeric(age_cutoff)[1L]
  if ("Age" %in% names(df)) {
    if (isTRUE(age_labels_compact)) {
      df$Age_Group <- factor(
        ifelse(as.numeric(df$Age) < cut, paste0("<", cut), paste0(">=", cut)),
        levels = c(paste0("<", cut), paste0(">=", cut))
      )
    } else {
      df$Age_Group <- factor(
        ifelse(as.numeric(df$Age) < cut, paste0("< ", cut), paste0("\u2265 ", cut)),
        levels = c(paste0("< ", cut), paste0("\u2265 ", cut))
      )
    }
  }
  if ("BMI" %in% names(df)) {
    bmi <- as.numeric(df$BMI)
    if (isTRUE(drop_extreme_bmi)) {
      bmi[!is.finite(bmi) | bmi < 10 | bmi > 80] <- NA_real_
      df$BMI <- bmi
    }
    lab_lo <- if (isTRUE(age_labels_compact)) paste0("<", bmi_cut) else paste0("< ", bmi_cut)
    lab_hi <- if (isTRUE(age_labels_compact)) paste0(">=", bmi_cut) else paste0("\u2265 ", bmi_cut)
    df$BMI_Group <- factor(
      ifelse(is.finite(bmi) & bmi < bmi_cut, lab_lo,
             ifelse(is.finite(bmi), lab_hi, NA_character_)),
      levels = c(lab_lo, lab_hi)
    )
  }
  .yes_no_to_never_ever <- function(x) {
    x <- as.character(x)
    out <- rep(NA_character_, length(x))
    out[x %in% c("Yes", "Ever", "ever", "Current", "Former")] <- "Ever"
    out[x %in% c("No", "Never", "never")] <- "Never"
    factor(out, levels = c("Never", "Ever"))
  }
  if ("Smoke" %in% names(df)) df$Smoke_ne <- .yes_no_to_never_ever(df$Smoke)
  if ("Drink" %in% names(df)) df$Drink_ne <- .yes_no_to_never_ever(df$Drink)
  if (ckm_col %in% names(df)) {
    st <- as.integer(as.numeric(as.character(df[[ckm_col]])))
    # Table3 style (en-dash) + forest style (hyphen)
    df$CKM_group <- factor(
      ifelse(st %in% 0:2, "0\u20132", ifelse(st %in% 3:4, "3\u20134", NA)),
      levels = c("0\u20132", "3\u20134")
    )
    df$CKM_stage_group <- factor(
      ifelse(st %in% 0:2, "0-2", ifelse(st %in% 3:4, "3-4", NA_character_)),
      levels = c("0-2", "3-4")
    )
  }
  if ("Gender" %in% names(df)) {
    df$Gender <- factor(as.character(df$Gender), levels = c("Female", "Male"))
  }
  if (!"Hypertension" %in% names(df)) {
    if ("Hypertension_t2" %in% names(df)) {
      df$Hypertension <- df$Hypertension_t2
    } else if ("htn1" %in% names(df)) {
      df$Hypertension <- factor(
        ifelse(as.integer(df$htn1) == 1L, "Yes", "No"),
        levels = c("No", "Yes")
      )
    }
  }
  df
}

# LRT P for interaction — glm: Pr(>Chi); coxph: Pr(>|Chi|) via test=Chisq
ckm_stroke_lrt_pint <- function(df, expo, sg_var, covars, is_hr = FALSE,
                                outcome = "Stroke") {
  need <- unique(c(expo, sg_var, covars, if (is_hr) c("futime", "status") else outcome))
  need <- intersect(need, names(df))
  d <- df[, need, drop = FALSE]
  d <- d[stats::complete.cases(d), , drop = FALSE]
  if (nrow(d) < 40L) return(NA_real_)
  d[[sg_var]] <- factor(d[[sg_var]])
  if (nlevels(d[[sg_var]]) < 2L) return(NA_real_)
  if (!is_hr && outcome %in% names(d)) {
    d[[outcome]] <- as.integer(as.numeric(d[[outcome]]) == 1L)
  }
  rhs0 <- paste(c(expo, sg_var, covars), collapse = " + ")
  rhs1 <- paste(c(paste0(expo, " * ", sg_var), covars), collapse = " + ")
  if (is_hr) {
    f0 <- stats::as.formula(paste("survival::Surv(futime, status) ~", rhs0))
    f1 <- stats::as.formula(paste("survival::Surv(futime, status) ~", rhs1))
    m0 <- tryCatch(survival::coxph(f0, data = d), error = function(e) NULL)
    m1 <- tryCatch(survival::coxph(f1, data = d), error = function(e) NULL)
  } else {
    f0 <- stats::as.formula(paste(outcome, "~", rhs0))
    f1 <- stats::as.formula(paste(outcome, "~", rhs1))
    m0 <- tryCatch(stats::glm(f0, data = d, family = stats::binomial()), error = function(e) NULL)
    m1 <- tryCatch(stats::glm(f1, data = d, family = stats::binomial()), error = function(e) NULL)
  }
  if (is.null(m0) || is.null(m1)) return(NA_real_)
  a <- tryCatch({
    if (is_hr) stats::anova(m0, m1, test = "Chisq") else stats::anova(m0, m1, test = "LRT")
  }, error = function(e) NULL)
  if (is.null(a)) return(NA_real_)
  pcol <- intersect(c("Pr(>Chi)", "Pr(>|Chi|)", "Pr(>Chisq)", "P(>|Chi|)"), names(a))
  if (!length(pcol)) return(NA_real_)
  as.numeric(a[[pcol[1L]]][2L])
}

# -----------------------------------------------------------------------------
# Table 1
# -----------------------------------------------------------------------------
ckm_stroke_build_table1_by_class <- function(
    data,
    class_col = "Class_paper",
    cmap = ckm_stroke_class_map_paper(),
    exposure_cols = c(cum = "cum_eGDR", t1 = "eGDR_t1", t2 = "eGDR_t2"),
    exposure_labs = c(
      cum = "Cumulative eGDR, mean (SD)",
      t1 = "eGDR2012, mean (SD)",
      t2 = "eGDR2015, mean (SD)"
    ),
    outcome = "Stroke",
    outcome_lab = "Incident stroke, n (%)") {
  levels_cls <- as.character(cmap$order_paper %||% c("Class 1", "Class 2", "Class 3", "Class 4"))
  # 仅保留样本中实际出现的类（k=3 时无 Class 4）
  present <- intersect(levels_cls, unique(as.character(data[[class_col]])))
  if (length(present)) levels_cls <- present
  cls <- factor(data[[class_col]], levels = levels_cls)
  n_all <- nrow(data)
  n_by_class <- as.integer(table(cls))
  names(n_by_class) <- names(table(cls))

  .row_shell <- function(lab, overall, by_named, p = "") {
    out <- data.frame(Characteristics = lab, Overall = overall,
                      check.names = FALSE, stringsAsFactors = FALSE)
    for (lv in levels_cls) out[[lv]] <- as.character(by_named[[lv]] %||% "")
    out[["P-value"]] <- p
    out
  }
  .empty_row <- function(lab, p = "") {
    .row_shell(lab, "", setNames(rep("", length(levels_cls)), levels_cls), p)
  }
  .cont_row <- function(lab, x) {
    overall <- ckm_stroke_mean_sd(x)
    by <- vapply(levels_cls, function(lv) ckm_stroke_mean_sd(x[as.character(cls) == lv]), character(1))
    names(by) <- levels_cls
    pv <- tryCatch(stats::kruskal.test(x ~ cls)$p.value, error = function(e) NA_real_)
    .row_shell(lab, overall, by, ckm_stroke_fmt_p(pv))
  }
  .cat_block <- function(lab, x) {
    x <- factor(x)
    pv <- tryCatch(suppressWarnings(stats::chisq.test(table(x, cls))$p.value),
                   error = function(e) NA_real_)
    rows <- list(.empty_row(lab, ckm_stroke_fmt_p(pv)))
    for (lvx in levels(x)) {
      n_o <- sum(as.character(x) == lvx, na.rm = TRUE)
      den_o <- sum(!is.na(x))
      by <- vapply(levels_cls, function(lv) {
        keep <- as.character(cls) == lv
        n <- sum(as.character(x[keep]) == lvx, na.rm = TRUE)
        den <- sum(!is.na(x[keep]))
        ckm_stroke_n_pct(n, den)
      }, character(1))
      names(by) <- levels_cls
      rows[[length(rows) + 1L]] <- .row_shell(
        paste0("  ", lvx), ckm_stroke_n_pct(n_o, den_o), by, ""
      )
    }
    do.call(rbind, rows)
  }

  parts <- list()
  parts[[length(parts) + 1L]] <- .empty_row("Demographics")
  if ("Age" %in% names(data)) parts[[length(parts) + 1L]] <- .cont_row("Age, mean (SD), years", data$Age)
  if ("Gender" %in% names(data)) parts[[length(parts) + 1L]] <- .cat_block("Gender, n (%)", data$Gender)
  if ("BMI" %in% names(data)) parts[[length(parts) + 1L]] <- .cont_row("BMI, mean (SD), kg/m\u00b2", data$BMI)
  if ("Education" %in% names(data)) parts[[length(parts) + 1L]] <- .cat_block("Educational level, n (%)", data$Education)
  if ("Smoke" %in% names(data)) {
    sm <- factor(ifelse(as.character(data$Smoke) == "Yes", "Ever",
                 ifelse(as.character(data$Smoke) == "No", "Never", NA_character_)),
                 levels = c("Never", "Ever"))
    parts[[length(parts) + 1L]] <- .cat_block("Smoking status, n (%)", sm)
  }
  if ("Drink" %in% names(data)) {
    dr <- factor(ifelse(as.character(data$Drink) == "Yes", "Ever",
                 ifelse(as.character(data$Drink) == "No", "Never", NA_character_)),
                 levels = c("Never", "Ever"))
    parts[[length(parts) + 1L]] <- .cat_block("Drinking status, n (%)", dr)
  }
  if ("Marital" %in% names(data)) parts[[length(parts) + 1L]] <- .cat_block("Marital status, n (%)", data$Marital)

  parts[[length(parts) + 1L]] <- .empty_row("Vital signs and laboratory tests")
  for (v in c("SBP", "DBP", "Waist_circumference", "Glucose", "Total_Cholesterol",
              "Triglycerides", "HDL", "LDL", "HbA1c", "UA", "eGFR")) {
    if (!v %in% names(data)) next
    lab <- switch(v,
      SBP = "SBP, mean (SD), mmHg", DBP = "DBP, mean (SD), mmHg",
      Waist_circumference = "WC, mean (SD), cm",
      Glucose = "Glucose, mean (SD), mg/dL",
      Total_Cholesterol = "TC, mean (SD), mg/dL",
      Triglycerides = "TG, mean (SD), mg/dL",
      HDL = "HDL, mean (SD), mg/dL", LDL = "LDL, mean (SD), mg/dL",
      HbA1c = "HbA1c, mean (SD), %", UA = "Uric acid, mean (SD), mg/dL",
      eGFR = "eGFR, mean (SD), mL/min/1.73 m\u00b2", v
    )
    parts[[length(parts) + 1L]] <- .cont_row(lab, data[[v]])
  }

  parts[[length(parts) + 1L]] <- .empty_row("Comorbidities")
  for (v in c("Hypertension", "Diabetes", "Dyslipidemia")) {
    if (!v %in% names(data)) next
    parts[[length(parts) + 1L]] <- .cat_block(paste0(v, ", n (%)"), data[[v]])
  }
  if (outcome %in% names(data)) {
    st <- factor(ifelse(as.integer(data[[outcome]]) == 1L, "Yes", "No"), levels = c("No", "Yes"))
    parts[[length(parts) + 1L]] <- .cat_block(
      as.character(outcome_lab %||% "Incident stroke, n (%)")[1L], st
    )
  }
  if ("CKM_stage" %in% names(data)) {
    st_vals <- sort(unique(stats::na.omit(as.integer(data$CKM_stage))))
    ckf <- factor(paste0("Stage ", as.integer(data$CKM_stage)),
                  levels = paste0("Stage ", st_vals))
    parts[[length(parts) + 1L]] <- .cat_block("CKM syndrome stages, n (%)", ckf)
  }

  parts[[length(parts) + 1L]] <- .empty_row("Exposure")
  for (nm in names(exposure_cols)) {
    col <- exposure_cols[[nm]]
    if (!col %in% names(data)) next
    lab <- exposure_labs[[nm]] %||% paste0(col, ", mean (SD)")
    parts[[length(parts) + 1L]] <- .cont_row(lab, data[[col]])
  }

  t1 <- do.call(rbind, parts)
  rownames(t1) <- NULL
  hdr <- c(
    "Characteristics",
    sprintf("Overall\n(N = %s)", format(n_all, big.mark = ",")),
    vapply(levels_cls, function(cl) {
      sprintf("%s\n(N = %s)", cl, format(n_by_class[[cl]] %||% 0L, big.mark = ","))
    }, character(1)),
    "P-value"
  )
  names(t1) <- hdr
  level_idx <- which(grepl("^  ", t1[[1]])) + 1L
  list(df = t1, n_all = n_all, n_by_class = n_by_class, excel_level_row_idx = level_idx,
       levels_cls = levels_cls)
}

ckm_stroke_style_table1_xlsx <- function(xlsx_path) {
  # R/openxlsx 加粗小节标题（Demographics 等）；不依赖 Windows python3
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    warning("openxlsx missing; skip Table1 style: ", xlsx_path)
    return(invisible(FALSE))
  }
  if (!file.exists(xlsx_path)) return(invisible(FALSE))
  wb <- openxlsx::loadWorkbook(xlsx_path)
  sh <- names(wb)[1L]
  vals <- openxlsx::read.xlsx(xlsx_path, sheet = 1L, colNames = FALSE)
  secs <- c(
    "Demographics",
    "Vital signs and laboratory tests",
    "Comorbidities",
    "Exposure"
  )
  levels <- c(
    "Female", "Male", "Never", "Ever", "Single", "Married", "No", "Yes",
    "Illiterate", "Primary", "Middle", "High+",
    "Below High school", "High school and above",
    "Stage 0", "Stage 1", "Stage 2", "Stage 3", "Stage 4"
  )
  sty_sec <- openxlsx::createStyle(
    fontName = "Times New Roman", fontSize = 12, textDecoration = "bold",
    halign = "left", valign = "center"
  )
  sty_plain <- openxlsx::createStyle(
    fontName = "Times New Roman", fontSize = 12,
    halign = "left", valign = "center", indent = 1L
  )
  sty_var <- openxlsx::createStyle(
    fontName = "Times New Roman", fontSize = 12,
    halign = "left", valign = "center"
  )
  sty_title <- openxlsx::createStyle(
    fontName = "Times New Roman", fontSize = 12, textDecoration = "bold",
    halign = "left", valign = "center"
  )
  # 表题 + Characteristics 表头加粗
  openxlsx::addStyle(wb, sh, sty_title, rows = 1L, cols = 1L, stack = TRUE)
  if (nrow(vals) >= 2L) {
    openxlsx::addStyle(wb, sh, sty_title, rows = 2L, cols = seq_len(ncol(vals)), stack = TRUE)
  }
  for (i in seq_len(nrow(vals))) {
    v <- as.character(vals[i, 1L])
    if (is.na(v) || !nzchar(v)) next
    if (grepl("^(Values are|Class mapping|Analytic|Section order)", v)) break
    vs <- trimws(v)
    if (vs %in% secs) {
      openxlsx::addStyle(wb, sh, sty_sec, rows = i, cols = 1L, stack = TRUE)
    } else if (startsWith(v, "  ") || vs %in% levels) {
      # 分类水平：去前导空格 + 缩进样式
      openxlsx::writeData(wb, sh, vs, startCol = 1L, startRow = i, colNames = FALSE)
      openxlsx::addStyle(wb, sh, sty_plain, rows = i, cols = 1L, stack = TRUE)
    } else if (i > 2L) {
      openxlsx::addStyle(wb, sh, sty_var, rows = i, cols = 1L, stack = TRUE)
    }
  }
  openxlsx::saveWorkbook(wb, xlsx_path, overwrite = TRUE)
  invisible(TRUE)
}

#' 写入分析软件版本说明（Nature 统计报告要求）
ckm_stroke_write_software_versions <- function(out_dir, extra = character(0)) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  pkgs <- c(
    "rms", "survival", "ggplot2", "forestploter", "mice",
    "openxlsx", "data.table", "arrow"
  )
  lines <- c(
    "Statistical software and package versions",
    sprintf("R version: %s", paste(R.version$major, R.version$minor, sep = ".")),
    sprintf("Platform: %s", R.version$platform),
    ""
  )
  for (p in pkgs) {
    ver <- tryCatch(as.character(utils::packageVersion(p)), error = function(e) "not installed")
    lines <- c(lines, sprintf("%s: %s", p, ver))
  }
  if (length(extra)) lines <- c(lines, "", extra)
  lines <- c(
    lines,
    "",
    "Primary analyses: logistic and Cox regression; restricted cubic splines (rms);",
    "k-means clustering; forest plots (forestploter); multiple imputation with mice and Rubin's rules when a sensitivity table is exported."
  )
  out <- file.path(out_dir, "Methods_software_versions.txt")
  writeLines(lines, out, useBytes = TRUE)
  invisible(out)
}

#' 表脚注用的一行软件版本（复用，勿课题手写）
ckm_stroke_software_footnote <- function() {
  sprintf(
    "Software: R %s; rms, survival, ggplot2, forestploter, mice. Package versions are listed in the methods note beside the tables.",
    paste(R.version$major, R.version$minor, sep = ".")
  )
}

# -----------------------------------------------------------------------------
# Association tables (Table2 / S1 / S3 / S4)
# -----------------------------------------------------------------------------
# 逻辑下标里的 NA 会在 data.frame 子集中插入空行，使缺失者同时进入两个水平。
.ckm_level_subset <- function(df, var, lv) {
  x <- df[[var]]
  hit <- which(!is.na(x) & as.character(x) == as.character(lv))
  if (!length(hit)) return(df[0, , drop = FALSE])
  df[hit, , drop = FALSE]
}

.ckm_get_term <- function(fit_df, term_pat) {
  if (is.null(fit_df) || !nrow(fit_df)) return(NULL)
  hit <- grepl(term_pat, fit_df$term)
  if (!any(hit)) return(NULL)
  fit_df[which(hit)[1L], , drop = FALSE]
}

.ckm_p_trend_class <- function(d, covars, is_hr = FALSE, outcome = "Stroke",
                               cmap = ckm_stroke_class_map_paper()) {
  d$Class_num <- as.integer(factor(as.character(d$Class_paper), levels = cmap$order_paper))
  keep <- unique(c(if (is_hr) c("futime", "status") else outcome, "Class_num", covars))
  dd <- d[, intersect(keep, names(d)), drop = FALSE]
  dd <- dd[stats::complete.cases(dd), , drop = FALSE]
  if (nrow(dd) < 40L) return(NA_real_)
  if (is_hr) {
    fml <- if (length(covars)) {
      stats::as.formula(paste("survival::Surv(futime, status) ~ Class_num +",
                              paste(covars, collapse = "+")))
    } else survival::Surv(futime, status) ~ Class_num
    fit <- tryCatch(survival::coxph(fml, data = dd), error = function(e) NULL)
    if (is.null(fit)) return(NA_real_)
    return(as.numeric(summary(fit)$coefficients["Class_num", 5]))
  }
  fml <- if (length(covars)) {
    stats::as.formula(paste(outcome, "~ Class_num +", paste(covars, collapse = "+")))
  } else stats::as.formula(paste(outcome, "~ Class_num"))
  fit <- tryCatch(stats::glm(fml, data = dd, family = binomial()), error = function(e) NULL)
  if (is.null(fit)) return(NA_real_)
  as.numeric(summary(fit)$coefficients["Class_num", 4])
}

.ckm_p_trend_tert <- function(d, covars, is_hr = FALSE, outcome = "Stroke",
                              tert_col = "eGDR_tertile") {
  lev <- levels(factor(d[[tert_col]]))
  if (!length(lev)) lev <- paste0("T", seq_len(nlevels(factor(as.character(d[[tert_col]])))))
  d$T_num <- as.integer(factor(as.character(d[[tert_col]]), levels = lev))
  keep <- unique(c(if (is_hr) c("futime", "status") else outcome, "T_num", covars))
  dd <- d[, intersect(keep, names(d)), drop = FALSE]
  dd <- dd[stats::complete.cases(dd), , drop = FALSE]
  if (nrow(dd) < 40L) return(NA_real_)
  if (is_hr) {
    fml <- if (length(covars)) {
      stats::as.formula(paste("survival::Surv(futime, status) ~ T_num +", paste(covars, collapse = "+")))
    } else survival::Surv(futime, status) ~ T_num
    fit <- tryCatch(survival::coxph(fml, data = dd), error = function(e) NULL)
    if (is.null(fit)) return(NA_real_)
    return(as.numeric(summary(fit)$coefficients["T_num", 5]))
  }
  fml <- if (length(covars)) {
    stats::as.formula(paste(outcome, "~ T_num +", paste(covars, collapse = "+")))
  } else stats::as.formula(paste(outcome, "~ T_num"))
  fit <- tryCatch(stats::glm(fml, data = dd, family = binomial()), error = function(e) NULL)
  if (is.null(fit)) return(NA_real_)
  as.numeric(summary(fit)$coefficients["T_num", 4])
}

ckm_stroke_build_table2_assoc <- function(
    data, models, is_hr = FALSE,
    outcome = "Stroke",
    class_col = "eGDR_Class",
    cont_col = "cum_eGDR",
    tert_col = "eGDR_tertile",
    cmap = ckm_stroke_class_map_paper(),
    index_lab = "eGDR",
    unit_delta = NULL,
    row_fit = NULL,
    trend_p = NULL) {
  .ckm_pub_ensure_literature()
  index_lab <- as.character(index_lab %||% "eGDR")[1L]
  if (!nzchar(index_lab)) index_lab <- "eGDR"
  unit_delta <- if (is.null(unit_delta)) ckm_stroke_cont_unit_delta(index_lab) else as.numeric(unit_delta)[1L]
  if (!is.finite(unit_delta) || unit_delta <= 0) unit_delta <- 1
  est_lab <- if (is_hr) "HR (95% CI)" else "OR (95% CI)"
  n_all <- nrow(data)

  d0 <- data
  d0[[class_col]] <- stats::relevel(factor(d0[[class_col]]), ref = cmap$ref_semantic)
  .model_names <- c("Model1", "Model2", "Model3")
  .one_fit <- function(dd, expo, cov) {
    if (is.function(row_fit)) return(row_fit(dd, expo, cov))
    if (is_hr) ckm_stroke_fit_hr_row(dd, expo, cov) else ckm_stroke_fit_or_row(dd, expo, outcome, cov)
  }
  class_fits <- list()
  for (mn in .model_names) class_fits[[mn]] <- .one_fit(d0, class_col, models[[mn]])
  # Continuous contrast: divide by unit_delta so coefficient = per unit_delta increase
  cont_use <- cont_col
  d_cont <- data
  if (!isTRUE(all.equal(unit_delta, 1))) {
    cont_use <- paste0(cont_col, "_udelta")
    d_cont[[cont_use]] <- as.numeric(d_cont[[cont_col]]) / unit_delta
  }
  cont_fits <- list()
  for (mn in .model_names) cont_fits[[mn]] <- .one_fit(d_cont, cont_use, models[[mn]])
  dtert <- data
  .tert_lv <- levels(factor(dtert[[tert_col]]))
  if (!length(.tert_lv)) {
    .tert_lv <- sort(unique(as.character(stats::na.omit(dtert[[tert_col]]))))
  }
  .tert_ref <- .tert_lv[[1L]]
  dtert[[tert_col]] <- stats::relevel(factor(dtert[[tert_col]], levels = .tert_lv), ref = .tert_ref)
  tert_fits <- list()
  for (mn in .model_names) tert_fits[[mn]] <- .one_fit(dtert, tert_col, models[[mn]])

  .model_cells <- function(rr, term_pat) {
    out <- list()
    for (mn in c("Model1", "Model2", "Model3")) {
      hit <- .ckm_get_term(rr[[mn]], term_pat)
      if (is.null(hit)) {
        out[[paste0(mn, "_est")]] <- ""; out[[paste0(mn, "_p")]] <- ""
      } else if (is_hr) {
        out[[paste0(mn, "_est")]] <- ckm_stroke_fmt_orci(hit$HR, hit$CI_low, hit$CI_high)
        out[[paste0(mn, "_p")]] <- ckm_stroke_fmt_p(hit$P)
      } else {
        out[[paste0(mn, "_est")]] <- ckm_stroke_fmt_orci(hit$OR, hit$CI_low, hit$CI_high)
        out[[paste0(mn, "_p")]] <- ckm_stroke_fmt_p(hit$P)
      }
    }
    out
  }
  .fmt_n_cell <- function(n) {
    n <- as.integer(n)[1L]
    if (!is.finite(n)) return("")
    if (exists("pub_format_int", mode = "function")) {
      as.character(pub_format_int(n))
    } else {
      format(n, big.mark = ",", scientific = FALSE, trim = TRUE)
    }
  }
  mk_row <- function(var, n, ev, cells, is_ref = FALSE) {
    if (is_ref) {
      data.frame(
        Variable = var, `Total number` = .fmt_n_cell(n), `Events, n (%)` = ev,
        Model1_OR = "Reference", Model1_P = "", Model2_OR = "Reference", Model2_P = "",
        Model3_OR = "Reference", Model3_P = "",
        check.names = FALSE, stringsAsFactors = FALSE
      )
    } else {
      data.frame(
        Variable = var, `Total number` = .fmt_n_cell(n), `Events, n (%)` = ev,
        Model1_OR = cells$Model1_est, Model1_P = cells$Model1_p,
        Model2_OR = cells$Model2_est, Model2_P = cells$Model2_p,
        Model3_OR = cells$Model3_est, Model3_P = cells$Model3_p,
        check.names = FALSE, stringsAsFactors = FALSE
      )
    }
  }
  sec <- function(lab) {
    data.frame(
      Variable = lab, `Total number` = "", `Events, n (%)` = "",
      Model1_OR = "", Model1_P = "", Model2_OR = "", Model2_P = "",
      Model3_OR = "", Model3_P = "",
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }

  rows <- list(sec(sprintf("%s change patterns", index_lab)))
  class_order <- cmap$order_table_ref_first
  class_order <- class_order[
    vapply(class_order, function(cl) sum(as.character(data$Class_paper) == cl, na.rm = TRUE) > 0L, logical(1))
  ]
  for (cl in class_order) {
    keep <- as.character(data$Class_paper) == cl
    n <- sum(keep)
    ev <- ckm_stroke_events_cell(data[[outcome]][keep])
    if (cl == cmap$ref_class) {
      rows[[length(rows) + 1L]] <- mk_row(paste0("  ", cl), n, ev, NULL, is_ref = TRUE)
    } else {
      sem <- names(cmap$map)[cmap$map == cl]
      cells <- .model_cells(class_fits, paste0(sem, "$"))
      rows[[length(rows) + 1L]] <- mk_row(paste0("  ", cl), n, ev, cells)
    }
  }
  rows[[length(rows) + 1L]] <- {
    cells <- .model_cells(cont_fits, paste0("^", cont_use, "$"))
    cont_lab <- if (isTRUE(all.equal(unit_delta, 1))) {
      sprintf("Cumulative %s", index_lab)
    } else {
      sprintf("Cumulative %s (per %.3g)", index_lab, unit_delta)
    }
    mk_row(cont_lab, n_all, ckm_stroke_events_cell(data[[outcome]]), cells)
  }
  tert_levels <- levels(factor(data[[tert_col]]))
  if (!length(tert_levels)) tert_levels <- sort(unique(as.character(stats::na.omit(data[[tert_col]]))))
  n_q <- length(tert_levels)
  rows[[length(rows) + 1L]] <- sec(ckm_stroke_quantile_section_label(n_q, index_lab))
  for (tv in tert_levels) {
    keep <- as.character(data[[tert_col]]) == tv
    n <- sum(keep, na.rm = TRUE)
    ev <- ckm_stroke_events_cell(data[[outcome]][keep])
    if (identical(tv, tert_levels[[1L]]) || identical(tv, "T1")) {
      rows[[length(rows) + 1L]] <- mk_row(paste0("  ", tv), n, ev, NULL, is_ref = TRUE)
    } else {
      cells <- .model_cells(tert_fits, paste0(tv, "$"))
      rows[[length(rows) + 1L]] <- mk_row(paste0("  ", tv), n, ev, cells)
    }
  }
  if (is.function(trend_p)) {
    ptr <- trend_p()
    ptr <- setNames(as.character(ptr[.model_names]), .model_names)
  } else {
    ptr <- vapply(.model_names, function(mn) {
      ckm_stroke_fmt_p(.ckm_p_trend_tert(data, models[[mn]], is_hr = is_hr,
                                         outcome = outcome, tert_col = tert_col))
    }, character(1))
    names(ptr) <- .model_names
  }
  rows[[length(rows) + 1L]] <- data.frame(
    Variable = "  P for trend",
    `Total number` = "", `Events, n (%)` = "",
    Model1_OR = "", Model1_P = ptr[["Model1"]],
    Model2_OR = "", Model2_P = ptr[["Model2"]],
    Model3_OR = "", Model3_P = ptr[["Model3"]],
    check.names = FALSE, stringsAsFactors = FALSE
  )
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  names(out) <- c("Variable", "Total number", "Events, n (%)",
                  "M1e", "M1p", "M2e", "M2p", "M3e", "M3p")
  list(
    df = out, est_lab = est_lab, cont_fits = cont_fits,
    unit_delta = unit_delta, cont_col_used = cont_use
  )
}

ckm_stroke_build_table_s1_cox <- function(...) {
  ckm_stroke_build_table2_assoc(..., is_hr = TRUE)
}

# Rubin 合并。只插补调用方点名且确有缺失的协变量；结局与暴露留在插补模型里作预测变量，本身不插。
ckm_stroke_prepare_mice <- function(data, impute_vars, m = 5L, maxit = 5L, seed = 2026L) {
  impute_vars <- intersect(as.character(impute_vars), names(data))
  impute_vars <- impute_vars[vapply(impute_vars, function(v) anyNA(data[[v]]), logical(1))]
  if (!length(impute_vars)) return(NULL)
  if (!requireNamespace("mice", quietly = TRUE)) {
    stop("mice is required to build Table S3/S4", call. = FALSE)
  }
  md <- data
  for (v in names(md)) if (is.character(md[[v]])) md[[v]] <- factor(md[[v]])
  ini <- mice::mice(md, maxit = 0L, printFlag = FALSE)
  meth <- ini$method
  pred <- ini$predictorMatrix
  diag(pred) <- 0
  meth[setdiff(names(md), impute_vars)] <- ""
  imp <- mice::mice(
    md, m = as.integer(m), maxit = as.integer(maxit),
    method = meth, predictorMatrix = pred,
    printFlag = FALSE, seed = as.integer(seed)
  )
  list(imp = imp, imputed = impute_vars)
}

ckm_stroke_mice_fit_row <- function(imp, exposure, covars, is_hr = FALSE, outcome = "Osteoporosis") {
  covars <- intersect(as.character(covars %||% character(0)), names(imp$data))
  rhs <- paste(c(exposure, covars), collapse = " + ")
  # 公式必须写进 with() 的表达式。事先 as.formula() 再传入时，mice 在插补数据里找不到结局列，拟合失败后单元格会是空的。
  if (isTRUE(is_hr)) {
    call_txt <- sprintf(
      "with(imp, survival::coxph(survival::Surv(futime, status) ~ %s))", rhs
    )
  } else {
    call_txt <- sprintf(
      "with(imp, stats::glm(%s ~ %s, family = stats::binomial()))", outcome, rhs
    )
  }
  mira <- tryCatch(eval(parse(text = call_txt)), error = function(e) {
    warning("MICE fit failed for ", exposure, ": ", conditionMessage(e), call. = FALSE)
    NULL
  })
  if (is.null(mira)) return(NULL)
  sm <- tryCatch(as.data.frame(summary(mice::pool(mira), conf.int = TRUE)), error = function(e) NULL)
  if (is.null(sm) || !nrow(sm)) return(NULL)
  lo_col <- grep("^2\\.5", names(sm), value = TRUE)[1L]
  hi_col <- grep("^97\\.5", names(sm), value = TRUE)[1L]
  hit <- grepl(paste0("^", exposure), sm$term)
  if (!any(hit)) return(NULL)
  rows <- lapply(which(hit), function(i) {
    est <- sm$estimate[i]
    data.frame(
      term = sm$term[i], OR = exp(est), HR = exp(est),
      CI_low = exp(sm[[lo_col]][i]), CI_high = exp(sm[[hi_col]][i]),
      P = sm$p.value[i], stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

ckm_stroke_assert_mice_not_shell <- function(cc_df, mi_df) {
  cols <- intersect(c("M2e", "M2p", "M3e", "M3p"), names(cc_df))
  same <- all(vapply(cols, function(cl) identical(as.character(cc_df[[cl]]), as.character(mi_df[[cl]])), logical(1)))
  if (isTRUE(same)) {
    stop("MICE table matches the complete-case table on Model 2/3. Export refused.", call. = FALSE)
  }
  est_cols <- intersect(c("M1e", "M2e", "M3e"), names(mi_df))
  body <- grepl("^  Class [0-9]+$", mi_df$Variable) |
    grepl("^  [TQ][0-9]+$", mi_df$Variable) |
    grepl("^Cumulative ", mi_df$Variable)
  filled <- mi_df[body, est_cols, drop = FALSE]
  if (!any(nzchar(trimws(as.character(unlist(filled)))))) {
    stop("MICE table has no effect estimates. Export refused.", call. = FALSE)
  }
  invisible(TRUE)
}

ckm_stroke_p_for_estimate_cell <- function(est_cell, p) {
  if (identical(as.character(est_cell)[1L], "NE")) return("\u2014")
  ckm_stroke_fmt_p(p)
}

ckm_stroke_assert_mice_footnote <- function(title, footnotes) {
  title <- paste(as.character(title %||% ""), collapse = " ")
  if (!grepl("MICE|multiple imputation", title, ignore.case = TRUE)) return(invisible(TRUE))
  blob <- paste(as.character(footnotes %||% ""), collapse = " ")
  if (grepl("mirror complete-case|missingness is near-zero|missingness near-zero", blob, ignore.case = TRUE)) {
    stop("MICE table footnote copies the complete-case table. Export refused.", call. = FALSE)
  }
  invisible(TRUE)
}

#' Continuous contrast step for cumulative exposure (OR/HR per unit_delta)
#'
#' Krakauer ABSI（米制）单波约 0.08、累计 SD 约 0.02；per-1 不现实，默认 per 0.01。
#' （旧错误 cm 公式约 10×，曾用 per 0.1；米制修正后改为 0.01。）
#' Other indices stay per 1.
ckm_stroke_cont_unit_delta <- function(index_lab) {
  ix <- toupper(trimws(as.character(index_lab %||% "")[1L]))
  if (identical(ix, "ABSI")) 0.01 else 1
}

ckm_stroke_unit_delta_label <- function(unit_delta) {
  ud <- as.numeric(unit_delta)[1L]
  if (!is.finite(ud) || ud <= 0) ud <- 1
  if (isTRUE(all.equal(ud, 1))) "1-unit" else sprintf("%.3g-unit", ud)
}

ckm_stroke_assert_forest_scale <- function(scale, title = NULL, allow_per_sd = FALSE,
                                           unit_delta = 1) {
  scale <- as.character(scale)[1L]
  if (identical(scale, "sd") && !isTRUE(allow_per_sd)) {
    stop("Subgroup forest scale is per 1-SD. Table 2/S1 continuous rows use unit_delta. Use scale='unit', or allow_per_sd=TRUE only for a historical figure.", call. = FALSE)
  }
  title <- paste(as.character(title %||% ""), collapse = " ")
  if (nzchar(title) && grepl("1-SD|per-SD|per SD", title) && identical(scale, "unit")) {
    stop("Forest title says per 1-SD but the estimate is per unit_delta.", call. = FALSE)
  }
  ud <- as.numeric(unit_delta)[1L]
  if (identical(scale, "unit") && is.finite(ud) && !isTRUE(all.equal(ud, 1)) &&
      nzchar(title) &&
      grepl("(^|[^0-9.])per 1-unit|per-1-unit|(^|[^0-9.])1-unit cum", title, ignore.case = TRUE) &&
      !grepl(sprintf("per\\s*%s", gsub("\\.", "\\\\.", format(ud, scientific = FALSE))), title, ignore.case = TRUE)) {
    stop("Forest title says per 1-unit but unit_delta=", ud, ". Align the title.", call. = FALSE)
  }
  invisible(TRUE)
}

ckm_stroke_fit_mice_assoc <- function(
    data, models, outcome = "Stroke", index_lab = "eGDR",
    cmap = NULL, m = 5L, maxit = 5L, seed = 2026L) {
  .ckm_pub_ensure_literature()
  if (is.null(cmap)) cmap <- ckm_stroke_class_map_paper()
  need <- unique(c(outcome, "futime", "status", "eGDR_Class", "cum_eGDR", "eGDR_tertile", unlist(models, use.names = FALSE)))
  need <- intersect(need, names(data))
  md <- data[, need, drop = FALSE]
  if ("eGDR_Class" %in% names(md)) md$eGDR_Class <- stats::relevel(factor(md$eGDR_Class), ref = cmap$ref_semantic)
  if ("eGDR_tertile" %in% names(md)) {
    .qlv <- levels(factor(md$eGDR_tertile))
    if (!length(.qlv)) .qlv <- sort(unique(as.character(stats::na.omit(md$eGDR_tertile))))
    md$eGDR_tertile <- stats::relevel(factor(md$eGDR_tertile, levels = .qlv), ref = .qlv[[1L]])
    md$T_num <- as.integer(md$eGDR_tertile)
  }
  impute <- setdiff(names(md), c(outcome, "futime", "status", "eGDR_Class", "cum_eGDR", "eGDR_tertile", "T_num"))
  prep <- ckm_stroke_prepare_mice(md, impute, m = m, maxit = maxit, seed = seed)
  if (is.null(prep)) return(NULL)
  row_fit <- function(is_hr) {
    function(dd, expo, cov) ckm_stroke_mice_fit_row(prep$imp, expo, cov, is_hr = is_hr, outcome = outcome)
  }
  trend_p <- function(is_hr) {
    function() vapply(c("Model1", "Model2", "Model3"), function(mn) {
      row <- ckm_stroke_mice_fit_row(prep$imp, "T_num", models[[mn]], is_hr = is_hr, outcome = outcome)
      if (is.null(row) || !nrow(row)) return("")
      ckm_stroke_fmt_p(row$P[1])
    }, character(1))
  }
  cc_cox <- ckm_stroke_build_table_s1_cox(data, models, outcome = outcome, cmap = cmap, index_lab = index_lab)
  cc_log <- ckm_stroke_build_table2_assoc(data, models, is_hr = FALSE, outcome = outcome, cmap = cmap, index_lab = index_lab)
  s3 <- ckm_stroke_build_table_s1_cox(data, models, outcome = outcome, cmap = cmap, index_lab = index_lab, row_fit = row_fit(TRUE), trend_p = trend_p(TRUE))
  s4 <- ckm_stroke_build_table2_assoc(data, models, is_hr = FALSE, outcome = outcome, cmap = cmap, index_lab = index_lab, row_fit = row_fit(FALSE), trend_p = trend_p(FALSE))
  ckm_stroke_assert_mice_not_shell(cc_cox$df, s3$df)
  ckm_stroke_assert_mice_not_shell(cc_log$df, s4$df)
  list(s3 = s3, s4 = s4, imputed = prep$imputed)
}

ckm_stroke_export_assoc_xlsx <- function(built, filepath, title, footnotes) {
  ckm_stroke_assert_mice_footnote(title, footnotes)
  df <- built$df
  h1 <- c("Variable", "Total number", "Events, n (%)",
          "Model 1", "Model 1", "Model 2", "Model 2", "Model 3", "Model 3")
  h2 <- c("", "", "",
          built$est_lab, "P value",
          built$est_lab, "P value",
          built$est_lab, "P value")
  export_sci_table(
    df, filepath, title = title,
    header_row1 = h1, header_row2 = h2,
    latex_include_colnames = FALSE,
    table_footnotes = footnotes,
    excel_level_row_idx = which(grepl("^  ", df$Variable) & df$Variable != "  P for trend")
  )
}

# -----------------------------------------------------------------------------
# Table 3 subgroup（参照类按 cmap$order_table_ref_first，不再写死 Class 2）
# -----------------------------------------------------------------------------
ckm_stroke_build_table3_subgroup <- function(
    data, models,
    outcome = "Stroke",
    class_col = "eGDR_Class",
    cmap = ckm_stroke_class_map_paper(),
    sg_defs = NULL) {
  .ckm_pub_ensure_literature()
  data_sg <- ckm_stroke_prepare_forest_groups(
    data, age_labels_compact = FALSE, drop_extreme_bmi = FALSE
  )
  if (is.null(sg_defs)) {
    sg_defs <- list(
      list(label = "Age, years", var = "Age_Group"),
      list(label = "Gender", var = "Gender"),
      list(label = "BMI, kg/m\u00b2", var = "BMI_Group"),
      list(label = "Smoke", var = "Smoke_ne"),
      list(label = "Drink", var = "Drink_ne"),
      list(label = "Dyslipidemia", var = "Dyslipidemia"),
      list(label = "Diabetes", var = "Diabetes"),
      list(label = "CKM", var = "CKM_group")
    )
  }
  .cov_drop <- function(sg_var) {
    if (sg_var == "Age_Group") return("Age")
    if (sg_var == "BMI_Group") return("BMI")
    if (sg_var == "Smoke_ne") return("Smoke")
    if (sg_var == "Drink_ne") return("Drink")
    if (sg_var %in% c("Gender", "Dyslipidemia", "Diabetes", "Hypertension", "Marital", "Education")) {
      return(sg_var)
    }
    character(0)
  }
  ord <- as.character(cmap$order_table_ref_first %||% cmap$order_paper)
  ref_cl <- as.character(cmap$ref_class %||% ord[1L])[1L]
  if (!length(ord)) ord <- c("Class 1", "Class 2", "Class 3", "Class 4")
  if (!ref_cl %in% ord) ord <- c(ref_cl, setdiff(ord, ref_cl))
  t3_rows <- list()
  for (sg in sg_defs) {
    if (!sg$var %in% names(data_sg)) next
    cov_base <- setdiff(models$Model3, .cov_drop(sg$var))
    pint <- ckm_stroke_lrt_pint(data_sg, class_col, sg$var, cov_base,
                                is_hr = FALSE, outcome = outcome)
    levs <- levels(factor(data_sg[[sg$var]]))
    levs <- levs[!is.na(levs)]
    level_rows <- list()
    sem_of <- function(cl) {
      hit <- names(cmap$map)[cmap$map == cl]
      if (!length(hit)) return(NA_character_)
      hit[[1L]]
    }
    for (lv in levs) {
      dsub <- .ckm_level_subset(data_sg, sg$var, lv)
      cov <- setdiff(models$Model3, .cov_drop(sg$var))
      dsub[[class_col]] <- .ckm_relevel_class_safe(dsub[[class_col]], cmap$ref_semantic)
      rr <- if (nrow(dsub) >= 40L) ckm_stroke_fit_or_row(dsub, class_col, outcome, cov) else NULL
      cell <- function(cl) {
        if (identical(cl, ref_cl)) return("Reference")
        sem <- sem_of(cl)
        if (is.na(sem)) return("NE")
        h <- .ckm_get_term(rr, paste0(sem, "$"))
        if (is.null(h)) return("NE")
        ckm_stroke_fmt_orci(h$OR, h$CI_low, h$CI_high)
      }
      cells <- vapply(ord, cell, character(1))
      # 非参照列全 NE → 空层不进表
      if (all(cells[ord != ref_cl] == "NE")) next
      row_df <- data.frame(
        Subgroup = paste0("  ", lv),
        check.names = FALSE, stringsAsFactors = FALSE
      )
      for (j in seq_along(ord)) row_df[[ord[j]]] <- cells[[j]]
      row_df[["P for interaction"]] <- ""
      level_rows[[length(level_rows) + 1L]] <- row_df
    }
    if (!length(level_rows)) next
    pint_txt <- if (length(level_rows) >= 2L) ckm_stroke_fmt_p(pint) else "\u2014"
    hdr <- data.frame(Subgroup = sg$label, check.names = FALSE, stringsAsFactors = FALSE)
    for (cl in ord) hdr[[cl]] <- ""
    hdr[["P for interaction"]] <- pint_txt
    t3_rows[[length(t3_rows) + 1L]] <- hdr
    t3_rows <- c(t3_rows, level_rows)
  }
  if (!length(t3_rows)) {
    empty <- data.frame(Subgroup = character(0), check.names = FALSE)
    for (cl in ord) empty[[cl]] <- character(0)
    empty[["P for interaction"]] <- character(0)
    return(list(df = empty, excel_level_row_idx = integer(0)))
  }
  t3 <- do.call(rbind, t3_rows)
  rownames(t3) <- NULL
  col_labs <- ord
  col_labs[1L] <- paste0(ord[1L], " Reference")
  names(t3) <- c("Subgroup", col_labs, "P for interaction")
  list(df = t3, excel_level_row_idx = which(grepl("^  ", t3$Subgroup)) + 1L)
}

# -----------------------------------------------------------------------------
# Table S2 MOESM long
# -----------------------------------------------------------------------------
ckm_stroke_build_table_s2_long <- function(
    data, models,
    outcome = "Stroke",
    class_col = "eGDR_Class",
    cmap = ckm_stroke_class_map_paper(),
    sg_defs = NULL) {
  .ckm_pub_ensure_literature()
  data_sg <- ckm_stroke_prepare_forest_groups(
    data, age_labels_compact = FALSE, drop_extreme_bmi = FALSE
  )
  if (is.null(sg_defs)) {
    sg_defs <- list(
      list(label = "Age, years", var = "Age_Group"),
      list(label = "Gender", var = "Gender"),
      list(label = "BMI, kg/m\u00b2", var = "BMI_Group"),
      list(label = "Smoke", var = "Smoke_ne"),
      list(label = "Drink", var = "Drink_ne"),
      list(label = "Dyslipidemia", var = "Dyslipidemia"),
      list(label = "Diabetes", var = "Diabetes"),
      list(label = "CKM", var = "CKM_group")
    )
  }
  .cov_drop <- function(sg_var) {
    if (sg_var == "Age_Group") return("Age")
    if (sg_var == "BMI_Group") return("BMI")
    if (sg_var == "Smoke_ne") return("Smoke")
    if (sg_var == "Drink_ne") return("Drink")
    if (sg_var %in% c("Gender", "Dyslipidemia", "Diabetes", "Hypertension")) return(sg_var)
    character(0)
  }
  rows <- list()
  for (sg in sg_defs) {
    if (!sg$var %in% names(data_sg)) next
    cov <- setdiff(models$Model3, .cov_drop(sg$var))
    pint <- ckm_stroke_lrt_pint(data_sg, class_col, sg$var, cov, is_hr = TRUE, outcome = outcome)
    rows[[length(rows) + 1L]] <- data.frame(
      Subgroup = sg$label, Variable = "", N = "", `Events, n (%)` = "",
      `HR (95%CI)` = "", `P value` = "", `P for interaction` = ckm_stroke_fmt_p(pint),
      check.names = FALSE, stringsAsFactors = FALSE
    )
    levs <- levels(factor(data_sg[[sg$var]]))
    levs <- levs[!is.na(levs)]
    n_assigned <- 0L
    for (lv in levs) {
      dsub <- .ckm_level_subset(data_sg, sg$var, lv)
      n_assigned <- n_assigned + nrow(dsub)
      rows[[length(rows) + 1L]] <- data.frame(
        Subgroup = lv, Variable = "", N = as.character(nrow(dsub)),
        `Events, n (%)` = ckm_stroke_events_cell(dsub[[outcome]]),
        `HR (95%CI)` = "", `P value` = "", `P for interaction` = "",
        check.names = FALSE, stringsAsFactors = FALSE
      )
      dsub[[class_col]] <- .ckm_relevel_class_safe(dsub[[class_col]], cmap$ref_semantic)
      rr <- if (nrow(dsub) >= 40L) ckm_stroke_fit_hr_row(dsub, class_col, cov) else NULL
      for (cl in cmap$order_table_ref_first) {
        keep <- which(as.character(dsub$Class_paper) == cl)
        n <- length(keep)
        # 层内该类 0 人：不写行（避免 N 列裸 0 触发发表数字门控）
        if (n < 1L) next
        ev <- ckm_stroke_events_cell(dsub[[outcome]][keep])
        if (cl == cmap$ref_class) {
          hr_cell <- "1(Ref)"; p_cell <- ""
        } else {
          sem <- names(cmap$map)[cmap$map == cl]
          h <- .ckm_get_term(rr, paste0(sem, "$"))
          if (is.null(h)) {
            hr_cell <- "NE"; p_cell <- "\u2014"
          } else {
            hr_cell <- ckm_stroke_fmt_orci(h$HR, h$CI_low, h$CI_high)
            p_cell <- ckm_stroke_p_for_estimate_cell(hr_cell, h$P)
          }
        }
        rows[[length(rows) + 1L]] <- data.frame(
          # 展示层用 "Class 1" 等；禁止 class1 / 去空格小写（禁下划线同类问题）
          Subgroup = "", Variable = paste0("  ", as.character(cl)[1L]),
          N = as.character(n), `Events, n (%)` = ev,
          `HR (95%CI)` = hr_cell, `P value` = p_cell, `P for interaction` = "",
          check.names = FALSE, stringsAsFactors = FALSE
        )
      }
    }
    n_obs <- sum(!is.na(data_sg[[sg$var]]))
    if (n_assigned != n_obs) {
      stop(sprintf(
        "Table S2 stratum N for %s sums to %d, non-missing N is %d",
        sg$var, n_assigned, n_obs
      ), call. = FALSE)
    }
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  list(df = out)
}

# -----------------------------------------------------------------------------
# Figure 2: A elbow | B scatter+hull | C mean±SE
# -----------------------------------------------------------------------------
ckm_stroke_theme_paper <- function(base = 11) {
  .ff <- if (exists("resolve_plot_font_family", mode = "function")) {
    resolve_plot_font_family("Times New Roman")
  } else {
    "serif"
  }
  ggplot2::theme_classic(base_size = base, base_family = .ff) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", size = base + 2, hjust = 0),
      axis.title = ggplot2::element_text(size = base),
      axis.text = ggplot2::element_text(color = "black", size = base - 1),
      legend.title = ggplot2::element_text(size = base - 1),
      legend.text = ggplot2::element_text(size = base - 1),
      panel.grid = ggplot2::element_blank(),
      legend.key = ggplot2::element_blank()
    )
}

ckm_stroke_fig2_abc <- function(
    data,
    elbow_csv = NULL,
    outfile = NULL,
    t1_col = "eGDR_t1",
    t2_col = "eGDR_t2",
    class_col = "Class_paper",
    cmap = ckm_stroke_class_map_paper(),
    chosen_k = 4L,
    year_labs = c(2012, 2015),
    ylab_c = "Mean eGDR (\u00b1 SE)",
    xlab_b = NULL,
    ylab_b = NULL,
    xlab_c = "Year",
    cluster_labels = NULL,
    width = 12.5, height = 4.0) {
  .ckm_pub_ensure_literature()
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("need ggplot2")
  if (!requireNamespace("gridExtra", quietly = TRUE)) stop("need gridExtra")

  if (!is.null(elbow_csv) && file.exists(elbow_csv)) {
    el_df <- utils::read.csv(elbow_csv)
    if ("chosen_k" %in% names(el_df) && is.finite(as.numeric(el_df$chosen_k[1L]))) {
      chosen_k <- as.integer(el_df$chosen_k[1L])
    }
    if (!"chosen_k" %in% names(el_df)) el_df$chosen_k <- chosen_k
    # 若 CSV 只到 k<10，补齐 WCSS 曲线到 10（虚线仍用 CSV 的 chosen_k）
    if (max(as.numeric(el_df$k), na.rm = TRUE) < 10) {
      mat <- cbind(as.numeric(data[[t1_col]]), as.numeric(data[[t2_col]]))
      el <- ckm_stroke_kmeans_elbow(mat, k_max = 10L, seed = 2026L, nstart = 25L)
      el_df <- data.frame(k = seq_along(el$wcss), WCSS = el$wcss, chosen_k = chosen_k)
    }
  } else {
    mat <- cbind(as.numeric(data[[t1_col]]), as.numeric(data[[t2_col]]))
    el <- ckm_stroke_kmeans_elbow(mat, k_max = 10L, seed = 2026L, nstart = 25L)
    el_df <- data.frame(k = seq_along(el$wcss), WCSS = el$wcss, chosen_k = chosen_k)
  }

  pA <- ggplot2::ggplot(el_df, ggplot2::aes(k, WCSS)) +
    ggplot2::geom_line(color = "#2C7FB8", linewidth = 0.9) +
    ggplot2::geom_point(color = "#2C7FB8", size = 2.2) +
    ggplot2::geom_vline(xintercept = chosen_k, linetype = 2, color = "grey50", linewidth = 0.7) +
    ggplot2::scale_x_continuous(breaks = seq(1, max(el_df$k), 1)) +
    ggplot2::labs(title = "A", x = "Number of clusters (k)", y = "Total Within Sum of Squares") +
    ckm_stroke_theme_paper(10)

  sc <- data.frame(
    x = as.numeric(data[[t1_col]]),
    y = as.numeric(data[[t2_col]]),
    Cluster = factor(data[[class_col]], levels = cmap$order_paper)
  )
  sc <- sc[stats::complete.cases(sc), ]
  if (is.null(xlab_b)) xlab_b <- expression(eGDR[2012])
  if (is.null(ylab_b)) ylab_b <- expression(eGDR[2015])
  # 原文 Fig2B：各类凸包多边形（非正态椭圆）
  hulls <- do.call(rbind, lapply(split(sc, sc$Cluster), function(d) {
    if (nrow(d) < 3L) return(NULL)
    idx <- grDevices::chull(d$x, d$y)
    out <- d[c(idx, idx[1L]), , drop = FALSE]
    out
  }))
  # 长标签（Class 1: Intermediate stable）放右侧会挤掉 B/C 绘图区；
  # B/C 不画独立图例，整图底部共用一条紧凑横排图例。
  .leg_labels <- cluster_labels
  pB <- ggplot2::ggplot(sc, ggplot2::aes(x, y, color = Cluster, fill = Cluster, shape = Cluster)) +
    ggplot2::geom_polygon(
      data = hulls,
      ggplot2::aes(x = x, y = y, group = Cluster, fill = Cluster, color = Cluster),
      alpha = 0.18, linewidth = 0.55, show.legend = FALSE
    ) +
    ggplot2::geom_point(size = 1.05, alpha = 0.65, stroke = 0.2) +
    ggplot2::scale_color_manual(values = cmap$colors, labels = .leg_labels) +
    ggplot2::scale_fill_manual(values = cmap$colors, labels = .leg_labels) +
    ggplot2::scale_shape_manual(values = cmap$shapes, labels = .leg_labels) +
    ggplot2::coord_cartesian(
      xlim = range(sc$x, na.rm = TRUE),
      ylim = range(sc$y, na.rm = TRUE),
      expand = TRUE
    ) +
    ggplot2::labs(title = "B", x = xlab_b, y = ylab_b,
                  color = "Cluster", shape = "Cluster") +
    ckm_stroke_theme_paper(10) +
    ggplot2::theme(legend.position = "none") +
    ggplot2::guides(fill = "none")

  agg <- do.call(rbind, lapply(cmap$order_paper, function(cl) {
    d <- data[as.character(data[[class_col]]) == cl, ]
    n1 <- sum(is.finite(as.numeric(d[[t1_col]])))
    n2 <- sum(is.finite(as.numeric(d[[t2_col]])))
    data.frame(
      Cluster = cl,
      Year = year_labs,
      Mean = c(mean(d[[t1_col]], na.rm = TRUE), mean(d[[t2_col]], na.rm = TRUE)),
      SE = c(stats::sd(d[[t1_col]], na.rm = TRUE) / sqrt(max(n1, 1)),
             stats::sd(d[[t2_col]], na.rm = TRUE) / sqrt(max(n2, 1)))
    )
  }))
  agg$Cluster <- factor(agg$Cluster, levels = cmap$order_paper)
  # Y 轴按数据自适应留白（旧硬编码 ±0.35 是 eGDR 量纲；ABSI~0.8 会被压成近似水平线）
  .yr <- range(c(agg$Mean - agg$SE, agg$Mean + agg$SE), na.rm = TRUE)
  .yspan <- diff(.yr)
  if (!is.finite(.yspan) || .yspan <= 0) .yspan <- max(abs(.yr), 1e-3)
  .ypad <- max(0.08 * .yspan, 0.02 * max(abs(.yr), 1e-6))
  pC <- ggplot2::ggplot(agg, ggplot2::aes(Year, Mean, color = Cluster, shape = Cluster, group = Cluster)) +
    ggplot2::geom_line(linewidth = 1.05) +
    ggplot2::geom_errorbar(
      ggplot2::aes(ymin = Mean - SE, ymax = Mean + SE),
      width = 0.22, linewidth = 0.85, show.legend = FALSE
    ) +
    ggplot2::geom_point(size = 2.6) +
    ggplot2::scale_color_manual(values = cmap$colors, labels = .leg_labels) +
    ggplot2::scale_shape_manual(values = cmap$shapes, labels = .leg_labels) +
    ggplot2::scale_x_continuous(breaks = year_labs) +
    ggplot2::coord_cartesian(ylim = c(.yr[1L] - .ypad, .yr[2L] + .ypad)) +
    ggplot2::labs(title = "C", x = xlab_c, y = ylab_c, color = "Cluster", shape = "Cluster") +
    ckm_stroke_theme_paper(10) +
    ggplot2::theme(legend.position = "none")

  .extract_legend <- function(p) {
    g <- ggplot2::ggplotGrob(p)
    # ggplot2 ≥3.5 常同时有 guide-box-right/left/bottom/...；空槽是 zeroGrob，
    # 不能取第一个 ^guide-box（往往是空的 right）。
    prefer <- c("guide-box-bottom", "guide-box", "guide-box-right", "guide-box-inside")
    for (nm in prefer) {
      idx <- which(g$layout$name == nm)
      if (!length(idx)) next
      gr <- g$grobs[[idx[[1L]]]]
      if (!inherits(gr, "zeroGrob") && !is.null(gr)) return(gr)
    }
    idx <- grep("^guide-box", g$layout$name)
    for (i in idx) {
      gr <- g$grobs[[i]]
      if (!inherits(gr, "zeroGrob") && !is.null(gr)) return(gr)
    }
    NULL
  }
  p_leg_src <- pC +
    ggplot2::theme(
      legend.position = "bottom",
      legend.direction = "horizontal",
      legend.title = ggplot2::element_text(size = 8, face = "bold"),
      legend.text = ggplot2::element_text(size = 7),
      legend.key.size = grid::unit(0.35, "cm"),
      legend.key.height = grid::unit(0.32, "cm"),
      legend.key.width = grid::unit(0.4, "cm"),
      legend.spacing.x = grid::unit(0.2, "cm"),
      legend.margin = ggplot2::margin(t = 1, r = 0, b = 0, l = 0),
      legend.box.margin = ggplot2::margin(0, 0, 0, 0)
    ) +
    ggplot2::guides(
      colour = ggplot2::guide_legend(
        nrow = 1, title.position = "left",
        override.aes = list(size = 2.2, alpha = 1, linewidth = 1)
      ),
      shape = ggplot2::guide_legend(nrow = 1, title.position = "left")
    )
  .leg <- .extract_legend(p_leg_src)

  if (!is.null(outfile) && nzchar(outfile)) {
    dir.create(dirname(outfile), recursive = TRUE, showWarnings = FALSE)
    # 底部图例需要略增高；B 无右侧图例后可加大中栏绘图宽
    .h <- if (is.null(.leg)) height else max(as.numeric(height), 4.35)
    .panels <- gridExtra::arrangeGrob(pA, pB, pC, ncol = 3, widths = c(1, 1.35, 1.2))
    .g <- if (!is.null(.leg)) {
      gridExtra::arrangeGrob(.panels, .leg, ncol = 1, heights = c(1, 0.16))
    } else {
      .panels
    }
    # 只用 grid.draw，避免 grid.arrange 在已打开的 pdf() 上再开一页空白页
    if (exists("pipeline_pdf_device", mode = "function")) {
      pipeline_pdf_device(outfile, width = width, height = .h)
    } else {
      grDevices::pdf(outfile, width = width, height = .h, useDingbats = FALSE, onefile = TRUE, family = "Times")
    }
    grid::grid.newpage()
    grid::grid.draw(.g)
    grDevices::dev.off()
  }
  invisible(list(A = pA, B = pB, C = pC, elbow = el_df, traj = agg, legend = .leg))
}

# -----------------------------------------------------------------------------
# Fig1 flowchart (attrition counts overridable)
# -----------------------------------------------------------------------------
ckm_stroke_fig1_flowchart <- function(
    outfile,
    attrition = list(n0 = 17708L, e1 = 8358L, n1 = 9350L,
                     e2 = 1804L, n2 = 7546L, e3 = 709L, n3 = 6837L,
                     e4 = 1854L, n_final = 4983L),
    class_n = NULL,
    cohort_lab = "CHARLS Wave 1 participants",
    excl1_lab = "Excluded: incomplete CKM-stage\n(0\u20134) data (n=%s)",
    eligible_lab = "Eligible with CKM stages 0\u20134\n(n=%s)",
    excl2_lab = NULL,
    note = "Note: denominators follow project construction (final N=4,983), not verbatim paper N=5,248.",
    width = 8.8, height = 7.6) {
  .ff <- if (exists("pipeline_pdf_device", mode = "function")) {
    pipeline_pdf_device(outfile, width = width, height = height)
  } else {
    grDevices::pdf(outfile, width = width, height = height, useDingbats = FALSE, family = "Times")
    "Times"
  }
  on.exit(try(dev.off(), silent = TRUE), add = TRUE)
  par(mar = c(0.35, 0.35, 0.35, 0.35), xpd = NA, family = .ff)
  plot(0, 0, type = "n", xlim = c(0, 10), ylim = c(1.85, 10.15),
       axes = FALSE, xlab = "", ylab = "")
  .box <- function(x, y, w, h, txt, cex = 0.85, font = 1) {
    rect(x - w / 2, y - h / 2, x + w / 2, y + h / 2,
         border = "black", lwd = 1.25, col = "white")
    text(x, y, txt, cex = cex, font = font, family = .ff)
  }
  .fmtn <- function(x) format(as.integer(x), big.mark = ",")
  .sprintf_excl <- function(tpl, a) {
    slots <- gregexpr("%s", tpl, fixed = TRUE)[[1L]]
    n_slot <- if (length(slots) == 1L && identical(as.integer(slots), -1L)) 0L else length(slots)
    if (n_slot < 1L) return(tpl)
    vals <- list(a$e2, a$e3, a$e4, a$e5, a$e6)
    vals <- vals[seq_len(min(n_slot, length(vals)))]
    do.call(sprintf, c(list(tpl), lapply(vals, .fmtn)))
  }
  a <- attrition
  if (is.null(excl2_lab)) {
    excl2_lab <- paste0(
      "Excluded sequentially:\n",
      "Stroke or missing stroke status\nWaves 1\u20133 (n=%s)\n",
      "Missing stroke data at Wave 4\n(n=%s)\n",
      "Incomplete eGDR data in Wave 1\nor Wave 3 (n=%s)"
    )
  }
  xc <- 3.15
  xe <- 7.55
  bw <- 4.5
  bh <- 0.72
  bw_ex1 <- 3.7
  bh_ex1 <- 0.85
  bw_ex2 <- 3.85
  n_ex2_lines <- length(strsplit(excl2_lab, "\n", fixed = TRUE)[[1L]])
  bh_ex2 <- if (n_ex2_lines >= 5L) 1.95 else 1.65

  y0 <- 9.55
  y1 <- 8.05
  y2 <- 5.85
  y_cls <- 3.3
  bh_cls <- 0.7

  .box(xc, y0, bw, bh,
       sprintf("%s\n(n=%s)", cohort_lab, .fmtn(a$n0)), cex = 0.92)
  y_j1 <- (y0 - bh / 2 + y1 + bh / 2) / 2
  arrows(xc, y0 - bh / 2, xc, y1 + bh / 2, length = 0.1, lwd = 1.3)
  arrows(xc, y_j1, xe - bw_ex1 / 2, y_j1, length = 0.1, lwd = 1.3)
  .box(xe, y_j1, bw_ex1, bh_ex1, sprintf(excl1_lab, .fmtn(a$e1)), cex = 0.72)

  .box(xc, y1, bw, bh, sprintf(eligible_lab, .fmtn(a$n1)), cex = 0.9)
  y_j2 <- (y1 - bh / 2 + y2 + bh / 2) / 2
  arrows(xc, y1 - bh / 2, xc, y2 + bh / 2, length = 0.1, lwd = 1.3)
  arrows(xc, y_j2, xe - bw_ex2 / 2, y_j2, length = 0.1, lwd = 1.3)
  .box(xe, y_j2, bw_ex2, bh_ex2, .sprintf_excl(excl2_lab, a), cex = 0.64)

  .box(xc, y2, bw, bh,
       sprintf("%s subjects in final analysis", .fmtn(a$n_final)), cex = 0.95)

  # 底部分叉：只画实际出现且 n>0 的类（k=3 时不留 Class 4 空框）
  .cls_labs <- character(0)
  .cls_ns <- integer(0)
  if (!is.null(class_n) && length(class_n)) {
    nm <- names(class_n)
    if (is.null(nm) || !any(nzchar(nm))) {
      nm <- paste0("Class ", seq_along(class_n))
      names(class_n) <- nm
    }
    # 优先按 Class 1..k 排序；否则保持传入顺序
    ord <- order(match(nm, paste0("Class ", seq_len(20L)), nomatch = 999L), nm)
    nm <- nm[ord]
    vv <- as.integer(class_n[nm])
    keep <- !is.na(vv) & vv > 0L
    .cls_labs <- nm[keep]
    .cls_ns <- vv[keep]
  }
  if (!length(.cls_labs)) {
    .cls_labs <- paste0("Class ", 1:4)
    .cls_ns <- rep(0L, 4L)
  }
  n_cls <- length(.cls_labs)
  # 横排居中：2/3/4 类自适应间距
  if (n_cls == 1L) {
    xs <- 5.0
  } else if (n_cls == 2L) {
    xs <- c(2.8, 7.2)
  } else if (n_cls == 3L) {
    xs <- c(2.0, 5.0, 8.0)
  } else {
    xs <- seq(1.2, 8.8, length.out = n_cls)
  }
  box_w <- if (n_cls <= 3L) 2.35 else 1.95
  cex_cls <- if (n_cls <= 3L) 0.88 else 0.82

  y_bar <- y_cls + bh_cls / 2 + 0.42
  arrows(xc, y2 - bh / 2, xc, y_bar, length = 0.08, lwd = 1.3)
  segments(xs[1L], y_bar, xs[n_cls], y_bar, lwd = 1.3)
  for (i in seq_len(n_cls)) {
    arrows(xs[i], y_bar, xs[i], y_cls + bh_cls / 2, length = 0.08, lwd = 1.3)
    .box(xs[i], y_cls, box_w, bh_cls,
         sprintf("%s\n(n=%s)", .cls_labs[i], .fmtn(.cls_ns[i])), cex = cex_cls)
  }
  if (nzchar(as.character(note %||% "")[1L])) {
    text(5, 2.1, note, cex = 0.62, col = "grey30")
  }
  invisible(outfile)
}

# -----------------------------------------------------------------------------
# RCS panel (Fig3 / S1)
# -----------------------------------------------------------------------------
ckm_stroke_rcs_one_panel <- function(
    d, xcol, y_binary = TRUE, title_letter = "A",
    ylab = "Odds Ratio of Stroke", covars, outcome = "Stroke",
    xlab = "Cumulative eGDR",
    xlim_probs = c(0.05, 0.95),
    or_cap = c(0.3, 3),
    nknots = 4L) {
  if (!requireNamespace("rms", quietly = TRUE)) stop("need rms")
  nknots <- as.integer(nknots)[1L]
  if (!is.finite(nknots) || nknots < 3L) nknots <- 3L
  keep <- unique(c(if (y_binary) outcome else c("futime", "status"), xcol, covars))
  dd <- d[, intersect(keep, names(d)), drop = FALSE]
  for (cv in covars) if (is.character(dd[[cv]])) dd[[cv]] <- factor(dd[[cv]])
  dd <- dd[stats::complete.cases(dd), , drop = FALSE]
  if (nrow(dd) < 100) {
    return(ggplot2::ggplot() + ggplot2::theme_void() + ggplot2::ggtitle(title_letter))
  }
  xref <- as.numeric(stats::median(dd[[xcol]], na.rm = TRUE))
  x_lim <- as.numeric(stats::quantile(dd[[xcol]], probs = xlim_probs, na.rm = TRUE, names = FALSE))
  if (!all(is.finite(x_lim)) || x_lim[2] <= x_lim[1]) {
    x_lim <- range(dd[[xcol]], na.rm = TRUE)
  }
  ddn <- paste0("dd_", gsub("[^A-Za-z0-9]", "", title_letter), sample.int(1e6, 1))
  assign(ddn, rms::datadist(dd), envir = .GlobalEnv)
  options(datadist = ddn)
  dist <- get(ddn, envir = .GlobalEnv)
  dist$limits[[xcol]][2] <- xref
  assign(ddn, dist, envir = .GlobalEnv)
  if (!"package:rms" %in% search()) suppressPackageStartupMessages(library(rms))
  if (!"package:survival" %in% search()) suppressPackageStartupMessages(library(survival))

  .rcs_rhs <- paste0("rcs(", xcol, ", ", nknots, ")")
  if (length(covars)) .rcs_rhs <- paste(.rcs_rhs, paste(covars, collapse = "+"), sep = " + ")

  if (y_binary) {
    fml <- stats::as.formula(paste0(outcome, " ~ ", .rcs_rhs))
    fit <- rms::lrm(fml, data = dd, x = TRUE, y = TRUE)
    a <- anova(fit)
    rn <- rownames(a)
    p_overall <- tryCatch(as.numeric(a[grep(xcol, rn)[1], "P"]), error = function(e) NA_real_)
    p_nonlin <- tryCatch(as.numeric(a[grep("Nonlinear|nonlinear", rn, ignore.case = TRUE)[1], "P"]),
                         error = function(e) NA_real_)
    pp <- as.data.frame(rms::Predict(fit, name = xcol, ref.zero = TRUE, fun = exp))
  } else {
    fml <- stats::as.formula(paste0("Surv(futime, status) ~ ", .rcs_rhs))
    fit <- rms::cph(fml, data = dd, x = TRUE, y = TRUE, surv = TRUE)
    a <- anova(fit)
    rn <- rownames(a)
    p_overall <- tryCatch(as.numeric(a[grep(xcol, rn)[1], "P"]), error = function(e) NA_real_)
    p_nonlin <- tryCatch(as.numeric(a[grep("Nonlinear|nonlinear", rn, ignore.case = TRUE)[1], "P"]),
                         error = function(e) NA_real_)
    pp <- as.data.frame(rms::Predict(fit, name = xcol, ref.zero = TRUE, fun = exp))
  }
  .fmtp <- function(p) {
    if (is.na(p)) return("NA")
    if (p < 0.001) "<0.001" else sprintf("%.3f", p)
  }
  xname <- names(pp)[1]
  # 仅截横轴到中央分位；纵轴用 coord 裁切，禁止把点估计压成地板线
  pp <- pp[is.finite(pp[[xname]]) & pp[[xname]] >= x_lim[1] & pp[[xname]] <= x_lim[2], , drop = FALSE]
  if (!nrow(pp)) {
    return(ggplot2::ggplot() + ggplot2::theme_void() + ggplot2::ggtitle(title_letter))
  }
  hist_df <- data.frame(x = dd[[xcol]])
  hist_df <- hist_df[hist_df$x >= x_lim[1] & hist_df$x <= x_lim[2], , drop = FALSE]
  br <- pretty(range(hist_df$x, na.rm = TRUE), n = 28)
  h <- hist(hist_df$x, breaks = br, plot = FALSE)
  h_df <- data.frame(xmin = head(h$breaks, -1), xmax = tail(h$breaks, -1), count = h$counts)
  or_lo <- as.numeric(or_cap[1]); or_hi <- as.numeric(or_cap[2])
  # 直方图高度映射到 log 轴可视高度
  h_df$ymin <- or_lo
  h_df$ymax <- or_lo * (or_hi / or_lo)^(0.20 * h_df$count / max(h_df$count, 1))
  annot_lab <- sprintf("P for overall = %s\nP for non-linearity = %s", .fmtp(p_overall), .fmtp(p_nonlin))
  # P / Ref 放 subtitle+caption（绘图区外），避免与 vline/曲线 text-stroke FAIL
  p_rcs <- ggplot2::ggplot() +
    ggplot2::geom_rect(data = h_df, ggplot2::aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
                       fill = "#9ECAE1", color = NA, alpha = 0.55) +
    ggplot2::geom_ribbon(data = pp, ggplot2::aes(x = .data[[xname]], ymin = lower, ymax = upper),
                         fill = "#FCBBA1", alpha = 0.45) +
    ggplot2::geom_line(data = pp, ggplot2::aes(x = .data[[xname]], y = yhat),
                       color = "#CB181D", linewidth = 0.9) +
    ggplot2::geom_hline(yintercept = 1, linetype = 2, color = "#41B6C4", linewidth = 0.6) +
    ggplot2::geom_vline(xintercept = xref, linetype = 2, color = "#41B6C4", linewidth = 0.6) +
    ggplot2::scale_y_continuous(
      trans = "log10",
      breaks = c(0.3, 0.5, 1, 2, 3),
      labels = c("0.3", "0.5", "1.0", "2.0", "3.0")
    ) +
    ggplot2::coord_cartesian(xlim = x_lim, ylim = c(or_lo, or_hi), clip = "on") +
    ggplot2::labs(
      title = title_letter,
      subtitle = annot_lab,
      caption = sprintf("Ref. point = %.2f", xref),
      x = xlab, y = ylab
    ) +
    ckm_stroke_theme_paper(10) +
    ggplot2::theme(
      plot.subtitle = ggplot2::element_text(size = 9, face = "bold", hjust = 0),
      plot.caption = ggplot2::element_text(size = 8, face = "bold", colour = "#41B6C4", hjust = 0.5)
    )
  attr(p_rcs, "rcs_p_overall") <- p_overall
  attr(p_rcs, "rcs_p_nonlin") <- p_nonlin
  attr(p_rcs, "rcs_ref") <- xref
  p_rcs
}

# -----------------------------------------------------------------------------
# Free-Statistics forest (Fig S2/S3) — continuous per-SD
# -----------------------------------------------------------------------------
.ckm_mice_pool_expo <- function(imp, data, rows, exposure, covars, is_hr, outcome, interaction = NULL) {
  covars <- intersect(as.character(covars %||% character(0)), names(imp$data))
  fits <- lapply(seq_len(imp$m), function(i) {
    d <- mice::complete(imp, i)
    extra <- setdiff(names(data), names(d))
    for (v in extra) d[[v]] <- data[[v]]
    if (!is.null(rows)) d <- d[rows, , drop = FALSE]
    if (!is.null(interaction)) {
      d[[interaction]] <- factor(d[[interaction]])
      rhs <- paste(c(sprintf("%s * %s", exposure, interaction), covars), collapse = " + ")
    } else {
      rhs <- paste(c(exposure, covars), collapse = " + ")
    }
    if (!nzchar(rhs)) return(NULL)
    fit <- tryCatch({
      if (isTRUE(is_hr)) {
        survival::coxph(stats::as.formula(paste("survival::Surv(futime, status) ~", rhs)), data = d)
      } else {
        stats::glm(
          stats::as.formula(paste(outcome, "~", rhs)),
          data = d, family = stats::binomial()
        )
      }
    }, error = function(e) NULL)
    fit
  })
  if (any(vapply(fits, is.null, logical(1)))) return(NULL)
  sm <- tryCatch(
    as.data.frame(summary(mice::pool(mice::as.mira(fits)), conf.int = TRUE)),
    error = function(e) NULL
  )
  if (is.null(sm) || !nrow(sm)) return(NULL)
  sm
}

ckm_stroke_forest_free_stats <- function(
    data, expo_raw = "cum_eGDR", is_hr = FALSE, outfile,
    title = NULL, outcome = "Stroke",
    expo_lab = NULL,
    index_lab = NULL,
    model3 = c("Age", "Gender", "Marital", "BMI", "Education", "Smoke", "Drink",
               "eGFR", "Dyslipidemia", "Diabetes"),
    scale = c("unit", "sd"),
    allow_per_sd = FALSE,
    unit_delta = NULL,
    mice_keep = NULL,
    mice_impute = NULL,
    mice_m = 5L,
    mice_maxit = 5L,
    mice_seed = 2026L) {
  .ckm_pub_ensure_literature()
  if (!requireNamespace("forestploter", quietly = TRUE)) stop("need forestploter")
  stopifnot(expo_raw %in% names(data))
  # 与 Table3 同口径：Age "< 60"/"≥ 60"；Smoke/Drink Never/Ever
  data <- ckm_stroke_prepare_forest_groups(data, age_labels_compact = FALSE, drop_extreme_bmi = TRUE)
  # 仅当尚无可用 futime 时才回填；已并入访视月差时勿覆盖成常数 4
  if (is_hr) {
    has_ft <- "futime" %in% names(data) &&
      any(is.finite(as.numeric(data$futime)) & as.numeric(data$futime) > 0)
    if (!has_ft) data <- ckm_stroke_add_futime(data)
    if (!"status" %in% names(data) && outcome %in% names(data)) {
      data$status <- as.integer(as.numeric(data[[outcome]]) == 1L)
    }
  }

  scale <- match.arg(scale)
  unit_delta <- if (is.null(unit_delta)) {
    ckm_stroke_cont_unit_delta(index_lab)
  } else {
    as.numeric(unit_delta)[1L]
  }
  if (!is.finite(unit_delta) || unit_delta <= 0) unit_delta <- 1
  ckm_stroke_assert_forest_scale(
    scale, title, allow_per_sd = allow_per_sd, unit_delta = unit_delta
  )
  if (is.null(expo_lab) || !nzchar(as.character(expo_lab)[1L])) {
    expo_lab <- if (!is.null(index_lab) && nzchar(as.character(index_lab)[1L])) {
      paste("cumulative", as.character(index_lab)[1L])
    } else {
      "cumulative exposure"
    }
  }
  if (!is.null(index_lab) && nzchar(as.character(index_lab)[1L]) &&
      grepl("eGDR", expo_lab) && !grepl("eGDR", as.character(index_lab)[1L])) {
    stop("Forest label says eGDR but index_lab is ", index_lab, ".", call. = FALSE)
  }
  x <- as.numeric(data[[expo_raw]])
  sd_x <- stats::sd(x, na.rm = TRUE)
  if (identical(scale, "unit")) {
    if (isTRUE(all.equal(unit_delta, 1))) {
      expo <- expo_raw
    } else {
      data$cum_eGDR_udelta <- x / unit_delta
      expo <- "cum_eGDR_udelta"
    }
  } else {
    data$cum_eGDR_z <- as.numeric(scale(x))
    expo <- "cum_eGDR_z"
  }
  models3 <- intersect(model3, names(data))
  if ((is.null(mice_keep) || !length(mice_keep)) && isTRUE(mice_m > 0) && identical(scale, "unit")) {
    miss <- models3[vapply(models3, function(v) anyNA(data[[v]]), logical(1))]
    if (length(miss)) {
      mice_impute <- miss
      mice_keep <- intersect(
        c(outcome, "futime", "status", "eGDR_Class", expo_raw, expo, "eGDR_tertile", models3),
        names(data)
      )
    }
  }
  if (!is.null(mice_keep) && length(mice_keep) && identical(scale, "unit") &&
      !identical(expo, expo_raw) && expo %in% names(data)) {
    mice_keep <- unique(c(as.character(mice_keep), expo))
  }
  imp <- NULL
  imp_labs <- character(0)
  if (!is.null(mice_keep) && length(mice_keep)) {
    keep <- intersect(as.character(mice_keep), names(data))
    prep_mi <- ckm_stroke_prepare_mice(
      data[, keep, drop = FALSE],
      as.character(mice_impute %||% models3),
      m = mice_m, maxit = mice_maxit, seed = mice_seed
    )
    if (!is.null(prep_mi)) {
      imp <- prep_mi$imp
      imp_labs <- prep_mi$imputed
    }
  }

  sub_specs <- list(
    list(var = "Age_Group", label = "Age, years", drop = "Age"),
    list(var = "Gender", label = "Gender", drop = "Gender"),
    list(var = "BMI_Group", label = "BMI, kg/m\u00b2", drop = "BMI"),
    list(var = "Education", label = "Education", drop = "Education"),
    list(var = "Smoke_ne", label = "Smoke", drop = "Smoke"),
    list(var = "Drink_ne", label = "Drink", drop = "Drink"),
    list(var = "CKM_stage_group", label = "CKM stage", drop = character(0)),
    list(var = "Diabetes", label = "Diabetes", drop = "Diabetes"),
    list(var = "Hypertension", label = "Hypertension", drop = "Hypertension"),
    list(var = "Dyslipidemia", label = "Dyslipidemia", drop = "Dyslipidemia")
  )
  sub_specs <- Filter(function(s) s$var %in% names(data), sub_specs)
  effect_lab <- if (is_hr) "HR (95%CI)" else "OR (95%CI)"
  .pool_hit <- function(rows, cov, interaction = NULL) {
    if (is.null(imp)) return(NULL)
    sm <- .ckm_mice_pool_expo(imp, data, rows, expo, cov, is_hr, outcome, interaction)
    if (is.null(sm)) return(NULL)
    if (is.null(interaction)) {
      hit <- sm$term == expo
      if (!any(hit)) return(NULL)
      sm[which(hit)[1L], , drop = FALSE]
    } else {
      hit <- grepl(":", sm$term, fixed = TRUE)
      if (!any(hit)) return(NULL)
      # 二分类亚组只有一个交互项，取该行的合并 Wald P
      sm[which(hit)[1L], , drop = FALSE]
    }
  }
  fit1 <- function(d, cov) {
    if (!is.null(imp)) return(NULL)
    if (is_hr) ckm_stroke_fit_hr_row(d, expo, cov) else ckm_stroke_fit_or_row(d, expo, outcome, cov)
  }
  .from_pool <- function(hit) {
    lo_col <- grep("^2\\.5", names(hit), value = TRUE)[1L]
    hi_col <- grep("^97\\.5", names(hit), value = TRUE)[1L]
    est <- exp(hit$estimate[1L])
    list(est = est, lo = exp(hit[[lo_col]][1L]), hi = exp(hit[[hi_col]][1L]), p = hit$p.value[1L])
  }
  .stroke01 <- function(d) as.integer(as.numeric(d[[outcome]]) == 1L)
  .mk <- function(subgroup, total = "", event = "", effect_txt = "", pint = "",
                  est = NA_real_, lo = NA_real_, hi = NA_real_, is_header = FALSE) {
    out <- data.frame(
      Subgroup = as.character(subgroup)[1L],
      Total = as.character(total)[1L],
      `Event (%)` = as.character(event)[1L],
      check.names = FALSE, stringsAsFactors = FALSE
    )
    out[[effect_lab]] <- as.character(effect_txt)[1L]
    out[[" "]] <- paste(rep(" ", 20L), collapse = "")
    out[["P for interaction"]] <- as.character(pint)[1L]
    out$`Point Estimate` <- as.numeric(est)[1L]
    out$Lower <- as.numeric(lo)[1L]
    out$Upper <- as.numeric(hi)[1L]
    out$is_header <- isTRUE(is_header)
    out
  }
  .fmt_event <- function(n_event, n_tot) {
    if (!is.finite(n_tot) || n_tot <= 0) return("")
    sprintf("%d (%.1f)", as.integer(n_event), 100 * n_event / n_tot)
  }

  rows <- list()
  if (!is.null(imp)) {
    n_tot <- nrow(data)
    n_evt <- if (is_hr) sum(as.integer(data$status) == 1L, na.rm = TRUE) else sum(.stroke01(data))
    hitp <- .pool_hit(NULL, models3)
    if (!is.null(hitp)) {
      got <- .from_pool(hitp)
      if (is.finite(got$est) && got$est > 0 && is.finite(got$lo) && got$lo > 0 && is.finite(got$hi) && got$hi > 0) {
        rows[[length(rows) + 1L]] <- .mk(
          "Overall", format(n_tot, big.mark = ","), .fmt_event(n_evt, n_tot),
          ckm_stroke_fmt_or_tilde(got$est, got$lo, got$hi), "",
          got$est, got$lo, got$hi, FALSE
        )
      }
    }
  } else {
    rr <- fit1(data, models3)
    cc_cols <- unique(c(expo, if (is_hr) c("futime", "status") else outcome, models3))
    ok_all <- stats::complete.cases(data[, intersect(cc_cols, names(data)), drop = FALSE])
    n_tot <- sum(ok_all)
    n_evt <- if (is_hr) sum(as.integer(data$status[ok_all]) == 1L) else sum(.stroke01(data[ok_all, , drop = FALSE]))
    if (!is.null(rr) && nrow(rr)) {
      hit <- rr[1, , drop = FALSE]
      est0 <- if (is_hr) hit$HR[1] else hit$OR[1]
      if (is.finite(est0) && is.finite(hit$CI_low[1]) && hit$CI_low[1] > 0 &&
          is.finite(hit$CI_high[1]) && hit$CI_high[1] > 0 && est0 > 0) {
        rows[[length(rows) + 1L]] <- .mk(
          "Overall", n_tot, .fmt_event(n_evt, n_tot),
          ckm_stroke_fmt_or_tilde(est0, hit$CI_low[1], hit$CI_high[1]), "",
          est0, hit$CI_low[1], hit$CI_high[1], FALSE
        )
      }
    }
  }
  for (sp in sub_specs) {
    sv <- sp$var
    cov_i <- setdiff(models3, sp$drop)
    levs <- if (is.factor(data[[sv]])) levels(data[[sv]]) else unique(stats::na.omit(as.character(data[[sv]])))
    levs <- as.character(levs); levs <- levs[nzchar(levs)]
    if (!is.null(imp)) {
      obs <- which(!is.na(data[[sv]]))
      pint_row <- .pool_hit(obs, cov_i, interaction = sv)
      pint_txt <- if (is.null(pint_row)) "" else ckm_stroke_fmt_p(.from_pool(pint_row)$p)
    } else {
      pint <- ckm_stroke_lrt_pint(data, expo, sv, cov_i, is_hr = is_hr, outcome = outcome)
      pint_txt <- ckm_stroke_fmt_p(pint)
    }
    rows[[length(rows) + 1L]] <- .mk(sp$label, "", "", "", pint_txt, NA_real_, NA_real_, NA_real_, TRUE)
    for (lev in levs) {
      if (!is.null(imp)) {
        idx <- which(!is.na(data[[sv]]) & as.character(data[[sv]]) == lev)
        n_i <- length(idx)
        if (n_i < 30L) next
        n_e <- if (is_hr) sum(as.integer(data$status[idx]) == 1L, na.rm = TRUE) else sum(.stroke01(data[idx, , drop = FALSE]))
        if (n_e < 1L) next
        hitp <- .pool_hit(idx, cov_i)
        if (is.null(hitp)) next
        got <- .from_pool(hitp)
        est0 <- got$est; lo0 <- got$lo; hi0 <- got$hi
      } else {
        dsub <- data[as.character(data[[sv]]) == lev & !is.na(data[[sv]]), , drop = FALSE]
        if (nrow(dsub) < 30L) next
        need_cols <- unique(c(expo, if (is_hr) c("futime", "status") else outcome, cov_i))
        ok_cc <- stats::complete.cases(dsub[, intersect(need_cols, names(dsub)), drop = FALSE])
        dfit <- dsub[ok_cc, , drop = FALSE]
        n_i <- nrow(dfit)
        if (n_i < 30L) next
        n_e <- if (is_hr) sum(as.integer(dfit$status) == 1L) else sum(.stroke01(dfit))
        if (n_e < 1L) next
        rr <- fit1(dfit, cov_i)
        if (is.null(rr) || !nrow(rr)) next
        hit <- rr[1, , drop = FALSE]
        est0 <- if (is_hr) hit$HR[1] else hit$OR[1]
        lo0 <- hit$CI_low[1]; hi0 <- hit$CI_high[1]
      }
      if (!(is.finite(est0) && est0 > 0 && is.finite(lo0) && lo0 > 0 && is.finite(hi0) && hi0 > 0)) next
      rows[[length(rows) + 1L]] <- .mk(
        paste0("  ", lev),
        if (!is.null(imp)) format(n_i, big.mark = ",") else n_i,
        .fmt_event(n_e, n_i),
        ckm_stroke_fmt_or_tilde(est0, lo0, hi0), "",
        est0, lo0, hi0, FALSE
      )
    }
  }
  plot_df <- do.call(rbind, rows)
  rownames(plot_df) <- NULL
  if (!nrow(plot_df)) stop("empty forest rows")

  disp_cols <- c("Subgroup", "Total", "Event (%)", effect_lab, " ", "P for interaction")
  disp <- plot_df[, disp_cols, drop = FALSE]
  pint_col <- "P for interaction"
  disp[[pint_col]] <- ifelse(
    nzchar(as.character(disp[[pint_col]])),
    paste0(as.character(disp[[pint_col]]), "   "),
    paste(rep(" ", 12L), collapse = "")
  )
  teal <- "#008B8B"
  .ff_forest <- if (exists("resolve_plot_font_family", mode = "function")) {
    resolve_plot_font_family("Times New Roman")
  } else {
    "serif"
  }
  tm <- forestploter::forest_theme(
    base_size = 9,
    refline_gp = grid::gpar(lty = 1, col = "grey60", lwd = 1),
    ci_pch = 16, ci_col = teal, ci_fill = teal, ci_alpha = 1,
    ci_lty = 1, ci_lwd = 1.6, ci_Theight = 0,
    xaxis_gp = grid::gpar(fontsize = 7.5, col = "grey20", fontfamily = .ff_forest),
    core = list(fg_params = list(hjust = 0, x = 0.01, fontfamily = .ff_forest),
                bg_params = list(fill = "white")),
    colhead = list(fg_params = list(hjust = 0, x = 0.01, fontface = "bold", fontfamily = .ff_forest))
  )
  est <- as.numeric(plot_df$`Point Estimate`)
  lo <- as.numeric(plot_df$Lower)
  hi <- as.numeric(plot_df$Upper)
  bad <- !(is.finite(est) & is.finite(lo) & is.finite(hi) & est > 0 & lo > 0 & hi > 0)
  est[bad] <- lo[bad] <- hi[bad] <- NA_real_
  # 自适应 log 轴：WWI 等 per-unit ~1 时仍落在窄轴；ABSI 等小量纲指数
  # per-unit OR/HR 常为 5–30+，旧硬封顶 xlim=4 会使全部 CI 落在轴外→全是箭头。
  xlim <- c(0.15, 1.8)
  finite_lo <- lo[is.finite(lo) & lo > 0]
  finite_hi <- hi[is.finite(hi) & hi > 0]
  finite_est <- est[is.finite(est) & est > 0]
  if (length(finite_lo)) {
    xlim[1] <- max(0.05, min(as.numeric(stats::quantile(finite_lo, 0.05)) * 0.85, 0.5))
  }
  if (length(finite_hi) || length(finite_est)) {
    hi_q <- if (length(finite_hi)) {
      as.numeric(stats::quantile(finite_hi, 0.90, names = FALSE)) * 1.15
    } else {
      1.8
    }
    est_cap <- if (length(finite_est)) max(finite_est) * 1.4 else 1.3
    xlim[2] <- max(1.3, hi_q, est_cap)
    # 软顶：极端稀疏层（如 Diabetes Yes 上界上千）仍可出箭头，主效应须可见
    xlim[2] <- min(xlim[2], 100)
  }
  if (!(is.finite(xlim[1]) && xlim[1] > 0 && is.finite(xlim[2]) && xlim[2] > xlim[1])) xlim <- c(0.2, 2)
  lo_draw <- pmax(lo, xlim[1] * 0.999); hi_draw <- pmin(hi, xlim[2] * 1.001)
  lo_draw[!is.finite(lo)] <- NA_real_; hi_draw[!is.finite(hi)] <- NA_real_
  # 稀疏刻度；宽轴时补 5/10/20/50/100，避免只剩 0.25–4
  ticks_cand <- c(0.1, 0.25, 0.5, 1, 2, 5, 10, 20, 50, 100)
  ticks <- ticks_cand[ticks_cand >= xlim[1] * 0.98 & ticks_cand <= xlim[2] * 1.02]
  if (!any(abs(ticks - 1) < 1e-8)) ticks <- sort(unique(c(ticks, 1)))
  if (length(ticks) < 2L) ticks <- sort(unique(c(xlim[1], 1, xlim[2])))
  # 若仍偏密（相邻比 <1.6），再抽稀
  if (length(ticks) >= 4L) {
    keep <- rep(TRUE, length(ticks))
    last <- ticks[1]
    for (i in seq_along(ticks)[-1]) {
      if (ticks[i] / last < 1.6 && abs(ticks[i] - 1) > 1e-8) {
        keep[i] <- FALSE
      } else {
        last <- ticks[i]
      }
    }
    ticks <- ticks[keep]
  }

  p <- forestploter::forest(
    disp, est = est, lower = lo_draw, upper = hi_draw, sizes = 0.4,
    ci_column = which(disp_cols == " ")[1L], ref_line = 1,
    xlim = xlim, ticks_at = ticks, x_trans = "log", theme = tm
  )
  p <- forestploter::edit_plot(p, part = "header", gp = grid::gpar(fontface = "bold"))
  hdr <- which(isTRUE(plot_df$is_header) | plot_df$is_header %in% TRUE)
  if (length(hdr)) p <- forestploter::edit_plot(p, row = hdr, gp = grid::gpar(fontface = "bold"))
  pint_idx <- which(disp_cols == pint_col)[1L]
  if (!is.null(p$widths) && is.finite(pint_idx)) {
    g_pint <- as.integer(pint_idx) + 1L
    if (g_pint >= 1L && g_pint <= length(p$widths)) {
      cur <- tryCatch(as.numeric(grid::convertWidth(p$widths[[g_pint]], "in", valueOnly = TRUE)),
                      error = function(e) NA_real_)
      if (!is.finite(cur) || cur < 0.55) cur <- 0.7
      p$widths[[g_pint]] <- grid::unit(max(cur, 0.95), "in")
    }
  }
  # 加宽 CI 列，减轻刻度拥挤
  ci_idx <- which(disp_cols == " ")[1L]
  if (!is.null(p$widths) && is.finite(ci_idx)) {
    g_ci <- as.integer(ci_idx) + 1L
    if (g_ci >= 1L && g_ci <= length(p$widths)) {
      cur_ci <- tryCatch(as.numeric(grid::convertWidth(p$widths[[g_ci]], "in", valueOnly = TRUE)),
                         error = function(e) NA_real_)
      if (!is.finite(cur_ci)) cur_ci <- 1.6
      p$widths[[g_ci]] <- grid::unit(max(cur_ci, 2.2), "in")
    }
  }
  if (!is.null(p$layout) && "clip" %in% names(p$layout)) p$layout$clip[] <- "off"

  ud_lab <- ckm_stroke_unit_delta_label(unit_delta)
  if (!is.null(imp)) {
    sd_note <- c(
      sprintf(
        "Per %s increase in %s, the same scale as Tables 2 and S1. Overall n = %s (%s events) is the analytic cohort.",
        ud_lab, as.character(expo_lab)[1L], format(n_tot, big.mark = ","), format(n_evt, big.mark = ",")
      ),
      sprintf(
        "Missing Model 3 covariates (%s) are imputed (mice, m=%d, seed=%d). Interaction P is the pooled Wald test. Observed stratum levels can sum to less than Overall.",
        paste(imp_labs, collapse = ", "), as.integer(mice_m), as.integer(mice_seed)
      )
    )
  } else if (identical(scale, "unit")) {
    sd_note <- sprintf(
      "Per %s increase in %s, the same scale as the regression tables. Model 3 covariates (stratification variable dropped). P for interaction: LRT.",
      ud_lab, as.character(expo_lab)[1L]
    )
  } else {
    sd_note <- sprintf(
      "Exposure: per 1-SD increase in %s (SD = %.3f). Continuous OR/HR in tables uses unit_delta=%s. Model 3 covariates (stratification variable dropped). P for interaction: LRT.",
      as.character(expo_lab)[1L], sd_x, format(unit_delta, trim = TRUE)
    )
  }
  fig_w <- 10.2
  fig_h <- max(5.4, min(7.6, 0.245 * nrow(plot_df) + 1.35))
  .ff <- if (exists("resolve_plot_font_family", mode = "function")) {
    resolve_plot_font_family("Times New Roman")
  } else {
    "Times"
  }
  if (exists("pipeline_pdf_device", mode = "function")) {
    pipeline_pdf_device(outfile, width = fig_w, height = fig_h)
  } else {
    grDevices::pdf(outfile, width = fig_w, height = fig_h, useDingbats = FALSE, family = .ff)
  }
  grid::grid.newpage()
  # 上下留白：避免标题压 Subgroup 表头、脚注压横轴刻度
  grid::pushViewport(grid::viewport(x = 0.5, y = 0.50, width = 0.98, height = 0.78))
  grid::grid.draw(p)
  grid::popViewport()
  if (!is.null(title) && nzchar(title)) {
    grid::grid.text(title, x = 0.02, y = 0.975, just = c("left", "top"),
                    gp = grid::gpar(fontsize = 9, fontface = "bold", col = "grey15", fontfamily = .ff))
  }
  sd_note <- as.character(sd_note)
  y0 <- 0.012 + 0.018 * (seq_along(sd_note) - 1L)
  y0 <- rev(y0)
  for (i in seq_along(sd_note)) {
    grid::grid.text(sd_note[i], x = 0.02, y = y0[i], just = c("left", "bottom"),
                    gp = grid::gpar(fontsize = 6.5, col = "grey25", fontfamily = .ff))
  }
  grDevices::dev.off()
  attr(plot_df, "sd") <- sd_x
  attr(plot_df, "unit_delta") <- unit_delta
  attr(plot_df, "exposure_scale") <- if (identical(scale, "sd")) {
    "per_1_SD"
  } else if (isTRUE(all.equal(unit_delta, 1))) {
    "per_1_unit"
  } else {
    paste0("per_", format(unit_delta, trim = TRUE), "_unit")
  }
  invisible(plot_df)
}

# -----------------------------------------------------------------------------
# Junk cleanup + kill old Fig2 split panels
# -----------------------------------------------------------------------------
ckm_stroke_clean_summary_junk <- function(tab_dir, fig_dir, sr_dir = dirname(tab_dir)) {
  junk_pat <- c(
    "^_raw_", "^_style_test", "Figure_S.*_forest_rows\\.csv$",
    "^Kmeans_elbow_WCSS\\.csv$", "^Flowchart_attrition",
    "^Covariate_UV_VIF_selection\\.csv$"
  )
  junk_dir <- file.path(sr_dir, "_archive_non_pub_tables")
  dir.create(junk_dir, recursive = TRUE, showWarnings = FALSE)
  moved <- character(0)
  for (f in list.files(tab_dir, full.names = TRUE)) {
    bn <- basename(f)
    if (any(vapply(junk_pat, function(p) grepl(p, bn), logical(1)))) {
      file.rename(f, file.path(junk_dir, bn))
      moved <- c(moved, bn)
    }
  }
  fr <- file.path(fig_dir, "Figure_S3_forest_rows.csv")
  if (file.exists(fr)) {
    file.rename(fr, file.path(junk_dir, basename(fr)))
    moved <- c(moved, basename(fr))
  }
  invisible(moved)
}

ckm_stroke_kill_fig2_splits <- function(fig_dir) {
  stems <- c(
    "Figure 2A. Elbow method WCSS",
    "Figure 2B. Mean eGDR trajectories by class",
    "Figure 2C. eGDR distribution by class",
    "Figure. Table3 Class subgroup forest OR"
  )
  for (sub in c("", "pdf", "png", "tiff", "image_information")) {
    base <- if (nzchar(sub)) file.path(fig_dir, sub) else fig_dir
    if (!dir.exists(base)) next
    for (stem in stems) {
      for (ext in c(".pdf", ".png", ".tiff", ".md")) {
        p <- file.path(base, paste0(stem, ext))
        if (file.exists(p)) unlink(p)
      }
    }
  }
  invisible(TRUE)
}

# -----------------------------------------------------------------------------
# Delivery finalize — Methods md + software txt + whitelist prune
# -----------------------------------------------------------------------------

#' ELSA / CKM 累积暴露×k-means 课题 Methods 正文行
#'
#' @param index_lab 指标展示名（如 ABSI / WWI）
#' @param n_analytic 分析集人数
#' @param model2_covars Model 2 协变量
#' @param model3_covars Model 3 协变量字符向量
#' @param ref_class_note 参照类按指标重挑的说明
#' @param unit_delta 连续项步长（ABSI 默认 0.1）
#' @param min_age 纳入年龄下界
#' @param database 数据库名
#' @param outcome_lab 结局展示名
ckm_stroke_elsa_methods_statistical_lines <- function(
    index_lab = "ABSI",
    n_analytic = NA_integer_,
    model2_covars = character(0),
    model3_covars = c("Age", "Gender", "Marital", "Dyslipidemia", "Hypertension"),
    ref_class_note = "",
    unit_delta = NULL,
    min_age = 50L,
    database = "ELSA",
    outcome_lab = "incident osteoporosis",
    k_clusters = NULL,
    k_note = NULL,
    covariate_scheme = c("uv_vif", "prespecified"),
    covariate_note = NULL,
    # osteoporosis: 暴露 W4+W6、结局 W8；masld: 暴露 W2+W4、结局 W6
    elsa_wave_scheme = c("osteoporosis", "masld")) {
  covariate_scheme <- match.arg(covariate_scheme)
  elsa_wave_scheme <- match.arg(elsa_wave_scheme)
  ix <- as.character(index_lab %||% "index")[1L]
  ud <- if (is.null(unit_delta)) ckm_stroke_cont_unit_delta(ix) else as.numeric(unit_delta)[1L]
  if (!is.finite(ud) || ud <= 0) ud <- 1
  ud_lab <- ckm_stroke_unit_delta_label(ud)
  cov2_txt <- paste(as.character(model2_covars %||% character(0)), collapse = ", ")
  cov_txt <- paste(as.character(model3_covars %||% character(0)), collapse = ", ")
  n_txt <- if (is.finite(as.numeric(n_analytic)[1L])) {
    format(as.integer(n_analytic)[1L], big.mark = ",")
  } else {
    "the analytic sample"
  }
  db <- as.character(database %||% "ELSA")[1L]
  is_elsa <- grepl("ELSA", db, ignore.case = TRUE)
  is_masld <- identical(elsa_wave_scheme, "masld")
  # 若调用方已写 MASLD 结局却未改 scheme，自动切到 masld 波次（防骨质疏松模板串台）
  if (!is_masld && grepl("MASLD|masld|fatty liver", as.character(outcome_lab)[1L], ignore.case = TRUE)) {
    is_masld <- TRUE
    elsa_wave_scheme <- "masld"
  }
  cohort_para <- if (is_elsa && is_masld) {
    sprintf(
      "Adults aged at least %s years at Wave 4 were eligible. Participants required Wave 2, Wave 4, and Wave 6 interviews. Incident MASLD was defined as Wave 6 DN = 1 among participants with Wave 4 DN = 0; Wave 2 DN was not used as an exclusion flag. The final analytic sample for %s comprised N = %s after requiring complete Wave 2 and Wave 4 exposure values.",
      as.integer(min_age)[1L], ix, n_txt
    )
  } else if (is_elsa) {
    sprintf(
      "Adults aged at least %s years at Wave 4 were eligible. Participants required Wave 6 and Wave 8 interviews. Incident osteoporosis was defined as Wave 8 DN = 1 among participants with Wave 6 DN = 0; Wave 4 DN was not used as an exclusion flag. The final analytic sample for %s comprised N = %s after requiring complete two-wave exposure values.",
      as.integer(min_age)[1L], ix, n_txt
    )
  } else {
    sprintf(
      "Adults aged at least %s years were eligible in %s. The final analytic sample for %s comprised N = %s after applying the study inclusion criteria and requiring complete two-wave exposure values used for cumulative exposure and k-means classes.",
      as.integer(min_age)[1L], db, ix, n_txt
    )
  }
  .k_sentence <- {
    kn <- as.character(k_note %||% "")[1L]
    if (nzchar(kn)) {
      kn
    } else if (!is.null(k_clusters) && is.finite(as.numeric(k_clusters)[1L])) {
      sprintf(
        "k was pre-specified as %d for this index (config force_k_by_index).",
        as.integer(k_clusters)[1L]
      )
    } else {
      "k was chosen from the elbow plot with a visual cap of 4."
    }
  }
  if (!endsWith(trimws(.k_sentence), ".") && !endsWith(trimws(.k_sentence), ";")) {
    .k_sentence <- paste0(trimws(.k_sentence), ".")
  }
  exposure_para <- if (is_elsa && is_masld) {
    paste0(
      sprintf(
        "Wave-specific %s used the standard anthropometric definition available in the harmonised files. Cumulative exposure was ((%s Wave 2 + %s Wave 4)/2) \u00d7 4 (ELSA wave span). Continuous association estimates are reported per %s increase. Trajectory classes used k-means on unstandardized Wave 2 and Wave 4 values (nstart = 25, seed = 2026, iter.max = 100); %s Class display names follow the observed mean trajectory; a decline is labelled rapid only when the absolute mean change is at least 25%% of the between-class Wave 2 mean range. ",
        ix, ix, ix, ud_lab, .k_sentence
      ),
      "The regression reference class was re-selected for each index (not hard-coded to Class 2): higher-worse indices use the lowest Wave-2 mean class; higher-better indices (eGDR) use the highest Wave-2 mean class.",
      if (nzchar(as.character(ref_class_note %||% "")[1L])) {
        paste0(" For this index: ", as.character(ref_class_note)[1L], ".")
      } else {
        ""
      }
    )
  } else if (is_elsa) {
    paste0(
      sprintf(
        "Wave-specific %s used the standard anthropometric definition available in the harmonised files. Cumulative exposure was ((%s Wave 4 + %s Wave 6)/2) \u00d7 4 (ELSA wave span). Continuous association estimates are reported per %s increase. Trajectory classes used k-means on unstandardized Wave 4 and Wave 6 values (nstart = 25, seed = 2026, iter.max = 100); %s Class display names follow the observed mean trajectory; a decline is labelled rapid only when the absolute mean change is at least 25%% of the between-class Wave 4 mean range. ",
        ix, ix, ix, ud_lab, .k_sentence
      ),
      "The regression reference class was re-selected for each index (not hard-coded to Class 2): higher-worse indices use the lowest Wave-4 mean class; higher-better indices (eGDR) use the highest Wave-4 mean class.",
      if (nzchar(as.character(ref_class_note %||% "")[1L])) {
        paste0(" For this index: ", as.character(ref_class_note)[1L], ".")
      } else {
        ""
      }
    )
  } else {
    .absi_formula <- if (identical(toupper(ix), "ABSI")) {
      " ABSI followed Krakauer (metres): (WC/100) / (BMI^(2/3) \u00d7 (Height/100)^(1/2)), with WC and Height stored in centimetres. "
    } else {
      " "
    }
    sprintf(
      "Wave-specific %s used the study anthropometric definition.%sCumulative exposure pooled the two analysis waves as defined in the project config. Continuous association estimates are reported per %s increase. Trajectory classes used k-means on unstandardized two-wave values (nstart = 25, seed = 2026, iter.max = 100); %s Class display names follow the observed mean trajectory; a decline is labelled rapid only when the absolute mean change is at least 25%% of the between-class first-wave mean range.",
      ix, .absi_formula, ud_lab, .k_sentence
    )
  }
  outcome_para <- if (is_elsa && is_masld) {
    sprintf(
      "The primary outcome was binary %s. Logistic models estimated odds ratios. Cox models (Table S1 / Figure S1) used a fixed Wave 4 to Wave 6 interval (4 years) as an interval check of the same binary outcome.",
      outcome_lab
    )
  } else if (is_elsa) {
    sprintf(
      "The primary outcome was binary %s. Logistic models estimated odds ratios. Cox models used a fixed Wave 6 to Wave 8 interval (4 years) as an interval check of the same binary outcome; Figure S1 used interview-month follow-up between Wave 6 and Wave 8.",
      outcome_lab
    )
  } else {
    sprintf(
      "The primary outcome was binary %s. Logistic models estimated odds ratios. Cox models used the study follow-up definition; Figure S1 (when present) used the time scale documented in the figure legend.",
      outcome_lab
    )
  }
  c(
    "# Statistical analysis",
    "",
    "## Study design and cohort",
    sprintf(
      "This was an observational association analysis of cumulative %s exposure and k-means trajectory classes with %s in %s. It is not a predictive modelling study and not an artificial-intelligence analysis.",
      ix, outcome_lab, db
    ),
    cohort_para,
    "",
    "## Exposure",
    exposure_para,
    "",
    "## Outcome and follow-up",
    outcome_para,
    "",
    "## Regression models",
    {
      m2v <- as.character(model2_covars %||% character(0))
      m3v <- as.character(model3_covars %||% character(0))
      .scheme <- as.character(covariate_scheme %||% "uv_vif")[1L]
      .extra <- as.character(covariate_note %||% "")[1L]
      paste0(
        "Model 1 was unadjusted. ",
        if (identical(.scheme, "prespecified")) {
          paste0(
            if (length(m2v)) sprintf("Model 2 was pre-specified and adjusted for: %s. ", paste(m2v, collapse = ", "))
            else "Model 2 used a pre-specified demographic core. ",
            if (length(m3v)) {
              sprintf(
                "Model 3 was pre-specified and adjusted for: %s (not screened by univariate P or VIF; exposure-component variables excluded; not fully adjusted). ",
                paste(m3v, collapse = ", ")
              )
            } else {
              "Model 3 extended Model 2 with pre-specified clinical covariates (not fully adjusted). "
            },
            if (nzchar(.extra)) paste0(.extra, " ") else ""
          )
        } else {
          paste0(
            if (length(m2v)) sprintf("Model 2 adjusted for: %s. ", paste(m2v, collapse = ", "))
            else "Model 2 used the study demographic core after univariate/VIF screening. ",
            if (length(m3v)) {
              sprintf(
                "Model 3 adjusted for: %s (univariate P < 0.05 then VIF < 4 where screening applied; exposure-component variables and proxies excluded; not fully adjusted). ",
                paste(m3v, collapse = ", ")
              )
            } else {
              "Model 3 extended Model 2 with clinical candidates after univariate/VIF screening (not fully adjusted). "
            }
          )
        },
        "The same locked Model 2 / Model 3 sets were used for Table 2, Table S1, RCS, and subgroup forests (stratification variable dropped within its own stratum)."
      )
    },
    if (nzchar(cov2_txt)) sprintf("Locked Model 2 covariates for this index: %s.", cov2_txt) else NULL,
    sprintf("Locked Model 3 covariates for this index (used for Table 2/S1/S3/S4, Table 3, RCS, and subgroup forests): %s.", cov_txt),
    "Odds ratios and hazard ratios are reported to three decimal places with 95% confidence intervals (engine rule; Wang 2026 often used two decimals). P values use three decimals or <0.001. Table 1 continuous summaries use two decimals; percentages use one decimal. Quantile P for trend used the ordinal quantile score. Unordered trajectory classes did not receive a P for trend.",
    "",
    "## Restricted cubic splines and subgroups",
    "Restricted cubic splines used three knots (rms). Figure 3 (logistic OR) and Figure S1 (Cox HR), when exported, show Overall and pre-specified strata under Model 3. P for overall and P for non-linearity are shown on each panel; the RCS overall test may differ from the Table 2 linear continuous P because the functional forms differ.",
    sprintf(
      "Subgroup forests (Figures S2–S3), when exported, report per-%s contrasts on the full analytic sample. When Model 3 covariates were incomplete, mice (m = 5) with Rubin's rules was used for those covariates; stratification variables themselves were not imputed. Table 2 / Table S1 Model 3 continuous rows remain complete-case estimates and may therefore differ numerically from the forest Overall row while sharing the same unit_delta.",
      ud_lab
    ),
    "",
    "## Missing data",
    "Primary Table 1 / Table 2 / Table S1 association estimates used complete cases for the variables in each model. Multiple-imputation sensitivity tables (when exported) used mice with m = 5 and Rubin's rules and were not copies of the complete-case tables.",
    "",
    "## Software",
    "Analyses were performed in R. Package versions are listed in Methods_software_versions.txt beside this file."
  )
}

#' 写 Methods md + 软件版本 txt，并按全项目白名单修剪 summary_results
#'
#' 交付根只留 Figures/ Tables/ Methods_statistical_analysis.md /
#' Methods_software_versions.txt / *中期*.pdf。
ckm_stroke_finalize_summary_delivery <- function(
    summary_root,
    index_lab = "ABSI",
    n_analytic = NA_integer_,
    model2_covars = character(0),
    model3_covars = c("Age", "Gender", "Marital", "Dyslipidemia", "Hypertension"),
    ref_class_note = "",
    unit_delta = NULL,
    min_age = 50L,
    database = "ELSA",
    outcome_lab = "incident osteoporosis",
    software_extra = character(0),
    prune = TRUE,
    k_clusters = NULL,
    k_note = NULL,
    covariate_scheme = c("uv_vif", "prespecified"),
    covariate_note = NULL,
    elsa_wave_scheme = c("osteoporosis", "masld")) {
  covariate_scheme <- match.arg(covariate_scheme)
  elsa_wave_scheme <- match.arg(elsa_wave_scheme)
  sr <- as.character(summary_root %||% "")[1L]
  if (!nzchar(sr) || !dir.exists(sr)) {
    stop("ckm_stroke_finalize_summary_delivery: summary_root missing: ", sr, call. = FALSE)
  }
  .repo <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = Sys.getenv("BLOCK_REPO_ROOT", unset = "."))
  if (!exists("pub_prune_delivery_root", mode = "function")) {
    pr <- file.path(.repo, "R/pub_delivery_prune.R")
    if (file.exists(pr)) source(pr, local = FALSE)
  }
  if (!exists("pub_delivery_scrub_display", mode = "function") &&
      !exists("pub_xlsx_scrub_underscores_dir", mode = "function")) {
    px <- file.path(.repo, "R/pub_xlsx_surgical.R")
    if (file.exists(px)) source(px, local = FALSE)
    if (file.exists(file.path(.repo, "R/pub_delivery_prune.R"))) {
      source(file.path(.repo, "R/pub_delivery_prune.R"), local = FALSE)
    }
  }
  if (exists("pub_delivery_normalize_fig_tab_dirs", mode = "function")) {
    pub_delivery_normalize_fig_tab_dirs(sr)
  }
  if (exists("pub_delivery_clean_tables_xlsx_only", mode = "function")) {
    pub_delivery_clean_tables_xlsx_only(sr)
  }
  # 展示层铁律：禁下划线 + Times New Roman（表 xlsx + image_information）
  scrub_res <- NULL
  if (exists("pub_delivery_scrub_display", mode = "function")) {
    scrub_res <- tryCatch(
      pub_delivery_scrub_display(sr, root = .repo),
      error = function(e) {
        warning("pub_delivery_scrub_display failed: ", conditionMessage(e))
        NULL
      }
    )
  } else if (exists("pub_delivery_scrub_tables_underscores", mode = "function")) {
    scrub_res <- tryCatch(
      pub_delivery_scrub_tables_underscores(sr, root = .repo),
      error = function(e) NULL
    )
  }
  lines <- ckm_stroke_elsa_methods_statistical_lines(
    index_lab = index_lab,
    n_analytic = n_analytic,
    model2_covars = model2_covars,
    model3_covars = model3_covars,
    ref_class_note = ref_class_note,
    unit_delta = unit_delta,
    min_age = min_age,
    database = database,
    outcome_lab = outcome_lab,
    k_clusters = k_clusters,
    k_note = k_note,
    covariate_scheme = covariate_scheme,
    covariate_note = covariate_note,
    elsa_wave_scheme = elsa_wave_scheme
  )
  lines <- lines[!vapply(lines, is.null, logical(1))]
  md_path <- file.path(sr, "Methods_statistical_analysis.md")
  writeLines(lines, md_path, useBytes = TRUE)
  soft_extra <- unique(c(
    sprintf(
      "Study title: association of trajectory clusters and cumulative %s with %s (logistic, Cox, RCS). Not a predictive or AI analysis.",
      index_lab, outcome_lab
    ),
    sprintf("Inclusion: baseline age at least %s years.", as.integer(min_age)[1L]),
    sprintf("Analytic N = %s (%s).", format(as.integer(n_analytic)[1L], big.mark = ","), database),
    sprintf(
      "Continuous exposure reported per %s (ckm_stroke_cont_unit_delta).",
      ckm_stroke_unit_delta_label(
        if (is.null(unit_delta)) ckm_stroke_cont_unit_delta(index_lab) else unit_delta
      )
    ),
    if (identical(as.character(covariate_scheme)[1L], "prespecified")) {
      "Model 2/3 covariates were pre-specified for this index (not UV/VIF screened); exposure components excluded; not fully adjusted."
    } else {
      sprintf(
        "Model 3: univariate P<0.05 then VIF<4; exposure components/proxies excluded%s; not fully adjusted.",
        if ("Age" %in% as.character(model3_covars %||% character(0))) "; Age forced when allowed" else ""
      )
    },
    "Subgroup forests may use mice(m=5)+Rubin for incomplete Model 3 covariates; Table2/S1 Model3 remain complete-case.",
    as.character(software_extra %||% character(0))
  ))
  soft_path <- ckm_stroke_write_software_versions(sr, extra = soft_extra)
  # Tables 旁保留一份副本供脚注引用（prune 会把 Tables 内非 xlsx 移走前先写根目录）
  tab_dir <- file.path(sr, "Tables")
  if (dir.exists(tab_dir) && file.exists(soft_path)) {
    file.copy(soft_path, file.path(tab_dir, "Methods_software_versions.txt"), overwrite = TRUE)
  }
  fig_dir <- file.path(sr, "Figures")
  if (dir.exists(fig_dir) && exists("pub_figure_ensure_formats", mode = "function")) {
    # 全项目默认 PDF + image_information；不交付 png/tiff
    try(
      pub_figure_ensure_formats(
        fig_dir,
        meta = list(study = "cum_kmeans", index = index_lab),
        config = list(
          pub_figures = list(
            dpi = 600L,
            formats_dir = TRUE,
            export_png = FALSE,
            export_tiff = FALSE
          )
        ),
        purge = FALSE
      ),
      silent = TRUE
    )
    if (exists("pub_figure_drop_raster_dirs", mode = "function")) {
      try(pub_figure_drop_raster_dirs(fig_dir), silent = TRUE)
    } else {
      unlink(file.path(fig_dir, c("png", "tiff")), recursive = TRUE, force = TRUE)
    }
  }
  # 图文件名禁下划线（展示层）
  if (dir.exists(fig_dir) && exists("pipeline_display_no_underscore", mode = "function")) {
    for (sub in c("pdf", "image_information", "")) {
      base <- if (nzchar(sub)) file.path(fig_dir, sub) else fig_dir
      if (!dir.exists(base)) next
      for (f in list.files(base, full.names = TRUE)) {
        if (dir.exists(f)) next
        bn <- basename(f)
        bn2 <- pipeline_display_no_underscore(bn)
        if (!identical(bn, bn2)) {
          dest <- file.path(dirname(f), bn2)
          if (!file.exists(dest)) file.rename(f, dest)
        }
      }
    }
  }
  moved <- character(0)
  if (isTRUE(prune) && exists("pub_prune_delivery_root", mode = "function")) {
    # Tables 内 txt 不在白名单根级规则内，但 clean_tables 会移走非 xlsx——先清再 prune
    if (exists("pub_delivery_clean_tables_xlsx_only", mode = "function")) {
      pub_delivery_clean_tables_xlsx_only(sr)
    }
    # 删除遗留 .keep_raster，避免 prune 误留 png/tiff
    if (dir.exists(fig_dir)) {
      unlink(file.path(fig_dir, ".keep_raster"), force = TRUE)
    }
    res <- pub_prune_delivery_root(sr, keep_raster = FALSE)
    moved <- res$moved %||% character(0)
  }
  # 白名单：根目录只留 Figures/Tables/Methods_*.md|txt/*中期*.pdf
  # （prune 已执行；此处再断言，失败只警告不阻断）
  if (isTRUE(prune)) {
    allow_root <- c(
      "Figures", "Tables",
      "Methods_statistical_analysis.md", "Methods_software_versions.txt"
    )
    left <- list.files(sr, all.files = FALSE, no.. = TRUE)
    bad <- setdiff(left, c(allow_root, left[grepl("\u4e2d\u671f", left)]))
    if (length(bad)) {
      warning(
        "ckm_stroke_finalize_summary_delivery: delivery root has non-whitelist items: ",
        paste(bad, collapse = ", ")
      )
    }
  }
  invisible(list(
    summary_root = normalizePath(sr, winslash = "/", mustWork = FALSE),
    methods = md_path,
    software = soft_path,
    moved = moved,
    scrub = scrub_res
  ))
}

#' 引擎级中期：客户名可配；默认不写日期；出完再 prune 白名单
ckm_stroke_write_midterm_report <- function(
    summary_root,
    index_lab,
    client = "vivili",
    no_date = TRUE,
    formula_lines = character(0),
    model2_covars = character(0),
    model3_covars = character(0),
    n_analytic = NA_integer_,
    outcome_lab = "新发骨质疏松",
    methods_lab = "k-means轨迹聚类、Logistic、Cox、限制性立方样条",
    database = "ELSA") {
  sr <- as.character(summary_root %||% "")[1L]
  stopifnot(dir.exists(sr))
  ix <- as.character(index_lab %||% "index")[1L]
  ix <- if (exists("pipeline_display_label", mode = "function")) pipeline_display_label(ix) else gsub("_", " ", ix, fixed = TRUE)
  client <- as.character(client %||% "vivili")[1L]
  if (!nzchar(client)) client <- "vivili"
  info <- file.path(sr, "项目信息-中期.md")
  formula_txt <- if (length(formula_lines)) paste(formula_lines, collapse = "；") else sprintf("%s（见 Methods）", ix)
  .info_lines <- c(
    sprintf("客户: %s", client),
    sprintf("暴露指标: %s", ix),
    sprintf("结局: %s", outcome_lab),
    sprintf("报告标题: %s轨迹类别与累积暴露和%s的关联分析", ix, outcome_lab),
    "标题副题: 中期分析结果",
    sprintf("研究人群: %s 基线年龄≥50岁成人", database),
    sprintf("分析方法: %s", methods_lab),
    sprintf("数据集: %s", database),
    "类型: 中期分析结果",
    sprintf("指标计算公式: %s", formula_txt),
    if (isTRUE(no_date)) "分析日期: 无" else NULL,
    if (isTRUE(no_date)) "日期: 无" else NULL,
    ""
  )
  # 必须 UTF-8 落盘；useBytes=TRUE 会写坏中文 → 封面退化成「与的/横断面」并冒出日期
  .con <- file(info, open = "wt", encoding = "UTF-8")
  writeLines(.info_lines, .con, useBytes = FALSE)
  close(.con)
  # 最小 content.json：由表图文件名驱动；数字在 build 前由 inspect dump 校验
  tabs <- list.files(file.path(sr, "Tables"), pattern = "\\.xlsx$", full.names = FALSE)
  figs <- character(0)
  pdf_dir <- file.path(sr, "Figures", "pdf")
  if (dir.exists(pdf_dir)) {
    figs <- list.files(pdf_dir, pattern = "\\.pdf$", full.names = FALSE)
  } else {
    figs <- list.files(file.path(sr, "Figures"), pattern = "\\.pdf$", full.names = FALSE)
  }
  .pick <- function(pats, pool) {
    for (p in pats) {
      hit <- pool[grepl(p, pool, ignore.case = TRUE)]
      if (length(hit)) return(hit[[1L]])
    }
    NA_character_
  }
  t1 <- .pick("^Table 1\\.", tabs)
  t2 <- .pick("^Table 2\\.", tabs)
  t3 <- .pick("^Table 3\\.", tabs)
  s1 <- .pick("^Table S1\\.", tabs)
  s2 <- .pick("^Table S2\\.", tabs)
  f1 <- .pick("^Figure 1\\.", figs)
  f2 <- .pick("^Figure 2\\.", figs)
  f3 <- .pick("^Figure 3\\.", figs)
  fs1 <- .pick("^Figure S1\\.", figs)
  fs2 <- .pick("^Figure S2\\.", figs)
  fs3 <- .pick("^Figure S3\\.", figs)
  m2txt <- paste(as.character(model2_covars %||% character(0)), collapse = ", ")
  m3txt <- paste(as.character(model3_covars %||% character(0)), collapse = ", ")
  n_txt <- if (is.finite(as.numeric(n_analytic)[1L])) format(as.integer(n_analytic)[1L], big.mark = ",") else "见 Table 1"
  chapters <- list(
    list(
      title = "研究背景与方法摘要",
      intro = list(
        sprintf("本研究基于 %s，评估累计 %s 与 k-means 轨迹类别和%s的关联。分析集 N=%s。", database, ix, outcome_lab, n_txt),
        sprintf("全文锁定 Model 2 = %s；Model 3 = %s。表、图、森林与 RCS 同源。非预测模型，亦非人工智能分析。",
                if (nzchar(m2txt)) m2txt else "（未调整）",
                if (nzchar(m3txt)) m3txt else "（未调整）")
      ),
      formula = as.list(if (length(formula_lines)) formula_lines else list(sprintf("%s（见 Methods_statistical_analysis.md）", ix)))
    )
  )
  sec <- function(title, table = NULL, figure = NULL, caption = "", annotation = "") {
    out <- list(title = title, caption = caption, annotation = annotation)
    if (!is.null(table) && !is.na(table)) out$table <- table
    if (!is.null(figure) && !is.na(figure)) out$figure <- figure
    out
  }
  body_secs <- list()
  if (!is.na(f1)) body_secs[[length(body_secs) + 1L]] <- sec("纳排流程", figure = f1, caption = "纳排流程图", annotation = sprintf("终步分析集 N=%s。", n_txt))
  if (!is.na(f2)) body_secs[[length(body_secs) + 1L]] <- sec("轨迹图", figure = f2, caption = sprintf("%s 轨迹类别", ix), annotation = "k-means 肘部与轨迹面板。")
  if (!is.na(t1)) body_secs[[length(body_secs) + 1L]] <- sec("基线特征", table = t1, caption = "基线特征", annotation = "按轨迹类别分层。")
  if (!is.na(t2)) body_secs[[length(body_secs) + 1L]] <- sec("Logistic 主表", table = t2, caption = "Logistic 关联", annotation = sprintf("Model2=%s；Model3=%s。", m2txt, m3txt))
  if (!is.na(f3)) body_secs[[length(body_secs) + 1L]] <- sec("RCS", figure = f3, caption = "限制性立方样条", annotation = "Overall | BMI<30 | Age≥60；调整集=Model 3。")
  if (!is.na(t3)) body_secs[[length(body_secs) + 1L]] <- sec("亚组", table = t3, caption = "亚组分析", annotation = "分层变量含 Gender 时仅作分层，不进入调整集（若 Model 已排除 Gender）。")
  chapters[[length(chapters) + 1L]] <- list(title = "主要结果", sections = body_secs)
  supp <- list()
  if (!is.na(s1)) supp[[length(supp) + 1L]] <- sec("Cox 主表", table = s1, caption = "Cox 关联", annotation = "调整集与 Table 2 一致。")
  if (!is.na(fs1)) supp[[length(supp) + 1L]] <- sec("Cox RCS", figure = fs1, caption = "Cox RCS", annotation = "与 Figure 3 同面板。")
  if (!is.na(fs2)) supp[[length(supp) + 1L]] <- sec("Cox 森林", figure = fs2, caption = "亚组森林（HR）", annotation = "Model 3；分层变量自身不进入该层。")
  if (!is.na(fs3)) supp[[length(supp) + 1L]] <- sec("Logistic 森林", figure = fs3, caption = "亚组森林（OR）", annotation = "与 Figure S2 同口径。")
  if (!is.na(s2)) supp[[length(supp) + 1L]] <- sec("Cox 亚组表", table = s2, caption = "Cox 亚组详表", annotation = "调整集同 Model 3。")
  if (length(supp)) chapters[[length(chapters) + 1L]] <- list(title = "补充分析", sections = supp)
  .db_abbr <- if (grepl("HRS", database, ignore.case = TRUE)) {
    list(缩写词 = "HRS", 对应英文 = "Health and Retirement Study", 对应中文 = "美国健康与退休研究", 单位 = "")
  } else if (grepl("ELSA", database, ignore.case = TRUE)) {
    list(缩写词 = "ELSA", 对应英文 = "English Longitudinal Study of Ageing", 对应中文 = "英国老龄化纵向研究", 单位 = "")
  } else {
    list(缩写词 = as.character(database)[1L], 对应英文 = as.character(database)[1L], 对应中文 = as.character(database)[1L], 单位 = "")
  }
  content <- list(
    exclude_figures = list(),
    abbreviations = list(
      .db_abbr,
      list(缩写词 = "OR", 对应英文 = "Odds Ratio", 对应中文 = "比值比", 单位 = ""),
      list(缩写词 = "HR", 对应英文 = "Hazard Ratio", 对应中文 = "风险比", 单位 = ""),
      list(缩写词 = "CI", 对应英文 = "Confidence Interval", 对应中文 = "置信区间", 单位 = ""),
      list(缩写词 = "RCS", 对应英文 = "Restricted Cubic Spline", 对应中文 = "限制性立方样条", 单位 = ""),
      list(缩写词 = "ABSI", 对应英文 = "A Body Shape Index", 对应中文 = "身体形态指数", 单位 = "")
    ),
    chapters = chapters
  )
  cj <- file.path(sr, "content.json")
  jsonlite::write_json(content, cj, auto_unbox = TRUE, pretty = TRUE)
  eng <- file.path(
    Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "."),
    ".cursor/skills/Aiya-NB004-midterm-report/engine/build_report.py"
  )
  if (!file.exists(eng)) {
    warning("midterm engine missing: ", eng)
    return(invisible(NULL))
  }
  # 文件名避免空格（system2/部分 shell 会拆参）；展示用连字符
  ix_fn <- gsub("[[:space:]]+", "-", ix)
  out_pdf <- file.path(
    sr,
    sprintf(
      "%s_%s_%s_中期分析结果.pdf",
      ix_fn,
      gsub("[[:space:]]+", "", outcome_lab),
      gsub("、", "-", methods_lab)
    )
  )
  # 交付根只留一份中期：先清旧 *中期*.pdf
  .old_mid <- list.files(sr, pattern = "\u4e2d\u671f", full.names = TRUE)
  if (length(.old_mid)) {
    unlink(.old_mid, force = TRUE)
  }
  py <- Sys.which("python3")
  if (!nzchar(py)) py <- Sys.which("python")
  # inspect / build：勿对每个参数 shQuote（引号会进 argv，导致 --project 找不到、封面退回默认「横断面」且写出日期）
  try(
    system2(py, c(eng, "--inspect", "--project", sr), stdout = TRUE, stderr = TRUE),
    silent = TRUE
  )
  st <- system2(
    py,
    c(eng, "--build", "--project", sr, "--content", cj, "--out", out_pdf),
    stdout = TRUE, stderr = TRUE
  )
  ok <- file.exists(out_pdf)
  if (!ok) warning("midterm build failed: ", paste(utils::tail(st, 40), collapse = "\n"))
  # 再建后兜底：只保留本次 out_pdf
  .left_mid <- setdiff(list.files(sr, pattern = "\u4e2d\u671f", full.names = TRUE), out_pdf)
  if (length(.left_mid)) unlink(.left_mid, force = TRUE)
  # prune：移走 content/dump/项目信息
  if (exists("pub_prune_delivery_root", mode = "function")) {
    try(pub_prune_delivery_root(sr, keep_raster = FALSE), silent = TRUE)
  }
  invisible(if (ok) normalizePath(out_pdf, winslash = "/", mustWork = FALSE) else NULL)
}
