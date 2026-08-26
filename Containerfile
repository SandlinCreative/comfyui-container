# syntax=docker/dockerfile:1.5

# ---------- Base image ----------

FROM python:3.11-slim as base
ENV PYTHONUNBUFFERED=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libgl1 \
        libglib2.0-0 \
        git \
        g++ \
        build-essential \
    && rm -rf /var/lib/apt/lists/*


# ---------- Stage 1: Build app deps into a venv ----------
FROM base AS builder

# Create a dedicated virtualenv
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

ARG TORCH_INDEX_URL=https://download.pytorch.org/whl/cu130
ARG EXTRA_INDEX_URL=https://pypi.org/simple

# Install app requirements
COPY requirements-app.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir \
      --index-url "${TORCH_INDEX_URL}" \
      --extra-index-url "${EXTRA_INDEX_URL}" \
      -r requirements-app.txt


# ---------- Stage 2: Build custom node requirements into venv----------

FROM builder AS node-reqs

# Install custom node requirements
COPY requirements-nodes.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir \
      -r requirements-nodes.txt


# ---------- Stage 3: App image ----------
FROM base AS app

# Use the venv from the builder stage
COPY --from=node-reqs /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

# Copy only the ready-to-run environment and your app code
COPY ComfyUI/ ./

EXPOSE 8188

CMD ["python", "main.py", "--listen", "0.0.0.0", "--port", "8188", "--enable-manager"]
