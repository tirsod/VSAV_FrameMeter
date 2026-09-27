 # Frame Meter UI for VSAV_Training
*A fork of a fork of VSAV's trainer tools.*
**You must supply your own ROM!** 

💬 This fork includes a frame meter *(similar to SF6's)*, which uses the game-tick clocks included by vampiresavior001's v11. It does not fix bugs or add any other features to the trainer. Just the frame meter.

🛠️ For the latest trainer, please see [the parent fork.](https://github.com/vampiresavior001/VSAV_Training/tree/fc2-v11)

📦 Downloads: [Trainer11.7.1+Meter0.2](https://github.com/tirsod/VSAV_FrameMeter/releases)

Special thanks to nbee, zako, hagure, kyle, bagel and vampiresavior001 for their help and input. 

``tirsod``

## Preview

<img width="640" height="480" alt="random demo wolf" src="https://github.com/user-attachments/assets/e24f862e-acc6-4e57-aa48-37aa3a3ef388" />

## Usage

 Open the trainer menu using **Lua hotkey 1**, then navigate to the **Analysis** tab to enable the meter.
 The following options are available.
 
 - Frame Meter: Enables the meter display on screen.
 - Show Throw Invulnerability: Enables special tiles on the meter when the player is invulnerable to being thrown. These states are not counted.
 - Show Movement Data: Enables logging during jumps and dashes, shown as cyan tiles. These states are not counted.
 - Show Player 1 Inputs: Enables "tombstones" display. A minimal pixel-sized input display is added above the tiles.
 - Log Hitstop Frames: Enables logging *during* [hitstop](https://glossary.infil.net/?t=Hitstop) frames. The game logs continues to record input during hitstop to allow for pushblocks, guard cancelling and chaining. Use this in conjunction with "Show Player 1 Inputs" to practice input timing.

## Legend

 - <img width="8" height="16" alt="FM_inactive" src="https://github.com/user-attachments/assets/e861d457-70ce-4ea7-b5de-058649b78d5e"/> Inactive State
 - <img width="8" height="16" alt="FM_startup" src="https://github.com/user-attachments/assets/5d7d71b5-6957-4fe4-9ecd-8e5932801a77"/> Startup (Pre-Active)
 - <img width="8" height="16" alt="FM_active" src="https://github.com/user-attachments/assets/e6c25919-7cc7-439f-9006-0bdf2bd57482" /> Active (Hitbox Present)
 - <img width="8" height="16" alt="FM_recovery" src="https://github.com/user-attachments/assets/622f72ff-7b96-4aa9-8e67-35cdd479e969" /> Recovery (Post-Active)
 - <img width="8" height="16" alt="FM_hurt" src="https://github.com/user-attachments/assets/a764254c-ea63-4e04-94c8-077324277289" /> Hurt or Blocking
 - <img width="8" height="16" alt="FM_invul" src="https://github.com/user-attachments/assets/e286f01d-7c17-4496-a21b-50bdabfd2f5a" /> Invulnerability
 - <img width="8" height="16" alt="FM_nothrow" src="https://github.com/user-attachments/assets/9d72a9e3-2bc8-443f-a036-b769b4a4da0c" /> Throw Protection
 - <img width="8" height="16" alt="FM_move" src="https://github.com/user-attachments/assets/27c20e2d-13f8-4114-88e0-424826000668" /> Movement State (Dash or Jump)
 - <img width="8" height="16" alt="FM_pushblock" src="https://github.com/user-attachments/assets/e5001131-e927-44a0-828e-518983b0baea" /> Pushblock Possible
 - <img width="8" height="16" alt="FM_pushblock_OK" src="https://github.com/user-attachments/assets/adcaae2d-94b2-4fa6-9e5c-9a2fd389f743" /> Pushblock Performed

## Scrolling

After 5 frames of idle states from both players, the meter will freeze logging and show advantage numbers.
During this time, you can hold down+back or down+forward on the stick to scroll through the meter's data.

<img width="640" height="480" alt="meter scroll and multipage" src="https://github.com/user-attachments/assets/af929f38-29b4-43b7-bdd8-538169f4e2c1" />

## Tombstones

The input display shows buttons as a 3x2 pixel grid, with an arrow for directional inputs underneath.
They are logged when the input state *changes*, not every frame.
Example displays:

<img width="330" height="77" alt="image" src="https://github.com/user-attachments/assets/303f28c6-eaf9-4fbb-9069-488ec631125e" /> Lilith's Luminous Illusion

<img width="330" height="77" alt="image" src="https://github.com/user-attachments/assets/005236d8-8484-45ba-95a3-d2b0a829dc79" /> Felicia 2MP into ES Rolling Buckler

## Windows Installation 
Follow the video guide: https://www.youtube.com/watch?v=To7DpTNSRi8

What is described in the video guide: 
  1) Place `run_vsav_training.bat` file and the `scripts` folder in your `...\Fightcade\emulator\fbneo`
  3) IMPORTANT: The path where you installed fightcade 2 should not have a space in it: e.g. 
  Bad: `C:/fightcade 2/` Good: `C:/fightcade2`. Try to make sure the path is also not too deep.
  4) Double click `run_vsav_training.bat`
  5) Set up hotkeys in fbneo input  Input --> Map Game Inputs (Can map to controller):
    a) Lua Hotkey 1 - Opens training menu
    b) Lua Hotkey 4 - Return to CSS
    c) Volume Up - Record Dummy 
    d) Volume Down - Playback Dummy

##  Linux Installation
  1) Place  `run_vsav_training.sh` and `scripts` in your `...\Fightcade\emulator\fbneo`
  3) Run `./run_vsav_training.sh` in the terminal

##  MacOS installation

1) Place the `scripts` folder in `/Applications/FightCade2.app/Contents/MacOS/emulator/fbneo/`
2) Create a text document in your `/Applications/FightCade2.app/Contents/MacOS/emulator/fbneo/` titled `run_vsav_training.command`
3) In the `run_vsav_training.command` document you created, copy and paste the contents of the file `run_vsav_training.command`
5) double click on the `run_vsav_training.command`

## Rom Patch installation

1) Place the 'support' folder in your `...\Fightcade\emulator\fbneo`
3) Launch the training mode with the .bat file
4) Press `F6` or click the `Game` dropdown on the top bar then press `Load Game...`
5) Select `Vampire Savior - the lord of vampire (970519 Japan)` and in the bottom right corner select `IPS Manager`
6) Check the box for the patch you want and press `OK`
7) Check the `Apply Patch` button above the `IPS Manager` button you selected
8) Click `Play`
9) Once the game reloads you will be playing on the patched version
10) Close the emulator and relaunch to return to the normal version

Video Guide here https://youtu.be/HwyTAnbSw_I

### Debugging Installation Issues

  1) If you encounter `gd.dll` issue, reinstall Fightcade 2. `gd.dll` is part of Fightcade 2 and not my training mode. It seems to break on update occasionally.
  2) If you are having issues with the above, make sure to whitelist `fcadefbneo.exe` on windows defender or other AntiVirus
  3) If you are having weird input issues make sure p2 controls are bound!
  4) If the .bat script does not work it may be because your path has spaces or is too long. I cannot control this, this is part of FC2 FBneo lua. See step 3 for more info above.
  5) Reach out to me on the Vampire Savior Discord's #development channel! I will usually respond on the same day.
  
## Hotkeys

You can configure these in FBNEO's Input>Map game inputs... (F5)

<img width="206" height="78" alt="image" src="https://github.com/user-attachments/assets/41a6f1ca-52f1-4fc6-b0c7-b76987674036" /> 

    Press Lua Hotkey 1 to open the training menu.
    Press Coin while hovering over a character in character select to select a stage
    Press Coin while in a match to swap controls to dummy
    Press Volume Down to play back recording. (found in 'map game inputs')
    Press Volume Up to record dummy. (found in 'map game inputs')
    Press Alt + 3 to toggle looping playback.
    Press Alt + 4 to return to character select

## More Demos

<img width="640" height="480" alt="demo for normals, projectiles and jumpins" src="https://github.com/user-attachments/assets/ae66ade5-3312-4a42-9b99-27ae590cb224" />
<img width="640" height="480" alt="df demo" src="https://github.com/user-attachments/assets/de876193-cdbe-45de-8fc7-5f82e3d4c326" />
<img width="640" height="480" alt="hitstop and 2player" src="https://github.com/user-attachments/assets/ce2e3ce4-876e-4636-8e95-c4197fb1bbe5" />
