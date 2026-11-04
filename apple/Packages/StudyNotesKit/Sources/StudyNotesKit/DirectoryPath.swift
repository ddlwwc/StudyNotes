import Foundation

public enum DirectoryPath {
    public static func expandedAncestors(of path: String) -> Set<String> {
        var paths: Set<String> = [""]
        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty else {
            return paths
        }
        for index in 1...components.count {
            paths.insert(
                components.prefix(index).joined(separator: "/")
            )
        }
        return paths
    }

    public static func rebase(
        _ paths: Set<String>,
        from oldPath: String,
        to newPath: String
    ) -> Set<String> {
        guard !oldPath.isEmpty else {
            return paths
        }
        return Set(
            paths.map { path in
                if path == oldPath {
                    return newPath
                }
                if path.hasPrefix(oldPath + "/") {
                    return newPath + String(path.dropFirst(oldPath.count))
                }
                return path
            }
        )
    }
}
