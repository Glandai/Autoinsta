import AppKit
import AVKit
import SwiftUI

// Assistant « Nouveau post » (écran `creation`, DESIGN.md §4.3) : plein écran sur le fond d'ambiance (dessiné par
// la coque), une étape à la fois, comme l'onboarding : 1 Idée · 2 Claude au travail · 3 Photos · 4 Légende ·
// 5 Musique · 6 Aperçu et publication. Les étapes photos, légende et musique ne s'affichent que si elles sont
// cochées dans Réglages › Création (`etat.etapesAValider`) ; sinon Claude s'en occupe et elles passent seules.
// L'étape affichée se déduit du statut du jour (reprise au bon endroit quand on revient) ; les étapes déjà
// validées pour le brouillon courant sont retenues dans les préférences de l'app (jamais dans le studio).
// Chaque validation n'envoie à `modifierPost` que ce qui a changé. Rien n'est publié sans un clic explicite.

struct VueCreation: View {
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j

    // Navigation
    @Local private var etape = 0
    @Local private var initialise = false
    @Local private var avance = true
    @Local private var valides: Set<String> = []
    @Local private var repris = false
    @Local private var nouvellesErreurs = false

    // 1. Idée
    @Local private var ideesDemandees = false

    // 3. Photos
    @Local private var medias: [MediaModifie] = []
    @Local private var mediasDepart: [MediaModifie] = []
    @Local private var images: [String: String] = [:]
    @Local private var candidatsSerie: [PhotoCandidate] = []
    @Local private var chargementCandidats = false
    @Local private var galerieOuverte = false
    @Local private var survolPhoto: String? = nil
    @Local private var cibleDepot: String? = nil

    // 4. Légende
    @Local private var legende = ""
    @Local private var legendeDepart = ""

    // 5. Musique
    @Local private var pistes: [PisteMusique] = []
    @Local private var rechercheMusique = false
    @Local private var musiqueCherchee = false
    @Local private var noteMusique: String? = nil
    @Local private var choixMusique: ChoixMusique = .proposee
    @Local private var lecteur: AVPlayer? = nil

    // Photos d'origine de la série (identifiant → vignette du catalogue, sinon fichier d'origine), lues une fois.
    @Local private var originaux: [String: String] = [:]
    @Local private var serieLue: String? = nil
    @Local private var enLecture: String? = nil

    // 6. Aperçu
    @Local private var retouche = ""
    @Local private var confirmerMaintenant = false
    @Local private var celebre = false

    private enum ChoixMusique: Equatable { case proposee, piste(String), aucune }

    // MARK: État du jour

    private var vue: VueJour? { etat.vue }
    private var post: Post? { vue?.post }
    private var statut: String { vue?.statut ?? "nouveau" }
    private var etapes: [EtapeCreation] { EtapeCreation.etapes(aValider: etat.etapesAValider) }

    /// L'exécution de Claude qui concerne ce post (création ou retouche du jour affiché).
    private var execCreation: ExecutionClaude? {
        guard let e = etat.execution, !e.aucune, e.jour == nil || e.jour == etat.jour,
              e.tacheClaude == .creation || e.tacheClaude == .retouche else { return nil }
        return e
    }

    private var occupe: Bool { etat.occupe || etat.modificationEnCours || etat.lancementEnCours }

    private var heurePublication: String { post?.heure?.nonVide ?? vue?.creneau?.nonVide ?? "18:30" }

    /// L'étape qui correspond au statut du jour.
    private var etapeNaturelle: Int {
        if execCreation?.enCours == true { return 1 }
        switch statut {
        case "idee_choisie": return 1
        case "brouillon_pret": return suivante(apres: 1)
        case "echec": return 5
        case "reporte": return repris ? 5 : 6
        case "approuve", "publie": return 6
        default: return 0
        }
    }

    /// Prochaine étape à montrer après `k` : la première qu'elle valide et pas encore validée, sinon l'aperçu.
    private func suivante(apres k: Int) -> Int {
        let e = etapes
        var i = k + 1
        while i < 5 {
            if e[i].aValider && !valides.contains(e[i].id) { return i }
            i += 1
        }
        return 5
    }

    private var cleSynchro: String {
        [etat.jour, statut, execCreation?.id ?? "", execCreation?.etat ?? "", etat.etapesAValider.joined(separator: ","),
         post == nil ? "0" : "1", repris ? "r" : ""].joined(separator: "|")
    }

    // MARK: Corps

    var body: some View {
        GeometryReader { geo in
            let compacte = geo.size.height < 800
            ZStack {
                if initialise {
                    page(compacte: compacte, hauteur: geo.size.height)
                        .id(etape)
                        .transition(j.transition(avance ? .suivante : .precedente))
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .overlay(alignment: .bottom) {
            if initialise {
                PointsProgression(total: 6, courant: min(etape, 5)) { i in
                    if (2...4).contains(i), etapes[i].aValider, etape <= 5, retour(depuis: etape) != nil { aller(i) }
                }
                // Au-dessus de la rangée d'actions (marge 26 + grande pilule), jamais sur la même ligne.
                .padding(.bottom, 26 + j.esp.hauteurBouton + 8 + 14)
                .allowsHitTesting(etape >= 2)
            }
        }
        .task {
            if etat.reglages == nil { await etat.chargerReglages() }
            if etat.vue == nil || etat.vue?.jour != etat.jour { await etat.chargerJour() }
            synchroniser()
        }
        .onChange(of: cleSynchro) { _, _ in if initialise { synchroniser() } }
        .onDisappear { lecteur?.pause() }
        .sheet(isPresented: $galerieOuverte) {
            feuilleGalerie
                .environment(\.jetons, j)
                .environmentObject(etat)
        }
        .alert("Publier tout de suite ?", isPresented: $confirmerMaintenant) {
            Button("Publier maintenant") { Task { await etat.decider("approuver", "maintenant") } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Le post part maintenant sur Instagram, sans attendre \(heurePublication).")
        }
    }

    @ViewBuilder private func page(compacte: Bool, hauteur: CGFloat) -> some View {
        switch etape {
        case 0: pageIdee(compacte: compacte)
        case 1: pageClaude(compacte: compacte)
        case 2: pagePhotos(compacte: compacte)
        case 3: pageLegende(compacte: compacte)
        case 4: pageMusique(compacte: compacte)
        case 5: pageApercu(compacte: compacte, hauteur: hauteur)
        default: pageFin(compacte: compacte)
        }
    }

    // MARK: Navigation

    private func synchroniser() {
        valides = lireValides()
        let n = etapeNaturelle
        if n == 0 { lancerIdeesSiBesoin() }
        if !initialise {
            preparer(n)
            etape = n
            initialise = true
            return
        }
        guard n != etape else { return }
        // Claude, l'idée et la fin suivent le studio ; entre photos et aperçu, c'est elle qui avance.
        if etape <= 1 || n <= 1 || n == 6 || etape == 6 { aller(n) }
    }

    private func aller(_ k: Int) {
        avance = k >= etape
        preparer(k)
        withAnimation(j.anim(.page)) { etape = k }
    }

    private func preparer(_ k: Int) {
        lecteur?.pause()
        enLecture = nil
        nouvellesErreurs = false
        switch k {
        case 2: preparerPhotos()
        case 3:
            legende = post?.legende ?? ""
            legendeDepart = legende
        case 4: preparerMusique()
        case 5: retouche = ""
        case 6: celebre = false
        default: break
        }
    }

    /// Retour vers l'étape précédente qu'elle valide (jamais vers l'idée ni vers Claude).
    private func retour(depuis k: Int) -> (() -> Void)? {
        guard (3...5).contains(k), ["brouillon_pret", "echec", "reporte"].contains(statut) else { return nil }
        let e = etapes
        var i = k - 1
        while i >= 2 {
            if e[i].aValider { let cible = i; return { aller(cible) } }
            i -= 1
        }
        return nil
    }

    private func fermer() {
        lecteur?.pause()
        if ["idee_choisie", "brouillon_pret"].contains(statut) || execCreation?.enCours == true {
            etat.message = "Brouillon gardé. Tu le retrouves avec le « + »."
        }
        etat.montrer(.aujourdhui)
    }

    // Étapes validées du brouillon courant (préférences de l'app, par studio et par jour). Une nouvelle création
    // ou retouche terminée remet le compteur à zéro : le post a changé, elle revalide.
    private var cleValides: String { "creation.valides|\(etat.dossier.path)|\(etat.jour)" }

    private func lireValides() -> Set<String> {
        let d = UserDefaults.standard.dictionary(forKey: cleValides) ?? [:]
        let execution = d["execution"] as? String ?? ""
        if let e = execCreation, e.terminee, e.id != execution { return [] }
        return Set(d["etapes"] as? [String] ?? [])
    }

    private func marquerValide(_ id: String) {
        valides.insert(id)
        var execution = UserDefaults.standard.dictionary(forKey: cleValides)?["execution"] as? String ?? ""
        if let e = execCreation, e.terminee { execution = e.id }
        UserDefaults.standard.set(["execution": execution, "etapes": Array(valides).sorted()], forKey: cleValides)
    }

    private func illustration(_ sujet: SujetIllustration, _ taille: CGFloat) -> some View {
        Illustration(sujet, taille: taille).frame(width: taille, height: taille)
    }

    // MARK: 1. Idée (trois cartes, trois actions)

    @ViewBuilder private func pageIdee(compacte: Bool) -> some View {
        EtapeAssistant(etapes: etapes, courante: 0, titre: "De quoi parle ce post ?", fermer: fermer, fond: false) {
            TroisCartesIdees(hauteurCouverture: compacte ? 150 : 200, lancer: lancerIdees) { idee in
                Task { await etat.decider("choix", "\(idee.numero)") }
            }
        } actions: {
            ActionsIdees { texte in
                Task { await etat.decider("libre", texte) }
            }
        }
    }

    private func lancerIdees() {
        guard etat.librePourIdees else { return }
        Task { _ = await etat.lancerClaude(.idees, jour: etat.jour) }
    }

    /// Pas encore d'idées pour ce jour : Claude en prépare trois tout de suite (une seule fois par ouverture).
    private func lancerIdeesSiBesoin() {
        guard !ideesDemandees, (vue?.idees ?? []).isEmpty, etat.executionIdeesDuJour?.enCours != true,
              etat.librePourIdees else { return }
        ideesDemandees = true
        lancerIdees()
    }

    // MARK: 2. Claude au travail

    @ViewBuilder private func pageClaude(compacte: Bool) -> some View {
        let e = execCreation
        let enErreur = e?.etat == "erreur" || e?.etat == "annule"
        EtapeAssistant(etapes: etapes, courante: 1,
                       titre: enErreur ? "Claude s'est arrêté." : "Claude prépare ton post.",
                       texte: enErreur ? "Rien n'est perdu : ton idée est gardée. Tu peux relancer Claude."
                                       : "Il choisit les photos et leur ordre, puis écrit la légende, sous tes yeux.",
                       fermer: fermer, fond: false) {
            ScrollView {
                VStack(spacing: j.esp.sections * 0.6) {
                    illustration(enErreur ? .erreur : .attente, compacte ? 150 : 220)
                    if let e {
                        CarteActiviteClaude(execution: e,
                                            arreter: { Task { await etat.annulerClaude() } },
                                            reessayer: relancer,
                                            reconnecter: { Task { await etat.accepterInvitation() } })
                            .frame(maxWidth: 520)
                    } else {
                        VStack(spacing: 6) {
                            Text("Claude n'a pas encore commencé.").typo(.chapo)
                            if let inv = etat.invitationClaude {
                                Text(inv.texte).typo(.legende).multilineTextAlignment(.center).frame(maxWidth: 460)
                            } else {
                                Text("Tu peux fermer l'app : elle se rouvrira quand ce sera prêt.").typo(.legende)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
            }
        } actions: {
            if e?.enCours != true {
                if let inv = etat.invitationClaude {
                    Button { Task { await etat.accepterInvitation() } } label: { Label(inv.libelleBouton, systemImage: inv.symbole) }
                        .buttonStyle(BoutonPrincipal())
                        .keyboardShortcut(.defaultAction)
                } else if e?.reussie == true {
                    Button { Task { await etat.chargerJour() } } label: { Label("Actualiser", systemImage: "arrow.triangle.2.circlepath") }
                        .buttonStyle(BoutonPilule(.claire))
                } else {
                    Button { relancer() } label: { Label(e == nil ? "Lancer Claude" : "Relancer Claude", systemImage: "sparkles") }
                        .buttonStyle(BoutonPrincipal(enCours: etat.lancementEnCours))
                        .keyboardShortcut(.defaultAction)
                        .disabled(etat.claudeTravaille || etat.lancementEnCours)
                }
            }
        }
    }

    private func relancer() {
        let e = execCreation
        Task {
            if e?.tacheClaude == .retouche, let c = e?.consigne?.nonVide {
                _ = await etat.lancerClaude(.retouche, jour: etat.jour, consigne: c)
            } else {
                _ = await etat.lancerClaude(.creation, jour: etat.jour)
            }
        }
    }

    // MARK: 3. Photos

    private var photosModifiables: Bool { etat.mediasDuPost != nil && post?.format != "reel" }

    private func preparerPhotos() {
        lireCatalogue()
        let m = etat.mediasDuPost ?? []
        medias = m
        mediasDepart = m
        var im: [String: String] = [:]
        for x in post?.medias ?? [] {
            if let id = x.photo_id?.nonVide, let c = vignetteCatalogue(id) ?? x.image { im[id] = c }
        }
        images = im
    }

    /// La photo d'origine (vignette du catalogue `catalogue/<serie>/vignettes/<photo_id>.jpg`), plein cadre,
    /// plutôt que l'image mise en page (marges papier) ; nil si elle n'existe pas.
    private func vignetteCatalogue(_ photoId: String?) -> String? {
        guard let id = photoId?.nonVide else { return nil }
        return originaux[id]
    }

    /// Lit `catalogue/<serie>/photos.json` (lecture seule) : pour chaque photo, sa vignette
    /// (`vignettes/<photo_id>.jpg` ou le champ `vignette`) si elle existe, sinon son fichier d'origine (`chemin_local`).
    private func lireCatalogue() {
        guard let serie = post?.serie?.nonVide, serieLue != serie else { return }
        serieLue = serie
        let dossier = etat.dossier.appendingPathComponent("catalogue").appendingPathComponent(serie)
        guard let data = try? Data(contentsOf: dossier.appendingPathComponent("photos.json")),
              let objet = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let photos = objet["photos"] as? [[String: Any]] else {
            originaux = [:]
            return
        }
        let fm = FileManager.default
        var r: [String: String] = [:]
        for p in photos {
            guard let id = p["id"] as? String, !id.isEmpty else { continue }
            let v = dossier.appendingPathComponent((p["vignette"] as? String)?.nonVide ?? "vignettes/\(id).jpg").path
            if fm.fileExists(atPath: v) {
                r[id] = v
            } else if let c = (p["chemin_local"] as? String)?.nonVide, fm.fileExists(atPath: c) {
                r[id] = c
            }
        }
        originaux = r
    }

    @ViewBuilder private func pagePhotos(compacte: Bool) -> some View {
        let modifiable = photosModifiables
        EtapeAssistant(etapes: etapes, courante: 2, titre: "Les photos que Claude propose",
                       texte: modifiable ? "Retire, ajoute, glisse pour changer l'ordre."
                           : (post?.format == "reel" ? "Le Reel est monté par Claude : tu le verras en entier dans l'aperçu."
                                                     : "Voici la séquence choisie par Claude."),
                       retour: retour(depuis: 2), fermer: fermer, fond: false) {
            ScrollView {
                VStack(spacing: j.esp.blocs + 4) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 132, maximum: 170), spacing: 14)], spacing: 14) {
                        if modifiable {
                            ForEach(Array(medias.enumerated()), id: \.element.id) { i, m in
                                tuile(m.photo_id, chemin: images[m.photo_id], index: i, modifiable: true)
                            }
                            tuileAjouter
                        } else if post?.format == "reel" {
                            tuile("couverture", chemin: post?.couverture, index: 0, modifiable: false)
                        } else {
                            ForEach(Array((post?.medias ?? []).enumerated()), id: \.element.id) { i, m in
                                tuile("\(m.ordre)", chemin: vignetteCatalogue(m.photo_id) ?? m.image, index: i, modifiable: false)
                            }
                        }
                    }
                    .frame(maxWidth: 900)
                    if modifiable && medias != mediasDepart {
                        Button("Revenir à la proposition de Claude") {
                            withAnimation(j.anim(.selection)) { preparerPhotos() }
                        }
                        .buttonStyle(.discret)
                    }
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
            }
        } actions: {
            if modifiable {
                Text(medias.count == 1 ? "1 photo" : "\(medias.count) photos").typo(.legende)
            }
            Button { Task { await validerPhotos() } } label: { Label("Valider les photos", systemImage: "checkmark") }
                .buttonStyle(BoutonPrincipal(enCours: etat.modificationEnCours))
                .keyboardShortcut(.defaultAction)
                .disabled(occupe || (modifiable && medias.isEmpty))
        }
    }

    @ViewBuilder private func tuile(_ id: String, chemin: String?, index: Int, modifiable: Bool) -> some View {
        let forme = RoundedRectangle(cornerRadius: j.rayons.photo, style: .continuous)
        let base = ImageLocale(chemin: chemin)
            .id("\(chemin ?? id)-\(etat.versionImages)")
            .aspectRatio(4 / 5, contentMode: .fit)
            .clipShape(forme)
            .overlay(forme.strokeBorder(cibleDepot == id ? j.accent : Color.clear, lineWidth: 2.5))
            .overlay(alignment: .topLeading) { Pastille("\(index + 1)", ton: .forte).padding(7) }
            .overlay(alignment: .topTrailing) {
                if modifiable && survolPhoto == id && medias.count > 1 {
                    Button { retirer(id) } label: { Image(systemName: "xmark") }
                        .buttonStyle(BoutonRond(.claire, diametre: 26))
                        .padding(6)
                        .help("Retirer cette photo")
                        .accessibilityLabel("Retirer la photo \(index + 1)")
                        .transition(.opacity)
                }
            }
            .ombre(.carte)
            .contentShape(forme)
            .onHover { dedans in
                withAnimation(j.anim(.survol)) {
                    if dedans { survolPhoto = id } else if survolPhoto == id { survolPhoto = nil }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Photo \(index + 1)")
        if modifiable {
            base
                .draggable(id) {
                    ImageLocale(chemin: chemin).frame(width: 80, height: 100).clipShape(forme)
                }
                .dropDestination(for: String.self) { ids, _ in
                    deplacer(ids.first, vers: id)
                    return true
                } isTargeted: { dessus in
                    if dessus { cibleDepot = id } else if cibleDepot == id { cibleDepot = nil }
                }
                .accessibilityAction(named: "Avancer d'une place") { decaler(id, de: -1) }
                .accessibilityAction(named: "Reculer d'une place") { decaler(id, de: 1) }
                .accessibilityAction(named: "Retirer") { retirer(id) }
        } else {
            base
        }
    }

    private var tuileAjouter: some View {
        Button { ouvrirGalerie() } label: {
            ZStack {
                CadreTraitsDeCoupe(rayon: j.rayons.photo)
                VStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 20, weight: .light))
                    Text("Ajouter").typo(.corpsFort, couleur: j.texteSecondaire)
                }
                .foregroundStyle(j.texteSecondaire)
            }
            .aspectRatio(4 / 5, contentMode: .fit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Ajouter une photo de la série")
        .accessibilityLabel("Ajouter une photo")
    }

    private func retirer(_ id: String) {
        guard medias.count > 1 else { return }
        withAnimation(j.anim(.selection)) {
            medias.removeAll { $0.photo_id == id }
            if survolPhoto == id { survolPhoto = nil }
        }
    }

    private func deplacer(_ source: String?, vers cible: String) {
        cibleDepot = nil
        guard let s = source, s != cible,
              let de = medias.firstIndex(where: { $0.photo_id == s }),
              let vers = medias.firstIndex(where: { $0.photo_id == cible }) else { return }
        withAnimation(j.anim(.selection)) {
            let m = medias.remove(at: de)
            medias.insert(m, at: vers)
        }
    }

    private func decaler(_ id: String, de pas: Int) {
        guard let i = medias.firstIndex(where: { $0.photo_id == id }) else { return }
        let k = i + pas
        guard medias.indices.contains(k) else { return }
        withAnimation(j.anim(.selection)) { medias.swapAt(i, k) }
    }

    private func ouvrirGalerie() {
        galerieOuverte = true
        guard candidatsSerie.isEmpty, let serie = post?.serie?.nonVide else { return }
        Task {
            chargementCandidats = true
            candidatsSerie = await etat.candidats(serie: serie)
            chargementCandidats = false
        }
    }

    private var candidatsDisponibles: [PhotoCandidate] {
        candidatsSerie.filter { c in !medias.contains { $0.photo_id == c.id } }
    }

    private var feuilleGalerie: some View {
        VStack(alignment: .leading, spacing: j.esp.blocs) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ajouter une photo").typo(.titre2)
                    Text("Les photos de la série, les mieux notées d'abord. Un clic l'ajoute à la fin.").typo(.legende)
                }
                Spacer()
                Button { galerieOuverte = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(BoutonRond(.claire, diametre: 32))
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Fermer")
            }
            if chargementCandidats {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if candidatsDisponibles.isEmpty {
                Text(post?.serie == nil ? "Ce post n'indique pas sa série : demande la photo à Claude dans l'aperçu."
                                        : "Aucune autre photo à proposer pour cette série.")
                    .typo(.chapo)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 140), spacing: 10)], spacing: 10) {
                        ForEach(candidatsDisponibles) { c in
                            Button { ajouter(c) } label: { vignetteCandidate(c) }
                                .buttonStyle(.plain)
                                .help(c.description ?? "Ajouter cette photo")
                        }
                    }
                    .padding(2)
                }
            }
        }
        .padding(j.esp.carte)
        .frame(width: 760, height: 560)
        .background(FondAmbiance(anime: false))
    }

    private func vignetteCandidate(_ c: PhotoCandidate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ImageLocale(chemin: c.vignette ?? originaux[c.id])
                .aspectRatio(4 / 5, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: j.rayons.photo, style: .continuous))
                .survol(.photo)
            HStack(spacing: 1) {
                ForEach(0..<5, id: \.self) { i in
                    Image(systemName: i < c.etoiles ? "star.fill" : "star")
                        .font(.system(size: 9))
                        .foregroundStyle(i < c.etoiles ? j.accentTexte : j.texteTertiaire)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(c.etoiles) étoiles sur 5")
        }
    }

    private func ajouter(_ c: PhotoCandidate) {
        withAnimation(j.anim(.selection)) {
            medias.append(MediaModifie(photo_id: c.id))
            if let v = c.vignette ?? originaux[c.id] { images[c.id] = v }
        }
        galerieOuverte = false
    }

    private func validerPhotos() async {
        if photosModifiables && medias != mediasDepart {
            guard await etat.modifierPost(medias: medias) else { return }
            mediasDepart = medias
        }
        marquerValide("photos")
        aller(suivante(apres: 2))
    }

    // MARK: 4. Légende

    private var nombreHashtags: Int { legende.split(whereSeparator: { $0.isWhitespace }).filter { $0.hasPrefix("#") }.count }

    @ViewBuilder private func pageLegende(compacte: Bool) -> some View {
        let modifiee = legende != legendeDepart
        let trop = legende.count > 2200
        EtapeAssistant(etapes: etapes, courante: 3, titre: "La légende", texte: "Claude l'a écrite ; modifie-la directement.",
                       retour: retour(depuis: 3), fermer: fermer, fond: false) {
            HStack(alignment: .top, spacing: j.esp.sections * 0.7) {
                VStack(alignment: .leading, spacing: 8) {
                    EditeurLegende(texte: $legende)
                        .frame(minHeight: 200, maxHeight: 420)
                    HStack {
                        Text("\(legende.count.formatted()) / 2 200")
                            .typo(.legende, couleur: trop ? j.alerte : j.texteSecondaire)
                            .monospacedDigit()
                        if nombreHashtags > 0 {
                            Text("· \(nombreHashtags) hashtag\(nombreHashtags > 1 ? "s" : "")").typo(.legende)
                        }
                        Spacer()
                        if modifiee {
                            Button("Revenir au texte de Claude") { legende = legendeDepart }
                                .buttonStyle(.discret)
                        }
                    }
                }
                .frame(maxWidth: 600)
                ScrollView {
                    VStack(alignment: .leading, spacing: j.esp.blocs) {
                        controleLegende(modifiee: modifiee, trop: trop)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 280)
            }
            .frame(maxWidth: .infinity)
        } actions: {
            Button { Task { await validerLegende() } } label: { Label("Valider la légende", systemImage: "checkmark") }
                .buttonStyle(BoutonPrincipal(enCours: etat.modificationEnCours))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(occupe || legende.nonVide == nil || trop)
                .help("Valider (⌘⏎)")
        }
    }

    @ViewBuilder private func controleLegende(modifiee: Bool, trop: Bool) -> some View {
        let v = vue?.verdict
        let erreurs = v?.erreurs ?? []
        let vigilance = (v?.alertes ?? []) + (v?.avertissements ?? [])
        VStack(alignment: .leading, spacing: j.esp.pile + 2) {
            Text("Contrôle du studio").typo(.surtitre)
            if modifiee {
                Pastille("Modifiée", symbole: "pencil.line", ton: .aToi)
                Text("Le contrôle sera refait quand tu valides.").typo(.legende).fixedSize(horizontal: false, vertical: true)
            } else if !erreurs.isEmpty {
                Pastille("À corriger", symbole: "exclamationmark.triangle.fill", ton: .alerte)
            } else if !vigilance.isEmpty {
                Pastille(vigilance.count == 1 ? "1 point à vérifier" : "\(vigilance.count) points à vérifier",
                         symbole: "exclamationmark.circle.fill", ton: .douce)
            } else if v != nil {
                Pastille("Tout est en règle", symbole: "checkmark.circle.fill", ton: .succes)
            }
            if !modifiee {
                if !erreurs.isEmpty { ListePoints(elements: erreurs, couleur: j.alerte) }
                if !vigilance.isEmpty { ListePoints(elements: vigilance) }
            }
            if trop {
                ListePoints(elements: ["Plus de 2 200 caractères : Instagram refusera la légende."], couleur: j.alerte)
            }
            if nombreHashtags > 30 {
                ListePoints(elements: ["Plus de 30 hashtags : Instagram en refuse au-delà."], couleur: j.alerte)
            }
            if nouvellesErreurs {
                Text("C'est enregistré, mais le contrôle a trouvé quelque chose : regarde, puis valide encore pour continuer.")
                    .typo(.legende, couleur: j.alerte)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func validerLegende() async {
        let texte = legende.trimmingCharacters(in: .whitespacesAndNewlines)
        if texte != legendeDepart.trimmingCharacters(in: .whitespacesAndNewlines) {
            let avant = vue?.verdict?.erreurs?.count ?? 0
            guard await etat.modifierPost(legende: texte) else { return }
            legende = texte
            legendeDepart = texte
            // Le contrôle refait trouve une nouvelle erreur : elle la voit avant de continuer.
            if (etat.vue?.verdict?.erreurs?.count ?? 0) > avant {
                nouvellesErreurs = true
                return
            }
        }
        nouvellesErreurs = false
        marquerValide("legende")
        aller(suivante(apres: 3))
    }

    // MARK: 5. Musique

    private var musiqueProposee: Musique? {
        guard let m = post?.musique, m.mode != "aucune", m.titre != nil || m.direction_sonore != nil else { return nil }
        return m
    }

    private var choixMusiqueDepart: ChoixMusique { musiqueProposee != nil ? .proposee : .aucune }

    private func preparerMusique() {
        choixMusique = choixMusiqueDepart
        guard !musiqueCherchee else { return }
        musiqueCherchee = true
        let m = post?.musique
        let requete = m?.requete?.nonVide
            ?? [m?.titre, m?.artiste].compactMap { $0 }.joined(separator: " ").nonVide
            ?? m?.direction_sonore?.nonVide
            ?? vue?.choix.flatMap { _ in vue?.idees?.first { $0.numero == vue?.choix?.numero }?.musique }
            ?? ""
        Task {
            rechercheMusique = true
            let avant = etat.erreur
            let r = await etat.chercherMusique(requete)
            if r.isEmpty && etat.erreur != avant {
                etat.erreur = avant
                noteMusique = "La bibliothèque musicale d'Instagram n'est pas joignable pour l'instant : "
                    + "garde la proposition de Claude ou choisis « Sans musique »."
            }
            pistes = Array(r.filter { $0.audio_id != m?.audio_id }.prefix(3))
            rechercheMusique = false
        }
    }

    @ViewBuilder private func pageMusique(compacte: Bool) -> some View {
        EtapeAssistant(etapes: etapes, courante: 4, titre: "La musique",
                       texte: musiqueProposee != nil ? "Claude a choisi une piste ; garde-la ou prends-en une autre." : "Choisis une piste, ou garde le silence.",
                       retour: retour(depuis: 4), fermer: fermer, fond: false) {
            HStack(alignment: .top, spacing: j.esp.sections * 0.7) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let m = musiqueProposee {
                            carteMusique(.proposee, titre: m.titre ?? "L'ambiance proposée",
                                         detail: [m.artiste, Musique.libelleMode(m.mode)].compactMap { $0 }.joined(separator: " · "),
                                         voix: m.direction_sonore, apercu: m.apercu_url)
                        }
                        if rechercheMusique {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Je cherche d'autres pistes…").typo(.voixCarte, couleur: j.texteSecondaire)
                            }
                        }
                        ForEach(pistes) { p in
                            carteMusique(.piste(p.id), titre: p.titre ?? "Sans titre",
                                         detail: [p.artiste, p.duree_s.map { Self.duree($0) }].compactMap { $0 }.joined(separator: " · "),
                                         voix: nil, apercu: p.apercu_url)
                        }
                        if let n = noteMusique { Text(n).typo(.legende).fixedSize(horizontal: false, vertical: true) }
                        carteMusique(.aucune, titre: "Sans musique", detail: "Le post part en silence.", voix: nil, apercu: nil)
                        if post?.format != "reel" && choixMusique != .aucune {
                            Text("Sur un carrousel, Instagram ne laisse pas le studio ajouter la musique : tu l'ajouteras dans Instagram, juste après la publication.")
                                .typo(.legende)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: 560)
            }
            .frame(maxWidth: .infinity)
        } actions: {
            Button { Task { await validerMusique() } } label: {
                Label(choixMusique == .aucune ? "Continuer sans musique" : "Garder cette musique", systemImage: "music.note")
            }
            .buttonStyle(BoutonPrincipal(enCours: etat.modificationEnCours))
            .keyboardShortcut(.defaultAction)
            .disabled(occupe)
        }
    }

    private func carteMusique(_ choix: ChoixMusique, titre: String, detail: String?, voix: String?, apercu: String?) -> some View {
        let choisie = choixMusique == choix
        let cle: String = {
            switch choix {
            case .proposee: return "proposee"
            case .piste(let id): return id
            case .aucune: return "aucune"
            }
        }()
        return Carte(style: .cliquable, choisie: choisie) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: choix == .aucune ? "speaker.slash" : "music.note")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(j.texte)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(j.fondDoux))
                VStack(alignment: .leading, spacing: 4) {
                    Text(titre).typo(.titre3).fixedSize(horizontal: false, vertical: true)
                    if let d = detail?.nonVide { Text(d).typo(.legende) }
                    if let v = voix?.nonVide { VoixDeClaude(v, compacte: true).padding(.top, 2) }
                }
                Spacer(minLength: 8)
                if let a = apercu, URL(string: a) != nil {
                    Button { ecouter(cle, a) } label: { Image(systemName: enLecture == cle ? "pause.fill" : "play.fill") }
                        .buttonStyle(BoutonRond(.claire, diametre: 34))
                        .help(enLecture == cle ? "Arrêter l'extrait" : "Écouter un extrait")
                        .accessibilityLabel(enLecture == cle ? "Arrêter l'extrait" : "Écouter un extrait")
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(j.anim(.selection)) { choixMusique = choix } }
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(choisie ? .isSelected : [])
    }

    private func ecouter(_ cle: String, _ adresse: String) {
        if enLecture == cle {
            lecteur?.pause()
            enLecture = nil
            return
        }
        guard let url = URL(string: adresse) else { return }
        lecteur?.pause()
        let p = AVPlayer(url: url)
        p.play()
        lecteur = p
        enLecture = cle
    }

    private static func duree(_ s: Double) -> String {
        let t = Int(s.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    private func validerMusique() async {
        lecteur?.pause()
        enLecture = nil
        if choixMusique != choixMusiqueDepart {
            var m: Musique?
            switch choixMusique {
            case .aucune: m = Musique(mode: "aucune")
            case .proposee: m = post?.musique
            case .piste(let id):
                if let p = pistes.first(where: { $0.id == id }) {
                    var x = p.musique()
                    if post?.format != "reel" {
                        x.mode = "a_ajouter_dans_l_app"
                        x.volume_musique = nil
                        x.volume_video = nil
                    }
                    m = x
                }
            }
            if let m {
                guard await etat.modifierPost(musique: m) else { return }
            }
        }
        marquerValide("musique")
        aller(5)
    }

    // MARK: 6. Aperçu et publication

    private var dateCourte: String? {
        guard let d = vue?.date_longue?.nonVide else { return nil }
        let mots = d.split(separator: " ")
        return mots.count > 2 ? mots.dropFirst().joined(separator: " ") : d
    }

    private var contenuInstagram: ContenuInstagram {
        let p = post
        let format = FormatInstagram(p?.format)
        let chemins = format == .reel ? [p?.couverture].compactMap { $0 }
            : (p?.medias ?? []).sorted { $0.ordre < $1.ordre }.compactMap { $0.image }
        var texte = p?.legende ?? ""
        let tags = (p?.hashtags ?? []).map { $0.hasPrefix("#") ? $0 : "#" + $0 }.filter { !texte.contains($0) }
        if !tags.isEmpty { texte += (texte.isEmpty ? "" : "\n\n") + tags.joined(separator: " ") }
        var musique: String? = nil
        if let m = p?.musique, m.mode != "aucune", let t = m.titre {
            musique = [t, m.artiste].compactMap { $0 }.joined(separator: " · ")
        }
        return ContenuInstagram(compte: p?.compte?.nonVide ?? "ton.compte", collaborateurs: p?.collaborateurs ?? [],
                                lieu: p?.localisation?.nonVide, musique: musique, medias: chemins, format: format,
                                legende: texte, date: dateCourte, heure: heurePublication)
    }

    private var publicationBloquee: Bool {
        occupe || post == nil || !(vue?.verdict?.erreurs ?? []).isEmpty || execCreation?.enCours == true
    }

    /// Hauteur du téléphone : la fenêtre moins le haut d'`EtapeAssistant` (feux, rappel, titre, chapô ≈ 190 pt),
    /// sa rangée d'actions (≈ 86 pt), les marges du contenu et la place des points de progression.
    private func hauteurTelephone(_ hauteur: CGFloat) -> CGFloat {
        min(TelephoneInstagram.hauteur, max(300, hauteur - 190 - 86 - 2 * j.esp.sections * 0.6 - 40))
    }

    @ViewBuilder private func pageApercu(compacte: Bool, hauteur: CGFloat) -> some View {
        let hTel = hauteurTelephone(hauteur)
        EtapeAssistant(etapes: etapes, courante: 5, titre: "Voici ton post.",
                       texte: statut == "echec" ? "La publication n'est pas passée. Vérifie, puis réessaie."
                                                : "Il partira à \(heurePublication) si tu le valides.",
                       retour: retour(depuis: 5), fermer: fermer, fond: false) {
            HStack(alignment: .top, spacing: j.esp.sections) {
                TelephoneInstagram(contenu: contenuInstagram)
                    .id(etat.versionImages)
                    .frame(width: hTel * TelephoneInstagram.largeur / TelephoneInstagram.hauteur, height: hTel)
                ScrollView { colonneDecision(compacte: compacte) }
                    .frame(maxWidth: 440, maxHeight: hTel)
            }
            .frame(maxWidth: .infinity)
        } actions: {
            Button { Task { await etat.decider("reporter") } } label: { Label("Reporter", systemImage: "calendar.badge.clock") }
                .buttonStyle(BoutonPilule(.claire))
                .disabled(occupe || post == nil)
            Button { confirmerMaintenant = true } label: { Label("Publier maintenant…", systemImage: "paperplane") }
                .buttonStyle(BoutonPilule(.claire))
                .disabled(publicationBloquee)
            Button { Task { await etat.decider("approuver", "creneau") } } label: {
                Label("Publier à \(heurePublication)", systemImage: "paperplane.fill")
            }
            .buttonStyle(BoutonPrincipal(enCours: etat.occupe))
            .keyboardShortcut(.defaultAction)
            .disabled(publicationBloquee)
        }
    }

    @ViewBuilder private func colonneDecision(compacte: Bool) -> some View {
        let v = vue?.verdict
        let erreurs = v?.erreurs ?? []
        let vigilance = (v?.alertes ?? []) + (v?.avertissements ?? [])
        VStack(alignment: .leading, spacing: j.esp.blocs) {
            if !erreurs.isEmpty {
                Pastille("À corriger avant publication", symbole: "exclamationmark.triangle.fill", ton: .alerte)
                ListePoints(elements: erreurs, couleur: j.alerte)
                Text("Claude peut s'en occuper : dis-le-lui juste en dessous.").typo(.legende)
            } else if !vigilance.isEmpty {
                Pastille(vigilance.count == 1 ? "Prêt, 1 point à vérifier" : "Prêt, \(vigilance.count) points à vérifier",
                         symbole: "exclamationmark.circle.fill", ton: .douce)
                ListePoints(elements: vigilance)
            } else if v != nil {
                Pastille("Prêt à publier", symbole: "checkmark.circle.fill", ton: .succes)
            }
            VStack(alignment: .leading, spacing: j.esp.pile + 2) {
                Text("Changer quelque chose ?").typo(.titre3)
                ChampDoux(texte: $retouche, exemple: "Une photo, l'ordre, un mot de la légende… dis-le simplement.",
                          lignes: 2...5, envoyer: demanderRetouche)
                Button { demanderRetouche() } label: { Label("Demander une retouche à Claude", systemImage: "pencil.line") }
                    .buttonStyle(BoutonPilule(.claire, taille: .petite))
                    .disabled(retouche.nonVide == nil || occupe || etat.claudeTravaille)
            }
            .padding(.top, j.esp.pile)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func demanderRetouche() {
        guard let t = retouche.nonVide, !occupe, !etat.claudeTravaille else { return }
        Task {
            await etat.decider("retouche", t)
            retouche = ""
        }
    }

    // MARK: Fin (validé, publié, reporté)

    private var quandPublication: String {
        guard let p = vue?.publier_a, p.count >= 16 else { return "à \(heurePublication)" }
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

    @ViewBuilder private func pageFin(compacte: Bool) -> some View {
        let publie = statut == "publie"
        let reporte = statut == "reporte"
        EtapeAssistant(etapes: etapes, courante: 6,
                       titre: publie ? "C'est en ligne !" : (reporte ? "Reporté." : "Validé."),
                       texte: publie ? "Ton post est publié sur Instagram."
                           : (reporte ? "Rien ne part aujourd'hui ; tu pourras le reprendre plus tard."
                                      : "Il partira \(quandPublication). Tu peux fermer l'app."),
                       fermer: fermer, fond: false) {
            VStack {
                Spacer(minLength: 0)
                illustration(reporte ? .attente : .publication, compacte ? 200 : 270)
                    .scaleEffect(celebre || !j.deplacements ? 1 : 0.82)
                    .opacity(celebre ? 1 : 0.4)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .onAppear { withAnimation(j.anim(.celebration) ?? j.anim(.doux)) { celebre = true } }
        } actions: {
            if publie, let l = vue?.permalink, let url = URL(string: l) {
                Button { NSWorkspace.shared.open(url) } label: { Label("Voir sur Instagram", systemImage: "arrow.up.right.square") }
                    .buttonStyle(BoutonPilule(.claire))
            }
            if reporte && post != nil {
                Button {
                    repris = true
                } label: { Label("Reprendre ce post", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(BoutonPilule(.claire))
            }
            Button { etat.montrer(.aujourdhui) } label: { Label("Revenir à la journée", systemImage: "sun.max") }
                .buttonStyle(BoutonPrincipal())
                .keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - Éditeur de légende

/// Grand champ de la légende, au style de `ChampDoux`, mais où ⏎ va à la ligne (TextEditor).
private struct EditeurLegende: View {
    @Binding var texte: String
    @Environment(\.jetons) private var j
    @FocusState private var focus: Bool

    var body: some View {
        let forme = RoundedRectangle(cornerRadius: j.rayons.champ, style: .continuous)
        TextEditor(text: $texte)
            .font(Font.jakarta(16))
            .lineSpacing(5)
            .foregroundStyle(j.texte)
            .scrollContentBackground(.hidden)
            .focused($focus)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(forme.fill(j.schema == .dark ? j.surfaceElevee : Color.white))
            .overlay(forme.strokeBorder(focus ? j.encre.opacity(0.75) : j.traitFort.opacity(0.8), lineWidth: focus ? 1.5 : 1))
            .background(forme.stroke(j.accent.opacity(focus ? 0.16 : 0), lineWidth: 8))
            .animation(j.anim(.survol), value: focus)
            .accessibilityLabel("Légende du post")
    }
}
