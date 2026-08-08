# Compatibility and migration

## Project documents

Schema-1 projects remain readable. They default to workbench grammar notation and an empty test suite where those fields were absent. New exports use schema 2.

## Artifact interchange

Schema-1 artifact envelopes remain readable and normalize to schema 2. Consumers should validate both envelope and public API versions and should not persist state or production identifiers across grammar edits.

## Parse results

Older parse-result JSON without `syntaxTree` remains decodable. Consumers should continue accepting the rendered `tree` field while adopting structured syntax nodes.

## Generalized parsing

Generalized parsing is experimental and is not part of the stable persistence contract. Do not store its result as durable project state.

## Generated parsers

Generated parsers are dependency-free. Regenerate them when upgrading Grammar Workbench so table behavior, recovery, and semantic evaluation remain aligned with the selected release.
