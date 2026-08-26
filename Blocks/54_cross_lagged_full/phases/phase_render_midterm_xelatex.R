#!/usr/bin/env Rscript
# 中期报告（老师版）——全横向、无目录/页码、正文顺序穿插图表
# 入口：Rscript run/cross_lagged/run_cross_lagged_frailty.R --phase midterm
#   或：Rscript Blocks/54_cross_lagged_full/phases/phase_render_midterm_xelatex.R
options(warn = 1)

.ca <- commandArgs(trailingOnly = FALSE)
.file_hits <- grep("^--file=", .ca, value = TRUE)
.file <- if (length(.file_hits)) sub("^--file=", "", .file_hits[1L]) else ""
.script_dir <- if (nzchar(.file)) {
  normalizePath(dirname(.file), winslash = "/", mustWork = FALSE)
} else {
  normalizePath(getwd(), winslash = "/")
}
ENGINE <- if (basename(.script_dir) == "phases" &&
             grepl("54_cross_lagged", basename(dirname(.script_dir)), fixed = TRUE)) {
  normalizePath(file.path(.script_dir, "..", "..", ".."), winslash = "/")
} else if (nzchar(Sys.getenv("MEDICAL_BLOCKS_ROOT", ""))) {
  normalizePath(Sys.getenv("MEDICAL_BLOCKS_ROOT"), winslash = "/")
} else {
  "/mnt/e/01block/01Block-new-Final"
}
STUDY <- Sys.getenv(
  "CROSS_LAGGED_STUDY_ROOT",
  unset = file.path(ENGINE, "Output/16_Hip_fracture_cross-laged_40595747_allages")
)
args_cli <- commandArgs(trailingOnly = TRUE)
i <- 1L
while (i <= length(args_cli)) {
  if (args_cli[[i]] == "--study-root" && i < length(args_cli)) {
    j <- i + 1L; parts <- character(0)
    while (j <= length(args_cli) && !startsWith(args_cli[[j]], "--")) {
      parts <- c(parts, args_cli[[j]]); j <- j + 1L
    }
    STUDY <- paste(parts, collapse = " "); i <- j
  } else i <- i + 1L
}
STUDY <- normalizePath(STUDY, winslash = "/", mustWork = FALSE)
G_SUM  <- "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747/summary_result"
SR_E  <- file.path(STUDY, "summary_result")
FIG_E <- file.path(SR_E, "figure")
TAB_E <- file.path(SR_E, "table")
FIG   <- if (dir.exists(file.path(G_SUM, "figure"))) file.path(G_SUM, "figure") else FIG_E
TAB   <- if (dir.exists(file.path(G_SUM, "table"))) file.path(G_SUM, "table") else TAB_E
if (length(list.files(FIG_E, pattern = "Figure 2-.*RCS"))) FIG <- FIG_E
if (length(list.files(TAB_E, pattern = "^Table "))) TAB <- TAB_E
OUTDIR <- SR_E
dir.create(OUTDIR, recursive = TRUE, showWarnings = FALSE)

workdir <- file.path(tempdir(), paste0("midterm_", format(Sys.time(), "%H%M%S")))
dir.create(workdir, recursive = TRUE, showWarnings = FALSE)
FIG_LOCAL <- workdir

# ── helpers ────────────────────────────────────────────────────────────────
.escape <- function(x) {
  x <- as.character(x)
  x[is.na(x)] <- ""
  x <- gsub("\u00b2", "2", x, fixed = TRUE)
  x <- gsub("\u00b3", "3", x, fixed = TRUE)
  x <- gsub("\u00d7|\u2212|\u2013|\u2014", "-", x)
  x <- gsub("\u2264", "<=", x, fixed = TRUE)
  x <- gsub("\u2265", ">=", x, fixed = TRUE)
  x <- gsub("<", "\001LT\001", x, fixed = TRUE)
  x <- gsub(">", "\001GT\001", x, fixed = TRUE)
  x <- gsub("\\", "\001BS\001", x, fixed = TRUE)
  x <- gsub("([#$%&_{}])", "\\\\\\1", x)
  x <- gsub("\001BS\001", "\\textbackslash{}", x, fixed = TRUE)
  x <- gsub("~", "\\textasciitilde{}", x, fixed = TRUE)
  x <- gsub("^", "\\textasciicircum{}", x, fixed = TRUE)
  x <- gsub("\001LT\001", "$<$", x, fixed = TRUE)
  x <- gsub("\001GT\001", "$>$", x, fixed = TRUE)
  x
}

.h1 <- function(title) {
  paste0(
    "\\vspace{0.6em}\\noindent\\textcolor{Accent}{\\rule{\\textwidth}{1.1pt}}\\\\\n",
    "\\vspace{0.2em}\\noindent{\\Large\\bfseries\\color{Ink} ", .escape(title), "}\\\\\n",
    "\\vspace{0.15em}\\noindent\\textcolor{RuleSoft}{\\rule{\\textwidth}{0.35pt}}\\par\\vspace{0.55em}\n\n"
  )
}
.h2 <- function(title) {
  paste0(
    "\\vspace{0.45em}\\noindent{\\large\\bfseries\\color{Accent} ", .escape(title), "}\\par\\vspace{0.25em}\n\n"
  )
}
.lead <- function(...) {
  paste0("{\\color{Muted}\\setlength{\\parskip}{0.35em}", .escape(paste0(...)),
         "}\\par\\vspace{0.35em}\n\n")
}
.para <- function(...) paste0(.escape(paste0(...)), "\\par\\vspace{0.25em}\n\n")
.note <- function(s) {
  if (is.null(s) || !nzchar(s)) return("")
  sprintf("{\\footnotesize\\color{Muted}%s}\\par\\vspace{0.2em}\n\n", .escape(s))
}
.cap <- function(s) {
  sprintf(
    "\\noindent{\\footnotesize\\bfseries\\color{Ink}%s}\\par\\vspace{0.15em}\n",
    .escape(s)
  )
}

# ── table readers ──────────────────────────────────────────────────────────
.read_table_simple <- function(path) {
  ext <- tolower(tools::file_ext(path))
  raw <- tryCatch({
    if (ext %in% c("xlsx", "xls")) {
      sh <- readxl::excel_sheets(path)[[1]]
      suppressMessages(as.data.frame(
        readxl::read_excel(path, sheet = sh, col_names = FALSE, .name_repair = "minimal"),
        stringsAsFactors = FALSE))
    } else {
      utils::read.csv(path, header = FALSE, check.names = FALSE, stringsAsFactors = FALSE)
    }
  }, error = function(e) NULL)
  if (is.null(raw) || !nrow(raw)) return(NULL)
  hdr_row <- 1L
  for (i in seq_len(min(6L, nrow(raw)))) {
    cells <- trimws(as.character(unlist(raw[i, ], use.names = FALSE)))
    cells[is.na(cells)] <- ""
    key <- paste(cells, collapse = " ")
    if (grepl("Characteristic|Variable", key, ignore.case = TRUE) && sum(nzchar(cells)) >= 2L) {
      hdr_row <- i
      break
    }
  }
  hdr <- trimws(as.character(unlist(raw[hdr_row, ], use.names = FALSE)))
  hdr[is.na(hdr) | !nzchar(hdr)] <- paste0("C", which(is.na(hdr) | !nzchar(hdr)))
  hdr <- make.unique(hdr, sep = " ")
  body <- raw[seq.int(hdr_row + 1L, nrow(raw)), , drop = FALSE]
  keep <- apply(body, 1, function(r) any(nzchar(trimws(as.character(r)))))
  body <- body[keep, , drop = FALSE]
  if (!nrow(body)) return(NULL)
  colnames(body) <- hdr
  for (j in seq_len(ncol(body))) {
    body[[j]] <- trimws(as.character(body[[j]]))
    body[[j]][body[[j]] %in% c("NA", "NaN", "null")] <- ""
  }
  body
}

.read_table_logistic <- function(path) {
  raw <- tryCatch({
    sh <- readxl::excel_sheets(path)[[1]]
    suppressMessages(as.data.frame(
      readxl::read_excel(path, sheet = sh, col_names = FALSE, .name_repair = "minimal"),
      stringsAsFactors = FALSE))
  }, error = function(e) NULL)
  if (is.null(raw) || nrow(raw) < 3L) return(.read_table_simple(path))
  char_row <- NA_integer_
  for (i in seq_len(min(6L, nrow(raw)))) {
    c1 <- tolower(as.character(raw[[1]][i]))
    if (!is.na(c1) && grepl("^characteristic", c1)) { char_row <- i; break }
  }
  if (is.na(char_row)) return(.read_table_simple(path))
  model_row <- if (char_row >= 2L) char_row - 1L else NA_integer_
  base_hdr <- trimws(as.character(unlist(raw[char_row, ], use.names = FALSE)))
  base_hdr[is.na(base_hdr)] <- ""
  model_lab <- if (!is.na(model_row)) {
    trimws(as.character(unlist(raw[model_row, ], use.names = FALSE)))
  } else rep("", length(base_hdr))
  model_lab[is.na(model_lab)] <- ""
  cur <- ""
  for (j in seq_along(model_lab)) {
    if (nzchar(model_lab[[j]])) cur <- model_lab[[j]] else model_lab[[j]] <- cur
  }
  hdr <- character(length(base_hdr))
  for (j in seq_along(base_hdr)) {
    b <- base_hdr[[j]]; m <- model_lab[[j]]
    if (!nzchar(b)) b <- paste0("C", j)
    if (nzchar(m) && grepl("OR|95|P-value|P value", b, ignore.case = TRUE)) {
      hdr[[j]] <- paste0(m, " ", b)
    } else hdr[[j]] <- b
  }
  hdr <- make.unique(hdr, sep = " ")
  body <- raw[seq.int(char_row + 1L, nrow(raw)), , drop = FALSE]
  keep <- apply(body, 1, function(r) any(nzchar(trimws(as.character(r)))))
  body <- body[keep, , drop = FALSE]
  colnames(body) <- hdr
  for (j in seq_len(ncol(body))) {
    body[[j]] <- trimws(as.character(body[[j]]))
    body[[j]][body[[j]] %in% c("NA", "NaN", "null")] <- ""
  }
  drop <- grepl("^Crude Model|^Adjusted by|^Note:", body[[1]], ignore.case = TRUE)
  body <- body[!drop, , drop = FALSE]
  body
}

.tab_render <- function(df, caption, note = NULL, max_rows = 55L) {
  out <- paste0(.cap(caption), .note(note))
  if (is.null(df) || !nrow(df)) {
    return(paste0(out, "{\\itshape\\color{Muted}（表内容为空）}\\par\\vspace{0.6em}\n\n"))
  }
  if (nrow(df) > max_rows) {
    df <- df[seq_len(max_rows), , drop = FALSE]
    note2 <- paste0(if (!is.null(note) && nzchar(note)) paste0(note, " ") else "",
                    sprintf("（篇幅所限，仅展示前 %d 行）", max_rows))
    out <- paste0(.cap(caption), .note(note2))
  }
  nc <- ncol(df)
  body_lines <- character(0)
  for (i in seq_len(nrow(df))) {
    cells_raw <- unlist(df[i, ], use.names = FALSE)
    cells <- .escape(cells_raw)
    if (sum(nzchar(cells_raw)) == 1L && nzchar(cells_raw[[1]])) {
      cells[[1]] <- paste0("\\textbf{", cells[[1]], "}")
    }
    # zebra row tint via rowcolor on even rows for readability
    row_prefix <- if (i %% 2L == 0L) "\\rowcolor{RowZ} " else ""
    body_lines <- c(body_lines, paste0(row_prefix, paste(cells, collapse = " & "), " \\\\"))
  }
  nh <- .escape(names(df))
  nh <- gsub(" ", "\\\\,", nh)
  hdr_line <- paste0("\\rowcolor{HeadBg}\\color{HeadFg} ",
                     paste(paste0("\\bfseries ", nh), collapse = " & "), " \\\\")
  colspec <- paste0(">{\\raggedright\\arraybackslash}p{0.18\\textwidth}",
                    paste(rep(">{\\centering\\arraybackslash}p{0.10\\textwidth}", max(0L, nc - 1L)),
                          collapse = ""))
  # wide tables: let resizebox handle; use simple colspec
  if (nc <= 6L) {
    colspec <- paste0("l", paste(rep("c", max(0L, nc - 1L)), collapse = ""))
  } else {
    colspec <- paste(rep("c", nc), collapse = "")
  }
  tab_body <- paste(c(
    sprintf("\\begin{tabular}{%s}", colspec),
    "\\toprule",
    hdr_line,
    "\\midrule",
    body_lines,
    "\\bottomrule",
    "\\end{tabular}"
  ), collapse = "\n")

  paste0(
    out,
    "\\begin{center}\n",
    "{\\scriptsize\\setlength{\\tabcolsep}{3.2pt}\n",
    "\\resizebox{\\textwidth}{!}{%\n", tab_body, "\n}}\n",
    "\\end{center}\\vspace{0.55em}\n\n"
  )
}

.tab_file <- function(pattern, caption, note = NULL, logistic = FALSE) {
  hits <- list.files(TAB, pattern = pattern, full.names = TRUE)
  if (!length(hits)) hits <- list.files(TAB_E, pattern = pattern, full.names = TRUE)
  if (!length(hits)) {
    return(paste0(.cap(caption), "{\\itshape\\color{Muted}（表未找到）}\\par\\vspace{0.5em}\n\n"))
  }
  path <- hits[[1L]]
  df <- if (isTRUE(logistic)) .read_table_logistic(path) else .read_table_simple(path)
  .tab_render(df, caption, note)
}

.fig_i <- 0L
.fig <- function(fname, caption, note = NULL, width = 0.88) {
  path <- file.path(FIG, fname)
  if (!file.exists(path)) path <- file.path(FIG_E, fname)
  if (!file.exists(path)) {
    hits <- list.files(c(FIG, FIG_E), pattern = gsub("([.?])", "\\\\\\1", fname), full.names = TRUE)
    if (!length(hits)) {
      stem <- sub("\\.pdf$", "", fname)
      hits <- list.files(c(FIG, FIG_E), pattern = paste0("^", gsub("([.+])", "\\\\\\1", stem)),
                         full.names = TRUE)
    }
    if (length(hits)) path <- hits[[1L]]
  }
  if (!file.exists(path)) {
    return(paste0(.cap(caption), "{\\itshape\\color{Muted}（图文件未找到）}\\par\\vspace{0.4em}\n\n"))
  }
  .fig_i <<- .fig_i + 1L
  local <- file.path(FIG_LOCAL, sprintf("fig%03d.pdf", .fig_i))
  file.copy(path, local, overwrite = TRUE)
  paste0(
    "\\vspace{0.2em}\\noindent",
    "\\begin{minipage}{\\textwidth}\\centering\n",
    sprintf("\\includegraphics[width=%.2f\\textwidth,height=0.78\\textheight,keepaspectratio]{%s}\n",
            width, basename(local)),
    "\\vspace{0.25em}\n",
    sprintf("{\\footnotesize\\bfseries\\color{Ink}%s}\\par\n", .escape(caption)),
    if (!is.null(note) && nzchar(note))
      sprintf("{\\footnotesize\\color{Muted}%s}\\par\n", .escape(note)) else "",
    "\\end{minipage}\\par\\vspace{0.55em}\n\n"
  )
}

.mediation_summary_text <- function() {
  hits <- list.files(c(TAB, TAB_E), pattern = "^Table S7", full.names = TRUE)
  if (!length(hits)) {
    return(.para("抑郁中介分析结果见 Table S7 与 Figure S3。"))
  }
  path <- hits[[1L]]
  raw <- suppressMessages(as.data.frame(
    readxl::read_excel(path, col_names = FALSE, .name_repair = "minimal"),
    stringsAsFactors = FALSE
  ))
  lines <- character(0)
  for (i in seq_len(nrow(raw))) {
    r <- trimws(as.character(unlist(raw[i, ])))
    r[is.na(r)] <- ""
    if (r[[1]] %in% c("CHARLS", "ELSA", "HRS") && length(r) >= 7L) {
      lines <- c(lines, sprintf(
        "%s：总效应 %s；直接效应 %s；间接效应（经抑郁）%s；中介比例约 %s。",
        r[[1]], r[[2]], r[[3]], r[[4]], r[[7]]
      ))
    }
  }
  note_row <- paste(trimws(as.character(unlist(raw[nrow(raw), ]))), collapse = " ")
  type_bits <- character(0)
  if (grepl("CHARLS: Complementary", note_row)) type_bits <- c(type_bits, "CHARLS 为互补中介")
  if (grepl("ELSA: Competitive", note_row)) type_bits <- c(type_bits, "ELSA 偏竞争/抑制")
  if (grepl("HRS: Complementary", note_row)) type_bits <- c(type_bits, "HRS 为互补中介")
  type_txt <- if (length(type_bits)) paste0(paste(type_bits, collapse = "；"), "。") else ""
  txt <- paste(lines, collapse = "")
  if (!nzchar(txt)) txt <- "详见 Table S7 与 Figure S3。"
  .para(paste0(
    "抑郁中介方面：", txt, type_txt,
    "总体而言，CHARLS 与 HRS 中抑郁可部分传导虚弱指数与髋部骨折的关联（间接效应方向一致），ELSA 间接效应不显著；三队列直接效应仍占主要部分。"
  ))
}

.covar_lock_blurb <- function() {
  acc <- file.path(STUDY, "phase3_relock_acceptance.txt")
  if (!file.exists(acc)) return("")
  L <- readLines(acc, warn = FALSE)
  m2 <- sub("^Model2_single=", "", L[grepl("^Model2_single=", L)][1])
  src <- sub("^lock_source=", "", L[grepl("^lock_source=", L)][1])
  isc <- sub("^intersect_screen=", "", L[grepl("^intersect_screen=", L)][1])
  if (is.na(m2) || !nzchar(m2)) return("")
  .para(sprintf(
    "多变量调整（Model 2）在三库统一锁定为：%s（来源：三库 VIF 筛选后交集；lock=%s%s）。合并分析另加 Country。",
    m2, src,
    if (!is.na(isc) && nzchar(isc)) paste0("；交集 ", isc) else ""
  ))
}

dbs <- c("CHARLS", "ELSA", "HRS")

# 正文顺序穿插：表1 → 表2 + 图2 → 图3 → 图4 + 表S8 → 变化表 → 中介表/图 → 补充表 → 补充图 → 小结
body <- c(
  # ── 封面式标题块（整份均为横向，无另起页码、无目录）────────────────
  "\\noindent\\begin{minipage}{\\textwidth}\n",
  "{\\color{Accent}\\rule{\\textwidth}{2.2pt}}\\par\\vspace{0.9em}\n",
  "{\\fontsize{22}{26}\\selectfont\\bfseries\\color{Ink} 虚弱指数与髋部骨折的关联\\\\[0.25em]\n",
  "及交叉滞后面板分析}\\par\\vspace{0.45em}\n",
  "{\\large\\color{Muted} CHARLS \\textperiodcentered{} ELSA \\textperiodcentered{} HRS ",
  "三队列纵向研究 · 中期汇报}\\par\\vspace{0.55em}\n",
  "{\\color{RuleSoft}\\rule{\\textwidth}{0.6pt}}\\par\\vspace{0.35em}\n",
  sprintf("{\\small\\color{Muted}%s}\\par\n", format(Sys.Date(), "%Y 年 %m 月")),
  "\\end{minipage}\\par\\vspace{0.9em}\n\n",

  .h1("一、研究背景与分析目的"),
  .lead("基于中国健康与养老追踪调查（CHARLS）、英国老龄化纵向研究（ELSA）与美国健康与退休研究（HRS），",
        "探讨基线虚弱指数（Frailty Index, FI）与髋部骨折（Hip fracture）的关联；",
        "并在纵向框架下开展 FI 剂量—反应、亚组稳健性、交叉滞后面板网络（CLPN）、",
        "FI 变化分析，以及以抑郁为中介的路径分析。"),
  .para("下文按论文主结果逻辑依次给出表与图，同主题下表图紧邻呈现，便于审阅。"),
  .covar_lock_blurb(),

  # ── 基线 ───────────────────────────────────────────────────────────
  .h1("二、基线特征"),
  .para("按是否发生髋部骨折比较三队列基线人口学与临床特征，描述分析样本构成。"),
  unlist(lapply(dbs, function(db) c(
    .h2(sprintf("Table 1 · %s", db)),
    .tab_file(sprintf("^Table 1-%s\\.", db),
              sprintf("Table 1 (%s). Baseline characteristics of Hip fracture", db),
              sprintf("%s：按骨折分层的基线比较。", db))
  ))),

  # ── 主关联：表2 立刻接图2 RCS ─────────────────────────────────────
  .h1("三、主要关联：三分位回归与剂量—反应"),
  .para("以 FI 连续变量及三分位为暴露，估计髋部骨折的优势比（OR）及 95% 置信区间；",
        "随后用限制性立方样条（RCS）展示连续 FI 的剂量—反应形态。"),

  unlist(lapply(c(dbs, "Pooled"), function(db) c(
    .h2(sprintf("Table 2 · %s  Logistic 回归", db)),
    .tab_file(sprintf("^Table 2-%s\\.", db),
              sprintf("Table 2 (%s). Logistic regression of FI tertile and Hip fracture", db),
              sprintf("%s：Crude / Model 1 / Model 2。", db),
              logistic = TRUE),
    .h2(sprintf("Figure 2 · %s  RCS", db)),
    .fig(sprintf("Figure 2-%s. RCS plot between Frailty Index and Hip Fracture.pdf", db),
         sprintf("Figure 2 (%s). RCS plot between Frailty Index and Hip Fracture", db),
         sprintf("%s：FI 与骨折风险的剂量—反应。", db),
         width = 0.78)
  ))),

  # ── 亚组 ───────────────────────────────────────────────────────────
  .h1("四、亚组稳健性"),
  .para("在预指定亚组中呈现 FI 与髋部骨折关联，评价主结果是否在不同人口学与临床亚群中方向一致。"),
  unlist(lapply(dbs, function(db) c(
    .h2(sprintf("Figure 3 · %s", db)),
    .fig(sprintf("Figure 3-%s. Subgroup Forest analyses of FI.pdf", db),
         sprintf("Figure 3 (%s). Subgroup forest analyses of FI", db),
         width = 0.90)
  ))),

  # ── 网络图 + 邻接表（成对）────────────────────────────────────────
  .h1("五、交叉滞后网络（条目水平）"),
  .para("基于交叉滞后面板网络（CLPN）展示虚弱条目及髋部骨折之间的纵向关联结构；",
        "邻接矩阵给出 Figure 4 对应边权重。",
        "Figure S1/S2 为网络边权 nonparametric bootstrap 与 case-dropping 稳定性",
        "（对齐文献 Supplementary Figs. 25–26）。"),
  unlist(lapply(dbs, function(db) c(
    .h2(sprintf("Figure 4 · %s  CLPN", db)),
    .fig(sprintf("Figure 4-%s. CLPN network of frailty index items.pdf", db),
         sprintf("Figure 4 (%s). CLPN network of frailty index items", db),
         width = 0.82),
    .h2(sprintf("Figure S1 · %s  边权 Bootstrap", db)),
    .fig(sprintf("Figure S1-%s. CLPN edge weight bootstrap.pdf", db),
         sprintf("Figure S1 (%s). CLPN edge-weight bootstrap (sample vs boot mean + 95%% CI)", db),
         width = 0.72),
    .h2(sprintf("Figure S2 · %s  Case-dropping", db)),
    .fig(sprintf("Figure S2-%s. CLPN case-dropping stability.pdf", db),
         sprintf("Figure S2 (%s). CLPN case-dropping stability (edge)", db),
         width = 0.72),
    .h2(sprintf("Table S8 · %s  邻接矩阵", db)),
    .tab_file(sprintf("^Table S8-%s", db),
              sprintf("Table S8 (%s). CLPN adjacency", db),
              sprintf("%s：与 Figure 4 对应。", db),
              logistic = TRUE)
  ))),

  # ── FI 变化 ────────────────────────────────────────────────────────
  .h1("六、FI 水平与变化分析"),
  .para("在纵向设计下评估平均 FI 及 FI 变化与髋部骨折的关系。"),
  .h2("Table S5"),
  .tab_file("^Table S5\\. Change", "Table S5. Change analysis: Mean FI and FI change",
            "主变化分析。", logistic = TRUE),
  .h2("Table S5.1"),
  .tab_file("^Table S5\\.1", "Table S5.1. Change analysis Mean FI and FI change",
            "变化分析补充表。", logistic = TRUE),

  # ── 中介：表 + 路径图 ──────────────────────────────────────────────
  .h1("七、抑郁中介路径"),
  .para("S6 为路径相关回归；S7 为以抑郁为中介的纵向分解；Figure S3 给出路径示意图。"),
  .h2("Table S6"),
  .tab_file("^Table S6", "Table S6. Correlation/regression FI, Depression, fracture",
            "路径相关回归。", logistic = TRUE),
  .h2("Table S7"),
  .tab_file("^Table S7", "Table S7. Longitudinal mediation FI → Depression → fracture",
            "纵向中介效应。"),
  .mediation_summary_text(),
  unlist(lapply(c(dbs, "Pooled"), function(db) c(
    .h2(sprintf("Figure S3 · %s", db)),
    .fig(sprintf("Figure S3-%s. Longitudinal mediation path diagram of FI and hip fracture.pdf", db),
         sprintf("Figure S3 (%s). Mediation path diagram", db),
         width = 0.80)
  ))),

  # ── 补充方法学表（插在中介后、补充描述图前）────────────────────────
  .h1("八、协变量筛选与数据质量补充表"),
  .para("S1 插补前后比较；S2 连续变量正态性；S3 单因素回归；S4 VIF 共线性诊断。"),
  unlist(lapply(dbs, function(db) c(
    .h2(sprintf("%s · Tables S1–S4", db)),
    .tab_file(sprintf("^Table S1-%s\\.", db), sprintf("Table S1 (%s). Before/after imputation", db)),
    .tab_file(sprintf("^Table S2-%s\\.", db), sprintf("Table S2 (%s). Normality tests", db)),
    .tab_file(sprintf("^Table S3-%s\\.", db), sprintf("Table S3 (%s). Univariate regression", db),
              logistic = TRUE),
    .tab_file(sprintf("^Table S4-%s\\.", db), sprintf("Table S4 (%s). VIF multicollinearity", db))
  ))),

  # ── 补充描述图 ─────────────────────────────────────────────────────
  .h1("九、补充描述图"),
  .para("疾病组 FI 描述仅采用纵向 incidence 分析样本上的 Figure S4（按调查年 × ever 入射分组的均值±SE），",
        "以及 Figure S5（三国基线）。不再使用基线横断面 FI 箱线图，以免与入射分析队列定义不一致。"),
  unlist(lapply(dbs, function(db) c(
    .h2(sprintf("Figure S4 · %s", db)),
    .fig(sprintf("Figure S4-%s. Mean FI by Year and Disease.pdf", db),
         sprintf("Figure S4 (%s). Mean FI by year and disease (ever-incident in analytic panel)", db),
         width = 0.78)
  ))),
  .h2("Figure S5 · 三国基线"),
  .fig("Figure S5. Mean FI by Country and Disease.pdf",
       "Figure S5. Mean FI by country and disease (ever-incident, baseline wave)",
       width = 0.78),

  # ── 小结 ───────────────────────────────────────────────────────────
  .h1("十、小结"),
  .para("基线与回归分析显示，较高虚弱指数与髋部骨折风险升高相关；RCS 与亚组结果进一步支持关联的稳健性。",
        "交叉滞后网络从条目水平刻画了虚弱维度与结局的时间先后关系；FI 变化分析补充了动态指标信息。"),
  .mediation_summary_text(),
  "\\vspace{0.8em}\\noindent{\\color{Accent}\\rule{\\textwidth}{1.1pt}}\\par\\vspace{0.35em}\n",
  "{\\small\\color{Muted}本材料为中期进展汇报，结果解释以最终定稿论文为准。}\\par\n"
)

tex <- c(
  "\\documentclass[11pt,a4paper,landscape]{article}",
  "\\usepackage[margin=1.35cm,top=1.2cm,bottom=1.2cm]{geometry}",
  "\\usepackage{fontspec}",
  "\\usepackage{xeCJK}",
  "\\setCJKmainfont{AR PL UMing CN}",
  "\\setCJKsansfont{Droid Sans Fallback}",
  "\\setmainfont{DejaVu Sans}",
  "\\setsansfont{DejaVu Sans}",
  "\\usepackage{graphicx}",
  "\\usepackage{booktabs}",
  "\\usepackage{array}",
  "\\usepackage{xcolor}",
  "\\usepackage{colortbl}",
  "\\usepackage{setspace}",
  # 配色：冷石灰 + 墨色正文
  "\\definecolor{Ink}{HTML}{1A2332}",
  "\\definecolor{Accent}{HTML}{1F5F6B}",
  "\\definecolor{Muted}{HTML}{5A6570}",
  "\\definecolor{RuleSoft}{HTML}{C5CDD4}",
  "\\definecolor{HeadBg}{HTML}{1F5F6B}",
  "\\definecolor{HeadFg}{HTML}{FFFFFF}",
  "\\definecolor{RowZ}{HTML}{F3F6F7}",
  "\\definecolor{PageBg}{HTML}{FBFCFC}",
  "\\pagecolor{PageBg}",
  "\\color{Ink}",
  "\\pagestyle{empty}",
  "\\setstretch{1.15}",
  "\\setlength{\\parindent}{0pt}",
  "\\setlength{\\parskip}{0.25em}",
  "\\renewcommand{\\arraystretch}{1.12}",
  "\\begin{document}",
  unlist(body),
  "\\end{document}"
)

writeLines(tex, file.path(workdir, "midterm.tex"), useBytes = TRUE)
message("FIG=", FIG, " TAB=", TAB, " workdir=", workdir)

old <- getwd(); setwd(workdir); on.exit(setwd(old), add = TRUE)
st <- system2("xelatex", c("-interaction=nonstopmode", "midterm.tex"),
              stdout = TRUE, stderr = TRUE)
writeLines(st, file.path(OUTDIR, "midterm_xelatex.log"))
pdf_ok <- file.exists(file.path(workdir, "midterm.pdf"))
has_fatal <- any(grepl("^!", st))
if (has_fatal || !pdf_ok) {
  message(paste(tail(st, 80), collapse = "\n"))
  stop("xelatex failed")
}
if (!is.null(attr(st, "status")) && attr(st, "status") != 0) {
  message("xelatex exit!=0 but PDF present; continuing (check midterm_xelatex.log)")
}

pdf_src <- file.path(workdir, "midterm.pdf")
out_name <- "中期报告_虚弱指数与髋部骨折_三队列交叉滞后分析.pdf"
out_e <- file.path(OUTDIR, out_name)
file.copy(pdf_src, out_e, overwrite = TRUE)
dir.create(G_SUM, recursive = TRUE, showWarnings = FALSE)
tryCatch(file.copy(pdf_src, file.path(G_SUM, out_name), overwrite = TRUE),
         error = function(e) message(e$message))
message("OK ", out_e, " size=", file.info(out_e)$size)
message("G  ", file.path(G_SUM, out_name), " size=",
        if (file.exists(file.path(G_SUM, out_name))) file.info(file.path(G_SUM, out_name))$size else NA)
