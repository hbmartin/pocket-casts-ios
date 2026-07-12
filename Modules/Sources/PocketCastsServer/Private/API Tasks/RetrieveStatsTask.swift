import Foundation
import PocketCastsDataModel
import PocketCastsUtils
import SwiftProtobuf

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class RetrieveStatsTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((RemoteStats?) -> Void)?

    var getFullStatsData = false

    override func apiTokenAcquired(token: String) {
        let url = ServerConstants.Urls.api() + "user/stats/summary"

        do {
            var statsRequest = Api_StatsRequest()
            guard let uniqueAppId = ServerConfig.shared.syncDelegate?.uniqueAppId() else {
                completion?(nil)
                return
            }

            statsRequest.deviceID = getFullStatsData ? "" : uniqueAppId
            statsRequest.deviceType = ServerConstants.Values.deviceTypeiOS
            let data = try statsRequest.serializedData()

            let (response, httpStatus) = postToServer(url: url, token: token, data: data)

            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                completion?(nil)

                return
            }

            do {
                let result = try Api_StatsResponse(serializedBytes: responseData)

                let remoteStats = RemoteStats(silenceRemovalTime: result.timeSilenceRemoval,
                                              totalListenTime: result.timeListened,
                                              autoSkipTime: result.timeIntroSkipping,
                                              variableSpeedTime: result.timeVariableSpeed,
                                              skipTime: result.timeSkipping,
                                              startedStatsAt: result.timesStartedAt.seconds)
                completion?(remoteStats)
            } catch {
                FileLog.shared.addMessage("Failed to retrieve remote stats \(error.localizedDescription)")
                completion?(nil)
            }
        } catch {
            FileLog.shared.addMessage("Failed to encode remote stats \(error.localizedDescription)")
            completion?(nil)
        }
    }
}
