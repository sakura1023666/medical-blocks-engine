# Page 1

Takkavatakarn et al. Critical Care          (2024) 28:156  
https://doi.org/10.1186/s13054-024-04935-x
RESEARCH
Machine learning derived serum creatinine 
trajectories in acute kidney injury in critically ill 
patients with sepsis
Kullaya Takkavatakarn1,2†, Wonsuk Oh3†, Lili Chan1,3,4, Ira Hofer4,5, Khaled Shawwa6, Monica Kraft7, Neomi Shah7, 
Roopa Kohli‑Seth8, Girish N. Nadkarni1,3,4† and Ankit Sakhuja3,4,8*† 
Abstract 
Background  Current classification for acute kidney injury (AKI) in critically ill patients with sepsis relies only on its 
severity-measured by maximum creatinine which overlooks inherent complexities and longitudinal evaluation of this 
heterogenous syndrome. The role of classification of AKI based on early creatinine trajectories is unclear.
Methods  This retrospective study identified patients with Sepsis-3 who developed AKI within 48-h of intensive care 
unit admission using Medical Information Mart for Intensive Care-IV database. We used latent class mixed modelling 
to identify early creatinine trajectory-based classes of AKI in critically ill patients with sepsis. Our primary outcome 
was development of acute kidney disease (AKD). Secondary outcomes were composite of AKD or all-cause in-hospital 
mortality by day 7, and AKD or all-cause in-hospital mortality by hospital discharge. We used multivariable regression 
to assess impact of creatinine trajectory-based classification on outcomes, and eICU database for external validation.
Results  Among 4197 patients with AKI in critically ill patients with sepsis, we identified eight creatinine trajectory-
based classes with distinct characteristics. Compared to the class with transient AKI, the class that showed severe AKI 
with mild improvement but persistence had highest adjusted risks for developing AKD (OR 5.16; 95% CI 2.87–9.24) 
and composite 7-day outcome (HR 4.51; 95% CI 2.69–7.56). The class that demonstrated late mild AKI with persistence 
and worsening had highest risks for developing composite hospital discharge outcome (HR 2.04; 95% CI 1.41–2.94). 
These associations were similar on external validation.
Conclusions  These 8 classes of AKI in critically ill patients with sepsis, stratified by early creatinine trajectories, were 
good predictors for key outcomes in patients with AKI in critically ill patients with sepsis independent of their AKI 
staging.
Keywords  Acute kidney injury, Creatinine trajectory, Critical care, Sepsis
Open Access
© The Author(s) 2024. Open Access This article is licensed under a Creative Commons Attribution 4.0 International License, which 
permits use, sharing, adaptation, distribution and reproduction in any medium or format, as long as you give appropriate credit to the 
original author(s) and the source, provide a link to the Creative Commons licence, and indicate if changes were made. The images or 
other third party material in this article are included in the article’s Creative Commons licence, unless indicated otherwise in a credit line 
to the material. If material is not included in the article’s Creative Commons licence and your intended use is not permitted by statutory 
regulation or exceeds the permitted use, you will need to obtain permission directly from the copyright holder. To view a copy of this 
licence, visit http://creativecommons.org/licenses/by/4.0/. The Creative Commons Public Domain Dedication waiver (http://creativecom‑
mons.org/publicdomain/zero/1.0/) applies to the data made available in this article, unless otherwise stated in a credit line to the data.
Critical Care
†Kullaya Takkavatakarn and Wonsuk Oh contributed equally as first author.
†Girish N. Nadkarni and Ankit Sakhuja contributed equally as senior author.
*Correspondence:
Ankit Sakhuja
ankit.sakhuja@mssm.edu
Full list of author information is available at the end of the article

# Page 2

Page 2 of 12
Takkavatakarn et al. Critical Care          (2024) 28:156 
Background
Acute kidney injury (AKI) is a common complication in 
up to 60% of patients with critical illness and is associ-
ated with high morbidity and mortality [1]. Sepsis is the 
most common cause of AKI among critically ill patients 
[2]. Sepsis patients with AKI, have mortality rates six to 
eight folds higher than those without AKI [3, 4]. AKI in 
critically ill patients with sepsis is also associated with a 
higher risk of worsening kidney function including acute 
kidney disease (AKD), chronic kidney disease (CKD) and 
end-stage kidney disease (ESKD) [5–7]. The risks of these 
complications increase with increasing severity of AKI as 
defined by Kidney Disease Improving Global Outcomes 
(KDIGO) AKI staging [2, 7, 8].
Recent evidence has shown that AKI in sepsis patients 
is a heterogenous syndrome [9] with multiple mecha-
nisms. These include inflammation, mitochondrial 
dysfunction, metabolic reprogramming, and microcir-
culatory dysfunction [10]. Additionally, sepsis associ-
ated factors including use of nephrotoxic medications or 
associated complications such as volume overload can 
further contribute to AKI in patients with sepsis [11, 12]. 
Therefore, relying on the assessment of AKI severity and 
patient prognosis solely based on the maximum changes 
in serum creatinine, as current KDIGO AKI staging 
does, without considering the longitudinal characteris-
tics of serum creatinine changes, is an oversimplifica-
tion, as it overlooks the complexities of this heterogenous 
syndrome.
The trajectory of serum creatinine, identified by the 
trend of percent change in serum creatinine over time, 
has been shown to be an important dimension for risk 
stratification of patients with AKI after cardiac surgery 
[13]. As classification based on creatinine trajectories 
early in AKI course accounts for both absolute rise in 
creatinine and patient’s response to treatment, it could be 
a better tool for risk stratification of AKI. The role of clas-
sification of AKI based on early creatinine trajectories is 
unclear. Additionally, it is unknown whether such classi-
fication offers any advantages over current KDIGO AKI 
severity staging alone. We hypothesized that classifica-
tion of AKI in critically ill patients with sepsis based on 
these trajectories will identify patients at risk for compli-
cations beyond KDIGO AKI staging.
Methods
Data sources
We used data from two independent databases—Medi-
cal Information Mart for Intensive Care IV (MIMIC-IV) 
and eICU Collaborative Research Database (eICU) [14, 
15], for this study. MIMIC-IV is a single center database 
containing de-identified electronic health records of 
patients admitted to the Beth Israel Deaconess Medical 
Center from 2008 to 2019. We used the MIMIC-IV 
database, focusing on critically ill patients with sep-
sis who developed AKI within 48 h after their first ICU 
admission. Our aim was to develop AKI classification in 
critically ill patients with sepsis based on creatinine tra-
jectories within the first 96 h (4 days) of ICU admission. 
We chose this time-period to adequately capture the 
early trajectory of the evolution of AKI. We further used 
this development cohort to develop prediction models 
to assess whether creatinine trajectories independently 
predict outcomes in sepsis patients with AKI. eICU is a 
multicenter database comprising de-identified health 
data from more than 200,000 ICU admissions across the 
United States during the period of 2014–2015. We used 
eICU as an independent external validation cohort.
Study population
We included adult patients with sepsis who developed 
AKI within 48 h of intensive care unit (ICU) admission. 
We identified patients with sepsis based on a combina-
tion of suspicion of infection and increase in Sequential 
Organ Failure Assessment (SOFA) score by two or more 
within a 24-h period. To be consistent with prior litera-
ture [16, 17], we assumed a SOFA score of zero before 
ICU admission. We defined suspicion of infection as the 
co-occurrence of intravenous antibiotic treatment and 
collection of blood cultures such that if intravenous anti-
biotics were given first, then the cultures must have been 
obtained within 24 h [18]. In comparison, if cultures were 
obtained first, then intravenous antibiotics must have 
been ordered within 72 h. We identified onset of sepsis 
as the earlier of the suspicion of infection time and SOFA 
time if SOFA time occurred no more than 24 h before or 
12 h after the suspected infection time [19]. As the eICU 
dataset provides limited data on body fluid samplings, 
we employed an alternative definition of suspected infec-
tion, which was determined by the occurrence of multi-
ple antibiotic administrations. This alternative definition 
has been previously validated in a study comparing it to 
the original definition used in MIMIC-IV [20]. As per 
KDIGO guidelines, we defined AKI as an increase in 
serum creatinine by 0.3 mg/dL or more within 48 h or an 
increase by at least 1.5 times the reference serum creati-
nine within 7 days [8]. In congruence with previous liter-
ature [21] our specific inclusion criteria were—(1) Adult 
patients defined as those 18 years or older on admission, 
(2) who developed sepsis within 24  h of admission to 
ICU, and (3) developed AKI within 48 h after admission 
to ICU. For patients with multiple ICU admissions, we 
included data from only the first ICU admission. Figure 
S1 demonstrates the criteria to identify the definition and 
time of AKI in patients with sepsis onset [18–20]. We 
excluded patients under the age of 18 years, those with

# Page 3

Page 3 of 12
Takkavatakarn et al. Critical Care          (2024) 28:156 
	
ESKD or prior kidney transplant, with a known base-
line creatinine level > 4  mg/dL or with development of 
AKI prior to ICU admission. We also excluded patients 
receiving kidney replacement therapy or those who were 
discharged or died before 96  h after ICU admission. 
Details regarding the selection process employed in this 
study are given in Fig. 1.
Outcome
The primary outcome was development of AKD, defined 
as the continued meeting of AKI criteria in surviving 
patients beyond 7  days after development of AKI [22]. 
The secondary outcomes were—(1) a composite of AKD 
or all-cause in-hospital mortality by day 7 after AKI 
onset, and (2) a composite of AKD by hospital discharge 
or all-cause in-hospital mortality.
Feature extraction
We included data on patient demographics, comorbidi-
ties, baseline creatinine, laboratory values, vasopressor 
use and duration and exposure to nephrotoxic drugs [23] 
during the first 96  h of the ICU admission. Similar to 
prior literature, we determined baseline serum creatinine 
as the median serum creatinine within 12 months prior 
to hospital admission [24, 25]. For patients with miss-
ing previous serum creatinine values in this timeframe, 
as recommended by KDIGO, we estimated the baseline 
serum creatinine by assuming the Modification of Diet 
in Renal Disease estimated glomerular filtration rate 
of 75 mL/min per 1.73 ­m2 [8]. In accordance with pre-
vious studies, we then determined the reference serum 
creatinine as the lower of the baseline serum creatinine 
mentioned above and the first admission serum creati-
nine [24, 26]. Following published literature, we excluded 
variables with more than 40% missing values [27–29]. All 
other missing data were imputed using predictive mean 
matching techniques with five imputations based on 
Multivariate Imputation via Chained Equations (MICE) 
function in R [30].
Statistical analysis
We expressed descriptive results for the participant base-
line characteristics as either mean with standard devia-
tion or as median with interquartile range, depending on 
skewness. We compared categorical features using Chi-
square test and continuous features using Student t test 
and Mann–Whitney U tests.
We utilized the latent class mixed models (LCMM) to 
identify classes based on serum creatinine trajectories 
defined by the percentage change in serum creatinine as 
([serum creatinine–reference creatinine]/reference cre-
atinine)*100. LCMM is a robust and validated statistical 
method designed to uncover clinically significant patient 
subgroups with similar longitudinal outcomes [31]. It 
integrates mixed models, which track individual-level 
growth in longitudinal outcomes through random effects, 
with latent class analysis that classifies patients into 
groups based on shared progression patterns. We calcu-
lated creatinine changes. We developed LCMM models 
with varying number of classes (2–10) in the develop-
ment cohort. We selected the model with the lowest 
Bayesian Information Criterion (BIC). Subsequently, we 
computed the probability that a patient belongs to each 
class using this model and classified them into the class 
Fig. 1  Consort diagram of development and validation cohorts

# Page 4

Page 4 of 12
Takkavatakarn et al. Critical Care          (2024) 28:156 
to which they had the highest probability of belonging. 
We assessed model discrimination using the mean poste-
rior class membership probability (MPCMP). It is a class-
specific metric that represents the mean probability of 
class membership for patients assigned to that class [32]. 
We then used mixed models to estimate marginal projec-
tion of the changes in creatinine levels across different 
LCMM classes. For external validation, we applied the 
trained LCMM model to the validation cohort, utilizing 
all estimated parameters derived from the model trained 
on the development cohort to classify creatinine trajecto-
ries with the validation cohort.
We used regression models to identify the impact 
of the classification of AKI in critically ill patients with 
sepsis based on early creatinine trajectories on vari-
ous outcomes. We used logistic regression to assess the 
relationship between classification of AKI in critically ill 
patients with sepsis based on early creatinine trajecto-
ries and development of AKD. We used Kaplan–Meier 
and Cox regression analyses to evaluate the relationship 
between classification of AKI in critically ill patients with 
sepsis based on early creatinine trajectories and compos-
ite outcomes of AKD or all-cause in-hospital mortality 
by day 7, and AKD or all-cause in-hospital mortality by 
hospital discharge. To evaluate the independent effect of 
classification of AKI in critically ill patients with sepsis 
based on early creatinine trajectories on these outcomes, 
we adjusted the logistic and Cox regressions for age, 
gender, race, comorbidities, laboratory results, baseline 
creatinine level, SOFA score, initial and maximum AKI 
staging. We performed all analyses using R, version 4.2.2 
[33].
Results
A total of 4197 patients with AKI in critically ill patients 
with sepsis from MIMIC-IV database satisfied the inclu-
sion and exclusion criteria of this study and served as 
the development set. A total of 3963 patients with AKI 
in critically ill patients with sepsis from eICU served as 
external validation set. A comparison of baseline charac-
teristics and outcomes between two cohorts is shown in 
Tables 1 and 2 respectively.
Classification of AKI in critically ill patients with sepsis 
based on early creatinine trajectories
With the lowest BIC for an eight-class model (Additional 
file 2: Table S1), we identified 8 distinct Classes of cre-
atinine trajectories in the development cohort using 
LCMM. MPCMP values for class assignment ranged 
from 62 to 89% (Additional file  2: Table  S2), indicat-
ing good discrimination between classes. These classes 
showed differences in AKI staging, rate, timing, and 
recovery (Fig. 2).
Class 1. Transient AKI—Creatinine trajectory in this 
class showed a minor nadir from baseline on ICU 
admission, followed by a mild rise that peaked at AKI 
stage 1 on day 2–3, with subsequent recovery.
Class 2. Minor Transient AKI—Creatinine trajectory 
in this class started with a minor decrease from base-
line, followed by a mild rise in creatinine that peaked 
on day 1, with subsequent recovery of AKI.
Class 3. Early Mild AKI with Persistence—Creatinine 
trajectory in this class started with stage I AKI at ICU 
admission with continued rise in creatinine till day 1 
to 2, followed by a sustained decline but persistence 
of AKI.
Class 4. Early Mild AKI followed by Recovery—Cre-
atinine trajectory in this class started with an initial 
stage 1 AKI on admission to ICU which then showed 
a sustained decline to AKI resolution.
Class 5. Late Mild AKI with persistence—This class 
had a mild rise in creatinine on ICU admission that 
continued worsening with peak at AKI stage 1 by day 
2, followed by a sustained decline but persistence of 
AKI.
Class 6. Late Mild AKI with persistence and wors-
ening—This class had a mildly elevated creatinine 
on ICU admission that then showed a sustained 
increase.
Class 7. Moderate AKI with persistence—This class 
had stage II AKI on ICU admission with continued 
increased in creatinine for a peak of AKI stage 2–3 by 
day 2–3. This was followed by a mild decline but with 
persistence of AKI.
Class 8. Severe AKI with mild improvement but per-
sistence—This class had AKI stage 3 on ICU admis-
sion followed by a small, sustained decline thereafter 
but with continued persistence of AKI.
The class observed most was Transient AKI (Class 1) 
(23.5%), followed by Late Mild AKI with Persistence 
(Class 5) (22%) and Early Mild AKI with Persistence 
(Class 3) (17%). There were significant differences among 
Classes in age (p < 0.001), hemoglobin (p = 0.009), white 
blood cell counts (p = 0.02), lactate levels (p = 0.009), 
maximum SOFA score (p < 0.001), vasopressor duration 
(p < 0.001) (Additional file 2: Table S3).
Classification of AKI in critically ill patients with sepsis 
based on early creatinine trajectories and outcomes 
in the development cohort (MIMIC‑IV)
Development of AKD
In development cohort, 674 (16%) patients developed 
AKD (Table 2). There were significant differences among 
Classes in development of AKD (p < 0.001) (Additional 
file  2: Table  S4). On regression analysis, the creatinine

# Page 5

Page 5 of 12
Takkavatakarn et al. Critical Care          (2024) 28:156 
	
Table 1  Baseline characteristics
MIMIC-IV (4197)
eICU (3963)
p-value
Age (years)
70 (59, 80)
67 (59, 78)
0.001
Male (%)
2577 (61%)
2228 (56%)
 < 0.001
Race (%)
 < 0.001
 White
2883 (69%)
3171 (80%)
 Black
375 (9%)
434 (11%)
 Hispanic
139 (3%)
64 (2%)
 Others
800 (19%)
294 (7%)
 Height (cm)
170 (163, 178)
170 (163, 178)
0.07
 Weight (kg)
80 (68, 96)
84.7 (70, 104)
 < 0.001
Underlying diseases (%)
 Diabetes mellitus
951 (23%)
467 (12%)
 < 0.001
 Congestive heart failure
968 (23%)
560 (14%)
 < 0.001
 Arrhythmia
774 (18%)
587 (15%)
 < 0.001
 Chronic lung disease
620 (15%)
379 (10%)
 < 0.001
 Liver disease
328 (8%)
180 (5%)
 < 0.001
Laboratorya
 Hemoglobin (g/dL)
8.4 (7.5, 9.6)
8.8 (7.6, 10.2)
 < 0.001
 Hematocrit (%)
25 (23, 29)
27 (23, 31)
 < 0.001
 White blood cell count (× ­109/L)
15.4 (11.5, 20.5)
15.3 (11.3, 20.8)
0.54
 Platelet (× 1000/mm3)
123 (82, 180)
130 (85, 185)
0.02
 PT
16 (14, 20)
17 (14, 22)
 < 0.001
 PTT
37 (31, 55)
38 (32, 55)
0.22
 INR
1.5 (1.3, 1.9)
1.4 (1.2, 2)
0.001
 BUN (mg/dL)
38 (26, 57)
44 (31, 61)
 < 0.001
 Sodium (mmo/L)
142 (139, 145)
142 (139, 146)
 < 0.001
 Potassium (mmo/L)
4.8 (4.4, 5.2)
4.7 (4.3, 5.1)
 < 0.001
 Chloride (mmo/L)
109 (106, 113)
109 (105, 114)
0.97
 Bicarbonate (mmo/L)
20 (17, 23)
20 (16, 23)
0.01
 Calcium (mg/dL)
8.6 (8.2, 9)
8.6 (8.1, 9)
 < 0.001
 SGOT (U/L)
54 (28, 137)
46 (25, 118)
 < 0.001
 SGPT (U/L)
34 (18, 100)
31 (18, 79)
0.01
 ALP (U/L)
86 (62, 129)
84 (61, 125)
0.21
 Albumin (d/dL)
2.9 (2.4, 3.2)
2.5 (2.1, 2.9)
 < 0.001
 Glucose (mg/dL)
171 (140, 229)
183 (147, 246)
 < 0.001
 pH
7.30 (7.24, 7.35)
7.31 (7.24, 7.37)
 < 0.001
 pO2
64 (40, 87)
75 (62, 95)
 < 0.001
 pCO2
47 (42, 55)
43 (37, 52)
 < 0.001
 pO2/FiO2
319 (234, 414)
310 (217, 376)
 < 0.001
 Lactate (mg/dL)
2.4 (1.7, 3.7)
2 (1.3, 3.6)
 < 0.001
 Baseline creatinine (mg/dL)b
1 (0.8, 1.2)
0.98 (0.8, 1)
 < 0.001
First AKI staging (%)
 < 0.001
 1
2755 (66%)
2047 (52%)
 2
667 (16%)
1114 (28%)
 3
775 (18%)
802 (20%)
MAX AKI Staging (%)
 < 0.001
 1
2421 (58%)
1508 (38%)
 2
788 (19%)
1204 (30%)
 3
988 (23%)
1251 (32%)
 MAX SOFA score
7 (5, 10)
8 (5, 10)
 < 0.001

# Page 6

Page 6 of 12
Takkavatakarn et al. Critical Care          (2024) 28:156 
trajectories were associated with differing risks of devel-
opment of AKD. In comparison to patients with tran-
sient AKI (Class 1), the highest risk for development 
of AKD was seen in patients in severe AKI with mild 
improvement but persistence (Class 8) (OR 9.02; 95% 
CI 5.94–13.7; p < 0.001), followed by Class 6, 7, 3, and 
5 respectively (Table  3). This difference in the risks of 
development of AKD by classes based on creatinine tra-
jectories persisted on multivariable logistic regression 
analysis where Class 8 still showed the highest risk for 
development of AKD with Class 1 as the reference group 
(OR 5.16; 95% CI 2.87–9.24; p < 0.001) (Fig. 3).
Composite of AKD or mortality in seven days
In the development cohort, 872 (21%) patients developed 
AKD or died within seven days after AKI onset.
On univariable cox regression analysis, creatinine 
trajectories were associated with differing risks of 
development of a composite of AKD or all-cause in-hos-
pital mortality by day 7 after AKI onset. In comparison 
to Transient AKI (Class 1), Late Mild AKI with Persis-
tence and Worsening (Class 6) showed the highest risk 
for development of a composite of AKD or mortality in 
7  days (HR 4.98; 95% CI 3.60–6.89; p < 0.001), followed 
by Severe AKI with Mild Improvement but Persistence 
(Class 8) (HR 3.38; 95% CI 2.36–4.85; p < 0.001) and 
Moderate AKI with Persistence (Class 7) (HR 3.02; 95% 
CI 2.28–3.99; p =  < 0.001), respectively (Table  3 and 
Additional file 1: Figure S2).
This difference in the risks of development of a com-
posite of AKD or all-cause in-hospital mortality by day 
7 after AKI onset by classes based on creatinine trajecto-
ries persisted on adjusted survival analysis (Fig. 4).
Composite of AKD or total all‑cause in‑hospital mortality 
by discharge
A total 772 (18%) patients had AKD by discharge or died 
during the hospital admission in the development cohort 
(Table 2). The classes of creatinine trajectories were asso-
ciated with differing risks of development of a composite 
of AKD or all-cause in-hospital mortality by discharge in 
both unadjusted (Table 3 and Additional file 1: Figure S3) 
and adjusted analyses (Fig. 5).
Validation of creatinine trajectories in independent 
external cohort (eICU)
We validated the LCMM model and identified 8 creati-
nine trajectories in the eICU which served as our exter-
nal validation cohort. Discrimination among classes was 
good, with MPCMP ranging from 60 to 91% (Additional 
Data are presented as count (percent) or median (interquartile range [IQR])
AKI acute kidney injury, BUN blood urea nitrogen, SGPT serum glutamic pyruvic transaminase, SGOT serum glutamic-oxaloacetic transaminase, SOFA sequential organ 
failure assessment
a Laboratory values were selected by the most abnormal results
b Baseline serum creatinine was determined as the lower of the median serum creatinine level within 12 months prior to hospital admission and the first admission 
creatinine measure. For patients with missing previous serum creatinine level, we calculated a baseline serum creatinine level by using the Modification of Diet in 
Renal Disease equation as recommended in the KDIGO AKI guideline, assuming a glomerular filtration rate of 75 mL/min per 1.73 ­m2
c Vasopressors included norepinephrine, dopamine, epinephrine, phenylephrine, or vasopressin
Table 1  (continued)
MIMIC-IV (4197)
eICU (3963)
p-value
 Vasopressor use (%)c
2603 (62%)
1019 (26%)
 < 0.001
 Vasopressor duration (minutes)
1285 (419, 3101)
2731 (960, 4906)
 < 0.001
 Nephrotoxins (%)
1441 (34%)
2883 (73%)
 < 0.001
Table 2  Clinical outcomes
MIMIC-IV (4197)
eICU (3963)
p-value
Outcomes
 AKD day 7 (%)
674 (16%)
1000 (25%)
 < 0.001
 Death within 7 days (%)
198 (5%)
184 (5%)
0.87
 In hospital mortality (%)
591 (14%)
512 (13%)
0.12
 Composite of AKD and death by day 7 (%)
872 (21%)
1184 (30%)
 < 0.001
 Composite of AKD or in-hospital mortality by hospital discharge 
(%)
772 (18%)
1008 (25%)
 < 0.001
 ICU length of stay (days)
3.9 (2, 7.2)
4.1 (2.2, 7.4)
0.004
 Hospital length of stay after ICU admission (days)
9.2 (6.1, 15.4)
9.1 (6.3, 14.4)
0.002

# Page 7

Page 7 of 12
Takkavatakarn et al. Critical Care          (2024) 28:156 
	
file 2: Table S5). There were significant differences among 
Classes in age (p < 0.001), hemoglobin (p < 0.001), white 
blood cell counts (p < 0.001), lactate levels (p < 0.001), 
maximum SOFA score (p < 0.001), vasopressor duration 
(p < 0.001), and development of AKD (p < 0.001) (Addi-
tional file 2: Table S6, S7).
Among 3963 AKI with sepsis patients, 1000 (25%) 
patients developed AKD at day 7 (Table  2). Like the 
development cohort, these classes of creatinine trajecto-
ries in the external validation cohort were associated with 
differing risks of development of AKD, and composite of 
both AKD or all-cause in-hospital morality by day 7 and 
Fig. 2  AKI in critically ill patients with sepsis classification based on serum creatinine trajectories in development cohort
Table 3  Univariate logistic regression models for AKD and univariate cox regression models for composite outcomes in the 
development cohort
AKD
AKD or mortality by day 7
AKD at discharge or in-hospital 
mortality
OR
95% CI
p
HR
95% CI
p
HR
95% CI
p
Class 1 (reference 
group)
1
1
1
Class 2
0.99
0.60, 1.63
0.97
0.99
0.68, 1.47
0.99
1.14
0.82, 1.58
0.43
Class 3
3.99
2.87, 5.55
 < 0.001
2.31
1.75, 3.04
 < 0.001
1.51
1.17, 1.94
0.001
Class 4
1.30
0.85, 2.01
0.23
0.85
0.58, 1.23
0.38
0.57
0.39, 0.83
0.003
Class 5
2.52
1.80, 3.55
 < 0.001
1.92
1.45, 2.54
 < 0.001
1.32
1.02, 1.70
0.03
Class 6
7.11
4.81, 10.53
 < 0.001
4.98
3.60, 6.89
 < 0.001
3.48
2.56, 4.74
 < 0.001
Class 7
5.59
3.99, 7.83
 < 0.001
3.02
2.28, 3.99
 < 0.001
1.79
1.37, 2.33
 < 0.001
Class 8
9.02
5.94, 13.69
 < 0.001
3.38
2.36, 4.85
 < 0.001
1.93
1.31, 2.82
 < 0.001

# Page 8

Page 8 of 12
Takkavatakarn et al. Critical Care          (2024) 28:156 
AKD or all-cause in-hospital by discharge, in both unad-
justed and adjusted analyses (Table 4 and Figs. 3, 4, 5).
Discussion
In this study using data from two large, independent 
critical care databases we derived and validated 8 differ-
ent classes of early creatinine trajectories early in AKI in 
critically ill patients with sepsis. These classes were het-
erogenous in both baseline characteristics and outcomes 
of patients with AKI in critically ill patients with sepsis. 
Additionally, we show that membership in these classes 
is an independent predictor for AKD and composite of 
AKD or mortality by day 7 and composite of AKD or 
mortality by hospital discharge.
AKI is common in critically ill patients and is associ-
ated with high morbidity and mortality. However, not 
all instances of AKI are the same as is demonstrated by 
the recognition of various stages of AKI [8]. The cur-
rent staging for AKI relies on the severity of AKI as 
identified by maximum change in serum creatinine or 
minimum urine output over a period. The recent dis-
covery of different phenotypes of AKI [9] suggests that 
classification of AKI just by severity is inadequate, par-
ticularly when considering different etiologies of AKI 
and effects of early management strategies of AKI in 
patients with sepsis [9, 25]. Use of an unbiased meth-
odology to identify novel and clinically relevant sub-
phenotypes of AKI based on early trajectory of serum 
creatinine provides a novel approach to classify AKI in 
critically ill patients with sepsis. An added advantage of 
this technique is that it enhances and further personal-
izes the current AKI classification, which relies solely 
on its severity.
The trajectories of serum creatinine have been shown 
to be associated with different outcomes in patients with 
AKI. Bhatraju et al. [34] studied the creatinine trajectory 
in first 72 h of ICU stay among critically ill patients with 
AKI and showed that patients who have a non-resolving 
AKI subphenotype in that timeframe have a higher risk 
of mortality in comparison to patients with a resolving 
subphenotype of AKI (RR 1.68; 95% CI 1.15–2.33). Simi-
larly, Kellum et al. [35] delineated five distinct recovery 
sub-phenotypes among critical care patients with AKI 
during the first week following the onset of AKI. These 
sub-phenotypes were classified based on patterns of 
reversal, relapse, or recovery. Sub-phenotypes with 
patients who never recovered or had reversal with relapse 
had the longest lengths of stay and the worst prognosis, 
Fig. 3  Multivariable logistic regression analysis of the risk of AKD

# Page 9

Page 9 of 12
Takkavatakarn et al. Critical Care          (2024) 28:156 
	
while patients recovering late did better than those with 
no recovery, but not as well as those recovering early.
Most recently, Andrew et  al. [13] employed LCMM 
technique to identify twelve different trajectories of 
serum creatinine within the first 4 days after cardiac sur-
gery. Among them, they found that there were four cre-
atinine trajectories that were associated with higher risk 
of death. These results are similar to our study where we 
identified eight creatinine trajectories, with distinct clini-
cal characteristics and outcomes, in patients with AKI in 
critically ill patients with sepsis. With increasing recogni-
tion of the importance of AKD, we focused our attention 
in this study on studying the impact of these trajectories 
on development of AKD.
Development of AKD is associated with develop-
ment of CKD, ESKD, longer length of stay, and greater 
risk of mortality [36, 37]. Additionally, the AKD period 
itself represents a critical time window during which 
interventions could be initiated to potentially alter the 
natural history of kidney disease. Though mortality is 
a critical endpoint, use of AKD for risk stratification of 
AKI in critically ill patients allows for a more holistic 
assessment by incorporating both risk for increased 
mortality with AKD and increased risk for further 
decline in kidney function. Additionally, it allows for 
identification of high-risk patients where targeted novel 
therapies could decrease the onset of AKD, and subse-
quent long term adverse consequences. In this study, we 
show that classification based on early creatinine tra-
jectories in sepsis patients with AKI identifies patients 
at risk for AKD. Moreover, these classes further identify 
patients at risk for a composite of AKD or mortality by 
day 7 and AKD or mortality by discharge. Risk stratifi-
cation of patients with AKI in critically ill patients with 
sepsis by creatinine trajectories is independent of AKI 
staging, thus providing a method to further personalize 
care. It has been shown that certain patients with AKI 
respond differently to vasopressin therapy [38]. As clas-
sification by creatinine trajectories incorporates infor-
mation about both severity of AKI and its response to 
early management strategies, this may allow for further 
identification of differential responses to therapeutic 
interventions across these classes. This classification 
would also be important for timely allocation of appro-
priate resources for patients, such as need for follow up 
in nephrology clinic on discharge.
Fig. 4  Multivariable Cox regression analysis of a composite of AKD and 7-day mortality

# Page 10

Page 10 of 12
Takkavatakarn et al. Critical Care          (2024) 28:156 
It is important to acknowledge the limitations of this 
study. Most importantly, this is a retrospective study and 
the impact of these classes on clinical care needs to be 
evaluated in prospective studies. Furthermore, our study 
aims to classify early AKI in critically ill patients with 
sepsis based on initial 96-h serum creatinine trajectory 
after ICU admission. We, therefore, utilized creatinine-
based criteria to define AKI, while focusing on patients 
who developed AKI within first 48 h of ICU admission 
and survived the initial 96 h. As kidney replacement ther-
apy directly affects serum creatinine measurements, we 
excluded patients receiving kidney replacement therapy 
Fig. 5  Multivariable Cox regression analysis of a composite of AKD at discharge and in-hospital mortality
Table 4  Univariate logistic regression models for AKD and univariate cox regression models for composite outcomes in the validation 
cohort
AKD
AKD or mortality by day 7
AKD at discharge or in-hospital 
mortality
OR
95% CI
p
HR
95% CI
p
HR
95% CI
p
Class 1 (reference 
group)
1
1
1
Class 2
0.39
0.05, 3.21
0.38
0.90
0.33, 2.44
0.84
1.24
0.49, 3.16
0.65
Class 3
7.58
3.38, 17.01
 < 0.001
3.57
1.96, 6.49
 < 0.001
3.46
1.95, 6.16
 < 0.001
Class 4
2.53
1.07, 5.95
0.03
1.47
0.77, 2.82
0.24
1.16
0.61, 2.21
0.65
Class 5
3.69
1.61, 8.45
0.002
1.92
1.03, 3.58
0.04
2.25
1.24, 4.09
0.007
Class 6
9.26
3.85, 22.32
 < 0.001
4.47
2.28, 8.76
 < 0.001
4.59
2.37, 8.88
 < 0.001
Class 7
13.32
5.95, 29.83
 < 0.001
4.23
2.33, 7.69
 < 0.001
3.61
2.03, 6.42
 < 0.001
Class 8
19.97
8.79, 45.4
 < 0.001
4.66
2.52, 8.62
 < 0.001
4.82
2.66, 8.74
 < 0.001

# Page 11

Page 11 of 12
Takkavatakarn et al. Critical Care          (2024) 28:156 
	
during the first 96 h after ICU admission. Despite these 
limitations, our study is a significant step towards per-
sonalization of risk stratification of AKI in critically ill 
patients with sepsis.
Conclusions
We identified eight distinct classes of AKI in critically ill 
patients with sepsis based-on serum creatinine trajecto-
ries within the first 96 h after AKI. These classes identi-
fied patients with distinct clinical characteristics and risk 
for development of AKD, AKD or mortality by day 7 and 
AKD or mortality by hospital discharge. This risk stratifi-
cation by creatinine trajectories was independent of AKI 
staging and validated independently. Further studies are 
needed to identify therapeutic and management implica-
tions of creatinine trajectories.
Abbreviations
AKD	
Acute kidney disease
AKI	
Acute kidney injury
BIC	
Bayesian information criterion
CKD	
Chronic kidney disease
eICU	
Electronic Intensive Care Unit
ESKD	
End-stage kidney disease
ICU	
Intensive care unit
KDIGO	
Kidney Disease Improving Global Outcomes
LCMM	
Latent class mixed models
MICE	
Multivariate imputation via chained equations
MIMIC-IV	
Medical Information mart for intensive care IV
MPCMP	
Mean posterior class membership probability
Supplementary Information
The online version contains supplementary material available at https://​doi.​
org/​10.​1186/​s13054-​024-​04935-x.
Supplementary Material 1: Figure S1. Criteria to identify time of AKI in criti‑
cal ill patients with sepsis onset. Figure S2. Kaplan Meier survival curve for 
AKD or 7-day mortality for creatinine trajectories in development cohort 
(A) and validation cohort (B). Figure S3. Kaplan Meier survival curve for 
AKD at discharge or in-hospital mortality in development cohort (A) and 
validation cohort (B).
Supplementary Material 2: Table S1. Fit statistics for latent class mixed 
models in development cohort. Table S2. Mean Posterior Probability of 
Membership in Class in MIMIC-IV. Table S3. Baseline characteristics by 
creatinine trajectory in MIMIC-IV. Table S4. Clinical outcomes by creatinine 
trajectory in MIMIC-IV. Table S5. Mean Posterior Probability of Membership 
in Class in eICU database. Table S6. Baseline characteristics by creatinine 
trajectory in eICU database. Table S7. Clinical outcomes by creatinine 
trajectory in eICU database.
Acknowledgements
None.
Author contributions
Conceptualization: Kullaya T, Wonsuk O, Ankit S. Funding acquisition: Girish 
NN, Ankit S. Methodology: Kullaya T, Wonsuk O, Ankit S. Data curation: Kullaya 
T, Wonsuk O, Ankit S. Data analysis: Kullaya T, Wonsuk O, Ankit S. Interpreta‑
tion of data and analysis: Kullaya T, Wonsuk O, Lili C, Ira H, Khaled S, Monica 
K, Neomi S, Roopa K, Girish NN, Ankit S. Drafting of Manuscript: Kullaya T, 
Wonsuk O, Ankit S. Critical revision of the manuscript for important intellectual 
content: Kullaya T, Wonsuk O, Lili C, Ira H, Khaled S, Monica K, Neomi S, Roopa 
K, Girish NN, Ankit S. Supervision: Lili C, Ira H, Girish NN, Ankit S. Final approval 
of version to be published: Kullaya T, Wonsuk O, Lili C, Ira H, Khaled S, Monica K, 
Neomi S, Roopa K, Girish NN, Ankit S.
Funding
This study was supported by NIDDK grant 5K08DK131286 (AS) and 
R01DK127139 (GNN). The funder had no role in study design, data collection 
and analysis, decision to publish, or preparation of the manuscript.
Availability of data and materials
Publicly available datasets were analyzed in this study. The dataset used in 
this study, MIMIC-IV, is available at https://​mimic.​physi​onet.​org/, and the eICU 
dataset is available at https://​github.​com/​mit-​lcp/​eicu-​code.
Declarations
Ethics approval and consent to participate
Consent obtained for use of MIMIC and eICU databases.
Consent for publication
Not applicable.
Competing interests
GNN is a founder of Renalytix, Pensieve, Verici and provides consultancy 
services to AstraZeneca, Reata, Renalytix, Siemens Healthineer and Variant Bio, 
serves a scientific advisory board member for Renalytix and Pensieve. He also 
has equity in Renalytix, Pensieve and Verici. LC is a consultant for Vifor Pharma 
INC and has received honorarium from Fresenius Medical Care. All remaining 
authors have declared no conflicts of interest.
Author details
1 Division of Nephrology, Department of Medicine, Icahn School of Medicine 
at Mount Sinai, New York, NY, USA. 2 Division of Nephrology, Department 
of Medicine, King Chulalongkorn Memorial Hospital, Chulalongkorn University, 
Bangkok, Thailand. 3 The Charles Bronfman Institute for Personalized Medicine, 
Icahn School of Medicine at Mount Sinai, New York, NY, USA. 4 Division of Data 
Driven and Digital Medicine, Department of Medicine, Icahn School of Medi‑
cine at Mount Sinai, New York, NY, USA. 5 Department of Anesthesiology, Icahn 
School of Medicine at Mount Sinai, New York, NY, USA. 6 Division of Nephrol‑
ogy, Department of Medicine, West Virginia University, Morgantown, WV, 
USA. 7 Division of Pulmonary, Critical Care and Sleep Medicine, Department 
of Medicine, Icahn School of Medicine at Mount Sinai, New York, NY, USA. 
8 Institute for Critical Care Medicine, Icahn School of Medicine at Mount Sinai, 
New York, NY, USA. 
Received: 12 February 2024   Accepted: 29 April 2024
References
	1.	
Hoste EAJ, Kellum JA, Selby NM, et al. Global epidemiology and 
outcomes of acute kidney injury. Nat Rev Nephrol. 2018;14(10):607–25. 
https://​doi.​org/​10.​1038/​s41581-​018-​0052-0.
	2.	
Hoste EA, Bagshaw SM, Bellomo R, et al. Epidemiology of acute 
kidney injury in critically ill patients: the multinational AKI-EPI study. 
Intensive Care Med. 2015;41(8):1411–23. https://​doi.​org/​10.​1007/​
s00134-​015-​3934-7.
	3.	
Uchino S, Kellum JA, Bellomo R, et al. Acute renal failure in critically ill 
patients: a multinational, multicenter study. JAMA. 2005;294(7):813–8. 
https://​doi.​org/​10.​1001/​jama.​294.7.​813.
	4.	
Thakar CV, Christianson A, Freyberg R, Almenoff P, Render ML. Incidence 
and outcomes of acute kidney injury in intensive care units: a veterans 
administration study. Crit Care Med. 2009;37(9):2552–8. https://​doi.​org/​
10.​1097/​CCM.​0b013​e3181​a5906f.
	5.	
Murugan R, Kellum JA. Acute kidney injury: What’s the prognosis? Nat Rev 
Nephrol. 2011;7(4):209–17. https://​doi.​org/​10.​1038/​nrneph.​2011.​13.
	6.	
Ou SM, Lee KH, Tsai MT, Tseng WC, Chu YC, Tarng DC. Sepsis and the risks 
of long-term renal adverse outcomes in patients with chronic kidney

# Page 12

Page 12 of 12
Takkavatakarn et al. Critical Care          (2024) 28:156 
disease. Front Med. 2022;9: 809292. https://​doi.​org/​10.​3389/​fmed.​2022.​
809292.
	7.	
Neyra JA, Mescia F, Li X, et al. Impact of acute kidney injury and CKD 
on adverse outcomes in critically Ill septic patients. Kidney Int Rep. 
2018;3(6):1344–53. https://​doi.​org/​10.​1016/j.​ekir.​2018.​07.​016.
	8.	
Khwaja A. KDIGO clinical practice guidelines for acute kidney injury. 
Nephron Clin Pract. 2012;120(4):c179–84. https://​doi.​org/​10.​1159/​00033​
9789.
	9.	
Chaudhary K, Vaid A, Duffy A, et al. Utilization of deep learning for 
subphenotype identification in sepsis-associated acute kidney injury. Clin 
J Am Soc Nephrol. 2020;15(11):1557–65. https://​doi.​org/​10.​2215/​CJN.​
09330​819.
	10.	 Gomez H, Kellum JA. Sepsis-induced acute kidney injury. Curr Opin 
Crit Care. 2016;22(6):546–53. https://​doi.​org/​10.​1097/​MCC.​00000​00000​
000356.
	11.	 Patil VP, Salunke BG. Fluid overload and acute kidney injury. Indian J Crit 
Care Med. 2020;24(Suppl 3):S94–7. https://​doi.​org/​10.​5005/​jp-​journ​
als-​10071-​23401.
	12.	 Yasrebi-de Kom IAR, Dongelmans DA, Abu-Hanna A, et al. Acute kidney 
injury associated with nephrotoxic drugs in critically ill patients: a mul‑
ticenter cohort study using electronic health record data. Clin Kidney J. 
2023. https://​doi.​org/​10.​1093/​ckj/​sfad1​60.
	13.	 Andrew BY, Pieper CF, Cherry AD, et al. Identification of trajectory-based 
acute kidney injury phenotypes among cardiac surgery patients. Ann 
Thorac Surg. 2022;114(6):2235–43. https://​doi.​org/​10.​1016/j.​athor​acsur.​
2021.​11.​047.
	14.	 Johnson A, Bulgarelli L, Pollard T, Horng S, Celi LA, Mark R. MIMIC-IV 
clinical database demo (version 2.2). PhysioNet. 2023. https://​doi.​org/​10.​
13026/​dp1f-​ex47.
	15.	 Johnson A PT, Badawi O, Raffa J. eICU collaborative research data‑
base demo (version 2.0.1). PhysioNet. 2021. https://​doi.​org/​10.​13026/​
4mxk-​na84.
	16.	 Singer M, Deutschman CS, Seymour CW, et al. The third international 
consensus definitions for sepsis and septic shock (sepsis-3). JAMA. 
2016;315(8):801–10.
	17.	 Raith EP, Udy AA, Bailey M, et al. Australian and New Zealand Intensive 
Care Society (ANZICS) Centre for Outcomes and Resource Evaluation 
(CORE). Prognostic Accuracy of the SOFA Score, SIRS Criteria, and qSOFA 
Score for in-hospital mortality among adults with suspected infection 
admitted to the intensive care unit. JAMA. 2017;317(3):290–300. https://​
doi.​org/​10.​1001/​jama.​2016.​20328.
	18.	 Kamaleswaran R, Lian J, Lin DL, et al. Predicting volume responsiveness 
among sepsis patients using clinical data and continuous physiological 
waveforms. AMIA Annu Symp Proc. 2020;2020:619–28.
	19.	 Reyna MA, Josef CS, Jeter R, et al. Early prediction of sepsis from clinical 
data: The PhysioNet/computing in cardiology challenge 2019. Crit Care 
Med. 2020;48(2):210–7. https://​doi.​org/​10.​1097/​CCM.​00000​00000​004145.
	20.	 Moor M, Bennett N, Plecko D, et al. Predicting sepsis using deep learning 
across international sites: a retrospective development and validation 
study. EClinicalMedicine. 2023;62: 102124. https://​doi.​org/​10.​1016/j.​
eclinm.​2023.​102124.
	21.	 Li X, Wu R, Zhao W, et al. Machine learning algorithm to predict mortality 
in critically ill patients with sepsis-associated acute kidney injury. Sci Rep. 
2023;13(1):5223. https://​doi.​org/​10.​1038/​s41598-​023-​32160-z.
	22.	 Chawla LS, Bellomo R, Bihorac A, et al. Acute kidney disease and renal 
recovery: consensus report of the Acute Disease Quality Initiative (ADQI) 
16 Workgroup. Nat Rev Nephrol. 2017;13(4):241–57. https://​doi.​org/​10.​
1038/​nrneph.​2017.2.
	23.	 Goswami E, Ogden RK, Bennett WE, et al. Evidence-based development 
of a nephrotoxic medication list to screen for acute kidney injury risk 
in hospitalized children. Am J Health Syst Pharm. 2019;76(22):1869–74. 
https://​doi.​org/​10.​1093/​ajhp/​zxz203.
	24.	 Peerapornratana S, Priyanka P, Wang S, et al. Sepsis-associated acute kid‑
ney disease. Kidney Int Rep. 2020;5(6):839–50. https://​doi.​org/​10.​1016/j.​
ekir.​2020.​03.​005.
	25.	 Zarbock A, Nadim MK, Pickkers P, et al. Sepsis-associated acute kidney 
injury: consensus report of the 28th acute disease quality initiative 
workgroup. Nat Rev Nephrol. 2023;19(6):401–17. https://​doi.​org/​10.​1038/​
s41581-​023-​00683-3.
	26.	 Zavada J, Hoste E, Cartin-Ceba R, et al. A comparison of three methods to 
estimate baseline creatinine for RIFLE classification. Nephrol Dial Trans‑
plant. 2010;25(12):3911–8. https://​doi.​org/​10.​1093/​ndt/​gfp766.
	27.	 Zhang Z, Zhang G, Goyal H, Mo L, Hong Y. Identification of subclasses of 
sepsis that showed different clinical outcomes and responses to amount 
of fluid resuscitation: a latent profile analysis. Crit Care. 2018;22(1):347. 
https://​doi.​org/​10.​1186/​s13054-​018-​2279-3.
	28.	 Gong K, Lee HK, Yu K, Xie X, Li J. A prediction and interpretation frame‑
work of acute kidney injury in critical care. J Biomed Inform. 2021;113: 
103653. https://​doi.​org/​10.​1016/j.​jbi.​2020.​103653.
	29.	 Park N, Kang E, Park M, et al. Predicting acute kidney injury in cancer 
patients using heterogeneous and irregular data. PLoS ONE. 2018;13(7): 
e0199839. https://​doi.​org/​10.​1371/​journ​al.​pone.​01998​39.
	30.	 Sterne JA, White IR, Carlin JB, et al. Multiple imputation for missing data 
in epidemiological and clinical research: potential and pitfalls. BMJ. 
2009;338:b2393. https://​doi.​org/​10.​1136/​bmj.​b2393.
	31.	 Proust-Lima C, Philipps V, Liquet B. Estimation of extended mixed models 
using latent classes and latent processes: the R package lcmm. J Stat 
Softw. 2015. https://​doi.​org/​10.​18637/​jss.​v078.​i02.
	32.	 Weller B, Bowen N, Faubert S. Latent class analysis: a guide to best prac‑
tice. J Black Psychol. 2020;46.
	33.	 R Core Team: A language and environment for statistical computing. 
Vienna, Austria. URL [R version 4.2.2 for Windows https://​www.R-​proje​ct.​
org/: R Foundation for Statistical Computing October 2022.
	34.	 Bhatraju PK, Mukherjee P, Robinson-Cohen C, et al. Acute kidney injury 
subphenotypes based on creatinine trajectory identifies patients at 
increased risk of death. Crit Care. 2016;20(1):372. https://​doi.​org/​10.​1186/​
s13054-​016-​1546-4.
	35.	 Kellum JA, Sileanu FE, Bihorac A, Hoste EA, Chawla LS. Recovery after 
acute kidney injury. Am J Respir Crit Care Med. 2017;195(6):784–91. 
https://​doi.​org/​10.​1164/​rccm.​201604-​0799OC.
	36.	 Gameiro J, Marques F, Lopes JA. Long-term consequences of acute kid‑
ney injury: a narrative review. Clin Kidney J. 2021;14(3):789–804. https://​
doi.​org/​10.​1093/​ckj/​sfaa1​77.
	37.	 Su CC, Chen JY, Chen SY, et al. Outcomes associated with acute kidney 
disease: a systematic review and meta-analysis. EClinicalMedicine. 
2023;55: 101760. https://​doi.​org/​10.​1016/j.​eclinm.​2022.​101760.
	38.	 Bhatraju PK, Zelnick LR, Herting J, et al. Identification of acute kidney 
injury subphenotypes with differing molecular signatures and responses 
to vasopressin therapy. Am J Respir Crit Care Med. 2019;199(7):863–72. 
https://​doi.​org/​10.​1164/​rccm.​201807-​1346OC.
Publisher’s Note
Springer Nature remains neutral with regard to jurisdictional claims in pub‑
lished maps and institutional affiliations.
