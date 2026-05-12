//
//  PasswordRules.swift
//  VerityLabsFoundation
//
//  Created by BJ Beecher on 6/10/25.
//

public enum PasswordRule: Hashable, CaseIterable {
    case minLength
    case lowercaseChar
    case uppercaseChar
    case specialChar
    case numberChar

    public var label: String {
        switch self {
        case .minLength:
            "Contains at least 8 characters."
        case .lowercaseChar:
            "Contains at least 1 lowercase character."
        case .uppercaseChar:
            "Contains at least 1 uppercase character."
        case .specialChar:
            "Contains at least 1 special characters."
        case .numberChar:
            "Contains at least 1 number."
        }
    }

    public func validate(string: String) throws -> Bool {
        switch self {
        case .minLength:
            return string.count >= 8
        case .lowercaseChar:
            let regex = try Regex(".*[a-z]+.*")
            return string.contains(regex)
        case .uppercaseChar:
            let regex = try Regex(".*[A-Z]+.*")
            return string.contains(regex)
        case .specialChar:
            let regex = try Regex(".*[!@#$%^&*(),.?\":{}|<>]+.*")
            return string.contains(regex)
        case .numberChar:
            let regex = try Regex(".*[0-9]+.*")
            return string.contains(regex)
        }
    }

    public static func validateAll(string: String) throws -> Bool {
        var valid = true

        for rule in PasswordRule.allCases {
            valid = try rule.validate(string: string)

            if !valid {
                break
            }
        }

        return valid
    }
    
    public static func isValid(string: String) -> Bool {
        do {
            return try PasswordRule.validateAll(string: string)
        } catch {
            debugPrint(error)
            return false
        }
    }
}
