#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/apply-kernel-prod-env.sh [bundle_dir] [target_dir]

Defaults:
  bundle_dir = parent directory of this script inside the extracted artifact
  target_dir = /mnt/data/kernel-prod-env

Environment overrides:
  KERNEL_GO_VERSION     Go version archive to install, default: 1.25.8
  KERNEL_ENV_TARGET     Same as target_dir when the second argument is omitted
  KERNEL_PLATFORM       linux-amd64 only for this shell script
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
default_bundle_dir="$(cd "$script_dir/.." && pwd)"
bundle_dir="${1:-$default_bundle_dir}"
target_dir="${2:-${KERNEL_ENV_TARGET:-/mnt/data/kernel-prod-env}}"
go_version="${KERNEL_GO_VERSION:-1.25.8}"
platform="${KERNEL_PLATFORM:-linux-amd64}"

if [[ "$platform" != "linux-amd64" ]]; then
  echo "apply-kernel-prod-env.sh currently supports linux-amd64; use apply-kernel-prod-env.ps1 for Windows." >&2
  exit 2
fi

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "missing required artifact file: $path" >&2
    exit 1
  fi
}

require_file "$bundle_dir/go/go${go_version}.linux-amd64.tar.gz"
require_file "$bundle_dir/tools-linux-amd64.tgz"
require_file "$bundle_dir/goproxy-cache.tgz"
require_file "$bundle_dir/buf-cache.tgz"

mkdir -p "$target_dir/go/$go_version" "$target_dir/tools" "$target_dir/goproxy" "$target_dir/buf-cache" "$target_dir/gomod-cache" "$target_dir/gobuild-cache"

tar -xzf "$bundle_dir/go/go${go_version}.linux-amd64.tar.gz" -C "$target_dir/go/$go_version" --strip-components=1
tar -xzf "$bundle_dir/tools-linux-amd64.tgz" -C "$target_dir/tools"
tar -xzf "$bundle_dir/goproxy-cache.tgz" -C "$target_dir/goproxy"
tar -xzf "$bundle_dir/buf-cache.tgz" -C "$target_dir/buf-cache"

if [[ -f "$bundle_dir/gomod-cache.tgz" ]]; then
  tar -xzf "$bundle_dir/gomod-cache.tgz" -C "$target_dir/gomod-cache"
fi
if [[ -f "$bundle_dir/gobuild-cache.tgz" ]]; then
  tar -xzf "$bundle_dir/gobuild-cache.tgz" -C "$target_dir/gobuild-cache" || true
fi

cat > "$target_dir/env.sh" <<EOF
# Source this file before building Kernel offline:
#   source "$target_dir/env.sh"
export KERNEL_PROD_ENV="$target_dir"
export GOROOT="$target_dir/go/$go_version"
export GOMODCACHE="$target_dir/gomod-cache"
export GOCACHE="$target_dir/gobuild-cache"
export GOPROXY="file://$target_dir/goproxy,off"
export GOSUMDB=off
export GOTOOLCHAIN=local
export BUF_CACHE_DIR="$target_dir/buf-cache"
export PATH="$target_dir/tools/bin:$target_dir/tools/protoc/bin:$target_dir/go/$go_version/bin:\$PATH"
EOF

cat > "$target_dir/verify.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"
echo "== versions =="
go version
protoc --version
buf --version
kernel version 2>/dev/null || true
echo "== env =="
go env GOROOT GOMODCACHE GOCACHE GOPROXY GOSUMDB GOTOOLCHAIN
EOF
chmod +x "$target_dir/verify.sh"

echo "installed Kernel production environment into: $target_dir"
echo "next: source '$target_dir/env.sh'"
echo "verify: '$target_dir/verify.sh'"
