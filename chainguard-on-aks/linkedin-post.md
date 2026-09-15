# LinkedIn post

Paste the block below as the post text. Attach `img/01-compare.png` (the 178 vs 5 table) as the image. Replace `[article link]` with the dev.to URL once published.

---

Same app. Same code. Two base images. 178 known CVEs vs 5.

I kept hearing the pitch: "Chainguard images are minimal, signed, rebuilt daily, most CVEs never reach your cluster." Marketing or real? I stopped guessing and built the smallest demo that could prove it wrong.

What I did, in one afternoon:

1. One 40-line FastAPI app, built twice: on python:3.13-slim and on cgr.dev/chainguard/python.
2. Scanned both with grype. 178 vs 5. Zero critical on the Chainguard side.
3. Tried to get a shell in each. Upstream: root prompt, apt-get, 259 binaries. Chainguard: there is no shell to start.
4. Verified the base image signature with cosign, no vendor account needed.
5. Deployed both to Azure Kubernetes Service, side by side, behind public IPs.
6. Put Kyverno in front: only signed images from trusted registries get in. Docker Hub nginx? Rejected at the API server.

What actually surprised me:

→ The CVE delta is real, but 7 of my first 12 findings were my own outdated FastAPI pin. The base image does not fix your requirements.txt. That part is still on you.

→ Two things bite on Azure that never bite on a laptop. ACR Tasks uses Docker's legacy builder, so WORKDIR comes out root-owned and the nonroot build fails. And Kubernetes refuses runAsNonRoot when the image names its user instead of numbering it. Both fixed, both documented.

→ No shell means kubectl exec is gone. Your on-call runbooks need kubectl debug. Plan for it.

Bonus: I turned the whole migration into a Claude Code skill. Open the repo, type "use the chainguard-migrate skill on docker/Dockerfile.upstream", and the agent baselines, rewrites the Dockerfile, rebuilds, rescans, verifies the signature and prints the before/after table. Its last rule: never claim zero CVEs without a fresh scan in the transcript. Security claims need receipts, even from an AI.

Everything is reproducible. Clone, run make demo, get today's numbers. No Azure needed for the local part.

Full walkthrough with every command and screenshot: [article link]
Repo: https://github.com/sathpal/chainguard-aks-demo

If you run it and your numbers differ, that is the point. Both images change every day. Only one of them changes in your favour.

#Kubernetes #Azure #AKS #ContainerSecurity #SupplyChainSecurity #DevSecOps #Chainguard #ClaudeCode #PlatformEngineering
