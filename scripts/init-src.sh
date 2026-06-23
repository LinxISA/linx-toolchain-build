#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${ROOT_DIR}/src"

mkdir -p "${SRC_DIR}"

sync_repo() {
  local name="$1"
  local url="$2"
  local branch="$3"
  local dir="${SRC_DIR}/${name}"

  if [[ -d "${dir}/.git" ]]; then
    echo "Updating ${name} (${branch})"
    git -C "${dir}" remote set-url origin "${url}"
    git -C "${dir}" fetch --prune origin "${branch}"
    git -C "${dir}" checkout -B "${branch}" "origin/${branch}"
  else
    if [[ -e "${dir}" ]]; then
      echo "Refusing to replace non-git path: ${dir}" >&2
      exit 1
    fi
    echo "Cloning ${name} (${branch})"
    git clone --branch "${branch}" --single-branch "${url}" "${dir}"
  fi
}

sync_repo "llvm-project" "https://github.com/LinxISA/llvm-project.git" "bisheng-linx"
sync_repo "musl" "https://github.com/LinxISA/linx-musl.git" "linx"
sync_repo "jemalloc" "https://github.com/LinxISA/jemalloc.git" "linx"
sync_repo "linux-linxisa" "https://github.com/LinxISA/linux.git" "main"
sync_repo "Linx-TileOP-API" "https://github.com/LinxISA/Linx-TileOP-API.git" "linx"

echo "Component repositories are ready under ${SRC_DIR}."
