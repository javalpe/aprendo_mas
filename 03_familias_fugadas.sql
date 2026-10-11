-- Caso práctico Aprendo+ | Motor: SQLite 3 (compatible con DuckDB)
-- Requiere las vistas de sql/00_vistas.sql

-- 1.3 Familias con evidencia en >=2 semanas distintas de 1-4 y SIN evidencia en 5 ni 6
WITH hist AS (
  SELECT telefono_hash,
         COUNT(DISTINCT CASE WHEN semana BETWEEN 1 AND 4 THEN semana END) AS sem_1_4,
         MAX(semana IN (5,6)) AS activa_5_6
  FROM evidencia_sem GROUP BY telefono_hash
),
fugadas AS (
  SELECT telefono_hash FROM hist WHERE sem_1_4 >= 2 AND activa_5_6 = 0
)
SELECT 'TOTAL' AS grupo_id, '' AS ugel, COUNT(*) AS familias_fugadas,
       (SELECT COUNT(*) FROM hist WHERE sem_1_4>=2) AS base_activas_1_4,
       ROUND(100.0*COUNT(*)/(SELECT COUNT(*) FROM hist WHERE sem_1_4>=2),1) AS pct_de_base
FROM fugadas;

-- 1.3 (detalle) Concentración por grupo
WITH hist AS (
  SELECT telefono_hash,
         COUNT(DISTINCT CASE WHEN semana BETWEEN 1 AND 4 THEN semana END) AS sem_1_4,
         MAX(semana IN (5,6)) AS activa_5_6
  FROM evidencia_sem GROUP BY telefono_hash
),
base AS (SELECT * FROM hist WHERE sem_1_4 >= 2)
SELECT f.grupo_id, i.ugel, i.zona,
       COUNT(*) AS base_activas_1_4,
       SUM(b.activa_5_6 = 0) AS fugadas,
       ROUND(100.0*SUM(b.activa_5_6 = 0)/COUNT(*),1) AS pct_fuga_grupo
FROM base b
JOIN familias f ON f.telefono_hash = b.telefono_hash
JOIN grupos g ON g.grupo_id = f.grupo_id
JOIN instituciones i ON i.institucion_id = g.institucion_id
GROUP BY f.grupo_id, i.ugel, i.zona
HAVING fugadas > 0
ORDER BY fugadas DESC, pct_fuga_grupo DESC
LIMIT 10;
