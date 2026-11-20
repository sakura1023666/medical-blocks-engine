###############################################################################
# tj_gbmtm_fit — 双指标联合轨迹（GBMTM）拟合、选 K、命名、类别/后验落盘
#
# 统计内核：R/gbmtm_core.R（gbmtm_to_long / gbmtm_fit / gbmtm_select / gbmtm_label）
# 口径：在「master 宽表（含真缺失波次）」上拟合；EM 局部独立自动处理缺失。
#      轨迹定类在操作层做一次（锁定类别），推断阶段类别列固定不再随插补重估。
#
# joint_trajectory = list(
#   index_pairs = list(BMI_TyG = c("TyG","BMI"), WHtR_TyG = c("TyG","WHtR")),
#   waves = c(2,4,6), wave_suffix = "_w",
#   k_range = 2:6, poly_degree = 2L, n_start = 10L, seed = 42L,
#   force_K = NULL,                       # 可选锁定 K（否则按 select）
#   force_K_by_system = list(BMI_TyG = 4L, WHtR_TyG = 4L),  # 按对标文献锁 K
#   avepp_min = 0.70,                     # 数据驱动质量门槛（内核 gbmtm_select）
#   min_prop_floor = 0.05,                # 最小类占比门槛
#   group_col_prefix = "grp_"             # 输出列 grp_BMI_TyG
# )
# 选 K 铁律：文献口径为六项标准（BIC/AIC/entropy/AvePP/OCC/最小类+临床可解释）；
# 大队列 AIC/BIC 单调下降无低谷时禁止 naive which.min，锁文献 K 并在表注/Methods 披露。
#
# register_block: "tj_gbmtm_fit"
# 写: ctx$results$tj_gbmtm[[system]]（fit/label/long）, ctx$data$cleaned[[grp_*]]
#     ctx$results$tj_classes[[system]]（id, class_map, label, n, prop）
# 落盘: results/trajectories/gbmtm_<system>.rds, classes_<system>.csv, posterior_<system>.csv
#       Tables/Table_Trajectory_IC_<system>.xlsx（AIC/BIC/熵/AvePP/OCC/最小类）
###############################################################################

block_tj_gbmtm_fit <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  suppressMessages({
    source(file.path(root, "R/literature_trajectory_joint.R"), local = FALSE)
    source(file.path(root, "R/gbmtm_core.R"), local = FALSE)
  })
  bl <- ctx$config$joint_trajectory %||% stop("tj_gbmtm_fit: 缺 config$joint_trajectory", call. = FALSE)
  id_col <- bl$id_column %||% ctx$config$data$id_column %||% "id"
  df <- ctx$data$cleaned %||% ctx$data$raw
  if (is.null(df)) stop("tj_gbmtm_fit: 无数据", call. = FALSE)

  waves <- as.integer(bl$waves)
  sfx <- bl$wave_suffix %||% "_w"
  k_range <- as.integer(bl$k_range %||% 2:6)
  deg <- as.integer(bl$poly_degree %||% 2L)
  n_start <- as.integer(bl$n_start %||% 10L)
  seed <- as.integer(bl$seed %||% 42L)
  prefix <- bl$group_col_prefix %||% "grp_"
  out_root <- file.path(ctx$config$project$output_dir %||% "Output")
  traj_dir <- file.path(out_root, "results", "trajectories")
  tab_dir <- file.path(out_root, "Tables")
  dir.create(traj_dir, showWarnings = FALSE, recursive = TRUE)
  dir.create(tab_dir, showWarnings = FALSE, recursive = TRUE)

  ctx$results$tj_gbmtm <- list(); ctx$results$tj_classes <- list()
  for (sys in names(bl$index_pairs)) {
    inds <- bl$index_pairs[[sys]]
    spec <- lapply(inds, function(ix) {
      list(name = ix, cols = paste0(ix, sfx, waves), t = as.numeric(waves))
    })
    d <- tryCatch(gbmtm_to_long(tj_to_long(df, spec, id_col = id_col)),
                  error = function(e) { cli::cli_alert_danger("GBMTM 长表失败 {sys}: {conditionMessage(e)}"); NULL })
    if (is.null(d) || !nrow(d)) { cli::cli_alert_danger("GBMTM {sys}: 长表为空，跳过"); next }

    fk_force <- bl$force_K
    if (is.list(bl$force_K_by_system) && !is.null(bl$force_K_by_system[[sys]])) {
      fk_force <- bl$force_K_by_system[[sys]]
    }
    # 定稿「轨迹发病」口径：按对标文献锁 K（如 Liu 2026 K=4 both systems），
    # 或数据驱动时用可调质量门槛（AvePP / 最小类占比）。
    sel <- gbmtm_select(d, k_range = k_range, deg = deg, n_start = n_start, seed = seed,
                        k_lock = if (!is.null(fk_force)) as.integer(fk_force)[1L] else NULL,
                        avepp_min = as.numeric(bl$avepp_min %||% 0.70),
                        min_prop_floor = as.numeric(bl$min_prop_floor %||% 0.05))
    K_opt <- if (!is.null(fk_force) && fk_force %in% sel$table$K) as.integer(fk_force)[1L] else sel$K_opt
    fk <- sel$fits[[which(sel$table$K == K_opt)]]
    lab <- gbmtm_label(fk)

    # 类别标签挂回主表（操作层固定列，推断阶段随 mi_complete_aligned extra 带回）
    # class_map = 命名整数向量（names=id, value=类号 1..K）；label 表按类号取展示名
    gcol <- paste0(prefix, sys)
    cls_int <- as.integer(fk$class_map[as.character(df[[id_col]])])
    df[[gcol]] <- lab$label[cls_int]
    n_unl <- sum(is.na(df[[gcol]]))
    if (n_unl > 0) cli::cli_alert_warning("GBMTM {sys}: {n_unl} 人无类别标签（轨迹全缺失），推断阶段将剔除")

    # 落盘 rds（供 Fig 轨迹曲线 + 敏感性 PP 加权）
    saveRDS(list(system = sys, fit_all = sel, K_opt = K_opt, sel_fit = fk,
                 label_tab = lab, long = d),
            file.path(traj_dir, paste0("gbmtm_", sys, ".rds")))
    cls <- data.frame(id = names(fk$class_map), class_map = unname(fk$class_map))
    cls <- merge(cls, lab, by.x = "class_map", by.y = "class", all.x = TRUE)
    utils::write.csv(cls[, c("id", "class_map", "label", "n", "prop")],
                     file.path(traj_dir, paste0("classes_", sys, ".csv")), row.names = FALSE)
    pp <- as.data.frame(fk$posterior); names(pp) <- paste0("pp_", sys, "_", seq_len(ncol(fk$posterior)))
    pp$id <- names(fk$class_map)
    utils::write.csv(pp, file.path(traj_dir, paste0("posterior_", sys, ".csv")), row.names = FALSE)

    ic <- sel$table
    ic$K_opt <- K_opt; ic$pick_aic <- sel$pick_aic; ic$pick_bic <- sel$pick_bic
    export_sci_table(ic, file.path(tab_dir, paste0("Table_Trajectory_IC_", sys, ".xlsx")),
                     title = paste0("Trajectory model selection (GBMTM) - ", sys),
                     table_footnotes = c(
                       "K = number of joint trajectory classes; deg = polynomial degree.",
                       "AIC/BIC primary; AvePP >= 0.70 and smallest class >= 5% as soft gates.",
                       paste0("Selected K = ", K_opt,
                              if (!is.null(fk_force))
                                " (locked per reference standard; selection by BIC/AIC/entropy/AvePP/OCC/class size, not curve trough alone)"
                              else " (data-driven)")))

    ctx$results$tj_gbmtm[[sys]] <- list(select = sel, K_opt = K_opt, fit = fk, label = lab, long = d)
    ctx$results$tj_classes[[sys]] <- cls
    cli::cli_alert_success("GBMTM {sys}: K_opt={K_opt} (AIC pick={sel$pick_aic}, BIC pick={sel$pick_bic}); n={nrow(cls)}")
  }

  ctx$data$cleaned <- df
  if (!is.null(ctx$data$raw)) ctx$data$raw <- df
  invisible(ctx)
}

register_block("tj_gbmtm_fit", block_tj_gbmtm_fit, "双指标联合轨迹 GBMTM 拟合+选K+命名+类别落盘")
