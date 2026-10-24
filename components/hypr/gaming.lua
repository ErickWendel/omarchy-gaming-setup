-- Managed by omarchy-gaming-setup (components/hypr); local edits are replaced
-- on the next install.

-- Forza Horizon 5 (Proton) maps an empty, untitled window that takes
-- fullscreen while the intro videos play, covering the game with black.
-- Keep it out of the way, and open the titled game window fullscreen so the
-- intros are not shown in its small splash-sized window.
o.window({ class = "steam_app_1551360", title = "^$" }, {
  float = true,
  size = { 1, 1 },
  no_focus = true,
  suppress_event = "fullscreen",
})
o.window({ class = "steam_app_1551360", title = ".+" }, { fullscreen = true })

-- NFS Underground 2 (non-Steam shortcut SPEED2.exe) with Pinnacle of View:
-- the DLSS add-on's 64-bit host opens its own screen-sized window, meant to
-- sit hidden behind the game. Here it took fullscreen and focus and left the
-- game tiled. Park it, still rendering, on a hidden workspace. Titles must
-- match in full, so the prefix needs a trailing ".*".
o.window({ class = "steam_app_2674037821", title = "DLSS 5 Feed host.*" }, {
  workspace = "special:nfsu2-dlss-host silent",
  no_focus = true,
})
o.window({ class = "steam_app_2674037821", title = "^NFS Underground 2$" }, { fullscreen = true })

-- NFS Most Wanted (non-Steam shortcut 3000485560) with Pinnacle of View has
-- the same DLSS host window.
o.window({ class = "steam_app_3000485560", title = "DLSS 5 Feed host.*" }, {
  workspace = "special:nfsmw-dlss-host silent",
  no_focus = true,
})

-- Keep the screensaver and lock away while a game window is open. The stock
-- rule only inhibits idle for fullscreen windows, and games drop out of
-- fullscreen during launches, intros and DLSS host restarts (NFSU2 hit the
-- screensaver mid-session). A wheel or pad is not keyboard/mouse input, and
-- "focus" would let it lapse whenever another monitor's window has focus.
o.window({ class = "steam_app_.*" }, { idle_inhibit = "always" })
