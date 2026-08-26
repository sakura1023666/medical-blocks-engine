# 人工流程：迁移 medical-blocks 到 192.168.68.34（user02 / 2202）

> 完整版见引擎技能 `.cursor/skills/deploy-medical-blocks-host/SKILL.md` 流程 B。  
> 2026-07-29：已从本机同步 5006 研究区 + TST 引擎关键路径；`engine.env` 指向  
> `/home/user02/medical-blocks/engine`。

## 1. 登录

```bash
ssh -p 2202 user02@192.168.68.34
# 密码（首次后请改密）: user02@2026
```

## 2. 目录（已存在可跳过）

```bash
mkdir -p ~/medical-blocks/{engine,studies-iface,data,results}
```

## 3. 从 133 / 本机同步

```bash
# 研究区接口（含 environment / trajectory / competing / tst）
rsync -avz -e 'ssh -p 2202' \
  /mnt/g/DockerHome/5006/medical-blocks-studies/ \
  user02@192.168.68.34:~/medical-blocks/studies-iface/

# 引擎（全量或按需；TST 至少需要 Blocks/71 + run/two_stage_transformer_stroke + python/two_stage_transformer）
rsync -avz -e 'ssh -p 2202' \
  --exclude '.git' --exclude 'Data' --exclude 'Output' --exclude 'adversarial_lit_reading' \
  /mnt/e/01block/01Block-new-Final/ \
  user02@192.168.68.34:~/medical-blocks/engine/
```

## 4. engine.env

```bash
echo 'MEDICAL_BLOCKS_ROOT=/home/user02/medical-blocks/engine' \
  > ~/medical-blocks/studies-iface/engine.env
```

## 5. 依赖

- R ≥ 4.3 + `Rscript`
- TST Worker：Python + PyTorch（`python/two_stage_transformer/`）
- 常用 R 包：`data.table` `mice` `cli` `dplyr` …

## 6. 冒烟

```bash
cd ~/medical-blocks/studies-iface
./run_study.sh _template_tst --routine tst --list-units
# 放入 Data/mimic/ 并改完 <TO_CONFIRM> 后：
cp -a studies/_template_tst studies/stroke_tst_smoke
./run_study.sh stroke_tst_smoke --routine tst --shared-only
```

竞争风险同理：

```bash
cp -a studies/_template_competing studies/stroke_aki_smoke
./run_study.sh stroke_aki_smoke --routine competing --shared-only
```

## 7. Cursor Remote-SSH（可选）

`HostName 192.168.68.34` / `Port 2202` / `User user02`  
打开：`/home/user02/medical-blocks/studies-iface`
