import AppKit
import AVFoundation
import CoreMedia
import Foundation

// ===== 1. Per-screen wallpaper, 5 fill modes =====
enum WallpaperFill: String, CaseIterable, Sendable { case fit, fill, stretch, center, tile }

@available(macOS 26.0, *)
func setWallpaper(_ url: URL, screen: NSScreen, fill: WallpaperFill) throws {
    var opts: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
    switch fill {
    case .fit:     opts[.imageScaling] = NSImageScaling.scaleProportionallyUpOrDown; opts[.allowClipping] = false
    case .fill:    opts[.imageScaling] = NSImageScaling.scaleProportionallyUpOrDown; opts[.allowClipping] = true
    case .stretch: opts[.imageScaling] = NSImageScaling.scaleAxesIndependently
    case .center:  opts[.imageScaling] = NSImageScaling.scaleNone
    case .tile:    opts[.imageScaling] = NSImageScaling.scaleNone
    }
    try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: opts)
}

// ===== 2. Desktop-level window =====
@available(macOS 26.0, *)
func makeWallpaperWindow(_ screen: NSScreen) -> NSWindow {
    let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
    w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
    w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
    w.sharingType = .none
    w.isOpaque = false
    w.backgroundColor = .clear
    w.ignoresMouseEvents = true
    w.hasShadow = false
    return w
}

// ===== 3. Looping playback =====
@available(macOS 26.0, *)
func makeLoopingPlayer(_ url: URL) -> (AVQueuePlayer, AVPlayerLooper, AVPlayerLayer) {
    let player = AVQueuePlayer()
    player.isMuted = true
    player.actionAtItemEnd = .none
    let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
    let layer = AVPlayerLayer(player: player)
    layer.videoGravity = .resizeAspectFill
    return (player, looper, layer)
}

// ===== 4. Editor export using macOS 26 API =====
@available(macOS 26.0, *)
func exportLoop(source: AVURLAsset, range: CMTimeRange, size: CGSize, to out: URL) async throws {
    let comp = AVMutableComposition()
    guard let src = try await source.loadTracks(withMediaType: .video).first,
          let dest = comp.addMutableTrack(
              withMediaType: .video,
              preferredTrackID: kCMPersistentTrackID_Invalid)
    else { throw CocoaError(.fileReadCorruptFile) }
    try dest.insertTimeRange(range, of: src, at: .zero)
    guard let ct = try await comp.loadTracks(withMediaType: .video).first else { return }

    let layer = AVVideoCompositionLayerInstruction(
        configuration: .init(assetTrack: ct))
    let instr = AVVideoCompositionInstruction(
        configuration: .init(backgroundColor: CGColor(gray: 0, alpha: 1),
                             layerInstructions: [layer],
                             timeRange: range))
    let session = AVAssetExportSession(asset: comp,
                                       presetName: AVAssetExportPresetHEVCHighestQuality)!
    session.videoComposition = AVVideoComposition(
        configuration: .init(instructions: [instr], renderSize: size))
    session.shouldOptimizeForNetworkUse = true
    try await session.export(to: out, as: .mp4)
}

// ===== 5. Screen observation =====
@available(macOS 26.0, *)
let notifications: [Notification.Name] = [
    NSApplication.didChangeScreenParametersNotification,
    NSWorkspace.activeSpaceDidChangeNotification,
    NSWorkspace.didWakeNotification,
    NSWorkspace.screensDidSleepNotification,
    NSWorkspace.sessionDidResignActiveNotification
]

// ===== 6. Display identity + physical pixel geometry (F2) =====

/// Two-tier display identity.
///
/// `CGDirectDisplayID` is unique per attached display and stable for the running
/// session, but Apple documents it as typically constant only "until the machine is
/// restarted", and it is also known to change when the display switches GPU on
/// multi-GPU hardware. So it is used as the session key, never as the persistent
/// storage key. Persistence uses the hardware tuple instead.
@available(macOS 26.0, *)
struct DisplayIdentity: Hashable, Sendable {
    /// Session-scoped. Unique per attached display; changes on replug/GPU switch.
    let sessionKey: UInt32
    /// Hardware tuple, stable across reboots when the hardware is unchanged.
    /// Nil when the display reports no serial number.
    let hardwareKey: String?
    /// Physical pixel size = frame.size * backingScaleFactor.
    /// All scaling / cropping / fill decisions MUST use this, never frame.size.
    let physicalPixels: CGSize
    let backingScale: CGFloat
}

@available(macOS 26.0, *)
enum DisplayIdentityResolver {

    static func resolve(_ screen: NSScreen) -> DisplayIdentity? {
        // NSScreen.cgDirectDisplayID is Optional (NS_REFINED_FOR_SWIFT) and is
        // kCGNullDirectDisplay when there is no display.
        guard let displayID = screen.cgDirectDisplayID,
              displayID != kCGNullDirectDisplay
        else { return nil }

        let scale = screen.backingScaleFactor
        let physical = CGSize(width: screen.frame.width * scale,
                              height: screen.frame.height * scale)

        let vendor = CGDisplayVendorNumber(displayID)
        let model = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)
        let hardwareKey: String? = serial != 0
            ? "v\(vendor)-m\(model)-s\(serial)"
            : nil

        return DisplayIdentity(sessionKey: UInt32(displayID),
                               hardwareKey: hardwareKey,
                               physicalPixels: physical,
                               backingScale: scale)
    }

    /// Keyed by sessionKey — stable for the running session.
    static func all() -> [UInt32: DisplayIdentity] {
        var out: [UInt32: DisplayIdentity] = [:]
        for screen in NSScreen.screens {
            if let id = resolve(screen) { out[id.sessionKey] = id }
        }
        return out
    }
}

/// Correctness of the `deviceDescription` accessor is NOT verified here:
/// `s.deviceDescription` is `[NSDeviceDescriptionKey: Any]`, and none of
/// `.screenNumber` / `.vendorNumber` / `.modelNumber` / `.screenNumberValue`
/// resolve on that key type. Use the CGDisplay* family above instead.
/// See ADR-007 Trap 7.

// ===== 7. GIF -> MP4 conversion without FFmpeg (ADR-008 constraint) =====

/// GIF cannot be *played* as a wallpaper (ADR-003 / §5.0.4), but GIF -> MP4 is a
/// lightweight transcode achievable with native frameworks only — so it does NOT
/// conflict with the "no FFmpeg" decision.
///
/// WEBM/MKV get no such offer: macOS has no native decoder for them, so MP4
/// conversion would require a full re-encode (slow, lossy). The UI must therefore
/// offer "convert to MP4" for GIF but only "use another file" for WEBM/MKV.
@available(macOS 26.0, *)
enum GIFTranscoder {

    /// Enumerate GIF frames via ImageIO.
    static func frameCount(of gifURL: URL) -> Int {
        guard let src = CGImageSourceCreateWithURL(gifURL as CFURL, nil) else { return 0 }
        return CGImageSourceGetCount(src)
    }

    /// Encode frames to H.264/HEVC MP4 via AVAssetWriter.
    /// Frame extraction uses ImageIO; encoding uses VideoToolbox-backed AVAssetWriter.
    static func writer(forVideoURL out: URL,
                       pixelWidth: Int,
                       pixelHeight: Int) throws -> (AVAssetWriter, AVAssetWriterInputPixelBufferAdaptor) {
        let writer = try AVAssetWriter(outputURL: out, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: pixelWidth,
                AVVideoHeightKey: pixelHeight
            ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: pixelWidth,
                kCVPixelBufferHeightKey as String: pixelHeight
            ])
        guard writer.canAdd(input) else { throw CocoaError(.featureUnsupported) }
        writer.add(input)
        return (writer, adaptor)
    }
}
