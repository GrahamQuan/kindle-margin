import Foundation
import KindleDomain

public enum ImportDecision: Equatable, Sendable {
    case directTransfer(format: String)
    case conversionRequired(input: String, output: String)
    case unavailable(reason: String)
}
public struct ImportPlanner: Sendable {
    public init() {}
    public func plan(detectedFormat: String?, structurallyValid: Bool, protected: Bool?, verifiedDeviceFormats: Set<String>, converterInputs: Set<String>) -> ImportDecision {
        guard let format = detectedFormat, structurallyValid else { return .unavailable(reason: "The file format or structure could not be verified.") }
        guard protected == false else { return .unavailable(reason: protected == true ? "Protected content cannot be converted." : "Content protection status could not be established.") }
        if verifiedDeviceFormats.contains(format) { return .directTransfer(format: format) }
        if ["epub", "docx", "html", "rtf"].contains(format), verifiedDeviceFormats.contains("azw3") {
            guard converterInputs.contains(format) else { return .unavailable(reason: "Select and validate a compatible local Calibre converter in Settings.") }
            return .conversionRequired(input: format, output: "azw3")
        }
        return .unavailable(reason: "This format is not verified for the target device.")
    }
}
