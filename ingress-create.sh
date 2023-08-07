helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
# helm upgrade dca0kafka-ingress ingress-nginx/ingress-nginx \
helm install dca0kafka-ingress ingress-nginx/ingress-nginx \
--version 4.7.0 \
--atomic \
--namespace kafka \
--set controller.ingressClassResource.name=kafka \
--set controller.scope.namespace=kafka \
--set controller.scope.enabled=true \
--set controller.ingressClass=nginx \
--set tcp.940=kafka-service/kafka:940 \
--set tcp.941=kafka-service/kafka:941 \
--set tcp.942=kafka-service/kafka:942 \
--set rbac.create=true \
--set-string controller.config.server-tokens=false \
--set-string controller.config.use-forwarded-headers=true \
--set controller.kind=Deployment \
--set controller.resources.limits.memory=2G \
--set controller.resources.limits.cpu=1 \
--set controller.resources.requests.memory=1M \
--set controller.resources.requests.cpu=.01 \
--set controller.config.hide-headers=Server
sleep 5 
kubectl --namespace kafka get services -o json dca0kafka-ingress-ingress-nginx-controller | jq -r '.status.loadBalancer.ingress[0].ip'
 
