# 交叉滞后试点脚本（非正式交付）

正式入口仍是 `run/cross_lagged/run_cross_lagged_frailty.R`。  
本目录仅放探索性脚本，**不覆盖**正式 Table S6/S7。

```bash
# 血检四中介（横截面/路径）
Rscript Blocks/54_cross_lagged_full/pilots/pilot_blood4_mediators.R --study-root "$STUDY" --sims 200

# 纵向血检时序试点
Rscript Blocks/54_cross_lagged_full/pilots/pilot_blood4_mediators_long.R --study-root "$STUDY" --sims 200
```
