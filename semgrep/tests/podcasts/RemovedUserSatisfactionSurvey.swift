final class RemovedUserSatisfactionSurveyReferences {
    // ruleid: pocketcasts.no-removed-user-satisfaction-survey
    let manager = UserSatisfactionSurveyManager.shared

    // ruleid: pocketcasts.no-removed-user-satisfaction-survey
    let debugView = SurveyDebugInfoView()

    // ruleid: pocketcasts.no-removed-user-satisfaction-survey
    let trigger = SurveyTriggerEvent.folderCreated

    // ruleid: pocketcasts.no-removed-user-satisfaction-survey
    let flag = FeatureFlag.userSatisfactionSurvey

    // ok: pocketcasts.no-removed-user-satisfaction-survey
    let appStoreReviewSource = AnalyticsSource.ratingPrompt
}
