# to_string-pkg-generator
📔 The script helps to generate a package of overloaded functions that converts an object of any type to string.

| Detail | Value |
| --- | --- |
| Language | PL/SQL |
| Object type | Procedure |
| DBMS | Oracle |
| Version DBMS| 11g |

## What is this for
I wrote this function after I ran into a situation several times when I needed to log the parameters with which users called the api of the working system. When the system encountered errors, in order to recreate the bug, I needed to transfer exactly the same values to the api. These were often objects with many fields, some of which were collections. At first, I wrote code to generate logs manually in the body of executable packages. It was quite labor intensive and at the same time rather mechanical. Now, when deploying the next build to the environment, I run the script from this repository. After that, I can use the "to_string" function for an object of any complexity when logging. And while debugging the program, I can simply copy the values stored in the logs directly into the test window of my ide.

##How to use
 1. Run the script from the file 'create.procedure.generate_to_string_pkg.sql' any way you want (for example you can copy and paste it in signed in PLSQLDeveloper window and press F5 button). It will create stored procedure 'generate_to_string_pkg' in active schema.
 2. Run new procedure with list of types you want to create to_string functions for as a parameter. You can send only parent types, child types will be added automatically (fields types of object for example or type of items in collection type).
####examples:

```plsql
begin
  generate_to_string_pkg('my_type_1,my_type_2');
end;
```
```plsql
declare
  l_type_list varchar2(32767);
begin
  select listagg(type_name,',') within group(order by type_name)
    into l_type_list
    from user_types
   where type_name like 'T!_%' escape '!';
  generate_to_string_pkg(i_type_list => l_type_list);
end;
```

##Specification
Procedure generate_to_string_pkg has three parameters

| Parameter | Type | Default | Meaning |
| --- | --- | --- | --- |
| i_type_list | varchar2 | | List of types you want create to_string() function for.
| i_package_name | varchar2 | 'pkg_obj_to_string' | Name of created package with to_string() functions. |
| i_max_list_log_count | number | null (inf.) | The maximum number of collection items to convert to string. |

## Using of created package
Package contain two functions: to_string and try_to_parse. You can use the second function for basic formatting of the output, which makes it much easier to read.
#### Example
* This example create two new user types.
* Then create package with to_string functions.
* Then create a variable of new type, fill its fields and output this variable as text in the console.
```plsql
  create type t_number_list is table of number;
  /
  create or replace type t_my_type is object
  (
    name varchar2(100),
    scores t_number_list,
    constructor function t_my_type return self as result
  );
  /
  create or replace type body t_my_type as
  constructor function t_my_type return self as result is
      begin
          return;
      end;
  end;
  /
  begin
    generate_to_string_pkg('t_my_type');
  end;
  /
  declare
    a t_my_type := t_my_type();
    b t_number_list := t_number_list();
  begin
    b.extend(2);
    b(1) := 5;
    b(2) := 3;
    a.name := 'Jack';
    a.scores := b;
    dbms_output.put_line(
      pkg_obj_to_string.try_to_parse(
        pkg_obj_to_string.to_string(a)
      )
    );
  end;
  /
```
As a result you will see in the console:
      t_my_type(name=>'Jack',
         scores=>t_number_list(5,
            3))