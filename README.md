# Examination System Data Warehouse (MySQL)

Multi-dimensional data models for an **Examination system**, built in MySQL as three schemas:
**Star**, **Snowflake** and **Fact Constellation**. Academic project for *Data Warehouse and Data Mining*.

## Design approach (Kimball)
1. **Business process:** students taking exams and receiving results
2. **Grain:** one row per student x course x exam x attempt
3. **Dimensions:** student, course, exam, date, examiner, grade
4. **Facts:** marks obtained, max marks, percentage, pass flag (`attempt_no` is a degenerate dimension)

## The three schemas

| Schema | Database | Fact tables | Total tables | Idea |
|---|---|---|---|---|
| Star | `exam_dw_star` | 1 | 7 | Flat (denormalised) dimensions, fewest joins |
| Snowflake | `exam_dw_snowflake` | 1 | 19 | Dimensions normalised into hierarchies (city > state > country, program > department > school, date > month > quarter > year) |
| Fact Constellation | `exam_dw_constellation` | 3 | 10 | `fact_exam_result`, `fact_exam_schedule`, `fact_revaluation` sharing conformed dimensions; `dim_examiner` is role-playing (evaluator / invigilator) |

## OLAP queries included
- **Star:** roll-up (`WITH ROLLUP`), drill-down, slice, dice, pivot, ranking (`RANK() OVER`), pass % by category and gender, grade distribution
- **Snowflake:** school/department/year roll-up, country/state/city roll-up, year/quarter/month roll-up, slice by program
- **Constellation:** drill-across (results + hall utilisation), revaluation impact, absentee rate, invigilator workload vs pass rate, students raised to pass by revaluation

## How to run
1. Install MySQL 8 and MySQL Workbench.
2. Open `exam_dw_mysql.sql` in Workbench.
3. Run the whole script (Ctrl+Shift+Enter). It drops and recreates the three databases, loads sample data and ends with a row-count check (70 / 70 / 70).
4. Run `USE exam_dw_star;` (or `exam_dw_snowflake` / `exam_dw_constellation`) before the queries of that schema.

## Repository contents
- `exam_dw_mysql.sql` - full script: schemas, sample data, OLAP queries
- `diagrams/` - EER diagrams exported from MySQL Workbench (star, snowflake, constellation)

## Notes
- All data is **synthetic sample data** generated for demonstration.
- Requires MySQL 8 (uses recursive CTEs, `GROUPING()` and window functions).
