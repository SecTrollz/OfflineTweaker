#!/bin/bash
set -e

echo "🚀 Setting up offline AI coding toolchain (Ollama + code-server + Continue + agents)..."

mkdir -p ./workspace ./ollama-data ./webui-data ./continue-config

# Create docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    ports:
      - "11434:11434"
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
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    ports:
      - "3000:8080"
    volumes:
      - ./webui-data:/app/backend/data
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
    depends_on:
      - ollama
    restart: unless-stopped

  code-server:
    image: codercom/code-server:latest
    container_name: code-server
    ports:
      - "8080:8080"
    volumes:
      - ./workspace:/home/coder/workspace
      - ./continue-config:/home/coder/.continue
    environment:
      - PASSWORD=ChangeThisToAStrongPassword123!
    restart: unless-stopped
EOF

# Create Continue config (pre-configured for Ollama)
cat > continue_config.json << 'EOF'
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

# Create requirements.txt for Python workspace
cat > requirements.txt << 'EOF'
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

# Create Python workspace setup script
cat > setup_venv.py << 'EOF'
#!/usr/bin/env python3
import os
import subprocess

venv_path = "/home/coder/workspace/venv"
if not os.path.exists(venv_path):
    print("Creating isolated Python venv...")
    subprocess.check_call(["python", "-m", "venv", venv_path])
    
    print("Installing high-quality Python packages for scripting + agents...")
    pip = os.path.join(venv_path, "bin", "pip")
    subprocess.check_call([pip, "install", "-r", "/home/coder/workspace/requirements.txt"])
    
    print("✅ Venv ready! Activate with: source venv/bin/activate")
else:
    print("Venv already exists.")
EOF

echo "✅ All files created!"
echo "Next steps:"
echo "1. docker compose up -d"
echo "2. docker exec -it ollama ollama pull qwen2.5-coder:7b   # (start small) or :14b for better quality"
echo "3. docker exec -it ollama ollama pull nomic-embed-text   # (optional embedding)"
echo "4. Open http://localhost:8080 (code-server, password above)"
echo "5. In code-server terminal: cd /home/coder/workspace && python setup_venv.py"
echo "6. Install Continue extension from VS Code marketplace (one-time)"
echo "7. Open WebUI chat: http://localhost:3000"
echo "All set for offline mobile dev! 🎉"
EOF

chmod +x setup.sh
echo "✅ Run ./setup.sh to finish setup (already done if you see this)"
