@echo off
REM Same runtime as ischemic stroke TST (Windows R + Anaconda torch, CPU)
set MEDICAL_BLOCKS_ROOT=E:\01block\01Block-new-Final
set BLOCK_RESULT_ROOT=G:\02block_result
set PYTHON=C:\ProgramData\anaconda3\python.exe
set PATH=C:\ProgramData\anaconda3;C:\ProgramData\anaconda3\Scripts;%PATH%
set CONFIG=G:\02block_result\33_AKI\two_stage_transformer_40041421\config_two_stage_transformer_stroke_task_parallel.R
set RSCRIPT=C:\Program Files\R\R-4.5.1\bin\x64\Rscript.exe
cd /d %MEDICAL_BLOCKS_ROOT%
echo === AKI TST full pipeline (stroke-identical env) ===
"%PYTHON%" -c "import torch; print('torch', torch.__version__, 'cuda', torch.cuda.is_available())"
"%RSCRIPT%" run\two_stage_transformer_stroke\run_two_stage_transformer_stroke_task_parallel.R --config "%CONFIG%" --workers 4
pause
