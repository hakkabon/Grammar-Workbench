"use strict";

// Grammar Workbench LSP client: a minimal Language Server Protocol client over
// stdio, using only the `vscode` API and Node built-ins (no npm dependencies).
// `startClient(vscode, context, options)` is also used by Scripts/m4-client-test.js
// with a stubbed `vscode` to verify the protocol handling end to end.

const { spawn } = require("child_process");
const fs = require("fs");
const path = require("path");

/** Converts a simple glob (`*`, `**`, `?`) into a regular expression. */
function globToRegExp(glob) {
  let pattern = "";
  for (let i = 0; i < glob.length; i += 1) {
    const c = glob[i];
    if (c === "*") {
      if (glob[i + 1] === "*") {
        pattern += ".*";
        i += 1;
      } else {
        pattern += "[^/]*";
      }
    } else if (c === "?") {
      pattern += "[^/]";
    } else {
      pattern += c.replace(/[.+^${}()|[\]\\]/g, "\\$&");
    }
  }
  return new RegExp(`^${pattern}$`);
}

function startClient(vscode, context, options) {
  const serverPath = options.serverPath;
  const associations = Object.entries(options.associations || {}).map(([glob, languageId]) => ({
    matcher: globToRegExp(glob),
    languageId,
    target: glob.includes("/") ? "path" : "name",
  }));
  const output = vscode.window.createOutputChannel("Grammar Workbench");
  const diagnostics = vscode.languages.createDiagnosticCollection("grammar-workbench");
  const handled = new Set();
  const pending = new Map();
  const outbox = [];
  let child = null;
  let seq = 0;
  let initialized = false;

  const isGrammarDocument = (uri) => {
    const lower = uri.fsPath.toLowerCase();
    return (
      lower.endsWith(".grammarworkbench") || lower.endsWith(".grammar") || lower.endsWith(".ebnf")
    );
  };

  // Patterns without a slash match the file name (like VS Code's own file
  // associations); patterns with a slash match the full path.
  const matchPath = (document) =>
    associations.some(({ matcher, target }) =>
      matcher.test(target === "path" ? document.uri.fsPath : path.basename(document.uri.fsPath))
    );

  const relevant = (document) => isGrammarDocument(document.uri) || matchPath(document);

  function languageIdFor(document) {
    const match = associations.find(({ matcher, target }) =>
      matcher.test(target === "path" ? document.uri.fsPath : path.basename(document.uri.fsPath))
    );
    return match ? match.languageId : document.languageId;
  }

  // MARK: - Wire protocol

  function write(message) {
    const body = JSON.stringify(message);
    child.stdin.write(`Content-Length: ${Buffer.byteLength(body)}\r\n\r\n${body}`);
  }

  function send(message) {
    if (!child) return;
    if (!initialized && message.method !== "initialize" && message.method !== "initialized") {
      outbox.push(message);
      return;
    }
    write(message);
  }

  function request(method, params) {
    return new Promise((resolve, reject) => {
      const id = ++seq;
      pending.set(id, { resolve, reject });
      send({ jsonrpc: "2.0", id, method, params });
    });
  }

  let buffer = Buffer.alloc(0);
  function onData(chunk) {
    buffer = Buffer.concat([buffer, chunk]);
    for (;;) {
      const headerEnd = buffer.indexOf("\r\n\r\n");
      if (headerEnd === -1) return;
      const header = buffer.subarray(0, headerEnd).toString();
      const match = /content-length:\s*(\d+)/i.exec(header);
      const length = match ? Number(match[1]) : 0;
      if (buffer.length < headerEnd + 4 + length) return;
      const body = JSON.parse(buffer.subarray(headerEnd + 4, headerEnd + 4 + length).toString());
      buffer = buffer.subarray(headerEnd + 4 + length);
      handleMessage(body);
    }
  }

  function handleMessage(message) {
    if (message.id !== undefined && message.id !== null) {
      const entry = pending.get(message.id);
      if (entry) {
        pending.delete(message.id);
        if (message.error) entry.reject(new Error(`${message.error.code}: ${message.error.message}`));
        else entry.resolve(message.result);
        return;
      }
      // Server-initiated requests: acknowledge work-done progress creation.
      if (message.method === "window/workDoneProgress/create") {
        send({ jsonrpc: "2.0", id: message.id, result: null });
        return;
      }
      return;
    }
    if (message.method === "$/progress") {
      output.appendLine(
        `progress ${message.params.value.kind}: ${message.params.value.message || message.params.value.title || ""}`
      );
      if (!entry) return;
      pending.delete(message.id);
      if (message.error) entry.reject(new Error(`${message.error.code}: ${message.error.message}`));
      else entry.resolve(message.result);
      return;
    }
    if (message.method === "textDocument/publishDiagnostics") {
      const uri = vscode.Uri.parse(message.params.uri);
      const items = (message.params.diagnostics || []).map((item) => {
        const diagnostic = new vscode.Diagnostic(
          rangeOf(item.range),
          item.message,
          item.severity ? item.severity - 1 : vscode.DiagnosticSeverity.Error
        );
        if (item.code !== undefined) diagnostic.code = String(item.code);
        if (item.source !== undefined) diagnostic.source = item.source;
        return diagnostic;
      });
      diagnostics.set(uri, items);
    }
  }

  const positionOf = (position) => new vscode.Position(position.line, position.character);
  const rangeOf = (range) => new vscode.Range(positionOf(range.start), positionOf(range.end));

  // The semantic token types advertised by the server (see
  // SemanticTokensProvider.legend); the client legend must match it exactly.
  const LEGEND_TYPES = [
    "keyword", "string", "number", "regexp", "comment",
    "operator", "type", "enumMember", "variable",
  ];

  function workspaceEditOf(edit) {
    const result = new vscode.WorkspaceEdit();
    for (const [uri, changes] of Object.entries(edit.changes || {})) {
      result.set(
        vscode.Uri.parse(uri),
        changes.map((change) => vscode.TextEdit.replace(rangeOf(change.range), change.newText))
      );
    }
    return result;
  }

  // MARK: - Document sync

  function openDocument(document) {
    if (handled.has(document.uri.toString())) return;
    handled.add(document.uri.toString());
    send({
      jsonrpc: "2.0",
      method: "textDocument/didOpen",
      params: {
        textDocument: {
          uri: document.uri.toString(),
          languageId: languageIdFor(document),
          version: document.version || 1,
          text: document.getText(),
        },
      },
    });
  }

  function changeDocument(event) {
    if (!handled.has(event.document.uri.toString())) return;
    send({
      jsonrpc: "2.0",
      method: "textDocument/didChange",
      params: {
        textDocument: { uri: event.document.uri.toString(), version: event.document.version },
        contentChanges: [{ text: event.document.getText() }],
      },
    });
  }

  function closeDocument(document) {
    if (!handled.has(document.uri.toString())) return;
    handled.delete(document.uri.toString());
    send({
      jsonrpc: "2.0",
      method: "textDocument/didClose",
      params: { textDocument: { uri: document.uri.toString() } },
    });
  }

  function saveDocument(document) {
    if (!handled.has(document.uri.toString())) return;
    send({
      jsonrpc: "2.0",
      method: "textDocument/didSave",
      params: { textDocument: { uri: document.uri.toString() }, text: document.getText() },
    });
  }

  // MARK: - Lifecycle

  function attach() {
    if (child) return;
    if (!fs.existsSync(serverPath)) {
      vscode.window.showErrorMessage(
        `Grammar Workbench: server not found at ${serverPath}; set grammarWorkbench.serverPath.`
      );
      return;
    }
    child = spawn(serverPath, [], { stdio: ["pipe", "pipe", "pipe"] });
    child.stdout.on("data", onData);
    child.stderr.on("data", (data) => output.appendLine(data.toString()));
    child.on("error", (error) => vscode.window.showErrorMessage(`Grammar Workbench: ${error.message}`));
    child.on("exit", (code) => {
      output.appendLine(`server exited (${code})`);
      child = null;
      initialized = false;
    });
    request("initialize", {
      processId: process.pid,
      capabilities: {},
      workspaceFolders: vscode.workspace.workspaceFolders
        ? vscode.workspace.workspaceFolders.map((folder) => ({
            uri: folder.uri.toString(),
            name: folder.name,
          }))
        : null,
    })
      .then(() => {
        initialized = true;
        send({ jsonrpc: "2.0", method: "initialized", params: {} });
        for (const message of outbox.splice(0)) write(message);
        for (const document of vscode.workspace.textDocuments) {
          if (relevant(document)) openDocument(document);
        }
      })
      .catch((error) => {
        vscode.window.showErrorMessage(`Grammar Workbench: ${error.message}`);
      });
  }

  // MARK: - Providers

  const selector = () => [
    ...new Set(["grammarworkbench", "ebnf", ...associations.map((a) => a.languageId)]),
  ];

  const providers = [
    vscode.languages.registerCompletionItemProvider(selector(), {
      provideCompletionItems(document, position) {
        if (!child) return [];
        return request("textDocument/completion", {
          textDocument: { uri: document.uri.toString() },
          position: { line: position.line, character: position.character },
        }).then((result) =>
          (result && result.items || []).map((item) => {
            const completion = new vscode.CompletionItem(
              item.label,
              item.kind !== undefined ? item.kind - 1 : vscode.CompletionItemKind.Text
            );
            if (item.detail) completion.detail = item.detail;
            if (item.sortText) completion.sortText = item.sortText;
            if (item.textEdit && item.textEdit.range && item.textEdit.newText !== undefined) {
              completion.textEdit = vscode.TextEdit.replace(
                rangeOf(item.textEdit.range),
                item.textEdit.newText
              );
            }
            return completion;
          })
        );
      },
    }),
    vscode.languages.registerHoverProvider(selector(), {
      provideHover(document, position) {
        if (!child) return null;
        return request("textDocument/hover", {
          textDocument: { uri: document.uri.toString() },
          position: { line: position.line, character: position.character },
        }).then((result) => {
          if (!result) return null;
          const value =
            result.contents && result.contents.kind === "markdown"
              ? result.contents.value
              : result.contents;
          return new vscode.Hover(new vscode.MarkdownString(value), result.range ? rangeOf(result.range) : undefined);
        });
      },
    }),
    vscode.languages.registerDefinitionProvider(selector(), {
      provideDefinition(document, position) {
        if (!child) return null;
        return request("textDocument/definition", {
          textDocument: { uri: document.uri.toString() },
          position: { line: position.line, character: position.character },
        }).then((result) => {
          const locations = Array.isArray(result) ? result : result && result.locations;
          return (locations || []).map((location) =>
            new vscode.Location(vscode.Uri.parse(location.uri), rangeOf(location.range))
          );
        });
      },
    }),
    vscode.languages.registerReferenceProvider(selector(), {
      provideReferences(document, position, context) {
        if (!child) return null;
        return request("textDocument/references", {
          textDocument: { uri: document.uri.toString() },
          position: { line: position.line, character: position.character },
          context: { includeDeclaration: context.includeDeclaration },
        }).then((locations) =>
          (locations || []).map((location) =>
            new vscode.Location(vscode.Uri.parse(location.uri), rangeOf(location.range))
          )
        );
      },
    }),
    vscode.languages.registerRenameProvider(selector(), {
      provideRenameEdits(document, position, newName) {
        if (!child) return null;
        return request("textDocument/rename", {
          textDocument: { uri: document.uri.toString() },
          position: { line: position.line, character: position.character },
          newName,
        }).then((edit) => (edit ? workspaceEditOf(edit) : null));
      },
    }),
    vscode.languages.registerCodeActionsProvider(
      selector(),
      {
        provideCodeActions(document, range, context) {
          if (!child) return [];
          return request("textDocument/codeAction", {
            textDocument: { uri: document.uri.toString() },
            range: {
              start: { line: range.start.line, character: range.start.character },
              end: { line: range.end.line, character: range.end.character },
            },
            context: {
              diagnostics: (context.diagnostics || []).map((diagnostic) => ({
                range: {
                  start: { line: diagnostic.range.start.line, character: diagnostic.range.start.character },
                  end: { line: diagnostic.range.end.line, character: diagnostic.range.end.character },
                },
                message: diagnostic.message,
              })),
            },
          }).then((result) => {
            const actions = Array.isArray(result) ? result : result && result.codeActions;
            return (actions || []).map((action) => {
              const codeAction = new vscode.CodeAction(
                action.title,
                action.kind === "quickfix" ? vscode.CodeActionKind.QuickFix : undefined
              );
              codeAction.isPreferred = action.isPreferred === true;
              if (action.diagnostics) {
                codeAction.diagnostics = action.diagnostics.map(
                  (diagnostic) =>
                    new vscode.Diagnostic(
                      rangeOf(diagnostic.range),
                      diagnostic.message,
                      diagnostic.severity ? diagnostic.severity - 1 : vscode.DiagnosticSeverity.Error
                    )
                );
              }
              if (action.edit) codeAction.edit = workspaceEditOf(action.edit);
              return codeAction;
            });
          });
        },
      },
      { providedCodeActionKinds: [vscode.CodeActionKind.QuickFix] }
    ),
    vscode.languages.registerDocumentSymbolProvider(selector(), {
      provideDocumentSymbols(document) {
        if (!child) return null;
        return request("textDocument/documentSymbol", {
          textDocument: { uri: document.uri.toString() },
        }).then((result) => {
          const symbols = Array.isArray(result) ? result : result && result.documentSymbols;
          return (symbols || []).map(symbolOf);
        });
      },
    }),
    vscode.languages.registerDocumentHighlightProvider(selector(), {
      provideDocumentHighlights(document, position) {
        if (!child) return null;
        return request("textDocument/documentHighlight", {
          textDocument: { uri: document.uri.toString() },
          position: { line: position.line, character: position.character },
        }).then((result) =>
          (result || []).map((highlight) => {
            const converted = new vscode.DocumentHighlight(rangeOf(highlight.range));
            if (highlight.kind !== undefined) converted.kind = highlight.kind - 1;
            return converted;
          })
        );
      },
    }),
    vscode.languages.registerDocumentFormattingEditProvider(selector(), {
      provideDocumentFormattingEdits(document, options) {
        if (!child) return null;
        return request("textDocument/formatting", {
          textDocument: { uri: document.uri.toString() },
          options: {
            tabSize: options.tabSize,
            insertSpaces: options.insertSpaces,
            trimTrailingWhitespace: options.trimTrailingWhitespace,
            insertFinalNewline: options.insertFinalNewline,
            trimFinalNewlines: options.trimFinalNewlines,
          },
        }).then((edits) =>
          (edits || []).map((edit) => vscode.TextEdit.replace(rangeOf(edit.range), edit.newText))
        );
      },
    }),
    vscode.languages.registerDocumentRangeFormattingEditProvider(selector(), {
      provideDocumentRangeFormattingEdits(document, range, options) {
        if (!child) return null;
        return request("textDocument/rangeFormatting", {
          textDocument: { uri: document.uri.toString() },
          range: {
            start: { line: range.start.line, character: range.start.character },
            end: { line: range.end.line, character: range.end.character },
          },
          options: {
            tabSize: options.tabSize,
            insertSpaces: options.insertSpaces,
            trimTrailingWhitespace: options.trimTrailingWhitespace,
            insertFinalNewline: options.insertFinalNewline,
            trimFinalNewlines: options.trimFinalNewlines,
          },
        }).then((edits) =>
          (edits || []).map((edit) => vscode.TextEdit.replace(rangeOf(edit.range), edit.newText))
        );
      },
    }),
    vscode.languages.registerDocumentLinkProvider(selector(), {
      provideDocumentLinks(document) {
        if (!child) return null;
        return request("textDocument/documentLink", {
          textDocument: { uri: document.uri.toString() },
        }).then((result) =>
          (result || []).map(
            (link) => new vscode.DocumentLink(rangeOf(link.range), link.target ? vscode.Uri.parse(link.target) : undefined)
          )
        );
      },
    }),
    vscode.languages.registerFoldingRangeProvider(selector(), {
      provideFoldingRanges(document) {
        if (!child) return [];
        return request("textDocument/foldingRange", {
          textDocument: { uri: document.uri.toString() },
        }).then((result) =>
          (result || []).map((range) => {
            const folding = new vscode.FoldingRange(range.startLine, range.endLine);
            if (range.startUTF16Index !== undefined) folding.startCharacter = range.startUTF16Index;
            if (range.endUTF16Index !== undefined) folding.endCharacter = range.endUTF16Index;
            return folding;
          })
        );
      },
    }),
    vscode.languages.registerDocumentSemanticTokensProvider(
      selector(),
      {
        getLegend: () => new vscode.SemanticTokensLegend(LEGEND_TYPES, []),
        provideDocumentSemanticTokens(document) {
          if (!child) return null;
          return request("textDocument/semanticTokens/full", {
            textDocument: { uri: document.uri.toString() },
          }).then((result) =>
            result ? new vscode.SemanticTokens(new Uint32Array(result.data)) : null
          );
        },
      },
      new vscode.SemanticTokensLegend(LEGEND_TYPES, [])
    ),
    vscode.languages.registerDefinitionProvider(selector(), {
      provideDefinition(document, position) {
        if (!child) return null;
        return request("textDocument/definition", {
          textDocument: { uri: document.uri.toString() },
          position: { line: position.line, character: position.character },
        }).then((result) => (result || []).map((location) =>
          new vscode.Location(vscode.Uri.parse(location.uri), rangeOf(location.range))
        ));
      },
    }),
    vscode.languages.registerCodeActionsProvider(selector(), {
      provideCodeActions(document, range, context) {
        if (!child) return [];
        return request("textDocument/codeAction", {
          textDocument: { uri: document.uri.toString() },
          range: {
            start: { line: range.start.line, character: range.start.character },
            end: { line: range.end.line, character: range.end.character },
          },
          context: { diagnostics: (context.diagnostics || []).map((diagnostic) => ({
            range: {
              start: { line: diagnostic.range.start.line, character: diagnostic.range.start.character },
              end: { line: diagnostic.range.end.line, character: diagnostic.range.end.character },
            },
            message: diagnostic.message,
          })) },
        }).then((result) => (result || []).map((item) => {
          const action = new vscode.CodeAction(item.title, vscode.CodeActionKind.QuickFix);
          action.isPreferred = item.isPreferred;
          if (item.edit && item.edit.changes) {
            const edit = new vscode.WorkspaceEdit();
            for (const [uri, edits] of Object.entries(item.edit.changes)) {
              for (const change of edits) {
                edit.replace(vscode.Uri.parse(uri), rangeOf(change.range), change.newText);
              }
            }
            action.edit = edit;
          }
          return action;
        }));
      },
    }, { providedCodeActionKinds: [vscode.CodeActionKind.QuickFix] }),
  ];

  function symbolOf(symbol) {
    const converted = new vscode.DocumentSymbol(
      symbol.name,
      symbol.detail || "",
      symbol.kind !== undefined ? symbol.kind - 1 : vscode.SymbolKind.Struct,
      rangeOf(symbol.range),
      rangeOf(symbol.selectionRange)
    );
    converted.children = (symbol.children || []).map(symbolOf);
    return converted;
  }

  function deactivate() {
    if (!child) return;
    request("shutdown", null)
      .catch(() => {})
      .finally(() => {
        send({ jsonrpc: "2.0", method: "exit", params: null });
        setTimeout(() => {
          if (child) child.kill();
        }, 2000);
      });
  }

  context.subscriptions.push(
    ...providers,
    new vscode.Disposable(() => deactivate()),
    vscode.workspace.onDidOpenTextDocument((document) => {
      attach();
      if (child && relevant(document)) openDocument(document);
    }),
    vscode.workspace.onDidChangeTextDocument(changeDocument),
    vscode.workspace.onDidCloseTextDocument(closeDocument),
    vscode.workspace.onDidSaveTextDocument(saveDocument)
  );

  return { output, diagnostics };
}

module.exports = { startClient };
