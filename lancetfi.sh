#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "当前工作目录: $SCRIPT_DIR"
echo "输入一下 sudo 密码哦"
sudo -v

# 保持 sudo 权限在后台不失效
(while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done) 2>/dev/null &

echo "3"
sleep 1
echo "2"
sleep 1
echo "start"

# ==========================================
# 1. 配置软件源 (COPR & RPM Fusion)
# ==========================================
echo "正在为你添加软件源..."

# 启用 COPR 仓库
sudo dnf copr enable alternateved/keyd -y || true
sudo dnf copr enable lihaohong/yazi -y || true
sudo dnf copr enable phracek/PyCharm -y || true

# 启用 RPM Fusion 仓库（必须在安装软件前完成）
if ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
    echo "正在启用 RPM Fusion 仓库..."
    sudo dnf install -y \
      https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
      https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm || true
fi

# 刷新 DNF 缓存，确保新添加的仓库生效
echo "正在刷新软件包缓存..."
sudo dnf makecache --refresh >/dev/null 2>&1 || true

# ==========================================
# 2. DNF 软件自动检测与补全安装
# ==========================================
# 完整的软件包列表（合并了原版的完整列表）
TARGET_SOFTWARE=(
  # Niri 桌面核心组件
  "niri" "waybar" "swaybg" "wl-clipboard" "fuzzel" "mako" "wlsunset"
  # 输入法
  "fcitx5" "fcitx5-configtool" "fcitx5-gtk" "fcitx5-qt" "fcitx5-rime"
  # 终端与 Shell
  "foot" "kitty" "fish" "vim-enhanced" "neovim"
  # 开发工具
  "nodejs20" "nodejs20-npm"
  # CLI 工具
  "bat" "eza" "zoxide" "starship" "btop" "fastfetch" "chafa" "timg" "jq" "gdu" "xclip"
  # 文件管理
  "yazi" "thunar" "file-roller" "gvfs-smb" "gvfs-mtp" "gvfs-gphoto2"
  "gnome-keyring" "tumbler" "poppler-glib" "ffmpegthumbnailer"
  "xdg-desktop-portal-gtk" "xdg-desktop-portal-gnome" "python3-pillow"
  "gstreamer1-plugins-base" "gstreamer1-plugins-good" "gstreamer1-plugin-libav"
  "thunar-archive-plugin" "thunar-volman"
  # 字体
  "google-noto-fonts-common" "google-noto-sans-cjk-fonts" "jetbrains-mono-nerd-fonts"
  # 桌面额外工具
  "breeze-cursor-theme" "mpv" "wf-recorder" "imv" "pavucontrol" "strace" "firefox"
)

# 关键软件包 - 失败则中止安装（Niri 桌面环境核心组件）
CRITICAL_SOFTWARE=(
  "niri" "waybar" "swaybg" "wl-clipboard" "fuzzel" "mako" "wlsunset"
  "fcitx5" "fcitx5-configtool" "fcitx5-gtk" "fcitx5-qt" "fcitx5-rime"
  "vim-enhanced" "neovim" "nodejs20" "nodejs20-npm" "foot" "kitty"
)

echo "正在检测 DNF 软件安装状态..."
MISSING_PKGS=()
for pkg in "${TARGET_SOFTWARE[@]}"; do
    if ! rpm -q "$pkg" >/dev/null 2>&1; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [ ${#MISSING_PKGS[@]} -eq 0 ]; then
    echo "所有需要的 DNF 软件包已存在，跳过安装。"
else
    echo "发现未安装的软件包: ${MISSING_PKGS[*]}"

    # 分离关键包和普通包
    CRITICAL_MISSING=()
    NORMAL_MISSING=()
    for pkg in "${MISSING_PKGS[@]}"; do
        is_critical=0
        for critical_pkg in "${CRITICAL_SOFTWARE[@]}"; do
            if [[ "$pkg" == "$critical_pkg" ]]; then
                is_critical=1
                break
            fi
        done
        if [[ $is_critical -eq 1 ]]; then
            CRITICAL_MISSING+=("$pkg")
        else
            NORMAL_MISSING+=("$pkg")
        fi
    done

    # 先安装关键包
    if [ ${#CRITICAL_MISSING[@]} -gt 0 ]; then
        echo "正在安装关键软件包: ${CRITICAL_MISSING[*]}"
        if ! sudo dnf install -y "${CRITICAL_MISSING[@]}"; then
            echo "错误: 关键软件包安装失败，终止安装。"
            exit 1
        fi
    fi

    # 再安装普通包
    if [ ${#NORMAL_MISSING[@]} -gt 0 ]; then
        echo "正在安装可选软件包: ${NORMAL_MISSING[*]}"
        sudo dnf install -y --skip-unavailable "${NORMAL_MISSING[@]}"
    fi

    # 二次重试检测机制
    STILL_MISSING=()
    for pkg in "${MISSING_PKGS[@]}"; do
        if ! rpm -q "$pkg" >/dev/null 2>&1; then
            STILL_MISSING+=("$pkg")
        fi
    done

    if [ ${#STILL_MISSING[@]} -gt 0 ]; then
        echo "正在对未成功的软件包尝试逐个重试安装..."
        CRITICAL_FAILED=()
        OPTIONAL_FAILED=()
        for pkg in "${STILL_MISSING[@]}"; do
            sudo dnf install -y "$pkg" || {
                # 检查是否为关键包
                is_critical=0
                for critical_pkg in "${CRITICAL_SOFTWARE[@]}"; do
                    if [[ "$pkg" == "$critical_pkg" ]]; then
                        is_critical=1
                        break
                    fi
                done
                if [[ $is_critical -eq 1 ]]; then
                    CRITICAL_FAILED+=("$pkg")
                else
                    OPTIONAL_FAILED+=("$pkg")
                fi
                echo "警告: 软件包 $pkg 安装失败，请检查包名或网络。"
            }
        done

        if [ ${#CRITICAL_FAILED[@]} -gt 0 ]; then
            echo "错误: 以下关键软件包安装失败: ${CRITICAL_FAILED[*]}"
            exit 1
        fi

        if [ ${#OPTIONAL_FAILED[@]} -gt 0 ]; then
            echo "警告: 以下可选软件包安装失败，请检查网络或软件源: ${OPTIONAL_FAILED[*]}"
            echo "脚本将继续执行，但由于软件缺失，部分功能可能无法正常工作。"
        fi
    fi
fi

# ==========================================
# 3. Flatpak 软件与字体安装
# ==========================================
echo "安装 Zen 浏览器中..."
flatpak install -y flathub app.zen_browser.zen 2>/dev/null || flatpak install -y app.zen_browser.zen 2>/dev/null || true

echo "马上帮你安装漂亮(nerd)的字体..."
if [ -d "$SCRIPT_DIR/fonts" ]; then
    mkdir -p ~/.local/share/fonts/
    cp -rf "$SCRIPT_DIR/fonts/." ~/.local/share/fonts/
    sudo fc-cache -fv >/dev/null 2>&1
fi

# ==========================================
# 4. 目录重命名与 Dotfiles 部署
# ==========================================
echo "正在把你的'音乐'、'下载'、'视频'等目录换成英文..."
sed -i 's/桌面/Desktop/g; s/下载/Downloads/g; s/模板/Templates/g; s/公共/Public/g; s/文档/Documents/g; s/音乐/Music/g; s/图片/Pictures/g; s/视频/Videos/g' ~/.config/user-dirs.dirs 2>/dev/null

declare -A DIRS=(["桌面"]="Desktop" ["下载"]="Downloads" ["模板"]="Templates" ["公共"]="Public" ["文档"]="Documents" ["音乐"]="Music" ["图片"]="Pictures" ["视频"]="Videos")
for zh in "${!DIRS[@]}"; do
    [ -d ~/"$zh" ] && mv ~/"$zh" ~/"${DIRS[$zh]}"
done

echo "正在备份并写入新的配置文件..."
mkdir -p .yourconfigbak
cp -rf ~/.config/. .yourconfigbak/ 2>/dev/null || true
[ -f ~/.vimrc ] && cp -f ~/.vimrc ~/.yourconfigbak/

cp -rf "$SCRIPT_DIR/dotfiles/.config/"* ~/.config/ 2>/dev/null || true
[ -f "$SCRIPT_DIR/dotfiles/.vimrc" ] && cp -f "$SCRIPT_DIR/dotfiles/.vimrc" ~/.
[ -d "$SCRIPT_DIR/dotfiles/.local" ] && cp -rf "$SCRIPT_DIR/dotfiles/.local/" ~/.local/
mkdir -p ~/Pictures
[ -f "$SCRIPT_DIR/Wallpapers/3840px-Van_Gogh_-_Starry_Night_-_Google_Art_Project.jpg" ] && cp -f "$SCRIPT_DIR/Wallpapers/3840px-Van_Gogh_-_Starry_Night_-_Google_Art_Project.jpg" ~/Pictures/

echo "正在适配配置文件里的用户名..."
replace_count=0
cd "$HOME" || true
while IFS= read -r -d '' file; do
    if grep -q "/home/lancetfish" "$file" 2>/dev/null; then
        sed -i "s|/home/lancetfish|/home/$USER|g" "$file"
        ((replace_count++))
    fi
done < <(find .config .local -type f -print0 2>/dev/null)
echo "已将 $replace_count 个文件中的占位用户名替换为: $USER"

# ==========================================
# 5. Shell / Vim / 外观微调
# ==========================================
echo "正在将默认 Shell 修改为 fish..."
FISH_PATH="$(command -v fish || true)"
if [ -n "$FISH_PATH" ]; then
    grep -qx "$FISH_PATH" /etc/shells || echo "$FISH_PATH" | sudo tee -a /etc/shells >/dev/null
    sudo chsh -s "$FISH_PATH" "$USER"
fi

echo "正在帮你改为深色模式及配置 Flatpak..."
if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface color-scheme "prefer-dark" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme "adw-gtk3-dark" 2>/dev/null || true
    gsettings set org.gnome.desktop.wm.preferences button-layout ":close" 2>/dev/null || true
fi

if command -v flatpak >/dev/null 2>&1; then
    flatpak override --user --filesystem=xdg-data/themes 2>/dev/null || true
    flatpak override --user --filesystem="$HOME/.themes" 2>/dev/null || true
    flatpak override --user --filesystem=xdg-config/gtk-4.0 2>/dev/null || true
    flatpak override --user --filesystem=xdg-config/gtk-3.0 2>/dev/null || true
    flatpak override --user --env=GTK_THEME=adw-gtk3-dark 2>/dev/null || true
    flatpak override --user --filesystem=xdg-config/fontconfig 2>/dev/null || true
fi

if command -v vim >/dev/null 2>&1; then
    if [[ ! -f "$HOME/.vim/autoload/plug.vim" ]]; then
        curl -fLo "$HOME/.vim/autoload/plug.vim" --create-dirs \
            https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim 2>/dev/null || true
    fi
    vim +PlugInstall +qall >/dev/null 2>&1 || true
fi

echo "安装美味的 omf..."
if command -v fish >/dev/null 2>&1; then
    # 使用官方完整 URL 安装，避免短链接失效
    if curl -s https://raw.githubusercontent.com/oh-my-fish/oh-my-fish/master/bin/install | fish; then
        # 验证 OMF 是否真正安装成功
        OMF_INIT="$HOME/.local/share/omf/init.fish"
        if [[ -f "$OMF_INIT" && -s "$OMF_INIT" ]] && ! grep -P '\\x00' "$OMF_INIT" 2>/dev/null; then
            echo "OMF 安装成功。"
            fish -c "omf install agnoster; omf theme agnoster" 2>/dev/null || echo "无法安装 agnoster 主题。"
        else
            echo "OMF 安装似乎成功但文件损坏或为空，请尝试手动安装。"
        fi
    else
        echo "OMF 安装失败，请检查网络连接。"
    fi
fi

echo "正在清理应用菜单里的终端工具图标..."
apps_to_hide=(
    "lstopo.desktop" "avahi-discover.desktop" "qv4l2.desktop" "qvidcap.desktop"
    "bssh.desktop" "org.fcitx.Fcitx5.desktop" "yazi.desktop" "btop.desktop"
    "vim.desktop" "nvim.desktop" "nvtop.desktop" "mpv.desktop"
)
mkdir -p "$HOME/.local/share/applications"
for app in "${apps_to_hide[@]}"; do
    if [[ -f "/usr/share/applications/$app" ]]; then
        cp -f "/usr/share/applications/$app" "$HOME/.local/share/applications/"
        echo "NoDisplay=true" >> "$HOME/.local/share/applications/$app"
    fi
done

echo "已经安装成功了 享受美好 fedora 生活吧"
fastfetch 2>/dev/null || true