###############################################################################
#  crm_mr_literature — Han 2025 文献级两样本 MR（本地 GWAS + plink clump +
#                      TwoSampleMR + MRPRESSO）
#
#  不修改 Blocks/57_*。本块替代 smoke 级 mr_snp_screen→…→mr_sensitivity 链，
#  使用原文暴露 GCST90018977.h + FinnGen R9 结局（可自动/预下载）。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_packages = TwoSampleMR, MendelianRandomization, MRPRESSO, data.table,
#                     ieugwasr（本地 plink clump，不依赖 OpenGWAS JWT）
#  require_files    = dual_incidence_mr$gwas_exposure_path（尿酸 GWAS .tsv.gz）
#                     + 各结局 FinnGen .gz（见 outcome_map）
#  require_plink    = dual_incidence_mr$plink_bin + ld_bfile（1000G EUR）
#
#  crm_mr_literature = list(
#    pause_enable = TRUE,
#    pause_on_download_fail = TRUE,
#    pause_on_few_ivs = TRUE,
#    pause_min_ivs = 10L,
#    outcome_key = NULL   # 由 worker 写入：CVD / CKD / Diabetes；NULL=跑全部
#  ),
#
#  dual_incidence_mr = list(
#    gwas_exposure_path = "E:/01block/01Block-new-Final/Data/GCST90018977.h.tsv.gz",
#    exposure_n = 343836L,          # Han 文 UKB n；写入 format_data
#    exposure_name = "SUA",
#    pval_threshold = 5e-8,
#    clump_kb = 10000L,
#    clump_r2 = 0.001,
#    mr_f_stat_threshold = 10,
#    mr_max_snps = NULL,            # NULL=不截断；论文约 148–268 IVs
#    plink_bin = "D:/easyMR/MRmyy_refer_file/plink/plink.exe",
#    ld_bfile = "D:/easyMR/MRmyy_refer_file/1000G_EUR_Phase3_plink/1000G.EUR.QC",
#    outcome_cache_dir = "E:/01block/01Block-new-Final/Data/crm_han2025_r9",
#    outcome_map = list(
#      CVD = list(file="finngen_R9_FG_CVD.gz", ...),
#      CKD = list(file="finngen_R9_N14_CHRONKIDNEYDIS.gz", ...),
#      Diabetes = list(file="finngen_R9_T2D_WIDE.gz", ...)
#    ),
#    presso_nb = 1000L,
#    auto_download_outcomes = FALSE
#  )
###############################################################################

.crm70lit_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.crm70lit_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L)
  else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "crm_mr_literature", reason = reason,
    suggestion = suggestion, data_snapshot = snap
  )
  stop("PAUSE_FOR_USER_DECISION: ", reason, " / ", suggestion, call. = FALSE)
}

.crm70lit_win_path <- function(p) {
  p <- as.character(p %||% "")[1L]
  if (!nzchar(p)) return(NA_character_)
  if (grepl("^/mnt/[a-z]/", p)) {
    drive <- toupper(sub("^/mnt/([a-zA-Z])/.*", "\\1", p))
    rest <- sub("^/mnt/[a-zA-Z]", "", p)
    p <- paste0(drive, ":", gsub("/", "\\\\", rest))
  }
  p
}

# Windows R 用 E:/；WSL 侧偶发探测用 /mnt/e/
.crm70lit_resolve_existing <- function(p) {
  p <- as.character(p %||% "")[1L]
  if (!nzchar(p)) return(NA_character_)
  if (file.exists(p)) return(p)
  if (grepl("^[A-Za-z]:[/\\\\]", p)) {
    drive <- tolower(substr(p, 1L, 1L))
    rest <- gsub("\\\\", "/", substring(p, 3L))
    alt <- paste0("/mnt/", drive, rest)
    if (file.exists(alt)) return(alt)
  }
  if (grepl("^/mnt/[a-zA-Z]/", p)) {
    wp <- .crm70lit_win_path(p)
    if (!is.na(wp) && file.exists(wp)) return(wp)
  }
  p
}

.crm70lit_ensure_outcome <- function(meta, cache_dir, auto_dl = TRUE) {
  cache_dir <- as.character(cache_dir)[1L]
  if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  dest <- file.path(cache_dir, meta$file)
  if (file.exists(dest) && file.info(dest)$size > 1e7) return(dest)
  if (!isTRUE(auto_dl)) stop("结局文件缺失且 auto_download_outcomes=FALSE: ", dest, call. = FALSE)
  url <- meta$url
  if (is.null(url) || !nzchar(url)) stop("无下载 URL: ", meta$file, call. = FALSE)
  cli::cli_alert_info("下载 FinnGen 结局: {basename(dest)}")
  # Windows R 下用 download.file；WSL 路径时 dest 仍可写
  utils::download.file(url, destfile = dest, mode = "wb", quiet = FALSE)
  if (!file.exists(dest) || file.info(dest)$size < 1e7)
    stop("下载失败或文件过小: ", dest, call. = FALSE)
  dest
}

.crm70lit_read_exposure <- function(path, n_exp, name = "SUA") {
  if (!requireNamespace("data.table", quietly = TRUE))
    stop("请安装 data.table", call. = FALSE)
  if (!file.exists(path)) stop("暴露 GWAS 不存在: ", path, call. = FALSE)
  cli::cli_alert_info("读取暴露 GWAS: {basename(path)}")
  dt <- data.table::fread(path, showProgress = TRUE)
  nms <- names(dt)
  # 优先 rsid / hm_rsid（GWAS Catalog 部分文件 variant_id 全为 NA）
  snp <- if ("hm_rsid" %in% nms && any(grepl("^rs", as.character(dt$hm_rsid)))) {
    "hm_rsid"
  } else if ("rsid" %in% nms && any(grepl("^rs", as.character(dt$rsid)))) {
    "rsid"
  } else if ("variant_id" %in% nms) {
    "variant_id"
  } else if ("hm_rsid" %in% nms) {
    "hm_rsid"
  } else if ("rsid" %in% nms) {
    "rsid"
  } else {
    NA
  }
  beta <- if ("hm_beta" %in% nms && any(!is.na(dt$hm_beta))) "hm_beta" else if ("beta" %in% nms) "beta" else NA
  se <- if ("standard_error" %in% nms) "standard_error" else if ("se" %in% nms) "se" else NA
  ea <- if ("hm_effect_allele" %in% nms) "hm_effect_allele" else if ("effect_allele" %in% nms) "effect_allele" else NA
  oa <- if ("hm_other_allele" %in% nms) "hm_other_allele" else if ("other_allele" %in% nms) "other_allele" else NA
  pval <- if ("p_value" %in% nms) "p_value" else if ("pval" %in% nms) "pval" else NA
  eaf <- if ("hm_effect_allele_frequency" %in% nms) "hm_effect_allele_frequency" else if ("effect_allele_frequency" %in% nms) "effect_allele_frequency" else NA
  chr <- if ("hm_chrom" %in% nms) "hm_chrom" else if ("chromosome" %in% nms) "chromosome" else NA
  pos <- if ("hm_pos" %in% nms) "hm_pos" else if ("base_pair_location" %in% nms) "base_pair_location" else NA
  need <- c(snp = snp, beta = beta, se = se, ea = ea, oa = oa, pval = pval)
  if (anyNA(need)) stop("暴露列映射失败: ", paste(names(need)[is.na(need)], collapse = ","), call. = FALSE)

  out <- data.frame(
    SNP = as.character(dt[[snp]]),
    beta.exposure = as.numeric(dt[[beta]]),
    se.exposure = as.numeric(dt[[se]]),
    effect_allele.exposure = toupper(as.character(dt[[ea]])),
    other_allele.exposure = toupper(as.character(dt[[oa]])),
    pval.exposure = as.numeric(dt[[pval]]),
    stringsAsFactors = FALSE
  )
  if (!is.na(eaf)) out$eaf.exposure <- as.numeric(dt[[eaf]])
  if (!is.na(chr)) out$chr.exposure <- as.character(dt[[chr]])
  if (!is.na(pos)) out$pos.exposure <- as.numeric(dt[[pos]])
  out$id.exposure <- name
  out$exposure <- name
  out$samplesize.exposure <- as.integer(n_exp %||% NA_integer_)
  # drop missing / non-rs
  out <- out[!is.na(out$SNP) & grepl("^rs", out$SNP) &
               !is.na(out$beta.exposure) & !is.na(out$se.exposure) &
               !is.na(out$pval.exposure) & out$se.exposure > 0, , drop = FALSE]
  out
}

.crm70lit_read_finngen <- function(path, id, ncase, ncontrol) {
  if (!requireNamespace("data.table", quietly = TRUE))
    stop("请安装 data.table", call. = FALSE)
  cli::cli_alert_info("读取结局 GWAS: {basename(path)}")
  dt <- data.table::fread(path, showProgress = TRUE)
  nms <- names(dt)
  # FinnGen R12 common columns
  snp <- if ("rsids" %in% nms) "rsids" else if ("rsid" %in% nms) "rsid" else NA
  beta <- if ("beta" %in% nms) "beta" else NA
  se <- if ("sebeta" %in% nms) "sebeta" else if ("se" %in% nms) "se" else NA
  # alt = effect allele in FinnGen
  ea <- if ("alt" %in% nms) "alt" else if ("effect_allele" %in% nms) "effect_allele" else NA
  oa <- if ("ref" %in% nms) "ref" else if ("other_allele" %in% nms) "other_allele" else NA
  pval <- if ("pval" %in% nms) "pval" else if ("p_value" %in% nms) "p_value" else NA
  eaf <- if ("af_alt" %in% nms) "af_alt" else if ("af" %in% nms) "af" else NA
  chr <- if ("#chrom" %in% nms) "#chrom" else if ("chrom" %in% nms) "chrom" else NA
  pos <- if ("pos" %in% nms) "pos" else NA
  need <- c(snp = snp, beta = beta, se = se, ea = ea, oa = oa, pval = pval)
  if (anyNA(need)) stop("FinnGen 列映射失败: ", paste(names(need)[is.na(need)], collapse = ","),
                        " 实际列=", paste(utils::head(nms, 20), collapse = ","), call. = FALSE)

  # rsids can be "rs1,rs2" — take first
  snp_raw <- as.character(dt[[snp]])
  snp_first <- sub(",.*$", "", snp_raw)
  out <- data.frame(
    SNP = snp_first,
    beta.outcome = as.numeric(dt[[beta]]),
    se.outcome = as.numeric(dt[[se]]),
    effect_allele.outcome = toupper(as.character(dt[[ea]])),
    other_allele.outcome = toupper(as.character(dt[[oa]])),
    pval.outcome = as.numeric(dt[[pval]]),
    stringsAsFactors = FALSE
  )
  if (!is.na(eaf)) out$eaf.outcome <- as.numeric(dt[[eaf]])
  if (!is.na(chr)) out$chr.outcome <- as.character(dt[[chr]])
  if (!is.na(pos)) out$pos.outcome <- as.numeric(dt[[pos]])
  out$id.outcome <- id
  out$outcome <- id
  out$ncase.outcome <- as.integer(ncase %||% NA_integer_)
  out$ncontrol.outcome <- as.integer(ncontrol %||% NA_integer_)
  out$samplesize.outcome <- suppressWarnings(as.integer(ncase) + as.integer(ncontrol))
  out <- out[!is.na(out$SNP) & grepl("^rs", out$SNP) &
               !is.na(out$beta.outcome) & !is.na(out$se.outcome) &
               out$se.outcome > 0, , drop = FALSE]
  # unique SNP
  out <- out[!duplicated(out$SNP), , drop = FALSE]
  out
}

.crm70lit_clump <- function(exp_df, pval_thr, kb, r2, plink_bin, bfile) {
  if (!requireNamespace("ieugwasr", quietly = TRUE))
    stop("请安装 ieugwasr", call. = FALSE)
  cand <- exp_df[!is.na(exp_df$pval.exposure) & exp_df$pval.exposure < pval_thr, , drop = FALSE]
  if (!nrow(cand)) stop("暴露在 p<", pval_thr, " 下无 SNP", call. = FALSE)
  cli::cli_alert_info("Clump 候选 SNP: {nrow(cand)} (p<{pval_thr})")
  dat <- data.frame(
    rsid = cand$SNP,
    pval = cand$pval.exposure,
    id = cand$id.exposure[1L],
    stringsAsFactors = FALSE
  )
  plink_bin <- .crm70lit_win_path(plink_bin)
  bfile <- .crm70lit_win_path(bfile)
  if (!file.exists(plink_bin)) stop("plink 不存在: ", plink_bin, call. = FALSE)
  # bfile is prefix; .bed must exist for chr1 at least
  if (!file.exists(paste0(bfile, ".bed")) && !file.exists(paste0(bfile, ".1.bed")) &&
      !file.exists(paste0(bfile, "1.bed"))) {
    # 1000G.EUR.QC is per-chr: 1000G.EUR.QC.1.bed — ieugwasr expects single bfile;
    # use merged EUR folder if available, else clump chromosome-wise fallback via first available
    # Try without chr suffix pattern used by MRmyy: 1000G.EUR.QC.{1..22}
    # ieugwasr ld_clump with per-chr: pass bfile as path to one merged — check EUR/
    stop("LD bfile 未找到 .bed: ", bfile,
         "（若为分染色体 1000G.EUR.QC.N，请在 config 设 ld_bfile_chr_template）", call. = FALSE)
  }
  clumped <- ieugwasr::ld_clump(
    dat = dat,
    clump_kb = as.integer(kb),
    clump_r2 = as.numeric(r2),
    clump_p = as.numeric(pval_thr),
    plink_bin = plink_bin,
    bfile = bfile
  )
  keep <- unique(as.character(clumped$rsid))
  cand[cand$SNP %in% keep, , drop = FALSE]
}

.crm70lit_clump_per_chr <- function(exp_df, pval_thr, kb, r2, plink_bin, bfile_template) {
  # bfile_template like ".../1000G.EUR.QC" → files 1000G.EUR.QC.{1..22}.bed
  if (!requireNamespace("ieugwasr", quietly = TRUE))
    stop("请安装 ieugwasr", call. = FALSE)
  cand <- exp_df[!is.na(exp_df$pval.exposure) & exp_df$pval.exposure < pval_thr, , drop = FALSE]
  if (!nrow(cand)) stop("暴露在 p<", pval_thr, " 下无 SNP", call. = FALSE)
  if (!"chr.exposure" %in% names(cand))
    stop("分染色体 clump 需要 chr.exposure 列", call. = FALSE)
  plink_bin <- .crm70lit_win_path(plink_bin)
  kept <- character(0)
  for (ch in sort(unique(as.character(cand$chr.exposure)))) {
    ch_num <- gsub("^chr", "", ch, ignore.case = TRUE)
    if (!ch_num %in% as.character(1:22)) next
    bf <- paste0(bfile_template, ".", ch_num)
    bf_w <- .crm70lit_win_path(bf)
    if (!file.exists(paste0(bf_w, ".bed")) && !file.exists(paste0(bf, ".bed"))) {
      cli::cli_alert_warning("缺少 LD chr{ch_num}: {bf}")
      next
    }
    sub <- cand[as.character(cand$chr.exposure) == ch, , drop = FALSE]
    dat <- data.frame(rsid = sub$SNP, pval = sub$pval.exposure, id = "SUA", stringsAsFactors = FALSE)
    cl <- tryCatch(
      ieugwasr::ld_clump(dat, clump_kb = as.integer(kb), clump_r2 = as.numeric(r2),
                         clump_p = as.numeric(pval_thr), plink_bin = plink_bin,
                         bfile = if (file.exists(paste0(bf_w, ".bed"))) bf_w else bf),
      error = function(e) {
        cli::cli_alert_warning("chr{ch_num} clump 失败: {conditionMessage(e)}")
        NULL
      }
    )
    if (!is.null(cl) && nrow(cl)) kept <- c(kept, as.character(cl$rsid))
  }
  kept <- unique(kept)
  if (!length(kept)) stop("分染色体 clump 后 0 SNP", call. = FALSE)
  cand[cand$SNP %in% kept, , drop = FALSE]
}

.crm70lit_run_one_outcome <- function(exp_iv, out_df, oc, presso_nb, out_dir) {
  if (!requireNamespace("TwoSampleMR", quietly = TRUE))
    stop("请安装 TwoSampleMR", call. = FALSE)
  # harmonise
  harm <- TwoSampleMR::harmonise_data(exposure_dat = exp_iv, outcome_dat = out_df, action = 2)
  harm <- harm[harm$mr_keep %in% TRUE, , drop = FALSE]
  if (nrow(harm) < 3L) {
    return(list(ok = FALSE, n = nrow(harm), note = "harmonised SNP < 3"))
  }
  # F filter
  if (!"eaf.exposure" %in% names(harm)) harm$eaf.exposure <- 0.5
  harm$F <- (harm$beta.exposure / harm$se.exposure)^2
  harm <- harm[is.finite(harm$F) & harm$F > 10, , drop = FALSE]
  if (nrow(harm) < 3L) {
    return(list(ok = FALSE, n = nrow(harm), note = "F>10 后 SNP < 3"))
  }

  utils::write.csv(harm, file.path(out_dir, sprintf("Table_MR_Harmonised_%s.csv", oc)), row.names = FALSE)

  mr_res <- TwoSampleMR::mr(harm, method_list = c(
    "mr_ivw", "mr_egger_regression", "mr_weighted_median",
    "mr_weighted_mode", "mr_simple_mode"
  ))
  het <- tryCatch(TwoSampleMR::mr_heterogeneity(harm), error = function(e) NULL)
  pleio <- tryCatch(TwoSampleMR::mr_pleiotropy_test(harm), error = function(e) NULL)
  singlesnp <- tryCatch(TwoSampleMR::mr_singlesnp(harm), error = function(e) NULL)
  loo <- tryCatch(TwoSampleMR::mr_leaveoneout(harm), error = function(e) NULL)

  # MR-PRESSO
  presso_tab <- NULL
  if (requireNamespace("MRPRESSO", quietly = TRUE) && nrow(harm) >= 4L) {
    presso_tab <- tryCatch({
      set.seed(1234)
      pr <- MRPRESSO::mr_presso(
        BetaOutcome = "beta.outcome", BetaExposure = "beta.exposure",
        SdOutcome = "se.outcome", SdExposure = "se.exposure",
        OUTLIERtest = TRUE, DISTORTIONtest = TRUE,
        data = harm, NbDistribution = as.integer(presso_nb %||% 1000L),
        SignifThreshold = 0.05
      )
      glob <- as.data.frame(pr$`MR-PRESSO results`$`Global Test`)
      main <- as.data.frame(pr$`Main MR results`)
      data.frame(
        outcome = oc,
        method = c("MR-PRESSO_raw", "MR-PRESSO_outlier_corrected"),
        b = main$`Causal Estimate`,
        se = main$Sd,
        pval = main$`P-value`,
        global_p = glob$Pvalue[1],
        n_snps = nrow(harm),
        stringsAsFactors = FALSE
      )
    }, error = function(e) {
      cli::cli_alert_warning("MR-PRESSO 失败 ({oc}): {conditionMessage(e)}")
      NULL
    })
  }

  # plots via TwoSampleMR → Figures/MR（与 Tables/MR 同级，勿落到 Tables/Figures）
  out_root <- dirname(dirname(normalizePath(out_dir, winslash = "/", mustWork = FALSE)))
  # out_dir = <unit>/Tables/MR → out_root = <unit>
  fig_dir <- file.path(out_root, "Figures", "MR")
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  # 保留 TwoSampleMR 默认单 SNP 图样式；仅按行数拉高 + 缩小 y 轴字，避免标签重叠
  .crm70lit_snp_panel_h <- function(n_row) {
    n <- max(1L, as.integer(n_row)[1L])
    # ~0.085 inch/行：紧密但仍可辨认 rsID
    min(40, max(8, 1.0 + 0.085 * n))
  }
  .crm70lit_thin_y <- function(p) {
    if (is.null(p) || !inherits(p, "ggplot")) return(p)
    p + ggplot2::theme(
      axis.text.y = ggplot2::element_text(size = 3.2, margin = ggplot2::margin(t = 0, b = 0)),
      axis.text.x = ggplot2::element_text(size = 9),
      plot.margin = ggplot2::margin(3, 6, 3, 3)
    )
  }
  tryCatch({
    p1 <- TwoSampleMR::mr_scatter_plot(mr_res, harm)[[1]]
    ggplot2::ggsave(file.path(fig_dir, sprintf("Figure_S4_MR_scatter_%s.pdf", oc)), p1, width = 6, height = 5)
  }, error = function(e) NULL)
  tryCatch({
    if (!is.null(singlesnp)) {
      p2 <- .crm70lit_thin_y(TwoSampleMR::mr_forest_plot(singlesnp)[[1]])
      ggplot2::ggsave(
        file.path(fig_dir, sprintf("Figure_S5_MR_forest_%s.pdf", oc)),
        p2, width = 7, height = .crm70lit_snp_panel_h(nrow(singlesnp)),
        limitsize = FALSE, device = grDevices::cairo_pdf
      )
    }
  }, error = function(e) NULL)
  tryCatch({
    if (!is.null(singlesnp)) {
      p3 <- TwoSampleMR::mr_funnel_plot(singlesnp)[[1]]
      ggplot2::ggsave(file.path(fig_dir, sprintf("Figure_S6_MR_funnel_%s.pdf", oc)), p3, width = 6, height = 5)
    }
  }, error = function(e) NULL)
  tryCatch({
    if (!is.null(loo)) {
      p4 <- .crm70lit_thin_y(TwoSampleMR::mr_leaveoneout_plot(loo)[[1]])
      ggplot2::ggsave(
        file.path(fig_dir, sprintf("Figure_S7_MR_loo_%s.pdf", oc)),
        p4, width = 7, height = .crm70lit_snp_panel_h(nrow(loo)),
        limitsize = FALSE, device = grDevices::cairo_pdf
      )
    }
  }, error = function(e) NULL)

  list(
    ok = TRUE, n = nrow(harm), harm = harm, mr_res = mr_res,
    het = het, pleio = pleio, presso = presso_tab,
    singlesnp = singlesnp, loo = loo
  )
}

block_crm_mr_literature <- function(ctx, ...) {
  bl <- ctx$config$dual_incidence_mr %||% list()
  bl_cfg <- ctx$config$crm_mr_literature %||% list()
  root <- ctx$config$project$root %||% getwd()
  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "MR")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  exp_path_raw <- bl$gwas_exposure_path %||% bl$gwas_exposure %||% ""
  exp_path <- .crm70lit_resolve_existing(exp_path_raw)
  if (!nzchar(exp_path) || !file.exists(exp_path)) {
    .crm70lit_pause(ctx, "暴露 GWAS 路径无效",
                    "设置 dual_incidence_mr$gwas_exposure_path 指向 E:/孟德尔/1暴露数据/...EFO_0004587.h.tsv.gz")
  }

  pthr <- as.numeric(bl$pval_threshold %||% 5e-8)[1L]
  kb <- as.integer(bl$clump_kb %||% 10000L)[1L]
  r2 <- as.numeric(bl$clump_r2 %||% 0.001)[1L]
  plink_bin <- bl$plink_bin %||% "D:/easyMR/MRmyy_refer_file/plink/plink.exe"
  bfile <- bl$ld_bfile %||% "D:/easyMR/MRmyy_refer_file/1000G_EUR_Phase3_plink/1000G.EUR.QC"
  use_chr <- isTRUE(bl$ld_clump_per_chr %||% TRUE)

  iv_cache <- bl$iv_cache_path %||% file.path(
    dirname(exp_path), "crm_han2025_iv",
    sprintf("SUA_IVs_p%g_kb%d_r%g.rds", pthr, kb, r2)
  )
  iv_cache <- .crm70lit_resolve_existing(iv_cache)
  reuse_iv <- isTRUE(bl$reuse_iv_cache %||% TRUE)
  n_genome <- NA_integer_; n_p <- NA_integer_

  if (reuse_iv && file.exists(iv_cache) && file.info(iv_cache)$size > 1000) {
    cli::cli_alert_info("复用 IV 缓存: {iv_cache}")
    exp_iv <- readRDS(iv_cache)
    if (!is.data.frame(exp_iv) || !"SNP" %in% names(exp_iv) || nrow(exp_iv) < 3L)
      stop("IV 缓存无效: ", iv_cache, call. = FALSE)
  } else {
    # 1) read + genome-wide filter
    exp_all <- .crm70lit_read_exposure(exp_path, bl$exposure_n %||% 343836L, bl$exposure_name %||% "SUA")
    n_genome <- nrow(exp_all)
    n_p <- sum(exp_all$pval.exposure < pthr, na.rm = TRUE)

    # 2) clump
    exp_iv <- if (use_chr) {
      .crm70lit_clump_per_chr(exp_all, pthr, kb, r2, plink_bin, bfile)
    } else {
      .crm70lit_clump(exp_all, pthr, kb, r2, plink_bin, bfile)
    }
    # F filter + top N
    exp_iv$F <- (exp_iv$beta.exposure / exp_iv$se.exposure)^2
    exp_iv <- exp_iv[is.finite(exp_iv$F) & exp_iv$F > (bl$mr_f_stat_threshold %||% 10), , drop = FALSE]
    if ("eaf.exposure" %in% names(exp_iv)) {
      exp_iv <- exp_iv[is.na(exp_iv$eaf.exposure) |
                         (exp_iv$eaf.exposure > 0.01 & exp_iv$eaf.exposure < 0.99), , drop = FALSE]
    }
    exp_iv <- exp_iv[order(-exp_iv$F), , drop = FALSE]
    max_n <- bl$mr_max_snps
    if (!is.null(max_n) && is.finite(as.numeric(max_n)[1L]) && as.integer(max_n)[1L] > 0L) {
      exp_iv <- utils::head(exp_iv, as.integer(max_n)[1L])
    }

    dir.create(dirname(iv_cache), recursive = TRUE, showWarnings = FALSE)
    # 原子写：避免并行 worker 读到半成品
    tmp_rds <- paste0(iv_cache, ".tmp_", Sys.getpid())
    saveRDS(exp_iv, tmp_rds)
    file.rename(tmp_rds, iv_cache)
    cli::cli_alert_success("IV 已缓存: {iv_cache} (n={nrow(exp_iv)})")
  }

  utils::write.csv(
    data.frame(SNP = exp_iv$SNP, beta = exp_iv$beta.exposure, se = exp_iv$se.exposure,
               effect_allele = exp_iv$effect_allele.exposure,
               other_allele = exp_iv$other_allele.exposure,
               eaf = if ("eaf.exposure" %in% names(exp_iv)) exp_iv$eaf.exposure else NA_real_,
               pval = exp_iv$pval.exposure, F = exp_iv$F,
               trait = "SUA", stringsAsFactors = FALSE),
    file.path(out_dir, "Table_MR_SNP_Screened.csv"), row.names = FALSE
  )
  utils::write.csv(
    data.frame(step = c("genome_wide_rs", "p_threshold", "after_clump_F", "final_IV"),
               n_snps = c(n_genome, n_p, nrow(exp_iv), nrow(exp_iv)),
               stringsAsFactors = FALSE),
    file.path(out_dir, "Table_MR_SNP_Screen_Log.csv"), row.names = FALSE
  )

  if (nrow(exp_iv) < as.integer(bl_cfg$pause_min_ivs %||% 10L) &&
      .crm70lit_should_pause(bl_cfg, "pause_on_few_ivs", TRUE)) {
    .crm70lit_pause(ctx, sprintf("IV 过少 n=%d", nrow(exp_iv)),
                    "检查 pval_threshold / LD 参考 / 暴露文件", exp_iv)
  }
  cli::cli_alert_success("文献级 IV 筛选完成: n={nrow(exp_iv)}")

  # 3) outcomes
  omap <- bl$outcome_map %||% list()
  key <- bl_cfg$outcome_key %||% bl$active_outcome %||% NULL
  if (!is.null(key) && nzchar(as.character(key)[1L])) {
    omap <- omap[names(omap) %in% as.character(key)[1L]]
  }
  if (!length(omap)) stop("outcome_map 为空", call. = FALSE)

  cache_dir <- bl$outcome_cache_dir %||% "E:/孟德尔/1结局数据/crm_han2025"
  auto_dl <- isTRUE(bl$auto_download_outcomes %||% TRUE)
  all_mr <- list(); all_presso <- list(); all_pleio <- list(); all_het <- list()
  notes <- list()

  for (oc in names(omap)) {
    meta <- omap[[oc]]
    opath <- tryCatch(
      .crm70lit_ensure_outcome(meta, cache_dir, auto_dl),
      error = function(e) {
        if (.crm70lit_should_pause(bl_cfg, "pause_on_download_fail", TRUE))
          stop(e)
        cli::cli_alert_warning("{oc}: {conditionMessage(e)}")
        NULL
      }
    )
    if (is.null(opath)) { notes[[oc]] <- "missing_outcome_file"; next }
    out_df <- .crm70lit_read_finngen(opath, oc, meta$ncase, meta$ncontrol)
    # subset outcome to IV SNPs for speed before harmonise (still pass full format to TwoSampleMR)
    out_df <- out_df[out_df$SNP %in% exp_iv$SNP, , drop = FALSE]
    res <- .crm70lit_run_one_outcome(exp_iv, out_df, oc, bl$presso_nb %||% 1000L, out_dir)
    if (!isTRUE(res$ok)) {
      notes[[oc]] <- res$note %||% "failed"
      next
    }
    mr_res <- res$mr_res
    mr_res$outcome_label <- oc
    all_mr[[oc]] <- mr_res
    if (!is.null(res$presso)) all_presso[[oc]] <- res$presso
    if (!is.null(res$pleio)) {
      pl <- res$pleio; pl$outcome_label <- oc; all_pleio[[oc]] <- pl
    }
    if (!is.null(res$het)) {
      ht <- res$het; ht$outcome_label <- oc; all_het[[oc]] <- ht
    }
    cli::cli_alert_success("{oc}: n_IV={res$n} MR methods 完成")
  }

  if (length(all_mr)) {
    tab5 <- do.call(rbind, all_mr)
    utils::write.csv(tab5, file.path(out_dir, "Table_5_MR_Estimates.csv"), row.names = FALSE)
    # also root Tables for pub_align / deliverables
    root_tab <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
    dir.create(root_tab, recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(tab5, file.path(root_tab, "Table_5_MR_Estimates.csv"), row.names = FALSE)
  }
  if (length(all_presso)) {
    utils::write.csv(do.call(rbind, all_presso),
                     file.path(out_dir, "Table_MR_Egger_PRESSO.csv"), row.names = FALSE)
  }
  if (length(all_pleio) || length(all_het)) {
    pl <- if (length(all_pleio)) do.call(rbind, all_pleio) else NULL
    ht <- if (length(all_het)) do.call(rbind, all_het) else NULL
    utils::write.csv(
      if (!is.null(pl) && !is.null(ht)) {
        data.frame(type = c(rep("pleiotropy", nrow(pl)), rep("heterogeneity", nrow(ht))),
                   rbind(
                     data.frame(outcome = pl$outcome_label, method = NA, Q = NA, Q_df = NA, Q_pval = NA,
                                egger_intercept = pl$egger_intercept, se = pl$se, pval = pl$pval),
                     data.frame(outcome = ht$outcome_label, method = ht$method, Q = ht$Q, Q_df = ht$Q_df,
                                Q_pval = ht$Q_pval, egger_intercept = NA, se = NA, pval = NA)
                   ))
      } else if (!is.null(pl)) pl else ht,
      file.path(out_dir, "Table_MR_Pleiotropy_Heterogeneity.csv"), row.names = FALSE
    )
  }
  # sensitivity alias
  if (length(all_mr)) {
    sens <- do.call(rbind, all_mr)
    utils::write.csv(sens, file.path(out_dir, "Table_MR_Sensitivity.csv"), row.names = FALSE)
    utils::write.csv(sens, file.path(out_dir, "Table_MR_IVW_Results.csv"), row.names = FALSE)
  }

  ctx$results$crm_mr_literature <- list(
    n_iv = nrow(exp_iv),
    outcomes = names(all_mr),
    notes = notes,
    output_dir = out_dir
  )
  ctx$results$mr_snp_screen <- list(n_iv = nrow(exp_iv),
                                    screened_path = file.path(out_dir, "Table_MR_SNP_Screened.csv"))
  ctx$results$mr_twosample <- list(table = if (length(all_mr)) do.call(rbind, all_mr) else NULL,
                                   output_dir = out_dir)
  cli::cli_alert_success("crm_mr_literature 完成")
  ctx
}

register_block("crm_mr_literature", block_crm_mr_literature, "文献级两样本 MR")
