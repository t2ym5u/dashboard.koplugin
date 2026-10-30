# Changelog

All notable changes to this project will be documented in this file.

Reconstructed from this repository's git history: each release lists the
feature and fix commits it carried. Version bumps, screenshot additions
and CI syncs are left out.

## [1.3.0] - 2026-10-30

### Added
- The dashboard is now a full-screen home screen built for e-ink: **Continue
  reading** (last book, with progress), **Resume** (last game played),
  **Daily Challenge** (today's puzzle in one of your puzzle games, with a ✓
  once started today), and a paged grid of large game tiles grouped by
  category. Landscape puts the cards in a side column.
- Everything Startup Menu did: open automatically **at KOReader launch only**
  (new default), **every time the file browser opens**, or **never**; choose
  which games show. The game list is a full-screen, category-grouped
  **Choose games** screen with show/hide and ▲ ▼ ordering, plus a **Last
  played first** order and a **Group by category** switch.
- **Daily Challenge game** setting: automatic (a different game every day) or
  a fixed game.
- One-time migration of `settings/startmenu.lua` (its game list and its
  on/off switch) and of the former "Show at startup" checkbox.
- Specs for the game model (ported from Startup Menu), startup trigger,
  migration, daily pick, category grouping and paging.

### Changed
- The former dashboard list is now the **Statistics** page, reached from the
  home screen's footer.
- Game names are shown translated, and the statistics list shows game names
  rather than plugin ids.

### Fixed
- Games whose `_meta.lua` writes its name as `_([[Sudoku]])` were labelled
  with the next quoted string in the file -- their version number ("2.5.0").
  The same bug is in Startup Menu.

## [1.2.18] - 2026-10-01

### Fixed
- KOReader offered no way to delete this plugin's settings. The settings path
  was computed inline rather than stored on the instance, and `PluginLoader`
  reads `instance.settings_file` to decide whether to show "Delete plugin
  settings" at all (2026.07, PR #15240). The option simply never appeared, and
  deleting the plugin left ``dashboard.lua`` behind.

## [1.2.17] - 2026-09-30

### Fixed
- The games section was empty. Installed plugins were identified by a `name`
  field read out of their `_meta.lua` -- a field none of these plugins
  declares, and which KOReader 2026.03 (PR #15096) deprecated in favour of the
  directory name. Games are now found by directory name, and told apart from
  KOReader's own plugins by the shared library they ship. 69 games are
  discovered where 1 was before.

## [1.2.16] - 2026-09-30

### Changed
- `reltime` and `fmt_seconds` move to `format.lua`, unchanged except that
  `reltime` now takes the current time as an argument so it can be asked about
  a fixed instant.

### Added
- A spec pinning the four relative-time boundaries -- two minutes, one hour,
  one day, one week -- the rounding direction, so a row never claims more time
  has passed than actually has, and a timestamp from the future, which a device
  with a jumped clock produces.

## [1.2.15] - 2026-08-05

### Added
- Add ES and DE translations

## [1.2.14] - 2026-08-05

### Changed
- Add issue/PR templates and CONTRIBUTING.md

### Fixed
- Use English source string for _meta.lua description

## [1.2.12] - 2026-08-04

### Added
- Surface a Games row on simpleui's homescreen

## [1.2.11] - 2026-08-04

### Changed
- Symlink common/ to shared game-common

### Fixed
- Define missing local lrequire, fixes plugin load crash
- Drop deprecated name field from _meta.lua

## [1.2.6] - 2026-07-28

### Changed
- Add GPL-3.0 LICENSE
- Add README

## [1.2.3] - 2026-07-21

### Added
- Own translations locally instead of via game-common

## [1.2.1] - 2026-07-15

### Added
- Fix Device/Screen require pattern + bump to v1.2.0

### Changed
- Remove ../game-common/ fallback from package.path

### Fixed
- Vendor common/i18n.lua (missing dependency)

## [1.2.0] - 2026-07-10

### Added
- I18n + play-stats section + reltime in English — v1.2.0

## [1.1.0] - 2026-07-08

### Added
- I18n FR/EN translation + bump to 1.1.0

## [1.0.0] - 2026-07-07

### Added
- Initial Dashboard plugin v1.0.0
