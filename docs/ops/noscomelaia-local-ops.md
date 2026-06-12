# Nos Come La IA Local Ops

This project can operate Nos Come La IA infrastructure, but only through the Nos Come La IA Dokploy organization.

## MCP

Project MCP config:

```text
.mcp.json
```

The `dokploy-noscomelaia` server points to:

```text
/Users/pablomunizmunoz/.local/bin/run-dokploy-mcp-noscomelaia.sh
```

Shared non-secret config lives in:

```text
/Users/pablomunizmunoz/.config/noscomelaia/env
```

That wrapper sources the shared config, loads the Nos Come La IA Dokploy token from the existing local `cuentos-infantiles/.env.local` setup, and exports it as `DOKPLOY_API_KEY` for the Dokploy MCP process.

To resync project MCP files from the shared convention:

```bash
noscomelaia-sync-mcps
```

Do not paste Dokploy, IONOS, Cloudflare, R2, or restic secrets into repo files.

## Sure Production Access

Sure production is not in the old/default Dokploy organization. It lives in the
Nos Come La IA Dokploy organization:

- Public URL: `https://sure.noscomelaia.com`
- Dokploy panel: `https://dok.inteliatech.ai`
- Organization: `noscomelaia`
- Project: `Personal pablo`
- Server: `hetzner-personal` / `46.224.186.242`
- Compose app name: `sure-w61dhd`
- Compose id: `i8YB9x5Paq4sqV1fCG9cw`
- Current container prefix: `sure-w61dhd-*`

The persistent Docker volumes intentionally keep the old `sure-vwdate_*` names
and are referenced as external volumes by the compose stack.

### Dokploy MCP Pitfall

If `project_all` only lists Intelia/default-org projects and does not show
`Personal pablo` / compose id `i8YB9x5Paq4sqV1fCG9cw`, the active Dokploy MCP is
the wrong profile for Sure.

For Sure/cuentos/ghost, use the project MCP config in `.mcp.json`, which points
to:

```text
/Users/pablomunizmunoz/.local/bin/run-dokploy-mcp-noscomelaia.sh
```

That wrapper loads the Nos Come La IA Dokploy token as
`DOKPLOY_API_KEY_NOSCOMELAIA` and exports it as `DOKPLOY_API_KEY` for the
Dokploy MCP process. The older/default `DOKPLOY_API_KEY` is for Intelia work and
must not be assumed to have access to Sure.

If a session does not see the Nos Come La IA project, run:

```bash
noscomelaia-sync-mcps
```

Then restart/reload the agent session so it picks up `.mcp.json`.

### Sure Dokploy Deployment Path

The currently installed `@ahdev/dokploy-mcp` package can read projects and
domains, but it does not expose Docker Compose tools. Sure is deployed as a
Dokploy `compose` service, not as a Dokploy `application`, so application tools
such as `application-deploy` are not the right deployment path.

For Sure deployments, use the Nos Come La IA Dokploy API profile directly when
compose operations are needed. The relevant endpoints are:

- `GET /api/compose.one?composeId=i8YB9x5Paq4sqV1fCG9cw`
- `POST /api/compose.update`
- `POST /api/compose.deploy`
- `POST /api/compose.redeploy`

When updating the raw compose file, preserve the existing YAML and change only
the intended image references. At the time this note was written, the `web` and
`worker` services used:

```text
ghcr.io/we-promise/sure:stable
```

### Sure MCP Access

For financial queries, prefer the Sure MCP tools when they are available in the
agent session. In Codex, load them with a targeted tool search such as:

```text
sure transactions income statement expenses mcp
```

The useful tools are:

- `mcp__sure.get_income_statement`
- `mcp__sure.get_transactions`
- `mcp__sure.get_accounts`
- `mcp__sure.get_balance_sheet`

Do not use local `SURE_MCP_TOKEN` as the `/mcp` bearer token. Sure's Rails MCP
endpoint authenticates with production env vars:

- `MCP_API_TOKEN`
- `MCP_USER_EMAIL`

Those are server/Dokploy env values. They should be read through the proper
Nos Come La IA Dokploy profile when needed, not pasted into repo files.

Example weekly expense query via the Sure MCP:

```json
{
  "start_date": "2026-06-08",
  "end_date": "2026-06-14"
}
```

For shell-level production checks, SSH to the server and detect the current
container name instead of hardcoding stale prefixes:

```bash
ssh root@46.224.186.242 'docker ps --format "{{.Names}}" | grep "^sure-.*-web-1$"'
```

## Local Helpers

Available local commands:

```bash
noscomelaia-with-ionos <command>
noscomelaia-export-ionos-dns [zone] [output-dir]
noscomelaia-with-r2 <command>
noscomelaia-env <command>
noscomelaia-cf <command>
noscomelaia-store-cf-token
```

Secrets for IONOS and R2 are stored in the macOS Keychain under account `noscomelaia`.

Cloudflare profile note: the account id is configured, but account-level Cloudflare operations require a dedicated API token in Keychain service `noscomelaia-cloudflare-api-token`. Store it with `noscomelaia-store-cf-token`. The `noscomelaia-cf` wrapper intentionally refuses to use the global `cf` login when that token is missing.

## Server Backup

Ghost backups run on `piensa-vps` through:

```text
/usr/local/sbin/noscomelaia-backup
/etc/systemd/system/noscomelaia-backup.timer
```

The restic repository is in Cloudflare R2 bucket `crm-backups`, prefix `noscomelaia/restic`.

Useful checks:

```bash
ssh piensa-vps 'systemctl status noscomelaia-backup.timer --no-pager'
ssh piensa-vps 'sudo systemctl status noscomelaia-backup.service --no-pager -l'
```

## Cloudflare Token Status

`noscomelaia-cf` is configured and verified for the Nos Come La IA Cloudflare account.

Verified:

- Account listing works.
- Account token verification works.
- R2 bucket listing works.

Limits:

- `noscomelaia.com` is not currently present as a Cloudflare DNS zone.
- The token cannot list/update Cloudflare account tokens. Permission changes must be done from the Cloudflare dashboard unless a separate token-management token is created.
