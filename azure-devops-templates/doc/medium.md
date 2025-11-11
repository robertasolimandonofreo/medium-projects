# Azure DevOps com Templates Reutilizáveis: Como Estruturar CI/CD sem Repetir Código

Se você trabalha com Kubernetes, ECR e precisa fazer deploy de backend em Go ou frontend em Node.js, provavelmente já se viu em uma situação incômoda: cada novo projeto gera um pipeline diferente, código duplicado em cada repositório, configurações espalhadas e difíceis de manter.

Eu passei por isso mais vezes do que gostaria de admitir. Até descobrir que usar templates reutilizáveis no Azure DevOps resolveu esse problema.

> **Todos os exemplos práticos deste artigo estão disponíveis em:** https://github.com/robertasolimandonofreo/medium-projects/azure-devops-templates

Você pode clonar, adaptar e usar em seus projetos!

---

## O Problema Real

Imagine que você tem 5 projetos diferentes:
- 3 backends em Go que precisam fazer build Docker, push para ECR e deploy em Kubernetes
- 2 frontends em Node.js que precisam fazer build, lint, push para S3 e invalidar CloudFront

**Sem templates reutilizáveis, o que acontece:**

```
projeto-1/
├── azure-pipelines.yml (300 linhas)
├── .github/workflows/...

projeto-2/
├── azure-pipelines.yml (300 linhas - código duplicado!)
├── .github/workflows/...

projeto-3/
├── azure-pipelines.yml (300 linhas - código duplicado!)
```

Você termina com:
- ❌ Código duplicado em cada repositório
- ❌ Atualizações precisam ser feitas em vários lugares
- ❌ Inconsistências entre projetos
- ❌ Difícil de manter quando algo muda na infraestrutura

**Com templates reutilizáveis:**

```
pipeline-templates/ (repositório central)
├── kubernetes.yml        # Template genérico para backend + K8s
├── cloudfront.yml        # Template genérico para frontend + S3
├── templates/
│   ├── sonar.yml        # SAST compartilhado
│   ├── docker.yml       # Build Docker compartilhado
│   ├── clean.yml        # Limpeza compartilhada
│   └── ...

projeto-1/ (simples!)
├── ci/
│   └── pipeline.yml     # Apenas 30 linhas chamando template

projeto-2/ (simples!)
├── ci/
│   └── pipeline.yml     # Apenas 30 linhas chamando template

projeto-3/ (simples!)
├── ci/
│   └── pipeline.yml     # Apenas 30 linhas chamando template
```

Resultado:
- ✅ Código reutilizável em todos os projetos
- ✅ Uma única fonte de verdade para CI/CD
- ✅ Atualizações em um único lugar
- ✅ Consistência garantida
- ✅ Onboarding de novos projetos em minutos

---

## Por Que Azure DevOps?

Existem várias opções (GitHub Actions, GitLab CI, Jenkins, CircleCI), mas por que escolher Azure DevOps para isso?

### 1. **Templates são First-Class Citizens**

Diferente de GitHub Actions que mistura YAML com lógica, Azure DevOps foi feito desde o início para trabalhar com templates. É natural e poderoso:

```yaml
# Azure DevOps - templates são perfeitos para reutilização
resources:
  repositories:
    - repository: pipeline
      type: git
      name: ci/pipeline
      endpoint: azure-devops-repo

stages:
  - template: kubernetes.yml@pipeline
```

Compare com GitHub Actions que precisam de workarounds para reutilizar workflows. Azure DevOps foi feito para isso.

### 2. **Múltiplos Ambientes Nativamente**

Azure DevOps entende conceitos como:
- **Variable Groups** - Variáveis compartilhadas entre pipelines
- **Service Connections** - Credenciais reutilizáveis (Kubernetes, AWS, Azure, etc)
- **Agent Pools** - Especificar qual agent rodará qual job
- **Approvals** - Aproveações entre stages

Isso tudo integrado, sem plugins ou workarounds.

### 3. **YAML + UI Equilibrados**

Você pode fazer tudo por YAML (infrastructure-as-code), mas também tem UI intuitiva para casos simples. O melhor dos dois mundos.

### 4. **Integração com Trabalho**

Azure DevOps não é só CI/CD. Tem Repos (Git), Boards (Kanban), Artifacts (Package repository) e Test Plans. Tudo integrado. Se você já usa para planejamento, usar também para CI/CD é natural.

### 5. **Custo-Benefício**

- Para open source e pequenos times: gratuito
- Pricing transparente por agent paralelo
- Não tem limite de repositórios
- Não tem limite de pipelines

---

## A Estrutura: Templates Reutilizáveis

Vou mostrar como estruturamos templates em um repositório central chamado `ci/pipeline`.

### Repositório Central de Templates

```
ci/pipeline/ (repositório central)
├── kubernetes.yml              # Template principal para backend
├── cloudfront.yml              # Template principal para frontend
├── templates/
│   ├── sonar.yml              # SAST + Testes
│   ├── cloudlogin.yml         # Auth AWS
│   ├── docker.yml             # Build Docker
│   ├── dockerpull.yml         # Pull imagens ECR
│   ├── kubernetes.yml         # Deploy K8s
│   ├── cloudfront-deploy.yml  # Deploy S3 + CloudFront
│   └── clean.yml              # Limpeza
└── README.md
```

### Como Funciona

Cada template é um arquivo YAML que define uma série de steps que podem ser reutilizados. Por exemplo, o template `sonar.yml` faz SAST e testes:

```yaml
# kubernetes.yml - Template principal para backend
stages:
  - stage: Build_Backend
    jobs:
      - job: Backend_Pipeline
        steps:
          - checkout: self
          - template: templates/sonar.yml
          - template: templates/cloudlogin.yml
            parameters:
              env: prod
          - template: templates/docker.yml
          - template: templates/kubernetes.yml
            parameters:
              env: prod
          - template: templates/clean.yml
```

Cada projeto que usa este template não precisa se preocupar com os detalhes. Basta referenciar:

```yaml
# seu-projeto/ci/pipeline.yml (projeto específico)
resources:
  repositories:
    - repository: pipeline
      type: git
      name: ci/pipeline
      endpoint: azure-devops-repo

stages:
  - template: kubernetes.yml@pipeline
```

É isso. O resto vem dos templates compartilhados.

---

## Exemplo Real: Backend em Go + Kubernetes

Vamos ver um case real de como isso funciona.

### Seu Projeto (simples!)

```
seu-servico-api/
├── ci/
│   └── pipeline.yml
├── cd/
│   ├── prod/
│   │   └── deployment.yaml
│   └── stage/
│       └── deployment.yaml
├── cmd/
│   └── main.go
├── Dockerfile
├── Makefile
└── go.mod
```

### Pipeline do Seu Projeto

**arquivo: `ci/pipeline.yml`**

```yaml
name: $(Build.BuildId)

trigger:
  branches:
    include:
      - stage
      - main
  paths:
    exclude:
      - cd/*
      - ci/*
      - Dockerfile

variables:
  - group: variables
  - name: appname
    value: 'seu-servico'
  - name: apppath
    value: '.'
  - name: language
    value: 'go'
  - name: version
    value: '1.23.0'
  - name: testun
    value: 'yes'
  - name: infra
    value: 'kube'
  - name: squad
    value: 'seu-squad'

resources:
  repositories:
    - repository: pipeline
      type: git
      name: ci/pipeline
      ref: refs/heads/main
      endpoint: azure-devops-repo

stages:
  - template: kubernetes.yml@pipeline
```

Vê só? 30 linhas. Todo o resto vem do template compartilhado.

### Seu Dockerfile

```dockerfile
FROM seu-account-id.dkr.ecr.us-east-1.amazonaws.com/golang:1.23.0-alpine3.20 AS builder

WORKDIR /app
COPY go.mod go.sum ./

RUN apk add --no-cache upx git make \
    && go env -w GOPRIVATE=github.com/robertasolimandonofreo/seu-repo \
    && go mod download

COPY . .
RUN rm -rf .env

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-s -w" \
    -o main ./cmd/main.go && \
    upx main

FROM seu-account-id.dkr.ecr.us-east-1.amazonaws.com/alpine:3.12.1
WORKDIR /root/
COPY --from=builder /app/main .
RUN apk add --no-cache ca-certificates tzdata
CMD ["./main"]
```

### Seu Makefile

```makefile
COVERAGE_DIR := coverage

.PHONY: setup-tools test-coverage coverage-report

setup-tools:
	@echo "Instalando ferramentas..."
	go install github.com/axw/gocov/gocov@v1.0.0
	go install github.com/jstemmer/go-junit-report@v1.0.0
	go install github.com/AlekSi/gocov-xml@v1.1.0
	curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | \
		sh -s -- -b $(go env GOPATH)/bin v1.61.0

test-coverage:
	@mkdir -p $(COVERAGE_DIR)
	go test -v -json ./... \
		-covermode=count \
		-coverprofile=$(COVERAGE_DIR)/coverage.out \
		-coverpkg=$$(go list ./... | grep -v '/tests/' | paste -sd "," -) \
		| tee $(COVERAGE_DIR)/test-output.txt

coverage-report:
	@echo "Gerando relatórios..."
	go-junit-report < $(COVERAGE_DIR)/test-output.txt > $(COVERAGE_DIR)/unit-report.xml
	gocov convert $(COVERAGE_DIR)/coverage.out > $(COVERAGE_DIR)/demo-coverage.json
	gocov-xml < $(COVERAGE_DIR)/demo-coverage.json > $(COVERAGE_DIR)/coverage-report.xml
```

### Seus Deployments

**`cd/prod/deployment.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: seu-servico
spec:
  replicas: 3
  selector:
    matchLabels:
      app: seu-servico
      env: prod
  template:
    metadata:
      labels:
        app: seu-servico
        env: prod
    spec:
      containers:
      - name: seu-servico
        image: seu-account-id.dkr.ecr.us-east-1.amazonaws.com/seu-servico-prod:latest
        ports:
        - containerPort: 8080
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
```

**`cd/stage/deployment.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: seu-servico-stage
spec:
  replicas: 1
  selector:
    matchLabels:
      app: seu-servico
      env: stage
  template:
    metadata:
      labels:
        app: seu-servico
        env: stage
    spec:
      containers:
      - name: seu-servico
        image: seu-account-id.dkr.ecr.us-east-1.amazonaws.com/seu-servico-stage:latest
        ports:
        - containerPort: 8080
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
```

Pronto. É isso que você precisa. O resto vem dos templates.

---

## Exemplo Real: Frontend em Node.js + S3

Agora vamos ver como é simples para frontend também.

### Seu Projeto

```
seu-frontend/
├── ci/
│   └── pipeline.yml
├── src/
├── package.json
├── vite.config.js
└── .eslintrc.js
```

### Pipeline

**arquivo: `ci/pipeline.yml`**

```yaml
name: $(Build.BuildId)

trigger:
  branches:
    include:
      - stage
      - main

variables:
  - group: variables
  - name: appname
    value: 'seu-frontend'
  - name: language
    value: 'node'
  - name: version
    value: '18.18.0'
  - name: testun
    value: 'yes'
  - name: infra
    value: 'cloudfront'
  - name: squad
    value: 'seu-squad'

resources:
  repositories:
    - repository: pipeline
      type: git
      name: ci/pipeline
      endpoint: azure-devops-repo

stages:
  - template: cloudfront.yml@pipeline
```

De novo, 30 linhas. A complexidade toda está nos templates.

### Seu package.json

```json
{
  "scripts": {
    "build": "npm run build:admin && npm run build:widget",
    "build:admin": "vite build --outDir dist/admin",
    "build:widget": "vite build --config vite.widget.config.js --outDir dist/widget",
    "lint": "eslint --ext .js,.vue src",
    "test:coverage": "vitest run --coverage"
  },
  "devDependencies": {
    "vite": "^4.3.0",
    "eslint": "^8.0.0",
    "vitest": "^0.33.0",
    "@vitest/coverage-v8": "^0.33.0"
  }
}
```

É isso. O template cuida do resto.

---

## Como os Templates Funcionam (Internamente)

Agora vou te mostrar o que acontece dentro dos templates. Essa é a verdadeira mágica.

### Template: `templates/sonar.yml`

Este template roda SAST (análise de segurança) e testes unitários:

```yaml
# SAST com Trivy
- task: CmdLine@2
  displayName: 'SAST - Trivy Scan'
  inputs:
    script: |
      trivy clean --all
      trivy repo . --db-repository public.ecr.aws/aquasecurity/trivy-db \
        --format json -o trivy.json
      trivy plugin install github.com/umax/trivy-plugin-sonarqube@v0.2.2
      trivy sonarqube trivy.json > sast.json

# Testes unitários (Go)
- task: CmdLine@2
  displayName: 'Unit Tests - Go'
  condition: eq(variables.language, 'go')
  inputs:
    script: |
      make setup-tools
      make test-coverage
      make coverage-report

# Testes unitários (Node.js)
- task: CmdLine@2
  displayName: 'Unit Tests - Node.js'
  condition: eq(variables.language, 'node')
  inputs:
    script: |
      npm install
      npm run test:coverage

# Upload para SonarQube
- task: CmdLine@2
  displayName: 'SonarQube Analysis'
  inputs:
    script: |
      sonar-scanner \
        -Dsonar.projectKey=$(appname) \
        -Dsonar.host.url=$(SONAR_HOST_URL) \
        -Dsonar.login=$(SONAR_TOKEN) \
        -Dsonar.sources=. \
        -Dsonar.externalIssuesReportPaths=sast.json
```

Note como usa **variáveis** como `$(language)` para adaptar o comportamento!

### Template: `templates/docker.yml`

Build da imagem Docker e push para ECR:

```yaml
- task: CmdLine@2
  displayName: 'Build Docker Image'
  inputs:
    script: |
      set -e
      docker build -f $(Dockerfile) \
        -t $(appname):$(Build.BuildId) .
      
      # Tag com repositório ECR
      docker tag $(appname):$(Build.BuildId) \
        $(subs_id).dkr.ecr.$(region).amazonaws.com/$(appname)-${{ parameters.env }}:$(Build.BuildId)
      
      # Login no ECR
      aws ecr get-login-password --region $(region) | \
        docker login --username AWS --password-stdin \
        $(subs_id).dkr.ecr.$(region).amazonaws.com
      
      # Criar repositório se não existir
      aws ecr create-repository \
        --repository-name $(appname)-${{ parameters.env }} \
        --image-scanning-configuration scanOnPush=true || true
      
      # Push
      docker push $(subs_id).dkr.ecr.$(region).amazonaws.com/$(appname)-${{ parameters.env }}:$(Build.BuildId)

    workingDirectory: $(Build.Repository.LocalPath)/$(apppath)
```

Usa variáveis do Azure DevOps como `$(Build.BuildId)` automaticamente!

### Template: `templates/kubernetes.yml`

Deploy em Kubernetes:

```yaml
- task: CmdLine@2
  displayName: 'Configure kubeconfig'
  inputs:
    script: |
      aws eks update-kubeconfig \
        --region $(region) \
        --name ${{ parameters.env }} \
        --profile ${{ parameters.env }}

- task: CmdLine@2
  displayName: 'Deploy to Kubernetes'
  inputs:
    script: |
      new_image=$(subs_id).dkr.ecr.$(region).amazonaws.com/$(appname)-${{ parameters.env }}:$(Build.BuildId)
      
      # Atualizar deployment com a nova imagem
      sed -i "s|image: .*|image: ${new_image}|" cd/${{ parameters.env }}/deployment.yaml
      
      # Apply no cluster
      kubectl apply -f cd/${{ parameters.env }}/deployment.yaml
      
      # Commit e push para o repositório (GitOps!)
      git config user.name "ci-bot"
      git config user.email "ci@empresa.com"
      git add cd/${{ parameters.env }}/deployment.yaml
      git commit -m "Deploy v$(Build.BuildNumber)"
      git push origin HEAD:${{ parameters.env }}
```

Note como **usa parâmetros** passados pelo pipeline! (`${{ parameters.env }}`)

---

## Por Que Isso é Tão Poderoso?

### 1. **DRY (Don't Repeat Yourself)**

Antes: Código duplicado em 5 repositórios, cada mudança é 5x mais trabalho

Depois: Código em um único lugar, mudança é feita uma vez e beneficia todos

### 2. **Consistência Garantida**

Todos os projetos usam o mesmo template. Significa que:
- ✅ Mesmo padrão de SAST em todos
- ✅ Mesma estratégia de build
- ✅ Mesma lógica de deploy
- ✅ Ninguém pode "fazer diferente"

### 3. **Manutenção Centralizada**

Quando sua infraestrutura muda (ECR endpoint, cluster Kubernetes, SonarQube host), você atualiza em um único lugar e todos os projetos automaticamente usam a nova config.

### 4. **Onboarding Rápido**

Novo projeto precisando de CI/CD? Copia 30 linhas, pronto. Ninguém precisa entender toda a complexidade de SAST, Docker, Kubernetes. Está abstraído.

### 5. **Evolução Segura**

Quer testar uma nova ferramenta (mudança de Docker para Podman, por exemplo)? Testa no template. Se funcionar, todos os projetos ganham a melhoria. Se não funcionar, reverte uma vez e todos voltam.

---

## Diagrama do Fluxo

```
┌─────────────────────────────────────────────────────────────┐
│                   Seu Repositório                           │
│  (apenas 30 linhas de pipeline.yml)                        │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ Referencia
                       ▼
┌─────────────────────────────────────────────────────────────┐
│        ci/pipeline (Repositório Central)                │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ kubernetes.yml (Template Principal)                 │  │
│  │  ├─ Chama templates/sonar.yml     (SAST)           │  │
│  │  ├─ Chama templates/cloudlogin    (AWS auth)       │  │
│  │  ├─ Chama templates/docker.yml    (Build)          │  │
│  │  └─ Chama templates/kubernetes.yml (Deploy)        │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ cloudfront.yml (Template Principal)                │  │
│  │  ├─ Chama templates/sonar.yml     (SAST)           │  │
│  │  ├─ Chama templates/cloudlogin    (AWS auth)       │  │
│  │  └─ Chama templates/cloudfront-deploy.yml (S3)     │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ templates/ (Biblioteca de Steps)                    │  │
│  │  ├─ sonar.yml                                       │  │
│  │  ├─ cloudlogin.yml                                  │  │
│  │  ├─ docker.yml                                      │  │
│  │  ├─ kubernetes.yml                                  │  │
│  │  ├─ cloudfront-deploy.yml                           │  │
│  │  └─ clean.yml                                       │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                       ▲
                       │ Executa
                       │
┌──────────────────────┴──────────────────────────────────────┐
│              Azure DevOps Agent                             │
│  (Docker, Go, Node.js, kubectl, AWS CLI, etc)            │
└────────────────────────────────────────────────────────────┘
```

---

## Setup Prático: Como Começar

### Passo 1: Criar Repositório de Templates

```bash
# No Azure DevOps
# Novo repositório: ci/pipeline
```

### Passo 2: Configurar Variable Group

No Azure DevOps: `Pipelines` > `Library` > `Variable groups`

```
Nome: variables

AWS_ACCOUNT_ID = seu-id
AWS_REGION = us-east-1
ECR_REPO_PROD = seu-servico-prod
SONAR_HOST_URL = https://sonar.empresa.com
SONAR_TOKEN = squ_abc...
```

### Passo 3: Configurar Service Connections

No Azure DevOps: `Project Settings` > `Service connections`

```
kubernetes-prod  (tipo: Kubernetes)
kubernetes-stage (tipo: Kubernetes)
```

### Passo 4: No Seu Projeto, Criar o Pipeline

**arquivo: `ci/pipeline.yml`**

```yaml
name: $(Build.BuildId)

trigger:
  branches:
    include:
      - stage
      - main

variables:
  - group: variables
  - name: appname
    value: 'seu-servico'
  - name: language
    value: 'go'
  # ... outras variáveis

resources:
  repositories:
    - repository: pipeline
      type: git
      name: ci/pipeline
      endpoint: azure-devops-repo

stages:
  - template: kubernetes.yml@pipeline
```

### Passo 5: Fazer Push

```bash
git add ci/pipeline.yml cd/prod/deployment.yaml cd/stage/deployment.yaml
git commit -m "Add CI/CD pipeline"
git push origin stage
```

Pronto! Azure DevOps vai disparar o pipeline automaticamente.

---

## Troubleshooting Comum

### Pipeline não encontra o template

**Erro:** `The template file 'kubernetes.yml@pipeline' could not be found in the repository`

**Solução:** Verificar que o repositório `ci/pipeline` está definido corretamente em `resources`. O `endpoint` (service connection) deve estar correto:

```yaml
resources:
  repositories:
    - repository: pipeline
      type: git
      name: ci/pipeline
      endpoint: azure-devops-repo  # Verificar esse nome!
```

### Variáveis não estão sendo substituídas

**Erro:** Seu pipeline roda mas as variáveis como `$(appname)` não são substituídas

**Solução:** Garantir que você está usando interpolação correta:
- `$(variavel)` para referências simples
- `${{ parameters.variavel }}` para parâmetros de templates
- `${{ variables.variavel }}` para variáveis dentro de templates

### Deploy falha no Kubernetes

**Erro:** `error: unable to recognize "cd/prod/deployment.yaml": no matches for kind "Deployment"`

**Solução:** Verificar que:
1. kubectl está autenticado: `kubectl cluster-info`
2. O arquivo YAML está correto: `kubectl apply -f cd/prod/deployment.yaml --dry-run`
3. Namespace existe: `kubectl create ns default` (ou seu namespace)

---

## Boas Práticas

### 1. **Versionamento Semântico para Templates**

Use tags de release para versões estáveis:

```yaml
resources:
  repositories:
    - repository: pipeline
      type: git
      name: ci/pipeline
      ref: refs/tags/v1.0.0  # Use tags, não main!
      endpoint: azure-devops-repo
```

### 2. **Documentação Clara**

Cada template deve ter comentários explícitos:

```yaml
# Template: kubernetes.yml
# Responsabilidade: Orquestra pipeline completo para backend em Go + Kubernetes
# Requer variáveis: appname, language, version, testun
# Requer Variable Group: variables
# Requer Service Connections: kubernetes-prod, kubernetes-stage
```

### 3. **Testes Locais**

Antes de colocar em produção, teste o template localmente:

```bash
# Validar YAML
az pipelines validate \
  --file ci/pipeline.yml \
  --repository-id seu-projeto

# Executar pipeline manualmente no Azure DevOps para verificar
```

### 4. **Gradual Rollout**

Se for mudar templates, faça em fases:

1. Teste com um projeto piloto
2. Depois com 2-3 projetos
3. Por fim, rolle para todos

### 5. **Manter Histórico**

Sempre faça commit de mudanças em templates:

```bash
git log --oneline ci/pipeline

# Resultado
abc1234 Upgrade Go 1.23.0 -> 1.24.0
def5678 Add Trivy scanning
ghi9012 Fix Docker build timeout
```

---

## Comparação: Com vs Sem Templates

### Sem Templates

**Tempo para adicionar novo projeto:** 2-3 dias
- Copiar pipeline de outro projeto
- Adaptá-lo para o novo serviço
- Testar tudo
- Descobrir que algo está quebrado

**Tempo para atualizar infraestrutura:** 2-3 horas
- Editar 5 repositórios diferentes
- Testar cada um
- Corrigir inconsistências

### Com Templates

**Tempo para adicionar novo projeto:** 15 minutos
- Criar arquivo pipeline.yml com 30 linhas
- Colocar deployment.yaml em cd/prod e cd/stage
- Push
- Pronto!

**Tempo para atualizar infraestrutura:** 5 minutos
- Editar template compartilhado
- Testar em um projeto
- Todos os outros ganham a mudança automaticamente

**Economia:** 94% de tempo em cada novo projeto + 98% de tempo em cada mudança

---

## Conclusão

Templates reutilizáveis no Azure DevOps não são só uma boa prática de engenharia. São uma **obrigação** se você quer escalar.

A diferença é brutal:

**Sem templates:**
- 5 projetos = 5x código duplicado
- Cada mudança = revisitar 5 places
- Cada bug = corrigir em 5 places
- Cada novo eng = aprender 5 variações diferentes

**Com templates:**
- 5 projetos = 1x template + 5x configuração mínima
- Cada mudança = 1 place
- Cada bug = 1 fix
- Cada novo eng = "use esse template"

Se você ainda está copiando/colando pipelines entre repositórios, é hora de parar.

Crie um repositório de templates, concentre a complexidade lá, e deixe seus projetos focarem no que importa: código de negócio.

---

## Recursos

- **Código completo:** https://github.com/robertasolimandonofreo/medium-projects/azure-devops-templates
- **Documentação Azure DevOps:** https://docs.microsoft.com/en-us/azure/devops/pipelines/
- **Templates YAML:** https://docs.microsoft.com/en-us/azure/devops/pipelines/process/templates
- **Variable Groups:** https://docs.microsoft.com/en-us/azure/devops/pipelines/library/variable-groups
- **Service Connections:** https://docs.microsoft.com/en-us/azure/devops/pipelines/library/service-endpoints

---

## Próximas Etapas

Se você implementou templates e quer ir além:

1. **Adicionar aprovações:** Configure aprovações automáticas entre stages
2. **Notificações:** Slack, Teams ou email em caso de falha
3. **Dashboards:** Monitore sucesso/falha de pipelines (Devlake é uma boa opção, vou criar um artigo sobre isso)
4. **Security scanning:** Adicione verificações de SAST mais rigorosas