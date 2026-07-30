import XCTest
@testable import SniffBrowser

final class BrowserViewModelTests: XCTestCase {
  private var defaults: UserDefaults?
  private var suiteName = ""

  override func setUp() {
    super.setUp()
    suiteName = "BrowserViewModelTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    defaults?.removePersistentDomain(forName: suiteName)
    defaults = nil
    super.tearDown()
  }

  @MainActor
  func testInitialStateRepresentsNewTab() throws {
    let viewModel = try makeViewModel()

    XCTAssertEqual(viewModel.state.title, "新标签页")
    XCTAssertNil(viewModel.state.url)
    XCTAssertFalse(viewModel.state.isLoading)
    XCTAssertEqual(viewModel.state.progress, 0)
    XCTAssertFalse(viewModel.state.canGoBack)
    XCTAssertFalse(viewModel.state.canGoForward)
  }

  @MainActor
  func testUpdatePublishesLoadingAndNavigationState() throws {
    let viewModel = try makeViewModel()
    let expectedURL = try XCTUnwrap(URL(string: "https://example.com"))
    var publishedState: BrowserViewState?
    var publishCount = 0
    viewModel.onStateChange = {
      publishedState = $0
      publishCount += 1
    }

    viewModel.update(
      title: "Example",
      url: expectedURL,
      isLoading: true,
      progress: 0.42,
      canGoBack: true,
      canGoForward: false
    )

    XCTAssertEqual(viewModel.state.title, "Example")
    XCTAssertEqual(viewModel.state.url, expectedURL)
    XCTAssertTrue(viewModel.state.isLoading)
    XCTAssertEqual(viewModel.state.progress, 0.42, accuracy: 0.001)
    XCTAssertTrue(viewModel.state.canGoBack)
    XCTAssertFalse(viewModel.state.canGoForward)
    XCTAssertEqual(publishedState, viewModel.state)
    XCTAssertEqual(publishCount, 1)
    XCTAssertTrue(viewModel.state.isSecure)
    XCTAssertFalse(viewModel.state.isInsecure)
  }

  @MainActor
  func testForwardAndBackStateCanChangeIndependently() throws {
    let viewModel = try makeViewModel()

    viewModel.update(
      title: "Navigation",
      url: URL(string: "http://example.com"),
      isLoading: false,
      progress: 1,
      canGoBack: false,
      canGoForward: true
    )

    XCTAssertFalse(viewModel.state.canGoBack)
    XCTAssertTrue(viewModel.state.canGoForward)
    XCTAssertFalse(viewModel.state.isSecure)
    XCTAssertTrue(viewModel.state.isInsecure)
  }

  @MainActor
  func testProgressIsClampedToValidRange() throws {
    let viewModel = try makeViewModel()

    viewModel.update(
      title: nil,
      url: nil,
      isLoading: true,
      progress: 3,
      canGoBack: false,
      canGoForward: false
    )
    XCTAssertEqual(viewModel.state.progress, 1)

    viewModel.update(
      title: nil,
      url: nil,
      isLoading: false,
      progress: -1,
      canGoBack: false,
      canGoForward: false
    )
    XCTAssertEqual(viewModel.state.progress, 0)
  }

  @MainActor
  func testResetReturnsToNewTabState() throws {
    let viewModel = try makeViewModel()
    viewModel.update(
      title: "Loaded",
      url: URL(string: "https://example.com"),
      isLoading: true,
      progress: 0.5,
      canGoBack: true,
      canGoForward: true
    )

    viewModel.resetToNewTab()

    XCTAssertEqual(viewModel.state, BrowserViewState())
  }

  @MainActor
  func testResolveUsesConfiguredSearchEngine() throws {
    let defaults = try XCTUnwrap(defaults)
    let preferences = BrowserPreferences(defaults: defaults)
    preferences.searchEngine = .baidu
    let viewModel = BrowserViewModel(preferences: preferences)

    let components = viewModel.resolve("中文关键词")
      .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }

    XCTAssertEqual(components?.host, "www.baidu.com")
    XCTAssertEqual(
      components?.queryItems?.first(where: { $0.name == "wd" })?.value,
      "中文关键词"
    )
  }

  @MainActor
  private func makeViewModel() throws -> BrowserViewModel {
    let defaults = try XCTUnwrap(defaults)
    return BrowserViewModel(
      preferences: BrowserPreferences(defaults: defaults)
    )
  }
}
