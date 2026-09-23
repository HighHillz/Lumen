# Keeping your customizations safe

This guide covers two situations:

- **Rebooting**: making sure what you changed is still there after a restart.
- **Moving to another machine**: getting the same setup, with your changes, on a new install.

Packages are listed in [requirements.txt](requirements.txt).

---

## 1. Where your setup actually lives

Your setup is spread across four places. Knowing which is which explains almost everything below.

| Place | What it holds | Tracked in this repo? |
|---|---|---|
| `~/lumen` | This repository: a copy of the config files | Yes |
| `~/.config/hypr`, `~/.config/quickshell`, … | The **live** config that Hyprland and Quickshell actually read | No, unless you symlink it (see section 4) |
| `~/.local/state/lumen/`, `~/.local/state/ricelin/` | Settings the shell saves as you use it | No |
| `~/.cache/lumen/` | Generated colors and shaders | No. It is rebuilt automatically, so you never need to save it |

On a plain install, `~/lumen` and `~/.config` are **separate copies**. Editing one does not change the other.

### What the UI writes, and where

Every setting you change in the pill is written to disk immediately:

| Change you make | File it is written to |
|---|---|
| Keybinds (Settings → Keybinds) | `~/.config/hypr/modules/binds.lua` |
| Special workspaces (names, keys, apps) | `~/.config/hypr/modules/spaces.lua` |
| Look, animation, input, display settings | `~/.config/hypr/modules/decoration.lua`, `animations.lua`, `input.lua`, `monitors.lua` |
| Night light mode, warmth, schedule | `~/.local/state/lumen/flags.json` and `~/.config/hypr/hyprsunset.conf` |
| UI font, scale, DND, recorder options, weather city, wallpaper folder | `~/.local/state/lumen/flags.json` |
| Current wallpaper, per-monitor wallpapers | `~/.local/state/lumen/lumen-wallpaper*` |
| Vibrance | `~/.local/state/ricelin/nvibrant-value` |
| Launcher usage history | `~/.local/state/lumen/launcher-usage.json` |

---

## 2. Rebooting

**Rebooting on its own never loses anything.** Everything in the table above is a file on disk, and it is read again at login:

- **Hyprland** reads `~/.config/hypr/hyprland.lua` and every module it `require`s. That covers binds, workspaces, look and monitors.
- **Quickshell** reads `flags.json` and the other state files when it starts. It then puts vibrance back and restores the wallpaper.
- **Brightness** is saved by systemd at shutdown and restored at boot (`systemd-backlight`). You don't need to do anything.
- **Night light** is restored by the `hyprsunset` service, which reads `hyprsunset.conf`.

### What must be true for it all to come back

Some features depend on a package being installed or a service being enabled. If one of these is missing, the feature silently does nothing, both after a reboot and before it.

```sh
# Services that must be enabled once
sudo systemctl enable --now NetworkManager bluetooth
systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber
systemctl --user enable --now hyprsunset hypridle
```

Check them at any time:

```sh
systemctl is-enabled NetworkManager bluetooth
systemctl --user is-enabled pipewire.socket wireplumber hyprsunset hypridle
```

Check for missing packages at any time. This prints only the packages that are **not** installed:

```sh
pacman -T $(sed 's/#.*//' ~/lumen/requirements.txt)
```

---

## 3. The two ways you *can* lose changes

A reboot won't lose anything. These two things can.

### Risk 1: the repo and the live config drift apart

The UI edits `~/.config`, never `~/lumen`. If you then commit `~/lumen`, or set up a new machine from it, your UI changes aren't included. The same happens the other way round: editing a file in `~/lumen` has no effect until it is copied into `~/.config`.

Show every file that differs between the two:

```sh
for d in hypr quickshell fish kitty fastfetch fontconfig nvim nvim-qt spicetify; do
    diff -rq ~/lumen/$d ~/.config/$d 2>/dev/null
done
diff -q ~/lumen/starship.toml ~/.config/starship.toml
diff -q ~/lumen/mimeapps.list ~/.config/mimeapps.list
```

No output means both copies are identical.

### Risk 2: `lumen update` overwrites code files

The built-in updater (Settings → Updates, or `lumen update`) pulls from the upstream Ricelin project. It treats files in two ways:

- **Protected files** are merged with upstream, so your edits survive. Before each update it saves a backup to `~/.local/share/lumen-update-backup/<date>/`. The protected files are:
  `hypr/modules/decoration.lua`, `binds.lua`, `monitors.lua`, `input.lua`, `env.lua`, `autostart.lua`, `animations.lua`, `stash-apps.lua`, `spaces.lua`, `hypr/hypridle.conf`, `fish/config.fish`
- **Everything else is replaced with upstream's version.** That includes all of `~/.config/quickshell/` and the scripts in `~/.config/hypr/scripts/`.

So any change to a QML file or a script (for example the vibrance fix in `Singletons/Devices.qml`, or the Keybinds sub-pages) is **wiped out by the next update**. Only the protected files are safe.

The updater skips itself entirely ("devmode") when `~/.config/hypr` or `~/.config/quickshell` is a symlink into a git repository. The next section uses that.

---

## 4. Recommended: link `~/.config` to this repo

If you replace the separate copies with **symlinks** into `~/lumen`, both risks go away at once:

- There is only one copy of each file. UI changes land directly in the repo, so `git status` shows them and you can commit them.
- `lumen update` detects the symlinks, switches to devmode and never overwrites anything.

The trade-off: upstream Ricelin updates no longer arrive automatically. Upstream uses a different folder layout (`configs/…`), so you would pick up its changes by hand if you ever want them.

### One-time switch on this machine

**Step 1: bring the live changes into the repo.** The live config is what you actually use, so it wins.

```sh
cd ~/lumen
for d in hypr quickshell fish kitty fastfetch fontconfig nvim nvim-qt spicetify; do
    rsync -a ~/.config/$d/ ~/lumen/$d/
done
cp ~/.config/starship.toml ~/.config/mimeapps.list ~/lumen/
git status
git diff        # review: make sure nothing you wanted in the repo was overwritten
```

If `git diff` shows a change you *didn't* want (the repo copy was the newer one), restore that file with `git checkout -- <file>` before continuing.

**Step 2: move the old live copies aside and replace them with links.**

```sh
mkdir -p ~/config-backup
for d in hypr quickshell fish kitty fastfetch fontconfig nvim nvim-qt spicetify; do
    mv ~/.config/$d ~/config-backup/$d
    ln -s ~/lumen/$d ~/.config/$d
done
for f in starship.toml mimeapps.list; do
    mv ~/.config/$f ~/config-backup/$f
    ln -s ~/lumen/$f ~/.config/$f
done
ln -sf ~/lumen/bin/lumen ~/.local/bin/lumen
```

**Step 3: restart and check.** Run `lumen restart` (or log out and back in), and confirm that keybinds, wallpaper and the pill all work. Once you're happy, delete `~/config-backup`.

**Step 4: commit.**

```sh
cd ~/lumen && git add -A && git commit -m "Sync live config" && git push
```

From now on your workflow is: change things in the UI or in the editor, then `git commit` and `git push`.

### Things that become noisy in `git status` after linking

A few files are rewritten by programs as they run, so they will show up as changed often:

- `fish/fish_variables`: fish writes to it whenever a universal variable changes
- `nvim/lazy-lock.json`: updated when plugins update
- `hypr/hyprsunset.conf`: rewritten whenever you change night light

Committing them is fine. They are your settings too.

### Fix `.gitignore`

This repo's `.gitignore` was inherited from upstream and uses upstream's paths (`configs/hypr/...`). **None of those rules match anything here.** Files that upstream meant to keep private are therefore not ignored, for example `hypr/modules/private.lua` (machine-only binds) and `hypr/hypridle.conf`. If you keep private or secret material in `private.lua`, add it yourself:

```gitignore
hypr/modules/private.lua
```

---

## 5. Alternative: keep separate copies

If you'd rather keep the updater and plain copies, make syncing a habit.

**Before committing, copy live → repo:**

```sh
for d in hypr quickshell fish kitty fastfetch fontconfig nvim nvim-qt spicetify; do
    rsync -a ~/.config/$d/ ~/lumen/$d/
done
```

**After editing the repo, copy repo → live:**

```sh
rsync -a ~/lumen/quickshell/ ~/.config/quickshell/
rsync -a ~/lumen/hypr/ ~/.config/hypr/
```

**Before running `lumen update`**, commit and push `~/lumen` first. After the update, run the drift check from section 3 and re-copy any code files it reverted.

---

## 6. Setting up another machine

### Step 1: base system

Install Arch with a user account, `git`, `base-devel` and an AUR helper:

```sh
sudo pacman -S --needed git base-devel
git clone https://aur.archlinux.org/paru-bin.git /tmp/paru && (cd /tmp/paru && makepkg -si)
```

### Step 2: clone this repo

```sh
git clone https://github.com/HighHillz/Lumen.git ~/lumen
```


### Step 3: install packages

```sh
cd ~/lumen
paru -S --needed $(sed 's/#.*//' requirements.txt)
```

Drop the lines marked `(optional)` for features you don't need (for example `nvidia-utils` on a machine without an NVIDIA GPU).

### Step 4: link the config

Back up anything already in `~/.config` first. A fresh install may have a default `hypr` folder.

```sh
mkdir -p ~/.config ~/.local/bin ~/config-backup
for d in hypr quickshell fish kitty fastfetch fontconfig nvim nvim-qt spicetify; do
    [ -e ~/.config/$d ] && mv ~/.config/$d ~/config-backup/
    ln -s ~/lumen/$d ~/.config/$d
done
for f in starship.toml mimeapps.list; do
    [ -e ~/.config/$f ] && mv ~/.config/$f ~/config-backup/
    ln -s ~/lumen/$f ~/.config/$f
done
ln -sf ~/lumen/bin/lumen ~/.local/bin/lumen
```

### Step 5: enable services and set fish as your shell

```sh
sudo systemctl enable --now NetworkManager bluetooth
systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber
systemctl --user enable hyprsunset hypridle
chsh -s /usr/bin/fish
```

### Step 6: restore your personal state (optional)

Copy these from the old machine to get your exact pill settings and wallpapers back (see section 7):

```sh
# on the old machine
tar czf lumen-state.tgz -C ~ .local/state/lumen .local/state/ricelin Pictures/Wallpapers

# on the new machine
tar xzf lumen-state.tgz -C ~
```

Without this, the shell starts with default settings, and you pick a wallpaper folder the first time you open the wallpaper picker.

### Step 7: adjust hardware-specific values

Some values in the repo are specific to this laptop. Check each one on the new machine:

| File | Value | How to find the right one |
|---|---|---|
| `hypr/modules/monitors.lua` | Monitor names, resolutions, scale | `hyprctl monitors` |
| `hypr/modules/binds.lua` | `touchpadName` in the Touchpad section | `hyprctl devices`, under "mice" |
| `hypr/modules/env.lua` | `XCURSOR_THEME` must match an installed cursor theme | `ls /usr/share/icons ~/.local/share/icons` |
| `bin/micmute-sync` | Mic-mute LED path `/sys/class/leds/platform::micmute` | `ls /sys/class/leds` |
| `hypr/modules/input.lua` | Keyboard layout, touchpad settings | Your preference |

### Step 8: log in to Hyprland

Log in and check that the pill appears. If it doesn't, run `lumen log` to see why. The most common cause is a missing package; `pacman -T $(sed 's/#.*//' ~/lumen/requirements.txt)` lists any.

---

## 7. What to back up outside the repo

The repo covers your configuration. These hold personal data it doesn't cover:

| Path | What it is | Needed? |
|---|---|---|
| `~/.local/state/lumen/` | All pill settings (`flags.json`), wallpaper choice, launcher history | Yes, if you want your exact settings back |
| `~/.local/state/ricelin/nvibrant-value` | Vibrance level | Nice to have |
| `~/Pictures/Wallpapers/` | Your wallpaper images | Yes, the repo doesn't include them |
| `~/Videos/Recordings/` | Screen recordings (or the folder set in the recorder) | Your call |
| `~/.cache/lumen/` | Generated colors and shaders | **No**, regenerated automatically |
| `~/.local/share/lumen-update-backup/` | Backups made by `lumen update` | Only if you use the updater |

One command to bundle the important ones:

```sh
tar czf ~/lumen-state-$(date +%F).tgz -C ~ .local/state/lumen .local/state/ricelin Pictures/Wallpapers
```

---

## 8. Quick checklist

**Before you reboot:** nothing to do. Everything is already saved.

**Every so often, or before a big change:**

- [ ] Run the drift check from section 3 (not needed if you're using symlinks)
- [ ] `cd ~/lumen && git status`, then commit and push your changes
- [ ] Back up `~/.local/state/lumen` and your wallpapers

**Before `lumen update`** (only if you're not using symlinks):

- [ ] Commit and push `~/lumen`
- [ ] After the update, run the drift check and restore any reverted code files

**On a new machine:** follow section 6 in order.
