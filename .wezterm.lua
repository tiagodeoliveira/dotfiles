local wezterm = require 'wezterm'

local config = wezterm.config_builder()

config.keys = {
  {
      key = '"',
      mods = 'CTRL|SHIFT|ALT',
      action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' },
  }, {
      key = "%",
      mods = 'CTRL|SHIFT|ALT',
      action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' },
  }
}

config.enable_scroll_bar = true
config.color_scheme = 'Solarized (dark) (terminal.sexy)'
config.font = wezterm.font('JetBrains Mono', { weight = 'Bold' })

return config
