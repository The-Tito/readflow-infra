# Readflow — Infraestructura

Repositorio de infraestructura del proyecto Readflow. Contiene la configuración de Docker, base de datos y servidor proxy para levantar el entorno de desarrollo local completo.

## Estructura

```
readflow-infrastructure/
├── docker-compose.yml     ← Orquestación de servicios
├── .env.example           ← Variables de entorno requeridas
├── database/
│   ├── init.sql           ← Schema completo de la BD
│   └── seed.sql           ← Datos iniciales (catálogos)
├── nginx/
│   └── nginx.conf         ← Configuración del reverse proxy
└── README.md
```

## Requisitos

- Docker Desktop instalado
- Repositorio `readflow-backend` clonado en la misma carpeta padre

```
proyectos/
├── readflow-infra/   ← este repo
├── readflow-backend/
└── readflow-frontend/
```

## Levantar el entorno local

**1. Clonar el repositorio**

```bash
git clone https://github.com/tu-org/readflow-infrastructure.git
cd readflow-infrastructure
```

**2. Configurar variables de entorno**

```bash
cp .env.example .env
# Editar .env con tus valores reales
```

**3. Levantar los servicios**

```bash
docker compose up -d
```

Esto levanta:

- PostgreSQL en `localhost:5432`
- API en `localhost:3333`
- Nginx en `localhost:80`

**4. Verificar que todo está corriendo**

```bash
curl http://localhost/health
# Respuesta esperada: {"status":"ok","env":"development"}
```

## Servicios

| Servicio   | Puerto | Descripción                        |
| ---------- | ------ | ---------------------------------- |
| PostgreSQL | 5432   | Base de datos                      |
| API        | 3333   | Backend (acceso directo)           |
| Nginx      | 80     | Reverse proxy (acceso recomendado) |

## Comandos útiles

```bash
# Ver logs de todos los servicios
docker compose logs -f

# Ver logs de un servicio específico
docker compose logs -f api

# Detener todos los servicios
docker compose down

# Detener y eliminar volúmenes (resetea la BD)
docker compose down -v

# Reconstruir la imagen del backend
docker compose build api
```

## Variables de entorno

| Variable          | Descripción                | Requerida |
| ----------------- | -------------------------- | --------- |
| POSTGRES_USER     | Usuario de PostgreSQL      | ✅        |
| POSTGRES_PASSWORD | Password de PostgreSQL     | ✅        |
| POSTGRES_DB       | Nombre de la base de datos | ✅        |
| JWT_SECRET        | Secreto para firmar JWT    | ✅        |
| JWT_EXPIRES_IN    | Duración del access token  | ✅        |
| GEMINI_API_KEY    | API key de Google Gemini   | ✅        |
| RESEND_API_KEY    | API key de Resend          | ✅        |
| FROM_EMAIL        | Email remitente            | ✅        |
| APP_URL           | URL del frontend           | ✅        |

## Producción

En producción la infraestructura está desplegada en:

| Servicio      | Plataforma | URL                                    |
| ------------- | ---------- | -------------------------------------- |
| API           | Render     | https://readflow-api-xq2p.onrender.com |
| Base de datos | Supabase   | PostgreSQL administrado                |
| Emails        | Resend     | no-reply@readflow.lat                  |
