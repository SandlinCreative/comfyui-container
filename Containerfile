# syntax=docker/dockerfile:1.5

# ---------- Runtime base image ----------

FROM python:3.11-slim AS runtime-base
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
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
    && rm -rf /var/lib/apt/lists/*

# Create a dedicated virtualenv
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

ARG TORCH_INDEX_URL=https://download.pytorch.org/whl/cu130
ARG EXTRA_INDEX_URL=https://pypi.org/simple

# Install consolidated application and node requirements
COPY custom-node-reqs.txt .
COPY ComfyUI/requirements.txt .
COPY ComfyUI/manager_requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir \
      --index-url "${TORCH_INDEX_URL}" \
      --extra-index-url "${EXTRA_INDEX_URL}" \
      -r custom-node-reqs.txt -r requirements.txt -r manager_requirements.txt


# ---------- Stage 2: App image ----------
FROM runtime-base AS app

# Triton JIT-compiles its CUDA driver helper during inference, so the runtime
# image needs a C compiler and the system C headers as well as the built venv.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        gcc \
        libc6-dev \
    && rm -rf /var/lib/apt/lists/*

ENV CC=/usr/bin/gcc

# Use the venv from the builder stage
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

# Copy only the ready-to-run environment and your app code
COPY ComfyUI/ ./

EXPOSE 8188

CMD ["python", "main.py", "--listen", "0.0.0.0", "--port", "8188", "--enable-manager"]
