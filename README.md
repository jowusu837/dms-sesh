# DMS Sesh

A DankMaterialShell launcher plugin inspired by [dms-sessionizer](https://github.com/leonardofranco01/dms-sessionizer), but powered by [sesh](https://github.com/joshmedeski/sesh).

## Features

- Search sesh results from the DMS launcher
- Open tmux sessions and zoxide projects through `sesh connect`
- Optional tmux/config/zoxide/tmuxinator sources
- Configurable terminal and launch mode
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

For a copied install instead of a symlink:

```bash
make install-copy
```
