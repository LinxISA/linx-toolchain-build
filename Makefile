MKFILE := $(abspath $(lastword $(MAKEFILE_LIST)))
MKFILE_DIR := $(shell dirname $(MKFILE))
SRC_DIR := $(MKFILE_DIR)/src
BUILD_DIR := $(MKFILE_DIR)/build
OUTPUT_DIR := $(MKFILE_DIR)/output
VERSION_CONF := $(MKFILE_DIR)/version.conf
BUILD_LOG := $(MKFILE_DIR)/build.log
CONFIGURE_HOST := $(shell gcc -dumpmachine)

SHELL := /bin/bash -o pipefail
AWK := awk

WITH_TARGET ?= linx64v5-linux-musl
WITH_ENDIAN ?= le
WITH_CPU ?=
ENABLE_LLVM_DEBUG ?= off
ENABLE_CCACHE ?= off
LLVM_ASSERTIONS ?= ON
THREADS ?= 16
INSTALL_DIR ?= default

MUSL_SRCDIR ?= $(SRC_DIR)/musl
JEMALLOC_SRCDIR ?= $(SRC_DIR)/jemalloc
KERNEL_HEADER_DIR ?= $(SRC_DIR)/linux-linxisa
LLVM_LINX_DIR ?= $(SRC_DIR)/llvm-project
TILEOP_API_DIR ?= $(SRC_DIR)/Linx-TileOP-API

PACKAGE_NAME := linx_blockisa_llvm_musl
DEFAULT_INSTALL_DIR := $(OUTPUT_DIR)/$(PACKAGE_NAME)

ifeq ($(WITH_TARGET),linx64v5-linux-musl)
LLVM_TARGETS := LinxV5
RT_ARCH := linx64v5
else
$(error This Makefile only supports WITH_TARGET=linx64v5-linux-musl)
endif

ifeq ($(WITH_ENDIAN),le)
ENDIAN := -mlittle-endian
else ifeq ($(WITH_ENDIAN),be)
ENDIAN := -mbig-endian
else
$(error Please set WITH_ENDIAN to le or be)
endif

SUPPORT_CPU := v0.43g v0.43w v0.43k v1.0w v1.0k
BUILD_LIGHT_CORE ?= off
CPU_FLAG :=
ifneq ($(filter $(WITH_CPU),$(SUPPORT_CPU)),)
  ifneq ($(filter $(WITH_CPU),v1.0w v1.0k),)
    BUILD_LIGHT_CORE := on
    WITH_ENDIAN := be
    ENDIAN := -mbig-endian
  endif
  ifeq ($(WITH_CPU),v0.43w)
    WITH_ENDIAN := be
    ENDIAN := -mbig-endian
  endif
  CPU_FLAG := -mcpu=$(WITH_CPU)
endif

ifeq ($(BUILD_LIGHT_CORE),on)
BUILD_LIGHT_CORE_MACRO := -DLINX_BUILD_LIGHT_CORE
endif

ifeq ($(INSTALL_DIR),default)
INSTALL_DIR := $(DEFAULT_INSTALL_DIR)
endif

ifneq ($(wildcard $(VERSION_CONF)),)
COMPILER_INFO := $(shell $(AWK) '/^\[version\]/ {sub(/^\[version\] /, ""); print}' $(VERSION_CONF))
else
COMPILER_INFO := linx64v5-musl-local
endif

OPTIMIZATION_FLAGS := -O2
WALL_STACK_PROTECTOR_FLAG := -Wall -fstack-protector-strong
SHARED_SECURE_LDFLAGS := -z relro -z now -z noexecstack
FORTIFY_FLAG := -D_FORTIFY_SOURCE=2
PUB_LD_OPTION := $(SHARED_SECURE_LDFLAGS) -Wl,-Bsymbolic -Wl,-s
SECURE_LDFLAGS := $(PUB_LD_OPTION) -rdynamic -Wl,--no-undefined
EXE_SECURE_LDFLAGS := $(SHARED_SECURE_LDFLAGS) -pie

ifeq ($(ENABLE_LLVM_DEBUG),on)
LLVM_BUILD_TYPE := Debug
LLVM_DEBUG_INFO := -g
SECURE_CFLAGS := $(WALL_STACK_PROTECTOR_FLAG) $(FORTIFY_FLAG) -fPIE
else
LLVM_BUILD_TYPE := Release
SECURE_CFLAGS := $(OPTIMIZATION_FLAGS) $(WALL_STACK_PROTECTOR_FLAG) $(FORTIFY_FLAG) -fPIE
endif
SECURE_CXXFLAGS := $(SECURE_CFLAGS)

ifeq ($(ENABLE_CCACHE),on)
ifeq (, $(shell which ccache))
LLVM_ENABLE_CCACHE := OFF
else
LLVM_ENABLE_CCACHE := ON
endif
else
LLVM_ENABLE_CCACHE := OFF
endif

PUB_CFLAGS_FOR_TARGET := -fno-short-enums -fno-short-wchar $(OPTIMIZATION_FLAGS) --target=$(WITH_TARGET) $(CPU_FLAG) $(ENDIAN) $(BUILD_LIGHT_CORE_MACRO) $(WALL_STACK_PROTECTOR_FLAG)
MUSL_CFLAGS_FOR_TARGET := $(PUB_CFLAGS_FOR_TARGET) -I$(LLVM_LINX_DIR)/libunwind/include $(FORTIFY_FLAG) -fPIE -DLINX_USE_JEMALLOC
MUSL_CXXFLAGS_FOR_TARGET := $(MUSL_CFLAGS_FOR_TARGET)
FLAGS_FOR_COMPILER_RT_MUSL := -Wall $(FORTIFY_FLAG) $(OPTIMIZATION_FLAGS) -nostdlib $(ENDIAN) $(CPU_FLAG) --target=$(WITH_TARGET)
FLAGS_FOR_JEMALLOC := -ftls-model=local-exec
JEMALLOC_CFLAGS_FOR_TARGET := $(filter-out -DLINX_USE_JEMALLOC,$(MUSL_CFLAGS_FOR_TARGET))
JEMALLOC_CXXFLAGS_FOR_TARGET := $(filter-out -DLINX_USE_JEMALLOC,$(MUSL_CFLAGS_FOR_TARGET))

COMMON_LIBCXX_CFLAGS_FOR_TARGET := $(PUB_CFLAGS_FOR_TARGET) -fno-short-enums -fno-short-wchar -nostdlib
LIBCXXABI_CFLAGS_FOR_TARGET := $(COMMON_LIBCXX_CFLAGS_FOR_TARGET)
LIBCXXABI_CXXFLAGS_FOR_TARGET := $(LIBCXXABI_CFLAGS_FOR_TARGET) -I$(INSTALL_DIR)/sysroot/usr/include/c++/v1
LIBCXX_CFLAGS_FOR_TARGET := $(COMMON_LIBCXX_CFLAGS_FOR_TARGET)
LIBCXX_CXXFLAGS_FOR_TARGET := $(LIBCXX_CFLAGS_FOR_TARGET) -I$(LLVM_LINX_DIR)/libcxxabi/include
LIBUNWIND_CFLAGS_FOR_TARGET := $(COMMON_LIBCXX_CFLAGS_FOR_TARGET)
LIBUNWIND_CXXFLAGS_FOR_TARGET := $(LIBUNWIND_CFLAGS_FOR_TARGET)
LIBUNWIND_ASMFLAGS_FOR_TARGET := $(LIBUNWIND_CFLAGS_FOR_TARGET)

BINUTILS_AR := $(INSTALL_DIR)/bin/llvm-ar
BINUTILS_AS := $(INSTALL_DIR)/bin/clang
BINUTILS_NM := $(INSTALL_DIR)/bin/llvm-nm
BINUTILS_READELF := $(INSTALL_DIR)/bin/llvm-readelf
BINUTILS_RANLIB := $(INSTALL_DIR)/bin/llvm-ranlib

ifeq (, $(shell which ninja))
LLVM_MAKE := $(MAKE) -j $(THREADS)
LLVM_GENERATOR := Unix Makefiles
else
LLVM_MAKE := ninja
LLVM_GENERATOR := Ninja
endif

MUSL_SRC_GIT := $(MUSL_SRCDIR)/.git
JEMALLOC_SRC_GIT := $(JEMALLOC_SRCDIR)/.git
KERNEL_HEADER_GIT := $(KERNEL_HEADER_DIR)/.git
LLVM_LINX_GIT := $(LLVM_LINX_DIR)/.git
TILEOP_API_GIT := $(TILEOP_API_DIR)/.git
RT_SRC_DIR := $(LLVM_LINX_DIR)/compiler-rt

.PHONY: all init-src musl build-llvm build-musl build-compiler-rt build-libcxx build-libcxxabi build-libunwind build-jemalloc build-tileopapi package clean help

all: musl

init-src:
	$(MKFILE_DIR)/scripts/init-src.sh

musl: stamps/build-llvm-musl$(LLVM_DEBUG_INFO) \
	stamps/build-kernel-header \
	stamps/build-musl \
	stamps/build-compiler-rt-musl \
	stamps/build-libcxx-musl \
	stamps/build-libcxxabi-musl \
	stamps/build-libunwind-musl \
	stamps/build-jemalloc \
	stamps/build-tileopapi

build-llvm: stamps/build-llvm-musl$(LLVM_DEBUG_INFO)
build-musl: stamps/build-musl
build-compiler-rt: stamps/build-compiler-rt-musl
build-libcxx: stamps/build-libcxx-musl
build-libcxxabi: stamps/build-libcxxabi-musl
build-libunwind: stamps/build-libunwind-musl
build-jemalloc: stamps/build-jemalloc
build-tileopapi: stamps/build-tileopapi

package: $(INSTALL_DIR)
	[ -n "$(INSTALL_DIR)/share" ] && rm -rf $(INSTALL_DIR)/share || true
	mkdir -p $(OUTPUT_DIR)
	tar --format=gnu -czf $(OUTPUT_DIR)/$(PACKAGE_NAME).tar.gz -C $(shell dirname $(INSTALL_DIR)) $(shell basename $(INSTALL_DIR))

stamps/check-write-permission:
	mkdir -p $(INSTALL_DIR)/.test || \
		(echo "No write permission to $(INSTALL_DIR)" && exit 1)
	rm -rf $(INSTALL_DIR)/.test
	mkdir -p $(dir $@) && touch $@

stamps/build-llvm-musl$(LLVM_DEBUG_INFO): $(LLVM_LINX_DIR) $(LLVM_LINX_GIT) stamps/check-write-permission
	rm -rf $@ $(BUILD_DIR)/$(notdir $@)
	mkdir -p $(BUILD_DIR)/$(notdir $@)
	cd $(BUILD_DIR)/$(notdir $@) && \
		cmake -G "$(LLVM_GENERATOR)" $(LLVM_LINX_DIR)/llvm \
		-DCMAKE_BUILD_TYPE=$(LLVM_BUILD_TYPE) \
		-DLLVM_ENABLE_ASSERTIONS=$(LLVM_ASSERTIONS) \
		-DLLVM_CCACHE_BUILD=$(LLVM_ENABLE_CCACHE) \
		-DLLVM_DEFAULT_TARGET_TRIPLE="$(WITH_TARGET)" \
		-DCMAKE_INSTALL_PREFIX=$(INSTALL_DIR) \
		-DLLVM_TARGETS_TO_BUILD="$(LLVM_TARGETS)" \
		-DLLVM_ENABLE_PROJECTS="clang;lld" \
		-DCLANG_REPOSITORY_STRING="$(COMPILER_INFO)" \
		-DLLVM_LINK_LLVM_DYLIB=OFF \
		-DLLVM_ENABLE_CLASSIC_FLANG=on \
		-DLINX_USE_LIBC="musl" \
		-DCMAKE_CXX_FLAGS="-std=c++11 $(SECURE_CXXFLAGS)" \
		-DBUILD_SHARED_LIBS=OFF \
		-DLLVM_ENABLE_PIC=ON \
		-DCMAKE_C_FLAGS="$(SECURE_CFLAGS)" \
		-DCMAKE_EXE_LINKER_FLAGS="$(EXE_SECURE_LDFLAGS)" \
		-DCMAKE_SHARED_LINKER_FLAGS="$(SHARED_SECURE_LDFLAGS)" \
		-DCMAKE_MODULE_LINKER_FLAGS="$(SHARED_SECURE_LDFLAGS)" 2>&1 | tee -a $(BUILD_LOG)
	$(LLVM_MAKE) -C $(BUILD_DIR)/$(notdir $@) 2>&1 | tee -a $(BUILD_LOG)
	$(LLVM_MAKE) -C $(BUILD_DIR)/$(notdir $@) install 2>&1 | tee -a $(BUILD_LOG)
	cd $(INSTALL_DIR)/bin && ln -s -f clang $(WITH_TARGET)-clang && ln -s -f clang++ $(WITH_TARGET)-clang++
	mkdir -p $(dir $@) && touch $@

stamps/build-kernel-header: $(KERNEL_HEADER_DIR) $(KERNEL_HEADER_GIT) stamps/check-write-permission
	echo "Installing kernel headers..."
	rm -rf $@ $(BUILD_DIR)/$(notdir $@)
	mkdir -p $(BUILD_DIR)/$(notdir $@)
	mkdir -p $(INSTALL_DIR)/sysroot/usr/include
	cd $(KERNEL_HEADER_DIR) && \
		make headers_install ARCH=linx INSTALL_HDR_PATH=$(BUILD_DIR)/$(notdir $@)
	cp -r $(BUILD_DIR)/$(notdir $@)/include $(INSTALL_DIR)/sysroot/usr
	mkdir -p $(dir $@) && touch $@

stamps/build-musl: $(MUSL_SRCDIR) $(MUSL_SRC_GIT) stamps/build-llvm-musl$(LLVM_DEBUG_INFO) stamps/build-kernel-header
	rm -rf $@ $(BUILD_DIR)/$(notdir $@)
	mkdir -p $(BUILD_DIR)/$(notdir $@)
	mkdir -p $(INSTALL_DIR)/sysroot/usr/lib
	touch $(INSTALL_DIR)/sysroot/usr/lib/libjemalloc.a
	cd $(BUILD_DIR)/$(notdir $@) && \
		$</configure \
		--build=$(CONFIGURE_HOST) \
		--host=$(WITH_TARGET) \
		--disable-shared \
		--enable-static \
		--enable-backtrace \
		--prefix=$(INSTALL_DIR) \
		--libdir=$(INSTALL_DIR)/sysroot/usr/lib \
		--includedir=$(INSTALL_DIR)/sysroot/usr/include \
		CC="$(INSTALL_DIR)/bin/clang $(MUSL_CFLAGS_FOR_TARGET)" \
		AR="$(BINUTILS_AR)" \
		RANLIB="$(BINUTILS_RANLIB)" \
		CC_FOR_TARGET=$(INSTALL_DIR)/bin/clang \
		CXX_FOR_TARGET=$(INSTALL_DIR)/bin/clang++ \
		AR_FOR_TARGET=$(BINUTILS_AR) \
		AS_FOR_TARGET=$(BINUTILS_AS) \
		NM_FOR_TARGET=$(BINUTILS_NM) \
		READELF_FOR_TARGET=$(BINUTILS_READELF) \
		RANLIB_FOR_TARGET=$(BINUTILS_RANLIB) \
		LDFLAGS="$(SECURE_LDFLAGS)" \
		CFLAGS_FOR_TARGET="$(MUSL_CFLAGS_FOR_TARGET)" \
		CXXFLAGS_FOR_TARGET="$(MUSL_CXXFLAGS_FOR_TARGET)" 2>&1 | tee -a $(BUILD_LOG)
	$(MAKE) -j $(THREADS) -C $(BUILD_DIR)/$(notdir $@) 2>&1 | tee -a $(BUILD_LOG)
	$(MAKE) -j $(THREADS) -C $(BUILD_DIR)/$(notdir $@) install 2>&1 | tee -a $(BUILD_LOG)
	mkdir -p $(dir $@) && touch $@

stamps/build-compiler-rt-musl: $(RT_SRC_DIR) stamps/build-llvm-musl$(LLVM_DEBUG_INFO) stamps/build-musl
	rm -rf $@ $(BUILD_DIR)/$(notdir $@)
	mkdir -p $(BUILD_DIR)/$(notdir $@)
	cd $(BUILD_DIR)/$(notdir $@) && \
		cmake -G Ninja $(RT_SRC_DIR) \
		-DCMAKE_INSTALL_PREFIX=$(INSTALL_DIR) \
		-DCMAKE_BUILD_TYPE=Release \
		-DCOMPILER_RT_BUILD_BUILTINS=ON \
		-DCOMPILER_RT_BUILD_SANITIZERS=OFF \
		-DCOMPILER_RT_BUILD_XRAY=OFF \
		-DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
		-DCOMPILER_RT_BUILD_PROFILE=OFF \
		-DCOMPILER_RT_BUILTINS_HIDE_SYMBOLS=OFF \
		-DCMAKE_C_COMPILER=$(INSTALL_DIR)/bin/clang \
		-DCMAKE_CXX_COMPILER=$(INSTALL_DIR)/bin/clang++ \
		-DCMAKE_AR=$(BINUTILS_AR) \
		-DCMAKE_AS=$(BINUTILS_AS) \
		-DCMAKE_NM=$(BINUTILS_NM) \
		-DCMAKE_RANLIB=$(BINUTILS_RANLIB) \
		-DCMAKE_C_COMPILER_TARGET=$(WITH_TARGET) \
		-DCMAKE_CXX_COMPILER_TARGET=$(WITH_TARGET) \
		-DCMAKE_ASM_COMPILER_TARGET=$(WITH_TARGET) \
		-DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
		-DCOMPILER_RT_EXCLUDE_ATOMIC_BUILTIN=OFF \
		-DLLVM_CONFIG_PATH=$(INSTALL_DIR)/bin/llvm-config \
		-DCMAKE_C_FLAGS="$(FLAGS_FOR_COMPILER_RT_MUSL)" \
		-DCMAKE_CXX_FLAGS="$(FLAGS_FOR_COMPILER_RT_MUSL)" \
		-DCMAKE_ASM_FLAGS="$(FLAGS_FOR_COMPILER_RT_MUSL)" \
		-DCMAKE_EXE_LINKER_FLAGS="$(SECURE_LDFLAGS)" \
		-DCMAKE_SHARED_LINKER_FLAGS="$(SECURE_LDFLAGS)" 2>&1 | tee -a $(BUILD_LOG)
	$(LLVM_MAKE) -C $(BUILD_DIR)/$(notdir $@) 2>&1 | tee -a $(BUILD_LOG)
	mkdir -p $(INSTALL_DIR)/lib/clang/15.0.4/lib/linux
	cp $(BUILD_DIR)/$(notdir $@)/lib/linux/libclang_rt.builtins-$(RT_ARCH).a $(INSTALL_DIR)/lib/clang/15.0.4/lib/linux
	cp $(BUILD_DIR)/$(notdir $@)/lib/linux/libclang_rt.builtins-$(RT_ARCH).a $(INSTALL_DIR)/lib/clang/15.0.4/lib/linux/libclang_rt.builtins-linx64be.a
	cp $(BUILD_DIR)/$(notdir $@)/lib/linux/clang_rt.crtbegin-$(RT_ARCH).o $(INSTALL_DIR)/sysroot/usr/lib/crtbeginT.o
	cp $(BUILD_DIR)/$(notdir $@)/lib/linux/clang_rt.crtend-$(RT_ARCH).o $(INSTALL_DIR)/sysroot/usr/lib/crtend.o
	mkdir -p $(dir $@) && touch $@

stamps/build-libcxx-musl: $(LLVM_LINX_DIR) stamps/build-llvm-musl$(LLVM_DEBUG_INFO) stamps/build-compiler-rt-musl
	rm -rf $@ $(BUILD_DIR)/$(notdir $@)
	mkdir -p $(BUILD_DIR)/$(notdir $@)
	touch $(INSTALL_DIR)/sysroot/usr/lib/libatomic.a
	cd $(BUILD_DIR)/$(notdir $@) && \
		cmake -G "$(LLVM_GENERATOR)" $(LLVM_LINX_DIR)/libcxx \
			-DCMAKE_INSTALL_PREFIX=$(INSTALL_DIR)/sysroot/usr \
			-DCMAKE_BUILD_TYPE=Release \
			-DCMAKE_C_COMPILER=$(INSTALL_DIR)/bin/clang \
			-DCMAKE_CXX_COMPILER=$(INSTALL_DIR)/bin/clang++ \
			-DCMAKE_AR=$(BINUTILS_AR) \
			-DCMAKE_NM=$(BINUTILS_NM) \
			-DCMAKE_RANLIB=$(BINUTILS_RANLIB) \
			-DCMAKE_C_COMPILER_TARGET=$(WITH_TARGET) \
			-DCMAKE_CXX_COMPILER_TARGET=$(WITH_TARGET) \
			-DCMAKE_C_FLAGS="$(LIBCXX_CFLAGS_FOR_TARGET)" \
			-DCMAKE_CXX_FLAGS="$(LIBCXX_CXXFLAGS_FOR_TARGET)" \
			-DCMAKE_EXE_LINKER_FLAGS="$(SECURE_LDFLAGS)" \
			-DLLVM_PATH=$(LLVM_LINX_DIR)/llvm \
			-DLLVM_RUNTIME_TARGETS=$(WITH_TARGET) \
			-DLIBCXX_CXX_ABI_INCLUDE_PATHS=$(LLVM_LINX_DIR)/libcxxabi/include \
			-DLIBCXX_CXX_ABI_LIBRARY_PATH=$(INSTALL_DIR)/$(WITH_TARGET)/lib/linx64-libcxxabi \
			-DLIBCXX_CXX_ABI=libcxxabi \
			-DLIBCXX_ENABLE_SHARED=OFF \
			-DLIBCXX_ENABLE_STATIC=ON \
			-DLIBCXX_HAS_MUSL_LIBC=ON \
			-DLIBCXX_HAS_NEWLIB_LIBC=OFF \
			-DLIBCXX_INCLUDE_BENCHMARKS=OFF \
			-DLIBCXX_ENABLE_LOCALIZATION=ON \
			-DLIBCXX_ENABLE_FILESYSTEM=OFF \
			-Wno-dev 2>&1 | tee -a $(BUILD_LOG)
	$(LLVM_MAKE) -C $(BUILD_DIR)/$(notdir $@) 2>&1 | tee -a $(BUILD_LOG)
	$(LLVM_MAKE) -C $(BUILD_DIR)/$(notdir $@) install 2>&1 | tee -a $(BUILD_LOG)
	mkdir -p $(dir $@) && touch $@

stamps/build-libcxxabi-musl: $(LLVM_LINX_DIR) stamps/build-llvm-musl$(LLVM_DEBUG_INFO) stamps/build-libcxx-musl
	rm -rf $@ $(BUILD_DIR)/$(notdir $@)
	mkdir -p $(BUILD_DIR)/$(notdir $@)
	cd $(BUILD_DIR)/$(notdir $@) && \
		cmake -G "$(LLVM_GENERATOR)" $(LLVM_LINX_DIR)/libcxxabi \
			-DCMAKE_INSTALL_PREFIX=$(INSTALL_DIR)/sysroot/usr \
			-DCMAKE_BUILD_TYPE=Release \
			-DCMAKE_C_COMPILER=$(INSTALL_DIR)/bin/clang \
			-DCMAKE_CXX_COMPILER=$(INSTALL_DIR)/bin/clang++ \
			-DCMAKE_AR=$(BINUTILS_AR) \
			-DCMAKE_NM=$(BINUTILS_NM) \
			-DCMAKE_RANLIB=$(BINUTILS_RANLIB) \
			-DCMAKE_C_COMPILER_TARGET=$(WITH_TARGET) \
			-DCMAKE_CXX_COMPILER_TARGET=$(WITH_TARGET) \
			-DCMAKE_C_FLAGS="$(LIBCXXABI_CFLAGS_FOR_TARGET)" \
			-DCMAKE_CXX_FLAGS="$(LIBCXXABI_CXXFLAGS_FOR_TARGET)" \
			-DCMAKE_EXE_LINKER_FLAGS="$(SECURE_LDFLAGS)" \
			-DLLVM_RUNTIME_TARGETS="$(WITH_TARGET)" \
			-DLIBCXXABI_LIBCXX_INCLUDES=$(LLVM_LINX_DIR)/libcxx/include \
			-DLIBCXXABI_LIBUNWIND_INCLUDES=$(LLVM_LINX_DIR)/libunwind/include \
			-DLIBCXXABI_LIBUNWIND_SOURCES=$(LLVM_LINX_DIR)/libunwind/src \
			-DLIBCXXABI_USE_LLVM_UNWINDER=YES \
			-DLIBCXXABI_USE_COMPILER_RT=YES \
			-DLIBCXXABI_ENABLE_SHARED=OFF \
			-DLIBCXXABI_ENABLE_STATIC=ON \
			-Wno-dev 2>&1 | tee -a $(BUILD_LOG)
	$(LLVM_MAKE) -C $(BUILD_DIR)/$(notdir $@) 2>&1 | tee -a $(BUILD_LOG)
	$(LLVM_MAKE) -C $(BUILD_DIR)/$(notdir $@) install 2>&1 | tee -a $(BUILD_LOG)
	mkdir -p $(dir $@) && touch $@

stamps/build-libunwind-musl: $(LLVM_LINX_DIR) stamps/build-llvm-musl$(LLVM_DEBUG_INFO)
	rm -rf $@ $(BUILD_DIR)/$(notdir $@)
	mkdir -p $(BUILD_DIR)/$(notdir $@)
	cd $(BUILD_DIR)/$(notdir $@) && \
		cmake -G "$(LLVM_GENERATOR)" $(LLVM_LINX_DIR)/libunwind \
			-DFORCE_COMPILE_ASM=ON \
			-DCMAKE_INSTALL_PREFIX=$(INSTALL_DIR)/sysroot/usr \
			-DCMAKE_BUILD_TYPE=Release \
			-DCMAKE_CROSSCOMPILING=True \
			-DCMAKE_C_COMPILER=$(INSTALL_DIR)/bin/clang \
			-DCMAKE_CXX_COMPILER=$(INSTALL_DIR)/bin/clang++ \
			-DCMAKE_AR=$(BINUTILS_AR) \
			-DCMAKE_NM=$(BINUTILS_NM) \
			-DCMAKE_RANLIB=$(BINUTILS_RANLIB) \
			-DCMAKE_C_COMPILER_TARGET=$(WITH_TARGET) \
			-DCMAKE_CXX_COMPILER_TARGET=$(WITH_TARGET) \
			-DCMAKE_ASM_COMPILER_TARGET=$(WITH_TARGET) \
			-DCMAKE_C_FLAGS="$(LIBUNWIND_CFLAGS_FOR_TARGET)" \
			-DCMAKE_CXX_FLAGS="$(LIBUNWIND_CXXFLAGS_FOR_TARGET)" \
			-DCMAKE_ASM_FLAGS="$(LIBUNWIND_ASMFLAGS_FOR_TARGET)" \
			-DCMAKE_EXE_LINKER_FLAGS="$(SECURE_LDFLAGS)" \
			-DLLVM_PATH=$(LLVM_LINX_DIR)/llvm \
			-DLIBUNWIND_IS_BAREMETAL=off \
			-DLIBUNWIND_ENABLE_ASSERTIONS=OFF \
			-DLIBUNWIND_ENABLE_SHARED=OFF \
			-DLIBUNWIND_ENABLE_STATIC=ON \
			-DLIBUNWIND_USE_COMPILER_RT=ON \
			-DLIBUNWIND_REMEMBER_HEAP_ALLOC=ON \
			-Wno-dev 2>&1 | tee -a $(BUILD_LOG)
	$(LLVM_MAKE) -C $(BUILD_DIR)/$(notdir $@) 2>&1 | tee -a $(BUILD_LOG)
	$(LLVM_MAKE) -C $(BUILD_DIR)/$(notdir $@) install 2>&1 | tee -a $(BUILD_LOG)
	mkdir -p $(dir $@) && touch $@

stamps/build-jemalloc: $(JEMALLOC_SRCDIR) $(JEMALLOC_SRC_GIT) stamps/build-llvm-musl$(LLVM_DEBUG_INFO) stamps/build-musl
	rm -rf $@ $(BUILD_DIR)/$(notdir $@)
	mkdir -p $(BUILD_DIR)/$(notdir $@)
	if command -v autoconf >/dev/null 2>&1 && command -v m4 >/dev/null 2>&1; then \
		mkdir -p $(INSTALL_DIR)/sysroot/usr/lib; \
		if [ ! -f $(INSTALL_DIR)/sysroot/usr/lib/libjemalloc.a ]; then \
			$(BINUTILS_AR) rcs $(INSTALL_DIR)/sysroot/usr/lib/libjemalloc.a; \
		fi; \
		cd $(JEMALLOC_SRCDIR) && ./autogen.sh --disable-shared --disable-stats --disable-prof --disable-fill --disable-initial-exec-tls --with-malloc-conf="narenas:1,dirty_decay_ms:-1,muzzy_decay_ms:-1"; \
		cd $(BUILD_DIR)/$(notdir $@) && \
			$(JEMALLOC_SRCDIR)/configure \
			--host=$(WITH_TARGET) \
			--disable-shared \
			--disable-cxx \
			--disable-initial-exec-tls \
			--disable-doc \
			--prefix=$(INSTALL_DIR) \
			--libdir=$(INSTALL_DIR)/sysroot/usr/lib \
			--with-malloc-conf="dirty_decay_ms:-1,muzzy_decay_ms:-1" \
			CC="$(INSTALL_DIR)/bin/clang $(JEMALLOC_CFLAGS_FOR_TARGET) $(FLAGS_FOR_JEMALLOC)" \
			CXX="$(INSTALL_DIR)/bin/clang++ $(JEMALLOC_CXXFLAGS_FOR_TARGET) $(FLAGS_FOR_JEMALLOC) $(LIBCXXABI_CXXFLAGS_FOR_TARGET)" 2>&1 | tee -a $(BUILD_LOG); \
		$(MAKE) -j $(THREADS) -C $(BUILD_DIR)/$(notdir $@) 2>&1 | tee -a $(BUILD_LOG); \
		$(MAKE) -j $(THREADS) -C $(BUILD_DIR)/$(notdir $@) install 2>&1 | tee -a $(BUILD_LOG); \
	else \
		echo "autoconf/m4 not found; creating placeholder libjemalloc.a" | tee -a $(BUILD_LOG); \
		mkdir -p $(INSTALL_DIR)/sysroot/usr/lib; \
		rm -f $(INSTALL_DIR)/sysroot/usr/lib/libjemalloc.a; \
		$(BINUTILS_AR) rcs $(INSTALL_DIR)/sysroot/usr/lib/libjemalloc.a; \
	fi
	mkdir -p $(dir $@) && touch $@

stamps/build-tileopapi: $(TILEOP_API_DIR) $(TILEOP_API_GIT) stamps/build-llvm-musl$(LLVM_DEBUG_INFO)
	echo "Installing Linx TileOp API headers..."
	rm -rf $@ $(BUILD_DIR)/$(notdir $@)
	mkdir -p $(BUILD_DIR)/$(notdir $@)
	mkdir -p $(INSTALL_DIR)/sysroot/usr/include
	cd $(TILEOP_API_DIR) && \
		make install CLANG_PREFIX=$(INSTALL_DIR)
	mkdir -p $(dir $@) && touch $@

clean:
	rm -rf $(BUILD_DIR) $(OUTPUT_DIR) stamps $(BUILD_LOG)

help:
	@echo "Targets:"
	@echo "  make                  Build the linx64v5-linux-musl toolchain"
	@echo "  make init-src         Clone or update required component repositories"
	@echo "  make package          Package output into output/linx_blockisa_llvm_musl.tar.gz"
	@echo "  make clean            Remove build outputs"
	@echo ""
	@echo "Configuration:"
	@echo "  WITH_TARGET=linx64v5-linux-musl"
	@echo "  MUSL_SRCDIR=$(SRC_DIR)/musl"
	@echo "  JEMALLOC_SRCDIR=$(SRC_DIR)/jemalloc"
	@echo "  KERNEL_HEADER_DIR=$(SRC_DIR)/linux-linxisa"
	@echo "  LLVM_LINX_DIR=$(SRC_DIR)/llvm-project"
	@echo "  TILEOP_API_DIR=$(SRC_DIR)/Linx-TileOP-API"
