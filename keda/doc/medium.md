<!-- ![KEDA](https://github.com/robertasolimandonofreo/medium-projects/blob/main/keda/doc/keda.png) -->

# Autoscaling Inteligente no Kubernetes com KEDA: Além do CPU e Memória

Se você trabalha com Kubernetes, provavelmente já se viu em uma situação incômoda: seu aplicativo está processando filas, respondendo a webhooks ou lidando com picos de tráfego, e o Horizontal Pod Autoscaler (HPA) nativo fica preso olhando só para CPU e memória. Resultado? Pods que não escalam quando deveriam ou que escalam no tempo errado.

Eu passei por isso mais vezes do que gostaria de admitir. Até descobrir que o KEDA resolve esse problema de um jeito bem elegante (e open source).

> **Código completo deste artigo:** https://github.com/robertasolimandonofreo/medium-projects/tree/main/keda

Todos os exemplos práticos que vou mostrar estão nesse repositório. Você pode clonar e testar localmente!

## O Problema Real

O HPA padrão do Kubernetes é básico demais para cenários do mundo real. Imagine que você tem:

- Uma aplicação que consome mensagens de uma fila RabbitMQ
- Um worker que processa jobs de um Redis
- Um serviço que depende de latência de uma API externa
- Um batch job que deveria escalar baseado no tamanho de um bucket S3

Em todos esses casos, CPU e memória não dizem muita coisa. A sua fila pode estar explodindo enquanto o CPU dos seus pods está em 10%. Você precisa escalar porque há trabalho na fila, não porque há calor na máquina.

Aí entra o KEDA.

## O que é KEDA?

KEDA é basicamente um autoscaler que entende eventos. Em vez de só olhar para métricas tradicionais, ele se conecta a diversas fontes e diz: "ei, tem 5 mil mensagens nessa fila, precisa de mais pods!".

A beleza é que ele suporta dezenas de scalers: RabbitMQ, Kafka, Redis, AWS SQS, Google Pub/Sub, Azure Service Bus, webhooks customizados… a lista é grande.

## Preparando o Ambiente

### Pré-requisitos

Antes de começar, você precisará de:

- K3s instalado
- Helm 3 instalado
- kubectl configurado

### Instalar K3s

Se você ainda não tem K3s instalado, execute:

```bash
curl -sfL https://get.k3s.io | sh -
sudo systemctl status k3s
```

Copiar o kubeconfig:

```bash
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
```

### Descobrir o IP do Cluster

Este é um detalhe importante! Você vai precisar do IP do seu nó para acessar os serviços expostos via NodePort.

```bash
export NODE_IP=$(kubectl get nodes -o wide | awk 'NR==2 {print $6}')
echo "NODE_IP: $NODE_IP"
```

Guarde este IP, você vai usar para acessar RabbitMQ UI, APIs e outros serviços nos próximos passos!

### Instalar Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

## Instalando o KEDA

Agora, vamos colocar KEDA no cluster:

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm install keda kedacore/keda --namespace keda --create-namespace
kubectl get pods -n keda
```

Pronto. Agora você tem dois novos recursos disponíveis: `ScaledObject` e `ScaledJob`. Vamos usar o primeiro para aplicações normais.

## Exemplo 1: Escalando por Fila RabbitMQ (Com Exemplo Real)

Vamos começar com um caso clássico: você tem workers processando mensagens de um RabbitMQ. Quanto mais mensagens na fila, mais workers você quer.

### Passo 1: Instalar o RabbitMQ Cluster Operator

```bash
kubectl apply -f "https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml"
kubectl get pods -n rabbitmq-system
```

### Passo 2: Criar o Cluster RabbitMQ

```yaml
apiVersion: rabbitmq.com/v1beta1
kind: RabbitmqCluster
metadata:
  name: rabbitmq
  namespace: rabbitmq
spec:
  replicas: 1
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
  rabbitmq:
    additionalConfig: |
      log.console.level = info
      channel_max = 1700
      default_user = rabbitmq
      default_pass = rabbitmq
      default_user_tags.administrator = true
      prometheus.tcp.port = 15692
    additionalPlugins:
      - rabbitmq_prometheus
  persistence:
    storageClassName: local-path
    storage: 1Gi
  service:
    type: NodePort
```

Criar namespace e aplicar:

```bash
kubectl create ns rabbitmq
kubectl apply -f cluster.yaml
```

### Passo 3: Criar a Fila de Teste

```bash
curl -i -u rabbitmq:rabbitmq -H "content-type: application/json" \
-XPUT http://${NODE_IP}:32062/api/queues/%2f/keda-queue \
-d '{"auto_delete":false,"durable":true}'
```

### Passo 4: Publicar Mensagens de Teste

```bash
for i in {1..20}; do
  curl -i -u rabbitmq:rabbitmq \
    -H "content-type: application/json" \
    -XPOST http://${NODE_IP}:32062/api/exchanges/%2f/amq.default/publish \
    -d '{"properties":{},"routing_key":"keda-queue","payload":"msg","payload_encoding":"string"}'
done
```

### Passo 5: Deployment do Consumer

Agora, o deployment do seu worker:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rabbit-consumer
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rabbit-consumer
  template:
    metadata:
      labels:
        app: rabbit-consumer
    spec:
      containers:
      - name: consumer
        image: busybox
        command: ["sh", "-c", "echo 'Consumidor ativo...'; sleep 3600"]
```

### Passo 6: Configurar o ScaledObject

Agora, o ScaledObject que faz a mágica:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: rabbit-consumer-scaler
  namespace: default
spec:
  scaleTargetRef:
    name: rabbit-consumer
  pollingInterval: 10
  cooldownPeriod: 30
  minReplicaCount: 1
  maxReplicaCount: 5
  triggers:
  - type: rabbitmq
    metadata:
      protocol: amqp
      queueName: keda-queue
      mode: QueueLength
      value: "5"
      host: "amqp://rabbitmq:rabbitmq@rabbitmq.rabbitmq.svc.cluster.local:5672/"
```

Traduzindo: o KEDA vai verificar a fila `keda-queue` do RabbitMQ a cada 10 segundos. Se tiver mais de 5 mensagens por pod, ele adiciona mais pods. Se tiver menos, reduz.

Então se a fila tem 20 mensagens e você já tem 1 pod, ele calcula: (20 / 5) = 4 pods. Pronto, vai criar mais 3.

**Monitorar o scaling:**

```bash
kubectl get deployment rabbit-consumer --watch
kubectl describe scaledobject rabbit-consumer-scaler
```

## Exemplo 2: Redis - Contando Itens em uma Lista (Com Implementação Real)

Agora vamos para algo um pouco diferente. Você tem uma aplicação que processa itens de uma lista Redis, e quer escalar baseado no comprimento dessa lista.

### Passo 1: Instalar Redis

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm install redis bitnami/redis \
  --namespace redis --create-namespace \
  --set auth.enabled=false \
  --set metrics.enabled=true \
  --set metrics.serviceMonitor.enabled=false
```

Verificar:

```bash
kubectl get pods -n redis
```

### Passo 2: Adicionar Itens na Lista Redis

```bash
kubectl exec -it -n redis redis-master-0 -- redis-cli LPUSH keda-list "msg1"
kubectl exec -it -n redis redis-master-0 -- redis-cli LPUSH keda-list "msg2"
kubectl exec -it -n redis redis-master-0 -- redis-cli LPUSH keda-list "msg3"
kubectl exec -it -n redis redis-master-0 -- redis-cli LPUSH keda-list "msg4"
kubectl exec -it -n redis redis-master-0 -- redis-cli LPUSH keda-list "msg5"
kubectl exec -it -n redis redis-master-0 -- redis-cli LPUSH keda-list "msg6"
```

### Passo 3: Deployment do Consumer Redis

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-consumer
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis-consumer
  template:
    metadata:
      labels:
        app: redis-consumer
    spec:
      containers:
      - name: redis-consumer
        image: busybox
        command: ["sh", "-c", "echo 'Consumidor Redis ativo'; sleep 3600"]
```

### Passo 4: ScaledObject para Redis

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: redis-consumer-scaler
  namespace: default
spec:
  scaleTargetRef:
    name: redis-consumer
  pollingInterval: 10
  cooldownPeriod: 30
  minReplicaCount: 1
  maxReplicaCount: 5
  triggers:
  - type: redis
    metadata:
      address: "redis-master.redis.svc.cluster.local:6379"
      listName: "keda-list"
      listLength: "5"
```

Simples assim. O KEDA vai contar quantos itens tem na lista e dividir por 5. Se tiver 30 itens, escalará para 6 pods (30 / 5 = 6).

**Monitorar:**

```bash
kubectl get deployment redis-consumer --watch
```
Todos os pods criados pelo KEDA:

![PODS](https://github.com/robertasolimandonofreo/medium-projects/blob/main/keda/doc/pod.png)

## Exemplo 3: Escalando por Métrica Customizada (Prometheus)

Agora vem a parte mais poderosa: você pode escalar baseado em qualquer métrica que você consiga exportar para o Prometheus.

Imagine que você quer escalar uma aplicação de video processing baseado no tempo médio de processamento. Se a latência está acima de 5 segundos, você quer mais workers.

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: custom-metric-scaler
spec:
  scaleTargetRef:
    name: video-processor
  minReplicaCount: 2
  maxReplicaCount: 30
  triggers:
  - type: prometheus
    metadata:
      serverAddress: http://prometheus.monitoring:9090
      query: |
        avg(video_processing_duration_seconds) > bool 5
      threshold: "1"
```

## Outras Possibilidades do KEDA

Importante mencionar: o KEDA suporta muito mais escalers além dos que implementamos aqui! Você pode escalar baseado em:

- **Filas de mensagens:** Kafka, AWS SQS, Google Pub/Sub, Azure Service Bus
- **Bancos de dados:** PostgreSQL, MySQL, MongoDB
- **Métricas customizadas:** Prometheus, Datadog, New Relic
- **Webhooks customizados:** Qualquer fonte de dados que você conseguir exposar via API

Neste artigo, focaremos nos exemplos práticos que temos no repositório (RabbitMQ e Redis), mas a lógica e padrão se aplicam para qualquer um dos scalers suportados.

**Confira a lista completa em:** https://keda.sh/docs/2.18/scalers/

A verdadeira flexibilidade vem quando você combina múltiplos escaladores. Por exemplo, você quer que sua aplicação escale se QUALQUER UMA dessas condições for verdadeira:

```yaml
triggers:
- type: rabbitmq
  metadata:
    protocol: amqp
    queueName: critical-jobs
    mode: QueueLength
    value: "10"
    host: "amqp://rabbitmq:rabbitmq@rabbitmq:5672/"
- type: redis
  metadata:
    address: redis-master.redis.svc.cluster.local:6379
    listName: backup-queue
    listLength: "20"
```

Dessa forma, seus workers escalam se a fila crítica do RabbitMQ estourar OU se a lista do Redis ultrapassar o limite. Você fica coberto em múltiplos cenários.

## Dicas Práticas que Aprendi no Caminho

### 1. Use `minReplicaCount` com cuidado

Se você seta `minReplicaCount: 0`, a aplicação pode ser completamente descalada quando não há eventos. Isso economiza recursos, mas pode adicionar latência quando a próxima onda de eventos chega. 

Para aplicações críticas, mantenha pelo menos 1 ou 2 réplicas:

```yaml
minReplicaCount: 2
```

Para economia de recursos, é aceitável usar 0, mas prepare-se para um cold start.

### 2. Entenda o `cooldownPeriod`

Por padrão, o KEDA espera 300 segundos (5 minutos) antes de desescalar. Você pode mudar isso em `cooldownPeriod`, mas tenha cuidado com "thrashing" - sua aplicação pode subir e descer constantemente se as métricas oscilarem.

```yaml
cooldownPeriod: 30
```

### 3. Ajuste o `pollingInterval`

O intervalo padrão é 15 segundos. Para escalers mais sensíveis, reduza para 10 ou até 5 segundos, mas considere o overhead na fonte de dados:

```yaml
pollingInterval: 10
```

### 4. Monitore o KEDA

O KEDA expõe suas próprias métricas em `:8080/metrics`. Monitore quantas vezes seus scalers falham para conectar às fontes de dados. Se o RabbitMQ fica indisponível, o KEDA não consegue escalar corretamente.

```bash
kubectl patch svc keda-operator-metrics-apiserver -n keda \
  -p '{"spec": {"type": "NodePort"}}'
kubectl get svc -n keda keda-operator-metrics-apiserver
```

### 5. Valores de threshold precisam de ajuste

Não existe valor mágico. Comece conservador, observe o comportamento da sua aplicação por uma semana e ajuste. 

Se seus workers RabbitMQ processam 50 mensagens por minuto em média, um threshold de 5 mensagens por pod faz sentido. Mas isso é específico do seu caso:

- **RabbitMQ:** 5-20 mensagens por pod (teste primeiro!)
- **Redis:** 5-10 itens por pod
- **SQS:** 50-100 mensagens por pod

### 6. Combine com PodDisruptionBudgets

Se você vai escalar agressivamente, use PDB para evitar que o Kubernetes derrube muitos pods ao mesmo tempo durante updates:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: consumer-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: rabbit-consumer
```

### 7. Sempre defina Requests e Limits

Recursos inadequados fazem o scheduler ficar confuso:

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

## Resolvendo Problemas Comuns

### Scaler não está disparando

Verifique os logs do KEDA:

```bash
kubectl logs -n keda deployment/keda-operator
kubectl logs -n keda deployment/keda-operator-metrics-apiserver
```

Verifique o status do ScaledObject:

```bash
kubectl describe scaledobject rabbit-consumer-scaler
```

Geralmente é problema de permissão ou conexão à fonte de dados.

### Escalando muito lentamente

Reduza o `pollingInterval` no trigger (padrão é 15s):

```yaml
pollingInterval: 5
```

Mas não coloque muito baixo ou você sobrecarrega o RabbitMQ/Redis/Prometheus.

### Pods criados, mas aplicação não processa

Geralmente é porque a aplicação não consegue se conectar à fila. Verifique as credenciais e a conectividade de rede:

```bash
kubectl exec -it deployment/rabbit-consumer -- sh
# Dentro do pod, testar conexão com RabbitMQ
```

Verifique também os logs da aplicação:

```bash
kubectl logs deployment/rabbit-consumer --tail=50
```

### Problemas com autenticação no RabbitMQ

Se a senha está errada na configuração do KEDA, o scaler simplesmente não vai conectar. Verifique que está usando o mesmo usuário e senha definidos no cluster:

```yaml
host: "amqp://rabbitmq:rabbitmq@NODE_IP:32662/"
```

## Conclusão

KEDA transformou a forma como eu penso em autoscaling. Não é mais sobre "quanto calor tem?", é sobre "quanto trabalho há para fazer?".

## Os Ganhos Reais em Produção

A curva de aprendizado é rápida, mas os ganhos em eficiência são reais e mensuráveis:

- ✅ **Menos overprovisioning** - Você não mantém 10 pods esperando picos que não vêm
- ✅ **Melhor uso de recursos** - Escala apenas quando necessário, economizando CPU, memória e storage
- ✅ **Melhor resposta a picos de tráfego** - Reage em tempo real ao volume real de trabalho, não a métricas genéricas
- ✅ **Economia na conta de cloud** - Redução significativa em custos de infraestrutura (já vi redução de 40-60% em alguns casos)

## Por Que Isso Economiza Tanto?

Imagine um cenário real:

**Sem KEDA (usando só HPA com CPU):**
- 10 pods rodando o tempo todo (mesmo sem trabalho)
- Cold start de 30s quando chega pico
- Overprovisioning para cobrir imprevistos
- Custo: ~$500/mês em 10 pods

**Com KEDA (escalando por fila):**
- 1-2 pods em repouso
- Sobe para 10 em segundos quando fila explode
- Desce automaticamente quando fila esvazia
- Custo: ~$100-150/mês
- **Economia: ~70%**

Se você ainda está usando só CPU e memória para escalar, eu fortemente recomendo experimentar KEDA. Seu cluster (e sua conta de cloud) vão agradecer.

**Todos os scalers disponíveis você encontra aqui:** https://keda.sh/docs/2.18/scalers/

**Código de todos os meus artigos** (incluindo este) está disponível em: https://github.com/robertasolimandonofreo/medium-projects

Já usou KEDA em produção? Qual foi sua experiência? Deixa um comentário aí! 🚀