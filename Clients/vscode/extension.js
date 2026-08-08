"use strict";

// Grammar Workbench LSP extension entry point. The client itself lives in
// client.js and takes `vscode` as a parameter so it can be exercised by
// Scripts/m4-client-test.js with a stub.

const { startClient } = require("./client.js");
const os = require("os");
const path = require("path");

function activate(context) {
  const vscode = require("vscode");
  const config = vscode.workspace.getConfiguration("grammarWorkbench");
  let serverPath = config.get("serverPath", "${workspaceFolder}/.build/debug/grammar-workbench-lsp");
  const folders = vscode.workspace.workspaceFolders;
  serverPath = serverPath.replace(/\$\{workspaceFolder\}/g, folders && folders[0] ? folders[0].uri.fsPath : "");
  if (serverPath.startsWith("~/")) serverPath = path.join(os.homedir(), serverPath.slice(2));
  startClient(vscode, context, {
    serverPath,
    associations: config.get("associations", {}),
  });
}

function deactivate() {}

module.exports = { activate, deactivate };
