import Foundation

public enum GrammarSemanticSymbolRole: String, Hashable, Codable, Sendable {
    case definition
    case reference
}

public enum GrammarSemanticSymbolScope: String, Hashable, Codable, Sendable {
    case workspace
    case document
}

/// Declaratively classifies one terminal in an incremental syntax tree.
/// `enclosingProduction` may identify any ancestor reduction, not only the
/// terminal's immediate parent.
public struct GrammarSemanticSymbolRule: Hashable, Codable, Sendable {
    public let tokenKind: String
    public let enclosingProduction: Int?
    public let kind: String
    public let role: GrammarSemanticSymbolRole
    public let scope: GrammarSemanticSymbolScope

    public init(
        tokenKind: String,
        enclosingProduction: Int? = nil,
        kind: String,
        role: GrammarSemanticSymbolRole,
        scope: GrammarSemanticSymbolScope = .workspace
    ) {
        self.tokenKind = tokenKind
        self.enclosingProduction = enclosingProduction
        self.kind = kind
        self.role = role
        self.scope = scope
    }
}

public struct GrammarSemanticWorkspaceSchema: Hashable, Codable, Sendable {
    public let rules: [GrammarSemanticSymbolRule]
    public let caseSensitive: Bool
    public let renamePattern: String

    public init(
        rules: [GrammarSemanticSymbolRule],
        caseSensitive: Bool = true,
        renamePattern: String = #"^[A-Za-z_][A-Za-z0-9_]*$"#
    ) {
        self.rules = rules
        self.caseSensitive = caseSensitive
        self.renamePattern = renamePattern
    }
}

public struct GrammarSemanticLocation: Hashable, Codable, Sendable {
    public let documentID: String
    public let path: String
    public let revision: Int
    public let range: SourceRange
}

public struct GrammarSemanticOccurrence: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let kind: String
    public let role: GrammarSemanticSymbolRole
    public let scope: GrammarSemanticSymbolScope
    public let location: GrammarSemanticLocation
    public let syntaxIdentity: GrammarIncrementalIdentity
}

public enum GrammarSemanticWorkspaceDiagnosticCode: String, Hashable, Codable, Sendable {
    case unresolvedReference
    case ambiguousReference
    case duplicateDefinition
}

public struct GrammarSemanticWorkspaceDiagnostic: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let code: GrammarSemanticWorkspaceDiagnosticCode
    public let message: String
    public let location: GrammarSemanticLocation
}

public struct GrammarSemanticDependency: Identifiable, Hashable, Codable, Sendable {
    public let sourceDocumentID: String
    public let targetDocumentID: String
    public let symbolCount: Int
    public var id: String { "\(sourceDocumentID)->\(targetDocumentID)" }
}

public struct GrammarSemanticWorkspaceDocumentEdit: Hashable, Codable, Sendable {
    public let documentID: String
    public let path: String
    public let expectedRevision: Int
    /// Descending source order so edits can be applied sequentially without
    /// invalidating the remaining ranges.
    public let edits: [GrammarTextEdit]
}

public struct GrammarSemanticRenamePlan: Hashable, Codable, Sendable {
    public let symbolName: String
    public let replacement: String
    public let kind: String
    public let affectedOccurrences: Int
    public let documents: [GrammarSemanticWorkspaceDocumentEdit]
}

public enum GrammarSemanticWorkspaceError: Error, LocalizedError, Sendable {
    case noSymbol
    case unresolved(String)
    case ambiguous(String)
    case invalidName(String)
    case nameCollision(String)
    case staleDocument(documentID: String, expected: Int, actual: Int)

    public var errorDescription: String? {
        switch self {
        case .noSymbol: "No semantic symbol exists at that source position."
        case .unresolved(let name): "‘\(name)’ has no definition in its semantic scope."
        case .ambiguous(let name): "‘\(name)’ resolves to more than one definition."
        case .invalidName(let name): "‘\(name)’ is not a valid replacement symbol name."
        case .nameCollision(let name): "Renaming would collide with existing definition \(name)."
        case .staleDocument(let id, let expected, let actual):
            "Rename plan for ‘\(id)’ expects revision \(expected), but the document is at revision \(actual)."
        }
    }
}

/// Immutable, tool-neutral semantic services for one coherent project analysis.
public struct GrammarSemanticWorkspaceSnapshot: Hashable, Codable, Sendable {
    public let occurrences: [GrammarSemanticOccurrence]
    public let diagnostics: [GrammarSemanticWorkspaceDiagnostic]
    public let dependencies: [GrammarSemanticDependency]
    public let documentRevisions: [String: Int]
    private let caseSensitive: Bool
    private let renamePattern: String

    public func workspaceSymbols(matching query: String = "") -> [GrammarSemanticOccurrence] {
        let needle = normalized(query)
        return occurrences.filter {
            $0.role == .definition && (needle.isEmpty || normalized($0.name).contains(needle))
        }.sorted(by: Self.occurrenceOrder)
    }

    public func occurrence(documentID: String, atUTF16Offset offset: Int) -> GrammarSemanticOccurrence? {
        occurrences.filter {
            $0.location.documentID == documentID
                && $0.location.range.start.offset <= offset
                && offset < $0.location.range.end.offset
        }.min { lhs, rhs in
            let left = lhs.location.range.end.offset - lhs.location.range.start.offset
            let right = rhs.location.range.end.offset - rhs.location.range.start.offset
            return left < right
        }
    }

    public func definitions(of occurrence: GrammarSemanticOccurrence) -> [GrammarSemanticOccurrence] {
        matchingDefinitions(for: occurrence).sorted(by: Self.occurrenceOrder)
    }

    public func references(
        to occurrence: GrammarSemanticOccurrence,
        includeDefinition: Bool = true
    ) -> [GrammarSemanticOccurrence] {
        let definitions = matchingDefinitions(for: occurrence)
        guard definitions.count == 1 else { return [] }
        let definition = definitions[0]
        return occurrences.filter { candidate in
            guard candidate.kind == definition.kind,
                  normalized(candidate.name) == normalized(definition.name),
                  candidate.scope == definition.scope else { return false }
            return definition.scope == .workspace
                || candidate.location.documentID == definition.location.documentID
        }.filter { includeDefinition || $0.role == .reference }.sorted(by: Self.occurrenceOrder)
    }

    public func renamePlan(
        documentID: String, atUTF16Offset offset: Int, replacement: String
    ) throws -> GrammarSemanticRenamePlan {
        guard let target = occurrence(documentID: documentID, atUTF16Offset: offset) else {
            throw GrammarSemanticWorkspaceError.noSymbol
        }
        guard let expression = try? NSRegularExpression(pattern: renamePattern),
              expression.firstMatch(
                in: replacement, range: NSRange(location: 0, length: replacement.utf16.count)
              )?.range == NSRange(location: 0, length: replacement.utf16.count) else {
            throw GrammarSemanticWorkspaceError.invalidName(replacement)
        }
        let definitions = matchingDefinitions(for: target)
        guard !definitions.isEmpty else { throw GrammarSemanticWorkspaceError.unresolved(target.name) }
        guard definitions.count == 1 else { throw GrammarSemanticWorkspaceError.ambiguous(target.name) }
        let definition = definitions[0]
        let affected = references(to: definition)
        let collision = occurrences.contains { candidate in
            candidate.role == .definition && candidate.id != definition.id
                && candidate.kind == definition.kind
                && normalized(candidate.name) == normalized(replacement)
                && candidate.scope == definition.scope
                && (definition.scope == .workspace
                    || candidate.location.documentID == definition.location.documentID)
        }
        guard !collision else { throw GrammarSemanticWorkspaceError.nameCollision(replacement) }
        let grouped = Dictionary(grouping: affected, by: { $0.location.documentID })
        let documents = grouped.keys.sorted().compactMap { id -> GrammarSemanticWorkspaceDocumentEdit? in
            guard let values = grouped[id], let first = values.first else { return nil }
            let edits = values.sorted {
                $0.location.range.start.offset > $1.location.range.start.offset
            }.map {
                GrammarTextEdit(range: Self.textRange($0.location.range), replacement: replacement)
            }
            return .init(
                documentID: id, path: first.location.path,
                expectedRevision: first.location.revision, edits: edits
            )
        }
        return .init(
            symbolName: definition.name, replacement: replacement, kind: definition.kind,
            affectedOccurrences: affected.count, documents: documents
        )
    }

    static func build(
        analysis: GrammarProjectAnalysis, schema: GrammarSemanticWorkspaceSchema
    ) -> Self {
        let sources = Dictionary(uniqueKeysWithValues: analysis.manifest.sources.map { ($0.id, $0) })
        var occurrences: [GrammarSemanticOccurrence] = []
        for document in analysis.documents {
            guard let source = sources[document.documentID] else { continue }
            let index = document.semanticIndex
            for entry in index.entries where entry.isTerminal && !entry.isMissing {
                guard let lexeme = entry.lexeme, let tokenKind = entry.tokenKind,
                      let range = entry.range,
                      let ruleIndex = schema.rules.firstIndex(where: { rule in
                          rule.tokenKind == tokenKind
                              && (rule.enclosingProduction == nil
                                  || ancestors(of: entry, in: index).contains(rule.enclosingProduction!))
                      }) else { continue }
                let rule = schema.rules[ruleIndex]
                occurrences.append(.init(
                    id: "\(document.documentID):\(entry.id.rawValue):\(ruleIndex)",
                    name: lexeme, kind: rule.kind, role: rule.role, scope: rule.scope,
                    location: .init(
                        documentID: document.documentID, path: source.path,
                        revision: document.text.revision, range: range
                    ),
                    syntaxIdentity: entry.id
                ))
            }
        }
        occurrences.sort(by: occurrenceOrder)
        return assemble(
            occurrences: occurrences,
            revisions: Dictionary(uniqueKeysWithValues: analysis.documents.map {
                ($0.documentID, $0.text.revision)
            }),
            schema: schema
        )
    }

    private static func assemble(
        occurrences: [GrammarSemanticOccurrence], revisions: [String: Int],
        schema: GrammarSemanticWorkspaceSchema
    ) -> Self {
        func normalized(_ value: String) -> String { schema.caseSensitive ? value : value.lowercased() }
        func key(_ occurrence: GrammarSemanticOccurrence) -> String {
            let scope = occurrence.scope == .document ? occurrence.location.documentID : "*"
            return "\(occurrence.kind)\u{1f}\(normalized(occurrence.name))\u{1f}\(scope)"
        }
        let grouped = Dictionary(grouping: occurrences, by: key)
        var diagnostics: [GrammarSemanticWorkspaceDiagnostic] = []
        var edgeCounts: [String: Int] = [:]
        for values in grouped.values {
            let definitions = values.filter { $0.role == .definition }
            if definitions.count > 1 {
                diagnostics.append(contentsOf: definitions.map {
                    .init(id: "duplicate:\($0.id)", code: .duplicateDefinition,
                          message: "‘\($0.name)’ has \(definitions.count) definitions in this scope.",
                          location: $0.location)
                })
            }
            for reference in values where reference.role == .reference {
                if definitions.isEmpty {
                    diagnostics.append(.init(
                        id: "unresolved:\(reference.id)", code: .unresolvedReference,
                        message: "No definition of ‘\(reference.name)’ is visible.",
                        location: reference.location
                    ))
                } else if definitions.count > 1 {
                    diagnostics.append(.init(
                        id: "ambiguous:\(reference.id)", code: .ambiguousReference,
                        message: "‘\(reference.name)’ resolves to \(definitions.count) definitions.",
                        location: reference.location
                    ))
                } else if definitions[0].location.documentID != reference.location.documentID {
                    let edge = "\(reference.location.documentID)\u{1f}\(definitions[0].location.documentID)"
                    edgeCounts[edge, default: 0] += 1
                }
            }
        }
        let dependencies = edgeCounts.map { key, count in
            let components = key.split(separator: "\u{1f}", omittingEmptySubsequences: false)
            return GrammarSemanticDependency(
                sourceDocumentID: String(components[0]), targetDocumentID: String(components[1]),
                symbolCount: count
            )
        }.sorted { $0.id < $1.id }
        return .init(
            occurrences: occurrences, diagnostics: diagnostics.sorted { $0.id < $1.id },
            dependencies: dependencies, documentRevisions: revisions,
            caseSensitive: schema.caseSensitive, renamePattern: schema.renamePattern
        )
    }

    private static func ancestors(
        of entry: GrammarIncrementalIndexEntry, in index: GrammarIncrementalSemanticIndex
    ) -> [Int] {
        var result: [Int] = []
        var parent = entry.parentID
        while let id = parent, let value = index.entry(id: id) {
            if let production = value.production { result.append(production) }
            parent = value.parentID
        }
        return result
    }

    private func matchingDefinitions(
        for occurrence: GrammarSemanticOccurrence
    ) -> [GrammarSemanticOccurrence] {
        occurrences.filter {
            $0.role == .definition && $0.kind == occurrence.kind
                && normalized($0.name) == normalized(occurrence.name)
                && $0.scope == occurrence.scope
                && (occurrence.scope == .workspace
                    || $0.location.documentID == occurrence.location.documentID)
        }
    }

    private func normalized(_ value: String) -> String {
        caseSensitive ? value : value.lowercased()
    }

    private static func occurrenceOrder(
        _ lhs: GrammarSemanticOccurrence, _ rhs: GrammarSemanticOccurrence
    ) -> Bool {
        if lhs.location.path != rhs.location.path { return lhs.location.path < rhs.location.path }
        if lhs.location.range.start.offset != rhs.location.range.start.offset {
            return lhs.location.range.start.offset < rhs.location.range.start.offset
        }
        return lhs.id < rhs.id
    }

    private static func textRange(_ range: SourceRange) -> GrammarTextRange {
        .init(
            start: .init(line: max(0, range.start.line - 1), utf16Column: max(0, range.start.column - 1)),
            end: .init(line: max(0, range.end.line - 1), utf16Column: max(0, range.end.column - 1))
        )
    }
}

public extension GrammarProjectAnalysis {
    func semanticWorkspace(
        schema: GrammarSemanticWorkspaceSchema
    ) -> GrammarSemanticWorkspaceSnapshot {
        .build(analysis: self, schema: schema)
    }
}

public extension GrammarProjectWorkspace {
    func semanticWorkspace(
        schema: GrammarSemanticWorkspaceSchema
    ) async throws -> GrammarSemanticWorkspaceSnapshot {
        try await analyze().semanticWorkspace(schema: schema)
    }

    /// Applies a previously validated plan as one replacement source set. All
    /// expected revisions and text ranges are checked before workspace state is
    /// mutated, so stale multi-document renames cannot be partially applied.
    func applySemanticRename(
        _ plan: GrammarSemanticRenamePlan
    ) async throws -> GrammarProjectAnalysis {
        let current = projectManifest()
        let plans = Dictionary(uniqueKeysWithValues: plan.documents.map { ($0.documentID, $0) })
        var replacements = current.sources
        for index in replacements.indices {
            guard let document = plans[replacements[index].id] else { continue }
            guard replacements[index].revision == document.expectedRevision else {
                throw GrammarSemanticWorkspaceError.staleDocument(
                    documentID: document.documentID, expected: document.expectedRevision,
                    actual: replacements[index].revision
                )
            }
            let changed = try GrammarTextSnapshot(
                revision: replacements[index].revision, text: replacements[index].text
            ).applying(document.edits, revision: document.expectedRevision + 1).snapshot
            replacements[index].text = changed.text
            replacements[index].revision = changed.revision
        }
        for document in plan.documents where !replacements.contains(where: { $0.id == document.documentID }) {
            throw GrammarProjectError.unknownSource(document.documentID)
        }
        return try await replaceSources(replacements)
    }
}
