import XCTest
@testable import DropMP4Free

final class LocalInboxTests: XCTestCase {
    func testStandaloneStorageRequiresNoAppGroup() throws {
        XCTAssertTrue(AppFeatures.localImportOnly)
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "SharedGroup"))
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
        XCTAssertEqual(try Inbox.directory().standardizedFileURL,
                       documents.appendingPathComponent("ImportedVideos", isDirectory: true).standardizedFileURL)
        XCTAssertNotEqual(try Inbox.directory().lastPathComponent, "Inbox",
                          "iOS reserves Documents/Inbox; simulator writes alone cannot validate this restriction")
    }

    func testStorageCanWriteAndRefresh() throws {
        let directory = try Inbox.directory()
        let probe = directory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: probe) }
        try Data([1, 2, 3]).write(to: probe)
        XCTAssertTrue(try Inbox.files().contains(probe))
        XCTAssertEqual(try Inbox.directory(), directory)
    }

    func testImportPreservesSourceAndBytes() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        let bytes = Data([0, 1, 2, 3, 255])
        try bytes.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let imported = try Inbox.importFile(source)
        defer { try? FileManager.default.removeItem(at: imported) }
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertEqual(try Data(contentsOf: imported), bytes)
        XCTAssertEqual(imported.deletingLastPathComponent(), try Inbox.directory())
    }
}
