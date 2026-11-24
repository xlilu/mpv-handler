# Source from .zshenv to handle directories opened by mpv-handler.
[[ -o interactive && -o login && ${TERM_PROGRAM-} == Apple_Terminal &&
   ${PWD:t} == request.???????? ]] || return 0

() {
    emulate -L zsh
    local root="$HOME/Library/Caches/mpv-handler/requests" dir=${PWD:A}
    local handler=${${(%):-%x}:A:h}/../MacOS/mpv-handler
    local url launch_path config_home
    [[ ${dir:h} -ef $root && ! -L $root && -O $root && -O . &&
       -f request && ! -L request && -O request ]] || return 0
    [[ $(/usr/bin/stat -f %Lp "$root") == 700 ]] || return 0

    builtin cd -q -- "$HOME" || return 0
    /bin/mv "$dir/request" "$dir/playing" 2>/dev/null || return 0
    {
        /bin/rm -f "$dir/playing"
        /bin/rmdir "$dir" 2>/dev/null || :
        IFS= read -r -d '' url && IFS= read -r -d '' launch_path && IFS= read -r -d '' config_home
    } < "$dir/playing" || return 0
    [[ $url == mpv-handler-debug://* ]] || return 0
    export PATH="$launch_path" XDG_CONFIG_HOME="$config_home"
    if [[ -t 1 ]]; then
        printf '\033[2J\033[3J\033[H'
    fi
    exec "$handler" "$url"
}
