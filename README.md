# Omarchy gaming setup

Private coordination repository for making this Omarchy gaming workstation
reproducible. The repository owns the setup contract, diagnostics, and central
issue backlog. Component-specific changes may also land in:

- [delta-cw360lcd-linux-driver](https://github.com/ErickWendel/delta-cw360lcd-linux-driver)
- [ps5-steam-big-picture](https://github.com/ErickWendel/ps5-steam-big-picture)

Proprietary Delta binaries, ROMs, Steam userdata, credentials, generated logs,
and other private payloads must never be committed, even though this repository
is private.

## Current state

The repository is initially a tracked implementation backlog. `setup.sh`
defines the eventual public command line and already provides non-mutating
preflight checks; component installation is completed through the linked
issues.

```bash
cp config/machine.example.env config/machine.env
./setup.sh --check
./setup.sh --dry-run
./setup.sh --delta-archive /path/to/private-delta-runtime.tar.gz --dry-run
```

The expected final workflow is one idempotent `./setup.sh` invocation on a
fresh installation. Files are backed up before replacement, filesystem repair
is never automatic, and missing optional hardware only blocks its own module.

## Work order

Issues 2–5 and the G29 investigation are independent work streams. Emulator
integration follows the storage investigation, PCSX2 follows emulator
integration, and the final issue is the end-to-end gate. The exact issue bodies are retained under
[`planning/issues`](planning/issues) so the backlog is versioned with the code.

The storage work includes a separately confirmed, destructive reformat only
after hardware diagnostics and a checksum-verified copy to another local disk.
Normal setup and doctor runs never format or repair a filesystem automatically.
