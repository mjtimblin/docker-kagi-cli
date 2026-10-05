# docker-kagi-cli

A container image for [kagi-cli](https://github.com/Microck/kagi-cli) that runs
as a [Model Context Protocol](https://modelcontextprotocol.io/) (MCP) server
over stdio.

This build is **session-token-only**. MCP tools that require a Kagi API key
(`KAGI_API_KEY`) or the legacy API token (`KAGI_API_TOKEN`) are removed from the
tool catalog at build time, so MCP clients never discover them. See
[Session-token-only build](#session-token-only-build).

## Image

```
ghcr.io/mjtimblin/kagi-cli:latest
ghcr.io/mjtimblin/kagi-cli:<kagi-cli version>   # e.g. 0.20.1
```

## Build locally

```bash
docker build -t kagi-cli .
```

Pin a different upstream kagi-cli version:

```bash
docker build --build-arg KAGI_VERSION=0.20.1 -t kagi-cli .
```

The image `ENTRYPOINT` is `kagi`, so `docker run kagi-cli mcp` runs
`kagi mcp`.

## Configure the session token

The CLI reads credentials from `$HOME/.config/kagi-cli/config.toml` (override
the path with `KAGI_CONFIG`). For a session token:

```toml
[auth]
session_token = "YOUR_KAGI_SESSION_TOKEN"
```

A session link (`https://kagi.com/search?token=...`) is also accepted and
normalized by the CLI.

## Run as an MCP server

MCP uses stdio, so the container must run with `-i` (keep stdin open). Do **not**
add `-t`.

### Plain `docker run` (bind mount)

```bash
docker run --rm -i \
  -v "$HOME/.config/kagi-cli:/root/.config/kagi-cli:ro" \
  kagi-cli mcp
```

### Portable named volume

A bind mount cannot use one identical path on Windows and Linux. A Docker
**named volume** can, so it is the recommended form for a config shared across
platforms. Seed it once per machine:

```bash
# bash / zsh (Linux, macOS, WSL)
docker run --rm -i -v kagi-config:/root/.config/kagi-cli alpine \
  sh -c 'mkdir -p /root/.config/kagi-cli && cat > /root/.config/kagi-cli/config.toml' < kagi-config.toml
```

```powershell
# PowerShell (Windows)
Get-Content .\kagi-config.toml -Raw |
  docker run --rm -i -v kagi-config:/root/.config/kagi-cli alpine `
    sh -c 'mkdir -p /root/.config/kagi-cli && cat > /root/.config/kagi-cli/config.toml'
```

Then run:

```bash
docker run --rm -i \
  -v kagi-config:/root/.config/kagi-cli:ro \
  -v kagi-cache:/root/.cache/kagi-cli \
  kagi-cli mcp
```

The second volume persists search history and cached responses.

## OpenCode MCP config

Add a server under `mcp.servers`. Because the volume is a named volume, the
`command` below is identical on Windows and Linux.

```jsonc title="opencode.jsonc"
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "servers": {
      "kagi": {
        "type": "local",
        "command": [
          "docker", "run", "--rm", "-i",
          "-v", "kagi-config:/root/.config/kagi-cli:ro",
          "-v", "kagi-cache:/root/.cache/kagi-cli",
          "kagi-cli", "mcp"
        ]
      }
    }
  }
}
```

### Alternative: environment variable (no volume)

If you prefer not to seed a volume, pass the token through the environment.
`{env:...}` substitution is the only string expansion OpenCode performs
(`$HOME` and similar shell expressions are not expanded).

```jsonc title="opencode.jsonc"
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "servers": {
      "kagi": {
        "type": "local",
        "command": [
          "docker", "run", "--rm", "-i",
          "-e", "KAGI_SESSION_TOKEN",
          "kagi-cli", "mcp"
        ],
        "environment": {
          "KAGI_SESSION_TOKEN": "{env:KAGI_SESSION_TOKEN}"
        }
      }
    }
  }
}
```

Set `KAGI_SESSION_TOKEN` in the shell that launches OpenCode.

## Session-token-only build

`patches/session-token-only.patch` is applied to `src/main.rs` during the image
build. It filters the MCP tool catalog and trims the discovery instructions so
the following tools are neither listed nor callable:

| Tool | Required credential |
| --- | --- |
| `kagi_extract` | `KAGI_API_KEY` |
| `kagi_fastgpt` | `KAGI_API_TOKEN` |
| `kagi_enrich_web` | `KAGI_API_TOKEN` |
| `kagi_enrich_news` | `KAGI_API_TOKEN` |
| `kagi_summarize` | `KAGI_API_TOKEN` (default path) |

Calls to a removed tool are rejected with `Unknown tool`, because the call
validator uses the same filtered catalog.

> **Version pinning:** the patch is written against a specific kagi-cli release
> (currently `0.20.1`). It contains context lines from `src/main.rs`, so it may
> need to be regenerated when `KAGI_VERSION` changes. The publish workflow builds
> with the new version and will fail loudly at the `git apply` step if the patch
> no longer applies — that is the signal to update the patch.

## Publishing

`.github/workflows/publish-image.yml` publishes the image to GHCR when you push
an image tag yourself:

```bash
git tag v1.0.0
git push origin v1.0.0
```

- Triggers on tags matching `v*`.
- Pushes `ghcr.io/<owner>/kagi-cli:<git tag>` and `:latest`.
- Builds with the kagi-cli version pinned in the `Dockerfile` (`KAGI_VERSION`).

A manual dispatch can publish an arbitrary `image_tag` and optionally override
`KAGI_VERSION` for that one build.

The first push creates a GHCR package. Set its visibility (public/private) under
the repository's **Packages** settings if needed.
