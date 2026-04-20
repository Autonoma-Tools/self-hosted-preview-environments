# syntax=docker/dockerfile:1.6
#
# Multi-stage Dockerfile for a Next.js app using the standalone output mode.
#
# Requires `output: 'standalone'` in next.config.js. With that set, Next.js
# emits a self-contained server under .next/standalone that bundles only the
# runtime dependencies actually used, so the final image stays small.

# ---------- deps ----------
FROM node:20-alpine AS deps
WORKDIR /app

# Install system packages that some Node native modules need during install.
RUN apk add --no-cache libc6-compat

COPY package.json package-lock.json* ./
RUN npm ci

# ---------- builder ----------
FROM node:20-alpine AS builder
WORKDIR /app

ENV NEXT_TELEMETRY_DISABLED=1

COPY --from=deps /app/node_modules ./node_modules
COPY . .

RUN npm run build

# ---------- runner ----------
FROM node:20-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000
ENV HOSTNAME=0.0.0.0

# Non-root runtime user for a smaller blast radius.
RUN addgroup --system --gid 1001 nodejs \
 && adduser  --system --uid 1001 nextjs

# Public assets and the standalone server bundle.
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs

EXPOSE 3000

# The standalone output generates a server.js at the image root.
CMD ["node", "server.js"]
