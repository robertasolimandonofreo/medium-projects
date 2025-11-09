##https://docs.k3s.io/
#install k3s
curl -sfL https://get.k3s.io | sh -
sudo systemctl status k3s &> /dev/null && echo "K3s installed successfully" || echo "K3s installation failed"
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -A
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
export NODE_IP=$(kubectl get nodes -o wide | awk 'NR==2 {print $6}')
echo "NODE_IP: $NODE_IP"
#install helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash