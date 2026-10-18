import ProjectDescription

let project = Project(
    name: "Moy",
    options: .options(
        automaticSchemesOptions: .disabled,
        defaultKnownRegions: ["en", "ja"],
        developmentRegion: "en",
    ),
    settings: .settings(base: [
        "SWIFT_VERSION": "6.0", // Swift 6 language mode; compiler: Swift 6.4 (Xcode 27).
        "ENABLE_APP_SANDBOX": "NO",
        "ARCHS": "arm64",
    ]),
    targets: [
        .target(
            name: "MoyApp",
            destinations: .macOS,
            product: .app,
            productName: "Moy",
            bundleId: "com.sputnik-apps.Moy",
            deploymentTargets: .macOS("26.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Moy",
                "CFBundleShortVersionString": "0.2.1",
                "CFBundleVersion": "1",
                "LSUIElement": true,
                "UTExportedTypeDeclarations": .array([
                    .dictionary([
                        "UTTypeIdentifier": "com.sputnik-apps.moy.editor-argument",
                        "UTTypeConformsTo": .array(["public.data"]),
                    ]),
                ]),
                "LSApplicationCategoryType": "public.app-category.developer-tools",
            ]),
            buildableFolders: [
                .folder("Sources/MoyApp", exceptions: [
                    .exception(excluded: ["Core/.gitkeep", "Views/.gitkeep"]),
                ]),
                "Resources/MoyApp",
            ],
            scripts: [
                .post(
                    script: """
                    set -eu
                    mkdir -p "${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers"
                    cp "${BUILT_PRODUCTS_DIR}/moy" "${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers/moy"
                    """,
                    name: "Embed CLI",
                    inputPaths: ["$(BUILT_PRODUCTS_DIR)/moy"],
                    outputPaths: ["$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Helpers/moy"],
                    basedOnDependencyAnalysis: true,
                ),
            ],
            dependencies: [
                .target(name: "MoyKit"),
                .target(name: "MoyCLI"),
                .external(name: "NanoRedux"),
            ],
            settings: .settings(base: [
                "PRODUCT_MODULE_NAME": "MoyApp",
                "ENABLE_HARDENED_RUNTIME": "YES",
                "CODE_SIGN_STYLE": "Automatic",
                "CODE_SIGN_IDENTITY": "-",
            ]),
        ),
        .target(
            name: "MoyCLI",
            destinations: .macOS,
            product: .commandLineTool,
            productName: "moy",
            bundleId: "com.sputnik-apps.MoyCLI",
            deploymentTargets: .macOS("26.0"),
            infoPlist: nil,
            buildableFolders: ["Sources/MoyCLI"],
            dependencies: [
                .target(name: "MoyKit"),
                .external(name: "ArgumentParser"),
            ],
            settings: .settings(base: [
                "PRODUCT_MODULE_NAME": "MoyCLI",
                "ENABLE_HARDENED_RUNTIME": "YES",
                "CODE_SIGN_IDENTITY": "-",
                "SKIP_INSTALL": "YES",
            ]),
        ),
        .target(
            name: "MoyKit",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "com.sputnik-apps.MoyKit",
            deploymentTargets: .macOS("26.0"),
            infoPlist: .default,
            buildableFolders: ["Sources/MoyKit"],
        ),
        .target(
            name: "MoyAppTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.sputnik-apps.MoyAppTests",
            deploymentTargets: .macOS("26.0"),
            infoPlist: .default,
            buildableFolders: ["Tests/MoyAppTests"],
            dependencies: [.target(name: "MoyApp")],
        ),
        .target(
            name: "MoyCLITests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.sputnik-apps.MoyCLITests",
            deploymentTargets: .macOS("26.0"),
            infoPlist: .default,
            buildableFolders: ["Tests/MoyCLITests"],
            dependencies: [.target(name: "MoyCLI")],
        ),
        .target(
            name: "MoyKitTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.sputnik-apps.MoyKitTests",
            deploymentTargets: .macOS("26.0"),
            infoPlist: .default,
            buildableFolders: ["Tests/MoyKitTests"],
            dependencies: [.target(name: "MoyKit")],
        ),
    ],
    schemes: [
        .scheme(
            name: "Moy",
            buildAction: .buildAction(targets: ["MoyApp"]),
            testAction: .targets(["MoyAppTests", "MoyCLITests", "MoyKitTests"]),
            runAction: .runAction(configuration: .debug, executable: "MoyApp"),
        ),
        .scheme(
            name: "MoyCLI",
            buildAction: .buildAction(targets: ["MoyCLI"]),
            testAction: .targets(["MoyCLITests"]),
            runAction: .runAction(configuration: .debug, executable: "MoyCLI"),
        ),
        .scheme(
            name: "MoyKit",
            buildAction: .buildAction(targets: ["MoyKit"]),
            testAction: .targets(["MoyKitTests"]),
        ),
    ],
    resourceSynthesizers: [.strings()],
)
