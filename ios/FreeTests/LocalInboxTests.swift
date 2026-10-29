import XCTest
@testable import DropMP4Free

final class LocalInboxTests: XCTestCase {
    func testStandaloneStorageRequiresNoAppGroup() throws {
        XCTAssertTrue(AppFeatures.localImportOnly)
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "SharedGroup"))
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
        XCTAssertEqual(try Inbox.directory().standardizedFileURL,
                       documents.appendingPathComponent("Inbox", isDirectory: true).standardizedFileURL)
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
