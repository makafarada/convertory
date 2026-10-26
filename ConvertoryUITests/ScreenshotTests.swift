import XCTest

/// Walks the app with sample files and saves App Store screenshots as attachments.
final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func launch(tool: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemo", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if let tool { app.launchArguments += ["-demoTool", tool] }
        app.launch()
        return app
    }

    private func shot(_ name: String) {
        Thread.sleep(forTimeInterval: 1.5)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func runTool(_ tool: String, button: String, name: String) {
        let app = launch(tool: tool)
        let action = app.buttons[button]
        _ = action.waitForExistence(timeout: 15)
        shot("\(name)-1-files")
        if action.exists {
            action.tap()
            let saved = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Saved in Files'")).firstMatch
            _ = saved.waitForExistence(timeout: 40)
            shot("\(name)-2-result")
        }
        app.terminate()
    }

    func test01Home() {
        let app = launch()
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 15)
        shot("01-home")
        app.terminate()
    }

    func test02Merge() { runTool("merge", button: "Merge files", name: "02-merge") }

    func test03Compress() { runTool("compress", button: "Compress", name: "03-compress") }

    func test04Word() { runTool("pdfToWord", button: "Convert to Word", name: "04-word") }

    func test05Text() { runTool("extractText", button: "Extract text", name: "05-text") }

    func test06Organize() {
        let app = launch(tool: "organize")
        _ = app.buttons["Save pages"].waitForExistence(timeout: 15)
        shot("06-organize")
        app.terminate()
    }

    func test07Watermark() {
        let app = launch(tool: "watermark")
        _ = app.buttons["Add watermark"].waitForExistence(timeout: 15)
        shot("07-watermark")
        app.terminate()
    }

    func test08Library() {
        let app = launch()
        let tab = app.tabBars.buttons["Library"]
        _ = tab.waitForExistence(timeout: 15)
        tab.tap()
        shot("08-library")
        app.terminate()
    }
}
