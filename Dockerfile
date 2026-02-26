# ────────────────────────────────────────────────
# Stage 1: Instalar dependencias
# ────────────────────────────────────────────────
FROM node:20-alpine AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci

# ────────────────────────────────────────────────
# Stage 2: Build
# ────────────────────────────────────────────────
FROM node:20-alpine AS builder
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# ⚠️ Para Next.js: output: "standalone" DEBE estar en next.config.ts
#    Sin eso, el contenedor arrancará pero no encontrará server.js
RUN npm run build

# ────────────────────────────────────────────────
# Stage 3: Runner (imagen mínima de producción)
# ────────────────────────────────────────────────
FROM node:20-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

# Usuario no-root para seguridad
RUN addgroup --system --gid 1001 nodejs && \
    adduser  --system --uid 1001 appuser

# Copiar solo los artefactos del build standalone
COPY --from=builder --chown=appuser:nodejs /app/.next/standalone ./
COPY --from=builder --chown=appuser:nodejs /app/.next/static ./.next/static
COPY --from=builder --chown=appuser:nodejs /app/public ./public

USER appuser

EXPOSE 3000

# server.js es generado por output: "standalone"
CMD ["node", "server.js"]
