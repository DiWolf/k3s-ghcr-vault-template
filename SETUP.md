# SETUP.md — Guía Paso a Paso

> Sigue cada paso en orden. Cada sección tiene una nota **NOTA: Trampa común** que documenta errores reales que no están en la documentación oficial.

---

## Índice

1. [Pre-requisitos en el cluster](#1-pre-requisitos-en-el-cluster)
2. [Paso 1 — Preparar el repositorio GitHub](#paso-1--preparar-el-repositorio-github)
3. [Paso 2 — Configurar el Dockerfile](#paso-2--configurar-el-dockerfile)
4. [Paso 3 — Adaptar los manifests de k8s](#paso-3--adaptar-los-manifests-de-k8s)
5. [Paso 4 — Configurar GitHub Secrets](#paso-4--configurar-github-secrets)
6. [Paso 5 — Configurar GitHub Environments](#paso-5--configurar-github-environments)
7. [Paso 6 — Preparar el cluster](#paso-6--preparar-el-cluster)
8. [Paso 7 — Configurar Vault](#paso-7--configurar-vault)
9. [Paso 8 — Adaptar el workflow](#paso-8--adaptar-el-workflow)
10. [Paso 9 — Primer deploy](#paso-9--primer-deploy)
11. [Errores conocidos y soluciones](#errores-conocidos-y-soluciones)

---

## 1. Pre-requisitos en el cluster

Antes de crear el proyecto, confirma que tienes operativo:

| Componente | Verificación |
|---|---|
| k3s (o distribución k8s) | `kubectl get nodes` |
| ExternalSecrets Operator | `kubectl get crd externalsecrets.external-secrets.io` |
| ClusterSecretStore apuntando a Vault | `kubectl get clustersecretstore` |
| Nodos con labels de ambiente | `kubectl get nodes --show-labels \| grep environment=` |
| HashiCorp Vault accesible desde el cluster | Verifica con `vault status` desde un pod de prueba |

**Labels requeridos en los nodos:**
```bash
kubectl label node <NODO_QA>   environment=qa
kubectl label node <NODO_PROD> environment=prod
```

---

## Paso 1 — Preparar el repositorio GitHub

### 1.1 Nombre del repo — regla crítica

> **NOTA: Trampa común**: GitHub Container Registry (GHCR) **exige nombres en minúsculas**.
> Si el nombre del repo tiene mayúsculas (`User/MyApp`), k8s rechazará la imagen con `InvalidImageName`.

La imagen que se publica en GHCR **siempre se referencia en minúsculas**:

```bash
# Correcto
ghcr.io/myuser/mi-app:sha-abc1234

# Incorrecto — k8s lo rechaza
ghcr.io/MyUser/mi-app:sha-abc1234
```

El workflow en este template maneja la conversión automáticamente con:
```bash
echo "image_name=$(echo '${{ github.repository }}' | tr '[:upper:]' '[:lower:]')"
```

### 1.2 Ramas recomendadas

| Rama | Ambiente | Nota |
|---|---|---|
| `development` | QA | Nombre exacto — no confundir con `develop` |
| `main` | PROD | Protegida con aprobación manual |

> **NOTA: Trampa común**: `develop` y `development` **no son la misma rama**.
> El workflow escucha `development`. Si tu rama activa se llama `develop`, el pipeline nunca se disparará.

```bash
# Verifica el nombre de tu rama activa antes de hacer push
git branch --show-current
```

---

## Paso 2 — Configurar el Dockerfile

El `Dockerfile` incluido en este template usa el modo **standalone** de Next.js.

**Ajusta la versión de Node si es necesario:**
```dockerfile
FROM node:20-alpine AS deps   # ← cambia la versión aquí
```

**Para Next.js** — agrega `output: "standalone"` en `next.config.ts`:
```typescript
const nextConfig: NextConfig = {
  output: "standalone",   // ← OBLIGATORIO para que Docker funcione
};
```

> **NOTA: Trampa común**: Sin `output: "standalone"`, el build de Docker completará
> sin errores pero el contenedor fallará al arrancar con:
> `Error: Cannot find module '/app/server.js'`

**Para otros frameworks** (Express, Fastify, etc.), reemplaza los stages de build
según el proceso de build de tu framework. Mantén el stage `runner` con usuario no-root y `CMD` apropiado.

---

## Paso 3 — Adaptar los manifests de k8s

### 3.1 Reemplazar placeholders

```bash
APP="mi-app"   # minúsculas, sin espacios
grep -r "APP_NAME\|CONTAINER_NAME" k8s/ --include="*.yaml" -l \
  | xargs sed -i "s/APP_NAME/$APP/g; s/CONTAINER_NAME/$APP/g"
```

### 3.2 Verificar el nombre del container — CRÍTICO

> **NOTA: Trampa común — la más difícil de diagnosticar**:
>
> `kubectl set image deployment/NAME CONTAINER=image` requiere que `CONTAINER`
> coincida **exactamente** con `spec.template.spec.containers[0].name` en tu YAML.
>
> Si no coincide, k8s devuelve este mensaje **que no menciona la causa real**:
> ```
> error: failed to patch image update to pod template:
> Deployment.apps "my-app" is invalid:
> spec.template.spec.containers[0].image: Required value
> ```

Verifica el nombre antes de hacer el primer deploy:

```bash
# En el YAML
grep -A2 "containers:" k8s/base/deployment.yaml
# Busca el campo "name:" justo debajo

# En el cluster (después del primer apply)
kubectl get deployment MY_APP -n qa \
  -o jsonpath='{.spec.template.spec.containers[0].name}'
```

Ese valor debe coincidir en el workflow:
```bash
grep "set image" .github/workflows/deploy.yml
# Debe mostrar: kubectl set image deployment/APP_NAME <CONTAINER_NAME>=...
```

### 3.3 Verificar nodeSelector

Confirma que los nodos del cluster tienen los labels correctos:
```bash
kubectl get nodes --show-labels | grep "environment="
# Esperado: environment=qa en nodo(s) de QA, environment=prod en nodo(s) de PROD
```

Si tus nodos usan labels diferentes, edita las patches en los overlays:
- `k8s/overlays/qa/kustomization.yaml`
- `k8s/overlays/prod/kustomization.yaml`

---

## Paso 4 — Configurar GitHub Secrets

### 4.1 Generar clave SSH para el nodo k3s

```bash
# En tu máquina local
ssh-keygen -t ed25519 -f ~/.ssh/github_actions_k8s -N "" -C "github-actions-deploy"

# Agregar la clave pública al nodo k3s
ssh-copy-id -i ~/.ssh/github_actions_k8s.pub USER@HOST_K8S

# Verificar
ssh -i ~/.ssh/github_actions_k8s USER@HOST_K8S "kubectl get nodes"
```

### 4.2 Agregar secrets al repo GitHub

```bash
gh secret set K8S_SSH_KEY --body "$(cat ~/.ssh/github_actions_k8s)" \
  --repo OWNER/REPO

gh secret set K8S_HOST --body "IP_O_HOSTNAME_DEL_NODO_K8S" \
  --repo OWNER/REPO

gh secret set K8S_USER --body "USUARIO_SSH" \
  --repo OWNER/REPO
```

> **NOTA: Trampa común**: No uses el token de `gh` CLI (`gh auth token`) para crear
> el secret de GHCR en k8s. Ese token **no tiene** el scope `packages` por defecto.
>
> El workflow ya resuelve esto: el step `Refresh GHCR pull secret` usa
> `GITHUB_TOKEN` que sí tiene `read:packages` automáticamente para el paquete del repo.

### 4.3 Verificar
```bash
gh secret list --repo OWNER/REPO
# Debe mostrar: K8S_SSH_KEY, K8S_HOST, K8S_USER
```

### 4.4 Nota para Proxmox

Si tu k3s corre dentro de un contenedor LXC de Proxmox, el host SSH es el **host de Proxmox** (no el CT directamente). Los comandos `kubectl` deben ir envueltos en `pct exec CT_ID -- bash -c "..."`. Consulta los comentarios en el workflow y el [repo privado de tu organización] para la implementación específica.

---

## Paso 5 — Configurar GitHub Environments

```bash
OWNER="tu-usuario"
REPO="tu-repo"

# QA: sin protección (deploy automático en push a development)
gh api repos/$OWNER/$REPO/environments/qa --method PUT

# PROD: protegido (requiere aprobación manual)
gh api repos/$OWNER/$REPO/environments/prod \
  --method PUT \
  --field "deployment_branch_policy[protected_branches]=true" \
  --field "deployment_branch_policy[custom_branch_policies]=false"

# Verificar
gh api repos/$OWNER/$REPO/environments --jq '[.environments[].name]'
# → ["qa", "prod"]
```

---

## Paso 6 — Preparar el cluster

```bash
# 1. Crear namespaces
kubectl create namespace qa   --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace prod --dry-run=client -o yaml | kubectl apply -f -

# 2. Crear secret inicial de GHCR
#    El workflow lo rota en cada deploy, pero necesita existir para el primer apply.
#    Usa un PAT con scope read:packages o el GITHUB_TOKEN de un workflow manual.
kubectl create secret docker-registry ghcr-credentials \
  --docker-server=ghcr.io \
  --docker-username=TU_USUARIO_GITHUB \
  --docker-password=TU_GITHUB_TOKEN \
  --namespace=qa \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret docker-registry ghcr-credentials \
  --docker-server=ghcr.io \
  --docker-username=TU_USUARIO_GITHUB \
  --docker-password=TU_GITHUB_TOKEN \
  --namespace=prod \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. Aplicar manifests
kubectl apply -k k8s/overlays/qa
kubectl apply -k k8s/overlays/prod

# 4. Verificar
kubectl get deployment,svc,externalsecret -n qa
kubectl get deployment,svc,externalsecret -n prod
```

---

## Paso 7 — Configurar Vault

### 7.1 Estructura de secrets recomendada

```
secret/
├── shared/
│   └── postgres          # url, host, port, dbname, user, password
├── qa/
│   └── APP_NAME          # secrets específicos del ambiente qa
└── prod/
    └── APP_NAME          # secrets específicos del ambiente prod
```

### 7.2 Crear secrets

```bash
export VAULT_ADDR="http://YOUR_VAULT_HOST:8200"
export VAULT_TOKEN="YOUR_VAULT_TOKEN"  # nunca hardcodees esto

# Compartidos entre ambientes
vault kv put secret/shared/postgres \
  url="postgresql://user:password@db-host:5432/dbname"

# Secrets de QA
vault kv put secret/qa/APP_NAME \
  NEXTAUTH_SECRET="$(openssl rand -hex 32)" \
  NEXTAUTH_URL="https://qa.tu-dominio.com" \
  APP_ENV="qa"

# Secrets de PROD
vault kv put secret/prod/APP_NAME \
  NEXTAUTH_SECRET="$(openssl rand -hex 32)" \
  NEXTAUTH_URL="https://tu-dominio.com" \
  APP_ENV="production"
```

### 7.3 Verificar sincronización de ExternalSecrets

```bash
kubectl get externalsecret -n qa
kubectl get externalsecret -n prod
# STATUS esperado: SecretSynced
```

Si el status no es `SecretSynced`, describe el resource para ver el error:
```bash
kubectl describe externalsecret APP_NAME-secrets -n qa
```

---

## Paso 8 — Adaptar el workflow

Abre `.github/workflows/deploy.yml` y verifica:

```yaml
# 1. Nombre del deployment debe existir en k8s
kubectl set image deployment/APP_NAME ...

# 2. CONTAINER_NAME debe coincidir con deployment.yaml
kubectl set image deployment/APP_NAME CONTAINER_NAME=...

# 3. Namespace correcto: -n qa / -n prod

# 4. Timeout apropiado (default 120s — aumenta para apps pesadas)
kubectl rollout status ... --timeout=120s
```

### Sobre el escaping de variables en bash

> **NOTA: Trampa común**: Si usas `pct exec` (Proxmox) o cualquier forma de subshell anidado,
> las variables de bash pueden no expandirse correctamente.
>
> ```bash
> # MAL — $IMAGE llega literal al kubectl, no se expande
> pct exec CT_ID -- bash -c "kubectl set image ... pos=\$IMAGE -n qa"
>
> # BIEN — IMAGE ya está expandida en el shell exterior antes de entrar al subshell
> IMAGE="ghcr.io/user/app:sha-abc1234"
> pct exec CT_ID -- bash -c "kubectl set image ... pos=${IMAGE} -n qa"
> ```
>
> Regla: define las variables **antes** del subshell y usa `${VAR}` sin escape.

---

## Paso 9 — Primer deploy

```bash
# Asegúrate de estar en la rama correcta
git branch --show-current   # debe mostrar: development

# Push inicial — el pipeline debe dispararse automáticamente
git push origin development

# Monitorear
gh run watch --repo OWNER/REPO
```

**Pipeline exitoso:**
```
build-and-push
  Set vars (lowercase image name + short SHA)
  Log in to GHCR
  Build & push

deploy-qa
  Refresh GHCR pull secret in QA namespace
  Deploy image to QA
```

**Validación final:**
```bash
kubectl get pods -n qa
# Esperado: 1/1 Running

kubectl get deployment APP_NAME -n qa \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
# Esperado: ghcr.io/user/app:sha-xxxxxxx (en minúsculas)
```

---

## Errores conocidos y soluciones

### `InvalidImageName` — repository name must be lowercase

```
Failed to pull image "ghcr.io/User/My-App:sha-abc":
invalid reference format: repository name must be lowercase
```

**Causa**: La imagen en el deployment tiene caracteres en mayúsculas.

**Solución**: El workflow convierte el nombre a minúsculas en el step `Set vars`
con `tr '[:upper:]' '[:lower:]'`. Verifica que usas `steps.vars.outputs.image_name`
(no `github.repository` directamente) cuando construyes la URL de la imagen.

---

### `403 Forbidden` en image pull desde GHCR

```
failed to pull and unpack image "ghcr.io/user/app:sha-abc":
unexpected status from HEAD request: 403 Forbidden
```

**Causa A**: El secret `ghcr-credentials` en k8s tiene un token sin scope `packages`.

El token del CLI de GitHub (`gh auth token`) tiene scopes `repo, workflow, read:org`
— **no incluye `packages`** salvo que lo hayas configurado explícitamente.

**Causa B**: El deployment no tiene `imagePullSecrets` definido.

**Solución**:
1. El workflow incluye el step `Refresh GHCR pull secret` que usa `GITHUB_TOKEN`
   (tiene `read:packages` automáticamente para el paquete del repo actual).
2. Confirma que `deployment.yaml` tiene:
   ```yaml
   imagePullSecrets:
     - name: ghcr-credentials
   ```

---

### `spec.containers[0].image: Required value` o `unable to find container "X"`

```
error: failed to patch image update to pod template:
Deployment.apps "my-app" is invalid:
spec.template.spec.containers[0].image: Required value
```

**Causa**: El nombre del container en `kubectl set image` no coincide con `containers[0].name` en el YAML del deployment.

**Diagnóstico**:
```bash
kubectl get deployment MY_APP -n qa \
  -o jsonpath='{.spec.template.spec.containers[0].name}'
```

Ese valor exacto es el que va en `kubectl set image deployment/NAME <ESTE_VALOR>=imagen`.

---

### Pipeline no se dispara en push

**Causa más común**: El trigger del workflow (`on.push.branches`) no coincide con tu rama activa.

```bash
git branch --show-current          # ve qué rama usas
grep -A5 "^on:" .github/workflows/deploy.yml  # ve qué escucha el workflow
```

El template usa `development`. Si tu rama de trabajo se llama diferente,
cambia el trigger en el workflow o renombra la rama.

---

### Variable `$IMAGE` llega literal a `kubectl set image`

```
kubectl set image deployment/app container=$IMAGE -n qa
error: ... spec.containers[0].image: Required value
```

**Causa**: La variable `$IMAGE` está siendo pasada a un subshell anidado sin expandir.

**Solución**:
```bash
# Define IMAGE primero en el shell actual
IMAGE="ghcr.io/user/app:sha-abc"

# Luego pásala al subshell — ya estará expandida
some-wrapper -- bash -c "kubectl set image deployment/app container=${IMAGE} -n qa"
```
