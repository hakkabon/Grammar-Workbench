FROM swift:6.0-jammy AS builder
WORKDIR /src
COPY . .
RUN Scripts/prepare-portable-dependencies.sh \
 && swift build -c release --product grammar-workbench \
 && swift build -c release --product grammar-workbench-lsp \
 && swift build -c release --product grammar-workbench-service

FROM swift:6.0-jammy
LABEL org.opencontainers.image.title="Grammar Workbench"
LABEL org.opencontainers.image.description="Portable Grammar Workbench CLI and language tooling"
WORKDIR /opt/grammar-workbench
COPY --from=builder /src/.build/release/grammar-workbench /usr/local/bin/grammar-workbench
COPY --from=builder /src/.build/release/grammar-workbench-lsp /usr/local/bin/grammar-workbench-lsp
COPY --from=builder /src/.build/release/grammar-workbench-service /usr/local/bin/grammar-workbench-service
COPY --from=builder /src/.build/release/GrammarWorkbench_GrammarWorkbench.resources /usr/local/bin/GrammarWorkbench_GrammarWorkbench.resources
ENTRYPOINT ["grammar-workbench"]
CMD ["--help"]
