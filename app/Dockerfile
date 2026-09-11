# Multi-stage. The old image was node:8.9.4 -- end of life since December 2019 --
# running `npm install express` with no package.json, no lock file, and as root.
#
# Build stage: install from the lock file so the image is reproducible.
FROM node:22-alpine AS deps

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Runtime stage: no npm, no build toolchain, no shell history from the install.
FROM node:22-alpine

# dumb-init reaps zombies and forwards signals, so SIGTERM actually reaches
# node rather than being swallowed by PID 1.
RUN apk add --no-cache dumb-init

ENV NODE_ENV=production
WORKDIR /app

COPY --from=deps --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node package.json hello.js ./

# The node:alpine images ship an unprivileged `node` user. The old image ran
# everything as root.
USER node

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://127.0.0.1:8080/healthz',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "hello.js"]
