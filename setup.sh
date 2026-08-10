#!/bin/bash
set -e

echo "🚀 Setting up offline AI coding toolchain (Ollama + code-server + Continue + agents)..."

mkdir -p ./workspace ./ollama-data ./webui-data ./continue-config

# Create .env with a fresh random code-server password, but only the first
# time — re-running setup.sh must never clobber a password you've already
# rotated, or the tip in the README becomes a lie.
if [ ! -f .env ]; then
  echo "Generating a random code-server password (.env)..."
  GENERATED_PASSWORD="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24)"
  cat > .env << EOF
# Password for code-server (http://localhost:8080). Change anytime and
# restart with 'docker compose up -d' to apply — setup.sh will not
# overwrite this file on subsequent runs.
CODE_SERVER_PASSWORD=$GENERATED_PASSWORD
EOF
  echo "code-server password: $GENERATED_PASSWORD (saved in .env, not committed to git)"
else
  echo ".env already exists, leaving your code-server password as-is."
fi

# Create docker-compose.yml, but don't overwrite one you've customized
# (GPU section uncommented, ports changed, etc.) on re-runs.
#
# Ports bind to 127.0.0.1 only, on purpose: none of these services have
# real auth (open-webui and ollama have none at all; code-server's PASSWORD
# is the only gate). That's fine on a personal machine, but this compose
# file is also meant to run unmodified on a rented cloud VM, where binding
# to 0.0.0.0 would put an unauthenticated LLM API on the public internet.
# To reach a cloud VM's services from elsewhere, use cloud/agent-loop.sh
# (SSH tunnel) or Tailscale rather than widening these bindings.
#
# Images are pinned to specific versions rather than :latest/:main --
# floating tags mean an upstream push can silently break or change behavior
# of every running stack with no changelog to consult. Each is still
# overridable per the ${VAR:-default} syntax below (e.g. OLLAMA_DOCKER_TAG=
# in .env) if you want to track upstream more closely (testing an unreleased
# fix, chasing a new feature) or pin to something older; just know that
# overriding to `latest` specifically reintroduces the exact silent-break
# risk pinning exists to avoid -- fine for a throwaway/dev box, not
# recommended for a stack you depend on. Bump the defaults here
# periodically instead of leaving them on `latest` long-term.
if [ ! -f docker-compose.yml ]; then
cat > docker-compose.yml << 'EOF'
services:
  ollama:
    image: ollama/ollama:${OLLAMA_DOCKER_TAG:-0.32.6}
    container_name: ollama
    ports:
      - "127.0.0.1:11434:11434"
    volumes:
      - ./ollama-data:/root/.ollama
    restart: unless-stopped
    # For NVIDIA GPU: uncomment below
    # deploy:
    #   resources:
    #     reservations:
    #       devices:
    #         - driver: nvidia
    #           count: all
    #           capabilities: [gpu]

  open-webui:
    image: ghcr.io/open-webui/open-webui:${WEBUI_DOCKER_TAG:-0.11.0}
    container_name: open-webui
    ports:
      - "127.0.0.1:3000:8080"
    volumes:
      - ./webui-data:/app/backend/data
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
    depends_on:
      - ollama
    restart: unless-stopped

  code-server:
    image: codercom/code-server:${CODE_SERVER_DOCKER_TAG:-4.131.0}
    container_name: code-server
    ports:
      - "127.0.0.1:8080:8080"
    volumes:
      - ./workspace:/home/coder/workspace
      - ./continue-config:/home/coder/.continue
    environment:
      - PASSWORD=${CODE_SERVER_PASSWORD}
    restart: unless-stopped
EOF
else
  echo "docker-compose.yml already exists, leaving it untouched."
fi

# Create Continue config (pre-configured for Ollama).
# Written into ./continue-config/, which docker-compose mounts to
# /home/coder/.continue inside code-server — that's the path the Continue
# extension actually reads, so it has to live there (not the repo root) to
# take effect.
if [ ! -f continue-config/config.json ]; then
cat > continue-config/config.json << 'EOF'
{
  "models": [
    {
      "title": "Qwen2.5-Coder (Agentic)",
      "provider": "ollama",
      "model": "qwen2.5-coder:14b",
      "apiBase": "http://ollama:11434"
    }
  ],
  "tabAutocompleteModel": {
    "title": "Qwen2.5-Coder Autocomplete",
    "provider": "ollama",
    "model": "qwen2.5-coder:7b",
    "apiBase": "http://ollama:11434"
  },
  "slashCommands": [
    { "name": "edit", "description": "Edit code with agent" },
    { "name": "run", "description": "Run terminal commands" },
    { "name": "comment", "description": "Add comments" }
  ]
}
EOF
else
  echo "continue-config/config.json already exists, leaving it untouched."
fi

# Create requirements.txt for the Python workspace. Written into ./workspace/,
# which docker-compose mounts to /home/coder/workspace inside code-server —
# it has to live there, not the repo root, or setup_venv.py (also run from
# inside that container) won't be able to find it.
if [ ! -f workspace/requirements.txt ]; then
cat > workspace/requirements.txt << 'EOF'
numpy
pandas
matplotlib
sympy
requests
jupyter
aider-chat
langchain
langchain-community
EOF
else
  echo "workspace/requirements.txt already exists, leaving it untouched."
fi

# Create Python workspace setup script. Also written into ./workspace/ (see
# above) — it hardcodes /home/coder/workspace paths because it's meant to be
# run *inside* the code-server container, where that's where this file and
# requirements.txt actually land.
if [ ! -f workspace/setup_venv.py ]; then
cat > workspace/setup_venv.py << 'EOF'
#!/usr/bin/env python3
import os
import subprocess
import sys

venv_path = "/home/coder/workspace/venv"
requirements_path = "/home/coder/workspace/requirements.txt"

if not os.path.exists(venv_path):
    print("Creating isolated Python venv...")
    subprocess.check_call([sys.executable, "-m", "venv", venv_path])

    print("Installing Python packages for scripting + agents...")
    pip = os.path.join(venv_path, "bin", "pip")
    try:
        subprocess.check_call([pip, "install", "-r", requirements_path])
    except subprocess.CalledProcessError as e:
        print(f"pip install failed (exit {e.returncode}). "
              f"venv was created but packages may be incomplete; "
              f"re-run 'pip install -r {requirements_path}' inside it.",
              file=sys.stderr)
        sys.exit(e.returncode)

    print("✅ Venv ready! Activate with: source venv/bin/activate")
else:
    print("Venv already exists.")
EOF
else
  echo "workspace/setup_venv.py already exists, leaving it untouched."
fi

echo "✅ All files created!"
echo "Next steps:"
echo "1. docker compose up -d"
echo "2. docker exec -it ollama ollama pull qwen2.5-coder:7b   # (start small) or :14b for better quality"
echo "3. docker exec -it ollama ollama pull nomic-embed-text   # (optional embedding)"
echo "4. Open http://localhost:8080 (code-server, password in .env)"
echo "5. In code-server terminal: cd /home/coder/workspace && python3 setup_venv.py"
echo "6. Install Continue extension from VS Code marketplace (one-time)"
echo "7. Open WebUI chat: http://localhost:3000"
echo "8. Running this on a rented cloud VM instead? Services are bound to"
echo "   127.0.0.1 only — connect from your phone/laptop with"
echo "   cloud/agent-loop.sh (SSH tunnel) rather than opening these ports."
echo "9. Image versions are pinned in docker-compose.yml -- override e.g."
echo "   OLLAMA_DOCKER_TAG=latest in .env if you want to track upstream"
echo "   more closely, then 'docker compose up -d' to apply."
echo "All set for offline mobile dev! 🎉"

chmod +x setup.sh
echo "✅ Run ./setup.sh to finish setup (already done if you see this)"
