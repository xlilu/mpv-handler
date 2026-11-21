#!/bin/sh
# Build a Launch Services URL handler for the Homebrew installation.
set -eu

usage() {
    echo "Usage: ${0##*/} [--no-register] [applications-directory]"
}

register=yes
case ${1-} in
    --help|-h) usage; exit 0 ;;
    --no-register) register=no; shift ;;
esac
if [ "$#" -gt 1 ]; then
    usage >&2
    exit 2
fi

dest=${1:-"$HOME/Applications"}
name=mpv-handler.app
mkdir -p "$dest"
dest=$(CDPATH='' cd -- "$dest" && pwd -P)
app="$dest/$name"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if [ -e "$app" ] || [ -L "$app" ]; then
    echo "Already exists: $app. Move it aside to generate a new wrapper." >&2
    exit 1
fi

prefix=$(brew --prefix)
handler="$prefix/opt/mpv-handler/bin/mpv-handler"
if [ ! -x "$handler" ]; then
    echo "Missing executable: $handler. Install the mpv-handler Formula first." >&2
    exit 1
fi

stage=$(mktemp -d "$dest/.mpv-handler.XXXXXXXX")
trap 'rm -rf "$stage"' EXIT
trap 'exit 1' HUP INT TERM

# The applet receives the URL as an Apple Event and passes a single argument
# to the helper. It can return immediately while mpv continues playing.
cat > "$stage/handler.applescript" <<'APPLESCRIPT'
use framework "Foundation"
using terms from application "/System/Library/ScriptingAdditions/StandardAdditions.osax"
    on open location theURL
        set appBundle to current application's NSBundle's mainBundle()
        set helper to appBundle's pathForResource:"open-url" ofType:(missing value)
        current application's NSTask's launchedTaskWithLaunchPath:helper arguments:{theURL}
        return
    end open location
end using terms from
APPLESCRIPT

bundle="$stage/$name"
/usr/bin/osacompile -o "$bundle" "$stage/handler.applescript"
resources="$bundle/Contents/Resources"
printf '%s\n' "$prefix" > "$resources/brew-prefix"
cat > "$resources/open-url" <<'SH'
#!/bin/sh
set -eu
IFS= read -r prefix < "${0%/*}/brew-prefix"
export PATH="$prefix/bin:/usr/bin:/bin:/usr/sbin:/sbin"
case ${1-} in
    mpv-handler-debug://*)
        umask 077
        logdir="$HOME/Library/Logs/mpv-handler"
        mkdir -p "$logdir"
        exec >> "$logdir/debug.log" 2>&1
        ;;
    mpv-handler://*) ;;
    *) exit 1 ;;
esac
exec "$prefix/opt/mpv-handler/bin/mpv-handler" "$1"
SH
chmod 755 "$resources/open-url"

plist="$bundle/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleIdentifier -string io.github.xlilu.mpv-handler "$plist"
/usr/bin/plutil -replace LSUIElement -bool YES "$plist"
/usr/bin/plutil -replace CFBundleURLTypes -json '[{"CFBundleTypeRole":"Viewer","CFBundleURLName":"mpv-handler","CFBundleURLSchemes":["mpv-handler","mpv-handler-debug"]}]' "$plist"
/usr/bin/codesign --force --sign - "$bundle"
/usr/bin/codesign --verify --strict "$bundle"

# Pass the parent directory so simultaneous builds target the same basename.
/bin/mv -n "$bundle" "$dest/"
if [ -e "$bundle" ]; then
    echo "Could not install $app. Another copy already exists." >&2
    exit 1
fi
if [ "$register" = yes ]; then
    if ! "$lsregister" -f "$app"; then
        echo "Created $app. Open it once in Finder to finish registering its URL schemes." >&2
        exit 1
    fi
fi
echo "Created $app"
