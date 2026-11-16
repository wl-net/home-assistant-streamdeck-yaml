# Container image for the wl-net fork (see FORK.md). Upstream's Dockerfile.latest and
# Dockerfile.locked are kept as-is; this one installs hash-pinned wheels from docker/*.txt.
#
#   docker build -t home-assistant-streamdeck-yaml .              # runtime image
#   docker build --target test .                                  # runs pytest in the image
FROM python:3.14-slim-trixie@sha256:9aaa474097d094040649f2162a627c0049b408f52138d980916788d80f04802f AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_ROOT_USER_ACTION=ignore

# Native libraries: cairo (cairosvg) and hidapi's libusb backend (streamdeck).
RUN apt-get update \
    && apt-get install -y --no-install-recommends libcairo2 libhidapi-libusb0 \
    && rm -rf /var/lib/apt/lists/*

# Locked Python dependencies: wheels only, every file verified against its hash.
COPY docker/requirements.txt docker/requirements-build.txt /tmp/requirements/
RUN pip install --no-deps --require-hashes --only-binary=:all: \
        -r /tmp/requirements/requirements.txt \
        -r /tmp/requirements/requirements-build.txt \
    && rm -rf /tmp/requirements

# The app reads and caches icons/fonts in "assets" next to its module. As in upstream's
# image, the module lives outside /app so bind mounts there cannot hide it; its assets
# directory is a symlink to /app/assets, which a named volume can take over.
COPY assets /app/assets
WORKDIR /opt/home-assistant-streamdeck-yaml
COPY pyproject.toml README.md LICENSE home_assistant_streamdeck_yaml.py ./
ARG VERSION=0.0.0
RUN ln -s /app/assets assets \
    && SETUPTOOLS_SCM_PRETEND_VERSION="${VERSION}" \
        pip install --no-deps --no-build-isolation --editable . \
    && rm -rf build *.egg-info

LABEL org.opencontainers.image.title="home-assistant-streamdeck-yaml" \
      org.opencontainers.image.description="Home Assistant on Stream Deck, configured via YAML (wl-net fork build)" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="${VERSION}"

# Runs as root (UID 0) on purpose: the deck is opened through /dev/bus/usb, whose device
# nodes are root-owned on a stock host. No extra capabilities are needed (see FORK.md).
WORKDIR /app
ENV STREAMDECK_CONFIG=/app/configuration.yaml
CMD ["home-assistant-streamdeck-yaml"]


# Test stage: upstream's test suite against the exact runtime environment above.
FROM runtime AS test
COPY docker/requirements-test.txt /tmp/requirements-test.txt
RUN pip install --no-deps --require-hashes --only-binary=:all: -r /tmp/requirements-test.txt
WORKDIR /opt/home-assistant-streamdeck-yaml
COPY --exclude=assets . ./
# Two reference images differ by sub-pixel text anti-aliasing under Pillow 13 (upstream's own
# CI fails the same way); drop these deselects once upstream regenerates the references.
RUN python -m pytest -p no:cacheprovider -q \
        --deselect "tests/test_image.py::test_image_generation[text_params2-None]" \
        --deselect "tests/test_image.py::test_image_generation[text_params4-icon_params4]"
