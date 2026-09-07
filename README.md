# Hermes Agent — Pterodactyl Egg

This repository packages [Nous Research Hermes Agent](https://github.com/NousResearch/hermes-agent)
for current Pterodactyl Panel and Wings releases. The egg uses a thin compatibility image; Hermes
itself still comes from the upstream `nousresearch/hermes-agent:latest` image.

## Install

1. In **Admin Panel → Nests**, import [`egg-hermes-agent.json`](./egg-hermes-agent.json).
2. Create a server from the **Hermes Agent** egg. A practical minimum is 2 GB RAM, 2 CPU threads,
   and 5 GB disk; 4 GB RAM is recommended when using browser or media tools.
3. Set one model-provider credential. The defaults expect an `OPENROUTER_API_KEY`.
4. Optionally set a Telegram or Discord bot token and its matching allowed-user IDs.
5. Start the server.

The dashboard listens on the primary allocation. When `Dashboard password` is blank, the first
start generates one in `/home/container/.dashboard-password`; open it from the Pterodactyl file
manager and sign in as `admin`. Set your own password in the egg variable if preferred.

Hermes writes `config.yaml`, memory, sessions, skills, and all other mutable state under
`/home/container`, so Pterodactyl backups include them. The model variables only initialize a new
`config.yaml`; after that, edit the model through the dashboard or the config file.

## Optional OpenAI-compatible API

Set `API_SERVER_ENABLED=true` and add a server allocation matching `API_SERVER_PORT` (default
`8642`). If `API_SERVER_KEY` is blank, the first start generates one in
`/home/container/.api-server-key`. When external access is disabled, the same API stays available
only on container loopback because the dashboard uses it as an authenticated gateway control plane.
Do not expose it publicly without a strong key and a narrow CORS allowlist.

## Image updates

[`publish-image.yml`](./.github/workflows/publish-image.yml) publishes
`ghcr.io/apple050620312/hermespterodactyl:latest` for AMD64 and ARM64 on changes and every Monday.
Reinstalling the server is not necessary: pull/recreate the server container from Panel after a new
image is published. Persistent data remains in `/home/container`.

The GHCR package must be **Public** so Wings can pull it anonymously. GitHub creates a package as
private on its first publication; change its visibility once under the package's settings.

## Notes and limitations

- Pterodactyl runs containers as the Wings host UID/GID and with a read-only root filesystem. The
  compatibility image therefore runs Hermes directly as that non-root user instead of using the
  root-only s6 bootstrap from the upstream image.
- Gateway crash recovery is handled by Pterodactyl's server restart policy. Hermes is launched with
  `--no-supervise --external-supervisor` so there is only one lifecycle owner.
- Do not enable "allow all users" on an Internet-facing bot. Authorized Hermes users can invoke
  powerful tools and should be treated as server operators.
