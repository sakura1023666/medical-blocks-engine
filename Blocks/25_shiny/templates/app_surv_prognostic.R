###############################################################################
#  Survival Prognostic Tool — UI 对齐 https://webcalcula.shinyapps.io/RSF-model_pro/
#  支持：rsf / ridge_cox / enet_cox / xgbsurv / gbmsurv / coxboost
#  由 block_shiny_ml_app 写入课题 ShinyApp/app.R（对象名 shiny_staging）
###############################################################################
library(shiny)
library(ggplot2)

`%||%` <- function(x, y) if (is.null(x) || !length(x)) y else x

load("shiny_staging.RData")
load("df_train_RData.RData")
if (!exists("shiny_staging") && exists("staged")) shiny_staging <- staged
if (!exists("shiny_staging")) stop("shiny_staging.RData must contain shiny_staging")
if (!exists("df_train")) stop("df_train_RData.RData must contain df_train")

ml_tag <- tolower(trimws(as.character(shiny_staging$ml_tag %||% "rsf")[1L]))
eval_bn <- as.character(
  shiny_staging$evalresult_basename %||% paste0("evalresult_", ml_tag, ".RData")
)[1L]
if (!file.exists(eval_bn)) stop("Missing model file: ", eval_bn)
load(eval_bn)

fit_nm <- paste0("final_", ml_tag)
if (!exists(fit_nm)) stop("Loaded ", eval_bn, " but object ", fit_nm, " not found")
final_model <- get(fit_nm)

feats <- shiny_staging$model_features %||% shiny_staging$Final_Features
feats <- as.character(feats)
feats <- feats[nzchar(feats)]
if (!length(feats) && !is.null(final_model$xvar.names)) {
  feats <- as.character(final_model$xvar.names)
}
if (!length(feats)) stop("No model features in shiny_staging")

disease <- as.character(shiny_staging$disease_lbl %||% "Outcome")[1L]
disease_lab <- gsub("_", " ", disease, fixed = TRUE)
hor_main <- as.numeric(shiny_staging$surv_horizon %||% 28)[1L]
if (!is.finite(hor_main)) hor_main <- 28
horizons <- unique(as.numeric(shiny_staging$horizons %||% c(7, 14, 21, hor_main)))
horizons <- sort(horizons[is.finite(horizons) & horizons > 0])
risk_hi <- as.numeric(shiny_staging$risk_high %||% 70)[1L]
risk_lo <- as.numeric(shiny_staging$risk_low %||% 30)[1L]
algo_lab <- switch(
  ml_tag,
  rsf = "Random Survival Forest (RSF)",
  ridge_cox = "Ridge-Cox (glmnet)",
  enet_cox = "ElasticNet-Cox (glmnet)",
  xgbsurv = "XGBoost-Cox",
  gbmsurv = "GBM-Cox",
  coxboost = "CoxBoost",
  ml_tag
)

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
  title = "Survival Prognostic Tool",
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
            "</b> using a <b>", algo_lab, "</b> model. ",
            "Enter clinical features on the <b>Survival Prediction</b> tab and click ",
            "<b>Predict</b> to obtain individualized event probabilities at ",
            paste(horizons, collapse = "/"), " days, together with a survival curve ",
            "and the submitted feature values."
          )))
        ),
        h4(class = "step-title", "Model details"),
        tags$ul(
          tags$li(paste0("Algorithm: ", algo_lab)),
          tags$li(paste0("Primary evaluation horizon: ", hor_main, " days")),
          tags$li(paste0("Displayed horizons: ", paste(paste0(horizons, " d"), collapse = ", "))),
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
          h4("Survival / Event Probability"),
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
  list(time = tms, surv = srow, probs = probs)
}

.predict_glmnet_cox <- function(df) {
  bl <- shiny_staging$cox_baseline
  if (is.null(bl) || is.null(bl$time) || is.null(bl$surv0) || is.null(bl$coef)) {
    stop("shiny_staging$cox_baseline missing; re-run shiny_ml_app block.")
  }
  mm_cols <- as.character(bl$mm_cols %||% names(bl$coef))
  x <- matrix(0, nrow = 1L, ncol = length(mm_cols))
  colnames(x) <- mm_cols
  for (cn in feats) {
    hit <- mm_cols[mm_cols == cn | startsWith(mm_cols, paste0(cn))]
    if (!length(hit)) next
    val <- df[[cn]][1L]
    if (is.factor(val) || is.character(val)) {
      lev <- as.character(val)
      for (h in hit) {
        if (identical(h, cn)) {
          x[1L, h] <- suppressWarnings(as.numeric(val))
        } else if (endsWith(h, lev) || grepl(paste0(cn, lev, "$"), h) ||
                   grepl(paste0(cn, "\\.", lev, "$"), h)) {
          x[1L, h] <- 1
        }
      }
    } else {
      if (cn %in% mm_cols) x[1L, cn] <- as.numeric(val)
    }
  }
  beta <- as.numeric(bl$coef)
  names(beta) <- names(bl$coef)
  beta <- beta[mm_cols]
  beta[!is.finite(beta)] <- 0
  lp <- as.numeric(x %*% beta)
  lp_ref <- as.numeric(bl$lp_mean %||% 0)
  rr <- exp(lp - lp_ref)
  tms <- as.numeric(bl$time)
  s0 <- as.numeric(bl$surv0)
  srow <- pmax(pmin(s0^rr, 1), 0)
  probs <- vapply(horizons, function(h) {
    j <- which.min(abs(tms - h))
    as.numeric(1 - srow[j])
  }, numeric(1L))
  names(probs) <- as.character(horizons)
  list(time = tms, surv = as.numeric(srow), probs = probs, lp = lp)
}

.predict_any <- function(df) {
  if (identical(ml_tag, "rsf")) return(.predict_rsf(df))
  if (ml_tag %in% c("ridge_cox", "enet_cox")) return(.predict_glmnet_cox(df))
  stop(
    "Survival Shiny path for model '", ml_tag,
    "' is not enabled in this template; use rsf / ridge_cox / enet_cox."
  )
}

server <- function(input, output, session) {
  rv <- reactiveVal(NULL)

  observeEvent(input$submitBtn, {
    tryCatch({
      df <- .build_newdata(input)
      out <- .predict_any(df)
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
        "%s-day event probability: %.2f%%",
        h, 100 * as.numeric(out$probs[[h]])
      ))
    })
    tagList(
      div(class = "prob-big", sprintf("%.2f%% at %s days", pct, hor_main)),
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
        title = paste0("Predicted survival — ", disease_lab),
        x = "Time (days)", y = "Survival probability S(t)"
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
