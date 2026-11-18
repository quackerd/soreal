# soreal: painless XRay (VLESS + TLS) in Docker!
[![Build](https://git.quacker.org/d/soreal/badges/workflows/build.yml/badge.svg?branch=master&label=build)](https://git.quacker.org/d/soreal/actions)

## What(who) is soreal?
`soreal` is the Xray frontend of a small set of Docker containers that offers easy 5-minute setups and braindead configurations for [Xray-core](https://github.com/XTLS/Xray-core) with VLESS over TCP, TLS and the [XTLS Vision](https://xtls.github.io/document/level-2/xtls.html) flow. It terminates TLS using a certificate managed by Caddy, serves the proxy, and forwards everything else to a decoy site and an upstream filtering proxy.

## How it works
- [Caddy](https://github.com/caddyserver/caddy) (installed from apk) handles certificate management: it serves the ACME HTTP-01 challenges on port `80` (redirecting to the public port) and runs an **internal** plain-HTTP `12345` listener speaking HTTP/1.1 and cleartext HTTP/2 (h2c), where it reverse-proxies to the decoy site (`SITE_URL`) or returns `404`.
- [Xray](https://github.com/XTLS/Xray-core) listens on `443` with VLESS + Vision + TLS and loads the certificate Caddy generated: VLESS clients are served in-place, and all other traffic (browsers, probes) is forwarded to Caddy's `12345` site via Xray's fallback mechanism.
- Xray is launched only after Caddy has obtained the certificate and the `12345` fallback site is listening.
- Both processes run supervised under [s6-overlay](https://github.com/just-containers/s6-overlay): a one-shot `init` service renders the configs, then Caddy and Xray start as supervised longruns and are restarted if they ever exit.

## Features
- A clean, simple deployment built using Xray-core (VLESS + `xtls-rprx-vision` + TLS) with Caddy for automatic certificate management.
- Blocks CN traffic and ADs using [HaGeZi](https://github.com/hagezi/dns-blocklists) Pro(++), TIF and Spam TLDs, via the bundled `filter` container.
- Uses [Cloudflare](https://one.one.one.one) DNS over HTTPS (RFC 8484, HTTP/2 with a Chrome uTLS fingerprint) for Xray's upstream name resolution. Both IPv4 and IPv6 resolvers are configured; queries are sent over TLS to the resolvers' IPs (no plaintext DNS leaves the container) and follow the same outbound as regular traffic, so they are filtered too.
- An optional decoy site served by a separate container using [reputable sources](https://github.com/torvalds/linux).
- Automatic QR code and link generation for popular APPs, printed to the container log.
- Automatic weekly builds.

## Quickstart
1. You can start with the example `docker-compose.yml` from this repo.
2. Adjust environment variables:
    - `HOST`: the hostname of the server. `REQUIRED`.
    - `PORT`: the port Xray listens on, for QR code and shared link generation. Any port works, but `80` (Caddy/ACME) and `12345` (internal fallback site) are reserved inside the container: picking one makes Xray fail to bind at startup and the container exits. The compose file maps the host port identity-mapped from this variable. Port `80` must always be identity mapped for certificate generation. Xray listens on `::`, so both IPv4 and IPv6 are served. `Optional, default = 443`.
    - `SITE_URL`: address of the decoy site backend, e.g. `decoy:3000`. When unset, all non-proxied requests receive a `404` response. `Optional, default = ""`.
    - `UPSTREAM_URL`: upstream socks5 proxy address the proxy chain forwards to, e.g. `filter:1080`. TCP and UDP traffic is both carried (Xray's socks outbound implements UDP ASSOCIATE, and domain names are forwarded unresolved for the upstream to resolve). When unset, requests are dialed directly. Malformed values produce a broken Xray config that fails at startup. `Optional, default = ""`.
    - `USERX`: an arbitrary number of user ids starting from X=0, see the `docker-compose.yml` for examples. `REQUIRED: at least one user.`. Each id is the VLESS credential (Xray maps it to an internal UUID), so use long, unguessable strings; ids must be under 30 bytes and must not contain `@`.
    - `LOG_LEVEL`: the verbosity of Xray logging, one of `debug`, `info`, `warning`, `error` and `none` (Xray's native levels). Anything else is passed through and makes Xray fail at startup. `Optional, default = warning`.
    - `CADDY_LOG_LEVEL`: the verbosity of the access logs of the `80` redirect site and the internal `12345` fallback site, one of Caddy's `debug`, `info`, `warn` and `error`. Both sites append to the same `data/caddy/access.log`. It does not affect Caddy's own system logs (certificate issuance/renewal, errors), which always log at `info` to the container log. `Optional, default = info`.
    - `SELF_SIGN`: have Caddy issue the certificate for `HOST` from its internal CA instead of ACME (auto-renewed like the ACME one). Only the literal `true` and `false` are recognized. Clients must then skip certificate verification (the generated links include `insecure=1`). `Optional, default = false`.
3. `docker compose up -d`
4. Check the container log using `docker logs` for per-user shareable links and QR codes; the same `vless://` link works with [v2rayN](https://github.com/2dust/v2rayn), [shadowrocket](https://shadowlaunch.com/) and other VLESS clients. The links carry the SNI and `xtls-rprx-vision` flow settings; ALPN is left at the clients' defaults (`h2`, `http/1.1`).
5. Visit your server in the browser to see your decoy site (or a `404` if `SITE_URL` is unset), and test your VLESS + TLS connections.

## Docker volume
Bind mount a local folder to `/opt/soreal/data` to persist settings and certificates across container reboots. Make sure the local folder is owned by or accessible to uid 1000 and gid 1000.

soreal stores Caddy's data and certificates under `caddy`, and Xray's `error.log` and `access.log` under `xray`. Caddy's own access logs (for the `80` redirect and the internal `12345` fallback site) go to `caddy/access.log`; its system log stays on the container's stdout. The certificate Xray serves is whichever Caddy issued: under `caddy/certificates/local` when `SELF_SIGN` is enabled, or under `caddy/certificates/acme-v02.api.letsencrypt.org-directory` otherwise. Xray watches the certificate file it loads, so renewals hot-reload without a restart.

It also writes per-user `link.txt` and `qrcode.png` files under `/opt/init/users`, which is outside the persisted volume. The same links and QR codes are printed to the container log on every start.

## How to update?
- `docker compose down`
- `docker compose pull`
- `docker compose up -d`

## Notes
- It may take a while to generate the certificates when running for the first time. Follow `docker logs` for more details: Xray only launches after Caddy has obtained the certificate and the `12345` fallback site is up.
- Caddy's `12345` fallback listener is internal to the container (plain HTTP) and must not be exposed.
- HTTP/3 is not available in this setup: Xray owns the `PORT` (TCP) and the fallback site runs on the internal `12345`.

## Troubleshooting
- Use `docker logs` to debug Caddy startup failures (certificate issuance, port 80 reachability) and the logs of the `filter` and `decoy` containers for their own. Xray logs to `data/xray/error.log` (verbosity set by `LOG_LEVEL`) and `data/xray/access.log`; Caddy's access logs are in `data/caddy/access.log` (verbosity set by `CADDY_LOG_LEVEL`).
- If name resolution fails, check `data/xray/error.log`: DNS upstreams are DoH endpoints at `1.1.1.1`, `1.0.0.1` and the two Cloudflare IPv6 addresses, tried in that order. The IPv4 entries are tried first, so a broken IPv6 path is harmless; all four being unreachable means the container has no egress (or, when `UPSTREAM_URL` is set, the upstream filter blocks them). At `LOG_LEVEL: info` each created resolver logs as `DNS: created DOH client for ...`.
- If Xray never launches, Caddy has not obtained a certificate: check that port `80` is identity-mapped and reachable, and that `HOST` points to your server. The ACME issuer is pinned to Let's Encrypt (`cert_issuer acme`), so Caddy's ZeroSSL fallback is intentionally disabled to keep the certificate path deterministic.
- Note on Reality: [Reality](https://xtls.github.io/document/level-2/reality.html) trades your own certificate for one borrowed from a target site, which helps when the domain itself is blocked or fingerprinted. Since this setup already holds valid certificates for `HOST` and falls back to a decoy site, plain TLS + Vision provides equivalent active-probing resistance with fully legitimate TLS.
- If you receive a warning about `"failed to sufficiently increase receive buffer size"`, you can simply ignore the warning. Otherwise follow the instructions [here](https://github.com/quic-go/quic-go/wiki/UDP-Buffer-Sizes). Note that these options must be set on *HOST*. You can use `/etc/sysctl.conf` to persist the settings across reboots.
- If you have trouble visiting certain sites and are sure the client is configured correctly, try relaxing `BLOCK_ADS` on the `filter` container. Disabling `BLOCK_CN` is not recommended as it might leak VPS's IPs.
