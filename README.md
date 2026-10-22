# Key Engraver Kiosk

Fullscreen keyboard for the production team. They type a key number (digits and/or letters), press **ENGRAVE**
(or hit Enter), and the BSL fiber engraves it. LightBurn runs minimized in the
background — operators never see it.

## How it works

1. You make **one template file per key type** in LightBurn, each containing the text
   `%KEYNUM%` positioned exactly where the number goes on the key in your fixture, and each
   with that key type's own power / speed / frequency settings.
2. The operator picks the key type on the kiosk, types the number and presses **ENGRAVE**.
   The kiosk copies that type's template, swaps `%KEYNUM%` for the typed number, and tells
   LightBurn (over its built-in UDP command port 19840) to load the file and start the job.

## Key types and their template files

| Button | Template file (in this folder) |
|---|---|
| METAL (default) | `template.lbrn2` |
| AXK | `template-axk.lbrn2` |
| DELUXE GREEN | `template-deluxe-green.lbrn2` |
| DELUXE BLUE | `template-deluxe-blue.lbrn2` |
| DELUXE RED | `template-deluxe-red.lbrn2` |

Quickest way to make the others: open `template.lbrn2` in LightBurn, change the layer
settings for that key type, **File → Save As** with the name above, into this folder.
Selecting a type whose file isn't there yet shows a red "TEMPLATE MISSING" warning and
ENGRAVE won't fire until it's saved.

To add, rename or reorder key types, edit the `$KeyTypes` list at the top of
`KeyEngraver.ps1` — the buttons are generated from it. The first entry is the default.

## One-time setup (you, not the operators)

1. Open LightBurn with your fiber connected as normal.
2. Put a key in your fixture. Create a **Text** object with the exact content `%KEYNUM%`
   (including the percent signs). Pick your font and size, position it on the key.
   Tip: type `%WWWWWWWW%`-style worst-case width first to check long codes fit, then
   set it back to `%KEYNUM%`.
3. Set that layer to your production settings: **Speed 2000 mm/s, Power 100%, Frequency 30 kHz**
   (plus your usual pass count / hatch fill).
4. **Test it manually once** — run the job from LightBurn to confirm position and marking.
5. Save as `template.lbrn2` **in this folder** (next to `KeyEngraver.ps1`).
6. Double-click `StartKeyEngraver.bat`. It starts LightBurn minimized if needed, then
   opens the fullscreen kiosk. Make a desktop shortcut to the .bat for the team.

## Operator flow

- Tap the **key type** (METAL / AXK / DELUXE GREEN / BLUE / RED) at the top — or press
  F1–F5. The chosen one lights up and stays selected until changed.
- Type the key number (physical keyboard or on-screen buttons — digits and letters, letters always
  come out as capitals) → press **ENGRAVE** / Enter.
- Need another identical key? Just press **ENGRAVE** again — the number and key type stay.
- Typing a new character after an engrave starts a fresh number automatically.
- CLR / ⌫ / Esc clear or edit the entry.
- Footer shows a running count of keys engraved this session.

## Hidden exit

**Ctrl + Shift + X** closes the kiosk (not on the screen, operators won't find it).

## Tuning (top of `KeyEngraver.ps1`)

| Setting | Default | What it does |
|---|---|---|
| `$MaxChars` | 8 | Max characters (digits + letters) an operator can enter |
| `$ZeroPadTo` | 0 | e.g. `4` turns `37` into `0037` (0 = off) |
| `$EngraveSeconds` | 8 | Input lockout while the job runs — set to your real cycle time + a second |
| `$LoadDelayMs` | 800 | Pause between loading the file and starting the job |
| `$LoadTimeoutMs` | 15000 | How long to wait for LightBurn to confirm it loaded the file (slow PCs need more) |
| `$Fullscreen` | `$false` | `$true` for the borderless kiosk; `$false` for a normal window while troubleshooting |
| `$LightBurnHost` | 127.0.0.1 | LightBurn PC (change if kiosk runs on a different machine) |

## Troubleshooting

- **"WAITING FOR LIGHTBURN..."** — LightBurn isn't running or isn't answering on UDP
  19840. Start it; the kiosk reconnects automatically every 3 s.
- **"… TEMPLATE MISSING - SAVE template-xxx.lbrn2"** — that key type's template isn't in
  this folder yet. Save it with exactly that name (see the table above).
- **"template-xxx.lbrn2 HAS NO %KEYNUM%"** — the text object in that template must literally
  read `%KEYNUM%`. Re-edit it and re-save.
- **Console shows red errors** - they are saved to `console.log` (and `engraver.log`) in this folder; send those.
- **Template was saved by a newer LightBurn** - open `template.lbrn2` in the LightBurn on the engraver PC and re-save it there, so the version matches.
- **Job doesn't start after loading** — increase `$LoadDelayMs` to 2500.
- **Laser fires before the operator is clear** — this kiosk starts the job immediately.
  Keep your interlocks/enclosure in place; if you want a "press twice to confirm" step,
  it's a small change — ask.
