# Running Northbridge on a single EC2 instance

This is a **quick/demo deployment**, not the production architecture — for that, use
[`infra/terraform`](../../infra/terraform) (ECS Fargate, RDS Multi-AZ, ALB, CloudFront),
which is what [`docs/architecture.md`](../../docs/architecture.md) describes and what a
real launch should run on. This EC2 path is the fastest way to get the whole system
reachable from a public URL for a demo/test, using the same Docker images and
docker-compose stack you've already been running locally, with **nginx** in front
playing the role CloudFront + ALB play in the real deployment.

It still uses LocalStack for S3/SQS/SNS (not real AWS services) — swapping that for real
AWS resources is exactly the `infra/terraform` path, not this one.

## 1. Launch the EC2 instance

In the AWS Console (EC2 → Launch Instance):
- AMI: **Ubuntu Server 22.04 LTS**
- Instance type: **t3.medium** or larger (Postgres + LocalStack + 6 .NET services need
  more than a t3.micro/small comfortably — 4GB+ RAM)
- Key pair: create/select one you have the `.pem` for
- Network settings → Security group: create a new one with:
  - SSH (22) — source: **My IP** (not `0.0.0.0/0`)
  - HTTP (80) — source: `0.0.0.0/0` (this is the only port the public needs)
  - Do **not** open 5001-5003, 5432, or 4566 — those stay internal to the instance
- Storage: 20GB is plenty

Launch it, note its **public IPv4 address / public DNS**.

## 2. Connect and install prerequisites

```bash
ssh -i /path/to/your-key.pem ubuntu@<EC2_PUBLIC_IP>
```

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg nginx
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker $USER
newgrp docker

# Node 20+ (to build the Angular apps) and .NET 8 SDK are only needed if you build ON the
# instance; the steps below build the .NET images via Docker (no host .NET needed) and
# build the Angular apps here directly, so install Node:
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
```

## 3. Get the code onto the instance

Simplest if you push this repo to GitHub (private repo is fine) and clone it here:
```bash
git clone <your-repo-url> project-simulation
cd project-simulation
```

If you don't have it in git yet, `scp` the folder from Windows instead (run this from
your Windows/WSL side, not the EC2):
```bash
scp -i /path/to/your-key.pem -r "/mnt/c/Users/jyothiswaroop.marri/OneDrive - Paltech Consulting Private Limited/Documents/project simulation" ubuntu@<EC2_PUBLIC_IP>:~/project-simulation
```

## 4. Start the backend stack

From the project root on the EC2 instance:
```bash
docker compose -f docker-compose.yml -f deploy/ec2/docker-compose.override.yml up -d --build
```

The override file rebinds Postgres/LocalStack/the 3 APIs to `127.0.0.1` — reachable from
nginx on the same box, not from the internet. Confirm everything's healthy:
```bash
docker compose ps
curl http://127.0.0.1:5001/health
curl http://127.0.0.1:5002/health
curl http://127.0.0.1:5003/health
```

## 5. Build both Angular apps for production

```bash
cd frontend/applicant-portal
npm install
npx ng build --configuration ec2
cd ../reviewer-console
npm install
npx ng build --configuration ec2 --base-href /reviewer/
cd ../..
```

(The `ec2` build configuration swaps in `environment.ec2.ts`, which points at relative
paths like `/applications-api/api` — that's what nginx's `deploy/ec2/nginx.conf` proxies.
Plain `--configuration production` instead builds against `environment.prod.ts`, which
targets the real ALB/CloudFront deployment's domain — don't use it here.)

## 6. Deploy the static files and nginx config

```bash
sudo mkdir -p /var/www/applicant-portal /var/www/reviewer-console
sudo cp -r frontend/applicant-portal/dist/applicant-portal/browser/* /var/www/applicant-portal/
sudo cp -r frontend/reviewer-console/dist/reviewer-console/browser/* /var/www/reviewer-console/

sudo cp deploy/ec2/nginx.conf /etc/nginx/sites-available/northbridge
sudo ln -sf /etc/nginx/sites-available/northbridge /etc/nginx/sites-enabled/northbridge
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t   # validates the config
sudo systemctl reload nginx
```

## 7. Test it

Open `http://<EC2_PUBLIC_IP>/` for the Applicant Portal, and
`http://<EC2_PUBLIC_IP>/reviewer/` for the Reviewer Console. Run the apply → upload →
(manually trigger the credit-scoring job, same as local) → review/approve flow exactly
as you did locally.

To trigger a fire-and-forget job manually (same as local):
```bash
docker compose -f docker-compose.yml -f deploy/ec2/docker-compose.override.yml run --rm \
  -e JOB_ID=<jobId> -e LOAN_APPLICATION_ID=<loanApplicationId> credit-scoring-job
```

## Redeploying after a code change

```bash
git pull   # or re-scp
docker compose -f docker-compose.yml -f deploy/ec2/docker-compose.override.yml up -d --build
cd frontend/applicant-portal && npx ng build --configuration ec2 && cd ../..
sudo cp -r frontend/applicant-portal/dist/applicant-portal/browser/* /var/www/applicant-portal/
cd frontend/reviewer-console && npx ng build --configuration ec2 --base-href /reviewer/ && cd ../..
sudo cp -r frontend/reviewer-console/dist/reviewer-console/browser/* /var/www/reviewer-console/
```

## Adding HTTPS (optional but recommended for anything beyond a quick test)

If you point a real domain at the EC2's IP, Certbot gets you a free cert in one command:
```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d your-domain.com
```

## Why this isn't "the AWS architecture"

This puts everything on one box with no redundancy, no auto-scaling, no managed Postgres
backups/failover, and LocalStack standing in for S3/SQS/SNS instead of the real thing —
fine for a demo, not for anything real users depend on. `infra/terraform` is the actual
answer to "run this in AWS properly": RDS Multi-AZ, ECS Fargate services behind an ALB,
real S3/SQS/SNS/EventBridge, CloudFront for the SPAs. That path needs a domain + ACM
certificate and will cost meaningfully more than one EC2 instance (roughly $150-300+/mo
just for the NAT Gateway, ALB, and Multi-AZ RDS, before compute) — worth doing once you're
past the demo stage, not before.
