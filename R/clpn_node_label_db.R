###############################################################################
#  clpn_node_label_db.R — CLPN / 交叉滞后节点短码 → 出版名映射库
#
#  真源：configs/clpn_node_label_db.csv（可手工增补；本文件内置兜底）。
#  以后图例 / Table S8 只查库，禁止在各 phase 里写死 Condition1、FI 题名。
###############################################################################

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (is.null(a)) b else a
}

clpn_node_label_db_path <- function(root = NULL) {
  if (is.null(root) || !nzchar(as.character(root)[1L])) {
    root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
    if (!nzchar(root) && exists("root", inherits = TRUE)) {
      cand <- get("root", inherits = TRUE)
      if (is.character(cand) && length(cand) && dir.exists(cand[1L]))
        root <- cand[1L]
    }
    if (!nzchar(as.character(root)[1L])) root <- getwd()
  }
  file.path(as.character(root)[1L], "configs", "clpn_node_label_db.csv")
}

#' 内置映射（CSV 缺失或不完整时的兜底；CSV 同 stem 覆盖内置）
clpn_node_label_db_builtin <- function() {
  row <- function(stem, short, display, group, aliases = "") {
    data.frame(
      stem = stem, short_label = short, display_name = display,
      group = group, aliases = aliases, stringsAsFactors = FALSE
    )
  }
  # ── 昼夜综合征 7 成分（本课题 CSV 的 condition1–7；NHANES 源列可核对）──
  circ <- rbind(
    row("condition1", "C1", "Abdominal obesity", "Circadian",
        "qm002;wstval;WSTVAL;BMXWAIST;waist"),
    row("condition2", "C2", "Elevated triglycerides", "Circadian",
        "LBXTR;newtg;trig;BPQ090D"),
    row("condition3", "C3", "Low HDL cholesterol", "Circadian",
        "LBDHDD;newhdl;hdl"),
    row("condition4", "C4", "Elevated blood pressure", "Circadian",
        "BPXSY1;BPQ050A;hemda;HeMDa;sysval;SYSVAL"),
    row("condition5", "C5", "Elevated fasting glucose", "Circadian",
        "LBXGLU;hba1c;DI070;newglu;fglu;hedimdi"),
    row("condition6", "C6", "Short sleep duration", "Circadian",
        "SLD01;da049;heslpe"),
    row("condition7", "C7", "Depression", "Circadian",
        "CES_D10;CES_D8;DPQ020"),
    row("DN", "DN", "Circadian syndrome", "Outcome", "Disease_Group;circadian_disorder"),
    row("met_count", "met", "Circadian component count", "Other", "")
  )
  # ── ELSA CES-D-8（参考图 DN1–DN8）──
  cesd <- rbind(
    row("psceda", "DN1", "Frustrated", "Depression", "CESD1;PScedA"),
    row("pscedb", "DN2", "Futility", "Depression", "CESD2;PScedB"),
    row("pscedc", "DN3", "Sleep", "Depression", "CESD3;PScedC"),
    row("pscedd", "DN4", "Happiness", "Depression", "CESD4;PScedD"),
    row("pscede", "DN5", "Lonely", "Depression", "CESD5;PScedE"),
    row("pscedf", "DN6", "Ability to enjoy life", "Depression", "CESD6;PScedF"),
    row("pscedg", "DN7", "Sad", "Depression", "CESD7;PScedG"),
    row("pscedh", "DN8", "Inability to make progress", "Depression", "CESD8;PScedH")
  )
  # ── 虚弱 FI 条目（髋部 Fig4；short 空 = 作图时按出现顺序编 FI1…）──
  fi <- rbind(
    row("hibpe", "", "Hypertension", "Comorbidity", "hedimbp;hypertension"),
    row("diabe", "", "Diabetes", "Comorbidity", "hedbts;diabetes"),
    row("cancre", "", "Cancer", "Comorbidity", "hedibca;cancer"),
    row("lunge", "", "Chronic lung disease", "Comorbidity", "hediblu;lung_disease"),
    row("psyche", "", "Psychiatric problems", "Comorbidity", "hedibps;spirit"),
    row("memrye", "", "Memory problems", "Comorbidity", "hedibpd;dementia"),
    row("arthre", "", "Arthritis", "Comorbidity", "hedibar;arthritis"),
    row("dressa", "", "Dressing", "ADL", "headldr"),
    row("batha", "", "Bathing", "ADL", "headlba"),
    row("eata", "", "Eating", "ADL", "headlea"),
    row("beda", "", "Getting in/out of bed", "ADL", "headlbe"),
    row("toilta", "", "Using toilet", "ADL", "headlwc"),
    row("mealsa", "", "Preparing meals", "IADL", "headlpr"),
    row("shopa", "", "Shopping", "IADL", "headlsh"),
    row("medsa", "", "Taking medications", "IADL", "headlme"),
    row("moneya", "", "Managing money", "IADL", "headlmo"),
    row("srh", "", "Self-rated health", "Mobility", "hehelf"),
    row("armsa", "", "Reaching arms", "Mobility", "hemobre"),
    row("chaira", "", "Getting up from chair", "Mobility", "hemobch"),
    row("climsa", "", "Climbing stairs", "Mobility", "hemobcs"),
    row("dimea", "", "Picking up a coin", "Mobility", "hemobpi"),
    row("lifta", "", "Lifting heavy objects", "Mobility", "hemobli"),
    row("stoopa", "", "Stooping/kneeling", "Mobility", "hemobst"),
    row("walk100a", "", "Walking 100m", "Mobility", "walk10;walk100;hemobwa"),
    row("glass", "", "Eyesight", "Sensory", "heeye"),
    row("hear", "", "Hearing", "Sensory", "hehear"),
    row("FI", "FI", "Frailty index", "Index", "Frailty;frailty26_total"),
    row("AIP_FI", "AIP-FI", "AIP-frailty index", "Index", "")
  )
  # ── 结局 / 血脂 ──
  outc <- rbind(
    row("Disease01", "D1", "Incident disease", "Outcome", "Sarcopenia;sarcop"),
    row("Triglycerides", "L1", "Triglycerides", "Lipid", "newtg;trig;TG"),
    row("HDL_Cholesterol", "L2", "HDL cholesterol", "Lipid", "newhdl;hdl;HDL")
  )
  # ── 常见复合指标（short = 指标名，图上直接写 TyG / ePWV）──
  idx_pretty <- c(
    ePWV = "Estimated pulse wave velocity",
    TyG = "Triglyceride-glucose index",
    TyG_BMI = "TyG-BMI",
    TyG_WC = "TyG-waist circumference",
    TyG_WHtR = "TyG-WHtR",
    TyG_WWI = "TyG-WWI",
    TyG_ABSI = "TyG-ABSI",
    PHR = "Platelet to HDL ratio",
    HHR = "Hemoglobin to hematocrit ratio",
    UA_CrR = "Uric acid to creatinine ratio",
    NLR = "Neutrophil to lymphocyte ratio",
    PLR = "Platelet to lymphocyte ratio",
    SII = "Systemic immune-inflammation index",
    SIRI = "Systemic inflammation response index",
    AIP = "Atherogenic index of plasma",
    WWI = "Weight-adjusted waist index",
    WHtR = "Waist-to-height ratio",
    ABSI = "A body shape index",
    BRI = "Body roundness index",
    CMI = "Cardiometabolic index",
    VAI = "Visceral adiposity index",
    LAP = "Lipid accumulation product",
    CRI_I = "Castelli risk index I",
    CRI_II = "Castelli risk index II",
    NHHR = "Non-HDL to HDL ratio",
    TG_HDL_C = "Triglyceride to HDL ratio",
    TC_HDL = "Total cholesterol to HDL ratio",
    FIB4 = "Fibrosis-4 index",
    APRI = "AST to platelet ratio index",
    ALBI = "ALBI score",
    PNI = "Prognostic nutritional index",
    EASIX = "Endothelial activation index",
    HOMA_IR = "HOMA-IR",
    SHR = "Stress hyperglycemia ratio",
    UACR = "Urine albumin-creatinine ratio",
    RFM = "Relative fat mass",
    GNRI = "Geriatric nutritional risk index",
    METSIR = "METS-IR",
    AISI = "Aggregate index of systemic inflammation",
    MHR = "Monocyte to HDL ratio",
    CALLY = "C-reactive protein-albumin-lymphocyte index",
    CTI = "C-reactive protein-triglyceride-glucose index",
    HALP = "Hemoglobin-albumin-lymphocyte-platelet index",
    GLR = "Glucose to lymphocyte ratio",
    ANLR = "Albumin to NLR ratio",
    NLPR = "Neutrophil-lymphocyte-platelet ratio",
    WPR = "WBC to platelet ratio",
    RC = "Remnant cholesterol",
    NHDL = "Non-HDL cholesterol",
    AC = "Atherogenic coefficient",
    LCI = "Lipoprotein combine index",
    CHG = "Cholesterol-HDL-glucose index",
    HGI = "Hemoglobin glycation index",
    GPR = "Glucose to potassium ratio",
    De_Ritis = "De Ritis ratio (AST/ALT)",
    AGR = "Albumin to globulin ratio",
    BAR = "BUN to albumin ratio",
    LAR = "LD to albumin ratio",
    log2LAR = "log2 LD/albumin",
    CAR = "Creatinine to albumin ratio",
    BUN_Cr = "BUN to creatinine ratio",
    RAR = "RDW to albumin ratio",
    HRR = "Hemoglobin to RDW ratio",
    SOSM = "Serum osmolality",
    AIP_BMI = "AIP-BMI",
    AIP_WC = "AIP-waist circumference",
    AIP_WHtR = "AIP-WHtR",
    TCBI = "Triglyceride-cholesterol-BMI index",
    WTI = "Waist-triglyceride index",
    MCMI = "Metabolic composite index",
    eGDR = "Estimated glucose disposal rate",
    ZJU = "ZJU index",
    NMLR = "Neutrophil-monocyte to lymphocyte ratio",
    CLR = "C-reactive protein to lymphocyte ratio",
    hs_CRP_HDL_C = "hs-CRP to HDL ratio",
    RCII = "Remnant cholesterol inflammatory index",
    lnRCII = "log remnant cholesterol inflammatory index",
    LHR = "Lymphocyte to HDL ratio",
    HbA1c_HDL_C = "HbA1c to HDL ratio",
    ALT_HDL_C = "ALT to HDL ratio",
    UHR = "Uric acid to HDL ratio",
    AFR = "Fibrinogen to albumin ratio",
    MCH = "Mean corpuscular hemoglobin",
    MCV = "Mean corpuscular volume",
    MCHC = "Mean corpuscular hemoglobin concentration",
    RDW_CV = "Red cell distribution width",
    ACAG = "Albumin-corrected anion gap",
    ALI = "Advanced lung cancer inflammation index",
    sdLDL_C = "Small dense LDL cholesterol",
    FSI = "Fatty liver score",
    METS_VF = "METS-VF",
    CONUT_score = "CONUT score",
    HSI = "Hepatic steatosis index",
    NFS = "NAFLD fibrosis score",
    BMI = "Body mass index"
  )
  idx <- do.call(rbind, lapply(names(idx_pretty), function(nm) {
    row(nm, nm, unname(idx_pretty[[nm]]), "Index", "")
  }))
  db <- rbind(circ, cesd, fi, outc, idx)
  db
}

.clpn_db_cache <- NULL

clpn_node_label_db <- function(root = NULL, refresh = FALSE) {
  if (!isTRUE(refresh) && is.data.frame(.clpn_db_cache)) return(.clpn_db_cache)
  base <- clpn_node_label_db_builtin()
  fp <- clpn_node_label_db_path(root)
  if (file.exists(fp)) {
    ext <- tryCatch(
      utils::read.csv(fp, stringsAsFactors = FALSE, check.names = FALSE, comment.char = ""),
      error = function(e) NULL
    )
    if (is.data.frame(ext) && "stem" %in% names(ext) && nrow(ext)) {
      need <- c("stem", "short_label", "display_name", "group", "aliases")
      for (nm in need) if (!nm %in% names(ext)) ext[[nm]] <- ""
      ext <- ext[, need, drop = FALSE]
      ext$stem <- trimws(as.character(ext$stem))
      ext <- ext[nzchar(ext$stem), , drop = FALSE]
      # CSV 覆盖同 stem
      base <- base[!base$stem %in% ext$stem, , drop = FALSE]
      base <- rbind(ext, base)
    }
  }
  rownames(base) <- NULL
  .clpn_db_cache <<- base
  base
}

clpn_node_label_db_write <- function(root = NULL, db = NULL) {
  db <- db %||% clpn_node_label_db_builtin()
  fp <- clpn_node_label_db_path(root)
  dir.create(dirname(fp), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(db, fp, row.names = FALSE, fileEncoding = "UTF-8")
  .clpn_db_cache <<- NULL
  fp
}

.clpn_alias_index <- function(db) {
  mp <- setNames(db$stem, db$stem)
  for (i in seq_len(nrow(db))) {
    als <- unlist(strsplit(as.character(db$aliases[[i]] %||% ""), ";", fixed = TRUE))
    als <- trimws(als)
    als <- als[nzchar(als)]
    if (length(als)) mp[als] <- db$stem[[i]]
  }
  mp
}

clpn_canonical_stem <- function(x, root = NULL) {
  x <- as.character(x)
  stem <- sub("^T[12]_", "", x)
  db <- clpn_node_label_db(root)
  idx <- .clpn_alias_index(db)
  hit <- unname(idx[stem])
  ifelse(is.na(hit) | !nzchar(hit), stem, hit)
}

#' 出版长名（图例 / Table S8）
clpn_node_display <- function(x, root = NULL, fallback = TRUE) {
  x <- as.character(x)
  wave <- ifelse(grepl("^T[12]_", x), substr(x, 1, 2), "")
  stem <- sub("^T[12]_", "", x)
  can <- clpn_canonical_stem(stem, root)
  db <- clpn_node_label_db(root)
  lab <- db$display_name[match(can, db$stem)]
  miss <- is.na(lab) | !nzchar(lab)
  if (any(miss) && isTRUE(fallback)) {
    lab[miss] <- gsub("_", " ", can[miss], fixed = TRUE)
    lab[miss] <- paste0(toupper(substr(lab[miss], 1, 1)), substring(lab[miss], 2))
  }
  lab
}

#' 图上短码：C1 / ePWV / DN1 / FI（空 short 时由作图端编序号）
clpn_node_short <- function(x, root = NULL) {
  can <- clpn_canonical_stem(x, root)
  db <- clpn_node_label_db(root)
  sh <- db$short_label[match(can, db$stem)]
  sh[is.na(sh)] <- ""
  sh
}

clpn_node_group <- function(x, root = NULL) {
  can <- clpn_canonical_stem(x, root)
  db <- clpn_node_label_db(root)
  g <- db$group[match(can, db$stem)]
  g[is.na(g) | !nzchar(g)] <- "Other"
  g
}

#' 与旧 `cross_lagged_fi_item_label` 兼容
clpn_node_label <- function(x, with_wave = TRUE, root = NULL) {
  x <- as.character(x)
  wave <- ifelse(grepl("^T[12]_", x), substr(x, 1, 2), "")
  lab <- clpn_node_display(x, root = root, fallback = TRUE)
  if (isTRUE(with_wave)) {
    ifelse(nzchar(wave), paste0(wave, "_", lab), lab)
  } else lab
}
