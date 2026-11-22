# Chroma Chameleon

Un jeu de cache-cache multijoueur original, inspiré des mécaniques de *MECCHA
CHAMELEON*, réalisé avec **Godot 4.7.2**. Tout le code, les textures et les sons
sont générés par le projet : aucun asset du jeu Steam n'est reproduit.

- Dépôt : <https://github.com/peakbuild112000/Project2>
- Moteur : Godot 4.7.2 stable (renderer GL Compatibility)

## Principe

À chaque manche, un joueur est désigné **Seeker** (chercheur), les autres sont
**Hiders** (caméléons). Les hiders commencent avec une combinaison blanche et
doivent la peindre pour se fondre dans le décor. Rester immobile près d'un objet
de couleur proche augmente le camouflage.

Le seeker utilise une lampe torche pour repérer les hiders. **Le simple fait de
voir un hider rapporte +1 point au seeker**, mais ne l'élimine pas : pour
l'éliminer, il doit **tirer** dessus (+3 points). Un hider qui survit à la manche
gagne +1 point. 3 manches, 3 cartes générées de façon déterministe.

## Peindre son personnage

- Le **hider est toujours en troisième personne** ; le **seeker reste en
  première personne**.
- Appuie sur **`P`** (hider uniquement) : le curseur se débloque et le panneau
  **PAINT** apparaît.
- Choisis une couleur **quelconque** avec le sélecteur HSV/RGB (couleurs
  infinies), ou les raccourcis `1`-`5` pour les couleurs rapides.
- Choisis la taille de brosse : **Petit / Moyen / Grand**.
- **Clic gauche + glisser sur ton avatar** pour peindre. Le trait est envoyé aux
  autres joueurs en réseau.
- **Clic droit + glisser** : fait tourner la caméra orbite, **uniquement** pour le
  hider en mode Paint.
- La **Pipette** prélève la couleur **telle qu'elle est rendue à l'écran**, donc
  avec l'éclairage et les ombres : un objet rouge dans un coin sombre donne un
  rouge sombre, pas un rouge vif. Elle fonctionne sur ton costume comme sur le
  décor (repli sur la couleur du matériau si la capture n'est pas disponible).
- `P` ou `Échap` pour quitter le mode Paint.

## Commandes

| Touche | Action |
| --- | --- |
| `ZQSD` / `WASD` | Se déplacer |
| `Shift` | Courir |
| `Souris` | Regarder (curseur capturé hors mode Paint) |
| `Clic droit + souris` | Tourner la caméra (hider, mode Paint uniquement) |
| `Flèches` | Regarder au clavier |
| `P` | Activer / quitter le mode Paint (hider) |
| `1`-`5` | Couleurs rapides (peinture intégrale) |
| `F` | Lampe torche (seeker) |
| `Clic gauche` / `E` | Tirer (seeker) — élimine un hider touché |
| `Échap` | Pause / reprise, ou quitter le mode Paint |
| `L` | Quitter la partie (depuis la pause ou le mode Paint) |
| `Entrée` | Lancer la partie en mode hôte |

## Lancer le projet

1. Ouvrir Godot 4.7.2 et importer `project.godot`.
2. `F5` pour lancer `scenes/Main.tscn`.
3. Choisir **PRACTICE (BOTS)** pour jouer immédiatement avec 3 bots.

La résolution de référence du projet est **1354 × 648** (`project.godot`).
L'interface est dessinée sur une surface 1280 × 720 puis mise à l'échelle et
recentrée automatiquement : elle reste correcte à cette résolution, ainsi que
pour toute autre résolution ou taille de fenêtre.

## Multijoueur

Le mode **HOST SESSION** ouvre un serveur WebSocket autoritatif sur le port
`9080` (TCP). Les clients utilisent **JOIN SESSION** avec
`ws://<IP_DE_L_HOTE>:9080`. Pour le Web, il faut une URL `wss://` (par exemple
via un tunnel Cloudflare) car GitHub Pages est en HTTPS. L'hôte appuie sur
`Entrée` pour démarrer ; les places vides sont comblées par des bots.

Les couleurs peintes et les tirs sont synchronisés : le serveur est autoritatif,
les clients n'envoient que leurs intentions.

L'addon **Godot Super-Wakatime** (v2.1.0) est installé dans `addons/` et activé
dans `project.godot`. Il ignore les exécutions headless et la CI.

## Structure

```
project.godot          configuration, autoloads Core et Net, plugin Wakatime
scenes/Main.tscn       scène unique
scripts/Core.gd        palette, cartes, textures et sons procéduraux
scripts/Net.gd         transport WebSocket (serveur/client)
scripts/Match.gd       règles de manches, rôles, score (repéré / tir / survie)
scripts/World.gd       arènes, avatar à texture peignable, camouflage
scripts/HUD.gd         interface, sélecteur de couleurs, brosses, pipette
scripts/Game.gd        contrôleur principal, paint, tir, bots, physique, caméra
addons/                plugin Godot Super-Wakatime
```
