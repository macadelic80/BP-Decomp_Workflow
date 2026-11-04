# Course online LAN : de `OnlineLoading` à `IN_PROGRESS` — 2026-11-04/05

**Conclusion :** une course LAN à deux instances atteint `E_GMS_IN_PROGRESS` sur l'hôte et l'invité, sans GUI 281 posté par le harness. Le burning home run (mode 13) aussi. Il reste deux défauts : un assert de debug pendant le chargement de la course (mode 10), dont la séquence paraît identique à la console, et une lecture de pointeur nul en road rage (mode 11), qui demande une décision de divergence PC.

- **Branches :** b5 `claude/night-2-online-modes-bf4a2c` (commits `f2259c23e` à `f1c422b21`), parent `claude/night-2-online-modes-bf4a2c` (`23a5e271` et ce rapport). Rien n'est fusionné dans `work/integration-20261104`, rien n'est poussé.
- **Exe :** `build\game\Burnout_PC.exe` du worktree, construit depuis `f1c422b21`.

## Chaîne de correctifs

| Commit b5 | Défaut | Preuve |
|---|---|---|
| `f2259c23e` (session 2) | `findInst` faisait correspondre par nom un nœud vivant : le second `ChevronsColour` d'`ON_LOAD` prenait la place du premier, et `OnlineLoading` attendait pour toujours en `LOADING_COMPONENTS`. | `0x82AD9A2C` teste `mbIsDefined` |
| `726778def` | Crash `GetDebugFullName` (`strnlen` sur `0x0000000200000000`) au début de l'intro online. Le bloc `+0x194` d'`ArbStateOnlineRaceIntro` était un POD `{0, 8, 0, 2}` décalé d'un mot, relu comme `BehaviourInterpolate::Parameters` ; sur x64 le nom de debug tombait sur les deux derniers mots. L'appel `SetInterpolationMode` venait d'une mauvaise lecture de ce même chargement du nom. | `Construct` `0x8225AE98` : `+0x194 = 8`, `+0x198 = 0`, `+0x19C = 0`, `+0x1A0 = 2`. Trois sites `SetParameters` (`0x822737F4`, `0x82273970`, `0x82273B10`) sans écriture à `+0x04`. |
| `245a049c2` | Assert `luTeam < 2` en road rage dès qu'une voiture est bleue. | DWARF `:500` : `Time maTotalTimeInTeam[3]`. `UpdateTeamStats` `0x8231F308` indexe sans assert. L'ancien `mTimeAsRunner` à `+0x84` est l'élément `[2]`. |
| `f44b700ea`, `f1c422b21` | Témoins `[net] opponents`, `[net] above-car`, `[net] scoring-bind`. Bornés, LAN ou harness seulement. | — |

Le case `net_lan_start_mode` (parent `23a5e271`) ne poste plus GUI 281 et n'envoie le lancement qu'une fois.

## Tests, exe du worktree

Tous valides : `TITLESTART requested=True ready-observed=True`, aucun VOID.

| Case | Résultat | Run |
|---|---|---|
| `net_lan_start_mode` mode 10 | Rouge, seul échec : 2150 asserts `Invalid rival position`. `IN_PROGRESS` atteint sur les deux, aucune exception. | `20261104_235407` |
| `net_lan_start_mode` mode 11, `BP_START_LAUNCH_GUI=54` | Rouge : `ACCESS_VIOLATION` en lisant `0xD9` dans `HUDMessageLogic::PostWorldUpdate`, sur les deux | `20261104_232400` |
| `net_lan_start_mode` mode 13 | Vert, `IN_PROGRESS` sur les deux (rouge sur l'exe assemblé) | `20261104_232633` |
| `net_lan_pair` | Vert | `20261104_233053` |
| `net_lan_see` | Vert | `20261104_233334` |
| `baseline_boot_drive` | Vert | `20261104_233623` |

Les runs sont sous `scratch\bugtest\runs\` du worktree. Les modes 10 et 11 étaient verts avec le stand-in GUI 281 parce qu'ils s'arrêtaient au `mode-start` ; sans lui, le jeu va plus loin et rencontre ces deux défauts. Le mode 13 passe désormais ; l'envoi unique de GUI 56 a pu y contribuer, sans preuve isolée.

## Défaut restant 1 : `Invalid rival position`, mode 10

**Où :** `AboveCarRenderer::UpdateCachedInfoForRival`. La rivale (voiture 1) a la position 8, avec 1 adversaire.

**Pourquoi :** 2148 occurrences tombent pendant `ONLINE_LOADING`, sim en pause (action 86), les 2 dernières juste après la reprise (action 87). Le témoin `scoring-bind` montre que les deux voitures ne sont liées au scoring qu'après la reprise. Tant qu'elles ne le sont pas, le scoring publie la position par défaut de `ClearData` (8), alors que `mabValid` est déjà vrai, car il vient de la liste des voitures en course.

**Vérifié contre la console, sans écart :**
- La boucle online de `RenderComponent` `0x82462A38` a les mêmes conditions.
- La voiture réseau de la grille n'est pas `CONNECTING` (`0x823010A0` : seulement si lobby free-burn et non locale).
- La table de slots est copiée avant le saut de pause (`0x823075F8`).
- `GameStateModule::PostWorldUpdate` saute `ModeManager::PostWorldUpdate` en pause (`0x8238F468`).

**Lecture :** probablement un assert de debug qui partait aussi sur console pendant ce chargement. Non prouvé, et non corrigé. Aucune piste de code n'a été trouvée ; masquer l'assert ou l'exclure du case reviendrait à cacher le symptôme.

## Défaut restant 2 : lecture `0xD9`, mode 11 — décision PC à prendre

**Où :** `GenerateOnlineBlueTeamEscapingMessage` `0x82395218`, `GenerateOnlineBlueTeamAreBehindYouMessage` `0x823953B0` et `GenerateOnlineLeaderMilestoneMessage` `0x82395548`. Les trois parcourent les 8 index actifs. Pour chacun, ils appellent `GetCarData` const (`sub_8231DCD0`) et lisent `mbEliminated` (`lbz 0xD9(r3)`) sans tester le retour.

**Pourquoi ça plante :** `sub_8231DCD0` renvoie NULL pour un index sans voiture (2 à 7 à deux joueurs, `li r3, 0` à `0x8231DD68`). Notre code reproduit exactement cette lecture, et Windows la refuse.

**Ce qui reste ouvert :** la console fait la même lecture. Ce code n'a pu tourner en production que si la lecture à l'adresse `0xD9` y était sans effet (page basse lisible, valeur 0), ce qui n'est pas établi ici. Ailleurs, le même code teste ce retour : `GetPlayerTeam`, et le `GetCarData` nommé juste avant à `0x823955F8`.

**Option proposée :** traiter un `CarData` absent comme « non éliminé » sur ces trois sites, marqué `// FLAG PC-platform leaf:`. Ce n'est pas fait : c'est une divergence PC à valider.

## Points du handoff refermés

- `SCREEN apt components: 5 of 5 still unloaded` : sans objet. La ligne est émise une fois au boot pour `SaveLoadComponent`, juste avant que ses 5 composants se chargent (`AddNewAptComponent` puis `ONLOAD`). Rien à voir avec l'online.
- Le correctif `findInst` ne fait régresser aucun des cases relancés.

## Non fait

- Aucune fusion dans `work/integration-20261104`.
- L'interpolateur de l'intro online prend encore des instantanés de caméra (`SetupCameraAFromCamera`/`BFromCamera`) là où la console référence les helpers vivants (`sub_8224EE58`, la surcharge `Setup(f32, from, to, manager)` déjà présente dans l'arbre). Les index de handle utilisés (`muRivalMovieOffset - 1` contre `muCurrentRival` sur la console) sont à revoir avec. Sans effet sur la stabilité, mais visible à l'écran.
