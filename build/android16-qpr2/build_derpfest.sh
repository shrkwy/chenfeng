#!/bin/bash
banner() {
    clear

    echo -e "${CYAN}${BOLD}"
    echo "╔═════════════════════════════════════════════════════════════════════════╗"
    echo "║                                                                                      ║"
    echo "║    ██████╗ ███████╗██████╗ ██████╗ ███████╗███████╗███████╗████████╗      ║"
    echo "║    ██╔══██╗██╔════╝██╔══██╗██╔══██╗██╔════╝██╔════╝██╔════╝╚══██╔══╝     ║"
    echo "║    ██║  ██║█████╗  ██████╔╝██████╔╝█████╗  █████╗  ███████╗   ██║           ║"
    echo "║    ██║  ██║██╔══╝  ██╔══██╗██╔═══╝ ██╔══╝  ██╔══╝  ╚════██║   ██║           ║"
    echo "║    ██████╔╝███████╗██║  ██║██║     ██║     ███████╗███████║   ██║           ║"
    echo "║    ╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝     ╚══════╝╚══════╝   ╚═╝            ║"
    echo "║                                                                                      ║"
    echo "║                             D E R P F E S T                                          ║"
    echo "║                        Automated Release Builder                                     ║"
    echo "║                                                                                      ║"
    echo "╠═════════════════════════════════════════════════════════════════════════╣"
    echo "║  Device     : Xiaomi Civi 4 Pro / chenfeng                                           ║"
    echo "║  Build      : bp4a-user                                                              ║"
    echo "║  Branch     : 16.2                                                                   ║"
    echo "╚═════════════════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

banner;

echo "============================================="
echo "    cleaning up previous local manifests    "
echo "============================================="

rm -rf .repo/local_manifests;
rm -rf out/soong/.intermediates/system/sepolicy;


echo ""
echo "====================="
echo "      repo init      "
echo "====================="

repo init -u https://github.com/DerpFest-AOSP/android_manifest.git -b 16.2 --depth=1 --git-lfs;
git clone https://github.com/shrkwy/chenfeng_manifest.git -b lineage-23.2 --depth=1 .repo/local_manifests;


echo ""
echo "==================="
echo "     repo sync     "
echo "==================="

/opt/crave/resync.sh;

# sudo apt-get update;
# sudo apt-get install -y patchelf coreutils ccache;

export BUILD_USERNAME=Marcy
export BUILD_HOSTNAME=foss

rm -rf build/soong/fsgen;


echo ""
echo "===================="
echo "   starting build  "
echo "===================="

. build/envsetup.sh;
lunch lineage_chenfeng-bp4a-user;
mka derp -j$(nproc --all);


echo ""
echo "=========================================="
echo "      uploading to sharing platforms      "
echo "=========================================="

ZIP=$(find out/target/product/chenfeng -maxdepth 1 -type f -name "*.zip" | head -n 1)

if [ -n "$ZIP" ]; then
    echo "Uploading: $ZIP..."
    wget https://raw.githubusercontent.com/shrkwy/chenfeng/refs/heads/main/tools/upload_util.sh
    chmod +x upload_util.sh
    ./upload_util.sh "$ZIP"
else
    echo "No ROM ZIP found in artifacts!"
    exit 1
fi
