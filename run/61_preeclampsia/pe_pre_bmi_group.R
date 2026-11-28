# 孕前 BMI 中国标准分组（供亚组森林图）
# 四分类：<18.5 / 18.5–23.9 / 24.0–27.9 / ≥28.0
# 三分类（稀有结局回退）：<24.0（低体重+正常）/ 24.0–27.9 / ≥28.0

.pe_pre_bmi_group_china4 <- function(bmi) {
  bmi <- suppressWarnings(as.numeric(bmi))
  out <- rep(NA_character_, length(bmi))
  ok <- is.finite(bmi)
  out[ok & bmi < 18.5] <- "<18.5"
  out[ok & bmi >= 18.5 & bmi < 24] <- "18.5-23.9"
  out[ok & bmi >= 24 & bmi < 28] <- "24.0-27.9"
  out[ok & bmi >= 28] <- "\u226528.0"
  factor(out, levels = c("<18.5", "18.5-23.9", "24.0-27.9", "\u226528.0"))
}

.pe_pre_bmi_group_china3 <- function(bmi) {
  # 低体重并入正常：<24 / 24–27.9 / ≥28
  bmi <- suppressWarnings(as.numeric(bmi))
  out <- rep(NA_character_, length(bmi))
  ok <- is.finite(bmi)
  out[ok & bmi < 24] <- "<24.0"
  out[ok & bmi >= 24 & bmi < 28] <- "24.0-27.9"
  out[ok & bmi >= 28] <- "\u226528.0"
  factor(out, levels = c("<24.0", "24.0-27.9", "\u226528.0"))
}

.pe_add_pre_bmi_group <- function(data, scheme = c("china4", "china3")) {
  scheme <- match.arg(scheme)
  if (!is.data.frame(data) || !"Pre_BMI" %in% names(data)) return(data)
  data$Pre_BMI_Group <- if (identical(scheme, "china4")) {
    .pe_pre_bmi_group_china4(data$Pre_BMI)
  } else {
    .pe_pre_bmi_group_china3(data$Pre_BMI)
  }
  data
}

.pe_is_rare_outcome <- function(oc) {
  oc %in% c(
    "Preterm34", "Apgar1_lt8", "Apgar5_lt8",
    "Newborn_lt1500", "Newborn_lt2000"
  )
}
