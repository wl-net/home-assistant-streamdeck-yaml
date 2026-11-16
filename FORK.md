# wl-net fork

This is a fork of [basnijholt/home-assistant-streamdeck-yaml](https://github.com/basnijholt/home-assistant-streamdeck-yaml).
The application code is upstream's, unchanged. The fork adds files only: it builds its own
container image from current, hash-pinned dependencies and publishes it to GHCR. Upstream's
README (rewritten by upstream's bot) still describes upstream's Docker Hub image; use the image
below instead.

## Image

`ghcr.io/wl-net/home-assistant-streamdeck-yaml`, for `linux/amd64` and `linux/arm64` (e.g. Raspberry Pi).

| Tag | Meaning |
| --- | --- |
| `2026.5.2.post7` (example) | Upstream release `2026.5.2` plus 7 commits (upstream's unreleased ones and the fork's) |
| `sha-<short>` | The fork commit the image was built from |
| `latest` | Newest build of `main` |

Images are rebuilt weekly from the same commit to pick up Debian package updates, so tags can be
re-pushed. Pin a digest (`@sha256:…`) if you need a byte-identical image. Pushing a tag
`v<version>` (a PEP 440 version, e.g. `v2026.5.2.post7`) publishes that version tag as well.

## Running it

```yaml
services:
  streamdeck:
    image: ghcr.io/wl-net/home-assistant-streamdeck-yaml:latest
    restart: unless-stopped
    network_mode: host
    environment:
      HASS_HOST: homeassistant.local:8123
      HASS_TOKEN: ${HASS_TOKEN} # long-lived access token
      WEBSOCKET_PROTOCOL: wss # or ws
      CONNECTION_RETRY_ATTEMPTS: "-1" # -1 retries forever
      CONNECTION_RETRY_DELAY: "10"
    volumes:
      - ./configuration.yaml:/app/configuration.yaml:ro
      - assets:/app/assets
      - /dev/bus/usb:/dev/bus/usb
    device_cgroup_rules:
      - "c 189:* rmw" # USB devices, including ones plugged in later
    cap_drop: [ALL]
    security_opt: [no-new-privileges:true]
volumes:
  assets:
```

- **Config:** `STREAMDECK_CONFIG=/app/configuration.yaml`, mounted read-only. Files pulled in with
  `!include` are resolved relative to it, so mount them under `/app` too (e.g. `./includes:/app/includes:ro`).
- **Assets:** the app reads fonts and icons from `/app/assets` and caches downloaded MDI/URL icons
  there. On first use Docker seeds the named volume from the image (bundled font and icons); later
  image updates don't change an existing volume. Delete the volume to re-seed it.
- **Other env:** `ALLOW_WEAKER_SSL`, `YAML_ENCODING` (see upstream's README).
- **User:** the container runs as **root (UID 0) with no capabilities**. The deck is opened through
  libusb on `/dev/bus/usb`, and on a stock host those device nodes are `root:root 0664`. So root,
  the owner, can open them with `cap_drop: [ALL]`, and no `--privileged` is needed. To run as
  another user instead, give a group access to the deck on the host (udev rule for vendor `0fd9`,
  e.g. `MODE="0660", GROUP="plugdev"`), then set `user:` and `group_add:` to match, and make the
  assets volume writable for that user.
- The app exits with `No Stream Deck found` when no deck is visible; `restart:` brings it back.

## How it is built

- `Dockerfile` (root): `python:3.14-slim-trixie`, pinned by digest, plus Debian's `libcairo2` and
  `libhidapi-libusb0`. Python packages come from `docker/requirements.txt` and
  `docker/requirements-build.txt` with `pip --require-hashes --only-binary=:all:`. The app is
  installed with `--no-deps --no-build-isolation --editable` under
  `/opt/home-assistant-streamdeck-yaml`. Its version comes from `SETUPTOOLS_SCM_PRETEND_VERSION`,
  since `.git` is not in the build context. Its `assets` directory is a symlink to `/app/assets`.
  Upstream's `Dockerfile.latest`, `Dockerfile.locked` and `conda-lock.yml` are untouched.
- `docker build --target test .` runs upstream's pytest suite inside that exact environment. Two
  reference-image cases are deselected: Pillow 13 changes sub-pixel text anti-aliasing, and
  upstream's own CI fails the same way. Drop the deselects once upstream regenerates the images.
- Locks: `docker/*.in` lists the inputs and `docker/lock.sh` compiles them (`uv pip compile
  --universal --generate-hashes`, for the Python version in the `FROM` line). Use uv if it is
  installed, or else the uv container image. `docker/lock.sh --upgrade` bumps everything.
- Python 3.14 is the newest version that both pydantic 1.10 and every locked package (as wheels)
  support. pydantic 1.10.27 itself works on 3.15, but PyYAML has no 3.15 wheels yet. To move up,
  change the `FROM` line (tag and digest), run `docker/lock.sh`, and build `--target test`.
- `matplotlib` is included because upstream's image ships it for the optional `colormap` setting.

## Automation

- `.github/workflows/image.yml` runs on pushes to `main`, `v*` tags, pull requests, weekly, and by
  hand. It derives the version, runs the test stage plus an entrypoint smoke test natively on
  amd64 and arm64 runners, then builds both platforms with buildx and pushes them to GHCR. Only
  `main` and `v*` tags publish. Pull requests and manual runs on other branches only build, and
  only the build job gets `packages: write`. Actions are pinned by commit SHA.
- `.github/dependabot.yml`: weekly grouped updates for the base image digest and the fork's
  workflow actions. Upstream's files are excluded, and Python minor bumps are left to a person
  (see above).
- `.github/workflows/lock-refresh.yml`: weekly, runs `docker/lock.sh --upgrade` and opens or
  updates a `deps/lock-refresh` pull request. Pull requests opened with `GITHUB_TOKEN` trigger no
  workflows, so it dispatches `image.yml` on that branch to get the checks.

Upstream's `docker-build`, `release`, `automerge`, `update-readme` and `toc` workflows are
disabled in this repository's Actions settings (`gh workflow disable`), not deleted, so syncing
with upstream stays conflict-free. `pytest` stays enabled. Re-enable one with
`gh workflow enable <name>`.

## Syncing with upstream

The fork only adds files (`FORK.md`, `Dockerfile`, `Dockerfile.dockerignore`, `docker/`,
`.github/dependabot.yml`, `.github/workflows/image.yml`, `.github/workflows/lock-refresh.yml`).
Merges therefore don't conflict:

```sh
git remote add upstream https://github.com/basnijholt/home-assistant-streamdeck-yaml.git  # once
git fetch upstream && git merge upstream/main && git push   # or GitHub's "Sync fork" button
```

The push to `main` builds and publishes a new image. After a sync, check whether upstream:

- changed runtime dependencies in `pyproject.toml` (`[tool.unidep]`). If so, mirror the change in
  `docker/requirements.in` and run `docker/lock.sh`.
- added workflows. If so, disable them and add them to `exclude-paths` in `.github/dependabot.yml`.
