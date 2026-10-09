"""prepare.py: true hourly slots when expand_hours=False (eICU path)."""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))

from two_stage_transformer.prepare import long_csv_to_npz  # noqa: E402


def test_true_hourly_slots_differ(tmp_path: Path) -> None:
    rows = []
    for hour in range(24):
        rows.append(
            {
                "patient": 1,
                "day": 1,
                "hour": hour,
                "hr": float(60 + hour),
                "label": 0,
                "los_days": 5,
            }
        )
    for hour in range(24):
        rows.append(
            {
                "patient": 1,
                "day": 2,
                "hour": hour,
                "hr": float(70 + hour),
                "label": 0,
                "los_days": 5,
            }
        )
    csv_path = tmp_path / "hourly.csv"
    pd.DataFrame(rows).to_csv(csv_path, index=False)
    out = tmp_path / "full.npz"
    long_csv_to_npz(
        str(csv_path),
        str(out),
        n_days=5,
        n_hours=24,
        sliding_window=False,
        expand_hours=False,
        max_calendar_day=5,
    )
    d = np.load(out, allow_pickle=True)
    X = d["X"]
    assert X.shape == (1, 5, 24, 1)
    assert X[0, 0, 0, 0] == 60.0
    assert X[0, 0, 1, 0] == 61.0
    assert X[0, 0, 0, 0] != X[0, 0, 1, 0]
    assert X[0, 1, 0, 0] == 70.0


def test_expand_hours_broadcast_still_works(tmp_path: Path) -> None:
    df = pd.DataFrame(
        {
            "patient": [1, 1],
            "day": [1, 2],
            "hour": [24, 48],
            "hr": [60.0, 70.0],
            "label": [1, 1],
            "los_days": [5, 5],
        }
    )
    csv_path = tmp_path / "day.csv"
    df.to_csv(csv_path, index=False)
    out = tmp_path / "full.npz"
    long_csv_to_npz(
        str(csv_path),
        str(out),
        n_days=5,
        n_hours=24,
        sliding_window=False,
        expand_hours=True,
        max_calendar_day=5,
    )
    X = np.load(out)["X"]
    assert X.shape == (1, 5, 24, 1)
    assert np.allclose(X[0, 0, :, 0], 60.0)
    assert np.allclose(X[0, 1, :, 0], 70.0)
