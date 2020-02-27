#!/bin/sh
# Simple Archlinux live ISO creator that supports AUR packages
# Requirements: git, pacstrap, makepkg, gettext, archiso

# --------------
# Variables
# --------------

# AUR repository settings
AUR_REPO_NAME="aur-local"

# INITCPIO settings
INITCPIO_HOOKS="archiso archiso_shutdown archiso_pxe_common archiso_pxe_nbd archiso_pxe_http archiso_pxe_nfs archiso_loop_mnt"

# Directories
CUR_DIR="$(readlink -f "${0%/*}")"
CONFIG_DIR="$CUR_DIR/configs"
BUILD_DIR="$CUR_DIR/build"
ISO_DIR="$BUILD_DIR/iso"
ROOTFS_DIR="$BUILD_DIR/rootfs"
AUR_CACHE_DIR="$BUILD_DIR/aur/cache"
AUR_REPO_DIR="$BUILD_DIR/aur/repository"

# File paths
PACMAN_CONF_PATH="$BUILD_DIR/pacman.conf"

# --------------
# Helper functions
# --------------

log()
{
    printf "[*] %s...\n" "$@"
}

error()
{
    log "$@"
    exit 1
}

read_package_list()
{
    if [ ! -f "$1" ]
    then
        error "Package list doesn't exist: $1"
    fi

    grep -h -v ^\# "$1"
}

install_packages()
{
    sudo pacstrap -C "$PACMAN_CONF_PATH" -c -d -G -M "$ROOTFS_DIR" $* > /dev/null 2>&1
}

run_chroot()
{
    sudo arch-chroot "$ROOTFS_DIR" "$@"
}

# --------------
# Core logic
# --------------

create_dirs()
{
    log "Creating build directories"
    cd "$CUR_DIR"
    mkdir -p "$ISO_DIR"
    mkdir -p "$ROOTFS_DIR"
    mkdir -p "$AUR_CACHE_DIR" "$AUR_REPO_DIR"
}

build_aur_packages()
{
    log "Building AUR packages"
    PACKAGES="$(read_package_list "$CONFIG_DIR/aur.packages")"
    
    cd "$AUR_CACHE_DIR"

    for PACKAGE in $PACKAGES
    do
        [ -f "$AUR_REPO_DIR/$PACKAGE-"*.pkg.tar.xz ] && continue
        log "-> Building $PACKAGE..."
        
        [ -d "$PACKAGE" ] && rm -rf "$PACKAGE"
        
        log "  -> Cloning repository"
        git clone "https://aur.archlinux.org/$PACKAGE" > /dev/null 2>&1
        
        cd "$AUR_CACHE_DIR/$PACKAGE"
        
        log "  -> Running makepkg"
        makepkg -s > /dev/null 2>&1

        log "  -> Moving to repo"
        mv "$AUR_CACHE_DIR/$PACKAGE/$PACKAGE-"*.pkg.tar.xz "$AUR_REPO_DIR"
        
        cd "$AUR_CACHE_DIR"
    done

    log "Creating local AUR repository"
    repo-add "$AUR_REPO_DIR/$AUR_REPO_NAME.db.tar.gz" "$AUR_REPO_DIR/"*.pkg.tar.xz > /dev/null 2>&1
}

generate_pacman_config()
{
    log "Generating pacman.conf"

    AUR_REPO_DIR="$AUR_REPO_DIR" envsubst < "$CONFIG_DIR/pacman.conf.template" > "$PACMAN_CONF_PATH"
}

install_core_packages()
{
    log "Installing core packages (Might take a while)"

    PACKAGES="$(read_package_list "$CONFIG_DIR/core.packages")"
    install_packages $PACKAGES
}

install_aur_packages()
{
    log "Installing AUR packages (Might take a while)"

    PACKAGES="$(read_package_list "$CONFIG_DIR/aur.packages")"
    install_packages $PACKAGES
}

patch_initcpio()
{
    log "Patching initcpio configuration"

    sudo mkdir -p "$ROOTFS_DIR/etc/initcpio/hooks"
    sudo mkdir -p "$ROOTFS_DIR/etc/initcpio/install"

    for HOOK in $INITCPIO_HOOKS
    do
        log "-> Applying hook $HOOK"
        sudo cp "/usr/lib/initcpio/hooks/$HOOK" "$ROOTFS_DIR/etc/initcpio/hooks"
        sudo cp "/usr/lib/initcpio/install/$HOOK" "$ROOTFS_DIR/etc/initcpio/install"
    done

    # Fix paths in archiso_shutdown
    sudo sed -i"" "s|/usr/lib/initcpio/|/etc/initcpio/|g" "$ROOTFS_DIR/etc/initcpio/install/archiso_shutdown"

    sudo cp "/usr/lib/initcpio/install/archiso_kms" "$ROOTFS_DIR/etc/initcpio/install"
    sudo cp "/usr/lib/initcpio/archiso_shutdown" "$ROOTFS_DIR/etc/initcpio"

    COMPRESSION="xz" envsubst < "$CONFIG_DIR/mkinitcpio.conf.template" | sudo tee "$ROOTFS_DIR/etc/mkinitcpio-iso.conf"
    run_chroot mkinitcpio -c /etc/mkinitcpio-iso.conf -k /boot/vmlinuz-linux -g /boot/zoomeriso.img
}

copy_boot()
{
    log "Copying boot files to iso directory"
    
    mkdir -p "$ISO_DIR/boot/x86_64"

    cp "$ROOTFS_DIR/boot/zoomeriso.img" "$ISO_DIR/boot/x86_64/zoomeriso.img"
    cp "$ROOTFS_DIR/boot/vmlinuz-linux" "$ISO_DIR/boot/x86_64/vmlinuz"
}

main()
{
    create_dirs
    build_aur_packages
    generate_pacman_config
    install_core_packages
    install_aur_packages
    patch_initcpio
    copy_boot
}

main