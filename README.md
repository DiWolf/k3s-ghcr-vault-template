# k3s-ghcr-vault-template

Template para desplegar aplicaciones **Node.js / Next.js** en un cluster **k3s** usando **GitHub Actions**, **GHCR** como registro y **HashiCorp Vault + ExternalSecrets** para la gestión de secrets.

Incluye una guía detallada con los errores más comunes que se cometen al configurar este stack por primera vez — y cómo evitarlos.

## Stack

| Capa | Tecnología |
|---|---|
| App | Next.js / Node.js |
| Contenedor | Docker multi-stage → standalone |
| Registro | GitHub Container Registry (GHCR) |
| Orquestación | k3s |
| Secrets | HashiCorp Vault + ExternalSecrets Operator |
| CI/CD | GitHub Actions |
| Config por ambiente | Kustomize (base + overlays) |

## Estructura

```
.
├── .github/
│   ├── workflows/
│   │   └── deploy.yml          # Pipeline: build → push GHCR → kubectl set image
│   └── ISSUE_TEMPLATE/
│       └── setup-checklist.md  # Checklist de onboarding para rastrear el setup
├── k8s/
│   ├── base/                   # Deployment + Service
│   └── overlays/
│       ├── qa/                 # Namespace qa, nodeSelector, ExternalSecret
│       └── prod/               # Namespace prod, 2 réplicas, ExternalSecret
├── Dockerfile                  # Multi-stage Next.js standalone
├── .dockerignore
└── SETUP.md                    # ⬅️ LEE ESTO PRIMERO
```

## Cómo usar

1. **GitHub** → **Use this template** → Create a new repository
2. Reemplaza los tres placeholders en todos los archivos:

   | Placeholder | Valor |
   |---|---|
   | `APP_NAME` | Nombre de tu app en k8s (minúsculas, sin espacios) |
   | `CONTAINER_NAME` | Valor de `containers[0].name` en `deployment.yaml` |
   | `CT_ID` | ID del contenedor / VM donde corre k3s (si aplica, o elimina `pct exec`) |

   ```bash
   APP="mi-app"
   grep -r "APP_NAME\|CONTAINER_NAME\|CT_ID" --include="*.yaml" --include="*.yml" -l \
     | xargs sed -i "s/APP_NAME/$APP/g; s/CONTAINER_NAME/$APP/g; s/CT_ID/1/g"
   ```

3. Sigue **[SETUP.md](./SETUP.md)** antes de hacer cualquier `git push`.

## Por qué este template

Este template nació de implementar el pipeline en producción. Los errores documentados en `SETUP.md` son los típicos que no aparecen en la documentación oficial:

- **Imagen en GHCR con mayúsculas** → `InvalidImageName` en k8s
- **Token sin scope `packages`** → `403 Forbidden` en image pull, aunque el secret exista
- **Nombre del container incorrecto** → error críptico que no menciona la causa real
- **Variable bash no expandida dentro de subshell anidado** → `kubectl set image` recibe el nombre literal de la variable

Cada uno está explicado con síntoma, causa y solución en `SETUP.md`.

## Requisitos previos

- k3s operativo (o cualquier distribución de Kubernetes)
- [ExternalSecrets Operator](https://external-secrets.io) instalado
- `ClusterSecretStore` apuntando a Vault configurado
- Nodos con labels `environment=qa` / `environment=prod`
- HashiCorp Vault accesible desde el cluster
