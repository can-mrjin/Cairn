import Foundation

/// Display row produced by ``SessionForkTree/flatten(ids:hostId:forkedFromHostId:collapsedParentIds:isActive:isUnread:)``.
public struct SessionForkRow: Equatable, Sendable, Identifiable {
    public let id: String
    /// Nesting level (0 = top-level root or orphan, 1..3 = forked branch).
    public let depth: Int
    /// True when this branch is the last visible child under its parent.
    public let isLastSibling: Bool
    /// For multi-level branches (`depth >= 2`), whether each ancestor column
    /// still has trailing siblings below (so a vertical connector should continue).
    public let ancestorHasMoreSiblings: [Bool]
    /// Total number of visible descendant branches under this session.
    public let descendantBranchCount: Int
    /// Whether this session's branches are currently collapsed.
    public let isCollapsed: Bool
    /// True when any descendant branch is actively working / needs attention.
    public let hasActiveBranch: Bool
    /// True when any descendant branch carries an unread reply.
    public let hasUnreadBranch: Bool

    public init(
        id: String,
        depth: Int,
        isLastSibling: Bool,
        ancestorHasMoreSiblings: [Bool] = [],
        descendantBranchCount: Int = 0,
        isCollapsed: Bool = false,
        hasActiveBranch: Bool = false,
        hasUnreadBranch: Bool = false
    ) {
        self.id = id
        self.depth = depth
        self.isLastSibling = isLastSibling
        self.ancestorHasMoreSiblings = ancestorHasMoreSiblings
        self.descendantBranchCount = descendantBranchCount
        self.isCollapsed = isCollapsed
        self.hasActiveBranch = hasActiveBranch
        self.hasUnreadBranch = hasUnreadBranch
    }
}

/// Groups visible sessions into parent → fork branch trees (matching Claude
/// Desktop's sidebar hierarchy for `(fork)` and `btw:` conversations).
///
/// Families stay ordered by the highest-priority (earliest) visible member in
/// the input list, so an active fork keeps its parent family near the top
/// instead of splitting parent and fork apart.
public enum SessionForkTree {
    public static let maxVisualDepth = 3

    public static func flatten(
        ids: [String],
        hostId: (String) -> String?,
        forkedFromHostId: (String) -> String?,
        collapsedParentIds: Set<String> = [],
        isActive: (String) -> Bool = { _ in false },
        isUnread: (String) -> Bool = { _ in false }
    ) -> [SessionForkRow] {
        guard !ids.isEmpty else { return [] }

        let rankById: [String: Int] = Dictionary(
            uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) }
        )

        // Map host session id (`local_...`) to the visible session id.
        var visibleIdByHost: [String: String] = [:]
        var forkedFromById: [String: String] = [:]
        for id in ids {
            if let host = hostId(id), !host.isEmpty, visibleIdByHost[host] == nil {
                visibleIdByHost[host] = id
            }
            if let parentHost = forkedFromHostId(id), !parentHost.isEmpty {
                forkedFromById[id] = parentHost
            }
        }

        // Resolve each session's nearest visible parent id, guarding against cycles.
        var parentById: [String: String] = [:]
        var childrenByParent: [String: [String]] = [:]
        for id in ids {
            guard let parentHost = forkedFromById[id],
                  let parentId = visibleIdByHost[parentHost],
                  parentId != id else { continue }
            parentById[id] = parentId
        }

        // Break any hypothetical cycle deterministically (lowest rank wins root).
        for id in ids {
            var visited: Set<String> = [id]
            var cursor = parentById[id]
            while let p = cursor {
                if !visited.insert(p).inserted {
                    parentById.removeValue(forKey: id)
                    break
                }
                cursor = parentById[p]
            }
        }

        for id in ids {
            if let parentId = parentById[id] {
                childrenByParent[parentId, default: []].append(id)
            }
        }

        // Preserve input priority order among sibling branches.
        for (parent, kids) in childrenByParent {
            childrenByParent[parent] = kids.sorted { (rankById[$0] ?? .max) < (rankById[$1] ?? .max) }
        }

        func subtreeBestRank(_ id: String) -> Int {
            var best = rankById[id] ?? .max
            for child in childrenByParent[id] ?? [] {
                best = min(best, subtreeBestRank(child))
            }
            return best
        }

        func subtreeStats(_ id: String) -> (count: Int, active: Bool, unread: Bool) {
            var count = 0
            var active = false
            var unread = false
            for child in childrenByParent[id] ?? [] {
                count += 1
                if isActive(child) { active = true }
                if isUnread(child) { unread = true }
                let sub = subtreeStats(child)
                count += sub.count
                active = active || sub.active
                unread = unread || sub.unread
            }
            return (count, active, unread)
        }

        let roots = ids
            .filter { parentById[$0] == nil }
            .sorted { subtreeBestRank($0) < subtreeBestRank($1) }

        var output: [SessionForkRow] = []
        output.reserveCapacity(ids.count)

        func emit(
            _ id: String,
            depth: Int,
            isLastSibling: Bool,
            ancestorHasMoreSiblings: [Bool]
        ) {
            let kids = childrenByParent[id] ?? []
            let stats = subtreeStats(id)
            let collapsed = !kids.isEmpty && collapsedParentIds.contains(id)
            output.append(SessionForkRow(
                id: id,
                depth: min(depth, maxVisualDepth),
                isLastSibling: isLastSibling,
                ancestorHasMoreSiblings: ancestorHasMoreSiblings,
                descendantBranchCount: stats.count,
                isCollapsed: collapsed,
                hasActiveBranch: stats.active,
                hasUnreadBranch: stats.unread
            ))
            guard !collapsed else { return }
            let nextAncestors = depth > 0
                ? ancestorHasMoreSiblings + [!isLastSibling]
                : ancestorHasMoreSiblings
            for (idx, child) in kids.enumerated() {
                emit(
                    child,
                    depth: depth + 1,
                    isLastSibling: idx == kids.count - 1,
                    ancestorHasMoreSiblings: nextAncestors
                )
            }
        }

        for (idx, root) in roots.enumerated() {
            emit(root, depth: 0, isLastSibling: idx == roots.count - 1, ancestorHasMoreSiblings: [])
        }
        return output
    }
}
