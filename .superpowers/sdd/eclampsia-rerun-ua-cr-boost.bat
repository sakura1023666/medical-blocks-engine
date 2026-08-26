@echo off
set MEDICAL_BLOCKS_ROOT=E:/01block/01Block-new-Final
set MEDICAL_BLOCKS_SKIP_WIN_R=1
"C:\Program Files\R\R-4.5.1\bin\x64\Rscript.exe" "E:/01block/01Block-new-Final/run/ml/run_ml_dual_batch.R" --config "G:/02block_result/27_eclampsia/small sample prediction_39780007/config_ua_cr_boost.R" --only-index UA_CR --workers 1 --db nhanes --no-skip
