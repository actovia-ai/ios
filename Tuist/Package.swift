// swift-tools-version: 6.0
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        productTypes: [
            "Markdown": .staticFramework,
            "HighlightSwift": .staticFramework
        ]
    )
#endif

let package = Package(
    name: "ExodusIos",
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0"),
        // highlight.js in JavaScriptCore, SwiftUI-first: the same tokenizer the desktop uses,
        // so both apps colour a code block alike (Xcode palette, Sources/MarkdownKit/CodeHighlight*).
        .package(url: "https://github.com/appstefan/HighlightSwift.git", from: "1.1.0")
    ]
)
