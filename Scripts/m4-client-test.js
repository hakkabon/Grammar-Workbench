"use strict";

// End-to-end verification of the VS Code extension's protocol handling:
// runs Clients/vscode/client.js against the real grammar-workbench-lsp server
// with a stubbed `vscode` API, and drives it like VS Code would.
<<<<<<< HEAD
=======

>>>>>>> dev-branch
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
class Location { constructor(uri, range) { this.uri = uri; this.range = range; } }
<<<<<<< HEAD
class WorkspaceEdit {
  constructor() { this.edits = new Map(); }
  set(uri, edits) { this.edits.set(uri.toString(), edits); }
  applyTo(text) {
    const lines = text.split("\n");
    const allEdits = [];
    for (const edits of this.edits.values()) allEdits.push(...edits);
    allEdits.sort(
      (a, b) =>
        b.range.start.line - a.range.start.line ||
        b.range.start.character - a.range.start.character
    );
    for (const edit of allEdits) {
      const line = lines[edit.range.start.line];
      lines[edit.range.start.line] =
        line.slice(0, edit.range.start.character) +
        edit.newText +
        line.slice(edit.range.end.character);
    }
    return lines.join("\n");
  }
}
class SemanticTokens { constructor(data) { this.data = data; } }
class SemanticTokensLegend { constructor(tokenTypes, tokenModifiers) { this.tokenTypes = tokenTypes; this.tokenModifiers = tokenModifiers; } }
class DocumentHighlight { constructor(range, kind) { this.range = range; this.kind = kind; } }
class DocumentLink { constructor(range, target) { this.range = range; this.target = target; } }
const DocumentHighlightKind = { Text: 0, Read: 1, Write: 2 };
class CodeAction {
  constructor(title, kind) { this.title = title; this.kind = kind; this.isPreferred = false; this.edit = undefined; }
}
const CodeActionKind = { QuickFix: "quickfix" };
=======
class CodeAction { constructor(title, kind) { this.title = title; this.kind = kind; } }
class WorkspaceEdit {
  constructor() { this.edits = []; }
  replace(uri, range, newText) { this.edits.push({ uri, range, newText }); }
}
>>>>>>> dev-branch
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
<<<<<<< HEAD
        registerDefinitionProvider: (selector, provider) => { providers.definition = { selector, provider }; return new Disposable(() => {}); },
        registerReferenceProvider: (selector, provider) => { providers.references = { selector, provider }; return new Disposable(() => {}); },
        registerRenameProvider: (selector, provider) => { providers.rename = { selector, provider }; return new Disposable(() => {}); },
        registerCodeActionsProvider: (selector, provider) => { providers.codeActions = { selector, provider }; return new Disposable(() => {}); },
        registerDocumentSymbolProvider: (selector, provider) => { providers.symbols = { selector, provider }; return new Disposable(() => {}); },
        registerFoldingRangeProvider: (selector, provider) => { providers.folding = { selector, provider }; return new Disposable(() => {}); },
        registerDocumentSemanticTokensProvider: (selector, provider) => { providers.semanticTokens = { selector, provider }; return new Disposable(() => {}); },
        registerDocumentHighlightProvider: (selector, provider) => { providers.highlights = { selector, provider }; return new Disposable(() => {}); },
        registerDocumentFormattingEditProvider: (selector, provider) => { providers.formatting = { selector, provider }; return new Disposable(() => {}); },
        registerDocumentRangeFormattingEditProvider: (selector, provider) => { providers.rangeFormatting = { selector, provider }; return new Disposable(() => {}); },
        registerDocumentLinkProvider: (selector, provider) => { providers.links = { selector, provider }; return new Disposable(() => {}); },
      },
      Uri, Position, Range, Diagnostic, DiagnosticSeverity,
      CompletionItem, CompletionItemKind, MarkdownString, Hover,
      DocumentSymbol, SymbolKind, FoldingRange, Location, WorkspaceEdit,
      SemanticTokens, SemanticTokensLegend, CodeAction, CodeActionKind,
      DocumentHighlight, DocumentHighlightKind, DocumentLink,
=======
        registerDocumentSymbolProvider: (selector, provider) => { providers.symbols = { selector, provider }; return new Disposable(() => {}); },
        registerFoldingRangeProvider: (selector, provider) => { providers.folding = { selector, provider }; return new Disposable(() => {}); },
        registerDefinitionProvider: (selector, provider) => { providers.definition = { selector, provider }; return new Disposable(() => {}); },
        registerCodeActionsProvider: (selector, provider) => { providers.codeActions = { selector, provider }; return new Disposable(() => {}); },
      },
      Uri, Position, Range, Diagnostic, DiagnosticSeverity,
      CompletionItem, CompletionItemKind, MarkdownString, Hover,
      DocumentSymbol, SymbolKind, FoldingRange,
      Location, CodeAction, CodeActionKind: { QuickFix: "quickfix" }, WorkspaceEdit,
>>>>>>> dev-branch
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

<<<<<<< HEAD
/** Decodes relative semantic-token data into [line, start, length, type]. */
function decodeTokens(data) {
  const tokens = [];
  let line = 0;
  let start = 0;
  for (let i = 0; i < data.length; i += 5) {
    line += data[i];
    start = data[i] === 0 ? start + data[i + 1] : data[i + 1];
    tokens.push([line, start, data[i + 2], data[i + 3]]);
  }
  return tokens;
}

/** Applies line-scoped formatting edits to `text` and returns the result. */
function applyLineEdits(text, edits) {
  const lines = text.split("\n");
  for (const edit of [...edits].sort((a, b) => b.range.start.line - a.range.start.line)) {
    const line = lines[edit.range.start.line];
    lines[edit.range.start.line] =
      line.slice(0, edit.range.start.character) +
      edit.newText +
      line.slice(edit.range.end.character);
  }
  return lines.join("\n");
}

=======
>>>>>>> dev-branch
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

<<<<<<< HEAD
=======
  const grammarCompletions = await harness.providers.completion.provider.provideCompletionItems(
    grammarDoc, new Position(1, 3)
  );
  assert.deepStrictEqual(grammarCompletions.map((item) => item.label), ["%start"]);
  console.log("PASS: grammar editor completion round-trip");

  const definitions = await harness.providers.definition.provider.provideDefinition(
    grammarDoc, new Position(3, 16)
  );
  assert.strictEqual(definitions.length, 1);
  assert.strictEqual(definitions[0].range.start.line, 4);
  console.log("PASS: grammar go-to-definition round-trip");

  const brokenGrammar = new FakeDocument(
    "/tmp/fix.grammarworkbench", "grammarworkbench", "%start S\nS 'x' ;"
  );
  harness.open(brokenGrammar);
  const brokenDiagnostics = await waitFor(() => {
    const items = harness.diagnosticsByUri.get("file:///tmp/fix.grammarworkbench");
    return items && items.length ? items : null;
  });
  const fixes = await harness.providers.codeActions.provider.provideCodeActions(
    brokenGrammar, new Range(new Position(1, 0), new Position(1, 7)),
    { diagnostics: brokenDiagnostics }
  );
  assert.strictEqual(fixes[0].title, "Insert missing ‘:’");
  assert.strictEqual(fixes[0].edit.edits[0].newText, ": ");
  console.log("PASS: grammar quick-fix round-trip");

>>>>>>> dev-branch
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

<<<<<<< HEAD
  const tokensResult = await harness.providers.semanticTokens.provider.provideDocumentSemanticTokens(grammarDoc);
  assert.ok(tokensResult, "expected semantic tokens for the grammar document");
  const tokens = decodeTokens(tokensResult.data);
  assert.deepStrictEqual(tokens[0], [1, 0, 6, 0], "directive should be a keyword");
  assert.deepStrictEqual(tokens[1], [1, 7, 7, 6], "start symbol should be a type");
  assert.ok(
    tokens.some((t) => t[0] === 4 && t[1] === 7 && t[2] === 8 && t[3] === 1),
    "literal 'number' should be a string token: " + JSON.stringify(tokens)
  );
  console.log("PASS: semantic tokens round-trip:", tokens.length, "tokens");

  const definition = await harness.providers.definition.provider.provideDefinition(
    source, new Position(0, 7)
  );
  assert.ok(definition && definition.length === 1, JSON.stringify(definition));
  assert.strictEqual(definition[0].uri.fsPath, "/tmp/prog.grammarworkbench");
  assert.deepStrictEqual(
    [definition[0].range.start.line, definition[0].range.start.character],
    [4, 0]
  );
  console.log("PASS: definition jumps to the token's rule in the grammar");

  const references = await harness.providers.references.provider.provideReferences(
    grammarDoc, new Position(3, 0), { includeDeclaration: true }
  );
  assert.deepStrictEqual(
    references.map((location) => [location.range.start.line, location.range.start.character]),
    [[2, 10], [2, 25], [3, 0]]
  );
  console.log("PASS: references round-trip:", references.length, "locations");

  const renameEdit = await harness.providers.rename.provider.provideRenameEdits(
    grammarDoc, new Position(3, 0), "Action"
  );
  assert.ok(renameEdit, "expected rename edits");
  const renamed = renameEdit.applyTo(grammarDoc.text);
  assert.ok(renamed.includes("Program : Action Program | Action ;"), renamed);
  assert.ok(renamed.includes("Action : 'print' Expr ;"), renamed);
  console.log("PASS: rename round-trip: Stmt -> Action");

  harness.change(source, "print nu");
  await waitFor(() => {
    const items = harness.diagnosticsByUri.get("file:///tmp/sample.prog");
    return items && items.length > 0;
  });
  const quickFixes = await harness.providers.codeActions.provider.provideCodeActions(
    source, new Range(new Position(0, 6), new Position(0, 8)), { diagnostics: [] }
  );
  assert.strictEqual(quickFixes.length, 1, JSON.stringify(quickFixes));
  assert.strictEqual(quickFixes[0].title, "Insert missing ‘number’");
  assert.strictEqual(quickFixes[0].kind, CodeActionKind.QuickFix);
  assert.strictEqual(quickFixes[0].isPreferred, true);
  assert.strictEqual(
    quickFixes[0].edit.edits.get("file:///tmp/sample.prog")[0].newText,
    "number "
  );
  console.log("PASS: recovery code action round-trip:", quickFixes[0].title);

  harness.change(grammarDoc, PROG_GRAMMAR + " ");
  await waitFor(() =>
    harness.outputLines.some((line) => line.includes("progress begin") && line.includes("Analyzing source documents"))
  );
  assert.ok(
    harness.outputLines.some((line) => line.includes("Analyzed 2/2 documents")),
    "expected a per-document progress report"
  );
  assert.ok(harness.outputLines.some((line) => line.includes("progress end")), "expected a progress end");
  console.log("PASS: work-done progress begin/report/end");

  const highlights = await harness.providers.highlights.provider.provideDocumentHighlights(
    grammarDoc, new Position(3, 0)
  );
  assert.deepStrictEqual(
    highlights.map((h) => [h.range.start.line, h.range.start.character, h.kind]),
    [[2, 10, DocumentHighlightKind.Read], [2, 25, DocumentHighlightKind.Read], [3, 0, DocumentHighlightKind.Write]]
  );
  console.log("PASS: document highlights round-trip:", highlights.length, "highlights");

  const blockHighlights = await harness.providers.highlights.provider.provideDocumentHighlights(
    blockSource, new Position(0, 0)
  );
  assert.deepStrictEqual(
    blockHighlights.map((h) => [h.range.start.line, h.range.start.character]),
    [[0, 0], [2, 0]]
  );
  console.log("PASS: source document highlights match repeated tokens");

  const MESSY_GRAMMAR = "%start  S\n\nS : A |   B ;\n  A : 'a' ;  \nB : 'b' ;\t// comment\n";
  const messyDoc = new FakeDocument("/tmp/messy.grammarworkbench", "grammarworkbench", MESSY_GRAMMAR);
  harness.open(messyDoc);
  await waitFor(() => harness.diagnosticsByUri.has("file:///tmp/messy.grammarworkbench"));
  const formatOptions = { tabSize: 4, insertSpaces: true };
  const formattingEdits = await harness.providers.formatting.provider.provideDocumentFormattingEdits(
    messyDoc, formatOptions
  );
  assert.strictEqual(
    applyLineEdits(MESSY_GRAMMAR, formattingEdits),
    "%start S\n\nS : A | B ;\nA : 'a' ;\nB : 'b' ; // comment\n"
  );
  console.log("PASS: formatting canonicalizes the grammar document");

  const rangeEdits = await harness.providers.rangeFormatting.provider.provideDocumentRangeFormattingEdits(
    messyDoc, new Range(new Position(1, 0), new Position(4, 0)), formatOptions
  );
  assert.deepStrictEqual(rangeEdits.map((e) => e.range.start.line), [2, 3]);
  console.log("PASS: range formatting edits only the requested lines");

  const links = await harness.providers.links.provider.provideDocumentLinks(blockSource);
  assert.strictEqual(links.length, 4, JSON.stringify(links));
  assert.ok(links.every((link) => link.target.fsPath === "/tmp/block.grammarworkbench"));
  assert.deepStrictEqual(
    links.map((link) => [link.range.start.line, link.range.start.character]),
    [[0, 0], [1, 0], [2, 0], [2, 5]]
  );
  console.log("PASS: document links jump to the grammar rules");

  for (const subscription of harness.context.subscriptions) subscription.dispose();
  await waitFor(() => harness.outputLines.includes("server exited (0)"));
  console.log("PASS: shutdown + exit on deactivate");
  console.log("ALL CLIENT CHECKS PASSED");
=======
  for (const subscription of harness.context.subscriptions) subscription.dispose();
  await waitFor(() => harness.outputLines.includes("server exited (0)"));
  console.log("PASS: shutdown + exit on deactivate");
  console.log("ALL M4 CLIENT CHECKS PASSED");
>>>>>>> dev-branch
  process.exit(0);
})().catch((error) => {
  console.error("FAILED:", error.message);
  process.exit(1);
});
