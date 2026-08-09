## What this changes

<!-- What does this PR do, and why? -->

## Which part(s) of the repo

<!-- Desktop (setup.sh) / Android (android/) / Cloud (cloud/) / Build loop
     (agent/build-loop.sh) / Docs / CI -- delete what doesn't apply -->

## Testing done

<!-- Be specific about what you actually ran, e.g. "ran termux-setup.sh on
     a Pixel 9a", "brought the Docker stack up locally and hit all three
     ports", "shellcheck only, couldn't test against a real device/API" --
     say what you couldn't verify too, don't leave it implied. -->

## Checklist

- [ ] `shellcheck --severity=warning` passes on any shell scripts touched
- [ ] README/comments updated if usage or behavior changed
- [ ] If this touches `agent/build-loop.sh`'s autonomy (auto-commit,
      confirmation gates, unattended iteration), the PR description
      explains why
