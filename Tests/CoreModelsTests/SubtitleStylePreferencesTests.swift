import XCTest
@testable import CoreModels

@MainActor
final class SubtitleStylePreferencesTests: XCTestCase {
    func testControlAvoidanceDefaultsOnAndPersistsProfileChoice() throws {
        XCTAssertTrue(try JSONDecoder().decode(SubtitleStyle.self, from: Data("{}".utf8)).avoidsPlayerControls)
        XCTAssertTrue(SubtitleStyle.default.avoidsPlayerControls)
        XCTAssertTrue(SubtitleStyle.profileDefault.avoidsPlayerControls)
        for enabled in [false, true] {
            var style = SubtitleStyle.default
            style.avoidsPlayerControls = enabled
            XCTAssertEqual(try JSONDecoder().decode(SubtitleStyle.self, from: JSONEncoder().encode(style)), style)
        }
        let name = "SubtitleControlAvoidance.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SubtitleStyleStore(defaults: defaults, namespace: "viewer")
        let model = SubtitleStyleModel(store: store)
        model.style.avoidsPlayerControls = false
        let reloaded = SubtitleStyleModel(store: store)
        XCTAssertFalse(reloaded.style.avoidsPlayerControls)
        XCTAssertTrue(SubtitleStyleStore(defaults: defaults).load().base.avoidsPlayerControls)
        XCTAssertTrue(SubtitleStyleStore(defaults: defaults, namespace: "other").load().base.avoidsPlayerControls)
    }

    func testPositionLabelsDescribeTheBottomReferenceWithoutChangingStoredValues() {
        let expected: [(SubtitleStyle.PositionReference, String, String)] = [
            (.screen, "screen", "Bottom of screen"),
            (.picture, "picture", "Bottom of video")
        ]
        XCTAssertEqual(SubtitleStyle.PositionReference.allCases, expected.map { $0.0 })
        for (reference, storedValue, title) in expected {
            var label = reference.displayName
            label.locale = Locale(identifier: "en")
            XCTAssertEqual(String(localized: label), title)
            XCTAssertEqual(reference.rawValue, storedValue)
        }
        XCTAssertEqual(SubtitleStyle.default.positionReference, .screen)
        XCTAssertEqual(SubtitleStyle.profileDefault.positionReference, .screen)
    }

    func testPictureReferenceDecodesLegacyUnknownAndRoundTrips() throws {
        XCTAssertEqual(try JSONDecoder().decode(SubtitleStyle.self, from: Data("{}".utf8)).positionReference, .screen)
        XCTAssertEqual(try JSONDecoder().decode(SubtitleStyle.self, from: Data("{\"positionReference\":\"future\"}".utf8)).positionReference, .screen)
        for reference in SubtitleStyle.PositionReference.allCases {
            var style = SubtitleStyle.default
            style.positionReference = reference
            style.verticalPosition = 0.73
            style.verticalAnchor = .top
            style.horizontalOffset = -0.12
            XCTAssertEqual(try JSONDecoder().decode(SubtitleStyle.self, from: JSONEncoder().encode(style)), style)
        }
    }
    func testSystemStyleChoiceAndCustomStyleTransferOnlyToTheSameProfile() throws {
        let sourceName = "SubtitleProfileSource.\(UUID().uuidString)"
        let targetName = "SubtitleProfileTarget.\(UUID().uuidString)"
        let source = try XCTUnwrap(UserDefaults(suiteName: sourceName))
        let target = try XCTUnwrap(UserDefaults(suiteName: targetName))
        defer {
            source.removePersistentDomain(forName: sourceName)
            target.removePersistentDomain(forName: targetName)
        }
        var otherStyle = SubtitleStyle.default
        otherStyle.fontFamily = .fredoka
        otherStyle.fontScale = 1.6
        let other = SubtitleStylePreferences(base: otherStyle)
        let sourceOther = SubtitleStyleStore(defaults: source, namespace: "profile-b")
        let targetOther = SubtitleStyleStore(defaults: target, namespace: "profile-b")
        sourceOther.save(other)
        targetOther.save(other)
        let defaultBefore = SubtitleStyleStore(defaults: source).load()
        let store = SubtitleStyleStore(defaults: source, namespace: "profile-a")
        let model = SubtitleStyleModel(store: store)
        for followsSystem in [false, true] {
            model.style.followsSystemStyle = followsSystem
            model.style.fontScale = 1.25
            model.style.positionReference = .picture
            model.style.avoidsPlayerControls = !followsSystem
            let settings = ProfileSettingsTransfer.capture(namespace: "profile-a", defaults: source)
            ProfileSettingsTransfer.apply(settings, namespace: "profile-a", defaults: target)
            let received = SubtitleStyleStore(defaults: target, namespace: "profile-a").load()
            XCTAssertEqual(received.base.followsSystemStyle, followsSystem)
            XCTAssertEqual(received.base.fontScale, 1.25)
            XCTAssertEqual(received.base.positionReference, .picture)
            XCTAssertEqual(received.base.avoidsPlayerControls, !followsSystem)
            XCTAssertEqual(sourceOther.load(), other)
            XCTAssertEqual(targetOther.load(), other)
            XCTAssertEqual(SubtitleStyleStore(defaults: source).load(), defaultBefore)
        }
    }

    func testFileEmphasisSettingPreservesOtherCapturedSourcePolicies() {
        var style = SubtitleStyle.default
        style.usesSourceColors = false
        XCTAssertTrue(style.usesSourceEmphasis)
        style.usesSourceEmphasis = false
        XCTAssertFalse(style.usesSourceEmphasis)
        XCTAssertEqual(style.captionSourceOverrides?.foregroundColor, false)
        XCTAssertEqual(style.captionSourceOverrides?.foregroundOpacity, false)
        style.captionSourceOverrides?.windowCornerRadius = false
        let previous = style.captionSourceOverrides
        style.usesSourceEmphasis = true
        XCTAssertEqual(style.captionSourceOverrides?.foregroundColor, previous?.foregroundColor)
        XCTAssertEqual(style.captionSourceOverrides?.foregroundOpacity, previous?.foregroundOpacity)
        XCTAssertEqual(style.captionSourceOverrides?.windowCornerRadius, false)
    }

    func testNewProfilesDefaultToMatchingButOldMissingFieldsRemainCustom() throws {
        let name = "SubtitleStyleDefaultsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        for namespace: String? in [nil, "new-viewer"] {
            let store = SubtitleStyleStore(defaults: defaults, namespace: namespace)
            XCTAssertTrue(store.load().base.followsSystemStyle)
            XCTAssertEqual(store.load().base.positionReference, .screen)
        }
        for json in ["{}", #"{"base":{}}"#, #"{"base":{"fontScale":0.37}}"#] {
            let saved = try JSONDecoder().decode(SubtitleStylePreferences.self, from: Data(json.utf8))
            XCTAssertFalse(saved.base.followsSystemStyle)
        }
        XCTAssertFalse(try JSONDecoder().decode(SubtitleStyle.self, from: Data("{}".utf8)).followsSystemStyle)
        XCTAssertFalse(SubtitleStyle.default.followsSystemStyle, "The old custom baseline is not a new-profile default.")
        XCTAssertTrue(SubtitleStyle.profileDefault.followsSystemStyle, "Explicit Reset and a new profile share this default.")
    }

    func testEverySavedChoiceSurvivesUpgradeAndReset() throws {
        let name = "SubtitleStyleSavedChoiceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        for namespace: String? in [nil, "viewer"] {
            let store = SubtitleStyleStore(defaults: defaults, namespace: namespace)
            for baseFollows in [false, true] {
                var base = SubtitleStyle.default
                base.followsSystemStyle = baseFollows
                base.fontScale = 0.37
                let expected = SubtitleStylePreferences(base: base, overrides: [.anime: base])
                store.save(expected)
                let model = SubtitleStyleModel(store: SubtitleStyleStore(defaults: defaults, namespace: namespace))
                XCTAssertEqual(store.load(), expected)
                XCTAssertEqual(model.style.followsSystemStyle, baseFollows)
                model.style = .profileDefault
                XCTAssertTrue(store.load().base.followsSystemStyle)
                XCTAssertEqual(store.load().overrides[.anime], base)
            }
        }
    }

    func testDefaultAndNamedLegacyNamespacesStillMigrateTheCustomLook() throws {
        let name = "SubtitleStyleLegacyDefaultTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        for namespace: String? in [nil, "legacy-viewer"] {
            for oldFlag in [false, true] {
                let legacy = LegacyCaptionSettings(
                    fontScale: 0.61, textColor: .cyan, backgroundColor: .yellow,
                    edgeStyle: .uniform, followsSystemStyle: oldFlag
                )
                defaults.removeObject(forKey: SettingsKey.scoped(SubtitleStyleStore.storageKey, namespace: namespace))
                defaults.set(try JSONEncoder().encode(legacy),
                             forKey: SettingsKey.scoped(LegacyCaptionSettings.storageKey, namespace: namespace))
                let store = SubtitleStyleStore(defaults: defaults, namespace: namespace)
                XCTAssertEqual(store.load().base, SubtitleStyle(from: legacy))
                XCTAssertFalse(store.load().base.followsSystemStyle)
                store.save(.init(base: .profileDefault))
                XCTAssertTrue(SubtitleStyleStore(defaults: defaults, namespace: namespace).load().base.followsSystemStyle,
                              "Legacy data may seed once, never overwrite a modern saved choice.")
            }
        }
        XCTAssertTrue(SubtitleStyleStore(defaults: defaults, namespace: "untouched-new-profile").load().base.followsSystemStyle)
    }

    func testFrozenAppearanceRoundTripsAllPublicFieldsWithoutNormalizingUniformEdge() throws {
        var style = SubtitleStyle.default
        style.fontDescriptor = .init(
            archive: Data([1, 3, 5, 7]), postScriptName: "ExampleFace",
            displayName: "Example Face · Small Capitals", weight: 0.23
        )
        var policy = SubtitleCaptionSourceOverrides()
        policy.font = false
        policy.relativeSize = false
        policy.foregroundColor = false
        policy.foregroundOpacity = true
        policy.backgroundColor = true
        policy.backgroundOpacity = false
        policy.windowColor = false
        policy.windowOpacity = true
        policy.windowCornerRadius = false
        policy.edge = true
        style.captionSourceOverrides = policy
        style.captionEdgeStyleRawValue = 17
        style.fontScale = 1.137
        style.textColor = .init(red: 0.12, green: 0.34, blue: 0.56, alpha: 0.37)
        style.glyphBackground = .init(red: 0.4, green: 0.2, blue: 0.1, alpha: 0.21)
        style.background = .init(color: .init(red: 0.3, green: 0.5, blue: 0.7, alpha: 0.48), cornerRadius: 3.75)
        style.edge = .init(style: .uniform)
        style.border.isEnabled = false
        let data = try JSONEncoder().encode(SubtitleStylePreferences(base: style))
        let restored = try JSONDecoder().decode(SubtitleStylePreferences.self, from: data)
        XCTAssertEqual(restored.base, style)
        XCTAssertEqual(restored.base.edge.style, .uniform)
        XCTAssertFalse(restored.base.border.isEnabled)
    }

    func testForegroundColorAndOpacitySourcePermissionsAreIndependent() throws {
        let source = SubtitleColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 0.25)
        for allowColor in [false, true] {
            for allowOpacity in [false, true] {
                var style = SubtitleStyle.default
                style.textColor = .init(red: 0.1, green: 0.3, blue: 0.5, alpha: 0.75)
                style.captionSourceOverrides = .init()
                style.captionSourceOverrides?.foregroundColor = allowColor
                style.captionSourceOverrides?.foregroundOpacity = allowOpacity
                style.usesSourceColors = allowColor
                let result = style.sourceTextColor(source) ?? style.textColor
                XCTAssertEqual(result.red, allowColor ? source.red : style.textColor.red)
                XCTAssertEqual(result.green, allowColor ? source.green : style.textColor.green)
                XCTAssertEqual(result.blue, allowColor ? source.blue : style.textColor.blue)
                XCTAssertEqual(result.alpha, allowOpacity ? source.alpha : style.textColor.alpha)
            }
        }
        var historical = SubtitleStyle.default
        historical.usesSourceColors = false
        XCTAssertNil(historical.sourceTextColor(source), "Old custom styles still disable source alpha with source colors.")
    }

    func testFineSizeStepsAndBothRangeEndpointsPersistExactly() throws {
        for scale in [0.2, 1.01, 1.37, 4.0] {
            var style = SubtitleStyle.default
            style.fontScale = scale
            let saved = try JSONEncoder().encode(SubtitleStylePreferences(base: style))
            let restored = try JSONDecoder().decode(SubtitleStylePreferences.self, from: saved)
            XCTAssertEqual(restored.base.fontScale, scale)
        }
    }

}
