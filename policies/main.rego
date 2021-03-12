package main
# Some OIDC specific validation rules for Keycloak clients.

# Set of client_id's that are allowed to use ROPC
oidc_ropc_client_ids := {"admin-cli"}

deny[msg] {
    msg := "Clients shall not use ROPC."
    input.protocol = "openid-connect"
    input.directAccessGrantsEnabled = true
    not oidc_ropc_client_ids[input.clientId]
}

deny[msg] {
    msg := "Clients shall not use Implicit Flow."
    input.protocol = "openid-connect"
    input.implicitFlowEnabled = true
}