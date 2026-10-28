###############################################################################
#  clhls_sex — 分性别 EBICglasso 网络 + 中心性（Fig 4 / Table 3）
#  register_block: "clhls_sex"
#  算法对齐既往 Step06；估计器同全样本（Pearson → nearPD → EBIC γ=0.5）
###############################################################################



if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x
}


block_clhls_sex <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "Blocks/81_clhls_symptom_network_full/00clhls_net_common.R"), local = FALSE)
  clhls_net_require_pkgs()
  cfg <- clhls_net_cfg(ctx)
  dirs <- clhls_net_out_dirs(ctx)
  df <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(df)) stop("clhls_sex: 无数据", call. = FALSE)

  parts <- clhls_net_sex_split(df, cfg)
  items <- unname(cfg$items)
  labels <- cfg$nodes
  groups <- cfg$groups
  short <- cfg$short
  tabs <- list()
  graphs <- list()
  ns <- list()

  for (sx in c("Male", "Female")) {
    sub <- parts[[sx]]
    if (nrow(sub) < 30L) stop("clhls_sex: ", sx, " 样本过少 n=", nrow(sub), call. = FALSE)
    dat <- clhls_net_cov_mat(sub, cfg$nodes, cfg$covariates)
    net <- clhls_net_fit_ebic(
      dat, cfg$ebic_gamma, method = cfg$cor_method, use = cfg$cor_use
    )
    W <- net$graph
    G <- qgraph::qgraph(W, layout = "spring", DoNotPlot = TRUE)
    cen <- qgraph::centrality(G)
    Strength <- rowSums(abs(W))
    Closeness <- cen$Closeness
    Betweenness <- cen$Betweenness
    EI <- if (!is.null(cen$ExpectedInfluence)) cen$ExpectedInfluence else rowSums(W)

    tab <- data.frame(
      Label = labels, Items = items, Sex = sx,
      Strength = round(as.numeric(Strength), 3),
      Closeness = round(as.numeric(Closeness), 3),
      Betweenness = round(as.numeric(Betweenness), 3),
      ExpectedInfluence = round(as.numeric(EI), 3),
      N = nrow(dat),
      check.names = FALSE, stringsAsFactors = FALSE
    )
    tabs[[sx]] <- tab
    graphs[[sx]] <- W
    ns[[sx]] <- nrow(dat)
    clhls_net_write_table(tab, file.path(dirs$tab, sprintf("Centrality_%s", sx)))
    save(net, dat, file = file.path(dirs$rdata, sprintf("core_EBIC_%s.RData", sx)))

    s_num <- if (identical(sx, "Female")) 1L else 2L
    clhls_net_save_pdf(file.path(dirs$fig, sprintf("Figure S%d. Centrality %s.pdf", s_num, sx)), function() {
      # print=FALSE：centralityPlot 默认会自己画一页，再 print 会变成两页
      p <- qgraph::centralityPlot(
        G, scale = "raw", standardized = FALSE, print = FALSE,
        include = c("Strength", "Closeness", "Betweenness", "ExpectedInfluence"),
        labels = labels
      ) + ggplot2::xlab("Centrality Value (Raw)")
      print(p)
    }, width = 12, height = 7)
  }

  clhls_net_save_pdf(file.path(dirs$fig, "Figure 4. Male and Female networks.pdf"), function() {
    graphics::layout(matrix(c(1, 2), nrow = 1))
    for (sx in c("Female", "Male")) {
      qgraph::qgraph(graphs[[sx]], layout = "spring", groups = groups, palette = "colorblind",
                     posCol = "#0B6ECC", negCol = "#CC2A2A", negDashed = TRUE, vsize = 7,
                     labels = short, nodeNames = items, legend = TRUE, legend.cex = 0.35,
                     label.cex = 0.9, mar = c(2, 2, 2, 2))
    }
  }, width = 16, height = 8)

  # Table 3：男女并排
  m <- tabs$Male
  f <- tabs$Female
  table3 <- data.frame(
    Label = m$Label, Items = m$Items,
    Male_Strength = m$Strength, Male_Closeness = m$Closeness,
    Male_Betweenness = m$Betweenness, Male_EI = m$ExpectedInfluence,
    Female_Strength = f$Strength, Female_Closeness = f$Closeness,
    Female_Betweenness = f$Betweenness, Female_EI = f$ExpectedInfluence,
    stringsAsFactors = FALSE, check.names = FALSE
  )
  clhls_net_write_table(table3, file.path(dirs$tab, "Table 3. Standardized centrality indices by gender"))

  ctx$results$clhls_sex <- list(
    n_male = tabs$Male$N[1], n_female = tabs$Female$N[1], table3 = table3
  )
  cli::cli_alert_success("性别网络完成: Male={ctx$results$clhls_sex$n_male}, Female={ctx$results$clhls_sex$n_female}")
  ctx
}

register_block("clhls_sex", block_clhls_sex, "CLHLS 分性别症状网络")
