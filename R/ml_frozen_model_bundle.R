###############################################################################
#  ml_frozen_model_bundle.R — AKI SOSM+WPR 原文复刻 Task 5
#  SOFA 分层五模型「冻结资产包」：MIMIC-IV 分层 Boruta + 五模型训练 →
#  saveRDS+md5 校验和落盘 → eICU 对应层只加载同名资产冻结预测（不重训、
#  不重做 Boruta、不递归扫描 evalresult 猜层别）。
#
#  复用（source-only，不修改）：
#   - R/ml_stratified_ctx.R      ml_stratum_spec_sofa / ml_clone_ctx_for_stratum
#   - R/ml_dual_dev_ext.R        prob/youden/scale/eval 度量口径
#   - Blocks/19_feature_selection/02block_feature_selection_boruta.R
#   - Blocks/22_ml_models/0{1,8}、02、03、09 五模型块（logistic/dt/rf/xgboost/lightgbm）
#
#  落盘结构（每层一个目录，禁止跨层混放）：
#    model_assets/<stratum_key>/
#      feature_manifest.rds     特征顺序、因子水平、结局标签、split 人数、版本、性能
#      model_<tag>.rds          每模型：fitted workflow + prepped recipe + baked 列序
#                               + Youden(train) + scale_type + 因子水平
#      manifest.json            人类可读 + 机器校验：stratum 定义、SOFA 切点、
#                               特征、每模型校验和（tools::md5sum(saveRDS 文件)）、
#                               R/包版本、来源库身份
#
#  铁律对齐（tst_methods_leakage_denom_gate / ml_prognosis_pub_reuse）：
#   - 外验只 predict：ml_predict_external_bundle 内无任何 fit/tune/Boruta 调用；
#   - 缺特征硬失败并列出缺失列；未见因子水平显式审计（level→NA 计数），
#     禁止把因子静默改数值；
#   - eICU 层只能继承 MIMIC 同层资产；跨层请求报错；
#   - 保留原 train/internal 划分（ml_clone_ctx_for_stratum 深拷贝 + ID 同步过滤）。
###############################################################################

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}

# /2: stratum 契约由单 cutoff/operator 改为 (lower, upper] 边界，支持 3 层 SOFA。
ml_frozen_bundle_schema_version <- function() "ml_frozen_model_bundle/2"

ml_frozen_default_methods <- function() {
  c("logistic", "dt", "rf", "xgboost", "lightgbm")
}

.ml_frozen_norm_id <- function(x) tolower(trimws(as.character(x %||% "")[1L]))

#' 主库身份判定（I2：fail-closed——未声明 database 一律拒绝训练）。
.ml_frozen_is_primary_database <- function(name) {
  if (is.null(name) || !length(name)) return(FALSE)
  norm <- .ml_frozen_norm_id(name)
  if (!nzchar(norm) || identical(norm, "na")) return(FALSE)
  norm %in% c("mimic_iv", "mimic-iv", "mimic iv", "mimic", "mimiciv")
}

.ml_frozen_normalize_methods <- function(methods) {
  m <- tolower(trimws(as.character(methods %||% character(0))))
  m <- m[nzchar(m)]
  if (!length(m)) m <- ml_frozen_default_methods()
  alias <- c("light_gbm" = "lightgbm", "lgbm" = "lightgbm", "xgb" = "xgboost",
             "decision_tree" = "dt", "random_forest" = "rf", "logreg" = "logistic")
  for (i in seq_along(m)) if (m[[i]] %in% names(alias)) m[[i]] <- alias[[m[[i]]]]
  allowed <- ml_frozen_default_methods()
  bad <- setdiff(m, allowed)
  if (length(bad)) {
    stop("ml_frozen bundle 五模型仅支持: ", paste(allowed, collapse = ", "),
         "；不支持: ", paste(bad, collapse = ", "), call. = FALSE)
  }
  unique(m)
}

.ml_frozen_sofa_breaks <- function(ctx) {
  cfg <- ctx$config %||% list()
  raw <- cfg$ml_frozen_bundle$sofa_breaks %||% cfg$reference$sofa_breaks
  if (is.null(raw)) {
    # 兼容旧 sofa_cutoff 单切点配置：cutoff=10 -> 2 层
    v <- suppressWarnings(as.numeric(
      cfg$ml_frozen_bundle$sofa_cutoff %||% cfg$reference$sofa_cutoff
    )[1L])
    if (is.finite(v) && v == as.integer(v)) return(as.integer(v))
    raw <- c(4, 10)
  }
  br <- suppressWarnings(as.integer(as.numeric(unlist(raw))))
  br <- br[is.finite(br)]
  if (!length(br)) br <- c(4L, 10L)
  unique(sort(br))
}

#' stratum key -> spec list（overall 返回 NULL 表示不分层）
.ml_frozen_resolve_stratum <- function(ctx, stratum_key) {
  stratum_key <- .ml_frozen_norm_id(stratum_key)
  if (!nzchar(stratum_key)) {
    stop("stratum_key is required (overall | one of the SOFA layer keys).",
         call. = FALSE)
  }
  if (identical(stratum_key, "overall")) return(NULL)
  spec <- ml_stratum_spec_sofa(breaks = .ml_frozen_sofa_breaks(ctx))
  hit <- spec$strata[[stratum_key]]
  if (is.null(hit)) {
    stop("Unknown stratum key: ", stratum_key,
         "（本课题合法层别: overall, ",
         paste(names(spec$strata), collapse = ", "), "）", call. = FALSE)
  }
  hit
}

#' overall 场景的轻量克隆：深拷贝 + 清 stale + 输出重定向（无患者过滤）。
.ml_frozen_clone_plain <- function(ctx, output_root) {
  child <- unserialize(serialize(ctx, connection = NULL, xdr = FALSE))
  output_root <- normalizePath(as.character(output_root)[1L],
                               winslash = "/", mustWork = FALSE)
  staging_checkpoint <- file.path(output_root, "checkpoints")
  if (exists(".ml_stratified_redirect_checkpoints", mode = "function")) {
    redirect <- get(".ml_stratified_redirect_checkpoints", mode = "function")
    child$config <- redirect(child$config, staging_checkpoint)
    if (is.list(child$pipeline)) child$pipeline <- redirect(child$pipeline, staging_checkpoint)
    for (key in intersect(names(child),
                          c("checkpoint_base", "checkpoint_dir",
                            "index_ck_base", "shared_ck_base"))) {
      child[[key]] <- staging_checkpoint
    }
  }
  if (exists(".ml_stratified_clear_stale", mode = "function")) {
    clear <- get(".ml_stratified_clear_stale", mode = "function")
    child <- clear(child)
  }
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
  child$results$stratum <- NULL
  child
}

#' 分层候选特征（每层独立特征集的入口名单）。
#' C1：主路径（Model2Factors/univar 非空）同样应用 never_features 与分层键排除；
#'     各 SOFA 层的定义变量（SOFA）禁止入模（与 Task3 Cox/RCS
#'     hard_exclude 口径一致）；overall 层不分层，SOFA 作为普通预测因子可保留。
.ml_frozen_candidate_features <- function(ctx, stratum = NULL) {
  cfg <- ctx$config %||% list()
  data_ref <- ctx$data$imputed %||% ctx$data$train
  if (!is.data.frame(data_ref)) return(character(0))
  cand <- as.character(ctx$results$Model2Factors %||% character(0))
  if (!length(cand)) cand <- as.character(ctx$results$univar_features %||% character(0))
  never <- if (exists("pipeline_never_predictor_names", mode = "function")) {
    pipeline_never_predictor_names(cfg)
  } else character(0)
  never <- unique(c(
    never, "Group",
    as.character(cfg$data$id_column %||% character(0)),
    as.character(cfg$data$outcome_column %||% "Disease"),
    as.character(cfg$ml_frozen_bundle$never_features %||% character(0)),
    if (is.null(stratum)) character(0) else as.character(stratum$variable)
  ))
  if (!length(cand)) {
    cand <- setdiff(names(data_ref), c(
      never,
      as.character(cfg$survival$time_var %||% character(0)),
      as.character(cfg$survival$event_var %||% character(0))
    ))
  }
  cand <- setdiff(cand, never)
  cand <- intersect(unique(cand[nzchar(cand)]), names(data_ref))
  cand
}

.ml_frozen_block_files <- function() {
  root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(root)) root <- normalizePath(".", winslash = "/")
  if (.Platform$OS.type != "windows" && grepl("^[A-Za-z]:/", root)) {
    root <- paste0("/mnt/", tolower(substr(root, 1L, 1L)), substring(root, 3L))
  }
  c(
    boruta = file.path(root, "Blocks/19_feature_selection/02block_feature_selection_boruta.R"),
    logistic = file.path(root, "Blocks/22_ml_models/08block_ml_logistic.R"),
    dt = file.path(root, "Blocks/22_ml_models/01block_ml_dt.R"),
    rf = file.path(root, "Blocks/22_ml_models/02block_ml_rf.R"),
    xgboost = file.path(root, "Blocks/22_ml_models/03block_ml_xgboost.R"),
    lightgbm = file.path(root, "Blocks/22_ml_models/09block_ml_lightgbm.R")
  )
}

.ml_frozen_source_blocks <- function(quiet = FALSE) {
  files <- .ml_frozen_block_files()
  for (nm in names(files)) {
    if (!file.exists(files[[nm]])) {
      stop("缺少引擎块源码: ", files[[nm]], call. = FALSE)
    }
    fn_name <- if (identical(nm, "boruta")) "block_feature_selection_boruta"
    else paste0("block_ml_", nm)
    if (!exists(fn_name, mode = "function")) {
      source(files[[nm]], local = FALSE)
    }
    if (!exists(fn_name, mode = "function")) {
      stop("无法加载引擎块: ", fn_name, call. = FALSE)
    }
  }
  invisible(TRUE)
}

#' 与 Blocks/22_ml_models 各块 .mll*0?_build_recipe 等价的无管道实现。
.ml_frozen_build_recipe <- function(train_dat, scale_type = "none") {
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

.ml_frozen_outcome_labels <- function(ctx) {
  cfg <- ctx$config %||% list()
  lbl <- if (exists("pipeline_resolve_outcome_display_labels", mode = "function")) {
    tryCatch(pipeline_resolve_outcome_display_labels(cfg), error = function(e) NULL)
  } else NULL
  ana <- as.character(if (!is.null(lbl) && nzchar(lbl$analysis %||% "")) {
    lbl$analysis
  } else cfg$project$analysis_group %||% cfg$project$disease %||% "Case")
  ref <- as.character(if (!is.null(lbl) && nzchar(lbl$reference %||% "")) {
    lbl$reference
  } else cfg$project$reference_group %||% "Control")
  list(analysis = ana[1L], reference = ref[1L])
}

.ml_frozen_versions_snapshot <- function() {
  pkgs <- c("parsnip", "recipes", "workflows", "rsample", "tune", "yardstick",
            "dials", "hardhat", "dplyr", "rpart", "randomForest", "xgboost",
            "lightgbm", "Boruta")
  vers <- lapply(pkgs, function(p) {
    if (requireNamespace(p, quietly = TRUE)) {
      as.character(utils::packageVersion(p))
    } else NA_character_
  })
  names(vers) <- pkgs
  list(r_version = R.version.string, package_versions = vers)
}

#' saveRDS + tools::md5sum（对齐 Task3 provenance 思路）。
#' 注意：必须用 RDS 默认序列化版本（3）——xgboost booster / prepped recipes 含
#' externalptr，version=2 往返会损坏（invalid 'xgb.Booster (blank externalptr)'）。
#' 校验和只对落盘文件本身复验，跨会话可验证。
.ml_frozen_rds_checksum <- function(object, path) {
  saveRDS(object, path)
  unname(tools::md5sum(path))
}

#' Youden 训练阈值：事件轴 P(event)，只取有限阈值（与
#' ml_dual_dev_ext_youden_from_wide 同口径）；退化时回 0.5。
.ml_finite_youden <- function(thr) {
  thr <- suppressWarnings(as.numeric(thr)[1L])
  if (!is.finite(thr) || thr <= 0 || thr >= 1) 0.5 else thr
}

#' 在给定 SOFA 层（或 overall）的 train 子集上跑 Boruta + 五模型。
#' 保留父 ctx 的 train/internal 划分（不重新 split）。每层独立特征集。
#'
#' @param ctx        父 pipeline ctx（含 data$imputed / train / test、config、
#'                   results$Model2Factors 等）。只读。
#' @param stratum_key "overall" | 任一 SOFA 层键（默认三层 sofa_0_4 / sofa_5_10 /
#'                   sofa_11plus，由 ml_stratum_spec_sofa(breaks) 生成）
#' @param methods    五模型子集，默认全部
#' @param assets_root 可选：临时工作区根（默认 tempfile，训练后即删）
#' @param quiet      降低日志噪声
ml_fit_stratum_bundle <- function(
  ctx, stratum_key, methods = ml_frozen_default_methods(),
  assets_root = NULL, quiet = FALSE
) {
  methods <- .ml_frozen_normalize_methods(methods)
  if (!is.list(ctx) || !is.list(ctx$data)) {
    stop("ml_fit_stratum_bundle: 需要 pipeline ctx（含 ctx$data）。", call. = FALSE)
  }
  db_id <- ctx$config$project$database
  if (!.ml_frozen_is_primary_database(db_id)) {
    stop("冻结资产只能在主库（MIMIC-IV 开发库）训练；当前 ctx 库身份: ",
         as.character(db_id)[1L], "。外验库禁止 fit/Boruta。", call. = FALSE)
  }
  stratum <- .ml_frozen_resolve_stratum(ctx, stratum_key)
  key <- if (is.null(stratum)) "overall" else stratum$name
  invisible(quiet)

  cand <- .ml_frozen_candidate_features(ctx, stratum)
  if (!length(cand)) {
    stop("分层 ", key, " 无候选特征（Model2Factors/univar 为空且无法回退）。",
         call. = FALSE)
  }

  work_root <- file.path(
    if (is.null(assets_root)) tempdir() else as.character(assets_root)[1L],
    paste0(".work_frozen_", key)
  )
  unlink(work_root, recursive = TRUE)
  dir.create(work_root, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(work_root, recursive = TRUE), add = TRUE)

  child <- if (is.null(stratum)) {
    .ml_frozen_clone_plain(ctx, work_root)
  } else {
    ml_clone_ctx_for_stratum(ctx, stratum, work_root)
  }
  child$results$Model2Factors <- cand
  if (is.null(stratum)) {
    child$results$stratum <- NULL
  }

  fs_cfg <- child$config$feature_selection %||% list()
  fs_on <- isTRUE(fs_cfg$enable %||% FALSE)
  if (fs_on && identical(fs_cfg$restrict_to_train, FALSE)) {
    stop("分层资产禁止层内重新抽样：feature_selection$enable=TRUE 时 ",
         "restrict_to_train 不得为 FALSE（会在层内二次 split 造成泄漏）。",
         call. = FALSE)
  }
  if (fs_on) {
    # C2：强制只在层 train 上拟合（保留原 train/internal 划分）
    child$config$feature_selection$restrict_to_train <- TRUE
  }
  feats <- cand
  selector <- "model2_factors"
  if (fs_on) {
    .ml_frozen_source_blocks(quiet = TRUE)
    child <- block_feature_selection_boruta(child)
    sel <- as.character(
      child$results$feature_selection_by_model[["boruta"]] %||% character(0)
    )
    # C1 双保险：Boruta 结果再强制剔除分层键与 never_features
    sel <- setdiff(sel, c(
      if (is.null(stratum)) character(0) else as.character(stratum$variable),
      as.character(child$config$ml_frozen_bundle$never_features %||%
                     character(0))
    ))
    if (length(sel) >= 2L) {
      feats <- sel
      selector <- "boruta"
    } else {
      cli::cli_alert_warning(
        "ml_frozen: 层 {key} Boruta 入选 {length(sel)} 个特征（<2），本层回退候选全集。"
      )
    }
  } else {
    cli::cli_alert_info("ml_frozen: 层 {key} feature_selection$enable=FALSE，本层用候选全集 {length(cand)} 特征。")
  }
  feats <- unique(as.character(feats))
  # ml_rf 引擎网格固定 mtry<=10（Blocks/22 不改）；本层特征不足 10 列时用
  # 候选全集补齐到 10（仍限定在本层候选域内，Boruta 结果优先保留）。
  if ("rf" %in% methods && length(feats) < 10L) {
    extra <- setdiff(cand, feats)
    if (length(feats) + length(extra) >= 10L) {
      feats <- c(feats, utils::head(extra, 10L - length(feats)))
      cli::cli_alert_info(
        "ml_frozen: 层 {key} 特征 {length(feats)}（RF 网格需 mtry<=10 支持列）已用本层候选补齐。"
      )
    } else {
      stop("ml_frozen: 层 ", key, " 候选特征不足 10 个但含 rf；",
           "请扩充 Model2Factors 或去掉 rf。", call. = FALSE)
    }
  }
  child$results$feature_selection_final <- feats

  for (m in c("ml_dt", "ml_rf", "ml_xgboost", "ml_lightgbm", "ml_logistic",
              "feature_selection_boruta")) {
    child$config[[m]] <- modifyList(child$config[[m]] %||% list(),
                                    list(pause_enable = FALSE))
  }
  .ml_frozen_source_blocks(quiet = TRUE)

  trained <- character(0)
  failed <- character(0)
  for (m in methods) {
    fn_name <- paste0("block_ml_", m)
    fn <- get(fn_name, mode = "function")
    child <- tryCatch(fn(child), error = function(e) {
      cli::cli_alert_danger("ml_frozen: 层 {key} 模型 {m} 训练失败: {conditionMessage(e)}")
      child
    })
    if (is.null(child$results$ml_models[[m]])) {
      failed <- c(failed, m)
    } else {
      trained <- c(trained, m)
    }
  }
  if (length(failed)) {
    stop("ml_frozen: 层 ", key, " 以下模型训练失败: ",
         paste(failed, collapse = ", "), call. = FALSE)
  }

  lbl <- .ml_frozen_outcome_labels(child)
  ana <- lbl$analysis
  ref <- lbl$reference
  train_df <- child$data$train
  internal_df <- child$data$test
  if (!is.data.frame(train_df) || !nrow(train_df)) {
    stop("ml_frozen: 层 ", key, " train 为空。", call. = FALSE)
  }
  train_dat <- train_df[, c("Group", feats), drop = FALSE]
  factor_levels <- list()
  for (cn in feats) {
    col <- train_dat[[cn]]
    if (is.factor(col)) {
      factor_levels[[cn]] <- levels(col)
    } else if (is.character(col)) {
      stop("ml_frozen: 训练列 ", cn, " 为 character，请先在本课题上游定为 factor。",
           call. = FALSE)
    }
  }

  id_col <- as.character(child$config$data$id_column %||%
                           child$config$project$id_column %||% NA_character_)[1L]
  get_ids <- function(df) {
    if (!is.data.frame(df) || !nrow(df)) return(character(0))
    if (!is.na(id_col) && id_col %in% names(df)) {
      as.character(df[[id_col]])
    } else if (!is.na(child$config$data$id_column) && "ID" %in% names(df)) {
      as.character(df[["ID"]])
    } else {
      rownames(df)
    }
  }

  per_model <- list()
  perf_rows <- list()
  for (m in trained) {
    fit <- child$results$ml_models[[m]]
    scale_type <- if (exists("ml_dual_dev_ext_scale_for_tag", mode = "function")) {
      ml_dual_dev_ext_scale_for_tag(m)
    } else "none"
    rec <- .ml_frozen_build_recipe(train_dat, scale_type = scale_type)
    baked_all <- as.data.frame(recipes::bake(rec, new_data = NULL))
    baked_columns <- setdiff(names(baked_all), "Group")
    tr2 <- baked_all[, c("Group", baked_columns), drop = FALSE]
    pr_train <- as.data.frame(stats::predict(fit, new_data = tr2, type = "prob"))
    predtrain <- cbind(pr_train, data.frame(Group = tr2$Group))
    p_ana <- ml_dual_dev_ext_prob_ana(predtrain, ana)
    if (is.null(p_ana)) {
      stop("ml_frozen: 模型 ", m, " 无法在训练预测中找到事件概率列。", call. = FALSE)
    }
    youden_ana <- .ml_finite_youden(
      ml_dual_dev_ext_youden_from_train(predtrain, ana, ref)
    )
    youden_ref <- .ml_finite_youden(
      ml_dual_dev_ext_youden_from_train(predtrain, ref, ana)
    )
    ev <- child$results$ml_eval_by_model[[m]]
    if (is.data.frame(ev) && nrow(ev)) {
      ev_df <- as.data.frame(ev)
      keep <- intersect(c("model", "dataset", ".metric", ".estimate"), names(ev_df))
      if (all(c("dataset", ".metric", ".estimate") %in% names(ev_df))) {
        row <- ev_df[, keep, drop = FALSE]
        if (!"model" %in% names(row)) row$model <- m
        row$model <- as.character(m)
        row$dataset <- tolower(as.character(row$dataset))
        perf_rows[[length(perf_rows) + 1L]] <- row
      }
    }
    per_model[[m]] <- list(
      tag = m,
      model = fit,
      features = feats,
      recipe = rec,
      baked_columns = baked_columns,
      scale_type = scale_type,
      youden_train = as.numeric(youden_ana),
      youden_train_ref_axis = as.numeric(youden_ref),
      pred_ref_col = child$results$ml_pred_ref_col %||% paste0(".pred_", make.names(ref)),
      pred_ana_col = child$results$ml_pred_ana_col %||% paste0(".pred_", make.names(ana)),
      factor_levels = factor_levels
    )
  }
  performance <- do.call(rbind, perf_rows)
  if (!is.null(performance)) rownames(performance) <- NULL

  bundle <- list(
    schema_version = ml_frozen_bundle_schema_version(),
    stratum = if (is.null(stratum)) {
      list(key = "overall", label = "Overall", variable = NA_character_,
           lower = NA_real_, upper = NA_real_, operator = "none")
    } else {
      list(key = stratum$name, label = stratum$label, variable = stratum$variable,
           lower = stratum$lower, upper = stratum$upper, operator = stratum$operator)
    },
    methods = methods,
    features = feats,
    feature_selector = selector,
    factor_levels = factor_levels,
    outcome = lbl,
    train_ids = get_ids(train_df),
    internal_ids = get_ids(internal_df),
    counts = list(n_train = nrow(train_df),
                  n_internal = if (is.data.frame(internal_df)) nrow(internal_df) else 0L),
    models = per_model,
    performance = list(train_internal = performance),
    seed = as.integer(child$config$splitting$seed %||%
                        child$config$imputation$seed %||% NA_integer_)[1L],
    source_database = as.character(db_id %||% "MIMIC_IV")[1L],
    authority_checkpoint_path = as.character(
      ctx$results$authority_checkpoint_path %||%
        ctx$config$authority_checkpoint_path %||% NA_character_
    )[1L],
    built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    dir = NULL
  )
  bundle <- modifyList(bundle, .ml_frozen_versions_snapshot())
  class(bundle) <- "ml_frozen_bundle"
  bundle
}

#' 落盘：feature_manifest.rds + model_<tag>.rds + manifest.json（含逐文件 md5）。
#' 返回资产目录（model_assets/<stratum_key>）。
ml_save_frozen_bundle <- function(bundle, path) {
  if (!inherits(bundle, "ml_frozen_bundle")) {
    stop("ml_save_frozen_bundle: 需要 ml_fit_stratum_bundle() 产出的 bundle。",
         call. = FALSE)
  }
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  key <- bundle$stratum$key

  payload_models <- list()
  files <- list()
  model_checksums <- list()
  for (m in names(bundle$models)) {
    rec <- bundle$models[[m]]
    payload <- list(
      schema_version = bundle$schema_version,
      stratum_key = key,
      tag = m,
      model = rec$model,
      features = rec$features,
      recipe = rec$recipe,
      baked_columns = rec$baked_columns,
      scale_type = rec$scale_type,
      youden_train = rec$youden_train,
      youden_train_ref_axis = rec$youden_train_ref_axis,
      pred_ref_col = rec$pred_ref_col,
      pred_ana_col = rec$pred_ana_col,
      factor_levels = rec$factor_levels,
      outcome = bundle$outcome
    )
    fpath <- file.path(path, paste0("model_", m, ".rds"))
    md5 <- .ml_frozen_rds_checksum(payload, fpath)
    files[[paste0("model_", m, ".rds")]] <- md5
    model_checksums[[m]] <- md5
    payload_models[[m]] <- list(
      tag = m,
      file = paste0("model_", m, ".rds"),
      model_checksum = md5,
      features = rec$features,
      baked_columns = rec$baked_columns,
      scale_type = rec$scale_type,
      youden_train = rec$youden_train,
      youden_train_ref_axis = rec$youden_train_ref_axis
    )
  }

  feature_manifest <- list(
    schema_version = bundle$schema_version,
    stratum = bundle$stratum,
    methods = bundle$methods,
    features = bundle$features,
    feature_selector = bundle$feature_selector,
    factor_levels = bundle$factor_levels,
    outcome = bundle$outcome,
    train_ids = bundle$train_ids,
    internal_ids = bundle$internal_ids,
    counts = bundle$counts,
    performance = bundle$performance,
    seed = bundle$seed,
    source_database = bundle$source_database,
    authority_checkpoint_path = bundle$authority_checkpoint_path,
    built_at = bundle$built_at,
    r_version = bundle$r_version,
    package_versions = bundle$package_versions
  )
  fm_md5 <- .ml_frozen_rds_checksum(feature_manifest,
                                    file.path(path, "feature_manifest.rds"))
  files[["feature_manifest.rds"]] <- fm_md5

  manifest <- list(
    schema_version = bundle$schema_version,
    bundle_type = "ml_frozen_stratum_asset",
    stratum = bundle$stratum,
    methods = bundle$methods,
    features = bundle$features,
    feature_selector = bundle$feature_selector,
    factor_levels = bundle$factor_levels,
    outcome = bundle$outcome,
    counts = bundle$counts,
    seed = bundle$seed,
    source_database = bundle$source_database,
    authority_checkpoint_path = bundle$authority_checkpoint_path,
    built_at = bundle$built_at,
    r_version = bundle$r_version,
    package_versions = bundle$package_versions,
    files = files,
    feature_manifest_checksum = fm_md5,
    models = payload_models
  )
  writeLines(
    jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE, null = "null"),
    file.path(path, "manifest.json")
  )
  bundle$dir <- normalizePath(path, winslash = "/", mustWork = FALSE)
  invisible(bundle$dir)
}

.ml_frozen_verify_files <- function(path, manifest) {
  for (m in names(manifest$models)) {
    fpath <- file.path(path, paste0("model_", m, ".rds"))
    if (!file.exists(fpath)) {
      stop("frozen asset integrity check failed: missing file model_", m, ".rds",
           call. = FALSE)
    }
    want <- manifest$models[[m]]$model_checksum
    got <- unname(tools::md5sum(fpath))
    if (!identical(as.character(want), got)) {
      stop("frozen asset integrity check failed: checksum mismatch for model_",
           m, ".rds (manifest ", want, ", file ", got, ")", call. = FALSE)
    }
  }
  fm <- file.path(path, "feature_manifest.rds")
  if (!file.exists(fm)) {
    stop("frozen asset integrity check failed: missing feature_manifest.rds",
         call. = FALSE)
  }
  if (!identical(as.character(manifest$feature_manifest_checksum),
                 unname(tools::md5sum(fm)))) {
    stop("frozen asset integrity check failed: checksum mismatch for feature_manifest.rds",
         call. = FALSE)
  }
  invisible(TRUE)
}

#' 加载冻结资产：先做 md5 全量校验（篡改 manifest 或 payload 均拒绝），
#' 再返回可直接 ml_predict_external_bundle 的 bundle。
ml_load_frozen_bundle <- function(path, expected_stratum = NULL) {
  if (!dir.exists(path)) {
    stop("ml_load_frozen_bundle: 资产目录不存在: ", path, call. = FALSE)
  }
  mpath <- file.path(path, "manifest.json")
  if (!file.exists(mpath)) {
    stop("ml_load_frozen_bundle: 缺 manifest.json（禁止从 evalresult_*.RData 猜资产）。",
         call. = FALSE)
  }
  manifest <- jsonlite::fromJSON(mpath, simplifyVector = FALSE)
  if (!identical(manifest$schema_version, ml_frozen_bundle_schema_version())) {
    stop("ml_load_frozen_bundle: 资产 schema ", manifest$schema_version %||% "NA",
         " 与当前 ", ml_frozen_bundle_schema_version(),
         " 不匹配（旧 2 层 SOFA 资产需重训）。", call. = FALSE)
  }
  .ml_frozen_verify_files(path, manifest)
  fm <- readRDS(file.path(path, "feature_manifest.rds"))
  if (!identical(fm$stratum$key, manifest$stratum$key)) {
    stop("frozen asset integrity check failed: manifest/feature_manifest stratum mismatch",
         call. = FALSE)
  }
  models <- list()
  for (m in names(manifest$models)) {
    payload <- readRDS(file.path(path, paste0("model_", m, ".rds")))
    if (!identical(payload$stratum_key, manifest$stratum$key) ||
        !identical(payload$tag, m)) {
      stop("frozen asset integrity check failed: payload identity mismatch for ", m,
           call. = FALSE)
    }
    if (!identical(as.character(payload$features), unlist(manifest$features))) {
      stop("frozen asset integrity check failed: feature order mismatch for ", m,
           call. = FALSE)
    }
    models[[m]] <- list(
      tag = m,
      model = payload$model,
      features = payload$features,
      recipe = payload$recipe,
      baked_columns = payload$baked_columns,
      scale_type = payload$scale_type,
      youden_train = payload$youden_train,
      youden_train_ref_axis = payload$youden_train_ref_axis,
      pred_ref_col = payload$pred_ref_col,
      pred_ana_col = payload$pred_ana_col,
      factor_levels = payload$factor_levels
    )
  }
  bundle <- list(
    schema_version = manifest$schema_version,
    stratum = manifest$stratum,
    methods = unlist(manifest$methods),
    features = unlist(manifest$features),
    feature_selector = manifest$feature_selector,
    factor_levels = fm$factor_levels,
    outcome = list(analysis = manifest$outcome$analysis,
                   reference = manifest$outcome$reference),
    train_ids = fm$train_ids,
    internal_ids = fm$internal_ids,
    counts = list(n_train = as.integer(manifest$counts$n_train),
                  n_internal = as.integer(manifest$counts$n_internal)),
    models = models,
    performance = fm$performance,
    seed = fm$seed,
    source_database = manifest$source_database,
    authority_checkpoint_path = manifest$authority_checkpoint_path,
    built_at = manifest$built_at,
    r_version = manifest$r_version,
    package_versions = manifest$package_versions,
    dir = normalizePath(path, winslash = "/", mustWork = FALSE)
  )
  class(bundle) <- "ml_frozen_bundle"
  if (!is.null(expected_stratum)) {
    .ml_frozen_assert_stratum(bundle, expected_stratum)
  }
  bundle
}

#' eICU 等外验库：按层名只解析同名主库资产目录。
ml_resolve_stratum_asset <- function(assets_root, stratum_key) {
  stratum_key <- .ml_frozen_norm_id(stratum_key)
  if (!nzchar(stratum_key)) {
    stop("ml_resolve_stratum_asset: stratum_key is required.", call. = FALSE)
  }
  dir_path <- file.path(as.character(assets_root)[1L], stratum_key)
  if (!file.exists(file.path(dir_path, "manifest.json"))) {
    stop("No frozen asset for stratum '", stratum_key, "' at: ", dir_path,
         "（禁止扫描 evalresult_*.RData 猜层别）", call. = FALSE)
  }
  normalizePath(dir_path, winslash = "/", mustWork = FALSE)
}

.ml_frozen_assert_stratum <- function(bundle, stratum_key) {
  want <- .ml_frozen_norm_id(stratum_key)
  got <- .ml_frozen_norm_id(bundle$stratum$key)
  if (!identical(want, got)) {
    stop("Stratum inheritance violation: external stratum '", want,
         "' may only use the MIMIC asset of the same stratum (loaded '", got,
         "').", call. = FALSE)
  }
  invisible(TRUE)
}

#' 禁止性护栏：本模块从不递归扫描 evalresult_*.RData 推断层别。
#' 保留函数仅用于测试/审计：默认恒返回 character(0)。
ml_frozen_scan_evalresults <- function(dir = NULL, ...) {
  if (!isTRUE(getOption("ml_frozen_allow_evalresult_scan", FALSE))) {
    return(character(0))
  }
  character(0)
}

#' 冻结外验预测（不重训）。
#' - eICU 对应层只加载同名主库资产（bundle 必须是该层资产，stratum 参数强校验）
#' - 缺特征 → 硬失败并列出缺失列
#' - 未见因子水平 → 显式审计表（column/level/n_rows/action=level->NA），禁止静默改数值
ml_predict_external_bundle <- function(bundle, newdata, stratum = NULL,
                                       database = NULL, tags = NULL) {
  if (!inherits(bundle, "ml_frozen_bundle")) {
    stop("ml_predict_external_bundle: 需要 ml_frozen_bundle（ml_load_frozen_bundle 产物）。",
         call. = FALSE)
  }
  if (!is.data.frame(newdata) || !nrow(newdata)) {
    stop("ml_predict_external_bundle: newdata 需为非空 data.frame。", call. = FALSE)
  }
  if (!is.null(stratum)) .ml_frozen_assert_stratum(bundle, stratum)

  # I1: 数据级层归属校验——行必须属于资产定义的层（overall 无 variable/边界
  # 时跳过）。缺失分层变量值的行不计违例（记入 provenance 供审计）。成员判定
  # 统一走 ml_stratum_member()，兼容 (lower, upper] 边界与旧 cutoff/operator。
  n_variable_missing <- 0L
  s_var <- bundle$stratum$variable
  s_op <- as.character(bundle$stratum$operator %||% "none")
  s_has_bounds <- !is.null(bundle$stratum$lower) || !is.null(bundle$stratum$upper)
  s_has_cut <- is.finite(suppressWarnings(as.numeric(bundle$stratum$cutoff)[1L]))
  if (!is.null(s_var) && length(s_var) == 1L && !is.na(s_var) && nzchar(s_var) &&
      !s_op %in% c("none", NA_character_)) {
    if (!s_has_bounds && !s_has_cut) {
      stop("ml_predict_external_bundle: 资产层定义缺少边界/切点，无法校验成员。",
           call. = FALSE)
    }
    member <- ml_stratum_member(newdata[[s_var]], bundle$stratum)
    n_variable_missing <- sum(is.na(
      suppressWarnings(as.numeric(as.character(newdata[[s_var]])))
    ))
    n_violation <- sum(!member)
    if (n_violation > 0L) {
      stop("ml_predict_external_bundle: stratum membership violation — ",
           n_violation, " of ", nrow(newdata),
           " external rows do not belong to stratum '", bundle$stratum$key,
           "' (", bundle$stratum$label,
           "); load the matching stratum asset or filter the external data.",
           call. = FALSE)
    }
  }
  feats <- bundle$features
  missing_feats <- setdiff(feats, names(newdata))
  if (length(missing_feats)) {
    stop("ml_predict_external_bundle: external data missing feature columns: ",
         paste(missing_feats, collapse = ", "), call. = FALSE)
  }
  ana <- bundle$outcome$analysis
  ref <- bundle$outcome$reference

  audit_rows <- list()
  coerce_col <- function(col_name) {
    col <- newdata[[col_name]]
    frozen_levels <- bundle$factor_levels[[col_name]]
    if (!is.null(frozen_levels)) {
      raw <- trimws(as.character(col))
      unseen <- setdiff(unique(raw[!is.na(raw)]), frozen_levels)
      for (lv in unseen) {
        audit_rows[[length(audit_rows) + 1L]] <<- data.frame(
          column = col_name, level = lv,
          n_rows = sum(!is.na(raw) & raw == lv, na.rm = TRUE),
          action = "level->NA", stringsAsFactors = FALSE
        )
      }
      factor(raw, levels = frozen_levels)
    } else {
      # 训练列为 numeric：外验同列按文本->数值；非数值文本硬失败，不静默。
      raw <- trimws(as.character(col))
      num <- suppressWarnings(as.numeric(raw))
      bad <- !is.na(raw) & nzchar(raw) & is.na(num)
      if (any(bad)) {
        stop("ml_predict_external_bundle: 训练数值列 ", col_name,
             " 在外验含非数值文本（禁止静默改数值），示例: ",
             paste(utils::head(unique(raw[bad]), 3L), collapse = ", "),
             call. = FALSE)
      }
      num
    }
  }

  nd <- newdata[, feats, drop = FALSE]
  for (cn in feats) nd[[cn]] <- coerce_col(cn)
  factor_audit <- if (length(audit_rows)) {
    do.call(rbind, audit_rows)
  } else {
    data.frame(column = character(0), level = character(0),
               n_rows = integer(0), action = character(0),
               stringsAsFactors = FALSE)
  }
  rownames(factor_audit) <- NULL

  truth <- NULL
  if ("Group" %in% names(newdata)) {
    g_raw <- trimws(as.character(newdata$Group))
    truth_chr <- ifelse(g_raw == ana, ana, ifelse(g_raw == ref, ref, NA_character_))
    truth <- factor(truth_chr, levels = c(ref, ana))
  } else {
    oc <- as.character(bundle$source_outcome_column %||% "Death_label")
    hit <- intersect(c(oc, "fustatus", "Death_label"), names(newdata))
    if (length(hit)) {
      vals <- trimws(as.character(newdata[[hit[1L]]]))
      truth <- factor(ifelse(vals == ana, ana,
                             ifelse(vals == ref, ref, NA_character_)),
                      levels = c(ref, ana))
    }
  }
  nd$Group <- if (is.null(truth)) factor(rep(NA_character_, nrow(nd)),
                                         levels = c(ref, ana)) else truth

  predictions <- data.frame(row_index = seq_len(nrow(nd)),
                            stringsAsFactors = FALSE)
  if (!is.null(truth)) {
    predictions$truth <- as.integer(!is.na(truth) & as.character(truth) == ana)
  }
  prepared <- list()
  thresholds <- list()
  model_tags <- names(bundle$models)
  if (!is.null(tags)) {
    tags <- unique(as.character(tags))
    miss <- setdiff(tags, model_tags)
    if (length(miss)) {
      stop("ml_predict_external_bundle: tags not in bundle: ",
           paste(miss, collapse = ", "), call. = FALSE)
    }
    model_tags <- tags
  }
  for (m in model_tags) {
    rec <- bundle$models[[m]]
    baked <- tryCatch({
      bk <- as.data.frame(suppressWarnings(suppressMessages(
        recipes::bake(rec$recipe, new_data = nd)
      )))
      bk[, c("Group", rec$baked_columns), drop = FALSE]
    }, error = function(e) {
      stop("ml_predict_external_bundle: 模型 ", m, " bake 失败: ",
           conditionMessage(e), call. = FALSE)
    })
    prepared[[m]] <- list(baked = baked)
    pr <- tryCatch(
      as.data.frame(stats::predict(rec$model, new_data = baked, type = "prob")),
      error = function(e) {
        stop("ml_predict_external_bundle: 模型 ", m, " 冻结预测失败: ",
             conditionMessage(e), call. = FALSE)
      }
    )
    p_ana <- ml_dual_dev_ext_prob_ana(pr, ana)
    if (is.null(p_ana) || length(p_ana) != nrow(nd)) {
      stop("ml_predict_external_bundle: 模型 ", m, " 找不到事件概率列。",
           call. = FALSE)
    }
    predictions[[m]] <- as.numeric(p_ana)
    thr <- suppressWarnings(as.numeric(rec$youden_train[1L]))
    if (!is.finite(thr)) thr <- 0.5
    thresholds[[m]] <- thr
    if (!is.null(truth)) {
      predictions[[paste0(m, "__pred_class")]] <-
        ifelse(p_ana >= thr, ana, ref)
    }
  }
  predictions$dataset <- "external"
  list(
    predictions = predictions,
    prepared = prepared,
    factor_audit = factor_audit,
    thresholds = thresholds,
    truth = truth,
    provenance = list(
      stratum = bundle$stratum$key,
      stratum_label = bundle$stratum$label,
      n_variable_missing = n_variable_missing,
      asset_dir = bundle$dir %||% NA_character_,
      source_database = bundle$source_database,
      external_database = as.character(database %||% NA_character_)[1L],
      r_version = bundle$r_version,
      no_refit = TRUE,
      no_boruta = TRUE
    )
  )
}

#' 外验性能长表（Table S11 口径：与 ml_dual_dev_ext_eval_metrics 同实现）。
ml_frozen_external_metrics <- function(bundle, result, dataset = "external") {
  w <- as.data.frame(result$predictions)
  models <- names(bundle$models)
  if (!"truth" %in% names(w)) {
    stop("ml_frozen_external_metrics: predictions 缺 truth 列（外验需结局）。",
         call. = FALSE)
  }
  w$D <- w$truth
  ok <- is.finite(w$D) &
    rowSums(vapply(models, function(m) is.finite(as.numeric(w[[m]])),
                   logical(nrow(w)))) == length(models)
  w <- w[ok, , drop = FALSE]
  if (!nrow(w)) {
    stop("ml_frozen_external_metrics: 无完整结局+概率行。", call. = FALSE)
  }
  ml_dual_dev_ext_eval_metrics(w, models, dataset = dataset,
                               thresh = result$thresholds)
}

#' train/internal/external 三集长表拼接（Table S11 行结构）。
ml_frozen_bind_performance <- function(bundle, external_metrics = NULL) {
  parts <- list()
  ti <- bundle$performance$train_internal
  if (is.data.frame(ti) && nrow(ti)) {
    ti <- as.data.frame(ti)
    ti$dataset <- ifelse(ti$dataset == "train", "train", "internal_validation")
    ti$stratum <- bundle$stratum$label
    parts[[length(parts) + 1L]] <- ti
  }
  if (!is.null(external_metrics) && nrow(external_metrics)) {
    em <- as.data.frame(external_metrics)
    em$dataset <- "external_validation"
    em$stratum <- bundle$stratum$label
    parts[[length(parts) + 1L]] <- em
  }
  if (!length(parts)) return(NULL)
  out <- do.call(rbind, parts)
  rownames(out) <- NULL
  out
}
