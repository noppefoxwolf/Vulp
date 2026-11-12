#if canImport(UIKit)
import UIKit

extension AsyncImageView {
    func updateLayerGravity() {
        let gravity = contentsGravity(for: contentMode)
        guard layer.contentsGravity != gravity else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contentsGravity = gravity
        CATransaction.commit()
    }

    private func contentsGravity(for contentMode: UIView.ContentMode) -> CALayerContentsGravity {
        switch contentMode {
        case .scaleToFill, .redraw:
            .resize
        case .scaleAspectFit:
            .resizeAspect
        case .scaleAspectFill:
            .resizeAspectFill
        case .center:
            .center
        default:
            .resizeAspect
        }
    }
}
#endif
