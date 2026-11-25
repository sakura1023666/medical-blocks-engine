@echo off
cd /d G:\02block_result\55_COPD\Prognosis_Trajectory_v2_42558177\by_index
if exist "【failed】GPR" rmdir /s /q "【failed】GPR"
ren "【success】GPR" "【failed】GPR"
if exist "【failed】GPR" (
  echo RENAME_OK
) else (
  echo RENAME_FAIL
  robocopy "【success】GPR" "【failed】GPR" /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS
  if exist "【failed】GPR\summary_results" (
    echo COPY_OK_AS_FAILED
    echo. > "【success】GPR\_MOVED_TO_FAILED.txt"
  )
)
exit /b 0
