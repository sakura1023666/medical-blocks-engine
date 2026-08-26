###############################################################################
# DynNom_czx_lrm / DNbuilder_czx_lrm — from Step05_Nomogram/C02_Dynamic_nomogram.R
# Requires: DynNom, rms, shiny, plotly, compare, stargazer
###############################################################################
  DynNom_czx_lrm<-function (model, data = NULL, clevel = 0.95, m.summary = c("raw","formatted"), covariate = c("slider", "numeric"), 
                            ptype = c("st","1-st"), DNtitle = NULL, DNxlab = NULL, DNylab = NULL, DNlimits = NULL,
                            KMtitle = NULL, KMxlab = NULL, KMylab = NULL) 
  {
    mclass <- getclass.DN(model)$model.class
    mfamily <- getclass.DN(model)$model.family
    if (mclass %in% c("coxph", "cph")) {
      Surv.in <- length(model$terms[[2]]) != 1
    }
    if (mclass %in% c("ols", "Glm", "lrm", "cph")) {
      model <- update(model, x = T, y = T)
    }
    if (!is.data.frame(data)) {
      if (any(class(try(getdata.DN(model), silent = TRUE)) == 
              "try-error")) {
        stop("Dataset needs to be provided in a data.frame format")
      }
      else {
        data <- getdata.DN(model)
      }
    }
    covariate <- match.arg(covariate)
    m.summary <- match.arg(m.summary)
    ptype <- match.arg(ptype)
    if (mclass %in% c("lm", "glm", "ols", "Glm", "lrm", "gam", 
                      "Gam")) {
      Terms.T <- all(all.vars(model$terms) %in% names(data))
    }
    if (mclass %in% c("coxph")) {
      if (Surv.in) {
        Terms.T <- all(all.vars(model$terms)[-c(1:2)] %in% 
                         names(data))
      }
      else {
        Terms.T <- all(all.vars(model$terms)[-1] %in% names(data))
      }
    }
    if (mclass %in% c("cph")) {
      Terms.T <- all(names(model$Design$units) %in% names(data))
    }
    if (!Terms.T) 
      stop("Error in model syntax: some of model's terms do not match to variables' name in dataset")
    if (!is.null(DNlimits) & !length(DNlimits) == 2) 
      stop("A vector of 2 is required as 'DNlimits'")
    if (is.null(DNtitle)) 
      DNtitle <- "Dynamic Nomogram"
    if (is.null(DNxlab)) {
      DNxlab <- ifelse((mclass %in% c("glm") & mfamily %in% 
                          c("binomial", "quasibinomial")) | mclass == "lrm" | 
                         mclass %in% c("coxph", "cph"), "Probability", "Response variable")
    }
    if (mclass %in% c("coxph", "cph")) {
      if (is.null(KMtitle)) {
        if (ptype == "st") {
          KMtitle <- "Estimated Survival Probability"
        }
        else {
          KMtitle <- "Estimated Probability"
        }
      }
      if (is.null(KMxlab)) {
        KMxlab <- "Follow Up Time"
      }
      if (is.null(KMylab)) {
        if (ptype == "st") {
          KMylab <- "S(t)"
        }
        else {
          KMylab <- "F(t)"
        }
      }
    }
    if (mclass %in% c("lm", "glm", "ols", "Glm", "lrm", "gam", 
                      "Gam")) {
      DynNom.core_czx_lrm(model, data, clevel, m.summary, covariate, 
                          DNtitle, DNxlab, DNylab, DNlimits)
    }
    if (mclass %in% c("coxph", "cph")) {
      DynNom.surv(model, data, clevel, m.summary, covariate, 
                  ptype, DNtitle, DNxlab, DNylab, KMtitle, KMxlab, 
                  KMylab)
    }
  }
  
  DynNom.core_czx_lrm<-function (model, data, clevel, m.summary, covariate, DNtitle,DNxlab, DNylab, DNlimits) 
  {
    mclass <- getclass.DN(model)$model.class
    mfamily <- getclass.DN(model)$model.family
    if (mclass %in% c("lm", "ols")) {
      mlinkF <- function(eta) eta
    }
    else {
      mlinkF <- ifelse(mclass == "lrm", function(mu) plogis(mu), 
                       model$family$linkinv)
    }
    input.data <- NULL
    old.d <- NULL
    if (mclass %in% c("ols", "Glm", "lrm")) {
      model <- update(model, x = T, y = T)
    }
    allvars <- all.vars(model$terms)
    if (mclass %in% c("ols", "lrm", "Glm")) {
      #进行lrm的分析时，此处term原意应为因变量及自变量的名称的character形式，但是此处仅生成自变量的部分，缺少因变量。
      #因此debug此处，增加一项因变量名称在前
      terms <- model$Design$assume[model$Design$assume != 
                                     "interaction"]
      terms<-c("asis",terms)
      names(terms) = c(model$terms[[2]],model$Design$name[model$Design$assume != "interaction"])
      #结束debug
      
      if (mclass %in% c("Glm")) {
        terms <- c(attr(attr(model$model, "terms"), "dataClasses")[1], 
                   terms)
      }
      else {
        terms <- c(attr(model$terms, "dataClasses")[1], 
                   terms)
      }
    }
    if (mclass %in% c("lm", "glm", "gam", "Gam")) {
      if (length(attr(model$terms, "dataClasses")) == length(allvars)) {
        terms <- attr(model$terms, "dataClasses")
        names(terms) = allvars
      }
      else {
        terms <- attr(model$terms, "dataClasses")[which(names(attr(model$terms, 
                                                                   "dataClasses")) %in% allvars)]
      }
    }
    if (terms[[1]] == "logical") 
      stop("Error in model syntax: logical form for response not supported")
    terms[terms %in% c("numeric", "asis", "polynomial", "integer", 
                       "double", "matrx") | grepl("nmatrix", terms, fixed = T) | 
            grepl("spline", terms, fixed = T)] = "numeric"
    terms[terms %in% c("factor", "ordered", "logical", "category", 
                       "scored")] = "factor"
    resp <- terms[1]
    names(resp) <- allvars[1]
    if ("(weights)" %in% names(terms)) {
      preds <- as.list(terms[-c(1, length(terms))])
    }
    else {
      preds <- as.list(terms[-1])
    }
    names(preds) <- allvars[-1]
    for (i in 1:length(preds)) {
      if (preds[[i]] == "numeric") {
        i.dat <- which(names(preds[i]) == names(data))
        preds[[i]] <- list(v.min = floor(min(na.omit(data[, 
                                                          as.numeric(i.dat)]))), v.max = ceiling(max(na.omit(data[, 
                                                                                                                  as.numeric(i.dat)]))), v.mean = zapsmall(mean(data[, 
                                                                                                                                                                     as.numeric(i.dat)], na.rm = T), digits = 4))
        next
      }
      if (preds[[i]] == "factor") {
        i.dat <- which(names(preds[i]) == names(data))
        if (mclass %in% c("ols", "Glm", "lrm", "cph")) {
          preds[[i]] <- list(v.levels = model$Design$parms[[which(names(preds[i]) == 
                                                                    names(model$Design$parms))]])
        }
        else {
          preds[[i]] <- list(v.levels = model$xlevels[[which(names(preds[i]) == 
                                                               names(model$xlevels))]])
        }
      }
    }
    if (!is.null(DNlimits) & !length(DNlimits) == 2) 
      stop("A vector of 2 is required as 'DNlimits'")
    if (is.null(DNlimits)) {
      if ((mclass %in% c("glm") & mfamily %in% c("binomial", 
                                                 "quasibinomial")) | mclass == "lrm") {
        limits0 <- c(0, 1)
      }
      else {
        if (mclass %in% c("lm", "glm", "gam", "Gam")) {
          limits0 <- c(mean(model$model[, names(resp)]) - 
                         3 * sd(model$model[, names(resp)]), mean(model$model[, 
                                                                              names(resp)]) + 3 * sd(model$model[, names(resp)]))
        }
        if (mclass %in% c("ols", "lrm", "Glm")) {
          limits0 <- c(mean(model$y) - 3 * sd(model$y), 
                       mean(model$y) + 3 * sd(model$y))
        }
      }
      if (mclass %in% c("glm", "Glm") & mfamily %in% c("poisson", 
                                                       "quasipoisson", "Gamma")) {
        limits0[1] <- 0
      }
    }
    neededVar <- c(names(resp), names(preds))
    data <- data[, neededVar]
    input.data <- data[0, ]
    runApp(list(ui = bootstrapPage(fluidPage(titlePanel(DNtitle), 
                                             sidebarLayout(sidebarPanel(uiOutput("manySliders"), 
                                                                        uiOutput("setlimits"), actionButton("add", "Predict"), 
                                                                        br(), br(), helpText("Press Quit to exit the application"), 
                                                                        actionButton("quit", "Quit")), mainPanel(tabsetPanel(id = "tabs", 
                                                                                                                             tabPanel("Graphical Summary", plotlyOutput("plot")), 
                                                                                                                             tabPanel("Numerical Summary", verbatimTextOutput("data.pred")), 
                                                                                                                             tabPanel("Model Summary", verbatimTextOutput("summary"))))))), 
                server = function(input, output) {
                  observe({
                    if (input$quit == 1) stopApp()
                  })
                  limits <- reactive({
                    if (!is.null(DNlimits)) {
                      limits <- DNlimits
                    } else {
                      if (input$limits) {
                        limits <- c(input$lxlim, input$uxlim)
                      } else {
                        limits <- limits0
                      }
                    }
                  })
                  output$manySliders <- renderUI({
                    slide.bars <- list()
                    for (j in 1:length(preds)) {
                      if (terms[j + 1] == "factor") {
                        slide.bars[[j]] <- list(selectInput(paste("pred", 
                                                                  j, sep = ""), names(preds)[j], preds[[j]]$v.levels, 
                                                            multiple = FALSE))
                      }
                      if (terms[j + 1] == "numeric") {
                        if (covariate == "slider") {
                          slide.bars[[j]] <- list(sliderInput(paste("pred", 
                                                                    j, sep = ""), names(preds)[j], min = preds[[j]]$v.min, 
                                                              max = preds[[j]]$v.max, value = preds[[j]]$v.mean))
                        }
                        if (covariate == "numeric") {
                          slide.bars[[j]] <- list(numericInput(paste("pred", 
                                                                     j, sep = ""), names(preds)[j], value = zapsmall(preds[[j]]$v.mean, 
                                                                                                                     digits = 4)))
                        }
                      }
                    }
                    do.call(tagList, slide.bars)
                  })
                  output$setlimits <- renderUI({
                    if (is.null(DNlimits)) {
                      setlim <- list(checkboxInput("limits", "Set x-axis ranges"), 
                                     conditionalPanel(condition = "input.limits == true", 
                                                      numericInput("uxlim", "x-axis upper", 
                                                                   zapsmall(limits0[2], digits = 2)), numericInput("lxlim", 
                                                                                                                   "x-axis lower", zapsmall(limits0[1], 
                                                                                                                                            digits = 2))))
                    } else {
                      setlim <- NULL
                    }
                    setlim
                  })
                  a <- 0
                  new.d <- reactive({
                    input$add
                    input.v <- vector("list", length(preds))
                    for (i in 1:length(preds)) {
                      input.v[[i]] <- isolate({
                        input[[paste("pred", i, sep = "")]]
                      })
                      names(input.v)[i] <- names(preds)[i]
                    }
                    out <- data.frame(lapply(input.v, cbind))
                    if (a == 0) {
                      input.data <<- rbind(input.data, out)
                    }
                    if (a > 0) {
                      if (!isTRUE(compare(old.d, out))) {
                        input.data <<- rbind(input.data, out)
                      }
                    }
                    a <<- a + 1
                    out
                  })
                  p1 <- NULL
                  old.d <- NULL
                  data2 <- reactive({
                    if (input$add == 0) return(NULL)
                    if (input$add > 0) {
                      if (!isTRUE(compare(old.d, new.d()))) {
                        isolate({
                          mpred <- getpred.DN(model, new.d())$pred
                          se.pred <- getpred.DN(model, new.d())$SEpred
                          if (is.na(se.pred)) {
                            lwb <- "No standard errors"
                            upb <- paste("by '", mclass, "'", sep = "")
                            pred <- mlinkF(mpred)
                            d.p <- data.frame(Prediction = zapsmall(pred, 
                                                                    digits = 3), Lower.bound = lwb, Upper.bound = upb)
                          } else {
                            lwb <- sort(mlinkF(mpred + cbind(1, 
                                                             -1) * (qnorm(1 - (1 - clevel)/2) * 
                                                                      se.pred)))[1]
                            upb <- sort(mlinkF(mpred + cbind(1, 
                                                             -1) * (qnorm(1 - (1 - clevel)/2) * 
                                                                      se.pred)))[2]
                            pred <- mlinkF(mpred)
                            d.p <- data.frame(Prediction = zapsmall(pred, 
                                                                    digits = 3), Lower.bound = zapsmall(lwb, 
                                                                                                        digits = 3), Upper.bound = zapsmall(upb, 
                                                                                                                                            digits = 3))
                          }
                          old.d <<- new.d()
                          data.p <- cbind(d.p, counter = 1, count = 0)
                          p1 <<- rbind(p1, data.p)
                          p1$counter <- seq(1, dim(p1)[1])
                          p1$count <- 0:(dim(p1)[1] - 1)%%11 + 1
                          p1
                        })
                      } else {
                        p1$count <- seq(1, dim(p1)[1])
                      }
                    }
                    rownames(p1) <- c()
                    p1
                  })
                  output$plot <- renderPlotly({
                    if (input$add == 0) return(NULL)
                    if (is.null(new.d())) return(NULL)
                    coll = c("#0E0000", "#0066CC", "#E41A1C", "#54A552", 
                             "#FF8000", "#BA55D3", "#006400", "#994C00", 
                             "#F781BF", "#00BFFF", "#A9A9A9")
                    lim <- limits()
                    yli <- c(0 - 0.5, 10 + 0.5)
                    dat2 <- data2()
                    if (dim(data2())[1] > 11) {
                      input.data = input.data[-c(1:(dim(input.data)[1] - 
                                                      11)), ]
                      dat2 <- data2()[-c(1:(dim(data2())[1] - 11)), 
                      ]
                      yli <- c(dim(data2())[1] - 11.5, dim(data2())[1] - 
                                 0.5)
                    }
                    in.d <- input.data
                    xx <- matrix(paste(names(in.d), ": ", t(in.d), 
                                       sep = ""), ncol = dim(in.d)[1])
                    Covariates <- apply(xx, 2, paste, collapse = "<br />")
                    p <- ggplot(data = dat2, aes(x = Prediction, 
                                                 y = counter - 1, text = Covariates, label = Prediction, 
                                                 label2 = Lower.bound, label3 = Upper.bound)) + 
                      geom_point(size = 2, colour = coll[dat2$count], 
                                 shape = 15) + ylim(yli[1], yli[2]) + coord_cartesian(xlim = lim) + 
                      labs(title = paste(clevel * 100, "% ", "Confidence Interval for Response", 
                                         sep = ""), x = DNxlab, y = DNylab) + theme_bw() + 
                      theme(axis.text.y = element_blank(), text = element_text(face = "bold", 
                                                                               size = 10))
                    if (is.numeric(dat2$Upper.bound)) {
                      p <- p + geom_errorbarh(xmax = dat2$Upper.bound, 
                                              xmin = dat2$Lower.bound, size = 1.45, height = 0.4, 
                                              colour = coll[dat2$count])
                    } else {
                      message(paste("Confidence interval is not available as there is no standard errors available by '", 
                                    mclass, "' ", sep = ""))
                    }
                    gp <- ggplotly(p, tooltip = c("text", "label", 
                                                  "label2", "label3"))
                    gp$elementId <- NULL
                    gp
                  })
                  output$data.pred <- renderPrint({
                    if (input$add > 0) {
                      if (nrow(data2()) > 0) {
                        if (dim(input.data)[2] == 1) {
                          in.d <- data.frame(input.data)
                          names(in.d) <- names(terms)[2]
                          data.p <- cbind(in.d, data2()[1:3])
                        }
                        if (dim(input.data)[2] > 1) {
                          data.p <- cbind(input.data, data2()[1:3])
                        }
                      }
                      stargazer(data.p, summary = FALSE, type = "text")
                    }
                  })
                  output$summary <- renderPrint({
                    if (m.summary == "formatted") {
                      if (mclass == "lm") {
                        stargazer(model, type = "text", omit.stat = c("LL", 
                                                                      "ser", "f"), ci = TRUE, ci.level = clevel, 
                                  single.row = TRUE, title = paste("Linear Regression:", 
                                                                   model$call[2], sep = " "))
                      }
                      if (mclass %in% c("glm")) {
                        stargazer(model, type = "text", omit.stat = c("LL", 
                                                                      "ser", "f"), ci = TRUE, ci.level = clevel, 
                                  single.row = TRUE, title = paste(mfamily, 
                                                                   " regression (", model$family$link, 
                                                                   "): ", model$formula[2], " ", model$formula[1], 
                                                                   " ", model$formula[3], sep = ""))
                      }
                      if (mclass == "gam") {
                        Msum <- list(summary(model)$formula, summary(model)$p.table, 
                                     summary(model)$s.table)
                        invisible(lapply(1:3, function(i) {
                          cat(sep = "", names(Msum)[i], "\n")
                          print(Msum[[i]])
                        }))
                      }
                      if (mclass == "Gam") {
                        Msum <- list(model$formula, summary(model)$parametric.anova, 
                                     summary(model)$anova)
                        invisible(lapply(1:3, function(i) {
                          cat(sep = "", names(Msum)[i], "\n")
                          print(Msum[[i]])
                        }))
                      }
                      if (mclass %in% c("ols", "lrm", "Glm")) {
                        stargazer(model, type = "text", omit.stat = c("LL", 
                                                                      "ser", "f"), ci = TRUE, ci.level = clevel, 
                                  single.row = TRUE, title = paste("Linear Regression:", 
                                                                   model$call[2], sep = " "))
                      }
                    }
                    if (m.summary == "raw") {
                      if (mclass %in% c("ols", "Glm", "lrm")) {
                        print(model)
                      } else {
                        summary(model)
                      }
                    }
                  })
                }))
  }
  
  DNbuilder_czx_lrm<-function (model, data = NULL, clevel = 0.95, m.summary = c("raw","formatted"), 
                               covariate = c("slider", "numeric"), ptype = c("st","1-st"), 
                               DNtitle = NULL, DNxlab = NULL, DNylab = NULL, DNlimits = NULL,KMtitle = NULL, KMxlab = NULL, KMylab = NULL) 
  {
    mclass <- getclass.DN(model)$model.class
    mfamily <- getclass.DN(model)$model.family
    if (mclass %in% c("coxph", "cph")) {
      Surv.in <- length(model$terms[[2]]) != 1
    }
    if (mclass %in% c("ols", "Glm", "lrm", "cph")) {
      model <- update(model, x = T, y = T)
    }
    if (!is.data.frame(data)) {
      if (any(class(try(getdata.DN(model), silent = TRUE)) == 
              "try-error")) {
        stop("Dataset needs to be provided in a data.frame format")
      }
      else {
        data <- getdata.DN(model)
      }
    }
    covariate <- match.arg(covariate)
    m.summary <- match.arg(m.summary)
    ptype <- match.arg(ptype)
    if (mclass %in% c("lm", "glm", "ols", "Glm", "lrm", "gam", 
                      "Gam")) {
      Terms.T <- all(all.vars(model$terms) %in% names(data))
    }
    if (mclass %in% c("coxph")) {
      if (Surv.in) {
        Terms.T <- all(all.vars(model$terms)[-c(1:2)] %in% 
                         names(data))
      }
      else {
        Terms.T <- all(all.vars(model$terms)[-1] %in% names(data))
      }
    }
    if (mclass %in% c("cph")) {
      Terms.T <- all(names(model$Design$units) %in% names(data))
    }
    if (!Terms.T) 
      stop("Error in model syntax: some of model's terms do not match to variables' name in dataset")
    if (!is.null(DNlimits) & !length(DNlimits) == 2) 
      stop("A vector of 2 is required as 'DNlimits'")
    if (is.null(DNtitle)) 
      DNtitle <- "Dynamic Nomogram"
    if (is.null(DNxlab)) {
      if ((mclass %in% c("glm") & mfamily %in% c("binomial", 
                                                 "quasibinomial")) | mclass == "lrm") {
        DNxlab <- "Probability"
      }
      else {
        DNxlab <- ifelse(mclass %in% c("coxph", "cph"), 
                         "Survival probability", "Response variable")
      }
    }
    if (mclass %in% c("coxph", "cph")) {
      if (is.null(KMtitle)) {
        if (ptype == "st") {
          KMtitle <- "Estimated Survival Probability"
        }
        else {
          KMtitle <- "Estimated Probability"
        }
      }
      if (is.null(KMxlab)) {
        KMxlab <- "Follow Up Time"
      }
      if (is.null(KMylab)) {
        if (ptype == "st") {
          KMylab <- "S(t)"
        }
        else {
          KMylab <- "F(t)"
        }
      }
    }
    if (mclass %in% c("lm", "glm", "ols", "Glm", "lrm", "gam", 
                      "Gam")) {
      DNbuilder.core_czx_lrm(model, data, clevel, m.summary, covariate, 
                             DNtitle, DNxlab, DNylab, DNlimits)
    }
    if (mclass %in% c("coxph", "cph")) {
      DNbuilder.surv(model, data, clevel, m.summary, covariate, 
                     ptype, DNtitle, DNxlab, DNylab, KMtitle, KMxlab, 
                     KMylab)
    }
  }
  DNbuilder.core_czx_lrm<-function (model, data, clevel, m.summary, covariate, DNtitle, 
                                    DNxlab, DNylab, DNlimits) 
  {
    mclass <- getclass.DN(model)$model.class
    mfamily <- getclass.DN(model)$model.family
    if (mclass %in% c("lm", "ols")) {
      mlinkF <- function(eta) eta
    }
    else {
      mlinkF <- ifelse(mclass == "lrm", function(mu) plogis(mu), 
                       model$family$linkinv)
    }
    input.data <- NULL
    old.d <- NULL
    if (mclass %in% c("ols", "Glm", "lrm")) {
      model <- update(model, x = T, y = T)
    }
    allvars <- all.vars(model$terms)
    if (mclass %in% c("ols", "lrm", "Glm")) {
      
      #进行lrm的分析时，此处term原意应为因变量及自变量的名称的character形式，但是此处仅生成自变量的部分，缺少因变量。
      #因此debug此处，增加一项因变量名称在前
      terms <- model$Design$assume[model$Design$assume != 
                                     "interaction"]
      terms<-c("asis",terms)
      names(terms) = c(model$terms[[2]],model$Design$name[model$Design$assume != "interaction"])
      #结束debug
      
      if (mclass %in% c("Glm")) {
        terms <- c(attr(attr(model$model, "terms"), "dataClasses")[1], 
                   terms)
      }
      else {
        terms <- c(attr(model$terms, "dataClasses")[1], 
                   terms)
      }
    }
    if (mclass %in% c("lm", "glm", "gam", "Gam")) {
      if (length(attr(model$terms, "dataClasses")) == length(allvars)) {
        terms <- attr(model$terms, "dataClasses")
        names(terms) = allvars
      }
      else {
        terms <- attr(model$terms, "dataClasses")[which(names(attr(model$terms, 
                                                                   "dataClasses")) %in% allvars)]
      }
    }
    if (terms[[1]] == "logical") 
      stop("Error in model syntax: logical form for response not supported")
    terms[terms %in% c("numeric", "asis", "polynomial", "integer", 
                       "double", "matrx") | grepl("nmatrix", terms, fixed = T) | 
            grepl("spline", terms, fixed = T)] = "numeric"
    terms[terms %in% c("factor", "ordered", "logical", "category", 
                       "scored")] = "factor"
    resp <- terms[1]
    names(resp) <- allvars[1]
    if ("(weights)" %in% names(terms)) {
      preds <- as.list(terms[-c(1, length(terms))])
    }
    else {
      preds <- as.list(terms[-1])
    }
    names(preds) <- allvars[-1]
    for (i in 1:length(preds)) {
      if (preds[[i]] == "numeric") {
        i.dat <- which(names(preds[i]) == names(data))
        preds[[i]] <- list(v.min = floor(min(na.omit(data[, 
                                                          as.numeric(i.dat)]))), v.max = ceiling(max(na.omit(data[, 
                                                                                                                  as.numeric(i.dat)]))), v.mean = zapsmall(mean(data[, 
                                                                                                                                                                     as.numeric(i.dat)], na.rm = T), digits = 4))
        next
      }
      if (preds[[i]] == "factor") {
        i.dat <- which(names(preds[i]) == names(data))
        if (mclass %in% c("ols", "Glm", "lrm", "cph")) {
          preds[[i]] <- list(v.levels = model$Design$parms[[which(names(preds[i]) == 
                                                                    names(model$Design$parms))]])
        }
        else {
          preds[[i]] <- list(v.levels = model$xlevels[[which(names(preds[i]) == 
                                                               names(model$xlevels))]])
        }
      }
    }
    if (!is.null(DNlimits) & !length(DNlimits) == 2) 
      stop("A vector of 2 is required as 'DNlimits'")
    if (is.null(DNlimits)) {
      if ((mclass %in% c("glm") & mfamily %in% c("binomial", 
                                                 "quasibinomial")) | mclass == "lrm") {
        limits0 <- c(0, 1)
      }
      else {
        if (mclass %in% c("lm", "glm", "gam", "Gam")) {
          limits0 <- c(mean(model$model[, names(resp)]) - 
                         3 * sd(model$model[, names(resp)]), mean(model$model[, 
                                                                              names(resp)]) + 3 * sd(model$model[, names(resp)]))
        }
        if (mclass %in% c("ols", "lrm", "Glm")) {
          limits0 <- c(mean(model$y) - 3 * sd(model$y), 
                       mean(model$y) + 3 * sd(model$y))
        }
      }
      if (mclass %in% c("glm", "Glm") & mfamily %in% c("poisson", 
                                                       "quasipoisson", "Gamma")) {
        limits0[1] <- 0
      }
    }
    else {
      limits0 <- DNlimits
    }
    neededVar <- c(names(resp), names(preds))
    data <- data[, neededVar]
    input.data <- data[0, ]
    model <- update(model, data = data)
    wdir <- getwd()
    app.dir <- paste(wdir, "DynNomapp", sep = "/")
    message(paste("creating new directory: ", app.dir, sep = ""))
    dir.create(app.dir)
    setwd(app.dir)
    message(paste("Export dataset: ", app.dir, "/dataset.RData", 
                  sep = ""))
    save(data, model, preds, resp, mlinkF, getpred.DN, getclass.DN, 
         DNtitle, DNxlab, DNylab, DNlimits, limits0, terms, input.data, 
         file = "data.RData")
    message(paste("Export functions: ", app.dir, "/functions.R", 
                  sep = ""))
    dump(c("getpred.DN", "getclass.DN"), file = "functions.R")
    if (!is.null(DNlimits)) {
      limits.bl <- paste("limits <- reactive({ DNlimits })")
    }
    else {
      limits.bl <- paste("limits <- reactive({ if (input$limits) { limits <- c(input$lxlim, input$uxlim) } else {\n                         limits <- limits0 } })")
    }
    noSE.bl <- paste("by '", mclass, "'", sep = "")
    p1title.bl <- paste(clevel * 100, "% ", "Confidence Interval for Response", 
                        sep = "")
    p1msg.bl <- paste("Confidence interval is not available as there is no standard errors available by '", 
                      mclass, "' ", sep = "")
    if (m.summary == "formatted") {
      if (mclass == "lm") {
        sumtitle.bl <- paste("Linear Regression:", model$call[2], 
                             sep = " ")
      }
      if (mclass %in% c("glm")) {
        sumtitle.bl <- paste(mfamily, " regression (", model$family$link, 
                             "): ", model$formula[2], " ", model$formula[1], 
                             " ", model$formula[3], sep = "")
      }
      if (mclass %in% c("ols", "lrm", "Glm")) {
        sumtitle.bl <- paste("Linear Regression:", model$call[2], 
                             sep = " ")
      }
    }
    else {
      sumtitle.bl = NULL
    }
    if (m.summary == "formatted") {
      if (mclass %in% c("lm", "glm", "ols", "lrm", "Glm")) {
        sum.bi <- paste("stargazer(model, type = 'text', omit.stat = c('LL', 'ser', 'f'), ci = TRUE, ci.level = clevel, single.row = TRUE, title = '", 
                        sumtitle.bl, "')", sep = "")
      }
      if (mclass == "gam") {
        sum.bi <- paste("Msum <- list(summary(model)$formula, summary(model)$p.table, summary(model)$s.table)\n                invisible(lapply(1:3, function(i){ cat(sep='', names(Msum)[i], '\n') ; print(Msum[[i]])}))")
      }
      if (mclass == "Gam") {
        sum.bi <- paste("Msum <- list(model$formula, summary(model)$parametric.anova, summary(model)$anova)\n                invisible(lapply(1:3, function(i){ cat(sep='', names(Msum)[i], '\n')) ; print(Msum[[i]])}))")
      }
    }
    if (m.summary == "raw") {
      if (mclass %in% c("ols", "Glm", "lrm")) {
        sum.bi <- paste("print(model)")
      }
      else {
        sum.bi <- paste("summary(model)")
      }
    }
    if (mclass %in% c("ols", "Glm", "lrm")) {
      datadist.bl <- paste("t.dist <- datadist(data)\noptions(datadist = 't.dist')", 
                           sep = "")
    }
    else {
      datadist.bl <- ""
    }
    if (mclass %in% c("lm", "glm")) {
      library.bl <- ""
    }
    else {
      if (mclass %in% c("ols", "Glm", "lrm")) {
        library.bl <- paste("library(rms)")
      }
      if (mclass %in% c("Gam")) {
        library.bl <- paste("library(gam)")
      }
      if (mclass %in% c("gam")) {
        library.bl <- paste("library(mgcv)")
      }
    }
    GLOBAL = paste("library(ggplot2)\nlibrary(shiny)\nlibrary(plotly)\nlibrary(stargazer)\nlibrary(compare)\nlibrary(prediction)\n", 
                   library.bl, "\n\n#######################################################\n#### Before publishing your dynamic nomogram:\n####\n#### - You may need to edit the following lines if\n#### data or model objects are not defined correctly\n#### - You could modify ui.R or server.R for\n#### making any required changes to your app\n#######################################################\n\nload('data.RData')\nsource('functions.R')\n", 
                   datadist.bl, "\nm.summary <- '", m.summary, "'\ncovariate <- '", 
                   covariate, "'\nclevel <- ", clevel, "\n\n### Please cite the package if used in publication. Use:\n# Amirhossein Jalali, Davood Roshan, Alberto Alvarez-Iglesias and John Newell (2019). DynNom: Visualising statistical models using dynamic nomograms.\n# R package version 5.0. https://CRAN.R-project.org/package=DynNom\n", 
                   sep = "")
    UI = paste("ui = bootstrapPage(fluidPage(\n    titlePanel('", 
               DNtitle, "'),\n    sidebarLayout(sidebarPanel(uiOutput('manySliders'),\n                               uiOutput('setlimits'),\n                               actionButton('add', 'Predict'),\n                               br(), br(),\n                               helpText('Press Quit to exit the application'),\n                               actionButton('quit', 'Quit')\n    ),\n    mainPanel(tabsetPanel(id = 'tabs',\n                          tabPanel('Graphical Summary', plotlyOutput('plot')),\n                          tabPanel('Numerical Summary', verbatimTextOutput('data.pred')),\n                          tabPanel('Model Summary', verbatimTextOutput('summary'))\n    )\n    )\n    )))", 
               sep = "")
    SERVER = paste("server = function(input, output){\nobserve({if (input$quit == 1)\n          stopApp()})\n\n", 
                   limits.bl, "\n\noutput$manySliders <- renderUI({\n  slide.bars <- list()\n               for (j in 1:length(preds)){\n               if (terms[j+1] == \"factor\"){\n               slide.bars[[j]] <- list(selectInput(paste(\"pred\", j, sep = \"\"), names(preds)[j], preds[[j]]$v.levels, multiple = FALSE))\n               }\n               if (terms[j+1] == \"numeric\"){\n               if (covariate == \"slider\") {\n               slide.bars[[j]] <- list(sliderInput(paste(\"pred\", j, sep = \"\"), names(preds)[j],\n               min = preds[[j]]$v.min, max = preds[[j]]$v.max, value = preds[[j]]$v.mean))\n               }\n               if (covariate == \"numeric\") {\n               slide.bars[[j]] <- list(numericInput(paste(\"pred\", j, sep = \"\"), names(preds)[j], value = zapsmall(preds[[j]]$v.mean, digits = 4)))\n               }}}\n               do.call(tagList, slide.bars)\n})\n\noutput$setlimits <- renderUI({\n        if (is.null(DNlimits)){\n               setlim <- list(checkboxInput(\"limits\", \"Set x-axis ranges\"),\n               conditionalPanel(condition = \"input.limits == true\",\n               numericInput(\"uxlim\", \"x-axis upper\", zapsmall(limits0[2], digits = 2)),\n               numericInput(\"lxlim\", \"x-axis lower\", zapsmall(limits0[1], digits = 2))))\n        } else{ setlim <- NULL }\n        setlim\n})\n\na <- 0\nnew.d <- reactive({\n               input$add\n               input.v <- vector(\"list\", length(preds))\n               for (i in 1:length(preds)) {\n               input.v[[i]] <- isolate({\n               input[[paste(\"pred\", i, sep = \"\")]]\n               })\n               names(input.v)[i] <- names(preds)[i]\n               }\n               out <- data.frame(lapply(input.v, cbind))\n               if (a == 0) {\n               input.data <<- rbind(input.data, out)\n               }\n               if (a > 0) {\n               if (!isTRUE(compare(old.d, out))) {\n               input.data <<- rbind(input.data, out)\n               }}\n               a <<- a + 1\n               out\n})\n\np1 <- NULL\nold.d <- NULL\ndata2 <- reactive({\n               if (input$add == 0)\n               return(NULL)\n               if (input$add > 0) {\n               if (!isTRUE(compare(old.d, new.d()))) {\n               isolate({\n               mpred <- getpred.DN(model, new.d(), set.rms=T)$pred\n               se.pred <- getpred.DN(model, new.d(), set.rms=T)$SEpred\n               if (is.na(se.pred)) {\n               lwb <- \"No standard errors\"\n               upb <- \"", 
                   noSE.bl, "\"\n               pred <- mlinkF(mpred)\n               d.p <- data.frame(Prediction = zapsmall(pred, digits = 3),\n               Lower.bound = lwb, Upper.bound = upb)\n               } else {\n               lwb <- sort(mlinkF(mpred + cbind(1, -1) * (qnorm(1 - (1 - clevel)/2) * se.pred)))[1]\n               upb <- sort(mlinkF(mpred + cbind(1, -1) * (qnorm(1 - (1 - clevel)/2) * se.pred)))[2]\n               pred <- mlinkF(mpred)\n               d.p <- data.frame(Prediction = zapsmall(pred, digits = 3),\n               Lower.bound = zapsmall(lwb, digits = 3),\n               Upper.bound = zapsmall(upb, digits = 3))\n               }\n               old.d <<- new.d()\n               data.p <- cbind(d.p, counter = 1, count=0)\n               p1 <<- rbind(p1, data.p)\n               p1$counter <- seq(1, dim(p1)[1])\n               p1$count <- 0:(dim(p1)[1]-1) %% 11 + 1\n               p1\n               })\n               } else {\n               p1$count <- seq(1, dim(p1)[1])\n               }}\n               rownames(p1) <- c()\n               p1\n})\n\noutput$plot <- renderPlotly({\n  if (input$add == 0)\n               return(NULL)\n               if (is.null(new.d()))\n               return(NULL)\n               coll=c(\"#0E0000\", \"#0066CC\", \"#E41A1C\", \"#54A552\", \"#FF8000\", \"#BA55D3\",\n               \"#006400\", \"#994C00\", \"#F781BF\", \"#00BFFF\", \"#A9A9A9\")\n               lim <- limits()\n               yli <- c(0 - 0.5, 10 + 0.5)\n               dat2 <- data2()\n               if (dim(data2())[1] > 11){\n               input.data = input.data[-c(1:(dim(input.data)[1]-11)),]\n               dat2 <- data2()[-c(1:(dim(data2())[1]-11)),]\n               yli <- c(dim(data2())[1] - 11.5, dim(data2())[1] - 0.5)\n               }\n               in.d <- input.data\n               xx <- matrix(paste(names(in.d), \": \", t(in.d), sep = \"\"), ncol = dim(in.d)[1])\n               Covariates <- apply(xx, 2, paste, collapse = \"<br />\")\n               p <- ggplot(data = dat2, aes(x = Prediction, y = counter - 1, text = Covariates,\n               label = Prediction, label2 = Lower.bound, label3=Upper.bound)) +\n               geom_point(size = 2, colour = coll[dat2$count], shape = 15) +\n               ylim(yli[1], yli[2]) + coord_cartesian(xlim = lim) +\n               labs(title = \"", 
                   p1title.bl, "\",\n               x = \"", DNxlab, "\", y = \"", 
                   DNylab, "\") + theme_bw() +\n               theme(axis.text.y = element_blank(), text = element_text(face = \"bold\", size = 10))\n               if (is.numeric(dat2$Upper.bound)){\n               p <- p + geom_errorbarh(xmax = dat2$Upper.bound, xmin = dat2$Lower.bound,\n               size = 1.45, height = 0.4, colour = coll[dat2$count])\n               } else{\n               message(\"", 
                   p1msg.bl, "\")\n               }\n               gp <- ggplotly(p, tooltip = c(\"text\", \"label\", \"label2\", \"label3\"))\n               gp$elementId <- NULL\n               gp\n})\n\noutput$data.pred <- renderPrint({\n  if (input$add > 0) {\n               if (nrow(data2()) > 0) {\n               if (dim(input.data)[2] == 1) {\n               in.d <- data.frame(input.data)\n               names(in.d) <- names(terms)[2]\n               data.p <- cbind(in.d, data2()[1:3])\n               }\n               if (dim(input.data)[2] > 1) {\n               data.p <- cbind(input.data, data2()[1:3])\n               }}\n               stargazer(data.p, summary = FALSE, type = \"text\")\n}\n})\n\noutput$summary <- renderPrint({\n", 
                   sum.bi, "\n})\n}", sep = "")
    output = list(ui = UI, server = SERVER, global = GLOBAL)
    text <- paste("This guide will describe how to deploy a shiny application using scripts generated by DNbuilder:\n\n1. Run the shiny app by setting your working directory to the DynNomapp folder, and then run: shiny::runApp() If you are using the RStudio IDE, you can also run it by clicking the Run App button in the editor toolbar after open one of the R scripts.\n\n2. You could modify codes to apply all the necessary changes. Run again to confirm that your application works perfectly.\n\n3. Deploy the application by either clicking on the Publish button in the top right corner of the running app, or use the generated files and deploy it on your server if you host any.\n\nYou can find a full guide of how to deploy an application on shinyapp.io server here:\nhttp://docs.rstudio.com/shinyapps.io/getting-started.html#deploying-applications\n\nPlease cite the package if using in publication.", 
                  sep = "")
    message(paste("writing file: ", app.dir, "/README.txt", 
                  sep = ""))
    writeLines(text, "README.txt")
    message(paste("writing file: ", app.dir, "/ui.R", sep = ""))
    writeLines(output$ui, "ui.R")
    message(paste("writing file: ", app.dir, "/server.R", sep = ""))
    writeLines(output$server, "server.R")
    message(paste("writing file: ", app.dir, "/global.R", sep = ""))
    writeLines(output$global, "global.R")
    setwd(wdir)
  }
