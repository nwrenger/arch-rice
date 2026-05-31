local apps = {
    terminal = "alacritty",
    terminalClass = "Alacritty",

    fileManager = "nautilus",

    applauncher = "walker --width 450 --height 520 || walker --close",
    applauncherClass = "dev.benz.walker",

    menu = "menu || walker --close",
    powerMenu = "menu-power nomenu",

    editor = "MESA_VK_WSI_PRESENT_MODE=mailbox zeditor",
    browser = "zen-browser",
    messenger = "discord",

    audio = "wiremix",
    internet = "impala",
    vpn = "menu-vpn nomenu",
    airplay = "control-uxplay toggle",
    bluetooth = "bluetui",
    systemMonitor = "btop",
}

return apps
