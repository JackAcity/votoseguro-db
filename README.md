# votoseguro-db — Schema Supabase

Scripts SQL para Voto Seguro 2026. Ejecutar en orden en el SQL Editor de Supabase.

## Orden de ejecución

| Archivo | Contenido |
|---|---|
| `001_schema_inicial.sql` | Tablas base + índices |
| `002_auditoria_logs.sql` | audit_log + triggers + auto updated_at |
| `003_rls_y_utilidades.sql` | RLS + vistas + funciones + etl_runs/errores |

## Tablas creadas

| Tabla | Descripción |
|---|---|
| `organizaciones_politicas` | Partidos y alianzas (fuente JNE) |
| `procesos_electorales` | Proceso 124 = Elecciones Generales Abril 2026 |
| `candidatos` | Tabla principal — un row por hoja de vida JNE |
| `hojas_vida` | JSON raw completo de la API JNE (source of truth) |
| `declaracion_ingresos` | Ingresos declarados por año |
| `educacion` | Formación académica (básica/técnica/universitaria/posgrado) |
| `experiencia_laboral` | Empleos y cargos |
| `trayectoria` | Cargos partidarios y electivos previos |
| `sentencias` | Sentencias penales y alimentarias |
| `bienes_inmuebles` | Patrimonio inmueble declarado |
| `bienes_muebles` | Vehículos y otros bienes |
| `audit_log` | Append-only: INSERT/UPDATE/DELETE en tablas críticas |
| `etl_runs` | Resumen de cada ejecución del scraper Python |
| `etl_errores` | Candidatos que fallaron — para reintento |

## Cómo usa el ETL el audit_log

El ETL Python debe setear la variable de sesión antes de cada operación:

```python
# En el cliente Supabase (postgrest) o psycopg2:
await conn.execute("SET LOCAL app.fuente = 'etl-jne'")
```

Así el trigger sabe que el cambio vino del scraper, no de una alteración manual.

## Política de retención audit_log

- UPDATE y DELETE: conservar 1 año (son sospechosos)
- INSERT de 'etl-jne': purgar después de 90 días (son cargas normales)
- Purga manual: descomentar el cron en `002_auditoria_logs.sql`

## Costo estimado Supabase Free Tier

| Recurso | Estimado | Límite Free |
|---|---|---|
| Rows totales | ~15,000 candidatos × 8 tablas ≈ 120K rows | 500MB storage |
| audit_log | ~5K rows/mes (solo mutaciones) | incluido |
| etl_runs | ~30 rows/mes | incluido |
| Queries/día | < 1,000 (sitio en crecimiento) | 50,000/día |
