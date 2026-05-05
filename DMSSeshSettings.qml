import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root

    pluginId: "dmsSesh"

    StyledText {
        width: parent.width
        text: "DMS Sesh"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "A sesh-powered launcher for DankMaterialShell. Search tmux sessions, configured sessions, zoxide projects, and tmuxinator entries from the launcher."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "trigger"
        label: "Trigger"
        description: "Launcher prefix used to activate DMS Sesh"
        placeholder: "se"
        defaultValue: "se"
    }

    StringSetting {
        settingKey: "binaryPath"
        label: "Sesh Binary"
        description: "Absolute path or command name for the sesh executable"
        placeholder: "sesh"
        defaultValue: "sesh"
    }

    StringSetting {
        settingKey: "configPath"
        label: "Config Path"
        description: "Optional absolute path to a custom sesh config. Leave empty to use $XDG_CONFIG_HOME/sesh/sesh.toml by default"
        placeholder: "/path/to/sesh.toml"
        defaultValue: ""
    }

    DankDropdown {
        id: terminalDropdown
        text: "Terminal Emulator"
        description: "Choose which terminal opens sesh connect"
        currentValue: root.loadValue("terminal", "alacritty")
        options: [
            "st",
            "alacritty",
            "kitty",
            "wezterm",
            "foot",
            "konsole",
            "gnome-terminal",
            "xterm",
            "ghostty",
            "Custom"
        ]
        dropdownWidth: 180
        onValueChanged: function(value) {
            root.saveValue("terminal", value)
        }
    }

    Column {
        width: parent.width
        visible: terminalDropdown.currentValue === "Custom"
        spacing: 5

        StyledText {
            text: "Custom Terminal"
        }

        DankTextField {
            width: parent.width
            text: root.loadValue("customTerminal", "")
            placeholderText: "my-terminal"
            onEditingFinished: root.saveValue("customTerminal", text)
        }
    }

    DankDropdown {
        text: "Launch Mode"
        description: "Open sesh in a new terminal, replace an existing terminal, or switch the current tmux client"
        currentValue: root.loadValue("terminalBehavior", "newWindow")
        options: [
            "newWindow",
            "killExisting",
            "switchClient"
        ]
        dropdownWidth: 180
        onValueChanged: function(value) {
            root.saveValue("terminalBehavior", value)
        }
    }

    ToggleSetting {
        settingKey: "includeTmux"
        label: "Include tmux sessions"
        description: "Show currently running tmux sessions from sesh"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "includeConfig"
        label: "Include configured sessions"
        description: "Show sessions defined in the sesh config file"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "includeZoxide"
        label: "Include zoxide projects"
        description: "Show directory results tracked by zoxide"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "includeTmuxinator"
        label: "Include tmuxinator entries"
        description: "Show tmuxinator projects from sesh"
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "hideAttached"
        label: "Hide attached sessions"
        description: "Exclude sessions already attached in tmux"
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "debugEnabled"
        label: "Enable debug logging"
        description: "Write debug logs to ${XDG_CACHE_HOME:-$HOME/.cache}/dms-sesh/debug.log"
        defaultValue: false
    }

    SliderSetting {
        settingKey: "maxResults"
        label: "Max Results"
        description: "Maximum number of results shown in the launcher"
        defaultValue: 50
        minimum: 10
        maximum: 200
        unit: "items"
    }

    StyledText {
        width: parent.width
        text: "Usage: type the trigger, search, and press Enter. Type ! to show tmux sessions you can kill."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }
}
