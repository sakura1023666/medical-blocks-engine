# Helpers for disease-severity stratified ML reruns.

.ml_stratified_or <- function(x, y) {
  if (is.null(x) || !length(x)) y else x
}

#' SOFA 分层规格（默认三层 0-4 / 5-10 / >10，对应原文 NGR/Pre-DM/DM 三层结构）。
#' breaks 为递增整数切点向量，产生 length(breaks)+1 层；每层区间 (lower, upper]。
ml_stratum_spec_sofa <- function(breaks = c(4, 10)) {
  breaks <- suppressWarnings(as.integer(as.numeric(breaks)))
  if (!length(breaks) || anyNA(breaks) || any(diff(breaks) <= 0L)) {
    stop("SOFA breaks must be a non-empty increasing integer vector.", call. = FALSE)
  }
  edges <- c(-Inf, breaks, Inf)
  strata <- list()
  for (i in seq_len(length(edges) - 1L)) {
    lo <- edges[[i]]
    hi <- edges[[i + 1L]]
    if (!is.finite(lo) && !is.finite(hi)) {
      stop("Degenerate SOFA stratification (no breaks).", call. = FALSE)
    }
    if (!is.finite(lo)) {
      key <- paste0("sofa_0_", hi)
      label <- paste0("SOFA 0\u2013", hi)
    } else if (!is.finite(hi)) {
      key <- paste0("sofa_", lo + 1L, "plus")
      label <- paste0("SOFA \u2265", lo + 1L)
    } else {
      key <- paste0("sofa_", lo + 1L, "_", hi)
      label <- paste0("SOFA ", lo + 1L, "\u2013", hi)
    }
    strata[[key]] <- list(
      name = key, label = label, variable = "SOFA",
      lower = lo, upper = hi, operator = "range"
    )
  }
  list(
    variable = "SOFA",
    breaks = breaks,
    strata = strata
  )
}

#' 单一成员判定入口：range 用 (lower, upper]；兼容旧 cutoff/operator 契约与
#' "missing" 层。所有分层谓词（clone/资产/SHAP/关联图）必须走本函数。
ml_stratum_member <- function(value, stratum) {
  v <- suppressWarnings(as.numeric(as.character(value)))
  if (identical(stratum$operator, "missing")) return(is.na(v))
  has_bounds <- !is.null(stratum$lower) || !is.null(stratum$upper)
  if (has_bounds) {
    # jsonlite 把 Inf 存成字符串 "Inf"、有限边界存成数值；统一 as.numeric 后，
    # 有限边界照常生效、Inf 边界 is.finite()=FALSE 自然跳过（开区间语义）。
    lo <- if (is.null(stratum$lower)) -Inf else suppressWarnings(as.numeric(stratum$lower)[1L])
    hi <- if (is.null(stratum$upper)) Inf else suppressWarnings(as.numeric(stratum$upper)[1L])
    ok <- !is.na(v)
    if (is.finite(lo)) ok <- ok & v > lo
    if (is.finite(hi)) ok <- ok & v <= hi
    return(ok)
  }
  cut <- suppressWarnings(as.numeric(stratum$cutoff)[1L])
  if (!is.finite(cut)) {
    stop("Stratum definition has neither bounds nor a finite cutoff.", call. = FALSE)
  }
  if (identical(stratum$operator, "<=")) return(!is.na(v) & v <= cut)
  if (identical(stratum$operator, ">")) return(!is.na(v) & v > cut)
  stop("Unsupported stratum operator: ", stratum$operator, call. = FALSE)
}

.ml_stratified_column <- function(data, wanted) {
  if (!is.data.frame(data)) return(NULL)
  hit <- names(data)[tolower(names(data)) == tolower(as.character(wanted)[1L])]
  if (!length(hit)) NULL else hit[[1L]]
}

.ml_stratified_id_info <- function(ctx, reference) {
  configured <- as.character(.ml_stratified_or(
    .ml_stratified_or(ctx$config$data$id_column, ctx$config$project$id_column),
    character(0)
  ))
  configured <- configured[nzchar(configured)]
  if (length(configured)) {
    column <- .ml_stratified_column(reference, configured[[1L]])
    if (is.null(column)) {
      stop(
        "Configured patient ID column is absent: ", configured[[1L]],
        call. = FALSE
      )
    }
    values <- as.character(reference[[column]])
    if (!length(values) || any(is.na(values) | !nzchar(values)) ||
        anyDuplicated(values)) {
      stop(
        "Configured patient ID must be non-missing and unique: ", column,
        call. = FALSE
      )
    }
    return(list(
      type = "column", column = column, values = values, configured = TRUE
    ))
  }
  candidates <- unique(c(
    "patient_id", "patientunitstayid", "stay_id", "subject_id",
    "hadm_id", "encounter_id", "ID", "id"
  ))
  for (candidate in candidates[nzchar(candidates)]) {
    column <- .ml_stratified_column(reference, candidate)
    if (is.null(column)) next
    values <- as.character(reference[[column]])
    if (length(values) && all(!is.na(values) & nzchar(values)) &&
        !anyDuplicated(values)) {
      return(list(
        type = "column", column = column, values = values, configured = FALSE
      ))
    }
  }
  rn <- rownames(reference)
  default_rn <- identical(rn, as.character(seq_len(nrow(reference))))
  if (isTRUE(default_rn)) {
    stop(
      "Default row names 1:n are not stable patient identifiers.",
      call. = FALSE
    )
  }
  if (is.null(rn) || anyNA(rn) || any(!nzchar(rn)) || anyDuplicated(rn)) {
    stop("No stable patient ID column or unique row names are available.", call. = FALSE)
  }
  list(type = "rownames", column = NULL, values = rn, configured = FALSE)
}

.ml_stratified_keys <- function(data, id_info) {
  if (!is.data.frame(data)) return(character(0))
  if (identical(id_info$type, "column")) {
    column <- .ml_stratified_column(data, id_info$column)
    if (is.null(column)) {
      stop("Patient ID column is not shared across analysis slots.", call. = FALSE)
    }
    return(as.character(data[[column]]))
  }
  rownames(data)
}

.ml_stratified_keep <- function(data, selected_ids, id_info) {
  if (!is.data.frame(data)) return(data)
  keys <- .ml_stratified_keys(data, id_info)
  if (isTRUE(id_info$configured) &&
      (any(is.na(keys) | !nzchar(keys)) || anyDuplicated(keys))) {
    stop(
      "Configured patient ID must be non-missing and unique in every patient slot.",
      call. = FALSE
    )
  }
  data[keys %in% selected_ids, , drop = FALSE]
}

.ml_stratified_patient_slots <- function(ctx = NULL) {
  built_in <- c(
    "raw", "mapped", "cleaned", "analysis", "analytic", "analysis_data",
    "imputed", "train", "test", "validation", "internal", "val", "cohort",
    "patient_data", "patients"
  )
  registered <- as.character(
    .ml_stratified_or(
      ctx$config$ml_stratified_ctx$patient_slots,
      character(0)
    )
  )
  unique(tolower(c(built_in, registered[nzchar(registered)])))
}

.ml_stratified_stable_rownames <- function(data) {
  rn <- rownames(data)
  if (is.null(rn)) {
    return(list(ok = FALSE, reason = "row names are absent", values = character(0)))
  }
  if (identical(rn, as.character(seq_len(nrow(data))))) {
    return(list(
      ok = FALSE, reason = "row names are default 1:n", values = character(0)
    ))
  }
  if (anyNA(rn) || any(!nzchar(rn))) {
    return(list(
      ok = FALSE, reason = "row names contain missing/empty values",
      values = character(0)
    ))
  }
  if (anyDuplicated(rn)) {
    return(list(
      ok = FALSE, reason = "row names are duplicated", values = character(0)
    ))
  }
  list(ok = TRUE, reason = "", values = rn)
}

.ml_stratified_slot_mapping <- function(
  data,
  slot_name,
  id_info,
  patient_slots,
  reference_rownames
) {
  known_slot <- tolower(as.character(slot_name)[1L]) %in% patient_slots
  if (!known_slot) return(NULL)
  if (!is.data.frame(data)) {
    stop(
      "Patient slot '", slot_name,
      "' cannot be mapped: value is not a data.frame.",
      call. = FALSE
    )
  }
  if (identical(id_info$type, "column")) {
    id_column <- .ml_stratified_column(data, id_info$column)
    if (!is.null(id_column)) {
      keys <- as.character(data[[id_column]])
      if (any(is.na(keys) | !nzchar(keys))) {
        stop(
          "Patient slot '", slot_name,
          "' cannot be mapped: selected ID contains missing/empty values.",
          call. = FALSE
        )
      }
      if (anyDuplicated(keys)) {
        stop(
          "Patient slot '", slot_name,
          "' cannot be mapped: selected ID is duplicated.",
          call. = FALSE
        )
      }
      return("id")
    }
    if (isTRUE(id_info$configured)) {
      stop(
        "Configured patient ID is absent from patient slot '", slot_name,
        "': selected ID column '", id_info$column, "' is missing.",
        call. = FALSE
      )
    }
    slot_rn <- .ml_stratified_stable_rownames(data)
    if (!isTRUE(slot_rn$ok)) {
      stop(
        "Patient slot '", slot_name,
        "' cannot be mapped: selected ID is absent and ", slot_rn$reason, ".",
        call. = FALSE
      )
    }
    if (!length(reference_rownames)) {
      stop(
        "Patient slot '", slot_name,
        "' cannot be mapped: selected ID is absent and reference row names are unstable.",
        call. = FALSE
      )
    }
    if (!any(slot_rn$values %in% reference_rownames)) {
      stop(
        "Patient slot '", slot_name,
        "' cannot be mapped: selected ID is absent and row names have no overlap with the reference layer.",
        call. = FALSE
      )
    }
    return("rownames")
  }
  slot_rn <- .ml_stratified_stable_rownames(data)
  if (!isTRUE(slot_rn$ok)) {
    stop(
      "Patient slot '", slot_name, "' cannot be mapped: ", slot_rn$reason, ".",
      call. = FALSE
    )
  }
  if (!any(slot_rn$values %in% id_info$values)) {
    stop(
      "Patient slot '", slot_name,
      "' cannot be mapped: row names have no overlap with the reference layer.",
      call. = FALSE
    )
  }
  "rownames"
}

.ml_stratified_mask <- function(data, stratum) {
  variable <- .ml_stratified_column(data, stratum$variable)
  if (is.null(variable)) {
    stop("Stratification variable is absent: ", stratum$variable, call. = FALSE)
  }
  ml_stratum_member(data[[variable]], stratum)
}

.ml_stratified_reference <- function(ctx) {
  slots <- ctx$data
  reference <- .ml_stratified_or(
    slots$imputed,
    .ml_stratified_or(slots$cleaned, .ml_stratified_or(slots$mapped, slots$train))
  )
  if (!is.data.frame(reference) || !nrow(reference)) {
    stop("No non-empty analysis data are available for stratification.", call. = FALSE)
  }
  reference
}

.ml_stratified_clear_stale <- function(ctx) {
  if (is.list(ctx$results) && length(ctx$results)) {
    result_names <- names(ctx$results)
    result_keys <- tolower(result_names)
    stale_exact <- tolower(c(
      "selected_features", "Model1Factors", "Model2Factors", "Model3Factors",
      "pause_point", "univar_features", "tb1_univar_features",
      "tb_screen_univar_features", "vif_screen_pass", "vif_screen_table"
    ))
    stale_prefixes <- c(
      "feature_selection_", "selected_features_", "boruta_", "lvq_",
      "lasso_", "vif_", "ml_feature_", "ml_model", "ml_best_",
      "ml_eval_", "ml_pred", "cox_", "logistic_", "rcs_", "shap_",
      "performance_", "hyperparameter_", "predtrain_", "predtest_",
      "evalresult_"
    )
    stale <- result_keys %in% stale_exact |
      vapply(
        result_keys,
        function(key) any(startsWith(key, stale_prefixes)),
        logical(1)
      )
    ctx$results[stale] <- NULL
    queue_names <- names(ctx$results)[grepl("queue$", names(ctx$results), ignore.case = TRUE)]
    for (key in queue_names) ctx$results[[key]] <- list()
    for (key in c("figure_queue", "table_queue")) {
      ctx$results[[key]] <- list()
    }
  }
  if (!is.null(ctx$models)) ctx$models <- list()
  if (!is.null(ctx$queues)) ctx$queues <- list()
  for (queue_env_name in c(".table_queue_env", ".figure_queue_env")) {
    if (exists(queue_env_name, mode = "environment", inherits = TRUE)) {
      queue_env <- get(queue_env_name, mode = "environment", inherits = TRUE)
      queue_env$items <- list()
    }
  }
  if (exists("pub_reset_counters", mode = "function", inherits = TRUE)) {
    reset_counters <- get(
      "pub_reset_counters", mode = "function", inherits = TRUE
    )
    ctx <- reset_counters(ctx)
  } else {
    defaults <- list(
      main_table = 0L, main_figure = 1L,
      supp_table = 0L, supp_figure = 0L
    )
    ctx$log$pub_counters <- defaults
    if (exists(".pub_state", mode = "environment", inherits = TRUE)) {
      pub_state <- get(".pub_state", mode = "environment", inherits = TRUE)
      for (key in names(defaults)) pub_state[[key]] <- defaults[[key]]
    }
  }
  ctx
}

.ml_stratified_relocate_checkpoint_value <- function(value, staging_checkpoint) {
  if (!is.character(value) || !length(value)) return(value)
  if (length(value) > 1L) return(rep(staging_checkpoint, length(value)))
  extension <- tools::file_ext(value)
  if (nzchar(extension)) {
    file.path(staging_checkpoint, basename(value))
  } else {
    staging_checkpoint
  }
}

.ml_stratified_redirect_checkpoints <- function(x, staging_checkpoint) {
  if (!is.list(x) || is.object(x)) return(x)
  nms <- names(x)
  if (is.null(nms)) nms <- rep("", length(x))
  for (i in seq_along(x)) {
    key <- nms[[i]]
    value <- x[[i]]
    if (identical(tolower(key), "checkpoint") && is.list(value)) {
      value$enable <- FALSE
      value$dir <- staging_checkpoint
      for (path_key in intersect(
        names(value), c("path", "file", "base", "checkpoint_base", "checkpoint_dir")
      )) {
        value[[path_key]] <- .ml_stratified_relocate_checkpoint_value(
          value[[path_key]], staging_checkpoint
        )
      }
      value$resume_from <- NULL
      value$from <- NULL
      x[[i]] <- .ml_stratified_redirect_checkpoints(value, staging_checkpoint)
    } else if (
      is.character(value) &&
      (
        grepl(
          "(^checkpoint_(base|dir|path|file)$|(^|_)(ck)_(base|dir|path|file)$)",
          tolower(key),
          perl = TRUE
        ) ||
        any(grepl(
          "(^|[/\\\\])checkpoints[^/\\\\]*([/\\\\]|$)",
          value,
          ignore.case = TRUE,
          perl = TRUE
        ))
      )
    ) {
      x[[i]] <- .ml_stratified_relocate_checkpoint_value(
        value, staging_checkpoint
      )
    } else if (
      is.logical(value) &&
      identical(tolower(key), "persist_to_checkpoints")
    ) {
      x[[i]] <- FALSE
    } else if (is.list(value)) {
      x[[i]] <- .ml_stratified_redirect_checkpoints(value, staging_checkpoint)
    }
  }
  x
}

ml_clone_ctx_for_stratum <- function(parent_ctx, stratum, output_root) {
  if (!is.list(parent_ctx) || !is.list(stratum)) {
    stop("parent_ctx and stratum must be lists.", call. = FALSE)
  }
  child <- unserialize(serialize(parent_ctx, connection = NULL, xdr = FALSE))
  reference <- .ml_stratified_reference(child)
  id_info <- .ml_stratified_id_info(child, reference)
  stratum_mask <- .ml_stratified_mask(reference, stratum)
  selected_ids <- .ml_stratified_keys(reference, id_info)[stratum_mask]
  if (!length(selected_ids)) {
    stop("Empty stratum; no staging directories were created.", call. = FALSE)
  }
  reference_rn <- .ml_stratified_stable_rownames(reference)
  stable_reference_rownames <- if (isTRUE(reference_rn$ok)) {
    reference_rn$values
  } else {
    character(0)
  }
  selected_reference_rownames <- if (length(stable_reference_rownames)) {
    stable_reference_rownames[stratum_mask]
  } else {
    character(0)
  }

  patient_slots <- .ml_stratified_patient_slots(child)
  for (slot in names(child$data)) {
    mapping <- .ml_stratified_slot_mapping(
      child$data[[slot]], slot, id_info, patient_slots,
      stable_reference_rownames
    )
    if (identical(mapping, "id")) {
      child$data[[slot]] <- .ml_stratified_keep(
        child$data[[slot]], selected_ids, id_info
      )
    } else if (identical(mapping, "rownames")) {
      child$data[[slot]] <- child$data[[slot]][
        rownames(child$data[[slot]]) %in% selected_reference_rownames,
        ,
        drop = FALSE
      ]
    }
  }

  output_root <- normalizePath(
    as.character(output_root)[1L], winslash = "/", mustWork = FALSE
  )
  staging_checkpoint <- file.path(output_root, "checkpoints")
  child$config <- .ml_stratified_redirect_checkpoints(
    child$config, staging_checkpoint
  )
  if (is.list(child$pipeline)) {
    child$pipeline <- .ml_stratified_redirect_checkpoints(
      child$pipeline, staging_checkpoint
    )
  }
  for (key in intersect(
    names(child),
    c("checkpoint_base", "checkpoint_dir", "index_ck_base", "shared_ck_base")
  )) {
    child[[key]] <- .ml_stratified_relocate_checkpoint_value(
      child[[key]], staging_checkpoint
    )
  }
  child <- .ml_stratified_clear_stale(child)
  dir.create(file.path(output_root, "Tables"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(output_root, "Figures"), recursive = TRUE, showWarnings = FALSE)
  child$root_output_dir <- output_root
  child$output_dir <- output_root
  child$output_dir_tables <- file.path(output_root, "Tables")
  child$output_dir_figures <- file.path(output_root, "Figures")
  child$config$project$output_dir <- output_root
  child$current_block <- NULL
  child$log$block_output_dirs <- list()
  child$log$block_step_counter <- 0L
  child$results$stratum <- stratum
  child
}

.ml_stratified_event_count <- function(ctx, data) {
  if (!is.data.frame(data) || !nrow(data)) return(0L)
  candidates <- c(
    as.character(ctx$config$data$outcome_column),
    "Group", "Disease_Group", "Outcome", "outcome"
  )
  outcome <- NULL
  for (candidate in candidates[nzchar(candidates)]) {
    outcome <- .ml_stratified_column(data, candidate)
    if (!is.null(outcome)) break
  }
  if (is.null(outcome)) return(NA_integer_)
  value <- data[[outcome]]
  analysis_group <- as.character(ctx$config$project$analysis_group)
  if (length(analysis_group) && nzchar(analysis_group[[1L]])) {
    return(as.integer(sum(as.character(value) == analysis_group[[1L]], na.rm = TRUE)))
  }
  as.integer(sum(value %in% c(1, "1", TRUE), na.rm = TRUE))
}

ml_stratum_audit <- function(ctx, spec) {
  reference <- .ml_stratified_reference(ctx)
  id_info <- .ml_stratified_id_info(ctx, reference)
  reference_keys <- .ml_stratified_keys(reference, id_info)
  variable <- .ml_stratified_column(reference, spec$variable)
  if (is.null(variable)) {
    stop("Stratification variable is absent: ", spec$variable, call. = FALSE)
  }
  value <- suppressWarnings(as.numeric(as.character(reference[[variable]])))
  strata <- c(spec$strata, list(
    sofa_missing = list(
      name = "sofa_missing", variable = spec$variable,
      cutoff = spec$cutoff, operator = "missing"
    )
  ))
  rows <- lapply(strata, function(stratum) {
    mask <- if (identical(stratum$operator, "missing")) {
      is.na(value)
    } else {
      .ml_stratified_mask(reference, stratum)
    }
    ids <- reference_keys[mask]
    subset <- reference[mask, , drop = FALSE]
    split_n <- function(slot) {
      data <- ctx$data[[slot]]
      if (!is.data.frame(data)) return(0L)
      keys <- .ml_stratified_keys(data, id_info)
      as.integer(length(unique(keys[keys %in% ids])))
    }
    base <- data.frame(
      stratum = stratum$name,
      n = as.integer(length(ids)),
      events = .ml_stratified_event_count(ctx, subset),
      stringsAsFactors = FALSE
    )
    external_all <- identical(
      tolower(as.character(ctx$config$train_validation$mode)[1L]),
      "external_all"
    ) || isTRUE(ctx$results$train_validation_external_all)
    if (isTRUE(external_all)) {
      external_slot <- c("test", "validation", "val", "train", "imputed")
      external_slot <- external_slot[
        vapply(external_slot, function(s) is.data.frame(ctx$data[[s]]), logical(1))
      ]
      base$external_n <- if (length(external_slot)) {
        split_n(external_slot[[1L]])
      } else {
        0L
      }
    } else {
      base$train_n <- split_n("train")
      internal_slot <- c("test", "validation", "val", "internal")
      internal_slot <- internal_slot[
        vapply(internal_slot, function(s) is.data.frame(ctx$data[[s]]), logical(1))
      ]
      base$internal_n <- if (length(internal_slot)) {
        split_n(internal_slot[[1L]])
      } else {
        0L
      }
    }
    base
  })
  rownames_out <- do.call(rbind, rows)
  rownames(rownames_out) <- NULL
  rownames_out
}
