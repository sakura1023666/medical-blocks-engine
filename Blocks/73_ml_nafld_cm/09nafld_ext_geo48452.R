###############################################################################
#  09nafld_ext_geo48452.R — Agilent/Illumina 微阵列 GEO 队列 → 通路收敛第二/三源
#
#  被 06block_ml_nafld_external_bridge.R 调用（source 后使用）：
#    .nafld_ext_geo_array(cfg, D, log)   # 接入 GSE48452 + GSE89632，返回合并 hits
#    .nafld_ext_gpl_annot_map(gpl, root) # GPL annot.gz → probe/symbol/entrez
#    .nafld_ext_annot_illumina()         # illuminaHumanv4.db → ILMN 探针注释
#  config$external_bridge$geo48452 = list(enable=TRUE)
#
#  GSE48452：GPL11532 Agilent（NCBI annot，分块下载），log2 ratio 已归一；
#            表型 group: Control/Nash/Steatosis/Healthy obese
#            主对比 Nash vs Control + 预设敏感性 Nash vs Healthy obese（BMI 匹配）
#  GSE89632：GPL14951 Illumina HumanHT-12 V4（ILMN_ 探针；NCBI 无 annot.gz、
#            family.soft=2.4GB 不可达 → 用 Bioconductor illuminaHumanv4.db 离线注释）；
#            原始 intensity → quantile+log2；表型 diagnosis: SS/NASH；对比 NASH vs SS
###############################################################################

#' GPL annot.gz → data.frame(probe, symbol, entrez)；带 gzip 校验，坏/缺文件返回 NULL
.nafld_ext_gpl_annot_map <- function(gpl = "GPL11532", root) {
  f <- file.path(root, "GEO", paste0(gpl, ".annot.gz"))
  if (!file.exists(f)) return(NULL)
  ok <- tryCatch({ system2("gzip", c("-t", shQuote(f)), stdout = FALSE, stderr = FALSE) == 0L },
                 error = function(e) FALSE)
  if (!ok) return(NULL)
  ln <- suppressWarnings(readLines(gzfile(f), warn = FALSE))
  hi <- grep(paste0("^ID\t"), ln)
  if (!length(hi)) return(NULL)
  hdr <- strsplit(ln[hi[1]], "\t")[[1]]
  ic <- which(hdr == "ID"); sc <- grep("^Gene symbol$", hdr); ec <- grep("^Gene ID$", hdr)
  if (length(ic) < 1 || length(sc) < 1 || length(ec) < 1) return(NULL)
  body <- ln[(hi[1] + 1):length(ln)]
  body <- body[nzchar(body)]
  sp <- lapply(body, function(s) strsplit(s, "\t", fixed = TRUE)[[1]])
  ncol_req <- max(ic, sc, ec)
  sp <- sp[lengths(sp) >= ncol_req]
  ann <- data.frame(probe = vapply(sp, function(v) v[ic], ""),
                    symbol = vapply(sp, function(v) v[sc], ""),
                    entrez = vapply(sp, function(v) v[ec], ""), stringsAsFactors = FALSE)
  multi <- grepl("///", ann$symbol)
  if (any(multi)) {
    ex <- do.call(rbind, lapply(which(multi), function(i) {
      ss <- trimws(strsplit(ann$symbol[i], "///")[[1]])
      ee <- trimws(strsplit(ann$entrez[i], "///")[[1]])
      n <- min(length(ss), length(ee))
      if (n < 1) NULL else data.frame(probe = rep(ann$probe[i], n), symbol = ss[seq_len(n)],
                                       entrez = ee[seq_len(n)], stringsAsFactors = FALSE)
    }))
    ann <- rbind(ann[!multi, , drop = FALSE], ex)
  }
  ann <- unique(ann[nzchar(ann$symbol) & !tolower(ann$symbol) %in% c("na",""), , drop = FALSE])
  if (nrow(ann) < 5000L) return(NULL)   # 截断坏文件防护
  ann
}

#' Illumina HumanHT-12 V4（ILMN_）离线注释：illuminaHumanv4.db
.nafld_ext_annot_illumina <- function() {
  if (!requireNamespace("illuminaHumanv4.db", quietly = TRUE) ||
      !requireNamespace("AnnotationDbi", quietly = TRUE)) return(NULL)
  m <- tryCatch(suppressMessages(AnnotationDbi::select(
    illuminaHumanv4.db::illuminaHumanv4.db,
    keys = AnnotationDbi::keys(illuminaHumanv4.db::illuminaHumanv4.db, keytype = "PROBEID"),
    keytype = "PROBEID", columns = c("SYMBOL", "ENTREZID"))), error = function(e) NULL)
  if (is.null(m) || !nrow(m)) return(NULL)
  ann <- data.frame(probe = as.character(m$PROBEID), symbol = as.character(m$SYMBOL),
                    entrez = as.character(m$ENTREZID), stringsAsFactors = FALSE)
  ann <- unique(ann[!is.na(ann$symbol) & nzchar(ann$symbol), , drop = FALSE])
  ann$entrez[is.na(ann$entrez)] <- ""
  if (nrow(ann) < 5000L) return(NULL)
  ann
}

#' 单队列微阵列 DE（limma）→ 四大通路超几何 hits（结构对齐 .nafld_ext_geo）
.nafld_ext_geo_array_one <- function(cfg, D, log, gse, gpl, main_pair, sens_pair = NULL,
                                     grp_from = c("group", "diagnosis"), log2done = TRUE,
                                     norm_qn = FALSE) {
  root <- .nafld_ext_root(cfg)
  mf <- file.path(root, "GEO", gse, paste0(gse, "_series_matrix.txt.gz"))
  if (!file.exists(mf)) { log(sprintf("%s series_matrix 缺失，跳过", gse), "warn"); return(NULL) }
  ann <- if (grepl("^GPL14951$", gpl)) .nafld_ext_annot_illumina() else .nafld_ext_gpl_annot_map(gpl, root)
  if (is.null(ann) || !nrow(ann)) {
    log(sprintf("%s: %s 注释缺失/损坏 → 暂不接入（探针无法映射基因）", gse, gpl), "warn")
    return(NULL)
  }
  if (!requireNamespace("limma", quietly = TRUE)) { log("无 limma，跳过微阵列", "warn"); return(NULL) }
  ln <- suppressWarnings(readLines(gzfile(mf), warn = FALSE))
  gv <- NULL; gname <- ""
  for (key in grp_from) {
    gl <- grep(paste0("^!Sample_characteristics_ch1.*\"", key, ": "), ln, value = TRUE)
    if (length(gl)) {
      gv <- sub(paste0("^", key, ": ?"), "", gsub('"', "", strsplit(gl[1], "\t")[[1]][-1]))
      gname <- key; break
    }
  }
  if (is.null(gv)) { log(sprintf("%s: 无 %s 表型行，跳过", gse, paste(grp_from, collapse="/")), "warn"); return(NULL) }
  i0 <- grep("series_matrix_table_begin", ln)[1]
  i1 <- grep("series_matrix_table_end", ln)[1]
  tab <- ln[(i0 + 1):(i1 - 1)]
  hdr <- gsub('"', "", strsplit(tab[1], "\t")[[1]])
  if (length(hdr) - 1L != length(gv)) { log(sprintf("%s: 矩阵列数≠表型数，跳过", gse), "warn"); return(NULL) }
  rows <- strsplit(tab[-1], "\t")
  probes <- gsub('"', "", vapply(rows, `[`, "", 1L))
  mat <- t(vapply(rows, function(v) suppressWarnings(as.numeric(gsub('"', "", v[-1]))),
                  numeric(length(gv))))
  rownames(mat) <- make.unique(probes); colnames(mat) <- hdr[-1]
  if (!log2done) mat <- log2(pmax(mat, 0) + 1)
  if (isTRUE(norm_qn)) {
    # 单通道 log2 intensity 阵列（如 GSE89632）：limma 标准分位数归一
    mat <- limma::normalizeBetweenArrays(mat, method = "quantile")
  }
  pidx <- match(rownames(mat), ann$probe)
  p2e <- ann$entrez[pidx]; p2s <- ann$symbol[pidx]
  cov <- mean(!is.na(p2e) & nzchar(p2e))
  if (cov < 0.5) {
    log(sprintf("%s: %s 注释覆盖率仅 %.1f%% → 判定注释不完整，跳过", gse, gpl, 100 * cov), "warn")
    return(NULL)
  }
  keep <- !is.na(p2e) & nzchar(p2e)
  mat <- mat[keep, , drop = FALSE]; p2e <- p2e[keep]; p2s <- p2s[keep]
  names(p2e) <- rownames(mat); names(p2s) <- rownames(mat)
  grp <- factor(gv)
  log(sprintf("%s (%s/%s): %d 探针映射 × %d 样本；组: %s；注释覆盖 %.0f%%",
              gse, gpl, gname, nrow(mat), ncol(mat),
              paste(sprintf("%s=%d", levels(grp), as.vector(table(grp))), collapse=", "), 100*cov))
  run_contrast <- function(lvl1, lvl2) {
    if (!all(c(lvl1, lvl2) %in% levels(grp))) return(NULL)
    k <- grp %in% c(lvl1, lvl2)
    if (sum(grp[k] == lvl1) < 5 || sum(grp[k] == lvl2) < 5) return(NULL)
    f2 <- factor(grp[k], levels = c(lvl2, lvl1))
    mm <- stats::model.matrix(~ f2)
    fit <- limma::eBayes(limma::lmFit(mat[, k, drop = FALSE], mm))
    tt <- limma::topTable(fit, coef = 2, number = Inf, sort.by = "none")
    tt <- tt[!is.na(tt$adj.P.Val), , drop = FALSE]
    tt$symbol <- p2s[rownames(tt)]; tt$entrez <- p2e[rownames(tt)]
    agg <- stats::aggregate(cbind(logFC = tt$logFC, t = tt$t), by = list(symbol = tt$symbol), FUN = stats::median)
    pvals <- stats::aggregate(adj.P.Val ~ symbol, data = tt, FUN = min)
    agg <- merge(agg, pvals, by = "symbol")
    agg <- agg[!is.na(agg$symbol) & nzchar(agg$symbol), ]
    sig <- agg[agg$adj.P.Val < 0.05 & abs(agg$logFC) > log2(1.5), ]
    sym_all <- unique(agg$symbol)
    ups <- unique(sig$symbol[sig$logFC > 0]); dns <- unique(sig$symbol[sig$logFC < 0])
    sets <- .nafld_ext_curated_pathways()
    hits <- data.frame(pathway = names(sets), up_n = 0L, dn_n = 0L, up_genes = "", dn_genes = "",
                       total_hits = 0L, pathway_in_universe = 0L, hyper_p = NA_real_,
                       stringsAsFactors = FALSE)
    for (i in seq_along(sets)) {
      g <- intersect(sets[[i]], sym_all)
      hits$pathway_in_universe[i] <- length(g)
      inup <- intersect(sets[[i]], ups); indn <- intersect(sets[[i]], dns)
      hits$up_n[i] <- length(inup); hits$dn_n[i] <- length(indn)
      hits$up_genes[i] <- paste(inup, collapse = "; "); hits$dn_genes[i] <- paste(indn, collapse = "; ")
      hits$total_hits[i] <- length(inup) + length(indn)
      hits$hyper_p[i] <- if (length(g) && length(sym_all) > length(c(ups, dns)))
        stats::phyper(hits$total_hits[i] - 1L, length(g),
                      length(sym_all) - length(g), length(union(ups, dns)), lower.tail = FALSE)
        else NA_real_
    }
    hits$overlap_with_scheme_pathway <- hits$total_hits >= 2L & !is.na(hits$hyper_p) & hits$hyper_p < 0.05
    list(tt = tt, agg = agg, sig = sig, hits = hits, n_up = nrow(sig[sig$logFC > 0, ]),
         n_dn = nrow(sig[sig$logFC < 0, ]), contrast = sprintf("%s vs %s", lvl1, lvl2))
  }
  m1 <- run_contrast(main_pair[1], main_pair[2])
  if (is.null(m1)) { log(sprintf("%s: 主对比组不足，跳过", gse), "warn"); return(NULL) }
  m2 <- if (!is.null(sens_pair)) tryCatch(run_contrast(sens_pair[1], sens_pair[2]), error = function(e) NULL) else NULL
  utils::write.csv(data.frame(symbol = m1$agg$symbol, logFC = round(m1$agg$logFC, 4),
                              FDR = signif(m1$agg$adj.P.Val, 4)),
                   file.path(D$work, sprintf("geo_%s_de_genelevel.csv", tolower(gse))), row.names = FALSE)
  log(sprintf("%s DE: %s；基因级显著 %d（上 %d/下 %d）%s", gse, m1$contrast, nrow(m1$sig),
              m1$n_up, m1$n_dn,
              if (!is.null(m2)) sprintf("；敏感性 %s: 显著 %d", m2$contrast, nrow(m2$sig)) else ""))
  # ── 主/次对比：GSE48452 的 CONTROL 组为正常体重健康人，病例 Nash 组偏胖，
  #    直接 Nash vs Control 会把「肥胖效应」混入「疾病效应」。院内队列同样 BMI
  #    不平衡，故【先验指定】BMI-matched（Nash vs Healthy obese）为主对比，
  #    Nash vs Control 作次要对照；两列均落 S13，非按显著性事后挑选。
  #    main_pair=第一对比（=primary），sens_pair=第二对比（=secondary）。
  hits <- m2$hits %||% m1$hits          # 主列取 BMI-matched（若可得），否则退回 m1
  prim_lbl <- if (!is.null(m2)) "BMI-matched" else "vs Control"
  hits$hyper_p_ctrl <- m1$hits$hyper_p; hits$total_hits_ctrl <- m1$hits$total_hits
  hits$up_n_ctrl <- m1$hits$up_n; hits$dn_n_ctrl <- m1$hits$dn_n
  hits$up_genes_ctrl <- m1$hits$up_genes; hits$dn_genes_ctrl <- m1$hits$dn_genes
  if (!is.null(m2)) {
    hits$hyper_p_bm <- m2$hits$hyper_p; hits$total_hits_bm <- m2$hits$total_hits
    hits$up_n_bm <- m2$hits$up_n; hits$dn_n_bm <- m2$hits$dn_n
    hits$up_genes_bm <- m2$hits$up_genes; hits$dn_genes_bm <- m2$hits$dn_genes
    hits$contrast_used <- "BMI-matched (primary)"
  } else {
    # 无 BMI-matched 第二对比（如 GSE89632）：不建 _bm 列，主列即 m1 本身
    hits$contrast_used <- "main"
  }
  hits$overlap_with_scheme_pathway <- hits$total_hits >= 2L &
    !is.na(hits$hyper_p) & hits$hyper_p < 0.05
  list(gse = gse, platform = gpl, pathway = hits, sens = m2, main = m1,
       method = sprintf("limma %s (%s; primary=%s)", gpl, gse, prim_lbl))
}

#' 两个微阵列队列 → 合并成 .nafld_ext_pathway_convergence 的 geo2 形参
.nafld_ext_geo_array <- function(cfg, D, log) {
  eb <- cfg$external_bridge %||% list()
  g4 <- eb$geo48452 %||% list(enable = TRUE)
  if (isFALSE(g4$enable)) { log("geo array (48452/89632) enable=FALSE，跳过", "info"); return(NULL) }
  q48 <- .nafld_ext_geo_array_one(cfg, D, log, "GSE48452", "GPL11532",
                                  main_pair = c("Nash", "Control"),
                                  sens_pair = c("Nash", "Healthy obese"),
                                  grp_from = "group", log2done = TRUE)
  q89 <- .nafld_ext_geo_array_one(cfg, D, log, "GSE89632", "GPL14951",
                                  main_pair = c("NASH", "SS"),
                                  grp_from = "diagnosis", log2done = TRUE, norm_qn = TRUE)
  qs <- Filter(Negate(is.null), list(q48, q89))
  if (!length(qs)) return(NULL)
  if (length(qs) == 1L) return(qs[[1]])
  base <- qs[[1]]$pathway
  base$pathway_src <- qs[[1]]$gse
  for (k in seq_along(qs)[-1]) {
    add <- qs[[k]]$pathway
    names(add) <- paste0(names(add), ".", qs[[k]]$gse)
    add$pathway <- NULL
    base <- cbind(base, add)
  }
  base$sources_available <- paste(vapply(qs, function(q) q$gse, ""), collapse = "+")
  list(pathway = base, merged_from = vapply(qs, function(q) q$gse, ""), detail = qs,
       method = paste(vapply(qs, function(q) q$method, ""), collapse = " | "),
       gse = paste(vapply(qs, function(q) q$gse, ""), collapse = "+"))
}
