import AVFoundation
import Foundation

enum WAV {
    /// Wraps interleaved 16-bit little-endian PCM in a WAV header.
    static func make(pcm16 pcm: Data, sampleRate: Int, channels: Int) -> Data {
        var data = Data(capacity: 44 + pcm.count)
        func append(_ string: String) { data.append(contentsOf: Array(string.utf8)) }
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        append("RIFF")
        append32(UInt32(36 + pcm.count))
        append("WAVE")
        append("fmt ")
        append32(16)
        append16(1) // PCM
        append16(UInt16(channels))
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * channels * 2))
        append16(UInt16(channels * 2))
        append16(16)
        append("data")
        append32(UInt32(pcm.count))
        data.append(pcm)
        return data
    }
}

enum ClipExporter {
    /// Cuts [start, end] seconds of audio out of any audio or video file into a temporary .m4a.
    static func exportAudio(from url: URL, start: Double, end: Double) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw SoundError.noAudio }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw SoundError.exportFailed
        }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        session.outputURL = output
        session.outputFileType = .m4a
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )
        await session.export()
        guard session.status == .completed else { throw session.error ?? SoundError.exportFailed }
        return output
    }
}
