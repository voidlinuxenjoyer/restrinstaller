#!/usr/bin/env bash
set -Eeuo pipefail

RESTRINSTALLER_VERSION="1.1.0"

: "${XDG_CACHE_HOME:=$HOME/.cache}"
: "${XDG_CONFIG_HOME:=$HOME/.config}"

RI_CACHE_DIR="$XDG_CACHE_HOME/restrinstaller"
RI_CONFIG_DIR="$XDG_CONFIG_HOME/restrinstaller"
RI_LOG_DIR="$RI_CACHE_DIR/logs"
RI_VOID_DIR="$RI_CACHE_DIR/void-packages"
RI_INDEX_FILE="$RI_CACHE_DIR/index.json"
RI_INDEX_TXT="$RI_CACHE_DIR/index.txt"
RI_HISTORY_FILE="$RI_CACHE_DIR/history.log"
RI_GH_CACHE_DIR="$RI_CACHE_DIR/github"

RI_VOID_REPO_URL="${RI_VOID_REPO_URL:-https://github.com/void-linux/void-packages.git}"
RI_VOID_BRANCH="${RI_VOID_BRANCH:-master}"
RI_GH_API="${RI_GH_API:-https://api.github.com}"
RI_GH_OWNER="void-linux"
RI_GH_REPO="void-packages"
RI_INDEX_TTL="${RI_INDEX_TTL:-86400}"
RI_UA="restrinstaller/${RESTRINSTALLER_VERSION}"
RI_ARCH="${RI_ARCH:-}"
RI_DEBUG="${RI_DEBUG:-0}"

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_CYAN=$'\033[36m'
    C_BRIGHT_YELLOW=$'\033[93m'
    C_BRIGHT_CYAN=$'\033[96m'
    C_BRIGHT_WHITE=$'\033[97m'
else
    C_RESET=""
    C_BOLD=""
    C_DIM=""
    C_RED=""
    C_GREEN=""
    C_YELLOW=""
    C_BLUE=""
    C_CYAN=""
    C_BRIGHT_YELLOW=""
    C_BRIGHT_CYAN=""
    C_BRIGHT_WHITE=""
fi

ICON_INFO=""
ICON_OK=""
ICON_WARN=""
ICON_ERROR=""
ICON_PKG=""
ICON_BUILD=""
ICON_INSTALL=""
ICON_UPDATE="󰚰"
ICON_SEARCH=""
ICON_STEP="󰮰"
SPINNER_CHARS=("" "" "" "" "" "")

ui_info() {
    printf '%s %s==>%s %s\n' "$ICON_INFO" "$C_BLUE" "$C_RESET" "$*"
}

ui_ok() {
    printf '%s %s ok%s %s\n' "$ICON_OK" "$C_GREEN" "$C_RESET" "$*"
}

ui_warn() {
    printf '%s %swarn%s %s\n' "$ICON_WARN" "$C_YELLOW" "$C_RESET" "$*" >&2
}

ui_error() {
    printf '%s %s !!%s %s\n' "$ICON_ERROR" "$C_RED" "$C_RESET" "$*" >&2
}

ui_step() {
    local n=$1 total=$2
    shift 2
    printf '%s %s[%d/%d]%s %s\n' "$ICON_STEP" "$C_BOLD" "$n" "$total" "$C_RESET" "$*"
}

ui_section() {
    printf '\n%s%s%s\n' "$C_BOLD" "$*" "$C_RESET"
}

ui_dim() {
    printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET"
}

ui_prompt() {
    printf '%s %s%s%s\n' "$ICON_INFO" "$C_BRIGHT_YELLOW" "$*" "$C_RESET"
}

ui_confirm() {
    local prompt=${1:-"Continue?"}
    local default=${2:-y}
    local reply
    local hint="[Y/n]"

    [[ "$default" == "n" ]] && hint="[y/N]"

    if [[ ! -t 0 ]]; then
        [[ "$default" == "y" ]] && return 0 || return 1
    fi

    ui_prompt "$prompt $hint"
    read -r reply || true
    reply=${reply,,}
    [[ -z "$reply" ]] && reply=$default
    [[ "$reply" == y || "$reply" == yes ]]
}

_spinner_cleanup() {
    kill $(jobs -p) 2>/dev/null || true
}
trap _spinner_cleanup EXIT

run_with_output() {
    local msg="$1"
    local cmd_name="$2"
    shift 2
    local cmd_args=("$@")
    local pid

    printf "\n%s %s\n" "$ICON_BUILD" "$msg"
    printf '%s\n' "$C_DIM"

    {
        "$cmd_name" "${cmd_args[@]}"
    } &
    pid=$!

    while kill -0 "$pid" 2>/dev/null; do
        sleep 0.1
    done

    wait "$pid"
    local exit_code=$?

    if (( exit_code == 0 )); then
        printf "%s %s%s%s\n" "$ICON_OK" "$C_GREEN" "$msg" "$C_RESET"
        return 0
    else
        printf "%s %s%s failed%s\n" "$ICON_ERROR" "$C_RED" "$msg" "$C_RESET"
        return "$exit_code"
    fi
}

log_init() {
    mkdir -p "$RI_LOG_DIR"
    RI_LOG_FILE="$RI_LOG_DIR/restrinstaller.log"
    : >>"$RI_LOG_FILE"
}

_ts() {
    date '+%Y-%m-%d %H:%M:%S'
}

log_info() {
    printf '[%s] [INFO]  %s\n' "$(_ts)" "$*" >>"$RI_LOG_FILE"
}

log_warn() {
    printf '[%s] [WARN]  %s\n' "$(_ts)" "$*" >>"$RI_LOG_FILE"
}

log_error() {
    printf '[%s] [ERROR] %s\n' "$(_ts)" "$*" >>"$RI_LOG_FILE"
}

log_pkg_file() {
    local pkg=$1
    local ts
    ts=$(date '+%Y%m%d-%H%M%S')
    printf '%s/%s-%s.log' "$RI_LOG_DIR" "$pkg" "$ts"
}

log_show() {
    local filter=${1:-}

    if [[ -z "$filter" ]]; then
        if [[ -f "$RI_LOG_FILE" ]]; then
            "${PAGER:-cat}" "$RI_LOG_FILE"
        else
            ui_warn "No logs yet."
        fi
        return 0
    fi

    local latest
    latest=$(ls -1t "$RI_LOG_DIR"/"$filter"-*.log 2>/dev/null | head -n1 || true)

    if [[ -z "$latest" ]]; then
        ui_warn "No logs found for '$filter'."
        return 1
    fi

    ui_info "Showing: $latest"
    "${PAGER:-cat}" "$latest"
}

REQUIRED_DEPS=(bash git curl jq)
BUILD_DEPS=(xbps-install xbps-query)
OPTIONAL_DEPS=(fzf sudo)

dep_have() {
    command -v "$1" >/dev/null 2>&1
}

dep_hint() {
    case "$1" in
        git|curl|jq|fzf)
            echo "sudo xbps-install -S $1"
            ;;
        sudo)
            echo "sudo xbps-install -S sudo  (or use doas)"
            ;;
        xbps-install|xbps-query)
            echo "Base Void package (xbps). Missing means broken system."
            ;;
        xbps-src)
            echo "Provided by void-packages: 'restrinstaller update'"
            ;;
        *)
            echo "sudo xbps-install -S $1"
            ;;
    esac
}

deps_check() {
    local missing=()
    local d

    for d in "${REQUIRED_DEPS[@]}" "${BUILD_DEPS[@]}"; do
        dep_have "$d" || missing+=("$d")
    done

    if (( ${#missing[@]} > 0 )); then
        ui_error "Missing dependencies: ${missing[*]}"
        for d in "${missing[@]}"; do
            printf '  - %s: %s\n' "$d" "$(dep_hint "$d")"
        done
        return 1
    fi

    return 0
}

deps_check_optional() {
    local d

    for d in "${OPTIONAL_DEPS[@]}"; do
        if dep_have "$d"; then
            ui_ok "optional: $d present"
        else
            ui_warn "optional: $d missing ($(dep_hint "$d"))"
        fi
    done
}

priv_cmd() {
    if [[ $EUID -eq 0 ]]; then
        echo ""
        return 0
    fi

    if dep_have sudo; then
        echo "sudo"
        return 0
    fi

    if dep_have doas; then
        echo "doas"
        return 0
    fi

    return 1
}

self_install() {
    local src="$0"
    local dest_bin="/usr/local/bin/restri"
    local dest_link="/usr/local/bin/restrinstaller"
    local SUDO

    SUDO=$(priv_cmd)

    if [[ -z "$SUDO" && $EUID -ne 0 ]]; then
        ui_error "Need root or sudo/doas to install system-wide."
        return 1
    fi

    ui_info "Installing restrinstaller to $dest_bin"

    if [[ -n "$SUDO" ]]; then
        $SUDO install -m 755 "$src" "$dest_bin"
        $SUDO ln -sf "$dest_bin" "$dest_link"
    else
        install -m 755 "$src" "$dest_bin"
        ln -sf "$dest_bin" "$dest_link"
    fi

    ui_ok "Installed as 'restri' and 'restrinstaller'"
    ui_info "You can now run: restri <command>"
}

self_uninstall() {
    local files=("/usr/local/bin/restri" "/usr/local/bin/restrinstaller")
    local SUDO

    SUDO=$(priv_cmd)

    if [[ -z "$SUDO" && $EUID -ne 0 ]]; then
        ui_error "Need root or sudo/doas to remove system files."
        return 1
    fi

    for f in "${files[@]}"; do
        if [[ -f "$f" || -L "$f" ]]; then
            ui_info "Removing $f"
            if [[ -n "$SUDO" ]]; then
                $SUDO rm -f "$f"
            else
                rm -f "$f"
            fi
        fi
    done

    ui_ok "Uninstalled."
}

cache_init() {
    mkdir -p "$RI_CACHE_DIR" "$RI_LOG_DIR" "$RI_GH_CACHE_DIR" "$RI_CONFIG_DIR"
}

cache_age() {
    local f=$1

    [[ -f "$f" ]] || {
        echo 999999999
        return
    }

    local now mtime
    now=$(date +%s)
    mtime=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
    echo $((now - mtime))
}

cache_is_fresh() {
    local age
    age=$(cache_age "$1")
    (( age < ${2:-$RI_INDEX_TTL} ))
}

cache_update() {
    ui_section "Updating package index"
    github_fetch_index
    ui_ok "Package index updated ($(wc -l <"$RI_INDEX_TXT" | tr -d ' ') packages)"
}

cache_ensure_index() {
    if [[ ! -f "$RI_INDEX_TXT" ]] || \
       ! cache_is_fresh "$RI_INDEX_TXT" || \
       [[ ! -f "$RI_CACHE_DIR/index_commit.txt" ]]; then
        cache_update
    fi
}

_gh_headers=(-H "User-Agent: $RI_UA" -H "Accept: application/vnd.github+json")
[[ -n "${GITHUB_TOKEN:-}" ]] && _gh_headers+=(-H "Authorization: Bearer $GITHUB_TOKEN")

gh_get() {
    local url=$1
    local out=${2:-}
    local tries=3
    local i
    local http

    for ((i=1; i<=tries; i++)); do
        if [[ -n "$out" ]]; then
            http=$(curl -sSL --fail-with-body -o "$out" -w '%{http_code}' \
                "${_gh_headers[@]}" "$url" || true)

            [[ "$http" =~ ^2 ]] && return 0
        else
            local tmp
            tmp=$(mktemp)

            http=$(curl -sSL --fail-with-body -o "$tmp" -w '%{http_code}' \
                "${_gh_headers[@]}" "$url" || true)

            if [[ "$http" =~ ^2 ]]; then
                cat "$tmp"
                rm -f "$tmp"
                return 0
            fi

            rm -f "$tmp"
        fi

        log_warn "GitHub GET $url -> HTTP $http (attempt $i/$tries)"
        sleep $((i*2))
    done

    log_error "GitHub GET failed: $url (HTTP $http)"
    return 1
}

github_fetch_index() {
    local branch_json commit_sha root_tree srcpkgs_sha tree_json

    ui_info "Resolving $RI_GH_OWNER/$RI_GH_REPO@$RI_VOID_BRANCH"

    branch_json=$(gh_get "$RI_GH_API/repos/$RI_GH_OWNER/$RI_GH_REPO/branches/$RI_VOID_BRANCH") || return 1
    commit_sha=$(printf '%s' "$branch_json" | jq -r '.commit.sha // empty')

    [[ -z "$commit_sha" ]] && {
        log_error "no branch sha"
        return 1
    }

    printf '%s' "$commit_sha" > "$RI_CACHE_DIR/index_commit.txt"

    ui_info "Fetching srcpkgs tree ($commit_sha)"
    root_tree=$(gh_get "$RI_GH_API/repos/$RI_GH_OWNER/$RI_GH_REPO/git/trees/$commit_sha") || return 1

    srcpkgs_sha=$(printf '%s' "$root_tree" | jq -r '.tree[] | select(.path=="srcpkgs" and .type=="tree") | .sha')

    [[ -z "$srcpkgs_sha" ]] && {
        log_error "srcpkgs missing"
        return 1
    }

    tree_json=$(gh_get "$RI_GH_API/repos/$RI_GH_OWNER/$RI_GH_REPO/git/trees/$srcpkgs_sha") || return 1

    printf '%s' "$tree_json" > "$RI_INDEX_FILE.tmp" && mv -f "$RI_INDEX_FILE.tmp" "$RI_INDEX_FILE"

    jq -r '.tree[] | select(.type=="tree") | .path' "$RI_INDEX_FILE" \
        | LC_ALL=C sort -u > "$RI_INDEX_TXT.tmp"
    mv -f "$RI_INDEX_TXT.tmp" "$RI_INDEX_TXT"
}

github_fetch_template() {
    local pkg=$1
    local out="$RI_GH_CACHE_DIR/${pkg}.template"

    if cache_is_fresh "$out" 3600; then
        printf '%s' "$out"
        return 0
    fi

    local url="https://raw.githubusercontent.com/$RI_GH_OWNER/$RI_GH_REPO/$RI_VOID_BRANCH/srcpkgs/$pkg/template"

    if curl -sSL --fail-with-body -H "User-Agent: $RI_UA" -o "$out.tmp" "$url"; then
        mv -f "$out.tmp" "$out"
        printf '%s' "$out"
        return 0
    fi

    rm -f "$out.tmp"
    return 1
}

pkg_exists() {
    cache_ensure_index
    grep -Fxq -- "$1" "$RI_INDEX_TXT"
}

pkg_template_path() {
    local pkg=$1
    local tpl="$RI_VOID_DIR/srcpkgs/$pkg/template"

    if [[ -f "$tpl" ]]; then
        printf '%s' "$tpl"
        return 0
    fi

    if tpl=$(github_fetch_template "$pkg"); then
        printf '%s' "$tpl"
        return 0
    fi

    return 1
}

pkg_is_restricted() {
    local tpl

    tpl=$(pkg_template_path "$1") || return 2
    grep -Eq '^[[:space:]]*restricted[[:space:]]*=[[:space:]]*yes' "$tpl"
}

pkg_is_in_repo() {
    local pkg=$1
    xbps-query -R "$pkg" >/dev/null 2>&1
}

void_have_tree() {
    [[ -d "$RI_VOID_DIR/.git" && -x "$RI_VOID_DIR/xbps-src" ]]
}

void_clone_tree() {
    ui_info "Cloning void-packages (shallow) into $RI_VOID_DIR"
    mkdir -p "$(dirname "$RI_VOID_DIR")"

    if [[ -e "$RI_VOID_DIR" && ! -d "$RI_VOID_DIR/.git" ]]; then
        rm -rf "$RI_VOID_DIR"
    fi

    git clone --depth=1 --filter=blob:none --branch "$RI_VOID_BRANCH" \
        "$RI_VOID_REPO_URL" "$RI_VOID_DIR" 2>&1 | tee -a "$RI_LOG_FILE"

    [[ -x "$RI_VOID_DIR/xbps-src" ]] || {
        log_error "xbps-src missing after clone"
        return 1
    }
}

void_update_tree() {
    local target_sha=${1:-}

    if ! void_have_tree; then
        void_clone_tree
        return
    fi

    ui_info "Updating void-packages"

    if ! _void_update_tree_inner "$target_sha"; then
        ui_error "void-packages update failed"
        return 1
    fi

    ui_ok "void-packages updated"
}

_void_update_tree_inner() {
    local target_sha=${1:-}

    (
        cd "$RI_VOID_DIR"
        git fetch --depth=1 origin "$RI_VOID_BRANCH"

        if [[ -n "$target_sha" ]]; then
            git checkout -f "$target_sha" || git reset --hard "$target_sha"
        else
            git reset --hard "origin/$RI_VOID_BRANCH"
        fi
    ) 2>&1 | tee -a "$RI_LOG_FILE"
}

void_ensure_tree() {
    void_have_tree || void_clone_tree
}

void_ensure_bootstrap() {
    void_ensure_tree

    local arch_master="$RI_VOID_DIR/masterdir-$(uname -m)"

    if [[ -f "$RI_VOID_DIR/masterdir/etc/xbps.d/repos-remote.conf" ]] || \
       [[ -f "$arch_master/etc/xbps.d/repos-remote.conf" ]]; then
        return 0
    fi

    ui_info "Bootstrapping xbps-src (binary-bootstrap)"

    if ! _void_bootstrap_inner; then
        ui_error "Bootstrap failed"
        return 1
    fi

    ui_ok "Bootstrap complete"
}

_void_bootstrap_inner() {
    ( cd "$RI_VOID_DIR" && ./xbps-src binary-bootstrap ) 2>&1 | tee -a "$RI_LOG_FILE"
}

void_enable_restricted() {
    void_ensure_tree

    local etc="$RI_VOID_DIR/etc"
    local cfg="$RI_VOID_DIR/etc/conf"

    mkdir -p "$etc"

    if [[ -f "$cfg" ]] && grep -Eq '^[[:space:]]*XBPS_ALLOW_RESTRICTED[[:space:]]*=' "$cfg"; then
        sed -i.bak -E 's|^[[:space:]]*XBPS_ALLOW_RESTRICTED[[:space:]]*=.*|XBPS_ALLOW_RESTRICTED=yes|' "$cfg"
    else
        printf '\nXBPS_ALLOW_RESTRICTED=yes\n' >> "$cfg"
    fi

    log_info "XBPS_ALLOW_RESTRICTED=yes set"
}

builder_build() {
    local pkg=$1

    void_ensure_bootstrap || return 1

    (
        cd "$RI_VOID_DIR"

        if [[ -n "$RI_ARCH" ]]; then
            ./xbps-src -a "$RI_ARCH" pkg "$pkg"
        else
            ./xbps-src pkg "$pkg"
        fi
    ) 2>&1
}

builder_find_binpkgs() {
    local pkg=$1
    local binroot="$RI_VOID_DIR/hostdir/binpkgs"

    [[ -d "$binroot" ]] || return 1
    find "$binroot" -maxdepth 3 -type f -name "${pkg}-[0-9]*.xbps" 2>/dev/null | sort -u
}

builder_clean() {
    ui_section "Cleaning build artifacts"

    if [[ ! -d "$RI_VOID_DIR" ]]; then
        ui_warn "No void-packages tree"
        return 0
    fi

    ( cd "$RI_VOID_DIR" && ./xbps-src -C zap || true ) 2>&1 | tee -a "$RI_LOG_FILE" || true
    rm -rf "$RI_VOID_DIR/hostdir/binpkgs" 2>/dev/null || true

    ui_ok "Cleaned"
}

history_record() {
    mkdir -p "$(dirname "$RI_HISTORY_FILE")"
    printf '%s\t%s\t%s\n' "$(_ts)" "$2" "$1" >> "$RI_HISTORY_FILE"
}

history_show() {
    if [[ ! -s "$RI_HISTORY_FILE" ]]; then
        ui_info "No history yet."
        return 0
    fi

    printf '%-20s  %-16s  %s\n' "DATE" "STATUS" "PACKAGE"
    printf '%-20s  %-16s  %s\n' "----" "------" "-------"
    awk -F'\t' '{ printf "%-20s  %-16s  %s\n", $1, $2, $3 }' "$RI_HISTORY_FILE"
}

search_cmd() {
    local query=${1:-}

    cache_ensure_index

    if [[ -z "$query" ]]; then
        if dep_have fzf; then
            local sel
            sel=$(fzf --prompt="package> " --height=80% --border < "$RI_INDEX_TXT" || true)

            [[ -z "$sel" ]] && {
                ui_info "No selection."
                return 0
            }

            printf '%s\n' "$sel"
            ui_confirm "Install '$sel' now?" y && installer_run "$sel"
            return 0
        else
            ui_error "Provide a query, or install 'fzf' for interactive search."
            return 2
        fi
    fi

    local matches
    matches=$(grep -Fi -- "$query" "$RI_INDEX_TXT" || true)

    if [[ -z "$matches" ]]; then
        ui_warn "No matches for: $query"
        return 1
    fi

    if dep_have fzf; then
        local sel
        sel=$(printf '%s\n' "$matches" | fzf --prompt="match> " --height=80% --border --query="$query" || true)

        [[ -z "$sel" ]] && {
            ui_info "No selection."
            return 0
        }

        ui_confirm "Install '$sel' now?" y && installer_run "$sel"
    else
        printf '%s\n' "$matches"
    fi
}

doctor_run() {
    local rc=0
    local p

    ui_section "Restrinstaller doctor"

    ui_info "System"

    if [[ -r /etc/os-release ]]; then
        (
            . /etc/os-release
            printf '  OS: %s %s\n' "${NAME:-?}" "${VERSION_ID:-}"
        )
        grep -qi 'void' /etc/os-release || {
            ui_warn "Does not look like Void Linux"
            rc=1
        }
    else
        ui_warn "/etc/os-release not readable"
    fi

    printf '  Arch: %s\n' "$(uname -m)"
    printf '  User: %s (uid=%s)\n' "$(id -un)" "$(id -u)"

    ui_info "Required commands"

    local d
    for d in "${REQUIRED_DEPS[@]}" "${BUILD_DEPS[@]}"; do
        if dep_have "$d"; then
            ui_ok "$d ($(command -v "$d"))"
        else
            ui_error "$d MISSING — $(dep_hint "$d")"
            rc=1
        fi
    done

    ui_info "Optional commands"
    deps_check_optional

    ui_info "Privilege escalation"

    if [[ $EUID -eq 0 ]]; then
        ui_ok "running as root"
    elif p=$(priv_cmd) && [[ -n "$p" ]]; then
        ui_ok "using: $p"
    else
        ui_error "no sudo/doas and not root"
        rc=1
    fi

    ui_info "Cache"
    printf '  Cache dir: %s\n' "$RI_CACHE_DIR"
    printf '  Log dir  : %s\n' "$RI_LOG_DIR"

    if [[ -f "$RI_INDEX_TXT" ]]; then
        printf '  Index    : %s pkgs (age %ss)\n' \
            "$(wc -l <"$RI_INDEX_TXT" | tr -d ' ')" "$(cache_age "$RI_INDEX_TXT")"
    else
        ui_warn "no package index yet — run: restrinstaller update"
    fi

    ui_info "void-packages tree"

    if void_have_tree; then
        ui_ok "present at $RI_VOID_DIR"
    else
        ui_warn "not cloned yet — run: restrinstaller update"
    fi

    ui_info "Network"

    if curl -sSfI --max-time 5 "$RI_GH_API" >/dev/null 2>&1; then
        ui_ok "GitHub API reachable"
    else
        ui_warn "GitHub API unreachable"
    fi

    if (( rc == 0 )); then
        ui_section "All checks passed."
    else
        ui_section "Some checks failed."
    fi

    return $rc
}

installer_run() {
    local pkg=$1

    [[ -z "$pkg" ]] && {
        ui_error "No package specified."
        return 2
    }

    local pkg_log
    pkg_log=$(log_pkg_file "$pkg")
    : >"$pkg_log"

    log_info "Install requested: $pkg (log: $pkg_log)"

    ui_section "Installing '$pkg'"

    ui_step 1 4 "Checking dependencies"
    deps_check || {
        history_record "$pkg" "failed:deps"
        return 1
    }

    if ! priv_cmd >/dev/null; then
        ui_error "Need root or sudo/doas."
        history_record "$pkg" "failed:noprivs"
        return 1
    fi

    ui_ok "Dependencies present"

    ui_step 2 4 "Checking if package is restricted"

    local SUDO
    SUDO=$(priv_cmd)

    if pkg_is_in_repo "$pkg"; then
        ui_info "Package '$pkg' is available in official repositories"
        ui_info "Installing directly with xbps-install (fast path)"

        ui_step 3 4 "Installing from repository"

        printf '\n'
        if ! $SUDO xbps-install -Sy "$pkg" 2>&1; then
            ui_error "Install failed. See $pkg_log"
            history_record "$pkg" "failed:install"
            return 1
        fi

        ui_ok "Installed"

        ui_step 4 4 "Done"
        ui_ok "Done"

        history_record "$pkg" "installed"
        ui_section "Success: $pkg"
        return 0
    fi

    ui_info "Package '$pkg' not in official repos, building from source"

    ui_step 3 4 "Building from source"

    void_ensure_tree

    if ! cache_is_fresh "$RI_VOID_DIR/.git/FETCH_HEAD" 86400; then
        void_update_tree
    fi

    if [[ ! -d "$RI_VOID_DIR/srcpkgs/$pkg" ]]; then
        cache_update

        if ! pkg_exists "$pkg"; then
            ui_error "Package '$pkg' not found in void-packages."
            history_record "$pkg" "failed:notfound"
            return 1
        fi

        local index_sha=""
        if [[ -f "$RI_CACHE_DIR/index_commit.txt" ]]; then
            index_sha=$(cat "$RI_CACHE_DIR/index_commit.txt")
        else
            index_sha=""
        fi

        void_update_tree "$index_sha"

        if [[ ! -d "$RI_VOID_DIR/srcpkgs/$pkg" ]]; then
            ui_error "Package '$pkg' still absent after refresh."
            history_record "$pkg" "failed:notfound"
            return 1
        fi
    fi

    if pkg_is_restricted "$pkg"; then
        ui_info "Package '$pkg' is RESTRICTED — enabling XBPS_ALLOW_RESTRICTED."
        ui_dim "docs: https://docs.voidlinux.org/xbps/repositories/restricted.html"
        void_enable_restricted
    else
        ui_info "Package '$pkg' is not restricted — building from source anyway."
    fi

    void_ensure_bootstrap
    ui_ok "void-packages ready"

    if ! run_with_output "Building $pkg" builder_build "$pkg"; then
        ui_error "Build failed. Log: $pkg_log"
        ui_dim "Try: 'restrinstaller update' / 'restrinstaller clean' / check disk space."
        history_record "$pkg" "failed:build"
        return 1
    fi

    ui_ok "Build completed"

    local binpkgs
    mapfile -t binpkgs < <(builder_find_binpkgs "$pkg")

    if (( ${#binpkgs[@]} == 0 )); then
        ui_error "No built .xbps found for '$pkg'."
        history_record "$pkg" "failed:nobinpkg"
        return 1
    fi

    log_info "Built binpkgs: ${binpkgs[*]}"

    local repo_dir
    repo_dir=$(dirname "${binpkgs[0]}")

    ui_step 4 4 "Installing built package"

    printf '\n'
    if ! $SUDO xbps-install -y -R "$repo_dir" "$pkg" 2>&1; then
        ui_warn "Repo install failed, retrying with --repository."
        if ! $SUDO xbps-install -y --repository="$repo_dir" "$pkg" 2>&1; then
            ui_error "Install failed. See $pkg_log"
            history_record "$pkg" "failed:install"
            return 1
        fi
    fi

    ui_ok "Installed"
    ui_ok "Done"

    history_record "$pkg" "installed"
    ui_section "Success: $pkg"
    ui_dim "Log saved to: $pkg_log"
}

usage() {
    cat <<EOF
restrinstaller $RESTRINSTALLER_VERSION - Void Linux restricted package installer

Usage:
  restrinstaller <command> [args]

Commands:
  search [QUERY]      Search packages (fzf if available)
  install PACKAGE     Build and install a package (auto-handles restricted)
  update              Refresh package index + void-packages tree
  doctor              Check dependencies and system readiness
  clean               Remove build artifacts (xbps-src zap + binpkgs)
  history             Show previous installs
  logs [PACKAGE]      Show global log or latest per-package log
  selfinstall         Install this script system-wide as 'restri'
  selfuninstall       Remove the system-wide installation
  version             Print version
  help                This message

Env vars:
  RI_VOID_REPO_URL, RI_VOID_BRANCH, RI_ARCH, RI_INDEX_TTL,
  GITHUB_TOKEN (higher API rate limit), RI_DEBUG
  NO_COLOR=1          Disable colors
EOF
}

on_error() {
    local exit_code=$?
    local line=${1:-?}

    log_error "Aborted (line $line, exit $exit_code)"
    ui_error "restrinstaller failed. See logs: $RI_LOG_DIR"
    exit "$exit_code"
}

main() {
    cache_init
    log_init
    trap 'on_error $LINENO' ERR
    trap 'echo -e "\n\nInterrupted by user"; exit 130' INT TERM

    local cmd="${1:-help}"
    shift || true

    case "$cmd" in
        search)
            search_cmd "${1:-}"
            ;;
        install|i)
            [[ $# -ge 1 ]] || {
                ui_error "'install' needs a package name"
                usage
                exit 2
            }
            installer_run "$1"
            ;;
        update|u)
            cache_update
            void_update_tree
            ;;
        doctor)
            doctor_run
            ;;
        clean)
            builder_clean
            ;;
        history)
            history_show
            ;;
        logs)
            log_show "${1:-}"
            ;;
        selfinstall)
            self_install
            ;;
        selfuninstall)
            self_uninstall
            ;;
        version|--version|-v)
            echo "restrinstaller $RESTRINSTALLER_VERSION"
            ;;
        help|--help|-h|"")
            usage
            ;;
        *)
            ui_error "Unknown command: $cmd"
            usage
            exit 2
            ;;
    esac
}

main "$@"
