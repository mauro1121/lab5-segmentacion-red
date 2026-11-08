# Laboratorio 5 – Segmentación de red (Roles 1 y 2)

Este paquete cubre **Rol 1 (Implementación)** y **Rol 2 (Vista arquitectónica)**.

## Patrón aplicado

**Aislamiento por zonas con límites de confianza.** El sistema se divide en tres
zonas de red separadas; cada servicio vive solo en las redes que necesita.

| Servicio | Zona        | Redes                 | Puede conectarse a |
|----------|-------------|-----------------------|--------------------|
| gateway  | Pública     | public_net, app_net   | backend            |
| backend  | Aplicación  | app_net, data_net     | db                 |
| db       | Datos       | data_net              | — (nada)           |

**Clave de seguridad:** el `gateway` y la `db` **no comparten ninguna red**, así que
aunque un atacante tome el gateway, no puede alcanzar la base de datos.

## Estructura

```
lab5/
├── docker-compose.yml           # DESPUÉS: segmentado (3 redes)
├── docker-compose.before.yml    # ANTES: todo en la red por defecto
├── gateway/nginx.conf           # gateway -> proxy a backend
├── backend/                     # API con /health que consulta la db
│   ├── Dockerfile
│   ├── server.js
│   └── package.json
├── run-tests.sh                 # ejecuta las 5 pruebas
└── vista-arquitectonica.svg     # diagrama de despliegue (Rol 2)
```

## Rol 1 – Cómo levantar y verificar

```bash
cd lab5

# Escenario ANTES (sin segmentar)
docker compose -f docker-compose.before.yml up -d --build
./run-tests.sh before
docker compose -f docker-compose.before.yml down

# Escenario DESPUÉS (segmentado)
docker compose up -d --build
./run-tests.sh after        # usa docker-compose.yml
docker compose down
```

Resultado esperado de las 5 pruebas:

| # | Desde → hacia      | Antes   | Después |
|---|--------------------|---------|---------|
| 1 | Exterior → gateway | Responde| Responde|
| 2 | gateway → backend  | Responde| Responde|
| 3 | backend → db       | Conecta | Conecta |
| 4 | gateway → db       | Conecta | **Falla** |
| 5 | Exterior → db      | Conecta | **Falla** |

Las pruebas 4 y 5 son las que demuestran el patrón.

## Rol 2 – Vista arquitectónica

`vista-arquitectonica.svg` es el diagrama de despliegue. Marca:
- Las **tres zonas** (pública / aplicación / datos).
- Los **límites de confianza** (línea roja punteada = el límite crítico).
- Los **flujos permitidos** (verde, pruebas 1–3) y **bloqueados** (rojo, pruebas 4–5).

### Exportar a PNG de alta resolución
El SVG es vectorial. Para obtener un PNG nítido:
- **Navegador:** abre el `.svg` en Chrome/Firefox y usa una extensión de captura, o
- **Figma / draw.io / Illustrator:** importa el SVG y exporta a PNG @2x o 300 dpi, o
- **Línea de comandos** (en tu máquina, si tienes librsvg):
  `rsvg-convert -w 2000 vista-arquitectonica.svg -o vista-arquitectonica.png`
