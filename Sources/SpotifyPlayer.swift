import AppKit
import Foundation

enum SpotifyPlayer {
    static let bundleID = "com.spotify.client"
    private static let musicID = "com.apple.Music"

    private static var playGeneration = 0
    private static var hideUntil: Date?
    private static var appleEventsStale = false
    private static var activationObserver: NSObjectProtocol?
    private static var unhideObserver: NSObjectProtocol?
    private static var wakeObserver: NSObjectProtocol?
    private static var screensWakeObserver: NSObjectProtocol?

    static var lastURI: String {
        get {
            let value = UserDefaults.standard.string(forKey: StorageKeys.lastURI) ?? ""
            return isPlayable(value) ? value : ""
        }
        set {
            if isPlayable(newValue) {
                UserDefaults.standard.set(newValue, forKey: StorageKeys.lastURI)
            }
        }
    }

    static var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    static func watchSystemEvents() {
        let center = NSWorkspace.shared.notificationCenter
        if wakeObserver == nil {
            wakeObserver = center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { _ in
                appleEventsStale = true
            }
        }
        if screensWakeObserver == nil {
            screensWakeObserver = center.addObserver(
                forName: NSWorkspace.screensDidWakeNotification,
                object: nil,
                queue: .main
            ) { _ in
                appleEventsStale = true
            }
        }
        startObserversIfNeeded()
    }

    static func snapshot() async -> PlayerSnapshot? {
        guard isRunning else { return .idle }
        let output = await script("""
          try
            set s to player state as text
          on error
            set s to "stopped"
          end try
          try
            set n to name of current track
            set a to artist of current track
            set u to spotify url of current track
            try
              set art to artwork url of current track as text
            on error
              set art to ""
            end try
            return s & "|||" & n & "|||" & a & "|||" & u & "|||" & art
          on error
            return s & "|||"
          end try
        """)
        guard let output else { return nil }
        let parts = output.components(separatedBy: "|||")
        let state = parts.first ?? "stopped"
        if parts.count > 3, isPlayable(parts[3]) {
            lastURI = parts[3]
        }
        let art = parts.count > 4 ? parts[4].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return PlayerSnapshot(
            isRunning: true,
            isPlaying: state == "playing",
            title: parts.count > 1 ? parts[1] : "",
            artist: parts.count > 2 ? parts[2] : "",
            artworkURL: URL(string: art)
        )
    }

    @discardableResult
    static func ensureReady() async -> Bool {
        if isRunning {
            let responsive = await ping()
            if appleEventsStale || !responsive {
                await recover()
            }
            hideWindow()
            return await ping()
        }
        let musicWasRunning = isMusicRunning
        launchHidden()
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 150_000_000)
            if let app = spotifyApp, app.isFinishedLaunching, await ping() {
                break
            }
        }
        hideWindow()
        if !musicWasRunning { quitMusicIfLaunched() }
        appleEventsStale = false
        return await ping()
    }

    static func hideWindow() {
        spotifyApp?.hide()
    }

    static func play() async {
        let wasRunning = isRunning
        let musicWasRunning = isMusicRunning
        suppressWindow(for: 1.5)
        _ = await ensureReady()
        guard isRunning else { return }
        if wasRunning && lastURI.isEmpty {
            _ = await script("set player state to playing")
            hideWindow()
        } else if !lastURI.isEmpty, !wasRunning {
            await playURI(lastURI)
        } else if wasRunning {
            _ = await script("set player state to playing")
            hideWindow()
            if !(await isPlaying()) , !lastURI.isEmpty {
                await playURI(lastURI)
            }
        } else {
            _ = await script("set player state to playing")
            hideWindow()
        }
        if !musicWasRunning { quitMusicIfLaunched() }
    }

    static func pause() async {
        guard isRunning else { return }
        suppressWindow(for: 1)
        _ = await script("set player state to paused")
        hideWindow()
    }

    static func playURI(_ uri: String) async {
        guard isPlayable(uri) else { return }
        playGeneration += 1
        let generation = playGeneration
        lastURI = uri
        let musicWasRunning = isMusicRunning
        suppressWindow(for: 2.5)
        _ = await ensureReady()
        guard generation == playGeneration, isRunning else { return }
        await sendPlay(uri)
        if generation == playGeneration, !(await isPlaying(uri: uri)) {
            let responsive = await ping()
            if !responsive {
                await recover()
            }
            guard generation == playGeneration else { return }
            await sendPlay(uri)
        }
        hideWindow()
        for _ in 0..<8 {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard generation == playGeneration else { return }
            hideWindow()
        }
        if !musicWasRunning { quitMusicIfLaunched() }
    }

    private static func sendPlay(_ uri: String) async {
        let escaped = uri.replacingOccurrences(of: "\"", with: "")
        _ = await script("play track \"\(escaped)\"")
        hideWindow()
        try? await Task.sleep(nanoseconds: 400_000_000)
    }

    private static func ping() async -> Bool {
        await script("return \"ok\"", timeout: 2) == "ok"
    }

    private static func isPlaying(uri: String? = nil) async -> Bool {
        let state = await script("""
          try
            return player state as text
          on error
            return "stopped"
          end try
        """, timeout: 2) ?? "stopped"
        guard state == "playing" else { return false }
        guard let uri else { return true }
        let current = await script("""
          try
            return spotify url of current track as text
          on error
            return ""
          end try
        """, timeout: 2) ?? ""
        if current.isEmpty { return false }
        return current == uri
    }

    private static func recover() async {
        appleEventsStale = false
        nudge()
        try? await Task.sleep(nanoseconds: 250_000_000)
        if await ping() {
            hideWindow()
            return
        }
        suppressWindow(for: 2)
        spotifyApp?.activate(options: [.activateIgnoringOtherApps])
        try? await Task.sleep(nanoseconds: 400_000_000)
        hideWindow()
        if await ping() { return }
        await relaunchHidden()
    }

    private static func relaunchHidden() async {
        suppressWindow(for: 3)
        spotifyApp?.terminate()
        for _ in 0..<25 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if !isRunning { break }
        }
        if isRunning {
            spotifyApp?.forceTerminate()
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        launchHidden()
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 150_000_000)
            if let app = spotifyApp, app.isFinishedLaunching, await ping() {
                break
            }
        }
        hideWindow()
        appleEventsStale = false
    }

    private static func nudge() {
        runOpen(["-g", "-b", bundleID])
    }

    private static func suppressWindow(for seconds: TimeInterval) {
        hideUntil = Date().addingTimeInterval(seconds)
        startObserversIfNeeded()
        hideWindow()
    }

    private static var shouldHide: Bool {
        guard let hideUntil else { return false }
        return Date() < hideUntil
    }

    private static func startObserversIfNeeded() {
        let center = NSWorkspace.shared.notificationCenter
        if activationObserver == nil {
            activationObserver = center.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { note in
                guard shouldHide else { return }
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == bundleID else { return }
                app.hide()
            }
        }
        if unhideObserver == nil {
            unhideObserver = center.addObserver(
                forName: NSWorkspace.didUnhideApplicationNotification,
                object: nil,
                queue: .main
            ) { note in
                guard shouldHide else { return }
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == bundleID else { return }
                app.hide()
            }
        }
    }

    private static var spotifyApp: NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
    }

    private static func isPlayable(_ uri: String) -> Bool {
        uri.hasPrefix("spotify:track:")
            || uri.hasPrefix("spotify:album:")
            || uri.hasPrefix("spotify:playlist:")
    }

    private static func launchHidden() {
        runOpen(["-b", bundleID, "-j", "-g"])
    }

    private static func runOpen(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        try? process.run()
        process.waitUntilExit()
    }

    private static var isMusicRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == musicID }
    }

    private static func quitMusicIfLaunched() {
        NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == musicID }
            .forEach { $0.terminate() }
    }

    @discardableResult
    private static func script(_ command: String, timeout: TimeInterval = 4) async -> String? {
        guard isRunning else { return nil }
        switch await AppleScript.run("""
        tell application id "\(bundleID)"
          \(command)
        end tell
        """, timeout: timeout) {
        case .success(let text):
            return text
        case .timedOut:
            appleEventsStale = true
            return nil
        case .failed:
            return nil
        }
    }
}
