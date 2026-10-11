import SwiftUI

/// Point at `radius` from `center`, `degrees` clockwise from straight up.
func radarPoint(_ center: CGPoint, _ radius: CGFloat, _ degrees: Double) -> CGPoint {
    let r = degrees * .pi / 180
    return CGPoint(x: center.x + radius * sin(r), y: center.y - radius * cos(r))
}
