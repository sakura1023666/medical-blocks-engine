###############################################################################
#  literature_packages.R — 文献完整复现所需 R 包（Windows R-4.5.1 安装）
###############################################################################

.lit_pkg_install <- function(pkgs, repos = "https://cloud.r-project.org") {
  miss <- pkgs[!vapply(pkgs, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1L))]
  if (!length(miss)) return(invisible(miss))
  utils::install.packages(miss, repos = repos, quiet = TRUE)
  invisible(miss)
}

literature_ensure_packages <- function(groups = c("network", "bayesian", "trajectory")) {
  groups <- unique(groups)
  pkgs <- character(0)
  if ("network" %in% groups) {
    pkgs <- c(pkgs, "bootnet", "qgraph", "networktools", "mgcv")
  }
  if ("bayesian" %in% groups) {
    pkgs <- c(pkgs, "brms", "bayesplot", "pROC", "rstan")
  }
  if ("trajectory" %in% groups) {
    pkgs <- c(pkgs, "lcmm", "survival", "splines", "ggplot2", "tidyr", "dplyr")
  }
  pkgs <- unique(pkgs)
  .lit_pkg_install(pkgs)
  invisible(pkgs)
}
