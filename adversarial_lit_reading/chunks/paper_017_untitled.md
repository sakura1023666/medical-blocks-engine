# Page 1

RESEARCH
Open Access
© The Author(s) 2024. Open Access  This article is licensed under a Creative Commons Attribution-NonCommercial-NoDerivatives 4.0 
International License, which permits any non-commercial use, sharing, distribution and reproduction in any medium or format, as long as you 
give appropriate credit to the original author(s) and the source, provide a link to the Creative Commons licence, and indicate if you modified the 
licensed material. You do not have permission under this licence to share adapted material derived from this article or parts of it. The images or 
other third party material in this article are included in the article’s Creative Commons licence, unless indicated otherwise in a credit line to the 
material. If material is not included in the article’s Creative Commons licence and your intended use is not permitted by statutory regulation or 
exceeds the permitted use, you will need to obtain permission directly from the copyright holder. To view a copy of this licence, visit ​h​t​t​p​:​/​/​c​r​e​a​t​i​
v​e​c​o​m​m​o​n​s​.​o​r​g​/​l​i​c​e​n​s​e​s​/​b​y​-​n​c​-​n​d​/​4​.​0​/​.​
Zhang et al. Journal of Translational Medicine           (2025) 23:16 
https://doi.org/10.1186/s12967-024-05975-1
Journal of Translational 
Medicine
*Correspondence:
Wei Hu
huwei@hospital.westlake.edu.cn
Mengyuan Diao
diaomengyuan@hospital.westlake.edu.cn
Full list of author information is available at the end of the article
Abstract
Introduction  Cardiac arrest (CA), characterized by its heterogeneity, poses challenges in patient management. This 
study aimed to identify clinical subphenotypes in CA patients to aid in patient classification, prognosis assessment, 
and treatment decision-making.
Methods  For this study, comprehensive data were extracted from the Medical Information Mart for Intensive Care 
IV (MIMIC-IV) 2.0 database. We excluded patients under 18 years old, those not initially admitted to the intensive 
care unit (ICU), or treated in the ICU for less than 72 h. A total of 57 clinical parameters relevant to CA patients were 
selected for analysis. These included demographic data, vital signs, and laboratory parameters. After an extensive 
literature review and expert consultations, key factors such as temperature (T), sodium (Na), creatinine (CR), glucose 
(GLU), heart rate (HR), PaO2/FiO2 ratio (P/F), hemoglobin (HB), mean arterial pressure (MAP), platelets (PLT), and white 
blood cell count (WBC) were identified as the most significant for cluster analysis. Consensus cluster analysis was 
utilized to examine the mean values of these routine clinical parameters within the first 24 h post-ICU admission 
to categorize patient classes. Furthermore, in-hospital and 28-day mortality rates of patients across different CA 
subphenotypes were assessed using multivariate logistic and Cox regression analysis.
Results  After applying exclusion criteria, 719 CA patients were included in the study, with a median age of 
67.22 years (IQR: 55.50-79.34), of whom 63.28% were male. The analysis delineated two distinct subphenotypes: 
Subphenotype 1 (SP1) and Subphenotype 2 (SP2). Compared to SP1, patients in SP2 exhibited significantly higher 
levels of P/F, HB, MAP, PLT, and Na, but lower levels of T, HR, GLU, WBC, and CR. SP2 patients had a notably higher 
in-hospital mortality rate compared to SP1 (53.01% for SP2 vs. 39.36% for SP1, P < 0.001). 28-day mortality decreased 
continuously for both subphenotypes, with a more rapid decline in SP2. These differences remained significant 
after adjusting for potential covariates (adjusted OR = 1.82, 95% CI: 1.26–2.64, P = 0.002; HR = 1.84, 95% CI: 1.40–2.41, 
P < 0.001).
Machine learning derivation of two cardiac 
arrest subphenotypes with distinct responses 
to treatment
Weidong Zhang1, Chenxi Wu1, Peifeng Ni2, Sheng Zhang3, Hongwei Zhang4, Ying Zhu1,4, Wei Hu1,4* and 
Mengyuan Diao1,4*

# Page 2

Page 2 of 12
Zhang et al. Journal of Translational Medicine           (2025) 23:16 
Introduction
The latest statistics from the American Heart Associa­
tion (AHA) indicate that the incidence of out-of-hospital 
cardiac arrest (OHCA) stands at 140.7 cases per 100,000 
population, while in-hospital cardiac arrest (IHCA) 
occurs at a rate of 17.16 cases per 1,000 hospitalized 
patients [1]. Cardiac arrest (CA) is a significant health 
concern, causing nearly 370,000 deaths annually in the 
United States [1] and almost 1 million deaths each year 
in China [2]. These numbers have been rising, especially 
in the period following the COVID-19 pandemic [1]. The 
high mortality rate associated with CA is largely attrib­
uted to its heterogeneity, making the identification of 
specific CA subphenotypes critical for the development 
of precise and effective treatment plans.
Now, there remains ambiguity about the various 
terms created to classify and study CA, and consen­
sus documents from various cardiovascular societies 
characterize them distinctively [3–5]. North American 
(American Heart Association/Heart Rhythm Society/
American Council of Cardiology), European (European 
Heart Society), and Asian-Pacific (Asia-Pacific Heart 
Rhythm Society) all have unique definitions of CA [6]. 
They differed in whether the emphasis is placed on tim­
ing, etiology, or situational context surrounding the car­
diac arrest. However, the above-mentioned traditional 
classification methods inevitably have the following prob­
lems: (1) Unable to accurately reflect the pathophysiolog­
ical state: The pathophysiological state of each patient 
after CA can be significantly different, but these classifi­
cation criteria do not accurately reflect these differences; 
(2) Inability to provide effective support for treatment 
decisions: Different types of cardiac arrest require differ­
ent treatment strategies. The above classification meth­
ods ignore individual differences and cannot provide 
enough clinical information to guide treatment. There­
fore, this study focused on the above two issues, hoping 
to use a new tool to derive a new clinical classification 
method for CA patients. This classification method does 
not rely on external factors such as timing, etiology, 
or situational context surrounding the CA, but uses 
demographic variables, severity scores, comorbidities, 
vital signs, laboratory parameters, medication, and spe­
cial treatments to depict the high-latitude stereoscopic 
characteristics of each CA patient, and uses computer 
tools to classify them in high-latitude digital space. This 
classification method is based on the pathophysiological 
state of CA patients, which can evaluate the prognosis of 
patients and help with clinical treatment decisions.
The machine learning (ML) classifier model has 
become one of the most indispensable tools in modern 
medical research for identifying various disease sub­
phenotypes. Among them, consensus cluster analysis is 
a suitable clustering method that has been widely used 
to identify sepsis [7] and acute respiratory distress syn­
drome (ARDS) subphenotypes [8]. Until the initiation of 
this study, the application of similar methods for identify­
ing clinical subphenotype models in CA patients had not 
been widely explored by researchers. This study sought 
to develop a consensus cluster analysis approach to iden­
tify clinical subphenotypes of CA patients based on data 
collected within 24 h of admission to the intensive care 
unit (ICU). This methodology aims to assist clinicians in 
classifying and assessing the prognosis of CA patients, 
thereby enabling the potential for early warning and pre­
cise interventions for CA in the future.
Methods
Data source
All the data were extracted from the Medical Infor­
mation Mart for Intensive Care IV (MIMIC-IV) 2.0 
database, which contained all medical record num­
bers corresponding to patients admitted to the ICU or 
emergency department between 2008 and 2019 in the 
Beth Israel Deaconess Medical Center (BIDMC). Access 
to the database was granted following the completion 
of NIH-required online training by one of the authors 
(Mengyuan Diao, with certification ID: 1630201). The 
Institutional Review Board (IRB) at BIDMC provided a 
waiver for informed consent and approved the use of this 
resource for research purposes. Consequently, the study 
was conducted using publicly available and anonymized 
data, negating the need for individual patient consent.
Study population and outcome
In this study, patients who experienced CA were included 
as research participants, regardless of the cause of the 
arrest. However, the study excluded patients who were 
under 18 years of age, as well as those who were either 
initially admitted to the ICU or treated in the ICU for less 
than 72 h. A flow diagram detailing the study design and 
participant selection is presented in Fig. 1. The primary 
Conclusions  The study successfully identified two distinct clinical subphenotypes of CA by analyzing routine clinical 
data from the first 24 h following ICU admission. SP1 was characterized by a lower rate of in-hospital and 28-day 
mortality when compared to SP2. This differentiation could play a crucial role in tailoring patient care, assessing 
prognosis, and guiding more targeted treatment strategies for CA patients.
Keywords  Cardiac arrest, Machine learning, Subphenotypes, Precision medicine, Critically illness, Latent class analysis, 
Mortality

# Page 3

Page 3 of 12
Zhang et al. Journal of Translational Medicine           (2025) 23:16 
outcome measured in the study was in-hospital mortal­
ity, while the secondary outcome focused on the 28-day 
mortality.
Data extraction and variable selection
The extracted data for this study encompassed a com­
prehensive range of parameters including demographic 
variables, severity scores, comorbidities, vital signs, 
laboratory parameters, medication, and special treat­
ments. The demographic variables considered were age, 
race, sex, and body mass index (BMI). Comorbidities 
included in the data were hypertension, heart failure, 
cerebral infarction, chronic obstructive pulmonary dis­
ease (COPD), cirrhosis of the liver, chronic kidney dis­
ease, malignant cancer, diabetes, myocardial infarction, 
arrhythmia, coronary heart disease, and cardiomyopa­
thy. Vital signs incorporated into the study were heart 
rate (HR), systolic blood pressure (SBP), diastolic blood 
pressure (DBP), mean arterial pressure (MAP), respira­
tory rate (RR), temperature (T), PaO2/FiO2(P/F), SPO2, 
and total input and output values. Laboratory param­
eters consisted of hemoglobin (HB), platelets (PLT), 
white blood cells (WBC), bicarbonate, chloride, creati­
nine (CR), glucose (GLU), sodium (Na), potassium, bili­
rubin, pH levels, PO2, PCO2, international normalized 
ratio (INR), base excess (BE), alanine aminotransferase 
(ALT), aspartate transaminase (AST), blood urea nitro­
gen (BUN), and lactate (LAC). Severity scoring included 
the Charlson score and the Sequential Organ Failure 
Assessment (SOFA) score. The medications considered 
were vasoactive drugs, antiarrhythmics, glucocorticoids, 
and sodium bicarbonate. Special treatments accounted 
for were positive end-expiratory pressure (PEEP), percu­
taneous transluminal coronary intervention (PCI), extra­
corporeal membrane oxygenation (ECMO), continuous 
renal replacement therapy (CRRT), intra-aortic balloon 
pump (IABP), and mechanical ventilation. All these 
parameters were average values within the first 24 h post-
ICU admission, except for input and output, which were 
cumulative totals within the same timeframe.
For feature selection, variables with a missing fraction 
exceeding 30% were excluded. Data were imputed with 
the use of multiple imputation for variables that were 
missing by less than 30%. The proportion of missing data 
is detailed in supplementary Fig. 1 (sFigure 1). Selection 
of variables was informed by prior literature and their 
potential association with the onset and progression of 
CA, as identified through literature review and expert 
discussions. The final variables chosen for consensus 
cluster analysis included T, Na, CR, GLU, HR, P/F, HB, 
MAP, PLT, and WBC. The consensus clustering analysis 
utilized the k-means clustering method as its internal 
algorithm, with each variable representing a different 
physiological system or function. Correlations between 
the selected parameters were generally low, as indicated 
in supplementary Fig. 2 (sFigure 2), with the highest cor­
relation observed between HB and MAP (r = 0.4).
Subphenotype classification
In this study, consensus cluster analysis was employed to 
identify clinical subphenotypes of CA in ICU patients. 
The analysis utilized a pre-defined subsampling param­
eter set at 80%, with 50 iterations. The potential num­
ber of clusters (k) was limited to a range from 2 to 6, 
Fig. 1  Flow chart of patient selection. Ultimately, 719 patients with cardiac arrest (CA) from the intensive care unit (ICU) were enrolled in this study
MIMIC-IV, Medical Information Mart for Intensive Care-IV; ICU, intensive care unit; CA, cardiac arrest

# Page 4

Page 4 of 12
Zhang et al. Journal of Translational Medicine           (2025) 23:16 
ensuring that the number of clusters remained clinically 
manageable and relevant. The optimal number of clus­
ters was determined through a comprehensive examina­
tion of various metrics. These included the consensus 
matrix (CM) heat map, the cumulative distribution func­
tion (CDF), and cluster-consensus plots that focused 
on within-cluster consensus scores. The proportion of 
ambiguously clustered pairs (PAC) and the Bayesian 
information criterion (BIC) also played a crucial role in 
this determination. The within-cluster consensus score, 
which varies between 0 and 1, represented the average 
consensus value for all pairs of individuals within the 
same cluster. A score closer to 1 indicated greater sta­
bility and homogeneity within that cluster. PAC, calcu­
lated in the range of 0 to 0.9, measured the proportion 
of sample pairs with consensus values within pre-set 
boundaries. A lower PAC value signified improved clus­
ter stability. Lastly, the BIC, ranging between 20,000 and 
20,500, served as a criterion for the selection of the num­
ber of clusters, with lower BIC values indicating a more 
parsimonious model.
Statistical analysis
Statistical analyses in this study were conducted using the 
R software tool, version 4.1.2. After the CA patients clus­
ters were identified, the differences between these clus­
ters were analyzed. Measurement data were represented 
as medians with their interquartile ranges (IQR), and 
the nonparametric rank sum test was used to compare 
these measurements across different groups. Counting 
data, such as frequencies, were expressed in percent­
ages, and the Chi-square test was employed to compare 
these frequencies between groups. For multivariable 
logistic regression, four distinct models were developed, 
each adjusted for different confounding variables. Model 
1 served as the baseline with no adjustments. Model 2 
included adjustments from Model 1, plus factors such as 
age and sex. Model 3 built upon Model 2 by also adjust­
ing for the Charlson score. Finally, Model 4 included all 
adjustments from Model 3, with the addition of the SOFA 
score. The odds ratios (ORs) and their 95% confidence 
intervals (CIs) were calculated using logistic regression to 
assess the prognosis for different patient classes. In this 
analysis, a p-value of less than 0.05 (two-tailed) was con­
sidered to indicate statistical significance.
Fig. 2  (A) Consensus matrix legend. (B) Consensus matrix (k = 2). (C) Consensus matrix (k = 3). (D) Consensus matrix (k = 4). (E) Consensus matrix (k = 5). 
(F) Consensus matrix (k = 6)

# Page 5

Page 5 of 12
Zhang et al. Journal of Translational Medicine           (2025) 23:16 
Results
Characteristics of the cohorts
In this study, a total of 76,540 ICU patients from the 
MIMIC-IV database were initially considered. After 
applying the exclusion criteria, 719 patients who experi­
enced CA were ultimately enrolled. The patient cohort in 
this study had a median age of 67.2 years, with an inter­
quartile range (IQR) of 55.5 to 79.3 years. Among these 
patients, 63.2% (455 out of 719) were male. The racial 
demographics were predominantly white (389/719, 
54.1%), followed by black (81/719, 11.2%), and oth­
ers (249/719, 34.6%). The most common comorbidities 
among the patients were hypertension (489/719, 68.0%), 
heart failure (265/719, 36.8%), and chronic kidney disease 
(176/719, 24.4%). These demographic details are further 
outlined in Table 1.
Regarding treatments within the first 24  h post-ICU 
admission, a significant proportion of the patients 
received vasoactive drugs (74.4%, 535/719), and nearly all 
were put on ventilation on the first day (99.0%, 712/719). 
Additionally, 29.7% (214/719) received antiarrhythmic 
drugs, and 29.2% (210/719) were administered sodium 
bicarbonate during the same period. The median Sequen­
tial Organ Failure Assessment (SOFA) score across the 
patient cohort was 7 (IQR: 4–9), indicative of a generally 
severe level of illness among these patients.
Among 
included 
patients, 
74.4%(535/719) 
were 
administered vasoactive agents dose within 24 h of ICU 
admission, 99.0%(712/719) received mechanical ventila­
tion, 29.7%(214/719) were given antiarrhythmic agents 
dose, and 29.2%(210/719) were treated with sodium 
bicarbonate. Across the dataset, Charlson score had a 
median score of 6 (IQR: 4–8), indicating a high risk of 
comorbidity.
Derivation of two subphenotypes
The CDF plot (sFigure 3A) shows the consensus distri­
butions for each cluster, where the curve had negligible 
variation when k = 2. The relative change in the area 
under the CDF curve is shown in the delta plot (sFigure 
3B), revealing significant differences in area when k = 3 
or 4, indicating the relative increased area became con­
siderably small. The mean cluster consensus score was 
comparable between a scenario of two clusters (sFigure 
3C), and the two clusters showed favorably low PACs by 
the criteria (take [0, 0.9] as the predetermined boundary, 
sFigure 3D). Then, we computed the optimal BIC values 
using Least Common Ancestors analysis (LCA), which 
was found to be minimum (20100) when k = 2, indicat­
ing the model reached the optimal clustering number 
(sFigure 4). The consensus matrix (CM) heatmap (Fig. 2) 
shows that consensus cluster analysis identifies clusters 2 
and 4 with clear boundaries, indicating good cluster sta­
bility over repeated iterations.
Through consensus clustering analysis, two distinct 
patient groups emerged from the parameters of CA 
patients within the first 24  h of their admission to the 
ICU. For simplicity, we referred to the two classes as 
subphenotype 1 (SP1) and subphenotype 2 (SP2), fol­
lowed by creating 2D images using t-distributed stochas­
tic neighbor embedding (t-SNE) to mark the differences 
between before and after clustering (Fig.  3A) for easier 
exploration and visualization of two subphenotypes. 
Abnormal clinical variables of the two subphenotypes are 
shown in Fig. 4.
Characteristics of two subphenotypes
Patients within both subphenotypes were of similar age. 
Among those with SP1, 57.6% were males. These patients 
also had lower Charlson Comorbidity Index and SOFA 
scores, and they required fewer vasoactive drugs and 
CRRT. In terms of laboratory parameters, patients in 
SP1 exhibited elevated levels of HB, Bicarbonate, Chlo­
ride, pH, PO2, and BE, contrasted with diminished levels 
of Potassium, Bilirubin, INR, and LAC. Similarly, 73.8% 
were male in SP2. However, patients in SP2 showed 
higher PEEP and a higher comorbidities burden. In addi­
tion, SP2 patients demonstrated elevated GLU, BUN, 
ALT and AST levels (Table 1). The distinct variables of 
both subphenotypes are depicted in Fig. 3B. In compari­
son to SP2, SP1 is distinguished by markedly higher levels 
of P/F, HB, MAP, PLT and Na, alongside lower values of 
T, HR, GLU, WBC and CR.
Clinical outcomes of two subphenotypes
As shown in Fig. 5A, SP1 had a lower proportion of in-
hospital mortality than SP2, where KM survival curves 
showed that SP1 had a lower 28-day mortality than 
SP2 (P < 0.001) (Fig.  5B). The univariate model 1 was 
adjusted three times by including different parameters 
and analyzed using multivariate logistic and COX regres­
sion analysis, respectively. Results showed that in either 
model, the in-hospital mortality (OR = 1.82, 95% CI: 
1.26–2.64, p = 0.002) and 28-day mortality (HR = 1.84, 
95% CI: 1.40–2.41, p < 0.001) of SP2 patients were higher 
than SP1 (Table 2).
We also analyzed the relationship between different 
vital signs and mortality (Table  3), and results showed 
that patients with MAP ≥ 65mmHg had lower mor­
tality than those with MAP < 65mmHg, independent 
of a whole group or in SP1 or SP2 individually. The in-
hospital mortality and 28-day mortality of SP1 patients 
with temperature 32 ∼ 36℃ were lower than those with 
temperature 36 ∼ 37.5℃(OR = 2.91, 95% Cl: 1.46–5.78], 
HR = 2.37 [95% Cl: 1.52–3.69]). However, the analyses for 
SP2 patients were not significantly different for patients 
with temperature 36–37.5  °C and others. In the whole 
cohort, patients also tended to have a lower mortality

# Page 6

Page 6 of 12
Zhang et al. Journal of Translational Medicine           (2025) 23:16 
Variables
Total (n = 719)
Subphenotype 1 (n = 470)
Subphenotype 2 (n = 249)
p
statistic
Demographic variables
Age
67.221 (55.509, 79.34)
66.695 (54.815, 79.3)
67.594 (56.261, 79.337)
0.478
-0.71
Sex, male
455 (63.282)
271 (57.66)
184 (73.896)
< 0.001
17.774
Race, n (%)
0.207
3.152
  black
81 (11.266)
46 (9.787)
35 (14.056)
  white
389 (54.103)
256 (54.468)
133 (53.414)
  other
249 (34.631)
168 (35.745)
81 (32.53)
BMI
27.758 (24.504, 32.162)
27.618 (24.07, 31.867)
28.395 (25.381, 33.333)
0.014
-2.469
Comorbidities
Hypertension, n (%)
489 (68.011)
305 (64.894)
184 (73.896)
0.017
5.656
Heart failure, n (%)
265 (36.857)
154 (32.766)
111 (44.578)
0.002
9.258
Cerebral infarction, n (%)
80 (11.127)
56 (11.915)
24 (9.639)
0.424
0.638
COPD, n (%)
114 (15.855)
79 (16.809)
35 (14.056)
0.393
0.729
Cirrhosis of liver, n (%)
27 (3.755)
10 (2.128)
17 (6.827)
0.003
8.689
Chronic kidney disease, n (%)
176 (24.478)
48 (10.213)
128 (51.406)
< 0.001
147.182
Malignant cancer, n (%)
75 (10.431)
43 (9.149)
32 (12.851)
0.156
2.008
Diabetes, n (%)
236 (32.823)
130 (27.66)
106 (42.57)
< 0.001
15.743
Myocardial infarction, n (%)
213 (29.624)
122 (25.957)
91 (36.546)
0.004
8.253
Arrhythmia, n (%)
600 (83.449)
392 (83.404)
208 (83.534)
1
< 0.001
Coronary heart disease, n (%)
347 (48.261)
213 (45.319)
134 (53.815)
0.037
4.371
Cardiomyopathy, n (%)
72 (10.014)
47 (10)
25 (10.04)
1
< 0.001
Severity scores
Charlson score
6 (4, 8)
5 (4, 7)
7 (5, 9)
< 0.001
-7.15
SOFA
7 (4, 9)
5 (3, 8)
9 (7, 11)
< 0.001
-12.41
Vital signs
Temperature
36.746 (36.234, 37.154)
36.763 (36.236, 37.175)
36.714 (36.24, 37.097)
0.838
0.204
Heart rate
81.88 (70.212, 95.651)
80.58 (68.613, 92.982)
84.22 (72.958, 99.438)
0.002
-3.141
Respiratory rate
20.122 (17.565, 23.575)
19.561 (17.101, 22.645)
21.379 (18.293, 24.875)
< 0.001
-4.143
MAP
78.219 (71.845, 84.728)
79.321 (72.876, 86.13)
74.852 (69.609, 82.232)
< 0.001
4.938
SBP
112.4 (105.069, 122.858)
113.19 (106.026, 124.572)
110.417 (103.409, 119.333)
0.001
3.198
DBP
62.692 (55.506, 69.929)
63.698 (57.122, 71.012)
60.097 (53.821, 68.5)
0.001
3.417
PaO2/FiO2
229.3 (145.7, 333.6)
249.9 (164, 356.4)
181.4 (120.2, 265.3)
< 0.001
6.39
spo2
98 (96.37, 99.197)
98.217 (96.767, 99.396)
97.484 (95.783, 98.889)
< 0.001
4.36
Input
6000 (3395, 9620)
5940 (3400, 9199.25)
6250 (3280, 10720)
0.269
-1.106
Output
1847 (1015.5, 3094)
2178.5 (1391, 3416.5)
1125 (502, 2125)
< 0.001
9.62
Laboratory parameters
Hemoglobin
11 (9.4, 13.115)
11.5 (9.79, 13.388)
10.3 (8.65, 12.35)
< 0.001
5.384
WBC
13.05 (9.31, 17.45)
12.49 (9.232, 16.488)
14.8 (9.7, 19.1)
0.001
-3.303
Platelets
183.5 (138.07, 245.29)
194 (144, 248.625)
170 (125.25, 236.67)
0.001
3.209
INR
1.3 (1.15, 1.6)
1.25 (1.105, 1.465)
1.47 (1.2, 1.85)
< 0.001
-7.203
ALT
73 (32, 188.75)
63 (31, 163)
96.5 (38, 309)
< 0.001
-3.947
AST
129.5 (48, 307)
106 (45.5, 243)
182 (56.2, 448)
< 0.001
-4.345
Bilirubin
0.6 (0.4, 1.14)
0.6 (0.377, 0.95)
0.7 (0.4, 1.55)
< 0.001
-3.556
BUN
23.75 (16.708, 36.5)
19 (14.5, 24.65)
42 (29.5, 60)
< 0.001
-17.587
Creatinine
1.2 (0.83, 1.99)
0.95 (0.732, 1.2)
2.46 (1.93, 3.6)
< 0.001
-21.701
Glucose
153.6 (123.5, 201.25)
149.585 (122, 190.188)
161.2 (128.5, 224.4)
0.001
-3.282
Sodium
139 (136.5, 141.67)
139.33 (137.05, 141.95)
138.5 (135.33, 141)
0.001
3.317
Potassium
4.13 (3.85, 4.55)
4.05 (3.8, 4.358)
4.45 (4, 4.95)
< 0.001
-7.971
Chloride
105.33 (101.55, 108.5)
106 (103, 109.75)
103 (98.5, 107)
< 0.001
7.085
pH
7.35 (7.3, 7.4)
7.36 (7.31, 7.4)
7.32 (7.27, 7.38)
< 0.001
5.087
po2
122 (86.8, 164.105)
132 (94.082, 173.31)
106.29 (76.21, 143)
< 0.001
5.206
pco2
39 (34.805, 43.84)
39 (34.842, 43.53)
39.33 (34.78, 44.36)
0.875
-0.157
Bicarbonate
21.25 (18.5, 24)
22 (19.25, 24.5)
20 (16.75, 23)
< 0.001
5.425
Table 1  Baseline characteristics between different Subphenotypes (median [Q1, Q3]/ n [%])

# Page 7

Page 7 of 12
Zhang et al. Journal of Translational Medicine           (2025) 23:16 
rate when PO2 ≥ 80mmHg. Nevertheless, PO2 ≥ 80mmHg 
showed the opposite outcome in SP2 as in SP1. Similarly, 
compared to patients with PCO2 < 35mmHg, those with 
35mmHg ≤ PCO2 ≤ 45mmHg or PCO2 ≥ 45mmHg had 
lower mortality, independent of a whole group or in SP1 
or SP2.
Discussion
In medicine, subphenotype and disease stage are two dis­
tinct concepts that can sometimes be difficult to distin­
guish. Is it possible that the discrimination that is being 
observed simply reflects two different stages of progres­
sion rather than separate clusters? Let me begin with 
our answer - “NO”. The two subphenotypes that have 
been identified are clearly not two stages of CA progres­
sion, but rather refer to a group of CA patients who are 
further subdivided according to different characteristics 
or responses. The stages of CA progression can include 
prodromal phase, onset phase, CA phase, and biological 
death phase. The subphenotypes identified in this study 
are certainly in one of these stages of development, but 
it is more of a coexisting condition. The identification 
of subphenotypes usually relies on in-depth analysis of 
patient clinical characteristics (such as symptoms and 
signs) and biomarkers (such as specific molecules in 
blood and urine). These features and markers can help 
physicians classify patients into subgroups with similar 
Fig. 3  (A) T-distributed stochastic neighbor embedding (t-SNE) plot. This nonlinear dimension reduction technique is used to visualize high-latitude data. 
(B) Selected variables by subphenotype in CA and the differences in the standardized values of each variable by subphenotype. All continuous variables 
were transformed into z-scores (mean: 0, standard deviation: −1 to 1)
WBC, white blood cell count; MAP, mean arterial pressure
 
Variables
Total (n = 719)
Subphenotype 1 (n = 470)
Subphenotype 2 (n = 249)
p
statistic
Base excess
-3 (-5.895, -0.15)
-2.29 (-4.8, 0)
-4.57 (-8, -0.75)
< 0.001
5.418
Lactate
2.4 (1.655, 3.8)
2.2 (1.6, 3.475)
2.929 (1.8, 5.142)
< 0.001
-4.975
Medication
Vasoactive, n (%)
535 (74.409)
327 (69.574)
208 (83.534)
< 0.001
15.932
Antiarrhythmic, n (%)
214 (29.764)
143 (30.426)
71 (28.514)
0.654
0.2
Glucocorticoids, n (%)
26 (3.616)
21 (4.468)
5 (2.008)
0.141
2.164
Sodium bicarbonate, n (%)
210 (29.207)
100 (21.277)
110 (44.177)
< 0.001
40.182
Special treatments
PEEP
5.96 (5, 9.38)
5.535 (5, 8.552)
7.57 (5.18, 10.32)
< 0.001
-4.911
PCI, n (%)
38 (5.285)
26 (5.532)
12 (4.819)
0.817
0.053
ECOM, n (%)
16 (2.225)
12 (2.553)
4 (1.606)
0.58
0.306
CRRT, n (%)
93 (12.935)
25 (5.319)
68 (27.309)
< 0.001
67.952
IABP, n (%)
38 (5.285)
20 (4.255)
18 (7.229)
0.128
2.312
Ventilation, n (%)
712 (99.026)
466 (99.149)
246 (98.795)
0.698
Fisher
Continuous variables were reported as medians (interquartile range [IQR]), categorical variables as count (percentage [%]). Abbreviations: BMI, body mass index; 
WBC, white blood cell; INR, international normalized ratio; ALT, alanine aminotransferase; AST, aspartate transaminase; BUN, blood urea nitrogen; SBP, systolic 
blood pressure; DBP, diastolic blood pressure; MAP, mean arterial pressure; PEEP, positiveend-expiratorypressure; SOFA, sequential organ failure assessment; PCI, 
percutaneous transluminal coronary intervention; ECMO, extracorporeal membrane oxygenation; CRRT, continuous renal replacement therapy; IABP, intra-aortic 
ballon pump; COPD, chronic obstructive pulmonary disease
Table 1  (continued)

# Page 8

Page 8 of 12
Zhang et al. Journal of Translational Medicine           (2025) 23:16 
Table 2  The associations of subphenotype and outcomes
Hospital mortality
28-day mortality
OR
95%CI
P
HR
95%CI
P
Model 1
Subphenotype 1
Ref
Ref
Subphenotype 2
1.73
1.27–2.37
< 0.001
1.59
1.28–1.99
< 0.001
Model 2
Subphenotype 1
Ref
Ref
Subphenotype 2
1.83
1.33–2.52
< 0.001
1.64
1.31–2.05
< 0.001
Model 3
Subphenotype 1
Ref
Ref
Subphenotype 2
1.79
1.28–2.50
< 0.001
1.74
1.37–2.20
< 0.001
Model 4
Subphenotype 1
Ref
Ref
Subphenotype 2
1.82
1.26–2.64
0.002
1.84
1.40–2.41
< 0.001
Fig. 5  (A) Hospital mortality among different subphenotypes of ICU patients with CA. (B) 28-day mortality among different subphenotypes of ICU 
patients with CA
 
Fig. 4  Chord diagram showing abnormal clinical variables by suphenotype. In (A), the ribbons connect an individual subphenotype to an organ or 
system if the group mean is greater or less than the overall mean for the entire cohort. For example, subphenotype 1 (light blue) is more likely to have 
patients with acid–base imbalance (the ribbons connect to these portions of the circle) than patients with subphenotype 2 (light red), who are more 
likely to have cardiovascular, pulmonary, and hepatic dysfunction. In (B) and (C), each subphenotype is highlighted separately, and the ribbons connect 
to different patterns of clinical variables and organ or system dysfunctions located at the top of the circle

# Page 9

Page 9 of 12
Zhang et al. Journal of Translational Medicine           (2025) 23:16 
pathophysiological mechanisms or different responses to 
therapy.
The analysis of CA patient data identified two distinct 
clinical subphenotypes, referred to as SP1 and SP2. This 
was achieved through the use of consensus cluster analy­
sis, employing a range of variables for the study, including 
T, Na, CR, GLU, HR, P/F, HB, MAP, PLT, and WBC. 
Results showed that both subphenotypes differed in sev­
eral dimensions, such as demographics, vital signs, labo­
ratory results, and organ dysfunction, which differs from 
how patients are grouped using traditional methods. 
Furthermore, we refined the parameters of the univariate 
Table 3  The associations of various vital signs and outcome in different populations
Hospital mortality
28-day mortality
OR
95%CI
P
HR
95%CI
P
The whole cohort
MAP
< 65 mmHg
Ref
Ref
≥ 65 mmHg
0.56
0.3–1.04
0.066
0.76
0.5–1.14
0.185
Temperature
32–36 ℃
Ref
Ref
36–37.5 ℃
2.73
1.56–4.77
< 0.001
2.13
1.52-3
< 0.001
other
1.35
0.88–2.06
0.166
1.33
0.98–1.81
0.068
PO2
< 80 mmHg
Ref
Ref
≥ 80 mmHg
0.86
0.56–1.33
0.509
0.85
0.62–1.15
0.293
PCO2
< 35 mmHg
Ref
Ref
35–45mmHg
0.46
0.3–0.69
< 0.001
0.61
0.46–0.8
< 0.001
≥ 45 mmHg
0.47
0.29–0.76
0.002
0.59
0.42–0.83
0.002
Subphenotype 1
MAP
< 65 mmHg
Ref
Ref
≥ 65 mmHg
0.62
0.25–1.53
0.302
0.78
0.41–1.51
0.467
Temperature
32–36 ℃
Ref
Ref
36–37.5 ℃
2.91
1.46–5.78
0.002
2.37
1.52–3.69
< 0.001
other
1.54
0.92–2.57
0.100
1.47
0.99–2.16
0.053
PO2
< 80 mmHg
Ref
Ref
≥ 80 mmHg
0.89
0.48–1.63
0.699
0.94
0.59–1.5
0.802
PCO2
< 35 mmHg
Ref
Ref
35–45 mmHg
0.37
0.22–0.63
< 0.001
0.54
0.38–0.78
0.001
≥ 45 mmHg
0.43
0.23–0.8
0.007
0.54
0.35–0.83
0.005
Subphenotype 2
MAP
< 65 mmHg
Ref
Ref
≥ 65 mmHg
0.58
0.23–1.43
0.233
0.82
0.48–1.4
0.461
Temperature
32–36 ℃
Ref
Ref
36–37.5 ℃
2.65
0.98–7.18
0.055
1.89
1.1–3.23
0.021
other
1.05
0.48–2.26
0.909
1.19
0.71–1.99
0.507
PO2
< 80 mmHg
Ref
Ref
≥ 80 mmHg
1.16
0.6–2.22
0.662
1.00
0.66–1.54
0.984
PCO2
< 35 mmHg
Ref
Ref
35–45 mmHg
0.71
0.36–1.37
0.306
0.74
0.49–1.12
0.153
≥ 45 mmHg
0.53
0.24–1.18
0.122
0.68
0.4–1.16
0.157

# Page 10

Page 10 of 12
Zhang et al. Journal of Translational Medicine           (2025) 23:16 
model on three separate occasions. It was consistently 
observed that patients categorized under the SP2 had 
higher in-hospital and 28-day mortality rates compared 
to those with the SP1. The findings of this study are antic­
ipated to serve as a vital reference for clinicians in clas­
sifying patients, assessing their prognosis, and making 
informed treatment decisions for CA patients.
ML has been widely used for classifying various disease 
subphenotypes, among which consensus cluster analy­
sis is one of the most popular ML clustering algorithms, 
and has been widely used for identifying subphenotypes 
of diseases such as ARDS [8], sepsis [9], septic acute kid­
ney injury (septic-AKI) [10], and liver dysfunction [11]. 
Under comprehensive consideration, consensus cluster 
analysis was selected for defining CA subphenotypes. CA 
subphenotypes can be determined after medical informa­
tion collection and routine examination of patients fol­
lowing their admission, which is helpful for the timing 
of advanced treatment intervention, flexible adjustment 
of treatment plans, and screening of clinical trial sub­
jects. After two critical care medicine experts discussed 
and reached a consensus, 52 relevant parameters were 
screened following the patient’s admission to the ICU. 
To avoid excessive confounding leading to decreased 
clinical utility, we selected the most representative 10 
parameters (T, Na, CR, GLU, HR, P/F, HB, MAP, PLT, 
and WBC) for cluster analysis. Only the mean values 
within 24 h after ICU admission were selected to achieve 
the early differentiation of clinical subphenotypes of CA 
patients. Although previous studies have shown that 
some new parameters can achieve considerable predic­
tion results, it wasn’t easy to carry out in practical clini­
cal work [8, 12]. To achieve the study objective, clinically 
available data was used in the cluster model and two sub­
phenotypes were derived. In these two phenotypes, SP2 
patients were most closely associated with abnormalities 
in organs or systems, notably including the cardiovascu­
lar and hematologic systems, as well as hepatic dysfunc­
tion. Conversely, SP1 patients exhibited considerably 
more favorable characteristics than SP2. Since the statis­
tical analysis showed that SP1 patients had overall fewer 
clinical anomalies despite a high proportion of acid-base 
imbalance, we may be able to classify patients with CA 
more quickly based on limited laboratory tests. The mul­
tiple cluster analyses showed consistency across clinical 
subphenotypes, which could help identify patients who 
would benefit from future intervention. Nonetheless, 
further understanding of the pathophysiological mecha­
nisms underlying CA subphenotypes is necessary.
Among the 10 most representative parameters, there 
were 5 parameters which were higher or lower than 
SP2 patients, respectively. Results showed that patients 
with SP2 had higher HR and lower MAP than those 
with SP1, in addition to significant history of underlying 
hypertension, heart failure, and a higher proportion 
of vasoactive drug use. A higher MAP within a specific 
range refers to better perfusion, leading to a better prog­
nosis. A study recently reported an insignificant dif­
ference in outcome between the MAP of patients with 
CA between 77mmHg and 63mmHg [13]. However, the 
grouping method used in above study was fundamen­
tally different from the subphenotypes classification 
method used in our study. Patients were grouped based 
on different target blood pressure in above study and ML 
was applied to cluster and classify patients under multi-
parameter conditions in our study, which could be the 
primary reason why the results of the two studies are par­
tially biased. Additionally, patients with potentially poor 
long-term outcomes were excluded from the sample. 
Hence, the influence of MAP on CA patients’ outcome 
remains to be determined. Na was used in this study as a 
representative of electrolytes. The Na levels in both sub­
phenotypes were similar and within the normal range but 
were slightly lower in SP2 patients than in SP1. More­
over, hypo- and hypernatremia were associated with a 
decreased probability of favorable neurological outcomes 
compared with normal Na [14]. It should also be noted 
that SP2 patients had lower Na even though they used 
sodium bicarbonate at a higher rate than SP1, suggest­
ing that Na in SP2 patients might be lower before the use 
of sodium bicarbonate, and the difference between the 
two groups may be more significant. The main function 
of PLT is coagulation and hemostasis, and they are often 
used to evaluate the coagulation function of patients in 
clinic. The PLT of two subphenotypes in this study was 
within the normal range but slightly reduced in SP2 than 
in SP1. According to the neurologic outcome at 6 months 
post-CA, patients with good prognosis had a mean PLT 
of 230.31*10^9/L at admission, and patients with poor 
prognosis had a mean PLT of 197.30*10^9/L at admission 
[15], which were similar to our results and end outcomes. 
P/F is an important indicator of respiratory function 
and is widely used to distinguish high-risk patients with 
adverse clinical outcomes [16]. Our results showed that 
SP2 patients had lower P/F than SP1, suggesting that SP2 
patients had poor respiratory function and more severe 
organ or tissue ischemia and hypoxia. Multiple factors 
could contribute to a lower P/F in CA patients, such as 
aspiration pneumonia, pulmonary embolism, systemic 
inflammatory reaction, pulmonary exudation, and ARDS, 
among which some were also common CA causes.
Furthermore, our results showed that patients with SP2 
had abnormally high levels of CR, while patients with SP1 
had normal levels of CR, which suggesting worse renal 
function in SP2 patients. Meanwhile, SP2 patients had 
a higher proportion of chronic kidney disease comor­
bidities. A decrease in CR of > 0.2 mg/dl in the first 24 h 
may indicate a good prognosis, while a constant or even

# Page 11

Page 11 of 12
Zhang et al. Journal of Translational Medicine           (2025) 23:16 
elevated serum CR level suggests a poor prognosis [17]. 
Excessively high GLU can lead to immunosuppression 
and oxidative stress, leading to poor patient outcomes. 
A study reported that higher GLU levels were associ­
ated with poor neurological outcomes in those patients 
with CA treated with targeted temperature management 
(TTM) [18]. Our data showed that SP2 patients had 
higher GLU than SP1. The statistical analysis revealed 
infection as the most significant difference between the 
two subphenotypes since SP2 patients had a higher WBC 
than SP1, indicating a severe infection. However, it could 
have happened before CA onset, or the infection could 
be the cause of CA. Furthermore, a study reported that 
WBC had no significant ability to distinguish infectio­
nin in CA patients receiving TTM [19]. Although WBC 
showed apparent difference between the two subphe­
notypes, but its reliability needs to be demonstrated by 
more clinical practice in the future. The temperature 
between the two subphenotypes not statistically signifi­
cant, which was related to the TTM commonly adopted 
in clinical practice. Despite some controversy, TTM at 
32–36 °C for at least 24 h post-CA remained the primary 
neuroprotective approach following OHCA or IHCA, 
consistent with AHA recommendations [20–22]. The 
results of COX and multivariate logistic analysis in this 
study showed that, in the whole population, the in-hos­
pital and 28-day mortality of patients with T of 32–36 °C 
were lower than those of 36–37.5 °C, which indicated the 
benifet of TTM for the prognosis of CA patients.
CA patients are classified into two subphenotypes (SP1 
and SP2) on the basis of different clinical features and 
physiological responses (on the basis of 10 vital signs and 
laboratory parameters that represent the pathophysi­
ology of CA). Compared with the previous classifica­
tion methods, these subphenotypes are more helpful for 
doctors to diagnose, treat and predict the prognosis of 
patients more accurately. The variables used for cluster­
ing can be obtained quickly after the patient is admitted 
to the hospital, so that clinicians can quickly identify the 
patient’s subphenotype (SP1 or SP2). Clinicians can then 
tailor treatment to patients on the basis of the patho­
physiological features of the subphenotypes that we have 
so far clustered. SP1 is more likely to have patients with 
acid–base imbalance than SP2 patients, who are more 
likely to have cardiovascular, pulmonary, and hepatic dys­
function. Therefore, attention to acid-base balance (e.g., 
an aggressive adjunctive CRRT strategy) is warranted 
beyond usual care in SP1 patients. For SP2 patients, we 
should be alert to the occurrence of multiple organ dys­
function syndrome (MODS). This may be because: 1. 
Poor basic organ function; 2. CA has a greater impact on 
the organs of patients. Active intra-aortic ballon pump 
(IABP), extracorporeal membrane oxygenation (ECMO) 
and artificial liver support system (ALSS) may be helpful 
for patients with organ support. In-hospital and 28-day 
mortality were lower with SP1 than with SP2. We can 
make a preliminary prognosis assessment of CA patients 
according to the classification of patients after admission. 
This can be used as a theoretical basis for prognosis pre­
diction in conversation with the patient’s family.
Translating theoretical research results into clinical 
practice is a significant challenge faced by the major­
ity of researchers. While previous studies found some 
critical factors in subphenotypes identification for ARDS 
and septic AKI, but these indicators have not been pop­
ularized because of the difficulty in extracting these 
indicators in clinical practice [8, 12, 23]. However, this 
challenge also exists in the classification of CA subphe­
notypes. Unlike previous research [12, 23], we used 10 
conventional clinical variables to derive clinical CA sub­
phenotypes, which were more straightforward and easier 
to obtain, and their values reflected the functional states 
of different systems or organs, making our cluster analy­
sis more representative and universal. In the future, we 
aimed to conduct an external multicenter validation to 
refine the underlying model.
This study had several limitations. Firstly, since CA 
causes are numerous and complex, using the currently 
known disease patterns to identify all subphenotypes 
might not be sufficient. We should examine the hetero­
geneity of CA from a higher latitude. This puts forward 
higher requirements for researchers’ ability to multi-
system joint thinking. Secondly, the two experts believed 
that age is an important factor affecting the survival rate 
of patients with CA since younger tends to mean fewer 
underlying diseases, stronger immunity, and a better 
prognosis. Considering that the potential influence of 
age on patients with CA is fundamental and multifac­
eted, this study was not temporarily included. Thirdly, 
including more potential variables, such as shock type 
and microbiological data et cetera could provide new 
insights. However, these were not present in the MINIC-
IV 2.0 database. Lastly, the variables for clinical subphe­
notypes in this study were derived from a single-center 
retrospective database in the United States. Therefore, 
whether these subphenotypes can be generalized to more 
diverse populations of severely ill patients with CA in 
other parts of the world remains to be seen. We would 
invest more time and energy to verify and adjust it fur­
ther. In the next few years, we planned to collect patients 
with CA information from multiple centers to establish 
the CA database of ICU patients in China.
Conclusions
Analysis of CA patients data retrieved from the MIMIC-
IV 2.0 database revealed two clinical subphenotypes of 
CA, namely SP1 and SP2. Consensus cluster analysis was 
performed using the mean values of clinical, vital signs,

# Page 12

Page 12 of 12
Zhang et al. Journal of Translational Medicine           (2025) 23:16 
and laboratory indicators as the analysis variables. The 
SP1 ad considerably higher levels of P/F, HB, MAP, PLT, 
and Na, and lower T, HR, GLU, WBC, and CR levels than 
SP2. The in-hospital and 28-day mortality of patients 
with SP2 was higher than patients with SP1. The study 
outcomes are envisaged to provide helpful information to 
the clinicians regarding patient classification, prognosis 
evaluation, and making treatment decisions for prospec­
tive CA patients.
Supplementary Information
The online version contains supplementary material available at ​h​t​t​p​s​:​/​/​d​o​i​.​o​r​
g​/​1​0​.​1​1​8​6​/​s​1​2​9​6​7​-​0​2​4​-​0​5​9​7​5​-​1​.​
Supplementary Material 1
Supplementary Material 2
Supplementary Material 3
Supplementary Material 4
Supplementary Material 5
Supplementary Material 6
Author contributions
The specifc division of labor was as follows: Conception, WZ; Funding, WH, and 
MD; Investigations, WZ; Methods, WZ, CW, and PN; Project management, SZ, 
HZ, and YZ.
Funding
1. Zhejiang Provincial Medical and Health Technology Project (grant. 
WKJ-ZJ-2315).
2. The Construction Fund of Key Medical Disciplines of Hangzhou 
(OO20200485).
3. Science and Technology Development Project of Hangzhou (grant. 
202204A10).
Declarations
Conflict of interest
The authors declare that there are no competing interests.
Author details
1Fourth Clinical Medical College of Zhejiang Chinese Medical University, 
Zhejiang 310006, Hangzhou, China
2Zhejiang University School of Medicine, Zhejiang 310006, Hangzhou, 
China
3Department of Critical Care Medicine, Ruijin Hospital, Shanghai Jiao Tong 
University School of Medicine, Shanghai 200000, China
4Department of Critical Care Medicine, Hangzhou First People’s Hospital, 
West Lake University School of Medicine, Zhejiang 310006, Hangzhou, 
China
Received: 24 February 2024 / Accepted: 13 December 2024
References
1.	
Tsao CW, et al. Heart disease and stroke statistics-2022 update: a report from 
the American Heart Association. Circulation. 2022;145(8):e153–639.
2.	
Gu XM, et al. Meta-analysis of the success rate of heartbeat recovery in 
patients with prehospital cardiac arrest in the past 40 years in China. Mil Med 
Res. 2020;7(1):34.
3.	
Al-Khatib SM, et al. 2017 AHA/ACC/HRS guideline for management of 
patients with ventricular arrhythmias and the prevention of sudden cardiac 
death: a report of the American College of Cardiology/American Heart 
Association Task Force on Clinical Practice Guidelines and the Heart Rhythm 
Society. Circulation. 2018;138(13):e272–391.
4.	
Priori SG et al. 2015 ESC guidelines for the management of patients with 
ventricular arrhythmias and the prevention of sudden cardiac death: the task 
force for the management of patients with ventricular arrhythmias and the 
prevention of sudden cardiac death of the European Society of Cardiology 
(ESC). Endorsed by: Association for European Paediatric and Congenital 
Cardiology (AEPC). Eur Heart J. 2015;36(41):2793–2867.
5.	
Stiles MK, et al. 2020 APHRS/HRS expert consensus statement on the inves­
tigation of decedents with sudden unexplained death and patients with 
sudden cardiac arrest, and of their families. Heart Rhythm. 2021;18(1):e1–50.
6.	
Elfassy MD, et al. Understanding etiologies of cardiac arrest: seeking defini­
tional clarity. Can J Cardiol. 2022;38(11):1715–8.
7.	
Seymour CW, et al. Derivation, validation, and potential treatment implica­
tions of novel clinical phenotypes for sepsis. JAMA. 2019;321(20):2003–17.
8.	
Maddali MV, et al. Validation and utility of ARDS subphenotypes identified by 
machine-learning models using clinical data: an observational, multicohort, 
retrospective analysis. Lancet Respir Med. 2022;10(4):367–77.
9.	
Hu C, et al. Application of machine learning for clinical subphenotype identi­
fication in sepsis. Infect Dis Ther. 2022;11(5):1949–64.
10.	 Chaudhary K, et al. Utilization of deep learning for subphenotype identi­
fication in sepsis-associated acute kidney injury. Clin J Am Soc Nephrol. 
2020;15(11):1557–65.
11.	 Miao H, et al. Identification of subphenotypes of sepsis-associated liver 
dysfunction using cluster analysis. Shock. 2023;59(3):368–74.
12.	 Wiersema R, et al. Two subphenotypes of septic acute kidney injury are 
associated with different 90-day mortality and renal recovery. Crit Care. 
2020;24(1):150.
13.	 Roedl K, Kluge S. Blood-pressure targets in comatose survivors of cardiac 
arrest. N Engl J Med. 2023;388(3):285.
14.	 Shida H, et al. Early prognostic impact of serum sodium level among out-of-
hospital cardiac arrest patients: a nationwide multicentre observational study 
in Japan (the JAAM-OHCA registry). Heart Vessels. 2022;37(7):1255–64.
15.	 Kim HJ, et al. Time course of platelet counts in relation to the neurologic 
outcome in patients undergoing targeted temperature management after 
cardiac arrest. Resuscitation. 2019;140:113–9.
16.	 Villar J, et al. A universal definition of ARDS: the PaO2/FiO2 ratio under a stan­
dard ventilatory setting–a prospective, multicenter validation study. Intensive 
Care Med. 2013;39(4):583–92.
17.	 Hasper D, et al. Changes in serum creatinine in the first 24 hours after 
cardiac arrest indicate prognosis: an observational cohort study. Crit Care. 
2009;13(5):R168.
18.	 Daviaud F, et al. Blood glucose level and outcome after cardiac arrest: 
insights from a large registry in the hypothermia era. Intensive Care Med. 
2014;40(6):855–62.
19.	 Schuetz P, et al. Serum procalcitonin, C-reactive protein and white blood 
cell levels following hypothermia after cardiac arrest: a retrospective cohort 
study. Eur J Clin Invest. 2010;40(4):376–81.
20.	 Andersen LW, et al. In-hospital cardiac arrest: a review. JAMA. 
2019;321(12):1200–10.
21.	 Mody P, et al. Targeted temperature management for cardiac arrest. Prog 
Cardiovasc Dis. 2019;62(3):272–8.
22.	 Sandroni C, et al. ERC-ESICM guidelines on temperature control after cardiac 
arrest in adults. Intensive Care Med. 2022;48(3):261–9.
23.	 Sinha P, et al. Development and validation of parsimonious algorithms to 
classify acute respiratory distress syndrome phenotypes: a secondary analysis 
of randomised controlled trials. Lancet Respir Med. 2020;8(3):247–57.
Publisher’s note
Springer Nature remains neutral with regard to jurisdictional claims in 
published maps and institutional affiliations.
