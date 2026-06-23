import CoreAudio

var deviceListProp = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDevices,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
)

var dataSize: UInt32 = 0
AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &deviceListProp, 0, nil, &dataSize)

let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &deviceListProp, 0, nil, &dataSize, &deviceIDs)

var inputActive = false
for id in deviceIDs {
    var runningProp = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    var running: UInt32 = 0
    var runningSize = UInt32(MemoryLayout<UInt32>.size)
    let err = AudioObjectGetPropertyData(id, &runningProp, 0, nil, &runningSize, &running)
    if err == noErr && running > 0 {
        inputActive = true
        break
    }
}

print(inputActive ? "in_use" : "available")
