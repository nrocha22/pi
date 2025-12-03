#!/bin/bash
#
# Depilarte Digital Signage - Instalación VLC
# Para Raspberry Pi Zero 2 W con Bullseye
#
# Uso: curl -sL https://raw.githubusercontent.com/nrocha22/pi/main/install_vlc_signage.sh -o install.sh && sudo bash install.sh
#

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

LOGFILE="/var/log/depilarte_install.log"
TAILSCALE_AUTHKEY="tskey-auth-kgQbqhPdAv11CNTRL-dZC5XzNiLvQjUuEn9QHfvQ2pW944Y5t6T"
GITHUB_RAW="https://raw.githubusercontent.com/nrocha22/pi/main"

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
echo "║  Depilarte Digital Signage - VLC Edition          ║"
echo "║  Instalación para Raspberry Pi                     ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

# Verificar root
if [ "$EUID" -ne 0 ]; then
    error "Este script debe ejecutarse como root (sudo)"
    exit 1
fi

# Verificar arquitectura
ARCH=$(uname -m)
log "Arquitectura: $ARCH"

# Verificar conexión
log "Verificando conexión de red..."
if ! ping -c 1 google.com &> /dev/null; then
    error "No hay conexión a internet"
    exit 1
fi
log "✓ Conexión de red OK"

# ══════════════════════════════════════════════════════
# ACTUALIZAR SISTEMA
# ══════════════════════════════════════════════════════
log "Actualizando sistema..."
apt update -qq
apt upgrade -y -qq

# ══════════════════════════════════════════════════════
# INSTALAR DEPENDENCIAS
# ══════════════════════════════════════════════════════
log "Instalando VLC y dependencias..."
apt install -y \
    vlc \
    python3-flask \
    python3-pip \
    curl \
    git \
    vim

log "✓ VLC y dependencias instalados"

# ══════════════════════════════════════════════════════
# INSTALAR TAILSCALE
# ══════════════════════════════════════════════════════
log "Instalando Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

log "Conectando a red Tailscale..."
tailscale up --authkey="$TAILSCALE_AUTHKEY" --hostname="$(hostname)"

TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "No asignada")
log "✓ Tailscale conectado: $TAILSCALE_IP"

# Guardar info
echo "$(hostname)|$TAILSCALE_IP|$(date)" > /home/pi/tailscale_info.txt
chown pi:pi /home/pi/tailscale_info.txt

# ══════════════════════════════════════════════════════
# CREAR ESTRUCTURA DE DIRECTORIOS
# ══════════════════════════════════════════════════════
log "Creando estructura de directorios..."
mkdir -p /home/pi/videos
mkdir -p /home/pi/signage
chown -R pi:pi /home/pi/videos
chown -R pi:pi /home/pi/signage

# ══════════════════════════════════════════════════════
# DESCARGAR SERVIDOR VLC
# ══════════════════════════════════════════════════════
log "Descargando servidor VLC..."
curl -sL "$GITHUB_RAW/pi_vlc_server.py" -o /home/pi/signage/server.py
chmod +x /home/pi/signage/server.py
chown pi:pi /home/pi/signage/server.py

# ══════════════════════════════════════════════════════
# CREAR SERVICIO SYSTEMD
# ══════════════════════════════════════════════════════
log "Configurando servicio systemd..."

cat > /etc/systemd/system/depilarte-signage.service << 'EOF'
[Unit]
Description=Depilarte Digital Signage Server
After=network.target

[Service]
Type=simple
User=pi
Group=pi
WorkingDirectory=/home/pi/signage
ExecStart=/usr/bin/python3 /home/pi/signage/server.py
Restart=always
RestartSec=5
Environment=DISPLAY=:0

[Install]
WantedBy=multi-user.target
EOF

# ══════════════════════════════════════════════════════
# CONFIGURAR FRAMEBUFFER PARA VLC
# ══════════════════════════════════════════════════════
log "Configurando video output..."

# Permitir acceso al framebuffer
usermod -a -G video pi

# Configurar para que VLC use framebuffer
cat > /home/pi/.vlcrc << 'EOF'
[core]
vout=fb
aout=alsa

[fb]
fb-dev=/dev/fb0
EOF
chown pi:pi /home/pi/.vlcrc

# ══════════════════════════════════════════════════════
# HABILITAR SERVICIOS
# ══════════════════════════════════════════════════════
log "Habilitando servicios..."
systemctl daemon-reload
systemctl enable depilarte-signage
systemctl start depilarte-signage

# ══════════════════════════════════════════════════════
# CONFIGURAR BOOT
# ══════════════════════════════════════════════════════
log "Configurando boot..."

# Deshabilitar splash screen y cursor
if ! grep -q "consoleblank=0" /boot/cmdline.txt; then
    sed -i 's/$/ consoleblank=0 logo.nologo/' /boot/cmdline.txt
fi

# ══════════════════════════════════════════════════════
# CREAR CONFIG INICIAL
# ══════════════════════════════════════════════════════
cat > /home/pi/signage_config.json << 'EOF'
{
  "assets": []
}
EOF
chown pi:pi /home/pi/signage_config.json

# ══════════════════════════════════════════════════════
# FINALIZACIÓN
# ══════════════════════════════════════════════════════
TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "No disponible")

echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║  ✓ INSTALACIÓN COMPLETADA                         ║"
echo "╠════════════════════════════════════════════════════╣"
echo "║  Hostname: $(hostname)"
echo "║  IP Tailscale: $TAILSCALE_IP"
echo "║  Web UI: http://$TAILSCALE_IP:8080"
echo "║  API: http://$TAILSCALE_IP:8080/api/v1.2/"
echo "╠════════════════════════════════════════════════════╣"
echo "║  El sistema se reiniciará en 10 segundos...       ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

# Guardar resumen
cat > /home/pi/install_summary.txt << SUMMARY
Depilarte Digital Signage - Instalación completada
==================================================
Fecha: $(date)
Hostname: $(hostname)
IP Tailscale: $TAILSCALE_IP
Web UI: http://$TAILSCALE_IP:8080
API: http://$TAILSCALE_IP:8080/api/v1.2/

Comandos útiles:
- Ver estado: sudo systemctl status depilarte-signage
- Ver logs: sudo journalctl -u depilarte-signage -f
- Reiniciar servicio: sudo systemctl restart depilarte-signage
SUMMARY
chown pi:pi /home/pi/install_summary.txt

sleep 10
reboot
