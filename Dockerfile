FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04

# Environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PIP_PREFER_BINARY=1 \
    PYTHONUNBUFFERED=1 \
    CMAKE_BUILD_PARALLEL_LEVEL=8

# Install system dependencies
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        curl ffmpeg ninja-build git aria2 git-lfs wget vim \
        libgl1 libglib2.0-0 build-essential gcc && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Miniconda
RUN wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh && \
    bash /tmp/miniconda.sh -b -p /opt/conda && \
    rm /tmp/miniconda.sh

# Add conda to PATH and initialize
ENV PATH="/opt/conda/bin:$PATH"
RUN conda init bash

# Clone repository
RUN git clone https://github.com/deepbeepmeep/Wan2GP.git /workspace/Wan2GP

WORKDIR /workspace/Wan2GP

# Create and setup conda environment
RUN conda create -n wan2gp python=3.10.9 -y && \
    conda run -n wan2gp pip install torch==2.7.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/test/cu128 && \
    conda run -n wan2gp pip install -r requirements.txt && \
    conda run -n wan2gp pip install pyyaml triton jupyterlab jupyterlab-lsp jupyter-server jupyter-server-terminals ipykernel jupyterlab_code_formatter

# Set default environment
ENV PATH="/opt/conda/envs/wan2gp/bin:/opt/conda/bin:$PATH"
ENV CONDA_DEFAULT_ENV=wan2gp

# Setup start script
COPY src/start_script.sh /start_script.sh
RUN chmod +x /start_script.sh

CMD ["/start_script.sh"]