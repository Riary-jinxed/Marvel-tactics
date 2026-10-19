# Marvel Tactics

Jeu mobile (Android) de stratégie au tour par tour en pixel art dans l'univers Marvel, avec un deck de cartes par héros, inspiré de Marvel Midnight Suns. Projet perso, développé avec Godot 4.

## Prototype actuel

Un combat jouable de bout en bout, avec des formes simples à la place du pixel art :

- grille de 6 × 7 cases en portrait (360 × 640) ;
- 3 héros : Magik (téléportation, Darkchylde), Luna Snow (givre, glace, soins), Jeff the Land Shark (engloutir, plongée, provocation) ;
- 8 cartes par héros, main commune de 5 cartes, 3 cartes jouées et 2 repioches par tour, Héroïsme pour les cartes Héroïques ;
- ennemis Hydra (sbires, brute, tireur) avec intentions affichées ;
- repousser contre un obstacle, glisser sur la glace, baril explosif.

## Comment jouer

- Toucher une carte, puis une case en surbrillance jaune pour la jouer.
- Toucher un héros, puis une case en surbrillance verte pour le déplacer (2 cases, une fois par tour).
- Toucher un ennemi pour voir ses PV et qui il vise. Au-dessus de chaque ennemi : la lettre du héros visé et les dégâts prévus.
- « Repiocher » remplace la carte sélectionnée, « Fin de tour » fait jouer les ennemis.

## Lancer le projet

1. Installer [Godot 4.4](https://godotengine.org/download) ou plus récent (version standard, pas .NET).
2. Ouvrir Godot, « Importer », choisir `project.godot`.
3. F5 pour lancer.

## Tests

La logique de combat est séparée de l'affichage et testée en headless :

```sh
godot --headless --path . --import
godot --headless --path . -s tests/run_tests.gd
```

## Export Android

1. Installer Android Studio (pour le SDK) et un JDK 17.
2. Dans Godot : Éditeur > Paramètres de l'éditeur > Export > Android, renseigner le chemin du SDK (le keystore de debug est généré automatiquement).
3. Projet > Exporter > Ajouter > Android, puis « Exporter le projet » pour obtenir un APK, ou brancher le téléphone en mode développeur et utiliser le bouton de déploiement en un clic.

## Structure

| Dossier | Contenu |
| --- | --- |
| `data/game_data.json` | Héros, cartes, ennemis et mission. Modifier une carte ne demande pas de code. |
| `scripts/core/` | Logique de combat (règles, effets, IA ennemie), sans affichage. |
| `scripts/view/` | Écran de combat placeholder et gestion du toucher. |
| `tests/` | Tests de la logique de combat. |
