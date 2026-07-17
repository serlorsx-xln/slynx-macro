# Custom patterns

Copy a `.txt` file to:

`%AppData%\SlynxMacro\patterns\<name>.txt`

Then set **Pattern** / `PatternName` in the UI to that `<name>` (without `.txt`).

Format: one `dx,dy` per line. Positive `y` pulls the mouse down.

Generate from a wall-spray video:

```bash
python recoil/tools/recoil_pattern_from_video.py spray.mp4 -o mygun.txt
```

Built-in names (no file needed): `vertical`, `sway`, `heavy`
