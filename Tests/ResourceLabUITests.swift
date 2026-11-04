import XCTest

final class ResourceLabUITests: XCTestCase {
    func testMeshLoadsAndCanBeRotated() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let model = app.otherElements["mesh-ready"]
        XCTAssertTrue(model.waitForExistence(timeout: 15), "Metal and mesh resources must load")
        XCTAssertFalse(app.staticTexts["mesh-error"].exists)
        model.swipeLeft()
        XCTAssertTrue(model.exists, "The mesh view should remain after a pan")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "ResourceLab-model"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.otherElements["mesh-ready"].waitForExistence(timeout: 15))
    }
}
