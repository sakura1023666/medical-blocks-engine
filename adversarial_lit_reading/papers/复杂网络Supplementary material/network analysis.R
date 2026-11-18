library(glmnet)
library(qgraph) 
library(networktools)
library(ggplot2)
library(bootnet)
library(mgm)
library(dplyr)
myData <- read.csv("original data.csv",fileEncoding = "GBK")
myData=myData[6:22]
labels <- c('Feeling bothered','Trouble focus','Feeling depressed','Trouble doing anything',
            'Hopelessness','Felt fearful','Lack of happiness',
            'Loneliness','Inability to get going','Sleep quality',
            'Nervousness or anxiety','Uncontrollable worry','Generalized worry',
            'Trouble relaxing','Restlessness',
            'Irritability','Fear of horrible events')
colnames(myData)<- c('CESD1','CESD2','CESD3','CESD4','CESD5','CESD6','CESD7',
                     'CESD8','CESD9','CESD10','GAD1','GAD2','GAD3','GAD4','GAD5',
                     'GAD6','GAD7')
groups <- c(
  'CESD','CESD','CESD','CESD','CESD','CESD','CESD',
  'CESD','CESD','CESD','GAD','GAD','GAD','GAD','GAD',
  'GAD','GAD')

# node predictability 
p <- ncol(myData)
object <- mgm(data = as.matrix(myData),
              type = rep("g", p),
              level = rep(1, p),
              lambdaSel = "CV",
              ruleReg = "OR",
              pbar = FALSE)
prediction <- predict(object = object, 
                      data = myData)
nodpre<- prediction$error
write.csv(nodpre,"node predictability.csv")
#To apply the Lasso algorithm for sparsifying a correlation matrix with a tuning parameter set to 0.5
cor(myData)
network2 <- estimateNetwork(myData, default = "EBICglasso", tuning = 0.5,
                            corMethod="cor",corArgs=list(method="spearman",
                                                    use="pairwise.complete.obs")) 
plot(network2, 
     layout = "spring",
     groups = groups, 
     label.cex = 1,
     label.color = 'black', 
     negDashed = T, 
     legend=T,
     node.width=0.8,
     nodeNames = labels, 
     legend.cex = 1, 
     legend.mode = 'style1', 
)

g <- qgraph(cor(myData), layout="spring",
            labels=labels, groups=groups, label.scale=FALSE,
            label.cex=2, node.width=1, color=c("mediumspringgreen",
                                               "red")) 


center<-centrality(network2) #centrality indices
strgth<-as.data.frame(center$InDegree)
Closeness<-as.data.frame(center$Closeness)
Between<-as.data.frame(center$Betweenness)

#centrality indices figure
P<-centralityPlot(network2, include=c("Strength","Closeness","Betweenness","OutExpectedInfluence")) #中心化结果可视化
#Bridge centrality
b <- bridge(cor(myData), communities= groups, directed=FALSE) 
plot(b, include=c( "Bridge Strength","Bridge Expected Influence (1-step)", "Bridge Closeness"),
     theme_bw=FALSE, raw0 = TRUE, signed=TRUE) 

###Network Stability and Accuracy###
nonParametricBoot <- bootnet(myData, nBoots = 1000, 
                             default = "EBICglasso", threshold = FALSE,
                             type="nonparametric", 
                             statistics="all")

plot(nonParametricBoot, labels=FALSE, order="sample")
plot(nonParametricBoot, "edge", plot = "difference", onlyNonZero = TRUE, order = "sample")
summary(nonParametricBoot) %>% ungroup %>% filter(type == "edge") %>% arrange(-sample) %>% View

#Difference Test for Strength
plot(nonParametricBoot, statistics="Strength", plot="difference",order = "mean")
###Accuracy analysis ###
caseDroppingBoot <- bootnet(myData, nBoots = 1000, threshold = FALSE, default = "EBICglasso", 
                            type="case", statistics="all")
corStability(caseDroppingBoot)
plot(caseDroppingBoot, statistics="all")
plot(caseDroppingBoot, statistics = c("Strength","Closeness","Betweenness"))

