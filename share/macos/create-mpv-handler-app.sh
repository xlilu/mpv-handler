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
[ "$#" -eq 1 ] || exit 1
case $1 in
    mpv-handler-debug://*) exec "${0%/*}/debug-terminal" "$1" ;;
    mpv-handler://*) ;;
    *) exit 1 ;;
esac
exec "${0%/*}/play" "$1"
SH

cat > "$resources/play" <<'SH'
#!/bin/sh
set -eu
IFS= read -r prefix < "${0%/*}/brew-prefix"
export PATH="$prefix/bin:/usr/bin:/bin:/usr/sbin:/sbin"
exec "$prefix/opt/mpv-handler/bin/mpv-handler" "$1"
SH

cat > "$resources/debug-terminal" <<'PERL'
#!/usr/bin/perl
use strict;
use warnings;
use File::Basename qw(dirname);
use IPC::SysV qw(IPC_PRIVATE IPC_RMID GETVAL);

my $resources = dirname($0);
if (!@ARGV) {
    # Terminal reuses its startup shell for additional tabs. Only the first
    # shell to remove the private semaphore may handle this URL.
    my ($launcher, $id, $deadline, $url, $home, $xdg) =
        delete @ENV{qw(MPV_HANDLER_START MPV_HANDLER_CLAIM MPV_HANDLER_DEADLINE
                       MPV_HANDLER_URL MPV_HANDLER_HOME MPV_HANDLER_XDG)};
    if (defined $id && $id =~ /^\d+$/ && defined $deadline && time <= $deadline
            && defined $url && $url =~ m{\Ampv-handler-debug://}
            && defined semctl($id, 0, IPC_RMID, 0)) {
        @ENV{qw(HOME XDG_CONFIG_HOME)} = ($home, $xdg);
        exec "$resources/play", $url or die "Cannot start mpv-handler: $!\n";
    }
    exec '/usr/bin/login', '-fpq', scalar getpwuid($<) or die "Cannot start login: $!\n";
}

@ARGV == 1 && $ARGV[0] =~ m{\Ampv-handler-debug://} or die "Expected one debug URL\n";
my $claim = semget(IPC_PRIVATE, 1, 0600) // die "Cannot reserve debug session: $!\n";
END { semctl($claim, 0, IPC_RMID, 0) if defined $claim }
local $SIG{$_} = sub { exit 1 } for qw(HUP INT TERM);
my $deadline = time + 60;
# Terminal splits -Shell on whitespace. Keep this command constant and let
# the noninteractive shell expand the quoted helper path as a single word.
system '/usr/bin/open', '-n', '-b', 'com.apple.Terminal',
    '--env', "MPV_HANDLER_START=$0", '--env', "MPV_HANDLER_CLAIM=$claim",
    '--env', "MPV_HANDLER_DEADLINE=$deadline", '--env', "MPV_HANDLER_URL=$ARGV[0]",
    '--env', "MPV_HANDLER_HOME=$ENV{HOME}", '--env', 'MPV_HANDLER_XDG=' . ($ENV{XDG_CONFIG_HOME} // ''),
    '--args', '-Shell', '/bin/sh -c "$MPV_HANDLER_START"';
die "Cannot open Terminal\n" if $? != 0;
while (defined semctl($claim, 0, GETVAL, 0)) {
    die "Terminal did not start the debug session in time\n" if time > $deadline;
    select undef, undef, undef, 0.1;
}
undef $claim;
PERL
chmod 755 "$resources/open-url" "$resources/play" "$resources/debug-terminal"

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
