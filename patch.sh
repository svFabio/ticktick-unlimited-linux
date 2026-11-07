#!/usr/bin/env bash
set -euo pipefail

ASAR_ORIGINAL="/opt/TickTick/resources/app.asar"
BACKUP="/tmp/ticktick-asar-backup-$(date +%Y%m%d_%H%M%S).asar"
WORKDIR="/tmp/ticktick-patch-work"
PATCHED="/tmp/ticktick-asar-patched.asar"

if [ ! -f "$ASAR_ORIGINAL" ]; then
    echo "ERROR: No se encontró $ASAR_ORIGINAL"
    exit 1
fi
if ! command -v npx &>/dev/null; then
    echo "ERROR: npx no encontrado"
    exit 1
fi
if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 no encontrado"
    exit 1
fi

echo "[1/6] Backup..."
cp "$ASAR_ORIGINAL" "$BACKUP"

echo "[2/6] Extrayendo asar..."
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
npx asar extract "$ASAR_ORIGINAL" "$WORKDIR/app" 2>/dev/null

VENDOR=$(grep -rl "proEndDate" "$WORKDIR/app/public/react/static/" --include="*.js" 2>/dev/null | head -1)
if [ -z "$VENDOR" ]; then
    echo "ERROR: No se encontró vendor con proEndDate"
    exit 1
fi
echo "    Vendor: $VENDOR"

echo "[3/6] Aplicando patches..."

python3 - "$WORKDIR" "$VENDOR" <<'PYEOF'
import sys, os, re

workdir = sys.argv[1]
vendor = sys.argv[2]
bundler = os.path.join(workdir, "app", "bundler", "index.js")

def patch_file(path, old, new, label):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    if old not in content:
        print("  FAIL: patron no encontrado en " + label)
        print("        " + old[:90])
        sys.exit(1)
    content = content.replace(old, new, 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("  OK: " + label)

# --- Patch 1: bundler login-with-token ---
with open(bundler, "r", encoding="utf-8") as f:
    content = f.read()

# Detect variable name (c or l)
varname = None
for v in ["c", "l"]:
    needle = "const t=await " + v + ".request.get(`${" + v + ".config.protocol}${" + v + ".config.api_domain}/api/v2/user/status`)"
    if needle in content:
        varname = v
        break

if varname is None:
    print("  FAIL: no se encontro variable de request en bundler")
    sys.exit(1)

v = varname
old1 = ("const t=await " + v + ".request.get(`${" + v + ".config.protocol}${" + v + ".config.api_domain}/api/v2/user/status`);"
        "200===t.status?" + v + ".storage.setGlobalUser(i(t.data)):(" + v + ".storage.removeToken()," + v + ".util.clearSessionCookies()),s=!0," + v + ".util.analyticsDevice(!1),await " + v + ".launchLogin()")
new1 = ("const t=await " + v + ".request.get(`${" + v + ".config.protocol}${" + v + ".config.api_domain}/api/v2/user/status`);"
        "t.data.proEndDate=\"2030-01-01T00:00:00.000+0000\";t.data.needSubscribe=false;t.data.freeTrial=true;t.data.pro=true;"
        "200===t.status?" + v + ".storage.setGlobalUser(i(t.data)):(" + v + ".storage.removeToken()," + v + ".util.clearSessionCookies()),s=!0," + v + ".util.analyticsDevice(!1),await " + v + ".launchLogin()")
patch_file(bundler, old1, new1, "bundler patch 1 (login-with-token)")

# --- Patch 2: bundler launchLogin ---
old2 = "const i=await this.request.get(`${this.config.protocol}${this.config.api_domain}/api/v2/user/status`);200===i.status&&this.storage.setGlobalUser(d(i.data))"
new2 = "const i=await this.request.get(`${this.config.protocol}${this.config.api_domain}/api/v2/user/status`);i.data.proEndDate=\"2030-01-01T00:00:00.000+0000\";i.data.needSubscribe=false;i.freeTrial=true;i.data.pro=true;200===i.status&&this.storage.setGlobalUser(d(i.data))"
patch_file(bundler, old2, new2, "bundler patch 2 (launchLogin)")

# --- Patch 3: vendor SET_USERPROFILE reducer ---
with open(vendor, "r", encoding="utf-8") as f:
    content = f.read()

import re
m = re.search(r't=arguments\.length>1\?arguments\[1\]:void 0;switch\(t\.type\)\{case (\w+)\.SET_USERPROFILE:', content)
if not m:
    print("  FAIL: enum SET_USERPROFILE no encontrado")
    sys.exit(1)
enum_name = m.group(1)

old3 = "t=arguments.length>1?arguments[1]:void 0;switch(t.type){case " + enum_name + ".SET_USERPROFILE:"
new3 = ('t=arguments.length>1?arguments[1]:void 0;if(t.data){if(t.data.proEndDate){'
       't.data.proEndDate=e.get("proEndDate");t.data.pro=true;t.data.needSubscribe=false;t.data.subscribeType="trial";}}'
       'switch(t.type){case ' + enum_name + '.SET_USERPROFILE:')
patch_file(vendor, old3, new3, "vendor patch 3 (SET_USERPROFILE)")

# --- Patch 4: neutralizar throw new Error ---
m = re.search(r'"use strict";var a=n\("VRtw"\);e\.exports=function\([^)]*\)\{var o=new Error\(e\);return a\(o,[^)]*\)\}', content)
if m:
    old4 = m.group(0)
    new4 = old4.replace("{var o=new Error(e);", "{return;var o=new Error(e);", 1)
    patch_file(vendor, old4, new4, "vendor patch 4 (throw new Error)")
else:
    print("  WARN: patron VRtw no encontrado, saltando patch 4")

print("Todos los patches aplicados.")
PYEOF

echo "[4/6] Repackeando asar..."
npx asar pack "$WORKDIR/app" "$PATCHED" 2>/dev/null

echo "[5/6] Reemplazando asar original..."
sudo cp "$PATCHED" "$ASAR_ORIGINAL"

echo "[6/6] Verificando..."
file "$ASAR_ORIGINAL"

echo ""
echo "Patch aplicado correctamente."
echo "  Backup: $BACKUP"
echo "  Lanzar TickTick: ticktick"
echo "  Revertir: ./revert.sh"