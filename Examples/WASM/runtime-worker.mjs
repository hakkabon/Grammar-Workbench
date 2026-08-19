import { parse, validateSpecification, PortableRuntimeError, PORTABLE_RUNTIME_VERSION } from "./parser-core.mjs";

let specification = null;
self.onmessage = ({ data }) => {
  const requestID = data?.requestID ?? "invalid-request";
  try {
    if (data?.operation === "initialize") {
      specification = validateSpecification(data.specification);
      self.postMessage({ requestID, status: "ready", runtimeVersion: PORTABLE_RUNTIME_VERSION });
    } else if (data?.operation === "parse") {
      if (!specification) throw new PortableRuntimeError("not-initialized", "Worker is not initialized.");
      self.postMessage({ requestID, status: "success", result: parse(data.source ?? "", specification, data.options) });
    } else throw new PortableRuntimeError("unknown-operation", `Unknown worker operation: ${data?.operation ?? "missing"}.`);
  } catch (error) {
    self.postMessage({ requestID, status: "failure", error: { code: error.code ?? "runtime-error", message: error.message, details: error.details ?? {} } });
  }
};
