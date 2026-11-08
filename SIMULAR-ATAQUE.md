# Cómo simular un ataque para probar la segmentación

> **Idea central:** no "hackeas" nada de verdad. Te metes DENTRO del gateway
> (como si ya lo hubieras comprometido) e intentas, desde ahí, alcanzar la base
> de datos. Si **todos** esos intentos fallan, la segmentación funciona y se
> cumple el escenario de calidad: *el 100 % de los intentos desde la zona
> pública hacia la zona de datos fallan*.

El atacante que nos preocupa es alguien que **ya tomó control del gateway/frontend**
(el único servicio expuesto a internet). La pregunta es: desde ahí, ¿puede llegar a la db?

---

## 0. Preparación

Levanta el escenario segmentado y entra "como atacante" al gateway:

```bash
docker compose up -d --build
sleep 10

# Instalamos herramientas de ataque DENTRO del gateway (solo para la prueba)
docker compose exec gateway sh -c "apk add --no-cache netcat-openbsd curl postgresql-client bind-tools 2>/dev/null"

# Abrimos una shell dentro del gateway: a partir de aquí actuamos como el atacante
docker compose exec gateway sh
```

> Todo lo que sigue en las secciones 1–5 se ejecuta **dentro de esa shell del gateway**.

---

## 1. Reconocimiento: ¿la db siquiera existe para mí?

Un atacante primero intenta resolver y descubrir la base de datos.

```sh
# ¿Puedo resolver el nombre 'db'?
nslookup db
getent hosts db
```

**Resultado esperado (segmentado):** el nombre `db` **no se resuelve** desde el gateway,
porque `db` vive en `data_net` y el gateway no está en esa red. Si ni siquiera puede
resolver el host, ya es una victoria del patrón.

---

## 2. Ataque directo al puerto de la base de datos (TCP 5432)

```sh
# Intento de conexión al puerto de PostgreSQL
nc -zv db 5432
```

**Resultado esperado:** **FALLA** (timeout o "bad address" / "host unreachable").
Equivale a la **prueba 4** de la tabla del laboratorio. Este es el intento más típico:
el atacante quiere abrir una conexión directa a la base de datos y no puede.

---

## 3. Intento de login real a PostgreSQL

Aunque conociera el usuario y la contraseña, no debería poder ni conectarse.

```sh
# Intento de autenticarse contra la base de datos
PGPASSWORD=app_secret psql -h db -U app -d appdb -c "SELECT 1;"
```

**Resultado esperado:** **FALLA** con un error de conexión (no "contraseña incorrecta",
sino que **ni siquiera alcanza** el servidor). Esto demuestra que, aunque el atacante
robara las credenciales, la segmentación de red lo detiene antes.

---

## 4. Intento de exfiltración de datos

Simula que el atacante quiere robar datos de la db.

```sh
# Intento de volcar una tabla / listar bases de datos
PGPASSWORD=app_secret psql -h db -U app -d appdb -c "\l"
PGPASSWORD=app_secret pg_dump -h db -U app appdb > /tmp/robo.sql
```

**Resultado esperado:** **FALLA**. No hay ruta de red hacia la db, así que no se puede
extraer nada. El archivo `/tmp/robo.sql` queda vacío o el comando da error de conexión.

---

## 5. Escaneo de puertos (opcional)

El atacante intenta descubrir qué hay en la zona de datos:

```sh
# Escaneo rápido de puertos típicos sobre el host 'db'
for p in 5432 3306 6379 27017; do nc -zv -w 2 db $p 2>&1; done
```

**Resultado esperado:** todos fallan. El gateway no tiene visibilidad de `data_net`.

Sal de la shell del gateway cuando termines:
```sh
exit
```

---

## 6. Prueba desde fuera del contenedor (atacante externo)

Simula a alguien en internet que intenta golpear la base de datos directamente,
sin pasar por los contenedores:

```bash
# Desde tu máquina (fuera de Docker)
nc -zv localhost 5432
```

**Resultado esperado:** **FALLA** (prueba 5). Como no publicamos el puerto 5432 de la db,
no hay nada escuchando desde afuera.

---

## 7. Control: el camino legítimo SÍ funciona

Para demostrar que no "rompimos" la aplicación, repite los mismos ataques pero
**desde el backend** (que sí tiene permiso de hablar con la db):

```bash
docker compose exec backend nc -zv db 5432                       # CONECTA (prueba 3)
docker compose exec backend sh -c "PGPASSWORD=app_secret psql -h db -U app -d appdb -c 'SELECT 1;'"   # FUNCIONA
```

Y la app completa responde a través del gateway:

```bash
curl localhost/health      # responde {"status":"ok","db":"reachable"}
```

Esto prueba lo importante: **la segmentación bloquea al atacante pero NO a la aplicación.**

---

## 8. Tabla resumen del "ataque"

| Acción del atacante                  | Desde      | Resultado esperado | Qué demuestra |
|--------------------------------------|------------|--------------------|---------------|
| Resolver el host `db`                | gateway    | No resuelve        | La db es invisible para la zona pública |
| `nc -zv db 5432`                     | gateway    | **Falla**          | No hay ruta de red a la db |
| Login `psql` a la db                 | gateway    | **Falla**          | Ni con credenciales se puede conectar |
| `pg_dump` (exfiltración)             | gateway    | **Falla**          | No se pueden robar datos |
| `nc -zv localhost 5432`              | exterior   | **Falla**          | La db no está publicada al exterior |
| `nc -zv db 5432`                     | backend    | **Conecta**        | El flujo legítimo sigue funcionando |
| `curl localhost/health`              | exterior   | **Responde**       | La aplicación sigue operativa |

---

## 9. Cómo capturar la evidencia

Guarda la salida de cada intento en un archivo de log para el PDF:

```bash
{
  echo "### Ataque desde el gateway (debe fallar) ###"
  docker compose exec -T gateway nc -zv db 5432
  echo "### Login a la db desde el gateway (debe fallar) ###"
  docker compose exec -T gateway sh -c "PGPASSWORD=app_secret psql -h db -U app -d appdb -c 'SELECT 1;'"
  echo "### Flujo legitimo desde el backend (debe conectar) ###"
  docker compose exec -T backend nc -zv db 5432
} 2>&1 | tee evidencia-ataque.txt
```

Toma capturas de pantalla de los intentos **fallidos** (prueba 4 y 5) y del
intento **exitoso** desde el backend: esa comparación es la evidencia más contundente.

---

## Importante (ética)

Esto es una simulación **en tu propio entorno de laboratorio**, contra contenedores
que tú mismo levantaste. Nunca ejecutes estas técnicas contra sistemas que no te
pertenecen o sin autorización explícita.
