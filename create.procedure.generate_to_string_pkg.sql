create or replace procedure generate_to_string_pkg(i_type_list varchar2
                                                  ,i_package_name varchar2 default 'pkg_obj_to_string'             
                                                  ,i_max_list_log_count number default null) is
  type t_String_List is table of varchar2(32767);

  e_unrecognized_type exception;
  pragma exception_init( e_unrecognized_type, -20001 );

  -- Local variables
  l_types_list t_String_List;
  l_inner_type varchar2(32767);
  l_coma       varchar2(1);
  l_temp_num   number;
  i            number;

  l_result_pkb clob;
  l_result_pks clob;

  -- List of built-in types for which methods are written manually
  l_simple_types t_String_List := t_String_List('NUMBER'
                                               ,'VARCHAR2'
                                               ,'DATE'
                                               ,'TIMESTAMP');
  -- Hand-written code for Oracle built-in data types
  lc_built_in_types_expr constant varchar2(32767) := '
  function to_string(i_obj in varchar2) return varchar2
  is
  begin
    if i_obj is null
      then return ''null'';
      else return ''''''''||i_obj||'''''''';
    end if;
  end to_string;

  function to_string(i_obj in timestamp) return varchar2
  is
  begin
    if i_obj is null then return ''null'';
    else
      return ''to_timestamp(''''''|| to_char( i_obj, ''YYYY-MM-DD HH24:MI:SS.FF'' ) || '''''','''''' || ''YYYY-MM-DD HH24:MI:SS.FF'' || '''''')'';
    end if;
  end to_string;

  function to_string(i_obj in number) return varchar2
  is
  begin
    if i_obj is null
      then return ''null'';
      else return to_char(i_obj);
    end if;
  end to_string;

  function to_string(i_obj in date) return varchar2
  is
  begin
    if i_obj is null then return ''null'';
    else
      return ''to_date(''''''|| to_char( i_obj, ''YYYY-MM-DD HH24:MI:SS'' ) || '''''','''''' || ''YYYY-MM-DD HH24:MI:SS'' || '''''')'';
    end if;
  end to_string;';

  -- Hand-written function to style the output of to_string functions
  lc_formatter_pkb_expr constant varchar2(32767) := '
  function try_to_parse(i_str in varchar2) return varchar2
  is
    v_bracket_counter number := 0;
    c_tab constant varchar2(3) := ''   '';
    l_result varchar2(4000) := '''';
    is_in_apostrophes boolean := false;
    is_special_symbol boolean := false;
    brackets_issue exception;
  begin
    for i in 1..length(i_str) loop
      case substr(i_str,i,1)
        when ''('' then
          v_bracket_counter := v_bracket_counter + 1;
          l_result := l_result || ''('';
        when '')'' then
          v_bracket_counter := v_bracket_counter - 1;
          l_result := l_result || '')'';
          if v_bracket_counter < 0 then raise brackets_issue; end if;
        when '','' then
          l_result := l_result || '','' || case when not is_in_apostrophes then chr(13) || LPAD(c_tab,v_bracket_counter*length(c_tab),c_tab) end;
        when '''''''' then
          l_result := l_result || '''''''';
          if is_in_apostrophes then
            if not is_special_symbol then
              if substr(i_str,i+1,1) = '''''''' then
                is_special_symbol := true;
              else
                is_in_apostrophes := false;
              end if;
            else
              is_special_symbol := false;
            end if;
          else
            is_in_apostrophes := true;
          end if;
        else
          l_result := l_result || substr(i_str,i,1);
      end case;
    end loop;
    return l_result;
  exception
    when others then return i_str;
  end try_to_parse;';
  lc_formatter_pks_expr constant varchar2(32767) := '  function try_to_parse(i_str in varchar2) return varchar2;';

  function is_in(i_list t_String_List, i_element varchar2) return boolean is
  begin
      if i_list is not null and i_element is not null and i_list is not empty then
          for i in i_list.first..i_list.last loop
                  if i_list(i) = i_element then
                      return true;
                  end if;
              end loop;
      end if;
      return false;
  end;

begin
  select a
    bulk collect
    into l_types_list
    from (select regexp_substr(upper(replace(i_type_list,' ')), '[^,]+', 1, level) a from dual
            connect by regexp_substr(upper(replace(i_type_list,' ')), '[^,]+', 1, level) is not null) t;
  l_result_pkb := 'create or replace package body ' || i_package_name || ' is' || chr(13) || chr(13) || chr(13)
      || lc_built_in_types_expr || chr(13) || chr(13)
      || lc_formatter_pkb_expr || chr(13) || chr(13);
  i := 1;
  while i <= l_types_list.count loop
    -- check if we know what to write in to_string function
    select count(*)
      into l_temp_num
      from user_types
     where type_name = upper(l_types_list(i));
    if l_temp_num = 0 and not is_in(l_simple_types,upper(l_types_list(i)))
      then
        raise_application_error( -20001, 'The type ' || l_types_list(i)
          || ' is not recognized as existing user type or is a built-in type without a hand-written to_string function.' );
    end if;

    l_result_pkb := l_result_pkb || '  function to_string (i_obj ' || lower(l_types_list(i)) || ') return varchar2 is' || chr(13);
    l_result_pkb := l_result_pkb || '    l_result varchar2(32767) := '''';'||chr(13);

    -- check if the type is a collection and ...
    select max(elem_type_name)
      into l_inner_type
      from user_coll_types
     where type_name = l_types_list(i);
     
    -- ... generate body of to_string function in any case
    if l_inner_type is null
      then
        l_result_pkb := l_result_pkb || '  begin'||chr(13);
        l_result_pkb := l_result_pkb || '    if i_obj is null then' || chr(13);
        l_result_pkb := l_result_pkb || '      return ''null'';' || chr(13);
        l_result_pkb := l_result_pkb || '    else' || chr(13);
        l_result_pkb := l_result_pkb || '      l_result := l_result || ''' || lower(l_types_list(i)) || '('';' || chr(13);
        l_coma := '';
        for r in (select attr_name, attr_type_name from user_type_attrs where type_name = upper(l_types_list(i)))
          loop
            l_result_pkb := l_result_pkb || '      l_result := l_result || ''' || l_coma
              || lower(r.attr_name) || '=>'' || to_string(i_obj.' || lower(r.attr_name) || ');' || chr(13);
            if not is_in(l_simple_types, upper(r.attr_type_name)) and not is_in(l_types_list, upper(r.attr_type_name))
              then
                l_types_list.extend;
                l_types_list(l_types_list.last) := r.attr_type_name;
            end if;
            l_coma := ',';
        end loop;
        l_result_pkb := l_result_pkb || '      l_result := l_result || '')'';' || chr(13);
        l_result_pkb := l_result_pkb || '    end if;' || chr(13);
        l_result_pkb := l_result_pkb || '    return l_result;' || chr(13);
        l_result_pkb := l_result_pkb || '  end to_string;' || chr(13) || chr(13);
      else
        l_result_pkb := l_result_pkb || '    l_coma varchar2(1) := '''';'||chr(13);
        l_result_pkb := l_result_pkb || '    v_counter number := 0;'||chr(13);
        l_result_pkb := l_result_pkb || '  begin'||chr(13);
        l_result_pkb := l_result_pkb || '    if i_obj is null or i_obj is empty then' || chr(13);
        l_result_pkb := l_result_pkb || '      return ''null'';' || chr(13);
        l_result_pkb := l_result_pkb || '    else' || chr(13);
        l_result_pkb := l_result_pkb || '      l_result := l_result || ''' || lower(l_types_list(i)) || '('';' || chr(13);
        l_result_pkb := l_result_pkb || '      l_coma := '''';' || chr(13);
        l_result_pkb := l_result_pkb || '      for i in 1..' || case
                                                                  when i_max_list_log_count is null
                                                                    then 'i_obj.count'
                                                                  else 'least(i_obj.count,' || to_char(i_max_list_log_count) || ')'
                                                                end ||  ' loop' || chr(13);
        l_result_pkb := l_result_pkb || '        l_result := l_result || l_coma || to_string(i_obj(i));' || chr(13);
        l_result_pkb := l_result_pkb || '      l_coma := '','';' || chr(13);
        l_result_pkb := l_result_pkb || '      end loop;' || chr(13);
        l_result_pkb := l_result_pkb || '      l_result := l_result || '')'';' || chr(13);
        l_result_pkb := l_result_pkb || '    end if;' || chr(13);
        l_result_pkb := l_result_pkb || '    return l_result;' || chr(13);
        l_result_pkb := l_result_pkb || '  end to_string;' || chr(13) || chr(13);
        if not is_in(l_types_list,upper(l_inner_type)) and not is_in(l_simple_types,upper(l_inner_type))
          then
            l_types_list.extend;
            l_types_list(l_types_list.last) := l_inner_type;
        end if;
    end if;
    i := i + 1;
  end loop;
  l_result_pkb := l_result_pkb || 'end ' || i_package_name || ';' || chr(13);
  l_types_list := l_types_list multiset union l_simple_types;
  l_result_pks := 'create or replace package ' || i_package_name || ' is' || chr(13) || chr(13)
    || lc_formatter_pks_expr || chr(13) || chr(13);
  for i in l_types_list.first..l_types_list.last
    loop
      l_result_pks := l_result_pks || '  function to_string (i_obj ' || lower(l_types_list(i)) || ') return varchar2;' || chr(13);
  end loop;
  l_result_pks := l_result_pks ||  chr(13) || 'end ' || i_package_name || ';' || chr(13);
  execute immediate l_result_pks;
  execute immediate l_result_pkb;
exception
  when e_unrecognized_type
    then
      dbms_output.put_line( sqlerrm );
end generate_to_string_pkg;
/