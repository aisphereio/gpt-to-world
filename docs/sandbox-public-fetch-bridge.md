# Sandbox Public Fetch Bridge 使用说明

本文档说明如何用 GitHub Actions 给不能直接访问公网的沙箱下载依赖、Release 包、Go modules、CLI 工具，并通过 Actions artifact 把结果取回来。

这个模式适合 ChatGPT / Codex / 其他受限代码沙箱：沙箱本身不能 `curl`、不能 `go mod download`，但可以通过 GitHub 连接器读取 Actions 日志和下载 artifact。

## 1. 核心思路

```text
受限沙箱不能直接访问公网
        ↓
GitHub Actions Runner 可以访问公网
        ↓
Actions 下载公网资源、Go 依赖、Release 包
        ↓
Actions 打包为 artifact
        ↓
受限沙箱通过 GitHub connector / 浏览器 / gh CLI 获取 artifact
        ↓
沙箱离线解压、使用、测试、构建
```

它不是让沙箱直接联网，而是把“公网下载动作”转移到 GitHub Actions 里执行。

## 2. 适用场景

适合下载和打包：

- Go modules：`vendor.tgz`、`gomod-cache-download.tgz`；
- protobuf 工具：`protoc`、`protoc-gen-go`、`buf`；
- GitHub Release 里的 Linux 二进制；
- 构建依赖包、测试报告、离线工具包；
- 小型源码包、patch、文档包。

不建议用于：

- 私密密钥、密码、token；
- 大模型权重等超大文件；
- 需要许可证限制的商业软件；
- 任何不应该进入公共 artifact 的敏感文件。

## 3. 权限准备

如果要让 ChatGPT 或其他 AI 助手直接维护这个仓库，需要给 GitHub App / Connector 至少这些权限：

```text
Contents: Read and write
Workflows: Read and write
Actions: Read
Pull requests: Read and write，可选
Metadata: Read
```

权限验证标准：

```text
能创建 README.md / 普通文件
  => Contents write 正常

能创建 .github/workflows/*.yml
  => Workflows write 正常

能读取 Actions run / job / artifact
  => Actions read 正常
```

## 4. 推荐目录结构

```text
gpt-to-world/
├── README.md
├── docs/
│   └── sandbox-public-fetch-bridge.md
└── .github/
    └── workflows/
        └── public-fetch-bridge.yml
```

## 5. 通用 workflow 模板

把下面文件保存为：

```text
.github/workflows/public-fetch-bridge.yml
```

```yaml
name: Public Fetch Bridge

on:
  workflow_dispatch:
    inputs:
      asset_urls:
        description: "Public URLs to download, one URL per line"
        required: false
        type: string
      run_go_mod:
        description: "Run go mod download when go.mod exists"
        required: true
        default: true
        type: boolean
  push:
    branches:
      - main
    paths:
      - "go.mod"
      - "go.sum"
      - "**/*.go"
      - ".github/workflows/public-fetch-bridge.yml"

permissions:
  contents: read

defaults:
  run:
    shell: bash

jobs:
  fetch:
    name: Fetch public assets and pack artifact
    runs-on: ubuntu-latest
    timeout-minutes: 30

    env:
      BUF_VERSION: "1.71.0"
      PROTOC_VERSION: "35.1"
      GO_VERSION: "1.25.x"

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Prepare directories
        run: |
          set -euxo pipefail
          mkdir -p downloads tools/bin tools/protoc reports offline
          {
            echo "repo=${GITHUB_REPOSITORY}"
            echo "sha=${GITHUB_SHA}"
            echo "ref=${GITHUB_REF}"
            echo "runner_os=${RUNNER_OS}"
            echo "started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
          } | tee reports/context.txt

      - name: Probe public internet
        run: |
          set -euxo pipefail
          curl -fsSL https://api.github.com/repos/bufbuild/buf/releases/latest -o reports/buf-latest-release.json
          curl -fsSL https://api.github.com/repos/protocolbuffers/protobuf/releases/latest -o reports/protobuf-latest-release.json
          python3 - <<'PY' | tee reports/release-summary.txt
          import json
          for name, path in [
              ("buf", "reports/buf-latest-release.json"),
              ("protobuf", "reports/protobuf-latest-release.json"),
          ]:
              data = json.load(open(path, encoding="utf-8"))
              print(f"{name}: {data.get('tag_name')} {data.get('html_url')}")
          PY

      - name: Download buf linux amd64
        run: |
          set -euxo pipefail
          curl -fL "https://github.com/bufbuild/buf/releases/download/v${BUF_VERSION}/buf-Linux-x86_64" -o tools/bin/buf
          chmod +x tools/bin/buf
          tools/bin/buf --version | tee reports/buf-version.txt

      - name: Download protoc linux amd64
        run: |
          set -euxo pipefail
          curl -fL "https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/protoc-${PROTOC_VERSION}-linux-x86_64.zip" -o downloads/protoc-linux-x86_64.zip
          unzip -q -o downloads/protoc-linux-x86_64.zip -d tools/protoc
          tools/protoc/bin/protoc --version | tee reports/protoc-version.txt

      - name: Download custom public URLs
        if: ${{ inputs.asset_urls != '' }}
        run: |
          set -euxo pipefail
          printf '%s\n' "${{ inputs.asset_urls }}" > reports/requested-asset-urls.txt
          i=0
          while IFS= read -r url; do
            [[ -z "$url" ]] && continue
            i=$((i+1))
            name="asset-${i}-$(basename "${url%%\?*}")"
            [[ "$name" == "asset-${i}-" ]] && name="asset-${i}.bin"
            echo "Downloading $url -> downloads/$name"
            curl -fL "$url" -o "downloads/$name"
          done < reports/requested-asset-urls.txt
          ls -lh downloads | tee reports/custom-downloads-list.txt

      - name: Setup Go
        uses: actions/setup-go@v5
        with:
          go-version: ${{ env.GO_VERSION }}
          cache: true

      - name: Download Go modules when go.mod exists
        if: ${{ inputs.run_go_mod }}
        run: |
          set -euxo pipefail
          go version | tee reports/go-version.txt
          go env GOPATH GOMODCACHE GOPROXY GOSUMDB | tee reports/go-env.txt

          if [[ -f go.mod ]]; then
            go mod download -x 2>&1 | tee reports/go-mod-download.log
            go mod verify 2>&1 | tee reports/go-mod-verify.log

            go mod vendor
            tar -czf vendor.tgz vendor go.mod go.sum

            mkdir -p offline/download
            cp -a "$(go env GOPATH)/pkg/mod/cache/download/." offline/download/
            tar -czf gomod-cache-download.tgz -C offline download
          else
            echo "go.mod not found; skip Go module download" | tee reports/go-mod-skip.txt
            tar -czf vendor.tgz --files-from /dev/null
            tar -czf gomod-cache-download.tgz --files-from /dev/null
          fi

      - name: Pack tools bundle
        run: |
          set -euxo pipefail
          tar -czf linux-amd64-tools.tgz tools reports downloads
          ls -lh *.tgz | tee reports/artifacts-list.txt

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: public-fetch-bundle
          path: |
            linux-amd64-tools.tgz
            vendor.tgz
            gomod-cache-download.tgz
            reports/**
          retention-days: 7
          if-no-files-found: error
```

## 6. 如何运行 workflow

### 方式一：GitHub 页面手动运行

进入仓库页面：

```text
Actions -> Public Fetch Bridge -> Run workflow
```

可选填 `asset_urls`，一行一个公网 URL，例如：

```text
https://github.com/bufbuild/buf/releases/download/v1.71.0/buf-Linux-x86_64
https://github.com/protocolbuffers/protobuf/releases/download/v35.1/protoc-35.1-linux-x86_64.zip
```

### 方式二：用 GitHub CLI 运行

```bash
gh workflow run public-fetch-bridge.yml \
  -R aisphereio/gpt-to-world \
  -f run_go_mod=true \
  -f asset_urls=$'https://example.com/file1.tgz\nhttps://example.com/file2.zip'
```

查看 run：

```bash
gh run list -R aisphereio/gpt-to-world --workflow public-fetch-bridge.yml
```

## 7. 如何下载 artifact

### 方式一：ChatGPT / AI 助手通过 GitHub connector 下载

给 AI 助手提供 Actions run URL，例如：

```text
https://github.com/aisphereio/gpt-to-world/actions/runs/<RUN_ID>
```

AI 助手可以：

```text
1. fetch_workflow_run_jobs
2. fetch_workflow_run_artifacts
3. download_workflow_artifact
4. 在沙箱里解压 artifact
```

### 方式二：GitHub 页面下载

```text
Actions -> 选择 run -> Artifacts -> public-fetch-bundle
```

### 方式三：GitHub CLI 下载

```bash
gh run download <RUN_ID> \
  -R aisphereio/gpt-to-world \
  -n public-fetch-bundle \
  -D public-fetch-bundle
```

## 8. 其他沙箱如何离线使用

拿到 `public-fetch-bundle.zip` 后：

```bash
unzip public-fetch-bundle.zip -d public-fetch-bundle
cd public-fetch-bundle
```

安装工具到当前 shell：

```bash
tar -xzf linux-amd64-tools.tgz
export PATH="$PWD/tools/bin:$PWD/tools/protoc/bin:$PATH"

buf --version
protoc --version
```

如果 artifact 里有 Go vendor：

```bash
tar -xzf vendor.tgz

go test -mod=vendor ./...
go build -mod=vendor ./...
```

如果使用 Go module download cache：

```bash
mkdir -p "$(go env GOPATH)/pkg/mod/cache"
tar -xzf gomod-cache-download.tgz -C "$(go env GOPATH)/pkg/mod/cache"

go env -w GOPROXY=off
go mod download
```

## 9. 给 Go 项目打离线依赖包

把真实 Go 项目的 `go.mod` 和 `go.sum` 放到仓库根目录，然后运行 workflow。

成功后 artifact 会包含：

```text
vendor.tgz
  vendor/
  go.mod
  go.sum

gomod-cache-download.tgz
  download/
    github.com/...
    golang.org/...
    google.golang.org/...
```

在另一个不能联网的沙箱里，推荐优先使用 vendor 模式：

```bash
tar -xzf vendor.tgz
go test -mod=vendor ./...
go build -mod=vendor ./...
```

## 10. 常见问题

### Q1: 沙箱还是不能 curl，怎么办？

正常。这个方案不是让沙箱直接 curl，而是让 GitHub Actions curl，然后通过 artifact 把结果带回来。

### Q2: artifact 过期怎么办？

默认示例里 `retention-days: 7`。可以改成更长，但不建议把 artifact 当长期制品仓库。长期文件应放 Release、对象存储或包仓库。

### Q3: 能不能下载私有资源？

可以技术上做到，但不建议把 token 和私密文件放进 artifact。若确实需要，必须使用 GitHub Secrets，并确保 artifact 不包含敏感信息。

### Q4: 为什么 workflow 能下载，沙箱不能下载？

因为 GitHub-hosted runner 有公网访问能力，而很多 AI 沙箱出于安全和隔离原因没有公网访问能力。

### Q5: 可以让 AI 自动改 workflow 吗？

可以，但需要 GitHub App / connector 有：

```text
Contents: Read and write
Workflows: Read and write
```

否则 AI 只能读文件、读日志、下载 artifact，不能推送变更。

## 11. 安全约束

使用这个模式时要遵守几个原则：

1. 不要把 secrets 写入 artifact。
2. 不要上传私有源码或敏感配置到公开仓库 artifact。
3. 下载的公网文件最好有版本号和 checksum。
4. 大文件不要长期放 artifact。
5. workflow 日志里不要 echo token、密码、内网地址等敏感信息。

## 12. 推荐工作流

```text
1. 用户或 AI 提交 workflow / go.mod / 下载清单
2. GitHub Actions 执行公网下载
3. Actions 上传 public-fetch-bundle artifact
4. AI 读取 run 日志并下载 artifact
5. AI 在沙箱里离线解压和验证
6. AI 根据验证结果继续修改代码或 workflow
```

这个仓库可以作为所有受限沙箱的“公网下载桥”。
