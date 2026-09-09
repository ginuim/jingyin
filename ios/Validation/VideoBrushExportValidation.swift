import SwiftUI
import AVFoundation
import CoreImage

@main
struct BrushValidationApp: App {
    var body: some Scene {
        WindowGroup { Text("Brush validation").task { await run() } }
    }
    @MainActor func run() async {
        let logURL = URL(fileURLWithPath: "/tmp/jingyin-brush-results.txt")
        try? "".write(to: logURL, atomically: true, encoding: .utf8)
        func log(_ text: String) {
            let old = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            try? (old + text + "\n").write(to: logURL, atomically: true, encoding: .utf8)
        }
        let path = NormalizedMaskPath(points: [.init(x: 0.15, y: 0.2), .init(x: 0.45, y: 0.4), .init(x: 0.2, y: 0.65)], strokeWidth: 0.12)!
        let track = MaskTrack(shape: .rectangle, manualPath: path,
            keyframes: [.init(timeSeconds: 0, rect: path.boundingRect)])
        // An asymmetric stroke on portrait and landscape extents must use the
        // exact same raster for photo and video, with empty bounding-box corners.
        for size in [CGSize(width: 360, height: 640), CGSize(width: 640, height: 360)] {
            let extent = CGRect(origin: .zero, size: size)
            let a = PhotoProcessor.manualPathMask(path, extent: extent)!
            let b = PhotoProcessor.manualPathMask(track.path(at: 60)!, extent: extent)!
            let context = CIContext()
            func pixels(_ image: CIImage) -> [UInt8] {
                var bytes = [UInt8](repeating: 0, count: Int(size.width * size.height) * 4)
                context.render(image, toBitmap: &bytes, rowBytes: Int(size.width) * 4,
                    bounds: extent, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
                return bytes
            }
            let ap = pixels(a), bp = pixels(b)
            precondition(ap == bp)
            let maskImage = context.createCGImage(a, from: extent)!
            let provider = maskImage.dataProvider!.data!
            precondition(CFDataGetLength(provider) > 0)
            log("PASS photo/video brush raster parity \(size)")
        }
        var options = ProcessingOptions()
        options.scope = .subjects
        options.subjects = []
        options.style = .pixel
        options.strength = 32
        options.quality = .fast
        options.exportResolution = .p480
        options.exportFrameRate = 24
        options.maskTracks = [track]
        let cases: [(String, AudioMode, ExportAccess)] = [
            ("portrait30", .original, .free),
            ("landscape60", .mute, .lifetime),
            ("landscape180", .original, .lifetime),
            ("portrait30", .voice, .lifetime)
        ]
        let processor = VideoProcessor()
        for (name, audio, access) in cases {
            options.audio = audio
            await processor.process(sourceURL: URL(fileURLWithPath: "/tmp/jingyin-brush-fixtures/\(name).mp4"), options: options, access: access)
            guard let output = processor.outputURL else { log("FAIL \(name): \(processor.stage)"); continue }
            let destination = URL(fileURLWithPath: "/tmp/jingyin-brush-fixtures/\(name)-output.mp4")
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.copyItem(at: output, to: destination)
            let asset = AVURLAsset(url: destination)
            let duration = (try? await asset.load(.duration).seconds) ?? 0
            log("PASS export \(name) audio=\(audio) duration=\(duration)")
        }
        options.audio = .voice
        options.maskTracks = []
        await processor.process(sourceURL: URL(fileURLWithPath: "/tmp/jingyin-brush-fixtures/landscape180.mp4"), options: options, access: .lifetime)
        log(processor.outputURL == nil ? "BASELINE 180s voice without brush also fails" : "PASS baseline 180s voice")
        options.maskTracks = [track]
        options.audio = .original
        let pending = Task { await processor.process(sourceURL: URL(fileURLWithPath: "/tmp/jingyin-brush-fixtures/landscape180.mp4"), options: options, access: .lifetime) }
        try? await Task.sleep(for: .milliseconds(250))
        processor.cancel()
        await pending.value
        log(processor.outputURL == nil ? "PASS cancellation" : "FAIL cancellation")
        await processor.process(sourceURL: URL(fileURLWithPath: "/tmp/jingyin-brush-fixtures/missing.mp4"), options: options, access: .free)
        log(processor.outputURL == nil ? "PASS invalid input fails" : "FAIL invalid input")
        await processor.process(sourceURL: URL(fileURLWithPath: "/tmp/jingyin-brush-fixtures/portrait30.mp4"), options: options, access: .free)
        log(processor.outputURL != nil ? "PASS retry after failure" : "FAIL retry")
        log("DONE")
    }
}
