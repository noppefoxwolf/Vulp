import MediaLoader
import SwiftUI
@_exported import MediaLoader_SwiftUI
@_exported import MediaLoader_UIKit
@_exported import MediaLoader_AppKit

/// Explicit umbrella-module name for the SwiftUI image view, avoiding ambiguity with SwiftUI.AsyncImage.
public typealias AsyncImage<Loader: MediaImageLoading, Placeholder: View> =
    MediaLoader_SwiftUI.AsyncImage<Loader, Placeholder>
