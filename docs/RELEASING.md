# Releasing

GitHub is the development home. Branch from `main`, submit a pull request,
and merge after the required build, test and privacy checks pass. Keep changes
under `## Unreleased` in the changelog until preparing a release.

## Release checklist

1. Confirm the release commit is on `main`, with all required checks green.
2. Run the documented build and tests from a fresh clone. Test desktop changes
   in a disposable user session or virtual machine; test database changes against
   a disposable database. Never attach production state to CI.
3. Review changed screenshots and every frame of animations. Use a demo account,
   invented notes and a synthetic media library. Strip metadata, window titles,
   credentials, personal paths and identifying network details.
4. Update the product version and changelog together. Package metadata must agree
   with the application version. Submit those changes as a pull request.
5. Create an immutable semantic-version tag on the checked release commit:

   ```bash
   git fetch origin main --tags
   git switch main
   git merge --ff-only origin/main
   git tag vX.Y.Z
   git push origin refs/tags/vX.Y.Z
   ```

6. The tag workflow re-runs the public CI and privacy gates, proves the tag
   belongs to main, and publishes a GitHub Release with checksummed source
   and product artifacts. Desktop package candidates are built from the tag;
   container products publish versioned GHCR images and record their digests.
   Never upload local configuration, data volumes, debug logs or a private archive.
7. Verify download checksums and installation on a clean supported system.
   Update the website's guides and media when visible behavior changes.

## Rebuild the window-glass packages

Each desktop release from 1.5.0 includes the all-architecture metapackage, the
amd64 window-glass component, the tagged project source, and the original
Ubuntu Mutter and Blur my Shell sources. On an amd64 Ubuntu 26.04 build host
with the Debian build dependencies installed, verify and restore the complete
release before building.

```sh
sha256sum --check SHA256SUMS.txt
tar -xzf source.tar.gz
cd source
python3 -I desktop/window-glass/source-inputs.py unpack ../upstream-source.tar.gz
scripts/build.sh ../dist
```

The source lock records the upstream revision and digest for each input. The
build uses the Debian changelog timestamp and runs offline after restoring those inputs. The pull request workflow
also exercises upgrading an existing desktop and both paths for loading the
installed extension in a clean Ubuntu guest.

## Deployment and recovery

Application source and public build checks live here. Signing keys, registry
credentials, production configuration and deployment approvals live in the
operator's secret manager and private deployment system. CI artifacts are
candidates until their release and installation checks pass.

Record the running version and image digest before an upgrade. Back up state,
rehearse its restore, and preserve the previous artifact. Database migrations
can make a binary-only downgrade unsafe; recover the matching backup when a
migration is not reversible. Never mutate an existing release tag.
