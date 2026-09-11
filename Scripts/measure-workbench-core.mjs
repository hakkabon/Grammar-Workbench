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
if (plan.schemaVersion !== 2 || typeof plan.planVersion !== "string"
    || typeof plan.coreSourceDirectory !== "string"
    || typeof plan.nativeSourceDirectory !== "string"
    || typeof plan.coreTarget !== "string" || typeof plan.facadeTarget !== "string"
    || !plan.classifications) {
  fail("invalid physical-separation plan envelope");
}

const core = plan.classifications.core;
const native = plan.classifications.native;
const mixed = plan.classifications.mixed;
if (!Array.isArray(core) || !Array.isArray(native) || !Array.isArray(mixed) || mixed.length !== 0) {
  fail("the physical separation plan requires complete core/native ownership and an empty mixed queue");
}

const coreDirectory = resolve(root, plan.coreSourceDirectory);
const nativeDirectory = resolve(root, plan.nativeSourceDirectory);
const swiftFiles = directory => readdirSync(directory).filter(path => path.endsWith(".swift")).sort();
const actualCore = swiftFiles(coreDirectory);
const actualNative = swiftFiles(nativeDirectory);
const duplicates = core.filter(path => native.includes(path));
const missingCore = core.filter(path => !actualCore.includes(path));
const missingNative = native.filter(path => !actualNative.includes(path));
const unexpectedCore = actualCore.filter(path => !core.includes(path));
const unexpectedNative = actualNative.filter(path => !native.includes(path));
if (duplicates.length || missingCore.length || missingNative.length || unexpectedCore.length || unexpectedNative.length) {
  fail(`ownership drift${duplicates.length ? `; duplicate ${duplicates.join(", ")}` : ""}${missingCore.length ? `; missing core ${missingCore.join(", ")}` : ""}${missingNative.length ? `; missing native ${missingNative.join(", ")}` : ""}${unexpectedCore.length ? `; unexpected core ${unexpectedCore.join(", ")}` : ""}${unexpectedNative.length ? `; unexpected native ${unexpectedNative.join(", ")}` : ""}`);
}

const nativeFrameworks = new Set(plan.nativeFrameworks ?? []);
const publicDeclarationPattern = /^\s*public\s+(?:(?:final|indirect|nonisolated|static|class)\s+)*(?:struct|class|enum|actor|protocol|typealias|func|var|let|subscript|init|extension)\b/gm;
const packageDeclarationPattern = /^\s*package\s+(?:(?:final|indirect|nonisolated|static|class)\s+)*(?:struct|class|enum|actor|protocol|typealias|func|var|let|subscript|init|extension)\b/gm;
const importPattern = /^(?:@_exported\s+)?import\s+([A-Za-z_][A-Za-z0-9_]*)/gm;

function measureSource(directory, directoryName, path, category) {
  const absolutePath = join(directory, path);
  const source = readFileSync(absolutePath, "utf8");
  const imports = [...source.matchAll(importPattern)].map(match => match[1]);
  const nativeImports = imports.filter(module => nativeFrameworks.has(module));
  if (category === "core" && nativeImports.length) {
    fail(`${path} is core-owned but imports ${nativeImports.join(", ")}`);
  }
  if (category === "native" && path !== "GrammarWorkbench.swift" && nativeImports.length === 0) {
    fail(`${path} is native-owned but has no reviewed native-framework import`);
  }
  return {
    path: join(directoryName, path),
    category,
    bytes: statSync(absolutePath).size,
    lines: source.length === 0 ? 0 : source.split("\n").length - (source.endsWith("\n") ? 1 : 0),
    nonblankLines: source.split("\n").filter(line => line.trim().length > 0).length,
    publicDeclarations: [...source.matchAll(publicDeclarationPattern)].length,
    packageDeclarations: [...source.matchAll(packageDeclarationPattern)].length,
    imports: [...new Set(imports)].sort(),
    nativeImports: [...new Set(nativeImports)].sort(),
    conditionalCompilationDirectives: (source.match(/^\s*#(?:if|elseif|else|endif)\b/gm) ?? []).length
  };
}

const sources = [
  ...actualCore.map(path => measureSource(coreDirectory, plan.coreSourceDirectory, path, "core")),
  ...actualNative.map(path => measureSource(nativeDirectory, plan.nativeSourceDirectory, path, "native"))
];

function totals(items) {
  return {
    files: items.length,
    bytes: items.reduce((sum, item) => sum + item.bytes, 0),
    lines: items.reduce((sum, item) => sum + item.lines, 0),
    nonblankLines: items.reduce((sum, item) => sum + item.nonblankLines, 0),
    publicDeclarations: items.reduce((sum, item) => sum + item.publicDeclarations, 0),
    packageDeclarations: items.reduce((sum, item) => sum + item.packageDeclarations, 0)
  };
}

const packageManifest = readFileSync(join(root, "Package.swift"), "utf8");
const facadeSource = readFileSync(join(nativeDirectory, "GrammarWorkbench.swift"), "utf8");
const coreSources = sources.filter(item => item.category === "core");
const nativeSources = sources.filter(item => item.category === "native");
const coreImportsFacade = coreSources.some(item => item.imports.includes(plan.facadeTarget));
const facadeReexportsCore = facadeSource.includes(`@_exported import ${plan.coreTarget}`);
const facadeDependsOnCore = new RegExp(
  `name:\\s*"${plan.facadeTarget}"[\\s\\S]{0,500}?dependencies:\\s*\\[[\\s\\S]{0,300}?"${plan.coreTarget}"`
).test(packageManifest);
const resourcesDirectory = join(coreDirectory, "Resources");
const resourcePaths = readdirSync(resourcesDirectory).sort();
const resourceBytes = resourcePaths.reduce((sum, path) => sum + statSync(join(resourcesDirectory, path)).size, 0);
const allTotals = totals(sources);
const categories = { core: totals(coreSources), native: totals(nativeSources) };

const report = {
  schemaVersion: 2,
  planVersion: plan.planVersion,
  planSHA256: createHash("sha256").update(planBytes).digest("hex"),
  state: {
    coreTarget: plan.coreTarget,
    facadeTarget: plan.facadeTarget,
    facadeReexportsCore,
    facadeDependsOnCore,
    coreDependsOnFacade: coreImportsFacade,
    physicallySeparated: facadeReexportsCore && facadeDependsOnCore && !coreImportsFacade
  },
  totals: allTotals,
  categories,
  corePercent: Number((categories.core.lines * 100 / allTotals.lines).toFixed(2)),
  extractionQueue: [],
  nativeFrameworkImports: [...new Set(nativeSources.flatMap(item => item.nativeImports))].sort(),
  resources: { owner: plan.coreTarget, files: resourcePaths.length, bytes: resourceBytes },
  sourceMetricsSHA256: createHash("sha256").update(JSON.stringify(sources)).digest("hex"),
  sources
};

if (!report.state.physicallySeparated) {
  fail("the Core/facade dependency direction does not match the physical separation plan");
}

if (shouldBuild) {
  const started = process.hrtime.bigint();
  const build = spawnSync("swift", [
    "build", "--package-path", root, "--scratch-path", scratchPath,
    "--target", plan.coreTarget, "--jobs", buildJobs
  ], { encoding: "utf8" });
  const durationMilliseconds = Number(process.hrtime.bigint() - started) / 1_000_000;
  if (build.status !== 0) {
    process.stderr.write(build.stdout ?? "");
    process.stderr.write(build.stderr ?? "");
    fail(`build observation exited with status ${build.status}`);
  }
  const swiftVersion = spawnSync("swift", ["--version"], { encoding: "utf8" });
  report.buildObservation = {
    target: plan.coreTarget,
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
  console.log(`WorkbenchCore physical separation valid: ${categories.core.files} core sources, ${categories.native.files} native sources, ${categories.core.lines} core lines.`);
} else if (!reportPath) {
  process.stdout.write(serialized);
}
