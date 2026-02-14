#!/usr/bin/env bash
# Runs tests before deploying an environment with 'provision.sh'.
#
# This adds some functions for working with cloud providers, the config file, and
# other useful things.
source "../../include/helpers/aws.sh"
source "../../include/helpers/config.sh"
source "../../include/helpers/data.sh"
source "../../include/helpers/errors.sh"
source "../../include/helpers/logging.sh"
source "../../include/helpers/install_config.sh"
source "../../include/helpers/yaml.sh"

# If this environment has includes of its own, use the ./include environment
# variable, like shown in the comment below.
#
# source "./include/foo.sh"

