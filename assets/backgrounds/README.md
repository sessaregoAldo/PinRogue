# Table background pictures

Put pictures in this folder and they show up in the game under
Story > Cosmetics > Table backgrounds, each for 60 coins.

- Formats: .png, .jpg / .jpeg, .webp
- Shape: the playfield is tall (560 x 1100). A portrait picture around
  1120 x 2200 looks sharp; other shapes are cropped to fit, never stretched.
- The game darkens the picture a little so the ball and parts stay easy to see.
  Dark, low-contrast art works best.
- The shop name comes from the file name: `old_workshop.png` becomes "Old Workshop".
- After adding files, open the project in Godot once so they are imported, then export.

The price is `IMAGE_PRICE` in scripts/story/cosmetics.gd.
