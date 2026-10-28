# Page 1

RESEARCH
Open Access
© The Author(s) 2024. Open Access  This article is licensed under a Creative Commons Attribution 4.0 International License, which permits use, 
sharing, adaptation, distribution and reproduction in any medium or format, as long as you give appropriate credit to the original author(s) and 
the source, provide a link to the Creative Commons licence, and indicate if changes were made. The images or other third party material in this 
article are included in the article’s Creative Commons licence, unless indicated otherwise in a credit line to the material. If material is not included 
in the article’s Creative Commons licence and your intended use is not permitted by statutory regulation or exceeds the permitted use, you will 
need to obtain permission directly from the copyright holder. To view a copy of this licence, visit http://creativecommons.org/licenses/by/4.0/. The 
Creative Commons Public Domain Dedication waiver (http://creativecommons.org/publicdomain/zero/1.0/) applies to the data made available 
in this article, unless otherwise stated in a credit line to the data.
Xu et al. Cardiovascular Diabetology          (2024) 23:212 
https://doi.org/10.1186/s12933-024-02251-w
Cardiovascular Diabetology
†Bin Xu and Qian Wu have contributed equally to this work.
*Correspondence:
Qian Wu
qianwujoint@163.com
Wenliang Che
chewenliang@tongji.edu.cn
Full list of author information is available at the end of the article
Abstract
Background  This study sought to elucidate the associations of cardiometabolic index (CMI), as a metabolism-related 
index, with all-cause and cardiovascular mortality among the older population. Utilizing data from the National Health 
and Nutrition Examination Survey (NHANES), we further explored the potential mediating effect of inflammation 
within these associations.
Methods  A cohort of 3029 participants aged over 65 years old, spanning six NHANES cycles from 2005 to 2016, was 
enrolled and assessed. The primary endpoints of the study included all-cause mortality and cardiovascular mortality 
utilizing data from National Center for Health Statistics (NCHS). Cox regression model and subgroup analysis were 
conducted to assess the associations of CMI with all-cause and cardiovascular mortality. The mediating effect of 
inflammation-related indicators including leukocyte, neutrophil, lymphocyte, systemic immune-inflammation index 
(SII), neutrophil to lymphocyte ratio (NLR) were evaluated to investigate the potential mechanism of the associations 
between CMI and mortality through mediation package in R 4.2.2.
Results  The mean CMI among the enrolled participants was 0.74±0.66, with an average age of 73.28±5.50 years. After 
an average follow-up period of 89.20 months, there were 1,015 instances of all-cause deaths and 348 cardiovascular 
deaths documented. In the multivariable-adjusted model, CMI was positively related to all-cause mortality (Hazard 
Ratio (HR)=1.11, 95% CI=1.01-1.21). Mediation analysis indicated that leukocytes and neutrophils mediated 6.6% and 
13.9% of the association of CMI with all-cause mortality.
Is systemic inflammation a missing 
link between cardiometabolic index 
with mortality? Evidence from a large 
population-based study
Bin Xu1,2†, Qian Wu3,4*†, Rui La3, Lingchen Lu5, Fuad A. Abdu1, Guoqing Yin1, Wen Zhang1, Wenquan Ding3, 
Yicheng Ling3, Zhiyuan He3 and Wenliang Che1*

# Page 2

Page 2 of 13
Xu et al. Cardiovascular Diabetology          (2024) 23:212 
Background
Cardiometabolic disease, initially conceptualized as a 
constellation of metabolic dysfunctions heightening the 
risk for cardiovascular disease (CVD) and diabetes melli­
tus (DM), stands as a principal cause of death and disabil­
ity globally [1]. Within the US, expenditures on CVD and 
DM healthcare have reached $89.3billion and $111.2bil­
lion respectively, ranking as the fourth and third high­
est healthcare costs and exerting considerable pressure 
on health care resources [2]. Besides, CVD and DM are 
highly prevalent health conditions in the older population 
[3]. In the US, the prevalence of CVD and DM are over 
78% for those aged>60 years and over 26.8% for those 
aged>65 years respectively [4, 6]. In 2019, CVD and DM 
were ranked first and fifth in leading factors that affect 
life span in age groups over 75 years [7]. Consequently, 
the identification of modifiable risk factors within the 
older population, especially in cardiometabolic disease, 
is imperative for the advancement of global public health 
and the formulation of preventive strategies.
The pathophysiology of CVD and DM is intricately 
linked to chronic inflammation, which is implicated in 
the exacerbation of long-term complications and worse 
prognosis [8]. Chronic, low-grade inflammation is a sig­
nificant contributor to insulin resistance and hyperglyce­
mia, precipitating DM and its associated microvascular 
and macrovascular complications [9, 10]. Meanwhile, 
inflammation has been considered a key factor in ath­
erosclerosis, thereby accelerating CVD progression [11, 
12]. In the older population, chronic, low-grade, systemic 
inflammation develops with age [11]. Elevated level of 
inflammation is predictive of all-cause mortality regard­
less of other established risk factors in the older adults 
[13, 14]. Therefore, systemic inflammation may have a 
potential role in mediating the long-term prognosis of 
the older population.
Cardiometabolic index (CMI), as a metabolism-related 
index, was an indicator initially devised to forecast DM 
risk [15]. With the in-depth clinical application, numer­
ous studies demonstrated that CMI was positively associ­
ated with risks of CVD and metabolic syndrome (MetS) 
[16, 18]. Further, research by Jovanovic et al. revealed that 
adherence to an anti-inflammatory diet correlates with 
lower CMI and reduced levels of inflammatory indicators 
[19]. Individuals with high CMI may experience elevated 
systemic inflammation, potentially aggravating CVD and 
DM and escalating the risk of long-term complications, 
leading to a worse prognosis and higher mortality. To our 
knowledge, there is no prior study to assess the prognos­
tic value of CMI in the older population.
Therefore, our study aimed to evaluate the associations 
of CMI with all-cause and cardiovascular mortality in 
the older adults, and further examine whether inflamma­
tory indicators have a potential role in mediating these 
associations.
Methods
Study design and population
The present study is a longitudinal cohort study and 
the database was from NHANES. NHANES serves as a 
comprehensive survey designed to amass data on the 
health status of the United States population. Employing 
a stratified multistage random sampling methodology, 
NHANES ensures the representation of a national sam­
ple [20]. NHANES was granted approval from the ethical 
review board of The National Center for Health Statistic, 
with each participant providing informed consent via 
signed agreements [21]. The datasets, replete with thor­
ough documentation and protocols, are publicly available 
on the NHANES website, aligning with the laboratory 
technologists and anthropometry procedures of our pre­
vious studies [22, 23].
For the present prospective cohort study, we screened 
and analyzed data spanning 6 two-year cycles from 2005 
to 2016. To uphold the integrity and reliability of results, 
the specific exclusion criteria were applied including (1) 
individuals<65 years of age (N=52734); (2) individuals 
without complete mortality data (N=13); (3) individu­
als without CMI value (N=4907); (4) individuals without 
records of necessary covariates including weight (N=6), 
leukocyte (N=15), drinking status (N=157), smoking 
status (N=4), eGFR (N=14), the history of hypertension 
(N=5), DM (N=8), coronary heart disease (CHD) (N=27), 
angina (N=9), heart attack (N=6) and stroke (N=2). A 
total of 3029 participants were enrolled from the years 
2005 to 2016 in our study (Fig. 1).
Assessment of CMI
The CMI was calculated using the formula:
CMI = triglyceride (TG, mmol/L) / high-density lipo­
protein cholesterol (HDL-C, mmol/L) waist circumfer­
ence (WC, cm)/ height (cm) [15].
Conclusion  Elevated CMI is positively associated with all-cause mortality in the older adults. The association 
appeared to be partially mediated through inflammatory pathways, indicating that CMI may serve as a valuable 
indicator for poor prognosis among the older population.
Keywords  Cardiometabolic index, Cardiovascular disease, Inflammation, Mortality, National Health and Nutrition 
Examination Survey

# Page 3

Page 3 of 13
Xu et al. Cardiovascular Diabetology          (2024) 23:212 
CMI was treated as a continuous exposure variable in 
our study and all enrolled participants were stratified into 
tertiles based on CMI values for subsequent analyses.
Assessment of all-cause and cardiovascular mortality
In the present study, the primary outcomes included all-
cause and cardiovascular mortality. To determine the 
mortality status, the NHANES public-use linked mor­
tality file as of December 31, 2019, was utilized in con­
junction with the National Death Index (NDI) by the 
National Center for Health Statistics (NCHS) through 
the implementation of a probability matching algorithm. 
Additionally, the International Statistical Classifica­
tion of Diseases, 10th Revision (ICD-10) was utilized to 
underly the cause of death. Cardiovascular mortality was 
described as death as a consequence of diseases of the 
heart (I00-I09, I11, I13, I20-I51) and cerebrovascular dis­
eases (I60-I69) [24].
Covariates
In the present study, following covariates were col­
lected including gender, age, race, education level, fam­
ily poverty-to-income ratio (PIR), body mass index 
(BMI), WC, waist-to-height ratio (WHtR), smoking, 
drinking, leukocyte, neutrophil, lymphocyte, systemic 
immune-inflammation index (SII), neutrophil to lym­
phocyte ratio (NLR), hemoglobin, platelet, albumin, 
total cholesterol (TC), TG, low-density lipoprotein cho­
lesterol (LDL-C), HDL-C, creatinine, blood urea nitro­
gen (BUN), estimated glomerular filtration rate (eGFR), 
Fig. 1  Flowchart of study participants

# Page 4

Page 4 of 13
Xu et al. Cardiovascular Diabetology          (2024) 23:212 
urinary albumin-creatinine ratio (UACR), hemoglobin 
A1c (HBA1c), hypertension, DM, cardiac disease history 
and stroke history.
BMI was the ratio of weight (kg) to height (m) squared. 
Smoking status was categorized into never, former and 
now according to the questionnaire "Smoked at least 100 
cigarettes in life?" (SMQ020) and "Do you now smoke 
cigarettes" (SMQ040). Based on the questionnaire "Had 
at least 12 alcohol drinks/1yr" (ALQ101), drinking sta­
tus was categorized into two groups based on whether 
participants had at least 12 drinks per year, and 1 unit 
of drink is equivalent to 12 ounces of beer, 5 ounces of 
wine, or 1.5 ounces of liquor. The chronic kidney disease 
epidemiology collaboration (CKD-EPI) formula was uti­
lized to calculate the eGFR [25]. The self-reported ques­
tionnaires were used for the diagnoses of hypertension 
(BPD035), DM (DIQ010), heart failure (MCQ160b), 
CHD(MCQ160c), angina (MCQ160d), heart attack 
(MCQ160e) and stroke (MCQ160f).
The formulas for calculating the relevant indexes are as 
follows:
WHtR = WC (cm)/ height (cm),
NLR = neutrophil (/L)/lymphocyte (/L),
SII = platelet (/L) *neutrophil (/L)/lymphocyte (/L).
Statistical analysis
All statistical analyses were performed with R software 
(version 4.2.2), EmpowerStats (version 2.0) along with 
the use of rms package and MSTATA. Categorical vari­
ables are expressed as frequencies and percentages, while 
continuous variables are expressed as medians and inter­
quartile ranges. The Chi-squared test or Kruskal-Wallis 
H test was used to analyze various CMI tertile categories. 
A statistically significant result was determined as a two-
sided p-value<0.05.
Multivariate Cox proportional hazard models were 
estimated for the associations of CMI with all-cause and 
cardiovascular mortality. The findings were displayed 
in the form of hazard ratios (HRs) and 95% confidence 
intervals (CI). Model 1 was unadjusted. Model 2 was 
modified to account for gender, age, and race. Based on 
Model 2, Model 3 additionally adjusted for smoking, 
drinking, leukocyte, hemoglobin, platelet, weight, TC, 
eGFR, the history of hypertension, DM, CHD, angina, 
heart attack and stroke. Kaplan-Meier curves were con­
ducted to estimate survival over time progression, with 
the log-rank test used to assess the disparity among the 
various survival curves. Additionally, the multivariate 
logistics and Cox regression were performed in the asso­
ciations between inflammatory indicators with CMI, all-
cause mortality and cardiovascular mortality respectively. 
The inflammatory-related indicators included leukocyte, 
neutrophil, lymphocyte, NLR and SII. The identical sta­
tistical techniques mentioned above were also utilized in 
the subgroup analyses to investigate potential differences 
among specific populations including gender, race, edu­
cation level, family PIR, hypertension, DM, smoking and 
drinking subgroups.
"mediation" package in R 4.2.2. was utilized to perform 
Mediation analysis assessing the mediating effects of 
inflammatory indicators (leukocyte, neutrophil, lympho­
cyte, NLR, and SII) on the associations of CMI with mor­
tality, adjusted by gender, age, race, smoking, drinking, 
hemoglobin, platelet, weight, TC, eGFR, the history of 
hypertension, DM, CHD, angina, heart attack and stroke. 
The presence of a mediating effect was defined as satis­
fying all of the following conditions having a significant 
indirect effect, a significant total effect, and a positive 
proportion of the mediator effect.
Results
Participants characteristics
Table 1 presents the baseline characteristics of enrolled 
participants in the present study with different CMI 
tertiles. Within all enrolled participants, the CMI val­
ues were 0.74±0.66 and ranging from 0.27±0.08 in T1, 
0.56±0.10 in T2, and 1.37±0.80 in T3. In comparison 
with those in the decreased CMI group, participants with 
elevated levels of CMI had an increasing proportion of 
males, smoking and lower education level and family PIR. 
In addition, participants in higher tertiles showed signifi­
cantly higher levels of leukocyte, neutrophil, lymphocyte, 
SII and had a higher prevalence of hypertension, DM, 
heart failure, stroke, CHD, angina, heart attack history.
Associations of CMI with all-cause and cardiovascular 
mortality
During an average of 89.20 months follow-up, 1015 
deaths and 348 cardiovascular-related deaths occurred in 
total. Table 2 displays the associations of CMI with all-
cause mortality and cardiovascular mortality. In model 
1, CMI had no associations with all-cause mortality and 
cardiovascular mortality. In model 2, CMI was posi­
tively associated with all-cause mortality (HR=1.14, 95% 
CI=1.05-1.24) and cardiovascular mortality (HR=1.17, 
95% CI=1.01-1.35). After adjusting all interfering factors 
in model 3, significant associations sustained positive and 
significant in all-cause mortality group (HR=1.11, 95% 
CI=1.01-1.21). However, in fully adjusted model 3, the 
HRs with corresponding CIs did not show positively sig­
nificant correlations among T1, T2 and T3. Besides, the 
Kaplan-Meier survival plots are shown in Fig. 2 and indi­
cated that participants with CMI tertiles did not show 
differences in all-cause mortality (P=0.756) and cardio­
vascular mortality (P=0.365).

# Page 5

Page 5 of 13
Xu et al. Cardiovascular Diabetology          (2024) 23:212 
Characteristics
  Overall 
  (N=3029)
Tertiles of CMI
P value
T1 (N=1010)
T2 (N=1009)
T3 (N=1010)
Gender
0.001
  Male
1507 (49.75%)
462 (45.74%)
501 (49.65%)
544 (53.86%)
  Female
1522 (50.25%)
548 (54.26%)
508 (50.35%)
466 (46.14%)
Age, years
73.28±5.50
73.55±5.56
73.53±5.53
72.77±5.38
0.001
Race, n (%)
<0.001
  Mexican American
321 (10.60%)
62 (6.14%)
124 (12.29%)
135 (13.37%)
  Other Hispanic
271 (8.95%)
71 (7.03%)
92 (9.12%)
108 (10.69%)
  Non-Hispanic White
1792 (59.16%)
582 (57.62%)
578 (57.28%)
632 (62.57%)
  Non-Hispanic Black
469 (15.48%)
230 (22.77%)
155 (15.36%)
84 (8.32%)
  Other Race
176 (5.81%)
65 (6.44%)
60 (5.95%)
51 (5.05%)
Education level, n (%)
<0.001
  Below high school
984 (32.49%)
278 (27.52%)
322 (31.91%)
384 (38.02%)
  High school
740 (24.43%)
212 (20.99%)
265 (26.26%)
263 (26.04%)
  Above high school
1305 (43.08%)
520 (51.49%)
422 (41.82%)
363 (35.94%)
Family PIR
<0.001
  <1.29
782 (25.82%)
215 (21.29%)
248 (24.58%)
319 (31.58%)
  1.30-3.49
1247 (41.17%)
403 (39.90%)
429 (42.52%)
415 (41.09%)
  >3.50
1000 (33.01%)
392 (38.81%)
332 (32.90%)
276 (27.33%)
Smoking, n (%)
0.047
  Never
1468 (48.46%)
515 (50.99%)
502 (49.75%)
451 (44.65%)
  Former
1265 (41.76%)
396 (39.21%)
413 (40.93%)
456 (45.15%)
  Now
296 (9.77%)
99 (9.80%)
94 (9.32%)
103 (10.20%)
Drinking, n (%)
0.564
  <12 drinks/year
1095 (36.15%)
353 (34.95%)
366 (36.27%)
376 (37.23%)
  ≥12 drinks/year
1934 (63.85%)
657 (65.05%)
643 (63.73%)
634 (62.77%)
BMI, kg/m2
28.63±5.78
25.83±4.88
28.61±4.99
31.44±5.99
<0.001
WC, cm
101.91±14.29
94.05±12.69
102.12±12.21
109.57±13.51
<0.001
WHtR
0.62±0.08
0.57±0.08
0.62±0.07
0.66±0.08
<0.001
Leukocyte, 109/L
6.80±3.15
6.34±3.96
6.75±2.44
7.31±2.76
<0.001
Neutrophil, 109/L
4.02±1.55
3.71±1.55
4.04±1.51
4.32±1.54
<0.001
Lymphocyte, 109/L
1.95±2.54
1.85±3.51
1.90±1.74
2.10±1.99
<0.001
NLR
2.47±1.52
2.46±1.67
2.50±1.51
2.46±1.37
0.159
SII
567.16±395.40
557.64±429.08
570.73±389.09
573.14±365.58
0.037
Hemoglobin, g/dL
13.93±1.51
13.71±1.47
13.94±1.51
14.15±1.53
<0.001
Platelets, 109/L
229.11±64.86
225.18±62.82
229.86±66.56
232.28±65.03
0.030
Albumin, g/L
41.75±2.96
41.76±2.97
41.74±2.92
41.75±3.00
0.998
TC, mmol/L
4.93±1.11
4.95±1.06
4.89±1.13
4.95±1.14
0.421
TG, mmol/L
1.44±0.81
0.82±0.24
1.28±0.32
2.22±0.90
<0.001
LDL-C, mmol/L
2.82±0.95
2.75±0.89
2.90±0.96
2.81±0.99
0.002
HDL-C, mmol/L
1.45±0.44
1.82±0.43
1.41±0.29
1.13±0.23
<0.001
Creatinine, umol/L
90.10±41.25
86.39±41.31
90.76±40.16
93.14±42.03
<0.001
BUN, mg/dl
17.00±7.35
16.50±6.28
16.88±7.54
17.63±8.06
0.077
eGFR, ml/min/1.73m2
70.41±18.60
72.94±17.66
69.86±18.78
68.42±19.07
<0.001
UACR, mg/g
73.42±348.93
51.72±246.30
76.41±405.72
92.12±373.52
<0.001
FBG, mmol/L
6.48±1.97
6.01±1.49
6.42±1.93
7.01±2.28
<0.001
OGTT, mmol/L
8.20±3.11
7.39±2.57
8.27±3.14
9.16±3.42
<0.001
HBA1c, %
6.05±1.04
5.82±0.77
6.06±1.12
6.27±1.14
<0.001
Fasting insulin, uU/mL
13.46±16.52
9.20±13.92
12.63±14.53
18.56±19.23
<0.001
Hypertension, n (%)
1910 (63.06%)
577 (57.13%)
628 (62.24%)
705 (69.80%)
<0.001
DM, n (%)
694 (22.91%)
148 (14.65%)
236 (23.39%)
310 (30.69%)
<0.001
Heart failure, n (%)
238 (7.88%)
61 (6.04%)
66 (6.55%)
111 (11.08%)
<0.001
CHD, n (%)
348 (11.49%)
99 (9.80%)
112 (11.10%)
137 (13.56%)
0.027
Table 1  Characteristics of the study population with various CMI tertiles

# Page 6

Page 6 of 13
Xu et al. Cardiovascular Diabetology          (2024) 23:212 
Subgroup Analysis
To evaluate the relationships of CMI with all-cause and 
cardiovascular mortality, subgroup analyses were per­
formed (Figs. 3 and 4). Interestingly, most analyses did 
not show differences within groups except that the posi­
tive correlation between CMI and cardiovascular mortal­
ity was stronger in the participants who were never or 
formerly smoke. Regarding the all-cause mortality group, 
there was no significant difference observed in all sub­
group analyses.
Associations of inflammation with CMI and mortality
Table 3 displays the associations of CMI and inflam­
mation-related indicators after multivariate logistic 
regression. After adjusting all interfering factors, CMI 
was positively associated with leukocyte (β=0.36, 95% 
CI=0.18-0.54, P<0.001), neutrophil (β=0.11, 95% CI=0.03-
0.19, P=0.010), lymphocyte (β=0.20, 95% CI=0.05-0.35, 
P=0.010) and negatively associated with NLR (β=-0.14, 
95% CI=-0.23--0.06, P=0.001) and SII (β=-29.62, 95% 
CI =-49.63--9.62, P=0.004). Cox regression models of 
inflammationrelated indicators with all-cause mortality 
and cardiovascular mortality are shown in Table 4. Most 
indicators were positively related to the mortality except 
lymphocytes with all-cause mortality and leukocytes 
with cardiovascular mortality.
Mediating role of inflammationrelated indicators
Fig. 5 shows that leukocyte mediated 6.6% of the associa­
tion between CMI and all-cause mortality. Regarding the 
analysis of neutrophils, the proportion of mediation was 
13.9%. Additionally, we also assessed the mediating roles 
of other inflammatory indicators including lymphocytes, 
NLR, and SII (Appendix Table S1).
Discussion
In our study, we unveiled a positive association of CMI 
with mortality among the older adults and the findings 
persisted significantly in the comprehensively adjusted 
model. After the positive correlations of inflamma­
tion-related indicators with mortality and CMI were 
demonstrated, mediation analysis was performed and 
highlighted the significant roles of leukocytes and 
Table 2  The associations of CMI with all-cause mortality and 
cardiovascular mortality in the older adults
HR (95% CI)
Model 1
Model 2
Model 3
All-cause mortality
CMI
1.07 (0.98, 1.16)
1.14 (1.05, 
1.24)
1.11 (1.01, 
1.21)
Tertile 1
1
1
1
Tertile 2
1.03 (0.89, 1.19)
1.05 (0.90, 
1.22)
1.02 (0.87, 
1.20)
Tertile 3
0.97 (0.84, 1.13)
1.09 (0.94, 
1.27)
1.07 (0.90, 
1.27)
P for trend
0.596
0.270
0.451
Cardiovascular 
mortality
CMI
1.05 (0.91, 1.22)
1.17 (1.01, 
1.35)
1.12 (0.96, 
1.30)
Tertile 1
1
1
1
Tertile 2
1.19 (0.92, 1.53)
1.24 (0.96, 
1.60)
1.16 (0.88, 
1.52) 
Tertile 3
0.97 (0.75, 1.27)
1.17 (0.90, 
1.54)
1.15 (0.86, 
1.55) 
P for trend
0.563
0.376
0.464
Model 1 adjust for: none
Model 2 adjust for: gender, age, race
Model 3 adjust for: gender, age, race, smoking, drinking, weight, leukocyte, 
hemoglobin, platelet, TC, eGFR, hypertension, DM, CHD, angina, heart attack 
and stroke
CMI cardiometabolic index, HR hazard ratio, CI confidence interval, PIR poverty-
to-income ratio, TC total cholesterol, eGFR estimated glomerular filtration rate, 
DM diabetes mellites, CHD coronary heart disease
Characteristics
  Overall 
  (N=3029)
Tertiles of CMI
P value
T1 (N=1010)
T2 (N=1009)
T3 (N=1010)
Angina, n (%)
191 (6.31%)
48 (4.75%)
66 (6.54%)
77 (7.62%)
0.025
Heart attack, n (%)
320 (10.56%)
94 (9.31%)
95 (9.42%)
131 (12.97%)
0.010
Stroke, n (%)
266 (8.78%)
79 (7.82%)
93 (9.22%)
94 (9.31%)
0.417
All-cause mortality 
0.148
  Yes
1015 (33.51%)
315 (31.19%)
354 (35.08%)
346 (34.26%)
  No
2014 (66.49%)
695 (68.81%)
655 (64.92%)
664 (65.74%)
Cardiovascular mortailty 
0.166
  Yes
348 (11.49%)
103 (10.20%)
130 (12.88%)
115 (11.39%)
  No
2681 (88.51%)
907 (89.80%)
879 (87.12%)
895 (88.61%)
Follow-up time (months)
89.20±42.67
85.33±41.32
90.16±43.00
92.12±43.41
0.001
CMI
0.74±0.66
0.27±0.08
0.56±0.10
1.37±0.80
<0.001
CMI cardiometabolic index, PIR poverty-to-income ratio, BMI body mass index, WC waist circumference, WHtR Waist-to-height ratio, NLR neutrophil to lymphocyte 
ratio, SII systemic immune-inflammation index, TC total cholesterol, TG triglyceride, LDL-C low-density lipoprotein cholesterol, HDL-C high-density lipoprotein 
cholesterol, BUN blood urea nitrogen, eGFR estimated glomerular filtration rate, UACR urinary albumin/creatinine ratio, FBG fasting blood glucose, OGTT oral glucose 
tolerance test, HBA1c hemoglobin A1c, DM diabetes mellites, CHD coronary heart disease
Table 1  (continued)

# Page 7

Page 7 of 13
Xu et al. Cardiovascular Diabetology          (2024) 23:212 
neutrophils in linking CMI with all-cause mortality, pro­
posing inflammation as a potential underlying mecha­
nism in these associations. Therefore, monitoring CMI 
among the older population offers a simple yet potent 
approach for epidemiological studies on worse prognosis.
CMI, as an innovative anthropometric index, was ini­
tially introduced by Wakabayashi et al. in 2015 to identify 
DM, demonstrating its significant correlation with hyper­
glycemia [15]. Subsequent research further explored 
the association between CMI and DM among Japanese 
adults (HR=1.65) and identified a non-linear relation­
ship with an inflection point at a CMI of 1.01 [26]. Simi­
larly, Qiu et al. reported that individuals with elevated 
CMI had a considerably increased risk of new-onset DM 
(HR=1.78), and those with initially low CMI who shifted 
to high CMI during follow-up saw their risk of develop­
ing DM elevated by 75% [27]. Moreover, researches have 
not only confirmed CMI’s linkage to increased risks of 
new-onset DM but also expanded its relevance to CVD 
and other metabolic disorders. Cai et al. found a posi­
tive association between CMI and the onset risk of CVD 
in hypertension and obstructive sleep apnea patients 
(HR=1.31) [17]. Higashiyama et al. discovered a higher 
risk for ischemic CVD in participants without MetS who 
had higher CMI [28]. Lazzer et al. indicated that CMI had 
higher sensitivity and specificity in detecting MetS com­
pared with other anthropometric indexes [18]. Radetti 
et al. revealed the validity of CMI in identifying MetS in 
severely obese children and adolescents (AUC=0.8476) 
[29]. Zou et al. identified a positive association between 
CMI and elevated risk of NAFLD in the general popu­
lation (AUC=0.8359) [16]. Liu et al. observed that CMI 
was a potent predictor of NAFLD in Chinese women 
(AUC=0.833) [30]. Miao et al. suggested CMI as an inde­
pendent risk factor for albuminuria (Odds Ratio=1.160), 
highlighting its potential in predicting renal dysfunction 
[31]. Numerous studies showed that CMI was related to 
various systematic diseases, underlining its association 
with worse prognosis. However, there is no prior study 
to evaluate the associations CMI with long-term mor­
tality, especially in the older adults with higher risk of 
comorbidities.
Other anthropometric and metabolic indices such 
as triglyceride glucose (TyG) index, WHtR as well as 
atherogenic index of plasma (AIP)—each validated as 
being associated with higher long-term mortality. Chen 
et al. elucidated a positive association of the TyG index 
with all-cause (HR=1.160) and cardiovascular mortality 
(HR=1.213) in the overall population [32]. Wang et al. 
suggested that the TyG index was a promising indicator 
for predicting all-cause mortality (HR=3.64) in patients 
younger than 65 years old with CVD [33]. Zhang et al. 
observed U-shaped associations of the TyG index with 
all-cause and cardiovascular mortality in CVD patients 
with DM or pre-DM and the threshold TyG index values 
were 9.05 and 8.84 in all-cause mortality and cardiovas­
cular mortality [34]. Shen et al. demonstrated that the 
TyG index was related to mortality (HR=1.44) in ACS 
patients with DM aged over 80 years old [35]. Similarly, 
Tamosiunas et al. suggested AIP was positively associ­
ated with all-cause mortality among women (HR=1.36) 
and cardiovascular mortality among men (HR=1.40) [36]. 
Duiyimuhan et al. demonstrated that AIP was associ­
ated with both all-cause and cardiovascular mortality 
in patients with hypertension and the U-shape associa­
tions were observed with RCS curves [37]. Considering 
of WHtR, Chen et al. suggested that WHtR was a predic­
tive factor of all-cause death (HR=1.96) in suffering from 
heart failure with preserved ejection fraction [38]. Meta-
analysis revealed that in the overall population, the HR 
for all-cause mortality increased by 16% and cardiovascu­
lar mortality by 19% with every unit of continuous WHtR 
measurements increased [39]. In the present study, 
we introduced CMI as a novel predictor of all-cause 
Fig. 2  Kaplan–Meier curves of the survival rate of participants with CMI tertiles (A All-cause mortality, B Cardiovascular mortality)

# Page 8

Page 8 of 13
Xu et al. Cardiovascular Diabetology          (2024) 23:212 
mortality in the older adults. To date, the current study is 
the first study to evaluate the prognostic value of CMI in 
the older population, as a metabolism-related index easy 
to obtain, further studies are necessary to perform for the 
validation of CMI in public health monitoring of other 
specific populations.
Although CMI is highly related to all-cause mortal­
ity as elucidated by our study, the underlying biological 
mechanisms driving these associations are not fully deci­
phered. Chronic inflammation is thought to be a signif­
icant factor in the progression of CVD and DM, which 
may explain the positive association between CMI and 
poor prognosis. Chronic low-grade inflammation is a 
well-documented contributor to insulin resistance and 
hyperglycemia, leading to the onset of DM and the fol­
lowing development of macrovascular and microvascu­
lar complications [9, 10]. The leading pathophysiological 
processes to explain insulin resistance and T2D include 
oxidative stress, amyloid deposition in the pancreas, 
endoplasmic reticulum stress, among others. Intriguingly, 
these cellular stressors can either trigger an inflammatory 
reaction or be worsened by or linked to inflammation 
[10, 40, 41]. Additionally, inflammation has been eluci­
dated as a crucial contributor to atherosclerosis, resulting 
Fig. 3  Subgroup analysis of associations between CMI and all-cause mortality

# Page 9

Page 9 of 13
Xu et al. Cardiovascular Diabetology          (2024) 23:212 
in the progress of CVD [11, 12]. Inflammatory cells also 
have important roles in the formation of plaque [12]. 
Thus far, every type of inflammatory cell has been discov­
ered in atherosclerotic lesions taken from both experi­
mental models and patients [42, 43]. In the early stage 
of atherosclerosis, macrophage subgroups were seen as 
the initial cells to infiltrate arterial lesions and transform 
into culprit foam cells [44]. Neutrophils and lympho­
cytes (including T and B cells) were subsequently iden­
tified and associated with the vulnerability and rupture 
risk of plaque [45, 46]. Additionally, recent clinical trials 
highlighted the efficacy of anti-inflammatory therapies 
including colchicine and canakinumab in secondary 
prevention of cardiovascular afflictions [12, 47]. More­
over, as individuals age, their immune system undergoes 
alterations that eventually lead to a noticeable and severe 
decline, resulting in increased rates of mortality from 
infectious and long-term comorbidity [48]. Inflammation 
can predict all-cause mortality beyond established risk 
factors in the older adults [13, 14]. Varadhan et al. sug­
gested that inflammatory indicators including C-reactive 
protein, and interleukin-6, among others were indepen­
dent predictors of 5-year mortality in the older popula­
tion [13]. Moreover, Different inflammation indicators 
Fig. 4  Subgroup analysis of associations between CMI and cardiovascular mortality

# Page 10

Page 10 of 13
Xu et al. Cardiovascular Diabetology          (2024) 23:212 
may correspond to various pathways. The signaling path­
ways involved in the regulation of various leukocyte 
functions includes NADPH Oxidase Pathway, MAPK 
Signaling Pathways, PI3K/Akt Pathway, TCR Pathway, 
BCR Pathway and NF-κB Signaling Pathway. Neutrophils, 
a pivotal class of leukocytes, play a fundamental role in 
the innate immune response. These cells are equipped 
with a variety of signaling pathways that regulate their 
activation, chemotaxis, phagocytosis, and the release 
of antimicrobial factors. Upon stimulation, neutrophils 
activate the NADPH oxidase Pathway, which is criti­
cal for the respiratory burst that produces reactive oxy­
gen species (ROS) [49]. This process is essential for the 
microbial killing capabilities of neutrophils. The MAPK 
pathways, including p38, ERK, and JNK, are activated in 
neutrophils by various stimulation such as cytokines and 
microbial products. These pathways regulate a range of 
functions including gene expression, apoptosis, and the 
production of inflammatory cytokines [50]. PI3K/Akt 
Pathway promotes cell survival by inhibiting apoptotic 
processes and is also involved in mediating responses to 
chemokines and other inflammatory stimulation [51]. 
Lymphocytes, which include T cells, B cells, and natural 
killer cells, are central to the adaptive immune response 
and also play roles in innate immunity. They are regulated 
by complex signaling pathways that govern their develop­
ment, activation, differentiation, and effector functions. 
The main signaling pathway involved in lymphocyte 
function is TCR pathway. Upon antigen recognition, the 
TCR engages with a peptide presented by the major his­
tocompatibility complex (MHC) on antigen-presenting 
cells. This interaction initiates a cascade involving the 
phosphorylation of the immunoreceptor tyrosine-based 
activation motifs (ITAMs) by Lck and Fyn, which are 
Src family tyrosine kinases. This leads to the recruitment 
and activation of ZAP-70, further propagating the signal 
through downstream effectors such as Linker for Activa­
tion of T cells (LAT) and SLP-76, culminating in the acti­
vation of transcription factors NF-AT, NF-κB, and AP-1 
[52, 53]. These factors drive gene expression crucial for 
T cell activation, proliferation, and cytokine production. 
In addition, similar to TCR, the BCR pathway is activated 
when the receptor binds its specific antigen. This results 
in the activation of Src family kinases like Lyn, which 
phosphorylate ITAMs on the Igα and Igβ chains of the 
BCR. This triggers a series of phosphorylation events 
involving Syk kinase and adaptor proteins such as BLNK, 
leading to the activation of several downstream path­
ways including PI3K/Akt, Bruton's tyrosine kinase (Btk), 
and PLCγ2. These pathways are essential for B cell sur­
vival, proliferation, differentiation into plasma cells, and 
antibody production [54]. In both T cells and B cells, the 
NF-κB pathway plays a crucial role in regulating immune 
responses by controlling the transcription of genes 
Table 3  The associations between CMI and inflammation-
related indicators
β value
95% CI
P value
Leukocyte
Model 1
0.55
0.39, 0.72
<0.001
Model 2
0.53
0.36, 0.70
<0.001
Model 3
0.36
0.18, 0.54
<0.001
Neutrophil
Model 1
0.29
0.21, 0.37
<0.001
Model 2
0.25
0.17, 0.34
<0.001
Model 3
0.11
0.03, 0.19
0.010
Lymphocyte
Model 1
0.19
0.06, 0.33
0.006
Model 2
0.21
0.07, 0.35
0.003
Model 3
0.20
0.05, 0.35
0.010
NLR
Model 1
 -0.04
 -0.13, 0.04
0.282
Model 2
 -0.08
 -0.16, 0.0
0.053
Model 3
 -0.14
 -0.23, -0.06
0.001
SII
Model 1
 -3.35
 -25.68, 16.98
0.689
Model 2
 -7.28
 -28.71, 14.14
0.505
Model 3
 -29.62
 -49.63, -9.62
0.004
Model 1 adjust for: none
Model 2 adjust for: gender, age, race
Model 3 adjust for: gender, age, race, smoking, drinking, weight, hemoglobin, 
platelet, TC, eGFR, hypertension, DM, CHD, angina, heart attack and stroke
CMI cardiometabolic index, HR hazard ratio, CI confidence interval, PIR poverty-
to-income ratio, TC total cholesterol, eGFR estimated glomerular filtration rate, 
DM diabetes mellites, CHD coronary heart disease
Table 4  The associations of inflammation-related indicators with 
all-cause mortality and cardiovascular mortality
HR (95% CI)
Model 1
Model 2
Model 3
All-cause 
mortality
Leukocyte
1.03 (1.03, 1.04)
1.02 (1.02, 1.03)
1.02 (1.01, 1.03)
Neutrophil
1.20 (1.16, 1.24)
1.16 (1.11, 1.20)
1.18 (1.11, 1.20)
Lymphocyte
1.02 (0.99, 1.04)
1.01 (1.00, 1.03)
1.01 (0.99, 1.03)
NLR
1.19 (1.16, 1.21)
1.13 (1.10, 1.16)
1.11 (1.09, 1.14)
SII
1.00 (1.00, 1.00)
1.00 (1.00, 1.00)
1.00 (1.00, 1.00)
Cardiovascular 
mortality
Leukocyte
1.02 (1.00, 1.05)
1.01 (0.99, 1.04)
1.01 (0.98, 1.03)
Neutrophil
1.17 (1.10, 1.25)
1.13 (1.06, 1.21)
1.17 (1.09, 1.25)
Lymphocyte
0.65 (0.54, 0.78)
0.79 (0.66, 0.95)
0.83 (0.69, 0.99)
NLR
1.19 (1.15, 1.23)
1.13 (1.08, 1.18)
1.11 (1.07, 1.16)
SII
1.00 (1.00, 1.00)
1.00 (1.00, 1.00)
1.00 (1.00, 1.00)
Model 1 adjust for: none
Model 2 adjust for: gender, age, race
Model 3 adjust for: gender, age, race, smoking, drinking, weight, hemoglobin, 
platelet, TC, eGFR, hypertension, DM, CHD, angina, heart attack and stroke
CMI cardiometabolic index, HR hazard ratio, CI confidence interval, PIR poverty-
to-income ratio, TC total cholesterol, eGFR estimated glomerular filtration rate, 
DM diabetes mellites, CHD coronary heart disease

# Page 11

Page 11 of 13
Xu et al. Cardiovascular Diabetology          (2024) 23:212 
involved in cell survival, proliferation, and inflammatory 
responses. Activation of NF-κB can be triggered by TCR/
BCR signaling as well as by other receptors such as Toll-
like receptors and TNF receptors [53, 55]. In the present 
study, we hypothesized that inflammation would have 
significant mediating effects in the association of CMI 
with mortality in the older adults. In the present study, 
leukocytes and neutrophils mediated 6.6% and 13.9% of 
the association between CMI and all-cause mortality. 
Our findings confirm the significant mediating role of 
inflammation, providing validate evidence for its involve­
ment in this association.
A major strength of our study is that the present study 
is a prospective cohort study, utilizing the large and rep­
resentative NHANES database, which strengthen the 
generalizability of our findings. We provide additional 
evidence supporting the positive associations of CMI 
with all-cause mortality in the older adults. Our study 
also highlights the potential of CMI as an easily obtain­
able anthropometric index for identifying individuals 
with worse prognoses and underscores the mediating 
role of inflammation in these associations.
Study limitations
Despite adjusting for several confounders, unmeasured 
or residual confounding cannot be fully excluded. Treat­
ment variables that might influence CMI, such as fibrates, 
statins, and specific oral antidiabetic medications, were 
not considered. CMI, as a novel anthropometric index, 
there is few studies to evaluate different comorbidities in 
older adults in predicting mortality. Thus, it is unknown 
that whether CMI contributes to the increased mortality 
through various comorbidities. Besides, it is noted that 
the diagnosis of hypertension, DM, heart failure, coro­
nary heart disease, angina, heart attack and stroke in this 
study were obtained through participant questionnaires, 
which may introduce recall bias, potentially affecting the 
accuracy of the diagnoses.
Conclusion
The present study provided evidence for the positive 
associations of CMI with all-cause mortality in the older 
adults, while also highlighting the significant mediating 
role of inflammation in this relationship. These insights 
added to the growing evidence supporting the clinical 
utility of CMI in predicting worse prognosis, contribut­
ing valuable perspectives for early risk stratification and 
the development of intervention strategies in the older 
populations.
Abbreviations
AIP	
Atherogenic Index of Plasma
BMI	
Body mass index
BUN	
Blood urea nitrogen
CI	
Confidence interval
CMI	
Cardiometabolic index
CVD	
Cardiovascular disease
DM	
Diabetes mellitus
eGFR	
Estimated glomerular filtration rate
FBG	
Fasting blood glucose
HbA1c	
Hemoglobin A1c
HDL-C	
High-density lipoprotein cholesterol
HR	
Hazard ratio
LDL-C	
Low-density lipoprotein cholesterol
METS	
Metabolic syndrome
NAFLD	
Nonalcoholic fatty liver disease
NHANES	
National Health and Nutrition Examination Survey
NLR	
Neutrophil to lymphocyte ratio
OGTT	
Oral glucose tolerance test
family PIR	
family poverty-to-income ratio
SII	
Systemic immune-inflammation index
TC	
Total cholesterol
TG	
Triglyceride
TyG index	
Triglyceride glucose index
UACR	
Urinary albumin/creatinine ratio
WC	
Waist circumference
WHtR	
Waist-to-height ratio
ROS	
Reactive oxygen species
MHC	
Major histocompatibility complex
Supplementary Information
The online version contains supplementary material available at https://doi.
org/10.1186/s12933-024-02251-w.
Additional file 1: Table S1. Analysis of the mediation by inflammation-
related indicators of the associations of CMI with all-cause mortality and 
cardiovascular mortality.
Fig. 5  Analysis of the mediation by leukocytes (A) and neutrophils (B) of the associations of CMI with all-cause mortality

# Page 12

Page 12 of 13
Xu et al. Cardiovascular Diabetology          (2024) 23:212 
Acknowledgements
We express our sincere gratitude for the editor and reviewers of their detailed 
and valuable suggestions, which provided invaluable improvements to the 
design and content of our study. We sincerely thank the participants and 
staff of the NHANES for their valuable contributions and to all members who 
contributed to this work.
Author contributions
BX, QW and WLC contributed to study conception and design. BX, LCL, GQY, 
FAA, WZ, WQD, YCL and ZYH organized the data and conducted the analyses. 
BX, RL, QW and WLC contributed to the interpretation of the results, revision. 
BX and QW wrote and edited and finalization of the manuscript. All authors 
have reviewed and approved the final version of the manuscript.
Funding
This work was supported by in part by Chinese National Natural Science 
Foundation (82170521), Shanghai Natural Science Foundation of China 
(21ZR1449500), Foundation of Shanghai Municipal Health Commission 
(202140263), Tibet Natural Science Foundation of China (XZ2022ZR-ZY27(Z), 
XZ202301ZR0032G), Foundation of Chongming (CKY2021-21, CKY2020-29), 
Clinical Research Plan of Shanghai Tenth People’s Hospital (YNCR2A001), 
Clinical Research Plan of SHDC (SHDC2020CR4065), and Foundation of the 
Science and Technology Commission of Shanghai Municipality (20dz1207200).
Availability of data and materials
No datasets were generated or analysed during the current study.
Declarations
Ethics approval and consent to participate
The NHANES has been approved by the National Center for Health Statistics 
Ethics Review Board, and all participants were provided informed written 
consent at enrollment.
Consent for publication
Not applicable.
Competing interests
The authors declare no competing interests.
Author details
1Department of Cardiology, Shanghai Tenth People’s Hospital, Tongji 
University School of Medicine, 301 Yanchang Road, Shanghai 
200072, China
2Department of Cardiology, Zhongshan-Xuhui Hospital, Shanghai Xuhui 
Central Hospital, Fudan University, Shanghai, China
3Department of Orthopedic Surgery, Orthopedic Institute, The First 
Affiliated Hospital of Soochow University, 188 Shizijie Road, 
Suzhou 215006, Jiangsu, China
4Research Institute of Clinical Medicine, Jeonbuk National University 
Medical School, Jeonju, Republic of Korea
5Department of Pediatric Surgery and Rehabilitation, Kunshan Maternity 
and Children’s Health Care Hospital, Kunshan, Jiangsu, China
Received: 29 February 2024 / Accepted: 26 April 2024
References
1.	
Guo F, Moellering DR, Garvey WT. The progression of cardiometabolic dis­
ease: validation of a new cardiometabolic disease staging system applicable 
to obesity. Obes (Silver Spring). 2014;22(1):110–8.
2.	
Dieleman JL, Cao J, Chapin A, et al. US Health Care Spending by Payer and 
Health Condition, 1996–2016. JAMA. 2020;323(9):863–84.
3.	
American Diabetes Association Professional Practice C. 13. Older adults: 
standards of Care in Diabetes-2024. Diabetes Care. 2024;47(Suppl 1):S244–57.
4.	
Benjamin EJ, Muntner P, Alonso A, et al. Heart Disease and Stroke Statis­
tics-2019 update: a Report from the American Heart Association. Circulation. 
2019;139(10):e56–528.
5.	
Laiteerapong N, Huang ES. (2018). Diabetes in older adults. Diabetes in 
America. 3rd edition.
6.	
Prevention CDC, National Diabetes Statistics Report. 2020: Estimates of Dia­
betes and its Burden in the United States. 2020. Accessed 13 October 2023.
7.	
Diseases GBD, Injuries C. Global burden of 369 diseases and injuries in 204 
countries and territories, 1990–2019: a systematic analysis for the global 
burden of Disease Study 2019. Lancet. 2020;396(10258):1204–22.
8.	
Donath MY, Meier DT, Boni-Schnetzler M. Inflammation in the pathophysiol­
ogy and therapy of Cardiometabolic Disease. Endocr Rev. 2019;40(4):1080–91.
9.	
Yousri NA, Suhre K, Yassin E, et al. Metabolic and Metabo-Clinical Signa­
tures of Type 2 diabetes, obesity, retinopathy, and Dyslipidemia. Diabetes. 
2022;71(2):184–205.
10.	 Donath MY, Shoelson SE. Type 2 diabetes as an inflammatory disease. Nat Rev 
Immunol. 2011;11(2):98–107.
11.	 Liberale L, Badimon L, Montecucco F, et al. Inflammation, aging, and 
Cardiovascular Disease: JACC Review topic of the Week. J Am Coll Cardiol. 
2022;79(8):837–47.
12.	 Liberale L, Montecucco F, Schwarz L, et al. Inflammation and cardio­
vascular diseases: lessons from seminal clinical trials. Cardiovasc Res. 
2021;117(2):411–22.
13.	 Varadhan R, Yao W, Matteini A, et al. Simple biologically informed inflam­
matory index of two serum cytokines predicts 10 year all-cause mortality in 
older adults. J Gerontol Biol Sci Med Sci. 2014;69(2):165–73.
14.	 Alpert A, Pickman Y, Leipold M, et al. A clinically meaningful metric of 
immune age derived from high-dimensional longitudinal monitoring. Nat 
Med. 2019;25(3):487–95.
15.	 Wakabayashi I, Daimon T. The cardiometabolic index as a new marker deter­
mined by adiposity and blood lipids for discrimination of diabetes mellitus. 
Clin Chim Acta. 2015;438:274–8.
16.	 Zou J, Xiong H, Zhang H, et al. Association between the cardiometabolic 
index and non-alcoholic fatty liver disease: insights from a general popula­
tion. BMC Gastroenterol. 2022;22(1):20.
17.	 Cai X, Hu J, Wen W, et al. Associations of the Cardiometabolic Index with the 
Risk of Cardiovascular Disease in Patients with Hypertension and Obstructive 
Sleep Apnea: Results of a Longitudinal Cohort Study. Oxid Med Cell Longev. 
2022, 2022:4914791.
18.	 Lazzer S, D'Alleva M, Isola M, et al. Cardiometabolic Index (CMI) and visceral 
Adiposity Index (VAI) highlight a higher risk of metabolic syndrome in 
women with severe obesity. J Clin Med. 2023, 12(9).
19.	 Kendel Jovanovic G, Mrakovcic-Sutic I, Pavicic Zezelj S, et al. The efficacy of an 
energy-restricted anti-inflammatory Diet for the management of obesity in 
younger adults. Nutrients. 2020, 12(11).
20.	 Johnson CL, Dohrmann SM, Burt VL, et al. National health and nutrition exam­
ination survey: sample design, 2011-2014. Vital Health Stat 2. 2014(162):1-33.
21.	 Skrivankova VW, Richmond RC, Woolf BAR, et al. Strengthening the reporting 
of Observational studies in Epidemiology using mendelian randomization: 
the STROBE-MR Statement. JAMA. 2021;326(16):1614–21.
22.	 Yan Y, Zhou L, La R, et al. The association between triglyceride glucose index 
and arthritis: a population-based study. Lipids Health Dis. 2023;22(1):132.
23.	 Yan Y, La R, Jiang M, et al. The association between remnant cholesterol and 
rheumatoid arthritis: insights from a large population study. Lipids Health Dis. 
2024;23(1):38.
24.	 WHO. International Statistical classification of diseases and related health 
problems: alphabetical index. Volume 3. World Health Organization; 2004.
25.	 Levey AS, Stevens LA, Schmid HD, et al. A new equation to estimate glomeru­
lar filtration rate. Ann Intern Med. 2009;150(9):604–12.
26.	 Zha F, Cao C, Hong M, et al. The nonlinear correlation between the cardio­
metabolic index and the risk of diabetes: a retrospective Japanese cohort 
study. Front Endocrinol (Lausanne). 2023;14:1120277.
27.	 Qiu Y, Yi Q, Li S, et al. Transition of cardiometabolic status and the risk of type 
2 diabetes mellitus among middle-aged and older Chinese: a national cohort 
study. J Diabetes Investig. 2022;13(8):1426–37.
28.	 Higashiyama A, Wakabayashi I, Okamura T, et al. The risk of Fasting 
triglycerides and its related indices for Ischemic Cardiovascular diseases 
in Japanese Community dwellers: the Suita Study. J Atheroscler Thromb. 
2021;28(12):1275–88.
29.	 Radetti G, Grugni G, Lupi F, et al. High Tg/HDL-Cholesterol Ratio Highlights a 
Higher Risk of Metabolic Syndrome in Children and Adolescents with Severe 
Obesity. J Clin Med. 2022, 11(15).
30.	 Liu Y, Wang W. Sex-specific contribution of lipid accumulation product and 
cardiometabolic index in the identification of nonalcoholic fatty liver disease 
among Chinese adults. Lipids Health Dis. 2022;21(1):8.

# Page 13

Page 13 of 13
Xu et al. Cardiovascular Diabetology          (2024) 23:212 
31.	 Miao M, Deng X, Wang Z, et al. Cardiometabolic index is associated with 
urinary albumin excretion and renal function in aged person over 60: data 
from NHANES 2011–2018. Int J Cardiol. 2023;384:76–81.
32.	 Chen J, Wu K, Lin Y, et al. Association of triglyceride glucose index with 
all-cause and cardiovascular mortality in the general population. Cardiovasc 
Diabetol. 2023;22(1):320.
33.	 Wang L, Wang Y, Liu R, et al. Influence of age on the association between the 
triglyceride-glucose index and all-cause mortality in patients with cardiovas­
cular diseases. Lipids Health Dis. 2022;21(1):135.
34.	 Zhang Q, Xiao S, Jiao X, et al. The triglyceride-glucose index is a predictor 
for cardiovascular and all-cause mortality in CVD patients with diabetes 
or pre-diabetes: evidence from NHANES 2001–2018. Cardiovasc Diabetol. 
2023;22(1):279.
35.	 Shen J, Feng B, Fan L, et al. Triglyceride glucose index predicts all-cause 
mortality in oldest-old patients with acute coronary syndrome and diabetes 
mellitus. BMC Geriatr. 2023;23(1):78.
36.	 Tamosiunas A, Luksiene D, Kranciukaite-Butylkiniene D, et al. Predictive 
importance of the visceral adiposity index and atherogenic index of plasma 
of all-cause and cardiovascular disease mortality in middle-aged and elderly 
Lithuanian population. Front Public Health. 2023;11:1150563.
37.	 Duiyimuhan G, Maimaiti N. The association between atherogenic index of 
plasma and all-cause mortality and cardiovascular disease-specific mortality 
in hypertension patients: a retrospective cohort study of NHANES. BMC 
Cardiovasc Disord. 2023;23(1):452.
38.	 Chen J, Li M, Hao B, et al. Waist to height ratio is associated with an increased 
risk of mortality in Chinese patients with heart failure with preserved ejection 
fraction. BMC Cardiovasc Disord. 2021;21(1):263.
39.	 Abdi Dezfouli R, Mohammadian Khonsari N, Hosseinpour A, et al. Waist to 
height ratio as a simple tool for predicting mortality: a systematic review and 
meta-analysis. Int J Obes (Lond). 2023;47(12):1286–301.
40.	 Hotamisligil GS, Erbay E. Nutrient sensing and inflammation in metabolic 
diseases. Nat Rev Immunol. 2008;8(12):923–34.
41.	 Donath MY, Schumann DM, Faulenbach M, et al. Islet inflammation in type 
2 diabetes: from metabolic stress to therapy. Diabetes Care. 2008;31(Suppl 
2):S161-164.
42.	 Fernandez DM, Rahman AH, Fernandez NF, et al. Single-cell immune land­
scape of human atherosclerotic plaques. Nat Med. 2019;25(10):1576–88.
43.	 Winkels H, Ehinger E, Vassallo M, et al. Atlas of the Immune Cell Repertoire 
in Mouse Atherosclerosis defined by single-cell RNA-Sequencing and Mass 
Cytometry. Circ Res. 2018;122(12):1675–88.
44.	 Nakashima Y, Fujii H, Sumiyoshi S, et al. Early human atherosclerosis: 
accumulation of lipid and proteoglycans in intimal thickenings followed by 
macrophage infiltration. Arterioscler Thromb Vasc Biol. 2007;27(5):1159–65.
45.	 Bonaventura A, Montecucco F, Dallegri F, et al. Novel findings in neutro­
phil biology and their impact on cardiovascular disease. Cardiovasc Res. 
2019;115(8):1266–85.
46.	 Ammirati E, Moroni F, Magnoni M, et al. The role of T and B cells in human 
atherosclerosis and atherothrombosis. Clin Exp Immunol. 2015;179(2):173–87.
47.	 Libby P. Inflammation in Atherosclerosis-No longer a theory. Clin Chem. 
2021;67(1):131–42.
48.	 Goronzy JJ, Weyand CM. Understanding immunosenescence to improve 
responses to vaccines. Nat Immunol. 2013;14(5):428–436.	
49.	 Amara N, Cooper MP, Voronkova MA, et al. Selective activation of PFKL sup­
presses the phagocytic oxidative burst. Cell. 2021;184(17):4480–4494.e15. 
50.	 Liu X, Ma B, Malik AB, et al. Bidirectional regulation of neutrophil migration by 
mitogen-activated protein kinases. Nat Immunol. 2012;13(5):457–64.
51.	 Wang X, Cai J, Lin B, et al. GPR34-mediated sensing of lysophosphatidylserine 
released by apoptotic neutrophils activates type 3 innate lymphoid cells to 
mediate tissue repair. Immunity. 2021;54(6):1123-e11361128.
52.	 Negishi I, Motoyama N, Nakayama K, et al. Essential role for ZAP-70 in both 
positive and negative selection of thymocytes. Nature. 1995;376(6539):435–8.
53.	 Weil R, Schwamborn K, Alcover A, et al. Induction of the NF-kappaB cascade 
by recruitment of the scaffold molecule NEMO to the T cell receptor. Immu­
nity. 2003;18(1):13.
54.	 Xu Y, Harder KW, Huntington ND. Lyn tyrosine kinase: accentuating the posi­
tive and the negative. Immunity. 2005.
55.	 Davis RE, Ngo VN, Lenz G, et al. Chronic active B-cell-receptor signalling in 
diffuse large B-cell lymphoma. Nature. 2010;463(7277):88–92.
Publisher’s Note
Springer Nature remains neutral with regard to jurisdictional claims in 
published maps and institutional affiliations.
