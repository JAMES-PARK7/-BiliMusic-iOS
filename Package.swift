// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BiliMusicPlaybackCore",
    platforms: [.iOS(.v15)],
    products: [.library(name: "BiliMusicPlaybackCore", targets: ["BiliMusicPlaybackCore"])],
    targets: [
        .target(
            name: "BiliMusicPlaybackCore",
            path: "ios/App/App",
            exclude: ["AppDelegate.swift", "SceneDelegate.swift", "AppBridgeViewController.swift", "NativePlayerPlugin.swift", "BiliBridgePlugin.swift", "Assets.xcassets", "Base.lproj", "Info.plist", "config.xml", "public", "capacitor.config.json"],
            sources: ["BiliNetwork.swift", "MediaResourceLoader.swift", "PlaybackAudioSession.swift"]
        ),
        .testTarget(
            name: "PlaybackRegressionTests",
            dependencies: ["BiliMusicPlaybackCore"],
            path: "native-tests",
            resources: [.copy("Fixtures"), .copy("Web")]
        )
    ]
)
