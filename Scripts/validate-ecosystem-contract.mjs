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

if (manifest.schemaVersion !== 1 || manifest.contractVersion !== "0.1.0") fail("unsupported ecosystem manifest");
if (!/^\d+\.\d+$/.test(manifest.swiftIntegrationVersion)) fail("invalid Swift integration version");
if (!Array.isArray(manifest.repositories) || manifest.repositories.length < 6) fail("ecosystem repositories are incomplete");

const names = new Set();
for (const repository of manifest.repositories) {
  if (names.has(repository.name)) fail(`duplicate repository ${repository.name}`);
  names.add(repository.name);
  if (!/^https:\/\/github\.com\/hakkabon\/[A-Za-z0-9-]+\.git$/.test(repository.repository)) fail(`invalid repository URL for ${repository.name}`);
  if (!/^[0-9a-f]{40}$/.test(repository.revision)) fail(`revision for ${repository.name} is not a full commit`);
  if (!["pinned", "conformance", "pending-adapter"].includes(repository.adoption)) fail(`invalid adoption state for ${repository.name}`);
}
for (const required of ["Grammar", "Parser", "LR-Parsing", "Compiler", "Grammar-REPL", "Grammar-Workbench"]) {
  if (!names.has(required)) fail(`missing repository ${required}`);
}

const corpusPath = join(root, manifest.corpus.path);
const schemaPath = join(root, manifest.corpus.schemaPath);
if (!existsSync(corpusPath) || !existsSync(schemaPath)) fail("corpus or schema is missing");
const schema = JSON.parse(readFileSync(schemaPath, "utf8"));
const corpus = JSON.parse(readFileSync(corpusPath, "utf8"));
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
  if (!Array.isArray(grammar.productions) || grammar.productions.length === 0) fail(`grammar ${grammar.id} has no productions`);
  const nonterminals = new Set(grammar.productions.map(production => production.lhs));
  const terminals = new Set(grammar.terminals);
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

console.log(`Ecosystem contract valid: ${manifest.repositories.length} pinned repositories, ${corpus.grammars.length} grammars, ${corpus.cases.length} corpus cases${cliIndex >= 0 ? ", Workbench conformant" : ""}.`);
