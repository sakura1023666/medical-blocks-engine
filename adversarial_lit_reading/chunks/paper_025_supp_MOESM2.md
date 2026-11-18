Model Benchmark

The performance of the LSTM, Transformer and TPC architecture were evaluated on the BlendedICU dataset. Models were trained on an extract from the BlendedICU dataset which included nearly 3,000 patients from each subset. A single model was trained for predicting ICU RLoS and ICU mortality for all subsets; performance results are presented for each subset in Table S2. We observed that the TPC model outperformed other models on most subsets and both prediction tasks. One exception was noted: for mortality prediction on the eICU subset, TPC showed the lowest AUROC of the three architectures (AUROC: 0.760 [0.756–0.765]), below both LSTM (0.768) and Transformer (0.777).

Table S2: Performance comparison of the LSTM, Transformer, and TPC architectures when training on 12,654 patients from the BlendedICU dataset.

AUROC, Area Under the Receiver Operating Characteristic curve; MAPE, Mean Absolute Percentage Error; RLoS, Remaining Length of Stay; CI, confidence interval; TPC, Temporal Pointwise Convolution; LSTM, Long Short-Term Memory; MNAR, Missing Not At Random. Higher AUROC indicate better mortality discrimination. Lower MAPE indicates better RLoS prediction. 95% CIs for AUROC were computed using the DeLong method; 95% CIs for MAPE were estimated by bootstrap resampling (10,000 iterations, percentile method). 

For each architecture, a single model was trained, but the validation was presented separately for each subset. The training set contained the same number of patients from each subset.


## Table 0


Prediction | Validation dataset | LSTM | Transformer | TPC

Remaining  Length of  Stay, MAPE [95% CI] | AmsterdamUMC | 91.955 [91.032, 92.879] | 95.201 [94.139, 96.249] | 86.881 [85.789, 87.953]

Remaining  Length of  Stay, MAPE [95% CI] | eICU | 104.536 [103.432, 105.622] | 114.857 [113.543, 116.147] | 98.959 [97.819, 100.095]

Remaining  Length of  Stay, MAPE [95% CI] | HiRID | 98.564 [97.192, 99.926] | 104.951 [103.310, 106.531] | 93.205 [91.694, 94.691]

Remaining  Length of  Stay, MAPE [95% CI] | MIMIC-IV | 92.381 [91.573, 93.193] | 98.446 [97.504, 99.385] | 86.193 [85.385, 87.005]

Mortality,  AUROC [95% CI] | AmsterdamUMC | 0.786 [0.781 - 0.791] | 0.800 [0.795 - 0.804] | 0.825 [0.821 - 0.830]

Mortality,  AUROC [95% CI] | eICU | 0.768 [0.762 - 0.773] | 0.777 [0.772 - 0.782] | 0.760 [0.756 - 0.765]

Mortality,  AUROC [95% CI] | HiRID | 0.854 [0.849 - 0.858] | 0.862 [0.858 - 0.866] | 0.883 [0.879 - 0.886]

Mortality,  AUROC [95% CI] | MIMIC-IV | 0.838 [0.835 - 0.841] | 0.836 [0.833 - 0.839] | 0.839 [0.836 - 0.842]
