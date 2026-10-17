FROM swift:6.0-jammy AS builder
ARG SWIFT_BUILD_JOBS=2
WORKDIR /src
COPY . .
RUN swift build --force-resolved-versions --jobs "$SWIFT_BUILD_JOBS" -c release --product grammar-workbench \
 && swift build --force-resolved-versions --jobs "$SWIFT_BUILD_JOBS" -c release --product grammar-workbench-lsp \
 && swift build --force-resolved-versions --jobs "$SWIFT_BUILD_JOBS" -c release --product grammar-workbench-service
RUN mkdir -p /runtime \
 && install -m 755 .build/release/grammar-workbench /runtime/grammar-workbench \
 && install -m 755 .build/release/grammar-workbench-lsp /runtime/grammar-workbench-lsp \
 && install -m 755 .build/release/grammar-workbench-service /runtime/grammar-workbench-service \
 && Scripts/install-workbench-resources.sh .build/release /runtime

FROM swift:6.0-jammy
LABEL org.opencontainers.image.title="Grammar Workbench"
LABEL org.opencontainers.image.description="Portable Grammar Workbench CLI and language tooling"
WORKDIR /opt/grammar-workbench
COPY --from=builder /runtime/ /usr/local/bin/
ENTRYPOINT ["grammar-workbench"]
CMD ["--help"]
