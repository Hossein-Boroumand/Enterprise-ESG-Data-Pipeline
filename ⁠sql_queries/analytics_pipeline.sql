-- 1. Aggregate energy consumption and calculate total CO2 emissions per facility by fiscal quarter
WITH Quarterly_Energy_Emissions AS (
    SELECT 
        f.company_id,
        f.facility_id,
        EXTRACT(YEAR FROM e.reading_timestamp) AS fiscal_year,
        EXTRACT(QUARTER FROM e.reading_timestamp) AS fiscal_quarter,
        SUM(e.electricity_kwh) AS total_electricity_kwh,
        SUM(e.calculated_co2_emissions_kg) AS total_facility_co2_kg,
        AVG(e.renewable_energy_ratio) AS avg_renewable_mix
    FROM facilities f
    JOIN energy_consumption_logs e ON f.facility_id = e.facility_id
    GROUP BY f.company_id, f.facility_id, EXTRACT(YEAR FROM e.reading_timestamp), EXTRACT(QUARTER FROM e.reading_timestamp)
),

-- 2. Map AI/BIS adoption status to each quarter for Causal Inference treatment
AI_Status_Mapping AS (
    SELECT 
        q.company_id,
        q.facility_id,
        q.fiscal_year,
        q.fiscal_quarter,
        q.total_electricity_kwh,
        q.total_facility_co2_kg,
        q.avg_renewable_mix,
        CASE 
            WHEN ai.implementation_date IS NOT NULL AND ai.implementation_date <= CAST(q.fiscal_year  '-'  (q.fiscal_quarter * 3) || '-30' AS DATE) THEN 1
            ELSE 0
        END AS ai_treatment_status 
    FROM Quarterly_Energy_Emissions q
    LEFT JOIN bis_ai_adoption ai ON q.facility_id = ai.facility_id
),

-- 3. Integrate financial data to calculate Corporate Carbon Intensity (Emissions per Euro Revenue)
Corporate_Financial_Integration AS (
    SELECT 
        a.*,
        f.revenue_eur,
        f.operating_costs_eur,
        (SUM(a.total_facility_co2_kg) OVER(PARTITION BY a.facility_id, a.fiscal_year, a.fiscal_quarter) / f.revenue_eur) AS carbon_intensity_per_euro
    FROM AI_Status_Mapping a
    JOIN financial_metrics f ON a.company_id = f.company_id 
        AND a.fiscal_year = f.fiscal_year 
        AND a.fiscal_quarter = f.fiscal_quarter
)

-- 4. Final Output: Calculate Quarter-over-Quarter (QoQ) changes in Carbon Intensity
SELECT 
    company_id,
    facility_id,
    fiscal_year,
    fiscal_quarter,
    ai_treatment_status,
    revenue_eur,
    carbon_intensity_per_euro,
    carbon_intensity_per_euro - LAG(carbon_intensity_per_euro, 1) OVER (PARTITION BY facility_id ORDER BY fiscal_year, fiscal_quarter) AS qoq_carbon_intensity_change
FROM Corporate_Financial_Integration
ORDER BY company_id, facility_id, fiscal_year, fiscal_quarter;
