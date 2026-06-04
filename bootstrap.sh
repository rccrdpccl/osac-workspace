#!/bin/bash
set -euo pipefail

GITHUB_ORG="osac-project"
NO_FORK=false
FIX_REMOTES=false

usage() {
  cat <<'EOF'
Usage: ./bootstrap.sh [--no-fork] [--fix-remotes]

Sets up the OSAC workspace by cloning all component repos.

By default, each repo is forked to your GitHub account and cloned with:
  origin   = <your-username>/<repo>  (push target for feature branches)
  upstream = osac-project/<repo>     (upstream source, PR target)

Options:
  --no-fork       Clone directly from osac-project as origin without forking.
                  Useful for read-only access or CI environments.
  --fix-remotes   Migrate existing repos from the old remote convention
                  (origin=upstream, fork=personal) to the new convention
                  (origin=personal, upstream=upstream).
  --help          Show this help message.

Prerequisites:
  - gh CLI installed and authenticated (gh auth login)
EOF
}

for arg in "$@"; do
  case "$arg" in
    --no-fork) NO_FORK=true ;;
    --fix-remotes) FIX_REMOTES=true ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $arg"; usage; exit 1 ;;
  esac
done

# Verify gh CLI for fork workflow
if [ "$NO_FORK" = false ]; then
  if ! command -v gh &>/dev/null; then
    echo "❌ Error: gh CLI is not installed."
    echo "Install it (https://cli.github.com/) or use --no-fork for read-only clone."
    exit 1
  fi
  if ! gh auth status &>/dev/null; then
    echo "❌ Error: gh CLI is not authenticated."
    echo "Run 'gh auth login' or use --no-fork for read-only clone."
    exit 1
  fi
  GH_USER=$(gh api user -q .login)
  GIT_PROTOCOL=$(gh config get git_protocol 2>/dev/null || echo "https")
  echo "🚀 Setting up OSAC workspace for GitHub user: $GH_USER"
else
  echo "🚀 Setting up OSAC workspace (read-only, no forks)..."
fi

get_remote_url() {
  local user="$1"
  local repo="$2"
  if [ "$GIT_PROTOCOL" = "ssh" ]; then
    echo "git@github.com:${user}/${repo}.git"
  else
    echo "https://github.com/${user}/${repo}.git"
  fi
}

ensure_fork() {
  local repo="$1"
  if ! gh repo fork "${GITHUB_ORG}/${repo}" --clone=false 2>/dev/null; then
    if ! gh repo view "${GH_USER}/${repo}" &>/dev/null; then
      echo "❌ Failed to fork ${GITHUB_ORG}/${repo}. Skipping."
      return 1
    fi
  fi
}

fix_remotes() {
  local repo="$1"
  local current_origin
  current_origin=$(git -C "$repo" remote get-url origin 2>/dev/null || echo "")

  # Already using the new convention (origin points to user fork)
  if echo "$current_origin" | grep -q "${GH_USER}"; then
    echo "  ✅ $repo: already using new convention"
    return 0
  fi

  # Old convention: origin=upstream, fork=personal → new: origin=personal, upstream=upstream
  echo "  🔄 $repo: migrating remotes..."

  # Rename origin → upstream (if it points to osac-project)
  if echo "$current_origin" | grep -q "${GITHUB_ORG}"; then
    git -C "$repo" remote rename origin upstream
  fi

  # If a 'fork' remote exists, rename it → origin
  if git -C "$repo" remote get-url fork &>/dev/null; then
    git -C "$repo" remote rename fork origin
  else
    # No fork remote — create origin pointing to user fork
    ensure_fork "$repo" || return 1
    local url
    url=$(get_remote_url "$GH_USER" "$repo")
    git -C "$repo" remote add origin "$url"
  fi

  # Update tracking: main should track upstream/main
  git -C "$repo" fetch upstream
  git -C "$repo" branch --set-upstream-to=upstream/main main 2>/dev/null || true

  echo "  ✅ $repo: origin=${GH_USER}/${repo}, upstream=${GITHUB_ORG}/${repo}"
}

REPOS=(
  "fulfillment-service"
  "osac-operator"
  "osac-aap"
  "osac-installer"
  "osac-test-infra"
  "enhancement-proposals"
  "docs"
  "host-management-openstack"
  "bare-metal-fulfillment-operator"
)

# --fix-remotes: migrate existing repos and exit
if [ "$FIX_REMOTES" = true ]; then
  if [ "$NO_FORK" = true ]; then
    echo "❌ --fix-remotes requires fork workflow (cannot use --no-fork)"
    exit 1
  fi
  echo "🔧 Migrating remotes to new convention (origin=fork, upstream=upstream)..."
  for repo in "${REPOS[@]}"; do
    if [ -d "$repo" ]; then
      fix_remotes "$repo"
    else
      echo "  ⏭️  $repo: not cloned, skipping"
    fi
  done
  echo ""
  echo "✅ Remote migration complete!"
  exit 0
fi

for repo in "${REPOS[@]}"; do
  if [ -d "$repo" ]; then
    echo "📦 Updating $repo..."
    # Detect which remote has the upstream URL
    local_upstream="upstream"
    if ! git -C "$repo" remote get-url upstream &>/dev/null; then
      local_upstream="origin"
    fi
    (cd "$repo" && git fetch "$local_upstream" && git rebase "${local_upstream}/main" --autostash)

    # Add upstream remote to existing repos that don't have one yet
    if [ "$NO_FORK" = false ] && ! git -C "$repo" remote get-url upstream &>/dev/null; then
      echo "  🔗 Adding upstream remote for $repo..."
      local upstream_url
      upstream_url=$(get_remote_url "$GITHUB_ORG" "$repo")
      git -C "$repo" remote add upstream "$upstream_url"
      git -C "$repo" fetch upstream
    fi
  else
    if [ "$NO_FORK" = false ]; then
      echo "📥 Cloning $repo from fork..."
      ensure_fork "$repo" || { echo "  ⏭️  Skipping $repo"; continue; }
      local fork_url
      fork_url=$(get_remote_url "$GH_USER" "$repo")
      git clone "$fork_url" "$repo"

      echo "  🔗 Adding upstream remote..."
      local upstream_url
      upstream_url=$(get_remote_url "$GITHUB_ORG" "$repo")
      git -C "$repo" remote add upstream "$upstream_url"
      git -C "$repo" fetch upstream
      git -C "$repo" branch --set-upstream-to=upstream/main main
    else
      echo "📥 Cloning $repo..."
      git clone "https://github.com/${GITHUB_ORG}/${repo}.git"
    fi
  fi
done

# Install ai-workflows (bugfix, implement, etc.)
AI_WORKFLOWS_REPO="flightctl/ai-workflows"
AI_WORKFLOWS_DIR=""
# Prefer existing ~/.ai-workflows if present; otherwise clone locally
if [ -d "${HOME}/.ai-workflows" ]; then
  AI_WORKFLOWS_DIR="$(readlink -f "${HOME}/.ai-workflows")"
  echo "📦 Updating ai-workflows (${AI_WORKFLOWS_DIR})..."
  (cd "$AI_WORKFLOWS_DIR" && git fetch origin && git rebase origin/main --autostash)
elif [ -d ".ai-workflows" ]; then
  AI_WORKFLOWS_DIR="$(pwd)/.ai-workflows"
  echo "📦 Updating ai-workflows (.ai-workflows)..."
  (cd "$AI_WORKFLOWS_DIR" && git fetch origin && git rebase origin/main --autostash)
else
  AI_WORKFLOWS_DIR="$(pwd)/.ai-workflows"
  echo "📥 Cloning ai-workflows..."
  git clone "https://github.com/${AI_WORKFLOWS_REPO}.git" ".ai-workflows"
fi
echo "🔧 Installing ai-workflows skills..."
"$AI_WORKFLOWS_DIR/install.sh" claude --project . --workflows bugfix,implement
"$AI_WORKFLOWS_DIR/install.sh" cursor --project . --workflows bugfix,implement

echo ""
echo "✅ Workspace ready! All repos are on their latest main branch."
echo ""
echo "📂 Available repos:"
for repo in "${REPOS[@]}"; do
  if [ -d "$repo" ]; then
    branch=$(git -C "$repo" branch --show-current 2>/dev/null || echo "unknown")
    origin_url=$(git -C "$repo" remote get-url origin 2>/dev/null || echo "not set")
    upstream_url=$(git -C "$repo" remote get-url upstream 2>/dev/null || echo "not set")
    echo "   $repo (branch: $branch)"
    echo "     origin:   $origin_url"
    if [ "$upstream_url" != "not set" ]; then
      echo "     upstream: $upstream_url"
    fi
  fi
done

if [ "$NO_FORK" = true ]; then
  echo ""
  echo "💡 Cloned in read-only mode. To contribute, re-run without --no-fork"
  echo "   or add your fork manually:"
  echo "   cd <repo> && git remote add origin \$(gh config get git_protocol | grep -q ssh && echo git@github.com: || echo https://github.com/)\$(gh api user -q .login)/<repo>.git"
  echo "   git remote rename origin upstream  # rename current origin first"
fi
