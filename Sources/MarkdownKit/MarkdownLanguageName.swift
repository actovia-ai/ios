import Foundation

/// The name a code block's language is shown under — `TypeScript`, not the fence's `typescript` or `ts` — the same
/// table the desktop keeps in `src/renderer/components/markdown/language-names.ts`. An unknown name keeps its
/// spelling with a capital first letter.
enum MarkdownLanguageName {
    static func display(_ id: String) -> String {
        let key = id.trimmingCharacters(in: .whitespaces).lowercased()
        if let known = names[key] { return known }
        guard let first = key.first else { return "" }
        return first.uppercased() + key.dropFirst()
    }

    /// A block with no language, or plain text by name: its strip carries no name — "Text" over an ASCII diagram or a
    /// command's output said nothing — only the copy button.
    static func isPlainText(_ id: String?) -> Bool {
        let key = (id ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return ["", "plaintext", "plain", "text", "txt"].contains(key)
    }

    private static let names: [String: String] = [
        "bash": "Bash", "c": "C", "c++": "C++", "cpp": "C++", "cs": "C#", "csharp": "C#", "css": "CSS",
        "dart": "Dart", "diff": "Diff", "dockerfile": "Dockerfile", "docker": "Dockerfile", "elixir": "Elixir",
        "erlang": "Erlang", "go": "Go", "golang": "Go", "graphql": "GraphQL", "groovy": "Groovy",
        "haskell": "Haskell", "hs": "Haskell", "html": "HTML", "http": "HTTP", "ini": "INI", "java": "Java",
        "javascript": "JavaScript", "js": "JavaScript", "json": "JSON", "json5": "JSON5", "jsonc": "JSON",
        "jsx": "JSX", "kotlin": "Kotlin", "kt": "Kotlin", "latex": "LaTeX", "tex": "LaTeX", "less": "Less",
        "lua": "Lua", "makefile": "Makefile", "make": "Makefile", "markdown": "Markdown", "md": "Markdown",
        "mermaid": "Mermaid", "nginx": "Nginx", "objc": "Objective-C", "objectivec": "Objective-C",
        "objective-c": "Objective-C", "ocaml": "OCaml", "perl": "Perl", "php": "PHP", "plaintext": "Text",
        "text": "Text", "txt": "Text", "powershell": "PowerShell", "ps1": "PowerShell", "pwsh": "PowerShell",
        "proto": "Protobuf", "protobuf": "Protobuf", "py": "Python", "python": "Python", "r": "R", "rb": "Ruby",
        "ruby": "Ruby", "rs": "Rust", "rust": "Rust", "scala": "Scala", "scss": "SCSS", "sass": "Sass",
        "sh": "Shell", "shell": "Shell", "zsh": "Zsh", "fish": "Fish", "console": "Console",
        "shell-session": "Console", "sql": "SQL", "postgres": "PostgreSQL", "postgresql": "PostgreSQL",
        "mysql": "MySQL", "sqlite": "SQLite", "svelte": "Svelte", "swift": "Swift", "toml": "TOML",
        "ts": "TypeScript", "typescript": "TypeScript", "tsx": "TSX", "vue": "Vue", "wasm": "WebAssembly",
        "xml": "XML", "yaml": "YAML", "yml": "YAML", "zig": "Zig",
    ]
}
