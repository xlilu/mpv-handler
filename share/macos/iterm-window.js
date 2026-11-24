function quoteArgument(value) {
    // Escape these outside single quotes so $$ placeholders and backslash escapes stay literal.
    return "'" + value.replace(/['\\$]/g, ch => "'\\" + ch + "'") + "'";
}

function run(args) {
    const app = Application.currentApplication();
    app.includeStandardAdditions = true;
    let iterm;
    try {
        iterm = Application("com.googlecode.iterm2");
    } catch (error) {
        app.displayAlert("mpv-handler", {message: "Install iTerm2 to open debug links."});
        return;
    }
    if (!iterm.running()) {
        // A reveal URL without a session ID starts iTerm2 without requesting an untitled window.
        app.doShellScript("/usr/bin/open -g -b com.googlecode.iterm2 iterm2:reveal --args -OpenNewWindowAtStartup NO");
    }
    const command = ["/usr/bin/env", ...args.map(quoteArgument)].join(" ");
    // The profile expands backslash sequences once before interpreting the command.
    const profileCommand = command.replace(/\\/g, "\\\\");
    iterm.createWindowWithDefaultProfile({command: profileCommand});
}
