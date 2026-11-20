# Receipt bucket setup

How to give maribelanja's staging stack its S3 receipt-photo bucket and the
credentials to use it. Covers the AWS resources, the IAM policy, the env vars
on the server, and how to verify it end to end.

Status: **done 2026-11-19** — bucket created, IAM user in use, env on the
server, admin container live at `admin.maribelanja.darmawan.be`. See
[What was actually done](#what-was-actually-done) for the specifics and the
two deploy traps worth remembering.

## What needs it

The `feat/receipt-photo-storage` work (maribelanja `f7debe1`) saves receipt
photos to S3 and serves them back through short-lived presigned URLs. Without
a bucket the app quietly falls back to the container's disk under `tmp/`,
which every `make maribelanja` rebuild wipes. The app still boots either way,
so a missing bucket shows up as photos that vanish after a deploy, not as an
error.

## Facts about the staging box

These drive the decisions below, so they are recorded here rather than
rediscovered each time.

| Fact | Value | Why it matters |
| --- | --- | --- |
| AWS account | `533267286678` | The bucket has to live in this account |
| Region | `ap-southeast-1` | Bucket region must match, or requests get redirected/signed wrong |
| Instance id | `i-0b47f5e5fb1cb1f15` | A policy can be scoped to it later |
| Instance profile | **none** | There is no instance role to attach anything to |
| Access from the Mac | **none yet** | The only local AWS identity is a different account (`975050110239`) |

The missing instance profile is the reason this guide uses an access key
instead of the instance role. An IAM role is the better answer whenever it
becomes available; see [Upgrade path](#upgrade-path-attach-an-instance-role).

## AWS resources

### 1. Bucket

Name it after the environment so it never collides with the prod bucket
(`maribelanja-receipts-<account-id>`, created by the app's own
`deploy/deploy.sh`):

```
maribelanja-receipts-staging
```

```bash
aws s3api create-bucket \
  --bucket maribelanja-receipts-staging \
  --region ap-southeast-1 \
  --create-bucket-configuration LocationConstraint=ap-southeast-1
```

Drop `--create-bucket-configuration` only for `us-east-1`, which rejects it.

Block all public access. The app never serves objects directly; every view
goes through the authorization check and a presigned URL.

```bash
aws s3api put-public-access-block \
  --bucket maribelanja-receipts-staging \
  --public-access-block-configuration \
  'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
```

Leave the default SSE-S3 encryption. Add **no lifecycle rule** and no versioning
expiry: the app treats saved photos as permanent, and the only cleanup it does
is its own staging sweep, which touches local disk and never S3.

Object keys are date-partitioned, so browsing or bulk-exporting by period
stays cheap:

```
receipts/<yyyy>/<mm>/<dd>/<scan_id>.<ext>
```

### 2. IAM policy and user

The app calls exactly three S3 operations (`lib/maribelanja/receipt_images/s3.ex`):
`PutObject` on save, `GetObject` for the admin preview, and a presigned GET
for the customer's own photo. A presigned GET is still a `GetObject` call,
so two permissions cover everything. No `ListBucket`, no `DeleteObject`; the
app never lists or deletes stored photos.

```bash
aws iam create-user --user-name maribelanja-staging-receipts

cat > /tmp/receipts-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject"],
      "Resource": "arn:aws:s3:::maribelanja-receipts-staging/*"
    }
  ]
}
EOF

aws iam put-user-policy \
  --user-name maribelanja-staging-receipts \
  --policy-name receipts-rw \
  --policy-document file:///tmp/receipts-policy.json
```

Note the resource is `bucket/*`, not the bucket itself. Scoping to the bucket
ARN would grant nothing the app uses.

Generate the key. It is shown once, so write it somewhere safe immediately.

```bash
aws iam create-access-key --user-name maribelanja-staging-receipts > /tmp/keyfile.json
```

### 3. Env vars on the server

`/opt/maribelanja/.env` is never synced by rsync (see the "`.env` never
syncs" note in `staging/README.md`), so these are appended by hand. Pipe the
key straight over SSH so it never lands in shell history:

```bash
awk -F'"' '/AccessKeyId/{id=$4} /SecretAccessKey/{s=$4}
  END{print "AWS_ACCESS_KEY_ID="id"\nAWS_SECRET_ACCESS_KEY="s}' /tmp/keyfile.json \
  | ssh -i .ssh/darmawan-be-staging.pem ubuntu@47.131.158.206 \
    'cat >> /opt/maribelanja/.env && chmod 600 /opt/maribelanja/.env'
```

Then add the two plain values. Do this on the server, or in the same pipe:

```bash
RECEIPT_IMAGE_BUCKET=maribelanja-receipts-staging
RECEIPT_IMAGE_REGION=ap-southeast-1
```

Finally remove `/tmp/keyfile.json`.

`RECEIPT_IMAGE_REGION` has no default. If `RECEIPT_IMAGE_BUCKET` is set and
the region is empty, `config/runtime.exs` raises at boot and the container
restart-loops. This is deliberate: a wrong region would otherwise fail at the
first upload instead of at deploy.

### 4. Compose wiring

Compose only passes into a container what its `environment:` block lists, so
both the S3 vars and the admin vars need adding to
`staging/apps/maribelanja/docker-compose.staging.yml`. The `.env.example`
documents the names; the compose file decides whether they reach the app.

## Verifying it works

Confirm the app picked up the S3 store rather than the disk fallback:

```bash
ssh -i .ssh/darmawan-be-staging.pem ubuntu@47.131.158.206 \
  'docker exec maribelanja-app env | grep -E "RECEIPT_IMAGE|AWS_"'
```

The values must be present. Then, inside the container, check the resolved store:

```bash
docker exec maribelanja-app /app/bin/maribelanja eval \
  'case Application.get_env(:maribelanja, Maribelanja.ReceiptImages, :no_config) do
     :no_config -> IO.puts("no_config (pre-S3 build, deploy first)")
     cfg -> IO.inspect(cfg[:store])
   end'
```

`Maribelanja.ReceiptImages.S3` means S3 is active. `Maribelanja.ReceiptImages.Local`
means the bucket var did not reach the container. `no_config (pre-S3 build)`
means the container still runs code from before the receipt-photo work: on
that build the whole `ReceiptImages` module is absent, so deploy first.

End to end: save a receipt with a photo in the customer app, then

```bash
aws s3 ls s3://maribelanja-receipts-staging/receipts/ --recursive | tail
```

A fresh object under today's date confirms upload. Opening the photo in the
app confirms the presigned redirect.

Common failure: uploads 403 with `AccessDenied` even though the key works.
Check the policy resource ends in `/*`, and that the user policy (not the
bucket policy) is the one carrying the grant.

## Upgrade path: attach an instance role

The access key works, but a key on disk is something that can leak and needs
rotating. The cleaner setup is an instance role with the same policy:

1. Create a role trusting `ec2.amazonaws.com`, attach the `receipts-rw`
   policy, create an instance profile, add the role to it.
2. Associate the profile with `i-0b47f5e5fb1cb1f15` (requires a stop/start,
   not a reboot).
3. `aws iam delete-access-key`, then remove `AWS_ACCESS_KEY_ID` and
   `AWS_SECRET_ACCESS_KEY` from `/opt/maribelanja/.env`.

The app needs no code change: ex_aws resolves credentials as env vars, then
pod identity, then instance role, so it picks the role up once the env vars
are gone. This is how the prod deploy works (`maribelanja-server` role in the
app's `deploy/deploy.sh`), so moving staging to a role brings it in line.

## What was actually done

2026-11-19, against account `533267286678` with the `jeffdarmawan` CLI
profile:

- Bucket `maribelanja-receipts-staging` created in `ap-southeast-1`, all four
  public-access blocks on, default SSE-S3. Name was checked free first;
  bucket names are global.
- IAM user `maribelanja-staging-receipts` with inline policy `receipts-rw`
  (`s3:PutObject`, `s3:GetObject` on `maribelanja-receipts-staging/*`) and one
  active access key.
- Key proven before deploy: `PutObject` and `GetObject` succeed, and
  `DeleteObject` is correctly denied (it is not in the policy).
- The four values appended to `/opt/maribelanja/.env` on the server. A
  timestamped backup `.env.bak-*` sits next to it.
- Compose now requires both S3 vars and the key pair, so an empty value fails
  the deploy instead of silently falling back to disk.
- Admin container added and live. First admin account:
  `jeff@darmawan.be`.

Two traps hit during this, both fixed:

**`make caddy` deleted the admin basic-auth hash.** The caddy rsync uses
`--delete`, and `CADDY_EXCLUDES` only listed the naikbusaja secrets. Adding
`.admin-bcrypt` and `admin-auth-credentials.txt` to the exclude list fixed it.
Any new server-only file under `/opt/caddy` must be added there too.

**Both release overlays exec'd the wrong binary.** `rel/overlays/bin/migrate`
and `server` derived the release name from the parent directory
(`basename $(dirname $PWD)`). That is only right when the release root is
named after the release, but the Dockerfile copies them into `/app` and
`/app-admin`, so they computed `app` and `app-admin` and exited 127. Both now
find the boot script by name instead. This broke `migrate` first and would
have broken every container start right after. Fixed upstream in PR #9.

Note the admin healthcheck: the image's `HEALTHCHECK` used to curl `$PORT`,
which the admin release never binds, so the container reported unhealthy
while actually serving fine. Fixed upstream in `docker/healthcheck.sh` (PR #9),
which now picks the port from `APP_ROLE`. The compose override that worked
around it has been removed.

## Reusing this for prod

Prod does not follow this guide. Its own `deploy/deploy.sh` creates
`maribelanja-receipts-$ACCOUNT_ID`, applies the same public-access-block,
adds an `s3-receipt-images` policy to the `maribelanja-server` role, and
writes `RECEIPT_IMAGE_BUCKET` / `RECEIPT_IMAGE_REGION` into its env file
automatically. The differences here come purely from staging having no
instance role and no deploy script of its own.
