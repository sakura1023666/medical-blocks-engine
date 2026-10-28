#!/bin/bash
set -u
PY=/home/ps/anaconda3/envs/torch/bin/python
ROOT=/mnt/sda/BlendedICU/data/cirrhosis_dzx_42151996/Output_database_pooling
"$PY" /mnt/sda/cirrhosis_train/Blocks/78_database_pooling_full/scripts/write_reeval_runners.py
for u in cirr_expA_nwicu_solo cirr_expB_mimic_solo cirr_expC_mimic2nwicu_transfer cirr_expD_pooled_mimic_nwicu; do
  d="$ROOT/$u"
  echo "$(date -Is) start $u"
  (cd "$d" && DBPOOL_REEVAL=1 CUDA_VISIBLE_DEVICES=0 "$PY" _run_reeval.py > "$d/reeval.log" 2>&1)
  echo "$(date -Is) end $u exit=$?"
  tail -n 5 "$d/reeval.log"
done
"$PY" /mnt/sda/cirrhosis_train/Blocks/78_database_pooling_full/scripts/merge_reeval_common_test.py
echo "$(date -Is) merge done"
