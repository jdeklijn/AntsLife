# AntsLife

Een 3D mierenkolonie-game in Godot 4.7, met een stylized look (à la Timberborn):
blokkerige grond, laagjes weggraven en mieren die rondlopen en opdrachten uitvoeren.

## Nu in het spel

- **3D level**: een blok grond van 20 × 22 × 20 cellen, opgebouwd uit gras- en grondblokken.
- **Graniet eromheen**: het level ligt in een massa graniet. De blokken die aan de grond grenzen zijn echte 3D-blokken (niet weg te graven). Waar de camera de grond opensnijdt vult een platte steendoorsnede de rest van het beeld met dezelfde graniet, zodat de ondergrond als 2D-speelveld leest en niet als een grot met horizon. De kant waar de camera staat blijft open, zodat je het zand altijd ziet.
- **Graven in lagen**: met de ogen aan de zijkant schakel je lagen uit, per zijde en per hoek.
- **Graven met de muis**: klik met de Dig-tool (G) een blok weg; houd de linkermuisknop ingedrukt om een rechte rij of kolom in één keer weg te graven. Elke gedolven cel levert zand op.
- **Mijngang-look**: wanden, vloer en plafond van weggegraven cellen krijgen hun eigen wand-, vloer- en plafondtextuur, zodat tunnels en schachten als mijngangen lezen.
- **Camera**: draaien naar de vier zijden, bovenaanzicht en onderaanzicht, pannen en zoomen.
- **Mier**: het echte geanimeerde 3D-model, met idle/walk-clips, selectie en een hitbox.
- **Opdrachten**: een radiaal menu met Dig, Carry en Defend, afhankelijk van het mier-type.
- **Dag/nacht-kaart**: in de zijbalk loopt de mier over een granieten pad, met pauze en 1x/2x/3x.
- **UI**: mier-info-paneel, grondstoffenlijst en een main menu met startwereld.

## Zo start je het

1. Open `project.godot` in Godot 4.7 (Forward+).
2. Druk op **F5**; de main scene is `scenes/main/main_scene.tscn`.
3. Het level zelf is `scenes/level/playfield.tscn`.

## Projectstructuur

```
assets/
  characters/ants/player_ant/   het mierenmodel (glTF)
  themes/                       het UI-thema
  ui/{fonts,icons,cursors,levels}
  world/textures/               gras-, grond- en graniettexturen
scenes/
  main/                         main menu, startwereld en UI
  level/                        het speelveld
  ant/                          de mier-scene
scripts/
  ant/                          mier, acties, radiaal menu, infopaneel
  ant/actions/                  de actie-resources
  core/                         events, ant-register, level-data
  level/                        level-opbouw, camera, 3D-weergave
  main/                         startwereld en level-wissel
  ui/                           zijbalk, laag-HUD, quit-knop
  world/                        grasveld en achtergrond
```

## Credits

- Mierenmodel: `assets/characters/ants/player_ant/ant_v4.glb` (gerigged, 3.960 driehoeken)
- Font: Nunito (SIL Open Font License, zie `assets/ui/fonts/Nunito/OFL.txt`)
