# RimWorld 1.7 multijoueur : le modpack du groupe

Tout ce qu'il faut pour jouer ensemble à RimWorld 1.7 avec le mod Multiplayer, sans désynchronisation.
La plupart des mods viennent du Steam Workshop ; les autres (versions 1.7 de Multiplayer, les mods de Raysor…)
sont installés par un petit installateur.

## Installation (une seule fois)

1. **RimSort** : télécharge et installe [RimSort](https://github.com/RimSort/RimSort/releases/latest)
   (fichier qui se termine par `Windows_x86_64.msi`). Au premier lancement, laisse-le trouver les dossiers de RimWorld.
2. **Les mods du groupe** : RimWorld fermé, télécharge
   [**Installer.bat**](https://github.com/MrRaysor/RimWorld17-Multijoueur/releases/latest/download/Installer.bat)
   et double-clique dessus. Si Windows affiche « Windows a protégé votre ordinateur », clique sur
   « Informations complémentaires » puis « Exécuter quand même ». Il trouve RimWorld tout seul et installe les mods
   qui ne sont pas sur le Workshop. Il doit finir par « Terminé ! ».
3. **La liste de mods** : dans RimSort, menu `File` → `Import` → `From Rentry.co`, colle le lien envoyé par Raysor
   (ou `File` → `Open Mod List…` s'il t'a envoyé un fichier). RimSort signale les mods manquants : choisis
   **Download with Steam client** (Steam ouvert) et attends la fin des téléchargements. Clique ensuite sur `Save`,
   puis lance le jeu avec `Run`.

## Mises à jour

Quand Raysor annonce une mise à jour : relance `Installer.bat` (il ne retélécharge que ce qui a changé), puis
laisse Steam mettre à jour les mods du Workshop avant de jouer. Tout le monde doit avoir exactement les mêmes versions.

## Pour jouer

- **Même version de RimWorld** pour tous (visible en bas à gauche du menu principal). Après une mise à jour de
  RimWorld, attendre le feu vert de Raysor.
- L'hôte coche **« Sync mod configs »** dans la fenêtre d'hébergement : les réglages de mods de l'hôte sont envoyés
  à ceux qui rejoignent. Ne pas changer les réglages des mods en cours de partie.
- On peut se connecter ou se reconnecter pendant que les autres jouent.
- Les fenêtres qui mettent la carte en pause pour tout le monde (caravane, cargaison d'un véhicule, rituel,
  commerce) : valider ou annuler rapidement.
- **En cas de desync**, Multiplayer propose de se reconnecter : accepter. Si cela se répète, envoyer à Raysor les
  fichiers `Desync-XX.zip` du dossier
  `%USERPROFILE%\AppData\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\MpDesyncs`.

## À éviter en partie à plusieurs

Ces outils n'agissent que chez celui qui clique : **Character Editor**, l'éditeur de **Custom Base Framework**,
le remplissage (« Flood Fill ») de **Designator Shapes**. L'hôte peut s'en servir seul, avant que les autres se
connectent. En multifaction, ne pas utiliser « tout autoriser » d'**Allow Tool**.

## Contenu du modpack

| Mod | Rôle |
|---|---|
| Multiplayer (1.7 dev build) | Le mod Multiplayer recompilé pour RimWorld 1.7 (pas de version officielle 1.7), avec des corrections de desync. |
| Multiplayer Compatibility (1.7 dev build) | La compatibilité multijoueur des mods populaires, pour 1.7. |
| Raysor's Multiplayer Patch | Le patch du groupe : synchronise les boutons et menus des mods et corrige les desyncs propres à notre liste. |
| Vehicle Framework (1.7 dev build) | Pour les mods de véhicules (sans effet s'il n'est pas activé dans la liste). |
| Exodia Mechanoids, Mecha Outposts, Raysor - Faction Leader Fix, Raysor - Loadout Fix | Les mods de Raysor. |

L'installateur ne touche qu'à ces dossiers du dossier `Mods` de RimWorld : ni aux autres mods, ni aux sauvegardes,
ni à la liste de mods.

## Licences et sources

Multiplayer (© Zetrith et contributeurs), Multiplayer Compatibility (© Meru et contributeurs) et Vehicle Framework
(© SmashPhil) sont sous licence MIT ; leur licence est incluse dans chaque mod. Sources des versions 1.7 :
[MrRaysor/Multiplayer](https://github.com/MrRaysor/Multiplayer/tree/raysor-1.7) et
[MrRaysor/Multiplayer-Compatibility](https://github.com/MrRaysor/Multiplayer-Compatibility/tree/raysor-1.7)
(branche `raysor-1.7`), [SmashPhil/Vehicle-Framework](https://github.com/SmashPhil/Vehicle-Framework) (branche
`develop`). Les autres mods sont ceux de Raysor.
