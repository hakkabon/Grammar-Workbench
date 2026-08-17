@_exported import GrammarWorkbench

/// Platform-neutral entry point for parser, grammar, semantic, project, and
/// graph-interchange services. Native Workbench UI declarations are excluded
/// when their Apple frameworks are unavailable.
public enum GrammarWorkbenchCoreModule {
    public static let apiVersion = GrammarWorkbenchAPIVersion.current
}
