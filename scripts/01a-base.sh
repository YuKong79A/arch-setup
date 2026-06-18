#!/bin/bash

# ==============================================================================
# 01-base.sh - Base System Configuration
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

check_root

log "Starting Phase 1: Base System Configuration..."

# ------------------------------------------------------------------------------
# 1. Set Global Default Editor
# ------------------------------------------------------------------------------
section "Step 1/5" "Global Default Editor"

TARGET_EDITOR="vim"

if command -v nvim &> /dev/null; then
    TARGET_EDITOR="nvim"
    log "Neovim detected."
    elif command -v nano &> /dev/null; then
    TARGET_EDITOR="nano"
    log "Nano detected."
else
    log "Neovim or Nano not found. Installing Vim..."
    if ! command -v vim &> /dev/null; then
        exe pacman -Syu --noconfirm gvim
    fi
fi

log "Setting EDITOR=$TARGET_EDITOR in /etc/environment..."

if grep -q "^EDITOR=" /etc/environment; then
    exe sed -i "s/^EDITOR=.*/EDITOR=${TARGET_EDITOR}/" /etc/environment
else
    # exe handles simple commands, for redirection we wrap in bash -c or just run it
    # For simplicity in logging, we just run it and log success
    echo "EDITOR=${TARGET_EDITOR}" >> /etc/environment
fi
success "Global EDITOR set to: ${TARGET_EDITOR}"

# ------------------------------------------------------------------------------
# 2. Add Software Repositories
# ------------------------------------------------------------------------------
section "Step 2/5" "Software Repositories"

append_repo_block() {
    local repo_name="$1"
    local repo_body="$2"
    
    if grep -q "^\[$repo_name\]" /etc/pacman.conf; then
        success "$repo_name repository already exists."
    else
        log "Adding $repo_name repository..."
        {
            echo ""
            echo "[$repo_name]"
            printf "%b\n" "$repo_body"
        } >> /etc/pacman.conf
    fi
}

import_pacman_key() {
    local key_id="$1"
    
    if pacman-key --list-keys "$key_id" >/dev/null 2>&1; then
        success "Pacman key already exists: $key_id"
    else
        log "Importing pacman key: $key_id"
        exe pacman-key --recv-keys "$key_id" --keyserver keyserver.ubuntu.com
    fi
    
    log "Locally signing pacman key: $key_id"
    exe pacman-key --lsign-key "$key_id"
}

append_repo_block "archlinuxcn" "Server = https://mirrors.ustc.edu.cn/archlinuxcn/\$arch
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/\$arch
Server = https://mirrors.hit.edu.cn/archlinuxcn/\$arch
Server = https://repo.huaweicloud.com/archlinuxcn/\$arch"

log "Refreshing databases for archlinuxcn keyring..."
exe pacman -Sy --noconfirm
exe pacman -S --noconfirm --needed archlinuxcn-keyring

import_pacman_key "7931B6D628C8D3BA"
append_repo_block "arch4edu" "Server = https://repository.arch4edu.org/\$arch"

if ! grep -q "^\[blackarch\]" /etc/pacman.conf || [ ! -f /etc/pacman.d/blackarch-mirrorlist ]; then
    log "Installing BlackArch repository via official strap.sh..."
    BLACKARCH_TMP="$(mktemp -d)"
    exe curl -fsSLo "$BLACKARCH_TMP/strap.sh" https://blackarch.org/strap.sh
    if ! (
        cd "$BLACKARCH_TMP"
        echo "00688950aaf5e5804d2abebb8d3d3ea1d28525ed strap.sh" | sha1sum -c
    ); then
        error "BlackArch strap.sh checksum verification failed."
        exe rm -rf "$BLACKARCH_TMP"
        exit 1
    fi
    exe chmod +x "$BLACKARCH_TMP/strap.sh"
    exe bash "$BLACKARCH_TMP/strap.sh"
    exe rm -rf "$BLACKARCH_TMP"
else
    success "blackarch repository already configured."
fi

if ! pacman -Q chaotic-keyring >/dev/null 2>&1; then
    log "Installing Chaotic-AUR keyring..."
    import_pacman_key "3056513887B78AEB"
    exe pacman -U --noconfirm https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst
else
    success "chaotic-keyring already installed."
fi

if ! pacman -Q chaotic-mirrorlist >/dev/null 2>&1; then
    log "Installing Chaotic-AUR mirrorlist..."
    exe pacman -U --noconfirm https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst
else
    success "chaotic-mirrorlist already installed."
fi
append_repo_block "chaotic-aur" "Include = /etc/pacman.d/chaotic-mirrorlist"

import_pacman_key "72BF227DD76AE5BF"
append_repo_block "andontie-aur" "Server = https://aur.andontie.net/\$arch"

log "Refreshing package databases after repository setup..."
exe pacman -Sy --noconfirm

# ------------------------------------------------------------------------------
# 3. Enable 32-bit (multilib) Repository
# ------------------------------------------------------------------------------
section "Step 3/5" "Multilib Repository"

if grep -q "^\[multilib\]" /etc/pacman.conf; then
    success "[multilib] is already enabled."
else
    log "Uncommenting [multilib]..."
    # Uncomment [multilib] and the following Include line
    exe sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
    
    log "Refreshing database..."
    exe pacman -Syu
    success "[multilib] enabled."
fi

# ------------------------------------------------------------------------------
# 4. Configure Fonts
# ------------------------------------------------------------------------------
section "Step 4/5" "Fontconfig Profile"

detect_target_user

log "Installing packaged fonts used by current local font setup..."
exe pacman -S --noconfirm --needed \
    fontconfig \
    ttf-misans \
    ttf-lxgw-wenkai \
    otf-comicshanns-nerd \
    ttf-sarasa-gothic \
    noto-fonts \
    noto-fonts-cjk \
    noto-fonts-emoji

FONTCONFIG_RESOURCE_DIR="$SCRIPT_DIR/../resources/fontconfig"

log "Deploying 1:1 user fontconfig and local font files..."
if [ ! -f "$FONTCONFIG_RESOURCE_DIR/.config/fontconfig/fonts.conf" ]; then
    error "Missing fontconfig resource: $FONTCONFIG_RESOURCE_DIR/.config/fontconfig/fonts.conf"
    exit 1
fi

as_user mkdir -p "$HOME_DIR/.config/fontconfig" "$HOME_DIR/.local/share/fonts"
exe as_user cp -rf "$FONTCONFIG_RESOURCE_DIR/.config/fontconfig/fonts.conf" "$HOME_DIR/.config/fontconfig/fonts.conf"
if [ -d "$FONTCONFIG_RESOURCE_DIR/.local/share/fonts" ]; then
    exe as_user cp -rf "$FONTCONFIG_RESOURCE_DIR/.local/share/fonts/." "$HOME_DIR/.local/share/fonts/"
fi
exe chown -R "$TARGET_USER:" "$HOME_DIR/.config/fontconfig" "$HOME_DIR/.local/share/fonts"

log "Refreshing font cache..."
exe as_user fc-cache -fv

info_kv "sans-serif" "$(as_user fc-match sans-serif | head -n 1)" ""
info_kv "serif" "$(as_user fc-match serif | head -n 1)" ""
info_kv "monospace" "$(as_user fc-match monospace | head -n 1)" ""
info_kv "SimSun" "$(as_user fc-match SimSun | head -n 1)" ""
info_kv "Courier New" "$(as_user fc-match 'Courier New' | head -n 1)" ""
success "1:1 user font setup applied."

# ------------------------------------------------------------------------------
# 5. Install AUR Helpers
# ------------------------------------------------------------------------------
section "Step 5/5" "AUR Helpers"

log "Installing paru..."
exe pacman -S --noconfirm --needed base-devel paru
success "paru installed."


# ------------------------------------------------------------------------------

log "Module 01 completed."
