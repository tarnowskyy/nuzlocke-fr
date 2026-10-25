# Nuzlocke FR

A [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp) mod that turns
Pokémon FireRed into an enforced, randomized, harder Nuzlocke.

The mod only activates on a save that answers YES to its setup question
right after NEW GAME. Existing saves are never touched.

## Rules
- **Randomized, seeded:** starters, wild Pokémon (every area and method)
  and all trainers, Gen 1 species only. One seed per run, so reloading
  keeps the same world. Gifts and static encounters stay vanilla.
- **One catch per area**, with dupes clause (evolution families) and shiny
  clause. Gifts and statics don't use up an area.
- **Permadeath:** a fainted Pokémon is dead and can't be revived.
  A full party wipe ends the run.
- **No shop purchases** (the Safari Zone fee still works).
- **Level caps** by badge: 15 / 22 / 26 / 31 / 45 / 45 / 49 / 52 / 61,
  64 after Lance. EXP over the cap is banked and paid out later. Rare Candy
  is refused at the cap.
- **Tougher trainers:** +10% levels for regular trainers, gym leaders at the
  cap, Elite Four and Champion slightly above it; smarter AI; better
  movesets; boss aces hold berries or type items.
- **Safety:** no HM softlocks (a party member can use an HM it could learn,
  or a stand-in), no deathtrap moves early (OHKO, early Self-Destruct,
  Sonic Boom, Dragon Rage...), trade evolutions at Lv 37.

START > NUZLOCKE opens the run menu: seed, level cap and banked EXP, your
party, every area used and what was caught there, and the deaths.

## Install
1. Download `nuzlocke_fr-<version>.zip` from the
   [Releases](https://github.com/tarnowskyy/nuzlocke-fr/releases) page.
2. In the launcher: MODS > Import mod .zip, enable it for Fire Red.
3. Start a NEW GAME and answer YES to the setup question.

## Requirements
- Gen1Recomp 0.3.96 exactly (the mod switches itself off on other engine
  versions so a run can't break mid-way).
- Your own legally obtained FireRed ROM. This repository contains no game
  data; species data is read from your game at runtime.

## License
MIT
