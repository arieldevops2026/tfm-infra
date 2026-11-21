# tfm-infra

Infraestructura del TFM *Diseño y evaluación de una plataforma GitOps con entrega progresiva gobernada por SLO y telemetría OpenTelemetry para microservicios en Kubernetes* (UNIR, Máster en DevOps).

Crea el clúster y lo deja listo para que Argo CD despliegue todo lo demás desde [`tfm-gitops`](https://github.com/arieldevops2026/tfm-gitops).

## Estructura

```text
vagrant/
├── Vagrantfile               # VM local: Ubuntu 24.04, 4 CPU, 12 GB, IP 192.168.56.20
└── scripts/
    ├── install-k3s.sh        # K3s de un nodo con versión fijada (incluye Traefik)
    ├── bootstrap.sh          # Argo CD, Argo Rollouts, Secret de Grafana y Applications
    ├── cambiar-escenario.sh  # cambia ms-orders entre los escenarios B0, B1 y B2
    └── generar-trafico.sh    # tráfico continuo contra ms-orders
terraform/                    # (pendiente) EC2 en AWS con los mismos scripts
```

`install-k3s.sh` y `bootstrap.sh` no dependen de Vagrant: son los mismos que usará la EC2.

## Levantar el laboratorio local

Requisitos: VirtualBox 7.2.8 o superior (soporta el kernel 7.0) y Vagrant.

La carpeta `tfm-infra` debe estar junto a los demás repositorios (`tfm-gitops`, `tfm-ms-*`), porque la VM monta la carpeta que los contiene en `/tfm`.

```bash
cd vagrant
vagrant up
```

Tarda varios minutos: instala K3s, Argo CD y Argo Rollouts, y Argo CD descarga y despliega los microservicios y la observabilidad. Al final imprime las contraseñas de Grafana y de Argo CD.

| Qué | Dónde |
|---|---|
| ms-orders | `http://192.168.56.20/api/v1/orders/create` |
| Grafana | `http://192.168.56.20/grafana` (usuario `admin`) |
| Argo CD | `https://192.168.56.20:8080` (usuario `admin`), con port-forward abierto: `vagrant ssh -c "kubectl -n argocd port-forward --address 0.0.0.0 svc/argocd-server 8080:443"` |

Las contraseñas se pueden volver a leer:

```bash
vagrant ssh -c "kubectl -n observability get secret grafana-admin -o jsonpath='{.data.password}' | base64 -d; echo"
vagrant ssh -c "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
```

## Uso diario

```bash
vagrant halt      # apagar antes de apagar el equipo
vagrant up        # volver a encender (no reinstala nada)
vagrant destroy   # borrar la VM; el siguiente "vagrant up" la recrea desde cero
```

Los datos de Prometheus, Tempo, Loki y Grafana son efímeros: se pierden al reiniciar la VM.

## Escenarios y tráfico

```bash
cd vagrant/scripts
./generar-trafico.sh 20        # 20 peticiones/s (Ctrl+C para parar)
./cambiar-escenario.sh b1      # b0, b1 o b2
```

`cambiar-escenario.sh` se puede ejecutar desde el equipo: entra solo en la VM. Solo actúa si la máquina se llama `tfm-k3s`, para no usar nunca otro clúster por error. Cambiar de escenario corta `ms-orders` unos segundos: se hace entre experimentos, no durante uno.

## Versiones fijadas

| Componente | Versión | Dónde se fija |
|---|---|---|
| K3s | v1.36.6+k3s1 | `install-k3s.sh` |
| Argo CD | v3.6.2 | `bootstrap.sh` |
| Argo Rollouts | v1.10.2 | `bootstrap.sh` |
