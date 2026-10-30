import XCTest

@testable import Mangla

final class CommandLineOptionsTests: XCTestCase {
    func testAbsentProjectOption() {
        XCTAssertEqual(ProjectArgument.parse(["Mangla"]), .absent)
    }

    func testProjectOptionWithPath() {
        XCTAssertEqual(
            ProjectArgument.parse(["Mangla", "--project", "/tmp/Library"]),
            .path("/tmp/Library")
        )
    }

    func testProjectOptionWithoutValue() {
        XCTAssertEqual(ProjectArgument.parse(["Mangla", "--project"]), .missingValue)
        XCTAssertEqual(
            ProjectArgument.parse(["Mangla", "--project", "--open-reader"]),
            .missingValue
        )
    }
}
