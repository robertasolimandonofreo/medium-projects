##https://docs.k3s.io/

curl -sfL https://get.k3s.io | sh -
sudo systemctl status k3s &> /dev/null && echo "K3s installed successfully" || echo "K3s installation failed"
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -A
