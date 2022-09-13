Keycloak OPA Integration
----

PoC for validating Keycloak configuration with [Open Policy Agent](https://www.openpolicyagent.org/). In this example we use OPA's ["rego" policy definition language](https://www.openpolicyagent.org/docs/latest/policy-language/)
and the configtest tool to validate a client configuration.

The example policy can be found in the [policies](policies) folder.

## Preparation

In this example we use three commands `kcadm`, `conftest` and `opa` to create our environment, as well as testing and developing policies.

Define aliases
```
# Convenience alias for kcadm.sh

mkdir -p $(echo $HOME)/.acme/.keycloak

alias kcadm="docker run --net=host -i --user=1000:1000 --rm -v $(echo $HOME)/.acme/.keycloak:/opt/keycloak/.keycloak:z --entrypoint /opt/keycloak/bin/kcadm.sh quay.io/keycloak/keycloak:19.0.1"

# Convenience alias for conftest
alias conftest="docker run -i --rm -v $(pwd):/project:z openpolicyagent/conftest:v0.34.0"

# Convenience alias for opa 
alias opa="docker run -it --rm -v $(pwd):/project:z openpolicyagent/opa:0.44.0-rootless"
```

## Keycloak Setup

Start Keycloak container
```
KC_SERVER_URL=http://localhost:8080/auth
KC_ADMIN_USER=admin
KC_ADMIN_PASSWORD=admin
KC_REALM=demo

docker run \
  -d \
  --rm \
  --name keycloak-opa \
  -e KEYCLOAK_ADMIN=$KC_ADMIN_USER \
  -e KEYCLOAK_ADMIN_PASSWORD=$KC_ADMIN_PASSWORD \
  -e KC_HTTP_RELATIVE_PATH=auth \
  -p 8080:8080 \
  quay.io/keycloak/keycloak:19.0.1 start-dev
```

Configure kcadm

```
kcadm config credentials --server $KC_SERVER_URL --realm master --user admin --password $KC_ADMIN_PASSWORD
```

### Create Demo Realm

```
kcadm create realms -s realm=$KC_REALM -s enabled=true
```

### Create public OIDC client for a SPA
```
kcadm create clients -r $KC_REALM  -f - << EOF
  {
    "protocol": "openid-connect",
    "clientId": "demo-client",
    "rootUrl": "http://myapp:3000",
    "baseUrl": "/",
    "enabled": true,
    "clientAuthenticatorType": "client-secret",
    "redirectUris": ["/*"],
    "webOrigins": ["+"],
    "standardFlowEnabled": true,
    "implicitFlowEnabled": true,
    "directAccessGrantsEnabled": true,
    "publicClient": true
  }
EOF
```

### Resolve id of generated client
```
KC_CLIENT=demo-client
clientUuid=$(kcadm get clients -r $KC_REALM  --fields 'id,clientId' | jq -c ".[] | select(.clientId == \"$KC_CLIENT\")" | jq -r .id)
```

## Testing our client policies

### Evaluate policies for client
```
kcadm get clients/$clientUuid -r demo | conftest -p policies/main.rego test -
```

Output:
```
$ kcadm get clients/$clientUuid -r demo | conftest -p policies/main.rego test -

FAIL - - main - Clients shall not use Implicit Flow.
FAIL - - main - Clients shall not use ROPC.

2 tests, 0 passed, 0 warnings, 2 failures, 0 exceptions
```

Output as JSON:

```
$ kcadm get clients/$clientUuid -r demo | conftest --policy policies/main.rego test --output json -

[
	{
		"filename": "",
		"namespace": "main",
		"successes": 0,
		"failures": [
			{
				"msg": "Clients shall not use ROPC."
			},
			{
				"msg": "Clients shall not use Implicit Flow."
			}
		]
	}
]
```

### Fix problems

```
kcadm update clients/$clientUuid -r $KC_REALM -s "implicitFlowEnabled=false" -s "directAccessGrantsEnabled=false"
```

### Evaluate policies for client again

Output:
```
$ kcadm get clients/$clientUuid -r demo | conftest -p policies/main.rego test -


2 tests, 2 passed, 0 warnings, 0 failures, 0 exceptions
```

Output as JSON:
```
$ kcadm get clients/$clientUuid -r demo | conftest -p policies/main.rego test -o json -

[
	{
		"filename": "",
		"namespace": "main",
		"successes": 2
	}
]
```

## Debugging

You can use the `opa run` command to test policy expressions in a REPL.

Below is a quick example session.

```
$ opa run
OPA 0.27.0 (commit 43a12ec, built at 2021-03-08T17:17:12Z)

Run 'help' to see a list of commands and check for updates.

> oidc_ropc_client_ids := {"admin-cli"}
Rule 'oidc_ropc_client_ids' defined in package repl. Type 'show' to see rules.
> 
> deny["Public clients should not allow ROPC Grant Flow."] {
    input.protocol = "openid-connect"
    input.publicClient = true
    input.directAccessGrantsEnabled = true
    not oidc_ropc_client_ids[input.clientId]
}
 
Rule 'deny' defined in package repl. Type 'show' to see rules.
> deny["Clients shall not use Implicit Flow."] {
     input.protocol = "openid-connect"
     input.implicitFlowEnabled = true
}
 
Rule 'deny' defined in package repl. Type 'show' to see rules.
> 
> # Should deny for demo-client
> deny with input as {"clientId":"demo-client",
                    "directAccessGrantsEnabled": true, 
                    "publicClient": true, 
                    "protocol": "openid-connect"}

[
  "Public clients should not allow ROPC Grant Flow."
]
> # Should deny for implicit-client
> deny with input as {"clientId":"demo-client",
                     "directAccessGrantsEnabled": true, 
                     "implicitFlowEnabled": true, 
                     "publicClient": true, 
                     "protocol": "openid-connect"}
 
[
  "Clients shall not use Implicit Flow.",
  "Public clients should not allow ROPC Grant Flow."
]
> # Should allow for admin-cli client
> 
> deny with input as {"clientId":"admin-cli",
                    "directAccessGrantsEnabled": true, 
                    "publicClient": true, 
                    "protocol": "openid-connect"}
 
[]
```