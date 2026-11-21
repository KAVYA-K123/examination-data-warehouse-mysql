/* ============================================================================
   DATA WAREHOUSE & DATA MINING PROJECT
   Multi-dimensional data models for an EXAMINATION SYSTEM  (MySQL 8.0+)

   Three databases are created:
     1. exam_dw_star           -> STAR schema           (1 fact, denormalised dims)
     2. exam_dw_snowflake      -> SNOWFLAKE schema      (1 fact, normalised dims)
     3. exam_dw_constellation  -> FACT CONSTELLATION    (3 facts, shared dims)

   Business process : Conducting examinations and publishing results
   Grain (result)   : one row per student, per course, per exam, per attempt
   Run order        : execute this file top to bottom (needs MySQL 8.0 for
                      recursive CTEs, window functions and WITH ROLLUP).
   ============================================================================ */

SET FOREIGN_KEY_CHECKS = 0;

/* ############################################################################
   PART 1 :  STAR SCHEMA
   ############################################################################ */
DROP DATABASE IF EXISTS exam_dw_star;
CREATE DATABASE exam_dw_star CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE exam_dw_star;

-- ---------- Dimension: Date ----------
CREATE TABLE dim_date (
    date_key      INT          NOT NULL PRIMARY KEY,      -- yyyymmdd
    full_date     DATE         NOT NULL UNIQUE,
    day_of_month  TINYINT      NOT NULL,
    day_name      VARCHAR(10)  NOT NULL,
    week_of_year  TINYINT      NOT NULL,
    month_no      TINYINT      NOT NULL,
    month_name    VARCHAR(10)  NOT NULL,
    quarter_no    TINYINT      NOT NULL,
    year_no       SMALLINT     NOT NULL,
    is_weekend    TINYINT(1)   NOT NULL
) ENGINE=InnoDB;

-- ---------- Dimension: Grade (small, descriptive dimension) ----------
CREATE TABLE dim_grade (
    grade_key     TINYINT       NOT NULL PRIMARY KEY,
    grade_letter  VARCHAR(2)    NOT NULL,
    grade_points  DECIMAL(3,1)  NOT NULL,
    min_pct       DECIMAL(5,2)  NOT NULL,
    max_pct       DECIMAL(5,2)  NOT NULL,
    result_status VARCHAR(10)   NOT NULL,
    performance_band VARCHAR(20) NOT NULL
) ENGINE=InnoDB;

-- ---------- Dimension: Student (denormalised: location + programme + department) ----------
CREATE TABLE dim_student (
    student_key     INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,   -- surrogate key
    student_id      VARCHAR(10)  NOT NULL UNIQUE,                       -- business key
    student_name    VARCHAR(60)  NOT NULL,
    gender          CHAR(1)      NOT NULL,
    date_of_birth   DATE         NOT NULL,
    category        VARCHAR(10)  NOT NULL,        -- GEN / OBC / SC / ST
    admission_year  SMALLINT     NOT NULL,
    program_name    VARCHAR(50)  NOT NULL,
    department_name VARCHAR(60)  NOT NULL,
    school_name     VARCHAR(60)  NOT NULL,
    city            VARCHAR(40)  NOT NULL,
    state           VARCHAR(40)  NOT NULL,
    country         VARCHAR(40)  NOT NULL
) ENGINE=InnoDB;

-- ---------- Dimension: Course (subject) ----------
CREATE TABLE dim_course (
    course_key      INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    course_code     VARCHAR(10)  NOT NULL UNIQUE,
    course_name     VARCHAR(60)  NOT NULL,
    credits         TINYINT      NOT NULL,
    course_type     VARCHAR(10)  NOT NULL,        -- Theory / Practical
    department_name VARCHAR(60)  NOT NULL,
    school_name     VARCHAR(60)  NOT NULL
) ENGINE=InnoDB;

-- ---------- Dimension: Exam ----------
CREATE TABLE dim_exam (
    exam_key        INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    exam_code       VARCHAR(10)  NOT NULL UNIQUE,
    exam_name       VARCHAR(60)  NOT NULL,
    exam_type       VARCHAR(15)  NOT NULL,        -- Internal / External / Supplementary
    academic_year   VARCHAR(9)   NOT NULL,        -- 2025-26
    semester_no     TINYINT      NOT NULL,
    max_marks       SMALLINT     NOT NULL,
    passing_marks   SMALLINT     NOT NULL
) ENGINE=InnoDB;

-- ---------- Dimension: Examiner / Faculty ----------
CREATE TABLE dim_examiner (
    examiner_key    INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    examiner_id     VARCHAR(10)  NOT NULL UNIQUE,
    examiner_name   VARCHAR(60)  NOT NULL,
    designation     VARCHAR(30)  NOT NULL,
    department_name VARCHAR(60)  NOT NULL
) ENGINE=InnoDB;

-- ---------- FACT: Exam Result ----------
CREATE TABLE fact_exam_result (
    result_key      BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    date_key        INT          NOT NULL,
    student_key     INT          NOT NULL,
    course_key      INT          NOT NULL,
    exam_key        INT          NOT NULL,
    examiner_key    INT          NOT NULL,
    grade_key       TINYINT      NOT NULL,
    attempt_no      TINYINT      NOT NULL DEFAULT 1,      -- degenerate dimension
    marks_obtained  DECIMAL(6,2) NOT NULL,                -- additive measure
    max_marks       SMALLINT     NOT NULL,                -- additive measure
    percentage      DECIMAL(5,2) NOT NULL,                -- semi-additive (use AVG)
    pass_flag       TINYINT(1)   NOT NULL,                -- 1 = pass (sum -> pass count)
    UNIQUE KEY uq_grain (student_key, course_key, exam_key, attempt_no),
    CONSTRAINT fk_r_date  FOREIGN KEY (date_key)     REFERENCES dim_date(date_key),
    CONSTRAINT fk_r_stud  FOREIGN KEY (student_key)  REFERENCES dim_student(student_key),
    CONSTRAINT fk_r_crs   FOREIGN KEY (course_key)   REFERENCES dim_course(course_key),
    CONSTRAINT fk_r_exam  FOREIGN KEY (exam_key)     REFERENCES dim_exam(exam_key),
    CONSTRAINT fk_r_examr FOREIGN KEY (examiner_key) REFERENCES dim_examiner(examiner_key),
    CONSTRAINT fk_r_grade FOREIGN KEY (grade_key)    REFERENCES dim_grade(grade_key)
) ENGINE=InnoDB;

CREATE INDEX ix_fact_date    ON fact_exam_result(date_key);
CREATE INDEX ix_fact_course  ON fact_exam_result(course_key);
CREATE INDEX ix_fact_exam    ON fact_exam_result(exam_key);

-- ============================ SAMPLE DATA (STAR) ============================
-- Date dimension: 2025-01-01 .. 2026-12-31
INSERT INTO dim_date
WITH RECURSIVE d AS (
    SELECT DATE('2025-01-01') AS dt
    UNION ALL
    SELECT dt + INTERVAL 1 DAY FROM d WHERE dt < DATE('2026-12-31')
)
SELECT CAST(DATE_FORMAT(dt,'%Y%m%d') AS UNSIGNED), dt, DAY(dt), DAYNAME(dt), WEEK(dt,3),
       MONTH(dt), MONTHNAME(dt), QUARTER(dt), YEAR(dt), IF(DAYOFWEEK(dt) IN (1,7),1,0)
FROM d;

INSERT INTO dim_grade VALUES
(1,'O' ,10.0, 90.00,100.00,'Pass','Outstanding'),
(2,'A+', 9.0, 80.00, 89.99,'Pass','Excellent'),
(3,'A' , 8.0, 70.00, 79.99,'Pass','Very Good'),
(4,'B+', 7.0, 60.00, 69.99,'Pass','Good'),
(5,'B' , 6.0, 50.00, 59.99,'Pass','Above Average'),
(6,'C' , 5.0, 40.00, 49.99,'Pass','Average'),
(7,'F' , 0.0,  0.00, 39.99,'Fail','Fail');

INSERT INTO dim_student
(student_id, student_name, gender, date_of_birth, category, admission_year,
 program_name, department_name, school_name, city, state, country) VALUES
('S001','Aarav Sharma','M','2004-03-14','GEN',2023,'B.Tech CSE','Computer Science','School of Engineering','Hyderabad','Telangana','India'),
('S002','Diya Reddy','F','2004-07-21','OBC',2023,'B.Tech CSE','Computer Science','School of Engineering','Hyderabad','Telangana','India'),
('S003','Rohan Mehta','M','2004-01-09','GEN',2023,'B.Tech ECE','Electronics and Communication','School of Engineering','Mumbai','Maharashtra','India'),
('S004','Ananya Iyer','F','2003-11-30','GEN',2022,'B.Tech ECE','Electronics and Communication','School of Engineering','Chennai','Tamil Nadu','India'),
('S005','Karthik Rao','M','2002-05-18','SC',2022,'MBA','Business Administration','School of Management','Bengaluru','Karnataka','India'),
('S006','Fatima Khan','F','2002-09-02','OBC',2022,'MBA','Business Administration','School of Management','Hyderabad','Telangana','India'),
('S007','Vikram Singh','M','2005-02-25','GEN',2024,'B.Tech CSE','Computer Science','School of Engineering','Delhi','Delhi','India'),
('S008','Sneha Patil','F','2005-06-12','ST',2024,'B.Sc Mathematics','Mathematics','School of Sciences','Pune','Maharashtra','India');

INSERT INTO dim_course (course_code, course_name, credits, course_type, department_name, school_name) VALUES
('CS101','Database Systems',4,'Theory','Computer Science','School of Engineering'),
('CS102','Data Mining',4,'Theory','Computer Science','School of Engineering'),
('CS103','DBMS Lab',2,'Practical','Computer Science','School of Engineering'),
('EC101','Digital Electronics',3,'Theory','Electronics and Communication','School of Engineering'),
('MB101','Marketing Management',3,'Theory','Business Administration','School of Management'),
('MA101','Linear Algebra',4,'Theory','Mathematics','School of Sciences');

INSERT INTO dim_exam (exam_code, exam_name, exam_type, academic_year, semester_no, max_marks, passing_marks) VALUES
('EX01','Mid Semester Exam - Odd 2025','Internal','2025-26',5,50,20),
('EX02','End Semester Exam - Odd 2025','External','2025-26',5,100,40),
('EX03','Supplementary Exam - 2026','Supplementary','2025-26',5,100,40);

INSERT INTO dim_examiner (examiner_id, examiner_name, designation, department_name) VALUES
('E01','Dr. Suresh Kumar','Professor','Computer Science'),
('E02','Dr. Meena Nair','Associate Professor','Electronics and Communication'),
('E03','Dr. Rajesh Gupta','Assistant Professor','Business Administration'),
('E04','Dr. Lakshmi Devi','Professor','Mathematics');

-- Attempt 1 results for exams EX01 and EX02 (deterministic pseudo-marks, ~2/3 enrolment)
INSERT INTO fact_exam_result
(date_key, student_key, course_key, exam_key, examiner_key, grade_key, attempt_no,
 marks_obtained, max_marks, percentage, pass_flag)
SELECT x.date_key, x.student_key, x.course_key, x.exam_key, x.examiner_key, g.grade_key, 1,
       ROUND(x.max_marks * x.pct / 100, 2), x.max_marks, x.pct, IF(g.grade_letter = 'F', 0, 1)
FROM (
    SELECT CAST(DATE_FORMAT(DATE_ADD(CASE e.exam_key WHEN 1 THEN DATE('2025-10-13')
                                                      ELSE DATE('2025-12-08') END,
                                     INTERVAL c.course_key DAY), '%Y%m%d') AS UNSIGNED) AS date_key,
           s.student_key, c.course_key, e.exam_key,
           CASE WHEN c.course_key <= 3 THEN 1 WHEN c.course_key = 4 THEN 2
                WHEN c.course_key = 5 THEN 3 ELSE 4 END AS examiner_key,
           e.max_marks,
           ROUND(25 + MOD(s.student_key*17 + c.course_key*13 + e.exam_key*7, 71)
                    + MOD(s.student_key*c.course_key, 10)/10, 2) AS pct
    FROM dim_student s CROSS JOIN dim_course c CROSS JOIN dim_exam e
    WHERE e.exam_key IN (1,2) AND MOD(s.student_key + c.course_key, 3) <> 0
) x
JOIN dim_grade g ON x.pct BETWEEN g.min_pct AND g.max_pct;

-- Attempt 2: supplementary exam for every student who failed EX02
INSERT INTO fact_exam_result
(date_key, student_key, course_key, exam_key, examiner_key, grade_key, attempt_no,
 marks_obtained, max_marks, percentage, pass_flag)
SELECT x.date_key, x.student_key, x.course_key, 3, x.examiner_key, g.grade_key, 2,
       x.pct, 100, x.pct, IF(g.grade_letter = 'F', 0, 1)
FROM (
    SELECT CAST(DATE_FORMAT(DATE_ADD(DATE('2026-03-02'), INTERVAL f.course_key DAY),'%Y%m%d') AS UNSIGNED) AS date_key,
           f.student_key, f.course_key, f.examiner_key,
           40 + MOD(f.student_key + f.course_key*3, 35) AS pct
    FROM fact_exam_result f
    JOIN dim_grade gg ON gg.grade_key = f.grade_key
    WHERE f.exam_key = 2 AND gg.grade_letter = 'F'
) x
JOIN dim_grade g ON x.pct BETWEEN g.min_pct AND g.max_pct;

-- ====================== DATA-MINING READY FLAT VIEW =========================
-- One wide row per result: ready to export to CSV/ARFF for Weka, Python, R.
CREATE OR REPLACE VIEW vw_mining_result AS
SELECT f.result_key, st.student_id, st.gender, st.category, st.admission_year,
       st.program_name, st.department_name, st.city, st.state,
       c.course_code, c.course_name, c.credits, c.course_type,
       e.exam_type, e.academic_year, e.semester_no, f.attempt_no,
       d.month_name, d.quarter_no, d.year_no,
       f.marks_obtained, f.max_marks, f.percentage,
       g.grade_letter, g.grade_points, g.performance_band, f.pass_flag AS class_label_pass
FROM fact_exam_result f
JOIN dim_student st ON st.student_key = f.student_key
JOIN dim_course  c  ON c.course_key   = f.course_key
JOIN dim_exam    e  ON e.exam_key     = f.exam_key
JOIN dim_date    d  ON d.date_key     = f.date_key
JOIN dim_grade   g  ON g.grade_key    = f.grade_key;

-- ============================ OLAP QUERIES (STAR) ===========================
-- Q1  ROLL-UP : average % by school > department > academic year (with sub-totals)
SELECT IF(GROUPING(c.school_name),'ALL SCHOOLS',c.school_name)       AS school,
       IF(GROUPING(c.department_name),'ALL DEPTS',c.department_name) AS department,
       IF(GROUPING(e.academic_year),'ALL YEARS',e.academic_year)     AS academic_year,
       COUNT(*) AS results, ROUND(AVG(f.percentage),2) AS avg_pct,
       ROUND(100*AVG(f.pass_flag),1) AS pass_pct
FROM fact_exam_result f
JOIN dim_course c ON c.course_key = f.course_key
JOIN dim_exam   e ON e.exam_key   = f.exam_key
GROUP BY c.school_name, c.department_name, e.academic_year WITH ROLLUP;

-- Q2  DRILL-DOWN : from department to individual course, for one department
SELECT c.department_name, c.course_code, c.course_name,
       COUNT(*) AS results, ROUND(AVG(f.percentage),2) AS avg_pct, SUM(f.pass_flag) AS passed
FROM fact_exam_result f JOIN dim_course c ON c.course_key = f.course_key
WHERE c.department_name = 'Computer Science'
GROUP BY c.department_name, c.course_code, c.course_name;

-- Q3  SLICE : only the External (end-semester) exam
SELECT c.course_name, ROUND(AVG(f.percentage),2) AS avg_pct, ROUND(100*AVG(f.pass_flag),1) AS pass_pct
FROM fact_exam_result f
JOIN dim_course c ON c.course_key = f.course_key
JOIN dim_exam   e ON e.exam_key   = f.exam_key
WHERE e.exam_type = 'External'
GROUP BY c.course_name ORDER BY avg_pct DESC;

-- Q4  DICE : female students from Telangana/Maharashtra in Theory courses, External + Internal
SELECT st.state, e.exam_type, COUNT(*) AS results, ROUND(AVG(f.percentage),2) AS avg_pct
FROM fact_exam_result f
JOIN dim_student st ON st.student_key = f.student_key
JOIN dim_course  c  ON c.course_key   = f.course_key
JOIN dim_exam    e  ON e.exam_key     = f.exam_key
WHERE st.gender = 'F' AND st.state IN ('Telangana','Maharashtra')
  AND c.course_type = 'Theory' AND e.exam_type IN ('Internal','External')
GROUP BY st.state, e.exam_type;

-- Q5  PIVOT : department x exam type (average %)
SELECT c.department_name,
       ROUND(AVG(CASE WHEN e.exam_type='Internal'      THEN f.percentage END),2) AS internal_avg,
       ROUND(AVG(CASE WHEN e.exam_type='External'      THEN f.percentage END),2) AS external_avg,
       ROUND(AVG(CASE WHEN e.exam_type='Supplementary' THEN f.percentage END),2) AS supplementary_avg
FROM fact_exam_result f
JOIN dim_course c ON c.course_key = f.course_key
JOIN dim_exam   e ON e.exam_key   = f.exam_key
GROUP BY c.department_name;

-- Q6  RANKING : SGPA (credit-weighted grade points) of each student for the End-Sem exam
SELECT st.student_id, st.student_name, st.program_name,
       ROUND(SUM(g.grade_points*c.credits)/SUM(c.credits),2) AS sgpa,
       RANK() OVER (ORDER BY SUM(g.grade_points*c.credits)/SUM(c.credits) DESC) AS rank_no
FROM fact_exam_result f
JOIN dim_student st ON st.student_key = f.student_key
JOIN dim_course  c  ON c.course_key   = f.course_key
JOIN dim_exam    e  ON e.exam_key     = f.exam_key
JOIN dim_grade   g  ON g.grade_key    = f.grade_key
WHERE e.exam_code = 'EX02'
GROUP BY st.student_id, st.student_name, st.program_name;

-- Q7  Pass percentage by student category and gender
SELECT st.category, st.gender, COUNT(*) AS results, ROUND(100*AVG(f.pass_flag),1) AS pass_pct
FROM fact_exam_result f JOIN dim_student st ON st.student_key = f.student_key
GROUP BY st.category, st.gender ORDER BY st.category, st.gender;

-- Q8  Grade distribution per course
SELECT c.course_code, g.grade_letter, COUNT(*) AS students
FROM fact_exam_result f
JOIN dim_course c ON c.course_key = f.course_key
JOIN dim_grade  g ON g.grade_key  = f.grade_key
GROUP BY c.course_code, g.grade_letter ORDER BY c.course_code, MIN(g.grade_key);


/* ############################################################################
   PART 2 :  SNOWFLAKE SCHEMA  (same fact, dimensions normalised into hierarchies)
   Location : city -> state -> country
   Academic : program -> department -> school
   Time     : date -> month -> quarter -> year
   ############################################################################ */
DROP DATABASE IF EXISTS exam_dw_snowflake;
CREATE DATABASE exam_dw_snowflake CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE exam_dw_snowflake;

-- ---- Location hierarchy ----
CREATE TABLE dim_country (
    country_key  INT AUTO_INCREMENT PRIMARY KEY,
    country_name VARCHAR(40) NOT NULL UNIQUE
) ENGINE=InnoDB;
CREATE TABLE dim_state (
    state_key    INT AUTO_INCREMENT PRIMARY KEY,
    state_name   VARCHAR(40) NOT NULL,
    country_key  INT NOT NULL,
    UNIQUE KEY uq_state (state_name, country_key),
    FOREIGN KEY (country_key) REFERENCES dim_country(country_key)
) ENGINE=InnoDB;
CREATE TABLE dim_city (
    city_key     INT AUTO_INCREMENT PRIMARY KEY,
    city_name    VARCHAR(40) NOT NULL,
    state_key    INT NOT NULL,
    UNIQUE KEY uq_city (city_name, state_key),
    FOREIGN KEY (state_key) REFERENCES dim_state(state_key)
) ENGINE=InnoDB;

-- ---- Academic hierarchy ----
CREATE TABLE dim_school (
    school_key   INT AUTO_INCREMENT PRIMARY KEY,
    school_name  VARCHAR(60) NOT NULL UNIQUE
) ENGINE=InnoDB;
CREATE TABLE dim_department (
    department_key  INT AUTO_INCREMENT PRIMARY KEY,
    department_name VARCHAR(60) NOT NULL UNIQUE,
    school_key      INT NOT NULL,
    FOREIGN KEY (school_key) REFERENCES dim_school(school_key)
) ENGINE=InnoDB;
CREATE TABLE dim_program (
    program_key     INT AUTO_INCREMENT PRIMARY KEY,
    program_name    VARCHAR(50) NOT NULL UNIQUE,
    department_key  INT NOT NULL,
    FOREIGN KEY (department_key) REFERENCES dim_department(department_key)
) ENGINE=InnoDB;

-- ---- Faculty / exam look-ups ----
CREATE TABLE dim_designation (
    designation_key  INT AUTO_INCREMENT PRIMARY KEY,
    designation_name VARCHAR(30) NOT NULL UNIQUE
) ENGINE=InnoDB;
CREATE TABLE dim_exam_type (
    exam_type_key    INT AUTO_INCREMENT PRIMARY KEY,
    exam_type_name   VARCHAR(15) NOT NULL UNIQUE
) ENGINE=InnoDB;
CREATE TABLE dim_academic_year (
    academic_year_key   INT AUTO_INCREMENT PRIMARY KEY,
    academic_year_label VARCHAR(9) NOT NULL UNIQUE
) ENGINE=InnoDB;

-- ---- Time hierarchy ----
CREATE TABLE dim_year (
    year_key     SMALLINT PRIMARY KEY            -- 2025
) ENGINE=InnoDB;
CREATE TABLE dim_quarter (
    quarter_key  INT PRIMARY KEY,                -- 20253
    quarter_no   TINYINT NOT NULL,
    year_key     SMALLINT NOT NULL,
    FOREIGN KEY (year_key) REFERENCES dim_year(year_key)
) ENGINE=InnoDB;
CREATE TABLE dim_month (
    month_key    INT PRIMARY KEY,                -- 202510
    month_no     TINYINT NOT NULL,
    month_name   VARCHAR(10) NOT NULL,
    quarter_key  INT NOT NULL,
    FOREIGN KEY (quarter_key) REFERENCES dim_quarter(quarter_key)
) ENGINE=InnoDB;
CREATE TABLE dim_date (
    date_key     INT PRIMARY KEY,
    full_date    DATE NOT NULL UNIQUE,
    day_of_month TINYINT NOT NULL,
    day_name     VARCHAR(10) NOT NULL,
    week_of_year TINYINT NOT NULL,
    is_weekend   TINYINT(1) NOT NULL,
    month_key    INT NOT NULL,
    FOREIGN KEY (month_key) REFERENCES dim_month(month_key)
) ENGINE=InnoDB;

-- ---- Core dimensions (now holding only foreign keys to the outriggers) ----
CREATE TABLE dim_grade (
    grade_key     TINYINT PRIMARY KEY,
    grade_letter  VARCHAR(2) NOT NULL,
    grade_points  DECIMAL(3,1) NOT NULL,
    min_pct       DECIMAL(5,2) NOT NULL,
    max_pct       DECIMAL(5,2) NOT NULL,
    result_status VARCHAR(10) NOT NULL,
    performance_band VARCHAR(20) NOT NULL
) ENGINE=InnoDB;
CREATE TABLE dim_student (
    student_key    INT PRIMARY KEY,
    student_id     VARCHAR(10) NOT NULL UNIQUE,
    student_name   VARCHAR(60) NOT NULL,
    gender         CHAR(1) NOT NULL,
    date_of_birth  DATE NOT NULL,
    category       VARCHAR(10) NOT NULL,
    admission_year SMALLINT NOT NULL,
    program_key    INT NOT NULL,
    city_key       INT NOT NULL,
    FOREIGN KEY (program_key) REFERENCES dim_program(program_key),
    FOREIGN KEY (city_key)    REFERENCES dim_city(city_key)
) ENGINE=InnoDB;
CREATE TABLE dim_course (
    course_key     INT PRIMARY KEY,
    course_code    VARCHAR(10) NOT NULL UNIQUE,
    course_name    VARCHAR(60) NOT NULL,
    credits        TINYINT NOT NULL,
    course_type    VARCHAR(10) NOT NULL,
    department_key INT NOT NULL,
    FOREIGN KEY (department_key) REFERENCES dim_department(department_key)
) ENGINE=InnoDB;
CREATE TABLE dim_exam (
    exam_key          INT PRIMARY KEY,
    exam_code         VARCHAR(10) NOT NULL UNIQUE,
    exam_name         VARCHAR(60) NOT NULL,
    exam_type_key     INT NOT NULL,
    academic_year_key INT NOT NULL,
    semester_no       TINYINT NOT NULL,
    max_marks         SMALLINT NOT NULL,
    passing_marks     SMALLINT NOT NULL,
    FOREIGN KEY (exam_type_key)     REFERENCES dim_exam_type(exam_type_key),
    FOREIGN KEY (academic_year_key) REFERENCES dim_academic_year(academic_year_key)
) ENGINE=InnoDB;
CREATE TABLE dim_examiner (
    examiner_key    INT PRIMARY KEY,
    examiner_id     VARCHAR(10) NOT NULL UNIQUE,
    examiner_name   VARCHAR(60) NOT NULL,
    designation_key INT NOT NULL,
    department_key  INT NOT NULL,
    FOREIGN KEY (designation_key) REFERENCES dim_designation(designation_key),
    FOREIGN KEY (department_key)  REFERENCES dim_department(department_key)
) ENGINE=InnoDB;

-- ---- FACT ----
CREATE TABLE fact_exam_result (
    result_key      BIGINT PRIMARY KEY,
    date_key        INT NOT NULL,
    student_key     INT NOT NULL,
    course_key      INT NOT NULL,
    exam_key        INT NOT NULL,
    examiner_key    INT NOT NULL,
    grade_key       TINYINT NOT NULL,
    attempt_no      TINYINT NOT NULL DEFAULT 1,
    marks_obtained  DECIMAL(6,2) NOT NULL,
    max_marks       SMALLINT NOT NULL,
    percentage      DECIMAL(5,2) NOT NULL,
    pass_flag       TINYINT(1) NOT NULL,
    UNIQUE KEY uq_grain (student_key, course_key, exam_key, attempt_no),
    FOREIGN KEY (date_key)     REFERENCES dim_date(date_key),
    FOREIGN KEY (student_key)  REFERENCES dim_student(student_key),
    FOREIGN KEY (course_key)   REFERENCES dim_course(course_key),
    FOREIGN KEY (exam_key)     REFERENCES dim_exam(exam_key),
    FOREIGN KEY (examiner_key) REFERENCES dim_examiner(examiner_key),
    FOREIGN KEY (grade_key)    REFERENCES dim_grade(grade_key)
) ENGINE=InnoDB;

-- ============== ETL: load snowflake from the star schema ====================
INSERT INTO dim_country (country_name)
SELECT DISTINCT country FROM exam_dw_star.dim_student;

INSERT INTO dim_state (state_name, country_key)
SELECT DISTINCT s.state, co.country_key
FROM exam_dw_star.dim_student s JOIN dim_country co ON co.country_name = s.country;

INSERT INTO dim_city (city_name, state_key)
SELECT DISTINCT s.city, st.state_key
FROM exam_dw_star.dim_student s
JOIN dim_country co ON co.country_name = s.country
JOIN dim_state   st ON st.state_name = s.state AND st.country_key = co.country_key;

INSERT INTO dim_school (school_name)
SELECT DISTINCT school_name FROM exam_dw_star.dim_student;

INSERT INTO dim_department (department_name, school_key)
SELECT DISTINCT s.department_name, sc.school_key
FROM exam_dw_star.dim_student s JOIN dim_school sc ON sc.school_name = s.school_name;

INSERT INTO dim_program (program_name, department_key)
SELECT DISTINCT s.program_name, d.department_key
FROM exam_dw_star.dim_student s JOIN dim_department d ON d.department_name = s.department_name;

INSERT INTO dim_designation (designation_name)
SELECT DISTINCT designation FROM exam_dw_star.dim_examiner;

INSERT INTO dim_exam_type (exam_type_name)
SELECT DISTINCT exam_type FROM exam_dw_star.dim_exam;

INSERT INTO dim_academic_year (academic_year_label)
SELECT DISTINCT academic_year FROM exam_dw_star.dim_exam;

INSERT INTO dim_year    SELECT DISTINCT year_no FROM exam_dw_star.dim_date;
INSERT INTO dim_quarter SELECT DISTINCT year_no*10 + quarter_no, quarter_no, year_no FROM exam_dw_star.dim_date;
INSERT INTO dim_month   SELECT DISTINCT year_no*100 + month_no, month_no, month_name, year_no*10 + quarter_no
                        FROM exam_dw_star.dim_date;
INSERT INTO dim_date
SELECT date_key, full_date, day_of_month, day_name, week_of_year, is_weekend, year_no*100 + month_no
FROM exam_dw_star.dim_date;

INSERT INTO dim_grade SELECT * FROM exam_dw_star.dim_grade;

INSERT INTO dim_student
SELECT s.student_key, s.student_id, s.student_name, s.gender, s.date_of_birth, s.category,
       s.admission_year, p.program_key, ci.city_key
FROM exam_dw_star.dim_student s
JOIN dim_program p  ON p.program_name = s.program_name
JOIN dim_city    ci ON ci.city_name   = s.city;

INSERT INTO dim_course
SELECT c.course_key, c.course_code, c.course_name, c.credits, c.course_type, d.department_key
FROM exam_dw_star.dim_course c JOIN dim_department d ON d.department_name = c.department_name;

INSERT INTO dim_exam
SELECT e.exam_key, e.exam_code, e.exam_name, t.exam_type_key, a.academic_year_key,
       e.semester_no, e.max_marks, e.passing_marks
FROM exam_dw_star.dim_exam e
JOIN dim_exam_type     t ON t.exam_type_name = e.exam_type
JOIN dim_academic_year a ON a.academic_year_label = e.academic_year;

INSERT INTO dim_examiner
SELECT x.examiner_key, x.examiner_id, x.examiner_name, dg.designation_key, d.department_key
FROM exam_dw_star.dim_examiner x
JOIN dim_designation dg ON dg.designation_name = x.designation
JOIN dim_department  d  ON d.department_name   = x.department_name;

INSERT INTO fact_exam_result
(result_key, date_key, student_key, course_key, exam_key, examiner_key, grade_key,
 attempt_no, marks_obtained, max_marks, percentage, pass_flag)
SELECT result_key, date_key, student_key, course_key, exam_key, examiner_key, grade_key,
       attempt_no, marks_obtained, max_marks, percentage, pass_flag
FROM exam_dw_star.fact_exam_result;

-- ======================= OLAP QUERIES (SNOWFLAKE) ===========================
-- Same business questions as the star schema, but each hierarchy level needs extra joins.

-- Q1  ROLL-UP by school > department > academic year
SELECT IF(GROUPING(sc.school_name),'ALL SCHOOLS',sc.school_name)        AS school,
       IF(GROUPING(d.department_name),'ALL DEPTS',d.department_name)    AS department,
       IF(GROUPING(ay.academic_year_label),'ALL YEARS',ay.academic_year_label) AS academic_year,
       COUNT(*) AS results, ROUND(AVG(f.percentage),2) AS avg_pct
FROM fact_exam_result f
JOIN dim_course        c  ON c.course_key  = f.course_key
JOIN dim_department    d  ON d.department_key = c.department_key
JOIN dim_school        sc ON sc.school_key = d.school_key
JOIN dim_exam          e  ON e.exam_key    = f.exam_key
JOIN dim_academic_year ay ON ay.academic_year_key = e.academic_year_key
GROUP BY sc.school_name, d.department_name, ay.academic_year_label WITH ROLLUP;

-- Q2  Geographic roll-up: country > state > city (student location hierarchy)
SELECT IF(GROUPING(co.country_name),'ALL',co.country_name) AS country,
       IF(GROUPING(st.state_name),'ALL',st.state_name)     AS state,
       IF(GROUPING(ci.city_name),'ALL',ci.city_name)       AS city,
       COUNT(*) AS results, ROUND(100*AVG(f.pass_flag),1) AS pass_pct
FROM fact_exam_result f
JOIN dim_student s  ON s.student_key = f.student_key
JOIN dim_city    ci ON ci.city_key   = s.city_key
JOIN dim_state   st ON st.state_key  = ci.state_key
JOIN dim_country co ON co.country_key = st.country_key
GROUP BY co.country_name, st.state_name, ci.city_name WITH ROLLUP;

-- Q3  Time roll-up: year > quarter > month
SELECT IF(GROUPING(y.year_key),'ALL',y.year_key) AS year_no,
       IF(GROUPING(q.quarter_no),'ALL',q.quarter_no) AS quarter_no,
       IF(GROUPING(m.month_name),'ALL',m.month_name) AS month_name,
       COUNT(*) AS results, ROUND(AVG(f.percentage),2) AS avg_pct
FROM fact_exam_result f
JOIN dim_date    d ON d.date_key    = f.date_key
JOIN dim_month   m ON m.month_key   = d.month_key
JOIN dim_quarter q ON q.quarter_key = m.quarter_key
JOIN dim_year    y ON y.year_key    = q.year_key
GROUP BY y.year_key, q.quarter_no, m.month_name WITH ROLLUP;

-- Q4  Slice: External exams only, by programme
SELECT p.program_name, ROUND(AVG(f.percentage),2) AS avg_pct
FROM fact_exam_result f
JOIN dim_student   s ON s.student_key = f.student_key
JOIN dim_program   p ON p.program_key = s.program_key
JOIN dim_exam      e ON e.exam_key    = f.exam_key
JOIN dim_exam_type t ON t.exam_type_key = e.exam_type_key
WHERE t.exam_type_name = 'External'
GROUP BY p.program_name;


/* ############################################################################
   PART 3 :  FACT CONSTELLATION (GALAXY) SCHEMA
   Three fact tables share conformed dimensions:
     fact_exam_result   - marks / grades per student per course per exam
     fact_exam_schedule - hall, invigilator and attendance per exam sitting
     fact_revaluation   - re-evaluation requests and their outcome
   Shared (conformed) dims: date, student, course, exam, examiner
   Private dims         : grade (result), exam_hall (schedule)
   ############################################################################ */
DROP DATABASE IF EXISTS exam_dw_constellation;
CREATE DATABASE exam_dw_constellation CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE exam_dw_constellation;

-- Conformed dimensions (identical structure and keys as the star schema)
CREATE TABLE dim_date     LIKE exam_dw_star.dim_date;
CREATE TABLE dim_grade    LIKE exam_dw_star.dim_grade;
CREATE TABLE dim_student  LIKE exam_dw_star.dim_student;
CREATE TABLE dim_course   LIKE exam_dw_star.dim_course;
CREATE TABLE dim_exam     LIKE exam_dw_star.dim_exam;
CREATE TABLE dim_examiner LIKE exam_dw_star.dim_examiner;

INSERT INTO dim_date     SELECT * FROM exam_dw_star.dim_date;
INSERT INTO dim_grade    SELECT * FROM exam_dw_star.dim_grade;
INSERT INTO dim_student  SELECT * FROM exam_dw_star.dim_student;
INSERT INTO dim_course   SELECT * FROM exam_dw_star.dim_course;
INSERT INTO dim_exam     SELECT * FROM exam_dw_star.dim_exam;
INSERT INTO dim_examiner SELECT * FROM exam_dw_star.dim_examiner;

-- Dimension used only by the schedule fact
CREATE TABLE dim_exam_hall (
    hall_key   INT AUTO_INCREMENT PRIMARY KEY,
    hall_code  VARCHAR(10) NOT NULL UNIQUE,
    hall_name  VARCHAR(40) NOT NULL,
    building   VARCHAR(30) NOT NULL,
    floor_no   TINYINT NOT NULL,
    capacity   SMALLINT NOT NULL
) ENGINE=InnoDB;

INSERT INTO dim_exam_hall (hall_code, hall_name, building, floor_no, capacity) VALUES
('H101','Examination Hall 1','Main Block',1, 60),
('H201','Examination Hall 2','Main Block',2,120),
('H301','Seminar Hall','Academic Block',3, 80);

-- ---- FACT 1 : exam result ----
CREATE TABLE fact_exam_result (
    result_key      BIGINT PRIMARY KEY,
    date_key        INT NOT NULL,
    student_key     INT NOT NULL,
    course_key      INT NOT NULL,
    exam_key        INT NOT NULL,
    examiner_key    INT NOT NULL,
    grade_key       TINYINT NOT NULL,
    attempt_no      TINYINT NOT NULL DEFAULT 1,
    marks_obtained  DECIMAL(6,2) NOT NULL,
    max_marks       SMALLINT NOT NULL,
    percentage      DECIMAL(5,2) NOT NULL,
    pass_flag       TINYINT(1) NOT NULL,
    UNIQUE KEY uq_grain (student_key, course_key, exam_key, attempt_no),
    FOREIGN KEY (date_key)     REFERENCES dim_date(date_key),
    FOREIGN KEY (student_key)  REFERENCES dim_student(student_key),
    FOREIGN KEY (course_key)   REFERENCES dim_course(course_key),
    FOREIGN KEY (exam_key)     REFERENCES dim_exam(exam_key),
    FOREIGN KEY (examiner_key) REFERENCES dim_examiner(examiner_key),
    FOREIGN KEY (grade_key)    REFERENCES dim_grade(grade_key)
) ENGINE=InnoDB;

-- ---- FACT 2 : exam schedule / hall utilisation (grain: one course sitting in one hall) ----
CREATE TABLE fact_exam_schedule (
    schedule_key         BIGINT AUTO_INCREMENT PRIMARY KEY,
    date_key             INT NOT NULL,
    exam_key             INT NOT NULL,
    course_key           INT NOT NULL,
    hall_key             INT NOT NULL,
    invigilator_key      INT NOT NULL,          -- role-playing use of dim_examiner
    students_registered  SMALLINT NOT NULL,
    students_appeared    SMALLINT NOT NULL,
    duration_minutes     SMALLINT NOT NULL,
    hall_utilisation_pct DECIMAL(5,2) NOT NULL,
    FOREIGN KEY (date_key)        REFERENCES dim_date(date_key),
    FOREIGN KEY (exam_key)        REFERENCES dim_exam(exam_key),
    FOREIGN KEY (course_key)      REFERENCES dim_course(course_key),
    FOREIGN KEY (hall_key)        REFERENCES dim_exam_hall(hall_key),
    FOREIGN KEY (invigilator_key) REFERENCES dim_examiner(examiner_key)
) ENGINE=InnoDB;

-- ---- FACT 3 : revaluation requests (grain: one request per student per course per exam) ----
CREATE TABLE fact_revaluation (
    revaluation_key    BIGINT AUTO_INCREMENT PRIMARY KEY,
    date_key           INT NOT NULL,            -- date the request was raised
    student_key        INT NOT NULL,
    course_key         INT NOT NULL,
    exam_key           INT NOT NULL,
    examiner_key       INT NOT NULL,            -- re-evaluator
    marks_before       DECIMAL(6,2) NOT NULL,
    marks_after        DECIMAL(6,2) NOT NULL,
    marks_change       DECIMAL(6,2) NOT NULL,
    fee_paid           DECIMAL(8,2) NOT NULL,
    marks_changed_flag TINYINT(1) NOT NULL,
    FOREIGN KEY (date_key)     REFERENCES dim_date(date_key),
    FOREIGN KEY (student_key)  REFERENCES dim_student(student_key),
    FOREIGN KEY (course_key)   REFERENCES dim_course(course_key),
    FOREIGN KEY (exam_key)     REFERENCES dim_exam(exam_key),
    FOREIGN KEY (examiner_key) REFERENCES dim_examiner(examiner_key)
) ENGINE=InnoDB;

-- ======================= LOAD (CONSTELLATION) ===============================
INSERT INTO fact_exam_result
(result_key, date_key, student_key, course_key, exam_key, examiner_key, grade_key,
 attempt_no, marks_obtained, max_marks, percentage, pass_flag)
SELECT result_key, date_key, student_key, course_key, exam_key, examiner_key, grade_key,
       attempt_no, marks_obtained, max_marks, percentage, pass_flag
FROM exam_dw_star.fact_exam_result;

INSERT INTO fact_exam_schedule
(date_key, exam_key, course_key, hall_key, invigilator_key,
 students_registered, students_appeared, duration_minutes, hall_utilisation_pct)
SELECT r.date_key, r.exam_key, r.course_key, h.hall_key, r.examiner_key,
       COUNT(*) + MOD(r.course_key, 2), COUNT(*),
       IF(r.exam_key = 1, 90, 180),
       ROUND(100 * COUNT(*) / h.capacity, 2)
FROM fact_exam_result r
JOIN dim_exam_hall h ON h.hall_key = 1 + MOD(r.course_key, 3)
GROUP BY r.date_key, r.exam_key, r.course_key, h.hall_key, r.examiner_key, h.capacity;

-- students scoring 36-49.99 % in the End-Sem exam apply for re-evaluation
INSERT INTO fact_revaluation
(date_key, student_key, course_key, exam_key, examiner_key,
 marks_before, marks_after, marks_change, fee_paid, marks_changed_flag)
SELECT CAST(DATE_FORMAT(DATE_ADD(t.full_date, INTERVAL 20 DAY),'%Y%m%d') AS UNSIGNED),
       t.student_key, t.course_key, t.exam_key, t.examiner_key,
       t.marks_before, t.marks_after, t.marks_after - t.marks_before, 500.00,
       IF(t.marks_after <> t.marks_before, 1, 0)
FROM (
    SELECT r.student_key, r.course_key, r.exam_key, r.examiner_key, d.full_date,
           r.marks_obtained AS marks_before,
           LEAST(r.max_marks, r.marks_obtained + MOD(r.student_key + r.course_key, 6)) AS marks_after
    FROM fact_exam_result r JOIN dim_date d ON d.date_key = r.date_key
    WHERE r.exam_key = 2 AND r.percentage BETWEEN 36 AND 49.99
) t;

-- ===================== OLAP QUERIES (CONSTELLATION) =========================
-- Q1  DRILL-ACROSS : combine result performance with hall utilisation per course & exam
SELECT c.course_code, e.exam_code,
       res.avg_pct, res.pass_pct, sch.registered, sch.appeared, sch.avg_hall_util
FROM (SELECT course_key, exam_key,
             ROUND(AVG(percentage),2) AS avg_pct, ROUND(100*AVG(pass_flag),1) AS pass_pct
      FROM fact_exam_result GROUP BY course_key, exam_key) res
JOIN (SELECT course_key, exam_key,
             SUM(students_registered) AS registered, SUM(students_appeared) AS appeared,
             ROUND(AVG(hall_utilisation_pct),2) AS avg_hall_util
      FROM fact_exam_schedule GROUP BY course_key, exam_key) sch
  ON sch.course_key = res.course_key AND sch.exam_key = res.exam_key
JOIN dim_course c ON c.course_key = res.course_key
JOIN dim_exam   e ON e.exam_key   = res.exam_key
ORDER BY c.course_code, e.exam_code;

-- Q2  Revaluation impact per course (uses fact_revaluation + conformed dim_course)
SELECT c.course_code, c.course_name, COUNT(*) AS requests,
       SUM(v.marks_changed_flag) AS marks_changed, ROUND(AVG(v.marks_change),2) AS avg_gain,
       SUM(v.fee_paid) AS fee_collected
FROM fact_revaluation v JOIN dim_course c ON c.course_key = v.course_key
GROUP BY c.course_code, c.course_name;

-- Q3  Attendance (absentee) rate per department using the schedule fact
SELECT c.department_name,
       SUM(s.students_registered) AS registered, SUM(s.students_appeared) AS appeared,
       ROUND(100*(1 - SUM(s.students_appeared)/SUM(s.students_registered)),2) AS absent_pct
FROM fact_exam_schedule s JOIN dim_course c ON c.course_key = s.course_key
GROUP BY c.department_name;

-- Q4  Invigilator workload vs. pass rate of the courses they examined (shared dim_examiner)
SELECT x.examiner_name,
       COUNT(DISTINCT s.schedule_key) AS sittings_invigilated,
       (SELECT ROUND(100*AVG(r.pass_flag),1) FROM fact_exam_result r
         WHERE r.examiner_key = x.examiner_key) AS pass_pct_of_evaluated
FROM dim_examiner x
LEFT JOIN fact_exam_schedule s ON s.invigilator_key = x.examiner_key
GROUP BY x.examiner_key, x.examiner_name;

-- Q5  Does re-evaluation help? students raised to pass (before < 40 % <= after) in the End-Sem exam
SELECT st.student_id, c.course_code, v.marks_before, v.marks_after
FROM fact_revaluation v
JOIN dim_student st ON st.student_key = v.student_key
JOIN dim_course  c  ON c.course_key   = v.course_key
JOIN dim_exam    e  ON e.exam_key     = v.exam_key
WHERE v.marks_before < e.passing_marks AND v.marks_after >= e.passing_marks;

SET FOREIGN_KEY_CHECKS = 1;

-- ============================== SANITY CHECKS ===============================
SELECT 'star'          AS db, COUNT(*) AS fact_rows FROM exam_dw_star.fact_exam_result
UNION ALL SELECT 'snowflake',     COUNT(*) FROM exam_dw_snowflake.fact_exam_result
UNION ALL SELECT 'constellation', COUNT(*) FROM exam_dw_constellation.fact_exam_result;
