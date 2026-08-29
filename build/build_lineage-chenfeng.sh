#!/usr/bin/env bash
#
# LineageOS 23.2 / Android 16 - Xiaomi chenfeng
#
# Optimized for a disposable, high-resource ~2 hour Ubuntu sandbox.
#
# IMPORTANT:
#   - NO proprietary-file extraction.
#   - The vendor repository is used exactly as supplied.
#   - The kernel repository is cloned directly; the device tree controls
#     whether/how its prebuilts are used.
#

set -Eeuo pipefail

###############################################################################
# CONFIGURATION
###############################################################################

DEVICE="chenfeng"
LINEAGE_BRANCH="lineage-23.2"
MANIFEST_URL="https://github.com/LineageOS/android.git"

SOURCE_DIR="/android"
OUTPUT_DIR="/xeon-man"

DEVICE_TREE_URL="https://github.com/sm8650-devs/android_device_xiaomi_chenfeng.git"
DEVICE_TREE_BRANCH="lineage-23.2"

KERNEL_TREE_URL="https://github.com/sm8650-devs/android_device_xiaomi_chenfeng-kernel.git"
KERNEL_TREE_BRANCH="lineage-23.2"

VENDOR_TREE_URL="https://codeberg.org/smgreborn/vendor_xiaomi_chenfeng.git"
VENDOR_TREE_BRANCH="lineage-23.2"

HARDWARE_TREE_URL="https://github.com/sm8650-devs/android_hardware_xiaomi-chenfeng.git"
HARDWARE_TREE_BRANCH="lineage-23.2"

GIT_NAME="xeon-man"
GIT_EMAIL="contact@gaminglnk.eu.org"

# This is deliberately higher than LineageOS' manifest default.
# If sync fails, the script retries lower.
SYNC_JOBS="${SYNC_JOBS:-32}"

# Actual compilation can use the whole machine.
BUILD_JOBS="${BUILD_JOBS:-48}"

# Reasonable for a one-shot sandbox.
CCACHE_SIZE="${CCACHE_SIZE:-64G}"

# User requested a clean build.
CLEAN_BUILD=true

###############################################################################
# LOGGING
###############################################################################

mkdir -p "$OUTPUT_DIR"

LOG_FILE="$OUTPUT_DIR/build.log"

exec > >(tee -a "$LOG_FILE") 2>&1

START_TIME="$(date '+%Y-%m-%d %H:%M:%S')"

echo
echo "============================================================"
echo " LineageOS 23.2 - Xiaomi $DEVICE"
echo " Disposable sandbox build"
echo " Started: $START_TIME"
echo "============================================================"
echo

###############################################################################
# ERROR HANDLING
###############################################################################

trap '
    rc=$?
    echo
    echo "============================================================"
    echo " BUILD SCRIPT EXITED WITH CODE: $rc"
    echo " Log: $LOG_FILE"
    echo " Time: $(date "+%Y-%m-%d %H:%M:%S")"
    echo "============================================================"
    exit "$rc"
' EXIT

###############################################################################
# BASIC CHECKS
###############################################################################

if [[ "${EUID}" -eq 0 ]]; then
    echo "[INFO] Running as root."
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "[ERROR] Not root and sudo is unavailable."
        exit 1
    fi
fi

echo "[INFO] CPU threads : $(nproc)"
echo "[INFO] RAM         : $(free -h | awk '/^Mem:/ {print $2}')"
echo "[INFO] Disk        : $(df -h / | awk 'NR==2 {print $4 " free"}')"
echo

###############################################################################
# DIRECTORY SETUP
###############################################################################

echo "[1/10] Creating build directories..."

mkdir -p "$SOURCE_DIR"
mkdir -p "$OUTPUT_DIR"

cd "$SOURCE_DIR"

###############################################################################
# APT PACKAGE INSTALLATION
#
# Do NOT let one unavailable package kill the entire dependency installation.
###############################################################################

echo
echo "[2/10] Updating Ubuntu package indexes..."

$SUDO apt-get update

# Candidate package list.
#
# The script checks availability individually. This is intentional:
# Ubuntu package naming/availability can differ between releases.
APT_PACKAGES=(
    adb
    bc
    bison
    build-essential
    ccache
    clang
    curl
    flex
    g++
    gcc
    git
    git-lfs
    gnupg
    gperf
    imagemagick
    lib32ncurses-dev
    lib32readline-dev
    lib32z1-dev
    liblz4-tool
    libncurses-dev
    libncurses5-dev
    libncurses5
    libreadline-dev
    libssl-dev
    libxml2
    libxml2-utils
    lzop
    openjdk-17-jdk
    openjdk-21-jdk
    pngcrush
    python3
    python3-pip
    python3-venv
    rsync
    schedtool
    squashfs-tools
    unzip
    xsltproc
    zip
    zlib1g-dev
)

echo
echo "[INFO] Checking available APT packages..."

INSTALLABLE=()
SKIPPED=()

for pkg in "${APT_PACKAGES[@]}"; do
    if apt-cache show "$pkg" >/dev/null 2>&1; then
        INSTALLABLE+=("$pkg")
    else
        SKIPPED+=("$pkg")
    fi
done

echo
echo "[INFO] Installable packages:"
printf '  %s\n' "${INSTALLABLE[@]}"

if ((${#SKIPPED[@]})); then
    echo
    echo "[WARN] Packages unavailable in the current Ubuntu repositories:"
    printf '  %s\n' "${SKIPPED[@]}"
    echo "[WARN] They will be skipped rather than aborting setup."
fi

echo
echo "[INFO] Installing available packages..."

if ((${#INSTALLABLE[@]})); then
    # Use a single apt transaction for speed, now that every package has
    # already been checked for availability.
    $SUDO DEBIAN_FRONTEND=noninteractive \
        apt-get install -y --no-install-recommends "${INSTALLABLE[@]}" \
        || {
            echo
            echo "[WARN] Batch APT installation failed."
            echo "[WARN] Retrying packages individually so one bad package"
            echo "[WARN] cannot prevent the rest from being installed."

            for pkg in "${INSTALLABLE[@]}"; do
                echo "[APT] Installing: $pkg"
                $SUDO DEBIAN_FRONTEND=noninteractive \
                    apt-get install -y --no-install-recommends "$pkg" \
                    || echo "[WARN] Could not install $pkg; continuing."
            done
        }
fi

###############################################################################
# JAVA
###############################################################################

echo
echo "[INFO] Checking Java..."

if command -v java >/dev/null 2>&1; then
    java -version 2>&1 | head -n 2
else
    echo "[WARN] No Java found after package installation."
fi

###############################################################################
# GIT CONFIGURATION
###############################################################################

echo
echo "[3/10] Configuring Git..."

git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"

git config --global protocol.version 2
git config --global core.compression 0
git config --global http.postBuffer 524288000
git config --global fetch.parallel "$SYNC_JOBS"

if command -v git-lfs >/dev/null 2>&1; then
    git lfs install --skip-repo
fi

###############################################################################
# REPO TOOL
###############################################################################

echo
echo "[4/10] Installing/configuring repo..."

if ! command -v repo >/dev/null 2>&1; then
    mkdir -p "$HOME/bin"

    curl -L \
        https://storage.googleapis.com/git-repo-downloads/repo \
        -o "$HOME/bin/repo"

    chmod +x "$HOME/bin/repo"

    export PATH="$HOME/bin:$PATH"

    if ! grep -qF '$HOME/bin' "$HOME/.bashrc" 2>/dev/null; then
        echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
    fi
fi

repo --version

###############################################################################
# LINEAGEOS SOURCE
###############################################################################

echo
echo "[5/10] Initializing LineageOS $LINEAGE_BRANCH..."

cd "$SOURCE_DIR"

if [[ ! -d ".repo" ]]; then
    repo init \
        -u "$MANIFEST_URL" \
        -b "$LINEAGE_BRANCH" \
        --git-lfs \
        --no-clone-bundle
else
    echo "[INFO] Existing .repo directory detected."
fi

###############################################################################
# DEVICE REPOSITORIES
###############################################################################

echo
echo "[6/10] Syncing LineageOS source..."

sync_success=false

# Aggressive first attempt.
for jobs in "$SYNC_JOBS" 24 16 12; do

    # Don't repeat a value.
    case " ${TRIED_SYNC_JOBS:-} " in
        *" $jobs "*) continue ;;
    esac

    TRIED_SYNC_JOBS="${TRIED_SYNC_JOBS:-} $jobs"

    echo
    echo "============================================================"
    echo "[SYNC] Trying repo sync with -j$jobs"
    echo "============================================================"

    if repo sync \
        -c \
        -j"$jobs" \
        --force-sync \
        --no-clone-bundle \
        --no-tags \
        --optimized-fetch \
        --prune \
        --retry-fetches=3
    then
        sync_success=true
        break
    fi

    echo
    echo "[WARN] repo sync failed at -j$jobs."
    echo "[WARN] Retrying with lower concurrency."
done

if [[ "$sync_success" != true ]]; then
    echo "[ERROR] LineageOS source synchronization failed."
    exit 1
fi

###############################################################################
# DIRECT DEVICE TREE CLONES
#
# NO extraction.
# NO proprietary ROM download.
# NO extract-files.py.
# NO extract-files.sh.
###############################################################################

echo
echo "[7/10] Installing supplied device repositories..."

clone_or_update() {
    local url="$1"
    local branch="$2"
    local destination="$3"

    echo
    echo "[GIT] $destination"
    echo "      $url"
    echo "      branch: $branch"

    mkdir -p "$(dirname "$SOURCE_DIR/$destination")"

    if [[ -d "$SOURCE_DIR/$destination/.git" ]]; then
        echo "[GIT] Existing repository found; checking branch."

        git -C "$SOURCE_DIR/$destination" fetch \
            --depth=1 origin "$branch" || true

        git -C "$SOURCE_DIR/$destination" checkout -B "$branch" \
            "origin/$branch"
    else
        rm -rf "$SOURCE_DIR/$destination"

        git clone \
            --depth=1 \
            --single-branch \
            --branch "$branch" \
            "$url" \
            "$SOURCE_DIR/$destination"
    fi
}

clone_or_update \
    "$DEVICE_TREE_URL" \
    "$DEVICE_TREE_BRANCH" \
    "device/xiaomi/chenfeng"

clone_or_update \
    "$KERNEL_TREE_URL" \
    "$KERNEL_TREE_BRANCH" \
    "device/xiaomi/chenfeng-kernel"

clone_or_update \
    "$VENDOR_TREE_URL" \
    "$VENDOR_TREE_BRANCH" \
    "vendor/xiaomi/chenfeng"

clone_or_update \
    "$HARDWARE_TREE_URL" \
    "$HARDWARE_TREE_BRANCH" \
    "hardware/xiaomi"

###############################################################################
# QUICK SANITY CHECK
#
# Deliberately NOT an extraction step.
###############################################################################

echo
echo "[INFO] Performing quick repository sanity check..."

REQUIRED_PATHS=(
    "device/xiaomi/chenfeng"
    "device/xiaomi/chenfeng-kernel"
    "vendor/xiaomi/chenfeng"
    "hardware/xiaomi"
)

for path in "${REQUIRED_PATHS[@]}"; do
    if [[ ! -d "$SOURCE_DIR/$path" ]]; then
        echo "[ERROR] Missing: $path"
        exit 1
    fi
    echo "[OK] $path"
done

if [[ -d "$SOURCE_DIR/vendor/xiaomi/chenfeng/proprietary" ]]; then
    echo "[OK] Vendor proprietary directory exists."
    echo "[INFO] No extraction will be performed."
fi

###############################################################################
# CCACHE
###############################################################################

echo
echo "[8/10] Configuring ccache..."

if command -v ccache >/dev/null 2>&1; then
    export USE_CCACHE=1
    export CCACHE_EXEC="$(command -v ccache)"

    ccache -M "$CCACHE_SIZE"

    # The sandbox is disposable, so don't waste time trying to preserve
    # cache state between machines.
    ccache -o compression=true

    echo "[INFO] ccache size: $CCACHE_SIZE"
    ccache -s || true
else
    echo "[WARN] ccache is unavailable; continuing without it."
fi

###############################################################################
# CLEAN BUILD
###############################################################################

echo
echo "[9/10] Preparing clean build..."

cd "$SOURCE_DIR"

if [[ "$CLEAN_BUILD" == true ]]; then
    echo "[CLEAN] Removing out/ for requested clean build..."
    rm -rf out
fi

# Build environment.
#
# LineageOS 23.2's envsetup handles the correct toolchain and build
# environment. We don't manually force a kernel build.
source build/envsetup.sh

echo
echo "[INFO] Selecting lineage_chenfeng-user..."

lunch "lineage_${DEVICE}-user"

###############################################################################
# BUILD
###############################################################################

echo
echo "============================================================"
echo "[10/10] BUILDING"
echo "============================================================"
echo
echo "[INFO] Device       : $DEVICE"
echo "[INFO] Branch       : $LINEAGE_BRANCH"
echo "[INFO] Build type   : user"
echo "[INFO] Build jobs   : $BUILD_JOBS"
echo "[INFO] Source       : $SOURCE_DIR"
echo "[INFO] Output       : $OUTPUT_DIR"
echo

# mka is Lineage's parallel build wrapper. Use the requested high
# concurrency for this disposable 48-core machine.
#
# 'bacon' produces the normal LineageOS install/OTA package and associated
# build artifacts selected by the device configuration.
mka -j"$BUILD_JOBS" bacon

###############################################################################
# ARTIFACT COLLECTION
###############################################################################

echo
echo "============================================================"
echo " BUILD FINISHED - COLLECTING ARTIFACTS"
echo "============================================================"

PRODUCT_OUT="$SOURCE_DIR/out/target/product/$DEVICE"

if [[ ! -d "$PRODUCT_OUT" ]]; then
    echo "[ERROR] Product output directory not found:"
    echo "        $PRODUCT_OUT"
    exit 1
fi

echo "[INFO] Product output:"
echo "       $PRODUCT_OUT"

# Copy, don't move. Keep Android's expected output structure intact.
find "$PRODUCT_OUT" -maxdepth 1 -type f \
    \( \
        -name '*.zip' \
        -o -name '*.img' \
        -o -name '*.json' \
        -o -name '*.txt' \
        -o -name '*.xml' \
        -o -name '*target_files*.zip' \
    \) \
    -exec cp -av {} "$OUTPUT_DIR/" \;

###############################################################################
# REPORT
###############################################################################

echo
echo "============================================================"
echo " ARTIFACTS"
echo "============================================================"

find "$OUTPUT_DIR" -maxdepth 1 -type f -printf '%f\n' | sort

echo
echo "============================================================"
echo " CCACHE"
echo "============================================================"

ccache -s 2>/dev/null || true

echo
echo "============================================================"
echo " DONE"
echo "============================================================"
echo
echo "Output directory:"
echo "  $OUTPUT_DIR"
echo
echo "Full build log:"
echo "  $LOG_FILE"
echo
echo "Product output:"
echo "  $PRODUCT_OUT"
echo
echo "Finished: $(date '+%Y-%m-%d %H:%M:%S')"
echo
