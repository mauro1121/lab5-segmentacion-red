# Laboratorio 5 – Segmentación de red (Roles 1 y 2)

Proyecto que implementa el patrón **aislamiento por zonas con límites de confianza**
usando Docker Compose. Si un atacante compromete el gateway, **no puede alcanzar la base de datos**.

## Patrón aplicado

| Servicio | Zona        | Redes                 | Puede conectarse a |
|----------|-------------|-----------------------|--------------------|
| gateway  | Pública     | public_net, app_net   | backend            |
| backend  | Aplicación  | app_net, data_net     | db                 |
| db       | Datos       | data_net              | — (nada)           |

**Clave:** `gateway` y `db` no comparten ninguna red; el `backend` es el único puente.

## Estructura

```
lab5/
├── antes/docker-compose.yml       # todo en una red, BD publicada en 15432 (inseguro)
├── despues/docker-compose.yml     # tres redes segmentadas (seguro)
├── gateway/                       # nginx (zona pública), proxy /api/ -> backend
│   ├── Dockerfile                 # trae curl y nc para las pruebas
│   └── nginx.conf
├── backend/                       # Node.js, GET /health consulta PostgreSQL
│   ├── Dockerfile                 # trae curl y nc para las pruebas
│   ├── server.js
│   └── package.json
├── run-tests.sh                   # corre las 5 pruebas (Linux/macOS)
├── vista-arquitectonica.svg       # diagrama de despliegue (Rol 2)
├── GUIA-PASO-A-PASO.md            # guía para implementar en otros equipos
└── SIMULAR-ATAQUE.md              # cómo simular un ataque y validar
```

## 1. Antes (sin segmentar)

```bash
cd antes
docker compose up -d --build
```

Pruebas (Linux/macOS):
```bash
curl localhost                                          # 1. Exterior -> gateway
curl localhost/api/health                               #    cadena gateway -> backend -> db
docker compose exec gateway curl -s backend:3000/health # 2. gateway -> backend
docker compose exec backend nc -zv -w 3 db 5432         # 3. backend -> db
docker compose exec gateway nc -zv -w 3 db 5432         # 4. gateway -> db  (CONECTA: problema)
nc -zv -w 3 localhost 15432                             # 5. Exterior -> db (conecta: problema)
docker compose down                                     # apagar (libera el puerto 80)
cd ..
```

## 2. Después (segmentado)

```bash
cd despues
docker compose up -d --build
```

Se repiten las mismas 5 pruebas. En el "después" las pruebas **4 y 5 fallan**.

Prueba extra (bloqueo por IP, no solo por DNS):
```bash
ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' l5-despues-db-1)
docker compose exec gateway nc -zv -w 3 "$ip" 5432      # timed out
docker compose down
```

> En Windows usa PowerShell: `curl.exe localhost`, `Test-NetConnection localhost -Port 15432`, etc.

## Resultados esperados

| # | Desde → hacia         | Antes            | Después                              |
|---|-----------------------|------------------|--------------------------------------|
| 1 | Exterior → gateway    | `gateway ok`     | `gateway ok`                         |
| 2 | gateway → backend     | `{"status":"ok","db":"up",...}` | `{"status":"ok","db":"up",...}` |
| 3 | backend → db          | succeeded        | succeeded                            |
| 4 | gateway → db          | succeeded        | **falla** (`Try again` / por IP: timed out) |
| 5 | Exterior → db (15432) | conecta          | **falla**                            |

## Snippet clave (`despues/docker-compose.yml`)

```yaml
services:
  gateway:
    ports: ["80:80"]                 # único puerto publicado
    networks: [public_net, app_net]
  backend:
    networks: [app_net, data_net]
  db:
    networks: [data_net]             # sin "ports"

networks:
  public_net: {}
  app_net:  { internal: true }       # sin salida a Internet
  data_net: { internal: true }
```

## Problemas comunes

- **Prueba 5 da conexión en el "después":** otro servicio usa ese puerto en el host.
  Por eso el "antes" publica la BD en **15432** en vez de 5432.
- **Puerto 80 ocupado:** cambia `"80:80"` por `"8080:80"` y usa `curl localhost:8080`.
- **El gateway no arranca:** nginx necesita que `backend` exista. Revisa `docker compose logs backend`.
