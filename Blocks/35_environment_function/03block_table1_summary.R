###############################################################################
#  table1_summary — 从 Table 1 Excel 文件生成中文描述性文字
#
#  register_block: "table1_summary"
#  典型用途: 从导出的 Table 1 xlsx 中自动生成 Methods / Results 段落里的人口学描述。
#
#  支持的变量行（通过首列关键字匹配）：
#    Gender, Race, PIR, Smoked, Diabetes, Hypertension, Cardiovasculardiseases
#
#  # ── Bug 修复说明（相对原 Table1_summary.R）────────────────────────────────
#  Bug: readxl::read_excel() 返回 tibble；tibble[i, j] 返回 1×1 tibble 而非标量。
#       is.na(tibble[i,1]) 返回 1×1 logical 矩阵，直接传入 if() 会报错或行为异常。
#  修复: 统一用 as.character(cell_data[[col]][row]) 安全提取标量字符值。
#
#  # ── 配置 config$table1_summary ───────────────────────────────────────────
#  table1_summary = list(
#    file_path  = NULL,   # Table 1 xlsx 文件路径（必填）
#    start_row  = 3L,     # 数据区起始行（1-based，Excel 行号）
#    end_row    = 70L,    # 数据区结束行
#    start_col  = 1L,     # 数据区起始列
#    end_col    = 5L      # 数据区结束列（至少含"变量名"和"总体"两列）
#  ),
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  写: ctx$results$table1_summary_text — 生成的中文描述字符串
###############################################################################

# ── 独立工具函数（可在 Block 流水线外直接调用）──────────────────────────────
#
#  用法示例:
#    txt <- generate_table1_summary("path/to/Table 1.xlsx")
#    cat(txt)
#
generate_table1_summary <- function(file_path,
                                    start_row = 3L, end_row = 70L,
                                    start_col = 1L, end_col = 5L) {
  if (!requireNamespace("readxl", quietly = TRUE)) {
    stop("generate_table1_summary: \u9700\u8981 readxl \u5305\uff0c\u8bf7\u5148 install.packages('readxl')\u3002")
  }

  data      <- readxl::read_excel(file_path)
  cell_data <- data[start_row:end_row, start_col:end_col]

  # 安全标量提取：tibble[i, j] 返回 1×1 tibble，需用 [[col]][row] 取标量
  .cell <- function(row, col) {
    as.character(cell_data[[col]][row])
  }

  # 去除千分位逗号并提取数值部分（如 "1,234 (56.7%)" → 1234）
  .num <- function(row, col) {
    val     <- .cell(row, col)
    cleaned <- gsub(",", "", val, fixed = TRUE)
    as.numeric(sub("\\s.*", "", cleaned))
  }

  # 提取括号内内容（如 "1234 (56.7%)" → "56.7%"）
  .pct <- function(row, col) {
    sub(".*\\((.*)\\).*", "\\1", .cell(row, col))
  }

  message <- ""
  n_rows  <- nrow(cell_data)

  for (i in seq_len(n_rows)) {
    name  <- .cell(i, 1L)
    value <- .cell(i, 2L)

    # 遇到 NA 名称行则停止（表格结束标记）
    if (is.na(name) || name == "NA") break

    if (name == "Gender") {
      if (i + 2L > n_rows) next
      num_female <- .num(i + 1L, 2L)
      num_male   <- .num(i + 2L, 2L)
      pct_female <- .pct(i + 1L, 2L)
      pct_male   <- .pct(i + 2L, 2L)
      message <- paste0(
        message,
        "\uff0c\u7537\u6027", num_male,  "\u4eba\uff08", pct_male,  "\uff09",
        "\uff0c\u5973\u6027", num_female, "\u4eba\uff08", pct_female, "\uff09"
      )
    }

    if (name == "Race") {
      if (i + 5L > n_rows) next
      rows  <- seq(i + 1L, i + 5L)
      nums  <- vapply(rows, .num, numeric(1L), col = 2L)
      pcts  <- vapply(rows, .pct, character(1L), col = 2L)
      labels <- c(
        "\u58a8\u897f\u54e5\u88d4\u7f8e\u56fd\u4eba", "\u975e\u897f\u73ed\u7259\u88d4\u9ed1\u4eba",
        "\u975e\u897f\u73ed\u7259\u88d4\u767d\u4eba", "\u5176\u4ed6\u897f\u73ed\u7259\u88d4",
        "\u5176\u4ed6\u79cd\u65cf"
      )
      message <- paste0(
        message,
        "\u3002\u5728\u79cd\u65cf\u65b9\u9762\uff0c",
        paste0(nums, "\u540d\u53c2\u4e0e\u8005\uff08", pcts, "\uff09\u4e3a", labels,
               collapse = "\uff0c")
      )
    }

    if (name == "PIR") {
      if (i + 3L > n_rows) next
      num_1   <- .num(i + 1L, 2L);  pct_1   <- .pct(i + 1L, 2L)
      num_3   <- .num(i + 2L, 2L);  pct_3   <- .pct(i + 2L, 2L)
      num_13  <- .num(i + 3L, 2L);  pct_13  <- .pct(i + 3L, 2L)
      message <- paste0(
        message,
        "\u3002\u5bb6\u5ead\u6536\u5165\u4e0e\u8d2b\u56f0\u6bd4\u7387\u65b9\u9762\uff0c",
        "\u5927\u4e8e3\u7684\u6709", num_3,  "\u4eba\uff08", pct_3,  "\uff09\uff0c",
        "\u22651\u4e14\u22643\u7684\u6709", num_13, "\u4eba\uff08", pct_13, "\uff09\uff0c",
        "\u5c0f\u4e8e1\u7684\u6709",   num_1,  "\u4eba\uff08", pct_1,  "\uff09"
      )
    }

    if (name == "Smoked" && (is.na(value) || value == "NA")) {
      if (i + 2L > n_rows) next
      num_no  <- .num(i + 1L, 2L);  pct_no  <- .pct(i + 1L, 2L)
      num_yes <- .num(i + 2L, 2L);  pct_yes <- .pct(i + 2L, 2L)
      message <- paste0(
        message,
        "\u3002\u5438\u70df\u65b9\u9762\uff0c\u4e0d\u5438\u70df\u7684\u4e3a", num_no,  "\u4eba\uff08", pct_no,  "\uff09\uff0c",
        "\u5438\u70df\u7684\u4e3a",   num_yes, "\u4eba\uff08", pct_yes, "\uff09"
      )
    }

    if (name == "Diabetes") {
      if (i + 3L > n_rows) next
      num_borderline <- .num(i + 1L, 2L);  pct_borderline <- .pct(i + 1L, 2L)
      num_no         <- .num(i + 2L, 2L);  pct_no         <- .pct(i + 2L, 2L)
      num_yes        <- .num(i + 3L, 2L);  pct_yes        <- .pct(i + 3L, 2L)
      message <- paste0(
        message,
        "\u3002\u7cd6\u5c3f\u75c5\u65b9\u9762\uff0c\u6ca1\u6709\u60a3\u7cd6\u5c3f\u75c5\u4e3a", num_no, "\u4eba\uff08", pct_no, "\uff09\uff0c",
        "\u60a3\u6709\u7cd6\u5c3f\u75c5\u4e3a",   num_yes, "\u4eba\uff08", pct_yes, "\uff09\uff0c",
        "\u53e6\u5916\u6709", num_borderline, "\u4eba\uff08", pct_borderline, "\uff09\u5904\u4e8e\u60a3\u75c5\u8fb9\u7f18"
      )
    }

    if (name == "Hypertension") {
      if (i + 2L > n_rows) next
      num_no  <- .num(i + 1L, 2L);  pct_no  <- .pct(i + 1L, 2L)
      num_yes <- .num(i + 2L, 2L);  pct_yes <- .pct(i + 2L, 2L)
      message <- paste0(
        message,
        "\u3002\u9ad8\u8840\u538b\u65b9\u9762\uff0c\u6ca1\u6709\u9ad8\u8840\u538b\u4e3a", num_no,  "\u4eba\uff08", pct_no,  "\uff09\uff0c",
        "\u6709\u9ad8\u8840\u538b\u4e3a",   num_yes, "\u4eba\uff08", pct_yes, "\uff09"
      )
    }

    if (name == "Cardiovasculardiseases") {
      if (i + 2L > n_rows) next
      num_no  <- .num(i + 1L, 2L);  pct_no  <- .pct(i + 1L, 2L)
      num_yes <- .num(i + 2L, 2L);  pct_yes <- .pct(i + 2L, 2L)
      message <- paste0(
        message,
        "\u3002\u5fc3\u8840\u7ba1\u75be\u75c5\u65b9\u9762\uff0c\u6ca1\u6709\u60a3\u5fc3\u8840\u7ba1\u75be\u75c5\u4e3a", num_no,  "\u4eba\uff08", pct_no,  "\uff09\uff0c",
        "\u60a3\u6709\u5fc3\u8840\u7ba1\u75be\u75c5\u4e3a", num_yes, "\u4eba\uff08", pct_yes, "\uff09"
      )
    }
  }

  # 去掉开头多余的逗号/句号
  message <- sub("^\uff0c", "", message)

  message
}

# ── Block 主函数 ──────────────────────────────────────────────────────────────
block_table1_summary <- function(ctx, ...) {
  cfg    <- ctx$config
  t1_cfg <- cfg$table1_summary %||% list()

  file_path <- as.character(t1_cfg$file_path %||% "")
  if (!nzchar(file_path)) {
    stop(
      "table1_summary: \u8bf7\u5728 config$table1_summary$file_path \u4e2d\u6307\u5b9a Table 1 xlsx \u6587\u4ef6\u8def\u5f84\u3002"
    )
  }
  if (!file.exists(file_path)) {
    stop("table1_summary: \u6587\u4ef6\u4e0d\u5b58\u5728: ", file_path)
  }

  start_row <- as.integer(t1_cfg$start_row %||% 3L)
  end_row   <- as.integer(t1_cfg$end_row   %||% 70L)
  start_col <- as.integer(t1_cfg$start_col %||% 1L)
  end_col   <- as.integer(t1_cfg$end_col   %||% 5L)

  cli::cli_alert_info("table1_summary: \u8bfb\u53d6 {basename(file_path)}")

  txt <- tryCatch(
    generate_table1_summary(file_path, start_row, end_row, start_col, end_col),
    error = function(e) {
      cli::cli_alert_danger("table1_summary \u5931\u8d25: {e$message}")
      stop(e)
    }
  )

  ctx$results$table1_summary_text <- txt
  cli::cli_alert_success(
    "table1_summary \u5b8c\u6210\uff0c\u5df2\u5199\u5165 ctx$results$table1_summary_text\uff08{nchar(txt)} \u5b57\u7b26\uff09"
  )

  ctx
}

register_block(
  "table1_summary",
  block_table1_summary,
  "\u4ece Table 1 xlsx \u751f\u6210\u4e2d\u6587\u4eba\u53e3\u5b66\u63cf\u8ff0\u6587\u672c"
)
