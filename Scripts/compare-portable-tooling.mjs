import { readFile } from "node:fs/promises";

const [nativePath, wasiPath] = process.argv.slice(2);
if (!nativePath) throw new Error("usage: compare-portable-tooling.mjs NATIVE_HOST [WASI_RESPONSES]");

const native = (await readFile(nativePath, "utf8")).trim().split("\n").map(JSON.parse);
if (native.length !== 2) throw new Error(`expected 2 native responses, received ${native.length}`);
for (const response of native) {
  if (response.status !== "success") throw new Error(`native request ${response.requestID} failed`);
}

if (wasiPath) {
  const wasi = (await readFile(wasiPath, "utf8")).trim().split("\n").map(JSON.parse);
  const normalize = (value) => {
    if (Array.isArray(value)) return value.map(normalize);
    if (value && typeof value === "object") {
      return Object.fromEntries(Object.entries(value)
        .filter(([key]) => !key.endsWith("Milliseconds"))
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, child]) => [key, normalize(child)]));
    }
    return value;
  };
  if (JSON.stringify(normalize(native)) !== JSON.stringify(normalize(wasi))) {
    throw new Error("native and WASI tooling responses differ");
  }
  console.log("Native and WASI tooling responses are equivalent.");
} else {
  console.log("Native tooling golden requests passed; WASI comparison was not requested.");
}
