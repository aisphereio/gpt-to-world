# Kernel env bundle

This branch adds `.github/workflows/build-kernel-prod-env.yml`.

Use it from GitHub Actions to build the Go, proto, Buf, generator, cache, source, report, and checksum bundle required by `aisphereio/kernel`.

Main Linux entry after downloading the artifact:

```bash
bash scripts/apply-kernel-prod-env.sh "$PWD" /mnt/data/kernel-prod-env
source /mnt/data/kernel-prod-env/env.sh
/mnt/data/kernel-prod-env/verify.sh
```
