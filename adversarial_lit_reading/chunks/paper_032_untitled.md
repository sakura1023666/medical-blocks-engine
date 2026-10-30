# Page 1

Received: 7 November 2025
Revised: 17 February 2026
Accepted: 19 February 2026
DOI: 10.1002/alz.71300
R E S E A R C H A R T I C L E
Circadian syndrome (CircS) and cognitive trajectory
deterioration in middle-aged and older adults: A national
cohort study with causal forest analysis
Jiangping Ma1,2
Nan Chen1,2
Jingxuan Huang1,2
Linghao Xu3
Huifang Shang1,2
1Department of Neurology, Laboratory of
Neurodegenerative Disorders, Rare Disease
Center, West China Hospital, Sichuan
University, Chengdu, China
2National Clinical Research Center for
Geriatric, West China Hospital, Sichuan
University, Chengdu, China
3Department of Endocrinology and
Metabolism, the Affiliated Hospital of
Southwest Medical University, Luzhou,
Sichuan, China
Correspondence
Huifang Shang, Department of Neurology,
West China Hospital, Sichuan University,
Guoxuexiang 37#, Wuhou District, Chengdu
610041, Sichuan Province, China.
Email: hfshang2002@126.com
Jiangping Ma and Nan Chen contributed to the
work equally and should be regarded as
co-first authors.
Funding information
Sichuan Science and Technology Program,
Grant/Award Number: 2022ZDZX0023
Abstract
INTRODUCTION: Cognitive impairment is a global health challenge. Circadian syn-
drome (CircS) extends beyond metabolic syndrome to include sleep and mental health,
but its long-term impact on cognitive trajectories remains unclear.
METHODS: We analyzed 6218 participants from the China Health and Retirement
Longitudinal Study (2011–2018). CircS was defined as ≥4 of 7 components. Cogni-
tive trajectories were identified using latent class growth modeling. Associations were
assessed via multinomial logistic regression, and heterogeneous effects via causal
forest analysis.
RESULTS: Three cognitive trajectories were identified: “persistently high” (40.29%),
“persistently moderate” (43.78%), and “persistently low” (15.93%). CircS increased
odds of “persistently low” global cognitive (adjusted OR = 1.27, 95%CI:1.06–1.52) and
episodic memory (OR = 1.28, 95%CI:1.06–1.55) trajectories. Causal forest identified a
vulnerable subgroup: younger age, mild anemia (Hb∼95 g/L), and elevated BMI.
DISCUSSION: CircS is a significant, modifiable risk factor for adverse cognitive trajec-
tories. Screening for CircS could enable early identification and targeted interventions,
especially for the identified high-risk subgroup.
KEYWORDS
causal forest, circadian syndrome, cognitive trajectory, latent class growth model, longitudinal
study
Highlights
∙Novel integration of latent class growth modeling with causal forest machine
learning.
∙Circadian syndrome increases risk of unfavorable cognitive trajectories by 27%–
28%.
∙Identification of high-risk subgroup: younger age, mild anemia, elevated BMI.
∙First longitudinal evidence linking circadian syndrome to low cognitive trajectories.
∙Circadian syndrome as a modifiable target for early screening and prevention.
This is an open access article under the terms of the Creative Commons Attribution License, which permits use, distribution and reproduction in any medium, provided
the original work is properly cited.
© 2026 The Author(s). Alzheimer’s & Dementia published by Wiley Periodicals LLC on behalf of Alzheimer’s Association.
Alzheimer’s Dement. 2026;22:e71300.
wileyonlinelibrary.com/journal/alz
1 of 16
https://doi.org/10.1002/alz.71300

# Page 2

2 of 16
MA ET AL.
1
BACKGROUND
Cognitive impairment presents a growing global public health chal-
lenge, particularly for aging populations.1,2 As the demographic trend
shifts towards an older population structure, the prevalence of cog-
nitive impairment is rising.3 Given the current lack of curative treat-
ments, identifying modifiable risk factors for cognitive decline has
become a critical strategy for early intervention and prevention.4
Metabolic syndrome (MetS) refers to a cluster of concurrent
metabolic disorders, mainly including central obesity, hypertension,
hyperglycemia, and dyslipidemia.5 MetS is a well-established risk fac-
tors for cognitive impairment which is mediated through pathologic
changes in the brain, such as reduced brain volume, white matter
lesions, and vascular pathology.6–8 However, the conventional MetS
framework does not fully consider other critical risk factors associ-
ated with cognitive impairment, such as sleep disturbances and mental
health issues. To address this limitation, the concept of Circadian Syn-
drome (CircS) has been proposed as a more comprehensive disorder
characterized by disrupted biological rhythms. CircS encompasses all
components of MetS while also integrating additional factors such as
reduced sleep duration and depressive symptoms.9 There is an increas-
ing consensus that CircS serves as a superior predictor for a range
of cardiometabolic diseases compared to MetS alone.10,11 Impor-
tantly, this enhanced predictive utility extends to cognitive health, with
emerging evidence demonstrating a strong correlation between CircS
andcognitiveimpairment.12,13 Giventheestablishedindependentlinks
between sleep, depression and cognitive decline, these findings high-
light the potential of CircS as a more integrative and sensitive tool for
identifying individuals at high risk for future cognitive impairment.14,15
Furthermore, emerging evidence indicates that the association
between CircS and cognitive outcomes is not uniform but varies
substantially across subgroups. For instance, the detrimental effect of
CircS on dementia risk is significantly modified by APOE-ε4 genotype
and smoking status.16 In addition, female gender has been associated
with a more pronounced cognitive impairment related to CircS.12 This
heterogeneity suggests that individual susceptibility to the cognitive
consequences of circadian and metabolic dysregulation is influenced
by a complex interplay of genetic, lifestyle, and sociodemographic
factors.
Despite these advancements, the majority of previous research
focuses on snapshots of cognition at a certain point in time, rather
than its change over time. We still know little about how CircS influ-
ences the long-term trajectory of cognitive function in middle-aged
and elderly individuals. Because cognitive decline is a dynamic pro-
cess, understanding its trajectory is key for early intervention. The
investigation of cognitive trajectories has advanced by utilizing statis-
tics that can find different patterns of changes within a cohort. Many
high-quality longitudinal studies have demonstrated that cognitive tra-
jectories differ between subgroups and possess predictive value for
long-term prognosis, such as conversion to Alzheimer’s disease.17,18
Causal inference methodologies utilizing real-world data provide
valuable evidence complementary to randomized controlled trials. In
observational research, the investigation of heterogeneous treatment
effects (HTEs) is fundamental to personalized risk assessment. Wager
and Athey advanced this field by developing the causal forest model,
an extension of the random forest algorithm, to infer HTEs or condi-
tional average treatment effects (CATEs) from observational data. This
innovative approach estimates treatment effects tailored to individual
characteristics, enabling personalized causal inference.19
Traditional methods for assessing effect heterogeneity, such as
interaction terms or subgroup analysis, are often limited by multi-
collinearity, model dependence, or spurious findings.20–23 In contrast,
the causal forest method offers several advantages: it handles high-
dimensional covariates and complex interactions without pre-specified
parametric forms, automatically partitions data based on effect het-
erogeneity, provides valid confidence intervals (CI), and incorpo-
rates cross-fitting (“honesty”) and out-of-bag estimation to mitigate
overfitting.24–26
In this research, we undertook a nationally representative cohort
study utilizing four waves of data from the China Health and Retire-
ment Longitudinal Study (CHARLS) spanning 2011–2018, with the
objective of investigating the influence of CircS on cognitive aging.
Through the application of trajectory-based modeling and personal-
ized effect estimation, this study furnishes novel insights into the role
of CircS as a modifiable risk factor for cognitive decline and pro-
poses targeted prevention strategies for populations at heightened
risk.
2
METHODS
2.1
Study design and population
CHARLS constitutes an ongoing, nationally representative longitudi-
nal survey focusing on adults aged 45 years and older. The primary
objective of the study is to gather comprehensive data on sociode-
mographic characteristics, health status, medical conditions, family
structure, and health-related behaviors. Initiated in 2011, the CHARLS
survey has been conducted with follow-up assessments occurring bien-
nially or triennially. To date, CHARLS has produced four waves of
survey data collected in the years 2011, 2013, 2015, and 2018. The
research project received approval from the Biomedical Ethics Com-
mittee of Peking University (IRB00001052-11015). Informed consent
was obtained from all participants, who also consented to the sharing
of their data.
We employed data from the four waves of the CHARLS to identify
eligible participants according to specific inclusion and exclusion cri-
teria. Initially, individuals lacking diagnostic information for CircS at
the baseline year of 2011 were excluded. Subsequently, participants
with cognitive impairment or Parkinson’s disease/dementia at base-
line were also removed from the study. Additionally, individuals who
participated in fewer than two waves of cognitive assessment were
excluded. Ultimately, the study comprised 6218 subjects, consisting
of 3054 males and 3164 females. A comprehensive flowchart detail-
ing the study design and the inclusion and exclusion of participants is
provided in Figure S1.
 15525279, 2026, 3, Downloaded from https://alz-journals.onlinelibrary.wiley.com/doi/10.1002/alz.71300, Wiley Online Library on [24/04/2026]. See the Terms and Conditions (https://onlinelibrary.wiley.com/terms-and-conditions) on Wiley Online Library for rules of use; OA articles are governed by the applicable Creative Commons License

# Page 3

MA ET AL.
3 of 16
RESEARCH IN CONTEXT
1. Systematic review: We reviewed the literature using
PubMed and other traditional sources. Previous research
has established links between Metabolic Syndrome and
cognitive impairment. The novel concept of Circadian
Syndrome (CircS) extends this framework to include sleep
and mental health, with emerging evidence suggesting
its superior predictive value for cardiometabolic diseases
and cross-sectional cognitive status. However, longitudi-
nal evidence on how CircS influences long-term cognitive
trajectories was lacking.
2. Interpretation: Our findings demonstrate that CircS is
a significant risk factor for adverse long-term cognitive
trajectories, increasing the odds of a “persistently low”
trajectory by 27%–28%. Crucially, by applying causal for-
est analysis, we move beyond average population risks
to identify a vulnerable subgroup for whom this effect is
most pronounced: younger individuals with mild anemia
and elevated BMI. This establishes CircS as a comprehen-
sive, modifiable risk factor and underscores the necessity
for personalized cognitive risk assessment.
3. Future directions: Future research should: (a) elucidate
the precise biological mechanisms, particularly the non-
linear role of hemoglobin, linking CircS to neurodegen-
eration; (b) develop and test targeted interventions (e.g.,
circadian rhythm stabilization) through randomized con-
trolled trials in the identified high-risk subgroup; and (c)
validate these findings and the generalizability of the
high-risk profile in diverse ethnic and younger popula-
tions.
2.2
Assessment of CircS
Venous blood samples were promptly received by the Chinese Cen-
ter for Disease Control and Prevention in Beijing within two weeks
after leaving the CDC station. These samples were immediately stored
and frozen at −20◦C prior to delivery. After necessary analyses in
the laboratory of China Medical University, they were transferred
to a deep freezer and maintained at −80◦C. In the clinical labora-
tory of Youanmen, Capital Medical University, the concentrations of
biomarkers such as high-density lipoprotein cholesterol (HDL-C), low-
density lipoprotein cholesterol(LDL-C), triglycerides (TG), and glycated
hemoglobin (HbA1c) were measured using the enzyme colorimetric
method.12
Blood pressure was measured three times by trained nurses using
a sphygmomanometer, and the average value was calculated. Hyper-
tension was defined as systolic blood pressure ≥140 mmHg and/or
diastolic blood pressure ≥90 mmHg or the use of antihypertensive
medications.
The Center for Epidemiologic Studies Depression Scale (CES-D)
(10-item version) was employed to assess depressive symptoms.
Depression was defined as a CES-D score ≥10 points.13
Anthropometric measurements were conducted by trained staff.
Body weight was measured without shoes to an accuracy of 0.1 kg.
Height was measured using a vertical stadiometer to an accuracy
of 0.1 cm. Waist circumference was measured at the umbilical level
to an accuracy of 0.1 cm. Central obesity was defined as a waist
circumference ≥85 cm in men and ≥80 cm in women.
Sleep duration was evaluated through personal self-report. A sleep
duration of less than 6 h was classified as reduced sleep duration. It
is important to note that sleep health is a multidimensional construct
encompassing not only duration but also regularity, timing, efficiency,
and quality.27 The single-item measure of sleep duration used here,
while practical for large cohort studies and aligned with prior CircS
research, may not fully distinguish between efficient short sleep and
sleep disruption stemming from circadian misalignment.
The concept of CircS was initially derived from MetS and was
assessed based on the following seven components: reduced sleep
duration, depression, central obesity, elevated TG (≥150 mg/dL or
drug treatment for TG elevation), reduced high-density lipoprotein
(HDL < 40 mg/dL in men; HDL < 50 mg/dL in women; or drug
treatment for HDL-C reduction), hypertension, and elevated fasting
blood glucose (≥100 mg/dL or drug treatment for hyperglycemia).
Participants with four or more components were diagnosed with
CircS.
2.3
Assessment of cognitive function
Based on prior research utilizing CHARLS, cognitive function was
assessed using the Chinese adaptation of the Mini-Mental State Exami-
nation (MMSE), which evaluates two key dimensions: episodic memory
and mental intactness. Participants were presented with a list of 10
unrelated Chinese words and were required to recall them immedi-
ately (immediate word recall) and again after a four-minute interval
(delayed word recall). The episodic memory score was determined
by averaging the number of words recalled in both the immediate
and delayed tasks, with possible scores ranging from 0 to 10. The
assessment of mental status included tasks such as serial subtrac-
tion of 7 from 100 (up to five iterations), identifying the current date
(month, day, and year), naming the day of the week, recognizing the
current season, and completing an intersecting pentagon copying test.
Responses to these tasks were aggregated to form a mental intact-
ness score, which could range from 0 to 11. The overall cognitive score
was calculated by summing the scores for episodic memory and mental
intactness, yielding a total score range of 0–21.
2.4
Outcome-cognitive trajectories
The primary outcome was the trajectory of global cognitive scores, and
the second outcomes were the trajectory of episodic memory and men-
 15525279, 2026, 3, Downloaded from https://alz-journals.onlinelibrary.wiley.com/doi/10.1002/alz.71300, Wiley Online Library on [24/04/2026]. See the Terms and Conditions (https://onlinelibrary.wiley.com/terms-and-conditions) on Wiley Online Library for rules of use; OA articles are governed by the applicable Creative Commons License

# Page 4

4 of 16
MA ET AL.
tal intactness scores. Latent class growth model (LCGM) was used to
determine the heterogeneity of cognitive trajectories. LCGM was uti-
lized to identify homogeneous clusters of individuals who follow similar
developmental trajectories across time.28
2.5
Covariates
Interviewers systematically gathered and documented data on
sociodemographic
characteristics,
health-related
behaviors,
and
medical information utilizing structured questionnaires. The sociode-
mographic variables encompassed age, gender (categorized as male
or female), educational attainment (classified as primary school or
below, junior high school to high school, and undergraduate or above),
marital status (dichotomized into married and unmarried), and place of
residence (rural or urban). Within the marital status classification, indi-
viduals identified as “married with spouse present” and “married but
not living with spouse” were grouped under “married,” whereas those
identified as “separated,” “divorced,” “widowed,” or “never married”
were categorized as “unmarried.” Health-related behaviors assessed
included smoking status (yes or no) and alcohol consumption status
(yes or no). The medical information collected comprised data on
functional restrictions, self-reported visual and hearing impairments,
history of stroke, and heart disease, which included conditions such
as heart attack, coronary heart disease, angina pectoris, congestive
heart failure, or other cardiac issues. Additionally, measurements
of hemoglobin levels and body mass index (BMI) were recorded.
Functional restriction was operationally defined as experiencing
limitations in any of the five activities of daily living (ADL), namely
bathing, dressing, eating, transferring in and out of bed, and toileting.
BMI was calculated as the weight in kilograms divided by the square of
the height in meters and was categorized as follows: <18.5, 18.5–23.9,
24.0–27.9, and ≥28.0 kg/m2.
2.6
Statistical analysis
Continuousnormallydistributedvariablesweredescribedusingmeans
and standard deviations. Non-normally distributed continuous vari-
ables were described using medians and interquartile ranges. Cate-
gorical variables were described using frequencies and percentages.
one-way analysis of variance, rank sum tests, or chi-square tests were
used to compare baseline differences between groups.
2.6.1
Identification of cognitive trajectories
To capture the heterogeneity in cognitive change over time, we identi-
fied distinct cognitive trajectories using the LCGM. This method groups
individuals into homogeneous subpopulations (latent classes) that
share similar developmental paths of global cognitive scores across the
study waves. Age in years was used as the timescale. We tested models
with 2–5 trajectory classes, employing both linear and quadratic func-
tions. The optimal number and shape of trajectories were determined
based on the following criteria29: (1) the lowest sample size-adjusted
Bayesian information criterion (SABIC); (2) an average posterior prob-
ability of assignment (AvePP) for each trajectory class greater than 0.7,
indicating adequate class separation; and (3) each trajectory class com-
prising no less than 5% of the total sample to ensure clinical relevance.
Detailed statistical methods were provided in the Supplementary File:
Supplementary Method 1.
2.6.2
Association analysis between CircS and
cognitive trajectories
Multinomial logistic regression model was used to estimate the associ-
ation of Circs with the trajectories of the cognitive function measures.
Odds ratios (OR) and the corresponding 95% CI were reported. To
preliminarily assess potential effect modification and to examine the
consistency of the CircS-cognitive trajectory association across key
demographic and clinical subgroups, we performed stratified analy-
ses by each of the following baseline covariates: sex (male, female),
age group (<60, ≥60 years), residence (urban, rural), educational level
(primary school or below, junior high school to high school, undergrad-
uate or above), marital status (married, unmarried), smoking status
(yes/no), drinking status (yes/no), BMI category (<18.5, 18.5–23.9,
24.0–27.9, ≥28.0 kg/m2), history of stroke (yes/no), history of heart
disease (yes/no), ADL restriction (yes/no), visual impairment (yes/no),
hearing impairment (yes/no), and hemoglobin level (split at the median
into high/low groups). These stratified analyses served a dual purpose:
(1) as an initial, descriptive exploration of heterogeneity in associa-
tion strength across subgroups, and (2) as robustness checks to ensure
the primary association was not driven by a specific subpopulation.
Subsequently, to formally test for statistically significant effect mod-
ification, we introduced multiplicative interaction terms (e.g., CircS ×
sex, CircS × age group) individually into the fully adjusted multinomial
logistic regression model. The significance of the interaction term was
assessed using the likelihood ratio test.
2.6.3
Causal forest analysis
To further investigate the HTEs of CircS on cognitive trajectories, we
employed a causal forest machine learning approach. We constructed
three separate causal forest models for each cognitive trajectory out-
come (persistently low, moderate, and high). The analysis included 14
pre-specified covariates: age, gender, residence, education, marital sta-
tus, smoking, drinking, heart disease, stroke, hemoglobin, BMI, visual
impairment, hearing impairment, and ADL ability. Each forest com-
prised 10,000 trees and utilized honest estimation (50% of the data for
splitting, 50% for estimation) to minimize overfitting.
We assessed model calibration and estimated the average treat-
ment effect (ATE) alongside Individual Treatment Effects (ITEs) to
quantify effect heterogeneity. Variable importance was analyzed to
identify key moderators of the CircS effect on cognitive trajectories.
 15525279, 2026, 3, Downloaded from https://alz-journals.onlinelibrary.wiley.com/doi/10.1002/alz.71300, Wiley Online Library on [24/04/2026]. See the Terms and Conditions (https://onlinelibrary.wiley.com/terms-and-conditions) on Wiley Online Library for rules of use; OA articles are governed by the applicable Creative Commons License

# Page 5

MA ET AL.
5 of 16
All analyses were performed using R version 4.4.2 with the grf pack-
age, and a random seed was set for reproducibility. Sensitivity analyses
with fewer trees were used to confirm the robustness of our results.
Detailed statistical methods were provided in the Supplementary File:
Supplementary Method 2.
2.6.4
Sensitivity analysis
1. Inverse Probability Weighting (IPW): We conducted IPW analysis
to address potential confounding and validate our primary find-
ings. Propensity scores were estimated using logistic regression
with CircS as the outcome and all baseline covariates as predictors.
Stabilized weights were applied to create a balanced pseudo-
population. Weighted multinomial logistic regression was used to
estimate the association between CircS and cognitive trajectories.
2. Linear Mixed-Effects Models (LMMs): We fitted LMMs to directly
model the repeated measures of global cognitive scores as a con-
tinuous outcome over time. This approach treats cognitive decline
as a continuous process and does not presuppose the existence of
discrete trajectory classes. The core model included fixed effects
for CircS status (present/absent), time (in years from baseline),
and their interaction term (CircS × Time). A significant interac-
tion term would indicate that the rate of cognitive decline (slope)
differs between individuals with and without CircS. The models
were adjusted for the same set of baseline covariates used in the
multinomial logistic regression.
3. Continuous CircS Score Analysis: As an additional sensitivity analy-
sis, we examined the association between a continuous CircS score
(range: 0–7) and cognitive trajectories using multinomial logistic
regression. This approach treats CircS as a dimensional construct
rather thana categorical diagnosis, allowing ustoinvestigate poten-
tial dose–response relationships. Both crude and fully adjusted
models were fitted using the same covariate sets as the primary
binary analysis.
4. Sensitivity Analysis with Additional Covariates: To further address
concerns regarding potential residual confounding, an extended
sensitivity analysis was performed. The original set of covari-
ates was supplemented with five additional baseline variables
for model refitting: physical activity level (categorized as low,
moderate, or high), frequency of social activities (categorized
as none, moderate, or high), use of sleep medication (yes/no),
use of antidepressant medication (yes/no), and habitual nap-
ping. Both the multinomial logistic regression models and the
causal forest analysis were repeated using this extended covariate
set.
5. Sensitivity Analysis Using Multiple Imputation: To assess potential
selection bias arising from missing CircS data at baseline, we con-
ducted a sensitivity analysis using multiple imputation. All missing
components defining CircS, along with other baseline covariates,
were imputed. The complete analytical workflow—including cog-
nitive trajectory identification, multinomial logistic regression, and
causal forest analysis—was then performed on the imputed data.
The pooled results were compared to the primary complete-case
analysis to evaluate the robustness of the findings.
6. Sensitivity Analysis Examining Collinearity and a Modified CircS
Definition: To further assess the robustness of BMI as a poten-
tial effect moderator, two supplementary analyses were con-
ducted. First, variance inflation factors (VIFs) were calculated for
all covariates in the causal forest model to examine potential
multicollinearity. Second, we repeated the primary causal forest
analysis using a modified CircS definition, which excluded the
central obesity component. In this analysis, CircS was defined
as the presence of ≥3 out of the remaining 6 components. All
other model specifications were kept identical to the primary
analysis.
2.6.5
Extended analysis
We conducted an extended analysis using person-specific rates of cog-
nitive change as the outcome. For each participant, a linear regression
model was fitted with the global cognitive score as the dependent vari-
able and time since baseline (in years) as the independent variable. The
individual-specific slope from this model represented the rate of cogni-
tive change. Participants were then classified into a binary transition
outcome: “Cognitive Decline” (slope < 0) versus “Cognitive Stability
or Improvement” (slope ≥0). The association between CircS and this
binary transition outcome was examined using a logistic regression
model, adjusted for the same baseline covariates as in the primary anal-
ysis. A causal forest analysis was subsequently performed to estimate
the heterogeneous effects of CircS on the risk of “Cognitive Decline.”
The above statistical analyses were conducted using SPSS 25.0 and
R 4.4.2. A two-sided p-value < 0.05 indicated a significant result.
3
RESULTS
3.1
Population characteristics
In the study, from the initial cohort of 17,708 participants in
CHARLS at baseline, individuals lacking CircS information (n = 7313)
were excluded. Subsequently, participants with cognitive impairment
(n = 678, Figure S2 presents the age-specific corresponding cog-
nitive impairment thresholds) or diagnosed with Parkinson’s dis-
ease/dementia (n = 91) were also excluded. Additionally, those with
fewer than two waves of cognitive assessment data (n = 3408) were
removed from the analysis. Ultimately, the final analytical sample
comprised 6218 subjects. Figure S1 illustrates the study design and
provides a detailed flowchart of inclusion and exclusion criteria of
participants.
Table 1 summarizes the baseline characteristics of the included par-
ticipants. The mean age of the sample was 57.35 years (SD = 8.65),
with 3054 (49.1%) being male. Statistically significant differences were
observed in the age, sex, place of residence, educational level, marital
status, smoking and drinking history, ADL ability, BMI, history of stroke
 15525279, 2026, 3, Downloaded from https://alz-journals.onlinelibrary.wiley.com/doi/10.1002/alz.71300, Wiley Online Library on [24/04/2026]. See the Terms and Conditions (https://onlinelibrary.wiley.com/terms-and-conditions) on Wiley Online Library for rules of use; OA articles are governed by the applicable Creative Commons License

# Page 6

6 of 16
MA ET AL.
TABLE 1
Baseline characteristics (described based on the presence or absence of circadian syndrome).
Variable
All (N = 6218)
No CircS (N = 4079)
CircS (N = 2139)
p.overall
Age (years), mean ± SD
57.35 ± 8.65
57.05 ± 8.67
57.91 ± 8.59
0.0002
Sex, n (%)
<0.0001
Male sex
3054 (49.1%)
2254 (55.3%)
800 (37.4%)
Female sex
3164 (50.9%)
1825 (44.7%)
1339 (62.6%)
Residence, n (%)
Urban
2186 (35.2%)
1362 (33.4%)
824 (38.5%)
0.0001
Rural
4032 (64.8%)
2717 (66.6%)
1315 (61.5%)
Educational level, n (%)
Below primary school
4137 (66.5%)
2641 (64.7%)
1496 (69.9%)
0.0002
Secondary to vocational school
2024 (32.6%)
1400 (34.3%)
624 (29.2%)
University and above
57 (0.9%)
38 (0.9%)
19 (0.9%)
Marital status, n (%)
Unmarried
483 (7.8%)
262 (6.4%)
221 (10.3%)
<0.0001
Married
5735 (92.2%)
3817 (93.6%)
1918 (89.7%)
Smoking status, n (%)
No
3715 (59.7%)
2267 (55.6%)
1448 (67.7%)
<0.0001
Yes
2503 (40.3%)
1812 (44.4%)
691 (32.3%)
Drinking status, n (%)
No
3729 (60.0%)
2311 (56.7%)
1418 (66.3%)
<0.0001
Yes
2489 (40.0%)
1768 (43.3%)
721 (33.7%)
Restriction on ADL, n (%)
No
5453 (87.7%)
3680 (90.2%)
1773 (82.9%)
<0.0001
Yes
765 (12.3%)
399 (9.8%)
366 (17.1%)
History of stroke, n (%)
No
6104 (98.2%)
4021 (98.6%)
2083 (97.4%)
0.0012
Yes
114 (1.8%)
58 (1.4%)
56 (2.6%)
Heart disease, n (%)
Yes
620 (10.0%)
329 (8.1%)
291 (13.6%)
<0.0001
No
5598 (90.0%)
3750 (91.9%)
1848 (86.4%)
BMI (kg/m2), n (%)
<18.5
343 (5.5%)
312 (7.6%)
31 (1.4%)
<0.0001
18.5–23.9
3235 (52.0%)
2503 (61.4%)
732 (34.2%)
24.0–27.9
1915 (30.8%)
990 (24.3%)
925 (43.2%)
≥28.0
725 (11.7%)
274 (6.7%)
451 (21.1%)
Visual impairment, n (%)
No
5876 (94.5%)
3879 (95.1%)
1997 (93.4%)
0.0052
Yes
342 (5.5%)
200 (4.9%)
142 (6.6%)
Hearing impairment, n (%)
No
5796 (93.2%)
3820 (93.7%)
1976 (92.4%)
0.0658
Yes
422 (6.8%)
259 (6.3%)
163 (7.6%)
Hb (g/L), mean ± SD
90.58 ± 8.53
90.83 ± 8.63
90.10 ± 8.31
0.0013
SD: standard deviation; BMI: body mass index; Hb: Hemoglobin; CircS: Circadian syndrome.
 15525279, 2026, 3, Downloaded from https://alz-journals.onlinelibrary.wiley.com/doi/10.1002/alz.71300, Wiley Online Library on [24/04/2026]. See the Terms and Conditions (https://onlinelibrary.wiley.com/terms-and-conditions) on Wiley Online Library for rules of use; OA articles are governed by the applicable Creative Commons License

# Page 7

MA ET AL.
7 of 16
FIGURE 1
UpSet plot displaying the frequency and combinations of the seven components defining circadian syndrome (Sleep↓, reduced
sleep duration; Glu↑, elevated fasting blood glucose; HDL↓, reduced high-density lipoprotein; TG↑, elevated triglycerides; BP↑, hypertension; CO,
central obesity).
and heart disease, Visual impairment, and hemoglobin levels between
participants with and without CircS.
The co-occurrence patterns of the seven CircS components are pre-
sented in Figure 1. The most frequent combinations involved central
obesity with other metabolic components, while the combination of
reduced sleep duration and depressive symptoms co-occurred in a
distinct subgroup.
Figure S3 presents the distribution of global cognitive scores at
baseline.
3.2
Estimated cognitive aging trajectories
We evaluated the optimal number of cognitive function trajectories
necessary to account for the variability in global cognitive scores within
this population (refer to Table S1). The BIC was lowest for the model
comprising four trajectories (BIC = 96,886.26); however, the average
posterior probability for this model was below 0.7. Consequently, we
determined that the GBTM approach with three trajectories was the
most suitable. Figure 2 illustrates three longitudinal patterns of cogni-
tive function, categorized by current age at each assessment, based on
global cognitive scores: Class 1, “Persistently High” (n = 2505, 40.29%);
Class 2, “Persistently Moderate” (n = 2722, 43.78%); and Class 3, “Per-
sistently Low” (n = 991, 15.93%). The trajectories for cognitive function
domains are presented in the Figure S4.
FIGURE 2
Mean trajectories of global cognitive scores by
increasing age among participants.
3.3
Trajectory sub-population characteristics
As illustrated in Table S2, the baseline characteristics are pre-
sented in accordance with global cognitive trajectories. A range
of significant statistical differences were identified in the age,
gender, place of residence, educational attainment, marital status,
smoking history, drinking history, ADL ability, BMI, hearing impair-
ment, and visual impairment among the three cognitive trajectory
groups.
 15525279, 2026, 3, Downloaded from https://alz-journals.onlinelibrary.wiley.com/doi/10.1002/alz.71300, Wiley Online Library on [24/04/2026]. See the Terms and Conditions (https://onlinelibrary.wiley.com/terms-and-conditions) on Wiley Online Library for rules of use; OA articles are governed by the applicable Creative Commons License

# Page 8

8 of 16
MA ET AL.
TABLE 2
Multinomial logistic regression analysis for the associations of CircS with the membership to cognitive function trajectory group.
Persistently low (vs. persistently high)
Persistently moderate (vs. persistently high)
OR (95% CI)*
p value
OR (95% CI)*
p value
Global cognitive scores
Crude model
1.40[1.20–1.63]
<0.001
1.08[0.96–1.21]
0.189
Adjusted model*
1.27[1.06–1.52]
0.009
1.10[0.97–1.26]
0.132
Mental intactness scores
Crude model
1.31[1.11–1.55]
0.002
1.14[1.02–1.28]
0.026
Adjusted model*
1.18[0.97–1.43]
0.099
1.09[0.96–1.25]
0.195
Episodic memory scores
Crude model
1.21[1.02–1.43]
0.027
1.10[0.95–1.28]
0.209
Adjusted model*
1.28[1.06–1.55]
0.012
1.14[0.96–1.35]
0.135
95%CI: 95% confidence interval;
*Adjusted for age at baseline (continuous), gender (male, female), education (primary school or below, junior high school to high school, undergraduate or
above), marital status (married, unmarried), residence (urban, rural), smoking (yes, no), drinking (yes, no), body mass index (<18.5, 18.5–23.9, 24.0–27.9,
≥28.0 kg/m2), restriction on activities of daily living (yes, no), visual impairment (yes, no), hearing impairment (yes, no), stroke (yes, no), heart disease (yes, no),
and hemoglobin (continuous).
3.4
Associations between CircS and cognitive
trajectories
The distribution of cognitive trajectories, stratified by CircS status, is
depicted in Figure S5. A chi-square test revealed a significant asso-
ciation between CircS status and cognitive trajectory membership
(p < 0.001). Visually, individuals with CircS were proportionally more
likely to belong to the “Persistently Low” trajectory and less likely to
belong to the “Persistently High” trajectory compared to those with-
out CircS. This preliminary unadjusted association necessitated further
investigation using multivariable-adjusted models.
Table 2 presents the findings from the multinomial regression
analysis examining the association between CircS and cognitive tra-
jectory membership. Compared to participants without CircS, adults
with CircS exhibited poorer cognitive trajectories, with multivariable-
adjusted OR and 95% CI for the “Persistently Low” trajectories of
global cognitive function being 1.27 [1.06–1.52]. Similarly, adults with
CircS demonstrated worse cognitive trajectories, with multivariable-
adjusted OR (95% CI) for the “Persistently Low” trajectories of episodic
memory being 1.28 [1.06–1.55].
Comprehensive analyses of interactions identified several signifi-
cant effect modifiers across various cognitive domains and trajectory
comparisons. In terms of global cognitive trajectories, significant inter-
actions were detected between CircS and education level (p = 0.0276)
in the comparison between “persistently low” and “persistently high”
trajectories, as well as between CircS and drinking status (p = 0.0167)
in the comparison between “persistently moderate” and “persistently
high” trajectories (see Figure 3). Regarding domain-specific trajecto-
ries, episodic memory (refer to Figure S6) exhibited significant inter-
actions with drinking status (p = 0.0337) and heart disease (p = 0.04)
in the comparison between “persistently low” and “persistently high”
trajectories, while mental intactness (refer to Figure S7) showed a sig-
nificant interaction with heart disease (p = 0.0309) in the comparison
between “persistently moderate” and “persistently high” trajectories.
These findings indicate that the cognitive effects of CircS are influ-
enced by distinct factors depending on the specific cognitive domain
and the severity of the trajectory.
3.5
Casual forest analysis
We employed causal forest analysis to estimate the HTEs of CircS on
distinct cognitive trajectories. The analysis included 6218 participants
with 2139 individuals diagnosed with CircS and 4079 controls.
3.5.1
ATEs
The ATE of CircS varied across different cognitive trajectories
(Figure 4A). For the persistently low cognitive trajectory, the ATE was
0.029 (95% CI: 0.007–0.051), indicating a statistically significant asso-
ciation. The persistently moderate cognitive trajectory showed an ATE
of −0.002 (95% CI: −0.031 to 0.028), while the persistently high cog-
nitive trajectory demonstrated an ATE of −0.029 (95% CI: −0.057 to
−0.002).
3.5.2
Heterogeneity of treatment effects
Substantial heterogeneity in ITEs was observed in persistently low
cognitive trajectory (Figure 4A). The standard deviation of ITEs for per-
sistently low cognitive trajectory was 0.0247, ranging from −0.0639 to
0.1063. The standard deviation of ITEs for persistently moderate cog-
nitive trajectory was 0.0429, ranging from −0.1994 to 0.1478 (Figure
S8). The standard deviation of ITEs for persistently high cognitive
trajectory was 0.0431, ranging from −0.2279 to 0.1454 (Figure S8).
 15525279, 2026, 3, Downloaded from https://alz-journals.onlinelibrary.wiley.com/doi/10.1002/alz.71300, Wiley Online Library on [24/04/2026]. See the Terms and Conditions (https://onlinelibrary.wiley.com/terms-and-conditions) on Wiley Online Library for rules of use; OA articles are governed by the applicable Creative Commons License

# Page 9

MA ET AL.
9 of 16
FIGURE 3
Stratified analysis of the association between circadian syndrome and global cognitive trajectory membership across all covariates,
with interaction p-values.
FIGURE 4
Heterogeneous treatment effects of circadian syndrome on cognitive trajectories: (A) causal forest analysis of circadian syndrome
effects on cognitive trajectories; (B) the predictive impact of circadian syndrome on persistently low cognitive trajectories and its relationship with
age, hemoglobin level, ADL ability, hearing impairment, and body mass index.
3.5.3
Variable importance in treatment effect
heterogeneity
Variable importance analysis identified key moderators of treatment
effect heterogeneity for persistently low cognitive trajectory risk
(Figure 4A). The most influential variables were: (1) Hemoglobin
(Hb)—Importance score: 0.287; (2) Age—Importance score: 0.252; (3)
BMI—Importance score: 0.236; (4) ADL—Importance score: 0.058; (5)
Hearing impairment (Deaf)—Importance score: 0.030. These variables
accounted for the majority of heterogeneity in how CircS affects cog-
 15525279, 2026, 3, Downloaded from https://alz-journals.onlinelibrary.wiley.com/doi/10.1002/alz.71300, Wiley Online Library on [24/04/2026]. See the Terms and Conditions (https://onlinelibrary.wiley.com/terms-and-conditions) on Wiley Online Library for rules of use; OA articles are governed by the applicable Creative Commons License

# Page 10

10 of 16
MA ET AL.
nitive decline risk. Variable importance analysis also identified key
moderators of treatment effect heterogeneity for persistently mod-
erate and high cognitive trajectories. The top three variables were
similarly BMI, Hb, and Age (see Figure S8).
3.5.4
Relationship between predicted treatment
effects and individual characteristics
The analysis of HTEs revealed distinct patterns between predicted
effect of CircS and key individual characteristics for persistently low
cognitive trajectory (Figure 4B). The visualization clearly demarcated
high-effect (predicted risk increase > 0) and low-effect (predicted risk
increase ≤0) subgroups across all covariate distributions.
A moderate negative correlation was observed between age and
treatment effects (r = −0.33), indicating that older individuals derived
significantly less treatment effects from CircS. The treatment effects
showed a clear decreasing trend with advancing age, with the high-
est treatment effects observed in younger participants. While the
simple linear correlation between Hb and the CircS effect was negli-
gible (r = 0.01), the causal forest model, capable of capturing complex,
nonlinear dependencies, identified Hb as the most important modera-
tor (variable importance score: 0.287). This apparent discrepancy was
resolved by visualizing the relationship, which uncovered a distinct
U-shaped pattern. Specifically, the treatment effects of CircS on persis-
tently low cognitive trajectory were most pronounced for individuals
with Hb levels concentrated in a mild-anemia range (approximately
95 g/L), whereas those at both the lower and upper extremes of the
Hb distribution exhibited relative resilience. This nonlinear pattern
underscores that Hb remains a variable of paramount importance
in moderating the cognitive impact of CircS, even in the absence
of a strong linear association, and highlights a specific “metabolic-
vulnerable” phenotypic window at middling Hb levels. A weak negative
correlation emerged between ADL, hearing impairment and influence
(r = −0.05), with a slight tendency for individuals without ADL ability
or with hearing impairment to experience greater treatment effects
against cognitive decline. A weak positive correlation was observed
between BMI and the ITE of CircS (r = 0.07), suggesting a tendency
for individuals with a higher BMI to experience a slightly greater detri-
mental effect from CircS on the risk of a persistently low cognitive
trajectory.
Supplementary analyses examined the heterogeneity of CircS
effects on the “persistently moderate” and “persistently high” cognitive
trajectories (Figure S9). Interpretation of the “persistently moderate”
trajectory was limited, as it was defined relative to both the high
and low trajectory classes. For the “persistently high” trajectory, the
moderating effect of age was minimal (r = −0.02), indicating that
the adverse association between CircS and maintaining high cogni-
tive function was largely consistent across the studied age range. Hb
exhibited a near U-shaped relationship with the CircS effect, with peak
susceptibility observed around 95 g/L, consistent with findings from
the low-trajectory analysis. BMI also showed a U-shaped moderating
effect, with the strongest negative effect of CircS on maintaining a
high trajectory occurring at approximately 24 kg/m2. While this pat-
tern is not fully aligned with the low-trajectory results, it underscores
the importance of maintaining a normal BMI for cognitive health.
3.5.5
Robustness and calibration
Model calibration tests confirmed adequate fit for all three cognitive
trajectories. The heterogeneity coefficients were 1.01 (p = 0.01) for the
persistently low cognitive trajectory, 0.82 (p = 0.24) for the persistently
moderate cognitive trajectory, and 0.98 (p = 0.01) for the persistently
high cognitive trajectory. Sensitivity analyses using reduced tree num-
bers (5000 trees) yielded consistent results, with ATE differences of
0.0001, 0.0007, and 0.0005 for the low, moderate, and high cognitive
trajectories, respectively.
3.6
Sensitivity analysis
3.6.1
IPW
The IPW analysis demonstrated adequate covariate balance after
weighting, with all standardized mean differences below 0.1 (Figure
S10). The distribution of inverse probability weights showed appropri-
ate specification with minimal extreme weights (Figure S11).
In the weighted analysis, the association between CircS and cogni-
tive trajectories remained consistent with our primary findings. For the
low versus high trajectory comparison, the weighted OR was 1.31 (95%
CI: 1.08–1.56). For the moderate versus high trajectory comparison,
the weighted OR was 1.09 (95% CI: 0.96–1.25). The distribution of cog-
nitive trajectories before and after weighting demonstrated successful
balancing of the study population (Figure S12).
These IPW results confirm the robustness of our primary multino-
mial logistic regression findings, providing additional evidence for the
association between CircS and unfavorable cognitive trajectories.
3.6.2
LMMs
The sensitivity analysis using LMMs revealed distinct patterns of cog-
nitive decline associated with CircS status over time (Figure S13). We
observed significant interaction effects between CircS and age for both
global cognitive scores (β = −0.02, p = 0.003) and episodic memory
(β = −0.01, p = 0.02), indicating that the presence of CircS was asso-
ciated with an accelerated rate of cognitive decline in these domains as
age increased.
In contrast, no significant interaction was found between CircS and
age for mental intactness scores (β = −0.01, p = 0.054), suggesting that
the decline in this cognitive domain might follow a similar trajectory
regardless of CircS status.
Visual inspection of the predicted trajectories clearly demonstrates
that participants with CircS (red line) exhibited steeper declines in
globalcognitionandepisodicmemorycomparedtothosewithoutCircS
 15525279, 2026, 3, Downloaded from https://alz-journals.onlinelibrary.wiley.com/doi/10.1002/alz.71300, Wiley Online Library on [24/04/2026]. See the Terms and Conditions (https://onlinelibrary.wiley.com/terms-and-conditions) on Wiley Online Library for rules of use; OA articles are governed by the applicable Creative Commons License

# Page 11

MA ET AL.
11 of 16
FIGURE 5
Dose–response relationships between continuous circadian syndrome score and global cognitive trajectory.
(blue line). This pattern was consistent with our primary analyses using
trajectory modeling.
3.6.3
Continuous CircS score analysis
When analyzing CircS as a continuous variable, we observed differ-
ences from the primary binary analysis (Table S3). For the low versus
high trajectory comparison, each one-unit increase in the CircS score
was associated with a 16% increase in odds (adjusted OR = 1.16, 95%
CI: 1.05–1.18), consistent with the direction of our primary analysis but
suggesting a more graded dose–response relationship.
Importantly, for the moderate versus high trajectory comparison,
the continuous analysis did not reveal a statistically significant associ-
ation in the primary binary analysis. Each unit increase in CircS score
was associated with a 7% increase in odds of belonging to the mod-
erate versus high trajectory (adjusted OR = 1.07, 95% CI: 1.03–1.11).
This finding suggests that the binary classification of CircS may have
limited sensitivity to detect more subtle associations with intermediate
cognitive outcomes, and that circadian dysregulation operates along a
continuum in its relationship with cognitive trajectories (Figure 5).
3.6.4
Sensitivity analysis with additional covariates
After adjusting for additional covariates, the associationbetweenCircS
and the “persistently low” global cognitive trajectory remained signif-
icant, with an adjusted odds ratio of 1.31 (95% CI: 1.09–1.57; Table
S4). In the causal forest analysis, the ATE of CircS on the “persistently
low” trajectory was 0.0312 (95% CI: 0.0111–0.0513) [Table S5]. The
distributions of ITEs are detailed in Table S5 and Figure S14. Variable
importance analysis (Figure S14) identified Hb, BMI, and age as the
top three moderators for the “persistently low” trajectory, consistent
with the primary analysis. Physical activity emerged as the fourth most
important variable. The relationships of predicted ITEs with Hb, BMI,
and age in “persistently low” trajectory (Figure S15) remained simi-
lar to those in the primary analysis. A weak positive correlation was
observed between physical activity and the ITEs in in “persistently low”
trajectory (r = 0.09).
3.6.5
Sensitivity analysis using multiple imputation
To evaluate the potential influence of selection bias due to missing
baseline CircS data, analyses were repeated using multiple imputation.
The trajectory patterns identified in the imputed data were similar to
the primary analysis (Figure S16). In the adjusted multinomial logis-
tic regression model, CircS remained associated with the “persistently
low” global cognitive trajectory (adjusted OR = 1.13, 95% CI: 1.01–
1.26; Table S6). Results from the causal forest analysis on the imputed
data are summarized in Table S7. The ATE of CircS on the “persistently
low” trajectory was 0.0209 (95% CI: 0.0096–0.0322).
Variable importance analysis (Figure S17) indicated that age, Hb,
and BMI remained the three most influential moderators of the CircS
effect across trajectories. The relationships between predicted ITEs
and Hb and BMI in “persistently low” global cognitive trajectory (Figure
S18) were consistent with the primary findings. However, the relation-
ship with age differed, exhibiting a U-shaped pattern in the imputed
data, with higher treatment effects observed in both younger and older
individuals.
 15525279, 2026, 3, Downloaded from https://alz-journals.onlinelibrary.wiley.com/doi/10.1002/alz.71300, Wiley Online Library on [24/04/2026]. See the Terms and Conditions (https://onlinelibrary.wiley.com/terms-and-conditions) on Wiley Online Library for rules of use; OA articles are governed by the applicable Creative Commons License

# Page 12

12 of 16
MA ET AL.
3.6.6
Sensitivity analysis examining collinearity
and a modified CircS definition
We conducted two additional sensitivity analyses to examine the
robustness of our findings regarding BMI as an effect moderator. First,
VIFs for all covariates, including CircS and BMI, were calculated. All
VIFs were below 5, indicating no substantial multicollinearity (Figure
S19).
Second, we repeated the causal forest analysis using a modified def-
inition of CircS that excluded the central obesity component. CircS
was redefined as having ≥3 of the remaining 6 components. The
association between this modified CircS and the “persistently low” cog-
nitive trajectory remained significant, with an ATE of 0.0336 (95%
CI: 0.0147–0.0525). Hemoglobin, age, and BMI were again identi-
fied as the top three moderators of this effect (Figures S20,21), and
their moderating patterns were basically consistent with the primary
analysis.
3.7
Extended analysis
In the extended analysis of cognitive transitions, the association
between CircS and cognitive decline yielded an adjusted odds ratio
of 1.04 (95% CI: 0.92–1.17; Table S8). The causal forest analy-
sis yielded an ATE of 0.0010 (95% CI: −0.0273 to 0.0294). Sub-
stantial heterogeneity in ITEs was observed (SD = 0.0397; range:
−0.0994 to 0.169; Figure S22). Variable importance analysis identified
BMI, hemoglobin, and age as the three most influential moderators,
and their effect modification patterns (Figure S23) were similar to
those observed for the “persistently low” trajectory in the primary
analysis.
4
DISCUSSION
This longitudinal study demonstrates that CircS is significantly asso-
ciated with unfavorable cognitive trajectories among middle-aged
and older Chinese adults. After multivariable adjustment, individ-
uals with CircS had a 27% higher risk of a “persistently low”
global cognitive trajectory and a 28% higher risk of a “persistently
low” episodic memory trajectory. Importantly, by utilizing LCGM, we
showed that CircS predicts distinct long-term cognitive aging pat-
terns, moving beyond prior cross-sectional evdience.13 These findings
were consistent in the sensitivity analyses, the latter confirming
accelerated decline in global cognitive function among individuals
with CircS. Additionally, causal forest analysis revealed substan-
tial heterogeneity in the effect of CircS, moderated primarily by
hemoglobin levels, age, and BMI. Collectively, our findings estab-
lish CircS as a comprehensive and potent risk factor for cognitive
decline.
4.1
Mechanisms between CircS and cognitive
trajectory deterioration
1. Pathophysiological mechanism:
The pathway through which CircS contributes to cognitive decline
initiates with the dysregulation of clock genes, such as
BMAL1 and PER.30–32 This disruption directly compromises
neuronal plasticity and synaptic functionality. Subsequently,
it induces the activation of microglial cells, which release
pro-inflammatory mediators, including IL-6 and TNF-α, and
results in the accumulation of mitochondrial reactive oxygen
species (ROS).33,34 Concurrently, metabolic and cerebrovas-
cular dysfunctions impair cerebral blood flow perfusion and
compromise the integrity of the blood–brain barrier, culminat-
ing in white matter lesions and microinfarcts.35 Additionally,
abnormal melatonin secretion diminishes its neuroprotec-
tive effects against oxidative stress and Aβ aggregation.36,37
Ultimately, sleep disturbances hinder the glymphatic sys-
tem’s ability to clear metabolic waste products, such as
Aβ and tau, leading to the accumulation of neurodegenera-
tive pathologies.38,39 These processes are intricately linked
through CircS disruptions and collectively exacerbate cogni-
tive decline.
1. Psychological and Behavioral Mechanisms:
In addition to the biological pathways, the link between CircS and
adverse cognitive trajectories may also involve behavioral and
psychological pathways. Depressive symptoms may serve as
a crucial mediator. Depression is frequently associated with
apathy, diminished motivation, and anhedonia, which can lead
to decreased participation in cognitively stimulating activi-
ties and social interactions—critical components of cognitive
reserve.40–42
4.2
Heterogeneity analysis
Causal forest analysis demonstrated significant heterogeneity in the
influence of CircS on cognitive trajectories, identifying hemoglobin,
age, and BMI as key moderators. Unlike conventional regression
approaches, our machine learning method quantified individual-level
variations and identified a high-treatment-effect subgroup: younger
individuals with mild-anemia hemoglobin levels (approximately 95 g/L)
and elevated BMI.
Hemoglobin emerged as the most influential moderator, exhibit-
ing a distinct nonlinear relationship with the effects of CircS. Rather
than a simple linear association, a U-shaped or threshold effect was
observed: the most pronounced adverse effects of CircS were concen-
 15525279, 2026, 3, Downloaded from https://alz-journals.onlinelibrary.wiley.com/doi/10.1002/alz.71300, Wiley Online Library on [24/04/2026]. See the Terms and Conditions (https://onlinelibrary.wiley.com/terms-and-conditions) on Wiley Online Library for rules of use; OA articles are governed by the applicable Creative Commons License

# Page 13

MA ET AL.
13 of 16
trated among individuals within an intermediate range of hemoglobin
concentration (approximately 95 g/L), while those at both lower and
higher extremes demonstrated relative resilience. This complex pat-
ternindicatesthepresenceofdistinctunderlyingpathophysiology.Low
hemoglobin may contribute to cognitive impairment primarily through
chronic cerebral hypoxia43–47—a parallel risk pathway—whereas the
concentration of risk in the middle range may signify a “metabolically-
vulnerable” phenotype. In these individuals, subclinical vascular dys-
function and low-grade inflammation, core components of CircS, likely
converge to induce cognitive damage without being severe enough to
manifest as overt anemia.
Age emerged as the second most significant moderator, exhibiting
an unexpected direction of effect. Our analysis revealed a negative
correlation between age and the ITE of CircS, suggesting that the
adverse impact on cognitive decline was more pronounced among
younger individuals. This observation may imply the presence of a
critical period in mid-life during which the intersection of circadian,
metabolic, and affective disturbances represented by CircS could
trigger a more rapid and potentially less reversible pathological pro-
gression, thereby establishing a trajectory for accelerated long-term
decline.9,48–52 Alternatively, this pattern could reflect a selective sur-
vival bias, wherein the oldest-old participants who remain in the study
are inherently more resilient.
BMI was also a significant moderator, a finding that requires care-
ful interpretation. It is important to distinguish the role of BMI as a
moderator from central obesity as a diagnostic component of CircS.
While central obesity specifically reflects abdominal visceral fat, a key
driver of cardiometabolic risk within CircS, BMI serves as a broader,
composite indicator of overall body composition and metabolic load. It
captures not only adiposity but also aspects of nutritional status and
chronic, low-grade systemic inflammation—factors implicated in neu-
roinflammation and cognitive decline through pathways distinct from,
though often concomitant with, abdominal fat accumulation.53–56
Therefore, BMI may represent a dimension of generalized metabolic
vulnerability that extends beyond the specific criterion of central obe-
sity. The observed moderating effect of BMI likely operates through
these extended pathways, which may interact synergistically with
circadian dysfunction to exacerbate cognitive decline. For instance,
elevated BMI frequently coincides with a state of “metabolically
unhealthy obesity,” characterized by insulin resistance and altered
adipokine secretion—conditions that are themselves both causes and
consequences of circadian disruption.57–60 This bidirectional relation-
ship suggests a vicious cycle wherein circadian misalignment and
metabolic dysfunction mutually reinforce each other, creating a com-
pounded risk for neural integrity. In this context, BMI emerges not
merely as a correlate of abdominal obesity but as a clinically accessi-
ble marker of this integrated, pathological network. Thus, its role as
an effect modifier likely reflects a distinct layer of metabolic suscep-
tibility that influences an individual’s resilience or vulnerability to the
cognitive impacts of CircS.
4.3
Clinical implications
Our findings have significant implications for clinical practice and
public health initiatives aimed at preserving cognitive function. This
longitudinal study demonstrates that CircS predicts the “persistently
low” cognitive trajectory. Furthermore, a dose–response relationship
was observed, wherein a higher CircS score increased the risk of
belonging to the persistently low cognitive trajectory. The identifi-
cation of CircS as a strong predictor of adverse cognitive outcomes
highlights its potential as a clinically actionable screening tool. In pri-
mary care and geriatric settings, evaluating the composite CircS profile
could enable the early identification of middle-aged and older adults
at elevated risk for persistent cognitive decline, thereby facilitat-
ing timely interventions before substantial neurodegeneration occurs.
Moreover, the heterogeneity revealed by our causal forest analysis
strongly supports a stratified and personalized prevention approach.
Specifically, individuals with mild anemia (hemoglobin levels around
95 g/L) and those in the younger middle-age bracket emerge as pri-
ority subgroups who may benefit most from targeted management
of their circadian and metabolic health. Potential interventions may
encompass lifestyle modifications aimed at aligning circadian rhythms,
such as scheduled light exposure and consistent meal and sleep rou-
tines, as well as strategies for metabolic enhancement. Future research
ought to prioritize the development and rigorous evaluation of these
multifaceted interventions, with a particular emphasis on conducting
randomized controlled trials. Such studies are essential to ascertain
whether addressing components of CircS factors can effectively slow
cognitive decline in identified high-risk populations.
4.4
Strength and limitation
This study possesses several methodological strengths. First, the uti-
lization of a large, nationally representative cohort with four waves
of longitudinal data allowed us to move beyond cross-sectional snap-
shots and model the dynamic nature of cognitive change, providing a
more robust assessment of the exposure–outcome relationship.61,62
Second, our application of LCGM was pivotal in capturing the inherent
heterogeneity in cognitive aging, identifying distinct subpopulations
with “persistently low,” “moderate,” and “high” trajectories that would
be obscured by analyzing the population average alone.63,64 Third,
we complemented this group-based trajectory analysis with a cutting-
edge machine learning technique—causal forest analysis—to estimate
ITEs. This advanced method allowed us to quantify the substantial
heterogeneity in how CircS affects cognitive trajectories and to iden-
tify key moderators and a high-risk subgroup, thereby providing a
foundation for personalized risk assessment.65,66
Several limitations should be considered when interpreting our find-
ings. First, the observational design inherently limits causal inference,
despite robust sensitivity analyses. Factors like social engagement may
 15525279, 2026, 3, Downloaded from https://alz-journals.onlinelibrary.wiley.com/doi/10.1002/alz.71300, Wiley Online Library on [24/04/2026]. See the Terms and Conditions (https://onlinelibrary.wiley.com/terms-and-conditions) on Wiley Online Library for rules of use; OA articles are governed by the applicable Creative Commons License

# Page 14

14 of 16
MA ET AL.
have bidirectional relationships with CircS, complicating full adjust-
ment. Furthermore, the lack of objective measures for conditions like
sleep apnea in CHARLS means residual confounding cannot be ruled
out. Thus, our findings, while robust, cannot fully satisfy the assump-
tion of no unmeasured confounding. Second, the assessment of key
CircS components, particularly sleep and depressive symptoms, relied
on self-reports, which may introduce measurement bias. This limita-
tion is especially pertinent for the sleep component. Our definition
used sleep duration alone (<6 h), a metric that does not capture other
core dimensions of sleep health (e.g., regularity, timing).27 Since short
sleep can arise from diverse causes (e.g., behavior, natural phenotype)
not specific to circadian dysfunction,67–69 our measure may lead to
misclassification and potentially underestimate the true association
between circadian disruption and cognitive trajectories. Future stud-
ies should employ multidimensional sleep assessments or circadian
biomarkers to better define this component of the syndrome. Third, the
generalizability of our findings may be limited to middle-aged and older
Chinese adults, and replication in other ethnic and younger populations
is needed. Finally, the conceptual overlap between BMI and the cen-
tral obesity component of CircS complicates the interpretation of BMI
as a distinct moderator. Although sensitivity analyses indicated that
BMI’s moderating role persists even when central obesity is excluded
from the syndrome definition, BMI likely reflects correlated metabolic
features of the exposure.
5
CONCLUSION
This study illustrates CircS significantly elevates the risk of adverse
cognitive trajectories among Chinese middle-aged and older adults.
Individuals with CircS exhibited a 27% increased risk of persistent
global cognitive decline and a 28% increased risk of poor episodic
memory trajectory. Causal forest analysis revealed considerable het-
erogeneity in individual susceptibility, identifying a high-treatment-
effect subgroup characterized by younger age, mid-anemia hemoglobin
levels, and elevated BMI. These findings establish CircS as a signifi-
cant and modifiable risk factor for cognitive trajectory deterioration.
Incorporating circadian health assessments into clinical practice could
facilitate the early identification of at-risk individuals, particularly
those exhibiting the identified risk profile. Future research should
prioritize the development of targeted interventions that address cir-
cadian disruption and its metabolic correlates to mitigate cognitive
consequences in vulnerable populations.
AUTHOR CONTRIBUTIONS
Jiangping Ma: Study design, data collection, formal analysis, visual-
ization, and writing an original draft. Nan Chen: Study design, data
collection, formal analysis, visualization, and writing an original draft.
Jingxuan Huang: Data collection, formal analysis, and writing an
original draft. Linghao Xu: Writing an original draft. Huifang Shang:
Supervision, project administration, writing a review & editing. All
authors read and approved the final manuscript.
ACKNOWLEDGMENTS
The authors would like to sincerely thank all the members of CHALRS
for their valuable contributions and the participants who provided data
for this study. This work was supported by the Sichuan Science and
Technology Program (Grant No. 2022ZDZX0023).
FUNDING INFORMATION
This work was supported by the Sichuan Science and Technology
Program (Grant No. 2022ZDZX0023).
CONFLICT OF INTEREST STATEMENT
The authors declare no conflicts of interest. Author disclosures are
available in the supporting information.
DATA AVAILABILITY STATEMENT
The datasets utilized in this investigation are available in online reposi-
tories. The names of the repository and the accession number(s) can be
found at the following link: http://charls.pku.edu.cn/en.
ETHICAL APPROVAL
The protocol received approval from the Ethical Review Committee
of Peking University (approval numbers: IRB00001052-11015 for the
main household survey and IRB00001052-11014 for biomarker col-
lection). The study was conducted in compliance with the Declaration
of Helsinki principles. All participants signed the informed consent
and repository consent that permitted their data to be shared after
a detailed presentation of the risks and benefits related to study
participation.
REFERENCES
1. Rookes T, Frost R, Barrado-Martin Y, et al. Type of goals set and
progress towards these goals, as part of a behaviour change interven-
tion, in people with mild cognitive impairment: a secondary analysis.
Lancet. 2023;402(Suppl 1):S80. doi:10.1016/s0140-6736(23)02112-
8
2. Jamil Y, Krishnaswami A, Orkaby AR, et al. The impact of cog-
nitive impairment on cardiovascular disease. J Am Coll Cardiol.
2025;85(25):2472-2491. doi:10.1016/j.jacc.2025.04.057
3. GBD 2023 Demographics Collaborators. Global age-sex-specific all-
cause mortality and life expectancy estimates for 204 countries
and territories and 660 subnational locations, 1950-2023: a demo-
graphic analysis for the global burden of disease study 2023. Lancet.
2025;406(10513):1731-1810. doi:10.1016/s0140-6736(25)01330-3
4. Burns DK, Alexander RC, Welsh-Bohmer KA, et al. Safety and effi-
cacy of pioglitazone for the delay of cognitive impairment in peo-
ple at risk of Alzheimer’s disease (TOMMORROW): a prognostic
biomarker study and a phase 3, randomised, double-blind, placebo-
controlled trial. Lancet Neurol. 2021;20(7):537-547. doi:10.1016/
s1474-4422(21)00043-0
5. Neeland IJ, Lim S, Tchernof A, et al. Metabolic syndrome. Nat Rev Dis
Primers. 2024;10(1):77. doi:10.1038/s41572-024-00563-5
6. Ng TP, Feng L, Nyunt MS, et al. Metabolic syndrome and the risk
of mild cognitive impairment and progression to dementia: follow-
up of the Singapore longitudinal ageing study cohort. JAMA Neurol.
2016;73(4):456-463. doi:10.1001/jamaneurol.2015.4899
7. Qureshi D, Topiwala A, Al Abid SU, Allen NE, Kuźma E, Littlejohns TJ.
Association of metabolic syndrome with neuroimaging and cognitive
 15525279, 2026, 3, Downloaded from https://alz-journals.onlinelibrary.wiley.com/doi/10.1002/alz.71300, Wiley Online Library on [24/04/2026]. See the Terms and Conditions (https://onlinelibrary.wiley.com/terms-and-conditions) on Wiley Online Library for rules of use; OA articles are governed by the applicable Creative Commons License

# Page 15

MA ET AL.
15 of 16
outcomes in the UK Biobank. Diabetes Care. 2024;47(8):1415-1423.
doi:10.2337/dc24-0537
8. Wang W, Li J, Cui S, et al. Microglial Ffar4 deficiency pro-
motes
cognitive
impairment
in
the
context
of
metabolic
syndrome.
Sci
Adv.
2024;10(5):eadj7813.
doi:10.1126/sciadv.
adj7813
9. Zimmet P, Alberti K, Stern N, et al. The circadian syndrome: is the
metabolic syndrome and much more!. J Intern Med. 2019;286(2):181-
191. doi:10.1111/joim.12924
10. Shi Z, Tuomilehto J, Kronfeld-Schor N, et al. The circadian syndrome
is a significant and stronger predictor for cardiovascular disease
than the metabolic syndrome-the NHANES survey during 2005-2016.
Nutrients. 2022;14(24):5317. doi:10.3390/nu14245317
11. Shi Z, Tuomilehto J, Kronfeld-Schor N, et al. The circadian syndrome
predicts cardiovascular disease better than metabolic syndrome in
Chinese adults. J Intern Med. 2021;289(6):851-860. doi:10.1111/joim.
13204
12. Liu Y, Zang B, Shao J, Ning N, He L, Ma Y. Predictor of cognitive
impairment: metabolic syndrome or circadian syndrome. BMC Geriatr.
2023;23(1):408. doi:10.1186/s12877-023-03996-x
13. Shi Z, Stern N, Liu J, et al. The circadian syndrome is a predic-
tor for cognition impairment in middle-aged adults: comparison with
the metabolic syndrome. Diabetes/Metab Res Rev. 2024;40(5):e3827.
doi:10.1002/dmrr.3827
14. Sharon O, Zhelezniakov V, Gat Y, et al. Slow wave synchrony
during NREM sleep tracks cognitive impairment in prodromal
Alzheimer’s
disease.
Alzheimers
Dement.
2025;21(5):e70247.
doi:10.1002/alz.70247
15. Ismail Z, Elbayoumi H, Fischer CE, et al. Prevalence of depres-
sion in patients with mild cognitive impairment: a systematic review
and meta-analysis. JAMA Psychiatry. 2017;74(1):58-67. doi:10.1001/
jamapsychiatry.2016.3162
16. Yu L, Liu W, Liao C, et al. The interaction between circadian syndrome
and genetic susceptibility in the risk of incident dementia: a longitu-
dinal cohort study. J Prev Alzheimers Dis. 2025;12(5):100089. doi:10.
1016/j.tjpad.2025.100089
17. Burnham SC, Bourgeat P, Doré V, et al. Clinical and cognitive tra-
jectories in cognitively healthy elderly individuals with suspected
non-Alzheimer’s disease pathophysiology (SNAP) or Alzheimer’s dis-
ease pathology: a longitudinal study. Lancet Neurol. 2016;15(10):1044-
1053. doi:10.1016/s1474-4422(16)30125-9
18. Devanarayan V, Donohue MC, Sperling RA, et al. Multimodal prog-
nostic modeling of individual cognitive trajectories to enhance
trial efficiency in preclinical Alzheimer’s disease. Alzheimers Dement.
2025;21(9):e70702. doi:10.1002/alz.70702
19. Wang T, Keil AP, Kim S, et al. Iterative causal forest: a novel algorithm
for subgroup identification. Am J Epidemiol. 2024;193(5):764-776.
doi:10.1093/aje/kwad219
20. Elek P, Bíró A. Regional differences in diabetes across Europe—
regression and causal forest analyses. Econ Hum Biol. 2021;40:100948.
doi:10.1016/j.ehb.2020.100948
21. Petticrew M, Tugwell P, Kristjansson E, Oliver S, Ueffing E, Welch
V. Damned if you do, damned if you don’t: subgroup analysis and
equity. J Epidemiol Community Health. 2012;66(1):95-98. doi:10.1136/
jech.2010.121095
22. Assmann SF, Pocock SJ, Enos LE, Kasten LE. Subgroup analysis and
other (mis)uses of baseline data in clinical trials. Lancet (Lond Engl).
2000;355(9209):1064-1069. doi:10.1016/s0140-6736(00)02039-0
23. Elston DM. Selection bias. J Am Acad Dermatol. 2019;S0190-
9622(19):32775-32776.
doi:10.1016/j.jaad.2019.09.
031
24. Baum A, Scarpa J, Bruzelius E, Tamler R, Basu S, Faghmous J. Target-
ing weight loss interventions to reduce cardiovascular complications
of type 2 diabetes: a machine learning-based post-hoc analysis of
heterogeneous treatment effects in the Look AHEAD trial. lancet Dia-
betes Endocrinol. 2017;5(10):808-815. doi:10.1016/s2213-8587(17)
30176-6
25. Marafino BJ, Schuler A, Liu VX, Escobar GJ, Baiocchi M. Predicting pre-
ventable hospital readmissions with causal machine learning. Health
Serv Res. 2020;55(6):993-1002. doi:10.1111/1475-6773.13586
26. Bonander C, Svensson M. Using causal forests to assess heterogene-
ity in cost-effectiveness analysis. Health Econ. 2021;30(8):1818-1832.
doi:10.1002/hec.4263
27. Buysse DJ. Sleep health: can we define it? does it matter?. Sleep.
2014;37(1):9-17. doi:10.5665/sleep.3298
28. Song M, Hu FB, Wu K, et al. Trajectory of body shape in early and mid-
dle life and all cause and cause specific mortality: results from two
prospective US cohort studies. BMJ. 2016;353:i2195. doi:10.1136/
bmj.i2195
29. Tein JY, Coxe S, Cham H. Statistical power to detect the cor-
rect number of classes in latent profile analysis. Struct Equ Model.
2013;20(4):640-657. doi:10.1080/10705511.2013.824781
30. Maiese K. Cognitive impairment and dementia: gaining insight through
circadian clock gene pathways. Biomolecules. 2021;11(7):1002. doi:10.
3390/biom11071002
31. Hui Y, Zhong Y, Kuang L, et al. O-GlcNAcylation of circadian clock
protein Bmal1 impairs cognitive function in diabetic mice. Embo J.
2024;43(22):5667-5689. doi:10.1038/s44318-024-00263-6
32. Chen M, Zhang L, Shao M, et al. E4BP4 coordinates circadian control
of cognition in delirium. Adv Sci (Weinh). 2022;9(23):e2200559. doi:10.
1002/advs.202200559
33. Huang SY, Yang ZJ, Cheng J, et al. Choline alleviates cognitive impair-
ment in sleep-deprived young mice via reducing neuroinflammation
and altering phospholipidomic profile. Redox Biol. 2025;81:103578.
doi:10.1016/j.redox.2025.103578
34. d’Avila JC, Siqueira LD, Mazeraud A, et al. Age-related cognitive
impairment is associated with long-term neuroinflammation and
oxidative stress in a mouse model of episodic systemic inflammation. J
Neuroinflammation. 2018;15(1):28. doi:10.1186/s12974-018-1059-y
35. Oue H, Yamazaki Y, Qiao W, et al. LRP1 in vascular mural cells modu-
lates cerebrovascular integrity and function in the presence of APOE4.
JCI Insight. 2023;8(7):e163822. doi:10.1172/jci.insight.163822
36. Wang X, Wang Z, Cao J, Dong Y, Chen Y. Gut microbiota-derived
metabolites mediate the neuroprotective effect of melatonin in
cognitive impairment induced by sleep deprivation. Microbiome.
2023;11(1):17. doi:10.1186/s40168-022-01452-3
37. Hu Y, Lv Y, Long X, Yang G, Zhou J. Melatonin attenuates chronic
sleep deprivation-induced cognitive deficits and HDAC3-Bmal1/clock
interruption. CNS Neurosci Ther. 2023;30(3):e14474. doi:10.1111/cns.
14474
38. Sun H, Cao Q, He X, et al. Melatonin mitigates sleep restriction-
induced cognitive and glymphatic dysfunction via Aquaporin-4
polarization. Mol Neurobiol. 2025;62(9):11443-11465. doi:10.1007/
s12035-025-04992-5
39. Chen Y, Guo H, Sun X, et al. Melatonin regulates glymphatic function
to affect cognitive deficits, behavioral issues, and blood-brain barrier
damage in mice after intracerebral hemorrhage: potential links to cir-
cadian rhythms. CNS Neurosci Ther. 2025;31(2):e70289. doi:10.1111/
cns.70289
40. HorneSJ,ToppTE,QuigleyL.Depressionandthewillingnesstoexpend
cognitive and physical effort for rewards: a systematic review. Clin
Psychol Rev. 2021;88:102065. doi:10.1016/j.cpr.2021.102065
41. Jelsma E, Zhang A, Goosby BJ, Cheadle JE. Sympathetic arousal
among
depressed
college
students:
examining
the
interplay
between
psychopathology
and
social
activity.
Psychophysiology.
2024;61(9):e14597. doi:10.1111/psyp.14597
42. Hung YC, Lao WL, Yeh CJ, MC Lee. The mediating effect of leisure
activities in the relationship between depression and cognitive decline
in middle age and older adults in Taiwan. BMC Geriatr. 2023;23(1):315.
doi:10.1186/s12877-023-03984-1
 15525279, 2026, 3, Downloaded from https://alz-journals.onlinelibrary.wiley.com/doi/10.1002/alz.71300, Wiley Online Library on [24/04/2026]. See the Terms and Conditions (https://onlinelibrary.wiley.com/terms-and-conditions) on Wiley Online Library for rules of use; OA articles are governed by the applicable Creative Commons License

# Page 16

16 of 16
MA ET AL.
43. Qin T, Yan M, Fu Z, et al. Association between anemia and cogni-
tive decline among Chinese middle-aged and elderly: evidence from
the China health and retirement longitudinal study. BMC Geriatr.
2019;19(1):305. doi:10.1186/s12877-019-1308-7
44. Wolters FJ, Zonneveld HI, Licher S, et al. Hemoglobin and ane-
mia in relation to dementia risk and accompanying changes on
brain
MRI.
Neurology.
2019;93(9):e917-e926.
doi:10.1212/wnl.
0000000000008003
45. Winchester LM, Newby D, Ghose U, et al. The relationship between
anaemia, haemoglobin levels, and cognitive function: evidence in two
population-based cohorts from India and the United States. Neurobiol
Dis. 2025;216:107112. doi:10.1016/j.nbd.2025.107112
46. Jung M, Zou L, Yu JJ, et al. Does exercise have a protective effect
on cognitive function under hypoxia? A systematic review with meta-
analysis. J Sport Health Sci. 2020;9(6):562-577. doi:10.1016/j.jshs.
2020.04.004
47. Winchester LM, Powell J, Lovestone S, Nevado-Holgado AJ. Red blood
cell indices and anaemia as causative factors for cognitive function
deficits and for Alzheimer’s disease. Genome Med. 2018;10(1):51.
doi:10.1186/s13073-018-0556-z
48. Duncan MJ. Interacting influences of aging and Alzheimer’s disease on
circadian rhythms. Eur J Neurosci. 2020;51(1):310-325. doi:10.1111/
ejn.14358
49. de Souza KA, Jackson M, Chen J, et al. Shift work schedules alter
immune cell regulation and accelerate cognitive impairment during
aging. J Neuroinflammation. 2025;22(1):4. doi:10.1186/s12974-024-
03324-z
50. Li P, Gao L, Gaba A, et al. Circadian disturbances in Alzheimer’s disease
progression: a prospective observational cohort study of community-
based older adults. Lancet Healthy Longev. 2020;1(3):e96-e105. doi:10.
1016/s2666-7568(20)30015-5
51. Hoyt KR, Obrietan K. Circadian clocks, cognition, and Alzheimer’s
disease: synaptic mechanisms, signaling effectors, and chronothera-
peutics. Mol Neurodegener. 2022;17(1):35. doi:10.1186/s13024-022-
00537-9
52. González HM, Tarraf W, Harrison K, et al. Midlife cardiovascular health
and 20-year cognitive decline: atherosclerosis risk in communities
study results. Alzheimer’s Dement: J Alzheimer’s Assoc. 2018;14(5):579-
589. doi:10.1016/j.jalz.2017.11.002
53. de A Boleti AP, de O Cardoso PH, F Frihling BE, E Silva PS, de Moraes
LFRN, Migliolo L. Adipose tissue, systematic inflammation, and neu-
rodegenerative diseases. Neural Regen Res. 2023;18(1):38-46. doi:10.
4103/1673-5374.343891
54. Barron AM, Tokunaga M, Zhang MR, Ji B, Suhara T, Higuchi M.
Assessment of neuroinflammation in a mouse model of obesity andβ-
amyloidosis using PET. J Neuroinflammation. 2016;13(1):221. doi:10.
1186/s12974-016-0700-x
55. Naomi R, Teoh SH, Embong H, et al. The role of oxidative stress and
inflammation in obesity and its impact on cognitive impairments-a
narrative review. Antioxidants (Basel). 2023;12(5):1071. doi:10.3390/
antiox12051071
56. Ghosh P, Fontanella RA, Scisciola L, et al. Obesity-induced neuronal
senescence: unraveling the pathophysiological links. Ageing Res Rev.
2024;101:102533. doi:10.1016/j.arr.2024.102533
57. Al Haj Ahmad RM, Ababneh NA, Al-Domi HA. Brain insulin resistance
as a mechanistic mediator links peripheral metabolic disorders with
declining cognition. Diabetes Metab Syndr. 2022;16(4):102468. doi:10.
1016/j.dsx.2022.102468
58. Cadena M, Barreto GE. Exploring the interplay between circadian
rhythms and obesity: a Boolean network approach to understand-
ing metabolic dysregulation. PloS One. 2025;20(9):e0331218. doi:10.
1371/journal.pone.0331218
59. Lejawa M, Osadnik K, Czuba Z, Osadnik T, Pawlas N. Association of
metabolically healthy and unhealthy obesity phenotype with markers
related to obesity, diabetes among young, healthy adult men. analy-
sis of MAGNETIC study. Life (Basel Switz). 2021;11(12):1350. doi:10.
3390/life11121350
60. Sripetchwandee J, Chattipakorn N, Chattipakorn SC. Links between
obesity-induced brain insulin resistance, brain mitochondrial dysfunc-
tion, and dementia. Front Endocrinol. 2018;9:496. doi:10.3389/fendo.
2018.00496
61. Li C, Bai C, Wang L, et al. Association between healthy lifestyle
and cognitive decline, all-cause mortality, and mortality from cardio-
vascular and cerebrovascular diseases: a 10-year population-based
prospective cohort study. Alzheimer’s Dement: J Alzheimer’s Assoc.
2025;21(3):e70021. doi:10.1002/alz.70021
62. Cantuaria ML, Waldorff FB, Wermuth L, et al. Residential exposure to
transportation noise in Denmark and incidence of dementia: national
cohort study. BMJ (Clin Res Ed). 2021;374:n1954. doi:10.1136/bmj.
n1954
63. Li H, Li C, Wang A, et al. Associations between social and intellectual
activities with cognitive trajectories in Chinese middle-aged and older
adults: a nationally representative cohort study. Alzheimer’s Res Ther.
2020;12(1):115. doi:10.1186/s13195-020-00691-6
64. de Vos BC, Runhaar J, Verkleij SP, van Middelkoop M, Bierma-Zeinstra
SM. Latent class growth analysis successfully identified subgroups of
participants during a weight loss intervention trial. J Clin Epidemiol.
2014;67(8):947-951. doi:10.1016/j.jclinepi.2014.03.007
65. Mori Y, Komura T, Adomi M, et al. Heterogeneous cardiovascular
effects of SGLT2 inhibitors in type 2 diabetes: a causal forest and tar-
get trial emulation study. Eur J Prev Cardiol. 2025;33(1):80-88. doi:10.
1093/eurjpc/zwaf539
66. Liu M, Xu Z, He L, et al. Heterogeneous effects of obesity on all-
cause mortality: a causal forest analysis of hospitalized patients
in China. Diabetes Obes Metab. 2025;27(7):3695-3704. doi:10.1111/
dom.16391
67. Wheaton AG, Jones SE, Cooper AC, Croft JB. Short sleep dura-
tion among middle school and high school students—United States,
2015. MMWR Morb Mortal Wkly Rep. 2018;67(3):85-90. doi:10.15585/
mmwr.mm6703a1
68. Ashbrook LH, Krystal AD, Fu YH, Ptáˇcek LJ. Genetics of the
human circadian clock and sleep homeostat. Neuropsychopharmacol-
ogy. 2020;45(1):45-54. doi:10.1038/s41386-019-0476-7
69. Johnson KA, Gordon CJ, Chapman JL, et al. The association of insom-
nia disorder characterised by objective short sleep duration with
hypertension, diabetes and body mass index: a systematic review and
meta-analysis. Sleep Med Rev. 2021;59:101456. doi:10.1016/j.smrv.
2021.101456
SUPPORTING INFORMATION
Additional supporting information can be found online in the Support-
ing Information section at the end of this article.
How to cite this article: Ma J, Chen N, Huang J, Xu L, Shang H.
Circadian syndrome (CircS) and cognitive trajectory
deterioration in middle-aged and older adults: A national
cohort study with causal forest analysis. Alzheimer’s Dement.
2026;22:e71300. https://doi.org/10.1002/alz.71300
 15525279, 2026, 3, Downloaded from https://alz-journals.onlinelibrary.wiley.com/doi/10.1002/alz.71300, Wiley Online Library on [24/04/2026]. See the Terms and Conditions (https://onlinelibrary.wiley.com/terms-and-conditions) on Wiley Online Library for rules of use; OA articles are governed by the applicable Creative Commons License
