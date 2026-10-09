# Leakage-safe association helpers for reference-paper prognosis replication.

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}

.reference_hash <- function(x) {
  path <- tempfile("reference_hash_", fileext = ".rds")
  on.exit(unlink(path), add = TRUE)
  saveRDS(x, path, version = 2)
  unname(tools::md5sum(path))
}

.reference_assert_columns <- function(data, columns) {
  missing <- setdiff(columns, names(data))
  if (length(missing)) {
    stop("Missing required columns: ", paste(missing, collapse = ", "), call. = FALSE)
  }
}

.reference_bt <- function(x) {
  if (!length(x)) return(character(0))
  paste0("`", gsub("`", "\\\\`", x), "`")
}

.reference_numeric <- function(x, label, positive = FALSE) {
  out <- suppressWarnings(as.numeric(as.character(x)))
  if (length(out) != length(x) || anyNA(out) || any(!is.finite(out))) {
    stop(label, " contains missing or non-numeric values.", call. = FALSE)
  }
  if (isTRUE(positive) && any(out <= 0)) {
    stop(label, " must be > 0.", call. = FALSE)
  }
  out
}

.reference_event01 <- function(x, cfg = NULL) {
  if (!exists("pipeline_outcome_as_01", mode = "function", inherits = TRUE)) {
    stop("pipeline_outcome_as_01() must be loaded.", call. = FALSE)
  }
  converter <- get("pipeline_outcome_as_01", mode = "function", inherits = TRUE)
  raw <- trimws(as.character(x))
  raw_levels <- unique(raw[!is.na(raw) & nzchar(raw)])
  labels <- if (!is.null(cfg) &&
      exists("pipeline_resolve_outcome_display_labels", mode = "function",
             inherits = TRUE)) {
    get(
      "pipeline_resolve_outcome_display_labels",
      mode = "function", inherits = TRUE
    )(cfg)
  } else {
    list(analysis = "1", reference = "0")
  }
  known <- unique(c(
    "0", "1", "Yes", "No",
    as.character(labels$analysis), as.character(labels$reference)
  ))
  unknown <- setdiff(raw_levels, known)
  if (length(unknown)) {
    stop("Unknown event label(s): ", paste(unknown, collapse = ", "), call. = FALSE)
  }
  out <- converter(x, cfg = cfg)
  if (length(out) != length(x) || anyNA(out) || any(!out %in% c(0, 1))) {
    stop("Event could not be converted to complete 0/1 values.", call. = FALSE)
  }
  if (length(raw_levels) >= 2L && length(unique(out)) < 2L) {
    stop("Two event levels mapped to a single state.", call. = FALSE)
  }
  as.integer(out)
}

.reference_authority_path_ok <- function(path) {
  grepl(
    "/checkpoints/by_index/[^/]+/MIMIC_IV/[^/]+[.]rds$",
    path, perl = TRUE
  )
}

.reference_authority_dir_ok <- function(path) {
  grepl("/checkpoints/by_index/[^/]+/MIMIC_IV$", path, perl = TRUE)
}

.reference_authority_norm_id <- function(x) {
  tolower(trimws(as.character(x)[[1L]]))
}

.reference_identity_is_mimic <- function(x) {
  x %in% c("mimic_iv", "mimic-iv", "mimic iv", "mimic", "mimiciv")
}

#' Database identity fields of a pipeline_save_checkpoint() payload.
#'
#' Real engine payloads carry NO split_role. Identity lives in
#' ctx$config$project$database (e.g. "MIMIC_IV"). ctx$config$dual_db$current_db
#' is a slot label ("nhanes"/"mimic"), NOT a database identity, so it is
#' deliberately not trusted here. ctx$config$project$current_db is also
#' accepted for ctx-style fixtures.
.reference_payload_database_identity <- function(payload) {
  cfg <- payload$ctx$config
  ids <- c(
    if (!is.null(cfg$project$database)) as.character(cfg$project$database),
    if (!is.null(cfg$project$current_db)) as.character(cfg$project$current_db)
  )
  Filter(function(v) length(v) == 1L && !is.na(v) && nzchar(v), ids)
}

.reference_payload_train <- function(payload) {
  payload$train %||% payload$ctx$data$train
}

.reference_payload_authority_ok <- function(payload) {
  train <- .reference_payload_train(payload)
  if (!is.data.frame(train) || !nrow(train)) return(FALSE)
  ids <- .reference_payload_database_identity(payload)
  length(ids) > 0L && all(.reference_identity_is_mimic(
    vapply(ids, .reference_authority_norm_id, character(1))
  ))
}

#' Within an authority checkpoint directory, resolve the latest engine step
#' payload (highest stepNN prefix) that passes full authority validation.
#' Callers should prefer passing an explicit file path; this exists for
#' per-DB checkpoint dirs where every step >= train_validation re-saves the
#' same train frame.
.reference_select_authority_in_dir <- function(dir_path) {
  files <- sort(list.files(dir_path, pattern = "[.]rds$", full.names = TRUE))
  if (!length(files)) {
    stop("Authority checkpoint directory contains no .rds files.", call. = FALSE)
  }
  step_rank <- suppressWarnings(
    as.integer(sub("^step(\\d+)_.*$", "\\1", basename(files)))
  )
  step_rank[is.na(step_rank)] <- 0L
  files <- files[order(step_rank, basename(files), decreasing = TRUE)]
  for (f in files) {
    payload <- tryCatch(readRDS(f), error = function(e) NULL)
    if (is.null(payload)) next
    if (.reference_payload_authority_ok(payload)) return(f)
  }
  stop(
    "No checkpoint under the authority directory carries a verified MIMIC ",
    "database identity and non-empty ctx$data$train. Pass the authority ",
    "checkpoint file path explicitly.",
    call. = FALSE
  )
}

.reference_read_authority <- function(path) {
  if (is.null(path) || !length(path) || !nzchar(as.character(path)[1L])) {
    stop("An authority checkpoint path is required.", call. = FALSE)
  }
  path <- normalizePath(as.character(path)[1L], winslash = "/", mustWork = FALSE)
  if (dir.exists(path)) {
    if (!.reference_authority_dir_ok(path)) {
      stop(
        "Authority checkpoint must be under checkpoints/by_index/<combo>/MIMIC_IV.",
        call. = FALSE
      )
    }
    path <- normalizePath(
      .reference_select_authority_in_dir(path), winslash = "/", mustWork = FALSE
    )
  }
  if (!file.exists(path) || !.reference_authority_path_ok(path)) {
    stop(
      "Authority checkpoint must be under checkpoints/by_index/<combo>/MIMIC_IV.",
      call. = FALSE
    )
  }
  payload <- readRDS(path)
  # split_role is validated when present, but a self-declared split_role is
  # never sufficient on its own: real engine payloads written by
  # pipeline_save_checkpoint carry no split_role at all.
  split_role <- tolower(trimws(as.character(
    payload$split_role %||%
      payload$ctx$results$split_role %||%
      payload$meta$split_role %||%
      ""
  )[1L]))
  if (nzchar(split_role) && !identical(split_role, "train")) {
    stop("Authority checkpoint payload split_role must be train.", call. = FALSE)
  }
  ids <- vapply(
    .reference_payload_database_identity(payload),
    .reference_authority_norm_id, character(1)
  )
  if (!length(ids)) {
    stop(
      "Authority checkpoint payload lacks a MIMIC database identity ",
      "(ctx$config$project$database). Directory naming and any self-declared ",
      "split_role alone are not trusted.",
      call. = FALSE
    )
  }
  if (!all(.reference_identity_is_mimic(ids))) {
    stop(
      "Authority checkpoint database identity mismatch: expected MIMIC_IV, got ",
      paste(unique(ids), collapse = ", "), ".",
      call. = FALSE
    )
  }
  train <- .reference_payload_train(payload)
  if (!is.data.frame(train) || !nrow(train)) {
    stop(
      "Authority checkpoint does not contain a non-empty ctx$data$train.",
      call. = FALSE
    )
  }
  list(
    checkpoint_path = path,
    checkpoint_md5 = unname(tools::md5sum(path)),
    data_hash = .reference_hash(train),
    train = train,
    split_role = "train"
  )
}

#' Bind development data to an authoritative MIMIC train checkpoint.
reference_trusted_development <- function(
  data, checkpoint_path = NULL, ctx = NULL
) {
  if (is.null(checkpoint_path) && !is.null(ctx)) {
    checkpoint_path <- ctx$results$authority_checkpoint_path %||%
      ctx$authority_checkpoint_path %||%
      ctx$config$authority_checkpoint_path
  }
  authority <- .reference_read_authority(checkpoint_path)
  data_hash <- .reference_hash(data)
  if (!identical(data_hash, authority$data_hash)) {
    stop("Current train data hash differs from authority checkpoint train hash.",
         call. = FALSE)
  }
  structure(
    authority[c("checkpoint_path", "checkpoint_md5", "data_hash", "split_role")],
    class = "reference_development_provenance"
  )
}

.reference_validate_provenance <- function(provenance, data = NULL) {
  if (!inherits(provenance, "reference_development_provenance")) {
    stop("Authoritative checkpoint provenance is required.", call. = FALSE)
  }
  authority <- .reference_read_authority(provenance$checkpoint_path)
  if (!identical(provenance$checkpoint_md5, authority$checkpoint_md5)) {
    stop("Authority checkpoint MD5 changed.", call. = FALSE)
  }
  if (!identical(provenance$data_hash, authority$data_hash)) {
    stop("Authority checkpoint train hash changed.", call. = FALSE)
  }
  if (!is.null(data) && !identical(.reference_hash(data), authority$data_hash)) {
    stop("Current train data hash differs from authority checkpoint.", call. = FALSE)
  }
  authority
}

.reference_sign_lock <- function(spec, kind, class_name, provenance) {
  authority <- .reference_validate_provenance(provenance)
  spec$lock_kind <- kind
  spec$authority_checkpoint_path <- authority$checkpoint_path
  spec$authority_checkpoint_md5 <- authority$checkpoint_md5
  spec$authority_data_hash <- authority$data_hash
  structure(spec, class = class_name)
}

.reference_validate_lock <- function(spec, kind, class_name) {
  if (!inherits(spec, class_name) || !identical(spec$lock_kind, kind)) {
    stop("A valid locked specification is required.", call. = FALSE)
  }
  authority <- .reference_read_authority(spec$authority_checkpoint_path)
  if (!identical(spec$authority_checkpoint_md5, authority$checkpoint_md5)) {
    stop("Authority checkpoint MD5 changed after locking.", call. = FALSE)
  }
  if (!identical(spec$authority_data_hash, authority$data_hash)) {
    stop("Authority checkpoint train hash changed after locking.", call. = FALSE)
  }
  authority
}

#' Map two frozen upper-tertile cutpoints to the four joint groups.
reference_joint_tertile_groups <- function(a, b, cut_a, cut_b) {
  if (length(a) != length(b)) stop("a and b must have equal length.", call. = FALSE)
  a <- suppressWarnings(as.numeric(as.character(a)))
  b <- suppressWarnings(as.numeric(as.character(b)))
  cut_a <- suppressWarnings(as.numeric(as.character(cut_a))[1L])
  cut_b <- suppressWarnings(as.numeric(as.character(cut_b))[1L])
  if (!is.finite(cut_a) || !is.finite(cut_b)) {
    stop("cut_a and cut_b must be finite frozen cutpoints.", call. = FALSE)
  }
  high_a <- !is.na(a) & a > cut_a
  high_b <- !is.na(b) & b > cut_b
  out <- rep(NA_character_, length(a))
  complete <- !is.na(a) & !is.na(b)
  out[complete & !high_a & !high_b] <- "Group1"
  out[complete & high_a & !high_b] <- "Group2"
  out[complete & !high_a & high_b] <- "Group3"
  out[complete & high_a & high_b] <- "Group4"
  factor(out, levels = paste0("Group", 1:4))
}

#' Estimate type-7 upper-tertile cutpoints on trusted MIMIC train only.
reference_lock_tertile_cutpoints <- function(
  development, a, b, provenance = NULL
) {
  .reference_validate_provenance(provenance, development)
  .reference_assert_columns(development, c(a, b))
  av <- .reference_numeric(development[[a]], a)
  bv <- .reference_numeric(development[[b]], b)
  qa <- unname(stats::quantile(av, probs = 2 / 3, type = 7))
  qb <- unname(stats::quantile(bv, probs = 2 / 3, type = 7))
  spec <- list(
    source = "MIMIC development/train",
    development_hash = .reference_hash(development),
    variables = c(a = a, b = b),
    cutpoints = c(a = qa, b = qb),
    probability = 2 / 3,
    quantile_type = 7L
  )
  .reference_sign_lock(
    spec, "tertile_lock", "reference_tertile_lock", provenance
  )
}

#' Apply a development-frozen joint-tertile specification.
reference_apply_joint_tertiles <- function(data, locked_spec) {
  authority <- .reference_validate_lock(
    locked_spec, "tertile_lock", "reference_tertile_lock"
  )
  vars <- unname(locked_spec$variables)
  .reference_assert_columns(data, vars)
  .reference_assert_columns(authority$train, vars)
  expected <- c(
    a = unname(stats::quantile(
      .reference_numeric(authority$train[[vars[[1L]]]], vars[[1L]]),
      2 / 3, type = 7
    )),
    b = unname(stats::quantile(
      .reference_numeric(authority$train[[vars[[2L]]]], vars[[2L]]),
      2 / 3, type = 7
    ))
  )
  if (!identical(locked_spec$quantile_type, 7L) ||
      !isTRUE(all.equal(locked_spec$cutpoints, expected, tolerance = 0))) {
    stop("Tertile lock contents were tampered with.", call. = FALSE)
  }
  list(
    group = reference_joint_tertile_groups(
      data[[vars[[1L]]]], data[[vars[[2L]]]],
      locked_spec$cutpoints[["a"]], locked_spec$cutpoints[["b"]]
    ),
    cutpoints = locked_spec$cutpoints,
    source = locked_spec$source
  )
}

.reference_assoc_models <- function(covariates, data, indices, stratum_vars) {
  m_age_sex <- intersect(c("Age", "Gender", "Sex"), names(data))
  sex_hit <- intersect(c("Gender", "Sex"), names(data))
  if (!("Age" %in% names(data)) || !length(sex_hit)) {
    stop("Model2 (Age+Sex) requires both Age and Gender/Sex.", call. = FALSE)
  }
  m_age_sex <- unique(c("Age", sex_hit[[1L]]))
  hard_exclude <- unique(c(indices, "SOFA", stratum_vars))
  if (is.list(covariates) && !is.null(covariates$config) &&
      !is.null(covariates$results)) {
    if (!exists("ml_resolve_assoc_covariates", mode = "function", inherits = TRUE)) {
      stop("ml_resolve_assoc_covariates() must be loaded.", call. = FALSE)
    }
    ctx <- unserialize(serialize(covariates, NULL))
    current <- ctx$config$assoc_covariate %||% list()
    current$exclude_extra <- unique(c(current$exclude_extra, hard_exclude))
    current$model2_exclude <- unique(c(current$model2_exclude, hard_exclude))
    ctx$config$assoc_covariate <- current
    resolver <- get("ml_resolve_assoc_covariates", mode = "function", inherits = TRUE)
    resolved <- resolver(ctx, data_names = names(data))
    m_full <- unique(c(m_age_sex, resolved$M2, resolved$M3 %||% character(0)))
  } else {
    stop("covariates must be an ML association-rule ctx.", call. = FALSE)
  }
  m_full <- setdiff(m_full, hard_exclude)
  use_lit <- FALSE
  if (exists("ml_assoc_is_literature_m123", mode = "function", inherits = TRUE)) {
    use_lit <- isTRUE(ml_assoc_is_literature_m123(covariates$config %||% list()))
  } else {
    use_lit <- identical(
      as.character((covariates$config$assoc_covariate %||% list())$scheme %||% "")[1L],
      "literature_m123"
    )
  }
  if (isTRUE(use_lit) || identical(resolved$scheme %||% "", "literature_m123")) {
    # 原文 Table2：Model1 未调整；Model2 Age+Sex；Model3 临床∩UV∩VIF
    list(
      "Model1" = character(0),
      "Model2" = m_age_sex,
      "Model3" = unique(c(m_age_sex, setdiff(m_full, m_age_sex)))
    )
  } else {
    list(
      "Unadjusted" = character(0),
      "Model1 Age+Gender" = m_age_sex,
      "Model2" = unique(c(m_age_sex, m_full))
    )
  }
}

.reference_cox_formula <- function(time, event, predictor, covariates) {
  rhs <- c(.reference_bt(predictor), .reference_bt(covariates))
  stats::as.formula(sprintf(
    "survival::Surv(%s, %s) ~ %s",
    .reference_bt(time), .reference_bt(event), paste(rhs, collapse = " + ")
  ))
}

.reference_term_coefficients <- function(fit, predictor) {
  tt <- stats::terms(fit)
  labels <- attr(tt, "term.labels")
  normalized <- gsub("^`|`$", "", labels)
  term_position <- match(predictor, normalized)
  if (is.na(term_position)) {
    stop("Predictor is absent from fitted model terms: ", predictor, call. = FALSE)
  }
  # 用 model.matrix 的逐列 assign 属性定位 term 对应的列（因子/哑变量/spline
  # 基会展开为多列），再映射回 coef 名。coxph 的 fit$assign 列表名是 term 名
  # 而非 coef 名，不能直接 intersect。
  mm <- stats::model.matrix(fit)
  col_assign <- attr(mm, "assign")
  if (is.null(col_assign)) {
    stop("model.matrix lacks an 'assign' attribute; cannot map term to coefficients.",
         call. = FALSE)
  }
  hits <- colnames(mm)[!is.na(col_assign) & col_assign == term_position]
  intersect(hits, names(stats::coef(fit)))
}

#' Fit unadjusted, Age+Gender, and association-rule Model2 Cox models.
reference_fit_cox_suite <- function(
  data, time, event, indices, stratum, covariates
) {
  if (!requireNamespace("survival", quietly = TRUE)) {
    stop("Package 'survival' is required.", call. = FALSE)
  }
  required <- unique(c(time, event, indices, stratum, "Age", "Gender"))
  .reference_assert_columns(data, required)
  data[[time]] <- .reference_numeric(data[[time]], time, positive = TRUE)
  data[[event]] <- .reference_event01(data[[event]], cfg = covariates$config)
  models <- .reference_assoc_models(covariates, data, indices, stratum)
  values <- as.character(data[[stratum]])
  strata <- stats::setNames(
    lapply(unique(values[!is.na(values)]), function(x) values == x),
    unique(values[!is.na(values)])
  )
  rows <- list()
  k <- 0L
  for (stratum_name in names(strata)) {
    subset <- data[strata[[stratum_name]], , drop = FALSE]
    for (index in indices) {
      for (model_name in names(models)) {
        vars <- models[[model_name]]
        fit <- survival::coxph(
          .reference_cox_formula(time, event, index, vars),
          data = subset, x = TRUE, model = TRUE
        )
        hits <- .reference_term_coefficients(fit, index)
        if (!length(hits)) {
          stop("No exact Cox coefficient was produced for index: ", index, call. = FALSE)
        }
        ci <- stats::confint(fit)
        for (term in hits) {
          k <- k + 1L
          z <- summary(fit)$coefficients[term, "z"]
          rows[[k]] <- data.frame(
            stratum = stratum_name, index = index, term = term,
            model = model_name,
            hr = unname(exp(stats::coef(fit)[term])),
            conf_low = unname(exp(ci[term, 1L])),
            conf_high = unname(exp(ci[term, 2L])),
            p = unname(2 * stats::pnorm(-abs(z))),
            n = fit$n, events = fit$nevent,
            stringsAsFactors = FALSE
          )
          rows[[k]]$covariates <- I(list(vars))
        }
      }
    }
  }
  out <- do.call(rbind, rows)
  out$model <- factor(out$model, levels = names(models))
  out <- out[order(out$stratum, out$index, out$model), , drop = FALSE]
  out$model <- as.character(out$model)
  rownames(out) <- NULL
  out
}

#' Lock spline basis, plotting range, and common reference on MIMIC train.
reference_lock_grouped_rcs <- function(
  development, index, provenance = NULL, spline_df = 3L
) {
  .reference_validate_provenance(provenance, development)
  .reference_assert_columns(development, index)
  x <- .reference_numeric(development[[index]], index)
  spline_df <- as.integer(spline_df)[1L]
  if (!is.finite(spline_df) || spline_df < 3L) stop("spline_df must be >=3.", call. = FALSE)
  boundary <- unname(stats::quantile(x, c(0.05, 0.95), type = 7))
  knot_probs <- seq(0, 1, length.out = spline_df + 1L)[-c(1L, spline_df + 1L)]
  knots <- unique(unname(stats::quantile(x, knot_probs, type = 7)))
  knots <- knots[knots > boundary[[1L]] & knots < boundary[[2L]]]
  if (!length(knots) || boundary[[1L]] >= boundary[[2L]]) {
    stop("Development exposure has insufficient variation for RCS.", call. = FALSE)
  }
  spec <- list(
    source = "MIMIC development/train",
    development_hash = .reference_hash(development),
    index = index,
    spline_df = spline_df,
    knots = knots,
    boundary_knots = boundary,
    reference_value = unname(stats::median(x)),
    grid_range = boundary
  )
  .reference_sign_lock(spec, "rcs_lock", "reference_rcs_lock", provenance)
}

.reference_lrt_p <- function(smaller, larger) {
  tab <- stats::anova(smaller, larger, test = "LRT")
  p_col <- grep("^P\\(|Pr\\(", names(tab), value = TRUE)
  if (!length(p_col)) return(NA_real_)
  as.numeric(tab[nrow(tab), p_col[[1L]]])
}

.reference_adjustment_row <- function(data, covariates) {
  out <- data[1L, covariates, drop = FALSE]
  for (v in covariates) {
    x <- data[[v]]
    if (is.numeric(x) || is.integer(x)) {
      out[[v]] <- stats::median(x)
    } else if (is.factor(x)) {
      out[[v]] <- factor(levels(x)[1L], levels = levels(x))
    } else {
      out[[v]] <- names(sort(table(x), decreasing = TRUE))[[1L]]
    }
  }
  out
}

.reference_common_rcs_covariates <- function(
  data, strata, stratum, core, covariates
) {
  kept <- dropped <- character(0)
  reasons <- character(0)
  for (candidate in covariates) {
    trial <- c(kept, candidate)
    estimable <- vapply(strata, function(label) {
      d <- data[as.character(data[[stratum]]) == label, c(core, trial), drop = FALSE]
      d <- d[stats::complete.cases(d), , drop = FALSE]
      if (nrow(d) < 5L || length(unique(d[[core[[2L]]]])) < 2L) return(FALSE)
      mm <- stats::model.matrix(
        stats::reformulate(trial), data = d
      )
      qr(mm)$rank == ncol(mm)
    }, logical(1))
    if (all(estimable)) {
      kept <- trial
    } else {
      dropped <- c(dropped, candidate)
      reasons <- c(reasons, "single-level, rank-deficient, or sparse in >=1 stratum")
    }
  }
  list(
    kept = kept,
    dropped = dropped,
    table = data.frame(
      covariate = c(kept, dropped),
      status = c(rep("kept", length(kept)), rep("dropped", length(dropped))),
      reason = c(rep("", length(kept)), reasons),
      stringsAsFactors = FALSE
    )
  )
}

#' Apply a train-locked adjusted spline Cox analysis within each stratum.
reference_grouped_rcs <- function(
  data, time, event, index, stratum, covariates = c("Age", "Gender"),
  locked_spec, outcome_cfg = NULL, grid_n = 50L
) {
  if (!requireNamespace("survival", quietly = TRUE)) {
    stop("Package 'survival' is required.", call. = FALSE)
  }
  authority <- .reference_validate_lock(
    locked_spec, "rcs_lock", "reference_rcs_lock"
  )
  if (!identical(index, locked_spec$index)) stop("RCS lock index mismatch.", call. = FALSE)
  grid_n <- as.integer(grid_n)[1L]
  if (!is.finite(grid_n) || grid_n < 2L) stop("grid_n must be >=2.", call. = FALSE)
  needed <- unique(c(time, event, index, stratum, covariates))
  .reference_assert_columns(data, needed)
  data[[time]] <- .reference_numeric(data[[time]], time, positive = TRUE)
  data[[event]] <- .reference_event01(data[[event]], cfg = outcome_cfg)
  strata <- unique(as.character(data[[stratum]]))
  strata <- strata[!is.na(strata)]
  train_x <- .reference_numeric(authority$train[[index]], index)
  expected_boundary <- unname(stats::quantile(
    train_x, c(0.05, 0.95), type = 7
  ))
  knot_probs <- seq(
    0, 1, length.out = locked_spec$spline_df + 1L
  )[-c(1L, locked_spec$spline_df + 1L)]
  expected_knots <- unique(unname(stats::quantile(
    train_x, knot_probs, type = 7
  )))
  expected_knots <- expected_knots[
    expected_knots > expected_boundary[[1L]] &
      expected_knots < expected_boundary[[2L]]
  ]
  expected_reference <- unname(stats::median(train_x))
  if (!isTRUE(all.equal(locked_spec$knots, expected_knots, tolerance = 0)) ||
      !isTRUE(all.equal(
        locked_spec$boundary_knots, expected_boundary, tolerance = 0
      )) ||
      !identical(locked_spec$reference_value, expected_reference)) {
    stop("RCS lock contents were tampered with.", call. = FALSE)
  }
  audit <- .reference_common_rcs_covariates(
    data, strata, stratum, c(time, event, index), covariates
  )
  covariates <- audit$kept
  needed <- unique(c(time, event, index, stratum, covariates))
  summaries <- curves <- vector("list", length(strata))
  knots_text <- paste(format(locked_spec$knots, digits = 17), collapse = ",")
  boundary_text <- paste(format(locked_spec$boundary_knots, digits = 17), collapse = ",")
  spline_term <- sprintf(
    "splines::ns(%s, knots=c(%s), Boundary.knots=c(%s))",
    .reference_bt(index), knots_text, boundary_text
  )
  for (i in seq_along(strata)) {
    label <- strata[[i]]
    d <- data[as.character(data[[stratum]]) == label, needed, drop = FALSE]
    d <- d[stats::complete.cases(d), , drop = FALSE]
    if (!nrow(d)) stop("No complete cases in stratum: ", label, call. = FALSE)
    surv_lhs <- sprintf(
      "survival::Surv(%s, %s)", .reference_bt(time), .reference_bt(event)
    )
    adjust <- if (length(covariates)) {
      paste(.reference_bt(covariates), collapse = " + ")
    } else {
      "1"
    }
    null_formula <- stats::as.formula(paste(surv_lhs, "~", adjust))
    linear_formula <- stats::as.formula(paste(
      surv_lhs, "~", paste(c(.reference_bt(index), adjust), collapse = " + ")
    ))
    spline_formula <- stats::as.formula(paste(
      surv_lhs, "~", paste(c(spline_term, adjust), collapse = " + ")
    ))
    fit0 <- survival::coxph(null_formula, data = d, x = TRUE)
    fit1 <- survival::coxph(linear_formula, data = d, x = TRUE)
    fit_spline <- survival::coxph(spline_formula, data = d, x = TRUE)
    summaries[[i]] <- data.frame(
      stratum = label,
      n_null = fit0$n, n_linear = fit1$n, n_spline = fit_spline$n,
      events = fit_spline$nevent,
      p_overall = .reference_lrt_p(fit0, fit_spline),
      p_nonlinear = .reference_lrt_p(fit1, fit_spline),
      adjusted_for = paste(covariates, collapse = "+"),
      stringsAsFactors = FALSE
    )
    grid <- seq(
      locked_spec$grid_range[[1L]], locked_spec$grid_range[[2L]],
      length.out = grid_n
    )
    grid <- sort(unique(c(grid, locked_spec$reference_value)))
    base <- .reference_adjustment_row(d, covariates)
    newdata <- base[rep(1L, length(grid)), , drop = FALSE]
    newdata[[index]] <- grid
    refdata <- base
    refdata[[index]] <- locked_spec$reference_value
    terms_no_response <- stats::delete.response(stats::terms(fit_spline))
    mm <- stats::model.matrix(terms_no_response, newdata)
    mm_ref <- stats::model.matrix(terms_no_response, refdata)
    beta <- stats::coef(fit_spline)
    mm <- mm[, names(beta), drop = FALSE]
    mm_ref <- mm_ref[, names(beta), drop = FALSE]
    contrast <- sweep(mm, 2L, mm_ref[1L, ], FUN = "-")
    log_hr <- drop(contrast %*% beta)
    se <- sqrt(pmax(0, rowSums((contrast %*% stats::vcov(fit_spline)) * contrast)))
    at_reference <- grid == locked_spec$reference_value
    log_hr[at_reference] <- 0
    se[at_reference] <- 0
    curves[[i]] <- data.frame(
      stratum = label, value = grid,
      reference = locked_spec$reference_value,
      hr = exp(log_hr),
      conf_low = exp(log_hr - 1.96 * se),
      conf_high = exp(log_hr + 1.96 * se),
      stringsAsFactors = FALSE
    )
  }
  list(
    summary = do.call(rbind, summaries),
    curve = do.call(rbind, curves),
    locked_spec = locked_spec,
    covariate_audit = list(
      kept = audit$kept, dropped = audit$dropped, details = audit$table
    )
  )
}
