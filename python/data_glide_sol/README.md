# Seoul KMA station catalog

Zonato et al. (2026) GMD validates **Dortmund** (Data2Resilience network).
This Seoul reproduction uses **Korea Meteorological Administration (KMA)** ASOS/AWS stations.

| Field | Meaning |
|-------|---------|
| `kma_id` | Official KMA station number (from AWS minute table) |
| `station_id` | Short label for figures (SEL, GNG, …) |
| `address` | Administrative address shown on weather.go.kr AWS table |
| `coord_source` | `kma_asos_official` / `kma_hq_known` / `nominatim_dong_centroid` |

Coordinates for most AWS sites are **dong centroids** geocoded from the public address
(not surveyed GPS pegs). ASOS Seoul (108) and a few known sites use published ASOS coords.

Clip to `config$glide_sol$bbox` when building `stations_meta.csv`.
