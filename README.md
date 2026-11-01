# ticktick-unlimited

Guía para desbloquear features premium de TickTick en Linux (Electron) mediante patching del `app.asar`.

> **Disclaimer:** Este repo es para fines educativos/testing. Modificar software puede violar los términos de servicio del desarrollador.

## Requisitos

- `node` / `npx` (para `@electron/asar`)
- `python3`
- `sudo` (para escribir en `/opt/TickTick`)
- TickTick instalado en `/opt/TickTick` (vía AUR: `yay -S ticktick`)

## Uso rápido (recomendado)

### One-liner (sin clonar el repo)

```bash
# Aplicar patch
curl -sSL https://raw.githubusercontent.com/svFabio/ticktick-unlimited/main/patch.sh | bash

# Revertir
curl -sSL https://raw.githubusercontent.com/svFabio/ticktick-unlimited/main/revert.sh | bash
```

### Con el repo clonado

```bash
make patch    # Aplica el patch
make revert   # Revierte al asar original
make status   # Verifica estado
```

O directamente:
```bash
./patch.sh    # Aplica el patch
./revert.sh   # Revierte al asar original
```

Los scripts automatizan todo el proceso (backup, extracción, patch, repack, reemplazo).

---

## Proceso de patching (manual)

### 1. Backup del asar original

```bash
cp /opt/TickTick/resources/app.asar /tmp/app.asar.original
```

### 2. Extraer el asar

```bash
mkdir -p /tmp/ticktick-asar
npx asar extract /opt/TickTick/resources/app.asar /tmp/ticktick-asar
```

### 3. Aplicar patches

Los archivos a modificar son:

- `bundler/index.js` — 2 lugares donde se llama a `/api/v2/user/status`
- `public/react/static/vendor.*.js` — reducer `SET_USERPROFILE` y función `throw new Error`

#### bundler/index.js — patch 1 (handler login-with-token)

Buscar:
```
const t=await c.request.get(`${c.config.protocol}${c.config.api_domain}/api/v2/user/status`);200===t.status?c.storage.setGlobalUser(n(t.data)):...
```

Reemplazar por:
```
const t=await c.request.get(`${c.config.protocol}${c.config.api_domain}/api/v2/user/status`);t.data.proEndDate="2030-01-01T00:00:00.000+0000";t.data.needSubscribe=false;t.data.freeTrial=true;t.data.pro=true;200===t.status?c.storage.setGlobalUser(n(t.data)):...
```

#### bundler/index.js — patch 2 (launchLogin)

Buscar:
```
const i=await this.request.get(`${this.config.protocol}${this.config.api_domain}/api/v2/user/status`);200===i.status&&this.storage.setGlobalUser(d(i.data))
```

Reemplazar por:
```
const i=await this.request.get(`${this.config.protocol}${this.config.api_domain}/api/v2/user/status`);i.data.proEndDate="2030-01-01T00:00:00.000+0000";i.data.needSubscribe=false;i.freeTrial=true;i.data.pro=true;200===i.status&&this.storage.setGlobalUser(d(i.data))
```

#### vendor.*.js — patch 3 (reducer SET_USERPROFILE)

Buscar:
```
t=arguments.length>1?arguments[1]:void 0;switch(t.type){case _b.SET_USERPROFILE:
```

Reemplazar por:
```
t=arguments.length>1?arguments[1]:void 0;if(t.data){if(t.data.proEndDate){t.data.proEndDate=e.get("proEndDate");t.data.pro=true;t.data.needSubscribe=false;t.data.subscribeType="trial";}}switch(t.type){case _b.SET_USERPROFILE:
```

#### vendor.*.js — patch 4 (neutralizar throw new Error)

Buscar:
```
"use strict";var a=n("VRtw");e.exports=function(e,t,n,i,r){var o=new Error(e);return a(o,t,n,i,r)}
```

Reemplazar por:
```
"use strict";var a=n("VRtw");e.exports=function(e,t,n,i,r){return;var o=new Error(e);return a(o,t,n,i,r)}
```

> **Nota:** El nombre del archivo vendor varía entre versiones (ej: `vendor.01c6875b1134851f7f53.js`). Usá `grep -rl "proEndDate"` para encontrarlo.

### 4. Repackear

```bash
npx asar pack /tmp/ticktick-asar /tmp/app.asar.patched
```

### 5. Reemplazar

```bash
sudo cp /tmp/app.asar.patched /opt/TickTick/resources/app.asar
```

### 6. Verificar

```bash
file /opt/TickTick/resources/app.asar
ticktick
```

## Revertir

```bash
sudo cp /tmp/app.asar.original /opt/TickTick/resources/app.asar
```

## Notas

- Después de actualizar TickTick (vía yay), el patch se pierde. Repetir el proceso.
- Algunas features pueden estar restringidas server-side y no funcionar aunque el patch esté aplicado.
- El script `src/disable_alert.py` **NO es usable** — busca prologues genéricos (`push rbp; mov rbp, rsp`) que aparecen en miles de funciones y corrompe el binario. No usar.
- Basado en la guía de la comunidad: https://github.com/yazdipour/unlimited-ticktick-windows/issues/12