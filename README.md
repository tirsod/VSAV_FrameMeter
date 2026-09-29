# VSAV_Training - The Warlord's Secret

See what the Warlord sees, and practice what the Warlord practices, in VSAV training mode for Fightcade 2.

English | [日本語](README.ja.md)

**A training mode for Fightcade 2 / FBNeo that uses internal-frame (Tick) control to reproduce opponent actions precisely, letting you practise GC, AG and interrupts after air guarding.**

Detailed input and interaction timelines help you identify what went wrong and track your improvement.

This v11 series builds on [VSAV_Training's original fc2 branch](https://github.com/NBeing/VSAV_Training/tree/fc2), extending dummy control and training readouts. This README describes **v11.7.17**.

**[English player manual](docs/PLAYER_MANUAL.en.md)** · [Release notes](RELEASE_NOTES.md) · [日本語リリースノート](RELEASE_NOTES.ja.md)

## What this fork offers

### Reproduce opponent actions in internal frames

A Tick is an internal game frame in Vampire Savior.

| Game speed | Displayed frames and internal frames |
|---|---|
| Normal | One displayed frame = one Tick |
| Turbo 3 | Three displayed frames = four Ticks |

This fork controls inputs on that internal clock, improving the response timing that was limited in the original. On wake-up, after blocking and after landing, you can make the dummy perform **light-normal or throw challenges, jumps and dashes**, as well as special-move reversals.

Does your pressure beat the earliest challenge? Can the opponent escape your wake-up setup? Who acts first after landing? Specify the dummy's response and test the interaction directly.

### Build strings and complex combos with Action Steps

**Action Steps** lets you define “when” and “what” one action at a time, using internal-frame timing. Combine normals, specials, throws, jumps and dashes to reproduce anything from individual responses to complex sequences. Definitions can even complete infinite combos for Bulleta (B.B. Hood) or Bishamon.

**Action Patterns** lets you save named sequences, randomly select among multiple candidates and share them as files.

For actions after landing, you can choose how the sequence waits:

- **After**: begins the command once the dummy can act. It does not enter the motion in advance, so a dash is delayed until its command is complete.
- **Landing**: can begin the necessary command before touchdown so its final input arrives on the landing Tick.

Landing does not always guarantee the earliest action, for example when touchdown cannot be predicted. See [Action Steps](docs/PLAYER_MANUAL.en.md#06-steps) for settings and conditions.

### Practise defense against the reproduced offense

| Practice | What the readouts show |
|---|---|
| **AG (Advancing Guard / Push Block)** | Whether you delayed input while fitting six valid presses inside the window; timing, simultaneous presses and presses after the window closes; averages and success rate in PB Stats |
| **GC (Guard Cancel)** | Directions and buttons accepted by the game, their intervals, command/window expiry and contact during guard-pose persistence |
| **Interrupts after air guarding** | Gaps in apparently continuous air chains, when you actually pressed and how long your response took to hit |
| **Landing after air guarding** | When you air-blocked a jump or air-dash attack, and which player could act first after landing, in Ticks |

The AG counter **includes presses after AG activates**. This is intentional: you can practise completing six presses every time without stopping when an earlier press happens to activate AG. Distinguish these presses from `LateMash`, which counts inputs after the window closes.

The English UI calls AG **Push Block / PB**.

### Measure move properties in internal frames

The original Frame Data measured displayed frames, which made its results unstable at turbo speeds. This fork’s **Tick Data** measures internal frames to avoid variation caused by turbo frames. Its **counting conventions for startup, active time, recovery and frame advantage are aligned with those used by strategy sites**. This does not guarantee a match with every published value; check move conditions and counting conventions when comparing results.

**Action History in Tick Data** displays a sequence of actions so you can examine the total time a setup takes in Ticks, as well as individual move data. This lets you inspect both move properties and the duration of a complete setup in internal frames.

For example, you can test **how many Ticks to spend before a wake-up attack reaches its intended timing**, or **how far away you can start a walk-up throw and still perform it within 15 displayed frames (20 Ticks at Turbo 3)**. Check the elapsed time in Action History, vary the starting distance and compare the actual results to develop practical setups.

### Measure and repeat

- **Tick Data / Action Timeline**: inspect startup, active time, recovery, advantage and the sequence of an action in internal frames.
- **Recording Wizard (added in this fork)**: easily capture an input sequence from start to finish. Recording starts on your first input and ends automatically after you finish. Review playback before saving.
- **Looped and random recording playback**: practise against repeated or varied offense. Supported recordings can restore the recorded spacing on each pass.
- **Position shortcuts**: quickly restore center, corner and side arrangements.

Recording and playback operate in displayed frames, so they do not reproduce input timing with Tick-level precision. Use Action Steps for drills that require precise internal-frame timing, especially at turbo speeds.

The original already includes recording, reversal settings, an AG counter and a GC-window display. This fork builds on them with **more precise action reproduction and more detailed feedback on inputs and interactions**. See the [manual introduction](docs/PLAYER_MANUAL.en.md) for a comparison.

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

### First things to try

Choose characters, wait for the match to begin and open the menu with `Lua Hotkey 1`.

- Make the dummy block: set `Dummy > Guard = All Guard` and `Random Guard % = 100%`.
- Record offense: open `Recording > Recording Wizard` and follow the prompts to record, review and save.
- Run counter actions or Action Steps: choose `Guard Action Type` and start with `Random Guard Action % = 100%`.

If `Random Guard %` or `Random Guard Action %` is `0%`, that behavior will not run; the row turns orange as a reminder. These instructions use **the current UI labels**.

### Optional ROM patches

The release zip includes IPS patches in `support/ips`. For `vsavj` they are `No-BGM`, `No-TechHit` and `Only-One-TechHit` to `Only-Six-TechHit`.

1. Put the `support` folder in the copied fbneo folder and launch through the batch file.
2. Press `F6` or choose `Game > Load Game...`.
3. Select `Vampire Savior - the lord of vampire (970519 Japan)` and open `IPS Manager` at the bottom right.
4. Check the patch you want and press `OK`.
5. Check `Apply Patch` above the `IPS Manager` button and click `Play`.

Close the emulator and launch it again to return to the unpatched game.

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

This project is based on [VSAV_Training's fc2 branch](https://github.com/NBeing/VSAV_Training/tree/fc2). Thanks to the creators and contributors of the original training mode and its scripts, and to the VSAV community.

<details>
<summary>Credits from the original README</summary>

Shoutouts to: Dammit and Jed for their wizardry, Grouflon (Stole their 3s training mode menu, and settings workflow!) and the VSAV Community.

BIGGEST SHOUTOUT to KyleW! This definitely would not have happened or continued without you.

`N-Bee`

</details>
