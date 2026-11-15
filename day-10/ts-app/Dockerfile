# Multi-stage build (slides 226-228, 230).
#
# Stage 1 ("builder") has everything needed to compile: the full Node.js image and
# the TypeScript compiler. Stage 2 ("runtime") is a small Alpine-based image that
# receives only the compiled result. Nothing from stage 1 is kept except what
# COPY --from=builder takes.

FROM node:26 AS builder
WORKDIR /build
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
RUN npx tsc

FROM node:26-alpine AS runtime
WORKDIR /app
COPY package.json package-lock.json ./
# Only the production dependencies: no compiler, no type definitions.
RUN npm ci --omit=dev
COPY --from=builder /build/dist ./dist

EXPOSE 3000
USER node

# Docker runs this command regularly and records the result as the container's
# health: "starting", then "healthy", or "unhealthy" after the retries are used up
# (slide 230). The image has no curl, so Node.js makes the request itself.
HEALTHCHECK --interval=3s --timeout=3s --start-period=3s --retries=2 \
  CMD node -e "fetch('http://localhost:3000/health').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"

CMD ["node", "dist/server.js"]
