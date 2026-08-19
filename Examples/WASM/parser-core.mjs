export function tokenize(source, specification) {
  const result = [];
  let offset = 0;
  while (offset < source.length) {
    if (/\s/.test(source[offset])) { offset += 1; continue; }
    let match = null;
    for (const token of specification.tokens) {
      if (token.literal && source.startsWith(token.literal, offset)) {
        match = { kind: token.kind, lexeme: token.literal };
      } else if (token.pattern) {
        const value = source.slice(offset).match(new RegExp(token.pattern))?.[0];
        if (value && (!match || value.length > match.lexeme.length)) match = { kind: token.kind, lexeme: value };
      }
    }
    if (!match) throw new Error(`Unexpected input at offset ${offset}: ${source[offset]}`);
    result.push({ ...match, offset });
    offset += match.lexeme.length;
  }
  result.push({ kind: specification.endToken, lexeme: "", offset });
  return result;
}

export function parse(source, specification) {
  const tokens = tokenize(source, specification);
  const states = [specification.startState], values = [], trace = [];
  let cursor = 0;
  for (let step = 0; step < 10000; step += 1) {
    const state = states.at(-1), lookahead = tokens[cursor];
    const action = specification.actions[`${state}|${lookahead.kind}`];
    if (!action) {
      return { status: "rejected", tree: null, trace, error: `State ${state} does not accept ${lookahead.kind}.` };
    }
    if (action.kind === "shift") {
      values.push({ symbol: lookahead.kind, lexeme: lookahead.lexeme, children: [] });
      states.push(action.state); cursor += 1;
      trace.push({ step, state, lookahead: lookahead.kind, action: `shift I${action.state}`, stack: [...states] });
    } else if (action.kind === "reduce") {
      const production = specification.productions.find(item => item.id === action.production);
      if (!production) throw new Error(`Missing production ${action.production}.`);
      const children = production.rhs.length ? values.splice(-production.rhs.length) : [];
      if (production.rhs.length) states.splice(-production.rhs.length);
      const target = specification.gotos[`${states.at(-1)}|${production.lhs}`];
      if (target === undefined) throw new Error(`Missing goto for ${states.at(-1)} and ${production.lhs}.`);
      values.push({ symbol: production.lhs, production: production.id, children });
      states.push(target);
      trace.push({ step, state, lookahead: lookahead.kind, action: `reduce ${production.lhs} → ${production.rhs.join(" ")}`, stack: [...states] });
    } else if (action.kind === "accept") {
      trace.push({ step, state, lookahead: lookahead.kind, action: "accept", stack: [...states] });
      return { status: "accepted", tree: values.at(-1) ?? null, trace, error: null };
    }
  }
  throw new Error("Portable parser exceeded its step limit.");
}
