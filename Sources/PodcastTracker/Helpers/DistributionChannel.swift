enum DistributionChannel {
    #if os(iOS)
    static let isAppStore = false
    static let allowsExternalMediaTools = true
    #elseif APP_STORE
    static let isAppStore = true
    static let allowsExternalMediaTools = false
    #else
    static let isAppStore = false
    static let allowsExternalMediaTools = true
    #endif
}
