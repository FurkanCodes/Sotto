import CoreAudio

/// Lowers the default output device's volume while dictating, so music and
/// video don't bleed into the mic, then puts it back.
@MainActor
enum SystemVolume {
    private static var saved: (device: AudioDeviceID, volumes: [UInt32: Float32])?

    /// Turns the volume down to `fraction` of where it is. Devices with no
    /// software volume (some HDMI and USB outputs) are left alone.
    static func lower(to fraction: Float32 = 0.2) {
        guard saved == nil, let device = defaultOutput() else { return }
        let volumes = elements(of: device).reduce(into: [UInt32: Float32]()) { result, element in
            if let volume = volume(device, element) { result[element] = volume }
        }
        guard !volumes.isEmpty else { return }
        saved = (device, volumes)
        for (element, volume) in volumes { setVolume(device, element, volume * fraction) }
    }

    static func restore() {
        guard let saved else { return }
        self.saved = nil
        for (element, volume) in saved.volumes { setVolume(saved.device, element, volume) }
    }

    private static func defaultOutput() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0
        else { return nil }
        return device
    }

    /// The main element if it has a volume, else the left and right channels.
    private static func elements(of device: AudioDeviceID) -> [UInt32] {
        volume(device, kAudioObjectPropertyElementMain) != nil ? [kAudioObjectPropertyElementMain] : [1, 2]
    }

    private static func address(_ element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
    }

    private static func volume(_ device: AudioDeviceID, _ element: UInt32) -> Float32? {
        var address = address(element)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else { return nil }
        return volume
    }

    private static func setVolume(_ device: AudioDeviceID, _ element: UInt32, _ value: Float32) {
        var address = address(element)
        var volume = max(0, min(1, value))
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
    }
}
