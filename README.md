# VSAV_Training - The Warlord's Secret

See what the Warlord sees, and practice what the Warlord practices, in VSAV training mode for Fightcade 2.

English | [日本語](README.ja.md)

**A training mode for Fightcade 2 / FBNeo that reproduces opponent actions with internal-frame (Tick) precision, so you can test your offense and practice your defense.** Detailed displays of your inputs and their timing help you see why an attempt succeeded or failed and adjust your timing.

This fork extends [VSAV_Training's fc2 branch](https://github.com/NBeing/VSAV_Training/tree/fc2). This README covers **v11.7.19**.

**[Download](https://github.com/vampiresavior001/VSAV_Training/archive/refs/heads/fc2-v11.zip)** · [Installation](#windows-installation) · [First AG / GC drill](#first-ag-drill) · [English manual](docs/PLAYER_MANUAL.en.md)

## Reproduce, test and improve in Ticks

A Tick is an internal game frame.

**Reproduce expert-level execution by defining actions and timing in Action Steps.** Set up a dash followed by an attack, both timed as early as possible, or crouching medium kick canceled into Tenraiha—without having to perform the sequence yourself.

**Reproduce the offense → try AG, GC or an interrupt → use the readouts to refine your inputs.** Repeat the same sequence to improve your response.

| Game speed | Displayed frames and internal frames |
|---|---|
| Normal | One displayed frame = one Tick |
| Turbo 3 | Three displayed frames = four Ticks |

This fork controls inputs on that internal clock, improving the precision of responses that were limited in the original. On wake-up, after blocking and after landing, you can specify **light attacks, throws, jumps and dashes**, as well as special-move reversals.

See [Action Steps](docs/PLAYER_MANUAL.en.md#06-steps) for the conditions required to act at the earliest possible moment.

## What you can test and practice

| Goal | How to use the tool |
|---|---|
| **Test when your offense works** | Make the dummy respond with a light normal, throw, jump or dash, then test whether your pressure or wake-up setup beats it |
| **Reproduce strings and combos precisely** | Define Tick-based actions with Action Steps; save, randomize and share them with Action Patterns. You can even define sequences that complete infinite combos for Bulleta (B.B. Hood) or Bishamon |
| **Measure setup timing** | Use Action Timeline in Tick Data to measure the time spent setting up wake-up pressure, or how far away you can start a walk-up throw and still perform it within 15 displayed frames (20 Ticks at Turbo 3) |
| **Practice AG (Advancing Guard / Push Block)** | Delay input while fitting six valid presses inside the window. Inspect timing, simultaneous presses, inputs after the window closes, averages and success rate |
| **Practice GC (Guard Cancel)** | Inspect accepted directions, buttons and their intervals to identify command expiry or late inputs |
| **Examine situations after air guarding** | Find interruptible gaps in air chains, evaluate actual interrupt timing, see when you air-blocked and check landing advantage |

**Tick Data** avoids the turbo-frame variation of the original display-frame measurements. Its counting conventions for startup, active time, recovery and frame advantage are aligned with those used by strategy sites. See [manual Section 10](docs/PLAYER_MANUAL.en.md#10-data) for measurement conditions and how to read Action Timeline.

### See what happened to your inputs

![PB Counter and PB Stats showing AG input count, timing, simultaneous presses and practice results](docs/images/pb_counter_stats.png)

Here, six presses on Ticks 5–13 of the window activated AG. Two Ticks contained simultaneous button presses, and no inputs fell after the window closed. **See whether AG activated and what you can improve on your next attempt.** The English UI refers to AG as Push Block / PB. See [AG practice](docs/PLAYER_MANUAL.en.md#08-pb) for the full readout guide.

### Choose easy recording or precise action control

For actions you can perform yourself, **[Recording Wizard](docs/PLAYER_MANUAL.en.md#05-recording)** offers a quick way to record them. It automatically captures your inputs from start to finish, then lets you review and save the recording.

**Recording and playback operate in displayed frames.** Use Action Steps for difficult execution or precise Tick-level timing.

## Before installing: disable Runahead

**Select `Video > Runahead > Disabled` in FBNeo itself. Leaving Runahead enabled causes the training script to behave incorrectly.**

If you also play matches through Fightcade, **copy the entire `emulator/fbneo` folder to create a separate training installation**. Apply this setting in the copy and keep separate launch paths and settings, so you do not have to remember to switch them for every session.

| Use | Launch method |
|---|---|
| Matches | Launch normally through Fightcade |
| Training | Launch the copied `run_vsav_training.bat`; select `Video > Runahead > Disabled` |

## Windows installation

The target game is **Vampire Savior - the lord of vampire (970519 Japan / `vsavj`)**.

**ROMs are not included. Supply your own files and first make sure the game runs in FBNeo.**

1. Close Fightcade and FBNeo.
2. Copy Fightcade's entire `emulator/fbneo` folder to another location, for example `C:/VSAV_Training/fbneo`.
3. Download and extract this project. Put `run_vsav_training.bat` and the entire `scripts` folder in the **copied fbneo folder**, with the batch file next to `fcadefbneo.exe`.
4. Launch the copied batch file and select **`Video > Runahead > Disabled`** in FBNeo itself. Copying the folder also copies settings; it does not disable Runahead by itself.
5. Fully close FBNeo, relaunch through the same batch file and confirm that `Disabled` is selected under `Video > Runahead`.
6. Use `Input > Map Game Inputs` to configure game controls and the functions below. Configure P2 game inputs too.

To play in full screen, check `Video > Blitter options > Windowed Fullscreen` first. The older full-screen mode cannot show the windows used to name, export and import patterns.

Use a short path without spaces or Japanese characters. Before updating an existing installation, make a [backup](#updates-and-backups).

### Basic controls

**Always assign `Lua Hotkey 1` and `P1 Coin`: neither has a menu equivalent.** The other shortcuts can be replaced by the menu operations below.

<details>
<summary>Show shortcuts and their menu alternatives</summary>

| FBNeo input entry | Function | Menu alternative |
|---|---|---|
| `Lua Hotkey 1` | Open/close the training menu | No alternative — **required** |
| `Lua Hotkey 2` | Restore positions by holding a direction and pressing the hotkey | In `Dummy > Position`, use Left/Right to choose a layout. LP restores it again; HP also closes the menu |
| `Lua Hotkey 3` | Toggle looping for recorded inputs | In `Recording > Looped Playback`, use Left/Right to switch between `yes` and `no` |
| `Lua Hotkey 4` | Return to character select | Select `Game > Return to Character Select` and press Right or LP |
| `Volume Up` | Start/stop standard recording | Open `Recording > Recording Wizard` with Right or LP, choose a slot and use automatic recording (see below) |
| `Volume Down` | Start/stop playback | Select `Recording > Play Recording` and press Right or LP. Activate it again to stop |
| `P1 Coin` | Switch which character you control during a match; choose a stage at character select | No alternative — **required** |

Open the menu with `Lua Hotkey 1`. With a tab name selected, use Left/Right to switch tabs, then Up/Down to select an item. LP means light punch. `>` means “tab > item.”

**To record through the menu:** choose a slot in the wizard, release all inputs, then start moving to begin recording. Finish your action and release the controls. Recording ends automatically after about two seconds of no input while the dummy is free to act. On the confirmation screen, select the save option and press LP. Use `Volume Up` if you want to start and stop recording manually.

Recording's `Looped Playback` and Action Steps' `Loop Steps` are separate settings. See the [recording instructions](docs/PLAYER_MANUAL.en.md#05-recording) for details.

`Volume Up / Down` are FBNeo input entries. You can assign them to arcade-stick or controller buttons.

</details>

<a id="first-ag-drill"></a>

## First drill: Practice AG and GC against Sasquatch

Make Sasquatch perform short-dash LP, then practice AG (Advancing Guard / Push Block) and GC (Guard Cancel) against it. Save the sequence so you can use it again next time.

**Start by trying either AG or GC. Looping and saving can wait until you are comfortable with the drill.**

1. **Build it.** Choose Sasquatch as the dummy. With `Reversal - Action Steps`, define `Dash > Forward Cancel` (`Auto (Fastest)`) followed by LP (`Auto (8)`).
2. **Practice AG.** Make the dummy block your attack to trigger short-dash LP, then perform AG against it. Use PB Counter / PB Stats to check, for example, whether you delayed AG while fitting six valid presses inside the window.
3. **Try GC too.** Block the same LP and enter your character’s GC command. Check the success indicator, accepted directions and buttons, and input intervals.
4. **Repeat it.** Set `Loop Steps = yes` and `Loop Wait = Auto (Landing)` to repeat short-dash LP as soon as the dummy lands.
5. **Save it.** Use `Add from current Steps` in Action Patterns to save it as `Short LP`. Save other attacks later to practice against randomly selected sequences.

Follow the **[complete walkthrough: setup, AG / GC feedback, looping and saving](docs/PLAYER_MANUAL.en.md#sasquatch-ag-tutorial)**. Start with one response at a time, then move on to repeated practice.

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

Update the separate training installation. The downloaded files may include recordings, so take care not to overwrite your own. Fully restart FBNeo afterward and confirm that `Disabled` is selected under `Video > Runahead`.

## Release history and reports

- [Release notes](docs/RELEASE_NOTES.md)
- [日本語リリースノート](docs/RELEASE_NOTES.ja.md)
- [This fork's Issues](https://github.com/vampiresavior001/VSAV_Training/issues)

When reporting a problem, include the version, P1/P2 characters, which character is on each side, screenshots of your settings and steps to reproduce the problem. In your training copy of FBNeo, confirm that `Disabled` is selected under `Video > Runahead`.

## Original project and credits

This project is based on [VSAV_Training's fc2 branch](https://github.com/NBeing/VSAV_Training/tree/fc2). The original already includes recording, reversal settings, an AG counter and a GC-window display. This fork builds on them with more precise action reproduction and more detailed feedback; see the [feature comparison](docs/PLAYER_MANUAL.en.md). Thanks to the creators and contributors of the original training mode and its scripts, and to the VSAV community.

<details>
<summary>Credits from the original README</summary>

Shoutouts to: Dammit and Jed for their wizardry, Grouflon (Stole their 3s training mode menu, and settings workflow!) and the VSAV Community.

BIGGEST SHOUTOUT to KyleW! This definitely would not have happened or continued without you.

`N-Bee`

</details>
