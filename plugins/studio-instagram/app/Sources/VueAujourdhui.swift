import SwiftUI

// L'ancien écran « Aujourd'hui » est remplacé par le flux unique de l'Accueil (`VueAccueil`, conception/flux-unique.md).
// Gardé pour la compatibilité (personnalisations, anciens appels) : il montre simplement ce flux.
struct VueAujourdhui: View {
    var body: some View { VueAccueil() }
}
