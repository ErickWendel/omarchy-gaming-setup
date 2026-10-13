-- Assetto Corsa's Content Manager (Proton) hides to the tray during a race and
-- comes back as a squashed tiled window. Float it at a usable size instead.
-- Matched by title so the race window (same class) is left alone.
o.window({ class = "^steam_app_244210$", title = "^Content Manager$" }, {
  float = true,
  center = true,
  size = { 1600, 900 },
})
