#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Default installation directory
INSTALL_DIR="/opt/quarkdown"

# Optional arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      # If the --prefix flag is provided, use the next argument as the install dir
      INSTALL_DIR="$2"
      shift 2 # Move past both --prefix and its value
      ;;
    *)
      # Unknown option provided
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Check if Java is installed
if ! command -v java &> /dev/null; then
  echo "Error: Java is not installed. Please install Java 17 or higher."
  exit 1
fi

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
  echo "Error: Node.js is not installed. Please install Node.js."
  exit 1
fi

# Check if npm is installed
if ! command -v npm &> /dev/null; then
  echo "Error: npm is not installed. Please install npm."
  exit 1
fi

# Ensure unzip is available
if ! command -v unzip &> /dev/null; then
  echo "Error: unzip is required but not installed."
  exit 1
fi

# Download and extract the latest release zip from GitHub
echo "Installing Quarkdown to $INSTALL_DIR. To change the installation directory, use --prefix <path>."
echo ""

TMP_DIR="$(mktemp -d)"
curl -L "https://github.com/iamgio/quarkdown/releases/latest/download/quarkdown.zip" -o "$TMP_DIR/quarkdown.zip"

unzip "$TMP_DIR/quarkdown.zip" -d "$TMP_DIR" > /dev/null

# Create the install directory if it doesn't exist
mkdir -p "$INSTALL_DIR"

# Move all extracted files to the install directory
cp -r "$TMP_DIR/quarkdown/"* "$INSTALL_DIR"

# Install Puppeteer without bundling a browser
export PUPPETEER_CHROME_SKIP_DOWNLOAD=true
npm install puppeteer --prefix "$INSTALL_DIR/lib" > /dev/null

# Create wrapper script in /usr/local/bin for CLI access
WRAPPER_PATH="/usr/local/bin/quarkdown"
cat <<EOF > "$WRAPPER_PATH"
#!/bin/bash
export JAVA_HOME="\$(dirname "\$(dirname "\$(readlink -f "\$(which java)")")")"
export PATH="$INSTALL_DIR/bin:\$PATH"
export QD_NPM_PREFIX="$INSTALL_DIR/lib"
exec "$INSTALL_DIR/bin/quarkdown" "\$@"
EOF

chmod +x "$WRAPPER_PATH"

# Clean up temporary files
rm -rf "$TMP_DIR"

echo "Quarkdown has been successfully installed!"
echo "Note: make sure a suitable installation of Chrome, Chromium or Firefox is available for PDF generation."
echo ""
echo "To uninstall Quarkdown, remove $INSTALL_DIR and $WRAPPER_PATH"