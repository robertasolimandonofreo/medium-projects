kubectl apply -f "https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml"
kubectl get pods -n rabbitmq-system
kubectl create ns rabbitmq
kubectl apply -f cluster.yaml

#UI: http://CLUSTER_IP:32062
#Broker: amqp://rabbitmq:rabbitmq@CLUSTER_IP:32662/
#Métricas Prometheus: http://CLUSTER_IP:31017/metrics