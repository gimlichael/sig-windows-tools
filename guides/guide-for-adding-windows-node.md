
# Adding Windows nodes

You can use Kubernetes to run a mixture of Linux and Windows nodes, so you can mix Pods that run on Linux on with Pods that run on Windows. This is a guide on how to register Windows nodes to your cluster.

## Warning

> The instructions and scripts in the directory DO NOT configure a CNI solution for Windows nodes running containerd.
There is a work-in-progress PR to assist in this at https://github.com/kubernetes-sigs/sig-windows-tools/pull/239

## Before you begin

Your Kubernetes server must be at or later than version 1.22. To check the version, enter `kubectl version`.

- Obtain a [Windows Server 2019 license](https://www.microsoft.com/en-us/cloud-platform/windows-server-pricing) (or higher) in order to configure the Windows node that hosts Windows containers. If you are using VXLAN/Overlay networking you must have also have [KB4489899](https://support.microsoft.com/help/4489899) installed.

- A Linux-based Kubernetes kubeadm cluster in which you have access to the control plane (see [Creating a single control-plane cluster with kubeadm](https://kubernetes-docsy-staging.netlify.app/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)).

## Objectives

- Register a Windows node to the cluster
- Configure networking so Pods and Services on Linux and Windows can communicate with each other

## Getting Started: Adding a Windows Node to Your Cluster

### Networking Configuration

Once you have a Linux-based Kubernetes control-plane node you are ready to choose a networking solution.

#### Configuring Flannel with rancher

1. Prepare Kubernetes control plane for Flannel

Some minor preparation is recommended on the Kubernetes control plane in our cluster. It is recommended to enable bridged IPv4 traffic to iptables chains when using Flannel. The following command must be run on all Linux nodes:

```bash
sudo sysctl net.bridge.bridge-nf-call-iptables=1
```

2. Download & configure Flannel for Linux

Download the most recent Flannel manifest:

```bash
wget https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
```

Modify the `net-conf.json` section of the flannel manifest in order to set the VNI to 4096 and the Port to 4789. It should look as follows:

```json
net-conf.json: |
    {
      "Network": "10.244.0.0/16",
      "Backend": {
        "Type": "vxlan",
        "VNI" : 4096,
        "Port": 4789
      }
    }
```

> **Note:** The VNI must be set to 4096 and port 4789 for Flannel on Linux to interoperate with Flannel on Windows. See the [VXLAN documentation](https://github.com/coreos/flannel/blob/master/Documentation/backends.md#vxlan). for an explanation of these fields.

> **Note:** To use L2Bridge/Host-gateway mode instead change the value of `Type` to `"host-gw"` and omit `VNI` and `Port`.

3. Apply the Flannel manifest and validate

Let's apply the Flannel configuration:

```bash
kubectl apply -f kube-flannel.yml
```

After a few minutes, you should see all the pods as running if the Flannel pod network was deployed.

```bash
kubectl get pods -n kube-flannel
```

The output should include the Linux flannel DaemonSet as running:

```
NAMESPACE NAME READY STATUS RESTARTS AGE
...
kube-system kube-flannel-ds-54954 1/1 Running 0 1m
```

4. Add Windows Flannel and kube-proxy DaemonSets

Now you can add Windows-compatible versions of Flannel and kube-proxy. In order to ensure that you get a compatible version of kube-proxy, you'll need to substitute the tag of the image. The following example shows usage for Kubernetes v1.24.3, but you should adjust the version for your own deployment.

```bash
curl -L https://github.com/kubernetes-sigs/sig-windows-tools/releases/latest/download/kube-proxy.yml | sed 's/VERSION/v1.24.3/g' | kubectl apply -f -
kubectl apply -f https://github.com/kubernetes-sigs/sig-windows-tools/releases/latest/download/flannel-overlay.yml
```

>  **Note** If you are using another version of kubernetes on your windows node, change v1.24.3 with your own version .
> To find your version of kubernetes run the following command:
> `kubeadm version`

5. Apply kube-flannel-rbac.yml from sig-windows-tools/kubeadm/flannel
Next you will need to apply the configuration that allows flannel to spawn pods and keep them running:

```bash
git clone https://github.com/kubernetes-sigs/sig-windows-tools
kubectl apply -f sig-windows-tools/kubeadm/flannel/kube-flannel-rbac.yml
```

### Joining a Windows worker node

> **Note:** All code snippets in Windows sections are to be run in a PowerShell environment with elevated permissions (Administrator) on the Windows worker node.

1. Install ContainerD, wins, kubelet, and kubeadm.

```PowerShell
git clone https://github.com/kubernetes-sigs/sig-windows-tools
cd .\sig-windows-tools\kubeadm\scripts\

# Install ContainerD
.\Install-Containerd.ps1

# Install wins, kubelet and kubeadm
.\PrepareNode.ps1 -KubernetesVersion v1.24.3 -ContainerRuntime containerD
```

> **Note** If you want to install another version of kubernetes, modify v1.24.3 with the version you want to install

2. Run `kubeadm` to join the node

> **Note** Before joining the node, copy the file from /run/flannel/subnet.env to your windows machine to C:\run\flannel\subnet.env
> You will need to create the folders for it

Use the command that was given to you when you ran `kubeadm init` on a control plane host. If you no longer have this command, or the token has expired, you can run `kubeadm token create --print-join-command` (on a control plane host) to generate a new token and join command.

> **Note:** Do not forget to add `--cri-socket "npipe:////./pipe/containerd-containerd" --v=5` at the end of the join command, if you use ContainerD

3. Install kubectl for windows (optional)

For more information about it : https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/

#### Verifying your installation

You should now be able to view the Windows node in your cluster by running:

```bash
kubectl get nodes -o wide
```

If your new node is in the `NotReady` state it is likely because the flannel image is still downloading. You can check the progress as before by checking on the flannel pods in the `kube-system` namespace:

```shell
kubectl -n kube-system get pods -l app=flannel
```

Once the flannel Pod is running, your node should enter the `Ready` state and then be available to handle workloads.