# Player-facing UI and Documentation Improvement Proposals

English | [日本語](PLAYER_UX_REVIEW.ja.md)

Target: v11.7.16, commit `351e31034a3e4eb067e60c4f74f17ec59277ca20`. Reviewed: 2026-09-29.

These findings come from source inspection while preparing the player manual. All changes below are proposals; no game or UI changes have been implemented. Emulator testing was not performed for this review.

## Implementation status (2026-09-29)

Implemented after v11.7.16.1: items 1, 2, 3, 4 (display only), 5 and 9, and the six-press wording. Items 6, 7 and 8 remain proposals. The player manuals and READMEs use the new labels.

- 1: the startup console message names Lua Hotkey 1–4 and no longer mentions Start or Alt.
- 2: the Tick Data description gives `4 + 3 + 7 - 1 = 13` and says Total includes gaps between hits.
- 3: descriptions use `Reversal - Action Steps` and `Reversal Action Steps`.
- 4 / 9: `Random Guard %`, `Random Guard Action %` and `Random Throw Tech %`, with `0%` in place of None. A 0% that stops the selected guard or guard action turns its row orange, and the bottom line says why. Stored values and defaults are unchanged. `Guard Action Frequency Check` on the Analysis tab is now `Random Guard Action % Check`.
- 5: each Wait choice has its own one-line description below the list.
- AG: the probability table at ROM `0x028D50`, read while the game ran, gives 0% for presses 1–2, 25/50/75% for the 3rd–5th and 100% from the 6th. Descriptions now say the 6th press always activates.

## Priority 1: instructions do not match behavior

### 1. The startup menu-button instruction is outdated

- Finding: startup text says `Press Start open the training menu`, but controller.lua's Start-based menu toggle is commented out. The actual registered control is Lua Hotkey 1.
- Impact: new users cannot reach the menu and may think their mappings are wrong.
- Proposal: consistently say `Lua Hotkey 1` and explain mapping it under `Input > Map Game Inputs`. Describe Lua Hotkey 3/4 first rather than presenting Alt+3/4 as fixed bindings.
- Sources: [vsav_training_master_script.lua](../scripts/vsav_training_master_script.lua), [controller.lua](../scripts/controller.lua).

### 2. Tick Data's description does not match its calculation

- Finding: the menu says startup, active and recovery add up to Total. The calculation shares the first hitbox Tick between startup and active. A basic single-move example is `4 + 3 + 7 - 1 = 13`.
- Impact: correct numbers look like an arithmetic error. Multi-hit moves also have gaps, making a simple-sum explanation more misleading.
- Proposal: explain the actual counting convention, the basic single-move formula and the inclusion of gaps between active periods in Total.
- Sources: `Tick Data` in [menu.lua](../scripts/menu.lua), result generation in [tickData.lua](../scripts/tickData.lua).

### 3. Descriptions still reference obsolete option names

- Finding: Action Steps instructions still mention `Reversal - Sequence` and `Reversal Sequence`; current choices are `Reversal - Action Steps` and the editor row `Reversal Action Steps`.
- Impact: players cannot find the option named in the instructions.
- Proposal: use the current labels and review references in descriptions whenever a label changes.
- Sources: parent_item in [actionSequenceEditor.lua](../scripts/actionSequenceEditor.lua), Guard Action Type descriptions in [menu.lua](../scripts/menu.lua).

## Priority 2: settings are easy to misinterpret

### 4. Selecting a guard or counter action can leave its probability at None

- Finding: `P2 Random Guard %` is separate from the guard method and defaults to None. `Guard Action Frequency` also defaults to None. Steps/Patterns already warn about None frequency.
- Impact: selecting All Guard or a counter-action type looks like enabling it, but nothing happens.
- Recommendation: preserve stored values and consistently show that the behavior is disabled because its probability is 0%. Extend the warning beyond Steps/Patterns. Align labels and None changes with proposal 9.
- Alternative: suggest 100% on first selection. Since this affects practice configuration, consider it separately from a display-only correction.
- Sources: [config.lua](../scripts/config.lua), [menu.lua](../scripts/menu.lua), [actionSequenceEditor.lua](../scripts/actionSequenceEditor.lua).

### 5. After and Landing both appear to mean “earliest Auto”

- Finding: After starts inputs once the dummy can act; a ground dash also waits for the ground. Landing predicts touchdown and enters the motion ahead of time so its final input arrives on landing. The generic editor description `Auto is the earliest` does not communicate this distinction.
- Impact: players may treat an After dash as the earliest possible dash and draw incorrect conclusions about pressure or interrupts.
- Proposal: distinguish “After: start inputs after recovery; no pre-input” from “Landing: pre-input to finish on landing.” If practical, indicate when missing prediction causes a fallback to input starting after touchdown.
- Scope: renaming all Auto modes would also affect other meanings, such as measured timing after dashes. Start with After/Landing descriptions.
- Sources: landing_ready, step.auto and LOOP_AUTO in [actionSequenceRunner.lua](../scripts/actionSequenceRunner.lua); HELP.wait in [actionSequenceEditor.lua](../scripts/actionSequenceEditor.lua).

### 6. Guard Action Delay sounds like a delay before the entire response

- Finding: for Specified actions, it primarily delays the button after the motion, not the dash itself. GC has a separate `GC Input Delay (Ticks)` setting.
- Impact: a delayed dash and a delayed attack during a dash are easily confused.
- Proposal: use a label such as `Button Delay after Motion (Ticks)` for Specified actions. Other Guard Action Types use the same setting, so evaluate labels by context instead of renaming every use indiscriminately.
- Sources: guard_action_delay_menu_item and gc_input_delay_menu_item in [menu.lua](../scripts/menu.lua).

### 7. Wait choices differ from their resulting labels, and zero is not shown numerically

- Finding: the selector uses After, Landing and Fixed Ticks, while the list shows Auto (After), Auto (Landing) and +Nt. Step one's minimum is labeled Auto (Fastest) inside Fixed Ticks. Hold duration comes from the next step's Wait.
- Impact: it is hard to discover that Fastest is inside Fixed Ticks or understand that Wait is not the duration of the action on that row.
- Proposal: offer Fastest directly for step one. Explain Wait as “delay before this action” and Hold as “hold the direction until the next step.” Retain the current `+Nt` and `Hold Nt` displays.
- Sources: wait_label, the Wait screen and detail_items in [actionSequenceEditor.lua](../scripts/actionSequenceEditor.lua).

### 8. Timing displays use different units

- Finding: Tick Data and Steps use internal frames; dash trainers, recording/playback and recording intervals use displayed frames. IAD Trainer shows height.
- Impact: equal numbers can mean different things and invite invalid comparisons.
- Proposal: always append `t` or `display f` to timing results. Explain “Normal: 1 display frame = 1 Tick / Turbo 3: 3 display frames = 4 Ticks” under Game Speed. Clearly distinguish height from time.
- Sources: trainer descriptions in [menu.lua](../scripts/menu.lua), [hud.lua](../scripts/hud.lua).

### 9. Standardize probability labels in the Dummy tab

The current UI has three settings where players specify a percentage. Since the Dummy tab makes the target clear, omit the P2 prefix. Use Random and % consistently, retaining wording familiar to Japanese-speaking players; do not rename these to Chance.

| Current label | Proposed label | Meaning |
|---|---|---|
| `P2 Random Guard %` | `Random Guard %` | Probability of blocking |
| `Guard Action Frequency` | `Random Guard Action %` | Probability of performing the configured guard action |
| `Tech Throws` | `Random Throw Tech %` | Probability of a throw tech |

Use `0% / 25% / 50% / 75% / 100%` for all three. Change the displayed None to 0% only. Keep None where it means no selected action or input, such as `Guard Action Type = None` or a direction/button choice.

#### Scope and checks

- Preserve internal setting keys, stored choice indices, defaults and random-selection logic. Existing saves must retain their meaning.
- Keep `Guard Action Type`. Action selection and execution probability remain separate fields.
- Update menu help, Steps/Patterns warnings about None frequency and references in the `Show GC Frequency Counter` description. That counter is a measured readout, not a fourth probability setting.
- Check renamed labels fit the menu columns and description area.
- After the UI changes are implemented, update both language versions of the manual's labels and procedures. Until then, the manuals must use the actual current labels.

#### Other random settings are outside these three

Random choices in `Wakeup`, recording-slot playback, Action Patterns, `Pit of Blame`, and the 0 = Random setting of `Gloomy Puppet Show` select among candidates. They do not let players specify a percentage. Do not replace their zero or None values with 0% globally.

The source also retains a probability list and default for `counter_attack_random_upback`, but the current menu does not register a row for it. It is therefore not a fourth current UI setting.

- Sources: probability lists, menu rows and get_menu in [menu.lua](../scripts/menu.lua), [config.lua](../scripts/config.lua), warning display in [actionSequenceEditor.lua](../scripts/actionSequenceEditor.lua).

## Preserve the current AG counter behavior

The earlier suggestion to split off post-activation presses is withdrawn. Counting them is an intentional design for practising all six presses every time. Players do not need to stop their hands as soon as AG activates.

- Practice target: delay as much as possible while fitting six valid presses inside the window.
- Display purpose: review activation, input timing and the total presses in the sequence.
- LateMash: presses after the window closes, not merely after activation. Keep this distinct from completing presses inside the window after AG has activated.
- Basis: `THE PUSH BLOCK COUNT IS A TRAINING NUMBER: PRESSES MADE` in [timers.lua](../scripts/timers.lua), and the developer's explanation of the design intent.

Some descriptions in menu.lua and elsewhere still say eight presses guarantee activation, while timers.lua says six and explicitly identifies six as the practice target. Align player-facing explanations around six. An eight-count comparison branch alone does not rule out a probability table that already guarantees activation at six. The ROM probability table itself was not verified in this review; inspect it before correcting the internal-analysis comments.

## Recommended order

1. Correct the startup instructions, Tick Data description and obsolete option names.
2. Standardize the three probability labels, 0% display and warnings; clarify After/Landing.
3. Improve Delay, Wait and unit labels.
4. Preserve the AG counter behavior and align explanations with the late-six-press practice goal and activation threshold.

Step 1 corrects documentation without changing behavior. Later items affect the UI and should be reviewed before implementation. Defaults or automatic adjustments can change existing setups and should be treated separately.
