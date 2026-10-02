# Workflows

## Deploy to Dev

Open a PR into `dev` and [`deploy-dev.yaml`](deploy-dev.yaml) deploys the image
tags pinned in that commit's `.env.versions` to the Dev host (checkout → `compose pull` →
`compose up -d`).
Only released tags belong in `.env.versions`.

- After adding a variable to the host's `.env` by hand, or to roll back to an earlier commit,
  run the workflow via `workflow_dispatch`.
- Changes to `templates/nginx/`, a service port, or `JWT_SECRET` still need
  `sudo ./bootstrap.sh -r` on the host.
- Never `git clean` or `git checkout -f` the deploy directory. `.env` and `certs/` are untracked.
- Do not rename or move the deploy directory; the compose project name comes from it.
- A deploy that fails at `compose pull` leaves the host on that commit; deploy a good commit
  before running compose by hand.
