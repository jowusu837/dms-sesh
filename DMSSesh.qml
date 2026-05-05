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
    property bool debugEnabled: false
    property int maxResults: 50

    property var cachedEntries: []
    property string listRawData: ""
    property string listStderrData: ""
    property string debugLogPath: ((Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") ? Quickshell.env("HOME") + "/.cache" : "/tmp")) + "/dms-sesh/debug.log")

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
        command: ["sh", "-lc", "sesh list -j -d"]
        running: false

        stdout: SplitParser {
            splitMarker: ""
            onRead: function(data) {
                root.listRawData += data
            }
        }

        stderr: SplitParser {
            splitMarker: ""
            onRead: function(data) {
                root.listStderrData += data
            }
        }

        onRunningChanged: {
            if (running)
                root.debugLog("list process started", { command: command })
        }

        onExited: function(exitCode) {
            root.debugLog("list process exited", {
                exitCode: exitCode,
                stdoutBytes: root.listRawData.length,
                stderrBytes: root.listStderrData.length,
                stderr: root.listStderrData.trim()
            })

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
        debugEnabled = pluginService.loadPluginData(pluginId, "debugEnabled", false)
        maxResults = parseInt(pluginService.loadPluginData(pluginId, "maxResults", "50"), 10) || 50

        debugLog("plugin initialized", {
            trigger: trigger,
            seshBinary: seshBinary,
            configPath: configPath,
            includeTmux: includeTmux,
            includeConfig: includeConfig,
            includeZoxide: includeZoxide,
            includeTmuxinator: includeTmuxinator,
            hideAttached: hideAttached,
            debugEnabled: debugEnabled,
            maxResults: maxResults,
            debugLogPath: debugLogPath
        })
    }

    function persist(key, value) {
        if (pluginService)
            pluginService.savePluginData(pluginId, key, value)
    }

    function refreshCache() {
        listRawData = ""
        listStderrData = ""
        cachedEntries = []

        const command = buildListCommand()
        debugLog("refreshing cache", {
            command: command,
            seshBinary: seshBinary,
            configPath: getConfiguredConfigPath(),
            includeTmux: includeTmux,
            includeConfig: includeConfig,
            includeZoxide: includeZoxide,
            includeTmuxinator: includeTmuxinator,
            hideAttached: hideAttached
        })

        if (command.length === 0) {
            debugLog("refresh skipped because no sources are enabled")
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
        const command = [String(seshBinary || "sesh").trim() || "sesh"]
        const configuredConfigPath = getConfiguredConfigPath()

        if (configuredConfigPath) {
            command.push("-C")
            command.push(configuredConfigPath)
        }

        return command.concat(args || [])
    }

    function buildSeshShellCommand(args) {
        const seshArgs = buildSeshArgs(args)
        const requestedBinary = seshArgs.shift()
        return "XDG_CONFIG_HOME=\"${XDG_CONFIG_HOME:-$HOME/.config}\"; " +
            "SESH_BIN=" + shellQuote(requestedBinary) + "; " +
            "if [ \"${SESH_BIN#*/}\" = \"$SESH_BIN\" ]; then " +
            "if [ -x \"$HOME/go/bin/$SESH_BIN\" ]; then SESH_BIN=\"$HOME/go/bin/$SESH_BIN\"; " +
            "elif [ -x \"$HOME/.local/bin/$SESH_BIN\" ]; then SESH_BIN=\"$HOME/.local/bin/$SESH_BIN\"; " +
            "elif command -v \"$SESH_BIN\" >/dev/null 2>&1; then SESH_BIN=\"$(command -v \"$SESH_BIN\")\"; " +
            "elif ls \"$HOME/.local/share/mise/installs/go\"/*/bin/\"$SESH_BIN\" >/dev/null 2>&1; then SESH_BIN=\"$(ls \"$HOME/.local/share/mise/installs/go\"/*/bin/\"$SESH_BIN\" | tail -n 1)\"; " +
            "fi; " +
            "fi; " +
            "\"$SESH_BIN\" " + shellJoin(seshArgs)
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

            debugLog("parsed sesh entries", { count: entries.length })
            cachedEntries = entries
            itemsChanged()
        } catch (error) {
            console.warn("DMS Sesh: failed to parse sesh output", error)
            debugLog("failed to parse sesh output", {
                error: String(error),
                stdoutSample: listRawData.substring(0, 1000),
                stderr: listStderrData.trim()
            })
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
                label: entry.name,
                path: entry.path,
                name: entry.name
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
        debugLog("launching entry", payload)

        const resolvedTarget = resolveConnectTarget(payload)
        debugLog("resolved connect target", {
            source: payload.source,
            requestedTarget: payload.target,
            resolvedTarget: resolvedTarget,
            path: payload.path
        })

        const hasTmuxClient = !!Quickshell.env("TMUX")
        if (terminalBehavior === "switchClient") {
            if (hasTmuxClient) {
                const switchCommand = buildSwitchShellCommand(payload, resolvedTarget)
                debugLog("switching via shell command", { shellCommand: switchCommand })
                Quickshell.execDetached(["sh", "-lc", switchCommand])
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
                launchInTerminal(payload, resolvedTarget, payload.label)
            })
            return
        }

        launchInTerminal(payload, resolvedTarget, payload.label)
    }

    function resolveConnectTarget(payload) {
        if (payload.source === "zoxide" && payload.path) {
            for (let i = 0; i < cachedEntries.length; i++) {
                const entry = cachedEntries[i]
                if (entry.source === "tmux" && entry.path === payload.path && entry.name)
                    return entry.name
            }
        }

        return payload.target
    }

    function isExistingTmuxTarget(payload, resolvedTarget) {
        if (payload.source === "tmux")
            return true

        if (payload.source === "zoxide" && payload.path && resolvedTarget !== payload.path)
            return true

        return false
    }

    function buildSwitchShellCommand(payload, resolvedTarget) {
        if (isExistingTmuxTarget(payload, resolvedTarget))
            return "tmux switch-client -t " + shellQuote(resolvedTarget)

        const switchArgs = ["connect", "--switch"]
        if (payload.source === "tmuxinator")
            switchArgs.push("-T")
        switchArgs.push(resolvedTarget)
        return buildSeshShellCommand(switchArgs)
    }

    function tmuxSessionNameForTarget(payload, resolvedTarget) {
        if (payload.source === "tmux" && resolvedTarget)
            return resolvedTarget

        const sourcePath = String(payload.path || resolvedTarget || "")
        const normalized = sourcePath.replace(/\/+$/, "")
        const parts = normalized.split("/")
        return parts.length > 0 ? parts[parts.length - 1] : normalized
    }

    function buildLaunchShellCommand(payload, resolvedTarget) {
        if (isExistingTmuxTarget(payload, resolvedTarget))
            return "unset TMUX TMUX_PANE; tmux attach-session -t " + shellQuote(resolvedTarget)

        const connectArgs = ["connect"]
        if (payload.source === "tmuxinator")
            connectArgs.push("-T")
        connectArgs.push(resolvedTarget)

        const sessionName = tmuxSessionNameForTarget(payload, resolvedTarget)
        return "unset TMUX TMUX_PANE; " +
            "SESH_SESSION_NAME=" + shellQuote(sessionName) + "; " +
            buildSeshShellCommand(connectArgs) + "; " +
            "status=$?; " +
            "if [ $status -ne 0 ] && tmux has-session -t \"$SESH_SESSION_NAME\" 2>/dev/null; then " +
            "tmux attach-session -t \"$SESH_SESSION_NAME\"; " +
            "else " +
            "exit $status; " +
            "fi"
    }

    function launchInTerminal(payload, resolvedTarget, label) {
        const command = []
        const executable = getTerminalExecutable()
        const execFlag = getTerminalExecFlag()
        const launchCommand = buildLaunchShellCommand(payload, resolvedTarget)

        debugLog("launching terminal command", {
            terminal: terminal,
            executable: executable,
            execFlag: execFlag,
            source: payload.source,
            resolvedTarget: resolvedTarget,
            shellCommand: launchCommand
        })

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

    function debugLog(message, details) {
        if (!debugEnabled)
            return

        const timestamp = (new Date()).toISOString()
        let line = timestamp + " " + message

        if (details !== undefined) {
            try {
                line += " " + JSON.stringify(details)
            } catch (error) {
                line += " [details-unserializable]"
            }
        }

        console.log("DMS Sesh:", line)
        Quickshell.execDetached([
            "sh",
            "-lc",
            "mkdir -p " + shellQuote(parentDirectory(debugLogPath)) +
                " && printf '%s\\n' " + shellQuote(line) +
                " >> " + shellQuote(debugLogPath)
        ])
    }

    function parentDirectory(path) {
        const normalized = String(path || "")
        const slashIndex = normalized.lastIndexOf("/")
        return slashIndex > 0 ? normalized.substring(0, slashIndex) : "."
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

    onSeshBinaryChanged: { persist("binaryPath", seshBinary); refreshCache() }
    onConfigPathChanged: { persist("configPath", configPath); refreshCache() }
    onTerminalChanged: persist("terminal", terminal)
    onCustomTerminalChanged: persist("customTerminal", customTerminal)
    onTerminalBehaviorChanged: persist("terminalBehavior", terminalBehavior)
    onIncludeTmuxChanged: { persist("includeTmux", includeTmux); refreshCache() }
    onIncludeConfigChanged: { persist("includeConfig", includeConfig); refreshCache() }
    onIncludeZoxideChanged: { persist("includeZoxide", includeZoxide); refreshCache() }
    onIncludeTmuxinatorChanged: { persist("includeTmuxinator", includeTmuxinator); refreshCache() }
    onHideAttachedChanged: { persist("hideAttached", hideAttached); refreshCache() }
    onDebugEnabledChanged: persist("debugEnabled", debugEnabled)
    onMaxResultsChanged: persist("maxResults", String(maxResults))
}
