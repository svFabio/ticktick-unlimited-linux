#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# revert.sh — Revierte el patch de TickTick restaurando el asar original
# ============================================================================

ASAR_ORIGINAL="/opt/TickTick/resources/app.asar"

# Buscar el backup más reciente
BACKUP=$(find /tmp -maxdepth 1 -name "ticktick-asar-backup-*.asar" -type f -printf "%T@ %p\n" 2>/dev/null | sort -rn | head -1 | cut -d" " -f2-)

if [ -z "$BACKUP" ]; then
    echo "ERROR: No se encontró backup en /tmp/ticktick-asar-backup-*.asar"
    echo "       Si tenés un backup manual, copialo manualmente:"
    echo "       sudo cp /ruta/al/backup.asar $ASAR_ORIGINAL"
    exit 1
fi

echo "Restaurando desde: $BACKUP"
sudo cp "$BACKUP" "$ASAR_ORIGINAL"
file "$ASAR_ORIGINAL"
echo "✓ Revertido. Lanzá TickTick para verificar."