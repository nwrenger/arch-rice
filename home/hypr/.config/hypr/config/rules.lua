local apps = require("config.apps")

-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- and https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

-- Workspaces
for i = 1, 4 do
    local monitor = (i == 1 or i == 3) and "DP-3" or "DP-2"
    local default = i == 1 or i == 2
    hl.workspace_rule({ workspace = tostring(i), monitor = monitor, default = default })
end

-- Windowrules

hl.window_rule({
    -- Ignore maximize requests from all apps. You'll probably like this.
    name           = "suppress-maximize-events",
    match          = { class = ".*" },

    suppress_event = "maximize",
})

hl.window_rule({
    -- Fix some dragging issues with XWayland
    name     = "fix-xwayland-drags",
    match    = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

-- Hyprland-run windowrule
hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },

    move  = "20 monitor_h-120",
    float = true,
})

-- Floating windows
hl.window_rule({ match = { class = apps.terminalClass, title = apps.audio, }, tag = "+float", })
hl.window_rule({ match = { class = apps.terminalClass, title = apps.internet, }, tag = "+float", })
hl.window_rule({ match = { class = apps.terminalClass, title = apps.bluetooth, }, tag = "+float", })
hl.window_rule({ match = { class = apps.terminalClass, title = apps.systemMonitor, }, tag = "+float", })
hl.window_rule({ match = { class = apps.terminalClass, title = "walker menu", }, tag = "+float", })
hl.window_rule({ match = { class = "com.gabm.satty", }, tag = "+float", })

hl.window_rule({
    match = {
        tag = "float",
    },
    float = true,
    size = "1100 750",
})

-- fastfetch
hl.window_rule({
    match = {
        class = apps.terminalClass,
        title = "fastfetch",
    },
    float = true,
    size = "575 222",
})

-- walker
hl.window_rule({
    match = {
        class = apps.applauncherClass,
    },
    stay_focused = true,
})

-- hyprpolkitagent
hl.window_rule({
    match = {
        class = "Hyprland Polkit Agent",
    },
    center = true,
})

-- Iriun Webcam
hl.window_rule({
    match = {
        class = "iriunwebcam",
    },
    float = true,
    center = true,
})
