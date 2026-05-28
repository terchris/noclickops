# Lovable Vite/PWA → nginx static serve.
# Rendered by `noclickops sync-lovable` (PLAN-006) — DO NOT edit per-service;
# changes here propagate via `noclickops update` then `noclickops sync-lovable`.
#
# Build context expectations (set up by sync-lovable, on every run):
#   package.json, package-lock.json   - lockfile-pinned npm install in the build stage
#   .env                              - Vite reads VITE_* at build time and bakes them
#                                       into the bundle; must be present in the context
#                                       (no .dockerignore that excludes it)
#   nginx.conf                        - copied from templates/lovable/
#   health.json                       - generated per sync; carries source repo + commit
#   src/, public/, index.html, ...    - the Lovable app

FROM node:20-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY health.json /usr/share/nginx/html/health.json
EXPOSE 3000
