# recall-db

Database schema and migration runner. Runs as a Kubernetes Job before every other component.

One of five components of the Product Recall Tracker. Start at the
[hands-on lab](../recall-tracker-hands-on-lab) rather than here.

## Layout

```
apps/recall-db/     this component
packages/shared/   code shared with the other components, vendored
.cloudbees/        build and deploy workflows
```

The workspace layout is preserved from the monorepo this was generated from, so
the Dockerfile builds with the repo root as context and the Helm chart lives at
`apps/recall-db/chart`.

## Local use

```
npm install
npm run typecheck
```

Running the full application needs all the components together — see the lab.

## Configuration

Set values as variables and secrets in the CloudBees Unify UI, not in files.
Run the **Verify Setup** workflow in the Application repo to check them.
