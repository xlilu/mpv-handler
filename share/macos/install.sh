#!/bin/sh
set -eu

src=$(dirname "$0")
apps=${1:-"$HOME/Applications"}
app="$apps/mpv-handler.app"
mkdir -p "$apps"
stage=$(mktemp -d "$apps/.mpv-handler.XXXXXXXX")
trap 'rm -rf "$stage"' EXIT

sh "$src/bundle.sh" "$src/mpv-handler" "$stage/mpv-handler.app"
codesign --verify --deep --strict --all-architectures "$stage/mpv-handler.app"

# Replace the complete bundle on upgrade so a failed build leaves the installed app usable.
osascript -l JavaScript - "$stage/mpv-handler.app" "$app" <<'JXA'
ObjC.import('Foundation')
function run(args) {
    const files = $.NSFileManager.defaultManager
    const [source, target] = args.map(path => $.NSURL.fileURLWithPath(path))
    const error = Ref()
    if (files.destinationOfSymbolicLinkAtPathError(target.path, null).js) {
        throw Error('Refusing to replace symlink ' + args[1])
    }
    if (files.fileExistsAtPath(target.path)) {
        const id = url => ObjC.unwrap($.NSBundle.bundleWithURL(url).bundleIdentifier)
        if (id(target) !== id(source)) {
            throw Error('Refusing to replace ' + args[1])
        }
        if (!files.replaceItemAtURLWithItemAtURLBackupItemNameOptionsResultingItemURLError(target, source, $(), 0, null, error)) {
            throw Error(ObjC.unwrap(error[0].localizedDescription))
        }
    } else if (!files.moveItemAtURLToURLError(source, target, error)) {
        throw Error(ObjC.unwrap(error[0].localizedDescription))
    }
}
JXA

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
printf 'Installed %s\n' "$app"
