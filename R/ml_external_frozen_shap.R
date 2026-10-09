###############################################################################
#  ml_external_frozen_shap.R — AKI SOSM+WPR 原文复刻 Task 6
#  分层 / overall 的 Boruta、SHAP（冻结模型）与个体解释面板：
#  Figure 7、Figure 8、Figure S2–S5（staging 单 PDF；四格式留 Task 7/8）。
#
#  铁律（对齐 ml_prognosis_pub_reuse / tst_methods_leakage_denom_gate）：
#   - eICU 解释只用 MIMIC-IV 冻结资产（Task5 ml_load_frozen_bundle）：
#     解释前复算 model_<tag>.rds payload 的 md5，必须等于 manifest.json 中该
#     tag 的 model_checksum —— 证明被解释的模型对象与落盘冻结模型字节一致，
#     非本库重训；
#   - bake 口径与 Task5 ml_predict_external_bundle 完全一致：bundle 训练帧
#     的 prepped recipe + baked_columns 列序 + 因子水平强制转换；
#   - 面板内 AUC 一律 sklearn 同口径的 pROC 仅作图形；性能数字（3/3/2/4）
#     走 pub_format_est；SHAP 内核只 source 复用 Blocks/17_shap/00shap_router
#     (.shap_compute_for_tag / .shap_method_for_tag)，不改内核；
#   - 分类列在 linear_coef / tree_shapviz 路径按引擎 baked 数值矩阵处理；
#     因子水平由冻结 recipe 统一 dummy 化（列名回映 features 见
#     ml_shap_backmap_features）；
#   - 个体 waterfall 的 survivor/non-survivor 案例只允许来自「本库本层」
#     （ml_pick_paired_cases 按 database x stratum 分组，缺类硬失败）。
#
#  面板规格（docs/superpowers/specs/2026-09-17-aki-sosm-wpr-...-design.md）：
#   - Figure 7：MIMIC-IV SOFA<=10 / >=11 两层 Boruta Z-score boxplot（2 面板；
#     eICU 禁止重做特征选择）。
#   - Figure 8：数据库 x SOFA 层网格（fixture=2x2），每格 最优模型 ROC +
#     SHAP beeswarm + importance bar（原文 Fig8 D–I 口径）。
#   - S2：MIMIC-IV overall Boruta（1 面板）。
#   - S3：overall 五模型 ROC 叠在同一坐标（原文 Fig.S3）；双库左右 A/B。
#   - S4：overall 最优冻结模型双库 SHAP（beeswarm + importance，2 面板）。
#   - S5：双库两层 survivor/non-survivor 个体 waterfall（2 库 x 2 层 x 2 结局）。
###############################################################################

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}

# patchwork 的 `|` / `/` 方法只在 patchwork 被 ATTACH 后才注册；本模块的
# 面板拼图统一依赖它（source 本文件的环境可能只 loadNamespace 过 patchwork）。
if (requireNamespace("patchwork", quietly = TRUE) &&
    !"package:patchwork" %in% search()) {
  suppressPackageStartupMessages(attachNamespace(asNamespace("patchwork")))
}

# --------------------------------------------------------------------------
# engine router (source-only, never modified)
# --------------------------------------------------------------------------

.ml_fshap_router_env <- new.env(parent = globalenv())

ml_fshap_router <- function() {
  if (!exists(".shap_compute_for_tag", envir = .ml_fshap_router_env,
              inherits = FALSE)) {
    root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
    if (!nzchar(root)) root <- normalizePath(".", winslash = "/")
    if (.Platform$OS.type != "windows" && grepl("^[A-Za-z]:/", root)) {
      root <- paste0("/mnt/", tolower(substr(root, 1L, 1L)), substring(root, 3L))
    }
    f <- file.path(root, "Blocks/17_shap/00shap_router.R")
    if (!file.exists(f)) stop("缺少 SHAP 路由源码: ", f, call. = FALSE)
    # router 依赖 %||%；在独立 env 里 source，避免污染/覆盖全局同名函数
    assign("%||%", (function(a, b) if (!is.null(a)) a else b),
           envir = .ml_fshap_router_env)
    sys.source(f, envir = .ml_fshap_router_env)
  }
  .ml_fshap_router_env
}

.ml_fshap_compute <- function(tag, wf, baked, sh_cfg) {
  env <- ml_fshap_router()
  get(".shap_compute_for_tag", envir = env)(tag, wf, baked, sh_cfg)
}

.ml_fshap_method <- function(tag, wf) {
  get(".shap_method_for_tag", envir = ml_fshap_router())(tag, wf)
}

# --------------------------------------------------------------------------
# frozen-baked frame (byte-identical bake path to ml_predict_external_bundle)
# --------------------------------------------------------------------------

#' 用冻结 recipe bake 外验/内验帧（与 Task5 预测路径同一强制转换：
#' 因子按训练水平 factor(levels)，数值列禁文本）。返回 baked data.frame
#' （含 Group 与 baked_columns）与 row_index。
.ml_fshap_bake <- function(bundle, rec, newdata) {
  feats <- bundle$features
  missing_feats <- setdiff(feats, names(newdata))
  if (length(missing_feats)) {
    stop("ml_shap_from_frozen_bundle: data missing feature columns: ",
         paste(missing_feats, collapse = ", "), call. = FALSE)
  }
  ana <- bundle$outcome$analysis
  ref <- bundle$outcome$reference
  nd <- newdata[, feats, drop = FALSE]
  for (cn in feats) {
    col <- nd[[cn]]
    frozen_levels <- bundle$factor_levels[[cn]]
    if (!is.null(frozen_levels)) {
      nd[[cn]] <- factor(trimws(as.character(col)), levels = frozen_levels)
    } else {
      raw <- trimws(as.character(col))
      num <- suppressWarnings(as.numeric(raw))
      bad <- !is.na(raw) & nzchar(raw) & is.na(num)
      if (any(bad)) {
        stop("ml_shap_from_frozen_bundle: 训练数值列 ", cn,
             " 含非数值文本（禁止静默改数值）。", call. = FALSE)
      }
      nd[[cn]] <- num
    }
  }
  g_raw <- if ("Group" %in% names(newdata)) trimws(as.character(newdata$Group)) else NA_character_
  nd$Group <- factor(ifelse(g_raw == ana, ana, ifelse(g_raw == ref, ref, NA_character_)),
                     levels = c(ref, ana))
  baked <- tryCatch({
    bk <- as.data.frame(suppressWarnings(suppressMessages(
      recipes::bake(rec$recipe, new_data = nd)
    )))
    bk[, c("Group", rec$baked_columns), drop = FALSE]
  }, error = function(e) {
    stop("ml_shap_from_frozen_bundle: 模型 ", rec$tag, " bake 失败: ",
         conditionMessage(e), call. = FALSE)
  })
  list(nd = nd, baked = baked)
}

# --------------------------------------------------------------------------
# 1) SHAP from frozen bundle
# --------------------------------------------------------------------------

#' 从冻结资产取指定/最优 tag 模型 + 其 recipe，用训练帧同口径 bake newdata，
#' 调引擎 .shap_compute_for_tag 得 shapviz。
#'
#' 关键断言（写进返回值，供测试）：解释所用模型对象的「落盘复算校验和」
#' == manifest 里该 tag 的 model_checksum == 实际 model_<tag>.rds 文件 md5。
#' 由于 Task5 的 .ml_frozen_rds_checksum 就是 saveRDS+md5，本函数把当前内存
#' 中的 payload 重新 saveRDS 到临时文件并 md5，与 manifest 比对——不一致即
#' 证明模型非冻结原物，硬失败。
#'
#' @param bundle ml_load_frozen_bundle()（或 ml_fit_stratum_bundle() 内存件）
#' @param newdata 本库本层（overall 时本库）数据帧，含 bundle$features
#' @param tag 模型 tag；NULL=按验证集最优（ml_frozen_best_tag）
#' @param sample_n 解释样本上限（行序确定性：truth 已知时先事件后非事件各
#'        按 prob 降/升取半，保证个体 waterfall 行必在解释矩阵内）
#' @param stratum 可选强校验（同 Task5：层不符 / 行不属层 → 硬失败）
#' 数据级层归属校验（与 Task5 I1 同口径）：newdata 含资产层 variable 时，
#' 违例（行不属该层）→ 硬失败。
.ml_fshap_assert_membership <- function(bundle, newdata) {
  s_var <- bundle$stratum$variable
  s_op <- as.character(bundle$stratum$operator %||% "none")
  s_has_bounds <- !is.null(bundle$stratum$lower) || !is.null(bundle$stratum$upper)
  s_has_cut <- is.finite(suppressWarnings(as.numeric(bundle$stratum$cutoff)[1L]))
  if (is.null(s_var) || !length(s_var) || is.na(s_var) || !nzchar(s_var) ||
      s_op %in% c("none", NA_character_)) {
    return(invisible(TRUE))
  }
  if (!s_has_bounds && !s_has_cut) {
    stop("ml_shap_from_frozen_bundle: 资产层定义缺少边界/切点，无法校验成员。",
         call. = FALSE)
  }
  if (!s_var %in% names(newdata)) return(invisible(TRUE))
  member <- ml_stratum_member(newdata[[s_var]], bundle$stratum)
  n_violation <- sum(!member)
  if (n_violation > 0L) {
    stop("ml_shap_from_frozen_bundle: stratum membership violation — ",
         n_violation, " of ", nrow(newdata),
         " rows do not belong to stratum '", bundle$stratum$key, "' (",
         bundle$stratum$label, ").", call. = FALSE)
  }
  invisible(TRUE)
}

ml_shap_from_frozen_bundle <- function(bundle, newdata, tag = NULL,
                                       sample_n = 200L, stratum = NULL) {
  if (!inherits(bundle, "ml_frozen_bundle")) {
    stop("ml_shap_from_frozen_bundle: 需要 ml_frozen_bundle。", call. = FALSE)
  }
  if (!is.data.frame(newdata) || !nrow(newdata)) {
    stop("ml_shap_from_frozen_bundle: newdata 需为非空 data.frame。",
         call. = FALSE)
  }
  .ml_fshap_assert_membership(bundle, newdata)
  if (!is.null(stratum)) {
    if (!exists(".ml_frozen_assert_stratum", mode = "function")) {
      stop("需要 R/ml_frozen_model_bundle.R（Task5）已 source。", call. = FALSE)
    }
    get(".ml_frozen_assert_stratum")(bundle, stratum)
  }
  tag <- if (is.null(tag)) ml_frozen_best_tag(bundle) else tag
  if (is.null(tag) || !nzchar(tag)) {
    stop("ml_shap_from_frozen_bundle: 未指定 tag 且 bundle 无验证集性能可判最优。",
         call. = FALSE)
  }
  if (is.null(bundle$models[[tag]])) {
    stop("ml_shap_from_frozen_bundle: tag '", tag,
         "' not in frozen bundle (available: ",
         paste(names(bundle$models), collapse = ", "), ").", call. = FALSE)
  }
  rec <- bundle$models[[tag]]

  # ---- frozen identity: file md5 == manifest; in-memory model == asset model
  ident <- .ml_fshap_identity(bundle, tag)
  recomputed <- ident$checksum
  want <- ident$manifest

  # ---- deterministically choose explained rows ----
  n_all <- nrow(newdata)
  sample_n <- as.integer(sample_n %||% 200L)[1L]
  row_index <- seq_len(n_all)
  has_truth <- "Group" %in% names(newdata) &&
    any(!is.na(match(trimws(as.character(newdata$Group)),
                     c(bundle$outcome$analysis, bundle$outcome$reference))) &
          trimws(as.character(newdata$Group)) %in%
          c(bundle$outcome$analysis, bundle$outcome$reference))
  if (n_all > sample_n && has_truth) {
    # 先用全帧冻结预测的 prob 选「高置信事件 + 高置信非事件」各半，
    # 剩余配额随机（seed 固定），个体 waterfall 行必落在解释矩阵内。
    pr_all <- tryCatch(
      ml_predict_external_bundle(bundle, newdata, stratum = NULL)$predictions[[tag]],
      error = function(e) NULL
    )
    if (!is.null(pr_all) && length(pr_all) == n_all) {
      ev <- bundle$outcome$analysis
      truth <- as.integer(trimws(as.character(newdata$Group)) == ev)
      i_ev <- which(truth == 1L & is.finite(pr_all))
      i_no <- which(truth == 0L & is.finite(pr_all))
      k_ev <- min(length(i_ev), ceiling(sample_n / 2))
      k_no <- min(length(i_no), sample_n - k_ev)
      k_ev <- min(length(i_ev), sample_n - k_no)
      sel_ev <- i_ev[order(-pr_all[i_ev])][seq_len(k_ev)]
      sel_no <- i_no[order(pr_all[i_no])][seq_len(k_no)]
      rest <- setdiff(row_index, c(sel_ev, sel_no))
      take <- sample_n - length(sel_ev) - length(sel_no)
      if (take > 0 && length(rest)) {
        set.seed(42L)
        sel_ev <- c(sel_ev, sample(rest, min(take, length(rest))))
      }
      row_index <- sort(unique(c(sel_ev, sel_no)))
      row_index <- row_index[seq_len(min(length(row_index), sample_n))]
    } else {
      set.seed(42L)
      row_index <- sort(sample(row_index, sample_n))
    }
  } else if (n_all > sample_n) {
    set.seed(42L)
    row_index <- sort(sample(row_index, sample_n))
  }

  sub <- newdata[row_index, , drop = FALSE]
  bak <- .ml_fshap_bake(bundle, rec, sub)
  baked_df <- bak$baked
  X_df <- baked_df[, rec$baked_columns, drop = FALSE]
  for (cn in names(X_df)) {
    col <- X_df[[cn]]
    if (is.factor(col) || is.character(col)) {
      X_df[[cn]] <- as.numeric(factor(col))
    } else if (is.logical(col)) {
      X_df[[cn]] <- as.integer(col)
    } else {
      X_df[[cn]] <- suppressWarnings(as.numeric(col))
    }
  }
  X_mat <- as.matrix(X_df)
  storage.mode(X_mat) <- "double"
  colnames(X_mat) <- rec$baked_columns
  # 子样本内 1..n 行号；kernel SHAP 再二次抽样后经 shap_source_row_ids 回映
  attr(X_df, "shap_source_row_ids") <- seq_along(row_index)
  baked <- list(X_mat = X_mat, X_df = X_df)

  sh_cfg <- bundle$shap_config %||% list()
  # kernel 默认 explain_n≈60，小于上游 sample_n 时会导致 row_id 越界；抬到子样本规模
  if (is.null(sh_cfg$kernel_explain_n)) {
    sh_cfg$kernel_explain_n <- as.integer(length(row_index))
  }
  shp <- .ml_fshap_compute(tag, rec$model, baked, sh_cfg)
  attr(shp, "frozen_model_checksum") <- recomputed
  attr(shp, "frozen_stratum") <- bundle$stratum$key
  attr(shp, "frozen_source_database") <- bundle$source_database

  pred_prob <- tryCatch(
    as.numeric(ml_predict_external_bundle(
      bundle, newdata[row_index, , drop = FALSE],
      stratum = NULL, tags = tag
    )$predictions[[tag]]),
    error = function(e) {
      warning("ml_shap_from_frozen_bundle: pred_prob failed for tag=", tag,
              ": ", conditionMessage(e), call. = FALSE)
      rep(NA_real_, length(row_index))
    }
  )
  if (!any(is.finite(pred_prob))) {
    stop("ml_shap_from_frozen_bundle: pred_prob all non-finite for tag=",
         tag, "（S5 选例依赖预测概率；请确保已 source R/ml_dual_dev_ext.R）",
         call. = FALSE)
  }
  truth_vec <- if ("Group" %in% names(sub)) {
    as.integer(trimws(as.character(sub$Group)) == bundle$outcome$analysis)
  } else {
    rep(NA_integer_, nrow(sub))
  }

  # 铁律：返回的 truth/prob/row_index 长度必须 == SHAP 矩阵行数（waterfall row_id 1..n）
  sv_n <- tryCatch(nrow(shapviz::get_shap_values(shp)),
                   error = function(e) NA_integer_)
  src_sub <- attr(shp, "shap_source_row_ids")
  if (is.finite(sv_n) && sv_n > 0L) {
    if (!is.null(src_sub) && length(src_sub) == sv_n &&
        all(is.finite(src_sub)) &&
        all(src_sub >= 1L & src_sub <= length(row_index))) {
      keep <- as.integer(src_sub)
      row_index <- row_index[keep]
      pred_prob <- pred_prob[keep]
      truth_vec <- truth_vec[keep]
    } else if (sv_n < length(row_index)) {
      keep <- seq_len(sv_n)
      row_index <- row_index[keep]
      pred_prob <- pred_prob[keep]
      truth_vec <- truth_vec[keep]
    }
  }
  if (length(row_index) != length(truth_vec) ||
      length(row_index) != length(pred_prob) ||
      (is.finite(sv_n) && length(row_index) != sv_n)) {
    stop("ml_shap_from_frozen_bundle: SHAP 元数据与矩阵行数不对齐 ",
         "(row_index=", length(row_index), ", truth=", length(truth_vec),
         ", pred=", length(pred_prob), ", shap=", sv_n, ").", call. = FALSE)
  }

  list(
    shp = shp,
    tag = tag,
    shap_method = attr(shp, "shap_method"),
    model_checksum = recomputed,
    manifest_checksum = if (is.null(want)) NA_character_ else want,
    stratum = bundle$stratum$key,
    features = as.character(bundle$features),
    baked_columns = as.character(rec$baked_columns),
    row_index = as.integer(row_index),
    pred_prob = as.numeric(pred_prob),
    truth = as.integer(truth_vec),
    source_database = bundle$source_database,
    no_refit = TRUE
  )
}

#' 当前内存 payload 复算校验和（与 Task5 落盘口径一致：同字段同序 saveRDS）。
.ml_fshap_payload <- function(bundle, tag) {
  rec <- bundle$models[[tag]]
  list(
    schema_version = bundle$schema_version %||%
      ml_frozen_bundle_schema_version(),
    stratum_key = bundle$stratum$key,
    tag = tag,
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
}

#' 对象内容摘要：serialize(xdr=TRUE)→临时文件→md5。对「从冻结 .rds
#' readRDS 而来」的对象，该摘要在内存-文件间稳定（两侧同为反序列化产物），
#' 不受 saveRDS gzip 时间戳影响——这是文件级 md5 无法重复计算的根本原因。
.ml_fshap_digest <- function(object) {
  tf <- tempfile()
  on.exit(unlink(tf), add = TRUE)
  con <- file(tf, "wb")
  serialize(object, con = con, xdr = TRUE)
  close(con)
  unname(tools::md5sum(tf))
}

#' 冻结模型身份核验（Task6 关键断言的实现）：
#'  1) 资产文件 md5 == manifest.model_checksum（文件未被篡改）；
#'  2) 内存模型对象 serialize 摘要 == 资产文件内模型摘要（解释的就是冻结件，
#'     不是任何重训/改系数的对象）；
#'  3) 返回文件级 checksum（= manifest 值）供上层报告。
#' dir 缺失（内存 fit 件、未落盘）时退化为 payload saveRDS+md5 自校验。
.ml_fshap_identity <- function(bundle, tag) {
  dir <- bundle$dir %||% NULL
  if (is.null(dir) || !nzchar(dir)) {
    tf <- tempfile(fileext = ".rds")
    on.exit(unlink(tf), add = TRUE)
    saveRDS(.ml_fshap_payload(bundle, tag), tf)
    return(list(checksum = unname(tools::md5sum(tf)),
                manifest = NA_character_,
                digest = .ml_fshap_digest(bundle$models[[tag]]$model),
                asset_digest = NA_character_))
  }
  fp <- file.path(dir, paste0("model_", tag, ".rds"))
  if (!file.exists(fp)) {
    stop("frozen model identity check failed: missing ", basename(fp),
         call. = FALSE)
  }
  got_file <- unname(tools::md5sum(fp))
  man <- .ml_fshap_manifest_checksum(bundle, tag)
  if (!is.null(man) && !identical(got_file, man)) {
    stop("frozen model identity check failed: asset file ",
         "model_", tag, ".rds md5 ", got_file,
         " != manifest model_checksum ", man,
         "（eICU 只允许解释 MIMIC 冻结模型）。", call. = FALSE)
  }
  payload_file <- readRDS(fp)
  asset_digest <- .ml_fshap_digest(payload_file$model)
  mem_digest <- .ml_fshap_digest(bundle$models[[tag]]$model)
  if (!identical(mem_digest, asset_digest)) {
    stop("frozen model identity check failed: in-memory model for ", tag,
         " (digest ", mem_digest, ") differs from the frozen asset model (",
         asset_digest, ") —— 解释禁用非冻结/被改动的模型对象。",
         call. = FALSE)
  }
  list(checksum = got_file,
       manifest = if (is.null(man)) NA_character_ else man,
       digest = mem_digest, asset_digest = asset_digest)
}

.ml_fshap_manifest_checksum <- function(bundle, tag) {
  dir <- bundle$dir %||% NULL
  if (is.null(dir) || !nzchar(dir)) return(NULL)
  mp <- file.path(dir, "manifest.json")
  if (!file.exists(mp)) return(NULL)
  man <- jsonlite::fromJSON(mp, simplifyVector = FALSE)
  v <- man$models[[tag]]$model_checksum
  if (is.null(v)) NULL else as.character(v)
}

#' SHAP 矩阵列（baked dummy 名）回映 bundle 特征名。
#' 规则：数值列直接同名；factor dummy `Name_Level` 按最长前缀匹配特征名
#' （特征名本身含下划线也可，取能匹配上的最长特征名）。
ml_shap_backmap_features <- function(columns, features) {
  features <- as.character(features)
  map <- vapply(columns, function(cn) {
    if (cn %in% features) return(cn)
    hit <- features[vapply(features, function(f)
      startsWith(cn, paste0(f, "_")), logical(1))]
    if (!length(hit)) return(NA_character_)
    hit[which.max(nchar(hit))]
  }, character(1), USE.NAMES = FALSE)
  data.frame(column = as.character(columns), feature = map,
             stringsAsFactors = FALSE)
}

# --------------------------------------------------------------------------
# 2) best tag from frozen performance (validation/internal optimum)
# --------------------------------------------------------------------------

#' 冻结资产「验证集最优」tag：performance$train_internal 中
#' dataset ∈ {internal_validation|test|validation} 且 .metric ∈
#' {roc_auc,c_index} 的最大值；并列时按树模型偏好序（与引擎
#' .shap_resolve_model_tag 同精神）。无性能 → NULL。
ml_frozen_best_tag <- function(bundle) {
  perf <- bundle$performance$train_internal
  if (!is.data.frame(perf) || !nrow(perf)) return(NULL)
  ds <- tolower(as.character(perf$dataset))
  ok_ds <- ds %in% c("internal_validation", "test", "validation", "internal")
  ok_m <- tolower(as.character(perf$.metric)) %in% c("roc_auc", "c_index")
  sub <- perf[ok_ds & ok_m & is.finite(suppressWarnings(as.numeric(perf$.estimate))), ,
              drop = FALSE]
  if (!nrow(sub)) return(NULL)
  sub$.estimate <- as.numeric(sub$.estimate)
  sub$model <- tolower(trimws(as.character(sub$model)))
  sub <- sub[sub$model %in% names(bundle$models), , drop = FALSE]
  if (!nrow(sub)) return(NULL)
  best_est <- max(sub$.estimate)
  tie <- sub[sub$.estimate >= best_est - 1e-9, , drop = FALSE]
  preferred <- c("xgboost", "lightgbm", "rf", "catboost", "dt", "adaboost",
                 "logistic")
  hit <- preferred[preferred %in% unique(tie$model)]
  if (length(hit)) return(hit[[1L]])
  tie$model[[1L]]
}

# --------------------------------------------------------------------------
# 3) paired survivor / non-survivor cases (own db, own stratum, never borrow)
# --------------------------------------------------------------------------

#' 从预测长表（database / stratum / row_id / truth(0=event|1) / prob）为每库
#' 每层各选一个 Survivor 与一个 Non-survivor 真实 row_id。
#' 选择规则（个体解释要「高置信代表」）：Non-survivor = 该类内 prob 最高者；
#' Survivor = 该类内 prob 最低者。缺任一类 → 硬失败（禁止跨层/跨库借样）。
#'
#' @param predictions data.frame：至少 row_id、truth（1=Non-survivor/event）、
#'        prob；database、stratum 可缺（视为单库单层）。
#' @param outcome 可选标签覆盖（默认 Survivor / Non-survivor）
#' @param stratum 可选：只在这些层里选
#' @param n 每类每层人数（本课题原文 =1；>1 时按置信度次序取前 n）
ml_pick_paired_cases <- function(predictions, outcome = NULL, stratum = NULL,
                                 n = 1L) {
  p <- as.data.frame(predictions)
  need <- c("row_id", "truth", "prob")
  miss <- setdiff(need, names(p))
  if (length(miss)) {
    stop("ml_pick_paired_cases: predictions 缺列: ",
         paste(miss, collapse = ", "), call. = FALSE)
  }
  if (!"database" %in% names(p)) p$database <- NA_character_
  if (!"stratum" %in% names(p)) p$stratum <- "overall"
  p$database <- as.character(p$database)
  p$stratum <- as.character(p$stratum)
  if (!is.null(stratum)) {
    p <- p[p$stratum %in% as.character(stratum), , drop = FALSE]
    if (!nrow(p)) stop("ml_pick_paired_cases: stratum 过滤后为空。",
                       call. = FALSE)
  }
  p$truth <- as.integer(p$truth)
  p$prob <- suppressWarnings(as.numeric(p$prob))
  p <- p[is.finite(p$prob) & !is.na(p$truth), , drop = FALSE]

  lbl <- outcome %||% c(Survivor = "Survivor", `Non-survivor` = "Non-survivor")
  ev_lab <- as.character(lbl[["Non-survivor"]] %||% "Non-survivor")
  no_lab <- as.character(lbl[["Survivor"]] %||% "Survivor")
  n <- as.integer(n)[1L]

  rows <- list()
  groups <- unique(p[, c("database", "stratum"), drop = FALSE])
  for (gi in seq_len(nrow(groups))) {
    db <- as.character(groups[gi, 1L]); sk <- as.character(groups[gi, 2L])
    sub <- p[p$database == db & p$stratum == sk, , drop = FALSE]
    for (cls in c(no_lab, ev_lab)) {
      want <- if (identical(cls, ev_lab)) 1L else 0L
      cand <- sub[sub$truth == want, , drop = FALSE]
      if (!nrow(cand)) {
        stop("ml_pick_paired_cases: no rows with outcome '", cls,
             "' in database '", db, "' stratum '", sk,
             "' —— 禁止跨库/跨层借样。", call. = FALSE)
      }
      cand <- cand[if (want == 1L) order(-cand$prob) else order(cand$prob), ,
                   drop = FALSE]
      take <- utils::head(cand, min(n, nrow(cand)))
      for (i in seq_len(nrow(take))) {
        rows[[length(rows) + 1L]] <- data.frame(
          database = db, stratum = sk, outcome_class = cls,
          row_id = as.integer(take$row_id[i]),
          prob = as.numeric(take$prob[i]),
          stringsAsFactors = FALSE
        )
      }
    }
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

# --------------------------------------------------------------------------
# shared figure plumbing
# --------------------------------------------------------------------------

.ml_fshap_save <- function(plot, out_pdf, width, height) {
  if (is.null(out_pdf)) return(NULL)
  dir.create(dirname(out_pdf), recursive = TRUE, showWarnings = FALSE)
  pipeline_ggsave_pdf(out_pdf, plot, width = width, height = height)
  normalizePath(out_pdf, winslash = "/", mustWork = FALSE)
}

.ref_theme <- ggplot2::theme_bw(base_size = 8) +
  ggplot2::theme(panel.grid.minor = ggplot2::element_blank(),
                 legend.position = "bottom")

#' pROC 曲线 + AUC(95%CI Delong) —— 与 Task4 Figure 4 同口径的图形行。
ml_ref_roc_rows <- function(prob, truth, dataset = NA_character_,
                            model = NA_character_, stratum = NA_character_,
                            database = NA_character_) {
  prob <- as.numeric(prob); truth <- as.integer(truth)
  ok <- is.finite(prob) & !is.na(truth)
  prob <- prob[ok]; truth <- truth[ok]
  if (length(unique(truth)) < 2L || length(unique(prob)) < 2L) {
    return(list(auc = NA_real_, ci_low = NA_real_, ci_high = NA_real_,
                curve = NULL, status = "not_estimable"))
  }
  if (!requireNamespace("pROC", quietly = TRUE)) {
    stop("Package 'pROC' is required for reference ROC panels.", call. = FALSE)
  }
  ro <- pROC::roc(truth, prob, direction = "auto", quiet = TRUE)
  ci <- as.numeric(suppressWarnings(
    pROC::ci.auc(ro, conf.level = 0.95, method = "delong", quiet = TRUE)
  ))
  cc <- pROC::coords(ro, x = "all",
                     ret = c("specificity", "sensitivity"), transpose = FALSE)
  list(
    auc = as.numeric(pROC::auc(ro)),
    ci_low = ci[1], ci_high = ci[3],
    curve = data.frame(fpr = 1 - cc$specificity, tpr = cc$sensitivity,
                       dataset = dataset, model = model,
                       stratum = stratum, database = database,
                       stringsAsFactors = FALSE),
    status = "estimable"
  )
}

#' shapviz importance(beeswarm/bar) 通用包装（统一主题 + 标题）。
.ml_fshap_plot <- function(shp, kind, title) {
  p <- if (identical(kind, "bee")) {
    tryCatch(shapviz::sv_importance(shp, kind = "bee", show_numbers = FALSE,
                                    max_display = 20L),
             error = function(e) shapviz::sv_importance(shp, kind = "bee"))
  } else {
    tryCatch(shapviz::sv_importance(shp, kind = "bar", max_display = 20L),
             error = function(e) shapviz::sv_importance(shp))
  }
  p + ggplot2::labs(title = title) + .ref_theme
}

.ml_fshap_force <- function(shp, row_id, title) {
  if (row_id < 1L || row_id > nrow(shapviz::get_shap_values(shp))) {
    stop("force row_id ", row_id, " outside SHAP matrix.", call. = FALSE)
  }
  # 第一色=正向（S>=0，粉），第二色=负向（蓝），对齐原文 force plot
  p <- shapviz::sv_force(
    shp, row_id = row_id, max_display = 8L,
    fill_colors = c("#FF0051", "#008BFB"),
    bar_label_size = 2.6, annotation_size = 2.8
  )
  p + ggplot2::labs(title = title, x = "Model output") +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 9, face = "bold", hjust = 0),
      plot.margin = ggplot2::margin(6, 8, 10, 8)
    )
}

# 原文 Fig.S4：A beeswarm | B bar，其下 C 非存活、D 存活 各一条 force
ml_ref_s4_paper <- function(shp, non_survivor, survivor, out_pdf = NULL,
                            database = "MIMIC-IV", tag = NA_character_) {
  bee <- .ml_fshap_plot(shp, "bee", "A") +
    ggplot2::theme(legend.position = "right")
  bar <- .ml_fshap_plot(shp, "bar", "B")
  fc <- .ml_fshap_force(
    shp, as.integer(non_survivor$row_id),
    sprintf("C   Non-survivor   f(x)=%s", pub_format_est(non_survivor$prob))
  )
  fd <- .ml_fshap_force(
    shp, as.integer(survivor$row_id),
    sprintf("D   Survivor   f(x)=%s", pub_format_est(survivor$prob))
  )
  plt <- (bee | bar) / fc / fd +
    patchwork::plot_layout(heights = c(1.35, 0.55, 0.55)) +
    patchwork::plot_annotation(
      title = sprintf(
        "Figure S4. Explanation of the 28-day mortality model in overall patients (%s, %s)",
        database, tag %||% ""
      ),
      subtitle = "A SHAP beeswarm; B mean(|SHAP|); C non-survivor force; D survivor force"
    )
  path <- .ml_fshap_save(plt, out_pdf, width = 11, height = 9.2)
  list(path = path, database = database, tag = tag,
       non_survivor = non_survivor, survivor = survivor)
}

# 原文 Fig.S5：按层交替 非存活/存活 的 force（A–F），单列
ml_ref_s5_forces <- function(items, out_pdf = NULL) {
  letters_ab <- LETTERS
  panels <- list(); plot_list <- list()
  for (i in seq_along(items)) {
    it <- items[[i]]
    lab <- sprintf("%s   %s | %s | %s",
                   letters_ab[i], it$database, it$stratum, it$outcome_class)
    plot_list[[i]] <- .ml_fshap_force(it$shp, as.integer(it$row_id), lab)
    panels[[i]] <- data.frame(
      database = it$database, stratum = it$stratum,
      outcome_class = it$outcome_class,
      row_id = as.integer(it$row_id), prob = as.numeric(it$prob),
      letter = letters_ab[i], stringsAsFactors = FALSE
    )
  }
  panels <- do.call(rbind, panels); rownames(panels) <- NULL
  plt <- patchwork::wrap_plots(plot_list, ncol = 1L) +
    patchwork::plot_annotation(
      title = "Figure S5. Inference process of the ML models (individual force plots)"
    )
  path <- .ml_fshap_save(plt, out_pdf, width = 10,
                         height = 2.15 * max(nrow(panels), 1L))
  list(panels = panels, path = path)
}

.ml_fshap_waterfall <- function(shp, row_id, title) {
  if (row_id < 1L || row_id > nrow(shapviz::get_shap_values(shp))) {
    stop("waterfall row_id ", row_id, " outside SHAP matrix (n=",
         nrow(shapviz::get_shap_values(shp)), ").", call. = FALSE)
  }
  p <- tryCatch(shapviz::sv_waterfall(shp, row_id = row_id,
                                      max_display = 15L),
                error = function(e) shapviz::sv_waterfall(shp, row_id = row_id))
  p + ggplot2::labs(title = NULL, subtitle = title, caption = NULL) +
    .ref_theme +
    ggplot2::theme(plot.subtitle = ggplot2::element_text(size = 6.5,
                                                          face = "bold"),
                   plot.margin = ggplot2::margin(t = 8, r = 5, b = 2, l = 2))
}

# --------------------------------------------------------------------------
# 4) Boruta Z-score panels (Figure 7 / S2)
# --------------------------------------------------------------------------

#' 由 Boruta ImpHistory（或 fixture list(imp=matrix, selected=...,
#' shadow_prefix=...)）构造 Z-score boxplot。阴影特征按 shadow_max 标准化为
#' Z 参考（原文样式：features vs shadow distribution）。
#' @param boruta Boruta 对象，或 list(imp=矩阵, selected=特征名,
#'        shadow_prefix="shadow") 
#' @param panel_key 面板标签
#' @return list(plot_df, n_features, n_shadow, n_selected, plot)
ml_ref_boruta_panels <- function(boruta_by_stratum) {
  rows <- list(); plots <- list(); dfs <- list()
  for (sk in names(boruta_by_stratum)) {
    b <- boruta_by_stratum[[sk]]
    imp <- as.matrix(if (inherits(b, "Boruta")) b$ImpHistory else b$imp)
    selected <- as.character(if (inherits(b, "Boruta")) {
      Boruta::getSelectedAttributes(b, withTentative = FALSE)
    } else b$selected)
    shadow_prefix <- as.character(b$shadow_prefix %||% "^shadow")
    is_shadow <- grepl(shadow_prefix, colnames(imp))
    if (!any(is_shadow)) {
      stop("ml_ref_boruta_panels: ImpHistory 无 shadow 列，无法标准化 Z。",
           call. = FALSE)
    }
    shadow_med <- apply(imp[, is_shadow, drop = FALSE], 2, stats::median,
                        na.rm = TRUE)
    shadow_max <- max(shadow_med)
    shadow_iqr <- suppressWarnings(stats::IQR(as.vector(imp[, is_shadow,
                                                             drop = TRUE]),
                                              na.rm = TRUE))
    if (!is.finite(shadow_iqr) || shadow_iqr <= 0) shadow_iqr <- 1
    med_all <- apply(imp, 2, stats::median, na.rm = TRUE)
    feats <- colnames(imp)[!is_shadow]
    feats_sorted <- feats[order(med_all[feats])]
    zcell <- function(j) (as.numeric(imp[, j]) - shadow_max) / shadow_iqr
    df <- do.call(rbind, lapply(feats_sorted, function(f) {
      data.frame(
        panel = sk, feature = f, z = zcell(f),
        state = if (f %in% selected) "Confirmed" else "Rejected",
        stringsAsFactors = FALSE
      )
    }))
    sdf <- do.call(rbind, lapply(colnames(imp)[is_shadow], function(f) {
      data.frame(panel = sk, feature = f, z = zcell(f), state = "Shadow",
                 stringsAsFactors = FALSE)
    }))
    pdf_df <- rbind(df, sdf)
    pdf_df$feature <- factor(pdf_df$feature,
                             levels = c(feats_sorted, colnames(imp)[is_shadow]))
    dfs[[sk]] <- pdf_df
    rows[[length(rows) + 1L]] <- data.frame(
      panel = sk, n_features = length(feats), n_shadow = sum(is_shadow),
      n_selected = length(intersect(selected, feats)),
      stringsAsFactors = FALSE
    )
    plots[[sk]] <- ggplot2::ggplot(
      pdf_df, ggplot2::aes(x = reorder(feature, z), y = z, fill = state)
    ) +
      ggplot2::geom_boxplot(outlier.shape = NA, width = 0.65) +
      ggplot2::geom_hline(yintercept = 0, linetype = 2, linewidth = 0.3,
                          colour = "grey40") +
      ggplot2::coord_flip() +
      ggplot2::scale_fill_manual(values = c(Confirmed = "#2E7D32",
                                            Rejected = "#B0BEC5",
                                            Shadow = "#90A4AE")) +
      ggplot2::labs(x = NULL, y = "Z-score (vs shadow max / shadow IQR)",
                    title = sk, fill = NULL) +
      .ref_theme +
      ggplot2::theme(axis.text.y = ggplot2::element_text(size = 5.5),
                     plot.title = ggplot2::element_text(size = 8,
                                                        face = "bold"))
  }
  panels <- do.call(rbind, rows)
  rownames(panels) <- NULL
  list(plot_df = do.call(rbind, dfs), panels = panels, plots = plots)
}

ml_ref_fig7_boruta <- function(boruta_by_stratum, out_pdf = NULL) {
  stopifnot(length(boruta_by_stratum) >= 2L)
  r <- ml_ref_boruta_panels(boruta_by_stratum)
  key_order <- names(boruta_by_stratum)
  plt <- patchwork::wrap_plots(r$plots[key_order], ncol = 1) +
    patchwork::plot_annotation(title = "Figure 7. Boruta importance by SOFA stratum (MIMIC-IV)",
                               theme = ggplot2::theme(plot.title = ggplot2::element_text(size = 9, face = "bold")))
  r$path <- .ml_fshap_save(plt, out_pdf, width = 8,
                           height = 5 * length(key_order))
  r
}

ml_ref_s2_boruta <- function(boruta_overall, out_pdf = NULL) {
  b <- list(Overall = boruta_overall)
  r <- ml_ref_boruta_panels(b)
  plt <- r$plots[["Overall"]] +
    ggplot2::labs(caption = "Figure S2. Boruta feature selection, MIMIC-IV overall")
  r$path <- .ml_fshap_save(plt, out_pdf, width = 7, height = 6)
  r
}

# --------------------------------------------------------------------------
# 4b) Boruta fit helper (MIMIC only — external dbs must never re-select)
# --------------------------------------------------------------------------

#' 在给定训练帧（Group + 特征列）上跑引擎同款 Boruta（Boruta::Boruta +
#' TentativeRoughFix），产出可直接喂 ml_ref_boruta_panels 的对象。
#' 仅供 MIMIC-IV 分层/overall 面板复算重要性分布；eICU 禁止调用本函数
#' （由调用方在面板编排里保证，函数本身记录 database 标签防误用）。
ml_ref_boruta_run <- function(train_dat, max_runs = 100L, seed = 42L,
                              database = "MIMIC_IV") {
  if (!requireNamespace("Boruta", quietly = TRUE)) {
    stop("ml_ref_boruta_run 需要 Boruta 包。", call. = FALSE)
  }
  db <- tolower(trimws(as.character(database %||% "")[1L]))
  if (!grepl("mimic", db)) {
    stop("ml_ref_boruta_run: Boruta 只允许在 MIMIC-IV 主库复算（database=",
         database, "）。外验库禁止重做特征选择。", call. = FALSE)
  }
  if (!is.data.frame(train_dat) || !"Group" %in% names(train_dat) ||
      ncol(train_dat) < 3L) {
    stop("ml_ref_boruta_run: train_dat 需为 Group + >=2 特征列的数据帧。",
         call. = FALSE)
  }
  d <- train_dat
  for (cn in names(d)) {
    if (is.character(d[[cn]])) d[[cn]] <- as.factor(d[[cn]])
  }
  set.seed(as.integer(seed)[1L])
  bo <- Boruta::Boruta(Group ~ ., data = d, doTrace = 0L,
                       maxRuns = as.integer(max_runs)[1L])
  bo <- Boruta::TentativeRoughFix(bo)
  bo
}

# --------------------------------------------------------------------------
# 5) Figure 8: db x stratum cells (ROC + beeswarm + importance bar)
# --------------------------------------------------------------------------

#' 归一化单格 ROC 输入：兼容两种形态——
#'  1) 单个 ml_ref_roc_rows 结果（含 auc/curve 字段；旧口径，向后兼容）；
#'  2) list(list(model=tag, roc=ml_ref_roc_rows 结果), ...) 多模型列表
#'     （新规格：每格叠加该层全部模型 ROC）。
#' 返回 list(entries=list(list(model, roc)), multi=logical)。
.ml_fig8_norm_roc <- function(cl) {
  ro <- cl$roc
  if (is.null(ro)) return(list(entries = list(), multi = FALSE))
  if ("auc" %in% names(ro)) {
    return(list(entries = list(list(
      model = cl$tag %||%
        (if (!is.null(ro$curve) && length(ro$curve$model))
          as.character(ro$curve$model[1]) else NA_character_),
      roc = ro)), multi = FALSE))
  }
  entries <- lapply(seq_along(ro), function(i) {
    e <- ro[[i]]
    roc <- if (!is.null(e$roc)) e$roc else e
    model <- as.character(e$model %||%
      (if (!is.null(roc$curve) && length(roc$curve$model))
        roc$curve$model[1] else cl$tag %||% paste0("model_", i)))
    list(model = model, roc = roc)
  })
  list(entries = entries, multi = TRUE)
}

#' @param cells list of list(database, stratum, tag, roc, shp (shapviz)).
#'   `roc` 兼容两种口径：单个 ml_ref_roc_rows 结果（旧：每格一条最优模型
#'   ROC）；或 list(list(model=tag, roc=ml_ref_roc_rows), ...) 多模型列表
#'   （新规格：每格叠加该层全部模型 ROC，colour=model，图例标各模型 AUC）。
#'   SHAP beeswarm/importance 两子格恒用最优 tag（cl$tag）。
#' @return list(panels（每格一行，tag=最优）、auc（每格×每模型一行长表）、
#'   curve、legend_labels（每格图例标签字符向量列表）、path)
ml_ref_fig8_grid <- function(cells, out_pdf = NULL) {
  panels <- list(); auc_rows <- list(); curves <- list(); plot_list <- list()
  legend_labels <- list()
  five_cols <- c(logistic = "#1565C0", dt = "#2E7D32", rf = "#EF6C00",
                 xgboost = "#6A1B9A", lightgbm = "#00838F")
  for (cl in cells) {
    nr <- .ml_fig8_norm_roc(cl)
    entries <- nr$entries
    best_idx <- which(vapply(entries, function(e) identical(e$model, cl$tag),
                             logical(1)))
    if (!length(best_idx)) best_idx <- 1L
    ro_best <- entries[[best_idx[1]]]$roc
    for (i in seq_along(entries)) {
      ro <- entries[[i]]$roc
      if (!is.null(ro$curve)) {
        cd <- ro$curve
        cd$model <- entries[[i]]$model
        curves[[length(curves) + 1L]] <- cd
      }
      auc_rows[[length(auc_rows) + 1L]] <- data.frame(
        database = cl$database, stratum = cl$stratum,
        model = entries[[i]]$model,
        best = identical(entries[[i]]$model, cl$tag),
        auc = ro$auc, ci_low = ro$ci_low, ci_high = ro$ci_high,
        stringsAsFactors = FALSE
      )
    }
    cell_curves <- vapply(entries, function(e) !is.null(e$roc$curve), logical(1))
    if (nr$multi) {
      model_lv <- unique(c("logistic", "dt", "rf", "xgboost", "lightgbm",
                           vapply(entries, function(e) e$model, character(1))))
      model_lv <- model_lv[model_lv %in% vapply(entries, function(e) e$model,
                                                character(1))]
      # keep declared five-model order first
      prefer_m <- c("logistic", "dt", "rf", "xgboost", "lightgbm")
      model_lv <- c(intersect(prefer_m, model_lv),
                    setdiff(model_lv, prefer_m))
      # reorder entries to match
      entries <- entries[match(model_lv,
                               vapply(entries, function(e) e$model,
                                      character(1)))]
      entries <- entries[!vapply(entries, is.null, logical(1))]
      model_lv <- vapply(entries, function(e) e$model, character(1))
      roc_df <- if (any(cell_curves)) {
        do.call(rbind, lapply(entries[cell_curves], function(e) e$roc$curve))
      } else NULL
      if (!is.null(roc_df)) {
        roc_df$model <- factor(as.character(roc_df$model), levels = model_lv)
      } else {
        roc_df <- data.frame(fpr = numeric(0), tpr = numeric(0),
                             model = factor(character(0), levels = model_lv))
      }
      lab <- sprintf("%s | %s\nSHAP = best: %s (AUC %s)",
                     cl$database, cl$stratum, cl$tag %||% "NA",
                     pub_format_est(ro_best$auc))
      leg_vals <- vapply(seq_along(entries), function(i) {
        # 原文 Fig.8 风格：短标签 + AUC（CI 已在 Table S11，图例勿过长遮曲线）
        sprintf("%s (AUC = %s)", entries[[i]]$model,
                pub_format_est(entries[[i]]$roc$auc))
      }, character(1))
      cols <- ifelse(model_lv %in% names(five_cols),
                     five_cols[model_lv], "#455A64")
      names(cols) <- model_lv
      # 图例放 ROC 面右下角空白（对齐原文 Fig.8），勿再挤到面外底部
      p_roc <- ggplot2::ggplot(roc_df, ggplot2::aes(x = fpr, y = tpr,
                                                    colour = model)) +
        ggplot2::geom_abline(linetype = 2, colour = "grey50",
                             linewidth = 0.3) +
        ggplot2::geom_line(linewidth = 0.5) +
        ggplot2::coord_cartesian(xlim = c(0, 1), ylim = c(0, 1)) +
        ggplot2::scale_colour_manual(values = cols, breaks = model_lv,
                                     labels = leg_vals, name = NULL) +
        ggplot2::labs(x = "1 - Specificity", y = "Sensitivity", title = lab) +
        .ref_theme +
        ggplot2::theme(
          plot.title = ggplot2::element_text(size = 6, face = "bold"),
          legend.position = "inside",
          legend.position.inside = c(0.98, 0.02),
          legend.justification = c(1, 0),
          legend.background = ggplot2::element_rect(
            fill = grDevices::adjustcolor("white", alpha.f = 0.9),
            colour = "grey65", linewidth = 0.25
          ),
          legend.key.height = grid::unit(0.28, "lines"),
          legend.key.width = grid::unit(0.7, "lines"),
          legend.text = ggplot2::element_text(size = 4.2),
          legend.spacing.y = grid::unit(0.02, "lines"),
          legend.margin = ggplot2::margin(1, 2, 1, 2)
        )
      legend_labels[[length(legend_labels) + 1L]] <- leg_vals
    } else {
      ro <- ro_best
      lab <- sprintf("%s | %s\n%s: AUC %s (95%%CI %s-%s)",
                     cl$database, cl$stratum, cl$tag,
                     pub_format_est(ro$auc), pub_format_est(ro$ci_low),
                     pub_format_est(ro$ci_high))
      roc_df <- if (is.null(ro$curve)) {
        data.frame(fpr = numeric(0), tpr = numeric(0))
      } else ro$curve
      p_roc <- ggplot2::ggplot(roc_df, ggplot2::aes(x = fpr, y = tpr)) +
        ggplot2::geom_abline(linetype = 2, colour = "grey50", linewidth = 0.3) +
        ggplot2::geom_line(colour = "#1565C0", linewidth = 0.6) +
        ggplot2::xlim(0, 1) + ggplot2::ylim(0, 1) +
        ggplot2::labs(x = "1 - Specificity", y = "Sensitivity", title = lab) +
        .ref_theme +
        ggplot2::theme(plot.title = ggplot2::element_text(size = 6,
                                                          face = "bold"))
      legend_labels[[length(legend_labels) + 1L]] <- character(0)
    }
    p_bee <- .ml_fshap_plot(cl$shp, "bee", "SHAP beeswarm") +
      ggplot2::theme(axis.text.y = ggplot2::element_text(size = 5),
                     legend.position = "none")
    p_bar <- .ml_fshap_plot(cl$shp, "bar", "mean(|SHAP|)") +
      ggplot2::theme(axis.text.y = ggplot2::element_text(size = 5))
    # store atomic panels for original A–I grid (row=plot type, col=stratum)
    plot_list[[length(plot_list) + 1L]] <- list(
      database = cl$database, stratum = cl$stratum,
      p_roc = p_roc, p_bee = p_bee, p_bar = p_bar
    )
    panels[[length(panels) + 1L]] <- data.frame(
      database = cl$database, stratum = cl$stratum, tag = cl$tag,
      auc = ro_best$auc, ci_low = ro_best$ci_low, ci_high = ro_best$ci_high,
      n_parts = 3L, n_models = length(entries), stringsAsFactors = FALSE
    )
  }
  panels <- do.call(rbind, panels); rownames(panels) <- NULL
  auc <- do.call(rbind, auc_rows); rownames(auc) <- NULL
  curve <- if (length(curves)) do.call(rbind, curves) else NULL
  # Original Fig.8 A–I: columns = strata, rows = ROC / beeswarm / bar;
  # dual-DB = MIMIC block then eICU block (18 panels).
  db_order <- unique(as.character(panels$database))
  prefer <- c("MIMIC-IV", "MIMIC_IV", "eICU")
  db_order <- c(intersect(prefer, db_order), setdiff(db_order, prefer))
  blocks <- list()
  for (dbn in db_order) {
    cells_db <- plot_list[vapply(plot_list, function(x)
      identical(as.character(x$database), dbn), logical(1))]
    if (!length(cells_db)) next
    # preserve stratum order from panels
    st_order <- unique(as.character(panels$stratum[panels$database == dbn]))
    cells_db <- cells_db[order(match(
      vapply(cells_db, function(x) as.character(x$stratum), character(1)),
      st_order
    ))]
    n_st <- length(cells_db)
    row_roc <- lapply(cells_db, function(x) x$p_roc)
    row_bee <- lapply(cells_db, function(x) x$p_bee)
    row_bar <- lapply(cells_db, function(x) x$p_bar)
    block <- patchwork::wrap_plots(c(row_roc, row_bee, row_bar),
                                   ncol = n_st, nrow = 3L) +
      patchwork::plot_annotation(
        title = sprintf("%s (columns = SOFA strata; rows = ROC / SHAP beeswarm / SHAP bar)",
                        dbn))
    blocks[[length(blocks) + 1L]] <- block
  }
  plt <- if (length(blocks) == 1L) blocks[[1]] else {
    patchwork::wrap_plots(blocks, ncol = 1L) +
      patchwork::plot_annotation(
        title = "Figure 8. Stratified five-model ROC and SHAP (frozen MIMIC models; eICU external)")
  }
  if (length(blocks) == 1L) {
    plt <- plt + patchwork::plot_annotation(
      title = "Figure 8. Stratified five-model ROC and SHAP (frozen MIMIC models; eICU external)")
  }
  n_st_max <- max(table(panels$database))
  path <- .ml_fshap_save(plt, out_pdf,
                         width = 4.2 * max(n_st_max, 1L),
                         height = 9.5 * max(length(db_order), 1L))
  list(panels = panels, auc = auc, curve = curve,
       legend_labels = legend_labels, path = path)
}

# --------------------------------------------------------------------------
# 6) S3: overall five-model ROC (internal + external per model)
# --------------------------------------------------------------------------

#' @param cells list of list(model, dataset, roc (ml_ref_roc_rows))
ml_ref_s3_roc <- function(cells, out_pdf = NULL) {
  auc_list <- list(); curves <- list(); per_model <- list()
  for (cl in cells) {
    ro <- cl$roc
    row <- data.frame(model = cl$model, dataset = cl$dataset,
                      auc = ro$auc, ci_low = ro$ci_low, ci_high = ro$ci_high,
                      stringsAsFactors = FALSE)
    auc_list[[length(auc_list) + 1L]] <- row
    if (!is.null(ro$curve)) {
      cd <- ro$curve
      if (!"dataset" %in% names(cd) || all(is.na(cd$dataset))) {
        cd$dataset <- cl$dataset
      }
      curves[[length(curves) + 1L]] <- cd
    }
    key <- cl$model
    per_model[[key]] <- modifyList(per_model[[key]] %||% list(),
                                   setNames(list(ro), cl$dataset))
  }
  auc <- do.call(rbind, auc_list); rownames(auc) <- NULL
  model_order <- unique(as.character(auc$model))
  panels <- do.call(rbind, lapply(model_order, function(m) {
    d <- auc[auc$model == m, , drop = FALSE]
    data.frame(
      model = m,
      internal_auc = d$auc[match("internal_validation", d$dataset)],
      external_auc = d$auc[match("external_validation", d$dataset)],
      datasets = paste(d$dataset, collapse = "|"),
      stringsAsFactors = FALSE
    )
  }))
  rownames(panels) <- NULL
  curve <- if (length(curves)) do.call(rbind, curves) else NULL
  # 原文 Fig.S3：一面叠五模型，图例右下 AUC=…（非按模型分面）
  # 双库：A=MIMIC internal，B=eICU external，左右并排
  disp_nm <- c(logistic = "LR", dt = "DT", rf = "RF",
               xgboost = "XGBoost", lightgbm = "LGB")
  disp_col <- c(LR = "#4FC3F7", DT = "#1565C0", RF = "#8D6E63",
                XGBoost = "#7E57C2", LGB = "#E53935")
  ds_title <- c(
    internal_validation = "A  MIMIC-IV overall (internal validation)",
    external_validation = "B  eICU overall (external validation)"
  )
  prefer_m <- c("logistic", "dt", "rf", "xgboost", "lightgbm")
  model_order <- c(intersect(prefer_m, model_order),
                   setdiff(model_order, prefer_m))
  plt <- NULL
  if (!is.null(curve) && nrow(curve)) {
    curve$model <- factor(as.character(curve$model), levels = model_order)
    ds_have <- intersect(c("internal_validation", "external_validation"),
                         unique(as.character(curve$dataset)))
    # 若只有单集，仍画一面
    if (!length(ds_have)) ds_have <- unique(as.character(curve$dataset))
    one_panel <- function(ds) {
      sub <- curve[as.character(curve$dataset) == ds, , drop = FALSE]
      if (!nrow(sub)) return(NULL)
      auc_ds <- auc[as.character(auc$dataset) == ds, , drop = FALSE]
      mo <- model_order[model_order %in% unique(as.character(sub$model))]
      lab_of <- function(m) {
        hit <- unname(disp_nm[m])
        ifelse(is.na(hit) | !nzchar(hit), m, hit)
      }
      leg <- vapply(mo, function(m) {
        hit <- auc_ds[as.character(auc_ds$model) == m, , drop = FALSE]
        lab <- lab_of(m)
        if (!nrow(hit) || !is.finite(hit$auc[1])) return(lab)
        sprintf("%s AUC = %s", lab, pub_format_est(hit$auc[1]))
      }, character(1))
      sub$lab <- factor(lab_of(as.character(sub$model)),
                        levels = lab_of(mo))
      cols <- disp_col[levels(sub$lab)]
      cols[is.na(cols)] <- "#455A64"
      ttl <- unname(ds_title[ds] %||% ds)
      ggplot2::ggplot(sub, ggplot2::aes(x = fpr, y = tpr, colour = lab)) +
        ggplot2::geom_abline(slope = 1, intercept = 0, linetype = 2,
                             colour = "grey45", linewidth = 0.4) +
        ggplot2::geom_line(linewidth = 0.7) +
        ggplot2::coord_cartesian(xlim = c(0, 1), ylim = c(0, 1)) +
        ggplot2::scale_colour_manual(values = cols, breaks = levels(sub$lab),
                                     labels = leg, name = NULL) +
        ggplot2::labs(x = "1 - Specificity", y = "Sensitivity", title = ttl) +
        ggplot2::theme_bw(base_size = 9) +
        ggplot2::theme(
          panel.grid.minor = ggplot2::element_blank(),
          plot.title = ggplot2::element_text(size = 10, face = "bold", hjust = 0.5),
          legend.position = "inside",
          legend.position.inside = c(0.98, 0.02),
          legend.justification = c(1, 0),
          legend.background = ggplot2::element_rect(fill = "white", colour = NA),
          legend.key.height = grid::unit(0.4, "lines"),
          legend.text = ggplot2::element_text(size = 7)
        )
    }
    ps <- lapply(ds_have, one_panel)
    ps <- ps[!vapply(ps, is.null, logical(1))]
    plt <- patchwork::wrap_plots(ps, ncol = length(ps)) +
      patchwork::plot_annotation(
        title = paste0(
          "Figure S3. Receiver operating characteristic curves of five ML models ",
          "for 28-day mortality in overall patients"
        )
      )
  }
  path <- .ml_fshap_save(plt, out_pdf,
                         width = 4.6 * max(length(unique(as.character(auc$dataset))), 1L),
                         height = 4.6)
  list(panels = panels, auc = auc, curve = curve, path = path)
}

# --------------------------------------------------------------------------
# 7) S4: overall best frozen model SHAP, both databases
# --------------------------------------------------------------------------

ml_ref_s4_shap <- function(items, out_pdf = NULL) {
  panels <- list(); plot_list <- list()
  for (it in items) {
    sv <- shapviz::get_shap_values(it$shp)
    panels[[length(panels) + 1L]] <- data.frame(
      database = it$database, tag = it$tag %||% NA_character_,
      n_features = ncol(sv), n_explained = nrow(sv),
      stringsAsFactors = FALSE
    )
    cell <- .ml_fshap_plot(it$shp, "bee",
                           sprintf("%s beeswarm", it$database)) /
      .ml_fshap_plot(it$shp, "bar", sprintf("%s importance", it$database))
    plot_list[[length(plot_list) + 1L]] <- cell
  }
  panels <- do.call(rbind, panels); rownames(panels) <- NULL
  plt <- patchwork::wrap_plots(plot_list, ncol = length(plot_list)) +
    patchwork::plot_annotation(
      title = "Figure S4. SHAP of frozen best overall model (MIMIC-IV / eICU)")
  path <- .ml_fshap_save(plt, out_pdf,
                         width = 6.5 * length(plot_list), height = 6)
  list(panels = panels, path = path)
}

# --------------------------------------------------------------------------
# 8) S5: individual survivor/non-survivor waterfalls
# --------------------------------------------------------------------------

#' @param items list of list(database, stratum, outcome_class, row_id, prob, shp)
ml_ref_s5_waterfalls <- function(items, out_pdf = NULL) {
  panels <- list(); plot_list <- list()
  for (it in items) {
    sub_lab <- sprintf("%s | %s | %s (pred=%s)",
                       it$database, it$stratum, it$outcome_class,
                       pub_format_est(it$prob))
    p <- .ml_fshap_waterfall(it$shp, it$row_id, sub_lab)
    plot_list[[length(plot_list) + 1L]] <- p
    panels[[length(panels) + 1L]] <- data.frame(
      database = it$database, stratum = it$stratum,
      outcome_class = it$outcome_class,
      row_id = as.integer(it$row_id), prob = as.numeric(it$prob),
      stringsAsFactors = FALSE
    )
  }
  panels <- do.call(rbind, panels); rownames(panels) <- NULL
  plt <- patchwork::wrap_plots(plot_list, ncol = 2) +
    patchwork::plot_annotation(
      title = "Figure S5. Individual SHAP waterfalls (survivor / non-survivor by database x SOFA stratum)")
  path <- .ml_fshap_save(plt, out_pdf, width = 10,
                         height = 3.8 * ceiling(nrow(panels) / 2))
  list(panels = panels, path = path)
}

# --------------------------------------------------------------------------
# 9) S9: overall five-model ROC — train / internal / eICU（1×3，原文式排版）
# --------------------------------------------------------------------------

#' 补充图 S9：三集各一面（A 训练 / B 内验 / C 外验），面内多模型 ROC，
#' 图例右下角空白处，条目含 AUC(95%CI)。对齐用户提供的 NHANES/CHARLS 式排版。
#' @param cells list of list(model, dataset, roc)
ml_ref_s9_three_set_auc <- function(cells, out_pdf = NULL) {
  prefer_ds <- c("training", "internal_validation", "external_validation")
  panel_meta <- list(
    training = list(
      letter = "A", title = "MIMIC-IV training set"
    ),
    internal_validation = list(
      letter = "B", title = "MIMIC-IV internal validation"
    ),
    external_validation = list(
      letter = "C", title = "eICU external validation"
    )
  )
  prefer_m <- c("logistic", "dt", "rf", "xgboost", "lightgbm")
  five_cols <- c(
    logistic = "#E41A1C", dt = "#377EB8", rf = "#4DAF4A",
    xgboost = "#984EA3", lightgbm = "#FF7F00"
  )
  auc_list <- list(); by_ds <- list()
  for (cl in cells) {
    ro <- cl$roc
    ds <- as.character(cl$dataset)
    if (!ds %in% prefer_ds) next
    auc_list[[length(auc_list) + 1L]] <- data.frame(
      model = cl$model, dataset = ds,
      auc = ro$auc, ci_low = ro$ci_low, ci_high = ro$ci_high,
      stringsAsFactors = FALSE
    )
    if (is.null(ro$curve) || !nrow(ro$curve)) next
    cd <- ro$curve
    cd$model <- cl$model
    cd$dataset <- ds
    by_ds[[ds]] <- c(by_ds[[ds]] %||% list(), list(list(
      model = cl$model, roc = ro, curve = cd
    )))
  }
  auc <- do.call(rbind, auc_list); rownames(auc) <- NULL
  if (!nrow(auc)) {
    warning("Figure S9: no AUC rows", call. = FALSE)
    return(list(auc = auc, curve = NULL, path = NULL))
  }
  model_order <- c(intersect(prefer_m, unique(auc$model)),
                   setdiff(unique(auc$model), prefer_m))

  .one_panel <- function(ds) {
    entries <- by_ds[[ds]]
    if (!length(entries)) return(NULL)
    # 保持五模型顺序
    mo <- model_order[model_order %in% vapply(entries, function(e) e$model,
                                              character(1))]
    entries <- entries[match(mo, vapply(entries, function(e) e$model,
                                        character(1)))]
    entries <- entries[!vapply(entries, is.null, logical(1))]
    mo <- vapply(entries, function(e) e$model, character(1))
    cdf <- do.call(rbind, lapply(entries, function(e) e$curve))
    cdf$model <- factor(as.character(cdf$model), levels = mo)
    leg_vals <- vapply(entries, function(e) {
      sprintf("%s AUC: %s(%s-%s)", e$model,
              pub_format_est(e$roc$auc),
              pub_format_est(e$roc$ci_low),
              pub_format_est(e$roc$ci_high))
    }, character(1))
    cols <- ifelse(mo %in% names(five_cols), five_cols[mo], "#455A64")
    names(cols) <- mo
    meta <- panel_meta[[ds]]
    ggplot2::ggplot(cdf, ggplot2::aes(x = fpr, y = tpr, colour = model)) +
      ggplot2::geom_abline(linetype = 2, colour = "grey55", linewidth = 0.35) +
      ggplot2::geom_line(linewidth = 0.7) +
      ggplot2::coord_cartesian(xlim = c(0, 1), ylim = c(0, 1)) +
      ggplot2::scale_colour_manual(values = cols, breaks = mo,
                                   labels = leg_vals, name = "Model") +
      ggplot2::labs(
        x = "1 - Specificity", y = "Sensitivity",
        title = sprintf("%s  %s", meta$letter, meta$title)
      ) +
      ggplot2::theme_bw(base_size = 9) +
      ggplot2::theme(
        panel.grid.minor = ggplot2::element_blank(),
        plot.title = ggplot2::element_text(size = 10, face = "bold",
                                           hjust = 0.5),
        legend.position = "inside",
        legend.position.inside = c(0.98, 0.02),
        legend.justification = c(1, 0),
        legend.background = ggplot2::element_rect(
          fill = grDevices::adjustcolor("white", alpha.f = 0.92),
          colour = NA
        ),
        legend.key.height = grid::unit(0.32, "lines"),
        legend.key.width = grid::unit(0.85, "lines"),
        legend.text = ggplot2::element_text(size = 5.5),
        legend.title = ggplot2::element_text(size = 6.5, face = "bold"),
        legend.margin = ggplot2::margin(1, 2, 1, 2)
      )
  }

  panels <- lapply(prefer_ds, .one_panel)
  panels <- panels[!vapply(panels, is.null, logical(1))]
  if (!length(panels)) {
    warning("Figure S9: no ROC panels", call. = FALSE)
    return(list(auc = auc, curve = NULL, path = NULL))
  }
  plt <- patchwork::wrap_plots(panels, ncol = length(panels)) +
    patchwork::plot_annotation(
      title = paste0(
        "Figure S9. Receiver operating characteristic curves of five ML models ",
        "across train, internal validation and eICU external sets"
      ),
      subtitle = paste0(
        "Frozen MIMIC-IV overall models. Train = in-sample; ",
        "eICU = external validation without refitting."
      )
    )
  path <- .ml_fshap_save(plt, out_pdf,
                         width = 4.15 * length(panels), height = 4.35)
  curve <- do.call(rbind, lapply(names(by_ds), function(ds) {
    do.call(rbind, lapply(by_ds[[ds]], function(e) e$curve))
  }))
  list(auc = auc, curve = curve, path = path)
}
