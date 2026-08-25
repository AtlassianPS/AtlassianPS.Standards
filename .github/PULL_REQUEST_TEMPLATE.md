### Description

<!-- Describe the change and why it is needed. -->

### Release intent

<!-- Apply exactly one release label: release:none, release:patch, release:minor, or release:major. -->
<!-- A releasing PR also needs one changelog:* label or one .changelog/<pr>.<impact>.<type>.md fragment. -->

- [ ] This change needs no independent package release (`release:none`).
- [ ] This change needs a patch, minor, or major release and includes release-note intent.

### Validation

- [ ] I ran the relevant focused tests.
- [ ] I ran `Invoke-Build -Task Lint, Build, Test`.
- [ ] I updated the release blueprint and downstream guidance when shared behavior changed.
