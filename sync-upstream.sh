#!/usr/bin/env bash
# =============================================================================
# sync-upstream.sh — 把源仓库(上游)的更新同步进本仓库的当前分支
#
# 源仓库: https://github.com/ReConstruction-127/OreUI-For-Everyone-1.20.1
# 策略  : 遇到冲突一律「以源仓库为主」(--X theirs)，残留冲突也按 theirs 逐条解决
#
# 用法:
#   ./sync-upstream.sh             # 同步并生成合并提交(不自动 push)
#
# 结束后自行检查并推送, 例如:  git push origin main
# =============================================================================
set -u

UPSTREAM_URL="https://github.com/ReConstruction-127/OreUI-For-Everyone-1.20.1.git"
REMOTE="upstream"
REF="${REMOTE}/main"     # 合并来源: upstream/main

# ---------- 进入仓库根目录 ----------
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "错误: 不在 git 仓库内运行。请先 cd 到仓库目录。"; exit 1
}
cd "$ROOT"

# ---------- 基本状态检查 ----------
if [ -f "$ROOT/.git/MERGE_HEAD" ] || git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
    echo "错误: 检测到未完成的合并, 请先处理(git status 查看, git merge --abort 放弃)。"; exit 1
fi
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "错误: 工作区有未提交的改动, 请先 commit 或 stash。"; exit 1
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$BRANCH" = "HEAD" ]; then
    echo "错误: 当前处于 detached HEAD, 请先切到具体分支。"; exit 1
fi
echo "==> 当前分支: $BRANCH"

# ---------- 确保 upstream remote 存在且指向源仓库 ----------
if git remote get-url "$REMOTE" >/dev/null 2>&1; then
    URL="$(git remote get-url "$REMOTE")"
    if [ "$URL" != "$UPSTREAM_URL" ]; then
        echo "错误: remote '$REMOTE' 指向的不是源仓库:"
        echo "    现在: $URL"
        echo "    期望: $UPSTREAM_URL"
        echo "如需继续, 请先: git remote set-url $REMOTE $UPSTREAM_URL"
        exit 1
    fi
else
    echo "==> 添加 remote '$REMOTE' -> $UPSTREAM_URL"
    git remote add "$REMOTE" "$UPSTREAM_URL"
fi

# ---------- 抓取上游 ----------
echo "==> 抓取上游更新..."
if ! git fetch "$REMOTE" --prune --tags 2>&1; then
    echo "错误: 抓取失败(网络问题?), 请重试。"; exit 1
fi

# ---------- 是否已是最新 ----------
if git merge-base --is-ancestor "$REF" HEAD; then
    echo "==> 已经是最新, 无需同步。($BRANCH 已包含 $REF)"
    exit 0
fi

# ---------- 预览即将合入的提交 ----------
echo
echo "==> 上游将合入以下提交:"
git log --oneline HEAD.."$REF" | sed 's/^/      /'
echo

# ---------- 合并: 冲突以源仓库(theirs)为主 ----------
echo "==> 开始合并 $REF (冲突以源仓库为主: -X theirs)..."
CONFLICTED=""
if ! git merge -X theirs --no-edit "$REF"; then
    # -X theirs 不能解决的残留冲突(如 修改/删除), 逐条按 theirs 解决
    echo
    echo "==> 处理 -X theirs 未能自动解决的冲突(一律以源仓库为准)..."
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        CONFLICTED="$CONFLICTED $f"
        if git cat-file -e "$REF:$f" 2>/dev/null; then
            # theirs 里还有这个文件 -> 直接取 theirs 版本
            git checkout --theirs -f -- "$f" || { echo "错误: 无法取 theirs 版本: $f"; exit 1; }
            git add -- "$f"
            echo "    已取源仓库版本: $f"
        else
            # theirs 里删除了这个文件 -> 跟随删除
            git rm -f -- "$f" >/dev/null 2>&1 || { echo "错误: 无法删除 $f"; exit 1; }
            echo "    已跟随源仓库删除: $f"
        fi
    done < <(git diff --name-only --diff-filter=U)

    if [ -n "$(git diff --name-only --diff-filter=U)" ]; then
        echo "错误: 仍有无法自动解决的冲突, 请手动处理:"
        git diff --name-only --diff-filter=U | sed 's/^/    /'
        echo "处理完请执行: git add <文件> && git commit --no-edit"
        exit 1
    fi

    echo "==> 提交合并结果..."
    git commit --no-edit || { echo "错误: 提交合并失败"; exit 1; }
fi

# ---------- 结果汇报 ----------
echo
echo "===== 同步完成 ====="
git log --oneline -3 | sed 's/^/  /'
if [ -n "${CONFLICTED:-}" ]; then
    echo "已按源仓库为准自动解决的冲突文件:$CONFLICTED"
else
    echo "本次无冲突, 自动合并完成。"
fi
echo
echo "尚未推送。确认无误后可执行:"
echo "    git push origin $BRANCH"
