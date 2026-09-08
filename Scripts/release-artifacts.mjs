#!/usr/bin/env node

import { createHash } from "node:crypto";
import {
  lstatSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync
} from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const scriptPath = fileURLToPath(import.meta.url);
const root = resolve(dirname(scriptPath), "..");
const mode = process.argv[2];

function fail(message) {
  console.error(`Release artifact validation failed: ${message}`);
  process.exit(1);
}

function values(name) {
  const result = [];
  for (let index = 3; index < process.argv.length; index += 1) {
    if (process.argv[index] === name) result.push(process.argv[index + 1]);
  }
  return result;
}

function value(name) {
  const found = values(name);
  if (found.length > 1) fail(`${name} may only be supplied once`);
  if (found.length === 1 && (!found[0] || found[0].startsWith("--"))) {
    fail(`${name} requires a value`);
  }
  return found[0];
}

function has(name) {
  return process.argv.slice(3).includes(name);
}

function validateArguments(options) {
  const allowed = new Set(options);
  for (let index = 3; index < process.argv.length; index += 1) {
    const argument = process.argv[index];
    if (!allowed.has(argument)) fail(`unknown option ${argument}`);
    if (!["--require-clean", "--print-version", "--signed", "--notarized"].includes(argument)) {
      index += 1;
    }
  }
}

function sha256(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

function git(...arguments_) {
  const result = spawnSync("git", ["-C", root, ...arguments_], { encoding: "utf8" });
  if (result.status !== 0) fail(`git ${arguments_.join(" ")} failed`);
  return result.stdout.trim();
}

function sourceVersion() {
  const source = readFileSync(join(root, "Sources/GrammarWorkbench/ProductionSupport.swift"), "utf8");
  const matches = [...source.matchAll(/public static let version = "([^"]+)"/g)];
  if (matches.length !== 1) fail("GrammarWorkbenchRelease.version must be declared exactly once");
  return matches[0][1];
}

function semanticVersion(version) {
  if (!/^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/.test(version)) {
    fail(`invalid stable semantic version ${version}`);
  }
  return version;
}

function validateSource() {
  const version = semanticVersion(sourceVersion());
  const requestedVersion = value("--version");
  if (requestedVersion && requestedVersion !== version) {
    fail(`requested version ${requestedVersion} differs from source version ${version}`);
  }
  const tag = value("--tag");
  if (tag) {
    const tagVersion = tag.startsWith("v") ? tag.slice(1) : tag;
    if (semanticVersion(tagVersion) !== version) {
      fail(`tag ${tag} differs from source version ${version}`);
    }
  }
  const revision = value("--revision");
  const head = git("rev-parse", "HEAD");
  if (!/^[0-9a-f]{40}$/.test(head)) fail("HEAD is not a full Git revision");
  if (revision && (!/^[0-9a-f]{40}$/.test(revision) || revision !== head)) {
    fail(`release revision ${revision} differs from HEAD ${head}`);
  }
  if (tag && git("rev-list", "-n", "1", tag) !== head) {
    fail(`tag ${tag} does not identify HEAD ${head}`);
  }
  if (has("--require-clean") && git("status", "--porcelain=v1", "--untracked-files=all") !== "") {
    fail("release checkout is not clean");
  }

  const toolchain = JSON.parse(readFileSync(join(root, "Packaging/PortabilityToolchain.json"), "utf8"));
  const manifest = readFileSync(join(root, "Package.swift"), "utf8");
  const toolsVersion = manifest.match(/^\/\/ swift-tools-version:\s*([^\s]+)/)?.[1];
  if (toolsVersion !== toolchain.swiftToolsVersion
      || toolchain.requiredSwiftVersion !== toolchain.swiftToolsVersion) {
    fail("Package.swift and the portability toolchain disagree on the Swift release baseline");
  }
  const plist = readFileSync(join(root, "Packaging/Info.plist"), "utf8");
  for (const placeholder of ["@VERSION@", "@BUILD_NUMBER@", "@BUNDLE_IDENTIFIER@"]) {
    if (!plist.includes(placeholder)) fail(`Info.plist is missing ${placeholder}`);
  }
  const releasePolicy = JSON.parse(readFileSync(join(root, "Packaging/ReleaseCandidate.json"), "utf8"));
  const releaseSchema = JSON.parse(readFileSync(join(root, releasePolicy.releaseArtifactManifestSchema), "utf8"));
  if (releasePolicy.releaseArtifactManifestVersion !== 1
      || releaseSchema.properties?.schemaVersion?.const !== releasePolicy.releaseArtifactManifestVersion) {
    fail("release artifact manifest schema differs from release policy");
  }
  const lockPath = join(root, "Package.resolved");
  const lock = JSON.parse(readFileSync(lockPath, "utf8"));
  if (lock.version !== 3 || !Array.isArray(lock.pins) || lock.pins.length === 0) {
    fail("Package.resolved is missing or unsupported");
  }
  const lockPins = new Map();
  for (const pin of lock.pins) {
    if (lockPins.has(pin.identity) || !/^[0-9a-f]{40}$/.test(pin.state?.revision ?? "")) {
      fail(`invalid resolved dependency ${pin.identity ?? "unknown"}`);
    }
    lockPins.set(pin.identity, pin);
  }
  const ecosystem = JSON.parse(readFileSync(join(root, "Packaging/EcosystemCompatibility.json"), "utf8"));
  for (const name of ["Grammar", "Parser", "LR-Parsing"]) {
    const expected = ecosystem.repositories.find(repository => repository.name === name);
    const identity = name.toLowerCase();
    const pin = lockPins.get(identity);
    if (!expected || pin?.state.version !== expected.version || pin?.state.revision !== expected.revision) {
      fail(`Package.resolved does not match the reviewed ${name} ecosystem release`);
    }
  }
  return {
    version,
    revision: head,
    dependencyLock: {
      file: "Package.resolved",
      sha256: sha256(lockPath),
      pins: lock.pins.map(pin => ({
        identity: pin.identity,
        version: pin.state.version,
        revision: pin.state.revision
      })).sort((left, right) => left.identity.localeCompare(right.identity))
    }
  };
}

function parseChecksums(path) {
  const entries = new Map();
  for (const line of readFileSync(path, "utf8").trim().split("\n")) {
    const match = line.match(/^([0-9a-f]{64})\s+\*?(.+)$/);
    if (!match) fail(`invalid checksum line in ${basename(path)}`);
    if (entries.has(match[2])) fail(`duplicate checksum for ${match[2]}`);
    entries.set(match[2], match[1]);
  }
  return entries;
}

function safeFile(directory, name, description) {
  if (!name || basename(name) !== name || name === "." || name === "..") {
    fail(`${description} must be a direct child filename`);
  }
  const path = join(directory, name);
  const metadata = lstatSync(path);
  if (!metadata.isFile() || metadata.isSymbolicLink()) fail(`${description} ${name} is not a regular file`);
  return path;
}

function verifyManifest(manifestPath) {
  const directory = dirname(manifestPath);
  const manifestName = basename(manifestPath);
  const manifestMetadata = lstatSync(manifestPath);
  if (!manifestMetadata.isFile() || manifestMetadata.isSymbolicLink()) {
    fail("release manifest is not a regular file");
  }
  const sidecarPath = safeFile(directory, `${manifestName}.sha256`, "manifest checksum");
  const sidecar = parseChecksums(sidecarPath);
  if (sidecar.size !== 1 || sidecar.get(manifestName) !== sha256(manifestPath)) {
    fail("release manifest checksum does not match");
  }

  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  if (manifest.schemaVersion !== 1 || manifest.checksumAlgorithm !== "sha256") {
    fail("unsupported release manifest");
  }
  semanticVersion(manifest.release?.version ?? "");
  if (!/^[1-9][0-9]*$/.test(manifest.release?.buildNumber ?? "")) fail("invalid build number");
  if (manifest.release.tag !== null && typeof manifest.release.tag !== "string") fail("invalid release tag");
  if (manifest.release.tag) {
    const tagVersion = manifest.release.tag.startsWith("v")
      ? manifest.release.tag.slice(1) : manifest.release.tag;
    if (tagVersion !== manifest.release.version) fail("manifest tag differs from release version");
  }
  if (!/^[0-9a-f]{40}$/.test(manifest.source?.revision ?? "")) fail("invalid source revision");
  if (typeof manifest.source?.repository !== "string" || manifest.source.repository.length === 0) {
    fail("invalid source repository");
  }
  if (typeof manifest.source?.clean !== "boolean") fail("invalid source cleanliness");
  if (manifest.source?.dependencyLock?.file !== "Package.resolved"
      || !/^[0-9a-f]{64}$/.test(manifest.source?.dependencyLock?.sha256 ?? "")
      || !Array.isArray(manifest.source?.dependencyLock?.pins)
      || manifest.source.dependencyLock.pins.length === 0) {
    fail("invalid dependency lock provenance");
  }
  const pinIdentities = new Set();
  for (const pin of manifest.source.dependencyLock.pins) {
    if (typeof pin?.identity !== "string" || pin.identity.length === 0
        || typeof pin?.version !== "string" || pin.version.length === 0
        || !/^[0-9a-f]{40}$/.test(pin?.revision ?? "")
        || pinIdentities.has(pin.identity)) {
      fail("invalid resolved dependency provenance");
    }
    pinIdentities.add(pin.identity);
  }
  if (!Array.isArray(manifest.artifacts) || manifest.artifacts.length === 0) fail("release has no artifacts");
  if (typeof manifest.platform?.name !== "string" || manifest.platform.name.length === 0
      || !Array.isArray(manifest.platform?.architectures)
      || manifest.platform.architectures.length === 0
      || manifest.platform.architectures.some(architecture =>
        typeof architecture !== "string" || architecture.length === 0)
      || new Set(manifest.platform.architectures).size !== manifest.platform.architectures.length) {
    fail("invalid release platform");
  }
  if (typeof manifest.security?.executablesSigned !== "boolean"
      || typeof manifest.security?.applicationNotarized !== "boolean") {
    fail("invalid release security state");
  }
  if (manifest.security?.applicationNotarized && !manifest.security?.executablesSigned) {
    fail("notarized application does not declare signed executables");
  }
  if (typeof manifest.toolchain?.swiftVersion !== "string"
      || manifest.toolchain.swiftVersion.length === 0) {
    fail("invalid release toolchain");
  }

  const checksumPath = safeFile(directory, manifest.checksums?.file, "checksum file");
  if (!/^[0-9a-f]{64}$/.test(manifest.checksums?.sha256 ?? "")
      || sha256(checksumPath) !== manifest.checksums.sha256) {
    fail("checksum file digest differs from manifest");
  }
  const checksums = parseChecksums(checksumPath);
  const names = new Set();
  for (const artifact of manifest.artifacts) {
    if (typeof artifact?.name !== "string" || names.has(artifact.name)) {
      fail(`invalid or duplicate artifact ${artifact?.name ?? "unknown"}`);
    }
    names.add(artifact.name);
    if (!artifact.name.includes(manifest.release.version)) {
      fail(`artifact ${artifact.name} does not carry release version ${manifest.release.version}`);
    }
    const path = safeFile(directory, artifact.name, "artifact");
    if (!Number.isSafeInteger(artifact.bytes) || artifact.bytes < 1
        || statSync(path).size !== artifact.bytes) {
      fail(`size differs for ${artifact.name}`);
    }
    const digest = sha256(path);
    if (!/^[0-9a-f]{64}$/.test(artifact.sha256 ?? "")
        || digest !== artifact.sha256 || checksums.get(artifact.name) !== digest) {
      fail(`checksum differs for ${artifact.name}`);
    }
  }
  if (checksums.size !== names.size || [...checksums.keys()].some(name => !names.has(name))) {
    fail("checksum file and release manifest contain different artifact sets");
  }
  return manifest;
}

function createManifest() {
  const source = validateSource();
  const directory = resolve(value("--directory") ?? fail("--directory is required"));
  const artifactNames = values("--artifact");
  if (artifactNames.length === 0 || new Set(artifactNames).size !== artifactNames.length) {
    fail("at least one unique --artifact is required");
  }
  const checksumName = value("--checksums") ?? fail("--checksums is required");
  const checksumPath = safeFile(directory, checksumName, "checksum file");
  const checksumEntries = parseChecksums(checksumPath);
  const artifacts = artifactNames.sort().map(name => {
    const path = safeFile(directory, name, "artifact");
    const digest = sha256(path);
    if (checksumEntries.get(name) !== digest) fail(`checksum differs for ${name}`);
    return { name, bytes: statSync(path).size, sha256: digest };
  });
  if (checksumEntries.size !== artifacts.length) fail("checksum file contains an undeclared artifact");
  const outputName = value("--output") ?? "ReleaseManifest.json";
  if (basename(outputName) !== outputName) fail("--output must be a direct child filename");
  const tag = value("--tag") ?? null;
  const buildNumber = value("--build") ?? "1";
  if (!/^[1-9][0-9]*$/.test(buildNumber)) fail("--build must be a positive integer");
  if (has("--notarized") && !has("--signed")) fail("--notarized requires --signed");
  const swift = spawnSync("swift", ["--version"], { encoding: "utf8" });
  if (swift.status !== 0) fail("swift --version failed");
  const manifest = {
    schemaVersion: 1,
    release: {
      version: source.version,
      buildNumber,
      tag
    },
    source: {
      repository: "https://github.com/hakkabon/Grammar-Workbench.git",
      revision: source.revision,
      clean: git("status", "--porcelain=v1", "--untracked-files=all") === "",
      dependencyLock: source.dependencyLock
    },
    toolchain: { swiftVersion: swift.stdout.trim() },
    platform: {
      name: value("--platform") ?? fail("--platform is required"),
      architectures: (value("--architectures") ?? fail("--architectures is required"))
        .split(/[ ,]+/).filter(Boolean).sort()
    },
    security: {
      executablesSigned: has("--signed"),
      applicationNotarized: has("--notarized")
    },
    checksumAlgorithm: "sha256",
    checksums: { file: checksumName, sha256: sha256(checksumPath) },
    artifacts
  };
  const outputPath = join(directory, outputName);
  writeFileSync(outputPath, `${JSON.stringify(manifest, null, 2)}\n`);
  writeFileSync(`${outputPath}.sha256`, `${sha256(outputPath)}  ${outputName}\n`);
  verifyManifest(outputPath);
  console.log(`Release manifest valid: ${artifacts.length} artifacts at ${source.revision}.`);
}

function selfTest() {
  const directory = mkdtempSync(join(tmpdir(), "grammar-workbench-release-test."));
  try {
    const version = sourceVersion();
    const artifact = `Grammar-Workbench-${version}-test.zip`;
    writeFileSync(join(directory, artifact), "release fixture\n");
    writeFileSync(join(directory, "SHA256SUMS"), `${sha256(join(directory, artifact))}  ${artifact}\n`);
    const common = [
      scriptPath, "create", "--directory", directory, "--version", version,
      "--platform", "test", "--architectures", process.arch,
      "--checksums", "SHA256SUMS", "--artifact", artifact
    ];
    const created = spawnSync(process.execPath, common, { encoding: "utf8" });
    if (created.status !== 0) fail(`self-test creation failed: ${created.stderr}`);
    const verified = spawnSync(process.execPath, [
      scriptPath, "verify", "--manifest", join(directory, "ReleaseManifest.json")
    ], { encoding: "utf8" });
    if (verified.status !== 0) fail(`self-test verification failed: ${verified.stderr}`);
    writeFileSync(join(directory, artifact), "corrupt\n");
    const rejected = spawnSync(process.execPath, [
      scriptPath, "verify", "--manifest", join(directory, "ReleaseManifest.json")
    ], { encoding: "utf8" });
    if (rejected.status === 0) fail("self-test accepted a corrupt artifact");
    console.log("Release artifact self-test passed.");
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

switch (mode) {
case "source": {
  validateArguments(["--version", "--tag", "--revision", "--require-clean", "--print-version"]);
  const source = validateSource();
  if (has("--print-version")) process.stdout.write(source.version);
  else console.log(`Release source valid: ${source.version} at ${source.revision}.`);
  break;
}
case "create":
  validateArguments([
    "--directory", "--artifact", "--checksums", "--output", "--version", "--tag",
    "--revision", "--require-clean", "--build", "--platform", "--architectures",
    "--signed", "--notarized"
  ]);
  createManifest();
  break;
case "verify":
  validateArguments(["--manifest"]);
  verifyManifest(resolve(value("--manifest") ?? fail("--manifest is required")));
  console.log("Release artifacts verified.");
  break;
case "self-test":
  validateArguments([]);
  selfTest();
  break;
default:
  fail("usage: release-artifacts.mjs source|create|verify|self-test [options]");
}
