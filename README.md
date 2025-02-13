# datafy-agent-helm

## Installation Guide

This guide will walk you through the process of adding the Datafy Helm repository and installing the `datafy-agent` on your Kubernetes cluster using Helm.

### **1. Add the Datafyio Helm Repository**

First, add the Datafy Helm repository to your Helm client:
```bash
helm repo add datafyio https://helm.datafy.io/datafy-agent
helm repo update
```

### **2. Install Datafy Agent**
The datafy-agent Helm chart is now available for installation. Run the following command to install the agent on your Kubernetes cluster:

```bash
helm install datafy-agent datafyio/datafy-agent --namespace <namespace> --create-namespace --set datafy.token=<your_token> --set datafy.version=<agent_version>
```
Replace `<namespace>` with the Kubernetes namespace where you want to install the agent, and `<your_token>` with the mandatory token for the Datafy agent.

### **3. Optional Customizations**
The datafy-agent chart allows customization through values provided in the `values.yaml` file. You can either specify values directly in the Helm install command using the `--set` flag, or you can create a values.yaml file.

Here are a few key parameters you can customize in your `values.yaml` file:

* Environment Variables for the Daemon Set
You can add environment variables to the Datafy agent by setting the `datafy.env` parameter:
```yaml
datafy:
  env:
    EXAMPLE_ENV: "example-value"
```

* Image Pull Secrets
To use private image registries, you can specify `image.pullSecrets` in your `values.yaml` file:
```yaml
image:
  pullSecrets:
    - myRegistryKeySecretName
```

* EBS-CSI Namespace
By default, the ebs-csi driver is installed in the `kube-system` namespace. If it's not installed there, you can specify a different namespace for the Datafy CSI components using the `csi.namespace` parameter:
```yaml
csi:
  namespace: <your_csi_namespace>  
```

### **4. Verify the Installation**
Once installed, verify that the datafy-agent pods are running:
```bash
kubectl get pods -n <namespace>
```

## Uninstall Guide
If you need to uninstall the datafy-agent, you can do so by running:
```bash
helm uninstall datafy-agent --namespace <namespace>
```
