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

Build the default `linx64v5-linux-musl` toolchain:

```sh
make -j16
```

Create a release tarball:

```sh
make package
```

The default install tree is `output/linx_blockisa_llvm_musl`, and the package is written to `output/linx_blockisa_llvm_musl.tar.gz`.

## Useful Overrides

```sh
make THREADS=64 ENABLE_CCACHE=on
make WITH_CPU=v0.43w
make INSTALL_DIR=/opt/linx-toolchain
make LLVM_LINX_DIR=/path/to/llvm-project
```

Only `WITH_TARGET=linx64v5-linux-musl` is currently supported by the top-level Makefile.
