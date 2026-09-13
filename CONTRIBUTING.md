Thanks for contributing to Demoland!

- **Creating a new base environment?** Fork this project and [create a pull
  request](https://github.com/carlosonunez-redhat/demoland/pulls/new) to merge your fork.

- **Fixing a bug with a base environment?** [Create an issue
  first!](https://github.com/carlosonunez-redhat/demoland/issues/new)

- All encrypted cloud credentials in your [config.yaml](./config.yaml) will be replaced
  with mine post-merge.

  Please make sure that you add a brief description of IAM permissions I'll need
  to deploy your environment during testing in the pull request description.

- This project **only** uses [sops](https://github.com/getsops/sops) for
  configuration and project secrets and [Just](https://github.com/casey/just)
  for build/deployment automation. **ANYTHING ELSE** (dotenvs, raw GPG files,
  etc) will not be accepted!

- Make sure that your run the [gitleaks secrets check](./githooks/commit-msg)
  supplied within this repository before ALL commits. (It takes less than 10
  seconds to run.)

  Any pull requests that do not pass this check will be closed and requested for
  deletion!

## Special notes for scripts and the `Justfile`

- These are the only applications that I require users to have installed to do
  anything with demoland:
  - `jq`
  - `yq`
  - `sops`
  - Docker or Podman

  ANYTHING ELSE needs to run within a container.

- All container images must be version tagged. DO NOT use `latest`. If `latest`
  is not availble, use the images SHA256 digest in its place.
