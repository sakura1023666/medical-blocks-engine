# Figure 1 文字。版式在 R/attrition_log.R 的 attrition_draw_outcome_panel。

.pv2_fig1_engine <- function() {
  if (exists("attrition_draw_outcome_figure", mode = "function")) return(invisible(TRUE))
  eng <- if (dir.exists("E:/01block/01Block-new-Final")) {
    "E:/01block/01Block-new-Final"
  } else {
    "/mnt/e/01block/01Block-new-Final"
  }
  source(file.path(eng, "R/attrition_log.R"), local = FALSE)
}

pv2_fig1_panel <- function(p) {
  .pv2_fig1_engine()
  attrition_draw_outcome_panel(p, family = "Times")
}

pv2_draw_fig1_three <- function(pdf_path, panels, csv_path = NULL) {
  .pv2_fig1_engine()
  if (is.null(csv_path)) {
    csv_path <- file.path(dirname(dirname(dirname(pdf_path))), "checkpoints", "Flowchart_attrition.csv")
  }
  attrition_draw_outcome_figure(
    pdf_path, panels, width = 15.6, height = 6.35, family = "Times", csv_path = csv_path
  )
}

pv2_fig1_default_panels <- function(n_death_nh = 1545L, n_alive_nh = 10513L,
                                    n_death_ch = 58L, n_alive_ch = 4010L,
                                    n_death_sh = 915L, n_alive_sh = 2981L,
                                    ## NHANES 顶格必须用标注周期合计，禁止换成未限制周期的全基线 nrow。
                                    ## 官方受访：1999–2018 = 101,316；2021–2023 = 11,933；合计 113,249。
                                    n_top_nh = 113249L,
                                    n_age45_nh = 36721L,
                                    n_inc_nh = 12058L) {
  fmt <- function(x) format(as.integer(x), big.mark = ",")
  n_age_ex_nh <- as.integer(n_top_nh) - as.integer(n_age45_nh)
  list(
    list(
      letter = "A  NHANES",
      top = paste0(
        "Participants in NHANES\n1999-2018 and 2021-2023\n(n = ",
        fmt(n_top_nh), ")"
      ),
      mid = paste0("Aged >= 45 years\n(n = ", fmt(n_age45_nh), ")"),
      inc = paste0("Participants included\n(n = ", fmt(n_inc_nh), ")"),
      side1 = paste0("Age < 45 years or\nmissing age (n = ", fmt(n_age_ex_nh), ")"),
      side2 = paste0(
        "1. Not dyslipidemia or\nunmatched (n = 23,055)\n",
        "2. Ineligible or missing\nfollow-up (n = 1,608)\n",
        "3. Missing or implausible\nsleep (n = 0)\n",
        "4. Missing survey weight\nWTMEC2YR, PSU or stratum (n = 0)"
      ),
      death = paste0("All-cause death\n(n = ", fmt(n_death_nh), ")"),
      alive = paste0("Alive\n(n = ", fmt(n_alive_nh), ")")
    ),
    list(
      letter = "B  CHARLS",
      top = "Participants in CHARLS 2011\n(n = 10,414)",
      mid = "Aged >= 45 years\n(n = 10,093)",
      inc = "Participants included\n(n = 4,068)",
      side1 = "Age < 45 years or\nmissing age (n = 321)",
      side2 = paste0(
        "1. Lipids normal or missing\n(n = 5,825)\n",
        "2. Missing sleep duration\nor death status (n = 200)"
      ),
      death = paste0("All-cause death\n(n = ", fmt(n_death_ch), ")"),
      alive = paste0("Alive\n(n = ", fmt(n_alive_ch), ")")
    ),
    list(
      letter = "C  SHHS",
      top = "Participants in SHHS visit 1\n(n = 5,802)",
      mid = "Aged >= 45 years\n(n = 5,460)",
      inc = "Participants included\n(n = 3,896)",
      side1 = "Age < 45 years or\nmissing age (n = 342)",
      side2 = paste0(
        "1. Lipids normal or missing\n(n = 1,476)\n",
        "2. Missing sleep duration\nor follow-up (n = 88)"
      ),
      death = paste0("All-cause death\n(n = ", fmt(n_death_sh), ")"),
      alive = paste0("Alive\n(n = ", fmt(n_alive_sh), ")")
    )
  )
}
