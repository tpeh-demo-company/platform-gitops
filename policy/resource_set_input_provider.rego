package main

import future.keywords.if
import future.keywords.contains

# ResourceSetInputProvider must pin an exact semver version.
# Floating versions make upgrades unpredictable across environments.

deny contains msg if {
  input.kind == "ResourceSetInputProvider"
  version := input.spec.defaultValues.version
  not regex.match(`^\d+\.\d+\.\d+$`, version)
  msg := sprintf(
    "ResourceSetInputProvider %s version '%s' must be exact semver (e.g. 1.2.3)",
    [input.metadata.name, version],
  )
}

# ResourceSetInputProvider must have an app label.
# The ResourceSet selects its input provider via matchLabels app: <name>.
# A missing label silently orphans the ResourceSet (no inputs → no HelmReleases deployed).

deny contains msg if {
  input.kind == "ResourceSetInputProvider"
  not input.metadata.labels.app
  msg := sprintf(
    "ResourceSetInputProvider %s is missing the required 'app' label",
    [input.metadata.name],
  )
}
