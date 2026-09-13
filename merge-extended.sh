#!/usr/bin/env bash
# =============================================================================
# merge-extended.sh — 把 OreUIForEveryone-1.21.1-Extended 的 assets 按需合并进本仓库
#
# 源仓库: https://github.com/OnDreamQwQ/OreUIForEveryone-1.21.1-Extended
# 策略  : 命名空间动态扫描 + 多选合并; 只增不删;
#         同路径但内容不同的文件逐个询问(默认保留本仓库版本)
#
# 用法:
#   ./merge-extended.sh                       # 交互式选择要合并哪些命名空间
#   ./merge-extended.sh --dry-run             # 只打印计划, 不改任何文件
#   ./merge-extended.sh --yes                 # 用默认勾选(无冲突的命名空间)直接执行
#   ./merge-extended.sh --only mekanism,curios --yes
#   ./merge-extended.sh --exclude lightmanscurrency
#   ./merge-extended.sh --prefer extended     # 冲突一律用源仓库(Extended)版本
#   ./merge-extended.sh --pull                # 先拉取源仓库最新提交再合并
#
# 参数:
#   --src <路径>        源仓库路径(默认 ~/桌面/orked-clone/OreUIForEveryone-1.21.1-Extended)
#   --only <a,b>        只处理这些命名空间(逗号分隔, 可重复; 写错会报错退出)
#   --exclude <路径,a/b> 排除命名空间或单个文件(相对 assets 的路径, 可重复)
#   --prefer <side>     冲突策略: extended=用源仓库 | fork=保留本仓库; 默认逐个询问
#   --split-commits     每个命名空间一个提交(默认合并成一次提交)
#   --dry-run           只打印计划并退出
#   -y, --yes           跳过确认(非交互模式; 选择 = 默认勾选)
#   -h, --help          显示本帮助
# =============================================================================

set -uo pipefail

EXTENDED_URL="https://github.com/OnDreamQwQ/OreUIForEveryone-1.21.1-Extended.git"
EXTENDED_NAME="OreUIForEveryone-1.21.1-Extend"
DEFAULT_SRC="$HOME/桌面/orked-clone/OreUIForEveryone-1.21.1-Extended"
CONFLICT_DIR="${TMPDIR:-/tmp}/extended-conflicts"

SRC="$DEFAULT_SRC"
PULL=0
ONLY=()
EXCLUDE=()
PREFER=""
ASSUME_YES=0
SPLIT=0
DRY=0

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "${BASH_SOURCE[0]}"; }

# ---------------------------------------------------------------- 参数解析
while [ $# -gt 0 ]; do
    case "$1" in
        --src)     SRC="${2:-}"; shift 2 ;;
        --src=*)   SRC="${1#*=}"; shift ;;
        --pull)    PULL=1; shift ;;
        --only)    IFS=',' read -ra _t <<< "${2:-}"; ONLY+=("${_t[@]}"); shift 2 ;;
        --only=*)  IFS=',' read -ra _t <<< "${1#*=}"; ONLY+=("${_t[@]}"); shift ;;
        --exclude) IFS=',' read -ra _t <<< "${2:-}"; EXCLUDE+=("${_t[@]}"); shift 2 ;;
        --exclude=*) IFS=',' read -ra _t <<< "${1#*=}"; EXCLUDE+=("${_t[@]}"); shift ;;
        --prefer)  PREFER="${2:-}"; shift 2 ;;
        --prefer=*) PREFER="${1#*=}"; shift ;;
        --split-commits) SPLIT=1; shift ;;
        --dry-run) DRY=1; shift ;;
        -y|--yes)  ASSUME_YES=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "未知参数: $1 (用 --help 查看用法)"; exit 2 ;;
    esac
done

case "$PREFER" in
    ""|extended|fork) ;;
    *) echo "错误: --prefer 只能是 extended 或 fork"; exit 2 ;;
esac

# ---------------------------------------------------------------- 仓库与安全检查
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)" || {
    echo "错误: 脚本不在 git 仓库内。"; exit 1;
}
cd "$ROOT"
FORK_ASSETS="$ROOT/assets"
[ -d "$FORK_ASSETS" ] || { echo "错误: 本仓库没有 assets 目录"; exit 1; }

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" = "HEAD" ] && { echo "错误: 当前处于 detached HEAD, 请先切到分支。"; exit 1; }

if [ "$DRY" -eq 0 ]; then
    if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
        echo "错误: 检测到未完成的合并, 请先处理(git status / git merge --abort)。"; exit 1
    fi
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "错误: 工作区有未提交的改动, 请先 commit 或 stash。"; exit 1
    fi
fi
echo "==> 目标仓库: $ROOT (分支 $BRANCH)"

# ---------------------------------------------------------------- 源仓库准备
if [ ! -d "$SRC" ]; then
    echo "==> 源仓库不存在, 克隆到 $SRC"
    mkdir -p "$(dirname "$SRC")"
    git clone "$EXTENDED_URL" "$SRC" || { echo "错误: 克隆失败。"; exit 1; }
fi
[ -d "$SRC/assets" ] || { echo "错误: $SRC 下没有 assets 目录。"; exit 1; }

SRC_SHA="unknown"
if git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1; then
    if [ "$PULL" -eq 1 ]; then
        echo "==> 拉取源仓库最新提交..."
        git -C "$SRC" pull --ff-only || { echo "错误: pull 失败(源仓库可能有本地改动), 请手动处理。"; exit 1; }
    fi
    SRC_SHA="$(git -C "$SRC" rev-parse --short HEAD)"
    if [ -n "$(git -C "$SRC" status --porcelain -- assets 2>/dev/null)" ]; then
        echo "警告: 源仓库 assets 内有未提交改动, 本次合并内容不对应任何已提交状态。"
    fi
else
    echo "警告: $SRC 不是 git 仓库, 无法记录来源 commit。"
fi
echo "==> 源仓库: $SRC @ $SRC_SHA"

# ---------------------------------------------------------------- 扫描 / 分类
declare -A NS_NEW NS_SAME NS_CONF NEW_LIST CONF_LIST
namespaces=()
mapfile -t namespaces < <(cd "$SRC/assets" && find . -maxdepth 1 -mindepth 1 -type d | sed 's|^\./||' | sort)
[ ${#namespaces[@]} -gt 0 ] || { echo "错误: 源仓库 assets 下没有命名空间目录。"; exit 1; }

is_excluded() {   # $1: 相对 assets 的路径(ns 或 ns/子路径)
    local p="${1%/}" e
    for e in "${EXCLUDE[@]}"; do
        e="${e%/}"
        [ -n "$e" ] || continue
        [ "$p" = "$e" ] && return 0
        case "$p" in "$e"/*) return 0 ;; esac
    done
    return 1
}

in_only() {       # $1: 命名空间
    [ ${#ONLY[@]} -eq 0 ] && return 0
    local n
    for n in "${ONLY[@]}"; do [ "$n" = "$1" ] && return 0; done
    return 1
}

selected_ns=()
for ns in "${namespaces[@]}"; do
    in_only "$ns" || continue
    if is_excluded "$ns"; then echo "==> 已排除(命令行): $ns"; continue; fi
    NS_NEW[$ns]=0; NS_SAME[$ns]=0; NS_CONF[$ns]=0; NEW_LIST[$ns]=""; CONF_LIST[$ns]=""
    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        is_excluded "$ns/$rel" && continue
        s="$SRC/assets/$ns/$rel"; f="$FORK_ASSETS/$ns/$rel"
        if [ ! -e "$f" ]; then
            NS_NEW[$ns]=$((NS_NEW[$ns] + 1)); NEW_LIST[$ns]+="$rel"$'\n'
        elif cmp -s "$s" "$f"; then
            NS_SAME[$ns]=$((NS_SAME[$ns] + 1))
        else
            NS_CONF[$ns]=$((NS_CONF[$ns] + 1)); CONF_LIST[$ns]+="$rel"$'\n'
        fi
    done < <(cd "$SRC/assets/$ns" && find . -type f | sed 's|^\./||' | sort)
    if [ $((NS_NEW[$ns] + NS_SAME[$ns] + NS_CONF[$ns])) -eq 0 ]; then
        echo "==> 跳过(无可合并文件): $ns"; continue
    fi
    selected_ns+=("$ns")
done

if [ ${#ONLY[@]} -gt 0 ] && [ ${#selected_ns[@]} -eq 0 ]; then
    echo "错误: --only 指定的命名空间在源仓库里不存在: ${ONLY[*]}"; exit 1
fi
[ ${#selected_ns[@]} -gt 0 ] || { echo "错误: 没有可合并的命名空间。"; exit 1; }

# ---------------------------------------------------------------- 默认勾选(数据驱动)
# 规则: 存在同路径冲突的命名空间默认不勾, 其余默认全勾
declare -A ON
for ns in "${selected_ns[@]}"; do
    if [ "${NS_CONF[$ns]}" -eq 0 ]; then ON[$ns]=1; else ON[$ns]=0; fi
done

png_dims() {      # 只读 PNG 头, 失败输出 '-'
    local hex
    [ "${1##*.}" = "png" ] || { echo "-"; return; }
    hex="$(od -An -tx1 -j16 -N8 "$1" 2>/dev/null | tr -d ' \n')"
    [ ${#hex} -eq 16 ] || { echo "-"; return; }
    echo "$((16#${hex:0:8}))x$((16#${hex:8:8}))"
}

# 中文是双宽字符, printf 按字节算宽度会错位, 这里按显示宽度补空格
vislen() { local s="$1" n=0 i c; for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"; if [[ "$c" == [!\ -~] ]]; then n=$((n + 2)); else n=$((n + 1)); fi; done; echo "$n"; }
rpad() { local s="$1" w="$2" l; l=$(vislen "$s"); printf '%s' "$s"
    while [ "$l" -lt "$w" ]; do printf ' '; l=$((l + 1)); done; }
lpad() { local s="$1" w="$2" l; l=$(vislen "$s")
    while [ "$l" -lt "$w" ]; do printf ' '; l=$((l + 1)); done; printf '%s' "$s"; }

choose_defaults() {
    chosen=()
    for ns in "${selected_ns[@]}"; do [ "${ON[$ns]}" -eq 1 ] && chosen+=("$ns"); done
    echo "==> 采用默认勾选(${#chosen[@]} 个命名空间)"
}

choose_menu() {   # 纯 bash 编号菜单
    local ans tok i ns mark
    while :; do
        echo
        echo "命名空间 (x=已勾选):"
        i=0
        for ns in "${selected_ns[@]}"; do
            i=$((i + 1))
            mark=" "; [ "${ON[$ns]}" -eq 1 ] && mark="x"
            printf '  [%s] %2d) %-20s 新增%-4s 相同%-4s 冲突%s\n' \
                "$mark" "$i" "$ns" "${NS_NEW[$ns]}" "${NS_SAME[$ns]}" "${NS_CONF[$ns]}"
        done
        echo "  输入编号(空格/逗号分隔)切换勾选; a=全选 n=全不选; 回车=确认; q=取消"
        read -r -p "> " ans || { echo "已取消。"; exit 0; }
        case "$ans" in
            "")  break ;;
            q|Q) echo "已取消。"; exit 0 ;;
            a|A) for ns in "${selected_ns[@]}"; do ON[$ns]=1; done ;;
            n|N) for ns in "${selected_ns[@]}"; do ON[$ns]=0; done ;;
            *)   for tok in ${ans//,/ }; do
                     if [[ "$tok" =~ ^[0-9]+$ ]] && [ "$tok" -ge 1 ] && [ "$tok" -le ${#selected_ns[@]} ]; then
                         ns="${selected_ns[$((tok - 1))]}"
                         ON[$ns]=$((1 - ${ON[$ns]}))
                     fi
                 done ;;
        esac
    done
    chosen=()
    for ns in "${selected_ns[@]}"; do [ "${ON[$ns]}" -eq 1 ] && chosen+=("$ns"); done
}

choose_whiptail() {  # whiptail 勾选框
    local out rc ns st desc
    local wl=()
    for ns in "${selected_ns[@]}"; do
        desc="$ns  (新增${NS_NEW[$ns]} 相同${NS_SAME[$ns]} 冲突${NS_CONF[$ns]})"
        st=OFF; [ "${ON[$ns]}" -eq 1 ] && st=ON
        wl+=("$ns" "$desc" "$st")
    done
    out="$(whiptail --title "选择要合并的命名空间 (共 ${#selected_ns[@]} 个)" \
            --checklist "空格=勾选/取消, 回车=确认。含冲突的默认不勾。" \
            22 100 14 "${wl[@]}" 3>&1 1>&2 2>&3)"
    rc=$?
    [ "$rc" -ne 0 ] && { echo "已取消。"; exit 0; }
    out="${out//\"/}"
    chosen=()
    for ns in $out; do chosen+=("$ns"); done
}

if [ ${#ONLY[@]} -gt 0 ]; then
    # --only 是明确指定, 不再套用"有冲突就默认不勾"的规则, 也不再弹选择界面
    echo "==> --only 指定: ${ONLY[*]}"
    chosen=("${selected_ns[@]}")
elif [ "$ASSUME_YES" -eq 1 ]; then
    choose_defaults
elif [ -t 0 ] && [ -t 1 ]; then
    if command -v whiptail >/dev/null 2>&1; then choose_whiptail; else choose_menu; fi
elif [ "$DRY" -eq 1 ]; then
    choose_defaults       # --dry-run 在管道/非交互下用默认勾选, 便于查看计划
else
    echo "错误: 非交互环境无法选择, 请加 --yes (用默认勾选) 或 --only <命名空间>。"; exit 1
fi

if [ ${#chosen[@]} -eq 0 ]; then echo "==> 没有选择任何命名空间, 无事可做。"; exit 0; fi

# ---------------------------------------------------------------- 计划预览
echo
echo "==> 执行计划"
printf '  %s %s %s %s\n' "$(rpad "命名空间" 22)" "$(lpad "新增" 6)" "$(lpad "相同" 6)" "$(lpad "冲突" 6)"
total_new=0; total_same=0; total_conf=0
for ns in "${chosen[@]}"; do
    printf '  %s %s %s %s\n' "$(rpad "$ns" 22)" "$(lpad "${NS_NEW[$ns]}" 6)" \
        "$(lpad "${NS_SAME[$ns]}" 6)" "$(lpad "${NS_CONF[$ns]}" 6)"
    total_new=$((total_new + NS_NEW[$ns]))
    total_same=$((total_same + NS_SAME[$ns]))
    total_conf=$((total_conf + NS_CONF[$ns]))
done
echo "  合计: 新增 $total_new, 相同(跳过) $total_same, 冲突 $total_conf"

if [ "$total_conf" -gt 0 ]; then
    echo
    echo "  冲突文件(同路径内容不同):"
    for ns in "${chosen[@]}"; do
        while IFS= read -r rel; do
            [ -n "$rel" ] || continue
            s="$SRC/assets/$ns/$rel"; f="$FORK_ASSETS/$ns/$rel"
            printf '    %s/%s\n      extended: %s 字节 %s\n      fork    : %s 字节 %s\n' \
                "$ns" "$rel" "$(wc -c <"$s")" "$(png_dims "$s")" "$(wc -c <"$f")" "$(png_dims "$f")"
        done <<< "${CONF_LIST[$ns]}"
    done
    case "$PREFER" in
        extended) echo "  冲突策略: --prefer extended (一律用源仓库版本)" ;;
        fork)     echo "  冲突策略: --prefer fork (一律保留本仓库版本)" ;;
        "")       if [ "$ASSUME_YES" -eq 1 ]; then
                      echo "  冲突策略: 未指定 --prefer 且使用了 --yes -> 一律保留本仓库版本"
                  else
                      echo "  冲突策略: 逐个询问 (默认保留本仓库版本)"
                  fi ;;
    esac
fi

# 预演 contributor.txt 将写入的那一行
build_contrib_line() {
    local ct="$ROOT/contributor.txt" existing rest p u dup line union=()
    existing="$(grep -m1 '^OnDreamQwQ,' "$ct" 2>/dev/null || true)"
    if [ -n "$existing" ]; then
        rest="${existing#OnDreamQwQ,}"; rest="${rest%%(*}"
        IFS=',' read -ra _parts <<< "$rest"
        for p in "${_parts[@]}"; do
            p="$(printf '%s' "$p" | sed 's/^ *//; s/ *$//')"
            [ -n "$p" ] && union+=("$p")
        done
    fi
    for ns in "${chosen[@]}"; do
        dup=0
        for u in "${union[@]}"; do [ "$u" = "$ns" ] && dup=1; done
        [ "$dup" -eq 1 ] || union+=("$ns")
    done
    joined=""
    for u in "${union[@]}"; do
        if [ -z "$joined" ]; then joined="$u"; else joined="$joined, $u"; fi
    done
    line="OnDreamQwQ, $joined (1.21.1适配, 来自 $EXTENDED_NAME)"
    echo "$line"
}
echo
echo "  将写入 contributor.txt 的署名行:"
echo "    $(build_contrib_line)"

if [ "$DRY" -eq 1 ]; then
    echo
    echo "==> --dry-run: 未做任何修改。"
    exit 0
fi

if [ "$ASSUME_YES" -eq 0 ]; then
    read -r -p "回车执行, 输入 n 取消: " _ans
    [ "$_ans" = "n" ] && { echo "已取消。"; exit 0; }
fi

# ---------------------------------------------------------------- 执行
echo
copied_new=0; overwritten=0; kept=0
declare -A NS_CHANGED
declare -a WRITTEN=()                 # 只记录本脚本真正写过的路径, 提交时只 stage 这些
declare -A NS_WRITTEN=()
for ns in "${chosen[@]}"; do
    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        dest="$FORK_ASSETS/$ns/$rel"
        mkdir -p "$(dirname "$dest")"
        cp "$SRC/assets/$ns/$rel" "$dest"
        copied_new=$((copied_new + 1)); NS_CHANGED[$ns]=1
        WRITTEN+=("assets/$ns/$rel"); NS_WRITTEN[$ns]+="assets/$ns/$rel"$'\n'
    done <<< "${NEW_LIST[$ns]}"
done
echo "==> 已新增 $copied_new 个文件"

if [ "$total_conf" -gt 0 ]; then
    rm -rf "$CONFLICT_DIR"
    for ns in "${chosen[@]}"; do
        while IFS= read -r rel <&3; do
            [ -n "$rel" ] || continue
            s="$SRC/assets/$ns/$rel"; f="$FORK_ASSETS/$ns/$rel"
            case "$PREFER" in
                extended) cp "$s" "$f"; overwritten=$((overwritten + 1)); NS_CHANGED[$ns]=1
                          WRITTEN+=("assets/$ns/$rel"); NS_WRITTEN[$ns]+="assets/$ns/$rel"$'\n'
                          echo "    覆盖: $ns/$rel"; continue ;;
                fork)     kept=$((kept + 1)); continue ;;
            esac
            if [ "$ASSUME_YES" -eq 1 ]; then
                kept=$((kept + 1)); continue
            fi
            outdir="$CONFLICT_DIR/$ns/$(dirname "$rel")"
            mkdir -p "$outdir"
            base="$(basename "$rel")"; ext="${base##*.}"; stem="${base%.*}"
            cp "$s" "$outdir/$stem.extended.$ext"
            cp "$f" "$outdir/$stem.fork.$ext"
            echo
            echo "  冲突: $ns/$rel"
            echo "    extended: $(wc -c <"$s") 字节 $(png_dims "$s")"
            echo "    fork    : $(wc -c <"$f") 字节 $(png_dims "$f")"
            echo "    两侧副本: $outdir/$stem.{extended,fork}.$ext"
            read -r -p "    用 extended 版本覆盖? [y/N] " _ans
            if [ "$_ans" = "y" ] || [ "$_ans" = "Y" ]; then
                cp "$s" "$f"; overwritten=$((overwritten + 1)); NS_CHANGED[$ns]=1
                WRITTEN+=("assets/$ns/$rel"); NS_WRITTEN[$ns]+="assets/$ns/$rel"$'\n'
                echo "    -> 已覆盖"
            else
                kept=$((kept + 1)); echo "    -> 保留 fork 版本"
            fi
        done 3<<< "${CONF_LIST[$ns]}"
    done
fi

ns_changed=()
for ns in "${chosen[@]}"; do [ "${NS_CHANGED[$ns]:-0}" -eq 1 ] && ns_changed+=("$ns"); done

# ---------------------------------------------------------------- 署名
if [ ${#ns_changed[@]} -gt 0 ]; then
    ct="$ROOT/contributor.txt"
    line="$(build_contrib_line)"
    if ! grep -qxF "$line" "$ct" 2>/dev/null; then
        tmp="$(mktemp)"
        grep -v '^OnDreamQwQ,' "$ct" > "$tmp" 2>/dev/null || true
        printf '%s\n' "$line" >> "$tmp"
        cat "$tmp" > "$ct"; rm -f "$tmp"
        echo "==> 已更新 contributor.txt"
    fi
fi

# ---------------------------------------------------------------- 提交
committed=0
if [ "$SPLIT" -eq 1 ]; then
    for ns in "${ns_changed[@]}"; do
        while IFS= read -r p; do [ -n "$p" ] && git add -- "$p"; done <<< "${NS_WRITTEN[$ns]}"
        if git diff --cached --quiet; then continue; fi
        git commit -q -m "merge $ns assets from $EXTENDED_NAME" \
            -m "来源: OnDreamQwQ/OreUIForEveryone-1.21.1-Extended @ $SRC_SHA"
        committed=$((committed + 1))
    done
    git add -- contributor.txt
    if ! git diff --cached --quiet; then
        git commit -q -m "update contributor.txt (OnDreamQwQ)"
        committed=$((committed + 1))
    fi
else
    [ ${#WRITTEN[@]} -gt 0 ] && git add -- "${WRITTEN[@]}"
    git add -- contributor.txt
    if git diff --cached --quiet; then
        echo "==> 没有产生任何改动, 不创建提交。"
    else
        git commit -q \
            -m "merge assets from $EXTENDED_NAME" \
            -m "命名空间: ${ns_changed[*]}" \
            -m "新增 $copied_new 个文件, 覆盖 $overwritten 个, 冲突保留 fork $kept 个" \
            -m "来源: OnDreamQwQ/OreUIForEveryone-1.21.1-Extended @ $SRC_SHA"
        committed=1
        echo "==> 已提交"
    fi
fi

# ---------------------------------------------------------------- 汇报
echo
echo "===== 合并完成 ====="
echo "  命名空间: ${ns_changed[*]:-无}"
echo "  新增 $copied_new 个文件, 覆盖 $overwritten 个, 冲突保留 fork 版本 $kept 个, 相同跳过 $total_same 个"
[ "$total_conf" -gt 0 ] && [ -d "$CONFLICT_DIR" ] && echo "  冲突副本(未覆盖时可供人工比对): $CONFLICT_DIR"
echo "  来源 commit: $SRC_SHA"
if [ "$committed" -eq 1 ]; then
    echo
    echo "尚未推送。确认无误后可执行:"
    echo "    git push origin $BRANCH"
fi
