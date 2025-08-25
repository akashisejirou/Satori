#!/bin/bash
set -e

# Install Docker + Docker Compose V2 + prerequisites 
echo "Checking Docker and Docker Compose installation..."

if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null; then
    echo "Installing Docker, Docker Compose V2, and required packages..."

    sudo apt remove -y docker-compose || true
    sudo apt update || { echo "Failed to update packages"; exit 1; }
    sudo apt install -y ca-certificates curl gnupg lsb-release software-properties-common unzip bc || { echo "Failed to install prerequisites"; exit 1; }
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg || { echo "Failed to add Docker GPG key"; exit 1; }

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null || { echo "Failed to set up Docker repository"; exit 1; }
      
    sudo apt update || { echo "Failed to update packages after adding Docker repo"; exit 1; }
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || { echo "Failed to install Docker"; exit 1; }

    if [ "$USER" != "root" ]; then
        echo "Adding user $USER to docker group..."
        sudo usermod -aG docker $USER || { echo "Failed to add user to docker group"; true; }
        echo "Running newgrp docker to apply group changes..."
        newgrp docker || { echo "newgrp docker failed, continuing as it may not be needed"; true; }
    else
        echo "Running as root, skipping docker group addition and newgrp."
    fi

    if ! docker info &> /dev/null; then
        echo "Docker daemon not running. Trying systemctl..."
        if ! sudo systemctl start docker; then
            echo "systemctl failed, starting dockerd manually..."
            sudo dockerd > /tmp/dockerd.log 2>&1 &
            sleep 5
        fi
        if ! docker info &> /dev/null; then
            echo "Docker daemon still not running. Please start it manually."
            exit 1
        fi
    fi

    # Verify Docker Compose V2
    docker compose version || { echo "Failed to verify Docker Compose V2"; exit 1; }
    echo "Docker and Docker Compose V2 installed successfully!"
else
    echo "Docker and Docker Compose V2 already installed, skipping reinstallation."
fi

# Stop and remove all existing Satori containers (ignore errors)
echo "Stopping and removing all existing Satori containers..."
EXISTING_CONTAINERS=$(docker ps -a -q --filter "name=satorineuron")
if [ -n "$EXISTING_CONTAINERS" ]; then
    docker stop $EXISTING_CONTAINERS || true
    docker rm $EXISTING_CONTAINERS || true
    echo "Existing Satori containers stopped and removed (if they existed)."
else
    echo "⚡ No existing Satori containers found."
fi

# Ask if user has existing nodes
read -p "Do you have existing nodes to migrate? (y/n): " HAS_EXISTING </dev/tty

if [[ "$HAS_EXISTING" =~ ^[Yy]$ ]]; then
    read -p "Enter the base directory of your existing nodes (e.g., /root/node/satori): " EXISTING_BASE </dev/tty
    MIGRATE_NODES=true
    echo "ℹScript will assume your existing nodes are in increments: ${EXISTING_BASE}0, ${EXISTING_BASE}1, etc."
else
    MIGRATE_NODES=false
fi

# Ask for number of nodes
read -p "Enter number of nodes: " NODE_COUNT </dev/tty


echo "Downloading Satori package..."
wget -P ~/ https://stage.satorinet.io/static/download/linux/linux.zip
unzip -o ~/linux.zip -d ~/
rm ~/linux.zip

if [ -d ~/linux/satori ]; then
    rm -rf ~/satori 2>/dev/null
    mv ~/linux/satori ~/satori
    rm -rf ~/linux
fi

BASE_DIR=~/satori
if [ ! -d "$BASE_DIR" ]; then
    echo "Base directory ~/satori not found!"
    exit 1
fi

# Base ports and resources
BASE_P2P_PORT=24600
BASE_UI_PORT=24601

TOTAL_CPU=$(nproc)
TOTAL_MEM=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEM_MB=$((TOTAL_MEM / 1024))

CPU_PER_NODE=$(echo "scale=2; $TOTAL_CPU / $NODE_COUNT" | bc)
MEM_PER_NODE=$((TOTAL_MEM_MB / $NODE_COUNT))

SERVER_IP=$(hostname -I | awk '{print $1}')

echo "------------------------------------------"
echo "Total CPU cores: $TOTAL_CPU"
echo "Total RAM: ${TOTAL_MEM_MB}MB"
echo "Each node will get $CPU_PER_NODE cores and ${MEM_PER_NODE}MB RAM"
echo "Server IP detected: $SERVER_IP"
echo "------------------------------------------"

# Setup nodes
for (( i=0; i<$NODE_COUNT; i++ ))
do
    NODE_DIR=~/satori${i}
    echo "Setting up node $i in $NODE_DIR..."

    rm -rf $NODE_DIR
    cp -r $BASE_DIR $NODE_DIR

    P2P_PORT=$((BASE_P2P_PORT + (i * 10)))
    UI_PORT=$((BASE_UI_PORT + (i * 10)))

    if [ "$MIGRATE_NODES" = true ]; then
        OLD_NODE_DIR=${EXISTING_BASE}${i}
    else
        OLD_NODE_DIR=~/.satori${i}
    fi

    for FOLDER in config wallet data models; do
        if [ -d "$OLD_NODE_DIR/$FOLDER" ]; then
            rm -rf $NODE_DIR/$FOLDER
            cp -r $OLD_NODE_DIR/$FOLDER $NODE_DIR/
        fi
    done
    
    CONFIG_FILE=$NODE_DIR/config/config.yaml
    if [ -f "$CONFIG_FILE" ]; then
        sed -i '/server ip:/d' $CONFIG_FILE
        sed -i '/server port:/d' $CONFIG_FILE
        sed -i '/ui port:/d' $CONFIG_FILE
        sed -i '/engine version:/d' $CONFIG_FILE
        sed -i '/prediction stream:/d' $CONFIG_FILE

        echo "server ip: 0.0.0.0" >> $CONFIG_FILE
        echo "server port: ${P2P_PORT}" >> $CONFIG_FILE
        echo "ui port: ${UI_PORT}" >> $CONFIG_FILE
        echo "engine version: v2" >> $CONFIG_FILE
        echo "prediction stream: null" >> $CONFIG_FILE
    fi

    COMPOSE_FILE=$NODE_DIR/docker-compose.yaml
    
    sed -i "/^version:/d" $COMPOSE_FILE
    sed -i "/- ~\/.satori\/config:/c\      - ${NODE_DIR}/config:/Satori/Neuron/config" $COMPOSE_FILE
    sed -i "/- ~\/.satori\/wallet:/c\      - ${NODE_DIR}/wallet:/Satori/Neuron/wallet" $COMPOSE_FILE
    sed -i "/- ~\/.satori\/data:/c\      - ${NODE_DIR}/data:/Satori/Neuron/data" $COMPOSE_FILE
    sed -i "/- ~\/.satori\/models:/c\      - ${NODE_DIR}/models:/Satori/Neuron/models" $COMPOSE_FIL
    sed -i "/deploy:/,/memory:/d" $COMPOSE_FILE
    sed -i "/image:/a\    deploy:\n      resources:\n        limits:\n          cpus: '${CPU_PER_NODE}'\n          memory: ${MEM_PER_NODE}M" $COMPOSE_FILE
    sed -i "/container_name:/d" $COMPOSE_FILE
    sed -i "/image:/a\    container_name: satorineuron${i}" $COMPOSE_FILE

    if command -v ufw &> /dev/null && sudo ufw status | grep -q "Status: active"; then
        echo "UFW is active, opening ports ${UI_PORT} and ${P2P_PORT}..."
        sudo ufw allow ${UI_PORT}/tcp || true
        sudo ufw allow ${P2P_PORT}/tcp || true
    fi

    cd $NODE_DIR
    docker compose up -d || echo "Failed to start container satorineuron${i}, continuing..."

    echo "Node $i running (container: satorineuron${i}, P2P=${P2P_PORT}, UI=${UI_PORT})"

    sleep 10
done

echo "------------------------------------------"
echo "All $NODE_COUNT nodes deployed, migrated old data if exists, set to auto-restart, and have prediction stream set!"
echo "Logs: cd ~/satori<n> && docker compose logs -f satorineuron<n> (n ∈ N)"
