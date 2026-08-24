# Language documentation pipeline

Phase 39 turns a compiled grammar into a reproducible language reference rather
than extending the engineering-oriented artifact report. The pipeline has one
versioned semantic manifest and deterministic Markdown and HTML renderers.

## Documentation manifest

`GrammarLanguageDocumentationPipeline.build` combines the parsed grammar with
the Phase 35 structural exploration data. Its Codable schema records:

- title, source fingerprint, start rule, and terminals;
- stable rule anchors and production identities;
- production symbols classified as terminals or nonterminals;
- source ranges, incoming and outgoing references, FIRST and FOLLOW sets;
- start, reachability, productivity, nullability, and recursion status.

The manifest contains no timestamps or filesystem paths. Equal source and
options therefore produce equal values and byte-stable sorted-key JSON.
`validate`, `encode`, and `decode` reject unsupported schemas, duplicate rule or
anchor identities, missing start rules, and unresolved symbol links.

## Publication formats

Markdown output contains a linked rule index, ASCII railroad diagrams,
productions and source lines, dependency links, and grammar facts. Standalone
HTML contains the same information with responsive navigation, escaped content,
accessible diagram labels, and SVG railroad diagrams generated through
Grammar-DiagramKit 0.1.0. Diagrams can be disabled for compact or text-only
publication.

`LanguageDocumentationGrammarGenerator` is registered as the built-in
`language-documentation` generator. Its `format` option accepts `html`,
`markdown`, `json`, or `bundle`; a bundle produces `LanguageReference.html`,
`LanguageReference.md`, and `LanguageReference.json`. `title` and `diagrams`
control presentation without changing grammar semantics.

## Deliberate limits

Phase 39 documents grammar structure. It does not infer prose descriptions from
comments, execute sample programmes, publish to a remote site, or invent a
semantic type reference. Future language-kit metadata can supply authored rule
descriptions, examples, deprecation state, and semantic API links while keeping
this manifest and validation boundary reproducible.
