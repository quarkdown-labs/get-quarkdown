# get-quarkdown

Scripts to install [Quarkdown](https://github.com/iamgio/quarkdown)
with automatic dependency management.

## Linux / macOS

Supported package managers: apt, dnf, yum, pacman, zypper, brew.

To run with the default options:

```shell
curl -fsSL https://raw.githubusercontent.com/quarkdown-labs/get-quarkdown/refs/heads/main/install.sh | sudo env "PATH=$PATH" bash
```

To add options, append `-s -- <options>`:

```shell
curl ... | sudo env "PATH=$PATH" bash -s -- --tag v1.12.0
```

> Make sure you run with sudo privileges, as the script may need to install system packages and create files in system directories.

## Windows

Supported package managers: winget, choco, scoop.

To run with the default options:

```powershell
irm https://raw.githubusercontent.com/quarkdown-labs/get-quarkdown/refs/heads/main/install.ps1 | iex
```

To run with options:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/quarkdown-labs/get-quarkdown/refs/heads/main/install.ps1))) -Tag v1.12.0
```

## Options

> The following options are formatted as: *`*nix` / `Windows` * 

### `--prefix <path>` / `-Prefix <path>`

Specify a custom installation directory.

**Default:** `/opt/quarkdown` (Linux/macOS), `%LOCALAPPDATA%\Quarkdown` (Windows)

### `--tag <version>` / `-Tag <version>`

Install a specific version of Quarkdown instead of the latest stable release.

- `vX.Y.Z` for specific versions (e.g., `v1.0.0`).
- `latest` for the latest **devbuild** release from the latest commit (possibly unstable).

### `--no-pm` / `-NoPM`

Prevent the script from installing dependencies using an available package manager.

Use this if you want to manually install dependencies or already have them installed.

### `--puppeteer-prefix <path>` / `-PuppeteerPrefix <path>`

Use an existing Puppeteer installation instead of installing a new one.


The path should point to the directory containing `node_modules/puppeteer`,
such as `/usr/lib`.

If this option is not provided, Puppeteer will be installed locally to the Quarkdown installation directory.
