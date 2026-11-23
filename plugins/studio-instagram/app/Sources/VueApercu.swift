import AVFoundation
import AppKit
import SwiftUI

// Aperçu (DESIGN.md §4.6) : revoir le post du jour à tout moment.
// Deux colonnes dans la page : le téléphone Instagram à gauche (publication ou grille du profil, clair ou sombre),
// la décision à droite dans une carte douce, puis le détail replié (légende, séquence, musique, détails).
// L'assistant de création (`VueCreation`) a sa propre étape d'aperçu : ici, on revoit et on décide.

struct VueApercu: View {
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j
    @Environment(\.openURL) private var ouvrirLien

    @Local private var telephoneSombre = false
    @Local private var vueGrille = false
    @Local private var indexMedia = 0
    @Local private var retouche = ""
    @Local private var retoucheOuverte = false
    @Local private var confirmerMaintenant = false

    /// Le téléphone tient dans la hauteur de la page (sélecteurs compris), entre 260 et 340 pt de large.
    private func largeurTelephone(pour hauteur: CGFloat) -> CGFloat {
        let disponible = hauteur - 2 * j.esp.page - j.esp.blocs - 34
        let largeur = disponible * TelephoneInstagram.largeur / TelephoneInstagram.hauteur
        return min(340, max(260, largeur))
    }

    /// Une rangée de pilules qui passe en colonne quand la place manque (jamais de chevauchement).
    private func rangeePilules<C: View>(@ViewBuilder _ contenu: () -> C) -> some View {
        let c = contenu()
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { c }
            VStack(alignment: .leading, spacing: 10) { c }
        }
    }

    var body: some View {
        Group {
            if let vue = etat.vue, let post = vue.post {
                avecPost(vue, post)
            } else if claudePreparePost {
                claudeAuTravail
            } else {
                pasDePost
            }
        }
        .animation(j.anim(.doux), value: etat.vue?.statut)
        .animation(j.anim(.doux), value: retoucheEnCours)
    }

    // MARK: - État de la journée

    private var statut: String { etat.vue?.statut ?? "nouveau" }

    /// Claude travaille sur le post de ce jour (création ou retouche).
    private var claudeSurCeJour: Bool {
        guard etat.claudeTravaille, let e = etat.execution else { return false }
        let tache = e.tacheClaude
        return (tache == .creation || tache == .retouche) && (e.jour ?? etat.jour) == etat.jour
    }

    private var claudePreparePost: Bool { claudeSurCeJour || statut == "idee_choisie" }

    /// Le post est en train d'être refait : voile sur le téléphone, actions en attente.
    private var retoucheEnCours: Bool { etat.modificationEnCours || claudeSurCeJour }

    private var verdict: Verdict? { etat.vue?.verdict }
    private var erreurs: [String] { verdict?.erreurs ?? [] }
    private var aVerifier: [String] { (verdict?.alertes ?? []) + (verdict?.avertissements ?? []) }

    private func heureCreneau(_ post: Post) -> String { etat.vue?.creneau?.nonVide ?? post.heure?.nonVide ?? "18:30" }

    // MARK: - Pas de post

    private var pasDePost: some View {
        VStack(spacing: j.esp.blocs) {
            Illustration(.apercu, taille: 230)
                .entreeEnCascade(0)
            Text("Pas encore de post pour ce jour.")
                .typo(.titre2)
                .multilineTextAlignment(.center)
                .entreeEnCascade(1)
            Text(statut == "idees_proposees"
                 ? "Trois idées t'attendent : choisis-en une, Claude prépare le post et il s'affichera ici."
                 : "Choisis d'abord une idée : Claude prépare le post et il s'affichera ici.")
                .typo(.chapo)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .fixedSize(horizontal: false, vertical: true)
                .entreeEnCascade(2)
            Button {
                etat.montrer(.idees)
            } label: {
                Label("Voir les idées", systemImage: "lightbulb")
            }
            .buttonStyle(.pilule(.claire))
            .padding(.top, j.esp.pile)
            .entreeEnCascade(3)
        }
        .padding(j.esp.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Claude prépare le post (pas encore de post)

    private var claudeAuTravail: some View {
        ScrollView {
            VStack(spacing: j.esp.blocs) {
                Illustration(.attente, taille: 200)
                Text("Claude prépare ton post.")
                    .typo(.titre1)
                    .multilineTextAlignment(.center)
                Text("Tu peux fermer l'app : elle se rouvrira quand ce sera prêt.")
                    .typo(.chapo)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                    .fixedSize(horizontal: false, vertical: true)
                if let e = etat.execution, claudeSurCeJour {
                    CarteActiviteClaude(execution: e, arreter: { Task { await etat.annulerClaude() } })
                        .frame(maxWidth: 520)
                        .padding(.top, j.esp.pile)
                } else {
                    Text("Le post s'affichera ici tout seul.")
                        .typo(.voixCarte, couleur: j.texteSecondaire)
                }
            }
            .padding(j.esp.page)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Avec un post

    private func avecPost(_ vue: VueJour, _ post: Post) -> some View {
        GeometryReader { geo in
            let largeur = largeurTelephone(pour: geo.size.height)
            ScrollView {
                HStack(alignment: .top, spacing: j.esp.sections) {
                    colonneTelephone(vue, post, largeur: largeur)
                        .frame(width: largeur)
                    VStack(alignment: .leading, spacing: j.esp.blocs) {
                        carteDecision(vue, post)
                            .entreeEnCascade(1)
                        detailsReplies(post)
                            .entreeEnCascade(2)
                    }
                    .frame(maxWidth: 560, alignment: .leading)
                }
                .frame(maxWidth: j.esp.largeurPage)
                .padding(j.esp.page)
                .frame(maxWidth: .infinity)
            }
        }
        .confirmationDialog("Publier tout de suite ?", isPresented: $confirmerMaintenant, titleVisibility: .visible) {
            Button("Publier maintenant") { Task { await etat.decider("approuver", "maintenant") } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Le post part maintenant sur Instagram, sans attendre \(heureCreneau(post)).")
        }
        .onChange(of: vue.jour) { _, _ in
            indexMedia = 0
            retouche = ""
            retoucheOuverte = false
        }
    }

    // MARK: Colonne du téléphone

    private func colonneTelephone(_ vue: VueJour, _ post: Post, largeur: CGFloat) -> some View {
        VStack(spacing: j.esp.blocs) {
            telephone(vue, post)
                .frame(width: largeur, height: largeur * TelephoneInstagram.hauteur / TelephoneInstagram.largeur)
                .overlay { if retoucheEnCours { voileActivite(largeur: largeur) } }
                .id(etat.versionImages)
                .entreeEnCascade(0)
            HStack(spacing: j.esp.pile) {
                ChoixDeux(gauche: ("Publication", "rectangle.portrait"), droite: ("Grille", "square.grid.3x3"),
                          droiteChoisie: $vueGrille)
                Spacer(minLength: 0)
                ChoixDeux(gauche: ("Clair", "sun.max"), droite: ("Sombre", "moon"), droiteChoisie: $telephoneSombre)
            }
            .frame(width: largeur)
        }
    }

    @ViewBuilder private func telephone(_ vue: VueJour, _ post: Post) -> some View {
        let contenu = contenuInstagram(vue, post)
        if vueGrille {
            TelephoneGrilleProfil(contenu: contenu, couverture: post.couverture ?? contenu.medias.first,
                                  anciennes: grilleExistante(vue), nouveau: statut != "publie",
                                  nom: post.nom?.nonVide, sombre: telephoneSombre)
        } else {
            TelephoneInstagram(contenu: contenu, sombre: telephoneSombre, index: $indexMedia)
        }
    }

    private func voileActivite(largeur: CGFloat) -> some View {
        let e = largeur / TelephoneInstagram.largeur
        let forme = RoundedRectangle(cornerRadius: j.rayons.telephone * e, style: .continuous)
        return ZStack {
            forme.fill(.ultraThinMaterial)
            forme.fill(j.remplissageCarte.opacity(0.55))
            VStack(spacing: 12) {
                ProgressView().controlSize(.regular)
                Text(etat.modificationEnCours ? "Je refais l'aperçu…" : "Claude retouche ton post…")
                    .typo(.voixCarte)
                    .multilineTextAlignment(.center)
                if let etape = etat.execution?.etapeCourante?.texte, claudeSurCeJour {
                    Text(etape)
                        .typo(.legende)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .id(etape)
                        .transition(.opacity)
                }
            }
            .padding(28)
        }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Carte de décision

    private func carteDecision(_ vue: VueJour, _ post: Post) -> some View {
        Carte(style: .heros) {
            VStack(alignment: .leading, spacing: j.esp.blocs) {
                if statut == "publie" { celebration }
                VStack(alignment: .leading, spacing: 6) {
                    Text(surTitre(vue, post)).typo(.surtitre).lineLimit(2)
                    Text(post.titre?.nonVide ?? "Le post du jour")
                        .typo(.titre2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                pastilleVerdict
                notesDuControle
                if let i = post.intention?.nonVide {
                    VoixDeClaude(i, compacte: true)
                }
                Group {
                    if retoucheEnCours {
                        attenteRetouche
                    } else {
                        actions(vue, post)
                    }
                }
                .padding(.top, j.esp.pile)
            }
        }
    }

    private func surTitre(_ vue: VueJour, _ post: Post) -> String {
        var morceaux: [String] = []
        if let f = post.format_libelle?.nonVide { morceaux.append(f) }
        if let p = post.pilier_libelle?.nonVide { morceaux.append(p) }
        return morceaux.joined(separator: " · ")
    }

    private var celebration: some View {
        HStack {
            Spacer(minLength: 0)
            Illustration(.publication, taille: 150)
            Spacer(minLength: 0)
        }
        .transition(j.transition(.apparition))
    }

    @ViewBuilder private var pastilleVerdict: some View {
        switch statut {
        case "publie":
            Pastille("Publié", symbole: "checkmark.circle.fill", ton: .succes)
        case "approuve":
            Pastille("Validé, publication prévue", symbole: "clock", ton: .succes)
        case "reporte":
            Pastille("Reporté", symbole: "pause.circle", ton: .neutre)
        case "abandonne":
            Pastille("Abandonné", symbole: "xmark.circle", ton: .neutre)
        case "echec":
            Pastille("Échec de publication", symbole: "exclamationmark.triangle.fill", ton: .alerte)
        default:
            if !erreurs.isEmpty {
                Pastille("À corriger avant publication", symbole: "exclamationmark.triangle.fill", ton: .alerte)
            } else if !aVerifier.isEmpty {
                Pastille(aVerifier.count == 1 ? "Prêt, 1 point à vérifier" : "Prêt, \(aVerifier.count) points à vérifier",
                         symbole: "eye", ton: .douce)
            } else {
                Pastille("Prêt à publier", symbole: "checkmark.circle.fill", ton: .succes)
            }
        }
    }

    /// Les notes du contrôle, avec une phrase simple qui dit quoi en faire.
    @ViewBuilder private var notesDuControle: some View {
        if statut != "publie" && (!erreurs.isEmpty || !aVerifier.isEmpty) {
            VStack(alignment: .leading, spacing: j.esp.pile + 2) {
                if !erreurs.isEmpty {
                    Text(erreurs.count == 1 ? "Une chose bloque la publication :" : "Ces points bloquent la publication :")
                        .typo(.corpsFort)
                    ListePoints(elements: erreurs, couleur: j.alerte)
                    Text("Claude peut s'en occuper : demande-lui une retouche, ou modifie le post dans l'assistant.")
                        .typo(.legende)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !aVerifier.isEmpty {
                    Text("À vérifier, sans rien bloquer :")
                        .typo(.corpsFort)
                        .padding(.top, erreurs.isEmpty ? 0 : 4)
                    ListePoints(elements: aVerifier)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: j.rayons.carte - 6, style: .continuous)
                .fill(erreurs.isEmpty ? j.fondDoux : j.fondAlerte))
        }
    }

    private var attenteRetouche: some View {
        Group {
            if let e = etat.execution, claudeSurCeJour {
                CarteActiviteClaude(execution: e, compacte: true, cadre: false,
                                    arreter: { Task { await etat.annulerClaude() } })
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Je refais la mise en page et le contrôle…").typo(.voixCarte)
                }
            }
        }
        .transition(.opacity)
    }

    // MARK: Actions selon l'état

    @ViewBuilder private func actions(_ vue: VueJour, _ post: Post) -> some View {
        switch statut {
        case "publie": actionsPublie(vue, post)
        case "approuve": actionsApprouve(vue, post)
        case "echec": actionsEchec(vue, post)
        default: actionsDecision(vue, post)
        }
    }

    private var bloqueParErreur: Bool { !erreurs.isEmpty }
    private var claudeOccupe: Bool { etat.occupe || etat.lancementEnCours || etat.claudeTravaille }

    /// Brouillon prêt (ou reporté) : publier, reporter, modifier, retoucher.
    private func actionsDecision(_ vue: VueJour, _ post: Post) -> some View {
        let heure = heureCreneau(post)
        return VStack(alignment: .leading, spacing: j.esp.blocs) {
            if statut == "reporte" {
                Text("Reporté. Rien ne part aujourd'hui ; tu peux le reprendre quand tu veux.")
                    .typo(.corps, couleur: j.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    Task { await etat.decider("approuver", "creneau") }
                } label: {
                    Label("Publier à \(heure)", systemImage: "paperplane")
                }
                .buttonStyle(BoutonPrincipal(pleineLargeur: true, enCours: etat.occupe))
                .keyboardShortcut(.defaultAction)
                .disabled(bloqueParErreur || etat.occupe)
                if let raison = erreurs.first {
                    Label {
                        Text("Pas encore possible : \(raison)").typo(.legende)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "lock").foregroundStyle(j.alerte)
                    }
                } else {
                    Text("Rien ne part sans ce clic. Tu pourras encore reporter.")
                        .typo(.legende)
                }
            }
            rangeePilules {
                Button {
                    confirmerMaintenant = true
                } label: {
                    Label("Publier maintenant…", systemImage: "bolt")
                }
                .buttonStyle(.pilule(.claire))
                .disabled(bloqueParErreur || etat.occupe)
                if statut != "reporte" {
                    Button {
                        Task { await etat.decider("reporter") }
                    } label: {
                        Label("Reporter", systemImage: "calendar.badge.clock")
                    }
                    .buttonStyle(.pilule(.claire))
                    .disabled(etat.occupe)
                }
            }
            Filet()
            rangeePilules {
                Button {
                    etat.montrer(.creation)
                } label: {
                    Label("Modifier dans l'assistant", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.pilule(.claire))
                .disabled(etat.occupe)
                if !retoucheOuverte {
                    Button {
                        withAnimation(j.anim(.doux)) { retoucheOuverte = true }
                    } label: {
                        Label("Demander une retouche", systemImage: "sparkles")
                    }
                    .buttonStyle(.pilule(.claire))
                }
            }
            if retoucheOuverte { zoneRetouche }
        }
    }

    /// Validé : l'heure de départ, reporter, et une retouche possible.
    private func actionsApprouve(_ vue: VueJour, _ post: Post) -> some View {
        VStack(alignment: .leading, spacing: j.esp.blocs) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "clock.fill").foregroundStyle(j.succes)
                Text("Validé. Il partira \(quandPartira(vue, post)).")
                    .typo(.titre3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Tu n'as plus rien à faire : le studio publie tout seul, même app fermée.")
                .typo(.corps, couleur: j.texteSecondaire)
                .fixedSize(horizontal: false, vertical: true)
            rangeePilules {
                Button {
                    Task { await etat.decider("reporter") }
                } label: {
                    Label("Reporter", systemImage: "calendar.badge.clock")
                }
                .buttonStyle(.pilule(.claire))
                .disabled(etat.occupe)
                if !retoucheOuverte {
                    Button {
                        withAnimation(j.anim(.doux)) { retoucheOuverte = true }
                    } label: {
                        Label("Demander une retouche", systemImage: "sparkles")
                    }
                    .buttonStyle(.pilule(.claire))
                }
            }
            if retoucheOuverte { zoneRetouche }
        }
    }

    /// Publié : lien Instagram, rappel pour la musique.
    private func actionsPublie(_ vue: VueJour, _ post: Post) -> some View {
        VStack(alignment: .leading, spacing: j.esp.blocs) {
            Text("C'est en ligne !").typo(.titre3)
            if let l = vue.permalink?.nonVide, let url = URL(string: l) {
                Button {
                    ouvrirLien(url)
                } label: {
                    Label("Voir sur Instagram", systemImage: "arrow.up.right")
                }
                .buttonStyle(BoutonPrincipal())
                .keyboardShortcut(.defaultAction)
            }
            if post.musique?.mode == "a_ajouter_dans_l_app", let t = post.musique?.titre {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "music.note")
                        .foregroundStyle(j.aToi)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(j.fondDoux))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Dernière touche : la musique").typo(.corpsFort)
                        Text("Instagram ne laisse pas le studio l'ajouter. Dans l'app Instagram, sur le post : ••• puis Modifier, puis Ajouter de la musique, et cherche « \([t, post.musique?.artiste].compactMap { $0 }.joined(separator: " · ")) ».")
                            .typo(.corps, couleur: j.texteSecondaire)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    /// Échec : la raison, réessayer (confirmé), reporter, retoucher.
    private func actionsEchec(_ vue: VueJour, _ post: Post) -> some View {
        VStack(alignment: .leading, spacing: j.esp.blocs) {
            Text(vue.erreur?.nonVide.map { "La publication n'est pas passée : \($0)" }
                 ?? "La publication n'est pas passée. Rien n'est perdu : ton post t'attend ici.")
                .typo(.corps)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Button {
                confirmerMaintenant = true
            } label: {
                Label("Réessayer maintenant…", systemImage: "arrow.clockwise")
            }
            .buttonStyle(BoutonPrincipal(pleineLargeur: true, enCours: etat.occupe))
            .keyboardShortcut(.defaultAction)
            .disabled(bloqueParErreur || etat.occupe)
            rangeePilules {
                Button {
                    Task { await etat.decider("approuver", "creneau") }
                } label: {
                    Label("Publier à \(heureCreneau(post))", systemImage: "clock")
                }
                .buttonStyle(.pilule(.claire))
                .disabled(bloqueParErreur || etat.occupe)
                Button {
                    Task { await etat.decider("reporter") }
                } label: {
                    Label("Reporter", systemImage: "calendar.badge.clock")
                }
                .buttonStyle(.pilule(.claire))
                .disabled(etat.occupe)
            }
            if retoucheOuverte {
                zoneRetouche
            } else {
                Button {
                    withAnimation(j.anim(.doux)) { retoucheOuverte = true }
                } label: {
                    Label("Demander une retouche", systemImage: "sparkles")
                }
                .buttonStyle(.discret)
            }
        }
    }

    private var zoneRetouche: some View {
        let texte = retouche.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Changer quelque chose ?").typo(.corpsFort)
            ChampDoux(texte: $retouche,
                      exemple: "Une photo, l'ordre, un mot de la légende… dis-le simplement.",
                      lignes: 2...6)
            HStack {
                Button("Annuler") {
                    withAnimation(j.anim(.doux)) {
                        retoucheOuverte = false
                        retouche = ""
                    }
                }
                .buttonStyle(.discret)
                Spacer(minLength: 0)
                Button {
                    Task {
                        await etat.decider("retouche", texte)
                        retouche = ""
                        retoucheOuverte = false
                    }
                } label: {
                    Label("Demander la retouche", systemImage: "sparkles")
                }
                .buttonStyle(.pilule(.sombre))
                .disabled(texte.isEmpty || claudeOccupe)
            }
        }
        .transition(j.transition(.apparition))
    }

    // MARK: - Détails repliés

    private func detailsReplies(_ post: Post) -> some View {
        let legende = post.legende ?? ""
        let caracteres = verdict?.caracteres ?? legende.count
        let medias = post.medias ?? []
        return VStack(alignment: .leading, spacing: j.esp.pile + 4) {
            SectionRepliee(titre: "Légende", symbole: "text.quote",
                           resume: "\(caracteres.formatted()) / 2 200") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(legende.nonVide ?? "Pas encore de légende.")
                        .typo(.corps)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    CompteurLegende(caracteres: caracteres)
                }
            }
            if !medias.isEmpty {
                SectionRepliee(titre: "Séquence", symbole: "square.stack",
                               resume: medias.count == 1 ? "1 image" : "\(medias.count) images") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(medias) { m in
                            ligneMedia(m)
                            if m.ordre < (medias.last?.ordre ?? 0) { Filet() }
                        }
                    }
                }
            }
            if let m = post.musique, m.titre != nil || m.direction_sonore != nil || m.mode != nil {
                SectionRepliee(titre: "Musique", symbole: "music.note",
                               resume: m.titre ?? Musique.libelleMode(m.mode)) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let t = m.titre {
                            Text([t, m.artiste].compactMap { $0 }.joined(separator: " · ")).typo(.corpsFort)
                        }
                        Text(Musique.libelleMode(m.mode)).typo(.legende)
                        if let d = m.direction_sonore?.nonVide {
                            VoixDeClaude(d, filet: false, compacte: true)
                        }
                        if m.mode == "a_ajouter_dans_l_app" {
                            Text("Instagram ne permet pas au studio d'ajouter la musique à ce format : tu l'ajouteras dans l'app après la publication.")
                                .typo(.legende)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let a = m.apercu_url, let url = URL(string: a) {
                            Button {
                                ouvrirLien(url)
                            } label: {
                                Label("Écouter un extrait", systemImage: "play.circle")
                            }
                            .buttonStyle(.pilule(.claire, taille: .petite))
                        }
                    }
                }
            }
            SectionRepliee(titre: "Détails", symbole: "list.bullet", resume: nil) {
                VStack(alignment: .leading, spacing: 8) {
                    ligneDetail("Format", post.format_libelle)
                    ligneDetail("Pilier", post.pilier_libelle)
                    ligneDetail("Série", post.serie)
                    ligneDetail("Lieu", post.localisation)
                    ligneDetail("Avec", (post.collaborateurs ?? []).map { "@\($0)" }.joined(separator: ", "))
                    ligneDetail("Hashtags", (post.hashtags ?? []).joined(separator: " "))
                    ligneDetail("Longueur", post.longueur_legende)
                    if let p = post.pourquoi?.nonVide {
                        Text("Pourquoi ce post").typo(.surtitre).padding(.top, 4)
                        VoixDeClaude(p, filet: false, compacte: true)
                    }
                }
            }
        }
    }

    private func ligneMedia(_ m: MediaPost) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ImageLocale(chemin: m.image)
                .frame(width: 52, height: 65)
                .clipShape(RoundedRectangle(cornerRadius: j.rayons.photo, style: .continuous))
                .id(etat.versionImages)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(m.ordre)").typo(.corpsFort)
                    Text(libelleRole(m.role)).typo(.corpsFort)
                    Text(m.presentation == "marges" ? "· sur fond" : "· plein cadre").typo(.legende)
                }
                if let ids = m.identifications?.filter({ !$0.isEmpty }), !ids.isEmpty {
                    Text("Identifie @" + ids.joined(separator: ", @")).typo(.legende)
                }
                if let alt = m.texte_alternatif?.nonVide {
                    Text(alt).typo(.legende).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private func ligneDetail(_ cle: String, _ valeur: String?) -> some View {
        if let v = valeur?.nonVide {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(cle).typo(.legende).frame(width: 90, alignment: .leading)
                Text(v).typo(.corps).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }
    }

    private func libelleRole(_ r: String?) -> String {
        switch r {
        case "ouverture": return "Ouverture"
        case "progression": return "Progression"
        case "respiration": return "Respiration"
        case "surprise": return "Surprise"
        case "cloture": return "Clôture"
        default: return r?.capitalized ?? "Image"
        }
    }

    // MARK: - Données du téléphone

    private func contenuInstagram(_ vue: VueJour, _ post: Post) -> ContenuInstagram {
        let format = FormatInstagram(post.format)
        let images = (post.medias ?? []).compactMap { $0.image }
        let musique = post.musique?.titre.map { t in [t, post.musique?.artiste].compactMap { $0 }.joined(separator: " · ") }
        return ContenuInstagram(
            compte: post.compte?.nonVide ?? "mon.studio",
            collaborateurs: post.collaborateurs ?? [],
            lieu: post.localisation?.nonVide,
            musique: musique,
            medias: images,
            format: format,
            legende: post.legende ?? "",
            date: nil,
            heure: heureCreneau(post))
    }

    /// Les couvertures déjà publiées (la plus récente d'abord). Une fois publié, le post du jour y est déjà :
    /// `TelephoneGrilleProfil(nouveau:)` ne le rajoute alors pas.
    private func grilleExistante(_ vue: VueJour) -> [String?] { vue.grille ?? [] }

    private func quandPartira(_ vue: VueJour, _ post: Post) -> String {
        if let p = vue.publier_a, let texte = FormatsApercu.quand(p) { return texte }
        return "à \(heureCreneau(post))"
    }
}

// MARK: - Petits composants de l'Aperçu

/// Deux pilules petites côte à côte : la choisie est sombre, l'autre claire.
private struct ChoixDeux: View {
    let gauche: (String, String)
    let droite: (String, String)
    @Binding var droiteChoisie: Bool
    @Environment(\.jetons) private var j

    var body: some View {
        HStack(spacing: 4) {
            bouton(gauche, choisi: !droiteChoisie) { droiteChoisie = false }
            bouton(droite, choisi: droiteChoisie) { droiteChoisie = true }
        }
        .accessibilityElement(children: .contain)
    }

    private func bouton(_ o: (String, String), choisi: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(j.anim(.selection)) { action() }
        } label: {
            Label(o.0, systemImage: o.1)
        }
        .buttonStyle(.pilule(choisi ? .sombre : .claire, taille: .petite))
        .accessibilityAddTraits(choisi ? .isSelected : [])
    }
}

/// Section repliée dans une carte douce : en-tête cliquable (symbole, titre, résumé, chevron), contenu dessous.
private struct SectionRepliee<Contenu: View>: View {
    let titre: String
    let symbole: String
    let resume: String?
    @ViewBuilder let contenu: () -> Contenu
    @Environment(\.jetons) private var j
    @Local private var ouvert = false

    var body: some View {
        let forme = RoundedRectangle(cornerRadius: j.rayons.carte, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(j.anim(.doux)) { ouvert.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: symbole)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(j.texte)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(j.fondDoux))
                    Text(titre).typo(.corpsFort)
                    Spacer(minLength: 8)
                    if let r = resume {
                        Text(r).typo(.legende).lineLimit(1)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(j.texteSecondaire)
                        .rotationEffect(.degrees(ouvert ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(resume.map { "\(titre), \($0)" } ?? titre)
            .accessibilityHint(ouvert ? "Replier" : "Déplier")
            if ouvert {
                contenu()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .padding(.top, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .background(forme.fill(j.remplissageCarte))
        .overlay(LisereHaut(rayon: j.rayons.carte))
        .overlay(forme.strokeBorder(j.systeme.augmenterContraste ? j.traitFort : Color.clear, lineWidth: 1))
        .clipShape(forme)
        .ombre(.carte)
    }
}

/// « 642 / 2 200 » et une barre fine ; alerte au-delà de la limite d'Instagram.
private struct CompteurLegende: View {
    let caracteres: Int
    @Environment(\.jetons) private var j
    private let limite = 2200

    var body: some View {
        let trop = caracteres > limite
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(j.trait)
                    Capsule().fill(trop ? j.alerte : j.accent)
                        .frame(width: geo.size.width * min(1, CGFloat(caracteres) / CGFloat(limite)))
                }
            }
            .frame(height: 4)
            Text(trop ? "\(caracteres.formatted()) / 2 200 caractères : trop long pour Instagram"
                      : "\(caracteres.formatted()) / 2 200 caractères")
                .typo(.legende, couleur: trop ? j.alerte : nil)
                .monospacedDigit()
        }
    }
}

// MARK: - Téléphones maison : grille du profil et Reel en vidéo

/// Le boîtier du téléphone, identique à celui de `TelephoneInstagram` (395 × 832, écran 375 × 812).
private struct BoitierTelephone<Ecran: View>: View {
    let sombre: Bool
    let heure: String
    var barreClaire = false
    @ViewBuilder let ecran: () -> Ecran
    @Environment(\.jetons) private var j

    static var largeurEcran: CGFloat { 375 }
    static var hauteurEcran: CGFloat { 812 }

    var body: some View {
        GeometryReader { geo in
            let e = min(geo.size.width / TelephoneInstagram.largeur, geo.size.height / TelephoneInstagram.hauteur)
            boitier
                .frame(width: TelephoneInstagram.largeur, height: TelephoneInstagram.hauteur)
                .scaleEffect(e)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(TelephoneInstagram.largeur / TelephoneInstagram.hauteur, contentMode: .fit)
    }

    private var boitier: some View {
        let ig = CouleursInstagram(sombre: sombre)
        return ZStack {
            RoundedRectangle(cornerRadius: j.rayons.telephone, style: .continuous)
                .fill(Color(red: 0.106, green: 0.106, blue: 0.114))
                .overlay(RoundedRectangle(cornerRadius: j.rayons.telephone, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1.5))
            ZStack(alignment: .top) {
                ig.fond
                ecran()
                barreEtat(barreClaire ? Color.white : ig.texte)
            }
            .frame(width: Self.largeurEcran, height: Self.hauteurEcran)
            .clipShape(RoundedRectangle(cornerRadius: j.rayons.ecranTelephone, style: .continuous))
            .environment(\.colorScheme, sombre ? .dark : .light)
            .symbolVariant(.none)
        }
        .ombre(.feuille)
    }

    private func barreEtat(_ couleur: Color) -> some View {
        ZStack(alignment: .top) {
            HStack {
                Text(heure).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "cellularbars")
                    Image(systemName: "wifi")
                    Image(systemName: "battery.100")
                }
                .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(couleur)
            .padding(.horizontal, 30)
            .padding(.top, 17)
            Capsule().fill(Color.black).frame(width: 120, height: 34).padding(.top, 11)
        }
        .frame(height: 54, alignment: .top)
        .accessibilityHidden(true)
    }
}

/// La grille du profil : le nouveau post en première case, puis les couvertures déjà publiées.
private struct TelephoneGrilleProfil: View {
    let contenu: ContenuInstagram
    let couverture: String?
    let anciennes: [String?]
    /// Vrai tant que le post n'est pas publié (il n'est pas encore dans `anciennes`).
    let nouveau: Bool
    let nom: String?
    let sombre: Bool
    @Environment(\.jetons) private var j

    private let largeur: CGFloat = 375

    var body: some View {
        BoitierTelephone(sombre: sombre, heure: contenu.heure) {
            ecran
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(nouveau ? "Grille du profil : ton nouveau post en premier, puis \(anciennes.count) publications"
                                    : "Grille du profil")
    }

    private var ecran: some View {
        let ig = CouleursInstagram(sombre: sombre)
        let colonnes = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
        let cases: [String?] = nouveau ? [couverture] + anciennes : anciennes
        let total = max(12, cases.count + (3 - cases.count % 3) % 3)
        return VStack(spacing: 0) {
            Color.clear.frame(height: 54)
            HStack(spacing: 6) {
                Image(systemName: "lock").font(.system(size: 13, weight: .semibold)).hidden()
                Text(contenu.compteCourt).font(.system(size: 20, weight: .bold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                Spacer()
                Image(systemName: "plus.app").font(.system(size: 22))
                Image(systemName: "line.3.horizontal").font(.system(size: 22)).padding(.leading, 14)
            }
            .foregroundStyle(ig.texte)
            .padding(.horizontal, 14)
            .frame(height: 44)
            HStack(spacing: 18) {
                ZStack {
                    Circle().fill(j.accent)
                    Text(contenu.initiales).font(.system(size: 30, weight: .semibold)).foregroundStyle(j.surAccent)
                }
                .frame(width: 84, height: 84)
                Spacer(minLength: 0)
                chiffre("\(cases.filter { $0 != nil }.count)", "publications", ig)
                chiffre("—", "followers", ig)
                chiffre("—", "suivi(e)s", ig)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                if let n = nom { Text(n).font(.system(size: 14, weight: .semibold)) }
                Text("Photographe").font(.system(size: 14)).foregroundStyle(ig.secondaire)
            }
            .foregroundStyle(ig.texte)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            HStack(spacing: 0) {
                onglet("square.grid.3x3", actif: true, ig)
                onglet("play.rectangle", actif: false, ig)
                onglet("person.crop.square", actif: false, ig)
            }
            .padding(.top, 14)
            LazyVGrid(columns: colonnes, spacing: 2) {
                ForEach(0..<total, id: \.self) { i in
                    caseGrille(i < cases.count ? cases[i] : nil, premiere: nouveau && i == 0, ig)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func chiffre(_ valeur: String, _ libelle: String, _ ig: CouleursInstagram) -> some View {
        VStack(spacing: 1) {
            Text(valeur).font(.system(size: 16, weight: .semibold)).monospacedDigit()
            Text(libelle).font(.system(size: 13))
        }
        .foregroundStyle(ig.texte)
        .frame(minWidth: 70)
    }

    private func onglet(_ symbole: String, actif: Bool, _ ig: CouleursInstagram) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbole).font(.system(size: 20))
                .foregroundStyle(actif ? ig.texte : ig.secondaire)
            Rectangle().fill(actif ? ig.texte : Color.clear).frame(height: 1)
        }
        .frame(maxWidth: .infinity)
    }

    private func caseGrille(_ chemin: String?, premiere: Bool, _ ig: CouleursInstagram) -> some View {
        let cote = (largeur - 4) / 3
        return ZStack(alignment: .bottomLeading) {
            if chemin != nil || premiere {
                ImageLocale(chemin: chemin)
            } else {
                Rectangle().fill(ig.separateur.opacity(0.5))
            }
            if premiere {
                Text("Nouveau")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(j.surAccent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(j.accent))
                    .padding(6)
            }
        }
        .frame(width: cote, height: cote * 4 / 3)
        .clipped()
        .overlay(premiere ? Rectangle().strokeBorder(j.accent, lineWidth: 2) : nil)
    }
}

// MARK: - Dates

private enum FormatsApercu {
    private static let locale = Locale(identifier: "fr_FR")

    private static func formateur(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = .current
        f.dateFormat = format
        return f
    }

    /// « 2026-11-19 » → « 19 novembre ».
    static func dateCourte(_ jour: String) -> String? {
        guard let d = formateur("yyyy-MM-dd").date(from: String(jour.prefix(10))) else { return nil }
        return formateur("d MMMM").string(from: d)
    }

    /// « 2026-11-19T18:30 » → « aujourd'hui à 18:30 », « demain à 18:30 » ou « jeudi 19 novembre à 18:30 ».
    static func quand(_ iso: String) -> String? {
        let texte = String(iso.prefix(16))
        guard let d = formateur("yyyy-MM-dd'T'HH:mm").date(from: texte) else { return nil }
        let heure = formateur("HH:mm").string(from: d)
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "aujourd'hui à \(heure)" }
        if cal.isDateInTomorrow(d) { return "demain à \(heure)" }
        return "\(formateur("EEEE d MMMM").string(from: d)) à \(heure)"
    }
}

extension String {
    /// Le texte, ou `remplacement` s'il est vide (utilisé aussi par Galeries).
    func ifEmpty(_ remplacement: String) -> String { isEmpty ? remplacement : self }
}
