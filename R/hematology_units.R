###############################################################################
#  hematology_units.R — 血液学计数单位统一（K/uL vs /uL）
#
#  标准：复合指标与 Table 字典均以
#    WBC / Neutrophil / Lymphocyte / RBC / Monocyte … = K/uL（10^9/L）
#    Platelet_Count = K/uL（10^9/L，临床中位数通常 150–400）
#
#  自动校正：
#    · 非血小板细胞：median(x) > 50  ⇒ 视为 /uL，÷1000 → K/uL
#      （例如 WBC 7000 → 7.0）
#    · Platelet / Platelet_Count：
#        · 禁止用 med>50 规则（150–400 会被误 ÷1000 → 0.15–0.4，
#          导致 APRI/FIB4/EASIX/SII/HALP 等放大约 1000 倍）
#        · 仅当 median > 1000（真·/uL，如 150000）才 ÷1000
#        · 若 median < 5（典型误缩后 0.15–0.4）⇒ ×1000 恢复到 K/uL
#          （Mean_platelet_volume 等体积列不参与此恢复）
#
#  入口：
#    scale_hematology_vector(x, var_name = NULL)
#    scale_hematology_dataframe(df, verbose = TRUE)
#
#  由 R/utils.R 加载；index / trajectory 等共用，勿在各 block 内复制阈值逻辑。
###############################################################################

# 非血小板：med>50 → /1000
.HEMATOLOGY_CELL_THRESHOLD_KUL <- 50
# 血小板：仅 med>1000 才按 /uL 缩放（阈值勿低于临床常规百级）
.HEMATOLOGY_PLT_THRESHOLD_KUL  <- 1000
# 血小板：med 过低视为曾被误 ÷1000，×1000 恢复（ICU 队列中位数几乎不会 <5 K/uL）
.HEMATOLOGY_PLT_RECOVER_MAX_KUL <- 5

hematology_platelet_col_names <- function() {
  c("Platelet_Count", "PlateletCount", "Platelet", "PLT", "platelet_count", "platelets")
}

hematology_cell_col_names <- function() {
  c(
    "WBC", "Neutrophil_Count", "Lymphocytes", "Monocyte",
    "Eosinophil_Count", "Basophil_Count", "RBC",
    "NeutrophilCount", "Monocyte_Count", "Eosinophils", "Basophils"
  )
}

is_hematology_platelet_name <- function(var_name) {
  if (is.null(var_name) || !nzchar(as.character(var_name)[1L])) return(FALSE)
  nm <- as.character(var_name)[1L]
  # 体积/形态学列不是计数，勿按 Platelet_Count 规则缩放
  if (grepl("volume|mpv|width|distribution", nm, ignore.case = TRUE)) return(FALSE)
  tolower(nm) %in% tolower(hematology_platelet_col_names()) ||
    grepl("platelet", nm, ignore.case = TRUE)
}

#' 单列血细胞 → K/uL
#' @param x numeric vector
#' @param var_name 列名（用于区分 Platelet）
#' @return scaled numeric vector; attr "scaled"/"recovered" 标记是否改变
scale_hematology_vector <- function(x, var_name = NULL) {
  x <- suppressWarnings(as.numeric(x))
  med <- stats::median(x, na.rm = TRUE)
  if (!is.finite(med) || med <= 0) {
    attr(x, "scaled") <- FALSE
    attr(x, "recovered") <- FALSE
    return(x)
  }

  if (is_hematology_platelet_name(var_name)) {
    # 误 ÷1000 残留（~0.18）→ 恢复到 ~180
    if (med < .HEMATOLOGY_PLT_RECOVER_MAX_KUL) {
      x <- x * 1000
      attr(x, "scaled") <- FALSE
      attr(x, "recovered") <- TRUE
      return(x)
    }
    if (med > .HEMATOLOGY_PLT_THRESHOLD_KUL) {
      x <- x / 1000
      attr(x, "scaled") <- TRUE
      attr(x, "recovered") <- FALSE
      return(x)
    }
    attr(x, "scaled") <- FALSE
    attr(x, "recovered") <- FALSE
    return(x)
  }

  if (med > .HEMATOLOGY_CELL_THRESHOLD_KUL) {
    x <- x / 1000
    attr(x, "scaled") <- TRUE
    attr(x, "recovered") <- FALSE
  } else {
    attr(x, "scaled") <- FALSE
    attr(x, "recovered") <- FALSE
  }
  x
}

#' 数据框：按列名对血细胞统一到 K/uL
#' @param df data.frame
#' @param verbose 是否 cli 提示
#' @param columns 仅缩放这些列；NULL=自动识别常见血细胞列 + 含 platelet 的列
#' @return df
scale_hematology_dataframe <- function(df, verbose = TRUE, columns = NULL) {
  if (is.null(df) || !is.data.frame(df) || !ncol(df)) return(df)

  if (is.null(columns)) {
    known <- c(hematology_cell_col_names(), hematology_platelet_col_names())
    columns <- intersect(known, names(df))
    extra_plt <- names(df)[vapply(names(df), is_hematology_platelet_name, logical(1))]
    columns <- unique(c(columns, extra_plt))
  } else {
    columns <- intersect(as.character(columns), names(df))
  }
  if (!length(columns)) return(df)

  scaled <- character(0)
  recovered <- character(0)
  for (col in columns) {
    x <- scale_hematology_vector(df[[col]], var_name = col)
    did_scale <- isTRUE(attr(x, "scaled"))
    did_recover <- isTRUE(attr(x, "recovered"))
    attr(x, "scaled") <- NULL
    attr(x, "recovered") <- NULL
    df[[col]] <- x
    if (did_scale) scaled <- c(scaled, col)
    if (did_recover) recovered <- c(recovered, col)
  }

  if (isTRUE(verbose)) {
    if (length(scaled)) {
      msg <- paste0(
        "hematology_units: /uL → K/uL (÷1000): ",
        paste(scaled, collapse = ", ")
      )
      if (requireNamespace("cli", quietly = TRUE)) {
        cli::cli_alert_warning(msg)
      } else {
        message(msg)
      }
    }
    if (length(recovered)) {
      msg <- paste0(
        "hematology_units: 误缩恢复 ×1000 → K/uL: ",
        paste(recovered, collapse = ", ")
      )
      if (requireNamespace("cli", quietly = TRUE)) {
        cli::cli_alert_warning(msg)
      } else {
        message(msg)
      }
    }
  }
  df
}
