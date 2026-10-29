import XCTest
import AVFoundation
#if DROPMP4_FREE_TEST
@testable import DropMP4Free
#else
@testable import DropMP4
#endif

final class RemuxTests: XCTestCase {
    func testKnownSHA256() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("abc".utf8).write(to: file)
        XCTAssertEqual(try FileDigest.sha256(file), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testMP4IsSentAsOriginal() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("original.mp4")
        let result = try await Remux.prepare(file)
        XCTAssertEqual(result.url, file)
        XCTAssertFalse(result.remuxed)
    }

    func testInvalidMOVKeepsSource() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("invalid movie".utf8).write(to: file)
        do { _ = try await Remux.prepare(file); XCTFail("Invalid MOV must not be converted") }
        catch { XCTAssertEqual(try Data(contentsOf: file), Data("invalid movie".utf8)) }
    }

    func testH264PassthroughPreservesSource() async throws {
        executionTimeAllowance = 60
        print("H264 test: generating fixture")
        let file = try await movie()
        print("H264 test: fixture written; preparing passthrough")
        defer { try? FileManager.default.removeItem(at: file) }
        let digest = try FileDigest.sha256(file)
        let result = try await Remux.prepare(file)
        print("H264 test: passthrough and payload verification completed")
        defer { try? FileManager.default.removeItem(at: result.url) }
        XCTAssertTrue(result.remuxed)
        XCTAssertEqual(result.url.pathExtension, "mp4")
        XCTAssertEqual(try FileDigest.sha256(file), digest)
        // Remux.prepare itself asserts byte-identical compressed track payloads.
    }

    private func movie() async throws -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        let writer = try AVAssetWriter(outputURL: file, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                                          kCVPixelBufferWidthKey as String: 64,
                                          kCVPixelBufferHeightKey as String: 64])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error! }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<8 {
            var waits = 0
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000)
                waits += 1
                if waits > 500 { throw DropError.message("Fixture encoder timed out") }
            }
            var buffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB,
                                             nil, &buffer)
            guard status == kCVReturnSuccess, let buffer else { throw DropError.message("Fixture allocation failed") }
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), Int32(frame * 20), CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 8)) else {
                throw writer.error ?? DropError.message("Fixture append failed")
            }
        }
        input.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else { throw writer.error ?? DropError.message("Fixture writer failed") }
        return file
    }
}
