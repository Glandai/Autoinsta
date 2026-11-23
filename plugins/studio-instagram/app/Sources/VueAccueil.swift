import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

// Accueil = création d'un post, en un seul flux (conception/flux-unique.md, 23/11). Cinq temps, une chose à la fois :
//   1. Les idées : trois cartes en éventail (deck), un brief d'une phrase ; dessous, une barre pour son propre brief.
//   2. Les photos : fichiers ou dossier du Mac (sélecteur, glisser-déposer) ou lien Pic-Time → `ajouter-source`,
//      puis Claude crée le post avec ces photos.
//   3. La génération : barre de chargement et phrase de l'étape en cours.
//   4. L'aperçu : le post comme sur Instagram, ses détails, et « Dis à Claude ce qu'il faut changer… ».
//   5. Finaliser : télécharger les fichiers, ou publier en un clic (confirmé).
// Le temps affiché se déduit du statut du jour (reprise au bon endroit). Rien n'est publié sans son clic.

struct VueAccueil: View {
    @EnvironmentObject var etat: EtatApp
    @EnvironmentObject var coque: CoqueStudio
    @Environment(\.jetons) private var j

    private enum Temps: Int, Comparable {
        case idees, photos, generation, apercu, finaliser
        static func < (a: Temps, b: Temps) -> Bool { a.rawValue < b.rawValue }
    }

    @Local private var changerIdee = false
    /// Étape choisie par la photographe (points du bas, ou demande d'un autre écran) : prime sur l'étape naturelle.
    @Local private var tempsChoisi: Temps? = nil
    @Local private var forcerPhotos = false
    @Local private var continuer = false
    @Local private var avance = true
    @Local private var ideesDemandees = false
    @Local private var monBrief = ""
    @Local private var lienPicTime = ""
    @Local private var survolDepot = false
    @Local private var retouche = ""
    @Local private var confirmerPublication = false
    @Local private var detailsAlt = false

    // MARK: État du jour

    private var vue: VueJour? { etat.vue }
    private var post: Post? { vue?.post }
    private var statut: String { vue?.statut ?? "nouveau" }
    private var idees: [Idee] { Array((vue?.idees ?? []).prefix(3)) }

    private var execCreation: ExecutionClaude? {
        guard let e = etat.execution, !e.aucune, e.jour == nil || e.jour == etat.jour,
              e.tacheClaude == .creation || e.tacheClaude == .retouche else { return nil }
        return e
    }

    private var tempsNaturel: Temps {
        if execCreation?.enCours == true { return .generation }
        switch statut {
        case "idee_choisie":
            if let e = execCreation, e.etat == "erreur" || e.etat == "annule" { return .generation }
            return .photos
        case "brouillon_pret": return .apercu
        case "approuve", "publie", "echec": return .finaliser
        default: return .idees
        }
    }

    private var temps: Temps {
        if let t = tempsChoisi { return t }
        let n = tempsNaturel
        if changerIdee && (n == .photos || n == .apercu) { return .idees }
        if n == .generation && forcerPhotos && execCreation?.enCours != true { return .photos }
        if n == .apercu && continuer { return .finaliser }
        return n
    }

    private var libre: Bool { etat.librePourIdees && !etat.ajoutSourceEnCours }
    private var heure: String { post?.heure?.nonVide ?? vue?.creneau?.nonVide ?? "18:30" }

    // MARK: Corps

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                ZStack {
                    page(geo.size)
                        .id(temps)
                        .transition(j.transition(avance ? .suivante : .precedente))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                PointsProgression(total: 5, courant: temps.rawValue,
                                  aller: { i in tempsChoisi = Temps(rawValue: i) })
                    .padding(.bottom, 22)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .animation(j.anim(.page), value: temps)
        .onChange(of: temps) { ancien, nouveau in avance = nouveau >= ancien }
        .onChange(of: statut) { _, _ in
            tempsChoisi = nil
            changerIdee = false
            forcerPhotos = false
            if statut != "brouillon_pret" { continuer = false }
            lancerIdeesSiBesoin()
        }
        .onChange(of: etat.jour) { _, _ in ideesDemandees = false }
        .onChange(of: coque.demandeNouveauPost) { _, _ in nouveauPost() }
        .onChange(of: etat.etapeAccueilDemandee) { _, e in
            if let e { tempsChoisi = Temps(rawValue: e); etat.etapeAccueilDemandee = nil }
        }
        .onChange(of: execCreation?.id) { _, _ in forcerPhotos = false }
        .task {
            if etat.vue == nil || etat.vue?.jour != etat.jour { await etat.chargerJour() }
            lancerIdeesSiBesoin()
        }
        .alert("Publier tout de suite ?", isPresented: $confirmerPublication) {
            Button("Publier maintenant") { Task { await etat.decider("approuver", "maintenant") } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Le post part maintenant sur Instagram.")
        }
    }

    @ViewBuilder private func page(_ taille: CGSize) -> some View {
        switch temps {
        case .idees: tempsIdees(taille)
        case .photos: tempsPhotos
        case .generation: tempsGeneration
        case .apercu: tempsApercu(taille)
        case .finaliser: tempsFinaliser
        }
    }

    private func entete(_ titre: String, _ texte: String? = nil) -> some View {
        VStack(spacing: j.esp.blocs - 4) {
            Text(titre)
                .typo(.titre1)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let t = texte {
                Text(t).typo(.chapo).multilineTextAlignment(.center).frame(maxWidth: 560)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, j.esp.page)
    }

    // MARK: 1. Les idées

    @ViewBuilder private func tempsIdees(_ taille: CGSize) -> some View {
        let echelle = min(1, max(0.72, (taille.height - 300) / 420))
        VStack(spacing: j.esp.sections * 0.6) {
            Spacer(minLength: 0)
            entete("Quelle histoire aujourd'hui ?")
            Group {
                if let e = etat.executionIdeesDuJour, e.enCours || (idees.isEmpty && !e.reussie) {
                    attenteIdees(e)
                } else if idees.isEmpty {
                    sansIdees
                } else {
                    DeckIdees(idees: idees, brief: { $0.briefAffiche }, actif: libre) { idee in
                        Task { await choisir("choix", "\(idee.numero)") }
                    }
                    .id(idees.map { "\($0.numero)-\($0.titre ?? "")" }.joined(separator: "|"))
                    .scaleEffect(echelle)
                    .frame(height: 400 * echelle)
                }
            }
            .frame(minHeight: 260 * echelle)
            VStack(spacing: 10) {
                BarreBrief(texte: $monBrief, exemple: "Ou décris ton idée…", actif: libre) {
                    guard let t = monBrief.nonVide else { return }
                    monBrief = ""
                    Task { await choisir("libre", t) }
                }
                .frame(maxWidth: 560)
                if !idees.isEmpty {
                    Button { lancerIdees() } label: { Label("D'autres idées", systemImage: "arrow.triangle.2.circlepath") }
                        .buttonStyle(.discret)
                        .disabled(!libre)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func attenteIdees(_ e: ExecutionClaude) -> some View {
        VStack(spacing: j.esp.blocs) {
            if e.enCours {
                ProgressView().controlSize(.small)
                Text(e.etapes.last(where: { !$0.fait })?.texte ?? "Claude prépare trois idées…")
                    .typo(.voixCarte, couleur: j.texteSecondaire)
            } else {
                Text(e.erreur ?? "Claude n'a pas pu préparer d'idées.").typo(.chapo).multilineTextAlignment(.center)
                Button { lancerIdees() } label: { Label("Réessayer", systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(BoutonPilule(.claire))
            }
        }
        .frame(maxWidth: 480)
    }

    private var sansIdees: some View {
        VStack(spacing: j.esp.blocs) {
            if let inv = etat.invitationClaude {
                Text(inv.texte).typo(.chapo).multilineTextAlignment(.center).frame(maxWidth: 460)
                Button { Task { await etat.accepterInvitation() } } label: { Label(inv.libelleBouton, systemImage: inv.symbole) }
                    .buttonStyle(BoutonPilule(.claire))
            } else if etat.lancementEnCours || etat.claudeTravaille {
                ProgressView().controlSize(.small)
                Text("Claude se met au travail…").typo(.voixCarte, couleur: j.texteSecondaire)
            } else {
                Button { lancerIdees() } label: { Label("Proposer trois idées", systemImage: "sparkles") }
                    .buttonStyle(BoutonPilule(.claire))
            }
        }
    }

    private func lancerIdees() {
        guard etat.librePourIdees else { return }
        Task { _ = await etat.lancerClaude(.idees, jour: etat.jour) }
    }

    /// Pas encore d'idées pour ce jour : Claude en prépare trois tout de suite (une fois par jour affiché).
    private func lancerIdeesSiBesoin() {
        // Jamais pour un autre jour que celui d'aujourd'hui (feuilleter les jours ne doit rien lancer), et jamais
        // après un échec (limite atteinte, pas connecté) : la photographe relance elle-même.
        guard etat.jour == EtatApp.aujourdhuiISO(),
              etat.executionIdeesDuJour == nil || etat.executionIdeesDuJour?.etat == "termine",
              tempsNaturel == .idees, !ideesDemandees, idees.isEmpty, etat.vue != nil,
              etat.executionIdeesDuJour?.enCours != true, etat.librePourIdees else { return }
        ideesDemandees = true
        lancerIdees()
    }

    /// Enregistre le choix (carte ou brief libre) sans lancer Claude : les photos se choisissent d'abord.
    private func choisir(_ action: String, _ valeur: String) async {
        etat.occupe = true
        defer { etat.occupe = false }
        do {
            _ = try await etat.appeler(Decision.self, ["app", "decider", etat.jour, action, valeur])
        } catch {
            etat.erreur = error.localizedDescription
            return
        }
        changerIdee = false
        await etat.chargerJour()
    }

    // MARK: 2. Les photos

    private var serieDeLIdee: String? {
        guard let n = vue?.choix?.numero else { return nil }
        return vue?.idees?.first { $0.numero == n }?.serie?.nonVide
    }

    private var tempsPhotos: some View {
        VStack(spacing: j.esp.sections * 0.6) {
            Spacer(minLength: 0)
            entete("Quelles photos ?", vue?.choix.flatMap { ($0.titre ?? $0.libre)?.nonVide }.map { "Pour « \($0) »." })
            zoneDepot
                .frame(maxWidth: 560)
            HStack(spacing: 10) {
                ChampDoux(texte: $lienPicTime, exemple: "Ou colle un lien Pic-Time…", lignes: 1...1, envoyer: utiliserLien)
                Button { utiliserLien() } label: { Image(systemName: "arrow.up") }
                    .buttonStyle(BoutonRond(.sombre, diametre: 40))
                    .disabled(!libre || lienPicTime.nonVide == nil)
                    .accessibilityLabel("Utiliser ce lien")
            }
            .frame(maxWidth: 560)
            HStack(spacing: j.esp.sections * 0.6) {
                if let s = serieDeLIdee {
                    Button { lancerCreation(serie: s) } label: { Text("Utiliser les photos de l'idée") }
                        .buttonStyle(.discret)
                        .disabled(!libre)
                }
                Button { changerIdee = true } label: { Text("Changer d'idée") }
                    .buttonStyle(.discret)
                    .disabled(etat.ajoutSourceEnCours)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var zoneDepot: some View {
        let forme = RoundedRectangle(cornerRadius: j.rayons.feuille, style: .continuous)
        return VStack(spacing: j.esp.blocs) {
            if etat.ajoutSourceEnCours {
                ProgressView().controlSize(.regular)
                Text("Je copie et je regarde tes photos…").typo(.voixCarte, couleur: j.texteSecondaire)
            } else {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(j.texteSecondaire)
                Text("Glisse tes photos ou un dossier ici").typo(.titre3)
                Button { choisirSurLeMac() } label: { Label("Choisir sur le Mac…", systemImage: "folder") }
                    .buttonStyle(BoutonPrincipal())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!libre)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 230)
        .background(forme.fill(survolDepot ? j.selection : j.remplissageCarte))
        .overlay(forme.strokeBorder(survolDepot ? j.accent : j.traitFort,
                                    style: StrokeStyle(lineWidth: survolDepot ? 2 : 1.2, dash: [6, 5])))
        .animation(j.anim(.survol), value: survolDepot)
        .dropDestination(for: URL.self) { urls, _ in
            deposer(urls)
            return !urls.isEmpty
        } isTargeted: { survolDepot = $0 }
    }

    private func choisirSurLeMac() {
        let panneau = NSOpenPanel()
        panneau.title = "Choisis tes photos ou un dossier"
        panneau.prompt = "Utiliser"
        panneau.canChooseFiles = true
        panneau.canChooseDirectories = true
        panneau.allowsMultipleSelection = true
        panneau.allowedContentTypes = [.image, .folder]
        guard panneau.runModal() == .OK else { return }
        deposer(panneau.urls)
    }

    private func deposer(_ urls: [URL]) {
        guard libre, !urls.isEmpty else { return }
        var estDossier: ObjCBool = false
        let dossier = urls.count == 1 && FileManager.default.fileExists(atPath: urls[0].path, isDirectory: &estDossier)
            && estDossier.boolValue
        creerAvec {
            dossier ? await etat.ajouterSource(dossier: urls[0], nom: urls[0].lastPathComponent)
                    : await etat.ajouterSource(fichiers: urls)
        }
    }

    private func utiliserLien() {
        guard libre, let lien = lienPicTime.nonVide else { return }
        creerAvec {
            let id = await etat.ajouterSource(pictime: lien)
            if id != nil { lienPicTime = "" }
            return id
        }
    }

    /// Ajoute les photos (`ajouterSource` : copiées, jamais modifiées), puis Claude crée le post avec elles.
    private func creerAvec(_ source: @escaping () async -> String?) {
        Task {
            guard let id = await source() else { return }
            _ = await etat.lancerClaude(.creation, jour: etat.jour, serie: id)
        }
    }

    private func lancerCreation(serie: String?) {
        guard libre else { return }
        Task { _ = await etat.lancerClaude(.creation, jour: etat.jour, serie: serie) }
    }

    // MARK: 3. La génération

    private var tempsGeneration: some View {
        let e = execCreation
        let enErreur = e?.etat == "erreur" || e?.etat == "annule"
        return VStack(spacing: j.esp.sections * 0.6) {
            Spacer(minLength: 0)
            Illustration(enErreur ? .erreur : .attente, taille: 170).frame(width: 170, height: 170)
            entete(enErreur ? "Claude s'est arrêté." : (e?.tacheClaude == .retouche ? "Claude retouche ton post." : "Claude prépare ton post."),
                   enErreur ? (e?.erreur ?? "Rien n'est perdu : ton idée et tes photos sont gardées.")
                            : "Tu peux fermer l'app : elle se rouvrira quand ce sera prêt.")
            if let e, !enErreur {
                VStack(spacing: 10) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(j.trait)
                            Capsule().fill(j.accent).frame(width: max(10, g.size.width * etat.progressionCreation))
                        }
                    }
                    .frame(height: 8)
                    .animation(j.anim(.doux), value: etat.progressionCreation)
                    .accessibilityElement()
                    .accessibilityLabel("Avancement")
                    .accessibilityValue("\(Int(etat.progressionCreation * 100)) %")
                    HStack {
                        Text(e.etapes.last(where: { !$0.fait })?.texte ?? e.message ?? "Je commence…")
                            .typo(.voixCarte, couleur: j.texteSecondaire)
                            .lineLimit(1)
                        Spacer()
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            Text(e.libelleDuree(a: ctx.date) ?? "").font(.system(size: 12)).monospacedDigit()
                                .foregroundStyle(j.texteTertiaire)
                        }
                    }
                }
                .frame(maxWidth: 480)
                if e.enCours {
                    Button("Arrêter") { Task { await etat.annulerClaude() } }.buttonStyle(.discret)
                }
            } else {
                HStack(spacing: j.esp.blocs) {
                    if let inv = etat.invitationClaude {
                        Button { Task { await etat.accepterInvitation() } } label: { Label(inv.libelleBouton, systemImage: inv.symbole) }
                            .buttonStyle(BoutonPrincipal())
                    } else {
                        Button { relancer() } label: { Label("Relancer Claude", systemImage: "sparkles") }
                            .buttonStyle(BoutonPrincipal(enCours: etat.lancementEnCours))
                            .keyboardShortcut(.defaultAction)
                            .disabled(!etat.librePourIdees)
                    }
                    if statut == "idee_choisie" {
                        Button("Choisir d'autres photos") { forcerPhotos = true }
                            .buttonStyle(BoutonPilule(.claire))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func relancer() {
        let e = execCreation
        Task {
            if e?.tacheClaude == .retouche, let c = e?.consigne?.nonVide {
                _ = await etat.lancerClaude(.retouche, jour: etat.jour, consigne: c)
            } else {
                _ = await etat.lancerClaude(.creation, jour: etat.jour, serie: e?.serie?.nonVide)
            }
        }
    }

    // MARK: 4. L'aperçu

    private var contenuInstagram: ContenuInstagram {
        let p = post
        let format = FormatInstagram(p?.format)
        let chemins = (p?.medias ?? []).sorted { $0.ordre < $1.ordre }.compactMap { $0.image }
        var texte = p?.legende ?? ""
        let tags = hashtags.filter { !texte.contains($0) }
        if !tags.isEmpty { texte += (texte.isEmpty ? "" : "\n\n") + tags.joined(separator: " ") }
        var musique: String? = nil
        if let m = p?.musique, m.mode != "aucune", let t = m.titre {
            musique = [t, m.artiste].compactMap { $0 }.joined(separator: " · ")
        }
        return ContenuInstagram(compte: p?.compte?.nonVide ?? "ton.compte", collaborateurs: p?.collaborateurs ?? [],
                                lieu: p?.localisation?.nonVide, musique: musique, medias: chemins, format: format,
                                legende: texte, date: nil,
                                heure: heure)
    }

    private var hashtags: [String] { (post?.hashtags ?? []).map { $0.hasPrefix("#") ? $0 : "#" + $0 } }

    private func tempsApercu(_ taille: CGSize) -> some View {
        let hTel = min(TelephoneInstagram.hauteur, max(320, taille.height - 190))
        return VStack(spacing: j.esp.blocs + 4) {
            HStack(alignment: .top, spacing: j.esp.sections) {
                TelephoneInstagram(contenu: contenuInstagram)
                    .id(etat.versionImages)
                    .frame(width: hTel * TelephoneInstagram.largeur / TelephoneInstagram.hauteur, height: hTel)
                ScrollView { details.padding(.trailing, 6) }
                    .frame(maxWidth: 460, maxHeight: hTel)
            }
            .padding(.top, j.esp.blocs + 8)
            HStack(spacing: j.esp.blocs) {
                BarreBrief(texte: $retouche, exemple: "Dis à Claude ce qu'il faut changer ou ajouter…",
                           actif: libre) {
                    guard let t = retouche.nonVide else { return }
                    retouche = ""
                    Task { await etat.decider("retouche", t) }
                }
                Button { continuer = true } label: { Label("Continuer", systemImage: "arrow.right") }
                    .buttonStyle(BoutonPrincipal())
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Continuer (⌘⏎)")
            }
            .frame(maxWidth: 860)
        }
        .padding(.horizontal, j.esp.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var details: some View {
        let v = vue?.verdict
        let erreurs = v?.erreurs ?? []
        let vigilance = (v?.alertes ?? []) + (v?.avertissements ?? [])
        return VStack(alignment: .leading, spacing: j.esp.blocs) {
            Text(post?.titre ?? "Ton post").typo(.titre2).fixedSize(horizontal: false, vertical: true)
            if !erreurs.isEmpty {
                Pastille("À corriger : \(erreurs.joined(separator: " "))", symbole: "exclamationmark.triangle.fill", ton: .alerte)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !vigilance.isEmpty {
                Pastille(vigilance.count == 1 ? "1 point à vérifier" : "\(vigilance.count) points à vérifier",
                         symbole: "exclamationmark.circle.fill", ton: .douce)
                    .help(vigilance.joined(separator: "\n"))
            } else if v != nil {
                Pastille("Prêt", symbole: "checkmark.circle.fill", ton: .succes)
            }
            if let medias = post?.medias, !medias.isEmpty {
                bloc("Mise en page") { CompositeurPages(medias: medias, actif: libre) }
            }
            bloc("Légende") {
                Text(post?.legende ?? "").typo(.corps).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            if !hashtags.isEmpty {
                bloc("Hashtags") { Text(hashtags.joined(separator: " ")).typo(.corps, couleur: j.accentTexte).textSelection(.enabled) }
            }
            let credits = (post?.collaborateurs ?? []).map { $0.hasPrefix("@") ? $0 : "@" + $0 }
            if !credits.isEmpty || post?.localisation?.nonVide != nil {
                bloc("Crédits et lieu") {
                    if !credits.isEmpty { Text(credits.joined(separator: ", ")).typo(.corps) }
                    if let l = post?.localisation?.nonVide { Label(l, systemImage: "mappin").typo(.corps) }
                }
            }
            if post != nil {
                bloc("Musique") { BlocMusique(musique: post?.musique, actif: libre) }
            }
            let alts = (post?.medias ?? []).sorted { $0.ordre < $1.ordre }.compactMap { $0.texte_alternatif?.nonVide }
            if !alts.isEmpty {
                Button { withAnimation(j.anim(.doux)) { detailsAlt.toggle() } } label: {
                    Label("Textes alternatifs", systemImage: detailsAlt ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(.discret)
                if detailsAlt {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(alts.enumerated()), id: \.offset) { i, a in
                            Text("\(i + 1). \(a)").typo(.legende).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bloc<C: View>(_ titre: String, @ViewBuilder _ contenu: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titre).typo(.surtitre)
            contenu()
        }
    }

    // MARK: 5. Finaliser

    private var publicationBloquee: Bool { !libre || post == nil || !(vue?.verdict?.erreurs ?? []).isEmpty }

    @ViewBuilder private var tempsFinaliser: some View {
        VStack(spacing: j.esp.sections * 0.6) {
            Spacer(minLength: 0)
            switch statut {
            case "publie":
                Illustration(.publication, taille: 200).frame(width: 200, height: 200)
                entete("C'est en ligne !", "Ton post est publié sur Instagram.")
                HStack(spacing: j.esp.blocs) {
                    if let l = vue?.permalink, let url = URL(string: l) {
                        Button { NSWorkspace.shared.open(url) } label: { Label("Voir sur Instagram", systemImage: "arrow.up.right.square") }
                            .buttonStyle(BoutonPilule(.claire))
                    }
                    Button { archiver() } label: { Label("Archiver dans la galerie", systemImage: "archivebox") }
                        .buttonStyle(BoutonPrincipal())
                        .keyboardShortcut(.defaultAction)
                }
            case "approuve":
                Illustration(.publication, taille: 180).frame(width: 180, height: 180)
                entete("C'est prévu.", "Il partira \(quandPublication). Tu peux fermer l'app.")
                HStack(spacing: j.esp.blocs) {
                    boutonTelecharger
                    Button { archiver() } label: { Label("Archiver dans la galerie", systemImage: "archivebox") }
                        .buttonStyle(BoutonPrincipal())
                }
            default:
                entete(statut == "echec" ? "La publication n'est pas passée." : "C'est prêt.",
                       statut == "echec" ? "Réessaie, ou télécharge les fichiers pour publier toi-même."
                                         : "Comment veux-tu le partager ?")
                HStack(spacing: j.esp.gouttiere) {
                    choix(titre: "Télécharger les fichiers", texte: "Les images et la légende, dans Téléchargements.",
                          symbole: "arrow.down.circle", actif: post != nil && !etat.exportEnCours, enCours: etat.exportEnCours) {
                        Task { _ = await etat.exporter() }
                    }
                    choix(titre: "Publier en un clic", texte: "Le post part tout de suite sur Instagram.",
                          symbole: "paperplane", actif: !publicationBloquee, enCours: etat.occupe) {
                        confirmerPublication = true
                    }
                }
                .frame(maxWidth: 680)
                if let e = vue?.verdict?.erreurs, !e.isEmpty {
                    Text("À corriger avant de publier : \(e.joined(separator: " "))").typo(.legende, couleur: j.alerte)
                        .multilineTextAlignment(.center).frame(maxWidth: 560)
                }
                HStack(spacing: j.esp.sections * 0.6) {
                    Button("Revenir à l'aperçu") { continuer = false; tempsChoisi = nil }.buttonStyle(.discret)
                    Button("Archiver dans la galerie") { archiver() }.buttonStyle(.discret)
                    Button("Ou programmer à \(heure)") { Task { await etat.decider("approuver", "creneau") } }
                        .buttonStyle(.discret)
                        .disabled(publicationBloquee)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func choix(titre: String, texte: String, symbole: String, actif: Bool, enCours: Bool,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Carte(style: .cliquable) {
                VStack(spacing: j.esp.blocs) {
                    ZStack {
                        Circle().fill(j.fondDoux).frame(width: 64, height: 64)
                        if enCours { ProgressView().controlSize(.small) } else {
                            Image(systemName: symbole).font(.system(size: 26, weight: .light)).foregroundStyle(j.texte)
                        }
                    }
                    Text(titre).typo(.titre3)
                    Text(texte).typo(.legende).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        }
        .buttonStyle(.plain)
        .disabled(!actif)
        .opacity(actif ? 1 : 0.5)
    }

    private var boutonTelecharger: some View {
        Button { Task { _ = await etat.exporter() } } label: { Label("Télécharger les fichiers", systemImage: "arrow.down.circle") }
            .buttonStyle(BoutonPilule(.claire, enCours: etat.exportEnCours))
            .disabled(post == nil || etat.exportEnCours)
    }

    private var quandPublication: String {
        guard let p = vue?.publier_a, p.count >= 16 else { return "à \(heure)" }
        let jourP = String(p.prefix(10))
        let h = String(p.dropFirst(11).prefix(5))
        if jourP == (vue?.aujourdhui ?? EtatApp.aujourdhuiISO()) { return "aujourd'hui à \(h)" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: jourP) else { return "le \(jourP) à \(h)" }
        f.dateFormat = "EEEE d MMMM"
        return "\(f.string(from: d)) à \(h)"
    }

    /// « Nouveau post » (⌘N) : retour aux idées ; si le post du jour est déjà prévu ou publié, le jour suivant.
    /// Range le post dans la galerie : l'accueil repart sur les idées pour un nouveau post.
    private func archiver() {
        Task {
            if await etat.archiverPost() {
                tempsChoisi = nil
                continuer = false
                changerIdee = false
            }
        }
    }

    private func nouveauPost() {
        tempsChoisi = nil
        if ["approuve", "publie"].contains(statut) { archiver(); return }
        guard execCreation?.enCours != true else { return }
        continuer = false
        forcerPhotos = false
        changerIdee = true
    }

    /// Le post du jour est fait : le suivant se prépare pour le lendemain (un post par jour).
    private func prochainPost() {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: etat.jour), let demain = Calendar.current.date(byAdding: .day, value: 1, to: d) else { return }
        continuer = false
        etat.montrer(etat.ecran ?? .aujourdhui, jour: f.string(from: demain))
    }
}

// MARK: - Deck d'idées

/// Trois cartes posées en éventail : la carte du milieu devant, les autres tournées ; au survol, la carte se
/// soulève et passe devant. À l'apparition, les cartes se distribuent depuis le centre.
private struct DeckIdees: View {
    let idees: [Idee]
    let brief: (Idee) -> String
    let actif: Bool
    let choisir: (Idee) -> Void
    @Environment(\.jetons) private var j
    @Local private var distribuees = false
    @Local private var survol: Int? = nil

    private let largeur: CGFloat = 250
    private let hauteur: CGFloat = 350

    var body: some View {
        ZStack {
            ForEach(Array(idees.enumerated()), id: \.element.id) { i, idee in
                carte(idee, index: i)
            }
        }
        .frame(width: largeur * 3.2, height: hauteur + 50)
        .onAppear { DispatchQueue.main.async { distribuees = true } }
        .accessibilityElement(children: .contain)
    }

    private func position(_ i: Int) -> (angle: Double, x: CGFloat, y: CGFloat) {
        let centre = Double(idees.count - 1) / 2
        let d = Double(i) - centre
        return (d * 7, CGFloat(d) * largeur * 1.02, CGFloat(abs(d)) * 22)   // un éventail : les cartes se frôlent sans se cacher
    }

    private func carte(_ idee: Idee, index i: Int) -> some View {
        let p = position(i)
        let leve = survol == i && actif
        let milieu = abs(Double(i) - Double(idees.count - 1) / 2) < 0.6
        let forme = RoundedRectangle(cornerRadius: j.rayons.carte, style: .continuous)
        return Button { choisir(idee) } label: {
            VStack(alignment: .leading, spacing: 12) {
                ImageLocale(chemin: idee.couverture)
                    .frame(width: largeur - 28, height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: j.rayons.photo, style: .continuous))
                Text(brief(idee))
                    .font(Font.jakarta(15, graisse: 600))
                    .foregroundStyle(j.texte)
                    .lineSpacing(2)
                    .lineLimit(5)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Text("\(idee.numero)").font(Font.jakarta(13, graisse: 700)).foregroundStyle(j.accentTexte)
                    Text(LibellesIdee.format(idee)).typo(.legende).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(leve ? j.accentTexte : j.texteTertiaire)
                }
            }
            .padding(14)
            .frame(width: largeur, height: hauteur, alignment: .topLeading)
            .background(forme.fill(j.schema == .dark ? j.carte : Color.white))
            .overlay(LisereHaut(rayon: j.rayons.carte))
            .clipShape(forme)
            .ombre(leve ? .flottante : .carte)
            .contentShape(forme)
        }
        .buttonStyle(.plain)
        .disabled(!actif)
        .rotationEffect(.degrees(distribuees ? (leve ? p.angle * 0.4 : p.angle) : 0), anchor: .bottom)
        .offset(x: distribuees ? p.x : 0, y: distribuees ? p.y - (leve ? 22 : 0) : 60)
        .scaleEffect(leve ? 1.04 : 1)
        .opacity(distribuees ? 1 : 0)
        .zIndex(leve ? 10 : (milieu ? 2 : 1))
        .animation(j.anim(.page).map { $0.delay(distribuees && survol == nil ? Double(i) * 0.09 : 0) }, value: distribuees)
        .animation(j.anim(.survol), value: leve)
        .onHover { dedans in
            if dedans { survol = i } else if survol == i { survol = nil }
        }
        .accessibilityLabel("Idée \(idee.numero) : \(brief(idee))")
        .accessibilityHint("Choisir cette idée")
    }
}

// MARK: - Barre de brief

/// Une simple barre : champ d'une à trois lignes et rond sombre pour envoyer (⏎).
private struct BarreBrief: View {
    @Binding var texte: String
    let exemple: String
    let actif: Bool
    let envoyer: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ChampDoux(texte: $texte, exemple: exemple, lignes: 1...3, envoyer: { if actif { envoyer() } })
            Button(action: envoyer) { Image(systemName: "arrow.up") }
                .buttonStyle(BoutonRond(.sombre, diametre: 40))
                .disabled(!actif || texte.nonVide == nil)
                .accessibilityLabel("Envoyer")
        }
    }
}


// MARK: - Mise en page : plusieurs photos sur une même page

/// Les pages du carrousel en vignettes. On en touche deux à quatre pour les réunir sur une seule page
/// (côte à côte, l'une sur l'autre, trio, grille…), ou une seule pour changer sa présentation.
/// Le moteur refait la mise en page tout de suite, sans Claude : les photos ne sont que recadrées.
private struct CompositeurPages: View {
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j
    let medias: [MediaPost]
    let actif: Bool
    @Local private var choix: [Int] = []

    private var pages: [MediaPost] { medias.sorted { $0.ordre < $1.ordre } }
    private var choisies: [MediaPost] { pages.filter { choix.contains($0.ordre) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(pages) { vignette($0) } }.padding(3)
            }
            options
        }
        .onChange(of: medias.map(\.ordre)) { _, _ in choix = [] }
        .disabled(!actif || etat.modificationEnCours)
        .opacity(etat.modificationEnCours ? 0.5 : 1)
    }

    private func vignette(_ m: MediaPost) -> some View {
        let choisie = choix.contains(m.ordre)
        return Button {
            withAnimation(j.anim(.doux)) {
                if choisie { choix.removeAll { $0 == m.ordre } } else { choix.append(m.ordre) }
            }
        } label: {
            ImageLocale(chemin: m.image)
                .frame(width: 48, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(choisie ? j.accent : Color.primary.opacity(0.08), lineWidth: choisie ? 2.5 : 1))
                .overlay(alignment: .topLeading) {
                    Text("\(m.ordre)").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(Color.black.opacity(0.55))).padding(3)
                }
                .overlay(alignment: .bottomTrailing) {
                    if m.nombrePhotos > 1 {
                        Image(systemName: "square.grid.2x2.fill").font(.system(size: 9)).foregroundStyle(.white)
                            .padding(3).background(Circle().fill(Color.black.opacity(0.55))).padding(3)
                    }
                }
                .id(etat.versionImages)
        }
        .buttonStyle(.plain)
        .help(choisie ? "Retirer de la sélection" : "Choisir cette page")
        .accessibilityLabel("Page \(m.ordre)\(choisie ? ", choisie" : "")")
    }

    @ViewBuilder private var options: some View {
        let c = choisies
        if c.isEmpty {
            Text("Touche deux à quatre pages pour les réunir sur une seule, ou une page pour changer sa présentation.")
                .typo(.legende).fixedSize(horizontal: false, vertical: true)
        } else if c.count == 1, let m = c.first, m.nombrePhotos > 1 {
            pilules(ModulePage.pour(m.nombrePhotos).filter { $0.cle != m.module }.map { mod in
                (mod.titre, mod.symbole, { reunir(mod.cle) })
            } + [("Séparer", "rectangle.split.3x3", { separer(m) })])
        } else if c.count == 1, let m = c.first {
            pilules([("Plein cadre", "rectangle.portrait.fill", { presenter(m, "plein_cadre") }),
                     ("Sur fond", "rectangle.inset.filled", { presenter(m, "marges") }),
                     ("Tirage", "photo", { reunir("tirage") })])
        } else if c.allSatisfy({ $0.nombrePhotos == 1 }), (2...4).contains(c.count) {
            pilules(ModulePage.pour(c.count).map { mod in (mod.titre, mod.symbole, { reunir(mod.cle) }) })
        } else {
            Text(c.count > 4 ? "Quatre photos au plus sur une page." : "Choisis seulement des pages d'une seule photo.")
                .typo(.legende)
        }
    }

    private func pilules(_ liste: [(String, String, () -> Void)]) -> some View {
        FlowPilules(liste: liste)
    }

    // MARK: Transformations

    private func base(_ m: MediaPost) -> MediaModifie? {
        guard let id = m.photo_id?.nonVide else { return nil }
        if let mod = m.module?.nonVide, let ph = m.photos, !ph.isEmpty {
            return MediaModifie(photo_id: id, module: mod, photos: ph)
        }
        return MediaModifie(photo_id: id)
    }

    private func photosDe(_ m: MediaPost) -> [String] {
        if let ph = m.photos, !ph.isEmpty { return ph }
        return [m.photo_id?.nonVide].compactMap { $0 }
    }

    private func reunir(_ module: String) {
        let ordres = Set(choix)
        let ids = choisies.flatMap { photosDe($0) }
        guard let premier = ids.first else { return }
        var res: [MediaModifie] = []
        var place = false
        for m in pages {
            if ordres.contains(m.ordre) {
                if !place { res.append(MediaModifie(photo_id: premier, module: module, photos: ids)); place = true }
            } else if let b = base(m) {
                res.append(b)
            }
        }
        envoyer(res)
    }

    private func separer(_ m: MediaPost) {
        var res: [MediaModifie] = []
        for p in pages {
            if p.ordre == m.ordre {
                res += photosDe(p).map { MediaModifie(photo_id: $0) }
            } else if let b = base(p) {
                res.append(b)
            }
        }
        envoyer(res)
    }

    private func presenter(_ m: MediaPost, _ presentation: String) {
        let res = pages.compactMap { p -> MediaModifie? in
            guard p.ordre == m.ordre, let id = photosDe(p).first else { return base(p) }
            return MediaModifie(photo_id: id, presentation: presentation)
        }
        envoyer(res)
    }

    private func envoyer(_ res: [MediaModifie]) {
        choix = []
        Task { await etat.modifierPost(medias: res) }
    }
}

/// Une rangée de petites pilules qui passe à la ligne.
private struct FlowPilules: View {
    let liste: [(String, String, () -> Void)]

    var body: some View {
        let lignes = stride(from: 0, to: liste.count, by: 2).map { Array(liste[$0..<min($0 + 2, liste.count)]) }
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lignes.enumerated()), id: \.offset) { _, ligne in
                HStack(spacing: 6) {
                    ForEach(Array(ligne.enumerated()), id: \.offset) { _, e in
                        Button(action: e.2) { Label(e.0, systemImage: e.1) }
                            .buttonStyle(.pilule(.claire, taille: .petite))
                    }
                }
            }
        }
    }
}


// MARK: - Musique : choisir une piste, écouter un extrait

/// Joue un extrait à la fois (30 secondes), dans tout l'app.
@MainActor final class LecteurExtraits: ObservableObject {
    static let partage = LecteurExtraits()
    @Published private(set) var enCours: String? = nil
    private var lecteur: AVPlayer?
    private var fin: NSObjectProtocol?

    func basculer(_ adresse: String?) {
        guard let s = adresse, let url = URL(string: s) else { return }
        if enCours == s { arreter(); return }
        arreter()
        let element = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: element)
        fin = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: element,
                                                     queue: .main) { [weak self] _ in
            Task { @MainActor in self?.arreter() }
        }
        lecteur = p
        enCours = s
        p.play()
    }

    func arreter() {
        lecteur?.pause()
        lecteur = nil
        if let f = fin { NotificationCenter.default.removeObserver(f) }
        fin = nil
        enCours = nil
    }
}

/// Pochette ronde avec bouton lecture / pause par-dessus.
private struct PochetteLecture: View {
    let pochette: String?
    let extrait: String?
    var cote: CGFloat = 48
    @ObservedObject private var lecteur = LecteurExtraits.partage

    var body: some View {
        let joue = extrait != nil && lecteur.enCours == extrait
        Button { lecteur.basculer(extrait) } label: {
            ZStack {
                AsyncImage(url: pochette.flatMap(URL.init(string:))) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    LinearGradient(colors: [.pink.opacity(0.35), .purple.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(Image(systemName: "music.note").foregroundStyle(.white))
                }
                .frame(width: cote, height: cote)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                if extrait != nil {
                    Image(systemName: joue ? "pause.fill" : "play.fill")
                        .font(.system(size: cote * 0.26, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: cote * 0.56, height: cote * 0.56)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                        .scaleEffect(joue ? 1.08 : 1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: joue)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(extrait == nil)
        .help(joue ? "Arrêter l'extrait" : "Écouter un extrait")
        .accessibilityLabel(joue ? "Arrêter l'extrait" : "Écouter un extrait")
    }
}

/// La musique du post dans l'aperçu : la piste choisie (avec extrait) ou le bouton pour en choisir une.
private struct BlocMusique: View {
    let musique: Musique?
    let actif: Bool
    @EnvironmentObject var etat: EtatApp
    @Local private var ouvert = false

    var body: some View {
        Group {
            if let m = musique, m.mode != "aucune", let t = m.titre {
                HStack(spacing: 12) {
                    PochetteLecture(pochette: m.pochette, extrait: m.apercu_url, cote: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t).typo(.corpsFort).lineLimit(1)
                        Text(m.artiste ?? "").typo(.legende).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button("Changer") { ouvert = true }
                        .buttonStyle(.pilule(.claire, taille: .petite))
                        .disabled(!actif)
                }
                Text("Tu l'ajouteras dans l'app Instagram en publiant : Instagram ne laisse pas une app ajouter la musique d'un carrousel.")
                    .typo(.legende).fixedSize(horizontal: false, vertical: true)
            } else {
                Button { ouvert = true } label: { Label("Choisir une musique", systemImage: "music.note") }
                    .buttonStyle(.pilule(.claire, taille: .petite))
                    .disabled(!actif)
            }
        }
        .sheet(isPresented: $ouvert) {
            ChoixMusique(actuelle: musique) { ouvert = false }
                .environmentObject(etat)
        }
    }
}

/// La feuille de choix : tendances du moment, ambiances (romantique, piano…) et recherche, chaque piste avec
/// son extrait. Un clic sur « Choisir » l'enregistre dans le post.
private struct ChoixMusique: View {
    let actuelle: Musique?
    let fermer: () -> Void
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j
    @ObservedObject private var lecteur = LecteurExtraits.partage
    @Local private var recherche = ""
    @Local private var rubrique = "tendances"
    @Local private var pistes: [PisteMusique] = []
    @Local private var chargement = false
    @Local private var enregistrement: String? = nil

    private static let rubriques: [(String, String, String)] = [
        ("tendances", "Tendances", "flame"), ("romantique", "Romantique", "heart"), ("piano", "Piano", "pianokeys"),
        ("acoustique", "Acoustique", "guitars"), ("cinematique", "Cinématique", "film"), ("indie", "Indie folk", "leaf"),
        ("jazz", "Jazz", "music.quarternote.3"), ("francais", "Chanson française", "quote.bubble"), ("joyeux", "Joyeux", "sun.max"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Choisir une musique").typo(.titre2)
                Spacer()
                Button { lecteur.arreter(); fermer() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)) }
                    .buttonStyle(.plain)
                    .frame(width: 28, height: 28)
                    .verreLiquide(Circle(), interactif: true)
                    .keyboardShortcut(.cancelAction)
                    .help("Fermer")
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Un titre, un artiste, une ambiance…", text: $recherche)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        guard let q = recherche.nonVide else { return }
                        rubrique = ""
                        Task { await charger(q) }
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .verreLiquide(Capsule())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.rubriques, id: \.0) { cle, titre, symbole in
                        Button {
                            rubrique = cle
                            recherche = ""
                            Task { await charger(cle) }
                        } label: {
                            Label(titre, systemImage: symbole)
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .foregroundStyle(rubrique == cle ? j.surEncre : j.texte)
                                .background(Capsule().fill(rubrique == cle ? j.encre : Color.primary.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            if rubrique == "tendances" {
                Text("Les morceaux les plus écoutés en ce moment (classement Apple Music). Touche une pochette pour écouter un extrait.")
                    .typo(.legende).fixedSize(horizontal: false, vertical: true)
            }
            ZStack {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(pistes) { ligne($0) }
                    }
                    .padding(.vertical, 2)
                }
                if chargement {
                    ProgressView().controlSize(.small)
                } else if pistes.isEmpty {
                    Text("Aucune piste trouvée.").typo(.legende)
                }
            }
            .frame(maxHeight: .infinity)
            HStack {
                Button("Sans musique") { Task { await choisir(Musique(mode: "aucune")) } }
                    .buttonStyle(.discret)
                Spacer()
                Text("À ajouter ensuite dans l'app Instagram, au moment de publier.").typo(.legende)
            }
        }
        .padding(22)
        .frame(width: 600, height: 660)
        .task { await charger("tendances") }
        .onDisappear { lecteur.arreter() }
    }

    private func ligne(_ p: PisteMusique) -> some View {
        let choisie = actuelle?.titre == p.titre && actuelle?.artiste == p.artiste
        return HStack(spacing: 12) {
            PochetteLecture(pochette: p.pochette, extrait: p.apercu_url)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.titre ?? "Sans titre").typo(.corpsFort).lineLimit(1)
                Text([p.artiste, p.source == "instagram" ? "Instagram" : nil].compactMap { $0 }.joined(separator: " · "))
                    .typo(.legende).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let d = p.duree { Text(d).typo(.legende).monospacedDigit() }
            if choisie {
                Label("Choisie", systemImage: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(j.accent)
            } else {
                Button(enregistrement == p.id ? "…" : "Choisir") { Task { await choisir(p.musique(), id: p.id) } }
                    .buttonStyle(.pilule(.claire, taille: .petite))
                    .disabled(enregistrement != nil)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(lecteur.enCours != nil && lecteur.enCours == p.apercu_url ? j.accent.opacity(0.10) : Color.clear))
    }

    private func charger(_ cle: String) async {
        chargement = true
        pistes = []
        let res = cle == "tendances" ? await etat.tendancesMusique() : await etat.chercherMusique(cle)
        withAnimation(j.anim(.doux)) { pistes = res }
        chargement = false
    }

    private func choisir(_ m: Musique, id: String = "aucune") async {
        enregistrement = id
        let ok = await etat.modifierPost(musique: m)
        enregistrement = nil
        if ok {
            lecteur.arreter()
            fermer()
        }
    }
}
