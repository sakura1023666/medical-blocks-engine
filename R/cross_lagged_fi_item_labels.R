###############################################################################
#  R/cross_lagged_fi_item_labels.R
#  虚弱指数（FI）条目短码 → 出版英文名（对齐原文 CLPN / HRS-style FI 字典）
###############################################################################

#' FI / CLPN 条目短码映射（不带 T1_/T2_ 前缀）
cross_lagged_fi_item_label_map <- function() {
  c(
    # 疾病 / 认知 / 感觉
    hibpe = "Hypertension",
    diabe = "Diabetes",
    cancre = "Cancer",
    lunge = "Chronic lung disease",
    psyche = "Psychiatric problems",
    memrye = "Memory problems",
    arthre = "Arthritis",
    glass = "Eyesight",
    hear = "Hearing",
    # ADL
    dressa = "Dressing",
    batha = "Bathing",
    eata = "Eating",
    beda = "Getting in/out of bed",
    toilta = "Using toilet",
    # IADL
    mealsa = "Preparing meals",
    shopa = "Shopping",
    medsa = "Taking medications",
    moneya = "Managing money",
    # 躯体功能
    srh = "Self-rated health",
    armsa = "Reaching arms",
    chaira = "Getting up from chair",
    climsa = "Climbing stairs",
    dimea = "Picking up a coin",
    lifta = "Lifting heavy objects",
    stoopa = "Stooping/kneeling",
    walk100a = "Walking 100m",
    walk10 = "Walking 100m",
    walk100 = "Walking 100m",
    # 血脂（原文网络曾纳入）
    Triglycerides = "Triglycerides",
    triglycerides = "Triglycerides",
    newtg = "Triglycerides",
    HDL_Cholesterol = "HDL cholesterol",
    hdl_cholesterol = "HDL cholesterol",
    newhdl = "HDL cholesterol",
    # 结局 / 汇总（若进入网络）
    Sarcopenia = "Sarcopenia",
    sarcop = "Sarcopenia",
    Disease01 = "Hip fracture",
    Disease_Group = "Hip fracture",
    FI = "Frailty Index",
    Frailty = "Frailty",
    frailty26_total = "Frailty (26-item total)",
    AIP = "AIP",
    AIP_FI = "AIP-FI",
    # ELSA 常见短码（若未先 harmonize）
    hedimbp = "Hypertension",
    hedbts = "Diabetes",
    hedibca = "Cancer",
    hedibar = "Arthritis",
    hediblu = "Chronic lung disease",
    hedibps = "Psychiatric problems",
    hedibpd = "Memory problems",
    headldr = "Dressing",
    headlba = "Bathing",
    headlea = "Eating",
    headlbe = "Getting in/out of bed",
    headlwc = "Using toilet",
    headlpr = "Preparing meals",
    headlsh = "Shopping",
    headlmo = "Managing money",
    headlme = "Taking medications",
    hemobwa = "Walking",
    hemobch = "Getting up from chair",
    hemobcs = "Climbing stairs",
    hemobst = "Stooping/kneeling",
    hemobre = "Reaching arms",
    hemobli = "Lifting heavy objects",
    hemobpi = "Picking up a coin",
    heeye = "Eyesight",
    hehear = "Hearing",
    hehelf = "Self-rated health"
  )
}

#' 将 stem 或 T1_/T2_ 列名映射为出版标签
#' @param x 字符向量
#' @param with_wave 若 TRUE 且输入带 T1_/T2_，输出保留 `T1_Hypertension` 形式
cross_lagged_fi_item_label <- function(x, with_wave = TRUE) {
  if (!exists("clpn_node_label", mode = "function")) {
    dbp <- file.path("R", "clpn_node_label_db.R")
    if (file.exists(dbp)) source(dbp, local = FALSE)
  }
  if (exists("clpn_node_label", mode = "function")) {
    return(clpn_node_label(x, with_wave = with_wave))
  }
  x <- as.character(x)
  mp <- cross_lagged_fi_item_label_map()
  vapply(x, function(nm) {
    wave <- ""
    stem <- nm
    if (grepl("^T[12]_", nm)) {
      wave <- substr(nm, 1, 2) # T1 / T2
      stem <- sub("^T[12]_", "", nm)
    }
    lab <- unname(mp[stem])
    if (is.na(lab) || !nzchar(lab)) {
      lab <- gsub("_", " ", stem, fixed = TRUE)
      lab <- paste0(toupper(substr(lab, 1, 1)), substring(lab, 2))
    }
    if (isTRUE(with_wave) && nzchar(wave)) paste0(wave, "_", lab) else lab
  }, character(1), USE.NAMES = FALSE)
}

#' 原文 CHARLS 风格 FI 条目优先顺序（用于 CLPN 节点选取）
cross_lagged_fi_item_stems_preferred <- function() {
  c(
    "hibpe", "diabe", "cancre", "lunge", "psyche", "memrye", "arthre",
    "dressa", "batha", "eata", "beda", "toilta",
    "mealsa", "shopa", "medsa", "moneya",
    "srh", "armsa", "chaira", "climsa", "dimea", "lifta", "stoopa", "walk100a",
    "glass", "hear",
    "Triglycerides", "HDL_Cholesterol", "newtg", "newhdl"
  )
}

#' ELSA / HRS 虚弱短码 → CHARLS 规范 stem（读入时统一，避免跨波大小写/别名导致整列 NA）
cross_lagged_fi_item_rename_to_canonical <- function(nms) {
  nms <- as.character(nms)
  low <- tolower(nms)
  elsa <- c(
    hedimbp = "hibpe", hedbts = "diabe", hedibca = "cancre", hedibar = "arthre",
    hediblu = "lunge", hedibps = "psyche", hedibpd = "memrye",
    headldr = "dressa", headlba = "batha", headlea = "eata", headlbe = "beda",
    headlwc = "toilta", headlpr = "mealsa", headlsh = "shopa", headlmo = "moneya",
    headlme = "medsa",
    hemobwa = "walk100a", hemobch = "chaira", hemobcs = "climsa", hemobst = "stoopa",
    hemobre = "armsa", hemobli = "lifta", hemobpi = "dimea",
    heeye = "glass", hehear = "hear", hehelf = "srh",
    trig = "Triglycerides", hdl = "HDL_Cholesterol",
    hypertension = "hibpe", diabetes = "diabe", cancer = "cancre",
    arthritis = "arthre", lung_disease = "lunge", spirit = "psyche", dementia = "memrye"
  )
  # HRS：波次前缀 n/o/p/q/r + 题号。必须按数据字典语义映射，禁止“按 CSV 列顺序”对齐 26 项。
  # 证据（HRS-2012-数据字典）：
  #   NC070=arthritis, NC030=lung, NC065=psych, NC001=rate health, NC095=eyesight, NC103=hearing
  #   NG014=dressing … NG030=toilet; NG041=meals … NG059=money;
  #   NG003=walk 1 block, NG005=chair, NG006=stairs, NG008=stoop, NG009=arms, NG010=push/pull,
  #   NG012=dime; NC272=Alzheimer, NC273=dementia
  # 旧映射曾整段错位（如 nc070→lunge、ng014→toilta），会导致 CLPN 标签与真实题义不符。
  hrs_suf <- c(
    # 慢性病 / 认知 / 自报健康与感官
    c005 = "hibpe",   # high blood pressure
    c010 = "diabe",   # diabetes
    c018 = "cancre",  # cancer
    c030 = "lunge",   # lung disease
    c070 = "arthre",  # arthritis
    c065 = "psyche",  # emotional/psychiatric
    c272 = "memrye",  # Alzheimer（与 dementia 一并作为 memory-related 缺陷）
    c273 = "memrye",  # dementia → 与 c272 读入时合并同一 stem
    c001 = "srh",     # rate health
    c095 = "glass",   # rate eyesight
    c103 = "hear",    # rate hearing
    # ADL
    g014 = "dressa",  # dressing
    g021 = "batha",   # bathing
    g023 = "eata",    # eating
    g025 = "beda",    # get in/out bed
    g030 = "toilta",  # toilet
    # IADL
    g041 = "mealsa",  # meal prep
    g044 = "shopa",   # grocery shop
    g050 = "medsa",   # medications
    g059 = "moneya",  # manage money
    # mobility / strength / fine motor
    g003 = "walk100a", # walk 1 block
    g005 = "chaira",  # up from chair
    g006 = "climsa",  # climbing stairs
    g008 = "stoopa",  # stooping
    g009 = "armsa",   # reaching arms
    g010 = "lifta",   # pull/push large objects（最接近 lifting）
    g011 = "lifta",   # lifting weights（若存在）
    g012 = "dimea"    # picking up dime
  )
  charls_hit <- cross_lagged_fi_item_stems_preferred()

  out <- nms
  for (i in seq_along(nms)) {
    k <- low[[i]]
    if (k %in% names(elsa)) {
      out[[i]] <- unname(elsa[[k]])
      next
    }
    # HRS: nc005 / pc005 / og014 → 去首字母波次前缀
    if (grepl("^[a-z][cgd][0-9]+$", k)) {
      suf <- substring(k, 2L)
      if (suf %in% names(hrs_suf)) {
        out[[i]] <- unname(hrs_suf[[suf]])
        next
      }
    }
    if (k %in% names(hrs_suf)) {
      out[[i]] <- unname(hrs_suf[[k]])
      next
    }
    if (k %in% tolower(charls_hit)) {
      out[[i]] <- charls_hit[match(k, tolower(charls_hit))]
    }
  }
  out
}
