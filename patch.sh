#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# patch.sh — Aplica el patch premium a TickTick (Linux/Electron) en un comando
# Uso: ./patch.sh
# Revertir: ./revert.sh
# ============================================================================

ASAR_ORIGINAL="/opt/TickTick/resources/app.asar"
BACKUP="/tmp/ticktick-asar-backup-$(date +%Y%m%d_%H%M%S).asar"
WORKDIR="/tmp/ticktick-patch-work"
PATCHED="/tmp/ticktick-asar-patched.asar"

# --- Verificaciones ---
if [ ! -f "$ASAR_ORIGINAL" ]; then
    echo "ERROR: No se encontró $ASAR_ORIGINAL. ¿TickTick está instalado?"
    exit 1
fi
if ! command -v npx &>/dev/null; then
    echo "ERROR: npx no encontrado. Instalá node/npm."
    exit 1
fi
if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 no encontrado."
    exit 1
fi

# --- Backup ---
echo "[1/6] Backup del asar original → $BACKUP"
cp "$ASAR_ORIGINAL" "$BACKUP"

# --- Extraer ---
echo "[2/6] Extrayendo asar..."
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
npx asar extract "$ASAR_ORIGINAL" "$WORKDIR/app" 2>/dev/null

# --- Encontrar vendor file ---
VENDOR=$(grep -rl "proEndDate" "$WORKDIR/app/public/react/static/" --include="*.js" 2>/dev/null | head -1)
if [ -z "$VENDOR" ]; then
    echo "ERROR: No se encontró el archivo vendor con proEndDate."
    exit 1
fi
echo "    Vendor: $VENDOR"

# --- Aplicar patches ---
echo "[3/6] Aplicando patches..."

python3 - "$WORKDIR" "$VENDOR" <<'PYEOF'
import sys, os

workdir = sys.argv[1]
vendor = sys.argv[2]

def patch_file(path, old, new, label):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    if old not in content:
        print(f"  FAIL: patrón no encontrado en {label}")
        print(f"        {old[:80]}...")
        sys.exit(1)
    content = content.replace(old, new, 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"  OK: {label}")

bundler = os.path.join(workdir, "app", "bundler", "index.js")

# Patch 1: bundler login-with-token
patch_file(bundler,
    'const t=await c.request.get(`${c.config.protocol}${c.config.api_domain}/api/v2/user/status`);200===t.status?c.storage.setGlobalUser(n(t.data)):(c.storage.removeToken(),c.util.clearSessionCookies()),s=!0,c.util.analyticsDevice(!1),await c.launchLogin()',
    'const t=await c.request.get(`${c.config.protocol}${c.config.api_domain}/api/v2/user/status`);t.data.proEndDate="2030-01-01T00:00:00.000+0000";t.data.needSubscribe=false;t.data.freeTrial=true;t.data.pro=true;200===t.status?c.storage.setGlobalUser(n(t.data)):(c.storage.removeToken(),c.util.clearSessionCookies()),s=!0,c.util.analyticsDevice(!1),await c.launchLogin()',
    "bundler patch 1 (login-with-token)")

# Patch 2: bundler launchLogin
patch_file(bundler,
    'const i=await this.request.get(`${this.config.protocol}${this.config.api_domain}/api/v2/user/status`);200===i.status&&this.storage.setGlobalUser(d(i.data))',
    'const i=await this.request.get(`${this.config.protocol}${this.config.api_domain}/api/v2/user/status`);i.data.proEndDate="2030-01-01T00:00:00.000+0000";i.data.needSubscribe=false;i.freeTrial=true;i.data.pro=true;200===i.status&&this.storage.setGlobalUser(d(i.data))',
    "bundler patch 2 (launchLogin)")

# Patch 3: vendor SET_USERPROFILE reducer
patch_file(vendor,
    't=arguments.length>1?arguments[1]:void 0;switch(t.type){case _b.SET_USERPROFILE:',
    't=arguments.length>1?arguments[1]:void 0;if(t.data){if(t.data.proEndDate){t.data.proEndDate=e.get("proEndDate");t.data.pro=true;t.data.needSubscribe=false;t.data.subscribeType="trial";}}switch(t.type){case _b.SET_USERPROFILE:',
    "vendor patch 3 (SET_USERPROFILE)")

# Patch 4: neutralizar throw new Error
patch_file(vendor,
    '"use strict";var a=n("VRtw");e.exports=function(e,t,n,i,r){var o=new Error(e);return a(o,t,n,i,r)}',
    '"use strict";var a=n("VRtw");e.exports=function(e,t,n,i,r){return;var o=new Error(e);return a(o,t,n,i,r)}',
    "vendor patch 4 (throw new Error)")

print("Todos los patches aplicados.")
PYEOF

# --- Repackear ---
echo "[4/6] Repackeando asar..."
npx asar pack "$WORKDIR/app" "$PATCHED" 2>/dev/null

# --- Reemplazar ---
echo "[5/6] Reemplazando asar original (requiere sudo)..."
sudo cp "$PATCHED" "$ASAR_ORIGINAL"

# --- Verificar ---
echo "[6/6] Verificando..."
file "$ASAR_ORIGINAL"

echo ""
echo "✓ Patch aplicado correctamente."
echo "  Backup: $BACKUP"
echo "  Lanzá TickTick para probar: ticktick"
echo "  Para revertir: ./revert.sh"