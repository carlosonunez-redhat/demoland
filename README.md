# Carlos's Demo Environments

Various demo environments I've created for things, mostly to help me learn
product internals.

## Demolands

- [OCP](./ocp)

## Deployment

1. Install `just`: `brew install just`
2. `just deploy $ENVIRONMENT_NAME`

## Creating new environments

An "environment" defines infrastructure for a product that will be installed.

To create a new environment, run `just create_new_environment
$ENVIRONMENT_NAME`. This will add the environment to the root-level
config and create the directory structure shown below:


```
$ENVIRONMENT_NAME
├── Containerfile   # can be changed in config
├── destroy.sh      # steps to destroy an environment
├── preflight.sh    # prerequisites before provisioning an environment
├── provision.sh    # provisions an environment
└── ...other files
```

## Deleting environments

Run `just delete_environment $ENVIRONMENT_NAME` to delete it.

You'll be asked to type something long to confirm this.

## Roadmap

- [ ] AAP Demoland
- [ ] OpenShift AI Demoland (needs refining)
- [ ] Developer Hub Demoland (needs refining)
