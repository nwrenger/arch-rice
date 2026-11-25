local apps = {
    terminal = "alacritty",
    terminalClass = "Alacritty",

    fileManager = "nautilus",

    applauncher = "launcher apps",

    menu = "launcher root",
    powerMenu = "launcher power",

    editor = "zeditor",
    browser = "zen-browser",
    messenger = "discord",
    passwordManager = "/usr/bin/env XDG_CURRENT_DESKTOP=GNOME /opt/enpass/Enpass",
    mails = "geary",

    calendar = "chroncal",

    audio = "wiremix -v output",
    mic = "wiremix -v input",
    internet = "wlctl",
    bluetooth = "bluetui",
    systemMonitor = "btop",
}

return apps
