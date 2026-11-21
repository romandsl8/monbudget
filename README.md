# Mon Budget — app iPhone (SwiftUI + SwiftData)

Gestion de budget : solde de départ, prélèvements/revenus récurrents, solde dynamique et projection.
Compilée et envoyée sur TestFlight par **GitHub Actions** (aucun Mac nécessaire), comme MonVoyage.

## Fonctionnalités

- **Solde de départ** + date à laquelle il a été constaté (écran d'accueil au 1er lancement, modifiable dans Réglages).
- **Opérations** : dépense ou revenu, montant, fréquence (ponctuelle, hebdo, 2 semaines, mensuelle, trimestrielle, annuelle), première échéance, date de fin optionnelle, catégorie, note, pause.
- **Solde dynamique** : solde du jour recalculé automatiquement à partir des échéances passées.
- **Tableau de bord** : solde du jour, fin de mois, dépenses du mois, point bas, graphique (30 j / 3 mois / 1 an), échéances à venir avec le solde après chacune.

## iPhone Duo plié / déplié

Compilée avec **Xcode 27.2 (SDK iOS 27)**. Aucune taille d'écran codée en dur :

| Élément | Plié (largeur *compact*) | Déplié (largeur *regular*) |
|---|---|---|
| Navigation (`TabView` `.sidebarAdaptable`) | barre d'onglets | barre latérale possible |
| Opérations (`NavigationSplitView`) | liste → détail empilés | liste et détail côte à côte |
| Tableau de bord | une colonne | deux colonnes |

Toutes les orientations sont autorisées et `UIRequiresFullScreen` n'est pas défini : l'appli se redimensionne à chaud.

## Mise en place (une seule fois)

Les étapes Apple sont les mêmes que pour MonVoyage (voir son `GUIDE_MISE_EN_PLACE.md`), en plus court : pas d'iCloud, pas de widget, pas d'App Group.

1. **Secrets GitHub** du dépôt `monbudget` (Settings → Secrets and variables → Actions → Secrets) — les **mêmes valeurs que MonVoyage** :
   `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_KEY_IDENTIFIER`, `APP_STORE_CONNECT_PRIVATE_KEY`, `CERTIFICATE_PRIVATE_KEY`.
2. **Lancer le workflow** (Actions → *MonBudget → TestFlight* → Run workflow). Il enregistre automatiquement le bundle ID `fr.tanguy.monbudget` chez Apple, puis compile et teste.
3. **App Store Connect** → Apps → **+ Nouvelle app** : iOS, nom `Mon Budget` (ou une variante si pris), langue Français, bundle ID `fr.tanguy.monbudget`, SKU `monbudget`. Notez l'**Identifiant Apple** (10 chiffres) dans *Informations sur l'app*.
4. **Variable GitHub** (onglet Variables) `APP_STORE_APPLE_ID` = cet identifiant — ou envoyez-le à Claude Code.
5. **TestFlight** → Tests internes → groupe avec votre compte. Relancez le workflow : le build arrive dans TestFlight.

Ensuite, chaque push sur `main` lance tests → build → TestFlight automatiquement.

## Structure

```
MonBudget/
  MonBudgetApp.swift        point d'entrée + navigation racine
  Models/                   BudgetEntry (SwiftData), BalanceEngine, AccountSettings / Money
  Views/                    Dashboard, Entries (liste/détail), EntryEditor, Settings
  Resources/Assets.xcassets icône (générée par scripts/make_icon.py) et couleur d'accent
MonBudgetTests/             tests du calcul des échéances et du solde
project.yml                 projet XcodeGen
.github/workflows/          build + TestFlight
```
