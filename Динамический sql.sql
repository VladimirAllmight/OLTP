SET SERVEROUTPUT ON;
--Удаление таблицы
DECLARE
    table_exists EXCEPTION;
    PRAGMA EXCEPTION_INIT(table_exists, -942);
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE employees_copy'; 
    DBMS_OUTPUT.PUT_LINE('копия таблицы copy_employees удалена.');
    EXCEPTION
        WHEN table_exists THEN
            DBMS_OUTPUT.PUT_LINE('Таблица copy_employees не существует.');
END;
/
--Создание копии таблицы
DECLARE
    table_exists EXCEPTION;
    PRAGMA EXCEPTION_INIT(table_exists, -955);
BEGIN
    EXECUTE IMMEDIATE 'CREATE TABLE employees_copy AS (select * from employees)'; 
    DBMS_OUTPUT.PUT_LINE('копия таблицы copy_employees создана.');
    EXCEPTION
        WHEN table_exists THEN
            DBMS_OUTPUT.PUT_LINE('Таблица copy_employees уже существует.');
END;
/
--Выбор первых 6 сотрудников из списка самых высокооплачиваемых
DECLARE
    v_table_name VARCHAR2(30) := 'EMPLOYEES_COPY';
    v_sql CLOB;
    TYPE t_dept_tab IS TABLE OF NUMBER;
    v_departments t_dept_tab;
    TYPE t_emp_rec IS RECORD (
        employee_id NUMBER,
        first_name  VARCHAR2(100),
        last_name   VARCHAR2(100),
        job_id      VARCHAR2(50),
        old_salary  NUMBER,
        new_salary  NUMBER
    );

    TYPE t_ref_cursor IS REF CURSOR;
    c_emp t_ref_cursor;
    r_emp t_emp_rec;

    TYPE t_updated_emp IS TABLE OF BOOLEAN INDEX BY PLS_INTEGER;
    v_updated_emp t_updated_emp;

BEGIN
    /*
      Берём ровно первые 6 сотрудников по зарплате.
      Даже если 6-й и 7-й имеют одинаковую зарплату,
      7-й не попадёт, потому что используется ROW_NUMBER().
    */
    v_sql :=
        'SELECT DISTINCT department_id
         FROM (
             SELECT department_id,
                    ROW_NUMBER() OVER (ORDER BY salary DESC, employee_id) AS rn
             FROM ' || v_table_name || '
             WHERE department_id IS NOT NULL
         )
         WHERE rn <= 6';

    EXECUTE IMMEDIATE v_sql BULK COLLECT INTO v_departments;

    DBMS_OUTPUT.PUT_LINE(
        RPAD('FIRST_NAME', 15) ||
        RPAD('LAST_NAME', 15)  ||
        RPAD('JOB_ID', 15)     ||
        LPAD('SALARY(old)', 15) ||
        LPAD('SALARY(new)', 15)
    );

    DBMS_OUTPUT.PUT_LINE(RPAD('-', 75, '-'));

    FOR i IN 1 .. v_departments.COUNT LOOP

        /*
          Для текущего отдела ищем сотрудников,
          которые занимают самую низкооплачиваемую должность
          именно в этом отделе.
        */
        v_sql :=
            'SELECT e.employee_id,
                    e.first_name,
                    e.last_name,
                    e.job_id,
                    e.salary AS old_salary,
                    ROUND(e.salary * 1.15, 2) AS new_salary
             FROM ' || v_table_name || ' e
             WHERE e.department_id = :d1
               AND e.job_id IN (
                   SELECT job_id
                   FROM ' || v_table_name || '
                   WHERE department_id = :d2
                   GROUP BY job_id
                   HAVING MIN(salary) = (
                       SELECT MIN(salary)
                       FROM ' || v_table_name || '
                       WHERE department_id = :d3
                   )
               )
             ORDER BY e.salary, e.employee_id';

        OPEN c_emp FOR v_sql
            USING v_departments(i), v_departments(i), v_departments(i);

        LOOP
            FETCH c_emp INTO r_emp;
            EXIT WHEN c_emp%NOTFOUND;

            /*
              Проверяем, не повышали ли уже этому сотруднику зарплату.
            */
            IF NOT v_updated_emp.EXISTS(r_emp.employee_id) THEN

                DBMS_OUTPUT.PUT_LINE(
                    RPAD(NVL(r_emp.first_name, ' '), 15) ||
                    RPAD(NVL(r_emp.last_name, ' '), 15)  ||
                    RPAD(NVL(r_emp.job_id, ' '), 15)     ||
                    LPAD(TO_CHAR(r_emp.old_salary, '9999990.00'), 15) ||
                    LPAD(TO_CHAR(r_emp.new_salary, '9999990.00'), 15)
                );

                /*
                  Обновляем конкретного сотрудника по EMPLOYEE_ID.
                  Поэтому один и тот же сотрудник физически не может быть
                  обновлён случайно вместе с другой группой.
                */
                EXECUTE IMMEDIATE
                    'UPDATE ' || v_table_name || '
                     SET salary = :new_salary
                     WHERE employee_id = :emp_id'
                USING r_emp.new_salary, r_emp.employee_id;

                /*
                  Запоминаем, что этому сотруднику зарплату уже повышали.
                */
                v_updated_emp(r_emp.employee_id) := TRUE;

            END IF;
        END LOOP;
        CLOSE c_emp;
    END LOOP;
    COMMIT; -- раскомментируй, если нужно сохранить изменения
END;
/

SELECT DISTINCT department_id
         FROM (
             SELECT department_id,
                    ROW_NUMBER() OVER (ORDER BY salary DESC, employee_id) AS rn
             FROM employees_copy
             WHERE department_id IS NOT NULL
         ) WHERE rn <= 6;
/