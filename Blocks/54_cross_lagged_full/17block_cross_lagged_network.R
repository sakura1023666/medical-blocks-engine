###############################################################################
#  cross_lagged_network — 交叉滞后 CLPN（glmnet），读纵向宽表
#
#  require_data = ctx$data$longitudinal_wide_clpn %||% longitudinal_wide
#  来源: C01_network_analysis.R；按同名 stem 对齐 T1_/T2_
#  出版：Table S8 — 邻接矩阵，行列用 FI 条目真名（无 T1_ 前缀，如 Dressing）
#  register_block: "cross_lagged_network"
###############################################################################

block_cross_lagged_network <- function(ctx, ...) {
  if (!requireNamespace("glmnet", quietly = TRUE))
    stop("cross_lagged_network: 需要 glmnet", call. = FALSE)
  if (!exists("cross_lagged_fi_item_label", mode = "function")) {
    lab_path <- file.path("R", "cross_lagged_fi_item_labels.R")
    if (file.exists(lab_path)) source(lab_path, local = FALSE)
  }
  if (!exists("clpn_node_display", mode = "function")) {
    db_path <- file.path("R", "clpn_node_label_db.R")
    if (file.exists(db_path)) source(db_path, local = FALSE)
  }

  cfg <- ctx$config
  bl <- cfg$cross_lagged_network %||% list()
  df <- ctx$data$longitudinal_wide_clpn %||% ctx$data$longitudinal_wide
  if (is.null(df) || !is.data.frame(df))
    stop("cross_lagged_network: 需要 longitudinal_wide（T1_/T2_ 列）", call. = FALSE)
  df <- as.data.frame(df)
  max_beta <- as.numeric(bl$max_beta %||% 5)
  max_nodes <- as.integer(bl$max_nodes %||% 40L)
  min_n <- as.integer(bl$min_n %||% 30L)
  max_na_rate <- as.numeric(bl$max_na_rate %||% 0.50)
  keep_forced <- isTRUE(bl$keep_forced_nodes %||% FALSE)
  # 默认排除汇总分 / 波次混用伪列；条目级 CLPN
  drop_stems <- unique(c(
    as.character(bl$exclude_stems %||% character(0)),
    "FI", "Frailty", "frailty26_total", "AIP", "AIP_FI",
    # 血压药/诊断代理列（ELSA hedbd* 等）若不想进网可 drop；默认保留低基数
    "score", "cognition_score", "DN"
  ))
  # 血脂默认可选纳入（文献有时含 TG/HDL）；从 drop 中移除以便可选再加入
  if (!isTRUE(bl$include_lipids %||% TRUE)) {
    drop_stems <- unique(c(
      drop_stems,
      "newtg", "newhdl", "Triglycerides", "HDL_Cholesterol", "trig", "hdl"
    ))
  }
  # 默认：虚弱条目 + 疾病结局
  fi_items_only <- !isFALSE(bl$fi_items_only %||% TRUE)
  include_outcome <- if (is.null(bl$include_outcome)) TRUE else isTRUE(bl$include_outcome)
  include_lipids <- isTRUE(bl$include_lipids %||% TRUE)

  t1_all <- grep("^T1_", names(df), value = TRUE)
  t2_all <- grep("^T2_", names(df), value = TRUE)
  stems <- intersect(sub("^T1_", "", t1_all), sub("^T2_", "", t2_all))
  stems <- setdiff(stems, c("time", "Year", "Country", "Cohort", drop_stems))

  force <- as.character(bl$node_stems %||% character(0))
  force <- force[nzchar(force)]
  if (length(force) && is.null(bl$keep_forced_nodes)) keep_forced <- TRUE
  if (length(force)) {
    missing_force <- setdiff(force, stems)
    if (length(missing_force))
      stop("cross_lagged_network: node_stems 缺失于宽表: ",
           paste(missing_force, collapse = ","), call. = FALSE)
    stems <- force
    cli::cli_alert_info("CLPN 使用强制 node_stems ({length(stems)})")
  }

  prefer <- if (exists("cross_lagged_fi_item_stems_preferred", mode = "function")) {
    # 共性 FI 缺陷项（不含血脂）
    setdiff(cross_lagged_fi_item_stems_preferred(),
            c("Triglycerides", "HDL_Cholesterol", "newtg", "newhdl"))
  } else {
    character(0)
  }
  outcome_stems <- intersect(c("Disease01", "Sarcopenia", "sarcop"), stems)
  lipid_stems <- if (isTRUE(include_lipids)) {
    intersect(c("Triglycerides", "HDL_Cholesterol", "newtg", "newhdl"), stems)
  } else character(0)
  item_stems <- intersect(prefer, stems)
  # 各库额外条目（例如 HRS 未 canonical 映射的题号、ELSA 药物代理列）— 仅纳入低基数 0/1
  demo_like <- c(
    "Age", "Gender", "Education", "Marital_Status", "Smoking", "Alcohol_drinking",
    "BMI", "Weight", "Height", "Residence", "Race", "Sex", "Income",
    "Disease_Group", "FI", "Frailty", "frailty26_total", "AIP", "AIP_FI",
    "Hypertension", "T2DM", "Cancer", "HbA1c", "SBP", "DBP", "PP", "HR",
    "Age_wave", "NBPS", "NBPD",
    "Hemoglobin", "Depression_cont", "Depression"
  )
  extra <- setdiff(stems, c(outcome_stems, item_stems, lipid_stems, demo_like))
  # 丢弃 HRS 波次未对齐伪列（nc069 vs oc069 等无法形成 T1/T2 对）
  extra <- extra[!grepl("^[a-z][cgd][0-9]+$", extra)]
  extra_ok <- character(0)
  for (s in extra) {
    x1 <- suppressWarnings(as.numeric(df[[paste0("T1_", s)]]))
    x2 <- suppressWarnings(as.numeric(df[[paste0("T2_", s)]]))
    u1 <- length(unique(stats::na.omit(x1)))
    u2 <- length(unique(stats::na.omit(x2)))
    # 条目型 0/1（或至多 4 水平），排除连续分
    if (u1 >= 2L && u1 <= 4L && u2 >= 2L && u2 <= 4L) extra_ok <- c(extra_ok, s)
  }
  # 限制每库额外项
  if (length(extra_ok) > 12L) extra_ok <- extra_ok[seq_len(12L)]

  if (!length(force)) {
    if (isTRUE(fi_items_only)) {
      # 严格：共性 FI 条目 + 结局 + 可选血脂（不把基线问卷共病/人口学当节点）
      stems <- unique(c(
        if (include_outcome) outcome_stems else character(0),
        item_stems,
        lipid_stems
      ))
    } else {
      other <- setdiff(stems, c(outcome_stems, item_stems, lipid_stems, demo_like))
      stems <- unique(c(
        if (include_outcome) outcome_stems else character(0),
        item_stems,
        lipid_stems,
        other,
        extra_ok
      ))
    }
  }

  cli::cli_alert_info(
    "CLPN 节点候选: outcome={paste(outcome_stems, collapse=',')} | FI items={length(item_stems)} | lipids={length(lipid_stems)} | extra={length(extra_ok)} | total_prefilter={length(stems)}"
  )
  # 丢掉整列缺失过多 / 无变异的节点（否则 complete.cases 会把 N 打成 0）
  # 结局 Disease：incidence 下 T1 常全为 0 → 只要求 T2 有变异（仍作为列进入，以画出文献中的疾病节点）
  ok_stem <- vapply(stems, function(s) {
    is_out <- s %in% outcome_stems
    x1 <- suppressWarnings(as.numeric(df[[paste0("T1_", s)]]))
    x2 <- suppressWarnings(as.numeric(df[[paste0("T2_", s)]]))
    if (mean(is.na(x1)) > max_na_rate || mean(is.na(x2)) > max_na_rate) return(FALSE)
    if (!is_out && length(unique(stats::na.omit(x1))) < 2L) return(FALSE)
    if (length(unique(stats::na.omit(x2))) < 2L) return(FALSE)
    TRUE
  }, logical(1))
  dropped <- stems[!ok_stem]
  if (length(dropped)) {
    cli::cli_alert_warning(
      "CLPN 无变异/高缺失节点 ({length(dropped)}): {paste(head(dropped, 12), collapse=', ')}{if (length(dropped)>12) '...' else ''}"
    )
  }
  if (isTRUE(keep_forced) && length(force)) {
    cli::cli_alert_info("keep_forced_nodes=TRUE：强制节点全部保留（无变异列系数记 0）")
  } else {
    stems <- stems[ok_stem]
  }
  if (length(stems) < 2L)
    stop("cross_lagged_network: 可用 FI 条目 < 2（检查虚弱列名是否已统一）", call. = FALSE)
  if (!isTRUE(keep_forced) && length(stems) > max_nodes)
    stems <- stems[seq_len(max_nodes)]

  t1 <- paste0("T1_", stems)
  t2 <- paste0("T2_", stems)
  for (nm in c(t1, t2)) {
    df[[nm]] <- suppressWarnings(as.numeric(df[[nm]]))
  }
  k <- length(stems)
  X_all <- as.matrix(df[, t1, drop = FALSE])
  # 出版标签：查映射库（condition1→Abdominal obesity；hibpe→Hypertension）
  lab <- if (exists("clpn_node_display", mode = "function")) {
    clpn_node_display(stems, fallback = TRUE)
  } else if (exists("cross_lagged_fi_item_label", mode = "function")) {
    cross_lagged_fi_item_label(stems, with_wave = FALSE)
  } else {
    stems
  }
  # 防重复标签
  if (any(duplicated(lab))) {
    lab <- make.unique(lab, sep = " ")
  }
  adj <- matrix(0, nrow = k, ncol = k, dimnames = list(lab, lab))

  # 小网（昼夜 7 成分+指标）：LASSO 过稀、二项/连续系数不可比。
  # 弹性网 + 全部高斯 + 标准化 Y，边权是可比的标准化回归系数。
  small_net <- k <= 12L
  alpha_used <- as.numeric(bl$alpha %||% if (isTRUE(small_net)) 0.5 else 1)
  gaussian_all <- isTRUE(bl$gaussian_all %||% small_net)
  if (isTRUE(small_net)) {
    cli::cli_alert_info(
      "CLPN 小网: alpha={alpha_used} gaussian_all={gaussian_all}（交叉边更稳、量纲一致）"
    )
  }

  for (i in seq_len(k)) {
    y_var <- df[[t2[[i]]]]
    y_ok <- !is.na(y_var)
    if (sum(y_ok) < min_n) next
    pred_ok <- vapply(seq_len(k), function(j) {
      x <- X_all[y_ok, j]
      if (mean(is.na(x)) > max_na_rate) return(FALSE)
      length(unique(stats::na.omit(x))) >= 2L
    }, logical(1))
    if (!any(pred_ok)) next
    valid <- y_ok & stats::complete.cases(X_all[, pred_ok, drop = FALSE], y_var)
    if (sum(valid) < min_n) next
    X <- X_all[valid, pred_ok, drop = FALSE]
    y <- y_var[valid]
    uv <- length(unique(y[!is.na(y)]))
    if (uv < 2) next
    family_used <- if (isTRUE(gaussian_all)) "gaussian" else if (uv == 2) "binomial" else "gaussian"
    y <- as.numeric(y)
    if (identical(family_used, "gaussian")) {
      ysd <- stats::sd(y, na.rm = TRUE)
      if (is.finite(ysd) && ysd > 1e-12) y <- as.numeric(scale(y))
    }
    sd_ok <- apply(X, 2, function(col) {
      s <- stats::sd(col, na.rm = TRUE)
      is.finite(s) && s > 1e-12
    })
    if (!any(sd_ok)) next
    tryCatch({
      cvfit <- glmnet::cv.glmnet(
        x = X[, sd_ok, drop = FALSE], y = y,
        nfolds = min(10L, max(3L, floor(sum(valid) / 20))),
        family = family_used, alpha = alpha_used, standardize = TRUE
      )
      coef_sub <- as.numeric(stats::coef(cvfit, s = "lambda.min"))[-1]
      coef_vec <- rep(0, k)
      pred_idx <- which(pred_ok)[sd_ok]
      if (length(coef_sub) == length(pred_idx)) coef_vec[pred_idx] <- coef_sub
      coef_vec[abs(coef_vec) > max_beta] <- 0
      adj[, i] <- coef_vec
    }, error = function(e) {
      cli::cli_alert_warning("network {stems[[i]]}: {e$message}")
    })
  }

  out_dir <- file.path(cfg$project$output_dir %||% "Output", "Tables")
  fig_dir <- file.path(cfg$project$output_dir %||% "Output", "Figures")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

  adj_raw <- adj
  dimnames(adj_raw) <- list(t1, t2)
  csv_raw <- file.path(out_dir, "CLPN_adjacency_raw_codes.csv")
  utils::write.csv(adj_raw, csv_raw)

  csv_path <- file.path(out_dir, "CLPN_adjacency.csv")
  utils::write.csv(adj, csv_path)
  db <- as.character(cfg$project$database %||% "Cohort")[1L]
  s8_path <- file.path(out_dir, paste0("Table S8-", db, ". CLPN adjacency.csv"))
  utils::write.csv(adj, s8_path)

  pdf_path <- file.path(fig_dir, "Fig_CLPN_network.pdf")
  if (requireNamespace("qgraph", quietly = TRUE) && any(adj != 0)) {
    grDevices::pdf(pdf_path, width = 9, height = 9)
    qgraph::qgraph(adj, labels = lab, edge.labels = FALSE, layout = "spring")
    grDevices::dev.off()
  } else {
    grDevices::pdf(pdf_path, width = 9, height = 9)
    graphics::image(t(adj), main = "CLPN adjacency", axes = FALSE)
    graphics::axis(1, at = seq(0, 1, length.out = k), labels = lab, las = 2, cex.axis = 0.55)
    graphics::axis(2, at = seq(0, 1, length.out = k), labels = lab, las = 2, cex.axis = 0.55)
    grDevices::dev.off()
  }

  dict_path <- file.path(out_dir, "CLPN_FI_item_label_dictionary.csv")
  utils::write.csv(
    data.frame(
      stem = stems, T1_code = t1, T2_code = t2, label = lab,
      stringsAsFactors = FALSE
    ),
    dict_path,
    row.names = FALSE
  )

  nz <- sum(adj != 0)
  ctx$results$cross_lagged_network <- list(
    adjacency = adj, path = csv_path, table_s8 = s8_path,
    raw_path = csv_raw, dictionary = dict_path, figure = pdf_path,
    stems = stems, labels = lab, n_nonzero = nz
  )
  cli::cli_alert_success("CLPN Table S8 已写: {s8_path} (k={k}, nonzero={nz})")
  if (nz == 0L)
    cli::cli_alert_warning("CLPN 邻接全 0：请检查条目列缺失/常量或样本量")
  ctx
}

register_block("cross_lagged_network", block_cross_lagged_network, "交叉滞后 CLPN 网络 (Table S8)")
