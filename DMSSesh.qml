import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services

QtObject {
    id: root

    property var pluginService: null
    property string pluginId: "dmsSesh"
    property string trigger: "se"

    signal itemsChanged

    property string seshBinary: "sesh"
    property string configPath: ""
    property string terminal: "alacritty"
    property string customTerminal: ""
    property string terminalBehavior: "newWindow"
    property bool includeTmux: true
    property bool includeConfig: true
    property bool includeZoxide: true
    property bool includeTmuxinator: false
    property bool hideAttached: false
    property int maxResults: 50

    property var cachedEntries: []
    property string listRawData: ""

    readonly property var terminalConfigs: ({
        "st": { executable: "st", execFlag: "-e" },
        "alacritty": { executable: "alacritty", execFlag: "-e" },
        "kitty": { executable: "kitty", execFlag: "-e" },
        "wezterm": { executable: "wezterm", execFlag: "start --" },
        "foot": { executable: "foot", execFlag: "-e" },
        "konsole": { executable: "konsole", execFlag: "-e" },
        "gnome-terminal": { executable: "gnome-terminal", execFlag: "--" },
        "xterm": { executable: "xterm", execFlag: "-e" },
        "ghostty": { executable: "ghostty", execFlag: "-e" },
        "Custom": { executable: "", execFlag: "-e" }
    })

    property var initTimer: Timer {
        interval: 100
        repeat: false
        running: true
        onTriggered: root.refreshCache()
    }

    property var listProcess: Process {
        command: ["sesh", "list", "-j", "-d"]
        running: false

        stdout: SplitParser {
            splitMarker: ""
            onRead: function(data) {
                root.listRawData += data
            }
        }

        onExited: function(exitCode) {
            if (exitCode !== 0) {
                console.warn("DMS Sesh: sesh list failed", exitCode)
                root.cachedEntries = []
                root.itemsChanged()
                return
            }

            root.parseListData()
        }
    }

    property var killSessionProcess: Process {
        property string targetName: ""

        command: ["tmux", "kill-session", "-t", ""]
        running: false

        onExited: function(exitCode) {
            if (exitCode === 0) {
                ToastService.showInfo("DMS Sesh", "Killed tmux session: " + targetName)
            } else {
                ToastService.showInfo("DMS Sesh", "Failed to kill tmux session: " + targetName)
            }
            root.refreshCache()
        }
    }

    property var killTerminalProcess: Process {
        command: ["pkill", "-x", ""]
        running: false
    }

    Component.onCompleted: {
        if (!pluginService)
            return

        trigger = pluginService.loadPluginData(pluginId, "trigger", "se")
        seshBinary = pluginService.loadPluginData(pluginId, "binaryPath", "sesh")
        configPath = pluginService.loadPluginData(pluginId, "configPath", "")
        terminal = pluginService.loadPluginData(pluginId, "terminal", "alacritty")
        customTerminal = pluginService.loadPluginData(pluginId, "customTerminal", "")
        terminalBehavior = pluginService.loadPluginData(pluginId, "terminalBehavior", "newWindow")
        includeTmux = pluginService.loadPluginData(pluginId, "includeTmux", true)
        includeConfig = pluginService.loadPluginData(pluginId, "includeConfig", true)
        includeZoxide = pluginService.loadPluginData(pluginId, "includeZoxide", true)
        includeTmuxinator = pluginService.loadPluginData(pluginId, "includeTmuxinator", false)
        hideAttached = pluginService.loadPluginData(pluginId, "hideAttached", false)
        maxResults = parseInt(pluginService.loadPluginData(pluginId, "maxResults", "50"), 10) || 50
    }

    function persist(key, value) {
        if (pluginService)
            pluginService.savePluginData(pluginId, key, value)
    }

    function refreshCache() {
        listRawData = ""
        cachedEntries = []

        const command = buildListCommand()
        if (command.length === 0) {
            itemsChanged()
            return
        }

        listProcess.command = command
        listProcess.running = true
    }

    function hasEnabledSources() {
        return includeTmux || includeConfig || includeZoxide || includeTmuxinator
    }

    function getConfiguredConfigPath() {
        return String(configPath || "").trim()
    }

    function buildSeshArgs(args) {
        const command = [seshBinary]
        const configuredConfigPath = getConfiguredConfigPath()

        if (configuredConfigPath) {
            command.push("-C")
            command.push(configuredConfigPath)
        }

        return command.concat(args || [])
    }

    function buildSeshShellCommand(args) {
        return "XDG_CONFIG_HOME=\"${XDG_CONFIG_HOME:-$HOME/.config}\" " + shellJoin(buildSeshArgs(args))
    }

    function buildListCommand() {
        const args = ["list", "-j", "-d"]

        if (includeTmux)
            args.push("-t")
        if (includeConfig)
            args.push("-c")
        if (includeZoxide)
            args.push("-z")
        if (includeTmuxinator)
            args.push("-T")
        if (hideAttached)
            args.push("-H")

        return hasEnabledSources() ? ["sh", "-lc", buildSeshShellCommand(args)] : []
    }

    function parseListData() {
        if (!listRawData) {
            cachedEntries = []
            itemsChanged()
            return
        }

        try {
            const data = JSON.parse(listRawData)
            const entries = []

            for (let i = 0; i < data.length; i++) {
                const raw = data[i]
                const source = String(raw.Src || "")
                const name = String(raw.Name || "")
                const path = String(raw.Path || "")
                const target = source === "zoxide" ? path : (name || path)

                if (!target)
                    continue

                entries.push({
                    source: source,
                    name: name || path,
                    path: path,
                    target: target,
                    attached: Number(raw.Attached || 0),
                    windows: Number(raw.Windows || 0),
                    score: Number(raw.Score || 0),
                    lowerSearch: [source, name, path, target].join(" ").toLowerCase()
                })
            }

            cachedEntries = entries
            itemsChanged()
        } catch (error) {
            console.warn("DMS Sesh: failed to parse sesh output", error)
            cachedEntries = []
            itemsChanged()
        }
    }

    function getTerminalExecutable() {
        if (terminal === "Custom" && customTerminal)
            return customTerminal

        const config = terminalConfigs[terminal] || terminalConfigs["alacritty"]
        return config.executable
    }

    function getTerminalExecFlag() {
        const config = terminalConfigs[terminal] || terminalConfigs["alacritty"]
        return config.execFlag
    }

    function makeRefreshItem() {
        return {
            name: "↻ Refresh sesh cache",
            comment: "Reload sessions and projects from sesh",
            action: encodeAction("refresh", {}),
            icon: "material:refresh",
            categories: ["DMS Sesh"]
        }
    }

    function makeHintItem() {
        return {
            name: "Open sesh picker",
            comment: "Search tmux sessions, config sessions, and zoxide projects",
            action: encodeAction("hint", {}),
            icon: "material:info",
            categories: ["DMS Sesh"]
        }
    }

    function makeEmptySourcesItem() {
        return {
            name: "No sesh sources enabled",
            comment: "Enable tmux, config, zoxide, or tmuxinator sources in plugin settings",
            action: encodeAction("hint", {}),
            icon: "material:warning",
            categories: ["DMS Sesh"]
        }
    }

    function sourceLabel(source) {
        if (source === "tmux")
            return "tmux session"
        if (source === "config")
            return "configured session"
        if (source === "tmuxinator")
            return "tmuxinator"
        if (source === "zoxide")
            return "zoxide project"
        return source || "session"
    }

    function sourceIcon(source) {
        if (source === "tmux")
            return "material:terminal"
        if (source === "zoxide")
            return "material:folder"
        return "material:play_arrow"
    }

    function buildEntryItem(entry) {
        let comment = sourceLabel(entry.source)
        if (entry.path)
            comment += " • " + entry.path
        if (entry.source === "tmux" && entry.windows > 0)
            comment += " • " + entry.windows + " window" + (entry.windows === 1 ? "" : "s")

        return {
            name: entry.name,
            comment: comment,
            action: encodeAction("connect", {
                source: entry.source,
                target: entry.target,
                label: entry.name
            }),
            icon: sourceIcon(entry.source),
            categories: ["DMS Sesh"]
        }
    }

    function buildKillItems(query, limit) {
        const filters = query.toLowerCase().split(/\s+/).filter(function(part) { return part.length > 0 })
        const items = []

        for (let i = 0; i < cachedEntries.length && items.length < limit; i++) {
            const entry = cachedEntries[i]
            if (entry.source !== "tmux")
                continue
            if (!matchesFilters(entry.lowerSearch, filters))
                continue

            items.push({
                name: "Kill session: " + entry.name,
                comment: entry.path || "tmux session",
                action: encodeAction("kill", {
                    target: entry.name
                }),
                icon: "material:close",
                categories: ["DMS Sesh"]
            })
        }

        return items
    }

    function matchesFilters(haystack, filters) {
        if (filters.length === 0)
            return true

        for (let i = 0; i < filters.length; i++) {
            if (haystack.indexOf(filters[i]) === -1)
                return false
        }

        return true
    }

    function getItems(query) {
        const trimmed = (query || "").trim()

        if (trimmed.indexOf("!") === 0) {
            const killItems = buildKillItems(trimmed.substring(1).trim(), maxResults)
            killItems.push(makeRefreshItem())
            return killItems
        }

        const filters = trimmed.toLowerCase().split(/\s+/).filter(function(part) { return part.length > 0 })
        const items = []

        if (trimmed === "")
            items.push(makeHintItem())

        if (!hasEnabledSources())
            items.push(makeEmptySourcesItem())

        for (let i = 0; i < cachedEntries.length && items.length < maxResults; i++) {
            const entry = cachedEntries[i]
            if (matchesFilters(entry.lowerSearch, filters))
                items.push(buildEntryItem(entry))
        }

        items.push(makeRefreshItem())
        return items
    }

    function executeItem(item) {
        const action = decodeAction(item ? item.action : "")
        if (!action)
            return

        if (action.type === "refresh") {
            refreshCache()
            ToastService.showInfo("DMS Sesh", "Refreshing sesh cache")
            return
        }

        if (action.type === "hint") {
            ToastService.showInfo("DMS Sesh", "Type to filter sesh results, then press Enter")
            return
        }

        if (action.type === "kill") {
            killSessionProcess.targetName = action.payload.target
            killSessionProcess.command = ["tmux", "kill-session", "-t", action.payload.target]
            killSessionProcess.running = true
            return
        }

        if (action.type === "connect") {
            launchEntry(action.payload)
        }
    }

    function launchEntry(payload) {
        const connectArgs = ["connect"]
        if (payload.source === "tmuxinator")
            connectArgs.push("-T")
        connectArgs.push(payload.target)

        if (terminalBehavior === "switchClient") {
            const hasTmuxClient = !!Quickshell.env("TMUX")
            if (hasTmuxClient) {
                const switchArgs = ["connect", "--switch"]
                if (payload.source === "tmuxinator")
                    switchArgs.push("-T")
                switchArgs.push(payload.target)
                Quickshell.execDetached(["sh", "-lc", buildSeshShellCommand(switchArgs)])
                ToastService.showInfo("DMS Sesh", "Switching to " + payload.label)
                return
            }

            ToastService.showInfo("DMS Sesh", "No tmux client detected, opening in a terminal instead")
        }

        if (terminalBehavior === "killExisting") {
            const executable = getTerminalExecutable()
            killTerminalProcess.command = ["pkill", "-x", processName(executable)]
            killTerminalProcess.running = true

            Qt.callLater(function() {
                launchInTerminal(connectArgs, payload.label)
            })
            return
        }

        launchInTerminal(connectArgs, payload.label)
    }

    function launchInTerminal(connectArgs, label) {
        const command = []
        const executable = getTerminalExecutable()
        const execFlag = getTerminalExecFlag()
        const launchCommand = "unset TMUX TMUX_PANE; " + buildSeshShellCommand(connectArgs)

        command.push(executable)
        execFlag.split(" ").forEach(function(part) {
            if (part)
                command.push(part)
        })
        command.push("sh")
        command.push("-lc")
        command.push(launchCommand + "; status=$?; if [ $status -ne 0 ]; then echo; echo 'sesh connect failed. Press Enter to close...'; read _; fi; exec \"${SHELL:-/bin/sh}\" -i")

        Quickshell.execDetached(command)
        ToastService.showInfo("DMS Sesh", "Opening " + label)
    }

    function encodeAction(type, payload) {
        return JSON.stringify({ type: type, payload: payload || {} })
    }

    function decodeAction(action) {
        if (!action)
            return null

        try {
            return JSON.parse(action)
        } catch (error) {
            console.warn("DMS Sesh: action decode failed", error)
            return null
        }
    }

    function processName(command) {
        const firstPart = String(command || "").split(/\s+/)[0]
        const slashIndex = firstPart.lastIndexOf("/")
        return slashIndex >= 0 ? firstPart.substring(slashIndex + 1) : firstPart
    }

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'"
    }

    function shellJoin(parts) {
        return parts.map(function(part) { return shellQuote(part) }).join(" ")
    }

    onTriggerChanged: {
        persist("trigger", trigger)
        itemsChanged()
    }

    onSeshBinaryChanged: persist("binaryPath", seshBinary)
    onConfigPathChanged: { persist("configPath", configPath); refreshCache() }
    onTerminalChanged: persist("terminal", terminal)
    onCustomTerminalChanged: persist("customTerminal", customTerminal)
    onTerminalBehaviorChanged: persist("terminalBehavior", terminalBehavior)
    onIncludeTmuxChanged: { persist("includeTmux", includeTmux); refreshCache() }
    onIncludeConfigChanged: { persist("includeConfig", includeConfig); refreshCache() }
    onIncludeZoxideChanged: { persist("includeZoxide", includeZoxide); refreshCache() }
    onIncludeTmuxinatorChanged: { persist("includeTmuxinator", includeTmuxinator); refreshCache() }
    onHideAttachedChanged: { persist("hideAttached", hideAttached); refreshCache() }
    onMaxResultsChanged: persist("maxResults", String(maxResults))
}
