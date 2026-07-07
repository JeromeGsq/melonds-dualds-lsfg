# Plan d'implémentation — LSFG (Lossless Scaling Frame Generation) dans melonDS-android

**Cible :** fork `SapphireRhodonite/melonDS-android`, branche `Fet_OfflineChevos`
**Submodule :** `SapphireRhodonite/melonDS-android-lib` (branche `GBARumble_PR`)
**Layer :** `lsfg-vk-android` (fork FrankBarretta / xXJSONDeruloXx, base lsfg-vk 1.0.0 + patches Android)
**Prérequis matériel :** Adreno 6xx+ recommandé, arm64-v8a uniquement
**Prérequis légal :** le `Lossless.dll` de l'utilisateur (Steam app 993090), jamais redistribué

---

## Vue d'ensemble

Le fork rend et présente déjà en Vulkan dans son propre process :

- **Instance** : `melonDS-android-lib/src/VulkanContext.cpp` → `initializeLocked()`, `vkCreateInstance` ligne ~273. Un pattern d'activation de layer existe déjà (validation layer sous `MELONDS_VULKAN_ENABLE_VALIDATION`, défini dans `melonDS-android-lib/src/CMakeLists.txt:196`).
- **Dispatch** : `VulkanDispatch.cpp` → `dlopen(libvulkan.so)` + `vkGetInstanceProcAddr` → compatible layer chain sur le chemin loader système.
- **Présentation** : `app/src/main/cpp/renderer/VulkanSurfacePresenter.cpp` → swapchain ~L1596, acquire ~L1157, `vkQueuePresentKHR` ~L3708. Une swapchain par surface, multi-surfaces géré par `VulkanFrameRenderCoordinator.kt`.

lsfg-vk hooke `vkCreateInstance` / `vkCreateDevice` / `vkCreateSwapchainKHR` / `vkQueuePresentKHR` — exactement les points que le fork traverse. L'intégration est donc un layer explicite activé dans notre propre `vkCreateInstance`, configuré par variables d'environnement.

---

## Phase 0 — Spike de validation (1–2 jours)

Objectif : dérisquer avant d'écrire la plomberie.

1. Compiler `liblsfg-vk.so` pour Android arm64 (NDK, CMake standalone du repo lsfg-vk-android, **sans** `LSFGVK_ANDROID_WINE`).
2. Build debug de melonDS avec le `.so` dans `jniLibs/arm64-v8a/`, hack temporaire en dur :
   - `setenv("LSFG_LEGACY", "1", 1)` + `LSFG_DLL_PATH` vers une copie manuelle de `Lossless.dll` (adb push)
   - push `"VK_LAYER_LS_frame_generation"` dans `enabledInstanceLayers` de `VulkanContext`
3. Lancer un jeu 3D simple, layout single-screen, renderer Vulkan pipeline simple.

**Critères de sortie :**

- [ ] Le layer est énuméré par `vkEnumerateInstanceLayerProperties` dans le process (vérifier que le loader Android énumère bien les layers du dossier de libs natives en build **release** aussi — si non, fallback : chaînage manuel via l'interface de négociation du layer)
- [ ] Frame gen visible (60 → 120 affiché), pas de crash sur resize/rotation
- [ ] Interaction acceptable avec le pacing du presenter (voir Risques R1)

Si le spike passe → phases suivantes. Si R1 bloque → arbitrage avant d'investir.

---

## Phase 1 — Build system (0,5–1 jour)

**Fichiers : `.gitmodules`, `app/CMakeLists.txt`, `app/build.gradle.kts`**

1. `git submodule add https://github.com/FrankBarretta/lsfg-vk-android app/src/main/cpp/lsfg-vk-android`
2. Dans `app/CMakeLists.txt` :
   - `option(MELONDS_ENABLE_LSFG "..." ON)` — même style que `MELONDS_ENABLE_ADRENOTOOLS`
   - `add_subdirectory(lsfg-vk-android)` (cible layer uniquement, pas l'app UI du repo)
   - restreindre à `ANDROID_ABI STREQUAL "arm64-v8a"`
3. Sortie du `.so` dans le répertoire de libs de l'APK pour énumération par le loader.
4. Vérifier les deps tierces du layer (volk, pe-parse, dxbc, toml11 — vendorées dans `thirdparty/`, pas de fetch réseau au build).
5. Entrée third-party notice (licences lsfg-vk + attribution port Android — exigence des licences upstream).

---

## Phase 2 — Activation du layer côté core (0,5 jour)

**Fichier : `melonDS-android-lib/src/VulkanContext.cpp` (+ `.h`)** → PR séparée sur le submodule.

1. Ajouter à `VulkanContext` un état configurable avant init (même mécanique que `gForceDisableTimelineSemaphores`) : `gEnableLsfgLayer` (atomic, setter public).
2. Dans `initializeLocked()`, dupliquer le bloc validation layer **hors** `#ifdef` :

```cpp
constexpr const char* kLsfgLayerName = "VK_LAYER_LS_frame_generation";

if (gEnableLsfgLayer.load(std::memory_order_relaxed))
{
    u32 layerCount = 0;
    if (vkEnumerateInstanceLayerProperties(&layerCount, nullptr) == VK_SUCCESS && layerCount > 0)
    {
        std::vector<VkLayerProperties> layers(layerCount);
        if (vkEnumerateInstanceLayerProperties(&layerCount, layers.data()) == VK_SUCCESS
            && hasLayer(kLsfgLayerName, layers))
        {
            enabledInstanceLayers.push_back(kLsfgLayerName);
            Platform::Log(Platform::LogLevel::Info, "VulkanContext: LSFG layer enabled");
        }
        else
        {
            Platform::Log(Platform::LogLevel::Warn, "VulkanContext: LSFG requested but layer not found");
        }
    }
}
```

3. Échec silencieux et propre si le layer est absent (LSFG devient no-op, jamais bloquant pour le rendu).

---

## Phase 3 — Configuration JNI (1 jour)

**Fichiers : `app/src/main/cpp/MelonDSAndroidJNI.cpp`, `Configuration.h`, `MelonDSAndroidConfiguration.cpp`**

1. Étendre la config native : `lsfgEnabled`, `lsfgDllPath`, `lsfgMultiplier` (2–4), `lsfgFlowScale`, `lsfgPerformanceMode`.
2. Avant toute init de `VulkanContext` (au setup de l'instance émulateur) :

```cpp
if (config.lsfgEnabled && !config.lsfgDllPath.empty()) {
    setenv("LSFG_LEGACY", "1", 1);
    setenv("LSFG_DLL_PATH", config.lsfgDllPath.c_str(), 1);
    setenv("LSFG_MULTIPLIER", std::to_string(config.lsfgMultiplier).c_str(), 1);
    setenv("LSFG_FLOW_SCALE", ..., 1);
    setenv("LSFG_PERFORMANCE_MODE", config.lsfgPerformanceMode ? "1" : "0", 1);
    melonDS::VulkanContext::SetLsfgLayerEnabled(true);
} else {
    setenv("DISABLE_LSFG", "1", 1);  // disable_environment du manifest
    melonDS::VulkanContext::SetLsfgLayerEnabled(false);
}
```

3. Contrainte : le layer lit sa config au chargement → **changer les réglages = recréer le contexte Vulkan** (pas de hot-reload en V1 ; le fork sait déjà tuer/recréer le contexte entre sessions, on s'aligne sur ça).

---

## Phase 4 — Import du Lossless.dll + UI settings (2–3 jours)

**Côté Kotlin : `me.magnum.melonds.ui.settings.*`, per-ROM config existante**

1. **Import DLL** : préférence "Importer Lossless.dll" → file picker SAF → validation (nom, taille plausible, magic PE `MZ`) → copie dans `filesDir/lsfg/Lossless.dll`. Afficher état (importé / manquant, version si extractible).
2. **Settings vidéo** (global + per-ROM, l'infra per-ROM existe déjà) :
   - Toggle "Frame generation (LSFG)" — visible seulement si renderer = Vulkan
   - Multiplier : 2x / 3x / 4x
   - Flow scale (slider)
   - Performance mode (toggle)
3. **Gates** (griser + message explicatif) :
   - renderer ≠ Vulkan
   - driver AdrenoTools custom actif (voir R2)
   - DLL non importée
   - layout multi-surface actif (V1, voir R3)
4. Strings FR/EN + notice tierce dans l'écran "À propos".

---

## Phase 5 — Tests et stabilisation (3–5 jours)

**Matrice de test :**

| Axe          | Cas                                                                                  |
| ------------ | ------------------------------------------------------------------------------------ |
| Pipeline     | Vulkan simple / Vulkan compute                                                       |
| Layout       | single-screen, dual-screen, écran externe                                            |
| Cycle de vie | rotation, background/foreground, resize, recovery swapchain (`VK_ERROR_OUT_OF_DATE`) |
| Réglages     | 2x/3x/4x, flow scale min/max, perf mode                                              |
| Interop      | RetroArch shaders (.slangp) actifs + LSFG, filtres, per-ROM override                 |
| GPU          | Adreno 7xx, Adreno 6xx, Mali (attendu : non fonctionnel → message propre)            |
| Négatifs     | DLL absente/corrompue, layer absent, driver custom actif                             |

**Mesures :** frametime réel vs affiché (les stats de pacing du presenter existent déjà : `takePacingStatsSnapshotAndReset`), latence input perçue, conso GPU/thermique sur 30 min.

---

## Risques

**R1 — Conflit pacing presenter ↔ layer (risque principal).**
`myvkCreateSwapchainKHR` du layer écrase `presentMode` avec sa propre valeur, ajoute +1/+2 à `minImageCount` et force `TRANSFER_SRC/DST`. Le presenter du fork a sa propre sélection de present mode (`choosePresentMode`, `rankPresentModes`), un budget d'acquire et des timeline semaphores. Symptômes possibles : pacing dégradé, judder, timeouts d'acquire. Mitigation : tester tôt (Phase 0), aligner `LSFG_EXPERIMENTAL_PRESENT_MODE` sur le mode choisi par le presenter, et si besoin patcher le layer (fork déjà nécessaire de toute façon).

**R2 — AdrenoTools bypasse le loader.**
Driver Turnip custom = `dlopen` direct du driver via libadrenotools, sans loader Android → pas de layer chain → LSFG inopérant. V1 : exclusivité mutuelle dans l'UI. V2 possible : chaînage manuel du layer (l'interface `layer_vkGetInstanceProcAddr` du manifest le permet), coût ~2–3 jours de plus.

**R3 — Multi-surface = coût ×N.**
Le layer hooke toutes les swapchains ; en dual-screen deux passes d'Optical Flow par frame. V1 : LSFG limité aux layouts single-surface. V2 : filtrage par swapchain (patch layer).

**R4 — Énumération des layers en release.**
Le loader Android énumère les layers du dossier de libs natives de l'app pour l'app elle-même ; à confirmer en build release sur device (Phase 0). Fallback identifié : chargement manuel via l'interface de négociation.

**R5 — Branche publique en retard.**
`master` est vide, le code vit sur `Fet_OfflineChevos` et les builds RC Patreon peuvent avoir de l'avance sur GitHub. Si l'objectif est un PR upstream vers SapphireRhodonite, synchroniser avec lui d'abord (Patreon/Discussions) pour viser la bonne base.

---

## Estimation

| Phase               | Durée                              |
| ------------------- | ---------------------------------- |
| 0 — Spike           | 1–2 j                              |
| 1 — Build           | 0,5–1 j                            |
| 2 — Layer core      | 0,5 j                              |
| 3 — JNI config      | 1 j                                |
| 4 — UI + DLL import | 2–3 j                              |
| 5 — Tests           | 3–5 j                              |
| **Total**           | **~8–12 jours** (hors R2/R3 en V2) |

## Ordre des PR

1. PR submodule (`melonDS-android-lib`) : Phase 2 seule, minuscule, facile à reviewer.
2. PR app : Phases 1 + 3 + 4, feature-flaguée.
3. PR optionnelle : patches du fork lsfg-vk (pacing, filtrage swapchain).
