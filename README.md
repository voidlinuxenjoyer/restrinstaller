# restrinstaller
voidlinux restricted package installer.
this tool installs restricted packages on void linux automatically. it clones the void-packages repo, enables restricted builds if needed, compiles the package with xbps-src, and installs it. it also keeps a package index from github, logs everything, and has commands for search, update, doctor checks, clean, history, logs, self-install, and self-update. just run ```restri install <pkg>``` and it handles the whole build process for you.
# setting up:
```
git clone https://github.com/voidlinuxenjoyer/restrinstaller.git
cd restrinstaller
chmod +x restri.sh
./restri.sh selfinstall
```
# how is it gonna look:
```
restrinstaller 1.1.0 - Void Linux restricted package installer

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
  RI_USE_NERD_FONT=1  Force Nerd Font icons (auto-detected otherwise)
  NO_COLOR=1          Disable colors
```



[▶ showcase(showcase.webm)
