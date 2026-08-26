# Page 1

Association of triglyceride glucose index with
stroke: from two large cohort studies and Mendelian
randomization analysis
Yong’An Jiang, MDa, Jing Shen, MSb,c, Peng Chen, MDa, JiaHong Cai, MDa, YangYang Zhao, MDa,
JiaWei Liang, MSa, JianHui Cai, MDd,e, ShiQi Cheng, MDa, Yan Zhang, MDa,e,*
Introduction: The triglyceride glucose index (TyG) is associated with cardiovascular diseases; however, its association with stroke
remains unclear. This study aimed to elucidate this relationship by examining two extensive cohort studies using two-sample
Mendelian randomization (MR).
Methods: Using data from the 1999–2018 National Health and Nutrition Examination Survey (NHANES) and the Medical
Information Mart for Intensive Care (MIMIC)-IV, the correlation between TyG (continuous and quartile) and stroke was examined using
multivariate Cox regression models and sensitivity analyses. Two-sample MR was employed to establish causality between TyG and
stroke using the inverse variance weighting method. Genome-wide association study catalog queries were performed for single
nucleotide polymorphism-mapped genes, and the STRING platform used to assess protein interactions. Functional annotation and
enrichment analyses were also conducted.
Results: From the NHANES and MIMIC-IV cohorts, we included 740 and 589 participants with stroke, respectively. After adjusting for
covariates, TyG was linearly associated with the risk of stroke death (NHANES: hazard ratio [HR] 0.64, 95% CI: 0.41–0.99, P=0.047; Q3
vs. Q1, HR 0.62, 95% CI: 0.40–0.96, P=0.033; MIMIC-IV: HR 0.46, 95% CI: 0.27–0.80, P=0.006; Q3 vs. Q1, HR 0.32, 95% CI:
0.12–0.86; Q4 vs. Q1, HR 0.30, 95% CI: 0.10–0.89, P=0.030, P for trend=0.017). Two-sample MR analysis showed genetic prediction
supported a causal association between a higher TyG and a reduced risk of stroke (odds ratio 0.711, 95% CI: 0.641–0.788, P=7.64e-11).
Conclusions: TyG was causally associated with a reduced risk of stroke. TyG is a critical factor for stroke risk management.
Keywords: Mendelian randomization, MIMIC-IV, NHANES, stroke, triglyceride-glucose index
Introduction
Stroke is a globally prevalent acute neurological disorder, posing
a grave threat to life and leading to irreversible neurological
impairment[1,2]. Globally,
more
than 13.7 million
people
experience a stroke annually, accounting for more than half of all
fatalities[3]. Given the substantial impact of stroke on the life and
health of a signiﬁcant proportion of the population, there is an
urgent
need
to
establish
timely
and
effective
preventive
interventions.
The triglyceride-glucose (TyG) index serves as a reliable bio-
marker of insulin resistance, reﬂecting insulin sensitivity. The
TyG index is a practical tool for utilizing fasting blood glucose
and routine biochemical test-derived glucose levels, thereby
bypassing the conventional high insulin-normoglycemic clamp
and
homeostatic
model
assessment
for
insulin
resistance
(HOMA-IR) tests[4]. Its simplicity, cost-effectiveness, and stabi-
lity confer distinct advantages[5]. However, limited research
exists on the association between TyG and stroke risk and further
investigations are warranted to establish a causal relationship.
aDepartment of Neurosurgery, The Second Afﬁliated Hospital, Jiangxi Medical College, Nanchang University, bInstitute of Geriatrics, Jiangxi Provincial People’s Hospital and
The First Afﬁliated Hospital of Nanchang Medical College, cSchool of Public Health, Nanchang University, dDepartment of Neurosurgery, Nanchang County People’s Hospital,
Nanchang and eNanchang Cranio-Cerebral Trauma Laboratory Nanchang, Jiangxi, People’s Republic of China
Y.A.J. and J.S. have contributed equally to this work.
Sponsorships or competing interests that may be relevant to content are disclosed at the end of this article.
*Corresponding author. Address: Department of Neurosurgery, The Second Afﬁliated Hospital, Jiangxi Medical College, Nanchang University, Nanchang 330006, Jiangxi, People’s
Republic of China. Tel.: +86 137 674 515 97. E-mail: ndefy12388@ncu.edu.cn (Y. Zhang).
Supplemental Digital Content is available for this article. Direct URL citations are provided in the HTML and PDF versions of this article on the journal's website,
www.lww.com/international-journal-of-surgery.
Published online 19 June 2024
Received 21 February 2024; Accepted 30 May 2024
Copyright © 2024 The Author(s). Published by Wolters Kluwer Health, Inc. This is an open access article distributed under the terms of the Creative Commons Attribution-Non
Commercial-No Derivatives License 4.0 (CCBY-NC-ND), where it is permissible to download and share the work provided it is properly cited. The work cannot be changed in
any way or used commercially without permission from the journal.
International Journal of Surgery (2024) 110:5409–5416
http://dx.doi.org/10.1097/JS9.0000000000001795
’Experimental Research
5409

# Page 2

Mendelian randomization (MR) analysis explores statistical
methods of causality using genetic variation [single nucleotide
polymorphisms (SNPs)] as an instrumental variable to identify
causal associations by taking advantage of the fact that genetic
variation is randomly assigned and is not subject to confounding
factors[6]. Thus, it appears feasible to use MR to assess the causal
association between TyG and stroke.
This study investigated the association between TyG and
stroke in two large cohort. Our ﬁndings validated through
meticulous adjustments for variables and sensitivity analyses,
conﬁrm the stability of the observed association. Additionally,
employing a two-sample MR enhances the causal understanding
of this relationship. In summary, our study highlights the resi-
lience of both cohorts and genetic factors, shedding light on the
possible correlation between TyG and stroke.
Methods
Study design overview
This study comprised two main phases. In the initial phase, we
conducted a comprehensive analysis of the correlation between
the TyG index and stroke, accounting for various potential
confounding factors. This analysis utilized data from both the
National Health and Nutrition Examination Survey (NHANES)
and Medical Information Mart for Intensive Care (MIMIC)-IV.
Our ﬁndings were robustly validated through sensitivity analyses.
Detailed data for extracting the two queues are shown in the
ﬂowcharts (Fig. 1).
In the subsequent phase, we extracted summary statistics
from a genome-wide association study (GWAS) of TyG and
stroke for two-sample MR analyses. Additionally, we per-
formed molecular function and pathway analyses using genes
identiﬁed through SNPs.
Two extensive observational cohort studies
NHANES Database Cohort All data for this study were sourced
from the NHANES website (https://wwwn.cdc.gov/nchs/nhanes/
Default.aspx), a comprehensive health screening and nutritional
status survey encompassing adults and children in the United
States. The dataset spans demographic, dietary, screening,
laboratory, and questionnaire sections, covering 1999–2018. All
study protocols were approved by the Ethics Review Board of the
National Center for Health Statistics, and written informed
consent was obtained from all participants before data collection
commenced.
MIMIC-IV Database one of the authors (J.Y.A.) underwent
formal training (record ID: 58,572,169). This study received
ethical
exemptions
from
the
Massachusetts
Institute
of
Technology and the Beth Israel Deaconess Medical Center, and
no additional ethical approval was deemed necessary.
Data collection and deﬁnitions
NHANES Database Cohort We conducted a comprehensive
analysis using the NHANES database, Covariates included age,
sex, race, BMI, LDL, HDL, and total cholesterol (TC), systolic
blood pressure (SBP), diastolic blood pressure (DBP), education
level, poverty income ratio (PIR), smoking status, drinking status,
physical activity, and diabetes. BMI categories followed WHO
guidelines: normal or underweight (< 24·9 kg/m2), overweight
(25·0–29·9 kg/m2), and obese ( ≥30·0 kg/m2). Education level
was classiﬁed as high school degree or less, high school gradua-
tion, and college or higher. PIR was grouped into
≤1·3,
1·31–3·50, and > 3·50. Smoking status was categorized as never,
former, and current. Drinking status was recorded as a yes or
no. Physical activity was assessed using the Global Physical
Activity Questionnaire, distinguishing between inactive [ < 600
metabolic equivalent (MET) minutes/week] and active ( ≥600
MET minutes/week). Diabetes was diagnosed based on Centers
Figure 1. Flowchart of this study. A, NHANES cohort (1999–2018); B, MIMIC-
IV cohort.
HIGHLIGHTS
• In observational studies, the triglyceride glucose index has
been associated with a reduced risk of death from stroke.
• The triglyceride glucose index was linearly associated with
the risk of stroke death.
• Mendelian randomization analyses support a causal asso-
ciation between triglyceride glucose index and risk of
stroke.
• Functional analyses also support that the stroke mechan-
ism is mediated by lipid metabolism.
Jiang et al. International Journal of Surgery (2024)
International Journal of Surgery
5410

# Page 3

for Disease Control and Prevention (CDC) criteria (yes/no).
MIMIC Database Cohort As previously noted[7], MIMIC-IV
data were acquired with proper authorization, the demographic
characteristics included age, sex, race, and weight. Laboratory
test results included cholesterol level, white blood cell (WBC)
count, red blood cell (RBC) count, SBP, and DBP. Documented
comorbidities included congestive heart failure, peripheral vas-
cular disease, hypertension, paralysis, vascular disease, and dia-
betes. Disease scores such as the Simpliﬁed Acute Physiology
Score (SAPS) II, Acute Physiology Score (APS) III, Logistic Organ
Dysfunction System (LODS), Glasgow Coma Scale (GCS), and
Sequential Organ Failure Assessment (SOFA) were also con-
sidered. The initial recorded values were determined when the
variables were documented more than once in the previous 24 h.
The follow-up period commenced on admission and concluded at
the occurrence of a speciﬁc endpoint of interest, providing crucial
insights into patient progression.
The NHANES (1999–2018) and MIMIC-IV cohorts were
systematically analyzed (Fig. 1). The missing values are detailed in
Supplementary
Table
S1–Table
S2
(Supplemental
Digital
Content 1, http://links.lww.com/JS9/C792). Variables with more
than 20% missing values were omitted, and multiple imputation
techniques were applied to enhance the reliability of the results
for variables with less than 20% missing values.
Triglyceride glucose (TyG) index deﬁnition
The TyG index is a key indicator calculated using the following
formula: Ln [triglycerides (mg/dl) × glucose (mg/dl)/2].
Outcomes and follow-up
In the NHANES cohort (1999–2018), data on all-cause mortality
were linked to the death linkage ﬁles until 31 December 2019.
The follow-up time was computed from the examination date to
either the date of death or the conclusion of the follow-up period
(31 December 2019).
For the MIMIC-IV cohort, the follow-up period commenced
more than 4 h after ICU admission and concluded with the
occurrence of the speciﬁed outcome.
Statistical analysis
In the NHANES cohort (1999–2018), we used sample weights,
pseudo-primary sampling units (PSUs) (sdmvpsu), and pseudos-
trata (sdmvstra) to accommodate a stratiﬁed multistage design
across various sampling cycles. Following the NHANES guide-
lines, the sample weights were computed as 2/5WTMEC4YR for
the years 1999–2002 and 1/5WTMEC4YR for the years
2003–2018 in subsequent analyses[8,9].
Survey weighting was employed for the NHANES cohort
(1999–2018) processing but not for the MIMIC-IV cohort.
TyG was computed as both a continuous and a categorical
variable (quartiles: Q1-Q4) in both cohorts to evaluate its asso-
ciation with stroke. Mann–Whitney U or Kruskal–Wallis tests
were used to assess the normal distribution. Continuous variables
are presented as mean [standard error (SE)] or median [inter-
quartile range (IQR)], and categorical variables as percentages
(%). Analysis of variance (ANOVA) and χ2 tests were used for
group comparisons.
The Cox proportional risk model was used to determine the
hazard ratios (HR) and 95% CI between TyG (continuous and
quartiles) and stroke-related all-cause mortality. Multivariate
regression models adhering to the STROBE guidelines[10] were
applied to the NHANES cohort (Model 1: no adjustment; Model
2: adjusted for age, sex, race, and weight; Model 3: adjusted for
age, sex, race, BMI, PIR, education, smoking, alcohol use, phy-
sical activity, diabetes, TC, LDL, HDL, SBP, and DBP). For the
MIMIC-IV cohort, several models were included (Model 1: no
adjustment; Model 2: adjusted for age, sex, race, and weight;
Model 3: adjusted for age, sex, race, weight, cholesterol, WBC
count, RBC count, SBP, DBP, congestive heart failure, peripheral
vascular disease, hypertension, paralysis, vascular disease, dia-
betes, SAPS II, APS III, LODS, GCS, and SOFA).
Restricted cubic spline (RCS) analysis was used to explore the
nonlinear
relationship
between
TyG
and
all-cause
stroke
mortality.
The subgroup analyses focused on speciﬁc populations. In the
NHANES cohort (1999–2018), attention was given to age (< 65
and ≥65 years), sex (female and male), race (non-Hispanic White
and others), BMI (< 30·0 kg/m2 and ≥30·0 kg/m2), smoking (yes/
no), and diabetes (yes/no). In the MIMIC-IV cohort, analyses
considered age (< 65 and ≥65 years), sex (male/female), race
(Black, White, and other), congestive heart failure (yes/no), per-
ipheral vascular disease (yes/no), hypertension, paralysis (yes/no),
vascular disease (yes/no), diabetes (yes/no), and GCS[3–15].
Likelihood ratio tests were used to assess stroke interactions with
the stratiﬁcation variables.
Sensitivity analysis
Sensitivity analysis was performed to enhance the stability of the
results. In the NHANES cohort (1999–2018), individuals who
experienced a stroke within 2 years were initially excluded to
mitigate the risk of reverse causation. Given the potential impact
of antihyperglycemic, antihyperlipidemic, and antihypertensive
drugs on stroke risk, participants using these medications were
excluded from the analysis. A similar approach was applied in the
MIMIC-IV cohort, excluding patients using antihyperglycemic
agents and antihyperlipidemic drugs, to bolster the robustness of
the results.
Two-sample MR analysis
MR relied on three core assumptions to evaluate the causal
association between exposure and outcomes: 1) SNPs chosen as
instrumental variables exhibited strong associations with TyG
(exposure), 2) genetic variants demonstrated no associations with
other confounding factors, and 3) the impact of a genetic variant
on stroke (outcome) was solely attributed to TyG.
Our
study
leveraged
data
from
the
Finnish
cohort
(ﬁnngen_R9_C_STROKE) within the FinnGen study[11], a large-
scale genomics initiative analyzing over 500 000 Finnish Biobank
samples, to correlate genetic variations with health data and
elucidate disease mechanisms and susceptibility. We utilized a
summary-level GWAS dataset for stroke in the European popu-
lation tested in 2023 (n = 311,635; cases n = 39 818; controls
n = 271 817). The validation cohort comprised publicly available
data
from
the
MEGASTROKE
consortium
encompassing
446 696 individuals of European ancestry (406 111 noncases and
40 585 stroke cases), including those with ischemic stroke,
intracerebral hemorrhage, and strokes of unknown or unde-
termined types (n = 67 162).
Jiang et al. International Journal of Surgery (2024)
5411

# Page 4

SNPs associated with the TyG index were selected from a
previous GWAS (P < 5 × 10-8). This GWAS involved 273 368
participants aged 40–69 years without diabetes or lipid meta-
bolism disorders[12]. SNPs were excluded based on linkage dis-
equilibrium
(R2 < 0·01,
kb = 10
Mb),
particularly
those
associated with triglycerides, glucose, and nonlipid/nonglycemic
factors (including SBP, DBP, and BMI), to address potential
horizontal pleiotropy (P < 5 × 10-8). Ultimately, 192 SNPs were
selected
as
instrumental
variables
for
the
TyG
index
(Supplementary Table S3, Supplemental Digital Content 1, http://
links.lww.com/JS9/C792).
Instrumental variables selection and functional analysis
We meticulously ﬁltered out nonpresent SNPs in the outcome
GWAS through a rigorous series of steps and harmonized the
exposure and outcome data. The identiﬁed SNPs were mapped to
their corresponding genes using the GWAS Catalog (https://
www.ebi.ac.uk/gwas/). To unravel the biological functions and
pathway mechanisms associated with these SNPs, we conducted
analyses using gene ontology and the Kyoto Encyclopedia of
Genes and Genomes (KEGG). Interactions between different
SNPs were explored using STRING (https://string-db.org/).
Univariate two-sample MR analysis
To assess the causal association between TyG and stroke, we
leveraged GWAS data. The outcome estimate for the primary MR
analysis
was
determined
using
inverse
variance-weighting
(IVW)[13]. Complementary analyses included the weighted
median[14], MR-Egger[15] , and weighted mode. The MR-Egger
intercept was employed for multivariate validity assessment, and
Cochran’s Q test was used to evaluate the heterogeneity among
genetic variants.
Multivariate mendelian randomization (MVMR) analysis
We employed the IVW method as the primary analysis, adjusting
for confounders such as alcohol consumption[16], diabetes[11],
BMI[17], and Apolipoprotein B (ApoB)[18]. Additionally, we
conducted co-adjustments for these confounders in sensitivity
analyses.
The
MR
analyses
were
performed
using
the
TwoSampleMR, MR-PRESSO, and MVMR software packages
in R (v.4.2.3; R Basis for Statistical Computing, Vienna, Austria).
All P-values were two-sided, and statistical signiﬁcance was
deﬁned as P < 0·05.
Data and resource availability
The MIMIC-IV cohort of this study is available from the
Massachusetts Institute of Technology (MIT) and the Beth Israel
Deaconess Medical Center (BIDMC), and the data are available
to the authors upon reasonable request, with permission from
MIT and BIDMC. The National Center for Health Statistics and
Ethics Review Board approved the NHANES protocol, and all
participants provided written informed consent.
Role of the funding source
The funder of the study had no role in study design, data col-
lection, data analysis, data interpretation, or writing of the
report.
Result
Baseline characteristics
In the NHANES cohort (1999–2018), the median age was 67.00
(54·00–77·00) years, with male participants (n = 355). In the
MIMIC-IV cohort, the median age was 69.03 (58·25–78·70)
years, with 52·12% male participants. The detailed baseline
characteristics are presented in (Supplementary Table S4,
Supplemental
Digital
Content
1,
http://links.lww.com/JS9/
C792). The association between the TyG index and stroke was
explored
using
TyG
quartiles.
In
the
NHANES
cohort
(1999–2018), a non-Hispanic White race, BMI ≥30 kg/m2, and
diabetes showed higher TyG indexes, with signiﬁcant differences
in LDL, HDL, and TC among TyG quartiles. In the MIMIC
cohort (Supplementary Table S5, Supplemental Digital Content
1, http://links.lww.com/JS9/C792), signiﬁcant differences were
observed in the TyG quartiles for congestive heart failure, dia-
betes mellitus, weight, APS III, LODS, SOFA, glucose, choles-
terol, and WBC count.
Association between TyG index and stroke: results from two
cohorts
The TyG index was evaluated as a continuous and categorical
variable to assess its association with the risk of stroke-related
mortality in the NHANES and MIMIC-IV cohorts. In the
NHANES cohort (1999–2018), after comprehensive adjustment
for potential confounders, a linear association was observed
between the TyG index and stroke-related mortality (P for non-
linearity = 0·164) (Figure S1). Notably, there was a 36% reduc-
tion in the risk of all-cause mortality for each unit increase in TyG
level as a continuous variable. A 38% reduction in risk was
observed for each unit increase in TyG level in the Q3 group.
Trend analysis indicated a statistically signiﬁcant association
between increasing TyG levels and reduced all-cause mortality
from stroke (P = 0·015) (Table 1). Sensitivity analysis, excluding
stroke
cases
with
follow-up
within
less
than
2
years
(Supplementary Table S6, Supplemental Digital Content 1, http://
links.lww.com/JS9/C792) and recent use of antihyperglycemic
(Supplementary Table S7, Supplemental Digital Content 1, http://
links.lww.com/JS9/C792), antihyperlipidemic (Supplementary
Table S8, Supplemental Digital Content 1, http://links.lww.com/
JS9/C792), and antihypertensive medications (Supplementary
Table S9, Supplemental Digital Content 1, http://links.lww.com/
JS9/C792), consistently supported our ﬁndings.
In the MIMIC-IV cohort, the results mirrored those of the
NHANES cohort (1999–2018), demonstrating a linear correla-
tion (P for nonlinearity = 0·173) (Figure S1). Following adjust-
ment for potential confounders, the TyG index as a continuous
variable exhibited a negative association with the risk of all-cause
mortality from stroke (HR 0·46, 95% CI: 0·27–0·80, P = 0·006).
Categorically, it showed a negative association with mortality
risk in the Q3 and Q4 groups (Q3, HR 0·32, 95% CI: 0·12–0·86,
P = 0·023; Q4, HR 0·30, 95% CI: 0·10–0·89, P = 0·030).
Consistent with the NHANES cohort (1999–2018), the risk of
all-cause mortality from stroke increased progressively with
increasing TyG index (P for trend = 0·017) (Table 1). Sensitivity
analyses further supported our conclusions (Supplementary
Table S10–S11, Supplemental Digital Content 1, http://links.
lww.com/JS9/C792).
Jiang et al. International Journal of Surgery (2024)
International Journal of Surgery
5412

# Page 5

Subgroup analysis
Subgroup analyses were conducted for both the stroke cohorts. In
the NHANES cohort (1999–2018) (Fig. 2A), non-Hispanic
White participants exhibited a higher stroke risk compared to
other racial groups (HR 0·29, 95% CI: 0·14–0·61, P = 0·001).
Participants with a BMI ≥30·0 kg/m2 (HR 0·27, 95% CI:
0·10–0·72, P = 0·009) and those with diabetes (HR 0·37, 95% CI:
0·17–0·80, P = 0·011) displayed a negative association between
TyG index and all-cause mortality from stroke. A similar trend
was observed in the MIMIC cohort (Fig. 2B), where the TyG
index in participants aged ≥65 years (HR 0·49, 95% CI:
0·26–0·94, P = 0·031, P for interaction = 0·026) and those with
paraplegia (HR 0·26, 95% CI: 0·07–0·99, P = 0·048) was nega-
tively linked to the risk of all-cause mortality from stroke. This
association persisted in both cohorts.
Two-sample Mendelian analysis of TyG and stroke, with
validation
To further validate our observational ﬁndings across the two
cohorts, we conducted a one-way two-sample MR to assess the
causal relationship between TyG index and stroke risk. The
results revealed a signiﬁcant association, indicating that an ele-
vated TyG index was associated with an increased risk of stroke
(OR 0·711, 95% CI: 0·641–0·788, P = 7·64 × 10-11) (Fig. 3).
Sensitivity analyses demonstrated no horizontal pleiotropy
(intercept = −0·003, P = 0.064) or heterogeneity (Cochran’s
Q = 102·425, P = 0·931) for the selected SNPs (Supplementary
Table S12, Supplemental Digital Content 1, http://links.lww.
com/JS9/C792).
Additional complementary MR methods, including MR-Egger
(P = 0·011), weighted median (P = 0·005), and weighted mode
(P = 0·019) consistently supported our primary ﬁndings. To fur-
ther strengthen our conclusions, we validated our results using
the MEGASTROKE Consortium’s stroke GWAS pooled data,
which conﬁrmed a similar phenomenon (OR 0·783, 95% CI:
0·698–0·878,
P = 2·95 × 10-05)
(Supplementary
Table
S13,
Supplemental
Digital
Content
1,
http://links.lww.com/JS9/
C792).
Moreover, we mapped common SNPs (n = 113) from both
cohorts to protein-coding genes (Supplementary Figure S2A-S2C,
Supplemental
Digital
Content
1,
http://links.lww.com/JS9/
C792). Subsequent investigations using the STRING protein
interaction database as well as gene ontology and KEGG analyses
revealed signiﬁcant enrichment of these genes in biological
functions such as lipid homeostasis, triglyceride homeostasis, and
regulatory pathways of cholesterol metabolism.
To address potential confounding factors, we performed
multivariate two-sample MR analyses after adjusting for stroke
risk factors (alcohol consumption, diabetes, BMI, and ApoB)
Table 1
Association between TyG and stroke from the NHANES Cohort (1999–2018) and MIMIC-IV cohort.
TyG quartile
NHANES Cohorta
TyG (continuous per 1 unit)
Q1
Q2
Q3
Q4
P for trend
Model 1b
HR (95% CI)
0.99 (0.80–1.22)
Ref
0.95 (0.58–1.56)
0.97 (0.64–1.47)
1.00 (0.65–1.53)
P
0.928
0.85
0.884
0.999
0.997
Model 2c
HR (95% CI)
0.99 (0.79–1.25)
Ref
1.19 (0.79–1.85)
0.82 (0.56–1.20)
1.05 (0.70–1.57)
P
0.957
0.452
0.3
0.821
0.237
Model 3d
HR (95% CI)
0.64 (0.41–0.99)
Ref
1.08 (0.67–1.74)
0.62 (0.40–0.96)
0.70 (0.38–1.32)
P
0.047
0.758
0.033
0.273
0.015
MIMIC-IV Cohorte
Model 1f
HR (95% CI)
0.76 (0.50–1.15)
Ref
0.56 (0.23–1.37)
0.44 (0.18–1.08)
0.64 (0.29–1.42)
P
0.197
0.204
0.074
0.276
0.291
Model 2g
HR (95% CI)
0.73 (0.47–1.13)
Ref
0.58 (0.23–1.47)
0.43 (0.17–1.07)
0.64 (0.28–1.46)
P
0.16
0.254
0.071
0.285
0.247
Model 3h
HR (95% CI)
0.46 (0.27–0.80)
Ref
0.50 (0.18–1.36)
0.32 (0.12–0.86)
0.30 (0.10–0.89)
P
0.006
0.17
0.023
0.03
0.017
aNHANES Cohort:
bModel 1: adjusted for none.
cModel 2: adjusted for age, sex, race, and BMI.
dModel 3: adjusted for age, sex, race, BMI, PIR, education, smoking, alcohol use, physical activity, diabetes, TC, LDL, HDL, SBP, and DBP.
eMIMIC-IV Cohort:
fModel 1: adjusted for none.
gModel 2: adjusted for age, sex, race, and weight.
hModel 3: adjusted for age, sex, race, weight, cholesterol, WBC count, RBC count, SBP, DBP, congestive heart failure, peripheral vascular disease, hypertension, paralysis, vascular disease, diabetes, SAPS II,
APS III, LODS, GCS, and SOFA.
APS III, Acute Physiology Score III; DBP, diastolic blood pressure; GCS, Glasgow Coma Scale; HR, hazard ratio; HDL, high-density lipoprotein; HR, hazard ratio; LDL, low-density lipoprotein; LODS, Logistic Organ
Dysfunction System; MIMIC, Medical Information Mart for Intensive Care; NHANES, National Health and Nutrition Examination Survey; PIR, poverty income ratio; SBP, systolic blood pressure; SAPS II, Simpliﬁed
Acute Physiology Score II; SBP, systolic blood pressure; SOFA, Sequential Organ Failure Assessment; TC, total cholesterol; TyG, triglyceride glucose index; WBC, white blood cell; RBC, red blood cell.
Jiang et al. International Journal of Surgery (2024)
5413

# Page 6

(Fig. 3). The results remained stable in both single-adjusted and
fully adjusted risk factor models.
Discussion
A large number of previous studies have conﬁrmed a strong
association between the TyG index and diseases such as diabetes,
atherosclerotic cardiovascular disease, hypertension, and heart
failure[19–21]. In NHANES cohort (1999–2018), the risk of death
from stroke decreased by 36% for each unit increase in the TyG
index, and in the Q3 group, the risk of death from stroke
decreased by 38%. In the MIMIC-IV cohort, the risk of death
from stroke was reduced by 54% for each unit increase in the
TyG index, and the risk of death was reduced by 68% in the Q3
group and 70% in the Q4 group.
The possible reasons for this are as follows:
(1) High or low levels of triglycerides and glucose can be
detrimental to health, and both can lead to worsening of
disease. Low levels of glucose increase adrenaline levels,
which can further lead to vasoconstriction and platelet
buildup, promoting cardiovascular and cerebrovascular
events[22]. Low triglyceride levels are associated with recur-
rent ischemia and higher mortality in patients with acute
coronary syndrome[23]. A U-shaped association of the TyG
index with mortality in CVD patients with diabetes mellitus
or prediabetes mellitus (all-cause mortality risk HR 0·47;
cardiovascular mortality risk HR 0·25)[24].
(2) We observed that the majority of participants included in the
NHANES and MIMIC cohorts were typically overweight,
from BMI and weight data. In the study by Hou et al.[25],
mortality was signiﬁcantly lower in overweight/obese stroke
patients than in stroke patients with normal/low BMI. This
may be due to the obesity-stroke paradox. Adipose tissue
secretes soluble tumor necrosis factor (TNF)-α receptors and,
therefore, neutralizes the biological effects of TNF-α. Some
studies have explained that obese patients may receive early
preventive measures from clinicians and earlier treatment
with antithrombotics, antihypertensives, and statins[26–28].
However, in our study, we performed sensitivity analyses
(including baseline use of hypoglycemic, lipid-lowering, and
antihypertensive medications), and our results did not sup-
port this explanation. Another argument that seems more
reasonable is that the obesity paradox occurs more fre-
quently in patients with insulin resistance; most patients with
insulin resistance have obesity and are overweight, and the
TyG index is more responsive to a disturbed insulin resis-
tance state[29]. In patients with acute ischemic stroke under-
going intravenous thrombolysis, a low percentage of visceral
abdominal fat is associated with good outcomes[30]. This
ﬁnding suggests that obesity has unexpected protective
effects.
MR, a technique for exploring causal associations which
assumes that the allele of interest is randomly and uniformly
distributed in the population of interest, is similar to a rando-
mized controlled experiment and can effectively overcome the
limitations of observational studies[31]. In our two-sample MR
analysis, a causal association between the TyG index and reduced
risk of stroke, which is consistent with our observational study
and was validated using other GWAS data. This ﬁnding sig-
niﬁcantly strengthened the authenticity and validity of the results.
Figure 3. Mendelian randomization to determine the causal association
between TyG index and stroke. OR, odd ratio; SNP, single nucleotide
polymorphisms.
Figure 2. Subgroup analysis of TyG index and stroke. A, NHANES cohort
(1999–2018). B, MIMIC- IV cohort. HR, hazard ratio; GCS, Glasgow
Coma Scale.
Jiang et al. International Journal of Surgery (2024)
International Journal of Surgery
5414

# Page 7

To the best of our knowledge, this is also the ﬁrst study to ela-
borate on the relationship between the TyG index and stroke risk.
Strengths and limitations
The strengths of our study are as follows: (1) detailed and com-
prehensive analysis of two independent cohorts strengthened our
ﬁndings through a series of sensitivity analyses; and (2) we further
addressed the limitations of traditional observational studies
through a MR approach and employed multivariate two-sample
MR to consolidate our conclusions, with multiple methods to test
for pleiotropy and heterogeneity.
In addition, there were limitations to this study. First, as an
observational cohort study, we only had BMI data from the
NHANES cohort and weight data from the MIMIC cohort
(height data were missing in large numbers), and the NHANES
data were obtained based on questionnaire self-reporting from
the population, which is not ideal for diagnostic accuracy.
Second, the obesity paradox is a concerning problem, and visceral
obesity, other factors, and selection bias in the population may
affect our conclusions. Third, the MR analysis was conﬁned to a
European population; generalizations of other populations
deserve our consideration, and the robustness of the study is still
relatively limited.
Conclusions
Our ﬁndings suggest that there is an association between the TyG
index and stroke risk reduction, and that our ﬁndings have
implications for stroke risk control not only in clinical treatment
but also in prevention. We look forward to large-scale, multi-
ethnic prospective studies addressing this issue in the future.
Ethical approval
All studies had been approved by a relevant ethical review board
and participants had given informed consent. Ethical approval
was not required because of the public characteristics of the data
of GWAS.
Consent
Informed consent was not required for this study
Source of funding
This study was supported by grants from the National Natural
Science Foundation of China (No. 82260378), High-end Talent
Program for Science, Technology and Innovation (No. G3423),
and Natural Science Foundation of Jiangxi Provincial Science and
Technology Department (No. 20232ACB206019).
Author contribution
All authors contributed signiﬁcantly to, and are in agreement
with, the content of the manuscript. Z.Y.: conceptualization;
J.Y.A. and S.J.: data curation and resources; C.P. and C.J.H.:
formal analysis and software; Z.Y.: funding acquisition; Z.Y.Y.,
L.J.W., and C.J.H.: investigation; C.J.H. and C.S.Q.: methodol-
ogy; Z.Y.: supervision; J.Y.A. and S.J.: validation; Z.Y.Y. and
L.J.W.: visualization; J.Y.A. and S.J.: writing – original draft; Z.
Y.: project administration and writing – review and editing and
ZY is the guarantor of this work and, as such, had full access to all
the data in the study and takes responsibility for the integrity of
the data and the accuracy of the data analysis.
Conﬂicts of interest disclosure
This study did not involve any research conducted on human or
animal participants. The authors declare no conﬂict of interest.
Research registration unique identifying number
(UIN)
1. Name of the registry: not applicable.
2. Unique identifying number or registration ID: not applicable.
3. Hyperlink to your speciﬁc registration (must be publicly
accessible and will be checked): not applicable.
Guarantor
Zhang Yan.
Data availability statement
The datasets that were obtained in this study can be made
available by the corresponding author upon reasonable request.
Provenance and peer review
Not applicable.
Acknowledgement
Genetic association estimates were obtained from a genome-wide
association meta-analysis of the MRC-IEU study and the
FinnGen consortium. The authors thank all the investigators for
sharing these data. We also thank “easyMR” for some code
support.
References
[1] Loh HC, Lim R, Lee KW, et al. Effects of vitamin E on stroke: a systematic
review with meta-analysis and trial sequential analysis. Stroke Vasc
Neurol 2021;6:109–20.
[2] Boehme AK, Esenwa C, Elkind MS. Stroke risk factors, genetics, and
prevention. Circ Res 2017;120:472–95.
[3] Campbell BCV, De Silva DA, Macleod MR, et al. Ischaemic stroke. Nat
Rev Dis Primers 2019;5:70.
[4] Guerrero-Romero F, Simental-Mendía LE, González-Ortiz M, et al. The
product of triglycerides and glucose, a simple measure of insulin sensi-
tivity. Comparison with the euglycemic-hyperinsulinemic clamp. J Clin
Endocrinol Metab 2010;95:3347–51.
[5] Sánchez-García A, Rodríguez-Gutiérrez R, Mancillas-Adame L, et al.
Diagnostic accuracy of the triglyceride and glucose index for insulin
resistance: a systematic review. Int J Endocrinol 2020;2020:4678526.
[6] Sekula P, Del Greco MF, Pattaro C, et al. Mendelian randomization as an
approach to assess causality using observational data. J Am Soc Nephrol
2016;27:3253–65.
[7] Jiang Y, Chen P, Zhao Y, et al. Association between triglyceride glucose
index and all-cause mortality in patients with cerebrovascular disease: a
retrospective study. Diabetol Metab Syndr 2024;16:1.
Jiang et al. International Journal of Surgery (2024)
5415

# Page 8

[8] Johnson CL, Paulose-Ram R, Ogden CL, et al. National health and
nutrition examination survey: analytic guidelines, 1999-2010. Vital
Health Stat 2 2013:1–24.
[9] Akinbami LJ, Chen TC, Davy O, et al. National health and nutrition
examination survey, 2017-march 2020 prepandemic ﬁle: sample design,
estimation, and analytic guidelines. Vital Health Stat 1 2022;190:1–36.
[10] von Elm E, Altman DG, Egger M, et al. The strengthening the reporting of
observational studies in epidemiology (STROBE) statement: guidelines
for reporting observational studies. Lancet (London, England) 2007;370:
1453–7.
[11] Kurki MI, Karjalainen J, Palta P, et al. FinnGen provides genetic insights
from a well-phenotyped isolated population. Nature 2023;613:508–18.
[12] Si S, Li J, Li Y, et al. Causal effect of the triglyceride-glucose index and the
joint exposure of higher glucose and triglyceride with extensive cardio-
cerebrovascular metabolic outcomes in the UK biobank: a mendelian
randomization study. Front Cardiovasc Med 2020;7:583473.
[13] Lin Z, Deng Y, Pan W. Combining the strengths of inverse-variance
weighting and Egger regression in Mendelian randomization using a
mixture of regressions model. PLoS Genet 2021;17:e1009922.
[14] Bowden J, Davey Smith G, Haycock PC, et al. Consistent estimation in
Mendelian randomization with some invalid instruments using a
weighted median estimator. Genet Epidemiol 2016;40:304–14.
[15] Bowden J, Davey Smith G, Burgess S. Mendelian randomization with
invalid instruments: effect estimation and bias detection through Egger
regression. Int J Epidemiol 2015;44:512–25.
[16] Clarke TK, Adams MJ, Davies G, et al. Genome-wide association
study of alcohol consumption and genetic overlap with other health-
related traits in UK Biobank (N = 112 117). Mol Psychiatry 2017;22:
1376–84.
[17] Yengo L, Sidorenko J, Kemper KE, et al. Meta-analysis of genome-wide
association studies for height and body mass index in ∼700000 indivi-
duals of European ancestry. Hum Mol Genet 2018;27:3641–9.
[18] Elsworth B, Lyon M, Alexander T, et al. The MRC IEU OpenGWAS data
infrastructure. bioRxiv 2020.
[19] Ramdas Nayak VK, Satheesh P, Shenoy MT, et al. Triglyceride glucose
(TyG) index: a surrogate biomarker of insulin resistance. J Pak Med
Assoc 2022;72:986–8.
[20] Muhammad IF, Bao X, Nilsson PM, et al. Triglyceride-glucose (TyG)
index is a predictor of arterial stiffness, incidence of diabetes, cardi-
ovascular disease, and all-cause and cardiovascular mortality: a
longitudinal two-cohort analysis. Front Cardiovasc Med 2022;9:
1035105.
[21] Xu J, Xu W, Chen G, et al. Association of TyG index with pre-
hypertension or hypertension: a retrospective study in Japanese normo-
glycemia subjects. Front Endocrinol 2023;14:1288693.
[22] Galassetti P, Davis SN. Effects of insulin per se on neuroendocrine and
metabolic counter-regulatory responses to hypoglycaemia. Clin Sci
(Lond) 2000;99:351–62.
[23] Cheng KH, Chu CS, Lin TH, et al. Lipid paradox in acute myocardial
infarction-the association with 30-day in-hospital mortality. Crit Care
Med 2015;43:1255–64.
[24] Zhang Q, Xiao S, Jiao X, et al. The triglyceride-glucose index is a pre-
dictor for cardiovascular and all-cause mortality in CVD patients with
diabetes
or
pre-diabetes:
evidence
from
NHANES
2001-2018.
Cardiovasc Diabetol 2023;22:279.
[25] Hou Z, Pan Y, Yang Y, et al. An analysis of the potential relationship of
triglyceride glucose and body mass index with stroke prognosis. Front
Neurol 2021;12:630140.
[26] Oesch L, Tatlisumak T, Arnold M, et al. Obesity paradox in stroke -
Myth or reality? A systematic review. PLoS ONE 2017;12:e0171334.
[27] Steinberg BA, Cannon CP, Hernandez AF, et al. Medical therapies and
invasive treatments for coronary artery disease by body mass: the ‘obesity
paradox’ in the Get With The Guidelines database. Am J Cardiol 2007;
100:1331–5.
[28] Kuo CS, Kuo NR, Yeh YK, et al. Residual risk of cardiovascular com-
plications in statin-using patients with type 2 diabetes: the Taiwan
Diabetes Registry Study. Lipids Health Dis 2024;23:24.
[29] Xu J, Wang A, Meng X, et al. Obesity-stroke paradox exists in insulin-
resistant patients but not insulin sensitive patients. Stroke 2019;50:
1423–9.
[30] Kim JH, Choi KH, Kang KW, et al. Impact of visceral adipose tissue on
clinical outcomes after acute ischemic stroke. Stroke 2019;50:448–54.
[31] Sanderson E. Multivariable Mendelian randomization and mediation.
Cold Spring Harb Perspect Med 2021;11:a038984.
Jiang et al. International Journal of Surgery (2024)
International Journal of Surgery
5416
