import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { parse, tokenize, validateSpecification, PORTABLE_RUNTIME_VERSION } from "../Examples/WASM/parser-core.mjs";

const specification = JSON.parse(await readFile(new URL("../Examples/WASM/expression-parser.json", import.meta.url)));
assert.equal(validateSpecification(specification), specification);
assert.equal(specification.minimumRuntimeVersion, PORTABLE_RUNTIME_VERSION);

const accepted = parse("left + middle + right", specification);
assert.equal(accepted.status, "accepted");
assert.equal(accepted.trace.at(-1).action, "accept");
assert.equal(accepted.tree.symbol, "E");
assert.deepEqual(accepted.diagnostics, []);

const rejected = parse("left +", specification);
assert.equal(rejected.status, "rejected");
assert.equal(rejected.diagnostics[0].code, "syntax-error");
assert.equal(rejected.diagnostics[0].offset, 6);
assert.throws(() => parse("left @ right", specification), error => error.code === "lexical-error" && error.details.offset === 5);
assert.throws(() => parse("left", specification, { signal: { aborted: true } }), error => error.code === "cancelled");
assert.throws(() => tokenize("one two", specification, { maximumTokens: 1 }), error => error.code === "token-limit");
assert.throws(() => parse("left + right", specification, { maximumSteps: 1 }), error => error.code === "step-limit");
assert.equal(parse("left", specification, { maximumSteps: 999999 }).status, "accepted");

const future = structuredClone(specification); future.schemaVersion = 99;
assert.throws(() => validateSpecification(future), error => error.code === "unsupported-schema");
const futureRuntime = structuredClone(specification); futureRuntime.minimumRuntimeVersion = 99;
assert.throws(() => validateSpecification(futureRuntime), error => error.code === "unsupported-runtime");
const unsafePattern = structuredClone(specification); unsafePattern.tokens[1].pattern = "[A-Za-z]+";
assert.throws(() => validateSpecification(unsafePattern), error => error.code === "invalid-token-pattern");
const unbounded = structuredClone(specification); unbounded.limits.maximumSteps = 10001;
assert.throws(() => validateSpecification(unbounded), error => error.code === "invalid-limits");

const worker = await readFile(new URL("../Examples/WASM/runtime-worker.mjs", import.meta.url), "utf8");
const client = await readFile(new URL("../Examples/WASM/runtime-client.mjs", import.meta.url), "utf8");
assert.match(worker, /validateSpecification/);
assert.match(client, /worker\.terminate\(\)/);
assert.match(client, /AbortSignal|signal/);
console.log("Portable browser runtime contract passed.");
