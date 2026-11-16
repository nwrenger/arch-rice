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

    audio = "shell popup audio",
    internet = "shell popup network",
    vpn = "shell popup vpn",
    airplay = "shell uxplay toggle",
    bluetooth = "shell popup bluetooth",
    systemMonitor = "btop",
    packageInstall = "package install",
    aurInstall = "AUR install",
    flatpakInstall = "Flatpak install",
    packageRemove = "package removal",
    flatpakRemove = "Flatpak removal",
    systemUpdate = "system update",
}

return apps
