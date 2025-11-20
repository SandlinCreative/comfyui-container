podman run --rm --device nvidia.com/gpu=all -p 8188:8188 \
-v /run/media/jeremy/Data/Stable-Diffusion/custom_nodes:/app/custom_nodes:rw \
-v /run/media/jeremy/Data/Stable-Diffusion/models:/app/models:rw \
-v /run/media/jeremy/Data/Stable-Diffusion/output:/app/output:rw \
localhost/comfyui:latest