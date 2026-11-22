local apps = {
    terminal = "alacritty",
    terminalClass = "Alacritty",

    fileManager = "nautilus",

    applauncher = "shell launcher apps",

    menu = "shell launcher root",
    powerMenu = "shell launcher power",

    editor = "zeditor",
    browser = "zen-browser",
    messenger = "discord",
    passwordManager = "/usr/bin/env XDG_CURRENT_DESKTOP=GNOME /opt/enpass/Enpass",
    mails = "geary",

    audio = "wiremix -v output",
    mic = "wiremix -v input",
    internet = "wlctl",
    bluetooth = "bluetui",
    systemMonitor = "btop",
}

return apps
