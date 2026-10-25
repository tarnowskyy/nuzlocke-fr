# Nuzlocke FR

A [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp) mod that turns
Pokémon FireRed into an enforced, randomized, harder Nuzlocke.

**Status:** in development (0.3.1: core Nuzlocke rules, level caps and the
seeded Gen-1-only randomizer; difficulty changes not built yet).

The randomizer reads species data (base stats, evolutions, movesets) from
your own game at runtime; the mod ships no game data.

## Planned rules
- Randomized starters, wild encounters and trainers (Gen 1 species only), seeded per run
- One catch per area, dupes clause, shiny clause
- Permadeath; a full party wipe ends the run
- No shop purchases
- Level caps tied to badges, with banked EXP
- Harder trainers, gym leaders, Elite Four and Champion

The mod only activates on a save that was started through its own setup
screen. Existing saves are never touched.

## Requirements
- Gen1Recomp 0.3.96
- Your own legally obtained FireRed ROM. This repository contains no game data.

## License
MIT
