import AVFoundation

/// Reads the audio of any file AVFoundation can open (voice memos, MP3,
/// WAV, M4A, MOV and MP4 video) as 16 kHz mono Float32 samples.
enum MediaReader {
    enum ReadError: LocalizedError {
        case noAudio
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .noAudio: "This file has no audio."
            case .unreadable(let reason): "Couldn't read this file: \(reason)"
            }
        }
    }

    static func samples(from url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw ReadError.noAudio }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        reader.add(output)
        guard reader.startReading() else {
            throw ReadError.unreadable(reader.error?.localizedDescription ?? "unknown error")
        }
        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            let length = CMBlockBufferGetDataLength(block)
            var chunk = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            chunk.withUnsafeMutableBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
            }
            samples.append(contentsOf: chunk)
        }
        if reader.status == .failed {
            throw ReadError.unreadable(reader.error?.localizedDescription ?? "unknown error")
        }
        return samples
    }
}
