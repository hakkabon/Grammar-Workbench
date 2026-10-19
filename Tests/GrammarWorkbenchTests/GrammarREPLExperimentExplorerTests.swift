import Foundation
import Testing
@testable import GrammarWorkbenchCore
#if os(macOS)
@testable import GrammarWorkbench
#endif

private func experimentData(invalidEdge: Bool = false, schemaVersion: Int = 1) throws -> Data {
    func observation(_ parser: String, derivations: Int) -> [String: Any] {
        let root = "\(parser)-root"
        let packed = "\(parser)-packed"
        let token = "\(parser)-token"
        return [
            "parser": parser,
            "availability": "supported",
            "contract": [
                "schemaVersion": 1,
                "engine": ["identity": parser, "displayName": parser.uppercased(), "algorithm": parser],
                "status": "accepted",
                "tree": NSNull(),
                "forest": [
                    "schemaVersion": 1,
                    "nodes": [
                        ["id": root, "kind": "symbol", "label": "S", "leftExtent": 0, "rightExtent": 1],
                        ["id": packed, "kind": "packed", "productionID": "p1", "position": 1, "leftExtent": 0, "rightExtent": 1, "pivot": 0],
                        ["id": token, "kind": "token", "label": "a", "leftExtent": 0, "rightExtent": 1],
                    ],
                    "edges": [
                        ["parent": root, "child": packed],
                        ["parent": packed, "child": invalidEdge && parser == "earley" ? "missing" : token],
                    ],
                    "roots": [root],
                    "ambiguityNodes": [],
                ],
                "diagnostics": [],
                "recoveryEdits": [],
                "replay": [
                    ["step": 0, "kind": "start"],
                    ["step": 1, "kind": "inspect", "forestNodeID": root],
                    ["step": 2, "kind": "accept", "forestNodeID": root],
                ],
            ],
            "treeFingerprints": (0..<derivations).map { "tree-\($0)" },
        ]
    }

    let value: [String: Any] = [
        "schemaVersion": schemaVersion,
        "producer": ["name": "Grammar-REPL", "version": "0.5.0"],
        "grammar": ["start": ["name": "S"], "productions": [["goal": ["name": "S"], "rule": []]]],
        "input": "a",
        "engines": ["earley", "cyk"],
        "precedence": [
            "levels": [["level": 1, "associativity": "left", "terminals": []]],
            "productionOverrides": [],
        ],
        "resolutionPolicy": NSNull(),
        "agreement": "acceptanceOnly",
        "observations": [observation("earley", derivations: 1), observation("cyk", derivations: 2)],
        "fingerprintAlgorithm": "fnv1a64",
        "fingerprint": "0123456789abcdef",
    ]
    return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
}

private func experimentProjectData(
    fingerprint: String = "fedcba9876543210",
    duplicateID: Bool = false
) throws -> Data {
    let experiment = try #require(
        JSONSerialization.jsonObject(with: experimentData(schemaVersion: 3)) as? [String: Any]
    )
    var second = experiment
    second["input"] = "b"
    second["fingerprint"] = "1111111111111111"
    let entries: [[String: Any]] = [
        [
            "id": "accepts-a", "title": "Accepted input", "tags": ["accepted", "baseline"],
            "experiment": experiment,
        ],
        [
            "id": duplicateID ? "accepts-a" : "rejects-b", "title": "Rejected input",
            "tags": ["negative"], "experiment": second,
        ],
    ]
    return try JSONSerialization.data(withJSONObject: [
        "schemaVersion": 1,
        "producer": ["name": "Grammar-REPL", "version": "0.9.0"],
        "name": "Acceptance study",
        "description": "Compare accepted and rejected inputs.",
        "experiments": entries,
        "fingerprintAlgorithm": "fnv1a64",
        "fingerprint": fingerprint,
    ], options: [.sortedKeys])
}

@Suite("Grammar-REPL experiment explorer")
struct GrammarREPLExperimentExplorerTests {
    @Test("Experiment projects preserve named evidence without claiming verification")
    func decodesExperimentProjects() throws {
        let project = try GrammarREPLExperimentProjectArtifact.decode(experimentProjectData())
        #expect(project.name == "Acceptance study")
        #expect(project.experiments.map(\.id) == ["accepts-a", "rejects-b"])
        #expect(project.totalEngines == 4)
        #expect(project.experiment(id: "accepts-a")?.tags == ["accepted", "baseline"])
        let report = GrammarREPLExperimentProjectExplorerReport(project)
        #expect(report.experimentCount == 2)
        #expect(report.fingerprintStatus == "recorded-requires-grammar-repl-verification")
        if case .project(let imported) = try GrammarREPLExperimentImport.decode(experimentProjectData()) {
            #expect(imported.fingerprint == project.fingerprint)
        } else {
            Issue.record("Expected project import")
        }
        #expect(throws: GrammarResearchNotebookError.self) {
            try GrammarREPLExperimentProjectArtifact.decode(experimentProjectData(duplicateID: true))
        }
    }

    @Test("Research notebooks are deterministic narratives over immutable evidence")
    func researchNotebookRoundTripAndResolution() throws {
        let project = try GrammarREPLExperimentProjectArtifact.decode(experimentProjectData())
        let empty = try GrammarResearchNotebook.create(
            title: "Acceptance notebook",
            researchQuestion: "Do engines agree on the acceptance boundary?",
            project: project
        )
        let withNote = try empty.adding(.init(
            id: "context", kind: .note, title: "Context",
            body: "The project contains one positive and one negative input."
        ))
        let notebook = try withNote.adding(.init(
            id: "accepted-evidence", kind: .evidence, title: "Accepted case",
            body: "Inspect the generalized and deterministic evidence.",
            experimentID: "accepts-a", selectedEngines: ["earley", "cyk"]
        ))
        let decoded = try GrammarResearchNotebook.decode(notebook.json())
        let recreated = try GrammarResearchNotebook.create(
            title: "Acceptance notebook",
            researchQuestion: "Do engines agree on the acceptance boundary?",
            project: project,
            cells: notebook.cells
        )

        #expect(decoded == notebook)
        #expect(recreated.fingerprint == notebook.fingerprint)
        #expect(decoded.resolve(against: project).isResolved)
        #expect(GrammarResearchNotebookExplorerReport(decoded, project: project).evidenceCellCount == 1)
    }

    @Test("Notebook tampering and stale project evidence fail visibly")
    func notebookTamperAndStaleEvidence() throws {
        let project = try GrammarREPLExperimentProjectArtifact.decode(experimentProjectData())
        let notebook = try GrammarResearchNotebook.create(
            title: "Evidence notebook", researchQuestion: "Is evidence stable?", project: project
        ).adding(.init(
            id: "evidence", kind: .evidence, title: "Baseline", body: "Recorded result.",
            experimentID: "accepts-a", selectedEngines: []
        ))
        var object = try #require(
            JSONSerialization.jsonObject(with: notebook.json()) as? [String: Any]
        )
        object["title"] = "Changed title"
        #expect(throws: GrammarResearchNotebookError.self) {
            try GrammarResearchNotebook.decode(JSONSerialization.data(withJSONObject: object))
        }

        let changedProject = try GrammarREPLExperimentProjectArtifact.decode(
            experimentProjectData(fingerprint: "2222222222222222")
        )
        let resolution = notebook.resolve(against: changedProject)
        #expect(!resolution.projectMatches)
        #expect(!resolution.isResolved)
    }

    @Test("Published notebook schema tracks the executable codec")
    func notebookSchemaAlignment() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent(
            "Validation/Research/ResearchNotebook.schema.json"
        ))
        let schema = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try #require(schema["properties"] as? [String: Any])
        let version = try #require(properties["schemaVersion"] as? [String: Any])
        let kind = try #require(properties["kind"] as? [String: Any])
        let fingerprint = try #require(properties["fingerprintAlgorithm"] as? [String: Any])
        #expect(version["const"] as? Int == GrammarResearchNotebook.currentSchemaVersion)
        #expect(kind["const"] as? String == GrammarResearchNotebook.kindIdentifier)
        #expect(fingerprint["const"] as? String == GrammarResearchNotebook.fingerprintAlgorithm)
    }

    @Test("Schema-one artifacts become bounded comparison summaries")
    func decodesSummaryAndEngineDelta() throws {
        let artifact = try GrammarREPLExperimentArtifact.decode(experimentData())
        #expect(artifact.engines == ["earley", "cyk"])
        #expect(artifact.summary.engineCount == 2)
        #expect(artifact.summary.supportedEngineCount == 2)
        #expect(artifact.summary.acceptedEngineCount == 2)
        #expect(artifact.summary.maximumDerivationCount == 2)
        #expect(artifact.summary.maximumForestNodeCount == 3)
        #expect(artifact.summary.replayEventCount == 6)
        let report = GrammarREPLExperimentExplorerReport(artifact)
        #expect(report.engines.count == 2)
        #expect(report.fingerprintStatus == "recorded-requires-grammar-repl-verification")

        let baseline = try #require(artifact.observation(for: "earley"))
        let candidate = try #require(artifact.observation(for: "cyk"))
        let delta = GrammarREPLExperimentEngineDelta(baseline: baseline, candidate: candidate)
        #expect(!delta.agrees)
        #expect(delta.differences == [.derivationCount])
    }

    @Test("Portable forests project into collapsible Workbench graphs")
    func projectsAndCollapsesForest() throws {
        let artifact = try GrammarREPLExperimentArtifact.decode(experimentData())
        let observation = try #require(artifact.observation(for: "earley"))
        let forest = try #require(observation.contract.forest)
        let complete = GrammarREPLExperimentForestProjection.project(forest, parser: "earley")
        #expect(complete.graph.nodes.count == 3)
        #expect(complete.graph.edges.count == 2)

        let root = try #require(forest.roots.first)
        let collapsed = GrammarREPLExperimentForestProjection.project(
            forest, parser: "earley", collapsedNodeIDs: [root]
        )
        #expect(collapsed.graph.nodes.count == 1)
        #expect(collapsed.hiddenNodeCount == 2)
        #expect(collapsed.graph.nodes.first?.metadata["collapsed"] == "true")
    }

    @Test("Playback clamps and forest corruption fails closed")
    func playbackAndValidation() throws {
        var playback = GrammarREPLExperimentPlaybackState(step: 99)
        playback.seek(to: 99, eventCount: 3)
        #expect(playback.step == 2)
        playback.stepForward(eventCount: 3)
        #expect(playback.step == 2)
        playback.stepBackward(eventCount: 3)
        #expect(playback.step == 1)
        playback.toggleCollapsed("root")
        #expect(playback.collapsedNodeIDs == ["root"])

        #expect(throws: GrammarREPLExperimentExplorerError.self) {
            try GrammarREPLExperimentArtifact.decode(experimentData(invalidEdge: true))
        }
        #expect(throws: GrammarREPLExperimentExplorerError.self) {
            try GrammarREPLExperimentArtifact.decode(experimentData(schemaVersion: 4))
        }
    }

    @Test("Schema-two projects Compiler-owned semantic evidence")
    func projectsSemanticConvergenceWithoutEvaluation() throws {
        var root = try #require(
            JSONSerialization.jsonObject(with: experimentData(schemaVersion: 2)) as? [String: Any]
        )
        root["producer"] = ["name": "Grammar-REPL", "version": "0.6.0"]
        root["semanticMapping"] = ["version": 1, "actions": [:]]
        root["semanticReport"] = [
            "schemaVersion": 1,
            "agreement": "complete",
            "observations": ["earley", "cyk"].map { engine in
                [
                    "engine": engine,
                    "status": "evaluated",
                    "derivationCount": 1,
                    "values": [["kind": "integer", "integer": 42]],
                    "diagnostics": [],
                ] as [String: Any]
            },
        ] as [String: Any]
        let artifact = try GrammarREPLExperimentArtifact.decode(
            JSONSerialization.data(withJSONObject: root)
        )

        #expect(artifact.semanticReport?.agreement == .complete)
        #expect(artifact.summary.semanticEvaluatedEngineCount == 2)
        #expect(artifact.semanticObservation(for: "earley")?.values.first?.displayValue == "42")
        let report = GrammarREPLExperimentExplorerReport(artifact)
        #expect(report.engines.first?.semanticValues == ["42"])
    }

    @Test("Schema-three preserves ambiguity-aware derivation semantics")
    func projectsAmbiguityAwareSemanticEvidence() throws {
        var root = try #require(
            JSONSerialization.jsonObject(with: experimentData(schemaVersion: 3)) as? [String: Any]
        )
        root["producer"] = ["name": "Grammar-REPL", "version": "0.8.0"]
        root["semanticMapping"] = ["version": 1, "actions": [:]]
        func value(_ integer: Int) -> [String: Any] {
            ["kind": "integer", "integer": integer]
        }
        func derivation(_ index: Int, _ fingerprint: String, _ integer: Int) -> [String: Any] {
            [
                "index": index,
                "syntaxFingerprint": fingerprint,
                "value": value(integer),
            ]
        }
        root["semanticReport"] = [
            "schemaVersion": 2,
            "agreement": "divergent",
            "ambiguity": "semanticallyDivergent",
            "observations": [
                [
                    "engine": "earley", "status": "evaluated", "derivationCount": 2,
                    "values": [value(3), value(7)], "diagnostics": [],
                    "ambiguity": "semanticallyDivergent",
                    "derivations": [
                        derivation(0, "1111111111111111", 3),
                        derivation(1, "2222222222222222", 7),
                    ],
                ],
                [
                    "engine": "cyk", "status": "evaluated", "derivationCount": 1,
                    "values": [value(3)], "diagnostics": [],
                    "ambiguity": "syntacticallyUnambiguous",
                    "derivations": [derivation(0, "3333333333333333", 3)],
                ],
            ],
        ] as [String: Any]
        let artifact = try GrammarREPLExperimentArtifact.decode(
            JSONSerialization.data(withJSONObject: root)
        )

        #expect(artifact.semanticReport?.agreement == .divergent)
        #expect(artifact.summary.semanticAmbiguity == .semanticallyDivergent)
        #expect(artifact.semanticObservation(for: "earley")?.derivations?.count == 2)
        #expect(artifact.semanticObservation(for: "earley")?.values.map(\.displayValue) == ["3", "7"])
        let report = GrammarREPLExperimentExplorerReport(artifact)
        #expect(report.engines.first?.semanticAmbiguity == .semanticallyDivergent)
        #expect(report.engines.first?.semanticDerivations == 2)
    }

    @Test("Explorer never presents a recorded fingerprint as verification")
    func ownershipBoundaryIsExplicit() throws {
        let artifact = try GrammarREPLExperimentArtifact.decode(experimentData())
        #expect(artifact.fingerprint == "0123456789abcdef")
        #expect(GrammarREPLExperimentArtifact.supportedFingerprintAlgorithm == "fnv1a64")
        // Semantic verification intentionally remains in `grammar-repl-experiment verify`.
    }

    #if os(macOS)
    @Test("Native store selects an explorable forest and resets replay")
    @MainActor
    func nativeStoreImport() throws {
        let store = ExplorerStore()
        try store.importExperiment(experimentData(), name: "comparison.json")
        #expect(store.experimentName == "comparison.json")
        #expect(store.experimentBaselineEngine == "earley")
        #expect(store.experimentSelectedEngine == "earley")
        store.seekExperimentReplay(to: 2)
        #expect(store.experimentPlayback.step == 2)
        store.selectExperimentEngine("cyk")
        #expect(store.experimentPlayback.step == 0)
    }

    @Test("Native store navigates projects and builds a notebook")
    @MainActor
    func nativeNotebookWorkflow() throws {
        let store = ExplorerStore()
        try store.importExperiment(experimentProjectData(), name: "study.json")
        #expect(store.experimentProject?.experiments.count == 2)
        #expect(store.experimentProjectSelectedID == "accepts-a")
        store.selectExperimentProjectEntry("rejects-b")
        #expect(store.experimentArtifact?.input == "b")
        try store.createResearchNotebook(
            title: "Study notes", question: "Where do the engines disagree?"
        )
        try store.addResearchNotebookCell(
            id: "rejected", kind: .evidence, title: "Rejected case",
            body: "The negative boundary is retained.", selectedEngines: ["cyk"]
        )
        #expect(store.researchNotebook?.cells.first?.experimentID == "rejects-b")
        #expect(store.researchNotebookResolution?.isResolved == true)
        let saved = try store.researchNotebookData()
        #expect(try GrammarResearchNotebook.decode(saved).cells.count == 1)

        let reopened = ExplorerStore()
        try reopened.importExperiment(experimentProjectData(), name: "study.json")
        try reopened.importResearchNotebook(saved)
        #expect(reopened.researchNotebook?.cells.count == 1)
        #expect(reopened.researchNotebookResolution?.isResolved == true)
    }
    #endif

    @Test("Single-event generalized rejection remains inspectable")
    func acceptsOwnedTerminalOnlyReplay() throws {
        var root = try #require(
            JSONSerialization.jsonObject(with: experimentData()) as? [String: Any]
        )
        var observations = try #require(root["observations"] as? [[String: Any]])
        var cyk = observations[1]
        var contract = try #require(cyk["contract"] as? [String: Any])
        contract["status"] = "rejected"
        contract["forest"] = NSNull()
        contract["replay"] = [["step": 0, "kind": "reject"]]
        cyk["contract"] = contract
        observations[1] = cyk
        root["observations"] = observations
        let data = try JSONSerialization.data(withJSONObject: root)

        let artifact = try GrammarREPLExperimentArtifact.decode(data)
        #expect(artifact.observation(for: "cyk")?.contract.replay == [
            .init(step: 0, kind: .reject, tokenIndex: nil, productionID: nil, forestNodeID: nil, diagnosticReason: nil)
        ])
    }

    @Test("Rejected deterministic contracts may omit portable replay")
    func acceptsOwnedEmptyRejectedReplay() throws {
        var root = try #require(
            JSONSerialization.jsonObject(with: experimentData()) as? [String: Any]
        )
        var observations = try #require(root["observations"] as? [[String: Any]])
        var cyk = observations[1]
        var contract = try #require(cyk["contract"] as? [String: Any])
        contract["status"] = "rejected"
        contract["forest"] = NSNull()
        contract["replay"] = []
        cyk["contract"] = contract
        observations[1] = cyk
        root["observations"] = observations
        let data = try JSONSerialization.data(withJSONObject: root)

        let artifact = try GrammarREPLExperimentArtifact.decode(data)
        #expect(artifact.observation(for: "cyk")?.contract.replay.isEmpty == true)
    }
}
