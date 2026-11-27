import Foundation

public enum BuiltInSilencePreset: String, CaseIterable, Sendable, Codable, Identifiable {
    case codexChronicle       // Codex Chronicle Memory Summary
    case codexAppGitHelper    // Codex App Git helper background sessions
    case codexAppSuggestions  // Codex App prompt suggestion background sessions
    case codexMemoryWriter    // Codex Memory Writer ("## Memory Writing Agent" / memory writer prefix)
    case claudeMem            // Claude-Mem plugin background sessions

    public var id: String { rawValue }
}

public struct SilenceRuleConfig: Sendable, Codable, Equatable {
    public var enabledPresets: Set<BuiltInSilencePreset>
    public var blockedDirectories: [String]
    public var blockedPromptPrefixes: [String]
    public var blockedBundleIds: [String]

    public static let defaultEnabledPresets: Set<BuiltInSilencePreset> = Set(BuiltInSilencePreset.allCases)

    public init(
        enabledPresets: Set<BuiltInSilencePreset> = defaultEnabledPresets,
        blockedDirectories: [String] = [],
        blockedPromptPrefixes: [String] = [],
        blockedBundleIds: [String] = []
    ) {
        self.enabledPresets = enabledPresets
        self.blockedDirectories = blockedDirectories
        self.blockedPromptPrefixes = blockedPromptPrefixes
        self.blockedBundleIds = blockedBundleIds
    }

    private enum CodingKeys: String, CodingKey {
        case enabledPresets
        case blockedDirectories
        case blockedPromptPrefixes
        case blockedBundleIds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enabledPresets = try container.decodeIfPresent(
            Set<BuiltInSilencePreset>.self,
            forKey: .enabledPresets
        ) ?? Self.defaultEnabledPresets
        self.blockedDirectories = try container.decodeIfPresent(
            [String].self,
            forKey: .blockedDirectories
        ) ?? []
        self.blockedPromptPrefixes = try container.decodeIfPresent(
            [String].self,
            forKey: .blockedPromptPrefixes
        ) ?? []
        self.blockedBundleIds = try container.decodeIfPresent(
            [String].self,
            forKey: .blockedBundleIds
        ) ?? []
    }
}

public enum SessionSilenceReason: Sendable, Equatable {
    case preset(BuiltInSilencePreset)
    case directory(String)
    case promptPrefix(String)
    case bundleId(String)
}

public enum SessionSilenceFilter {
    /// Returns a silence reason if this session should be hidden/silenced, or nil if allowed.
    public static func silenceReason(
        source: String,
        cwd: String?,
        firstPrompt: String?,
        launcherBundleId: String? = nil,
        config: SilenceRuleConfig
    ) -> SessionSilenceReason? {
        if let rawBundle = launcherBundleId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawBundle.isEmpty {
            let loweredBundle = rawBundle.lowercased()
            for rule in config.blockedBundleIds {
                let trimmedRule = rule.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedRule.isEmpty && trimmedRule.lowercased() == loweredBundle {
                    return .bundleId(trimmedRule)
                }
            }
        }

        if let rawCwd = cwd {
            let normalizedCwd = normalizeDirectory(rawCwd)
            if !normalizedCwd.isEmpty {
                for rule in config.blockedDirectories {
                    let normalizedRule = normalizeDirectory(rule)
                    guard !normalizedRule.isEmpty else { continue }
                    if directoryMatches(cwd: normalizedCwd, blockedDirectory: normalizedRule) {
                        return .directory(normalizedRule)
                    }
                }
            }
        }

        let trimmedPrompt = (firstPrompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredPrompt = trimmedPrompt.lowercased()

        if !loweredPrompt.isEmpty {
            for rule in config.blockedPromptPrefixes {
                let trimmedRule = rule.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedRule.isEmpty else { continue }
                if loweredPrompt.hasPrefix(trimmedRule.lowercased()) {
                    return .promptPrefix(trimmedRule)
                }
            }
        }

        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let loweredCwd = (cwd ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        for preset in BuiltInSilencePreset.allCases where config.enabledPresets.contains(preset) {
            if matchesPreset(
                preset,
                source: normalizedSource,
                loweredCwd: loweredCwd,
                loweredPrompt: loweredPrompt
            ) {
                return .preset(preset)
            }
        }

        return nil
    }

    @discardableResult
    public static func addBlockedDirectory(_ dir: String, to config: inout SilenceRuleConfig) -> Bool {
        let normalized = normalizeDirectory(dir)
        guard !normalized.isEmpty else { return false }
        if config.blockedDirectories.contains(where: { normalizeDirectory($0) == normalized }) {
            return false
        }
        config.blockedDirectories.append(normalized)
        return true
    }

    public static func removeBlockedDirectory(_ dir: String, from config: inout SilenceRuleConfig) {
        let normalized = normalizeDirectory(dir)
        guard !normalized.isEmpty else { return }
        config.blockedDirectories.removeAll { normalizeDirectory($0) == normalized }
    }

    @discardableResult
    public static func addBlockedPromptPrefix(_ prefix: String, to config: inout SilenceRuleConfig) -> Bool {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lowered = trimmed.lowercased()
        if config.blockedPromptPrefixes.contains(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == lowered
        }) {
            return false
        }
        config.blockedPromptPrefixes.append(trimmed)
        return true
    }

    public static func removeBlockedPromptPrefix(_ prefix: String, from config: inout SilenceRuleConfig) {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let lowered = trimmed.lowercased()
        config.blockedPromptPrefixes.removeAll {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == lowered
        }
    }

    public static func togglePreset(_ preset: BuiltInSilencePreset, in config: inout SilenceRuleConfig) {
        if config.enabledPresets.contains(preset) {
            config.enabledPresets.remove(preset)
        } else {
            config.enabledPresets.insert(preset)
        }
    }

    public static func encode(_ config: SilenceRuleConfig) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(config),
              let raw = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return raw
    }

    public static func decode(_ raw: String) -> SilenceRuleConfig {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(SilenceRuleConfig.self, from: data) else {
            return SilenceRuleConfig()
        }
        return decoded
    }

    // MARK: - Helpers

    private static func normalizeDirectory(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let expanded: String
        if trimmed == "~" || trimmed.hasPrefix("~/") {
            expanded = (trimmed as NSString).expandingTildeInPath
        } else {
            expanded = trimmed
        }

        if expanded == "/" {
            return "/"
        }

        var result = expanded
        while result.count > 1 && result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    private static func directoryMatches(cwd: String, blockedDirectory: String) -> Bool {
        if blockedDirectory == "/" {
            return cwd.hasPrefix("/")
        }
        return cwd == blockedDirectory || cwd.hasPrefix(blockedDirectory + "/")
    }

    private static func isCodexSource(_ source: String) -> Bool {
        source == "codex" || source.hasPrefix("codex")
    }

    private static func isClaudeSource(_ source: String) -> Bool {
        source == "claude" || source.hasPrefix("claude")
    }

    private static func matchesPreset(
        _ preset: BuiltInSilencePreset,
        source: String,
        loweredCwd: String,
        loweredPrompt: String
    ) -> Bool {
        switch preset {
        case .codexChronicle:
            guard isCodexSource(source) else { return false }
            if loweredCwd.contains("/.codex/chronicle")
                || loweredCwd.hasSuffix("/.codex/chronicle")
                || loweredCwd.contains("/.codex/codex-chronicle") {
                return true
            }
            // Only match structured background job header prefixes, never casual user prompts.
            if loweredPrompt.hasPrefix("codex chronicle:")
                || loweredPrompt.hasPrefix("[codex chronicle]")
                || loweredPrompt.hasPrefix("## codex chronicle")
                || (loweredPrompt.hasPrefix("create a chronicle memory summary") && loweredPrompt.contains("today's sessions")) {
                return true
            }
            return false

        case .codexAppGitHelper:
            guard isCodexSource(source), !loweredPrompt.isEmpty else { return false }
            // Require explicit helper-prompt anchors at the start of the prompt (never mid-sentence
            // matches like "Review this script and make sure it does not commit or push").
            if loweredPrompt.hasPrefix("generate a concise commit message")
                || loweredPrompt.hasPrefix("generate a commit message")
                || loweredPrompt.hasPrefix("write a concise commit message")
                || loweredPrompt.hasPrefix("suggest a git commit message based on")
                || loweredPrompt.hasPrefix("generate a pull request title")
                || loweredPrompt.hasPrefix("generate a pr title")
                || loweredPrompt.hasPrefix("help decide whether to commit or push") {
                return true
            }
            return false

        case .codexAppSuggestions:
            guard isCodexSource(source), !loweredPrompt.isEmpty else { return false }
            // Require helper-job directive prefixes rather than arbitrary substring mentions.
            if loweredPrompt.hasPrefix("suggest next prompt")
                || loweredPrompt.hasPrefix("suggest the next prompt")
                || loweredPrompt.hasPrefix("return 3 follow-up suggestions")
                || loweredPrompt.hasPrefix("generate follow-up suggestions")
                || loweredPrompt.hasPrefix("generate recommended prompts")
                || loweredPrompt.hasPrefix("suggest follow-up prompts") {
                return true
            }
            if loweredPrompt.hasPrefix("generate prompt suggestions")
                || loweredPrompt.hasPrefix("provide prompt suggestions")
                || loweredPrompt.hasPrefix("return prompt suggestions") {
                return true
            }
            return false

        case .codexMemoryWriter:
            guard isCodexSource(source), !loweredPrompt.isEmpty else { return false }
            return loweredPrompt.hasPrefix("## memory writing agent")
                || loweredPrompt.hasPrefix("# memory writing agent")
                || loweredPrompt.hasPrefix("memory writing agent:")
                || loweredPrompt.hasPrefix("you are a memory writing agent")
                || loweredPrompt.hasPrefix("you are the memory writing agent")

        case .claudeMem:
            guard isClaudeSource(source) else { return false }
            // Match hidden plugin/state directories rather than arbitrary user repos named `claude-mem`.
            if loweredCwd.contains("/.claude-mem")
                || loweredCwd.hasSuffix("/.claude-mem")
                || loweredCwd.contains("/.claude/plugins/claude-mem")
                || loweredCwd.contains("/.claude/claude-mem") {
                return true
            }
            if loweredPrompt.hasPrefix("[claude-mem]")
                || loweredPrompt.hasPrefix("claude-mem:")
                || loweredPrompt.hasPrefix("claude-mem observer") {
                return true
            }
            if loweredPrompt.contains("observer")
                && (loweredPrompt.contains("memory summary")
                    || loweredPrompt.contains("memory worker")
                    || (loweredPrompt.contains("observation") && loweredPrompt.contains("memory"))) {
                return true
            }
            return false
        }
    }
}
