import Foundation

public struct DiscoveredProject: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var path: String
    public var kind: ProjectFact.Kind

    public init(id: String, name: String, path: String, kind: ProjectFact.Kind) {
        self.id = id
        self.name = name
        self.path = path
        self.kind = kind
    }

    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
}

/// Finds git repositories under the configured roots and maps arbitrary folders
/// (like a Claude session's cwd) to the project that contains them.
public enum RepoDiscovery {
    /// Folders that never contain the user's own top-level repos and are expensive to walk.
    static let skippedFolderNames: Set<String> = [
        "node_modules", ".build", "build", "dist", "DerivedData", "Pods", "Carthage", "vendor",
        "target", "venv", ".venv", "__pycache__", ".next", ".nuxt", "Library", "Applications",
        ".Trash", "Photos Library.photoslibrary",
    ]

    /// Breadth-first walk; stops descending once a repo is found.
    public static func scan(roots: [URL], depth: Int) -> [URL] {
        let fileManager = FileManager.default
        var found: [URL] = []
        var queue: [(URL, Int)] = roots.map { ($0.standardizedFileURL, 0) }
        var visited = Set<String>()

        while !queue.isEmpty {
            let (folder, level) = queue.removeFirst()
            guard visited.insert(folder.path).inserted else { continue }
            if isRepository(folder) {
                found.append(folder)
                continue
            }
            guard level < depth,
                  let children = try? fileManager.contentsOfDirectory(
                      at: folder,
                      includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey],
                      options: [.skipsHiddenFiles]
                  )
            else { continue }
            for child in children {
                guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]),
                      values.isDirectory == true,
                      values.isSymbolicLink != true,
                      values.isPackage != true,
                      !skippedFolderNames.contains(child.lastPathComponent)
                else { continue }
                queue.append((child, level + 1))
            }
        }
        return found.sorted { $0.path < $1.path }
    }

    public static func isRepository(_ folder: URL) -> Bool {
        // `.git` is a folder in normal clones and a file in worktrees/submodules.
        FileManager.default.fileExists(atPath: folder.appending(path: ".git").path)
    }

    /// Walks up from `path` to the nearest repository root, never above `ceiling`.
    public static func repositoryRoot(containing path: URL, ceiling: URL) -> URL? {
        var current = path.standardizedFileURL
        let ceilingPath = ceiling.standardizedFileURL.path
        while current.path.hasPrefix(ceilingPath), current.path != ceilingPath {
            if isRepository(current) { return current }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return nil
    }

    /// Gives every project a stable id. Names are used alone unless two projects share one,
    /// then the parent folder disambiguates: `repo:Notary` vs `repo:work/Notary`.
    public static func identify(repos: [URL], folders: [URL]) -> [DiscoveredProject] {
        func build(_ urls: [URL], kind: ProjectFact.Kind) -> [DiscoveredProject] {
            let unique = urls.map(\.standardizedFileURL).uniqued(by: \.path)
            let nameCounts = Dictionary(grouping: unique, by: \.lastPathComponent).mapValues(\.count)
            return unique.map { url in
                let name = url.lastPathComponent
                let key = nameCounts[name, default: 0] > 1
                    ? "\(url.deletingLastPathComponent().lastPathComponent)/\(name)"
                    : name
                let id = kind == .repo ? FactID.repo(key) : FactID.folder(key)
                return DiscoveredProject(id: id, name: name, path: url.path, kind: kind)
            }
        }
        let repoProjects = build(repos, kind: .repo)
        let repoPaths = Set(repoProjects.map(\.path))
        let folderProjects = build(folders.filter { !repoPaths.contains($0.standardizedFileURL.path) }, kind: .folder)
        return repoProjects + folderProjects
    }

    /// The project whose folder contains `path` (deepest match wins).
    public static func project(containing path: String, in projects: [DiscoveredProject]) -> DiscoveredProject? {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        return projects
            .filter { normalized == $0.path || normalized.hasPrefix($0.path + "/") }
            .max { $0.path.count < $1.path.count }
    }
}
