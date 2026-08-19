import { parse } from "./parser-core.mjs";

const specification = await fetch("./expression-parser.json").then(response => response.json());
const input = document.querySelector("#source"), status = document.querySelector("#status");
const trace = document.querySelector("#trace"), tree = document.querySelector("#tree");

function renderTree(node, depth = 0) {
  if (!node) return "";
  const value = `${"  ".repeat(depth)}${node.symbol}${node.lexeme ? ` “${node.lexeme}”` : ""}`;
  return [value, ...node.children.flatMap(child => renderTree(child, depth + 1))].join("\n");
}

function run() {
  try {
    const result = parse(input.value, specification);
    status.textContent = result.status === "accepted" ? "Accepted" : result.error;
    status.dataset.kind = result.status;
    trace.innerHTML = result.trace.map(frame =>
      `<tr><td>${frame.step}</td><td>I${frame.state}</td><td>${frame.lookahead}</td><td>${frame.action}</td></tr>`
    ).join("");
    tree.textContent = renderTree(result.tree);
  } catch (error) {
    status.textContent = error.message; status.dataset.kind = "rejected";
    trace.innerHTML = ""; tree.textContent = "";
  }
}

document.querySelector("#run").addEventListener("click", run);
input.addEventListener("keydown", event => { if (event.key === "Enter") run(); });
run();
