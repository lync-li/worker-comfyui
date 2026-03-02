# Build argument for base image selection
ARG BASE_IMAGE=pytorch/pytorch:2.10.0-cuda13.0-cudnn9-runtime

# Stage 1: Base image with common dependencies
FROM ${BASE_IMAGE} AS base

# Build arguments for this stage with sensible defaults for standalone builds
ARG COMFYUI_VERSION=0.15.1
ARG COMFYUI_GIT_REF

# Prevents prompts from packages asking for user input during installation
ENV DEBIAN_FRONTEND=noninteractive
# Prefer binary wheels over source distributions for faster pip installations
ENV PIP_PREFER_BINARY=1
# Ensures output from python is printed immediately to the terminal without buffering
ENV PYTHONUNBUFFERED=1
# Speed up some cmake builds
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/* \
    && git clone --depth 1 --branch "${COMFYUI_GIT_REF:-v${COMFYUI_VERSION}}" https://github.com/comfyanonymous/ComfyUI /comfyui \
    && python -m pip install --no-cache-dir --upgrade pip setuptools wheel \
    && python -m pip install --no-cache-dir comfy-cli \
    && grep -vE '^[[:space:]]*(torch|torchvision|torchaudio|xformers|triton|nvidia-)' /comfyui/requirements.txt > /tmp/requirements.no_torch.txt \
    && python -m pip install --no-cache-dir -r /tmp/requirements.no_torch.txt \
    && python -m pip install --no-cache-dir runpod requests websocket-client \
    && apt-get purge -y --auto-remove git \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*


# Change working directory to ComfyUI
WORKDIR /comfyui

# Support for the network volume
ADD src/extra_model_paths.yaml ./

# Go back to the root
WORKDIR /

# Add application code and scripts
ADD src/start.sh src/network_volume.py handler.py test_input.json ./
RUN chmod +x /start.sh

# Add script to install custom nodes
COPY scripts/comfy-node-install.sh /usr/local/bin/comfy-node-install
RUN chmod +x /usr/local/bin/comfy-node-install

# Prevent pip from asking for confirmation during uninstall steps in custom nodes
ENV PIP_NO_INPUT=1

# Copy helper script to switch Manager network mode at container start
COPY scripts/comfy-manager-set-mode.sh /usr/local/bin/comfy-manager-set-mode
RUN chmod +x /usr/local/bin/comfy-manager-set-mode

# Set the default command to run when starting the container
CMD ["/start.sh"]

# Stage 2: Final image
FROM base AS final
