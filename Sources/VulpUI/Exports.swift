import Vulp
import SwiftUI
@_exported import Vulp_SwiftUI
@_exported import Vulp_UIKit
@_exported import Vulp_AppKit

/// Explicit umbrella-module name for the SwiftUI image view, avoiding ambiguity with SwiftUI.AsyncImage.
public typealias AsyncImage<Loader: MediaImageLoading, Content: View, Placeholder: View> =
    Vulp_SwiftUI.AsyncImage<Loader, Content, Placeholder>
