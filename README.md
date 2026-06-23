# Linx Toolchain Build

This repository contains the top-level build flow for the Linx LLVM + musl toolchain.

## Components

`make init-src` creates `src/` and checks out the required component repositories:

| Directory | Repository | Branch |
| --- | --- | --- |
| `src/llvm-project` | `https://github.com/LinxISA/llvm-project.git` | `bisheng-linx` |
| `src/musl` | `https://github.com/LinxISA/linx-musl.git` | `linx` |
| `src/jemalloc` | `https://github.com/LinxISA/jemalloc.git` | `linx` |
| `src/linux-linxisa` | `https://github.com/LinxISA/linux.git` | `main` |
| `src/Linx-TileOP-API` | `https://github.com/LinxISA/Linx-TileOP-API.git` | `linx` |

## Quick Start

Install the host build tools first:

```sh
sudo apt-get install -y git make cmake ninja-build gcc g++ python3 autoconf m4
```

Initialize component sources:

```sh
make init-src
```

Build the `linx64v5-linux-musl` toolchain:

```sh
make WITH_TARGET=linx64v5-linux-musl
```

Package the build output:

```sh
make package
```

The default install tree is `output/linx_blockisa_llvm_musl`, and the package is written to:

```text
output/linx_blockisa_llvm_musl.tar.gz
```

Only `WITH_TARGET=linx64v5-linux-musl` is supported by the top-level Makefile.
