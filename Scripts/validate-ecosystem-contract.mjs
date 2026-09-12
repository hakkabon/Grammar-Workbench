#!/usr/bin/env node

import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = resolve(fileURLToPath(new URL("..", import.meta.url)));
const manifestPath = join(root, "Packaging/EcosystemCompatibility.json");
const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
const fail = message => { throw new Error(message); };

if (manifest.schemaVersion !== 1 || !/^0\.\d+\.\d+$/.test(manifest.contractVersion)) fail("unsupported ecosystem manifest");
if (!/^\d+\.\d+$/.test(manifest.swiftIntegrationVersion)) fail("invalid Swift integration version");
if (!Array.isArray(manifest.repositories) || manifest.repositories.length < 6) fail("ecosystem repositories are incomplete");

const experiments = manifest.grammarREPLExperiments;
if (experiments?.schemaVersion !== 1 ||
    experiments.minimumGrammarREPLVersion !== "0.5.0" ||
    experiments.fingerprintAlgorithm !== "fnv1a64" ||
    experiments.verifierProduct !== "grammar-repl-experiment" ||
    experiments.explorerProjectionVersion !== 1) {
  fail("invalid Grammar-REPL experiment capability");
}

const names = new Set();
for (const repository of manifest.repositories) {
  if (names.has(repository.name)) fail(`duplicate repository ${repository.name}`);
  names.add(repository.name);
  if (!/^https:\/\/github\.com\/hakkabon\/[A-Za-z0-9-]+\.git$/.test(repository.repository)) fail(`invalid repository URL for ${repository.name}`);
  if (!/^[0-9a-f]{40}$/.test(repository.revision)) fail(`revision for ${repository.name} is not a full commit`);
  if (!/^\d+\.\d+\.\d+$/.test(repository.version)) fail(`invalid release version for ${repository.name}`);
  if (repository.swiftVersion !== undefined && !/^\d+\.\d+$/.test(repository.swiftVersion)) fail(`invalid Swift version for ${repository.name}`);
  if (!["pinned", "conformance", "pending-adapter"].includes(repository.adoption)) fail(`invalid adoption state for ${repository.name}`);
}
for (const required of ["Grammar", "Parser", "LR-Parsing", "Compiler", "Grammar-REPL", "Grammar-Workbench"]) {
  if (!names.has(required)) fail(`missing repository ${required}`);
}
const grammarREPL = manifest.repositories.find(repository => repository.name === "Grammar-REPL");
if (grammarREPL.version !== experiments.minimumGrammarREPLVersion) fail("Grammar-REPL experiment version differs from repository pin");

const boundaryPath = join(root, manifest.dependencyBoundaries?.path ?? "");
const boundarySchemaPath = join(root, manifest.dependencyBoundaries?.schemaPath ?? "");
if (!existsSync(boundaryPath) || !existsSync(boundarySchemaPath)) fail("dependency boundary policy or schema is missing");
const boundaryPolicy = JSON.parse(readFileSync(boundaryPath, "utf8"));
const boundarySchema = JSON.parse(readFileSync(boundarySchemaPath, "utf8"));
if (boundarySchema.properties?.schemaVersion?.const !== manifest.dependencyBoundaries.version || boundaryPolicy.schemaVersion !== manifest.dependencyBoundaries.version) fail("dependency boundary version differs from manifest");
const auditedBoundaryNames = new Set(boundaryPolicy.packages?.filter(entry => entry.audited).map(entry => entry.name));
if (auditedBoundaryNames.size !== names.size || [...names].some(name => !auditedBoundaryNames.has(name))) fail("dependency boundary scope differs from compatibility repositories");

const corpusPath = join(root, manifest.corpus.path);
const schemaPath = join(root, manifest.corpus.schemaPath);
const convergencePath = join(root, manifest.corpus.lrConvergencePath ?? "");
if (!existsSync(corpusPath) || !existsSync(schemaPath) || !existsSync(convergencePath)) fail("corpus, schema, or LR convergence policy is missing");
const schema = JSON.parse(readFileSync(schemaPath, "utf8"));
const corpus = JSON.parse(readFileSync(corpusPath, "utf8"));
const convergence = JSON.parse(readFileSync(convergencePath, "utf8"));
if (schema.properties?.schemaVersion?.const !== manifest.corpus.version) fail("corpus schema version differs from manifest");
if (corpus.schemaVersion !== manifest.corpus.version || !Array.isArray(corpus.grammars) || corpus.grammars.length < 4 || !Array.isArray(corpus.cases) || corpus.cases.length < 45) fail("invalid corpus envelope");

const expectedEngines = new Set([
  "earley", "earley-sl", "earley-el", "cyk", "rnglr", "ll1",
  "lr0", "slr", "lalr", "lr1",
]);
if (!Array.isArray(corpus.engines) || corpus.engines.length !== expectedEngines.size) fail("invalid parser engine catalog");
const engineIDs = new Set();
for (const engine of corpus.engines) {
  if (!expectedEngines.has(engine.id) || engineIDs.has(engine.id)) fail(`invalid or duplicate parser engine ${engine.id}`);
  engineIDs.add(engine.id);
  if (!["generalized", "deterministic"].includes(engine.family)) fail(`invalid family for parser engine ${engine.id}`);
  if (!Array.isArray(engine.requires) || new Set(engine.requires).size !== engine.requires.length || engine.requires.some(capability => capability !== "ll1")) fail(`invalid capability requirements for ${engine.id}`);
  if (engine.family === "generalized" && (engine.forest !== "portable" || engine.replay !== "forestTraversal")) fail(`invalid generalized capabilities for ${engine.id}`);
  if (engine.family === "deterministic" && (engine.forest !== "none" || !["runtimeTrace", "tokenTrace"].includes(engine.replay))) fail(`invalid deterministic capabilities for ${engine.id}`);
  if ((engine.id === "ll1") !== (engine.requires.length === 1 && engine.requires[0] === "ll1")) fail(`invalid LL(1) capability declaration for ${engine.id}`);
}

const grammarIDs = new Set();
const grammars = new Map();
for (const grammar of corpus.grammars) {
  if (!/^[a-z0-9][a-z0-9-]*$/.test(grammar.id) || grammarIDs.has(grammar.id)) fail(`invalid or duplicate grammar id ${grammar.id}`);
  grammarIDs.add(grammar.id);
  grammars.set(grammar.id, grammar);
  if (!grammar.source.startsWith("Examples/Corpus/") || !grammar.source.endsWith(".grammar") || !existsSync(join(root, grammar.source))) fail(`missing source fixture for grammar ${grammar.id}`);
  if (typeof grammar.start !== "string" || !Array.isArray(grammar.terminals) || grammar.terminals.length === 0 || new Set(grammar.terminals).size !== grammar.terminals.length) fail(`invalid terminals for grammar ${grammar.id}`);
  if (!Array.isArray(grammar.capabilities) || new Set(grammar.capabilities).size !== grammar.capabilities.length || grammar.capabilities.some(capability => capability !== "ll1")) fail(`invalid capabilities for grammar ${grammar.id}`);
  if (!Array.isArray(grammar.precedence)) fail(`invalid precedence for grammar ${grammar.id}`);
  if (!Array.isArray(grammar.productions) || grammar.productions.length === 0) fail(`grammar ${grammar.id} has no productions`);
  const productionIDs = new Set();
  const nonterminals = new Set(grammar.productions.map(production => production.lhs));
  const terminals = new Set(grammar.terminals);
  const precedenceTerminals = new Set();
  for (const level of grammar.precedence) {
    if (!["left", "right", "nonAssociative"].includes(level.associativity) || !Array.isArray(level.terminals) || level.terminals.length === 0) fail(`invalid precedence level for grammar ${grammar.id}`);
    for (const terminal of level.terminals) {
      if (!terminals.has(terminal) || precedenceTerminals.has(terminal)) fail(`invalid precedence terminal ${terminal} in grammar ${grammar.id}`);
      precedenceTerminals.add(terminal);
    }
  }
  if (!nonterminals.has(grammar.start)) fail(`start symbol is not defined for grammar ${grammar.id}`);
  for (const production of grammar.productions) {
    if (!/^[a-z0-9][a-z0-9-]*$/.test(production.id) || productionIDs.has(production.id)) fail(`invalid or duplicate production id ${production.id} in grammar ${grammar.id}`);
    productionIDs.add(production.id);
    if (typeof production.lhs !== "string" || production.lhs.length === 0 || !Array.isArray(production.rhs)) fail(`invalid production in grammar ${grammar.id}`);
    if (terminals.has(production.lhs)) fail(`terminal ${production.lhs} appears on the left side in grammar ${grammar.id}`);
    for (const symbol of production.rhs) {
      if (!terminals.has(symbol) && !nonterminals.has(symbol)) fail(`undefined symbol ${symbol} in grammar ${grammar.id}`);
    }
  }
}

const caseIDs = new Set();
const statuses = new Set(["accepted", "acceptedWithRecovery", "rejected", "lexicalError"]);
for (const testCase of corpus.cases) {
  if (!/^[a-z0-9][a-z0-9-]*$/.test(testCase.id) || caseIDs.has(testCase.id)) fail(`invalid or duplicate case id ${testCase.id}`);
  caseIDs.add(testCase.id);
  const grammar = grammars.get(testCase.grammar);
  if (!grammar) fail(`unknown grammar ${testCase.grammar} for ${testCase.id}`);
  if (typeof testCase.input !== "string" || !statuses.has(testCase.expectedStatus)) fail(`invalid expectation for ${testCase.id}`);
  if (!Array.isArray(testCase.expectedTokenKinds) || testCase.expectedTokenKinds.some(kind => !grammar.terminals.includes(kind))) fail(`invalid expected tokens for ${testCase.id}`);
  const succeeds = testCase.expectedStatus === "accepted" || testCase.expectedStatus === "acceptedWithRecovery";
  if ((typeof testCase.expectedRoot === "string") !== succeeds) fail(`invalid expected root for ${testCase.id}`);
  if (succeeds && testCase.expectedRoot !== grammar.start) fail(`expected root is not the start symbol for ${testCase.id}`);
  if (typeof testCase.expectedAmbiguous !== "boolean") fail(`missing ambiguity expectation for ${testCase.id}`);
  if (testCase.expectedDiagnostic !== null) {
    const diagnostic = testCase.expectedDiagnostic;
    if (!Number.isInteger(diagnostic.tokenIndex) || diagnostic.tokenIndex < 0 || typeof diagnostic.unexpected !== "string") fail(`invalid diagnostic position for ${testCase.id}`);
    if (!Array.isArray(diagnostic.expectedTerminals) || diagnostic.expectedTerminals.length === 0 || new Set(diagnostic.expectedTerminals).size !== diagnostic.expectedTerminals.length || diagnostic.expectedTerminals.some(symbol => !grammar.terminals.includes(symbol))) fail(`invalid diagnostic expectation for ${testCase.id}`);
  } else if (testCase.expectedStatus === "rejected" || testCase.expectedStatus === "acceptedWithRecovery") {
    fail(`missing diagnostic expectation for ${testCase.id}`);
  }
  if (testCase.expectedRecovery !== null) {
    const recovery = testCase.expectedRecovery;
    if (testCase.expectedStatus !== "acceptedWithRecovery" || !["insert", "delete"].includes(recovery.kind) || !grammar.terminals.includes(recovery.terminal) || !Number.isInteger(recovery.tokenIndex) || recovery.tokenIndex < 0) fail(`invalid recovery expectation for ${testCase.id}`);
  } else if (testCase.expectedStatus === "acceptedWithRecovery") {
    fail(`missing recovery expectation for ${testCase.id}`);
  }
  if (!Array.isArray(testCase.tags) || testCase.tags.length === 0 || new Set(testCase.tags).size !== testCase.tags.length) fail(`invalid tags for ${testCase.id}`);
  const isComparison = testCase.tags.includes("engine-comparison");
  if (isComparison !== (testCase.expectedReplay !== undefined && testCase.expectedForest !== undefined)) fail(`engine comparison expectations are incomplete for ${testCase.id}`);
  if (isComparison) {
    const replay = testCase.expectedReplay;
    const forest = testCase.expectedForest;
    const expectedTerminal = succeeds ? "accept" : "reject";
    if (replay.terminal !== expectedTerminal || !Array.isArray(replay.requiredEvents) || !replay.requiredEvents.includes("start") || !replay.requiredEvents.includes(expectedTerminal)) fail(`invalid replay envelope for ${testCase.id}`);
    if (!Array.isArray(replay.productionIDs) || replay.productionIDs.some(id => !grammar.productions.some(production => production.id === id))) fail(`invalid replay production identity for ${testCase.id}`);
    if (!Number.isInteger(forest.generalizedDerivations) || forest.generalizedDerivations < 1 || forest.ambiguous !== testCase.expectedAmbiguous || forest.productionIdentity !== "required") fail(`invalid forest expectation for ${testCase.id}`);
    if ((forest.generalizedDerivations > 1) !== forest.ambiguous) fail(`derivation count and ambiguity disagree for ${testCase.id}`);
    if (!Array.isArray(forest.acceptedDifferences)) fail(`missing accepted engine differences for ${testCase.id}`);
    if (forest.acceptedDifferences.length !== 0) fail(`${testCase.id}: engine-truthfulness baseline permits no accepted engine differences`);
    const differenceEngines = new Set();
    for (const difference of forest.acceptedDifferences) {
      if (!expectedEngines.has(difference.engine) || differenceEngines.has(difference.engine) || !statuses.has(difference.status) || difference.status === testCase.expectedStatus || typeof difference.reason !== "string" || difference.reason.length < 20) fail(`invalid accepted engine difference for ${testCase.id}`);
      differenceEngines.add(difference.engine);
    }
  }
}

const taggedCases = tag => corpus.cases.filter(testCase => testCase.tags.includes(tag));
if (taggedCases("engine-comparison").length < 10) fail("corpus has insufficient engine-comparison coverage");
if (taggedCases("stress").length < 8) fail("corpus has insufficient bounded stress coverage");
if (!["accepted", "acceptedWithRecovery", "rejected"].every(status => corpus.cases.some(testCase => testCase.expectedStatus === status))) fail("corpus does not cover every supported outcome class");
if ([...grammarIDs].some(id => !corpus.cases.some(testCase => testCase.grammar === id))) fail("corpus contains an unexercised grammar");
const comparisonDerivations = new Set(taggedCases("engine-comparison").map(testCase => testCase.expectedForest.generalizedDerivations));
for (const count of [1, 2, 5, 14, 42]) {
  if (!comparisonDerivations.has(count)) fail(`corpus omits generalized derivation probe ${count}`);
}
const comparisonCapabilityClasses = new Set(taggedCases("engine-comparison").map(testCase => grammars.get(testCase.grammar).capabilities.includes("ll1")));
if (!comparisonCapabilityClasses.has(true) || !comparisonCapabilityClasses.has(false)) fail("corpus does not exercise both supported and unsupported LL(1) grammar classes");

if (convergence.schemaVersion !== corpus.schemaVersion || convergence.algorithm !== "lalr" || !Array.isArray(convergence.acceptedDifferences)) fail("invalid LR convergence policy");
const acceptedLRDifferences = new Map();
for (const difference of convergence.acceptedDifferences) {
  if (!caseIDs.has(difference.case)) fail(`accepted LR difference references unknown case ${difference.case}`);
  if (acceptedLRDifferences.has(difference.case)) fail("duplicate accepted LR difference");
  if (!statuses.has(difference.workbenchStatus) || !statuses.has(difference.lrParsingStatus) || difference.workbenchStatus === difference.lrParsingStatus) fail(`invalid accepted LR statuses for ${difference.case}`);
  if (typeof difference.reason !== "string" || difference.reason.length < 20) fail(`missing accepted LR rationale for ${difference.case}`);
  acceptedLRDifferences.set(difference.case, difference);
}

const cliIndex = process.argv.indexOf("--cli");
if (cliIndex >= 0) {
  const cli = process.argv[cliIndex + 1];
  if (!cli) fail("--cli requires a path");
  const work = mkdtempSync(join(tmpdir(), "grammar-ecosystem-"));
  try {
    for (const testCase of corpus.cases) {
      const output = join(work, `${testCase.id}.json`);
      const grammar = grammars.get(testCase.grammar);
      const result = spawnSync(resolve(cli), ["parse", join(root, grammar.source), testCase.input, output], { encoding: "utf8" });
      if (!existsSync(output)) fail(`${testCase.id}: adapter produced no result (${result.stderr.trim()})`);
      const parsed = JSON.parse(readFileSync(output, "utf8"));
      if (parsed.status !== testCase.expectedStatus) fail(`${testCase.id}: expected ${testCase.expectedStatus}, got ${parsed.status}`);
      const tokenKinds = parsed.tokens?.map(token => token.kind);
      if (JSON.stringify(tokenKinds) !== JSON.stringify(testCase.expectedTokenKinds)) fail(`${testCase.id}: normalized token kinds disagree`);
      if ((parsed.syntaxTree?.symbol ?? null) !== testCase.expectedRoot) fail(`${testCase.id}: normalized tree root disagrees`);
      const firstDiagnostic = parsed.diagnostics?.[0] ?? null;
      if (testCase.expectedDiagnostic === null) {
        if (firstDiagnostic !== null) fail(`${testCase.id}: unexpected diagnostic`);
      } else {
        if (!firstDiagnostic) fail(`${testCase.id}: expected diagnostic was omitted`);
        if (firstDiagnostic.tokenIndex !== testCase.expectedDiagnostic.tokenIndex || firstDiagnostic.unexpected !== testCase.expectedDiagnostic.unexpected || JSON.stringify(firstDiagnostic.expected) !== JSON.stringify(testCase.expectedDiagnostic.expectedTerminals)) fail(`${testCase.id}: normalized diagnostic disagrees`);
      }
      if (testCase.expectedRecovery !== null) {
        const expectedKind = testCase.expectedRecovery.kind === "insert" ? "insertedToken" : "deletedToken";
        if (firstDiagnostic?.recovery !== expectedKind || firstDiagnostic?.recoverySymbol !== testCase.expectedRecovery.terminal || firstDiagnostic?.tokenIndex !== testCase.expectedRecovery.tokenIndex) fail(`${testCase.id}: normalized recovery disagrees`);
      }
      const shouldSucceed = testCase.expectedStatus === "accepted" || testCase.expectedStatus === "acceptedWithRecovery";
      if (testCase.expectedReplay !== undefined) {
        const events = new Set(["start"]);
        const productionIDs = [];
        for (const frame of parsed.trace ?? []) {
          if (frame.action === "accept") events.add("accept");
          else if (frame.action.startsWith("shift")) events.add("consume");
          else if (frame.action.startsWith("reduce")) events.add("applyProduction");
          else if (frame.action.startsWith("recover")) events.add("recover");
          else if (frame.action.startsWith("error")) events.add("reject");
          if (Number.isInteger(frame.production)) productionIDs.push(grammar.productions[frame.production - 1]?.id);
        }
        const terminal = shouldSucceed ? "accept" : "reject";
        if (terminal !== testCase.expectedReplay.terminal || testCase.expectedReplay.requiredEvents.some(event => !events.has(event))) fail(`${testCase.id}: Workbench replay milestones disagree`);
        if (JSON.stringify(productionIDs) !== JSON.stringify(testCase.expectedReplay.productionIDs)) fail(`${testCase.id}: Workbench replay production sequence disagrees`);
      }
      if ((result.status === 0) !== shouldSucceed) fail(`${testCase.id}: exit status disagrees with normalized status`);
    }
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

const lrIndex = process.argv.indexOf("--lr-adapter");
if (lrIndex >= 0) {
  const adapter = process.argv[lrIndex + 1];
  if (!adapter) fail("--lr-adapter requires a path");
  const work = mkdtempSync(join(tmpdir(), "grammar-lr-convergence-"));
  try {
    const output = join(work, "lr-observations.json");
    const result = spawnSync(resolve(adapter), [corpusPath, output], { encoding: "utf8" });
    if (result.status !== 0 || !existsSync(output)) fail(`LR adapter failed: ${result.stderr.trim()}`);
    const observations = JSON.parse(readFileSync(output, "utf8"));
    const byID = new Map(observations.map(item => [item.id, item]));
    if (byID.size !== corpus.cases.length) fail("LR adapter did not report every corpus case exactly once");
    for (const testCase of corpus.cases) {
      const observed = byID.get(testCase.id);
      if (!observed) fail(`LR adapter omitted ${testCase.id}`);
      if ((observed.root ?? null) !== testCase.expectedRoot && observed.status === testCase.expectedStatus) fail(`${testCase.id}: LR-Parsing tree root disagrees`);
      if (testCase.expectedReplay !== undefined) {
        if (!observed.replay || observed.replay.terminal !== testCase.expectedReplay.terminal) fail(`${testCase.id}: LR-Parsing replay terminal disagrees`);
        if (testCase.expectedReplay.requiredEvents.some(event => !observed.replay.events.includes(event))) fail(`${testCase.id}: LR-Parsing replay milestones disagree`);
        if (JSON.stringify(observed.replay.productionIDs) !== JSON.stringify(testCase.expectedReplay.productionIDs)) fail(`${testCase.id}: LR-Parsing replay production sequence disagrees`);
      }
      const difference = acceptedLRDifferences.get(testCase.id);
      if (observed.status === testCase.expectedStatus) {
        if (difference) fail(`accepted LR difference for ${testCase.id} is stale`);
      } else if (!difference || difference.workbenchStatus !== testCase.expectedStatus || difference.lrParsingStatus !== observed.status || typeof difference.reason !== "string" || difference.reason.length < 20) {
        fail(`${testCase.id}: Workbench ${testCase.expectedStatus}, LR-Parsing ${observed.status}`);
      }
    }
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

const compilerIndex = process.argv.indexOf("--compiler-adapter");
if (compilerIndex >= 0) {
  const adapter = process.argv[compilerIndex + 1];
  if (!adapter) fail("--compiler-adapter requires a path");
  const work = mkdtempSync(join(tmpdir(), "grammar-compiler-conformance-"));
  try {
    const output = join(work, "compiler-observations.json");
    const result = spawnSync(resolve(adapter), [corpusPath, output], { encoding: "utf8" });
    if (result.status !== 0 || !existsSync(output)) fail(`Compiler adapter failed: ${result.stderr.trim()}`);
    const observations = JSON.parse(readFileSync(output, "utf8"));
    if (!Array.isArray(observations)) fail("Compiler adapter result is not an array");
    const byID = new Map(observations.map(item => [item.id, item]));
    if (observations.length !== corpus.cases.length || byID.size !== corpus.cases.length) {
      fail("Compiler adapter did not report every corpus case exactly once");
    }
    for (const testCase of corpus.cases) {
      const observed = byID.get(testCase.id);
      if (!observed) fail(`Compiler adapter omitted ${testCase.id}`);
      if (!statuses.has(observed.status)) fail(`${testCase.id}: Compiler emitted invalid status ${observed.status}`);
      if (typeof observed.supported !== "boolean") fail(`${testCase.id}: Compiler omitted its support decision`);
      if (!Number.isInteger(observed.diagnostics) || observed.diagnostics < 0) fail(`${testCase.id}: Compiler emitted an invalid diagnostic count`);
      if (observed.supported) {
        if (observed.status !== testCase.expectedStatus) {
          fail(`${testCase.id}: expected ${testCase.expectedStatus}, Compiler reported ${observed.status}`);
        }
        if (observed.reason !== undefined) fail(`${testCase.id}: supported Compiler result carries an unsupported reason`);
        if ((observed.root ?? null) !== testCase.expectedRoot) fail(`${testCase.id}: Compiler tree root disagrees`);
      } else {
        if (testCase.expectedStatus !== "acceptedWithRecovery" || !testCase.tags.includes("recovery")) {
          fail(`${testCase.id}: Compiler marked a required capability unsupported`);
        }
        if (typeof observed.reason !== "string" || observed.reason.length < 20) fail(`${testCase.id}: Compiler unsupported result has no rationale`);
      }
    }
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

const grammarREPLIndex = process.argv.indexOf("--grammar-repl-adapter");
if (grammarREPLIndex >= 0) {
  const adapter = process.argv[grammarREPLIndex + 1];
  if (!adapter) fail("--grammar-repl-adapter requires a path");
  const work = mkdtempSync(join(tmpdir(), "grammar-repl-conformance-"));
  try {
    const output = join(work, "grammar-repl-observations.json");
    const result = spawnSync(resolve(adapter), [corpusPath, output], { encoding: "utf8" });
    if (result.status !== 0 || !existsSync(output)) fail(`Grammar-REPL adapter failed: ${result.stderr.trim()}`);
    const observations = JSON.parse(readFileSync(output, "utf8"));
    if (!Array.isArray(observations)) fail("Grammar-REPL adapter result is not an array");
    const byID = new Map(observations.map(item => [item.id, item]));
    if (observations.length !== corpus.cases.length || byID.size !== corpus.cases.length) {
      fail("Grammar-REPL adapter did not report every corpus case exactly once");
    }
    for (const testCase of corpus.cases) {
      const observed = byID.get(testCase.id);
      const grammar = grammars.get(testCase.grammar);
      if (!observed) fail(`Grammar-REPL adapter omitted ${testCase.id}`);
      if (!statuses.has(observed.status)) fail(`${testCase.id}: Grammar-REPL emitted invalid status ${observed.status}`);
      if (!Number.isInteger(observed.diagnostics) || observed.diagnostics < 0) fail(`${testCase.id}: Grammar-REPL emitted an invalid diagnostic count`);
      if (!Number.isInteger(observed.recoveryEdits) || observed.recoveryEdits < 0) fail(`${testCase.id}: Grammar-REPL emitted an invalid recovery edit count`);
      if (observed.status !== testCase.expectedStatus) {
        fail(`${testCase.id}: expected ${testCase.expectedStatus}, Grammar-REPL reported ${observed.status}`);
      }
      if ((observed.root ?? null) !== testCase.expectedRoot) fail(`${testCase.id}: Grammar-REPL tree root disagrees`);
      if (observed.status === "accepted" && (observed.diagnostics !== 0 || observed.recoveryEdits !== 0)) {
        fail(`${testCase.id}: clean Grammar-REPL acceptance reported diagnostics or recovery edits`);
      }
      if (observed.status === "acceptedWithRecovery" && (observed.diagnostics === 0 || observed.recoveryEdits === 0)) {
        fail(`${testCase.id}: Grammar-REPL recovery omitted diagnostics or edits`);
      }
      if (testCase.expectedForest !== undefined) {
        if (!Array.isArray(observed.engines) || observed.engines.length !== corpus.engines.length) fail(`${testCase.id}: Grammar-REPL engine comparison is incomplete`);
        const engines = new Map(observed.engines.map(engine => [engine.parser, engine]));
        if (engines.size !== corpus.engines.length) fail(`${testCase.id}: Grammar-REPL engine comparison contains duplicates`);
        for (const descriptor of corpus.engines) {
          const engine = engines.get(descriptor.id);
          if (!engine) fail(`${testCase.id}: ${descriptor.id} result is missing`);
          const supported = descriptor.requires.every(capability => grammar.capabilities.includes(capability));
          if (engine.supported !== supported) fail(`${testCase.id}: ${descriptor.id} capability decision disagrees`);
          if (!supported) {
            if (engine.status !== "rejected" || engine.derivations !== 0 || (engine.forestNodes ?? null) !== null || (engine.ambiguous ?? null) !== null || typeof engine.unsupportedReason !== "string" || engine.unsupportedReason.length < 20) fail(`${testCase.id}: ${descriptor.id} unsupported evidence disagrees`);
            if (!engine.replayEvents.includes("start") || !engine.replayEvents.includes("reject")) fail(`${testCase.id}: ${descriptor.id} unsupported replay disagrees`);
            continue;
          }
          if (engine.unsupportedReason != null) fail(`${testCase.id}: ${descriptor.id} supported result carries an unsupported reason`);
          const difference = testCase.expectedForest.acceptedDifferences.find(item => item.engine === descriptor.id);
          const expectedStatus = difference?.status ?? testCase.expectedStatus;
          if (engine.status !== expectedStatus) fail(`${testCase.id}: ${descriptor.id} acceptance disagrees`);
          const requiredEvents = difference
            ? ["start", expectedStatus === "rejected" ? "reject" : "accept"]
            : testCase.expectedReplay.requiredEvents.filter(event => descriptor.replay !== "tokenTrace" || event !== "applyProduction");
          if (requiredEvents.some(event => !engine.replayEvents.includes(event))) fail(`${testCase.id}: ${descriptor.id} replay milestones disagree`);
          if (descriptor.family === "generalized" && expectedStatus === "accepted") {
            if (engine.derivations !== testCase.expectedForest.generalizedDerivations || engine.ambiguous !== testCase.expectedForest.ambiguous || !Number.isInteger(engine.forestNodes) || engine.forestNodes < 1 || engine.productionIdentified !== true) fail(`${testCase.id}: ${descriptor.id} forest evidence disagrees`);
          } else if (descriptor.family === "generalized") {
            if (engine.derivations !== 0 || (engine.forestNodes ?? null) !== null || (engine.ambiguous ?? null) !== null) fail(`${testCase.id}: ${descriptor.id} rejected evidence disagrees`);
          } else if (engine.derivations !== 1 || (engine.forestNodes ?? null) !== null || (engine.ambiguous ?? null) !== null) {
            fail(`${testCase.id}: ${descriptor.id} deterministic evidence disagrees`);
          }
        }
      }
    }
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

console.log(`Ecosystem contract valid: ${manifest.repositories.length} pinned repositories, ${corpus.grammars.length} grammars, ${corpus.cases.length} corpus cases${cliIndex >= 0 ? ", Workbench conformant" : ""}${lrIndex >= 0 ? ", LR convergence recorded" : ""}${compilerIndex >= 0 ? ", Compiler corpus coverage recorded" : ""}${grammarREPLIndex >= 0 ? ", Grammar-REPL conformant" : ""}.`);
