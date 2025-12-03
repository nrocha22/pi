#!/bin/bash
#
# Depilarte Digital Signage - Script de Instalación
# Ejecutar por SSH después de flashear con Raspberry Pi Imager
#
# Uso: curl -sL [URL] | bash
#   o: bash install_depilarte.sh
#

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

LOGFILE="/var/log/depilarte_install.log"
TAILSCALE_AUTHKEY="tskey-auth-kgQbqhPdAv11CNTRL-dZC5XzNiLvQjUuEn9QHfvQ2pW944Y5t6T"

log() {
    echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $1" | tee -a "$LOGFILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOGFILE"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOGFILE"
}

echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║  Depilarte Digital Signage - Instalación          ║"
echo "║  Bullseye + Tailscale + Anthias                   ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

# Verificar que es Bullseye
if grep -q "bullseye" /etc/os-release; then
    log "✓ Sistema operativo: Debian Bullseye (correcto)"
else
    warn "Este script está diseñado para Bullseye"
    cat /etc/os-release
    read -p "¿Continuar de todos modos? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        exit 1
    fi
fi

# Verificar conexión de red
log "Verificando conexión de red..."
if ! ping -c 1 google.com &> /dev/null; then
    error "No hay conexión a internet"
    exit 1
fi
log "✓ Conexión de red OK"

# Actualizar sistema
log "Actualizando sistema (esto toma unos minutos)..."
sudo apt update -qq
sudo apt upgrade -y -qq
sudo apt install -y curl git vim

# ══════════════════════════════════════════════════════
# INSTALAR TAILSCALE
# ══════════════════════════════════════════════════════
log "Instalando Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

log "Conectando a red Tailscale..."
sudo tailscale up --authkey="$TAILSCALE_AUTHKEY" --hostname="$(hostname)"

TAILSCALE_IP=$(sudo tailscale ip -4 2>/dev/null || echo "No asignada")
log "✓ Tailscale conectado: $TAILSCALE_IP"

# Guardar info
echo "$(hostname)|$TAILSCALE_IP|$(date)" | sudo tee /home/pi/tailscale_info.txt > /dev/null
sudo chown pi:pi /home/pi/tailscale_info.txt

# ══════════════════════════════════════════════════════
# INSTALAR ANTHIAS
# ══════════════════════════════════════════════════════
log "Instalando Anthias..."
log "IMPORTANTE: Responde 'n' a ambas preguntas:"
log "  - Manage network? → n"
log "  - Full system upgrade? → n"
echo ""
echo -e "${YELLOW}Presiona ENTER para continuar con la instalación de Anthias...${NC}"
read

cd /home/pi
bash <(curl -sL https://install-anthias.srly.io)

# ══════════════════════════════════════════════════════
# FINALIZACIÓN
# ══════════════════════════════════════════════════════
echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║  ✓ INSTALACIÓN COMPLETADA                         ║"
echo "╠════════════════════════════════════════════════════╣"
echo "║  Hostname: $(hostname)"
echo "║  IP Tailscale: $TAILSCALE_IP"
echo "║  Anthias Web: http://$TAILSCALE_IP:8080"
echo "╠════════════════════════════════════════════════════╣"
echo "║  La Pi se reiniciará en 10 segundos...            ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

sleep 10
sudo reboot
