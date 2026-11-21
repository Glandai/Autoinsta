import SwiftUI

// L'app se compile avec les seuls outils en ligne de commande d'Apple (app/construire.sh), sans Xcode.
// Les macros dont le greffon n'est livré qu'avec Xcode y sont donc interdites :
//   @State → @Local (ci-dessous) ; pas de #Preview, @Previewable, @Entry, @Animatable, @AnimatableIgnored ;
//   pas de @Observable : ObservableObject + @Published (voir EtatApp).
// Vérification : xcrun swiftc -typecheck -swift-version 5 -parse-as-library \
//   -target arm64-apple-macos14.0 -module-name StudioInstagram Sources/*.swift

/// Dans le SDK macOS 27, `@State` est une macro dont le greffon n'est livré qu'avec Xcode :
/// les outils en ligne de commande ne savent pas la développer. `@Local` désigne la même
/// structure `State` (toujours un property wrapper) et se compile avec tous les SDK.
typealias Local<Valeur> = State<Valeur>
