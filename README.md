# aprendo_mas

Consultas SQL del caso práctico Data Analyst Aprendo+ (datos sintéticos, 17 ago - 27 set 2026, 3 UGEL).

## Archivos (sql/)

| Archivo | Contenido |
|---|---|
| 00_vistas.sql | Vistas de limpieza: semanas, familias (persona única), int_limpia, evidencia_sem |
| 01_participacion_semanal.sql | 1.1 Tasa de participación semanal por UGEL y total |
| 02_top5_caida_grupos.sql | 1.2 Top 5 grupos con mayor caída (promedio S1-S4 vs S5-S6) |
| 03_familias_fugadas.sql | 1.3 Familias activas en S1-S4 sin evidencia en S5-S6, y su concentración por grupo |
| 04_control_calidad.sql | 1.4 Consultas de control de calidad de datos |
| caso_aprendo_consultas_consolidado.sql | Todo lo anterior en un solo script |

## Cómo ejecutarlo (SQLite)

```
sqlite3 aprendo.sqlite
.mode csv
.import --csv instituciones.csv instituciones
.import --csv grupos.csv grupos
.import --csv participantes.csv participantes
.import --csv actividades.csv actividades
.import --csv interacciones.csv interacciones
.read sql/00_vistas.sql
.mode column
.headers on
.read sql/01_participacion_semanal.sql
```

Ejecuta primero 00_vistas.sql: el resto de las consultas depende de esas vistas.
