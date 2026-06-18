#!/usr/bin/env bash

# ==============================================================================
# 脚本功能说明 (Bootstrap Script for Shorin Arch Setup - PR #23 Edition)
# 1. 环境防御：严格检测操作系统(仅限Linux)与系统架构(仅限x86_64)。
# 2. 权限自适应：智能识别 root/普通用户，防止 Live CD 环境下缺少 sudo 导致崩溃。
# 3. 依赖隐身：静默准备 git。
# 4. PR 拉取：从远程仓库获取指定 Pull Request (#23) 并合并到本地。
# 5. 一键引导：无缝切换目录并接管标准输入，提权执行核心安装脚本。
# ==============================================================================

# 启用严格模式：遇到错误、未定义变量或管道错误时立即退出
set -euo pipefail

# --- [颜色配置] ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- [环境检测与准备] ---

# 1. 检查是否为 Linux 内核
if [ "$(uname -s)" != "Linux" ]; then
    printf "%bError: This installer only supports Linux systems.%b\n" "$RED" "$NC"
    exit 1
fi

# 2. 检查架构是否匹配 (仅允许 x86_64)
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
    printf "%bError: Unsupported architecture: %s%b\n" "$RED" "$ARCH" "$NC"
    printf "This installer is strictly designed for x86_64 (amd64) systems only.\n"
    exit 1
fi
ARCH_NAME="amd64"

# 3. 极简提权封装 (KISS 原则：是 root 直接跑，不是 root 才加 sudo)
run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        if ! command -v sudo >/dev/null 2>&1; then
            printf "%bError: 'sudo' command not found. Please run this script as root.%b\n" "$RED" "$NC"
            exit 1
        fi
        sudo "$@"
    fi
}

# --- [配置区域] ---
TARGET_DIR="/tmp/shorin-arch-setup"
PR_NUMBER="23"
REPO_URL="https://github.com/SHORiN-KiWATA/shorin-arch-setup.git"

printf "%b>>> Preparing to install from PR #%s on %s%b\n" "$BLUE" "$PR_NUMBER" "$ARCH_NAME" "$NC"

# --- [执行流程] ---

# 1. 依赖检查与静默安装
MISSING_PKGS=()

if ! command -v git >/dev/null 2>&1; then
    MISSING_PKGS+=("git")
fi

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    run_as_root pacman -Sy --noconfirm --needed "${MISSING_PKGS[@]}" >/dev/null 2>&1
fi

# 2. 清理旧目录并重新创建
if [ -d "$TARGET_DIR" ]; then
    run_as_root rm -rf "$TARGET_DIR"
fi
mkdir -p "$TARGET_DIR"

# 3. 克隆仓库
printf "Cloning repository to %s...\n" "$TARGET_DIR"
if ! git clone "$REPO_URL" "$TARGET_DIR"; then
    printf "%bError: Failed to clone repository.%b\n" "$RED" "$NC"
    exit 1
fi

# 4. 配置本地 Git 用户信息（用于合并提交）
cd "$TARGET_DIR"
git config user.email "t@t.com"
git config user.name "t"

# 5. 获取并合并 PR #23
printf "Fetching and merging PR #%s...\n" "$PR_NUMBER"
if ! git fetch origin pull/${PR_NUMBER}/head:pr-${PR_NUMBER}; then
    printf "%bError: Failed to fetch PR #%s.%b\n" "$RED" "$PR_NUMBER" "$NC"
    exit 1
fi

if ! git merge --no-edit pr-${PR_NUMBER}; then
    printf "%bError: Failed to merge PR #%s.%b\n" "$RED" "$PR_NUMBER" "$NC"
    exit 1
fi

printf "%b\nSuccessfully merged PR #%s.%b\n" "$GREEN" "$PR_NUMBER" "$NC"

# 6. 运行安装
printf "Starting installer...\n"
run_as_root bash install.sh < /dev/tty