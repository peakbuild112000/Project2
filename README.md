# Chroma Chameleon

Un jeu de cache-cache multijoueur original, inspiré des mécaniques de *MECCHA
CHAMELEON*, réalisé avec **Godot 4.7.2**. Tout le code, les textures et les sons
sont générés par le projet : aucun asset du jeu Steam n'est reproduit.

- Dépôt : <https://github.com/peakbuild112000/Project2>
- Moteur : Godot 4.7.2 stable (renderer GL Compatibility)

## Principe

À chaque manche, un joueur est désigné **Seeker** (chercheur), les autres sont
**Hiders** (caméléons). Les hiders commencent avec une combinaison blanche et
doivent la peindre avec la couleur d'un élément du décor pour se camoufler.
Rester immobile près d'un objet de la même couleur augmente le camouflage. Le
seeker utilise une lampe torche et doit taguer tous les hiders avant la fin du
chronomètre. 3 manches, 3 cartes générées de façon déterministe.

## Commandes

| Touche | Action |
| --- | --- |
| `ZQSD` / `WASD` | Se déplacer |
| `Shift` | Courir |
| `Souris` | Regarder (clic dans la fenêtre pour capturer le curseur) |
| `Flèches` | Regarder au clavier |
| `1`-`5` | Peindre : cyan / rose / or / vert / blanc |
| `Tab` | Ouvrir la palette (clic sur une couleur, puis `Tab` pour fermer) |
| `F` | Lampe torche (seeker) |
| `E` ou clic droit | Taguer (seeker) |
| `Échap` | Pause / reprise |
| `L` | Quitter la partie (depuis la pause ou la palette) |
| `Entrée` | Lancer la partie en mode hôte |

## Lancer le projet

1. Ouvrir Godot 4.7.2 et importer `project.godot`.
2. `F5` pour lancer `scenes/Main.tscn`.
3. Choisir **PRACTICE (BOTS)** pour jouer immédiatement avec 3 bots.

## Multijoueur

Le mode **HOST SESSION** ouvre un serveur WebSocket autoritatif sur le port
`9080` (TCP). Les clients utilisent **JOIN SESSION** avec
`ws://<IP_DE_L_HOTE>:9080`. Pour le Web, il faut une URL `wss://` (par exemple
via un tunnel Cloudflare) car GitHub Pages est en HTTPS. L'hôte appuie sur
`Entrée` pour démarrer ; les places vides sont comblées par des bots.

L'addon **Godot Super-Wakatime** (v2.1.0) est installé dans `addons/` et activé
dans `project.godot`. Il ignore les exécutions headless et la CI.

## Structure

```
project.godot          configuration, autoloads Core et Net, plugin Wakatime
scenes/Main.tscn       scène unique
scripts/Core.gd        palette, cartes, textures et sons procéduraux
scripts/Net.gd         transport WebSocket (serveur/client)
scripts/Match.gd       règles de manches, rôles et scores
scripts/World.gd       arènes, avatar et camouflage
scripts/HUD.gd         interface assemblée en code
scripts/Game.gd        contrôleur principal, bots, physique, caméra
addons/                plugin Godot Super-Wakatime
```
