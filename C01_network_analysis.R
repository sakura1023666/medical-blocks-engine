rm(list = ls())
gc()
script_path <- normalizePath(dirname(rstudioapi::getActiveDocumentContext()$path))  # 获取当前文件目录 by dyy
setwd(script_path) # 设定当前文件目录为工作路径
source("../RDATA/initConfig.R")
# install.packages("showtext")

library(mgm) 
library(Hmisc)
library(bootnet)
library(qgraph)
library(glmnet)
library(lavaan)
library(dplyr)
library(gridExtra)
library(networktools)
library(ggplot2)
library(readxl)
library(tidyr)

# Read data
load("../Step05_Change/CHARLS_long.RData")
load("../Step05_Change/ELSA_long.RData")

CHARLS_long1<- CHARLS_long[CHARLS_long$wave==1,]
CHARLS_long1 <- CHARLS_long1[CHARLS_long1$DN == 0,]
CHARLS_long2<- CHARLS_long[CHARLS_long$wave==2,]
CHARLS_long <- rbind(CHARLS_long1,CHARLS_long2)
CHARLS_long <- CHARLS_long %>%
  group_by(ID) %>%
  filter(n() > 1) %>%  # 只保留出现次数大于1的ID
  ungroup()

ELSA_long1<- ELSA_long[ELSA_long$wave==1,]
ELSA_long1 <- ELSA_long1[ELSA_long1$DN == 0,]
ELSA_long2<- ELSA_long[ELSA_long$wave==2,]
ELSA_long <- rbind(ELSA_long1,ELSA_long2)
ELSA_long <- ELSA_long %>%
  group_by(ID) %>%
  filter(n() > 1) %>%  # 只保留出现次数大于1的ID
  ungroup()


class(CHARLS_long)
class(ELSA_long)
colnames(CHARLS_long)
colnames(ELSA_long)
sum(is.na(ELSA_long))

load("../Step04_RCS/cutoff_Model3_CHARLS_MCMI.RData")
cutoff_CHARLS <- cutoff_C

load("../Step04_RCS/cutoff_Model3_ELSA_MCMI.RData")
cutoff_ELSA <- cutoff_C

CHARLS_long$MCMI <- ifelse(CHARLS_long$MCMI>cutoff_CHARLS,1,0)
ELSA_long$MCMI <- ifelse(ELSA_long$MCMI>cutoff_ELSA,1,0)
table(CHARLS_long$MCMI)
table(ELSA_long$MCMI)
str(CHARLS_long)
library(dplyr)

# ELSA_long <- ELSA_long %>%
#   mutate(across(where(is.integer), as.numeric))

str(ELSA_long)

# names(ELSA_long)[names(ELSA_long) == "HSCRP"] <- "CRP"
###数据处理完成
###########################################################################################

# Get variable names from all datasets
names_list <- list(names(CHARLS_long),names(ELSA_long))
all_names <- unlist(names_list)

# Count variable name occurrences
name_counts <- table(all_names)
print("Variable name counts:")
print(name_counts)

# Define covariates
cov0 <- c("T1_Gender", "T1_Weight", "T1_HbA1C", "T1_White_blood_cell_count","T1_Total_Cholesterol")
cov1 <- c("T1_Age",'T1_Race','T1_Smoke', "T1_Gender",'T1_Marital_Status', "T1_Weight", "T1_HbA1C", "T1_White_blood_cell_count","T1_Total_Cholesterol")
# covm <- c("T2_Age", "T2_Gender", "T2_Education", "T2_Weight", "T2_HbA1C", "T2_White_blood_cell_count","T2_CRP")
covm <- c("T2_Age", "T2_Gender",'T2_Race','T2_Smoke','T2_Marital_Status', "T2_Weight", "T2_HbA1C", "T2_White_blood_cell_count","T2_Total_Cholesterol")

# Function to convert long to wide format
convert_to_wide <- function(data_long, cov) {
  # data_long<-ELSA_long
  # data_long<-CHARLS_long
  # cov<-cov1
  cols_to_expand <- names(data_long)[!names(data_long) %in% c("ID", "wave")]
  data_wide <- data_long %>%
    pivot_wider(
      id_cols = ID,
      names_from = wave,
      names_glue = "T{wave}_{.value}",
      values_from = contains(cols_to_expand)
    ) %>%
    select(starts_with("T1"), starts_with("T2")) 
  cov_columns <- data_wide %>%
    select(contains(cov)) %>%
    colnames()
  other_columns <- data_wide %>%
    select(-contains(cov)) %>%
    colnames()
  data_wide <- data_wide %>%
    select(all_of(other_columns), all_of(cov_columns), -contains(covm))
  # data_wide <- as.matrix(data_wide)
  # class(data_wide)
  return(as.matrix(data_wide))
}

# Convert all datasets to wide format
CHARLS_wide <- convert_to_wide(CHARLS_long, cov0)
colnames(CHARLS_wide)
sum(is.na(CHARLS_wide))
ELSA_wide <- convert_to_wide(ELSA_long,  cov1)
colnames(ELSA_wide)
sum(is.na(ELSA_wide))
which(colSums(is.na(ELSA_wide)) > 0)


CHARLS_wide <- as.data.frame(CHARLS_wide)
table(CHARLS_wide$T2_DN)

ELSA_wide <- as.data.frame(ELSA_wide)
table(ELSA_wide$T2_DN)



CLPN.fun <- function(df) {
  # df<-ELSA_wide
  # colnames(ELSA_wide)
  k <- df %>% as.data.frame() %>% select(starts_with("T2")) %>% ncol()  #T2的变量数（随访期）
  num_T1 <- df %>% as.data.frame() %>% select(starts_with("T1")) %>% ncol()  #T1总变量数
  num_T2 <- df %>% as.data.frame() %>% select(starts_with("T2")) %>% ncol()  #T2总变量数
  num_Cov <- num_T1 - num_T2    #协变量个数
  adjMat_Cov <- matrix(0, nrow = (k + num_Cov), ncol = (k + num_Cov))    #初始化矩阵
  
  #Lasso回归建模
  for (i in 1:k) {
    lassoreg_Cov <- cv.glmnet(
      # if(dataset_name == 'CHARLS'){x = as.matrix(df[, c(1:k-1, k*2+3, (k * 2 + 1):(k * 2 + num_Cov))])},
      if(dataset_name == 'ELSA'){x = as.matrix(df[, c(1:k-1, k*2+6, (k * 2 + 1):(k * 2 + num_Cov))])},  #自变量为所有T1变量和协变量
      y = df[, (k + i)],   #第i个随访变量
      nfolds = 10,
      family = "binomial", 
      alpha = 1, 
      standardize = TRUE
    )
    lambda_Cov <- lassoreg_Cov$lambda.min
    #提取最优lambda系数
    adjMat_Cov[(1:(k + num_Cov)), i] <- coef(lassoreg_Cov, s = lambda_Cov, exact = FALSE)[2:(num_Cov + k + 1)]
  }
  #矩阵标准化
  adjMat_Cov1 <- getWmat(
    adjMat_Cov,
    nNodes = k + num_Cov, 
    labels = c("MCMI", paste0("DN", 1:(num_T2 - 2)),"Mediator",paste0("Cov", 1:num_Cov)), 
    diRested = TRUE
  )
  #保留终点变量间的网络
  adjMat_Cov <- adjMat_Cov1[1:k, 1:k]
  return(adjMat_Cov)
}



# Create list of datasets
datasets <- list(
  # CHARLS = CHARLS_wide
  ELSA = ELSA_wide
  # HRS = HRS_wide,
  # MHAS = MHAS_wide,
  # SHARE = SHARE_wide
)

# Estimate networks for all datasets循环处理所有数据集，交叉滞后网络
results <- lapply(names(datasets), function(dataset_name) {
  dataset_name <- 'ELSA'
  current_data <- datasets[[dataset_name]]
  mynetwork <- estimateNetwork(current_data, fun = CLPN.fun, directed = TRUE)
  
  edgeweight_file <- paste0("edgeWeight_", dataset_name, ".csv")
  network_file <- paste0("network_", dataset_name, ".RData")
  
  write.csv(mynetwork$graph, edgeweight_file)#Supplementary Table 21,22,23,24,25
  save(mynetwork, file = network_file)
  
  return(list(network_file = network_file, edgeweight_file = edgeweight_file))
})

# Load network objects
load("network_CHARLS.RData")
network_CHARLS <- mynetwork
network_CHARLS$graph

load("network_ELSA.RData")
network_ELSA <- mynetwork
network_ELSA$graph
# 
# load("network_HRS.RData")
# network_HRS <- mynetwork
# network_HRS$graph
# 
# load("network_MHAS.RData")
# network_MHAS <- mynetwork
# network_MHAS$graph
# 
# load("network_SHARE.RData")
# network_SHARE <- mynetwork
# network_SHARE$graph

rm(mynetwork)

groups11 <- c(
  MCMI1 = "MCMI" ,
  DN1 = "DN", DN2 = "DN", DN3 = "DN", DN4 = "DN", DN5 = "DN", 
  DN6 = "DN", DN7 = "DN", DN8 = "Mediator"
)

myname1 <- c("MCMI", "Waist circumference", "Hypertension", "Diabetes", "Abnormal triglycerides",
             "HDL-C", "Depression", "Sleep quality", "HbA1C")
label1 <- c("MCMI", paste0("DN", 1:7),"HbA1C")
# # Define groups for visualization
# groups11 <- c(
#   CVD1 = "CVD", CVD2 = "CVD", 
#   FI1 = "FI", FI2 = "FI", FI3 = "FI", FI4 = "Highlights", FI5 = "FI", 
#   FI6 = "FI", FI7 = "FI", FI8 = "FI", FI9 = "FI", FI10 = "FI", 
#   FI11 = "FI", FI12 = "FI", FI13 = "FI", FI14 = "FI", FI15 = "FI", 
#   FI16 = "FI", FI17 = "FI", FI18 = "FI", FI19 = "FI", FI20 = "FI", 
#   FI21 = "FI", FI22 = "Highlights", FI23 = "FI", FI24 = "FI", FI25 = "FI", 
#   FI26 = "FI", FI27 = "FI"
# )
# groups12 <- c(
#   CVD1 = "CVD", CVD2 = "CVD", 
#   FI1 = "Highlights", FI2 = "Highlights", FI3 = "FI", FI4 = "FI", FI5 = "FI", 
#   FI6 = "FI", FI7 = "FI", FI8 = "FI", FI9 = "FI", FI10 = "Highlights", 
#   FI11 = "FI", FI12 = "FI", FI13 = "Highlights", FI14 = "FI", FI15 = "FI", 
#   FI16 = "FI", FI17 = "FI", FI18 = "FI", FI19 = "FI", FI20 = "Highlights", 
#   FI21 = "FI", FI22 = "Highlights", FI23 = "FI", FI24 = "FI", FI25 = "FI", 
#   FI26 = "FI", FI27 = "FI"
# )
# groups2 <- c(
#   CVD1 = "CVD", CVD2 = "CVD", 
#   FI1 = "Highlights", FI2 = "Highlights", FI3 = "FI", FI4 = "FI", FI5 = "FI", 
#   FI6 = "FI", FI7 = "FI", FI8 = "FI", FI9 = "Highlights", FI10 = "FI", 
#   FI11 = "FI", FI12 = "Highlights", FI13 = "FI", FI14 = "FI", FI15 = "FI", 
#   FI16 = "FI", FI17 = "FI", FI18 = "FI", FI19 = "Highlights", FI20 = "FI", 
#   FI21 = "Highlights", FI22 = "FI", FI23 = "FI", FI24 = "FI", FI25 = "FI", 
#   FI26 = "FI"
# )
# groups3 <- c(
#   CVD1 = "CVD", CVD2 = "CVD", 
#   FI1 = "Highlights", FI2 = "Highlights", FI3 = "FI", FI4 = "FI", FI5 = "FI", 
#   FI6 = "FI", FI7 = "FI", FI8 = "Highlights", FI9 = "FI", FI10 = "FI", 
#   FI11 = "Highlights", FI12 = "FI", FI13 = "FI", FI14 = "FI", FI15 = "FI", 
#   FI16 = "FI", FI17 = "FI", FI18 = "Highlights", FI19 = "FI", FI20 = "Highlights", 
#   FI21 = "FI", FI22 = "FI", FI23 = "FI", FI24 = "FI", FI25 = "FI"
# )
# 
# # Define node labels
# myname1 <- c("Heart problem", "Stroke", "Hypertension", "Diabetes", "Cancer",
#              "Arthritis", "Chronic lung", "Psychiatric", "Memory", "Eyesight",
#              "Hearing", "Health", "Dressing", "Bathing", "Eating", "Getting in/out bed",
#              "Using toilet", "Preparing meals", "Shopping", "Managing money",
#              "Taking medications", "Walking", "Getting up from chair", "Climbing",
#              "Stooping", "Reaching arms", "Lifting", "Picking up coin", "Cognition"
# )
# myname2 <- c("Heart problem", "Stroke", "Hypertension", "Diabetes", "Cancer",
#              "Arthritis", "Chronic lung", "Memory", "Eyesight",
#              "Hearing", "Health", "Dressing", "Bathing", "Eating", "Getting in/out bed",
#              "Using toilet", "Preparing meals", "Shopping", "Managing money",
#              "Taking medications", "Walking", "Getting up from chair", "Climbing",
#              "Stooping", "Reaching arms", "Lifting", "Picking up coin", "Cognition"
# )
# myname3 <- c("Heart problem", "Stroke", "Hypertension", "Diabetes", "Cancer",
#              "Arthritis", "Chronic lung", "Eyesight",
#              "Hearing", "Health", "Dressing", "Bathing", "Eating", "Getting in/out bed",
#              "Using toilet", "Preparing meals", "Shopping", "Managing money",
#              "Taking medications", "Walking", "Getting up from chair", "Climbing",
#              "Stooping", "Reaching arms", "Lifting", "Picking up coin", "Cognition"
# )
# 
# # Define node labels for visualization
# label1 <- c(paste0("CVD", 1:2), paste0("FI", 1:27))
# label2 <- c(paste0("CVD", 1:2), paste0("FI", 1:26))
# label3 <- c(paste0("CVD", 1:2), paste0("FI", 1:25))
# 
# 

# Function to plot network绘制网络图
plot_network <- function(mat, groups, myname, label, node_colors) {
  mat_name <- deparse(substitute(mat))  
  title_suffix <- sub(".*_", "", mat_name)
  output_file <- paste0("network_", title_suffix, ".pdf")
  
  mat <- exp(mat$graph)  #OR
  mat <- ifelse(mat > 0.7 & mat < 1.3, 0, mat)   #过滤弱关联
  diag(mat) <- 0
  
  edge_colors <- ifelse(mat > 1, "#6095ce", "#e87d72")
  
  pdf(output_file, width = 16, height = 12)
  
  qgraph(mat, 
         groups = groups, 
         layout = "spring", 
         title = title_suffix, 
         title.cex = 1.5,
         nodeNames = myname, 
         labels = label,
         edge.color = edge_colors, 
         layout.par = list(repulse.rad = 80),
         color = node_colors)
  
  dev.off()
  
  return(output_file)
}

plot_network(network_CHARLS, groups11, myname1, label1, c("MCMI" = "#F6B7C6", "DN" = "#c9d8eb", "Circadian Rhythm" = "#82b181"))
plot_network(network_ELSA, groups11, myname1, label1, c("MCMI" = "#F6B7C6", "DN" = "#F0A780", "Circadian Rhythm" = "#82b181"))
# plot_network(network_HRS, groups12, myname1, label1, c("CVD" = "#F6B7C6", "FI" = "#A2DADE", "Highlights" = "#82b181"))
# plot_network(network_MHAS, groups3, myname3, label3, c("CVD" = "#F6B7C6", "FI" = "#f37e78", "Highlights" = "#82b181"))
# plot_network(network_SHARE, groups2, myname2, label2, c("CVD" = "#F6B7C6", "FI" = "#C8BFD9", "Highlights" = "#82b181"))


# Load required libraries
library(bootnet)
library(glmnet)
library(dplyr)
library(qgraph)

# Define the list of network names and their corresponding files
networks <- list(
  # "CHARLS" = "network_CHARLS.RData"
  # ,
  "ELSA" = "network_ELSA.RData"
  # "HRS" = "network_HRS.RData",
  # "MHAS" = "network_MHAS.RData",
  # "SHARE" = "network_SHARE.RData"
)

# Loop through each network and perform analysis网络稳定性分析
for (network_name in names(networks)) {
  # Load the network data
  load(networks[[network_name]])
  assign(paste0("network_", network_name), mynetwork)
  
  # Perform nonparametric bootnet analysis估计边的置信区间
  b1 <- bootnet(get(paste0("network_", network_name)), nCores = 1, nBoots = 1000, directed = TRUE,
                type = "nonparametric", statistics = c("edge"))
  save_file <- paste0("b1_", network_name, ".RData")
  save(b1, file = save_file)
  
  # Perform case bootnet analysis网络稳定性
  b2 <- bootnet(get(paste0("network_", network_name)), nCores = 1, nBoots = 1000, directed = TRUE,
                type = "case", statistics = c("edge"))
  save_file <- paste0("b2_", network_name, ".RData")
  save(b2, file = save_file)
  
  cat(paste("Analysis for", network_name, "completed.\n"))
  
  # Supplementary Figure 25. Bootstrapped confidence intervals of estimated edges across HRS, CHARLS, SHARE, ELSA, and MHAS
  pdf_file <- paste0("edgeCI_", network_name, ".pdf")
  pdf(pdf_file, width = 8, height = 8)
  plot(b1, "edge", order = "sample", labels = FALSE)
  dev.off()
  
  # Supplementary Figure 26. Case-dropping analysis across HRS, CHARLS, SHARE, ELSA, and MHAS
  pdf_file <- paste0("edgeStability_", network_name, ".pdf")
  pdf(pdf_file, width = 8, height = 8)
  plot(b2, "edge", facet = TRUE)
  dev.off()
}

cat("All analyses completed.\n")
