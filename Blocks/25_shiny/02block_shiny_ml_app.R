###############################################################################
#  shiny_ml_app — ML 风险预测 Shiny App（C01 / ShinyApp + 生成 app.R）
#
#  register_block: "shiny_ml_app"
#  典型流水线: train_validation → ml_models → shiny_ml_app
#              （非 logistic 最优模型；或由 block_shiny 调度）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = train_validation/Data；ml_models/Models/evalresult_<tag>.RData
#  require_results = Model2Factors、ml_best_model_tag（或 shiny_ml_app$ml_model_tag）
#
#  shiny_ml_app = list(
#    enable = TRUE, ml_model_tag = NULL, index_var = NULL,
#    export_app = TRUE, risk_high_pct = 70, risk_low_pct = 30,
#    app_subdir = "ShinyApp", run_interactive = FALSE
#  ),
#  未设 shiny_ml_app 时回退 config$shiny 同名键
###############################################################################

.sma_merged_cfg <- function(cfg) {
  sh <- cfg$shiny %||% list()
  sma <- cfg$shiny_ml_app %||% list()
  if (length(sma)) utils::modifyList(sh, sma) else sh
}

.sma_resolve_tv_data_dir <- function(ctx) {
  tv <- ctx$log$block_output_dirs[["train_validation"]] %||% ""
  tv <- as.character(tv)[1L]
  if (nzchar(tv)) {
    d <- file.path(tv, "Data")
    if (dir.exists(d)) return(normalizePath(d, winslash = "/", mustWork = FALSE))
  }
  d2 <- file.path(ctx$output_dir, "Data")
  if (dir.exists(d2)) return(normalizePath(d2, winslash = "/", mustWork = FALSE))
  ""
}

.sma_resolve_ml_models_dir <- function(ctx, tag = NULL) {
  if (!is.null(tag) && nzchar(as.character(tag)[1L])) {
    d <- resolve_ml_models_dir_for_tag(ctx, tag)
    if (dir.exists(d)) {
      return(normalizePath(d, winslash = "/", mustWork = FALSE))
    }
  }
  ml_block <- as.character(ctx$log$block_output_dirs[["ml_models_bundle"]] %||% "")[1L]
  if (nzchar(ml_block)) {
    d <- file.path(ml_block, "Models")
    if (dir.exists(d)) return(normalizePath(d, winslash = "/", mustWork = FALSE))
  }
  stored <- as.character(ctx$results[["ml_models_models_dir"]] %||% "")[1L]
  if (nzchar(stored) && dir.exists(stored)) {
    return(normalizePath(stored, winslash = "/", mustWork = FALSE))
  }
  ""
}

.sma_resolve_index_vars <- function(cfg, sma_cfg) {
  idx <- sma_cfg$index_var %||% cfg$incidence$index_var %||% NULL
  if (is.null(idx)) {
    pred_idx <- (cfg$prediction %||% list())$index_vars
    if (!is.null(pred_idx)) idx <- pred_idx
  }
  idx <- unique(as.character(idx))
  idx <- idx[nzchar(trimws(idx))]
  if (!length(idx)) {
    cli::cli_alert_info(
      "block_shiny_ml_app: 未配置主暴露 index，按纯预测特征生成 Shiny（侧栏不标注 index）。"
    )
    return(character(0))
  }
  if (length(idx) > 1L) {
    cli::cli_alert_info(
      "block_shiny_ml_app: 纳入 {length(idx)} 个 index 指标: {paste(idx, collapse = ', ')}"
    )
  }
  idx
}

.sma_resolve_ml_tag <- function(ctx, sma_cfg) {
  tag <- as.character(sma_cfg$ml_model_tag %||% ctx$results$ml_best_model_tag %||% "")[1L]
  if (!nzchar(tag)) {
    tag <- as.character(sma_cfg$ml_model_tag_fallback %||% "logistic")[1L]
  }
  tolower(trimws(tag))
}

.sma_recipe_type_for_ml_tag <- function(tag) {
  tg <- tolower(trimws(tag))
  if (tg %in% c("enet", "rsvm")) return("center_scale")
  if (tg %in% c("mlp", "realmlp")) return("range")
  "none"
}

.sma_build_recipe <- function(train_dat, scale_type = "none") {
  r <- recipes::recipe(Group ~ ., data = train_dat)
  r <- recipes::step_impute_median(r, recipes::all_numeric_predictors())
  r <- recipes::step_impute_mode(r, recipes::all_nominal_predictors())
  r <- recipes::step_dummy(r, recipes::all_nominal_predictors())
  if (identical(scale_type, "center_scale")) {
    r <- recipes::step_center(r, recipes::all_predictors())
    r <- recipes::step_scale(r, recipes::all_predictors())
  } else if (identical(scale_type, "range")) {
    r <- recipes::step_range(r, recipes::all_predictors())
  }
  recipes::prep(r)
}

.sma_copy_if_exists <- function(src, dst) {
  if (!nzchar(src) || !file.exists(src)) return(FALSE)
  dir.create(dirname(dst), recursive = TRUE, showWarnings = FALSE)
  isTRUE(tryCatch(file.copy(src, dst, overwrite = TRUE), error = function(e) FALSE))
}

.sma_ensure_group_column <- function(df, cfg) {
  if ("Group" %in% names(df)) return(df)
  oc <- cfg$data$outcome_column %||% "Disease"
  ana <- cfg$project$analysis_group %||% cfg$project$disease %||% "Case"
  ref <- cfg$project$reference_group %||% "Control"
  if (oc %in% names(df)) {
    y_chr <- trimws(as.character(df[[oc]]))
    df$Group <- factor(
      ifelse(y_chr == trimws(ana), ana, ifelse(y_chr == trimws(ref), ref, NA_character_)),
      levels = c(ref, ana)
    )
    return(df)
  }
  if ("fustatus" %in% names(df)) {
    colnames(df)[colnames(df) == "fustatus"] <- "Group"
    return(df)
  }
  if ("Disease" %in% names(df)) {
    colnames(df)[colnames(df) == "Disease"] <- "Group"
    return(df)
  }
  df
}

.sma_resolve_model2_factors <- function(ctx) {
  Model2Factors <- as.character(ctx$results$Model2Factors %||% character(0))
  Model2Factors <- unique(Model2Factors[nzchar(Model2Factors)])
  if (length(Model2Factors)) return(Model2Factors)
  fs_dir <- as.character(ctx$log$block_output_dirs[["feature_selection"]] %||% "")[1L]
  m2_path <- if (nzchar(fs_dir)) file.path(fs_dir, "Model2Factors.RData") else ""
  if (nzchar(m2_path) && file.exists(m2_path)) {
    e_m2 <- new.env(parent = emptyenv())
    load(m2_path, envir = e_m2)
    if (exists("Model2Factors", envir = e_m2)) {
      Model2Factors <- as.character(e_m2$Model2Factors)
    }
  }
  unique(Model2Factors[nzchar(Model2Factors)])
}

.sma_pick_max_predicted_individual <- function(rdata_path, cov_names) {
  if (!nzchar(rdata_path) || !file.exists(rdata_path)) {
    return(list(ok = FALSE, msg = paste0("未找到 ", rdata_path)))
  }
  e <- new.env(parent = emptyenv())
  load(rdata_path, envir = e)
  nms <- ls(envir = e, pattern = "^final_prediction", all.names = TRUE)
  if (!length(nms)) {
    if (exists("final_predictions", envir = e, inherits = FALSE)) {
      nms <- "final_predictions"
    } else {
      return(list(ok = FALSE, msg = "evalresult 中无 final_predictions 或 final_prediction* 对象。"))
    }
  }
  dfs <- list()
  for (nm in nms) {
    obj <- get(nm, envir = e)
    if (is.data.frame(obj) && nrow(obj) > 0L) dfs[[nm]] <- obj
  }
  if (!length(dfs)) {
    return(list(ok = FALSE, msg = "final_predictions 为空。"))
  }
  big <- if (length(dfs) == 1L) dfs[[1L]] else dplyr::bind_rows(dfs)
  pred_cols <- grep("_predicted_value$", names(big), value = TRUE)
  if (!length(pred_cols)) {
    return(list(ok = FALSE, msg = "final_predictions 中无 *_predicted_value 列。"))
  }
  pm <- as.matrix(big[, pred_cols, drop = FALSE])
  if (!is.numeric(pm)) mode(pm) <- "numeric"
  row_max <- apply(pm, 1L, function(z) suppressWarnings(max(as.numeric(z), na.rm = TRUE)))
  row_max[!is.finite(row_max)] <- NA_real_
  if (all(is.na(row_max))) {
    return(list(ok = FALSE, msg = "_predicted_value 列无法转为有效数值。"))
  }
  imax <- which.max(row_max)
  ref <- big[imax, , drop = FALSE]
  cov_keep <- intersect(cov_names, names(ref))
  ref_cov <- if (length(cov_keep)) ref[, cov_keep, drop = FALSE] else ref[, character(0), drop = FALSE]
  top_col <- pred_cols[which.max(as.numeric(ref[1, pred_cols, drop = TRUE]))]
  top_val <- suppressWarnings(max(as.numeric(ref[1, pred_cols, drop = TRUE]), na.rm = TRUE))
  summ <- paste0(
    "参考个体：final_predictions 第 ", imax, " 行（*_predicted_value 行内最大约 ",
    format(top_val, digits = 6), "，列 ", top_col, "）。"
  )
  list(ok = TRUE, row = ref_cov, summary = summ)
}

.sma_default_for_covariate <- function(v, ref_row, x_train) {
  ref_one <- NULL
  if (!is.null(ref_row) && is.data.frame(ref_row) && nrow(ref_row) >= 1L && v %in% names(ref_row)) {
    ref_one <- ref_row[[v]][1L]
  }
  x <- x_train[[v]]
  if (is.numeric(x) || is.integer(x)) {
    def <- if (!is.null(ref_one) && is.finite(suppressWarnings(as.numeric(ref_one)))) {
      as.numeric(ref_one)
    } else {
      suppressWarnings(stats::median(x, na.rm = TRUE))
    }
    if (!is.finite(def)) def <- 0
    return(list(kind = "numeric", value = def))
  }
  if (is.logical(x)) {
    def <- if (!is.null(ref_one)) as.logical(ref_one) else as.logical(stats::median(as.integer(x), na.rm = TRUE))
    if (is.na(def)) def <- FALSE
    return(list(kind = "logical", value = def))
  }
  levs <- if (is.factor(x)) levels(x) else unique(as.character(x[!is.na(x)]))
  if (!length(levs)) levs <- ""
  def <- if (!is.null(ref_one)) {
    rc <- as.character(ref_one)
    if (rc %in% levs) rc else NA_character_
  } else {
    NA_character_
  }
  if (is.na(def) || !length(def)) {
    def <- levs[which.max(tabulate(match(as.character(x), levs)))]
  }
  if (!length(def) || is.na(def)) def <- levs[1]
  list(kind = "factor", value = def, levels = levs)
}

.sma_r_string <- function(x) {
  paste0("\"", gsub("\\\\", "\\\\\\\\", gsub("\"", "\\\\\"", as.character(x))), "\"")
}

.sma_r_literal <- function(x) {
  x <- as.character(x)
  if (length(x) <= 1L) return(.sma_r_string(x[1L]))
  paste0("c(", paste(vapply(x, .sma_r_string, character(1L)), collapse = ", "), ")")
}

.sma_generate_sidebar_ui_lines <- function(cov_names, defaults, index_vars) {
  index_vars <- as.character(index_vars)
  lines <- character(0)
  for (v in cov_names) {
    id <- v
    lab <- gsub("_", " ", v, fixed = TRUE)
    if (v %in% index_vars) lab <- paste0(lab, " (index)")
    d <- defaults[[v]]
    if (d$kind == "numeric") {
      lines <- c(lines, sprintf(
        "      numericInput(%s, %s, value = %s),",
        .sma_r_string(id), .sma_r_string(paste0("Please enter your ", lab)),
        as.character(d$value)
      ))
    } else if (d$kind == "logical") {
      sel <- if (isTRUE(d$value)) "TRUE" else "FALSE"
      lines <- c(lines, sprintf(
        "      selectInput(%s, %s, choices = c(\"FALSE\", \"TRUE\"), selected = %s),",
        .sma_r_string(id), .sma_r_string(paste0("Please enter your ", lab)),
        .sma_r_string(sel)
      ))
    } else {
      ch <- paste(vapply(d$levels, .sma_r_string, character(1L)), collapse = ", ")
      lines <- c(lines, sprintf(
        "      selectInput(%s, %s, choices = c(%s), selected = %s),",
        .sma_r_string(id), .sma_r_string(paste0("Please enter your ", lab)),
        ch, .sma_r_string(d$value)
      ))
    }
  }
  lines
}

.sma_generate_server_assign_lines <- function(cov_names) {
  vapply(cov_names, function(v) sprintf("    %s <- input$%s", v, v), character(1L))
}

.sma_generate_df_assign_lines <- function(cov_names) {
  vapply(cov_names, function(v) sprintf("      %s = %s,", v, v), character(1L))
}

.sma_write_app_r <- function(app_dir, meta) {
  sidebar_ui <- .sma_generate_sidebar_ui_lines(
    meta$cov_names, meta$defaults, meta$Index_vars
  )
  server_assign <- .sma_generate_server_assign_lines(meta$cov_names)
  df_assign <- .sma_generate_df_assign_lines(meta$cov_names)
  note_b <- meta$note_covariates_text
  disease <- meta$disease_lbl
  pred_col <- meta$pred_col
  risk_hi <- meta$risk_high
  risk_lo <- meta$risk_low
  ml_tag <- meta$ml_tag
  eval_bn <- meta$evalresult_basename

  lines <- c(
    "# Auto-generated by block_shiny_ml_app — deploy this folder to shinyapps.io",
    "# Files required in the same directory: shiny_staging.RData, df_train_RData.RData,",
    paste0("# model2factors.RData, ", eval_bn),
    "",
    paste0("Index <- ", .sma_r_literal(meta$Index_vars)),
    "",
    "library(tidymodels)",
    "library(tidyverse)",
    "library(tidyr)",
    "library(dplyr)",
    "",
    "library(xgboost)",
    "library(randomForest)",
    "library(sfd)",
    "library(dials)",
    "library(shiny)",
    "library(httr)",
    "library(jsonlite)",
    "library(lightgbm)",
    "library(bonsai)",
    "",
    "load(\"shiny_staging.RData\")",
    "load(\"df_train_RData.RData\")",
    paste0("load(", .sma_r_string(eval_bn), ")"),
    "",
    "datarecipe <- shiny_staging$datarecipe",
    paste0("final_model <- final_", ml_tag),
    "if (!exists(\"df_train\")) stop(\"df_train_RData.RData 须包含 df_train\")",
    "if (!\"Group\" %in% names(df_train)) {",
    "  if (\"fustatus\" %in% names(df_train)) colnames(df_train)[colnames(df_train) == \"fustatus\"] <- \"Group\"",
    "}",
    "",
    "ui <- fluidPage(",
    "  tags$head(",
    "    tags$style(HTML(\"",
    "      .blue-text {",
    "        font-size: 1.5em;",
    "        color: #6699FF;",
    "        font-weight: bold;",
    "        margin: 10px 0;",
    "        white-space: pre-line;",
    "      }",
    "      .note p{",
    "        font-size: 0.9em;",
    "        margin-bottom: 5px;",
    "        line-height: 1.2;",
    "      }",
    "    \"))",
    "  ),",
    paste0("  titlePanel(", .sma_r_string(paste0("Predicting ", disease)), "),"),
    "  sidebarLayout(",
    "    sidebarPanel(",
    sidebar_ui,
    "      actionButton(\"submitBtn\", \"Submit\", icon = icon(\"play\"), class = \"btn-primary\")",
    "    ),",
    "    mainPanel(",
    paste0("      h3(", .sma_r_string(paste0("Predicting ", disease, " outcomes:")), "),"),
    "      div(class = \"blue-text\", textOutput(\"result\")),",
    "      div(class = \"note\",",
    "        p(\"Note:\"),",
    paste0("        p(", .sma_r_string(paste0(
      "a. This website aims to develop and validate a model using machine learning algorithms to predict the risk of ",
      disease
    )), "),"),
    paste0("        p(", .sma_r_string(paste0(
      "b. By simply inputting the information: ", note_b,
      ", it is possible to predict the risk of ", disease
    )), "),"),
    "      )",
    "    )",
    "  )",
    ")",
    "",
    "options(shiny.maxRequestSize = 100*1024^2, shiny.timeout = 600)",
    "server <- function(input, output) {",
    "  observeEvent(input$submitBtn, {",
    server_assign,
    "    df <- data.frame(",
    df_assign,
    "      stringsAsFactors = FALSE",
    "    )",
    "    df_processed <- bake(datarecipe, new_data = df)",
    "    pred_prob <- predict(final_model, new_data = df_processed, type = \"prob\")",
    paste0("    pred_col <- ", .sma_r_string(pred_col)),
    "    if (!pred_col %in% names(pred_prob)) {",
    "      pcols <- grep(\"^\\\\.pred_\", names(pred_prob), value = TRUE)",
    "      pred_col <- pcols[length(pcols)]",
    "    }",
    "    predicted_probability <- round(pred_prob[[pred_col]] * 100, 2)",
    paste0("    if (predicted_probability >= ", risk_hi, ") {"),
    "      risk_level <- \"high risk\"",
    paste0("    } else if (predicted_probability < ", risk_lo, ") {"),
    "      risk_level <- \"low risk\"",
    "    } else {",
    "      risk_level <- \"medium risk\"",
    "    }",
    "    output$result <- renderText({",
    paste0("      paste0(\"This patient is at \", risk_level, \" of ", disease, "! \\\\n\","),
    paste0("             \"The probability of ", disease, " is: \", predicted_probability, \"%\")"),
    "    })",
    "  })",
    "}",
    "",
    "shinyApp(ui = ui, server = server)",
    ""
  )
  writeLines(lines, file.path(app_dir, "app.R"), useBytes = TRUE)
}

block_shiny_ml_app <- function(ctx, ...) {
  cfg <- ctx$config
  sma_cfg <- .sma_merged_cfg(cfg)
  pred_cfg <- cfg$prediction %||% list()

  sh_legacy <- cfg$shiny %||% list()
  if (!isTRUE(sma_cfg$enable %||% sh_legacy$enable %||% pred_cfg$shiny_app_enable %||% FALSE)) {
    cli::cli_alert_info(
      "block_shiny_ml_app: 未启用（shiny_ml_app$enable / shiny$enable / prediction$shiny_app_enable），跳过。"
    )
    return(ctx)
  }

  if (!requireNamespace("recipes", quietly = TRUE)) {
    stop("block_shiny_ml_app: 需要 recipes 包。", call. = FALSE)
  }
  if (!requireNamespace("shiny", quietly = TRUE)) {
    stop("block_shiny_ml_app: 需要 shiny 包。", call. = FALSE)
  }

  Index_vars <- .sma_resolve_index_vars(cfg, sma_cfg)
  ml_tag <- .sma_resolve_ml_tag(ctx, sma_cfg)

  disease_lbl <- cfg$project$disease %||% cfg$project$analysis_group %||% "Outcome"
  disease_lbl <- as.character(disease_lbl)[1L]
  pred_col <- paste0(".pred_", make.names(disease_lbl))
  risk_high <- as.numeric(sma_cfg$risk_high_pct %||% 70)[1L]
  risk_low  <- as.numeric(sma_cfg$risk_low_pct %||% 30)[1L]
  app_subdir <- as.character(
    sma_cfg$app_subdir_ml %||% sma_cfg$app_subdir %||% "ShinyApp"
  )[1L]

  tv_dir <- .sma_resolve_tv_data_dir(ctx)
  ml_dir <- .sma_resolve_ml_models_dir(ctx, ml_tag)
  if (!nzchar(tv_dir)) {
    stop("block_shiny_ml_app: 未找到 train_validation/Data。", call. = FALSE)
  }
  if (!nzchar(ml_dir)) {
    stop("block_shiny_ml_app: 未找到 ml_models/Models。", call. = FALSE)
  }

  src_train <- file.path(tv_dir, "df_train_RData.RData")
  src_val   <- file.path(tv_dir, "df_validation_RData.RData")
  if (!file.exists(src_val)) {
    alt <- file.path(tv_dir, "df_val_RData.RData")
    if (file.exists(alt)) src_val <- alt
  }
  eval_src <- file.path(ml_dir, paste0("evalresult_", ml_tag, ".RData"))
  if (!file.exists(eval_src)) {
    stop("block_shiny_ml_app: 未找到 ", eval_src, call. = FALSE)
  }

  Model2Factors <- .sma_resolve_model2_factors(ctx)
  if (!length(Model2Factors)) {
    stop("block_shiny_ml_app: 无 Model2Factors（请先运行 feature_selection）。", call. = FALSE)
  }

  Final_Features <- unique(c(Model2Factors, Index_vars))
  Final_Features <- Final_Features[nzchar(Final_Features)]

  e_tr <- new.env(parent = emptyenv())
  load(src_train, envir = e_tr)
  if (!exists("df_train", envir = e_tr)) {
    stop("block_shiny_ml_app: ", src_train, " 中无 df_train。", call. = FALSE)
  }
  df_train <- e_tr$df_train
  df_train <- .sma_ensure_group_column(df_train, cfg)

  miss <- setdiff(Final_Features, names(df_train))
  if (length(miss)) {
    stop(
      "block_shiny_ml_app: 训练集缺少协变量: ", paste(miss, collapse = ", "),
      call. = FALSE
    )
  }

  pick <- .sma_pick_max_predicted_individual(eval_src, Final_Features)
  ref_row <- if (isTRUE(pick$ok)) pick$row else NULL
  if (!isTRUE(pick$ok)) {
    cli::cli_alert_warning("block_shiny_ml_app: {pick$msg}；侧栏默认值改用训练集中位数/众数。")
  }

  defaults <- stats::setNames(
    lapply(Final_Features, function(v) {
      .sma_default_for_covariate(v, ref_row, df_train)
    }),
    Final_Features
  )

  traindata <- df_train[, c("Group", Final_Features), drop = FALSE]
  scale_type <- .sma_recipe_type_for_ml_tag(ml_tag)
  datarecipe <- .sma_build_recipe(traindata, scale_type = scale_type)
  cli::cli_alert_success(
    "block_shiny_ml_app: recipe 已预计算（scale={scale_type}）。"
  )

  app_dir <- file.path(ctx$output_dir, app_subdir)
  data_dir <- file.path(ctx$output_dir, "Data")
  dir.create(app_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)

  eval_bn <- paste0("evalresult_", ml_tag, ".RData")
  staged <- list(
    datarecipe = datarecipe,
    Index = Index_vars,
    Index_vars = Index_vars,
    disease_lbl = disease_lbl,
    Final_Features = Final_Features,
    cov_names = Final_Features,
    ml_tag = ml_tag,
    pred_col = pred_col,
    risk_high = risk_high,
    risk_low = risk_low,
    ref_summary = pick$summary %||% "",
    note_covariates_text = paste(Final_Features, collapse = ",")
  )
  save(staged, file = file.path(app_dir, "shiny_staging.RData"))

  copies <- list(
    list(src = src_train, dst = file.path(app_dir, "df_train_RData.RData")),
    list(src = src_val,   dst = file.path(app_dir, "df_validation_RData.RData")),
    list(src = eval_src,  dst = file.path(app_dir, eval_bn))
  )
  if (nzchar(src_val) && file.exists(src_val)) {
    copies[[2]]$dst <- file.path(app_dir, "df_validation_RData.RData")
  } else {
    copies <- copies[c(1L, 3L)]
  }

  copied <- character(0)
  for (cp in copies) {
    if (.sma_copy_if_exists(cp$src, cp$dst)) {
      copied <- c(copied, basename(cp$dst))
      .sma_copy_if_exists(cp$src, file.path(data_dir, basename(cp$dst)))
    }
  }

  save(Model2Factors, file = file.path(app_dir, "model2factors.RData"))
  save(Model2Factors, file = file.path(data_dir, "model2factors.RData"))

  note_cov <- paste(Final_Features, collapse = ",")
  meta <- list(
    Index_vars = Index_vars,
    disease_lbl = disease_lbl,
    cov_names = Final_Features,
    defaults = defaults,
    pred_col = pred_col,
    risk_high = risk_high,
    risk_low = risk_low,
    ml_tag = ml_tag,
    evalresult_basename = eval_bn,
    note_covariates_text = note_cov
  )

  if (isTRUE(sma_cfg$export_app %||% TRUE)) {
    .sma_write_app_r(app_dir, meta)
    writeLines(
      c(
        "ML Risk Prediction App (block_shiny_ml_app)",
        "",
        "Deploy to shinyapps.io:",
        "1. Upload entire ShinyApp/ folder (app.R + all .RData files).",
        "2. Or: setwd to this folder; source('app.R') or shiny::runApp()",
        "",
        paste0("Model tag: ", ml_tag),
        paste0("Index: ", paste(Index_vars, collapse = ", ")),
        paste0("Features: ", note_cov),
        "",
        if (nzchar(pick$summary %||% "")) pick$summary else ""
      ),
      file.path(app_dir, "README.txt"),
      useBytes = TRUE
    )
    cli::cli_alert_success("block_shiny_ml_app: 已写出 {.file {app_dir}/app.R}")
  }

  if (isTRUE(sma_cfg$run_interactive %||% FALSE)) {
    old_wd <- getwd()
    on.exit(setwd(old_wd), add = TRUE)
    setwd(app_dir)
    cli::cli_alert_info("block_shiny_ml_app: 启动 Shiny（关闭后流水线继续）...")
    shiny::runApp(app_dir)
  }

  ctx$results$shiny_app_dir <- app_dir
  ctx$results$shiny_app_mode <- "ml_predict_c01"
  ctx$results$shiny_ml_model_tag <- ml_tag
  ctx$results$shiny_index_var <- Index_vars
  ctx$results$shiny_staged_files <- copied
  ctx$results$shiny_final_features <- Final_Features

  cli::cli_alert_success(
    "block_shiny_ml_app: 完成（模型={ml_tag}；已复制: {paste(copied, collapse=', ')})"
  )
  ctx
}

register_block(
  "shiny_ml_app",
  block_shiny_ml_app,
  "Shiny ML 预测 App（C01 / ShinyApp）"
)
