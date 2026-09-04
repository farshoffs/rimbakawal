import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    prepareRondaanReminderSound()
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func prepareRondaanReminderSound() {
    let assetKey = FlutterDartProject.lookupKey(forAsset: "assets/audio/patrol_alarm.wav")
    guard let sourcePath = Bundle.main.path(forResource: assetKey, ofType: nil),
          let source = try? Data(contentsOf: URL(fileURLWithPath: sourcePath)),
          source.count > 44 else {
      return
    }

    let byteRate = Int(readUInt32LE(source, offset: 28))
    guard byteRate > 0 else { return }
    let pcm = source.subdata(in: 44..<source.count)
    guard !pcm.isEmpty else { return }

    let targetBytes = byteRate * 29
    var output = Data(source.prefix(44))
    output.reserveCapacity(44 + targetBytes)
    while output.count < 44 + targetBytes {
      let remaining = 44 + targetBytes - output.count
      output.append(pcm.prefix(min(remaining, pcm.count)))
    }
    writeUInt32LE(UInt32(36 + targetBytes), into: &output, offset: 4)
    writeUInt32LE(UInt32(targetBytes), into: &output, offset: 40)

    let manager = FileManager.default
    guard let library = manager.urls(for: .libraryDirectory, in: .userDomainMask).first else {
      return
    }
    let sounds = library.appendingPathComponent("Sounds", isDirectory: true)
    try? manager.createDirectory(at: sounds, withIntermediateDirectories: true)
    let destination = sounds.appendingPathComponent("rondaan_reminder.wav")
    try? output.write(to: destination, options: .atomic)
  }

  private func readUInt32LE(_ data: Data, offset: Int) -> UInt32 {
    guard offset + 3 < data.count else { return 0 }
    return UInt32(data[offset])
      | (UInt32(data[offset + 1]) << 8)
      | (UInt32(data[offset + 2]) << 16)
      | (UInt32(data[offset + 3]) << 24)
  }

  private func writeUInt32LE(_ value: UInt32, into data: inout Data, offset: Int) {
    guard offset + 3 < data.count else { return }
    data[offset] = UInt8(value & 0xff)
    data[offset + 1] = UInt8((value >> 8) & 0xff)
    data[offset + 2] = UInt8((value >> 16) & 0xff)
    data[offset + 3] = UInt8((value >> 24) & 0xff)
  }
}
