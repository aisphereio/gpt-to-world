# gpt-to-world

`gpt-to-world` is a GitHub Actions based public-fetch bridge for ChatGPT coding workflows.

It lets a restricted ChatGPT sandbox obtain public internet resources indirectly through GitHub Actions artifacts.

```text
ChatGPT sandbox has no direct public network access
        ↓
GitHub Actions runner has public internet access
        ↓
Actions downloads public assets and Go dependencies
        ↓
Actions uploads them as workflow artifacts
        ↓
ChatGPT reads the workflow run, downloads the artifact, and uses it offline
```

## Why this exists

In some ChatGPT coding sessions, the execution sandbox can run commands and inspect files, but it cannot reliably access the public internet. Commands like these may fail:

```bash
go mod download
curl https://github.com/...
wget https://...
```

This repository provides a practical workaround: use GitHub Actions as a controlled public-network worker, then return the downloaded files through workflow artifacts.

## Current proven flow

The initial probe workflow has verified that GitHub Actions can:

- access public GitHub APIs;
- download `buf` for Linux amd64;
- download `protoc` for Linux amd64;
- initialize Go with `actions/setup-go`;
- package downloaded assets into an artifact;
- expose that artifact back to ChatGPT through the GitHub connector.

Verified artifact contents include:

```text
public-fetch-bundle.zip
├── linux-amd64-tools.tgz
├── vendor.tgz
├── gomod-cache-download.tgz
└── reports/
```

When no `go.mod` exists, `vendor.tgz` and `gomod-cache-download.tgz` are intentionally empty. Once a real Go project is committed, the workflow can package Go dependencies as well.

## Typical workflow

1. Commit a Go project, or at least `go.mod` and `go.sum`.
2. Run the GitHub Actions workflow.
3. The workflow downloads dependencies and public tools.
4. The workflow uploads an artifact such as `public-fetch-bundle`.
5. ChatGPT reads the run logs and downloads the artifact.
6. ChatGPT uses the artifact inside its sandbox for offline build, test, or analysis.

## Example assets to fetch

The bridge can be used to prepare assets such as:

- `buf` Linux amd64 binary;
- `protoc` Linux amd64 archive;
- Go module cache;
- vendored Go dependencies;
- generated test reports;
- release archives from public GitHub repositories.

## Suggested artifact layout

```text
public-fetch-bundle.zip
├── linux-amd64-tools.tgz          # buf, protoc, and other CLI tools
├── vendor.tgz                     # vendored Go dependencies
├── gomod-cache-download.tgz       # Go module download cache
└── reports/
    ├── context.txt
    ├── release-summary.txt
    ├── buf-version.txt
    ├── protoc-version.txt
    ├── go-version.txt
    ├── go-env.txt
    ├── go-mod-download.log
    └── go-mod-verify.log
```

## Minimal local usage after downloading the artifact

```bash
unzip public-fetch-bundle.zip -d public-fetch-bundle
cd public-fetch-bundle

tar -xzf linux-amd64-tools.tgz
export PATH="$PWD/tools/bin:$PWD/tools/protoc/bin:$PATH"

buf --version
protoc --version
```

For a Go project with vendored dependencies:

```bash
tar -xzf vendor.tgz

go test -mod=vendor ./...
go build -mod=vendor ./...
```

## Notes

This repository is not intended to bypass security controls. It is a reproducible, auditable way to let GitHub Actions perform public downloads and return the resulting files as explicit artifacts.

Keep secrets out of artifacts. Only publish public dependencies, public release binaries, generated reports, and reproducible build inputs.
