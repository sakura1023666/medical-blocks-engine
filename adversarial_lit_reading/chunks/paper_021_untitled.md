# Page 1

Investigating the potential risk of cadmium exposure on Osteoporosis: An 
integrated multi-omics approach
Yiwei Li a, Xuezhen Liang a, Yifa Rong a, Kai Jiang a, Jiahao Zhang a, Gang Li b,*
a The First Clinical Medical School, Shandong University of Traditional Chinese Medicine, Jinan, Shandong, China
b Orthopaedic, Affiliated Hospital of Shandong University of Traditional Chinese Medicine, Jinan, Shandong, China
A R T I C L E I N F O
Edited by Yong Liang
Keywords:
Cadmium
Osteoporosis
Network toxicology
Single-cell RNA sequencing
Geniposide
A B S T R A C T
Osteoporosis (OP) is a chronic progressive bone disease, and its occurrence and development under cadmium 
exposure remain unclear. This study aims to explore the role of cadmium exposure in the pathogenesis of OP 
through a comprehensive analysis of multi-omics data. Through cross-sectional analysis using National Health 
and Nutrition Examination Survey (NHANES), we observed that cadmium exposure is a risk factor for OP. 
Bioinformatics and machine learning further emphasized the importance of FOXO3, CCND1, MAP1LC3B, 
HMOX1, and MT1G as independent risk factors for OP, which was confirmed through robust internal validation. 
Single-cell RNA sequencing revealed the heterogeneous expression of cadmium-related genes in different cell 
populations, with a particular emphasis on the role of HMOX1 in cell communication and signaling. Through 
Gene Set Enrichment Analysis (GSEA), we found that HMOX1 is positively correlated with the activity of M2 
macrophage polarization. Through Mendelian randomization (MR), molecular docking, and molecular dynamics 
simulations, we further discovered that geniposide can target and bind to HMOX1. Ultimately, this compre­
hensive study elucidates the role of cadmium exposure in OP and highlights the potential of HMOX1 as a 
therapeutic target in alleviating the adverse effects of the disease.
1. Introduction
Cadmium is a toxic heavy metal that is widely present in the envi­
ronment and can pose a serious threat to human health (Genchi et al., 
2020). With the acceleration of industrialization, cadmium is not only 
extensively released into the environment through industrial activities, 
but is also widely present in consumer goods. Epidemiological studies 
suggest that food and cigarettes are the two main routes of cadmium 
intake (Zhu et al., 2024). Cadmium is associated with an increased risk 
of various diseases and can significantly raise the risk of chronic con­
ditions such as cardiovascular diseases, kidney damage, and cancer 
(Satarug et al., 2010; Verzelloni et al., 2024). Cadmium has a long 
half-life, allowing it to accumulate in human organs over time and is 
considered a key inducer of inflammation, oxidative stress, and other 
processes(Ma et al., 2022).
Osteoporosis (OP) is a common skeletal disease characterized by 
decreased bone mass and deterioration of bone microstructure, leading 
to increased bone fragility and a significantly higher risk of fractures. 
Recent research has focused on the impact of cadmium exposure on bone 
metabolism. A metabolomics study has shown that cadmium exposure 
can block the electron transport chain in human osteoblast-like cells, 
resulting in pyruvate accumulation and the buildup of nucleic acids 
associated with aging (Tian et al., 2021). Additionally, cadmium expo­
sure activates the DNA damage response through phosphorylation of 
ATM and H2AX, while promoting the acetylation of SOD2, which in­
duces mitochondrial dysfunction and exacerbates the aging process of 
osteoblasts (Zhou et al., 2023). Further research has revealed the critical 
role of NF-κB in the senescence of bone marrow-derived mesenchymal 
stromal cells induced by cadmium exposure (Luo et al., 2021). A sys­
tematic review and meta analysis found that even low levels of envi­
ronmental cadmium exposure (urinary cadmium >0.5 µg/g creatinine) 
are a risk factor for OP (Kunioka et al., 2022). A case-control study found 
that blood cadmium levels are associated with an increased risk of 
fractures (Wallin et al., 2024). A study based on the Swedish cohort of 
the Osteoporotic Fractures in Men Study (MrOS) revealed that cadmium 
exposure is associated with reduced cortical thickness, cortical area, and 
trabecular bone volume fraction in elderly men (Wallin et al., 2021). A 
similar phenomenon has been validated in the Korean population (Kim 
* Corresponding author.
E-mail addresses: liyiweizyy@163.com (Y. Li), 60170109@sdutcm.edu.cn (X. Liang), 2018128134@sdutcm.edu.cn (Y. Rong), 2023111093@sdutcm.edu.cn
(K. Jiang), zjh160037@foxmail.com (J. Zhang), sdszylg@163.com (G. Li). 
Contents lists available at ScienceDirect
Ecotoxicology and Environmental Safety
journal homepage: www.elsevier.com/locate/ecoenv
https://doi.org/10.1016/j.ecoenv.2025.118502
Received 27 February 2025; Received in revised form 20 May 2025; Accepted 9 June 2025  
Ecotoxicology and Environmental Safety 301 (2025) 118502 
Available online 14 June 2025 
0147-6513/© 2025 The Author(s). Published by Elsevier Inc. This is an open access article under the CC BY-NC license ( http://creativecommons.org/licenses/by- 
nc/4.0/ ).

# Page 2

et al., 2021). Another predictive model found that cadmium exposure 
plays an important role in predicting decreased bone mineral density 
(BMD) (Ximenez et al., 2021). Human biomonitoring surveys emphasize 
that cadmium exposure represents a significant proportion of the soci­
etal costs associated with OP (Ougier et al., 2021). As an environmental 
pollutant, cadmium may play a crucial role in the onset and progression 
of OP.
This study employed various research methods aimed at exploring 
the potential role of cadmium exposure in OP. Through network toxi­
cology analysis, we constructed a gene-toxicity association network to 
gain deeper insights into the expression patterns of cadmium exposure- 
related genes in OP and their potential toxicological mechanisms. Key 
genes were identified through machine learning, and bioinformatics and 
single-cell RNA sequencing were combined to reveal the complex rela­
tionship between cadmium exposure and mechanisms related to OP, 
such as M2 macrophage polarization. Single-cell sequencing analysis 
further revealed the specific expression of cadmium exposure-related 
genes across different cell types in OP, thereby enhancing understand­
ing of the underlying pathological mechanisms. In addition, Drug target 
Mendelian randomization (MR) analysis, molecular docking, and mo­
lecular dynamics simulations were employed to provide clues for the 
development of novel targeted therapeutic drugs in the future.
2. Method
2.1. Cross-sectional analysis
National Health and Nutrition Examination Survey (NHANES) 
selected representative samples from the U.S. population to assess their 
health and nutritional status. To ensure ethical standards, the survey 
was approved by the National Center for Health Statistics. All selected 
individuals voluntarily provided written informed consent before being 
included in the study. The relevant data for this study were publicly 
available through the website (https://www.cdc.gov/nchs/nhanes/ 
index.htm). Data from multiple NHANES cycles were selected for sta­
tistical analysis. A total of 13417 participants were included in our study 
(Fig. 1).
2.1.1. Variables
Femoral neck bone mineral density (FN BMD) is widely used in 
clinical practice for OP prediction (Kanis et al., 2008; Wright et al., 
2014). Dual-energy X-ray absorptiometry (DXA) is easy to use, with low 
radiation exposure, and is a common method for BMD measurement 
(Baran et al., 1997). Blood cadmium levels were directly measured from 
whole blood samples using mass spectrometry (Caudill et al., 2008). 
Based on the characteristics of the studied population, the following 
covariates were selected for analysis. These covariates include sex, age, 
race, education, marital status, family income-to-poverty ratio, smok­
ing, drinking, hypertension, diabetes, and hyperlipidemia.
2.1.2. Regression analysis
To further assess the relationship between blood cadmium and FN 
BMD, weighted multiple linear regression analysis was used to examine 
the association. In 2013–2014, blood analysis indicators were measured 
for all participants aged 1–11 years, while only half of the participants 
aged 12 years and older were measured. Therefore, for participants aged 
12 and above, "WTSH2YR" was used as the weight variable; participants 
aged 1–11 in this cycle and other cycles, "WTMEC2YR" was used as the 
weight variable. To control for confounding factors, we adjusted for 
different variables and constructed various linear regression models.
2.2. Construction of networks
To further investigate the mechanism by which cadmium affects 
bone mineral density, we conducted a network toxicology analysis 
(Chang et al., 2024; He et al., 2024). Initially, we retrieved gene targets 
related to cadmium exposure from the Comparative Toxicogenomics 
Database (CTD, https://ctdbase.org), a comprehensive platform that 
Fig. 1. Overview of the study design.
Y. Li et al.                                                                                                                                                                                                                                        
Ecotoxicology and Environmental Safety 301 (2025) 118502 
2

# Page 3

aggregates biological effect data for chemicals, metals, and other sub­
stances (Davis et al., 2023). In this study, we used the keyword “Cad­
mium” and applied a filtering criterion to retain only genes with more 
than 10 interactions. OP data were sourced from the Gene Expression 
Omnibus (GEO) database, specifically bulk datasets GSE7158 and 
GSE56815 (Lei et al., 2009; Zhou et al., 2018). GEOquery was employed 
to download and extract both the expression matrix and sample meta­
data (Davis and Meltzer, 2007). Expression data were normalized using 
the normalizeBetweenArrays function from the limma package, fol­
lowed by log2 transformation. Probe annotations were mapped to gene 
symbols using platform annotation files (GPL96 and GPL570). Differ­
ential expression analysis was performed with the limma package 
(Ritchie et al., 2015). By intersecting the genes identified in both the 
CTD and GEO datasets, we ultimately selected key genes for further 
analysis. Subsequently, we utilized Cytoscape software to construct a 
"Cadmium - gene - OP" network diagram, visualizing the relationships 
between cadmium exposure, genes, and OP (Shannon et al., 2003). 
Enrichment analysis of the intersected genes was carried out using the 
clusterProfiler package to elucidate their biological relevance in OP(Xu 
et al., 2024). Gene Ontology (GO) analysis encompassed biological 
processes (BP), cellular components (CC), and molecular functions (MF). 
Kyoto Encyclopedia of Genes and Genomes (KEGG) enrichment analysis 
highlighted significant pathways associated with the intersected genes, 
enhancing our understanding of their potential mechanisms in OP. The 
Protein-Protein Interaction (PPI) network for the intersected genes was 
constructed using the STRING database (https://cn.string-db.org), 
employing default parameters and visualizing the network based on 
degree (Szklarczyk et al., 2023).
2.3. Machine learning
We conducted differential expression analysis by merging GSE7158 
and GSE56815 using the limma package in R (Ma and Li, 2024). To 
assess the predictive power of these genes, we employed machine 
learning techniques. Specifically, we applied random forest and Support 
Vector Machine - Recursive Feature Elimination (SVM-RFE) methods to 
reduce the feature space and identify key genes for classification 
(Breiman, 2001; Cortes and Vapnik, 1995; Guyon et al., 2002; Liaw and 
Wiener, 2007). Feature selection was performed using the caret package 
(Kuhn, 2008), and a random forest model was trained with the ran­
domForest package (Breiman, 2001; Liaw and Wiener, 2007). The 
importance of variables was determined using the MeanDecreaseGini 
criterion, with the number of trees set to 1000 to ensure model stability 
and optimize the tree count to minimize the error rate. Feature selection 
was further refined through SVM-RFE, which iteratively eliminated less 
predictive features, retaining only those most informative for the 
outcome. A logistic regression model was subsequently fitted using the 
selected genes to evaluate the relationship between gene expression and 
the disease. The model was trained with the glm function, and odds 
ratios (OR) with 95 % confidence intervals (CI) were computed for each 
gene to assess their effects. To validate the robustness of the model, 
bootstrap resampling with 1000 iterations was performed to estimate 
model accuracy and calculate the Area Under the Curve (AUC) for 
performance evaluation. Sensitivity and specificity analyses were also 
conducted during the bootstrap to assess classification performance 
across varying threshold settings.
A nomogram was constructed using logistic regression to predict the 
probability of the outcome, and a calibration curve was plotted to 
compare predicted and observed probabilities. Additionally, decision 
curve analysis (DCA) was applied to evaluate the clinical utility of the 
models(Vickers and Elkin, 2006).
2.4. Single-cell RNA sequencing data analysis
2.4.1. Data acquisition and preprocessing
Single-cell sequencing analysis was conducted using the Seurat 
package (version 4.3.0). The raw data from GSE147287 were imported 
using the Read10X function and stored as a Seurat object using the 
CreateSeuratObject function (Wang et al., 2021; Zheng et al., 2017). For 
quality control, cells with low or high feature counts were filtered using 
subset(nFeature_RNA > 200 & nFeature_RNA < 10,000). Cells with 
more than 15 % mitochondrial gene content were also removed. The 
data were then normalized using NormalizeData(normalization.method 
= "LogNormalize"), and highly variable genes were selected for subse­
quent analysis using FindVariableFeatures(selection.method = "vst"). 
Principal component analysis (PCA) was performed with the RunPCA 
function (Jolliffe, 2002). Clustering was carried out using FindNeigh­
bors(dims = 1:30) and FindClusters(resolution = seq(0.1, 1, 0.2)) to 
explore the optimal resolution across different parameter settings. 
UMAP dimensionality reduction was applied and visualized using 
RunUMAP(dims = 1:15) (McInnes et al., 2018). Cell type annotation 
was based on known markers from the literature (Wang et al., 2024). 
The expression of key marker genes was visualized using the DotPlot 
function.
2.4.2. Cell-cell communication analysis
Cell-cell communication analysis was performed using the CellChat 
package, utilizing the CellChatDB.human within CellChat, with a focus 
on secreted signal transduction (Jin et al., 2021; Su et al., 2024). 
Overexpressed genes and ligand-receptor pairs were identified using the 
identifyOverExpressedGenes and identifyOverExpressedInteractions 
functions, respectively. The identified ligand and receptor genes were 
then mapped to the human protein-protein interaction network to pro­
vide a more comprehensive biological interpretation. Communication 
probabilities between different cell populations were calculated using 
the computeCommunProb function. Cell communication pathways were 
inferred with the computeCommunProbPathway function, with rare 
interactions filtered out. The results were visualized using the netVi­
sual_circle function, which displayed both the number and intensity of 
interactions. Specific signaling pathways were further analyzed using 
the netVisual_aggregate function. Lastly, we calculated and visualized 
the centrality of different cell types within the communication network, 
showcasing their roles in signal transduction through heatmaps and 
scatter plots.
2.4.3. GSEA
GSEA was a widely utilized method for identifying biological path­
ways that were significantly enriched in gene expression data 
(Subramanian et al., 2005). Differentially expressed genes across 
various cell subgroups were identified using FindMarkers function. Gene 
sets for GSEA were obtained from the Molecular Signatures Database 
(MSigDB, http://software.broadinstitute.org/gsea/msigdb) and the 
literature to explore biological differences between distinct cell sub­
groups (Liberzon et al., 2015).
2.5. Drug-target MR analysis
2.5.1. Data sources
To further investigate the potential relationship between key genes 
and OP. We performed Drug-target MR. We used publicly accessible 
GWAS datasets. The related eQTL data for genes were obtained from 
eQTLGen (https://eqtlgen.org/), which provides data from 31684 Eu­
ropean individuals’ blood samples (Vosa et al., 2021). The Genetic 
Factors for Osteoporosis Consortium (GEFOS) is a large international 
collaborative organization that provides numerous GWAS data related 
to bone health (Zheng et al., 2015). UK Biobank (UKB) is one of the 
largest human genetic cohort biobank in the world, and its research data 
are significant for understanding human health and diseases (Donertas 
et al., 2021). We selected FN BMD from GEFOS and OP from UKB as 
outcomes (Table S1). This study followed the STROBE guidelines.
Y. Li et al.                                                                                                                                                                                                                                        
Ecotoxicology and Environmental Safety 301 (2025) 118502 
3

# Page 4

2.5.2. Instrumental variables (IVs) selection
We selected single nucleotide polymorphisms (SNPs) strongly asso­
ciated with genes to construct IVs (p < 5.00E-08), and extracted expo­
sure data based on the gene’s location, choosing SNPs within the 
±1000 kb range of each gene’s transcription start site (TSS). We 
removed linkage disequilibrium based on the European population 
reference genome, setting r² to 0.1 and kb to 10,000. The F-statistic can 
be used to assess the strength of the IVs (Bowden et al., 2019). We 
calculated the value using F= β² /se². The selection process follows the 
three main assumptions of MR: (1) a strong and robust association be­
tween IVs and exposure; (2) IVs are independent of confounding factors 
affecting the exposure-outcome relationship; (3) genetic variation af­
fects the outcome only through the exposure and not through other 
pathways (Emdin et al., 2017).
2.5.3. MR and Meta-analysis
MR analysis was conducted using the TwoSampleMR package. This 
study used five MR methods to explore the relationship between genes 
and diseases. Inverse Variance Weighted (IVW) method assumes that all 
instrumental variables are valid and that there is no horizontal pleiot­
ropy, providing high statistical power (Slob and Burgess, 2020). 
Therefore, we selected the IVW as the primary analytical method. Het­
erogeneity was assessed using Cochran’s Q test (Greco et al., 2015). 
Pleiotropy refers to the potential of a gene or genetic variation to have 
more than one independent phenotype. Horizontal pleiotropy was tested 
using MR-Egger regression intercept (Bowden et al., 2015). 
Leave-one-out sensitivity analysis was applied to assess the robustness of 
the results (Burgess et al., 2017). To obtain more stable results, we used 
the meta package to perform a meta analysis of the IVW estimates from 
different cohort MR analyses and visualized the results using the forest 
function (Schwarzer et al., 2015).
2.6. Molecular docking and Molecular dynamic simulation
2.6.1. Candidate drug prediction
The Drug Signatures Database (http://dsigdb.tanlab.org/) collected 
a large number of drug-related genes and compounds(Yoo et al., 2015). 
We utilized the database to evaluate whether the target genes could 
serve as drug targets and predict the potential effects of the drugs.
2.6.2. Molecular docking
To evaluate the binding energy and interaction patterns between the 
candidate drug and its target. Molecular docking was performed using 
AutoDock Vina 1.1.2 (Trott and Olson, 2010). We obtained the protein 
crystal structure from the PubChem Compound Database (https://p 
ubchem.ncbi.nlm.nih.gov/). The structural data of the drug were ob­
tained from the Protein Data Bank (PDB, http://www.rcsb.org/). We 
prepared the protein using PyMol 1.8.5 software, including hydroge­
nation, removal of water molecules, etc., and converted the PDB format 
of small molecules and receptor proteins into PDBQT format (Delano, 
2002). During docking, the conformation with the lowest binding en­
ergy was selected as the docking conformation, and visualization anal­
ysis was performed using Plip 2021 (Adasme et al., 2021).
2.6.3. Molecular dynamics simulations
To further assess the stability and interactions of the molecular 
docking, we performed molecular dynamics simulations using AMBER 
22(Salomon-Ferrer et al., 2013). The charges of small molecule were 
calculated using the antechamber module and the Hartree-Fock (HF) 
SCF/6–31 G* method in Gaussian 09 software. We selected the TIP3P 
water model and added sodium and chloride ions to the complex to 
neutralize the charges. The system was optimized using the steepest 
descent method and the conjugate gradient method. Following energy 
optimization, the system was heated for 200 ps. The system was main­
tained at a temperature of 298.15 K and underwent a 500 ps canonical 
ensemble 
(NVT). 
A 
500 ps 
equilibration 
simulation 
under 
isothermal-isobaric ensemble (NPT) conditions was performed for the 
entire system. Finally, both complex systems underwent 100 ns NPT 
under periodic boundary conditions. The system pressure was set to 
1 atm, the integration time step was 2fs, and the trajectory was saved 
every 10 ps for subsequent analysis.
2.7. Statistical analysis
All statistical analyses were performed using R version 4.1.3. For 
continuous variables, group differences were assessed using Student’s t- 
test or the Wilcoxon rank-sum test. For categorical variables, group as­
sociations were assessed using chi-square tests or Fisher’s exact test 
based on the expected frequency of each category. A p-value less than 
0.05 was considered statistically significant. The data used in this study 
are publicly available and have received ethical approval.
3. Results
3.1. Cross-Sectional analysis
FN BMD was grouped by quartiles (Table 1). Notably, participants 
with lower FN BMD tended to have higher blood cadmium levels. We 
further employed multiple linear regression models and found a signif­
icant negative correlation between blood cadmium and FN BMD, with 
this significance persisting after adjusting for confounders. Specifically, 
with an increase in blood cadmium, FN BMD decreased by 0.006 g/cm² 
(-0.011, −0.001, p = 0.017). These results suggested a significant 
negative correlation between blood cadmium levels and BMD, indi­
cating that cadmium exposure was an important factor in reducing BMD 
(Table 2).
3.2. Identification of blood cadmium targets affecting OP
We selected cadmium-related genes with "Interactions > 10" from 
the CTD. OP-related genes were obtained from the GEO. A total of 24 
significantly different genes were identified (Fig. 2A). To further explore 
the potential biological functions of key genes, we performed GO and 
KEGG enrichment analysis. We found that these genes are involved in 
the following BP: response to cadmium ion, response to oxidative stress, 
and cellular response to chemical stress. CC included transcription 
repressor complex, nuclear envelope, mitochondrial outer membrane, 
and others. MF analysis revealed RNA polymerase II−specific 
DNA−binding transcription factor binding, DNA−binding transcription 
factor binding, cholesterol transfer activity, and others. KEGG analysis 
showed that the genes were enriched in pathways such as endocrine 
resistance, mineral absorption, and lipid and atherosclerosis (Fig. 2B). 
Based on the results of GO and KEGG enrichment, we found that these 
genes are closely related to immune response, oxidative stress, and other 
processes, providing clues for further investigating their potential roles 
in diseases. Proteins such as AKT1, JUN, TP53, EGFR, and HMOX1 
showed tight interactions with other proteins in the network (Fig. 2C). In 
OP, FOXO3, MAP1LC3B, and MT1G were significantly upregulated, 
while CCND1 and HMOX1 were downregulated (Fig. 2D–F). Correlation 
analysis indicated relationships between multiple genes (Fig. 2G). We 
identified key genes associated with cadmium exposure and revealed 
their potential roles such as immune response and oxidative stress, 
providing important clues for further investigation of their functions in 
related diseases.
3.3. Machine learning identifies key genes
To identify key genes from another perspective, we employed ma­
chine learning approaches. Random forest analysis showed that the 
genes with the highest MeanDecreaseGini scores included CCND1, 
FOXO3, SIRT1, MT1G, HMOX1, MAP1LC3B, HSP90B1, TP53, EGFR, 
and XAF1 (Fig. 3A, B). The intersection of top genes from random forest 
Y. Li et al.                                                                                                                                                                                                                                        
Ecotoxicology and Environmental Safety 301 (2025) 118502 
4

# Page 5

and SVM-RFE algorithms highlighted six common genes: FOXO3, 
CCND1, MAP1LC3B, HMOX1, EGFR, and MT1G (Fig. 3C). Multivariable 
logistic regression further confirmed that FOXO3, MAP1LC3B, and 
MT1G were positively correlated with OP, while CCND1 and HMOX1 
were negatively correlated with OP (Fig. 3D). Internal validation con­
ducted through bootstrap analysis showed that the model had stable 
sensitivity and specificity (Fig. 3E–H). A nomogram was constructed to 
visualize the model, and calibration curves indicated robust predictive 
performance (Fig. 3I, J). DCA showed that the combination of these 
genes outperformed the use of any single gene in enhancing clinical 
decision-making (Fig. 3K).
3.4. Single-cell RNA sequencing of HMOX1 in macrophages
Single-cell RNA sequencing of OP identified macrophages, mono­
cytes, b cells, and other subpopulations (Fig. 4A, B). Among the key 
Table 1 
Characteristics of the participants.
Characteristics
Q1
Q2
Q3
Q4
p Value
Age (years)
​
61.68 ± 0.36
53.54 ± 0.40
48.24 ± 0.35
43.09 ± 0.38
< 0.0001
Blood cadmium (ug/L)
​
0.58 ± 0.02
0.55 ± 0.01
0.55 ± 0.02
0.51 ± 0.01
0.01
Sex (%)
​
​
​
​
​
< 0.0001
​
Male
1171(30.10)
1637(46.78)
1849(54.73)
2134(63.71)
​
​
Female
2212(69.90)
1719(53.22)
1495(45.27)
1200(36.29)
​
Race (%)
​
​
​
​
​
< 0.0001
​
Black
349(4.40)
487(6.42)
688(10.48)
1071(18.37)
​
​
White
2054(80.10)
1778(76.20)
1550(70.89)
1244(61.61)
​
​
Mexican American
399(4.24)
543(6.30)
599(8.15)
563(9.06)
​
​
Other
581(11.26)
548(11.08)
507(10.48)
456(10.97)
​
Marital status (%)
​
​
​
​
​
< 0.0001
​
Married/Living with Partner
1887(60.32)
2146(68.56)
2175(69.67)
2070(65.88)
​
​
Never married
255(7.39)
330(8.66)
491(12.92)
713(20.51)
​
​
Widowed/Divorced/Separated
1241(32.29)
880(22.78)
678(17.41)
551(13.61)
​
Family income-to-poverty radio (%)
​
​
​
​
​
< 0.001
​
Low income
936(17.14)
921(15.79)
924(17.52)
968(19.36)
​
​
Middle income
1387(38.27)
1221(33.39)
1260(32.79)
1239(35.20)
​
​
High income
1060(44.60)
1214(50.83)
1160(49.69)
1127(45.44)
​
Education (%)
​
​
​
​
​
0.02
​
Less Than 9th Grade
412(5.74)
337(4.41)
346(5.23)
302(5.22)
​
​
9–11th Grade
470(10.73)
470(10.15)
456(9.51)
555(12.85)
​
​
High School Grad/GED or Equivalent
835(24.82)
771(23.49)
805(25.50)
800(24.82)
​
​
Some College or AA degree
913(28.79)
976(30.98)
970(30.07)
968(30.02)
​
​
College Graduate or above
753(29.92)
802(30.97)
767(29.69)
709(27.09)
​
Drinking (%)
​
​
​
​
​
< 0.0001
​
Former
648(15.94)
574(13.60)
520(12.86)
447(11.46)
​
​
Never
626(14.15)
404(9.74)
351(8.20)
295(7.27)
​
​
Mild
1276(43.04)
1244(39.49)
1156(37.89)
1116(35.61)
​
​
Moderate
467(15.70)
543(19.15)
527(17.96)
542(17.13)
​
​
Heavy
366(11.18)
591(18.02)
790(23.09)
934(28.53)
​
Smoking (%)
​
​
​
​
​
< 0.0001
​
Former
1017(29.49)
1002(29.60)
888(27.17)
748(23.53)
​
​
Never
1722(52.78)
1595(48.70)
1606(48.72)
1707(50.92)
​
​
Now
644(17.73)
759(21.69)
850(24.12)
879(25.55)
​
Hypertension (%)
​
​
​
​
​
< 0.0001
​
No
1503(51.59)
1789(57.09)
1962(60.85)
2055(64.82)
​
​
Yes
1880(48.41)
1567(42.91)
1382(39.15)
1279(35.18)
​
Diabetes Mellitus (%)
​
​
​
​
​
0.36
​
No
2359(76.45)
2417(76.79)
2492(78.15)
2450(76.52)
​
​
IFG
169(4.62)
154(4.56)
165(4.89)
166(5.33)
​
​
IGT
183(4.38)
128(3.19)
118(3.62)
128(3.97)
​
​
Yes
672(14.54)
657(15.47)
569(13.34)
590(14.18)
​
Hyperlipidemia (%)
​
​
​
​
​
< 0.0001
​
No
701(21.80)
846(24.90)
899(26.65)
968(29.72)
​
​
Yes
2682(78.20)
2510(75.10)
2445(73.35)
2366(70.28)
​
Note：
Mean ± SD for continuous variables: the p-value was calculated by the weighted linear regression model. (%) for categorical variables: the p-value was calculated by 
the weighted chisquare test.
GED, general educational development; IFG, Impaired Fasting Glycaemia; IGT, Impaired Glucose Tolerance.
Table 2 
Associations between blood cadmium and BMD.
Model 1
Model 2
Model 3
Variables
β (95 %CI)
p Value
β (95 %CI)
p Value
β (95 %CI)
p Value
Femoral neck BMD
−0.011 (−0.017,−0.005)
< 0.001
−0.012(−0.017,−0.008)
< 0.0001
−0.006(−0.011,−0.001)
0.017
Note：
Model 1-Unadjusted.
Model 2-Model 1 additionally adjusted for the age, sex, race, marital status, family income-to-poverty ratio, and education.
Model 3-Model 2 plus additional adjustment for drinking, smoking, hypertension, diabetes mellitus, and hyperlipidemia.
BMD, bone mineral density.
Y. Li et al.                                                                                                                                                                                                                                        
Ecotoxicology and Environmental Safety 301 (2025) 118502 
5

# Page 6

genes selected by machine learning, we found that HMOX1 was most 
significantly expressed in macrophages (Fig. 4C, D). Therefore, we 
stratified Macrophages into HMOX1-positive (HMOX1 + Macr) and 
HMOX1-negative (HMOX1- Macr) subpopulations. HMOX1 + Macr had 
stronger interactions with DC, B cells, NK/T cells, and monocytes 
(Fig. 4E, S1), indicating that HMOX1 mediated intercellular communi­
cation. Notably, ANXA1 and MIF signaling pathways were enriched in 
HMOX1 + Macr, potentially driving macrophage polarization. Path­
ways such as LGALS9 and TNFSF13B suggested their involvement in 
immune regulation (Fig. 4F). Pathway analysis highlighted increased 
activity of pathways such as SPP1, ANNEXIN, and GRN in 
HMOX1 + Macr (Fig. 4G). HMOX1 + Macr had higher incoming and 
outgoing interaction strength (Fig. 4H). This indicated that HMOX1 may 
regulate the function of macrophages and affect their interactions with 
other cells. Notably, similar to cell communication, GSEA also found 
that HMOX1 + Macr was associated with the upregulation of M2 
macrophage polarization (Fig. 4I). These results suggested that HMOX1 
was closely related to the function and intercellular interactions of 
macrophages and affected macrophage polarization.
3.5. Drug-target MR study between HMOX1 and OP
3.5.1. Preliminary analysis
To further explore the potential role of HMOX1 in OP, we performed 
Drug-target MR. After excluding SNPs using strict criteria, we selected 
IVs that met the standards. The F-values of all IVs were greater than 10, 
Fig. 2. Network Toxicology for Cadmium and OP. (A)Target genes between cadmium and OP. (B)Enrichment results of GO and KEGG. The circle size reflects the 
proportion of cells expressing each gene, and the color intensity indicates the level of gene expression. (C)The PPI network for target genes. Greater importance is 
represented by a darker color. (D)Boxplots showing the expression levels of target genes in the OP and control (CT) groups. Significance is indicated as follows: 
*p < 0.05, **p < 0.01, ***p < 0.001 and **** p < 0.0001. (E)Volcano plot of target genes. Upregulation is represented in red, while downregulation is shown in blue. 
(F)Heatmap of target genes. Upregulation is represented in orange, while downregulation is shown in blue. (G)Correlation analysis of the expression levels of target 
genes. Strong positive correlations are shown in darker red, and strong negative correlations are shown in darker blue.
Y. Li et al.                                                                                                                                                                                                                                        
Ecotoxicology and Environmental Safety 301 (2025) 118502 
6

# Page 7

indicating that there were no weak instrumental variables (Table S2-S5). 
We found that HMOX1 increased FN BMD (β=0.0399, 95 % CI: 
0.0076–0.0722, p = 1.54E-02) and acted as a protective factor for OP 
(OR=0.9989, 95 % CI: 0.9979–0.9998, p = 2.32E-02), which was 
consistent with the results of multivariable logistic regression.
3.5.2. Replication and meta-analysis
We performed the analysis in the replication cohort in the same 
manner to increase the stability of the results (Table S6, S7). We also 
found that HMOX1 is a protective factor for OP (OR=0.9986, 95 % CI: 
0.9974–0.9997, p = 1.46E-02). The study results showed no heteroge­
neity or pleiotropy (Table S8, S9). Leave-one-out analysis, scatter plots, 
and funnel plots supported the robustness of the MR estimates 
(Fig. 5A–I). Meta-analysis further revealed that HMOX1 is a protective 
factor for OP (Fig. 5J). These results further suggest from a genetic 
perspective that HMOX1 may have a potential protective role in OP.
3.6. Candidate drug prediction
3.6.1. Molecular docking
Based on the results of the drug enrichment analysis, we found that 
geniposide can target HMOX1. Geniposide and HMOX1 were selected 
for docking, with a binding energy of −6.9 (kcal/mol), suggesting a 
good docking result. Hydrogen bonds indicate the binding strength be­
tween the ligand and the protein. Geniposide and HMOX1 formed 
hydrogen bonds with HIS-25, TYR-134, SER-142, LYS-179, and ARG- 
183. These interactions formed the basis for the binding of the small 
molecule and the protein (Fig. 6A).
3.6.2. Molecular dynamics simulations
To further improve the accuracy of the simulation, we performed 
molecular dynamics simulations based on molecular docking to capture 
the dynamic behavior and stability of the complex more precisely. We 
found that the complex reached a stable state after 20 ns, with the root 
mean square deviation (RMSD) fluctuation range smaller than 1 Å, 
indicating good stability of the complex (Fig. 6B). The root mean square 
fluctuation (RMSF) showed an overall fluctuation range between 0.5 Å 
Fig. 3. Machine Learning Identifies Key Genes. (A) The curve illustrates the error rate of the Random Forest model as the number of decision trees increases. The x- 
axis represents the number of trees, while the y-axis denotes the corresponding error. (B) Ranking of gene importance in the Random Forest model based on the 
decrease in the Gini index. (C) Venn diagram indicating that the key genes FOXO3, CCND1, MAP1LC3B, HMOX1, EGFR and MT1G are identified in both the SVM 
model and the Random Forest model. (D) Odds ratios (OR) and 95 % confidence intervals for the key genes, demonstrating the strength of their association with the 
model. (E) Internal validation of the model using the receiver operating characteristic (ROC) curve, with an area under the curve (AUC) of 0.883. (F) Distribution of 
the AUC values for the model. (G) Sensitivity analysis of the AUC curve. (H) Specificity analysis of the AUC curve. (I) Nomogram displaying the contribution of 
FOXO3, CCND1, MAP1LC3B, HMOX1, EGFR and MT1G to the total risk score, used for outcome prediction. (J) Calibration curve comparing the predicted proba­
bilities with the observed outcomes, with the mean absolute error reflecting the calibration accuracy of the model. (K) Decision curve analysis (DCA) of the key genes 
(FOXO3, CCND1, MAP1LC3B, HMOX1, EGFR and MT1G), demonstrating that the combination of these genes outperforms individual genes in improving clinical 
decision-making.
Y. Li et al.                                                                                                                                                                                                                                        
Ecotoxicology and Environmental Safety 301 (2025) 118502 
7

# Page 8

and 2 Å, with two distinct peaks between residues 0–50, indicating 
higher activity, but no significant conformational changes occurred 
(Fig. 6C). The radius of gyration (RoG) fluctuation was also stable, 
further indicating the compact structure of the complex (Fig. 6D). The 
binding energy calculated using the molecular mechanics generalized 
born surface area (MM-GBSA) method was −22.78 (kcal/mol) (Table 3). 
The top ten amino acids contributing to the binding of the protein-ligand 
complex are shown in Fig. 6E. The docking complex exhibited a stable 
hydrogen bond pattern (Fig. 6F). Additionally, we extracted the complex 
conformations at every 10 ns interval during the 0–100 ns process 
(Figure S2). In conclusion, our results showed that the complex 
exhibited minimal conformational changes during the simulation and 
remained stable, indicating that geniposide has the potential to target 
and bind to HMOX1.
4. Discussion
This study aimed to elucidate the key role and biological mechanisms 
of cadmium exposure in the pathogenesis of OP. Through a cross- 
sectional study of NHANES, we found a significant negative correla­
tion between blood cadmium and BMD. Network toxicology was per­
formed by integrating the CTD and GEO, and a PPI network was 
constructed. Key genes were further identified through machine 
learning, and their expression in specific cells was observed using single- 
cell sequencing analysis. We found that the expression of HMOX1 was 
significant in macrophages. Cell communication analysis revealed that 
HMOX1 + Macr had higher communication activity. It was found that 
HMOX1 + Macr were associated with the upregulation of M2 macro­
phage polarization through GSEA. MR demonstrated the potential pro­
tective effect of HMOX1 in OP at the genetic level. Furthermore, 
molecular docking and molecular dynamics simulations showed that 
geniposide could specifically target and bind to HMOX1, offering 
Fig. 4. Single-cell RNA sequencing Analysis of Key Genes in OP. (A)UMAP plot of different cell clusters, indicated by various colors. (B)Single-cell annotation in­
formation. (C)Expression differences of key genes (FOXO3, CCND1, MAP1LC3B, HMOX1, EGFR and MT1G) in different cell types. The size of the circles represents 
the proportion of cells expressing the gene, while the color intensity indicates expression levels. (D)Expression of HMOX1 in UMAP plot.The color intensity indicates 
the density. (E)Left panel: the quantity of interactions between various cell types, with thicker lines represent a higher number of interactions. Right panel: the 
intensity of communication between cell types, with thicker lines signifying stronger interactions. (F)Communication probability and signaling pathways between 
HMOX1 + and HMOX1- Macr and other cell types. Red indicates higher probability, blue indicates lower probability, and larger circles indicate smaller P-value. (G) 
Signaling patterns divided into outgoing and incoming categories. Darker colors indicate higher relative signaling strength, while lighter colors indicate lower 
relative strength. (H)Comparison of interaction strength. The x-axis represents the outgoing interaction strength, and the y-axis represents the incoming interaction 
strength. The color indicates cell types and the size of the circles represents the strength. (I) GSEA of differential genes between the HMOX1 + and HMOX1- Macr. 
Score > 0 indicates that HMOX1 + Macr are associated with upregulation of pathway.
Y. Li et al.                                                                                                                                                                                                                                        
Ecotoxicology and Environmental Safety 301 (2025) 118502 
8

# Page 9

potential directions for intervention therapy.
Cadmium is a commonly found toxic heavy metal in the environ­
ment, and it has been shown to be closely related to decreased BMD and 
the onset of OP. Based on the representative sample in NHANES, we 
found a significant negative correlation between blood cadmium and FN 
BMD, but the biological mechanisms behind this process remain unclear, 
with inflammation being a widely discussed factor. An observational 
study based on electroplating workers found that serum levels of IL-6 
and TNF-α were significantly higher in the cadmium exposure group 
compared to the non-exposure group, suggesting that cadmium 
exposure is closely related to inflammation (Ramadan and Saif Eldin, 
2022). Cadmium exposure depletes glutathione (GSH) and disrupts the 
binding of NRF2 with the ARE (Chou and Tsai, 2023). A study has shown 
that cadmium exposure induces oxidative stress in osteoblasts by 
inhibiting the NRF2/NQO1 pathway (Jia et al., 2023). In the absence of 
NRF2, L-NRF1 is compensatorily upregulated, which subsequently in­
creases the expression of NFATc1, a critical transcription factor in 
osteoclast differentiation (Liu et al., 2024). The overexpression of 
NFATc1 enhances RANKL expression and activates NF-κB, thus pro­
moting osteoclastogenesis. HMOX1 has been shown to alleviate this 
Fig. 5. Durg-target MR and Meta analysis. (A)Leave−one−out plot of HMOX1 on FNBMD. (B)Scatter plot of HMOX1 on FNBMD. (C)Forest plot of HMOX1 on 
FNBMD. (D)Leave−one−out plot of HMOX1 on OP in the preliminary analysis. (E)Scatter plot of HMOX1 on OP in the preliminary analysis. (F)Forest plot of HMOX1 
on OP in the preliminary analysis. (G)Leave−one−out plot of HMOX1 on OP in the replication analysis. (H)Scatter plot of HMOX1 on OP in the replication analysis. 
(I)Forest plot of HMOX1 on OP in the replication analysis. (J)Meta analysis of different OP cohorts.
Y. Li et al.                                                                                                                                                                                                                                        
Ecotoxicology and Environmental Safety 301 (2025) 118502 
9

# Page 10

process (Tan et al., 2022). It is important to note that activated NF-κB 
also promotes the expression of NFATc1, establishing a positive feed­
back loop that further accelerates osteoclast differentiation, with reac­
tive oxygen species (ROS) playing a crucial role in this mechanism. Even 
low levels of cadmium exposure (blood cadmium <2.40 μg/L) may 
disrupt redox balance by reducing antioxidant enzyme activity and 
increasing lipid peroxidation, leading to an increase in ROS, oxidative 
stress, activation of NF-κB and IL-8 release, and induction of IL-6 and 
TNF-α release (Freitas and Fernandes, 2011; Goyal et al., 2021). To 
further explore its specific mechanisms in OP, we conducted network 
toxicology and identified 24 key genes. Enrichment analysis also 
revealed that these genes were closely related to NF-κB signaling, in­
flammatory response, and oxidative phosphorylation in OP. Further 
single-cell sequencing analysis revealed that HMOX1 was most signifi­
cant in macrophages.
HMOX1 is a key enzyme involved in heme catabolism and can pro­
duce biliverdin and carbon monoxide (Naito et al., 2014). HMOX1 is 
induced under the stimulation of various stressors, such as oxidative 
stress and inflammatory cytokines. NRF2 dissociates from KEAP1 in 
response to stress stimuli, translocates to the nucleus, and interacts with 
small musculoaponeurotic fibrosarcoma (sMAF) proteins to recognize 
and bind the ARE sequence, thereby positively promoting the tran­
scription of HMOX1 (Che et al., 2021). Cells lacking HMOX1 exhibit 
increased sensitivity to oxidative damage (Tanaka et al., 2011). NRF2 
activators have been utilized to enhance HMOX1 activity, thus main­
taining redox homeostasis. BACH1 has been shown to compete with 
NRF2 for binding to the HMOX1 promoter region, inhibiting its 
expression and negatively regulating the NRF2 signaling pathway. 
NF-κB plays a crucial role in bone metabolism; its activation inhibits 
osteoblast differentiation and promotes osteoclastogenesis, thereby 
accelerating bone resorption. HMOX1 and its metabolites inhibit the 
NF-κB signaling pathway through several mechanisms. CO and bili­
verdin, produced during heme metabolism, play key roles in this pro­
cess. CO inhibits RANKL-induced osteoclast differentiation by 
suppressing the ROS/IKK/NF-κB signaling pathway (Bak et al., 2017). 
Additionally, CO interferes with TLR4 transport and restricts the trans­
location of NF-κB to the nucleus (Watabe et al., 2025). CO also induces 
p65 S-glutathionylation, leading to NF-κB inactivation (Yeh et al., 
2014). CO can activate the NRF2 signaling pathway, induce HMOX1 
expression, create a positive feedback loop, and promote M2 polariza­
tion in macrophages (Jin et al., 2022). Biliverdin is converted to bili­
rubin by biliverdin reductase; both compounds participate in ROS 
clearance and inhibit oxidative stress-induced NF-κB activation (Huang 
et al., 2022). Both biliverdin and bilirubin suppress IL-18-mediated 
NF-κB activation, and bilirubin further inhibits NF-κB pathway activa­
tion by blocking p65 phosphorylation (Li et al., 2020; Zabalgoitia et al., 
2008). The schematic diagram of the signaling pathways is shown in 
Fig. 7. HMOX1 has anti-inflammatory protective effects, and the absence 
of HMOX1 leads to elevated levels of circulating inflammatory markers 
such as TNF-α (Chudy et al., 2024). Pre-treatment with CO or bilirubin 
significantly reduces IL-1B release from macrophages, suggesting the 
potential role of HMOX1 in inflammatory regulation (Vitali et al., 2020). 
Activation of the NRF2/HMOX1 pathway can effectively improve 
inflammation and cell apoptosis induced by heavy metal mixtures 
(Eddie-Amadi et al., 2022). HMOX1 can inhibit the activity of iNOS 
(inducible nitric oxide synthase) in macrophages and is associated with 
an anti-inflammatory macrophage phenotype (Townsend et al., 2014). 
Fig. 6. Molecular Docking and Molecular Dynamic Simulation between Geniposide and HMOX1. (A)Binding mode of geniposide and HMOX1. The left panel shows 
the overall binding pose, while the right panel illustrates the interaction details with residues. The blue lines represent hydrogen bonds, and the yellow dashed lines 
indicate salt bridges. B-D) RMSD, RMSF, Rog of the complex. Smaller fluctuations suggest a more stable structure. (E)The top 10 residues contributing to the binding 
affinity of the complex. (F)Variation in the number of hydrogen bonds of the complex during molecular dynamics simulations.
Table 3 
Binding free energies and energy components predicted by 
MM/GBSA (kcal/mol).
System name
Geniposide/HMOX1
ΔEvdw
−27.23 ± 2.19
ΔEelec
−11.92 ± 4.21
ΔGGB
20.18 ± 4.16
ΔGSA
−3.80 ± 0.25
ΔGbind
−22.78 ± 2.82
ΔEvdW: van der Waals energy.
ΔEelec: electrostatic energy.
ΔGGB: electrostatic contribution to solvation.
ΔGSA: non-polar contribution to solvation.
ΔGbind: binding free energy.
Y. Li et al.                                                                                                                                                                                                                                        
Ecotoxicology and Environmental Safety 301 (2025) 118502 
10

# Page 11

Other research further revealed that HMOX1 not only promotes 
macrophage polarization towards the M2 subtype but also suppresses 
pro-inflammatory responses, stimulates IL-10 secretion, and boosts the 
antioxidant capacity of macrophages (Lv et al., 2023). HMOX1 expres­
sion was positively correlated with M2 polarization-related markers and 
could serve as a therapeutic strategy to enhance M2 polarization (Ye 
et al., 2021). Regulating the M2/M1 macrophage ratio under the NF-κB 
pathway and inhibiting oxidative stress through the NRF2/HMOX1 
pathway could effectively alleviate periodontitis and promote new bone 
formation (Yin et al., 2025). This is similar to our findings. We found 
that HMOX1 + Macr was associated with the upregulation of M2 
macrophage polarization, while HMOX1 was downregulated in OP, 
suggesting that macrophages under cadmium exposure may have 
stronger pro-inflammatory characteristics, which means that cadmium 
exposure may promote bone metabolic imbalance and exacerbate OP 
progression by regulating macrophage polarization.
HMOX1, as a potential target, plays an important regulatory role in 
the occurrence and progression of various diseases. A multi-omics study 
suggested that HMOX1 could be a drug target for upper and lower res­
piratory diseases (Wang et al., 2025). However, its role in OP remains 
unclear. We found that HMOX1 has a protective effect in OP through 
drug-target MR. Further molecular docking showed that geniposide can 
target and bind to HMOX1, and molecular dynamics simulations 
confirmed the stability of the binding. Geniposide, an iridoid glycoside 
derived from the fruit of Gardenia jasminoides (Xiaofeng et al., 2012), 
has garnered attention for its potential role in the prevention and 
treatment of OP. Research has demonstrated that geniposide enhances 
the expression of NRF2 and HMOX1, reducing cadmium-induced 
oxidative stress damage in osteoblasts (He et al., 2019). The 
NF-κB/HIF-1α signaling pathway mediated by HMOX1 exerts 
anti-inflammatory effects (Jin et al., 2021). Upregulating HMOX1 
through the PI3-kinase-JNK-1/2-Nrf2 pathway can enhance the 
anti-inflammatory capacity of macrophages (Jeon et al., 2011). This is 
similar to our findings. In summary, geniposide may regulate bone 
metabolism by inhibiting inflammation, with targeting HMOX1 being 
one of its key mechanisms of action.
Our study presents several limitations that warrant consideration. 
Firstly, this study used multi-omics analysis to explore the key role of 
HMOX1 in cadmium exposure. These results suggest correlational, 
rather than definitive causal, regulatory relationships. Inflammatory 
responses, M2 macrophage polarization, and other factors exhibit 
complex interactions in cadmium-induced OP, and their biochemical 
dynamics require further experimental and systems biology exploration. 
Secondly, the population in the MR study was focused on the European 
population, so extrapolating these findings to populations with other 
genetic backgrounds, such as Asians, should be done with caution. 
Additionally, computational predictions cannot fully capture the 
complexity of biological systems, and the anti-inflammatory activity of 
geniposide in OP still requires multi-level validation. These limitations 
highlight the need for caution in interpreting our findings and under­
score the importance of complementary studies to validate and expand 
upon our conclusions.
In summary, this study explored the potential mechanisms of 
cadmium-induced OP through multi-omics analysis and identified po­
tential drug targets. The study covered cross-sectional analysis, network 
toxicology, bioinformatics, single-cell sequencing analysis, and drug- 
target MR, providing multidimensional support and enhancing the 
reliability of the results. We found that cadmium exposure is a signifi­
cant risk factor for osteoporosis, HMOX1 may exert a protective effect by 
regulating M2 macrophage polarization, and geniposide can target and 
bind to HMOX1. Our findings not only deepened the understanding of 
bone loss under cadmium exposure but also provided insights for future 
drug interventions.
Abbreviation
Osteoporosis OP
National Health and Nutrition Examination Survey NHANES
Gene Set Enrichment Analysis GSEA
Mendelian randomization MR
Swedish cohort of the Osteoporotic Fractures in Men Study MrOS
bone mineral density BMD
Femoral neck bone mineral density FN BMD
Dual-energy X-ray absorptiometry DXA
Fig. 7. Summary diagram of HMOX1-mediated regulation of cadmium-induced OP via NF-κB and NRF2 signaling pathways. Cadmium exposure induces oxidative 
stress by promoting the production of ROS, which activate the NF-κB signaling pathway and trigger inflammatory responses. ROS promote the release of NRF2 from 
KEAP1, facilitating its translocation into the nucleus, where it binds to ARE and initiates the transcription of HMOX1. HMOX1 catalyzes the degradation of heme into 
CO and biliverdin, both of which collaboratively modulate oxidative stress. CO inhibits NF-κB activity by regulating TLR4 and the S-glutathionylation of p65. 
Biliverdin is further reduced to bilirubin, which suppresses NF-κB activation by downregulating p65 phosphorylation and IL-18. Cadmium exposure inhibits the 
NRF2/NQO1 pathway, impairs the antioxidant defense response, and facilitates osteoclastogenesis via the NFATc1/RANKL axis, thereby exacerbating OP. 
Figure created with BioRender (http://biorender.com).
Y. Li et al.                                                                                                                                                                                                                                        
Ecotoxicology and Environmental Safety 301 (2025) 118502 
11

# Page 12

Comparative Toxicogenomics Database CTD
Gene Expression Omnibus GEO
Gene Ontology GO
biological processes BP
cellular components CC
molecular functions MF
Kyoto Encyclopedia of Genes and Genomes KEGG
Protein-Protein Interaction PPI
Support Vector Machine - Recursive Feature Elimination SVM-RFE
odds ratios OR
confidence intervals CI
Area Under the Curve AUC
decision curve analysis DCA
Principal component analysis PCA
Molecular Signatures Database MSigDB
Genetic Factors for Osteoporosis Consortium GEFOS
UK Biobank UKB
Instrumental variables IVs
single nucleotide polymorphisms SNPs
transcription start site TSS
Inverse Variance Weighted IVW
Protein Data Bank PDB
Hartree-Fock HF
canonical ensemble NVT
isothermal-isobaric ensemble NPT
root mean square deviation RMSD
root mean square fluctuation RMSF
radius of gyration RoG
molecular mechanics generalized born surface area MM-GBSA
glutathione GSH
reactive oxygen species ROS
small musculoaponeurotic fibrosarcoma sMAF
iNOS
inducible nitric oxide synthase
Authors’ contributions
All authors made a significant contribution to the work reported and 
agreed to be accountable for all aspects of the work. LYW, ZJH and LG 
designed the experiments. LYW, RYF and JK carried out data extraction 
LYW, RYF and LXZ carried out mapping and tabulation LYW, JK and LXZ 
prepared the initial draft of the manuscript LG gave critical feedback 
during the study or during the submission of the manuscript. All authors 
provided final approval of the version to be submitted and agreed on the 
journal for publication.
Clinical trial number
Not applicable.
Data availability
Publicly available datasets and materials were analyzed in this study.
CRediT authorship contribution statement
Yifa Rong: Visualization, Software. Kai Jiang: Visualization, Soft­
ware, Data curation. Jiahao Zhang: Data curation, Conceptualization. 
Gang Li: Writing – review & editing, Writing – original draft, Formal 
analysis, Data curation, Conceptualization. Yiwei Li: Writing – original 
draft, Formal analysis, Data curation, Conceptualization. Xuezhen 
Liang: Software, Formal analysis, Data curation, Conceptualization.
Consent for publication
All participating authors give their consent for this work to be 
published.
Ethics approval and consent to participate
All data used in this work are publicly available from studies with 
relevant participant consent and ethical approval.
Funding
We would like to acknowledge the following financial support: Key 
Technology Research and Development Program of Shandong Province 
(NO.2021CXGC010501) and Leading Science and Technology Innova­
tion Team (2024sdskctd-02).
Declaration of Competing Interest
The authors declare that they have no known competing financial 
interests or personal relationships that could have appeared to influence 
the work reported in this paper.
Acknowledgements
We thank all the participants involved in this research for their 
priceless contribution.
Appendix A. Supporting information
Supplementary data associated with this article can be found in the 
online version at doi:10.1016/j.ecoenv.2025.118502.
Data availability
All data used in this work are publicly available from studies with 
relevant participant consent and ethical approval. I have shared the link 
of data.
References
Adasme, M.F., Linnemann, K.L., Bolz, S.N., Kaiser, F., Salentin, S., Haupt, V.J., 
Schroeder, M., 2021. PLIP 2021: expanding the scope of the protein–ligand 
interaction profiler to DNA and RNA. Nucleic Acids Res. 49 (W1), W530–W534. 
https://doi.org/10.1093/nar/gkab294.
Bak, S.U., Kim, S., Hwang, H.J., Yun, J.A., Kim, W.S., Won, M.H., Kim, J.Y., Ha, K.S., 
Kwon, Y.G., Kim, Y.M., 2017. Heme oxygenase-1 (HO-1)/carbon monoxide (CO) axis 
suppresses RANKL-induced osteoclastic differentiation by inhibiting redox-sensitive 
NF-kappaB activation. BMB Rep. 50 (2), 103–108. https://doi.org/10.5483/ 
bmbrep.2017.50.2.220.
Baran, D.T., Faulkner, K.G., Genant, H.K., Miller, P.D., Pacifici, R., 1997. Diagnosis and 
management of osteoporosis: guidelines for the utilization of bone densitometry. 
Calcif. Tissue Int. 61 (6), 433–440. https://doi.org/10.1007/s002239900362.
Bowden, J., Davey Smith, G., Burgess, S., 2015. Mendelian randomization with invalid 
instruments: effect estimation and bias detection through Egger regression. Int. J. 
Epidemiol. 44 (2), 512–525. https://doi.org/10.1093/ije/dyv080.
Bowden, J., Del Greco, M.F., Minelli, C., Zhao, Q., Lawlor, D.A., Sheehan, N.A., 
Thompson, J., Davey Smith, G., 2019. Improving the accuracy of two-sample 
summary-data Mendelian randomization: moving beyond the NOME assumption. 
Int. J. Epidemiol. 48 (3), 728–742. https://doi.org/10.1093/ije/dyy258.
Breiman, L., 2001. 2001/10/01). Random Forests. Mach. Learn. 45 (1), 5–32. https:// 
doi.org/10.1023/A:1010933404324.
Burgess, S., Bowden, J., Fall, T., Ingelsson, E., Thompson, S.G., 2017. Sensitivity analyses 
for robust causal inference from mendelian randomization analyses with multiple 
genetic variants. Epidemiology 28 (1), 30–42. https://doi.org/10.1097/ 
EDE.0000000000000559.
Caudill, S.P., Schleicher, R.L., Pirkle, J.L., 2008. Multi-rule quality control for the age- 
related eye disease study. Stat. Med. 27 (20), 4094–4106. https://doi.org/10.1002/ 
sim.3222.
Chang, Y., Jiang, X., Dou, J., Xie, R., Zhao, W., Cao, Y., Gao, J., Yao, F., Wu, D., Mei, H., 
Zhong, Y., Ge, Y., Xu, H., Jiang, W., Xiao, X., Jiang, Y., Hu, S., Wu, Y., Liu, Y., 2024. 
Investigating the potential risk of cadmium exposure on seizure severity and anxiety- 
like behaviors through the ferroptosis pathway in epileptic mice: An integrated 
multi-omics approach. J. Hazard Mater. 480, 135814. https://doi.org/10.1016/j. 
jhazmat.2024.135814.
Che, J., Yang, J., Zhao, B., Shang, P., 2021. HO-1: A new potential therapeutic target to 
combat osteoporosis. Eur. J. Pharm. 906, 174219. https://doi.org/10.1016/j. 
ejphar.2021.174219.
Y. Li et al.                                                                                                                                                                                                                                        
Ecotoxicology and Environmental Safety 301 (2025) 118502 
12

# Page 13

Chou, L.C., Tsai, C.C., 2023. Assessing the effectiveness of fermented banana peel 
extracts for the biosorption and removal of cadmium to mitigate inflammation and 
oxidative stress. Foods 12 (13). https://doi.org/10.3390/foods12132632.
Chudy, P., Bednarczyk, K., Chatian, E., Krzeptowski, W., Szade, A., Szade, K., ˙Zukowska, 
M., Wolnik, J., Sokołowski, G., J´ozkowicz, A., & Nowak, W.N. (2024). https://doi. 
org/10.1101/2024.11.04.620611.
Cortes, C., Vapnik, V.N., 1995. Support-vector networks. Mach. Learn. 20, 273–297.
Davis, S., Meltzer, P.S., 2007. GEOquery: a bridge between the Gene Expression Omnibus 
(GEO) and BioConductor. Bioinformatics 23 (14), 1846–1847. https://doi.org/ 
10.1093/bioinformatics/btm254.
Davis, A.P., Wiegers, T.C., Johnson, R.J., Sciaky, D., Wiegers, J., Mattingly, C.J., 2023. 
Comparative Toxicogenomics Database (CTD): update 2023. Nucleic Acids Res. 51 
(D1), D1257–D1262. https://doi.org/10.1093/nar/gkac833.
Delano, W.L., 2002. The PyMOL Molecular Graphics System.
Donertas, H.M., Fabian, D.K., Valenzuela, M.F., Partridge, L., Thornton, J.M., 2021. 
Common genetic associations between age-related diseases. Nat. Aging 1 (4), 
400–412. https://doi.org/10.1038/s43587-021-00051-5.
Eddie-Amadi, B.F., Ezejiofor, A.N., Orish, C.N., Rovira, J., Allison, T.A., Orisakwe, O.E., 
2022. Banana peel ameliorated hepato-renal damage and exerted anti-inflammatory 
and anti-apoptotic effects in metal mixture mediated hepatic nephropathy by 
activation of Nrf2/ Hmox-1 and inhibition of Nfkb pathway. Food Chem. Toxicol. 
170, 113471. https://doi.org/10.1016/j.fct.2022.113471.
Emdin, C.A., Khera, A.V., Kathiresan, S., 2017. Mendelian randomization. JAMA 318 
(19), 1925–1926. https://doi.org/10.1001/jama.2017.17219.
Freitas, M., Fernandes, E., 2011. Zinc, cadmium and nickel increase the activation of NF- 
kappaB and the release of cytokines from THP-1 monocytic cells. Metallomics 3 (11), 
1238–1243. https://doi.org/10.1039/c1mt00050k.
Genchi, G., Sinicropi, M.S., Lauria, G., Carocci, A., Catalano, A., 2020. The effects of 
cadmium toxicity. Int. J. Environ. Res. Public Health 17 (11). https://doi.org/ 
10.3390/ijerph17113782.
Goyal, T., Mitra, P., Singh, P., Sharma, P., Sharma, S., 2021. Evaluation of oxidative 
stress and pro-inflammatory cytokines in occupationally cadmium exposed workers. 
Work 69 (1), 67–73. https://doi.org/10.3233/WOR-203302.
Greco, M.F., Minelli, C., Sheehan, N.A., Thompson, J.R., 2015. Detecting pleiotropy in 
Mendelian randomisation studies with summary data and a continuous outcome. 
Stat. Med. 34 (21), 2926–2940. https://doi.org/10.1002/sim.6522.
Guyon, I., Weston, J., Barnhill, S., Vapnik, V., 2002. 2002/01/01). Gene selection for 
cancer classification using support vector machines. Mach. Learn. 46 (1), 389–422. 
https://doi.org/10.1023/A:1012487302797.
He, T., Shen, H., Zhu, J., Zhu, Y., He, Y., Li, Z., Lu, H., 2019. Geniposide attenuates 
cadmium‑induced oxidative stress injury via Nrf2 signaling in osteoblasts. Mol. Med. 
Rep. 20 (2), 1499–1508. https://doi.org/10.3892/mmr.2019.10396.
He, N., Zhang, J., Liu, M., Yin, L., 2024. Elucidating the mechanism of plasticizers 
inducing breast cancer through network toxicology and molecular docking analysis. 
Ecotoxicol. Environ. Saf. 284, 116866. https://doi.org/10.1016/j. 
ecoenv.2024.116866.
Huang, Y., Li, J., Li, W., Ai, N., Jin, H., 2022. Biliverdin/bilirubin redox pair protects lens 
epithelial cells against oxidative stress in age-related cataract by regulating NF- 
kappaB/iNOS and Nrf2/HO-1 pathways. Oxid. Med. Cell Longev. 2022, 7299182. 
https://doi.org/10.1155/2022/7299182.
Jeon, W.K., Hong, H.Y., Kim, B.C., 2011. Genipin up-regulates heme oxygenase-1 via PI3- 
kinase-JNK1/2-Nrf2 signaling pathway to enhance the anti-inflammatory capacity in 
RAW264.7 macrophages. Arch. Biochem. Biophys. 512 (2), 119–125. https://doi. 
org/10.1016/j.abb.2011.05.016.
Jia, L., Ma, T., Lv, L., Yu, Y., Zhao, M., Chen, H., Gao, L., 2023. Endoplasmic reticulum 
stress mediated by ROS participates in cadmium exposure-induced MC3T3-E1 cell 
apoptosis. Ecotoxicol. Environ. Saf. 251, 114517. https://doi.org/10.1016/j. 
ecoenv.2023.114517.
Jin, S., Guerrero-Juarez, C.F., Zhang, L., Chang, I., Ramos, R., Kuan, C.H., Myung, P., 
Plikus, M.V., Nie, Q., 2021. Inference and analysis of cell-cell communication using 
CellChat. Nat. Commun. 12 (1), 1088. https://doi.org/10.1038/s41467-021-21246- 
9.
Jin, C., Lin, B.H., Zheng, G., Tan, K., Liu, G.Y., Yao, Z., Xie, J., Chen, W.K., Chen, L., 
Xu, T.H., Huang, C.B., Wu, Z.Y., Yang, L., 2022. CORM-3 attenuates oxidative stress- 
induced bone loss via the Nrf2/HO-1 pathway. Oxid. Med. Cell Longev. 2022, 
5098358. https://doi.org/10.1155/2022/5098358.
Jin, Z., Zhao, H., Luo, Y., Li, J., Pi, J., He, W., Yan, J., Yang, P., 2021. Geniposide 
achieved an anti-inflammatory effect through the NF-κB/HIF-1α signaling pathway 
mediated by VEGFA and HMOX1 genes. SSRN Electron. J.
Jolliffe, I.T., 2002. Principal Component Analysis. Springer. 〈https://books.google.com. 
ar/books?id=TtVF-ao4fI8C〉.
Kanis, J.A., McCloskey, E.V., Johansson, H., Oden, A., Melton, L.J., 3rd, Khaltaev, N., 
2008. A reference standard for the description of osteoporosis. Bone 42 (3), 
467–475. https://doi.org/10.1016/j.bone.2007.11.001.
Kim, E.S., Shin, S., Lee, Y.J., Ha, I.H., 2021. Association between blood cadmium levels 
and the risk of osteopenia and osteoporosis in Korean post-menopausal women. 
Arch. Osteoporos. 16 (1), 22. https://doi.org/10.1007/s11657-021-00887-9.
Kuhn, M., 2008. Building predictive models in R using the caret package. J. Stat. Softw. 
28, 1–26.
Kunioka, C.T., Manso, M.C., Carvalho, M., 2022. Association between environmental 
cadmium exposure and osteoporosis risk in postmenopausal women: a systematic 
review and meta-analysis. Int. J. Environ. Res. Public Health 20 (1). https://doi.org/ 
10.3390/ijerph20010485.
Lei, S.F., Wu, S., Li, L.M., Deng, F.Y., Xiao, S.M., Jiang, C., Chen, Y., Jiang, H., Yang, F., 
Tan, L.J., Sun, X., Zhu, X.Z., Liu, M.Y., Liu, Y.Z., Chen, X.D., Deng, H.W., 2009. An in 
vivo genome wide gene expression study of circulating monocytes suggested GBP1, 
STAT1 and CXCL10 as novel risk genes for the differentiation of peak bone mass. 
Bone 44 (5), 1010–1014. https://doi.org/10.1016/j.bone.2008.05.016.
Li, Y., Huang, B., Ye, T., Wang, Y., Xia, D., Qian, J., 2020. Physiological concentrations of 
bilirubin control inflammatory response by inhibiting NF-κB and inflammasome 
activation. Int. Immunopharmacol. 84. https://doi.org/10.1016/j. 
intimp.2020.106520.
Liaw, A., Wiener, M.C., 2007. Classification and Regression by randomForest.
Liberzon, A., Birger, C., Thorvaldsdottir, H., Ghandi, M., Mesirov, J.P., Tamayo, P., 2015. 
The Molecular Signatures Database (MSigDB) hallmark gene set collection. Cell Syst. 
1 (6), 417–425. https://doi.org/10.1016/j.cels.2015.12.004.
Liu, Z., Wu, J., Dong, Z., Wang, Y., Wang, G., Chen, C., Wang, H., Yang, Y., Sun, Y., 
Yang, M., Fu, J., Li, J., Zhang, Q., Xu, Y., Pi, J., 2024. Prolonged cadmium exposure 
and osteoclastogenesis: a mechanistic mouse and in vitro study. Environ. Health 
Perspect. 132 (6), 67009. https://doi.org/10.1289/EHP13849.
Luo, H., Gu, R., Ouyang, H., Wang, L., Shi, S., Ji, Y., Bao, B., Liao, G., Xu, B., 2021. 
Cadmium exposure induces osteoporosis through cellular senescence, associated 
with activation of NF-kappaB pathway and mitochondrial dysfunction. Environ. 
Pollut. 290, 118043. https://doi.org/10.1016/j.envpol.2021.118043.
Lv, Z., Zhao, B., Hu, L., Pan, J., Li, X., Li, M., Wu, C., & Mao, W. (2023). https://doi.or 
g/10.21203/rs.3.rs-3268699/v1.
Ma, W., Li, C., 2024. Enhancing postmenopausal osteoporosis: a study of KLF2 
transcription factor secretion and PI3K-Akt signaling pathway activation by PIK3CA 
in bone marrow mesenchymal stem cells. Arch. Med. Sci. 20 (3), 918–937. https:// 
doi.org/10.5114/aoms/171785.
Ma, Y., Su, Q., Yue, C., Zou, H., Zhu, J., Zhao, H., Song, R., Liu, Z., 2022. The effect of 
oxidative stress-induced autophagy by cadmium exposure in kidney, liver, and bone 
damage, and neurotoxicity. Int. J. Mol. Sci. 23 (21). https://doi.org/10.3390/ 
ijms232113491.
McInnes, L., Healy, J., Saul, N., Großberger, L., 2018. UMAP: uniform manifold 
approximation and projection. J. Open Source Softw. 3, 861.
Naito, Y., Takagi, T., Higashimura, Y., 2014. Heme oxygenase-1 and anti-inflammatory 
M2 macrophages. Arch. Biochem. Biophys. 564, 83–88. https://doi.org/10.1016/j. 
abb.2014.09.005.
Ougier, E., Fiore, K., Rousselle, C., Assuncao, R., Martins, C., Buekers, J., 2021. Burden of 
osteoporosis and costs associated with human biomonitored cadmium exposure in 
three European countries: France, Spain and Belgium. Int. J. Hyg. Environ. Health 
234, 113747. https://doi.org/10.1016/j.ijheh.2021.113747.
Ramadan, M.A., Saif Eldin, A.S., 2022. Effect of occupational cadmium exposure on the 
thyroid gland and associated inflammatory markers among workers of the 
electroplating industry. Toxicol. Ind. Health 38 (4), 210–220. https://doi.org/ 
10.1177/07482337221085046.
Ritchie, M.E., Phipson, B., Wu, D., Hu, Y., Law, C.W., Shi, W., Smyth, G.K., 2015. limma 
powers differential expression analyses for RNA-sequencing and microarray studies. 
Nucleic Acids Res. 43 (7), e47. https://doi.org/10.1093/nar/gkv007.
Salomon-Ferrer, R., G¨otz, A.W., Poole, D., Le Grand, S., Walker, R.C., 2013. Routine 
microsecond molecular dynamics simulations with AMBER on GPUs. 2. Explicit 
solvent particle mesh Ewald. J. Chem. Theory Comput. 9 (9), 3878–3888. https:// 
doi.org/10.1021/ct400314y.
Satarug, S., Garrett, S.H., Sens, M.A., Sens, D.A., 2010. Cadmium, environmental 
exposure, and health outcomes. Environ. Health Perspect. 118 (2), 182–190. https:// 
doi.org/10.1289/ehp.0901234.
Schwarzer, G., Carpenter, J.R., & Rücker, G. (2015). Meta-Analysis with R. Springer 
International Publishing. 〈https://books.google.com.ar/books?id=xhvFsgEACAAJ〉.
Shannon, P., Markiel, A., Ozier, O., Baliga, N.S., Wang, J.T., Ramage, D., Amin, N., 
Schwikowski, B., Ideker, T., 2003. Cytoscape: a software environment for integrated 
models of biomolecular interaction networks. Genome Res. 13 (11), 2498–2504. 
https://doi.org/10.1101/gr.1239303.
Slob, E.A.W., Burgess, S., 2020. A comparison of robust Mendelian randomization 
methods using summary data. Genet Epidemiol. 44 (4), 313–329. https://doi.org/ 
10.1002/gepi.22295.
Su, J., Song, Y., Zhu, Z., Huang, X., Fan, J., Qiao, J., Mao, F., 2024. Cell-cell 
communication: new insights and clinical implications. Signal Transduct. Target 
Ther. 9 (1), 196. https://doi.org/10.1038/s41392-024-01888-z.
Subramanian, A., Tamayo, P., Mootha, V.K., Mukherjee, S., Ebert, B.L., Gillette, M.A., 
Paulovich, A., Pomeroy, S.L., Golub, T.R., Lander, E.S., Mesirov, J.P., 2005. Gene set 
enrichment analysis: a knowledge-based approach for interpreting genome-wide 
expression profiles. Proc. Natl. Acad. Sci. USA 102 (43), 15545–15550. https://doi. 
org/10.1073/pnas.0506580102.
Szklarczyk, D., Kirsch, R., Koutrouli, M., Nastou, K., Mehryary, F., Hachilif, R., Gable, A. 
L., Fang, T., Doncheva, N.T., Pyysalo, S., Bork, P., Jensen, L.J., von Mering, C., 2023. 
The STRING database in 2023: protein-protein association networks and functional 
enrichment analyses for any sequenced genome of interest. Nucleic Acids Res. 51 
(D1), D638–D646. https://doi.org/10.1093/nar/gkac1000.
Tan, S., Su, Y., Huang, L., Deng, S., Yan, G., Yang, X., Chen, R., Xian, Y., Liang, J., Liu, Q., 
Cheng, J., 2022. Corilagin attenuates osteoclastic osteolysis by enhancing HO-1 and 
inhibiting ROS. J. Biochem. Mol. Toxicol. 36 (7), e23049. https://doi.org/10.1002/ 
jbt.23049.
Tanaka, G., Aminuddin, F., Akhabir, L., He, J.Q., Shumansky, K., Connett, J.E., 
Anthonisen, N.R., Abboud, R.T., Pare, P.D., Sandford, A.J., 2011. Effect of heme 
oxygenase-1 polymorphisms on lung function and gene expression. BMC Med. Genet 
12, 117. https://doi.org/10.1186/1471-2350-12-117.
Tian, J., Li, Z., Wang, L., Qiu, D., Zhang, X., Xin, X., Cai, Z., Lei, B., 2021. Metabolic 
signatures for safety assessment of low-level cadmium exposure on human 
osteoblast-like cells. Ecotoxicol. Environ. Saf. 207, 111257. https://doi.org/ 
10.1016/j.ecoenv.2020.111257.
Y. Li et al.                                                                                                                                                                                                                                        
Ecotoxicology and Environmental Safety 301 (2025) 118502 
13

# Page 14

Townsend, B.E., Chen, Y.J., Jeffery, E.H., Johnson, R.W., 2014. Dietary broccoli mildly 
improves neuroinflammation in aged mice but does not reduce lipopolysaccharide- 
induced sickness behavior. Nutr. Res. 34 (11), 990–999. https://doi.org/10.1016/j. 
nutres.2014.10.001.
Trott, O., Olson, A.J., 2010. AutoDock Vina: improving the speed and accuracy of 
docking with a new scoring function, efficient optimization, and multithreading. 
J. Comput. Chem. 31 (2), 455–461. https://doi.org/10.1002/jcc.21334.
Verzelloni, P., Urbano, T., Wise, L.A., Vinceti, M., Filippini, T., 2024. Cadmium exposure 
and cardiovascular disease risk: A systematic review and dose-response meta- 
analysis. Environ. Pollut. 345, 123462. https://doi.org/10.1016/j. 
envpol.2024.123462.
Vickers, A.J., Elkin, E.B., 2006. Decision curve analysis: a novel method for evaluating 
prediction models. Med. Decis. Mak. 26 (6), 565–574. https://doi.org/10.1177/ 
0272989X06295361.
Vitali, S.H., Fernandez-Gonzalez, A., Nadkarni, J., Kwong, A., Rose, C., Mitsialis, S.A., 
Kourembanas, S., 2020. Heme oxygenase-1 dampens the macrophage sterile 
inflammasome response and regulates its components in the hypoxic lung. Am. J. 
Physiol. Lung Cell Mol. Physiol. 318 (1), L125–L134. https://doi.org/10.1152/ 
ajplung.00074.2019.
Vosa, U., Claringbould, A., Westra, H.J., Bonder, M.J., Deelen, P., Zeng, B., Kirsten, H., 
Saha, A., Kreuzhuber, R., Yazar, S., Brugge, H., Oelen, R., de Vries, D.H., van der 
Wijst, M.G.P., Kasela, S., Pervjakova, N., Alves, I., Fave, M.J., Agbessi, M., 
Christiansen, M.W., Jansen, R., Seppala, I., Tong, L., Teumer, A., Schramm, K., 
Hemani, G., Verlouw, J., Yaghootkar, H., Sonmez Flitman, R., Brown, A., 
Kukushkina, V., Kalnapenkis, A., Rueger, S., Porcu, E., Kronberg, J., Kettunen, J., 
Lee, B., Zhang, F., Qi, T., Hernandez, J.A., Arindrarto, W., Beutner, F., 
Consortium, B., i, Dmitrieva, Q.T.L.C., Elansary, J., Fairfax, M., Georges, B.P., 
Heijmans, M., Hewitt, B.T., Kahonen, A.W., Kim, M., Knight, Y., Kovacs, J.C., 
Krohn, P., Li, K., Loeffler, S., Marigorta, M., Mei, U.M., Momozawa, H., Muller- 
Nurasyid, Y., Nauck, M., Nivard, M., Penninx, M.G., Pritchard, B., Raitakari, J.K., 
Rotzschke, O.T., Slagboom, O., Stehouwer, E.P., Stumvoll, C.D.A., Sullivan, P., T, M., 
Hoen, P.A.C., Thiery, J., Tonjes, A., van Dongen, J., van Iterson, M., Veldink, J.H., 
Volker, U., Warmerdam, R., Wijmenga, C., Swertz, M., Andiappan, A., 
Montgomery, G.W., Ripatti, S., Perola, M., Kutalik, Z., Dermitzakis, E., Bergmann, S., 
Frayling, T., van Meurs, J., Prokisch, H., Ahsan, H., Pierce, B.L., Lehtimaki, T., 
Boomsma, D.I., Psaty, B.M., Gharib, S.A., Awadalla, P., Milani, L., Ouwehand, W.H., 
Downes, K., Stegle, O., Battle, A., Visscher, P.M., Yang, J., Scholz, M., Powell, J., 
Gibson, G., Esko, T., Franke, L., 2021. Large-scale cis- and trans-eQTL analyses 
identify thousands of genetic loci and polygenic scores that regulate blood gene 
expression. Nat. Genet 53 (9), 1300–1310. https://doi.org/10.1038/s41588-021- 
00913-z.
Wallin, M., Andersson, E.M., Engstrom, G., 2024. Blood cadmium is associated with 
increased fracture risk in never-smokers - results from a case-control study using data 
from the Malmo Diet and Cancer cohort. Bone 179, 116989. https://doi.org/ 
10.1016/j.bone.2023.116989.
Wallin, M., Barregard, L., Sallsten, G., Lundh, T., Sundh, D., Lorentzon, M., Ohlsson, C., 
Mellstrom, D., 2021. Low-level cadmium exposure is associated with decreased 
cortical thickness, cortical area and trabecular bone volume fraction in elderly men: 
the MrOS Sweden study. Bone 143, 115768. https://doi.org/10.1016/j. 
bone.2020.115768.
Wang, E., Li, S., Li, Y., Zhou, T., 2025. HMOX1 as a potential drug target for upper and 
lower airway diseases: insights from multi-omics analysis. Respir. Res. 26 (1), 41. 
https://doi.org/10.1186/s12931-025-03124-w.
Wang, Z., Li, X., Yang, J., Gong, Y., Zhang, H., Qiu, X., Liu, Y., Zhou, C., Chen, Y., 
Greenbaum, J., Cheng, L., Hu, Y., Xie, J., Yang, X., Li, Y., Schiller, M.R., Chen, Y., 
Tan, L., Tang, S.Y., Shen, H., Xiao, H.M., Deng, H.W., 2021. Single-cell RNA 
sequencing deconvolutes the in vivo heterogeneity of human bone marrow-derived 
mesenchymal stem cells. Int. J. Biol. Sci. 17 (15), 4192–4206. https://doi.org/ 
10.7150/ijbs.61950.
Wang, H., Peng, C., Hu, G., Chen, W., Hu, Y., Pi, H., 2024. Integrated single-cell RNA-seq 
and Bulk RNA-seq identify diagnostic biomarkers for Postmenopausal Osteoporosis. 
Curr. Med. Chem. https://doi.org/10.2174/0109298673343344240930054414.
Watabe, Y., Giam Chuang, V.T., Sakai, H., Ito, C., Enoki, Y., Kohno, M., Otagiri, M., 
Matsumoto, K., Taguchi, K., 2025. Carbon monoxide alleviates endotoxin-induced 
acute lung injury via NADPH oxidase inhibition in macrophages and neutrophils. 
Biochem. Pharm. 233, 116782. https://doi.org/10.1016/j.bcp.2025.116782.
Wright, N.C., Looker, A.C., Saag, K.G., Curtis, J.R., Delzell, E.S., Randall, S., Dawson- 
Hughes, B., 2014. The recent prevalence of osteoporosis and low bone mass in the 
United States based on bone mineral density at the femoral neck or lumbar spine. 
J. Bone Min. Res. 29 (11), 2520–2526. https://doi.org/10.1002/jbmr.2269.
Xiaofeng, Y., Qinren, C., Jingping, H., Xiao, C., Miaomiao, W., Xiangru, F., Xianxing, X., 
Meixia, H., Jing, L., Jingyuan, W., Xinxin, C., Hongyu, L., Yanhong, D., Lanxiang, J., 
Xuming, D., 2012. Geniposide, an iridoid glucoside derived from Gardenia 
jasminoides, protects against lipopolysaccharide-induced acute lung injury in mice. 
Planta Med. 78 (6), 557–564. https://doi.org/10.1055/s-0031-1298212.
Ximenez, J.P.B., Zamarioli, A., Kacena, M.A., Barbosa, R.M., Barbosa, F., Jr, 2021. 
Association of Urinary and Blood Concentrations of Heavy Metals with Measures of 
Bone Mineral Density Loss: a Data Mining Approach with the Results from the 
National Health and Nutrition Examination Survey. Biol. Trace Elem. Res. 199 (1), 
92–101. https://doi.org/10.1007/s12011-020-02150-7.
Xu, S., Hu, E., Cai, Y., Xie, Z., Luo, X., Zhan, L., Tang, W., Wang, Q., Liu, B., Wang, R., 
Xie, W., Wu, T., Xie, L., Yu, G., 2024. Using clusterProfiler to characterize 
multiomics data. Nat. Protoc. 19 (11), 3292–3320. https://doi.org/10.1038/s41596- 
024-01020-z.
Ye, W., Liu, Z., Liu, F., Luo, C., 2021. Heme oxygenase-1 predicts risk stratification and 
immunotherapy efficacy in lower grade gliomas. Front. Cell Dev. Biol. 9, 760800. 
https://doi.org/10.3389/fcell.2021.760800.
Yeh, P.Y., Li, C.Y., Hsieh, C.W., Yang, Y.C., Yang, P.M., Wung, B.S., 2014. CO-releasing 
molecules and increased heme oxygenase-1 induce protein S-glutathionylation to 
modulate NF-kappaB activity in endothelial cells. Free Radic. Biol. Med. 70, 1–13. 
https://doi.org/10.1016/j.freeradbiomed.2014.01.042.
Yin, Y., Weng, Y., Ma, Z., Li, L., 2025. Tectochrysin alleviates periodontitis by 
modulating M2/M1 macrophage ratio and oxidative stress via nuclear factor Kappa 
B/heme oxygenase-1/nuclear factor erythroid 2-related factor 2 pathway. Immunol. 
Invest. 54 (1), 97–111. https://doi.org/10.1080/08820139.2024.2418938.
Yoo, M., Shin, J., Kim, J., Ryall, K.A., Lee, K., Lee, S., Jeon, M., Kang, J., Tan, A.C., 2015. 
DSigDB: drug signatures database for gene set analysis. Bioinformatics 31 (18), 
3069–3071. https://doi.org/10.1093/bioinformatics/btv313.
Zabalgoitia, M., Colston, J.T., Reddy, S.V., Holt, J.W., Regan, R.F., Stec, D.E., Rimoldi, J. 
M., Valente, A.J., Chandrasekar, B., 2008. Carbon monoxide donors or heme 
oxygenase-1 (HO-1) overexpression blocks interleukin-18-mediated NF-kappaB- 
PTEN-dependent human cardiac endothelial cell death. Free Radic. Biol. Med. 44 
(3), 284–298. https://doi.org/10.1016/j.freeradbiomed.2007.08.012.
Zheng, H.F., Forgetta, V., Hsu, Y.H., Estrada, K., Rosello-Diez, A., Leo, P.J., Dahia, C.L., 
Park-Min, K.H., Tobias, J.H., Kooperberg, C., Kleinman, A., Styrkarsdottir, U., Liu, C. 
T., Uggla, C., Evans, D.S., Nielson, C.M., Walter, K., Pettersson-Kymmer, U., 
McCarthy, S., Eriksson, J., Kwan, T., Jhamai, M., Trajanoska, K., Memari, Y., Min, J., 
Huang, J., Danecek, P., Wilmot, B., Li, R., Chou, W.C., Mokry, L.E., Moayyeri, A., 
Claussnitzer, M., Cheng, C.H., Cheung, W., Medina-Gomez, C., Ge, B., Chen, S.H., 
Choi, K., Oei, L., Fraser, J., Kraaij, R., Hibbs, M.A., Gregson, C.L., Paquette, D., 
Hofman, A., Wibom, C., Tranah, G.J., Marshall, M., Gardiner, B.B., Cremin, K., 
Auer, P., Hsu, L., Ring, S., Tung, J.Y., Thorleifsson, G., Enneman, A.W., van 
Schoor, N.M., de Groot, L.C., van der Velde, N., Melin, B., Kemp, J.P., 
Christiansen, C., Sayers, A., Zhou, Y., Calderari, S., van Rooij, J., Carlson, C., 
Peters, U., Berlivet, S., Dostie, J., Uitterlinden, A.G., Williams, S.R., Farber, C., 
Grinberg, D., LaCroix, A.Z., Haessler, J., Chasman, D.I., Giulianini, F., Rose, L.M., 
Ridker, P.M., Eisman, J.A., Nguyen, T.V., Center, J.R., Nogues, X., Garcia-Giralt, N., 
Launer, L.L., Gudnason, V., Mellstrom, D., Vandenput, L., Amin, N., van Duijn, C.M., 
Karlsson, M.K., Ljunggren, O., Svensson, O., Hallmans, G., Rousseau, F., Giroux, S., 
Bussiere, J., Arp, P.P., Koromani, F., Prince, R.L., Lewis, J.R., Langdahl, B.L., 
Hermann, A.P., Jensen, J.E., Kaptoge, S., Khaw, K.T., Reeve, J., Formosa, M.M., 
Xuereb-Anastasi, A., Akesson, K., McGuigan, F.E., Garg, G., Olmos, J.M., 
Zarrabeitia, M.T., Riancho, J.A., Ralston, S.H., Alonso, N., Jiang, X., Goltzman, D., 
Pastinen, T., Grundberg, E., Gauguier, D., Orwoll, E.S., Karasik, D., Davey-Smith, G., 
Consortium, A., Smith, A.V., Siggeirsdottir, K., Harris, T.B., Zillikens, M.C., van 
Meurs, J.B., Thorsteinsdottir, U., Maurano, M.T., Timpson, N.J., Soranzo, N., 
Durbin, R., Wilson, S.G., Ntzani, E.E., Brown, M.A., Stefansson, K., Hinds, D.A., 
Spector, T., Cupples, L.A., Ohlsson, C., Greenwood, C.M., Consortium, U.K., 
Jackson, R.D., Rowe, D.W., Loomis, C.A., Evans, D.M., Ackert-Bicknell, C.L., 
Joyner, A.L., Duncan, E.L., Kiel, D.P., Rivadeneira, F., Richards, J.B., 2015. Whole- 
genome sequencing identifies EN1 as a determinant of bone density and fracture. 
Nature 526 (7571), 112–117. https://doi.org/10.1038/nature14878.
Zheng, G.X., Terry, J.M., Belgrader, P., Ryvkin, P., Bent, Z.W., Wilson, R., Ziraldo, S.B., 
Wheeler, T.D., McDermott, G.P., Zhu, J., Gregory, M.T., Shuga, J., Montesclaros, L., 
Underwood, J.G., Masquelier, D.A., Nishimura, S.Y., Schnall-Levin, M., Wyatt, P.W., 
Hindson, C.M., Bharadwaj, R., Wong, A., Ness, K.D., Beppu, L.W., Deeg, H.J., 
McFarland, C., Loeb, K.R., Valente, W.J., Ericson, N.G., Stevens, E.A., Radich, J.P., 
Mikkelsen, T.S., Hindson, B.J., Bielas, J.H., 2017. Massively parallel digital 
transcriptional profiling of single cells. Nat. Commun. 8, 14049. https://doi.org/ 
10.1038/ncomms14049.
Zhou, Y., Gao, Y., Xu, C., Shen, H., Tian, Q., Deng, H.W., 2018. A novel approach for 
correction of crosstalk effects in pathway analysis and its application in osteoporosis 
research. Sci. Rep. 8 (1), 668. https://doi.org/10.1038/s41598-018-19196-2.
Zhou, D., Ran, Y., Yu, R., Liu, G., Ran, D., Liu, Z., 2023. SIRT1 regulates osteoblast 
senescence through SOD2 acetylation and mitochondrial dysfunction in the 
progression of Osteoporosis caused by Cadmium exposure. Chem. Biol. Inter. 382, 
110632. https://doi.org/10.1016/j.cbi.2023.110632.
Zhu, H., Tang, X., Gu, C., Chen, R., Liu, Y., Chu, H., Zhang, Z., 2024. Assessment of 
human exposure to cadmium and its nephrotoxicity in the Chinese population. Sci. 
Total Environ. 918, 170488. https://doi.org/10.1016/j.scitotenv.2024.170488.
Y. Li et al.                                                                                                                                                                                                                                        
Ecotoxicology and Environmental Safety 301 (2025) 118502 
14
