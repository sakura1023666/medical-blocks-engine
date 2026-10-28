rm(list = ls()); gc()
################################################################################
# N05_sex_NCT_marked.R —— 性别分层网络(NCT) + 在表中标记显著结果
# 使用: 非正则化全偏相关(pcor)网络 + NCT性别比较
# 输出: 结果直接保存在当前目录(Step06_性别分层_backup)
################################################################################
args <- commandArgs(trailingOnly = FALSE)
fa <- grep("^--file=", args, value = TRUE)
if (length(fa) > 0) setwd(normalizePath(dirname(sub("^--file=", "", fa[1])), mustWork = FALSE))
cat("工作目录:", getwd(), "\n"); options(width = 220)

suppressPackageStartupMessages({ 
  library(bootnet); library(qgraph); library(NetworkComparisonTest); 
  library(ggplot2); library(openxlsx) 
})

SCRIPT_DIR <- getwd()
DATA_DIR <- normalizePath(file.path(dirname(SCRIPT_DIR), "Step01_基线"), mustWork = FALSE)
COHORTS  <- c("CHARLS","ELSA"); SEXES <- c("Female","Male")
NCT_IT   <- 1000

UNIFIED <- list(
  list(name="Felt Depressed",           CHARLS=c(dc011="Felt Depressed"),             ELSA=c(PScedA="Felt Depressed")),
  list(name="Everything Was an Effort", CHARLS=c(dc012="Everything Was an Effort"),   ELSA=c(PScedB="Everything Was an Effort")),
  list(name="Restless Sleep",           CHARLS=c(dc015="Restless Sleep"),             ELSA=c(PScedC="Restless Sleep")),
  list(name="Happy [POS]",              CHARLS=c(dc016="Happy [POS]"),                ELSA=c(PScedD="Happy [POS]")),
  list(name="Positive Mindset [POS]",   CHARLS=c(dc013="Hopeful About Future [POS]"), ELSA=c(PScedF="Enjoyed Life [POS]")),
  list(name="Negative Mindset",         CHARLS=c(dc014="Felt Fearful"),               ELSA=c(PScedG="Felt Sad")),
  list(name="Felt Lonely",              CHARLS=c(dc017="Felt Lonely"),                ELSA=c(PScedE="Felt Lonely")),
  list(name="Could Not Get Going",      CHARLS=c(dc018="Could Not Get Going"),        ELSA=c(PScedH="Could Not Get Going")))
METS_RAW <- c(waist_cm="Waist Circumference (cm)", hdl_mgdl="HDL-Cholesterol (mg/dL)",
              tg_mgdl="Triglycerides (mg/dL)", meanSBP="Systolic Blood Pressure (mmHg)",
              glu_mgdl="Fasting Glucose (mg/dL)")
LOG_METS <- c("tg_mgdl","meanSBP","glu_mgdl")

build_nodes <- function(coh, sex) {
  e <- new.env(); load(file.path(DATA_DIR, paste0("D01_AfterMI_Data_", coh, ".RData")), envir = e)
  df <- e$data_imp
  df <- df[which(as.character(df$Gender) == sex), , drop = FALSE]
  dep_map  <- setNames(lapply(UNIFIED, `[[`, coh), sapply(UNIFIED, `[[`, "name"))
  dep_cols <- unname(sapply(dep_map, names)); mets_cols <- names(METS_RAW)
  cols <- c(dep_cols, mets_cols)
  dat <- df[complete.cases(df[, cols]), cols, drop = FALSE]
  for (i in seq_along(dep_cols)) {
    cn <- dep_cols[i]; others <- rowSums(dat[, dep_cols[-i], drop=FALSE], na.rm=TRUE)
    r <- cor(dat[[cn]], others, use="pairwise.complete.obs")
    if (!is.na(r) && r < 0) dat[[cn]] <- max(dat[[cn]], na.rm=TRUE) - dat[[cn]]
  }
  for (cn in intersect(LOG_METS, mets_cols))
    dat[[cn]] <- if (any(dat[[cn]] <= 0, na.rm=TRUE)) log1p(dat[[cn]]) else log(dat[[cn]])
  list(dat=dat, ndep=length(dep_cols), nmets=length(mets_cols),
       Label=c(paste0("Depression_",seq_along(dep_cols)), paste0("MetS_",seq_along(mets_cols))),
       Items=c(names(dep_map), unname(METS_RAW)), N=nrow(dat))
}

EBIC_GAMMA <- 0.5
est_ebic <- local({ .g <- EBIC_GAMMA; function(data, verbose=TRUE, ...) {
  S <- cor(data)
  evmin <- min(eigen(S, symmetric=TRUE, only.values=TRUE)$values)
  if (!is.na(evmin) && evmin <= 1e-8) S <- as.matrix(Matrix::nearPD(S, corr=TRUE, keepDiag=TRUE)$mat)
  list(graph=qgraph::EBICglasso(S, nrow(data), gamma=.g, threshold=FALSE),
       intercepts=rep(0, ncol(data)), results=list())
}})

save_plot <- function(stem, plotfun, width=11, height=8, res=300) {
  cairo_pdf(paste0(stem,".pdf"), width=width, height=height, family="sans"); plotfun(); dev.off()
  svg(paste0(stem,".svg"), width=width, height=height); plotfun(); dev.off()
  png(paste0(stem,".png"), width=width, height=height, units="in", res=res); plotfun(); dev.off()
  cat("  [图]", stem, "\n")
}

write_table <- function(df, stem) {
  write.csv(df, paste0(stem,".csv"), row.names=FALSE)
  wb <- createWorkbook(); addWorksheet(wb,"Sheet1")
  hs <- createStyle(fontSize=12, fontName="Times New Roman", halign="center", textDecoration="bold", border="bottom")
  bs <- createStyle(fontSize=12, fontName="Times New Roman", halign="left", valign="center")
  writeData(wb, 1, df, startRow=1, colNames=TRUE, headerStyle=hs)
  if (nrow(df) > 0) addStyle(wb, 1, bs, rows=2:(nrow(df)+1), cols=1:ncol(df), gridExpand=TRUE)
  setColWidths(wb, 1, cols=1:ncol(df), widths="auto")
  saveWorkbook(wb, paste0(stem,".xlsx"), overwrite=TRUE)
  cat("  [表]", stem, "\n")
}

extract_nct_sig <- function(nct, node_names, fdr = "BH", alpha = 0.05) {
  stopifnot(!is.null(nct), !is.null(node_names))
  do_fdr <- !identical(fdr, "none")
  P <- length(node_names)
  
  p_edge <- if (!is.null(nct$einv.pvals)) as.numeric(nct$einv.pvals[["p-value"]])
            else if (!is.null(nct$einf.pvals)) as.numeric(nct$einf.pvals) else NULL
  all_edges <- data.frame(); sig_edges <- data.frame()
  if (!is.null(p_edge) && length(p_edge) > 0) {
    q_edge  <- if (do_fdr) p.adjust(p_edge, method = fdr) else p_edge
    pairs <- tryCatch(as.matrix(combn(node_names, 2)), error = function(e) NULL)
    npair <- if (!is.null(pairs)) ncol(pairs) else NA_integer_
    if (!is.null(pairs) && !is.na(npair) && npair == length(p_edge)) {
      all_edges <- data.frame(
        nodeA = pairs[1, ], nodeB = pairs[2, ],
        p_raw = round(p_edge, 4), q_BH = round(q_edge, 4),
        significant = q_edge < alpha, stringsAsFactors = FALSE, check.names = FALSE)
    } else {
      all_edges <- data.frame(
        edge_idx = seq_along(p_edge), p_raw = round(p_edge, 4), q_BH = round(q_edge, 4),
        significant = q_edge < alpha, stringsAsFactors = FALSE, check.names = FALSE)
    }
    sig_edges <- all_edges[!is.na(all_edges$significant) & all_edges$significant, , drop = FALSE]
  }
  
  p_cent_m <- if (!is.null(nct$diffcen.pval)) as.matrix(nct$diffcen.pval)
              else if (!is.null(nct$cinall)) as.matrix(nct$cinall) else NULL
  all_centrality <- data.frame(); sig_centrality <- data.frame()
  if (!is.null(p_cent_m)) {
    cols <- if (ncol(p_cent_m) >= 1) seq_len(ncol(p_cent_m)) else 1L
    nodename_ok <- !is.null(rownames(p_cent_m)) && all(rownames(p_cent_m) %in% node_names)
    long <- do.call(rbind, lapply(cols, function(j) {
      p <- as.numeric(p_cent_m[, j])
      q <- if (do_fdr) p.adjust(p, method = fdr) else p
      nm <- if (nodename_ok) rownames(p_cent_m)
            else if (nrow(p_cent_m) == P) node_names
            else seq_len(nrow(p_cent_m))
      idx <- if (ncol(p_cent_m) > 1) colnames(p_cent_m)[j] else "strength"
      data.frame(node = nm, index = idx,
                 p_raw = round(p, 4), q_BH = round(q, 4),
                 significant = q < alpha, stringsAsFactors = FALSE, check.names = FALSE)
    }))
    all_centrality <- long
    sig_centrality <- long[!is.na(long$significant) & long$significant, , drop = FALSE]
  }
  
  list(fdr = fdr, alpha = alpha,
       n_edges_sig = nrow(sig_edges), n_centrality_sig = nrow(sig_centrality),
       all_edges = all_edges, sig_edges = sig_edges,
       all_centrality = all_centrality, sig_centrality = sig_centrality)
}

cent_bysex <- function(net, nm, raw = TRUE) {
  W <- net$graph
  G <- qgraph::qgraph(W, layout = "spring", DoNotPlot = TRUE)
  c <- qgraph::centrality(G)
  st <- rowSums(abs(W)); ei <- rowSums(W); cl <- c$Closeness; bw <- c$Betweenness
  if (!raw) { st <- (st - mean(st))/sd(st); ei <- (ei - mean(ei))/sd(ei); cl <- (cl - mean(cl))/sd(cl); bw <- (bw - mean(bw))/sd(bw) }
  data.frame(
    Strength          = round(st, 3),
    ExpectedInfluence = round(ei, 3),
    Closeness         = round(cl, 3),
    Betweenness       = round(bw, 3),
    row.names = nm, check.names = FALSE)
}

for (coh in COHORTS) {
  cat("\n==================== ", coh, " 性别分层 / NCT ====================\n")
  
  L_male   <- build_nodes(coh, "Male")
  L_female <- build_nodes(coh, "Female")
  dat_male <- L_male$dat
  dat_female <- L_female$dat
  nm <- L_male$Label
  items <- L_male$Items
  ndep <- L_male$ndep
  P <- ncol(dat_male)
  
  net_male   <- estimateNetwork(dat_male, fun=est_ebic)
  net_female <- estimateNetwork(dat_female, fun=est_ebic)
  
  groups <- list(Depression = 1:ndep, MetS = (ndep+1):P)
  short  <- c(paste0("D", 1:ndep), paste0("M", 1:(P-ndep)))
  
  cM <- cent_bysex(net_male, nm, raw = TRUE)
  cF <- cent_bysex(net_female, nm, raw = TRUE)
  
  cat("  NCT 置换 (it =", NCT_IT, ")...\n")
  nct <- tryCatch(
    NCT(dat_male, dat_female, it = NCT_IT, binary.data = FALSE, paired = FALSE,
        test.edges = TRUE, edges = "all", test.centrality = TRUE,
        centrality = "strength", progressbar = FALSE),
    error = function(e) { message("  NCT 失败: ", conditionMessage(e)); NULL })
  
  if (!is.null(nct)) {
    sig <- extract_nct_sig(nct, nm, fdr = "BH", alpha = 0.05)
    
    sig_edges_df <- sig$sig_edges
    sig_cent_df <- sig$sig_centrality
    
    sig_edges_df$stars <- ifelse(sig_edges_df$p_raw < 0.01, "**", 
                                 ifelse(sig_edges_df$p_raw < 0.05, "*", ""))
    
    sig_cent_df$stars <- ifelse(sig_cent_df$p_raw < 0.01, "**", 
                                ifelse(sig_cent_df$p_raw < 0.05, "*", ""))
    
    if (nrow(sig_edges_df) > 0) {
      sig_edges_output <- data.frame(
        nodeA = sig_edges_df$nodeA,
        nodeB = sig_edges_df$nodeB,
        nodeA_label = items[match(sig_edges_df$nodeA, nm)],
        nodeB_label = items[match(sig_edges_df$nodeB, nm)],
        p_value = sig_edges_df$p_raw,
        q_BH = sig_edges_df$q_BH,
        significance = sig_edges_df$stars,
        stringsAsFactors = FALSE, check.names = FALSE)
      write_table(sig_edges_output, paste0("NCTsig_edges_", coh, "_marked"))
      
      cat("    FDR 显著差异边:\n")
      for (i in 1:nrow(sig_edges_output)) {
        cat(sprintf("      %s (%s) - %s (%s)  p=%.4f%s\n", 
                    sig_edges_output$nodeA[i], sig_edges_output$nodeA_label[i],
                    sig_edges_output$nodeB[i], sig_edges_output$nodeB_label[i],
                    sig_edges_output$p_value[i], sig_edges_output$significance[i]))
      }
    }
    
    if (nrow(sig_cent_df) > 0) {
      sig_cent_output <- data.frame(
        node = sig_cent_df$node,
        node_label = items[match(sig_cent_df$node, nm)],
        p_value = sig_cent_df$p_raw,
        q_BH = sig_cent_df$q_BH,
        significance = sig_cent_df$stars,
        Male_Strength = cM[sig_cent_df$node, "Strength"],
        Female_Strength = cF[sig_cent_df$node, "Strength"],
        Strength_diff = cF[sig_cent_df$node, "Strength"] - cM[sig_cent_df$node, "Strength"],
        stringsAsFactors = FALSE, check.names = FALSE)
      write_table(sig_cent_output, paste0("NCTsig_centrality_", coh, "_marked"))
      
      cat("    FDR 显著差异中心性节点:\n")
      for (i in 1:nrow(sig_cent_output)) {
        cat(sprintf("      %s (%s)  p=%.4f%s  Male_strength=%.3f  Female_strength=%.3f  Diff=%.3f\n", 
                    sig_cent_output$node[i], sig_cent_output$node_label[i],
                    sig_cent_output$p_value[i], sig_cent_output$significance[i],
                    sig_cent_output$Male_Strength[i], sig_cent_output$Female_Strength[i],
                    sig_cent_output$Strength_diff[i]))
      }
    }
    
    tab3 <- data.frame(Label = nm, Items = items,
                       Male_Strength   = cM[nm, "Strength"],   
                       Male_ExpectedInfluence = cM[nm, "ExpectedInfluence"],  
                       Male_Closeness   = cM[nm, "Closeness"],   
                       Male_Betweenness   = cM[nm, "Betweenness"],
                       Female_Strength = cF[nm, "Strength"],   
                       Female_ExpectedInfluence = cF[nm, "ExpectedInfluence"], 
                       Female_Closeness = cF[nm, "Closeness"],   
                       Female_Betweenness = cF[nm, "Betweenness"],
                       Sex_diff_strength = round(cF[nm, "Strength"] - cM[nm, "Strength"], 3),
                       NCT_p_strength = NA,
                       NCT_q_BH_strength = NA,
                       NCT_significance = "",
                       stringsAsFactors = FALSE, check.names = FALSE)
    
    if (nrow(sig$all_centrality) > 0) {
      for (i in 1:nrow(sig$all_centrality)) {
        node_idx <- match(sig$all_centrality$node[i], nm)
        if (!is.na(node_idx)) {
          tab3$NCT_p_strength[node_idx] <- sig$all_centrality$p_raw[i]
          tab3$NCT_q_BH_strength[node_idx] <- sig$all_centrality$q_BH[i]
          if (sig$all_centrality$p_raw[i] < 0.01) {
            tab3$NCT_significance[node_idx] <- "**"
          } else if (sig$all_centrality$p_raw[i] < 0.05) {
            tab3$NCT_significance[node_idx] <- "*"
          }
        }
      }
    }
    
    write_table(tab3, paste0("Table3_", coh, "_sex_centrality_marked"))
    
    W_male <- net_male$graph
    W_female <- net_female$graph
    
    edge_info <- data.frame()
    upper <- upper.tri(W_male)
    for (i in 1:P) {
      for (j in 1:P) {
        if (i < j) {
          edge_info <- rbind(edge_info, data.frame(
            nodeA = nm[i],
            nodeB = nm[j],
            nodeA_label = items[i],
            nodeB_label = items[j],
            Male_edge_weight = round(W_male[i, j], 4),
            Female_edge_weight = round(W_female[i, j], 4),
            Edge_diff = round(W_female[i, j] - W_male[i, j], 4),
            NCT_p = NA,
            NCT_q_BH = NA,
            NCT_significance = "",
            stringsAsFactors = FALSE))
        }
      }
    }
    
    if (nrow(sig$all_edges) > 0) {
      for (k in 1:nrow(sig$all_edges)) {
        idx <- which((edge_info$nodeA == sig$all_edges$nodeA[k] & edge_info$nodeB == sig$all_edges$nodeB[k]) |
                     (edge_info$nodeA == sig$all_edges$nodeB[k] & edge_info$nodeB == sig$all_edges$nodeA[k]))
        if (length(idx) > 0) {
          edge_info$NCT_p[idx] <- sig$all_edges$p_raw[k]
          edge_info$NCT_q_BH[idx] <- sig$all_edges$q_BH[k]
          if (sig$all_edges$p_raw[k] < 0.01) {
            edge_info$NCT_significance[idx] <- "**"
          } else if (sig$all_edges$p_raw[k] < 0.05) {
            edge_info$NCT_significance[idx] <- "*"
          }
        }
      }
    }
    
    edge_info <- edge_info[order(abs(edge_info$Edge_diff), decreasing = TRUE), ]
    write_table(edge_info, paste0("Edge_weights_", coh, "_sex_diff_marked"))
    
    save(nct, sig, file = paste0("nct_", coh, ".RData"))
  }
  
  save_plot(paste0("Network_", coh, "_Male"), function() {
    qgraph::qgraph(net_male$graph, layout="spring", groups=groups, palette="colorblind",
                   posCol="#0B6ECC", negCol="#CC2A2A", negDashed=TRUE, vsize=7,
                   labels=short, nodeNames=items, legend=TRUE, legend.cex=0.5, label.cex=0.95,
                   title=paste0(coh, " Male (pcor) N=", nrow(dat_male)), mar=c(2,2,4,2))
  })
  
  save_plot(paste0("Network_", coh, "_Female"), function() {
    qgraph::qgraph(net_female$graph, layout="spring", groups=groups, palette="colorblind",
                   posCol="#0B6ECC", negCol="#CC2A2A", negDashed=TRUE, vsize=7,
                   labels=short, nodeNames=items, legend=TRUE, legend.cex=0.5, label.cex=0.95,
                   title=paste0(coh, " Female (pcor) N=", nrow(dat_female)), mar=c(2,2,4,2))
  })
}

cat("\n==================== N05 完成 ====================\n")
