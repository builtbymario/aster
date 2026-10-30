// swift-tools-version:5.10
import PackageDescription

// The app executable compiles Sources/ and Shared/ (Shared/ is also compiled into
// the iPhone app, so it stays a plain folder rather than a separate module).
// build.sh wraps the executable in Aster.app with Info.plist, resources and signing.
let package = Package(
    name: "Aster",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Aster",
            path: ".",
            exclude: [
                "Assets", "Localization", "Tests", "Info.plist", "Release.entitlements", "connection.json",
                "LEEME.md", "INSTALAR.md", "build.sh", "release.sh", "run.sh", "test.sh", "test-remote.sh", "sign-local.py"
            ],
            sources: ["Sources", "Shared"]
        ),
        .testTarget(name: "AsterTests", dependencies: ["Aster"], path: "Tests")
    ]
)
