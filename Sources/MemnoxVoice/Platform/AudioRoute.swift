import CoreAudio

/// The microphone and speakers in use, so echo cancellation that failed on one pair is tried again on the next.
struct AudioRoute: Equatable {
    let input: AudioDeviceID
    let output: AudioDeviceID

    static func current() -> AudioRoute {
        AudioRoute(input: defaultDevice(kAudioHardwarePropertyDefaultInputDevice),
                   output: defaultDevice(kAudioHardwarePropertyDefaultOutputDevice))
    }

    /// Both devices by name and rate, since echo cancellation most often fails on two that run at different rates.
    var described: String {
        "\(Self.describe(input)) into \(Self.describe(output))"
    }

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID {
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }

    /// What a device that will not say its name is called in the diary.
    private static let unnamed = "an unnamed device"

    private static func describe(_ device: AudioDeviceID) -> String {
        var name: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var nameAddress = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
        let named = AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &nameSize, &name) == noErr
        var rate: Float64 = 0
        var rateSize = UInt32(MemoryLayout<Float64>.size)
        var rateAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(device, &rateAddress, 0, nil, &rateSize, &rate)
        let label = named ? (name?.takeRetainedValue() as String?) ?? unnamed : unnamed
        return "\(label) at \(Int(rate)) Hz"
    }
}
