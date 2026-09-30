# VSAV_Training - The Warlord's Secret

See what the Warlord sees, and practice what the Warlord practices, in VSAV training mode for Fightcade 2.

English | [日本語](README.ja.md)

**A training mode for Fightcade 2 / FBNeo that reproduces opponent actions in internal frames (Ticks), helping you test offense and practise defense.** Detailed input and interaction readouts let you examine why an attempt succeeded or failed and adjust your timing.

This fork extends [VSAV_Training's fc2 branch](https://github.com/NBeing/VSAV_Training/tree/fc2). This README covers **v11.7.18**.

**[Download](https://github.com/vampiresavior001/VSAV_Training/archive/refs/heads/fc2-v11.zip)** · [Installation](#windows-installation) · [First AG drill](#first-ag-drill) · [English manual](docs/PLAYER_MANUAL.en.md)

## Reproduce, test and improve in Ticks

A Tick is an internal game frame.

| Game speed | Displayed frames and internal frames |
|---|---|
| Normal | One displayed frame = one Tick |
| Turbo 3 | Three displayed frames = four Ticks |

This fork controls inputs on that internal clock, improving response timing that was limited in the original. On wake-up, after blocking and after landing, you can specify **light-normal or throw challenges, jumps and dashes**, as well as special-move reversals.

**Reproduce an opponent's action → try your response → examine the readouts → adjust your timing and repeat.** Precise action control and detailed feedback work together to improve both offense and defense. See [Action Steps](docs/PLAYER_MANUAL.en.md#06-steps) for the conditions governing earliest inputs.

## What you can test and practise

| Goal | How to use the tool |
|---|---|
| **Test when your offense works** | Make the dummy respond with a light normal, throw, jump or dash, then test whether your pressure or wake-up setup beats it |
| **Reproduce strings and combos precisely** | Define Tick-based actions with Action Steps; save, randomize and share them with Action Patterns. Definitions can even complete infinite combos for Bulleta (B.B. Hood) or Bishamon |
| **Measure setup timing** | Use Action Timeline in Tick Data to examine time spent in wake-up setups, or the starting distance for a walk-up throw performed within 15 displayed frames (20 Ticks at Turbo 3) |
| **Practise AG (Advancing Guard / Push Block)** | Delay input while fitting six valid presses inside the window. Inspect timing, simultaneous presses, inputs after the window closes, averages and success rate |
| **Practise GC (Guard Cancel)** | Inspect accepted directions, buttons and their intervals to identify command expiry or late inputs |
| **Examine situations after air guarding** | Find interruptible gaps in air chains, evaluate actual interrupt timing, see when you air-blocked and check landing advantage |

**Tick Data** avoids the turbo-frame variation of the original display-frame measurements. Its counting conventions for startup, active time, recovery and frame advantage are aligned with those used by strategy sites. See [manual Section 10](docs/PLAYER_MANUAL.en.md#10-data) for measurement conditions and how to read Action Timeline.

### See what happened to your inputs

![PB Counter and PB Stats showing AG input count, timing, simultaneous presses and practice results](docs/images/pb_counter_stats.png)

Here, six presses on Ticks 5–13 of the window activated AG. Two Ticks contained simultaneous button presses, and no inputs fell after the window closed. **Check not only whether AG activated, but what to improve next.** The English UI calls AG Push Block / PB. See [AG practice](docs/PLAYER_MANUAL.en.md#08-pb) for the full readout guide.

### Choose easy recording or precise action control

Added in this fork, **Recording Wizard** makes it easy to capture an input sequence from start to finish. Recording starts on your first input and ends automatically after the action and your inputs finish. Review playback before saving, then use looped or random playback for repeated practice.

**Recording and playback operate in displayed frames. Use Action Steps for drills that require precise Tick-level input timing.**

## Before installing: turn Run-ahead OFF

**Leaving Run-ahead ON causes the training script to behave incorrectly.**

If you also play matches through Fightcade, **copy the entire `emulator/fbneo` folder to create a separate training installation**. Turn Run-ahead OFF in the copy and keep separate launch paths and settings, so you do not have to remember to switch them for every session.

| Use | Launch method |
|---|---|
| Matches | Launch normally through Fightcade |
| Training | Launch the copied `run_vsav_training.bat`; keep Run-ahead OFF |

## Windows installation

The target game is **Vampire Savior - the lord of vampire (970519 Japan / `vsavj`)**.

**ROMs are not included. Supply your own files and first make sure the game runs in FBNeo.**

1. Close Fightcade and FBNeo.
2. Copy Fightcade's entire `emulator/fbneo` folder to another location, for example `C:/VSAV_Training/fbneo`.
3. Download and extract this project. Put `run_vsav_training.bat` and the entire `scripts` folder in the **copied fbneo folder**, with the batch file next to `fcadefbneo.exe`.
4. Launch the copied batch file and **turn Run-ahead OFF**. Copying the folder also copies settings; it does not turn Run-ahead off by itself.
5. Fully close FBNeo, relaunch through the same batch file and confirm Run-ahead remains OFF.
6. Use `Input > Map Game Inputs` to configure game controls and the functions below. Configure P2 game inputs too.

Use a short path without spaces or Japanese characters. Before updating an existing installation, make a [backup](#updates-and-backups).

### Basic controls

| FBNeo input entry | Function |
|---|---|
| `Lua Hotkey 1` | Open/close the training menu |
| `Lua Hotkey 2` | Restore positions using a direction modifier |
| `Lua Hotkey 3` | Toggle recording playback looping |
| `Lua Hotkey 4` | Return to character select |
| `Volume Up` | Start/stop standard recording |
| `Volume Down` | Start/stop playback |
| `P1 Coin` | Switch the controlled side in a match; choose a stage at character select |

`Volume Up / Down` are FBNeo input entries. You can assign them to arcade-stick or controller buttons.

<a id="first-ag-drill"></a>

## First drill: AG against a recorded attack

1. **Record an attack.** Choose yourself as P1 and the attacking character as P2, and place them within range of a ground attack. Open the menu with `Lua Hotkey 1`, then choose an unused slot in `Recording > Recording Wizard`. Release all inputs; when `START MOVING TO RECORD!` appears, perform a single attack as P2. Release the controls and wait about two seconds after the action finishes for recording to end. Review playback, then choose save.
2. **Repeat it.** Under `Recording`, set `Use Random Recording Slot = no`, choose the saved `Recording Slot`, and set `Looped Playback = yes` and `Reset Distance Each Loop = yes`. Start `Play Recording`.
3. **Show the feedback and practise.** Set `Trainer > Show PB Counter = yes` and `Show PB Stats = yes`, then close the menu. As P1, block the attack and perform AG.
4. **Review each attempt.** Green means AG activated. Check your first pressed Tick and press count. First make six valid presses inside the window consistently, then delay your starting input. Inspect `MultiPush` for simultaneous presses and `LateMash` for inputs after the window closes.

**Keep pressing to complete six even if AG activates earlier. Counting presses after activation is intentional and supports this drill.** Stop playback with `Volume Down`. See [recording instructions](docs/PLAYER_MANUAL.en.md#05-recording) or [AG practice](docs/PLAYER_MANUAL.en.md#08-pb) for more detail.

Next, try [GC practice](docs/PLAYER_MANUAL.en.md#09-gc), [air-guard analysis](docs/PLAYER_MANUAL.en.md#10-data), or [precise action control with Action Steps](docs/PLAYER_MANUAL.en.md#06-steps).

## Manual

The **[English player manual](docs/PLAYER_MANUAL.en.md)** covers controls, settings and how to interpret the readouts.

- [Dummy defense, recovery and counter actions](docs/PLAYER_MANUAL.en.md#04-dummy)
- [Recording and looping](docs/PLAYER_MANUAL.en.md#05-recording)
- [Action Steps](docs/PLAYER_MANUAL.en.md#06-steps) / [Action Patterns](docs/PLAYER_MANUAL.en.md#07-patterns)
- [AG practice](docs/PLAYER_MANUAL.en.md#08-pb) / [GC practice](docs/PLAYER_MANUAL.en.md#09-gc)
- [Tick Data and air-guard analysis](docs/PLAYER_MANUAL.en.md#10-data)
- [Practice recipes](docs/PLAYER_MANUAL.en.md#11-drills)
- [Troubleshooting](docs/PLAYER_MANUAL.en.md#14-troubleshooting)

### Scope

These installation instructions target Windows. Linux launch scripts are included, but support for every feature of this fork on Linux/macOS was not verified when this README was prepared. Action Patterns naming and file dialogs are implemented for Windows.

Some timing readouts use internal frames and others use displayed frames. Existing dash trainers and other displays have not all been converted to Ticks. See the [manual's unit guide](docs/PLAYER_MANUAL.en.md#10-data).

## Updates and backups

Save your edits before closing FBNeo, then back up:

| Content | Location |
|---|---|
| Settings, Action Steps and Action Patterns | `scripts/training_settings.json` |
| Recordings | Entire `scripts/macro` folder |

Update the separate training installation. A distribution may contain recordings, so avoid overwriting your own. Fully restart FBNeo afterward and confirm Run-ahead is OFF.

## Release history and reports

- [Release notes](RELEASE_NOTES.md)
- [日本語リリースノート](RELEASE_NOTES.ja.md)
- [This fork's Issues](https://github.com/vampiresavior001/VSAV_Training/issues)

When reporting a problem, include the version, P1/P2 characters, side arrangement, setting screenshots and reproduction steps. Confirm that Run-ahead is OFF in the training FBNeo.

## Original project and credits

This project is based on [VSAV_Training's fc2 branch](https://github.com/NBeing/VSAV_Training/tree/fc2). The original already includes recording, reversal settings, an AG counter and a GC-window display. This fork builds on them with more precise action reproduction and more detailed feedback; see the [feature comparison](docs/PLAYER_MANUAL.en.md). Thanks to the creators and contributors of the original training mode and its scripts, and to the VSAV community.

<details>
<summary>Credits from the original README</summary>

Shoutouts to: Dammit and Jed for their wizardry, Grouflon (Stole their 3s training mode menu, and settings workflow!) and the VSAV Community.

BIGGEST SHOUTOUT to KyleW! This definitely would not have happened or continued without you.

`N-Bee`

</details>
