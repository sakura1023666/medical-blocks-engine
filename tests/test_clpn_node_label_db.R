# tests/test_clpn_node_label_db.R
root <- "/mnt/e/01block/01Block-new-Final"
source(file.path(root, "R/clpn_node_label_db.R"))
source(file.path(root, "R/clpn_network_plot.R"))

db <- clpn_node_label_db(root)
stopifnot(nrow(db) > 40L)
stopifnot(identical(clpn_node_display("condition1", root), "Abdominal obesity"))
stopifnot(identical(clpn_node_short("condition6", root), "C6"))
stopifnot(identical(clpn_node_short("ePWV", root), "ePWV"))
stopifnot(identical(clpn_node_display("hibpe", root), "Hypertension"))
stopifnot(identical(clpn_node_display("TyG", root), "Triglyceride-glucose index"))
stopifnot(identical(clpn_canonical_stem("BMXWAIST", root), "condition1"))
stopifnot(identical(clpn_node_display("pscedc", root), "Sleep"))
sh <- clpn_plot_short_labels(c(paste0("condition", 1:7), "ePWV"), root)
stopifnot(identical(sh, c(paste0("C", 1:7), "ePWV")))
cat("OK clpn_node_label_db\n")
