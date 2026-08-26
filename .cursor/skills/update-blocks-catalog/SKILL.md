---
name: update-blocks-catalog
description: >-
  Sync docs/Blocks_catalog.md after adding or changing Blocks/*.R register_block
  modules. Use when the user adds a new block, renames register_block, edits
  block file headers, adds a config template, or says 更新 Blocks 目录 / sync
  blocks catalog / 新加 block 写进总结文档.
---

# Update Blocks Catalog

## Goal
Keep `docs/Blocks_catalog.md` (config-writing index) in sync with `Blocks/` and
`configs/templates/`. Do **not** confuse with `docs/block_catalog/` (programmer
`search_blocks` export via `scripts/export_block_catalog.R`).

## When to run (mandatory)
After **any** of these in the same turn / task:
- New `Blocks/**/0*block_*.R` (or any file calling `register_block(...)`)
- Rename / remove `register_block`
- Material change to a block **header comment** (purpose, config keys, prerequisites)
- New or renamed `configs/templates/*.template.R`
- User asks to refresh the Blocks summary / catalog

## Steps
1. **Header quality (new/changed block)**  
   Ensure the `.R` file starts with a comment banner including:
   - one-line purpose (`name — …`)
   - `register_block: "exact_id"` matching `register_block("exact_id", ...)`
   - typical pipeline position
   - `config$<id> = list(...)` example with key comments
   - what it reads/writes on `ctx` (if non-obvious)  
   If missing, add a minimal header **before** regenerating the catalog.

2. **Regenerate AUTO sections** (repo root):
   ```bash
   python3 scripts/update_blocks_catalog.py
   ```
   Optional:
   ```bash
   python3 scripts/update_blocks_catalog.py --only-new   # missing card ids
   python3 scripts/update_blocks_catalog.py --check      # CI-style stale check
   ```

3. **MANUAL sections (only if needed)**  
   Preserved markers in `docs/Blocks_catalog.md`:
   - `HOW_TO_USE`, `ROUTINES`, `GLOBAL_KEYS`, `PITFALLS`  
   Update them when:
   - new **study routine** / template should appear in §1
   - new **cross-cutting** `config$*` keys belong in §2
   - a new **pitfall** is discovered  
   Do **not** hand-edit `<!-- BEGIN AUTO:... -->` regions.

4. **Optional sidecar**  
   Full manual overrides: `docs/Blocks_catalog.manual.md` (same `<!-- MANUAL:NAME -->` markers). Script merges sidecar over file manuals.

5. **Report**  
   Tell the user: script exit OK, new `register_block` id(s), whether MANUAL §1/§2/§3 were touched.

## Do not
- Paste full `.R` bodies into the markdown.
- Regenerate via inventing cards by hand when the script exists.
- Overwrite MANUAL markers when only AUTO needs refresh (script already preserves them).
- Treat `docs/block_catalog/catalog.md` as a substitute for `docs/Blocks_catalog.md`.

## Quick reference
| Artifact | Role |
|---|---|
| `docs/Blocks_catalog.md` | Human/AI config选型字典 |
| `scripts/update_blocks_catalog.py` | Sync tool |
| `docs/Blocks_catalog.manual.md` | Optional MANUAL overrides |
| `scripts/export_block_catalog.R` | Different export for study CLI |
