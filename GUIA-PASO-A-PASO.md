# Guía paso a paso: cómo implementar segmentación de red en tu equipo

> **Objetivo:** aislar tu sistema en tres zonas (pública, aplicación y datos) para que,
> si un atacante compromete el gateway o el frontend, **no pueda llegar a la base de datos**.
> Patrón aplicado: *aislamiento por zonas con límites de confianza*.

Esta guía está pensada para alguien que parte de cero. Al final tendrás un escenario
de tres servicios segmentado y verificado con cinco pruebas.

---

## 0. Antes de empezar: ¿qué es la segmentación y por qué sirve?

Por defecto, cuando levantas varios contenedores juntos, **todos se ven entre sí**.
Eso significa que si alguien entra por el servicio expuesto a internet (el gateway),
desde ahí puede intentar conectarse a la base de datos directamente.

La segmentación divide el sistema en **zonas de red separadas** y pone cada servicio
solo en las redes que realmente necesita:

| Zona            | Qué va aquí                     | Regla |
|-----------------|---------------------------------|-------|
| **Pública**     | gateway / frontend (nginx)      | Lo único expuesto a internet |
| **Aplicación**  | backend, microservicios         | Solo accesible desde el gateway |
| **Datos**       | bases de datos (PostgreSQL)     | Solo accesible desde el backend |

La clave: **el gateway y la base de datos nunca comparten una red en común**, así que
no hay forma de que uno alcance al otro. El backend es el único "puente".

**Escenario de calidad (confidencialidad):** el 100 % de los intentos de conexión
desde la zona pública hacia la zona de datos deben fallar.

---

## 1. Requisitos previos

Necesitas una máquina (tu PC o un servidor) con:

- **Docker** y **Docker Compose** instalados.
  - Verifícalo con:
    ```bash
    docker --version
    docker compose version
    ```
  - Si no los tienes: instala *Docker Desktop* (Windows/Mac) o *Docker Engine* (Linux)
    desde la documentación oficial de Docker.
- Un terminal (bash, PowerShell, etc.).
- Conexión a internet la primera vez (para descargar las imágenes `nginx` y `postgres`).

---

## 2. Estructura de archivos

Crea una carpeta para el proyecto con esta estructura:

```
mi-proyecto/
├── docker-compose.yml           # escenario segmentado (el "después")
├── docker-compose.before.yml    # escenario sin segmentar (el "antes")
├── gateway/
│   └── nginx.conf               # config del gateway
├── backend/
│   ├── Dockerfile
│   ├── server.js                # API con /health que consulta la db
│   └── package.json
└── run-tests.sh                 # script que corre las 5 pruebas
```

> Puedes copiar estos archivos del repositorio de ejemplo y luego cambiar los servicios
> por los reales de tu proyecto (tu propio frontend, tu propio backend, tu propia db).

---

## 3. El concepto central: una red por zona

En Docker Compose, una **red** es una zona. La segmentación se logra así:

1. Defines **tres redes**: `public_net`, `app_net`, `data_net`.
2. A cada servicio le asignas **solo las redes que necesita**:
   - `gateway`  → `public_net` + `app_net`   (habla con el exterior y con el backend)
   - `backend`  → `app_net` + `data_net`     (habla con el gateway y con la db)
   - `db`       → `data_net`                 (solo la zona de datos)
3. Marcas `app_net` y `data_net` como **`internal: true`** para que no tengan salida a internet.

Como `gateway` no está en `data_net` y `db` no está en `app_net`, **jamás pueden verse**.

---

## 4. Paso a paso de implementación

### Paso 4.1 — Escribe el `docker-compose.yml` segmentado

```yaml
services:
  gateway:
    image: nginx:alpine
    ports:
      - "80:80"                 # única puerta al exterior
    volumes:
      - ./gateway/nginx.conf:/etc/nginx/conf.d/default.conf:ro
    networks:
      - public_net
      - app_net
    depends_on:
      - backend

  backend:
    build: ./backend
    networks:
      - app_net
      - data_net                # ÚNICO servicio con acceso a la db
    environment:
      - DB_HOST=db
      - DB_PORT=5432
      - DB_USER=app
      - DB_PASSWORD=app_secret
      - DB_NAME=appdb
    depends_on:
      - db

  db:
    image: postgres:16-alpine
    networks:
      - data_net                # SOLO zona de datos
    environment:
      - POSTGRES_USER=app
      - POSTGRES_PASSWORD=app_secret
      - POSTGRES_DB=appdb
    # OJO: NO publicamos el puerto 5432 -> no es accesible desde afuera

networks:
  public_net:
    driver: bridge
  app_net:
    driver: bridge
    internal: true              # sin salida a internet
  data_net:
    driver: bridge
    internal: true
```

**Lo más importante de este archivo:**
- `db` **no** tiene `ports:` → no se expone al exterior (esto hace fallar la prueba 5).
- `gateway` **no** está en `data_net` → no puede llegar a la db (esto hace fallar la prueba 4).

### Paso 4.2 — Config del gateway (`gateway/nginx.conf`)

```nginx
server {
    listen 80;
    server_name _;

    location / {
        default_type application/json;
        return 200 '{"service":"gateway","status":"ok"}';
    }

    location /health {
        proxy_pass http://backend:3000/health;   # reenvía al backend
        proxy_set_header Host $host;
    }
}
```

### Paso 4.3 — Backend con endpoint `/health` (`backend/`)

`server.js` (Node.js, usa el driver `pg` para probar la conexión a la db):

```javascript
const http = require("http");
const { Client } = require("pg");

const dbConfig = {
  host: process.env.DB_HOST || "db",
  port: parseInt(process.env.DB_PORT || "5432", 10),
  user: process.env.DB_USER || "app",
  password: process.env.DB_PASSWORD || "app_secret",
  database: process.env.DB_NAME || "appdb",
  connectionTimeoutMillis: 3000,
};

async function checkDb() {
  const client = new Client(dbConfig);
  await client.connect();
  await client.query("SELECT 1");
  await client.end();
}

http.createServer(async (req, res) => {
  if (req.url === "/health") {
    try {
      await checkDb();
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ status: "ok", db: "reachable" }));
    } catch (e) {
      res.writeHead(503, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ status: "error", db: "unreachable" }));
    }
    return;
  }
  res.writeHead(200, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ service: "backend" }));
}).listen(3000, () => console.log("backend en :3000"));
```

`package.json`:

```json
{
  "name": "backend",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": { "pg": "^8.11.3" }
}
```

`Dockerfile`:

```dockerfile
FROM node:20-alpine
RUN apk add --no-cache netcat-openbsd curl
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY server.js ./
EXPOSE 3000
CMD ["node", "server.js"]
```

### Paso 4.4 — Levanta el sistema

```bash
docker compose up -d --build
```

Espera unos 10 segundos a que PostgreSQL arranque.

---

## 5. Verificación: las 5 pruebas

Estas pruebas demuestran que la segmentación funciona. Córrelas una por una.

| # | Desde → hacia      | Comando                                               | Esperado (segmentado) |
|---|--------------------|-------------------------------------------------------|-----------------------|
| 1 | Exterior → gateway | `curl localhost`                                      | Responde              |
| 2 | gateway → backend  | `docker compose exec gateway curl backend:3000/health`| Responde              |
| 3 | backend → db       | `docker compose exec backend nc -zv db 5432`          | Conecta               |
| 4 | gateway → db       | `docker compose exec gateway nc -zv db 5432`          | **Falla** ✅          |
| 5 | Exterior → db      | `nc -zv localhost 5432`                               | **Falla** ✅          |

- Las pruebas **1–3** confirman que la aplicación sigue funcionando.
- Las pruebas **4 y 5** son las que **demuestran el patrón**: el gateway no llega a la
  db y la db no es accesible desde fuera.

> **Nota:** la imagen `nginx:alpine` no trae `nc` ni `curl`. Instálalos solo para la
> prueba con:
> `docker compose exec gateway sh -c "apk add --no-cache netcat-openbsd curl"`

### Comparar con el "antes"
Para ver la diferencia, levanta primero una versión sin segmentar (todos los servicios
en la red por defecto y la db con `ports: ["5432:5432"]`). Ahí las pruebas 4 y 5
**sí conectan** → eso es justo lo inseguro que corregimos.

---

## 6. Cómo adaptarlo a TU proyecto real

1. **Reemplaza las imágenes de ejemplo** por tus servicios reales:
   - `gateway` → tu frontend o tu reverse proxy real.
   - `backend` → tu API / microservicios reales.
   - `db` → tu base de datos real (MySQL, Mongo, etc.).
2. **Conserva la regla de oro:** el servicio público y la base de datos **nunca**
   deben compartir una red.
3. **No publiques el puerto de la base de datos** (`ports:`) salvo que sea
   estrictamente necesario, y si lo haces, restringe el acceso.
4. Si tienes **varios microservicios**, agrúpalos por zona: los que necesitan la db
   van en `data_net`; los que no, se quedan en `app_net`.

---

## 7. Equivalente en otras plataformas

El mismo patrón se implementa igual en otras tecnologías:

- **Kubernetes:** usa `NetworkPolicy` para permitir/denegar tráfico entre pods por
  etiquetas (equivalente a decir "solo el backend puede hablar con la db").
- **Nube (AWS/GCP/Azure):** usa **subredes** (pública/privada) y **security groups** o
  reglas de firewall: la subred pública no tiene ruta hacia la subred de datos.
- **VMs tradicionales:** VLANs + reglas de firewall entre segmentos.

La idea es siempre la misma: **separar por zonas y permitir solo los flujos necesarios.**

---

## 8. Recomendaciones para otros equipos

- **Empieza por el diagrama:** dibuja las zonas y las flechas permitidas ANTES de
  escribir el compose. Si una flecha va del gateway a la db, está mal.
- **Principio de mínimo privilegio:** cada servicio solo en las redes que necesita.
- **Prueba el "antes" y el "después":** la mejor evidencia es mostrar las pruebas 4 y 5
  conectando sin segmentar y fallando con segmentación.
- **Usa `internal: true`** en las redes que no necesitan salir a internet.
- **No publiques puertos de la base de datos.** Si necesitas inspeccionarla en
  desarrollo, usa `docker compose exec` desde dentro, no un puerto abierto.
- **Documenta los límites de confianza** en el diagrama: deja claro cuál es el límite
  crítico (pública ↔ datos).

---

## 9. Comandos de limpieza

```bash
docker compose down            # apaga y borra los contenedores
docker compose down -v         # además borra los volúmenes (datos de la db)
```

---

¡Con esto cualquier equipo puede montar y verificar la segmentación en una hora!
