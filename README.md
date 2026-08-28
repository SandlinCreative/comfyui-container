# Containerized ComfyUI

This project builds and runs [ComfyUI](https://github.com/Comfy-Org/ComfyUI) in a
Podman container with NVIDIA GPU access. The image includes ComfyUI's Python
dependencies, a consolidated set of custom-node dependencies, `ffmpeg`, and
ComfyUI Manager support.

## Repository layout

- `ComfyUI/` — ComfyUI application source copied into the image.
- `Containerfile` — multi-stage Python 3.11 container build.
- `requirements-app.txt` — core ComfyUI Python dependencies.
- `custom-node-reqs.txt` — dependencies required by the installed custom nodes.
- `combine_requirements.py` — utility for combining requirements from multiple
  custom nodes.
- `build_pod.sh` — builds the image as `comfyui:new2`.
- `run_pod.sh` — starts the container with GPU access and persistent mounts.

## Prerequisites

- Podman with support for Containerfiles and BuildKit-style cache mounts.
- An NVIDIA GPU with a working driver.
- NVIDIA Container Toolkit configured so Podman recognizes
  `nvidia.com/gpu=all`.
- A populated `ComfyUI/` source directory.

The default PyTorch package index targets CUDA 13.0. If your driver or GPU setup
requires a different build, override `TORCH_INDEX_URL` as described below.

## Build

From the repository root, run:

```bash
./build_pod.sh
```

This builds the image with the tag `comfyui:new2`. The script uses
`$HOME/.cache/podman-tmp` as Podman's temporary directory; create that directory
first if it does not exist:

```bash
mkdir -p "$HOME/.cache/podman-tmp"
```

To select another PyTorch wheel index or image tag, invoke Podman directly:

```bash
podman build \
  --build-arg TORCH_INDEX_URL=https://download.pytorch.org/whl/cu130 \
  -t comfyui:local \
  .
```

## Run

`run_pod.sh` publishes ComfyUI on port 8188 and mounts persistent custom-node,
model, and output directories into the container:

```bash
./run_pod.sh
```

Then open <http://localhost:8188>.

The host paths in `run_pod.sh` are specific to the original machine:

```text
/run/media/jeremy/55D/comfyui/custom_nodes
/run/media/jeremy/55D/comfyui/models
/run/media/jeremy/55D/comfyui/output
```

Edit those paths before running the script on another system. An equivalent
manual command is:

```bash
podman run --rm \
  --device nvidia.com/gpu=all \
  -p 8188:8188 \
  -v /path/to/custom_nodes:/app/custom_nodes:rw \
  -v /path/to/models:/app/models:rw \
  -v /path/to/output:/app/output:rw \
  localhost/comfyui:new2
```

The container starts ComfyUI with `--listen 0.0.0.0`, port `8188`, and
`--enable-manager`.

## Updating custom-node requirements

`combine_requirements.py` recursively finds files named `requirements.txt` and
combines them into one output file. For duplicate packages, it retains the entry
with the highest detected exact or minimum version. Pip options, VCS URLs, and
other non-PEP 508 lines are preserved once.

The utility requires the `packaging` Python module:

```bash
python -m pip install packaging
```

To regenerate the file used by the container build from a custom-node tree:

```bash
./combine_requirements.py /path/to/custom_nodes -o custom-node-reqs.txt
```

Review the generated file before rebuilding. Combining independent custom-node
requirements can expose incompatible upper bounds or packages that cannot be
installed together on the selected Python, CUDA, or operating-system version.

## Persistent data

The container itself is removed when it exits because the run command uses
`--rm`. Workflows and other data that must survive should be saved in a mounted
host directory. The supplied script persists custom nodes, models, and generated
output; add another volume mount if you also want to persist ComfyUI's `user/`
directory.
