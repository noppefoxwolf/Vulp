import Vulp
import SwiftUI
@_exported import Vulp_SwiftUI
@_exported import Vulp_UIKit
@_exported import Vulp_SwiftUI_Vulp_UIKit
@_exported import Vulp_AppKit

/// Explicit umbrella-module name for the timeline-driven SwiftUI image view.
public typealias AsyncImageTimelineView<Loader: MediaImageLoading, Content: View, Placeholder: View> =
    Vulp_SwiftUI.AsyncImageTimelineView<Loader, Content, Placeholder>
