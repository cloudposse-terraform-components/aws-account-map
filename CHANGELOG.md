## Breaking changes

### overridable_team_permission_sets_enabled deprecated, default changed

In `modules/roles-to-principals`, the input `overridable_team_permission_sets_enabled`
has been deprecated and the default value has been changed to `false`. This will
cause changes in the Terraform plan, but it is likely that they will be
inconsequential, because this feature never worked with Dynamic Terraform Roles,
even though it was introduced in the same PR.

To enable the intended behavior, a new feature has been added to `aws-team-roles`
and `modules/iam-roles`: `trusted_identity_permission_sets`. This feature 
allows you to explicitly configure permission sets in the `identity` account to
be allowed to assume roles in other accounts, just as you do with `trusted_teams`.
This has the added advantage of being able to configure non-team permissions
sets to be trusted.
