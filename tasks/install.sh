#!/bin/bash

# This is a the installation script for rebo for any UNIX flavoured OS.  This
# script will be executed only once for a clean installation.  It does verify
# that the installation director does not exist before proceeding and, if it 
# does, will call a rebo script to refresh the installation.
#
# Using it solely for a first time installation will ensure that the this script
# is kept clean, simple and concise.

print_error() {
    printf "\e[31mError:\e[0m %s\n" "$@"
    exit 1
}

print_info() {
    printf "\e[32mInfo:\e[0m %s\n" "$@"
}

print_warning() {
    printf "\e[33mWarning:\e[0m %s\n" "$@"
}

download_file() {
    local URL="https://raw.githubusercontent.com/graeme-lockley/rebo-lang/main/$1"
    local FILENAME="$2"

    print_info "Downloading $FILENAME"
    curl "$URL" -s -o "$FILENAME" || print_error "Unable to download $URL"
}

if [ "$#" -ne 1 ]; then
    print_error "Installation must be supplied with a single argument denoting the installation directory."
fi

INSTALL_DIR="$1"

if [ -d "$INSTALL_DIR" ]; then
    print_warning "Installation directory already exists.  Refreshing installation..."

    if [ ! -f "$INSTALL_DIR/rebo-refresh" ]; then
        print_error "Installation directory already exists but rebo-refresh script is missing."
    fi

    "$INSTALL_DIR/rebo-refresh" || exit 1
    exit 0
fi

print_info "Creating installation directory at $INSTALL_DIR"
mkdir -p "$INSTALL_DIR" || print_error "Failed to create installation directory."

cd "$INSTALL_DIR" || print_error "Failed to change to installation directory."

SYSTEM=$(uname -s | tr '[:upper:]' '[:lower:]')
MACHINE=$(uname -m | tr '[:upper:]' '[:lower:]')
REBO_URL="https://littlelanguages.blob.core.windows.net/rebo/${SYSTEM}-${MACHINE}"

mkdir ./bin || print_error "Failed to create ./bin directory."
mkdir ./bin/src || print_error "Failed to create ./bin/src directory."
mkdir ./lib || print_error "Failed to create ./lib directory."

print_info "Downloading rebo from $REBO_URL"
curl "$REBO_URL" -s -o ./bin/rebo || print_error "Failed to download rebo from $REBO_URL"
chmod u+x ./bin/rebo || print_error "Failed to make ./bin/rebo executable."

download_file "bin/prelude.rebo" "./bin/prelude.rebo"
download_file "bin/rebo-test" "./bin/rebo-test"
chmod u+x ./bin/rebo-test || print_error "Failed to make rebo-test executable."


download_file "bin/src/repl-util.rebo" "./bin/src/repl-util.rebo"
download_file "bin/src/test-markdown.rebo" "./bin/src/test-markdown.rebo"
download_file "bin/src/test-suite.rebo" "./bin/src/test-suite.rebo"

download_file "lib/cli.rebo" "./lib/cli.rebo"
download_file "lib/cli.test.rebo" "./lib/cli.test.rebo"
download_file "lib/fs.rebo" "./lib/fs.rebo"
download_file "lib/fs.test.rebo" "./lib/fs.test.rebo"
download_file "lib/http-client.rebo" "./lib/http-client.rebo"
download_file "lib/http.rebo" "./lib/http.rebo"
download_file "lib/http.test.rebo" "./lib/http.test.rebo"
download_file "lib/json.rebo" "./lib/json.rebo"
download_file "lib/json.test.rebo" "./lib/json.test.rebo"
download_file "lib/path.rebo" "./lib/path.rebo"
download_file "lib/path.test.rebo" "./lib/path.test.rebo"
download_file "lib/std.rebo" "./lib/std.rebo"
download_file "lib/std.test.rebo" "./lib/std.test.rebo"
download_file "lib/str.rebo" "./lib/str.rebo"
download_file "lib/str.test.rebo" "./lib/str.test.rebo"
download_file "lib/sys.rebo" "./lib/sys.rebo"
download_file "lib/t.rebo" "./lib/t.rebo"
download_file "lib/test.rebo" "./lib/test.rebo"

{
    cd ./bin || print_error "Failed to change to ./bin directory."
    echo "Please include the following into your PATH: $PWD"
}
