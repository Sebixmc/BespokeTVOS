# Fire TV Clean-Up Kit

## 👉 [Open the step-by-step guide](https://sebixmc.github.io/BespokeTVOS/)

Start here. It's also in the download as **GUIDE.html**: double-click it to open it in your browser.

Makes an Amazon Fire TV (a Fire TV stick, Cube or smart TV running **Fire OS**) faster and quieter:

- **Turns off Amazon's ads, tracking and junk apps.** Nothing is deleted, and it can all be undone.
- **Replaces Amazon's ad-filled home screen** with [Projectivy Launcher](https://github.com/spocky/miproja1), a clean home screen you can arrange yourself.
- **Blocks Amazon's tracking servers** using free [AdGuard DNS](https://adguard-dns.io/). Only the TV changes, not your router.

Prime Video, the Appstore, Alexa, Live TV, AirPlay and HDMI inputs keep working.

> Doesn't work on **Vega OS** devices (the newest Fire TV Sticks). On the TV, check **Settings → My Fire TV → About**: the software line has to say "Fire OS".

## Windows: quick steps

1. **On the TV:** go to **Settings → My Fire TV → About**, highlight the first line, and press the select button **7 times**. Then, under **Developer Options**, turn **ADB debugging** ON. Write down the IP address from **About → Network**.
2. **On the PC:** [download this kit as a ZIP](https://github.com/Sebixmc/BespokeTVOS/archive/refs/heads/main.zip). Right-click it → **Extract All**.
3. Open the extracted folder and double-click **`START-HERE.bat`**. If Windows warns you, click **More info → Run anyway**.
4. Type **`1`** to connect, enter the TV's IP address, then on the TV tick **Always allow** and press **OK**.
5. Type **`2`** to do everything, and follow the yellow instructions.

To put everything back, double-click `START-HERE.bat` again and type **`8`**.

## What's in here

| File | What it is |
|---|---|
| `START-HERE.bat` | The file to double-click on Windows |
| `windows/firetv-kit.ps1` | The menu and all the steps (PowerShell) |
| `config/disable.txt` | The list of Amazon apps and services that get turned off, with notes |
| `scripts/` | Mac versions (`debloat.sh`, `privacy-dns.sh`) |

The first time the kit runs, it downloads Google's official [Android platform-tools](https://developer.android.com/tools/releases/platform-tools) and the latest Projectivy release from its developer's GitHub.
