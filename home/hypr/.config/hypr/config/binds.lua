local apps = require("config.apps")

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- See https://wiki.hypr.land/Configuring/Basics/Binds/

-- App Shortcuts
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(apps.terminal))
hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd(apps.powerMenu))
hl.bind(mainMod .. " + Space", hl.dsp.exec_cmd(apps.applauncher))
hl.bind(mainMod .. " + ALT + Space", hl.dsp.exec_cmd(apps.menu))
hl.bind(mainMod .. " + F", hl.dsp.exec_cmd(apps.fileManager))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(apps.browser))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(apps.editor))
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd(apps.messenger))

-- System ctl
hl.bind(mainMod .. " + SHIFT + A", hl.dsp.exec_cmd(apps.terminal .. " --title " .. apps.audio .. " -e " .. apps.audio))
hl.bind(mainMod .. " + SHIFT + E",
    hl.dsp.exec_cmd(apps.terminal .. " --title " .. apps.internet .. " -e " .. apps.internet))
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.exec_cmd(apps.vpn))
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd(apps.airplay))
hl.bind(mainMod .. " + SHIFT + B",
    hl.dsp.exec_cmd(apps.terminal .. " --title " .. apps.bluetooth .. " -e " .. apps.bluetooth))
hl.bind(mainMod .. " + SHIFT + S",
    hl.dsp.exec_cmd(apps.terminal .. " --title " .. apps.systemMonitor .. " -e " .. apps.systemMonitor))
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd("random-background"))
hl.bind(mainMod .. " + Print", hl.dsp.exec_cmd("colorpicker"))
hl.bind("Print", hl.dsp.exec_cmd("take-screenshot"))

-- Window managment
hl.bind(mainMod .. " + W", hl.dsp.window.close())
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + S", hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + X", hl.dsp.layout("swapsplit"))
hl.bind(mainMod .. " + A", hl.dsp.window.fullscreen({ mode = "fullscreen" }))

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))

-- Switch workspaces with mainMod + [1-4]
-- Move active window to a workspace with mainMod + SHIFT + [1-4]
for i = 1, 4 do
    hl.bind(mainMod .. " + " .. i, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end

-- Disabled: Example special workspace (scratchpad)
-- hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("magic"))
-- hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Move active window through scrolling to an existing workspaces with mainMod SHIFT + scroll
hl.bind(mainMod .. " + SHIFT + mouse_down", hl.dsp.window.move({ workspace = "e+1" }))
hl.bind(mainMod .. " + SHIFT + mouse_up", hl.dsp.window.move({ workspace = "e-1" }))

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- To switch between windows in a workspace
hl.bind("SUPER + Tab", function()
    hl.dispatch(hl.dsp.window.cycle_next())
    hl.dispatch(hl.dsp.window.bring_to_top())
end)

-- Keyboard multimedia keys for volume and Monitor brightness
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("raise-speaker"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("lower-speaker"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("mute-speaker"), { locked = true, repeating = true })
hl.bind("XF86Tools", hl.dsp.exec_cmd("mute-mic"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("raise-brightness"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("lower-brightness"), { locked = true, repeating = true })

-- playerctl
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("player-next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("player-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("player-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("player-previous"), { locked = true })
