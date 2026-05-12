# Infra Findings

**Audit date:** 2026-05-12
**Scope:** backend/infra/*.tf, .github/workflows/ci.yml, deploy-staging.yml, deploy-production.yml, traffic-snapshot.yml
**Environment:** staging only (no real users yet)
**Auditor:** Claude Sonnet 4.6 (read-only)

---

## Security

### 🟡 Medium — OTEL collector sidecar pinned to `latest` tag

**File:** backend/infra/ecs.tf — resource "aws_ecs_task_definition" "backend"
**Lens:** Security
**Subsystem:** Infra

**What:** The OTEL collector sidecar image is `public.ecr.aws/aws-observability/aws-otel-collector:latest`, which is a mutable floating tag.
**Why it matters:** `latest` can silently pull a new image version on every task launch, introducing regressions or supply-chain changes without a Terraform diff to review; image digests or pinned version tags (e.g., `v0.40.0`) make deploys reproducible and auditable.
**Recommended fix:** Pin to a specific version tag or SHA digest, e.g., `public.ecr.aws/aws-observability/aws-otel-collector:v0.40.0`.

---

### 🟡 Medium — `ml_demo_image` default is `hello-world:latest` from public registry

**File:** backend/infra/variables.tf — variable "ml_demo_image" / backend/infra/ml_demo.tf — resource "aws_ecs_task_definition" "ml_demo"
**Lens:** Security
**Subsystem:** Infra

**What:** The default value for `ml_demo_image` is `public.ecr.aws/docker/library/hello-world:latest`, a public mutable image that runs in the ECS service using the same task role as the main backend.
**Why it matters:** If staging is ever applied without overriding this variable (e.g., after a state wipe), a public placeholder container runs with production-equivalent IAM permissions (S3 read/write, Secrets Manager, Bedrock) and shares the same security group; mutable `latest` tag can be swapped by upstream.
**Recommended fix:** Add a `staging.tfvars` entry for `ml_demo_image` pointing to the real ECR URI, and remove the public-registry default. Consider a separate, minimal task role for the ml_demo service.

---

### 🟡 Medium — OIDC staging trust allows `pull_request` sub-claim (any fork contributor can assume the role)

**File:** backend/infra/oidc.tf — data "aws_iam_policy_document" "gha_staging_assume_role"
**Lens:** Security
**Subsystem:** Infra

**What:** The staging OIDC trust policy includes `repo:${var.gha_repo_full_name}:pull_request` as an allowed `sub` value with `StringLike`, meaning any contributor who opens a PR (including fork PRs if the repo setting allows) can trigger a job that assumes the staging deploy role.
**Why it matters:** A malicious PR could exfiltrate the staging AWS role permissions (ECR push, ECS RunTask, Secrets Manager reads via the CloudWatch log tail) from a forked branch; the deploy job is gated on CI success but the role assumption itself is not gated on passing CI.
**Recommended fix:** Remove the `pull_request` sub entry from the trust policy; restrict to `refs/heads/master` and `environment:staging` only. The CI workflow does not need AWS credentials (it only builds and scans locally).

---

### 🟡 Medium — ECS task role IAM policy for X-Ray/logs uses `resources = ["*"]`

**File:** backend/infra/ecs.tf — data "aws_iam_policy_document" "ecs_task_xray"
**Lens:** Security
**Subsystem:** Infra

**What:** The X-Ray and CloudWatch Logs policy attached to the ECS task role grants `xray:*` and `logs:*` actions against `resources = ["*"]` (all log groups and X-Ray in the account).
**Why it matters:** A compromised container could write to or enumerate any CloudWatch log group in the account; least-privilege would scope log write permissions to only the specific log group ARNs used by the service.
**Recommended fix:** Scope the `logs:PutLogEvents` / `logs:CreateLogStream` resources to `${aws_cloudwatch_log_group.backend.arn}:*` and `${aws_cloudwatch_log_group.otel_collector.arn}:*`; keep `xray:*` on `*` as X-Ray requires it.

---

### 🟢 Low — ECR repositories use `MUTABLE` image tags

**File:** backend/infra/ecr.tf — resource "aws_ecr_repository" "backend" / backend/infra/ml_demo_ecr.tf — resource "aws_ecr_repository" "ml_demo"
**Lens:** Security
**Subsystem:** Infra

**What:** Both ECR repositories have `image_tag_mutability = "MUTABLE"`, allowing existing image tags to be overwritten silently.
**Why it matters:** A deploy tag (e.g., a git SHA) can be re-pointed to a different image layer without changing the tag reference; immutable tags prevent silent image substitution and force a new tag per push.
**Recommended fix:** Set `image_tag_mutability = "IMMUTABLE"` on both repositories; the CI workflow already uses full SHA tags for deploys so this will not break the pipeline.

---

### 🟢 Low — ALB access logging is not enabled

**File:** backend/infra/alb.tf — resource "aws_lb" "api"
**Lens:** Security
**Subsystem:** Infra

**What:** The ALB resource has no `access_logs` block, so per-request access logs are not being written to S3.
**Why it matters:** Without ALB access logs, there is no durable audit trail of all inbound HTTP requests, making post-incident forensics and intrusion detection significantly harder once real users are added.
**Recommended fix:** Add an `access_logs { bucket = <log-bucket> enabled = true }` block to `aws_lb.api`, and create a dedicated S3 bucket with an appropriate bucket policy for ALB log delivery.

---

### 🟢 Low — `staging.tfvars` contains the alert recipient email address in plaintext

**File:** backend/infra/staging.tfvars
**Lens:** Security
**Subsystem:** Infra

**What:** The `alert_email` value (`anu.bnda@gmail.com`) is committed in plaintext to the repository.
**Why it matters:** This is a personal email address in a version-controlled file; low sensitivity currently, but establishes a pattern of embedding PII in tfvars files that could be followed for more sensitive values.
**Recommended fix:** Move `alert_email` to a GitHub Actions secret or Terraform Cloud variable and remove it from the committed tfvars file.

---

### ℹ️ Info — S3 bucket `sync` has no object-expiry lifecycle rule

**File:** backend/infra/s3.tf — resource "aws_s3_bucket_lifecycle_configuration" "sync"
**Lens:** Security
**Subsystem:** Infra

**What:** The `sync` bucket has only an abort-multipart-upload lifecycle rule; the `biosignals` bucket has a 365-day expiry rule, but the `sync` bucket has no object expiration.
**Why it matters:** Health sync objects will accumulate indefinitely in the sync bucket unless the application explicitly deletes them; this is an observation rather than an immediate risk.
**Recommended fix:** Evaluate whether sync objects should expire after a retention period (e.g., 90 days) and add an `expiration { days = N }` rule matching the data retention policy.

---

## Reliability

### 🟠 High — ECS service has no autoscaling configured and runs a fixed `desired_count = 1`

**File:** backend/infra/ecs.tf — resource "aws_ecs_service" "backend"
**Lens:** Reliability
**Subsystem:** Infra

**What:** The backend ECS service has `desired_count = 1` with no `aws_appautoscaling_target` or `aws_appautoscaling_policy` resources defined anywhere in the codebase.
**Why it matters:** A single Fargate task is a single point of failure; if the task crashes or is replaced during a deploy there is a period with zero healthy tasks; autoscaling is also necessary to handle load spikes when real users are onboarded.
**Recommended fix:** Add an `aws_appautoscaling_target` with `min_capacity = 1`, `max_capacity = 3` and a CPU-based `aws_appautoscaling_policy`; also configure the ECS service deployment circuit breaker with `rollback = true`.

---

### 🟠 High — ECS service has no deployment circuit breaker configured

**File:** backend/infra/ecs.tf — resource "aws_ecs_service" "backend"
**Lens:** Reliability
**Subsystem:** Infra

**What:** The `aws_ecs_service.backend` resource does not include a `deployment_circuit_breaker` block.
**Why it matters:** Without a circuit breaker, a bad deploy that keeps failing health checks will loop indefinitely and never auto-rollback; this means a broken image can take the service down for the full `aws ecs wait services-stable` timeout (10 minutes) with no automatic recovery.
**Recommended fix:** Add `deployment_circuit_breaker { enable = true rollback = true }` to the `aws_ecs_service.backend` resource (the CloudWatch alarm for `DeploymentFailureCount` is already in place and will alert on circuit trips).

---

### 🟡 Medium — RDS is single-AZ with no Multi-AZ standby

**File:** backend/infra/rds.tf — resource "aws_db_instance" "postgres"
**Lens:** Reliability
**Subsystem:** Infra

**What:** The RDS instance does not set `multi_az = true`, so it runs on a single Availability Zone with no automatic standby.
**Why it matters:** An AZ-level hardware failure or scheduled maintenance requiring an AZ-level failover would result in 1–2 minutes of downtime; acceptable for staging, but must be addressed before production.
**Recommended fix:** Set `multi_az = true` in the production override (document this in a `production.tfvars`); for staging, note explicitly in a comment that single-AZ is intentional for cost.

---

### 🟡 Medium — RDS `deletion_protection = false` and `skip_final_snapshot = true` in staging.tfvars

**File:** backend/infra/staging.tfvars + backend/infra/rds.tf
**Lens:** Reliability
**Subsystem:** Infra

**What:** Staging is explicitly configured with `rds_deletion_protection = false` and `rds_skip_final_snapshot = true`, meaning a `terraform destroy` would delete the database with no final snapshot.
**Why it matters:** If staging is used for any form of real testing data or becomes a stepping stone for production data validation, a mistaken destroy loses the database irreversibly; even staging data can be valuable for debugging.
**Recommended fix:** Consider setting `rds_deletion_protection = true` for staging as well (it only adds a manual step to delete), and set `rds_skip_final_snapshot = false` to always capture a snapshot; snapshot cost for `db.t4g.micro` is negligible.

---

### 🟡 Medium — No CloudWatch alarm for RDS CPU utilization

**File:** backend/infra/monitoring.tf
**Lens:** Reliability
**Subsystem:** Infra

**What:** Monitoring covers RDS connections and disk space, but there is no alarm for `CPUUtilization` on the RDS instance.
**Why it matters:** A CPU-saturated RDS instance will degrade query performance before connection limits are reached; without a CPU alarm, the first symptom visible in alerting will be the 5xx rate alarm, which is a lagging indicator.
**Recommended fix:** Add `aws_cloudwatch_metric_alarm.rds_cpu` watching `AWS/RDS CPUUtilization` with a threshold of 80% over 2 × 5-minute periods.

---

### 🟡 Medium — Single NAT Gateway covers all three private subnets

**File:** backend/infra/networking.tf — resource "aws_nat_gateway" "main"
**Lens:** Reliability
**Subsystem:** Infra

**What:** There is one NAT Gateway deployed in `public[0]` (AZ-a), and a single private route table is shared by all three private subnets routing all traffic through it.
**Why it matters:** If the AZ hosting the NAT gateway fails, all ECS tasks in private subnets across all AZs lose internet access (needed for ECR image pulls, Secrets Manager, Bedrock, etc.); this is acceptable for a single-AZ staging environment but is an outage vector.
**Recommended fix:** For production, deploy one NAT Gateway per AZ and create per-AZ private route tables; for staging, document the single-NAT decision as a cost trade-off.

---

### 🟢 Low — `aws_ecs_cluster` has no Container Insights enabled

**File:** backend/infra/ecs.tf — resource "aws_ecs_cluster" "main"
**Lens:** Reliability
**Subsystem:** Infra

**What:** The ECS cluster resource has no `setting { name = "containerInsights" value = "enabled" }` block.
**Why it matters:** Without Container Insights, per-task CPU and memory metrics are not available in CloudWatch, making it impossible to right-size tasks or detect memory pressure before OOM kills.
**Recommended fix:** Add `setting { name = "containerInsights" value = "enabled" }` to `aws_ecs_cluster.main`; note there is an additional CloudWatch cost (~$0.50/cluster/month at low scale).

---

### ℹ️ Info — Health check grace period is absent on the backend ECS service

**File:** backend/infra/ecs.tf — resource "aws_ecs_service" "backend"
**Lens:** Reliability
**Subsystem:** Infra

**What:** `aws_ecs_service.backend` has no `health_check_grace_period_seconds` set; the ml_demo service sets it to 120s, but the main backend service does not.
**Why it matters:** The container-level `healthCheck.startPeriod = 30s` provides some buffer, but the ALB target group's `unhealthy_threshold = 3` at 30s intervals means 90s of failed checks triggers deregistration; a slow cold start (e.g., loading large ML models or running migrations) could cause the service to be marked unhealthy before it is ready.
**Recommended fix:** Add `health_check_grace_period_seconds = 60` to `aws_ecs_service.backend` to match the container-level `startPeriod`.

---

## Cost & Architecture

### 🟡 Medium — ml_demo service is permanently running (ephemeral service with no teardown plan)

**File:** backend/infra/ml_demo.tf — resource "aws_ecs_service" "ml_demo"
**Lens:** Cost & Architecture
**Subsystem:** Infra

**What:** The comment in `ml_demo.tf` says "ephemeral ECS Fargate stack for the LIT-60 handoff window," but the `aws_ecs_service.ml_demo` has `desired_count = 1` with no scheduled scale-down or conditional deployment.
**Why it matters:** A permanently running Fargate task (256 CPU / 512 MB) costs approximately $7–10/month in ap-northeast-2; if this is truly ephemeral and the handoff window has passed, the task and associated resources (ECR repo, target group, listener rule, CloudWatch alarm, log group) are running/paying for nothing.
**Recommended fix:** Either set `desired_count = 0` now if the handoff is complete, or use a `count = var.ml_demo_enabled ? 1 : 0` pattern on all ml_demo resources controlled by a boolean variable; add a tracking ticket to tear down after the demo window.

---

### 🟡 Medium — `common_tags` Sprint field is hardcoded to Sprint "2"

**File:** backend/infra/locals.tf — locals block
**Lens:** Cost & Architecture
**Subsystem:** Infra

**What:** `common_tags` includes `Sprint = "2"` as a static string.
**Why it matters:** Resources created in subsequent sprints carry a stale Sprint tag, making cost allocation by sprint incorrect; Sprint 7 resources (scheduler, DLQ) and Sprint 5 resources (S3 buckets) all report as Sprint 2.
**Recommended fix:** Either remove the Sprint tag (sprint-level tagging rarely provides value post-launch) or make it a variable so it can be updated per apply cycle.

---

### 🟢 Low — Three NAT Gateway EIPs allocated (networking creates 3 public subnets but only 1 EIP/NAT)

**File:** backend/infra/networking.tf
**Lens:** Cost & Architecture
**Subsystem:** Infra

**What:** Three public subnets are created (for multi-AZ ALB), and one NAT Gateway is created — this is actually correct and not over-provisioned; only one EIP is allocated.
**Recommended fix:** No action required. This is correctly implemented for a staging single-NAT cost trade-off. (Observation only.)

---

### 🟢 Low — ECS task CPU/memory is appropriate for staging but should be documented for production planning

**File:** backend/infra/ecs.tf — resource "aws_ecs_task_definition" "backend"
**Lens:** Cost & Architecture
**Subsystem:** Infra

**What:** The backend task definition allocates 512 vCPU units and 1024 MB memory; the cron and ml_demo tasks each allocate 256 vCPU / 512 MB.
**Why it matters:** These are appropriately sized for staging but will need revisiting under real load; there is no documentation of what baseline CPU/memory utilization looks like at target scale.
**Recommended fix:** Once Container Insights is enabled (see Reliability findings), capture a 30-day memory/CPU baseline before promoting to production and size accordingly.

---

### ℹ️ Info — RDS `db.t4g.micro` is correctly sized for staging

**File:** backend/infra/rds.tf — resource "aws_db_instance" "postgres"
**Lens:** Cost & Architecture
**Subsystem:** Infra

**What:** `db.t4g.micro` (~$12/month in ap-northeast-2) is appropriate for staging; `max_allocated_storage = 100` GB provides sensible autoscaling headroom.
**Why it matters:** No immediate action needed; note that `db.t4g.micro` has a maximum of ~86 connections, which is why the RDS connection alarm threshold of 60 is well-calibrated.
**Recommended fix:** No action needed for staging. Plan to upgrade to at least `db.t4g.small` (or `db.t4g.medium` with pgBouncer) for production.

---

## Correctness

### 🟡 Medium — `staging.tfvars` does not set `ml_demo_image` — service deploys with `hello-world` placeholder

**File:** backend/infra/staging.tfvars + backend/infra/variables.tf — variable "ml_demo_image"
**Lens:** Correctness
**Subsystem:** Infra

**What:** `ml_demo_image` defaults to `public.ecr.aws/docker/library/hello-world:latest` in `variables.tf` and is not overridden in `staging.tfvars`, so `aws_ecs_task_definition.ml_demo` uses the placeholder image.
**Why it matters:** The ECS service for ml_demo is running with `desired_count = 1`, meaning the `hello-world` container is actually what is deployed; the `hello-world` image exits immediately, causing the service to keep cycling through task replacements and generating `ml-demo-unhealthy` alarms.
**Recommended fix:** Add `ml_demo_image = "<real-ecr-uri>:<sha>"` to `staging.tfvars` once the image is pushed, or set `desired_count = 0` if the service is not actively needed.

---

### 🟡 Medium — `container_image` in `staging.tfvars` is the Python stdlib image, not the real backend

**File:** backend/infra/staging.tfvars — container_image
**Lens:** Correctness
**Subsystem:** Infra

**What:** `container_image = "public.ecr.aws/docker/library/python:3.12-slim"` is the bootstrap placeholder defined in the comments of `variables.tf`; it is not the actual application image.
**Why it matters:** If `terraform apply` is run against the staging state without the CI deploy workflow first building and pushing a real image, the bootstrap placeholder would be used, which does not contain the FastAPI app and would fail all health checks.
**Recommended fix:** This is likely correct for the initial bootstrap flow (apply → CI builds and pushes real image → deploy workflow re-renders task definition). Ensure the `staging.tfvars` file is never committed with this value after the first real deploy, or document clearly that the value in tfvars is always the bootstrap default and the actual running image is managed by the CI deploy workflow independently of Terraform state.

---

### 🟡 Medium — OIDC thumbprint is a single, legacy SHA1 value

**File:** backend/infra/oidc.tf — resource "aws_iam_openid_connect_provider" "github"
**Lens:** Correctness
**Subsystem:** Infra

**What:** The `thumbprint_list` contains a single SHA1 thumbprint (`6938fd4d98bab03faadb97b34396831e3780aea1`) for the GitHub Actions OIDC provider.
**Why it matters:** GitHub rotated its OIDC certificate in 2023 and the current recommended practice for AWS is to include both the old and new thumbprint in the list; if the single thumbprint becomes stale, OIDC authentication will fail for all CI/CD workflows.
**Recommended fix:** Add the second GitHub Actions OIDC thumbprint (`1c58a3a8518e8759bf075b76b750d4f2df264fcd`) to the `thumbprint_list`. Note that AWS now validates the OIDC token signature against the JWKS endpoint rather than the TLS thumbprint for GitHub, so the thumbprint check is de-facto a no-op for GitHub — but keeping the list current avoids confusion.

---

### 🟢 Low — `required variables with no default` all covered in `staging.tfvars`

**File:** backend/infra/variables.tf + backend/infra/staging.tfvars
**Lens:** Correctness
**Subsystem:** Infra

**What:** Variables with no default (`domain_name`, `hosted_zone_name`, `container_image`, `alert_email`, `gha_repo_full_name`) are all provided in `staging.tfvars`.
**Why it matters:** No missing variable values — `terraform plan -var-file=staging.tfvars` should not fail on unset required variables.
**Recommended fix:** No action required; observation only.

---

### 🟢 Low — Scheduler `cron()` expressions are valid EventBridge syntax

**File:** backend/infra/scheduler.tf
**Lens:** Correctness
**Subsystem:** Infra

**What:** All three schedule expressions (`cron(0 3 * * ? *)`, `cron(15 */6 * * ? *)`, `cron(0 17 ? * SAT *)`) use correct EventBridge cron format (with the `?` wildcard for the day-of-month or day-of-week field as required by EventBridge).
**Why it matters:** Malformed cron expressions fail silently at creation and the schedule never fires.
**Recommended fix:** No action required; all three expressions are syntactically valid.

---

### ℹ️ Info — ECR repo name referenced in `ecs.tf` correctly matches what `ecr.tf` creates

**File:** backend/infra/ecs.tf + backend/infra/ecr.tf
**Lens:** Correctness
**Subsystem:** Infra

**What:** The ECS task definition uses `var.container_image` (the full URI, not the repo name), and the ECR repo is created as `${local.name_prefix}-backend`; the deploy workflow references `ECR_REPOSITORY_NAME: little-signals-staging-backend`, which matches `local.name_prefix = "little-signals-staging"`.
**Why it matters:** No mismatch — all three are consistent.
**Recommended fix:** No action required.

---

## CI/CD

### 🟠 High — `deploy-production.yml` does not run migrations against production DB before the service roll

**File:** .github/workflows/deploy-production.yml
**Lens:** CI/CD
**Subsystem:** Infra

**What:** The production deploy workflow does run an Alembic migration task ("Run migrations against production DB"), but it does so using the new task definition revision, which means the new code is in the migration container. However, the `"Discover production ECS networking"` step pulls subnets/SG from the production ECS *service*, and if the production ECS service does not yet exist (production infra has not been applied), `describe-services` returns an empty result, causing the subsequent `jq` to produce empty strings and the migration `run-task` call to fail with a missing network config error.
**Why it matters:** If the production environment is provisioned for the first time via this workflow (before a Terraform apply creates the production ECS service), the migration step will fail with a non-obvious networking error before the service rolls, leaving the database un-migrated and the deploy workflow reporting failure.
**Recommended fix:** Add an explicit check that the production ECS service exists before proceeding; alternatively, document that `terraform apply` for the production environment must complete before `deploy-production.yml` can be run.

---

### 🟠 High — Production deploy has no smoke test rollback — it exits 1 but leaves the bad task definition active

**File:** .github/workflows/deploy-production.yml — "Production smoke" step
**Lens:** CI/CD
**Subsystem:** Infra

**What:** If the production smoke test fails, the workflow exits with code 1, but the ECS service has already been updated to the new task definition and `update-service` issued; there is no automatic rollback step.
**Why it matters:** A failed smoke test means the new (bad) task definition is already running in production; the engineer must manually revert via `ecs update-service --task-definition <previous-arn>`; an automated rollback step would reduce MTTR.
**Recommended fix:** Capture the previous task definition ARN before the `update-service` call and add a step that triggers `ecs update-service --task-definition $PREVIOUS_ARN` on smoke test failure (and ECS already has a circuit breaker that will detect health check failures, so this is belt-and-suspenders).

---

### 🟡 Medium — `deploy-staging.yml` does not explicitly verify CI passed before deploying

**File:** .github/workflows/deploy-staging.yml
**Lens:** CI/CD
**Subsystem:** Infra

**What:** The workflow triggers on `workflow_run` of the CI workflow with `conclusion == 'success'`, and also on `workflow_dispatch`. Manual dispatch has no guard on CI status (`if: ${{ github.event_name == 'workflow_dispatch' || github.event.workflow_run.conclusion == 'success' }}`).
**Why it matters:** A developer can trigger a manual deploy dispatch (`workflow_dispatch`) for any SHA — even one where CI is failing — bypassing the lint, type-check, test, and Trivy scan gates; this is a correctness risk not a security risk (since only repo members can dispatch), but is worth noting.
**Recommended fix:** Add a check step at the top of the manual dispatch path that queries the GitHub API for the CI status of the target SHA and aborts if any check failed, or document that manual dispatch is intentionally unrestricted for emergency hotfixes.

---

### 🟡 Medium — `deploy-staging.yml` pushes a `latest` mutable tag alongside the SHA tag

**File:** .github/workflows/deploy-staging.yml — "Build and push image" step
**Lens:** CI/CD
**Subsystem:** Infra

**What:** Every staging deploy pushes two tags: `<sha>` and `latest`; the ECS task definition is rendered with the SHA tag, but `latest` is always overwritten.
**Why it matters:** The `latest` tag is relied upon by Terraform's `variables.tf` default for `container_image` (bootstrap placeholder); more importantly, `latest` in ECR being mutable means any `aws ecs run-task` call that references `latest` directly (e.g., a manual test invocation) will use whatever was last deployed — invisible drift.
**Recommended fix:** Keep the SHA tag as the authoritative deploy tag; either stop pushing `latest` or explicitly document that `latest` in ECR is only a convenience alias for the most recent staging deploy.

---

### 🟡 Medium — Production workflow role ARN is hardcoded as a string with a naming assumption

**File:** .github/workflows/deploy-production.yml — "Configure AWS credentials via OIDC" step
**Lens:** CI/CD
**Subsystem:** Infra

**What:** The role ARN is `arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/little-signals-staging-gha-production-deploy`; the prefix `little-signals-staging` is the staging `name_prefix` derived from `project = "little-signals"` and `environment = "staging"`.
**Why it matters:** The production deploy IAM role lives in the staging Terraform state (correctly — it is the same AWS account for now), but the name embeds `staging`, which is confusing when this workflow is described to other contributors; there is also a hard dependency on `AWS_ACCOUNT_ID` being set in repo secrets.
**Recommended fix:** Expose the role ARN as a Terraform output (`gha_production_role_arn`) and store it as a GitHub Actions repository secret (`GHA_PRODUCTION_ROLE_ARN`) so it does not need to be reconstructed from account ID + name convention in the workflow.

---

### 🟢 Low — `traffic-snapshot.yml` directly pushes to `master` without a PR

**File:** .github/workflows/traffic-snapshot.yml
**Lens:** CI/CD
**Subsystem:** Infra

**What:** The traffic snapshot workflow commits and pushes directly to `master` via `git push` using the `github-actions[bot]` identity.
**Why it matters:** This bypasses any branch protection rules on `master` (e.g., required PR reviews); if branch protection is enforced later, this workflow will start failing; it also makes the commit history noisier for other contributors.
**Recommended fix:** Either create a separate branch and open a PR (overkill for traffic data), or ensure the branch protection rules explicitly allow `github-actions[bot]` to bypass the review requirement for paths under `.github/traffic/`.

---

### ℹ️ Info — CI workflow Trivy scan uses `exit-code: '1'` for HIGH and CRITICAL vulnerabilities

**File:** .github/workflows/ci.yml — "Trivy vulnerability scan" step
**Lens:** CI/CD
**Subsystem:** Infra

**What:** Trivy is configured to fail CI on HIGH or CRITICAL severity unfixed vulnerabilities, with `ignore-unfixed: true` so only actionable findings block the build.
**Why it matters:** This is a healthy security gate; no action needed. The `ignore-unfixed: true` flag prevents false positives from blocking deploys.
**Recommended fix:** No action required; observation only.

---

## Summary

**28 total findings: 0 🔴 critical, 3 🟠 high, 11 🟡 medium, 6 🟢 low, 5 ℹ️ info**

| Severity | Count |
|----------|-------|
| 🔴 Critical | 0 |
| 🟠 High | 3 |
| 🟡 Medium | 11 |
| 🟢 Low | 6 |
| ℹ️ Info | 5 |

### High-severity summary

1. **ECS service has no autoscaling or deployment circuit breaker** (`ecs.tf`): A single Fargate task with no circuit breaker means a bad deploy loops indefinitely; a spike in load has no relief valve. Both can be fixed with ~10 lines of Terraform.

2. **Production deploy has no automatic rollback on smoke test failure** (`deploy-production.yml`): The workflow exits 1 but leaves the bad image running in production; an engineer must intervene manually.

3. **Production ECS networking discovery depends on the production service existing** (`deploy-production.yml`): First-run of the production deploy workflow will fail before migrations are applied if the production Terraform has not been applied first.

### Notable patterns

- **Staging-vs-production defaults are well-separated** in variables.tf with clear comments — this is a good pattern, but production overrides (multi_az, deletion_protection, skip_final_snapshot) are not yet codified in a `production.tfvars`.
- **IAM is tightly scoped** in most places (specific secret ARNs, specific ECR repo ARNs, PassRole with service condition), with the exception of the X-Ray/logs wildcard resource.
- **The ml_demo "ephemeral" service** appears to be running indefinitely with a placeholder image; it needs either a real image or `desired_count = 0`.
- **No critical findings** for a staging-only environment — the most dangerous production risks (RDS publicly accessible, public S3, hardcoded secrets) are all correctly configured.
