@_exported import GrammarWorkbenchCore

/// Native compatibility façade. Portable contracts and implementations are
/// owned by `GrammarWorkbenchCore`; this module adds platform presentation.
public enum GrammarWorkbenchModule {
    public static let coreAPIVersion = GrammarWorkbenchCoreModule.apiVersion
}
