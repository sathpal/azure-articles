# LinkedIn post

Paste the block below as the post text. Attach `img/cover.png` as the image. Replace `[article link]` with the dev.to URL once published.

---

I ran the AKS team's guide to GitHub Actions Runner Controller on AKS Automatic, end to end, from a subscription that had never created an Automatic cluster. Here is what the guide gets right and what it assumes you already have.

The setup: an AKS Automatic cluster, Actions Runner Controller, and a runner scale set with minimum zero registered against a GitHub repository. A workflow with runs-on pointing at the scale set is the test.

What happened on the first job: the listener saw it queued and created a runner pod. Nothing could schedule it, so Karpenter provisioned a D4 node, the pod pulled the runner image, and the job ran in 8 seconds. Total 2 minutes 48 seconds from dispatch to success, then back to zero runners. Twenty minutes later Karpenter decided the node it had bought was underused, launched a cheaper size, moved the pods and deleted the original, with the saving printed in the event log. Nobody configured that.

What the guide assumes:

Quota. AKS Automatic needs 16 vCPUs in one of a specific list of D4 families. A default subscription has 10 in every family, in every region I checked. A CLI quota request for the AMD v6 family was approved instantly; the same request for DSv5 was refused.

A current Azure CLI. The guide starts with the aks-preview extension. On CLI 2.72 that broke every az aks command. The automatic SKU is in the core CLI from 2.80, and the fix was to remove the extension and upgrade.

Time. Cluster creation took 33 minutes. Automatic builds a zone-spread system pool, a hosted pool for its add-ons, Karpenter, managed Prometheus and Grafana, and the policy stack before it reports ready.

Deployment Safeguards had more to say than the guide mentions. The controller install produced warnings about missing liveness and readiness probes and about anti-affinity rules it added by mutation. Those are warn-level, so the install went through. The deny-level ones, such as resource requests and no floating image tags, are exactly what the guide's values files already handle.

One mistake I made and documented: I moved the runner set to a different repository by changing the URL in place. The listener crashed on every start with "No runner scale set found with identifier 1", because the set kept the ID it had registered under the first repo. Uninstall and reinstall is the only clean path.

The write-up has every command and its output, and the companion repo has one make target per step with a preflight check that verifies tools, logins and quota before anything costs money. Fork it, set your GitHub user, run the steps.

Article: [article link]
Repository: https://github.com/sathpal/arc-aks-automatic-demo
The guide: https://blog.aks.azure.com/2026/09/17/github-actions-runner-controller-aks-automatic

#Kubernetes #Azure #AKS #GitHubActions #PlatformEngineering #DevOps #Karpenter
