import SwiftUI

/// L'ancien écran « Nouveau post » : la création se fait maintenant dans l'accueil, en un seul flux
/// (`VueAccueil`, conception/flux-unique.md). Gardé pour le routage de l'écran `creation`.
struct VueCreation: View {
    var body: some View { VueAccueil() }
}
