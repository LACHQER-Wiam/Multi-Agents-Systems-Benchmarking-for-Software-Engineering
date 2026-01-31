int btrfs_rm_device(struct btrfs_fs_info *fs_info, const char *device_path,
		    u64 devid)
{
	struct btrfs_device *device;
	struct btrfs_fs_devices *cur_devices;
	struct btrfs_fs_devices *fs_devices = fs_info->fs_devices;
	u64 num_devices;
	int ret = 0;
	mutex_lock(&uuid_mutex);
	num_devices = btrfs_num_devices(fs_info);
	ret = btrfs_check_raid_min_devices(fs_info, num_devices - 1);
	if (ret)
		goto out;
	device = btrfs_find_device_by_devspec(fs_info, devid, device_path);
	if (IS_ERR(device)) {
		if (PTR_ERR(device) == -ENOENT &&
		    strcmp(device_path, "missing") == 0)
			ret = BTRFS_ERROR_DEV_MISSING_NOT_FOUND;
		else
			ret = PTR_ERR(device);
		goto out;
	}
	if (btrfs_pinned_by_swapfile(fs_info, device)) {
		btrfs_warn_in_rcu(fs_info,
		  "cannot remove device %s (devid %llu) due to active swapfile",
				  rcu_str_deref(device->name), device->devid);
		ret = -ETXTBSY;
		goto out;
	}
	if (test_bit(BTRFS_DEV_STATE_REPLACE_TGT, &device->dev_state)) {
		ret = BTRFS_ERROR_DEV_TGT_REPLACE;
		goto out;
	}
	if (test_bit(BTRFS_DEV_STATE_WRITEABLE, &device->dev_state) &&
	    fs_info->fs_devices->rw_devices == 1) {
		ret = BTRFS_ERROR_DEV_ONLY_WRITABLE;
		goto out;
	}
	if (test_bit(BTRFS_DEV_STATE_WRITEABLE, &device->dev_state)) {
		mutex_lock(&fs_info->chunk_mutex);
		list_del_init(&device->dev_alloc_list);
		device->fs_devices->rw_devices--;
		mutex_unlock(&fs_info->chunk_mutex);
	}
	mutex_unlock(&uuid_mutex);
	ret = btrfs_shrink_device(device, 0);
	if (!ret)
		btrfs_reada_remove_dev(device);
	mutex_lock(&uuid_mutex);
	if (ret)
		goto error_undo;
	ret = btrfs_rm_dev_item(device);
	if (ret)
		goto error_undo;
	clear_bit(BTRFS_DEV_STATE_IN_FS_METADATA, &device->dev_state);
	btrfs_scrub_cancel_dev(device);
	cur_devices = device->fs_devices;
	mutex_lock(&fs_devices->device_list_mutex);
	list_del_rcu(&device->dev_list);
	cur_devices->num_devices--;
	cur_devices->total_devices--;
	if (cur_devices != fs_devices)
		fs_devices->total_devices--;
	if (test_bit(BTRFS_DEV_STATE_MISSING, &device->dev_state))
		cur_devices->missing_devices--;
	btrfs_assign_next_active_device(device, NULL);
	if (device->bdev) {
		cur_devices->open_devices--;
		btrfs_sysfs_remove_device(device);
	}
	num_devices = btrfs_super_num_devices(fs_info->super_copy) - 1;
	btrfs_set_super_num_devices(fs_info->super_copy, num_devices);
	mutex_unlock(&fs_devices->device_list_mutex);
	if (test_bit(BTRFS_DEV_STATE_WRITEABLE, &device->dev_state))
		btrfs_scratch_superblocks(fs_info, device->bdev,
					  device->name->str);
	btrfs_close_bdev(device);
	synchronize_rcu();
	btrfs_free_device(device);
	if (cur_devices->open_devices == 0) {
		list_del_init(&cur_devices->seed_list);
		close_fs_devices(cur_devices);
		free_fs_devices(cur_devices);
	}
out:
	mutex_unlock(&uuid_mutex);
	return ret;
error_undo:
	btrfs_reada_undo_remove_dev(device);
	if (test_bit(BTRFS_DEV_STATE_WRITEABLE, &device->dev_state)) {
		mutex_lock(&fs_info->chunk_mutex);
		list_add(&device->dev_alloc_list,
			 &fs_devices->alloc_list);
		device->fs_devices->rw_devices++;
		mutex_unlock(&fs_info->chunk_mutex);
	}
	goto out;
}