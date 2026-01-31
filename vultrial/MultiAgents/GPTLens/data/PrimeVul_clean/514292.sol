multi_update::initialize_tables(JOIN *join)
{
  TABLE_LIST *table_ref;
  DBUG_ENTER("initialize_tables");
  if (unlikely((thd->variables.option_bits & OPTION_SAFE_UPDATES) &&
               error_if_full_join(join)))
    DBUG_RETURN(1);
  if (join->implicit_grouping)
  {
    my_error(ER_INVALID_GROUP_FUNC_USE, MYF(0));
    DBUG_RETURN(1);
  }
  main_table=join->join_tab->table;
  table_to_update= 0;
  DBUG_ASSERT(fields->elements);
  TABLE *first_table_for_update= ((Item_field *) fields->head())->field->table;
  for (table_ref= update_tables; table_ref; table_ref= table_ref->next_local)
  {
    TABLE *table=table_ref->table;
    uint cnt= table_ref->shared;
    List<Item> temp_fields;
    ORDER     group;
    TMP_TABLE_PARAM *tmp_param;
    if (ignore)
      table->file->extra(HA_EXTRA_IGNORE_DUP_KEY);
    if (table == main_table)			
    {
      if (safe_update_on_fly(thd, join->join_tab, table_ref, all_tables))
      {
	table_to_update= table;			
        has_vers_fields= table->vers_check_update(*fields);
	continue;
      }
    }
    table->prepare_for_position();
    join->map2table[table->tablenr]->keep_current_rowid= true;
    if (table_ref->check_option && !join->select_lex->uncacheable)
    {
      SELECT_LEX_UNIT *tmp_unit;
      SELECT_LEX *sl;
      for (tmp_unit= join->select_lex->first_inner_unit();
           tmp_unit;
           tmp_unit= tmp_unit->next_unit())
      {
        for (sl= tmp_unit->first_select(); sl; sl= sl->next_select())
        {
          if (sl->master_unit()->item)
          {
            join->select_lex->uncacheable|= UNCACHEABLE_CHECKOPTION;
            goto loop_end;
          }
        }
      }
    }
loop_end:
    if (table == first_table_for_update && table_ref->check_option)
    {
      table_map unupdated_tables= table_ref->check_option->used_tables() &
                                  ~first_table_for_update->map;
      List_iterator<TABLE_LIST> ti(*leaves);
      TABLE_LIST *tbl_ref;
      while ((tbl_ref= ti++) && unupdated_tables)
      {
        if (unupdated_tables & tbl_ref->table->map)
          unupdated_tables&= ~tbl_ref->table->map;
        else
          continue;
        if (unupdated_check_opt_tables.push_back(tbl_ref->table))
          DBUG_RETURN(1);
      }
    }
    tmp_param= tmp_table_param+cnt;
    List_iterator_fast<TABLE> tbl_it(unupdated_check_opt_tables);
    TABLE *tbl= table;
    do
    {
      LEX_CSTRING field_name;
      field_name.str= tbl->alias.c_ptr();
      field_name.length= strlen(field_name.str);
      tbl->prepare_for_position();
      join->map2table[tbl->tablenr]->keep_current_rowid= true;
      Item_temptable_rowid *item=
        new (thd->mem_root) Item_temptable_rowid(tbl);
      if (!item)
         DBUG_RETURN(1);
      item->fix_fields(thd, 0);
      if (temp_fields.push_back(item, thd->mem_root))
        DBUG_RETURN(1);
    } while ((tbl= tbl_it++));
    temp_fields.append(fields_for_table[cnt]);
    bzero((char*) &group, sizeof(group));
    group.direction= ORDER::ORDER_ASC;
    group.item= (Item**) temp_fields.head_ref();
    tmp_param->quick_group= 1;
    tmp_param->field_count= temp_fields.elements;
    tmp_param->func_count=  temp_fields.elements - 1;
    calc_group_buffer(tmp_param, &group);
    my_bool save_big_tables= thd->variables.big_tables; 
    thd->variables.big_tables= FALSE;
    tmp_tables[cnt]=create_tmp_table(thd, tmp_param, temp_fields,
                                     (ORDER*) &group, 0, 0,
                                     TMP_TABLE_ALL_COLUMNS, HA_POS_ERROR, &empty_clex_str);
    thd->variables.big_tables= save_big_tables;
    if (!tmp_tables[cnt])
      DBUG_RETURN(1);
    tmp_tables[cnt]->file->extra(HA_EXTRA_WRITE_CACHE);
  }
  join->tmp_table_keep_current_rowid= TRUE;
  DBUG_RETURN(0);
}