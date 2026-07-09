# Scripts Lua (style DraStic)

melonDS charge automatiquement un script Lua au lancement d'un jeu si un fichier
correspondant existe dans le dossier `scripts` de l'application :

```
/Android/data/me.magnum.melondualds/files/scripts/<nom du fichier ROM>.lua
```

(build dev : `me.magnum.melondualds.dev`, nightly : `me.magnum.melondualds.nightly`)

Le nom du script doit correspondre au nom du fichier ROM sans son extension
(ex. `Metroid Prime Hunters.nds` → `Metroid Prime Hunters.lua`). Le nom d'affichage
du jeu est aussi accepté en fallback.

## API disponible

Le script définit une fonction globale `on_frame_update()` appelée à chaque frame
émulée, avant l'exécution de la frame. Le script lit l'input brut de l'utilisateur
et peut le remplacer.

### Table `drastic`

| Fonction | Description |
| --- | --- |
| `drastic.get_buttons()` | Masque de boutons effectif (entier) |
| `drastic.set_buttons(mask)` | Remplace le masque effectif |
| `drastic.set_touch(x, y)` | Coordonnées tactiles (0-255, 0-191) |
| `drastic.get_touch()` | Retourne `x, y` courants |
| `drastic.get_pixel(screen, x, y)` | Couleur d'un pixel : `r, g, b` (0-255) ou `nil` |
| `drastic.set_swap_screen(bool)` | Force l'échange écran haut/bas |
| `drastic.get_swap_screen()` | État actuel de l'échange (bool) |
| `drastic.log(screen, text, x, y, color)` | Affiche une ligne de texte de debug à l'écran |

Constantes dans `drastic.C` : `BUTTON_A`, `BUTTON_B`, `BUTTON_SELECT`, `BUTTON_START`,
`BUTTON_RIGHT`, `BUTTON_LEFT`, `BUTTON_UP`, `BUTTON_DOWN`, `BUTTON_R`, `BUTTON_L`,
`BUTTON_X`, `BUTTON_Y`, `BUTTON_TOUCH`, `BUTTON_LID` (alias `BUTTON_HINGE`),
`SCREEN_TOP` (0), `SCREEN_BOTTOM` (1).

Le toucher n'est appliqué que si `BUTTON_TOUCH` est présent dans le masque passé à
`set_buttons` ; sinon l'écran est relâché.

#### `get_pixel` : coût et fraîcheur selon le renderer

- **Renderer Software** : lecture directe du framebuffer 2D CPU de melonDS — gratuit,
  sans readback GPU, toujours à jour (frame courante).
- **Renderer Vulkan** (renderer par défaut de ce fork, requis pour LSFG) : l'image
  composée finale vit dans une texture GPU qui n'est normalement jamais relue vers le
  CPU (LSFG présente directement au swapchain). En faire un readback à chaque frame
  émulée doublerait le travail de composition GPU et irait à l'encontre de la frame
  generation. `get_pixel` rafraîchit donc son buffer sur un intervalle throttlé —
  **toutes les 6 frames émulées** (~10 Hz à 60 fps, `kLuaVulkanPixelRefreshIntervalFrames`
  dans `MelonInstance.h`) — et retourne entre-temps la dernière couleur connue. Ordre de
  grandeur similaire au détecteur "battle screen" déjà présent côté Kotlin dans
  `EmulatorActivity.kt` (~5 Hz), suffisant pour de la logique de jeu (détection d'état
  d'écran, déclenchement de HUD) mais pas pour un tracking pixel-perfect frame par frame.
- **OpenGL / Compute** : pas encore câblé, `get_pixel` retourne `nil`.

Toujours vérifier le retour, `nil` signalant un renderer non pris en charge :

```lua
local r, g, b = drastic.get_pixel(drastic.C.SCREEN_TOP, 0, 0)
if r then
    -- couleur valide (fraîche en Software, jusqu'à ~6 frames de retard en Vulkan)
end
```

#### `log` : afficher du texte de debug à l'écran

`drastic.log(screen, text, x, y, color)` dessine une ligne de texte par-dessus l'écran
émulé, indépendamment du renderer actif (Software/OpenGL/Vulkan) — c'est une vue
Android superposée, pas un pixel écrit dans la frame NDS.

- `screen` : `drastic.C.SCREEN_TOP` ou `SCREEN_BOTTOM`
- `text` : chaîne à afficher (tronquée à 96 caractères)
- `x, y` : coordonnées en pixels DS (0-255, 0-191) sur l'écran choisi
- `color` (optionnel) : entier packé `0xRRGGBB`, blanc par défaut

**Une ligne ne persiste pas d'elle-même** : comme `on_frame_update()` tourne déjà à
chaque frame, il suffit de rappeler `drastic.log(...)` chaque frame pour garder le texte
affiché — exactement comme le reste de l'API (pas de `clear()` à gérer, la ligne
disparaît simplement si le script arrête de l'émettre).

Max 24 lignes par frame (les appels en trop sont ignorés).

```lua
function on_frame_update()
    drastic.log(drastic.C.SCREEN_TOP, "hp: 42", 4, 4, 0x00FF00)
end
```

### Table `android`

| Fonction | Description |
| --- | --- |
| `android.get_axis_lx()` / `get_axis_ly()` | Stick gauche brut (-1..1) |
| `android.get_axis_rx()` / `get_axis_ry()` | Stick droit brut (-1..1) |

Les valeurs sont brutes : deadzone et courbes de réponse sont à gérer dans le script,
comme sous DraStic.

### Divers

- `print(...)` est redirigé vers logcat (tag `MelonLua`).
- Lua 5.4 : les opérateurs bit à bit `&`, `|`, `~`, `<<`, `>>` sont disponibles.
- En cas d'erreur d'exécution, le script est désactivé (log `MelonLua` dans logcat)
  et l'input utilisateur repasse en direct — pas de touche bloquée.
