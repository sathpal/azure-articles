# LinkedIn post

Paste the block below as the post text. Attach `img/cover.png` as the image. Replace `[article link]` with the dev.to URL once published.

---

Same application, two base images, 178 known CVEs versus 5. A hands-on evaluation of Chainguard images on Azure Kubernetes Service.

After watching the Cloud Native Partner Showcase episode in which David Giard (Microsoft) discusses secure-by-default container images with Hannah Hawken and Manfred Moser (Chainguard), I wanted to validate the claims with numbers I produced myself. The result is a small, fully reproducible walkthrough with every command, output and screenshot.

What the evaluation covers:

1. One FastAPI service, built on python:3.13-slim and on cgr.dev/chainguard/python, with identical application code.
2. Vulnerability scanning of both images with grype: 178 findings against 5, none critical on the Chainguard side.
3. Runtime inspection: the upstream image runs as root with a shell and package manager; the Chainguard image runs as a non-root user with neither.
4. Signature verification of the base image with cosign against Chainguard's public Sigstore identity, and SBOM comparison with syft.
5. Deployment of both images to AKS, each behind a public load balancer, with the full restricted Pod Security profile applied to the Chainguard workload.
6. Admission control with Kyverno: an allow-list of trusted registries and mandatory signature verification for Chainguard images. Unsigned images from Docker Hub are rejected at the API server.

Three findings worth sharing:

The CVE reduction is real, but it stops at the base image. Seven of my first twelve Chainguard findings were caused by an outdated FastAPI pin in my own requirements file. Application dependencies remain the team's responsibility.

Two issues appear only when building and running in Azure rather than locally. ACR Tasks uses Docker's legacy builder, which creates the working directory as root and breaks a non-root build stage. Kubernetes also refuses runAsNonRoot when an image declares its user by name rather than by numeric uid. Both are fixed in the repository and documented with the exact error messages.

Operational practices change. With no shell in the image, kubectl exec is no longer available and on-call runbooks need to move to kubectl debug with ephemeral containers.

As an additional exercise, the migration procedure is packaged as a Claude Code skill. Given a Dockerfile, the agent establishes a baseline scan, rewrites the file to the multi-stage Chainguard pattern, rebuilds, rescans, verifies the base image signature and reports the before-and-after comparison. Its final rule is that no vulnerability claim may be made without a fresh scan in the transcript, which I consider a sensible standard for any automated security tooling.

Full walkthrough: [article link]
Repository: https://github.com/sathpal/chainguard-aks-demo
The episode that prompted it: https://www.youtube.com/watch?v=-dMyVMPeUug&t=320s

The local part of the demo runs in about fifteen minutes with Docker installed. The AKS part takes another twenty and includes teardown. If your numbers differ from mine, that is expected: both images are rebuilt continuously, and only one of them improves over time.

#Kubernetes #Azure #AKS #ContainerSecurity #SupplyChainSecurity #DevSecOps #PlatformEngineering #Chainguard #ClaudeCode
