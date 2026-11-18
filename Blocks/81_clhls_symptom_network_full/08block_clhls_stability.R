###############################################################################
#  clhls_stability — bootstrap 稳定性 / 边权准确性 / 差异检验（Fig 5 + Suppl）
#  register_block: "clhls_stability"
#  算法对齐既往 Step07：nonparametric + case-dropping bootnet
###############################################################################



if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x
}


block_clhls_stability <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "Blocks/81_clhls_symptom_network_full/00clhls_net_common.R"), local = FALSE)
  clhls_net_require_pkgs()
  cfg <- clhls_net_cfg(ctx)
  dirs <- clhls_net_out_dirs(ctx)
  e <- clhls_net_load_core(dirs, "EBIC")
  net <- e$net

  cli::cli_alert_info("非参数 bootstrap nBoots={cfg$n_boots}, nCores={cfg$n_cores}")
  boot_param <- bootnet::bootnet(
    net,
    statistics = c("edge", "strength", "closeness", "betweenness", "expectedInfluence"),
    nBoots = cfg$n_boots, nCores = cfg$n_cores, type = "nonparametric"
  )

  cli::cli_alert_info("case-dropping bootstrap nBoots={cfg$n_boots}")
  boot_case <- bootnet::bootnet(
    net,
    statistics = c("strength", "closeness", "betweenness", "expectedInfluence"),
    nBoots = cfg$n_boots, nCores = cfg$n_cores, type = "case"
  )
  cs <- bootnet::corStability(boot_case)
  cs_df <- data.frame(
    Statistic = names(cs),
    CS_coefficient = round(unname(cs), 3),
    Stable = ifelse(cs >= 0.25, "yes", "NO (<0.25)"),
    stringsAsFactors = FALSE
  )
  clhls_net_write_table(cs_df, file.path(dirs$tab, "CS_coefficients"))

  clhls_net_save_pdf(file.path(dirs$fig, "Figure 5. Network stability and edge-weight accuracy.pdf"), function() {
    p1 <- plot(boot_case, statistics = c("strength", "closeness", "betweenness", "expectedInfluence"))
    p2 <- plot(boot_param, labels = FALSE, order = "sample", statistics = "edge")
    grid::grid.newpage()
    grid::pushViewport(grid::viewport(layout = grid::grid.layout(1, 2)))
    print(p1, vp = grid::viewport(layout.pos.row = 1, layout.pos.col = 1))
    print(p2, vp = grid::viewport(layout.pos.row = 1, layout.pos.col = 2))
  }, width = 12, height = 6)

  clhls_net_save_pdf(file.path(dirs$fig, "Figure S3. Edge-weight difference test.pdf"), function() {
    print(plot(boot_param, "edge", plot = "difference", onlyNonZero = TRUE, order = "sample"))
  }, width = 12, height = 12)

  clhls_net_save_pdf(file.path(dirs$fig, "Figure S4. Strength difference test.pdf"), function() {
    print(plot(boot_param, "strength", plot = "difference",
               order = "sample", decreasing = TRUE))
  }, width = 10, height = 9)

  save(boot_param, boot_case, cs, file = file.path(dirs$rdata, "boot_CLHLS.RData"))

  ctx$results$clhls_stability <- list(n_boots = cfg$n_boots, cs = cs)
  cli::cli_alert_success("稳定性/准确性完成")
  ctx
}

register_block("clhls_stability", block_clhls_stability, "CLHLS 网络稳定性与准确性")
