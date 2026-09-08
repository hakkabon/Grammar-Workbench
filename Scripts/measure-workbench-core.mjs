#!/usr/bin/env node

import { createHash } from "node:crypto";
import { mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const defaultPlan = join(root, "Validation/CoreSeparation/Plan.json");
const defaultBaseline = join(root, "Validation/CoreSeparation/Baseline.json");

function fail(message) {
  console.error(`WorkbenchCore measurement failed: ${message}`);
  process.exit(1);
}

function option(name) {
  const index = process.argv.indexOf(name);
  if (index < 0) return undefined;
  const value = process.argv[index + 1];
  if (!value || value.startsWith("--")) fail(`${name} requires a value`);
  return value;
}

const planPath = resolve(option("--plan") ?? defaultPlan);
const baselinePath = resolve(option("--baseline") ?? defaultBaseline);
const reportPath = option("--report");
const shouldCheck = process.argv.includes("--check");
const shouldBuild = process.argv.includes("--build");
const scratchPath = resolve(option("--scratch-path") ?? join(root, ".build/core-separation-measurement"));
const buildJobs = option("--jobs") ?? process.env.SWIFT_BUILD_JOBS ?? "2";
if (!/^[1-9][0-9]*$/.test(buildJobs)) fail("--jobs must be a positive integer");
const knownOptions = new Set([
  "--plan", "--baseline", "--report", "--scratch-path", "--jobs", "--check", "--build"
]);
for (let index = 2; index < process.argv.length; index += 1) {
  const argument = process.argv[index];
  if (!knownOptions.has(argument)) fail(`unknown option ${argument}`);
  if (argument !== "--check" && argument !== "--build") index += 1;
}

const planBytes = readFileSync(planPath);
const plan = JSON.parse(planBytes);
if (plan.schemaVersion !== 1 || typeof plan.planVersion !== "string"
    || typeof plan.sourceDirectory !== "string" || !plan.classifications) {
  fail("invalid plan envelope");
}

const portable = plan.classifications.portable;
const native = plan.classifications.native;
const mixed = plan.classifications.mixed;
if (!Array.isArray(portable) || !Array.isArray(native) || !Array.isArray(mixed)
    || !mixed.every(item => typeof item.path === "string" && typeof item.reason === "string")) {
  fail("invalid source classifications");
}

const sourceDirectory = resolve(root, plan.sourceDirectory);
const actualPaths = readdirSync(sourceDirectory)
  .filter(path => path.endsWith(".swift"))
  .sort();
const classifiedPaths = [
  ...portable,
  ...native,
  ...mixed.map(item => item.path)
];
const uniquePaths = new Set(classifiedPaths);
if (uniquePaths.size !== classifiedPaths.length) fail("a source is classified more than once");
const unclassified = actualPaths.filter(path => !uniquePaths.has(path));
const missing = classifiedPaths.filter(path => !actualPaths.includes(path));
if (unclassified.length || missing.length) {
  fail(`classification drift${unclassified.length ? `; unclassified ${unclassified.join(", ")}` : ""}${missing.length ? `; missing ${missing.join(", ")}` : ""}`);
}

const nativeFrameworks = new Set(plan.nativeFrameworks ?? []);
const publicDeclarationPattern = /^\s*public\s+(?:(?:final|indirect|nonisolated|static|class)\s+)*(?:struct|class|enum|actor|protocol|typealias|func|var|let|subscript|init|extension)\b/gm;
const importPattern = /^\s*(?:@_exported\s+)?import\s+([A-Za-z_][A-Za-z0-9_]*)/gm;

function measureSource(path, category, reason) {
  const absolutePath = join(sourceDirectory, path);
  const source = readFileSync(absolutePath, "utf8");
  const imports = [...source.matchAll(importPattern)].map(match => match[1]);
  const nativeImports = imports.filter(module => nativeFrameworks.has(module));
  if (category === "portable" && nativeImports.length) {
    fail(`${path} is classified portable but imports ${nativeImports.join(", ")}`);
  }
  if ((category === "native" || category === "mixed") && nativeImports.length === 0) {
    fail(`${path} is classified ${category} but has no reviewed native-framework import`);
  }
  return {
    path,
    category,
    ...(reason ? { reason } : {}),
    bytes: statSync(absolutePath).size,
    lines: source.length === 0 ? 0 : source.split("\n").length - (source.endsWith("\n") ? 1 : 0),
    nonblankLines: source.split("\n").filter(line => line.trim().length > 0).length,
    publicDeclarations: [...source.matchAll(publicDeclarationPattern)].length,
    imports: [...new Set(imports)].sort(),
    nativeImports: [...new Set(nativeImports)].sort(),
    conditionalCompilationDirectives: (source.match(/^\s*#(?:if|elseif|else|endif)\b/gm) ?? []).length
  };
}

const mixedReasons = new Map(mixed.map(item => [item.path, item.reason]));
const categoryByPath = new Map([
  ...portable.map(path => [path, "portable"]),
  ...native.map(path => [path, "native"]),
  ...mixed.map(item => [item.path, "mixed"])
]);
const sources = actualPaths.map(path => measureSource(path, categoryByPath.get(path), mixedReasons.get(path)));

function totals(items) {
  return {
    files: items.length,
    bytes: items.reduce((sum, item) => sum + item.bytes, 0),
    lines: items.reduce((sum, item) => sum + item.lines, 0),
    nonblankLines: items.reduce((sum, item) => sum + item.nonblankLines, 0),
    publicDeclarations: items.reduce((sum, item) => sum + item.publicDeclarations, 0)
  };
}

const packageManifest = readFileSync(join(root, "Package.swift"), "utf8");
const coreFacade = readFileSync(join(root, "Sources/GrammarWorkbenchCore/GrammarWorkbenchCore.swift"), "utf8");
const resourcesDirectory = join(sourceDirectory, "Resources");
const resourcePaths = readdirSync(resourcesDirectory).sort();
const resourceBytes = resourcePaths.reduce((sum, path) => sum + statSync(join(resourcesDirectory, path)).size, 0);
const categories = Object.fromEntries(["portable", "native", "mixed"].map(category => [
  category,
  totals(sources.filter(item => item.category === category))
]));
const allTotals = totals(sources);

const report = {
  schemaVersion: 1,
  planVersion: plan.planVersion,
  planSHA256: createHash("sha256").update(planBytes).digest("hex"),
  state: {
    facadeTarget: plan.facadeTarget,
    implementationTarget: plan.implementationTarget,
    facadeReexportsImplementation: coreFacade.includes(`@_exported import ${plan.implementationTarget}`),
    facadeDependsOnImplementation: new RegExp(`name:\\s*"${plan.facadeTarget}"[^\\n]*dependencies:\\s*\\["${plan.implementationTarget}"\\]`).test(packageManifest),
    physicallySeparated: false
  },
  totals: allTotals,
  categories,
  candidatePortablePercent: Number((categories.portable.lines * 100 / allTotals.lines).toFixed(2)),
  extractionQueue: mixed.map(item => ({ path: item.path, reason: item.reason })),
  nativeFrameworkImports: [...new Set(sources.flatMap(item => item.nativeImports))].sort(),
  resources: { files: resourcePaths.length, bytes: resourceBytes },
  sourceMetricsSHA256: createHash("sha256").update(JSON.stringify(sources)).digest("hex"),
  sources
};

if (!report.state.facadeReexportsImplementation || !report.state.facadeDependsOnImplementation) {
  fail("the pre-split façade relationship no longer matches the measurement plan");
}

if (shouldBuild) {
  const started = process.hrtime.bigint();
  const build = spawnSync("swift", [
    "build", "--package-path", root, "--scratch-path", scratchPath,
    "--target", plan.facadeTarget, "--jobs", buildJobs
  ], { encoding: "utf8" });
  const durationMilliseconds = Number(process.hrtime.bigint() - started) / 1_000_000;
  if (build.status !== 0) {
    process.stderr.write(build.stdout ?? "");
    process.stderr.write(build.stderr ?? "");
    fail(`build observation exited with status ${build.status}`);
  }
  const swiftVersion = spawnSync("swift", ["--version"], { encoding: "utf8" });
  report.buildObservation = {
    target: plan.facadeTarget,
    configuration: "debug",
    jobs: Number(buildJobs),
    scratchPath,
    durationMilliseconds: Number(durationMilliseconds.toFixed(2)),
    platform: process.platform,
    architecture: process.arch,
    swiftVersion: (swiftVersion.stdout ?? "").trim()
  };
}

const serialized = `${JSON.stringify(report, null, 2)}\n`;
if (reportPath) {
  const resolvedReport = resolve(reportPath);
  mkdirSync(dirname(resolvedReport), { recursive: true });
  writeFileSync(resolvedReport, serialized);
}

if (shouldCheck) {
  const baseline = JSON.parse(readFileSync(baselinePath, "utf8"));
  const { sources: _, buildObservation: __, ...baselineMeasurement } = report;
  if (JSON.stringify(baseline) !== JSON.stringify(baselineMeasurement)) {
    fail(`baseline differs; inspect with --report and review the separation plan before updating ${baselinePath}`);
  }
  console.log(`WorkbenchCore pre-split baseline valid: ${allTotals.files} sources, ${allTotals.lines} lines, ${categories.mixed.files} mixed files.`);
} else if (!reportPath) {
  process.stdout.write(serialized);
}
