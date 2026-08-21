#!/usr/bin/env bash

set -e

where=$(pwd)
echo "当前工作目录: $where"
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
echo "正在为你添加源..."
sudo dnf copr enable alternateved/keyd -y || true
sudo dnf copr enable lihaohong/yazi -y || true
sudo dnf copr enable phracek/PyCharm -y || true
sudo dnf install -y \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm || true

# ==========================================
# 2. DNF 软件自动检测与补全安装
# ==========================================
PKGS=(
  niri waybar swaybg wl-clipboard fuzzel mako wlsunset
  fcitx5 fcitx5-configtool fcitx5-gtk fcitx5-qt fcitx5-rime
  vim-enhanced nodejs npm foot kitty fish yazi
  bat eza zoxide starship btop fastfetch chafa timg jq gdu xclip
)

echo "正在检测 DNF 软件安装状态..."
MISSING_PKGS=()
for pkg in "${PKGS[@]}"; do
    if ! rpm -q "$pkg" >/dev/null 2>&1; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [ ${#MISSING_PKGS[@]} -eq 0 ]; then
    echo "所有需要的 DNF 软件包已存在，跳过安装。"
else
    echo "发现未安装的软件包: ${MISSING_PKGS[*]}"
    echo "正在使用 DNF 统一安装..."
    sudo dnf install -y --skip-unavailable "${MISSING_PKGS[@]}" || true

    # 二次重试检测机制
    STILL_MISSING=()
    for pkg in "${MISSING_PKGS[@]}"; do
        if ! rpm -q "$pkg" >/dev/null 2>&1; then
            STILL_MISSING+=("$pkg")
        fi
    done

    if [ ${#STILL_MISSING[@]} -gt 0 ]; then
        echo "正在对未成功的软件包尝试逐个重试安装..."
        for pkg in "${STILL_MISSING[@]}"; do
            sudo dnf install -y "$pkg" || echo "警告: 软件包 $pkg 安装失败，请检查包名或网络。"
        done
    fi
fi

# ==========================================
# 3. Flatpak 软件与字体安装
# ==========================================
echo "安装 Zen 浏览器中..."
flatpak install -y flathub app.zen_browser.zen 2>/dev/null || flatpak install -y app.zen_browser.zen 2>/dev/null || true

echo "马上帮你安装漂亮(nerd)的字体..."
if [ -d ./fonts ]; then
    mkdir -p ~/.local/share/fonts/
    cp -rf ./fonts/. ~/.local/share/fonts/
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

cp -rf ./dotfiles/.config/* ~/.config/ 2>/dev/null || true
[ -f ./dotfiles/.vimrc ] && cp -f ./dotfiles/.vimrc ~/.
[ -d ./dotfiles/.local ] && cp -rf ./dotfiles/.local/ ~/.local/
mkdir -p ~/Pictures
[ -f ./Wallpapers/3840px-Van_Gogh_-_Starry_Night_-_Google_Art_Project.jpg ] && cp -f ./Wallpapers/3840px-Van_Gogh_-_Starry_Night_-_Google_Art_Project.jpg ~/Pictures/

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
    curl -s https://raw.githubusercontent.com/oh-my-fish/oh-my-fish/master/bin/install | fish
    fish -c "omf install agnoster; omf theme agnoster" 2>/dev/null || true
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
