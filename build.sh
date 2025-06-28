#!/usr/bin/env bash
# Copyright (C) 2019-2020 Jago Gardiner (nysascape)
#
# Licensed under the Raphielscape Public License, Version 1.d (the "License");
# you may not use this file except in compliance with the License.
#
# CI build script

# Needed exports
export TELEGRAM_TOKEN=7485743487:AAEKPw9ubSKZKit9BDHfNJSTWcWax4STUZs
export ANYKERNEL=$(pwd)/anykernel3
export CLANG_DIR=${PWD}/clang
export GCC_64_DIR=${PWD}/gcc
export GCC_32_DIR=${PWD}/gcc32
export OUTDIR=${PWD}/out
export COMPILER_STRING=$(${CLANG_DIR}/bin/clang --version | head -n 1)
export ccache_="" #ccache
export COMPILER_TYPE=clang
DEVICE="surya"
export DEVICE

# Avoid hardcoding things
KERNEL=Perf-qgki
DEFCONFIG=surya_ksu_defconfig
CIPROVIDER=CircleCI
PARSE_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
PARSE_ORIGIN="$(git config --get remote.origin.url)"
COMMIT_POINT="$(git log --pretty=format:'%h : %s' -1)"

# Get total RAM
RAM_INFO=$(free -m)
TOTAL_RAM=$(echo "$RAM_INFO" | awk '/^Mem:/{print $2}')
TOTAL_RAM_GB=$(awk "BEGIN {printf \"%.0f\", $TOTAL_RAM/1024}")
export TOTAL_RAM_GB

# Get all cores of CPU
PROCS=$(nproc --all)
export PROCS

# Get CPU name
export CPU_NAME="$(lscpu | sed -nr '/Model name/ s/.*:\s*(.*) */\1/p')"

# Get distro name
DISTRO=$(source /etc/os-release && echo ${NAME})

# Export custom KBUILD
export IMG_DTB=${OUTDIR}/arch/arm64/boot/Image.gz-dtb
export DTB_IMG=${OUTDIR}/arch/arm64/boot/dtb.img
export DTBO_IMG=${OUTDIR}/arch/arm64/boot/dtbo.img
export KBUILD_BUILD_USER=mahiroo
export KBUILD_BUILD_HOST=android-build
export CLANG_PATH=${PWD}/clang
export PATH=${CLANG_PATH}/bin:${PATH}
export ARCH=arm64
export DATE=$(TZ=Asia/Jakarta date)
# Kernel groups
TELE_CHANNEL=-1002354747626

# Kernel revision
KERNELRELEASE=surya

# Toolchain check
if ! [ -d "${CLANG_DIR}" ]; then
    echo "Clang not found! Cloning..."
    git clone --depth=1 -b clang-21.0 https://gitlab.com/kutemeikito/rastamod69-clang "${CLANG_DIR}" || exit 1
fi
if ! [ -d "${GCC_64_DIR}" ]; then
    echo "GCC 64 not found! Cloning..."
    git clone --depth=1 -b lineage-19.1 https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9.git "${GCC_64_DIR}" || exit 1
fi
if ! [ -d "${GCC_32_DIR}" ]; then
    echo "GCC 32 not found! Cloning..."
    git clone --depth=1 -b lineage-19.1 https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9.git "${GCC_32_DIR}" || exit 1
fi

# Set date and time
DATE=$(TZ=Asia/Jakarta date)

# Set date and time for zip name
ZIP_DATE=$(TZ=Asia/Jakarta date +"%Y%m%d-%H%M")

# Function to replace defconfig versioning
setversioning() {

# For staging branch
            KERNELNAME="${KERNEL}-${KERNELRELEASE}-KSU-${ZIP_DATE}"
	    
    # Export our new localversion and zipnames
    export KERNELTYPE KERNELNAME
    export TEMPZIPNAME="${KERNELNAME}.zip"
    export ZIPNAME="${KERNELNAME}.zip"
}

# Send to channel
tg_channelcast() {
    "${TELEGRAM}" -c "${TELE_CHANNEL}" -H \
    "$(2
		for POST in "${@}"; do
			echo "${POST}"
		done
    )"
}

# Make the kernel
makekernel() {
    # Clean any old AnyKernel
    rm -rf ${ANYKERNEL}
    git clone https://github.com/rinnsakaguchi/AnyKernel3.git -b FSociety anykernel3

    # Regenerate defconfig
    make O=out ARCH=arm64 ${DEFCONFIG}

    # Start actual build
    make -j$(nproc --all) \
        O=out \
        CC="${ccache_} clang" \
        AS=llvm-as \
        LD=ld.lld \
        AR=llvm-ar \
        NM=llvm-nm \
        STRIP=llvm-strip \
        OBJCOPY=llvm-objcopy \
        OBJDUMP=llvm-objdump \
        CROSS_COMPILE="${GCC_64_DIR}/bin/aarch64-none-linux-gnu-" \
        CROSS_COMPILE_ARM32="${GCC_32_DIR}/bin/arm-none-linux-gnueabihf-" \
        |& tee build.log

    # Check if compilation is done successfully.
    if ! [ -f "${IMG_DTB}" ]; then
	END=$(date +"%s")
	DIFF=$(( END - START ))
	echo -e "Kernel compilation failed, see buildlog to fix errors."
	tg_channelcast "Build for ${DEVICE} <b>failed</b> in $((DIFF / 60)) minute(s) and $((DIFF % 60)) second(s)! Check ${CIPROVIDER} for errors!"
	if [[ -f build.log ]]; then
		curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendDocument" \
		  -F chat_id="${TELE_CHANNEL}" \
		  -F document=@"build.log" \
		  -F caption="Build failed log for ${KERNELNAME}"
	fi
	exit 1
    fi
}

# Ship the compiled kernel
shipkernel() {
    # Copy compiled kernel
    cp "${IMG_DTB}" "${ANYKERNEL}/"
    cp "${DTB_IMG}" "${ANYKERNEL}/"
    cp "${DTBO_IMG}" "${ANYKERNEL}/"
   
    # Zip the kernel, or fail
    cd "${ANYKERNEL}" || exit
    zip -r9 "${TEMPZIPNAME}" *

    # Ship it to the CI channel
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendDocument" \
     -F chat_id="${TELE_CHANNEL}" \
     -F document=@"${TEMPZIPNAME}" \
     -F caption="Kernel build: ${KERNELNAME}"

    # Go back for any extra builds
    cd ..
}

# Ship China firmware builds
clearout() {
    # Pick DSP change
    rm -rf out
    mkdir -p out
}

#Setver 2 for ksu
setver2() {
    KERNELNAME="${KERNEL}-${KERNELRELEASE}-KSU-${ZIP_DATE}"
    export KERNELTYPE KERNELNAME
    export TEMPZIPNAME="${KERNELNAME}-unsigned.zip"
    export ZIPNAME="${KERNELNAME}.zip"
}

## Start the kernel buildflow ##
setversioning
tg_channelcast "Docker OS: <code>$DISTRO</code>" \
        "Compiler: <code>${COMPILER_STRING}</code>" \
	"Device: <code>Poco X3 NFC (surya)</code>" \
	"Linux Version: <code>$(make kernelversion)</code>" \
        "Date: <code>$DATE</code>" \
	"Branch: <code>${PARSE_BRANCH}</code>" \
        "Host RAM Count: <code>${TOTAL_RAM_GB}</code>" \
        "Pipeline Host: <code>${KBUILD_BUILD_HOST}</code>" \
        "Host CPU Name: <code>${CPU_NAME}</code>" \
        "Host Core Count: <code>${PROCS} core(s)</code>" \
	"Commit point: <code>${COMMIT_POINT}</code>"
START=$(date +"%s")
makekernel || exit 1
shipkernel

END=$(date +"%s")
DIFF=$(( END - START ))
tg_channelcast "Build for Poco X3 NFC with ${COMPILER_STRING} <b>succeed</b> took $((DIFF / 60)) minute(s) and $((DIFF % 60)) second(s)!"
