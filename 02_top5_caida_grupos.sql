-- Caso práctico Aprendo+ | Motor: SQLite 3 (compatible con DuckDB)
-- Requiere las vistas de sql/00_vistas.sql

-- 1.2 Top 5 grupos con mayor caída: promedio sem 1-4 vs promedio sem 5-6
-- Tasa de grupo-semana con la misma definición de la métrica (personas únicas)
WITH base AS (
  SELECT f.telefono_hash, f.grupo_id, s.semana
  FROM familias f JOIN semanas s ON f.fecha_alta <= s.fin_semana
),
tasa_gs AS (                          -- tasa por grupo y semana
  SELECT b.grupo_id, b.semana,
         COUNT(*) AS registradas,
         SUM(CASE WHEN e.telefono_hash IS NOT NULL THEN 1 ELSE 0 END) AS con_evid,
         100.0 * SUM(CASE WHEN e.telefono_hash IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) AS tasa
  FROM base b
  LEFT JOIN evidencia_sem e ON e.telefono_hash = b.telefono_hash AND e.semana = b.semana
  GROUP BY b.grupo_id, b.semana
),
prom AS (                             -- promedio simple de las tasas semanales
  SELECT grupo_id,
         AVG(CASE WHEN semana BETWEEN 1 AND 4 THEN tasa END) AS prom_s1_4,
         AVG(CASE WHEN semana IN (5,6)         THEN tasa END) AS prom_s5_6
  FROM tasa_gs GROUP BY grupo_id
)
SELECT p.grupo_id, i.ugel, i.zona, g.edad,
       (SELECT registradas FROM tasa_gs t WHERE t.grupo_id=p.grupo_id AND t.semana=6) AS familias,
       ROUND(prom_s1_4,1) AS prom_s1_4_pct,
       ROUND(prom_s5_6,1) AS prom_s5_6_pct,
       ROUND(prom_s1_4 - prom_s5_6,1) AS caida_pp
FROM prom p
JOIN grupos g ON g.grupo_id = p.grupo_id
JOIN instituciones i ON i.institucion_id = g.institucion_id
ORDER BY caida_pp DESC
LIMIT 5;
