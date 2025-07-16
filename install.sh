#!/bin/bash

set -e

INSTALL_DIR="/opt/quarkdown"
USE_PM=true

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

# Install Puppeteer
npm install puppeteer --prefix "$INSTALL_DIR/lib" > /dev/null
npx puppeteer browsers install chrome-headless-shell

# Ensure unzip is available
if ! command -v unzip &>/dev/null; then
  echo "Error: unzip is required but not installed."
  exit 1
fi

echo "Installing Quarkdown to $INSTALL_DIR..."
echo ""

TMP_DIR="$(mktemp -d)"
curl -L "https://github.com/iamgio/quarkdown/releases/latest/download/quarkdown.zip" -o "$TMP_DIR/quarkdown.zip"
unzip "$TMP_DIR/quarkdown.zip" -d "$TMP_DIR" > /dev/null

mkdir -p "$INSTALL_DIR"
cp -r "$TMP_DIR/quarkdown/"* "$INSTALL_DIR"

WRAPPER_PATH="/usr/local/bin/quarkdown"
cat <<EOF > "$WRAPPER_PATH"
#!/bin/bash
export JAVA_HOME="\$(dirname "\$(dirname "\$(readlink -f "\$(which java)")")")"
export PATH="$INSTALL_DIR/bin:\$PATH"
export QD_NPM_PREFIX="$INSTALL_DIR/lib"
exec "$INSTALL_DIR/bin/quarkdown" "\$@"
EOF

chmod +x "$WRAPPER_PATH"

rm -rf "$TMP_DIR"

echo "Quarkdown is now installed!"
echo ""
echo "To uninstall, remove $INSTALL_DIR and $WRAPPER_PATH"