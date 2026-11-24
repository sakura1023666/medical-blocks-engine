@echo off
cd /d E:\01block\01Block-new-Final
set SMOKE_NO_FEISHU=1
set MEDICAL_BLOCKS_AUTO_PUB_QC=0
"C:\Program Files\R\R-4.5.1\bin\x64\Rscript.exe" --vanilla run\trajectory_prognosis\run_trajectory_prognosis_copd_jlcm_batch_worker.R --unit GPR --db eicu --config configs\config_trajectory_prognosis_copd_jlcm_batch.R > G:\02block_result\55_COPD\Prognosis_Trajectory_v2_42558177\reports\rerun_gpr_eicu_ng3_20261124.log 2>&1
