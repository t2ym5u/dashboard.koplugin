# Changelog

All notable changes to this project will be documented in this file.

Reconstructed from this repository's git history: each release lists the
feature and fix commits it carried. Version bumps, screenshot additions
and CI syncs are left out.

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
