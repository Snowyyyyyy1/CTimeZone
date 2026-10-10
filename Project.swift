import ProjectDescription

let bundlePrefix = "com.snowyy"

/// Sparkle verifies every update against this EdDSA public key. It is public by
/// design; the matching private key lives only in the maintainer's keychain and
/// the release workflow's `SPARKLE_PRIVATE_ED_KEY` secret. Rotating it strands
/// every installed copy, so treat it as permanent.
let sparklePublicKey = "9sidt3/qLWykaiyqlRhd50gU94Ll7s+cdisiCpdEQD0="

let project = Project(
    name: "CTimezone",
    options: .options(
        defaultKnownRegions: ["en"],
        developmentRegion: "en"
    ),
    packages: [
        .remote(url: "https://github.com/sparkle-project/Sparkle", requirement: .upToNextMajor(from: "2.9.0"))
    ],
    targets: [
        .target(
            name: "CTimezoneKit",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "\(bundlePrefix).CTimezoneKit",
            deploymentTargets: .macOS("14.0"),
            sources: ["Sources/CTimezoneKit/**"],
            dependencies: []
        ),
        .target(
            name: "CTimezone",
            destinations: .macOS,
            product: .app,
            bundleId: "\(bundlePrefix).CTimezone",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "CTimeZone",
                "CFBundleName": "CTimeZone",
                "LSUIElement": false,
                "LSMinimumSystemVersion": "14.0",
                "NSHumanReadableCopyright": "CTimeZone",
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "SUFeedURL": "https://snowyyyyyy1.github.io/CTimeZone/appcast.xml",
                "SUPublicEDKey": .string(sparklePublicKey),
                "SUEnableAutomaticChecks": true,
                // Download in the background; install on quit or when the user agrees.
                "SUAutomaticallyUpdate": true,
                "SUScheduledCheckInterval": 86400
            ]),
            sources: ["Sources/CTimezone/**"],
            resources: ["Resources/Assets.xcassets"],
            scripts: [
                // The launcher ships inside CTimeZone so Sparkle updates both at once.
                // CTimeZone copies it to ~/Applications when the user asks for it.
                .post(
                    script: """
                    set -euo pipefail
                    DEST="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Library/Helpers"
                    mkdir -p "$DEST"
                    rm -rf "$DEST/ClaudeLauncher.app"
                    ditto "$BUILT_PRODUCTS_DIR/ClaudeLauncher.app" "$DEST/ClaudeLauncher.app"
                    """,
                    name: "Embed Claude Launcher",
                    inputPaths: ["$(BUILT_PRODUCTS_DIR)/ClaudeLauncher.app"],
                    outputPaths: ["$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Library/Helpers/ClaudeLauncher.app"]
                )
            ],
            dependencies: [
                .target(name: "CTimezoneKit"),
                .target(name: "ClaudeLauncher"),
                .package(product: "Sparkle")
            ],
            settings: .settings(base: [
                "PRODUCT_NAME": "CTimeZone",
                // Release builds override both from the git tag (see release.yml).
                // Sparkle compares CFBundleVersion, so it must grow with every release.
                "MARKETING_VERSION": "0.1.0",
                "CURRENT_PROJECT_VERSION": "1",
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
                // The embed script copies a whole bundle, which the script sandbox blocks.
                "ENABLE_USER_SCRIPT_SANDBOXING": "NO"
            ])
        ),
        // Windowless helper: opens Claude Desktop in the time zone chosen in
        // CTimeZone, then quits. Installed copies are renamed per zone.
        .target(
            name: "ClaudeLauncher",
            destinations: .macOS,
            product: .app,
            bundleId: "\(bundlePrefix).CTimezone.ClaudeLauncher",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Claude Launcher",
                "CFBundleName": "Claude Launcher",
                "LSUIElement": true,
                "LSMinimumSystemVersion": "14.0",
                "NSHumanReadableCopyright": "CTimeZone",
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)"
            ]),
            sources: ["Sources/ClaudeLauncher/**"],
            resources: ["Resources/Assets.xcassets"],
            dependencies: [.target(name: "CTimezoneKit")],
            settings: .settings(base: [
                "PRODUCT_NAME": "ClaudeLauncher",
                "MARKETING_VERSION": "0.1.0",
                "CURRENT_PROJECT_VERSION": "1",
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                "SKIP_INSTALL": "YES"
            ])
        ),
        .target(
            name: "CTimezoneKitTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "\(bundlePrefix).CTimezoneKitTests",
            deploymentTargets: .macOS("14.0"),
            sources: ["Tests/CTimezoneKitTests/**"],
            dependencies: [.target(name: "CTimezoneKit")]
        )
    ],
    schemes: [
        .scheme(
            name: "CTimezoneKit",
            buildAction: .buildAction(targets: ["CTimezoneKit"]),
            testAction: .targets(["CTimezoneKitTests"])
        )
    ]
)
