bool open_table(THD *thd, TABLE_LIST *table_list, Open_table_context *ot_ctx)
{
  TABLE *table;
  const char *key;
  uint	key_length;
  const char *alias= table_list->alias.str;
  uint flags= ot_ctx->get_flags();
  MDL_ticket *mdl_ticket;
  TABLE_SHARE *share;
  uint gts_flags;
  bool from_share= false;
#ifdef WITH_PARTITION_STORAGE_ENGINE
  int part_names_error=0;
#endif
  DBUG_ENTER("open_table");
  DBUG_ASSERT(!table_list->table);
  if (check_stack_overrun(thd, STACK_MIN_SIZE_FOR_OPEN, (uchar *)&alias))
    DBUG_RETURN(TRUE);
  if (!(flags & MYSQL_OPEN_IGNORE_KILLED) && thd->killed)
  {
    thd->send_kill_message();
    DBUG_RETURN(TRUE);
  }
  if (table_list->mdl_request.is_write_lock_request() &&
      thd->tx_read_only &&
      !(flags & (MYSQL_LOCK_LOG_TABLE | MYSQL_OPEN_HAS_MDL_LOCK)))
  {
    my_error(ER_CANT_EXECUTE_IN_READ_ONLY_TRANSACTION, MYF(0));
    DBUG_RETURN(true);
  }
  if (!table_list->db.str)
  {
    my_error(ER_NO_DB_ERROR, MYF(0));
    DBUG_RETURN(true);
  }
  key_length= get_table_def_key(table_list, &key);
  if (thd->locked_tables_mode &&
      ! (flags & MYSQL_OPEN_GET_NEW_TABLE))
  {						
    TABLE *best_table= 0;
    int best_distance= INT_MIN;
    for (table=thd->open_tables; table ; table=table->next)
    {
      if (table->s->table_cache_key.length == key_length &&
	  !memcmp(table->s->table_cache_key.str, key, key_length))
      {
        if (!my_strcasecmp(system_charset_info, table->alias.c_ptr(), alias) &&
            table->query_id != thd->query_id && 
            (thd->locked_tables_mode == LTM_LOCK_TABLES ||
             table->query_id == 0))
        {
          int distance= ((int) table->reginfo.lock_type -
                         (int) table_list->lock_type);
          if ((best_distance < 0 && distance > best_distance) ||
              (distance >= 0 && distance < best_distance))
          {
            best_distance= distance;
            best_table= table;
            if (best_distance == 0)
            {
              break;
            }
          }
        }
      }
    }
    if (best_table)
    {
      table= best_table;
      table->query_id= thd->query_id;
      table->init(thd, table_list);
      DBUG_PRINT("info",("Using locked table"));
#ifdef WITH_PARTITION_STORAGE_ENGINE
      part_names_error= set_partitions_as_used(table_list, table);
#endif
      goto reset;
    }
    if (is_locked_view(thd, table_list))
    {
      if (table_list->sequence)
      {
        my_error(ER_NOT_SEQUENCE, MYF(0), table_list->db.str, table_list->alias.str);
        DBUG_RETURN(true);
      }
      DBUG_RETURN(FALSE); 
    }
    if (thd->locked_tables_mode == LTM_PRELOCKED)
      my_error(ER_NO_SUCH_TABLE, MYF(0), table_list->db.str, table_list->alias.str);
    else
      my_error(ER_TABLE_NOT_LOCKED, MYF(0), alias);
    DBUG_RETURN(TRUE);
  }
  if (! (flags & MYSQL_OPEN_HAS_MDL_LOCK))
  {
    if (table_list->mdl_request.is_write_lock_request() &&
        ! (flags & (MYSQL_OPEN_IGNORE_GLOBAL_READ_LOCK |
                    MYSQL_OPEN_FORCE_SHARED_MDL |
                    MYSQL_OPEN_FORCE_SHARED_HIGH_PRIO_MDL |
                    MYSQL_OPEN_SKIP_SCOPED_MDL_LOCK)) &&
        ! ot_ctx->has_protection_against_grl())
    {
      MDL_request protection_request;
      MDL_deadlock_handler mdl_deadlock_handler(ot_ctx);
      if (thd->global_read_lock.can_acquire_protection())
        DBUG_RETURN(TRUE);
      protection_request.init(MDL_key::GLOBAL, "", "", MDL_INTENTION_EXCLUSIVE,
                              MDL_STATEMENT);
      thd->push_internal_handler(&mdl_deadlock_handler);
      bool result= thd->mdl_context.acquire_lock(&protection_request,
                                                 ot_ctx->get_timeout());
      thd->pop_internal_handler();
      if (result)
        DBUG_RETURN(TRUE);
      ot_ctx->set_has_protection_against_grl();
    }
    if (open_table_get_mdl_lock(thd, ot_ctx, &table_list->mdl_request,
                                flags, &mdl_ticket) ||
        mdl_ticket == NULL)
    {
      DEBUG_SYNC(thd, "before_open_table_wait_refresh");
      DBUG_RETURN(TRUE);
    }
    DEBUG_SYNC(thd, "after_open_table_mdl_shared");
  }
  else
  {
    mdl_ticket= table_list->mdl_request.ticket;
  }
  if (table_list->open_strategy == TABLE_LIST::OPEN_IF_EXISTS)
  {
    if (!ha_table_exists(thd, &table_list->db, &table_list->table_name))
      DBUG_RETURN(FALSE);
  }
  else if (table_list->open_strategy == TABLE_LIST::OPEN_STUB)
    DBUG_RETURN(FALSE);
  if (table_list->i_s_requested_object & OPEN_TABLE_ONLY)
    gts_flags= GTS_TABLE;
  else if (table_list->i_s_requested_object &  OPEN_VIEW_ONLY)
    gts_flags= GTS_VIEW;
  else
    gts_flags= GTS_TABLE | GTS_VIEW;
retry_share:
  share= tdc_acquire_share(thd, table_list, gts_flags, &table);
  if (unlikely(!share))
  {
    if (thd->is_error())
    {
      if (table_list->parent_l)
      {
        thd->clear_error();
        my_error(ER_WRONG_MRG_TABLE, MYF(0));
      }
      else if (table_list->belong_to_view)
      {
        TABLE_LIST *view= table_list->belong_to_view;
        thd->clear_error();
        my_error(ER_VIEW_INVALID, MYF(0),
                 view->view_db.str, view->view_name.str);
      }
    }
    DBUG_RETURN(TRUE);
  }
  if (share->is_view)
  {
    if (table_list->parent_l)
    {
      my_error(ER_WRONG_MRG_TABLE, MYF(0));
      goto err_lock;
    }
    if (table_list->sequence)
    {
      my_error(ER_NOT_SEQUENCE, MYF(0), table_list->db.str,
               table_list->alias.str);
      goto err_lock;
    }
    if (check_and_update_table_version(thd, table_list, share))
      goto err_lock;
    if (mysql_make_view(thd, share, table_list, false))
      goto err_lock;
    tdc_release_share(share);
    DBUG_ASSERT(table_list->view);
    DBUG_RETURN(FALSE);
  }
#ifdef WITH_WSREP
  if (!((flags & MYSQL_OPEN_IGNORE_FLUSH) ||
        (thd->wsrep_applier)))
#else
  if (!(flags & MYSQL_OPEN_IGNORE_FLUSH))
#endif
  {
    if (share->tdc->flushed)
    {
      DBUG_PRINT("info", ("Found old share version: %lld  current: %lld",
                          share->tdc->version, tdc_refresh_version()));
      if (table)
        tc_release_table(table);
      else
        tdc_release_share(share);
      MDL_deadlock_handler mdl_deadlock_handler(ot_ctx);
      bool wait_result;
      thd->push_internal_handler(&mdl_deadlock_handler);
      wait_result= tdc_wait_for_old_version(thd, table_list->db.str,
                                            table_list->table_name.str,
                                            ot_ctx->get_timeout(),
                                            mdl_ticket->get_deadlock_weight());
      thd->pop_internal_handler();
      if (wait_result)
        DBUG_RETURN(TRUE);
      goto retry_share;
    }
    if (thd->open_tables && thd->open_tables->s->tdc->flushed)
    {
      if (table)
        tc_release_table(table);
      else
        tdc_release_share(share);
      (void)ot_ctx->request_backoff_action(Open_table_context::OT_REOPEN_TABLES,
                                           NULL);
      DBUG_RETURN(TRUE);
    }
  }
  if (table)
  {
    DBUG_ASSERT(table->file != NULL);
    MYSQL_REBIND_TABLE(table->file);
#ifdef WITH_PARTITION_STORAGE_ENGINE
    part_names_error= set_partitions_as_used(table_list, table);
#endif
  }
  else
  {
    enum open_frm_error error;
    if (!(table=(TABLE*) my_malloc(sizeof(*table),MYF(MY_WME))))
      goto err_lock;
    error= open_table_from_share(thd, share, &table_list->alias,
                                 HA_OPEN_KEYFILE | HA_TRY_READ_ONLY,
                                 EXTRA_RECORD,
                                 thd->open_options, table, FALSE,
                                 IF_PARTITIONING(table_list->partition_names,0));
    if (unlikely(error))
    {
      my_free(table);
      if (error == OPEN_FRM_DISCOVER)
        (void) ot_ctx->request_backoff_action(Open_table_context::OT_DISCOVER,
                                              table_list);
      else if (share->crashed)
      {
        if (!(flags & MYSQL_OPEN_IGNORE_REPAIR))
          (void) ot_ctx->request_backoff_action(Open_table_context::OT_REPAIR,
                                                table_list);
        else
          table_list->crashed= 1;  
      }
      goto err_lock;
    }
    if (open_table_entry_fini(thd, share, table))
    {
      closefrm(table);
      my_free(table);
      goto err_lock;
    }
    tc_add_table(thd, table);
    from_share= true;
  }
  table->mdl_ticket= mdl_ticket;
  table->reginfo.lock_type=TL_READ;		
  table->init(thd, table_list);
  table->next= thd->open_tables;		
  thd->set_open_tables(table);
 reset:
  DBUG_ASSERT(table->file->pushed_cond == NULL);
  table_list->updatable= 1; 
  table_list->table= table;
  if (!from_share && table->vcol_fix_expr(thd))
    goto err_lock;
#ifdef WITH_PARTITION_STORAGE_ENGINE
  if (unlikely(table->part_info))
  {
    if (part_names_error)
    {
      table->file->print_error(part_names_error, MYF(0));
      DBUG_RETURN(true);
    }
  }
  else if (table_list->partition_names)
  {
    my_error(ER_PARTITION_CLAUSE_ON_NONPARTITIONED, MYF(0));
    DBUG_RETURN(true);
  }
#endif
  if (table_list->sequence && table->s->table_type != TABLE_TYPE_SEQUENCE)
  {
    my_error(ER_NOT_SEQUENCE, MYF(0), table_list->db.str, table_list->alias.str);
    DBUG_RETURN(true);
  }
  DBUG_RETURN(FALSE);
err_lock:
  tdc_release_share(share);
  DBUG_PRINT("exit", ("failed"));
  DBUG_RETURN(TRUE);
}