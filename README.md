# System setup playbook

A small Ansible playbook I run after installing Fedora Workstation. I got tired of repeating the
same stuff every time I reinstalled, so I wrote it down. It throws out the apps
I never open, updates everything, installs my stuff and swaps Podman for Docker.

Plain Fedora Workstation only, x86_64. Silverblue and the other atomic versions won't work.

## Running it

Run it as yourself, not as root. Look at what it wants to do first.

```bash
./bootstrap.sh --check
```

Check mode changes nothing. If the plan looks right:

```bash
./bootstrap.sh
```

It installs Ansible if you don't have it, then asks for your sudo password.

Pick your own list if you want. It replaces the defaults, it doesn't add to them.

```bash
./bootstrap.sh --profiles web_dev
./bootstrap.sh --profiles desktop_dev_rust,web_dev
./bootstrap.sh --profiles all
```

## What it does

The work is split into profiles. Six run by default, four you have to ask for.

| Profile | Default? | What it does |
| --- | --- | --- |
| `snapshots` | yes | Snapper snapshots, so you can roll back. Btrfs only. |
| `cleanup` | yes | Uninstalls the GNOME apps, printer and virtualization packages I never touch. |
| `system` | yes | Updates Fedora, adds Flathub and RPM Fusion, gets video codecs working. |
| `desktop` | yes | My apps, GNOME extensions, Papirus icons, VS Code extensions. |
| `zsh_ricing` | yes | Zsh, a Nerd Font, and Ghostty as the terminal. |
| `containers` | yes | Rips out Podman and puts Docker in. |
| `remote` | no | Lets you SSH into this box: key-only, tight firewall, Fail2ban. |
| `dns` | no | Points systemd-resolved at your own DNS-over-TLS endpoints. |
| `desktop_dev_rust` | no | Rust, Cargo, Clippy, GCC, Make. |
| `web_dev` | no | Bun and Vite+. |

## Changing what gets installed

My picks are not your picks, so edit the lists before you run anything.

- [group_vars/all.yml](group_vars/all.yml) holds the default profiles and the Flatpak apps.
- [roles/cleanup/defaults/main.yml](roles/cleanup/defaults/main.yml) is the list of what gets
  uninstalled. Read this one properly.
- Every other profile keeps its list in its own `defaults/main.yml`.

Cleanup only removes packages it can name. It never goes hunting for extras.

## When it skips things

Fedora releases move faster than the people packaging Docker and some GNOME extensions. The run
tells you what it skipped and carries on. Try again in a few weeks.

## If something breaks

On Btrfs, `snapshots` takes a snapshot before anything else runs. Pick "Fedora Linux snapshots" in
the GRUB menu at boot, then `snapper status` to see what changed and `snapper undochange` to put
files back.

The boot menu entries need a third-party repo. Don't want it? Set
`snapshots_enable_grub_menu: false` and you keep snapper without the menu.

## The remote profile

Off by default. Skip it and nothing is listening for SSH at all, which is the safer way round.

SSH goes key-only, root can't log in, and nobody but your user can. Put your public key in
`~/.ssh/authorized_keys` first, and keep your current session open while you test a new one. The
run stops if that file is missing, so it can't lock you out by accident.

It also closes the `1025-65535` range Fedora leaves open. But KDE Connect, Chromecast and
Syncthing stop finding devices until you add their ports to `remote_firewall_enabled_services`.
Fail2ban bans an IP for an hour after 2 bad logins.

## The dns profile

Skip this unless you use a DNS filter (Pi-hole, Cloudflare Gateway). 
Your endpoints are the secret, so they go in `inventory/localhost.vault.yml`.

```yaml
dns_endpoints:
  - 172.64.36.1#YOUR_ID.cloudflare-gateway.com
  - 2a06:98c0:3600::YOUR_ID#YOUR_ID.cloudflare-gateway.com
```

Encrypt it with `ansible-vault encrypt inventory/localhost.vault.yml`, then run `./bootstrap.sh --profiles dns`. 
To undo it later, `./bootstrap.sh --profiles dns -e dns_enable=false`.

## Handy extra

`./tools/audit-current.sh` prints everything installed on the machine right now. It's how I see
what to add to the cleanup list.

```bash
./tools/audit-current.sh > /tmp/report.yml
```

Worth doing once per Fedora release and diffing against `roles/cleanup/defaults/main.yml`. 

When Fedora renames a package, cleanup quietly stops removing it.

## One warning

Try it on a VM or a fresh install before you point it at a machine you care about, and actually read
the `--check` output. The removals especially. This is my setup script, not a product.
