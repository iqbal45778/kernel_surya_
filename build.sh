#!/usr/bin/env bash

# Build script for Poco X3 NFC (Surya)
# Author: Adapted by Mahiroo from nysascape
# License: Hirateam Public License

# ========== CONFIG ==========
export TELEGRAM_TOKEN=7485743487:AAEKPw9ubSKZKit9BDHfNJSTWcWax4STUZs
export TELE_CHANNEL=-1002354747626
export DEVICE=surya
KERNEL=Perf-qgki
DEFCONFIG=surya_defconfig
KERNELRELEASE=surya
CIPROVIDER="GitHub Action"
export ANYKERNEL=$(pwd)/anykernel3
export OUTDIR=${PWD}/out
export ARCH=arm64

# ========== SYSTEM INFO ==========
PARSE_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
PARSE_ORIGIN="$(git config --get remote.origin.url)"
COMMIT_POINT="$(git log --pretty=format:'%h : %s' -1)"
TOTAL_RAM_GB=$(awk '/^Mem/ {printf "%.0f", $2 / 1024}' < <(free -m))
PROCS=$(nproc --all)
CPU_NAME=$(lscpu | awk -F: '/Model name/ {print $2}' | xargs)
DISTRO=$(source /etc/os-release && echo "${NAME}")
DATE=$(TZ=Asia/Jakarta date)
ZIP_DATE=$(TZ=Asia/Jakarta date +"%Y%m%d-%H%M")

# ========== PATH & IMG ==========
export IMG_DTB=${OUTDIR}/arch/arm64/boot/Image.gz-dtb
export DTB_IMG=${OUTDIR}/arch/arm64/boot/dtb.img
export DTBO_IMG=${OUTDIR}/arch/arm64/boot/dtbo.img

# ========== FUNCTIONS ==========

clang() {
    mkdir clang && cd clang
    curl -LO "https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman"
    chmod +x antman
    ./antman -S
    ./antman --patch=glibc
    cd ..
    
    git clone --depth=1 https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9 gcc64
    git clone --depth=1 https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9 gcc32
    
    export CLANG_DIR="${PWD}/clang"
    export COMPILER_STRING="$(${CLANG_DIR}/bin/clang --version | head -n 1)"
    
    if ! command -v ${CLANG_DIR}/bin/clang &> /dev/null; then
        echo "❌ Clang not found! Exiting..."
        exit 1
    fi
}

setversioning() {
    KERNELNAME="${KERNEL}-${KERNELRELEASE}-KSU-${ZIP_DATE}"
    export KERNELNAME ZIPNAME="${KERNELNAME}.zip" TEMPZIPNAME="${KERNELNAME}.zip"
}

tg_channelcast() {
    local msg=""
    for POST in "$@"; do msg+="${POST}"$'\n'; done
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d chat_id="${TELE_CHANNEL}" \
        -d disable_web_page_preview=true \
        -d parse_mode=HTML \
        -d text="${msg}"
}

makekernel() {
    rm -rf ${ANYKERNEL}
    git clone https://github.com/rinnsakaguchi/AnyKernel3.git -b FSociety anykernel3
    mkdir -p out
    export PATH="${PWD}/clang/bin:${PWD}/gcc64/bin:${PWD}/gcc32/bin:$PATH"
    export KBUILD_BUILD_USER="Mahiroo"
    export KBUILD_BUILD_HOST="HiraTeam"
    export KBUILD_COMPILER_STRING="${COMPILER_STRING}"

    make O=out ARCH=arm64 ${DEFCONFIG}
    make -j${PROCS} O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 \
         CLANG_TRIPLE=aarch64-linux-gnu- \
         CROSS_COMPILE=aarch64-linux-gnu- \
         CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
         CROSS_COMPILE_ARM32=arm-linux-gnueabi- |& tee build.log

    if [ ! -f "${IMG_DTB}" ]; then
        END=$(date +"%s")
        DIFF=$((END - START))
        tg_channelcast "❌ Build for ${DEVICE} <b>failed</b> in $((DIFF/60))m $((DIFF%60))s! Check ${CIPROVIDER} logs."
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendDocument" \
            -F chat_id="${TELE_CHANNEL}" \
            -F document=@"build.log" \
            -F caption="❌ Failed build log for ${KERNELNAME}"
        exit 1
    fi
}

shipkernel() {
    cp "${IMG_DTB}" "${ANYKERNEL}/" || true
    cp "${DTB_IMG}" "${ANYKERNEL}/" || true
    cp "${DTBO_IMG}" "${ANYKERNEL}/" || true

    cd "${ANYKERNEL}" || exit
    zip -r9 "${TEMPZIPNAME}" *
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendDocument" \
         -F chat_id="${TELE_CHANNEL}" \
         -F document=@"${TEMPZIPNAME}" \
         -F caption="✅ Kernel build: ${KERNELNAME}"
    cd ..

    # Optional: Send build log on success
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendDocument" \
         -F chat_id="${TELE_CHANNEL}" \
         -F document=@"build.log" \
         -F caption="📝 Build log for ${KERNELNAME}"
}

# ========== EXECUTION FLOW ==========

clang
setversioning
tg_channelcast "🚀 <b>Starting Kernel Build</b>" \
    "OS: <code>${DISTRO}</code>" \
    "Compiler: <code>${COMPILER_STRING}</code>" \
    "Device: <code>Poco X3 NFC (${DEVICE})</code>" \
    "Linux Version: <code>$(make kernelversion)</code>" \
    "Branch: <code>${PARSE_BRANCH}</code>" \
    "Commit: <code>${COMMIT_POINT}</code>" \
    "CPU: <code>${CPU_NAME} (${PROCS} cores)</code>" \
    "RAM: <code>${TOTAL_RAM_GB} GB</code>" \
    "Build Host: <code>${KBUILD_BUILD_HOST}</code>" \
    "Date: <code>${DATE}</code>"

START=$(date +"%s")
makekernel
shipkernel
END=$(date +"%s")
DIFF=$((END - START))

tg_channelcast "✅ <b>Build Success</b> for <b>${DEVICE}</b> with <code>${COMPILER_STRING}</code> in $((DIFF/60))m $((DIFF%60))s!"