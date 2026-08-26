"""two_stage_transformer — MIMIC 缺血性脑卒中两阶段 Transformer 双轨包。

迁移自 `code/*.py`（5day ICU 通用纵向时序二分类实现），保持原算法不变：
  - model.py       两阶段(hour+day) Transformer(B 轨) + 单阶段 Transformer(A2 轨公平基线)
  - dataloader.py  npz -> (X,day_mask,y) Dataset
  - focal.py       FocalLoss(类别不平衡)
  - prepare.py     长表 CSV -> 张量 npz + 7:2:1 split
  - train.py       A1(公开实现单截止)/ A2(单阶段规范基线)/ B(两阶段多截止监督) 训练
  - eval.py        Day1..D ROC/AUC 指标表 + 校准/DCA
  - shap_plot.py   分日 SHAP 热图
  - baselines.py   Logistic/XGBoost/MLP/LSTM 传统基线
  - synthetic_external.py  合成地理外推队列(is_synthetic=True)

运行入口见 `python/block_two_stage_transformer.py`（`--mode` CLI）。
"""

__version__ = "0.1.0"
