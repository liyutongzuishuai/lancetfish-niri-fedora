#!/bin/bash

# 0. 拦截空输入：如果什么都没输入直接回车，直接退出
[ -z "$*" ] && exit 0

# 1. 正常桌面应用直通车
if [ -n "$FUZZEL_DESKTOP_FILE_ID" ] || [ -n "$DESKTOP_ENTRY_ID" ]; then
    exec "$@"
fi

INPUT="$*"

# ==========================================
# 网址直达检测 (增强版正则)
# ==========================================
# 兼容了 example.com?query=1 和 example.com#top 这种没有斜杠的情况
URL_REGEX="^(https?://)?([a-zA-Z0-9.-]+\.[a-zA-Z]{2,}|localhost|([0-9]{1,3}\.){3}[0-9]{1,3})(:[0-9]+)?(/.*|\?.*|#.*)?$"

if [[ ! "$INPUT" == *" "* ]] && [[ "$INPUT" =~ $URL_REGEX ]]; then
    TARGET_URL="$INPUT"
    if [[ ! "$INPUT" =~ ^https?:// ]]; then
        TARGET_URL="https://$INPUT"
    fi
    exec xdg-open "$TARGET_URL"
fi

# ==========================================
# 时区检测与默认搜索引擎设置
# ==========================================
DEFAULT_ENGINE="https://www.google.com/search?q="

# 优化：优先读取环境变量，减少 IO 和子进程开销
if [[ -n "$TZ" && "$TZ" == *"Asia/Shanghai"* ]]; then
    DEFAULT_ENGINE="https://www.bing.com/search?q="
else
    # 环境变量没有时再动用系统命令
    if command -v timedatectl >/dev/null 2>&1; then
        SYS_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null)
    elif [ -L /etc/localtime ]; then
        SYS_TZ=$(readlink /etc/localtime)
    else
        SYS_TZ=$(cat /etc/timezone 2>/dev/null)
    fi

    if [[ "$SYS_TZ" == *"Asia/Shanghai"* ]]; then
        DEFAULT_ENGINE="https://www.bing.com/search?q="
    fi
fi

# ==========================================
# 解析智能前缀 (正则拆分 + case 路由)
# ==========================================
# 尝试将输入拆分为 "前缀" + "后续关键词"
if [[ "$INPUT" =~ ^([a-zA-Z0-9_]+)[[:space:]]+(.*) ]]; then
    PREFIX="${BASH_REMATCH[1]}"
    QUERY="${BASH_REMATCH[2]}"
    
    # 集中管理你的搜索引擎前缀，添加新引擎非常简单
    case "$PREFIX" in
        g)    SEARCH_URL="https://www.google.com/search?q=" ;;
        bili) SEARCH_URL="https://search.bilibili.com/all?keyword=" ;;
        yt)   SEARCH_URL="https://www.youtube.com/results?search_query=" ;;
        b)    SEARCH_URL="https://www.bing.com/search?q=" ;;
        gh)   SEARCH_URL="https://github.com/search?q=" ;;
        # 如果前缀不在上面的列表里，当作普通搜索处理（例如输入了 "vue js" 却被正则抓到了 vue 前缀）
        *)    SEARCH_URL="$DEFAULT_ENGINE"; QUERY="$INPUT" ;;
    esac
else
    # 没有前缀，直接使用默认引擎
    SEARCH_URL="$DEFAULT_ENGINE"
    QUERY="$INPUT"
fi

# ==========================================
# URL 编码与执行
# ==========================================
# 优先使用 jq (速度极快)，如果没有安装 jq，则退回到 python3
if command -v jq >/dev/null 2>&1; then
    query_encoded=$(jq -rn --arg x "$QUERY" '$x|@uri')
else
    query_encoded=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$QUERY")
fi

exec xdg-open "${SEARCH_URL}${query_encoded}"
