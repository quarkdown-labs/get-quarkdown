#!/bin/bash

set -e

INSTALL_DIR="/opt/quarkdown"
TAG=""

# Parse options
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      INSTALL_DIR="$2"
      shift 2
      ;;
    --tag)
      TAG="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Ensure unzip is available
if ! command -v unzip &>/dev/null; then
  echo "Error: unzip is required but not installed."
  exit 1
fi

echo "Installing Quarkdown to $INSTALL_DIR..."
echo ""

# Download and extract to a temp directory before touching the existing installation
TMP_DIR="$(mktemp -d)"
INSTALL_PARENT="$(dirname "$INSTALL_DIR")"
INSTALL_NONCE="$(date +%s)-$$-$RANDOM"
STAGE_DIR="$INSTALL_PARENT/.quarkdown-new-$INSTALL_NONCE"
BACKUP_DIR="$INSTALL_PARENT/.quarkdown-old-$INSTALL_NONCE"
ROLLBACK_CANDIDATE=false
NEW_INSTALL_PLACED=false

# Ensure temporary artifacts are cleaned and restore the previous install on failure.
cleanup_install_artifacts() {
  local cleanup_exit=$?
  set +e

  if [[ $cleanup_exit -ne 0 ]] && [[ "$ROLLBACK_CANDIDATE" == "true" ]] && [[ -d "$BACKUP_DIR" ]]; then
    if [[ -d "$INSTALL_DIR" ]]; then
      rm -rf "$INSTALL_DIR" || echo "Warning: failed to remove incomplete installation at $INSTALL_DIR"
    fi

    if mv "$BACKUP_DIR" "$INSTALL_DIR"; then
      echo "Restored previous installation at $INSTALL_DIR after failure."
    else
      echo "Warning: failed to restore previous installation from $BACKUP_DIR"
    fi
  elif [[ $cleanup_exit -ne 0 ]] && [[ "$NEW_INSTALL_PLACED" == "true" ]] && [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR" || echo "Warning: failed to remove incomplete installation at $INSTALL_DIR"
  elif [[ $cleanup_exit -eq 0 ]] && [[ -d "$BACKUP_DIR" ]]; then
    rm -rf "$BACKUP_DIR" || echo "Warning: failed to remove previous installation backup $BACKUP_DIR"
  fi

  if [[ -d "$STAGE_DIR" ]]; then
    rm -rf "$STAGE_DIR" || echo "Warning: failed to remove staging directory $STAGE_DIR"
  fi

  if [[ -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR" || echo "Warning: failed to remove temporary directory $TMP_DIR"
  fi

  return $cleanup_exit
}
trap cleanup_install_artifacts EXIT

# Detect target platform for the per-platform release zip.
case "$(uname -s)" in
  Linux)  OS="linux" ;;
  Darwin) OS="macos" ;;
  *)      echo "Error: unsupported operating system: $(uname -s)"; exit 1 ;;
esac

case "$(uname -m)" in
  x86_64|amd64)    ARCH="x64" ;;
  aarch64|arm64)   ARCH="aarch64" ;;
  *)               echo "Error: unsupported architecture: $(uname -m)"; exit 1 ;;
esac

# Linux on ARM is not part of the published release set yet.
if [[ "$OS" == "linux" && "$ARCH" == "aarch64" ]]; then
  echo "Error: linux-aarch64 is not currently published. Use an x64 host or install Quarkdown manually."
  exit 1
fi

ZIP_NAME="quarkdown-$OS-$ARCH.zip"

if [[ -z "$TAG" ]]; then
  DOWNLOAD_URL="https://github.com/iamgio/quarkdown/releases/latest/download/$ZIP_NAME"
else
  DOWNLOAD_URL="https://github.com/iamgio/quarkdown/releases/download/$TAG/$ZIP_NAME"
fi

curl -fL --show-error "$DOWNLOAD_URL" -o "$TMP_DIR/$ZIP_NAME"
unzip "$TMP_DIR/$ZIP_NAME" -d "$TMP_DIR" > /dev/null

# Install chrome-headless-shell, required for PDF export, into the staging directory
# via the browser installer script shipped with the distribution.
CHROME_INSTALL_SCRIPT="$TMP_DIR/quarkdown/scripts/install-chrome.sh"
if [[ -f "$CHROME_INSTALL_SCRIPT" ]]; then
  STAGED_CHROME_PATH="$(bash "$CHROME_INSTALL_SCRIPT" "$TMP_DIR/quarkdown/lib")"
  # The printed path points into the staging directory: remap it to the final installation directory.
  QD_CHROME_PATH="$INSTALL_DIR/lib/${STAGED_CHROME_PATH#"$TMP_DIR/quarkdown/lib/"}"
else
  echo "Warning: this Quarkdown release does not ship a browser installer. PDF export may require a manual browser setup."
  QD_CHROME_PATH=""
fi

# Stage the extracted payload in the target volume for a fast final move.
mkdir -p "$INSTALL_PARENT"
mv "$TMP_DIR/quarkdown" "$STAGE_DIR"

# Move previous installation out of the way only after the downloads succeed.
if [[ -d "$INSTALL_DIR" ]]; then
  if [[ ! -x "$INSTALL_DIR/bin/quarkdown" ]]; then
    echo "Error: $INSTALL_DIR exists but does not contain a Quarkdown installation. Aborting."
    exit 1
  fi
  echo "Staging previous installation from $INSTALL_DIR..."
  mv "$INSTALL_DIR" "$BACKUP_DIR"
  ROLLBACK_CANDIDATE=true
fi

mv "$STAGE_DIR" "$INSTALL_DIR"
NEW_INSTALL_PLACED=true

CHROME_EXPORT=""
if [[ -n "$QD_CHROME_PATH" ]]; then
  CHROME_EXPORT="export QD_CHROME_PATH=\"$QD_CHROME_PATH\""
fi

WRAPPER_PATH="/usr/local/bin/quarkdown"
cat <<EOF > "$WRAPPER_PATH"
#!/bin/bash
export PATH="$INSTALL_DIR/bin:\$PATH"
$CHROME_EXPORT
exec "$INSTALL_DIR/bin/quarkdown" "\$@"
EOF

chmod +x "$WRAPPER_PATH"

echo "Quarkdown is now installed!"
echo ""
echo "To uninstall, remove $INSTALL_DIR and $WRAPPER_PATH"
