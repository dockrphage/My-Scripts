Here is a **clean, reproducible, step‑by‑step setup** for LocalStack (2026 version) and testing it with a simple: awslocal s3 ls


This guide reflects the **new LocalStack licensing model**, the **Python 3.14 environment**, and  **venv‑based workflow**.

Below is the complete, ordered procedure.

---

01
Install AWS CLI
You need the AWS CLI installed globally so LocalStack tooling can wrap it.

```
sudo apt update && sudo apt install awscli -y
```

Verify installation with aws --version

This installs the system-wide AWS CLI used by awslocal

02
Configure Dummy AWS Credentials
LocalStack ignores real AWS credentials, but AWS CLI requires something.

```
aws configure

AWS Access Key ID: test

AWS Secret Access Key: test

Region: us-east-1

Output: json
```

03
Create and Activate a Python Virtual Environment
LocalStack and awslocal run cleanly inside an isolated Python environment.

```
python3 -m venv ~/my-venv && source ~/my-venv/bin/activate
```
Ensure python3.14-venv is installed

 prompt should show (my-venv)

04
Install LocalStack and awslocal
These packages provide the LocalStack runtime and AWS CLI wrapper.

```
pip install localstack awscli-local localstack-client
```

Verify awslocal with 
```
awslocal --version
```

This installs binaries inside ~/my-venv/bin

05
Set  LocalStack Auth Token
Required
LocalStack 2026 requires a free account and auth token to run.

Create a free account at app.localstack.cloud

Copy  token from Settings → Auth Tokens

Export it globally:
```
echo 'export LOCALSTACK_AUTH_TOKEN="<your-token>"' >> ~/.bashrc
```

Reload shell: 
```
source ~/.bashrc
```

06
Start LocalStack
Runs LocalStack in Docker mode and exposes AWS APIs on port 4566.

```
localstack start
```

You should see logs ending with Ready.

Keep this terminal open (foreground mode)

07
Test S3 Connectivity with awslocal
Success Check
Confirms LocalStack is running and reachable.

```
awslocal s3 ls
```

Should return empty output (no buckets yet)

Create a bucket: 
```
awslocal s3 mb s3://test-bucket
```

List again: ```
awslocal s3 ls
```


---

# ⭐ Summary

After completing these steps:

- LocalStack is running in Docker mode  
- awslocal is available inside  venv  
- AWS CLI is configured with dummy credentials  
- You can run:

```
awslocal s3 ls
awslocal s3 mb s3://my-bucket
awslocal s3 cp file.txt s3://my-bucket/
```

Everything is now reproducible and stable.

---
