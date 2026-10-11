-- Caso práctico Aprendo+ | Motor: SQLite 3 (compatible con DuckDB)
-- Requiere las vistas de sql/00_vistas.sql

-- 1.1 Tasa de participación semanal por UGEL y total
-- Numerador: familias distintas con evidencia en la semana
-- Denominador: familias distintas registradas hasta el fin de esa semana
WITH base AS (                       -- familia x semana en que ya estaba registrada
  SELECT f.telefono_hash, g.institucion_id, s.semana
  FROM familias f
  JOIN grupos g  ON g.grupo_id = f.grupo_id
  JOIN semanas s ON f.fecha_alta <= s.fin_semana
),
por_ugel AS (
  SELECT i.ugel, b.semana,
         COUNT(*) AS registradas,
         SUM(CASE WHEN e.telefono_hash IS NOT NULL THEN 1 ELSE 0 END) AS con_evidencia
  FROM base b
  JOIN instituciones i ON i.institucion_id = b.institucion_id
  LEFT JOIN evidencia_sem e ON e.telefono_hash = b.telefono_hash AND e.semana = b.semana
  GROUP BY i.ugel, b.semana
),
total AS (
  SELECT 'TOTAL' AS ugel, semana, SUM(registradas) AS registradas, SUM(con_evidencia) AS con_evidencia
  FROM por_ugel GROUP BY semana
),
todo AS (SELECT * FROM por_ugel UNION ALL SELECT * FROM total)
SELECT ugel, semana, registradas, con_evidencia,
       ROUND(100.0 * con_evidencia / registradas, 1) AS tasa_pct
FROM todo
ORDER BY CASE ugel WHEN 'TOTAL' THEN 1 ELSE 0 END, ugel, semana;
