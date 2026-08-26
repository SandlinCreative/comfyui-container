podman run --rm --device nvidia.com/gpu=all -p 8188:8188 \
-v /run/media/jeremy/55D/comfyui/custom_nodes:/app/custom_nodes:rw \
-v /run/media/jeremy/55D/comfyui/models:/app/models:rw \
-v /run/media/jeremy/55D/comfyui/output:/app/output:rw \
localhost/comfyui:new