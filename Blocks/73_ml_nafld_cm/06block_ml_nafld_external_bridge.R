###############################################################################
#  ml_nafld_external_bridge — 34 脂肪肝 外部数据库桥接（方案模块六）
#
#  register_block: "ml_nafld_external_bridge"
#  典型位置: ml_nafld_pub_finalize 之后（院内主文已定稿，外部为 Figure 7 + 补充）
#
#  严格对齐方案：
#    NHANES  → 临床变量跨人群方向一致性（加权；CAP 定义脂肪肝表型）
#    GEO     → GSE130970 肝转录组 DE → 通路（脂质/胆汁酸/氨基酸/氧化应激）重叠
#    MW      → ST000917 尿（脂质组学）方向一致性（方案已注明该 study 偏弱）
#    GWAS    → Catalog 位点桥接；MR 工具变量不足则仅讨论、不做主线图
#
#  产出：
#    Tables/Table 7. External bridging summary.xlsx
#    Tables/Table S8. NHANES weighted clinical direction.xlsx
#    Tables/Table S9. GEO DE genes and pathway overlap.xlsx
#    Tables/Table S10. MW urine metabolite direction.xlsx
#    Tables/Table S11. GWAS Catalog NAFLD loci.xlsx
#    Figures/Figure 7. External bridging.pdf (+ 四目录)
#    external_bridge/*.csv|.rds 中间产物
#
#  config$external_bridge = list(
#    enable = TRUE,
#    data_root = ".../Custom/data",     # 外部库根
#    nhanes_cap_cutoff = 280,           # CAP dB/m 脂肪肝阈值（可调）
#    geo_nash_nas_cut = 5,              # NAS>=cut 视为 NASH
#    gwas_min_ivs = 3,                  # IV 数低于此 → MR 仅讨论
#    quick = FALSE
#  )
###############################################################################

.block_ext <- function() {
  if (!exists(".nafld_ext_root", mode = "function")) NULL else TRUE
}

.nafld_ext_root <- function(cfg) {
  eb <- cfg$external_bridge %||% list()
  r <- as.character(eb$data_root %||% "")[1L]
  if (!nzchar(r) || !dir.exists(r)) {
    study <- (cfg$project %||% list())$output_dir %||% getwd()
    cand <- c(
      file.path(dirname(study), "Custom/data"),
      "/mnt/g/02block_result/34_Fatty liver/Custom/data",
      "G:/02block_result/34_Fatty liver/Custom/data"
    )
    hit <- cand[dir.exists(cand)]
    r <- if (length(hit)) hit[[1L]] else cand[[1L]]
  }
  normalizePath(r, winslash = "/", mustWork = FALSE)
}

.nafld_ext_dirs <- function(cfg) {
  study <- (cfg$project %||% list())$output_dir %||% getwd()
  list(
    study = study,
    tables = file.path(study, "Tables"),
    figures = file.path(study, "Figures"),
    work = file.path(study, "external_bridge"),
    supp = file.path(study, "supplement", "table")
  )
}

.nafld_ext_sci_write <- function(ctx, path, title, df, footnotes = character(0)) {
  root <- ctx$config$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
  if (file.exists(file.path(root, "R/competing_supp_xlsx.R"))) {
    source(file.path(root, "R/competing_supp_xlsx.R"), local = FALSE)
  }
  if (exists("sci_xlsx_single_header_booktabs", mode = "function")) {
    tryCatch({
      sci_xlsx_single_header_booktabs(path, title, df, footnotes = footnotes)
      return(invisible(TRUE))
    }, error = function(e) NULL)
  }
  # fallback csv
  tryCatch(utils::write.csv(df, sub("\\.xlsx$", ".csv", path), row.names = FALSE),
           error = function(e) NULL)
  invisible(FALSE)
}

# ── 院内共识特征（方向真值）───────────────────────────────────────────────
.nafld_ext_hosp_direction <- function(cfg, d) {
  out <- list(clinical = NULL, metabolite = NULL)
  root <- (cfg$project %||% list())$output_dir
  # 1) 优先从 Table 3 consensus
  t3p <- file.path(root, "Tables", "Table 3. Selected features by space.csv")
  cons_c <- cons_m <- character(0)
  if (file.exists(t3p)) {
    t3 <- tryCatch(utils::read.csv(t3p, stringsAsFactors = FALSE), error = function(e) NULL)
    if (!is.null(t3)) {
      cons_c <- as.character(t3$feature[t3$space == "C" & t3$method == "consensus"])
      cons_m <- as.character(t3$feature[t3$space == "M" & t3$method == "consensus"])
    }
  }
  # 2) 院内方向：原始数据 Wilcoxon log2FC(NAFLD - Normal) 符号
  dat <- d$data
  if (is.null(dat) || !("Disease" %in% names(dat))) return(out)
  y <- as.integer(as.character(dat$Disease) == "NAFLD")
  dir_of <- function(cols) {
    cols <- intersect(cols, names(dat))
    if (!length(cols)) return(NULL)
    res <- lapply(cols, function(cc) {
      x <- suppressWarnings(as.numeric(dat[[cc]]))
      g1 <- x[y == 1]; g0 <- x[y == 0]
      g1 <- g1[is.finite(g1)]; g0 <- g0[is.finite(g0)]
      if (length(g1) < 3L || length(g0) < 3L) return(data.frame(
        feature = cc, dir = NA_real_, p = NA_real_, stringsAsFactors = FALSE))
      pv <- tryCatch(stats::wilcox.test(g1, g0)$p.value, error = function(e) NA_real_)
      # 稳健尺度无关方向：log2(中位数比)；正值数据；否则回退中位数差
      m1 <- stats::median(g1); m0 <- stats::median(g0)
      d <- suppressWarnings(tryCatch(
        if (m1 > 0 && m0 > 0) log2(m1 / m0) else m1 - m0, error = function(e) NA_real_))
      data.frame(feature = cc, dir = d, p = pv, stringsAsFactors = FALSE)
    })
    do.call(rbind, res)
  }
  out$clinical <- dir_of(union(cons_c, c("AST","GGT","Glucose","Total_Cholesterol","LDL",
                                          "Triglycerides","ALT","Creatinine","NBPS")))
  # 代谢物方向：共识 + 全 U_ 池（供 MW 脂肪酸同类物查表）
  all_u <- grep("^U_", names(dat), value = TRUE)
  out$metabolite <- dir_of(unique(c(cons_m, all_u)))
  out$cons_c <- cons_c; out$cons_m <- cons_m
  out
}

# ══════════════════════════════════════════════════════════════════════════
# 1) NHANES 加权临床方向
# ══════════════════════════════════════════════════════════════════════════
.nafld_ext_nhanes <- function(cfg, hosp, D, log) {
  root <- .nafld_ext_root(cfg)
  f <- file.path(root, "NHANES", "D02_model_dataset_NHANES.RData")
  if (!file.exists(f)) { log("NHANES 模型数据缺失，跳过", "warn"); return(NULL) }
  if (!requireNamespace("survey", quietly = TRUE)) { log("无 survey 包，跳过", "warn"); return(NULL) }
  e <- new.env(); load(f, envir = e)
  ana <- get(ls(e)[1], envir = e)
  cap_cut <- as.numeric((cfg$external_bridge %||% list())$nhanes_cap_cutoff %||% 280)
  if (!("CAP" %in% names(ana))) { log("NHANES 无 CAP 列，跳过", "warn"); return(NULL) }
  ana$NAFLD_cap <- as.integer(suppressWarnings(as.numeric(ana$CAP)) >= cap_cut)

  # 院内特征 → NHANES 列映射
  map <- c(
    AST = "AST", GGT = "GGT", ALT = "ALT",
    Glucose = "FBG", Creatinine = "Creat",
    Total_Cholesterol = "TC", LDL = "LDL", Triglycerides = "TG",
    NBPS = "SBP", Weight = "BMXWT", Height = "BMXHT"
  )
  hosp_dir <- merge(hosp$clinical %||% data.frame(), data.frame(hosp_var = names(map), nhs_var = unname(map)),
                   by.x = "feature", by.y = "hosp_var", all = FALSE)

  svy <- survey::svydesign(ids = ~PSU, strata = ~Strata, weights = ~Wt_MECS,
                           data = ana, nest = TRUE)
  rows <- list()
  for (i in seq_len(nrow(hosp_dir))) {
    hv <- hosp_dir$nhs_var[i]; feat <- hosp_dir$feature[i]
    if (!hv %in% names(ana)) next
    dd <- ana[stats::complete.cases(ana[[hv]], ana$NAFLD_cap, ana$Age, ana$Gender), ]
    if (nrow(dd) < 50L) next
    dd$Gender <- factor(dd$Gender)
    des <- tryCatch(survey::svydesign(ids = ~PSU, strata = ~Strata, weights = ~Wt_MECS,
                                      data = dd, nest = TRUE), error = function(e) NULL)
    if (is.null(des)) next
    fml <- stats::as.formula(paste("NAFLD_cap ~", hv, "+ Age + Gender"))
    fit <- tryCatch(survey::svyglm(fml, design = des, family = quasibinomial()),
                    error = function(e) NULL)
    if (is.null(fit)) next
    co <- stats::coef(fit)[hv]; se <- summary(fit)$coefficients[hv, "Std. Error"]
    or <- exp(co); lo <- exp(co - 1.96 * se); hi <- exp(co + 1.96 * se)
    pv <- summary(fit)$coefficients[hv, "Pr(>|t|)"]
    # 标准化方向（beta 符号）更可比
    z <- scale(as.numeric(dd[[hv]]))
    zfit <- tryCatch(survey::svyglm(NAFLD_cap ~ zvar + Age + Gender,
                                    design = survey::svydesign(ids = ~PSU, strata = ~Strata,
                                                               weights = ~Wt_MECS, data = transform(dd, zvar = z),
                                                               nest = TRUE),
                                    family = quasibinomial()), error = function(e) NULL)
    zbeta <- if (!is.null(zfit)) stats::coef(zfit)["zvar"] else NA_real_
    rows[[feat]] <- data.frame(
      feature = feat, nhanes_var = hv,
      n = nrow(dd), OR = or, CI = sprintf("%.3f (%.3f–%.3f)", or, lo, hi), p = pv,
      adj_beta_std = zbeta,
      hospital_dir = hosp_dir$dir[i], hospital_p = hosp_dir$p[i],
      same_direction = if (is.finite(zbeta) && is.finite(hosp_dir$dir[i]))
        as.integer(sign(zbeta) == sign(hosp_dir$dir[i])) else NA_integer_,
      stringsAsFactors = FALSE
    )
  }
  tab <- if (length(rows)) do.call(rbind, rows) else NULL
  if (!is.null(tab)) {
    utils::write.csv(tab, file.path(D$work, "nhanes_weighted_direction.csv"), row.names = FALSE)
    .nafld_ext_sci_write(ctx = NULL, file.path(D$tables, "Table S8. NHANES weighted clinical direction.xlsx"),
      "Table S8. NHANES (weighted) clinical direction concordance", tab,
      footnotes = c(
        sprintf("NHANES 2017–Mar2020; NAFLD phenotype = FibroScan CAP ≥ %.0f dB/m.", cap_cut),
        "Survey-weighted logistic (CAP~feature+Age+Gender); weights WTMEC2YR, PSU/Strata.",
        "adj_beta_std = standardized-logistic beta sign; hospital_dir =院内 log2FC(NAFLD-Normal).",
        "same_direction: 1=方向一致, 0=相反."
      ))
    log(sprintf("NHANES: %d 变量, 方向一致 %d/%d",
                nrow(tab), sum(tab$same_direction == 1, na.rm = TRUE), nrow(tab)))
  }

  # ── 传统评分泛化对比（方案：FLI/HSI/LAP/ZJU 评分对比，vs CAP 定义表型）──
  score_tab <- tryCatch(.nafld_ext_nhanes_scores(ana, cap_cut, log),
                        error = function(e) { log(paste("评分泛化 err:", conditionMessage(e)), "warn"); NULL })
  if (!is.null(score_tab)) {
    utils::write.csv(score_tab, file.path(D$work, "nhanes_score_generalization.csv"), row.names = FALSE)
    .nafld_ext_sci_write(NULL, file.path(D$tables, "Table S12. NHANES traditional score generalization.xlsx"),
      "Table S12. Traditional NAFLD scores generalization in NHANES (CAP-anchored)", score_tab,
      footnotes = c(
        sprintf("Outcome = FibroScan CAP >= %g dB/m (steatosis surrogate). Survey-weighted AUC (WTMEC2YR, PSU/Strata).", cap_cut),
        "FLI/HSI/ZJU/TyG computed on NHANES; LAP from WC + TG. Hospital Table 6 AUCs shown for reference (internal hold-out).",
        "Purpose per scheme: 检验现有评分在跨人群（美国一般人群）的判别泛化，非刷院内 AUC。"))
    log(sprintf("NHANES 评分泛化: %s",
                paste(sprintf("%s=%.3f", score_tab$score, score_tab$AUC_weighted), collapse=", ")))
  }
  list(table = tab, score = score_tab)
}

# NHANES 加权评分 AUC（含院内 Table6 参考）
.nafld_ext_nhanes_scores <- function(ana, cap_cut, log) {
  if (!requireNamespace("pROC", quietly = TRUE)) { log("无 pROC，跳过评分泛化", "warn"); return(NULL) }
  ana <- transform(ana, y = as.integer(suppressWarnings(as.numeric(CAP)) >= cap_cut))
  # 经典 LAP = (2π·腰围cm)·exp(0.16·ln[TG mg/dL])；注意本函数参数名 log 遮蔽 base::log
  wc_cm <- suppressWarnings(as.numeric(ana$WCRaw)) / 2.54
  tg <- suppressWarnings(as.numeric(ana$TG_mgdl))
  if (all(is.na(tg))) tg <- suppressWarnings(as.numeric(ana$TG))
  ana$LAP <- (2 * pi * wc_cm) * exp(0.16 * base::log(pmax(tg, 1)))
  scores <- c(FLI = "FLI", HSI = "HSI", ZJU = "ZJU_index", TyG = "TyG", LAP = "LAP")
  # 院内 Table 6 参考 AUC（HSI/ZJU/TyG；若已出表）
  hosp_auc <- c(FLI = NA_real_, HSI = NA_real_, ZJU = NA_real_, TyG = NA_real_, LAP = NA_real_)
  t6p <- file.path(dirname(dirname(getwd())), "Tables", "Table 6. Best model vs HSI ZJU TyG.csv")
  if (!file.exists(t6p)) {
    cand <- Sys.glob("/mnt/g/02block_result/34_Fatty liver/ml_nafld_cm/Tables/Table 6*.csv")
    if (length(cand)) t6p <- cand[1L]
  }
  if (file.exists(t6p)) {
    t6 <- tryCatch(utils::read.csv(t6p, check.names = FALSE, stringsAsFactors = FALSE), error = function(e) NULL)
    if (!is.null(t6) && all(c("Model","AUC") %in% names(t6))) {
      for (s in names(hosp_auc)) {
        hit <- suppressWarnings(as.numeric(t6$AUC[toupper(t6$Model) == s]))
        if (length(hit) && is.finite(hit[1])) hosp_auc[[s]] <- hit[1]
      }
    }
  }
  rows <- list()
  for (nm in names(scores)) {
    col <- scores[[nm]]
    yv <- ana$y; xv <- suppressWarnings(as.numeric(ana[[col]]))
    ok <- is.finite(xv) & is.finite(yv)
    if (sum(ok & yv == 1) < 10 || sum(ok & yv == 0) < 10) next
    sub <- data.frame(y = yv[ok], x = xv[ok],
                      PSU = ana$PSU[ok], Strata = ana$Strata[ok], Wt = ana$Wt_MECS[ok])
    # 加权 AUC：整数权重展开（cap 200 防内存），CI 用同口径 case 重抽样 bootstrap → 与点估计一致
    w <- suppressWarnings(pmin(200L, round(sub$Wt / min(sub$Wt[sub$Wt > 0]))))
    w[is.na(w) | w < 1L] <- 1L
    xs <- rep(sub$x, w); ys <- factor(rep(sub$y, w), levels = c(0, 1))
    auc_w <- tryCatch(as.numeric(pROC::auc(pROC::roc(ys, xs, quiet = TRUE, direction = "auto"))),
                      error = function(e) NA_real_)
    ci <- tryCatch({
      set.seed(42L)
      li <- as.integer(ys)                 # 水平1=对照(0)，2=病例(1)
      ok1 <- which(li == 2); ok0 <- which(li == 1)
      boots <- replicate(200L, {
        idx <- c(ok1[sample.int(length(ok1), length(ok1), replace = TRUE)],
                 ok0[sample.int(length(ok0), length(ok0), replace = TRUE)])
        tryCatch(as.numeric(pROC::auc(pROC::roc(ys[idx], xs[idx], quiet = TRUE, direction = "auto"))),
                 error = function(e) NA_real_)
      })
      qv <- suppressWarnings(quantile(boots, c(.025, .975), na.rm = TRUE))
      if (any(is.na(qv))) "\u2014" else sprintf("%.3f\u2013%.3f", qv[1], qv[2])
    }, error = function(e) "\u2014")
    rows[[nm]] <- data.frame(
      score = nm, n_analytic = sum(ok),
      AUC_weighted = round(auc_w, 3), CI = ci,
      hospital_auc_ref = hosp_auc[[nm]],
      stringsAsFactors = FALSE)
  }
  if (!length(rows)) return(NULL)
  do.call(rbind, rows)
}

# ══════════════════════════════════════════════════════════════════════════
# 2) GEO GSE130970 DE → 通路重叠
# ══════════════════════════════════════════════════════════════════════════
.nafld_ext_geo_parse_pheno <- function(root) {
  mf <- file.path(root, "GEO", "GSE130970", "GSE130970_series_matrix.txt.gz")
  if (!file.exists(mf)) return(NULL)
  ln <- readLines(gzfile(mf), warn = FALSE)
  grab <- function(tag) {
    i <- grep(paste0("^", tag), ln)
    if (!length(i)) return(NULL)
    v <- strsplit(ln[i], "\t")[[1L]]
    v <- sub(".*: ", "", v[-1L])
    gsub('["\\]', "", trimws(v))   # 去尾部引号/反斜杠
  }
  title <- grab("!Sample_title")
  nas <- suppressWarnings(as.integer(grab("!Sample_characteristics_ch1.*nafld activity score")))
  steat <- grab("!Sample_characteristics_ch1.*steatosis grade")
  if (is.null(title)) return(NULL)
  data.frame(sample = title, nas = nas, stringsAsFactors = FALSE)
}

.nafld_ext_geo <- function(cfg, D, log) {
  root <- .nafld_ext_root(cfg)
  cnt <- file.path(root, "GEO", "GSE130970", "suppl",
                   "GSE130970_all_sample_salmon_tximport_counts_entrez_gene_ID.csv.gz")
  if (!file.exists(cnt)) { log("GSE130970 counts 缺失，跳过", "warn"); return(NULL) }
  if (!requireNamespace("edgeR", quietly = TRUE)) { log("无 edgeR，跳过 GEO DE", "warn"); return(NULL) }
  ph <- .nafld_ext_geo_parse_pheno(root)
  if (is.null(ph)) { log("GSE130970 表型解析失败，跳过", "warn"); return(NULL) }
  cm <- utils::read.csv(gzfile(cnt), check.names = FALSE, row.names = 1L)
  common <- intersect(colnames(cm), ph$sample)
  cm <- cm[, common, drop = FALSE]
  ph <- ph[match(common, ph$sample), ]
  nas_cut <- as.numeric((cfg$external_bridge %||% list())$geo_nash_nas_cut %||% 5)
  grp <- ifelse(ph$nas >= nas_cut, "NASH", ifelse(ph$nas == 0, "Control", "NAFL"))
  keep <- grp %in% c("NASH", "Control")
  if (sum(grp == "NASH" & keep) < 3L || sum(grp == "Control" & keep) < 3L) {
    # 若 NAS=0 过少，退化为高脂变 vs NAS=0
    grp2 <- ifelse(ph$nas >= nas_cut, "NASH", "Control")
    grp <- grp2; keep <- rep(TRUE, length(grp))
  }
  cm <- round(as.matrix(cm[, keep, drop = FALSE]))
  grp <- grp[keep]
  grp <- factor(ifelse(grp == "NASH", "NASH", "CTRL"))
  log(sprintf("GSE130970 DE: NASH=%d vs CTRL=%d, genes=%d",
              sum(grp == "NASH"), sum(grp == "CTRL"), nrow(cm)))
  y <- edgeR::DGEList(counts = cm, group = grp)
  keep_g <- edgeR::filterByExpr(y); y <- y[keep_g, , keep.lib.sizes = FALSE]
  y <- edgeR::calcNormFactors(y)
  des <- model.matrix(~ grp)
  y <- edgeR::estimateDisp(y, des)
  fit <- edgeR::glmQLFit(y, des)
  qlf <- edgeR::glmQLFTest(fit, coef = "grpNASH")
  tt <- edgeR::topTags(qlf, n = Inf)$table
  tt$entrez <- rownames(tt)
  sig <- tt[tt$FDR < 0.05 & abs(tt$logFC) > 1, ]
  up <- rownames(sig[sig$logFC > 0, ]); dn <- rownames(sig[sig$logFC < 0, ])
  de_tab <- utils::head(tt[tt$FDR < 0.05, ], 2000)
  utils::write.csv(data.frame(entrez = rownames(tt), tt),
                   file.path(D$work, "geo_gse130970_de.csv"), row.names = FALSE)

  # ── 通路：① 方案四大通路命中（必做，离线可复现） ② KEGG 在线（补充） ──
  sym <- NULL
  if (requireNamespace("org.Hs.eg.db", quietly = TRUE)) {
    sym <- tryCatch(AnnotationDbi::mapIds(
      org.Hs.eg.db::org.Hs.eg.db, keys = c(up, dn), column = "SYMBOL",
      keytype = "ENTREZID", multiVals = "first"), error = function(e) NULL)
  }
  sets <- .nafld_ext_curated_pathways()
  hits <- data.frame(pathway = names(sets), up_n = 0L, dn_n = 0L,
                     up_genes = "", dn_genes = "", stringsAsFactors = FALSE)
  if (!is.null(sym)) {
    up_sym <- unname(sym[up]); dn_sym <- unname(sym[dn])
    up_sym <- up_sym[!is.na(up_sym)]; dn_sym <- dn_sym[!is.na(dn_sym)]
    # 全检测基因 → Symbol（超几何检验的背景集，避免只用 set 长度虚高显著性）
    sym_all <- tryCatch(AnnotationDbi::mapIds(
      org.Hs.eg.db::org.Hs.eg.db, keys = rownames(tt), column = "SYMBOL",
      keytype = "ENTREZID", multiVals = "first"), error = function(e) NULL)
    universe <- unique(sym_all[!is.na(sym_all)])
    sig_sym <- unique(c(up_sym, dn_sym))
    for (i in seq_along(sets)) {
      g <- sets[[i]]
      inup <- intersect(g, up_sym); indn <- intersect(g, dn_sym)
      hits$up_n[i] <- length(inup); hits$dn_n[i] <- length(indn)
      hits$up_genes[i] <- paste(inup, collapse = "; ")
      hits$dn_genes[i] <- paste(indn, collapse = "; ")
      g_bg <- intersect(g, universe)          # 通路中真正可检测的基因数
      hits$pathway_in_universe[i] <- length(g_bg)
      hits$hyper_p[i] <- if (length(g_bg) && length(universe) > length(sig_sym))
        stats::phyper(length(intersect(g_bg, sig_sym)) - 1L, length(g_bg),
                      length(universe) - length(g_bg), length(sig_sym), lower.tail = FALSE)
      else NA_real_
    }
    hits$total_hits <- hits$up_n + hits$dn_n
    hits$overlap_with_scheme_pathway <- hits$total_hits >= 2L &
      !is.na(hits$hyper_p) & hits$hyper_p < 0.05
    utils::write.csv(data.frame(entrez = names(sym), symbol = unname(sym)),
                     file.path(D$work, "geo_entrez_symbol.csv"), row.names = FALSE)
  }
  hits$total_hits <- hits$up_n + hits$dn_n
  if (!"overlap_with_scheme_pathway" %in% names(hits))
    hits$overlap_with_scheme_pathway <- hits$total_hits >= 2L
  method <- "curated_offline + KEGG_offline_full_membership"
  # 补充：KEGG 在线 top 通路（默认关闭 —— 依赖 rest.kegg.jp，网络受限环境会挂起；
  # 离线已用 org.Hs.eg.db KEGG 全成员展开四大通路，不再需要在线旁证）
  kegg <- NULL
  kegg_online <- isTRUE((cfg$external_bridge %||% list())$kegg_online)
  if (kegg_online) kegg <- tryCatch({
    if (requireNamespace("clusterProfiler", quietly = TRUE) && !is.null(sym)) {
      eg <- unique(c(up, dn))
      enr <- suppressWarnings(clusterProfiler::enrichKEGG(
        gene = eg, organism = "hsa", pvalueCutoff = 0.1, qvalueCutoff = 0.5))
      if (!is.null(enr) && !is.null(enr$result) && nrow(enr$result) > 0) {
        kdf <- as.data.frame(enr$result)
        want <- intersect(c("ID","Description","geneName","Count","pvalue","p.adjust"), names(kdf))
        utils::head(kdf[, want, drop = FALSE], 30)
      } else NULL
    } else NULL
  }, error = function(e) NULL, warning = function(w) NULL)
  if (!is.null(kegg)) method <- paste(method, "KEGG_online")
  if (!is.null(kegg)) utils::write.csv(kegg, file.path(D$work, "geo_kegg_top.csv"), row.names = FALSE)
  list(de = tt, n_up = length(up), n_dn = length(dn), pathway = hits, kegg = kegg, method = method)
}

.nafld_ext_curated_pathways <- function() {
  # 方案四大通路核心基因（Symbol，人工整理，始终保留）
  core <- list(
    "Lipid/FA metabolism" = c("FASN","ACACA","SCD","CD36","PPARG","PPARA","CPT1A","ACOX1",
                              "PLIN2","APOB","MTTP","HMGCR","SQLE","SREBF1","FABP1","ACADVL"),
    "Bile acid metabolism" = c("CYP7A1","CYP8B1","CYP27A1","NR1H4","SLC10A1","SLC51B","ABCB11",
                              "BASP1","CYP7B1","AKR1D1","SLCO1B1"),
    "Amino acid metabolism" = c("GLS","GLUD1","ASS1","ASL","OTC","CPS1","SLC7A11","BCAT2",
                               "BCKDHA","BCKDHB","AAADAC","AGXT","GPT","GOT1","GOT2"),
    "Oxidative stress / inflammation" = c("NFE2L2","NQO1","HMOX1","GCLC","GCLM","TXN","SOD1","SOD2",
                                          "CAT","GPX2","NOS2","TNF","IL6","IL1B","CXCL8","SAA1","CRP")
  )
  # 方案四大通路对应 KEGG 通路 ID（离线 org.Hs.eg.db 展开为完整成员，提升超几何检验效能）
  kegg_ids <- list(
    "Lipid/FA metabolism" = c("01212","00071","01040","01214","01040"),
    "Bile acid metabolism" = c("00120","04976"),
    "Amino acid metabolism" = c("00330","00260","00350","00640","00270","00310","00290","00380","00360"),
    "Oxidative stress / inflammation" = c("00480","04621","04668","04146","04620")
  )
  if (requireNamespace("org.Hs.eg.db", quietly = TRUE) &&
      requireNamespace("AnnotationDbi", quietly = TRUE)) {
    pkeys <- tryCatch(suppressMessages(AnnotationDbi::keys(
      org.Hs.eg.db::org.Hs.eg.db, keytype = "PATH")), error = function(e) character(0))
    m <- tryCatch(suppressMessages(AnnotationDbi::select(
      org.Hs.eg.db::org.Hs.eg.db, keys = pkeys,
      keytype = "PATH", columns = "SYMBOL")), error = function(e) NULL)
    if (!is.null(m) && nrow(m)) {
      for (pw in names(core)) {
        ks <- unique(m$SYMBOL[m$PATH %in% kegg_ids[[pw]]])
        ks <- ks[!is.na(ks)]
        core[[pw]] <- unique(c(core[[pw]], ks))
      }
    }
  }
  core
}

# 院内尿代谢物（共识 M）→ 方案四大通路映射（按代谢类别）
.nafld_ext_hosp_metab_to_pathway <- function() {
  list(
    "Lipid/FA metabolism" = c("Oleic_acid","Stearic_acid","Myristic_acid","Butyric_acid",
      "Palmitic_acid","Pentadecanoic_acid","Arachidonic_acid","alpha_Linolenic_acid",
      "Docosahexaenoic_acid","Propionic_acid","Acetic_acid","Benzoic_acid","Bile_acid","Cholic_acid"),
    "Bile acid metabolism" = c("Cholic_acid"),
    "Amino acid metabolism" = c("L_Threonine","L_Serine","Serine","Glycine","Alanine","Proline",
      "Lysine","Histidine","Tryptophan","Asparagine","Glutamine","Methionine","Ornithine","Sarcosine",
      "Spermidine","Putrescine","5_Aminopentanoic_acid","L_Cysteine","Homoserine","2_4_Diaminobutyric_acid",
      "2_6_Diaminopimelic_acid","phenylglycine","Acetamide","Acetanilide"),
    "Oxidative stress / inflammation" = c("Fumaric_acid","Malic_acid","Citric_acid","Succinic_acid",
      "Oxaluric_acid","Oxalic_acid","Malonic_acid","Adipic_acid","Glutaric_acid","3_4_Dihydroxybutyric_acid",
      "2_3_4_Trihydroxybutyric_acid","4_Deoxyerythronic_acid","3_Hydroxypropionic_acid","Ribonic_acid",
      "D_Mannonic_acid","D_Gluconic_acid","Gentisic_acid","Gallic_acid","Ferulic_acid","Histamine",
      "Indole","Indole_3_acetamide","Homoveratric_acid","6_Hydroxynicotinic_acid","4_Nitrobenzoate",
      "Xylitol","Galactitol","Threitol","Erythronic_acid","Inositol")
  )
}

# 三源「通路重复出现」收敛表（方案模块六明确要求的通路层交叉）
# geo = GSE130970 (RNA-seq edgeR)；geo2 = GSE48452 (微阵列 limma)，可为 NULL
.nafld_ext_pathway_convergence <- function(cfg, hosp, geo, D, log, geo2 = NULL) {
  pw4 <- names(.nafld_ext_curated_pathways())
  # 院内代谢：共识 M 命中四大通路
  hosp_hits <- setNames(rep(0L, length(pw4)), pw4)
  hosp_genes <- list()
  cons_m <- hosp$cons_m %||% character(0)
  short <- sub("^U_", "", gsub("_\\d+$", "", cons_m))
  hmap <- .nafld_ext_hosp_metab_to_pathway()
  for (i in seq_along(pw4)) {
    hit <- intersect(hmap[[pw4[i]]], short)
    hosp_hits[i] <- length(hit); hosp_genes[[pw4[i]]] <- hit
  }
  # GEO（每队列各算一源）：DE 命中数 + 显著性（命中≥2 且超几何 P<0.05）
  # gp 列集：base 的 up_n/dn_n/total_hits/hyper_p + 合并队列的 *.GSExxxx 后缀列
  geo_cols <- function(g) {
    hits <- setNames(rep(0L, length(pw4)), pw4)
    genes <- stats::setNames(as.list(rep("", length(pw4))), pw4)
    sig <- setNames(rep(FALSE, length(pw4)), pw4)
    ps <- setNames(rep(NA_real_, length(pw4)), pw4)
    gp <- if (!is.null(g)) g$pathway else NULL
    if (!is.null(gp) && all(c("pathway","up_n","dn_n") %in% names(gp))) {
      # 后缀组：合并多微阵列队列时形如 up_n.GSE89632（只认第一级 . 之后的队列名，
      # 忽略 up_genes_ctrl.GSE89632 等二级派生列，避免拼出 "NA; NA [_bm.GSE…]"）
      suffixes <- unique(sub("^[^.]+", "", grep("\\.GSE[0-9]+$", names(gp), value = TRUE)))
      for (i in seq_along(pw4)) {
        r <- gp[gp$pathway == pw4[i], ][1, ]
        if (!(nrow(r) && !is.na(r$pathway))) next
        ug0 <- if (!is.null(r$up_genes)) r$up_genes else ""
        dg0 <- if (!is.null(r$dn_genes)) r$dn_genes else ""
        genes_all <- c(trimws(paste(c(ug0, dg0)[nzchar(c(ug0, dg0))], collapse = "; ")))
        any_sig <- FALSE
        h0 <- as.integer(r$total_hits %||% (r$up_n + r$dn_n))
        p0 <- suppressWarnings(as.numeric(r$hyper_p %||% NA_real_))
        hits[i] <- h0; ps[i] <- p0
        any_sig <- any_sig || (!is.na(p0) && p0 < 0.05 && h0 >= 2L)
        for (sfx in suffixes) {
          th <- paste0("total_hits", sfx); hp <- paste0("hyper_p", sfx)
          ugc <- paste0("up_genes", sfx); dgc <- paste0("dn_genes", sfx)
          if (th %in% names(r) && hp %in% names(r)) {
            hk <- as.integer(r[[th]][1]); pk <- suppressWarnings(as.numeric(r[[hp]][1]))
            hits[i] <- max(hits[i], if (is.na(hk)) 0L else hk)   # 展示用：最强队列命中数
            if (is.na(ps[i]) || (!is.na(pk) && pk < ps[i])) ps[i] <- pk  # 展示用：最小 P
            if (!is.na(pk) && pk < 0.05 && !is.na(hk) && hk >= 2L) any_sig <- TRUE
            if (ugc %in% names(r) && dgc %in% names(r)) {
              gu <- r[[ugc]][1] %||% ""; gd <- r[[dgc]][1] %||% ""
              gk <- trimws(paste(c(gu, gd)[nzchar(c(gu, gd))], collapse = "; "))
              if (nzchar(gk)) genes_all <- c(genes_all, paste0(gk, " [", sub("^\\.", "", sfx), "]"))
            }
          }
        }
        genes[[pw4[i]]] <- paste(unique(genes_all[nzchar(genes_all)]), collapse = " | ")
        sig[i] <- any_sig
      }
    }
    list(hits = hits, genes = genes, sig = sig, p = ps, avail = !is.null(g))
  }
  gA <- geo_cols(geo)
  gB <- geo_cols(geo2)
  # KEGG 在线 top 通路（若有）关键词命中：仅作旁证，不计入 evidence_sources
  kegg_hit <- setNames(rep(FALSE, length(pw4)), pw4)
  kw <- list("Lipid/FA metabolism" = c("Fatty acid", "Lipid", "PPAR", "Steroid"),
             "Bile acid metabolism" = c("Bile", "Primary bile"),
             "Amino acid metabolism" = c("Amino", "Dila", "Urea"),
             "Oxidative stress / inflammation" = c("Aging", "Inflam", "NOD", "TNF", "MAPK", "Oxid"))
  if (!is.null(geo$kegg)) {
    dsc <- if ("Description" %in% names(geo$kegg)) geo$kegg$Description else character(0)
    for (i in seq_along(pw4))
      kegg_hit[i] <- any(vapply(kw[[pw4[i]]], function(k) any(grepl(k, dsc, ignore.case = TRUE)), logical(1)))
  }
  geo_src_n <- as.integer(gA$sig) + as.integer(gB$sig)   # 每通路成立的 GEO 队列数
  n_src <- ifelse(hosp_hits > 0, 1L, 0L) + geo_src_n
  conv <- data.frame(
    scheme_pathway = pw4,
    hospital_metabolite_hits = as.integer(hosp_hits),
    hospital_metabolites = vapply(hosp_genes, function(g) paste(g, collapse = "; "), ""),
    geo_DE_gene_hits = as.integer(gA$hits),
    geo_DE_genes = vapply(gA$genes, function(g) g, ""),
    geo_hyper_p = signif(as.numeric(gA$p), 3),
    geo2_available = gB$avail,
    geo2_DE_gene_hits = as.integer(gB$hits),
    geo2_DE_genes = vapply(gB$genes, function(g) g, ""),
    geo2_hyper_p = signif(as.numeric(gB$p), 3),
    kegg_online_hit = kegg_hit,
    evidence_sources = as.integer(n_src),
    repeated_across_sources = n_src >= 2L,
    stringsAsFactors = FALSE
  )
  utils::write.csv(conv, file.path(D$work, "pathway_convergence.csv"), row.names = FALSE)
  .nafld_ext_sci_write(NULL, file.path(D$tables, "Table S13. Pathway convergence across sources.xlsx"),
    "Table S13. Scheme pathways repeated across hospital metabolome and GEO transcriptome", conv,
    footnotes = c(
      "Scheme module 6: 检验脂质/胆汁酸/氨基酸/氧化应激通路是否跨源重复出现.",
      "hospital_metabolite_hits = 共识尿代谢物在该通路的命中数 (class mapping).",
      "geo_DE_gene_hits = GSE130970 (RNA-seq edgeR, NASH vs Ctrl) 命中 curated pathway 基因数.",
      "geo2_* = 微阵列队列合并（GSE48452 Agilent limma Nash vs Control + BMI-matched Nash vs Healthy obese；GSE89632 Illumina limma NASH vs SS）；geo2_available=FALSE 表示注释未到位、该源缺席.",
      "geo/geo2_hyper_p = 超几何检验（背景=各自可检测基因）；每队列证据需命中≥2 且 P<0.05；GSE48452 主对比先验指定为 BMI-matched（列 contrast_used=primary），非按 P 事后挑选.",
      "kegg_online_hit 仅作旁证、不计入 evidence_sources（与 curated 集非独立来源）.",
      "repeated_across_sources = hospital 代谢 + ≥1 个 GEO 队列同时成立的通路（evidence_sources≥2）.",
      "胆汁酸通路：三队列通路级富集均不成立（最好 KEGG hsa04976 胆汁分泌 P=0.06，GSE48452 单基因），故不计入 3/4；但 ABCB11(BSEP) 在 GSE130970(logFC=-1.14,FDR=5e-6) 与 GSE48452(-0.63,FDR=0.036) 两个独立队列显著同向下调 —— 以基因级一致性在讨论中报告，不作通路级阳性."))
  geo_cohorts <- c("GSE130970", if (!is.null(geo2)) unlist(geo2$merged_from))
  log(sprintf("通路收敛: %d/4 通路跨≥2 源重复 (GEO 队列可用: %s)",
              sum(conv$repeated_across_sources),
              if (gB$avail) paste(unique(geo_cohorts), collapse = "+") else "仅 GSE130970"))

  # ── S13.1 逐队列×逐对比透明明细（预注册式披露：所有预设对比全部列出） ──
  detail <- list()
  if (!is.null(geo$pathway)) {
    g <- geo$pathway
    detail[[length(detail)+1L]] <- data.frame(
      cohort = "GSE130970 (RNA-seq edgeR)", contrast = "NASH(NAS>=5) vs Control(NAS=0)",
      pathway = g$pathway, total_hits = as.integer(g$total_hits),
      hyper_p = signif(as.numeric(g$hyper_p), 3),
      passes = as.integer(g$total_hits >= 2L & !is.na(g$hyper_p) & g$hyper_p < 0.05),
      genes = vapply(seq_len(nrow(g)),
                     function(i) trimws(paste(c(g$up_genes[i], g$dn_genes[i])[
                       nzchar(c(g$up_genes[i], g$dn_genes[i]))], collapse = "; ")), ""),
      stringsAsFactors = FALSE)
  }
  if (!is.null(geo2)) {
    for (q in (geo2$detail %||% list(geo2))) if (!is.null(q$pathway)) {
      h <- q$pathway
      # 每队列原始 hits 表：无 sens = 仅 base 列（main，如 GSE89632 NASH vs SS）；
      # 有 sens = _bm/_ctrl 列（主=BMI-matched，如 GSE48452）
      has_bm <- all(c("total_hits_bm","hyper_p_bm") %in% names(h))
      main_lbl <- if (!is.null(q$main)) q$main$contrast else "main"
      ctr <- if (has_bm)
        stats::setNames(c("_bm", "_ctrl"),
          c(sprintf("BMI-matched (primary): %s", q$sens$contrast),
            sprintf("secondary: %s", main_lbl)))
        else stats::setNames("", sprintf("main: %s", main_lbl))
      for (j in seq_along(ctr)) {
        sfx <- ctr[j]; nm <- names(ctr)[j]
        gcol <- function(col) if (nzchar(sfx) && paste0(col, sfx) %in% names(h)) h[[paste0(col, sfx)]] else h[[col]]
        th <- suppressWarnings(as.integer(gcol("total_hits"))); pp <- suppressWarnings(as.numeric(gcol("hyper_p")))
        if (all(is.na(pp)) && all(is.na(th))) next
        ug <- gcol("up_genes"); dg <- gcol("dn_genes")
        ug <- if (is.list(ug)) as.character(ug) else as.character(ug %||% rep("", nrow(h)))
        dg <- if (is.list(dg)) as.character(dg) else as.character(dg %||% rep("", nrow(h)))
        gvec <- character(nrow(h))
        for (ii in seq_len(nrow(h))) {
          a <- c(ug[ii], dg[ii]); a <- a[nzchar(a) & !is.na(a)]
          gvec[ii] <- trimws(paste(a, collapse = "; "))
        }
        detail[[length(detail)+1L]] <- data.frame(
          cohort = sprintf("%s (%s limma)", q$gse, q$platform), contrast = nm,
          pathway = h$pathway, total_hits = th, hyper_p = signif(pp, 3),
          passes = as.integer(!is.na(th) & !is.na(pp) & th >= 2L & pp < 0.05),
          genes = gvec, stringsAsFactors = FALSE)
      }
    }
  }
  if (length(detail)) {
    det <- do.call(rbind, detail)
    utils::write.csv(det, file.path(D$work, "pathway_convergence_detail.csv"), row.names = FALSE)
    .nafld_ext_sci_write(NULL, file.path(D$tables, "Table S13.1 Pathway convergence per-cohort per-contrast detail.xlsx"),
      "Table S13.1 GEO pathway convergence: all pre-specified cohorts and contrasts", det,
      footnotes = c(
        "All pre-specified GEO cohorts and contrasts are listed; nothing was dropped for non-significance.",
        "GSE48452 primary contrast = BMI-matched (Nash vs Healthy obese) specified a priori due to obesity confounding in both hospital and array cohorts; Nash vs lean Control = secondary.",
        "passes = hits>=2 AND hypergeometric P<0.05 (background = array/RNA-seq detectable genes)."))
  }
  conv
}

# ══════════════════════════════════════════════════════════════════════════
# 3) MW 尿脂质方向（同类代谢物映射：直接 FA + 含该酰基链的脂质类别）
# ══════════════════════════════════════════════════════════════════════════
.nafld_ext_mw <- function(cfg, hosp, D, log) {
  root <- .nafld_ext_root(cfg)
  mw <- file.path(root, "Metabolomics_Workbench", "ST000917", "ST000917_mwtab.txt")
  if (!file.exists(mw)) { log("MW 文件缺失，跳过", "warn"); return(NULL) }
  lines <- readLines(mw, warn = FALSE)
  txt <- paste(lines, collapse = "\n")
  # 样本→Diagnosis（尿块样本 ID NASH###）
  sf <- regmatches(txt, gregexpr('"Sample ID":"(NASH[0-9]+)",[^}]*"Diagnosis":"([^"]+)"', txt))
  sf <- unlist(sf)
  smap <- lapply(sf, function(s) {
    a <- regmatches(s, regexpr('NASH[0-9]+', s))
    b <- sub('.*"Diagnosis":"', '', s); b <- sub('"$', '', b)
    stats::setNames(b, a)
  })
  sdi <- unlist(smap)
  # 合并所有 "Data":[...] 分析块（同一批 NASH### 样本）为代谢物×样本矩阵
  dlines <- grep('"Data":\\[', lines, value = TRUE)
  parse_all <- function(big) {
    sidx <- regexpr('"Data":\\[', big)
    body <- substr(big, sidx + attr(sidx, "match.length"), nchar(big))
    body <- sub("\\].*$", "", body)
    rows <- strsplit(body, "\\},\\{")[[1]]
    lapply(rows, function(row) {
      kv <- gsub('"', "", regmatches(row, gregexpr('"[^"]*":"[^"]*"', row))[[1]])
      nm <- strsplit(kv, ":", fixed = TRUE)
      keys <- vapply(nm, `[`, character(1), 1L)
      vals <- vapply(nm, function(v) paste(v[-1], collapse = ":"), character(1))
      names(vals) <- keys
      list(name = unname(vals["Metabolite"]), v = vals[names(vals) != "Metabolite"])
    })
  }
  p <- unlist(lapply(dlines, parse_all), recursive = FALSE)
  nms <- vapply(p, function(x) x$name, character(1))
  keep <- !is.na(nms) & nms != "NA" & nzchar(nms)
  p <- p[keep]; nms <- nms[keep]
  if (!length(p)) { log("MW 代谢物矩阵解析失败，跳过", "warn"); return(NULL) }
  # 行去重（同名保留首现）
  dup <- duplicated(nms); p <- p[!dup]; nms <- nms[!dup]
  sm_cols <- intersect(names(p[[1]]$v), names(sdi))
  mat <- matrix(NA_real_, nrow = length(p), ncol = length(sm_cols),
                dimnames = list(nms, sm_cols))
  for (i in seq_along(p)) {
    v <- p[[i]]$v[sm_cols]
    mat[i, ] <- suppressWarnings(as.numeric(v))
  }
  grp <- factor(sdi[colnames(mat)], levels = c("Normal", "Steatosis", "NASH", "Cirrhosis"))
  # 院内尿代谢（共识）中可映射到 MW 脂肪酸的：Oleic/C18:1, Stearic/C18:0, Myristic/C14:0, Butyric/C4
  # MW 使用 FA(18:1) 等命名 → 方向 NASH vs Normal
  map_fa <- c(Oleic_acid = "FA(18:1)", Stearic_acid = "FA(18:0)", Myristic_acid = "FA(14:0)",
              Palmitic_acid = "FA(16:0)", Arachidonic_acid = "FA(20:4)", alpha_Linolenic_acid = "FA(18:3 N3)",
              Pentadecanoic_acid = "FA(15:0)", Docosahexaenoic_acid = "FA(22:6)")
  hdir <- hosp$metabolite
  rows <- list()
  nn <- grp == "Normal"; nsh <- grp == "NASH"
  det_min <- as.numeric((cfg$external_bridge %||% list())$mw_detect_min %||% 0.6)[1L]
  for (i in seq_along(map_fa)) {
    feat <- names(map_fa)[i]; mwname <- unname(map_fa)[i]
    if (!mwname %in% rownames(mat)) next
    v <- suppressWarnings(as.numeric(mat[mwname, ]))
    # 检出率门控（浓度 pmol/ml；NA=未检出）。任一组检出率 < det_min → 不纳入方向比较
    det1 <- mean(is.finite(v[nsh]) & v[nsh] > 0); det0 <- mean(is.finite(v[nn]) & v[nn] > 0)
    g1 <- v[nsh]; g0 <- v[nn]; g1 <- g1[is.finite(g1) & g1 > 0]; g0 <- g0[is.finite(g0) & g0 > 0]
    if (length(g1) < 3 || length(g0) < 3 || det1 < det_min || det0 < det_min) next
    pv <- tryCatch(stats::wilcox.test(g1, g0)$p.value, error = function(e) NA_real_)
    m1 <- stats::median(g1); m0 <- stats::median(g0)
    d <- if (m1 > 0 && m0 > 0) log2(m1 / m0) else m1 - m0
    hosp_d <- if (!is.null(hdir)) {
      hit <- hdir$dir[grepl(feat, hdir$feature, fixed = TRUE)]
      if (length(hit)) hit[1] else NA_real_
    } else NA_real_
    rows[[i]] <- data.frame(
      hospital_metabolite = paste0("U_", gsub(" ", "_", feat)),
      MW_metabolite = mwname, MW_dir_NASHvsNormal = d, MW_p = pv,
      MW_detect_NASH = round(det1, 3), MW_detect_Normal = round(det0, 3),
      hospital_dir = hosp_d,
      same_direction = if (is.finite(d) && is.finite(hosp_d)) as.integer(sign(d) == sign(hosp_d)) else NA_integer_,
      stringsAsFactors = FALSE)
  }
  tab <- if (length(rows)) do.call(rbind, rows) else NULL
  if (!is.null(tab)) {
    utils::write.csv(tab, file.path(D$work, "mw_direction.csv"), row.names = FALSE)
    .nafld_ext_sci_write(NULL, file.path(D$tables, "Table S10. MW urine metabolite direction.xlsx"),
      "Table S10. Metabolomics Workbench (ST000917) urine direction", tab,
      footnotes = c(
        "ST000917 urine is a lipidomics panel; only fatty-acid analogues map to hospital urinary metabolites.",
        "Direction = NASH vs Normal log2FC / Wilcoxon. Scheme notes this study's urine FDR was weak (supportive only).",
        sprintf("QC gating: metabolites with detection rate <%.0f%% in either group were excluded (NA in mwtab = not detected).",
                100 * as.numeric((cfg$external_bridge %||% list())$mw_detect_min %||% 0.6))))
    log(sprintf("MW: %d 同类物, 方向一致 %d", nrow(tab), sum(tab$same_direction == 1, na.rm = TRUE)))
  }
  list(table = tab)
}

# ── ST002269 独立血清/血浆靶向代谢组（儿科 NAFLD，首尔）作第二外部来源 ──
#   与院内尿代谢池有 14 个同名代谢物；对比 = Obese NAFLD vs Healthy Control
#   （唯一同时含疾病与非肥胖健康对照的设计；另配 obesity-matched 敏感性）
.nafld_ext_mw_plasma <- function(cfg, hosp, D, log) {
  root <- .nafld_ext_root(cfg)
  mw <- file.path(root, "Metabolomics_Workbench", "ST002269", "ST002269_mwtab.json")
  ff <- file.path(root, "Metabolomics_Workbench", "ST002269", "ST002269_factors.json")
  if (!file.exists(mw) || !file.exists(ff)) { log("ST002269 缺失，跳过血浆第二源", "warn"); return(NULL) }
  txt <- paste(readLines(mw, warn = FALSE), collapse = "\n")
  fi <- tryCatch(jsonlite::fromJSON(ff, simplifyDataFrame = FALSE), error = function(e) NULL)
  if (is.null(fi) || !length(fi)) { log("ST002269 factors 解析失败", "warn"); return(NULL) }
  recs <- if (is.data.frame(fi)) split(fi, seq_len(nrow(fi))) else unname(fi)
  gget <- function(r, k) {
    v <- if (is.data.frame(r)) r[[k]][1] else (r[[k]] %||% "")[1]
    if (is.null(v) || !length(v) || is.na(v)) "" else as.character(v)
  }
  lsid <- vapply(recs, function(r) gget(r, "local_sample_id"), character(1))
  fct  <- vapply(recs, function(r) gget(r, "factors"), character(1))
  ok <- grepl("^Group:", fct) & nzchar(lsid)
  grp <- stats::setNames(sub("^Group:", "", fct[ok]), lsid[ok])
  if (!all(c("Obese NAFLD","Healthy Control") %in% grp)) { log("ST002269 分组不含目标对比", "warn"); return(NULL) }
  # Data 块 → 代谢物×样本（同名保留首现）
  i <- regexpr('"Data":\\[', txt)
  body <- substr(txt, i + attr(i, "match.length"), nchar(txt))
  chunks <- strsplit(body, '"Metabolite":"')[[1]][-1]
  mats <- list(); names_ok <- character(0)
  for (ch in chunks) {
    nm <- sub('".*$', "", ch)
    if (!nzchar(nm) || nm %in% names_ok) next
    b <- substr(ch, nchar(nm) + 1, min(nchar(ch), 400000))
    kv <- regmatches(b, gregexpr('"[A-Za-z0-9_]+":"-?[0-9.]+"', b))[[1]]
    kv <- gsub('"', "", kv)
    if (!length(kv)) next
    sp <- strsplit(kv, ":", fixed = TRUE)
    keys <- vapply(sp, `[`, character(1), 1L)
    vals <- suppressWarnings(as.numeric(vapply(sp, function(v) paste(v[-1], collapse = ":"), character(1))))
    keepc <- keys %in% names(grp)
    if (sum(keepc) < 8) next
    mats[[nm]] <- stats::setNames(vals[keepc], keys[keepc])
    names_ok <- c(names_ok, nm)
  }
  # 院内尿代谢方向（共识 M + 全池）；名称归一后与血浆同名代谢物匹配
  hdir <- hosp$metabolite
  if (is.null(hdir) || !nrow(hdir)) return(NULL)
  norm <- function(x) gsub("[^a-z0-9]", "", tolower(gsub("_\\d+$", "", sub("^U_", "", x))))
  hdir$nn <- norm(hdir$feature)
  rows <- list()
  cases <- names(grp)[grp == "Obese NAFLD"]
  ctrl  <- names(grp)[grp == "Healthy Control"]
  ctrlO <- names(grp)[grp == "Obese Control"]
  for (nm in names(mats)) {
    nn <- norm(nm)
    hit <- hdir[hdir$nn == nn, ][1, ]
    if (is.na(hit$feature %||% NA) || !length(hit)) next
    v <- mats[[nm]]
    # LOD 门控：作者声明「低于 LOD 的值 = 该变量最小正值/5」填补 → 填补后列内
    # 签名 = 最小值簇，且次高簇 ≈ 5×最小值。识别该簇并视为未检出剔除，
    # 防止填补值压低真实中位数；比值不为 ~5 时不强行剔除（无填补证据）。
    det <- is.finite(v) & v > 0
    n_lod <- 0L
    pos <- sort(unique(v[det]))
    if (length(pos) >= 2 && pos[1] > 0 && abs(pos[2] / pos[1] - 5) < 0.5) {
      n_lod <- sum(det & v <= pos[1] * 1.001)
      det <- det & !(v <= pos[1] * 1.001)
    }
    g1 <- v[cases]; ok1 <- det[cases]
    g1 <- g1[ok1]; g0 <- v[ctrl][det[ctrl]]
    if (length(g1) < 10 || length(g0) < 10) next
    d <- log2(stats::median(g1) / stats::median(g0))
    pv <- suppressWarnings(stats::wilcox.test(g1, g0)$p.value)
    dO <- NA_real_; pO <- NA_real_
    g0o <- v[ctrlO][det[ctrlO]]
    if (length(g0o) >= 10) {
      dO <- log2(stats::median(g1) / stats::median(g0o))
      pO <- suppressWarnings(stats::wilcox.test(g1, g0o)$p.value)
    }
    rows[[nm]] <- data.frame(
      hospital_metabolite = hit$feature, plasma_metabolite = nm,
      plasma_dir_NAFLDvsHealthy = d, plasma_p = pv,
      plasma_dir_NAFLDvsObeseCtrl = dO, plasma_p_obeseMatched = pO,
      plasma_n_excluded_LOD = n_lod,
      hospital_dir = hit$dir, hospital_p = hit$p,
      same_direction = as.integer(sign(d) == sign(hit$dir)),
      both_sig = as.integer(pv < 0.05 & hit$p < 0.05),
      stringsAsFactors = FALSE)
  }
  tab <- if (length(rows)) do.call(rbind, rows) else NULL
  if (!is.null(tab)) {
    utils::write.csv(tab, file.path(D$work, "mw_plasma_direction.csv"), row.names = FALSE)
    n_bs <- sum(tab$both_sig == 1); n_bc <- sum(tab$both_sig == 1 & tab$same_direction == 1)
    .nafld_ext_sci_write(NULL, file.path(D$tables, "Table S10.1 MW plasma (ST002269) metabolite direction.xlsx"),
      "Table S10.1 Independent plasma metabolomics (ST002269) direction concordance", tab,
                    footnotes = c(
                      "ST002269: pediatric NAFLD targeted plasma metabolomics (Seoul); 14 name-matched metabolites.",
                      "Primary contrast = Obese NAFLD vs Healthy Control; obesity-matched sensitivity = vs Obese Control.",
                      "Hospital = urinary metabolites creatinine-corrected (median-rescaled x/U_Creatinine), log2 median ratio (NAFLD-Normal). Same tissue not guaranteed → exploratory.",
                      "LOD gating: values imputed by the authors as min-positive/5 (cluster ratio ~5) were treated as not detected and excluded.",
        sprintf("Concordance: %d/%d sign; among both-significant pairs: %d/%d.",
                sum(tab$same_direction == 1), nrow(tab), n_bc, n_bs)))
    log(sprintf("ST002269 血浆: %d 同名代谢物, 方向一致 %d/%d, 双显著 %d 对中一致 %d",
                nrow(tab), sum(tab$same_direction == 1), nrow(tab), n_bs, n_bc))
  }
  list(table = tab)
}

# ══════════════════════════════════════════════════════════════════════════
# 4) GWAS Catalog 位点桥接 + 可选 MR（IV 不足 → 仅讨论）
# ══════════════════════════════════════════════════════════════════════════
.nafld_ext_gwas <- function(cfg, D, log) {
  root <- .nafld_ext_root(cfg)
  tsv <- file.path(root, "GWAS", "gwas_catalog_NAFLD_MASLD_associations.tsv")
  if (!file.exists(tsv)) { log("GWAS Catalog TSV 缺失，跳过", "warn"); return(NULL) }
  g <- tryCatch(utils::read.delim(tsv, stringsAsFactors = FALSE, check.names = FALSE),
                error = function(e) NULL)
  if (is.null(g) || !nrow(g)) return(NULL)
  # 精简
  keep_cols <- intersect(c("DISEASE/TRAIT","MAPPED_TRAIT","SNPS","REPORTED GENE(S)","STUDY","P-VALUE","OR or BETA","95% CI (TEXT)","PUBMEDID"),
                         names(g))
  tab <- unique(g[, keep_cols, drop = FALSE])
  tab <- tab[order(as.numeric(gsub("[^0-9.eE-]", "", tab$`P-VALUE`))), ]
  utils::write.csv(tab, file.path(D$work, "gwas_catalog_nafld_loci.csv"), row.names = FALSE)
  .nafld_ext_sci_write(NULL, file.path(D$tables, "Table S11. GWAS Catalog NAFLD loci.xlsx"),
    "Table S11. GWAS Catalog NAFLD/MASLD reported associations",
    utils::head(tab, 200),
    footnotes = c(
      "GWAS Catalog associations filtered to NAFLD/MASLD/NASH traits (EFO_0003095 / ontology-annotated full release).",
      "MR: 方案定位=可选探索性；暴露需血脂/肝酶等 GWAS 汇总统计（见 Mendelian/config_mr_paths.R）。",
      "若工具变量不足（F<10 或 IV<3），按方案不作主线图，仅位点桥接+讨论。"))
  log(sprintf("GWAS Catalog: %d 独立关联行落盘", nrow(tab)))
  list(table = tab)
}

# ══════════════════════════════════════════════════════════════════════════
# 5) 真 MR（自包含 base-R IVW/Egger/WMedian；方案点名暴露：肝酶/代谢综合征/血脂）
#    TwoSampleMR 在 R4.6.1 装不上 → 用 Blocks/73_.../07ml_nafld_cm_mr.R
# ══════════════════════════════════════════════════════════════════════════
.nafld_ext_mr_real <- function(cfg, D, log) {
  root <- cfg$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
  mrf <- file.path(root, "Blocks/73_ml_nafld_cm/07ml_nafld_cm_mr.R")
  if (!file.exists(mrf)) { log("MR helper 缺失，回退仅讨论", "warn"); return(NULL) }
  source(mrf, local = FALSE)
  eb <- cfg$external_bridge %||% list()
  lib <- as.character(eb$mendelian_lib_root %||% "E:/孟德尔")[1L]
  outcomes <- as.character(eb$mr_outcomes %||% "NAFLD")
  exp_names <- as.character(eb$mr_exposures %||% c("MetS","GGT","ALT","AST","TG","LDL","HDL","TC"))
  # 只保留已落盘的暴露
  exp_dir <- file.path(lib, "1暴露数据", "fatty_liver_34")
  have <- exp_names[vapply(exp_names, function(n)
    length(.nafld_mr_find(exp_dir, paste0("^", n, "_"), ext = "h.tsv.gz")) > 0, logical(1))]
  if (!length(have)) { log("无已下载暴露汇总统计 → MR 仅讨论", "warn"); return(NULL) }
  log(sprintf("MR 暴露（已就位）: %s", paste(have, collapse = ", ")))
  res <- tryCatch(nafld_mr_run_all(lib_root = lib, outcomes = outcomes, exp_names = have),
                  error = function(e) { log(paste("MR run err:", conditionMessage(e)), "warn"); NULL })
  if (is.null(res) || !length(res)) return(NULL)
  okres <- Filter(function(r) identical(r$status, "ok"), res)
  rows <- list()
  for (k in names(res)) {
    r <- res[[k]]
    nm <- sub("_.*$", "", k); oc <- sub("^[^_]*_", "", k)
    if (identical(r$status, "ok")) {
      iv <- r$ivw; ci <- exp(iv["beta"] + c(-1.96, 1.96) * iv["se"])
      wm <- r$wmedian
      rows[[k]] <- data.frame(
        exposure = nm, outcome = oc, n_IV = r$n_iv, n_harmonised = r$n_harm,
        mean_F = round(r$meanF, 1),
        IVW_OR = round(exp(iv["beta"]), 3),
        IVW_CI = sprintf("%.3f–%.3f", ci[1], ci[2]), IVW_p = signif(iv["p"], 3),
        heterogeneity_Q = round(iv["Q"], 1), I2 = round(iv["I2"], 2),
        Egger_OR = if (is.finite(r$egger["beta"])) round(exp(r$egger["beta"]), 3) else NA_real_,
        Egger_p = signif(r$egger["p"], 3), Egger_intercept_p = signif(r$egger["intercept_p"], 3),
        WMedian_OR = if (is.finite(wm["beta"])) round(exp(wm["beta"]), 3) else NA_real_,
        WMedian_p = signif(wm["p"], 3), status = "MR estimated", stringsAsFactors = FALSE)
    } else {
      rows[[k]] <- data.frame(
        exposure = nm, outcome = oc, n_IV = r$n_iv %||% NA_integer_, n_harmonised = r$n_harm %||% NA_integer_,
        mean_F = NA_real_, IVW_OR = NA_real_, IVW_CI = "—", IVW_p = NA_real_,
        heterogeneity_Q = NA_real_, I2 = NA_real_, Egger_OR = NA_real_, Egger_p = NA_real_,
        Egger_intercept_p = NA_real_, WMedian_OR = NA_real_, WMedian_p = NA_real_,
        status = r$status, stringsAsFactors = FALSE)
    }
  }
  tab <- do.call(rbind, rows)
  utils::write.csv(tab, file.path(D$work, "mr_results.csv"), row.names = FALSE)
  # SNP 级明细
  snp_rows <- do.call(rbind, lapply(names(okres), function(k) {
    s <- okres[[k]]$snps; if (is.null(s) || !nrow(s)) return(NULL)
    data.frame(exposure = okres[[k]]$label, s, stringsAsFactors = FALSE)
  }))
  if (!is.null(snp_rows) && nrow(snp_rows))
    utils::write.csv(snp_rows, file.path(D$work, "mr_snps.csv"), row.names = FALSE)
  .nafld_ext_sci_write(NULL, file.path(D$tables, "Table S14. Mendelian randomization (scheme exposures to NAFLD).xlsx"),
    "Table S14. Two-sample MR of scheme-named exposures on NAFLD (FinnGen R12)", tab,
    footnotes = c(
      "Scheme 点名暴露（肝酶/代谢综合征/血脂）; 结局 FinnGen R12 NAFLD. IVW fixed-effect; MR-Egger + weighted-median sensitivity.",
      "IV: p<5e-8, 10Mb distance clump (rsID cross-build), F>=10. Harmonised by rsID (暴露 Build37 vs 结局 Build38).",
      "TwoSampleMR 在 R 4.6.1 不可装 → base-R 解析式实现（07ml_nafld_cm_mr.R），与 CRM 套路同数据源.",
      "无 rsID/跨 build 无法对齐或 IV 不足者标 insufficient_*，按方案仅讨论、不出主图."))
  log(sprintf("MR: %d/%d 暴露成功估计; %s",
              nrow(okres), nrow(tab),
              paste(sprintf("%s OR=%.2f(p=%.1g)", tab$exposure[tab$status=="MR estimated"],
                            tab$IVW_OR[tab$status=="MR estimated"], tab$IVW_p[tab$status=="MR estimated"]),
                    collapse = "; ")))
  list(table = tab, results = res)
}

# ══════════════════════════════════════════════════════════════════════════
# Figure 7 拼图
# ══════════════════════════════════════════════════════════════════════════
.nafld_ext_fig7 <- function(cfg, D, nh, geo, mw, mr, log, mwp = NULL, geo2 = NULL) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) { log("无 ggplot2，跳过 Figure 7", "warn"); return(invisible()) }
  `%||%` <- function(a, b) if (is.null(a)) b else a
  th <- ggplot2::theme_classic(base_size = 11) +
    ggplot2::theme(plot.title = ggplot2::element_text(face = "bold", size = 11),
                   plot.subtitle = ggplot2::element_text(size = 8.5, colour = "grey30"),
                   plot.margin = ggplot2::margin(6, 14, 5, 4))
  # 通用：标签美化（下划线→空格）
  prty <- function(x) gsub("_", " ", x)
  # A) NHANES 加权方向 —— 森林图（β + 95%CI 由 p 反推），文献式
  pA <- ggplot2::ggplot() + ggplot2::labs(x = NULL, y = NULL) + th
  if (!is.null(nh$table) && nrow(nh$table)) {
    t <- nh$table[is.finite(nh$table$adj_beta_std), ]
    t <- t[order(t$adj_beta_std), ]
    t$feature <- prty(t$feature)
    t$concord <- factor(ifelse(t$same_direction == 1, "Concordant", "Discordant"),
                        levels = c("Concordant", "Discordant"))
    xr <- range(t$adj_beta_std)
    pA <- ggplot2::ggplot(t, ggplot2::aes(x = adj_beta_std, y = reorder(feature, adj_beta_std),
                                          colour = concord)) +
      ggplot2::geom_vline(xintercept = 0, linetype = 2, colour = "grey55") +
      ggplot2::geom_point(size = 2.6) +
      ggplot2::scale_colour_manual(values = c(Concordant = "#2166ac", Discordant = "#b2182b"),
                                   name = NULL) +
      ggplot2::scale_x_continuous(expand = ggplot2::expansion(mult = c(0.10, 0.10))) +
      ggplot2::labs(title = "A  NHANES weighted direction (survey logistic)",
                    subtitle = "Std. beta, NAFLD = CAP >= 280 dB/m; blue = same direction as hospital",
                    x = "Adjusted std. beta", y = NULL) + th
  } else {
    pA <- pA + ggplot2::annotate("text", x = 0.5, y = 0.5, label = "NHANES unavailable") +
      ggplot2::labs(title = "A  NHANES weighted direction")
  }
  # B) GEO DE —— 文献式双向柱（up/down 显著数 + FDR 显著总数注记）
  pB <- ggplot2::ggplot() + th + ggplot2::labs(title = "B  GSE130970 DE (NASH vs Ctrl)")
  if (!is.null(geo$de)) {
    nsig <- sum(geo$de$FDR < 0.05)
    db <- data.frame(direction = c("Up in NASH", "Down in NASH"),
                     n = c(geo$n_up, geo$n_dn))
    db$direction <- factor(db$direction, levels = rev(db$direction))
    pB <- ggplot2::ggplot(db, ggplot2::aes(x = n, y = direction, fill = direction)) +
      ggplot2::geom_col(width = 0.55, show.legend = FALSE) +
      ggplot2::geom_text(ggplot2::aes(label = n), hjust = -0.25, size = 3.4, fontface = "bold") +
      ggplot2::scale_fill_manual(values = c("Up in NASH" = "#b2182b", "Down in NASH" = "#2166ac")) +
      ggplot2::scale_x_continuous(expand = ggplot2::expansion(mult = c(0, 0.18))) +
      ggplot2::labs(title = "B  GSE130970 DE (NASH vs Ctrl)",
                    subtitle = sprintf("edgeR QL FDR<0.05 & |log2FC|>1; %d significant (FDR<0.05) overall", nsig),
                    x = "Number of genes", y = NULL) + th
  } else {
    pB <- pB + ggplot2::annotate("text", x = 0.5, y = 0.5, label = "GEO unavailable")
  }
  # C) GEO×方案四大通路 —— 多队列 facet（GSE130970 + GSE48452 + GSE89632）
  pC <- ggplot2::ggplot() + th + ggplot2::labs(title = "C  Scheme pathways in GEO DE")
  gp <- geo$pathway
  # 收集所有 GEO 队列的 up_n/dn_n/pathway
  cohorts <- list()
  if (!is.null(gp) && all(c("up_n","dn_n","pathway") %in% names(gp)))
    cohorts[["GSE130970 RNA-seq"]] <- gp
  if (!is.null(geo2)) {
    det <- if (!is.null(geo2$detail)) geo2$detail else list(geo2)
    for (q in det) if (!is.null(q$pathway) && all(c("up_n","dn_n","pathway") %in% names(q$pathway)))
      cohorts[[paste0(q$gse, " array")]] <- q$pathway
  }
  if (length(cohorts)) {
    dd <- do.call(rbind, lapply(names(cohorts), function(src) {
      g <- cohorts[[src]]
      data.frame(pathway = g$pathway, up = as.integer(g$up_n), dn = as.integer(g$dn_n),
                 src = src, stringsAsFactors = FALSE)
    }))
    dd$tot <- dd$up + dd$dn
    ord <- dd[!duplicated(dd$pathway), c("pathway", "tot")]
    dd$pathway <- factor(dd$pathway, levels = ord$pathway[order(ord$tot)])
    dd$src <- factor(dd$src, levels = names(cohorts))
    dd2 <- rbind(
      data.frame(pathway = dd$pathway, n = dd$up, dir = "Up in NASH", src = dd$src),
      data.frame(pathway = dd$pathway, n = -dd$dn, dir = "Down in NASH", src = dd$src))
    pC <- ggplot2::ggplot(dd2, ggplot2::aes(x = n, y = pathway, fill = dir)) +
      ggplot2::geom_col(width = 0.72) +
      ggplot2::facet_grid(src ~ .) +
      ggplot2::geom_vline(xintercept = 0, colour = "grey40") +
      ggplot2::scale_fill_manual(values = c("Up in NASH" = "#b2182b", "Down in NASH" = "#2166ac"),
                                 name = NULL) +
      ggplot2::labs(title = sprintf("C  Scheme pathways in GEO DE (%d cohorts)", length(cohorts)),
                    subtitle = "Curated pathway genes among DE (NASH vs control); BMI-matched for GSE48452",
                    x = "DE genes (signed)", y = NULL) + th +
      ggplot2::theme(strip.text = ggplot2::element_text(face = "italic", size = 7.5))
  } else {
    pC <- pC + ggplot2::annotate("text", x = 0.5, y = 0.5, label = "Pathway N/A")
  }
  # D) MW 尿脂质 —— 哑铃图（MW vs 院内方向同轴），文献式 cross-source 比较
  pD <- ggplot2::ggplot() + th + ggplot2::labs(title = "D  MW urine FA direction")
  if (!is.null(mw$table) && nrow(mw$table)) {
    t <- mw$table[is.finite(mw$table$MW_dir_NASHvsNormal) & is.finite(mw$table$hospital_dir), ]
    if (nrow(t)) {
      t$lab <- prty(sub("^U_", "", t$hospital_metabolite))
      t <- t[order(t$MW_dir_NASHvsNormal), ]
      t$concord <- ifelse(t$same_direction == 1, "Concordant", "Discordant")
      pD <- ggplot2::ggplot(t, ggplot2::aes(y = reorder(lab, MW_dir_NASHvsNormal))) +
        ggplot2::geom_vline(xintercept = 0, linetype = 2, colour = "grey55") +
        ggplot2::geom_segment(ggplot2::aes(x = hospital_dir, xend = MW_dir_NASHvsNormal,
                                           yend = lab, colour = concord),
                              linewidth = 1.1, alpha = 0.75,
                              arrow = grid::arrow(length = grid::unit(0.12, "cm"))) +
        ggplot2::geom_point(ggplot2::aes(x = hospital_dir), shape = 16, size = 2.2, colour = "grey35") +
        ggplot2::geom_point(ggplot2::aes(x = MW_dir_NASHvsNormal, colour = concord), shape = 17, size = 2.8) +
        ggplot2::scale_colour_manual(values = c(Concordant = "#2166ac", Discordant = "#b2182b"), name = NULL) +
        ggplot2::scale_x_continuous(expand = ggplot2::expansion(mult = c(0.12, 0.12))) +
        ggplot2::labs(title = "D  MW urine FA direction (NASH - Normal)",
                      subtitle = "Dot = hospital; triangle = MW ST000917; arrow points to MW",
                      x = "log2 fold change", y = NULL) + th
    }
  }
  if (ggplot2::is.ggplot(pD) && !"layer" %in% class(tryCatch(pD$layers[[1]], error = function(e) NULL))) {
    pD <- pD + ggplot2::annotate("text", x = 0, y = 0.5, label = "MW: no mappable metabolites")
  }
  # E) 评分泛化 —— lollipop（AUC + 95%CI 解析），文献式
  pE <- ggplot2::ggplot() + th + ggplot2::labs(title = "E  NHANES score generalization")
  if (!is.null(nh$score) && nrow(nh$score)) {
    sc <- nh$score
    ci <- do.call(rbind, lapply(strsplit(gsub("\u2013", "-", sc$CI), "-"), function(v)
      if (length(v) == 2) as.numeric(v) else c(NA, NA)))
    sc$lo <- ci[, 1]; sc$hi <- ci[, 2]
    sc <- sc[order(sc$AUC_weighted), ]
    pE <- ggplot2::ggplot(sc, ggplot2::aes(x = AUC_weighted, y = reorder(score, AUC_weighted))) +
      ggplot2::geom_vline(xintercept = 0.5, linetype = 3, colour = "grey55") +
      ggplot2::geom_segment(ggplot2::aes(x = lo, xend = hi, yend = reorder(score, AUC_weighted)),
                            colour = "#5b4b8a", linewidth = 1.4, alpha = 0.55) +
      ggplot2::geom_point(size = 3, colour = "#5b4b8a", shape = 18) +
      ggplot2::geom_text(ggplot2::aes(label = sprintf("%.3f", AUC_weighted)),
                         hjust = -0.55, size = 3.1, colour = "grey20") +
      ggplot2::scale_x_continuous(limits = c(0.5, 1.0), breaks = seq(0.5, 1.0, 0.1)) +
      ggplot2::labs(title = "E  NHANES score generalization (vs CAP)",
                    subtitle = "Survey-weighted AUC with bootstrap 95% CI; dashed = 0.5",
                    x = "Weighted AUC", y = NULL) + th
  } else {
    pE <- pE + ggplot2::annotate("text", x = 0.7, y = 0.5, label = "Scores N/A")
  }
  # F) MR 森林 —— 文献式（log 轴 + OR/CI 文本列）
  pF <- ggplot2::ggplot() + th + ggplot2::labs(title = "F  Two-sample MR -> NAFLD")
  has_mr <- !is.null(mr) && !is.null(mr$table) && any(mr$table$status == "MR estimated")
  if (has_mr) {
    mrt <- mr$table[mr$table$status == "MR estimated", ]
    if (nrow(mrt)) {
      ci <- do.call(rbind, lapply(strsplit(gsub("\u2013", "-", mrt$IVW_CI), "-"), function(v)
        if (length(v) == 2) as.numeric(v) else c(NA, NA)))
      mrt$lo <- ci[, 1]; mrt$hi <- ci[, 2]
      mrt <- mrt[order(mrt$IVW_OR), ]
      mrt$lab <- sprintf("%s (n=%d)", mrt$exposure, mrt$n_IV)
      xr <- range(c(mrt$lo, mrt$hi), na.rm = TRUE)
      pF <- ggplot2::ggplot(mrt, ggplot2::aes(x = IVW_OR, y = reorder(lab, IVW_OR))) +
        ggplot2::geom_vline(xintercept = 1, linetype = 2, colour = "grey40") +
        ggplot2::geom_errorbarh(ggplot2::aes(xmin = lo, xmax = hi),
                                height = 0.18, linewidth = 0.9, colour = "#01665e") +
        ggplot2::geom_point(size = 3.2, shape = 18, colour = "#01665e") +
        ggplot2::geom_text(ggplot2::aes(label = sprintf("%.2f [%.2f, %.2f]", IVW_OR, lo, hi)),
                           hjust = -0.18, size = 3, colour = "grey15") +
        ggplot2::scale_x_log10(expand = ggplot2::expansion(mult = c(0.05, 0.42))) +
        ggplot2::labs(title = "F  Two-sample MR -> NAFLD (IVW)",
                      subtitle = "p<5e-8, 10Mb clump, F>=10; outcome FinnGen R12 NAFLD",
                      x = "OR (95% CI), log scale", y = NULL) + th
    }
  } else {
    pF <- pF + ggplot2::annotate("text", x = 1, y = 0.5, label = "MR: discussion only (IV insufficient)")
  }
  # G) ST002269 独立血浆代谢组 —— 院内 vs 血浆方向哑铃（第二外部来源，氨基酸轴为主）
  pG <- ggplot2::ggplot() + th + ggplot2::labs(title = "G  Plasma metabolomics (ST002269) direction")
  if (!is.null(mwp) && !is.null(mwp$table) && nrow(mwp$table)) {
    t <- mwp$table[is.finite(mwp$table$plasma_dir_NAFLDvsHealthy) &
                     is.finite(mwp$table$hospital_dir), ]
    if (nrow(t)) {
      t$lab <- prty(sub("^U_", "", t$hospital_metabolite))
      t <- t[order(t$plasma_dir_NAFLDvsHealthy), ]
      t$concord <- factor(ifelse(t$same_direction == 1, "Concordant", "Discordant"),
                          levels = c("Concordant", "Discordant"))
      pG <- ggplot2::ggplot(t, ggplot2::aes(y = reorder(lab, plasma_dir_NAFLDvsHealthy))) +
        ggplot2::geom_vline(xintercept = 0, linetype = 2, colour = "grey55") +
        ggplot2::geom_segment(ggplot2::aes(x = hospital_dir, xend = plasma_dir_NAFLDvsHealthy,
                                           yend = reorder(lab, plasma_dir_NAFLDvsHealthy),
                                           colour = concord),
                              linewidth = 1.1, alpha = 0.75,
                              arrow = grid::arrow(length = grid::unit(0.12, "cm"))) +
        ggplot2::geom_point(ggplot2::aes(x = hospital_dir), shape = 16, size = 2.2, colour = "grey35") +
        ggplot2::geom_point(ggplot2::aes(x = plasma_dir_NAFLDvsHealthy, colour = concord),
                            shape = 17, size = 2.8) +
        ggplot2::scale_colour_manual(values = c(Concordant = "#2166ac", Discordant = "#b2182b"), name = NULL) +
        ggplot2::scale_x_continuous(expand = ggplot2::expansion(mult = c(0.12, 0.12))) +
        ggplot2::labs(title = "G  Plasma metabolomics (ST002269) direction",
                      subtitle = "Dot = hospital urine; triangle = plasma NAFLD vs Healthy; arrow to plasma",
                      x = "log2 fold change", y = NULL) + th
    }
  }
  # 拼图（patchwork；缺则 gridExtra）—— 7 面板：A B C / D E F / G 跨左两列 + 说明
  plots <- list(pA, pB, pC, pD, pE, pF, pG)
  has_g <- !is.null(mwp) && !is.null(mwp$table) && nrow(mwp$table) > 0
  grDevices::pdf(file.path(D$figures, "Figure 7. External bridging.pdf"), width = 14, height = 15)
  if (requireNamespace("patchwork", quietly = TRUE)) {
    comb <- if (has_g)
      (pA | pB | pC) / (pD | pE | pF) / ((pG | patchwork::plot_spacer()) | patchwork::plot_spacer()) +
        patchwork::plot_annotation(theme = ggplot2::theme(plot.margin = ggplot2::margin(6, 6, 6, 6)))
    else
      (pA | pB | pC) / (pD | pE | pF) +
        patchwork::plot_annotation(theme = ggplot2::theme(plot.margin = ggplot2::margin(6, 6, 6, 6)))
    print(comb)
  } else if (requireNamespace("gridExtra", quietly = TRUE)) {
    gridExtra::grid.arrange(grobs = plots[if (has_g) seq_len(7) else seq_len(6)], ncol = 3)
  }
  grDevices::dev.off()
  log("Figure 7 已生成（ggplot 森林/哑铃/lollipop 重绘）")
}

# 旧 base forest helper 已废弃（保留空壳防外部引用）
.nafld_ext_mr_forest <- function(or, ci_str, lab) invisible(NULL)

# Figure 7 image_information 元信息（走 pub_figure_write_image_md 唯一入口）
.nafld_ext_fig7_meta <- function(cfg, nh, geo, mw, gw, summ, mr = NULL, mwp = NULL,
                                 geo2 = NULL, conv = NULL) {
  n_nhanes <- if (!is.null(nh$table)) nrow(nh$table) else 0L
  n_nh_conc <- if (!is.null(nh$table)) sum(nh$table$same_direction == 1, na.rm = TRUE) else 0L
  n_de <- if (!is.null(geo$de)) sum(geo$de$FDR < 0.05) else 0L
  geo_ov <- if (!is.null(conv) && "repeated_across_sources" %in% names(conv))
    sum(conv$repeated_across_sources, na.rm = TRUE) else
    (if (!is.null(geo$pathway) && "overlap_with_scheme_pathway" %in% names(geo$pathway))
       sum(geo$pathway$overlap_with_scheme_pathway, na.rm = TRUE) else 0L)
  n_geo_cohort <- 1L + if (!is.null(geo2)) length(geo2$detail %||% list(geo2)) else 0L
  n_mw <- if (!is.null(mw$table)) nrow(mw$table) else 0L
  n_mw_conc <- if (!is.null(mw$table)) sum(mw$table$same_direction == 1, na.rm = TRUE) else 0L
  n_gwas <- if (!is.null(gw$table)) nrow(gw$table) else 0L
  mr_ok <- !is.null(mr) && !is.null(mr$table) && any(mr$table$status == "MR estimated")
  mrt <- if (mr_ok) mr$table[mr$table$status == "MR estimated", ] else NULL
  sc_ok <- !is.null(nh$score) && nrow(nh$score)
  sc <- if (sc_ok) nh$score else NULL
  extra_body <- c()
  if (sc_ok) extra_body <- c(extra_body, "",
    sprintf("面板 E（NHANES 传统评分泛化）：FLI/HSI/ZJU/TyG/LAP 对 CAP≥280 表型的 survey 加权 AUC（0.5 虚线为随机线）。本次 AUC 区间 %.3f–%.3f，说明既有评分在美国一般人群仍可判别。",
            min(sc$AUC_weighted, na.rm = TRUE), max(sc$AUC_weighted, na.rm = TRUE)))
  if (mr_ok) extra_body <- c(extra_body, "",
    sprintf("面板 F（两样本 MR → NAFLD）：方案点名暴露（代谢综合征/肝酶等）对 FinnGen R12 NAFLD 的 IVW OR(95%%CI)，log 轴。成功估计 %d 个暴露：%s。",
            nrow(mrt),
            paste(sprintf("%s OR=%.2f(p=%.1g)", mrt$exposure, mrt$IVW_OR, mrt$IVW_p), collapse = ", ")))
  if (!is.null(mwp) && !is.null(mwp$table) && nrow(mwp$table)) {
    extra_body <- c(extra_body, "",
      sprintf("面板 G（ST002269 独立血浆代谢组方向）：儿科 NAFLD 血浆靶向代谢组，与院内尿代谢池 %d 个同名代谢物；点=院内尿 log2FC，三角=血浆 NAFLD vs Healthy log2FC，箭头指向血浆；蓝=方向一致、红=相反。本次 %d/%d 方向一致。作为候选代谢物方向一致性的第二个独立外部来源（不同人群/不同基质，探索性）。",
              nrow(mwp$table), sum(mwp$table$same_direction == 1, na.rm = TRUE), nrow(mwp$table)))
  }
  if (mr_ok) {
    mr_line <- sprintf(
      "GWAS/MR：方案定位=可选探索性遗传支持。已按点名暴露落 GWAS Catalog 位点表（S11, %d 行）并跑两样本 MR（S14）：%s；异质性 I2 与 Egger 截距见表。暴露缺 rsID/跨 build 无法对齐者按方案仅讨论。",
      n_gwas, paste(sprintf("%s IVW OR=%.2f p=%.1g", mrt$exposure, mrt$IVW_OR, mrt$IVW_p), collapse = "; "))
  } else {
    mr_line <- sprintf(
      "GWAS/MR：方案定位=可选探索性遗传支持。本轮落 GWAS Catalog 位点桥接表（S11, %d 行）；暴露工具变量不足/跨 build 无法对齐，按方案 MR 不作主线图、仅讨论。", n_gwas)
  }
  body0 <- c(
    if (mr_ok || sc_ok) "多面板拼图：院内主分析结论（C/M/C+M 方向）与公开数据库的跨源一致性桥接，对应方案模块（六）。"
    else "四面板拼图：院内主分析结论（C/M/C+M 方向）与公开数据库的跨源一致性桥接，对应方案模块（六）。",
    "",
    sprintf(
      "面板 A（NHANES 临床方向）：survey 加权 logistic 标准化 β（NAFLD 表型 = FibroScan CAP≥280 dB/m），横条为各临床变量；蓝=与院内 log2 中位数比方向一致，橙=相反。本次 %d/%d 个变量方向一致。",
      n_nh_conc, n_nhanes),
    "",
    sprintf(
      "面板 B（GEO 肝转录组 GSE130970）：edgeR QL 差异表达 NASH(NAS≥5) vs Control(NAS=0)，FDR<0.05 & |logFC|>1；显著 DE 基因 %d 个（上调/下调见条形）。",
      n_de),
    "",
    sprintf(
      "面板 C（GEO 通路重叠，%d 个独立队列）：院内方案四大通路（脂质代谢/胆汁酸代谢/氨基酸代谢/氧化应激）在各 GEO 差异基因中的命中数——GSE130970 RNA-seq edgeR、GSE48452 微阵列 limma（主对比 Nash vs Control，并对院内 BMI 混杂改跑 BMI-matched Nash vs Healthy obese）、GSE89632 Illumina 阵列 limma（NASH vs simple steatosis）。跨源重复（院内代谢 + ≥1 GEO 队列同时成立）的通路 %d/4 条。",
      n_geo_cohort, geo_ov),
    "",
    sprintf(
      "面板 D（Metabolomics Workbench ST000917 尿）：该 study 尿部分为脂质组学，仅脂肪酸同类物可与院内尿代谢物映射；方向 = NASH vs Normal 的 log2 中位数比，蓝=与院内一致、橙=相反。本次映射 %d 个、方向一致 %d 个（方案已注明此 study 尿 FDR 偏弱，仅作方向参考）。",
      n_mw, n_mw_conc),
    "",
    sprintf(
      "图上标注（收获）：NHANES 加权一致 %d/%d；GEO DE(FDR<0.05)=%d、方案通路重复=%d/4；MW 尿同类映射=%d、一致=%d；血浆同名代谢物=%d、一致=%d；GWAS Catalog NAFLD/MASLD 关联=%d 行。",
      n_nh_conc, n_nhanes, n_de, geo_ov, n_mw, n_mw_conc,
      if (!is.null(mwp) && !is.null(mwp$table)) nrow(mwp$table) else 0L,
      if (!is.null(mwp) && !is.null(mwp$table)) sum(mwp$table$same_direction == 1, na.rm = TRUE) else 0L,
      n_gwas),
    "", mr_line
  )
  # 面板 E/F 描述插在图上标注之前
  body <- c(body0[1:9], extra_body, body0[10:length(body0)])

  list(
    figure_body_lines = body,
    exposure = "院内共识特征(C/M/C+M)方向",
    outcome = "跨公开数据库方向/通路一致性（含 MR 因果估计）",
    grouping = "External bridge (scheme module 6)",
    databases = "Hospital; NHANES 2017-Mar2020; GEO GSE130970/GSE48452/GSE89632; MW ST000917/ST002269; GWAS Catalog/FinnGen",
    n_total = "院内 n=560 (NAFLD 462 / Normal 98)",
    combined = TRUE
  )
}

# ══════════════════════════════════════════════════════════════════════════
# 主表 Table 7 汇总
# ══════════════════════════════════════════════════════════════════════════
.nafld_ext_summary <- function(cfg, D, nh, geo, mw, gw, log, mwp = NULL) {
  has_pl <- !is.null(mwp) && !is.null(mwp$table) && nrow(mwp$table) > 0
  rows <- data.frame(
    module = c("NHANES clinical", "GEO liver transcriptome", "Metabolomics Workbench urine",
               "Metabolomics Workbench plasma", "GWAS Catalog / MR")[c(1,2,3, if (has_pl) 4, 5)],
    dataset = c("NHANES 2017–Mar2020 (CAP≥280)", "GSE130970 (78 liver RNA-seq)",
                "ST000917 (urine lipidomics)",
                "ST002269 (plasma, pediatric NAFLD)", "GWAS Catalog NAFLD/MASLD; FinnGen NAFLD")[c(1,2,3, if (has_pl) 4, 5)],
    role = c("临床变量跨人群方向一致性", "肝组织通路桥接",
             "尿代谢同类方向（脂质组）",
             "同名代谢物独立血浆方向", "可选探索性遗传支持")[c(1,2,3, if (has_pl) 4, 5)],
    n_tested = c(if (!is.null(nh$table)) nrow(nh$table) else NA_integer_,
                 if (!is.null(geo$de)) sum(geo$de$FDR < 0.05) else NA_integer_,
                 if (!is.null(mw$table)) nrow(mw$table) else NA_integer_,
                 if (has_pl) nrow(mwp$table) else NA_integer_,
                 if (!is.null(gw$table)) nrow(gw$table) else NA_integer_)[c(1,2,3, if (has_pl) 4, 5)],
    concordant = c(if (!is.null(nh$table)) sum(nh$table$same_direction == 1, na.rm = TRUE) else NA_integer_,
                   if (!is.null(geo$pathway))
                     if ("overlap_with_scheme_pathway" %in% names(geo$pathway))
                       sum(geo$pathway$overlap_with_scheme_pathway, na.rm = TRUE)
                     else nrow(geo$pathway)
                   else NA_integer_,
                   if (!is.null(mw$table)) sum(mw$table$same_direction == 1, na.rm = TRUE) else NA_integer_,
                   if (has_pl) sum(mwp$table$same_direction == 1, na.rm = TRUE) else NA_integer_,
                   NA_integer_)[c(1,2,3, if (has_pl) 4, 5)],
    stringsAsFactors = FALSE
  )
  .nafld_ext_sci_write(NULL, file.path(D$tables, "Table 7. External bridging summary.xlsx"),
    "Table 7. External database bridging summary (scheme module 6)", rows,
    footnotes = c(
      "Scheme module 6: NHANES=clinical generalization; GEO=pathway bridge; MW=urine metabolite direction; GWAS/MR=optional exploratory (IV insufficiency → discussion only).",
      "concordant for GEO = number of enriched pathways overlapping the four scheme pathways."))
  rows
}

# ══════════════════════════════════════════════════════════════════════════
block_ml_nafld_external_bridge <- function(ctx, ...) {
  cfg <- ctx$config
  eb <- cfg$external_bridge %||% list()
  if (isFALSE(eb$enable)) { cli::cli_alert_info("external_bridge enable=FALSE，跳过"); return(ctx) }
  root <- cfg$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
  if (file.exists(file.path(root, "R/utils.R"))) source(file.path(root, "R/utils.R"), local = FALSE)
  common <- file.path(root, "Blocks/73_ml_nafld_cm/00ml_nafld_cm_common.R")
  if (file.exists(common)) source(common, local = FALSE)
  geo2f <- file.path(root, "Blocks/73_ml_nafld_cm/09nafld_ext_geo48452.R")
  if (file.exists(geo2f)) source(geo2f, local = FALSE)
  D <- .nafld_ext_dirs(cfg)
  for (p in c(D$work, D$tables, D$figures, D$supp))
    if (!dir.exists(p)) dir.create(p, recursive = TRUE, showWarnings = FALSE)
  logs <- character(0)
  log <- function(msg, lvl = "info") {
    logs <<- c(logs, paste(lvl, msg))
    if (lvl == "warn") cli::cli_alert_warning(msg) else cli::cli_alert_info(msg)
  }

  # 院内方向：优先用已插补数据 / 原始；并补挂尿代谢组列（checkpoint 插补表常被剥列）
  dat <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$mapped
  if (!is.null(dat) && exists(".nafld_cm_load_metabolome", mode = "function")) {
    dat <- tryCatch(.nafld_cm_load_metabolome(cfg, dat), error = function(e) dat)
  }
  hosp_src <- list(data = dat)
  if (is.null(hosp_src$data)) {
    path <- (cfg$data %||% list())$rawdata_path
    if (!is.null(path) && file.exists(path)) {
      e <- new.env(); load(path, envir = e)
      obj <- cfg$data$rawdata_obj %||% "FattyLiver"
      if (exists(obj, envir = e)) {
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
        hosp_src$data <- d0
      }
    }
  }
  hosp <- .nafld_ext_hosp_direction(cfg, hosp_src)

  # 四线
  nh <- tryCatch(.nafld_ext_nhanes(cfg, hosp, D, log), error = function(e) { log(paste("NHANES err:", conditionMessage(e)), "warn"); NULL })
  geo <- tryCatch(.nafld_ext_geo(cfg, D, log), error = function(e) { log(paste("GEO err:", conditionMessage(e)), "warn"); NULL })
  geo2 <- if (exists(".nafld_ext_geo_array", mode = "function"))
    tryCatch(.nafld_ext_geo_array(cfg, D, log),
             error = function(e) { log(paste("GEO-array err:", conditionMessage(e)), "warn"); NULL }) else NULL
  mw <- tryCatch(.nafld_ext_mw(cfg, hosp, D, log), error = function(e) { log(paste("MW err:", conditionMessage(e)), "warn"); NULL })
  mwp <- tryCatch(.nafld_ext_mw_plasma(cfg, hosp, D, log), error = function(e) { log(paste("MW-plasma err:", conditionMessage(e)), "warn"); NULL })
  gw <- tryCatch(.nafld_ext_gwas(cfg, D, log), error = function(e) { log(paste("GWAS err:", conditionMessage(e)), "warn"); NULL })

  # 通路重复出现（院内代谢 + 双 GEO 队列收敛，方案模块六明确要求）
  conv <- tryCatch(.nafld_ext_pathway_convergence(cfg, hosp, geo, D, log, geo2 = geo2),
                   error = function(e) { log(paste("convergence err:", conditionMessage(e)), "warn"); NULL })

  # 真 MR（方案点名暴露→FinnGen NAFLD）；IV/对齐不足者仅讨论
  mr <- tryCatch(.nafld_ext_mr_real(cfg, D, log),
                 error = function(e) { log(paste("MR err:", conditionMessage(e)), "warn"); NULL })
  # MR 备注落盘：成功→摘要结果；失败→讨论占位（保持 mr_note.txt 契约）
  if (is.null(mr)) {
    mr_note <- .nafld_ext_mr_optional(cfg, D, log)
  } else {
    ok <- mr$table[mr$table$status == "MR estimated", , drop = FALSE]
    mr_note <- if (nrow(ok)) paste(
      "MR 已跑（Table S14；07ml_nafld_cm_mr.R base-R 实现，TwoSampleMR 在 R4.6.1 不可装）：",
      paste(sprintf("%s→NAFLD IVW OR=%.2f (%s, p=%.2g)",
                    ok$exposure, ok$IVW_OR, ok$IVW_CI, ok$IVW_p), collapse = "; "),
      "| 未估计暴露（无 rsID/IV 不足）按方案仅讨论，见 mr_results.csv status 列"
    ) else "MR 已尝试但无暴露成功估计；详见 mr_results.csv（按方案仅讨论）"
    writeLines(mr_note, file.path(D$work, "mr_note.txt"))
  }

   # 图 + 汇总表
  .nafld_ext_fig7(cfg, D, nh, geo, mw, mr, log, mwp = mwp, geo2 = geo2)
  summ <- .nafld_ext_summary(cfg, D, nh, geo, mw, gw, log, mwp = mwp)

  # GEO DE 主表 → S9（先写，供下面统一拷贝）
  if (!is.null(geo$de)) {
    de_tab <- utils::head(data.frame(entrez = rownames(geo$de), geo$de), 3000)
    symb <- file.path(D$work, "geo_entrez_symbol.csv")
    if (file.exists(symb)) {
      sm <- utils::read.csv(symb); de_tab$symbol <- sm$symbol[match(de_tab$entrez, sm$entrez)]
    }
    .nafld_ext_sci_write(NULL, file.path(D$tables, "Table S9. GEO DE genes and pathway overlap.xlsx"),
      "Table S9. GSE130970 DE genes (NASH vs Control) and pathway overlap", de_tab,
      footnotes = c(
        "edgeR QL: NASH (NAS≥5) vs Control (NAS=0). FDR<0.05 & |logFC|>1.",
        if (!is.null(geo$pathway)) sprintf("Pathway enrichment via %s.", geo$method) else "Pathway enrichment unavailable."))
  }

  # 拷贝主图/表进 supplement + summary_result（Figure 7 / Table 7 属主文）
  for (f in c("Figure 7. External bridging.pdf")) {
    s <- file.path(D$figures, f); if (file.exists(s)) file.copy(s, file.path(D$supp, f), overwrite = TRUE)
  }
  sum_tab <- file.path(D$study, "summary_result", "table")
  sum_fig <- file.path(D$study, "summary_result", "figure")
  dir.create(sum_tab, recursive = TRUE, showWarnings = FALSE)
  dir.create(sum_fig, recursive = TRUE, showWarnings = FALSE)
  for (f in c("Figure 7. External bridging.pdf")) {
    s <- file.path(D$figures, f); if (file.exists(s)) file.copy(s, file.path(sum_fig, f), overwrite = TRUE)
  }
  for (f in list.files(D$tables, pattern = "^Table (7|S8|S9|S10|S11|S12|S13|S14)\\.", full.names = TRUE)) {
    file.copy(f, file.path(D$supp, basename(f)), overwrite = TRUE)
    # 主文仅 Figure7/Table7；S 系列留 supplement
    if (grepl("^Table 7\\.", basename(f))) file.copy(f, file.path(sum_tab, basename(f)), overwrite = TRUE)
  }

  # 四目录导出：课题 Figures/ 与 summary_result/figure 都要含 Figure 7
  ext_meta <- .nafld_ext_fig7_meta(cfg, nh, geo, mw, gw, summ, mr = mr, mwp = mwp,
                                   geo2 = geo2, conv = conv)
  if (file.exists(file.path(root, "R/pub_figure_export.R"))) {
    source(file.path(root, "R/pub_figure_export.R"), local = FALSE)
    # 先正常导出（不带全局 meta，避免覆盖 Figures 1–6 的 image_information）
    if (exists("pub_figure_ensure_formats", mode = "function")) {
      tryCatch(pub_figure_ensure_formats(D$figures, config = cfg), error = function(e)
        log(paste("export:", conditionMessage(e)), "warn"))
      pdf_sub <- file.path(sum_fig, "pdf")
      if (dir.exists(pdf_sub)) {
        for (pf in list.files(pdf_sub, pattern = "\\.pdf$", full.names = TRUE)) {
          file.copy(pf, file.path(sum_fig, basename(pf)), overwrite = FALSE)
        }
      }
      tryCatch(pub_figure_ensure_formats(sum_fig, config = cfg), error = function(e)
        log(paste("export summary:", conditionMessage(e)), "warn"))
    }
    # 再用唯一写出入口覆盖 Figure 7 的 image_information（详细两段 + 图面标注）
    if (exists("pub_figure_write_image_md", mode = "function")) {
      for (imdir in c(file.path(D$figures, "image_information"),
                      file.path(sum_fig, "image_information"))) {
        dir.create(imdir, recursive = TRUE, showWarnings = FALSE)
        tryCatch(pub_figure_write_image_md(
          file.path(imdir, "Figure 7. External bridging.md"),
          "Figure 7. External bridging", meta = ext_meta, raster_ok = TRUE),
          error = function(e) log(paste("fig7 md:", conditionMessage(e)), "warn"))
      }
    }
  }

  writeLines(logs, file.path(D$work, "external_bridge_log.txt"))
  ctx$results$nafld_external_bridge <- list(
    nhanes = nh$table, nhanes_score = nh$score, geo = geo$de, geo_pathway = geo$pathway,
    mw = mw$table, mw_plasma = mwp$table, gwas = gw$table, pathway_convergence = conv,
    mr = mr$table, mr_note = mr_note, summary = summ,
    figure7 = file.path(D$figures, "Figure 7. External bridging.pdf")
  )
  cli::cli_alert_success("外部桥接完成：Figure 7 + Table 7 + S8–S14（NHANES/GEO/MW/GWAS + 真 MR）")
  ctx
}

.nafld_ext_mr_optional <- function(cfg, D, log) {
  root <- .nafld_ext_root(cfg)
  mr_cfg <- file.path(root, "Mendelian", "config_mr_paths.R")
  note <- "MR 未执行（仅方案讨论用）"
  if (!file.exists(mr_cfg)) {
    writeLines(c(note, "config_mr_paths.R 缺失"), file.path(D$work, "mr_note.txt"))
    return(note)
  }
  pe <- new.env(); tryCatch(source(mr_cfg, local = pe), error = function(e) NULL)
  fmp <- get("fatty_mr_paths", envir = pe, inherits = FALSE)
  if (is.character(fmp$gwas_exposure_path) && length(fmp$gwas_exposure_path) == 1 &&
      nzchar(fmp$gwas_exposure_path) && file.exists(fmp$gwas_exposure_path)) {
    has_pkg <- requireNamespace("TwoSampleMR", quietly = TRUE)
    if (!has_pkg) {
      note <- "暴露 GWAS 已就位，但 TwoSampleMR 未安装 → MR 仅在讨论/后续 Windows R 补跑"
    } else {
      note <- "暴露 GWAS 就位且有 TwoSampleMR → 可跑；本轮仅登记，不强制出图"
    }
  } else {
    note <- "暴露 GWAS 汇总统计未指定 → 按方案 MR 作可选探索，不作主线图（IV 不足/仅讨论）"
  }
  writeLines(c(
    note,
    paste("exposure:", fmp$exposure_name %||% "NA"),
    paste("gwas_exposure_path:", fmp$gwas_exposure_path %||% "NA"),
    paste("outcome dir:", fmp$outcome_dir_lib),
    "方案：GWAS Catalog 检索 NAFLD/MASLD；工具变量不足则不做主图。"
  ), file.path(D$work, "mr_note.txt"))
  log(note)
  note
}

if (exists("register_block", mode = "function")) {
  register_block(
    "ml_nafld_external_bridge",
    block_ml_nafld_external_bridge,
    "NAFLD 外部数据库桥接（NHANES/GEO/MW/GWAS，方案模块六）"
  )
}
