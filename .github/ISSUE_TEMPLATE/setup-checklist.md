---
name: "⚙️ Checklist de Setup — Nuevo Proyecto"
about: "Usa esta issue para trackear el onboarding del proyecto al pipeline CI/CD de Aurora"
title: "Setup CI/CD: [NOMBRE DEL PROYECTO]"
labels: ["infrastructure", "setup"]
assignees: []
---

## Checklist de pre-requisitos

### Repositorio GitHub
- [ ] Nombre del repo en minúsculas o confirmado que el workflow hace lowercase
- [ ] Rama `development` creada (no `develop`)
- [ ] Rama `main` protegida

### Dockerfile y app
- [ ] `Dockerfile` multi-stage copiado y adaptado al framework
- [ ] Para Next.js: `output: "standalone"` agregado en `next.config.ts`
- [ ] Build local verifica: `docker build -t test .`

### k8s manifests
- [ ] `APP_NAME` reemplazado en todos los archivos de `k8s/`
- [ ] Nombre del container en `deployment.yaml` anotado: `CONTAINER_NAME = ______`
- [ ] Ese mismo nombre configurado en el workflow (`deploy.yml`: `kubectl set image ... CONTAINER_NAME=...`)
- [ ] Namespace `qa` y `prod` creados en el cluster
- [ ] `imagePullSecrets: [{name: ghcr-credentials}]` presente en `deployment.yaml`
- [ ] Labels de nodos verificados (`environment=qa`, `environment=prod`)

### GitHub Secrets
- [ ] `SSH_PROXMOX_KEY` — clave privada ed25519
- [ ] `PROXMOX_HOST` — IP pública o Tailscale de Proxmox

### GitHub Environments
- [ ] Environment `qa` creado (sin protección)
- [ ] Environment `prod` creado (con `protected_branches: true`)

### Vault
- [ ] `secret/shared/postgres` creado
- [ ] `secret/qa/APP_NAME` creado con todos los secrets de la app
- [ ] `secret/prod/APP_NAME` creado con todos los secrets de la app
- [ ] ExternalSecret en QA muestra `SecretSynced: True`
- [ ] ExternalSecret en PROD muestra `SecretSynced: True`

### Workflow
- [ ] `CT_ID` reemplazado con el ID del CT de Proxmox correcto
- [ ] `APP_NAME` reemplazado en `kubectl set image` y `rollout status`
- [ ] `CONTAINER_NAME` reemplazado (coincide con `deployment.yaml`)

### Primer deploy
- [ ] Pipeline `build-and-push` completado
- [ ] Pipeline `deploy-qa` → `Refresh GHCR pull secret` completado
- [ ] Pipeline `deploy-qa` → `Deploy image to QA` completado
- [ ] Pod en `qa` en estado `1/1 Running`
- [ ] Imagen tiene formato: `ghcr.io/diwolf/app-name:sha-xxxxxxx` (minúsculas)

---

## Notas del proyecto

<!-- Documenta aquí cualquier configuración especial, desvíos del template, 
     o problemas encontrados durante el setup -->
