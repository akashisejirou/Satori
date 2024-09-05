#!/bin/bash

set -e

install_docker() {
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

test_docker() {
    sudo docker run hello-world
}

satori_setup() {
    sudo apt update
    sudo apt install -y mc

    if ! getent group docker >/dev/null; then
        sudo groupadd docker
    fi

    if ! groups $USER | grep &>/dev/null "\bdocker\b"; then
        sudo usermod -aG docker $USER
        echo "You need to log out and log back in for the group changes to take effect."
    fi

    cd ~
    wget -P ~/ https://satorinet.io/static/download/linux/satori.zip
    unzip ~/satori.zip
    rm ~/satori.zip

    cd ~/.satori
    sudo apt install -y python3-venv
    bash install.sh
    bash install_service.sh
    journalctl -fu satori.service
}

install_docker
test_docker
satori_setup
