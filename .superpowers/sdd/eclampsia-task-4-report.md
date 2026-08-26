# Eclampsia Task 4 Report — Launch 10-worker ML batch

**Status:** SUCCESS (scheduling confirmed; batch long-running)

## Launch

| Item | Value |
|------|--------|
| Master PID (Windows Rscript) | **76412** |
| Wrapper PID (cmd) | **56208** |
| Started | 2026-08-21 14:32:15 |
| Log (primary) | `G:/02block_result/27_eclampsia/small sample prediction_39780007/logs/batch_ps_err.log` (cli → stderr) |
| Log (stable excerpt) | `…/logs/batch_master_20260821_143215.log` |
| Launcher bat | `E:/01block/01Block-new-Final/.superpowers/sdd/eclampsia-launch-ml-batch.bat` |
| Config | `G:/…/small sample prediction_39780007/config.R` |
| Args | `--workers 10 --db nhanes` |
| R | Windows R-4.5.1 `Rscript.exe` |

## Startup evidence (one-line)

`db_mode=nhanes, workers=10` → 任务队列 27（NLR…ACAG）；已启动 worker `[NLR]`…`[APRI]`；`by_index/` 与 `checkpoints/` 已出现产物。

## Queue / artifacts

- Gate: 候选 69 → NHANES `n_valid>=30` 可用 **27**（42 未过筛跳过）
- `by_index/`: 多指标目录 + 若干 `【failed】*`（见 Concerns）
- `checkpoints/`: `_global_harmonization`, `_shared`, `by_index`
- Worker logs: `logs/NLR.log`, `PLR.log`, …（课题 `logs/`）

## TabPFN

Probe: `C:/ProgramData/anaconda3/python.exe` → **tabpfn_ok 7.1.1**. Config 保留 Windows anaconda 路径，未改。

## How launched (deviation from brief nohup)

WSL `nohup Rscript … --config "/mnt/g/…/small sample …/config.R"` 在转 Windows R 时因路径空格拆参失败（`path[1]="sample"`）；直接调 `Rscript.exe` 时 `MEDICAL_BLOCKS_ROOT` 未进 Win32。  
改用 **bat + PowerShell Start-Process**，设置 `MEDICAL_BLOCKS_ROOT=E:/01block/01Block-new-Final` 与 `MEDICAL_BLOCKS_SKIP_WIN_R=1`，config 用 `G:/…` 带空格引号路径。

## Cleanup

早期误启动产生 **3 个 master**（14:30:46 / 14:31:12 / 14:32:15）。已杀掉 74320、74484 及其 worker，仅保留 **76412**（约 10 路 worker）。

## Concerns

1. **路径空格**：课题目录名含空格；`mv.exe` 重命名 `【failed】*` 常 status=1（部分失败目录残留）。
2. **大量 `status=error`**：与重复 master 竞态 + rename 失败有关；部分指标流水线已写出 Tables/code 仍被标 failed。可用 `skip_existing` 续跑或清 `【failed】` 后重跑。
3. **主日志在 stderr**：`batch_ps_out.log` 为空；以 `batch_ps_err.log` / `batch_master_*.log` 为准。
4. Git：按约束跳过。

## Success criteria

- [x] `logs/` 存在  
- [x] workers=10 / db=nhanes 调度  
- [x] 进程存活（76412 + workers）  
- [x] `by_index` / checkpoints 开始出现  
