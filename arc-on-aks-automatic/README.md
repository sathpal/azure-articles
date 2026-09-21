---
title: "Running GitHub Actions Runner Controller on AKS Automatic: the blog post, executed end to end"
published: false
description: "I ran the AKS team's ARC on AKS Automatic guide from a clean subscription: quota, cluster, controller, scale-to-zero runners, node auto-provisioning and Deployment Safeguards, with every output captured."
tags: kubernetes, azure, github, devops
cover_image: https://raw.githubusercontent.com/sathpal/azure-articles/main/arc-on-aks-automatic/img/cover.png
---

On 17 September 2026 the AKS engineering blog published [Running GitHub Actions Runner Controller on AKS Automatic](https://blog.aks.azure.com/2026/09/17/github-actions-runner-controller-aks-automatic) by Steve Griffith. It is a clean guide: create an AKS Automatic cluster, install Actions Runner Controller (ARC), register a runner scale set against a GitHub repository, run a workflow, watch it scale.

I followed it from a subscription that had never run AKS Automatic, and this post is what happened, command by command, with the real output. Most of it went exactly as written. Three things did not, and those are the useful parts.

**Repo:** [github.com/sathpal/arc-aks-automatic-demo](https://github.com/sathpal/arc-aks-automatic-demo). One `make` target per step, a screenshot of each, a troubleshooting section for everything that went wrong, and the validation workflow. Fork it, set your GitHub user in `.env`, and the runners register against your fork.

## What AKS Automatic changes

A standard AKS cluster gives you a Kubernetes API and lets you decide the rest. AKS Automatic decides for you: node auto-provisioning (Karpenter) instead of hand-sized node pools, Azure RBAC for Kubernetes with local accounts disabled, managed Prometheus and Grafana, and Deployment Safeguards, which are Gatekeeper policies that block or warn on common anti-patterns such as pods without resource requests or images tagged `latest`.

ARC is a good test of that. It has a controller, a listener per runner set, and ephemeral runner pods that appear when a job is queued and vanish when it finishes. The runner pods are exactly the kind of bursty workload node auto-provisioning is for, and the charts are exactly the kind of upstream Helm charts that Safeguards will have opinions about.

## Step 0: two things the blog assumes you already have

**A current Azure CLI.** The guide's first command is `az extension add --name aks-preview --upgrade`. On my machine that pulled an aks-preview build that needs a newer CLI than the 2.72 I had, and every `az aks` command then died with a Python traceback. The `--sku automatic` flag is GA and lives in the core CLI, so the fix was not the extension but the CLI itself:

```bash
az extension remove -n aks-preview
brew upgrade azure-cli          # 2.72.0 -> 2.90.0
az aks create --help | grep -A2 -- --sku
```

**Sixteen vCPUs of quota in one VM family that AKS Automatic likes.** My first create attempt failed after a minute with:

```
AKS Automatic could not find a suitable VM size. The subscription may not have the
required quota of '16' vCPUs, may have restrictions, or location 'australiaeast' may
not support three availability zones for the following VM sizes: 'standard_d4lds_v5,
standard_d4ads_v5, standard_d4ds_v5, standard_d4d_v5, standard_d4d_v4, standard_ds3_v2,
standard_ds12_v2, standard_d4alds_v6, standard_d4lds_v6, standard_d4alds_v5'
```

Every D-family in every region I checked was at the default limit of 10 cores. The fix was a quota request through the CLI, which was approved instantly for one family:

```bash
az extension add -n quota
az quota update \
  --resource-name standardDaldv6Family \
  --scope "/subscriptions/<sub-id>/providers/Microsoft.Compute/locations/australiaeast" \
  --limit-object value=48 --resource-type dedicated
```

The same request for the DSv5 family came back "ContactSupport", so pick a family that is cheap and new; the v6 AMD sizes were the ones that went through for me.

## Step 1: create the cluster

```bash
export LOCATION=australiaeast RG=rg-arc-auto-lab CLUSTER=arc-auto-lab
az group create --name $RG --location $LOCATION
az aks create --resource-group $RG --name $CLUSTER --location $LOCATION \
  --sku automatic --no-ssh-key
```

This took 33 minutes, not the ten I had budgeted from experience with standard AKS. Automatic creates a three-node system pool spread across zones, a hosted pool for its own add-ons, Karpenter, managed monitoring, and the policy stack, then waits for all of it to be healthy.

Local accounts are disabled, so you give yourself a Kubernetes RBAC role through Azure and use kubelogin:

```bash
AKS_ID=$(az aks show -g $RG -n $CLUSTER --query id -o tsv)
ME=$(az ad signed-in-user show --query id -o tsv)
az role assignment create --assignee $ME \
  --role "Azure Kubernetes Service RBAC Cluster Admin" --scope $AKS_ID
az aks get-credentials -g $RG -n $CLUSTER --format exec --overwrite-existing
kubectl get nodes -o wide
```

![Cluster profile: Automatic SKU, node provisioning Auto, Azure RBAC on, local accounts disabled, six nodes](https://raw.githubusercontent.com/sathpal/azure-articles/main/arc-on-aks-automatic/img/02-cluster.png)

Six nodes on day one: three `nodepool1` system nodes and three `hostedpool` nodes that AKS runs for its managed components. All on Azure Linux 3.0.

## Step 2: install the controller

The controller chart has no resource requests by default, and Deployment Safeguards will refuse a pod without them. The blog's values file fixes that:

```yaml
# arc-controller-values.yaml
resources:
  requests: { cpu: 100m, memory: 128Mi }
  limits:   { cpu: 500m, memory: 512Mi }
```

```bash
helm upgrade --install arc \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
  --namespace arc-systems --create-namespace --wait --timeout 10m \
  -f arc-controller-values.yaml
```

![helm install of the controller succeeds; controller pod Running](https://raw.githubusercontent.com/sathpal/azure-articles/main/arc-on-aks-automatic/img/03-controller.png)

It installs, but Safeguards has more to say than the blog mentions. The install printed warnings that the controller container has no liveness or readiness probe, and that anti-affinity and topology spread constraints were added to the deployment by mutation. Those are warn-level policies, so the install goes through. The ones in deny mode, such as resource requests, are the ones that would have stopped it:

![Deployment Safeguards warnings from the helm install, and the Gatekeeper constraints with their enforcement actions](https://raw.githubusercontent.com/sathpal/azure-articles/main/arc-on-aks-automatic/img/09-safeguards.png)

If you want the probe warning gone, the controller chart accepts `livenessProbe` and `readinessProbe` values. I left it as the blog has it so the output matches.

## Step 3: token and runner scale set

```bash
kubectl create namespace arc-runners --dry-run=client -o yaml | kubectl apply -f -
printf '%s' "$GITHUB_TOKEN" | kubectl create secret generic github-pat \
  --namespace arc-runners --from-file=github_token=/dev/stdin
```

A classic PAT with `repo` scope is enough for a repository-level runner set. The blog says, and I agree, that anything beyond a lab should use a GitHub App so the permission is narrow and rotation is not a person's job.

The runner set values need three things to be explicit for Safeguards: resource requests on the listener, resource requests on the runner, and a pinned runner image tag. The default chart uses `ghcr.io/actions/actions-runner:latest`, and Safeguards rejects floating tags.

```yaml
# arc-runner-set-values.yaml
githubConfigUrl: https://github.com/<owner>/<repo>
githubConfigSecret: github-pat
minRunners: 0
maxRunners: 3
listenerTemplate:
  spec:
    containers:
      - name: listener
        resources:
          requests: { cpu: 100m, memory: 128Mi }
          limits:   { cpu: 500m, memory: 512Mi }
template:
  spec:
    containers:
      - name: runner
        image: ghcr.io/actions/actions-runner:2.337.0
        command: ["/home/runner/run.sh"]
        resources:
          requests: { cpu: "2", memory: 4Gi }
          limits:   { cpu: "2", memory: 4Gi }
```

The blog pins 2.336.0. By the time I ran this, 2.337.0 was current, and GitHub refuses runners more than a few versions behind, so check [the releases page](https://github.com/actions/runner/releases) before you copy a tag.

```bash
helm upgrade --install arc-auto-runners \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --namespace arc-runners --wait --timeout 10m -f arc-runner-set-values.yaml
```

![Runner scale set installed: min 0, max 3, listener pod Running next to the controller](https://raw.githubusercontent.com/sathpal/azure-articles/main/arc-on-aks-automatic/img/04-runnerset.png)

A listener pod appears in `arc-systems` and long-polls GitHub's broker for jobs. With `minRunners: 0` nothing else runs until a job arrives, and the repository's runner list stays empty. That is normal and briefly alarming.

![Listener pod Running; log shows the ephemeral runner set scaled and the listener waiting on the broker](https://raw.githubusercontent.com/sathpal/azure-articles/main/arc-on-aks-automatic/img/05-listener.png)

## Step 4: run a workflow and watch it scale

The validation workflow from the blog, unchanged, committed to `.github/workflows/arc-automatic-validation.yml` with `runs-on: arc-auto-runners`, which is the Helm release name and therefore the runner label.

```bash
gh workflow run arc-automatic-validation.yml --repo <owner>/<repo> --ref main
```

I polled the run status, the runner pods and the node count every ten seconds:

![Timeline: job queued, runner pod Pending, node count 7 to 8, ContainerCreating, Running, completed success, back to 0 runners](https://raw.githubusercontent.com/sathpal/azure-articles/main/arc-on-aks-automatic/img/06-scale.png)

What happened in those 190 seconds:

- **t+19s** the listener saw the queued job and created one ephemeral runner pod. It went Pending: the system nodes are tainted for system workloads and the one schedulable node did not have 4Gi free.
- **t+53s** node auto-provisioning launched a new node for it. Karpenter nominated the pod onto the node claim before the VM existed.
- **t+121s** the node was ready and the pod pulled the runner image, which is about a gigabyte and took 52 seconds.
- **t+173s** the job ran. It took 8 seconds.
- **t+190s** the run reported success, the pod was gone, and the runner count was back to zero.

![kubectl get nodeclaims shows the D4as_v6 Karpenter provisioned, then a consolidation candidate event offering to replace it for a cheaper size with the savings in dollars](https://raw.githubusercontent.com/sathpal/azure-articles/main/arc-on-aks-automatic/img/08-nap.png)

The node claim output is the part worth staring at. Karpenter picked a `Standard_D4as_v6` on demand for the runner, and within minutes of the job finishing it flagged that node as a consolidation candidate, launched a cheaper `D4als_v6` replacement and moved the controller and listener onto it, quoting the saving. Nobody configured any of that.

On the GitHub side it looks like any other run:

![GitHub Actions run page: ARC AKS Automatic validation, Success, validate job 8s, total 2m 48s](https://raw.githubusercontent.com/sathpal/azure-articles/main/arc-on-aks-automatic/img/10-github-run.png)

```
Current runner version: '2.337.0'
Runner name: 'arc-auto-runners-j4kzc-runner-x8p8j'
ARC runner reached workflow execution
Linux arc-auto-runners-j4kzc-runner-x8p8j 6.6.150.1-1.azl3 #1 SMP x86_64 GNU/Linux
Docker version 29.7.2, build a7dcaa6
Validation complete
```

![Job log from gh run view: runner version, runner name, uname, df, docker version](https://raw.githubusercontent.com/sathpal/azure-articles/main/arc-on-aks-automatic/img/07-run.png)

The total of 2 minutes 48 seconds is almost entirely cold start: a new VM and a cold image pull. A second job arriving while the node is still there would start in seconds. If that latency matters, set `minRunners: 1`, and accept that you now pay for one idle D4.

## Step 5: clean up

```bash
helm uninstall arc-auto-runners -n arc-runners
helm uninstall arc -n arc-systems
kubectl delete namespace arc-runners arc-systems
az group delete --name rg-arc-auto-lab --yes --no-wait
```

The resource group delete also removes the node resource group AKS created.

One more thing I learned by doing it wrong. I moved the runner set from one repository to another with `helm upgrade` and a new `githubConfigUrl`. The listener crashed on every start with "No runner scale set found with identifier 1": the set had kept the ID it registered under the first repository, and the second one had no such ID. Uninstall and reinstall is the only clean path, and if a stale `AutoscalingListener` object survives that, delete it and the controller recreates it in seconds.

## What I would tell a colleague

- **It works as described.** The blog's values files are correct and complete for Safeguards. Copy them.
- **Budget an hour for the first cluster.** 33 minutes to create, plus the quota round trip if your subscription is at defaults. Check `az vm list-usage -l <region> -o table` before you start and request the increase first.
- **Keep the CLI current.** The preview extension is not the thing that enables Automatic; the CLI version is.
- **Safeguards are mostly warnings.** Only a few policies deny. Read the warnings anyway; they are the same list a security review would produce.
- **Node auto-provisioning is the quiet win.** Zero runner nodes at rest, a right-sized node in two minutes when a job lands, and consolidation to a cheaper size afterwards with the saving printed in the event log.
- **Use a GitHub App for anything shared.** The PAT path is fine for a lab and wrong for a team.

## Try it

```bash
gh repo fork sathpal/arc-aks-automatic-demo --clone && cd arc-aks-automatic-demo
make tools && cp .env.example .env         # set GITHUB_OWNER to your user
make quota && make cluster && make access && make arc
export GITHUB_TOKEN=$(gh auth token) && make runners && make test
make cleanup
```
