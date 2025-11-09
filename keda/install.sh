helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm install keda kedacore/keda --namespace keda --create-namespace
kubectl get pods -n keda
kubectl patch svc keda-operator-metrics-apiserver -n keda \
  -p '{"spec": {"type": "NodePort"}}'
kubectl get svc -n keda keda-operator-metrics-apiserver
curl http://localhost:31906/metrics