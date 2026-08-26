# Page 1

npj | digital medicine
Article
Published in partnership with Seoul National University Bundang Hospital
https://doi.org/10.1038/s41746-025-02072-5
Interpretable Multiomics Models for
Predicting Surgical Interventions and
Blood Transfusion Requirements in
Traumatic Brain Injury
Check for updates
JiangDeng1,8
,TaoDeng2,8, Yan-ChunZhang3,8,NingZhao1,8,KaiLiu4,5,Chao-JieWang1,6,Zi-JianZhang1,
Jing-Han Ma4,5, Hao Wang4,7, Li-Ping Lv1, Ping Ma1, Xiang-Yan Huang4,7
, Tao Wu3
& Yan-Yu Zhang1
Accurately predicting surgical and transfusion needs in traumatic brain injury (TBI) patients remains
challenging in emergency settings. We developed multiomics data fusion (MDF) models integrating
clinical biomarkers, neural radiological imaging, and clinical text mining for predicting surgical
intervention and blood transfusion requirements across four multicenter cohorts (N = 2219). The MDF
models provided predictions a median of 3 hours before interventions, with surgical model F1 scores
of 0.63–0.85 across external testing, outperforming single-domain approaches. The transfusion
model demonstrated strong cross-center performance (validation/external F1 scores: 0.78, 0.74) and
correlated well with actual transfusion volumes (validation: R = 0.687, external: R = 0.580). SHapley
additive exPlanations revealed radiological features drove surgical predictions, while clinical
parameters (lactate, GCS scores, pupillary reﬂex, and hemoglobin) were crucial for transfusion
predictions. We also developed a simpliﬁed emergency model maintaining robust performance
(validation AUC: 0.81, external AUC: 0.75). These models demonstrate cross-center generalizability
and practical utility for emergency settings, supporting clinical implementation for improved TBI
patient management.
Traumatic brain injury (TBI) is a leading cause of death and disability
worldwide, particularly during major disasters, military conﬂicts, and
emergency care settings1–4. It is estimatedthat there are 69 million new cases
globally each year2, with mortality rates as high as 16% in elderly patients5.
The pathophysiology of TBI involves direct mechanical injuries and sec-
ondary brain damage, initiating cascading pathophysiological changes that
threaten patient survival and long-term quality of life6–8. In emergency care,
rapid identiﬁcation of patients requiring surgical intervention and predic-
tion of perioperative massive transfusion requirements are critical for
optimizing treatment decisions and improving patient outcomes9–11.
However, timely decisions regarding these critical clinical interventions
remain challenging in resource-limited emergency settings. Recent large-
scale randomized controlled trials have demonstrated that even under strict
restrictivetransfusionstrategies,38.4%(141/367)12and48.5%(205/423)13of
TBI patients still required blood transfusion, highlighting the clinical
importance of transfusion requirement prediction. Early identiﬁcation of
patients at high risk for massive transfusion within 2–4 h of admission is
critically important for proactive blood bank preparation, timely blood
resource allocation, and ensuring patient safety—particularly crucial in
emergency settings where blood supply constraints and rapid decision-
making demands intersect14. This early prediction enables medical teams to
secure adequate blood reserves before surgical intervention, potentially
reducing perioperative mortality and improving patient outcomes through
timely transfusion when clinically indicated. Therefore, developing
1Academy of Military Medical Sciences, Beijing, China. 2Department of Anesthesiology, The Second Hospital of Hebei Medical University, Shijiazhuang, China.
3Department of Blood Transfusion Medicine, The Seventh Medical Center of PLA General Hospital, Beijing, China. 4The 960th Hospital of the PLA Joint Logistics
Support Force, Jinan, China. 5Department of Radiology, The 960th Hospital of the PLA Joint Logistics Support Force, Jinan, China. 6College of Biotechnology,
Tianjin University of Science & Technology, Tianjin, China. 7Department of Blood Transfusion Medicine, The 960th Hospital of the PLA Joint Logistics Support
Force, Jinan, China. 8These authors contributed equally: Jiang Deng, Tao Deng, Yan-Chun Zhang, Ning Zhao.
e-mail: ammsdjxm@163.com;
xiangyan73@aliyun.com; wut7175@sina.com; swgczhyy@126.com
npj Digital Medicine | (2025) 8:693 
1
1234567890():,;
1234567890():,;

# Page 2

predictive models capable of early identiﬁcation of surgical indicators and
prediction of massive transfusion risk is of signiﬁcant importance for
improving patient outcomes through ensuring timely and appropriate
clinical interventions and optimal blood resource utilization.
Recent advancements in machine learning (ML), deep learning, and
natural language processing (NLP) have demonstrated the immense
potential of these tools in the medical ﬁeld, particularly in the development
of automated clinical decision support models15–18. Traditional approaches
relying on clinical biomarker analysis are increasingly being supplemented
and enhanced by radiomics and deep learning techniques19,20, with parti-
cularly active applications in the TBI ﬁeld21–24. Additionally, NLP-based
deep learning models can extract key information from electronic health
records, providing valuable solutions for disease prediction and treatment
planning25–27. However, despite these technological advances, research on
their applications in TBI management—particularly in automated predic-
tion of surgical indications and perioperative transfusion requirements—
remains relatively limited. While some predictive models for surgical
indications28,29andtransfusion16basedontraditionalclinicalindicatorshave
shown good performance, these studies are mostly limited to single-center
validation and lack extensive multi-center validation in heterogeneous
patient populations. More importantly, according to the Transparent
Reporting of a multivariable prediction model for Individual Prognosis Or
Diagnosis (TRIPOD) + AI statement guidelines30, these models must
undergo rigorous evaluation across multiple dimensions, including dis-
crimination, calibration, and clinical utility—critical metrics that are fre-
quently underreported in existing literature30–34.
The integration of multicenter, multimodal data has emerged as a
powerful approach in biomedical research, offering signiﬁcant beneﬁts in
improving
prediction
model
robustness
and
cross-scenario
applicability35–37. While concerns about model complexity versus clinical
practicality are valid, existing single-modality prediction models for TBI
management demonstrate signiﬁcant limitations in real-world applications,
particularly regarding cross-institutional generalizability and performance
consistency across diverse patient populations. In the context of TBI
management, multimodal models that synthesize clinical phenotypic data,
radiological imaging ﬁndings, and medical text data provide a more com-
prehensive understanding of the complex pathophysiology than single-
domain prediction models do, theoretically enabling more precise clinical
decision-making. However, the increased sophistication of these models
introduces new challenges, not only regarding model interpretability and
clinical trust, but also including increased computational complexity from
multimodal data fusion, potential information redundancy issues, and
practical deployment difﬁculties in clinical environments. To address these
challenges, on one hand, interpretable machine learning techniques have
become crucial tools for enhancing model transparency by revealing
decision-making processes and quantifying the contribution of individual
input variables to prediction outcomes, thereby improving clinical trust38,39;
ontheotherhand,itisnecessarytoreducethetechnicalbarriersforpractical
deployment through optimizing model architecture and reducing feature
dimensionality. Consequently, the development of predictive models that
balance prediction performance, deployment feasibility, clinical interpret-
ability, and multicenterapplicability is essential for advancing precision TBI
management.
To address these challenges in TBI management, this study integrates
early-available clinical biomarkers, radiomic features, and clinical text data
to develop multimodal prediction models with automated decision support
capabilities for surgical intervention indications and massive blood trans-
fusion requirements (deﬁned as ≥4 U RBCs based on previous studies40–42)
during the early admission period (within 2–4 h). We constructed a mul-
timodal dataset comprising four distinct cohorts with 2219 patients and
validated the predictive performance of our models on this comprehensive
dataset (Table 1). To enhance clinical credibility and transparency, we
incorporated interpretable machine learning techniques, including SHapley
Additive exPlanations (SHAP) and Gradient-weighted Class Activation
Mapping (Grad-CAM), to elucidate model prediction mechanisms and
provide individualized decision explanations. Additionally, considering the
diverse needs of different clinical scenarios, we developed simpliﬁed ver-
sions of our models to provide efﬁcient decision support for resource-
limited emergency medical environments. These models facilitate early
identiﬁcation of TBI patients requiring surgical intervention and massive
blood transfusion, while supporting rapid triage and blood allocation
decisions in emergency medical settings (Fig. 1).
Results
Development and validation of the LR-based CBI model for TBI
surgical indicators
The primary objective of this model was to predict the need for surgical
intervention versus conservative treatment for patients with TBI upon
hospital admission. We analyzed four clinical variables in the training set:
pupillary response (categorized as bilateral normal pupils, bilateral con-
stricted pupils, bilateral dilated pupils, or anisocoria), level of consciousness
(conscious, drowsy, or comatose), age, and sex. Univariable logistic
regression analysis revealed signiﬁcant associations for pupillary response
(OR: 1.40–10.51), level of consciousness (OR: 2.06–7.16), and age categories
(OR: 2.27–2.42) (p < 0.001) (Fig. 2a). Multivariable logistic regression ana-
lysis conﬁrmed these associations, revealing progressive increases in the
odds ratio with age category (OR: 1.72-2.18), increased risk across con-
sciousness levels (OR: 1.95-5.74), and signiﬁcant risks for a partial pupillary
response (OR: 0.74, 4.61, and 1.67, respectively) (Fig. 2b). Following the
evaluation of eight ML algorithms in both the training set and internal set,
we selected the LRmodelastheoptimalapproachonthebasisofitssuperior
discriminative capability while maintaining interpretability (Fig. 2c). A
practical nomogram incorporating age, consciousness level, and pupillary
responseaskeypredictorswasdevelopedforuseinclinicalpractice(Fig.2d).
The predictive performance was robust across the data from multiple
centers, with AUC values consistently exceeding 0.70 (training set: 0.74;
validation set: 0.76; external testing sets 1–3: 0.75) (Fig. 2e, Table 2). Cali-
bration analysis revealed moderate concordance between the predicted and
observed probabilities across all datasets (Fig. 2f). DCA demonstrated the
clinical utility of the model, supporting evidence-based decision-making for
the management of TBI patients (Fig. 2g).
Development and performance evaluation of the 2.5D deep
transfer learning model for CT-based surgical planning
We developed a 2.5D NRI model utilizing deep transfer learning to evaluate
surgical indicators in patients with TBI based on cranial CT scan data. The
model was developed via an innovative multislice analysis strategy centered
on the maximum cross-sectional area of the brain and a two-stage training
strategy: the training set was divided into an initial training set and a
reﬁnement set for 2.5D deep learning model training and validation. The
features extracted from the reﬁnement set by the trained deep learning
modelweresubsequentlyused ina second trainingphase involvingmultiple
ML methods, and ﬁnal validation was performed in the validation set (Fig.
3a). Following extensive comparative analysis of multiple deep learning
architectures, MobileNet V2 emerged as the superior performer (Fig. 3b).
Grad-CAM demonstrated remarkable spatial correspondence between the
regions from which MobileNet V2 extracted key features and areas of cer-
ebral hemorrhage, validating the selection of this model as the optimal
feature extractor (Fig. 3c and detailed in Supplementary Fig. 2). In the
feature engineering phase, we employed PCA to reduce the dimensionality
of the extracted features to 36 components, followed by LASSO regression
for reﬁned feature selection (Fig. 3d). Among the evaluated ML algorithms,
a transfer-trained LR model demonstrated superior performance (Fig. 3e).
This model achieved impressive discriminative ability, with AUC values of
0.89 (95% CI: 0.84–0.93) in the reﬁnement set and 0.83 (95% CI: 0.77–0.88)
in the validation set.
While the model exhibited greater performance than the CBI model in
the internal validation set did, it showed lower stability across the three
external testing sets (AUC range: 0.70–0.81) (Fig. 3f). Calibration analysis
revealed a tendency to underestimate surgical intervention requirements in
https://doi.org/10.1038/s41746-025-02072-5
Article
npj Digital Medicine | (2025) 8:693 
2

# Page 3

external testing set 1 (Fig. 3g). Nevertheless, DCA conﬁrmed the model’s
clinical utility across a broad range of threshold probabilities (Fig. 3h),
suggesting that its potential value remains in clinical decision-making.
Development and validation of the CTM model for admission-
based surgical decision support in TBI patients
In addition to the previously described models, we developed a compre-
hensive NLP approach, named the CTM model, to extract predictive fea-
tures from admission texts for admission-based surgical decision support in
TBIpatients(Fig.4a).TheBorutaalgorithmidentiﬁedkeyclinicalattributes,
and feature importance analysis highlighted brain herniation, multiple
cerebral contusions, and subarachnoid hemorrhage as the most signiﬁcant
predictive variables (Fig. 4b).
Among the eight ML algorithms evaluated in the various datasets, the
LR model demonstrated consistently superior performance in both the
training and validation sets, leading to its selection as the optimal model
(Fig. 4c). The ﬁnal multivariable LR model incorporated multiple clinical
variables, among which brainstem injury and cerebral hemorrhage were
identiﬁed as the two strongest predictors for surgical intervention according
to coefﬁcient analysis (Fig. 4d). The model achieved AUC values of 0.73
(95% CI: 0.70–0.77) in the training set and 0.71 (95% CI: 0.64–0.77) in the
validation set and achieved stable performance across the three external
validation sets, with AUC values ranging from 0.68 to 0.69 (Fig. 4e).
Although the model exhibited relatively modest discriminative ability, its
reliance solely on clinical text data without requiring examination results
underscores its potential as an early screening tool. Calibration analysis
revealed suboptimal calibration in most validation and external testing sets
(Fig. 4f), whereas DCA conﬁrmed the model’s clinical utility across various
threshold probabilities (Fig. 4g), suggesting its potential value as an early
screening tool for TBI surgical decision support.
Development and validation of a CBI Model for Admission-based
Transfusion Prediction in Surgical TBI Patients
The second objective of our predictive modeling focused on identifying the
need for massive transfusion, deﬁned as the administration of more than 4
units of RBCs, in surgical TBI patients. The model development process
began with comprehensive feature selection from a pool of 146 clinical
variables, encompassing ﬁve major categories: baseline characteristics,
biochemical test results, coagulation test results, blood gas analysis results,
and complete blood counts (Supplementary Table 1). We employed RFE to
identify the 30 most signiﬁcant predictive variables for subsequent analysis
(Fig. 5A). Further reﬁnement was achieved through LASSO regression with
cross-validation, ultimately yielding nine key variables for construction of
theﬁnalmodel:consciousnesslevel,Lac(lacticacid),TP(totalprotein),AST
(aspartate aminotransferase), K (potassium), GCS score (Glasgow Coma
Scale score), RBC (red blood cell count), HGB (hemoglobin), and PLR
(pupillary light reﬂex) (Fig. 5B). Among the eight ML algorithms evaluated,
the XGB model demonstrated consistently superior performance in both
the training and validation sets and was thus selected as the optimal model
(Fig. 5c). SHAP analysis provided interpretable insights into feature
importance, revealing that elevated lactate levels, decreased GCS scores, and
low hemoglobin were the three most signiﬁcant predictors of the need for
transfusion (Fig. 5d).
Themodel exhibited robustperformance inthetrainingand validation
sets, achieving AUC values of 0.86 and 0.82, respectively. However, upon
evaluation of the merged external testing datasets, we observed a substantial
decline in predictive ability (AUC = 0.69, 95% CI: 0.63–0.73). This marked
decreaseinperformanceindicateslimitedmodelgeneralizability,suggesting
that in isolation, clinical phenotypic data are insufﬁcient for comprehen-
sively assessing the need for intraoperative transfusion in TBI patients (Fig.
5e). Calibration analyses demonstrated that the CBI model systematically
Table 1 | Demographic characteristics of all included patients and surgical patients in the study
Variable
Overall
Training (Cohort 1)
Validation (Cohort 1)
External Testing 1
(Cohort 2)
External Testing 2
(Cohort 2)
External Testing 3
(Cohort 3)
N = 22191
N = 8481
N = 2121
N = 5011
N = 2621
N = 3961
For all
included
patients
Age (years)
Median (Q1–Q3)
52.00 (40.00–61.00)
55.00 (44.00–64.00)
54.00 (40.50–63.50)
51.00 (40.00–60.00)
54.00 (41.00–60.00)
52.00 (40.00–60.00)
Sex, n (%)
Female
595 (27)
237 (28)
64 (30)
139 (28)
54 (21)
101 (26)
Male
1,624 (73)
611 (72)
148 (70)
362 (72)
208 (79)
295 (74)
Surgery, n (%)
No
1127 (51)
387 (46)
96 (45)
357 (71)
123 (47)
164 (41)
Yes
1092 (49)
461 (54)
116 (55)
144 (29)
139 (53)
232 (59)
Overall
Training (Cohort 1)
Validation (Cohort 1)
External Testing 1
(Cohort 2)
External Testing 2
(Cohort 2)
External Testing 3
(Cohort 3)
N = 10921
N = 4611
N = 1161
N = 1441
N = 1391
N = 2321
For all surgical
patients
Age (years)
Median (Q1–Q3)
53.00 (43.00–62.00)
56.00 (46.00–64.00)
57.00 (43.00 – 65.500)
50.00 (40.00–59.50)
55.00 (47.00–61.00)
53.00 (43.00–61.00)
Sex, n (%)
Female
279 (26)
125 (27)
37 (32)
31 (22)
29 (21)
57 (25)
Male
813 (74)
336 (73)
79 (68)
113 (78)
110 (79)
175 (75)
Transfusion,
n (%)
No
640 (59)
281 (61)
70 (60)
66 (46)
85 (61)
138 (59)
Yes
452 (41)
180 (39)
46 (40)
78 (54)
54 (39)
94 (41)
Time from admission examination to surgery (h)2
Median (Q1–Q3)
3.00 (2.50–10.00)
3.00 (2.50–9.00)
4.00 (2.50–10.50)
3.00 (2.00–13.25)
3.00 (2.50–7.00)
3.00 (2.50–9.00)
1Median (IQR) or frequency (%).
2The median time interval between completion of initial admission records (establishment of initial medical history, diagnosis, blood tests, and CT reports, enabling model-based prediction output) and
surgery initiation.
https://doi.org/10.1038/s41746-025-02072-5
Article
npj Digital Medicine | (2025) 8:693 
3

# Page 4

overestimated the need for transfusion across the external testing cohorts
(Fig. 5f). Furthermore, DCA revealed limited clinical utility in the external
testing sets (Fig. 5g). Taken together, these ﬁndings demonstrate the sub-
stantial challenges inherent in developing standardized transfusion risk
prediction tools that are both consistent and reliable across diverse
institutions.
Development of ML models based on radiological and clinical
text data for admission-based transfusion prediction in TBI
patients
Similarly, we developed two ML models based on radiological and clinical
text data from admission records for the early prediction of intra/post-
operative transfusion (>4 U RBCs) in TBI patients. For the radiological-
based model (NRI model), RFE was implemented to select signiﬁcant
imaging-derived features (Fig. 6a). An evaluation of eight ML algorithms
across both the training and validation sets identiﬁed RF as the optimal
model (Fig. 6b). External validation revealed an AUC of 0.73 (95% CI:
0.68–0.78), marginally exceeding the value for the CBI Model (Fig. 6c and
Supplementary Fig. 3; details on the performance in the training and vali-
dation sets are presented in Supplementary Fig. 1).
For the CTM model, the Boruta algorithm was employed for
feature selection from the structured admission text data (Fig. 6d),
followed by a comprehensive evaluation of eight ML algorithms (Fig.
6e). The ﬁnal model was the LR model, and brainstem injury,
pulmonary edema, and sacroiliac joint fracture were identiﬁed as the
three strongest predictors of the need for transfusion (Fig. 6f). This
text-based model achieved an AUC of 0.69 (95% CI: 0.64–0.74) in the
external validation set (Fig. 6g and Supplementary Fig. 4; details on the
performance in the training and validation sets are shown in Supple-
mentary Fig. 1).
Interestingly, both models exhibited limitations similar to those of
the CBI model during external validation, including suboptimal pre-
dictive performance, systematic overestimation of transfusion risk in
the calibration analyses and limited clinical utility according to the
DCA. These ﬁndings demonstrate the substantial challenges inherent
in developing standardized transfusion prediction methods across
diverse institutions while also suggesting that single-modality data
sources, whether radiological, textual, or biochemical, may be insuf-
ﬁcient for comprehensively assessing the need for intraoperative
transfusion in TBI patients. These limitations emphasize the potential
need for integrated, multimodal approaches in future predictive model
development.
Development and performance evaluation of multiomics data
fusion models (MDF Models) for surgery and transfusion
prediction in TBI
The integration of multiomics data yielded two comprehensive pre-
dictive models following feature selection through LASSO regression
I. Medical Data Collection
Medical Text Data
Clinical Biomarker 
Integratve Model (CBI Model)
Radiological Imaging Data
III. Model Analysis and Application 
   Model Evaluation
   Model Interpretability
Discrimination
Calibration
Clinical Applicability
Grad-CAM
SHAP
Neural Radiological 
Imaging Model (NRI Model)
Clinical Text 
Mining Model (CTM Model)
Clinical Penotype Data
Mutiomics Data Fusion Model (MDF Model)
II. Model Training, Validation and Testing
DT KNN LGBM LR 
Naive Bayes RF SVM XGB
MobileNet, ResNet, 
DenseNet, Inception V3
Cohort 2  N=501 Cohort 3  N=262
Cohort 4  N=396
   Model Building and Validation
 Methods
  External Testing Set 
Machine Learning
2.5D Deep Learning
Cohort 1
Validation Set
N=212
Training Set
N=848
  ;
   Model Fusion      
   Model Simplification 
Consciousness_2
Consciousness_1
Age_2
Pupil_3
Age_0
Age_1
Pupil_0
Age_3
Consciousness_0
Pupil_1
Pupil_2
DL_3
DL_1
DL_0
Subarachnoid hemorrhage
Rib fracture
Skull fracture
Pneumonia
Hepatitis/Cirrhosis
Brainstem injury
Depressed skull fracture
Brain herniation
R = 0.580, P < 0.001
R = 0.687, P < 0.001
[External] R = 0.580, P < 0.001
[Validation] R = 0.687, P < 0.001
0
5
10
15
20
25
0.00
0.25
0.50
0.75
Predicted Probability
RBC (U)
External
Validation
Multiomics Integration
Risk Identification
Blood Count
Physical Examination
CT
Medical Text
Treatment Workflow
Predictive Target 2 
Hospitalization
1. Surgery?
2. Transfusion?
TBI
Bleeding
Predictive Target 1
Cohort 4
(N=396)
Cohort 3 
(N=262)
Cohort 1 
(N=1060)
Cohort 2
(N=501)
Fig. 1 | Schematic showing the workﬂow of the ML-based pipeline to predict
indicators for surgery and blood transfusion. The ﬁgure illustrates the compre-
hensive workﬂow of models developed in this study, comprising three distinct
phases: I. Medical Data Collection, II. Model Training, Validation and Testing, and
III. Model Analysis and Clinical Application.
https://doi.org/10.1038/s41746-025-02072-5
Article
npj Digital Medicine | (2025) 8:693 
4

# Page 5

Fig. 2 | CBI model for surgery prediction in TBI patients. Initial variable screening
through univariable analysis a followed by multivariable logistic regression
b identiﬁed key predictors, including age, consciousness level, and pupillary
response. Model performance was evaluated via various ML approaches (c) and
visualized with a practical nomogram (d). Extensive validation was performed
across multiple datasets (e), while model calibration assessment (f) and decision
curve analysis (g) demonstrated the clinical utility of the model. Age_0: <35 years;
Age_1: 35-50 years; Age_2: 50-65 years; Age_3: >65 years; Consciousness_0: Con-
scious; Consciousness_1: Drowsy; Consciousness_2: Comatose; Pupil_0: Bilateral
Normal Pupils; Pupil_1: Bilateral Constricted Pupils; Pupil_2: Bilateral Dilated
Pupils; Pupil_3: Anisocoria; DT: Decision Tree; KNN: K-nearest neighbors; LGBM:
Light gradient boosting machine; LR: Logistic Regression; RF: Random Forest; SVM:
Support Vector Machine; XGB: eXtreme Gradient Boosting.
https://doi.org/10.1038/s41746-025-02072-5
Article
npj Digital Medicine | (2025) 8:693 
5

# Page 6

Table 2 | Summary of the predictive performance of all the models
Model name
Cohort
AUC
(95% CI)
BrierScore
(95% CI)
Sensitivity
(95% CI)
Speciﬁcity
(95% CI)
Accuracy
(95%CI)
F1 score
(95% CI)
Sample size
(95% CI)
Model architecture
Clinical biomarker integrative model for
surgery
Training
0.74 (0.7–0.77)
0.21 (0.19–0.22)
0.67 (0.63–0.72)
0.72 (0.68–0.78)
0.7 (0.67–0.73)
0.71 (0.67–0.74)
848
LR
Validation
0.76 (0.69–0.82)
0.19 (0.17–0.22)
0.69 (0.6–0.82)
0.78 (0.64–0.88)
0.73 (0.68–0.79)
0.74 (0.67–0.8)
212
External Testing 1
0.75 (0.69–0.79)
0.18 (0.17–0.2)
0.78 (0.46–0.84)
0.62 (0.58–0.92)
0.66 (0.64–0.8)
0.57 (0.52–0.64)
501
External Testing 2
0.75 (0.69–0.81)
0.2 (0.18–0.23)
0.61 (0.55–0.89)
0.79 (0.49–0.86)
0.69 (0.65–0.76)
0.68 (0.63–0.78)
262
External Testing 3
0.75 (0.68–0.81)
0.16 (0.14–0.17)
0.6 (0.5–0.69)
0.85 (0.81–0.91)
0.79 (0.75–0.83)
0.59 (0.52–0.67)
396
Neural radiological imaging model for
surgery
Reﬁnement
0.89 (0.84–0.93)
0.13 (0.11–0.16)
0.89 (0.72–0.94)
0.77 (0.7–0.93)
0.83 (0.79–0.89)
0.85 (0.79–0.9)
210
MobileNet V2 + LR
Validation
0.83 (0.77-0.88)
0.17 (0.14–0.21)
0.77 (0.53–0.93)
0.74 (0.56–0.96)
0.75 (0.7–0.82)
0.77 (0.67–0.84)
212
External Testing 1
0.7 (0.64–0.75)
0.25 (0.22–0.28)
0.78 (0.65–0.85)
0.58 (0.52–0.7)
0.64 (0.6–0.7)
0.57 (0.51–0.63)
429
External Testing 2
0.78 (0.71–0.83)
0.21 (0.17–0.24)
0.83 (0.65–0.89)
0.66 (0.59–0.83)
0.75 (0.7–0.8)
0.77 (0.7–0.82)
248
External Testing 3
0.81 (0.77–0.86)
0.18 (0.15–0.2)
0.81 (0.66–0.9)
0.7 (0.6–0.85)
0.77 (0.72–0.83)
0.82 (0.75–0.87)
367
Clinical text mining model for surgery
Training
0.73 (0.7-0.77)
0.2 (0.19–0.21)
0.66 (0.58–0.7)
0.72 (0.68–0.8)
0.69 (0.66–0.72)
0.69 (0.65–0.73)
848
LR
Validation
0.71 (0.64–0.77)
0.21 (0.19–0.24)
0.72 (0.3–0.81)
0.6 (0.55–0.99)
0.67 (0.59–0.74)
0.71 (0.45–0.77)
212
External Testing 1
0.68 (0.62–0.74)
0.24 (0.22–0.25)
0.38 (0.3–0.71)
0.92 (0.63–0.97)
0.77 (0.63–0.81)
0.48 (0.42–0.57)
501
External Testing 2
0.68 (0.61–0.75)
0.25 (0.22–0.27)
0.79 (0.59–0.86)
0.63 (0.55–0.81)
0.71 (0.66–0.77)
0.75 (0.66–0.8)
262
External Testing 3
0.69 (0.64–0.74)
0.22 (0.2–0.24)
0.72 (0.59–0.78)
0.61 (0.54–0.75)
0.68 (0.63–0.73)
0.74 (0.67–0.78)
396
Mutiomics data fusion model for surgery
Reﬁnement
0.95 (0.92–0.98)
0.09 (0.07–0.11)
0.88 (0.8–0.95)
0.92 (0.85–0.99)
0.9 (0.87–0.94)
0.9 (0.87–0.95)
210
XGB
Validation
0.87 (0.82–0.91)
0.15 (0.12–0.18)
0.79 (0.71–0.88)
0.82 (0.73–0.91)
0.81 (0.76–0.86)
0.82 (0.76–0.88)
212
External Testing 1
0.81 (0.76–0.86)
0.17 (0.16–0.18)
0.81 (0.5–0.88)
0.67 (0.63–
0.72 (0.69–0.85)
0.63 (0.59–0.71)
429
External Testing 2
0.81 (0.75–0.86)
0.18 (0.16–0.21)
0.8 (0.68–0.88)
0.72 (0.66–0.86)
0.77 (0.72–0.82)
0.78 (0.72–0.84)
248
External Testing 3
0.87 (0.83–0.91)
0.15 (0.13–0.17)
0.86 (0.65–0.94)
0.73 (0.65–0.93)
0.81 (0.74–0.86)
0.85 (0.77–0.89)
367
Clinical biomarker integrative model for
blood transfusion
Training
0.86 (0.83–0.9)
0.15 (0.13–0.17)
0.81 (0.65–0.85)
0.77 (0.74–0.93)
0.79 (0.76–0.84)
0.77 (0.72–0.82)
412
XGB
Validation
0.82 (0.73–0.89)
0.17 (0.13-0.22)–
0.74 (0.57–0.86)
0.85 (0.76–0.95)
0.8 (0.73–0.88)
0.76 (0.66–0.86)
106
Merged External Testing
0.69 (0.63–0.73)
0.24 (0.23–0.25)
0.65 (0.6–0.74)
0.67 (0.57–0.74)
0.66 (0.62–0.71)
0.67 (0.62–0.72)
436
Neural radiological imaging model for
blood transfusion
Training
1.0 (1.0–1.0)
0.04 (0.03–0.04)
1.0 (1.0–1.0)
1.0 (1.0–1.0)
1.0 (1.0–1.0)
1.0 (1.0–1.0)
406
RF
Validation
0.74 (0.66–0.83)
0.21 (0.19–0.23)
0.78 (0.54–0.93)
0.63 (0.48–0.88)
0.7 (0.63–0.8)
0.69 (0.59–0.8)
106
Merged External Testing
0.73 (0.68–0.78)
0.21 (0.19–0.22)
0.62 (0.37–0.98)
0.71 (0.33–0.95)
0.66 (0.63–0.71)
0.65 (0.52–0.76)
396
Clinical text mining model for blood
transfusion
Training
0.71 (0.66–0.76)
0.21 (0.2–0.23)
0.57 (0.37–0.84)
0.75 (0.46–0.92)
0.67 (0.62–0.72)
0.6 (0.49–0.67)
412
LR
Validation
0.68 (0.58–0.77)
0.22 (0.2–0.26)
0.59 (0.43–0.88)
0.75 (0.43–0.87)
0.68 (0.58–0.76)
0.61 (0.49–0.73)
106
Merged External Testing
0.69 (0.64–0.74)
0.24 (0.22–0.25)
0.5 (0.44–0.89)
0.79 (0.39–0.85)
0.64 (0.61–0.69)
0.59 (0.54–0.75)
436
Muti-omics data fusion model for blood
transfusion
Training
1.0 (1.0-1.0)
0.03 (0.03–0.03)
1.0 (1.0–1.0)
1.0 (1.0–1.0)
1.0 (1.0–1.0)
1.0 (1.0–1.0)
406
RF
Validation
0.88 (0.81-0.94)
0.15 (0.12–0.17)
0.67 (0.6–0.96)
0.95 (0.66–1.0)
0.83 (0.76–0.9)
0.78 (0.71–0.88)
106
Merged External Testing
0.82 (0.78–0.86)
0.19 (0.17–0.22)
0.65 (0.6–0.78)
0.88 (0.75–0.92)
0.77 (0.73–0.81)
0.74 (0.69–0.79)
396
Simpliﬁed muti-omics data fusion model
for blood transfusion
Training
0.84 (0.8–0.88)
0.18 (0.17–0.19)
0.8 (0.61–0.86)
0.73 (0.68–0.9)
0.76 (0.73–0.81)
0.74 (0.68–0.79)
406
XGB
Validation
0.81 (0.73–0.89)
0.17 (0.13–0.21)
0.63 (0.52–0.9)
0.9 (0.65–0.97)
0.78 (0.72–0.87)
0.72 (0.64–0.83)
106
Merged External Testing
0.75 (0.7–0.8)
0.21 (0.2–0.23)
0.55 (0.45–0.9)
0.83 (0.46–0.92)
0.69 (0.65–0.73)
0.64 (0.57–0.76)
396
https://doi.org/10.1038/s41746-025-02072-5
Article
npj Digital Medicine | (2025) 8:693 
6

# Page 7

a
DenseNet−121
DenseNet−161
DenseNet−169
DenseNet−201
ResNet−50
ResNet−101
Inception V3
MobileNet V2
MobileNet v3 small
0.00
0.25
0.50
0.75
1.00
b
d
f
g
h
e
c
DenseNet-121
ResNet-50
MobileNet V2
−8
−6
−4
−2
1.0
1.2
1.4
1.6
Log(λ)
Binomial Deviance
36 36 36 36 35 35 35 34 34 32 32 32 32 31 29 27 25 23 22 17 10 9 8 6 3 2 2 1 1 1 1 0
Predicted Probability
1
0
0.00
0.25
0.50
0.75
1.00
0.00
0.25
0.50
0.75
1.00
Observed Proportion
Ideal
Flexible Calibration (Loess)
Calibration
...intercept: 0.00 (−0.37 to 0.37)
...slope: 1.00 (0.74 to 1.26)
Discrimination
...c−statistic: 0.89 (0.84 to 0.93)
0.00
0.25
0.50
0.75
1.00
0.00
0.25
0.50
0.75
1.00
Ideal
Flexible Calibration (Loess)
1
0
Predicted Probability
Calibration
...intercept: 0.15 (−0.21 to 0.51)
...slope: 0.75 (0.54 to 0.96)
Discrimination
...c−statistic: 0.83 (0.77 to 0.88)
0.00
0.25
0.50
0.75
1.00
0.00
0.25
0.50
0.75
1.00
Ideal
Flexible Calibration (Loess)
1
0
Predicted Probability
Calibration
...intercept: −1.28 (−1.54 to −1.02)
...slope: 0.40 (0.28 to 0.53)
Discrimination
...c−statistic: 0.70 (0.64 to 0.75)
0.00
0.25
0.50
0.75
1.00
0.00
0.25
0.50
0.75
1.00
Ideal
Flexible Calibration (Loess)
1
0
Predicted Probability
Calibration
...intercept: 0.35 (0.02 to 0.68)
...slope: 0.55 (0.38 to 0.71)
Discrimination
...c−statistic: 0.78 (0.71 to 0.83)
0.00
0.25
0.50
0.75
1.00
0.00
0.25
0.50
0.75
1.00
Ideal
Flexible Calibration (Loess)
1
0
Predicted Probability
Calibration
...intercept: 0.45 (0.16 to 0.73)
...slope: 0.66 (0.51 to 0.81)
Discrimination
...c−statistic: 0.81 (0.77 to 0.86)
0.0
0.2
0.4
0.6
0.8
1.0
0.0
0.2
0.4
0.6
0.8
1.0
Net Benefit
Threshold Probability
0.0
0.2
0.4
0.6
0.8
1.0
0.0
0.2
0.4
0.6
0.8
1.0
Threshold Probability
0.0
0.2
0.4
0.6
0.8
1.0
0.0
0.2
0.4
0.6
0.8
1.0
Threshold Probability
0.0
0.2
0.4
0.6
0.8
1.0
0.0
0.2
0.4
0.6
0.8
1.0
Threshold Probability
0.0
0.2
0.4
0.6
0.8
1.0
0.0
0.2
0.4
0.6
0.8
1.0
Threshold Probability
AUC:0.89
95%CI (0.84−0.93)
0.00
0.25
0.50
0.75
1.00
0.00
0.25
0.50
0.75
1.00
1 − Specificity
Sensitivity
Refinement Set
0.00
0.25
0.50
0.75
1.00
0.00
0.25
0.50
0.75
1.00
1 − Specificity
AUC:0.83 
95%CI (0.77−0.88)
Validation Set
0.00
0.25
0.50
0.75
1.00
0.00
0.25
0.50
0.75
1.00
1 − Specificity
AUC:0.70
95%CI (0.64−0.75)
External Testing Set 1
0.00
0.25
0.50
0.75
1.00
0.00
0.25
0.50
0.75
1.00
1 − Specificity
AUC:0.78
95%CI (0.71−0.83)
External Testing Set 2
0.00
0.25
0.50
0.75
1.00
0.00
0.25
0.50
0.75
1.00
1 − Specificity
AUC:0.81
95%CI (0.77−0.86)
External Testing Set 3
Apparent Curve
Cross−validated Curve
All
None
1.0
0.8
0.6
0.4
0.2
0.0
False Positive Rate
0.0
0.2
0.4
0.6
0.8
1.0
True Positive Rate
DT (AUC = 0.852 (95% CI: 0.798 - 0.901))
KNN (AUC = 1.000 (95% CI: 1.000 - 1.000))
LGBM (AUC = 0.500 (95% CI: 0.500 - 0.500))
LR (AUC = 0.890 (95% CI: 0.842 - 0.930))
Naive Bayes (AUC = 0.862 (95% CI: 0.809 - 0.911))
RF (AUC = 1.000 (95% CI: 1.000 - 1.000))
SVM (AUC = 0.114 (95% CI: 0.071 - 0.164))
XGB (AUC = 0.959 (95% CI: 0.934 - 0.979))
1.0
0.8
0.6
0.4
0.2
0.0
ROC Curve Comparison Diagram
False Positive Rate
0.0
0.2
0.4
0.6
0.8
1.0
True Positive Rate
DT (AUC = 0.736 (95% CI: 0.670 - 0.798))
KNN (AUC = 0.771 (95% CI: 0.708 - 0.829))
LGBM (AUC = 0.500 (95% CI: 0.500 - 0.500))
LR (AUC = 0.833 (95% CI: 0.775 - 0.882))
Naive Bayes (AUC = 0.830 (95% CI: 0.773 - 0.883))
RF (AUC = 0.804 (95% CI: 0.739 - 0.861))
SVM (AUC = 0.173 (95% CI: 0.122 - 0.232))
XGB (AUC = 0.804 (95% CI: 0.740 - 0.862))
Refinement Set
Validation Set
+20 pixel
MaxRoi
+5 pixel
+10 pixel
-5 pixel
-10 pixel
-20 pixel
Initial Training:
Deep Learning
Refinement Set 
(N=210)
Symmetric CT Slices
Secon
S
dary Training:
Machine Learning
1.0
0.8
0.6
0.4
0.2
0.0
Validation Set
0.0
0.2
0.4
0.6
0.8
1.0
DT (AUC = 0.719 (95% CI: 0.623 - 0.812))
KNN (AUC = 0.761 (95% CI: 0.666 - 0.843))
LGBM (AUC = 0.654 (95% CI: 0.547 - 0.756))
LR (AUC = 0.768 (95% CI: 0.669 - 0.851))
Naive Bayes (AUC = 0.730 (95% CI: 0.634 - 0.821))
RF (AUC = 0.790 (95% CI: 0.690 - 0.869))
SVM (AUC = 0.759 (95% CI: 0.653 - 0.843))
XGB (AUC = 0.809 (95% CI: 0.719 - 0.883))
Cranial CT
Data
Preprocessing
Validation Set 
(N=212)
Validation
V
Initial Training Set
（N=638）
Accuracy
Fig. 3 | NRI Model for Surgery Prediction in TBI Patients. a Overview of the 2.5D
deep learning framework: Seven strategic slices (central slices ±5, ±10, ±20 pixels)
from the patient’s brain CT image are processed to form a 7-channel input for deep
learning and ML analysis. b Comparative performance of different deep learning
architectures, including MobileNet, Inception, ResNet, and DenseNet variants.
c Grad-CAM visualization results for DenseNet-121, ResNet-50, and MobileNet V2,
demonstrating image areas where the models focused their attention. d LASSO
regression for feature selection optimization. e ROC curves demonstrating the
performance of multiple ML classiﬁers. f Model performance across the reﬁnement
set (AUC = 0.89), validation set (AUC = 0.83), and three external testing sets
(AUC = 0.70-0.82). g Calibration plots showing predicted versus observed prob-
abilities across all datasets. h Decision curve analysis demonstrating the clinical
utility across various threshold probabilities. MaxRoi Max Region of interest.
https://doi.org/10.1038/s41746-025-02072-5
Article
npj Digital Medicine | (2025) 8:693 
7

# Page 8

Fig. 4 | CTM Model for Surgery Prediction in TBI Patients. a Model development
pipeline demonstrating the conversion of admissions text into structured data,
involving steps including tokenization and lemmatization. b Feature selection via
the Boruta algorithm; the panel shows the importance of various attributes used in
the model. c Training and validation results of eight ML algorithms applied to the
training and validation cohorts. d Variables included in the ﬁnal multivariable LR
model; the coefﬁcients indicate the inﬂuence of each variable on the prediction.
Model performance evaluation across all datasets (training, validation, and three
external testing sets) via e receiver operating characteristic (ROC) curves for dis-
criminative ability, f calibration plots for prediction accuracy, and g decision curve
analysis for clinical utility assessment. a: Hemorrhage from multiple cerebral
contusions; b: Soft tissue swelling of the head; c: Multiple cutaneous contusions and
lacerations.
https://doi.org/10.1038/s41746-025-02072-5
Article
npj Digital Medicine | (2025) 8:693 
8

# Page 9

(Supplementary Fig. 5a, b). The surgical indicator model incorporated
14 key features, including clinical phenotypic features (consciousness
level, age, and pupil status), radiological imaging features (three deep
learning features), and information extracted from medical texts
(including subarachnoid hemorrhage, fracture patterns, and several
complications). The transfusion prediction model included 23
features, including laboratory parameters, clinical scores, deep
learning-derived imaging features, and text-mined clinical complica-
tions. XGB demonstrated optimal performance for surgical prediction
across all cohorts (Fig. 7a), whereas RF emerged as the superior
algorithm for transfusion prediction (Fig. 7b). Notably, both MDF
models exhibited greater discriminative ability and generalizability
https://doi.org/10.1038/s41746-025-02072-5
Article
npj Digital Medicine | (2025) 8:693 
9

# Page 10

than the corresponding single-domain approaches did, as evidenced
by ROC curve analysis, calibration plots, and DCA (Supplementary
Fig. 5c–e for the surgery indicator model and Supplementary Fig. 5f–h
for the transfusion model).
To evaluate potential demographic biases in model performance, we
conductedcomprehensivesubgroupanalysesstratiﬁedbysexandageacross
alltheexternalvalidationdatasets(SupplementaryFig.6).TheMDFmodels
maintained consistent performance across most demographic subgroups,
with no signiﬁcant degradation in predictive ability observed between male
and female patients or across different age categories. This stability in per-
formance across diverse patient demographics supports the fairness and
generalizability of our models, although it should be noted that certain
subgroups with limited sample sizes or single-category outcomes could not
undergo complete model validation (as indicated in the ROC curve
annotations).
To compare the heterogeneity observed in single-omics transfusion
models with that observed in multiomics approaches, we employed rain
cloud plots to analyze the prediction probability distributions for the
transfused and nontransfused patients across the internal and external
testing sets (Fig. 7c, d). The results showed that the CBI model and CTM
model, which are predominantly based on discrete variables, exhibited
discontinuous probability distributions with limited discriminative ability.
Both the NRI models and the MDF models demonstrated robust dis-
crimination in the internal test set. Notably, the MDF models maintained
superior performance in the external testing sets, indicating greater
robustness and generalizability.
This conclusion was further validated by radar plots of F1 scores
(Fig. 7e, f and details in Table 2). In both the surgical indication and
blood transfusion prediction tasks, the MDF model demonstrated
consistently superior balanced performance across the validation and
external testing cohorts. For surgical indication prediction, the model
achieved an impressive F1 score of 0.82 in the validation cohort and
maintained robust performance (F1: 0.63–0.85) across external testing
cohorts, substantially outperforming other single-domain approaches
(CBI: 0.57–0.68, NRI: 0.57–0.82, CTM: 0.48–0.75). Similarly, in terms
of blood transfusion prediction, the multiomics model achieved the
highest F1 scores in both the validation (0.78) and external testing
(0.74) cohorts, which consistently surpassed those of the CBI (0.76,
0.67), NRI (0.69, 0.65), and CTM (0.61, 0.59) models in the respective
cohorts. The superior F1 scores across both tasks reﬂect the model’s
robust ability to balance sensitivity and speciﬁcity, which was further
supported by higher accuracy rates (surgical: 0.72–0.81; transfusion:
0.77–0.83) and better calibration, as indicated by lower Brier scores.
This consistent performance advantage demonstrates the exceptional
ability of the MDF model to integrate diverse data types and maintain
reliable predictions across different clinical settings and prediction
tasks, representing a signiﬁcant advancement in multimodal clinical
decision support systems.
Feature importance analysis and clinical validation of the MDF
models in TBI management
To improve the possibility of the clinical implementation of our models, we
conducted comprehensive model interpretability analyses. SHAP analysis
revealed distinct feature importance patterns for the prediction of surgical
intervention (Fig. 8a) and blood transfusion (Fig. 8b). For surgical predic-
tion, deep learning features (DL_1–3) derived from radiological imaging
demonstrated the highest predictive weights, followed by the level of con-
sciousness from among the clinical biomarkers and subarachnoid hemor-
rhage and skull fracture from among the medical text data. For transfusion
prediction,clinicalbiomarkers,particularlyhighLaclevels,highGCSscores,
high PLRs, and high HGB values, had the greatest importance weights.
Radiological imaging-derived deep learning features showed moderate
importance, whereas medical text data features, including rib fracture and
multiple cerebral contusions, demonstrated lower predictive weights.
We further validated the clinical utility of the MDF model through
systematic patient risk stratiﬁcation. TBI patients who underwent surgical
intervention were stratiﬁed into three risk categories (low, medium, and
high) on the basis of the model-predicted transfusion risk. Analysis of the
actual red blood cell transfusion volumes during perioperative care revealed
statistically signiﬁcant differences among the risk groups (P < 0.05 or 0.001)
across both the internal and external testing sets (Fig. 8c). The model’s
predictive accuracy was further supported by correlation analysis between
the predicted probabilities and the actual RBC transfusion volumes, which
revealedstrongassociationsinboththevalidation(R = 0.687,P < 0.001)and
merged external testing sets (R = 0.580, P < 0.001) (Fig. 8d). These ﬁndings
validate the model’s potential as a clinical transfusion risk score, demon-
stratingitseffectivenessinpatientstratiﬁcationandtransfusionrequirement
prediction and supporting its potential integration into clinical decision
support systems. To achieve this goal, we propose a workﬂow designed for
deployment within real-world hospital settings, comprising three key
components: clinical workﬂow integration, user training outline, and spe-
ciﬁc case demonstrations (Supplementary Notes 1–3).
Performance evaluation and clinical validation of the simpliﬁed
multiomics prediction model
The complex biochemical and blood gas analysis data requirements of the
comprehensive MDF model could limit its application in emergency
situations. Therefore, a simpliﬁed version was developed that incorporates
only routine complete blood count parameters, physical examination data,
CT imaging features, and admission diagnostic text data. A systematic
evaluation of multiple ML algorithms revealed that XGB had the best per-
formance; therefore, this algorithm was selected as the optimal modeling
approach (Fig. 9a). The model achieved robust performance in the training
set (AUC: 0.84, 95% CI: 0.80–0.88) and demonstrated strong general-
izability in both the validation and external testing sets (0.81, 95% CI:
0.73–0.89; and 0.75, 95% CI: 0.70–0.80, respectively). The calibration curves
revealed moderate agreement between the predicted probabilities and
observed outcomes (Fig. 9c), whereas DCA demonstrated that the model
offered positive net clinical beneﬁts (Fig. 9d). SHAP analysis identiﬁed key
predictive factors: HGB from complete blood counts, ﬁve deep learning
features (DL_17, DL_11, DL_30, DL_0, DL_23), and the GCS score and the
PLR from the physical examination, thus validating the clinical utility of
the model.
Discussion
This study developed a multi-omics fusion model integrating clinical phe-
notypic data, radiological imaging, and medical text data to predict surgical
indications and blood transfusion requirements in traumatic brain injury
Fig. 5 | CBI model for transfusion prediction in TBI patients. a Initial feature
selection via RFE from 146 clinical variables; the panel shows variable importance
rankings for baseline characteristics, biochemical test parameters, coagulation test
parameters, blood gas analysis parameters, and complete blood counts. b LASSO
regression results demonstrating reﬁned feature selection with optimal lambda value
selection through cross-validation. c Comparison of the performance of eight ML
algorithms in the training and validation cohorts, displaying ROC curves with
corresponding AUC values for each model. d SHAP analysis of the XGBoost model,
revealing the contribution and importance ranking of each selected feature in
predicting the need for transfusion. Model performance evaluation across all
datasets (training, validation, and merged external test sets) via e receiver operating
characteristic (ROC) curves for discriminative ability, f calibration plots for pre-
diction accuracy, and g decision curve analysis for clinical utility assessment.
Consciousness_0: conscious; Consciousness_1: drowsy; Consciousness_2: coma-
tose; Lac: lactic acid; TP: total protein; AST: aspartate aminotransferase; K: potas-
sium ion; GCS score: Glasgow Coma Scale score, GCS score_0: > 15; GCS
score_1:15--13; GCS score_2:13--9; GCS score_3:9--3; GCS score_4: < 3; RBC red
blood cell count, HGB hemoglobin, PLR pupillary light reﬂex.
https://doi.org/10.1038/s41746-025-02072-5
Article
npj Digital Medicine | (2025) 8:693 
10

# Page 11

Fig. 6 | NRI and CTM models for fusion prediction in TBI patients. a Feature
selection process employing RFE for deep learning features extracted from radi-
ological images. b Comparison of the performance of eight ML algorithms in the
training and validation sets, displaying ROC curves with corresponding AUC values
for each model. c Performance evaluation of the optimized RF model in the external
testing set. d Feature selection of structured data from the CTM model via the Boruta
algorithm for model construction. e Comparison of the performance of eight ML
algorithms in the training and validation sets. f Features and their coefﬁcients were
incorporated into the optimal LR model. g Performance evaluation of the optimized
LR model in the external testing set. a: Soft tissue swelling of the head; b: Multiple
cutaneous contusions and lacerations; c: Hemorrhage from multiple cerebral
contusions; d: Closed craniocerebral injury; e: Temporal lobe contusion.
https://doi.org/10.1038/s41746-025-02072-5
Article
npj Digital Medicine | (2025) 8:693 
11

# Page 12

(TBI) patients. The model was validated using data from four independent
clinical cohorts. All models—including both single-omics and multi-omics
approaches—were rigorously developed and validated following TRI-
POD + AI guidelines43, with comprehensive evaluation of discrimination,
calibration, and clinical utility (see Supplementary Table 2). By integrating
explainable machine learning techniques such as SHAP and Grad-CAM,
the model’s decision-making process became transparent, enhancing its
clinical credibility. It must be acknowledged that the multi-omics model did
notperformbestacrossallevaluationmetrics,andsome“lessdataintensive”
models16,18 may perform better on speciﬁc indicators. However, our
comprehensive evaluation demonstrated that the multi-omics model
exhibited the most consistent robustness in cross-center validation (see
Table 2). Even under broad inclusion criteria—encompassing a wide age
range, minimal restrictions on comorbidities, and no time limitations
between admission and surgery—our constructed model maintained stable
predictive performance, conﬁrming its practical value. The end-to-end
modeling strategy requires only standard admission data without additional
examinations, thereby ensuring feasibility in clinical practice. Our research
ﬁndings suggest that this model has the potential to support surgical
decision-making assistance and may provide additional preparation time
Fig. 7 | Multiomics data fusion model for surgery and transfusion prediction in
TBI patients. A comprehensive multiomics approach that integrates biochemical
markers, radiological imaging features, and CTM data was developed and validated
for the prediction of the need for surgery and blood transfusion in traumatic brain
injury (TBI) patients. a, b Receiver operating characteristic (ROC) curves illustrating
the systematic evaluation of various ML algorithms during the model training and
validation phases, utilizing carefully selected features from each data modality.
c, d Rain cloud plot visualization and probability density distributions comparing
four distinct omics approaches (CBI, NRI, CTM, and MDF models), illustrating
model discrimination between transfusion/nontransfusion patients across valida-
tion cohorts. e, f Comprehensive performance evaluation through radar plot
visualization of F1 scores (which harmonically balance precision and recall) across
multiple datasets, demonstrating the predictive accuracy for both surgical inter-
vention indicators and the need for transfusion.
https://doi.org/10.1038/s41746-025-02072-5
Article
npj Digital Medicine | (2025) 8:693 
12

# Page 13

Fig. 8 | Feature importance analysis and clinical validation of the MDF Model.
SHAP analysis showing feature importance weights for surgical intervention a and
blood transfusion prediction b in circular plots and heatmap visualization of SHAP
value distributions for key predictive features; f(x) curves show the model output
distribution. c Comparison of actual RBC transfusion volumes across risk groups
(low-, medium-, and high-risk) in the validation (upper) and external (lower) testing
sets (*P < 0.05, **P < 0.01, ***P < 0.001). d Correlation analysis between the pre-
dicted transfusion probabilities and actual RBC transfusion volumes (internal:
R = 0.687, P < 0.001; external: R = 0.580, P < 0.001).
https://doi.org/10.1038/s41746-025-02072-5
Article
npj Digital Medicine | (2025) 8:693 
13

# Page 14

Fig. 9 | Performance evaluation of the simpliﬁed multiomics prediction model.
a ROC curves showing algorithm performance in the training and internal testing
sets, including the DT, KNN, LGBM, LR, naive Bayes, RF, SVM, and XGB models,
with corresponding AUC values and 95% conﬁdence intervals. b ROC curves
demonstrating model performance in the training, validation and merged external
testing cohorts (AUC: 0.84, 0.81, and 0.75, respectively; gray shading indicates 95%
CIs). c Calibration curves comparing the predicted probabilities with the observed
outcomes across the three cohorts (orange lines). d Decision curve analysis showing
the net clinical beneﬁts of the models (red lines) alongside the treat-all (solid black)
and treat-none (dotted) strategies across different threshold probabilities. e SHAP
value heatmap displaying the impact of key features (HGB, DL_17, DL_11,
GCS_Score, PLR, DL_30, DL_0, DL_23) on model prediction; the corresponding
model output distribution is shown in f(x).
https://doi.org/10.1038/s41746-025-02072-5
Article
npj Digital Medicine | (2025) 8:693 
14

# Page 15

for blood bank reserves, although its clinical utility still requires further
validation through prospective studies44.
Model development based on clinical phenotypes represents the most
common paradigm for machine learning in medicine. In our initial phase,
we integrated clinical guidelines with frontline expertise to ensure appro-
priate
feature
selection
(https://www.facs.org/media/vgfgjpfk/best-
practices-guidelines-traumatic-brain-injury.pdf). However, most guideline
criteria (such as coma from traumatic hematoma or posterior fossa lesions)
arederivedprimarilyfromCTﬁndingsorclinicalassessments,makingthem
difﬁcult to directly quantify from phenotypic data. Our ﬁnal model, con-
structed using only three parameters—pupillary response, consciousness
level,andage—achievedexcellentrobustness(externaltestingsets1–3AUC:
0.75). This ﬁnding is highly consistent with clinical understanding: pupillary
response is closely related to the GCS score, while the level of consciousness
serves as a simpliﬁed indicator for intracranial pressure. According to the
literature, GCS45,46, intracranial pressure47–49, and age50–53 are all recognized
determinants in neurosurgical decision-making. Therefore, we consider this
streamlined model a further reﬁnement of clinical expertise. For transfusion
prediction, SHAP analysis revealed elevated lactate levels, low GCS scores,
and decreased HGB levels as the three most signiﬁcant predictors of trans-
fusion requirements, which is consistent with the European guidelines on
posttraumatic severe bleeding management54 and the ﬁndings of multiple
studies55–57, which emphasize lactate as a sensitive marker for hemorrhage
and tissue perfusion. GCS scores and HGB reﬂect the overall severity of TBI
and anemic status, respectively, in accordance with our clinical experience.
However, the model’s low generalizability in predicting transfusion, despite
feature selection from 146 admission variables, reﬂects the inherent chal-
lenge in predicting the future need for transfusion on the basis solely of early
admission indicators (Merged external AUC: 0.69). These ﬁndings suggest
that clinical phenotypic data alone may be insufﬁcient for fully character-
izing patients’ transfusion needs.
The implementation of radiological imaging data through 2.5D deep
transfer learning for predicting neurosurgical indicators is a relatively novel
technique inbrain imaginganalysis. This approach offers a strategic balance
between traditional methodologies; 2D approaches can capture only planar
information, whereas 3D methods, although more comprehensive, are
limited by computational challenges related to parameter complexity.
Therefore, 2.5D methods leverage multiple consecutive slices to combine
the advantages of both approaches58–60. To address the inherent “black box”
nature of deep learning, we employed Grad-CAMvisualization, a technique
that is being implemented more frequently for intracerebral hemorrhage
prediction models61, to elucidate the decision-making processes of the
models. Our results demonstrated signiﬁcant spatial correspondence
between MobileNet V2’s feature extraction regions and areas of cerebral
hemorrhage, suggesting that the 2.5D deep learning approach successfully
captured trauma-related features across multiple planes of the brain. While
the model achieved greater performance than the CBI model in the vali-
dation set, its lower stability across the external testing sets (AUC range:
0.70-0.81) highlights the challenges in maintaining consistent performance
across diverse clinical settings.
The automation of clinical text extraction for predictive modeling is an
innovative approach in current clinical prediction frameworks, potentially
capturing physicians’ comprehensive symptom descriptions, including
severity assessments and multisystem injury patterns. Initially, we explored
popular NLP models such as BERT for feature extraction or prediction
output62.However,thisapproachwasultimatelyabandoned fortwo reasons:
ﬁrst, the admission diagnoses proved too concise for effective BERT
implementation (10–50 characters in length), and second, more complex
NLP models presented signiﬁcant challenges in interpreting the results.
Instead, we opted for a structured approach involving the conversion of
admission diagnoses into structured data through stemming techniques.
While this model demonstrated relatively modest predictive abilities in both
surgical indication and transfusion prediction and suboptimal discrimina-
tion and calibration across the external datasets, it provided suitable trans-
parency regarding the decision processes. Notably, these model features
identiﬁedthroughdata-drivenselectionprocessesshowedhighconcordance
withpreviousclinicalﬁndingsorexperience,whicharewellsupportedbythe
existing medical literature. For example, brainstem injury and cerebral
hemorrhagehaveemergedasthestrongestsurgicalinterventionindicators63,
whereas brainstem injury64,65, pulmonary edema66, and sacroiliac joint
fracture have been identiﬁed as markers of poor disease prognosis or severe
injury, potentially indirectly predicting the need for perioperative or post-
operative transfusion. Future research with larger datasets and advances in
reasoning-based transformer models may provide promising directions for
enhancing clinical text analysis in TBI prediction tasks.
PreviousmultimodalstudiesinTBIresearchhaveprimarilyfocusedon
prognostic applications, typically integrating imaging data with clinical
phenotypic parameters but rarely incorporating clinical text features. For
instance, recent work combined diffusion tensor imaging metrics with
serum biomarkers for evaluating recovery outcomes in mild TBI patients,
yet concentrated on long-term functional outcomes rather than acute
clinical decision-making20,23,67. Therefore, the study’s most important result
is the integration of clinical, radiological, and text data into the MDF model.
By synthesizing complementary information frommultiple data modalities,
the fusion models consistently outperform the single-domain models.
Speciﬁcally, radiological imaging data capture localized injury severity,
clinical biomarkers reﬂect systemic physiological states, and medical text
data provide a holistic summary of injury patterns and comorbidities. This
comprehensive characterization allowed the models to achieve superior
generalizability and robustness across diverse patient populations. SHAP
analysis further elucidated the contributions of each data modality. For
surgical prediction, radiological features are the most important, reﬂecting
their critical role in assessing intracranial lesions. Conversely, transfusion
prediction was driven primarily by clinical biomarkers, emphasizing their
relevanceinestimatingsystemicbloodlossandhemodynamiccompromise.
These results indicate that while the multiomics model may not be optimal
in all scenarios, it consistently demonstrates the highest robustness. More-
over, the model’s end-to-end design requires no additional diagnostic tests
for patients, enhancing its clinical feasibility. To further improve its
applicability in emergency medical scenarios, we developed a simpliﬁed
versionof themultiomicsmodelthatomitsbloodbiochemistry,coagulation
function, and blood gas analysis results. Despite its reduced complexity, the
simpliﬁedmodelmaintained strongpredictiveperformance,demonstrating
its potential utility in resource-limited settings.
A key advantage of our multi-omics approach lies in its exceptional
potential for seamless integration with existing emergency clinical work-
ﬂows. Model prediction occurs after patients complete necessary admission
examinations, typically within 2–4 h post-admission when all required
features are available. Our results demonstrate that the model can generate
outputs a median of 3 h before actual intervention, thereby providing
additional preparation time for surgical implementation and massive
transfusion protocols. When predictions indicate potential perioperative
massive transfusion needs, multi-disciplinary teams receive alerts and blood
banks initiate proactive resource allocation with products maintained in
“standby” status. It is important to emphasize that actual transfusion
decisions still depend on real-time physiological status during surgery,
following current guidelines that recommend restrictive transfusion stra-
tegiesforhemodynamicallystableTBIpatients(hemoglobin<7 g/dL)68.The
core value of our model lies in ensuring readily available blood products
when healthcare providers determine massive transfusion is required.
Furthermore, the model demonstrates remarkable ﬂexibility when facing
suboptimaldataquality—forexample,whenCTimagingiscompromised,it
canoperateinsingle-modalmodeusingonlyclinicalbiomarkersortextdata
while still providing clinically relevant results.
To facilitate the practical implementation of this model, we propose a
three-layer system architecture integration framework comprising a data
extraction layer, prediction engine, and clinical interface (Supplementary
Note 1). This architecture addresses key implementation requirements
through optimized design: (1) text information is extracted solely from
patient admission diagnoses, signiﬁcantly reducing data acquisition
https://doi.org/10.1038/s41746-025-02072-5
Article
npj Digital Medicine | (2025) 8:693 
15

# Page 16

complexity; (2) structured data employs standardized strategies for direct
retrieval, minimizing processing burden; (3) image data processing utilizes
thelightweightShufﬂeNetv2model,whichsupportssmartphoneoperation.
All input data derive from routine clinical activities and can be instantly
accessed within existing electronic health record (EHR) systems without
requiring additional examinations. The model features minimal computa-
tional load, with a user interface that can be seamlessly integrated into EHR
platforms to provide real-time decision support without disrupting existing
workﬂows. Currently,comprehensive software basedonthismodelisunder
development, and we anticipate that this intelligent decision support system
will advance to clinical prospective validation as soon as possible. To ensure
effective application, we will provide structured training for users, covering
core components including model principle understanding, output inter-
pretation, limitation identiﬁcation, and clinical knowledge integration
(Supplementary Note 2). Supplementary Note 3 demonstrates the practical
clinical application value of this model through four representative cases.
This study has several limitations that should be considered. First,
the retrospective design introduces inherent limitations, including
potential biases from missing data (deletion/imputation) and patient
selection criteria, thereby affecting the representativeness of the study
population. These limitations may inﬂuence machine learning model
development by highlighting associations rather than causal relation-
ships between features and predicted outcomes, ultimately impacting
the models’ generalizability and clinical applicability in diverse settings.
Furthermore, the retrospective design limited our ability to capture
comprehensive socioeconomic data, which may introduce unmeasured
confounding bias. To mitigate these limitations, we implemented
standardized review processes with independent physician assessment,
mandatory data collection training, and uniﬁed treatment protocols
across participating high-level tertiary institutions. Although these
measures reduce, but may not eliminate, residual confounding from
unmeasured socioeconomic factors. Regarding demographic repre-
sentativeness, our analysis of age, sex, and other demographic factors
across cohorts (Table 1) revealed relatively minor differences, with
female proportions ranging from 21% to 32% and median ages between
51 and 57 years. To address potential demographic biases, our time-
based inclusion strategy enrolled all eligible patients within predeﬁned
time windows, minimizing selection bias while representing the natural
demographic distribution of TBI patients in real-world settings.
Through our data-driven feature selection process, neither gender nor
age emerged as input features in the ﬁnal predictive models, suggesting a
limited impact on model predictions. Additional subgroup analyses
demonstrated consistent model performance across most demographic
categories, although some subgroups could not undergo complete
validation due to insufﬁcient sample sizes (Supplementary Fig. 6). Our
expanded diagnostic performance assessment across different age and
sex subgroups strengthens evidence regarding model “fairness,” com-
plying with the TRIPOD-AI guidelines for model evaluation. Finally,
despite robust retrospective multicenter validation, prospective real-
time validation remains essential to conﬁrm clinical utility and assess
real-world performance under actual clinical44.
In summary, this study demonstrates the feasibility and efﬁcacy of a
multiomics fusion model that integrates clinical phenotypic, radiological
imaging, and medical text data for TBI management. By synthesizing
traditional clinical markers with deep learning features and medical text
data, the model achieves an optimal balance among predictive accuracy,
interpretability, and clinical applicability across diverse datasets. The
automated integration and standardized decision-making processes
render these models particularly valuable in emergency medical sce-
narios, such as major disasters and military conﬂicts, effectively facil-
itating medical resource optimization. Through prospective validation
with larger and more diverse patient cohorts, these models demonstrate
promise for broader clinical implementation, ultimately enhancing the
quality of care for TBI patients.
Methods
Study design and population
We conducted aretrospective,multicenterstudyof2219TBIpatientsacross
four independent cohorts from January 2015 to June 2024. The study
population comprised Cohort 1 (n = 1060) from the main campus of the
Second Hospital of Hebei Medical University, Cohort 2 (n = 501) from the
Seventh Medical Center of PLA General Hospital, Cohort 3 (n = 262) from
the 960th Hospital of the PLA Joint Logistics Support Force, and Cohort 4
(n = 396) from the Luquan Campus of the Second Hospital of Hebei
Medical University. All the participating centers are Grade IIIA hospitals
with specialized neurosurgical units and emergency departments, and are
selected to ensure diverse patient populations and healthcare settings for
robust model development and validation.
Cohort 1 was designated for model development and internal valida-
tion, whereas Cohorts 2–4 were used for external testing (Supplementary
Fig. 1). The inclusion criteria included a conﬁrmed TBI diagnosis by qua-
liﬁed physicians and complete head CT scan data. Patients were excluded if
they were <18 years, >80 years, or pregnant; transferred >48 h postinjury;
received prior blood transfusion at other facilities; or had severe infectious
diseases, active malignancies, chronic conditions, or other major illnesses
affecting daily activities. All patients received standardized care according to
current TBI management guidelines, with consistent surgical intervention
criteria and blood transfusion protocols across all participating centers
(detailed in Supplementary Note 4).
Data collection and outcomes
Data were collected from electronic health records across three domains:
clinical phenotypic data, radiological imaging data, and medical text data.
To ensure data consistency across participating centers, we implemented
comprehensive standardization protocols: uniﬁed training documentation
was developed for all data collectors with written speciﬁcations for inclu-
sion/exclusion criteria and standardized data entry procedures. All data
collection personnel underwent mandatory training sessions before study
initiation. An independent quality control team performed systematic
random audits of collected data to prevent entry errors and ensure con-
sistent application of study criteria. Additionally, standardized review
processes with mandatory dual physician assessment were implemented for
all clinical decisions, with a third independent physician consulted for ﬁnal
adjudication in cases of disagreement. Variables with >30% missing data
were excluded,with remainingmissing valuesimputed using the missForest
algorithm.
Two primary prediction targets were established: (1) Surgical indica-
tors, determined through comprehensive clinical assessment; and (2) Blood
transfusion requirement, deﬁned as administration of >4 units of RBCs
duringsurgeryorwithinoneweekpostoperatively.Allmedicalimagingdata
andexaminationrecordswereindependentlyreviewedandvalidatedbytwo
designated clinical physicians. Predictor variable assessment was performed
by neurosurgical clinicians with associate senior professional titles or above.
The outcome assessors were blinded to patients’ clinical outcomes during
the evaluation process. In cases of disagreement, an independent third
physician was consulted for ﬁnal adjudication.
Model development overview
We developed two sets of machine learning models for predicting sur-
gical indication and transfusion requirements. Each prediction target
utilized four distinct models: Clinical Biomarker Integrative (CBI),
Neural Radiological Imaging (NRI), Clinical Text Mining (CTM), and
Multiomics Data Fusion (MDF) models. A simpliﬁed transfusion pre-
diction model was also developed for emergency settings. Eight ML
algorithms were evaluated using Python’s scikit-learn library (v3.8),
including decision tree (DT), k-nearest neighbors (KNN), light gradient
boosting machine (LGBM), logistic regression (LR), naive Bayes, random
forest (RF), support vector machine (SVM), and eXtreme gradient
boosting (XGB).
https://doi.org/10.1038/s41746-025-02072-5
Article
npj Digital Medicine | (2025) 8:693 
16

# Page 17

The study incorporated three main categories of predictor variables:
clinical phenotypic data, radiological imaging data, and medical text data.
Clinicalphenotypicdatacomprisedinitialassessmentparameters(pupillary
response, level of consciousness, age, and sex) and 146 clinical variables
spanning ﬁve categories: baseline characteristics, biochemical test results,
coagulation proﬁles, blood gas analyses, and complete blood counts (Sup-
plementary Table 1). The radiological data consisted of cranial CT scans,
whereas the medical text data included admission diagnoses from clinical
records. These variables were selected on the basis of their clinical relevance,
immediate availability in emergency settings, and support from the litera-
ture (detailed in Supplementary Note 4).
Compliance with reporting guidelines
The development, validation, and reporting of all the models adhered
strictly to the TRIPOD + AI guidelines43. The detailed methodologies and
additional analyses are provided in Supplementary Table 2.
Development and validation of a clinical biomarker integrative
model (CBI model)
The variables were transformed into binary, ordinal, nominal, or discrete
formats based on predeﬁned criteria (Supplementary Table 1). Feature
selection was performed with univariate logistic regression (p < 0.05), fol-
lowed by multivariate validation. Eight machine learning algorithms were
systematically evaluated using Python’s scikit-learn library to determine
optimal performance characteristics.
For model development, Cohort 1 data were stratiﬁed and randomly
divided into training (n = 848, 80%) and validation (n = 212, 20%) sets. The
training set underwent bootstrap resampling (1000 iterations) to assess
model stability. Different testing strategies were implemented for the sur-
gical indicator and transfusion requirement models, with the latter using
merged data from Cohorts 2-4 due to smaller patient numbers (Supple-
mentary Fig. 1).
Development and Validation of a Neural Radiological Imaging
Model (NRI Model)
To minimize cross-center imaging variability, we implemented standar-
dized preprocessing protocols across all participating centers. The CT
images underwent uniform preprocessing procedures including standar-
dized resampling (1×1×1 mm3), consistent window adjustment parameters
(width=100 HU, Level=50 HU), and automated brain segmentation via
PAIR software using identical algorithms across all centers. Our systematic
slice extraction protocolinvolved automatedidentiﬁcation of the maximum
region of interest (ROI) cross-sectional area, followed by standardized
multi-slice extraction at predetermined pixel intervals (-20, -10, -5, 0, 5, 10,
20 pixels) to ensure consistent 2.5D representation across different scanner
types and acquisition protocols. A 2.5D deep transfer learning model was
developed via two stages:
Stage 1-Initial training and reﬁnement: Cohort 1 was divided into
initial training (n = 638, 60%), reﬁnement (n = 210, 20%), and validation
(n = 212, 20%) sets. CT slices at seven symmetric positions (-20, -10, -5, 0, 5,
10, 20 pixels) were used as input channels. Multiple architectures were
evaluated to determine optimal development.
Stage 2-Feature extraction, dimensionality reduction and secondary
training: MobileNet V2 was employed as the feature extractor, with features
reduced to 36 components via PCA and LASSO regression or RFE. These
featuresweresubsequentlyusedforsecondarytrainingonthereﬁnementset
(n = 210) and validated on the validation set (n = 212). Notably, for the
transfusion prediction model, features were re-extracted from the training
set via the pretrained MobileNet V2 obtained from the surgical indicator
prediction model, followed by direct training of machine learning models.
Development and Validation of the Clinical Text Mining Model
(CTM Model)
The automated preprocessing pipeline included Chinese text segmentation
(Jieba
library),
standardized
lemmatization
(KIMI
system),
and
transformation into structured binary features (Supplementary Table 3).
The CTM model automatically extracted 44 distinct features from
admission texts.
The Boruta algorithm was used for feature selection, followed by ML
model construction following the CBI model methods.
Development and Validation of a Multiomics Data Fusion Model
(MDF Model) and Simpliﬁed Version
TheintegratedmodelaggregatedsigniﬁcantfeaturesfromtheCBI,NRI,and
CTM models, with secondary feature selection via LASSO regression. Eight
ML algorithms were evaluated following hyperparameter optimization. The
surgicalindicatormodelusedonlythereﬁnementset(n = 210)fromCohort
1 to prevent data leakage (Supplementary Fig. 1). A simpliﬁed version
incorporated only routine complete blood count parameters, CT imaging
features, and admission text data, following the MDF model methodology.
Model Interpretability
SHAP quantiﬁed feature importance in surgical intervention and blood
transfusion prediction models. Grad-CAM visualization identiﬁed relevant
regions in radiological images. SHAP analysis was omitted for the LR
models because of its inherent interpretability.
Statistical Analysis and Model Evaluation
Continuous variables are presented as medians (IQRs) or means ± SDs
based on distribution, while categorical variables are expressed as numbers
and percentages. Model performance was evaluated using multiple metrics
including AUC-ROC, sensitivity, speciﬁcity, and F1 score, with 95% CIs
calculated via bootstrapping (1000 resamples). Calibration was assessed
using calibration plots and the Hosmer-Lemeshow test, while clinical utility
was evaluated through decision curve analysis. Correlations between pre-
dicted and actual transfusion volumes were assessed using Pearson’s cor-
relation coefﬁcient. P values were adjusted for multiple testing using the
Benjamini-Hochberg method, and model comparisons were performed
using DeLong’s test.
The sample size calculation followed the events per variable principle,
requiring a minimum of 10 events per predictor variable. With 15 candidate
predictorsandananticipated50%eventrate,theminimumrequiredsample
size was 300 patients. Our development cohort (n = 848) substantially
exceeded this requirement, ensuring adequate statistical power for both
development and validation.
Ethics statement
This study received institutional review board approval from all partici-
pating centers. The Research Ethics Committee of the Second Hospital of
Hebei Medical University approved data collection for Cohorts 1 and 4
(2023-R502). Data collection for Cohort 2 was approved by the Research
Ethics Committee of the Seventh Medical Center of PLA General Hospital
(S2023-023-01), while Cohort 3 was approved by the Research Ethics
Committee of the 960th Hospital of the PLA Joint Logistics Support Force
(2023-073). All patient data underwent anonymization and deidentiﬁcation
prior to analysis. The requirement for informed consent was waived due to
the study’s retrospective nature. All procedures adhered to the Declaration
of Helsinki and applicable ethical guidelines for medical research.
Data availability
Two MDF models are available: one for predicting surgical indications
(https://www.xsmartanalysis.com/model/views/?id=171) and the other for
predicting transfusion needs (https://www.xsmartanalysis.com/model/
views/?id=172). These web-based tools allow users to validate our models
or analyze their own data following standardized protocols. The platform
ensures data security through Alibaba Cloud servers and dual backup
mechanisms, with encrypted storage for all uploaded data. The multimodal
models that include clinical phenotypic data, radiological imaging ﬁndings,
and medical text data from multiple centers used in this study are not
publicly available due to patient privacy protection policies. However,
https://doi.org/10.1038/s41746-025-02072-5
Article
npj Digital Medicine | (2025) 8:693 
17

# Page 18

researchers interested in accessing the data for scientiﬁc research purposes
may submit requests to the corresponding author. These requests will be
reviewed within3monthsandsubjecttoapprovalbytheEthicsCommittees
of three participating hospitals: the Second Hospital of Hebei Medical
University, the Seventh Medical Center of PLA General Hospital, and the
960th Hospital of the PLA Joint Logistics Support Force. The Ethics
Committees reserve the right to deny access to the data.
Code availability
The complete source code for model construction and implementation,
including data preprocessing pipelines, model architecture, and evaluation
scripts, is available for download through Baidu Netdisk (https://pan.baidu.
com/s/1bRR3hD4WgwC3lXgr8o8zLw) via the access code jxwk. This code
repository contains detailed documentation and usage instructions to
facilitatereproductionofourresultsand furtherdevelopmentofthe models.
Received: 3 March 2025; Accepted: 7 October 2025;
References
1.
GBD 2016 Traumatic Brain Injury and Spinal Cord Injury Collaborators.
Global, regional, and national burden of traumatic brain injury and spinal
cord injury, 1990-2016: a systematic analysis for the Global Burden of
Disease Study 2016. Lancet Neurol. 18, 56–87 (2019).
2.
Dewan, M. C. et al. Estimating the global incidence of traumatic brain
injury. J. Neurosurg. 130, 1080–1097 (2019).
3.
Helmick, K. M. et al. Traumatic brain injury in the US military:
epidemiology and key clinical and research programs. Brain Imaging
Behav. 9, 358–366 (2015).
4.
Wang, K., Cui, D. & Gao, L. Traumatic brain injury: a review of
characteristics, molecular basis and management. Front. Biosci.
(Landmark Ed. 21, 890–899 (2016).
5.
Ma, Z. et al. Traumatic brain injury in elderly population: a global
systematic review and meta-analysis of in-hospital mortality and risk
factors among 2.22 million individuals. Ageing Res. Rev. 99, 102376
(2024).
6.
Forslund,M.V. etal. Health-relatedqualityof lifetrajectoriesacross10
years after moderate to severe traumatic brain injury in norway. J. Clin.
Med. 10, 157 (2021).
7.
Freire, M. et al. Cellular and molecular pathophysiology of traumatic
brain injury: what have we learned so far. Biology (Basel) 12, 1139
(2023).
8.
Stocchetti, N. & Zanier, E. R. Chronic impact of traumatic brain injury
on outcome and quality of life: a narrative review. Crit. Care (Lond.,
Engl.) 20, 148 (2016).
9.
AlSowaiegh, R. et al. The Emergency Surgery Score is a powerful
predictor of outcomes across multiple surgical specialties: results of a
retrospective nationwide analysis. Surgery 170, 1501–1507 (2021).
10. Buccilli, B. et al. Neuroprotection: surgical approaches in traumatic
brain injury. Surg. Neurol. Int. 15, 23 (2024).
11. Rakhit, S. et al. Management and challenges of severe traumatic brain
injury. Semin. Respir. Crit. Care Med. 42, 127–144 (2021).
12. Turgeon, A. F. et al. Liberal or restrictive transfusion strategy in
patients with traumatic brain injury. N. Engl. J. Med. 391, 722–735
(2024).
13. Taccone, F. S. et al. Restrictive vs liberal transfusion strategy in
patients with acute brain injury: the TRAIN Randomized Clinical Trial.
J. Am. Med. Assoc. 332, 1623–1633 (2024).
14. Lee, S. M. et al. Development and validation of a prediction model for
need for massive transfusion during surgery using intraoperative
hemodynamic monitoring data. JAMA Netw. Open 5, e2246637
(2022).
15. Eloranta, S. & Boman, M. Predictive models for clinical decision
making: Deep dives in practical machine learning. J. Intern. Med. 292,
278–295 (2022).
16. Gauss, T. et al. Pilot deployment of a machine-learning enhanced
prediction of need for hemorrhage resuscitation after trauma - the
ShockMatrix pilot study. BMC Med. Inform. Decis. Mak. 24, 315 (2024).
17. Hadjiiski, L. et al. AAPM task group report 273: recommendations on
best practices for AI and machine learning for computer-aided
diagnosis in medical imaging. Med. Phys. 50, e1–e24 (2023).
18. Yin, A. A. et al. Machine learning models for predicting in-hospital
outcomes after non-surgical treatment among patients with
moderate-to-severe traumatic brain injury. J. Clin. Neurosci. 120,
36–41 (2024).
19. Monteiro, M. et al. Multiclass semantic segmentation and
quantiﬁcation of traumatic brain injury lesions on head CT using deep
learning: an algorithm development and multicentre validation study.
Lancet Digital Health 2, e314–e322 (2020).
20. Pease, M. et al. Outcome prediction in patients with severe traumatic
brain injury using deep learning from head CT scans. Radiology 304,
385–394 (2022).
21. Czeiter, E. et al. Blood biomarkers on admission in acute traumatic
brain injury: Relations to severity, CT ﬁndings and care path in the
CENTER-TBI study. EBioMedicine 56, 102785 (2020).
22. Richter, S. et al. Prognostic value of serum biomarkers in patients with
moderate-severe traumatic brain injury, differentiated by marshall
computer tomography classiﬁcation. J. Neurotrauma 40, 2297–2310
(2023).
23. Richter, S. et al. Predicting recovery in patients with mild traumatic
brain injury and a normal CT using serum biomarkers and diffusion
tensor imaging (CENTER-TBI): an observational cohort study.
EClinicalMedicine 75, 102751 (2024).
24. Siqueira Pinto, M. et al. Use of support vector machines approach via
ComBat harmonized diffusion tensor imaging for the diagnosis and
prognosis of mild traumatic brain injury: a CENTER-TBI study. J.
Neurotrauma 40, 1317–1338 (2023).
25. Chu, J., Dong, W., Wang, J., He, K. & Huang, Z. Treatment effect
prediction with adversarial deep learning using electronic health
records. BMC Med. Inform. Decis. Mak. 20, 139 (2020).
26. Pham, T., Tran, T., Phung, D. & Venkatesh, S. Predicting healthcare
trajectories from medical records: a deep learning approach. J.
Biomed. Inform. 69, 218–229 (2017).
27. Rajkomar, A. etal. Scalableandaccuratedeeplearningwithelectronic
health records. NPJ Digit. Med. 1, 18 (2018).
28. Habibzadeh, A. et al. Machine learning-based models to predict the
need for neurosurgical intervention after moderate traumatic brain
injury. Health Sci. Rep. 6, e1666 (2023).
29. Moyer, J. D. et al. Machine learning-based prediction of emergency
neurosurgery within 24 h after moderate to severe traumatic brain
injury. World J. Emerg. Surg. 17, 42 (2022).
30. Gelderblom, M. E., Stevens, K., Houterman, S., Weyers, S. & Schoot,
B.C. Prediction modelsin gynaecology: transparent reportingneeded
for clinical application. Eur. J. Obstet. Gynecol. Reprod. Biol. 265,
190–202 (2021).
31. Groot, O. Q. et al. Availability and reporting quality of external validations
of machine-learning prediction models with orthopedic surgical
outcomes: a systematic review. Acta Orthop. 92, 385–393 (2021).
32. Papadomanolakis-Pakis, N. et al. Prognostic clinical prediction
models for acute post-surgical pain in adults: a systematic review.
Anaesthesia 79, 1335–1347 (2024).
33. Warman, A., Kalluri, A. L. & Azad, T. D. Machine learning predictive
models in neurosurgery: an appraisal based on the TRIPOD
guidelines. Systematic review. Neurosurg. Focus 54, E8 (2023).
34. Yang, L. et al. Reporting of coronavirus disease 2019 prognostic models:
the transparent reporting of a multivariable prediction model for individual
prognosis or diagnosis statement. Ann. Transl. Med. 9, 421 (2021).
35. Boehm, K. M., Khosravi, P., Vanguri, R., Gao, J. & Shah, S. P.
Harnessing multimodal data integration to advance precision
oncology. Nat. Rev. Cancer 22, 114–126 (2022).
https://doi.org/10.1038/s41746-025-02072-5
Article
npj Digital Medicine | (2025) 8:693 
18

# Page 19

36. Lobato-Delgado, B., Priego-Torres, B. & Sanchez-Morillo, D.
Combining molecular, imaging, and clinical data analysis for
predicting cancer prognosis. Cancers (Basel) 14, 3215 (2022).
37. Zhou, K. et al. Integration of multimodal data from disparate sources
for identifying disease subtypes. Biology (Basel) 11, 360 (2022).
38. Petch, J., Di, S. & Nelson, W. Opening the Black Box: the promise and
limitations of explainable machine learning in cardiology. Can. J.
Cardiol. 38, 204–213 (2022).
39. Rudin, C. Stop explaining black box machine learning models for high
stakes decisions and use interpretable models instead. Nat. Mach.
Intell. 1, 206–215 (2019).
40. Cole, E. et al. A decade of damage control resuscitation: new
transfusion practice, new survivors, new directions. Ann. Surg. 273,
1215–1220 (2021).
41. Dorken-Gallastegi, A. et al. Whole blood and blood component
resuscitation in trauma: interaction and association with mortality.
Ann. Surg. 280, 1014–1020 (2024).
42. Gauss, T. et al. Comparison of machine learning and human
prediction to identify trauma patients in need of hemorrhage control
resuscitation (ShockMatrix study): a prospective observational study.
Lancet Reg. Health Eur. 55, 101340 (2025).
43. Collins, G. S. et al. TRIPOD+AI statement: updated guidance for
reporting clinical prediction models that use regression or machine
learning methods. Br. Med. J. (Clin. Res. Ed.) 385, e078378 (2024).
44. Berkhout, W. et al. Operationalization of Artiﬁcial Intelligence
Applications in the Intensive Care Unit: a systematic review. JAMA
Netw. Open 8, e2522866 (2025).
45. McNett, M. A review of the predictive ability of Glasgow Coma Scale
scores in head-injured patients. J. Neurosci. Nurs. 39, 68–75 (2007).
46. Tude Melo, J. R. et al. Criteria for neurosurgical treatment of children
andadolescents withtraumatic braininjuryin a Brazilianlevel1 trauma
center. J. Neurosurg. Pediatr. 35, 72–78 (2025).
47. Kalyvas, A. et al. A systematic review of surgical treatments of
idiopathic intracranial hypertension (IIH). Neurosurg. Rev. 44,
773–792 (2021).
48. Sahuquillo, J. & Dennis, J. A. Decompressive craniectomy for the
treatment of high intracranial pressure in closed traumatic brain injury.
Cochrane Database Syst. Rev. 12, CD003983 (2019).
49. Zhang, D., Sheng, Y., Wang, C., Chen, W. & Shi, X. Global traumatic
brain injury intracranial pressure: from monitoring to surgical decision.
Front. Neurol. 15, 1423329 (2024).
50. Barthélemy, E. J., Melis, M., Gordon, E., Ullman, J. S. & Germano, I. M.
Decompressive craniectomy for severe traumatic brain injury: a
systematic review. World Neurosurg. 88, 411–420 (2016).
51. Lee, K. S. et al. Surgical decision making for the elderly patients in
severe head injuries. J. Korean Neurosurg. Soc. 55, 195–199
(2014).
52. Pilitsis,J. etal. Outcomesinoctogenarians with subduralhematomas.
Clin. Neurol. Neurosurg. 115, 1429–1432 (2013).
53. Unterhofer, C., Ho, W. M., Wittlinger, K., Thomé, C. & Ortler, M. “I am
not afraid of death”—a survey on preferences concerning
neurosurgical interventions among patients over 75 years. Acta
Neurochir. (Wien.) 159, 1547–1552 (2017).
54. Rossaint, R. et al. The European guideline on management of major
bleeding and coagulopathy following trauma: sixth edition. Crit. Care
(Lond., Engl.) 27, 80 (2023).
55. Fu, Y. Q., Bai, K. & Liu, C. J. The impact of admission serum lactate on
children with moderate to severe traumatic brain injury. PLoS ONE 14,
e0222591 (2019).
56. Lekomtseva, Y. Targeting higher levels of lactate in the post-injury
period following traumatic brain injury. Clin. Neurol. Neurosurg. 196,
106050 (2020).
57. Wang, R., He, M., Qu, F., Zhang, J. & Xu, J. Lactate albumin ratio is
associated with mortality in patients with moderate to severe
traumatic brain injury. Front. Neurol. 13, 662385 (2022).
58. Li, M. et al. Enhancing automatic prediction of clinically signiﬁcant
prostate cancer with deep transfer learning 2.5-dimensional
segmentation on bi-parametric magnetic resonance imaging (bp-
MRI). Quant. Imaging Med. Surg. 14, 4893–4902 (2024).
59. Ottesen, J. A. et al. 2.5D and 3D segmentation of brain metastases
with deep learning on multinational MRI data. Front. Neuroinform. 16,
1056068 (2022).
60. Zeng, Y. et al. A 2.5D deep learning-based method for drowning
diagnosis using post-mortem computed tomography. IEEE J.
Biomed. Health Inf. 27, 1026–1035 (2023).
61. Yeo, M. et al. Evaluation of techniques to improve a deep learning
algorithm for the automatic detection of intracranial haemorrhage on
CT head imaging. Eur. Radiol. Exp. 7, 17 (2023).
62. Liu, H. et al. Use of BERT (Bidirectional Encoder Representations from
Transformers)-Based Deep Learning Method for Extracting
Evidences in Chinese Radiology Reports: development of a
computer-aided liver cancer diagnosis framework. J. Med. Internet
Res. 23, e19689 (2021).
63. Vakil, M. T. & Singh, A. K. A review of penetrating brain trauma:
epidemiology, pathophysiology, imaging assessment,
complications, and treatment. Emerg. Radiol. 24, 301–309 (2017).
64. O’Phelan, K. H. Not Always a Nail in the Cofﬁn! Brainstem lesions after
traumatic brain injury. Neurocrit. Care 35, 306–307 (2021).
65. Williams, J. R. et al. Prognostic value of hemorrhagic brainstem injury
on early computed tomography: a TRACK-TBI study. Neurocrit. Care
35, 335–346 (2021).
66. Maslonka, M. A., Sheehan, K. N., Datar, S. V., Vachharajani, V. &
Namen, A. Pathophysiology and management of neurogenic
pulmonary edema in patients with acute severe brain injury. South.
Med. J. 115, 784–789 (2022).
67. Khalili, H. et al. Prognosis prediction in traumatic brain injury patients
using machine learning algorithms. Sci. Rep. 13, 960 (2023).
68. Carson,J. L. et al. Red blood cell transfusion: 2023 AABB International
Guidelines. J. Am. Med. Assoc. 330, 1892–1902 (2023).
Acknowledgements
This work was supported by the National Natural Science Foundation of
China Youth Project (82200738).
Author contributions
J.D., T.D., Y.Z. and N.Z. conceptualized the study; performed data curation,
formal analysis, investigation, and methodology development; and wrote
the original draft. K.L., C.W., Z.Z. and J.M. contributed to software
development, data validation, and visualization. Ha.W., L.L., and P.M.
provided supervision, project administration, and critical revision of the
manuscript. Y.Z., T.W., X.H., and J.D. veriﬁed the underlying data and were
responsible for the overall direction of the project. All the authors read and
approved the ﬁnal version of the manuscript.
Competing interests
The authors declare no competing interests.
Additional information
Supplementary information The online version contains
supplementary material available at
https://doi.org/10.1038/s41746-025-02072-5.
Correspondence and requests for materials should be addressed to
Jiang Deng, Xiang-Yan Huang, Tao Wu or Yan-Yu Zhang.
Reprints and permissions information is available at
http://www.nature.com/reprints
Publisher’s note Springer Nature remains neutral with regard to
jurisdictional claims in published maps and institutional afﬁliations.
https://doi.org/10.1038/s41746-025-02072-5
Article
npj Digital Medicine | (2025) 8:693 
19

# Page 20

Open Access This article is licensed under a Creative Commons
Attribution-NonCommercial-NoDerivatives 4.0 International License,
which permits any non-commercial use, sharing, distribution and
reproduction in any medium or format, as long as you give appropriate
credit to the original author(s) and the source, provide a link to the Creative
Commons licence, and indicate if you modiﬁed the licensed material. You
do not have permission under this licence to share adapted material
derived from this article or parts of it. The images or other third party
material in this article are included in the article’s Creative Commons
licence, unless indicated otherwise in a credit line to the material. If material
isnot includedin thearticle’s CreativeCommons licenceandyour intended
use is not permitted by statutory regulation or exceeds the permitted use,
you will need to obtain permission directly from the copyright holder. To
view a copy of this licence, visit http://creativecommons.org/licenses/by-
nc-nd/4.0/.
© The Author(s) 2025
https://doi.org/10.1038/s41746-025-02072-5
Article
npj Digital Medicine | (2025) 8:693 
20
