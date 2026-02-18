# Adding capacity to the OpenShift hub cluster

If GitOps pods (e.g. `openshift-gitops-applicationset-controller`) stay **Pending** with **"Too many pods"**, the cluster or node has no room for more pods. Use one of the options below.

---

## Option 1: Add worker nodes (recommended)

Use this when the cluster has the **Machine API** (installer-provisioned clusters, most cloud and IPI installs).

**1. List machine sets (hub cluster):**

```bash
oc get machinesets -n openshift-machine-api
```

**2. Scale a worker MachineSet to add one or more nodes:**

```bash
# Replace <machineset_name> with the name from step 1 (e.g. cluster-9nvg4-worker-us-east-1a)
oc scale machineset <machineset_name> -n openshift-machine-api --replicas=2
```

Or set replicas in the spec:

```bash
oc edit machineset <machineset_name> -n openshift-machine-api
# Set spec.replicas: 2 (or higher). Save and exit.
```

**3. Wait for new nodes to be Ready:**

```bash
oc get nodes -w
```

When the new node is `Ready`, the scheduler can place the ApplicationSet controller and other Pending pods there.

---

## Option 2: Increase max pods per node (single-node or fixed node count)

Use this when you **cannot add nodes** (e.g. single-node cluster, sandbox) and the node has enough CPU/memory but has hit the **max pods per node** limit.

**1. Create a KubeletConfig to raise the pod limit:**

```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: KubeletConfig
metadata:
  name: increase-max-pods
spec:
  machineConfigPoolSelector:
    matchLabels:
      pools.operator.machineconfiguration.openshift.io/worker: ""
  kubeletConfig:
    maxPods: 250
```

If your hub node is **control-plane/master** only (no worker pool), or you have a single node with mixed roles, target the master pool instead:

```yaml
  machineConfigPoolSelector:
    matchLabels:
      pools.operator.machineconfiguration.openshift.io/master: ""
```

Check which pool your node belongs to: `oc get nodes -l node-role.kubernetes.io/worker` and `oc get nodes -l node-role.kubernetes.io/master`.

**2. Apply and wait for the config to roll out:**

```bash
oc apply -f kubeletconfig-increase-max-pods.yaml
oc get machineconfigpools
# Wait until UPDATED=true and DEGRADED=false for the relevant pool.
```

**3. Recheck pods:**

```bash
oc get pods -n openshift-gitops
```

Raising `maxPods` too high on a small node can cause memory or CPU pressure; 250 is a common default. If the node is very small, prefer adding a node (Option 1) or reducing other workloads.

---

## Verify after adding capacity

```bash
oc get pods -n openshift-gitops
# openshift-gitops-applicationset-controller should become Running

kubectl get applications -n openshift-gitops
# Six nfl-wallet Applications should appear after the controller runs
```
