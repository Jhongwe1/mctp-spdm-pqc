# The hermetic lane.
#
# WSL2 is where this project is developed; this image is how anyone else
# reproduces it, and how the ninety-minute rule in RUNBOOK.md is honoured — if
# a local build cannot be made to work in an evening, come here instead of
# spending a second one.
#
#     docker build -t spdm-lab docker/
#     docker run -it --rm -v "$PWD:/repo" -w /repo spdm-lab bash
#
# Then follow RUNBOOK.md from section 3. The scripts do not know or care which
# environment they are in.
#
# ── on pinning ──────────────────────────────────────────────────────────────
# The tag below is deliberately a digest, not `ubuntu:24.04`. A tag is a moving
# pointer: `ubuntu:24.04` today and `ubuntu:24.04` in three months are different
# images, with different compilers, and this whole file exists to make the
# environment a constant. When this needs updating, change it on purpose and
# record why in LOG.md.
#
# Resolved from the registry on 2026-08-11, without needing a running daemon:
#
#   TOKEN=$(curl -fsSL "https://auth.docker.io/token?service=registry.docker.io\
#   &scope=repository:library/ubuntu:pull" | jq -r .token)
#   curl -fsSI -H "Authorization: Bearer $TOKEN" \
#        -H "Accept: application/vnd.oci.image.index.v1+json" \
#        https://registry-1.docker.io/v2/library/ubuntu/manifests/24.04 \
#     | grep -i docker-content-digest
#
# Refresh it deliberately and say why in LOG.md. Do not transcribe a digest
# from anywhere but the registry: a plausible-looking wrong one fails at
# `docker build` with a message that points nowhere near the cause.
FROM ubuntu@sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

# Exactly what harness/doctor.sh asks for, and nothing else. Every extra
# package is a way for this image to stop resembling a clean machine.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        git \
        iproute2 \
        perl \
        python3 \
        shellcheck \
    && rm -rf /var/lib/apt/lists/*

# Build trees go on the container filesystem, never on a bind mount. The same
# reasoning as on WSL: compiling OpenSSL is tens of thousands of small file
# operations, and a bind mount to a host filesystem is where that gets slow.
# Mount the repository at /repo; let LAB_DIR stay inside the container.
ENV LAB_DIR=/opt/spdm-lab
RUN mkdir -p /opt/spdm-lab

WORKDIR /repo

# A container that exits immediately is hard to use interactively; a container
# that runs the build without being asked is worse. Land in a shell.
CMD ["bash"]
