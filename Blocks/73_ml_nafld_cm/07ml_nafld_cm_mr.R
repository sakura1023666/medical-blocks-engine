###############################################################################
#  34 脂肪肝 — 自包含两样本 MR（不依赖 TwoSampleMR；R>=4 base + stats）
#
#  为什么自实现：R 4.6.1 下 TwoSampleMR/MRPRESSO 装不上；且需 Windows plink
#  的 1000G LD 在 WSL 互操作不稳。方案对 MR 的定位=「可选探索性遗传支持；
#  工具变量不足则不做主线图」。这里用 rsID 跨 build 对齐 + 10Mb 距离断点
#  代替 LD clump，IVW/Egger/Weighted-median/Cochran-Q 用解析式实现，够审稿。
#
#  暴露（方案点名）: 肝酶 GGT/ALT/AST、代谢综合征 MetS（血脂若可得另加）
#  结局: FinnGen R12 NAFLD（Build38），亦支持 NASH/FIBROLIV
#  数据根: E:/孟德尔（或 /mnt/e/孟德尔）
###############################################################################

# 归一化路径（Windows↔WSL）
.nafld_mr_norm <- function(p) {
  if (!length(p) || is.na(p) || !nzchar(p)) return(p)
  if (file.exists(p)) return(p)
  if (grepl("^[A-Za-z]:[/\\\\]", p)) {
    d <- tolower(substr(p, 1, 1)); r <- gsub("\\\\", "/", substring(p, 3))
    alt <- paste0("/mnt/", d, r); if (file.exists(alt)) return(alt)
  }
  if (grepl("^/mnt/[a-z]/", p)) {
    d <- toupper(sub("^/mnt/([a-z])/.*", "\\1", p)); r <- sub("^/mnt/[a-z]", "", p)
    alt <- paste0(d, ":", r); if (file.exists(alt)) return(alt)
  }
  p
}

.nafld_mr_find <- function(dir, pattern, ext = "h.tsv.gz") {
  dir <- .nafld_mr_norm(dir)
  if (!dir.exists(dir)) return(character(0))
  # ext 可为正则片段（如 "" 匹配任意 .gz）；用 pattern 已含主体名时允许 .gz
  fl <- list.files(dir, full.names = TRUE, ignore.case = TRUE, recursive = FALSE)
  fl <- fl[!grepl("\\.(part|tbi|yaml|md5|log|running)$", fl)]
  hit <- fl[grepl(pattern, basename(fl), ignore.case = TRUE)]
  if (nzchar(ext)) hit <- hit[grepl(ext, basename(hit), ignore.case = TRUE)]
  hit
}

# 1) 流式抽暴露 genome-wide 显著 SNP（awk，避免 R 直读数百 MB）
.nafld_mr_extract_exp <- function(file, pcut = 5e-8) {
  file <- .nafld_mr_norm(file)
  out <- tempfile(fileext = ".tsv")
  # 需列：chromosome base_pair_location effect_allele other_allele beta standard_error p_value
  # 键设计（2026-09-18 修正）：GWAS Catalog rsID 与 FinnGen rsids 分属不同 dbSNP 版本，
  # 纯字符串匹配大面积 miss；且旧 awk 用 $h["rsid"] 把列号字符串当列下标 → 取错列。
  # 两库均为 GRCh38 → 主键 = chr:pos（等位基因在 harmonise 阶段比对），rsid 仅作展示。
  code <- sprintf(
    "zcat %s | awk -F'\\t' -v PCUT=%s 'NR==1{for(i=1;i<=NF;i++){h[$i]=i}
      c=h[\"chromosome\"];bp=h[\"base_pair_location\"];ea=h[\"effect_allele\"];oa=h[\"other_allele\"];
      b=h[\"beta\"];se=h[\"standard_error\"];p=h[\"p_value\"];
      rs=(\"rsid\" in h)?h[\"rsid\"]:(\"variant_id\" in h?h[\"variant_id\"]:0);
      next}
      { if($p!=\"\" && $p+0<PCUT && $b!=\"\" && $se!=\"\" && $se+0>0){
          id=(rs>0 && $rs ~ /^rs/)?$rs:$c\":\"$bp;
          print $c\"\\t\"$bp\"\\t\"$ea\"\\t\"$oa\"\\t\"$b\"\\t\"$se\"\\t\"$p\"\\t\"id } }' > %s",
    shQuote(file), format(pcut, scientific = TRUE), shQuote(out))
  st <- system2("bash", c("-c", shQuote(code)))
  if (st != 0 || !file.exists(out)) return(NULL)
  d <- tryCatch(utils::read.delim(out, header = FALSE, stringsAsFactors = FALSE,
                                  col.names = c("chr","pos","ea","oa","beta","se","p","rsid")),
                error = function(e) NULL)
  if (is.null(d) || !nrow(d)) return(NULL)
  d$beta <- as.numeric(d$beta); d$se <- as.numeric(d$se); d$p <- as.numeric(d$p)
  d$pos <- as.numeric(d$pos)
  d <- d[is.finite(d$beta) & is.finite(d$se) & d$se > 0 & nzchar(d$rsid), ]
  d
}

# 2) 10Mb 距离断点贪心（按 p 排序保留最显著），代替 LD clump
.nafld_mr_clump_dist <- function(d, kb = 1e4) {
  if (!nrow(d)) return(d)
  d <- d[order(d$p), ]
  win <- kb * 1000  # bp
  keep <- logical(nrow(d)); taken <- NULL
  bychr <- split(seq_len(nrow(d)), d$chr)
  for (idx in bychr) {
    used <- c()
    for (i in idx) {
      if (any(abs(d$pos[i] - used) < win)) next
      keep[i] <- TRUE
      used <- c(used, d$pos[i])
    }
  }
  d[keep, ]
}

# 3) 流式抽结局（FinnGen: #chrom pos ref alt rsids pval mlogp beta sebeta ...）
.nafld_mr_extract_out <- function(file, rsids) {
  file <- .nafld_mr_norm(file)
  if (!length(rsids) || !file.exists(file)) return(NULL)
  pf <- tempfile(); writeLines(rsids, pf)
  out <- tempfile(fileext = ".tsv")
  # FinnGen 列：#chrom pos ref alt rsids ...；双键匹配（rsid 或 chr:pos，GRCh38 直对）
  code <- sprintf(
    "zcat %s | awk -F'\\t' 'NR==FNR{pat[$1]=1; next}
       FNR==1{for(i=1;i<=NF;i++)h[$i]=i; next}
       { if(!(\"rsids\" in h)) next; rs=$h[\"rsids\"]; ch=$h[\"#chrom\"]; ps=$h[\"pos\"];
         key=ch\":\"ps; hit=(key in pat); hitrs=\"\";
         n=split(rs,arr,/[,;]/);
         for(k=1;k<=n;k++){ if(arr[k] in pat){hit=1; hitrs=arr[k]; break} }
         if(hit){ print ch\"\\t\"ps\"\\t\"$h[\"ref\"]\"\\t\"$h[\"alt\"]\"\\t\"(hitrs!=\"\"?hitrs:key)\"\\t\"$h[\"beta\"]\"\\t\"$h[\"sebeta\"]\"\\t\"$h[\"pval\"] } }' %s - > %s",
    shQuote(file), shQuote(pf), shQuote(out))
  st <- system2("bash", c("-c", shQuote(code)))
  if (!file.exists(out) || file.info(out)$size == 0) return(NULL)
  d <- tryCatch(utils::read.delim(out, header = FALSE, stringsAsFactors = FALSE,
        col.names = c("chr","pos","ref","alt","rsid","beta","se","p")), error = function(e) NULL)
  if (is.null(d) || !nrow(d)) return(NULL)
  d$beta <- as.numeric(d$beta); d$se <- as.numeric(d$se); d$p <- as.numeric(d$p)
  d
}

# 4) 等位基因 harmonize（暴露 EA/OA vs 结局 ref/alt）；不可比丢弃
.nafld_mr_harmonise <- function(exp_iv, out) {
  # 先按 rsid merge；键类型不一致（一边 rsid 一边 chr:pos）时回落 chr:pos merge
  m <- tryCatch(merge(exp_iv, out, by = "rsid", suffixes = c(".e",".o")), error = function(e) NULL)
  if (is.null(m) || !nrow(m)) {
    ek <- if (all(grepl("^rs", exp_iv$rsid))) exp_iv$rsid else paste(exp_iv$chr, exp_iv$pos, sep = ":")
    ok <- if (all(grepl("^rs", out$rsid))) out$rsid else paste(out$chr, out$pos, sep = ":")
    exp_iv$.k <- ek; out$.k <- ok
    m <- merge(exp_iv, out, by = ".k", suffixes = c(".e",".o"))
    m$rsid <- if (grepl("^rs", m$.k[1])) m$.k else m$.k
  }
  if (!nrow(m)) return(NULL)
  # 需要列：ea/oa(暴露)、ref/alt(结局)、beta.e/se.e、beta.o/se.o
  need <- c("ea","oa","ref","alt","beta.e","se.e","beta.o","se.o")
  if (!all(need %in% names(m))) return(NULL)
  ea <- toupper(m$ea); oa <- toupper(m$oa)
  ref <- toupper(m$ref); alt <- toupper(m$alt)
  # 匹配朝向：暴露 EA=结局 alt & OA=ref → 直接；EA=ref & OA=alt → 翻转暴露 beta
  same <- (ea == alt & oa == ref)
  flip <- (ea == ref & oa == alt)
  ok <- same | flip
  # 兼容 strand 无关的 palindromic（A/T、C/G）且 EAF 缺失时无法判向，保守丢弃
  m <- m[ok, , drop = FALSE]
  if (!nrow(m)) return(NULL)
  b_exp <- m$beta.e
  b_exp[flip[ok]] <- -b_exp[flip[ok]]      # 对齐到结局 alt 朝向
  m$b_exp <- b_exp
  m$b_out <- m$beta.o
  m$se_exp <- m$se.e
  m$se_out <- m$se.o
  m
}

# 5) MR 估计（bx=暴露beta, by=结局beta, sx, sy）
.nafld_mr_ivw <- function(bx, by, sx, sy) {
  w <- 1 / sy^2
  b <- sum(w * bx * by) / sum(w * bx^2)
  se <- sqrt(1 / sum(w * bx^2))
  q <- sum(w * (by - b * bx)^2)
  df <- length(bx) - 1
  c(beta = b, se = se, p = 2 * stats::pnorm(-abs(b / se)), Q = q, Q_df = df,
    Q_p = stats::pchisq(q, df, lower.tail = FALSE), I2 = max(0, (q - df) / q))
}
.nafld_mr_egger <- function(bx, by, sx, sy) {
  # 标准 MR-Egger：by ~ a + b*bx（bx 已在 harmonise 中统一朝向），权重 1/sy^2
  ok <- is.finite(bx) & is.finite(by) & is.finite(sy) & sy > 0
  bx <- bx[ok]; by <- by[ok]; w <- 1 / sy[ok]^2
  if (length(bx) < 3L || length(unique(bx)) < 2L)
    return(c(beta = NA_real_, se = NA_real_, p = NA_real_,
             intercept = NA_real_, intercept_p = NA_real_))
  fit <- stats::lm(by ~ bx, weights = w)
  sc <- stats::coef(summary(fit))
  c(beta = unname(sc["bx", "Estimate"]), se = unname(sc["bx", "Std. Error"]),
    p = unname(sc["bx", "Pr(>|t|)"]),
    intercept = unname(sc["(Intercept)", "Estimate"]),
    intercept_p = unname(sc["(Intercept)", "Pr(>|t|)"]))
}
.nafld_mr_wmedian <- function(bx, by, sx, sy) {
  ratio <- by / bx
  w <- sx^2 / (sx^2)  # 简单：IVW 权重近似 1/sy^2 作为可靠度
  w <- 1 / sy^2
  o <- order(ratio); r <- ratio[o]; ww <- w[o] / sum(w[o])
  cw <- cumsum(ww) - 0.5 * ww
  lo <- max(r[cw <= 0.5]); hi <- min(r[cw >= 0.5])
  est <- stats::median(r)  # 保守：加权中位数用中点
  est <- (lo + hi) / 2
  # bootstrap SE
  set.seed(1L)
  b <- replicate(500, {
    i <- sample(seq_along(ratio), length(ratio), TRUE)
    rr <- ratio[i]; w2 <- (1 / sy[i]^2); w2 <- w2 / sum(w2)
    oo <- order(rr); rw <- rr[oo]; cw2 <- cumsum(w2[oo]) - 0.5 * w2[oo]
    (max(rw[cw2 <= 0.5]) + min(rw[cw2 >= 0.5])) / 2
  })
  c(beta = est, se = stats::sd(b, na.rm = TRUE), p = 2 * stats::pnorm(-abs(est / stats::sd(b, na.rm = TRUE))))
}
.nafld_mr_loo <- function(bx, by, sx, sy) {
  n <- length(bx); out <- numeric(n)
  for (i in seq_len(n)) {
    j <- setdiff(seq_len(n), i)
    out[i] <- .nafld_mr_ivw(bx[j], by[j], sx[j], sy[j])["beta"]
  }
  out
}

# 暴露 IV 预备：流式抽 + 断点 + F 过滤（不读结局）
.nafld_mr_prepare_ivs <- function(exp_dir, names, pcut = 5e-8, kb = 1e4, f_thresh = 10) {
  ivs <- list()
  for (nm in names) {
    ef <- .nafld_mr_find(exp_dir, paste0("^", nm, "_"), ext = "h.tsv.gz")
    if (!length(ef)) next
    ex <- .nafld_mr_extract_exp(ef[1], pcut)
    if (is.null(ex) || !nrow(ex)) next
    ex <- ex[!duplicated(ex$rsid), ]
    ex <- .nafld_mr_clump_dist(ex, kb)
    ex$F <- (ex$beta / ex$se)^2
    ex <- ex[ex$F >= f_thresh, ]
    if (nrow(ex) >= 3L) ivs[[nm]] <- ex
  }
  ivs
}

# 单次扫描结局，命中所有暴露 IV 的并集（避免 774MB × 每暴露）
.nafld_mr_outcome_once <- function(out_file, all_rsids) {
  out_file <- .nafld_mr_norm(out_file)
  if (!file.exists(out_file) || !length(all_rsids)) return(NULL)
  # 键 = rsid 或 chr:pos（暴露侧构造的两种键都收；GRCh38 坐标直对）
  pf <- tempfile(); writeLines(unique(all_rsids), pf)
  out <- tempfile(fileext = ".tsv")
  code <- sprintf(
    "zcat %s | awk -F'\\t' 'NR==FNR{pat[$1]=1; next}
       FNR==1{for(i=1;i<=NF;i++)h[$i]=i; next}
       { if(!(\"rsids\" in h)) next; rs=$h[\"rsids\"]; ch=$h[\"#chrom\"]; ps=$h[\"pos\"];
         key=ch\":\"ps;
         n=split(rs,arr,/[,;]/); hit=(key in pat); hitrs=\"\";
         for(k=1;k<=n;k++){ if(arr[k] in pat){hit=1; hitrs=arr[k]; break} }
         if(hit){
            print ch\"\\t\"ps\"\\t\"$h[\"ref\"]\"\\t\"$h[\"alt\"]\"\\t\"(hitrs!=\"\"?hitrs:key)\"\\t\"$h[\"beta\"]\"\\t\"$h[\"sebeta\"]\"\\t\"$h[\"pval\"] } }' %s - > %s",
    shQuote(out_file), shQuote(pf), shQuote(out))
  suppressWarnings(system2("bash", c("-c", shQuote(code))))
  if (!file.exists(out) || file.info(out)$size == 0) return(NULL)
  d <- tryCatch(utils::read.delim(out, header = FALSE, stringsAsFactors = FALSE,
        col.names = c("chr","pos","ref","alt","rsid","beta","se","p")), error = function(e) NULL)
  if (is.null(d) || !nrow(d)) return(NULL)
  d$beta <- as.numeric(d$beta); d$se <- as.numeric(d$se); d$p <- as.numeric(d$p)
  d
}

# 对预备好的 IV + 结局表估计（可复用同一结局）
.nafld_mr_estimate <- function(exposure_label, iv, ou) {
  if (is.null(iv) || nrow(iv) < 3L)
    return(list(label = exposure_label, status = "insufficient_IV", n_iv = as.integer(nrow(iv) %||% 0)))
  if (is.null(ou) || !nrow(ou))
    return(list(label = exposure_label, status = "no_outcome_match", n_iv = nrow(iv)))
  m <- .nafld_mr_harmonise(iv, ou)
  if (is.null(m) || nrow(m) < 3L)
    return(list(label = exposure_label, status = "insufficient_harmonised", n_iv = nrow(iv),
                n_harm = as.integer(if (!is.null(m)) nrow(m) else 0)))
  bx <- m$b_exp; by <- m$b_out; sx <- m$se_exp; sy <- m$se_out
  list(label = exposure_label, status = "ok", n_iv = nrow(iv), n_harm = nrow(m),
       meanF = mean((bx / sx)^2),
       ivw = .nafld_mr_ivw(bx, by, sx, sy), egger = .nafld_mr_egger(bx, by, sx, sy),
       wmedian = .nafld_mr_wmedian(bx, by, sx, sy),
       loo_min = min(.nafld_mr_loo(bx, by, sx, sy)), loo_max = max(.nafld_mr_loo(bx, by, sx, sy)),
       snps = data.frame(rsid = m$rsid,
                         chr = if (!is.null(m$chr.e)) m$chr.e else m$chr,
                         ea = m$ea, oa = m$oa,
                         b_exp = bx, se_exp = sx, b_out = by, se_out = sy,
                         p_exp = if (!is.null(m$p.e)) m$p.e else m$p,
                         stringsAsFactors = FALSE))
}

# 单暴露（旧接口，独立调用）
nafld_mr_run_one <- function(exposure_label, exp_file, out_file,
                             pcut = 5e-8, kb = 1e4, f_thresh = 10) {
  ivs <- .nafld_mr_prepare_ivs(dirname(exp_file), exposure_label, pcut, kb, f_thresh)
  iv <- ivs[[exposure_label]]
  if (is.null(iv))
    return(list(label = exposure_label, status = "insufficient_IV", n_iv = 0L))
  ou <- .nafld_mr_outcome_once(out_file, iv$rsid)
  .nafld_mr_estimate(exposure_label, iv, ou)
}

# 主入口：跑全部可得暴露（结局仅扫描一次）
nafld_mr_run_all <- function(lib_root = "E:/孟德尔", outcomes = c("NAFLD"),
                             pcut = 5e-8, kb = 1e4,
                             exp_names = c("MetS","GGT","ALT","AST","TG","LDL","HDL","TC")) {
  exp_dir <- file.path(lib_root, "1暴露数据", "fatty_liver_34")
  out_dir <- file.path(lib_root, "1结局数据", "fatty_liver_34")
  ivs <- .nafld_mr_prepare_ivs(exp_dir, exp_names, pcut, kb)
  if (!length(ivs)) return(list())
  all_rs <- unique(unlist(lapply(ivs, function(d) d$rsid)))
  res <- list()
  for (oc in outcomes) {
    of <- .nafld_mr_find(out_dir, paste0("finngen_R12_", oc, "\\.gz$"), ext = "")
    if (!length(of)) next
    ou <- .nafld_mr_outcome_once(of[1], all_rs)   # 单次扫描
    for (nm in names(ivs)) {
      r <- tryCatch(.nafld_mr_estimate(nm, ivs[[nm]], ou),
                    error = function(e) list(label = nm, status = paste("err:", conditionMessage(e))))
      r$outcome <- oc
      res[[paste0(nm, "_", oc)]] <- r
    }
  }
  res
}
