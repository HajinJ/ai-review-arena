# Release Process

Arena uses semantic versioning.

1. Update `pyproject.toml` version.
2. Update `CHANGELOG.md` under `Unreleased` or the release version.
3. Run the full local verification suite.
4. Tag the release:

```bash
git tag v0.2.0
git push origin v0.2.0
```

5. GitHub Actions builds the package and creates a GitHub Release for `v*.*.*` tags.

Publishing to PyPI is intentionally not automatic until project ownership, package name, and credentials are finalized.
