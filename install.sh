#!/bin/bash

set -e

INSTALL_DIR="/opt/quarkdown"
USE_PM=true
PUPPETEER_PATH=""
TAG=""

# Parse options
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      INSTALL_DIR="$2"
      shift 2
      ;;
    --no-pm)
      USE_PM=false
      shift
      ;;
    --puppeteer-prefix)
      PUPPETEER_PATH="$2"
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

# Detect package manager
detect_package_manager() {
  if command -v apt >/dev/null; then
    echo "apt"
  elif command -v dnf >/dev/null; then
    echo "dnf"
  elif command -v yum >/dev/null; then
    echo "yum"
  elif command -v pacman >/dev/null; then
    echo "pacman"
  elif command -v zypper >/dev/null; then
    echo "zypper"
  elif command -v brew >/dev/null; then
    echo "brew"
  else
    echo ""
  fi
}

# Install dependencies using the detected package manager
install_with_pm() {
  local pm="$1"
  local package="$2"

  echo ""
  echo "Installing $package using $pm..."

  case "$pm" in
    apt)
      sudo apt update
      sudo apt install -y "$package"
      ;;
    dnf)
      sudo dnf install -y "$package"
      ;;
    yum)
      sudo yum install -y "$package"
      ;;
    pacman)
      sudo pacman -Sy --noconfirm "$package"
      ;;
    zypper)
      sudo zypper install -y "$package"
      ;;
    brew)
      brew install "$package"
      ;;
    *)
      echo "Unsupported package manager: $pm"
      exit 1
      ;;
  esac
}

# Check Java
if ! command -v java &>/dev/null; then
  echo "Java not found."

  if $USE_PM; then
    PM=$(detect_package_manager)
    if [[ -z "$PM" ]]; then
      echo "No supported package manager found. Skipping automatic install."
      USE_PM=false
    else
      case "$PM" in
        apt) install_with_pm "$PM" openjdk-17-jdk ;;
        dnf|yum|zypper) install_with_pm "$PM" java-17-openjdk ;;
        pacman) install_with_pm "$PM" jdk17-openjdk ;;
        brew) install_with_pm "$PM" openjdk@17 ;;
      esac
    fi
  fi

  if ! command -v java &>/dev/null; then
    echo "Error: Java is still not installed. Please install JDK 17 manually."
    exit 1
  fi
fi

# Check Node.js
if ! command -v node &>/dev/null; then
  echo "Node.js not found."

  if $USE_PM; then
    PM=$(detect_package_manager)
    if [[ -z "$PM" ]]; then
      echo "No supported package manager found. Skipping automatic install."
      USE_PM=false
    else
      install_with_pm "$PM" nodejs
    fi
  fi

  if ! command -v node &>/dev/null; then
    echo "Error: Node.js is still not installed. Please install Node.js manually."
    exit 1
  fi
fi

# Check npm
if ! command -v npm &>/dev/null; then
  echo "npm not found."

  if $USE_PM; then
    PM=$(detect_package_manager)
    if [[ -z "$PM" ]]; then
      echo "No supported package manager found. Skipping automatic install."
      USE_PM=false
    else
      if [[ "$PM" == "brew" || "$PM" == "pacman" ]]; then
        # Usually nodejs includes npm here
        echo "npm comes with Node.js for $PM"
      else
        install_with_pm "$PM" npm
      fi
    fi
  fi

  if ! command -v npm &>/dev/null; then
    echo "Error: npm is still not installed. Please install npm manually."
    exit 1
  fi
fi

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

if [[ -z "$TAG" ]]; then
  DOWNLOAD_URL="https://github.com/iamgio/quarkdown/releases/latest/download/quarkdown.zip"
else
  DOWNLOAD_URL="https://github.com/iamgio/quarkdown/releases/download/$TAG/quarkdown.zip"
fi

curl -fL --show-error "$DOWNLOAD_URL" -o "$TMP_DIR/quarkdown.zip"
unzip "$TMP_DIR/quarkdown.zip" -d "$TMP_DIR" > /dev/null

QD_NPM_PREFIX="$INSTALL_DIR/lib"

# Check if puppeteer path is provided via --puppeteer-prefix
if [[ -n "$PUPPETEER_PATH" ]] && [[ -d "$PUPPETEER_PATH/node_modules/puppeteer" ]]; then
  QD_NPM_PREFIX="$PUPPETEER_PATH"
  export PUPPETEER_CACHE_DIR="$HOME/.cache/puppeteer"
else
  # Install Puppeteer into the staging directory
  export PUPPETEER_CACHE_DIR="$TMP_DIR/quarkdown/lib/puppeteer_cache"
  mkdir -p "$PUPPETEER_CACHE_DIR"
  npm init -y --prefix "$TMP_DIR/quarkdown/lib" > /dev/null
  npm install puppeteer --prefix "$TMP_DIR/quarkdown/lib" --no-audit --no-fund --loglevel=error > /dev/null
  export PUPPETEER_CACHE_DIR="$INSTALL_DIR/lib/puppeteer_cache"
fi

# Stage the extracted payload in the target volume for a fast final move.
mkdir -p "$INSTALL_PARENT"
mv "$TMP_DIR/quarkdown" "$STAGE_DIR"

# Move previous installation out of the way only after download and Puppeteer install succeed.
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

JAVA_HOME_RESOLVED="$(java -XshowSettings:property -version 2>&1 | grep 'java.home' | sed 's/.*= //')"

WRAPPER_PATH="/usr/local/bin/quarkdown"
cat <<EOF > "$WRAPPER_PATH"
#!/bin/bash
export JAVA_HOME="$JAVA_HOME_RESOLVED"
if [ ! -d "\$JAVA_HOME" ]; then
  export JAVA_HOME="\$(java -XshowSettings:property -version 2>&1 | grep 'java.home' | sed 's/.*= //')"
fi
export PATH="$INSTALL_DIR/bin:\$PATH"
export QD_NPM_PREFIX="$QD_NPM_PREFIX"
export PUPPETEER_CACHE_DIR="$PUPPETEER_CACHE_DIR"
exec "$INSTALL_DIR/bin/quarkdown" "\$@"
EOF

chmod +x "$WRAPPER_PATH"

echo "Quarkdown is now installed!"
echo ""
echo "To uninstall, remove $INSTALL_DIR and $WRAPPER_PATH"
