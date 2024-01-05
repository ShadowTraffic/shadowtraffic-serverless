# shadowtraffic-serverless

Run ShadowTraffic by invoking a URL. Powered by AWS CDK.

## Up and running

🪧 Sign up for [ShadowTraffic](https://shadowtraffic.io/). You'll receive an email with a set of license keys. Set those as environment variables:

```
export LICENSE_ID="XXX"
export LICENSE_EMAIL="XXX"
export LICENSE_ORGANIZATION="XXX"
export LICENSE_EDITION="XXX"
export LICENSE_EXPIRATION="XXX"
export LICENSE_SIGNATURE="XXX"
```

📦 Navigate to this repo and install the npm packages:

```
npm i
```

🥾 Install [AWS CDK](https://docs.aws.amazon.com/cdk/v2/guide/getting_started.html) and run the bootstrap

```
cdk bootstrap
```

🗃️ Optionally, change the ShadowTraffic configuration in `lambda/lambda.py`

🚀 Deploy it

```
npx cdk deploy
```

You'll now have a Lambda with a public URL. Invoke it to start ShadowTraffic, something like:

```
curl -G -v "https://your-url.on.aws/" --data-urlencode "bootstrapServers=xxx:9092" --data-urlencode "username=xxx" --data-urlencode "password=xxx"
```
