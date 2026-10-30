# Page 1

Wang et al. BMC Medicine          (2025) 23:555  
https://doi.org/10.1186/s12916-025-04298-2
RESEARCH
Open Access
© The Author(s) 2025. Open Access This article is licensed under a Creative Commons Attribution-NonCommercial-NoDerivatives 4.0 
International License, which permits any non-commercial use, sharing, distribution and reproduction in any medium or format, as long 
as you give appropriate credit to the original author(s) and the source, provide a link to the Creative Commons licence, and indicate if 
you modified the licensed material. You do not have permission under this licence to share adapted material derived from this article or 
parts of it. The images or other third party material in this article are included in the article’s Creative Commons licence, unless indicated 
otherwise in a credit line to the material. If material is not included in the article’s Creative Commons licence and your intended use is not 
permitted by statutory regulation or exceeds the permitted use, you will need to obtain permission directly from the copyright holder. To 
view a copy of this licence, visit http://creativecommons.org/licenses/by-nc-nd/4.0/.
BMC Medicine
Additive effects of depression 
and abdominal obesity on cognitive function 
in middle‑aged and older population: evidence 
from multinational cohorts
Ruiqi Wang1†, Yalin Chen1†, Kayla M. Teopiz2, Roger S. McIntyre3,4 and Bing Cao1,5* 
Abstract 
Background  This study aimed to investigate the joint trajectories of obesity/abdominal obesity and depression, 
and their association with cognitive function among four nationally representative cohorts.
Methods  We used data from four nationally representative cohorts (China, UK, USA, and Mexico) in adults 
over the age of 45, which included a total of 114,633 participants. Kml3D clustering algorithm was conducted to iden-
tify the potential joint trajectories of obesity/abdominal obesity and depression of homogeneous groups. Generalized 
Estimating Equations (GEE) were performed to examine the joint trajectory of obesity/abdominal obesity and depres-
sion in relation to cognitive function.
Results  In all cohorts, the baseline “Comorbidity” (with both depression and obesity/abdominal obesity) exhib-
ited significantly poorer performance on subsequent cognitive assessments compared to the “Neither condi-
tion” group (neither depression nor obesity). Cluster analysis and GEE revealed that when Body Mass Index (BMI) 
was used as an obesity indicator, individuals in the joint trajectory groups with depression trajectories (regardless 
of obesity trajectories) across four cohorts exhibited poorer cognitive performance compared to the Normal weight 
and No depressed group (CHARLS: β =  − 0.35, 95% CI − 0.42 to − 0.28; ELSA: β =  − 0.32, 95% CI − 0.44 to − 0.20; HRS: 
β =  − 0.20, 95% CI − 0.27 to − 0.13, MHAS: β =  − 0.15, 95% CI − 0.19 to − 0.10; all P < 0.001). Conversely, associations 
between the joint trajectory groups with obesity trajectories (regardless of depression trajectories) and cogni-
tive function demonstrated significant heterogeneity across cohorts. Abdominal obesity measures indicated 
that the abdominal obesity or higher waist-to-height ratio (WHtR) and Depression group significantly contributed 
to cognitive decline compared to those in the No abdominal obesity and No depression group (CHARLS: β =  − 0.31, 
95% CI − 0.39 to − 0.23; ELSA: β =  − 0.20, 95% CI 0.29 to − 0.12; HRS: β =  − 0.20, 95% CI − 0.27 to − 0.14, all P < 0.001).
Conclusions  Abdominal obesity and depression exert independent additive and fluctuating effects on measures 
of cognition in middle-aged and older persons. Strategies that broadly aim to decrease excess fat, notably abdominal 
obesity, represent near-term interventions that may beneficially influence aspects of cognition in depression.
Keywords  Trajectory, Obesity, Abdominal obesity, Depression, Cognitive function, Cohort study
†Ruiqi Wang and Yalin Chen contributed equally to this work.
*Correspondence:
Bing Cao
bingcao@swu.edu.cn
Full list of author information is available at the end of the article

# Page 2

Page 2 of 17
Wang et al. BMC Medicine          (2025) 23:555 
Graphical Abstract
Background
The widespread nature of depression and obesity car-
ries considerable public health challenges [1, 2], par-
ticularly among middle-aged and older adults [3]. 
Recent US data show that 44.3% of adults aged 40–59 
were classified as obese during 2017–2020, increas-
ing to nearly 41.5% among those aged 60 and older [4]. 
Similarly, a recent study found that 21.3% of adults aged 
50 and above report depressive symptoms [5].
Furthermore, both disorders co-occur within indi-
viduals, with depression conferring a 37% increased 
risk of obesity and obesity elevating depression risk by 
40% [1], creating compound impairment in physical 
and mental health. This interplay is mediated mainly 
through shared genetic loci [6], neuroendocrine dys-
function [notably the hypothalamic–pituitary–adrenal 
(HPA) axis hyperactivity], metabolic disturbances, and 
chronic inflammation [7]. These interconnected path-
ways form a self-perpetuating vicious cycle that exac-
erbates pathological progression in both conditions [8]. 
Accumulating evidence suggested that the comorbidity 
of obesity and depression may impair health outcomes 
in middle-aged and older adults, including increased 
risks of functional disability, cardiometabolic multi-
morbidity, and cognitive decline [9–12]. These inter-
connected health burdens underscore the urgent need 
for integrated preventive and therapeutic strategies tar-
geting this vulnerable demographic.
Cognitive decline is a growing public-health concern. 
Statistics show that approximately 5–8% of older adults 
experience cognitive decline annually, which is consid-
ered a precursor symptom of dementia [13]. Neurode-
generative processes mediated by chronic inflammation 
and metabolic disturbances, including cerebrovascular 
pathology, are key contributors to this decline [14–16]. 
Given the established mechanistic associations of obesity 
and depression with chronic inflammation and metabolic 
dysfunction [17], these conditions may synergistically 
drive cognitive impairment progression.
Extensive evidence indicates that depression links to 
cognitive decline and is a prodrome to dementia [18–20]. 
Depressive symptoms mediate cognitive impairment via 
multiple pathways, including the aforementioned HPA 
axis hyperactivation, inflammation, and hippocam-
pal atrophy [21–23]. Chronic or recurrent depression 
particularly impairs attention, executive function, and 
episodic memory—specific domains critical for daily 
functioning and predictive of dementia risk [24, 25]. 
However, the association between obesity and cognitive 
health in middle-aged and older adults remains unclear 
[9]. Some studies suggest that obesity may have a protec-
tive effect on cognitive decline [26, 27], supporting the

# Page 3

Page 3 of 17
Wang et al. BMC Medicine          (2025) 23:555 
	
concept of an “obesity paradox” [28], while others view 
obesity as a risk factor for cognitive decline [27, 29, 30], 
necessitating further investigation into their connec-
tion. Of note, while Body Mass Index (BMI) is a widely 
accepted indicator for defining obesity, cross-cultural 
researches have uncovered heterogeneity in its correla-
tion with cognitive deterioration [9, 31]. Importantly, as 
a contributing factor to various chronic illnesses includ-
ing type 2 diabetes, cardiovascular disease, and meta-
bolic syndrome [32], abdominal obesity (AO)[33]) has 
been demonstrated by numerous studies to have a robust 
association with cognitive decline [34–37]. Additionally, 
considering the comorbid mechanisms between obesity 
and depression, the joint changes of both conditions over 
time should not be overlooked.
To overcome limitations of prior studies using a single 
obesity indicator and elucidate mechanisms underly-
ing cognitive decline, this study incorporates BMI and 
(waist to height ratio) WHtR as predictive indicators in 
middle-aged and older populations. While prior work 
often has predominantly examined the effects of a sin-
gle developmental trajectory of obesity or depression on 
cognitive decline, it overlooked the combined effects of 
their joint trajectories. Hence, we conducted a multina-
tional cohort study to examine the association between 
comorbid obesity-depression trajectories and cogni-
tive decline. We hypothesize that individuals exhibiting 
co-occurring trajectories of persistent obesity/AO and 
persistent depression demonstrate significantly poorer 
cognitive performance compared to those who remained 
consistently non-obese and non-depressed throughout 
the observation period. Findings aim to identify high-risk 
populations and inform targeted interventions for age-
related cognitive impairment.
Methods
Study population
The multinational cohort employed in this survey design 
comprised four prospective, nationally representative 
longitudinal studies: the China Health and Retirement 
Longitudinal Study (CHARLS, China), the English Lon-
gitudinal Study of Ageing (ELSA, United Kingdom), the 
Health and Retirement Study (HRS, United States), and 
the Mexican Health and Aging Study (MHAS, Mexico). 
All sample population was recruited as part of a strati-
fied, multistage probability design, with longitudinal 
follow-up administered by trained research teams. The 
detailed introduction of each cohort could be found on 
their websites [CHARLS: https://​charls.​pku.​edu.​cn/​gy/​
gyxm.​htm [38]; ELSA: https://​ukdat​aserv​ice.​ac.​uk/​about/ 
[39]; HRS: https://​hrs.​isr.​umich.​edu/​about? [40]; MHAS: 
https://​www.​mhasw​eb.​org/​Home/​Index.​aspx [41]]. Rele-
vant ethical review institutes granted our survey’s ethical 
approval, and all participants signed informed consent 
forms before the survey.
According to the current research objectives, we ruled 
out the impact of COVID-19 and selected the appropri-
ate waves from the four cohorts. The included waves need 
to include all the key variables of this study (e.g., BMI, 
WHtR, depressive symptoms, cognitive function scores, 
and covariates). Thus, 3 waves (wave1–3: 2011, 2013, and 
2015) in CHARLS, 3 waves (wave3–5: 2012, 2015, and 
2018) in MHAS, 4 waves (wave2,4,6,8: 2004, 2008, 2012, 
and 2016) in ELSA, and 6 waves (wave8–13: 2006–2016) 
in HRS (participants only received body measurements 
in odd or even waves, so we merged the odd and even 
waves into three waves: wave1, wave2, wave3:2006/2008, 
2010/2012 and 2014/2016) were included in the cur-
rent study. Our exclusion criteria were as follows: (1) 
age < 45 years old; (2) participants with cognitive-related 
disorders (see Additional file  1: Table S1)[42]; (3) cases 
of missing, unclear responses, and rejections both in 
baseline and follow-up surveys. Therefore, 114,633 par-
ticipants from four countries were considered, and after 
screening, a total of 36,718 participants remained. The 
comprehensive screening flowchart of participants could 
be seen in Additional file  1: Fig. S1, with an in-depth 
description of each cohort’s selecting procedure available 
in Additional file 1: Fig. S2.
Obesity and abdominal obesity
In the main analyses, obesity in middle-aged and older 
adults was defined by Body Mass Index (BMI), and the 
calculation of BMI was done by dividing a person’s 
weight (in kilograms) by the square of their height (in 
meters). It is worth noting that objectively measured 
height, weight, and waist circumference (WC) were pro-
vided only in CHARLS, ELSA, and HRS. MHAS only 
included self-reported height and weight (no WC data 
available). Furthermore, because the study population 
comes from various continents and exhibits variations in 
ethnicity, physique, culture, and public health priorities, 
it is considered to adopt distinct body type classification 
standards [43]. Our study referred to previous research, 
stipulated the use of the Chinese criteria to classify 
participants from CHARLS, and obesity is defined as 
BMI ≥ 28 kg/cm2 [44]. For the population from ELSA, 
HRS, and MHAS cohorts, the European and American 
criteria were utilized for classification, and obesity is 
defined as BMI ≥ 30 kg/cm2 [45] (cut-off values of BMI 
under different standards were shown in Additional file 1: 
Table S2) [44].
Abdominal obesity was defined by waist-to-height ratio 
(WHtR), which was calculated as WC divided by height 
(both in centimeters). Considering it is probable that 
middle-aged and older adults may have an overestimation

# Page 4

Page 4 of 17
Wang et al. BMC Medicine          (2025) 23:555 
of abdominal obesity due to height loss [46]. The current 
study defined 0.6 as the cut-off value of abdominal obe-
sity [47].
In addition, we opted to use the Weight-Adjusted Waist 
Index (WWI) in the secondary analysis to reflect obesity 
[48]. The WWI standardizes WC with weight, providing 
a more accurate depiction of adiposity that is unrelated 
to weight and partially circumvents the “obesity paradox” 
associated with BMI [49]. It was calculated by dividing 
WC (in centimeters) by the square root of weight (in kilo-
grams) (√kg) [50].
Depressive symptoms assessment
In all four cohorts, depressive symptoms and depression 
were evaluated by calculating the total scores of different 
standardized scales and referring to the corresponding 
cut-off values. Briefly, in CHARLS, depressive symptoms 
were measured by the ten-item Center for Epidemiologic 
Studies Depression Scale (CESD-10); in ELSA and HRS, 
depressive symptoms were measured by the eight-item 
version of the Center for Epidemiologic Studies Depres-
sion Scale (CES-D); in MHAS, depressive symptoms 
were measured by the nine-item scale modified from 
the Center for Epidemiological Studies Depression scale 
(CESD-9). Additional file 1: Table S3 [20, 51–55] provides 
more information about each scale.
Empirical classification (secondary analysis): depression 
and obesity group
In the baseline and outcome wave, participants’ depres-
sion and obesity status were divided into four groups 
based on previous research and empirical criteria: (1) 
neither depression nor obesity (“Neither condition”); (2) 
depression without obesity (“Depression alone”); (3) obe-
sity without depression (“Obesity alone”); (4) with both 
depression and obesity (“Comorbidity”) (3). Therefore, 
the changes in the subjects’ depression-obesity status 
can be further categorized into three groups over time: 
(1) Stability; (2) Progression; (3) Regression. More details 
about the grouping criteria are provided in the Addition-
alfile 1: Fig. S3.
Cognitive function assessment
Cognitive function was assessed through face-to-face 
self-questionnaire, evaluating the response and opera-
tional performance of participants. Each cohort used 
different questionnaires and measurement dimensions. 
Briefly, in CHARLS, the cognitive function was assessed 
by the Chinese version of the Mini-Mental State Exami-
nation (MMSE); in ELSA, the cognitive function assess-
ment was assessed by standardized episodic memory 
and orientation tests; in HRS, the cognitive function 
was assessed by the modified version of the Telephone 
Interview for Cognitive Status (TICS); in MHAS, the 
cognitive function was assessed by the Cross-Cultural 
Cognitive Examination (CCCE). In all tests, a higher cog-
nitive score indicated better cognitive performance. To 
achieve comparability across different tests, we generated 
the z-score of cognitive function for each cohort, refer-
ring to previous research [20]. Details of cognitive assess-
ments for each cohort and the method for calculating 
z-score are provided in the Additional file 1: Table S4 and 
Supplementary Methods1 [20, 42, 56–61].
Covariates
Covariate selection was guided by two criteria: (1) avail-
ability of key demographic variables in the database, and 
(2) prior empirical evidence from relevant studies [42, 
62]. The following variables were ultimately incorpo-
rated as potential confounding factors: age, gender, race, 
marital status, education level, residential area, house-
hold financial situation, five doctor-diagnosed health 
problems (hypertension, diabetes, cancer, stroke and 
arthritis), smoking and drinking status at baseline. The 
definition of covariates is reported in the Additionalfile 1: 
Supplementary Methods2.
Statistical analysis
All analyses were conducted based on complete data-
sets with exclusion of missing data. In the main analy-
ses, the baseline characteristics of the participants were 
described as means ± standard deviations (SD) of con-
tinuous variables and percentages (%) of categorical vari-
ables. Differences in the characteristics were analyzed 
using t-tests and chi-square tests. And to better present 
the transition of depression-obesity status, we depicted 
Sankey diagrams to visualize the proportion of partici-
pants transitioning across different groups from baseline 
to outcome wave.
To identify the potential joint variable-trajectories of 
obesity (indicator: BMI and WHtR) and depression of 
homogeneous groups, the current study used Kml3D, 
a partitioning clustering algorithm from the package 
KmL3D [63], which is based on the k-means algorithm 
[64]. Then, we thoroughly considered both Calinski & 
Harabasz criterion (high value denoting good partition) 
[65] and the interpretability of the results to decide the 
final number of clusters for each cohort; meanwhile, we 
named the trajectory groups for further analysis. Further 
explanations on this methodology are provided in the 
Additionalfile 1: Supplementary Methods3 [66, 67].
Subsequently, 
Generalized 
Estimating 
Equations 
(GEE),which are an extension of generalized linear 
models (GLM) and allow for the resolution of the issue 
of the correlations between observations in longitu-
dinal studies [68], were employed to evaluate baseline

# Page 5

Page 5 of 17
Wang et al. BMC Medicine          (2025) 23:555 
	
depression-obesity status of participants and the joint 
trajectory of the two in relation to cognitive function 
(z-score). We set follow-up time as the timescale to cal-
culate the β with corresponding 95% confidence intervals 
(CI). GEE was repeated after stratifying by baseline main 
characteristics.
In subgroup analyses, we stratified populations based 
on main demographic variables (e.g., age, sex, educa-
tional attainment) to examine heterogeneous associations 
between joint trajectories of BMI/WHtR and depressive 
symptoms and cognitive function change across distinct 
population subgroups. The interaction effects between 
different subgroups and combined trajectory groups 
were examined. In secondary analyses, we employed 
various obesity indicators and different grouping strat-
egies to redefine changes in depression-obesity status, 
aiming to supplement the main results. (1) Considering 
that KmL3D is a data-driven clustering algorithm and 
might ignore practical experience standards, we classified 
participants into stability groups, progression groups, 
and regression groups based on a previous classification 
method and empirical criteria, reflecting the transition 
between obesity and depression at baseline and outcome 
waves. We then repeated GEE to explore the association 
between the transition groups and development of cogni-
tive function in participants. (2) Used WWI as another 
obesity indicator and generated joint trajectory groups. 
Subsequently, replicated the statistics of the main results. 
We also conducted several sensitivity analyses to test the 
robustness of our findings: (1) Removed the underweight 
population (BMI < 18.5) and the statistical approach was 
consistent with previous work; (2) To ensure joint tra-
jectories were robust, 20% of the participants were ran-
domly excluded and repeated the KmL3D cluster analysis 
[67].
All analyses were conducted with R (version 4.3.1); spe-
cifically, we used “kml3d”, “gee”, “geepack” and “ggplot2” 
packages. Sankey diagrams and forest plots were plot-
ted by [https://​www.​bioin​forma​tics.​com.​cn] and the 
CNSknowall platform [https://​cnskn​owall.​com] respec-
tively. All analyses employed stepwise adjustment for 
confounding variables, with statistical significance 
defined as two-tailed P-values < 0.05.
Results
Baseline characteristics of the study population
A total of 36,718 individuals [8286 (22.6%) in CHARLS, 
5225 (14.2%) in ELSA, 10,849 (29.5%) in HRS and 12,358 
(33.7%) in MHAS] were included in the study popula-
tion. The main baseline characteristic distributions of 
participants and the demographic descriptions stratified 
by depression status are presented in Fig. 1 and Table 1. 
The mean follow-up duration across the four cohorts was 
9 years, with cohort-specific durations as follows: 4 years 
for CHARLS, 10 years for both ELSA and HRS, and 12 
years for MHAS. Among the continuous variables, the 
mean age of participants was 63.69 (SD 9.99) years. The 
mean of BMI was 27.27 (SD 5.40) and the mean of WHtR 
was 0.55 (SD 0.10). T-tests and chi-square tests showed 
participants who had experienced depression tended to 
have a higher BMI (all P < 0.05) and WHtR in ELSA and 
HRS and lower baseline cognitive test score in all cohorts 
(all P < 0.001). In all four studies, age, gender, education 
status, marital status, hypertension, stroke, drinking 
status, and smoking status had impacts on depressive 
symptoms (all P < 0.05). Moreover, Additionalfile 1: Fig. 
S4 and Fig.S5 shows basic characteristics of the dynamic 
transition of depression-obesity status from baseline to 
outcome wave. Overall, the proportion of participants in 
all studies experiencing a state transition was relatively 
small.
Association between baseline depression‑obesity status 
and changes in cognitive function
No matter which obesity indicator was adopted, com-
pared to participants in “Neither condition,” individu-
als in “Depression alone” and “Comorbidity” at baseline 
exhibited significantly poorer performance in subsequent 
cognitive assessments (Fig. 2 and Additional File 1: Table 
S5). This association persisted even after full adjustment 
for all covariates, maintaining statistical significance 
across analytical models (“Depression alone” of Fig. 2A—
CHARLS: β =  − 0.30, 95% CI − 0.35 to − 0.25; ELSA: 
β =  − 0.27, 95% CI − 0.40 to − 0.14; HRS: β =  − 0.17, 95% 
CI − 0.26 to − 0.09; MHAS: β =  − 0.19, 95% CI − 0.23 
to − 0.14; Fig.  2B: CHARLS: β =  − 0.29, 95% CI − 0.34 
to − 0.23; ELSA: β =  − 0.24, 95% CI: − 0.37 to − 0.11; 
HRS: β =  − 0.14, 95% CI − 0.23 to − 0.05; “Comorbidity” 
of Fig. 2A: CHARLS: β =  − 0.25, 95% CI − 0.42 to − 0.08; 
ELSA: β =  − 0.26, 95% CI − 0.41 to − 0.11; HRS: β =  − 0.18, 
95% CI − 0.26 to − 0.10; MHAS: β =  − 0.07, 95% CI − 0.12 
to − 0.01; Fig.  2B: CHARLS: β =  − 0.34, 95% CI − 0.45 
to − 0.24; ELSA: β =  − 0.32, 95% CI − 0.48 to − 0.16; HRS: 
β =  − 0.26, 95% CI − 0.34 to − 0.18, all P < 0.05). When 
the obesity indicator was BMI, we observed individuals 
in “Obesity alone” exhibited superior cognitive develop-
ment in HRS and MHAS (HRS: β = 0.05, 95% CI 0.01 to 
0.08; MHAS: β = 0.06, 95% CI 0.02 to 0.10, all P < 0.05), 
whereas ELSA revealed an inverse pattern, with indi-
viduals with obesity exhibiting comparatively impaired 
cognitive outcomes (β =  − 0.10, 95% CI − 0.17 to − 0.02, 
P = 0.012). When the obesity indicator was WHtR, “Obe-
sity alone” participants demonstrated significantly poorer 
cognitive performance compared to “Neither condi-
tion” only in ELSA (β =  − 0.11, 95% CI − 0.18 to − 0.03, 
P = 0.004).

# Page 6

Page 6 of 17
Wang et al. BMC Medicine          (2025) 23:555 
Cluster analysis and joint trajectories of obesity 
and depression
In order to determine the appropriate number of poten-
tial trajectories of BMI (kg/m2)/WHtR and depressive 
symptoms groups, our study combined the iterative 
results of KmL3D (the number of clusters was iteratively 
increased from 2 to 20), cluster classification metrics, and 
interpretability of the results [a reference group (Normal 
weight/No abdominal obesity & No depression) should 
be defined at least]. Therefore, we identified different 
numbers of trajectories for different cohorts respectively 
(Fig. 3, Additional file 1: Table S6 and S7). Furthermore, 
after randomly excluding 20% of participants and repeat-
ing the cluster analysis, no substantial differences were 
found in the newly divided trajectory group (Additional-
file 1: Fig. S6, Table S6 and S7).
Association between joint trajectories and changes 
in cognitive function
Figure  4 and Additional file  1: Table S8–S9 summa-
rize the association between joint trajectories (BMI/
WHtR and depressive symptoms) and changes in cogni-
tive function. In Fig.  4A (adjusted all covariates), com-
pared to the reference group (Group1: Normal weight 
and No depression), participants in the joint trajectory 
groups with depression (regardless of obesity trajecto-
ries) had poorer cognitive function [CHARLS (Group2: 
Normal weight & Depression): β =  − 0.35, 95% CI − 0.42 
to − 0.28; ELSA (Group2: Overweight & Depression): 
β =  − 0.32, 95% CI − 0.44 to − 0.20; HRS (Group2: Over-
weight & Depression): β =  − 0.20, 95% CI − 0.27 to − 0.13, 
MHAS (Group3: Overweight & Depression): β =  − 0.15, 
95% CI − 0.19 to − 0.10; all P < 0.001]. However, in other 
trajectory groups, inconsistent results were observed 
among the four studies. When compared with the refer-
ence group, the significantly accelerated cognitive decline 
was reported in Group 4 (Obesity and No depression) 
of ELSA (β =  − 0.16, 95% CI − 0.26 to − 0.06, P = 0.002). 
Additionally, the association between trajectory groups 
characterized by overweight/obesity and better cogni-
tive development was observed in HRS and MHAS [HRS 
(Group3 and Group4: Obesity (I)/Obesity II) and No 
depression): β = 0.06, 95% CI 0.02 to 0.11; β = 0.10, 95% 
CI 0.04 to 0.16; MHAS (Group2: Overweight and No 
depression): β = 0.09, 95% CI 0.04 to 0.13, all P < 0.05]; 
however, this association was not observed in the 
CHARLS.
Figure  4B shows the relationship between the joint 
trajectory (WHtR and depressive symptoms) and cog-
nitive changes. In the fully adjusted model (adjusted all 
Fig. 1  Main baseline characteristics of participants from four cohorts. Abbreviations: CHARLS, China Health and Retirement Longitudinal Study; 
ELSA, English Longitudinal Study of Ageing; MHAS, the Mexican Health and Aging Study; HRS, Health and Retirement Study

# Page 7

Page 7 of 17
Wang et al. BMC Medicine          (2025) 23:555 
	
Table 1  Baseline characteristics of participants from four cohorts according to depression status
Variables
Overall 
(Mean ± 
SD or
events/n)
China Health and Retirement Longitudinal 
Study (CHARLS) 
(n=8286)
English Longitudinal Study of Ageing 
(ELSA)
(n=5225)
Health and Retirement Study(HRS)
(n=10849)
Mexican Health and Aging Study (MHAS)
(n=12358)
No depression 
(n=5504)
Depression  
(n=2782)
p
No depression 
(n=4552)
Depression 
(n=673)
p
No depression 
(n=9539)
Depression 
(n=1310)
p
No depression 
(n=8591)
Depression(n=3767)
p
Age (years)
63.69 ± 9.99
58.12 ± 8.97
59.13 ± 8.97
<0.001
65.39 ± 8.92
66.26 ± 9.78
0.200
66.98 ± 9.56
65.83 ± 9.97
<0.001
63.28 ± 9.77
64.53 ± 10.20
<0.001
BMI (kg/m2)*
27.27 ± 5.40
23.82 ± 3.71
23.20 ± 3.71
<0.001
27.88 ± 4.75
28.37 ± 5.31
0.014
29.21 ± 5.71
30.52 ± 6.67
<0.001
27.81 ± 4.56
27.50 ± 4.71
0.004
Underweight
300/728
260 (4.7)
216 (7.8)
<0.001
27 (0.6)
5 (0.7)
0.041
53 (0.6)
10 (0.8)
<0.001
88 (1.0)
69 (1.8)
<0.001
Normal weight
2771/11579
2811 (51.1)
1544 (55.5)
1237 (27.2)
180 (26.7)
2152 (22.6)
257 (19.6)
2608 (30.4)
1180 (31.3)
Overweight
2838/13889
1755 (31.9)
745 (26.8)
1993 (43.8)
263 (39.1)
3575 (37.5)
416 (31.8)
3728 (43.4)
1414 (37.5)
Obesity
2233/9952
678 (12.3)
277 (10.0)
1295 (28.4)
225 (33.4)
3579 (39.4)
627 (47.9)
2167 (25.2)
1104 (29.3)
Waist-to-height 
ratio (WHtR)
0.55 ± 0.10
0.54 ± 0.06
0.54 ± 0.66
0.305
0.58 ± 0.07
0.59 ± 0.08
<0.001
0.60 ± 0.09
0.63 ± 0.10
<0.001
NA
NA
NA
No abdominal 
obesity
3182/15478
4557 (82.8)
2285 (82.1)
0.455
2966 (65.2)
401 (59.6)
0.005
4773 (50.0)
496 (37.9)
<0.001
NA
NA
NA
Abdominal 
obesity
1583/8882
947 (17.2)
497 (17.9)
1586 (34.8)
272 (40.4)
4766 (50.0)
814 (62.1)
Gender (%)
Male
2955/16614
3099 (56.3)
1215 (43.7)
<0.001
2247 (49.4)
226 (33.6)
<0.001
4013 (42.1)
363 (27.7)
<0.001
4300 (50.1)
1151 (30.6)
<0.001
Female
5577/20104
2405 (43.7)
1567 (56.3)
2305 (50.6)
447 (66.4)
5526 (57.9)
947 (72.3)
4291 (49.9)
2616 (69.4)
Race (%)
White
1655/14125
NA
NA
NA
4511 (99.1)
655 (97.3)
<0.001
7959 (83.4)
1000 (76.3)
<0.001
NA
NA
NA
Other
328/1949
41 (0.9)
18 (2.7)
1580 (16.6)
310 (23.7)
Education status 
(%)
Less than lower 
secondary
6796/21571
4645 (84.4)
2588 (93.0)
<0.001
1678 (36.9)
333 (49.5)
<0.001
1502 (15.7)
410 (31.3)
<0.001
6950 (80.9)
3465 (92.0)
<0.001
Upper secondary 
& vocational 
training
1395/11285
734 (13.3)
177 (6.4)
2198 (48.3)
284 (42.2)
5708 (59.8)
731 (55.8)
1250 (14.6)
203 (5.4)
Tertiary
341/3862
125 (2.3)
17 (0.6)
676 (14.9)
56 (8.3)
2329 (24.4)
169 (12.9)
391 (4.6)
99 (2.6)
Residence (%)§
Type A(Urban)
5016/24405
2331 (42.4)
877 (31.50)
<0.001
4374 (96.1)
632 (93.9)
0.008
6381 (66.9)
912 (69.6)
0.490
6303 (73.4)
2595 (68.9)
<0.001
Type B(Rural)
3516/12313
3173 (57.6)
1905 (68.5)
178 (3.9)
41 (6.1)
3158 (33.1)
398 (30.4)
2288 (26.6)
1172 (31.1)
Marital status (%)
Living alone（No）
2670/9025
462 (8.4)
419(15.1)
<0.001
1085 (23.8)
293 (43.5)
<0.001
2658 (27.9)
592 (45.2)
<0.001
2150 (25.0)
1366 (36.3)
<0.001
Living 
with partner(Yes)
5862/27693
5042 (91.6)
2363 (84.9)
3467 (76.2)
380 (56.5)
6881 (72.1)
718 (54.8)
6441 (75.0)
2401 (63.7)
Household eco-
nomic situation 
(%)✝
Low tertile
3633/12753
1736 (31.5)
1023 (36.8)
<0.001
1490 (32.7)
251 (37.3)
0.062
2933 (30.7)
684 (52.2)
<0.001
2961 (34.5)
1675 (44.5)
<0.001
Medium tertile
2678/11751
1796 (32.6)
972 (34.9)
1530 (33.6)
214 (31.8)
3243 (34.0)
378 (28.9)
2504 (29.1)
1114 (29.6)
High tertile
2221/12214
1972 (35.8)
787 (28.3)
1532 (33.7)
208 (30.9)
3363 (35.3)
248 (18.9)
3126 (36.4)
978 (26.0)
Hypertension (%)

# Page 8

Page 8 of 17
Wang et al. BMC Medicine          (2025) 23:555 
Data are presented as means ± standard deviations or number (proportion %)P values were calculated using analysis of t-test and Cchi-square test for continuous and categorical variables, respectively*BMI: In CHARLS: 
underweight (< 18.5 kg/cm2); normal weight (>= 18.5 kg/cm2 and < 22.9 kg/cm2); overweight (>= 23 kg/cm2 and < 28 kg/cm2); obesity (>= 28kg/cm2). In other databases, underweight (< 18.5 kg/cm2); normal weight 
(>= 18.5 kg/cm2 and <25 kg/cm2); overweight (>= 25 kg/cm2 and < 30 kg/cm2); obesity (>=30 kg/cm2)§Residence: In CHARLS, HRS and MHAS, type A: Urban area; type B: Rural area. In ELSA, type A: UK; type B: Other 
area✝Household economic situation: In CHARLS, ELSA and MHAS, Household economic situation was defined by total household per capita consumption. In HRS,Household economic situation was defined by total 
household income
Table 1  (continued)
Variables
Overall 
(Mean ± 
SD or
events/n)
China Health and Retirement Longitudinal 
Study (CHARLS) 
(n=8286)
English Longitudinal Study of Ageing 
(ELSA)
(n=5225)
Health and Retirement Study(HRS)
(n=10849)
Mexican Health and Aging Study (MHAS)
(n=12358)
No depression 
(n=5504)
Depression  
(n=2782)
p
No depression 
(n=4552)
Depression 
(n=673)
p
No depression 
(n=9539)
Depression 
(n=1310)
p
No depression 
(n=8591)
Depression(n=3767)
p
No
4317/20672
4148 (75.4)
2014 (72.4)
0.003
2791 (61.3)
366 (54.4)
<0.001
4723 (49.5)
544 (41.5)
<0.001
4693 (54.6)
1393 (37.0)
<0.001
Yes
4215/16046
1356 (24.6)
768 (27.6)
1761 (38.7)
307 (45.6)
4816 (50.5)
766 (58.5)
3898 (45.4)
2374 (63.0)
Diabetes (%)
No
6758/31007
5179 (94.1)
2587 (93.0)
0.050
4233 (93.0)
601 (89.3)
<0.001
8076 (84.7)
955 (76.0)
<0.001
6761 (78.7)
2615 (69.4)
<0.001
Yes
1734/5671
325 (5.9)
195 (7.0)
319 (7.0)
72 (10.7)
1463 (15.3)
315 (24.0)
1830 (21.3)
1152 (30.3)
Cancer (%)
No
8147/34546
5457 (99.1)
2756 (99.1)
0.711
4239 (93.1)
619 (92.0)
0.277
8331 (87.3)
1169 (89.2)
0.051
8372 (97.5)
3603 (95.6)
<0.001
Yes
385/2172
47 (0.9)
26 (0.9)
313 (6.9)
54 (8.0)
1208 (12.7)
141 (10.8)
219 (2.5)
164 (4.4)
Stroke (%)
No
8137/35451
5422 (98.5)
2682 (96.4)
<0.001
4407 (96.8)
637 (94.7)
0.004
9074 (95.1)
1218 (93.0)
0.001
8411 (97.9)
3600 (95.6)
<0.001
Yes
395/1267
82 (1.5)
100 (3.6)
145 (3.2)
36 (5.3)
465 (4.9)
92 (7.0)
180 (2.1)
167 (4.4)
Arthritis (%)
No
4800/23580
4078 (74.1)
1557 (56.0)
<0.001
3148 (69.2)
328 (48.7)
<0.001
4515 (47.3)
418 (31.9)
<0.001
7039 (81.9)
2497 (66.3)
<0.001
Yes
3732/13138
1426 (25.9)
1225 (44)
1404 (30.8)
345 (51.3)
5024 (52.7)
892 (68.1)
1552 (18.1)
1270 (33.7)
Drinking status (%)
None
5660/19578
3134 (56.9)
1713 (61.6)
<0.001
389 (8.5)
117 (17.4)
<0.001
4187 (43.9)
741 (56.6)
<0.001
6208 (72.3)
3089 (82.0)
<0.001
Yes
2872/17140
2370 (43.1)
1069 (38.4)
4163 (91.5)
556 (82.6)
5352 (56.1)
569 (43.4)
2383 (27.7)
678 (18.0)
Smoking status 
(%)
None
4908/17718
3042 (55.3)
1698 (61.0)
<0.001
1727 (37.9)
206 (30.6)
<0.001
4249 (44.5)
537 (41.0)
0.015
5136 (59.8)
2467 (65.5)
<0.001
Yes
3624/18740
2462 (44.7)
1084 (39.0)
2825 (62.1)
467 (69.4)
5290 (55.5)
773 (59.0)
3455 (40.2)
1300 (34.5)
Baseline cognitive
test score
NA
16.65 ± 4.63
14.33 ± 4.63
<0.001
14.25 ± 3.40
13.42 ± 3.64
<0.001
15.92 ± 3.98
14.29 ± 4.60
<0.001
53.22 ± 18.25
46.71 ± 17.71
<0.001

# Page 9

Page 9 of 17
Wang et al. BMC Medicine          (2025) 23:555 
	
covariates), compared to the reference group (Group1: 
No abdominal obesity & No depression), participants 
in “Abdominal obesity and Depression group” met with 
more cognitive decline [ELSA (Group2: Abdominal obe-
sity (I) and Depression): β =  − 0.20, 95% CI 0.29 to − 0.12; 
HRS (Group2: Abdominal obesity (I) and Depression): 
β =  − 0.20, 95% CI: − 0.27 to − 0.14, all P < 0.001]. In 
CHARLS, although no “Abdominal obesity and Depres-
sion” group was divided, the group containing depression 
(Group 2: No abdominal obesity (II) and Depression) 
also had poorer cognitive development than the refer-
ence group (β =  − 0.31, 95% CI − 0.39 to − 0.23, P < 0.001); 
meanwhile, participants in this group exhibited a higher 
WHtR compared to those in the reference group (Addi-
tionalfile 1: Table S9).
Subgroup analysis
We further stratified the population into different sub-
groups according to main demographic variables (such 
as age, gender, education status and so on) to assess the 
heterogeneity of joint trajectories (BMI and Depressive 
symptoms and WHtR and Depressive symptoms) on 
changes in cognitive function (Additional file 2: Fig. S7–
S8, and Table S10). The results were similar to the main 
results but not consistent in four cohorts.
Secondary and sensitivity analyses
The current research further conducted two secondary 
analyses to supplement the results. (1) We explored the 
association between the transition in depression-obesity 
status and development of cognitive function in partici-
pants. The results indicated that compared to those who 
maintained neither depression nor obesity, participants 
in other transition groups may have had worse cognitive 
function (Additional file 3: Table S11–S13 and Fig. S9). 
(2) We included Weight-Adjusted Waist Index (WWI) 
as another measure of obesity. It was observed that indi-
viduals in the joint trajectory groups with higher WWI 
and/or depression had poorer cognitive development 
compared to the reference group (Low WWI and No 
depression) (Additional file  3: Fig. S10 and Table S14–
S15). We also conducted a sensitivity analysis (removed 
566 underweight participants) and obtained results that 
accorded closely with those of the main analyses (Addi-
tional file 3: Fig. S11 andTable S16).
Discussion
Our analysis of longitudinal data from four multinational 
cohorts examined the additive and synergistic effects of 
depression and obesity/abdominal obesity (AO), and 
their combination, on cognitive function in middle-aged 
and older adults. Specifically, individuals in “Depression 
Fig. 2  Associations between joint trajectories and changes in cognitive function A Association between baseline depression-obesity status 
(Obesity indicator: BMI) and changes in cognitive function. B Association between baseline depression-obesity status (Obesity indicator: WHtR) 
and changes in cognitive function. All models were adjusted for age, gender, education status, residence, marital status, household economic 
situation, (race:only in the ELSA, and HRS), hypertension, diabetes, cancer, stroke, arthritis, drinking status, and smoking status. [Standardized β 
are shown as centers of horizonal bar plots, with error bars representing 95% CI, *P < 0.05, **P < 0.01, ***P < 0.001]. Abbreviations: CHARLS, China 
Health and Retirement Longitudinal Study; ELSA, English Longitudinal Study of Ageing; MHAS, the Mexican Health and Aging Study; HRS, Health 
and Retirement Study. Notes: In CHARLS, ELSA, and MHAS, household economic situation was defined by total household per capita consumption. 
In HRS, household economic situation was defined by total household income

# Page 10

Page 10 of 17
Wang et al. BMC Medicine          (2025) 23:555 
Fig. 3  Joint trajectories of BMI (kg/m2)/WHtR and depressive symptoms in all waves. Abbreviations: CHARLS, China Health and Retirement 
Longitudinal Study; ELSA, English Longitudinal Study of Ageing; MHAS, the Mexican Health and Aging Study; HRS, Health and Retirement Study; 
95% CI, 95% confidence interval. Notes: The different colored lines show the mean of BMI/WHtR and score of depressive symptoms in different 
trajectory groups; (I) and (II) represent different degrees

# Page 11

Page 11 of 17
Wang et al. BMC Medicine          (2025) 23:555 
	
alone” or “Comorbidity” at baseline experienced acceler-
ated cognitive decline compared to those with “Neither 
condition,” using either BMI or WHtR. We also found the 
impact of “Obesity alone” was heterogeneous. However, 
when WHtR defined obesity, “Comorbidity” showed the 
greatest variance to variance in cognitive development. In 
cluster analysis, employing BMI to gauge obesity revealed 
that the joint trajectory of depression and obesity had 
heterogeneous effects on cognition decline. Nonetheless, 
all cohorts demonstrated that the trajectory group with 
depression had quicker cognitive deterioration than the 
reference group. Notably, in examining AO, a key obesity 
subtype, all three groups with measured waist circum-
ference revealed that the “Higher WHtR/AO & Depres-
sion” group significantly contributed to cognitive decline 
relative to the reference group. The outcome was further 
corroborated through the joint trajectory analysis of sec-
ondary analysis employing WWI.
Factors influencing the cognitive function of middle-
aged and older adults have conducted numerous cross-
cultural longitudinal studies on the relationship between 
obesity and cognition, as well as depression and cogni-
tion individually [9, 19, 20, 27, 28, 31]. However, consid-
ering that obesity and depression may share common 
pathological pathways [8], and serve as significant factors 
affecting overall systemic metabolic disorders and qual-
ity of life [69–74], exerting negative influences on higher-
order functions of the brain. Therefore, results evaluating 
only individual factors may be limited and biased, which 
makes them difficult to interpret and validate [73].
Replicated evidence indicates a negative relationship 
exists between cognitive function and depressive disor-
ders [11, 75–78]. Cognitive decline in middle- and older-
aged adults with depression may be a consequence of 
alteration in the structure and function of pathogenetic 
mechanisms including neurotransmitters, vascular pro-
cesses, neuroinflammation, and neural networks [79–83].
The association between obesity and cognition is 
inconsistent and heterogeneity [26, 27, 84]. Some stud-
ies have indicated a negative correlation between obesity 
and cognitive ability [27, 84]. In contrast, other research 
has shown a positive correlation, implying that obesity 
may exert a protective effect on cognitive development 
in middle-aged and older adults. When employing BMI 
as an indicator of obesity and comprehensively consid-
ering the depressive symptoms of the participants, our 
study also reached similar conclusions among the HRS 
and MHAS populations. This could be explained by 
the “obesity paradox,” which suggests that compared to 
underweight individuals, body fat may have a protective 
Fig. 4  Associations between joint trajectories and changes in cognitive function. A Associations between joint trajectories (BMI and score 
of depressive symptoms) and changes in cognitive function. B Associations between joint trajectories (WHtR and score of depressive symptoms) 
and changes in cognitive function. All models were adjusted for age, gender, education status, residence, marital status, household economic 
situation, race (race:only in the ELSA and HRS), hypertension, diabetes, cancer, stroke, arthritis, drinking status, and smoking status [Standardized β 
are shown as centers of horizonal bar plots, with error bars representing 95% CI, *P < 0.05, **P < 0.01, ***P < 0.001]. Abbreviations: CHARLS, China 
Health and Retirement Longitudinal Study; ELSA, English Longitudinal Study of Ageing; MHAS, the Mexican Health and Aging Study; HRS, Health 
and Retirement Study. Notes: In CHARLS, ELSA, and MHAS, household economic situation was defined by total household per capita consumption. 
In HRS, household economic situation was defined by total household income. (I) and (II) represented different degrees

# Page 12

Page 12 of 17
Wang et al. BMC Medicine          (2025) 23:555 
effect on specific health conditions, including cognitive 
function [85]. This can be explained as higher body fat 
may protect against frailty, or that people with obesity 
may have higher energy reserves to buffer the effects of 
age-related brain atrophy [26, 27]. Additionally, individu-
als with overweight or obesity may also attempt to lose 
weight by engaging in physical exercise, and appropri-
ate physical activity has been shown to improve cogni-
tive conditions [86, 87]. For underweight individuals, this 
association may be linked to sarcopenia and malnutrition 
[88]. Meanwhile, weight loss or localized adipose tissue 
deficiency is due to reduced food intake and food attrac-
tiveness [89]. Furthermore, recent research has high-
lighted that the obesity paradox may be explained by the 
interaction between obesity and other factors, such as 
individual genetic, metabolic, and anthropometric fac-
tors [90–92].
Agreement exists that BMI is an imprecise estimate 
of fat mass which may be a source of variance in the 
reported studies [93]. Differences in body fat distribution 
exhibit different patterns in relation to cognitive function 
[94]. As a general measure of body weight, BMI fails to 
reflect fat distribution. In contrast, the Waist-to-Height 
Ratio (WHtR) captures central obesity and serves as a 
surrogate marker for visceral fat accumulation. Visceral 
fat is closely associated with insulin resistance, endothe-
lial dysfunction, and elevated levels of pro-inflammatory 
cytokines such as interleukin-6 (IL-6) and C-reactive 
protein (CRP), all of which are considered key factors 
in the pathogenesis of cognitive impairment and neu-
rodegenerative diseases [95]. Additionally, the Weight-
Adjusted Waist Index (WWI) provides an adiposity index 
independent of total body weight. Studies have shown 
that WWI correlates more strongly with cardiovascular 
metabolic risk factors, oxidative stress, and inflammatory 
markers than BMI. Therefore, it is imperative to further 
investigate the relationship between obesity subtypes or 
fat distribution and cognitive function. Based on this, 
the present study also conducted a parallel analysis using 
the WHtR as a measure of central obesity and obtained 
relatively consistent results across multinational sam-
ples. Previous research indicates that AO is a risk factor 
for cognitive decline in later life [96]. This association 
may be related to dietary habits, metabolic impairment, 
lipid disorders and activities, etc. [97–99]. However, the 
decline in the physical and mental functions of older 
adults leads to lower levels of leisure activity [100], which 
may promote the occurrence of AO and further impair 
their cognitive functions, while there may be a mutually 
reinforcing relationship between cognitive decline and 
some of the aforementioned influencing factors. There-
fore, the relationship between fat distribution/physique 
and cognition requires further consideration of more 
specific fields and possibly integrate multiple physiologi-
cal indicators for exploration. This point has been par-
tially reflected in this study.
Overall, obesity and depression are two prevalent and 
potentially interdependent metabolic disorders, imposing 
a significant disease burden on the health and well-being 
of the middle-aged and older population. This study com-
prehensively examined the impact of the joint trajectories 
of these two diseases on the cognitive development of the 
research subjects and, to some extent, revealed the intri-
cate connections between them and cognitive decline. 
The comorbidity of obesity (obesity indicator: BMI) and 
depression at baseline may have a synergistic negative 
effect on cognitive function. When including the scale 
of time, the conclusions drawn from different cohorts 
were inconsistent. These differences may stem from the 
influence of cultural differences, dietary habits, and the 
geographical environment [101–103]. For instance, a 
Mediterranean diet, rich in antioxidants and healthy fats, 
has been associated with better cognitive function even 
in people living with obesity, whereas high-fat, high-
sugar diets common in Western countries may exacer-
bate cognitive decline [101] Conversely, after conducting 
a parallel analysis employing WHtR as an obesity indica-
tor to reflect the accumulation of abdominal fat, we have 
identified its potential negative impact on cognitive func-
tion in combination with depression. This may be due to 
two shared pathways.
Firstly, both conditions elevate the body’s inflamma-
tory levels. Depressed individuals have higher levels of 
inflammatory markers in their blood, such as interleu-
kin (IL)−1β and C-reactive protein (CRP) [104, 105]. 
Concurrently, adipose tissue has been identified as a 
major source of inflammatory molecules [106], and the 
link between inflammatory cytokines and AO is closer 
than that with BMI [107], suggesting that the accumu-
lation of abdominal fat may predispose the body to a 
pro-inflammatory state [108]. It is worth noting that cir-
culating pro-inflammatory mediators are associated with 
neurodegenerative diseases, and peripheral inflamma-
tion has been shown to negatively impact the develop-
ment of chronic brain inflammation [109]. These insights 
imply that depression and AO may jointly contribute to 
an increase in systemic inflammation, which could sub-
sequently impair cognitive function in middle-aged and 
older adults. Additionally, the combined effects of AO 
and depression are manifested in the elevation of oxi-
dative stress levels. Secondly, during the aging process, 
the brain’s antioxidant defense system becomes increas-
ingly imbalanced, leading to increased oxidative stress, 
which is one of the primary causes of cognitive decline 
[110]. It is widely accepted that abdominal fat is a seri-
ous risk factor for the accumulation of visceral fat, which

# Page 13

Page 13 of 17
Wang et al. BMC Medicine          (2025) 23:555 
	
promotes the release of pro-oxidants, pro-inflammatory 
agents, and reactive oxygen species (ROS) [111, 112]. 
Studies have also demonstrated that antioxidant defenses 
are weakened in individuals with depression, thereby 
increasing oxidative stress [113]. In summary, AO and 
depression may jointly elevate oxidative stress levels 
within the body, which can stimulate brain atrophy and 
morphological changes within the brain that ultimately 
result in cognitive decline [114].
This study has several strengths. Firstly, analyzed mul-
tinational cohorts and a large sample size improve the 
generalizability of the results. Secondly, advanced and 
appropriate analytical methods provide a more compre-
hensive interpretation of the joint contributions of the 
heterogeneous trajectories of obesity and depression 
to cognitive function. Additionally, the current study 
examined multiple obesity-related indicators, which will 
more accurately assess the interrelationship between 
obesity and health status comprehensively. Finally, we 
confirmed the robustness of our findings through vari-
ous sensitivity analyses. To sum up, our findings under-
score the importance of early detection and management 
of both depression and obesity as a potential strategy to 
mitigate cognitive deterioration. Specifically, clinicians 
should screen for depressive symptoms alongside obesity 
assessments (e.g., using BMI or waist-to-height ratio) to 
identify at-risk individuals early, allowing for timely inter-
vention. Moreover, an integrated treatment approach can 
be adopted for patients with obesity-depression comor-
bidity. Combining pharmacotherapy for depression with 
lifestyle modifications aimed at weight management and 
improved physical activity can enhance both mental and 
physical well-being, thereby potentially slowing cognitive 
decline.
Of note, there are several limitations to be acknowl-
edged. Firstly, there is a potential self-reporting bias. 
Height and weight data in the MHAS cohort were self-
reported, potentially misclassifying obesity prevalence 
and obscuring its relationship with cognitive decline, 
as BMI accuracy remains unverified. Secondly, there 
are variations in measurement dimensions of cognitive 
function across different cohorts. Although the study 
attempted to standardize scores from each cohort by 
generating z-scores, it must be acknowledged that dis-
parities in cognitive measurement instruments and their 
respective sensitivities may introduce a degree of system-
atic bias, potentially affecting outcome validity and gen-
eralizability. Thirdly, there are unmeasured confounding 
factors. Although the study adjusted for multiple con-
founding factors, certain variables relevant to cognitive 
function—such as dietary patterns [101], physical activ-
ity levels [86], social support networks [115], and sleep 
quality [116]—were not consistently available across the 
included cohorts due to limitations in data collection or 
heterogeneity in measurement methods. The absence of 
these factors may have influenced the observed associa-
tions. These constraints suggest that the findings should 
be generalized with caution to populations with differing 
sociodemographic characteristics, measurement infra-
structures, or exposure to unmeasured confounders—
particularly among groups who may experience difficulty 
providing accurate and complete data. And to enhance 
generalizability, future research must prioritize: [1] rep-
lication in geographically and culturally diverse cohorts, 
[2] integration of objectively measured variables (e.g., 
accelerometer-derived physical activity, validated dietary 
assessments), and [3] systematic inclusion of previously 
unmeasured confounders. Such efforts are essential to 
validate the observed associations across heterogeneous 
populations and real-world clinical contexts.
Conclusions
Herein, we observed that the comorbidity of obesity 
and depression independently and additively negatively 
affected cognitive function in middle-aged and older 
people. This advocates for clinical screening to prioritize 
depression and abdominal obesity beyond BMI, thereby 
enhancing early identification of high-risk populations. 
Overall, the critical clinical importance of managing 
abdominal fat accumulation and maintaining positive 
emotions to prevent and mitigate cognitive deterioration 
is emphasized. For comorbid cases, an innovative dual-
pathway intervention could be considered: combining 
antidepressant pharmacotherapy with lifestyle-based 
weight management to simultaneously improve mental/
physical health and preserve cognition.
Abbreviations
AO	
Abdominal obesity
BMI	
Body Mass Index
CCCE	
Cross-Cultural Cognitive Examination
CESD	
Center for Epidemiologic Studies Depression Scale
CESD-9	
9-item version of the CESD (used in MHAS)
CESD-10	
10-item version of the CESD (used in CHARLS)
CHARLS	
China Health and Retirement Longitudinal Study
CI	
Confidence interval
CRP	
C-reactive protein
ELSA	
English Longitudinal Study of Ageing
GEE	
Generalized Estimating Equations
GLM	
Generalized linear model
HPA	
Hypothalamic-pituitary-adrenal (axis)
HRS	
Health and Retirement Study
IL-6	
Interleukin-6
KMl3D	
K-means longitudinal clustering in 3 dimensions
MHAS	
Mexican Health and Aging Study
MMSE	
Mini-Mental State Examination
ROS	
Reactive oxygen species
SD	
Standard deviation
TICS	
Telephone Interview for Cognitive Status
WHtR	
Waist-to-height ratio
WHO	
World Health Organization
WWI	
Weight-Adjusted Waist Index
z-score	
Standardized score

# Page 14

Page 14 of 17
Wang et al. BMC Medicine          (2025) 23:555 
Supplementary Information
The online version contains supplementary material available at https://​doi.​
org/​10.​1186/​s12916-​025-​04298-2.
Additional File 1
Acknowledgements
All authors thank the the GATEWAY TO GLOBAL AGING DATA for providing 
the Harmonized Data. We also thank the original data collectors, depositors, 
copyrightholders, and funders of China Health and Retirement LongitudinaS-
tudy, English Longitudinal Study of Ageing, Health andRetirement Study, and 
Mexican Health and Aging Study.
Authors’ contributions
RW, YC and BC contributed to the study design. RW analysed the data and RW, 
YC and BC were involved in data interpretation. RW and YC drafted the first 
version of the manuscript and prepared tables and figures. KMT, RSM, and BC 
reviewed and revised the manuscript. All authors were involved in the writing 
and critical revision of the manuscript. All authors have read and approved the 
final manuscript.
Funding
This work was sponsored by the National Natural Science Foundation of China 
(No. 32300926). The funding agents had no role in the design and conduct 
of the study; collection, management, interpretation of the data; preparation, 
review, or approval of the manuscript.
Data availability
The datasets analyzed during the current study are publicly available and can 
be accessed as follows: CHARLS (China Health and Retirement Longitudinal 
Study): https://​hrs.​isr.​umich.​edu/​about? ELSA (English Longitudinal Study 
of Ageing): https://​ukdat​aserv​ice.​ac.​uk/​about/​HRS (Health and Retirement 
Study): https://​charls.​pku.​edu.​cn/​gy/​gyxm.​htm MHAS (Mexican Health and 
Aging Study): https://​www.​mhasw​eb.​org/​Home/​Index.​aspx All data are free to 
access for bona fide research purposes upon registration with the respective 
study platforms. No personally identifiable information was used. Analysis 
scripts and processed data files can be requested from the corresponding 
author.
Declarations
Ethics approval and consent to participate
The China Health and Retirement Longitudinal Study (CHARLS) received 
approval from the Ethical Review Committee of Peking University 
(IRB00001052-11015). The English Longitudinal Study of Ageing (ELSA) 
was approved by the London Multicentre Research Ethics Committee 
(MREC/01/2/91). The Health and Retirement Study (HRS) was approved by 
the Institutional Review Board at the University of Michigan and the National 
Institute on Aging (HUM00061128) and the Mexican Health and Aging Study 
(MHAS) is partly sponsored by the National Institutes of Health/National 
Institute on Aging (NIH R01AG018016) in the United States and the Instituto 
Nacional de Estadística y Geografía (INEGI) in Mexico. All respondents pro-
vided written informed consent.
Consent for publication
Not applicable.
Competing interests
Dr. Roger S. McIntyre has received research grant support from CIHR/GACD/
National Natural Science Foundation of China (NSFC) and the Milken Institute; 
speaker/consultation fees from Lundbeck, Janssen, Alkermes, Neumora Thera-
peutics, Boehringer Ingelheim, Sage, Biogen, Mitsubishi Tanabe, Purdue, Pfizer, 
Otsuka, Takeda, Neurocrine, Neurawell, Sunovion, Bausch Health, Axsome, 
Novo Nordisk, Kris, Sanofi, Eisai, Intra-Cellular, NewBridge Pharmaceuticals, 
Viatris, Abbvie and Atai Life Sciences. Kayla M. Teopiz has received fees from 
Braxia Scientific Corp.All other authors have no conflicts of interest to declare.
Author details
1 Key Laboratory of Cognition and Personality, Faculty of Psychology, Ministry 
of Education, Southwest University, Chongqing 400715, People’s Republic 
of China. 2 Brain and Cognition Discovery Foundation, Toronto, ON, Canada. 
3 Department of Psychiatry, University of Toronto, Toronto, ON, Canada. 
4 Department of Pharmacology and Toxicology, University of Toronto, Toronto, 
ON, Canada. 5 National Demonstration Center for Experimental Psychology 
Education, Southwest University, Chongqing 400715, People’s Republic 
of China. 
Received: 14 April 2025   Accepted: 24 July 2025
References
	
1.	 Luppino FS, de Wit LM, Bouvy PF, Stijnen T, Cuijpers P, Penninx BW, et al. 
Overweight, obesity, and depression: a systematic review and meta-
analysis of longitudinal studies. Arch Gen Psychiatry. 2010;67(3):220–9.
	
2.	 McIntyre RS. The co-occurrence of depression and obesity: implications 
for clinical practice and the discovery of targeted and precise mecha-
nistically informed therapeutics. J Clin Psychiatry. 2024;85(2):55135.
	
3.	 Lin L, Bai S, Qin K, Wong CKH, Wu T, Chen D, et al. Comorbid depres-
sion and obesity, and its transition on the risk of functional disability 
among middle-aged and older Chinese: a cohort study. BMC Geriatr. 
2022;22(1):275.
	
4.	 CDC. Obesity prevalence among adults in the United States, 2017-2020. 
Centers for Disease Control and Prevention (CDC); 2023 [cited 2025 Jun 
13]. Available from: https://​www.​cdc.​gov/​obesi​ty/​adult-​obesi​ty-​facts/​
index.​html.
	
5.	 Christl J, Grumbach P, Jockwitz C, Wege N, Caspers S, Meisenzahl E. 
Prevalence of depressive symptoms in people aged 50 years and older: 
a retrospective cross-sectional study. J Affect Disord. 2025;373:353–63.
	
6.	 Zhang H, Zheng R, Yu B, Yu Y, Luo X, Yin S, et al. Dissecting shared 
genetic architecture between depression and body mass index. BMC 
Medicine. 2024;22(1):455.
	
7.	 Milaneschi Y, Simmons WK, van Rossum EFC, Penninx BWJH. Depression 
and obesity: evidence of shared biological mechanisms. Mol Psychiatry. 
2018;24(1):18–33.
	
8.	 Mannan M, Mamun A, Doi S, Clavarino A. Is there a bi-directional 
relationship between depression and obesity among adult men and 
women? Systematic review and bias-adjusted meta analysis. Asian J 
Psychiatry. 2016;21:51–66.
	
9.	 Grapsa I, Mamalaki E, Ntanasi E, Kosmidis MH, Dardiotis E, Hadjigeorgiou 
GM, et al. Longitudinal examination of body mass index and cognitive 
function in older adults: the HELIAD study. Nutrients. 2023;15(7):1795.
	 10.	 Muhammad T, Meher T. Association of late-life depression with cogni-
tive impairment: evidence from a cross-sectional study among older 
adults in India. BMC Geriatr. 2021;21(1):364.
	 11.	 McIntyre RS, Cha DS, Soczynska JK, Woldeyohannes HO, Gallaugher LA, 
Kudlow P, et al. Cognitive Deficits and functional outcomes in major 
depressive disorder: determinants, substrates, and treatment interven-
tions. Depress Anxiety. 2013;30(6):515–27.
	 12.	 Lin L, Bai S, Qin K, Wong CKH, Wu T, Chen D, et al. Comorbid depres-
sion and obesity, and its transition on the risk of functional disability 
among middle-aged and older Chinese: a cohort study. BMC Geriatrics. 
2022;22(1):275.
	 13.	 Collyer TA, Murray AM, Woods RL, Storey E, Chong TTJ, Ryan J, et al. 
Association of dual decline in cognition and gait speed with risk of 
dementia in older adults. JAMA Network Open. 2022;5(5).
	 14.	 Elías-López D, Vargas-Vázquez A, Mehta R, Cruz Bautista I, Del Razo 
Olvera F, Gómez-Velasco D, et al. Natural course of metabolically 
healthy phenotype and risk of developing Cardiometabolic diseases: a 
three years follow-up study. BMC Endocr Disord. 2021;21(1):85.
	 15.	 Ganguli M, Beer JC, Zmuda JM, Ryan CM, Sullivan KJ, Chang CCH, et al. 
Aging, diabetes, obesity, and cognitive decline: a population-based 
study. J Am Geriatr Soc. 2020;68(5):991–8.
	 16.	 Miller AA, Spencer SJ. Obesity and neuroinflammation: a pathway to 
cognitive impairment. Brain Behav Immun. 2014;42:10–21.

# Page 15

Page 15 of 17
Wang et al. BMC Medicine          (2025) 23:555 
	
	 17.	 Fu X, Wang Y, Zhao F, Cui R, Xie W, Liu Q, et al. Shared biological mecha-
nisms of depression and obesity: focus on adipokines and lipokines. 
Aging (Albany NY). 2023;15(12):5917.
	 18.	 Kaup AR, Byers AL, Falvey C, Simonsick EM, Satterfield S, Ayonayon HN, 
et al. Trajectories of depressive symptoms in older adults and risk of 
dementia. JAMA Psychiatry. 2016;73(5):523–31.
	 19.	 Yang X, Pan A, Gong J, Wen Y, Ye Y, Wu JHY, et al. Prospective associa-
tions between depressive symptoms and cognitive functions in mid-
dle-aged and elderly Chinese adults. J Affect Disord. 2020;263:692–7.
	 20.	 Zhang B, Lin Y, Hu M, Sun Y, Xu M, Hao J, et al. Associations between tra-
jectories of depressive symptoms and rate of cognitive decline among 
Chinese middle-aged and older adults: an 8-year longitudinal study. J 
Psychosom Res. 2022;160:110986.
	 21.	 Keller J, Gomez R, Williams G, Lembke A, Lazzeroni L, Murphy GM, et al. 
HPA axis in major depression: cortisol, clinical symptomatology and 
genetic variation predict cognition. Mol Psychiatry. 2016;22(4):527–36.
	 22.	 Frank P, Jokela M, Batty GD, Cadar D, Steptoe A, Kivimäki M. Association 
between systemic inflammation and individual symptoms of depres-
sion: a pooled analysis of 15 population-based cohort studies. Am J 
Psychiatry. 2021;178(12):1107–18.
	 23.	 Videbech P, Ravnkilde B. Hippocampal volume and depression: a meta-
analysis of MRI studies. Am J Psychiatry. 2004;161(11):1957–66.
	 24.	 Rock PL, Roiser JP, Riedel WJ, Blackwell AD. Cognitive impairment 
in depression: a systematic review and meta-analysis. Psychol Med. 
2013;44(10):2029–40.
	 25.	 McDermott LM, Ebmeier KP. A meta-analysis of depression severity and 
cognitive function. J Affect Disord. 2009;119(1–3):1–8.
	 26.	 Albanese E, Launer LJ, Egger M, Prince MJ, Giannakopoulos P, Wolters 
FJ, et al. Body mass index in midlife and dementia: systematic review 
and meta-regression analysis of 589,649 men and women followed in 
longitudinal studies. Alzheimer’s & Dementia: Diagnosis, Assessment & 
Disease Monitoring. 2017;8(1):165–78.
	 27.	 Pedditizi E, Peters R, Beckett N. The risk of overweight/obesity in mid-life 
and late life for the development of dementia: a systematic review and 
meta-analysis of longitudinal studies. Age Ageing. 2016;45(1):14–21.
	 28.	 Kim G, Choi S, Lyu J. Body mass index and trajectories of cogni-
tive decline among older Korean adults. Aging Ment Health. 
2019;24(5):758–64.
	 29.	 McIntyre RS, Rong C, Mansur RB, Brietzke E. Does obesity and diabetes 
mellitus metastasize to the brain? “Metaboptosis” and implications for 
drug discovery and development. CNS Spectr. 2019;24(5):467–9.
	 30.	 Norton S, Matthews FE, Barnes DE, Yaffe K, Brayne C. Potential for 
primary prevention of Alzheimer’s disease: an analysis of population-
based data. Lancet Neurol. 2014;13(8):788–94.
	 31.	 Liang F, Fu J, Moore JB, Zhang X, Xu Y, Qiu N, et al. Body mass index, 
waist circumference, and cognitive decline among Chinese older 
adults: a nationwide retrospective cohort study. Front Aging Neurosci. 
2022;14: 737532.
	 32.	 Tang X, Zhao W, Lu M, Zhang X, Zhang P, Xin Z, et al. Relationship 
between central obesity and the incidence of cognitive impairment 
and dementia from cohort studies involving 5,060,687 participants. 
Neurosci Biobehav Rev. 2021;130:301–13.
	 33.	 Tang H, Li Q, Du C. The association between waist-to-height ratio and 
cognitive function in older adults. Nutr Neurosci. 2024;27(12):1405–12.
	 34.	 Wang S-H, Su M-H, Chen C-Y, Lin Y-F, Feng Y-CA, Hsiao P-C, et al. 
Causality of abdominal obesity on cognition: a trans-ethnic Mendelian 
randomization study. Int J Obes. 2022;46(8):1487–92.
	 35.	 Ren Z, Li Y, Li X, Shi H, Zhao H, He M, et al. Associations of body mass 
index, waist circumference and waist-to-height ratio with cognitive 
impairment among Chinese older adults: based on the CLHLS. J Affect 
Disord. 2021;295:463–70.
	 36.	 Dye L, Boyle NB, Champ C, Lawton C. The relationship between obesity 
and cognitive health and decline. Proc Nutr Soc. 2017;76(4):443–54.
	 37.	 Li J, Sun J, Zhang Y, Zhang B, Zhou L. Association between weight-
adjusted-waist index and cognitive decline in US elderly participants. 
Front Nutr. 2024;11:1390282.
	 38.	 Team CR. China Health and Retirement Longitudinal Study (CHARLS). 
Peking University; 2015 [cited 2024 Jul 2]. Available from: https://​charls.​
pku.​edu.​cn/​gy/​gyxm.​htm.
	 39.	 Banks J, Batty, G. D., Breedvelt, J., Coughlin, K., Crawford, R., Marmot, 
M., Nazroo, J., Oldfield, Z., Steel, N., Steptoe, A., Wood, M., Zaninotto, P. 
English Longitudinal Study of Ageing: Waves 0–10, 1998–2023: UK Data 
Service; 2024 Available from: https://​ukdat​aserv​ice.​ac.​uk/​about/.
	 40.	 Health and Retirement Study pud. Health and Retirement Study, public 
use dataset. University of Michigan; 2016 [cited 2024 Jul 3]. Available 
from: https://​hrs.​isr.​umich.​edu/​about.
	 41.	 (MHAS) MHaAS. Mexican Health and Aging Study (MHAS). University of 
Texas Medical Branch & INEGI; 2018 [cited 2024 Jul 4]. Available from: 
https://​www.​mhasw​eb.​org/​Home/​Index.​aspx.
	 42.	 Xu T, Ye X, Lu X, Lan G, Xie M, Huang Z, et al. Association between solid 
cooking fuel and cognitive decline: three nationwide cohort studies in 
middle-aged and older population. Environ Int. 2023;173: 107803.
	 43.	 Tan K. Appropriate body-mass index for Asian populations and 
its implications for policy and intervention strategies. The lancet. 
2004;363(9403):157–63.
	 44.	 Talaei M, Feng L, Barrenetxea J, Yuan J-M, Pan A, Koh W-P. Adiposity, 
weight change, and risk of cognitive impairment: the Singapore Chi-
nese Health Study. J Alzheimers Dis. 2020;74(1):319–29.
	 45.	 Consultation W. Obesity: preventing and managing the global epi-
demic. World Health Organ Tech Rep Ser. 2000;894:1–253.
	 46.	 Chan V, Cao L, Wong MMH, Lo K, Tam W. Diagnostic accuracy of waist-
to-height ratio, waist circumference, and body mass index in identifying 
metabolic syndrome and its components in older adults: a systematic 
review and meta-analysis. Curr Dev Nutr. 2024;8(1):102061.
	 47.	 Konig HH, Lehnert T, Brenner H, Schottker B, Quinzler R, Haefeli WE, et al. 
Health service use and costs associated with excess weight in older 
adults in Germany. Age Ageing. 2015;44(4):616–23.
	 48.	 Ye J, Hu Y, Chen X, Yin Z, Yuan X, Huang L, et al. Association between the 
weight-adjusted waist index and stroke: a cross-sectional study. BMC 
Public Health. 2023;23(1):1689.
	 49.	 Liu H, Zhi J, Zhang C, Huang S, Ma Y, Luo D, et al. Association between 
weight-adjusted waist index and depressive symptoms: a nationally 
representative cross-sectional study from NHANES 2005 to 2018. J 
Affect Disord. 2024;350:49–57.
	 50.	 Park Y, Kim NH, Kwon TY, Kim SG. A novel adiposity index as an inte-
grated predictor of cardiometabolic disease morbidity and mortality. 
Scientific Reports. 2018;8(1):16753.
	 51.	 Andresen EM, Malmgren JA, Carter WB, Patrick DL. Screening for 
depression in well older adults: evaluation of. Prev Med. 1994;10:77–84.
	 52.	 Steffick D. Documentation of affective functioning measures in the 
Health and Retirement Study. 2000. Available from: https://​hrs.​isr.​umich.​
edu/​docum​entat​ion/​affec​tive-​funct​ioning.
	 53.	 Poole L, Jackowska M. The epidemiology of depressive symptoms and 
poor sleep: findings from the English longitudinal study of ageing 
(ELSA). Int J Behav Med. 2018;25(2):151–61.
	 54.	 García-Pérez A, Pineda AEG-A, Sandoval-Bonilla BA, Cruz-Hervert LP. 
Prevalence and factors associated with depressive symptoms in rural 
and urban Mexican older adults: evidence from the Mexican Health 
and Aging Study 2018. salud pública de méxico. 2022;64(4):367–76.
	 55.	 Cruz-Cruz C, Zamora-Macorra M, Astudillo-García CI, Guerra G. Intersec-
tionality and depression symptoms in Mexican adults aged≥ 50, MHAS 
2001 and 2012. salud pública de méxico. 2023;65(5):475–84.
	 56.	 Palta P, Carlson MC, Crum RM, Colantuoni E, Sharrett AR, Yasar S, 
et al. Diabetes and cognitive decline in older adults: the ginkgo 
evaluation of memory study. The Journals of Gerontology: Series A. 
2018;73(1):123–30.
	 57.	 Weir D, Faul J, Langa K. Proxy interviews and bias in the distribution 
of cognitive abilities due to non-response in longitudinal studies: a 
comparison of HRS and ELSA. Longitudinal and life course studies. 
2011;2(2):170.
	 58.	 Langa KM, Llewellyn DJ, Lang IA, Weir DR, Wallace RB, Kabeto MU, 
et al. Cognitive health among older adults in the United States and in 
England. BMC Geriatr. 2009;9(1):23.
	 59.	 Li C, Zhu Y, Ma Y, Hua R, Zhong B, Xie W. Association of cumulative 
blood pressure with cognitive decline, dementia, and mortality. J Am 
Coll Cardiol. 2022;79(14):1321–35.
	 60.	 Barragán-García M, Ramírez-Aldana R, López-Ortega M, Sánchez-
García S, García-Peña C. Widowhood status and cognitive function in 
community-dwelling older adults from the Mexican Health and Aging 
Study (MHAS). J Popul Ageing. 2022;15(3):605–22.
	 61.	 Zheng F, Yan L, Zhong B, Yang Z, Xie W. Progression of cognitive decline 
before and after incident stroke. Neurology. 2019;93(1):e20–8.

# Page 16

Page 16 of 17
Wang et al. BMC Medicine          (2025) 23:555 
	 62.	 He D, Wang Z, Li J, Yu K, He Y, He X, et al. Changes in frailty and incident 
cardiovascular disease in three prospective cohorts. Eur Heart J. 
2024;45(12):1058–68.
	 63.	 Genolini C. kml3d: K-Means for Joint Longitudinal Data (p. 2.4.6.1) [Data-
set]. 2010 [cited 2024 Sep 10]. Available from: https://​cran.r-​proje​ct.​org/​
web/​packa​ges/​kml3d/​index.​html.
	 64.	 Hartigan JA, Wong MA. Algorithm AS 136: A k-means clustering algo-
rithm. J Roy Stat Soc: Ser C (Appl Stat). 1979;28(1):100–8.
	 65.	 Genolini C, Alacoque X, Sentenac M, Arnaud C. kml and kml3d: R pack-
ages to cluster longitudinal data. J Stat Softw. 2015;65:1–34.
	 66.	 Genolini C, Pingault J-B, Driss T, Côté S, Tremblay RE, Vitaro F, et al. 
KmL3D: a non-parametric algorithm for clustering joint trajectories. 
Comput Methods Programs Biomed. 2013;109(1):104–11.
	 67.	 Farrahi V, Rostami M, Dumuid D, Chastin SF, Niemelä M, Korpelainen R, 
et al. Joint profiles of sedentary time and physical activity in adults and 
their associations with cardiometabolic health. Med Sci Sports Exerc. 
2022;54(12):2118.
	 68.	 Ziegler A, Vens M. Generalized estimating equations. Methods Inf Med. 
2010;49(05):421–5.
	 69.	 Graham EA, Deschênes SS, Khalil MN, Danna S, Filion KB, Schmitz N. 
Measures of depression and risk of type 2 diabetes: a systematic review 
and meta-analysis. J Affect Disord. 2020;265:224–32.
	 70.	 Jawad MY, Meshkat S, Tabassum A, McKenzie A, Di Vincenzo JD, Guo 
Z, et al. The bidirectional association of nonalcoholic fatty liver disease 
with depression, bipolar disorder, and schizophrenia. CNS Spectr. 
2022;28(5):541–60.
	 71.	 Luo H, Li J, Zhang Q, Cao P, Ren X, Fang A, et al. Obesity and the onset of 
depressive symptoms among middle-aged and older adults in China: 
evidence from the CHARLS. BMC Public Health. 2018;18(1):909.
	 72.	 McGrowder DA, Fang T, Zhang Q, Wang Z, Liu J-P. Bidirectional associa-
tion between depression and diabetic nephropathy by meta-analysis. 
Plos One. 2022;17(12):e0278489.
	 73.	 Pu F, Lin J, Wei Y, Li J, Liao X, Shi L, et al. Association of dietary behavior 
patterns of middle-aged and older adults with their obesity metabolic 
phenotype: a cross-sectional study. BMC Public Health. 2024;24(1):2311.
	 74.	 Zhao Q, Tan X, Su Z, Manzi HP, Su L, Tang Z, et al. The relationship 
between the Dietary Inflammatory Index (DII) and Metabolic Syndrome 
(MetS) in middle-aged and elderly individuals in the United States. 
Nutrients. 2023;15(8):1857.
	 75.	 Hemphill L, Valenzuela Y, Luna K, Szymkowicz SM, Jones JD. Synergistic 
associations of depressive symptoms and aging on cognitive decline in 
early Parkinson’s disease. Clin Park Relat Disord. 2023;8:100192.
	 76.	 Yuan J, Wang Y, Liu Z. Temporal relationship between depression and 
cognitive decline in the elderly: a two-wave cross-lagged study in a 
Chinese sample. Aging Ment Health. 2023;27(11):2179–86.
	 77.	 Zheng F, Zhong B, Song X, Xie W. Persistent depressive symptoms and 
cognitive decline in older adults. Br J Psychiatry. 2018;213(5):638–44.
	 78.	 Federman AD, Becker J, Carnavali F, Rivera Mindt M, Cho D, Pandey 
G, et al. Relationship between cognitive impairment and depression 
among middle aged and older adults in primary care. Gerontol Geriatr 
Med. 2024;10:23337214231214216.
	 79.	 Manning KJ, Steffens DC. Systems Neuroscience in Late-Life Depres-
sion. Systems Neuroscience in Depression2016. p. 325–40.
	 80.	 Rieck JR, Baracchini G, Nichol D, Abdi H, Grady CL. Reconfiguration and 
dedifferentiation of functional networks during cognitive control across 
the adult lifespan. Neurobiol Aging. 2021;106:80–94.
	 81.	 Staffaroni AM, Brown JA, Casaletto KB, Elahi FM, Deng J, Neuhaus J, 
et al. The longitudinal trajectory of default mode network connectiv-
ity in healthy older adults varies as a function of age and is associated 
with changes in episodic memory and processing speed. J Neurosci. 
2018;38(11):2809–17.
	 82.	 Jellinger KA. Pathomechanisms of Vascular Depression in Older Adults. 
Int J Mol Sci. 2021;23(1):308.
	 83.	 Straka K, Tran M-L, Millwood S, Swanson J, Kuhlman KR. Aging as a 
context for the role of inflammation in depressive symptoms. Front 
Psychiatry. 2021;11.
	 84.	 Mina T, Yew YW, Ng HK, Sadhu N, Wansaicheong G, Dalan R, et al. Adi-
posity impacts cognitive function in Asian populations: an epidemio-
logical and Mendelian Randomization study. Lancet Reg Health West 
Pac. 2023;33:100710.
	 85.	 Liu CR, Wong PY, Chung YL, Chow SKH, Cheung WH, Law SW, et al. 
Deciphering the “obesity paradox” in the elderly: a systematic review 
and meta-analysis of sarcopenic obesity. Obes Rev. 2023. https://​doi.​
org/​10.​1111/​obr.​13534.
	 86.	 Iso-Markku P, Kujala UM, Knittle K, Polet J, Vuoksimaa E, Waller K. Physical 
activity as a protective factor for dementia and Alzheimer’s disease: 
systematic review, meta-analysis and quality assessment of cohort and 
case–control studies. Br J Sports Med. 2022;56(12):701–9.
	 87.	 Rodriguez-Ayllon M, Solis-Urra P, Arroyo-Ávila C, Álvarez-Ortega M, 
Molina-García P, Molina-Hidalgo C, et al. Physical activity and amyloid 
beta in middle-aged and older adults: a systematic review and meta-
analysis. J Sport Health Sci. 2024;13(2):133–44.
	 88.	 Coin A, Veronese N, De Rui M, Mosele M, Bolzetta F, Girardi A, et al. Nutri-
tional predictors of cognitive impairment severity in demented elderly 
patients: the key role of BMI. J Nutr Health Aging. 2012;16(6):553–6.
	 89.	 Hegele RA, Joy TR, Al-Attar SA, Rutt BK. Thematic review series: 
adipocyte Biology. Lipodystrophies: windows on adipose biology and 
metabolism. Journal of Lipid Research. 2007;48(7):1433–44.
	 90.	 Shinohara M, Gheni G, Hitomi J, Bu G, Sato N. APOE genotypes modify 
the obesity paradox in dementia. J Neurol Neurosurg Psychiatry. 
2023;94(9):670–80.
	 91.	 Zhang J, Na X, Li Z, Ji JS, Li G, Yang H, et al. Sarcopenic obesity is 
part of obesity paradox in dementia development: evidence from a 
population-based cohort study. BMC Med. 2024;22(1):133.
	 92.	 Zhang F, Ning Z, Wang C. Body roundness index and cognitive func-
tion in older adults: a nationwide perspective. Front Aging Neurosci. 
2024;16:1466464.
	 93.	 Liang Z, Jin W, Huang L, Chen H. Body mass index, waist circumfer-
ence, hip circumference, abdominal volume index, and cognitive 
function in older Chinese people: a nationwide study. BMC Geriatrics. 
2024;24(1):925.
	 94.	 Forte R, Pesce C, de Vito G, Boreham CAG. The body fat-cognition 
relationship in healthy older individuals: does gynoid vs android distri-
bution matter? J Nutr Health Aging. 2017;21(3):284–92.
	 95.	 Liu X, Chen X, Hou L, Xia X, Hu F, Luo S, et al. Associations of body mass 
index, visceral fat area, waist circumference, and waist-to-hip ratio with 
cognitive function in western China: results from WCHAT study. J Nutr 
Health Aging. 2021;25(7):903–8.
	 96.	 Xu S, Wen S, Yang Y, He J, Yang H, Qu Y, et al. Association between body 
composition patterns, cardiovascular disease, and risk of neurodegen-
erative disease in the UK Biobank. Neurology. 2024;103(4):e209659.
	 97.	 Chu C-Q, Yu L-l, Qi G-y, Mi Y-S, Wu W-Q, Lee Y-k, et al. Can dietary pat-
terns prevent cognitive impairment and reduce Alzheimer’s disease 
risk: exploring the underlying mechanisms of effects. Neurosci Biobe-
hav Rev. 2022;135:104556.
	 98.	 Wei K, Yang J, Lin S, Mei Y, An N, Cao X, et al. Dietary habits modify 
the association of physical exercise with cognitive impairment in 
community-dwelling older adults. J Clin Med. 2022;11(17):512.
	 99.	 Witczak-Sawczuk K, Ostrowska L, Cwalina U, Leszczyńska J, Jastrzębska-
Mierzyńska M, Hładuński MK. Estimation of the impact of abdominal 
adipose tissue (subcutaneous and visceral) on the occurrence of car-
bohydrate and lipid metabolism disorders in patients with obesity—a 
pilot study. Nutrients. 2024;16(9):1301.
	100.	 Zhu C-e, Zhou L, Zhang X. Effects of leisure activities on the cognitive 
ability of older adults: a latent variable growth model analysis. Front 
Psychol. 2022;13:838878
	101.	 Scarmeas N, Stern Y, Mayeux R, Luchsinger JA. Mediterranean 
diet, Alzheimer disease, and vascular mediation. Arch Neurol. 
2006;63(12):1709–17.
	102.	 Zhao Y-L, Qu Y, Ou Y-N, Zhang Y-R, Tan L, Yu J-T. Environmental factors 
and risks of cognitive impairment and dementia: a systematic review 
and meta-analysis. Ageing Res Rev. 2021;72: 101504.
	103.	 Lavallee KL, Zhang XC, Schneider S, Margraf J. Obesity and mental 
health: a longitudinal, cross-cultural examination in Germany and 
China. Front Psychol. 2021;12:712567.
	104.	 Johnston JN, Greenwald MS, Henter ID, Kraus C, Mkrtchian A, Clark NG, 
et al. Inflammation, stress and depression: an exploration of ketamine’s 
therapeutic profile. Drug Discov Today. 2023;28(4):103518.
	105.	 Majd M, Saunders EFH, Engeland CG. Inflammation and the dimensions 
of depression: a review. Front Neuroendocrinol. 2020;56:100800.

# Page 17

Page 17 of 17
Wang et al. BMC Medicine          (2025) 23:555 
	
	106.	 Unamuno X, Gómez-Ambrosi J, Rodríguez A, Becerril S, Frühbeck G, 
Catalán V. Adipokine dysregulation and adipose tissue inflammation in 
human obesity. Eur J Clin Invest.  2018;48(9):e12997.
	107.	 Pou KM, Massaro JM, Hoffmann U, Vasan RS, Maurovich-Horvat P, Larson 
MG, et al. Visceral and subcutaneous adipose tissue volumes are cross-
sectionally related to markers of inflammation and oxidative stress. 
Circulation. 2007;116(11):1234–41.
	108.	 Lin W-T, Kao Y-H, Li MS, Luo T, Lin H-Y, Lee C-H, et al. Sugar-sweetened 
beverages intake, abdominal obesity, and inflammation among US 
adults without and with prediabetes—an NHANES Study. Int J Environ 
Res Public Health.  2022;20(1):681.
	109.	 Gonzales MM, Garbarino VR, Pollet E, Palavicini JP, Kellogg DL, Kraig 
E, et al. Biological aging processes underlying cognitive decline and 
neurodegenerative disease. J Clin Invest. 2022;132(10):e158453.
	110.	 Mulè S, Ferrari S, Rosso G, Galla R, Battaglia S, Curti V, et al. The com-
bined effect of green tea, saffron, resveratrol, and citicoline against 
neurodegeneration induced by oxidative stress in an in vitro model of 
cognitive decline. Oxid Med Cell Longev. 2024;2024(1):7465045.
	111.	 Oyerinde AS, Selvaraju V, Babu JR, Geetha T. Potential role of oxidative 
stress in the production of volatile organic compounds in obesity. 
Antioxidants. 2023;12(1):129.
	112.	 Yeo J, Hwang IC, Ahn HY. Association between oxidative balance 
score and neck circumference in Korean adults. Obes Res Clin Pract. 
2022;16(4):343–5.
	113.	 Sipahi H, Mat AF, Özhan Y, Aydin A. The interrelation between oxidative 
stress, depression and inflammation through the kynurenine pathway. 
Curr Top Med Chem. 2023;23(6):415–25.
	114.	 Naomi R, Teoh SH, Embong H, Balan SS, Othman F, Bahari H, et al. 
The role of oxidative stress and inflammation in obesity and its 
impact on cognitive impairments—a narrative review. Antioxidants. 
2023;12(5):1071.
	115.	 Kelly ME, Duff H, Kelly S, McHugh Power JE, Brennan S, Lawlor BA, et al. 
The impact of social activities, social networks, social support and social 
relationships on the cognitive functioning of healthy older adults: a 
systematic review. Sys Rev. 2017;6(1):259.
	116.	 Ma Y, Liang L, Zheng F, Shi L, Zhong B, Xie W. Association between 
sleep duration and cognitive decline. JAMA Network Open. 
2020;3(9):e2013573.
Publisher’s Note
Springer Nature remains neutral with regard to jurisdictional claims in pub-
lished maps and institutional affiliations.
