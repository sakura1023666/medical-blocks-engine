# Page 1

Precision Clinical Medicine , 2025, 8 : pbaf003 
DOI: 10.1093/pcmedi/pbaf003 
Methodology 
Predicti v e model for daily risk alerts in sepsis patients in 
the ICU: visualization and clinical analysis of risk 
indicators 
Hao Yang, 1 ,2 ,‡ Jiaxi Li, 3 ,‡ Chi Zhang, 4 Alejandro Pazos Sierra, 2 , * Bairong Shen 
4 , * 
1 Information Center, West China Hospital of Sichuan University, Chengdu 610041, China 
2 Department of Computer Science and Information Tec hnologies, Researc h Center for Information and Communications Tec hnologies, Univ ersity of A Coruña, 
Biomedical Research Institute of a Coruña, A Coruña 15071, Spain 
3 Department of Clinical Laboratory Medicine, Jinniu Maternity and Child Health Hospital of Chengdu, Chengdu 610031, China 
4 Joint Laboratory of Artificial Intelligence for Critical Care Medicine, Department of Critical Care Medicine and Institutes for Systems Genetics, Frontiers Science 
Center for Disease-related Molecular Network, West China Hospital, Sichuan University, Chengdu 610041, China 
∗Corr esponding authors. Bair ong Sheng, bair ong.shen@scu.edu.cn ; Alejandr o P azos Sierr a, a pazos@udc.es 
‡ Hao Yang and Jiaxi Li contributed equally to this work. 
Abstract 
This study introduces a novel Transformer-based time-series framework designed to r ev olutionize risk stratification in Intensi v e Car e 
Units (ICUs) by predicting patient outcomes with high temporal precision. Leveraging sequential data from the eICU database, our 
tw o-stage ar c hitecture dynamically captures evolving health trajectories throughout a patient’s ICU stay, enabling real-time identifi- 
cation of high-risk individuals and actionable insights for personalized interventions. The model demonstrated exceptional predictive 
pow er, ac hieving a pr ogr essi v e AUC incr ease fr om 0.87 ( ±0.021) on admission da y to 0.92 ( ±0.009) b y da y 5, reflecting its capacity to as- 
similate long itudinal physiolog ical patterns. Rigor ous external v alidation acr oss geographicall y di v erse cohorts—including an 81.8% 
accuracy on Chinese sepsis data (AUC = 0.73) and 76.56% accuracy on MIMIC-IV-3.1 (AUC = 0.84)—confirmed r obust generaliza bility. Cru- 
ciall y, SHAP-deri v ed temporal heatmaps unveiled mortality-associated feature dynamics over time, bridging the gap between model 
predictions and clinically interpretable biomarkers. These findings establish a new paradigm for ICU prognostics, where data-driven 
temporal modeling synergizes with clinician expertise to optimize tria ge, r educe dia gnostic latency, and ultimatel y impr ov e survi v al 
outcomes in critical care. 
Keywords: sepsis; Transformer; time-series; visualization; predicting mortality 
Recei v ed 17 November 2024; revised 26 January 2025; accepted 27 January 2025. published 8 February 2025 
© The Author(s) 2025. Published by Oxford Uni v ersity Pr ess on behalf of the W est China School of Medicine & W est China Hospital of Sichuan Uni v ersity. This 
is an Open Access article distributed under the terms of the Cr eati v e Commons Attribution License ( https://creativecommons.org/licenses/by/4.0/ ), which 
permits unrestricted reuse, distribution, and reproduction in any medium, provided the original work is properly cited. 
Downloaded from https://academic.oup.com/pcm/article/8/1/pbaf003/8005968 by guest on 07 March 2025

# Page 2

2 | Yang et al 
Gr aphical Abstr act 
The fr amew ork of hospital system inte gr ation with pr edicti v e models. 
Introduction 
Sepsis is defined as life-threatening organ dysfunction resulting 
from a dysregulated host response to infection, as outlined in the 
Sepsis-3 definition [ 1 ]. It is a critical medical emergency and clin- 
ical syndrome characterized by widespread inflammation. Sepsis 
can also lead to disseminated intr av ascular coa gulation [ 2 ], caus- 
ing multiple organ failures, high mortality rates, and long-term 
disability among survi vors. Se psis is most commonly observed in 
critically ill patients, with in-hospital mortality r anging fr om 20 
to 50% [ 3 ]. Despite continuous advancements in medical technol- 
ogy that enable timely and effective treatment, a subset of pa- 
tients still succumbs to the acute pr ogr ession of sepsis . T her efor e, 
accur atel y pr edicting mortality risk in sepsis patients is of 
paramount clinical importance. Such prognostic predictions can 
help intensivists make prompt, informed decisions regarding in- 
terv entions, ultimatel y impr oving surviv al outcomes for sepsis 
patients. 
Accur atel y pr edicting mortality among sepsis patients is cru- 
cial for clinical physicians, as it facilitates not only the eval- 
uation of disease se v erity but also the optimization of treat- 
ment str ategies, r eduction in adv erse outcomes, and extension 
of patient longe vity. Pr esentl y, v arious clinical scoring systems, 
such as the sequential organ failure assessment score [ 4 ] and 
the acute physiology and c hr onic health e v aluation (APACHE-II) 
scoring system [ 5 ], assist clinicians in e v aluating sepsis se v erity 
and predicting adverse events . Nonetheless , these scoring systems 
ar e de vised for the broader population of critically ill patients and 
do not specifically target se psis. Gi ven the critical nature of sep- 
sis, the diagnosis and treatment are of great importance, and an 
earl y pr e-sepsis dia gnosis could potentiall y enhance patient sur- 
viv al r ates. 
Recentl y, mac hine learning in medical r esearc h has facilitated 
the de v elopment of pr edictiv e models customized to specific clin- 
ical r equir ements and data c har acteristics, exhibiting superior 
pr edictiv e performance in anticipating adverse outcomes com- 
par ed to conv entional clinical scoring systems . T he construction 
of existing sepsis mortality prediction models predominantly re- 
lies on the utilization of machine learning models, like logistic 
r egr ession, r andom for est, and XGBoost [ 6 ], and ac hie v ed a good 
area under the receiver operating characteristic curve (AUC) in the 
range 0.70–0.85 [ 7–9 ]. Ho w ever, there is still considerable potential 
to impr ov e their performance. 
The majority of r esearc h has focused on constructing predic- 
tive models using data from isolated instances or patient-specific 
time interv als, inadv ertentl y ov erlooking the tempor al e volution 
of underlying disease conditions. In this study, we utilized the 
eICU Collabor ativ e Researc h Database [ 10 ], focusing on patients 
diagnosed with sepsis, and conducted experiments by extracting 
r ele v ant data suc h as vital signs and labor atory test r esults r elated 
to sepsis . T hr ough or ganizing this data c hr onologicall y and ana- 
lyzing the statistical characteristics and temporal patterns of the 
time-series samples, we constructed a time-series model based 
on the Transformer architecture [ 11 ] to predict mortality risk in 
sepsis patients . Furthermore , visual algorithms were used to an- 
al yze activ ation c har acteristics at differ ent time interv als to ex- 
plore their correlation with the risk of sepsis-related death. Our 
objective is to provide novel insights and approaches for the treat- 
ment and prognosis of sepsis by establishing a temporal model. 
Methods and materials 
Participants 
The eICU Collabor ativ e Researc h Database is a compr ehensiv e, 
m ulti-center intensiv e car e unit (ICU) dataset de v eloped thr ough 
a collaboration between the Massachusetts Institute of Technol- 
ogy and the Philips Group. It contains high-quality clinical data 
from > 200 000 patients admitted to 208 hospitals across the USA, 
spanning the years 2014 to 2015. The dataset includes diverse in- 
formation such as demographics, vital signs, laboratory results, 
tr eatments, dia gnoses, and mor e, with its r eliability v alidated 
thr ough m ultiple r esearc h studies [ 10 ]. 
The study included patients diagnosed with sepsis, as recorded 
in the diagnostic table of the eICU database. Exclusion crite- 
ria were as follows: patients under 18 years of age, those with 
Downloaded from https://academic.oup.com/pcm/article/8/1/pbaf003/8005968 by guest on 07 March 2025

# Page 3

Time-series prediction of sepsis outcomes | 3 
F igure 1. Flo wchart of data inclusion and exclusion criteria for ICU sepsis patients in the eICU database. 
unknown gender, cases where the diagnosis was deemed invalid 
at disc har ge , patients with ICU sta ys of < 24 h, and records with 
> 30% missing data. 
In this study, mortality was defined as in-hospital mortality, 
referring to deaths that occurred during the hospital stay as 
documented in the disc har ge disposition. The participants’ 
screening w orkflo w is detailed in Fig. 1 . 
Data collection 
Drawing upon clinical expertise, published liter atur e, and data 
available in the eICU database, we gathered the following cate- 
gories of data: (i) demogr a phic information encompassing gender, 
age, and ethnicity; (ii) vital signs recorded post-ICU admission, in- 
cluding heart rate, mean arterial pressure, respiratory rate, and 
oxygen saturation; and (iii) laboratory test results obtained after 
ICU admission, suc h as cr eatinine and hemoglobin le v els, among 
others. In total, there are 226 distinct vital sign data features (see 
supplementary Table 1 in the online supplementary material for 
further details). 
Data preprocessing 
Using Python data pr epr ocessing libr aries suc h as NumPy and 
pandas [ 12 ,13 ], the data are organized chronologically based on 
the ICU admission timeline, utilizing the ‘offset’ field in each eICU 
Downloaded from https://academic.oup.com/pcm/article/8/1/pbaf003/8005968 by guest on 07 March 2025

# Page 4

4 | Yang et al 
data table. With 24 hourly sampling points per day, a total of 226 
featur es ar e consider ed, and for eac h hourl y sampling point, the 
near est av ailable data v alue is selected. This r esults in a time- 
series matrix of size 24 × 226. To prioritize earl y-sta ge risk pr edic- 
tion, the model focuses on the first 5 days of ICU admission, as 
sepsis-related mortality is most pronounced within this period. 
This design is informed by clinical observations that the major- 
ity of sepsis-related mortalities occur early in the ICU stay, mak- 
ing early identification of high-risk patients crucial for improving 
outcomes. For patients with stays > 5 days, a sliding time-window 
a ppr oac h ensur es that the model r emains d ynamic, contin uously 
updated with patient data throughout the ICU sta y. T he data is 
r andoml y divided into tr aining, v alidation, and testing sets in a 
7 : 2 : 1 ratio to ensure robust model performance. 
Missing data and filling 
In time-series analysis, missing data is a common challenge. 
Given the presence of missing data in our study and the limita- 
tions of traditional imputation methods, we employed two dis- 
tinct imputation a ppr oac hes tailor ed to the natur e of the data. For 
the tempor al data, particularl y the dail y risk indicators of sepsis 
patients in the ICU, we utilized forward imputation. This method 
is well-suited for time-series data, as it assumes that the miss- 
ing v alues ar e likel y to be similar to the preceding values, pre- 
serving the temporal continuity of the data. For other basic fea- 
tures that are not time-dependent, we opted for random forest 
imputation. This method is particularl y effectiv e for m ultiv ariate 
datasets, as it ca ptur es complex, non-linear r elationships among 
features to predict missing values. By leveraging interactions be- 
tween v ariables, r andom for est imputation pr ovides accur ate esti- 
mates, making it ideal for filling in missing data in non-sequential 
features. 
These imputation strategies were chosen to address the spe- 
cific needs of our time-series analysis and ensure that missing 
data would not bias our model. The combination of forw ar d im- 
putation for temporal features and random forest imputation for 
other attributes helped to impr ov e the ov er all performance of the 
pr edictiv e model. 
Anal ysis pla tform 
We utilized the deep learning fr ame w ork PyTor ch ( https://p ytor ch. 
org/) to construct our prediction model. PyTorch offers a com- 
pr ehensiv e r ange of functionalities and empo w ers users with 
complete control over their Python programs [ 14 ]. Our predic- 
tion model is built on a Windows computer with the following 
specifications: Windows 11 operating system, 12th Gen Intel (R) 
Core (TM) i7-12700F central processing unit, 32 GB random access 
memory, and NVDIA GeFor ce R TX3060Ti gr a phics pr ocessing unit. 
Model architecture 
The proposed model is a two-stage Transformer-based architec- 
ture designed to capture both hourly and daily temporal patterns 
in patient time-series data. The input data consists of 226 vital 
sign features recorded every hour across a maximum of 5 da ys , 
with variable time lengths depending on the patient’s ICU stay. In 
the first stage, the model processes the hourly time-series data for 
each day using an hour-le v el Tr ansformer encoder. For eac h day, 
the input data, which has a shape of ’batch size , da ys , features , 
hours’ is r esha ped into hourl y sequences of dimension ’batch 
size × da ys , hours , features’. T he Transformer encoder, com- 
prising multiple self-attention la yers , is applied to these hourly 
sequences to ca ptur e dependencies acr oss hours within a day. 
The output of the hour-le v el Tr ansformer r epr esents the encoded 
hourl y featur es for eac h da y. T hese encoded featur es ar e then a g- 
gr egated using av er a ge pooling acr oss hours to pr oduce a dail y 
r epr esentation. 
The second stage of the model processes the daily representa- 
tions generated by the hour-level Transformer using a day-level 
Tr ansformer encoder, whic h is designed to model temporal de- 
pendencies across up to 5 da ys . Regardless of the actual number 
of ICU days per patient, the input for this module is standard- 
ized to 5 da ys . For patients with < 5 days of data, masking is ap- 
plied to the missing da ys . T his ensures that the model can handle 
patients with different ICU stay durations while maintaining tem- 
poral consistency across the entire cohort. 
The use of masking in this context is essential. Missing data for 
these patients may r esult fr om se v er al possible scenarios: data 
may be absent due to technical issues, incomplete records, or 
other factors; the patient may have passed away before reaching 
the fifth day in the ICU; the patient may have been discharged 
early following recovery; or the patient ma y ha ve been transferred 
to another hospital or department. In all such cases, masking 
ensures that these missing days do not introduce bias or distort 
the analysis. By masking, the model avoids making assumptions 
about the reason for the missing data—whether it is due to data 
absence or patient mortality—ther eby pr eserving the integrity of 
the model and avoiding skewed results. Masking also maintains 
the tempor al structur e of the data, as all patients ar e pr ocessed 
within the same standardized 5-day windo w, regar dless of their 
actual ICU sta y. T his allows the model to effectiv el y ca ptur e 
both intra-day and inter-day dependencies without discarding 
valuable information from patients with shorter sta ys . Moreo ver, 
by masking the missing data, the model avoids learning from 
potentially misleading information, especially when the absence 
of data could be correlated with critical patient outcomes such 
as mortality. 
The final output from the day-le v el Tr ansformer, corr espond- 
ing to the 5th day, is used as the patient’s ov er all time-series 
r epr esentation. This r epr esentation is then passed through a 
fully connected layer to produce the final prediction, which is 
a continuous value representing the predicted outcome. By fix- 
ing the day-le v el Tr ansformer to 5 da ys , the model remains flex- 
ible enough to handle patients with varying ICU stay durations 
while ensuring temporal consistency across different patient 
trajectories. 
This two-sta ge Tr ansformer arc hitectur e, whic h effectiv el y ca p- 
tures both intra-day and inter-day temporal patterns over a max- 
imum of 5 da ys , is well-suited for modeling the complex trajecto- 
ries of patients in critical care settings . T he o verall framework is 
illustrated in Fig. 2 . (Please refer to the following link for the rele- 
vant code: https:// github.com/ yanghaoljx/ Sepsis- ICU- timeseries ) 
Based on the classification results of the model, we performed 
a visual analysis using SHAP [ 15 ] and obtained the corresponding 
heatmap of feature weights. Considering the problem of imbal- 
anced positive and negative samples in the study, the focal loss 
[ 16 ] is introduced as the loss function for the model. 
Results 
Baseline 
A total of 13 610 patients were selected from the eICU database 
for inclusion in the study. Of these, 2 114 patients died dur- 
ing their ICU stay, while 11 496 patients survived. Data extrac- 
tion was performed using the PostgreSQL database system [ 17 ]. 
Downloaded from https://academic.oup.com/pcm/article/8/1/pbaf003/8005968 by guest on 07 March 2025

# Page 5

Time-series prediction of sepsis outcomes | 5 
F igure 2. F r ame work of the two-stage Transformer model for ICU patient time-series analysis: hourly and daily temporal pattern encoding with 
prediction. 
Statistical analysis was carried out using SPSS 22.0 [ 18 ], while data 
cleaning, model construction, and performance e v aluation wer e 
performed using Python. Continuous v ariables ar e pr esented as 
the median (interquartile range) and categorical data are shown 
as counts (percentages). The Mann–Whitney U test [ 19 ] was used 
to analyze continuous variables and the c hi-squar e test [ 20 ] was 
applied to assess significant differences in categorical variables. 
The results are presented in Table 1 . 
Model performance 
Based on the temporal features observed for patients each day, 
a two-sta ge Tr ansformer netw ork model w as de v eloped to en- 
hance prediction accuracy for sepsis outcomes . T his model inte- 
gr ates dail y time-series data, effectiv el y ca pturing tempor al de- 
pendencies and improving ov er all pr edictiv e performance. It is 
observed that the model performs optimally in predicting out- 
comes for the fifth day. For each day’s prediction, the model uti- 
lizes continuous data from the preceding days to estimate the 
risk of in-hospital mortality. For example, the Day 3 model uses 
a masked matrix, a ppl ying masking to the subsequent day’s data, 
and relies on data from Day 1 and Day 2 to predict the risk of 
in-hospital mortality. The model then dir ectl y outputs the pre- 
dicted mortality risk for the patient. A comparison, presented in 
Table 2 and Fig. 3 , illustrates the daily prediction results, along- 
side those obtained using the traditional APACHE II-based predic- 
tion method. Additionall y, clear er dail y activ ation heatma ps ar e 
provided in supplementary Figs. 1 –5 , see online supplementary 
material. T he results , derived from the testing data, include 211 
samples from the expired group and 1 150 samples from the alive 
group. 
A comparison with existing models, such as decision tree [ 21 ], 
XGBoost, and Long Short-Term Memory (LSTM) [ 22 ], r e v eals that 
the two-sta ge Tr ansformer network significantl y outperforms in 
predicting sepsis prognosis. To facilitate the input for traditional 
mac hine learning models, dail y featur e v alues ar e av er a ged ov er 
the 24-h period, resulting in a consistent 226-dimensional feature 
vector per da y. T his approach ensures uniform input dimensions 
across all data points while also reducing computational com- 
plexity. The mean and variance of the model’s performance across 
differ ent days wer e calculated (a bar chart comparing the results 
of different models is presented in supplementary Fig. 6 , see on- 
line supplementary material), with the specific results presented 
in Table 3 . 
Utilizing the prediction model, weight analysis is conducted us- 
ing the SHAP algorithm, whic h gener ates visual heatmaps. Due 
to limitations in formatting, the paper presents only the heatmap 
r epr esenting the most pr ominentl y activ ated featur e for eac h day, 
as depicted in Fig. 4 ). 
External v alida tion 
To assess the generalizability of the model, we utilized ICU sep- 
sis patient data from a large tertiary hospital collected over the 
past 3 years (2021–2023). Inclusion criteria r equir ed patients to 
ha ve an ICU sta y of ≥5 days and disc har ge outcomes (surviv al or 
mortality) wer e car efull y v erified. A total of 417 patients were in- 
cluded, with 350 classified as alive and 67 as expired. The model 
ac hie v ed an ov er all accur acy of ∼81.8%, with an AUC value of 
0.73. To account for potential performance variations due to eth- 
nic differences, we further validated the model using the MIMIC- 
i v-3.1database [ 23 ]. Se psis patient data wer e extr acted based on 
ICD-9 codes (‘99591’, ‘99592’, ‘78552’) [ 24 ], and outcomes were de- 
termined using the ‘date of death (dod)’ column in the patient’s 
table. To ensure the scientific rigor of the validation and the sta- 
bility of the model’s performance, we performed feature selection 
and randomized grouping of the data. Compared to the domestic 
dataset, the MIMIC dataset exhibited a more balanced ratio of pos- 
iti ve and negati ve samples, with 877 classified as alive and 1 192 
as expired. The model achieved an overall accuracy of 76.56% on 
this dataset, with an AUC value of 0.84, demonstr ating str ong pr e- 
dictive performance . T he results indicate that while the accuracy 
was slightly higher on the domestic dataset, the AUC value for 
the MIMIC dataset was superior, likely due to the larger sample 
size and the balanced distribution of outcomes . T his validation 
highlights the model’s adaptability across diverse populations and 
data sources , pro viding a solid foundation for futur e clinical a p- 
plications across regions and ethnic groups. Specific results are 
presented in supplementary Figs. 7 and 8 , see online supplemen- 
tary material. 
Clinical application 
In our r esearc h, we ar e inv estigating the integr ation of r eal-time 
patient data from hospital information systems to enhance the 
assistance provided to clinical sepsis patients. Our system inte- 
gr ation fr ame w ork inv olves collecting essential patient informa- 
tion, laboratory test results, and vital signs from the point of ad- 
mission and consolidating this data in a centralized data center. 
Downloaded from https://academic.oup.com/pcm/article/8/1/pbaf003/8005968 by guest on 07 March 2025

# Page 6

6 | Yang et al 
Table 1. Baseline c har acteristics and statistical comparisons of ICU sepsis patients; continuous variables are expressed as mean (stan- 
dard deviation) and categorical variables are expressed as counts (percentages). 
Characteristic 
Ali v e 
Expired 
P- valu e 
ICU stay [mean (SD)] 
4.171 (5.340) 
5.518 (7.933) 
< 0.001 a 
Apache II [mean (SD)] 
66.020 (23.845) 
88.479 (30.147) 
< 0.001 a 
Gender (%) 
Female 
5693 (49.52) 
1004 (47.49) 
0.1889 b 
Male 
5801 (50.46) 
1110 (52.51) 
Unknown 
2 (0.02) 
0 (0.00) 
Age, years [mean (SD)] 
65.252 (16.309) 
69.807 (13.987) 
< 0.001 a 
Ethnicity (%) 
African–American 
1136 (9.88) 
222 (10.50) 
0.4997 b 
Asian 
175 (1.52) 
43 (2.03) 
Caucasian 
9080 (78.98) 
1641 (77.63) 
Hispanic 
425 (3.70) 
88 (4.16) 
Native American 
94 (0.82) 
17 (0.80) 
Other/unknown 
586 (5.10) 
103 (4.87) 
Height [mean (SD), cm] 
168.341 (14.618) 
168.067 (14.465) 
0.428 a 
Unit type (%) 
Cardiac ICU 
741 (6.45) 
155 (7.33) 
0.0143 b 
CCU-CTICU 
697 (6.06) 
121 (5.72) 
CSICU 
132 (1.15) 
33 (1.56) 
CTICU 
85 (0.74) 
18 (0.85) 
Med-Surg ICU 
7669 (66.71) 
1345 (63.62) 
MICU 
1510 (13.14) 
331 (15.66) 
Neuro ICU 
222 (1.93) 
41 (1.94) 
SICU 
440 (3.83) 
70 (3.31) 
Weight [mean (SD), kg] 
83.271 (27.945) 
79.428 (27.426) 
< 0.001 a 
CCU-CTICU (Cor onary Car e Unit-Cardiothor acic ICU) CSICU (Cardiothor acic Sur gical ICU) CTICU (Cardiothor acic ICU) Med-Sur g ICU (Medical-Sur gical ICU) MICU 
(Medical ICU) SICU (Surgical ICU) 
a Continuous variables were compared using the Mann–Whitney U test. 
b Categorical variables were compared using the chi-square test. 
Ta ble 2. P erformance comparison [mean (SD)] of the two-stage Transformer model and APACHE II in predicting in-hospital mortality 
across ICU da ys . 
Model 
Day 1 
Day 2 
Day 3 
Day 4 
Day 5 
APACHE II 
AUC 
0.87 (0.021) 
0.88 (0.022) 
0.89 (0.019) 
0.92 (0.011) 
0.92 (0.009) 
0.68 (0.030) 
Accuracy (%) 
77.82 (1.63) 
78.93 (1.53) 
80.98 (0.89) 
82.03 (0.71) 
83.92 (0.69) 
63.74 (1.78) 
F1-score a 
0.704 (0.058) 
0.711 (0.061) 
0.732 (0.044) 
0.773 (0.048) 
0.804 (0.024) 
0.667 (0.045) 
a F1-score, harmonic mean of precision and recall. 
Table 3. Compar ativ e performance metrics [mean (SD)] of pr edictiv e models for sepsis prognosis: decision tree, XGBoost, Multilayer 
P er ceptron (MLP), LSTM, and two-sta ge Tr ansformer. 
Metric 
Decision tree 
XGBoost 
MLP 
LSTM 
Two-stage 
Transformer 
P -value 
AUC 
0.733 (0.035) 
0.727 (0.045) 
0.905 (0.015) 
0.876 (0.025) 
0.92 (0.009) 
< 0.001 
Accuracy (%) 
72.35 (1.68) 
66.46 (2.66) 
81.35 (0.89) 
78.03 (1.23) 
83.92 (0.69) 
< 0.001 
F1-score a 
0.750 (0.045) 
0.645 (0.063) 
0.801 (0.035) 
0.790 (0.039) 
0.804 (0.024) 
< 0.001 
a F1-score, harmonic mean of precision and recall. 
Given that patients generate time-series data every minute, con- 
tin uous se psis risk assessment is impr actical. Ther efor e, we pr o- 
cess this data through an application programming interface to 
utilize deep learning models, which generate daily risk predictions 
until the patient is disc har ged. To impr ov e the model’s adaptabil- 
ity, we plan to incor por ate online learning techniques, allowing 
the model to adjust in real-time based on clinical feedback. These 
pr edictions ar e then r elayed bac k to the patient monitoring sys- 
tem (shown in supplementary Fig. 9 , see online supplementary 
material). Ultimately, the decision to intervene clinically is made 
by the doctor, thus completing the closed-loop pr ocess. Curr entl y, 
we have only completed the framework design, and further de- 
velopment is needed for data and system integration to facilitate 
clinical application. 
Discussion 
Se psis re presents a critical and life-threatening condition that re- 
quir es car eful identification of patients at high risk in order to op- 
timize treatment and prognostic predictions. In this study, we pro- 
pose a two-sta ge Tr ansformer model, whic h demonstr ates signif- 
icant adv anta ges in pr edicting sepsis outcomes for ICU patients. 
As the length of ICU stay increases, the model’s pr edictiv e perfor- 
mance gr aduall y impr ov es. Notabl y, the AUC r eac hes 0.92 ( ±0.009) 
on Day 5, significantly higher than the AUC of 0.87 ( ±0.021) on Day 
1. This trend indicates that the model better ca ptur es the time- 
dependent nature of patients’ condition c hanges ov er time, and 
as more clinical data accumulates, the reliability of its predictions 
incr eases. Fr om an arc hitectur al perspectiv e, the Tr ansformer 
Downloaded from https://academic.oup.com/pcm/article/8/1/pbaf003/8005968 by guest on 07 March 2025

# Page 7

Time-series prediction of sepsis outcomes | 7 
Figure 3. Receiv er oper ation c har acteristic (ROC) curv es, confusion matrix, and statistical comparison ( P < 0.001) demonstrating the superior 
pr edictiv e performance of the two-stage Transformer model over APACHE II across ICU da ys . Statistical comparison was performed using the 
Mann–Whitney U Test. 
network incor por ates both hourl y and dail y time-series patterns. 
This allows it to effectiv el y ca ptur e dependencies acr oss both 
hours and da ys , whic h is crucial giv en the fr equent fluctuations 
in ICU patients’ vital signs . T he two-stage Transformer not only 
tr ac ks within-day trends in vital signs but also models cross-day 
time-series data, identifying signs of deterioration that emerge 
gr aduall y during the hospital stay. 
In comparison with traditional models such as the APACHE 
II scoring system and other models (Tables 2 and 3 ), our model 
consistently outperforms across various metrics. For instance, on 
Day 5, the AUC r eac hed 0.92 ( ±0.009), significantl y sur passing tr a- 
ditional machine learning models like XGBoost (AUC of 0.7277) 
and decision trees (AUC of 0.7329). Similarly, in terms of accu- 
racy and F1 score, the Transformer model exhibited more sta- 
ble and superior performance. P articularl y, the F1 scor e on day 
5 was 0.804 ( ±0.024), outperforming deep learning models such 
as MLP (0.801) and LSTM (0.790). These results suggest that the 
Tr ansformer arc hitectur e not onl y excels in accur atel y pr edict- 
ing sepsis outcomes but also has a strong ability to adapt to the 
dynamic changes in patient conditions, making it well-suited for 
Downloaded from https://academic.oup.com/pcm/article/8/1/pbaf003/8005968 by guest on 07 March 2025

# Page 8

8 | Yang et al 
Figure 4. Dail y featur e visualization heatma ps showing featur e activ ation in the two-sta ge Tr ansformer model. The v ertical axis r epr esents the 24 h of 
the day, with the color intensity indicating the le v el of activ ation, wher e r edder colors corr espond to higher activ ation le v els . (Da y 5: k e y acti vated 
features include RBC , WBC , glucose , bicarbonate , chloride , and creatinine , whic h ar e crucial for assessing ov er all blood and metabolic status; Day 4: 
PTT, peak insp. pr essur e, TV/kg IBW, total RR, creatine, chloride, calcium, and bicarbonate, indicating vital r espir atory and metabolic indicators; Day 3: 
PT-INR, PTT, peak insp. pr essur e, plateau pr essur e, total RR, TV/kg IBW, v ent r ate , and bicarbonate , highlighting coagulation, ventilation, and acid–base 
balance; Day 2: RDW, albumin, alkaline, glucose, and calcium, r eflecting r ed blood cell c har acteristics and nutritional status; Da y 1: lactate , tidal 
volume , chloride , and glucose , important for early sepsis detection and metabolic evaluation). RBC, Red blood cells; WBC, white blood cells; glucose, 
blood sugar le v el; PTT, partial thromboplastin time; peak insp. pr essur e, peak inspir atory pr essur e; TV/kg IBW, tidal volume per kilogr am ideal body 
weight; total RR, total r espir atory r ate; PT-INR, pr othr ombin time—international normalized r atio; RDW, r ed cell distribution width. 
r eal ICU envir onments. Furthermor e, b y emplo ying the SHAP vi- 
sualization algorithm, we noted a rising presence of life features 
str ongl y linked to mortality as the time sequence advances . T his 
is distinctly evident from their elevated levels of activation. Com- 
paring these obtained activation features with relevant literature, 
we found that these patterns align with known clinical markers 
of sepsis pr ogr ession, demonstr ating their potential clinical and 
r esearc h v alue. 
The vital signs and diagnostic indicators recorded during the 
patient’s initial day of admission must not be overlooked as they 
play a pivotal role in e v aluating the se v erity of the patient’s con- 
dition. According to our model, on the first day after ICU admis- 
sion, lactate le v els wer e the most str ongl y associated featur e with 
patient mortality, follo w ed b y tidal v olume , chloride , bedside glu- 
cose, and ideal body weight (IBW). In most cases, ele v ated lactate 
le v els wer e corr elated with poor pr ognosis, particularl y in sep- 
sis, trauma, bleeding, shock, and cardiac arrest [ 25–27 ]. Lactate 
le v el possesses div erse dia gnostic a pplications and has been ex- 
tensiv el y utilized as an indicator for resuscitation, the stratifica- 
tion of risk, and the prediction of mortality in cases of sepsis [ 28 ]. 
In a pr ospectiv e cohort study of patients with infections in the 
emer gency department, ele v ated lactate le v els wer e associated 
with increased mortality, and an initial lactate le v el ≥4 mmol/l 
was found to be linked to a 28% in-hospital mortality rate [ 29 ]. ICU 
patients who r equir e mec hanical v entilation face a high incidence 
and mortality rate [ 30 , 31 ]. Acute respiratory distress syndrome 
(ARDS) contributes to the ele v ated admission and mortality r ates 
in the ICU, and lung-pr otectiv e v entilation, including lo w tidal v ol- 
ume ventilation, has demonstrated benefits for both ARDS and 
non-ARDS patients [ 32 , 33 ]. According to our model, in addition to 
lactate concentr ation, electr ol yte disturbances ar e also common 
in the ICU. Serum chloride, the second most abundant electr ol yte 
in the human body, plays a critical role in the pathophysiology 
of acute heart failure and is considered a ther a peutic tar get for 
reducing mortality [ 34–36 ]. Among ICU patients with heart fail- 
ur e, v arious electr ol yte abnormalities wer e commonl y observ ed, 
with hyponatremia and hypoc hlor emia being the most pr e v alent 
[ 37 ]. Pr e vious studies have investigated the detrimental effects of 
hyper gl ycemia on the prognosis of critically ill patients, such as 
those with se psis, m y ocar dial infar ction, acute pancreatitis, and 
stroke [ 38 ]. Our model enables us not only to observe the indica- 
tors connected with human organ failure, but also systemic indi- 
cators like glucose le v els. In our r esearc h, serum blood glucose 
concentration during ICU stay was associated with ov er all ICU 
mortality in sepsis patients. Patients with severe hyperglycemia 
( ≥200 mg/dl) upon ICU admission exhibit the highest ov er all ICU 
mortality, regardless of whether they have diabetes, highlighting 
sustained hyper gl ycemia as a significant risk factor for ICU mor- 
tality in sepsis patients [ 39 ]. 
As the disease advances and in response to the subsequent ad- 
ministr ation of r ele v ant medications, sur gical interv entions, and 
other treatment modalities, the patient’s indicators will undergo 
alterations. With the model, on the second day the le v els of red 
cell distribution width (RDW), albumin, alkaline phosphatase, and 
calcium start to increase. Following respiratory support and basic 
care, most patients show signs of recovery. Ho w ever, patients with 
Downloaded from https://academic.oup.com/pcm/article/8/1/pbaf003/8005968 by guest on 07 March 2025

# Page 9

Time-series prediction of sepsis outcomes | 9 
or gan failur e begin to exhibit disruptions in r ele v ant or gan func- 
tion indicators. RDW is a parameter traditionally used for the dif- 
fer ential dia gnosis of anemia, and its incr ease r eflects disruptions 
in red blood cell production and unregulated red cell homeostasis. 
Tutak and Avni Findiki conducted a study indicating that ele v ated 
RDW le v els serv e as a reliable marker for predicting mortality and 
should be included in the APACHE II score to forecast patient out- 
comes [ 40 ]. RDW values above the upper limit of 14.5% are associ- 
ated with abnormal metabolic conditions such as inflammation, 
o xidati v e str ess, and nutritional imbalances [ 41 ]. Özdemir et al . 
demonstrated an association between high RDW levels and mor- 
tality in ICU patients with mixed conditions [ 42 ]. Similarly, Safdar 
et al . reported a correlation between high RDW levels and 30-day 
mortality rates in follow-up patients from ICU medical and sur- 
gical departments [ 43 ]. Salmoran et al. also found a correlation 
between ele v ated RDW le v els and mortality in ICU patients [ 44 ]. 
From this, the RDW in routine blood tests plays a significant role 
in predicting the mortality rate and prognosis of ICU sepsis pa- 
tients and should not be ov erlooked. Mor eov er, our model sho w ed 
another indicator associated with sepsis se v erity, i.e. albumin, a 
m ultifunctional pr otein with colloidal and pharmacological prop- 
erties that exhibits physiological functions intricately linked to its 
distribution (intr av ascular, extr av ascular, and intr acellular loca- 
tions), concentr ation, and complex structur e [ 45 ]. Yin et al . con- 
ducted a pr ospectiv e cohort study and found that serum albumin 
le v els < 2.92 g/dl upon admission are associated with an increased 
28-day mortality rate in patients with se v er e sepsis [ 46 ]. Researc h 
suggested that serum albumin trends can predict mortality rates 
in ICU sepsis patients. Significant correlations exist between mor- 
tality rates and serum albumin trends, as well as av er a ge, peak, 
admission, and minimum levels of albumin [ 47 ]. In critically ill el- 
derly patients, serum albumin levels upon ICU admission serve as 
effectiv e pr edictiv e indicators for mortality and other outcomes. 
Low serum albumin le v els upon admission were independent risk 
factors for 6-month mortality in critically ill elderly patients af- 
ter ICU disc har ge [ 48 ]. Sepsis is associated with or gan dama ge. 
Acute kidney injury (AKI) is one of the most common organ fail- 
ures. Total alkaline phosphatase activity slightly increases in ICU 
patients with septic AKI, and its activity positiv el y corr elates with 
ICU length of stay [ 49 ]. In a pr edictiv e experiment for earl y liv er 
failure in pediatric ICU patients, elevated alkaline phosphatase on 
the first day of admission was identified as a k e y laboratory pa- 
r ameter for dia gnosing liv er dysfunction. Alkaline phosphatase is 
widely used to predict liver function prognosis in ICU patients [ 50 ]. 
The parameters most strongly associated with ICU mortality 
were identified, with one-third of sepsis-related deaths occurring 
within 3 days of ICU admission [ 51 ]. In the models on the third 
and fourth da ys , coa gulation par ameters suc h as pr othr ombin 
time (PT) and activated partial thromboplastin time (APTT) re- 
flect their value in predicting the length of hospital stay for sep- 
tic patients. PT and APTT can serve as early prognostic markers 
for se v er e pneumonia r equiring tr ansfer to the ICU. Bar anovskii et 
al. compared these coagulation parameters and various coagula- 
tion and inflammation factor le v els between patients with early 
tr eatment-r esistant r espir atory failur e or se v er e acute r espir atory 
distr ess syndr ome r equiring ICU tr eatment and stable COVID-19 
patients . T hey disco v er ed that earl y measur ement of PT v alues 
can predict the course of COVID-19-related pneumonia. Prolonged 
PT in patients tr ansferr ed to the ICU and PT le v els upon admis- 
sion for COVID-19 patients can serve as early prognostic mark- 
ers for se v er e pneumonia r equiring ICU car e [ 52 , 53 ]. APTT, the 
most used and sensitive screening method for assessing clotting 
activity, has been shown in multiple studies to be a risk factor for 
thrombosis and pulmonary embolism. It is a significant predictor 
for pulmonary embolism in ICU patients [ 54–57 ]. Monitoring APTT 
in ICU patients should be emphasized to pr e v ent pulmonary em- 
bolism. For patients admitted to the ICU due to r espir atory condi- 
tions, particularly COVID-19, respiratory-related parameters ex- 
hibit a strong association with ICU mortality. Plateau pressure, 
whic h r epr esents airway pr essur e within the alv eoli during pos- 
itiv e pr essur e v entilation when the br eath is held, has been ana- 
lyzed for its impact on the prognosis of patients with ARDS. There 
is a correlation between plateau pr essur e and short-term mor- 
tality, with significantly higher overall short-term mortality rates 
observed in patients with plateau pr essur e > 32 cm H 2 O within 
3 days of ICU admission. This correlation becomes evident in the 
following days and may persist for the first 3 days after ICU admis- 
sion [ 58 ]. The r espir atory index, the ratio of peripheral oxygen sat- 
uration (SpO 2 ) to respiratory rate (RR), has been validated for prog- 
nostic stratification in patients with acute pulmonary embolism 
[ 59 ]. Ho w e v er, in patients admitted to the ICU due to COVID-19, 
RR may be an important parameter that has r eceiv ed insufficient 
reporting and attention. Marziti and Becattini found that RR is 
a better predictor of mortality compared to blood gas parame- 
ters P aO 2 /FiO 2 r atio (P/F) and SpO 2 /FiO 2 r atio (STP/F)in e v aluat- 
ing patients with COVID-19-related pneumonia admitted to the 
ICU [ 60 ]. 
In the model on the fifth day, compared to the pr e vious four 
da ys , red blood cell, white blood cell, and cr eatinine le v els be- 
gan to rise. Cells of the innate immune system and ada ptiv e im- 
mune system play a crucial role in the host response to sepsis, 
which is associated with profound inhibition of constitutive neu- 
tr ophil a poptosis [ 61 ]. During the onset of sepsis, neutr ophils r e- 
spond r a pidl y to infection, their numbers incr ease shar pl y, and 
they quic kl y migr ate to sites of se v er e infection [ 62 ]. While neu- 
tr ophil counts ar e indicativ e of the ov er all inflammation se v er- 
ity, in intricate sepsis scenarios, the delay in neutrophil apoptosis 
could result in a persistent ele v ation of neutr ophil counts [ 61 ]. 
Hence, the significance of leukocytes as an indicator should not 
be diminished in the presence of sepsis; rather, it should continue 
to be closely monitored. The incidence of AKI in sepsis patients in 
the ICU can r eac h up to 60%, and the occurrence of AKI is associ- 
ated with increased mortality, with survivors being at risk of de- 
v eloping c hr onic kidney disease [ 63 , 64 ]. Serum cr eatinine slowl y 
increases after the onset of AKI, and its rise can be further de- 
layed due to large fluid resuscitation and fluid balance [ 65 ]. On 
the third day following sepsis-induced AKI, serum creatinine may 
onl y incr ease to the borderline v alue. If the glomerular filtr ation 
r ate r emains stable, the expansion of distribution volume is ex- 
pected to lead to a decrease in serum creatinine levels, resulting 
in a delay in the number of days before serum creatinine concen- 
tration rises [ 66 ]. T herefore , continuous monitoring of creatinine 
le v els in sepsis patients in the ICU allows for better assessment of 
renal injury. 
We chose Day 5 as the k e y time point for prediction because the 
highest mortality risk in sepsis patients typically occurs within 
around the fifth day of ICU admission [ 67 , 68 ]. Studies have consis- 
tently shown that early identification of high-risk patients during 
this window significantly enhances the chances of better clinical 
outcomes [ 69 , 70 ]. For patients staying beyond 5 days in the ICU, 
the model can still be applied by utilizing a sliding time-window 
a ppr oac h. This method allows the model to use the most recent 
data within a defined windo w, thereb y maintaining pr edictiv e per- 
formance. 
Although this study demonstrates the significant adv anta ges 
of Transformer-based models in predicting the prognosis of 
Downloaded from https://academic.oup.com/pcm/article/8/1/pbaf003/8005968 by guest on 07 March 2025

# Page 10

10 | Yang et al 
sepsis patients in the ICU, it also has some limitations. A primary 
challenge is the sparsity of the data, which stems from the in- 
her ent c har acteristics of time-series data. Variability in patient 
tr eatment r egimens and the fr equency of dia gnostic tests during 
the ICU stay contribute to this issue. As discrepancies in treat- 
ment protocols and testing schedules accumulate over time, data 
gaps become increasingly evident. To address this, we employed 
a sliding-window a ppr oac h combined with filling missing values 
using the most recent available data points, aiming to generate 
more complete time-series matrices . T his strategy helps mitigate 
data gaps while minimizing potential distortion. Ho w ever, it may 
still introduce some degree of data distortion, particularly when 
ther e ar e substantial differ ences in tr eatment pr otocols or testing 
fr equencies. Additionall y, the data used in this study was derived 
from a single center, which may limit the generalizability of the 
model, particularl y in differ ent r egions , populations , or disease 
conditions . T her efor e, the model’s performance may vary across 
hospitals and diverse patient demographics, including differences 
in r ace, a ge, and gender. While the model has shown high predic- 
tiv e accur acy, its performance r emains constr ained by the qual- 
ity and completeness of the input data, particularly its sensitivity 
to missing data and noise. We are currently collecting real-world 
data to validate and further optimize the model, with the aim of 
impr oving its gener alizability and r obustness acr oss div erse clin- 
ical settings. Ho w e v er, this pr ocess will take time and may still 
encounter challenges related to data integration and quality con- 
trol. 
Conclusion 
The results of this study highlight the effectiveness of time-series 
algorithms, specificall y the Tr ansformer-based a ppr oac h, in pr e- 
dicting patient outcomes in the ICU. The utilization of these algo- 
rithms enables the ca ptur e of temporal patterns and the integra- 
tion of compr ehensiv e patient featur es, leading to impr ov ed accu- 
r acy and r eliability in pr edictions. Furthermor e, the identification 
and activation of life features associated with mortality provide 
valuable insights into the underlying mechanisms of sepsis and 
its pr ogr ession. 
In futur e r esearc h, it would be beneficial to explor e the clinical 
implications of these identified activation features and examine 
their potential role in guiding early interventions and personal- 
ized treatment plans for sepsis patients. Additionall y, adv ancing 
the de v elopment of mor e sophisticated time-series models by in- 
cor por ating additional data sources like MetaSepsisBase [ 71 ] and 
r efining featur e selection tec hniques holds pr omise for further en- 
hancing the pr edictiv e ca pabilities and pr actical a pplications of 
mortality prediction in critical care settings. 
Availability of data and material 
The data used in this study were sourced from the publicly avail- 
able eICU database ( https:// eicu-crd.mit.edu/ about/ eicu/ ). For ac- 
cess to the related code, please contact the corresponding author. 
Ac kno wledgments 
This w ork w as supported b y the National Natural Science Foun- 
dation of China (Grant Nos. 32200545 and 32270690) and the 
1 ·3 ·5 Project for Disciplines of Excellence, West China Hospital, 
Sic huan Univ ersity (Gr ant Nos. ZYGD23012 and ZYAI24044), and 
w as funded b y the EU and the Xunta de Galicia (Spain) through 
grant ED431C2022/46 for Competitive Reference Groups (GRC). It 
was also supported by CITIC-UDC and INIBIC. We are grateful to 
the staff in our r esearc h gr oups involv ed in the study for their 
valuable contributions and discussions. 
Author contributions 
Hao Yang (Data curation, Methodology, Writing—original draft), 
Jiaxi Li (Writing—original dr aft, Writing—r e vie w & editing), Chi 
Zhang (Supervision, Validation, Visualization), Alejandr o P azos 
Sierr a (Conceptualization), and Bair ong Shen (Conceptualization). 
Supplementary data 
Supplementary data is available at PCMEDI online. 
Conflict of interest 
Ther e ar e no conflicts of inter est r elated to this manuscript. In ad- 
dition, as an Editorial Board Member of Precision Clinical Medicine , 
the corresponding author Bairong Shen was blinded from review- 
ing and making decisions on this manuscript. 
Ethics appr o v al 
This study was a ppr ov ed by the Medical Ethics Committee 
of the West China Hospital, Sichuan University (2024-126). All 
pr ocedur es wer e conducted in accordance with r ele v ant ethi- 
cal guidelines. No patient-identifiable data were used in this 
study, and all data were anonymized to ensure privacy and 
confidentiality. 
References 
1.
Singer M, Deutschman CS, Seymour CW et al. The third interna- 
tional consensus definitions for sepsis and septic shock (Sepsis- 
3). JAMA 2016; 315 :801–10. https:// doi.org/ 10.1001/ jama.2016.02 
87 .
2.
Iba T, Levi M, Levy JH. Sepsis-induced Coagulopathy and Dis- 
seminated Intravascular Coagulation. In Seminars in Thrombosis 
and Hemostasis . Stuttgart, Germany Thieme Medical Publishers, 
2020.
3.
Patel R, Arisoyin AE, Okoronkwo OU et al. Trends and factors as- 
sociated with the mortality rate of de pressi ve e pisodes: an anal- 
ysis of the CDC wide-ranging online data for epidemiological re- 
search (WONDER) database. Cureus 2023; 15 (7):e41627.
4.
Jones AE, Trzeciak S, Kline JA. The sequential organ failure 
assessment score for predicting outcome in patients with se- 
v er e sepsis and evidence of hypoperfusion at the time of emer- 
gency department presentation. Crit Care Med 2009; 37 :1649–54. 
https:// doi.org/ 10.1097/ CCM.0b013e31819def97 .
5.
Zeng W, Mao P, Huang Y et al. Analyses of factors affecting prog- 
nosis of patients with sepsis and e v aluation of their predicting 
v alues. Chinese J ournal of Integrated Traditional and Western Medicine 
in Intensive and Critical Care 2015; (6) : 118–23.
6.
Chen T, Guestrin C. Xgboost: A scalable tree boosting system. In 
Proceedings of the 22nd acm sigkdd international conference on Knowl- 
edge Discovery and Data Mining . 2016. ACM (Association for Com- 
puting Mac hinery), Ne w York, NY, USA.
7.
Rhee C, Wang R, Song Y et al. Risk adjustment for sepsis mortal- 
ity to facilitate hospital comparisons using centers for disease 
contr ol and pr e v ention’s adult sepsis e v ent criteria and r outine 
electronic clinical data. Critical Care Explorations 2019; 1 :e0049. 
https:// doi.org/ 10.1097/ CCE.0000000000000049 .
Downloaded from https://academic.oup.com/pcm/article/8/1/pbaf003/8005968 by guest on 07 March 2025

# Page 11

Time-series prediction of sepsis outcomes | 11 
8.
Park JY, Hsu T-C, Hu J-R et al. Predicting sepsis mortality in 
a population-based national database: machine learning ap- 
pr oac h. J ournal of Medical Internet Research 2022; 24 :e29982. https: 
// doi.org/ 10.2196/ 29982 .
9.
Su L, Xu Z, Chang F et al. Early prediction of mortality, sever- 
ity, and length of stay in the intensive care unit of sepsis pa- 
tients based on sepsis 3.0 by machine learning models . F rontiers 
in Medicine 2021; 8 :664966. https:// doi.org/ 10.3389/ fmed.2021.66 
4966 .
10. P ollard TJ, J ohnson AEW, Raffa JD et al. The eICU Collabor ativ e 
Researc h Database, a fr eel y av ailable m ulti-center database for 
critical car e r esearc h. Sci Data 2018; 5 :1–13. https:// doi.org/ 10.1 
038/sdata.2018.178 .
11. Vaswani A. 
Attention is all you need. arXiv preprint 
arXiv:1706.03762, 2017.
12. Harris CR, Millman KJ, Van Der Walt SJ et al. Array programming 
with NumPy. Nature 2020; 585 :357–62. https:// doi.org/ 10.1038/ s4 
1586- 020- 2649- 2 .
13. Reback J, McKinney W. pandas-dev/pandas: Pandas 1.0.5. Zen- 
odo, 2020. https:// doi.org/ 10.5281/ zenodo.3898987 .
14. Ketkar N, Moolayil J. Introduction to p ytor ch. Deep Learning with 
Python: Learn Best Practices of Deep Learning Models with PyTorch , 
2021, pp . 27–91. Apr ess, Ne w York.
15. Lundberg S. A unified approach to interpreting model predic- 
tions. arXi v pre print arXi v:1705.07874, 2017.
16. Lin T. Focal loss for dense object detection. arXiv preprint 
arXiv:1708.02002, 2017.
17. Worsle y J, Drak e JD. Pr actical Postgr eSQL. 2002: “O’Reill y Media, 
Inc. ”. 
18. Pramesti G. Kupas tuntas data penelitian dengan SPSS 22. 2015: 
Elex Media Komputindo.
19. McKnight PE, Najab J. Mann-Whitney U Test. The Corsini Encyclo- 
pedia of Psyc holog y , 2010, pp . 1–1. W ile y, Hobok en.
20. McHugh ML. The c hi-squar e test of independence. Bioc hemia 
medica 2013; 23 :143–9. https:// doi.org/ 10.11613/BM.2013.018 .
21. Song Y-Y, Ying L. Decision tree methods: applications for 
classification and prediction. Shanghai Archives of Psychiatry 
2015; 27 :130.
22. Gr av es A. Long short-term memory. Supervised Sequence Labelling 
with Recurrent Neural Networks , 2012, pp. 37–45. Springer, Berlin.
23. Johnson A, Bulgarelli L. Mimic-iv. PhysioNet. Available on- 
line at: https:// physionet.org/ content/ mimiciv/ 3.1/ (accessed 
A ugust 23, 2021). 
24. Zeng Q, Zhang L, Wu Y et al., Association of number of days with 
se v er e anemia in the first week with 28-day mortality in patients 
with sepsis: propensity score-based analyses. https:// doi.org/ 10 
.21203/rs.3.rs-4553695/v1 .
25. Donnino MW, Miller J, Go y al N et al. Effective lactate clearance 
is associated with impr ov ed outcome in post-cardiac arrest pa- 
tients. Resuscitation 2007; 75 :229–34. https:// doi.org/ 10.1016/ j.re 
suscitation.2007.03.021 .
26. Régnier M-A, Raux M, Manach LE et al. Prognostic significance 
of blood lactate and lactate clearance in trauma patients. The 
Journal of the American Society of Anesthesiologists 2012; 117 :1276–
88.
27. W ardi G, W ali AR, Villar J et al. Unexpected intensiv e car e tr ans- 
fer of admitted patients with se v er e sepsis. J ournal of Intensive 
Care 2017; 5 :1–9. https:// doi.org/ 10.1186/ s40560- 017- 0239- 7 .
28. Wardi G, Brice J, Correia M et al. Demystifying lactate in the 
emergency department. Ann Emerg Med 2020; 75 :287–98. https: 
// doi.org/ 10.1016/ j.annemergmed.2019.06.027 .
29. Sha pir o NI, Ho w ell MD, Talmor D et al. Serum lactate as a pre- 
dictor of mortality in emergency department patients with in- 
fection. Ann Emerg Med 2005; 45 :524–8. https:// doi.org/ 10.1016/ j. 
annemergmed.2004.12.006 .
30. GD R, Herridge MS. Epidemiology and outcomes of acute lung 
injury. Chest 2007; 131 :554–62.
31. Rose L, Gray S, Burns K et al. Emergency department length of 
stay for patients r equiring mec hanical v entilation: a pr ospectiv e 
observ ational study. Scandinavian J ournal of Trauma, Resuscitation 
and Emergency Medicine 2012; 20 :1–7. https:// doi.org/ 10.1186/ 1757 
- 7241- 20- 30 .
32. Pan C, Liu L, Xie J-F et al. Acute r espir atory distr ess syn- 
dr ome: c hallenge for diagnosis and therapy. Chin Med J (Engl) 
2018; 131 :1220–4. https:// doi.org/ 10.4103/ 0366-6999.228765 .
33. Serpa Neto A, Cardoso SO, Manetta JA et al. Association between 
use of lung-pr otectiv e v entilation with lo w er tidal v olumes and 
clinical outcomes among patients without acute r espir atory dis- 
tr ess syndr ome: a meta-anal ysis. JAMA 2012; 308 :1651–9. https: 
// doi.org/ 10.1001/ jama.2012.13730 .
34. Waikar SS, Mount DB, Curhan GC. Mortality after hospitaliza- 
tion with mild, moderate, and severe hyponatremia. Am J Med 
2009; 122 :857–65. https:// doi.org/ 10.1016/ j.amjmed.2009.01.027 .
35. Berend K, Van Hulsteijn LH, Gans RO. Chloride: the queen of 
electr ol ytes? European J ournal of Internal Medicine 2012; 23 :203–11. 
https:// doi.org/ 10.1016/ j.ejim.2011.11.013 .
36. Grodin JL, Simon J, Hachamovitch R et al. Prognostic role of 
serum c hloride le v els in acute decompensated heart failure. J 
Am Coll Cardiol 2015; 66 :659–66. https:// doi.org/ 10.1016/ j.jacc.201 
5.06.007 .
37. Riv er a FB, Alfonso P, Golbin JM et al. The role of serum chloride 
in acute and c hr onic heart failur e: a narr ativ e r e vie w. Cardiorenal 
Medicine 2021; 11 :87–98. https:// doi.org/ 10.1159/ 000515604 .
38. Hou D, Zhong P, Ye X et al. Persistent hyper gl ycemia is a useful 
glycemic pattern to predict stroke mortality: a systematic review 
and meta-anal ysis. BMC Neurolog y 2021; 21 :1–13. https://doi.org/ 
10.1186/s12883- 021- 02512- 1 .
39. Lu Z, Tao G, Sun X et al. Association of blood glucose le v el and 
gl ycemic v ariability with mortality in sepsis patients during ICU 
hospitalization. Frontiers in Public Health 2022; 10 :857368. https: 
// doi.org/ 10.3389/ fpubh.2022.857368 .
40. Tutak AS, Avni Findikli H. Can RDW be added to intensive care 
disease se v erity scoring systems? Arc hives of Clinical and Biomed- 
ical Research 2018; 2 :183–7. https:// doi.org/ 10.26502/acbr.501700 
57 .
41. Fernandez R, Cano S, Catalan I et al. High red blood cell distri- 
bution width as a marker of hospital mortality after ICU dis- 
c har ge: a cohort study. Journal of Intensive Care 2018; 6 :1–7. https: 
// doi.org/ 10.1186/ s40560- 018- 0343- 3 .
42. Özdemir R, Mutlu NM, Özdemir M et al. The importance of red 
cell distribution width (RDW) in patient follow up in intensive 
care unit (ICU). Acta Medica Mediterranea 2016. 66 (2):151–4. 
43. Safdar SA, Modi T, Srir am ulu L et al., The role of red cell dis- 
tribution width as a predictor of mortality for critically ill pa- 
tients in an inner-city hospital. Journal of natural science, biology, 
and medicine 2017; 8 :154.
44. Salmorán HO, Martínez I, Ramírez S et al. Extent of erythrocyte 
distribution as a predictor of mortality on admission to the In- 
tensiv e Car e Unit of the Angeles Pedregal Hospital. Acta Médica 
Grupo Angeles 2019; 17 :230–6.
45. Garcia-Martinez R, Caraceni P, Bernardi M et al. Albumin: patho- 
physiologic basis of its role in the treatment of cirrhosis and its 
complications. Hepatology 2013; 58 :1836–46. https:// doi.org/ 10.1 
002/hep .26338 . 
46. Yin M, Si L, Qin W et al. Pr edictiv e v alue of serum albumin le v el 
for the prognosis of severe sepsis without exogenous human 
Downloaded from https://academic.oup.com/pcm/article/8/1/pbaf003/8005968 by guest on 07 March 2025

# Page 12

12 | Yang et al 
albumin administration: a prospective cohort study. J Intensive 
Care Med 2018; 33 :687–94. https:// doi.org/ 10.1177/ 088506661668 
5300 .
47. Pan SW, Kao H, Yu W et al. Synergistic impact of low serum albu- 
min on intensive care unit admission and high blood urea nitro- 
gen during intensive care unit stay on post-intensive care unit 
mortality in critically ill elderly patients requiring mechanical 
ventilation. Geriatrics & Gerontology International 2013; 13 :107–15.
48. Arques S, Roux E, Stolidi P et al. Usefulness of serum albumin 
and serum total c holester ol in the prediction of hospital death 
in older patients with se v er e, acute heart failur e. Arc h Cardiov asc 
Dis 2011; 104 :502–8. https:// doi.org/ 10.1016/ j.acvd.2011.06.003 .
49. Baek SD, Kang J-Y, Yu H et al. Change in alkaline phosphatase 
activity associated with intensive care unit and hospital length 
of stay in patients with septic acute kidney injury on continuous 
r enal r eplacement ther a py. BMC Nephrolog y 2018; 19 :1–7. https: 
// doi.org/ 10.1186/ s12882- 018- 1028- 9 .
50. Zahmatkeshan M, Serati Z, Freydooni S et al. Prediction of early 
liv er failur e in pediatric patients admitted to intensiv e car e unit. 
Middle East Journal of Digestive Diseases 2019; 11 :141. https://doi.or 
g/10.15171/mejdd.2019.140 .
51. Daviaud F, Grimaldi D, Dec hartr es A et al. Timing and causes of 
death in septic shock. Annals of Intensive Care 2015; 5 :1–9. https: 
// doi.org/ 10.1186/ s13613- 015- 0058- 8 .
52. Bar anovskii DS, Klabuk ov ID, Kr asilnik ov a OA et al. Prolonged 
pr othr ombin time as an earl y pr ognostic indicator of se v er e 
acute r espir atory distr ess syndr ome in patients with COVID- 
19 related pneumonia. Curr Med Res Opin 2021; 37 :21–5. https: 
// doi.org/ 10.1080/ 03007995.2020.1853510 .
53. Tang N, Li D, Wang X et al. Abnormal coa gulation par ameters 
are associated with poor prognosis in patients with novel coro- 
navirus pneumonia. J Thromb Haemost 2020; 18 :844–7. https://do 
i.org/ 10.1111/ jth.14768 .
54. Prucnal CK, Jansson PS, Deadmon E et al. Analysis of partial 
thromboplastin times in patients with pulmonary embolism 
during the first 48 hours of anticoagulation with unfractionated 
heparin. Acad Emerg Med 2020; 27 :117–27. https:// doi.org/ 10.111 
1/acem.13872 .
55. Lippi G, Fav alor o EJ, Fr anc hini M. P ar adoxical thr ombosis part 1: 
factor replacement therapy, inherited clotting factor deficiencies 
and prolonged APTT. J Thromb Thrombolysis 2012; 34 :360–6. https: 
// doi.org/ 10.1007/ s11239- 012- 0753- 3 .
56. Matsubara S, Usui R, Ohkuchi A et al. Prolonged activated partial 
thromboplastin time in thromboprophylaxis with unfraction- 
ated heparin in patients undergoing cesarean section. J Obstet 
Gynaecol Res 2010; 36 :58–63. https:// doi.org/ 10.1111/ j.1447-0756. 
2009.01107.x .
57. Huang C-B, Hong C-X, Xu T-H et al. Risk factors for pul- 
monary embolism in ICU patients: a r etr ospectiv e cohort 
study from the MIMIC-III database. Clin Appl Thromb Hemost 
2022; 28 :10760296211073925. https:// doi.org/ 10.1177/ 10760296 
211073925 .
58. Yasuda H, Sanui M, Nishim ur a T et al. Optimal upper limits of 
Plateau pr essur e for patients with Acute Respir atory Distr ess 
Syndrome during the first se v en days: a meta-r egr ession anal- 
ysis. Journal of Clinical Medicine Research 2021; 13 :48. https://doi.or 
g/10.14740/jocmr4390 .
59. Cr etik os MA, Bellomo R, Hillman K et al. Respiratory rate: the 
neglected vital sign. Med J Aust 2008; 188 :657–9. https://doi.org/ 
10.5694/j.1326-5377.2008.tb01825.x .
60. Mar aziti G, Becattini C. Earl y v ariation of r espir atory indexes 
to predict death or ICU admission in severe acute respiratory 
syndr ome cor onavirus-2-r elated r espir atory failur e. Respiration 
2022; 101 :632–7. https:// doi.org/ 10.1159/ 000522275 .
61. Taneja R, P ar odo J, Jia SH et al. Delayed neutr ophil a poptosis in 
sepsis is associated with maintenance of mitochondrial trans- 
membrane potential and reduced caspase-9 activity. Crit Care 
Med 2004; 32 :1460–9. https:// doi.org/ 10.1097/ 01.CCM.000012997 
5.26905.77 .
62. Huang Z, Fu Z, Huang W et al. Pr ognostic v alue of neutr ophil- 
to-l ymphocyte r atio in sepsis: a meta-anal ysis. Am J Emerg Med 
2020; 38 :641–7. https:// doi.org/ 10.1016/ j.ajem.2019.10.023 .
63. Lameir e NH, Ba gga A, Cruz D et al. Acute kidney injury: an in- 
creasing global concern. The Lancet 2013; 382 :170–9. https://doi. 
org/ 10.1016/ S0140- 6736(13)60647- 9 .
64. Hoste EAJ, Bagshaw SM, Bellomo R et al. Epidemiology of acute 
kidney injury in critically ill patients: the multinational AKI-EPI 
study. Intensive Care Med 2015; 41 :1411–23. https:// doi.org/ 10.100 
7/s00134- 015- 3934- 7 .
65. Pickering JW, Ralib AM, Endre ZH. Combining creatinine and 
volume kinetics identifies missed cases of acute kidney injury 
follo wing car diac arrest. Critical Care 2013; 17 :1–18. https://doi.or 
g/ 10.1186/ cc11931 .
66. Pickkers P, Mehta RL, Murray PT et al. Effect of human recombi- 
nant alkaline phosphatase on 7-day creatinine clearance in pa- 
tients with sepsis-associated acute kidney injury: a randomized 
clinical trial. JAMA 2018; 320 :1998–2009. https:// doi.org/ 10.1001/ 
jama.2018.14283 .
67. Otto GP, Sossdorf M, Claus RA et al. The late phase of sepsis 
is c har acterized by an incr eased micr obiological burden and 
death rate. Critical Care 2011; 15 :1–8. https:// doi.org/ 10.1186/ cc10 
332 .
68. Weiss SL, Balamuth F, Hensley J et al. The epidemiology of hospi- 
tal death following pediatric se v er e sepsis: when, why, and how 
c hildr en with sepsis die. Pediatr Crit Care Med 2017; 18 :823–30. 
https:// doi.org/ 10.1097/ PCC.0000000000001222 .
69. Remick DG, Bolgos GR, Siddiqui J et al. Six at six: interleukin- 
6 measured 6 h after the initiation of sepsis predicts mortality 
over 3 days. Shock 2002; 17 :463–7. https:// doi.org/ 10.1097/ 000243 
82- 200206000- 00004 .
70. Noritomi DT, Soriano FG, Kellum JA et al. Metabolic acidosis 
in patients with se v er e sepsis and septic shock: a longitudinal 
quantitati ve stud y. Crit Care Med 2009; 37 :2733–9. https://doi.or 
g/ 10.1097/ CCM.0b013e3181a59165 .
71. Zhang C, Zhang X, Sun Z et al. MetaSe psisBase: a biomark er 
database for systems biological analysis and personalized di- 
agnosis of heterogeneous human sepsis. Intensive Care Med 
2023; 49 :1015–7. https:// doi.org/ 10.1007/ s00134- 023- 07126- 4 .
Recei v ed 17 November 2024; revised 26 January 2025; accepted 27 January 2025. published 8 February 2025 
© The Author(s) 2025. Published by Oxford Uni v ersity Pr ess on behalf of the W est China School of Medicine & W est China Hospital of Sichuan Uni v ersity. This is an Open Access article distributed under the 
terms of the Cr eati v e Commons Attribution License ( https://creativecommons.org/licenses/by/4.0/ ), which permits unrestricted reuse, distribution, and reproduction in any medium, provided the original 
work is pr operl y cited. 
Downloaded from https://academic.oup.com/pcm/article/8/1/pbaf003/8005968 by guest on 07 March 2025
