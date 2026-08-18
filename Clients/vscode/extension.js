"use strict";

// Grammar Workbench LSP extension entry point. The client itself lives in
// client.js and takes `vscode` as a parameter so it can be exercised by
// Scripts/m4-client-test.js with a stub.

const { startClient } = require("./client.js");
const os = require("os");
const path = require("path");
const fs = require("fs");

async function activate(context) {
  const vscode = require("vscode");
  const config = vscode.workspace.getConfiguration("grammarWorkbench");
  let serverPath = config.get("serverPath", "${workspaceFolder}/.build/debug/grammar-workbench-lsp");
  const folders = vscode.workspace.workspaceFolders;
  serverPath = serverPath.replace(/\$\{workspaceFolder\}/g, folders && folders[0] ? folders[0].uri.fsPath : "");
  if (serverPath.startsWith("~/")) serverPath = path.join(os.homedir(), serverPath.slice(2));
  let associations = config.get("associations", {});
  let associationRoot = null;
  let descriptorPath = null;
  let grammarPath = null;
  let grammarAssociations = {};
  const projectFile = config.get("projectFile", ".grammar-workbench-source.json");
  if (folders && folders[0]) {
    descriptorPath = path.isAbsolute(projectFile)
      ? projectFile : path.join(folders[0].uri.fsPath, projectFile);
    if (fs.existsSync(descriptorPath)) {
      try {
        const descriptor = JSON.parse(fs.readFileSync(descriptorPath, "utf8"));
        if (descriptor.kind === "grammar-workbench-source-project") {
          associationRoot = path.dirname(descriptorPath);
          const declared = Object.fromEntries(
            (descriptor.associations || []).map((entry) => [entry.pattern, entry.languageID])
          );
          associations = { ...declared, ...associations };
          grammarPath = path.join(associationRoot, descriptor.grammar.path);
          grammarAssociations[descriptor.grammar.languageID] = vscode.Uri.file(grammarPath).toString();
        }
      } catch (error) {
        vscode.window.showErrorMessage(`Could not load Grammar Workbench source project: ${error.message}`);
      }
    }
  }
  startClient(vscode, context, {
    serverPath,
    associations,
    associationRoot,
    grammarAssociations,
  });
  if (grammarPath) {
    await vscode.workspace.openTextDocument(vscode.Uri.file(grammarPath));
  }
  context.subscriptions.push(vscode.commands.registerCommand("grammarWorkbench.openGrammar", () => {
    if (grammarPath) return vscode.commands.executeCommand("vscode.open", vscode.Uri.file(grammarPath));
    return vscode.window.showErrorMessage("No source-project grammar is configured.");
  }));
  context.subscriptions.push(vscode.commands.registerCommand("grammarWorkbench.openProjectDescriptor", () => {
    if (descriptorPath && fs.existsSync(descriptorPath)) {
      return vscode.commands.executeCommand("vscode.open", vscode.Uri.file(descriptorPath));
    }
    return vscode.window.showErrorMessage("No Grammar Workbench source-project descriptor was found.");
  }));
}

function deactivate() {}

module.exports = { activate, deactivate };
