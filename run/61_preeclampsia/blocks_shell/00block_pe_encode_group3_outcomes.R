###############################################################################
#  pe_encode_group3_outcomes — 子痫课题：Disease(3类) / 早产 / GDM 编码
#  课题壳（run/61_preeclampsia/blocks_shell/），不进 Blocks 方法族。
#
#  require_data = ctx$data$cleaned %||% ctx$data$raw
#  写: ctx$data$cleaned
#  Disease_detail = 原始 6 水平；Disease = 三组合并英文水平
###############################################################################

block_pe_encode_group3_outcomes <- function(ctx, ...) {
  data <- ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$mapped
  if (is.null(data) || !is.data.frame(data)) {
    stop("pe_encode_group3_outcomes: 无 cleaned/raw 数据", call. = FALSE)
  }
  if (!"Disease" %in% names(data)) {
    stop("pe_encode_group3_outcomes: 缺少 Disease 列", call. = FALSE)
  }

  # 原始 6 水平保留
  if (!"Disease_detail" %in% names(data)) {
    data$Disease_detail <- data$Disease
  }
  dis <- as.character(data$Disease_detail)

  # 三组合并 → Disease（英文）
  # Non-preeclampsia = Normal + Gestational Hypertension + Chronic hypertension
  # Preeclampsia     = Preeclampsia + Severe Preeclampsia
  # CH with PE       = Chronic hypertension with preeclampsia（单独）
  data$Disease <- dplyr::case_when(
    dis == "Chronic hypertension with preeclampsia" ~
      "Chronic hypertension with preeclampsia",
    dis %in% c("Preeclampsia", "Severe Preeclampsia") ~
      "Preeclampsia",
    TRUE ~ "Non-preeclampsia"
  )
  data$Disease <- factor(
    data$Disease,
    levels = c(
      "Non-preeclampsia",
      "Preeclampsia",
      "Chronic hypertension with preeclampsia"
    )
  )

  if (!"Gestational_Week_Delivery" %in% names(data)) {
    stop("pe_encode_group3_outcomes: 缺少 Gestational_Week_Delivery", call. = FALSE)
  }
  # 分析用结局（logistic outcome_column）
  data$Preterm34 <- factor(
    ifelse(as.numeric(data$Gestational_Week_Delivery) < 34, "Preterm34", "Term34"),
    levels = c("Term34", "Preterm34")
  )
  # 表用描述列（引擎会剔除 outcome_column，故不能直接用 Preterm34 进 S1/Table1）
  # 水平 Yes/No，避免出现 Preterm lt34 / Preterm34 / Term34 叠名
  data$Preterm_delivery <- factor(
    ifelse(as.numeric(data$Gestational_Week_Delivery) < 34, "Yes", "No"),
    levels = c("No", "Yes")
  )

  if (!"GDM" %in% names(data)) stop("pe_encode_group3_outcomes: 缺少 GDM", call. = FALSE)
  g <- data$GDM
  if (is.factor(g) || is.character(g)) {
    data$GDM01 <- as.integer(grepl("^\\s*Yes", as.character(g), ignore.case = TRUE))
  } else {
    data$GDM01 <- as.integer(as.numeric(g) >= 1)
  }
  # GDM 已可进 Table1；统一保留因子水平供描述
  if (!is.factor(data$GDM)) {
    data$GDM <- factor(
      ifelse(grepl("^\\s*Yes", as.character(data$GDM), ignore.case = TRUE), "Yes", "No"),
      levels = c("No", "Yes")
    )
  }

  data$PE_vs_SPE <- NA_character_
  data$PE_vs_SPE[dis == "Preeclampsia"] <- "PE"
  data$PE_vs_SPE[dis == "Severe Preeclampsia"] <- "SPE"
  data$PE_vs_SPE <- factor(data$PE_vs_SPE, levels = c("PE", "SPE"))

  # Is_Twin → Yes/No
  if ("Is_Twin" %in% names(data)) {
    tw <- data$Is_Twin
    if (is.logical(tw)) {
      data$Is_Twin <- factor(ifelse(tw, "Yes", "No"), levels = c("No", "Yes"))
    } else if (is.factor(tw) || is.character(tw)) {
      twc <- tolower(trimws(as.character(tw)))
      data$Is_Twin <- factor(
        dplyr::case_when(
          twc %in% c("true", "yes", "1", "y") ~ "Yes",
          twc %in% c("false", "no", "0", "n") ~ "No",
          TRUE ~ NA_character_
        ),
        levels = c("No", "Yes")
      )
    } else {
      data$Is_Twin <- factor(
        ifelse(as.numeric(tw) >= 1, "Yes", "No"),
        levels = c("No", "Yes")
      )
    }
  }

  # Parity 强制连续
  if ("Parity" %in% names(data)) {
    data$Parity <- suppressWarnings(as.numeric(as.character(data$Parity)))
  }

  # 新生儿体重：双胎常写 "1100/1000" → 取第一胎数值（g）供 Table1
  if ("Newborn_Weight" %in% names(data)) {
    nw <- trimws(as.character(data$Newborn_Weight))
    nw <- sub("/.*$", "", nw)
    data$Newborn_Weight_g <- suppressWarnings(as.numeric(nw))
    z <- which(is.finite(data$Newborn_Weight_g) & data$Newborn_Weight_g <= 0)
    if (length(z)) data$Newborn_Weight_g[z] <- NA_real_
  }

  # Apgar 数值化（表描述用）
  for (ac in c("APGAR_1min", "APGAR_5min", "APGAR_1min_numeric", "APGAR_5min_numeric")) {
    if (!ac %in% names(data)) next
    data[[ac]] <- suppressWarnings(as.numeric(as.character(data[[ac]])))
  }

  # 二分类结局：Apgar <8；新生儿体重 <1500g；剖宫产
  if ("APGAR_1min" %in% names(data)) {
    data$Apgar1_lt8 <- as.integer(is.finite(data$APGAR_1min) & data$APGAR_1min < 8)
  }
  if ("APGAR_5min" %in% names(data)) {
    data$Apgar5_lt8 <- as.integer(is.finite(data$APGAR_5min) & data$APGAR_5min < 8)
  }
  if ("Newborn_Weight_g" %in% names(data)) {
    data$Newborn_lt1500 <- as.integer(
      is.finite(data$Newborn_Weight_g) & data$Newborn_Weight_g < 1500
    )
    data$Newborn_lt2000 <- as.integer(
      is.finite(data$Newborn_Weight_g) & data$Newborn_Weight_g < 2000
    )
  }
  if ("Delivery_Mode" %in% names(data)) {
    dm <- as.character(data$Delivery_Mode)
    data$Cesarean01 <- as.integer(grepl("cesarean", dm, ignore.case = TRUE))
  }

  # ROC / 对齐终稿：Any PE（PE + CH+PE）vs Non-PE
  data$PE01 <- as.integer(as.character(data$Disease) != "Non-preeclampsia")

  bmi_cols <- grep("_BMI$", names(data), value = TRUE)
  for (bc in bmi_cols) {
    z <- which(data[[bc]] == 0)
    if (length(z)) data[[bc]][z] <- NA_real_
  }
  wt_cols <- setdiff(grep("_Weight$", names(data), value = TRUE), "Newborn_Weight")
  for (wc in wt_cols) {
    z <- which(data[[wc]] == 0)
    if (length(z)) data[[wc]][z] <- NA_real_
  }

  ctx$data$cleaned <- data
  ctx$data$raw <- data
  ctx$results$pe_encode <- list(
    n = nrow(data),
    disease = as.list(table(data$Disease, useNA = "ifany")),
    disease_detail = as.list(table(data$Disease_detail, useNA = "ifany")),
    preterm34 = as.list(table(data$Preterm34, useNA = "ifany")),
    gdm01 = as.list(table(data$GDM01, useNA = "ifany"))
  )
  dis_txt <- paste(names(table(data$Disease)), as.integer(table(data$Disease)),
                   sep = "=", collapse = ", ")
  cli::cli_alert_success("pe_encode: n={nrow(data)}; Disease: {dis_txt}")
  ctx
}

register_block(
  "pe_encode_group3_outcomes",
  block_pe_encode_group3_outcomes,
  "子痫：Disease三分类/早产/GDM编码壳"
)
