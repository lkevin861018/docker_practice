# Docker Lab v8 | HTTPS + external access

## What this upgrade does
- Adds Caddy in front of existing Nginx; Caddy handles HTTPS and automatic certificate renewals.
- Keeps the existing Flask, PostgreSQL, pgAdmin, Grafana, Prometheus and other services intact.
- Publishes only TCP 80 and 443, and protects **all** public endpoints with basic authentication.
- Does NOT export/migrate your Windows Docker volumes to an Ubuntu server. DB migration is a separate backup/restore step.

## Prerequisites
1. Existing v7 `compose.yaml` successfully starts db, app, nginx; verify `docker compose ps`.
2. Own a real domain or dynamic-DNS hostname (example `app.example.com`). Point DNS A to your public IPv4. Do not create a wrong AAAA record.
3. For hosting on Windows behind a home router: router WAN address must be publicly reachable. Forward TCP 80->Windows-LAN-IP:80 and TCP 443->Windows-LAN-IP:443. Carrier-grade NAT (CGNAT) may prevent this. Do not put the Windows host in the router DMZ.
4. Allow **only** necessary inbound TCP 80/443 in Windows Defender Firewall. Keep admin ports loopback-only.
5. Back up PostgreSQL and verify that the backup is restorable before making deployment changes.

## Install (Windows PowerShell)
From project root, after extracting upgrade ZIP *into* project root:

```powershell
Copy-Item .\caddy\Caddyfile.example .\caddy\Caddyfile
notepad .env
```
Append `SITE_DOMAIN=app.your-real-domain.tld` to `.env`. This is not a URL; do not include `https://` or a slash.

Generate a hashed Basic Auth password **interactively** (avoid placing the plaintext password on the command line or in shell history):

```powershell
docker run --rm -it caddy:2.11.7-alpine caddy hash-password
```

Enter and confirm a strong unique password. Copy the resulting bcrypt string, replace `REPLACE_WITH_BCRYPT_HASH` in `caddy/Caddyfile`. Basic auth login will be `labuser` unless you edit that username. Never commit `caddy/Caddyfile` with the hash; merge `gitignore-v8.snippet` into existing `.gitignore`.

Validate and start Caddy:

```powershell
docker compose -f compose.yaml -f compose.public.yaml config --quiet
docker compose -f compose.yaml -f compose.public.yaml up -d --no-deps --force-recreate caddy
docker compose -f compose.yaml -f compose.public.yaml ps caddy
docker compose -f compose.yaml -f compose.public.yaml logs --tail=100 caddy
```

`--no-deps` assumes Nginx and Flask are already healthy. If not, start base services first with `docker compose up -d`.

Validate config in running Caddy:

```powershell
docker compose -f compose.yaml -f compose.public.yaml exec caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
```

Test from **mobile data, not only the same Wi-Fi**:

```powershell
curl.exe -I https://app.your-real-domain.tld
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\https-check.ps1
```

A response of `HTTP/2 401` is **expected before authentication** because Caddy requires login. `https://app.your-real-domain.tld` in a web browser prompts for `labuser` and your password; `/api/visits` remains protected.

Caddy automatically redirects HTTP to HTTPS if it obtains a valid certificate; DNS/80/443 must be reachable for normal ACME validation.

## Windows Firewall (admin PowerShell, after verifying network configuration)

```powershell
New-NetFirewallRule -DisplayName 'Docker Lab HTTPS TCP 443' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 443
New-NetFirewallRule -DisplayName 'Docker Lab HTTP ACME TCP 80' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 80
```

Add rules only if needed; avoid duplicate rules; check local Windows/Docker Desktop firewall behavior. For home LAN host assign a reserved LAN IP in the router. Avoid opening ports 5050, 3000, 9090, 9093, 8025, 5432 or 8000.

## Ubuntu Server / VPS

1. Provision Ubuntu, install Docker Engine and Docker Compose Plugin from Docker's official repository.
2. Configure DNS A record of the hostname to your VPS public IP.
3. Allow inbound only TCP 80 and TCP 443 (plus restricted SSH) at the VPS provider firewall and host firewall; do **not** publish admin ports.
4. Transfer the project with `.env`/secrets provisioned **on the server**, not committed to Git. Prefer image-pulled app deployments; ensure `db-setup` was run successfully for the data being hosted.
5. Create the Caddyfile and generate a unique password hash on the server, then start with the same two Compose files.
6. For existing Windows PostgreSQL data: perform a verified pg_dump/pg_restore migration to a fresh Ubuntu database first. Copying only Compose files does not migrate Docker volumes. Do not run `docker compose down -v`.
7. If using the v7 GitHub Actions CD flow, continue app-only deploy via `compose.deploy.yaml`; apply the public gateway separately, and always specify the intended Compose file combinations to avoid accidentally removing or reconfiguring public services.

## Troubleshooting
- **404**: Caddy routes to Nginx but URL is not in Flask; check Nginx and Flask logs.
- **502**: Caddy cannot reach Nginx; check `docker compose ps nginx app` and frontend network.
- **401**: expected Basic Auth challenge; verify hash and use the correct username/password.
- **Certificate error**: check DNS A/AAAA, open 80/443, router forwarding, ISP CGNAT, router loopback/NAT hairpin, logs and Caddy data volume.
- **Ports occupied**: run `Get-NetTCPConnection -LocalPort 80,443 -State Listen -ErrorAction SilentlyContinue` and check IIS/other reverse proxies.
- **Missing Caddyfile**: create by copying `caddy/Caddyfile.example`; do not commit actual password hash.
- **Caddy cert renewal**: persist `caddy_data`, do not delete with `docker compose down -v`.

## Security limitations
The legacy Flask app has no application-level RBAC, rate limit, CSRF design, or privacy policy. Basic Auth is an access gate for a *small trusted test audience*, not a substitute for production app authentication or authorization. The `/api/visits` service can disclose and accept entries once authenticated. Avoid publishing sensitive datasets or a shared demo password. For public production use, add application authentication, permissions, audit logs, and abuse controls before removing Basic Auth.

## Stop public entrypoint safely

```powershell
docker compose -f compose.yaml -f compose.public.yaml stop caddy
```

This stops only public HTTPS entrypoint; Flask/PostgreSQL and other services remain running.

Official documentation: https://caddyserver.com/docs/automatic-https , https://caddyserver.com/docs/caddyfile/directives/basic_auth , https://docs.docker.com/compose/how-tos/multiple-compose-files/merge/
