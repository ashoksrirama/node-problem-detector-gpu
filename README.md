# GPU Support for node-problem-detector

This customized version of node-problem-detector has support for checking gpu health and gpu count and report the status upstream so that appropriate actions can be taken.

To build the image, run the below command with appropraite NVIDIA and node-problem-detector versions

```shell
docker build --build-arg="NPD_TAG=v0.8.14" -t npd-gpu:npd-v0.8.14-cuda-12.3 .
```

## Solution Walkthrough

### Prerequisites

* AWS Account
* [Amazon EKS Cluster](https://docs.aws.amazon.com/eks/latest/userguide/create-cluster.html) with below addons
    - [ClusterAutoScaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler/cloudprovider/aws) / [Karpenter](https://github.com/aws/karpenter)
    - [Managed Nodegroup](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html) or [NodePool](https://karpenter.sh/docs/concepts/nodepools/) with NVIDIA GPU nodes
    - [nvidia-device-plugin](https://github.com/NVIDIA/k8s-device-plugin) or [gpu-operator](https://github.com/NVIDIA/gpu-operator) (recommended)
* [kubectl](https://kubernetes.io/docs/tasks/tools/)
* [helm] (https://helm.sh/docs/intro/install/)

### Deploy the node-problem-detector in EKS Cluster

```shell
helm repo add deliveryhero https://charts.deliveryhero.io/
helm install --generate-name deliveryhero/node-problem-detector --values npd-gpu-values.yaml --namespace kube-system
```

Validate the Daemon pods are running:

```shell
kubectl --namespace=kube-system get pods -l "app.kubernetes.io/name=node-problem-detector" -o wide
```

node-problem-detector runs the [check_gpu.sh](config/check_gpu.sh) as configured in [gpu-monitor.json](config/gpu-monitor.json) and reports any issues by setting the `GPUProblem` NodeCondition on the worker node.

Now, lets install Draino to watch for `GPUProblem` NodeCondition and automatically cordon and drain the node

You can verify the condition added to the nodes:

```shell
kubectl get node -o custom-columns='NODE_NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status,GPUProblem:.status.conditions[?(@.type=="GPUProblem")].status,INSTANCE-TYPE:.metadata.labels.node\.kubernetes\.io/instance-type,AZ:.metadata.labels.topology\.kubernetes\.io/zone,VERSION:.status.nodeInfo.kubeletVersion,OS-IMAGE:.status.nodeInfo.osImage,INTERNAL-IP:.metadata.annotations.alpha\.kubernetes\.io/provided-node-ip'

NODE_NAME                                    READY   GPUProblem   INSTANCE-TYPE   AZ           VERSION               OS-IMAGE         INTERNAL-IP
ip-10-0-101-160.us-west-2.compute.internal   True    Unknown      m5.xlarge       us-west-2a   v1.28.1-eks-43840fb   Amazon Linux 2   10.0.101.160
ip-10-0-133-159.us-west-2.compute.internal   True    Unknown      m5.xlarge       us-west-2b   v1.28.1-eks-43840fb   Amazon Linux 2   10.0.133.159
ip-10-0-158-235.us-west-2.compute.internal    True    False        g5.4xlarge      us-west-2b   v1.28.2-eks-a5df82a   Amazon Linux 2   10.0.158.235
ip-10-0-174-218.us-west-2.compute.internal   True    Unknown      m5.xlarge       us-west-2c   v1.28.1-eks-43840fb   Amazon Linux 2   10.0.174.218
ip-10-0-160-21.us-west-2.compute.internal    True    False        g5.4xlarge      us-west-2a   v1.28.2-eks-a5df82a   Amazon Linux 2   10.0.160.21
```

Non-GPU nodes will have `GPUProblem` as `Unknown` and for GPU nodes it will be set to `True / False` based on underlying GPU Health.

### Deploy the Draino in EKS Cluster

Draino automatically drains Kubernetes nodes based on labels and node conditions. Nodes that match all of the supplied labels and any of the supplied node conditions will be cordoned immediately and drained after a configurable `drain-buffer` time. Draino is intended for use alongside the Kubernetes Node Problem Detector and Cluster Autoscaler / Karpenter.

```shell
kubectl apply -f draino.yaml
```

Validate the deployment:

```shell
kubectl --namespace=kube-system get pods -l "component=draino" -o wide
```

### Deploy sample application

```shell
kubectl apply -f gpu-burn.yaml
```

Now, we have all components configured on the cluster to monitor and recover the worker nodes for any GPU errors. When there is an issue, you would notice following behavior:

node-problem-detector would log any issues with the GPU:

```shell
kubectl logs -f -n kube-system <<NPD POD NAME>>
```

```output
...
I1031 19:56:15.266737       1 plugin.go:282] End logs from plugin {Type:permanent Condition:GPUProblem Reason:GPUsAreDown Path:/config/plugin/check_gpu.sh Args:[] TimeoutString:0xc00057f560 Timeout:1m0s}
I1031 19:56:15.266806       1 custom_plugin_monitor.go:280] New status generated: &{Source:ntp-custom-plugin-monitor Events:[{Severity:warn Timestamp:2023-10-31 19:56:15.266783693 +0000 UTC m=+1141.179657898 Reason:GPUsAreDown Message:Node condition GPUProblem is now: True, reason: GPUsAreDown, message: "Unable to determine the device handle for GPU0000:00:1B.0: Unknown Error\nnvidia-"}] Conditions:[{Type:GPUProblem Status:True Transition:2023-10-31 19:56:15.266783693 +0000 UTC m=+1141.179657898 Reason:GPUsAreDown Message:Unable to determine the device handle for GPU0000:00:1B.0: Unknown Error
nvidia-}]}
...
```

`GPUProblem` NodeCondition will be set to `True` by the node-problem-detector

```shell
kubectl get node -o custom-columns='NODE_NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status,GPUProblem:.status.conditions[?(@.type=="GPUProblem")].status,INSTANCE-TYPE:.metadata.labels.node\.kubernetes\.io/instance-type,AZ:.metadata.labels.topology\.kubernetes\.io/zone,VERSION:.status.nodeInfo.kubeletVersion,OS-IMAGE:.status.nodeInfo.osImage,INTERNAL-IP:.metadata.annotations.alpha\.kubernetes\.io/provided-node-ip'

NODE_NAME                                    READY   GPUProblem   INSTANCE-TYPE   AZ           VERSION               OS-IMAGE         INTERNAL-IP
ip-10-0-101-160.us-west-2.compute.internal   True    Unknown      m5.xlarge       us-west-2a   v1.28.1-eks-43840fb   Amazon Linux 2   10.0.101.160
ip-10-0-133-159.us-west-2.compute.internal   True    Unknown      m5.xlarge       us-west-2b   v1.28.1-eks-43840fb   Amazon Linux 2   10.0.133.159
ip-10-0-158-235.us-west-2.compute.internal    True    True        g5.4xlarge      us-west-2b   v1.28.2-eks-a5df82a   Amazon Linux 2   10.0.158.235
ip-10-0-174-218.us-west-2.compute.internal   True    Unknown      m5.xlarge       us-west-2c   v1.28.1-eks-43840fb   Amazon Linux 2   10.0.174.218
ip-10-0-160-21.us-west-2.compute.internal    True    False        g5.4xlarge      us-west-2a   v1.28.2-eks-a5df82a   Amazon Linux 2   10.0.160.21
```

As soon as the `GPUProblem` condition is set to `True`, Draino will kick in and start cordoning and draining the node to evict all existing pods from it 

```shell
kubectl logs -f -n kube-system deployment/draino
```

```output
{"level":"info","ts":1698899483.5951388,"caller":"kubernetes/eventhandler.go:272","msg":"Cordoned","node":"ip-10-0-158-235.us-west-2.compute.internal"}
{"level":"info","ts":1698899483.632801,"caller":"kubernetes/eventhandler.go:308","msg":"Drain scheduled ","node":"ip-10-0-158-235.us-west-2.compute.internal","after":1698899494.5970578}
{"level":"info","ts":1698899912.4616818,"caller":"kubernetes/drainSchedule.go:154","msg":"Drained","node":"ip-10-0-158-235.us-west-2.compute.internal"}
```

```shell
kubectl get nodes -o wide
```

```output
NAME                                         STATUS                     ROLES    AGE     VERSION
ip-10-0-101-160.us-west-2.compute.internal   Ready                      <none>   7d10h   v1.28.1-eks-43840fb
ip-10-0-133-159.us-west-2.compute.internal   Ready                      <none>   7d10h   v1.28.1-eks-43840fb
ip-10-0-158-235.us-west-2.compute.internal   Ready, SchedulingDisabled  <none>   9h      v1.28.2-eks-a5df82a
ip-10-0-174-218.us-west-2.compute.internal   Ready                      <none>   7d10h   v1.28.1-eks-43840fb
ip-10-0-160-21.us-west-2.compute.internal    Ready                      <none>   9h      v1.28.2-eks-a5df82a
```

As the pods evict from the unhealthy node, they went into `Pending` state, ClusterAutoScaler/Karpenter will look for these pending pods and launch a new GPU instance into the cluster and destroy the existing node as it is drained.

```shell
kubectl get pods
```
```output
NAME                        READY   STATUS      RESTARTS   AGE 
gpu-burn-6bb999c6b9-28blw   1/1     Pending     0          50s    
gpu-burn-6bb999c6b9-gdfb4   1/1     Running     0          9h  
```

```shell
kubectl get node -o custom-columns='NODE_NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status,GPUProblem:.status.conditions[?(@.type=="GPUProblem")].status,INSTANCE-TYPE:.metadata.labels.node\.kubernetes\.io/instance-type,AZ:.metadata.labels.topology\.kubernetes\.io/zone,VERSION:.status.nodeInfo.kubeletVersion,OS-IMAGE:.status.nodeInfo.osImage,INTERNAL-IP:.metadata.annotations.alpha\.kubernetes\.io/provided-node-ip'
```
```output
NODE_NAME                                    READY   GPUProblem   INSTANCE-TYPE   AZ           VERSION               OS-IMAGE         INTERNAL-IP
ip-10-0-101-160.us-west-2.compute.internal   True    Unknown      m5.xlarge       us-west-2a   v1.28.1-eks-43840fb   Amazon Linux 2   10.0.101.160
ip-10-0-133-159.us-west-2.compute.internal   True    Unknown      m5.xlarge       us-west-2b   v1.28.1-eks-43840fb   Amazon Linux 2   10.0.133.159
ip-10-0-142-13.us-west-2.compute.internal    True    False        g5.4xlarge      us-west-2b   v1.28.2-eks-a5df82a   Amazon Linux 2   10.0.142.13
ip-10-0-174-218.us-west-2.compute.internal   True    Unknown      m5.xlarge       us-west-2c   v1.28.1-eks-43840fb   Amazon Linux 2   10.0.174.218
ip-10-0-160-21.us-west-2.compute.internal    True    False        g5.4xlarge      us-west-2a   v1.28.2-eks-a5df82a   Amazon Linux 2   10.0.160.21
```

YaY!! We successfully demonstrated how we can customize the node-problem-detector image to monitor GPU health and use draino and ClusterAutoScaler/Karpenter to automatically recover from those failures.

### Cleanup

* Destroy the EKS Cluster to stop incurring additional cost.

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file.