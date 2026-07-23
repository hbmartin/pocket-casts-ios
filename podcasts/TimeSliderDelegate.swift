import UIKit

@MainActor
protocol TimeSliderDelegate: AnyObject {
    func sliderDidBeginSliding()
    func sliderDidEndSliding()
    func sliderDidProvisionallySlide(to time: TimeInterval)
    func sliderDidSlide(to time: TimeInterval)
    /// A Moment pin was tapped (Slice 6). Optional — defaults to a no-op.
    func sliderDidTapMoment(id: Int64)
}

extension TimeSliderDelegate {
    /// Delegates that do not present Moment comments may omit this callback.
    func sliderDidTapMoment(id _: Int64) {}
}
