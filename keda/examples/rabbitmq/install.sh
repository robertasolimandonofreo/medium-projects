kubectl apply -f "https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml"
kubectl get pods -n rabbitmq-system
kubectl create ns rabbitmq
kubectl apply -f cluster.yaml

#UI: http://172.19.169.56:32062
#Broker: amqp://rabbitmq:rabbitmq@172.19.169.56:32662/
#Métricas Prometheus: http://172.19.169.56:31017/metrics