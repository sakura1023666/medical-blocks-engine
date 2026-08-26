###############################################################################
#  sem_data_prep — CHARLS 肌少症/抑郁/认知/衰弱变量（AWGS2019 + CESD + recall）
#  文献: Zhu 2025 J Adv Research — Sarcopenia → Depression → Cognitive → Frailty
###############################################################################

.sem_ctx_data <- function(ctx) {
  ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
}

.sem_awgs2019_sarcopenia <- function(d, bl) {
  grip_col <- bl$grip_col %||% "Grip_strength"
  asm_col <- bl$asm_col %||% "ASM"
  height_col <- bl$height_col %||% "Height"
  gait_col <- bl$gait_col %||% "Gait_speed"
  gender_col <- bl$gender_col %||% intersect(c("Gender", "Sex"), names(d))[1L]

  if (!grip_col %in% names(d)) grip_col <- grep("grip|handgrip", names(d), ignore.case = TRUE, value = TRUE)[1L]
  if (!asm_col %in% names(d)) asm_col <- grep("^ASM|appendicular", names(d), ignore.case = TRUE, value = TRUE)[1L]
  if (!height_col %in% names(d)) height_col <- grep("^Height|height_cm", names(d), ignore.case = TRUE, value = TRUE)[1L]
  if (!gait_col %in% names(d)) gait_col <- grep("gait|walk.*speed", names(d), ignore.case = TRUE, value = TRUE)[1L]

  d$Grip_strength <- if (!is.null(grip_col) && grip_col %in% names(d))
    suppressWarnings(as.numeric(d[[grip_col]])) else NA_real_
  d$ASM <- if (!is.null(asm_col) && asm_col %in% names(d))
    suppressWarnings(as.numeric(d[[asm_col]])) else NA_real_
  d$Height <- if (!is.null(height_col) && height_col %in% names(d))
    suppressWarnings(as.numeric(d[[height_col]])) else NA_real_
  d$Gait_speed <- if (!is.null(gait_col) && gait_col %in% names(d))
    suppressWarnings(as.numeric(d[[gait_col]])) else NA_real_

  if (length(d$Height) && any(!is.na(d$Height)) && median(d$Height, na.rm = TRUE) > 10) d$Height <- d$Height / 100
  d$SMI <- d$ASM / (pmax(d$Height, 0.5)^2)

  male <- if (!is.null(gender_col) && gender_col %in% names(d)) {
    g <- toupper(as.character(d[[gender_col]]))
    ifelse(g %in% c("M", "MALE", "1", "男"), TRUE,
      ifelse(g %in% c("F", "FEMALE", "2", "女"), FALSE, NA))
  } else NA

  mass_cut_m <- bl$smi_cut_male %||% 7.0
  mass_cut_f <- bl$smi_cut_female %||% 5.7
  grip_cut_m <- bl$grip_cut_male %||% 28
  grip_cut_f <- bl$grip_cut_female %||% 18
  gait_cut <- bl$gait_cut %||% 1.0

  d$Low_muscle_mass <- ifelse(
    is.na(male),
    as.integer(d$SMI < mean(c(mass_cut_m, mass_cut_f), na.rm = TRUE)),
    as.integer(ifelse(male, d$SMI < mass_cut_m, d$SMI < mass_cut_f))
  )
  d$Low_grip <- ifelse(
    is.na(male),
    as.integer(d$Grip_strength < mean(c(grip_cut_m, grip_cut_f), na.rm = TRUE)),
    as.integer(ifelse(male, d$Grip_strength < grip_cut_m, d$Grip_strength < grip_cut_f))
  )
  d$Low_gait <- as.integer(!is.na(d$Gait_speed) & d$Gait_speed <= gait_cut)
  d$Sarcopenia <- as.integer(d$Low_muscle_mass == 1L & (d$Low_grip == 1L | d$Low_gait == 1L))
  d$Sarcopenia_status <- ifelse(d$Sarcopenia == 1L, "Sarcopenia", "Non_sarcopenia")
  d
}

block_sem_data_prep <- function(ctx, ...) {
  bl <- ctx$config$sem_chain %||% list()
  data <- .sem_ctx_data(ctx)
  if (is.null(data)) stop("sem_data_prep: 无数据", call. = FALSE)

  d <- data
  d <- .sem_awgs2019_sarcopenia(d, bl)

  cesd_col <- bl$cesd_col %||% "CESD"
  if (!cesd_col %in% names(d)) cesd_col <- grep("^CESD|depression.*total", names(d), ignore.case = TRUE, value = TRUE)[1L]
  cesd_items <- bl$cesd_items %||% grep("^CESD[0-9]+$|^dc[0-9]+$", names(d), ignore.case = TRUE, value = TRUE)
  if (!is.null(cesd_col) && cesd_col %in% names(d)) {
    d$Depression_score <- suppressWarnings(as.numeric(d[[cesd_col]]))
  } else if (length(cesd_items) >= 3L) {
    d$Depression_score <- rowSums(sapply(d[cesd_items], function(x) suppressWarnings(as.numeric(x))), na.rm = TRUE)
  } else {
    d$Depression_score <- NA_real_
  }
  dep_cut <- bl$depression_cutoff %||% 10L
  d$Depression <- as.integer(!is.na(d$Depression_score) & d$Depression_score >= dep_cut)

  recall_cols <- bl$recall_cols %||% grep("recall|memory|orient|cog", names(d), ignore.case = TRUE, value = TRUE)
  recall_cols <- intersect(recall_cols, names(d))
  if (length(recall_cols) >= 1L) {
    d$Cognitive_score <- rowMeans(sapply(d[recall_cols], function(x) suppressWarnings(as.numeric(x))), na.rm = TRUE)
  } else if ("Cognitive_score" %in% names(d)) {
    d$Cognitive_score <- suppressWarnings(as.numeric(d$Cognitive_score))
  } else {
    d$Cognitive_score <- NA_real_
  }

  event_var <- bl$event_var %||% "Frailty_event"
  time_var <- bl$time_var %||% "Frailty_time"
  if (!event_var %in% names(d) && "fustatus" %in% names(d)) {
    d[[event_var]] <- as.integer(suppressWarnings(as.numeric(d$fustatus)) >= 1L)
  }
  if (!time_var %in% names(d) && "futime" %in% names(d)) {
    d[[time_var]] <- suppressWarnings(as.numeric(d$futime))
  }
  if (event_var %in% names(d)) {
    if (is.factor(d[[event_var]])) {
      case_lbl <- if (exists("pipeline_outcome_case_label", mode = "function"))
        pipeline_outcome_case_label(ctx$config) else "1"
      d[[event_var]] <- as.integer(as.character(d[[event_var]]) == case_lbl)
    } else {
      d[[event_var]] <- as.integer(suppressWarnings(as.numeric(d[[event_var]])) >= 1L)
    }
  }
  if (time_var %in% names(d)) d[[time_var]] <- suppressWarnings(as.numeric(d[[time_var]]))

  covs <- bl$covariate_vars %||% c("Age", "Gender", "Education", "Marital", "Smoking", "Drinking", "BMI")
  covs <- intersect(covs, names(d))
  for (cv in covs) {
    if (is.numeric(d[[cv]])) next
    d[[cv]] <- as.factor(d[[cv]])
  }

  ctx$data$cleaned <- d
  ctx$data$imputed <- d
  ctx$results$sem_data_prep <- list(
    n = nrow(d),
    n_sarcopenia = sum(d$Sarcopenia == 1L, na.rm = TRUE),
    n_depression = sum(d$Depression == 1L, na.rm = TRUE),
    n_frailty = if (event_var %in% names(d)) sum(d[[event_var]] == 1L, na.rm = TRUE) else NA_integer_,
    covariates = covs
  )
  cli::cli_alert_success("SEM 链式中介数据准备完成 (N={nrow(d)}, 肌少症={sum(d$Sarcopenia == 1L, na.rm = TRUE)})")
  ctx
}

register_block("sem_data_prep", block_sem_data_prep, "肌少症-抑郁-认知-衰弱变量准备")
