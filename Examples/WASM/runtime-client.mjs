export class PortableParserClient {
  constructor(specificationURL, workerURL = new URL("./runtime-worker.mjs", import.meta.url)) {
    this.specification = fetch(specificationURL).then(response => {
      if (!response.ok) throw new Error(`Unable to load parser artifact (${response.status}).`);
      return response.json();
    });
    this.workerURL = workerURL;
  }

  async parse(source, { signal, ...options } = {}) {
    const specification = await this.specification;
    if (signal?.aborted) throw new DOMException("Parse was cancelled.", "AbortError");
    const worker = new Worker(this.workerURL, { type: "module" });
    const requestID = crypto.randomUUID();
    return new Promise((resolve, reject) => {
      const cancel = () => { worker.terminate(); reject(new DOMException("Parse was cancelled.", "AbortError")); };
      signal?.addEventListener("abort", cancel, { once: true });
      worker.onerror = event => { worker.terminate(); reject(new Error(event.message)); };
      worker.onmessage = ({ data }) => {
        if (data.requestID !== requestID) return;
        if (data.status === "ready") worker.postMessage({ requestID, operation: "parse", source, options });
        else {
          worker.terminate(); signal?.removeEventListener("abort", cancel);
          if (data.status === "success") resolve(data.result);
          else reject(Object.assign(new Error(data.error.message), data.error));
        }
      };
      worker.postMessage({ requestID, operation: "initialize", specification });
    });
  }
}
