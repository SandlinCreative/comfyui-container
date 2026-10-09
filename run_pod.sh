podman run --rm --device nvidia.com/gpu=all -p 8188:8188 \
-v Z:/comfyui/custom_nodes:/app/custom_nodes:rw \
-v Z:/comfyui/models:/app/models:rw \
-v Z:/comfyui/output:/app/output:rw \
localhost/comfyui:new3
