# LinkedIn post

Paste the block below as the post text. Attach `img/cover.png` as the image. Replace `[article link]` with the dev.to URL once published.

---

I watched a Kubernetes cluster buy a VM, run my job, decide the VM was too expensive, and swap it for a cheaper one. Nobody asked it to.

That was the moment this experiment stopped being a chore.

It started with a blog post. The AKS team published a guide to running GitHub Actions Runner Controller on AKS Automatic, and I wanted to know one thing: does it work from a normal subscription, or only from a Microsoft engineer's?

Round one: Azure said no. The first cluster create failed in a minute. "Could not find a suitable VM size." AKS Automatic wants 16 vCPUs of quota in one of its favourite VM families. My subscription had 10. So did every region I checked. Fine: quota request through the CLI. The AMD v6 family was approved before I finished reading the output. The DSv5 request came back "contact support". Lesson one: check quota before you check anything else.

Round two: the CLI broke. The guide's first command installs a preview extension. On my CLI version, that extension killed every az aks command with a Python traceback. The automatic SKU turned out to be in the core CLI all along; I just had an old one. Remove the extension, upgrade, move on.

Round three: 33 minutes of waiting. That is how long the cluster took. Automatic builds a lot: three-zone system pool, a hidden pool for its own add-ons, Karpenter, Prometheus, Grafana, policy engine. Enough time to read the guide twice more.

Then the good part. Controller installed. Runner scale set installed, minimum zero. I triggered a workflow and watched:

19 seconds: a runner pod appears. Pending. Nothing can host it.
53 seconds: Karpenter launches a node for it. The pod is already nominated onto a node that does not exist yet.
2 minutes: node ready, image pulled.
2 min 53: job done. It took 8 seconds. Pod gone. Runners back to zero.

Twenty minutes after that, the VM swap. Karpenter flagged the node as underused, priced a cheaper size, launched it, moved the pods, deleted the original, and wrote the saving in the event log. I have hand-built that logic before and never got it this clean.

I also broke it, on purpose, sort of. I pointed the runner set at a different repo by editing the URL. The listener crashed on every start: "no runner scale set found with identifier 1". It had kept the ID from the first repo. Uninstall and reinstall is the only way through. That one is in the troubleshooting section now, with the screenshot.

Everything is in a repo with one make target per step and a preflight check that tells you what will fail before you spend a dollar. Fork it, set your GitHub user, run it. Every screenshot in the write-up is from that run.

Article: [article link]
Repo: https://github.com/sathpal/arc-aks-automatic-demo
The guide that started it: https://blog.aks.azure.com/2026/09/17/github-actions-runner-controller-aks-automatic

#Kubernetes #Azure #AKS #GitHubActions #Karpenter #PlatformEngineering #DevOps
