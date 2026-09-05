# get-quarkdown

Scripts to install [Quarkdown](https://github.com/iamgio/quarkdown)
with automatic dependency management.

Along with Quarkdown itself, the scripts install [`chrome-headless-shell`](https://googlechromelabs.github.io/chrome-for-testing/),
a lightweight headless browser required for PDF export, at the version pinned by the Quarkdown release.

## Linux / macOS

To run with the default options:

```shell
curl -fsSL https://raw.githubusercontent.com/quarkdown-labs/get-quarkdown/refs/heads/main/install.sh | sudo env "PATH=$PATH" bash
```

To add options, append `-s -- <options>`:

```shell
curl ... | sudo env "PATH=$PATH" bash -s -- --tag v1.12.0
```

> Make sure you run with sudo privileges, as the script needs to create files in system directories.

## Windows

To run with the default options:

```powershell
irm https://raw.githubusercontent.com/quarkdown-labs/get-quarkdown/refs/heads/main/install.ps1 | iex
```

To run with options:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/quarkdown-labs/get-quarkdown/refs/heads/main/install.ps1))) -Tag v1.12.0
```

## Options

> The following options are formatted as: *`*nix` / `Windows`* 

### `--prefix <path>` / `-Prefix <path>`

Specify a custom installation directory.

**Default:** `/opt/quarkdown` (Linux/macOS), `%LOCALAPPDATA%\Quarkdown` (Windows)

### `--tag <version>` / `-Tag <version>`

Install a specific version of Quarkdown instead of the latest stable release.

- `vX.Y.Z` for specific versions (e.g., `v1.0.0`).
- `latest` for the latest **devbuild** release from the latest commit (possibly unstable).
