local awful = require("awful")
local gears = require("gears")

local menubar = require("menubar")

local hotkeys_popup = require("awful.hotkeys_popup")

local brightness_widget = require("awesome-wm-widgets.brightness-widget.brightness")
local volume_widget = require('awesome-wm-widgets.pactl-widget.volume')


return gears.table.join(
    awful.key({ modkey, }, "s", hotkeys_popup.show_help,
        { description = "show help", group = "awesome" }),
    awful.key({ modkey, }, "Left", awful.tag.viewprev,
        { description = "view previous", group = "tag" }),
    awful.key({ modkey, }, "Right", awful.tag.viewnext,
        { description = "view next", group = "tag" }),
    awful.key({ modkey, }, "Escape", awful.tag.history.restore,
        { description = "go back", group = "tag" }),

    awful.key({ modkey, }, "j",
        function()
            awful.client.focus.byidx(1)
        end,
        { description = "focus next by index", group = "client" }
    ),
    awful.key({ modkey, }, "k",
        function()
            awful.client.focus.byidx(-1)
        end,
        { description = "focus previous by index", group = "client" }
    ),
    awful.key({ modkey, }, "w", function() mymainmenu:show() end,
        { description = "show main menu", group = "awesome" }),

    -- Layout manipulation
    awful.key({ modkey, "Shift" }, "j", function() awful.client.swap.global_bydirection("down") end,
        { description = "swap with client below", group = "client" }),
    awful.key({ modkey, "Shift" }, "k", function() awful.client.swap.global_bydirection("up") end,
        { description = "swap with client above", group = "client" }),
    awful.key({ modkey, "Shift" }, "h", function() awful.client.swap.global_bydirection("left") end,
        { description = "swap with client to the left", group = "client" }),
    awful.key({ modkey, "Shift" }, "l", function() awful.client.swap.global_bydirection("right") end,
        { description = "swap with client above", group = "client" }),
    awful.key({ modkey, "Control" }, "j", function() awful.screen.focus_relative(1) end,
        { description = "focus the next screen", group = "screen" }),
    awful.key({ modkey, "Control" }, "k", function() awful.screen.focus_relative(-1) end,
        { description = "focus the previous screen", group = "screen" }),
    awful.key({ modkey, }, "u", awful.client.urgent.jumpto,
        { description = "jump to urgent client", group = "client" }),
    awful.key({ modkey, }, "Tab",
        function()
            awful.client.focus.history.previous()
            if client.focus then
                client.focus:raise()
            end
        end,
        { description = "go back", group = "client" }),

    -- Laptop stuff
    awful.key({ modkey, "Shift" }, "d", function() awful.spawn.with_shell("autorandr -c") end,
        { description = "Configure displays" }),
    awful.key({}, "XF86Display", function() awful.spawn.with_shell("autorandr -c") end,
        { description = "Configure displays" }),
    awful.key({}, "XF86AudioRaiseVolume", function() volume_widget:inc(5) end),
    awful.key({}, "XF86AudioLowerVolume", function() volume_widget:dec(5) end),
    awful.key({}, "XF86AudioMute", function() volume_widget:toggle() end),
    --    awful.key({}, "XF86AudioRaiseVolume",
    --        function() awful.util.spawn("pactl set-sink-volume @DEFAULT_SINK@ +5%", false) end,
    --        { description = "volume up", group = "volume" }),
    --    awful.key({}, "XF86AudioLowerVolume",
    --        function() awful.util.spawn("pactl set-sink-volume @DEFAULT_SINK@ -5%", false) end,
    --        { description = "volume down", group = "volume" }),
    --    awful.key({}, "XF86AudioMute",
    --        function() awful.util.spawn("pactl set-sink-mute @DEFAULT_SINK@ toggle", false) end,
    --        { description = "audio mute", group = "volume" }),
    awful.key({}, "XF86AudioMicMute",
        function() awful.util.spawn("pactl set-source-mute @DEFAULT_SOURCE@ toggle", false) end,
        { description = "mic mute", group = "volume" }),

    -- Other media keys
    awful.key({}, "XF86AudioNext",
        function() awful.spawn.with_shell("playerctl next") end,
        { description = "skip to next", group = "media" }),
    awful.key({}, "XF86AudioPrev",
        function() awful.spawn.with_shell("playerctl previous") end,
        { description = "back to previous", group = "media" }),
    awful.key({}, "XF86AudioPlay",
        function() awful.spawn.with_shell("playerctl play-pause") end,
        { description = "toggle play/pause", group = "media" }),
    awful.key({}, "XF86AudioStop",
        function() awful.spawn.with_shell("playerctl stop") end,
        { description = "stop", group = "media" }),

    -- Brightness controls
    awful.key({}, "XF86MonBrightnessUp", function() brightness_widget:inc() end,
        { description = "increase brightness", group = "custom" }),
    awful.key({}, "XF86MonBrightnessDown", function() brightness_widget:dec() end,
        { description = "decrease brightness", group = "custom" }),

    -- Standard program
    awful.key({ modkey, }, "Return", function() awful.spawn(terminal) end,
        { description = "open a terminal", group = "launcher" }),
    awful.key({ modkey, "Control" }, "r", awesome.restart,
        { description = "reload awesome", group = "awesome" }),
    awful.key({ modkey, "Shift" }, "q", awesome.quit,
        { description = "quit awesome", group = "awesome" }),
    awful.key({ modkey, }, "l", function() awful.tag.incmwfact(0.05) end,
        { description = "increase master width factor", group = "layout" }),
    awful.key({ modkey, }, "h", function() awful.tag.incmwfact(-0.05) end,
        { description = "decrease master width factor", group = "layout" }),
    --    awful.key({ modkey, "Shift" }, "h", function() awful.tag.incnmaster(1, nil, true) end,
    --        { description = "increase the number of master clients", group = "layout" }),
    --    awful.key({ modkey, "Shift" }, "l", function() awful.tag.incnmaster(-1, nil, true) end,
    --        { description = "decrease the number of master clients", group = "layout" }),
    awful.key({ modkey, "Control" }, "h", function() awful.tag.incncol(1, nil, true) end,
        { description = "increase the number of columns", group = "layout" }),
    awful.key({ modkey, "Control" }, "l", function() awful.tag.incncol(-1, nil, true) end,
        { description = "decrease the number of columns", group = "layout" }),
    awful.key({ modkey, }, "space", function() awful.layout.inc(1) end,
        { description = "select next", group = "layout" }),
    awful.key({ modkey, "Shift" }, "space", function() awful.layout.inc(-1) end,
        { description = "select previous", group = "layout" }),

    awful.key({ modkey, "Control" }, "n",
        function()
            local c = awful.client.restore()
            -- Focus restored client
            if c then
                c:emit_signal(
                    "request::activate", "key.unminimize", { raise = true }
                )
            end
        end,
        { description = "restore minimized", group = "client" }),

    -- Prompt
    awful.key({ modkey }, "r", function() awful.screen.focused().mypromptbox:run() end,
        { description = "run prompt", group = "launcher" }),

    awful.key({ modkey }, "x",
        function()
            awful.prompt.run {
                prompt       = "Run Lua code: ",
                textbox      = awful.screen.focused().mypromptbox.widget,
                exe_callback = awful.util.eval,
                history_path = awful.util.get_cache_dir() .. "/history_eval"
            }
        end,
        { description = "lua execute prompt", group = "awesome" }),
    -- Menubar
    awful.key({ modkey }, "p", function() menubar.show() end,
        { description = "show the menubar", group = "launcher" })
)
