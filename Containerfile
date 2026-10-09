# syntax=docker/dockerfile:1.5

# ---------- Runtime base image ----------

# Keep the Debian release aligned with NVIDIA's debian12 CUDA repository.
# The floating python:3.11-slim tag currently resolves to Debian 13 (trixie),
# whose stricter signature policy rejects NVIDIA's Debian 12 repository key.
FROM python:3.11-slim-bookworm AS runtime-base
ENV PYTHONUNBUFFERED=1 PIP_DISABLE_PIP_VERSION_CHECK=1 CC=gcc
WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libgl1 \
        libglib2.0-0 \
        git \
        ffmpeg \
        gcc \
        libc6-dev \
    && rm -rf /var/lib/apt/lists/*


# ---------- Stage 1: Build app deps into a venv ----------
FROM runtime-base AS builder

# Compilers and headers are needed only while building Python dependencies.
# SageAttention 2.x ships CUDA extensions, so install the matching CUDA compiler
# in this stage without carrying the toolkit into the runtime image.
ARG CUDA_REPO_DISTRO=debian12
ARG CUDA_TOOLKIT_VERSION=13-0
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        ninja-build \
    && curl -fsSLo /tmp/cuda-keyring.deb \
        "https://developer.download.nvidia.com/compute/cuda/repos/${CUDA_REPO_DISTRO}/x86_64/cuda-keyring_1.1-1_all.deb" \
    && dpkg -i /tmp/cuda-keyring.deb \
    && rm /tmp/cuda-keyring.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        "cuda-cudart-dev-${CUDA_TOOLKIT_VERSION}" \
        "cuda-nvcc-${CUDA_TOOLKIT_VERSION}" \
        "libcublas-dev-${CUDA_TOOLKIT_VERSION}" \
        "libcusolver-dev-${CUDA_TOOLKIT_VERSION}" \
        "libcusparse-dev-${CUDA_TOOLKIT_VERSION}" \
    && rm -rf /var/lib/apt/lists/*

# Create a dedicated virtualenv
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

ARG TORCH_INDEX_URL=https://download.pytorch.org/whl/cu130
ARG EXTRA_INDEX_URL=https://pypi.org/simple
ARG SAGEATTENTION_COMMIT=d1a57a546c3d395b1ffcbeecc66d81db76f3b4b5
ARG SAGEATTENTION_CUDA_ARCH=8.6
ARG CUDA_HOME_PATH=/usr/local/cuda-13.0

ENV CUDA_HOME="${CUDA_HOME_PATH}" \
    PATH="${CUDA_HOME_PATH}/bin:${PATH}" \
    TORCH_CUDA_ARCH_LIST="${SAGEATTENTION_CUDA_ARCH}"

# Install consolidated application and node requirements
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir \
      --index-url "${TORCH_INDEX_URL}" \
      --extra-index-url "${EXTRA_INDEX_URL}" \
      -r requirements.txt

# PyPI only provides the legacy SageAttention 1.x package. KJNodes' LTX2
# memory-efficient patch needs the CUDA-backed 2.2.0 API from upstream.
# A single build worker keeps nvcc within Podman machine's modest RAM limit.
RUN --mount=type=cache,target=/root/.cache/pip \
    EXT_PARALLEL=1 MAX_JOBS=1 NVCC_APPEND_FLAGS="--threads 1" \
    pip install --no-cache-dir --no-build-isolation \
      "sageattention @ git+https://github.com/thu-ml/SageAttention.git@${SAGEATTENTION_COMMIT}" \
    && python -c "from sageattention.core import get_cuda_arch_versions, per_thread_int8_triton, per_warp_int8_cuda, per_block_int8_triton, per_channel_fp8"


# ---------- Stage 2: App image ----------
FROM runtime-base AS app

# Use the venv from the builder stage
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

# Copy only the ready-to-run environment and your app code
COPY ComfyUI/ ./

EXPOSE 8188

CMD ["python", "main.py", "--listen", "0.0.0.0", "--port", "8188", "--enable-manager", "--use-sage-attention"]
