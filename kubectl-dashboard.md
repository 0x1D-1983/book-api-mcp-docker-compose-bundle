# Access the Kubernetes Dashboard

## Step 1: Start the kubectl proxy:
```
kubectl proxy
```

## Step 2: Open your browser and navigate to:
http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/

Alternative (if the above doesn't work):
http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/kubernetes-dashboard/proxy/

Note: You'll need to authenticate. You can either:
Use a service account token (recommended for production)
Or skip authentication if your cluster allows it (not recommended)

To get a service account token:
```
kubectl -n kubernetes-dashboard create token admin-user
```

Or if you have a service account already:
```
kubectl -n kubernetes-dashboard get secret $(kubectl -n kubernetes-dashboard get sa admin-user -o jsonpath="{.secrets[0].name}") -o jsonpath="{.data.token}" | base64 -d
```

The kubectl proxy command will keep running in your terminal. Press Ctrl+C to stop it when you're done.

