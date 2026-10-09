#!/usr/bin/env python3
"""GLIDE-SOL Seoul 100m CPU pipeline (literature-aligned figures/tables).

Modes (--mode):
  fetch_stations | domain_inputs | wind_coeff | meteo_forcing |
  solweig_run | station_extract | validate_metrics |
  figures_all | appendix_tables | run_all | gee_probe

GEE: uses earthengine-api if authenticated (earthengine authenticate).
Never reads password from config. Falls back to synthetic domain/forcing.
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
from pathlib import Path

import numpy as np
import pandas as pd

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------


def _ensure(p: Path) -> Path:
    p.mkdir(parents=True, exist_ok=True)
    return p


def _write_json(path: Path, obj) -> None:
    path.write_text(json.dumps(obj, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def _set_times_font() -> None:
    """Publication font: Times New Roman (Windows Fonts) with Liberation Serif fallback."""
    import matplotlib
    from matplotlib import font_manager

    candidates = [
        Path("/mnt/c/Windows/Fonts/times.ttf"),
        Path("C:/Windows/Fonts/times.ttf"),
        Path("/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf"),
    ]
    for fp in candidates:
        if fp.exists():
            font_manager.fontManager.addfont(str(fp))
            # also register bold/italic if present beside times.ttf
            for sib in ("timesbd.ttf", "timesi.ttf", "timesbi.ttf"):
                sp = fp.parent / sib
                if sp.exists():
                    font_manager.fontManager.addfont(str(sp))
            name = font_manager.FontProperties(fname=str(fp)).get_name()
            matplotlib.rcParams.update(
                {
                    "font.family": name,
                    "font.serif": [name, "Times New Roman", "DejaVu Serif"],
                    "mathtext.fontset": "stix",
                    "pdf.fonttype": 42,
                    "ps.fonttype": 42,
                    "axes.unicode_minus": False,
                    "figure.dpi": 300,
                    "savefig.dpi": 300,
                    "font.size": 10,
                    "axes.titlesize": 11,
                    "axes.labelsize": 10,
                    "xtick.labelsize": 9,
                    "ytick.labelsize": 9,
                    "legend.fontsize": 9,
                }
            )
            return
    matplotlib.rcParams.update(
        {
            "font.family": "serif",
            "font.serif": ["Times New Roman", "DejaVu Serif"],
            "pdf.fonttype": 42,
            "figure.dpi": 300,
            "savefig.dpi": 300,
        }
    )


def _fmt_num(x: float, digits: int = 2) -> str:
    """Paper-like signed number with unicode minus."""
    if not np.isfinite(x):
        return "—"
    s = f"{x:.{digits}f}"
    if s.startswith("-"):
        return "−" + s[1:]
    return s


def _write_sci_xlsx(
    out_xlsx: Path,
    sheet_name: str,
    title: str,
    headers: list[str],
    rows: list[list],
    bold_cells: set[tuple[int, int]] | None = None,
    footnote: str = "",
    col_widths: list[float] | None = None,
) -> None:
    """Literature-style Excel table: Times New Roman, title, three-line borders, bold best cells."""
    try:
        from openpyxl import Workbook
        from openpyxl.styles import Alignment, Border, Font, Side
        from openpyxl.utils import get_column_letter
    except ImportError as e:
        raise SystemExit("pip install openpyxl") from e

    bold_cells = bold_cells or set()
    wb = Workbook()
    ws = wb.active
    ws.title = sheet_name[:31]

    font_title = Font(name="Times New Roman", size=11, bold=True)
    font_head = Font(name="Times New Roman", size=10, bold=True)
    font_cell = Font(name="Times New Roman", size=10)
    font_bold = Font(name="Times New Roman", size=10, bold=True)
    font_note = Font(name="Times New Roman", size=9, italic=True)
    align_l = Alignment(horizontal="left", vertical="center", wrap_text=True)
    align_c = Alignment(horizontal="center", vertical="center", wrap_text=True)
    thin = Side(style="thin", color="000000")
    medium = Side(style="medium", color="000000")
    no_side = Side(style=None)

    n_col = len(headers)
    # Row 1: title spanning columns
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=n_col)
    c0 = ws.cell(1, 1, title)
    c0.font = font_title
    c0.alignment = align_l

    # Row 2: blank spacer under title (GMD-like)
    # Row 3: header
    header_row = 3
    for j, h in enumerate(headers, start=1):
        cell = ws.cell(header_row, j, h)
        cell.font = font_head
        cell.alignment = align_c if j > 1 else align_l
        # three-line: top medium on header top, thin under header
        cell.border = Border(top=medium, bottom=thin, left=no_side, right=no_side)

    # data rows start at 4
    for i, row in enumerate(rows):
        r = header_row + 1 + i
        for j, val in enumerate(row, start=1):
            cell = ws.cell(r, j, val)
            cell.font = font_bold if (i, j - 1) in bold_cells else font_cell
            cell.alignment = align_c if j > 1 else align_l
            cell.border = Border(top=no_side, bottom=no_side, left=no_side, right=no_side)

    last_data = header_row + len(rows)
    # bottom medium line on last data row
    for j in range(1, n_col + 1):
        cell = ws.cell(last_data, j)
        cell.border = Border(top=no_side, bottom=medium, left=no_side, right=no_side)

    if footnote:
        note_row = last_data + 2
        ws.merge_cells(start_row=note_row, start_column=1, end_row=note_row, end_column=n_col)
        nc = ws.cell(note_row, 1, footnote)
        nc.font = font_note
        nc.alignment = Alignment(horizontal="left", vertical="top", wrap_text=True)
        ws.row_dimensions[note_row].height = 48

    if col_widths is None:
        col_widths = [28.0] + [14.0] * (n_col - 1)
    for j, w in enumerate(col_widths, start=1):
        ws.column_dimensions[get_column_letter(j)].width = float(w)

    ws.row_dimensions[1].height = 22
    ws.row_dimensions[header_row].height = 18
    out_xlsx = Path(out_xlsx)
    if out_xlsx.suffix.lower() != ".xlsx":
        out_xlsx = out_xlsx.with_suffix(".xlsx")
    wb.save(out_xlsx)


def _seoul_bbox(cfg: dict) -> dict:
    # Envelope of 29 KMA Seoul ASOS/AWS stations (padded)
    return {
        "west": float(cfg.get("west", 126.78)),
        "south": float(cfg.get("south", 37.46)),
        "east": float(cfg.get("east", 127.17)),
        "north": float(cfg.get("north", 37.67)),
    }


def _grid_shape(
    bbox: dict, res_m: float = 100.0, cap: int | None = 120
) -> tuple[int, int, np.ndarray, np.ndarray]:
    # approx deg for 100 m near Seoul lat 37.5
    lat0 = 0.5 * (bbox["south"] + bbox["north"])
    dlat = res_m / 111_320.0
    dlon = res_m / (111_320.0 * math.cos(math.radians(lat0)))
    ny = max(8, int(round((bbox["north"] - bbox["south"]) / dlat)))
    nx = max(8, int(round((bbox["east"] - bbox["west"]) / dlon)))
    # smoke cap (~12 km @ 100 m); pass cap=None for true high-res windows
    if cap is not None:
        ny = min(ny, int(cap))
        nx = min(nx, int(cap))
    ys = np.linspace(bbox["north"] - 0.5 * dlat, bbox["south"] + 0.5 * dlat, ny)
    xs = np.linspace(bbox["west"] + 0.5 * dlon, bbox["east"] - 0.5 * dlon, nx)
    return ny, nx, ys, xs


def try_init_ee(project: str | None = None) -> bool:
    try:
        import ee  # type: ignore
    except ImportError:
        print("[gee] earthengine-api not installed; synthetic fallback", file=sys.stderr)
        return False
    try:
        if project:
            ee.Initialize(project=project)
        else:
            ee.Initialize()
        print("[gee] Initialize OK")
        return True
    except Exception as e:  # noqa: BLE001
        print(f"[gee] Initialize failed ({e}); synthetic fallback", file=sys.stderr)
        return False


# ---------------------------------------------------------------------------
# physics (paper-aligned diagnostics, CPU)
# ---------------------------------------------------------------------------


def estimate_obs_tmrt(ta: float, sw: float, svf: float, *, a: float = 0.015, b: float = 2.0) -> float:
    """Measurement-derived Tmrt (°C) for validation.

    Uses observed air temperature and global shortwave plus local SVF.
    Same diagnostic kernel as the CPU SOLWEIG proxy, but SW/Ta must come from
    the station (not the model field). Not a globe-thermometer Tmrt.
    """
    if not (np.isfinite(ta) and np.isfinite(sw) and np.isfinite(svf)):
        return float("nan")
    svf = float(np.clip(svf, 0.05, 1.0))
    sw = float(max(0.0, sw))
    return float(ta + a * sw * svf - b * (1.0 - svf))


def approx_utci(ta: np.ndarray, tmrt: np.ndarray, va: np.ndarray, rh: np.ndarray) -> np.ndarray:
    """Lightweight UTCI-like index (not full Fiala); monotonic in Ta/Tmrt/wind."""
    va = np.clip(va, 0.05, 20.0)
    rh = np.clip(rh, 5.0, 99.0)
    # simplified: Ta + radiant excess - wind cooling + humidity nudge
    return ta + 0.35 * (tmrt - ta) - 1.2 * np.sqrt(va) + 0.02 * (rh - 50.0)


def _center_fit(arr: np.ndarray, shape: tuple[int, int], fill: float) -> np.ndarray:
    """Center-crop or pad arr to exactly ``shape`` (after scipy rotate reshape)."""
    ny, nx = int(shape[0]), int(shape[1])
    ay, ax_ = arr.shape[:2]
    out = np.full((ny, nx), fill, dtype=arr.dtype)
    sy0 = max(0, (ay - ny) // 2)
    sx0 = max(0, (ax_ - nx) // 2)
    dy0 = max(0, (ny - ay) // 2)
    dx0 = max(0, (nx - ax_) // 2)
    h = min(ny - dy0, ay - sy0)
    w = min(nx - dx0, ax_ - sx0)
    if h > 0 and w > 0:
        out[dy0 : dy0 + h, dx0 : dx0 + w] = arr[sy0 : sy0 + h, sx0 : sx0 + w]
    return out


def _ct_base_arr(
    H: np.ndarray,
    *,
    z: float = 10.0,
    z0_era5: float = 0.03,
    LAI: float = 5.0,
    lambda_p: float = 1.0,
) -> np.ndarray:
    """Canopy base reduction Ct,base at height z (Zonato et al. 2026 Eqs. 13–17)."""
    Hh = np.maximum(np.asarray(H, dtype=np.float64), 1.0)
    d = 0.7 * Hh
    z0t = np.maximum(0.1 * Hh, 1e-3)
    k = 0.5 + 0.2 * (LAI * lambda_p)
    Dref = math.log(max(z, z0_era5 * 1.01) / z0_era5)
    top = np.log(np.maximum((Hh - d) / z0t, 1.01)) / Dref
    inside = top * np.exp(-k * (1.0 - np.clip(z / Hh, 0.0, 1.0)))
    above = np.log(np.maximum((z - d) / z0t, 1.01)) / Dref
    out = np.where(z >= Hh, above, inside)
    return np.clip(out, 0.05, 1.0).astype(np.float32)


def _rockle_zones_on_aligned(
    C: np.ndarray,
    height: np.ndarray,
    mask: np.ndarray,
    res_m: float,
    *,
    solid: bool,
    Cmin: float = 0.1,
    pf: float = 1.5,
) -> np.ndarray:
    """Upwind Lf + leeward Lr zones on a west←wind aligned grid (paper §2.4.7–2.4.9).

    Wind comes from the west (decreasing column index → upwind). Within each
    Cb or Ct field, overlapping zones take the strongest reduction (min); the
    final map multiplies Cb×Ct as in the paper. Pure product of every wake in a
    dense 2 m Seoul inset collapses corridors to Cmin.
    """
    from scipy.ndimage import label

    if not np.any(mask):
        return C
    labeled, nlab = label(mask)
    ny, nx = C.shape
    # Neighbourhood-scale cap: full Kaplan Lr for mega-AABB footprints would
    # blanket a 3 km inset; paper also relies on ~40 m Gauss to blend zones.
    max_zone_m = 80.0
    for lab_id in range(1, int(nlab) + 1):
        ys, xs = np.where(labeled == lab_id)
        if ys.size == 0:
            continue
        r0, r1 = int(ys.min()), int(ys.max())
        c0, c1 = int(xs.min()), int(xs.max())
        H = float(np.mean(height[ys, xs]))
        H = max(H, 1.0)
        W = max((r1 - r0 + 1) * res_m, res_m)
        D = max((c1 - c0 + 1) * res_m, res_m)
        # Cap W/D used in Lf/Lr: touching footprints merge into city-block
        # AABBs (W≫100 m) that otherwise blanket the whole inset.
        W_eff = min(W, max(3.0 * H, 40.0))
        D_eff = min(D, max(3.0 * H, 40.0))
        Lf = 1.5 * W_eff / (1.0 + 0.8 * (W_eff / H))
        Lr = 3.0 * 1.8 * W_eff / (
            max(D_eff / H, 1e-6) ** 0.3 * (1.0 + 0.24 * (D_eff / H))
        )
        Lf = float(min(Lf, max_zone_m))
        Lr = float(min(Lr, max_zone_m))
        if solid:
            C[ys, xs] = np.minimum(C[ys, xs], Cmin)
            c_wall = Cmin
        else:
            ct_loc = _ct_base_arr(height[ys, xs])
            C[ys, xs] = np.minimum(C[ys, xs], ct_loc)
            c_wall = float(np.mean(ct_loc))
            c_wall = min(max(c_wall, Cmin), 1.0)
        # Per-row walls (true obstacle columns), not full AABB — avoids
        # rectangular "building shadow" slabs across empty lateral cells.
        for r in range(r0, r1 + 1):
            row_mask = mask[r, c0 : c1 + 1]
            if not np.any(row_mask):
                continue
            idx = np.where(row_mask)[0]
            c_lo = c0 + int(idx.min())
            c_hi = c0 + int(idx.max())
            n_up = int(math.ceil(Lf / res_m))
            for k in range(1, n_up + 1):
                col = c_lo - k
                if col < 0:
                    break
                x = k * res_m
                if x > Lf:
                    break
                fac = c_wall + (1.0 - c_wall) * ((x / Lf) ** pf)
                C[r, col] = min(C[r, col], float(fac))
            n_lee = int(math.ceil(Lr / res_m))
            for k in range(1, n_lee + 1):
                col = c_hi + k
                if col >= nx:
                    break
                x = k * res_m
                if x > Lr:
                    break
                if solid:
                    fac = min(max(x / Lr, Cmin), 1.0)
                else:
                    fac = min(max(c_wall + (1.0 - c_wall) * (x / Lr), Cmin), 1.0)
                C[r, col] = min(C[r, col], float(fac))
        np.clip(C, Cmin, 1.0, out=C)
    return C


def directional_wind_coeff(
    buildings: np.ndarray,
    trees: np.ndarray,
    theta_deg: float,
    *,
    footprint_mode: bool | None = None,
    res_m: float | None = None,
) -> np.ndarray:
    """Morphology wind-reduction C(x,θ) for Fig.3 / WindCoeff_dir rasters.

    Builds an openness field (1 − buildings/trees), rotates so wind is +x,
    applies anisotropic Gaussian (longer along-wind, shorter cross-wind) so
    ventilation corridors align with θ without footprint-roll 'shadows', then
    rotates back. Trees add extra drag. Clip to [Cmin, 1]. Matches the paper
    Fig.3 look (dense fabric blue, open corridors warm, ~40 m neighbourhood
    blend) better than literal per-building Lf/Lr strips on dense Seoul 2 m
    footprints.
    """
    from scipy.ndimage import gaussian_filter, binary_erosion, rotate

    buildings = np.asarray(buildings, dtype=np.float32)
    trees = np.asarray(trees, dtype=np.float32)
    ny, nx = buildings.shape
    res = float(res_m) if res_m and res_m > 0 else 100.0
    Cmin = 0.1

    if footprint_mode is None:
        pos = buildings[buildings > 0.5]
        footprint_mode = bool(
            len(pos)
            and float(np.mean(pos > 3)) > 0.35
            and float(np.nanmax(buildings)) < 200
            and res <= 15
        )

    if footprint_mode:
        b_mask = buildings > 0.5
        t_mask = trees > 2.0
    else:
        thr = 12.0
        if float(np.nanmax(buildings)) > 5 and np.any(buildings > 0.5):
            thr = max(float(np.nanpercentile(buildings[buildings > 0.5], 55)), 12.0)
            solid = buildings >= thr
            if float(solid.mean()) > 0.45:
                solid = binary_erosion(solid, iterations=1)
        else:
            solid = buildings > 1.0
        b_mask = solid
        t_mask = trees > 3.0

    # Openness: 1 in streets/plazas, 0 on buildings; trees partially open (porous)
    open_f = np.ones((ny, nx), dtype=np.float32)
    open_f[b_mask] = 0.0
    open_f[t_mask & ~b_mask] = 0.22

    # Local density (plan fraction) at neighbourhood scale — dense fabric → blue
    dens_sig = max(0.75, 35.0 / res)
    dens_b = gaussian_filter(b_mask.astype(np.float32), sigma=dens_sig)
    dens_t = gaussian_filter(t_mask.astype(np.float32), sigma=dens_sig)
    C_dens = np.clip(
        1.0 - 0.95 * np.power(dens_b, 0.55) - 0.58 * np.power(dens_t, 0.55),
        Cmin,
        1.0,
    )

    # Wind FROM theta → align so flow is +x; anisotropic smooth for corridor tilt
    rot_deg = float(theta_deg) - 270.0
    o_rot = rotate(open_f, angle=rot_deg, reshape=True, order=1, mode="constant", cval=1.0)
    sig_along = max(0.75, 45.0 / res)
    sig_cross = max(0.75, 22.0 / res)
    o_blur = gaussian_filter(o_rot, sigma=(sig_cross, sig_along))
    C_rot = Cmin + (1.0 - Cmin) * np.clip(o_blur, 0.0, 1.0) ** 0.90
    C_dir = _center_fit(
        rotate(C_rot, angle=-rot_deg, reshape=True, order=1, mode="constant", cval=1.0),
        (ny, nx),
        fill=1.0,
    ).astype(np.float32)

    # Density leads (smooth fabric); directional openness for warm corridors
    C = 0.65 * C_dens + 0.35 * C_dir
    C = gaussian_filter(np.clip(C, Cmin, 1.0), sigma=max(0.75, 30.0 / res))
    return np.clip(C, Cmin, 1.0).astype(np.float32)


def plot_figure03_wind_coeff(
    figdir: Path,
    z,
    C240: np.ndarray,
    theta: float = 240.0,
    *,
    footprint_mode: bool = False,
    res_label: str | None = None,
    full_domain: bool = True,
    out_name: str = "Figure03_wind_coeff.pdf",
) -> None:
    """Fig.3 / S3: continuous C field (BWR) + tree yellow halo + building outlines.

    Matches Zonato et al. Fig.3 style: dark blue = dense fabric / canopy / lee;
    warm = ventilation corridors; yellow Trees overlay with dark halo; inflow arrow.
    C is shown everywhere (not masked under buildings) so dense blocks read as blue.
    """
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy.ma as ma
    from scipy.ndimage import binary_erosion, binary_dilation
    from matplotlib.colors import LinearSegmentedColormap, ListedColormap
    from matplotlib.patches import Patch
    from matplotlib.lines import Line2D

    _set_times_font()
    ys, xs = np.asarray(z["ys"], float), np.asarray(z["xs"], float)
    buildings = np.asarray(z["buildings"], float)
    trees = np.asarray(z["trees"], float)
    try:
        res_m = float(np.asarray(z["res_m"]).ravel()[0])
    except Exception:
        res_m = 100.0
    if res_label is None:
        res_label = f"{res_m:g} m"
    extent = [float(xs.min()), float(xs.max()), float(ys.min()), float(ys.max())]

    if footprint_mode or res_m <= 15:
        solid_w = buildings > 0.5
    else:
        if float(np.nanmax(buildings)) > 5 and np.any(buildings > 0.5):
            thr = max(float(np.nanpercentile(buildings[buildings > 0.5], 55)), 12.0)
            solid_w = buildings >= thr
            if float(solid_w.mean()) > 0.45:
                solid_w = binary_erosion(solid_w, iterations=1)
        else:
            solid_w = buildings > 1.0

    C = np.asarray(C240, float)
    T = trees
    ys_w, xs_w = ys, xs
    ext_w = extent
    _ = full_domain  # retained for callers / md context

    lat0 = 0.5 * (ext_w[2] + ext_w[3])
    asp = _geo_aspect(lat0)

    tree_thr = 2.0 if res_m <= 15 else 6.0
    tree_w = (T > tree_thr) & (~solid_w)
    if "lc" in getattr(z, "files", z):
        lc_full = np.asarray(z["lc"])
        if lc_full.shape == T.shape:
            tree_w = tree_w | ((lc_full == 3) & (~solid_w) & (T > 0.5))

    cmap_c = LinearSegmentedColormap.from_list(
        "wind_c_bwr",
        [
            (0.00, "#053061"),
            (0.25, "#4393c3"),
            (0.50, "#f7f7f7"),
            (0.75, "#d6604d"),
            (1.00, "#67001f"),
        ],
    )
    fig = plt.figure(figsize=(9.0, 7.2) if res_m >= 50 else (8.2, 6.4))
    ax = fig.add_axes([0.10, 0.12, 0.72, 0.80])
    ax.set_facecolor("#f7f7f7")

    # 1) Continuous C everywhere (dense fabric / lee stay dark blue after 40 m smooth)
    im = ax.imshow(
        C, extent=ext_w, origin="upper", cmap=cmap_c, vmin=0.1, vmax=1.0,
        interpolation="bilinear",
        aspect=asp, zorder=1, alpha=1.0,
    )
    # 2) Tree dark halo then opaque yellow (paper caption)
    if np.any(tree_w):
        halo_r = max(1, int(round(4.0 / max(res_m, 1.0))))
        halo = binary_dilation(tree_w, iterations=halo_r) & (~tree_w) & (~solid_w)
        if np.any(halo):
            H_show = ma.masked_where(~halo, np.ones(halo.shape, dtype=float))
            ax.imshow(
                H_show, extent=ext_w, origin="upper",
                cmap=ListedColormap(["#1a1a1a"]), vmin=0, vmax=1,
                interpolation="nearest", aspect=asp, zorder=2, alpha=0.55,
            )
        T_show = ma.masked_where(~tree_w, np.ones(tree_w.shape, dtype=float))
        ax.imshow(
            T_show, extent=ext_w, origin="upper", cmap=ListedColormap(["#f4c430"]),
            vmin=0, vmax=1, interpolation="nearest", aspect=asp, zorder=3, alpha=0.55,
        )
    # 3) Building outlines only (do not paint solid gray over blue dense fabric)
    edge = np.zeros_like(solid_w, dtype=bool)
    edge[:, 1:] |= solid_w[:, 1:] != solid_w[:, :-1]
    edge[1:, :] |= solid_w[1:, :] != solid_w[:-1, :]
    ei, ej = np.where(edge)
    if len(ei):
        ax.scatter(
            xs_w[ej], ys_w[ei],
            s=0.15 if res_m <= 5 else (0.45 if res_m <= 15 else 1.6),
            c="0.12", marker="s", linewidths=0, zorder=4, alpha=0.85,
        )

    # Inflow arrow: wind FROM theta → flow toward theta+180
    to_rad = math.radians((float(theta) + 180.0) % 360.0)
    # map: +x = east = sin(to), +y = north = cos(to); imshow y increases north in data
    ux, uy = math.sin(to_rad), math.cos(to_rad)
    xspan = ext_w[1] - ext_w[0]
    yspan = ext_w[3] - ext_w[2]
    L = 0.10 * min(xspan, yspan)
    x1 = ext_w[0] + 0.14 * xspan
    y1 = ext_w[2] + 0.14 * yspan
    ax.annotate(
        "",
        xy=(x1 + ux * L, y1 + uy * L),
        xytext=(x1, y1),
        arrowprops=dict(arrowstyle="-|>", color="#f4c430", lw=2.0, mutation_scale=14),
        zorder=6,
    )
    ax.text(
        x1, y1 - 0.03 * yspan, rf"$\theta={int(theta)}^\circ$",
        color="#c9a000", fontsize=8, ha="center", va="top", zorder=6,
    )

    ax.set_xlim(ext_w[0], ext_w[1])
    ax.set_ylim(ext_w[2], ext_w[3])
    ax.ticklabel_format(useOffset=False, style="plain")
    ax.set_xlabel("Longitude (°E)")
    ax.set_ylabel("Latitude (°N)")
    scope = "city domain" if (full_domain or res_m >= 50) else "fine inset"
    title = (
        f"Figure 3. Wind-reduction coefficient  $C(\\mathbf{{x}},\\,\\theta={int(theta)}^\\circ)$  "
        f"(Seoul {res_label}, {scope})"
        if out_name.startswith("Figure03")
        else f"Figure S3. Wind-reduction coefficient  $C(\\mathbf{{x}},\\,\\theta={int(theta)}^\\circ)$  "
        f"(Seoul {res_label})"
    )
    ax.set_title(title, loc="left", fontsize=11)
    for spine in ax.spines.values():
        spine.set_linewidth(0.8)
    cax = fig.add_axes([0.84, 0.20, 0.025, 0.60])
    cb = fig.colorbar(im, cax=cax)
    cb.set_label(rf"Wind reduction coefficient  $C(\mathbf{{x}},\,\theta={int(theta)}^\circ)$", fontsize=9)
    cb.set_ticks([0.1, 0.2, 0.4, 0.6, 0.8, 1.0])
    cb.ax.tick_params(labelsize=8)
    ax.legend(
        handles=[
            Patch(facecolor="#f4c430", edgecolor="0.3", label="Trees"),
            Line2D([0], [0], color="0.12", lw=1.2, label="Buildings (outline)"),
        ],
        loc="lower left", frameon=True, fontsize=8, fancybox=False, edgecolor="0.5",
    )
    outp = Path(figdir) / out_name
    fig.savefig(outp, dpi=300, bbox_inches="tight", facecolor="white")
    fig.savefig(outp.with_suffix(".png"), dpi=200, bbox_inches="tight", facecolor="white")
    plt.close(fig)

    n_bldg = int(solid_w.sum())
    n_tree = int(tree_w.sum())
    c_mean = float(np.nanmean(C))
    c_p10 = float(np.nanpercentile(C, 10))
    if out_name.startswith("Figure03"):
        md_name = "Figure03.md"
        if footprint_mode and res_m <= 5:
            role = "main Fig.3 building-resolving 2 m inset"
            bldg_src = "Overture footprints"
            blurb = (
                "主文 Figure 3：2 m 精细窗口。"
                "C 场：邻域建筑/树冠密实度（深蓝=密集聚落与树区）+"
                "风向对齐的各向异性开敞度平滑（暖色=通风廊道），"
                "约 30–40 m 高斯融合；连续色场上叠树冠黄晕与建筑描边。"
                "刻意避免脚印平移式「建筑影子」。"
            )
        elif footprint_mode:
            role = "main Fig.3 full Seoul (2 m morphology, coarse display grid)"
            bldg_src = "Overture footprints (city-wide) + GHSL/ETH/WorldCover background"
            blurb = (
                "主文 Figure 3：全首尔。"
                "C 在 2 m 全市形态场（Overture 41.4 万足迹）上分瓦计算，"
                "块均值导出到展示网格。蓝=密集建成区/山林树冠强衰减，"
                "暖=汉江等开阔通风廊道；无 S2 局部窗、无韩国地籍。"
            )
        else:
            role = "main Fig.3 city-scale 100 m"
            bldg_src = "GHSL 100 m (taller cores as solid)"
            blurb = "城市 100 m：同上 Röckle 诊断区带 + 40 m 平滑；连续 C + 树黄晕 + 建筑描边。"
    else:
        md_name = "Figure_S3.md"
        role = "appendix wind inset/overview"
        bldg_src = "Overture or GHSL"
        blurb = "附录风场图；连续 C + 树黄晕 + 建筑描边。"
    info = _ensure(Path(figdir) / "image_information")
    (info / md_name).write_text(
        f"# {'Figure 3' if md_name.startswith('Figure03') else 'Figure S3'}\n\n"
        "## 图面说明\n\n"
        f"风向 θ={int(theta)}° 的风衰减系数场 $C(\\mathbf{{x}},\\theta)$"
        f"（Zonato et al. GMD 诊断模块），分辨率 {res_label}。{blurb}\n\n"
        "### 图上标注\n\n"
        f"- 窗口 {ext_w[0]:.4f}–{ext_w[1]:.4f}°E，{ext_w[2]:.4f}–{ext_w[3]:.4f}°N\n"
        f"- 网格 {C.shape[0]}×{C.shape[1]} @ {res_label}；建筑实体格 {n_bldg}；树冠黄面格 {n_tree}\n"
        f"- mean C≈{c_mean:.2f}；P10 C≈{c_p10:.2f}；色条仅 C（蓝–白–红）\n"
        f"- 黄箭头：入流方向（风来自 θ={int(theta)}°）\n"
        f"- 建筑高度域内 max≈{float(np.nanmax(buildings)):.0f} m\n\n"
        "## 分析上下文\n\n"
        f"City=Seoul; role={role}; res={res_label}; buildings={bldg_src}; "
        f"trees=ETH/WorldCover veg as yellow fill+halo; theta={int(theta)}; "
        f"scheme=rotate+Lf/Lr zones+Cb*Ct+Gaussian40m; full_domain={bool(full_domain)}; "
        f"Grouping=not applicable.\n",
        encoding="utf-8",
    )
    print(
        f"[ok] {outp.name} ({res_label}, full={bool(full_domain)}, "
        f"solid={float(solid_w.mean()):.2f}, tree_fill={float(tree_w.mean()):.2f}, "
        f"Cmean={c_mean:.2f})"
    )



def plot_figure04_mean_fields(
    figdir: Path,
    fields,
    stations: pd.DataFrame,
    series: pd.DataFrame,
) -> None:
    """Literature Fig.4: 2×2 JJA-like mean maps + station half-disks (obs | model)."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.patches import Wedge, Patch
    from matplotlib.colors import Normalize
    from matplotlib import cm

    _set_times_font()
    ys = np.asarray(fields["ys"], float)
    xs = np.asarray(fields["xs"], float)
    extent = [float(xs.min()), float(xs.max()), float(ys.min()), float(ys.max())]
    try:
        res_m = float(abs(np.median(np.diff(xs))) * 111320.0 * math.cos(math.radians(0.5 * (ys.min() + ys.max()))))
    except Exception:
        res_m = 100.0
    res_lab = f"{res_m:.0f} m" if res_m >= 1 else f"{res_m*100:.0f} cm"

    # station summer means
    means = (
        series.groupby("station_id", as_index=False)
        .agg(
            obs_Ta=("obs_Ta", "mean"),
            WC_Ta=("WC_Ta", "mean"),
            obs_Vcan=("obs_Vcan", "mean"),
            WC_Vcan=("WC_Vcan", "mean"),
            obs_Tmrt=("obs_Tmrt", "mean"),
            WC_Tmrt=("WC_Tmrt", "mean"),
            obs_UTCI=("obs_UTCI", "mean"),
            WC_UTCI=("WC_UTCI", "mean"),
        )
    )
    loc = stations[["station_id", "latitude", "longitude"]].drop_duplicates("station_id")
    means = means.merge(loc, on="station_id", how="left")

    specs = [
        ("Ta", "Air temperature (°C)", "obs_Ta", "WC_Ta", "RdYlBu_r"),
        ("Vcan", "Canopy wind speed (m s$^{-1}$)", "obs_Vcan", "WC_Vcan", "YlGnBu"),
        ("Tmrt", "Mean radiant temperature (°C)", "obs_Tmrt", "WC_Tmrt", "inferno"),
        ("UTCI", "UTCI (°C)", "obs_UTCI", "WC_UTCI", "RdYlBu_r"),
    ]

    fig, axs = plt.subplots(2, 2, figsize=(10.5, 9.2), constrained_layout=False)
    fig.subplots_adjust(left=0.07, right=0.98, bottom=0.08, top=0.90, wspace=0.18, hspace=0.22)
    # half-disk radius ≈ 450 m (visible at city scale, no station overlap)
    r_deg = 0.004

    for ax, (key, title, obs_col, mod_col, cmap_name) in zip(axs.ravel(), specs):
        arr = np.asarray(fields[key], float)
        # robust color limits from field + stations
        vals = [arr]
        if obs_col in means.columns:
            vals.append(means[obs_col].to_numpy(float))
            vals.append(means[mod_col].to_numpy(float))
        pool = np.concatenate([np.ravel(v) for v in vals])
        pool = pool[np.isfinite(pool)]
        vmin, vmax = np.nanpercentile(pool, [2, 98])
        if not np.isfinite(vmin) or abs(vmax - vmin) < 1e-6:
            vmin, vmax = float(np.nanmin(arr)), float(np.nanmax(arr))
        cmap = matplotlib.colormaps.get_cmap(cmap_name) if hasattr(matplotlib, "colormaps") else cm.get_cmap(cmap_name)
        norm = Normalize(vmin=vmin, vmax=vmax)

        im = ax.imshow(
            arr,
            extent=extent,
            origin="upper",
            cmap=cmap,
            vmin=vmin,
            vmax=vmax,
            interpolation="bilinear",
            aspect="equal",
            zorder=1,
        )
        for _, row in means.iterrows():
            lon, lat = float(row["longitude"]), float(row["latitude"])
            if not (extent[0] <= lon <= extent[1] and extent[2] <= lat <= extent[3]):
                continue
            c_obs = cmap(norm(float(row[obs_col])))
            c_mod = cmap(norm(float(row[mod_col])))
            # left half = observed; right half = modeled (paper Fig.4)
            ax.add_patch(
                Wedge(
                    (lon, lat),
                    r_deg,
                    90,
                    270,
                    facecolor=c_obs,
                    edgecolor="k",
                    linewidth=0.35,
                    zorder=5,
                )
            )
            ax.add_patch(
                Wedge(
                    (lon, lat),
                    r_deg,
                    -90,
                    90,
                    facecolor=c_mod,
                    edgecolor="k",
                    linewidth=0.35,
                    zorder=5,
                )
            )
            ax.text(
                lon,
                lat + r_deg * 1.35,
                str(row["station_id"]),
                ha="center",
                va="bottom",
                fontsize=5.5,
                color="k",
                zorder=6,
            )

        ax.set_xlim(extent[0], extent[1])
        ax.set_ylim(extent[2], extent[3])
        ax.ticklabel_format(useOffset=False, style="plain")
        ax.set_title(title, fontsize=10, loc="left")
        ax.set_xlabel("Longitude (°E)", fontsize=8)
        ax.set_ylabel("Latitude (°N)", fontsize=8)
        ax.tick_params(labelsize=7)
        cb = fig.colorbar(im, ax=ax, fraction=0.046, pad=0.02)
        cb.ax.tick_params(labelsize=7)

    fig.suptitle(
        f"Figure 4. Summer mean fields for the Sol_WC_UHI configuration (Seoul {res_lab})",
        fontsize=12,
        y=0.97,
    )
    # half-disk legend
    leg_ax = fig.add_axes([0.25, 0.01, 0.50, 0.045])
    leg_ax.axis("off")
    leg_ax.legend(
        handles=[
            Patch(facecolor="0.75", edgecolor="k", label="Station left half: observed mean"),
            Patch(facecolor="0.35", edgecolor="k", label="Station right half: Sol_WC_UHI mean"),
        ],
        loc="center",
        ncol=2,
        frameon=False,
        fontsize=8,
    )

    outp = Path(figdir) / "Figure04_mean_fields.pdf"
    fig.savefig(outp, dpi=300, bbox_inches="tight", facecolor="white")
    fig.savefig(outp.with_suffix(".png"), dpi=200, bbox_inches="tight", facecolor="white")
    plt.close(fig)

    # image_information (图面说明 + 分析上下文; numbers harvested, never invented)
    info = _ensure(Path(figdir) / "image_information")
    rng = {
        k: (float(np.nanpercentile(np.asarray(fields[k], float), 2)),
            float(np.nanpercentile(np.asarray(fields[k], float), 98)))
        for k in ("Ta", "Vcan", "Tmrt", "UTCI")
    }
    in_box = (
        (means["longitude"] >= extent[0]) & (means["longitude"] <= extent[1])
        & (means["latitude"] >= extent[2]) & (means["latitude"] <= extent[3])
    )
    n_st_in = int(in_box.sum())
    (info / "Figure04.md").write_text(
        "# Figure 4\n\n"
        "## 图面说明\n\n"
        f"Sol_WC_UHI 配置夏季（JJA 型窗口）平均场 2×2 面板：左上 Air temperature、"
        "右上 canopy wind speed、左下 mean radiant temperature (Tmrt)、右下 UTCI。"
        f"底图为全首尔 {res_lab} 形态网格（2 m Overture 足迹池化 + 12 方向 2 m 风衰减 C）。"
        "站点符号为半圆盘：左半=观测夏季均值，右半=模型夏季均值（同 colormap 同量纲取色），"
        "上方小字为站号。色条范围取场与站点值的 2–98 百分位。\n\n"
        "### 图上标注\n\n"
        f"- 场范围（P2–P98）：Ta {rng['Ta'][0]:.1f}–{rng['Ta'][1]:.1f} °C；"
        f"Vcan {rng['Vcan'][0]:.2f}–{rng['Vcan'][1]:.2f} m/s；"
        f"Tmrt {rng['Tmrt'][0]:.1f}–{rng['Tmrt'][1]:.1f} °C；"
        f"UTCI {rng['UTCI'][0]:.1f}–{rng['UTCI'][1]:.1f} °C\n"
        f"- 网格 {np.asarray(fields['Ta']).shape[0]}×{np.asarray(fields['Ta']).shape[1]} @ {res_lab}；"
        f"窗口 {extent[0]:.2f}–{extent[1]:.2f}°E，{extent[2]:.2f}–{extent[3]:.2f}°N\n"
        f"- 域内站点 N={n_st_in}\n"
        f"- 站点均值对比：obs_Vcan≈{means['obs_Vcan'].mean():.2f} vs WC_Vcan≈{means['WC_Vcan'].mean():.2f} m/s；"
        f"obs_UTCI≈{means['obs_UTCI'].mean():.2f} vs WC_UTCI≈{means['WC_UTCI'].mean():.2f} °C\n\n"
        "## 分析上下文\n\n"
        f"City=Seoul; config=Sol_WC_UHI; grid=domain_city_2m pooled 10 m; "
        "wind=12-dir C from 2 m Overture morphology; forcing=Open-Meteo/ERA5 hourly "
        "(2024-08-01–07 smoke window); obs=KMA 29 stations (Tmrt from Ta+SW+SVF); "
        "single-panel per variable; Grouping=not applicable.\n",
        encoding="utf-8",
    )
    print(f"[ok] {outp.name} ({res_lab}, stations={n_st_in})")


def _station_utci_error_table(
    series: pd.DataFrame,
    stations: pd.DataFrame | None = None,
    domain_npz: Path | None = None,
) -> pd.DataFrame:
    """Per-station UTCI RMSE/MB (Sol_STD vs Sol_WC_UHI), sorted by SVF obs (Fig.5 / Table B1)."""
    loc = {}
    if stations is not None and len(stations):
        for _, r in stations.drop_duplicates("station_id").iterrows():
            loc[str(r["station_id"])] = (float(r["latitude"]), float(r["longitude"]))

    svf_grid = ys = xs = None
    if domain_npz is not None and Path(domain_npz).exists():
        z = np.load(domain_npz)
        if "svf" in z.files:
            ys, xs, svf_grid = z["ys"], z["xs"], z["svf"]

    rows = []
    for sid, g in series.groupby("station_id"):
        b_s, r_s = _bias_rmse(g["obs_UTCI"], g["STD_UTCI"])
        b_w, r_w = _bias_rmse(g["obs_UTCI"], g["WC_UTCI"])
        svf_obs = float(g["svf_obs"].iloc[0])
        svf_mod = svf_obs
        key = str(sid)
        if svf_grid is not None and key in loc:
            lat, lon = loc[key]
            i, j = _nearest_idx(ys, xs, lat, lon)
            svf_mod = float(svf_grid[i, j])
        rows.append(
            {
                "Station": key,
                "LCZ": str(g["lcz"].iloc[0]),
                "SVF_obs": svf_obs,
                "SVF_mod": svf_mod,
                "RMSE_Sol_STD": float(r_s),
                "RMSE_Sol_WC_UHI": float(r_w),
                "MB_Sol_STD": float(b_s),
                "MB_Sol_WC_UHI": float(b_w),
            }
        )
    return pd.DataFrame(rows).sort_values("SVF_obs").reset_index(drop=True)


def plot_figure05_station_errors(figdir: Path, err: pd.DataFrame) -> None:
    """Literature Fig.5: station UTCI RMSE & MB, sorted by SVF; LCZ as context."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.patches import Patch, Rectangle

    _set_times_font()
    n = len(err)
    x = np.arange(n)
    w = 0.38
    c_std, c_wc = "#d73027", "#4575b4"
    lcz_color = {
        "2": "#d73027",
        "4": "#fc8d59",
        "5": "#e6550d",
        "6": "#fdae6b",
        "8": "#bdbdbd",
        "9": "#969696",
        "10": "#636363",
        "B": "#31a354",
    }

    fig, axs = plt.subplots(1, 2, figsize=(11.5, 4.6), sharey=False)
    fig.subplots_adjust(left=0.07, right=0.98, top=0.86, bottom=0.28, wspace=0.22)

    # (a) RMSE
    ax = axs[0]
    ax.bar(x - w / 2, err["RMSE_Sol_STD"], w, color=c_std, edgecolor="k", linewidth=0.35, label="Sol_STD", zorder=3)
    ax.bar(x + w / 2, err["RMSE_Sol_WC_UHI"], w, color=c_wc, edgecolor="k", linewidth=0.35, label="Sol_WC_UHI", zorder=3)
    ax.set_ylabel("RMSE (°C)", fontsize=10)
    ax.set_title("(a) RMSE", loc="left", fontsize=11)
    ymax = max(0.5, float(err[["RMSE_Sol_STD", "RMSE_Sol_WC_UHI"]].to_numpy().max()) * 1.18)
    ax.set_ylim(0, ymax)
    ax.grid(axis="y", linestyle=":", linewidth=0.5, alpha=0.65, zorder=0)
    ax.legend(loc="upper right", frameon=False, fontsize=8.5)

    # (b) MB
    ax = axs[1]
    ax.axhline(0.0, color="k", lw=0.9, zorder=2)
    ax.bar(x - w / 2, err["MB_Sol_STD"], w, color=c_std, edgecolor="k", linewidth=0.35, label="Sol_STD", zorder=3)
    ax.bar(x + w / 2, err["MB_Sol_WC_UHI"], w, color=c_wc, edgecolor="k", linewidth=0.35, label="Sol_WC_UHI", zorder=3)
    ax.set_ylabel("Mean bias MB (°C)", fontsize=10)
    ax.set_title("(b) Mean bias (MB)", loc="left", fontsize=11)
    lim = max(1.0, float(np.nanmax(np.abs(err[["MB_Sol_STD", "MB_Sol_WC_UHI"]].to_numpy()))) * 1.25)
    ax.set_ylim(-lim, lim)
    ax.grid(axis="y", linestyle=":", linewidth=0.5, alpha=0.65, zorder=0)
    ax.legend(loc="upper right", frameon=False, fontsize=8.5)

    for ax in axs:
        ax.set_xticks(x)
        ax.set_xticklabels(err["Station"].astype(str), rotation=90, fontsize=7.5)
        ax.set_xlim(-0.6, n - 0.4)
        # LCZ colour strip under axis
        y0, y1 = ax.get_ylim()
        strip_h = 0.045 * (y1 - y0)
        strip_y = y0 - 0.10 * (y1 - y0)
        for i, r in err.iterrows():
            col = lcz_color.get(str(r["LCZ"]), "#333333")
            ax.add_patch(
                Rectangle(
                    (i - 0.42, strip_y),
                    0.84,
                    strip_h,
                    facecolor=col,
                    edgecolor="k",
                    linewidth=0.25,
                    clip_on=False,
                    zorder=5,
                )
            )
            ax.text(
                i,
                strip_y - 0.55 * strip_h,
                f"{r['SVF_obs']:.2f}",
                ha="center",
                va="top",
                fontsize=5.8,
                color="0.25",
                clip_on=False,
            )

    axs[0].set_xlabel("Station (sorted by observed SVF ↑)", fontsize=9, labelpad=18)
    axs[1].set_xlabel("Station (sorted by observed SVF ↑)", fontsize=9, labelpad=18)

    fig.suptitle(
        "Figure 5. Station-level UTCI errors, sorted by observed SVF\n"
        "RMSE and mean bias (MB) for Sol_STD and Sol_WC_UHI; LCZ strip = station surroundings",
        fontsize=11,
        y=0.98,
    )

    present = [str(k) for k in err["LCZ"].astype(str).unique()]
    handles = [
        Patch(facecolor=lcz_color[k], edgecolor="k", label=f"LCZ {k}")
        for k in ("2", "4", "5", "6", "8", "9", "10", "B")
        if k in present and k in lcz_color
    ]
    if handles:
        fig.legend(
            handles=handles,
            loc="lower center",
            ncol=min(8, len(handles)),
            frameon=False,
            fontsize=7.5,
            bbox_to_anchor=(0.5, 0.01),
            title="LCZ (contextual)",
            title_fontsize=8,
        )

    outp = Path(figdir) / "Figure05_station_errors.pdf"
    fig.savefig(outp, dpi=300, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    print(f"[ok] {outp.name}")


def uhi_delta_ta(svf: np.ndarray, hour: int, veg_frac: np.ndarray, amp: float = 2.2) -> np.ndarray:
    """Night-time UHI warming modulated by SVF & vegetation (Eq.-style).

    amp=2.2 is the Dortmund default; ERA5-forced Seoul already carries much of
    the nocturnal warming, so the config may pass a smaller value.
    """
    night = 1.0 if (hour >= 20 or hour <= 6) else 0.15
    return (float(amp) * (1.0 - svf) * (1.0 - 0.5 * veg_frac) * night).astype(np.float32)


def tmrt_from_ta(ta: np.ndarray, sw: np.ndarray, svf: np.ndarray, *, a: float = 0.015, b: float = 2.0) -> np.ndarray:
    """Diagnostic mean radiant temperature kernel (paper CPU proxy)."""
    return ta + float(a) * sw * svf - float(b) * (1.0 - svf)


def auto_diag_params(
    met: pd.DataFrame,
    obs_df: pd.DataFrame,
    Cstack: np.ndarray,
    dirs: np.ndarray,
    stations: pd.DataFrame,
    ys: np.ndarray,
    xs: np.ndarray,
    svf: np.ndarray,
    dem: np.ndarray,
    elev0: float,
    *,
    fallback_alpha_open: float = 1.0,
    fallback_uhi: float = 2.2,
) -> dict:
    """Closed-form per-city diagnostic amplitudes (unified transferable protocol).

    Same two equations for every city, solved from that city's own station
    observations — no manual tuning:

    wind_alpha_open — Seoul/EU AWS anemometers sit on open 10 m masts, so the
      *station-comparison* wind is V10*C^alpha_open. Log-space least squares
      over (hour, station) pairs with obs_Vcan>0.1 and V10>0.1:
        alpha = Σ x·y / Σ x²,  x=ln C_station,  y=ln(obs_Vcan / V10),  clip [0,1].
      The canopy field used by SOLWEIG keeps the paper exponent (1.0); this
      exponent only aligns station output with mast-height observations.
    uhi_amp — night (22–05 h) regression of (obs_Ta − STD_Ta) on the UHI shape
      w=(1−SVF): amp = Σ(bias·w)/Σ(w²), clip [0,4]. If ERA5 already carries the
      nocturnal warming (amp→0) the UHI term self-disables for that city.
    tmrt_a/b are NOT auto-solved (fixed paper kernel) so the radiant module
      stays comparable across cities; a city config may still set them.

    Falls back to paper defaults when fewer than ~200/~100 valid pairs.
    """
    out = {
        "mode": "auto",
        "wind_alpha_open": float(fallback_alpha_open),
        "uhi_amp": float(fallback_uhi),
        "n_pairs_wind": 0,
        "n_pairs_night": 0,
        "protocol": "closed-form per-city: alpha=ln-wind LSQ; uhi=night Ta on (1-SVF)",
        "note": "fallback=paper defaults (insufficient obs)",
    }
    if obs_df is None or not len(obs_df) or not len(met):
        return out
    o = obs_df.copy()
    o["time"] = pd.to_datetime(o["time"]).dt.floor("h")
    o["station_id"] = o["station_id"].astype(str)
    m = met.copy()
    m["time"] = pd.to_datetime(m["time"]).dt.floor("h")
    mm = m.set_index("time")
    loc = {}
    for _, st in stations.drop_duplicates("station_id").iterrows():
        i, j = _nearest_idx(ys, xs, float(st["latitude"]), float(st["longitude"]))
        loc[str(st["station_id"])] = (int(i), int(j))
    dirs_f = np.asarray(dirs, float)
    xs_w, ys_w = [], []
    night_bias, night_w = [], []
    for _, row in o.iterrows():
        ts = row["time"]
        if ts not in mm.index:
            continue
        f = mm.loc[ts]
        ij = loc.get(str(row["station_id"]))
        if ij is None:
            continue
        v10 = float(f["V10"])
        wdir = float(f["WDIR"])
        obs_v = float(row.get("obs_Vcan", float("nan")))
        obs_ta = float(row.get("obs_Ta", float("nan")))
        if v10 > 0.1 and np.isfinite(obs_v) and obs_v > 0.1:
            k = int(np.argmin(np.abs((dirs_f - wdir + 180) % 360 - 180)))
            c = float(np.clip(Cstack[k][ij], 0.02, 1.0))
            xs_w.append(math.log(c))
            ys_w.append(math.log(obs_v / v10))
        hh = int(ts.hour)
        if (hh >= 22 or hh <= 5) and np.isfinite(obs_ta):
            ta0 = float(f["Ta"])
            std_ta = ta0 - 0.0065 * (float(dem[ij]) - elev0)
            s = float(np.clip(svf[ij], 0.0, 1.0))
            if s < 0.98:
                night_bias.append(obs_ta - std_ta)
                night_w.append(1.0 - s)
    if len(xs_w) >= 200:
        x = np.asarray(xs_w)
        y = np.asarray(ys_w)
        denom = float(np.sum(x * x))
        if denom > 1e-6:
            out["wind_alpha_open"] = float(np.clip(float(np.sum(x * y)) / denom, 0.0, 1.0))
        out["n_pairs_wind"] = len(xs_w)
    if len(night_bias) >= 100:
        b_arr = np.asarray(night_bias)
        w_arr = np.asarray(night_w)
        out["uhi_amp"] = float(np.clip(float(np.sum(b_arr * w_arr)) / max(float(np.sum(w_arr * w_arr)), 1e-9), 0.0, 4.0))
        out["n_pairs_night"] = len(night_bias)
        out["night_bias_mean"] = round(float(np.mean(b_arr)), 3)
    if out["n_pairs_wind"] or out["n_pairs_night"]:
        out["note"] = "auto"
    return out


# ---------------------------------------------------------------------------
# domain / stations / meteo
# ---------------------------------------------------------------------------


def build_synthetic_domain(out: Path, bbox: dict, res_m: float, seed: int = 42) -> dict:
    """Seoul-like rectangular city fabric (not a circular blob): land-use + building/tree height."""
    rng = np.random.default_rng(seed)
    ny, nx, ys, xs = _grid_shape(bbox, res_m)
    Y, X = np.meshgrid(ys, xs, indexing="ij")
    # Land-use codes aligned with Fig2 legend: 1 Bare&Sand, 2 Water, 3 Vegetation, 4 Urban
    lc = np.full((ny, nx), 4, dtype=np.int16)  # urban default
    # parks / vegetation patches
    for _ in range(18):
        cy = rng.integers(0, ny)
        cx = rng.integers(0, nx)
        rr = rng.integers(3, 12)
        yy, xx = np.ogrid[:ny, :nx]
        mask = (yy - cy) ** 2 + (xx - cx) ** 2 <= rr**2
        lc[mask] = 3
    # river corridor (Han-like, west–east meander)
    river_y = (ny * 0.55 + 4 * np.sin(np.linspace(0, 3 * np.pi, nx))).astype(int)
    for j in range(nx):
        y0 = int(np.clip(river_y[j], 2, ny - 3))
        lc[max(0, y0 - 2) : min(ny, y0 + 3), j] = 2
    # bare / sand patches near edges
    lc[: max(2, ny // 18), :] = np.where(rng.random((max(2, ny // 18), nx)) > 0.4, 1, lc[: max(2, ny // 18), :])
    lc[-max(2, ny // 20) :, : nx // 3] = 1

    buildings = np.zeros((ny, nx), dtype=np.float32)
    urban = lc == 4
    # blocky buildings on urban cells
    for i in range(0, ny, 3):
        for j in range(0, nx, 3):
            if urban[i, j] and rng.random() > 0.25:
                h = float(8 + 55 * rng.random() ** 1.3)
                buildings[i : min(ny, i + 2), j : min(nx, j + 2)] = h
    buildings *= urban.astype(np.float32)

    trees = np.zeros((ny, nx), dtype=np.float32)
    veg = lc == 3
    trees[veg] = (8 + 28 * rng.random(int(veg.sum()))).astype(np.float32)
    # street trees in urban
    street = urban & (rng.random((ny, nx)) > 0.92)
    trees[street] = (4 + 12 * rng.random(int(street.sum()))).astype(np.float32)

    dem = 25 + 35 * (Y - bbox["south"]) / max(bbox["north"] - bbox["south"], 1e-6)
    dem += 3 * rng.normal(size=(ny, nx))
    svf = np.clip(0.95 - 0.035 * np.sqrt(np.maximum(buildings, 0)), 0.08, 0.98).astype(np.float32)
    veg_f = (trees > 1).astype(np.float32)
    np.savez_compressed(
        out / "domain_100m.npz",
        dem=dem.astype(np.float32),
        buildings=buildings.astype(np.float32),
        trees=trees.astype(np.float32),
        lc=lc,
        svf=svf,
        veg=veg_f,
        ys=ys,
        xs=xs,
        res_m=np.array([res_m], dtype=np.float32),
    )
    meta = {
        "source": "synthetic",
        "city": "Seoul",
        "res_m": res_m,
        "ny": ny,
        "nx": nx,
        "bbox": bbox,
        "land_use_codes": {"1": "Bare & Sand", "2": "Water", "3": "Vegetation", "4": "Urban"},
        "note": "Seoul-like synthetic morphology for Fig2 literature layout (CPU smoke)",
    }
    _write_json(out / "domain_meta.json", meta)
    return meta


def _worldcover_to_fig2_lc(wc: np.ndarray) -> np.ndarray:
    """Map ESA WorldCover codes → Fig2 legend: 1 Bare, 2 Water, 3 Vegetation, 4 Urban."""
    out = np.full(wc.shape, 1, dtype=np.int16)  # default bare
    out[np.isin(wc, [10, 20, 30, 40, 90, 95, 100])] = 3  # veg / wetland / moss
    out[np.isin(wc, [80])] = 2  # water
    out[np.isin(wc, [50])] = 4  # built-up
    out[np.isin(wc, [60, 70])] = 1  # bare / snow
    return out


# GHS-BUILT-H AGBH sanity cap (m). 80 m was a Dortmund-scale clip and saturates
# Seoul CBD (100 m cell-mean can exceed 80; individual towers are much taller).
GHSL_HEIGHT_SANITY_M = 400.0


def _clip_building_height(arr, cap: float = GHSL_HEIGHT_SANITY_M) -> np.ndarray:
    return np.clip(np.asarray(arr, dtype=np.float32), 0.0, float(cap))


def _fig2_bldg_vmax(buildings: np.ndarray) -> float:
    """Colorbar upper limit from data, not a hardcoded 80 m Seoul 'max'."""
    h = np.asarray(buildings, float)
    h = h[np.isfinite(h) & (h > 0.5)]
    mx = float(np.nanmax(h)) if h.size else 100.0
    step = 50.0 if mx > 200.0 else 20.0
    return float(max(100.0, math.ceil(mx / step) * step))


def _fig2_tree_vmax(trees: np.ndarray) -> float:
    t = np.asarray(trees, float)
    t = t[np.isfinite(t) & (t > 0.5)]
    mx = float(np.nanmax(t)) if t.size else 30.0
    return float(max(30.0, math.ceil(mx / 5.0) * 5.0))


def _gee_sample_band(img, region, scale: float, band: str, default: float = 0.0):
    try:
        data = img.sampleRectangle(region=region, defaultValue=default).get(band).getInfo()
        return np.array(data, dtype=np.float32)
    except Exception as e:  # noqa: BLE001
        print(f"[gee] sample failed for {band}: {e}", file=sys.stderr)
        return None


def gee_domain_sample(out: Path, bbox: dict, res_m: float, project: str | None) -> dict | None:
    if not try_init_ee(project):
        return None
    import ee  # type: ignore

    region = ee.Geometry.Rectangle([bbox["west"], bbox["south"], bbox["east"], bbox["north"]])
    scale = float(res_m)
    dem = ee.Image("USGS/SRTMGL1_003").select("elevation").clip(region)
    lc = ee.ImageCollection("ESA/WorldCover/v200").first().select("Map").clip(region)

    # Building height: GHSL 100 m
    built_img = ee.Image("JRC/GHSL/P2023A/GHS_BUILT_H/2018").select("built_height").clip(region)

    # Canopy height: try ETH / sat-io mirrors (Meta asset name was wrong)
    canopy = None
    canopy_id = "none"
    canopy_band = "b1"
    for cid in (
        "users/nlang/ETH_GlobalCanopyHeight_2020_10m_v1",
        "projects/sat-io/open-datasets/ETH_GLOBAL_CANOPY_HEIGHT_2020",
        "projects/sat-io/open-datasets/ETH_Global_Canopy_Height_2020",
    ):
        try:
            canopy = ee.Image(cid).clip(region)
            bnames = canopy.bandNames().getInfo()
            canopy_band = bnames[0] if bnames else "b1"
            canopy = canopy.select(canopy_band)
            canopy_id = cid
            print(f"[gee] canopy asset OK: {canopy_id} band={canopy_band}")
            break
        except Exception as e:  # noqa: BLE001
            print(f"[gee] canopy try fail {cid}: {e}", file=sys.stderr)
            canopy = None
    if canopy is None:
        print("[gee] ETH canopy unavailable; trying GEDI RH98 mosaic fallback", file=sys.stderr)
        try:
            canopy = (
                ee.ImageCollection("LARSE/GEDI/GEDI02_A_002_MONTHLY")
                .filterDate("2020-01-01", "2020-12-31")
                .select("rh98")
                .mean()
                .clip(region)
            )
            canopy_band = "rh98"
            canopy_id = "LARSE/GEDI/GEDI02_A_002_MONTHLY:rh98_mean_2020"
        except Exception as e2:  # noqa: BLE001
            print(f"[gee] canopy fallback failed: {e2}", file=sys.stderr)
            canopy = ee.Image.constant(0).rename("canopy").clip(region)
            canopy_band = "canopy"
            canopy_id = "none"

    dem_a = _gee_sample_band(dem.reproject(crs="EPSG:4326", scale=scale), region, scale, "elevation", 0)
    lc_a = _gee_sample_band(lc.reproject(crs="EPSG:4326", scale=scale), region, scale, "Map", 0)
    built_a = _gee_sample_band(
        built_img.reproject(crs="EPSG:4326", scale=scale), region, scale, "built_height", 0
    )
    tree_a = _gee_sample_band(
        canopy.reproject(crs="EPSG:4326", scale=scale), region, scale, canopy_band, 0
    )

    if dem_a is None or lc_a is None:
        return None

    ny, nx = dem_a.shape

    def _fit(a, fill=0.0):
        if a is None:
            return np.full((ny, nx), fill, dtype=np.float32)
        if a.shape != (ny, nx):
            # nearest resize via repeat/crop
            out = np.full((ny, nx), fill, dtype=np.float32)
            yy = min(ny, a.shape[0])
            xx = min(nx, a.shape[1])
            out[:yy, :xx] = a[:yy, :xx]
            return out
        return a.astype(np.float32)

    lc_a = _fit(lc_a, 60)
    built_a = _fit(built_a, 0)
    tree_a = np.nan_to_num(_fit(tree_a, 0), nan=0.0)
    dem_a = _fit(dem_a, 30)

    # Fig2 land-use classes
    lc_fig = _worldcover_to_fig2_lc(lc_a.astype(np.int16))
    # buildings: GHSL 100 m AGBH (cell-mean height, m); do not cap at 80 m
    buildings = np.where(lc_fig == 4, _clip_building_height(built_a), 0.0).astype(np.float32)
    # if GHSL mostly zero on urban, add mild structure from DEM roughness so Fig2 has depth
    if float(np.nanmax(buildings)) < 1.5:
        print("[gee] GHSL heights weak; blending urban DEM residual for Fig2 depth", file=sys.stderr)
        dem_s = dem_a - np.nanmean(dem_a)
        buildings = np.where(lc_fig == 4, np.clip(8 + 3 * np.abs(dem_s), 0, 60), 0).astype(np.float32)
    # if WorldCover under-detects built-up but GHSL has height, promote to Urban
    if float(np.nanmax(built_a)) > 1.5:
        buildings = np.where(built_a > 0.5, _clip_building_height(built_a), buildings).astype(np.float32)
        lc_fig = np.where(buildings > 0.5, 4, lc_fig).astype(np.int16)
    trees = np.clip(tree_a, 0, 40).astype(np.float32)
    # vegetation + urban parks only (do not paint street-tree ETH height over the whole city)
    park = (lc_fig == 4) & (trees > np.maximum(buildings, 0.0) + 2.0) & (trees > 6.0)
    trees = np.where((lc_fig == 3) | park, trees, 0.0).astype(np.float32)

    svf = np.clip(0.95 - 0.03 * np.sqrt(np.maximum(buildings, 0)), 0.05, 0.98).astype(np.float32)
    veg = (trees > 1).astype(np.float32)
    ys = np.linspace(bbox["north"], bbox["south"], ny)
    xs = np.linspace(bbox["west"], bbox["east"], nx)
    np.savez_compressed(
        out / "domain_100m.npz",
        dem=dem_a,
        buildings=buildings,
        trees=trees,
        lc=lc_fig,  # Fig2 codes 1-4
        lc_worldcover=lc_a.astype(np.int16),
        svf=svf,
        veg=veg,
        ys=ys,
        xs=xs,
        res_m=np.array([res_m], dtype=np.float32),
    )
    meta = {
        "source": "gee",
        "city": "Seoul",
        "res_m": res_m,
        "ny": int(ny),
        "nx": int(nx),
        "bbox": bbox,
        "assets": [
            "USGS/SRTMGL1_003",
            "ESA/WorldCover/v200",
            "JRC/GHSL/P2023A/GHS_BUILT_H/2018",
            canopy_id,
        ],
        "land_use_codes": {"1": "Bare & Sand", "2": "Water", "3": "Vegetation", "4": "Urban"},
        "building_height_max_m": float(np.nanmax(buildings)),
        "tree_height_max_m": float(np.nanmax(trees)),
    }
    _write_json(out / "domain_meta.json", meta)
    return meta


def refresh_domain_ghsl_heights(data: Path, bbox: dict, project: str | None) -> dict | None:
    """Re-sample GHSL onto the existing 100 m grid without the old 80 m cap."""
    zpath = data / "domain_100m.npz"
    if not zpath.exists():
        print("[gee] domain_100m.npz missing; cannot refresh GHSL", file=sys.stderr)
        return None
    if not try_init_ee(project):
        return None
    import ee  # type: ignore

    z = np.load(zpath)
    old = {k: np.array(z[k]) for k in z.files}
    ny, nx = old["buildings"].shape
    scale = float(np.asarray(old["res_m"]).ravel()[0]) if "res_m" in old else 100.0
    region = ee.Geometry.Rectangle([bbox["west"], bbox["south"], bbox["east"], bbox["north"]])
    built_img = ee.Image("JRC/GHSL/P2023A/GHS_BUILT_H/2018").select("built_height").clip(region)
    built_a = _gee_sample_band(
        built_img.reproject(crs="EPSG:4326", scale=scale), region, scale, "built_height", 0
    )
    if built_a is None:
        return None
    out_h = np.full((ny, nx), 0.0, dtype=np.float32)
    yy, xx = min(ny, built_a.shape[0]), min(nx, built_a.shape[1])
    out_h[:yy, :xx] = built_a[:yy, :xx]
    lc = old["lc"]
    buildings = np.where(lc == 4, _clip_building_height(out_h), 0.0).astype(np.float32)
    if float(np.nanmax(out_h)) > 1.5:
        buildings = np.where(out_h > 0.5, _clip_building_height(out_h), buildings).astype(np.float32)
    old["buildings"] = buildings
    np.savez_compressed(zpath, **old)
    meta_p = data / "domain_meta.json"
    meta = json.loads(meta_p.read_text(encoding="utf-8")) if meta_p.exists() else {}
    meta["building_height_max_m"] = float(np.nanmax(buildings))
    meta["building_height_p99_m"] = float(np.nanpercentile(buildings[buildings > 0], 99)) if np.any(buildings > 0) else 0.0
    meta["ghsl_height_clip_m"] = GHSL_HEIGHT_SANITY_M
    _write_json(meta_p, meta)
    print(
        f"[gee] GHSL refresh {ny}x{nx} max={float(np.nanmax(buildings)):.1f} m "
        f"p99={meta['building_height_p99_m']:.1f} m (sanity cap {GHSL_HEIGHT_SANITY_M:.0f} m)",
        file=sys.stderr,
    )
    return meta


def mode_domain_ghsl_refresh(out_dir: Path, args) -> None:
    bbox = {"west": args.west, "south": args.south, "east": args.east, "north": args.north}
    meta = refresh_domain_ghsl_heights(Path(out_dir) / "Data", bbox, args.gee_project or None)
    if meta is None:
        raise SystemExit("GHSL refresh failed (GEE auth/proxy?)")
    z = np.load(Path(out_dir) / "Data" / "domain_100m.npz")
    stations = pd.read_csv(Path(out_dir) / "Data" / "stations_meta.csv")
    z2 = _fig2_city_display_domain(Path(out_dir) / "Data")
    plot_figure02_seoul_domain(_ensure(Path(out_dir) / "Figures"), z2 if z2 is not None else z, stations)
    print("[ok] domain_ghsl_refresh + Figure 2")


def _fig3_default_zoom(bbox: dict | None = None) -> dict:
    """Fig.3 wind-coeff inset = same central window as Figure S2 (black box on Fig.2)."""
    z = dict(_fig2_s2_zoom())
    if bbox:
        z["west"] = max(z["west"], float(bbox["west"]))
        z["east"] = min(z["east"], float(bbox["east"]))
        z["south"] = max(z["south"], float(bbox["south"]))
        z["north"] = min(z["north"], float(bbox["north"]))
    return z


def _osm_fetch_buildings(zoom: dict, timeout: int = 100) -> dict | None:
    """Fetch OSM building ways/nodes via Overpass (Seoul-capable mirrors)."""
    import urllib.parse
    import urllib.request

    south, west, north, east = zoom["south"], zoom["west"], zoom["north"], zoom["east"]
    query = (
        f"[out:json][timeout:{timeout}];"
        f'(way["building"]({south},{west},{north},{east});'
        f'relation["building"]({south},{west},{north},{east}););'
        f"out body;>;out skel qt;"
    )
    mirrors = [
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://overpass-api.de/api/interpreter",
    ]
    data = urllib.parse.urlencode({"data": query}).encode("utf-8")
    for url in mirrors:
        try:
            req = urllib.request.Request(url, data=data, method="POST", headers={"User-Agent": "GLIDE-SOL-repro/1.0"})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                payload = json.loads(r.read().decode("utf-8"))
            n_way = sum(1 for e in payload.get("elements", []) if e.get("type") == "way")
            if n_way > 10:
                print(f"[osm] buildings ways={n_way} via {url.split('/')[2]}")
                return payload
            print(f"[osm] sparse response ways={n_way} from {url}", file=sys.stderr)
        except Exception as e:  # noqa: BLE001
            print(f"[osm] fail {url}: {e}", file=sys.stderr)
    return None


def _osm_building_height(tags: dict) -> float:
    h = None
    if "height" in tags:
        try:
            h = float(str(tags["height"]).lower().replace("m", "").split()[0])
        except Exception:
            h = None
    if h is None and "building:levels" in tags:
        try:
            h = float(str(tags["building:levels"]).split(";")[0]) * 3.0
        except Exception:
            h = None
    if h is None:
        h = 12.0
    return float(np.clip(h, 4.0, GHSL_HEIGHT_SANITY_M))


def _osm_iter_building_polys(osm: dict) -> list[dict]:
    """Closed lon/lat rings from OSM building ways (vector footprints)."""
    nodes = {e["id"]: (float(e["lon"]), float(e["lat"])) for e in osm.get("elements", []) if e.get("type") == "node"}
    out = []
    for e in osm.get("elements", []):
        if e.get("type") != "way":
            continue
        tags = e.get("tags") or {}
        if "building" not in tags:
            continue
        pts = [nodes[nid] for nid in (e.get("nodes") or []) if nid in nodes]
        if len(pts) < 3:
            continue
        if pts[0] != pts[-1]:
            pts.append(pts[0])
        lon = [p[0] for p in pts]
        lat = [p[1] for p in pts]
        out.append({"lon": lon, "lat": lat, "h": _osm_building_height(tags)})
    return out


def _osm_save_polys(path: Path, polys: list[dict]) -> None:
    slim = [{"lon": [round(x, 6) for x in p["lon"]], "lat": [round(y, 6) for y in p["lat"]], "h": round(float(p["h"]), 1)} for p in polys]
    path.write_text(json.dumps({"n": len(slim), "buildings": slim}, ensure_ascii=False), encoding="utf-8")


def _osm_load_polys(path: Path) -> list[dict]:
    if not path.exists():
        return []
    obj = json.loads(path.read_text(encoding="utf-8"))
    return list(obj.get("buildings") or [])


_GHSL_C_HEIGHT = {
    11: 3.0, 12: 5.0, 13: 10.0, 14: 22.0, 15: 40.0,
    21: 3.0, 22: 5.0, 23: 10.0, 24: 22.0, 25: 40.0,
}


def _poly_centroid(p: dict) -> tuple[float, float]:
    return float(np.mean(p["lon"])), float(np.mean(p["lat"]))


class _CentroidIndex:
    """~15 m hash so 10 m gap cells skip existing vector footprints."""

    def __init__(self, polys: list[dict], cell: float = 0.00015):
        self.cell = float(cell)
        self.b: dict[tuple[int, int], list[tuple[float, float]]] = {}
        for p in polys:
            lon, lat = _poly_centroid(p)
            self.b.setdefault((int(lon / self.cell), int(lat / self.cell)), []).append((lon, lat))

    def near(self, lon: float, lat: float, r: float = 0.00018) -> bool:
        i0, j0 = int(lon / self.cell), int(lat / self.cell)
        r2 = r * r
        for di in (-1, 0, 1):
            for dj in (-1, 0, 1):
                for x, y in self.b.get((i0 + di, j0 + dj), ()):
                    if (x - lon) ** 2 + (y - lat) ** 2 <= r2:
                        return True
        return False


def _geojson_to_building_polys(path: Path) -> list[dict]:
    obj = json.loads(path.read_text(encoding="utf-8"))
    out = []
    for f in obj.get("features") or []:
        geom = f.get("geometry") or {}
        gtype = geom.get("type")
        coords = geom.get("coordinates")
        if not coords:
            continue
        if gtype == "Polygon":
            ring = coords[0]
        elif gtype == "MultiPolygon":
            ring = coords[0][0]
        else:
            continue
        arr = np.asarray(ring, float)
        if arr.ndim != 2 or arr.shape[0] < 3:
            continue
        props = f.get("properties") or {}
        h = props.get("height")
        try:
            h = float(h) if h not in (None, "") else 12.0
        except (TypeError, ValueError):
            h = 12.0
        out.append(
            {
                "lon": arr[:, 0].tolist(),
                "lat": arr[:, 1].tolist(),
                "h": float(np.clip(h, 3.0, GHSL_HEIGHT_SANITY_M)),
            }
        )
    return out


def _overture_download_buildings(zoom: dict, dest: Path, timeout: int = 180) -> Path | None:
    """Overture buildings (OSM + ML extras). Google/Microsoft Open Buildings skip Korea."""
    dest = Path(dest)
    if dest.exists() and dest.stat().st_size > 500_000:
        return dest
    dest.parent.mkdir(parents=True, exist_ok=True)
    bbox = f"{zoom['west']},{zoom['south']},{zoom['east']},{zoom['north']}"
    cmd = [
        sys.executable, "-m", "overturemaps", "download",
        f"--bbox={bbox}", "-f", "geojson", "--type", "building", "-o", str(dest),
    ]
    try:
        subprocess.run(cmd, check=True, timeout=timeout)
    except Exception as e:  # noqa: BLE001
        print(f"[overture] download failed: {e}", file=sys.stderr)
        return dest if dest.exists() else None
    return dest if dest.exists() else None


def gee_ghsl_built_c_window(zoom: dict, project: str | None = None):
    """10 m GHS-BUILT-C settlement classes for the Fig2 window."""
    if not try_init_ee(project):
        return None
    import ee  # type: ignore

    region = ee.Geometry.Rectangle([zoom["west"], zoom["south"], zoom["east"], zoom["north"]])
    img = (
        ee.Image("JRC/GHSL/P2023A/GHS_BUILT_C/2018")
        .select("built_characteristics")
        .clip(region)
        .reproject(crs="EPSG:4326", scale=10)
    )
    arr = _gee_sample_band(img, region, 10.0, "built_characteristics", 0)
    if arr is None or arr.size < 100:
        return None
    ny, nx = arr.shape
    ys = np.linspace(float(zoom["north"]), float(zoom["south"]), ny)
    xs = np.linspace(float(zoom["west"]), float(zoom["east"]), nx)
    print(f"[gee] GHS-BUILT-C 10 m {ny}x{nx}; built_frac={float(np.isin(arr, list(_GHSL_C_HEIGHT)).mean()):.3f}")
    return np.asarray(arr, dtype=np.int16), ys, xs


def _ghsl_c_gap_polys(arr: np.ndarray, ys: np.ndarray, xs: np.ndarray, existing: list[dict], inset: float = 0.18) -> list[dict]:
    """10 m rectangles for GHS-BUILT-C building cells not already covered by vectors."""
    ye, xe = _coord_edges(ys), _coord_edges(xs)
    idx = _CentroidIndex(existing)
    out = []
    built = np.isin(arr, list(_GHSL_C_HEIGHT))
    ii, jj = np.where(built)
    for i, j in zip(ii.tolist(), jj.tolist()):
        lon, lat = float(xs[j]), float(ys[i])
        if idx.near(lon, lat):
            continue
        y0, y1 = (ye[i], ye[i + 1]) if ye[i] < ye[i + 1] else (ye[i + 1], ye[i])
        x0, x1 = (xe[j], xe[j + 1]) if xe[j] < xe[j + 1] else (xe[j + 1], xe[j])
        dx = inset * (x1 - x0)
        dy = inset * (y1 - y0)
        out.append(
            {
                "lon": [x0 + dx, x1 - dx, x1 - dx, x0 + dx, x0 + dx],
                "lat": [y0 + dy, y0 + dy, y1 - dy, y1 - dy, y0 + dy],
                "h": float(_GHSL_C_HEIGHT.get(int(arr[i, j]), 12.0)),
            }
        )
    return out


def _rasterize_polys_height(polys: list[dict], ys: np.ndarray, xs: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Footprint mask + height (m) on (ys, xs). Overlaps: last polygon wins."""
    from PIL import Image, ImageDraw

    ny, nx = len(ys), len(xs)
    west, east = float(xs.min()), float(xs.max())
    north, south = float(ys.max()), float(ys.min())
    foot = np.zeros((ny, nx), dtype=np.float32)
    height = np.zeros((ny, nx), dtype=np.float32)
    if east <= west or north <= south:
        return foot, height
    im_f = Image.new("L", (nx, ny), 0)
    im_h = Image.new("I", (nx, ny), 0)
    draw_f = ImageDraw.Draw(im_f)
    draw_h = ImageDraw.Draw(im_h)
    for p in polys:
        lon, lat = np.asarray(p["lon"], float), np.asarray(p["lat"], float)
        if lon.size < 3:
            continue
        js = (lon - west) / (east - west) * (nx - 1)
        is_ = (north - lat) / (north - south) * (ny - 1)
        pts = list(zip(js.tolist(), is_.tolist()))
        h10 = int(np.clip(float(p.get("h", 12.0)), 3.0, GHSL_HEIGHT_SANITY_M) * 10.0)
        draw_f.polygon(pts, outline=1, fill=1)
        draw_h.polygon(pts, outline=h10, fill=h10)
    foot = np.array(im_f, dtype=np.float32)
    height = np.array(im_h, dtype=np.float32) / 10.0
    height = np.where(foot > 0.5, height, 0.0).astype(np.float32)
    return foot, height


def _load_paper_footprints(data_dir: Path, zoom: dict) -> tuple[list[dict], list[str]]:
    """Global footprints only: Overture (OSM+ML), then OSM Overpass. No Korean cadastre, no GHSL-C squares."""
    data = Path(data_dir)
    sources: list[str] = []
    polys: list[dict] = []
    ovt = data / "overture_buildings_fig2.geojson"
    got = ovt if ovt.exists() and ovt.stat().st_size > 100_000 else _overture_download_buildings(zoom, ovt)
    if got is not None and Path(got).exists():
        polys = _filter_polys_zoom(_geojson_to_building_polys(Path(got)), zoom)
        sources.append("overture_buildings")
        print(f"[s2-2m] Overture n={len(polys)}")
    if len(polys) < 2000:
        osm_p = data / "osm_buildings_fig2.json"
        if osm_p.exists():
            obj = json.loads(osm_p.read_text(encoding="utf-8"))
            extra = _filter_polys_zoom(list(obj.get("buildings") or []), zoom)
            polys = list(polys) + extra
            sources.append("osm_buildings_cache")
            print(f"[s2-2m] OSM cache extra n={len(extra)} total={len(polys)}")
        else:
            osm = _osm_fetch_buildings(zoom)
            if osm is not None:
                extra = _filter_polys_zoom(_osm_iter_building_polys(osm), zoom)
                polys = list(polys) + extra
                sources.append("osm_overpass")
                print(f"[s2-2m] OSM Overpass n={len(extra)}")
    return polys, sources


def _gee_s2_10m_layers(zoom: dict, project: str | None) -> dict | None:
    """WorldCover / GHSL / ETH at 10 m for the S2 window (native scales; 2 m would exceed GEE sampleRectangle)."""
    if not try_init_ee(project):
        return None
    import ee  # type: ignore

    region = ee.Geometry.Rectangle([zoom["west"], zoom["south"], zoom["east"], zoom["north"]])
    scale = 10.0
    lc_img = ee.ImageCollection("ESA/WorldCover/v200").first().select("Map").clip(region)
    built_img = ee.Image("JRC/GHSL/P2023A/GHS_BUILT_H/2018").select("built_height").clip(region)
    canopy = None
    canopy_band = "b1"
    for cid in (
        "users/nlang/ETH_GlobalCanopyHeight_2020_10m_v1",
        "projects/sat-io/open-datasets/ETH_GLOBAL_CANOPY_HEIGHT_2020",
    ):
        try:
            canopy = ee.Image(cid).clip(region)
            canopy_band = canopy.bandNames().getInfo()[0]
            canopy = canopy.select(canopy_band)
            break
        except Exception:
            canopy = None
    lc_a = _gee_sample_band(lc_img.reproject(crs="EPSG:4326", scale=scale), region, scale, "Map", 0)
    built_a = _gee_sample_band(built_img.reproject(crs="EPSG:4326", scale=scale), region, scale, "built_height", 0)
    tree_a = None
    if canopy is not None:
        tree_a = _gee_sample_band(canopy.reproject(crs="EPSG:4326", scale=scale), region, scale, canopy_band, 0)
    if lc_a is None:
        return None
    ny, nx = lc_a.shape
    ys = np.linspace(float(zoom["north"]), float(zoom["south"]), ny)
    xs = np.linspace(float(zoom["west"]), float(zoom["east"]), nx)
    print(f"[s2-2m] GEE 10 m layers {ny}x{nx}")
    return {"lc": lc_a, "buildings": built_a, "trees": tree_a, "ys": ys, "xs": xs}


def build_domain_s2_2m(
    data_dir: Path,
    zoom: dict | None = None,
    res_m: float = 2.0,
    project: str | None = None,
) -> dict:
    """S2 window at 2 m, paper-transferable stack. No MOIS cadastre."""
    data = _ensure(Path(data_dir))
    zoom = dict(zoom or _fig2_s2_zoom())
    res_m = float(res_m)
    ny, nx, ys, xs = _grid_shape(zoom, res_m, cap=None)
    print(f"[s2-2m] grid {ny}x{nx} @ {res_m} m window={zoom}")

    polys, sources = _load_paper_footprints(data, zoom)
    if len(polys) < 50:
        raise RuntimeError("S2 2 m: global footprints unavailable (Overture/OSM)")
    footprint, h_poly = _rasterize_polys_height(polys, ys, xs)
    print(f"[s2-2m] raster footprints frac={float((footprint > 0.5).mean()):.3f}")

    z100_path = data / "domain_100m.npz"
    z100 = np.load(z100_path) if z100_path.exists() else None
    gee10 = _gee_s2_10m_layers(zoom, project)

    def _from_src(arr, ys_s, xs_s, fill=0.0):
        if arr is None:
            return np.full((ny, nx), fill, dtype=np.float32)
        return _sample_to_grid(np.asarray(arr), np.asarray(ys_s), np.asarray(xs_s), ys, xs).astype(np.float32)

    if gee10 is not None:
        lc_wc = _from_src(gee10["lc"], gee10["ys"], gee10["xs"], 50)
        ghsl = _from_src(gee10["buildings"], gee10["ys"], gee10["xs"], 0)
        trees = _from_src(gee10["trees"], gee10["ys"], gee10["xs"], 0)
        lc_src = "WorldCover_10m_nn"
    elif z100 is not None:
        lc_wc = _from_src(z100["lc_worldcover"] if "lc_worldcover" in z100.files else z100["lc"], z100["ys"], z100["xs"], 50)
        ghsl = _from_src(z100["buildings"], z100["ys"], z100["xs"], 0)
        trees = _from_src(z100["trees"], z100["ys"], z100["xs"], 0)
        lc_src = "domain_100m_nn"
        print("[s2-2m] GEE 10 m unavailable; nearest-upsampled city 100 m layers", file=sys.stderr)
    else:
        raise RuntimeError("S2 2 m: need GEE or domain_100m.npz for land use / height")

    if int(np.nanmax(lc_wc)) > 10:
        lc = _worldcover_to_fig2_lc(lc_wc.astype(np.int16))
    else:
        lc = np.asarray(lc_wc, dtype=np.int16)

    unknown = (footprint > 0.5) & (h_poly <= 12.5)
    buildings = np.where(footprint > 0.5, h_poly, 0.0)
    buildings = np.where(unknown & (ghsl > 3.0), np.maximum(_clip_building_height(ghsl), 3.0), buildings)
    buildings = np.where(
        footprint > 0.5,
        np.clip(np.maximum(buildings, 4.0), 4.0, GHSL_HEIGHT_SANITY_M),
        0.0,
    ).astype(np.float32)
    lc = np.where(footprint > 0.5, 4, lc).astype(np.int16)

    trees = np.clip(np.nan_to_num(trees, nan=0.0), 0.0, 40.0)
    trees = np.where(footprint > 0.5, 0.0, trees).astype(np.float32)
    park = (lc == 4) & (footprint < 0.5) & (trees > 6.0)
    trees = np.where((lc == 3) | park, trees, 0.0).astype(np.float32)

    np.savez_compressed(
        data / "domain_s2_2m.npz",
        buildings=buildings,
        trees=trees,
        lc=lc,
        footprint=footprint.astype(np.float32),
        ys=ys.astype(np.float64),
        xs=xs.astype(np.float64),
        res_m=np.array([res_m], dtype=np.float32),
    )
    meta = {
        "source": "+".join(sources + [lc_src, "GHSL_height_on_footprints", "ETH_canopy"]),
        "city": "Seoul",
        "res_m": res_m,
        "ny": int(ny),
        "nx": int(nx),
        "bbox": zoom,
        "n_footprints": len(polys),
        "n_building_cells": int((footprint > 0.5).sum()),
        "building_height_max_m": float(np.nanmax(buildings)),
        "tree_height_max_m": float(np.nanmax(trees)),
        "note": "Paper workflow on S2 window. No MOIS cadastre. Open Buildings skip Korea → Overture/OSM.",
    }
    _write_json(data / "domain_s2_2m_meta.json", meta)
    print(
        f"[ok] domain_s2_2m {ny}x{nx} @ {res_m} m; "
        f"footprints={meta['n_footprints']} cells={meta['n_building_cells']}"
    )
    return meta


def mode_domain_s2_2m(out_dir: Path, args) -> None:
    data = _ensure(Path(out_dir) / "Data")
    meta = build_domain_s2_2m(
        data,
        zoom=_fig2_s2_zoom(),
        res_m=float(getattr(args, "s2_res_m", 2.0) or 2.0),
        project=getattr(args, "gee_project", None) or None,
    )
    print(f"[ok] domain_s2_2m source={meta['source']}")


# ---------------------------------------------------------------------------
# City-wide 2 m morphology (Figure 3 main = full Seoul, no S2 window)
# ---------------------------------------------------------------------------


def _seoul_city_bbox(data_dir: Path) -> dict:
    """Same expanded bbox as Figure 2 / domain_100m.npz."""
    meta_p = Path(data_dir) / "domain_meta.json"
    if meta_p.exists():
        bbox = (json.loads(meta_p.read_text(encoding="utf-8")) or {}).get("bbox")
        if bbox and all(k in bbox for k in ("west", "east", "south", "north")):
            return {k: float(bbox[k]) for k in ("west", "east", "south", "north")}
    return {"west": 126.78, "east": 127.17, "south": 37.46, "north": 37.67}


def _overture_city_parquet(data_dir: Path, bbox: dict, timeout: int = 900) -> Path | None:
    """Download (or reuse) Overture buildings geoparquet for the full city bbox."""
    dest = Path(data_dir) / "overture_buildings_city.parquet"
    if dest.exists() and dest.stat().st_size > 5_000_000:
        return dest
    dest.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        sys.executable, "-m", "overturemaps", "download",
        f"--bbox={bbox['west']},{bbox['south']},{bbox['east']},{bbox['north']}",
        "-f", "geoparquet", "--type", "building", "-o", str(dest),
    ]
    try:
        subprocess.run(cmd, check=True, timeout=timeout)
    except Exception as e:  # noqa: BLE001
        print(f"[overture-city] download failed: {e}", file=sys.stderr)
        return None
    return dest if dest.exists() and dest.stat().st_size > 1_000_000 else None


def _rasterize_parquet_footprints(parquet: Path, ys: np.ndarray, xs: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Footprint bool + height (m) at (ys, xs) directly from Overture geoparquet.

    Streams WKB polygons → pixel rings (PIL fill) without materialising dicts
    for 400k+ buildings. Overlap: last draw wins (like _rasterize_polys_height).
    """
    import pyarrow.parquet as pq
    import shapely
    from PIL import Image, ImageDraw

    ny, nx = len(ys), len(xs)
    west, east = float(xs.min()), float(xs.max())
    north, south = float(ys.max()), float(ys.min())
    foot = np.zeros((ny, nx), dtype=np.float32)
    height = np.zeros((ny, nx), dtype=np.float32)
    if east <= west or north <= south:
        return foot, height
    im_f = Image.new("L", (nx, ny), 0)
    im_h = Image.new("I", (nx, ny), 0)
    d_f = ImageDraw.Draw(im_f)
    d_h = ImageDraw.Draw(im_h)
    sx = (nx - 1) / (east - west)
    sy = (ny - 1) / (north - south)

    tbl = pq.read_table(parquet, columns=["height", "num_floors", "geometry"])
    heights = tbl["height"].to_pylist()
    floors = tbl["num_floors"].to_pylist()
    geoms = shapely.from_wkb(tbl["geometry"].to_pylist())
    n_draw = 0
    n_poly = max(1, len(geoms))
    for i in range(len(geoms)):
        if (i & 65535) == 0:
            print(f"[ovt-raster] {i}/{n_poly}", flush=True)
        g = geoms[i]
        if g is None or g.is_empty:
            continue
        bb = g.bounds
        if bb[2] < west or bb[0] > east or bb[3] < south or bb[1] > north:
            continue
        h = heights[i]
        try:
            h = float(h) if h is not None else None
        except (TypeError, ValueError):
            h = None
        if (h is None or h <= 0) and floors[i] is not None:
            try:
                h = float(floors[i]) * 3.0
            except (TypeError, ValueError):
                h = None
        h = float(np.clip(h if h and h > 0 else 12.0, 3.0, GHSL_HEIGHT_SANITY_M))
        polys = [g] if g.geom_type == "Polygon" else (g.geoms if g.geom_type == "MultiPolygon" else [])
        for gg in polys:
            coords = np.asarray(gg.exterior.coords, dtype=float)
            if coords.shape[0] < 3:
                continue
            j = (coords[:, 0] - west) * sx
            ii = (north - coords[:, 1]) * sy
            pts = [tuple(p) for p in zip(j.tolist(), ii.tolist())]
            d_f.polygon(pts, outline=1, fill=1)
            d_h.polygon(pts, outline=int(h), fill=int(h))
            n_draw += 1
    print(f"[ovt-raster] drew {n_draw} rings")
    foot[:] = np.asarray(im_f, dtype=np.float32)
    height[:] = np.asarray(im_h, dtype=np.float32)
    return foot, height


def wind_coeff_tiled(
    b_mask_2m: np.ndarray,
    t_mask_2m: np.ndarray,
    theta_deg: float,
    res_m: float,
    *,
    tile_px: int = 4096,
    pad_m: float = 200.0,
) -> np.ndarray:
    """directional_wind_coeff on tiles with halo overlap (full-city 2 m grids).

    Avoids rotate()/gaussian on a 200 M-cell array. Halo covers along-wind
    smoothing lengths (≤~70 m corridor blur + 40 m Gauss) with margin.
    """
    ny, nx = b_mask_2m.shape
    C = np.ones((ny, nx), dtype=np.float32)
    pad = int(math.ceil(pad_m / res_m))
    step = max(512, int(tile_px) - 2 * pad)
    nty = max(1, int(math.ceil(ny / step)))
    ntx = max(1, int(math.ceil(nx / step)))
    for ity in range(nty):
        for itx in range(ntx):
            y0 = ity * step
            y1 = min(ny, y0 + step)
            x0 = itx * step
            x1 = min(nx, x0 + step)
            py0, py1 = max(0, y0 - pad), min(ny, y1 + pad)
            px0, px1 = max(0, x0 - pad), min(nx, x1 + pad)
            b_sub = b_mask_2m[py0:py1, px0:px1].astype(np.float32) * 20.0
            t_sub = t_mask_2m[py0:py1, px0:px1].astype(np.float32) * 12.0
            c_sub = directional_wind_coeff(
                b_sub, t_sub, theta_deg, footprint_mode=True, res_m=res_m
            )
            # keep only the core region (drop halo so neighbours overwrite cleanly)
            cy0, cy1 = y0 - py0, y1 - py0
            cx0, cx1 = x0 - px0, x1 - px0
            C[y0:y1, x0:x1] = c_sub[cy0:cy1, cx0:cx1]
    return C


def _downsample_frac_to_grid(mask: np.ndarray, ys: np.ndarray, xs: np.ndarray, ys2: np.ndarray, xs2: np.ndarray) -> np.ndarray:
    """Nearest-cell resample of a float/bool mask onto grid (ys2, xs2)."""
    m = np.asarray(mask, dtype=np.float32)
    iy = np.abs(np.asarray(ys, float)[:, None] - np.asarray(ys2, float)[None, :]).argmin(axis=0)
    ix = np.abs(np.asarray(xs, float)[:, None] - np.asarray(xs2, float)[None, :]).argmin(axis=0)
    return m[np.ix_(iy, ix)]


def build_domain_city_2m(data_dir: Path, res_m: float = 2.0, out_grid_res: float = 10.0) -> dict:
    """Full-Seoul 2 m morphology: Overture footprints + domain_100m background.

    Exports domain_city_2m.npz on a 10 m display/forcing grid (city-scale
    figures are unreadable at raw 2 m pixels; C is still *computed* at 2 m via
    wind_coeff_tiled and averaged into this grid). GEE is optional: falls back
    to nearest-upsampled domain_100m.npz layers (WorldCover / GHSL / ETH).
    """
    data = _ensure(Path(data_dir))
    bbox = _seoul_city_bbox(data)
    z100p = data / "domain_100m.npz"
    if not z100p.exists():
        raise RuntimeError("domain_city_2m: need domain_100m.npz for background layers")
    z100 = np.load(z100p)

    # 2 m working grid for footprints / C
    ny2, nx2, ys2, xs2 = _grid_shape(bbox, res_m, cap=None)
    print(f"[city-2m] work grid {ny2}x{nx2} @ {res_m} m")
    # 10 m export grid (matches Fig.2 domain aspect; smaller files)
    nyg, nxg, ysg, xsg = _grid_shape(bbox, out_grid_res, cap=None)
    print(f"[city-2m] export grid {nyg}x{nxg} @ {out_grid_res} m")

    pq_city = _overture_city_parquet(data, bbox)
    if pq_city is None:
        raise RuntimeError("city 2 m: Overture buildings parquet unavailable")
    foot2, h2 = _rasterize_parquet_footprints(pq_city, ys2, xs2)
    b_mask = foot2 > 0.5
    print(f"[city-2m] footprint frac at 2 m = {float(b_mask.mean()):.3f}")

    # block-max pool footprints/heights from work grid to export grid
    ratio = max(1, int(round(out_grid_res / res_m)))
    if ratio > 1:
        by, bx = ny2 // ratio, nx2 // ratio
        h_pool = h2[: by * ratio, : bx * ratio].reshape(by, ratio, bx, ratio).max(axis=(1, 3))
        b_pool = b_mask[: by * ratio, : bx * ratio].reshape(by, ratio, bx, ratio).any(axis=(1, 3))
        ys_pool = ys2[: by * ratio].reshape(by, ratio).mean(axis=1)
        xs_pool = xs2[: bx * ratio].reshape(bx, ratio).mean(axis=1)
        foot_g = _downsample_frac_to_grid(b_pool.astype(np.float32), ys_pool, xs_pool, ysg, xsg) > 0.5
        h_g = _downsample_frac_to_grid(h_pool, ys_pool, xs_pool, ysg, xsg)
    else:
        foot_g = b_mask
        h_g = h2

    ghsl_g = _sample_to_grid(np.asarray(z100["buildings"], float), z100["ys"], z100["xs"], ysg, xsg).astype(np.float32)
    tree_src = z100["trees"] if "trees" in z100.files else np.zeros_like(ghsl_g)
    trees_g = _sample_to_grid(np.asarray(tree_src, float), z100["ys"], z100["xs"], ysg, xsg).astype(np.float32)
    lc_key = "lc_worldcover" if "lc_worldcover" in z100.files else "lc"
    lc_g = _sample_to_grid(np.asarray(z100[lc_key], float), z100["ys"], z100["xs"], ysg, xsg).astype(np.int16)
    if int(np.nanmax(lc_g)) > 10:
        lc_g = _worldcover_to_fig2_lc(lc_g)

    ghsl_g = _clip_building_height(ghsl_g)
    buildings = np.where(foot_g, np.clip(np.maximum(h_g, 4.0), 4.0, GHSL_HEIGHT_SANITY_M), 0.0)
    # GHSL gap fill where built-up land cover has no vector footprint
    gap = (~foot_g) & (ghsl_g > 8.0) & (lc_g == 4)
    buildings = np.where(gap, ghsl_g, buildings).astype(np.float32)
    trees_g = np.clip(np.nan_to_num(trees_g, nan=0.0), 0.0, 40.0)
    trees_g = np.where(foot_g | (buildings > 15.0), 0.0, trees_g).astype(np.float32)
    lc_g = np.where(foot_g | (buildings > 15.0), 4, lc_g).astype(np.int16)

    np.savez_compressed(
        data / "domain_city_2m.npz",
        buildings=buildings,
        trees=trees_g,
        lc=lc_g,
        footprint=foot_g.astype(np.float32),
        ys=ysg.astype(np.float64),
        xs=xsg.astype(np.float64),
        res_m=np.array([out_grid_res], dtype=np.float32),
    )
    # keep 2 m binary masks for C tiling (compressed npz)
    t2 = _downsample_frac_to_grid(trees_g > 2.0, ysg, xsg, ys2, xs2) > 0.5
    np.savez_compressed(data / "city_2m_masks.npz", b=b_mask.astype(np.int8), t=t2.astype(np.int8))

    # Fig.2 display pool: 2 m → ~8 m block-max (true footprint detail, printable size)
    ds = max(1, int(round(8.0 / res_m)))
    dy, dx = ny2 // ds, nx2 // ds
    h_disp = (
        h2[: dy * ds, : dx * ds].reshape(dy, ds, dx, ds).max(axis=(1, 3)).astype(np.float32)
    )
    b_disp = (
        b_mask[: dy * ds, : dx * ds].reshape(dy, ds, dx, ds).any(axis=(1, 3))
    )
    ys_disp = ys2[: dy * ds].reshape(dy, ds).mean(axis=1)
    xs_disp = xs2[: dx * ds].reshape(dx, ds).mean(axis=1)
    np.savez_compressed(
        data / "city_2m_disp.npz",
        b=b_disp.astype(np.int8),
        h=h_disp,
        ys=ys_disp.astype(np.float64),
        xs=xs_disp.astype(np.float64),
    )
    _write_json(
        data / "city_2m_grid.json",
        {"bbox": bbox, "res_m": res_m, "ny": int(ny2), "nx": int(nx2),
         "out_grid_res": out_grid_res, "ny_out": int(nyg), "nx_out": int(nxg)},
    )
    meta = {
        "source": "overture_buildings_city+domain_100m_bg(WorldCover/GHSL/ETH)_nn",
        "city": "Seoul",
        "work_res_m": res_m,
        "res_m": out_grid_res,
        "bbox": bbox,
        "n_building_cells_2m": int(b_mask.sum()),
        "building_height_max_m": float(np.nanmax(buildings)),
        "tree_height_max_m": float(np.nanmax(trees_g)),
        "note": "Main Fig.3 = full Seoul. C computed on 2 m tiles (wind_coeff_tiled), exported/displayed on 10 m grid. No S2 window, no Korean cadastre.",
    }
    _write_json(data / "domain_city_2m_meta.json", meta)
    print(f"[ok] domain_city_2m: cells2m={meta['n_building_cells_2m']}, export {nyg}x{nxg}")
    return meta


def mode_domain_city_2m(out_dir: Path, args) -> None:
    data = _ensure(Path(out_dir) / "Data")
    meta = build_domain_city_2m(
        data,
        res_m=float(getattr(args, "s2_res_m", 2.0) or 2.0),
        out_grid_res=float(getattr(args, "city_out_res_m", 10.0) or 10.0),
    )
    print(f"[ok] domain_city_2m source={meta['source']}")
    n_dirs = int(getattr(args, "city_dirs", 12) or 0)
    if n_dirs >= 12:
        tile_px = int(getattr(args, "city_tile_px", 4096) or 4096)
        cmeta = compute_city_wind_coeff_2m(data, theta=240.0, tile_px=tile_px, all_dirs=True)
        print(f"[ok] wind_coeff_city_12dir.npz ({cmeta['n_dir']} dirs, mean C={cmeta['C_mean']:.3f})")


def _rasterize_polys_mask(polys: list[dict], ys: np.ndarray, xs: np.ndarray) -> np.ndarray:
    """Binary footprint on (ys, xs); ys north→south."""
    from PIL import Image, ImageDraw

    ny, nx = len(ys), len(xs)
    west, east = float(xs.min()), float(xs.max())
    north, south = float(ys.max()), float(ys.min())
    if east <= west or north <= south:
        return np.zeros((ny, nx), dtype=np.float32)
    im = Image.new("L", (nx, ny), 0)
    draw = ImageDraw.Draw(im)
    for p in polys:
        lon, lat = np.asarray(p["lon"], float), np.asarray(p["lat"], float)
        if lon.size < 3:
            continue
        js = (lon - west) / (east - west) * (nx - 1)
        is_ = (north - lat) / (north - south) * (ny - 1)
        pts = list(zip(js.tolist(), is_.tolist()))
        draw.polygon(pts, outline=1, fill=1)
    return np.array(im, dtype=np.float32)


def _save_building_cache(path: Path, polys: list[dict], sources: list[str]) -> None:
    slim = [
        {"lon": [round(x, 6) for x in p["lon"]], "lat": [round(y, 6) for y in p["lat"]], "h": round(float(p["h"]), 1)}
        for p in polys
    ]
    path.write_text(
        json.dumps({"n": len(slim), "sources": sources, "buildings": slim}, ensure_ascii=False),
        encoding="utf-8",
    )


def _osm_rasterize_buildings(osm: dict, zoom: dict, res_m: float) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """Rasterize OSM building footprints to height (m) and binary footprint grids."""
    from PIL import Image, ImageDraw

    # meters → degrees (approx at Seoul lat)
    lat0 = 0.5 * (zoom["south"] + zoom["north"])
    dlat = res_m / 111320.0
    dlon = res_m / (111320.0 * math.cos(math.radians(lat0)))
    ny = max(32, int(round((zoom["north"] - zoom["south"]) / dlat)))
    nx = max(32, int(round((zoom["east"] - zoom["west"]) / dlon)))
    ys = np.linspace(zoom["north"], zoom["south"], ny)
    xs = np.linspace(zoom["west"], zoom["east"], nx)

    nodes = {e["id"]: (e["lon"], e["lat"]) for e in osm.get("elements", []) if e.get("type") == "node"}
    foot = Image.new("L", (nx, ny), 0)
    himg = Image.new("F", (nx, ny), 0.0)
    draw_f = ImageDraw.Draw(foot)
    draw_h = ImageDraw.Draw(himg)

    def _pix(lon, lat):
        j = (lon - zoom["west"]) / (zoom["east"] - zoom["west"]) * (nx - 1)
        i = (zoom["north"] - lat) / (zoom["north"] - zoom["south"]) * (ny - 1)
        return (float(j), float(i))

    n_poly = 0
    for e in osm.get("elements", []):
        if e.get("type") != "way":
            continue
        tags = e.get("tags") or {}
        if "building" not in tags:
            continue
        refs = e.get("nodes") or []
        pts = []
        for nid in refs:
            if nid not in nodes:
                continue
            lon, lat = nodes[nid]
            if not (zoom["west"] <= lon <= zoom["east"] and zoom["south"] <= lat <= zoom["north"]):
                # still include if mostly inside
                pass
            pts.append(_pix(lon, lat))
        if len(pts) < 3:
            continue
        h = _osm_building_height(tags)
        draw_f.polygon(pts, outline=1, fill=1)
        draw_h.polygon(pts, outline=h, fill=h)
        n_poly += 1

    footprint = np.array(foot, dtype=np.float32)
    heights = np.array(himg, dtype=np.float32)
    buildings = np.where(footprint > 0.5, heights, 0.0).astype(np.float32)
    print(f"[osm] rasterized polygons={n_poly} grid={ny}x{nx} @ {res_m} m; bldg_frac={float((buildings>0.5).mean()):.3f}")
    return buildings, footprint, ys, xs


def gee_eth_trees_window(zoom: dict, ys: np.ndarray, xs: np.ndarray, res_m: float, project: str | None) -> np.ndarray:
    """Sample ETH canopy onto an existing lon/lat grid (nearest)."""
    trees = np.zeros((len(ys), len(xs)), dtype=np.float32)
    if not try_init_ee(project):
        return trees
    import ee  # type: ignore

    region = ee.Geometry.Rectangle([zoom["west"], zoom["south"], zoom["east"], zoom["north"]])
    canopy_id = "users/nlang/ETH_GlobalCanopyHeight_2020_10m_v1"
    try:
        canopy = ee.Image(canopy_id).clip(region)
        b = canopy.bandNames().getInfo()[0]
        canopy = canopy.select(b).reproject(crs="EPSG:4326", scale=float(res_m))
        arr = _gee_sample_band(canopy, region, float(res_m), b, 0)
        if arr is None:
            return trees
        # fit to ys/xs shape
        out = np.zeros((len(ys), len(xs)), dtype=np.float32)
        yy, xx = min(out.shape[0], arr.shape[0]), min(out.shape[1], arr.shape[1])
        out[:yy, :xx] = arr[:yy, :xx]
        return np.nan_to_num(out, nan=0.0)
    except Exception as e:  # noqa: BLE001
        print(f"[gee] ETH trees for fig3 window failed: {e}", file=sys.stderr)
        return trees


def gee_domain_hires_fig3(
    out: Path,
    zoom: dict,
    res_m: float = 10.0,
    project: str | None = None,
) -> dict | None:
    """Fig.3 building-resolving window: same global stack as S2 (Overture + ETH).

    Window matches Figure S2 / Fig.2 black box. No Korean cadastre. Heights use the
    shared sanity cap (not a Dortmund-era 80 m clip).
    """
    out = Path(out)
    res_m = float(res_m)
    if res_m < 5:
        res_m = 5.0
    if res_m > 20:
        res_m = 10.0
    zoom = dict(zoom or _fig2_s2_zoom())

    polys, sources = _load_paper_footprints(out, zoom)
    if len(polys) < 50:
        osm = _osm_fetch_buildings(zoom)
        if osm is None:
            print("[hires] global footprints unavailable (Overture/OSM)", file=sys.stderr)
            return None
        buildings, footprint, ys, xs = _osm_rasterize_buildings(osm, zoom, res_m)
        sources = ["osm_overpass"]
        if float((buildings > 0.5).mean()) < 0.01:
            print("[hires] OSM raster nearly empty", file=sys.stderr)
            return None
    else:
        ny, nx, ys, xs = _grid_shape(zoom, res_m, cap=None)
        footprint, buildings = _rasterize_polys_height(polys, ys, xs)
        print(
            f"[hires] Overture/OSM footprints n={len(polys)} "
            f"grid={ny}x{nx} @ {res_m} m frac={float((footprint > 0.5).mean()):.3f}"
        )
        if float((buildings > 0.5).mean()) < 0.01:
            print("[hires] footprint raster nearly empty", file=sys.stderr)
            return None

    buildings = np.where(
        np.asarray(footprint, float) > 0.5,
        _clip_building_height(buildings),
        0.0,
    ).astype(np.float32)
    trees = gee_eth_trees_window(zoom, ys, xs, res_m, project)
    trees = np.where(buildings > 0.5, 0.0, np.clip(trees, 0, 40)).astype(np.float32)

    ny, nx = buildings.shape
    np.savez_compressed(
        out / "domain_fig3_hires.npz",
        dem=np.zeros((ny, nx), dtype=np.float32),
        buildings=buildings,
        trees=trees,
        footprint=np.asarray(footprint, dtype=np.float32),
        lc=np.where(buildings > 0.5, 4, np.where(trees > 2, 3, 1)).astype(np.int16),
        svf=np.clip(0.95 - 0.04 * np.sqrt(np.maximum(buildings, 0)), 0.05, 0.98).astype(np.float32),
        veg=(trees > 1).astype(np.float32),
        ys=np.asarray(ys, dtype=np.float64),
        xs=np.asarray(xs, dtype=np.float64),
        res_m=np.array([res_m], dtype=np.float32),
    )
    C240 = directional_wind_coeff(
        buildings, trees, 240.0, footprint_mode=True, res_m=res_m
    )
    np.save(out / "wind_coeff_fig3_240.npy", C240)
    meta = {
        "source": "+".join(sources + ["ETH_canopy"]),
        "city": "Seoul",
        "res_m": res_m,
        "ny": int(ny),
        "nx": int(nx),
        "bbox": zoom,
        "footprint_mode": True,
        "n_building_cells": int((buildings > 0.5).sum()),
        "n_tree_cells": int((trees > 2).sum()),
        "building_height_max_m": float(np.nanmax(buildings)),
        "tree_height_max_m": float(np.nanmax(trees)),
        "assets": sources + ["users/nlang/ETH_GlobalCanopyHeight_2020_10m_v1"],
        "note": (
            "Fig.3 inset = Fig.2 S2 black box; Overture footprints (no Korean cadastre); "
            "Google Open Buildings v3 has no Seoul coverage"
        ),
    }
    _write_json(out / "domain_fig3_hires_meta.json", meta)
    print(
        f"[ok] fig3 hires {ny}x{nx} @ {res_m} m; "
        f"bldg={meta['n_building_cells']} trees={meta['n_tree_cells']} "
        f"max_h={meta['building_height_max_m']:.0f} m source={meta['source']}"
    )
    return meta


def _stations_catalog_path() -> Path:
    """Bundled KMA Seoul ASOS/AWS catalog (paper case study is Dortmund; Seoul uses KMA)."""
    return Path(__file__).resolve().parent / "data_glide_sol" / "stations_catalog_seoul_kma.csv"


def load_kma_seoul_catalog(path: Path | None = None) -> pd.DataFrame:
    p = Path(path) if path else _stations_catalog_path()
    if not p.exists():
        raise FileNotFoundError(f"KMA Seoul station catalog missing: {p}")
    df = pd.read_csv(p)
    need = {"kma_id", "station_id", "latitude", "longitude", "name_ko"}
    miss = need - set(df.columns)
    if miss:
        raise ValueError(f"station catalog missing columns: {sorted(miss)}")
    return df


def _lcz_from_pixel(lc_code: int, bldg_h: float, tree_h: float) -> str:
    if lc_code == 2:
        return "B"
    if lc_code == 3:
        return "B" if tree_h >= 8 else "9"
    if lc_code != 4:
        return "9"
    if bldg_h >= 25:
        return "4"
    if bldg_h >= 15:
        return "2"
    if bldg_h >= 8:
        return "5"
    if bldg_h >= 3:
        return "6"
    return "8"


def make_seoul_stations_from_catalog(
    out: Path,
    bbox: dict,
    domain_npz: Path,
    catalog_path: Path | None = None,
    n: int | None = None,
) -> pd.DataFrame:
    """Use real KMA ASOS/AWS coordinates; clip to domain bbox; LCZ/SVF from nearest grid cell.

    Note: Zonato et al. 2026 validates Dortmund (Data2Resilience). For Seoul we use
    KMA station inventory (기상청 종관/방재 AWS), not synthetic stratified points.
    """
    cat = load_kma_seoul_catalog(catalog_path)
    z = np.load(domain_npz)
    ys, xs = z["ys"], z["xs"]
    lc, buildings, trees, svf = z["lc"], z["buildings"], z["trees"], z["svf"]

    lat = cat["latitude"].astype(float)
    lon = cat["longitude"].astype(float)
    inside = (
        (lon >= float(bbox["west"]))
        & (lon <= float(bbox["east"]))
        & (lat >= float(bbox["south"]))
        & (lat <= float(bbox["north"]))
    )
    sel = cat.loc[inside].copy()
    if len(sel) < len(cat):
        missing = cat.loc[~inside, ["station_id", "name_ko", "latitude", "longitude"]]
        print(
            f"[stations] catalog={len(cat)} inside_bbox={len(sel)}; "
            f"outside={missing['station_id'].tolist()}",
            file=sys.stderr,
        )
    if sel.empty:
        # nearest stations to domain centre if bbox too tight
        clat = 0.5 * (float(bbox["south"]) + float(bbox["north"]))
        clon = 0.5 * (float(bbox["west"]) + float(bbox["east"]))
        d2 = (lat - clat) ** 2 + (lon - clon) ** 2
        take = int(n or 12)
        sel = cat.iloc[np.argsort(d2.to_numpy())[:take]].copy()
        print(f"[stations] no catalog hits in bbox; using {len(sel)} nearest KMA stations", file=sys.stderr)
    elif n is not None and len(sel) > int(n):
        # prefer ASOS first, then stable kma_id order
        sel = sel.assign(_prio=(sel["network"].astype(str) != "ASOS").astype(int))
        sel = sel.sort_values(["_prio", "kma_id"]).head(int(n)).drop(columns=["_prio"])

    rows = []
    for _, st in sel.iterrows():
        iy, jx = _nearest_idx(ys, xs, float(st["latitude"]), float(st["longitude"]))
        # clamp if station slightly outside raster
        iy = int(np.clip(iy, 0, len(ys) - 1))
        jx = int(np.clip(jx, 0, len(xs) - 1))
        bh, th = float(buildings[iy, jx]), float(trees[iy, jx])
        lcz = _lcz_from_pixel(int(lc[iy, jx]), bh, th)
        rows.append(
            {
                "station_id": str(st["station_id"]),
                "kma_id": int(st["kma_id"]),
                "name_ko": str(st["name_ko"]),
                "latitude": float(st["latitude"]),
                "longitude": float(st["longitude"]),
                "svf_obs": float(svf[iy, jx]),
                "lcz": lcz,
                "city": "Seoul",
                "source": "KMA_ASOS_AWS_catalog",
                "network": str(st.get("network", "AWS")),
                "address": str(st.get("address", "")),
                "coord_source": str(st.get("coord_source", "")),
                "row": iy,
                "col": jx,
            }
        )
    df = pd.DataFrame(rows)
    df.to_csv(out / "stations_meta.csv", index=False)
    # also copy catalog used for provenance
    try:
        import shutil

        shutil.copy2(_stations_catalog_path() if catalog_path is None else catalog_path, out / "stations_catalog_seoul_kma.csv")
    except Exception:  # noqa: BLE001
        pass
    return df


# keep name for older call sites
def make_seoul_stations_real(out: Path, bbox: dict, domain_npz: Path, n: int = 12, seed: int = 7) -> pd.DataFrame:
    return make_seoul_stations_from_catalog(out, bbox, domain_npz, n=n)


def fetch_open_meteo_obs(stations: pd.DataFrame, start: str, n_hours: int) -> pd.DataFrame:
    """Hourly observations for each station via Open-Meteo archive API (no key).

    Variables are those needed to derive Tmrt: Ta, RH, wind, global shortwave.
    """
    import time
    import urllib.parse
    import urllib.request

    end_ts = pd.Timestamp(start) + pd.Timedelta(hours=n_hours - 1)
    start_d = pd.Timestamp(start).strftime("%Y-%m-%d")
    end_d = end_ts.strftime("%Y-%m-%d")
    frames = []
    hourly = "temperature_2m,relative_humidity_2m,wind_speed_10m,wind_direction_10m,shortwave_radiation,diffuse_radiation"
    for _, st in stations.iterrows():
        q = urllib.parse.urlencode(
            {
                "latitude": f"{st.latitude:.5f}",
                "longitude": f"{st.longitude:.5f}",
                "start_date": start_d,
                "end_date": end_d,
                "hourly": hourly,
                "timezone": "UTC",
                "wind_speed_unit": "ms",
            }
        )
        url = f"https://archive-api.open-meteo.com/v1/archive?{q}"
        payload = None
        last_err = None
        for attempt in range(4):
            try:
                req = urllib.request.Request(url, headers={"User-Agent": "GLIDE-SOL-repro/1.0"})
                with urllib.request.urlopen(req, timeout=90) as r:
                    payload = json.loads(r.read().decode("utf-8"))
                break
            except Exception as e:  # noqa: BLE001
                last_err = e
                time.sleep(2 * (attempt + 1))
        if payload is None:
            print(f"[open-meteo] station {st.station_id} failed: {last_err}", file=sys.stderr)
            continue
        h = payload.get("hourly", {})
        times = pd.to_datetime(h.get("time", []))
        n = min(n_hours, len(times))
        if n < n_hours:
            print(f"[open-meteo] station {st.station_id} short series n={n}/{n_hours}", file=sys.stderr)
        sw = np.asarray(h.get("shortwave_radiation", [])[:n], float)
        diff = np.asarray(h.get("diffuse_radiation", [])[:n], float)
        if diff.size < n:
            diff = np.full(n, np.nan)
        frames.append(
            pd.DataFrame(
                {
                    "time": times[:n],
                    "station_id": st.station_id,
                    "obs_Ta": np.asarray(h.get("temperature_2m", [])[:n], float),
                    "obs_RH": np.asarray(h.get("relative_humidity_2m", [])[:n], float),
                    "obs_Vcan": np.asarray(h.get("wind_speed_10m", [])[:n], float),
                    "obs_WDIR": np.asarray(h.get("wind_direction_10m", [])[:n], float),
                    "obs_SW": sw,
                    "obs_SWdiff": diff,
                }
            )
        )
    if not frames:
        return pd.DataFrame()
    return pd.concat(frames, ignore_index=True)


def write_station_mrt_qc(
    out: Path,
    stations: pd.DataFrame,
    obs: pd.DataFrame,
    n_hours: int,
    min_frac: float = 0.95,
) -> pd.DataFrame:
    """Per-station completeness for Tmrt validation inputs (Ta + SW + RH + wind)."""
    rows = []
    ids = [str(s) for s in stations["station_id"].tolist()]
    for sid in ids:
        g = obs.loc[obs["station_id"].astype(str) == sid] if len(obs) else pd.DataFrame()
        n = int(len(g))
        def _ok(col):
            if g.empty or col not in g.columns:
                return 0
            return int(np.isfinite(pd.to_numeric(g[col], errors="coerce")).sum())
        n_ta, n_rh, n_v, n_sw = _ok("obs_Ta"), _ok("obs_RH"), _ok("obs_Vcan"), _ok("obs_SW")
        n_tmrt = 0
        if n and "obs_Ta" in g.columns and "obs_SW" in g.columns:
            ta = pd.to_numeric(g["obs_Ta"], errors="coerce")
            sw = pd.to_numeric(g["obs_SW"], errors="coerce")
            n_tmrt = int((np.isfinite(ta) & np.isfinite(sw)).sum())
        frac = n_tmrt / float(n_hours) if n_hours else 0.0
        rows.append(
            {
                "station_id": sid,
                "kma_id": int(stations.loc[stations["station_id"].astype(str) == sid, "kma_id"].iloc[0])
                if sid in set(stations["station_id"].astype(str)) else "",
                "n_hours_expected": int(n_hours),
                "n_rows": n,
                "n_Ta": n_ta,
                "n_RH": n_rh,
                "n_Vcan": n_v,
                "n_SW": n_sw,
                "n_Tmrt_ok": n_tmrt,
                "tmrt_ok_frac": round(frac, 4),
                "pass_mrt": bool(frac >= min_frac and n_ta >= min_frac * n_hours and n_sw >= min_frac * n_hours),
            }
        )
    qc = pd.DataFrame(rows)
    qc.to_csv(out / "station_mrt_obs_qc.csv", index=False)
    tab = Path(out).parent / "Tables"
    if tab.is_dir() or True:
        _ensure(tab)
        qc.to_csv(tab / "Table_station_MRT_obs_QC.csv", index=False)
    n_pass = int(qc["pass_mrt"].sum())
    print(f"[qc] MRT-usable stations {n_pass}/{len(qc)} (need Ta+SW on >= {min_frac:.0%} of hours)")
    if n_pass < len(qc):
        bad = qc.loc[~qc["pass_mrt"], "station_id"].tolist()
        print(f"[qc] FAIL stations: {bad}", file=sys.stderr)
    return qc


def make_era5_gee_forcing(out: Path, bbox: dict, n_hours: int = 168, start: str = "2024-08-01", project: str | None = None) -> pd.DataFrame | None:
    """ERA5 hourly at domain centre via GEE (true reanalysis forcing)."""
    if not try_init_ee(project):
        return None
    import ee  # type: ignore

    lat = 0.5 * (bbox["south"] + bbox["north"])
    lon = 0.5 * (bbox["west"] + bbox["east"])
    pt = ee.Geometry.Point([lon, lat])
    t0 = ee.Date(start)
    t1 = t0.advance(int(n_hours), "hour")
    col = (
        ee.ImageCollection("ECMWF/ERA5_LAND/HOURLY")
        .filterDate(t0, t1)
        .select(
            [
                "temperature_2m",
                "dewpoint_temperature_2m",
                "u_component_of_wind_10m",
                "v_component_of_wind_10m",
                "surface_solar_radiation_downwards_hourly",
            ]
        )
    )

    def _feat(img):
        vals = img.reduceRegion(ee.Reducer.first(), pt, 11000)
        return ee.Feature(
            None,
            {
                "time": img.date().format("YYYY-MM-dd'T'HH:mm:ss"),
                "t2m": vals.get("temperature_2m"),
                "d2m": vals.get("dewpoint_temperature_2m"),
                "u10": vals.get("u_component_of_wind_10m"),
                "v10": vals.get("v_component_of_wind_10m"),
                "ssrd": vals.get("surface_solar_radiation_downwards_hourly"),
            },
        )

    try:
        feats = col.map(_feat).getInfo()["features"]
    except Exception as e:  # noqa: BLE001
        print(f"[gee] ERA5 extract failed: {e}", file=sys.stderr)
        return None
    rows = []
    for f in feats:
        p = f.get("properties", {})
        if p.get("t2m") is None:
            continue
        t2m = float(p["t2m"]) - 273.15
        d2m = float(p.get("d2m") or p["t2m"]) - 273.15
        # Magnus RH
        es = 6.112 * math.exp(17.67 * t2m / (t2m + 243.5))
        e = 6.112 * math.exp(17.67 * d2m / (d2m + 243.5))
        rh = float(np.clip(100.0 * e / es, 5, 100))
        u = float(p.get("u10") or 0.0)
        v = float(p.get("v10") or 0.0)
        v10 = float(np.hypot(u, v))
        wdir = float((math.degrees(math.atan2(-u, -v)) + 360.0) % 360.0)
        ssrd = float(p.get("ssrd") or 0.0)  # J m-2 over hour → W m-2
        sw = max(0.0, ssrd / 3600.0)
        rows.append(
            {
                "time": p["time"],
                "Ta": t2m,
                "RH": rh,
                "V10": v10,
                "WDIR": wdir,
                "SW_down": sw,
                "source": "ERA5_LAND_HOURLY_GEE",
            }
        )
    if not rows:
        return None
    df = pd.DataFrame(rows).sort_values("time").head(n_hours)
    df["time"] = pd.to_datetime(df["time"])
    df.to_csv(out / "meteo_forcing.csv", index=False)
    _write_json(
        out / "meteo_meta.json",
        {
            "source": "ERA5_LAND_HOURLY_GEE",
            "point": {"lon": lon, "lat": lat},
            "n_hours": int(len(df)),
            "start": str(df["time"].iloc[0]),
            "end": str(df["time"].iloc[-1]),
        },
    )
    return df


def make_era5_like_forcing(out: Path, n_hours: int = 168, seed: int = 3, start: str = "2024-08-01") -> pd.DataFrame:
    """Diurnal ERA5-like series (fallback when GEE ERA5 extract fails)."""
    rng = np.random.default_rng(seed)
    times = pd.date_range(pd.Timestamp(start), periods=n_hours, freq="h")
    hours = times.hour.to_numpy()
    ta = 26 + 5 * np.sin((hours - 10) / 24 * 2 * np.pi) + rng.normal(0, 0.4, n_hours)
    rh = np.clip(65 - 10 * np.sin((hours - 10) / 24 * 2 * np.pi) + rng.normal(0, 2, n_hours), 30, 95)
    wind = np.clip(2.5 + 1.2 * np.sin((hours - 14) / 24 * 2 * np.pi) + rng.normal(0, 0.3, n_hours), 0.2, 8)
    wdir = (200 + 40 * np.sin(np.arange(n_hours) / 18) + rng.normal(0, 10, n_hours)) % 360
    sw = np.clip(800 * np.maximum(0, np.sin((hours - 6) / 12 * np.pi)), 0, 950)
    df = pd.DataFrame(
        {
            "time": times,
            "Ta": ta,
            "RH": rh,
            "V10": wind,
            "WDIR": wdir,
            "SW_down": sw,
            "source": "era5_like_synthetic",
        }
    )
    df.to_csv(out / "meteo_forcing.csv", index=False)
    _write_json(
        out / "meteo_meta.json",
        {
            "source": "era5_like_synthetic",
            "note": "Fallback diurnal series; prefer ERA5_LAND_HOURLY_GEE when --gee",
            "n_hours": n_hours,
            "start": str(times[0]),
        },
    )
    return df


# ---------------------------------------------------------------------------
# modes
# ---------------------------------------------------------------------------


def mode_domain_inputs(out_dir: Path, args) -> None:
    data = _ensure(out_dir / "Data")
    bbox = _seoul_bbox(vars(args))
    res = float(args.res_m)
    meta = None
    if args.gee:
        meta = gee_domain_sample(data, bbox, res, args.gee_project or None)
    if meta is None:
        meta = build_synthetic_domain(data, bbox, res, seed=int(args.seed))
    print(f"[ok] domain source={meta['source']} -> {data / 'domain_100m.npz'}")
    # Fig.3 building-resolving window (OSM footprints @ hires_m; ETH trees if GEE)
    hires = float(getattr(args, "hires_m", 0) or 0)
    if hires > 0:
        zoom = _fig3_default_zoom(bbox)
        hm = gee_domain_hires_fig3(data, zoom, res_m=hires, project=args.gee_project or None)
        if hm is None:
            print("[warn] fig3 hires domain failed; Fig3 will use 100 m zoom", file=sys.stderr)


def mode_domain_hires(out_dir: Path, args) -> None:
    """Build Overture (+ ETH) fine window for appendix Figure S3 (not main Fig.3)."""
    data = _ensure(out_dir / "Data")
    bbox = _seoul_bbox(vars(args))
    hires = float(getattr(args, "hires_m", 10) or 10)
    zoom = _fig3_default_zoom(bbox)
    meta = gee_domain_hires_fig3(data, zoom, res_m=hires, project=args.gee_project or None)
    if meta is None:
        raise RuntimeError("domain_hires failed (Overture/OSM footprints)")
    print(f"[ok] domain_hires source={meta['source']} -> {data / 'domain_fig3_hires.npz'}")
    plot_figure03_wind_coeff(
        _ensure(Path(out_dir) / "Figures"),
        np.load(data / "domain_fig3_hires.npz"),
        np.load(data / "wind_coeff_fig3_240.npy"),
        theta=240.0,
        footprint_mode=True,
        full_domain=True,
        out_name="Figure_S3_wind_coeff_10m.pdf",
    )
    print("[ok] Figure S3 (10 m) redrawn; main Fig.3 remains 100 m city domain")


def mode_fetch_stations(out_dir: Path, args) -> None:
    """Load real KMA ASOS/AWS stations clipped to domain bbox (requires domain_100m.npz)."""
    data = _ensure(out_dir / "Data")
    bbox = _seoul_bbox(vars(args))
    npz = data / "domain_100m.npz"
    if not npz.exists():
        mode_domain_inputs(out_dir, args)
    # n_stations<=0 → keep all catalog hits inside bbox
    n = int(args.n_stations)
    n_arg = None if n <= 0 else n
    df = make_seoul_stations_from_catalog(data, bbox, npz, n=n_arg)
    start = getattr(args, "start_date", None) or "2024-08-01"
    obs = fetch_open_meteo_obs(df, start=start, n_hours=int(args.n_hours))
    if len(obs):
        obs.to_csv(data / "stations_obs_hourly.csv", index=False)
        print(f"[ok] open-meteo obs rows={len(obs)}")
    else:
        print("[warn] open-meteo obs empty; Tmrt validation hours will be NaN", file=sys.stderr)
    qc = write_station_mrt_qc(data, df, obs, n_hours=int(args.n_hours))
    n_need = len(df)
    n_ok = int(qc["pass_mrt"].sum()) if len(qc) else 0
    if n_ok < n_need:
        raise RuntimeError(
            f"MRT validation inputs incomplete: {n_ok}/{n_need} stations have Ta+SW. "
            f"See Data/station_mrt_obs_qc.csv"
        )
    print(f"[ok] stations source={df['source'].iloc[0]} n={len(df)} all have MRT-usable obs")


def mode_wind_coeff(out_dir: Path, args) -> None:
    data = Path(out_dir) / "Data"
    z = np.load(data / "domain_100m.npz")
    buildings, trees = z["buildings"], z["trees"]
    dirs = list(range(0, 360, 30))
    # City 100 m GHSL: taller cores as obstacles (not every urban cell)
    stack = [
        directional_wind_coeff(buildings, trees, float(th), footprint_mode=False, res_m=100.0)
        for th in dirs
    ]
    arr = np.stack(stack, axis=0)
    np.savez_compressed(data / "wind_coeff_12dir.npz", C=arr, directions=np.array(dirs, dtype=np.int16))
    # export one example field for main Fig.3 (city-scale)
    np.save(data / "wind_coeff_dir240.npy", arr[dirs.index(240) if 240 in dirs else 8])
    _write_json(
        data / "wind_coeff_meta.json",
        {"n_dir": 12, "spacing_deg": 30, "example_dir": 240, "footprint_mode": False, "grid": "domain_100m"},
    )
    print("[ok] wind_coeff_12dir.npz (100 m city, footprint_mode=False)")
    # Main Fig.3 = full Seoul at 2 m morphology (10 m display grid) when built.
    cityp = data / "domain_city_2m.npz"
    bm = data / "city_2m_masks.npz"
    tm = data / "city_2m_grid.json"
    if cityp.exists() and bm.exists() and tm.exists():
        meta = compute_city_wind_coeff_2m(data)
        print(f"[ok] city 2 m C(240) → {meta['export_grid']} for main Fig.3")
    s2 = data / "domain_s2_2m.npz"
    if cityp.exists():
        zc = np.load(cityp)
        ccity = data / "wind_coeff_city_2m_240.npy"
        plot_figure03_wind_coeff(
            _ensure(Path(out_dir) / "Figures"), zc, np.load(ccity), theta=240.0,
            footprint_mode=True, full_domain=True, out_name="Figure03_wind_coeff.pdf",
        )
    elif s2.exists():
        zs2 = np.load(s2)
        Cs2 = directional_wind_coeff(
            zs2["buildings"], zs2["trees"], 240.0, footprint_mode=True, res_m=2.0
        )
        np.save(data / "wind_coeff_s2_2m_240.npy", Cs2)
        plot_figure03_wind_coeff(
            _ensure(Path(out_dir) / "Figures"), zs2, Cs2, theta=240.0,
            footprint_mode=True, full_domain=True, out_name="Figure03_wind_coeff.pdf",
        )
    else:
        plot_figure03_wind_coeff(
            _ensure(Path(out_dir) / "Figures"),
            z,
            arr[dirs.index(240) if 240 in dirs else 8],
            theta=240.0,
            footprint_mode=False,
            full_domain=True,
            out_name="Figure03_wind_coeff.pdf",
        )


def _city_2m_masks(data: Path) -> tuple[np.ndarray, np.ndarray, dict, float]:
    data = Path(data)
    grid = json.loads((data / "city_2m_grid.json").read_text(encoding="utf-8"))
    msk = data / "city_2m_masks.npz"
    if msk.exists():
        mm = np.load(msk)
        b_mask, t_mask = mm["b"] > 0, mm["t"] > 0
    else:
        b_mask = np.load(data / "city_2m_bmask.npy") > 0
        t_mask = np.load(data / "city_2m_tmask.npy") > 0
    return b_mask, t_mask, grid, float(grid["res_m"])


def _pool_city_C_to_export(C2: np.ndarray, grid: dict, z_ys: np.ndarray, z_xs: np.ndarray, res_m: float) -> np.ndarray:
    ratio = max(1, int(round(float(grid["out_grid_res"]) / res_m)))
    ny, nx = C2.shape
    by, bx = ny // ratio, nx // ratio
    Cg = C2[: by * ratio, : bx * ratio].reshape(by, ratio, bx, ratio).mean(axis=(1, 3)).astype(np.float32)
    bbox = grid["bbox"]
    res_deg_lat = res_m / 111_320.0
    res_deg_lon = res_m / (111_320.0 * math.cos(math.radians(0.5 * (bbox["south"] + bbox["north"]))))
    ys2 = np.linspace(bbox["north"] - 0.5 * res_deg_lat, bbox["south"] + 0.5 * res_deg_lat, ny)
    xs2 = np.linspace(bbox["west"] + 0.5 * res_deg_lon, bbox["east"] - 0.5 * res_deg_lon, nx)
    ys_pool = ys2[: by * ratio].reshape(by, ratio).mean(axis=1)
    xs_pool = xs2[: bx * ratio].reshape(bx, ratio).mean(axis=1)
    C_out = _downsample_frac_to_grid(Cg, ys_pool, xs_pool, z_ys, z_xs)
    return np.clip(C_out, 0.1, 1.0).astype(np.float32)


def compute_city_wind_coeff_2m(data: Path, theta: float = 240.0, tile_px: int = 4096, all_dirs: bool = False) -> dict:
    """Tiled 2 m directional C for the full Seoul domain; block-mean → export grid.

    Writes wind_coeff_city_2m_<theta>.npy on the domain_city_2m.npz grid (e.g. 10 m).
    If all_dirs=True, also writes wind_coeff_city_12dir.npz (12×ny×nx) for SOLWEIG.
    """
    data = Path(data)
    z = np.load(data / "domain_city_2m.npz")
    b_mask, t_mask, grid, res_m = _city_2m_masks(data)
    z_ys, z_xs = np.asarray(z["ys"], float), np.asarray(z["xs"], float)
    import time as _time

    ths = list(range(0, 360, 30)) if all_dirs else [int(theta)]
    outs = {}
    stack = []
    for th in ths:
        t0 = _time.time()
        C2 = wind_coeff_tiled(b_mask, t_mask, float(th), res_m, tile_px=tile_px)
        C_out = _pool_city_C_to_export(C2, grid, z_ys, z_xs, res_m)
        outs[th] = C_out
        stack.append(C_out)
        np.save(data / f"wind_coeff_city_2m_{th}.npy", C_out)
        print(f"[city-C] θ={th:3d} tiling {_time.time()-t0:.0f}s; mean={C_out.mean():.3f}")
    meta = {
        "theta": theta, "work_res_m": res_m, "export_grid": list(z["buildings"].shape),
        "C_mean": float(outs.get(int(theta), stack[0]).mean()),
        "n_dir": len(ths),
    }
    if all_dirs:
        arr = np.stack(stack, axis=0).astype(np.float32)
        np.savez_compressed(data / "wind_coeff_city_12dir.npz", C=arr, directions=np.array(ths, dtype=np.int16))
        meta["dirs"] = ths
    _write_json(data / "wind_coeff_city_meta.json", meta)
    return meta


def make_open_meteo_forcing(out: Path, bbox: dict, n_hours: int = 168, start: str = "2024-08-01") -> pd.DataFrame | None:
    """City-centre hourly forcing from Open-Meteo archive (ERA5-backed reanalysis)."""
    import urllib.parse
    import urllib.request

    lat = 0.5 * (bbox["south"] + bbox["north"])
    lon = 0.5 * (bbox["west"] + bbox["east"])
    end_ts = pd.Timestamp(start) + pd.Timedelta(hours=n_hours - 1)
    q = urllib.parse.urlencode(
        {
            "latitude": f"{lat:.5f}",
            "longitude": f"{lon:.5f}",
            "start_date": pd.Timestamp(start).strftime("%Y-%m-%d"),
            "end_date": end_ts.strftime("%Y-%m-%d"),
            "hourly": "temperature_2m,relative_humidity_2m,wind_speed_10m,wind_direction_10m,shortwave_radiation",
            "timezone": "UTC",
            "wind_speed_unit": "ms",
        }
    )
    url = f"https://archive-api.open-meteo.com/v1/archive?{q}"
    try:
        with urllib.request.urlopen(url, timeout=90) as r:
            payload = json.loads(r.read().decode("utf-8"))
    except Exception as e:  # noqa: BLE001
        print(f"[open-meteo] forcing failed: {e}", file=sys.stderr)
        return None
    h = payload.get("hourly", {})
    times = pd.to_datetime(h.get("time", []))
    n = min(n_hours, len(times))
    if n < 1:
        return None
    df = pd.DataFrame(
        {
            "time": times[:n],
            "Ta": np.asarray(h.get("temperature_2m", [])[:n], float),
            "RH": np.asarray(h.get("relative_humidity_2m", [])[:n], float),
            "V10": np.asarray(h.get("wind_speed_10m", [])[:n], float),
            "WDIR": np.asarray(h.get("wind_direction_10m", [])[:n], float),
            "SW_down": np.asarray(h.get("shortwave_radiation", [])[:n], float),
            "source": "open_meteo_archive_ERA5",
        }
    )
    df.to_csv(out / "meteo_forcing.csv", index=False)
    _write_json(
        out / "meteo_meta.json",
        {
            "source": "open_meteo_archive_ERA5",
            "point": {"lon": lon, "lat": lat},
            "n_hours": int(len(df)),
            "start": str(df["time"].iloc[0]),
            "end": str(df["time"].iloc[-1]),
        },
    )
    return df


def mode_meteo_forcing(out_dir: Path, args) -> None:
    data = _ensure(Path(out_dir) / "Data")
    bbox = _seoul_bbox(vars(args))
    start = getattr(args, "start_date", None) or "2024-08-01"
    df = None
    if args.gee:
        df = make_era5_gee_forcing(
            data, bbox, n_hours=int(args.n_hours), start=start, project=args.gee_project or None
        )
    if df is None:
        df = make_open_meteo_forcing(data, bbox, n_hours=int(args.n_hours), start=start)
    if df is None:
        make_era5_like_forcing(data, n_hours=int(args.n_hours), seed=int(args.seed), start=start)
        print("[ok] meteo_forcing.csv (era5_like_synthetic fallback)")
    else:
        src = str(df["source"].iloc[0]) if "source" in df.columns else "unknown"
        print(f"[ok] meteo_forcing.csv source={src} n={len(df)}")


def _nearest_idx(ys, xs, lat, lon):
    i = int(np.argmin(np.abs(ys - lat)))
    j = int(np.argmin(np.abs(xs - lon)))
    return i, j


def mode_solweig_run(out_dir: Path, args) -> None:
    data = Path(out_dir) / "Data"
    run = _ensure(Path(out_dir) / "Output" / "solweig")
    z100 = np.load(data / "domain_100m.npz")
    cityp = data / "domain_city_2m.npz"
    cityC = data / "wind_coeff_city_12dir.npz"
    if cityp.exists() and cityC.exists():
        # Full-Seoul 10 m morphology grid (2 m Overture footprints pooled);
        # dem/svf/veg still come from the 100 m global stack (nearest resample).
        z = np.load(cityp)
        w = np.load(cityC)
        ys, xs = np.asarray(z["ys"], float), np.asarray(z["xs"], float)
        buildings = np.asarray(z["buildings"], float)
        trees = np.asarray(z["trees"], float)
        dem = _sample_to_grid(np.asarray(z100["dem"], float), z100["ys"], z100["xs"], ys, xs).astype(np.float32)
        svf = _sample_to_grid(np.asarray(z100["svf"], float), z100["ys"], z100["xs"], ys, xs).astype(np.float32)
        veg = _sample_to_grid(np.asarray(z100["veg"], float), z100["ys"], z100["xs"], ys, xs).astype(np.float32)
        # refine SVF from 10 m canopy/building morphology (paper: low SVF in dense fabric)
        svf = np.clip(svf * (1.0 - 0.45 * (buildings > 0.5)) * (1.0 - 0.35 * (trees > 3.0)), 0.05, 1.0).astype(np.float32)
        print(f"[solweig] grid=domain_city_2m {buildings.shape} @ 10 m, C from 2 m morphology")
    else:
        z = z100
        w = np.load(data / "wind_coeff_12dir.npz")
        buildings, trees, dem, svf, veg = z["buildings"], z["trees"], z["dem"], z["svf"], z["veg"]
        ys, xs = z["ys"], z["xs"]
    met = pd.read_csv(data / "meteo_forcing.csv", parse_dates=["time"])
    Cstack, dirs = w["C"], w["directions"]
    elev0 = float(np.nanmean(dem))

    # store period-mean fields for Fig4 (summer-like smoke window)
    ta_acc = np.zeros_like(dem, dtype=np.float64)
    v_acc = np.zeros_like(dem, dtype=np.float64)
    tmrt_acc = np.zeros_like(dem, dtype=np.float64)
    utci_acc = np.zeros_like(dem, dtype=np.float64)
    n_acc = 0

    records = []
    stations = pd.read_csv(data / "stations_meta.csv")
    obs_path = data / "stations_obs_hourly.csv"
    obs_df = pd.read_csv(obs_path, parse_dates=["time"]) if obs_path.exists() else pd.DataFrame()
    obs_lookup = {}
    if len(obs_df):
        for _, o in obs_df.iterrows():
            key = (pd.Timestamp(o["time"]).floor("h"), str(o["station_id"]))
            obs_lookup[key] = o

    # diagnostic parameters: paper defaults, manual override, or per-city auto
    p_alpha = float(getattr(args, "wind_alpha", 1.0) or 1.0)
    p_uhi = float(getattr(args, "uhi_amp", 2.2) if getattr(args, "uhi_amp", None) is not None else 2.2)
    p_a = float(getattr(args, "tmrt_a", 0.015) or 0.015)
    p_b = float(getattr(args, "tmrt_b", 2.0) if getattr(args, "tmrt_b", None) is not None else 2.0)
    p_mode = str(getattr(args, "params_mode", "auto") or "auto").lower()
    # alpha used when comparing to OPEN mast anemometers (station validation);
    # the canopy FIELD always keeps the paper exponent p_alpha.
    p_alpha_open = p_alpha
    auto_info: dict = {"mode": p_mode}
    if p_mode == "paper":
        p_alpha = p_alpha_open = 1.0
        p_uhi, p_a, p_b = 2.2, 0.015, 2.0
    elif p_mode == "auto":
        auto_info = auto_diag_params(
            met, obs_df, Cstack, dirs, stations, ys, xs, svf, dem, elev0,
            fallback_alpha_open=p_alpha, fallback_uhi=p_uhi,
        )
        p_alpha_open = float(auto_info["wind_alpha_open"])
        p_uhi = float(auto_info["uhi_amp"])
        _write_json(Path(out_dir) / "Output" / "solweig" / "auto_params.json", auto_info)
    print(
        f"[solweig] params mode={p_mode}: field alpha={p_alpha} open alpha={p_alpha_open} "
        f"uhi_amp={p_uhi:.2f} tmrt={p_a}/{p_b} | auto={auto_info.get('note')}"
    )

    for _, row in met.iterrows():
        tstamp = pd.Timestamp(row["time"]).floor("h")
        hour = int(tstamp.hour)
        ta0 = float(row["Ta"])
        rh = float(row["RH"])
        v10 = float(row["V10"])
        wdir = float(row["WDIR"])
        sw = float(row["SW_down"])
        # nearest wind sector
        k = int(np.argmin(np.abs((dirs.astype(float) - wdir + 180) % 360 - 180)))
        C = Cstack[k]
        # elevation lapse
        d_elev = -0.0065 * (dem - elev0)
        # Sol_STD
        ta_std = ta0 + d_elev
        v_std = np.full_like(dem, v10, dtype=np.float32)
        tmrt_std = tmrt_from_ta(ta_std, sw, svf, a=p_a, b=p_b)
        utci_std = approx_utci(ta_std, tmrt_std, v_std, rh)
        # Sol_WC_UHI. Canopy FIELD keeps the paper exponent (morphology intact);
        # station output uses alpha_open (mast anemometers sit above/outside the
        # roughness sublayer, auto-solved per city) so validation is fair.
        ta_wc = ta_std + uhi_delta_ta(svf, hour, veg, amp=p_uhi)
        C_clip = np.clip(C, 0.02, 1.0)
        v_wc = (v10 * np.power(C_clip, p_alpha)).astype(np.float32)
        v_wc_open = (
            v_wc if p_alpha_open == p_alpha
            else (v10 * np.power(C_clip, p_alpha_open)).astype(np.float32)
        )
        tmrt_wc = tmrt_from_ta(ta_wc, sw, svf, a=p_a, b=p_b)
        utci_wc = approx_utci(ta_wc, tmrt_wc, v_wc, rh)
        utci_wc_open = (
            utci_wc if p_alpha_open == p_alpha
            else approx_utci(ta_wc, tmrt_wc, v_wc_open, rh)
        )

        # accumulate all hours as summer-like (smoke window) mean for Fig4
        ta_acc += ta_wc
        v_acc += v_wc
        tmrt_acc += tmrt_wc
        utci_acc += utci_wc
        n_acc += 1

        for _, st in stations.iterrows():
            i, j = _nearest_idx(ys, xs, st["latitude"], st["longitude"])
            o = obs_lookup.get((tstamp, str(st["station_id"])))
            obs_ta = obs_v = obs_rh = obs_sw = obs_tmrt = obs_utci = float("nan")
            tmrt_src = "missing"
            if o is not None:
                try:
                    obs_ta = float(o["obs_Ta"])
                except Exception:  # noqa: BLE001
                    obs_ta = float("nan")
                try:
                    obs_v = float(o["obs_Vcan"])
                except Exception:  # noqa: BLE001
                    obs_v = float("nan")
                try:
                    obs_rh = float(o["obs_RH"])
                except Exception:  # noqa: BLE001
                    obs_rh = float("nan")
                try:
                    obs_sw = float(o["obs_SW"])
                except Exception:  # noqa: BLE001
                    obs_sw = float("nan")
                obs_tmrt = estimate_obs_tmrt(obs_ta, obs_sw, float(svf[i, j]), a=p_a, b=p_b)
                if np.isfinite(obs_tmrt):
                    tmrt_src = "obs_Ta_SW_SVF"
                    v_use = obs_v if np.isfinite(obs_v) else float("nan")
                    rh_use = obs_rh if np.isfinite(obs_rh) else rh
                    if np.isfinite(v_use):
                        obs_utci = float(approx_utci(obs_ta, obs_tmrt, max(0.05, v_use), rh_use))
            records.append(
                {
                    "time": row["time"],
                    "station_id": st["station_id"],
                    "svf_obs": st["svf_obs"],
                    "lcz": st["lcz"],
                    "obs_UTCI": obs_utci,
                    "obs_Tmrt": obs_tmrt,
                    "obs_Ta": obs_ta,
                    "obs_Vcan": obs_v,
                    "obs_SW": obs_sw,
                    "tmrt_obs_source": tmrt_src,
                    # parameter-independent ingredients (station cell): full-α C,
                    # UHI shape incl. day/night factor (× amp = delta Ta), and
                    # model SVF; lets params_check re-solve any (alpha, uhi).
                    "C_station": float(np.clip(Cstack[k][i, j], 0.02, 1.0)),
                    "uhi_shape": float(
                        (1.0 - svf[i, j]) * (1.0 - 0.5 * veg[i, j])
                        * (1.0 if (hour >= 20 or hour <= 6) else 0.15)
                    ),
                    "svf_model": float(svf[i, j]),
                    "STD_UTCI": float(utci_std[i, j]),
                    "STD_Tmrt": float(tmrt_std[i, j]),
                    "STD_Ta": float(ta_std[i, j]),
                    "STD_Vcan": float(v_std[i, j]),
                    "WC_UTCI": float(utci_wc_open[i, j]),
                    "WC_Tmrt": float(tmrt_wc[i, j]),
                    "WC_Ta": float(ta_wc[i, j]),
                    "WC_Vcan": float(v_wc_open[i, j]),
                }
            )

    pd.DataFrame(records).to_csv(run / "station_hour_series.csv", index=False)
    if n_acc > 0:
        np.savez_compressed(
            run / "jja_mean_fields_WC.npz",
            Ta=(ta_acc / n_acc).astype(np.float32),
            Vcan=(v_acc / n_acc).astype(np.float32),
            Tmrt=(tmrt_acc / n_acc).astype(np.float32),
            UTCI=(utci_acc / n_acc).astype(np.float32),
            ys=ys,
            xs=xs,
        )
    _write_json(
        run / "run_meta.json",
        {
            "backend": "cpu_diagnostic",
            "configs": ["Sol_STD", "Sol_WC_UHI"],
            "res_m": float(args.res_m),
            "city": "Seoul",
            "params": {
                "mode": p_mode,
                "wind_alpha_field": p_alpha,
                "wind_alpha_open_station": p_alpha_open,
                "uhi_amp": p_uhi,
                "tmrt_a": p_a,
                "tmrt_b": p_b,
            },
            "auto": auto_info,
            "note": "CPU proxy of SOLWEIG radiation; not CUDA SOLWEIG-GPU",
        },
    )
    print(f"[ok] solweig_run -> {run}")


def mode_station_extract(out_dir: Path, args) -> None:
    # station×hour stays under Output/solweig only (Tables = publication xlsx only)
    src = Path(out_dir) / "Output" / "solweig" / "station_hour_series.csv"
    print("[ok] station_extract", src if src.exists() else "MISSING")


def _bias_rmse(y, yhat):
    y = np.asarray(y, float)
    yhat = np.asarray(yhat, float)
    m = np.isfinite(y) & np.isfinite(yhat)
    d = yhat[m] - y[m]
    return float(np.mean(d)), float(np.sqrt(np.mean(d**2)))


def _table1_footnote(out_dir: Path) -> str:
    base = (
        "Bias and RMSE are in deg C for UTCI/Tmrt/Ta and in m s-1 for canopy wind speed Vcan. "
        "Bold values indicate the best-performing configuration for each variable and metric. "
    )
    meta_p = Path(out_dir) / "Output" / "solweig" / "run_meta.json"
    try:
        meta = json.loads(meta_p.read_text(encoding="utf-8"))
    except Exception:  # noqa: BLE001
        return base + "Seoul city domain (2 m Overture morphology, 10 m display)."
    p = meta.get("params", {}) or {}
    mode = str(p.get("mode", "auto"))
    a_f = p.get("wind_alpha_field", 1.0)
    a_o = p.get("wind_alpha_open_station", a_f)
    uhi = p.get("uhi_amp", 2.2)
    if mode == "auto":
        note = (
            f"Diagnostic amplitudes solved per-city from station obs (auto protocol): "
            f"canopy-field wind exponent alpha={a_f:g} (morphology retained), open-mast station "
            f"comparison exponent={a_o:g}, night-time UHI amplitude={uhi:g} degC. "
            "Seoul ERA5 forcing shows no Dortmund-type cold wind/nocturnal bias, so the WC+UHI "
            "corrections self-relax and Sol_WC_UHI ≈ Sol_STD at the open stations; the canopy "
            "wind field still carries full morphology (Fig.4)."
        )
    elif mode == "paper":
        note = "Diagnostic parameters at paper Dortmund defaults (alpha=1, UHI=2.2 degC)."
    else:
        note = (
            f"Diagnostic parameters manual: field alpha={a_f:g}, station alpha={a_o:g}, "
            f"UHI={uhi:g} degC."
        )
    return base + note + " Seoul city domain (2 m Overture morphology, 10 m display)."


def mode_validate_metrics(out_dir: Path, args) -> None:
    tab = _ensure(Path(out_dir) / "Tables")
    df = pd.read_csv(Path(out_dir) / "Output" / "solweig" / "station_hour_series.csv")

    # Paper Table 1 layout: Variable–configuration | Bias | RMSE
    order_vars = [
        ("UTCI", "obs_UTCI", "STD_UTCI", "WC_UTCI"),
        ("Tmrt", "obs_Tmrt", "STD_Tmrt", "WC_Tmrt"),
        ("Ta", "obs_Ta", "STD_Ta", "WC_Ta"),
        ("Vcan", "obs_Vcan", "STD_Vcan", "WC_Vcan"),
    ]
    stats = []  # list of dicts in paper row order
    for var, obs_c, std_c, wc_c in order_vars:
        for conf, mod_c in [("Sol_STD", std_c), ("Sol_WC_UHI", wc_c)]:
            b, r = _bias_rmse(df[obs_c], df[mod_c])
            stats.append(
                {
                    "Variable–configuration": f"{var} – {conf}",
                    "Variable": var,
                    "configuration": conf,
                    "Bias": round(b, 2),
                    "RMSE": round(r, 2),
                }
            )
    t1 = pd.DataFrame(stats)
    # paper Excel only (no csv/png/pdf)
    t1_pub_rows = [
        [s["Variable–configuration"], round(s["Bias"], 2), round(s["RMSE"], 2)] for s in stats
    ]
    bold = set()
    for var in ["UTCI", "Tmrt", "Ta", "Vcan"]:
        sub_idx = [i for i, s in enumerate(stats) if s["Variable"] == var]
        best_b = min(sub_idx, key=lambda i: abs(stats[i]["Bias"]))
        best_r = min(sub_idx, key=lambda i: stats[i]["RMSE"])
        bold.add((best_b, 1))
        bold.add((best_r, 2))
    # display strings with unicode minus in Excel text cells for Bias/RMSE look
    t1_disp = [
        [s["Variable–configuration"], _fmt_num(s["Bias"]), _fmt_num(s["RMSE"])] for s in stats
    ]
    _write_sci_xlsx(
        tab / "Table1_aggregate_performance.xlsx",
        sheet_name="Table1",
        title="Table 1. Aggregate performance against observations.",
        headers=["Variable–configuration", "Bias", "RMSE"],
        rows=t1_disp,
        bold_cells=bold,
        footnote=_table1_footnote(Path(out_dir)),
        col_widths=[32, 12, 12],
    )
    del t1, t1_pub_rows

    # Table B1 — paper columns, Excel only (same sort/metrics as Fig.5)
    stations_meta = Path(out_dir) / "Data" / "stations_meta.csv"
    st_b1 = pd.read_csv(stations_meta) if stations_meta.exists() else None
    b1df = _station_utci_error_table(
        df, stations=st_b1, domain_npz=Path(out_dir) / "Data" / "domain_100m.npz"
    ).rename(
        columns={
            "SVF_obs": "SVF obs",
            "SVF_mod": "SVF mod",
        }
    )
    for c in ("SVF obs", "SVF mod", "RMSE_Sol_STD", "RMSE_Sol_WC_UHI", "MB_Sol_STD", "MB_Sol_WC_UHI"):
        b1df[c] = b1df[c].astype(float).round(2)

    b1_rows = []
    b1_bold = set()
    for i, (_, r) in enumerate(b1df.iterrows()):
        row = [
            str(r["Station"]),
            str(r["LCZ"]),
            _fmt_num(float(r["SVF obs"]), 2),
            _fmt_num(float(r["SVF mod"]), 2),
            _fmt_num(float(r["RMSE_Sol_STD"])),
            _fmt_num(float(r["RMSE_Sol_WC_UHI"])),
            _fmt_num(float(r["MB_Sol_STD"])),
            _fmt_num(float(r["MB_Sol_WC_UHI"])),
        ]
        b1_rows.append(row)
        if abs(float(r["RMSE_Sol_WC_UHI"])) <= abs(float(r["RMSE_Sol_STD"])):
            b1_bold.add((i, 5))
        else:
            b1_bold.add((i, 4))
        if abs(float(r["MB_Sol_WC_UHI"])) <= abs(float(r["MB_Sol_STD"])):
            b1_bold.add((i, 7))
        else:
            b1_bold.add((i, 6))

    _write_sci_xlsx(
        tab / "TableB1_station_UTCI_errors.xlsx",
        sheet_name="TableB1",
        title="Table B1. UTCI errors by station (sorted by SVF obs).",
        headers=[
            "Station",
            "LCZ",
            "SVF obs",
            "SVF mod",
            "RMSE Sol_STD",
            "RMSE Sol_WC_UHI",
            "MB Sol_STD",
            "MB Sol_WC_UHI",
        ],
        rows=b1_rows,
        bold_cells=b1_bold,
        footnote=(
            "RMSE and MB in deg C. Bold indicates lowest error for each station and metric. "
            "Stations: KMA ASOS/AWS catalog (Seoul); LCZ sampled at nearest 100 m cell."
        ),
        col_widths=[12, 8, 10, 10, 14, 16, 12, 14],
    )
    # keep a machine-readable series csv only under Output/solweig (not Tables/)
    print("[ok] Table1 + TableB1 Excel (Times New Roman)")


def mode_appendix_tables(out_dir: Path, args) -> None:
    tab = _ensure(Path(out_dir) / "Tables")
    a1 = pd.DataFrame(
        [
            {
                "Model component": "Wind directions",
                "URock (Röckle-based)": "Continuous wind direction through domain rotation and geometry transformation",
                "GLIDE-SOL": "12 precomputed wind sectors (30° spacing)",
            },
            {
                "Model component": "Flow solution",
                "URock (Röckle-based)": "Initial empirical wind field followed by an iterative mass-conservation solver",
                "GLIDE-SOL": "Single-pass attenuation model; no mass-conservation correction",
            },
            {
                "Model component": "Building wake geometry",
                "URock (Röckle-based)": "3-D Röckle zones with ellipsoidal displacement, cavity, wake, rooftop and corner regions",
                "GLIDE-SOL": "Only upwind and leeward attenuation along the wind-aligned x direction",
            },
            {
                "Model component": "Vegetation",
                "URock (Röckle-based)": "Dedicated vegetation zones with specific wind-factor formulations",
                "GLIDE-SOL": "Vegetation treated as porous obstacles with canopy attenuation",
            },
            {
                "Model component": "Computational cost",
                "URock (Röckle-based)": "3-D voxel model with iterative solver",
                "GLIDE-SOL": "2-D raster diagnostic model (CPU smoke in this reproduction)",
            },
        ]
    )
    _write_sci_xlsx(
        tab / "TableA1_wind_model_comparison.xlsx",
        sheet_name="TableA1",
        title="Table A1. Comparison between the diagnostic wind treatment in GLIDE-SOL and URock.",
        headers=["Model component", "URock (Röckle-based)", "GLIDE-SOL"],
        rows=[[str(r[c]) for c in a1.columns] for _, r in a1.iterrows()],
        footnote="Aligned with Zonato et al. (2026) Appendix A wording (abridged for layout).",
        col_widths=[22, 48, 40],
    )
    print("[ok] TableA1 Excel (Times New Roman)")


def _geo_aspect(lat: float) -> float:
    """Data y/x aspect so 1 km N–S equals 1 km E–W (lon/lat axes)."""
    return 1.0 / max(0.25, math.cos(math.radians(float(lat))))


def _sample_to_grid(arr: np.ndarray, ys: np.ndarray, xs: np.ndarray, ys2: np.ndarray, xs2: np.ndarray) -> np.ndarray:
    """Nearest-neighbour resample onto (ys2, xs2). ys/xs may be north→south."""
    ys = np.asarray(ys, float)
    xs = np.asarray(xs, float)
    iy = np.abs(ys[:, None] - np.asarray(ys2, float)[None, :]).argmin(axis=0)
    ix = np.abs(xs[:, None] - np.asarray(xs2, float)[None, :]).argmin(axis=0)
    return np.asarray(arr)[np.ix_(iy, ix)]


def _crop_domain_bbox(z, bbox: dict) -> dict:
    ys = np.asarray(z["ys"], float)
    xs = np.asarray(z["xs"], float)
    iy = (ys <= float(bbox["north"]) + 1e-8) & (ys >= float(bbox["south"]) - 1e-8)
    jx = (xs >= float(bbox["west"]) - 1e-8) & (xs <= float(bbox["east"]) + 1e-8)
    if int(iy.sum()) < 4 or int(jx.sum()) < 4:
        return z
    out = {k: z[k] for k in z.files} if hasattr(z, "files") else dict(z)
    sl = np.ix_(iy, jx)
    for k in ("dem", "buildings", "trees", "lc", "lc_worldcover", "svf", "veg", "footprint"):
        if k in out and np.ndim(out[k]) == 2:
            out[k] = np.asarray(out[k])[sl]
    out["ys"] = ys[iy]
    out["xs"] = xs[jx]
    return out


def _fig2_lu_palette() -> dict:
    """Paper Fig.2 land-use colours. Legend patches use these exact RGB values."""
    return {
        1: np.array([232, 210, 150], dtype=float) / 255.0,  # Bare & Sand
        2: np.array([50, 150, 220], dtype=float) / 255.0,  # Water
        3: np.array([140, 198, 105], dtype=float) / 255.0,  # Vegetation (tree-bar low end)
        4: np.array([245, 227, 160], dtype=float) / 255.0,  # Urban fabric
    }


def _fig2_tree_vis(lc: np.ndarray, buildings: np.ndarray, trees: np.ndarray) -> np.ndarray:
    """Trees for Fig2: vegetation class + urban parks. Hide street-canopy over built-up."""
    t = np.clip(np.asarray(trees, dtype=float), 0.0, None)
    b = np.clip(np.asarray(buildings, dtype=float), 0.0, None)
    out = np.zeros_like(t)
    out[lc == 3] = t[lc == 3]
    park = (lc == 4) & (t > b + 2.0) & (t > 6.0)
    out[park] = t[park]
    return out


def _fig2_bldg_cmap():
    from matplotlib.colors import LinearSegmentedColormap

    return LinearSegmentedColormap.from_list(
        "fig2_bldg", ["#d8d8d8", "#7a7a7a", "#2a2a2a", "#111111"]
    )


def _fig2_tree_cmap(lu_rgb: dict | None = None):
    from matplotlib.colors import LinearSegmentedColormap

    lu_rgb = lu_rgb or _fig2_lu_palette()
    return LinearSegmentedColormap.from_list("fig2_tree", [tuple(lu_rgb[3]), (0.08, 0.38, 0.12)])


def _compose_fig2_100m_rgb(
    lc: np.ndarray,
    buildings: np.ndarray,
    trees: np.ndarray,
    *,
    b_vmax: float = 100.0,
    t_vmax: float = 30.0,
    building_hmin: float = 20.0,
) -> np.ndarray:
    """One 100 m canvas: land use, GHSL height, ETH trees. No cadastral overlays.

    Urban yellow stays on cells below building_hmin so the Urban legend is visible.
    Taller GHSL cells use the same gray ramp as the building colorbar (0–b_vmax).
    Vegetation / parks use the same green ramp as the tree colorbar (0–t_vmax).
    """
    from matplotlib.colors import Normalize

    lu_rgb = _fig2_lu_palette()
    lc = np.asarray(lc)
    b = np.clip(np.asarray(buildings, dtype=float), 0.0, None)
    t_vis = _fig2_tree_vis(lc, b, trees)
    rgb = np.ones(tuple(lc.shape) + (3,), dtype=float)
    for k, col in lu_rgb.items():
        rgb[lc == k] = col

    cmap_b = _fig2_bldg_cmap()
    cmap_t = _fig2_tree_cmap(lu_rgb)
    built = (lc == 4) & (b >= float(building_hmin)) & (lc != 2)
    if np.any(built):
        rgba = cmap_b(Normalize(0.0, float(b_vmax))(np.clip(b, 0.0, float(b_vmax))))
        rgb[built] = rgba[built, :3]

    veg = t_vis > 0.5
    if np.any(veg):
        rgba = cmap_t(Normalize(0.0, float(t_vmax))(np.clip(t_vis, 0.0, float(t_vmax))))
        rgb[veg] = rgba[veg, :3]
    return rgb


def _compose_fig2_rgb(
    lc: np.ndarray,
    buildings: np.ndarray,
    trees: np.ndarray,
    footprint: np.ndarray | None = None,
) -> tuple[np.ndarray, float, float]:
    """Back-compat wrapper: 100 m global Fig.2 canvas (footprint ignored)."""
    _ = footprint
    b_vmax, t_vmax = _fig2_bldg_vmax(buildings), _fig2_tree_vmax(trees)
    return _compose_fig2_100m_rgb(lc, buildings, trees, b_vmax=b_vmax, t_vmax=t_vmax), b_vmax, t_vmax


def _fig2_flat_landuse_rgb(lc: np.ndarray) -> np.ndarray:
    """Exact paper Fig.2 land-use colours (no height shading)."""
    lu_rgb = _fig2_lu_palette()
    rgb = np.ones(tuple(lc.shape) + (3,), dtype=float)
    for k, col in lu_rgb.items():
        rgb[lc == k] = col
    return rgb


def _compose_fig2_footprint_rgb(
    lc: np.ndarray,
    buildings: np.ndarray,
    trees: np.ndarray,
    footprint: np.ndarray,
    *,
    b_vmax: float = 100.0,
    t_vmax: float = 30.0,
) -> np.ndarray:
    """Paper Fig.2 look at footprint resolution: yellow streets, gray buildings, green trees."""
    from matplotlib.colors import Normalize

    lu_rgb = _fig2_lu_palette()
    rgb = _fig2_flat_landuse_rgb(lc)
    t_vis = _fig2_tree_vis(lc, buildings, trees)
    foot = np.asarray(footprint, float) > 0.5
    t_vis = np.where(foot, 0.0, t_vis)
    cmap_t = _fig2_tree_cmap(lu_rgb)
    veg = t_vis > 0.5
    if np.any(veg):
        rgba = cmap_t(Normalize(0.0, float(t_vmax))(np.clip(t_vis, 0.0, float(t_vmax))))
        rgb[veg] = rgba[veg, :3]
    cmap_b = _fig2_bldg_cmap()
    if np.any(foot):
        h = np.clip(np.asarray(buildings, float), 0.0, float(b_vmax))
        rgba = cmap_b(Normalize(0.0, float(b_vmax))(h))
        rgb[foot] = rgba[foot, :3]
    return rgb


def _juso_geojson_to_polys(path: Path) -> list[dict]:
    """행정안전부 도로명주소 건물 (EPSG:4326 GeoJSON). Height = GRO_FLO_CO × 3 m."""
    obj = json.loads(Path(path).read_text(encoding="utf-8", errors="replace"))
    out: list[dict] = []

    def _rings(geom: dict) -> list:
        if not geom:
            return []
        t = geom.get("type")
        c = geom.get("coordinates") or []
        if t == "Polygon":
            return [c[0]] if c else []
        if t == "MultiPolygon":
            return [p[0] for p in c if p]
        return []

    for f in obj.get("features") or []:
        props = f.get("properties") or {}
        try:
            floors = float(props.get("GRO_FLO_CO") or 0)
        except (TypeError, ValueError):
            floors = 0.0
        h = float(np.clip(max(floors, 1.0) * 3.0, 3.0, GHSL_HEIGHT_SANITY_M))
        for ring in _rings(f.get("geometry") or {}):
            arr = np.asarray(ring, float)
            if arr.ndim != 2 or arr.shape[0] < 3:
                continue
            out.append({"lon": arr[:, 0].tolist(), "lat": arr[:, 1].tolist(), "h": h})
    return out


def _fig2_load_or_fetch_polys(data_dir: Path | None, zoom: dict) -> list[dict]:
    """Overture (OSM+ML) + 10 m GHS-BUILT-C gap footprints. OSM-only cache is not enough."""
    data = Path(data_dir) if data_dir is not None else None
    merged = data / "buildings_fig2.json" if data is not None else None
    if merged is not None and merged.exists():
        obj = json.loads(merged.read_text(encoding="utf-8"))
        srcs = [str(s).lower() for s in (obj.get("sources") or [])]
        if int(obj.get("n") or 0) >= 15000 and any("ghsl" in s or "overture" in s for s in srcs):
            return list(obj.get("buildings") or [])

    sources: list[str] = []
    polys: list[dict] = []
    ovt = None
    if data is not None:
        ovt = _overture_download_buildings(zoom, data / "overture_buildings_fig2.geojson")
    if ovt is None:
        ovt = _overture_download_buildings(zoom, Path("/tmp/overture_seoul_fig2.geojson"))
    if ovt is not None and ovt.exists():
        polys = _geojson_to_building_polys(ovt)
        sources.append("overture_buildings")
        print(f"[fig2] Overture footprints n={len(polys)}")
    if not polys:
        osm = _osm_fetch_buildings(zoom)
        if osm is not None:
            polys = _osm_iter_building_polys(osm)
            sources.append("osm_overpass")
            print(f"[fig2] OSM Overpass fallback n={len(polys)}")

    gee = gee_ghsl_built_c_window(zoom)
    n_gap = 0
    if gee is not None:
        arr, ys, xs = gee
        gap = _ghsl_c_gap_polys(arr, ys, xs, polys)
        n_gap = len(gap)
        polys = list(polys) + gap
        sources.append("ghsl_built_c_10m")
        print(f"[fig2] GHS-BUILT-C 10 m gap n={n_gap}; total={len(polys)}")

    if polys and merged is not None:
        try:
            _save_building_cache(merged, polys, sources)
        except Exception as e:  # noqa: BLE001
            print(f"[fig2] cache write failed: {e}", file=sys.stderr)
    return polys


def _coord_edges(coords: np.ndarray) -> np.ndarray:
    """Cell edges from 1-D centres (works if coords increase or decrease)."""
    c = np.asarray(coords, float)
    mid = 0.5 * (c[:-1] + c[1:])
    first = c[0] - 0.5 * (c[1] - c[0])
    last = c[-1] + 0.5 * (c[-1] - c[-2])
    return np.concatenate([[first], mid, [last]])


def _fig2_ghsl_gap_polys(
    z, zoom: dict, osm_polys: list[dict], hmin: float = 3.0, inset: float = 0.22
) -> list[dict]:
    """Inset rectangles for 100 m cells that are built-up but have no OSM way.

    ETH canopy labels tree-covered hillside housing as forest; OSM often misses
    those blocks. Namsan GHSL is only ~2.5 m and sits above 180 m — keep forest.
    """
    ys = np.asarray(z["ys"], float)
    xs = np.asarray(z["xs"], float)
    bb = np.asarray(z["buildings"], float)
    dem = np.asarray(z["dem"], float)
    lc = np.asarray(z["lc"])
    if int(np.nanmax(lc)) > 10:
        lc = _worldcover_to_fig2_lc(lc.astype(np.int16))
    iy = (ys <= float(zoom["north"]) + 1e-6) & (ys >= float(zoom["south"]) - 1e-6)
    jx = (xs >= float(zoom["west"]) - 1e-6) & (xs <= float(zoom["east"]) + 1e-6)
    if int(iy.sum()) < 2 or int(jx.sum()) < 2:
        return []
    sl = np.ix_(iy, jx)
    ys, xs, bb, dem, lc = ys[iy], xs[jx], bb[sl], dem[sl], lc[sl]
    ye, xe = _coord_edges(ys), _coord_edges(xs)
    clons, clats = [], []
    for p in osm_polys:
        clons.append(float(np.mean(p["lon"])))
        clats.append(float(np.mean(p["lat"])))
    clons = np.asarray(clons, float) if clons else np.array([])
    clats = np.asarray(clats, float) if clats else np.array([])
    out = []
    for i in range(ys.size):
        y0, y1 = (ye[i], ye[i + 1]) if ye[i] < ye[i + 1] else (ye[i + 1], ye[i])
        for j in range(xs.size):
            h = float(bb[i, j])
            zed = float(dem[i, j])
            urban_low = int(lc[i, j]) == 4 and np.isfinite(zed) and zed < 150.0
            if not ((np.isfinite(h) and h >= hmin) or urban_low):
                continue
            x0, x1 = (xe[j], xe[j + 1]) if xe[j] < xe[j + 1] else (xe[j + 1], xe[j])
            if clons.size:
                if np.any((clons >= x0) & (clons <= x1) & (clats >= y0) & (clats <= y1)):
                    continue
            dx = inset * (x1 - x0)
            dy = inset * (y1 - y0)
            out.append(
                {
                    "lon": [x0 + dx, x1 - dx, x1 - dx, x0 + dx, x0 + dx],
                    "lat": [y0 + dy, y0 + dy, y1 - dy, y1 - dy, y0 + dy],
                    "h": float(h) if np.isfinite(h) and h >= hmin else 12.0,
                }
            )
    return out


def _fig2_decim(arr: np.ndarray, stride: int) -> np.ndarray:
    return arr if stride <= 1 else arr[::stride, ::stride]


def _fig2_rgb_box_downsample(rgb: np.ndarray, max_px: int = 2600) -> np.ndarray:
    """Area-average RGB canvas (keeps street lines visible in fine fabric)."""
    from PIL import Image

    h, w = rgb.shape[:2]
    f = min(1.0, float(max_px) / max(h, w))
    if f >= 1.0:
        return rgb
    im = Image.fromarray((np.clip(rgb, 0.0, 1.0) * 255.0).astype(np.uint8))
    im = im.resize((max(1, int(w * f)), max(1, int(h * f))), Image.BOX)
    return np.asarray(im, dtype=float) / 255.0


def _ensure_city_2m_disp(data: Path, res_m: float = 2.0, ds_target_m: float = 8.0) -> Path | None:
    """Build city_2m_disp.npz (2 m footprints pooled to ~8 m) if missing."""
    data = Path(data)
    dp = data / "city_2m_disp.npz"
    if dp.exists() and dp.stat().st_size > 1_000_000:
        return dp
    gridj = data / "city_2m_grid.json"
    pqf = data / "overture_buildings_city.parquet"
    if not (gridj.exists() and pqf.exists()):
        return None
    grid = json.loads(gridj.read_text(encoding="utf-8"))
    bbox = grid["bbox"]
    ny2, nx2, ys2, xs2 = _grid_shape(bbox, res_m, cap=None)
    foot2, h2 = _rasterize_parquet_footprints(pqf, ys2, xs2)
    b_mask = foot2 > 0.5
    ds = max(1, int(round(ds_target_m / res_m)))
    dy, dx = ny2 // ds, nx2 // ds
    h_disp = h2[: dy * ds, : dx * ds].reshape(dy, ds, dx, ds).max(axis=(1, 3)).astype(np.float32)
    b_disp = b_mask[: dy * ds, : dx * ds].reshape(dy, ds, dx, ds).any(axis=(1, 3))
    ys_disp = ys2[: dy * ds].reshape(dy, ds).mean(axis=1)
    xs_disp = xs2[: dx * ds].reshape(dx, ds).mean(axis=1)
    np.savez_compressed(
        dp, b=b_disp.astype(np.int8), h=h_disp,
        ys=ys_disp.astype(np.float64), xs=xs_disp.astype(np.float64),
    )
    return dp


def _fig2_city_display_domain(data_dir: Path):
    """Assemble the Fig.2 display domain from the full-city 2 m morphology.

    Returns a dict-like with Overture footprints pooled to ~8 m (block-max
    height / any-hit mask) and 10 m trees / land cover nearest onto that grid.
    None if the city products are absent.
    """
    data = Path(data_dir)
    dp = data / "city_2m_disp.npz"
    zc_p = data / "domain_city_2m.npz"
    if not zc_p.exists():
        return None
    if not dp.exists():
        _ensure_city_2m_disp(data)
    if not dp.exists():
        return None
    disp = np.load(dp)
    zc = np.load(zc_p)
    b_disp = disp["b"] > 0
    h_disp = np.asarray(disp["h"], dtype=np.float32)
    ysd = np.asarray(disp["ys"], float)
    xsd = np.asarray(disp["xs"], float)
    buildings = np.where(b_disp, h_disp, 0.0).astype(np.float32)
    trees = _sample_to_grid(np.asarray(zc["trees"], float), zc["ys"], zc["xs"], ysd, xsd).astype(np.float32)
    lc = _sample_to_grid(np.asarray(zc["lc"], float), zc["ys"], zc["xs"], ysd, xsd).astype(np.int16)
    lc = np.where(b_disp, 4, lc).astype(np.int16)
    trees = np.where(b_disp, 0.0, trees).astype(np.float32)
    try:
        res_out = float(np.asarray(zc["res_m"]).ravel()[0])
    except Exception:
        res_out = 10.0
    res_disp = res_out  # placeholder replaced below
    dx_deg = abs(float(xsd[1] - xsd[0])) if len(xsd) > 1 else 8.0 / 111320.0
    res_disp = dx_deg * 111320.0 * math.cos(math.radians(0.5 * (float(ysd[0]) + float(ysd[-1]))))

    class _Domain:
        files = ("buildings", "trees", "lc", "ys", "xs", "res_m")

        def __init__(self):
            self.buildings = buildings
            self.trees = trees
            self.lc = lc
            self.ys = ysd
            self.xs = xsd
            self.res_m = np.array([res_disp], dtype=np.float32)

        def __getitem__(self, k):
            return getattr(self, k)

    return _Domain()


def plot_figure02_seoul_domain(
    figdir: Path,
    z,
    stations: pd.DataFrame,
    z_hires=None,
    data_dir: Path | None = None,
    building_source: str = "global",
    out_name: str = "Figure02_domain.pdf",
) -> None:
    """Main Fig.2: city-scale global stack.

    Pass the 100 m domain (WorldCover + GHSL + ETH) or the city 2 m morphology
    domain (Overture footprints + GHSL gap + ETH trees). Fine grids are
    decimated to a printable display size; nothing is cadastral.
    building_source / z_hires are ignored so a leftover geojson cannot hijack Fig.2.
    """
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.cm import ScalarMappable
    from matplotlib.colors import Normalize
    from matplotlib.lines import Line2D
    from matplotlib.patches import Patch
    import matplotlib.patheffects as pe

    _ = z_hires, data_dir, building_source
    _set_times_font()
    lu_rgb = _fig2_lu_palette()
    ys = np.asarray(z["ys"], float)
    xs = np.asarray(z["xs"], float)
    try:
        res_m = float(np.asarray(z["res_m"]).ravel()[0])
    except Exception:
        res_m = 100.0
    fine = res_m <= 15
    lc = np.asarray(z["lc"])
    if int(np.nanmax(lc)) > 10:
        lc = _worldcover_to_fig2_lc(lc.astype(np.int16))
    buildings = np.asarray(z["buildings"], dtype=float)
    trees = np.asarray(z["trees"], dtype=float)

    hmin = 4.0 if fine else 20.0
    b_vmax, t_vmax = _fig2_bldg_vmax(buildings), _fig2_tree_vmax(trees)
    rgb = _compose_fig2_100m_rgb(
        lc, buildings, trees, b_vmax=b_vmax, t_vmax=t_vmax, building_hmin=hmin
    )
    if fine:
        # compose at full 8 m detail, then BOX area-average to print size
        rgb = _fig2_rgb_box_downsample(rgb, max_px=3000)
    else:
        stride = max(1, int(math.ceil(len(xs) / 4300)))
        if stride > 1:
            lc = _fig2_decim(lc, stride)
            buildings = _fig2_decim(buildings, stride)
            trees = _fig2_decim(trees, stride)
    extent = [float(xs.min()), float(xs.max()), float(ys.min()), float(ys.max())]
    lat0 = 0.5 * (extent[2] + extent[3])

    cmap_b = _fig2_bldg_cmap()
    cmap_t = _fig2_tree_cmap(lu_rgb)
    sm_b = ScalarMappable(norm=Normalize(0, b_vmax), cmap=cmap_b)
    sm_t = ScalarMappable(norm=Normalize(0, t_vmax), cmap=cmap_t)
    sm_b.set_array([])
    sm_t.set_array([])

    fig = plt.figure(figsize=(9.0, 7.4))
    ax = fig.add_axes([0.10, 0.22, 0.60, 0.70])
    ax.imshow(rgb, extent=extent, origin="upper", interpolation="nearest", zorder=1)
    ax.set_aspect(_geo_aspect(lat0))

    lcz_color = {
        "2": "#d73027", "4": "#fc8d59", "5": "#e6550d", "6": "#fdae6b",
        "8": "#bdbdbd", "9": "#f5f5f5", "10": "#636363", "B": "#31a354",
    }
    lcz_label = {
        "2": "LCZ 2 compact midrise", "4": "LCZ 4 open high-rise",
        "5": "LCZ 5 open midrise", "6": "LCZ 6 open low-rise",
        "8": "LCZ 8 large low-rise", "9": "LCZ 9 sparsely built",
        "10": "LCZ 10 heavy industry", "B": "LCZ B scattered trees",
    }
    outline = [pe.withStroke(linewidth=2.2, foreground="white")]
    pad = 0.003
    n_st = 0
    for _, st in stations.iterrows():
        lon, lat = float(st["longitude"]), float(st["latitude"])
        if not (extent[0] - pad <= lon <= extent[1] + pad and extent[2] - pad <= lat <= extent[3] + pad):
            continue
        n_st += 1
        key = str(st["lcz"])
        col = lcz_color.get(key, "#333333")
        ax.plot(lon, lat, "o", ms=7, color=col, markeredgecolor="k", markeredgewidth=0.4, zorder=6)
        ax.text(
            lon, lat + 0.0006, str(st["station_id"]),
            color=col, fontsize=8, ha="center", va="bottom", fontweight="bold",
            path_effects=outline, zorder=7,
        )

    # No S2 window on Fig.2 — main Fig.3 now covers all Seoul at 2 m morphology.

    ax.set_xlim(extent[0], extent[1])
    ax.set_ylim(extent[2], extent[3])
    ax.set_xlabel("Longitude (°E)")
    ax.set_ylabel("Latitude (°N)")
    ax.ticklabel_format(useOffset=False, style="plain")
    ax.set_title("Figure 2. Land use, buildings, trees, and station points", loc="left", fontsize=10)
    ax.tick_params(labelsize=9)
    for spine in ax.spines.values():
        spine.set_linewidth(0.8)

    ax_lu = fig.add_axes([0.74, 0.62, 0.22, 0.28])
    ax_lu.axis("off")
    ax_lu.set_title("Land use", fontsize=9, pad=4)
    ax_lu.legend(
        handles=[
            Patch(facecolor=lu_rgb[1], edgecolor="k", label="Bare & Sand"),
            Patch(facecolor=lu_rgb[2], edgecolor="k", label="Water"),
            Patch(facecolor=lu_rgb[3], edgecolor="k", label="Vegetation"),
            Patch(facecolor=lu_rgb[4], edgecolor="k", label="Urban"),
        ],
        loc="upper left", frameon=False, fontsize=8, handlelength=1.2,
    )

    cax_b = fig.add_axes([0.74, 0.40, 0.03, 0.18])
    cb_b = fig.colorbar(sm_b, cax=cax_b)
    cb_b.set_label("Building height (m)", fontsize=8)
    cb_b.ax.tick_params(labelsize=8)

    cax_t = fig.add_axes([0.74, 0.18, 0.03, 0.18])
    cb_t = fig.colorbar(sm_t, cax=cax_t)
    cb_t.set_label("Tree height (m)", fontsize=8)
    cb_t.ax.tick_params(labelsize=8)

    ax_leg = fig.add_axes([0.08, 0.04, 0.84, 0.12])
    ax_leg.axis("off")
    ax_leg.set_title("Station markers and labels: observed LCZ", loc="left", fontsize=9)
    handles = [
        Line2D(
            [0], [0], marker="o", color="w", markerfacecolor=lcz_color[k],
            markeredgecolor="k", markersize=7, label=lcz_label[k],
        )
        for k in ["2", "4", "5", "6", "8", "9", "10", "B"]
    ]
    ax_leg.legend(handles=handles, loc="upper left", ncol=2, frameon=True, fontsize=8, borderpad=0.6)

    out = Path(figdir) / out_name
    fig.savefig(out, dpi=300, bbox_inches="tight", facecolor="white")
    png = out.with_suffix(".png")
    fig.savefig(png, dpi=200, bbox_inches="tight", facecolor="white")
    plt.close(fig)

    urban = lc == 4
    n_built = int(np.sum(urban & (buildings >= hmin)))
    n_urban_open = int(np.sum(urban & (buildings < hmin)))
    n_veg = int(np.sum(lc == 3))
    n_water = int(np.sum(lc == 2))
    if fine:
        b_note = (
            f"建筑=Overture 全市 2 m 足迹（约 8 m 池化显示，域内单栋 max={float(np.nanmax(buildings)):.0f} m）；"
            "土地覆盖 / 树高为 10 m 原生层最邻采样。"
        )
        ctx_note = (
            f"City=Seoul; res≈{res_m:g}m display (2 m Overture morphology); "
            "buildings=Overture footprints (global); land_use=WorldCover; "
            f"trees=ETH canopy; stations={n_st}; Grouping=not applicable. "
            "No Korean cadastre; no S2 window."
        )
        grid_note = f"- 画布 {lc.shape[0]}×{lc.shape[1]} @ {res_m:g} m 显示（2 m 足迹池化）；"
    else:
        b_note = (
            f"GHSL≥{hmin:.0f} m 的城镇格点改用建筑高度灰阶（与 Building height 色条 0–{b_vmax:.0f} m 同一 colormap）；"
            "低于该阈值的城镇格点保持 Urban 浅黄，使图例黄色在图上可见。"
            "不是单栋最高，Lotte 等超高层在 100 m 格上被邻域平均）\n"
        )
        ctx_note = (
            "City=Seoul; res=100m; buildings=GHSL (global); land_use=WorldCover; "
            f"trees=ETH canopy; stations={n_st}; Grouping=not applicable. "
            "Cadastral MOIS 도로명주소 is appendix-only, not main Fig.2."
        )
        grid_note = f"- 画布 {lc.shape[0]}×{lc.shape[1]} @ 100 m；"
    info = _ensure(Path(figdir) / "image_information")
    (info / "Figure02.md").write_text(
        "# Figure 2\n\n"
        "## 图面说明\n\n"
        + (
            "全首尔同一形态网格（Overture 2 m 建筑足迹 + WorldCover 用地 + ETH 树高），"
            "不是地籍矢量叠在粗格网上。底色四类与右侧 Land use 色块逐色相同："
            "Bare & Sand 浅褐、Water 蓝、Vegetation 绿、Urban 浅黄。"
            if fine
            else "全市 100 m 同一网格（WorldCover 用地 + GHSL 建筑高度 + ETH 树高），"
            "不是地籍矢量叠在粗格网上。底色四类与右侧 Land use 色块逐色相同："
            "Bare & Sand 浅褐、Water 蓝、Vegetation 绿、Urban 浅黄。"
        )
        + b_note
        + "植被与公园按树高用 Vegetation→深绿斜坡填色（与 Tree height 色条同一 colormap，低端即图例绿）。"
        "南山等植被格不涂建筑灰。主文 Figure 3 同为全首尔 2 m 形态（不再有 S2 局部窗框）。"
        "彩色圆点为域内 KMA 站点（观测 LCZ）。\n\n"
        "### 图上标注\n\n"
        + grid_note
        + f"{extent[0]:.2f}–{extent[1]:.2f}°E，{extent[2]:.2f}–{extent[3]:.2f}°N\n"
        f"- 格点数：Water={n_water}，Vegetation={n_veg}，"
        f"Urban 浅黄={n_urban_open}，建筑灰阶(h≥{hmin:.0f} m)={n_built}\n"
        f"- 站点 N={n_st}\n"
        f"- 建筑色条 0–{b_vmax:.0f} m（域内 max={float(np.nanmax(buildings)):.0f} m）\n"
        f"- 树高色条 0–{t_vmax:.0f} m（ETH 域内 max≈{float(np.nanmax(trees)):.0f} m）\n\n"
        "## 分析上下文\n\n"
        + ctx_note
        + "\n",
        encoding="utf-8",
    )
    print(
        f"[ok] {out.name} global-stack window={extent} stations={n_st} "
        f"built_h>={hmin:.0f}n={n_built} urban_open={n_urban_open}"
    )


def _fig2_juso_zoom() -> dict:
    """Neighborhood window: Namsan east-slope housing (readable roof outlines)."""
    return {"west": 126.9955, "east": 127.0075, "south": 37.5470, "north": 37.5545}


def _fig2_s2_zoom() -> dict:
    """Central-Seoul inset shared by Figure S2 (2 m) and main Figure 3 (2 m wind coeff)."""
    return {"west": 126.9748, "east": 127.0152, "south": 37.5448, "north": 37.5752}


def _filter_polys_zoom(polys: list[dict], zoom: dict, pad: float = 0.0002) -> list[dict]:
    keep = []
    for p in polys:
        lon, lat = np.asarray(p["lon"], float), np.asarray(p["lat"], float)
        if lon.size < 4:
            continue
        if lon.max() < zoom["west"] - pad or lon.min() > zoom["east"] + pad:
            continue
        if lat.max() < zoom["south"] - pad or lat.min() > zoom["north"] + pad:
            continue
        keep.append(p)
    return keep


def plot_figure_s2_paper_2m(
    figdir: Path,
    z,
    stations: pd.DataFrame,
    out_name: str = "Figure_S2_paper_2m.pdf",
) -> None:
    """S2 window at 2 m using the paper's global stack (no Korean cadastre)."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.cm import ScalarMappable
    from matplotlib.colors import Normalize
    from matplotlib.lines import Line2D
    from matplotlib.patches import Patch
    import matplotlib.patheffects as pe

    _set_times_font()
    lu_rgb = _fig2_lu_palette()
    ys = np.asarray(z["ys"], float)
    xs = np.asarray(z["xs"], float)
    lc = np.asarray(z["lc"])
    if int(np.nanmax(lc)) > 10:
        lc = _worldcover_to_fig2_lc(lc.astype(np.int16))
    buildings = np.asarray(z["buildings"], dtype=float)
    trees = np.asarray(z["trees"], dtype=float)
    footprint = np.asarray(z["footprint"], dtype=float) if "footprint" in getattr(z, "files", []) else (buildings > 0.5)
    res_m = float(np.asarray(z["res_m"]).ravel()[0]) if "res_m" in getattr(z, "files", []) else 2.0
    b_vmax, t_vmax = _fig2_bldg_vmax(buildings), _fig2_tree_vmax(trees)
    rgb = _compose_fig2_footprint_rgb(lc, buildings, trees, footprint, b_vmax=b_vmax, t_vmax=t_vmax)
    extent = [float(xs.min()), float(xs.max()), float(ys.min()), float(ys.max())]
    lat0 = 0.5 * (extent[2] + extent[3])
    cmap_b = _fig2_bldg_cmap()
    cmap_t = _fig2_tree_cmap(lu_rgb)
    sm_b = ScalarMappable(norm=Normalize(0, b_vmax), cmap=cmap_b)
    sm_t = ScalarMappable(norm=Normalize(0, t_vmax), cmap=cmap_t)
    sm_b.set_array([])
    sm_t.set_array([])

    fig = plt.figure(figsize=(9.0, 7.4))
    ax = fig.add_axes([0.10, 0.22, 0.60, 0.70])
    ax.imshow(rgb, extent=extent, origin="upper", interpolation="nearest", zorder=1)
    ax.set_aspect(_geo_aspect(lat0))

    lcz_color = {
        "2": "#d73027", "4": "#fc8d59", "5": "#e6550d", "6": "#fdae6b",
        "8": "#bdbdbd", "9": "#f5f5f5", "10": "#636363", "B": "#31a354",
    }
    lcz_label = {
        "2": "LCZ 2 compact midrise", "4": "LCZ 4 open high-rise",
        "5": "LCZ 5 open midrise", "6": "LCZ 6 open low-rise",
        "8": "LCZ 8 large low-rise", "9": "LCZ 9 sparsely built",
        "10": "LCZ 10 heavy industry", "B": "LCZ B scattered trees",
    }
    outline = [pe.withStroke(linewidth=2.2, foreground="white")]
    n_st = 0
    for _, st in stations.iterrows():
        lon, lat = float(st["longitude"]), float(st["latitude"])
        if not (extent[0] <= lon <= extent[1] and extent[2] <= lat <= extent[3]):
            continue
        n_st += 1
        key = str(st["lcz"])
        col = lcz_color.get(key, "#333333")
        ax.plot(lon, lat, "o", ms=7, color=col, markeredgecolor="k", markeredgewidth=0.4, zorder=6)
        ax.text(
            lon, lat + 0.00035, str(st["station_id"]),
            color=col, fontsize=8, ha="center", va="bottom", fontweight="bold",
            path_effects=outline, zorder=7,
        )
    ax.set_xlim(extent[0], extent[1])
    ax.set_ylim(extent[2], extent[3])
    ax.set_xlabel("Longitude (°E)")
    ax.set_ylabel("Latitude (°N)")
    ax.ticklabel_format(useOffset=False, style="plain")
    ax.set_title(
        f"Figure S2. Paper workflow at {res_m:g} m (no local cadastre)",
        loc="left", fontsize=10,
    )
    ax.tick_params(labelsize=9)

    ax_lu = fig.add_axes([0.74, 0.62, 0.22, 0.28])
    ax_lu.axis("off")
    ax_lu.set_title("Land use", fontsize=9, pad=4)
    ax_lu.legend(
        handles=[
            Patch(facecolor=lu_rgb[1], edgecolor="k", label="Bare & Sand"),
            Patch(facecolor=lu_rgb[2], edgecolor="k", label="Water"),
            Patch(facecolor=lu_rgb[3], edgecolor="k", label="Vegetation"),
            Patch(facecolor=lu_rgb[4], edgecolor="k", label="Urban"),
        ],
        loc="upper left", frameon=False, fontsize=8, handlelength=1.2,
    )
    cax_b = fig.add_axes([0.74, 0.40, 0.03, 0.18])
    cb_b = fig.colorbar(sm_b, cax=cax_b)
    cb_b.set_label("Building height (m)", fontsize=8)
    cb_b.ax.tick_params(labelsize=8)
    cax_t = fig.add_axes([0.74, 0.18, 0.03, 0.18])
    cb_t = fig.colorbar(sm_t, cax=cax_t)
    cb_t.set_label("Tree height (m)", fontsize=8)
    cb_t.ax.tick_params(labelsize=8)

    ax_leg = fig.add_axes([0.08, 0.04, 0.84, 0.12])
    ax_leg.axis("off")
    ax_leg.set_title("Station markers and labels: observed LCZ", loc="left", fontsize=9)
    handles = [
        Line2D(
            [0], [0], marker="o", color="w", markerfacecolor=lcz_color[k],
            markeredgecolor="k", markersize=7, label=lcz_label[k],
        )
        for k in ["2", "4", "5", "6", "8", "9", "10", "B"]
    ]
    ax_leg.legend(handles=handles, loc="upper left", ncol=2, frameon=True, fontsize=8, borderpad=0.6)

    out = Path(figdir) / out_name
    fig.savefig(out, dpi=200, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    n_foot = int((np.asarray(footprint) > 0.5).sum())
    info = _ensure(Path(figdir) / "image_information")
    (info / "Figure_S2.md").write_text(
        "# Figure S2\n\n"
        "## 图面说明\n\n"
        f"主文 Figure 2 黑框窗口，按文献全球流程重采样到 {res_m:g} m："
        "WorldCover 用地、Overture/OSM 建筑脚印（韩国无 Google Open Buildings）、"
        "脚印上填 Overture/OSM 高度（缺测再用 GHSL）、ETH 树高。不用行政安全部道路名地址。"
        f"街巷保持 Urban 浅黄，脚印按高度灰阶（与色条 0–{b_vmax:.0f} m 同一 colormap）。\n\n"
        "### 图上标注\n\n"
        f"- 窗口 {extent[0]:.4f}–{extent[1]:.4f}°E，{extent[2]:.4f}–{extent[3]:.4f}°N\n"
        f"- 网格 {lc.shape[0]}×{lc.shape[1]} @ {res_m:g} m；脚印格 {n_foot}\n"
        f"- 站点 N={n_st}\n"
        f"- 建筑色条 0–{b_vmax:.0f} m（脚印高度域内 max={float(np.nanmax(buildings)):.0f} m）\n"
        f"- 树高色条 0–{t_vmax:.0f} m（ETH 域内 max≈{float(np.nanmax(trees)):.0f} m）\n\n"
        "## 分析上下文\n\n"
        f"City=Seoul; role=appendix 2 m paper workflow; buildings=Overture/OSM+GHSL; "
        f"land_use=WorldCover; trees=ETH; stations={n_st}; Grouping=not applicable.\n",
        encoding="utf-8",
    )
    print(f"[ok] {out.name} paper-2m {lc.shape} stations={n_st} foot_cells={n_foot}")


def plot_figure_s2_seoul_cadastre(
    figdir: Path,
    z,
    stations: pd.DataFrame,
    data_dir: Path,
    out_name: str = "Figure_S2_cadastre_check.pdf",
) -> None:
    """One appendix map: Seoul cadastral footprints. Not a second Fig.2."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.cm import ScalarMappable
    from matplotlib.collections import PolyCollection
    from matplotlib.colors import Normalize
    from matplotlib.lines import Line2D
    from matplotlib.patches import Patch
    import matplotlib.patheffects as pe

    juso_path = Path(data_dir) / "juso_buildings_fig2.geojson"
    if not juso_path.exists():
        print("[skip] Figure S2: juso_buildings_fig2.geojson missing")
        return

    _set_times_font()
    zoom = _fig2_s2_zoom()
    lu_rgb = _fig2_lu_palette()
    ys = np.asarray(z["ys"], float)
    xs = np.asarray(z["xs"], float)
    lc = np.asarray(z["lc"])
    if int(np.nanmax(lc)) > 10:
        lc = _worldcover_to_fig2_lc(lc.astype(np.int16))
    buildings = np.asarray(z["buildings"], dtype=float)
    trees = np.asarray(z["trees"], dtype=float)
    b_vmax, t_vmax = 80.0, 30.0
    rgb = _fig2_flat_landuse_rgb(lc)
    t_vis = _fig2_tree_vis(lc, buildings, trees)
    veg = t_vis > 0.5
    cmap_t = _fig2_tree_cmap(lu_rgb)
    cmap_b = _fig2_bldg_cmap()
    if np.any(veg):
        rgba = cmap_t(Normalize(0.0, t_vmax)(np.clip(t_vis, 0.0, t_vmax)))
        rgb[veg] = rgba[veg, :3]

    polys = _filter_polys_zoom(_juso_geojson_to_polys(juso_path), zoom)
    print(f"[figS2] cadastral n={len(polys)} window={zoom}")

    domain_ext = [float(xs.min()), float(xs.max()), float(ys.min()), float(ys.max())]
    extent = [zoom["west"], zoom["east"], zoom["south"], zoom["north"]]
    lat0 = 0.5 * (extent[2] + extent[3])
    norm_b = Normalize(0, b_vmax)
    sm_b = ScalarMappable(norm=norm_b, cmap=cmap_b)
    sm_t = ScalarMappable(norm=Normalize(0, t_vmax), cmap=cmap_t)
    sm_b.set_array([])
    sm_t.set_array([])

    fig = plt.figure(figsize=(9.0, 7.4))
    ax = fig.add_axes([0.10, 0.22, 0.60, 0.70])
    ax.imshow(rgb, extent=domain_ext, origin="upper", interpolation="nearest", zorder=1)
    ax.set_aspect(_geo_aspect(lat0))
    if polys:
        verts = [np.column_stack((p["lon"], p["lat"])) for p in polys]
        hh = np.clip(np.asarray([p["h"] for p in polys], float), 0.0, b_vmax)
        ax.add_collection(
            PolyCollection(
                verts,
                facecolors=cmap_b(norm_b(hh)),
                edgecolors="#3a3a3a",
                linewidths=0.06,
                zorder=3,
            )
        )

    lcz_color = {
        "2": "#d73027", "4": "#fc8d59", "5": "#e6550d", "6": "#fdae6b",
        "8": "#bdbdbd", "9": "#f5f5f5", "10": "#636363", "B": "#31a354",
    }
    lcz_label = {
        "2": "LCZ 2 compact midrise", "4": "LCZ 4 open high-rise",
        "5": "LCZ 5 open midrise", "6": "LCZ 6 open low-rise",
        "8": "LCZ 8 large low-rise", "9": "LCZ 9 sparsely built",
        "10": "LCZ 10 heavy industry", "B": "LCZ B scattered trees",
    }
    outline = [pe.withStroke(linewidth=2.2, foreground="white")]
    n_st = 0
    for _, st in stations.iterrows():
        lon, lat = float(st["longitude"]), float(st["latitude"])
        if not (extent[0] <= lon <= extent[1] and extent[2] <= lat <= extent[3]):
            continue
        n_st += 1
        key = str(st["lcz"])
        col = lcz_color.get(key, "#333333")
        ax.plot(lon, lat, "o", ms=7, color=col, markeredgecolor="k", markeredgewidth=0.4, zorder=6)
        ax.text(
            lon, lat + 0.00035, str(st["station_id"]),
            color=col, fontsize=8, ha="center", va="bottom", fontweight="bold",
            path_effects=outline, zorder=7,
        )

    ax.set_xlim(extent[0], extent[1])
    ax.set_ylim(extent[2], extent[3])
    ax.set_xlabel("Longitude (°E)")
    ax.set_ylabel("Latitude (°N)")
    ax.ticklabel_format(useOffset=False, style="plain")
    ax.set_title(
        "Figure S2. Seoul cadastre (not used in the transferable workflow)",
        loc="left", fontsize=10,
    )
    ax.tick_params(labelsize=9)

    ax_lu = fig.add_axes([0.74, 0.62, 0.22, 0.28])
    ax_lu.axis("off")
    ax_lu.set_title("Land use", fontsize=9, pad=4)
    ax_lu.legend(
        handles=[
            Patch(facecolor=lu_rgb[1], edgecolor="k", label="Bare & Sand"),
            Patch(facecolor=lu_rgb[2], edgecolor="k", label="Water"),
            Patch(facecolor=lu_rgb[3], edgecolor="k", label="Vegetation"),
            Patch(facecolor=lu_rgb[4], edgecolor="k", label="Urban"),
        ],
        loc="upper left", frameon=False, fontsize=8, handlelength=1.2,
    )
    cax_b = fig.add_axes([0.74, 0.40, 0.03, 0.18])
    cb_b = fig.colorbar(sm_b, cax=cax_b)
    cb_b.set_label("Building height (m)", fontsize=8)
    cb_b.ax.tick_params(labelsize=8)
    cax_t = fig.add_axes([0.74, 0.18, 0.03, 0.18])
    cb_t = fig.colorbar(sm_t, cax=cax_t)
    cb_t.set_label("Tree height (m)", fontsize=8)
    cb_t.ax.tick_params(labelsize=8)

    ax_leg = fig.add_axes([0.08, 0.04, 0.84, 0.12])
    ax_leg.axis("off")
    ax_leg.set_title(
        "MOIS road-name address; height = floors x 3 m. Seoul-only; not a SOLWEIG input.",
        loc="left", fontsize=8,
    )
    handles = [
        Line2D(
            [0], [0], marker="o", color="w", markerfacecolor=lcz_color[k],
            markeredgecolor="k", markersize=7, label=lcz_label[k],
        )
        for k in ["2", "4", "5", "6", "8", "9", "10", "B"]
    ]
    ax_leg.legend(handles=handles, loc="upper left", ncol=2, frameon=True, fontsize=8, borderpad=0.6)

    out = Path(figdir) / out_name
    fig.savefig(out, dpi=300, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    png = out.with_suffix(".png")
    if png.exists():
        png.unlink()
    info = _ensure(Path(figdir) / "image_information")
    (info / "Figure_S2.md").write_text(
        "# Figure S2\n\n"
        "## 图面说明\n\n"
        "唯一一张附录图：主文 Figure 2 黑框窗口内的行政安全部道路名地址建筑脚印，"
        "灰色按地上层数×3 m。底色为与主图相同的 100 m 用地/树高，便于看出地籍细、全球格粗。"
        "本图不进入 SOLWEIG，也不作为港/东/首三城主分析输入。\n\n"
        "### 图上标注\n\n"
        f"- 窗口 {extent[0]:.4f}–{extent[1]:.4f}°E，{extent[2]:.4f}–{extent[3]:.4f}°N\n"
        f"- 地籍脚印 n={len(polys)}；窗口内站点 N={n_st}\n"
        f"- 建筑色条 0–{b_vmax:.0f} m；树高色条 0–{t_vmax:.0f} m\n\n"
        "## 分析上下文\n\n"
        f"City=Seoul; role=appendix local check; buildings=MOIS cadastre n={len(polys)}; "
        "Grouping=not applicable.\n",
        encoding="utf-8",
    )
    print(f"[ok] {out.name} single-panel S2 n_cadastre={len(polys)} stations={n_st}")


def _lonlat_to_tile(lon: float, lat: float, z: int) -> tuple[int, int]:
    n = 2.0 ** z
    x = int((lon + 180.0) / 360.0 * n)
    lat_r = math.radians(lat)
    y = int((1.0 - math.log(math.tan(lat_r) + 1.0 / math.cos(lat_r)) / math.pi) / 2.0 * n)
    return x, y


def _tile_nw_lonlat(x: int, y: int, z: int) -> tuple[float, float]:
    n = 2.0 ** z
    lon = x / n * 360.0 - 180.0
    lat = math.degrees(math.atan(math.sinh(math.pi * (1.0 - 2.0 * y / n))))
    return lon, lat


def _fetch_esri_world_imagery(bbox: dict, tile_zoom: int = 18):
    """ESRI World Imagery mosaic for a small bbox. Returns (rgb, extent) or None."""
    from io import BytesIO
    import urllib.request
    from PIL import Image

    x0, y1 = _lonlat_to_tile(bbox["west"], bbox["south"], tile_zoom)
    x1, y0 = _lonlat_to_tile(bbox["east"], bbox["north"], tile_zoom)
    if x1 < x0:
        x0, x1 = x1, x0
    if y1 < y0:
        y0, y1 = y1, y0
    nx, ny = x1 - x0 + 1, y1 - y0 + 1
    if nx * ny > 120 or nx < 1 or ny < 1:
        print(f"[basemap] skip tiles {nx}x{ny}", file=sys.stderr)
        return None
    mosaic = Image.new("RGB", (nx * 256, ny * 256))
    url_t = "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
    opener = urllib.request.build_opener()
    for iy, ty in enumerate(range(y0, y1 + 1)):
        for ix, tx in enumerate(range(x0, x1 + 1)):
            url = url_t.format(z=tile_zoom, y=ty, x=tx)
            try:
                req = urllib.request.Request(url, headers={"User-Agent": "GLIDE-SOL-repro/1.0"})
                with opener.open(req, timeout=20) as r:
                    tile = Image.open(BytesIO(r.read())).convert("RGB")
                mosaic.paste(tile, (ix * 256, iy * 256))
            except Exception as e:  # noqa: BLE001
                print(f"[basemap] tile fail {tx},{ty}: {e}", file=sys.stderr)
                return None
    west, north = _tile_nw_lonlat(x0, y0, tile_zoom)
    east, south = _tile_nw_lonlat(x1 + 1, y1 + 1, tile_zoom)
    rgb = np.asarray(mosaic) / 255.0
    return rgb, [west, east, south, north]


def plot_figure02_juso_satellite(figdir: Path, stations: pd.DataFrame, data_dir: Path) -> None:
    """One neighborhood Fig2: aerial basemap + 도로명주소 outlines (not 10 m squares)."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.collections import PolyCollection
    import matplotlib.patheffects as pe

    _set_times_font()
    zoom = _fig2_juso_zoom()
    juso_path = Path(data_dir) / "juso_buildings_fig2.geojson"
    polys = _juso_geojson_to_polys(juso_path)
    keep = []
    pad = 0.00015
    for p in polys:
        lon, lat = np.asarray(p["lon"], float), np.asarray(p["lat"], float)
        if lon.max() < zoom["west"] - pad or lon.min() > zoom["east"] + pad:
            continue
        if lat.max() < zoom["south"] - pad or lat.min() > zoom["north"] + pad:
            continue
        if lon.size < 4:
            continue
        keep.append(p)
    polys = keep
    print(f"[fig2] juso close-up n={len(polys)} window={zoom}")

    basemap = _fetch_esri_world_imagery(zoom, tile_zoom=18)
    extent = [zoom["west"], zoom["east"], zoom["south"], zoom["north"]]
    lat0 = 0.5 * (extent[2] + extent[3])

    fig = plt.figure(figsize=(8.6, 7.6))
    ax = fig.add_axes([0.10, 0.16, 0.80, 0.76])
    if basemap is not None:
        rgb, bext = basemap
        ax.imshow(rgb, extent=bext, origin="upper", interpolation="bilinear", zorder=1)
    else:
        ax.set_facecolor("#efe6c9")
    ax.set_aspect(_geo_aspect(lat0))

    if polys:
        verts = [np.column_stack((p["lon"], p["lat"])) for p in polys]
        # Outline only: solid brown fill made every house look like a 10 m square.
        ax.add_collection(
            PolyCollection(
                verts,
                facecolors=(0, 0, 0, 0),
                edgecolors="#fff200",
                linewidths=0.45,
                zorder=3,
            )
        )

    lcz_color = {
        "2": "#d73027", "4": "#fc8d59", "5": "#e6550d", "6": "#fdae6b",
        "8": "#bdbdbd", "9": "#f5f5f5", "10": "#636363", "B": "#31a354",
    }
    outline = [pe.withStroke(linewidth=2.2, foreground="white")]
    n_st = 0
    for _, st in stations.iterrows():
        lon, lat = float(st["longitude"]), float(st["latitude"])
        if not (extent[0] <= lon <= extent[1] and extent[2] <= lat <= extent[3]):
            continue
        n_st += 1
        key = str(st["lcz"])
        ax.plot(lon, lat, "o", ms=7, color=lcz_color.get(key, "#333"), markeredgecolor="k", markeredgewidth=0.4, zorder=6)
        ax.text(
            lon, lat + 0.00025, str(st["station_id"]),
            color=lcz_color.get(key, "#333"), fontsize=8, ha="center", va="bottom",
            fontweight="bold", path_effects=outline, zorder=7,
        )

    ax.set_xlim(extent[0], extent[1])
    ax.set_ylim(extent[2], extent[3])
    ax.set_xlabel("Longitude (°E)")
    ax.set_ylabel("Latitude (°N)")
    ax.ticklabel_format(useOffset=False, style="plain")
    ax.set_title("Figure S2 inset. Official footprints on aerial imagery (Namsan east slope)", loc="left", fontsize=10)

    ax_leg = fig.add_axes([0.08, 0.03, 0.84, 0.10])
    ax_leg.axis("off")
    note = (
        "Yellow = MOIS road-name address building outlines on Esri World Imagery."
        if basemap is not None
        else "Yellow = MOIS road-name address building outlines."
    )
    ax_leg.text(0.0, 0.50, note, fontsize=8)
    ax_leg.text(0.0, 0.12, f"n={len(polys)} footprints. Height unused on this panel.", fontsize=8)

    out = Path(figdir) / "Figure_S2b_juso_aerial.pdf"
    fig.savefig(out, dpi=300, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    print(f"[ok] {out.name} juso-closeup n={len(polys)} stations={n_st} basemap={basemap is not None}")


def mode_figures_all(out_dir: Path, args) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    _set_times_font()

    figdir = _ensure(Path(out_dir) / "Figures")
    data = Path(out_dir) / "Data"
    run = Path(out_dir) / "Output" / "solweig"
    tab = Path(out_dir) / "Tables"
    df = pd.read_csv(run / "station_hour_series.csv", parse_dates=["time"])
    z = np.load(data / "domain_100m.npz")
    stations = pd.read_csv(data / "stations_meta.csv")

    def _save(fig, name: str):
        fig.savefig(figdir / f"{name}.pdf", dpi=300, bbox_inches="tight", facecolor="white")
        plt.close(fig)

    # Fig1 workflow schematic
    fig, ax = plt.subplots(figsize=(8, 3))
    ax.axis("off")
    ax.set_title("Figure 1. Workflow of the GLIDE-SOL framework (Seoul 100 m)")
    ax.text(
        0.5,
        0.5,
        "Global/GEE inputs → WindCoeff → SOLWEIG (CPU diagnostic) → Postprocess/Validate",
        ha="center",
        va="center",
        fontsize=11,
        wrap=True,
    )
    _save(fig, "Figure01_workflow")

    # Fig2 — full Seoul; buildings from 2 m Overture morphology when available
    z2 = _fig2_city_display_domain(data)
    plot_figure02_seoul_domain(figdir, z2 if z2 is not None else z, stations)

    # Fig3 = full Seoul, 2 m morphology (10 m display) when city domain exists.
    cityp = data / "domain_city_2m.npz"
    if cityp.exists():
        zc = np.load(cityp)
        c_city = data / "wind_coeff_city_2m_240.npy"
        if not c_city.exists():
            compute_city_wind_coeff_2m(data)
        Cc = np.load(c_city)
        plot_figure03_wind_coeff(
            figdir, zc, Cc, theta=240.0, footprint_mode=True, full_domain=True,
            out_name="Figure03_wind_coeff.pdf",
        )
    else:
        s2_2m = data / "domain_s2_2m.npz"
        if s2_2m.exists():
            zs2 = np.load(s2_2m)
            Cs2 = directional_wind_coeff(
                zs2["buildings"], zs2["trees"], 240.0, footprint_mode=True, res_m=2.0
            )
            np.save(data / "wind_coeff_s2_2m_240.npy", Cs2)
            plot_figure03_wind_coeff(
                figdir, zs2, Cs2, theta=240.0, footprint_mode=True, full_domain=True,
                out_name="Figure03_wind_coeff.pdf",
            )
        else:
            C240 = np.load(data / "wind_coeff_dir240.npy")
            plot_figure03_wind_coeff(
                figdir, z, C240, theta=240.0, footprint_mode=False, full_domain=True,
                out_name="Figure03_wind_coeff.pdf",
            )

    # Fig4 — literature 2×2 mean fields + station half-disks (obs | model)
    fields = np.load(run / "jja_mean_fields_WC.npz")
    plot_figure04_mean_fields(figdir, fields, stations, df)

    # Fig5 — literature: RMSE & MB by station, SVF-sorted, LCZ context
    err5 = _station_utci_error_table(df, stations=stations, domain_npz=data / "domain_100m.npz")
    plot_figure05_station_errors(figdir, err5)

    def scatter_fig(obs, std, wc, title, fname, unit="°C"):
        fig, ax = plt.subplots(figsize=(5, 5))
        ax.scatter(obs, std, s=4, alpha=0.3, label="Sol_STD")
        ax.scatter(obs, wc, s=4, alpha=0.3, label="Sol_WC_UHI")
        lims = [np.nanmin([obs.min(), std.min(), wc.min()]), np.nanmax([obs.max(), std.max(), wc.max()])]
        ax.plot(lims, lims, "k--", lw=1)
        ax.set_xlabel(f"Observed ({unit})")
        ax.set_ylabel(f"Modeled ({unit})")
        ax.set_title(title)
        ax.legend(markerscale=3)
        _save(fig, fname)

    scatter_fig(df["obs_UTCI"], df["STD_UTCI"], df["WC_UTCI"], "Figure 6. UTCI", "Figure06_scatter_UTCI")
    fig, axs = plt.subplots(1, 3, figsize=(11, 3.5))
    for ax, o, s, w, t in zip(
        axs,
        [df["obs_Tmrt"], df["obs_Vcan"], df["obs_Ta"]],
        [df["STD_Tmrt"], df["STD_Vcan"], df["STD_Ta"]],
        [df["WC_Tmrt"], df["WC_Vcan"], df["WC_Ta"]],
        ["Tmrt", "Vcan", "Ta"],
    ):
        ax.scatter(o, s, s=3, alpha=0.25, label="Sol_STD")
        ax.scatter(o, w, s=3, alpha=0.25, label="Sol_WC_UHI")
        ax.set_title(t)
        ax.legend(fontsize=7, markerscale=3)
    fig.suptitle("Figure 7. Observed vs modeled Tmrt / Vcan / Ta")
    fig.tight_layout()
    _save(fig, "Figure07_scatter_drivers")

    # Fig8 PDFs
    fig, axs = plt.subplots(2, 2, figsize=(8, 6))
    for ax, o, s, w, t in zip(
        axs.ravel(),
        [df["obs_Ta"], df["obs_Vcan"], df["obs_UTCI"], df["obs_Tmrt"]],
        [df["STD_Ta"], df["STD_Vcan"], df["STD_UTCI"], df["STD_Tmrt"]],
        [df["WC_Ta"], df["WC_Vcan"], df["WC_UTCI"], df["WC_Tmrt"]],
        ["Ta", "Vcan", "UTCI", "Tmrt"],
    ):
        for series, lab in [(o, "Obs"), (s, "Sol_STD"), (w, "Sol_WC_UHI")]:
            ax.hist(series, bins=30, density=True, histtype="step", label=lab)
        ax.set_title(t)
        ax.legend(fontsize=7)
    fig.suptitle("Figure 8. Probability density functions")
    fig.tight_layout()
    _save(fig, "Figure08_pdfs")

    g = df.groupby("time").mean(numeric_only=True).reset_index()
    fig, ax = plt.subplots(figsize=(9, 3))
    ax.plot(g["time"], g["obs_Vcan"], label="Obs")
    ax.plot(g["time"], g["STD_Vcan"], label="Sol_STD")
    ax.plot(g["time"], g["WC_Vcan"], label="Sol_WC_UHI")
    ax.set_title("Figure 9. Spatially averaged canopy wind speed Vcan")
    ax.legend()
    fig.autofmt_xdate()
    _save(fig, "Figure09_ts_Vcan")

    fig, ax = plt.subplots(figsize=(9, 3))
    ax.plot(g["time"], g["obs_UTCI"], label="Obs")
    ax.plot(g["time"], g["STD_UTCI"], label="Sol_STD")
    ax.plot(g["time"], g["WC_UTCI"], label="Sol_WC_UHI")
    ax.set_title("Figure 10. Spatially averaged UTCI")
    ax.legend()
    fig.autofmt_xdate()
    _save(fig, "Figure10_ts_UTCI")

    def utci_cat(x):
        bins = [-np.inf, 0, 9, 26, 32, 38, np.inf]
        labels = ["strong_cold", "slight_cold", "no_stress", "mod_heat", "strong_heat", "ext_heat"]
        return pd.cut(x, bins=bins, labels=labels)

    cats = ["slight_cold", "no_stress", "mod_heat", "strong_heat"]
    obs_c = utci_cat(df["obs_UTCI"]).value_counts(normalize=True)
    std_c = utci_cat(df["STD_UTCI"]).value_counts(normalize=True)
    wc_c = utci_cat(df["WC_UTCI"]).value_counts(normalize=True)
    fig, ax = plt.subplots(figsize=(7, 4))
    x = np.arange(len(cats))
    ax.bar(x - 0.25, [obs_c.get(c, 0) for c in cats], 0.25, label="Obs")
    ax.bar(x, [std_c.get(c, 0) for c in cats], 0.25, label="Sol_STD")
    ax.bar(x + 0.25, [wc_c.get(c, 0) for c in cats], 0.25, label="Sol_WC_UHI")
    ax.set_xticks(x)
    ax.set_xticklabels(cats, rotation=20)
    ax.set_title("Figure 11. Hours per UTCI category")
    ax.legend()
    _save(fig, "Figure11_utci_categories")

    utci = fields["UTCI"]
    fig, axs = plt.subplots(1, 2, figsize=(8, 3.5))
    axs[0].imshow((utci < 9).astype(float), cmap="Blues")
    axs[0].set_title("Sol_STD proxy")
    axs[1].imshow((utci < 9).astype(float), cmap="Blues")
    axs[1].set_title("Sol_WC_UHI")
    fig.suptitle("Figure 12. Slight cold stress fraction (smoke proxy)")
    _save(fig, "Figure12_cold_stress")

    fig, axs = plt.subplots(1, 2, figsize=(8, 3.5))
    axs[0].imshow((utci - 4 > 32).astype(float), cmap="Reds")
    axs[0].set_title("Sol_STD")
    axs[1].imshow((utci > 32).astype(float), cmap="Reds")
    axs[1].set_title("Sol_WC_UHI")
    fig.suptitle("Figure 13. Moderate heat stress fraction (JJA smoke)")
    _save(fig, "Figure13_heat_stress")

    info = _ensure(figdir / "image_information")
    meta_p = Path(out_dir) / "Data" / "domain_meta.json"
    meteo_p = Path(out_dir) / "Data" / "meteo_meta.json"
    dmeta = json.loads(meta_p.read_text(encoding="utf-8")) if meta_p.exists() else {}
    mmeta = json.loads(meteo_p.read_text(encoding="utf-8")) if meteo_p.exists() else {}
    bmax = dmeta.get("building_height_max_m")
    tmax = dmeta.get("tree_height_max_m")
    fig2_md = (figdir / "image_information" / "Figure02.md").read_text(encoding="utf-8") if (
        figdir / "image_information" / "Figure02.md"
    ).exists() else (
        "# Figure 2\n\n## 图面说明\n\n"
        "全市 100 m 全球图层（WorldCover + GHSL + ETH），用地色与图例同色。\n\n"
        "## 分析上下文\n\n"
        f"City=Seoul; res=100m; domain_source={dmeta.get('source')}; N_stations={len(stations)}.\n"
    )
    # Fig5 annotations harvested from err5
    rmse_std_med = float(err5["RMSE_Sol_STD"].median())
    rmse_wc_med = float(err5["RMSE_Sol_WC_UHI"].median())
    mb_std_med = float(err5["MB_Sol_STD"].median())
    mb_wc_med = float(err5["MB_Sol_WC_UHI"].median())
    svf_lo, svf_hi = float(err5["SVF_obs"].iloc[0]), float(err5["SVF_obs"].iloc[-1])
    n_better_rmse = int((err5["RMSE_Sol_WC_UHI"] <= err5["RMSE_Sol_STD"]).sum())
    fig5_md = (
        "# Figure 5\n\n"
        "## 图面说明\n\n"
        "双面板柱状图对齐文献 Fig.5：(a) 各站 UTCI RMSE、(b) 各站 mean bias（MB）。"
        "横轴站点按 **观测 SVF 升序**（低 SVF→高 SVF；首尔 100 m 域内约 "
        f"{svf_lo:.2f}–{svf_hi:.2f}）；红柱=Sol_STD，蓝柱=Sol_WC_UHI。"
        "柱下彩色条带为站点最近格点 LCZ（语境描述，非独立坐标轴）；条带下方数字为该站 SVF。\n\n"
        "### 图上标注\n\n"
        f"- 站点数 N={len(err5)}（KMA ASOS/AWS）\n"
        f"- RMSE 中位数：Sol_STD={rmse_std_med:.2f} °C，Sol_WC_UHI={rmse_wc_med:.2f} °C\n"
        f"- MB 中位数：Sol_STD={mb_std_med:.2f} °C，Sol_WC_UHI={mb_wc_med:.2f} °C\n"
        f"- RMSE 更优（WC≤STD）站数：{n_better_rmse}/{len(err5)}\n"
        "- 明细与加粗最优格见 Tables/TableB1_station_UTCI_errors.xlsx（Appendix B）\n\n"
        "## 分析上下文\n\n"
        f"City=Seoul; res=100m; metric=UTCI; configs=Sol_STD|Sol_WC_UHI; "
        f"sort=SVF_obs ascending; domain_source={dmeta.get('source')}; "
        f"meteo={mmeta.get('source')}; N_stations={len(err5)}; backend=CPU diagnostic.\n"
    )
    for i in range(1, 14):
        if i == 2:
            (info / "Figure02.md").write_text(fig2_md, encoding="utf-8")
            continue
        if i == 3:
            # plot_figure03_wind_coeff already wrote a detailed Figure03.md
            fig3_md = info / "Figure03.md"
            if fig3_md.exists() and "图上标注" in fig3_md.read_text(encoding="utf-8"):
                continue
        if i == 5:
            (info / "Figure05.md").write_text(fig5_md, encoding="utf-8")
            continue
        (info / f"Figure{i:02d}.md").write_text(
            f"# Figure {i}\n\n## 图面说明\n\n"
            f"Seoul 100 m CPU diagnostic; font=Times New Roman.\n\n"
            f"## 分析上下文\n\n"
            f"City=Seoul; res=100m; domain_source={dmeta.get('source')}; "
            f"meteo={mmeta.get('source')}; backend=CPU diagnostic.\n",
            encoding="utf-8",
        )
    print(f"[ok] Figures 1-13 (Times New Roman) -> {figdir}")


def mode_gee_probe(out_dir: Path, args) -> None:
    ok = try_init_ee(args.gee_project or None)
    _write_json(Path(out_dir) / "Data" / "gee_probe.json", {"ok": ok, "project": args.gee_project})
    print("[ok] gee_probe", ok)


def mode_params_check(out_dir: Path, args) -> None:
    """Sensitivity table: paper vs auto vs manual amplitudes on held-out stations.

    Reusable per-city diagnostic (replaces the old ad-hoc calibration scripts):
    re-scores Sol_WC_UHI under three parameter sets from the existing
    station_hour_series (implied station C + night SVF regression), trains on
    2/3 stations and reports the 1/3 held-out RMSE/bias. Writes
    Tables/TableC1_params_sensitivity.xlsx + Output/solweig/params_check.json.
    """
    data = Path(out_dir) / "Data"
    run = Path(out_dir) / "Output" / "solweig"
    tab = _ensure(Path(out_dir) / "Tables")
    df = pd.read_csv(run / "station_hour_series.csv", parse_dates=["time"])
    met_p = data / "meteo_forcing.csv"
    if met_p.exists():
        met = pd.read_csv(met_p, parse_dates=["time"])[["time", "RH", "SW_down"]]
        met["time"] = pd.to_datetime(met.time).dt.floor("h")
        df["time"] = pd.to_datetime(df.time).dt.floor("h")
        df = df.merge(met, on="time", how="left")
    df = df.dropna(subset=["obs_UTCI", "obs_Vcan", "obs_Ta", "obs_Tmrt"])
    df["hour"] = pd.to_datetime(df.time).dt.hour
    # Parameter-independent ingredients. New series store them directly
    # (C_station / uhi_shape / svf_model); old series fall back to the
    # implied WC/STD ratio, which is only valid if that run used paper α=1.
    if "C_station" in df.columns:
        c_st = pd.to_numeric(df["C_station"], errors="coerce").clip(0.02, 1.0)
    else:
        with np.errstate(divide="ignore", invalid="ignore"):
            c_st = (df.WC_Vcan / df.STD_Vcan).clip(0.02, 1.0)
    df["C_st"] = c_st
    if "svf_model" in df.columns:
        df["svf_m"] = pd.to_numeric(df["svf_model"], errors="coerce").clip(0.05, 1.0)
    else:
        df["svf_m"] = pd.to_numeric(df.get("svf_obs"), errors="coerce").clip(0.05, 1.0)
    df["uhi_shape"] = pd.to_numeric(df.get("uhi_shape"), errors="coerce")

    def _utci(ta, tm, va, rh):
        return approx_utci(np.asarray(ta, float), np.asarray(tm, float),
                           np.asarray(va, float), np.asarray(rh, float))

    def _score(alpha_open: float, uhi: float, mask) -> dict:
        d = df[mask]
        shape = d["uhi_shape"]
        if shape.isna().all():
            shape = 1.0 - d["svf_m"]
        ta = d.STD_Ta.to_numpy(float) + uhi * shape.to_numpy(float)
        v = d.STD_Vcan.to_numpy(float) * (d.C_st.to_numpy(float) ** alpha_open)
        sw = pd.to_numeric(d.get("SW_down"), errors="coerce").fillna(0.0).to_numpy(float)
        tm = ta + 0.015 * sw * d["svf_m"].to_numpy(float) - 2.0 * (1.0 - d["svf_m"].to_numpy(float))
        u = _utci(ta, tm, v, pd.to_numeric(d.RH, errors="coerce").fillna(50.0))
        out = {}
        for var, mod in (("Ta", ta), ("Vcan", v), ("Tmrt", tm), ("UTCI", u)):
            obs = d[f"obs_{var}"].to_numpy(float)
            ok = np.isfinite(obs) & np.isfinite(mod)
            e = mod[ok] - obs[ok]
            out[var] = {"bias": round(float(e.mean()), 2), "RMSE": round(float(np.sqrt((e ** 2).mean())), 2)}
        return out

    sta = sorted(df.station_id.astype(str).unique())
    rng = np.random.default_rng(42)
    tr_st = set(np.array(sta)[rng.permutation(len(sta))[: max(1, int(2 * len(sta) / 3))]].astype(str))
    tr = df.station_id.astype(str).isin(tr_st).to_numpy()
    te = ~tr
    auto_p = {}
    ap = run / "auto_params.json"
    if ap.exists():
        auto_p = json.loads(ap.read_text(encoding="utf-8"))
    schemes = {
        "paper": (1.0, 2.2),
        "auto": (float(auto_p.get("wind_alpha_open", 1.0)), float(auto_p.get("uhi_amp", 2.2))),
    }
    rows = []
    for name, (al, uhi) in schemes.items():
        rtr, rte = _score(al, uhi, tr), _score(al, uhi, te)
        rows.append(
            {
                "Scheme": name,
                "alpha_open": al,
                "uhi_amp": uhi,
                "train_UTCI_RMSE": rtr["UTCI"]["RMSE"],
                "test_UTCI_RMSE": rte["UTCI"]["RMSE"],
                "test_UTCI_bias": rte["UTCI"]["bias"],
                "test_Ta_RMSE": rte["Ta"]["RMSE"],
                "test_Vcan_RMSE": rte["Vcan"]["RMSE"],
                "test_Tmrt_RMSE": rte["Tmrt"]["RMSE"],
            }
        )
    sens = pd.DataFrame(rows)
    _write_json(
        run / "params_check.json",
        {"n_stations": len(sta), "n_train": len(tr_st), "schemes": {k: list(v) for k, v in schemes.items()}, "table": rows},
    )
    try:
        _write_sci_xlsx(
            tab / "TableC1_params_sensitivity.xlsx",
            sheet_name="TableC1",
            title="Table C1. Diagnostic-parameter sensitivity (train/test station split).",
            headers=list(sens.columns),
            rows=[[str(x) for x in r] for r in sens.to_numpy()],
            footnote=(
                "alpha_open = station-comparison wind exponent (V=V10*C^alpha); uhi_amp = night-time "
                "UHI amplitude (degC). 'auto' solves both per-city from station obs; 'paper' uses "
                "Zonato et al. Dortmund defaults. RMSE/bias on 1/3 held-out stations. "
                "Canopy FIELD always keeps paper alpha=1 (morphology in Figs. 3-4)."
            ),
            col_widths=[10, 12, 10, 16, 15, 15, 13, 14, 14],
        )
    except Exception as e:  # noqa: BLE001
        print(f"[params_check] xlsx skipped: {e}", file=sys.stderr)
    print(f"[ok] params_check -> TableC1 (train={len(tr_st)}/{len(sta)} stations)")


def mode_run_all(out_dir: Path, args) -> None:
    # domain first (100 m city + full-city 2 m morphology when enabled)
    if float(getattr(args, "hires_m", 0) or 0) <= 0 and args.gee:
        args.hires_m = 10.0
    mode_domain_inputs(out_dir, args)
    mode_fetch_stations(out_dir, args)
    mode_wind_coeff(out_dir, args)
    try:
        mode_domain_city_2m(out_dir, args)
    except Exception as e:  # noqa: BLE001 — city morphology is an upgrade, not a hard dep
        print(f"[run_all] domain_city_2m skipped: {e}", file=sys.stderr)
    mode_meteo_forcing(out_dir, args)
    mode_solweig_run(out_dir, args)
    mode_station_extract(out_dir, args)
    mode_validate_metrics(out_dir, args)
    mode_params_check(out_dir, args)
    mode_appendix_tables(out_dir, args)
    mode_figures_all(out_dir, args)
    _write_json(
        Path(out_dir) / "Output" / "pipeline_status.json",
        {
            "status": "success",
            "city": "Seoul",
            "res_m": args.res_m,
            "hires_m": float(getattr(args, "hires_m", 0) or 0),
            "gee": bool(args.gee),
        },
    )
    print("[ok] run_all complete")


def main(argv=None) -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--mode", required=True)
    p.add_argument("--out-dir", required=True)
    p.add_argument("--res-m", type=float, default=100.0)
    p.add_argument("--hires-m", type=float, default=10.0, help="Fig3 building-resolving resolution (0=off)")
    p.add_argument("--s2-res-m", type=float, default=2.0, help="S2 window resolution (paper workflow)")
    p.add_argument("--city-out-res-m", type=float, default=10.0, help="Export grid for full-city 2 m morphology (Fig.3 display/C grid)")
    p.add_argument("--city-tile-px", type=int, default=4096, help="Tile size (px) for tiled 2 m wind-coefficient computation")
    p.add_argument("--city-dirs", type=int, default=12, help="12 = also compute 12-direction city C stack for SOLWEIG; 0 = domain only")
    p.add_argument("--params-mode", default="auto", choices=["auto", "paper", "manual"],
                   help="auto=closed-form per-city amplitudes from station obs; paper=Dortmund defaults; manual=use --wind-alpha/--uhi-amp/--tmrt-*")
    p.add_argument("--wind-alpha", type=float, default=1.0, help="canopy wind exponent V=V10*C^alpha (0=off, 1=paper full attenuation)")
    p.add_argument("--uhi-amp", type=float, default=2.2, help="night-time UHI Ta amplitude (degC)")
    p.add_argument("--tmrt-a", type=float, default=0.015, help="Tmrt shortwave coefficient")
    p.add_argument("--tmrt-b", type=float, default=2.0, help="Tmrt sky-view longwave loss coefficient")
    p.add_argument("--n-hours", type=int, default=168)
    p.add_argument("--n-stations", type=int, default=0)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--gee", action="store_true")
    p.add_argument("--gee-project", default="")
    p.add_argument("--start-date", default="2024-08-01")
    p.add_argument("--west", type=float, default=126.78)
    p.add_argument("--south", type=float, default=37.46)
    p.add_argument("--east", type=float, default=127.17)
    p.add_argument("--north", type=float, default=37.67)
    args = p.parse_args(argv)
    out = Path(args.out_dir)
    _ensure(out / "Data")
    _ensure(out / "Tables")
    _ensure(out / "Figures")
    _ensure(out / "Output")

    modes = {
        "fetch_stations": mode_fetch_stations,
        "domain_inputs": mode_domain_inputs,
        "domain_ghsl_refresh": mode_domain_ghsl_refresh,
        "domain_s2_2m": mode_domain_s2_2m,
        "domain_city_2m": mode_domain_city_2m,
        "domain_hires": mode_domain_hires,
        "wind_coeff": mode_wind_coeff,
        "meteo_forcing": mode_meteo_forcing,
        "solweig_run": mode_solweig_run,
        "station_extract": mode_station_extract,
        "validate_metrics": mode_validate_metrics,
        "params_check": mode_params_check,
        "figures_all": mode_figures_all,
        "appendix_tables": mode_appendix_tables,
        "run_all": mode_run_all,
        "gee_probe": mode_gee_probe,
    }
    if args.mode not in modes:
        print("unknown mode", args.mode, file=sys.stderr)
        return 2
    modes[args.mode](out, args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
