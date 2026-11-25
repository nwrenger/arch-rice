-- See https://wiki.hypr.land/Configuring/Basics/Autostart/

-- System dependent inside: `/etc/systemd/*`
-- User dependent inside: `~/.config/systemd/*`

-- Enpass window workaround, see more below
local enpass_state = "idle"

-- Autostart applications with Hyprland
hl.on("hyprland.start", function()
    -- Keyring
    hl.exec_cmd("dbus-update-activation-environment --systemd --all")

    -- Enpass window workaround, see more below
    enpass_state = "armed"
end)

-- "Enpass starting with opened window" workaround:
-- Focus the Enpass window when it opens and return to the main workspace after a short delay

hl.on("window.open", function(window)
    if enpass_state ~= "armed" or window.class ~= "enpass" then
        return
    end

    enpass_state = "finished"
    hl.dispatch(hl.dsp.focus({ window = window }))

    hl.timer(function()
        hl.dispatch(hl.dsp.focus({ workspace = "1" }))
    end, { timeout = 250, type = "oneshot" })
end)
