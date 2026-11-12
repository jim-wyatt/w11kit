# Roadmap

What comes next, roughly in order. Nothing here has a date: the project is maintained in spare
time ([Support](README.md#support)). Issues on the project page track each item.

## Before the first release (0.1.0-beta)

- **The signed release tag**, and the repository's security settings on GitHub.

## After the first release

- **The last checks on real hardware**, at the reference PC's next reinstall: turning BitLocker
  on with the kit's own script, and restoring the build inputs from the stick
  ([A release is proven by the VM test](docs/dev/DECISIONS.md#a-release-is-proven-by-the-vm-test)).

- **Windows in another display language.** Today the build refuses one: the answer file names the
  account groups in English. Next: set the groups by their security IDs, and a VM test on a German
  image ([Another language](docs/reference/CONFIGURATION.md#another-language)).
- **More hardware.** Profiles for an Intel desktop, a laptop, and a PC with Wi-Fi only, each with
  a report from a real install ([Contributing a hardware profile](CONTRIBUTING.md#contributing-a-hardware-profile)).
- **Tests for the PowerShell logic** in the public lint workflow (the Python logic has them).
- **One shared helper file** for functions several scripts carry today, and one profile schema
  instead of two.
- **A "this kit is stale" signal**, and a list of every input of a build (an SBOM-style record).
- **Checks of the build PC**: report a PC managed by an employer or school, and Smart App Control's
  state, before a build starts.

Want to help? [CONTRIBUTING.md](CONTRIBUTING.md) says how; a hardware profile from your own PC
helps most.
