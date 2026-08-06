"use strict";

// End-to-end verification of the VS Code extension's protocol handling:
// runs Clients/vscode/client.js against the real grammar-workbench-lsp server
// with a stubbed `vscode` API, and drives it like VS Code would.

const assert = require("assert");
const fs = require("fs");
const { startClient } = require("../Clients/vscode/client.js");

const SERVER = ".build/debug/grammar-workbench-lsp";
if (!fs.existsSync(SERVER)) {
  console.error("server binary not found; build it first: swift build --product grammar-workbench-lsp");
  process.exit(2);
}

const PROG_GRAMMAR = `
%start Program
Program : Stmt Program | Stmt ;
Stmt : 'print' Expr ;
Expr : 'number' | 'string' ;
`;
const BLOCK_GRAMMAR = `
%start Program
Program : Stmt Program | Stmt ;
Stmt : '{' Stmt '}' | 'expr' ;
`;

// MARK: - Stubbed vscode API

function emitter() {
  const listeners = [];
  return {
    listen(fn) {
      listeners.push(fn);
      return { dispose() { const i = listeners.indexOf(fn); if (i >= 0) listeners.splice(i, 1); } };
    },
    fire(...args) { for (const fn of [...listeners]) fn(...args); },
  };
}

class Uri {
  constructor(fsPath) { this.fsPath = fsPath; this.path = fsPath; this._str = "file://" + fsPath; }
  toString() { return this._str; }
  static file(fsPath) { return new Uri(fsPath); }
  static parse(text) { return new Uri(text.replace(/^file:\/\//, "")); }
}
class Position { constructor(line, character) { this.line = line; this.character = character; } }
class Range { constructor(start, end) { this.start = start; this.end = end; } }
class Diagnostic { constructor(range, message, severity) { this.range = range; this.message = message; this.severity = severity; } }
class CompletionItem { constructor(label, kind) { this.label = label; this.kind = kind; } }
class MarkdownString { constructor(value) { this.value = value; } }
class Hover { constructor(contents, range) { this.contents = contents; this.range = range; } }
class DocumentSymbol {
  constructor(name, detail, kind, range, selectionRange) {
    this.name = name; this.detail = detail; this.kind = kind;
    this.range = range; this.selectionRange = selectionRange; this.children = [];
  }
}
class FoldingRange { constructor(startLine, endLine) { this.startLine = startLine; this.endLine = endLine; } }
class Disposable { constructor(fn) { this.fn = fn; } dispose() { if (this.fn) { const fn = this.fn; this.fn = null; fn(); } } }
class FakeDocument {
  constructor(fsPath, languageId, text) {
    this.uri = Uri.file(fsPath); this.languageId = languageId; this.text = text; this.version = 1;
  }
  getText() { return this.text; }
}

const CompletionItemKind = { Text: 0, Keyword: 13 };
const SymbolKind = { Struct: 22 };
const DiagnosticSeverity = { Error: 0, Warning: 1, Information: 2, Hint: 3 };

function makeVscode() {
  const documents = [];
  const openEvent = emitter();
  const changeEvent = emitter();
  const closeEvent = emitter();
  const saveEvent = emitter();
  const diagnosticsByUri = new Map();
  const providers = {};
  const outputLines = [];
  const subscriptions = [];
  const errors = [];
  return {
    vscode: {
      workspace: {
        textDocuments: documents,
        workspaceFolders: null,
        onDidOpenTextDocument: (fn) => openEvent.listen(fn),
        onDidChangeTextDocument: (fn) => changeEvent.listen(fn),
        onDidCloseTextDocument: (fn) => closeEvent.listen(fn),
        onDidSaveTextDocument: (fn) => saveEvent.listen(fn),
      },
      window: {
        createOutputChannel: () => ({ appendLine: (line) => outputLines.push(line) }),
        showErrorMessage: (message) => errors.push(message),
      },
      languages: {
        createDiagnosticCollection: () => ({
          set(uri, items) { diagnosticsByUri.set(uri.toString(), items); },
          delete(uri) { diagnosticsByUri.delete(uri.toString()); },
          dispose() {},
        }),
        registerCompletionItemProvider: (selector, provider) => { providers.completion = { selector, provider }; return new Disposable(() => {}); },
        registerHoverProvider: (selector, provider) => { providers.hover = { selector, provider }; return new Disposable(() => {}); },
        registerDocumentSymbolProvider: (selector, provider) => { providers.symbols = { selector, provider }; return new Disposable(() => {}); },
        registerFoldingRangeProvider: (selector, provider) => { providers.folding = { selector, provider }; return new Disposable(() => {}); },
      },
      Uri, Position, Range, Diagnostic, DiagnosticSeverity,
      CompletionItem, CompletionItemKind, MarkdownString, Hover,
      DocumentSymbol, SymbolKind, FoldingRange,
      TextEdit: { replace: (range, newText) => ({ range, newText }) },
      Disposable,
    },
    open(document) { documents.push(document); openEvent.fire(document); },
    change(document, text) { document.text = text; document.version += 1; changeEvent.fire({ document }); },
    save(document) { saveEvent.fire(document); },
    close(document) { closeEvent.fire(document); },
    context: { subscriptions },
    diagnosticsByUri, providers, outputLines, errors,
  };
}

function waitFor(check, timeoutMs = 8000) {
  const deadline = Date.now() + timeoutMs;
  return new Promise((resolve, reject) => {
    const poll = () => {
      let value;
      try { value = check(); } catch (error) { return reject(error); }
      if (value) return resolve(value);
      if (Date.now() > deadline) return reject(new Error("timed out waiting for condition"));
      setTimeout(poll, 20);
    };
    poll();
  });
}

// MARK: - Scenario

(async () => {
  const harness = makeVscode();
  const { vscode } = harness;
  const client = startClient(vscode, harness.context, {
    serverPath: SERVER,
    associations: { "*.prog": "prog", "*.blk": "block" },
  });
  const grammars = [
    ["/tmp/prog.grammarworkbench", "grammarworkbench", PROG_GRAMMAR],
    ["/tmp/block.grammarworkbench", "grammarworkbench", BLOCK_GRAMMAR],
  ];
  const grammarDoc = new FakeDocument(grammars[0][0], grammars[0][1], grammars[0][2]);
  const blockGrammarDoc = new FakeDocument(grammars[1][0], grammars[1][1], grammars[1][2]);
  harness.open(grammarDoc); // first relevant document spawns the server
  harness.open(blockGrammarDoc);

  await waitFor(() => harness.diagnosticsByUri.has("file:///tmp/prog.grammarworkbench"));
  assert.deepStrictEqual(harness.diagnosticsByUri.get("file:///tmp/prog.grammarworkbench"), []);
  console.log("PASS: grammar document compiled, empty diagnostics published");

  const source = new FakeDocument("/tmp/sample.prog", "prog", "print nu");
  harness.open(source);
  await waitFor(() => harness.diagnosticsByUri.has("file:///tmp/sample.prog"));
  const sourceDiagnostics = harness.diagnosticsByUri.get("file:///tmp/sample.prog");
  assert.ok(sourceDiagnostics.length >= 1, JSON.stringify(sourceDiagnostics));
  assert.strictEqual(sourceDiagnostics[0].severity, DiagnosticSeverity.Error);
  assert.ok(sourceDiagnostics[0].message.includes("nu"), sourceDiagnostics[0].message);
  console.log(
    "PASS: source document analyzed via association *.prog -> prog:",
    sourceDiagnostics.length, "diagnostics, e.g.", sourceDiagnostics[0].message
  );

  const completion = await harness.providers.completion.provider.provideCompletionItems(
    source, new Position(0, 8)
  );
  assert.deepStrictEqual(completion.map((item) => item.label), ["number"]);
  const item = completion[0];
  assert.strictEqual(item.kind, CompletionItemKind.Keyword);
  assert.strictEqual(item.detail, "'number'");
  assert.deepStrictEqual(item.textEdit.newText, "number");
  assert.deepStrictEqual(
    [item.textEdit.range.start.line, item.textEdit.range.start.character,
     item.textEdit.range.end.line, item.textEdit.range.end.character],
    [0, 6, 0, 8]
  );
  console.log("PASS: completion request round-trip:", completion.map((i) => i.label).join(", "));

  harness.change(source, "print number");
  await waitFor(() => {
    const items = harness.diagnosticsByUri.get("file:///tmp/sample.prog");
    return items && items.length === 0;
  });
  console.log("PASS: didChange (full sync) reanalyzed the document");

  harness.save(source);
  await new Promise((resolve) => setTimeout(resolve, 300));
  const afterSave = harness.diagnosticsByUri.get("file:///tmp/sample.prog");
  assert.ok(afterSave && afterSave.length === 0, "didSave should leave a valid document clean");
  console.log("PASS: didSave round-trip");

  const hover = await harness.providers.hover.provider.provideHover(source, new Position(0, 7));
  assert.ok(hover, "expected a hover");
  assert.ok(hover.contents.value.includes("Token `number`"), hover.contents.value);
  assert.ok(hover.contents.value.includes("Expr → 'number'"), hover.contents.value);
  assert.deepStrictEqual(
    [hover.range.start.line, hover.range.start.character, hover.range.end.line, hover.range.end.character],
    [0, 6, 0, 12]
  );
  console.log("PASS: hover request round-trip");

  const symbols = await harness.providers.symbols.provider.provideDocumentSymbols(source);
  assert.strictEqual(symbols.length, 1);
  assert.strictEqual(symbols[0].name, "Stmt");
  assert.strictEqual(symbols[0].kind, SymbolKind.Struct);
  assert.strictEqual(symbols[0].children[0].name, "Expr");
  console.log("PASS: document symbols round-trip");

  const blockSource = new FakeDocument("/tmp/sample.blk", "block", "expr\n{\nexpr }");
  harness.open(blockSource);
  await waitFor(() => harness.diagnosticsByUri.has("file:///tmp/sample.blk"));
  const folding = await harness.providers.folding.provider.provideFoldingRanges(blockSource);
  assert.ok(
    folding.some((range) => range.startLine === 1 && range.endLine === 2),
    JSON.stringify(folding)
  );
  console.log("PASS: folding ranges round-trip:", JSON.stringify(folding));

  for (const subscription of harness.context.subscriptions) subscription.dispose();
  await waitFor(() => harness.outputLines.includes("server exited (0)"));
  console.log("PASS: shutdown + exit on deactivate");
  console.log("ALL M4 CLIENT CHECKS PASSED");
  process.exit(0);
})().catch((error) => {
  console.error("FAILED:", error.message);
  process.exit(1);
});
