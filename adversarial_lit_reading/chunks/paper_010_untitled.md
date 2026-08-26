# Page 1

Article
https://doi.org/10.1038/s41467-025-58819-x
Health octo tool matches personalized
health with rate of aging
Sh Salimi1
, A. Vehtari
2, M. Salive
3, M. Kaeberlein
4, D. Raftery
5 &
L. Ferrucci
6
Medical practice mainly addresses single diseases, neglecting multimorbidity
as a heterogeneous health decline across organ systems. Aging is a multi-
dimensional process and cannot be captured by a single metric. Therefore, we
assessed global health in longitudinal studies, BLSA (n = 907), InCHIANTI
(n = 986), and NHANES (n = 40,790), by examining disease severities in 13
bodily systems, generating the Body Organ Disease Number (BODN), reﬂect-
ing progressive system morbidities. We used Bayesian ordinal models,
regressing BODN over organ speciﬁc and all organs disease severities to obtain
Body System-Speciﬁc Clocks and the Body Clock, respectively. The Body Clock
is BODN weighted by the posterior coefﬁcient of diseases for each individual. It
supersedes the frailty index, predicting disability, geriatric syndrome, SPPB,
and mortality with ≥90% accuracy. The Health Octo Tool, derived from Bodily
System-Speciﬁc Clocks, the Body Clock and Clocks that incorporate walking
speed and disability and their aging rates, captures multidimensional aging
heterogeneity across organs and individuals.
Current medical practice focuses primarily on the diagnosis and cure
of single diseases and only rarely considers comorbidities, even for
diseases that are highly prevalent in the population such as diabetes
and hypertension. This focus on speciﬁc diseases may overlook the
broader implications of multimorbidity on global health in older
adults, where the coexistence of two or more diseases is not only
highly prevalent but also an indicator of higher disease susceptibility
due to entropic molecular and cellular damage not adequately coun-
teracted by mechanisms of allostatic resilience1–3. Recently, it has been
proposed that biological aging is the root cause of age-associated
pathologies across multiple body systems, functional decline, and
disability, through the accumulation of damage that surpasses the
body’s resilience and homeostatic mechanisms, leading to declining
health and emerging clinically as multimorbidity4,5. Accordingly, mul-
timorbidity, a strong clinical risk factor for disability and mortality6, is
often associated with polypharmacy and iatrogenesis and imposes
signiﬁcant burdens on individuals and society7.
Despite the importance of multimorbidity and the growing evi-
dence that it is not merely the sum of single diseases, there are cur-
rently no widely acknowledged measures of multimorbidity that fully
account for its complexity and the connection between the rate of
aging and the rising susceptibility to chronic diseases development.
Guidelines for the clinical management of multimorbidity in older
patients have only recently appeared in the literature8,9. However,
diagnostic tools proposed in the literature focus on the number of
chronic diseases7,10; the proportional number of deﬁcits over the total
number of measured deﬁcits, as in the Frailty Index (FI)11–16; or com-
ponents of FI to predict mortality using Machine Learning17,18. Other
authors have proposed weighting the contribution of speciﬁc diseases
based upon their impact on functional status19,20 or mortality21,22. These
tools overlook the possibility that combinations of chronic diseases or
deﬁcits can potentially be heterogeneous, and that organ system
health can differentially impact whole-body health entropy and func-
tional
and
disability
status
in
different
individuals.
Current
Received: 26 February 2021
Accepted: 3 April 2025
Check for updates
1Department of Anesthesiology and Pain Medicine, University of Washington, Seattle, WA, USA. 2Department of Computer Science, Aalto University,
Aalto, Finland. 3Division of Geriatrics and Clinical Gerontology, National Institute on Aging, Bethesda, MD, USA. 4Optispan Inc, Seattle, WA, USA. 5Department
of Anesthesiology and Pain Medicine, University of Washington, Northwest Metabolomics Research Center, Seattle, WA, USA. 6Intramural Research Program,
National Institute on Aging, Baltimore, MD, USA.
e-mail: ssalimi2@uw.edu
Nature Communications|  (2025) 16:4007 
1
1234567890():,;
1234567890():,;

# Page 2

approaches, for example, may underestimate the health burden in
patients with one very severe disease or fail to recognize that indivi-
duals with multiple diseases can still maintain functional resilience or
live long, autonomous lives. In fact, there is evidence that consistent
dynamic compensatory mechanisms might counteract a speciﬁc organ
system’s dysfunction, while global physical and cognitive functions
remain preserved despite the severity of a single system’s deﬁcit19,23.
Therefore, focusing only on late-life outcomes for reference might
skew the metric toward older chronological ages and underestimate
the cumulative effect of health decline that has already occurred at an
earlier stage22,24,25. In addition, indices developed to predict mortality
are prone to validity issues as incidence rates and causes of mortality
have varied over the decades and are likely to vary in the future21.
Moreover, there is currently no metricthat captures the rate of aging in
terms of multimorbidity components. In light of these limitations, the
development of novel metrics that account for early-onset diseases/
deﬁcits, their severity, and the complexity of multimorbidity inter-
preted as entropic ﬂuctuations of health independent of chronological
age would be highly desirable26,27.
To address this challenge, we ﬁrst developed the Body Organ
Disease Number (BODN) as the number of organ systems with at least
one deviation from health due to disease or impairment. Because
organ systems function as interconnected entities rather than inde-
pendent units, their progression value can be considered as a latent
continuous process from one system to another. Given this situation,
we conceptualized BODN in the statistical models as a progressive
ordinal metric in a Bayesian framework and postulated unequal
intervals between its successive values. This approach provides an
unequally spaced ordinal scale, where varying severities of diseases or
disease stages can contribute ﬂexibly to these unevenly distributed
values. The predicted values of such models when focused on organ-
speciﬁc diseases are called Bodily System-Speciﬁc Clocks (BSCs) and
when combined to include all organ systems’ disease levels produce a
health entropy that we call the Body Clock. Therefore, the Body Clock
is a more nuanced metric than BODN and is operationalized from each
disease-weighted contribution into BODN for each person over time
without including chronological age.
Bodily system health entropy can variably affect functional out-
comes such as walking speed, as well as physical and cognitive dis-
ability. Therefore, the Body Clock subsequently informed additional
tools to assess walking speed (the Speed-Body Clock) and a new Dis-
ability Index (Disability-Body Clock). To capture the rate of aging in
terms of multidimensional health, we regressed chronological age on
each set of clocks. Together, these eight metrics form the Health Octo
Tool (Fig. 1), which provides multidimensional health assessment and
aging rates which can operate independently of chronological age. By
incorporating early disease states and assessing the impact of system
entropy on functional outcomes, the Health Octo Tool offers a robust
framework for understanding and tracking multidimensional pathol-
ogies and heterogeneity of aging across lifespan, supporting the eva-
luation of interventions aimed at improving healthy aging at both the
population and individual levels.
Results
Within each organ system, we deﬁned disease states, and their seve-
rities based on accepted medically pre-deﬁned disease criteria
(Table S1), using combinations of medical history, medical laboratory
and physical examinations. The related health questions are listed in
the Table S2, and the disease deﬁnitions and their levels are also
summarized in Table S1. The organ systems considered were cardio-
vascular (CV), renal (Re), metabolic (Me), gastrointestinal and liver
(GL), respiratory (Res), Thyroid (Th), hematopoietic (He), oral health
[i.e., periodontitis (Pe)], musculoskeletal (MS), sensory (Se), and cen-
tral nervous system (CNS).
Body organ disease number (BODN)
BODN was determined as the number of organs with at least one dis-
ease, serving as a new measure of system morbidity. Pathology at the
speciﬁc organ level was established based on predeﬁned disease/
impairment criteria, either deviating from normal or as used for dis-
ease diagnoses in clinical practice (Table S1). For instance, the cardi-
ovascular system encompasses diseases such as hypertension [deﬁned
using systolic and diastolic blood pressure above the cut-points],
ischemic heart disease [clinically deﬁned as developing chest pain
when exercising and other related symptoms identiﬁed on the Elec-
trocardiogram (ECG)], peripheral artery disease (measured by ankle-
brachial index), different arrhythmias (based on ECG), and congestive
heart failure (based on signs and symptoms such as shortness of
breath, low ejection fraction value [<40], and other medical signs and
symptoms), each varying in severity. We considered an organ system
to have morbidity if it exhibited at least one of the organ-speciﬁc
diseases or deviation from normal health (subclinical states in some of
diseases like sub-clinical hypothyroidism). It is important to note that
disease diagnosis in the medical ﬁeld relies on a combination of factors
Fig. 1 | The Health Octo Tool is comprised of eight components designed to
assess multidimensional health. The Clock components of the Health Octo Tool.
Body Organ Disease Number (BODN) quantiﬁes organ systems with at least one
disease, considering diseases across multiple systems. Post hoc analyses of the
organ-speciﬁc diseases predicting BODN yield the Bodily Organ-Speciﬁc Clock
(BSC). Including all organ systems in the Bayesian ordinal regression generates the
Body Clock. The Body Clock impacts walking speed, resulting in the Speed-Body
Clock, and functional and cognitive disability, resulting in the Disability-Body
Clock. System abbreviations: CNS Central Nervous System, St Stroke, CV Cardio-
vascular, Thyr Thyroid, MS Musculoskeletal, He Hematology, Pe Periodontal sys-
tem, Ca Cancer, Se Sensory, GI-Liv Gastrointestinal and Liver system, Me Metabolic
system, Res Respiratory system, Re Renal System. The interactive sunburst graphs
shown at https://bodiagesystem.shinyapps.io/BODN_BLSA/ reveal increases in
multisystem morbidity and BODN values with aging and heterogenous combina-
tions of systems in the BLSA data. Sample size n = 907.
Article
https://doi.org/10.1038/s41467-025-58819-x
Nature Communications|  (2025) 16:4007 
2

# Page 3

including
medical
history,
physical
examination,
organ-speciﬁc
laboratory tests, and ongoing prescribed treatments. The questions
and medical examinations are summarized in Tables S1 and S2.
Therefore, BODN is derived by combining all this clinical information.
The deﬁnition of BODN, reﬂecting progressive system morbidities,
using the 11 organ systems was then extended to include cere-
brovascular accidents (CA), and cancer (Can) (Fig. 1, S1, Tables S1, S2),
because CA involves multiple mechanisms, such as hypertension,
coagulopathy and genetics, and cancers have both shared and distinct
mechanisms across organs. Therefore, we considered them as sepa-
rate system entities from other organ systems.
Since organ systems operate as interconnected parts of a whole,
their pathologies do not occur in isolation but progressively, with
uneven transitions from one to the another, often across different
systems. Considering these transitional states, BODN was considered
as a progressive arithmetic measure, characterized by variable inter-
vals between consecutive values. This design allows for an ordinal scale
with cumulative family28. In Bayesian statistical models, cumulative
family allows cut-points to be introduced to the continuous latent
BODN using probability information from the data, where differing
disease severities or stages contribute to these irregularly spaced cut-
points, enabling quantiﬁcation of variable contributions of disease
severity or levels to its non-equidistant values. We employed the
concepts of ordinal outcome with cumulative family in a Bayesian
framework to model BODN28. Moreover, ordinal numbers were
assigned to the disease levels as covariates of the models, representing
the severity of each organ-speciﬁc pathology, serving as lagged pre-
dictors of BODN (e.g., no hypertension, hypertension with no treat-
ment, and hypertension with treatment would be coded 1, 2, and 3,
respectively; Table S1). A monotonic effect function described in
Bayesian statistics was used to capture the maximum effect of disease
as well as level-speciﬁc effects. This approach allows for detailed and
nuanced quantiﬁcation of disease effects on BODN29.
Health octo tool metrics
Through post hoc analyses using the posterior prediction function, we
derived predicted values of BODN from the models that included
organ-speciﬁc diseases as covariates and created Bodily System-
Speciﬁc Clocks (BSCs). By considering all diseases collectively, we
developed the Body Clock, a measure of health entropy that is obtained
from prediction of the model, where all disease burdens were covari-
ates to predict BODN over time without adding chronological age.
Using Gamma distribution models with a log link function, we regres-
sed chronological age against BSCs and the Body Clock to obtain Bodily
System-Speciﬁc Age and Body Age, as proxies for organ-speciﬁc and
whole-body systems rates of aging, respectively (Table S3). Walking
speed is one of the phenotypes of aging most related to health in older
persons. To understand the effect of whole bodily systems’ health on
walking speed, we estimated the effect of Body Clock on walking speed
and the predicted value is called Speed-Body Clock. Capturing function
and whole system aging heterogeneity, the chronological age was
regressed over Speed-Body Clock to obtain Speed-Body Age.
We developed a Disability Index (DI) by applying the Zero Inﬂated
Beta Binomial (ZIBB) approach in a probability theory framework30
(Formula [S1] and [S2] in the Supplemental Methods), combining
information on physical and cognitive function, falls, and urinary or
bowel incontinence (Table S4). Regressing DI against the Body Clock
allowed us to understand how body health entropy predicts DI and
obtained the Disability-Body Clock from the predictive value of the
model. Regressing chronological age over Disability-Body Clock using
Gamma distribution family, its age estimator is Disability Body Age—a
proxy for the rate of aging that incorporates bodily system health and
disability states. Together, the four sets of clocks and their corre-
sponding rates of aging comprise the Health Octo Tool (Fig.1). The
equations and description of each model are summarized in Table S3.
We performed longitudinal data analyses in the Baltimore Long-
itudinal Study of Aging (BLSA)31,32 and replicated the analyses using the
Invecchiare in Chianti (InCHIANTI) study33. Cumulative multilevel
ordinal regression was employed to estimate the posterior coefﬁcient
values for lagged diseases contributing to BODN28,30,34,35. To manifest
increasing weight of health entropy compared to chronological age,
various models were developed, including those for chronological age,
single diseases, single system diseases, multiple-system diseases, and
global-system entropy, including all systems as co-variates. Model
performance was assessed using leave-one-out cross-validation (LOO-
CV)36, and the model weights were compared with the chronological
age model as a reference using “stacking” in the Bayesian framework to
evaluate model performance37.
Validation assessment using BLSA parameters as a training set
applied to InCHIANTI and NHANES data as test sets
In the Bayesian framework, employing parameters from the training
data (BLSA) and applying them to new data provides out-of-sample
predictive accuracy. The parameters of the BLSA entropy model, ﬁtted
with BLSA data, were tested by making predictions for individuals in
the InCHIANTI study(n = 986, women = 551) and subsequently for
40,700 participants in the National Health and Nutrition Examination
Survey (NHANES) data from 2003 to 201838. We compared the
observed values with the predicted Body Clock using the visualization
function pp_check from the brms package. Additionally, we examined
the relationship between the Body Clock derived from the replicated
analysis of InCHIANTI and the validated version obtained by applying
BLSA data parameters to the InCHIANTI data.
The characteristics of the BLSA study by age group are summar-
ized in Table S5. The schematic representation of BODN systems and
combinations of systems’ morbidities are shown in online interactive
graphs (Body Organ Disease Patterns (shinyapps.io), S1, and S2 (Sup-
plemental Results). The graphs illustrate a wide heterogeneity in sys-
tem combinations within BODN, which increases with age. This pattern
aligns with health entropy, characterized by the random expansion of
health deterioration.
To demonstrate that entropy increases with the addition of dis-
eases and affected systems, we initiated the models with longitudinal
BODN as the ordinal outcome and lagged single diseases as ordinal
covariates (predictors/features). We then sequentially added diseases
within a single organ system (organ-speciﬁc diseases are deﬁned in
Table S1), multi-system diseases, and, ultimately, whole entropy,
incorporating all organ-system diseases as covariates.
Analyses of the BLSA data and then InCHIANTI as replication
revealed signiﬁcant and varied effects of single diseases and organ
system-speciﬁc diseases on the accumulation of system multi-
morbidity, as expressed by the longitudinal BODN (Table S6). Com-
paring the effects of organ system-speciﬁc diseases to those of
individual diseases in the regression models, we found that, in most
cases, single diseases had a greater contribution to BODN than the
aggregated organ systems’ diseases. For example, in the BLSA study,
peripheral artery disease (PAD) contributed to BODN with posterior
estimate [b]=3.43, 95% CI: 2.05–4.8, while the cardiovascular (CV)
system’s contribution was b = 1.21, 95% CI: 0.03–2.46 (Table S6A–B).
Similarly, in the InCHIANTI data, the effect size of PAD as a single
disease was b = 1.56, 95% CI: 1.06–2.06 (Table S6G–H), which was
attenuated within the organ system (b = 0.8, 95% CI: 0.8–1.26)
(Table S6G–H), indicating the link between diseases within the same
organ system and potential shared mechanisms. Separately, we ana-
lyzed the effect of chronological age on BODN, and it emerged as a
robust
predictor
of
BODN
(BLSA,
time-1:
b = 0.20 ± 0.01,
95%
CI = 0.18–0.22; time-2: b = 0.24 ± 0.01, 95% CI = 0.21–0.26; InCHIANTI:
b = 0.14, 95% CI = 0.12–0.14). Comparing model performance weights,
called average model weight stacking (Supplemental Methods), indi-
cated that the model including the chronological age as only predictor,
Article
https://doi.org/10.1038/s41467-025-58819-x
Nature Communications|  (2025) 16:4007 
3

# Page 4

the age-only model, outperformed individual disease or single organ-
system models (Fig. 2A–D; Table S7), highlighting the necessity of
developing models that explain the variability of health entropy with
aging beyond what is explained by a single disease. On the other hand,
these ﬁndings underscore that chronological age still strongly affects
the deterioration of whole body health in a way that cannot be simply
captured by single pathological or physiological measures.
Multiple systems with morbidity outperform chronological age
in predicting longitudinal BODN
Stepwise analyses that included multiple-systems diseases with
increasing entropy to predict longitudinal BODN compared to chron-
ological age alone substantially and signiﬁcantly maximized and
explained higher levels of entropy. This was evident in the superior
model performance (larger ELPD: expected log pointwise predictive
density) and greater model weights compared to chronological age-
only models (Fig. 2E, F, Table S7). The higher ELPD indicates better
predictive performance, as the model is more accurate in predicting
observations. Furthermore, the full models, including all systems,
outperformed chronological age in predicting longitudinal BODN in
both the BLSA and InCHIANTI datasets (Fig. 2E, F, Table 1, Table S7).
This suggests that capturing the health state of all organ systems as a
comprehensive measure, referred to as whole-body entropy, can serve
as a proxy for intrinsic aging.
In the BLSA dataset, incorporating all body disease burdens at
time-2 provided a better prediction of BODN compared to chron-
ological age (Fig. 2F). The full entropy model at time-2 exhibited higher
model weights and ELPD than the time-1 model, indicating that the
predictive power of intrinsic biological age increases with advancing
chronological age (Table 1).
Single Disease, Single System, and Multiple Systems Weights Vs. Age Only Weight Predicting BODN
0
25
50
75
100
Age
Anemia
Arrhythmia
Asthma
Cancer
CHF
CKD
COPD
Dementia
Depression
DM
Eye
GID
Hearing
Hyperlipidemia
Hypertension
Hyperthyroidism
Hypothyroidism
IHD
Liver
Osteoartheritis
Osteoporosis
PAD
Parkinson
Periodont
Stroke
Thrombocytopenia
Weight
Age
Disease
A
0
25
50
75
100
Age
Anemia
Arrhythmia
Asthma
Cancer
CHF
CKD
COPD
Dementia
Depression
DM
Eye
GID
Hearing
Hyperlipidemia
Hypertension
Hyperthyroidism
Hypothyroidism
IHD
Liver
Osteoartheritis
Osteoporosis
PAD
Parkinson
Periodontitis
Stroke
Thrombocytopenia
B
0
25
50
75
100
Age
Cancer
CNS
CVD
DisThyr
GILIV
Hemat
Metabolic
MSK
Periodont
Renal
Resp
Sensory
Stroke
Weight
Age
System
C
0
25
50
75
100
Age
Cancer
CNS
CVA
CVD
DisThyr
GILIV
Hemat
Metabolic
MSK
Periodont
Renal
Resp
Sensory
D
0
25
50
75
100
0
1
2
3
4
5
6
7
8
9
10 11 12 13
Weight
Age
Multisystem
E
0
25
50
75
100
0
1
2
3
4
5
6
7
8
9
10 11 12 13
F
Fig. 2 | Model weight comparisons using average model stacking. Model weights
for single diseases in the BLSA at time 1 (A) and time 2 (B), single systems (C, D), and
multisystem (E, F) are compared to the corresponding age-only model weights. The
data illustrate that the weight of single systems surpasses that of single diseases. As
the number of systems increases, indicating a rise in entropy, the weight of mul-
tisystem models signiﬁcantly surpasses that of chronological age, enabling a more
optimal model for the prediction of longitudinal BODN. Sample size n = 907,
Women = 451. The detailed weights are reported in Table S7.
Article
https://doi.org/10.1038/s41467-025-58819-x
Nature Communications|  (2025) 16:4007 
4

# Page 5

Bodily System-Speciﬁc Clocks (BSC) and Bodily System-Speciﬁc
Ages (BSA)
Given the diverse contribution of different organ systems to the BODN
for each person, our study further explored heterogeneous organ-
speciﬁc intrinsic aging as clocks, when organ-speciﬁc diseases are
predictors of BODN, and rates of aging, when chronological age is
regressed over such clocks. We propose the concept of Bodily System-
Speciﬁc Clocks (BSC) and Bodily System-Speciﬁc Age (BSA) to under-
line the idea that human health is shaped by the entropic accumulation
of damage in cellular structures and functions that act at the overall
body organ system level (entropy that drives the rate of organ system
aging, captured by BSA), as well as predisposition to speciﬁc organ
pathology due to genetic susceptibility or speciﬁc environmental
exposures (captured by BSC). Indeed, examination of correlations
among the 13 organ-system BSAs revealed varying degrees of corre-
lation between each pair of BSA values, indicating disparate aging rates
among organ systems and suggesting that organs do not age syn-
chronously (Fig. S3A, B).
The ordinal cumulative regression model was built using weak
priors (in the Bayesian formula, the posterior coefﬁcient is quantiﬁed
via multiplication of prior knowledge on the coefﬁcient by the like-
lihood of the coefﬁcients, Supplemental Methods). The Bayesian pos-
terior inference model was sampled using a Markov chain Monte Carlo
approach (Supplemental Methods)30. In the BLSA study, BSA of several
systems, including kidney, sensory, cardiovascular, musculoskeletal,
metabolic, stroke, CNS, GI, liver, and thyroid, were consistently older
than chronological age and even exceeded the reported maximum
chronological age (Fig. 3). These results emphasize a biological aging
process at the organ level that extends beyond 125 years, further sug-
gesting that the emergence of pathology in human life results from the
accelerated aging of speciﬁc organ systems. Interventions to delay
aging may focus on reestablishing harmonious aging across different
systems (Fig. 3). Notably, a similar trend emerged in the InCHIANTI
dataset, conﬁrming the replication of this approach (Fig. S3C).
To assess the degree to which each disease level contributes to
BODN, we quantiﬁed posterior coefﬁcient estimates of each disease
level and 95% credible intervals using a monotonic effect in the Baye-
sian approach. The detailed monotonic effect function is described in
the Supplemental Methods29. In both BLSA and InCHIANTI datasets,
collectively including all diseases of organ systems led to a hetero-
geneous and signiﬁcant contribution to BODN. However, for some
organ-system diseases, such as peripheral artery disease, hyperthyr-
oidism, thrombocytopenia, adult-onset asthma, and Parkinson’s dis-
ease, there was substantial uncertainty in the estimate, reﬂected by
wider 95% credible intervals, possibly because the prevalence of these
conditions in the population is relatively low (Fig. 4A, B, Fig. S4 A, B,
Table S6C, S6F, I). Interestingly, milder states of organ system diseases
(e.g., transitional ischemic attack, impaired glucose tolerance, mild
anemia, subclinical hypothyroidism, cataract, mild liver disease, gin-
givitis without edentulous, osteopenia, mild osteoarthritis, and poor
hearing that improves with a hearing aid) had larger estimates con-
tributing to longitudinal BODN compared to more severe states of
these diseases (Figs. 4A, B, S4 A&B, Table S6C, F, I). Similarly, diseases
without pharmacological treatment (e.g., hypertension [HTN], type-2
diabetes mellitus, hyperlipidemia, chronic bronchitis, gastrointestinal
disease, depression, and Parkinson’s) had larger posterior coefﬁcient
estimates for predicting BODN (Fig. S4A, B Table S6). For example,
HTN without treatment was a stronger contributor to BODN (b = 0.32,
95%
CI:
0.23–0.39)
than
HTN
with
treatment
(b = 0.17,
95%
CI:0.13–0.22). Similarly, congestive heart failure with preserved ejec-
tion fraction, a common type of heart failure in older adults, had a
larger posterior coefﬁcient estimate (b = 0.22, 95% CI:0.12–0.23)
compared to the congestive heart failure with a low ejection fraction
(b = 0.09, 95% CI: 0.05–0.13). Arrhythmias, such as sinus bradycardia,
elongated QTc, and atrial ﬁbrillation, also signiﬁcantly affected BODN
(Fig. S4A, B; Table S6C, F, I). Stage-1 age-related chronic kidney disease
(CKD), decoupled from diabetic kidney failure, exhibited stronger
incorporation into BODN (b = 0.53, 95% CI: 0.38–0.71) compared to
stage-2 (b = 0.07, 95% CI:0.05–0.10) and stage-3 CKD (b = 0.1,95%
CI:0.05–0.10), as well as end-stage renal disease (b = 0.20, 95%
CI:0.15–0.28). Similar results were observed in the InCHIANTI study for
stage-1 CKD (Table S6). These patterns were also observed in the time-
2 full model BLSA, where hyperthyroidism and Parkinson’s sig-
niﬁcantly incorporated into BODN (Fig. S4A, B, Table S6). Overall, as
pointed out above, model assessments using LOO-CV approach indi-
cated that full entropy models, incorporating all disease severities,
with larger ELPD (Table 1) had the best performance in predicting
longitudinal BODN (Fig. S5). These ﬁndings suggest that the overall
health assessment of an individual should consider pathology across a
wide range of severities in all organ systems.
Interestingly, there was a slight discrepancy between the BLSA
and InCHIANTI results. In the BLSA, peripheral artery disease (PAD)
showed signiﬁcant incorporation into BODN either as a single disease
or as part of a single-organ system, but its signiﬁcance was not retained
in the full model; while in the InCHIANTI study, PAD retained its sig-
niﬁcance in the full model, albeit with a smaller magnitude (Fig. S4A, B,
Table S6C, F, I). These ﬁndings suggest a potential shared pathophy-
siology among diseases within the cardiovascular system. This con-
clusion was further supported by comparing model weights using
Bayesian Stacking37 (Supplemental Method), which revealed that
Table 1 | Model assessments, model comparisons, and model weights to predict BODN
Model Fits
ELPD
SE
PSIS κ < 0.7
ELPD_DIFF
DIFF_SE
Weights %
BLSA
Time1a
−3926.5
40.5
100.0%
−168.3
24.2
0.0
Time-1 age-only
Time-1 full entropy
−3891.0
−3758.0
40.0
42.3
98.0%
100.0%
−133.2
0.0 (Reference)
25.9
0.0 (Reference)
25.0
75.0
Time2b
−2830.0
33.3
99.9%
−384.7
39.3
0.0
Time-2 age-only
−2751.3
32.6
99.8%
−305.4
29.5
10.0
Time-2 full entropy
−2445.9
38.1
100.0%
0.0 (Reference)
0.0 (Reference)
90.0
InCHIANTI
Time
Time age-only
Full entropy
−5363.2
−5174.2
−4899.6
39.7
39.4
46.4
100%
100%
100%
−463.6
−274.5
Ref
34.5
35.50
0.0
10.0
90.0
ELPD expected log posterior predictive density (the higher the value, the better model is), ELPD-DIFF difference in ELPD values compared the time, the age-only, and full entropy models, SE-DIFF
standard error of the ELDP_DIFF.
aTime from baseline to the end of study.
bTime from the second visit to the end of study.
Article
https://doi.org/10.1038/s41467-025-58819-x
Nature Communications|  (2025) 16:4007 
5

# Page 6

model weights of 49.7%, 48.3%, and 2% for HTN, congestive heart
failure (CHF), and arrhythmia, respectively, while the weights for PAD
and ischemic heart disease (IHD) models were zero, indicating a higher
degree of shared pathophysiology among certain cardiovascular-
related diseases. In the InCHIANTI study, the weights for HTN, CHF,
and arrhythmia were 58%, 41%, and 1%, respectively.
Personalized Body Clock and Body Age
We developed the individualized Body Clock by extracting the pre-
dicted value of BODN from the post hoc analysis of the multilevel
ordinal regression model that included all organ systems diseases and
their severities for each individual. Brieﬂy, the Eqs. (1) and (2) in the
brms R package are as follows, where mo stands for the monotonic
function for the ordinal predictor:
Fit BLSA = ðbodn  moðHypertensionÞ + moðcongestiveHeartFailureÞ
+ moðIschemicHeartDiseaseÞ + moðArrhythmiaÞ + moðKidneyÞ
+ moðDiabetesÞ + moðHyperlipidemiaÞ + PrepheralArteryDisease
+ moðStrokeÞ + moðAnemiaÞ + Thrombocytopnia
+ moðGastrointestinalDiseaseÞ + moðLiverÞ + moðCOPDÞ + Asthma
+ moðOralHealthÞ + moðHypothyroisismÞ + Hyperthyroisism
+ moðOsteoArtheristisÞ + moðOsteoporosisÞ + moðHearingÞ + moðEyeÞ
+ moðDepressionÞ + moðsParkinsonsÞ + moðCognitionÞ + Cancer
+ yrs + ð1 + 1jidÞ, data = BLSAÞ
ð1Þ
Body Clock BLSA = posterior predictðfit BLSA, data = BLSAÞ
The above equation was applied to the InCHIANTI data for repli-
cation, and the predicted model Eq. (2) is:
Body Clock InCHIANTI = posterior predictðfit InCHIANTI, data= InCHIANTIÞ
ð2Þ
Overall, the median Body Clock in the BLSA dataset was 6.1
(range: 2.1–11.5) and for InCHIANTI was 6.6 (range: 2.4–11.1). It is
worth noting that the BLSA enrolls individuals who are very healthy
at baseline, whereas the INCHIANTI dataset is population-based and
primarily includes individuals over the age of 50. In the InCHIANTI
study, women 65 to 85 years old exhibited a higher Body Clock value
than men, with measurements of 7.1 ± 1.1 compared to 6.8 ± 1.2,
respectively. However, in the BLSA study, there were no sex differ-
ences in Body Clock values.
We used the monotonic effect to assess severity-speciﬁc
coefﬁcients and derive the latent maximum disease severity
effects, which form a linear scale from minimum to maximum
effect, to obtain the Body Clock at the individual level (Supple-
mental Methods). Furthermore, individualized trajectory plots for
Body Clock vividly demonstrate diverse trajectories among indi-
viduals of the same chronological age. These trajectories exhibit
varying slopes and magnitudes, underscoring the unique max-
imum
intrinsic
aging
experienced
by
different
individuals
(Fig. S6A, B). Additionally, age was categorized into the following
groups: <45, 45–54, 55–64, 65–74, 75–84, and 85 and older. The
Body Clock increases with each successive 10-year age interval,
Men
Women
30
40
50
60
70
80
90
30
40
50
60
70
80
90
50
60
70
80
90
100
110
120
130
140
Age (Years)
Bodiy System Speciﬁc Age
System
CA
Can
CNS
CV
GL
He
Met
MS
Pe
Re
Res
Se
Th
Bodily System Speciﬁc Age and Chronological Age in the BLSA Data
Fig. 3 | Relationships between bodily system-speciﬁc age (BSA) and chronological age. The graph reveals that BSA for cardiovascular (CV), renal (Re), Res, CNS, and MS
systems can exceed 120, surpassing the maximum reported human chronological age. System abbreviations same as Fig. 1. Sample size n = 907, Women = 451.
Article
https://doi.org/10.1038/s41467-025-58819-x
Nature Communications|  (2025) 16:4007 
6

# Page 7

and its values are heterogeneously distributed within each age
group, as depicted in both the BLSA and InCHIANTI studies
(Fig. S7A, B). These ﬁndings emphasize the diversity of the aging
process. Subsequently, the chronological age was regressed over
the Body Clock using a Gamma distribution family and a log link
function, allowing the ﬁtting of non-linear, exponential points
into the models (equations [3] and [4]).
FitAge = Chronological Age  Body Clock, data = BLSA,
ð3Þ
Body Age = posterio predictðFitAgeÞ
ð4Þ
CV
CA
Re
Me
GL
Res
Th
He
MS
Pe
Se
CNS
Can
CV
CA
Re
Me
GL
Res
Th
He
MS
Pe
Se
CNS
Can
−1.25
−0.25
0.75
1.75
2.75
HTN
IHD
CHF
Arr
PAD
Stroke
CKD
DM
Lipid
Liver
GID
COPD
Asthma
Hypoth
Hyperth
Anemia
Thromb
OA
Osteop
Periodon
Hearing
Eye
Dep
Park
CI
Cancer
−1.25
−0.25
0.75
1.75
2.75
HTN
IHD
CHF
Arr
PAD
Stroke
CKD
DM
Lipid
Liver
GID
COPD
Asthma
Hypoth
Hyperth
Anemia
Thromb
OA
Osteop
Periodon
Hearing
Eye
Depression
Parkinson
CI
Cancer
Posterior Estimates, 95% Credible Interval
Posterior Estimates, 95% Credible Interval
Time−1 Multisystems' Diseases Predicting BODN
Time−2 Multisystems' Diseases Predicting BODN
A
B
Fig. 4 | Lagged full-model multisystem posterior estimates predict longitudinal
body organ disease number (BODN). The lagged full-model estimates reveal
heterogenous contributions of diseases into BODN. A Maximum contribution of
diseases into longitudinal BODN at time 1. B Maximum contributions of diseases
into longitudinal BODN at time 2. Larger posterior estimates, accompanied by
narrower 95% credible intervals (CI), yield more accurate predictions. The max-
imum effects of most diseases increase with time. Signiﬁcance is determined when
the 95% CI does not include 0. Disease Abbreviations: HTN hypertension, IHD
ischemic heart disease, CHF congestive heart failure, Arr arrhythmia, PAD periph-
eral artery disease, CKD chronic kidney disease, DM diabetes mellitus, GID gas-
trointestinal disease, COPD chronic obstructive pulmonary disease, Hypoth
hypothyroidism, Hyperth hyperthyroidism, OA osteoarthritis, Osteop osteo-
porosis, Periodon periodontal disease, Dep depression, Park Parkinson’s disease, CI
cognitive impairment. System abbreviations: same as for Fig. 1. For the values of
mean posterior estimates and 95% CI, please see the values in Table S6C, F for full
models. Sample size n = 907, Women = 451.
Article
https://doi.org/10.1038/s41467-025-58819-x
Nature Communications|  (2025) 16:4007 
7

# Page 8

The same formula was applied to the InCHIANTI data.
We obtained the post hoc prediction for each individual using
posterior predict, termed Body Age (Eq. 4, Fig. S7C, D). At the popu-
lation level, given the constant value of 3.78 and the mean posterior
estimate of 0.12 obtained from the Bayesian Gamma distribution
model with BLSA, where chronological age was regressed over Body
Clock, if an individual has a Body Clock value of 9, the Body Age would
be 129 (calculated as e (3.78+0.12×9) = 129.02, e is the natural logarithm).
However, it is crucial to avoid generalizing the population mean pos-
terior estimate, rather Body Age should be quantiﬁed for an individual,
obtained from the prediction model using individual-speciﬁc posterior
estimates, to ensure accurate predictions for precision-medicine
decisions.
Speed-Body Clock and Speed-Body Age
Walking speed serves as a fundamental measure of health commonly
utilized as an important risk factor, biomarker, and outcome at the old
age. Walking speed was recorded (in meters per second) over 6 meters
in the BLSA and 7 meters in the InCHIANTI studies. To assess the
inﬂuence of the Body Clock on walking speed, we predicted long-
itudinal changes of walking speed by the Body Clock, adjusting for
height using a Gaussian regression and modeled the walking speed
variance (sigma) over the Body Clock to develop another health metric
that we called Speed-Body Clock (equation [5] and [6]; Fig. S8 A, B).
Fit BLSA = Walking Speed  Body Clock + height, data = BLSA
ð5Þ
Speed  Body Clock = Postrior predictðFit BLSAÞ
ð6Þ
The same formula was applied to the InCHIANTI study for
replication.
Because of the inverse relationship between the Body Clock and
walking speed, a smaller Speed-Body Clock indicates a negative
impact of system's health on physical function. In the BLSA study, the
Speed-Body Clock was lower in women compared to men, even after
adjustment for height, with values of 1.09 ± 0.1 for women and
1.15 ± 0.1 for men. At the population level, for each unit increase in
the Body Clock, the posterior coefﬁcient of walking speed decreased
by 0.062 m/s (0.065–0.062) in men and 0.064 m/s (0.063–0.061) in
women (Fig. S8A). In the InCHIANTI study, a one-unit increase in
Body Clock corresponded to a decrease in the posterior coefﬁcient
of walking speed by -0.03 m/s in both sexes. Again, women exhibited
a smaller Speed-Body Clock than men, with values of 1.29 ± 0.15 for
women and 1.56 ± 0.14 for men (Fig. S8B). For BLSA, the mean Speed-
Body Clock was signiﬁcantly different between age groups so that
the youngest group (<45 years old) with a 1.26 value had the largest,
and the oldest group with 1.01 value had the smallest Speed-Body
Clock. Similar results were observed in the InCHIANTI study with 1.55
vs. 1.29 values for the youngest and oldest groups, respectively.
These ﬁndings indicate that bodily system health entropy (Body
Clock) can contribute to a decline in walking speed, which accel-
erates after age 65.
Additionally, individuals of the same chronological age may have
different rates of aging in terms of how the Body Clock affects walking
speed. This heterogeneity in the aging rate is captured by regressing
chronological age on the Speed-Body Clock using a Gamma distribu-
tion and the predicted value was denoted as Speed-Body Age (equa-
tion [7] and [8]; Fig. S8 C, D).
Fit BLSA = Age  Spreed  Body Clock + Height, data = BLSA
ð7Þ
Speed  Body Age = psoterior predictðFit BLSAÞ
ð8Þ
The same formula was applied to the InCHIANTI data for
replication.
With a one unit increase in the Speed-Body Clock, the Speed-Body
Age decreases in both BLSA (intercept=5.34, b = −0.99, 95% CI (−1.06 to
−0.95) and InCHIANTI (intercept = 4.8, b = −0.43, 95% CI = −0.48 to
−0.39). That is, using a Gamma distribution interpretation, we pre-
dicted that a Speed-Body Clock of 0.8 resulted in a speed Speed-Body
Age of e(4.8-0.43*0.8) = 86.14 in InCHIANTI and 94.44 in BLSA. The differ-
ence between these estimates may be explained by the healthier
people enrolled in BLSA, while InCHIANTI is a population-based sam-
ple. A larger Speed-Body Age represents resilience to functional or
system function decline and can reﬂect aging heterogeneity. Note that
we relied on individual-based metrics using a Bayesian approach that
can be obtained from prediction models rather than the population
level metrics and thus reduced the chance of bias due to population
variability. In the InCHIANTI study, the Speed-Body Age could extend
up to 105 units, while in the BLSA, the maximum Speed-Body Age did
not surpass 97 units. Despite the smaller average population state
within InCHIANTI, some individuals manifested resilience indicated by
a higher Speed-Body Age. The data revealed increasing heterogeneity
in Speed-Body Age after age 70 as depicted in Fig. S8C, D.
Disability index (DI), Disability-Body Clock, and Disability-
Body Age
To capture late-onset outcomes experienced by individuals, we
devised a new Bayesian DI, in which each individual could have mul-
tiple components of physical and cognitive disability. We incorporated
a total of 47 measured components as the total number of trials in the
DI (Table S4). The components representing these outcomes were
modeled using the Zero Inﬂated Beta Binomial (ZIBB) distribution,
estimating the probability distribution of the number of observed
components (events) given the total number of measured components
(trials) for each individual. This approach allowed for ﬂexible prob-
abilities that could vary from person to person. Moreover, ZIBB han-
dled model instability resulting from zero values in young populations
without age-related disability or in the older adults exhibiting resi-
lience to late-onset outcomes. The detailed ZIBB formula is described
in the Supplemental Methods (equations [S1], [S2], and below, equa-
tions [9] and [10]).
Fit BLSA = probability ofðeventsÞjtrialðtotal eventsÞ  1 + ð1jidÞ, data = BLSA
ð9Þ
Disability Index = posterior predictðFit BLSAÞ
ð10Þ
The same formula was applied to the InCHIANTI data for repli-
cation. This approach enabled us to explore how the Body Clock
predicts the model-based physical and cognitive DI, based on events
within the total 47 measured (trials) components (Table S3).
Not everyone with an elevated Body Clock experiences disability.
This heterogeneous process can be captured using the Disability-Body
Clock (deﬁned as the sum of positive events conditioned on the total
number of measured events and predicted by the Body Clock). This
approach enabled us to explore how the Body Clock predicts the
model-based physical and cognitive DI, based on events within the
total 47 measured components (Table S4; equations [11 and [12]).
FitBLSA = probability of
events
ð
Þ
ð
Þjtrial total events
ð
Þ  Body Clock
+ 1jid
ð
Þ, data = BLSA
ð11Þ
Disability  Body Clock = posterior predict Fit BLSA
ð
Þ
ð12Þ
Article
https://doi.org/10.1038/s41467-025-58819-x
Nature Communications|  (2025) 16:4007 
8

# Page 9

The same formula was applied to the InCHIANTI data for
replication.
In the BLSA data, the median DI was 0.03 (range 0.007–0.71). The
median Disability-Body Clock was 1.2 (range 0.12–9.48) and not dif-
ferent between men and women (women: 1.5 ± 1.04; men: 1.52 ± 1.08)
(Fig. S9.A). In the InCHIANTI study, the median DI was 0.22 (range
0.05–0.95) with a larger mean DI in women (0.3 ± 0.16) than men
(0.22 ± 0.13). The median Disability-Body Clock was 6.3 (range:
1.45–12.8) with a larger mean in women (6.5 ± 1.82) than men
(6.17 ± 1.74) (Fig. S9B). Additionally, individuals of varying ages may
exhibit different effects of the Body Clock on disability. To account for
this heterogeneity in such aging rate, we regressed the chronological
age against the Disability-Body Clock. The predicted value from this
model is referred to as the Disability-Body Age (equations [13] and
[14]).
FitBLSA = Age  Disability  Body Clock, data = BLSA
ð13Þ
Disability  Body Age  posterior predict Fit BLSA
ð
Þ
ð14Þ
The same formula was applied to the InCHIANTI data for
replication.
In the BLSA data, the median Disability-Body Age was 62.71 (range
60.4–135.67) with high heterogeneity after age 60. Moreover, in some
individualsof either sex, the biologicalage surpassed 120 (Fig. 5). In the
InCHIANTI data, the median Disability-Body Age was 67.3 (range
43.5–120.2) with women exhibiting a higher average biological age
compared to men (69.56 ± 11.55 vs. 67.2 ± 10.7) (Fig. S9C).
Body Clock predicts binary short physical performance battery
(SPPB), disability, geriatric syndrome, and mortality
To evaluate the predictive capability of the Body Clock for age-related
late-life binary outcomes, we utilized Multilevel Negative Binomial
Regression models within the Bayesian framework, accounting for
time. We focused on outcomes including SPPB < 9, disability (Activities
of Daily Living scale [ADL] >1 and/or Instrumental Activities of Daily
Living scale [IADL] >1), geriatric syndrome (injurious fall or urinary/
bowel incontinence as dichotomous variables), and mortality. Our
analysis revealed that individuals with higher Body Clock scores had an
elevated
risk
of
SPPB < 9
(BLSA:
hazard
ratio
[HR] = 2.7,
95%
CI = 1.7–10.6; InCHIANTI: HR = 2.0, 95% CI = 1.7–2.3), geriatric syn-
drome (BLSA: HR = 1.6, 95% CI = 1.5–1.7; InCHIANTI: HR = 1.2, 95%
CI = 1.2–1.3), disability (BLSA: HR = 1.7, 95% CI = 1.5–1.8; InCHIANTI:
HR = 1.6,
95%
CI = 1.5–1.7),
and
mortality
(BLSA:
HR = 1.8,
95%
CI = 1.5–2.2; InCHIANTI: HR = 1.5, 95% CI: 1.4–1.6). These ﬁndings indi-
cate that the Body Clock could signiﬁcantly predict age-related late-life
outcomes.
The Body Clock superseded Frailty Index to predict late-onset
binary outcomes. We used the same list of diseases described in
Table S1 to manually develop disease-based FI scores, which is a
common metric used to capture age-related deﬁcits11,39,40. Rather than
considering different levels of disease severity, each condition was
treated as a separate binary variable. For example, in the case of
ischemic heart disease, angina pectoris and acute myocardial infarc-
tion are considered distinct deﬁcits in the FI, whereas the Body Clock
treats them as different levels of the same condition. Similarly, for eye
diseases, the Body Clock treats cataract, glaucoma, and macular
degeneration as varying levels of eye disease, while in the FI, each
condition is treated as a separate binary variable (e.g., having cataracts
vs. no cataract). Overall, the same diseases were considered in both the
FI and Body Clock. The primary difference lies in the methods (Baye-
sian-based Body Clock vs. manually developed FI) used to develop
these health metrics.
It is important to note that while the FI and Body Clock exhibit
strong correlation (r = 0.83, 95% CI: 0.816–0.84), the Body Clock more
effectively captures health heterogeneity, as evidenced by instances
where identical FI values correspond to varying Body Clock values
(Figs. 6, S10A, B). We utilized Receiver Operating Characteristic (ROC)
and Area Under the Curve (AUC) analyses to compare the predictive
performance of the FI and Body Clock for various binary outcomes
including SPPB, geriatric syndrome, disability, and mortality. The AUC
values consistently indicate that the Body Clock provided stronger
predictions for all these outcomes across both the BLSA and
InCHIANTI studies (Figs. 7, S11A).
We used a Bayesian model for the FI and Body Clock to predict
Bayesian DI. To assess DI predictions, we compared the Body Clock’s
performance comparing ELPD, which averages the logarithm of pre-
dictive densities for each data point and serves as a metric for com-
paring models, indicating how effectively they predict observed or new
data points. Higher ELPD values signify better predictive performance
and discern which model offers the most accurate predictions for the
data. Our results demonstrated that the Body Clock exhibited better
model performance compared to FI, with differences in ELPD favoring
the Body Clock, indicated by the larger ELPD with both BLSA and
InCHIANTI data. The ELPD difference presented as negative values in
differences of ELPD (ELPD_DIFF) from the FI and Body Clock models
where the Body Clock with the higher ELPD is the reference model (FI in
BLSA: ELPD_DIFF = −27.9 ± 7.5; FI in InCHIANTI: ELPD_DIFF = −26.6 ± 6).
To gain deeper insights into the relationship between the Body
Clock and SPPB, we explored the association between SPPB < 9 at time-
1 and the Body Clock. This analysis revealed a reciprocal relationship
between lagged functional impairment. With BLSA, we observed that
SPPB < 9 was associated with a higher Body Clock value (b = 1.9, 95%
CI = 1.6–2.4). Similarly, in the InCHIANTI dataset, SPPB < 9 predicted an
increased Body Clock value (b = 2.1, 95% CI = 1.6–2.8). These results
underscore the reciprocal nature of the association between the Body
Clock and SPPB, suggesting when impaired physical performance is
established it can signiﬁcantly contribute to health deterioration as
reﬂected in the Body Clock.
Replication of Body Clock using NHANES data
We applied the same statistical pipeline described for BLSA and
InCHIANTI to predict BODN in 40,700 individuals in the NHANES data,
spanning the years 2003–2018, and derived personalized Body Clocks.
As chronological age increased, the Body Clock demonstrated heigh-
tened heterogeneity after age 60, mirroring the pattern observed in
the BLSA and InCHIANTI studies (Fig. S12A). The distribution of the
BODN number suggests that morbidity in more than 5 organs becomes
dominant after age 50 and older. However, some older adults with low
Body Clock values exhibited bodily system resilience. In the NHANES
data, women exhibited larger Body Clock values than men, suggesting
that in general, women experienced poorer health compared to men.
In addition, in NHANES data, Body Clock outperformed FIs speciﬁcally
in predicting mortality, with an accuracy of 80% (Fig. S13).
The chronological age was then regressed over the Body Clock.
Similar to the BLSA and InCHIANTI data, the Disability-Body Age sur-
passed the reported ceiling in humans (Fig. S12B). The Body Clock
predicted SPPB, disability, geriatric syndrome, and all-cause mortality
(Table 2). Of note, in the NHANES data, there was only a small sample
size for adults older than 85 years and, thus, it is likely that our esti-
mates were affected by information censoring.
Applying the BLSA parameters (training set) to the NHANES and
InCHIANTI data (validation sets) to develop the Body Clock
Using out-of-data input, the validation is the same concept as applying
training data parameters (BLSA model) to a new data (InCHIANTI or
NHANES) as test sets to obtain the Body Clock. We used the BLSA full
entropy model to predict out-of-data input in the NHANES and the
Article
https://doi.org/10.1038/s41467-025-58819-x
Nature Communications|  (2025) 16:4007 
9

# Page 10

Fig. 5 | Disability-body age and chronological age in BLSA datasets. Disability-Body Age surpasses the reported chronological age in humans. There is increasing
heterogeneity in Disability-Body Age with increases in chronological age. Sample size n = 907, Women=451.
0.00
0.05
0.10
0.15
0.20
0.25
0.30
0.35
0.40
0.45
0.50
0.55
0.60
0.65
1
2
3
4
5
6
7
8
9
10
11
12
Body Clock
Frailty Index
Frailty Index and Body Clock in BLSA Data
Fig. 6 | High correlation between the Body Clock and disease-based frailty
index (FI) with BLSA (r = 0.83, 95% CI: 0.816–0.84). Body Clock also captures
heterogeneity better than FI: for heterogeneous values of the Body Clock—serving
as a proxy for the intrinsic age and health entropy—FI values remain largely
unchanged. Sample size n = 907, Women = 451.
Article
https://doi.org/10.1038/s41467-025-58819-x
Nature Communications|  (2025) 16:4007 
10

# Page 11

InCHIANTI data (test sets). The predicted and observed values in both
studies were matched as depicted using posterior predicted check in
the Bayesian framework (Fig. S14 A, B).
FitBLSA = BODN  mo Disease1
ð
Þ  + mo DiseasesN
ð
Þ + time + 1jid
ð
Þ, data = BLSA
ð15Þ
Predict in InCHIANTIðtest setÞ = posterior predictðFit BLSA, data = INCHIANTIÞ
ð16Þ
Predict in NHANESðtest setÞ = posterior predictðFit BLSA, data = NHANESÞ
ð17Þ
There is a strong correlation between the Body Clock derived
directly from the analysis of the InCHIANTI dataset (as a replication)
and the Body Clock obtained by applying the BLSA parameters to the
InCHIANTI dataset (as a validation test set) (Fig. 8). These results
suggest that a valid model can be used to estimate the Body Clock in
new data as a test set.
Discussion
Using Bayesian inference on longitudinal data containing well-deﬁned
comprehensive clinical information, we developed and validated a
personalized health tool that aligns multidimensional health with
accelerated aging. Considering multimorbidity as a comprehensive
measure of organ system health, we introduced the concept of BODN.
Predicting SPBB
1 - Speciﬁcity
Sensitivity
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
Body Clock
Disease-based FI
AUC (Body Clock) = 1
AUC (Disease-based FI) = 0.8
Predicting Geriatric Syndrome
1 - Speciﬁcity
Sensitivity
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
Body Clock
Disease-based FI
AUC (Body Clock) = 0.96
AUC (Disease-based FI) = 0.75
Predicting Disability
1 - Speciﬁcity
Sensitivity
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
Body Clock
Disease-based FI
AUC (Body Clock) = 0.97
AUC (Disease-based FI) = 0.74
Predicting Death
1 - Speciﬁcity
Sensitivity
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
Body Clock
Disease-based FI
AUC (Body Clock) = 0.9
AUC (Disease-based FI) = 0.73
Fig. 7 | Receiver operating characteristic (ROC) and area under the curve (AUC) of the Body Clock and FI score predict binary outcomes in the BLSA data. The Body
Clock predicts binary SPPB < 9, geriatric syndrome, and disability, superseding the FI score with more than 90% accuracy. Sample size n = 907, Women=451.
Article
https://doi.org/10.1038/s41467-025-58819-x
Nature Communications|  (2025) 16:4007 
11

# Page 12

The random and wide combinations of systems in the BODN represent
the random expansion of health deterioration representing health
entropy. We quantiﬁed the contribution of each disease severity over
time using Bayesian models. Notably, we showed sub-clinical pathol-
ogies, such as sub-clinical hypothyroidism or mild kidney function
decline, can signiﬁcantly contribute to health entropy. One inter-
pretation is that mild disease is part of the aging process while greater
severity could be related to a speciﬁc organ system’s susceptibility,
from genetics as well as behavioral and environmental factors, that
accelerate consumption of allostatic responses. We developed system-
based clocks (BSCs) and their corresponding rates of aging (BSAs),
demonstrating that organs age heterogeneously and can exhibit dif-
ferent biological ages, even at the same chronological age.
There are some population-based discrepancies in biological
organ age, underscoring the diverse nature of the aging process across
organ systems in different environments, which also can be potentially
inﬂuenced by different genetics and behavioral factors41. This ﬁnding
emphasizes the necessity of using individualized health metrics.
Including all disease burdens that contribute to BODN, we
developed the Body Clock as a weighted BODN. This entropy model
exhibits better prediction of BODN compared to age-only, single dis-
ease, or single-system models manifesting increasing health entropy
burden. While chronological age remained a signiﬁcant predictor of
BODN, integrated disease levels of body organ systems surpass
chronological age in predicting future BODN, revealing multi-
morbidity as a clinical manifestation of the intrinsic rate of aging that
would otherwise remain concealed when focusing solely on individual
diseases or organ systems. These ﬁndings strongly support the idea
that as we age, chronological age becomes a weaker predictor of global
bodily health. Instead, the emergence of pathologies, particularly
multiple sub-clinical or mild impairments, becomes a more effective
metric for measuring the rate of aging. In this framework, we were able
to predict individual-based BODN and quantify the Body Clock as a
measure of intrinsic biological aging independent of chronological
age. The Body Clock serves as a strong predictor of late binary out-
comes and supersedes the FI for predicting disability, geriatric syn-
drome, functional decline, and mortality. Moreover, as an individual-
based measure of damage accumulation, the Body Clock enables the
differentiation of biomarkers between those indicating accumulation
of damage and those indicating resilience at the organ and whole-body
levels. Regressing chronological age over the Body Clock, we deter-
mined the rate of aging in the whole-body systems; in another word,
we obtained the rate of aging in terms of health entropy, which we call
Body Age. We used the Body Clock to predict walking speed, a pow-
erful functional phenotype in older adults. The Speed-Body Clock
represents the effect of the whole bodily systems health entropy on
functional health, while Speed-Body Age quantiﬁes the rate of aging in
terms of the impact of the whole-body systems on functional health.
Speed-Body Clock can potentially differentiate individuals with
resilience to functional decline, despite increases in the Body Clock,
from those with poor function. Such a metric can be used to study
resilience or assess responses to multidimensional health interven-
tions. We also devised a new approach to disability called the Bayesian
DI that captures both cognitive and physical disability using a Bayesian
model that accounts for model uncertainty due to the number of zero
values. Similarly, we used the Body Clock to predict DI, deriving pre-
dicted values as the Disability-Body Clock and its rate of aging, termed
the Disability-Body Age, to reﬂect the impact of the whole-body sys-
tems’ health entropy on combined functional and cognitive disability.
Such metrics allow us to understand why some individuals age with
better health and free of disability while some present accelerated
disability with or without increases in the Body Clock.
Of the known multimorbidity indices, the Charlson Index42 and
the Cumulative Illness Rating Scale for Geriatrics (CIRS-G) are widely
used as hospital-based multimorbidity indices43. The Charlson Index
incorporates disease weights based on 1-year mortality hazard ratios
and age categories, but it may introduce bias due to selective mortality
and lack of consideration for early-onset changes in health. In contrast,
the Body Clock is decoupled from chronological age and reﬂects
progressive health impairments at any age, independent of mortality.
The CIRS-G assesses acute and chronic disease burdens and disability
but may skew severity scores towards acute conditions or late-onset
outcomes, potentially underestimating chronic diseases at younger
ages. As we show, the Body Clock can be employed to predict late-life
outcomes at any age, offering potential beneﬁts in clinical settings and
for preventive strategies.
The FI is also commonly used to measure deﬁcits and aging in
geriatric research11,44 and has repeatedly been shown to predict mor-
tality and a number of other health outcomes17,24,25. Notably, increases
in the prevalence of frailty with decreases or no change in mortality
have been shown, suggesting the necessity of understanding and
preventing frailty45. We believe that there are conceptual similarities in
our approach and the frailty paradigm, mainly that aging implies a
progressive accumulation of entropic damage, with the Body Clock
capturing heterogeneous health states and more strongly predicting
late-onset outcomes. Some FIs include components of late-onset
outcomes and also assign equal weight to all deﬁcits, disregarding
their varying magnitudes of effects on the body. Including late-onset
deﬁcits as components of disability tends to bias FI towards older age
groups, resulting in an underestimation of early-onset aging. There-
fore, in our study, to compare the FI with the Body Clock we con-
sistently used the same diseases in both algorithms. Moreover, FI may
not adequately consider the heterogeneity of disease impacts on the
body and suffers from model instability and variability in the compo-
sitions of the components, affecting its reliability46. We demonstrated
a strong correlation between the Body Clock and FI; nevertheless, FI
lacks sensitivity to heterogeneity in the aging process. The metho-
dology used to develop the Body Clock incorporates prior knowledge
Table 2 | Body Clock predicts binary health outcomes in NHANES data over 16 years
NHANES
SPPB category
HR (95% CI)
Urinary Incontinence
Disability
Mortality
2003–2004
1.67 (1.60–1.70)
1.05 (1.02–1.08)
1.90 (1.84–1.95)
1.60 (1.45–1.77)
2005–2006
1.71 (1.65–1.79)
1.09 (1.06–1.14)
1.86 (1.79–1.93)
1.57 (1.40–1.77)
2007–2008
1.67 (1.60–1.72)
1.12 (1.09–1.15)
1.68 (1.65–1.72)
1.55 (1.45–1.68)
2009–2010
1.68 (1.63–1.75)
1.12 (1.08–1.14)
1.90 (1.84–1.93)
1.67 (1.52–1.84)
2011–2012
1.77 (1.70–1.86)
1.09 (1.06–1.12)
1.78 (1.72–1.82)
1.61 (1.48–1.75)
2013–2014
1.77 (1.70–1.82)
1.17 (1.15–1.21)
1.95 (1.90–2.01)
1.70 (1.52–1.77)
2015–2016
1.82 (1.77–1.90)
1.14 (1.1–1.17)
1.97 (1.92–2.03)
1.62 (1.49–1.77)
2017–2018
1.71 (1.66–1.77)
1.16 (1.14–1.20)
1.73 (1.68–1.79)
1.58 (1.45–1.75)
HR Hazard ratio, CI credible interval.
Article
https://doi.org/10.1038/s41467-025-58819-x
Nature Communications|  (2025) 16:4007 
12

# Page 13

and provides a robust framework for Bayesian analysis, avoiding the
pitfalls of manual calculations.
Physical function is a phenotype of aging47,48. Some multi-
morbidity tools, like the multimorbidity-weighted index, use physical
function to weight diseases19,20. However, this may introduce bias as
compensatory strategies in some organs can offset damaging effects4,
just as resilience to functional decline undermines a disease’s effect on
other body systems. The Body Clock as an overall whole-body system
health entropy measure predicts functional decline. We found that
decline in physical function measured by SPPB also increases the value
of the Body Clock, showing the bidirectional link between physical
function and multimorbidity49.
Certain indices use diseases to predict in-hospital mortality for
multimorbidity. Mortality-based tools21 may skew results towards fatal
diseases. We quantiﬁed the Body Clock independent of mortality or
other late-onset outcomes serving as an entropy of whole-body sys-
tems, while it predicts these outcomes. This ﬁnding suggests that
capturing the health state of all bodily organ systems as a compre-
hensive measure (whole-body entropy) reﬂects intrinsic biological
aging and predicts lifespan. Moreover, the components of the Health
Octo Tool emphasize that maximizing healthy longevity in humans
might require a combination of interventions that target multiple
aspects of health based on the basic mechanisms that prevent and
repair damage accumulation with aging, as well as early diagnosis of
particular pathologies driven by speciﬁc genetic and environmental
factors.
Our data indicate that diseases at subclinical states or without
treatment have signiﬁcant predictive power for BODN. Clinical trials
have linked even mild hypertension to cognitive impairments50, and
early intensive treatment may protect cognitive function and kidney
health51–53. Our research supports the idea that sustained exposure to
subclinical disease levels leads to chronic wear and tear, resulting in
damage accumulation and variable organ impairment, as reﬂected in
changes in the personalized Body Clocks. The large estimates and
uncertainty associated with some disease states suggest that certain
organs respond more readily to accumulated damage, possibly with
reduced resilience. Therefore, the Body Clock, as an integrated esti-
mate of disease levels contributing to BODN, can capture allostatic
overload,
representing
cumulative
physiological
dysregulation
beyond the body’s ability to adapt to stress4. Thus, various body
Men
Women
2.0 2.5 3.0 3.5 4.0 4.5 5.0 5.5 6.0 6.5 7.0 7.5 8.0 8.5 9.0 9.5 10.0 10.5 11.0 11.5 12.0
2.0 2.5 3.0 3.5 4.0 4.5 5.0 5.5 6.0 6.5 7.0 7.5 8.0 8.5 9.0 9.5 10.0 10.5 11.0 11.5 12.0
1.0
1.5
2.0
2.5
3.0
3.5
4.0
4.5
5.0
5.5
6.0
6.5
7.0
7.5
8.0
8.5
9.0
9.5
10.0
10.5
11.0
11.5
12.0
Out−of−Data Body Clock Applying BLSA Model Parameters to InCHIANTI Data
In−Data Body Clock Uisng InCHIANTI Model
In−Data (Replication) InCHIANTI Body Clock vs. Out−Of−Data (Test Set) Body Clock 
Fig. 8 | There is a high correlation between in-data and out-of-data methods
used developing the Body Clock in InCHIANTI study. With the in-data method
the full model (all diseases predicting longitudinal BODN) was performed, and the
Body Clock (replication) was obtained. Using the out-of-data method the para-
meters of the BLSA model (training set) were applied to the InCHIANTI data (test
set). The graph depicts a high correlation between in-data and out-of-data methods
of developing the Body Clock. The Pearson correlation for men was r = 0.76, 95% CI
(0.73–0.78) and for women was r = 0.70, 95% CI (0.68–0.72). The parameters of a
valid model can be used to predict new data. Sample size in InCHIANTI data n = 986,
women = 551.
Article
https://doi.org/10.1038/s41467-025-58819-x
Nature Communications|  (2025) 16:4007 
13

# Page 14

stressors, such as diseases, medications, infections, and socio-
environmental factors, may manifest as unique rates of increase in
the Body Clock and other components of the Health Octo Tool.
There are limitations to this study. The BLSA study recruited pri-
marily initially healthy individuals, focusing on healthy aging. Some of
the inter-population differences can be due to the initial study
recruitment inclusion criteria. Therefore, the general population,
which may have more severe conditions and hereditary diseases,
might experience a more accelerated Body Clock in comparison to
chronological age or time. Nevertheless, since the Body Clock is
quantiﬁed at the individual level, it can be updated whenever new
personalized information on disease levels becomes available using
our prediction models.
In the NHANES dataset, only mortality was considered as a long-
itudinal outcome, and we used the Body Clock to forecast mortality. It
is important to acknowledge, however, that the NHANES data slightly
underestimates the Body Clock due to the lack of information on
speciﬁc diseases, such as thyroid conditions or macular degeneration,
or ejection fraction from echocardiography in certain cohorts. Despite
this constraint, the AUC for mortality prediction in this cohort
remained at 0.8, surpassing the performance of the FI.
In summary, together, BSC, BSA, Body Clock, Body Age, Speed-
Body Clock, Speed-Body Age, Disability-Body Clock, and Disability-
Body Age comprise the Health Octo Tool—a multidimensional, com-
prehensive health assessment instrument. This marks the ﬁrst instance
of framing multimorbidity in terms of intrinsic clocks and their
translation to rates of aging. Such metrics enable a deeper under-
standing of the genomic and environmental factors underlying het-
erogeneity in various aspects of health at any age. This tool can shed
light on the variability of the biological aging and has the potential to
differentiate personalized markers of comprehensive health, encom-
passing genomics and environmental factors. It can also identify
organs and individuals with accelerated aging or at risk, and can be
applied in all-age clinics, precision medicine, and clinical trials. By
understanding the complex interplay between organ health, aging,
and disease, this tool can contribute to improving healthcare strate-
gies and identifying early-onset requirements for personalized
interventions.
Methods
This study employs secondary data analyses using data from three
distinct sources: the Baltimore Longitudinal Study on Aging (BLSA)31,32
[n = 907,
women=451],
the
longitudinal
Invecchiare
in
Chianti
(InCHIANTI) aging study33 [n = 986, women=551], and NHANES data
(2003–2018)38 [n = 40,700, women = 23,121]. These studies are sum-
marized in the supplemental materials. This study was conducted in
accordance with all relevant ethical regulations. The original BLSA and
InCHIANTI studies were approved by the Institutional Review Board at
the Intramural Research program at National Institute on Aging (NIA/
IRP). The study participants provided informed consent for the future
use of the data. Our analyses used de-identiﬁed data. The proposals
using BLSA and InCHIANTI data for this project were approved at NIA/
IRP, and NHANES data is publicly available.
Bayesian inference
We brieﬂy describ the formula for the Bayesian approach in the Sup-
plemental Method. Bayesian inference allowed us to estimate the
coefﬁcient distribution around the observed point and build models
for all points using both prior knowledge and likelihood. In our ana-
lyses, we used BODN as an ordinal longitudinal outcome with the
cumulative family.
Brieﬂy, the cumulative model operates under the assumption that
the observed ordinal variable Y is derived from the categorization of an
underlying continuous latent variable ey: In this framework, there are
latent thresholds τκ (where 1≤κ ≤K) that divide the continuous latent
variable ey into K + 1 distinct, ordered categories, which correspond to
the observed ordered values of Y (equation [18]).
Y = K, τκ1<ey<τκ
ð18Þ
In this formula K is 13, the number of subsequent values of BODN,
and ey is the predicted BODN in the model28,30.
The disease levels are included in the models as lagged ordinal
predictors, adjusting for time and excluding chronological age. To
develop various models, we employed Multilevel Ordinal Regression
with individuals as the model level within a Bayesian framework28,30. To
assess the models’ predictive accuracy, we used leave-one-out cross-
validation36, calculated the models’ weights37, and compared all mod-
els with chronological age. By incorporating all disease levels into a
single model, we were able to predict post-analyses BODN at individual
levels, quantifying an individual-based Body Clock. To determine Body
Age, we regressed chronological age over the Body Clock with a
Gamma distribution and log link.
Latent maximum effect
To avoid crude categorization of diseases and the risk of disease
misclassiﬁcation in older adults, in addition to the ordinal BODN, we
used speciﬁc diseases as ordinal variables within the Bayesian
framework29. This approach treated ordinal categorized diseases as a
continuous monotonic latent variable, which allowed us to estimate
maximum coefﬁcient effects for each ordinal predictor, referred to as
maximum disease-speciﬁc posterior coefﬁcient estimates. We then
introduced ordinal cut-points based on the proportion of each disease
level in the data to quantify disease-level-speciﬁc estimates.
Model evaluation and in-sample and out-of-sample
predictive checks
To assess the robustness of the model’s ability to predict BODN, we
employed the Time-1 full model based on BLSA data to predict BODN
in the InCHIANTI and NHANES data for out-of-sample validation, and
we used InCHIANTI and NHANES data as separate models for replica-
tion. We compared the estimated log predictive density (ELPD) of the
models using LOO-CV, which allows us to compare the predictive
distribution to the true data generating process. Additionally, we used
posterior predictive checking54 to compare the posterior predictive
density of simulated data to density estimates of the observed data to
predict the new data (for InCHIANTI and NHANES data, representing
out-of-sample validations).
Bayesian stacking weights to compare models
To compare several models simultaneously and determine their
respective strengths, we used Bayesian stacking53. This method
allowed us to compute model weights for each type of model, paired
with their corresponding age-only models (single-disease, single-sys-
tem, stepwise multisystem, and full models separately). Bayesian
stacking optimizes the estimated LOO-CV predictive performance of
the weighted model combinations, providing model-speciﬁc weights
compared to the age-only models, guiding us towards the models with
the best predictive performance.
Reporting summary
Further information on research design is available in the Nature
Portfolio Reporting Summary linked to this article.
Data availability
The BLSA and InCHAINTI data are available under restricted access,
because the elderly individuals are identiﬁable based on their age. The
access can be obtained by submission of a proposal to the BLSA and
InCHIANTI study research committees. NHANES data is available
online through the link: https://www.cdc.gov/nchs/nhanes/index.html.
Article
https://doi.org/10.1038/s41467-025-58819-x
Nature Communications|  (2025) 16:4007 
14

# Page 15

Code availability
The codes for algorithms are presented in the GitHub and Zenodo
pages55. https://github.com/ssalimi/HealthOctoTool https://zenodo.
org/records/14835216.
References
1.
Rocca, W. A. et al. Prevalence of multimorbidity in a geographically
deﬁned American population: patterns by age, sex, and race/eth-
nicity. Mayo Clin. Proc. 89, 1336–1349 (2014).
2.
Salive, M. E. Multimorbidity in older adults. Epidemiol. Rev. 35,
75–83 (2013).
3.
Cesari, M., Perez-Zepeda, M. U. & Marzetti, E. Frailty and multi-
morbidity: different ways of thinking about geriatrics. J. Am. Med.
Dir. Assoc. 18, 361–364 (2017).
4.
Ferrucci, L. et al. Measuring biological aging in humans: a quest.
Aging Cell 19, e13080 (2020).
5.
Kennedy, B. K. et al. Geroscience: linking aging to chronic disease.
Cell 159, 709–713 (2014).
6.
Ferrucci, L., Wilson, D. M. 3rd, Donega, S. & Montano, M. Enabling
translational geroscience by broadening the scope of geriatric care.
Aging Cell 23, e14034 (2024).
7.
Fabbri, E. et al. Aging and multimorbidity: new tasks, priorities, and
frontiers for integrated gerontological and clinical research. J. Am.
Med. Dir. Assoc. 16, 640–647 (2015).
8.
Salive, M. E., Suls, J., Farhat, T. & Klabunde, C. N. National Institutes
of Health advancing multimorbidity research. Med. Care 59,
622–624 (2021).
9.
Suls, J. et al. Emerging approaches to multiple chronic condition
assessment. J. Am. Geriatr. Soc. 70, 2498–2507 (2022).
10.
Fabbri, E. et al. Aging and the burden of multimorbidity: associa-
tions with inﬂammatory and anabolic hormonal biomarkers. J.
Gerontol. A Biol. Sci. Med. Sci. 70, 63–70 (2015).
11.
Mitnitski, A. B., Mogilner, A. J. & Rockwood, K. Accumulation of
deﬁcits as a proxy measure of aging. ScientiﬁcWorldJournal 1,
323–336 (2001).
12.
Searle, S. D., Mitnitski, A., Gahbauer, E. A., Gill, T. M. & Rockwood, K.
A standard procedure for creating a frailty index. BMC Geriatr. 8,
24 (2008).
13.
Jones, D. M., Song, X. & Rockwood, K. Operationalizing a frailty
index from a standardized comprehensive geriatric assessment. J.
Am. Geriatr. Soc. 52, 1929–1933 (2004).
14.
Rockwood, K. & Mitnitski, A. Frailty in relation to the accumulation of
deﬁcits. J. Gerontol. A Biol. Sci. Med. Sci. 62, 722–727 (2007).
15.
Pilotto, A. et al. A multidimensional approach to frailty in older
people. Ageing Res. Rev. 60, 101047 (2020).
16.
Veronese, N. et al. Prevalence of multidimensional frailty and pre-
frailty in older people in different settings: A systematic review and
meta-analysis. Ageing Res. Rev. 72, 101498 (2021).
17.
Schultz, M. B. et al. Age and life expectancy clocks based on
machine learning analysis of mouse frailty. Nat. Commun. 11,
4618 (2020).
18.
Langsetmo, L. et al. Advantages and disadvantages of random
forest models for prediction of hip fracture risk versus mortality risk
in the oldest old. JBMR 7, e10757 (2023).
19.
Wei, M. Y., Kabeto, M. U., Langa, K. M. & Mukamal, K. J. Multi-
morbidity and physical and cognitive function: performance of a
new multimorbidity-weighted index. J. Gerontol. A Biol. Sci. Med.
Sci. 73, 225–232 (2018).
20. Wei, M. Y., Ratz, D. & Mukamal, K. J. Multimorbidity in medicare
beneﬁciaries: performance of an ICD-coded multimorbidity-
weighted index. J. Am. Geriatr. Soc. 68, 999–1006 (2020).
21.
van Walraven, C., Austin, P. C., Jennings, A., Quan, H. & Forster, A. J.
A modiﬁcation of the Elixhauser comorbidity measures into a point
system for hospital death using administrative data. Med. Care 47,
626–633 (2009).
22. Moore, B. J., White, S., Washington, R., Coenen, N. & Elixhauser, A.
Identifying increased risk of readmission and in-hospital mortality
using hospital administrative data: the AHRQ Elixhauser Comor-
bidity Index. Med. Care 55, 698–705 (2017).
23. Wei, M. Y., Luster, J. E., Ratz, D., Mukamal, K. J. & Langa, K. M.
Development, validation, and performance of a new physical
functioning-weighted multimorbidity index for use in administrative
data. J. Gen. Intern Med. 36, 2427–2433 (2021).
24. Stolz, E., Hoogendijk, E. O., Mayerl, H. & Freidl, W. Frailty changes
predict mortality in 4 longitudinal studies of aging. J. Gerontol. A
Biol. Sci. Med Sci. 76, 1619–1626 (2021).
25. Li, X. et al. Longitudinal trajectories, correlations and mortality
associations of nine biological ages across 20-years follow-up. Elife
9, e51507 (2020).
26. Pilotto, A., Addante, F., D’Onofrio, G., Sancarlo, D. & Ferrucci,
L. The comprehensive geriatric assessment and the multi-
dimensional approach. A new look at the older patient with
gastroenterological disorders. Best. Pr. Res. Clin. Gastro-
enterol. 23, 829–837 (2009).
27.
Whitty, C. J. M. & Watt, F. M. Map clusters of diseases to tackle
multimorbidity. Nature 579, 494–496 (2020).
28. Bürkner, P. C. & Vourre, M. Ordinal regression models in psy-
chology: a tutorial. Adv. Methods Pract. Psychol. Sci. 2, 77–101
(2019).
29. Burkner, P. C. & Charpentier, E. Modelling monotonic effects of
ordinal predictors in Bayesian regression models. Br. J. Math. Stat.
Psychol. 73, 420–451 (2020).
30. Gelman, A., et al. Bayesian Data Analysis. (2014).
31.
Shock, N. W., et al. in NIH Publication no. 84–2450.
32. Ferrucci, L. The Baltimore Longitudinal Study of Aging (BLSA): a 50-
year-long journey and plans for the future. J. Gerontol. A Biol. Sci.
Med. Sci. 63, 1416–1419 (2008).
33. Ferrucci, L. et al. Subsystems contributing to the decline in ability to
walk: bridging the gap between epidemiology and geriatric prac-
tice in the InCHIANTI study. J. Am. Geriatr. Soc. 48, 1618–1625
(2000).
34. Bürkner, P. C. Advanced Bayesian multilevel modeling with the R
package brms. R. J. 10, 395–411 (2018).
35. Carpenter, B., et al. Stan: a probabilistic programming language. J.
Stat. Softw. 76, 1-32 (2017).
36. Vehtari, A., Gelman, A. & Gabry, J. Practical Bayesian model eva-
luation using leave-one-out cross-validation and WAIC. Stat. Com-
put. 27, 1413–1432 (2017).
37. Yao, Y., Vehtari, A., Simpson, D. & Gelman, A. Using stacking to
average Bayesian predictive distributions. Bayesian Anal. 13,
917–1003 (2018).
38. CDC. National Health and Nutrition Examination Survey. <https://
www.cdc.gov/nchs/nhanes/index.htm> (2003-2018).
39. Rockwood, K., Andrew, M. & Mitnitski, A. A comparison of two
approaches to measuring frailty in elderly people. J. Gerontol. A
Biol. Sci. Med. Sci. 62, 738–743 (2007).
40. Rockwood, K., McMillan, M., Mitnitski, A. & Howlett, S. E. A frailty
index based on common laboratory tests in comparison with a
clinical frailty index for older adults in long-term care facilities. J.
Am. Med. Dir. Assoc. 16, 842–847 (2015).
41.
Tian, Y. E. et al. Heterogeneous aging across multiple organ sys-
tems and prediction of chronic disease and mortality. Nat. Med. 29,
1221–1231 (2023).
42. Charlson, M. E. et al. The Charlson comorbidity index is adapted to
predict costs of chronic disease in primary care patients. J. Clin.
Epidemiol. 61, 1234–1240 (2008).
43. Salvi, F. et al. A manual of guidelines to score the modiﬁed
cumulative illness rating scale and its validation in acute hos-
pitalized elderly patients. J. Am. Geriatr. Soc. 56, 1926–1931
(2008).
Article
https://doi.org/10.1038/s41467-025-58819-x
Nature Communications|  (2025) 16:4007 
15

# Page 16

44. Mitnitski, A. B., Graham, J. E., Mogilner, A. J. & Rockwood, K. Frailty,
ﬁtness and late-life mortality in relation to chronological and bio-
logical age. BMC Geriatr. 2, 1 (2002).
45. Hoogendijk, E. O. et al. Trends in frailty and its association with
mortality: results from the longitudinal aging study Amsterdam,
1995-2016. Am. J. Epidemiol. 190, 1316–1323 (2021).
46. Nguyen, Q. D., Moodie, E. M., Keezer, M. R. & Wolfson, C. Clinical
correlates and implications of the reliability of the frailty index in the
Canadian longitudinal study on aging. J. Gerontol. A Biol. Sci. Med.
Sci. 76, e340–e346 (2021).
47. Fried, L. P. et al. Nonlinear multisystem physiological dysregulation
associated with frailty in older women: implications for etiology and
treatment. J. Gerontol. A Biol. Sci. Med. Sci. 64, 1049–1057 (2009).
48. Kuo, P. L. et al. A roadmap to build a phenotypic metric of ageing:
insights from the Baltimore Longitudinal Study of Aging. J. Intern.
Med. 287, 373–394 (2020).
49. Calderon-Larranaga, A. et al. Multimorbidity and functional
impairment-bidirectional interplay, synergistic effects and com-
mon pathways. J. Intern. Med. 285, 255–271 (2019).
50. de Menezes, S. T. et al. Hypertension, prehypertension, and
hypertension control: association with decline in cognitive perfor-
mance in the ELSA-Brasil Cohort. Hypertension 77, 672–681 (2021).
51.
Weiner, D. E. et al. Cognitive function and kidney disease: baseline
data from the systolic blood pressure intervention trial (SPRINT).
Am. J. Kidney Dis. 70, 357–367 (2017).
52. Rapp, S. R. et al. Effects of intensive versus standard blood pressure
control on domain-speciﬁc cognitive function: a substudy of the
SPRINT randomised controlled trial. Lancet Neurol. 19, 899–907
(2020).
53. Yang, M. & Williamson, J. Blood pressure and statin effects on
cognition: a review. Curr. Hypertens. Rep. 21, 70 (2019).
54. Gabry, J., Simpson, D., Vehtari, A., Betancourt, M. & Gelman, A.
Visualization in Bayesian workﬂow. J. R. Stat. Soc. Ser. A 182,
389–402 (2019).
55. Salimi, S. Health Octo Tool Matches Personalized Health with Rate
of Aging. Health Octo Tool (2025). https://doi.org/10.5281/zenodo.
14835216.
Acknowledgements
ShS is funded by National Institute on Aging K01 AG059898. DR is fun-
ded by Nathan Shock Center at University of Washington P30AZ013280.
We are grateful to the participants of the BLSA and InCHIANTI, and
NHANES studies, researchers, staff, and administrators. ShS acknowl-
edges the Stan Community, and the Bayesian Data Analysis course tar-
geted for Global South taught by AV. We appreciate Jefferey
Laubenstein for painting Fig. S1.
Author contributions
Sh.S. conceptualized the Body Clock, Body Age, Bodily System-Speciﬁc
Clock, Bodily System-Speciﬁc Age, Speed-Body Clock, Speed-Body
Age, Disability Index, Disability-Body Clock, and Disability-Body Age.
Sh.S. managed the data, conducted statistical analyses, designed
graphs, and authored the manuscript. Sh.S. designed the Figs. 1 and S1.
A.V. supervised Bayesian analyses, advised on methods, and commu-
nicated statistical ﬁndings. M.S. contributed to interpreting multi-
morbidity indices, writing, and editing. D.R. edited the manuscript and
provided feedback on aging rates, results, and discussion, and designed
Fig. 1 with Sh.S. M.K. provided feedback on aging rates. F.L. contributed
to health concepts, results interpretation, manuscript writing and edit-
ing, rates of aging, and insight on study methods in the InCHIANTI and
BLSA data.
Competing interests
The Health Octo Tool has a provisional patent (patent pending) by Sh.S.
with the aim to make it digitally available to researchers. M.K. is a co-
founder and shareholder of Optispan, Inc., and has expressed no con-
ﬂict of interest with this work. The remaining authors declare no com-
peting interests. This material should not be interpreted as representing
the viewpoint of the US Department of Health and Human Services, the
National Institutes of Health, or its represented agencies.
Additional information
Supplementary information The online version contains
supplementary material available at
https://doi.org/10.1038/s41467-025-58819-x.
Correspondence and requests for materials should be addressed to
Sh Salimi.
Peer review information Nature Communications thanks Kenneth
Rockwood and the other anonymous reviewer(s) for their contribution to
the peer review of this work. A peer review ﬁle is available.
Reprints and permissions information is available at
http://www.nature.com/reprints
Publisher’s note Springer Nature remains neutral with regard to jur-
isdictional claims in published maps and institutional afﬁliations.
Open Access This article is licensed under a Creative Commons
Attribution 4.0 International License, which permits use, sharing,
adaptation, distribution and reproduction in any medium or format, as
long as you give appropriate credit to the original author(s) and the
source, provide a link to the Creative Commons licence, and indicate if
changes were made. The images or other third party material in this
article are included in the article's Creative Commons licence, unless
indicated otherwise in a credit line to the material. If material is not
included in the article's Creative Commons licence and your intended
use is not permitted by statutory regulation or exceeds the permitted
use, you will need to obtain permission directly from the copyright
holder. To view a copy of this licence, visit http://creativecommons.org/
licenses/by/4.0/.
© The Author(s) 2025
Article
https://doi.org/10.1038/s41467-025-58819-x
Nature Communications|  (2025) 16:4007 
16
