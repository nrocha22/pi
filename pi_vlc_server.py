#!/usr/bin/env python3
"""
Depilarte Digital Signage - Pi VLC Server
Servidor que emula la API de Anthias usando VLC para reproducción
"""

from flask import Flask, request, jsonify, send_from_directory
import os
import subprocess
import json
import time
import signal
from datetime import datetime
from pathlib import Path
import threading

app = Flask(__name__)

# Configuración
VIDEO_DIR = '/home/pi/videos'
CONFIG_FILE = '/home/pi/signage_config.json'
PLAYLIST_FILE = '/home/pi/playlist.m3u'

# Estado global
vlc_process = None
start_time = datetime.now()

def ensure_dirs():
    """Crear directorios necesarios"""
    os.makedirs(VIDEO_DIR, exist_ok=True)

def load_config():
    """Cargar configuración"""
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE) as f:
            return json.load(f)
    return {'assets': []}

def save_config(config):
    """Guardar configuración"""
    with open(CONFIG_FILE, 'w') as f:
        json.dump(config, f, indent=2)

def generate_playlist():
    """Generar archivo de playlist M3U"""
    config = load_config()
    with open(PLAYLIST_FILE, 'w') as f:
        f.write('#EXTM3U\n')
        for asset in config.get('assets', []):
            if asset.get('is_enabled', True):
                video_path = os.path.join(VIDEO_DIR, asset['filename'])
                if os.path.exists(video_path):
                    f.write(f"#EXTINF:{asset.get('duration', 10)},{asset.get('name', 'Video')}\n")
                    f.write(f"{video_path}\n")

def restart_vlc():
    """Reiniciar VLC con la playlist actualizada"""
    global vlc_process
    
    # Matar proceso anterior
    if vlc_process:
        try:
            vlc_process.terminate()
            vlc_process.wait(timeout=5)
        except:
            vlc_process.kill()
    
    # Generar playlist
    generate_playlist()
    
    # Verificar que hay videos
    if not os.path.exists(PLAYLIST_FILE):
        return False
    
    with open(PLAYLIST_FILE) as f:
        content = f.read()
        if content.strip() == '#EXTM3U':
            return False  # Playlist vacía
    
    # Iniciar VLC
    try:
        vlc_process = subprocess.Popen([
            'cvlc',  # VLC sin interfaz
            '--fullscreen',
            '--loop',
            '--no-video-title-show',
            '--no-osd',
            '--quiet',
            PLAYLIST_FILE
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except Exception as e:
        print(f"Error starting VLC: {e}")
        return False

# ══════════════════════════════════════════════════════
# API ENDPOINTS (Compatible con Anthias API v1.2)
# ══════════════════════════════════════════════════════

@app.route('/api/v1.2/info', methods=['GET'])
def get_info():
    """Estado del dispositivo"""
    uptime_seconds = (datetime.now() - start_time).total_seconds()
    uptime_str = f"{int(uptime_seconds // 3600)}h {int((uptime_seconds % 3600) // 60)}m"
    
    return jsonify({
        'online': True,
        'uptime': uptime_str,
        'hostname': os.uname().nodename,
        'video_count': len(load_config().get('assets', [])),
        'vlc_running': vlc_process is not None and vlc_process.poll() is None,
        'system': 'vlc-signage'
    })

@app.route('/api/v1.2/assets', methods=['GET'])
def list_assets():
    """Listar todos los assets"""
    config = load_config()
    return jsonify(config.get('assets', []))

@app.route('/api/v1.2/file_asset', methods=['POST'])
def upload_asset():
    """Subir nuevo video"""
    if 'file_upload' not in request.files:
        return jsonify({'error': 'No file provided'}), 400
    
    file = request.files['file_upload']
    if file.filename == '':
        return jsonify({'error': 'No file selected'}), 400
    
    # Obtener parámetros
    name = request.form.get('name', file.filename)
    duration = int(request.form.get('duration', 10))
    is_enabled = request.form.get('is_enabled', '1') == '1'
    play_order = int(request.form.get('play_order', 0))
    
    # Guardar archivo
    ensure_dirs()
    filename = file.filename
    filepath = os.path.join(VIDEO_DIR, filename)
    file.save(filepath)
    
    # Actualizar config
    config = load_config()
    
    # Remover asset existente con mismo nombre
    config['assets'] = [a for a in config.get('assets', []) if a.get('filename') != filename]
    
    # Agregar nuevo asset
    asset = {
        'filename': filename,
        'name': name,
        'duration': duration,
        'is_enabled': is_enabled,
        'play_order': play_order,
        'uploaded_at': datetime.now().isoformat()
    }
    config['assets'].append(asset)
    
    # Ordenar por play_order
    config['assets'].sort(key=lambda x: x.get('play_order', 0))
    
    save_config(config)
    
    # Reiniciar VLC
    restart_vlc()
    
    return jsonify({
        'success': True,
        'asset': asset
    })

@app.route('/api/v1.2/assets/<asset_id>', methods=['DELETE'])
def delete_asset(asset_id):
    """Eliminar un asset"""
    config = load_config()
    
    # Buscar y eliminar
    asset_to_delete = None
    for asset in config.get('assets', []):
        if asset.get('filename') == asset_id or asset.get('name') == asset_id:
            asset_to_delete = asset
            break
    
    if not asset_to_delete:
        return jsonify({'error': 'Asset not found'}), 404
    
    # Eliminar archivo
    filepath = os.path.join(VIDEO_DIR, asset_to_delete['filename'])
    if os.path.exists(filepath):
        os.remove(filepath)
    
    # Actualizar config
    config['assets'] = [a for a in config['assets'] if a != asset_to_delete]
    save_config(config)
    
    # Reiniciar VLC
    restart_vlc()
    
    return jsonify({'success': True})

@app.route('/api/v1.2/reboot', methods=['POST'])
def reboot():
    """Reiniciar el dispositivo"""
    def do_reboot():
        time.sleep(2)
        os.system('sudo reboot')
    
    threading.Thread(target=do_reboot).start()
    return jsonify({'success': True, 'message': 'Rebooting in 2 seconds'})

@app.route('/api/v1.2/restart_vlc', methods=['POST'])
def api_restart_vlc():
    """Reiniciar VLC"""
    success = restart_vlc()
    return jsonify({'success': success})

# Endpoint adicional para listar videos en disco
@app.route('/api/videos', methods=['GET'])
def list_video_files():
    """Listar archivos de video en disco"""
    ensure_dirs()
    videos = []
    for f in os.listdir(VIDEO_DIR):
        if f.lower().endswith(('.mp4', '.mov', '.avi', '.mkv', '.webm')):
            filepath = os.path.join(VIDEO_DIR, f)
            videos.append({
                'filename': f,
                'size_mb': round(os.path.getsize(filepath) / (1024*1024), 2)
            })
    return jsonify(videos)

# Health check
@app.route('/health', methods=['GET'])
def health():
    return jsonify({'status': 'ok'})

@app.route('/', methods=['GET'])
def index():
    """Página de inicio simple"""
    config = load_config()
    videos = config.get('assets', [])
    vlc_status = "Running" if (vlc_process and vlc_process.poll() is None) else "Stopped"
    
    html = f"""
    <html>
    <head><title>Depilarte Signage - {os.uname().nodename}</title></head>
    <body style="font-family: Arial; padding: 20px;">
        <h1>🎥 Depilarte Digital Signage</h1>
        <p><strong>Hostname:</strong> {os.uname().nodename}</p>
        <p><strong>VLC Status:</strong> {vlc_status}</p>
        <p><strong>Videos:</strong> {len(videos)}</p>
        <h2>Playlist:</h2>
        <ul>
        {''.join(f"<li>{v.get('name', v['filename'])} ({v.get('duration', 10)}s)</li>" for v in videos)}
        </ul>
        <p><a href="/api/v1.2/info">API Info</a> | <a href="/api/v1.2/assets">Assets</a></p>
    </body>
    </html>
    """
    return html

def signal_handler(sig, frame):
    """Manejar señales de terminación"""
    global vlc_process
    if vlc_process:
        vlc_process.terminate()
    exit(0)

if __name__ == '__main__':
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
    
    ensure_dirs()
    
    # Intentar iniciar VLC si hay videos
    restart_vlc()
    
    print(f"""
    ╔════════════════════════════════════════════════════╗
    ║  Depilarte VLC Signage Server                     ║
    ╠════════════════════════════════════════════════════╣
    ║  Hostname: {os.uname().nodename:<37} ║
    ║  API: http://0.0.0.0:8080/api/v1.2/               ║
    ╚════════════════════════════════════════════════════╝
    """)
    
    app.run(host='0.0.0.0', port=8080, threaded=True)
