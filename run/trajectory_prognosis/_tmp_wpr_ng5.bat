@echo off
cd /d E:\01block\01Block-new-Final
"C:\Program Files\R\R-4.5.1\bin\x64\Rscript.exe" --vanilla run\trajectory_prognosis\rerun_wpr_force_ng5_fcimb.R
exit /b %ERRORLEVEL%
