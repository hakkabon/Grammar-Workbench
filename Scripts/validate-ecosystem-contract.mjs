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

const corpusPath = join(root, manifest.corpus.path);
const schemaPath = join(root, manifest.corpus.schemaPath);
const convergencePath = join(root, manifest.corpus.lrConvergencePath ?? "");
if (!existsSync(corpusPath) || !existsSync(schemaPath) || !existsSync(convergencePath)) fail("corpus, schema, or LR convergence policy is missing");
const schema = JSON.parse(readFileSync(schemaPath, "utf8"));
const corpus = JSON.parse(readFileSync(corpusPath, "utf8"));
const convergence = JSON.parse(readFileSync(convergencePath, "utf8"));
if (schema.properties?.schemaVersion?.const !== manifest.corpus.version) fail("corpus schema version differs from manifest");
if (corpus.schemaVersion !== manifest.corpus.version || !Array.isArray(corpus.grammars) || corpus.grammars.length === 0 || !Array.isArray(corpus.cases) || corpus.cases.length === 0) fail("invalid corpus envelope");

const grammarIDs = new Set();
const grammars = new Map();
for (const grammar of corpus.grammars) {
  if (!/^[a-z0-9][a-z0-9-]*$/.test(grammar.id) || grammarIDs.has(grammar.id)) fail(`invalid or duplicate grammar id ${grammar.id}`);
  grammarIDs.add(grammar.id);
  grammars.set(grammar.id, grammar);
  if (!grammar.source.startsWith("Examples/Corpus/") || !grammar.source.endsWith(".grammar") || !existsSync(join(root, grammar.source))) fail(`missing source fixture for grammar ${grammar.id}`);
  if (typeof grammar.start !== "string" || !Array.isArray(grammar.terminals) || grammar.terminals.length === 0 || new Set(grammar.terminals).size !== grammar.terminals.length) fail(`invalid terminals for grammar ${grammar.id}`);
  if (!Array.isArray(grammar.precedence)) fail(`invalid precedence for grammar ${grammar.id}`);
  if (!Array.isArray(grammar.productions) || grammar.productions.length === 0) fail(`grammar ${grammar.id} has no productions`);
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
  if (!Array.isArray(testCase.tags) || testCase.tags.length === 0 || new Set(testCase.tags).size !== testCase.tags.length) fail(`invalid tags for ${testCase.id}`);
}

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
      const shouldSucceed = testCase.expectedStatus === "accepted" || testCase.expectedStatus === "acceptedWithRecovery";
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

console.log(`Ecosystem contract valid: ${manifest.repositories.length} pinned repositories, ${corpus.grammars.length} grammars, ${corpus.cases.length} corpus cases${cliIndex >= 0 ? ", Workbench conformant" : ""}${lrIndex >= 0 ? ", LR convergence recorded" : ""}${compilerIndex >= 0 ? ", Compiler corpus coverage recorded" : ""}.`);
