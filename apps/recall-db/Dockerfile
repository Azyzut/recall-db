# Recall Tracker — database migration Job.
#
# Build from the REPO ROOT, not this directory:
#   docker build -f apps/recall-db/Dockerfile -t recall-db .
#
# The root context is required because npm workspaces resolve from the root
# package.json and lockfile.
#
# No build step: migrate.ts runs directly under Node's native type stripping.
# That is why the tsconfigs set erasableSyntaxOnly — anything Node cannot strip
# fails here at runtime rather than at compile time.

FROM node:24-alpine

WORKDIR /app
ENV NODE_ENV=production

# Install only this workspace's dependencies. --include-workspace-root brings in
# the root manifest so npm can resolve the workspace graph; --omit=dev skips
# TypeScript, which is not needed when nothing is compiled.
COPY --chown=node:node package.json package-lock.json ./
COPY --chown=node:node apps/recall-db/package.json ./apps/recall-db/
RUN npm ci --workspace @recall/db --include-workspace-root --omit=dev

COPY --chown=node:node apps/recall-db ./apps/recall-db

# Run as the unprivileged user the base image already provides.
USER node

# Exits 0 on success, 1 on failure, so Kubernetes can tell whether the Job
# succeeded. Idempotent: re-running against an up-to-date database is a no-op.
CMD ["node", "apps/recall-db/src/migrate.ts"]
