# Godot Grondblokken TileSet

## Hoe te gebruiken

1. Kopieer de HELE map `godot_grondblokken_tileset` naar je Godot-project
   (bijvoorbeeld naar `res://tiles/` of gewoon in de root van je project).

2. Open Godot en laat het project de bestanden importeren.

3. Belangrijk: open het bestand `grondblokken_tileset.tres` 
   en controleer of het pad naar de texture klopt.
   - Staat de map in de root van je project? Dan is het pad al goed (`res://godot_tilesheet_...`).
   - Staat de map in een submap (bijv. `res://tiles/godot_grondblokken_tileset/`)?
     → Open dan `grondblokken_tileset.tres` in een teksteditor en pas het pad aan naar:
       `res://tiles/godot_grondblokken_tileset/godot_tilesheet_grondblokken_64x64_atlas.png`

4. Maak een TileMap (of TileMapLayer) node.
5. Sleep `grondblokken_tileset.tres` in de "Tile Set" property van de TileMap.

Klaar! Alle 59 tiles zijn al aangemaakt.

## Indeling atlas (13 kolommen)

Rij 0 : Gras (13 varianten)
Rij 1 : Aarde (13 varianten)
Rij 2 : Rots (13 varianten)
Rij 3 : Erts / mineralen (13 varianten)
Rij 4 : Zijvlakken (7 stuks)
         0 = Gras-zijde
         1 = Aarde-zijde
         2 = Rots-zijde
         3 = Erts-zijde
         4 = Water-zijde
         5 = Grot-zijde
         6 = Tunnel-zijde
