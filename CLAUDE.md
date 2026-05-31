# modhousekeeper — notes for AI assistants

A norns mod manager (install / update / remove mods) that lives in the norns
SYSTEM > MODS menu. Runs on a monome norns (and shield); **it cannot be tested
in this dev environment** — there is no norns runtime here, so verify Lua with
`luac -p` and reason carefully rather than running it.

## Layout

- `lib/mod.lua` — everything: state, mods-list parsing, install/update/remove,
  the menu UI (`menu_ui` with init/deinit/key/enc/redraw), hooks. ~1380 lines.
- `lib/animation.lua` — the lighthouse intro (60fps tweetcart port).
- `lib/json.lua` — minimal decode-only JSON parser (Phase 2; for community.json).
- `mods.lua` — curated mod list as a Lua return-table (Phase 2; was `mods.list`).
- `mods.local.lua` — optional per-user overrides, gitignored (Phase 2).
- `community.json` — a copy of monome/norns-community's catalog (350 entries; 19
  tagged "mod", but the tag does NOT reliably distinguish mods from scripts).
- `README.md` — user-facing docs.

## Conventions

- **Commit messages: no Claude Code / AI attribution** (per the user's global
  rule). Commit or push only when the user explicitly asks.
- norns APIs in use: `norns.system_cmd` (async shell, callback gets stdout),
  `norns.system_glob`, `_path.code`, `_path.data`, `screen.*` (128×64),
  `clock.run/sleep/cancel`, `util.file_exists/clamp`, `tabutil`. Mods are dirs
  under `_path.code` containing `lib/mod.lua`.
- Screen: title bar y0–10; usable area to y64. Body rows start y19, step 9,
  `max_visible = 5` (keeps descenders off the bottom edge and clear of the
  transient message bar at y53).
- `mod_entry.install_dir` holds the resolved on-disk dir; use `get_mod_dir()`
  rather than `repo_id` for any filesystem path (a mod's dir can differ from the
  URL basename — e.g. `broadcast` vs repo `norns-broadcast`).

## Phase 1 (done 2026-05-31)

- `update_mod` checks git output and reports up-to-date / failure (dirty tree,
  no upstream, detached HEAD, conflict, network) instead of always "updated!".
- Info popups dismiss on any key; the "Checking n/m" update scan is cancellable
  (`modhousekeeper.check_state.cancelled`) so a hung repo can't freeze the popup.
- Row layout retuned so descenders don't clip; intro animation plays once per
  session (no replay when toggling script↔menu with K1).
- Mod rows indented under category headers; E3 collapses/expands a category.
- `mods.list`: fixed the split `cron` line; "Uncategorized / Miscellaneous" →
  "Misc"; `normalize_repo_name()` stopgap matches `norns-`/case-different dirs;
  added verified mods (doubledecker, nb_drumcrow, nb_polyperc, nb_rudiments,
  norns-example-mod). Left out keyano/funkit (no such norns mod) and
  hs010/toga/tending_the_waves/repl-looper (scripts, not mods).

## Phase 2 (done 2026-05-31)

Data layer rewritten and removal made norns-native.

- **`lib/json.lua`** — decode-only JSON parser (no deps; handles objects, arrays,
  strings w/ escapes + `\uXXXX`, numbers, bool, null). `json.decode(str)` and
  `json.decode_file(path)` return `value` or `nil, err`.
- **`lib/catalog.lua`** — loads `community.json` and indexes it by normalized
  repo URL. `catalog.load()` prefers a refreshed copy in `_path.data`
  (`modhousekeeper_community.json`), else the bundled `community.json` in the mod
  dir. `catalog.lookup(url)` → entry. `catalog.refresh(cb)` curls the latest from
  `raw.githubusercontent.com/monome/norns-community/main/community.json` to a
  `.tmp`, validates it parses, then `os.rename`s into place (never clobbers a
  good catalog).
- **`mods.lua`** — curated list as `return { categories = {...}, mods = {...} }`.
  Each mod: `name, url, description, category`, optional `dir` and
  `alts = {{url, description}, ...}`. Replaces the old CSV `mods.list`.
- **`mod.lua` `load_mods()`** — dofiles `mods.lua` (required) then optional
  `mods.local.lua` overlay; a same-`name` entry overrides. `resolve_entry()`
  computes `install_dir` as **explicit `dir` → catalog `project_name` → URL
  basename**, and fills a missing description from the catalog. CSV parser /
  `mods.list` / `mods.list.local` / `use_local_mods_list` / `create_local_mods_list`
  / `get_active_mods_list_path` all removed. `init()` does `catalog.load()` then
  `load_mods()`.
- **Settings** — replaced "Use local mods.list" with a **Refresh mod catalog**
  trigger (`modhousekeeper.refresh_catalog()`), wired in both `enc` and `key`.
- **Removal** — `remove_mod` runs `maiden project remove <dir>` (dir = the name
  under `~/dust/code/`); if the dir still exists afterward it falls back to the
  validated `rm -rf`. (Reinstall still uses `rm -rf` directly before re-cloning.)
- **Item 10** — install ○◉◆ vs norns' enable-dot: addressed with a README note
  only; glyphs unchanged pending a look on the real screen.

Caveat: only ~16/60 curated mods appear in `community.json` (broadcast, receiver
and most sixolet nb voices don't), so the `norns-` dir fix relies on explicit
`dir` fields, not the catalog. The catalog only enriches the entries it has.

Not yet smoke-tested on hardware: menu flow, `refresh_catalog` curl, maiden remove.

## Phase 3 (planned)

On-device testing (2026-05-31): install/remove work for some mods (gridkeys OK),
but **arcify and broadcast fail to install**, and the catalog-refresh popup says
"350 entries" (it's counting all scripts, not mods). Phase 3:

0. **Diagnose & fix install failures** (arcify, broadcast; gridkeys works):
   - `install_mod` declares success only if `<install_dir>/lib/mod.lua` exists
     after `git clone`, and prints the git output to matron on failure — check
     matron for the exact cause first.
   - Leading hypotheses: (a) **arcify is a library, not a mod** — mimetaur/arcify
     ships `arcify.lua` at the root, no `lib/mod.lua`, so it can never satisfy the
     check (data error inherited from the old list → remove it, or stop treating
     non-mods as installable). (b) The two failures (arcify, broadcast) are the
     ones whose `install_dir` ≠ URL basename (arcify via catalog project_name,
     broadcast via explicit `dir`), whereas gridkeys was unmatched → basename;
     verify the clone target dir is correct and not pre-existing (a non-empty
     `broadcast` dir makes `git clone` fail). Confirm schollz/norns-broadcast
     actually has `lib/mod.lua` and on which default branch.
   - Consider: detect "cloned but not a mod" distinctly from "clone failed", and
     clean up a partial/non-mod clone instead of leaving it on disk.
1. **Catalog-refresh messaging / meaning** — the popup shouldn't imply 350 mods.
   community.json is all scripts+mods (~19 tagged "mod"); the catalog is used to
   resolve install dirs + enrich descriptions for *curated* mods, not to count
   mods. Report something honest (e.g. "Catalog updated") and/or the number of
   curated mods matched.
2. **Fix mod-list scrolling** — in `menu_ui.enc` (E2 handler) and `draw_mod_list`
   in `lib/mod.lua`:
   - *Top not reachable:* after scrolling up to the title, the category/Settings
     rows don't scroll back onto the screen. `flat_list[1]` is the Settings entry
     and category headers are list items too — check the `scroll_offset`
     clamping (`selected_index < scroll_offset + 1` branch) so the top of the
     list is always shown when `selected_index` reaches 1.
   - *Bottom occluded:* scrolling to the end hides the last mod behind the bottom
     message bar. Layout today: rows at y = 19, +9 each, `max_visible = 5` (so
     19/28/37/46/55); the message bar is `rect(0, 53, 128, 11)`. The 5th row
     (y55) sits under the bar. Reconcile row count / positions with the bar
     (e.g. reserve its space, drop to 4 visible when a message shows, and/or add
     a scroll-position indicator).
3. **Browse community mods** — a browsable view of `community.json` entries
   tagged `"mod"` that are NOT already in `mods.lua`, installable without
   hand-editing. The catalog is already loaded (`catalog.entries`,
   `catalog.lookup`); needs a new UI mode and a way to mark/skip ones already
   curated. (Caveat: the `"mod"` tag set is small and imperfect — ~19 entries.)
4. **Visual install vs. enable** — item 10 done properly: redesign the ○◉◆
   install indicators so install state can't be mistaken for norns' own
   enable-dot in SYSTEM > MODS.
