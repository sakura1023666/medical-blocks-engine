# 81 — CLHLS 抑郁×焦虑症状网络

复现 Chang 2025（BMC Psychiatry）：独居老人 CESD-10 × GAD-7，N=2028。

## Block（名称不含项目内部编码）

| 文件 | register_block |
|------|----------------|
| `01block_clhls_symptom_ingest.R` | `clhls_symptom_ingest` |
| `02block_clhls_network.R` | `clhls_network` |
| `03block_clhls_centrality.R` | `clhls_centrality` |
| `04block_clhls_weighted.R` | `clhls_weighted` |
| `05block_clhls_bridge.R` | `clhls_bridge` |
| `06block_clhls_sex.R` | `clhls_sex` |
| `07block_clhls_sex_nct.R` | `clhls_sex_nct` |
| `08block_clhls_stability.R` | `clhls_stability` |
| `09block_clhls_network_pub.R` | `clhls_network_pub` |

公共：`00clhls_net_common.R`（Pearson → nearPD → EBICglasso γ=0.5 等）。

## 入口

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
  run/clhls_symptom_network/run_clhls_symptom_network.R

# 冒烟（少次数）
CLHLS_NBOOTS=20 CLHLS_NCT_IT=20 SMOKE_NO_FEISHU=1 \
  "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
  run/clhls_symptom_network/run_clhls_symptom_network.R
```

## 飞书

B14；base 见 `run/feishu/.env.feishu`。
