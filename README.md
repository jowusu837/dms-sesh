# DMS Sesh

A DankMaterialShell launcher plugin inspired by [dms-sessionizer](https://github.com/leonardofranco01/dms-sessionizer), but powered by [sesh](https://github.com/joshmedeski/sesh).

## Features

- Search sesh results from the DMS launcher
- Open tmux sessions and zoxide projects through `sesh connect`
- Optional tmux/config/zoxide/tmuxinator sources
- Configurable terminal, launch mode, and sesh config path
- Kill tmux sessions with `!`

## Files

- `plugin.json`
- `DMSSesh.qml`
- `DMSSeshSettings.qml`

## Install

```bash
make validate
make install
```

This installs the plugin into `~/.config/DankMaterialShell/plugins/DMSSesh` and then enables or reloads it in DMS.

By default, DMS Sesh resolves the sesh config from `$XDG_CONFIG_HOME/sesh/sesh.toml` (falling back to `~/.config/sesh/sesh.toml` when `XDG_CONFIG_HOME` is unset). You can override this in the plugin settings with a custom config path.

When `Enable debug logging` is turned on in plugin settings, the plugin appends logs to `${XDG_CACHE_HOME:-$HOME/.cache}/dms-sesh/debug.log`.

For a copied install instead of a symlink:

```bash
make install-copy
```
