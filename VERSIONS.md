# Matched toolchain versions

Maintain two separate component sets. Branch names describe the development
tracks; the commit table below records the source snapshot at the split on
2026-11-26. `make init-src` follows branch heads, so later runs can fetch newer
commits on the same track.

## Component branches

| Repository | Main build track | 0.59 build track |
| --- | --- | --- |
| [linx-toolchain-build](https://github.com/LinxISA/linx-toolchain-build) | `main` | `0.59` |
| [llvm-project](https://github.com/LinxISA/llvm-project) | `dev-llvm15_56` | `0.59` |
| [linx-musl](https://github.com/LinxISA/linx-musl) | `linx` | `0.59` |
| [Linx-TileOP-API](https://github.com/LinxISA/Linx-TileOP-API) | `linx` | `0.59` |
| [jemalloc](https://github.com/LinxISA/jemalloc) | `linx` | `linx` |
| [linux](https://github.com/LinxISA/linux) | `main` | `main` |

The initializer and both GitHub Actions workflows in each build branch select
that branch's component set. jemalloc and Linux are shared by both tracks.

## Source snapshot

| Component | Main track commit | 0.59 track commit |
| --- | --- | --- |
| llvm-project | `99afda46f2ad7f6d1cc9d5ccf4c4f9c89d3d366f` | `6ea2054b2f8d1851bfb6aa9c786bb29e930d59ad` |
| linx-musl | `fe6cef34984e9af9d5779213c4180f39d2ba9fab` | `798f0fb819154d1484113a3c8011655ca7c26754` |
| Linx-TileOP-API | `5f764847b707fabf998c93fb4725787bcd2d6417` | `1e5e392c75849b40898b332eb6b38a0dbe8c8a64` |
| jemalloc | `4495309cd11cae1a0a2d008c65acd9c410076f06` | `4495309cd11cae1a0a2d008c65acd9c410076f06` |
| linux | `aa9e4404588ca06019270530fc95fbf7f7504a68` | `aa9e4404588ca06019270530fc95fbf7f7504a68` |

Both build tracks start from build-repository commit
`e6a31efb4cfb17f1f1c33265cbf6dbb61bbba156`. The commits adding this document and
selecting the track are recorded in the respective build branch histories.
To reproduce the component snapshot, run `make init-src` in a fresh clone,
then check out the recorded commits in each component before building.

## Runtime ABI split

musl commit `798f0fb819154d1484113a3c8011655ca7c26754` adds
`-mlinx-runtime-intra-abi` and the matching fixed-address static four-PE startup
integration. The complete commit is preserved on musl `0.59`; LLVM `0.59`
contains its compiler support (introduced by `66bfa50f7c45`).

musl `linx` reverts that entire integration in
`fe6cef34984e9af9d5779213c4180f39d2ba9fab`. Its source tree exactly matches
`d0e442cf5f7daaa201c4f707810fd559670330df`, the parent of the integration.
This retains history and restores the source used with `dev-llvm15_56`.
Do not remove just the compiler flag while retaining its dependent startup ABI.

## Build a track

Use separate clones and output directories for the two tracks:

```sh
git clone --branch main https://github.com/LinxISA/linx-toolchain-build.git linx-build-main
cd linx-build-main
make init-src
make WITH_TARGET=linx64v5-linux-musl
```

```sh
git clone --branch 0.59 https://github.com/LinxISA/linx-toolchain-build.git linx-build-059
cd linx-build-059
make init-src
make WITH_TARGET=linx64v5-linux-musl
```

If reusing a build directory, preserve local source changes first, switch the
build-repository branch, run `make clean` to remove generated outputs and stamp
files, then run `make init-src` and build again. `make init-src` resets component
branches to their configured remote branch heads; it does not preserve manual
component commit selections. The build stamps do not track component commit IDs.

For the 0.59 track, this compile-only probe must accept the runtime ABI option:

```sh
output/linx_blockisa_llvm_musl/bin/clang \
  --target=linx64v5-linux-musl -mlinx-runtime-intra-abi \
  -fsyntax-only -x c /dev/null
```

The branch split records matching source requirements. It does not certify a
complete build or four-PE runtime execution on a particular host/platform.
