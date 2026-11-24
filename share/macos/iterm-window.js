function quoteArgument(value) {
    // Escape these outside single quotes so $$ placeholders and backslash escapes stay literal.
    return "'" + value.replace(/['\\$]/g, ch => "'\\" + ch + "'") + "'";
}

function run(args) {
    let iterm;
    try {
        iterm = Application("com.googlecode.iterm2");
    } catch (error) {
        const app = Application.currentApplication();
        app.includeStandardAdditions = true;
        app.displayAlert("mpv-handler", {message: "Install iTerm2 to open debug links."});
        return;
    }
    const command = ["/usr/bin/env", ...args.map(quoteArgument)].join(" ");
    // The profile expands backslash sequences once before interpreting the command.
    const profileCommand = command.replace(/\\/g, "\\\\");
    iterm.createWindowWithDefaultProfile({command: profileCommand});
}
