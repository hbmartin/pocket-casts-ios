// Checked-in copy of the Intents.intentdefinition codegen (codegen disabled for the
// app target because SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor would isolate the
// generated INIntent subclasses, which SiriKit calls off-main). Classes are
// explicitly nonisolated. Regenerate by re-enabling codegen and re-copying if the
// intent definition changes.

//
// SJNextPrevious.swift
//
// This file was automatically generated and should not be edited.
//

#if canImport(Intents)

import Intents

@available(iOS 12.0, macOS 11.0, watchOS 5.0, *) @available(tvOS, unavailable)
@objc public enum SJNextPrevious: Int {
    case `unknown` = 0
    case `next` = 1
    case `previous` = 2
}

@available(iOS 13.0, macOS 11.0, watchOS 6.0, *) @available(tvOS, unavailable)
@objc(SJNextPreviousResolutionResult)
nonisolated public class SJNextPreviousResolutionResult: INEnumResolutionResult {

    // This resolution result is for when the app extension wants to tell Siri to proceed, with a given SJNextPrevious. The resolvedValue can be different than the original SJNextPrevious. This allows app extensions to apply business logic constraints.
    // Use notRequired() to continue with a 'nil' value.
    @objc(successWithResolvedNextPrevious:)
    public class func success(with resolvedValue: SJNextPrevious) -> Self {
        return __success(withResolvedValue: resolvedValue.rawValue)
    }

    // This resolution result is to ask Siri to confirm if this is the value with which the user wants to continue.
    @objc(confirmationRequiredWithNextPreviousToConfirm:)
    public class func confirmationRequired(with valueToConfirm: SJNextPrevious) -> Self {
        return __confirmationRequiredWithValue(toConfirm: valueToConfirm.rawValue)
    }
}

#endif
