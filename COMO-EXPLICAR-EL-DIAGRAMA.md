# Cómo explicar la Vista de Despliegue (Rol 2)

Esta guía te sirve para entender el diagrama y para presentarlo en el PDF o en la
sustentación. Está escrita en lenguaje sencillo.

---

## 1. ¿Qué es este diagrama?

Es una **vista de despliegue**: muestra **dónde vive cada pieza del sistema** cuando
está corriendo (en qué contenedor, en qué red) y **quién puede hablar con quién**.

No muestra el código por dentro; muestra el sistema "montado y funcionando".

---

## 2. Las cuatro franjas = las cuatro zonas (de arriba hacia abajo)

El diagrama se lee **de arriba hacia abajo**, como el camino que recorre una petición:

1. **USER ZONE (gris):** el mundo exterior. Aquí está el navegador o `curl` del
   usuario... o de un atacante. Es territorio **no confiable**.
2. **ZONA PÚBLICA / public_net (azul):** lo único expuesto a Internet. Aquí vive el
   **gateway**. Es la "puerta de entrada".
3. **ZONA DE APLICACIÓN / app_net (verde):** la lógica del sistema. Aquí vive el
   **backend**. No está expuesta al exterior.
4. **ZONA DE DATOS / data_net (roja):** lo más valioso. Aquí vive la **base de datos**.
   Es la zona más protegida.

Cada franja es una **red de Docker distinta**. Y aquí está la idea central:
**una red = una zona = un límite de confianza (trust boundary).**

---

## 3. Los tres servicios (las cajas blancas)

| Caja | Qué es | En qué redes está |
|------|--------|-------------------|
| **gateway** (borde rojo) | nginx, la puerta de entrada. Publica el puerto 80. | public_net + app_net |
| **backend** (borde verde) | la API con `/health`. El "cerebro". | app_net + data_net |
| **db** (borde verde) | PostgreSQL, guarda los datos. | solo data_net |

Fíjate en el detalle más importante:
- El **gateway** está en `public_net` y `app_net`, pero **NO** en `data_net`.
- La **db** está solo en `data_net`.
- Como **no comparten ninguna red**, el gateway **no tiene forma de llegar a la db**.
- El **backend** es el único que está en `app_net` **y** `data_net`: por eso es el
  **único puente** entre la aplicación y los datos.

El cuadrito amarillo con el "80" significa que **ese es el único puerto abierto al
exterior**. Todo lo demás está "hacia adentro".

---

## 4. Las flechas = los flujos (quién habla con quién)

### Flechas verdes/azules = PERMITIDO (la aplicación funciona)
- **C1 · Exterior → gateway (:80):** el usuario entra por la puerta pública.
- **C2 · gateway → backend (/api/ :3000):** el gateway reenvía la petición al backend.
- **C3 · backend → db (:5432):** el backend consulta la base de datos.

Estas tres flechas, en cadena, son el camino normal: un `curl localhost/api/health`
baja por C1 → C2 → C3 y vuelve con `{"status":"ok","db":"up"}`.

### Flechas rojas punteadas con ❌ = BLOQUEADO (el ataque se detiene)
- **C4 · gateway → db (:5432):** si un atacante toma el gateway e intenta saltar
  directo a la base de datos, **falla** (no comparten red). El ❌ marca justo dónde
  se corta: en el **trust boundary crítico**.
- **C5 · Exterior → db (:15432):** si alguien desde fuera intenta golpear la db,
  **falla**, porque la db no publica ningún puerto al host.

La línea roja punteada horizontal es el **límite de confianza crítico**: separa la
zona pública de la zona de datos. Ninguna flecha permitida lo cruza directamente.

---

## 5. Cómo explicarlo en 30 segundos (guion para la sustentación)

> "Esta es la vista de despliegue de nuestro sistema segmentado. Lo dividimos en
> tres zonas, cada una es una red de Docker separada: pública, aplicación y datos.
>
> El gateway es lo único expuesto a Internet; publica el puerto 80. El backend está
> en el medio y es el único que puede hablar con la base de datos. La base de datos
> está completamente aislada en su propia red, sin puertos publicados.
>
> Las flechas verdes son los flujos permitidos: el usuario entra por el gateway (C1),
> el gateway llama al backend (C2) y el backend consulta la base de datos (C3). Así
> la aplicación funciona normal.
>
> Las flechas rojas son los ataques que quedan bloqueados: si alguien compromete el
> gateway no puede llegar a la base de datos (C4), y nadie desde fuera puede
> conectarse a la base de datos directamente (C5). Eso cumple nuestro escenario de
> calidad: el 100 % de los intentos desde la zona pública hacia los datos fallan."

---

## 6. Preguntas típicas y cómo responderlas

**¿Por qué el gateway no puede llegar a la db si están en el mismo host?**
Porque en Docker dos contenedores solo se ven si comparten una red. El gateway está
en `public_net`/`app_net` y la db en `data_net`: no hay ninguna red en común, así que
ni siquiera puede resolver el nombre `db`.

**¿Y si el atacante usa la IP en vez del nombre?**
Tampoco funciona. Aunque adivine la IP de la db, no existe una ruta de red entre
`public_net` y `data_net`, así que el intento se queda en "timed out".

**¿Por qué el backend sí puede y el gateway no?**
Porque el backend está deliberadamente conectado a las dos redes (`app_net` y
`data_net`). Es el único puente autorizado. El gateway no tiene ese privilegio.

**¿Qué es `internal: true`?**
Marca una red como "sin salida a Internet". Las redes de aplicación y datos la tienen,
así que esos contenedores no pueden salir a la red externa ni ser alcanzados desde ella.

**¿Qué pasaba "antes" (sin segmentar)?**
Todo estaba en una sola red, así que C4 y C5 **sí conectaban**. Eso era el riesgo:
un atacante en el gateway llegaba directo a la base de datos. La segmentación lo corrige.

---

## 7. Notación usada (para la leyenda del PDF)

- **«container»**: un contenedor de Docker (etiquetado con el nombre del servicio).
- **«artifact»**: un archivo que se despliega o configura el nodo (nginx.conf, server.js).
- **Color del borde:** rojo = gateway (puerta pública), verde = aplicación y datos.
- **Franja de color = zona = red Docker = trust boundary.**
- **Cuadrito amarillo:** puerto publicado al host (solo el 80).
- **Flecha:** la dirección indica quién abre la conexión (cliente → servidor).
- **Flecha verde:** flujo permitido. **Flecha roja punteada con ❌:** flujo bloqueado.
