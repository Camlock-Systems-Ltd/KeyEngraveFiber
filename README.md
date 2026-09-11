# Key Engraver Kiosk

Fullscreen keypad for the production team. They type a key number, press **ENGRAVE**
(or hit Enter), and the BSL fiber engraves it. LightBurn runs minimized in the
background — operators never see it.

## How it works

1. You make **one template file** in LightBurn (`template.lbrn2`) containing the text
   `%KEYNUM%` positioned exactly where the number goes on the key in your fixture.
2. The kiosk copies the template, swaps `%KEYNUM%` for the typed number, and tells
   LightBurn (over its built-in UDP command port 19840) to load the file and start the job.

## One-time setup (you, not the operators)

1. Open LightBurn with your fiber connected as normal.
2. Put a key in your fixture. Create a **Text** object with the exact content `%KEYNUM%`
   (including the percent signs). Pick your font and size, position it on the key.
   Tip: type `%8888888%`-style worst-case width first to check long numbers fit, then
   set it back to `%KEYNUM%`.
3. Set that layer to your production settings: **Speed 2000 mm/s, Power 100%, Frequency 30 kHz**
   (plus your usual pass count / hatch fill).
4. **Test it manually once** — run the job from LightBurn to confirm position and marking.
5. Save as `template.lbrn2` **in this folder** (next to `KeyEngraver.ps1`).
6. Double-click `StartKeyEngraver.bat`. It starts LightBurn minimized if needed, then
   opens the fullscreen kiosk. Make a desktop shortcut to the .bat for the team.

## Operator flow

- Type the number (physical numpad or on-screen buttons) → press **ENGRAVE** / Enter.
- Need another identical key? Just press **ENGRAVE** again — the number stays.
- Typing a new digit after an engrave starts a fresh number automatically.
- CLR / ⌫ / Esc clear or edit the entry.
- Footer shows a running count of keys engraved this session.

## Hidden exit

**Ctrl + Shift + X** closes the kiosk (not on the screen, operators won't find it).

## Tuning (top of `KeyEngraver.ps1`)

| Setting | Default | What it does |
|---|---|---|
| `$MaxDigits` | 8 | Max digits an operator can enter |
| `$ZeroPadTo` | 0 | e.g. `4` turns `37` into `0037` (0 = off) |
| `$EngraveSeconds` | 8 | Input lockout while the job runs — set to your real cycle time + a second |
| `$LoadDelayMs` | 1500 | Pause between loading the file and starting the job |
| `$LightBurnHost` | 127.0.0.1 | LightBurn PC (change if kiosk runs on a different machine) |

## Troubleshooting

- **"WAITING FOR LIGHTBURN..."** — LightBurn isn't running or isn't answering on UDP
  19840. Start it; the kiosk reconnects automatically every 3 s.
- **"TEMPLATE.LBRN2 MISSING"** — save your template into this folder with that exact name.
- **"TEMPLATE HAS NO %KEYNUM%"** — the text object in the template must literally read
  `%KEYNUM%`. Re-edit it and re-save.
- **Job doesn't start after loading** — increase `$LoadDelayMs` to 2500.
- **Laser fires before the operator is clear** — this kiosk starts the job immediately.
  Keep your interlocks/enclosure in place; if you want a "press twice to confirm" step,
  it's a small change — ask.
