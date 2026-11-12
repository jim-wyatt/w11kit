## What and why

<!-- What this changes and why. Link the issue if there is one. -->

## Tests run

<!-- Which of these you ran, and the result. See docs/dev/TESTING.md, "Reporting a test run". -->

- [ ] Syntax gate → `SYNTAX OK` (docs/dev/TESTING.md, "Syntax gate")
- [ ] Build (`Run-Build.cmd -TestBuild`): the image read-back passed — profile: <!-- id -->
- [ ] VM test: `Run-VmTest.cmd` (Hyper-V) → `RESULT:` <!-- PASS / FAIL; paste the summary's UNEXPECTED rows, if any -->
- [ ] Real PC: validator report <!-- FAIL / WARN counts; attach with personal data removed -->

## Checklist

- [ ] Docs updated in this PR for every changed setting, decision, check, default, option or message
      (CONTRIBUTING.md, "Docs change with the code"), and `CHANGELOG.md`
- [ ] Security baseline: nothing weakened, or the exception is documented in
      `docs/reference/SECURITY-BASELINE.md` and checked by the validator
- [ ] Profile changes: `scripts/KitProfile.ps1`, the profile check and `docs/reference/PROFILES.md` agree
- [ ] No secrets or keys: no passwords (`accounts.txt`, test passwords), product keys, tokens, private keys,
      personal data (computer names, MACs, user names, serials)
- [ ] No drivers, firmware or Microsoft files added (a baseline update changes only its pin in
      `config/baselines/<id>/source.json`)
- [ ] Commits are signed off (`git commit -s`; CONTRIBUTING.md, "Licence of contributions")
