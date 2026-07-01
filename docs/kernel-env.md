# Kernel env

Use `.github/workflows/build-kernel-prod-env.yml` as the maintained entry for Kernel offline development bundles.

## What the action prepares

- Go offline archives for Linux amd64 and Windows amd64.
- `protoc` and `buf` archives and installed Linux/Windows tool directories.
- Kernel command and protobuf generator binaries.
- Upstream protobuf generator binaries.
- Go module download cache as a local file-proxy cache.
- Full Go module cache and Go build cache.
- Buf remote module cache.
- Kernel source snapshot.
- Build reports and SHA256 checksums.

## Current Kernel tag

The current root module tag verified during maintenance is:

```text
v0.1.16
```

Use it in the workflow input:

```text
kernel_ref = v0.1.16
```

The Kernel root `go.mod` currently requires:

```text
go 1.25.8
```

## Local Linux install

```bash
bash scripts/apply-kernel-prod-env.sh "$PWD" /mnt/data/kernel-prod-env
source /mnt/data/kernel-prod-env/env.sh
/mnt/data/kernel-prod-env/verify.sh
```

## Build Kernel from the artifact

```bash
mkdir -p /mnt/data/kernel-src
tar -xzf kernel-source.tgz -C /mnt/data/kernel-src
cd /mnt/data/kernel-src
go mod download
make tools
make proto
make test-root
```
