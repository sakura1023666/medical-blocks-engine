# Page 1

RESEARCH
Open Access
© The Author(s) 2026. Open Access  This article is licensed under a Creative Commons Attribution-NonCommercial-NoDerivatives 4.0 
International License, which permits any non-commercial use, sharing, distribution and reproduction in any medium or format, as long as you 
give appropriate credit to the original author(s) and the source, provide a link to the Creative Commons licence, and indicate if you modified the 
licensed material. You do not have permission under this licence to share adapted material derived from this article or parts of it. The images or 
other third party material in this article are included in the article’s Creative Commons licence, unless indicated otherwise in a credit line to the 
material. If material is not included in the article’s Creative Commons licence and your intended use is not permitted by statutory regulation or 
exceeds the permitted use, you will need to obtain permission directly from the copyright holder. To view a copy of this licence, visit ​h​t​t​p​:​/​/​c​r​e​a​t​i​
v​e​c​o​m​m​o​n​s​.​o​r​g​/​l​i​c​e​n​s​e​s​/​b​y​-​n​c​-​n​d​/​4​.​0​/.
Jin et al. Cardiovascular Diabetology          (2026) 25:145 
https://doi.org/10.1186/s12933-026-03149-5
Cardiovascular Diabetology
*Correspondence:
Yue Liu
liuyue0422@163.com
Liping Wei
weilipingme@163.com
Zhi Qi
qizhi@nankai.edu.cn
Xin Qi
qixinx2011@126.com
Full list of author information is available at the end of the article
Abstract
Background  Insulin resistance is a central pathophysiological feature of cardiovascular–kidney–metabolic (CKM) 
syndrome and has been implicated in adverse cardiovascular outcomes. However, the association between 
triglyceride–glucose (TyG) index–related indicators and heart failure (HF)–related mortality in individuals with early-
stage CKM syndrome remains unclear.
Methods  This research conducted a prospective analysis using data from the National Health and Nutrition 
Examination Survey (NHANES) 2005–2018. Participants with CKM stages 0–2 and without clinical cardiovascular 
disease at baseline were included. TyG and related indices (TyG-BMI, TyG-WC, and TyG-WHtR) were analyzed as 
continuous and quartile-based variables. The primary outcome was HF-related mortality, ascertained via linkage to 
the National Death Index. Associations were assessed using Cox proportional hazards and Fine–Gray competing risk 
models with hierarchical adjustment, including additional adjustment for CKM stage in extended models. Machine 
learning approaches (Boruta and SHAP) were applied for covariate selection. Nonlinear associations, predictive 
performance, mediation by HbA1c, and subgroup effects were further evaluated.
Results  Among 14,830 participants, higher TyG-related indices were associated with increased HF-related mortality 
during follow-up. After full adjustment, each 1-SD increase in TyG-WC and TyG-WHtR was associated with a 2.27-fold 
and 2.94-fold higher risk of HF-related mortality, respectively (all P < 0.05). The associations remained consistent after 
Association between triglyceride-glucose 
index and related indicators with heart 
failure–related mortality in individuals 
with early-stage cardiovascular-kidney-
metabolic syndrome
Xiandu Jin1,2,3, Yurong Feng1,2, Chang Liu1,2, Tianwei Cheng1,2, Yanye Jin1,2, Zibin Shao1, Yongyu Bian1, Hao Wu1,3, 
Jiao Li3, Yue Liu1,2,3*, Liping Wei1,2,3*, Zhi Qi1,2,3* and Xin Qi1,2,3*

# Page 2

Page 2 of 18
Jin et al. Cardiovascular Diabetology          (2026) 25:145 
Introduction
Heart failure (HF) represents a common and devastat­
ing clinical endpoint of multiple cardiovascular, meta­
bolic, and renal disorders, characterized by complex and 
heterogeneous pathophysiological mechanisms [1, 2]. 
In recent decades, the global rise in metabolic abnor­
malities—including obesity, diabetes, and chronic kidney 
disease—has contributed to a sustained increase in the 
absolute burden of HF, posing a major public health chal­
lenge worldwide [3]. Although age-standardized rates of 
HF incidence and mortality have modestly declined, the 
total number of HF-related deaths continues to rise due 
to population aging and the growing prevalence of car­
diometabolic risk factors [4]. These trends underscore 
the urgent need for early risk stratification and targeted 
additional adjustment for CKM stage. Restricted cubic spline analyses demonstrated predominantly linear dose–
response relationships. TyG-WHtR exhibited the strongest discriminatory ability (AUC = 0.641, 95% CI 0.601–0.680). 
Mediation analyses indicated that HbA1c accounted for approximately 15%–30% of the observed associations. 
Associations were generally consistent across clinically relevant subgroups and remained robust in competing risk 
analyses and sensitivity analyses.
Conclusions  In individuals with early-stage CKM syndrome, TyG-related indices—particularly those incorporating 
central adiposity—are independently associated with HF-related mortality. These findings highlight the prognostic 
relevance of insulin resistance–related metabolic burden in the early stages of CKM syndrome.
Highlights
1.Higher triglyceride–glucose (TyG) index and related indicators were independently associated with heart failure–
related mortality among individuals with early-stage CKM syndrome (stages 0–2).
2.TyG-related indices integrating central adiposity, particularly TyG–WHtR, showed stronger associations with HF-
related mortality than TyG alone.
3.These associations remained robust after multivariable adjustment and competing risk analyses accounting for 
non–HF-related death.
4.Restricted cubic spline analyses indicated largely linear dose–response relationships between TyG-related indices 
and HF-related mortality risk.
5.HbA1c partially mediated the associations, suggesting impaired glucose metabolism as an important pathway 
linking insulin resistance to HF-related mortality.
Keywords  CKM syndrome, Heart failure-related mortality, TyG, TyG-related indicators, HbA1c
Graphical abstract

# Page 3

Page 3 of 18
Jin et al. Cardiovascular Diabetology          (2026) 25:145 
preventive strategies before the onset of overt cardiovas­
cular disease.
The concept of the Cardiovascular–Kidney–Metabolic 
Syndrome (CKM) was proposed by the American Heart 
Association (AHA) in 2023. It emphasizes the interac­
tions and co-morbid mechanisms among the cardiovas­
cular, renal, and metabolic systems, establishing a novel 
pathophysiological framework for systematically compre­
hending the link between metabolic abnormalities and 
cardiovascular disease [5]. The AHA categorizes CKM 
syndrome into five stages to better define its progression 
from metabolic abnormalities to clinical cardiovascular 
events [6]. Stages 0–2 of CKM syndrome primarily rep­
resent preclinical or early phases, where metabolic dis­
orders and cardiac-renal impairment have not yet fully 
manifested. Identification of high-risk individuals during 
these early stages offers a critical window for preventive 
intervention and may yield substantial long-term clini­
cal benefit [7]. In contrast, CKM Stage 4 is the stage of 
established clinical cardiovascular disease, encompassing 
coronary artery disease, heart failure, stroke, peripheral 
arterial disease, or atrial fibrillation. Given heart failure’s 
central role in CKM-related adverse outcomes, identify­
ing predictive indicators for HF-related deaths in indi­
viduals with CKM syndrome stages 0–2 holds important 
clinical and public health implications.
Insulin resistance (IR) plays a central role in the patho­
genesis of CKM syndrome and is considered a key mech­
anistic link between metabolic dysregulation and adverse 
cardiovascular outcomes [8]. IR contributes to endo­
thelial dysfunction, chronic low-grade inflammation, 
myocardial metabolic remodeling, and neurohormonal 
activation, all of which are implicated in the develop­
ment and progression of HF [9]. The triglyceride–glu­
cose (TyG) index, derived from fasting triglyceride and 
glucose levels, has emerged as a simple and reproduc­
ible surrogate marker of insulin resistance and has been 
associated with atherosclerosis, coronary heart disease, 
and cardiovascular mortality in population-based stud­
ies [10–12]. IR is closely linked not only to dysglycemia 
but also to adiposity distribution, particularly visceral 
and central fat accumulation, which plays a key role in 
cardiometabolic dysfunction and heart failure patho­
physiology [13, 14]. While the TyG index is a validated 
surrogate marker of insulin resistance, it does not directly 
capture body fat distribution. Therefore, composite indi­
ces such as TyG-BMI, TyG-WC, and TyG-WHtR have 
been proposed to integrate metabolic dysregulation with 
anthropometric indicators of obesity, especially cen­
tral adiposity, which is more strongly associated with 
adverse cardiovascular outcomes than overall body mass 
alone [15, 16]. Prior studies have demonstrated that TyG-
related indices (TyG-BMI, TyG-WC, and TyG-WHtR) 
outperform the traditional TyG index in predicting 
cardiovascular disease, heart failure, and mortality, sup­
porting their potential prognostic value [17, 18]. How­
ever, the link with the likelihood of HF-related deaths in 
individuals with early-stage CKM syndrome is unknown.
Despite growing evidence linking TyG-related indices 
to cardiovascular events, several important gaps remain. 
First, most prior studies have focused on composite car­
diovascular outcomes, with limited attention to heart 
failure–related mortality, a clinically robust and prognos­
tically meaningful endpoint. Second, the predictive value 
of TyG-related indices specifically within early-stage 
CKM populations—prior to the development of overt 
cardiovascular disease—remains poorly characterized. 
Third, whether the associations between TyG-related 
indices and HF-related mortality exhibit nonlinear pat­
terns or are mediated through long-term glycemic bur­
den has not been fully explored.
Accordingly, using nationally representative data from 
the US National Health and Nutrition Examination Sur­
vey (NHANES, 2005–2018), this study aimed to inves­
tigate the associations between TyG and related indices 
with heart failure–related mortality among individu­
als with CKM stages 0–2. We further evaluated poten­
tial nonlinear dose–response relationships, assessed the 
mediating role of glycated hemoglobin (HbA1c), and 
compared the predictive performance of TyG-related 
indicators for HF-related mortality. By focusing on early-
stage CKM populations and a hard clinical endpoint, this 
study seeks to refine cardiometabolic risk stratification 
and inform early preventive strategies for heart failure.
Materials and methods
Study data and population
The data utilized in this investigation came from the 
from the National Health and Nutrition Examina­
tion Survey (NHANES). Conducted by the US Centers 
for Disease Control and Prevention (CDC), NHANES 
employs a stratified, multistage probability sampling 
design to collect nationally representative data on the 
health and nutritional status of US adults and children. 
The survey comprises standardized questionnaires and 
physical examinations laboratory assessments [19]. 
Detailed survey protocols are publicly available on the 
NHANES website (​h​t​t​p​s​:​/​/​w​w​w​.​c​d​c​.​g​o​v​/​n​c​h​s​/​n​h​a​n​e​s). 
The National Centre for Health Statistics’ (NCHS) Insti­
tutional Review Board (IRB) authorized the NHANES 
study methodology, and each participant gave written 
informed permission [20]. All data utilized in this inves­
tigation were publicly available anonymized datasets, 
requiring no additional ethical approval, and were strictly 
processed in compliance with regulations governing the 
protection of human subjects’ privacy and data security. 
The Declaration of Helsinki’s ethical guidelines were fol­
lowed throughout the research procedure.

# Page 4

Page 4 of 18
Jin et al. Cardiovascular Diabetology          (2026) 25:145 
The selection of the 2005–2018 cycles was based on the 
availability and consistency of key variables required for 
the construction of TyG-related indices and CKM stage 
classification, including fasting glucose, triglycerides, 
waist circumference, HbA1c, and kidney function mark­
ers. Earlier NHANES cycles (1999–2004) exhibited sub­
stantial variability in laboratory methods and incomplete 
availability of several relevant variables, which could 
compromise the comparability and internal validity of the 
analyses.
A total of 70,190 participants were initially identified. 
To construct the final analysis cohort, we sequentially 
excluded the following groups: (1) Baseline age < 18 years 
and age > 80 years; (2) baseline classification as CKM 
stage 4 (including coronary heart disease, myocardial 
infarction, stroke, heart failure, peripheral arterial dis­
ease, or atrial fibrillation;) (3) lacking CKM staging infor­
mation; (4) Missing data or key variables for calculating 
TyG and related indicators, including weight, height, 
waist circumference, triglycerides (TG), and fasting 
blood glucose (FBG); Following these exclusions, 14,830 
participants were ultimately enrolled. The participant 
inclusion process is illustrated in Fig. 1.
Definition of CKM syndrome stages
According to the American Heart Association (AHA) 
classification 
of 
Cardiovascular–kidney–metabolic 
(CKM) syndrome, it is categorized into stages 0 to 
4 [21]: Stage 0: No history of cardiovascular disease 
(CVD), chronic kidney disease (CKD), glucose metabo­
lism abnormalities, obesity or other metabolic syndrome 
characteristics; Stage 1: Presence of mild metabolic 
abnormalities (e.g., obesity, mild blood pressure or lipid 
abnormalities), mild renal impairment, or cardiovascu­
lar risk factors without clinical cardiovascular events; 
Stage 2 represents the coexistence of abnormalities in 
two or more systems, such as diabetes, hypertension, 
hypertriglyceridaemia, or CKD. Stage 3: Subclinical car­
diovascular abnormalities developing on a background 
of metabolic or renal dysfunction, like undetected ath­
erosclerosis or cardiac remodelling. Stage 4: Established 
clinical cardiovascular disease, including coronary artery 
disease, heart failure, stroke, peripheral arterial disease, 
or atrial fibrillation [22, 23].
In the present study, individuals classified as CKM 
stage 3 were intentionally excluded. Although CKM stage 
3 is defined as subclinical cardiovascular disease, reli­
able differentiation between subclinical cardiovascular 
abnormalities and established clinical CVD is limited in 
NHANES due to the reliance on self-reported diagnoses 
and the lack of systematic imaging or biomarker-based 
adjudication. To minimize misclassification bias and 
reverse causation, and to specifically focus on early-stage 
cardiometabolic risk preceding overt cardiovascular dis­
ease, participants with CKM stage 4 (clinical CVD) were 
also excluded at baseline. Therefore, the final analytical 
population was restricted to individuals with CKM stages 
0–2. Detailed operational definitions for CKM stage clas­
sification are provided in Table S1.
Definition of TyG and TyG-related indices
The calculation formulas for TyG and TyG-related indi­
ces are as follows [24, 25]: TyG = ln [fasting triglycerides 
(mg/dL) × fasting plasma glucose (mg/dL) / 2]; TyG-
BMI = TyG × body mass index (BMI) = TyG × [weight 
(kg) / height² (m²)]; TyG-WC = TyG × waist circumfer­
ence (WC, cm); TyG-WHtR = TyG × [WC (cm) / height 
(cm)]. BMI was calculated as weight (kg) divided by 
height squared (m²) [26]. All TyG-related indices were 
analyzed both as continuous variables (per 1-standard 
deviation increment) and as categorical variables based 
on quartiles.
Outcome assessment
The primary outcome of this study was heart failure–
related mortality. Mortality data were obtained through 
probabilistic linkage of NHANES participants to the 
National Death Index (NDI) by the National Center for 
Health Statistics. Follow-up time was calculated from the 
baseline examination date to the date of death or cen­
soring (December 31, 2019), whichever occurred first. 
Heart failure–related mortality was defined as death for 
which heart failure (ICD-10 code I50) was recorded as 
the underlying cause of death in the NDI-linked mor­
tality file. Because death certificate coding may involve 
multiple cardiovascular conditions—including ischemic 
heart disease, hypertensive heart disease, valvular heart 
disease, and cardiomyopathies—the underlying cause of 
death represents the condition judged to have initiated 
the chain of events leading directly to death. In secondary 
analyses, we also considered deaths in which heart failure 
(ICD-10 code I50) was recorded as a contributing cause, 
to assess the robustness of our findings. Deaths from 
Fig. 1  Participant selection flowchart

# Page 5

Page 5 of 18
Jin et al. Cardiovascular Diabetology          (2026) 25:145 
causes other than heart failure were treated as compet­
ing events and analyzed using Fine–Gray subdistribution 
hazard models to account for competing risks. Partici­
pants who were alive at the end of follow-up were cen­
sored. This outcome definition is consistent with prior 
NHANES-based epidemiological studies evaluating heart 
failure–related mortality [27–29].
Covariate extraction
Demographic and laboratory data were collected from 
participants via interviews and physical examinations. 
Demographic data included age, gender (male/female), 
body mass index (BMI), waist circumference (WC), 
race (Mexican American/ Non-Hispanic Black /Non-
Hispanic White/Other Hispanic/ Other Race–Including 
Multi-Racial), educational level (Less than 9th grade/9-
11th grade[including 12th grade with no diploma]/High 
school graduate or GED equivalent/Some college or AA 
degree/ College graduate or above/ Don’t Know), SBP/
DBP, smoking (No/Yes), drinking (No/Yes), hyperten­
sion (No/Yes), diabetes (No/Yes), and hyperlipidemia 
(No/Yes). Laboratory blood test data included fasting 
blood glucose (FBG), glycated haemoglobin (HbA1c), 
total cholesterol (TC), triglycerides (TG), high-density 
lipoprotein cholesterol (HDL-C), low-density lipoprotein 
cholesterol (LDL-C), and Urine creatinine-to-albumin 
ratio (ACR). Self-reported diagnosis, treatment of oral 
antihypertensive drugs or measured systolic blood pres­
sure ≥ 140 mmHg and/or diastolic blood pressure ≥ 90 
mmHg was considered hypertension [30]. Diabetes was 
defined according to American Diabetes Association 
criteria, determined based on self-reported diagnosis or 
treatment, fasting blood glucose ≥ 7.0 mmol/L, or HbA1c 
≥ 6.5% [31].
Blood samples were collected according to standardized 
procedures in the NHANES Mobile Examination Cen­
ter after an overnight fast. Fasting blood glucose (FBG) 
was measured using a hexokinase enzymatic method. 
Glycated hemoglobin (HbA1c) was assessed using high-
performance liquid chromatography (HPLC) [32]. Serum 
triglycerides (TG) and total cholesterol (TC) were mea­
sured using enzymatic assays on Roche Modular P chem­
istry analyzers. Fasting blood glucose was determined by 
a hexokinase-mediated enzymatic method using Roche/
Hitachi Cobas C 501 chemistry analyzers [33]. All labo­
ratory analyses were conducted by certified laboratories 
following standardized protocols established by the Cen­
ters for Disease Control and Prevention (CDC). Detailed 
information on specimen collection, processing, analyti­
cal methods, instruments, and quality control procedures 
is publicly available in the NHANES Laboratory Proce­
dures Manual [34].
Machine learning algorithms
Covariate selection was guided by a combination of the 
Boruta feature selection algorithm and SHapley Additive 
exPlanations (SHAP) to identify the most relevant pre­
dictors associated with heart failure–related mortality. 
The Boruta algorithm, originally proposed by Kursa and 
Rudnicki, is a wrapper-based feature selection method 
built around random forest models that iteratively com­
pares the importance of original variables with that of 
randomly permuted “shadow” features, thereby identify­
ing variables with statistically significant predictive rel­
evance [35, 36]. In this study, Boruta was implemented 
using the Boruta package in R (version 7.0.0), with default 
settings and 500 trees. SHAP values were subsequently 
applied to quantify the contribution of each predictor 
to the model output and to enhance model interpret­
ability. SHAP is based on cooperative game theory and 
was introduced by Lundberg and Lee to provide consis­
tent and locally accurate feature attributions for machine 
learning models [37, 38]. SHAP analyses were performed 
using the fastshap package in R, based on gradient boost­
ing survival models. The mean absolute SHAP value was 
used to rank variables according to their overall contribu­
tion to HF-related mortality risk.
Statistical analysis
Baseline characteristics were described according to 
CKM syndrome stages (0–2). The Shapiro–Wilk test 
assessed normality of continuous variables. Normally 
distributed variables were presented as mean ± standard 
deviation (SD) and compared using one-way ANOVA 
during intergroup; whereas non-normally distributed 
variables were summarized as median (interquartile 
range, IQR), with intergroup comparisons performed 
using the Kruskal–Wallis test. Categorical variables were 
reported as frequency and percentage (n, %), with inter­
group differences evaluated using chi-square tests. Bon­
ferroni corrections were applied to account for multiple 
comparisons.
Subsequently, each TyG-related index is grouped 
by quartile (Q1–Q4). Covariate inclusion was guided 
by Boruta and SHAP algorithms to identify the stron­
gest model predictors. Kaplan–Meier curves compared 
cumulative incidence of failure–related mortality across 
quartiles, with statistical significance evaluated using log-
rank tests. Associations between TyG-related indices and 
heart failure–related mortality were assessed using Cox 
proportional hazards models and Fine–Gray subdistribu­
tion hazard models, treating non–heart failure–related 
death as a competing risk. Three hierarchical models were 
constructed: Model 1 (unadjusted); Model 2 (adjusted for 
age and gender); and Model 3 (fully adjusted for demo­
graphic, lifestyle, and clinical covariates). As a sensitiv­
ity analysis, cardiovascular mortality was examined as

# Page 6

Page 6 of 18
Jin et al. Cardiovascular Diabetology          (2026) 25:145 
an alternative outcome using Fine–Gray competing risk 
models, treating non-cardiovascular deaths as competing 
events. Effect estimates were reported as hazard ratios 
(HRs) or subdistribution hazard ratios (sHRs) with 95% 
confidence intervals. Prior to model fitting, multicol­
linearity among covariates was evaluated using variance 
inflation factors (VIFs). Variables directly involved in the 
calculation of the TyG index, including body mass index 
(BMI), waist circumference, fasting glucose, and triglyc­
erides, were excluded from the VIF assessment to avoid 
inherent collinearity with the exposure of interest. VIFs 
were subsequently calculated for the remaining covari­
ates, including demographic characteristics, blood pres­
sure, lipid parameters (total cholesterol and HDL-C), 
and other cardiovascular risk factors. A VIF value < 5 
was considered indicative of acceptable multicollinearity 
(Table S2). Potential nonlinear relationships were exam­
ined using restricted cubic spline functions with knots 
positioned at the 5th, 35th, 65th, and 95th percentiles, 
with the median value of each exposure used as the ref­
erence point in spline models. Predictive performance of 
TyG-related indices was compared using receiver oper­
ating characteristic (ROC) curve analysis, and the area 
under the curve (AUC) was calculated to quantify and 
compare their discriminative ability for heart failure–
related mortality. The optimal cutoff value was deter­
mined using the Youden index, and the corresponding 
sensitivity and specificity were calculated.
Additionally, 
Bayesian 
mediation 
analysis 
was 
employed to investigate the mediating role of HbA1c in 
the link between TyG-related indices and heart failure–
related mortality, estimating the average causal media­
tion effect (ACME), average direct effect (ADE), and 
proportion mediated. To investigate consistency of asso­
ciations across different populations, subgroup analyses 
were conducted, with stratification variables including 
gender, age (< 60 years vs. ≥60 years), body mass index 
(BMI < 30 vs. ≥30  kg/m2), smoking, drinking, hyperten­
sion, diabetes, and dyslipidaemia. Interaction terms were 
introduced into Cox models to identify potential effect 
modifiers. All statistical analyses were performed using R 
software (version 4.2.1, R Foundation for Statistical Com­
puting, Vienna, Austria). P values < 0.05 were considered 
statistically significant.
Results
General clinical baseline characteristics
A total of 14,830 participants were included in this inves­
tigation and categorized by CKM stages as follows: Stage 
0 (n = 474), Stage 1 (n = 452), Stage 2 (n = 13904), as shown 
in Table 1. Participants in higher CKM stages were older 
and had a progressively adverse cardiometabolic profile. 
Mean age, BMI, WC, SBP and DBP increased signifi­
cantly across CKM stages (all P < 0.001). The proportion 
of females was highest in CKM stage 2 (P < 0.001). Meta­
bolic parameters, including FBG, HbA1c, TC, TG, LDL-
C, and urinary albumin-to-creatinine ratio, increased 
with advancing CKM stage, whereas HDL-C was lowest 
in stage 1 (all P < 0.001). TyG and TyG-related indices 
(TyG-BMI, TyG-WC, and TyG-WHtR) also showed a 
graded increase across CKM stages (all P < 0.001). Con­
sistent with CKM staging, the prevalence of diabetes, 
hypertension, and dyslipidemia increased markedly from 
stage 0 to stage 2 (all P < 0.001). During follow-up, HF-
related mortality differed significantly across CKM stages 
(P = 0.016), with events occurring almost exclusively 
in CKM stage 2. Mean follow-up duration was slightly 
shorter in stage 2 than in stages 0 and 1 (P < 0.001).
Incidence of heart failure-related mortality
During follow-up, the incidence and cumulative inci­
dence of heart failure-related mortality according to 
different TyG quantiles and its related indices are sum­
marized in Table 2. Across increasing quartiles of TyG, 
the incidence rate of HF-related mortality rose from 9.34 
per 10,000 person-years in the lowest quantile to 20.79 
per 10,000 person-years in the highest quantile, with the 
corresponding cumulative incidence increasing from 
0.67 to 1.67%. Similar patterns were observed for TyG-
WC and TyG-WHtR. For TyG-WC, the cumulative inci­
dence of HF-related mortality increased from 0.67% in 
the first quartile to 1.78% in the fourth quartile, while for 
TyG-WHtR, it rose from 0.46 to 1.78% across quartiles. 
In contrast, the cumulative incidence across quartiles for 
TyG-BMI exhibited a less consistent pattern, showing no 
clear monotonic increasing trend. Among participants 
who experienced heart failure–related mortality, the 
majority had ICD-10 code I50 listed as the underlying 
or contributing cause of death. Although detailed attri­
bution to specific cardiovascular conditions is limited 
by death certificate data, contributing conditions likely 
included ischemic heart disease, hypertensive heart dis­
ease, valvular heart disease, and cardiomyopathies.
Feature selection based on boruta and SHAP analyses
To support covariate selection and improve model inter­
pretability, Boruta feature selection and SHAP analy­
ses were conducted as exploratory analyses (Fig.  2). 
Age, body size–related measures, and glycaemic indices 
emerged as dominant contributors to HF-related mor­
tality. TyG and its related composite indices were con­
sistently confirmed as relevant features, although their 
relative importance was modest compared with major 
demographic and clinical predictors (Fig. 2 A, B). SHAP 
analyses further demonstrated that higher TyG-related 
values were directionally associated with increased HF-
related mortality risk, providing supportive evidence for 
subsequent regression-based findings (Fig. 2 C, D).

# Page 7

Page 7 of 18
Jin et al. Cardiovascular Diabetology          (2026) 25:145 
Associations of TyG-related indices with HF-related 
mortality
Figure 3 displays Kaplan–Meier curves for TyG and 
TyG-related indicators across quartiles. The cumula­
tive incidence of HF-related mortality progressively 
increased with higher quartiles. Higher TyG quartiles 
were associated with a progressively increased risk of 
HF-related mortality (log-rank P = 0.01; Fig. 3A). cumu­
lative HF-related mortality did not differ significantly 
across TyG–BMI quartiles (log-rank P = 0.13; Fig. 3B). In 
contrast, clear dose–response relationships were iden­
tified for TyG–WC and TyG–WHtR. Participants in 
the highest quartiles of TyG–WC and TyG–WHtR had 
markedly higher cumulative HF-related mortality com­
pared with those in lower quartiles (log-rank P = 0.00012 
and P < 0.0001, respectively; Fig.  3C–D). Overall, TyG, 
TyG–WC, and TyG–WHtR were positively associated 
Table 1  General clinical baseline characteristics
Stage 0
(n = 474)
Stage 1
(n = 452)
Stage 2
(n = 13904)
P
Age(year)
37.29 ± 13.77
44.01 ± 14.95
48.48 ± 17.28
< 0.001
Gender (Female, n,%)
128 (27.0)
108 (23.9)
7554 (54.3)
< 0.001
BMI(Kg /M2)
27.37 ± 5.15
30.38 ± 6.10
28.93 ± 6.79
< 0.001
WC(cm)
93.91 ± 13.44
102.68 ± 14.51
98.65 ± 16.21
< 0.001
SBP(mmHg)
114.39 ± 9.91
121.73 ± 14.39
123.73 ± 18.70
< 0.001
DBP(mmHg)
67.24 ± 9.80
70.69 ± 11.04
70.00 ± 12.81
< 0.001
Race (n,%)
< 0.001
Mexican American
45 (9.5)
56 (12.4)
2359(17.0)
Non-hispanic black
152 (32.1)
131 (29.0)
2726(19.6)
Non-hispanic white
185 (39.0)
194 (42.9)
5736(41.3)
Other hispanic
31 (6.5)
31 (6.9)
1449(10.4)
Other race
61 (12.9)
40 (8.8)
1634(11.7)
Education (n,%)
< 0.001
Less than 9th grade
22 (4.6)
38 (8.4)
1439 (10.3)
9-11th grade (Includes 12th grade with no diploma)
55 (11.6)
56 (12.4)
1990 (14.3)
High school graduate or GED equivalent
104 (21.9)
97 (21.5)
3163 (22.7)
Some college or AA degree
141 (29.8)
140 (31.0)
4048 (29.2)
College graduate or above
151 (31.9)
121 (26.7)
3253(23.4)
Don’t Know
1 (0.2)
0 (0)
11 (0.1)
Smoking (n,%)
184 (38.8)
207 (45.8)
6056 (43.6)
0.074
Drinking (n,%)
319 (80.8)
311 (77.6)
7926 (57.0)
< 0.001
FBG (mg/dL)
95.51 ± 9.05
103.71 ± 24.04
108.52 ± 35.26
< 0.001
HbA1c (%)
5.28 ± 0.38
5.54 ± 0.56
5.73 ± 1.09
< 0.001
TC (mg/dL)
181.35 ± 29.23
201.49 ± 46.69
194.53 ± 41.56
< 0.001
TG (mg/dL, Median (IQR))
78.00 [58.00, 111.00]
119.00 [85.00, 184.50]
102.00 [70.00, 151.00]
< 0.001
HDL-C(mg/dL)
56.72 ± 13.50
47.07 ± 14.30
54.72 ± 16.30
< 0.001
LDL-C(mg/dL)
107.08 ± 26.04
125.12 ± 38.45
115.06 ± 35.39
< 0.001
ACR (mg/g, Median (IQR))
25.00 [21.24, 27.81]
25.44 [21.94, 27.99]
73.93 [49.02, 139.30]
< 0.001
TyG index
8.24 ± 0.47
8.76 ± 0.62
8.61 ± 0.68
< 0.001
TyG-BMI index
225.79 ± 45.69
266.61 ± 57.53
250.33 ± 66.58
< 0.001
TyG-WC index
775.17 ± 127.98
901.63 ± 151.75
853.44 ± 175.40
< 0.001
TyG-WHtR index
4.47 ± 0.75
5.24 ± 0.91
5.12 ± 1.05
< 0.001
Diabetes (n,%)
0 (0.0)
59 (13.1)
2305 (16.6)
< 0.001
Hypertension (n,%)
0 (0.0)
220 (48.7)
5592 (40.2)
< 0.001
Dyslipidemia(n,%)
0 (0.0)
299 (66.2)
4509 (32.4)
< 0.001
HF-related mortality (n,%)
0 (0.0)
2 (0.4)
174 (31.6)
0.016
Follow_up (years)
8.63 ± 4.03
8.95 ± 3.67
7.66 ± 3.93
< 0.001
BMI: Body mass index (weight [kg] / height2 [m2]); WC: Waist circumference; SBP: Systolic blood pressure; DBP: Diastolic blood pressure; FBG: Fasting blood glucose; 
HbA1c: Glycosylated hemoglobin; TC: Total cholesterol; TG: Triglyceride; HDL-C: High-density lipoprotein cholesterol; LDL-C: Low-density lipoprotein cholesterol; 
TyG: ln [TG (mg/dL) × fasting glucose (mg/dL)/2]; TyG-BMI: TyG × BMI; TyG-WC: TyG × WC (cm); TyG-WHtR: TyG × [WC (cm)/height (cm)]; ACR: Urine albumin-to-
creatinine ratio; HF: Heart failure
Data are presented as mean ± standard deviation (SD), number (%), or median (interquartile range). Normally distributed variables were compared using one-way 
ANOVA, while non-normally distributed variables were compared using the Kruskal–Wallis test. Categorical variables were compared using the χ2 test or Fisher’s 
exact test, as appropriate. Bonferroni correction was applied for multiple comparisons. A two-sided P value < 0.05 was considered statistically significant

# Page 8

Page 8 of 18
Jin et al. Cardiovascular Diabetology          (2026) 25:145 
with HF-related mortality, whereas TyG–BMI showed no 
significant association in unadjusted survival analyses.
To investigate the link between TyG and its related 
indicators with HF-related mortality, this study con­
structed three Cox proportional hazards regression 
models (Table  3). When TyG, TyG-BMI, TyG-WC and 
TyG-WHtR were examined as continuous variables, each 
1-SD increase in TyG was associated with a higher risk 
of HF-related mortality in the crude model (HR 1.47, 
95% CI 1.23–1.76, P < 0.001), and this link remained sig­
nificant in the fully adjusted model (HR 1.49, 95% CI 
1.05–2.12, P = 0.025). Similarly, higher levels of TyG–
BMI, TyG–WC, and TyG–WHtR were independently 
associated with increased HF-related mortality after full 
adjustment, with HRs per 1-SD increase of 3.39 (95% CI 
1.01–11.30), 2.27 (95% CI 1.29–4.00), and 2.94 (95% CI 
1.63–5.29) (all P < 0.05), respectively. In quartile-based 
analyses, compared with the lowest quartile(Q1), par­
ticipants in the highest quartile(Q4) of TyG–BMI, TyG–
WC, and TyG–WHtR had significantly higher risks of 
HF-related mortality in the fully adjusted model (HR 
2.15, 95% CI 1.06–4.36; HR 2.97, 95% CI 1.19–7.38; and 
HR 2.75, 95% CI 1.04–7.31, respectively; all P < 0.05). 
However, the association between TyG quartiles and HF-
related mortality was not statistically significant after 
multivariable adjustment.(P > 0.05). Further adjustment 
for CKM stage did not materially change the associations 
between TyG-related indices and HF-related mortality. 
The results remained statistically significant after includ­
ing CKM stage in the fully adjusted model (Model 4) 
(Table S3).
Nonlinear relationship between TyG-related indicators and 
HF-related mortality
To investigate the potential nonlinear link between TyG 
and TyG related indicators with HF-related mortality, 
Restricted Cubic Spline (RCS) model was employed for 
analysis. Restricted cubic spline analyses revealed signifi­
cant link between TyG, TyG–WC, and TyG–WHtR and 
HF-related mortality (all P for overall < 0.05, Fig. 4A, C, 
D); whereas the association for TyG–BMI was of bor­
derline significance (Fig. 4 B). No evidence of nonlinear­
ity was observed for any TyG-related index, indicating 
largely linear dose–response relationships (all P for 
non-linearity > 0.05).
Predictive performance of TyG and related indicators
Receiver operating characteristic (ROC) curve analysis 
revealed varying predictive capabilities of different TyG-
related indicators for HF-related mortality. Among these, 
TyG-WHtR displayed the highest discriminatory efficacy 
(AUC = 0.641), followed by TyG-WC (AUC = 0.622) and 
TyG (AUC = 0.612), while the predictive capability of the 
TyG-BMI index was relatively lower (AUC = 0.549), as 
illustrated in Fig.  5. The optimal cutoff points for TyG 
and related indices were determined using the Youden 
index. Corresponding sensitivity and specificity values 
are summarized in Table S4.
Mediating role of HbA1c in the relationship between TyG-
related indicators and HF-related mortality
 
The 
Bayesian 
mediation 
analysis 
demonstrated 
that HbA1c plays a notable intermediary role in the 
Table 2  Incidence rate of HF-related mortality (% or per 10,000 
person-year)
Variable
Participants
HF-
related 
mortality
Cumu­
lative 
incidence 
(%)
Per 10,000 
person-year 
(95% CI)
TyG
Q1
3708
25
0.67
9.34 
(6.05–13.79)
Q2
3708
47
1.27
16.31 
(11.99–21.69)
Q3
3707
42
1.13
14.34 
(10.33–19.38)
Q4
3707
62
1.67
20.79 
(15.94–26.66)
P for trend
< 0.001
TyG -BMI
Q1
3708
32
0.86
11.24 
(7.69–15.86)
Q2
3708
54
1.46
18.85 
(14.16–24.59)
Q3
3707
48
1.29
16.54 
(12.20–21.93)
Q4
3707
42
1.13
14.72 
(10.61–19.90)
P for trend
< 0.001
TyG -WC
Q1
3708
25
0.67
8.65 
(5.60–12.78)
Q2
3708
45
1.21
15.75 
(11.49–21.07)
Q3
3707
40
1.08
13.82 
(9.89–18.82)
Q4
3707
66
1.78
23.35 
(18.06–29.70)
P for trend
< 0.001
TyG -WHtR
Q1
3708
17
0.46
5.85 (3.41–9.36)
Q2
3708
41
1.11
14.11 
(10.13–19.15)
Q3
3707
52
1.40
18.33 
(13.69–24.04)
Q4
3707
66
1.78
23.42 
(18.11–29.80)
P for trend
< 0.001
Q1: The lowest quartile; Q4: The highest quartile; HF: Heart failure, CI: Confidence 
intervals; TyG: ln [TG (mg/dL) × fasting glucose (mg/dL)/2]; TyG-BMI: TyG × BMI; 
TyG-WC: TyG × WC (cm); TyG-WHtR: TyG × [WC (cm)/height (cm)]

# Page 9

Page 9 of 18
Jin et al. Cardiovascular Diabetology          (2026) 25:145 
relationship between TyG- related indicators and the 
HF-related mortality (Fig.  6). Specifically, TyG showed 
a significant overall effect (estimate = 0.5517, P < 0.001), 
consisting of a direct pathway (ADE = 0.2794, P = 0.0185) 
and an indirect pathway through HbA1c (ACME = 0.1522, 
P < 0.001), indicating that 28.7% of the total association 
was mediated by HbA1c (Fig. 6A). Regarding TyG-BMI, 
the total effect reached 0.0023 (P < 0.05), with direct 
and indirect effects of 0.0003 (P = 0.808), and 0.0014 
(P < 0.001), respectively, accounting for a mediation 
proportion of 15.2% (Fig.  6B). For TyG-WC, the global 
effect was estimated at 0.0021(P < 0.001), including a 
direct effect of 0.0014 and an indirect effect of 0.0005 
(both P < 0.05), with HbA1c mediating 26.0% of the effect 
(Fig. 6C). Additionally, TyG-WHtR exhibited a total effect 
of 0.4163 (P < 0.001), where HbA1c contributed a direct 
effect of 0.2940 and an indirect effect of 0.0849 (both 
P < 0.001), corresponding to a mediation rate of 21.0% 
(Fig. 6D). In summary, HbA1c explained roughly 15–30% 
of the observed associations between TyG-related indi­
ces and incident HF-related mortality. This supports the 
notion that abnormal glucose metabolism may be a key 
biological pathway linking insulin resistance to elevated 
HF-related mortality risk.
Subgroup analysis
Subgroup analyses showed that the associations 
between the TyG index and its related indices (TyG-
BMI, TyG-WC, and TyG-WHR) with the risk of 
HF–related mortality were largely consistent across 
clinically relevant subgroups (Fig.  7). A significant 
interaction with age was consistently observed across 
all TyG-related indices (all P for interaction < 0.001), 
with stronger associations in participants aged < 60 
years. For the TyG index, hypertension status also 
significantly modified the association (P for interac­
tion = 0.019), with a more pronounced effect among 
individuals without hypertension. No significant 
interactions were identified for gender, BMI, diabetes, 
smoking, or drinking. For TyG-BMI, the association 
was generally stable across subgroups, with a sig­
nificant interaction observed for age and a borderline 
Fig. 2  Feature selection based on Boruta and SHAP regression; A Feature selection process; B Evolution of Z-score values during screening. The horizontal 
axis displays the number of runs for each variable, whilst the vertical axis represents the Z-score for each variable. Green lines denote confirmed variables, 
and red ones signify variables rejected during model computation. C Distribution of SHAP values for each variable (swarm plot) D Variables ranked by 
mean absolute SHAP value (bar chart). Abbreviations: BMI: Weight (kg)/Height (m)2; WC: Waist circumference; SBP: Systolic blood pressure, DBP: Diastolic 
blood pressure; FBG: Fasting blood glucose; HbA1c: Glycosylated hemoglobin; TC: Total cholesterol; TG: Triglyceride; HDL-C: High-density lipoprotein 
cholesterol; LDL-C: Low-density lipoprotein cholesterol; TyG: ln [TG (mg/dL) × fasting glucose (mg/dL)/2]; TyG-BMI: TyG × BMI; TyG-WC: TyG × WC (cm); 
TyG-WHtR: TyG × [WC (cm)/height (cm)]; ACR: Urine creatinine-to-albumin ratio; HF: Heart failure

# Page 10

Page 10 of 18
Jin et al. Cardiovascular Diabetology          (2026) 25:145 
interaction for smoking (P for interaction = 0.049). 
TyG-WC and TyG-WHtR demonstrated additional 
effect modification by BMI, hypertension, and dia­
betes, while no interaction was observed for gender 
or drinking. Because no HF-related mortality events 
occurred in participants with CKM stage 0, subgroup 
analyses by CKM stage were limited to participants 
with stage 1 and stage 2. The associations between 
TyG-related indices and HF-related mortality were 
generally consistent across these CKM stage strata, 
and no significant interactions were observed (all P 
for interaction > 0.05). Overall, despite the presence 
of statistically significant interactions in subgroups, 
the direction of associations remained consistent, sup­
porting the robustness of the relationship between 
TyG-related indices and HF–related mortality.
TyG-related indices and HF-related mortality in competing 
risk analyses
 In Fine–Gray competing risk models accounting 
for non–HF-related mortality as a competing event, 
higher TyG-related indices were associated with an 
increased risk of HF-related mortality (Table 4). When 
analyzed as continuous variables, each 1 SD increase 
in TyG was associated with a higher risk of HF-related 
mortality in the unadjusted model (sHR 1.32, 95% CI 
1.13–1.54), and this association remained significant 
after full adjustment (sHR 1.40, 95% CI 1.05–1.86). 
Similarly, TyG–BMI showed a significant associa­
tion with HF-related mortality in the fully adjusted 
model (sHR 1.21, 95% CI 1.02–1.43). Strong and con­
sistent associations were observed for TyG–WC and 
TyG–WHtR, with fully adjusted sHRs of 1.46 (95% CI 
1.17–1.83) and 1.54 (95% CI 1.22–1.96), respectively. 
In quartile-based analyses, participants in the high­
est quartile(Q4) of TyG exhibited a higher crude risk 
of HF-related mortality compared with those in the 
lowest quartile(Q1); however, this association was 
attenuated after multivariable adjustment. In contrast, 
TyG–WC and TyG–WHtR demonstrated clearer dose–
response relationships. In the fully adjusted model, the 
highest quartiles of TyG–WC and TyG–WHtR were 
Fig. 3  Kaplan–Meier curves for TyG and its related indices with HF-related mortality; A TyG, B TyG-BMI, C TyG-WC, and D TyG-WHtR. Abbreviations: Q1: The 
lowest quartile; Q4: The highest quartile; HF: Heart failure, HR: Hazard ratio; CI: Confidence interval; SD: Standard deviation; TyG: ln [TG (mg/dL) × fasting 
glucose (mg/dL)/2]; TyG-BMI: TyG × BMI; TyG-WC: TyG × WC (cm); TyG-WHtR: TyG × [WC (cm)/height (cm)]

# Page 11

Page 11 of 18
Jin et al. Cardiovascular Diabetology          (2026) 25:145 
associated with significantly increased risks of HF-
related mortality (sHR 2.78, 95% CI 1.30–5.95 and sHR 
2.69, 95% CI 1.16–6.24, respectively), whereas quar­
tile-based associations for TyG–BMI did not reach sta­
tistical significance.
  
Sensitivity analysis: TyG-related indices and cardiovascular 
mortality
To further examine the robustness of the find­
ings, a sensitivity analysis was performed using 
cardiovascular mortality as the outcome. In the com­
peting risk analysis using the Fine–Gray model with 
non-cardiovascular death treated as a competing 
event, higher TyG index and TyG-related parameters 
remained significantly associated with an increased 
risk of cardiovascular mortality (Table S5). In the fully 
adjusted model (Model 3), each 1-SD increment in 
TyG, TyG-BMI, TyG-WC, and TyG-WHtR was asso­
ciated with a 26% (sHR 1.26, 95% CI 1.05–1.51), 18% 
(sHR 1.18, 95% CI 1.02–1.35), 22% (sHR 1.22, 95% 
CI 1.03–1.45), and 28% (sHR 1.28, 95% CI 1.08–1.52) 
higher risk of cardiovascular mortality, respectively. 
Similar trends were observed in the quartile analyses, 
with participants in the highest quartiles (Q4) showing 
significantly increased risks compared with those in 
Table 3  Associations of TyG-related indices with HF-related mortality in individuals with CKM stages 0–2: Cox proportional hazards 
models
Variable
Model 1
HR (95%CI)
P
Model 2
HR (95%CI)
Model 3
HR (95%CI)
P
P
TyG
TyG
(per 1 SD)
1.47(1.23–1.76)
< 0.001
1.29 (0.99–1.68)
0.064
1.49(1.05–2.12)
0.025
TyG
Quartile 1
Reference
Reference
Reference
Quartile 2
2.61 (1.30–5.25)
0.007
1.40 (0.69–2.84)
0.357
1.28 (0.58–2.80)
0.543
Quartile 3
2.56 (1.38–4.76)
0.003
1.19 (0.63–2.24)
0.591
1.25 (0.57–2.72)
0.579
Quartile 4
3.82 (2.04–7.16)
< 0.001
1.63 (0.85–3.12)
0.139
1.59 (0.68–3.68)
0.278
TyG-BMI
TyG-BMI
(per 1 SD)
1.20 (1.03–1.41)
0.021
1.24 (1.02–1.51)
0.034
3.39 (1.01–11.30)
0.048
TyG-BMI
Quartile 1
Reference
Reference
Reference
Quartile 2
2.17 (1.26–3.74)
0.005
1.35 (0.78–2.35)
0.287
1.60(0.83–3.09)
0.161
Quartile 3
2.01 (1.17–3.44)
0.011
1.32 (0.76–2.27)
0.321
1.68 (0.90–3.14)
0.103
Quartile 4
2.59 (1.43–4.70)
0.002
2.09 (1.15–3.80)
0.016
2.15 (1.06–4.36)
0.035
TyG-WC
TyG-WC
(per 1 SD)
1.48 (1.26–1.73)
< 0.001
1.33(1.08–1.65)
0.009
2.27 (1.29–4.00)
0.004
TyG-WC
Quartile 1
Reference
Reference
Reference
Quartile 2
2.64 (1.36–5.14)
0.004
1.42 (0.71–2.84)
0.319
1.72 (0.80–3.74)
0.168
Quartile 3
2.30 (1.27–4.16)
0.006
1.00 (0.55–1.83)
0.989
1.44 (0.69–3.02)
0.333
Quartile 4
4.52 (2.35–8.70)
< 0.001
2.19 (1.08–4.41)
0.029
2.97 (1.19–7.38)
0.020
TyG-WHtR
TyG-WHtR
(per 1 SD)
1.65 (1.43–1.91)
< 0.001
1.41 (1.14–1.75)
0.002
2.94 (1.63–5.29)
< 0.001
TyG-WHtR
Quartile 1
Reference
Reference
Reference
Quartile 2
2.37 (1.18–4.72)
0.015
1.05 (0.53–2.08)
0.880
1.34(0.62–2.91)
0.455
Quartile 3
3.65 (1.79–7.45)
< 0.001
1.35 (0.64–2.87)
0.434
2.05 (0.80–5.24)
0.135
Quartile 4
6.32 (3.23–12.40)
< 0.001
2.19 (1.04–4.59)
0.039
2.75 (1.04–7.31)
0.042
Model 1: Unadjusted
Model 2: Adjusted for gender and age
Model 3: Adjusted for gender, age, educational levels, race, SBP, smoking, drinking, TC, HDL-C, diabetes and dyslipidemia
Q1: The lowest quartile; Q4: The highest quartile; HF: Heart failure, HR: Hazard ratio; CI: Confidence interval; SD: Standard deviation; TyG: ln [TG (mg/dL) × fasting 
glucose (mg/dL) / 2]; TyG-BMI: TyG × BMI; TyG-WC: TyG × WC (cm); TyG-WHtR: TyG × [WC (cm)/height (cm)]; SBP: Systolic blood pressure, TC: Total cholesterol; HDL-C: 
High-density lipoprotein cholesterol; CKM: Cardiovascular-kidney-metabolic

# Page 12

Page 12 of 18
Jin et al. Cardiovascular Diabetology          (2026) 25:145 
the lowest quartiles(Q1). Overall, the sensitivity analy­
sis yielded results broadly consistent with the primary 
analyses, supporting the robustness of the observed 
associations.
Discussion
Using 
nationally 
representative 
data 
from 
the 
NHANES 2005–2018 cycles, this study evaluated the 
associations between the triglyceride–glucose (TyG) 
index and its related composite indicators (TyG-BMI, 
TyG-WC, and TyG-WHtR) with heart failure–related 
mortality among individuals with early-stage CKM 
syndrome (stages 0–2). Findings demonstrated that 
TyG and its related indices significantly increased 
with advancing CKM stages and were positively linked 
with the probability of heart failure–related mortal­
ity. This link remained robust even after adjusting 
for demographic, clinical, and metabolic variables. 
The best prediction ability for heart failure–related 
mortality was demonstrated by TyG-WHtR. Further­
more, according to Restricted Cubic Spline (RCS) 
analysis. TyG, TyG-WC, TyG-WHtR, and heart fail­
ure–related mortality was found to significant linear 
relationships; Mediator analysis further indicated that 
HbA1c partially mediated the link between TyG series 
indicators and heart failure–related mortality, suggest­
ing insulin resistance and related metabolic abnormal­
ities may promote heart failure development through 
impaired glucose metabolism. Subgroup analysis fur­
ther revealed that TyG and its related indicators were 
more significantly linked to the risk of heart failure–
related mortality. In addition, given that non–heart 
failure–related death represents a major competing 
event in individuals with early-stage CKM syndrome, 
competing risk analyses were performed to account for 
this possibility. The associations between TyG-related 
indices and heart failure–related mortality remained 
materially unchanged in Fine–Gray subdistribution 
Fig. 4  Restricted cubic spline curves illustrate the relationship between TyG-related indicators and HF-related mortality. A TyG, B TyG-BMI, C TyG-WC, and 
D TyG-WHtR. Solid lines denote adjusted hazard ratios derived from multivariate Cox models, with shaded areas representing 95% confidence intervals. 
Adjustments were made for gender, age, educational levels, race, SBP, smoking, drinking, TC, HDL-C, diabetes and dyslipidemia. Abbreviations: TyG: ln [TG 
(mg/dL) × fasting glucose (mg/dL)/2]; TyG-BMI: TyG × BMI; TyG-WC: TyG × WC (cm); TyG-WHtR: TyG × [WC (cm)/height (cm)]; SBP: Systolic blood pressure, 
TC: Total cholesterol; HDL-C: High-density lipoprotein cholesterol; HF: Heart failure

# Page 13

Page 13 of 18
Jin et al. Cardiovascular Diabetology          (2026) 25:145 
hazard models, supporting the robustness of the pri­
mary findings. These associations were observed in a 
population without advanced cardiovascular disease, 
underscoring the potential importance of metabolic 
dysfunction in shaping long-term heart failure–related 
outcomes at early CKM stages.
Given the strong association between TyG-related 
indices and CKM stages observed in the present study, 
we further examined whether these indices provide 
additional prognostic information beyond CKM stag­
ing. The results showed that TyG-related indices 
remained significantly associated with HF-related 
mortality even after further adjustment for CKM stage, 
suggesting that these indices may provide comple­
mentary metabolic risk information beyond the CKM 
staging framework. A potential explanation is that 
CKM stage represents a categorical classification of 
cardiometabolic risk, whereas TyG-related indices are 
continuous markers reflecting the severity of insulin 
resistance and metabolic dysfunction. As such, these 
indices may capture subtle metabolic heterogeneity 
within the same CKM stage that is not fully reflected 
by the staging system, thereby helping to refine risk 
stratification for HF-related mortality.
The TyG index is a surrogate marker reflecting insu­
lin resistance arising from disturbed glucose–lipid 
homeostasis. Insulin resistance is widely recognized 
as a central pathophysiological mechanism linking 
metabolic disorders to cardiovascular disease, includ­
ing heart failure [39, 40]. Persistent insulin resistance 
promotes myocardial lipid accumulation, mitochon­
drial dysfunction, impaired myocardial energetics, and 
adverse ventricular remodeling, ultimately contribut­
ing to both systolic and diastolic dysfunction [41]. Pre­
vious research had demonstrated that the TyG index 
is a valid measure of IR, closely linked to coronary 
heart disease, atherosclerosis, cardiovascular and cere­
brovascular mortality, and heart failure risk [42–44]. 
Our findings are consistent with prior studies report­
ing positive associations between elevated TyG levels 
Fig. 6  Mediating analysis of HbA1c in the relationship between TyG-related indicators and HF-related mortality; A TyG, B TyG-BMI, C TyG-WC, and D TyG-
WHtR. Abbreviations: TyG: ln [TG (mg/dL) × fasting glucose (mg/dL)/2]; TyG-BMI: TyG × BMI; TyG-WC: TyG × WC (cm); TyG-WHtR: TyG × [WC (cm)/height 
(cm)]; HF: Heart failure
 
Fig. 5  ROC curves for TyG-related indicators predicting the risk of HF-re­
lated mortality. Abbreviations: TyG: ln [TG (mg/dL) × fasting glucose (mg/
dL)/2]; TyG-BMI: TyG × BMI; TyG-WC: TyG × WC (cm); TyG-WHtR: TyG × [WC 
(cm)/height (cm)]; ROC: Receiver operating characteristic; HF: Heart failure

# Page 14

Page 14 of 18
Jin et al. Cardiovascular Diabetology          (2026) 25:145 
and cardiovascular events, including heart failure, and 
extend this evidence specifically to individuals in early 
CKM stages, a population that has received compara­
tively limited attention.
Furthermore, a more thorough representation of the 
combined metabolic abnormalities of insulin resistance 
and central obesity was provided by TyG-related indices, 
such as TyG-BMI, TyG-WC, and TyG-WHtR, which take 
into account body fat distribution or obesity markers [45, 
46]. This study found that TyG-WHtR demonstrated the 
highest predictive efficacy (AUC = 0.641) in forecasting 
heart failure–related mortality, supporting the concept 
that central fat distribution plays a particularly important 
role in early myocardial metabolic stress. Central obesity 
has been shown to exacerbate myocardial lipotoxicity, 
oxidative stress, and mitochondrial injury, thereby accel­
erating maladaptive cardiac remodeling even before clini­
cally overt cardiovascular disease becomes apparent [47].
Restricted cubic spline analyses further revealed lin­
ear relationships between TyG, TyG-WC, TyG-WHtR 
and heart failure–related mortality, suggesting that the 
adverse impact of metabolic dysregulation may accelerate 
beyond certain thresholds. This pattern implies that early 
metabolic compensation may initially buffer myocardial 
injury, whereas excessive insulin resistance and adiposity 
may overwhelm adaptive mechanisms, leading to a sharp 
increase in heart failure–related mortality, These findings 
underscore the potential value of early metabolic risk 
stratification rather than relying solely on traditional car­
diovascular risk factors.
To further explore potential mechanistic pathways, 
mediation analyses indicated that HbA1c partially 
mediated the association between TyG-related indices 
and heart failure–related mortality. This suggests that 
impaired glucose metabolism represents an important 
intermediate link between insulin resistance and heart 
failure progression [48]. Chronic hyperglycemia may 
aggravate myocardial dysfunction through advanced 
glycation end-product accumulation, oxidative stress, 
low-grade inflammation, and endothelial dysfunction, 
Fig. 7  . Subgroup analysis of the relationship between TyG and related indicators with HF-related mortality. A TyG, B TyG-BMI, C TyG-WC, and D TyG-WHtR

# Page 15

Page 15 of 18
Jin et al. Cardiovascular Diabetology          (2026) 25:145 
thereby contributing to structural and functional myo­
cardial impairment [49–51]. While these results do not 
establish causality, they provide supportive epidemiologi­
cal evidence for metabolic pathways implicated in heart 
failure–related mortality development [52].Likewise, the 
mediating analysis of HbA1c further supports the bridg­
ing function of impaired glucose metabolism between 
insulin resistance and heart failure–related mortality.
Subgroup analyses showed generally consistent asso­
ciations across clinically relevant strata, with stronger 
associations observed among males, individuals without 
diabetes or hypertension, and those with normal BMI. 
These findings suggest that TyG-related indices may be 
particularly informative for identifying metabolically 
vulnerable individuals who do not yet exhibit traditional 
cardiometabolic risk profiles, reinforcing their role as risk 
stratification markers rather than diagnostic or predictive 
tools.
To contextualize TyG-related indices within a broader 
risk framework, Boruta feature selection and SHAP 
analyses were applied as exploratory approaches. Age, 
anthropometric measures, and established glycaemic 
indicators emerged as dominant contributors to HF-
related mortality, consistent with the multifactorial 
nature of heart failure risk. TyG and its related compos­
ite indices were consistently retained as relevant features, 
although their relative importance was modest com­
pared with major demographic and clinical predictors. 
Table 4  TyG-related indices and HF-related mortality in competing risk analyses
Variable
Model 1
sHR (95%CI)
P
Model 2
sHR (95%CI)
P
Model 3
sHR (95%CI)
P
TyG
TyG
(per 1 SD)
1.32(1.13–1.54)
< 0.001
1.20 (0.97–1.48)
0.091
1.40(1.05–1.86)
0.021
TyG
Quartile 1
Reference
Reference
Reference
Quartile 2
1.74 (0.98–3.09)
0.060
1.04 (0.58–1.85)
0.910
1.11 (0.63–1.97)
0.710
Quartile 3
1.64 (0.92–2.91)
0.092
0.89 (0.50–1.58)
0.680
1.07 (0.59–1.94)
0.820
Quartile 4
2.25 (1.30–3.88)
0.004
1.21 (0.70–2.09)
0.510
1.42 (0.74–2.74)
0.290
TyG-BMI
TyG-BMI
(per 1 SD)
1.12 (0.97–1.30)
0.110
1.19 (1.00–1.41)
0.057
1.21 (1.02–1.43)
0.025
TyG-BMI
Quartile 1
Reference
Reference
Reference
Quartile 2
1.95 (1.15–3.31)
0.014
1.44 (0.85–2.44)
0.180
1.54(0.89–2.67)
0.120
Quartile 3
1.72 (1.01–2.94)
0.048
1.34 (0.78–2.29)
0.280
1.47 (0.81–2.65)
0.200
Quartile 4
1.62 (0.94–2.80)
0.082
1.51 (0.88–2.59)
0.130
1.70 (0.90–3.20)
0.100
TyG-WC
TyG-WC
(per 1 SD)
1.43 (1.24–1.65)
< 0.001
1.31(1.09–1.58)
0.005
1.46 (1.17–1.83)
< 0.001
TyG-WC
Quartile 1
Reference
Reference
Reference
Quartile 2
2.76 (1.40–5.44)
0.003
1.64 (0.83–3.23)
0.160
1.64 (0.81–3.31)
0.170
Quartile 3
2.69 (1.37–5.30)
0.004
1.37 (0.69–2.72)
0.370
1.59 (0.75–3.35)
0.220
Quartile 4
4.11 (2.15–7.86)
< 0.001
2.22 (1.15–4.32)
0.018
2.78 (1.30–5.95)
0.009
TyG-WHtR
TyG-WHtR
(per 1 SD)
1.56 (1.36–1.79)
< 0.001
1.37 (1.14–1.65)
< 0.001
1.54(1.22–1.96)
< 0.001
TyG-WHtR
Quartile 1
Reference
Reference
Reference
Quartile 2
2.90 (1.37–6.10)
0.005
1.42 (0.67–3.02)
0.360
1.57(0.73–3.39)
0.250
Quartile 3
4.08 (1.99–8.38)
< 0.001
1.76 (0.85–3.66)
0.130
2.14 (0.96–4.78)
0.063
Quartile 4
5.22 (2.58–10.58)
< 0.001
2.11 (1.03–4.33)
0.043
2.69 (1.16–6.24)
0.022
Model 1: Unadjusted
Model 2: Adjusted for gender and age
Model 3: Adjusted for gender, age, educational levels, race, SBP, smoking, drinking, TC, HDL-C, diabetes and dyslipidemia
 Q1: The lowest quartile; Q4: The highest quartile; HF: Heart failure, sHR: Subdistribution hazard ratios; CI: Confidence interval; SD: Standard deviation; TyG: ln [TG 
(mg/dL) × fasting glucose (mg/dL)/2]; TyG-BMI: TyG × BMI; TyG-WC: TyG × WC (cm); TyG-WHtR: TyG × [WC (cm)/height (cm)]; SBP: Systolic blood pressure; TC: Total 
cholesterol; HDL-C: High-density lipoprotein cholesterol

# Page 16

Page 16 of 18
Jin et al. Cardiovascular Diabetology          (2026) 25:145 
Importantly, SHAP analyses showed a directionally con­
sistent pattern, with higher TyG-related values associated 
with increased HF-related mortality risk, supporting the 
robustness of the associations observed in conventional 
regression and competing risk models. These results 
reinforce the interpretation that TyG-related indices 
function as independent but non-dominant metabolic 
risk markers, capturing insulin resistance–related vulner­
ability that may not be fully reflected by conventional risk 
factors in early-stage CKM populations.
Although insulin resistance–related markers have been 
extensively studied in relation to cardiometabolic out­
comes, the present study extends existing evidence in 
several important aspects. Prior NHANES-based stud­
ies have explored TyG in relation to heart failure risk or 
composite cardiovascular mortality but generally lacked 
focus on early-stage CKM populations and HF-specific 
mortality [53, 54]. Meta-analytic evidence also supports 
the prognostic value of TyG in heart failure populations 
more broadly [55], and systematic reviews suggest pre­
dictive relevance of TyG-WC for cardiovascular out­
comes [56]. In contrast, our analysis compares multiple 
TyG-related composite indices within a unified frame­
work and relates them specifically to HF-related mor­
tality, thereby providing outcome-specific prognostic 
insights in an understudied early CKM cohort.
By restricting the analysis to individuals with early-
stage CKM syndrome (stages 0–2), our study targets a 
clinically relevant population in whom metabolic abnor­
malities are often subclinical yet potentially modifiable. 
Moreover, rather than relying on composite cardiovas­
cular endpoints, we specifically evaluated heart failure–
related mortality, thereby providing outcome-specific 
prognostic information for a condition with distinct 
pathophysiology and clinical trajectories. In addition, 
we systematically compared multiple TyG-related com­
posite indices incorporating measures of central adipos­
ity within a unified analytical framework. This approach 
allowed assessment of their relative contributions beyond 
the traditional TyG index, addressing a gap in prior stud­
ies in which these indices were typically examined in 
isolation. The integration of conventional regression 
models with machine learning–based feature selection 
and SHAP interpretation situates TyG-related indices 
within a broader multivariable risk context, highlighting 
their role as independent but non-dominant metabolic 
risk markers rather than standalone predictors of heart 
failure–related mortality. To further ensure the robust­
ness of our findings, sensitivity analyses were conducted 
using cardiovascular mortality as an alternative outcome. 
Results from Fine–Gray subdistribution hazard mod­
els showed that the associations between TyG-related 
indices and mortality remained materially unchanged, 
complementing the insights from SHAP analyses and 
reinforcing the interpretation of TyG-related indices as 
independent yet non-dominant metabolic risk markers.
This study provides population-based evidence that 
TyG and its related indices are independently associated 
with HF-related mortality among individuals with CKM 
stages 0–2. Rather than serving as standalone predictive 
or diagnostic tools, these indices may function as acces­
sible metabolic risk markers that help identify individu­
als who could benefit from early lifestyle or metabolic 
interventions. However, some limitations remain, First, 
although NHANES-linked mortality data enable lon­
gitudinal outcome assessment, NHANES is not a con­
ventional prospective cohort, and residual confounding 
cannot be fully excluded. in particular, diet, physical 
activity, and detailed pharmacological treatments—espe­
cially glucose-lowering, lipid-lowering, and antihyperten­
sive therapies—were not included in the models, which 
may influence the interpretation of TyG-related asso­
ciations. Future prospective studies with more detailed 
lifestyle and medication data are warranted to further 
validate these findings. Second, heart failure is a het­
erogeneous clinical syndrome with diverse phenotypes 
and etiologies. The NHANES dataset does not allow 
differentiation of heart failure subtypes (e.g., HFrEF vs. 
HFpEF) or underlying etiologies. In addition, heart fail­
ure–related mortality was determined based on death 
certificate–derived cause-of-death information from the 
National Death Index, in which heart failure (ICD-10 
code I50) was recorded as the underlying cause of death. 
Although this approach has been widely used in prior 
NHANES-based epidemiological studies, misclassifica­
tion of cause-specific mortality cannot be completely 
excluded due to the complexity of death certificate coding 
and overlap among cardiovascular conditions. To miti­
gate potential bias, deaths from causes other than heart 
failure were treated as competing events and analyzed 
using competing risk models. Nevertheless, some resid­
ual misclassification may remain. Third, the analysis was 
restricted to NHANES cycles from 2005–2018 to ensure 
consistency in exposure definitions and CKM staging. 
Although NHANES mortality linkage is available from 
1999 onward, earlier cycles lacked complete or compa­
rable measurements for several key variables. Inclusion 
of these cycles would have necessitated extensive exclu­
sions and may have introduced additional selection bias. 
Nevertheless, this restriction may have reduced the over­
all sample size and limited the generalizability of the find­
ings to earlier survey periods. Meanwhile, CKM staging 
was derived from available NHANES variables and may 
not fully capture all components of the recently proposed 
CKM framework, particularly subclinical cardiovascular 
pathology. Therefore, the present findings are primarily 
applicable to individuals without subclinical or clinical 
cardiovascular disease and may not be generalizable to

# Page 17

Page 17 of 18
Jin et al. Cardiovascular Diabetology          (2026) 25:145 
those in CKM stage 3. Finally, metabolic biomarkers were 
measured at a single time point, precluding assessment of 
temporal changes. Future studies with adjudicated heart 
failure phenotypes, repeated metabolic assessments, and 
external validation cohorts are needed to further clarify 
causality and clinical applicability.
Conclusion
In this nationally representative study of adults with 
early-stage cardiovascular–kidney–metabolic syndrome 
(CKM stages 0–2), higher levels of TyG index and its 
related composite indicators were independently associ­
ated with an increased risk of heart failure–related mor­
tality. TyG-related indices incorporating anthropometric 
measures, particularly TyG-WHtR, showed stronger 
associations, underscoring the combined impact of insu­
lin resistance and central adiposity. The observed nonlin­
ear relationships and partial mediation by HbA1c suggest 
that impaired glucose metabolism may act as an interme­
diate pathway linking metabolic dysfunction to adverse 
heart failure–related outcomes. These findings support 
the potential utility of TyG-related indices as accessible 
metabolic risk markers for identifying vulnerable individ­
uals at early CKM stages.
Supplementary Information
The online version contains supplementary material available at ​h​t​t​p​s​:​/​/​d​o​i​.​o​r​
g​/​1​0​.​1​1​8​6​/​s​1​2​9​3​3​-​0​2​6​-​0​3​1​4​9​-​5.
Supplementary Material 1.
Acknowledgements
We deeply appreciative the editors and reviewers for their valuable time 
and constructive suggestions, which have been instrumental in improving 
the quality of this manuscript. We appreciate all of the participants and the 
NHANES team for providing valuable data and support for this study.
Author contributions
XQ, ZQ, LW and YL designed the experiments. XJ drafted the manuscript, 
analysed the data and generated the figures, YF, CL, TC, YJ, ZS, YB, HW and JL 
collected data. All authors have read and approved the final version of the 
manuscript.
Funding
Supported by the Tianjin Science and Technology Project(No.23JCYBJC01470), 
Tianjin Science and Technology Planning Project (No.16ZXMJSY00060) and the 
National International Science and Technology Cooperation Project of China 
(No. S2011ZR02601) .
Data availability
Publicly accessible data used in this investigation may be accessed at ​h​t​t​p​s​:​/​/​
w​w​w​.​c​d​c​.​g​o​v​/​n​c​h​s​/​n​h​a​n​e​s​/​.​
Declarations
Ethics approval and consent to participate
This research is based on data from the National Health and Nutrition 
Examination Survey (NHANES), which received approval from the Institutional 
Review Board of the National Center for Health Statistics (NCHS). All 
participants enrolled in the survey provided written informed permission prior 
to data collection. The investigation strictly followed the ethical principles 
outlined in the Declaration of Helsinki throughout all procedures.
Competing interests
The authors declare no competing interests.
Author details
1School of Medicine, Nankai University, Tianjin, People’s Republic of China
2Department of Molecular Pharmacology, School of Medicine, Nankai 
University, Tianjin, People’s Republic of China
3Department of Cardiology, Tianjin Union Medical Center, The First 
Affiliated Hospital of Nankai University, Nankai University, Tianjin, People’s 
Republic of China
Received: 19 January 2026 / Accepted: 9 March 2026
References
1.	
Bozkurt B, Coats AJS, Tsutsui H, et al. Universal definition and classification 
of heart failure: a report of the heart failure society of America, Heart failure 
association of the european society of cardiology, Japanese heart failure 
society and writing committee of the universal definition of heart failure: 
endorsed by the canadian heart failure society, Heart failure association 
of India, Cardiac society of Australia and New Zealand, and Chinese Heart 
Failure Association. Eur J Heart Fail. 2021;23(3):352–80.
2.	
Heidenreich PA, Bozkurt B. 2022 AHA/ACC/HFSA guideline for the manage­
ment of heart failure: executive summary: a report of the American college 
of cardiology/American heart association joint committee on clinical practice 
guidelines. Circulation. 2022;145(18):e876–94.
3.	
GBD 2021 diseases and injuries collaborators. Global incidence, prevalence, 
years lived with disability (YLDs), disability-adjusted life-years (DALYs), and 
healthy life expectancy (HALE) for 371 diseases and injuries in 204 countries 
and territories and 811 subnational locations, 1990–2021: a systematic analy­
sis for the global burden of disease study 2021. Lancet (London, England). 
2024, 403(10440): 2133–2161.
4.	
McDonagh T A, Metra M, Adamo M, et al. 2021 ESC guidelines for the 
diagnosis and treatment of acute and chronic heart failure. Eur Heart J. 
2021;42(36):3599–726.
5.	
Marassi M, Fadini GP. The cardio-renal-metabolic connection: a review of the 
evidence. Cardiovasc Diabetol. 2023;22(1):195.
6.	
Ndumele CE, Rangaswami J, Chow SL, et al. Cardiovascular-kidney-metabolic 
health: a presidential advisory from the American heart association. Circula­
tion. 2023;148(20):1606–35.
7.	
Khan SS, Coresh J, Pencina M J, et al. Novel prediction equations for absolute 
risk assessment of total cardiovascular disease incorporating cardiovascular-
kidney-metabolic health: a scientific statement from the American heart 
association. Circulation. 2023;148(24):1982–2004.
8.	
Chen Y, Lian W. Joint association of estimated glucose disposal rate and 
systemic inflammation response index with mortality in cardiovascular-kid­
ney-metabolic syndrome stage 0–3: a nationwide prospective cohort study. 
Cardiovasc Diabetol. 2025;24(1):147.
9.	
Liu Q, Zhang Y, Chen S, et al. Association of the triglyceride-glucose index 
with all-cause and cardiovascular mortality in patients with cardiometabolic 
syndrome: a national cohort study. Cardiovasc Diabetol. 2024;23(1):80.
10.	 Xia X, Chen S, Tian X, et al. Association of triglyceride-glucose index 
and its related parameters with atherosclerotic cardiovascular disease: 
evidence from a 15-year follow-up of Kailuan cohort. Cardiovasc Diabetol. 
2024;23(1):208.
11.	 Rafiee H, Mohammadifard N, Nouri F, et al. Association of triglyceride glucose 
index with cardiovascular events: insights from the Isfahan Cohort Study 
(ICS). Eur J Med Res. 2024;29(1):135.
12.	 Liu L, Sun H. Association between triglyceride-glucose index and cardiovas­
cular disease in US adults with chronic kidney disease: a population-based 
study. BMC Cardiovasc Disord. 2024;24:723.
13.	 Qiao Y, Wang Y, Chen C, et al. Association between triglyceride-glucose (TyG) 
related indices and cardiovascular diseases and mortality among individuals 
with metabolic dysfunction-associated steatotic liver disease: a cohort study 
of UK Biobank. Cardiovasc Diabetol. 2025;24(1):12.

# Page 18

Page 18 of 18
Jin et al. Cardiovascular Diabetology          (2026) 25:145 
14.	 Qiu J, Li J, Xu S, et al. Triglyceride glucose-weight-adjusted waist index as a 
cardiovascular mortality predictor: incremental value beyond the establish­
ment of TyG-related indices. Cardiovasc Diabetol. 2025;24(1):306.
15.	 Wei X, Min Y, Song G, et al. Association between triglyceride-glucose related 
indices with the all-cause and cause-specific mortality among the popula­
tion with metabolic syndrome. Cardiovasc Diabetol. 2024;23:134.
16.	 Yadegar A, Mohammadi F, Seifouri K, et al. Surrogate markers of insulin 
resistance and coronary artery disease in type 2 diabetes: U-shaped TyG 
association and insights from machine learning integration. Lipids Health Dis. 
2025;24:96.
17.	 Hong J, Zhang R, Tang H, et al. Comparison of triglyceride glucose index and 
modified triglyceride glucose indices in predicting cardiovascular diseases 
incidence among populations with cardiovascular-kidney-metabolic 
syndrome stages 0–3: a nationwide prospective cohort study. Cardiovasc 
Diabetol. 2025;24:98.
18.	 Du M, Chen L, Li Y, et al. Association between sedentary behavior, physical 
activity, and the triglyceride glucose index and its derived indices: evidence 
from NHANES 2013–2018. J Exerc Sci Fit. 2025;23(4):451–61.
19.	 Patel CJ, Pho N, Mcduffie M, et al. A database of human exposomes and 
phenomes from the US national health and nutrition examination survey. Sci 
Data. 2016;3:160096.
20.	 Zhang P, Mo D. Association between triglyceride-glucose related indices 
and all-cause and cardiovascular mortality among the population with 
cardiovascular-kidney-metabolic syndrome stage 0–3: a cohort study. Cardio­
vasc Diabetol. 2025;24:92.
21.	 Ndumele CE, Neeland IJ, Tuttle KR, et al. A synopsis of the evidence for the 
science and clinical management of cardiovascular-kidney-metabolic (CKM) 
syndrome: a scientific statement from the American heart association. Circu­
lation. 2023;148(20):1636–64.
22.	 Liu K, Hu J, Huang Y, et al. Triglyceride-glucose-related indices and risk of 
cardiovascular disease and mortality in individuals with cardiovascular–kid­
ney–metabolic (CKM) syndrome stages 0–3: a prospective cohort study of 
282,920 participants in the UK Biobank. Cardiovasc Diabetol. 2025;24:277.
23.	 Yue Y, Li P, Sun Z, et al. Association of novel triglyceride-glucose-related 
indices with incident stroke in early-stage cardiovascular-kidney-metabolic 
syndrome. Cardiovasc Diabetol. 2025;24:301.
24.	 Wang M, Gao B, Huang F. Association between the triglyceride glucose-
Chinese visceral adiposity index and new-onset stroke risk: a national cohort 
study. Cardiovasc Diabetol. 2025;24(1):119.
25.	 Zhang H, Tu Z, Liu S, et al. Association of different insulin resistance surro­
gates with all-cause and cardiovascular mortality among the population with 
cardiometabolic multimorbidity. Cardiovasc Diabetol. 2025;24(1):33.
26.	 Jin X, Liu Y, Jia W, et al. Association between systemic immune-inflammatory 
indices and severity of coronary artery lesions in patients with coro­
nary artery disease in different glucose metabolic states. J Inflamm Res. 
2025;18:3295–309.
27.	 Duo H, Zhao S, Zhao Y, et al. Association between life’s essential 8 scores 
and heart failure: insights from NHANES (2007–2020). Rev Cardiovasc Med. 
2025;26(9):39464.
28.	 Zheng H, Yin Z, Luo X, et al. Associations between systemic immunity-inflam­
mation index and heart failure: evidence from the NHANES 1999–2018. Int J 
Cardiol. 2024;395:131400.
29.	 Alva M, Dolman S, Sikirica S, et al. Prevalence and mortality rate of heart fail­
ure across demographic groups in the United States: 2001–2020. Am Heart J 
Plus: Cardiol Res Pract. 2025;60:100658.
30.	 Chen L, Zhong J, Niu Y, et al. Association of dietary choline intake with 
incidence of frailty: a nationwide prospective cohort study from China. J 
Cachexia Sarcopenia Muscle. 2025;16(2):e13796.
31.	 Zhang Y, Song K, Bi S, et al. Higher remnant cholesterol increases the risk 
of coronary heart disease and diabetes in postmenopausal women. Front 
Endocrinol. 2024;15:1475933.
32.	 Guo F, Garvey WT. Trends in cardiovascular health metrics in obese adults: 
national health and nutrition examination survey (NHANES), 1988–2014. J 
Am Heart Association. 2016;5(7):e003619.
33.	 Zhang Q, Xiao S. The triglyceride-glucose index is a predictor for cardiovas­
cular and all-cause mortality in CVD patients with diabetes or pre-diabetes: 
evidence from NHANES 2001–2018. Cardiovasc Diabetol. 2023;22:279.
34.	 Dang K, Wang X. The association between triglyceride-glucose index and its 
combination with obesity indicators and cardiovascular disease: NHANES 
2003–2018. Cardiovasc Diabetol. 2024;23:8.
35.	 Kursa MB. Rudnicki WR. Feature selection with the boruta package. J Stat 
Softw. 2010;36:1–13.
36.	 Chen Y, Jia W, Guo J, et al. Association between the C-reactive protein-
triglyceride glucose index and new-onset coronary heart disease among 
metabolically heterogeneous individuals. Cardiovasc Diabetol. 2025;24:316.
37.	 Lundberg SM, Lee SI. A unified approach to interpreting model predictions. 
Advances in neural information processing systems: vol 30. Curran Associ­
ates, Inc.; 2017.
38.	 Hsu W, Ko A, Weng C, et al. Explainable machine learning model for predict­
ing skeletal muscle loss during surgery and adjuvant chemotherapy in 
ovarian cancer. J Cachexia Sarcopenia Muscle. 2023;14(5):2044–53.
39.	 Chauhan A, Gupta A, Goyal P, et al. Serum levels of activin A: marker of insulin 
resistance and cardiovascular risk in prediabetics. J Family Med Prim Care. 
2022;11(10):5983–9.
40.	 Fahed G, Aoun L, Bou Zerdan M, et al. Metabolic syndrome: updates on 
pathophysiology and management in 2021. Int J Mol Sci. 2022;23(2):786.
41.	 Islam MS, Wei P, Suzauddula M, et al. The interplay of factors in metabolic 
syndrome: understanding its roots and complexity. Vol. 30(1). Molecular 
Medicine (Cambridge, Mass.); 2024. pp. 279.
42.	 Zhu F, Gan W. Association between the triglyceride-glucose index and major 
adverse cardiovascular events in patients with chronic kidney disease stages 
3–4. Sci Rep. 2025;15:28538.
43.	 Li ZF, Yin Z, Li X, et al. Effect of changes in the triglyceride-glucose index 
on atherogenic lipid profiles in coronary artery disease patients receiving 
lipid-lowering therapy: a prospective cohort study. Cardiovasc Diabetol. 
2025;24:372.
44.	 Tang H, Wang K, Zheng K, et al. The triglyceride-glucose index: updating 
evidence from clinical settings to molecular mechanisms in ageing-related 
cerebrovascular diseases. Cardiovasc Diabetol. 2025;24:350.
45.	 Fan Y, Ye D, Zhou K, et al. The novel triglyceride–glucose-weighted adjusted 
waist index as a supplementary diagnostic tool for heart failure: evidence of 
improved reclassification beyond traditional TyG-related indices from a cross-
sectional study. Cardiovasc Diabetol. 2025;24:329.
46.	 Yadegar A, Mohammadi F, Aghayan SN et al. Association of non-insulin-based 
markers of insulin resistance with hypertension in type 2 diabetes: an age- 
and gender-matched cross-sectional study. Am J Hypertens. 2025: hpaf237.
47.	 Duarte GBS, Pascoal G de FL, Rogero MM. Polymorphisms involved in insulin 
resistance and metabolic inflammation: influence of nutrients and dietary 
interventions. Metabolites. 2025;15(4):245.
48.	 Ramos-Lopez O, Riezu-Boj JI, Milagro FI, et al. Interplay of an obesity-based 
genetic risk score with dietary and endocrine factors on insulin resistance. 
Nutrients. 2019;12(1):33.
49.	 Jin Y, Ji Y, Song Y, et al. Depletion of adipocyte Becn1 leads to lipodystrophy 
and metabolic dysregulation. Diabetes. 2021;70(1):182–95.
50.	 Domingo E, Marques P. Targeting systemic inflammation in metabolic disor­
ders. A therapeutic candidate for the prevention of cardiovascular diseases? 
Pharmacol Res. 2024;200:107058.
51.	 Fan Y, Yan Z, Li T, et al. Primordial drivers of diabetes heart disease: 
comprehensive insights into insulin resistance. Diabetes Metabolism J. 
2024;48(1):19–36.
52.	 Tian J, Chen H, Luo Y, et al. Association between estimated glucose disposal 
rate and prediction of cardiovascular disease risk among individuals with 
cardiovascular-kidney-metabolic syndrome stage 0–3: a nationwide prospec­
tive cohort study. Diabetol Metab Syndr. 2025;17(1):58.
53.	 Khalaji A, Behnoush AH, Khanmohammadi S, et al. Triglyceride-glucose index 
and heart failure: a systematic review and meta-analysis. Cardiovasc Diabetol. 
2023;22(1):244.
54.	 Zhang F, Hou X. Association between the triglyceride glucose index and 
heart failure: NHANES 2007–2018. Front Endocrinol. 2024;14:1322445.
55.	 Cai Y, Yang M. A meta-analysis of the prognostic value of the TyG index in 
heart failure. Front Endocrinol. 2025;16:1463647.
56.	 Rabiee Rad M, Ghasempour Dabaghi G, Sadri H, et al. Triglyceride glucose-
waist circumference as a predictor of mortality and subtypes of cardiovas­
cular disease: a systematic review and meta-analysis. Diabetol Metab Syndr. 
2025;17(1):59.
Publisher’s note
Springer Nature remains neutral with regard to jurisdictional claims in 
published maps and institutional affiliations.
