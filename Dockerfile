# Use multi-stage build with caching optimizations
FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04 AS base

# Consolidated environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PIP_PREFER_BINARY=1 \
    PYTHONUNBUFFERED=1 \
    CMAKE_BUILD_PARALLEL_LEVEL=8

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

# Add conda to PATH
ENV PATH="/opt/conda/bin:$PATH"

# Initialize conda
RUN conda init bash

# Clone the repository
RUN git clone https://github.com/deepbeepmeep/Wan2GP.git /workspace/Wan2GP

WORKDIR /workspace/Wan2GP

# Create conda environment with Python 3.10.9
RUN conda create -n wan2gp python=3.10.9 -y

# Install PyTorch 2.7.0 with CUDA 12.8
RUN conda run -n wan2gp pip install torch==2.7.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/test/cu128

# Install requirements
RUN conda run -n wan2gp pip install -r requirements.txt

# Set conda environment to be activated by default
ENV CONDA_DEFAULT_ENV=wan2gp
ENV PATH="/opt/conda/envs/wan2gp/bin:$PATH"

FROM base AS final
# Ensure conda environment is available
ENV PATH="/opt/conda/envs/wan2gp/bin:/opt/conda/bin:$PATH"
ENV CONDA_DEFAULT_ENV=wan2gp

WORKDIR /workspace/Wan2GP

COPY src/start_script.sh /start_script.sh
RUN chmod +x /start_script.sh

CMD ["/start_script.sh"]