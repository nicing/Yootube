#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
destination="${1:-$project_dir/.build/runtime-cache/prepared}"
cache_dir="$project_dir/.build/runtime-cache"
downloads_dir="$cache_dir/downloads"
prepared_dir="$cache_dir/prepared"

invidious_commit="049d591d294e2a43cb32b97a0bb018c2093e5beb"
crystal_version="1.21.0"
postgres_version="18.6.0"
openssl_version="3.6.3"
runtime_version="invidious=$invidious_commit crystal=$crystal_version postgres=$postgres_version openssl=$openssl_version companion=release-master"

crystal_archive="$downloads_dir/crystal.tar.gz"
postgres_archive="$downloads_dir/postgres.tar.gz"
companion_archive="$downloads_dir/companion.tar.gz"
companion_license="$downloads_dir/companion-license.txt"
openssl_archive="$downloads_dir/openssl.tar.gz"

mkdir -p "$downloads_dir"

download() {
    local url="$1"
    local expected_sha="$2"
    local output="$3"

    if [ ! -f "$output" ]; then
        curl --fail --location --retry 3 --output "$output" "$url"
    fi

    local actual_sha
    actual_sha="$(shasum -a 256 "$output" | awk '{print $1}')"
    if [ "$actual_sha" != "$expected_sha" ]; then
        echo "Checksum mismatch for $output" >&2
        exit 1
    fi
}

if [ ! -f "$prepared_dir/runtime-version.txt" ] || [ "$(cat "$prepared_dir/runtime-version.txt")" != "$runtime_version" ]; then
    if [ "$(uname -m)" != "arm64" ]; then
        echo "The bundled runtime currently targets Apple Silicon (arm64)." >&2
        exit 1
    fi

    download \
        "https://github.com/crystal-lang/crystal/releases/download/$crystal_version/crystal-$crystal_version-1-darwin-universal.tar.gz" \
        "7fc4af56b0cb5c7ea5703f744c6629bb19ff36ba3abbf232d50e40c39a20ee16" \
        "$crystal_archive"
    download \
        "https://github.com/theseus-rs/postgresql-binaries/releases/download/$postgres_version/postgresql-$postgres_version-aarch64-apple-darwin.tar.gz" \
        "a257bcdb8aa3301a13d6a5bcec48f8c9517045b7cbae71e50788b2615539e95b" \
        "$postgres_archive"
    download \
        "https://github.com/iv-org/invidious-companion/releases/download/release-master/invidious_companion-aarch64-apple-darwin.tar.gz" \
        "7e5c8cdd6c850cbeb182a3ad0830cc530f9c1902916a6008e2355817a2e1dd48" \
        "$companion_archive"
    download \
        "https://raw.githubusercontent.com/iv-org/invidious-companion/master/LICENSE" \
        "d8de517917a591daa447d6be28ffb2fac866703e4feb65e86221be9a22d3033a" \
        "$companion_license"
    download \
        "https://github.com/openssl/openssl/releases/download/openssl-$openssl_version/openssl-$openssl_version.tar.gz" \
        "243a86649cf6f23eeb6a2ff2456e09e5d77dd9018a54d3d96b0c6bdd6ba6c7f1" \
        "$openssl_archive"

    work_dir="$(mktemp -d /tmp/yootube-runtime.XXXXXX)"
    trap 'rm -rf "$work_dir"' EXIT

    mkdir -p "$work_dir/crystal" "$work_dir/postgres" "$work_dir/companion" "$work_dir/openssl-source"
    tar -xzf "$crystal_archive" -C "$work_dir/crystal" --strip-components=1
    tar -xzf "$postgres_archive" -C "$work_dir/postgres" --strip-components=1
    tar -xzf "$companion_archive" -C "$work_dir/companion"
    tar -xzf "$openssl_archive" -C "$work_dir/openssl-source" --strip-components=1

    openssl_root="$work_dir/openssl"
    cd "$work_dir/openssl-source"
    ./Configure darwin64-arm64-cc \
        --prefix="$openssl_root" \
        --openssldir="$openssl_root/ssl" \
        no-apps
    make -j"$(sysctl -n hw.logicalcpu)"
    make install_sw

    git clone https://github.com/iv-org/invidious.git "$work_dir/invidious"
    git -C "$work_dir/invidious" checkout --detach "$invidious_commit"

    mkdir -p "$work_dir/tools" "$work_dir/crystal-cache"
    cat > "$work_dir/tools/pkg-config" <<'PKGCONFIG'
#!/usr/bin/env bash
set -euo pipefail
arguments="$*"
if [[ "$arguments" == *"--modversion"* ]]; then
    if [[ "$arguments" == *"libssl"* || "$arguments" == *"libcrypto"* ]]; then
        echo "3.6.3"
        exit 0
    fi
    exit 1
fi
if [[ "$arguments" == *"--libs"* ]]; then
    if [[ "$arguments" == *"libssl"* ]]; then
        echo "-L${YOOTUBE_OPENSSL_ROOT}/lib -lssl -lcrypto"
        exit 0
    fi
    if [[ "$arguments" == *"libcrypto"* ]]; then
        echo "-L${YOOTUBE_OPENSSL_ROOT}/lib -lcrypto"
        exit 0
    fi
    exit 1
fi
if [[ "$arguments" == *"--cflags"* ]]; then
    if [[ "$arguments" == *"libssl"* || "$arguments" == *"libcrypto"* ]]; then
        echo "-I${YOOTUBE_OPENSSL_ROOT}/include"
        exit 0
    fi
    exit 1
fi
exit 1
PKGCONFIG
    cat > "$work_dir/tools/sha1sum" <<'SHA1SUM'
#!/usr/bin/env bash
exec shasum -a 1 "$@"
SHA1SUM
    chmod +x "$work_dir/tools/pkg-config" "$work_dir/tools/sha1sum"

    crystal_root="$work_dir/crystal"
    export YOOTUBE_OPENSSL_ROOT="$openssl_root"
    export PATH="$work_dir/tools:$crystal_root/bin:$crystal_root/embedded/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    export CRYSTAL_CACHE_DIR="$work_dir/crystal-cache"
    export LIBRARY_PATH="$openssl_root/lib"

    cd "$work_dir/invidious"
    "$crystal_root/embedded/bin/shards" install --production
    "$crystal_root/bin/crystal" run scripts/fetch-player-dependencies.cr -- --minified
    "$crystal_root/bin/crystal" build src/invidious.cr \
        --release \
        -Dskip_videojs_download \
        --warnings all \
        --link-flags "-L$openssl_root/lib -lxml2 -llzma"

    next_prepared="$cache_dir/prepared-next"
    rm -rf "$next_prepared"
    mkdir -p \
        "$next_prepared/invidious" \
        "$next_prepared/companion" \
        "$next_prepared/openssl" \
        "$next_prepared/licenses"

    cp -R "$work_dir/postgres" "$next_prepared/postgres"
    cp "$work_dir/invidious/invidious" "$next_prepared/invidious/invidious"
    cp -R "$work_dir/invidious/assets" "$next_prepared/invidious/assets"
    cp -R "$work_dir/invidious/locales" "$next_prepared/invidious/locales"
    mkdir -p "$next_prepared/invidious/config"
    cp -R "$work_dir/invidious/config/sql" "$next_prepared/invidious/config/sql"
    cp "$work_dir/companion/invidious_companion" "$next_prepared/companion/invidious_companion"
    cp "$openssl_root/lib/libssl.3.dylib" "$next_prepared/openssl/libssl.3.dylib"
    cp "$openssl_root/lib/libcrypto.3.dylib" "$next_prepared/openssl/libcrypto.3.dylib"
    cp "$work_dir/invidious/LICENSE" "$next_prepared/licenses/Invidious-AGPL-3.0.txt"
    cp "$companion_license" "$next_prepared/licenses/Invidious-Companion-AGPL-3.0.txt"
    cp "$work_dir/postgres/LICENSE" "$next_prepared/licenses/PostgreSQL.txt"
    cp "$work_dir/openssl-source/LICENSE.txt" "$next_prepared/licenses/OpenSSL-Apache-2.0.txt"
    cp "$project_dir/THIRD_PARTY_NOTICES.md" "$next_prepared/licenses/THIRD_PARTY_NOTICES.md"

    install_name_tool \
        -change "$openssl_root/lib/libssl.3.dylib" \
        '@loader_path/../openssl/libssl.3.dylib' \
        "$next_prepared/invidious/invidious"
    install_name_tool \
        -change "$openssl_root/lib/libcrypto.3.dylib" \
        '@loader_path/../openssl/libcrypto.3.dylib' \
        "$next_prepared/invidious/invidious"
    install_name_tool -id '@loader_path/libcrypto.3.dylib' "$next_prepared/openssl/libcrypto.3.dylib"
    install_name_tool -id '@loader_path/libssl.3.dylib' "$next_prepared/openssl/libssl.3.dylib"
    install_name_tool \
        -change "$openssl_root/lib/libcrypto.3.dylib" \
        '@loader_path/libcrypto.3.dylib' \
        "$next_prepared/openssl/libssl.3.dylib"

    chmod +x "$next_prepared/invidious/invidious" "$next_prepared/companion/invidious_companion"
    codesign --force --sign - "$next_prepared/openssl/libcrypto.3.dylib"
    codesign --force --sign - "$next_prepared/openssl/libssl.3.dylib"
    codesign --force --sign - "$next_prepared/invidious/invidious"
    codesign --force --sign - "$next_prepared/companion/invidious_companion"
    printf '%s\n' "$runtime_version" > "$next_prepared/runtime-version.txt"

    rm -rf "$prepared_dir"
    mv "$next_prepared" "$prepared_dir"
fi

rm -rf "$destination"
mkdir -p "$destination"
ditto "$prepared_dir" "$destination"
