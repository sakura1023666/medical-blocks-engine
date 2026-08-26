@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion

REM =============================================================================
REM  remove_block.bat — 移除已挂接 block
REM  用法: remove_block.bat <研究名> --slot SLOT_ID --block BLOCK_ID
REM =============================================================================

set "ROOT=%~dp0"
set "STUDY=%~1"
if "%STUDY%"=="" (
  echo 用法: remove_block.bat ^<研究名^> --slot SLOT_ID --block BLOCK_ID
  exit /b 1
)
shift

set "STUDY_DIR=%ROOT%studies\%STUDY%"
set "CONFIG=%STUDY_DIR%\config.R"
if not exist "%CONFIG%" (
  echo [错误] 找不到配置: %CONFIG%
  exit /b 1
)

set "ENGINE="
if exist "%ROOT%engine.env" (
  for /f "usebackq tokens=1,* delims==" %%a in ("%ROOT%engine.env") do (
    if /I "%%a"=="MEDICAL_BLOCKS_ROOT" set "ENGINE=%%b"
  )
)
if "%ENGINE%"=="" (
  echo [错误] engine.env 未设置 MEDICAL_BLOCKS_ROOT
  exit /b 1
)
set "ENGINE=%ENGINE:"=%"
for /f "tokens=* delims= " %%a in ("%ENGINE%") do set "ENGINE=%%a"

set "RSCRIPT=C:\Program Files\R\R-4.5.1\bin\x64\Rscript.exe"
if not exist "%RSCRIPT%" (
  where Rscript >nul 2>&1
  if errorlevel 1 (
    echo [错误] 找不到 Rscript
    exit /b 1
  )
  set "RSCRIPT=Rscript"
)

set "CATALOG=%ROOT%docs\block_catalog"
set "CLI=%ENGINE%\scripts\run_programmer_block_hooks_cli.R"
if not exist "%CLI%" (
  echo [错误] 引擎 CLI 不存在: %CLI%
  exit /b 1
)

set "MEDICAL_BLOCKS_ROOT=%ENGINE%"
"%RSCRIPT%" "%CLI%" remove --study-dir "%STUDY_DIR%" --catalog-dir "%CATALOG%" %*
exit /b %ERRORLEVEL%
