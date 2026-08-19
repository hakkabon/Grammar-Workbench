import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { parse } from "../Examples/WASM/parser-core.mjs";

const specification = JSON.parse(await readFile(new URL("../Examples/WASM/expression-parser.json", import.meta.url)));
const accepted = parse("left + middle + right", specification);
assert.equal(accepted.status, "accepted");
assert.equal(accepted.trace.at(-1).action, "accept");
assert.equal(accepted.tree.symbol, "E");
assert.equal(parse("left +", specification).status, "rejected");
assert.throws(() => parse("left @ right", specification), /Unexpected input/);
console.log("Portable WASM browser demonstration passed.");
