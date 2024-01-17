# shadowtraffic-serverless

Run ShadowTraffic by invoking a URL. Powered by Terraform.

## Up and running

🪧 Sign up for [ShadowTraffic](https://shadowtraffic.io/). You'll receive an email with a set of license keys. Set those as environment variables, prefixed with `TF_VAR` for Terraform:

```
export TF_VAR_LICENSE_ID="XXX"
export TF_VAR_LICENSE_EMAIL="XXX"
export TF_VAR_LICENSE_ORGANIZATION="XXX"
export TF_VAR_LICENSE_EDITION="XXX"
export TF_VAR_LICENSE_EXPIRATION="XXX"
export TF_VAR_LICENSE_SIGNATURE="XXX"
```

📦 Navigate to this repo and apply the changes:

```
terraform apply
```

You'll now have an API Gateway with a public URL. Invoke it to start ShadowTraffic, something like:

```
curl -G -v "https://your-url.on.aws/" --data-urlencode "bootstrapServers=xxx:9092" --data-urlencode "username=xxx" --data-urlencode "password=xxx"
```
