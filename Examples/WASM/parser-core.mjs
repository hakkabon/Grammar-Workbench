export const PORTABLE_RUNTIME_VERSION = 1;
export const PORTABLE_ARTIFACT_SCHEMA_VERSION = 2;
export const PORTABLE_RUNTIME_LIMITS = Object.freeze({
  maximumInputLength: 10000,
  maximumTokens: 2000,
  maximumSteps: 10000,
  maximumStackDepth: 2048
});

export class PortableRuntimeError extends Error {
  constructor(code, message, details = {}) { super(message); this.name = "PortableRuntimeError"; this.code = code; this.details = details; }
}
const fail = (code, message, details = {}) => { throw new PortableRuntimeError(code, message, details); };

export function validateSpecification(specification) {
  if (!specification || typeof specification !== "object") fail("invalid-artifact", "Parser artifact must be an object.");
  if (specification.kind !== "grammar-workbench-portable-lr") fail("unsupported-kind", `Unsupported artifact kind: ${specification.kind ?? "missing"}.`);
  if (specification.schemaVersion !== PORTABLE_ARTIFACT_SCHEMA_VERSION) fail("unsupported-schema", `Portable artifact schema ${specification.schemaVersion ?? "missing"} is unsupported.`);
  if (specification.minimumRuntimeVersion > PORTABLE_RUNTIME_VERSION) fail("unsupported-runtime", `Artifact requires runtime ${specification.minimumRuntimeVersion}.`);
  if (!Number.isSafeInteger(specification.startState) || !specification.endToken) fail("invalid-artifact", "Artifact start state or end token is invalid.");
  if (!Array.isArray(specification.tokens) || !Array.isArray(specification.productions)) fail("invalid-artifact", "Artifact tokens and productions must be arrays.");
  if (!specification.actions || !specification.gotos || !specification.limits) fail("invalid-artifact", "Artifact tables or limits are missing.");
  for (const name of ["maximumInputLength", "maximumTokens", "maximumSteps", "maximumStackDepth"]) {
    if (!Number.isSafeInteger(specification.limits[name]) || specification.limits[name] < 1 || specification.limits[name] > PORTABLE_RUNTIME_LIMITS[name]) fail("invalid-limits", `Artifact limit ${name} must be between 1 and ${PORTABLE_RUNTIME_LIMITS[name]}.`);
  }
  const productionIDs = new Set();
  for (const production of specification.productions) {
    if (!Number.isSafeInteger(production.id) || productionIDs.has(production.id) || !production.lhs || !Array.isArray(production.rhs)) fail("invalid-production", `Invalid or duplicate production ${production.id}.`);
    productionIDs.add(production.id);
  }
  for (const action of Object.values(specification.actions)) {
    if (!action || !["shift", "reduce", "accept"].includes(action.kind)) fail("invalid-action", "Artifact contains an unknown parser action.");
    if (action.kind === "reduce" && !productionIDs.has(action.production)) fail("invalid-action", `Artifact references missing production ${action.production}.`);
  }
  for (const token of specification.tokens) {
    if (!token.kind || (!token.literal && !token.pattern)) fail("invalid-token", "Every token requires a kind and matcher.");
    if (token.pattern) {
      if (!token.pattern.startsWith("^")) fail("invalid-token-pattern", `Pattern for ${token.kind} must be anchored.`);
      let expression;
      try { expression = new RegExp(token.pattern); } catch { fail("invalid-token-pattern", `Pattern for ${token.kind} is invalid.`); }
      if (expression.test("")) fail("empty-token-pattern", `Pattern for ${token.kind} matches empty input.`);
    }
  }
  return specification;
}

export function tokenize(source, specification, limits = {}) {
  validateSpecification(specification);
  if (typeof source !== "string") fail("invalid-input", "Parser input must be a string.");
  const maximumInputLength = Math.min(limits.maximumInputLength ?? Infinity, specification.limits.maximumInputLength);
  const maximumTokens = Math.min(limits.maximumTokens ?? Infinity, specification.limits.maximumTokens);
  if (source.length > maximumInputLength) fail("input-limit", `Input exceeds the ${maximumInputLength} character limit.`, { maximumInputLength });
  const result = [];
  let offset = 0;
  while (offset < source.length) {
    if (/\s/u.test(source[offset])) { offset += 1; continue; }
    let match = null;
    for (const token of specification.tokens) {
      let lexeme = null;
      if (token.literal && source.startsWith(token.literal, offset)) lexeme = token.literal;
      else if (token.pattern) lexeme = source.slice(offset).match(new RegExp(token.pattern, "u"))?.[0] ?? null;
      if (lexeme && (!match || lexeme.length > match.lexeme.length)) match = { kind: token.kind, lexeme, skip: token.skip === true };
    }
    if (!match) fail("lexical-error", `Unexpected input at offset ${offset}: ${source[offset]}`, { offset });
    if (!match.skip) result.push({ ...match, offset });
    if (result.length > maximumTokens) fail("token-limit", `Input exceeds the ${maximumTokens} token limit.`, { maximumTokens });
    offset += match.lexeme.length;
  }
  result.push({ kind: specification.endToken, lexeme: "", offset });
  return result;
}

export function parse(source, specification, options = {}) {
  validateSpecification(specification);
  const maximumSteps = Math.min(options.maximumSteps ?? Infinity, specification.limits.maximumSteps);
  const maximumStackDepth = Math.min(options.maximumStackDepth ?? Infinity, specification.limits.maximumStackDepth);
  const tokens = tokenize(source, specification, options);
  const states = [specification.startState], values = [], trace = [];
  let cursor = 0;
  for (let step = 0; step < maximumSteps; step += 1) {
    if (options.signal?.aborted) fail("cancelled", "Parse was cancelled.");
    const state = states.at(-1), lookahead = tokens[cursor];
    const action = specification.actions[`${state}|${lookahead.kind}`];
    if (!action) {
      const diagnostic = { code: "syntax-error", message: `State ${state} does not accept ${lookahead.kind}.`, offset: lookahead.offset, state, lookahead: lookahead.kind };
      return { status: "rejected", tree: null, trace, diagnostics: [diagnostic], error: diagnostic.message };
    }
    if (action.kind === "shift") {
      values.push({ symbol: lookahead.kind, lexeme: lookahead.lexeme, offset: lookahead.offset, children: [] });
      states.push(action.state); cursor += 1;
      trace.push({ step, state, lookahead: lookahead.kind, action: `shift I${action.state}`, stack: [...states] });
    } else if (action.kind === "reduce") {
      const production = specification.productions.find(item => item.id === action.production);
      if (!production) fail("invalid-action", `Missing production ${action.production}.`);
      const children = production.rhs.length ? values.splice(-production.rhs.length) : [];
      if (production.rhs.length) states.splice(-production.rhs.length);
      const target = specification.gotos[`${states.at(-1)}|${production.lhs}`];
      if (target === undefined) fail("invalid-goto", `Missing goto for ${states.at(-1)} and ${production.lhs}.`);
      values.push({ symbol: production.lhs, production: production.id, children });
      states.push(target);
      trace.push({ step, state, lookahead: lookahead.kind, action: `reduce ${production.lhs} → ${production.rhs.join(" ")}`, stack: [...states] });
    } else if (action.kind === "accept") {
      trace.push({ step, state, lookahead: lookahead.kind, action: "accept", stack: [...states] });
      return { status: "accepted", tree: values.at(-1) ?? null, trace, diagnostics: [], error: null };
    } else fail("invalid-action", `Unknown parser action ${action.kind}.`);
    if (states.length > maximumStackDepth) fail("stack-limit", `Parser exceeds the ${maximumStackDepth} state stack limit.`, { maximumStackDepth });
  }
  fail("step-limit", `Parser exceeds the ${maximumSteps} step limit.`, { maximumSteps });
}
