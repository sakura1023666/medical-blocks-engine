###############################################################################
# gallstone_train_split — 7:3 分层划分 + Table2 train vs val
###############################################################################

block_gallstone_train_split <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_gallstone_nomogram.R"), local = FALSE)
  d <- ctx$data$imputed %||% ctx$data$cleaned
  outcome <- ctx$config$data$outcome_column %||% "Success"
  bl <- ctx$config$gallstone_nomogram %||% list()
  ratio <- as.numeric(bl$train_ratio %||% 0.7)
  seed <- as.integer(bl$seed %||% 42L)
  if (is.null(d)) stop("train_split: 无数据", call. = FALSE)
  y <- d[[outcome]]
  if (!is.factor(y)) y <- factor(ifelse(as.integer(d$success %||% y) == 1L, "Yes", "No"))
  set.seed(seed)
  if (requireNamespace("rsample", quietly = TRUE)) {
    sp <- rsample::initial_split(d, prop = ratio, strata = outcome)
    train <- rsample::training(sp)
    test <- rsample::testing(sp)
  } else {
    idx_yes <- which(as.character(y) %in% c("Yes", "1"))
    idx_no <- setdiff(seq_len(nrow(d)), idx_yes)
    n_tr_y <- max(1L, floor(length(idx_yes) * ratio))
    n_tr_n <- max(1L, floor(length(idx_no) * ratio))
    tr <- c(sample(idx_yes, n_tr_y), sample(idx_no, n_tr_n))
    train <- d[tr, , drop = FALSE]
    test <- d[setdiff(seq_len(nrow(d)), tr), , drop = FALSE]
  }
  ctx$data$train <- train
  ctx$data$test <- test
  # Table2 简表
  vars <- unique(c(gallstone_nomogram_cat_features(ctx$config),
                   gallstone_nomogram_cont_features(ctx$config)))
  vars <- vars[vars %in% names(d)]
  rows <- list()
  for (v in vars) {
    if (is.numeric(train[[v]]) && !is.factor(train[[v]])) {
      rows[[length(rows) + 1L]] <- data.frame(
        variable = v,
        train = sprintf("%.2f \u00b1 %.2f", mean(train[[v]], na.rm = TRUE), stats::sd(train[[v]], na.rm = TRUE)),
        validation = sprintf("%.2f \u00b1 %.2f", mean(test[[v]], na.rm = TRUE), stats::sd(test[[v]], na.rm = TRUE)),
        stringsAsFactors = FALSE
      )
    } else {
      rows[[length(rows) + 1L]] <- data.frame(
        variable = v,
        train = paste(names(table(train[[v]])), as.integer(table(train[[v]])), sep = "=", collapse = "; "),
        validation = paste(names(table(test[[v]])), as.integer(table(test[[v]])), sep = "=", collapse = "; "),
        stringsAsFactors = FALSE
      )
    }
  }
  tab <- do.call(rbind, rows)
  dirs <- gallstone_nomogram_out_dirs(ctx, "ALL")
  gallstone_nomogram_ensure_dirs(list(dirs$shared_tables, file.path(dirs$project, "Tables")))
  for (td in unique(c(dirs$shared_tables, file.path(dirs$project, "Tables")))) {
    utils::write.csv(tab, file.path(td, "Table 2. Train vs validation baseline.csv"),
                     row.names = FALSE)
    writeLines(c(
      sprintf("train_n=%d", nrow(train)),
      sprintf("val_n=%d", nrow(test)),
      sprintf("seed=%d", seed),
      sprintf("ratio=%.2f", ratio),
      "External validation: not applicable; bootstrap used for Fig7-9 third panel."
    ), file.path(td, "Methods_split_denominator_note.txt"))
  }
  ctx$results$gallstone_train_split <- list(n_train = nrow(train), n_val = nrow(test), seed = seed)
  cli::cli_alert_success("7:3 split: train={nrow(train)} val={nrow(test)}")
  ctx
}

register_block("gallstone_train_split", block_gallstone_train_split, "胆结石7:3划分Table2")
