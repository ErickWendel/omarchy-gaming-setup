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
