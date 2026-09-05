#!/usr/bin/env node

import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const defaultPolicy = join(root, "Validation/Ecosystem/DependencyBoundaries.json");

function fail(message) {
  console.error(`Dependency boundary audit failed: ${message}`);
  process.exit(1);
}

function option(name) {
  const index = process.argv.indexOf(name);
  return index < 0 ? undefined : process.argv[index + 1];
}

const policyPath = resolve(option("--policy") ?? defaultPolicy);
const reportPath = option("--report");
const packageArguments = [];
for (let index = 2; index < process.argv.length; index += 1) {
  if (process.argv[index] !== "--package") continue;
  const value = process.argv[index + 1];
  if (!value || !value.includes("=")) fail("--package must use NAME=PATH");
  const separator = value.indexOf("=");
  packageArguments.push({ name: value.slice(0, separator), path: value.slice(separator + 1) });
  index += 1;
}
if (packageArguments.length === 0) {
  packageArguments.push({ name: "Grammar-Workbench", path: root });
}

const policyBytes = readFileSync(policyPath);
const policy = JSON.parse(policyBytes);
if (policy.schemaVersion !== 1 || !Array.isArray(policy.packages) || !Array.isArray(policy.allowedRequirementKinds)) fail("invalid policy envelope");

const byName = new Map();
const byIdentity = new Map();
for (const entry of policy.packages) {
  if (typeof entry.name !== "string" || typeof entry.identity !== "string" || !Number.isInteger(entry.layer) || !["ecosystem", "external"].includes(entry.kind) || typeof entry.audited !== "boolean") fail("invalid package policy entry");
  if (byName.has(entry.name) || byIdentity.has(entry.identity)) fail(`duplicate package policy entry ${entry.name}`);
  if (entry.audited && (!Array.isArray(entry.allowedDependencies) || new Set(entry.allowedDependencies).size !== entry.allowedDependencies.length)) fail(`invalid allowlist for ${entry.name}`);
  byName.set(entry.name, entry);
  byIdentity.set(entry.identity, entry);
}
for (const entry of policy.packages) {
  for (const dependency of entry.allowedDependencies ?? []) {
    if (!byIdentity.has(dependency)) fail(`${entry.name} allows unknown dependency ${dependency}`);
  }
}

const requestedNames = new Set();
const observations = [];
for (const request of packageArguments) {
  if (requestedNames.has(request.name)) fail(`duplicate --package ${request.name}`);
  requestedNames.add(request.name);
  const boundary = byName.get(request.name);
  if (!boundary?.audited) fail(`${request.name} is not an audited package`);
  const packagePath = isAbsolute(request.path) ? request.path : resolve(request.path);
  const dumped = spawnSync("swift", ["package", "dump-package", "--package-path", packagePath], { encoding: "utf8" });
  if (dumped.status !== 0) fail(`${request.name} manifest could not be evaluated: ${dumped.stderr.trim()}`);
  const manifest = JSON.parse(dumped.stdout);
  if (manifest.name !== boundary.manifestName) fail(`${request.name} manifest declares package ${manifest.name}`);

  const dependencies = [];
  const identities = new Set();
  for (const encoded of manifest.dependencies ?? []) {
    const source = encoded.sourceControl?.[0];
    if (!source) fail(`${request.name} uses a local or unsupported package dependency`);
    const identity = source.identity;
    if (identities.has(identity)) fail(`${request.name} declares ${identity} more than once`);
    identities.add(identity);
    const dependency = byIdentity.get(identity);
    if (!dependency) fail(`${request.name} depends on unclassified package ${identity}`);
    if (!boundary.allowedDependencies.includes(identity)) fail(`${request.name} is not allowed to depend on ${dependency.name}`);
    const requirementKinds = Object.keys(source.requirement ?? {});
    if (requirementKinds.length !== 1 || !policy.allowedRequirementKinds.includes(requirementKinds[0])) fail(`${request.name} uses mutable or unsupported requirement for ${dependency.name}`);
    if (dependency.kind === "ecosystem" && dependency.layer >= boundary.layer) fail(`${request.name} has a reverse or lateral dependency on ${dependency.name}`);
    dependencies.push({ identity, name: dependency.name, kind: dependency.kind, requirement: requirementKinds[0] });
  }

  const actual = [...identities].sort();
  const expected = [...boundary.allowedDependencies].sort();
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    const missing = expected.filter(identity => !identities.has(identity));
    fail(`${request.name} dependency allowlist is stale${missing.length ? `; missing ${missing.join(", ")}` : ""}`);
  }
  observations.push({ name: request.name, identity: boundary.identity, owner: boundary.owner, layer: boundary.layer, dependencies });
}

const report = {
  schemaVersion: 1,
  policyVersion: policy.policyVersion,
  policySHA256: createHash("sha256").update(policyBytes).digest("hex"),
  packages: observations,
  result: "passed"
};
if (reportPath) {
  const resolvedReport = resolve(reportPath);
  mkdirSync(dirname(resolvedReport), { recursive: true });
  writeFileSync(resolvedReport, `${JSON.stringify(report, null, 2)}\n`);
}
console.log(`Dependency boundaries valid: ${observations.length} package${observations.length === 1 ? "" : "s"}, ${observations.reduce((count, item) => count + item.dependencies.length, 0)} direct dependencies.`);
