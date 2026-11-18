# soreal: painless Xray (VLESS + TLS) in Docker!
[![Build](https://git.quacker.org/d/soreal/badges/workflows/build.yml/badge.svg?branch=master&label=build)](https://git.quacker.org/d/soreal/actions)

## What is soreal?
`soreal` offers easy 5-minute setups and braindead configurations for Xray using vless + xtls-vision.

## Features
- A clean, simple deployment built using official [Xray](https://github.com/XTLS/Xray-core) and [Caddy](https://github.com/caddyserver/caddy) for automatic certificate management.
- An optional container for filtering upstream requestrs. The example `docker-compose.yml` includes a container that blocks CN traffic and ADs using [HaGeZi](https://github.com/hagezi/dns-blocklists) Pro(++), TIF and Spam TLDs.
- An optional decoy site served by a separate container using [reputable sources](https://github.com/torvalds/linux).
- Automatic QR code and link generation in the container log and to a directory.
- Automatic weekly builds.

## Quickstart
1. You can start with the example `docker-compose.yml` from this repo.
2. Adjust environment variables:
    - `HOST`: the hostname of the server. `REQUIRED`.
    - `PORT`: the port Xray listens on, for QR code and shared link generation. Any port works except `80` (Caddy/ACME) and `12345/12346` (internal fallback sites) are reserved inside the container. Port `80` must always be identity mapped for certificate generation. When this variable is changed, `Optional, default = 443`.
    - `SITE_URL`: address of the decoy site backend, e.g. `decoy:3000`. When unset, all non-proxied requests receive a `404` response. `Optional, default = ""`.
    - `UPSTREAM_URL`: upstream socks5 proxy address the proxy chain forwards to, e.g. `filter:1080`. Supports both UDP and TCP. When unset, requests are dialed directly. `Optional, default = ""`.
    - `USERX`: an arbitrary number of user ids starting from X=0, see the `docker-compose.yml` for examples. `REQUIRED: at least one user.`.
    - `LOG_LEVEL`: the verbosity of Xray logging, one of `debug`, `info`, `warning`, `error` and `none`. `Optional, default = warning`.
    - `CADDY_LOG_LEVEL`: the verbosity of Caddy's access logs. `Optional, default = info`.
    - `SELF_SIGN`: whether to generate self signed certificates. `Optional, default = false`.
3. `docker compose up -d`
4. Check the container log using `docker logs` for per-user shareable links and QR codes.
5. Visit your server in the browser to see your decoy site, and test your proxy connections. User QR codes and shareable links can be found in the console and in `/opt/soreal/data/users`.

## Docker volume
Bind mount a local folder to `/opt/soreal/data` to persist settings and certificates across container reboots.

## How to update?
- `docker compose pull`
- `docker compose up -d`

## Notes
- It may take a while to generate the certificates when running for the first time. Check `docker logs` for more details: Xray only starts after Caddy has obtained the certificate.
- QUIC/H3 is not available as Xray owns the `PORT` (TCP).

## Troubleshooting
- Use `docker logs` to debug Caddy startup failures (certificate issuance, port 80 reachability) and the logs of the `filter` and `decoy` containers for their own. Xray logs to `/opt/soreal/data/xray`. Caddy logs to `/opt/soreal/data/caddy`.
- If you have trouble visiting certain sites and are sure the client is configured correctly, try relaxing `BLOCK_ADS` on the `filter` container. Disabling `BLOCK_CN` is not recommended as it might leak the VPS's IP.
