#!/usr/bin/env bash

# Activate conda environment first
source /opt/conda/etc/profile.d/conda.sh
conda activate wan2gp

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

URL="127.0.0.1:7860"

if ! which aria2 > /dev/null 2>&1; then
    echo "Installing aria2..."
    apt-get update && apt-get install -y aria2
else
    echo "aria2 is already installed"
fi

if ! which curl > /dev/null 2>&1; then
    echo "Installing curl..."
    apt-get update && apt-get install -y curl
else
    echo "curl is already installed"
fi

if [ "${BUILD_SAGE_ATTENTION:-true}" = "true" ]; then
    echo "Installing SageAttention..."
    cd /tmp
    git clone https://github.com/thu-ml/SageAttention.git
    cd SageAttention
    pip install -e .
    pip install --no-cache-dir triton

    if python -c "import sageattention" 2>/dev/null; then
        echo "✅ SageAttention installed successfully"
        ATTENTION_MODE="--attention=sage2"
    else
        echo "❌ SageAttention installation failed"
        ATTENTION_MODE=""
    fi

    cd "$NETWORK_VOLUME/Wan2GP" || cd "/workspace/Wan2GP"
else
    echo "Skipping SageAttention build"
    ATTENTION_MODE=""
fi

# Set the network volume path
NETWORK_VOLUME="/workspace"

# Check if NETWORK_VOLUME exists; if not, use root directory instead
if [ ! -d "$NETWORK_VOLUME" ]; then
    echo "NETWORK_VOLUME directory '$NETWORK_VOLUME' does not exist. You are NOT using a network volume. Setting NETWORK_VOLUME to '/' (root directory)."
    NETWORK_VOLUME="/"
    echo "NETWORK_VOLUME directory doesn't exist. Starting JupyterLab on root directory..."
    jupyter-lab --ip=0.0.0.0 --allow-root --no-browser --NotebookApp.token='' --NotebookApp.password='' --ServerApp.allow_origin='*' --ServerApp.allow_credentials=True --notebook-dir=/ &
else
    echo "NETWORK_VOLUME directory exists. Starting JupyterLab..."
    jupyter-lab --ip=0.0.0.0 --allow-root --no-browser --NotebookApp.token='' --NotebookApp.password='' --ServerApp.allow_origin='*' --ServerApp.allow_credentials=True --notebook-dir=/workspace &
fi

# Download CivitAI script only if not already present
if [ ! -f "/usr/local/bin/download_with_aria.py" ]; then
    echo "Downloading CivitAI download script to /usr/local/bin"
    git clone "https://github.com/Hearmeman24/CivitAI_Downloader.git" || { echo "Git clone failed"; exit 1; }
    mv CivitAI_Downloader/download_with_aria.py "/usr/local/bin/" || { echo "Move failed"; exit 1; }
    chmod +x "/usr/local/bin/download_with_aria.py" || { echo "Chmod failed"; exit 1; }
    rm -rf CivitAI_Downloader  # Clean up the cloned repo
else
    echo "CivitAI download script already exists"
fi

# Navigate to Wan2GP directory
cd "$NETWORK_VOLUME/Wan2GP" || cd "/workspace/Wan2GP" || {
    echo "Error: Could not find Wan2GP directory"
    exit 1
}

# Patch Gradio for RunPod compatibility
echo "Patching Gradio for RunPod proxy compatibility..."
GRADIO_ROUTE_UTILS="/opt/conda/envs/wan2gp/lib/python3.10/site-packages/gradio/route_utils.py"

if [ -f "$GRADIO_ROUTE_UTILS" ] && ! grep -q "runpod.net" "$GRADIO_ROUTE_UTILS"; then
    cp "$GRADIO_ROUTE_UTILS" "$GRADIO_ROUTE_UTILS.backup"

    python3 << 'GRADIO_PATCH_EOF'
import re

gradio_file = "/opt/conda/envs/wan2gp/lib/python3.10/site-packages/gradio/route_utils.py"

with open(gradio_file, 'r') as f:
    content = f.read()

# Replace the ValueError line with RunPod-aware logic
old_line = "raise ValueError(f\"Request url '{root_url}' has an unkown api call pattern.\")"
new_lines = """# Handle RunPod proxy URLs
    if ".proxy.runpod.net" in root_url:
        return "/api/predict"
    raise ValueError(f"Request url '{root_url}' has an unkown api call pattern.")"""

content = content.replace(old_line, new_lines)

with open(gradio_file, 'w') as f:
    f.write(content)

print("✅ Patched Gradio route_utils.py for RunPod")
GRADIO_PATCH_EOF

    echo "Gradio patched successfully"
else
    echo "Gradio already patched or file not found"
fi

WGP_ARGS=(
    "--server-name=0.0.0.0"
    "--server-port=7860"
)

if [ -n "$ATTENTION_MODE" ]; then
  WGP_ARGS+=("$ATTENTION_MODE")
fi

echo "Patching wgp.py for RunPod proxy compatibility..."
if ! grep -q "root_path=" wgp.py; then
    cp wgp.py wgp.py.backup

    # Use Python to patch the file more reliably
    python3 << 'EOF'
import re

# Read the original file
with open('wgp.py', 'r') as f:
    content = f.read()

# Find the launch call and replace it
old_pattern = r'demo\.launch\(server_name=server_name,\s*server_port=server_port,\s*share=args\.share,\s*allowed_paths=\[save_path\]\)'
new_launch = 'demo.launch(server_name=server_name, server_port=server_port, share=args.share, allowed_paths=[save_path], root_path=os.getenv("GRADIO_ROOT_PATH", ""))'

# Replace the pattern
content = re.sub(old_pattern, new_launch, content)

# Write back to file
with open('wgp.py', 'w') as f:
    f.write(content)

print("✅ wgp.py patched successfully")
EOF
else
    echo "✅ wgp.py already patched"
fi

# Start Wan2GP
echo "▶️  Starting Wan2GP with RunPod proxy support"
nohup python wgp.py --listen ${ATTENTION_MODE:+$ATTENTION_MODE} > "$NETWORK_VOLUME/wan2gp_${RUNPOD_POD_ID}_nohup.log" 2>&1 &

# Wait for Wan2GP to start
until curl --silent --fail "$URL" --output /dev/null; do
  echo "🔄  Wan2GP Starting Up... You can view the startup logs here: $NETWORK_VOLUME/wan2gp_${RUNPOD_POD_ID}_nohup.log"
  sleep 2
done

echo "🚀 Wan2GP is UP and running at http://localhost:7860"
sleep infinity