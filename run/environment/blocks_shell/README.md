# 74_glide_sol

方法族：城市热暴露 GLIDE-SOL。

源库 Final 的 `pipeline_runner` 已登记这些 block 名，但 `Blocks/74_glide_sol_full/` **在源库中亦不存在**；
实现主体在 `python/block_glide_sol.py`。此处提供可被 pipeline 加载的 R 壳，内部委托 Python。
