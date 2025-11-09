helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm install redis bitnami/redis \
  --namespace redis --create-namespace \
  --set auth.enabled=false \
  --set metrics.enabled=true \
  --set metrics.serviceMonitor.enabled=false
kubectl get pods -n redis
kubectl exec -it -n redis redis-master-0 -- redis-cli LPUSH keda-list "msg1"
kubectl exec -it -n redis redis-master-0 -- redis-cli LPUSH keda-list "msg2"
kubectl exec -it -n redis redis-master-0 -- redis-cli LPUSH keda-list "msg3"
kubectl exec -it -n redis redis-master-0 -- redis-cli LPUSH keda-list "msg4"
kubectl exec -it -n redis redis-master-0 -- redis-cli LPUSH keda-list "msg5"
kubectl exec -it -n redis redis-master-0 -- redis-cli LPUSH keda-list "msg6"