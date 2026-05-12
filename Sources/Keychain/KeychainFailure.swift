import Security

public enum KeychainFailure: Error {
    case itemNotfound
    case badStatus(OSStatus)
}
