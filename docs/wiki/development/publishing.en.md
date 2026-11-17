# Preview and publish the Wiki

The Wiki uses MkDocs, Material and static i18n. Documentation dependencies are separate from Godot runtime requirements.

## Local preview

```sh
python3 tools/wiki/wiki.py setup
python3 tools/wiki/wiki.py serve --open
```

On Windows, `py -3` can replace `python3`. On macOS the repository also provides `打开Wiki.command`. The first run installs pinned packages into ignored `.venv-wiki/`. The default address is `http://127.0.0.1:8765/GodotLevelEditor/`; use the printed address. `--port 8766` chooses another port. Ctrl+C stops the server.

## Build and check

```sh
python3 tools/wiki/wiki.py build
python3 tools/wiki/wiki.py check
```

Build writes `site/`. Check verifies both language versions, links, anchors, images and search. Preview over HTTP; opening HTML files directly is not equivalent. The source/output `.gdignore` markers prevent Godot from importing documentation images.

## Publish

`.github/workflows/wiki.yml` builds and checks relevant pull requests. Relevant pushes to `main` publish the built site through GitHub Pages; manual dispatch is also available. The repository's Pages source must be **GitHub Actions**.

The Chinese root remains `https://lanyi021102.github.io/GodotLevelEditor/`; English is under `/en/`. Local success does not prove online deployment. Check the Actions deployment result before sharing an updated site.

Historical module pages remain readable with an original-record notice and are excluded from current-guide search. Update `site_url`, `repo_url` and source-link bases if hosting changes.
