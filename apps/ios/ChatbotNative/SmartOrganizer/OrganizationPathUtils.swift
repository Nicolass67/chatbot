import Foundation

enum OrganizationPathUtils {
    static func normalize(_ path: String) -> String {
        var p = path.replacingOccurrences(of: "\\", with: "/")
        while p.contains("//") { p = p.replacingOccurrences(of: "//", with: "/") }
        p = p.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = p.split(separator: "/").map(String.init)
        var stack: [String] = []
        for part in parts {
            if part.isEmpty || part == "." { continue }
            if part == ".." {
                if !stack.isEmpty { stack.removeLast() }
                continue
            }
            stack.append(part)
        }
        return stack.joined(separator: "/")
    }

    static func containsTraversal(_ path: String) -> Bool {
        let raw = path.replacingOccurrences(of: "\\", with: "/")
        if raw.hasPrefix("/") || raw.contains("://") { return true }
        return raw.split(separator: "/", omittingEmptySubsequences: false).map(String.init).contains("..")
    }

    static func isWithin(root: String, path: String) -> Bool {
        let r = normalize(root)
        let p = normalize(path)
        if containsTraversal(path) { return false }
        if r.isEmpty { return true }
        if p == r { return true }
        return p.hasPrefix(r + "/")
    }

    static func parent(of path: String) -> String {
        let n = normalize(path)
        guard let idx = n.lastIndex(of: "/") else { return "" }
        return String(n[..<idx])
    }

    static func join(_ base: String, _ child: String) -> String {
        let b = normalize(base)
        let c = normalize(child)
        if b.isEmpty { return c }
        if c.isEmpty { return b }
        return b + "/" + c
    }

    static func depth(of path: String) -> Int {
        let n = normalize(path)
        if n.isEmpty { return 0 }
        return n.split(separator: "/").count
    }

    static func fileExtension(of name: String) -> String {
        let n = name.lowercased()
        guard let dot = n.lastIndex(of: "."), dot < n.endIndex else { return "" }
        return String(n[n.index(after: dot)...])
    }

    static func basename(of path: String) -> String {
        let n = normalize(path)
        return n.split(separator: "/").last.map(String.init) ?? n
    }
}
