Methods

This study is reported according to the TRIPOD+AI guidelines (21). All our codes are available at https://github.com/CIC-1410/BlendedLoS.

Ethics Statement

Datasets were observational and had preexisting ethical approvals or exemptions that allowed for retrospective analysis (8–11). Access was obtained following the respective requirements for each dataset.

The BlendedICU dataset

The BlendedICU dataset comprises harmonized data from five major publicly available ICU databases: eICU, MIMIC-III, MIMIC-IV, HiRID and AmsterdamUMC (8–12). It contains 42 time series variables, and exposure to more than 100 drugs for nearly 380,000 ICU stays from four data sources in the USA, Switzerland and the Netherlands. Because it contains ICU data from international care sites, this database is more representative of worldwide ICU data than individual databases (12). Original patient data from each source database of the BlendedICU dataset was preserved, apart from converting numerical values to a single unit system.

Extraction and pre-processing

In this work, we extracted nearly 20,000 unique patients from each of four subsets of the BlendedICU dataset: AmsterdamUMC, eICU, HiRID, and MIMIC-IV. Time series variables were sampled hourly using forward filling.

Missing data in this study are best characterized as Missing Not At Random (MNAR), a pattern well-documented in ICU electronic health records (22–24). Two mechanisms account for this: first, the frequency of measurements varies across source databases (e.g., electrolyte sampling rates differ between institutions), so missingness is structurally linked to data origin; second, the likelihood that a measurement is performed depends on the patient's clinical condition — a stable patient is far less likely to undergo repeated laboratory sampling than a deteriorating one, meaning that the absence of a value is itself informative about the patient's status. Classical imputation methods (mean/median substitution, multiple imputation by chained equations) implicitly assume data are Missing At Random (MAR) and may therefore introduce systematic bias when applied to MNAR data. We adopted forward-filling combined with missingness indicator masks, a strategy widely used in ICU prediction models (25,26).  Forward-filling preserves the temporal structure of the data while missingness masks allow the model to leverage the informative nature of missing values as an additional predictive signal. Although this approach rests on the simplifying assumption that physiological values remain stable between measurements, it avoids the distributional assumptions required by model-based imputation and retains all observations, unlike complete-case analysis which would disproportionately exclude the most severely ill patients.

Prior to normalization, extreme values were clipped to physiologically plausible ranges rather than winsorised to boundary values. Clipping thresholds were defined a priori based on physiological plausibility — for instance, setting to zero negative values for variables that cannot be negative by definition, or capping percentage values at 100% — consistently with the BlendedICU preprocessing pipeline. This clipping approach was preferred over winsorisation to avoid introducing a systematic signal at the boundary values that could distort gradient updates during model training. A supplementary table comparing descriptive statistics before and after this step is provided (Table S1 in Additional File 1).

All numerical data were then normalized according to the following rules:

where q5 and q95 are the 5% and 95% quantiles, respectively. This normalization step transformed the data between q5 and q95 to [−1, 1] and clipped extreme values to [−4, 4], which limited the influence of residual outliers on model training.

Feature Selection

The model uses longitudinal tabular time series data derived from electronic health records, sampled hourly throughout each ICU stay. This data type reflects the continuous, high-frequency monitoring that characterizes modern ICU care and enables dynamic, time-updated predictions rather than static admission-time risk scores. Demographic and time series variables in the BlendedICU dataset (version v0.3.2) were included, along with a selection of 17 drugs. All input variables used in this study are listed in Additional File 1. Patient length of stay in the ICU and mortality were extracted for prediction. Because diagnoses are not available in all four source databases, they were not used in this study.

Experimental designs

Numerous studies have used patient data to predict length of stay in ICU including simple linear regression models based on physiology scores (Sequential Organ Failure Assessment (SOFA) score, Simplified Acute Physiology Score II (SAPS II), Acute Physiology and Chronic Health Evaluation (APACHE)) and multiple linear regression models (27,28). They assumed a linear relation between patient data and the length of stay and did not use temporal data acquired during a patient’s stay. Machine learning models, such as random forest and gradient boosting methods, have also been utilized for non-temporal data (29,30).

Machine learning models improved current performance by utilizing time series data on the HiRID dataset (31). In addition, Rocheteau et al. introduced the Temporal Pointwise Convolution (TPC) architecture, which outperformed Long Short-Term Memory (LSTM) and Transformer architectures for predicting the length of stay and mortality on MIMIC-IV and eICU datasets (25). The TPC architecture is the current reference for predicting ICU mortality and ICU remaining length of stay (RLoS). 

Prediction of the ICU remaining length of stay through a two-stage process

Patient mortality drastically influences their RLoS: a severe patient could either recover over a long period of time or deteriorate and die swiftly. For this reason, RLoS prediction assumed that the patient was discharged alive. Accordingly, a two-step process was chosen. First, the model predicts the probability of patient mortality before discharge from ICU, and then the model predicts a patient’s time-to-discharge assuming survival. RLoS was capped to 10 days; a prediction of 10 was equivalent to “RLoS is more than 10 days”. Mortality and RLoS were evaluated hourly during a patient’s stay, beginning 5 hours after admission. 

The model is trained on the entire patient cohort, including those with a known fatal outcome. However, when evaluating performance, length-of-stay predictions are not included for patients who have died. This design preserves the full range of illness trajectories during training while ensuring that RLoS performance metrics reflect only clinically interpretable predictions — that is, those for patients who survive to discharge. The loss function (L) is therefore a weighted sum of the binary cross-entropy of mortality prediction and the mean squared logarithmic error of the RLoS prediction, applied conditionally:

where yM and yL are the true ICU mortality and RLoS; ŷM and ŷL are the ICU mortality and RLoS predictions; and α = 20.

Comparison of Transformer, LSTM, and TPC models 

In this study, we used state-of-the-art prediction models to predict ICU mortality and RLoS. We benchmarked Transformer, LSTM, and TPC models on our two-stage prediction task using the BlendedICU dataset. The TPC architecture demonstrated superior performance compared to Transformer and LSTM architectures (see Additional File 2). This architecture was introduced to handle both static (tabular) and dynamic (temporal) data, which is essential when dealing with data from electronic medical records (25).

Model evaluation

The BlendedICU dataset was partitioned using the source database of each patient. Each partition was split into a train, validation and test set containing, respectively, 70%, 15%, and 15% of the patients in the partition. Critically, the unit of splitting was the patient, not the individual observation or time step. 

Model performance was evaluated for predictions of both mortality and RLoS. Mortality prediction was evaluated using the Area Under the Receiver Operating Characteristic curve (AUROC) and the Area Under the Precision-Recall Curve (AUPRC), the latter being particularly informative in the presence of class imbalance. RLoS prediction was evaluated using the Mean Absolute Percentage Error (MAPE). The outcome studied is in-ICU mortality, defined as death occurring prior to ICU discharge. In-hospital mortality was not studied, as it is not available in a consistent and harmonized form across all four constituent databases of BlendedICU. Ninety-five percent confidence intervals (95% CI) for AUROC were computed using the DeLong method, a non-parametric approach designed for ROC curve comparison that does not assume a normal distribution of the AUC statistic (32). For MAPE and AUPRC, 95% CIs were estimated via bootstrapping with 10,000 resampling iterations. For the composite metric, 1,000 bootstrap iterations were used. All bootstrap CIs were computed using the percentile method on the held-out test set. There is currently no universally accepted statistical framework for comparing regression-based performance metrics such as MAPE across models; we therefore report bootstrapped CIs to convey uncertainty around point estimates, consistent with recommendations for transparent model evaluation reporting.

We introduced a composite metric “Mcomposite” that evaluated both the mortality and RLoS performance by comparing them to a baseline:

where yrlos and ymort are the predicted RLoS and ICU mortality, respectively; and MAPErlos,baseline and AUCmort,baseline are the performance baseline metrics obtained through internal validation. Lower values of Mcomposite indicate better performance; scores lower than 1 indicate a performance higher than internal validation.

The composite metric is normalized to the internal validation performance of each model on its training database, such that Mcomposite = 1 corresponds to performance equal to the internal baseline, values below 1 indicate improvement relative to that baseline, and values above 1 indicate degradation. This formulation enables fair cross-model and cross-database comparison by accounting for the inherent differences in task difficulty across datasets. The composite metric is used solely for overall model ranking; the individual AUROC and MAPE values reported in Tables 2 and S1 remain the primary performance metrics.

Specialization and Generalization

Two model performances were considered in particular:

Specialization: Model performance on a selected care site from which some data may be seen in training. This property is most relevant when applying a trained model to a known clinical setting. As it applies to a single known environment, some of its data may be used for training. 

Generalization: Model performance on care settings unseen in training. Generalization evaluates the model’s portability to new clinical environments. When evaluating generalization, it is important for the evaluation data to have been acquired outside of the training data's clinical setting. Generalization is a crucial property for applying a generic model to care sites unseen during model development.

Experiment

Dataset benchmark

We evaluated the TPC architecture for each source database of the BlendedICU dataset:

Internally: Training and evaluation were done on separate samples from a single subset;

Externally: Training was done on a sample from a single subset and evaluation was done on a sample from all other subsets.

This experiment measured the shortcomings of using solely internal validation as an indicator of model performance. It was also used to define the baseline performance metrics that are used in the composite metric Mcomposite.

Training scheme comparison

The aim of this experiment was to compare the benefits of methodologies utilizing multi-site data:

Data pooling; which consists of training a model with data from several data sources. This method avoids overfitting specific features of a single data source and improves generalization for external care sites. Overfitting occurs when a model learns the noise and specific patterns of the training data rather than the underlying generalizable relationships, resulting in poor performance on new, unseen data.

Transfer learning; where a model is pre-trained on a data source, then fine-tuned to another data source by resuming training using some of its data. This method can optimize the specialization of the model on a selected care site.

To evaluate multi-site integration, we compared two distinct regimes. In the Data Pooling approach, a unified model was trained on the combined cohorts of MIMIC-IV (N ≈10,000) and AmsterdamUMC (N ≈3,000). In the Transfer Learning approach, models were first pre-trained on MIMIC-IV dataset and subsequently fine-tuned on AmsterdamUMC to assess site-specific adaptation. For both regimes, specialization was measured on the respective test sets of the training sources, while generalization was strictly evaluated on the unseen eICU and HiRID databases.

Table S1. Distribution of variable values before and after removal of physiologically implausible values and outlier clipping.

ALT : alanine aminotransferase; AST : aspartate aminotransferase; BUN : blood urea nitrogen; GCS : Glasgow Coma Scale; IQR : interquartile range; PTT : partial thromboplastin time. Prior to normalization, extreme values were clipped to physiologically plausible ranges (e.g., negative values set to zero for variables constrained to be non-negative, percentage values capped at 100%). After normalization, a second clipping step was applied: values outside [−4, 4] in the normalized space were capped at the boundary, limiting the influence of residual outliers on model training. All statistics are reported on the original clinical scale, prior to normalization.

Input features

The following variables, extracted from Blended-ICU, were used as input variables for the Deep Learning model’s predictions:

•	Admission: age, sex, height, weight.

•	Vitals: heart rate, invasive systolic blood pressure, invasive diastolic blood pressure, invasive mean blood pressure, non-invasive systolic blood pressure, non-invasive diastolic blood pressure, non-invasive mean blood pressure, O² arterial saturation, temperature.

•	Laboratory: Lactate, glucose, magnesium, sodium, creatinine, calcium, chloride, potassium, PTT, bilirubin, alanine aminotransferase, aspartate aminotransferase, alkaline phosphatase, albumin, phosphate, bicarbonate, blood urea nitrogen, pH, paO2, paCO2, haemoglobin, white blood cells, platelets.

•	Drug exposures (yes or no): Alteplase, Atracurium, Cisatracurium, Dexamethasone, Dobutamine, Dopamine, Epinephrine, Fentanyl, Flumazenil, Furosemide, Ketamine, Midazolam, Norepinephrine, Pancuronium, Propofol, Sufentanil, Vercuronium.

•	Others: urine output, Glasgow coma score, Glasgow coma score eye, Glasgow coma score motor, Glasgow coma score verbal.


## Table 0


Variable | Total measurements (N) | Outliers clipped after normalisation | Outliers clipped after normalisation | Before removal/clipping (original scale) | After removal/clipping (original scale) | Normal physiological range

 |  | N clipped | % of total | Median [IQR] | Median [IQR] | 

Heart rate (/min) | 2,927,729 -2,927,683 | 46 | < 0.01 | 84.74 [72.66 - 98.0] | 84.74 [72.66 - 98.0] | [46.74 - 122.7]

Inv. Syst. Art. pressure (mmHg) | 2,012,993 – 2,012,799 | 194 | < 0.01 | 121.8 [104.9 - 141.0] | 121.8 [104.9 - 141.0] | [67.78 - 175.8]

Inv. Diast. Art. pressure (mmHg) | 1,750,345 - 1,748,403 | 1,942 | 0.11 | 58.79 [51.03 - 68.0] | 58.76 [51.03 - 68.0] | [33.34 - 84.24]

Inv. Mean Art. pressure (mmHg) | 2,011,034 – 2,007,587 | 3,447 | 2.7 | 80.1 [70.0 - 92.1] | 80.07 [70.0 - 92.0] | [46.95 - 113.2]

Non-inv. Syst. Art. pressure (mmHg) | 1,681,100- 1,681,029 | 73 | < 0.01 | 120.0 [105.0 - 138.0] | 120.0 [105.0 - 138.0] | [70.5 - 169.5]

Non-inv. Diast. Art. pressure (mmHg) | 1,467,823 – 1,467,610 | 213 | 0.014 | 65.0 [55.33 - 76.75] | 65.0 [55.33 - 76.75] | [32.87 - 97.12]

Non-inv. Mean Art. pressure (mmHg) | 1,499,913 – 1,499,760 | 153 | 0.01 | 80.0 [69.25 - 93.0] | 80.0 [69.25 - 93.0] | [44.37 - 115.6]

O² Sat. in Art. blood (%) | 214,190 – 213,225 | 965 | 0.45 | 96.2 [93.0 - 98.0] | 96.3 [93.0 - 98.0] | [88.7 - 103.7]

Temperature (°C) | 489,405 – 488,310 | 1,095 | 0.22 | 36.92 [36.51 - 37.38] | 36.93 [36.53 - 37.38] | [35.61 - 38.23]

Lactate (mmol/L) | 206,670 – 206,241 | 429 | 0.21 | 1.7 [1.1 - 2.7] | 1.7 [1.1 - 2.7] | [0.70 – 2.2]

Glucose (mmol/L) | 701,180 – 699,973 | 1,207 | 0.17 | 7.6 [6.2 - 9.4] | 7.6 [6.2 - 9.379] | [2.800 - 12.4]

Magnesium (mmol/L) | 215,097 – 214,757 | 340 | 0.16 | 0.863 [0.76 - 0.98] | 0.863 [0.76 - 0.98] | [0.533 - 1.193]

Sodium (mmol/L) | 300,317 – 300,238 | 79 | 0.026 | 139.0 [136.0 - 142.0] | 139.0 [136.0 - 142.0] | [130.0 - 148.0]

Creatinine (µmol/L) | 279,472 – 279,203 | 269 | 0.096 | 93.0 [66.0 - 159.1] | 93.0 [66.0 - 159.1] | [46.6 - 110]

Calcium (mmol/L) | 233,584 – 233,385 | 199 | 0.085 | 2.05 [1.925 - 2.175] | 2.05 [1.925 - 2.175] | [1.675 - 2.425]

Chloride (mmol/L) | 270,461 – 270,110 | 351 | 0.113 | 106.0 [101.0 - 110.0] | 106.0 [101.0 - 110.0] | [92.5 - 119.5]

Potassium (mmol/L) | 381,317 – 381,118 | 199 | 0.052 | 4.1 [3.7 - 4.5] | 4.1 [3.7 - 4.5] | [2.9 - 5.299]

PTT (s) | 146,212 – 145,968 | 244 | 0.17 | 37.0 [30.0 - 53.7] | 37.0 [30.0 - 53.5] | [1.449 - 72.55]

Bilirubin (µmol/L) | 89,790 – 89,245 | 545 | 0.61 | 13.91 [8.0 - 33.04] | 13.91 [8.0 - 33.0] | [23.6 - 51.47]

ALT (U/L) | 113,338 – 112,019 | 1,319 | 1.16 | 41.0 [21.0 - 106.0] | 40.0 [21.0 - 101.0] | [10 - 40]

AST (U/L) | 114,827 – 113,227 | 1,600 | 1.4 | 53.0 [28.0 - 131.0] | 52.0 [28.0 - 125.0] | [10 - 40]

Alkaline phosphatase (U/L) | 95,542 – 95,207 | 335 | 0.35 | 87.0 [61.0 - 138.0] | 87.0 [61.0 - 137.0] | [28.5 - 202.5]

Albumin (g/L) | 80, 557-  80,550 | 7 | < 0.01 | 25.0 [20.0 - 30.0] | 25.0 [20.0 - 30.0] | [10.0 - 40.0]

Phosphate (mmol/L) | 243,169 – 243,106 | 63 | 0.026 | 1.065 [0.839 - 1.34] | 1.065 [0.839 - 1.34] | [0.315 - 1.816]

Bicarbonate (mmol/L) | 531,299 – 531,232 | 67 | 0.013 | 24.1 [21.5 - 27.1] | 24.1 [21.5 - 27.1] | [15.7 - 32.5]

BUN (mmol/L) | 263,903 – 263,881 | 22 | < 0.01 | 8.5 [5.3 - 14.4] | 8.5 [5.3 - 14.4] | [-5.14 - 22.15]

pH | 368,957 – 368,601 | 356 | 0.096 | 7.4 [7.34 - 7.45] | 7.4 [7.34 - 7.45] | [7.235 - 7.564]

PaO₂ (mmHg) | 507,426 – 506,695 | 731 | 0.14 | 94.9 [76.0 - 122.0] | 94.6 [76.0 - 122.0] | [25.90 - 163.9]

PaCO₂ (mmHg) | 366,977 – 366,726 | 251 | 0.068 | 39.1 [34.5 - 45.5] | 39.1 [34.5 - 45.3] | [22.59 - 55.6]

Haemoglobin (g/dL) | 326,213 – 326,188 | 25 | < 0.01 | 10.0 [8.8 - 11.45] | 10.0 [8.8 - 11.45] | [6.021 - 13.97]

White blood cells (G/L) | 329,152 – 328,420 | 732 | < 0.01 | 11.3 [8.2 - 15.4] | 11.2 [8.2 - 15.4] | [0.500 - 22.09]

Platelets (G/L) | 345,538 – 345,444 | 94 | 0.027 | 174.0 [116.0 - 247.0] | 174.0 [116.0 - 247.0] | [150 - 370.5]

Urine output (mL/h) | 1,097,755 -1,093,619 | 4,136 | 0.38 | 110.0 [52.42 - 225.0] | 110.0 [52.42 - 225.0] | [100.0 - 368.8]

Glasgow Coma Score (total) | 234,883 | 0 | 0 | 11.0 [6.0 - 14.0] | 11.0 [6.0 - 14.0] | [-1.0 - 23.0]

GCS Eye | 118, 016 | 0 | 0 | 4.0 [3.0 - 4.0] | 4.0 [3.0 - 4.0] | [2.5 - 5.5]

GCS Motor | 108,137 | 0 | 0 | 5.0 [2.0 - 5.0] | 5.0 [2.0 - 5.0] | [0.5 - 9.5]

GCS Verbal | 93,769 | 0 | 0 | 5.0 [4.0 - 5.0] | 5.0 [4.0 - 5.0] | [3.5 - 6.5]
