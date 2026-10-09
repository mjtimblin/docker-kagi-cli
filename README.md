# docker-kagi-cli

A container image for [kagi-cli](https://github.com/Microck/kagi-cli) that runs
as a [Model Context Protocol](https://modelcontextprotocol.io/) (MCP) server
over stdio (default) or Streamable HTTP.

The image ships kagi-cli's full MCP tool catalog. If you authenticate with a
session token, the tools that require a Kagi API key (`KAGI_API_KEY`) or the
legacy API token (`KAGI_API_TOKEN`) cannot work; hide them at runtime with
`--exclude-tools` or `KAGI_MCP_TOOLS`. See
[Choosing which tools to expose](#choosing-which-tools-to-expose).

## Image

```
ghcr.io/mjtimblin/kagi-cli:latest
ghcr.io/mjtimblin/kagi-cli:<kagi-cli version>   # e.g. 0.22.0
```

## Build locally

```bash
docker build -t kagi-cli .
```

Pin a different upstream kagi-cli version:

```bash
docker build --build-arg KAGI_VERSION=0.22.0 -t kagi-cli .
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

## Run as an HTTP MCP server

Pass `--transport http` to serve the MCP Streamable HTTP transport instead of
stdio, and choose the bind address with `--host` (default `127.0.0.1`) and the
port with `--port` (default `8080`):

```bash
docker run --rm \
  -p 127.0.0.1:8080:8080 \
  -v kagi-config:/root/.config/kagi-cli:ro \
  -v kagi-cache:/root/.cache/kagi-cli \
  kagi-cli mcp --transport http --host 0.0.0.0 --port 8080
```

MCP clients send requests to `http://<host>:<port>/mcp`. Any path is accepted;
`/mcp` is the conventional endpoint. Inside the container the server must bind
`0.0.0.0` (not the default `127.0.0.1`) for the published port to be reachable
from the host.

The HTTP transport has no authentication of its own and is stateless, so more
than one client can share one instance. Only publish the port on a trusted
interface; `-p 127.0.0.1:8080:8080` keeps it on the local host.

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

To apply a tool filter, append `--exclude-tools ...` (or `--tools ...`) to the
`command` array. See [Choosing which tools to expose](#choosing-which-tools-to-expose).

### Remote (HTTP transport)

Start the container in HTTP mode as shown in
[Run as an HTTP MCP server](#run-as-an-http-mcp-server), then point OpenCode at
its URL. No volume is referenced from OpenCode itself:

```jsonc title="opencode.jsonc"
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "servers": {
      "kagi": {
        "type": "remote",
        "url": "http://127.0.0.1:8080/mcp"
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

## Choosing which tools to expose

kagi-cli [0.22.0](https://github.com/Microck/kagi-cli/releases/tag/v0.22.0)
filters the MCP tool catalog at startup, so this image no longer patches the
source to hide tools. Pass `--exclude-tools` to drop tools, `--tools` to
allowlist them, or set `KAGI_MCP_TOOLS` to an environment allowlist. Hidden tools
are also rejected when called, not just omitted from `tools/list`.

### Session-token-only

If you authenticate with a session token, exclude the tools that need a Kagi API
key or the legacy API token:

| Tool | Required credential |
| --- | --- |
| `kagi_extract` | `KAGI_API_KEY` |
| `kagi_fastgpt` | `KAGI_API_TOKEN` |
| `kagi_enrich_web` | `KAGI_API_TOKEN` |
| `kagi_enrich_news` | `KAGI_API_TOKEN` |
| `kagi_summarize` | `KAGI_API_TOKEN` (default path) |

Pass them to `kagi mcp`:

```bash
docker run --rm -i \
  -v kagi-config:/root/.config/kagi-cli:ro \
  kagi-cli mcp \
  --exclude-tools kagi_extract,kagi_fastgpt,kagi_enrich_web,kagi_enrich_news,kagi_summarize
```

Or set `KAGI_MCP_TOOLS` to the tools you *do* want, which is useful when passing
arguments is awkward. For example, expose a core read-only catalog:

```bash
docker run --rm -i -e KAGI_MCP_TOOLS \
  -v kagi-config:/root/.config/kagi-cli:ro \
  kagi-cli mcp
```

```bash
KAGI_MCP_TOOLS=kagi_search,kagi_batch_search,kagi_quick kagi-cli mcp
```

`--tools` and `--exclude-tools` cannot be combined; either flag overrides
`KAGI_MCP_TOOLS`. Names are case-sensitive, surrounding whitespace is trimmed,
and duplicates are ignored. Unknown or empty names abort startup. Mutating tools
still require `--enable-mutating-tools`; an allowlist alone does not enable them.

> **Tool names can change between kagi-cli releases.** Run `kagi mcp` and call
> `tools/list`, or check the upstream
> [MCP docs](https://github.com/Microck/kagi-cli/blob/main/docs/content/docs/commands/mcp.mdx),
> to confirm the names for your pinned `KAGI_VERSION`.

## HTTP transport build

`patches/mcp-http-transport.patch` adds the `--transport`, `--host`, and `--port`
flags to `kagi mcp`. It factors the per-message JSON-RPC handling out of the
stdio loop (`mcp_handle_request`) so both transports share it, and serves the
Streamable HTTP transport with `axum`. See
[Run as an HTTP MCP server](#run-as-an-http-mcp-server).

> **Version pinning:** the patch is written against a specific kagi-cli release
> (currently `0.22.0`). It contains context lines from the upstream sources, so
> it may need to be regenerated when `KAGI_VERSION` changes. The publish workflow
> builds with the new version and will fail loudly at the `git apply` step if the
> patch no longer applies — that is the signal to update the patch.

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
