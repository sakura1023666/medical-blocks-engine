###############################################################################
#  08block_ml_nafld_omics_display.R — 34 脂肪肝 代谢组学展示 + Nomogram + 风险分层
#
#  register_block: "ml_nafld_omics_display"
#  典型位置: ml_nafld_external_bridge 之后（模块六/七补齐）
#
#  严格按方案与同类文献（AP&T 2021 尿类固醇 GMLVQ / Frontiers Nutr 2026
#  靶向代谢+OPLS-DA/RF/SVM / PLOS One 2025 CHB+MASLD / 尿重金属 XGBoost+SHAP）
#  补齐代谢组学「身份证图」与模块七转化输出：
#
#  Figure 8  代谢组学概览（A PLS-DA 得分 / B 火山图 / C top 差异代谢物热图 / D 相关网络）
#  Figure 9  Nomogram + P5–P95 标准化 0–100 简化评分（≤10 变量）+ 校准/风险分层
#  Figure S2 院内四大通路富集（bar + dot；与 Figure 7C/GEO 呼应）
#  Figure S3 SHAP beeswarm 大图（对 Figure 5 补充）
#  Table S15 差异代谢物全表（90 U_ 池 Wilcoxon FDR + log2FC）
#  Table S16 代谢物-临床 Spearman 相关矩阵（top 显著对）
#  Table S17 简化评分系数与分层切点（低/中/高风险）
#  Table S18 NAFLD 组内中医证型分层；Table S19 低/中/高风险代表病例
#  ShinyApp  原始值输入、0–100 总分、个体概率与风险层在线计算雏形
#
#  config$omics_display = list(enable = TRUE, top_n_heatmap = 25L,
#                              nomogram_max_features = 10L)
###############################################################################

.nafld_od_dirs <- function(cfg) {
  study <- (cfg$project %||% list())$output_dir %||% getwd()
  list(study = study,
       tables = file.path(study, "Tables"),
       figures = file.path(study, "Figures"),
       work = file.path(study, "omics_display"),
       supp_tab = file.path(study, "supplement", "table"),
       supp_fig = file.path(study, "supplement", "figure"))
}

# 数据装配：临床 + 尿代谢组（原始 RData 重建，不走 checkpoint 剥列表）
.nafld_od_data <- function(cfg) {
  path <- (cfg$data %||% list())$rawdata_path
  if (!file.exists(path)) return(NULL)
  e <- new.env(); load(path, envir = e)
  obj <- cfg$data$rawdata_obj %||% "FattyLiver"
  if (!exists(obj, envir = e)) return(NULL)
  d0 <- get(obj, envir = e)
  mobj <- cfg$data$metabolome_obj %||% "FattyLiver_metabolome"
  if (exists(mobj, envir = e)) {
    mm <- get(mobj, envir = e); idc <- cfg$data$id_column %||% "ID"
    uc <- grep("^U_", names(mm), value = TRUE)
    if (idc %in% names(mm) && idc %in% names(d0) && length(uc))
      d0 <- merge(d0, mm[, c(idc, uc), drop = FALSE], by = idc, all.x = TRUE)
  }
  if (exists(".nafld_cm_creatinine_correct", mode = "function"))
    d0 <- .nafld_cm_creatinine_correct(cfg, d0)
  d0
}

# 差异代谢物（Wilcoxon BH-FDR + log2 中位数比）
.nafld_od_de_metab <- function(dat, alpha = 0.05) {
  uc <- grep("^U_", names(dat), value = TRUE)
  y <- as.integer(as.character(dat$Disease) == "NAFLD")
  res <- do.call(rbind, lapply(uc, function(cc) {
    x <- suppressWarnings(as.numeric(dat[[cc]]))
    g1 <- x[y == 1 & is.finite(x)]; g0 <- x[y == 0 & is.finite(x)]
    if (length(g1) < 3L || length(g0) < 3L)
      return(data.frame(feature = cc, mean_NAFLD = NA_real_, mean_Normal = NA_real_,
                        log2FC = NA_real_, p = NA_real_, stringsAsFactors = FALSE))
    pv <- tryCatch(stats::wilcox.test(g1, g0)$p.value, error = function(e) NA_real_)
    m1 <- stats::median(g1); m0 <- stats::median(g0)
    fc <- if (m1 > 0 && m0 > 0) log2(m1 / m0) else NA_real_
    data.frame(feature = cc, mean_NAFLD = mean(g1), mean_Normal = mean(g0),
               log2FC = fc, p = pv, stringsAsFactors = FALSE)
  }))
  res$padj <- stats::p.adjust(res$p, method = "BH")
  res$sig <- res$padj < alpha & is.finite(res$log2FC)
  res[order(res$p), ]
}

# 轻量 PLS-DA 得分（不依赖 mixOmics；2 类 NIPALS PLS1）
.nafld_od_plsda_scores <- function(X, y, ncomp = 2L) {
  # X: samples × features（已中心化/标准化）；y: 0/1
  X0 <- as.matrix(X)
  storage.mode(X0) <- "double"
  y0 <- as.numeric(y)
  y0 <- as.numeric(scale(y0))
  ncomp <- max(1L, min(as.integer(ncomp), ncol(X0), nrow(X0) - 1L))
  E <- X0
  f <- y0
  Tsc <- matrix(NA_real_, nrow(X0), ncomp)
  for (h in seq_len(ncomp)) {
    w <- crossprod(E, f)
    nw <- sqrt(sum(w^2))
    if (!is.finite(nw) || nw < .Machine$double.eps) {
      Tsc[, h:ncomp] <- 0
      break
    }
    w <- w / nw
    t <- as.numeric(E %*% w)
    p <- as.numeric(crossprod(E, t) / max(sum(t * t), .Machine$double.eps))
    q <- sum(f * t) / max(sum(t * t), .Machine$double.eps)
    E <- E - t %*% t(p)
    f <- f - q * t
    Tsc[, h] <- t
  }
  colnames(Tsc) <- paste0("Comp", seq_len(ncomp))
  Tsc
}

# ── Figure 8: A PLS-DA 得分 / B 火山 / C 组分割热图 / D 相关（文献式）──
.nafld_od_fig8 <- function(cfg, dat, de, D, log) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) { log("无 ggplot2，跳过 Fig8", "warn"); return(invisible(FALSE)) }
  `%||%` <- function(a, b) if (is.null(a)) b else a
  od <- cfg$omics_display %||% list()
  fc_cut <- as.numeric(od$volcano_fc_cutoff %||% 0.25)
  topn_hm <- as.integer(od$top_n_heatmap %||% 25L)
  th <- ggplot2::theme_classic(base_size = 11) +
    ggplot2::theme(plot.title = ggplot2::element_text(face = "bold", size = 11),
                   plot.subtitle = ggplot2::element_text(size = 8.5, colour = "grey30"))
  y <- as.integer(as.character(dat$Disease) == "NAFLD")
  uc <- de$feature
  uc <- uc[vapply(uc, function(f) f %in% names(dat) &&
    sum(is.finite(suppressWarnings(as.numeric(dat[[f]])))) >= 10L, logical(1))]
  X <- t(vapply(uc, function(cc) suppressWarnings(as.numeric(dat[[cc]])), numeric(nrow(dat))))
  rownames(X) <- uc
  ok_s <- stats::complete.cases(t(X))
  X <- X[, ok_s, drop = FALSE]
  y <- y[ok_s]
  lx <- log2(pmax(X, min(X[X > 0], na.rm = TRUE) / 10))
  row_sd <- apply(lx, 1L, stats::sd, na.rm = TRUE)
  lx <- lx[is.finite(row_sd) & row_sd > 0, , drop = FALSE]

  # A) PLS-DA：左 2D 得分 + 右 Comp1 分组分布（校正后 2D 椭圆易套叠，Comp1 才是监督分离主轴）
  Xs <- scale(t(lx), center = TRUE, scale = TRUE)
  Xs[!is.finite(Xs)] <- 0
  sc <- .nafld_od_plsda_scores(Xs, y, ncomp = 2L)
  sdf <- data.frame(Comp1 = sc[, 1], Comp2 = sc[, 2],
                    Group = factor(ifelse(y == 1, "NAFLD", "Normal"),
                                   levels = c("Normal", "NAFLD")))
  mu <- stats::aggregate(cbind(Comp1, Comp2) ~ Group, sdf, mean)
  sep <- sqrt(sum((mu[mu$Group == "NAFLD", c("Comp1", "Comp2")] -
                     mu[mu$Group == "Normal", c("Comp1", "Comp2")])^2))
  # Comp1 组间分离（Mann-Whitney AUC）
  r1 <- rank(sdf$Comp1)
  n1 <- sum(sdf$Group == "NAFLD"); n0 <- sum(sdf$Group == "Normal")
  auc1 <- (sum(r1[sdf$Group == "NAFLD"]) - n1 * (n1 + 1) / 2) / (n1 * n0)
  pA_scatter <- ggplot2::ggplot(sdf, ggplot2::aes(Comp1, Comp2, colour = Group, fill = Group)) +
    ggplot2::geom_point(size = 1.7, alpha = 0.75, shape = 16) +
    ggplot2::stat_ellipse(ggplot2::aes(fill = Group), geom = "polygon",
                          alpha = 0.10, colour = NA, level = 0.95) +
    ggplot2::stat_ellipse(ggplot2::aes(colour = Group), geom = "path",
                          level = 0.95, linewidth = 0.65, show.legend = FALSE) +
    ggplot2::scale_colour_manual(values = c(Normal = "#2166ac", NAFLD = "#b2182b"), name = NULL) +
    ggplot2::scale_fill_manual(values = c(Normal = "#2166ac", NAFLD = "#b2182b"), name = NULL) +
    ggplot2::labs(title = "A  PLS-DA scores",
                  subtitle = sprintf("Creatinine-corrected; centroid dist=%.2f", sep),
                  x = "Component 1", y = "Component 2") + th +
    ggplot2::theme(legend.position = "bottom")
  pA_comp1 <- ggplot2::ggplot(sdf, ggplot2::aes(Group, Comp1, fill = Group)) +
    ggplot2::geom_violin(alpha = 0.25, colour = NA, width = 0.9) +
    ggplot2::geom_boxplot(width = 0.28, outlier.size = 0.6, alpha = 0.9) +
    ggplot2::scale_fill_manual(values = c(Normal = "#2166ac", NAFLD = "#b2182b"), guide = "none") +
    ggplot2::labs(title = "Comp1 by group",
                  subtitle = sprintf("MW AUC=%.2f (dilution removed)", auc1),
                  x = NULL, y = "PLS-DA Component 1") + th
  # 拼成单面板 A（左散点 | 右 Comp1）
  if (requireNamespace("patchwork", quietly = TRUE)) {
    pA <- pA_scatter + pA_comp1 + patchwork::plot_layout(widths = c(1.35, 0.85))
  } else {
    pA <- pA_scatter
  }

  # B) 火山：着色与虚线统一为 FDR<0.05 且 |log2FC|≥fc_cut（文献双门槛）
  v <- de[is.finite(de$log2FC) & is.finite(de$p) & is.finite(de$padj), ]
  v$pass <- !is.na(v$padj) & v$padj < 0.05 & abs(v$log2FC) >= fc_cut
  v$cls <- ifelse(!v$pass, "NS", ifelse(v$log2FC > 0, "Up", "Down"))
  v$cls <- factor(v$cls, levels = c("Up", "Down", "NS"))
  n_up <- sum(v$cls == "Up"); n_dn <- sum(v$cls == "Down")
  lab <- v[v$pass, ]
  lab <- lab[order(lab$padj, lab$p), ]
  lab <- lab[seq_len(min(12L, nrow(lab))), ]
  pB <- ggplot2::ggplot(v, ggplot2::aes(log2FC, -log10(p))) +
    ggplot2::geom_point(ggplot2::aes(colour = cls), size = 1.6, alpha = 0.85) +
    ggplot2::scale_colour_manual(
      values = c(Up = "#b2182b", Down = "#2166ac", NS = "grey72"), name = NULL,
      drop = FALSE) +
    ggplot2::geom_hline(yintercept = -log10(0.05), linetype = 3, colour = "grey40") +
    ggplot2::geom_vline(xintercept = c(-fc_cut, fc_cut), linetype = 3, colour = "grey40") +
    ggplot2::annotate("text", x = max(v$log2FC, na.rm = TRUE), y = max(-log10(v$p), na.rm = TRUE) * 0.95,
                      label = sprintf("Up %d", n_up), hjust = 1, colour = "#b2182b",
                      size = 3.5, fontface = "bold") +
    ggplot2::annotate("text", x = min(v$log2FC, na.rm = TRUE), y = max(-log10(v$p), na.rm = TRUE) * 0.95,
                      label = sprintf("Down %d", n_dn), hjust = 0, colour = "#2166ac",
                      size = 3.5, fontface = "bold")
  if (nrow(lab) && requireNamespace("ggrepel", quietly = TRUE)) {
    pB <- pB + ggrepel::geom_text_repel(
      data = lab, ggplot2::aes(label = sub("^U_", "", feature)),
      size = 2.6, max.overlaps = 14, segment.size = 0.25, colour = "grey15",
      min.segment.length = 0.05)
  }
  pB <- pB + ggplot2::labs(
    title = "B  Volcano (urinary metabolites)",
    subtitle = sprintf(
      "Wilcoxon; coloured if FDR<0.05 & |log2FC|\u2265%.2f (n=%d/%d). Not genes.",
      fc_cut, n_up + n_dn, nrow(v)),
    x = "log2 FC (NAFLD / Normal)", y = "-log10 P") + th

  # C) 热图：仅双门槛差异物；列按组分割（Normal | NAFLD），组内按平均 z 排序
  sigd <- v[v$pass, ]
  sigd <- sigd[order(sigd$padj, -abs(sigd$log2FC)), ]
  if (nrow(sigd) < 3L) {
    # 回退：仅 FDR
    sigd <- de[de$sig & de$feature %in% rownames(lx), ]
    sigd <- sigd[order(sigd$padj), ]
  }
  topn <- min(topn_hm, nrow(sigd)); topn <- max(topn, min(8L, nrow(sigd)))
  sigd <- sigd[seq_len(topn), , drop = FALSE]
  sigd <- sigd[sigd$feature %in% rownames(lx), , drop = FALSE]
  pC <- NULL
  if (requireNamespace("ComplexHeatmap", quietly = TRUE) &&
      requireNamespace("circlize", quietly = TRUE) && nrow(sigd) >= 3) {
    M <- lx[sigd$feature, , drop = FALSE]
    z <- t(scale(t(M)))
    z[!is.finite(z)] <- 0
    # 行：按 NAFLD−Normal 均值差排序（上调在上），再轻度行聚类可选
    d_mean <- rowMeans(z[, y == 1, drop = FALSE]) - rowMeans(z[, y == 0, drop = FALSE])
    z <- z[order(-d_mean), , drop = FALSE]
    grp <- factor(ifelse(y == 1, "NAFLD", "Normal"), levels = c("Normal", "NAFLD"))
    # 组内按该行均值（上调代谢物平均）排序，使块状更清晰
    score <- colMeans(z[seq_len(min(8L, nrow(z))), , drop = FALSE])
    o <- order(grp, score)
    z <- z[, o, drop = FALSE]
    grp <- grp[o]
    colf <- circlize::colorRamp2(c(-2, 0, 2), c("#2166ac", "white", "#b2182b"))
    ha <- ComplexHeatmap::HeatmapAnnotation(
      Group = grp,
      col = list(Group = c(Normal = "#2166ac", NAFLD = "#b2182b")),
      show_annotation_name = TRUE,
      annotation_name_side = "left",
      simple_anno_size = grid::unit(3.5, "mm"))
    rn <- sub("^U_", "", rownames(z))
    hp <- ComplexHeatmap::Heatmap(
      z, name = "z-score", col = colf,
      top_annotation = ha,
      cluster_rows = FALSE, cluster_columns = FALSE,
      column_split = grp,
      cluster_column_slices = FALSE,
      column_gap = grid::unit(2.5, "mm"),
      show_column_names = FALSE,
      row_labels = rn,
      row_names_gp = grid::gpar(fontsize = 7),
      row_names_side = "left",
      column_title = NULL,
      heatmap_legend_param = list(
        title = "Row z-score", title_gp = grid::gpar(fontsize = 9),
        labels_gp = grid::gpar(fontsize = 8)))
    pC <- hp
  }

  # D) 相关热图
  clin <- intersect(c("Age", "BMI", "ALT", "AST", "GGT", "Glucose", "Triglycerides",
                      "Total_Cholesterol", "LDL", "Creatinine"), names(dat))
  pD <- ggplot2::ggplot() + th
  if (length(clin) >= 3 && nrow(sigd) >= 3) {
    cv <- vapply(sigd$feature, function(f) suppressWarnings(as.numeric(dat[[f]])), numeric(nrow(dat)))
    ccv <- vapply(clin, function(f) suppressWarnings(as.numeric(dat[[f]])), numeric(nrow(dat)))
    R <- matrix(NA_real_, nrow = nrow(sigd), ncol = length(clin),
                dimnames = list(sub("^U_", "", sigd$feature), clin))
    P <- R
    for (i in seq_len(nrow(sigd))) for (j in seq_along(clin)) {
      ct <- tryCatch(stats::cor.test(cv[, i], ccv[, j], method = "spearman"), error = function(e) NULL)
      if (!is.null(ct)) { R[i, j] <- unname(ct$estimate); P[i, j] <- ct$p.value }
    }
    if (nrow(R) > 2) {
      hc <- stats::hclust(stats::dist(1 - abs(R)))
      R <- R[hc$order, , drop = FALSE]
      P <- P[hc$order, , drop = FALSE]
    }
    lg <- data.frame(Metabolite = rownames(R)[row(R)], Clinical = colnames(R)[col(R)],
                     rho = as.vector(R), p = as.vector(P), row.names = NULL)
    lg$star <- ifelse(is.na(lg$p), "", ifelse(lg$p < 0.001, "***",
                    ifelse(lg$p < 0.01, "**", ifelse(lg$p < 0.05, "*", ""))))
    lg$Clinical <- factor(lg$Clinical, levels = clin)
    lg$Metabolite <- factor(lg$Metabolite, levels = rev(rownames(R)))
    pD <- ggplot2::ggplot(lg, ggplot2::aes(Clinical, Metabolite, fill = rho)) +
      ggplot2::geom_tile(colour = "white", linewidth = 0.4) +
      ggplot2::geom_text(ggplot2::aes(label = star), size = 2.4, colour = "black", vjust = 0.75) +
      ggplot2::scale_fill_gradient2(low = "#2166ac", mid = "white", high = "#b2182b",
                                    midpoint = 0, limits = c(-1, 1), name = "Spearman rho") +
      ggplot2::labs(title = "D  Metabolite-clinical correlation",
                    subtitle = "Spearman rho; * P<0.05, ** P<0.01, *** P<0.001",
                    x = NULL, y = NULL) +
      th + ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1, size = 8.5),
                          axis.text.y = ggplot2::element_text(size = 6.5))
  }

  out_pdf <- file.path(D$figures, "Figure 8. Metabolomics overview.pdf")
  grDevices::pdf(out_pdf, width = 14, height = 12, useDingbats = FALSE)
  gl <- grid::grid.layout(nrow = 2, ncol = 2, heights = grid::unit(c(1, 1.15), "null"))
  grid::pushViewport(grid::viewport(layout = gl))
  grid::pushViewport(grid::viewport(layout.pos.row = 1, layout.pos.col = 1))
  print(pA, newpage = FALSE); grid::upViewport()
  grid::pushViewport(grid::viewport(layout.pos.row = 1, layout.pos.col = 2))
  print(pB, newpage = FALSE); grid::upViewport()
  if (!is.null(pC)) {
    grid::pushViewport(grid::viewport(layout.pos.row = 2, layout.pos.col = 1, width = 0.96))
    ComplexHeatmap::draw(pC, newpage = FALSE,
                         padding = grid::unit(c(2, 2, 8, 4), "mm"),
                         column_title = sprintf(
                           "C  Top %d differential metabolites (split by group)", nrow(sigd)),
                         column_title_gp = grid::gpar(fontsize = 11, fontface = "bold"))
    grid::upViewport()
  }
  if (ggplot2::is.ggplot(pD) && length(pD$layers)) {
    grid::pushViewport(grid::viewport(layout.pos.row = 2, layout.pos.col = 2))
    print(pD, newpage = FALSE); grid::upViewport()
  }
  grid::popViewport()
  grDevices::dev.off()

  # 同步 summary
  sum_fig <- file.path(D$study, "summary_result", "figure")
  if (dir.exists(sum_fig)) {
    file.copy(out_pdf, file.path(sum_fig, basename(out_pdf)), overwrite = TRUE)
    if (dir.exists(file.path(sum_fig, "pdf")))
      file.copy(out_pdf, file.path(sum_fig, "pdf", basename(out_pdf)), overwrite = TRUE)
  }
  log(sprintf(
    "Figure 8 已重画：PLS-DA 分离距=%.2f；火山双门槛 Up=%d Down=%d；热图 %d 代谢物（按组分割）",
    sep, n_up, n_dn, nrow(sigd)))
  invisible(TRUE)
}

# ── Figure S2: 院内四大通路富集（对齐方案/文献 KEGG 风格）────────────────
.nafld_od_figS2 <- function(cfg, de, D, log) {
  pathmap <- .nafld_od_pathway_map()
  # de$feature 带 U_ 前缀与重复峰后缀（U_Fumaric_acid_125）；pathway map 用裸名 → 归一后再匹配
  norm <- function(x) gsub("_\\d+$", "", sub("^U_", "", x))
  de_n <- de; de_n$pn <- norm(de_n$feature)
  bg_n <- length(unique(de_n$pn))
  rows <- do.call(rbind, lapply(names(pathmap), function(pw) {
    hit <- de_n[de_n$pn %in% norm(pathmap[[pw]]) & de_n$sig, , drop = FALSE]
    # 同一代谢物多个检测峰只计一次
    hit <- hit[!duplicated(hit$pn), , drop = FALSE]
    data.frame(pathway = pw, n_sig = nrow(hit),
               metabolites = paste(hit$pn, collapse = "; "),
               min_padj = if (nrow(hit)) min(hit$padj) else NA_real_,
               stringsAsFactors = FALSE)
  }))
  # 超几何背景：通路映射池占全部检测代谢物的比例
  rows$pathway_pool_n <- vapply(names(pathmap),
                                function(pw) length(intersect(unique(norm(pathmap[[pw]])),
                                                              unique(de_n$pn))), integer(1))
  rows$hyper_p <- stats::phyper(rows$n_sig - 1L, rows$pathway_pool_n,
                                bg_n - rows$pathway_pool_n,
                                sum(de_n$sig & !duplicated(de_n$pn)), lower.tail = FALSE)
  utils::write.csv(rows, file.path(D$work, "pathway_enrichment.csv"), row.names = FALSE)
  grDevices::pdf(file.path(D$supp_fig, "Figure S2. Hospital pathway enrichment.pdf"),
                 width = 9, height = 4.5)
  par(mar = c(4, 12, 3, 1))
  hitn <- pmax(rows$n_sig, 0.05)
  barplot(hitn, horiz = TRUE, las = 1, col = "#4d9221",
          names.arg = rows$pathway, xlab = "# significant metabolites (FDR<0.05)",
          main = "Hospital urinary pathway enrichment (scheme 4 pathways)")
  dev.off()
  log("Figure S2 (院内通路富集) 已生成")
  rows
}

# 代谢物→方案四大通路（与 external_bridge 同一映射，保持一致）
.nafld_od_pathway_map <- function() {
  src <- tryCatch(get(".nafld_ext_hosp_metab_to_pathway", mode = "function")(), error = function(e) NULL)
  if (!is.null(src)) return(src)
  list(
    "Lipid/FA metabolism" = c("Oleic_acid","Stearic_acid","Myristic_acid","Butyric_acid",
      "Palmitic_acid","Pentadecanoic_acid","Arachidonic_acid","alpha_Linolenic_acid","Propionic_acid"),
    "Bile acid metabolism" = c("Cholic_acid"),
    "Amino acid metabolism" = c("L_Threonine","L_Serine","Glycine","Alanine","Proline","Lysine",
      "Histidine","Tryptophan","Methionine","Ornithine","Spermidine","Putrescine"),
    "Oxidative stress / inflammation" = c("Fumaric_acid","Malic_acid","Citric_acid","Succinic_acid",
      "Glutaric_acid","Histamine","Threitol","Gentisic_acid","Gallic_acid")
  )
}

# ── Figure 9: Nomogram + 简化评分 ────────────────────────────────────────
.nafld_od_fig9 <- function(cfg, dat, D, log) {
  if (!requireNamespace("rms", quietly = TRUE)) { log("无 rms，Nomogram 跳过", "warn"); return(NULL) }
  od <- cfg$omics_display %||% list()
  maxf <- as.integer(od$nomogram_max_features %||% 10L)
  max_clin <- as.integer(od$nomogram_max_clinical %||% 4L)
  max_met  <- as.integer(od$nomogram_max_metabolite %||% 6L)
  root <- (cfg$project %||% list())$output_dir
  t3 <- tryCatch(utils::read.csv(file.path(root, "Tables",
    "Table 3. Selected features by space.csv"), stringsAsFactors = FALSE), error = function(e) NULL)
  feats_all <- if (!is.null(t3)) {
    as.character(t3$feature[t3$space == "CM" & t3$method == "consensus"])
  } else character(0)
  feats_all <- intersect(feats_all, names(dat))
  if (length(feats_all) < 3L) { log("Nomogram: 共识特征不足", "warn"); return(NULL) }

  y0 <- as.integer(as.character(dat$Disease) == "NAFLD")
  # 全 CM 先 P5–P95 标准化，再按 |β| 选特征（禁止用原始方差截断——尿代谢量纲会挤掉全部临床）
  .scale_p5p95 <- function(x) {
    x <- suppressWarnings(as.numeric(x))
    qq <- stats::quantile(x, c(0.05, 0.95), na.rm = TRUE, names = FALSE)
    if (!is.finite(qq[2] - qq[1]) || qq[2] <= qq[1]) return(list(z = rep(NA_real_, length(x)), lo = NA, hi = NA))
    list(z = pmin(1, pmax(0, (x - qq[1]) / (qq[2] - qq[1]))), lo = qq[1], hi = qq[2])
  }
  scaled_all <- list(); bounds_all <- list()
  for (f in feats_all) {
    sc <- .scale_p5p95(dat[[f]])
    if (!is.finite(sc$lo)) next
    scaled_all[[f]] <- sc$z
    bounds_all[[f]] <- c(P5 = sc$lo, P95 = sc$hi)
  }
  feats_ok <- names(scaled_all)
  mat <- as.data.frame(scaled_all, stringsAsFactors = FALSE)
  keep <- stats::complete.cases(mat) & !is.na(y0)
  mat <- mat[keep, , drop = FALSE]
  y <- y0[keep]
  fit0 <- tryCatch(stats::glm(y ~ ., data = cbind(data.frame(y = y), mat), family = binomial()),
                   error = function(e) NULL)
  if (is.null(fit0)) { log("Nomogram: 全特征 glm 失败", "warn"); return(NULL) }
  b0 <- stats::coef(fit0)
  b0 <- b0[setdiff(names(b0), "(Intercept)")]
  b0 <- b0[is.finite(b0)]
  clin <- names(b0)[!grepl("^U_", names(b0))]
  met  <- names(b0)[grepl("^U_", names(b0))]
  pick_clin <- clin[order(-abs(b0[clin]))][seq_len(min(max_clin, length(clin)))]
  pick_met  <- met[order(-abs(b0[met]))][seq_len(min(max_met, length(met)))]
  feats <- c(pick_clin, pick_met)
  if (length(feats) > maxf) {
    feats <- names(sort(abs(b0[feats]), decreasing = TRUE))[seq_len(maxf)]
  }
  if (length(feats) < 3L) { log("Nomogram: 筛选后特征不足", "warn"); return(NULL) }
  log(sprintf("Nomogram 入选 %d 特征（临床 %d + 代谢 %d）：%s",
              length(feats), sum(!grepl("^U_", feats)), sum(grepl("^U_", feats)),
              paste(feats, collapse = ", ")))

  # 显示名：临床保留；尿代谢物加 Urine 前缀（避免 Glucose vs U_Glucose → Glucose.1）
  .disp_one <- function(f) {
    if (grepl("^U_", f)) paste0("Urine ", gsub("_", "-", sub("^U_", "", f)))
    else gsub("_", " ", f)
  }
  disp <- stats::setNames(vapply(feats, .disp_one, character(1)), feats)
  # 若仍撞名（极少）再 make.unique
  if (anyDuplicated(unname(disp))) disp[] <- make.unique(unname(disp), sep = " ")

  # 列线图用原始单位（截断到 P5–P95），不再画 0–1；负相关轴自然「右低左高」由 rms 按系数取向
  keep_idx <- which(keep)
  raw <- as.data.frame(lapply(feats, function(f) {
    x <- suppressWarnings(as.numeric(dat[[f]]))[keep_idx]
    lo <- bounds_all[[f]][["P5"]]; hi <- bounds_all[[f]][["P95"]]
    pmin(hi, pmax(lo, x))
  }), stringsAsFactors = FALSE)
  names(raw) <- unname(disp[feats])
  bounds <- do.call(rbind, bounds_all[feats])
  rownames(bounds) <- feats

  df <- cbind(data.frame(y = y), raw)
  dd <- rms::datadist(df)
  assign("dd", dd, envir = .GlobalEnv)
  on.exit(try(rm(list = c("dd", "dd2"), envir = .GlobalEnv), silent = TRUE), add = TRUE)
  options(datadist = "dd")
  fit <- rms::lrm(y ~ ., data = df, x = TRUE, y = TRUE)
  cf_raw <- stats::coef(fit)[-1]
  # 排序用标准化 |β|（跨量纲可比）；列线图拟合仍用原始单位
  b_sc <- abs(b0[feats])
  names(b_sc) <- unname(disp[feats])
  ord <- order(-b_sc[names(cf_raw)])
  cf <- cf_raw[ord]
  feats <- feats[match(names(cf), unname(disp[feats]))]
  # 整数分：用标准化系数权重（与选模一致）
  w <- abs(b0[feats]); names(w) <- names(cf)
  pts <- round(100 * w / sum(w))
  pts[pts == 0 & w > 0] <- 1L
  direction <- ifelse(
    cf >= 0,
    "Higher value = higher risk",
    "Lower value = higher risk"
  )
  # 预测概率 + 人数等分三分位（避免概率顶满时 High>1.00）
  pr <- as.numeric(stats::plogis(stats::predict(fit)))
  tier_i <- as.integer(ceiling(rank(pr, ties.method = "first") / length(pr) * 3))
  tier_i <- pmin(3L, pmax(1L, tier_i))
  tier <- factor(c("Low", "Moderate", "High")[tier_i], levels = c("Low", "Moderate", "High"))
  tier_rng <- vapply(levels(tier), function(lv) {
    z <- pr[tier == lv]
    sprintf("%.2f\u2013%.2f", min(z), max(z))
  }, character(1))
  q_pr <- c(max(pr[tier == "Low"]), min(pr[tier == "High"]))
  names(q_pr) <- c("low_max", "high_min")
  tab_tier <- as.data.frame.matrix(table(tier, df$y))
  names(tab_tier) <- c("n_Normal", "n_NAFLD")
  tab_tier$NAFLD_rate <- round(tab_tier$n_NAFLD / pmax(1, tab_tier$n_NAFLD + tab_tier$n_Normal), 3)
  tab_tier$prob_range <- unname(tier_rng[rownames(tab_tier)])

  sci <- tryCatch({
    root2 <- cfg$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
    if (file.exists(file.path(root2, "R/competing_supp_xlsx.R")))
      source(file.path(root2, "R/competing_supp_xlsx.R"), local = FALSE)
    TRUE
  }, error = function(e) FALSE)
  feat_of_disp <- feats
  names(feat_of_disp) <- unname(disp[feats])
  span <- bounds[feats, "P95"] - bounds[feats, "P5"]
  names(span) <- names(cf)
  coef_tab <- data.frame(
    feature = names(pts),
    original = unname(feat_of_disp[names(pts)]),
    `P5 (raw unit)` = round(bounds[feats, "P5"], 3),
    `P95 (raw unit)` = round(bounds[feats, "P95"], 3),
    direction = unname(direction),
    `Maximum points` = as.integer(pts),
    beta_per_unit = round(cf, 4),
    `OR per P5-P95 span` = round(exp(cf * span), 3),
    stringsAsFactors = FALSE, check.names = FALSE
  )
  tier_note <- paste(
    "Tier NAFLD rates (equal-count predicted-probability tertiles):",
    paste(sprintf("%s %.1f%% [%s]", rownames(tab_tier), tab_tier$NAFLD_rate * 100,
                  tab_tier$prob_range), collapse = "; ")
  )
  if (sci && exists("sci_xlsx_single_header_booktabs", mode = "function")) {
    tryCatch(
      sci_xlsx_single_header_booktabs(
        file.path(D$tables, "Table S17. Simplified score and risk tiers.xlsx"),
        "Table S17. Nomogram-based simplified score (integer points) and risk tiers",
        coef_tab,
        footnotes = c(
          "Features: top clinical + top urinary metabolites from CM consensus by |logistic beta| after P5–P95 scaling (selection only; nomogram axes use raw units).",
          "Nomogram fitted on winsorized raw values (P5–P95); axis length reflects contribution.",
          "Absolute standardized coefficients normalized to ~100 total points.",
          "Risk tiers = equal-count tertiles of predicted probability (ranges in table).",
          tier_note,
          "High baseline NAFLD prevalence in this hospital cohort elevates absolute rates in all tiers."
        )
      ),
      error = function(e) NULL
    )
  }
  utils::write.csv(data.frame(tier = rownames(tab_tier), tab_tier, row.names = NULL),
                   file.path(D$work, "risk_tiers.csv"), row.names = FALSE)

  # ── 绘图：A1 分值条（全特征可读）+ A2 仅 top 贡献列线图；B 校准；C 分层 ──
  out_pdf <- file.path(D$figures, "Figure 9. Nomogram and simplified score.pdf")
  grDevices::pdf(out_pdf, width = 12, height = 11.5, useDingbats = FALSE)
  on.exit({
    try(grDevices::dev.off(), silent = TRUE)
  }, add = FALSE)
  cal <- tryCatch(
    rms::calibrate(fit, method = "boot", B = 200),
    error = function(e) tryCatch(rms::calibrate(fit, method = "crossvalidation", B = 10),
                                 error = function(e2) NULL)
  )
  # 全特征模型用于校准与分层；列线图只画贡献最大的若干项，避免轴被压成细线
  df2 <- df[, c("y", names(cf)), drop = FALSE]
  dd2 <- rms::datadist(df2)
  assign("dd2", dd2, envir = .GlobalEnv)
  options(datadist = "dd2")
  fit2 <- rms::lrm(y ~ ., data = df2, x = TRUE, y = TRUE)
  n_nomo <- min(5L, length(pts))
  top_nm <- names(sort(pts, decreasing = TRUE))[seq_len(n_nomo)]
  df3 <- df2[, c("y", top_nm), drop = FALSE]
  dd3 <- rms::datadist(df3)
  assign("dd3", dd3, envir = .GlobalEnv)
  on.exit(try(rm(list = c("dd", "dd2", "dd3"), envir = .GlobalEnv), silent = TRUE), add = TRUE)
  options(datadist = "dd3")
  fit3 <- rms::lrm(y ~ ., data = df3, x = TRUE, y = TRUE)
  # 刻度宜疏：高患病率队列若密排 0.5–0.99 会叠字
  fun_at <- if (stats::median(pr, na.rm = TRUE) > 0.85) {
    c(0.5, 0.8, 0.9, 0.99)
  } else {
    c(0.2, 0.4, 0.6, 0.8, 0.9)
  }
  nom <- rms::nomogram(
    fit3,
    fun = plogis,
    fun.at = fun_at,
    funlabel = "Predicted NAFLD probability",
    lp = FALSE,
    maxscale = 100
  )
  tb <- tab_tier$NAFLD_rate * 100
  names(tb) <- rownames(tab_tier)

  # A1: 整数分横条（全 10 特征，临床/代谢分色）
  graphics::par(fig = c(0.04, 0.48, 0.42, 0.96), new = FALSE, mar = c(4.2, 10.5, 3.0, 1.0))
  pts_ord <- sort(pts, decreasing = FALSE)
  is_urine <- grepl("^Urine ", names(pts_ord))
  bar_cols <- ifelse(is_urine, "#5B8DB8", "#C85A54")
  bp1 <- graphics::barplot(
    pts_ord, horiz = TRUE, col = bar_cols, border = NA,
    xlim = c(0, max(pts_ord) * 1.18),
    xlab = "Maximum points (~100 total)",
    main = "A1  Simplified score weights",
    cex.main = 1.05, font.main = 2, las = 1, cex.names = 0.85
  )
  graphics::text(pts_ord + max(pts_ord) * 0.03, bp1, as.integer(pts_ord),
                 cex = 0.8, adj = 0, xpd = TRUE)
  graphics::legend("bottomright", c("Clinical", "Urine metabolite"),
                   fill = c("#C85A54", "#5B8DB8"), border = NA, bty = "n", cex = 0.85)

  # A2: 仅 top 贡献特征的可读列线图
  graphics::par(fig = c(0.50, 0.98, 0.42, 0.96), new = TRUE, mar = c(2.0, 5.5, 3.0, 1.0))
  graphics::plot(nom, cex.axis = 0.78, cex.var = 0.95, lmgp = 0.25,
                 col.grid = grDevices::gray(c(0.88, 0.95)))
  graphics::mtext(sprintf("A2  Nomogram (top-%d by points; raw units)", n_nomo),
                  side = 3, line = 0.5, cex = 1.05, font = 2, adj = 0)

  graphics::par(fig = c(0.06, 0.50, 0.05, 0.38), new = TRUE, mar = c(4.2, 4.2, 2.2, 0.6))
  if (!is.null(cal)) {
    pred <- as.numeric(cal[, "predy"])
    obs  <- as.numeric(cal[, "calibrated.corrected"])
    appr <- as.numeric(cal[, "calibrated.orig"])
    o <- order(pred)
    graphics::plot(NA, xlim = c(0, 1), ylim = c(0, 1), xaxs = "i", yaxs = "i",
                   xlab = "Predicted probability", ylab = "Observed probability",
                   main = "B  Calibration (bootstrap B=200)", cex.main = 1.05, font.main = 2)
    graphics::abline(0, 1, lty = 2, col = "grey50")
    graphics::lines(pred[o], appr[o], col = "#b2182b", lwd = 2.2)
    graphics::lines(pred[o], obs[o], col = "#2166ac", lwd = 2.2)
    graphics::legend("bottomright", c("Apparent", "Bias-corrected", "Ideal"),
                     col = c("#b2182b", "#2166ac", "grey50"), lwd = c(2.2, 2.2, 1.5),
                     lty = c(1, 1, 2), bty = "n", cex = 0.85)
  } else {
    graphics::plot.new()
    graphics::legend("center", "Calibration unavailable", bty = "n")
  }

  graphics::par(fig = c(0.56, 0.96, 0.05, 0.38), new = TRUE, mar = c(5.4, 4.2, 2.2, 0.8))
  cols <- c(Low = "#4D4D4D", Moderate = "#FDAE61", High = "#D73027")[rownames(tab_tier)]
  bp <- graphics::barplot(tb, col = cols, border = NA, ylim = c(0, 118),
                          ylab = "NAFLD proportion (%)",
                          main = "C  NAFLD rate by equal-count risk tertile",
                          cex.main = 1.05, font.main = 2, cex.names = 1.0, xaxt = "n")
  graphics::axis(1, at = bp, labels = rownames(tab_tier), tick = FALSE, cex.axis = 1.0)
  graphics::text(bp, tb + 5,
                 sprintf("%.1f%%\n(n=%d)\n[%s]", tb, tab_tier$n_Normal + tab_tier$n_NAFLD,
                         tab_tier$prob_range),
                 xpd = TRUE, cex = 0.78, font = 2)
  graphics::mtext("Equal-count tertiles of predicted probability (range in brackets)",
                  side = 1, line = 3.8, cex = 0.72, col = "grey30")
  grDevices::dev.off()
  on.exit(try(rm(list = c("dd", "dd2", "dd3"), envir = .GlobalEnv), silent = TRUE), add = FALSE)

  sum_fig <- file.path(D$study, "summary_result", "figure")
  if (dir.exists(sum_fig)) {
    file.copy(out_pdf, file.path(sum_fig, basename(out_pdf)), overwrite = TRUE)
    if (dir.exists(file.path(sum_fig, "pdf")))
      file.copy(out_pdf, file.path(sum_fig, "pdf", basename(out_pdf)), overwrite = TRUE)
  }

  log(sprintf("Figure 9 已重画：%d 特征（原始单位；列线图 top-%d）；分层率 %s",
              length(feats), n_nomo,
              paste(sprintf("%s=%.1f%%", rownames(tab_tier), tab_tier$NAFLD_rate * 100), collapse = ", ")))
  list(coef = coef_tab, tiers = tab_tier, cutoffs = q_pr, model = fit2,
       feats_disp = disp, df = df2, bounds = bounds, pts = pts, beta = cf,
       direction_negative = cf < 0, selected_features = feats,
       tier_prob_range = tier_rng, nomogram_features = top_nm)
}

# ── Shiny 在线计算器雏形（模块七：导出独立 app 目录 + staging RData）──
.nafld_od_shiny <- function(cfg, nom_res, D, log) {
  if (is.null(nom_res)) { log("Shiny: 无 Nomogram 结果，跳过", "warn"); return(invisible(FALSE)) }
  if (!requireNamespace("shiny", quietly = TRUE)) { log("无 shiny 包，跳过", "warn"); return(invisible(FALSE)) }
  app_dir <- file.path(D$study, "ShinyApp")
  dir.create(app_dir, recursive = TRUE, showWarnings = FALSE)
  # staging：显示名系数 + 分层切点（app 只依赖这两样）
  shiny_staging <- list(
    coefs = nom_res$coef,
    cutoffs = nom_res$cutoffs,
    tiers = nom_res$tiers,
    feat_disps = nom_res$feats_disp,
    intercept = unname(stats::coef(nom_res$model)[1]),
    tier_prob_range = nom_res$tier_prob_range
  )
  saveRDS(shiny_staging, file.path(app_dir, "shiny_staging.rds"))
  app <- paste0(
    'library(shiny)\n',
    'st <- readRDS("shiny_staging.rds")\n',
    'coefs <- st$coefs\n',
    'coefs$input_id <- make.unique(make.names(coefs$feature))\n',
    'beta_col <- if ("beta_per_unit" %in% names(coefs)) "beta_per_unit" else "beta"\n',
    'rev_flag <- grepl("Lower value", coefs$direction, ignore.case = TRUE)\n',
    'ui <- fluidPage(\n',
    '  titlePanel("NAFLD simplified-score calculator"),\n',
    '  sidebarLayout(\n',
    '    sidebarPanel(\n',
    '      helpText("Enter raw laboratory / metabolite values (winsorized to cohort P5-P95)."),\n',
    '      lapply(seq_len(nrow(coefs)), function(i) numericInput(\n',
    '        coefs$input_id[i], coefs$feature[i],\n',
    '        value = round(mean(c(coefs[["P5 (raw unit)"]][i], coefs[["P95 (raw unit)"]][i])), 3))),\n',
    '      actionButton("go", "Calculate", class = "btn-primary")\n',
    '    ),\n',
    '    mainPanel(\n',
    '      h3("Result"), verbatimTextOutput("res"),\n',
    '      h4("Interpretation"), textOutput("interp")\n',
    '    )\n',
    '  )\n',
    ')\n',
    'server <- function(input, output, session) {\n',
    '  vals <- eventReactive(input$go, {\n',
    '    x <- sapply(coefs$input_id, function(f) input[[f]])\n',
    '    if (any(is.na(x))) return(NULL)\n',
    '    lo <- coefs[["P5 (raw unit)"]]; hi <- coefs[["P95 (raw unit)"]]\n',
    '    xw <- pmin(hi, pmax(lo, x))\n',
    '    z <- pmin(1, pmax(0, (xw - lo) / (hi - lo)))\n',
    '    oriented <- ifelse(rev_flag, 1 - z, z)\n',
    '    total <- sum(oriented * coefs[["Maximum points"]], na.rm = TRUE)\n',
    '    probability <- plogis(st$intercept + sum(xw * coefs[[beta_col]]))\n',
    '    # equal-count style tier via stored ranges if present\n',
    '    tr <- st$tiers\n',
    '    if (!is.null(st$tier_prob_range)) {\n',
    '      # assign by nearest tertile mid\n',
    '      mids <- sapply(st$tier_prob_range, function(s) {\n',
    '        ab <- as.numeric(strsplit(gsub("\\\\u2013|–", "-", s), "-")[[1]])\n',
    '        mean(ab)\n',
    '      })\n',
    '      tier <- names(mids)[which.min(abs(mids - probability))]\n',
    '    } else {\n',
    '      cut0 <- st$cutoffs\n',
    '      tier <- as.character(cut(probability, breaks = c(-Inf, cut0[1], cut0[2], Inf),\n',
    '                              labels = c("Low", "Moderate", "High")))\n',
    '    }\n',
    '    list(total = total, tier = tier, probability = probability)\n',
    '  })\n',
    '  output$res <- renderPrint({\n',
    '    v <- vals(); if (is.null(v)) return("Enter all values, then Calculate.")\n',
    '    cat(sprintf("Total score: %.1f / 100\\nPredicted NAFLD probability: %.1f%%\\nRisk tier: %s",\n',
    '                v$total, 100*v$probability, v$tier))\n',
    '  })\n',
    '  output$interp <- renderText({\n',
    '    v <- vals(); if (is.null(v)) return("")\n',
    '    tr <- st$tiers[as.character(v$tier), "NAFLD_rate"]\n',
    '    sprintf("In this cohort, %s-tier patients had %.1f%% NAFLD prevalence.", v$tier, tr*100)\n',
    '  })\n',
    '}\n',
    'shinyApp(ui, server)\n')
  writeLines(app, file.path(app_dir, "app.R"))
  log(sprintf("Shiny 雏形已导出: %s（app.R + shiny_staging.rds）", app_dir))
  invisible(TRUE)
}

# ── 证型特色分析（Table S18：NAFLD 亚组证型×代谢/临床）──
.nafld_od_syndrome <- function(cfg, dat, de, D, log) {
  sc <- intersect(c("Syndrome_Main", "Syndrome_Typicality"), names(dat))
  if (!"Syndrome_Main" %in% sc) { log("无 Syndrome_Main，证型表跳过", "warn"); return(NULL) }
  d <- dat[dat$Disease == "NAFLD", , drop = FALSE]   # 证型仅在 NAFLD 组内（Normal 全为正常人）
  syn <- as.character(d$Syndrome_Main)
  if (length(unique(syn)) < 2) { log("证型无变异，跳过", "warn"); return(NULL) }
  # 临床比较（连续，中位数[IQR]）
  clin <- intersect(c("Age","BMI","ALT","AST","GGT","Glucose","Triglycerides",
                      "Total_Cholesterol","LDL","Creatinine"), names(d))
  fmt_iqr <- function(x) {
    x <- suppressWarnings(as.numeric(x)); x <- x[is.finite(x)]
    sprintf("%.2f (%.2f–%.2f)", stats::median(x), stats::quantile(x, .25), stats::quantile(x, .75))
  }
  rows <- list()
  for (v in clin) {
    cmp <- stats::kruskal.test(suppressWarnings(as.numeric(d[[v]])) ~ syn)
    r <- data.frame(Variable = v,
                    t(stats::setNames(tapply(d[[v]], syn, fmt_iqr), NULL)),
                    P = ifelse(cmp$p.value < 0.001, "<0.001", sprintf("%.3f", cmp$p.value)),
                    stringsAsFactors = FALSE, check.names = FALSE)
    names(r) <- c("Variable", sort(unique(syn)), "P")
    rows[[v]] <- r
  }
  # 差异代谢物比较（top 8 by padj）
  top <- utils::head(de[de$sig, ][order(de$padj), ], 8)
  for (v in top$feature) {
    if (!v %in% names(d)) next
    cmp <- stats::kruskal.test(suppressWarnings(as.numeric(d[[v]])) ~ syn)
    r <- data.frame(Variable = paste0("U: ", sub("^U_", "", v)),
                    t(stats::setNames(tapply(d[[v]], syn, fmt_iqr), NULL)),
                    P = ifelse(cmp$p.value < 0.001, "<0.001", sprintf("%.3f", cmp$p.value)),
                    stringsAsFactors = FALSE, check.names = FALSE)
    names(r) <- c("Variable", sort(unique(syn)), "P")
    rows[[v]] <- r
  }
  tab <- do.call(rbind, rows)
  rownames(tab) <- NULL
  # 证型构成（NAFLD 内）
  comp <- data.frame(table(syn))
  names(comp) <- c("Syndrome", "n_NAFLD")
  comp$pct <- round(comp$n_NAFLD / sum(comp$n_NAFLD) * 100, 1)
  blank_cols <- max(0L, ncol(tab) - 2L)
  composition_header <- data.frame(
    Variable = "── Syndrome composition (n, %) ──",
    matrix("", nrow = 1L, ncol = blank_cols),
    P = "", stringsAsFactors = FALSE, check.names = FALSE)
  composition_rows <- data.frame(
    Variable = paste0("  ", comp$Syndrome, " (", comp$n_NAFLD, ", ", comp$pct, "%)"),
    matrix("", nrow = nrow(comp), ncol = blank_cols),
    P = "", stringsAsFactors = FALSE, check.names = FALSE)
  names(composition_header) <- names(tab)
  names(composition_rows) <- names(tab)
  out <- rbind(composition_header, composition_rows, tab)
  names(out) <- names(tab)
  root <- cfg$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
  if (file.exists(file.path(root, "R/competing_supp_xlsx.R")))
    source(file.path(root, "R/competing_supp_xlsx.R"), local = FALSE)
  if (exists("sci_xlsx_single_header_booktabs", mode = "function")) {
    tryCatch(sci_xlsx_single_header_booktabs(
      file.path(D$tables, "Table S18. TCM syndrome stratification (NAFLD subgroup).xlsx"),
      "Table S18. TCM syndrome stratification: clinical and urinary metabolites (NAFLD subgroup)",
      out,
      footnotes = c(
        "Syndrome assessed in NAFLD patients only (all Normal controls were syndrome-free).",
        "Continuous variables: median (IQR); P from Kruskal-Wallis across syndromes.",
        "U: = urinary metabolite (top FDR-ranked). 特色分析：不作预测特征（结局泄漏，见 analysis_exclusion）。")), silent = TRUE)
  } else {
    utils::write.csv(out, file.path(D$tables, "Table S18. TCM syndrome stratification (NAFLD subgroup).csv"),
                     row.names = FALSE)
  }
  log(sprintf("证型特色表 S18 完成（%d 证型 × %d 变量）", length(unique(syn)), nrow(tab)))
  list(table = out, composition = comp)
}

# ── 代表性病例（Table S19：3 例 低/中/高 完整评分演示）──
.nafld_od_cases <- function(cfg, nom_res, D, log) {
  if (is.null(nom_res) || is.null(nom_res$df) || is.null(nom_res$raw_df)) {
    log("无评分模型，病例表跳过", "warn"); return(NULL)
  }
  df <- nom_res$df; raw_df <- nom_res$raw_df; pts <- nom_res$pts
  X <- as.matrix(df[, names(pts), drop = FALSE])
  oriented <- X
  oriented[, nom_res$direction_negative] <-
    1 - oriented[, nom_res$direction_negative, drop = FALSE]
  total <- as.vector(oriented %*% pts)
  cut0 <- nom_res$cutoffs
  tier <- cut(total, breaks = c(-Inf, cut0[1], cut0[2], Inf), labels = c("Low","Moderate","High"))
  rows <- list()
  for (tl in c("Low","Moderate","High")) {
    idx <- which(tier == tl)
    if (!length(idx)) next
    # 取该层总分中位者
    i <- idx[which.min(abs(total[idx] - stats::median(total[idx])))]
    vals <- as.numeric(raw_df[i, names(pts), drop = TRUE])
    names(vals) <- names(pts)
    sc <- round(total[i], 1)
    prob <- tryCatch({
      predict(nom_res$model, newdata = df[i, , drop = FALSE], type = "fitted")
    }, error = function(e) NA_real_)
    rows[[tl]] <- data.frame(
      Case = tl, `Total score (0-100)` = sc,
      `Predicted risk` = if (is.finite(prob)) sprintf("%.1f%%", prob * 100) else "—",
      `Observed` = ifelse(df$y[i] == 1, "NAFLD", "Normal"),
      t(stats::setNames(round(vals, 2), NULL)), stringsAsFactors = FALSE, check.names = FALSE)
  }
  if (!length(rows)) return(NULL)
  tab <- do.call(rbind, rows)
  names(tab) <- c("Case","Total score (0-100)","Predicted risk","Observed", names(pts))
  root <- cfg$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
  if (file.exists(file.path(root, "R/competing_supp_xlsx.R")))
    source(file.path(root, "R/competing_supp_xlsx.R"), local = FALSE)
  if (exists("sci_xlsx_single_header_booktabs", mode = "function")) {
    tryCatch(sci_xlsx_single_header_booktabs(
      file.path(D$tables, "Table S19. Representative cases by risk tier.xlsx"),
      "Table S19. Representative cases: low/moderate/high-risk patients with score walkthrough",
      tab,
      footnotes = c(
        "Each case = patient at the median total score of its tier.",
        "Predicted risk from the nomogram logistic model; management per scheme module 7:",
        "Low = lifestyle counseling + annual review; Moderate = hepatology referral + metabolic workup;",
        "High = intensified intervention + fibrosis assessment (FibroScan/FIB-4).")), silent = TRUE)
  }
  log("代表病例表 S19 完成（低/中/高 各 1 例）")
  tab
}

# ── Table S15/S16 ────────────────────────────────────────────────────────
.nafld_od_tables <- function(cfg, dat, de, D, log) {
  root <- cfg$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
  if (file.exists(file.path(root, "R/competing_supp_xlsx.R")))
    source(file.path(root, "R/competing_supp_xlsx.R"), local = FALSE)
  wr <- function(path, title, df, fn) {
    if (exists("sci_xlsx_single_header_booktabs", mode = "function")) {
      tryCatch(sci_xlsx_single_header_booktabs(path, title, df, footnotes = fn), error = function(e) NULL)
    } else utils::write.csv(df, sub("\\.xlsx$", ".csv", path), row.names = FALSE)
  }
  # S15 全差异表（发表小数位：描述 2 位、效应 3 位、P 3 位）
  de2 <- de[, c("feature","mean_NAFLD","mean_Normal","log2FC","p","padj","sig")]
  names(de2) <- c("Metabolite","Mean NAFLD","Mean Normal","log2FC (median ratio)","P (Wilcoxon)",
                  "FDR (BH)","FDR<0.05")
  de2$Metabolite <- sub("^U_", "", de2$Metabolite)
  de2$`Mean NAFLD` <- round(de2$`Mean NAFLD`, 2)
  de2$`Mean Normal` <- round(de2$`Mean Normal`, 2)
  de2$`log2FC (median ratio)` <- round(de2$`log2FC (median ratio)`, 3)
  fmt_p3 <- function(v) ifelse(is.na(v), NA, ifelse(v < 0.001, "<0.001", sprintf("%.3f", v)))
  de2$`P (Wilcoxon)` <- fmt_p3(de2$`P (Wilcoxon)`)
  de2$`FDR (BH)` <- fmt_p3(de2$`FDR (BH)`)
  wr(file.path(D$tables, "Table S15. Differential urinary metabolites.xlsx"),
     "Table S15. Differential urinary metabolites (NAFLD vs Normal, Wilcoxon BH-FDR)", de2,
     c("log2FC = log2(median ratio); full 90-metabolite urinary pool.",
       "Consensus ML features (Table 3, space M) are a subset of this pool."))
  # S16 相关矩阵
  clin <- intersect(c("Age","BMI","ALT","AST","GGT","Glucose","Triglycerides",
                      "Total_Cholesterol","LDL","Creatinine"), names(dat))
  sigd <- de[de$sig, ][order(de$padj), ]
  # 防御：剔除合并后全 NA / 缺列（个别 U_ 列在分析表无观测）
  usable <- vapply(sigd$feature, function(f) {
    if (!f %in% names(dat)) return(FALSE)
    x <- suppressWarnings(as.numeric(dat[[f]]))
    if (is.null(x)) return(FALSE)
    sum(is.finite(x)) >= 10L
  }, logical(1))
  sigd <- sigd[usable, , drop = FALSE]
  if (nrow(sigd) && length(clin) >= 3) {
    cv <- vapply(sigd$feature, function(f) suppressWarnings(as.numeric(dat[[f]])), numeric(nrow(dat)))
    ccv <- vapply(clin, function(f) suppressWarnings(as.numeric(dat[[f]])), numeric(nrow(dat)))
    R <- matrix(NA_real_, nrow = nrow(sigd), ncol = length(clin),
                dimnames = list(sub("^U_", "", sigd$feature), clin))
    for (i in seq_len(nrow(sigd))) for (j in seq_along(clin)) {
      R[i, j] <- tryCatch(stats::cor(cv[, i], ccv[, j], method = "spearman",
                                     use = "complete.obs"), error = function(e) NA_real_)
    }
    long <- data.frame(Metabolite = rownames(R)[row(R)], Clinical = colnames(R)[col(R)],
                       rho = round(as.vector(R), 3), row.names = NULL)
    long <- long[order(-abs(long$rho)), ]
    wr(file.path(D$tables, "Table S16. Metabolite-clinical Spearman correlations.xlsx"),
       "Table S16. Spearman correlations: differential metabolites x clinical measures", long,
       c("Spearman rho, complete pairs; metabolites = FDR<0.05 set ranked by padj.",
         "Abs(rho) top pairs highlighted in Figure 8D."))
    utils::write.csv(long, file.path(D$work, "metab_clin_cor.csv"), row.names = FALSE)
  }
  log("Table S15/S16 已生成")
}

# 分层划分（与 train_validation 块同思路：组内按比例抽 train 索引）
.nafld_od_split <- function(y, ratio) {
  idx <- integer(0)
  for (g in unique(y[is.finite(y)])) {
    gi <- which(y == g)
    n_tr <- round(length(gi) * ratio)
    idx <- c(idx, sample(gi, n_tr))
  }
  sort(idx)
}

# ── Figure S3: SHAP beeswarm 大图（验证集 LightGBM，对 Figure 5 的补充）──
.nafld_od_figS3_shap <- function(cfg, D, log, dat) {
  if (!requireNamespace("lightgbm", quietly = TRUE) ||
      !requireNamespace("shapviz", quietly = TRUE)) { log("无 lightgbm/shapviz，S3 跳过", "warn"); return(invisible(FALSE)) }
  root <- (cfg$project %||% list())$output_dir
  eng <- cfg$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
  polish <- file.path(eng, "Blocks/73_ml_nafld_cm/05ml_nafld_cm_pub_polish.R")
  if (file.exists(polish)) source(polish, local = FALSE)
  common <- file.path(eng, "Blocks/73_ml_nafld_cm/00ml_nafld_cm_common.R")
  if (file.exists(common)) source(common, local = FALSE)
  # CM 共识特征：读 Table 3（主文定稿口径）
  t3 <- tryCatch(utils::read.csv(file.path(root, "Tables",
    "Table 3. Selected features by space.csv"), stringsAsFactors = FALSE), error = function(e) NULL)
  feats <- if (!is.null(t3)) as.character(t3$feature[t3$space == "CM" & t3$method == "consensus"]) else character(0)
  feats <- intersect(feats, names(dat))
  if (length(feats) < 3L) { log("S3: 无 CM 特征", "warn"); return(invisible(FALSE)) }
  # 复现 train/validation split（与 train_validation 块同 seed/比例/分层）
  tv <- cfg$train_validation %||% list()
  seed <- as.integer(tv$base_seed %||% tv$seed %||% 1234L)
  ratio <- as.numeric(tv$train_ratio %||% 0.7)
  y0 <- as.integer(as.character(dat$Disease) == (cfg$project$analysis_group %||% "NAFLD"))
  set.seed(seed)
  idx_tr <- .nafld_od_split(y0, ratio)
  oc <- cfg$data$outcome_column %||% "Disease"; pos <- cfg$project$analysis_group %||% "NAFLD"
  feats <- feats[feats %in% names(dat)]           # 先剔除缺列，防 model_matrix 失败
  mm_tr <- .nafld_cm_model_matrix(dat[idx_tr, , drop = FALSE], feats, oc, pos)
  mm_va <- .nafld_cm_model_matrix(dat[-idx_tr, , drop = FALSE], feats, oc, pos)
  feats2 <- intersect(intersect(feats, colnames(mm_tr$x)), colnames(mm_va$x))
  if (mm_tr$n < 20L || mm_va$n < 10L || !length(feats2)) { log("S3: split 过小", "warn"); return(invisible(FALSE)) }
  xtr <- mm_tr$x[, feats2, drop = FALSE]; xva <- mm_va$x[, feats2, drop = FALSE]
  dtr <- lightgbm::lgb.Dataset(data = as.matrix(xtr), label = mm_tr$y)
  fit <- lightgbm::lgb.train(
    params = list(objective = "binary", metric = "auc", num_leaves = 15L,
                  learning_rate = 0.05, verbosity = -1L, num_threads = 1L),
    data = dtr, nrounds = 120L, verbose = -1L)
  ok <- tryCatch({
    sv <- shapviz::shapviz(fit, X_pred = as.matrix(xva), X = as.data.frame(xva))
    grDevices::pdf(file.path(D$supp_fig, "Figure S3. SHAP beeswarm.pdf"), width = 10, height = 6.5)
    print(shapviz::sv_importance(sv, kind = "beeswarm", max_display = min(21L, ncol(xva))) +
            ggplot2::labs(title = "SHAP beeswarm (best CM model, validation set)"))
    grDevices::dev.off()
    TRUE
  }, error = function(e) { log(paste("S3 shap:", conditionMessage(e)), "warn"); FALSE })
  if (ok) log("Figure S3 (SHAP beeswarm) 已生成")
  invisible(ok)
}

# ── 主入口 ────────────────────────────────────────────────────────────────
block_ml_nafld_omics_display <- function(ctx, ...) {
  cfg <- ctx$config
  od <- cfg$omics_display %||% list()
  if (isFALSE(od$enable)) { cli::cli_alert_info("omics_display enable=FALSE，跳过"); return(ctx) }
  root <- cfg$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
  # 单块重跑（--from/--blocks）时须自行加载 common（含肌酐校正 helper），
  # 否则 .nafld_od_data 的 creatinine_correct 因函数缺失被 exists() 跳过 → 静默用未校正值
  for (cf in c(file.path(root, "Blocks/73_ml_nafld_cm/00ml_nafld_cm_common.R"),
               file.path(getwd(), "Blocks/73_ml_nafld_cm/00ml_nafld_cm_common.R"))) {
    if (file.exists(cf)) { source(cf, local = FALSE); break }
  }
  if (file.exists(file.path(root, "R/utils.R"))) source(file.path(root, "R/utils.R"), local = FALSE)
  D <- .nafld_od_dirs(cfg)
  for (p in c(D$work, D$tables, D$figures, D$supp_tab, D$supp_fig))
    if (!dir.exists(p)) dir.create(p, recursive = TRUE, showWarnings = FALSE)
  logs <- character(0)
  log <- function(m, l = "info") { logs <<- c(logs, m); if (l == "warn") cli::cli_alert_warning(m) else cli::cli_alert_info(m) }

  dat <- .nafld_od_data(cfg)
  if (is.null(dat)) { log("原始数据缺失，omics_display 跳过", "warn"); return(ctx) }
  de <- .nafld_od_de_metab(dat)
  n_sig <- sum(de$sig)
  log(sprintf("差异代谢物: %d/%d (FDR<0.05)", n_sig, nrow(de)))

  # 图表
  tryCatch(.nafld_od_fig8(cfg, dat, de, D, log), error = function(e) log(paste("Fig8 err:", conditionMessage(e)), "warn"))
  pw <- tryCatch(.nafld_od_figS2(cfg, de, D, log), error = function(e) log(paste("FigS2 err:", conditionMessage(e)), "warn"))
  nom <- tryCatch(.nafld_od_fig9(cfg, dat, D, log),
                  error = function(e) { log(paste("Fig9 err:", conditionMessage(e)), "warn"); NULL })
  if (!is.list(nom) || is.null(nom$coef)) nom <- NULL  # 失败 → 不引用
  tryCatch(.nafld_od_tables(cfg, dat, de, D, log), error = function(e) log(paste("S15/16 err:", conditionMessage(e)), "warn"))
  tryCatch(.nafld_od_figS3_shap(cfg, D, log, dat), error = function(e) log(paste("FigS3 err:", conditionMessage(e)), "warn"))
  syn <- tryCatch(.nafld_od_syndrome(cfg, dat, de, D, log),
                  error = function(e) { log(paste("S18 syndrome err:", conditionMessage(e)), "warn"); NULL })
  cases <- tryCatch(.nafld_od_cases(cfg, nom, D, log),
                    error = function(e) { log(paste("S19 cases err:", conditionMessage(e)), "warn"); NULL })
  shiny_ok <- tryCatch(.nafld_od_shiny(cfg, nom, D, log),
                       error = function(e) { log(paste("Shiny err:", conditionMessage(e)), "warn"); FALSE })

  # 拷贝图到 summary；S15–S19 进 supplement（定稿 Table S 由 finalize 统一映射到 table/）
  sum_tab <- file.path(D$study, "summary_result", "table")
  sum_fig <- file.path(D$study, "summary_result", "figure")
  dir.create(sum_tab, recursive = TRUE, showWarnings = FALSE)
  dir.create(sum_fig, recursive = TRUE, showWarnings = FALSE)
  for (f in c("Figure 8. Metabolomics overview.pdf", "Figure 9. Nomogram and simplified score.pdf")) {
    s <- file.path(D$figures, f)
    if (file.exists(s)) {
      file.copy(s, file.path(sum_fig, f), overwrite = TRUE)
      file.copy(s, file.path(D$supp_fig, f), overwrite = TRUE)
    }
  }
  # S2/S3 进汇总（与 finalize S1–S6 连续编号对齐）
  for (f in c("Figure S2. Hospital pathway enrichment.pdf",
              "Figure S3. SHAP beeswarm.pdf")) {
    s <- file.path(D$supp_fig, f)
    if (file.exists(s)) file.copy(s, file.path(sum_fig, f), overwrite = TRUE)
  }
  for (f in list.files(D$tables, pattern = "^Table S1[5-9]\\.", full.names = TRUE)) {
    file.copy(f, file.path(D$supp_tab, basename(f)), overwrite = TRUE)
  }

  # 四目录 + image_information（唯一写出入口）
  if (file.exists(file.path(root, "R/pub_figure_export.R"))) {
    source(file.path(root, "R/pub_figure_export.R"), local = FALSE)
    meta8 <- list(
      figure_body_lines = c(
        sprintf("代谢组学概览四面板：A 得分图（PCA/PLS 轴投影，红=NAFLD n=%d，蓝=Normal n=%d，PC1/PC2 标方差占比）；B 火山图（%d 个尿代谢物 Wilcoxon，红=显著上调/蓝=显著下调 FDR<0.05，虚线参考 |log2FC|=0.25 与 P=0.05，标注 top-8 代谢物名）；C top-%d 差异代谢物 z-score 热图（行按 FDR 升序，红=高表达）；D 差异代谢物×临床指标 Spearman 相关（红=正/蓝=负）。对应文献标配（OPLS-DA/火山/聚类热图/相关网络）。",
                sum(as.character(dat$Disease) == "NAFLD"), sum(as.character(dat$Disease) == "Normal"),
                nrow(de), min(max(25L, 8L), max(8L, n_sig))),
        sprintf("图上标注（收获）：FDR<0.05 差异代谢物 %d 个；C 图行数 = min(25, 显著数)；D 图相关系数绝对值 top 对见 Table S16。", n_sig)),
      exposure = "尿代谢组（90 代谢物 GC-MS 池）", outcome = "NAFLD vs Normal",
      grouping = "binary", databases = "Hospital",
      n_total = sprintf("N=%d (NAFLD %d / Normal %d)", nrow(dat),
                        sum(as.character(dat$Disease) == "NAFLD"), sum(as.character(dat$Disease) == "Normal")),
      combined = TRUE)
    meta9 <- list(
      figure_body_lines = c(
        "Nomogram（CM 共识特征：临床+尿代谢物按标准化后 |β| 配额入选，轴一律右=高风险；rms::lrm）。A 列线图；B bootstrap 校准；C 预测概率三分位 NAFLD 率。配套 Table S17。",
        if (!is.null(nom)) sprintf(
          "图上标注（收获）：纳入特征 %d 个（临床 %d + 代谢 %d）；概率三分位切点 %.2f / %.2f；三层 NAFLD 率 %s。",
          nrow(nom$coef),
          sum(!grepl("^U_", nom$selected_features %||% character(0))),
          sum(grepl("^U_", nom$selected_features %||% character(0))),
          nom$cutoffs[1], nom$cutoffs[2],
          paste(sprintf("%s %.1f%%", rownames(nom$tiers), nom$tiers$NAFLD_rate * 100), collapse = " / ")
        ) else NULL),
      exposure = "CM 共识特征（简化评分）", outcome = "NAFLD",
      grouping = "binary", databases = "Hospital",
      n_total = sprintf("N=%d", nrow(dat)), combined = FALSE)
    if (exists("pub_figure_ensure_formats", mode = "function")) {
      tryCatch(pub_figure_ensure_formats(D$figures, config = cfg), error = function(e) NULL)
      pdf_sub <- file.path(sum_fig, "pdf")
      if (dir.exists(pdf_sub))
        for (pf in list.files(pdf_sub, pattern = "\\.pdf$", full.names = TRUE))
          file.copy(pf, file.path(sum_fig, basename(pf)), overwrite = FALSE)
      tryCatch(pub_figure_ensure_formats(sum_fig, config = cfg), error = function(e) NULL)
      if (exists("pub_figure_write_image_md", mode = "function")) {
        for (imdir in c(file.path(D$figures, "image_information"), file.path(sum_fig, "image_information"))) {
          dir.create(imdir, recursive = TRUE, showWarnings = FALSE)
          if (!is.null(meta8$figure_body_lines))
            tryCatch(pub_figure_write_image_md(file.path(imdir, "Figure 8. Metabolomics overview.md"),
                      "Figure 8. Metabolomics overview", meta = meta8, raster_ok = TRUE),
                      error = function(e) NULL)
          if (!is.null(meta9$figure_body_lines) && length(meta9$figure_body_lines))
            tryCatch(pub_figure_write_image_md(file.path(imdir, "Figure 9. Nomogram and simplified score.md"),
                      "Figure 9. Nomogram and simplified score", meta = meta9, raster_ok = TRUE),
                      error = function(e) NULL)
        }
      }
    }
  }

  writeLines(logs, file.path(D$work, "omics_display_log.txt"))
  ctx$results$nafld_omics_display <- list(
    de = de, pathway = pw, nomogram = nom, syndrome = syn,
    representative_cases = cases, shiny = shiny_ok, logs = logs
  )
  cli::cli_alert_success("omics_display 完成：Figure 8/9 + S2/S3 + Table S15–S19 + Shiny")
  ctx
}

if (exists("register_block", mode = "function")) {
  register_block("ml_nafld_omics_display", block_ml_nafld_omics_display,
                 "NAFLD 代谢组学展示 + Nomogram 简化评分（模块六/七补齐）")
}
