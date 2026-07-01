# Kernel env bundle

This repository includes `.github/workflows/build-kernel-prod-env.yml` for preparing an offline Kernel development bundle.

Current default target:

```text
kernel_repository = aisphereio/kernel
kernel_ref = master
go_version = 1.25.8
go_bundle_versions = 1.25.8,1.26.4
buf_version = 1.50.0
protoc_version = 35.1
include_windows_amd64 = true
run_validation = true
```

Current note:

```text
Use master until the platformflow compile fix is tagged.
After the next Kernel release tag is created, switch kernel_ref back to that tag.
```

Latest sandbox execution trigger:

```text
2026-07-01T12:12:00+02:00 full kernel prod env requested
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

See scripts/apply-kernel-prod-env.sh in the artifact.
