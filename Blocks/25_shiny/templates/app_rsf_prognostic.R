###############################################################################
#  RSF Prognostic Tool — Endometriosis Recurrence
#  UI 风格对齐文献站: https://webcalcula.shinyapps.io/RSF-model_pro/
#  预测: randomForestSRC rfsrc；事件概率 = 1 - S(t)
###############################################################################
library(shiny)
library(randomForestSRC)
library(ggplot2)

`%||%` <- function(x, y) if (is.null(x) || !length(x)) y else x

load("shiny_staging.RData")
load("df_train_RData.RData")
load("evalresult_rsf.RData")
if (!exists("shiny_staging") && exists("staged")) shiny_staging <- staged
if (!exists("shiny_staging")) stop("shiny_staging.RData must contain shiny_staging")
if (!exists("final_rsf")) stop("evalresult_rsf.RData must contain final_rsf")

final_model <- final_rsf
feats <- shiny_staging$model_features %||% shiny_staging$Final_Features
feats <- as.character(feats)
feats <- feats[nzchar(feats)]
if (!length(feats) && !is.null(final_model$xvar.names)) {
  feats <- as.character(final_model$xvar.names)
}
disease <- as.character(shiny_staging$disease_lbl %||% "Endometriosis Recurrence")[1L]
disease_lab <- gsub("_", " ", disease, fixed = TRUE)
hor_main <- as.numeric(shiny_staging$surv_horizon %||% 48)[1L]
if (!is.finite(hor_main)) hor_main <- 48
## 多时点展示（类似参考站 5/8/10 年）
horizons <- unique(as.numeric(c(12, 24, 36, hor_main)))
horizons <- sort(horizons[is.finite(horizons) & horizons > 0])
risk_hi <- as.numeric(shiny_staging$risk_high %||% 70)[1L]
risk_lo <- as.numeric(shiny_staging$risk_low %||% 30)[1L]

if (!"Group" %in% names(df_train) && "fustatus" %in% names(df_train)) {
  names(df_train)[names(df_train) == "fustatus"] <- "Group"
}

.defaults <- lapply(feats, function(v) {
  x <- df_train[[v]]
  if (is.null(x)) return(list(kind = "numeric", value = 0))
  if (is.numeric(x) && !is.factor(x)) {
    list(kind = "numeric", value = as.numeric(stats::median(x, na.rm = TRUE)))
  } else {
    x <- as.character(x)
    x <- x[!is.na(x) & nzchar(x)]
    lv <- sort(unique(x))
    tab <- sort(table(x), decreasing = TRUE)
    list(kind = "factor", value = names(tab)[1], levels = lv)
  }
})
names(.defaults) <- feats

.ui_inputs <- lapply(feats, function(v) {
  lab <- gsub("_", " ", v, fixed = TRUE)
  d <- .defaults[[v]]
  if (identical(d$kind, "numeric")) {
    numericInput(v, lab, value = d$value, width = "100%")
  } else {
    selectInput(v, lab, choices = d$levels, selected = d$value, width = "100%")
  }
})

.css <- HTML("
  body { font-family: 'Segoe UI', Helvetica, Arial, sans-serif; }
  .navbar-default { background-color: #1B4F72; border-color: #154360; }
  .navbar-default .navbar-brand, .navbar-default .navbar-nav > li > a { color: #ECF0F1 !important; }
  .navbar-default .navbar-nav > .active > a {
    background-color: #154360 !important; color: #fff !important;
  }
  .hero-box {
    background: linear-gradient(135deg, #1B4F72 0%, #2980B9 100%);
    color: #fff; padding: 28px 32px; border-radius: 8px; margin-bottom: 24px;
  }
  .hero-box h3 { margin-top: 0; font-weight: 600; }
  .step-title { color: #1B4F72; font-weight: 600; margin-top: 8px; }
  .result-card {
    background: #F8FBFF; border: 1px solid #D4E6F1; border-radius: 8px;
    padding: 18px 20px; margin-top: 12px;
  }
  .prob-big { font-size: 1.8em; color: #1B4F72; font-weight: 700; margin: 6px 0; }
  .risk-high { color: #C0392B; font-weight: 700; }
  .risk-med { color: #D68910; font-weight: 700; }
  .risk-low { color: #1E8449; font-weight: 700; }
  .btn-predict {
    background-color: #1B4F72; border-color: #154360; font-size: 1.05em;
    padding: 10px 28px; margin-top: 8px;
  }
  .btn-predict:hover { background-color: #154360; }
  .note { color: #5D6D7E; font-size: 0.92em; line-height: 1.45; }
")

ui <- navbarPage(
  title = "RSF Prognostic Tool",
  id = "main_nav",
  header = tags$head(tags$style(.css)),
  tabPanel(
    "Model Overview",
    fluidRow(
      column(
        10, offset = 1,
        div(
          class = "hero-box",
          h3("Model Introduction"),
          p(HTML(paste0(
            "This web-based prognostic tool estimates the risk of <b>", disease_lab,
            "</b> after surgery using a <b>Random Survival Forest (RSF)</b> model. ",
            "Enter clinical features on the <b>Survival Prediction</b> tab and click ",
            "<b>Predict</b> to obtain individualized recurrence probabilities at ",
            paste(horizons, collapse = "/"), " months, together with a survival curve ",
            "and the submitted feature values."
          )))
        ),
        h4(class = "step-title", "Model details"),
        tags$ul(
          tags$li(paste0("Algorithm: Random Survival Forest (randomForestSRC)")),
          tags$li(paste0("Primary evaluation horizon: ", hor_main, " months")),
          tags$li(paste0("Displayed horizons: ", paste(paste0(horizons, " mo"), collapse = ", "))),
          tags$li(paste0("Features (", length(feats), "): ", paste(gsub("_", " ", feats), collapse = ", "))),
          tags$li("Risk bands (event probability at primary horizon): high ≥70%, medium 30–70%, low <30%.")
        ),
        p(class = "note",
          "For research / educational use. Predictions do not replace clinical judgment.")
      )
    )
  ),
  tabPanel(
    "Survival Prediction",
    fluidRow(
      column(
        10, offset = 1,
        h3(class = "step-title", "Prediction Analysis"),
        p("Please enter the patient's clinical variables below and click the ",
          tags$b("Predict"), " button to generate individual results."),
        hr(),
        h4(class = "step-title", "Step 1: Patient Clinical Features"),
        fluidRow(
          lapply(seq_along(.ui_inputs), function(i) {
            column(width = 4, .ui_inputs[[i]])
          })
        ),
        hr(),
        h4(class = "step-title", "Step 2: Calculated Survival Probabilities"),
        actionButton("submitBtn", "Predict", icon = icon("calculator"),
                     class = "btn-primary btn-predict"),
        br(), br(),
        div(
          class = "result-card",
          h4("Survival / Recurrence Probability"),
          uiOutput("result_box"),
          plotOutput("surv_plot", height = "360px")
        ),
        br(),
        div(
          class = "result-card",
          h4("Feature Contribution (Original Values)"),
          tableOutput("feat_table"),
          p(class = "note",
            "Table lists the values submitted for prediction (original clinical scale).")
        )
      )
    )
  )
)

.build_newdata <- function(input) {
  df <- as.data.frame(
    lapply(feats, function(v) input[[v]]),
    stringsAsFactors = FALSE
  )
  names(df) <- feats
  for (cn in names(df)) {
    if (is.character(df[[cn]]) || is.logical(df[[cn]])) {
      lv <- if (cn %in% names(df_train)) levels(factor(df_train[[cn]])) else NULL
      df[[cn]] <- if (length(lv)) {
        factor(as.character(df[[cn]]), levels = lv)
      } else {
        factor(df[[cn]])
      }
    } else {
      df[[cn]] <- as.numeric(df[[cn]])
    }
  }
  df
}

.predict_rsf <- function(df) {
  pr <- predict(final_model, newdata = df)
  tms <- as.numeric(pr$time.interest)
  srow <- as.numeric(pr$survival[1, ])
  probs <- vapply(horizons, function(h) {
    j <- which.min(abs(tms - h))
    as.numeric(1 - srow[j])
  }, numeric(1L))
  names(probs) <- as.character(horizons)
  list(time = tms, surv = srow, probs = probs, pr = pr)
}

server <- function(input, output, session) {
  rv <- reactiveVal(NULL)

  observeEvent(input$submitBtn, {
    tryCatch({
      df <- .build_newdata(input)
      out <- .predict_rsf(df)
      out$df <- df
      rv(out)
    }, error = function(e) {
      rv(NULL)
      showNotification(conditionMessage(e), type = "error", duration = 10)
    })
  })

  output$result_box <- renderUI({
    out <- rv()
    if (is.null(out)) {
      return(p(class = "note", "Click Predict to compute individualized probabilities."))
    }
    p_main <- out$probs[as.character(hor_main)]
    if (!length(p_main) || !is.finite(p_main)) p_main <- out$probs[length(out$probs)]
    pct <- round(100 * p_main, 2)
    risk <- if (pct >= risk_hi) {
      tags$span(class = "risk-high", "high risk")
    } else if (pct < risk_lo) {
      tags$span(class = "risk-low", "low risk")
    } else {
      tags$span(class = "risk-med", "medium risk")
    }
    rows <- lapply(names(out$probs), function(h) {
      tags$li(sprintf(
        "%s-month recurrence probability: %.2f%%",
        h, 100 * as.numeric(out$probs[[h]])
      ))
    })
    tagList(
      div(class = "prob-big", sprintf("%.2f%% at %s months", pct, hor_main)),
      p(HTML(paste0("This patient is at ", as.character(risk),
                    " of ", disease_lab, "."))),
      tags$ul(rows)
    )
  })

  output$surv_plot <- renderPlot({
    out <- rv()
    if (is.null(out)) return(invisible(NULL))
    d <- data.frame(time = out$time, surv = out$surv)
    d <- d[is.finite(d$time) & is.finite(d$surv), , drop = FALSE]
    if (!nrow(d)) return(invisible(NULL))
    ggplot(d, aes(x = time, y = surv)) +
      geom_step(linewidth = 1.05, color = "#1B4F72") +
      geom_vline(xintercept = horizons, linetype = "dashed",
                 color = "#85929E", linewidth = 0.4) +
      scale_y_continuous(
        limits = c(0, 1), breaks = seq(0, 1, 0.2),
        labels = function(x) paste0(round(100 * x), "%")
      ) +
      labs(
        title = paste0("Predicted recurrence-free survival — ", disease_lab),
        x = "Time (months)", y = "Survival probability S(t)"
      ) +
      theme_minimal(base_size = 13) +
      theme(
        plot.title = element_text(face = "bold", color = "#1B4F72"),
        panel.grid.minor = element_blank()
      )
  })

  output$feat_table <- renderTable({
    out <- rv()
    if (is.null(out)) return(NULL)
    df <- out$df
    data.frame(
      Feature = gsub("_", " ", names(df), fixed = TRUE),
      Value = vapply(df, function(x) as.character(x)[1L], character(1L)),
      stringsAsFactors = FALSE
    )
  }, striped = TRUE, bordered = TRUE, hover = TRUE, width = "100%")
}

shinyApp(ui = ui, server = server)
