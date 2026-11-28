# upstream: kml3d

文献 Wang 2025 使用 R 包 `kml3d`（依赖 `longitudinalData`）。

## 状态（2026-11-06）

在本机 R 4.5.1（`/mnt/c/Program Files/R/R-4.5.1`）上，CRAN 已不再提供 `kml3d` / `longitudinalData` / `clv` 二进制或源码安装通道。

## 本仓库实现

- 方法块：`Blocks/26_trajectory/27block_trajectory_kml3d.R`
- 默认 `config$multimorbidity$kml3d_engine = "kmeans_ch"`：联合标准化轨迹矩阵 + `stats::kmeans` + Calinski–Harabasz 选 k（与 `hrs/step03_kml3d/kml3d_part.R` 一致）
- 若将来恢复 `kml3d` 包，设 `kml3d_engine = "kml3d"` 即可优先走真包，失败自动回退

## 公开代码入口

- CRAN 归档检索：https://cran.r-project.org/package=kml3d
- 本地算法对照：`hrs/step03_kml3d/`
