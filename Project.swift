import ProjectDescription

private let bundleIdRoot = "app.yancey.actovia.ios"
private let developmentTeam = "YLF27G9ZMT"
private let deploymentTargets = DeploymentTargets.iOS("26.0")

private func moduleTarget(
    name: String,
    dependencies: [TargetDependency] = []
) -> Target {
    .target(
        name: name,
        destinations: .iOS,
        product: .staticFramework,
        bundleId: "\(bundleIdRoot).\(name)",
        deploymentTargets: deploymentTargets,
        buildableFolders: [BuildableFolder(stringLiteral: "Sources/\(name)")],
        dependencies: dependencies
    )
}

let project = Project(
    name: "ActoviaIos",
    options: .options(
        defaultKnownRegions: ["en", "zh-Hant", "zh-HK", "ja", "ko", "fr", "de", "es", "pt-BR", "it"],
        developmentRegion: "en"
    ),
    // The composer's glow while recording (Sources/ChatFeature/ComposerVoiceGlow.swift): Jakub Antalik's voice-glow,
    // MIT. Through Xcode's own package integration, not Tuist/Package.swift: Tuist (4.208) puts the package's `.metal`
    // in both the Sources and Resources phases of its bundle and Xcode refuses the duplicate tasks. The monorepo's
    // tags predate its root manifest, so a revision of main is pinned.
    packages: [
        .remote(
            url: "https://github.com/Jakubantalik/Libraries.dev",
            requirement: .revision("b7f44b8744f4e09ff088d824719636a513110e2a"))
    ],
    // The version (marketing + build number) comes from one xcconfig, shared by
    // the app and the widget extension — see Configs/Version.xcconfig.
    settings: .settings(
        base: ["SWIFT_VERSION": "6.0"],
        configurations: [
            .debug(name: .debug, xcconfig: "Configs/Version.xcconfig"),
            .release(name: .release, xcconfig: "Configs/Version.xcconfig")
        ]
    ),
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            productName: "Actovia",
            bundleId: bundleIdRoot,
            deploymentTargets: deploymentTargets,
            infoPlist: .extendingDefault(
                with: [
                    // Ody on a plain background; LaunchSplash (Sources/App)
                    // picks up from this exact frame and animates it away.
                    "UILaunchScreen": [
                        "UIColorName": "LaunchBackground",
                        "UIImageName": "LaunchLogo"
                    ],
                    // What the app is showing, published as the current activity so a screenshot is titled after
                    // it (ActoviaActivity and screenTitle in Models).
                    "NSUserActivityTypes": ["app.yancey.actovia.viewing"],
                    "NSAppTransportSecurity": [
                        "NSAllowsLocalNetworking": true,
                        // Away from home the paired computer is reached over Tailscale by its MagicDNS name. Its
                        // certificate is self-signed and trusted by its pin (PinnedSessionDelegate); ATS honours that
                        // only where it is relaxed — local networks above, and Tailscale's names here. Nothing else.
                        "NSExceptionDomains": [
                            "ts.net": [
                                "NSIncludesSubdomains": true,
                                "NSExceptionAllowsInsecureHTTPLoads": true
                            ]
                        ]
                    ],
                    "NSLocalNetworkUsageDescription":
                        "Actovia needs local network access to connect to the Actovia service running on your computer.",
                    "NSMicrophoneUsageDescription":
                        "Actovia records your voice only while you are dictating a message, to turn it into text for the chat.",
                    "NSCameraUsageDescription":
                        "Actovia uses the camera to scan the pairing code shown on your computer, and to take photos you add to a chat.",
                    "NSFaceIDUsageDescription":
                        "Actovia uses Face ID to unlock the connection to your computer.",
                    "NSLocationWhenInUseUsageDescription":
                        "Actovia uses your location to show your position on the itinerary map and center the map when you tap the location button.",
                    "NSPhotoLibraryAddUsageDescription":
                        "Actovia saves the images you choose to your photo library.",
                    "NSHealthShareUsageDescription":
                        "Actovia reads your sleep, activity, heart and body data to write your daily health report.",
                    "NSHealthUpdateUsageDescription":
                        "Actovia saves the water you log to Apple Health.",
                    // actovia:// — the widgets' links (WidgetKitShared.DeepLink).
                    "CFBundleURLTypes": [
                        ["CFBundleURLName": "app.yancey.actovia.link", "CFBundleURLSchemes": ["actovia"]]
                    ]
                ]
            ),
            buildableFolders: ["Sources/App", "Resources/App"],
            entitlements: .dictionary([
                "com.apple.developer.healthkit": .boolean(true),
                "com.apple.developer.healthkit.access": .array([]),
                "com.apple.security.application-groups": .array([.string("group.app.yancey.actovia")])
            ]),
            dependencies: [
                .target(name: "ChatFeature"),
                .target(name: "SettingsFeature"),
                .target(name: "PhilharmonicFeature"),
                .target(name: "HealthFeature"),
                .target(name: "OdyKit"),
                .target(name: "WidgetKitShared"),
                .target(name: "WidgetUI"),
                .target(name: "ActoviaWidgets"),
                .target(name: "NetworkingKit"),
                .target(name: "MarkdownKit")
            ],
            settings: .settings(
                base: [
                    "DEVELOPMENT_TEAM": .string(developmentTeam),
                    "CODE_SIGN_STYLE": "Automatic"
                ]
            )
        ),
        // The widgets and the Control Center control. Links only the widget modules — never NetworkingKit or the
        // keychain; it reads the App Group snapshot the app writes. The App's string catalog is a member too.
        .target(
            name: "ActoviaWidgets",
            destinations: .iOS,
            product: .appExtension,
            productName: "ActoviaWidgets",
            bundleId: "\(bundleIdRoot).widgets",
            deploymentTargets: deploymentTargets,
            infoPlist: .file(path: "Widgets/Info.plist"),
            resources: ["Resources/App/Localizable.xcstrings"],
            buildableFolders: ["Widgets/Sources"],
            entitlements: .dictionary([
                "com.apple.security.application-groups": .array([.string("group.app.yancey.actovia")])
            ]),
            dependencies: [
                .target(name: "WidgetKitShared"), .target(name: "WidgetUI"), .target(name: "OdyKit"),
                .sdk(name: "WidgetKit", type: .framework), .sdk(name: "SwiftUI", type: .framework)
            ],
            settings: .settings(base: ["DEVELOPMENT_TEAM": .string(developmentTeam), "CODE_SIGN_STYLE": "Automatic"])
        ),
        .target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleIdRoot).AppTests",
            deploymentTargets: deploymentTargets,
            buildableFolders: ["Tests/AppTests"],
            dependencies: [.target(name: "App")]
        ),
        moduleTarget(name: "Models"),
        .target(
            name: "ModelsTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleIdRoot).ModelsTests",
            deploymentTargets: deploymentTargets,
            buildableFolders: ["Tests/ModelsTests"],
            dependencies: [.target(name: "Models")]
        ),
        moduleTarget(name: "NetworkingKit", dependencies: [.target(name: "Models")]),
        .target(
            name: "NetworkingKitTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleIdRoot).NetworkingKitTests",
            deploymentTargets: deploymentTargets,
            buildableFolders: ["Tests/NetworkingKitTests"],
            dependencies: [.target(name: "NetworkingKit"), .target(name: "Models")]
        ),
        moduleTarget(
            name: "MarkdownKit",
            dependencies: [.external(name: "Markdown"), .external(name: "HighlightSwift")]
        ),
        .target(
            name: "MarkdownKitTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleIdRoot).MarkdownKitTests",
            deploymentTargets: deploymentTargets,
            buildableFolders: ["Tests/MarkdownKitTests"],
            dependencies: [.target(name: "MarkdownKit")]
        ),
        moduleTarget(
            name: "ChatFeature",
            dependencies: [
                .target(name: "NetworkingKit"), .target(name: "Models"), .target(name: "MarkdownKit"),
                .package(product: "VoiceGlowKit")
            ]
        ),
        .target(
            name: "ChatFeatureTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleIdRoot).ChatFeatureTests",
            deploymentTargets: deploymentTargets,
            buildableFolders: ["Tests/ChatFeatureTests"],
            dependencies: [
                .target(name: "ChatFeature"), .target(name: "NetworkingKit"), .target(name: "Models")
            ]
        ),
        moduleTarget(
            name: "SettingsFeature",
            dependencies: [.target(name: "NetworkingKit"), .target(name: "Models")]
        ),
        .target(
            name: "SettingsFeatureTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleIdRoot).SettingsFeatureTests",
            deploymentTargets: deploymentTargets,
            buildableFolders: ["Tests/SettingsFeatureTests"],
            dependencies: [
                .target(name: "SettingsFeature"), .target(name: "NetworkingKit"), .target(name: "Models")
            ]
        ),
        moduleTarget(name: "PhilharmonicFeature", dependencies: [.target(name: "Models")]),
        moduleTarget(name: "OdyKit"),
        moduleTarget(name: "WidgetKitShared"),
        moduleTarget(name: "WidgetUI", dependencies: [.target(name: "WidgetKitShared"), .target(name: "OdyKit")]),
        .target(
            name: "WidgetKitSharedTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleIdRoot).WidgetKitSharedTests",
            deploymentTargets: deploymentTargets,
            buildableFolders: ["Tests/WidgetKitSharedTests"],
            dependencies: [.target(name: "WidgetKitShared")]
        ),
        .target(
            name: "OdyKitTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleIdRoot).OdyKitTests",
            deploymentTargets: deploymentTargets,
            buildableFolders: ["Tests/OdyKitTests"],
            dependencies: [.target(name: "OdyKit")]
        ),
        moduleTarget(
            name: "HealthFeature",
            dependencies: [
                .target(name: "Models"), .target(name: "NetworkingKit"), .target(name: "MarkdownKit"),
                .target(name: "OdyKit"), .target(name: "WidgetKitShared")
            ]
        ),
        .target(
            name: "HealthFeatureTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleIdRoot).HealthFeatureTests",
            deploymentTargets: deploymentTargets,
            buildableFolders: ["Tests/HealthFeatureTests"],
            dependencies: [
                .target(name: "HealthFeature"), .target(name: "NetworkingKit"), .target(name: "Models")
            ]
        )
    ]
)
