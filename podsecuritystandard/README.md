# Pod Security Standards

## Overview

Pod Security Standards (PSS) are Kubernetes guidelines that define a set of security profiles for pods to ensure they adhere to best practices for security and compliance. The standards are not policies themselves but rather well known groupings of pod restrictions.

Three PSS levels are defined from least to most restrictive:
1. Privileged - No restrictions on pod security settings. Pods have full access to the host and its resources
1. Baseline - Blocks known privilege escalation paths, allows common container functionality, and disallows dangerous features (e.g., hostPID, hostNetwork)
> For a full list of restrictions enforced by the Baseline profile, see the [Pod Security Standards Documentation](https://kubernetes.io/docs/concepts/security/pod-security-standards/#baseline)
1. Restricted - Enforces best practices for hardening by requiring non-root users, read-only file systems, and disallowing privilege escalation and host access
> For a full list of restrictions enforced by the Restricted profile, see the [Pod Security Standards Documentation](https://kubernetes.io/docs/concepts/security/pod-security-standards/#restricted)

The PSSs can be enforced in a cluster using a built-in or third party Pod Security Admission Controller. The admission controller validates pod specifications against the selected PSS level for a given namespace. Namespaces can be labeled to specify which PSS level to enforce, allowing for flexible security configurations across different workloads.

Restrictions apply to the following functionalities, capabilities, and settings (non exhaustive list):
- **Namespace sharing**
    Pods can share the namespace (PID, IPC, network) of the host. Sharing the host PID or IPC namespace allows a pod to see or interact with host processes, which can lead to privilege escalation or data leakage. Carefully evaluate the need for namespace sharing and avoid it unless absolutely necessary.

    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: secure-pod
    spec:
      hostNetwork: false   # Do not share host network
      hostPID: false       # Do not share host process namespace
      hostIPC: false       # Do not share host IPC
    containers:
      - name: app
        image: nginx:latest
    ```
- **Privilege escalation**
    A container process can gain more privileges than its parent process. Even if a container runs as a non-root user, it may still be able to escalate its privileges to root user (via `setuid` or `setgid`). Setting `privileged` in the SecurityContext to false helps mitigate this risk.
- **Linux capabilities**
    Linux capabilities that are fine-grained ways to grant piviliges to processes without giving then full root/host access. Some of the units of root privileges include:
      - `NET_ADMIN`: Allows changing network settings (routes, interfaces)
      - `SYS_ADMIN`: Very powerful capability that allows mounting filesystems and changing kernel settings
      - `CHOWN`: Allows changing file ownership
    Even though the are smaller units of privilege, they can still be misused to escalate privileges or compromise the host. The Baseline and Restricted profiles drop a set of dangerous capabilities by default. As a best practice, it is best to drop all capabilities and only add back the ones that are absolutely necessary for the application to function.

    Example of dropping all capabilities:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: web-server
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
          - containerPort: 80
        securityContext:
          privileged: false                # Do NOT run privileged
          runAsNonRoot: true              # Avoid root user
          allowPrivilegeEscalation: false # Prevent privilege escalation
          capabilities:
            drop: ["ALL"]                 # Drop all capabilities first
            add: ["NET_BIND_SERVICE"]     # Add only what’s needed
    ```
- **Volume types**
    Kubernetes supports various volume types (e.g. `hostPath`, `emptyDir`, `configMap`, `secret`), some of which can expose the host filesystem or sensitive data to pods. For example, `hostPath` volumes allow pods to access files on the host (e.g., /etc, /var/run/docker.sock), which can lead to privilege escalation or container escape.
- **Host port access**
    Pods can bind to specific host ports, bypassing Kubernetes networking isolation. This can lead to port conflicts and expose services directly to the host network, increasing the attack surface.
    Use ClusterIP or NodePort services instead of direct host port bindings whenever possible.
- **AppArmor/SELinux**
    These are Linux kernel security modules that provide mandatory access control (MAC) for processes. They help contain the actions of a pod and limit its access to system resources. The Restricted profile requires pods to have appropriate AppArmor or SELinux profiles to enforce confinement.
- **Proc/ mounts**
    The `/proc` filesystem provides process and system information. Allowing pods to mount `/proc` with write access can lead to information leakage or manipulation of system settings. The Restricted profile ensures that `/proc` mounts are read-only.
- **Running as non-root**
    Running containers as the root user (UID 0) can lead to privilege escalation and compromise of the host system. The Restricted profile requires pods to run as non-root users to minimize the risk of privilege escalation.
- **Seccomp**
    Seccomp (Secure Computing Mode) is a Linux kernel feature that restricts the system calls a process can make. By using seccomp profiles, you can limit the attack surface of a container by allowing only necessary system calls. Without Seccomp, containers can invoke dangerous syscalls like mount or ptrace. The Restricted profile requires pods to use a seccomp profile to enhance security.
- **Sysctls**
    Sysctls are kernel parameters that modify networking, memory, etc. at the node or namespace level. Allowing pods to set unsafe sysctls can lead to system instability or security vulnerabilities. Containers could modify host networking, enable traffic interception, or facilitate DoS attacks. The Restricted profile restricts the use of unsafe sysctls.

## Common Pitfalls

### Allowing Overly Permissive Controls

For simplicity or inadvertently, developers may configure pods with overly permissive security settings, such as running as root, using privileged containers, or enabling host networking. These configurations can expose the cluster to significant security risks. The default settings for fields may not align with the desired security posture. For example, the default value for `allowPrivilegeEscalation` is true. Most containers do not require privilege escalation, but may unintentionally have this capability. Additionally, users may set `privileged` to true for simplicity when in reality they only need a specific capability. `privileged: true` grants all capabilities and unrestricted host access while adding a capability only grants a specific privilege.

Consider a developer who configured a pod for debugging to run as `privileged: true` and `runAsUser: 0`, and then forgot to revert the change before deploying to production. They may have added the capabilities in their development environment or namespace to more easily troubleshoot networking, storage, or kernel-related issues. They also many have wanted access to tools like `tcpdump` or `strace` that require elevated privileges.

```yaml
# Modified pod for debugging
apiVersion: v1
kind: Pod
metadata:
  name: privileged-debug
  namespace: prod
spec:
  containers:
    - name: nginx
      image: nginx:latest
      securityContext:
        privileged: true
        runAsUser: 0
```
Applying the Pod
```sh
kubectl apply -f privileged-debug.yaml
```
With access to the pod, the attack would have full root access to the host and could compromise the entire cluster.

```sh
kubectl exec -it privileged-debug -- sh
# Now inside the container with root access

whoami                # Shows root
id                    # UID 0
ls /dev               # Full device access
mount -t proc proc /host/proc   # Can mount host paths
```
To avoid future pitfalls, the user call apply the Baseline or Restricted profile to the pod/namespace.

```sh
kubectl label namespace prod \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest
```

Reapply the pod after labeling the namespace results in a rejection due to non-compliance with the Restricted profile.

```sh
kubectl apply -f privileged-debug.yaml
```

To fix the issue, the user must modify the pod to comply with the Restricted profile by removing privileged access and ensuring it runs as a non-root user while only allowing necessary capabilities.

```yaml
# Suppose the pod only needs to bind to port 80. Use NET_BIND_SERVICE instead of full privileged mode:
apiVersion: v1
kind: Pod
metadata:
  name: privileged-debug
  namespace: prod
spec:
  containers:
    - name: nginx
      image: nginx:latest
      ports:
        - containerPort: 80
      securityContext:
        privileged: false
        runAsNonRoot: true
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
          add: ["NET_BIND_SERVICE"]
```

### Not Enforcing Pod Security Standards

Kubernetes provides a built-in pod security admission controller to enforce the standards in namespaces. Relying on manual reviews or external tools can lead to inconsistent enforcement and potential security gaps. Either configure the built-in admission controller or use a third-party solution to ensure consistent enforcement of Pod Security Standards across all namespaces.

The following manifest blocks pods in the `my-baseline-namespace` namespace that do not comply with the Baseline profile, while generating audits and warnings for violations of the Restricted profile. The policies are also set to the v1.34 version of the Pod Security Standards.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: my-baseline-namespace
  labels:
    pod-security.kubernetes.io/enforce: baseline # Required to enforce Baseline profile
    pod-security.kubernetes.io/enforce-version: v1.34
    pod-security.kubernetes.io/audit: restricted # Adds an audit annotation to Restricted profile violations
    pod-security.kubernetes.io/audit-version: v1.34
    pod-security.kubernetes.io/warn: restricted # Surfaces a user-facing warning on Restricted profile violations
    pod-security.kubernetes.io/warn-version: v1.34
```

For more examples and details on configuring the built-in Pod Security Admission Controller, see the [Enforce Pod Security Standards by Configuring the Built-in Admission Controller](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-admission-controller/) guide and [Enforce Pod Security Standards Using Namespace Labels](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/) guide.

## Resources
- [Pod Security Standards Documentation](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/)
- [Enforcing Pod Security Standards](https://kubernetes.io/docs/setup/best-practices/enforcing-pod-security-standards/)
- [Enforce Pod Security Standards by Configuring the Built-in Admission Controller](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-admission-controller/)
- [Enforce Pod Security Standards Using Namespace Labels](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels)
