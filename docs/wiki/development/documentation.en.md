# Maintain the Wiki

Current guides are in `docs/wiki/`; the home page is `docs/index.md`. Chinese is the default. English counterparts use `.en.md`, such as `getting-started.en.md`, with the same relative links as the default source. The language selector preserves the current page when a counterpart exists.

## Update with the feature

1. Read the relevant README and INTERFACES, and verify the actual code/UI.
2. Update the relevant current Chinese guide and its English counterpart.
3. Keep stable IDs, file paths, parameter names and ports unchanged by translation.
4. Add real screenshots for changed visual behavior, preserving dated evidence boundaries.
5. Update the changelog, module interface and actual validation record.
6. Run `python3 tools/wiki/wiki.py check`; inspect changed pages and the language switcher in a browser.

Use English folder names. Interface labels, Excel worksheet names and user-authored filenames may remain Chinese. The plugin UI's Chinese labels should be shown alongside English descriptions when needed to locate an action.

## Sources and history

Dated module/verification records remain original sources. Current guides and their English translations are searchable; old records are excluded from main search and carry a historical-record notice. Do not promote a deleted feature by copying an old workflow into a new guide.

Add navigation in `mkdocs.yml` and its English `nav_translations`. Images live under `docs/wiki/assets/`; share one real screenshot between languages when the UI is the same. `site/` is generated and ignored.

The README has language links to `README.md` and `README.en.md`. Its feature pictures must show actual editor/runtime output, rather than a mock UI presented as evidence.

## Language pairs and screenshots

Maintain every current Chinese `.md` page with its matching `.en.md` source. The site uses suffix-based mkdocs-static-i18n routing; Chinese URLs remain stable and English lives under `/en/`. Update `README.md` and `README.en.md` together. Keep technical IDs, paths, sheet names and essential Chinese UI labels unchanged.

`tools/readme_media/capture.py` captures the released addon in an isolated temporary project. Shared source PNGs are in `docs/wiki/assets/readme/`; local promotional output is in `exports/`. Use actual UI and rendered frames. The current promotional pack has no added captions or advertising text.
