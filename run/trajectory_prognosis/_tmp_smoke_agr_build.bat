@echo off
cd /d E:\01block\01Block-new-Final
"C:\Program Files\R\R-4.5.1\bin\x64\Rscript.exe" --vanilla run\trajectory_prognosis\build_fcimb_summary_results.R --index AGR --proj G:/02block_result/55_COPD/Prognosis_Trajectory_v2_42558177
exit /b %ERRORLEVEL%
