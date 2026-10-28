import Foundation
import AVFoundation
import CryptoKit
import AudioToolbox

struct PreparedVideo {
    let url: URL
    let message: String
    let remuxed: Bool
}

enum Remux {
    private struct StreamMarker: Equatable {
        let timing: String
        let propagated: NSDictionary
        let local: NSDictionary
    }

    private struct TrackSignature: Equatable {
        let media: String
        let codec: FourCharCode
        let hash: String
        let bytes: Int
        let samples: Int
        let emptyIntervals: [StreamMarker]
    }

    // Nil outputSettings asks AVAssetReader for compressed samples, not decoded pixels.
    // Strict equality can reject a valid remux; fallback always keeps the source MOV.
    private static func signatures(_ asset: AVAsset) async throws -> [TrackSignature] {
        let tracks = try await asset.load(.tracks)
        var result: [TrackSignature] = []
        for track in tracks {
            let type = track.mediaType
            guard type == .video || type == .audio else {
                throw DropError.message("這部 MOV 包含額外軌道，這一版無法確認 MP4 可完整保留。")
            }
            let formats = try await track.load(.formatDescriptions)
            guard formats.count == 1 else {
                throw DropError.message("這部影片的編碼格式會變動，請傳送原始 MOV。")
            }
            let codec = CMFormatDescriptionGetMediaSubType(formats[0])
            if type == .video && codec != kCMVideoCodecType_H264 && codec != kCMVideoCodecType_HEVC {
                throw DropError.message("目前僅嘗試 H.264 / HEVC 的 MP4 免重編碼封裝。")
            }
            if type == .audio && codec != kAudioFormatMPEG4AAC {
                throw DropError.message("這部 MOV 的音訊不是 AAC，這一版保守保留原檔。")
            }
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { throw DropError.message("無法驗證影片軌道。") }
            reader.add(output)
            guard reader.startReading() else { throw reader.error ?? DropError.message("無法讀取影片。") }
            var hash = SHA256()
            var total = 0
            var samples = 0
            var emptyIntervals: [StreamMarker] = []
            do {
                while let sample = output.copyNextSampleBuffer() {
                    try Task.checkCancellation()
                    // AVAssetReader can emit attachment-only stream markers, which
                    // are not missing compressed frames. Preserve and compare their
                    // timing instead of treating them as payload or ignoring them.
                    if CMSampleBufferGetNumSamples(sample) == 0,
                       CMSampleBufferGetTotalSampleSize(sample) == 0,
                       CMSampleBufferGetImageBuffer(sample) == nil {
                        // Stream markers are not limited to EmptyMedia / PermanentEmptyMedia.
                        // A zero-sample buffer may carry another timing/control event.
                        let timing = [CMSampleBufferGetOutputPresentationTimeStamp(sample),
                                      CMSampleBufferGetDecodeTimeStamp(sample),
                                      CMSampleBufferGetOutputDuration(sample)].map { time in
                            "\(time.flags.rawValue):\(time.epoch):" + String(format: "%.9f", time.seconds)
                        }.joined(separator: "|")
                        let propagated = CMCopyDictionaryOfAttachments(allocator: kCFAllocatorDefault,
                            target: sample, attachmentMode: kCMAttachmentMode_ShouldPropagate) as NSDictionary? ?? NSDictionary()
                        let local = CMCopyDictionaryOfAttachments(allocator: kCFAllocatorDefault,
                            target: sample, attachmentMode: kCMAttachmentMode_ShouldNotPropagate) as NSDictionary? ?? NSDictionary()
                        emptyIntervals.append(StreamMarker(timing: timing, propagated: propagated, local: local))
                        guard emptyIntervals.count <= 4096 else {
                            throw DropError.message("影音空白區段標記過多，無法確認封裝相容性，請保留原始 MOV。")
                        }
                        continue
                    }
                    guard let buffer = CMSampleBufferGetDataBuffer(sample) else {
                        throw DropError.message("無法驗證壓縮資料（samples=\(CMSampleBufferGetNumSamples(sample)), bytes=\(CMSampleBufferGetTotalSampleSize(sample))），請保留原始 MOV。")
                    }
                    let length = CMBlockBufferGetDataLength(buffer)
                    guard length > 0 else { throw DropError.message("壓縮影音 sample 沒有資料，請保留原始 MOV。") }
                    var data = Data(count: length)
                    let status = data.withUnsafeMutableBytes { bytes in
                        CMBlockBufferCopyDataBytes(buffer, atOffset: 0, dataLength: length,
                                                   destination: bytes.baseAddress!)
                    }
                    guard status == kCMBlockBufferNoErr else { throw DropError.message("軌道校驗讀取失敗。") }
                    hash.update(data: data)
                    total += length
                    samples += CMSampleBufferGetNumSamples(sample)
                }
            } catch { reader.cancelReading(); throw error }
            guard reader.status == .completed else { throw reader.error ?? DropError.message("影片讀取未完成。") }
            guard total > 0, samples > 0 else { throw DropError.message("影音軌道沒有可驗證的壓縮資料。") }
            #if DEBUG
            print("DropMP4 track verified: codec=\(codec), samples=\(samples), bytes=\(total), emptyIntervals=\(emptyIntervals.count)")
            #endif
            result.append(TrackSignature(media: type.rawValue, codec: codec,
                hash: hash.finalize().map { String(format: "%02x", $0) }.joined(), bytes: total,
                samples: samples, emptyIntervals: emptyIntervals))
        }
        guard result.contains(where: { $0.media == AVMediaType.video.rawValue }) else {
            throw DropError.message("找不到影片軌道。")
        }
        return result
    }

    static func prepare(_ source: URL) async throws -> PreparedVideo {
        if source.pathExtension.lowercased() == "mp4" {
            return PreparedVideo(url: source, message: "原始 MP4，直接傳送。", remuxed: false)
        }
        let asset = AVURLAsset(url: source)
        let before = try await signatures(asset)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough),
              export.supportedFileTypes.contains(.mp4) else {
            throw DropError.message("AVFoundation 不支援這部 MOV 的 MP4 免重編碼封裝。")
        }
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("DropMP4", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let target = cache.appendingPathComponent(UUID().uuidString + ".mp4")
        export.outputURL = target
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true
        do {
            try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    export.exportAsynchronously {
                        if export.status == .completed { continuation.resume() }
                        else { continuation.resume(throwing: export.error ?? DropError.message("免重編碼封裝未完成。")) }
                    }
                }
            }, onCancel: { export.cancelExport() })
            try Task.checkCancellation()
            let output = AVURLAsset(url: target)
            let after = try await signatures(output)
            let durationBefore = try await asset.load(.duration).seconds
            let durationAfter = try await output.load(.duration).seconds
            guard before == after, abs(durationBefore - durationAfter) < 0.05 else {
                throw DropError.message("封裝後的壓縮影音資料或長度不一致，請傳送原始 MOV。")
            }
            let originalTracks = try await asset.loadTracks(withMediaType: .video)
            let newTracks = try await output.loadTracks(withMediaType: .video)
            for (original, converted) in zip(originalTracks, newTracks) {
                let a = try await original.load(.preferredTransform)
                let b = try await converted.load(.preferredTransform)
                guard a == b else { throw DropError.message("影片旋轉資訊不一致，請保留原始 MOV。") }
            }
            return PreparedVideo(url: target,
                message: "MP4 已免重編碼封裝，壓縮影音資料校驗一致。HDR、色彩與其他中繼資料仍須實機確認；原始 MOV 已保留。",
                remuxed: true)
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw error
        }
    }

    static func digest(_ file: URL) async throws -> String { try FileDigest.sha256(file) }
}
