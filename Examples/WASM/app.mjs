import { PortableParserClient } from "./runtime-client.mjs";

const client = new PortableParserClient("./expression-parser.json");
const input = document.querySelector("#source"), status = document.querySelector("#status");
const trace = document.querySelector("#trace"), tree = document.querySelector("#tree");
const runButton = document.querySelector("#run"), cancelButton = document.querySelector("#cancel");
let activeController = null;

function renderTree(node, depth = 0) {
  if (!node) return "";
  const value = `${"  ".repeat(depth)}${node.symbol}${node.lexeme ? ` “${node.lexeme}”` : ""}`;
  return [value, ...node.children.flatMap(child => renderTree(child, depth + 1))].join("\n");
}

async function run() {
  activeController?.abort();
  activeController = new AbortController();
  runButton.disabled = true; cancelButton.disabled = false;
  status.textContent = "Parsing in worker…"; status.dataset.kind = "running";
  try {
    const result = await client.parse(input.value, { signal: activeController.signal });
    status.textContent = result.status === "accepted" ? "Accepted" : result.diagnostics[0].message;
    status.dataset.kind = result.status;
    trace.replaceChildren(...result.trace.map(frame => {
      const row = document.createElement("tr");
      for (const value of [frame.step, `I${frame.state}`, frame.lookahead, frame.action]) {
        const cell = document.createElement("td"); cell.textContent = value; row.append(cell);
      }
      return row;
    }));
    tree.textContent = renderTree(result.tree);
  } catch (error) {
    const cancelled = error.name === "AbortError";
    status.textContent = cancelled ? "Cancelled" : `${error.code ? `${error.code}: ` : ""}${error.message}`;
    status.dataset.kind = cancelled ? "cancelled" : "rejected";
    trace.replaceChildren(); tree.textContent = "";
  } finally {
    runButton.disabled = false; cancelButton.disabled = true; activeController = null;
  }
}

runButton.addEventListener("click", run);
cancelButton.addEventListener("click", () => activeController?.abort());
input.addEventListener("keydown", event => { if (event.key === "Enter") run(); });
run();
