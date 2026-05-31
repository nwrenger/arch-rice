-- See https://wiki.hypr.land/Configuring/Basics/Autostart/

-- System dependent inside: `/etc/systemd/*`
-- User dependent inside: `~/.config/systemd/*`

-- Autostart applications with Hyprland
hl.on("hyprland.start", function()
    -- Keyring
    hl.exec_cmd("dbus-update-activation-environment --systemd --all")
end)
