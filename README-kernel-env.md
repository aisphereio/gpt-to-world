# Kernel env bundle

This repository includes `.github/workflows/build-kernel-prod-env.yml` for preparing an offline Kernel development bundle.

Current default target:

```text
kernel_repository = aisphereio/kernel
kernel_ref = v0.1.16
go_version = 1.25.8
go_bundle_versions = 1.25.8,1.26.4
buf_version = 1.50.0
protoc_version = 35.1
include_windows_amd64 = true
run_validation = true
```

Recommended manual run for the current Kernel release tag:

```text
Actions -> build-kernel-prod-env -> Run workflow
kernel_ref = v0.1.16
```

Artifact includes:

```text
Go offline archives
protoc and buf raw archives
Linux amd64 tool bundle
Windows amd64 tool bundle
Go module file-proxy cache
Go module cache
Go build cache
Buf cache
Kernel source snapshot
reports
checksums
```

Linux usage after downloading and extracting the artifact:

```bash
bash scripts/apply-kernel-prod-env.sh "$PWD" /mnt/data/kernel-prod-env
source /mnt/data/kernel-prod-env/env.sh
/mnt/data/kernel-prod-env/verify.sh
```
