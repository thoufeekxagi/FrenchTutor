import XCTest

final class PermissionSettingsUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testAcceptPendingLocalNetworkPermissionPrompt() throws {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let localNetworkAlert = springboard.alerts.firstMatch
    if localNetworkAlert.waitForExistence(timeout: 3) {
      let allow = localNetworkAlert.buttons["Allow"].firstMatch
      XCTAssertTrue(allow.exists, springboard.debugDescription)
      allow.tap()
      NSLog("PARLESPRINT_LOCAL_NETWORK_PERMISSION_ENABLED_FROM_PROMPT")
      return
    }

    // Xcode can foreground the release test host while the first-use prompt is
    // pending. In that case, enable the same permission from Settings.
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    settings.launch()
    let searchField = settings.searchFields.firstMatch
    XCTAssertTrue(searchField.waitForExistence(timeout: 15), settings.debugDescription)
    searchField.tap()
    searchField.typeText("Local Network")

    let localNetworkRow = settings.cells.containing(
      .staticText,
      identifier: "Local Network"
    ).firstMatch
    XCTAssertTrue(localNetworkRow.waitForExistence(timeout: 15), settings.debugDescription)
    localNetworkRow.tap()

    let appSwitch = settings.switches.matching(
      NSPredicate(format: "label CONTAINS[c] %@", "ParleSprint")
    ).firstMatch
    XCTAssertTrue(appSwitch.waitForExistence(timeout: 15), settings.debugDescription)
    if (appSwitch.value as? String) != "1" {
      appSwitch.tap()
    }
    XCTAssertEqual(appSwitch.value as? String, "1", settings.debugDescription)
    NSLog("PARLESPRINT_LOCAL_NETWORK_PERMISSION_ENABLED_FROM_SETTINGS")
  }

  func testMicrophonePermissionEnabledInSettings() throws {
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    settings.launch()

    let searchField = settings.searchFields.firstMatch
    XCTAssertTrue(searchField.waitForExistence(timeout: 15), settings.debugDescription)
    searchField.tap()
    searchField.typeText("ParleSprint")

    let appRow = settings.cells.containing(.staticText, identifier: "ParleSprint").firstMatch
    XCTAssertTrue(appRow.waitForExistence(timeout: 15), settings.debugDescription)
    appRow.tap()

    let appSettingsTitle = settings.navigationBars["ParleSprint"]
    XCTAssertTrue(appSettingsTitle.waitForExistence(timeout: 10), settings.debugDescription)

    let settingsSwitches = settings.switches.allElementsBoundByIndex
    for permissionSwitch in settingsSwitches {
      NSLog(
        "PARLESPRINT_PERMISSION_SWITCH label=%@ value=%@",
        permissionSwitch.label,
        String(describing: permissionSwitch.value)
      )
    }

    let microphoneSwitch = settings.switches.matching(
      NSPredicate(format: "label CONTAINS[c] %@", "Microphone")
    ).firstMatch
    XCTAssertTrue(microphoneSwitch.exists, settings.debugDescription)

    if (microphoneSwitch.value as? String) != "1" {
      microphoneSwitch.tap()
    }

    XCTAssertEqual(microphoneSwitch.value as? String, "1")
    NSLog("PARLESPRINT_MIC_PERMISSION_ENABLED")
  }

  func testLiveTutorReceivesAndRepliesToLearnerAudio() throws {
    let app = XCUIApplication(bundleIdentifier: "com.thoufeekx.frenchtutor")
    app.launch()

    func acceptPrivacyDisclosureIfNeeded() {
      let agree = app.buttons["Agree and continue"].firstMatch
      if agree.waitForExistence(timeout: 3) {
        agree.tap()
        Thread.sleep(forTimeInterval: 0.65)
      }
    }

    func skipOnboardingPracticeIfNeeded() {
      let skip = app.buttons["Skip practice"].firstMatch
      if skip.waitForExistence(timeout: 3) {
        skip.tap()
        Thread.sleep(forTimeInterval: 0.65)
      }
    }

    acceptPrivacyDisclosureIfNeeded()
    skipOnboardingPracticeIfNeeded()

    let marieTab = app.buttons["Marie"].firstMatch
    if !marieTab.waitForExistence(timeout: 3) {
      // Fresh Release installs begin in onboarding. Complete its optional
      // choices without entering the separate three-minute trial so this test
      // reaches the same live tutor screen a learner can open from the shell.
      for _ in 0..<8 {
        let continueButton = app.buttons["Continue"].firstMatch
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10), app.debugDescription)
        continueButton.tap()
        Thread.sleep(forTimeInterval: 0.65)
      }

      let startLearning = app.buttons["Start learning"].firstMatch
      XCTAssertTrue(startLearning.waitForExistence(timeout: 10), app.debugDescription)
      startLearning.tap()

      acceptPrivacyDisclosureIfNeeded()

      let skipPractice = app.buttons["Skip practice"].firstMatch
      XCTAssertTrue(skipPractice.waitForExistence(timeout: 15), app.debugDescription)
      skipPractice.tap()
    }
    XCTAssertTrue(marieTab.waitForExistence(timeout: 30), app.debugDescription)
    marieTab.tap()

    let practise = app.buttons["Practise French with Marie"].firstMatch
    XCTAssertTrue(practise.waitForExistence(timeout: 10), app.debugDescription)
    practise.tap()

    let start = app.buttons["Start"].firstMatch
    XCTAssertTrue(start.waitForExistence(timeout: 10), app.debugDescription)
    start.tap()

    // On a clean install the in-app voice disclosure can appear once.
    let disclosure = app.staticTexts["Enable your microphone"]
    if disclosure.waitForExistence(timeout: 2) {
      app.buttons["Continue"].tap()
    }

    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let allowMicrophone = springboard.alerts.buttons["Allow"].firstMatch
    if allowMicrophone.waitForExistence(timeout: 2) {
      allowMicrophone.tap()
    }

    let tutorSpeaking = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", "Marie is speaking")
    ).firstMatch
    XCTAssertTrue(
      tutorSpeaking.waitForExistence(timeout: 45),
      "Marie never played her opening turn.\n\(app.debugDescription)"
    )

    let ignoredLabels: Set<String> = [
      "Live tutor",
      "Lesson · French vocabulary",
      "Connecting",
      "Reconnecting",
      "Listening",
      "Microphone off",
      "Ended",
      "Mute",
      "End",
    ]
    func transcriptLabels() -> Set<String> {
      Set(
        app.staticTexts.allElementsBoundByIndex.map(\.label).filter {
          !$0.isEmpty && !ignoredLabels.contains($0)
        }
      )
    }

    let firstTutorTurn = Date().addingTimeInterval(30)
    var firstTranscript = transcriptLabels().first
    while firstTranscript == nil && Date() < firstTutorTurn {
      Thread.sleep(forTimeInterval: 0.5)
      firstTranscript = transcriptLabels().first
    }
    XCTAssertNotNil(firstTranscript, "No spoken tutor transcript appeared.")

    let listening = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", "Listening")
    ).firstMatch
    XCTAssertTrue(
      listening.waitForExistence(timeout: 30),
      "The tutor did not return to listening after her opening turn.\n\(app.debugDescription)"
    )

    NSLog("PARLESPRINT_LIVE_TUTOR_READY_FOR_LEARNER_AUDIO")
    let baseline = transcriptLabels()
    let learnerDeadline = Date().addingTimeInterval(45)
    var learnerTranscript: String?
    while learnerTranscript == nil && Date() < learnerDeadline {
      Thread.sleep(forTimeInterval: 0.5)
      learnerTranscript = transcriptLabels().first { !baseline.contains($0) }
    }
    XCTAssertNotNil(
      learnerTranscript,
      "Mac-speaker French audio did not appear in the live transcript.\n\(app.debugDescription)"
    )

    NSLog("PARLESPRINT_LIVE_TUTOR_LEARNER_TRANSCRIPT_RECEIVED")
    XCTAssertTrue(
      tutorSpeaking.waitForExistence(timeout: 35),
      "Marie did not reply after the learner's spoken turn.\n\(app.debugDescription)"
    )
  }
}
