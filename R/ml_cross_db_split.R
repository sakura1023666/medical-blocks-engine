###############################################################################
#  ml_cross_db_split.R — cross-DB train/test role assignment (by analysis n)
###############################################################################

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}

#' Assign train / test roles across databases by analysis sample size.
#'
#' Larger-n database becomes \code{train}; remaining DBs become \code{test},
#' \code{test2}, ... in descending \code{n}. Ties break toward
#' \code{primary_name}, then alphabetical \code{db_name}.
#'
#' @param db_n Named integer vector of analysis \code{n} per database.
#' @param primary_name Optional primary DB name for tie-breaking.
#' @param event_counts Optional named integer vector of outcome events per DB.
#' @return List with \code{assignment} (data.frame), \code{train_db}, \code{test_dbs}.
ml_cross_db_assign_roles <- function(db_n, primary_name = NULL, event_counts = NULL) {
  stopifnot(length(db_n) >= 1L, !is.null(names(db_n)))
  db_names <- names(db_n)
  db_n <- as.integer(db_n)
  names(db_n) <- db_names
  if (!is.null(event_counts)) {
    stopifnot(!is.null(names(event_counts)))
    ev_names <- names(event_counts)
    event_counts <- as.integer(event_counts)
    names(event_counts) <- ev_names
  }

  primary_name <- as.character(primary_name %||% character())[1L]
  ord <- order(
    -db_n,
    !(names(db_n) %in% primary_name),
    names(db_n)
  )
  nm <- names(db_n)[ord]
  roles <- if (length(nm) == 1L) {
    c(train = nm[[1L]])
  } else {
    test_role_names <- c(
      "test",
      if (length(nm) > 2L) paste0("test", seq_len(length(nm) - 2L) + 1L) else character()
    )
    c(train = nm[[1L]], stats::setNames(nm[-1L], test_role_names))
  }

  n_vec <- unname(db_n[roles])
  n_event_vec <- if (!is.null(event_counts)) {
    unname(event_counts[roles])
  } else {
    rep(NA_integer_, length(roles))
  }

  assignment <- data.frame(
    role = names(roles),
    db_name = unname(roles),
    n = n_vec,
    n_event = n_event_vec,
    stringsAsFactors = FALSE
  )

  list(
    assignment = assignment,
    train_db = assignment$db_name[assignment$role == "train"][[1L]],
    test_dbs = assignment$db_name[assignment$role != "train"]
  )
}

#' Bind pre-imputation frames to train / test roles from an assignment table.
#'
#' @param frames Named list of raw data.frames keyed by database name.
#' @param assignment Data.frame from \code{ml_cross_db_assign_roles()}.
#' @return Named list of frames keyed by role (\code{train}, \code{test}, ...).
ml_cross_db_bind_role <- function(frames, assignment) {
  stopifnot(is.data.frame(assignment))
  req_cols <- c("role", "db_name")
  if (!all(req_cols %in% names(assignment))) {
    stop("assignment 必须包含列: ", paste(req_cols, collapse = ", "), call. = FALSE)
  }
  stopifnot(is.list(frames), !is.null(names(frames)))

  missing_db <- setdiff(unique(assignment$db_name), names(frames))
  if (length(missing_db)) {
    stop(
      "frames 缺少库: ",
      paste(missing_db, collapse = ", "),
      call. = FALSE
    )
  }

  roles <- assignment$role
  if (anyDuplicated(roles)) {
    stop("assignment$role 存在重复", call. = FALSE)
  }

  out <- stats::setNames(
    lapply(seq_len(nrow(assignment)), function(i) frames[[assignment$db_name[[i]]]]),
    roles
  )
  out
}
