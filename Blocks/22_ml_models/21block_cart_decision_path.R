###############################################################################
#  cart_decision_path — CART 临床决策路径图（rpart 挖切点 + 可读分流树）
#
#  与 ml_dt 解耦：本块不做 ML 竞品评估，只导出门诊可读路径图与切点规则表。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$train（data_scope=train）或 imputed/cleaned（analysis）
#  require_ctx_results = feature_selection_final（可选）或 Model2Factors / config$features
#
#  cart_decision_path = list(
#    enable = FALSE,
#    features = NULL,              # NULL → feature_selection_final → Model2Factors
#    outcome = NULL,               # NULL → data$outcome_column / Group
#    data_scope = "train",         # "train" | "analysis"
#    maxdepth = 3L,
#    minsplit = 20L,
#    minbucket = 10L,
#    cp = 0.01,                    # 生长树复杂度门槛（剪枝前）
#    xval = 10L,                   # >0 时做交叉验证；0 = 不剪枝（旧行为）
#    prune = TRUE,                 # xval>0 时按 prune_rule 剪枝
#    prune_rule = "1se",           # "1se" | "min"
#    plot_clinical = TRUE,
#    plot_rpart = TRUE,
#    leaf_labels = NULL,           # 建议软措辞，如 "倾向首选 DXA" / "考虑加做 QCT"
#    root_label = "Enrolled patients",
#    var_labels = NULL,
#    edge_yes = "Yes",
#    edge_no = "No",
#    figure_title = "CART decision path",
#    figure_width = 8,
#    figure_height = 6,
#    seed = NULL
#  ),
#
#  register_block: "cart_decision_path"
#  典型流水线: train_validation → ml_feature_selection_bundle → 本块 → ml_models_bundle
#  产出: Figure … CART decision path (clinical).pdf；可选 rpart 统计树；切点规则表
###############################################################################

.cdp21_var_label <- function(v, var_labels = NULL) {
  v <- as.character(v)[1L]
  if (!nzchar(v) || identical(v, "<leaf>")) return(v)
  if (!is.null(var_labels) && !is.null(var_labels[[v]])) {
    return(as.character(var_labels[[v]])[1L])
  }
  if (!is.null(names(var_labels)) && v %in% names(var_labels)) {
    return(as.character(var_labels[[v]])[1L])
  }
  v
}

.cdp21_leaf_label <- function(pred_class, leaf_labels = NULL) {
  pc <- as.character(pred_class)[1L]
  if (is.null(leaf_labels) || !length(leaf_labels)) return(pc)
  if (!is.null(leaf_labels[[pc]])) return(as.character(leaf_labels[[pc]])[1L])
  if (!is.null(names(leaf_labels)) && pc %in% names(leaf_labels)) {
    return(as.character(leaf_labels[[pc]])[1L])
  }
  pc
}

.cdp21_resolve_outcome <- function(cfg, bl_cfg, data_nms) {
  cand <- c(
    bl_cfg$outcome %||% character(0),
    cfg$data$outcome_column %||% character(0),
    "Group", "Disease", "outcome"
  )
  cand <- unique(as.character(cand))
  cand <- cand[nzchar(cand)]
  hit <- cand[cand %in% data_nms]
  if (!length(hit)) return(NA_character_)
  hit[1L]
}

.cdp21_resolve_features <- function(ctx, bl_cfg, data, outcome_col) {
  cfg <- ctx$config
  feats_cfg <- bl_cfg$features
  if (!is.null(feats_cfg) && length(feats_cfg)) {
    feats <- as.character(feats_cfg)
  } else {
    ff0 <- ctx$results$feature_selection_final
    if (is.null(ff0) || !length(ff0)) {
      if (exists("load_feature_selection_final_into_ctx", mode = "function")) {
        ctx <- load_feature_selection_final_into_ctx(ctx)
        ff0 <- ctx$results$feature_selection_final
      }
    }
    if (length(ff0)) {
      feats <- as.character(ff0)
    } else {
      feats <- as.character(ctx$results$Model2Factors %||% character(0))
    }
  }

  id_col <- cfg$data$id_column %||% character(0)
  time_var <- cfg$survival$time_var %||% character(0)
  event_var <- cfg$survival$event_var %||% character(0)
  index_var <- cfg$index$var %||%
    cfg$index$index_var %||%
    cfg$prediction$index_var %||%
    character(0)
  ae <- cfg$analysis_exclusion %||% list()
  drop_extra <- unique(c(
    as.character(ae$resolved_drop_vars %||% character(0)),
    as.character(ae$disease_vars %||% character(0)),
    as.character(ae$exclude_extra %||% character(0))
  ))

  ban <- unique(c(
    outcome_col, id_col, time_var, event_var, index_var, drop_extra,
    "Group", ".pred_class", "predicted_prob"
  ))
  ban <- ban[nzchar(ban)]
  feats <- setdiff(intersect(unique(feats), names(data)), ban)
  list(ctx = ctx, feats = feats)
}

.cdp21_pick_data <- function(ctx, bl_cfg) {
  scope <- tolower(trimws(as.character(bl_cfg$data_scope %||% "train")[1L]))
  if (identical(scope, "train")) {
    df <- ctx$data$train
    if (is.null(df) || !is.data.frame(df) || !nrow(df)) {
      cli::cli_alert_warning(
        "cart_decision_path: data_scope=train 但无 ctx$data$train，回退 analysis。"
      )
      scope <- "analysis"
    }
  }
  if (!identical(scope, "train")) {
    df <- ctx$data$imputed %||% ctx$data$cleaned
  }
  list(data = df, scope = scope)
}

.cdp21_prepare_y <- function(df, outcome_col, cfg) {
  y_raw <- df[[outcome_col]]
  if (is.factor(y_raw)) {
    y <- droplevels(y_raw)
  } else if (is.logical(y_raw)) {
    y <- factor(ifelse(y_raw, "1", "0"), levels = c("0", "1"))
  } else {
    ana <- cfg$project$analysis_group %||% cfg$project$disease %||% NULL
    ref <- cfg$project$reference_group %||% NULL
    y_chr <- trimws(as.character(y_raw))
    if (!is.null(ana) && !is.null(ref) &&
        all(c(trimws(as.character(ana)), trimws(as.character(ref))) %in% unique(y_chr))) {
      y <- factor(
        dplyr::case_when(
          y_chr == trimws(as.character(ana)) ~ as.character(ana),
          y_chr == trimws(as.character(ref)) ~ as.character(ref),
          TRUE ~ NA_character_
        ),
        levels = c(as.character(ref), as.character(ana))
      )
    } else {
      u <- unique(y_chr[!is.na(y_chr) & nzchar(y_chr)])
      y <- factor(y_chr, levels = sort(u))
    }
  }
  y
}

.cdp21_pick_cp <- function(cptable, rule = c("1se", "min")) {
  rule <- match.arg(rule)
  cp_tab <- as.data.frame(cptable)
  if (!nrow(cp_tab) || !"xerror" %in% names(cp_tab)) {
    return(list(cp = NA_real_, row = NA_integer_, rule = rule))
  }
  # rpart cptable: CP, nsplit, rel error, xerror, xstd
  xerr <- as.numeric(cp_tab[["xerror"]])
  xstd <- as.numeric(cp_tab[["xstd"]])
  i_min <- which.min(xerr)
  if (identical(rule, "min")) {
    i <- i_min
  } else {
    thresh <- xerr[i_min] + xstd[i_min]
    cand <- which(xerr <= thresh)
    # 1-SE：在不超过 min+1SE 的树中选最简单（nsplit 最小 → 通常 CP 更大）
    i <- cand[which.min(as.numeric(cp_tab$nsplit[cand]))]
  }
  list(
    cp = as.numeric(cp_tab$CP[i]),
    row = as.integer(i),
    rule = rule,
    xerror = xerr[i],
    xstd = xstd[i],
    nsplit = as.integer(cp_tab$nsplit[i])
  )
}

.cdp21_stratified_split <- function(y, p_test = 0.3, seed = 42L) {
  y <- as.character(y)
  stopifnot(length(y) >= 4L)
  set.seed(as.integer(seed)[1L])
  idx <- seq_along(y)
  test <- integer(0)
  for (lv in unique(y[!is.na(y)])) {
    ii <- idx[y == lv]
    n_te <- max(1L, as.integer(round(length(ii) * p_test)))
    n_te <- min(n_te, length(ii) - 1L)
    test <- c(test, sample(ii, n_te))
  }
  test <- sort(unique(test))
  train <- setdiff(idx, test)
  list(train = train, test = test)
}

.cdp21_class_metrics <- function(y, pred, pos = "1") {
  y <- as.character(y)
  pred <- as.character(pred)
  ok <- !is.na(y) & !is.na(pred)
  y <- y[ok]
  pred <- pred[ok]
  tp <- sum(pred == pos & y == pos)
  tn <- sum(pred != pos & y != pos)
  fp <- sum(pred == pos & y != pos)
  fn <- sum(pred != pos & y == pos)
  n <- length(y)
  list(
    n = n,
    events = sum(y == pos),
    Accuracy = if (n == 0L) NA_real_ else (tp + tn) / n,
    Sensitivity = if ((tp + fn) == 0L) NA_real_ else tp / (tp + fn),
    Specificity = if ((tn + fp) == 0L) NA_real_ else tn / (tn + fp),
    PPV = if ((tp + fp) == 0L) NA_real_ else tp / (tp + fp),
    NPV = if ((tn + fn) == 0L) NA_real_ else tn / (tn + fn)
  )
}

.cdp21_boot_metrics <- function(y, pred, n_boot = 400L, seed = 42L, pos = "1") {
  y <- as.character(y)
  pred <- as.character(pred)
  ok <- !is.na(y) & !is.na(pred)
  y <- y[ok]
  pred <- pred[ok]
  n <- length(y)
  keys <- c("Accuracy", "Sensitivity", "Specificity", "PPV", "NPV")
  set.seed(as.integer(seed)[1L])
  mat <- matrix(NA_real_, nrow = n_boot, ncol = length(keys), dimnames = list(NULL, keys))
  for (b in seq_len(n_boot)) {
    ii <- sample.int(n, n, replace = TRUE)
    m <- .cdp21_class_metrics(y[ii], pred[ii], pos = pos)
    mat[b, ] <- unlist(m[keys], use.names = FALSE)
  }
  point <- .cdp21_class_metrics(y, pred, pos = pos)
  ci <- lapply(keys, function(k) {
    qs <- stats::quantile(mat[, k], c(0.025, 0.975), na.rm = TRUE, names = FALSE)
    c(lo = qs[1], hi = qs[2])
  })
  names(ci) <- keys
  list(point = point, ci = ci, n_boot = as.integer(n_boot), seed = as.integer(seed)[1L])
}

.cdp21_fmt_pct_ci <- function(est, lo, hi) {
  if (!is.finite(est)) return("NA")
  if (!is.finite(lo) || !is.finite(hi)) return(sprintf("%.1f%%", 100 * est))
  sprintf("%.1f%% (%.1f–%.1f)", 100 * est, 100 * lo, 100 * hi)
}

.cdp21_fit <- function(df, outcome_col, feats, bl_cfg, seed) {
  if (!requireNamespace("rpart", quietly = TRUE)) {
    stop("cart_decision_path: 需要 rpart 包。", call. = FALSE)
  }
  dat <- df[, c(outcome_col, feats), drop = FALSE]
  names(dat)[1L] <- "Group"
  dat <- dat[stats::complete.cases(dat), , drop = FALSE]
  if (nrow(dat) < 30L) {
    return(list(ok = FALSE, reason = sprintf("有效样本过少 (n=%d)", nrow(dat))))
  }
  if (nlevels(droplevels(dat$Group)) != 2L) {
    return(list(
      ok = FALSE,
      reason = sprintf(
        "结局须为二分类（当前 %d 水平）",
        nlevels(droplevels(dat$Group))
      )
    ))
  }
  dat$Group <- droplevels(dat$Group)

  xval <- as.integer(bl_cfg$xval %||% 10L)[1L]
  if (is.na(xval) || xval < 0L) xval <- 0L
  # 小样本：折数不超过阳性数与 n/2
  n_pos <- sum(dat$Group == levels(dat$Group)[length(levels(dat$Group))])
  if (xval > 0L) {
    xval <- max(2L, min(xval, as.integer(nrow(dat) %/% 2L), max(2L, n_pos)))
  }

  ctrl <- rpart::rpart.control(
    maxdepth = as.integer(bl_cfg$maxdepth %||% 3L)[1L],
    minsplit = as.integer(bl_cfg$minsplit %||% 20L)[1L],
    minbucket = as.integer(bl_cfg$minbucket %||% 10L)[1L],
    cp = as.numeric(bl_cfg$cp %||% 0.01)[1L],
    xval = xval
  )
  if (!is.null(seed) && is.finite(as.numeric(seed)[1L])) {
    set.seed(as.integer(seed)[1L])
  }
  fit0 <- rpart::rpart(
    Group ~ ., data = dat, method = "class", control = ctrl, model = TRUE
  )

  prune_meta <- list(applied = FALSE, rule = NA_character_, cp = NA_real_)
  fit <- fit0
  do_prune <- isTRUE(bl_cfg$prune %||% (xval > 0L)) && xval > 0L
  if (do_prune) {
    rule <- as.character(bl_cfg$prune_rule %||% "1se")[1L]
    pick <- .cdp21_pick_cp(fit0$cptable, rule = rule)
    if (is.finite(pick$cp)) {
      fit <- rpart::prune(fit0, cp = pick$cp)
      prune_meta <- list(
        applied = TRUE,
        rule = pick$rule,
        cp = pick$cp,
        xerror = pick$xerror,
        xstd = pick$xstd,
        nsplit = pick$nsplit,
        xval = xval
      )
    }
  }

  list(
    ok = TRUE,
    fit = fit,
    fit_unpruned = fit0,
    data = dat,
    n = nrow(dat),
    prune = prune_meta,
    xval = xval
  )
}

.cdp21_split_info <- function(fit, node_id) {
  fr <- fit$frame
  rn <- as.integer(rownames(fr))
  i <- match(as.integer(node_id), rn)
  if (is.na(i)) return(NULL)
  if (identical(as.character(fr$var[i]), "<leaf>")) return(NULL)
  var <- as.character(fr$var[i])
  ## 每个非叶节点在 splits 中占 1 + ncompete + nsurrogate 行，首行为主分裂
  cursor <- 1L
  for (k in seq_len(nrow(fr))) {
    if (identical(as.character(fr$var[k]), "<leaf>")) next
    ncompete <- as.integer(fr$ncompete[k] %||% 0L)[1L]
    nsurrogate <- as.integer(fr$nsurrogate[k] %||% 0L)[1L]
    if (is.na(ncompete)) ncompete <- 0L
    if (is.na(nsurrogate)) nsurrogate <- 0L
    if (k == i) {
      if (cursor > nrow(fit$splits)) return(NULL)
      sp <- fit$splits[cursor, , drop = FALSE]
      cut <- as.numeric(sp[, "index"])
      ncat <- as.numeric(sp[, "ncat"])
      return(list(
        var = var,
        cut = cut,
        ncat = ncat,
        is_factor = is.finite(ncat) && ncat >= 2
      ))
    }
    cursor <- cursor + 1L + ncompete + nsurrogate
  }
  NULL
}

.cdp21_condition_text <- function(info, var_labels, side = c("left", "right")) {
  side <- match.arg(side)
  if (is.null(info)) return(NA_character_)
  lab <- .cdp21_var_label(info$var, var_labels)
  if (isTRUE(info$is_factor)) {
    ## 因子分裂：左/右对应 csplits；简化为变量名 + 水平侧
    if (identical(side, "left")) {
      paste0(lab, " (left levels)")
    } else {
      paste0(lab, " (right levels)")
    }
  } else {
    cut_s <- if (is.finite(info$cut)) {
      formatC(round(info$cut, 4), format = "fg", digits = 4)
    } else {
      "?"
    }
    ## rpart 连续变量：左支 var < cut，右支 var >= cut（ncat = -1 时）
    if (identical(side, "left")) {
      paste0(lab, " < ", cut_s, "?")
    } else {
      paste0(lab, " \u2265 ", cut_s, "?")
    }
  }
}

.cdp21_node_table <- function(fit, leaf_labels = NULL, var_labels = NULL) {
  fr <- fit$frame
  rn <- as.integer(rownames(fr))
  ylevels <- attr(fit, "ylevels")
  if (is.null(ylevels) && !is.null(fit$terms)) {
    ylevels <- levels(fit$model$Group)
  }
  out <- lapply(seq_along(rn), function(i) {
    nid <- rn[i]
    is_leaf <- identical(as.character(fr$var[i]), "<leaf>")
    n <- as.integer(fr$n[i])
    ## yval2: 列布局 ncomp, prob..., nodeprob...
    yv2 <- fr$yval2
    pred_idx <- as.integer(fr$yval[i])
    pred_class <- if (!is.null(ylevels) && pred_idx >= 1L && pred_idx <= length(ylevels)) {
      ylevels[pred_idx]
    } else {
      as.character(pred_idx)
    }
    event_rate <- NA_real_
    if (!is.null(yv2) && !is.null(ylevels) && length(ylevels) >= 2L) {
      ## yval2: 1=pred class; 2:(1+K)=counts; (2+K):(1+2K)=probs；取末类概率
      ncl <- length(ylevels)
      prob_col <- 1L + ncl + ncl
      if (NCOL(yv2) >= prob_col) {
        event_rate <- as.numeric(yv2[i, prob_col])
      }
    }
    info <- if (!is_leaf) .cdp21_split_info(fit, nid) else NULL
    depth <- floor(log2(nid))
    data.frame(
      node_id = nid,
      depth = as.integer(depth),
      is_leaf = is_leaf,
      split_var = if (is.null(info)) NA_character_ else info$var,
      cut_value = if (is.null(info)) NA_real_ else info$cut,
      condition_left = if (is.null(info)) NA_character_ else .cdp21_condition_text(info, var_labels, "left"),
      condition_right = if (is.null(info)) NA_character_ else .cdp21_condition_text(info, var_labels, "right"),
      n = n,
      event_rate = event_rate,
      pred_class = pred_class,
      leaf_label = if (is_leaf) .cdp21_leaf_label(pred_class, leaf_labels) else NA_character_,
      rule_text = NA_character_,
      stringsAsFactors = FALSE
    )
  })
  dplyr::bind_rows(out)
}

.cdp21_fill_rules <- function(nodes, fit, var_labels = NULL) {
  ## 用 path.rpart 生成叶节点规则文本
  leaf_ids <- nodes$node_id[nodes$is_leaf]
  if (!length(leaf_ids)) return(nodes)
  paths <- tryCatch(
    rpart::path.rpart(fit, nodes = leaf_ids, pretty = 0, print.it = FALSE),
    error = function(e) NULL
  )
  if (is.null(paths)) return(nodes)
  for (nm in names(paths)) {
    nid <- as.integer(nm)
    steps <- paths[[nm]]
    ## 第一项常为 "root"
    steps <- steps[steps != "root"]
    if (length(var_labels)) {
      steps <- vapply(steps, function(s) {
        for (vn in names(var_labels)) {
          if (grepl(paste0("^", vn, "\\b"), s)) {
            s <- sub(vn, .cdp21_var_label(vn, var_labels), s, fixed = TRUE)
            break
          }
        }
        s
      }, character(1L))
    }
    rule <- paste(steps, collapse = " AND ")
    nodes$rule_text[nodes$node_id == nid] <- rule
  }
  nodes
}

.cdp21_layout_tree <- function(nodes) {
  ## 自底向上：叶节点按出现顺序均分 x，父节点取子节点均值；y = -depth
  leaves <- nodes$node_id[nodes$is_leaf]
  if (!length(leaves)) {
    nodes$x <- 0.5
    nodes$y <- 0
    return(nodes)
  }
  xmap <- stats::setNames(
    as.numeric(seq_along(leaves) / (length(leaves) + 1L)),
    as.character(leaves)
  )
  ## 按 depth 降序填父节点
  ord <- order(nodes$depth, decreasing = TRUE)
  for (i in ord) {
    nid <- nodes$node_id[i]
    key <- as.character(nid)
    if (key %in% names(xmap)) next
    left <- 2L * nid
    right <- 2L * nid + 1L
    xs <- c(
      if (as.character(left) %in% names(xmap)) xmap[[as.character(left)]],
      if (as.character(right) %in% names(xmap)) xmap[[as.character(right)]]
    )
    xmap[[key]] <- if (length(xs)) mean(xs) else 0.5
  }
  nodes$x <- vapply(as.character(nodes$node_id), function(k) {
    if (k %in% names(xmap)) unname(xmap[[k]]) else 0.5
  }, numeric(1))
  nodes$y <- -as.numeric(nodes$depth)
  nodes
}

.cdp21_draw_clinical <- function(nodes, bl_cfg, font_family = "Times New Roman") {
  suppressPackageStartupMessages(library(ggplot2))
  if (exists("resolve_plot_font_family", mode = "function")) {
    font_family <- resolve_plot_font_family(font_family)
  }
  root_label <- as.character(bl_cfg$root_label %||% "Enrolled patients")[1L]
  edge_yes <- as.character(bl_cfg$edge_yes %||% "Yes")[1L]
  edge_no <- as.character(bl_cfg$edge_no %||% "No")[1L]
  title <- as.character(bl_cfg$figure_title %||% "CART decision path")[1L]

  nodes <- .cdp21_layout_tree(nodes)
  ## 根上再加一层标题节点
  root_row <- nodes[nodes$node_id == 1L, , drop = FALSE]
  if (!nrow(root_row)) {
    return(ggplot2::ggplot() + ggplot2::theme_void() +
             ggplot2::labs(title = "Empty CART tree"))
  }

  edges <- list()
  labels_edge <- list()
  for (i in seq_len(nrow(nodes))) {
    if (isTRUE(nodes$is_leaf[i])) next
    nid <- nodes$node_id[i]
    left <- 2L * nid
    right <- 2L * nid + 1L
    p <- nodes[nodes$node_id == nid, , drop = FALSE]
    for (child in c(left, right)) {
      if (!child %in% nodes$node_id) next
      c_row <- nodes[nodes$node_id == child, , drop = FALSE]
      ## 菱形问句为「var ≥ cut?」：Yes → 右支，No → 左支
      is_left <- identical(child, left)
      edges[[length(edges) + 1L]] <- data.frame(
        x = p$x, y = p$y, xend = c_row$x, yend = c_row$y,
        stringsAsFactors = FALSE
      )
      labels_edge[[length(labels_edge) + 1L]] <- data.frame(
        x = (p$x + c_row$x) / 2,
        y = (p$y + c_row$y) / 2,
        lab = if (is_left) edge_no else edge_yes,
        stringsAsFactors = FALSE
      )
    }
  }
  edge_df <- if (length(edges)) dplyr::bind_rows(edges) else data.frame()
  elab_df <- if (length(labels_edge)) dplyr::bind_rows(labels_edge) else data.frame()

  ## 节点标签
  nodes$label <- NA_character_
  for (i in seq_len(nrow(nodes))) {
    if (isTRUE(nodes$is_leaf[i])) {
      nodes$label[i] <- paste0(
        "【", nodes$leaf_label[i], "】\n",
        "n=", nodes$n[i],
        if (is.finite(nodes$event_rate[i])) {
          paste0("\nrate=", formatC(round(nodes$event_rate[i], 3), format = "f", digits = 3))
        } else {
          ""
        }
      )
    } else {
      ## 决策菱形：用「var ≥ cut?」作是/否问句（对齐门诊分流图）
      cond <- nodes$condition_right[i]
      if (is.na(cond) || !nzchar(cond)) {
        cond <- paste0(.cdp21_var_label(nodes$split_var[i], bl_cfg$var_labels), "?")
      }
      nodes$label[i] <- paste0(cond, "\nn=", nodes$n[i])
    }
  }

  ## 标题锚点（略高于根）
  title_df <- data.frame(
    x = root_row$x[1L],
    y = root_row$y[1L] + 0.85,
    label = root_label,
    stringsAsFactors = FALSE
  )

  decision <- nodes[!nodes$is_leaf, , drop = FALSE]
  leaves <- nodes[nodes$is_leaf, , drop = FALSE]

  p <- ggplot2::ggplot()
  if (nrow(edge_df)) {
    p <- p + ggplot2::geom_segment(
      data = edge_df,
      ggplot2::aes(x = x, y = y, xend = xend, yend = yend),
      linewidth = 0.6, color = "#444444"
    )
  }
  if (nrow(elab_df)) {
    p <- p + ggplot2::geom_label(
      data = elab_df,
      ggplot2::aes(x = x, y = y, label = lab),
      size = 2.8, linewidth = 0.15, fill = "white",
      family = font_family, label.padding = ggplot2::unit(0.12, "lines")
    )
  }
  if (nrow(decision)) {
    p <- p + ggplot2::geom_label(
      data = decision,
      ggplot2::aes(x = x, y = y, label = label),
      size = 3.0, linewidth = 0.35, fill = "#FFF8E7",
      color = "#8B6914", family = font_family, lineheight = 0.95,
      label.padding = ggplot2::unit(0.35, "lines")
    )
  }
  if (nrow(leaves)) {
    p <- p + ggplot2::geom_label(
      data = leaves,
      ggplot2::aes(x = x, y = y, label = label),
      size = 3.1, linewidth = 0.4, fill = "#E8F4FC",
      color = "#1B4F72", family = font_family, fontface = "bold",
      lineheight = 0.95, label.padding = ggplot2::unit(0.4, "lines")
    )
  }
  p <- p +
    ggplot2::geom_label(
      data = title_df,
      ggplot2::aes(x = x, y = y, label = label),
      size = 3.4, linewidth = 0.3, fill = "#F4F4F4",
      color = "#222222", family = font_family, fontface = "bold"
    ) +
    ggplot2::labs(title = title) +
    ggplot2::theme_void(base_family = font_family) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(
        hjust = 0.5, face = "bold", size = 12, family = font_family,
        margin = ggplot2::margin(b = 8)
      ),
      plot.margin = ggplot2::margin(12, 12, 12, 12)
    ) +
    ggplot2::coord_cartesian(
      xlim = range(c(nodes$x, title_df$x), na.rm = TRUE) + c(-0.12, 0.12),
      ylim = range(c(nodes$y, title_df$y), na.rm = TRUE) + c(-0.35, 0.25),
      expand = FALSE
    )
  p
}

.cdp21_export_rules_table <- function(ctx, nodes, bl_cfg) {
  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables")
  if (!dir.exists(tbl_dir)) dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)

  leaf_tbl <- nodes[nodes$is_leaf, , drop = FALSE]
  out <- data.frame(
    Node = leaf_tbl$node_id,
    Depth = leaf_tbl$depth,
    Rule = leaf_tbl$rule_text,
    N = leaf_tbl$n,
    Event_rate = leaf_tbl$event_rate,
    Predicted = leaf_tbl$pred_class,
    Clinical_label = leaf_tbl$leaf_label,
    stringsAsFactors = FALSE
  )
  ## 也附上内部切点（非叶）便于复核
  split_tbl <- nodes[!nodes$is_leaf, c(
    "node_id", "depth", "split_var", "cut_value",
    "condition_left", "condition_right", "n"
  ), drop = FALSE]
  names(split_tbl) <- c(
    "Node", "Depth", "Split_var", "Cut_value",
    "Condition_left", "Condition_right", "N"
  )

  title <- "CART decision rules and cut-points"
  fp <- file.path(tbl_dir, paste0(title, ".xlsx"))
  if (exists("export_sci_table", mode = "function")) {
    export_sci_table(out, fp, title = title, sheet = "Leaf_rules")
    if (nrow(split_tbl)) {
      export_sci_table(split_tbl, fp, title = paste0(title, " (splits)"), sheet = "Splits")
    }
  } else {
    utils::write.csv(out, file.path(tbl_dir, paste0(title, "_leaf.csv")), row.names = FALSE)
    if (nrow(split_tbl)) {
      utils::write.csv(
        split_tbl, file.path(tbl_dir, paste0(title, "_splits.csv")), row.names = FALSE
      )
    }
  }
  list(leaf = out, splits = split_tbl, path = fp)
}

block_cart_decision_path <- function(ctx, ...) {
  bl_cfg <- ctx$config$cart_decision_path %||% list()
  if (isFALSE(bl_cfg$enable %||% FALSE)) {
    cli::cli_alert_info("config$cart_decision_path$enable=FALSE，跳过。")
    return(ctx)
  }

  cli::cli_h2("cart_decision_path: CART 临床决策路径图")

  picked <- .cdp21_pick_data(ctx, bl_cfg)
  data <- picked$data
  if (is.null(data) || !is.data.frame(data) || !nrow(data)) {
    cli::cli_alert_warning("cart_decision_path: 无可用数据，跳过。")
    return(ctx)
  }

  outcome_col <- .cdp21_resolve_outcome(ctx$config, bl_cfg, names(data))
  if (is.na(outcome_col)) {
    cli::cli_alert_warning("cart_decision_path: 找不到结局列，跳过。")
    return(ctx)
  }

  fr <- .cdp21_resolve_features(ctx, bl_cfg, data, outcome_col)
  ctx <- fr$ctx
  feats <- fr$feats
  if (!length(feats)) {
    cli::cli_alert_warning("cart_decision_path: 无可用特征，跳过。")
    return(ctx)
  }

  y <- .cdp21_prepare_y(data, outcome_col, ctx$config)
  data[[outcome_col]] <- y
  keep <- !is.na(data[[outcome_col]])
  data <- data[keep, , drop = FALSE]

  seed <- bl_cfg$seed %||% ctx$config$splitting$seed %||% ctx$config$imputation$seed %||% 42L
  fit_res <- .cdp21_fit(data, outcome_col, feats, bl_cfg, seed)
  if (!isTRUE(fit_res$ok)) {
    cli::cli_alert_warning("cart_decision_path: 拟合跳过 — {fit_res$reason}")
    return(ctx)
  }
  fit <- fit_res$fit
  if (!is.null(fit_res$prune) && isTRUE(fit_res$prune$applied)) {
    cli::cli_alert_info(
      "CART 剪枝: rule={fit_res$prune$rule}; cp={round(fit_res$prune$cp, 4)}; xval={fit_res$xval}; nsplit={fit_res$prune$nsplit}"
    )
  }
  if (identical(as.character(fit$frame$var[1L]), "<leaf>")) {
    cli::cli_alert_warning(
      "cart_decision_path: 剪枝后仅根叶。若需展示探索树，可设 prune=FALSE 或 prune_rule='min'。"
    )
    # 仍允许导出根叶规则表，但不出分流图
  }

  var_labels <- bl_cfg$var_labels
  leaf_labels <- bl_cfg$leaf_labels
  nodes <- .cdp21_node_table(fit, leaf_labels = leaf_labels, var_labels = var_labels)
  nodes <- .cdp21_fill_rules(nodes, fit, var_labels = var_labels)

  tab <- .cdp21_export_rules_table(ctx, nodes, bl_cfg)
  cli::cli_alert_success("切点规则表已写出: {.file {basename(tab$path)}}")

  only_root <- identical(as.character(fit$frame$var[1L]), "<leaf>")

  font_family <- if (exists("plot_font_from_config", mode = "function")) {
    plot_font_from_config(ctx$config)
  } else {
    ctx$config$plot$font_family %||% "Times New Roman"
  }
  fig_w <- as.numeric(bl_cfg$figure_width %||% 8)[1L]
  fig_h <- as.numeric(bl_cfg$figure_height %||% 6)[1L]

  if (!only_root && isTRUE(bl_cfg$plot_clinical %||% TRUE) && exists("save_figure", mode = "function")) {
    g_clin <- .cdp21_draw_clinical(nodes, bl_cfg, font_family = font_family)
    fig_title <- as.character(bl_cfg$figure_title %||% "Figure S. CART decision path (clinical)")[1L]
    if (!grepl("\\.pdf$", fig_title, ignore.case = TRUE)) {
      fig_title <- paste0(fig_title, ".pdf")
    }
    ctx <- save_figure(
      ctx,
      fig_title,
      function() g_clin,
      width = fig_w,
      height = fig_h
    )
  }

  if (!only_root && isTRUE(bl_cfg$plot_rpart %||% TRUE)) {
    if (!requireNamespace("rpart.plot", quietly = TRUE)) {
      cli::cli_alert_warning("cart_decision_path: 未安装 rpart.plot，跳过统计树图。")
    } else if (exists("save_figure", mode = "function")) {
      fit_plot <- fit
      ctx <- save_figure(
        ctx,
        "Figure S. CART decision path (rpart).pdf",
        function() {
          rpart.plot::rpart.plot(
            fit_plot,
            type = 2,
            extra = 104,
            under = TRUE,
            fallen.leaves = TRUE,
            main = as.character(bl_cfg$figure_title %||% "CART decision path")[1L],
            box.palette = "BuGn",
            shadow.col = "gray80",
            nn = TRUE
          )
          invisible(NULL)
        },
        width = fig_w,
        height = fig_h
      )
    }
  }

  ctx$results$cart_decision_path <- list(
    fit = fit,
    fit_unpruned = fit_res$fit_unpruned,
    prune = fit_res$prune,
    xval = fit_res$xval,
    nodes = nodes,
    features = feats,
    outcome = outcome_col,
    data_scope = picked$scope,
    n = fit_res$n,
    rules_table = tab$leaf,
    splits_table = tab$splits
  )
  cli::cli_alert_success(
    "cart_decision_path 完成（scope={picked$scope}; n={fit_res$n}; features={length(feats)}; leaves={sum(nodes$is_leaf)}）。"
  )
  ctx
}

register_block(
  "cart_decision_path",
  block_cart_decision_path,
  "CART 临床决策路径图：rpart 挖切点 + 分流树图 + 规则表"
)
