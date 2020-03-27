#!/usr/bin/env bash
#
# Copyright (C) 2019 nysascape
#
# Licensed under the Raphielscape Public License, Version 1.d (the "License");
# you may not use this file except in compliance with the License.
#
# CI build script for Acrux

# Make sure our fekking token is exported ig?
export TELEGRAM_TOKEN=${BOT_API_TOKEN}

# Some misc enviroment vars
DEVICE=X00T
CIPROVIDER=CircleCI

# Clone our AnyKernel3 branch to KERNELDIR
git clone https://github.com/Danish1999/AnyKernel3 anykernel3
export ANYKERNEL=$(pwd)/anykernel3

# Parse git things
PARSE_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
PARSE_ORIGIN="$(git config --get remote.origin.url)"
COMMIT_POINT="$(git log --pretty=format:'%h : %s' -1)"

# Do some silly defconfig replacements
if [[ "${PARSE_BRANCH}" =~ "staging"* ]]; then
	# For staging branch
	KERNELTYPE=nightly
	KERNELNAME="Acrux-${KERNELRELEASE}-Nightly-${KERNELFW}-$(date +%y%m%d-%H%M)"
	sed -i "50s/.*/CONFIG_LOCALVERSION=\"-${KERNELNAME}\"/g" arch/arm64/configs/acrux_defconfig
        # Disable LTO on non-release builds
        sed -i 's/CONFIG_LTO=y/CONFIG_LTO=n/g' arch/arm64/configs/acrux_defconfig
        sed -i 's/# CONFIG_LTO_NONE is not set/CONFIG_LTO_NONE=y/g' arch/arm64/configs/acrux_defconfig
        sed -i 's/CONFIG_LTO_CLANG=y/CONFIG_LTO_CLANG=n/g' arch/arm64/configs/acrux_defconfig
elif [[ "${PARSE_BRANCH}" =~ "ten"* ]]; then
	# For stable (ten) branch
	KERNELTYPE=stable
	KERNELNAME="Acrux-${KERNELRELEASE}-Release-${KERNELFW}-$(date +%y%m%d-%H%M)"
        sed -i "50s/.*/CONFIG_LOCALVERSION=\"-${KERNELNAME}\"/g" arch/arm64/configs/acrux_defconfig
else
	# Dunno when this will happen but we will cover, just in case
	KERNELTYPE=${PARSE_BRANCH}
	KERNELNAME="Vortex-${KERNELRELEASE}-${PARSE_BRANCH}-$(date +%y%m%d-%H%M)"
fi

export KERNELTYPE KERNELNAME

# Workaround for long af kernel strings
git config --global user.name "Danish1999"
git config --global user.email "danish01031999@gmail.com"
git add .
git commit -m "stop adding dirty"

# Might as well export our zip
export TEMPZIPNAME="${KERNELNAME}-unsigned.zip"
export ZIPNAME="${KERNELNAME}.zip"

# Our TG channels
export CI_CHANNEL="-1001373270821"

# sendcast to channel
tg_channelcast() {
    "${TELEGRAM}" -c "${CI_CHANNEL}" -H \
    "$(
		for POST in "${@}"; do
			echo "${POST}"
		done
    )"
}

# Let's announce our naisu new kernel!
tg_groupcast "Vortex compilation clocked at $(date +%Y%m%d-%H%M)!"
tg_channelcast "Compiler: <code>${COMPILER_STRING}</code>" \
	"Device: <b>${DEVICE}</b>" \
	"Kernel: <code>Vortex, release ${KERNELRELEASE}</code>" \
	"Branch: <code>${PARSE_BRANCH}</code>" \
	"Commit point: <code>${COMMIT_POINT}</code>" \
	"Under <code>${CIPROVIDER}</code>" \
	"Clocked at: <code>$(date +%Y%m%d-%H%M)</code>" \
	"Started on <code>$(whoami)</code>"

# Make is shit so I have to pass thru some toolchains
# Let's build, anyway
PATH="${KERNELDIR}/clang/bin:${PATH}"
START=$(date +"%s")

mkdir ${KERNELDIR}/out

make O=out ARCH=arm64 X00T_defconfig
if [[ "${COMPILER_TYPE}" =~ "clang"* ]]; then
        make -j"${JOBS}" CC=clang CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- O=out ARCH=arm64
elif [[ "${COMPILER_TYPE}" =~ "GCC9"* ]]; then
	make -j"${JOBS}" O=out ARCH=arm64 CROSS_COMPILE="${KERNELDIR}/gcc/bin/aarch64-elf-" CROSS_COMPILE_ARM32="${KERNELDIR}/gcc32/bin/arm-eabi-"
elif [[ "${COMPILER_TYPE}" =~ "GCC4.9"* ]]; then
	make -j"${JOBS}" O=out ARCH=arm64 CROSS_COMPILE="${KERNELDIR}/gcc/bin/aarch64-linux-android-"
else
	make -j"${JOBS}" O=out ARCH=arm64 CROSS_COMPILE="${KERNELDIR}/gcc/bin/aarch64-elf-" CROSS_COMPILE_ARM32="${KERNELDIR}/gcc32/bin/arm-eabi-"
fi

## Check if compilation is done successfully.
if ! [ -f "${OUTDIR}"/arch/arm64/boot/Image.gz-dtb ]; then
	END=$(date +"%s")
	DIFF=$(( END - START ))
	echo -e "Kernel compilation failed, See buildlog to fix errors"
	tg_channelcast "Build for ${DEVICE} <b>failed</b> in $((DIFF / 60)) minute(s) and $((DIFF % 60)) second(s)! Check ${CIPROVIDER} for errors!"
	exit 1
fi

# Copy our !!hopefully!! compiled kernel
cp "${OUTDIR}"/arch/arm64/boot/Image.gz-dtb "${ANYKERNEL}"/

# POST ZIP OR FAILURE
cd "${ANYKERNEL}" || exit
zip -r9 "${TEMPZIPNAME}" *

## Sign the zip before sending it to telegram
curl -sLo zipsigner-3.0.jar https://raw.githubusercontent.com/baalajimaestro/AnyKernel2/master/zipsigner-3.0.jar
java -jar zipsigner-3.0.jar ${TEMPZIPNAME} ${ZIPNAME}

"${TELEGRAM}" -f "$ZIPNAME" -c "${CI_CHANNEL}"

cd ..

rm -rf "${ANYKERNEL}"
END=$(date +"%s")
DIFF=$(( END - START ))
tg_channelcast "Build for ${DEVICE} with ${COMPILER_STRING} took $((DIFF / 60)) minute(s) and $((DIFF % 60)) second(s)!"
