// camera-list — enumerate video capture devices, one per line:
//     <index>\t<kind>\t<name>
// where <kind> is "builtin", "continuity" or "external".
//
// Why this exists: OpenCV opens a camera by index, and on a Mac paired with an iPhone
// macOS happily makes the iPhone the first device. Unlocking sudo would then wake the
// phone instead of using the webcam sitting right there. The daemon uses this listing to
// pick the built-in camera unless the user asked for a specific one.
//
// The discovery session mirrors what OpenCV's AVFoundation backend enumerates, so the
// indices printed here match the ones VideoCapture expects.
import AVFoundation
import Foundation

var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external]
if #available(macOS 14.0, *) {
    types.append(.continuityCamera)
}

let session = AVCaptureDevice.DiscoverySession(
    deviceTypes: types, mediaType: .video, position: .unspecified)

for (index, device) in session.devices.enumerated() {
    var kind = "external"
    if device.deviceType == .builtInWideAngleCamera {
        kind = "builtin"
    } else if #available(macOS 14.0, *), device.deviceType == .continuityCamera {
        kind = "continuity"
    } else if device.modelID.contains("iPhone") || device.modelID.contains("iPad") {
        // Older systems surface Continuity cameras as plain external devices.
        kind = "continuity"
    }
    print("\(index)\t\(kind)\t\(device.localizedName)")
}
