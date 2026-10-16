import CoreAudio
import Foundation

enum AudioActivity {
    /// True when some app other than SpotifyBar / Spotify is sending audio to the output device.
    static func isForeignAppUsingOutput() -> Bool {
        if let ids = runningOutputBundleIDs() {
            return ids.contains { isForeign($0) }
        }
        if SpotifyPlayer.isRunning { return false }
        return isDefaultOutputRunningSomewhere()
    }

    static func shouldClaimIdlePlayKey() -> Bool {
        if SpotifyPlayer.isRunning { return false }
        if isForeignAppUsingOutput() { return false }
        return true
    }

    private static func isForeign(_ bundleID: String) -> Bool {
        let id = bundleID.lowercased()
        if id.isEmpty { return false }
        if id.contains("spotifybar") { return false }
        if id == "com.spotify.client" { return false }
        if id.hasPrefix("com.apple.audio") { return false }
        if id.contains("coreaudiod") { return false }
        if id == "com.apple.controlcenter" { return false }
        return true
    }

    private static func runningOutputBundleIDs() -> [String]? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else {
            return nil
        }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var processes = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr else {
            return nil
        }
        return processes.compactMap { process in
            guard isProcessRunningOutput(process) else { return nil }
            return bundleID(of: process)
        }
    }

    private static func isProcessRunningOutput(_ process: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &running) == noErr else {
            return false
        }
        return running != 0
    }

    private static func bundleID(of process: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(process, &address, 0, nil, &size) == noErr, size > 0 else {
            return nil
        }
        var cfid: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &cfid) == noErr,
              let cfid else {
            return nil
        }
        // kAudioProcessPropertyBundleID: caller must release (+1).
        return cfid.takeRetainedValue() as String
    }

    private static func isDefaultOutputRunningSomewhere() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &device) == noErr else {
            return false
        }
        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &runningAddress, 0, nil, &size, &running) == noErr else {
            return false
        }
        return running != 0
    }
}
