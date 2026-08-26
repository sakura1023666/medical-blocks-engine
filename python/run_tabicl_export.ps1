#Requires -Version 5.0
<#
.SYNOPSIS
  Run block_tabicl_ml_export.py -> xlsx for R tablcl_v2 (excel mode).

.DESCRIPTION
  Sets KMP_DUPLICATE_LIB_OK for Windows OpenMP issues.
  -Ref / -Ana default from project root config.R: analysis_group & reference_group (same as R ml_models).
  Override with -Ref / -Ana when they differ from config.R.
  Use -UseLatestPipelineCsv to pick newest df_train/df_validation under Output_*/*/Data/.

.EXAMPLE
  .\python\run_tabicl_export.ps1 -UseLatestPipelineCsv -OutXlsx "Models\TabICL_export.xlsx"

.EXAMPLE
  .\python\run_tabicl_export.ps1 `
    -TrainCsv "D:\work\03block-ML\Output_run1\...\Data\df_train.csv" `
    -ValCsv "D:\work\03block-ML\Output_run1\...\Data\df_validation.csv" `
    -OutXlsx "D:\work\03block-ML\Output_run1\...\Models\TabICL_export.xlsx"
#>
[CmdletBinding(DefaultParameterSetName = "ExplicitPaths")]
param(
  [Parameter(ParameterSetName = "ExplicitPaths", Mandatory = $true)]
  [string]$TrainCsv,
  [Parameter(ParameterSetName = "ExplicitPaths", Mandatory = $true)]
  [string]$ValCsv,
  [Parameter(ParameterSetName = "AutoLatest", Mandatory = $true)]
  [switch]$UseLatestPipelineCsv,
  [Parameter(Mandatory = $true)]
  [string]$OutXlsx,
  [string]$Ref = "",
  [string]$Ana = "",
  [string]$ConfigPath = "",
  [int]$NFolds = 5,
  [int]$Seed = 42,
  [string]$Device = "",
  [switch]$KvCache,
  [Nullable[int]]$NEstimators = $null,
  [string]$CheckpointVersion = "",
  [Nullable[int]]$BatchSize = $null
)

$ErrorActionPreference = "Stop"
$env:KMP_DUPLICATE_LIB_OK = "TRUE"

$scriptDir = $PSScriptRoot
$projectRoot = Split-Path -Parent $scriptDir
$pyScript = Join-Path $scriptDir "block_tabicl_ml_export.py"
if (-not (Test-Path -LiteralPath $pyScript)) { throw "Missing: $pyScript" }

function Read-ConfigProjectGroups {
  param([string]$Path)
  $analysis = $null
  $reference = $null
  $lines = Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop
  foreach ($line in $lines) {
    $trim = $line.TrimStart()
    if ($trim.StartsWith("#")) { continue }
    if ($line -match '^\s*analysis_group\s*=\s*"([^"]+)"') {
      $analysis = $Matches[1]
    }
    elseif ($line -match "^\s*analysis_group\s*=\s*'([^']+)'") {
      $analysis = $Matches[1]
    }
    if ($line -match '^\s*reference_group\s*=\s*"([^"]+)"') {
      $reference = $Matches[1]
    }
    elseif ($line -match "^\s*reference_group\s*=\s*'([^']+)'") {
      $reference = $Matches[1]
    }
  }
  return [PSCustomObject]@{ Analysis = $analysis; Reference = $reference }
}

function Resolve-ExistingFile {
  param([string]$Path, [string]$Label)
  if ([string]::IsNullOrWhiteSpace($Path)) {
    throw "$Label path is empty."
  }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    $nl = [Environment]::NewLine
    $msg = @(
      "$Label file not found: $Path",
      "",
      "Replace with real paths on your PC (after train_validation / ml_models), e.g.",
      "  ...\step07_train_validation\Data\df_train.csv",
      "",
      "Or from repo root auto-pick latest under Output_*:",
      "  .\python\run_tabicl_export.ps1 -UseLatestPipelineCsv -OutXlsx `"Models\TabICL_export.xlsx`"",
      "",
      "Get-Location: $(Get-Location)",
      "Project root: $projectRoot"
    ) -join $nl
    throw $msg
  }
  return (Resolve-Path -LiteralPath $Path).Path
}

if ($PSCmdlet.ParameterSetName -eq "AutoLatest") {
  $candidates = @()
  $outDirs = Get-ChildItem -LiteralPath $projectRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "Output_*" }
  foreach ($od in $outDirs) {
    Get-ChildItem -LiteralPath $od.FullName -Recurse -Filter "df_train.csv" -File -ErrorAction SilentlyContinue |
      Where-Object { $_.DirectoryName -match '[\\/]Data$' } |
      ForEach-Object { $candidates += $_ }
  }
  if ($candidates.Count -eq 0) {
    throw "No Data\df_train.csv under $($projectRoot)\Output_*. Run train_validation first, or pass -TrainCsv/-ValCsv."
  }
  $newestTrain = $candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  $trainDir = $newestTrain.Directory.FullName
  $valPath = Join-Path $trainDir "df_validation.csv"
  if (-not (Test-Path -LiteralPath $valPath -PathType Leaf)) {
    throw "Found train CSV but missing df_validation.csv next to: $($newestTrain.FullName)"
  }
  $TrainCsv = $newestTrain.FullName
  $ValCsv = $valPath
  Write-Host "Train: $TrainCsv"
  Write-Host "Val:   $ValCsv"
}

$cfgFile = if ($ConfigPath) { $ConfigPath } else { Join-Path $projectRoot "config.R" }
if ((-not $Ref) -or (-not $Ana)) {
  if (-not (Test-Path -LiteralPath $cfgFile -PathType Leaf)) {
    throw "Missing -Ref/-Ana and config not found: $cfgFile"
  }
  $gr = Read-ConfigProjectGroups $cfgFile
  if (-not $Ref) {
    if (-not $gr.Reference) { throw "Could not parse reference_group from $cfgFile; pass -Ref explicitly." }
    $Ref = $gr.Reference
  }
  if (-not $Ana) {
    if (-not $gr.Analysis) { throw "Could not parse analysis_group from $cfgFile; pass -Ana explicitly." }
    $Ana = $gr.Analysis
  }
}

Write-Host "Groups: -Ref (reference) = $Ref ; -Ana (analysis/case) = $Ana  [from config.R if not overridden]"

$trainResolved = Resolve-ExistingFile -Path $TrainCsv -Label "Train (-TrainCsv)"
$valResolved = Resolve-ExistingFile -Path $ValCsv -Label "Val (-ValCsv)"

$argsList = @(
  $pyScript,
  "--train", $trainResolved,
  "--val", $valResolved,
  "--out", $OutXlsx,
  "--ref", $Ref,
  "--ana", $Ana,
  "--n-folds", "$NFolds",
  "--seed", "$Seed"
)
if ($Device) { $argsList += @("--device", $Device) }
if ($KvCache) { $argsList += "--kv-cache" }
if ($null -ne $NEstimators) { $argsList += @("--n-estimators", "$NEstimators") }
if ($CheckpointVersion) { $argsList += @("--checkpoint-version", $CheckpointVersion) }
if ($null -ne $BatchSize) { $argsList += @("--batch-size", "$BatchSize") }

$outDir = Split-Path -Parent $OutXlsx
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

Push-Location $projectRoot
try {
  & python @argsList
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
  Pop-Location
}

Write-Host "Done. Set config.R tablcl_v2_data_path to: $OutXlsx"
