"""Shared bootstrap / stratum seeds for TCF Wang-style Table2 / S10 / Fig5 / Fig6.

Lock rule (2026-11-02): Internal TCF AUC CI strings must match across
Table 2 TCF, Table S10 Internal, Figure 5 legend, Figure 6 Internal.
Training uses the same integer offset as Internal but a different sample
(apparent in-sample row only; omit from Fig6).
"""

N_BOOT = 400
BOOT_SEED = 42
THR = 0.5

SEED_OFF_TRAIN = 0
SEED_OFF_INTERNAL = 0
SEED_OFF_C1 = 2
SEED_OFF_C2 = 3
SEED_OFF_EICU = 4
