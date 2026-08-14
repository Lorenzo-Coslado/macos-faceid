// window-id — imprime l'identifiant des fenêtres à l'écran d'une app.
//
// Sert à régénérer les captures du README : `screencapture -l<id>` prend la fenêtre
// seule, sans le bureau ni les fenêtres voisines, et sans dépendre de sa position.
//
//   swiftc -O -o /tmp/window-id scripts/window-id.swift -framework CoreGraphics
//   /tmp/window-id Mugshot          → une ligne « <id>\t<largeur>x<hauteur>\t<titre> »
//
// N'exige pas l'accès à l'accessibilité : CGWindowListCopyWindowInfo est la même
// source que celle qu'utilise screencapture.
import CoreGraphics
import Foundation

let wanted = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""

guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly,
                                               .excludeDesktopElements],
                                              kCGNullWindowID) as? [[String: Any]] else {
    fputs("liste des fenêtres indisponible\n", stderr)
    exit(1)
}

var found = false
for w in windows {
    guard let owner = w[kCGWindowOwnerName as String] as? String,
          wanted.isEmpty || owner == wanted,
          let id = w[kCGWindowNumber as String] as? Int,
          let bounds = w[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? Double,
          let height = bounds["Height"] as? Double
    else { continue }
    // Les fenêtres de 1 pixel sont les artefacts des apps sans interface.
    guard width > 40, height > 40 else { continue }
    let title = w[kCGWindowName as String] as? String ?? ""
    print("\(id)\t\(Int(width))x\(Int(height))\t\(owner)\t\(title)")
    found = true
}

exit(found ? 0 : 2)
