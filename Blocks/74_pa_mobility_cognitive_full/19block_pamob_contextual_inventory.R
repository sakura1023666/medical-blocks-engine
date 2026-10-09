###############################################################################
# pamob_contextual_inventory — 抽取 CHARLS da056/da057 + NHANES PA/PFQ/PIR
# 输出可用性矩阵、缺失率、四组分布（不做中介）
###############################################################################

block_pamob_contextual_inventory <- function(ctx, ...) {
  source(file.path(ctx$config$project$root %||% getwd(),
                   "Blocks/74_pa_mobility_cognitive_full/00pamob_common.R"), local = FALSE)
  .pamob_source_utils(ctx)
  bl <- pamob_cfg(ctx)
  root_data <- pamob_data_root(ctx)
  out_ms <- file.path(pamob_out_root(ctx), "Manuscript")
  out_tab <- pamob_tables_dir(ctx)
  dir.create(out_ms, recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(out_tab, "Contextual"), recursive = TRUE, showWarnings = FALSE)

  charls_dir <- file.path(root_data, "CHARLS")
  nh_dir <- file.path(root_data, "NHANES")
  wave <- as.integer(bl$baseline_wave %||% 2011L)[1L]

  # ---- 抽取 ----
  ctx_c <- pamob_extract_charls_contextual(charls_dir, wave = wave)
  ctx_n <- pamob_extract_nhanes_contextual(
    nh_dir,
    cycle = as.character(bl$nhanes_cycle %||% "H")[1L],
    source_file = as.character(bl$nhanes_source_file %||% "2013-2014")[1L]
  )
  if (!is.null(ctx_c)) {
    pamob_write_csv(ctx_c, file.path(out_tab, "Contextual", "CHARLS_contextual_person.csv"))
  }
  if (!is.null(ctx_n)) {
    pamob_write_csv(ctx_n, file.path(out_tab, "Contextual", "NHANES_contextual_person.csv"))
  }

  # ---- 可用性矩阵 ----
  avail <- list()
  .add_avail <- function(db, var, wave_lab, source, status, n_nonmiss = NA_integer_, n_total = NA_integer_) {
    avail[[length(avail) + 1L]] <<- data.frame(
      database = db, variable = var, wave = wave_lab, source = source,
      status = status,
      n_nonmiss = n_nonmiss, n_total = n_total,
      pct_miss = if (is.finite(n_total) && n_total > 0) round(100 * (1 - n_nonmiss / n_total), 1) else NA_real_,
      stringsAsFactors = FALSE
    )
  }
  if (!is.null(ctx_c)) {
    cfile <- attr(ctx_c, "community_file")
    for (v in setdiff(names(ctx_c), c("ID_h", "ctx_wave"))) {
      x <- ctx_c[[v]]
      is_comm <- grepl("^community_|^recreation_n_types$|^bus_", v)
      if (is_comm) {
        src <- if (!is.null(cfile) && nzchar(cfile)) {
          paste0("rawdata/", cfile, " (JB003/JB004/JB029) via communityID")
        } else {
          "Community questionnaire (file missing)"
        }
        st <- if (all(is.na(x))) "NOT_AVAILABLE_no_community_file" else "extracted_2011_Community"
      } else {
        src <- "rawdata/health_status_and_functioning-2011.dta (da056/da057)"
        st <- if (all(is.na(x))) "NOT_AVAILABLE_in_delivered_extract" else "extracted_2011_Health"
      }
      .add_avail("CHARLS", v, as.character(wave), src, st, sum(!is.na(x)), length(x))
    }
  } else {
    .add_avail("CHARLS", "da056/da057", as.character(wave), "Health dta", "EXTRACT_FAILED", 0L, 0L)
  }
  # CHARLS 无 NHANES 式 PA domain/purpose（仅有强度 da051–055）
  .add_avail(
    "CHARLS", "pa_activity_purpose_work_transport_recreation", as.character(wave),
    "Health da051–da055 intensity only (no purpose/domain items)",
    "NOT_AVAILABLE_no_purpose_items_in_CHARLS_2011", 0L, 0L
  )

  if (!is.null(ctx_n)) {
    for (v in setdiff(names(ctx_n), "SEQN")) {
      x <- ctx_n[[v]]
      src <- if (grepl("^pa_|work_met|transport_met|recreation_met", v)) "D03_physical_activity.csv"
      else if (grepl("PIR", v)) "D01_baseline PIR"
      else if (grepl("^(has_routine_|healthcare_visits_|overnight_|seen_mental_)", v)) "HUQ_H.XPT"
      else if (grepl("^(covered_by_|private_|medicare|medicaid|no_insurance_|insurance_covers_)", v)) "HIQ_H.XPT"
      else "PFQ_H.XPT"
      .add_avail("NHANES", v, "2013-2014 (H)", src, "extracted", sum(!is.na(x)), length(x))
    }
  }
  avail_df <- do.call(rbind, avail)
  dir.create(file.path(out_tab, "Contextual"), recursive = TRUE, showWarnings = FALSE)
  pamob_write_csv(avail_df, file.path(out_tab, "Contextual", "Table_S_Contextual_variable_inventory.csv"))
  pamob_write_csv(avail_df, file.path(out_tab, "Contextual", "availability_matrix.csv"))

  # ---- 并入分析基线并做四组分布 ----
  dist_rows <- list()
  discordant_rows <- list()

  # CHARLS：phenotype baseline from long/base
  long <- ctx$data$pamob_charls_long
  base <- ctx$data$pamob_charls_baseline
  if (!is.null(long) && !is.null(ctx_c)) {
    b <- long[long$wave == wave & !duplicated(long$ID_h), , drop = FALSE]
    if (!nrow(b) && !is.null(base)) {
      b <- base
      b$phenotype <- factor(b$phenotype_bl, levels = unname(pamob_phenotype_labels()))
    }
    b <- merge(b, ctx_c, by = "ID_h", all.x = TRUE)
    b$phenotype <- factor(as.character(b$phenotype %||% b$phenotype_bl),
                          levels = unname(pamob_phenotype_labels()))
    ctx$data$pamob_charls_contextual <- b
    bin_vars <- c("social_friend", "social_club_or_cards", "social_community_org",
                  "social_volunteer", "social_help_or_care", "social_any", "social_none",
                  "community_recreation_facility", "community_public_transport")
    cont_vars <- c("social_n_types", "recreation_n_types", "bus_lines_n", "bus_stop_km")
    for (v in intersect(bin_vars, names(b))) {
      for (ph in levels(b$phenotype)) {
        idx <- as.character(b$phenotype) == ph
        xx <- b[[v]][idx]
        n <- sum(idx)
        nm <- sum(!is.na(xx))
        k <- sum(xx == 1L, na.rm = TRUE)
        dist_rows[[length(dist_rows) + 1L]] <- data.frame(
          database = "CHARLS", variable = v, phenotype = ph,
          n_stratum = n, n_nonmiss = nm,
          pct_yes = if (nm) round(100 * k / nm, 1) else NA_real_,
          mean = NA_real_, sd = NA_real_,
          stringsAsFactors = FALSE
        )
      }
    }
    for (v in intersect(cont_vars, names(b))) {
      for (ph in levels(b$phenotype)) {
        xx <- suppressWarnings(as.numeric(b[[v]][as.character(b$phenotype) == ph]))
        xx <- xx[!is.na(xx)]
        dist_rows[[length(dist_rows) + 1L]] <- data.frame(
          database = "CHARLS", variable = v, phenotype = ph,
          n_stratum = sum(as.character(b$phenotype) == ph),
          n_nonmiss = length(xx),
          pct_yes = NA_real_,
          mean = if (length(xx)) mean(xx) else NA_real_,
          sd = if (length(xx) > 1) stats::sd(xx) else NA_real_,
          stringsAsFactors = FALSE
        )
      }
    }
    # 主比较：同 mobility 维内比 PA（IP vs AP；AL vs IL）；AL vs IP 仅作次要保留
    .ctx_pairs <- list(
      list(role = "primary_mobility_preserved_PA",
           contrast = "Inactive_preserved vs Active_preserved",
           ph = c("Inactive_preserved", "Active_preserved")),
      list(role = "primary_mobility_limited_PA",
           contrast = "Active_limited vs Inactive_limited",
           ph = c("Active_limited", "Inactive_limited")),
      list(role = "secondary_cross_discordant",
           contrast = "Active_limited vs Inactive_preserved",
           ph = c("Active_limited", "Inactive_preserved"))
    )
    for (pr in .ctx_pairs) {
      for (v in intersect(c(bin_vars, cont_vars), names(b))) {
        for (ph in pr$ph) {
          xx <- b[[v]][as.character(b$phenotype) == ph]
          if (v %in% bin_vars) {
            nm <- sum(!is.na(xx)); k <- sum(xx == 1L, na.rm = TRUE)
            discordant_rows[[length(discordant_rows) + 1L]] <- data.frame(
              database = "CHARLS", contrast = pr$contrast, role = pr$role,
              variable = v, phenotype = ph,
              n_nonmiss = nm, estimate = if (nm) round(100 * k / nm, 1) else NA_real_,
              metric = "pct_yes", stringsAsFactors = FALSE
            )
          } else {
            xv <- suppressWarnings(as.numeric(xx)); xv <- xv[!is.na(xv)]
            discordant_rows[[length(discordant_rows) + 1L]] <- data.frame(
              database = "CHARLS", contrast = pr$contrast, role = pr$role,
              variable = v, phenotype = ph,
              n_nonmiss = length(xv), estimate = if (length(xv)) mean(xv) else NA_real_,
              metric = "mean", stringsAsFactors = FALSE
            )
          }
        }
      }
    }
  }

  # NHANES DSST main
  d_ds <- ctx$data$pamob_nhanes_dsst
  if (!is.null(d_ds) && !is.null(ctx_n) && nrow(d_ds)) {
    d <- merge(d_ds, ctx_n, by = "SEQN", all.x = TRUE, suffixes = c("", "_ctx"))
    # prefer contextual PIR if analytic missing
    if ("PIR_ctx" %in% names(d) && "PIR" %in% names(d)) {
      d$PIR <- ifelse(is.na(d$PIR), d$PIR_ctx, d$PIR)
    } else if ("PIR_ctx" %in% names(d) && !"PIR" %in% names(d)) {
      d$PIR <- d$PIR_ctx
    }
    ctx$data$pamob_nhanes_contextual <- d
    bin_n <- c("pa_domain_work", "pa_domain_transport", "pa_domain_recreation",
               "pa_work_yes", "pa_transport_yes", "pa_recreation_yes",
               "social_event_difficulty", "leisure_home_difficulty",
               "work_limitation", "assistive_walk_equipment", "special_healthcare_equipment",
               "has_routine_healthcare_place", "overnight_hospital_past_year",
               "seen_mental_health_past_year", "covered_by_health_insurance",
               "private_insurance", "medicare", "medicaid",
               "no_insurance_spell_past_year", "insurance_covers_prescriptions")
    cont_n <- c("PIR", "work_met", "transport_met", "recreation_met",
                "healthcare_visits_past_year")
    d$phenotype <- factor(as.character(d$phenotype), levels = unname(pamob_phenotype_labels()))
    for (v in intersect(bin_n, names(d))) {
      for (ph in levels(d$phenotype)) {
        xx <- d[[v]][as.character(d$phenotype) == ph]
        nm <- sum(!is.na(xx)); k <- sum(xx == 1L, na.rm = TRUE)
        dist_rows[[length(dist_rows) + 1L]] <- data.frame(
          database = "NHANES", variable = v, phenotype = ph,
          n_stratum = sum(as.character(d$phenotype) == ph),
          n_nonmiss = nm,
          pct_yes = if (nm) round(100 * k / nm, 1) else NA_real_,
          mean = NA_real_, sd = NA_real_,
          stringsAsFactors = FALSE
        )
      }
    }
    for (v in intersect(cont_n, names(d))) {
      for (ph in levels(d$phenotype)) {
        xx <- suppressWarnings(as.numeric(d[[v]][as.character(d$phenotype) == ph]))
        xx <- xx[!is.na(xx)]
        dist_rows[[length(dist_rows) + 1L]] <- data.frame(
          database = "NHANES", variable = v, phenotype = ph,
          n_stratum = sum(as.character(d$phenotype) == ph),
          n_nonmiss = length(xx), pct_yes = NA_real_,
          mean = if (length(xx)) mean(xx) else NA_real_,
          sd = if (length(xx) > 1) stats::sd(xx) else NA_real_,
          stringsAsFactors = FALSE
        )
      }
    }
    .ctx_pairs_n <- list(
      list(role = "primary_mobility_preserved_PA",
           contrast = "Inactive_preserved vs Active_preserved",
           ph = c("Inactive_preserved", "Active_preserved")),
      list(role = "primary_mobility_limited_PA",
           contrast = "Active_limited vs Inactive_limited",
           ph = c("Active_limited", "Inactive_limited")),
      list(role = "secondary_cross_discordant",
           contrast = "Active_limited vs Inactive_preserved",
           ph = c("Active_limited", "Inactive_preserved"))
    )
    for (pr in .ctx_pairs_n) {
      for (v in intersect(c(bin_n, cont_n), names(d))) {
        for (ph in pr$ph) {
          xx <- d[[v]][as.character(d$phenotype) == ph]
          if (v %in% bin_n) {
            nm <- sum(!is.na(xx)); k <- sum(xx == 1L, na.rm = TRUE)
            discordant_rows[[length(discordant_rows) + 1L]] <- data.frame(
              database = "NHANES", contrast = pr$contrast, role = pr$role,
              variable = v, phenotype = ph,
              n_nonmiss = nm, estimate = if (nm) round(100 * k / nm, 1) else NA_real_,
              metric = "pct_yes", stringsAsFactors = FALSE
            )
          } else {
            xv <- suppressWarnings(as.numeric(xx)); xv <- xv[!is.na(xv)]
            discordant_rows[[length(discordant_rows) + 1L]] <- data.frame(
              database = "NHANES", contrast = pr$contrast, role = pr$role,
              variable = v, phenotype = ph,
              n_nonmiss = length(xv), estimate = if (length(xv)) mean(xv) else NA_real_,
              metric = "mean", stringsAsFactors = FALSE
            )
          }
        }
      }
    }
  }

  dist <- if (length(dist_rows)) do.call(rbind, dist_rows) else {
    data.frame(database = character(), variable = character(), phenotype = character(),
               n_stratum = integer(), n_nonmiss = integer(), pct_yes = numeric(),
               mean = numeric(), sd = numeric(), stringsAsFactors = FALSE)
  }
  disc <- if (length(discordant_rows)) do.call(rbind, discordant_rows) else dist[0, ]
  dir.create(file.path(out_tab, "Contextual"), recursive = TRUE, showWarnings = FALSE)
  pamob_write_csv(dist, file.path(out_tab, "Contextual", "Table_S_Contextual_by_phenotype.csv"))
  pamob_write_csv(disc, file.path(out_tab, "Contextual", "Table_S_Contextual_discordant_contrast.csv"))
  pamob_write_csv(dist, file.path(out_tab, "Contextual", "by_phenotype.csv"))
  pamob_write_csv(disc, file.path(out_tab, "Contextual", "paired_contrasts_primary_and_secondary.csv"))
  # 主比较子集（交付 Table S9）
  disc_primary <- if (nrow(disc) && "role" %in% names(disc)) {
    disc[grepl("^primary_", disc$role), , drop = FALSE]
  } else disc
  pamob_write_csv(disc_primary, file.path(out_tab, "Contextual", "primary_mobility_stratum_PA_contrasts.csv"))

  # ---- Manuscript note ----
  md <- c(
    "# Contextual profiling — variable extraction & four-group distribution",
    "",
    "Teacher request fulfilled at inventory+distribution stage (**no mediation/interaction**).",
    "",
    "## Primary contextual contrasts (updated)",
    "1. **Inactive–preserved vs Active–preserved** (mobility both preserved): correlates of inactivity.",
    "2. **Active–limited vs Inactive–limited** (mobility both limited): correlates of staying active.",
    "3. Active–limited vs Inactive–preserved retained only as **secondary** (crosses both PA and mobility).",
    "",
    "## CHARLS (baseline wave 2011)",
    "- Source: `health_status_and_functioning-2011.dta` items `da056s1–s12` / `da057_*`.",
    "- Community recreation & public transport via `community-2011.dta` / `communityID`.",
    "",
    "## NHANES (2013–2014, DSST main sample merge)",
    "- PA domains, PFQ, HUQ/HIQ healthcare access, PIR.",
    "- No community-level recreation/transport module in NHANES.",
    "",
    paste0("- Availability rows: ", nrow(avail_df)),
    paste0("- Distribution rows: ", nrow(dist)),
    paste0("- Contrast rows (all roles): ", nrow(disc), "; primary: ", nrow(disc_primary)),
    "",
    "## Gate for next module",
    "Still **do not** run mediation until confirmed."
  )
  writeLines(md, file.path(out_ms, "Contextual_variable_inventory.md"))

  ctx$results$pamob_contextual_inventory <- list(
    availability = avail_df, distribution = dist, discordant = disc,
    n_charls = if (!is.null(ctx_c)) nrow(ctx_c) else 0L,
    n_nhanes = if (!is.null(ctx_n)) nrow(ctx_n) else 0L
  )
  cli::cli_alert_success(
    "contextual extract: CHARLS n={if (!is.null(ctx_c)) nrow(ctx_c) else 0}; NHANES n={if (!is.null(ctx_n)) nrow(ctx_n) else 0}; dist rows={nrow(dist)}"
  )
  ctx
}

register_block("pamob_contextual_inventory", block_pamob_contextual_inventory, "Contextual inventory")
