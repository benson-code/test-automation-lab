import XCTest
@testable import Wallet

/// Where the app finds the API (ApiConfig.swift). Same cases as the Android ApiConfigTest.
final class ApiConfigTests: XCTestCase {
    func testDebugBuildTakesTheLaunchArgument() {
        XCTAssertEqual(ApiConfig.resolve("http://127.0.0.1:8471/", debugBuild: true).baseUrl, "http://127.0.0.1:8471")
    }

    func testReleaseBuildIgnoresTheLaunchArgument() {
        XCTAssertEqual(ApiConfig.resolve("http://127.0.0.1:8471", debugBuild: false).baseUrl, ApiConfig.defaultBaseUrl)
    }

    func testNoArgumentMeansTheDefault() {
        XCTAssertEqual(ApiConfig.resolve(nil, debugBuild: true).baseUrl, ApiConfig.defaultBaseUrl)
        XCTAssertEqual(ApiConfig.fromLaunch(["Wallet"]).baseUrl, ApiConfig.defaultBaseUrl)
        XCTAssertEqual(ApiConfig.fromLaunch(["Wallet", "-apiBaseUrl"]).baseUrl, ApiConfig.defaultBaseUrl, "no value after it")
    }

    func testTheArgumentIsReadFromTheLaunch() {
        XCTAssertEqual(ApiConfig.fromLaunch(["Wallet", "-apiBaseUrl", "http://127.0.0.1:9999"]).baseUrl, "http://127.0.0.1:9999")
    }

    func testSomethingThatIsNotAUrlIsIgnored() {
        for bad in ["", "  ", "127.0.0.1:8400", "ftp://127.0.0.1", "http://", "http://host/path", "javascript:alert(1)"] {
            XCTAssertEqual(ApiConfig.resolve(bad, debugBuild: true).baseUrl, ApiConfig.defaultBaseUrl, bad)
        }
    }
}
